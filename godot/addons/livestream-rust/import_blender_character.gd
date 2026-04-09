@tool
extends EditorScenePostImport

# const ARMATURE_NODE_NAME := "Armature"
const ARMATURE_NODE_NAME := "XXX"

func _post_import(scene: Node) -> Object:
	var body := CharacterBody3D.new()
	body.name = scene.name

	for child in scene.get_children():
		scene.remove_child(child)
		if child.name == ARMATURE_NODE_NAME:
			for grandchild in child.get_children():
				child.remove_child(grandchild)
				body.add_child(grandchild)
				_set_owner_recursive(grandchild, body)
		else:
			body.add_child(child)
			_set_owner_recursive(child, body)

	return body

func _set_owner_recursive(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_set_owner_recursive(child, owner)
