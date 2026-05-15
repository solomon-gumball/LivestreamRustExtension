@tool
extends Node

const LINE_RADIUS := 0.003

var _sphere_mmi: MultiMeshInstance3D
var _line_mmi: MultiMeshInstance3D
var _sphere_items: Array = []
var _line_items: Array = []


class _Item:
  var transform: Transform3D
  var color: Color
  var time_left: float

  func _init(t: Transform3D, c: Color, d: float) -> void:
    transform = t
    color = c
    time_left = d

func _ready() -> void:
  _sphere_mmi = _make_mmi(SphereMesh.new())

  var cyl := CylinderMesh.new()
  cyl.top_radius = LINE_RADIUS
  cyl.bottom_radius = LINE_RADIUS
  cyl.height = 1.0
  _line_mmi = _make_mmi(cyl)


var next_pass_mat: ShaderMaterial = preload("res://materials/dither_xray.tres")
func _make_mmi(mesh: Mesh) -> MultiMeshInstance3D:
  var mmi := MultiMeshInstance3D.new()
  mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
  add_child(mmi)
  var mm := MultiMesh.new()
  mm.transform_format = MultiMesh.TRANSFORM_3D
  mm.use_colors = true
  mm.mesh = mesh
  mmi.multimesh = mm
  # TODO: replace with wireframe shader
  var mat := StandardMaterial3D.new()
  mat.vertex_color_use_as_albedo = true
  mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
  mat.next_pass = next_pass_mat
  mm.mesh.surface_set_material(0, mat)
  return mmi

func _physics_process(delta: float) -> void:
  _flush(_sphere_mmi, _sphere_items)
  _flush(_line_mmi, _line_items)
  _cull(delta, _sphere_items)
  _cull(delta, _line_items)

func _flush(mmi: MultiMeshInstance3D, items: Array) -> void:
  var mm := mmi.multimesh
  mm.instance_count = items.size()
  for i in items.size():
    mm.set_instance_transform(i, items[i].transform)
    mm.set_instance_color(i, items[i].color)

func _cull(delta: float, items: Array) -> void:
  var i := items.size() - 1
  while i >= 0:
    items[i].time_left -= delta
    if items[i].time_left < 0.0:
      items.remove_at(i)
    i -= 1

func draw_sphere(location: Vector3, radius: float, color: Color, duration: float = 0.0) -> void:
  var t := Transform3D(Basis.IDENTITY.scaled(Vector3(radius, radius, radius)), location)
  _sphere_items.append(_Item.new(t, color, duration))

func draw_line(from_point: Vector3, to_point: Vector3, color: Color, width: float = LINE_RADIUS, duration: float = 0.0) -> void:
  _line_items.append(_Item.new(_line_transform(from_point, to_point, width), color, duration))

static func _line_transform(from_pt: Vector3, to_pt: Vector3, width: float = LINE_RADIUS) -> Transform3D:
  var diff := to_pt - from_pt
  var length := diff.length()
  if length < 1e-6:
    return Transform3D.IDENTITY
  var dir := diff / length
  var b := _y_basis(dir)
  var scale := width / LINE_RADIUS
  var basis := Basis(b.x * scale, b.y * length, b.z * scale)
  return Transform3D(basis, (from_pt + to_pt) * 0.5)

static func _y_basis(y_axis: Vector3) -> Basis:
  var ref := Vector3.RIGHT if abs(y_axis.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
  var x_axis := ref.cross(y_axis).normalized()
  var z_axis := x_axis.cross(y_axis)
  return Basis(x_axis, y_axis, z_axis)
