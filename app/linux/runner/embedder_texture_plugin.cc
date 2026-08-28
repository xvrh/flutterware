#include "embedder_texture_plugin.h"

#include "crash_report.h"

#include <epoxy/gl.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstdint>
#include <cstdlib>

// Must match SURFACE_RING_COUNT in `native/surface.h`. The guest sends the
// count with every announcement, so a mismatch is caught rather than assumed —
// this is the cap on what will be mapped, not a second declaration of the
// truth.
#define FW_RING_COUNT 3

G_DECLARE_FINAL_TYPE(FwEmbedderTexture,
                     fw_embedder_texture,
                     FW,
                     EMBEDDER_TEXTURE,
                     FlTextureGL)

// One ring of the guest's shared-memory slots, shown to Flutter as a texture.
//
// Where macOS wraps the guest's IOSurface as a CVPixelBuffer and lets the
// compositor read it in place, this frame has already been copied once — the
// guest's `glReadPixels` — and is uploaded from the mapping here. Both copies
// go away together, with a dmabuf imported straight into `populate`, and
// neither before then; the findings doc has why.
//
// `FlTextureGL` rather than the `FlPixelBufferTexture` this obviously wants to
// be, because doing the upload ourselves is what a dmabuf import needs anyway
// and there is nothing to be gained from the class that hands the engine a
// pointer instead.
struct _FwEmbedderTexture {
  FlTextureGL parent_instance;

  // Written by the platform thread on a remap, read by the raster thread in
  // populate. Everything below it is under this.
  GMutex mutex;

  uint8_t* slots[FW_RING_COUNT];
  size_t mapped_size;
  uint32_t width;
  uint32_t height;
  int current;

  // Our GL texture, in Flutter's context, and the size it was last allocated
  // at. A name is reused frame to frame — the engine caches by name, so
  // changing it every frame would throw that cache away — but never across a
  // resize; see [fw_embedder_texture_populate].
  GLuint name;
  uint32_t name_width;
  uint32_t name_height;
};

// GL names waiting to be deleted, and the lock over them.
//
// **Per plugin rather than per texture, because the owner does not outlive the
// name.** A name can only be freed with Flutter's GL context current, and
// `populate` is the only place that ever holds it — so a name given up by a
// texture that is being disposed has nobody left to free it, and every closed
// panel stranded a full-size RGBA texture in the driver. Parked here instead,
// and deleted by whichever texture paints next.
//
// Names given up by the last texture in the process wait for a panel that may
// never open. That is the one leak this does not close, and it ends with the
// GL context, which ends with the process.
static GMutex fw_dead_names_lock;
static GArray* fw_dead_names;

// Hands a name over to be deleted at the next paint. Zero is not a name.
static void fw_retire_gl_name(GLuint name) {
  if (name == 0) return;
  g_mutex_lock(&fw_dead_names_lock);
  if (fw_dead_names == nullptr) {
    fw_dead_names = g_array_new(FALSE, FALSE, sizeof(GLuint));
  }
  g_array_append_val(fw_dead_names, name);
  g_mutex_unlock(&fw_dead_names_lock);
}

// Deletes everything parked. The caller holds Flutter's GL context.
static void fw_delete_retired_gl_names() {
  g_mutex_lock(&fw_dead_names_lock);
  if (fw_dead_names != nullptr && fw_dead_names->len > 0) {
    glDeleteTextures(fw_dead_names->len,
                     &g_array_index(fw_dead_names, GLuint, 0));
    g_array_set_size(fw_dead_names, 0);
  }
  g_mutex_unlock(&fw_dead_names_lock);
}

G_DEFINE_TYPE(FwEmbedderTexture, fw_embedder_texture, fl_texture_gl_get_type())

// Drops the current mapping. The caller holds the mutex.
//
// Safe to do the moment a ring is replaced, and that is a property of
// [fw_embedder_texture_populate] rather than luck: the upload happens inside
// the lock and `glTexImage2D` has consumed the client memory by the time it
// returns, so no mapping is ever reachable by the engine after this call.
static void fw_embedder_texture_unmap(FwEmbedderTexture* self) {
  for (int i = 0; i < FW_RING_COUNT; i++) {
    if (self->slots[i] != nullptr) {
      munmap(self->slots[i], self->mapped_size);
      self->slots[i] = nullptr;
    }
  }
  self->mapped_size = 0;
}

