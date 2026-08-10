#version 300 es
precision highp float;

in vec2 v_texcoord;
layout(location = 0) out vec4 fragColor;

uniform sampler2D tex;

// Optical softness plus a few panel imperfections, for a green phosphor
// console rendered on a real LCD. Deliberately no CRT geometry, scan raster,
// concentric vignette, curvature, phosphor persistence, animated noise, or
// colour separation: those all announce a retro shader. The guiding rule is
// that broad irregular fields read as hardware while fine per-pixel texture
// reads as a filter, so every defect here is static and spatially large.
//
// Three things this deliberately does NOT do, each removed after measuring:
//
//   Raised black floor. It was the one uniform effect, which made it
//   equivalent to editing `background` in home/palettes.nix — no shader can
//   add what a palette rung cannot. It also compressed the dark ladder:
//   lifting the floor toward `raisedBlack` shrank the gap that keeps an
//   ANSI-black selected row visible, from 2.25x to 1.77x at only +2%.
//
//   Vertical column banding. Real column-driver nonuniformity is a smooth
//   sub-percent ripple, but this background sits about ten levels above
//   black, so any band quantises to a hard one-level step: measured as a
//   202 px (31 mm) stripe one level brighter than its neighbours, with a
//   30 px edge, running the full height of the screen. It is also the only
//   effect that structurally cannot avoid the reading area.
//
//   LCD ghosting. Not implementable: a Hyprland screen shader receives only
//   the current frame, with no history buffer.
//
// The backlight falloff added below is not the vignette that was rejected. The
// rejected one was concentric and centred, which is the shape no panel has and
// every photo filter does. This one is an edge-lit backlight deficit: three
// unequal sources with unequal reach, none of them centred, none of them
// mirrored by a partner on the opposite side, with their boundary bent by the
// same kind of noise field as the mura. It is also multiplicative, so it scales
// every local contrast *ratio* by the same factor rather than shifting levels;
// that is the property the raised black floor lacked, and it is why the floor
// compressed the dark ladder while this does not.

// Optics. The kernel below is normalised, so on a flat field soft == base and
// both of these contribute exactly nothing; they act only near glyph edges.
const float DIFFUSION_STRENGTH = 0.160;
const float BLOOM_STRENGTH = 0.580;

// Panel imperfections. The panel is meant to read as visibly tired: the uneven
// edge light and the dark far corner are both noticed without looking for them,
// and the clouding sits just under that.
//
// The bleed is additive and so it does compress the dark ladder where it is
// strongest, which is the one property the raised black floor was rejected for.
// Measured on a field of ANSI-black blocks over the background, ANSI black
// against background falls from 2.24x unshaded to 2.06x mid-screen and 1.64x in
// the brightest bleed corner. What the floor could not do and this does is keep
// the absolute separation: the gap stays 8.5 of 255 against 8.93 unshaded, and
// the worst of it is confined to two corners instead of the whole screen.
const float BACKLIGHT_BLEED = 0.070;
const float MURA_STRENGTH = 0.020;
const float WASH_STRENGTH = 0.450;

// Peak fraction of light lost in the corner furthest from the edge strip.
// Applied to the whole frame, not gated to dark content, because a backlight
// deficit dims emitted light regardless of what is being displayed; gating it
// would have made it a tint over the background instead of a dim panel. It
// scales R, G and B together, so glyph hue is untouched by construction.
const float EDGE_FALLOFF = 0.300;

// Colour-temperature nonuniformity rides on the panel's own emission, where it
// cannot disturb the hue of lit text; only a token fraction gains the
// transmitted image. Tinting the whole frame instead pulled green glyphs
// toward yellow on whichever side was warm — measured at a 6.5% loss of green
// purity on glyph cores, which this palette must not pay.
const float TEMP_ON_PANEL = 0.450;
const float TEMP_ON_IMAGE = 0.012;

