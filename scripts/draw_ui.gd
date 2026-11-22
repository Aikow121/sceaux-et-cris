class_name DrawUI
extends CanvasLayer
## Écran de dessin d'un sceau (piège). Un seul trait, 6 secondes maximum.

signal finished(points: PackedVector2Array, result: Dictionary)
signal cancelled

const TIME_LIMIT := 6.0
const RADIUS := 230.0

var _canvas: Control
var _points := PackedVector2Array()
var _drawing := false
var _t := 0.0
var _info: Label


class Canvas extends Control:
	var ui: DrawUI

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, DrawUI.RADIUS + 12.0, Color(0.93, 0.87, 0.72, 0.92))
		draw_arc(c, DrawUI.RADIUS, 0.0, TAU, 64, Color(0.45, 0.3, 0.15, 0.6), 3.0)
		if ui._points.size() > 1:
			draw_polyline(ui._points, Color(0.35, 0.05, 0.05), 5.0, true)
		var frac := clampf(ui._t / DrawUI.TIME_LIMIT, 0.0, 1.0)
		draw_arc(c, DrawUI.RADIUS + 22.0, -PI / 2, -PI / 2 + TAU * (1.0 - frac), 64, Color(1, 0.8, 0.3), 5.0)


func _ready() -> void:
	layer = 5
	visible = false
	_canvas = Canvas.new()
	_canvas.ui = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_canvas)
	_info = Label.new()
	_info.text = "Dessinez votre sceau d'un seul trait : pentacle = explosion · triangle = catapulte · carré = cage · cercle = poule\nClic droit ou Échap : annuler — vous êtes immobile et vulnérable pendant le dessin !"
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 18)
	_info.add_theme_constant_override("outline_size", 6)
	_info.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(_info)
	_info.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 30)
	_info.grow_horizontal = Control.GROW_DIRECTION_BOTH


func open() -> void:
	_points = PackedVector2Array()
	_drawing = false
	_t = 0.0
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_canvas.queue_redraw()


func close() -> void:
	visible = false
	_drawing = false


func is_open() -> bool:
	return visible


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	_canvas.queue_redraw()
	if _t >= TIME_LIMIT:
		if _points.size() > 10:
			_finish()
		else:
			close()
			cancelled.emit()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drawing = true
				_points = PackedVector2Array([event.position])
			elif _drawing:
				_drawing = false
				_finish()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			close()
			cancelled.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _drawing:
		if _points.is_empty() or _points[-1].distance_to(event.position) > 3.0:
			_points.append(event.position)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close()
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	var result := Gesture.recognize(_points)
	# Points ramenés dans le cercle unité (pour les dessiner sur la surface)
	var c := _canvas.size / 2.0
	var norm := PackedVector2Array()
	var step := maxi(1, _points.size() / 120)
	for i in range(0, _points.size(), step):
		var p := (_points[i] - c) / RADIUS
		norm.append(p.limit_length(1.0))
	close()
	finished.emit(norm, result)
