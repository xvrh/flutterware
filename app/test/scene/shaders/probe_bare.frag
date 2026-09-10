#version 460 core
#include <flutter/runtime_effect.glsl>

uniform float uSize;
uniform vec3 uTint;

out vec4 fragColor;

void main() {
  fragColor = vec4(uTint * clamp(uSize, 1.0, 1.0), 1.0);
}