// Maps the named shared-memory objects, replacing whatever was mapped before.
//
// Nothing is swapped in until every slot has mapped, so a ring that fails
// half-way leaves the previous one showing rather than a torn mixture of two.
static gboolean fw_embedder_texture_map(FwEmbedderTexture* self,
                                        FlValue* surfaces,
                                        uint32_t width,
                                        uint32_t height,
                                        uint32_t row_bytes) {
  if (fl_value_get_type(surfaces) != FL_VALUE_TYPE_LIST) return FALSE;
  size_t count = fl_value_get_length(surfaces);
  if (count != FW_RING_COUNT) return FALSE;
  // An FlPixelBufferTexture has nowhere to put a stride: it hands the engine a
  // pointer and a size, and the engine reads width*4 per row. The GL guest
  // allocates exactly that, so a mismatch means the ring came from somewhere
  // this cannot show rather than something to paper over.
  if (width == 0 || height == 0 || row_bytes != width * 4) return FALSE;

  size_t size = static_cast<size_t>(row_bytes) * height;
  uint8_t* fresh[FW_RING_COUNT] = {nullptr, nullptr, nullptr};
  gboolean ok = TRUE;
  for (size_t i = 0; i < count && ok; i++) {
    FlValue* handle = fl_value_get_list_value(surfaces, i);
    if (fl_value_get_type(handle) != FL_VALUE_TYPE_STRING) {
      ok = FALSE;
      break;
    }
    int fd = shm_open(fl_value_get_string(handle), O_RDONLY, 0);
    if (fd < 0) {
      ok = FALSE;
      break;
    }
    void* base = mmap(nullptr, size, PROT_READ, MAP_SHARED, fd, 0);
    // The mapping holds the object open, so the descriptor has nothing left to
    // do and the pixels survive the name going away — which they are about to,
    // just below.
    close(fd);
    if (base == MAP_FAILED) {
      ok = FALSE;
      break;
    }
    fresh[i] = static_cast<uint8_t*>(base);
  }
  if (!ok) {
    for (size_t i = 0; i < count; i++) {
      if (fresh[i] != nullptr) munmap(fresh[i], size);
    }
    return FALSE;
  }

  fw_embedder_texture_unmap(self);
  // **Unlinked the moment they are mapped.** A mapping holds the object open,
  // so the pixels outlive the name — and the name is what must not outlive the
  // guest. `/dev/shm` keeps an entry until somebody unlinks it, the guest is
  // stopped with a signal it does not handle, and a guest that crashes never
  // gets the chance either: every panel that closed left its ring behind,
  // ~11MB at 800x600, until the machine was rebooted. This is the one point at
  // which both halves are provably done with the name — the guest has
  // published it, this has it mapped — so it is where the name goes. The
  // guest's own `shm_unlink` a generation later then finds nothing, which is
  // exactly what it wants to find.
  for (size_t i = 0; i < count; i++) {
    shm_unlink(fl_value_get_string(fl_value_get_list_value(surfaces, i)));
    self->slots[i] = fresh[i];
  }
  self->mapped_size = size;
  self->width = width;
  self->height = height;
  self->current = 0;
  return TRUE;
}

// Called on the raster thread, with Flutter's own GL context current — which
// is what makes uploading here legal and is where a dmabuf import would go when
// this stops copying at all.
//
// **Not an `FlPixelBufferTexture`, which is a preference after all.** That
// class was ruled out while a segfault was being chased through this file, and
// the segfault turned out to be elsewhere entirely — a `toImage` over the
// external texture, see the findings doc. What is left is the reason to keep
// this one: doing the upload here is what a dmabuf import needs anyway, and
// there is nothing to be gained from the class that hands the engine a
// pointer instead.
static gboolean fw_embedder_texture_populate(FlTextureGL* texture,
                                             uint32_t* target,
                                             uint32_t* name,
                                             uint32_t* width,
                                             uint32_t* height,
                                             GError** error) {
  FwEmbedderTexture* self = FW_EMBEDDER_TEXTURE(texture);
  // Names given up by an earlier resize, or by a texture that has since been
  // disposed. Deleted here rather than where they were given up because this is
  // the only place with Flutter's GL context current — and outside this
  // texture's lock, because the list belongs to every texture.
  fw_delete_retired_gl_names();
  g_mutex_lock(&self->mutex);
  const uint8_t* pixels = self->slots[self->current];
  uint32_t mapped_width = self->width;
  uint32_t mapped_height = self->height;

  if (pixels == nullptr) {
    g_mutex_unlock(&self->mutex);
    g_set_error(error, g_quark_from_static_string("flutterware"), 0,
                "the embedder ring is not mapped");
    return FALSE;
  }

  // A resize gets a *new* name rather than a `glTexImage2D` at a new size on
  // the old one. The engine wraps what we hand it and keeps that wrapper, and
  // nothing in the contract says a name may change dimensions underneath it —
  // reallocating one the compositor still holds is a hazard on its own terms.
  // It was not the resize crash — that was a `toImage`, and the findings doc
  // has it — so this is care rather than a fix.
  if (self->name != 0 && (self->name_width != mapped_width ||
                          self->name_height != mapped_height)) {
    fw_retire_gl_name(self->name);
    self->name = 0;
  }
  if (self->name == 0) {
    glGenTextures(1, &self->name);
    glBindTexture(GL_TEXTURE_2D, self->name);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  } else {
    glBindTexture(GL_TEXTURE_2D, self->name);
  }
  self->name_width = mapped_width;
  self->name_height = mapped_height;
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, mapped_width, mapped_height, 0,
               GL_RGBA, GL_UNSIGNED_BYTE, pixels);
  g_mutex_unlock(&self->mutex);

  fw_crash_note(mapped_width, mapped_height, self->name, self->current);
  *target = GL_TEXTURE_2D;
  *name = self->name;
  *width = mapped_width;
  *height = mapped_height;
  return TRUE;
}

