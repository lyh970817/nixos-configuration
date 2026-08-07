#version 300 es
precision highp float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;

// A restrained optical-softness treatment for a modern LCD. This deliberately
// contains no CRT geometry, scan raster, vignette, noise, or color separation.
const float DIFFUSION_STRENGTH = 0.025;
const float BLOOM_STRENGTH = 0.070;

void main() {
    vec2 uv = v_texcoord;
    vec2 pixel = 1.0 / vec2(textureSize(tex, 0));
    vec4 base = texture(tex, uv);
    vec2 x = vec2(pixel.x, 0.0);
    vec2 y = vec2(0.0, pixel.y);

    // Compact Gaussian-like kernel: enough to take the digital edge off the
    // panel without making text look defocused.
    vec3 soft = base.rgb * 0.24;
    soft += texture(tex, uv + x).rgb * 0.12;
    soft += texture(tex, uv - x).rgb * 0.12;
    soft += texture(tex, uv + y).rgb * 0.12;
    soft += texture(tex, uv - y).rgb * 0.12;
    soft += texture(tex, uv + x + y).rgb * 0.07;
    soft += texture(tex, uv + x - y).rgb * 0.07;
    soft += texture(tex, uv - x + y).rgb * 0.07;
    soft += texture(tex, uv - x - y).rgb * 0.07;

    vec3 diffused = mix(base.rgb, soft, DIFFUSION_STRENGTH);
    vec3 bloom = max(soft - base.rgb, vec3(0.0));
    vec3 color = diffused + bloom * BLOOM_STRENGTH;

    fragColor = vec4(clamp(color, 0.0, 1.0), base.a);
}
