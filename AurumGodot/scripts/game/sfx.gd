extends RefCounted
## Procedurally synthesised sound effects, so the game needs no audio files.
## Gunshots = sharp noise crack + low-passed blast + low "thump", tuned per weapon class.

static var _cache := {}


static func gunshot(kind: String) -> AudioStreamWAV:
	var key := "shot_" + kind
	if _cache.has(key):
		return _cache[key]
	var dur := 0.55
	var body_hz := 110.0
	var crack := 1.0
	var decay := 9.0
	match kind:
		"pistol":
			body_hz = 160.0
			decay = 13.0
			dur = 0.4
		"smg":
			body_hz = 150.0
			decay = 15.0
			dur = 0.35
		"shotgun":
			body_hz = 70.0
			decay = 6.5
			dur = 0.75
		"sniper", "dmr":
			body_hz = 60.0
			decay = 5.5
			dur = 0.9
		"suppressed":
			body_hz = 230.0
			decay = 26.0
			crack = 0.2
			dur = 0.25
	var fn := func(t: float, noise: float, lp: float) -> float:
		var env := exp(-t * decay)
		var thump := sin(TAU * body_hz * t * (1.0 - t * 0.6)) * exp(-t * decay * 1.6)
		return noise * crack * exp(-t * 70.0) + lp * 0.9 * env + thump * 0.8
	var wav := _synth(dur, fn, 0.35, hash(kind))
	_cache[key] = wav
	return wav


static func click() -> AudioStreamWAV:
	if _cache.has("click"):
		return _cache["click"]
	var fn := func(t: float, noise: float, _lp: float) -> float:
		return noise * exp(-t * 120.0) * 0.6 + sin(TAU * 2400.0 * t) * exp(-t * 90.0) * 0.4
	var wav := _synth(0.08, fn, 0.8, 7)
	_cache["click"] = wav
	return wav


static func reload() -> AudioStreamWAV:
	if _cache.has("reload"):
		return _cache["reload"]
	var fn := func(t: float, noise: float, _lp: float) -> float:
		var a := exp(-absf(t - 0.05) * 90.0)
		var b := exp(-absf(t - 0.45) * 70.0)
		var c := exp(-absf(t - 0.6) * 110.0)
		return noise * (a * 0.7 + b * 0.9 + c * 0.6) + sin(TAU * 900.0 * t) * (b + c) * 0.3
	var wav := _synth(0.7, fn, 0.6, 11)
	_cache["reload"] = wav
	return wav


static func hit_marker() -> AudioStreamWAV:
	if _cache.has("hit"):
		return _cache["hit"]
	var fn := func(t: float, _noise: float, _lp: float) -> float:
		return sin(TAU * 1800.0 * t) * exp(-t * 45.0) * 0.5
	var wav := _synth(0.12, fn, 0.5, 3)
	_cache["hit"] = wav
	return wav


static func _synth(duration: float, sample: Callable, lowpass: float, seed_value: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * duration)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, lowpass)
		var s: float = sample.call(t, noise, lp)
		data.encode_s16(i * 2, int(clampf(s * 0.85, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav
