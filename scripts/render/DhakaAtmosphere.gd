@tool
class_name DhakaAtmosphere
extends Node3D
## Forward+ "URP-equivalent" rendering rig for Godot 4.6: a gritty, polluted Dhaka sky.
##
## Builds and owns:
##   • WorldEnvironment  SDFGI, SSAO, SSIL, SSR, volumetric fog, depth/height fog with aerial
##                       perspective, glow, AgX tonemapping (ACES fallback), colour grading
##   • ProceduralSky     heavy brown-grey smog haze, a dimmed sun disk, noise cloud cover
##   • DirectionalLight3D 4-split PSSM shadows, soft angular size, volumetric-fog scatter
##   • CameraAttributes  auto-exposure (for walking out of dark alleys) and far DOF
##   • FogVolumes        low street smog, plus a helper for local smoke (tea stalls, braziers)
##
## Drop this node into any level. It runs in the editor (@tool), so the look appears while you
## build. Pick a `preset` (time of day / weather) and a `quality` tier. Call `blend_to()` at runtime
## for transitions (cutscenes, the monsoon arriving).
##
## Property names were written against the Godot 4.4–4.6 API. Properties that may differ
## between minor versions are set through _set_if(), which skips any the engine doesn't have.

enum Preset { HAZE_NOON, GOLDEN_SMOG, MONSOON_OVERCAST, NIGHT_SODIUM }
enum Quality { LOW, MEDIUM, HIGH, ULTRA }

@export var preset: Preset = Preset.HAZE_NOON:
	set(v):
		preset = v
		_queue_rebuild()
@export var quality: Quality = Quality.HIGH:
	set(v):
		quality = v
		_queue_rebuild()
## Overall smog thickness: 0 = a clear winter morning, 1 = dry-season AQI 300+.
@export_range(0.0, 1.5, 0.01) var smog: float = 1.0:
	set(v):
		smog = v
		_queue_rebuild()
## Street-level smog FogVolume (sits in the alleys, makes light shafts read).
@export var street_smog_volume := true:
	set(v):
		street_smog_volume = v
		_queue_rebuild()
@export var street_smog_size := Vector3(400.0, 14.0, 400.0)
## Optional 3D LUT or 1D gradient for final grading (leave empty for the built-in curve).
@export var color_lut: Texture = null

var world_env: WorldEnvironment
var env: Environment
var sun: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var cam_attr: CameraAttributesPractical
var _street_fog: FogVolume
var _pending := false
var _suppress := false
var _grade: GradientTexture1D

