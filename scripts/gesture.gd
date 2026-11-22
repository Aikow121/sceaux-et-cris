class_name Gesture
extends RefCounted
## Reconnaissance de dessins en un seul trait (« $1 Unistroke Recognizer »,
## Wobbrock et al. 2007). Insensible à la taille, à la position et à la rotation.

const N := 64
const SQUARE := 250.0
const ANGLE_RANGE := deg_to_rad(45.0)
const ANGLE_PREC := deg_to_rad(2.0)
const PHI := 0.6180339887

## Formes reconnues -> type de piège
const SHAPES := {
	"pentacle": "Explosion",
	"triangle": "Catapulte",
	"carre": "Cage",
	"cercle": "Poule",
}
const MIN_SCORE := 0.8   # en dessous : dessin raté

static var _templates: Dictionary = {}


static func _ensure_templates() -> void:
	if not _templates.is_empty():
		return
	var star := PackedVector2Array()
	for i in 6:   # étoile à 5 branches tracée d'un seul trait
		var a := -PI / 2 + i * 2.0 * TAU / 5.0
		star.append(Vector2(cos(a), sin(a)))
	_add("pentacle", star)
	var star_rev := star.duplicate()
	star_rev.reverse()
	_add("pentacle", star_rev)
	var tri := PackedVector2Array()
	for i in 4:
		var a := -PI / 2 + i * TAU / 3.0
		tri.append(Vector2(cos(a), sin(a)))
	_add("triangle", tri)
	var tri_rev := tri.duplicate()
	tri_rev.reverse()
	_add("triangle", tri_rev)
	var sq := PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)])
	_add("carre", sq)
	var sq_rev := sq.duplicate()
	sq_rev.reverse()
	_add("carre", sq_rev)
	var circ := PackedVector2Array()
	for i in 33:
		circ.append(Vector2(cos(-PI / 2 + i * TAU / 32), sin(-PI / 2 + i * TAU / 32)))
	_add("cercle", circ)
	var circ_rev := circ.duplicate()
	circ_rev.reverse()
	_add("cercle", circ_rev)


static func _add(name: String, corners: PackedVector2Array) -> void:
	# Densifie les segments pour obtenir un vrai trait
	var pts := PackedVector2Array()
	for i in corners.size() - 1:
		for k in 20:
			pts.append(corners[i].lerp(corners[i + 1], k / 20.0))
	pts.append(corners[-1])
	if not _templates.has(name):
		_templates[name] = []
	_templates[name].append(_normalize(pts))


## Renvoie { shape, score (0..1) }
static func recognize(points: PackedVector2Array) -> Dictionary:
	_ensure_templates()
	if points.size() < 10 or _path_length(points) < 40.0:
		return {"shape": "", "score": 0.0}
	var cand := _normalize(points)
	var best := INF
	var best_name := ""
	for name in _templates:
		for t in _templates[name]:
			var d := _distance_at_best_angle(cand, t)
			if d < best:
				best = d
				best_name = name
	var half_diag := 0.5 * sqrt(2.0 * SQUARE * SQUARE)
	return {"shape": best_name, "score": clampf(1.0 - best / half_diag, 0.0, 1.0)}


static func _normalize(pts: PackedVector2Array) -> PackedVector2Array:
	var p := _resample(pts)
	var c := _centroid(p)
	p = _rotate(p, -atan2(p[0].y - c.y, p[0].x - c.x))
	p = _scale(p)
	return _translate(p, -_centroid(p))


static func _resample(pts: PackedVector2Array) -> PackedVector2Array:
	var interval := _path_length(pts) / (N - 1)
	var d := 0.0
	var src := pts.duplicate()
	var out := PackedVector2Array([src[0]])
	var i := 1
	while i < src.size():
		var seg := src[i - 1].distance_to(src[i])
		if d + seg >= interval and seg > 0.0:
			var q := src[i - 1] + (src[i] - src[i - 1]) * ((interval - d) / seg)
			out.append(q)
			src.insert(i, q)
			d = 0.0
		else:
			d += seg
		i += 1
	while out.size() < N:
		out.append(src[-1])
	return out


static func _path_length(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i - 1].distance_to(p[i])
	return l


static func _centroid(p: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for v in p:
		c += v
	return c / p.size()


static func _rotate(p: PackedVector2Array, a: float) -> PackedVector2Array:
	var c := _centroid(p)
	var out := PackedVector2Array()
	for v in p:
		out.append((v - c).rotated(a) + c)
	return out


static func _scale(p: PackedVector2Array) -> PackedVector2Array:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in p:
		mn = mn.min(v)
		mx = mx.max(v)
	var size := (mx - mn).max(Vector2(1e-3, 1e-3))
	var out := PackedVector2Array()
	for v in p:
		out.append(Vector2(v.x * SQUARE / size.x, v.y * SQUARE / size.y))
	return out


static func _translate(p: PackedVector2Array, off: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		out.append(v + off)
	return out


static func _path_distance(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var d := 0.0
	var n := mini(a.size(), b.size())
	for i in n:
		d += a[i].distance_to(b[i])
	return d / n


static func _distance_at_best_angle(p: PackedVector2Array, t: PackedVector2Array) -> float:
	var a := -ANGLE_RANGE
	var b := ANGLE_RANGE
	var x1 := PHI * a + (1.0 - PHI) * b
	var f1 := _path_distance(_rotate(p, x1), t)
	var x2 := (1.0 - PHI) * a + PHI * b
	var f2 := _path_distance(_rotate(p, x2), t)
	while absf(b - a) > ANGLE_PREC:
		if f1 < f2:
			b = x2
			x2 = x1
			f2 = f1
			x1 = PHI * a + (1.0 - PHI) * b
			f1 = _path_distance(_rotate(p, x1), t)
		else:
			a = x1
			x1 = x2
			f1 = f2
			x2 = (1.0 - PHI) * a + PHI * b
			f2 = _path_distance(_rotate(p, x2), t)
	return minf(f1, f2)
