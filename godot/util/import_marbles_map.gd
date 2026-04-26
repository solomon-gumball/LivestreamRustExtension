@tool
extends EditorScenePostImport

const PROGRESS_CURVE_MESH_NAME := "progress_curve"
const DEBUG_KEEP_PROGRESS_MESH := false

# The Geometry Nodes extrude offset axis used in Blender to give the edge-chain
# faces for glTF export. Extruded duplicate verts are filtered out by checking
# that their position on this axis is near zero.
# Max distance between an original vert and its extruded duplicate.
# Set this to slightly above the extrude offset distance used in Blender.
const EXTRUDE_PAIR_DISTANCE := 0.1

# Controls how far tangents extend toward neighboring points (0.0–1.0).
# Lower = tighter corners, higher = more sweeping curves.
const CURVE_TENSION := 0.3

func _post_import(scene: Node) -> Object:
	var mesh_node := _find_node_by_name(scene, PROGRESS_CURVE_MESH_NAME)
	if mesh_node == null:
		push_error("import_marbles_map: No node named '%s' found in imported scene." % PROGRESS_CURVE_MESH_NAME)
		return scene

	if not mesh_node is MeshInstance3D:
		push_error("import_marbles_map: '%s' is not a MeshInstance3D (got %s)." % [PROGRESS_CURVE_MESH_NAME, mesh_node.get_class()])
		return scene

	var path := _build_path3d(mesh_node as MeshInstance3D)
	if path == null:
		return scene

	scene.add_child(path)
	path.owner = scene

	if not DEBUG_KEEP_PROGRESS_MESH:
		var removal_target: Node = mesh_node
		var parent := mesh_node.get_parent()
		if parent != null and parent != scene and parent.get_child_count() == 1:
			removal_target = parent
		removal_target.get_parent().remove_child(removal_target)
		removal_target.queue_free()

	return scene


func _find_node_by_name(root: Node, target_name: String) -> Node:
	if root.name == target_name:
		return root
	for child in root.get_children():
		var result := _find_node_by_name(child, target_name)
		if result != null:
			return result
	return null


func _build_path3d(mesh_node: MeshInstance3D) -> Path3D:
	var mesh: Mesh = mesh_node.mesh
	if mesh == null:
		push_error("import_marbles_map: '%s' has no mesh data." % PROGRESS_CURVE_MESH_NAME)
		return null

	var mdt := MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)

	var vertex_count := mdt.get_vertex_count()
	var edge_count := mdt.get_edge_count()

	if vertex_count < 2:
		push_error("import_marbles_map: progress_curve has fewer than 2 vertices.")
		return null

	# Filter out extruded duplicate verts. The Blender Geometry Nodes extrude
	# creates a near-identical copy of each vert offset by a small amount.
	# We find pairs of verts within EXTRUDE_PAIR_DISTANCE and keep only the
	# lower-indexed one from each pair.
	var paired: Array[bool] = []
	paired.resize(vertex_count)
	for i in vertex_count:
		if paired[i]:
			continue
		for j in range(i + 1, vertex_count):
			if paired[j]:
				continue
			if mdt.get_vertex(i).distance_to(mdt.get_vertex(j)) < EXTRUDE_PAIR_DISTANCE:
				paired[j] = true
				break

	var original_verts: Array[int] = []
	for i in vertex_count:
		if not paired[i]:
			original_verts.append(i)

	if original_verts.size() < 2:
		push_error("import_marbles_map: No original (non-extruded) vertices found. Check EXTRUDE_PAIR_DISTANCE.")
		return null

	# Map original vert indices to a compact 0..n range for the adjacency list.
	var original_set := {}
	for i in original_verts:
		original_set[i] = true

	var index_map := {}
	for i in original_verts.size():
		index_map[original_verts[i]] = i

	var n := original_verts.size()
	var adjacency: Array = []
	adjacency.resize(n)
	for i in n:
		adjacency[i] = []

	for e in edge_count:
		var a := mdt.get_edge_vertex(e, 0)
		var b := mdt.get_edge_vertex(e, 1)
		if original_set.has(a) and original_set.has(b):
			var ia: int = index_map[a]
			var ib: int = index_map[b]
			if not adjacency[ia].has(ib):
				adjacency[ia].append(ib)
			if not adjacency[ib].has(ia):
				adjacency[ib].append(ia)

	# Validate clean chain: every vertex must have 1 or 2 neighbors.
	var endpoints: Array[int] = []
	for i in n:
		var degree: int = adjacency[i].size()
		if degree == 0 or degree > 2:
			push_error("import_marbles_map: progress_curve is not a clean edge chain (vertex %d has %d edges)." % [i, degree])
			return null
		if degree == 1:
			endpoints.append(i)

	if endpoints.size() != 2:
		push_error("import_marbles_map: progress_curve must be an open chain with exactly 2 endpoints, found %d." % endpoints.size())
		return null

	# Start from the endpoint with the highest Y (top of the track, where gravity begins).
	var start_idx: int = endpoints[0]
	if mdt.get_vertex(original_verts[endpoints[1]]).y > mdt.get_vertex(original_verts[endpoints[0]]).y:
		start_idx = endpoints[1]

	# Walk the chain in order.
	var ordered: Array[int] = []
	var prev := -1
	var current := start_idx
	while true:
		ordered.append(original_verts[current])
		var next := -1
		for neighbor in adjacency[current]:
			if neighbor != prev:
				next = neighbor
				break
		if next == -1:
			break
		prev = current
		current = next

	# Apply the node's local transform to get scene-space positions.
	var xform := mesh_node.transform
	var positions: Array[Vector3] = []
	for idx in ordered:
		positions.append(xform * mdt.get_vertex(idx))

	# Build Curve3D with Catmull-Rom derived tangents.
	var curve := Curve3D.new()
	var count := positions.size()
	for i in count:
		var pos := positions[i]
		var prev_pos := positions[i - 1] if i > 0 else pos - (positions[1] - pos)
		var next_pos := positions[i + 1] if i < count - 1 else pos + (pos - positions[count - 2])
		var segment_len := positions[i].distance_to(next_pos if i < count - 1 else prev_pos)
		var tangent := (next_pos - prev_pos).normalized() * segment_len * CURVE_TENSION
		curve.add_point(pos, -tangent, tangent)

	var path := Path3D.new()
	path.name = "ProgressCurve"
	path.curve = curve
	return path
