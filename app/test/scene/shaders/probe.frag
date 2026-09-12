#version 460 core
// A shader whose output names the uniform under test, so a pixel test can
// read a uniform back as a colour. uMode picks what is shown.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uColor;
uniform float uTime;
uniform vec3 uTint;
uniform float uMode;

out vec4 fragColor;

void main() {
  vec2 p = FlutterFragCoord().xy / uSize;
  if (uMode < 0.5) {
    fragColor = vec4(uTint, 1.0);                         // 0: the author's tint
  } else if (uMode < 1.5) {
    fragColor = vec4(fract(uTime), 0.0, 0.0, 1.0);        // 1: scene seconds
  } else if (uMode < 2.5) {
    fragColor = vec4(clamp(p.x, 0.0, 1.0), 0.0, 0.0, 1.0); // 2: where x sits in the box
  } else {
    fragColor = vec4(uColor.rgb, 1.0);                    // 3: the text's own colour
  }
}