# --------------------------------------------------------------------------- preset table
# All colours in sRGB. sun_rot: x = elevation (negative points down), y = azimuth.
const PRESETS := {
	Preset.HAZE_NOON: {
		"sky_top": Color(0.34, 0.53, 0.76), "sky_horizon": Color(0.93, 0.87, 0.74), "sky_curve": 0.09,
		"ground_horizon": Color(0.62, 0.58, 0.52), "ground_bottom": Color(0.22, 0.2, 0.18),
		"sky_energy": 1.0, "cloud_cover": 0.45, "sun_disk_max": 12.0, "sun_curve": 0.06,
		"sun_color": Color(1.0, 0.92, 0.8), "sun_energy": 2.3, "sun_rot": Vector3(-58.0, -32.0, 0.0), "sun_angular": 1.6,
		"amb_energy": 0.6, "fog_color": Color(0.79, 0.8, 0.76), "fog_density": 0.0035, "fog_aerial": 0.45,
		"fog_sun_scatter": 0.35, "height_fog": 0.01, "vol_density": 0.012, "vol_albedo": Color(0.9, 0.87, 0.8),
		"vol_emission": Color(0.07, 0.06, 0.05), "vol_aniso": 0.55, "exposure": 1.0, "saturation": 1.08,
		"contrast": 1.08, "brightness": 1.0, "glow": 0.55, "glow_threshold": 1.1, "sdfgi_energy": 1.0,
	},
	Preset.GOLDEN_SMOG: {
		"sky_top": Color(0.42, 0.37, 0.4), "sky_horizon": Color(0.98, 0.62, 0.32), "sky_curve": 0.14,
		"ground_horizon": Color(0.62, 0.42, 0.28), "ground_bottom": Color(0.16, 0.12, 0.1),
		"sky_energy": 1.05, "cloud_cover": 0.45, "sun_disk_max": 18.0, "sun_curve": 0.1,
		"sun_color": Color(1.0, 0.6, 0.32), "sun_energy": 1.7, "sun_rot": Vector3(-11.0, -72.0, 0.0), "sun_angular": 2.4,
		"amb_energy": 0.45, "fog_color": Color(0.92, 0.6, 0.38), "fog_density": 0.0075, "fog_aerial": 0.7,
		"fog_sun_scatter": 0.85, "height_fog": 0.016, "vol_density": 0.024, "vol_albedo": Color(1.0, 0.78, 0.58),
		"vol_emission": Color(0.06, 0.035, 0.02), "vol_aniso": 0.75, "exposure": 1.05, "saturation": 1.02,
		"contrast": 1.12, "brightness": 1.0, "glow": 0.8, "glow_threshold": 0.95, "sdfgi_energy": 1.1,
	},
	Preset.MONSOON_OVERCAST: {
		"sky_top": Color(0.36, 0.4, 0.43), "sky_horizon": Color(0.6, 0.63, 0.63), "sky_curve": 0.2,
		"ground_horizon": Color(0.38, 0.4, 0.38), "ground_bottom": Color(0.14, 0.15, 0.14),
		"sky_energy": 0.8, "cloud_cover": 0.95, "sun_disk_max": 1.0, "sun_curve": 0.01,
		"sun_color": Color(0.82, 0.86, 0.9), "sun_energy": 0.55, "sun_rot": Vector3(-70.0, -20.0, 0.0), "sun_angular": 8.0,
		"amb_energy": 0.8, "fog_color": Color(0.55, 0.6, 0.6), "fog_density": 0.0095, "fog_aerial": 0.4,
		"fog_sun_scatter": 0.05, "height_fog": 0.02, "vol_density": 0.03, "vol_albedo": Color(0.82, 0.86, 0.88),
		"vol_emission": Color(0.02, 0.025, 0.025), "vol_aniso": 0.2, "exposure": 1.15, "saturation": 0.82,
		"contrast": 1.04, "brightness": 1.0, "glow": 0.35, "glow_threshold": 1.2, "sdfgi_energy": 1.2,
	},
	Preset.NIGHT_SODIUM: {
		"sky_top": Color(0.03, 0.035, 0.05), "sky_horizon": Color(0.32, 0.18, 0.1), "sky_curve": 0.12,
		"ground_horizon": Color(0.2, 0.12, 0.07), "ground_bottom": Color(0.02, 0.02, 0.02),
		"sky_energy": 0.6, "cloud_cover": 0.7, "sun_disk_max": 0.5, "sun_curve": 0.01,
		"sun_color": Color(0.55, 0.62, 0.85), "sun_energy": 0.12, "sun_rot": Vector3(-48.0, 40.0, 0.0), "sun_angular": 0.5,
		"amb_energy": 0.22, "fog_color": Color(0.36, 0.22, 0.12), "fog_density": 0.009, "fog_aerial": 0.3,
		"fog_sun_scatter": 0.0, "height_fog": 0.02, "vol_density": 0.035, "vol_albedo": Color(0.95, 0.8, 0.62),
		"vol_emission": Color(0.035, 0.018, 0.008), "vol_aniso": 0.6, "exposure": 1.35, "saturation": 1.08,
		"contrast": 1.14, "brightness": 1.0, "glow": 1.0, "glow_threshold": 0.75, "sdfgi_energy": 1.3,
	},
}

# --------------------------------------------------------------------------- lifecycle
func _ready() -> void:
	rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _pending or _suppress:
		return
	_pending = true
	call_deferred("rebuild")

func rebuild() -> void:
	_pending = false
	for c in get_children():
		if c.has_meta("dhaka_atmo"):
			c.free()
	_build_sky_and_env()
	_build_sun()
	_build_camera_attributes()
	_build_fog_volumes()
	apply_preset(PRESETS[preset], 1.0)
	apply_quality()

func _own(n: Node) -> Node:
	n.set_meta("dhaka_atmo", true)
	add_child(n)               # no owner: generated nodes are never saved into the .tscn
	return n

func _set_if(obj: Object, prop: StringName, value: Variant) -> void:
	for p in obj.get_property_list():
		if p.name == prop:
			obj.set(prop, value)
			return

