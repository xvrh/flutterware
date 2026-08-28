#ifndef RUNNER_EMBEDDER_TEXTURE_PLUGIN_H_
#define RUNNER_EMBEDDER_TEXTURE_PLUGIN_H_

#include <flutter_linux/flutter_linux.h>

// Serves `flutterware/embedder_texture` — the channel `EmbeddedEngine` uses to
// turn the guest's ring of surfaces into something a `Texture` widget can show.
// The macOS half of this is `macos/Runner/EmbedderTexturePlugin.swift`; the two
// answer the same four methods and differ only in what a ring slot is.
void fw_embedder_texture_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

#endif  // RUNNER_EMBEDDER_TEXTURE_PLUGIN_H_
