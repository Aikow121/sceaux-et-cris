class_name Trap
extends Node3D
## Piège dessiné sur une surface. Le tracé du joueur est reproduit tel quel
## (tout le monde voit donc vos dessins… même ratés).

const RADIUS := 1.1
const ARM_TIME := 1.2
const COLORS := {
	"pentacle": Color(1.0, 0.35, 0.15),
	"triangle": Color(0.3, 0.8, 1.0),
	"carre": Color(0.75, 0.75, 0.8),
	"cercle": Color(1.0, 0.9, 0.3),
}

var id := 0
var owner_name := ""
var shape := "pentacle"
var power := 1.0
var normal := Vector3.UP
var points := PackedVector2Array()
var mine := false
var armed_t := ARM_TIME
var _mat: StandardMaterial3D


func _ready() -> void:
	var col: Color = COLORS.get(shape, Color.WHITE)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(col.r, col.g, col.b, 0.9 if mine else 0.35)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.mesh = _build_ribbon()
	mi.material_override = _mat
	add_child(mi)
	# Cercle extérieur
	var ring := PackedVector2Array()
	for i in 41:
		ring.append(Vector2.from_angle(i * TAU / 40.0))
	var ri := MeshInstance3D.new()
	ri.mesh = _ribbon_from(ring, 0.035)
	ri.material_override = _mat
	add_child(ri)


## Ruban plat le long du tracé (dans le plan local XZ, normale = +Y local)
func _build_ribbon() -> ArrayMesh:
	return _ribbon_from(points, 0.05)


func _ribbon_from(pts: PackedVector2Array, half_w: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, pts.size()):
		var a := Vector3(pts[i - 1].x, 0.0, pts[i - 1].y) * RADIUS
		var b := Vector3(pts[i].x, 0.0, pts[i].y) * RADIUS
		var d := b - a
		if d.length() < 0.001:
			continue
		var side := Vector3(-d.z, 0, d.x).normalized() * half_w
		st.add_vertex(a - side)
		st.add_vertex(a + side)
		st.add_vertex(b + side)
		st.add_vertex(a - side)
		st.add_vertex(b + side)
		st.add_vertex(b - side)
	return st.commit()


## Oriente le piège sur la surface (appelé après add_child)
func place(pos: Vector3, n: Vector3) -> void:
	normal = n.normalized()
	var ref := Vector3.FORWARD if absf(normal.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(normal).normalized()
	var z := x.cross(normal).normalized()
	global_transform = Transform3D(Basis(x, normal, z), pos + normal * 0.03)


func _process(delta: float) -> void:
	if armed_t > 0.0:
		armed_t -= delta
		_mat.albedo_color.a = (0.9 if mine else 0.35) * (0.4 + 0.6 * absf(sin(armed_t * 12.0)))
	else:
		_mat.albedo_color.a = (0.9 if mine else 0.35)


func is_armed() -> bool:
	return armed_t <= 0.0