# --------------------------------------------------------------------------- builders
func _cloud_texture(w: int = 1024, h: int = 512) -> NoiseTexture2D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.0035
	fnl.fractal_type = FastNoiseLite.FRACTAL_FBM
	fnl.fractal_octaves = 6
	fnl.fractal_gain = 0.55
	fnl.domain_warp_enabled = true
	fnl.domain_warp_amplitude = 40.0
	var tex := NoiseTexture2D.new()
	tex.width = w
	tex.height = h
	tex.seamless = true
	tex.noise = fnl
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0, 0, 0, 0))
	ramp.set_color(1, Color(1, 1, 1, 1))
	ramp.add_point(0.45, Color(0, 0, 0, 0))
	tex.color_ramp = ramp
	return tex

func _build_sky_and_env() -> void:
	var low := quality <= Quality.LOW
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_cover = _cloud_texture(512, 256) if low else _cloud_texture()
	_set_if(sky_mat, &"use_debanding", not low)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	sky.radiance_size = Sky.RADIANCE_SIZE_128 if low else Sky.RADIANCE_SIZE_256

	# Screen-space GI, SDFGI, SSR and volumetric fog are Forward+ only. Enabling them in
	# Compatibility prints errors and costs time for nothing, so gate them on the renderer.
	var compat := RenderingServer.get_current_rendering_method() != "forward_plus"
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0

	# Tonemapping: AgX (Godot 4.4+) handles bright smoggy skies better than ACES. Falls back to ACES.
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	if ClassDB.class_has_integer_constant(&"Environment", &"TONE_MAPPER_AGX"):
		env.tonemap_mode = ClassDB.class_get_integer_constant(&"Environment", &"TONE_MAPPER_AGX")
	env.tonemap_white = 6.0

	# Screen-space ambient occlusion: tight contact shadows where walls meet streets
	env.ssao_enabled = not compat
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.12
	env.ssao_ao_channel_affect = 0.35

	# Screen-space indirect lighting: red-brick and tarp colour bleeding into alleys
	env.ssil_enabled = not compat
	env.ssil_radius = 6.0
	env.ssil_intensity = 1.1
	env.ssil_sharpness = 0.98
	env.ssil_normal_rejection = 1.0

	# SDFGI: large-scale bounce for a whole city block (no baking needed)
	env.sdfgi_enabled = not compat
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = 0.55
	env.sdfgi_cascades = 6
	env.sdfgi_min_cell_size = 0.25
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_normal_bias = 1.1
	env.sdfgi_probe_bias = 1.1

	# Screen-space reflections: monsoon puddles, shop glass, steel shutters
	env.ssr_enabled = not compat
	env.ssr_max_steps = 72
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 2.4
	env.ssr_depth_tolerance = 0.25

	# Depth fog with aerial perspective: distant towers dissolve into brown haze
	env.fog_enabled = true
	_set_if(env, &"fog_mode", 0)        # 0 = exponential
	env.fog_sky_affect = 0.65
	env.fog_height = 6.0

	# Volumetric fog: the smog itself. Sun shafts between buildings, halos round street lamps.
	env.volumetric_fog_enabled = not compat
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_gi_inject = 0.6
	env.volumetric_fog_ambient_inject = 0.25
	env.volumetric_fog_sky_affect = 0.35
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.92

	# Glow: neon shop signs, sodium lamps, sun bloom through smog
	env.glow_enabled = true
	env.glow_normalized = true
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_scale = 2.0
	env.glow_hdr_luminance_cap = 16.0
	for i in 7:
		env.set_glow_level(i, [0.0, 0.0, 1.0, 0.85, 1.0, 0.6, 0.35][i])

	# Grading
	env.adjustment_enabled = true

	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	_own(world_env)

func _build_sun() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_split_1 = 0.06
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_fade_start = 0.85
	sun.directional_shadow_pancake_size = 30.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.light_indirect_energy = 1.0
	sun.light_specular = 0.8
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_own(sun)

func _build_camera_attributes() -> void:
	var low := quality <= Quality.LOW
	cam_attr = CameraAttributesPractical.new()
	cam_attr.auto_exposure_enabled = not low
	cam_attr.auto_exposure_scale = 0.4
	cam_attr.auto_exposure_speed = 0.6
	cam_attr.auto_exposure_min_sensitivity = 50.0
	cam_attr.auto_exposure_max_sensitivity = 800.0
	cam_attr.dof_blur_far_enabled = not low
	cam_attr.dof_blur_far_distance = 140.0
	cam_attr.dof_blur_far_transition = 90.0
	cam_attr.dof_blur_amount = 0.05
	world_env.camera_attributes = cam_attr

