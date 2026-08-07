#version 300 es
precision highp float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;

// A restrained optical-softness treatment for a modern LCD. This deliberately
// contains no CRT geometry, scan raster, vignette, animated noise, or color
// separation.
const float DIFFUSION_STRENGTH = 0.080;
const float BLOOM_STRENGTH = 0.220;
const float BLACK_LIFT = 0.010;
const float BACKLIGHT_BLEED = 0.018;
const float MURA_STRENGTH = 0.004;

float panelNoise(vec2 position) {
    vec2 cell = floor(position / 3.0);
    return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

void main() {
    vec2 uv = v_texcoord;
    vec2 pixel = 1.0 / vec2(textureSize(tex, 0));
    vec4 base = texture(tex, uv);
    vec2 x = vec2(pixel.x, 0.0);
    vec2 y = vec2(0.0, pixel.y);

    // A deliberately assertive two-pixel Gaussian-like footprint. It stays
    // spatially uniform, so the result can still read as imperfect panel
    // optics rather than simulated tube geometry.
    vec3 soft = base.rgb * 0.16;
    soft += texture(tex, uv + x).rgb * 0.10;
    soft += texture(tex, uv - x).rgb * 0.10;
    soft += texture(tex, uv + y).rgb * 0.10;
    soft += texture(tex, uv - y).rgb * 0.10;
    soft += texture(tex, uv + x + y).rgb * 0.06;
    soft += texture(tex, uv + x - y).rgb * 0.06;
    soft += texture(tex, uv - x + y).rgb * 0.06;
    soft += texture(tex, uv - x - y).rgb * 0.06;
    soft += texture(tex, uv + 2.0 * x).rgb * 0.05;
    soft += texture(tex, uv - 2.0 * x).rgb * 0.05;
    soft += texture(tex, uv + 2.0 * y).rgb * 0.05;
    soft += texture(tex, uv - 2.0 * y).rgb * 0.05;

    vec3 diffused = mix(base.rgb, soft, DIFFUSION_STRENGTH);
    vec3 bloom = max(soft - base.rgb, vec3(0.0));
    vec3 color = diffused + bloom * BLOOM_STRENGTH;

    // A low-quality LCD can have a raised black floor and uneven edge light.
    // Gate both to dark content so normal bright surfaces retain their color.
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float darkness = pow(1.0 - clamp(luminance, 0.0, 1.0), 2.0);
    vec3 warmBlack = vec3(1.0, 0.72, 0.34) * BLACK_LIFT * darkness;

    float lowerLeft = 1.0 - smoothstep(0.0, 0.62, distance(uv, vec2(0.06, 1.03)));
    float lowerRight = 1.0 - smoothstep(0.0, 0.48, distance(uv, vec2(0.94, 1.04)));
    float upperRight = 1.0 - smoothstep(0.0, 0.38, distance(uv, vec2(1.02, 0.02)));
    float bleedMask = lowerLeft * 0.75 + lowerRight + upperRight * 0.35;
    vec3 panelBleed = vec3(1.0, 0.82, 0.55)
        * BACKLIGHT_BLEED * bleedMask * darkness;

    // Static, low-amplitude panel mura rather than animated signal noise.
    float mura = (panelNoise(gl_FragCoord.xy) - 0.5)
        * MURA_STRENGTH * darkness;

    color += warmBlack + panelBleed + vec3(mura);

    fragColor = vec4(clamp(color, 0.0, 1.0), base.a);
}