// GObject allows dispose to run more than once, so everything here is written
// to survive that, and the mutex is cleared in finalize instead — which runs
// exactly once. Clearing it here is how a second dispose comes to lock a mutex
// that no longer exists.
static void fw_embedder_texture_dispose(GObject* object) {
  FwEmbedderTexture* self = FW_EMBEDDER_TEXTURE(object);
  g_mutex_lock(&self->mutex);
  fw_embedder_texture_unmap(self);
  // The platform thread holds no GL context, so the name is parked rather than
  // deleted — see [fw_retire_gl_name].
  fw_retire_gl_name(self->name);
  self->name = 0;
  g_mutex_unlock(&self->mutex);
  G_OBJECT_CLASS(fw_embedder_texture_parent_class)->dispose(object);
}

static void fw_embedder_texture_finalize(GObject* object) {
  FwEmbedderTexture* self = FW_EMBEDDER_TEXTURE(object);
  g_mutex_clear(&self->mutex);
  G_OBJECT_CLASS(fw_embedder_texture_parent_class)->finalize(object);
}

static void fw_embedder_texture_class_init(FwEmbedderTextureClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = fw_embedder_texture_dispose;
  G_OBJECT_CLASS(klass)->finalize = fw_embedder_texture_finalize;
  FL_TEXTURE_GL_CLASS(klass)->populate = fw_embedder_texture_populate;
}

static void fw_embedder_texture_init(FwEmbedderTexture* self) {
  g_mutex_init(&self->mutex);
}

G_DECLARE_FINAL_TYPE(FwEmbedderTexturePlugin,
                     fw_embedder_texture_plugin,
                     FW,
                     EMBEDDER_TEXTURE_PLUGIN,
                     GObject)

// The plugin: one method channel, and every ring it has been asked to show.
struct _FwEmbedderTexturePlugin {
  GObject parent_instance;
  FlMethodChannel* channel;
  FlTextureRegistrar* textures;
  // int64 texture id -> FwEmbedderTexture, owned. A texture id is issued by the
  // registrar and is what Dart names a ring by afterwards.
  GHashTable* by_id;
};

G_DEFINE_TYPE(FwEmbedderTexturePlugin,
              fw_embedder_texture_plugin,
              g_object_get_type())

static FwEmbedderTexture* lookup(FwEmbedderTexturePlugin* self, FlValue* args) {
  FlValue* value = fl_value_lookup_string(args, "textureId");
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return nullptr;
  }
  int64_t id = fl_value_get_int(value);
  return static_cast<FwEmbedderTexture*>(g_hash_table_lookup(self->by_id, &id));
}

// The geometry that comes with every ring announcement. Zero for anything
// missing, which the mapping then refuses.
static uint32_t arg_uint(FlValue* args, const char* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return 0;
  }
  int64_t number = fl_value_get_int(value);
  return number > 0 ? static_cast<uint32_t>(number) : 0;
}

static FlMethodResponse* error_response(const char* code, const char* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new(code, message, nullptr));
}

static FlMethodResponse* handle_create(FwEmbedderTexturePlugin* self,
                                       FlValue* args) {
  FlValue* surfaces = fl_value_lookup_string(args, "surfaces");
  if (surfaces == nullptr) {
    return error_response("bad_args", "surfaces required");
  }
  FwEmbedderTexture* texture = FW_EMBEDDER_TEXTURE(
      g_object_new(fw_embedder_texture_get_type(), nullptr));
  if (!fw_embedder_texture_map(texture, surfaces, arg_uint(args, "width"),
                               arg_uint(args, "height"),
                               arg_uint(args, "rowBytes"))) {
    g_object_unref(texture);
    return error_response("map_failed",
                          "could not map the guest's shared memory ring");
  }
  if (!fl_texture_registrar_register_texture(self->textures,
                                             FL_TEXTURE(texture))) {
    g_object_unref(texture);
    return error_response("register_failed", "could not register the texture");
  }
  int64_t id = fl_texture_get_id(FL_TEXTURE(texture));
  int64_t* key = g_new(int64_t, 1);
  *key = id;
  g_hash_table_insert(self->by_id, key, texture);
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_int(id)));
}

