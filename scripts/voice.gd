class_name VoiceSystem
extends Node
## Micro, chat vocal de proximité et enregistrement des incantations.
## - Le micro est capté via un bus audio muet « Micro » (AudioEffectCapture).
## - La voix est ramenée à 16 kHz, compressée en µ-law (8 bits) et envoyée
##   seulement quand on parle (porte de bruit). ~128 kbit/s par joueur qui parle.
## - Chez les autres, elle est jouée par un AudioStreamPlayer3D sur le corps du
##   joueur : on entend donc les gens selon la distance (proximité).

const RATE := 16000
const PACKET := 640                 # 40 ms
const GATE := 0.012                 # seuil de la porte de bruit (RMS)
const HANGOVER := 0.35              # on continue d'envoyer un peu après la fin d'une phrase
const LAST_WORDS_SEC := 3.0
const MAX_UTTERANCE_SEC := 4.0

signal level_changed(level: float)

var main: Node
var enabled := false
var level := 0.0                    # volume actuel du micro (0..1)
var transmit := true                # coupé si on est « réduit au silence »

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _mix_rate := 44100.0
var _phase := 0.0
var _mono_buf := PackedFloat32Array()
var _out_buf := PackedFloat32Array()  # 16 kHz en attente d'envoi
var _last_words := PackedFloat32Array()
var _utterance := PackedFloat32Array()
var _recording := false
var _hang := 0.0
var _clip_player: AudioStreamPlayer
var _clip_queue: Array = []


func _ready() -> void:
	_mix_rate = AudioServer.get_mix_rate()
	_clip_player = AudioStreamPlayer.new()
	_clip_player.volume_db = 4.0
	add_child(_clip_player)
	_clip_player.finished.connect(_play_next_clip)


## Démarre le micro (à appeler une fois).
func start_mic() -> void:
	if enabled:
		return
	var idx := AudioServer.get_bus_index("Micro")
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Micro")
		AudioServer.set_bus_mute(idx, true)   # on ne s'entend pas soi-même
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(idx, _capture)
	else:
		_capture = AudioServer.get_bus_effect(idx, 0)
	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "Micro"
	add_child(_mic_player)
	_mic_player.play()
	enabled = true


func _process(delta: float) -> void:
	if not enabled or _capture == null:
		return
	var n := _capture.get_frames_available()
	if n <= 0:
		return
	var frames := _capture.get_buffer(n)
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		mono[i] = (frames[i].x + frames[i].y) * 0.5
	inject_samples(_to_16k(mono), delta)


## Point d'entrée des échantillons à 16 kHz (aussi utilisé par les tests).
func inject_samples(s: PackedFloat32Array, delta := 0.016) -> void:
	if s.is_empty():
		return
	var e := 0.0
	for v in s:
		e += v * v
	var rms := sqrt(e / s.size())
	level = lerpf(level, clampf(rms * 6.0, 0.0, 1.0), 0.5)
	level_changed.emit(level)
	# Derniers mots (3 s glissantes)
	_last_words.append_array(s)
	var keep := int(LAST_WORDS_SEC * RATE)
	if _last_words.size() > keep:
		_last_words = _last_words.slice(_last_words.size() - keep)
	# Incantation en cours
	if _recording and _utterance.size() < MAX_UTTERANCE_SEC * RATE:
		_utterance.append_array(s)
	# Chat vocal
	_out_buf.append_array(s)
	while _out_buf.size() >= PACKET:
		var chunk := _out_buf.slice(0, PACKET)
		_out_buf = _out_buf.slice(PACKET)
		_send_chunk(chunk)


func _to_16k(src: PackedFloat32Array) -> PackedFloat32Array:
	# Rééchantillonnage en continu (moyenne sur la fenêtre) mix_rate -> 16 kHz
	_mono_buf.append_array(src)
	var ratio := _mix_rate / RATE
	var out := PackedFloat32Array()
	var span := maxi(1, int(ratio))
	while _phase + span < _mono_buf.size():
		var i0 := int(_phase)
		var acc := 0.0
		for k in span:
			acc += _mono_buf[i0 + k]
		out.append(acc / span)
		_phase += ratio
	var consumed := int(_phase)
	_mono_buf = _mono_buf.slice(consumed)
	_phase -= consumed
	return out


func _send_chunk(chunk: PackedFloat32Array) -> void:
	var e := 0.0
	for v in chunk:
		e += v * v
	var rms := sqrt(e / chunk.size())
	if rms > GATE:
		_hang = HANGOVER
	else:
		_hang -= float(PACKET) / RATE
	if _hang <= 0.0 or not transmit:
		return
	if main == null or not main.in_game or multiplayer.get_peers().is_empty():
		return
	voice_packet.rpc(encode(chunk))


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func voice_packet(data: PackedByteArray) -> void:
	if main == null:
		return
	var sender := str(multiplayer.get_remote_sender_id())
	main.route_voice(sender, decode(data))


# ------------------------------------------------------------------ Incantation

func begin_utterance() -> void:
	_utterance = PackedFloat32Array()
	_recording = true


func end_utterance() -> PackedFloat32Array:
	_recording = false
	return _utterance


func is_recording() -> bool:
	return _recording


func utterance_length() -> float:
	return float(_utterance.size()) / RATE


func last_words() -> PackedFloat32Array:
	return _last_words.duplicate()


# ------------------------------------------------------------------ Lecture de clips (replay)

func play_clips(clips: Array) -> void:
	_clip_queue = clips.duplicate()
	_clip_player.stop()
	_play_next_clip()


func _play_next_clip() -> void:
	while not _clip_queue.is_empty():
		var c: PackedFloat32Array = _clip_queue.pop_front()
		if c.size() > RATE / 10:
			_clip_player.stream = make_wav(c)
			_clip_player.play()
			return


static func make_wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav


# ------------------------------------------------------------------ µ-law

static func encode(s: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(s.size())
	var k := 1.0 / log(256.0)
	for i in s.size():
		var x := clampf(s[i], -1.0, 1.0)
		var y := signf(x) * log(1.0 + 255.0 * absf(x)) * k
		out[i] = int(round((y + 1.0) * 127.5))
	return out


static func decode(b: PackedByteArray) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(b.size())
	for i in b.size():
		var y := b[i] / 127.5 - 1.0
		out[i] = signf(y) * (pow(256.0, absf(y)) - 1.0) / 255.0
	return out


## 16 kHz -> 8 kHz pour la reconnaissance
static func to_8k(s: PackedFloat32Array) -> PackedFloat32Array:
	return SpellRecognizer.resample(s, RATE, SpellRecognizer.SR)
