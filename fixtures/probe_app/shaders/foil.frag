#version 460 core
// Foil for a headline: diagonal sheen bands over a tint, drifting with scene
// time. The comments on the uniforms are what the studio's inspector reads.
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uColor;
uniform float uTime;
uniform float uAngle; // @range 0 6.283 @default 0.6
uniform float uSpeed; // @range 0 2 @default 0.35
uniform vec3 uShine; // @color @default 1 0.92 0.6

out vec4 fragColor;

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 dir = vec2(cos(uAngle), sin(uAngle));
  float phase = dot(frag / max(uSize.y, 1.0), dir) * 3.0 - uTime * uSpeed * 6.2831853;
  float sheen = pow(0.5 + 0.5 * sin(phase), 6.0);
  vec3 base = uColor.rgb * (0.75 + 0.25 * frag.y / max(uSize.y, 1.0));
  vec3 c = mix(base, uShine, sheen);
  fragColor = vec4(c * uColor.a, uColor.a);
}
