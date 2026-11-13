class_name Backdrop extends Node2D

## Backdrop
##
## What is under the sheet: a cutting mat, ruled in cells (`mat.gdshader`).
##
## It draws one rectangle — whatever part of the world the pixel viewport is showing —
## and the shader rules it from world position. So it is not a `WrapCanvas` and must
## not become one: it is the one thing on screen that is NOT in the space. The sheet
## repeats inside a fold; the mat it lies on does not, and the sheet sliding over a
## ruling that stays put is what makes a fold read as the sheet moving.
##
## It keeps no state and reads no clock. Redrawing every frame only re-asks where the
## camera is, and the picture at a given camera position is always the same one.

const SHADER_PATH := "res://assets/shaders/mat.gdshader"

var cell_size := 64.0
var _material: ShaderMaterial


func _ready() -> void:
	var shader: Shader = load(SHADER_PATH) if ResourceLoader.exists(SHADER_PATH) else null
	if shader != null:
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("pixel_size", PixelArt.WORLD_PER_PIXEL)
		_material.set_shader_parameter("cell", cell_size)
		material = _material
	set_depth(0)


## How deep in folds the space on screen is. The mat takes the same ground colour the
## HUD keeps behind the viewport (`WorldHud.ground_color`), so there is one answer to
## "what colour is nothing".
func set_depth(depth: int) -> void:
	if _material != null:
		var ground := WorldHud.ground_color(depth)
		_material.set_shader_parameter("ground", Vector3(ground.r, ground.g, ground.b))


## The colour the mat is currently ruled on.
func ground() -> Color:
	if _material == null:
		return WorldHud.ground_color(0)
	var g: Vector3 = _material.get_shader_parameter("ground")
	return Color(g.x, g.y, g.z)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(view_rect(), WorldHud.ground_color(0))


## The part of the world this viewport is showing, in this node's own space, and a
## cell more each way so a camera snapping between pixels never shows an edge.
func view_rect() -> Rect2:
	var to_world := get_global_transform_with_canvas().affine_inverse()
	return (to_world * get_viewport_rect()).grow(cell_size)
