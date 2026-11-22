class_name SpellRecognizer
extends RefCounted
## Reconnaissance de mots de sorts, propre à chaque joueur.
## Le joueur enregistre lui-même chaque mot (grimoire vocal) ; on compare ensuite
## sa voix aux enregistrements avec des coefficients MFCC + DTW (alignement
## temporel), ce qui tolère qu'on prononce plus lentement ou qu'on tienne une voyelle.
## Aucun module externe : tout est en GDScript.

const SR := 8000          # fréquence d'analyse
const FRAME := 200        # 25 ms
const HOP := 160          # 20 ms
const NFFT := 256
const NMEL := 24
const NCEP := 12
const SAVE_PATH := "user://grimoire_vocal.json"

static var _ready_tables := false
static var _window := PackedFloat32Array()
static var _mel: Array = []          # [ [start_bin, PackedFloat32Array poids], ... ]
static var _dct: Array = []          # NCEP x NMEL
static var _cos := PackedFloat32Array()
static var _sin := PackedFloat32Array()
static var _rev := PackedInt32Array()

## spell_id -> Array de séquences de caractéristiques (Array[PackedFloat32Array])
var templates := {}


# ------------------------------------------------------------------ Tables

static func _init_tables() -> void:
	if _ready_tables:
		return
	_ready_tables = true
	_window.resize(FRAME)
	for i in FRAME:
		_window[i] = 0.54 - 0.46 * cos(TAU * i / (FRAME - 1))
	# Bit-reversal et facteurs de rotation de la FFT
	var bits := int(round(log(NFFT) / log(2)))
	_rev.resize(NFFT)
	for i in NFFT:
		var r := 0
		var x := i
		for b in bits:
			r = (r << 1) | (x & 1)
			x >>= 1
		_rev[i] = r
	_cos.resize(NFFT / 2)
	_sin.resize(NFFT / 2)
	for i in NFFT / 2:
		_cos[i] = cos(-TAU * i / NFFT)
		_sin[i] = sin(-TAU * i / NFFT)
	# Banc de filtres mel triangulaires (100 Hz -> 4000 Hz)
	var mel_lo := _hz_to_mel(100.0)
	var mel_hi := _hz_to_mel(SR / 2.0)
	var pts := []
	for i in NMEL + 2:
		var hz := _mel_to_hz(mel_lo + (mel_hi - mel_lo) * i / (NMEL + 1))
		pts.append(hz * NFFT / SR)
	for m in NMEL:
		var a: float = pts[m]
		var c: float = pts[m + 1]
		var b: float = pts[m + 2]
		var start := int(floor(a))
		var w := PackedFloat32Array()
		for k in range(start, int(ceil(b)) + 1):
			var v := 0.0
			if k > a and k <= c:
				v = (k - a) / maxf(c - a, 1e-6)
			elif k > c and k < b:
				v = (b - k) / maxf(b - c, 1e-6)
			w.append(v)
		_mel.append([start, w])
	for n in NCEP:
		var row := PackedFloat32Array()
		row.resize(NMEL)
		for m in NMEL:
			row[m] = cos(PI * (n + 1) * (m + 0.5) / NMEL)   # on saute c0 (volume)
		_dct.append(row)


static func _hz_to_mel(hz: float) -> float:
	return 2595.0 * log(1.0 + hz / 700.0) / log(10.0)


static func _mel_to_hz(mel: float) -> float:
	return 700.0 * (pow(10.0, mel / 2595.0) - 1.0)


static func _fft(re: PackedFloat32Array, im: PackedFloat32Array) -> void:
	var n := NFFT
	for i in n:
		var j := _rev[i]
		if j > i:
			var t := re[i]
			re[i] = re[j]
			re[j] = t
			t = im[i]
			im[i] = im[j]
			im[j] = t
	var size := 2
	while size <= n:
		var half := size >> 1
		var step := n / size
		var start := 0
		while start < n:
			var k := 0
			for j in range(start, start + half):
				var wr := _cos[k]
				var wi := _sin[k]
				var l := j + half
				var tr := wr * re[l] - wi * im[l]
				var ti := wr * im[l] + wi * re[l]
				re[l] = re[j] - tr
				im[l] = im[j] - ti
				re[j] += tr
				im[j] += ti
				k += step
			start += size
		size <<= 1