func _smog_density_texture() -> NoiseTexture3D:
	var fnl := FastNoiseLite.new()
	fnl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnl.frequency = 0.04
	fnl.fractal_octaves = 4
	var t := NoiseTexture3D.new()
	t.width = 64
	t.height = 32
	t.depth = 64
	t.seamless = true
	t.noise = fnl
	return t

func _build_fog_volumes() -> void:
	if not street_smog_volume or quality <= Quality.LOW:
		return
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return
	_street_fog = FogVolume.new()
	_street_fog.name = "StreetSmog"
	_street_fog.size = street_smog_size
	_street_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_street_fog.position = Vector3(0, street_smog_size.y * 0.5 - 1.0, 0)
	var fm := FogMaterial.new()
	fm.density = 0.035
	fm.albedo = Color(0.82, 0.76, 0.66)
	fm.height_falloff = 0.22
	fm.edge_fade = 0.15
	fm.density_texture = _smog_density_texture()
	_street_fog.material = fm
	_own(_street_fog)

## Local smoke column (tea-stall stove, burning rubbish, brazier). Returns the FogVolume.
func add_smoke(at: Vector3, radius: float = 1.6, height: float = 7.0, color: Color = Color(0.7, 0.68, 0.64)) -> FogVolume:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return null
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_CYLINDER
	fv.size = Vector3(radius * 2.0, height, radius * 2.0)
	var fm := FogMaterial.new()
	fm.density = 0.6
	fm.albedo = color
	fm.height_falloff = 0.35
	fm.edge_fade = 0.6
	fm.density_texture = _smog_density_texture()
	fv.material = fm
	get_parent().add_child(fv)
	fv.global_position = at + Vector3(0, height * 0.5, 0)
	return fv

## Glowing neon/sodium FogVolume halo, used around lamps at night.
func add_light_halo(at: Vector3, color: Color, radius: float = 2.5) -> FogVolume:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		return null
	var fv := FogVolume.new()
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	fv.size = Vector3.ONE * radius * 2.0
	var fm := FogMaterial.new()
	fm.density = 0.25
	fm.albedo = color
	fm.emission = color * 0.25
	fm.edge_fade = 1.0
	fv.material = fm
	get_parent().add_child(fv)
	fv.global_position = at
	return fv

# --------------------------------------------------------------------------- presets
func apply_preset(p: Dictionary, _t: float = 1.0) -> void:
	var s := smog
	sky_mat.sky_top_color = p["sky_top"]
	sky_mat.sky_horizon_color = p["sky_horizon"]
	sky_mat.sky_curve = p["sky_curve"]
	sky_mat.sky_energy_multiplier = p["sky_energy"]
	sky_mat.ground_horizon_color = p["ground_horizon"]
	sky_mat.ground_bottom_color = p["ground_bottom"]
	sky_mat.sky_cover_modulate = Color(p["sky_horizon"].r, p["sky_horizon"].g, p["sky_horizon"].b, float(p["cloud_cover"]))
	sky_mat.sun_angle_max = p["sun_disk_max"]
	sky_mat.sun_curve = p["sun_curve"]
	sun.light_color = p["sun_color"]
	sun.light_energy = float(p["sun_energy"]) * lerpf(1.25, 0.8, clampf(s, 0.0, 1.0))
	sun.rotation_degrees = p["sun_rot"]
	sun.light_angular_distance = p["sun_angular"]
	sun.light_volumetric_fog_energy = 1.4
	env.ambient_light_energy = p["amb_energy"]
	env.fog_light_color = p["fog_color"]
	env.fog_density = float(p["fog_density"]) * s
	env.fog_aerial_perspective = p["fog_aerial"]
	env.fog_sun_scatter = p["fog_sun_scatter"]
	env.fog_height_density = float(p["height_fog"]) * s
	env.volumetric_fog_density = float(p["vol_density"]) * s
	env.volumetric_fog_albedo = p["vol_albedo"]
	env.volumetric_fog_emission = p["vol_emission"]
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = p["vol_aniso"]
	env.tonemap_exposure = p["exposure"]
	env.adjustment_saturation = p["saturation"]
	env.adjustment_contrast = p["contrast"]
	env.adjustment_brightness = p["brightness"]
	if _grade == null:
		_grade = _grade_curve()
	env.adjustment_color_correction = color_lut if color_lut else _grade
	env.glow_intensity = p["glow"]
	env.glow_hdr_threshold = p["glow_threshold"]
	env.sdfgi_energy = p["sdfgi_energy"]
	if _street_fog:
		(_street_fog.material as FogMaterial).density = 0.035 * s
		(_street_fog.material as FogMaterial).albedo = p["vol_albedo"]

