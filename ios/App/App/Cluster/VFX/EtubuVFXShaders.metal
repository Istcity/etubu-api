#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

/// Cutout / Dynamic Island FX — SwiftUI stitchable Metal library.
/// Applied as distortion / layer / color effects around the camera hole.

// MARK: - Heat shimmer (ateş / yanardağ / patlama)

[[ stitchable ]] float2 etubu_heat_distortion(
    float2 position,
    float time,
    float intensity,
    float2 size
) {
    float2 uv = position / max(size, float2(1.0));
    float amp = clamp(intensity, 0.0, 1.5) * 3.2;
    float2 warp = float2(
        sin(uv.y * 36.0 + time * 6.2) * cos(uv.x * 14.0 + time * 2.1),
        cos(uv.x * 30.0 - time * 5.4) * sin(uv.y * 12.0 + time * 1.7)
    ) * amp;
    // Soft falloff toward edges so Island rim stays readable
    float2 c = uv - 0.5;
    float rim = smoothstep(0.72, 0.18, length(c * float2(1.15, 1.55)));
    return position + warp * rim;
}

[[ stitchable ]] half4 etubu_heat_layer(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float intensity
) {
    float amp = clamp(intensity, 0.0, 1.5) * 2.8;
    float2 warp = float2(
        sin(position.y * 0.09 + time * 6.0),
        cos(position.x * 0.08 - time * 5.0)
    ) * amp;
    half4 sample = layer.sample(position + warp);
    // Warm refraction tint on distorted samples
    half warm = half(0.12 * intensity);
    sample.rgb = mix(sample.rgb, sample.rgb * half3(1.12, 0.92, 0.72), warm);
    return sample;
}

// MARK: - Electric / plasma chromatic pulse

[[ stitchable ]] half4 etubu_electric_tint(
    float2 position,
    half4 color,
    float time,
    float intensity
) {
    float pulse = 0.5 + 0.5 * sin(time * 9.0 + position.x * 0.04);
    float flicker = 0.5 + 0.5 * sin(time * 27.0 + position.y * 0.07);
    half3 cyan = half3(0.45h, 0.85h, 1.0h);
    half3 violet = half3(0.55h, 0.25h, 1.0h);
    half3 tint = mix(cyan, violet, half(flicker));
    half mixAmt = half(0.22 * intensity * (0.55 + 0.45 * pulse));
    half3 rgb = mix(color.rgb, tint, mixAmt);
    // Core hot-white flash
    rgb += half3(0.18h) * half(pulse * intensity * flicker);
    return half4(rgb, color.a);
}

[[ stitchable ]] float2 etubu_electric_jitter(
    float2 position,
    float time,
    float intensity,
    float2 size
) {
    float2 uv = position / max(size, float2(1.0));
    float amp = clamp(intensity, 0.0, 1.5) * 1.6;
    float jx = sin(time * 42.0 + uv.y * 50.0) * amp;
    float jy = cos(time * 38.0 + uv.x * 40.0) * amp * 0.55;
    float2 c = uv - 0.5;
    float rim = smoothstep(0.7, 0.2, length(c * float2(1.1, 1.5)));
    return position + float2(jx, jy) * rim;
}

// MARK: - Water / wave ripple

[[ stitchable ]] float2 etubu_water_ripple(
    float2 position,
    float time,
    float intensity,
    float2 size
) {
    float2 uv = position / max(size, float2(1.0));
    float2 c = uv - 0.5;
    float d = length(c);
    float amp = clamp(intensity, 0.0, 1.5) * 4.0;
    float wave = sin(d * 48.0 - time * 7.0) * amp;
    float2 dir = (d > 1e-4) ? normalize(c) : float2(0.0, 1.0);
    float rim = smoothstep(0.75, 0.15, d);
    return position + dir * wave * rim;
}

[[ stitchable ]] half4 etubu_water_tint(
    float2 position,
    half4 color,
    float time,
    float intensity
) {
    float pulse = 0.5 + 0.5 * sin(time * 4.5 + position.y * 0.05);
    half3 aqua = half3(0.55h, 0.85h, 1.0h);
    half mixAmt = half(0.18 * intensity * (0.6 + 0.4 * pulse));
    return half4(mix(color.rgb, aqua, mixAmt), color.a);
}

// MARK: - Speed / warp chromatic streak

[[ stitchable ]] half4 etubu_speed_layer(
    float2 position,
    SwiftUI::Layer layer,
    float time,
    float intensity
) {
    float amp = clamp(intensity, 0.0, 1.5) * 3.5;
    float2 streak = float2(amp, 0.0);
    half4 c0 = layer.sample(position);
    half4 cR = layer.sample(position + streak);
    half4 cB = layer.sample(position - streak * 0.7);
    half3 rgb = half3(cR.r, c0.g, cB.b);
    float pulse = 0.5 + 0.5 * sin(time * 11.0);
    rgb = mix(c0.rgb, rgb, half(0.45 + 0.35 * pulse));
    return half4(rgb, max(c0.a, max(cR.a, cB.a)));
}

// MARK: - Smoke / fog soft bloom tint

[[ stitchable ]] half4 etubu_smoke_tint(
    float2 position,
    half4 color,
    float time,
    float intensity
) {
    float n = 0.5 + 0.5 * sin(position.x * 0.03 + time * 1.8) * cos(position.y * 0.025 - time * 1.3);
    half grey = half(0.55 + 0.25 * n);
    half3 smoke = half3(grey, grey * 0.98h, grey * 1.05h);
    half mixAmt = half(0.2 * intensity);
    return half4(mix(color.rgb, smoke, mixAmt), color.a * half(0.85 + 0.15 * intensity));
}

// MARK: - Fireworks / meteor sparkle boost

[[ stitchable ]] half4 etubu_sparkle_tint(
    float2 position,
    half4 color,
    float time,
    float intensity
) {
    float spark = pow(max(0.0, sin(position.x * 0.17 + time * 14.0) * cos(position.y * 0.13 - time * 11.0)), 8.0);
    half3 hot = half3(1.0h, 0.85h, 0.45h);
    half3 rgb = color.rgb + hot * half(spark * intensity * 0.85);
    return half4(rgb, color.a);
}
