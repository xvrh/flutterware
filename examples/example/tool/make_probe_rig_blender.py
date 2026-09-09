# The third 3D probe's fixture, through Blender's own glTF exporter.
#
# `make_probe_rig_glb.dart` writes the same rig by hand and can only confirm
# our own assumptions. This builds it in Blender — Z-up, its default plane,
# its default UVs, an action named `Open` — and lets the exporter decide how
# names, axes, UVs and clips come out. That output is what a modeller's file
# looks like, and the walk test over it is what makes the surface convention
# real. Run headless, from `examples/example`:
#
#     /Applications/Blender.app/Contents/MacOS/Blender --background \
#         --python tool/make_probe_rig_blender.py
#
# Conventions this relies on, and which the test checks:
#   * an object's name becomes the glTF node's name (`Screen` is found by it);
#   * Blender -Y is glTF +Z, so a plane facing -Y here faces the viewer there;
#   * the exporter flips V, so Blender's default plane UVs land top-left;
#   * with the default animation export mode, an action's name is the clip's.
import math
import os

import bpy

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = 24


def material(name, rgba, roughness=0.5, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def box(name, size, location, mat):
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.name = name
    obj.scale = size
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat)
    return obj


# Body: 0.78 wide (X), 1.6 tall (Z), 0.08 deep (Y).
body = box("Body", (0.78, 0.08, 1.6), (0, 0, 0), material("BodyMat", (0.06, 0.06, 0.07, 1), 0.6))

# Screen: Blender's default plane faces +Z; turned to face -Y it faces the
# viewer after export. A hair in front of the body's front face.
bpy.ops.mesh.primitive_plane_add(size=1, location=(0, -0.041, 0))
screen = bpy.context.active_object
screen.name = "Screen"
screen.data.name = "Screen"
screen.rotation_euler = (math.pi / 2, 0, 0)
screen.scale = (0.69, 1.5, 1)
bpy.ops.object.transform_apply(rotation=True, scale=True)
screen.data.materials.append(material("ScreenMat", (1, 1, 1, 1), 1.0, 0.0))

# Lid: a flap whose origin is its hinge on the body's top front edge, so the
# clip is a rotation about the hinge.
lid = box("Lid", (0.78, 0.02, 0.3), (0, -0.05, 0.65), material("LidMat", (0.8, 0.2, 0.1, 1), 0.5))
scene.cursor.location = (0, -0.05, 0.8)
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")

# The clip: `Open`, 0° → 90° about X over two seconds at 24fps. Linear keys
# by preference, since Blender 5's layered actions moved the curves off the
# action.
bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"
lid.rotation_mode = "XYZ"
lid.animation_data_create()
action = bpy.data.actions.new("Open")
lid.animation_data.action = action
for frame, angle in ((1, 0.0), (25, math.pi / 4), (49, math.pi / 2)):
    lid.rotation_euler = (angle, 0, 0)
    lid.keyframe_insert(data_path="rotation_euler", frame=frame)
scene.frame_start = 1
scene.frame_end = 49

out = os.path.join(os.getcwd(), "assets", "models", "probe_rig_blender.glb")
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    export_apply=True,
    export_animations=True,
    export_yup=True,
)
print("wrote", out, os.path.getsize(out), "bytes")