## Gentle cinematic grade (warm highlights, olive-teal shadows) as a 1D LUT.
func _grade_curve() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.045, 0.05))
	g.set_color(1, Color(1.0, 0.97, 0.9))
	g.add_point(0.25, Color(0.2, 0.22, 0.2))
	g.add_point(0.55, Color(0.56, 0.54, 0.5))
	g.add_point(0.8, Color(0.84, 0.79, 0.7))
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	return t

## Smoothly move to another preset (e.g. GOLDEN_SMOG for a sunset chase, MONSOON for Act 3).
func blend_to(target: Preset, seconds: float = 4.0) -> void:
	var from := _snapshot()
	var to: Dictionary = PRESETS[target]
	_suppress = true
	preset = target
	_suppress = false
	var tw := create_tween()
	tw.tween_method(func(t: float): apply_preset(_mix(from, to, t)), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE)

func _snapshot() -> Dictionary:
	return PRESETS[preset].duplicate()

func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := {}
	for k in a.keys():
		var va = a[k]
		var vb = b[k]
		if va is Color:
			out[k] = (va as Color).lerp(vb, t)
		elif va is Vector3:
			out[k] = (va as Vector3).lerp(vb, t)
		else:
			out[k] = lerpf(float(va), float(vb), t)
	return out

# --------------------------------------------------------------------------- quality tiers
func apply_quality() -> void:
	match quality:
		Quality.LOW:
			env.sdfgi_enabled = false
			env.ssil_enabled = false
			env.ssr_enabled = false
			env.volumetric_fog_enabled = false
			env.ssao_enabled = false
			env.fog_density *= 1.4        # depth fog stands in for the missing volumetrics
			env.glow_intensity = minf(env.glow_intensity, 0.7)
			for i in 7:
				env.set_glow_level(i, [0.0, 0.0, 1.0, 0.7, 0.0, 0.0, 0.0][i])
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 80.0
			if _street_fog:
				_street_fog.visible = false
		Quality.MEDIUM:
			env.sdfgi_enabled = false
			env.ssil_enabled = true
			env.ssr_enabled = false
			env.volumetric_fog_enabled = true
			env.volumetric_fog_length = 64.0
			sun.directional_shadow_max_distance = 140.0
		Quality.HIGH:
			env.sdfgi_cascades = 4
		Quality.ULTRA:
			env.sdfgi_cascades = 8
			env.sdfgi_min_cell_size = 0.2
			env.ssr_max_steps = 128
			env.volumetric_fog_length = 160.0
			sun.directional_shadow_max_distance = 320.0
	# Compatibility has no screen-space GI / SSR / volumetrics: keep them off at every tier.
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		env.sdfgi_enabled = false
		env.ssil_enabled = false
		env.ssr_enabled = false
		env.volumetric_fog_enabled = false
		env.ssao_enabled = false
	# Global settings that live on the RenderingServer rather than the Environment
	if not Engine.is_editor_hint():
		var hi := quality >= Quality.HIGH
		if env.ssao_enabled:
			RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_HIGH if hi else RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
		if env.ssil_enabled:
			RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_HIGH if hi else RenderingServer.ENV_SSIL_QUALITY_LOW, true, 0.5, 4, 50.0, 300.0)
		if env.volumetric_fog_enabled:
			RenderingServer.environment_set_volumetric_fog_volume_size(160 if quality == Quality.ULTRA else (128 if hi else 64), 128 if hi else 64)
			RenderingServer.environment_set_volumetric_fog_filter_active(true)
		if env.sdfgi_enabled:
			RenderingServer.environment_set_sdfgi_ray_count(RenderingServer.ENV_SDFGI_RAY_COUNT_64 if hi else RenderingServer.ENV_SDFGI_RAY_COUNT_32)
			RenderingServer.environment_set_sdfgi_frames_to_converge(RenderingServer.ENV_SDFGI_CONVERGE_IN_15_FRAMES if hi else RenderingServer.ENV_SDFGI_CONVERGE_IN_10_FRAMES)
		RenderingServer.directional_shadow_atlas_set_size(2048 if quality == Quality.LOW else (8192 if quality == Quality.ULTRA else 4096), true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			RenderingServer.SHADOW_QUALITY_SOFT_LOW if quality <= Quality.LOW else (RenderingServer.SHADOW_QUALITY_SOFT_HIGH if hi else RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM))