static FlMethodResponse* handle_update(FwEmbedderTexturePlugin* self,
                                       FlValue* args) {
  FwEmbedderTexture* texture = lookup(self, args);
  FlValue* surfaces = fl_value_lookup_string(args, "surfaces");
  if (texture == nullptr || surfaces == nullptr) {
    return error_response("bad_args", "unknown texture");
  }
  g_mutex_lock(&texture->mutex);
  gboolean ok = fw_embedder_texture_map(texture, surfaces,
                                        arg_uint(args, "width"),
                                        arg_uint(args, "height"),
                                        arg_uint(args, "rowBytes"));
  g_mutex_unlock(&texture->mutex);
  if (!ok) {
    // The previous ring is still mapped and still showing, so the panel freezes
    // at its old size rather than going blank. Worth naming: nothing about that
    // state looks like a failure from anywhere else.
    g_warning("[embedder_texture] could not map the ring; the panel is holding "
              "its previous frame");
  }
  return FL_METHOD_RESPONSE(
      fl_method_success_response_new(fl_value_new_bool(ok)));
}

static FlMethodResponse* handle_mark_frame(FwEmbedderTexturePlugin* self,
                                           FlValue* args) {
  FwEmbedderTexture* texture = lookup(self, args);
  FlValue* index = fl_value_lookup_string(args, "ringIndex");
  if (texture == nullptr || index == nullptr ||
      fl_value_get_type(index) != FL_VALUE_TYPE_INT) {
    return error_response("bad_args", "unknown texture");
  }
  int64_t slot = fl_value_get_int(index);
  g_mutex_lock(&texture->mutex);
  if (slot >= 0 && slot < FW_RING_COUNT && texture->slots[slot] != nullptr) {
    texture->current = static_cast<int>(slot);
  }
  g_mutex_unlock(&texture->mutex);
  fl_texture_registrar_mark_texture_frame_available(self->textures,
                                                    FL_TEXTURE(texture));
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
}

static FlMethodResponse* handle_dispose(FwEmbedderTexturePlugin* self,
                                        FlValue* args) {
  FwEmbedderTexture* texture = lookup(self, args);
  if (texture != nullptr) {
    fl_texture_registrar_unregister_texture(self->textures,
                                            FL_TEXTURE(texture));
    int64_t id = fl_texture_get_id(FL_TEXTURE(texture));
    g_hash_table_remove(self->by_id, &id);
  }
  return FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_null()));
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  FwEmbedderTexturePlugin* self =
      static_cast<FwEmbedderTexturePlugin*>(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    args = fl_value_new_map();
  } else {
    fl_value_ref(args);
  }

  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(method, "createTexture") == 0) {
    response = handle_create(self, args);
  } else if (g_strcmp0(method, "updateSurfaces") == 0) {
    response = handle_update(self, args);
  } else if (g_strcmp0(method, "markFrameAvailable") == 0) {
    response = handle_mark_frame(self, args);
  } else if (g_strcmp0(method, "disposeTexture") == 0) {
    response = handle_dispose(self, args);
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_value_unref(args);

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("[embedder_texture] failed to respond: %s", error->message);
  }
}

static void fw_embedder_texture_plugin_dispose(GObject* object) {
  FwEmbedderTexturePlugin* self = FW_EMBEDDER_TEXTURE_PLUGIN(object);
  g_clear_pointer(&self->by_id, g_hash_table_unref);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(fw_embedder_texture_plugin_parent_class)->dispose(object);
}

static void fw_embedder_texture_plugin_class_init(
    FwEmbedderTexturePluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = fw_embedder_texture_plugin_dispose;
}

static void fw_embedder_texture_plugin_init(FwEmbedderTexturePlugin* self) {
  self->by_id = g_hash_table_new_full(g_int64_hash, g_int64_equal, g_free,
                                      g_object_unref);
}

void fw_embedder_texture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  FwEmbedderTexturePlugin* plugin = FW_EMBEDDER_TEXTURE_PLUGIN(
      g_object_new(fw_embedder_texture_plugin_get_type(), nullptr));
  plugin->textures = fl_plugin_registrar_get_texture_registrar(registrar);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  plugin->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "flutterware/embedder_texture", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      plugin->channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
