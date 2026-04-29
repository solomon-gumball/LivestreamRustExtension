@tool
extends EditorScenePostImport

func _post_import(scene: Node) -> Object:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(scene, meshes)
	for mesh_instance in meshes:
		_replace_with_rigid_body(mesh_instance, scene)
	return scene

func _collect_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var has_mesh_child := node.get_children().any(func(c): return c is MeshInstance3D)
		if not has_mesh_child:
			result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, result)

func _replace_with_rigid_body(mesh_instance: MeshInstance3D, scene: Node) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return

	var parent := mesh_instance.get_parent()
	if parent == null:
		return

	var idx := mesh_instance.get_index()
	mesh_instance.owner = null
	parent.remove_child(mesh_instance)

	var body := RigidBody3D.new()
	body.name = mesh_instance.name
	body.transform = mesh_instance.transform
	mesh_instance.transform = Transform3D.IDENTITY

	parent.add_child(body)
	body.owner = scene
	parent.move_child(body, idx)

	body.add_child(mesh_instance)
	mesh_instance.owner = scene

	var col_shape := CollisionShape3D.new()
	col_shape.shape = mesh.create_convex_shape()
	body.add_child(col_shape)
	col_shape.owner = scene