// A weak diagonal viewing-angle wash: dim lit pixels slightly and lift only
// the dark field, preserving the centre while the top-right loses contrast.
const float OFF_AXIS_CONTRAST = 0.030;
const float OFF_AXIS_BLACK_LIFT = 0.006;
const vec3 OFF_AXIS_TINT = vec3(1.00, 0.96, 0.88);

// How far a washed-out patch pulls colour toward its own luminance. The earlier
// 0.080 ceiling existed because the wash was applied at full strength to lit
// text and greyed it at 0.30. It is now scaled by WASH_TEXT_SHARE on lit
// content, so the value below is what dark background receives; glyph cores see
// 0.220 * 0.35 = 0.077, marginally less than the old ungated 0.080.
const float WASH_DESATURATION = 0.220;
const float WASH_TEXT_SHARE = 0.350;

// Edge light tint. Follows the phosphor rather than a fixed warm constant, the
// way the palette's own dark rungs do. If the active profile in
// home/palettes.nix ever changes hue, this wants changing with it.
const vec3 BLEED_TINT = vec3(0.72, 1.00, 0.80);

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float valueNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Two octaves sampled in screen space, not pixel space. The low octave sets
// two to five broad regions across the panel; the high one only bends their
// borders so they do not read as a tidy grid of blobs. An earlier version
// hashed 3 px cells instead, which is the fine-grain failure mode: it carried
// five times this one's high-frequency energy and a fifth less of its
// large-scale structure.
float panelField(vec2 uv, vec2 offset) {
    return valueNoise(uv * vec2(2.6, 1.7) + offset) * 0.72
        + valueNoise(uv * vec2(5.3, 3.1) + offset * 1.7) * 0.28;
}