# ------------------------------------------------------------------ Audio -> caractéristiques

## Rééchantillonnage simple (interpolation linéaire, avec moyenne si on réduit).
static func resample(src: PackedFloat32Array, from_rate: float, to_rate: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if src.is_empty():
		return out
	var ratio := from_rate / to_rate
	var n := int(src.size() / ratio)
	out.resize(n)
	var span := maxi(1, int(ratio))
	for i in n:
		var pos := i * ratio
		var i0 := int(pos)
		if span > 1:
			var acc := 0.0
			var cnt := 0
			for k in span:
				var idx := i0 + k
				if idx < src.size():
					acc += src[idx]
					cnt += 1
			out[i] = acc / maxi(cnt, 1)
		else:
			var f := pos - i0
			var a := src[i0]
			var b := src[mini(i0 + 1, src.size() - 1)]
			out[i] = a + (b - a) * f
	return out


## Analyse un enregistrement mono à 8000 Hz.
## Renvoie { feat: séquence MFCC (rognée, compressée, normalisée), duration: s parlées, level: volume 0..1 }
static func analyze(samples: PackedFloat32Array) -> Dictionary:
	_init_tables()
	var res := {"feat": [], "duration": 0.0, "level": 0.0}
	if samples.size() < FRAME:
		return res
	var re := PackedFloat32Array()
	var im := PackedFloat32Array()
	re.resize(NFFT)
	im.resize(NFFT)
	var mels: Array = []
	var energies := PackedFloat32Array()
	var rmss := PackedFloat32Array()
	var mel_peak := 0.0
	var pos := 0
	while pos + FRAME <= samples.size():
		var e := 0.0
		var prev := samples[pos - 1] if pos > 0 else 0.0
		for i in FRAME:
			var s := samples[pos + i]
			re[i] = (s - 0.97 * prev) * _window[i]
			prev = s
			im[i] = 0.0
			e += s * s
		for i in range(FRAME, NFFT):
			re[i] = 0.0
			im[i] = 0.0
		_fft(re, im)
		var melv := PackedFloat32Array()
		melv.resize(NMEL)
		for m in NMEL:
			var f: Array = _mel[m]
			var st: int = f[0]
			var w: PackedFloat32Array = f[1]
			var acc := 0.0
			for k in w.size():
				var bin := st + k
				if bin <= NFFT / 2:
					acc += w[k] * (re[bin] * re[bin] + im[bin] * im[bin])
			melv[m] = acc
			mel_peak = maxf(mel_peak, acc)
		mels.append(melv)
		energies.append(log(e / FRAME + 1e-10))
		rmss.append(sqrt(e / FRAME))
		pos += HOP
	# Rognage des silences au début et à la fin
	var emax := -INF
	for e in energies:
		emax = maxf(emax, e)
	var thr := maxf(emax - 3.5, log(1e-6))
	var first := 0
	while first < energies.size() and energies[first] < thr:
		first += 1
	var last := energies.size() - 1
	while last > first and energies[last] < thr:
		last -= 1
	if last - first + 1 < 4:
		return res
	var level := 0.0
	for i in range(first, last + 1):
		level = maxf(level, rmss[i])
	res.level = clampf(level * 4.0, 0.0, 1.0)
	res.duration = (last - first + 1) * float(HOP) / SR
	# Plancher spectral (réduit l'effet du bruit de fond) puis cepstre
	var floor_v := mel_peak * 0.003 + 1e-10
	var frames: Array = []
	for i in range(first, last + 1):
		var melv: PackedFloat32Array = mels[i]
		var lg := PackedFloat32Array()
		lg.resize(NMEL)
		for m in NMEL:
			lg[m] = log(maxf(melv[m], floor_v))
		var c := PackedFloat32Array()
		c.resize(NCEP)
		for n in NCEP:
			var row: PackedFloat32Array = _dct[n]
			var acc2 := 0.0
			for m in NMEL:
				acc2 += row[m] * lg[m]
			c[n] = acc2
		frames.append(c)
	# Compression des passages stables (voyelle tenue) : on garde une trame
	# seulement si elle diffère assez de la précédente gardée.
	var kept: Array = [frames[0]]
	for i in range(1, frames.size()):
		if _dist(frames[i], kept[-1]) > 3.0 or i == frames.size() - 1:
			kept.append(frames[i])
	# Normalisation (soustraction de la moyenne cepstrale)
	var mean := PackedFloat32Array()
	mean.resize(NCEP)
	for fr in kept:
		for n in NCEP:
			mean[n] += fr[n]
	for n in NCEP:
		mean[n] /= kept.size()
	for fr in kept:
		for n in NCEP:
			fr[n] -= mean[n]
	res.feat = kept
	return res


static func _dist(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var d := 0.0
	for k in NCEP:
		var x := a[k] - b[k]
		d += x * x
	return sqrt(d)


# ------------------------------------------------------------------ Comparaison

static func dtw(a: Array, b: Array) -> float:
	var n := a.size()
	var m := b.size()
	if n == 0 or m == 0:
		return INF
	var prev := PackedFloat32Array()
	var cur := PackedFloat32Array()
	prev.resize(m + 1)
	cur.resize(m + 1)
	prev.fill(INF)
	prev[0] = 0.0
	for i in range(1, n + 1):
		cur.fill(INF)
		var fa: PackedFloat32Array = a[i - 1]
		for j in range(1, m + 1):
			var fb: PackedFloat32Array = b[j - 1]
			var d := 0.0
			for k in NCEP:
				var x := fa[k] - fb[k]
				d += x * x
			d = sqrt(d)
			cur[j] = d + minf(prev[j - 1], minf(prev[j], cur[j - 1]))
		var t := prev
		prev = cur
		cur = t
	return prev[m] / (n + m)


func has_spell(id: String) -> bool:
	return templates.has(id) and not templates[id].is_empty()


func count() -> int:
	var c := 0
	for k in templates:
		if not templates[k].is_empty():
			c += 1
	return c


func add_template(id: String, feat: Array) -> void:
	if feat.is_empty():
		return
	if not templates.has(id):
		templates[id] = []
	templates[id].append(feat)
	while templates[id].size() > 3:
		templates[id].pop_front()


func clear_spell(id: String) -> void:
	templates.erase(id)


## Renvoie { id, dist, second, ok } : ok = reconnaissance fiable.
func classify(feat: Array) -> Dictionary:
	var res := {"id": "", "dist": INF, "second": INF, "ok": false}
	if feat.is_empty():
		return res
	var scores := {}
	for id in templates:
		var best := INF
		for t in templates[id]:
			best = minf(best, dtw(feat, t))
		scores[id] = best
	for id in scores:
		if scores[id] < res.dist:
			res.second = res.dist
			res.dist = scores[id]
			res.id = id
		elif scores[id] < res.second:
			res.second = scores[id]
	# Fiable si assez proche ET nettement meilleur que le 2e candidat
	# (réglages testés sur voix synthétiques : mots normaux, bruités, voyelle tenue).
	if res.second == INF:
		res.ok = res.dist < 6.0
	else:
		res.ok = res.dist < 7.5 and res.dist < res.second * 0.82
	return res


# ------------------------------------------------------------------ Sauvegarde

func save() -> void:
	var data := {}
	for id in templates:
		var arr := []
		for feat in templates[id]:
			var seq := []
			for fr in feat:
				seq.append(Array(fr))
			arr.append(seq)
		data[id] = arr
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


func load_saved() -> void:
	templates.clear()
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	for id in data:
		var list := []
		for seq in data[id]:
			var feat := []
			for fr in seq:
				feat.append(PackedFloat32Array(fr))
			list.append(feat)
		templates[id] = list
