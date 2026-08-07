#version 300 es
precision highp float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;

const float BLOOM_STRENGTH = 0.055;
const float SCANLINE_STRENGTH = 0.000;
const float VIGNETTE_STRENGTH = 0.050;
const float CURVATURE = 0.000;

void main() {
    vec2 p = v_texcoord * 2.0 - 1.0;
    float r2 = dot(p, p);
    p *= 1.0 + CURVATURE * r2;
    vec2 uv = p * 0.5 + 0.5;

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(8.0 / 255.0, 7.0 / 255.0, 5.0 / 255.0, 1.0);
        return;
    }

    vec2 pixel = 1.0 / vec2(textureSize(tex, 0));
    vec4 base = texture(tex, uv);
    vec3 bloom = vec3(0.0);
    bloom += texture(tex, uv + vec2(pixel.x, 0.0)).rgb;
    bloom += texture(tex, uv - vec2(pixel.x, 0.0)).rgb;
    bloom += texture(tex, uv + vec2(0.0, pixel.y)).rgb;
    bloom += texture(tex, uv - vec2(0.0, pixel.y)).rgb;
    bloom *= 0.25;

    float luminance = dot(base.rgb, vec3(0.2126, 0.7152, 0.0722));
    vec3 color = base.rgb + bloom * luminance * BLOOM_STRENGTH;

    float scanline = 1.0 - SCANLINE_STRENGTH
        * (0.5 + 0.5 * sin(uv.y / pixel.y * 3.14159265));
    color *= scanline;

    float vignette = 1.0 - VIGNETTE_STRENGTH * smoothstep(0.2, 1.35, r2);
    color *= vignette;

    fragColor = vec4(color, base.a);
}