void main() {
    vec2 uv = v_texcoord;
    vec2 pixel = 1.0 / vec2(textureSize(tex, 0));
    vec4 base = texture(tex, uv);
    vec2 x = vec2(pixel.x, 0.0);
    vec2 y = vec2(0.0, pixel.y);

    // Radius-one footprint, weights summing to one. All of the energy sits on
    // the immediate ring, so glyph edges soften without the glyph interior
    // going out of focus and without the wide halo that reads as neon rather
    // than as optics.
    vec3 soft = base.rgb * 0.20;
    soft += (texture(tex, uv + x).rgb + texture(tex, uv - x).rgb
        + texture(tex, uv + y).rgb + texture(tex, uv - y).rgb) * 0.14;
    soft += (texture(tex, uv + x + y).rgb + texture(tex, uv + x - y).rgb
        + texture(tex, uv - x + y).rgb + texture(tex, uv - x - y).rgb) * 0.06;

    vec3 diffused = mix(base.rgb, soft, DIFFUSION_STRENGTH);

    // Gate the glow on local brightness so muted text barely glows while the
    // cursor and bold text do.
    float peak = max(max(soft.r, soft.g), soft.b);
    float glowGate = smoothstep(0.05, 0.25, peak);
    vec3 bloom = max(soft - base.rgb, vec3(0.0)) * BLOOM_STRENGTH * glowGate;
    vec3 color = diffused + bloom;

    // Gate the additive panel imperfections to dark content so lit surfaces
    // keep their colour and only the large flat background reveals the panel.
    // The backlight falloff below is the one effect deliberately outside this
    // gate, because it removes light rather than adding it.
    float luminance = dot(color, LUMA);
    float darkness = pow(1.0 - clamp(luminance, 0.0, 1.0), 2.0);

    // Colour temperature runs warm on the left, cool on the right, with the
    // bottom-left corner aged a touch further so the axis is not a clean
    // linear ramp.
    float tempAxis = (uv.x - 0.5) * 2.0;
    float aged = (1.0 - smoothstep(0.0, 0.85, distance(uv, vec2(0.0, 1.0)))) * 0.35;
    float warmth = -tempAxis * 0.5 + aged;
    vec3 tempShift = vec3(warmth, 0.0, -warmth);

    // Asymmetric edge light from three unequal sources, no radial symmetry.
    // Two sit at the bottom corners and one is a bezel leak at the top right;
    // all three contribute exactly zero at the centre of the screen.
    float lowerLeft = 1.0 - smoothstep(0.0, 0.62, distance(uv, vec2(0.06, 1.03)));
    float lowerRight = 1.0 - smoothstep(0.0, 0.48, distance(uv, vec2(0.94, 1.04)));
    float upperRight = 1.0 - smoothstep(0.0, 0.38, distance(uv, vec2(1.02, 0.02)));
    float bleedMask = lowerLeft * 0.75 + lowerRight + upperRight * 0.35;
    bleedMask *= mix(0.88, 1.12, panelField(uv, vec2(17.3, 9.1)));
    vec3 panelBleed = (BLEED_TINT + tempShift * TEMP_ON_PANEL)
        * BACKLIGHT_BLEED * bleedMask * darkness;

    // Backlight deficit, the counterpart of the bleed above. All three bleed
    // sources sit on or near the bottom edge, so the strip is read as running
    // along the bottom and the light runs out going up and to the left: a wide
    // weak loss over the top-left corner, a narrower one along the top edge
    // right of centre, and a mild one at the middle of the left edge. Nothing
    // is placed at the top-right, where the bezel leak already is. The noise
    // term bends the boundary so no edge of the shadow is a clean arc, and
    // every source runs out before the middle of the screen: at uv (0.5, 0.5)
    // all three are exactly zero, so the reading area is untouched.
    float darkTopLeft = 1.0 - smoothstep(0.0, 0.66, distance(uv, vec2(-0.08, -0.06)));
    float darkTopEdge = 1.0 - smoothstep(0.0, 0.40, distance(uv, vec2(0.72, -0.10)));
    float darkLeftEdge = 1.0 - smoothstep(0.0, 0.34, distance(uv, vec2(-0.04, 0.58)));
    float falloffMask = darkTopLeft + darkTopEdge * 0.62 + darkLeftEdge * 0.45;
    falloffMask *= 0.70 + 0.60 * panelField(uv, vec2(8.2, 5.6));
    color *= 1.0 - EDGE_FALLOFF * clamp(falloffMask, 0.0, 1.25);

    // Mura as a handful of broad irregular clouds rather than grain.
    float mura = (panelField(uv, vec2(1.7, 4.3)) - 0.5) * MURA_STRENGTH * darkness;

    color += panelBleed + vec3(mura);
    color *= 1.0 + tempShift * TEMP_ON_IMAGE;

    // Viewing-angle loss favors the right and top. A decorrelated broad field
    // bends the diagonal boundary without turning it into visible texture.
    float offAxisWarp = panelField(uv, vec2(13.7, 2.4)) - 0.5;
    float rightWash = smoothstep(0.28, 1.02, uv.x + offAxisWarp * 0.06);
    float topWash = 1.0 - smoothstep(-0.08, 0.72, uv.y + offAxisWarp * 0.04);
    float offAxis = clamp(rightWash * (0.35 + topWash * 0.65), 0.0, 1.0);
    color *= 1.0 - OFF_AXIS_CONTRAST * offAxis;
    color += OFF_AXIS_TINT * OFF_AXIS_BLACK_LIFT * offAxis * darkness;

    // Local contrast loss: a couple of patches that read slightly washed out,
    // on a field decorrelated from the mura above. The offset is not
    // arbitrary — the original one put the strongest patch as a tall streak
    // straight down the middle of the screen, at 0.89 of the panel's worst,
    // directly under the reading area. This one leaves the centre third at
    // 0.13 and moves the patches to the bottom-right and top edges, where the
    // edge light already is.
    float wash = smoothstep(0.55, 0.85, panelField(uv, vec2(2.9, 11.4)))
        * WASH_STRENGTH;
    float washDesat = WASH_DESATURATION * mix(WASH_TEXT_SHARE, 1.0, darkness);
    vec3 washed = mix(color, vec3(dot(color, LUMA)), washDesat);
    color = mix(color, washed, wash);

    fragColor = vec4(clamp(color, 0.0, 1.0), base.a);
}
