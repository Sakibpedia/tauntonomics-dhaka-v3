// Window glass and lamp heads for instanced facades. Per-instance COLOR: rgb = curtain or lamp
// tint, a = 1 if the room (or lamp) is lit at night. `night` is driven by the day/night clock.
shader_type spatial;
render_mode cull_back;

uniform float night : hint_range(0.0, 1.0) = 0.0;

varying float lit;
varying vec3 tint;
varying vec3 wpos;

void vertex() {
	lit = COLOR.a;
	tint = COLOR.rgb;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// dark reflective glass with a faint curtain colour, dusty at the bottom
	float dust = smoothstep(0.0, 1.0, fract(wpos.y * 0.33));
	ALBEDO = mix(vec3(0.03, 0.04, 0.05), tint * 0.25, 0.25 + 0.15 * dust);
	ROUGHNESS = 0.08 + 0.2 * dust;
	METALLIC = 0.25;
	SPECULAR = 0.8;
	// lit rooms glow warm at night, with slight per-window variation
	float flicker = 0.85 + 0.15 * sin(wpos.x * 3.1 + wpos.y * 7.3 + wpos.z * 1.7);
	EMISSION = tint * vec3(1.0, 0.82, 0.6) * lit * night * 2.6 * flicker;
}
