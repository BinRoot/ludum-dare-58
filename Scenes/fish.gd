extends Node3D

# =======================
# Types for small results
# =======================
class BFSResult:
	var node: int
	var dist: int
	func _init(p_node: int, p_dist: int) -> void:
		node = p_node
		dist = p_dist

class PolylineProjection:
	var cum_length: float
	var side_sign: int
	func _init(p_cum_length: float, p_side_sign: int) -> void:
		cum_length = p_cum_length
		side_sign = p_side_sign

var mutate_graph: MutateGraph = MutateGraph.new()

# ===============
# User parameters
# ===============
@export var graph: Array[Vector2i] = []
@export var move_speed := (randf() * 1) + 2
@export var bounds_shape: CollisionShape3D

@export var body_segments: int = 64
@export var ring_sides: int = 32
@export var body_length_scale: float = 1.0
@export var camber_z: float = 0.18
@export var twist_degrees: float = 14.0

@export var a0: float = 0.40
@export var b0: float = 0.34
@export var taper_a_power: float = 0.35
@export var taper_b_power: float = 0.20
@export var min_radius: float = 0.05  # Minimum radius to prevent degenerate geometry
@export var bulge_amp: float = 0.30
@export var bulge_center: float = 0.40
@export var bulge_sigma: float = 0.18

@export var asymmetry_amp: float = 0.22
@export var node_sigma_s: float = 0.20
@export var degree_bias: float = 0.60

@export var add_edge_tubes: bool = true
@export var tube_radius: float = 0.06  # Slightly increased for better body overlap
@export var tube_segments: int = 8
@export var tube_overlap_factor: float = 1.15  # Tubes slightly larger to ensure connection

@export var layout_iterations: int = 120
@export var layout_area: float = 9.0

@export var base_color: Color = Color(0.78, 0.9, 1.0)

@export_group("Fins")
@export var add_fins: bool = true
@export var dorsal_fin_size: float = 0.3  # Height of dorsal fin
@export var dorsal_fin_position: float = 0.4  # Position along body (0=tail, 1=head)
@export var pectoral_fin_size: float = 0.25  # Size of side fins
@export var pectoral_fin_position: float = 0.7  # Position along body
@export var tail_fin_size: float = 0.4  # Size of tail fin
@export var fin_segments: int = 8  # Tessellation of fins

@export_group("Wiggle")
@export var wiggle_amplitude: float = 0.15
@export var wiggle_frequency: float = 2.0
@export var wiggle_speed: float = 1.5
@export var tail_amplification: float = 2.5

@export_group("Scaling")
@export var enable_complexity_scaling: bool = true
@export var min_scale: float = 0.5
@export var max_scale: float = 15.0
@export var base_complexity: float = 5.0  # Graph with 4 nodes = 1.0 scale

@export_group("Debug")
@export var debug_mode: bool = false
@export var debug_spine_color: Color = Color(1.0, 0.0, 0.0)
@export var debug_node_color: Color = Color(0.0, 1.0, 0.0)
@export var debug_edge_color: Color = Color(0.0, 0.5, 1.0)

@onready var left_fish_eye: Node3D = $LeftFishEye
@onready var right_fish_eye: Node3D = $RightFishEye


const TAU: float = PI * 2.0

# Movement state
var current_target: Vector3 = Vector3.ZERO
var is_moving: bool = false
var arrival_distance: float = 0.5

# Age and growth
var age: int = -1
var is_in_tank: bool = false
var parent_tank: Node3D = null  # Reference to the tank this fish is in

# Surface behavior state
var is_surfacing: bool = false
var surface_timer: float = 0.0
var next_surface_time: float = 0.0
@export var surface_interval_min: float = 2.0  # Minimum time between surfaces
@export var surface_interval_max: float = 8.0  # Maximum time between surfaces
@export var surface_duration: float = 1.0  # How long the fish stays visible at surface
@export var surface_look_angle: float = 0.0  # Degrees to look up when surfacing

var _mesh_instance: MeshInstance3D
var _debug_mesh_instance: MeshInstance3D
var _shader_material: ShaderMaterial

# Store spine data for wiggle calculations
var _spine_curve: PackedVector3Array
var _spine_normals: PackedVector3Array
var _spine_binormals: PackedVector3Array
var _spine_tangents: PackedVector3Array
var _spine_bias: PackedFloat32Array
var _spine_segments: int

func _ready() -> void:
	# Generate a unique random graph for this fish if not already set
	if graph.is_empty():
		graph = _generate_random_graph()

	# Randomize fish color only on initial creation
	base_color = Color(randf(), randf(), randf())

	render_graph()
	# Start moving once the fish is ready
	_pick_new_destination()
	# Schedule first surface appearance
	next_surface_time = randf_range(surface_interval_min, surface_interval_max)
	# Start hidden (underwater)
	visible = false

# Generate a random connected graph with 3-5 nodes
func _generate_random_graph() -> Array[Vector2i]:
	var num_nodes: int = randi_range(3, 5)
	var edges: Array[Vector2i] = []

	# Create a list of all possible edges (complete graph)
	var all_possible_edges: Array[Vector2i] = []
	for i in range(1, num_nodes + 1):
		for j in range(i + 1, num_nodes + 1):
			all_possible_edges.append(Vector2i(i, j))

	# Shuffle the possible edges for randomness
	all_possible_edges.shuffle()

	# First, create a spanning tree to ensure connectivity
	# Start with node 1 and gradually connect other nodes
	var connected_nodes: Array[int] = [1]
	var unconnected_nodes: Array[int] = []
	for i in range(2, num_nodes + 1):
		unconnected_nodes.append(i)

	# Connect each unconnected node to a random connected node
	while unconnected_nodes.size() > 0:
		var new_node: int = unconnected_nodes.pop_back()
		var connect_to: int = connected_nodes[randi() % connected_nodes.size()]

		# Create edge (ensure smaller node is first for consistency)
		if connect_to < new_node:
			edges.append(Vector2i(connect_to, new_node))
		else:
			edges.append(Vector2i(new_node, connect_to))

		connected_nodes.append(new_node)

	# Now we have a connected tree with (num_nodes - 1) edges
	# Add 0-3 additional random edges to make the graph more interesting
	var additional_edges: int = randi_range(0, min(3, all_possible_edges.size() - edges.size()))

	for edge in all_possible_edges:
		if additional_edges <= 0:
			break

		# Check if this edge is not already in our edge list
		var already_exists: bool = false
		for existing_edge in edges:
			if existing_edge == edge:
				already_exists = true
				break

		if not already_exists:
			edges.append(edge)
			additional_edges -= 1

	return edges

# Calculate scale factor based on graph complexity
func _calculate_complexity_scale() -> float:
	if not enable_complexity_scaling:
		return 1.0

	var nodes: Array[int] = _collect_nodes(graph)
	var num_nodes: float = float(nodes.size())
	var num_edges: float = float(graph.size())

	# Complexity metric: weighted combination of nodes and edges
	# More weight on nodes since they represent major structural elements
	var complexity: float = num_nodes + (num_edges * 2)

	# Scale relative to base complexity
	var scale_factor: float = sqrt(complexity / base_complexity)

	# Clamp to min/max range
	return clamp(scale_factor, min_scale, max_scale)

func _process(delta: float) -> void:
	# Handle surface behavior
	_handle_surface_behavior(delta)

	# Handle movement
	if is_moving and not is_surfacing:
		_move_toward_target(delta)

	# Update eye positions to match the wiggle animation
	if _spine_curve.size() > 0 and left_fish_eye != null and right_fish_eye != null:
		_update_wiggling_eyes()

		# Make eyes look at the destination while moving
		if is_moving and not is_surfacing:
			_make_eyes_look_at_target()

func render_graph() -> void:
	# Don't randomize color here - it's set in _ready() and preserved during growth
	if _mesh_instance != null:
		_mesh_instance.queue_free()
	if _debug_mesh_instance != null:
		_debug_mesh_instance.queue_free()
		_debug_mesh_instance = null
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)

	var nodes: Array[int] = _collect_nodes(graph)
	if nodes.size() < 2:
		push_warning("Graph has fewer than 2 nodes; nothing to render.")
		return

	# Calculate complexity-based scale factor
	var complexity_scale: float = _calculate_complexity_scale()

	var adj: Dictionary = _build_undirected_adjacency(graph)

	# --- Pick endpoints via double-BFS
	var any_node: int = nodes[0]
	var a_far: BFSResult = _bfs_farthest(any_node, adj)
	var b_far: BFSResult = _bfs_farthest(a_far.node, adj)
	var head: int = a_far.node
	var tail: int = b_far.node

	# --- Path (spine in node space)
	var path: Array[int] = _bfs_path(head, tail, adj)
	if path.size() < 2:
		push_warning("Could not find a path between endpoints; graph may be disconnected.")
		return

	# --- 2D layout (FR)
	var pos2d: Dictionary[int, Vector2] = _force_layout_2d(nodes, adj, layout_iterations, layout_area)
	_normalize_layout(pos2d, body_length_scale)

	# --- Build Curve3D for spine in XY (camber later)
	var curve: Curve3D = Curve3D.new()
	for i: int in range(path.size()):
		var nid: int = path[i]
		var p2: Vector2 = pos2d[nid]
		curve.add_point(Vector3(p2.x, p2.y, 0.0))
	curve.bake_interval = 0.1

	# --- Sample spine + add camber
	var ns: int = max(4, body_segments)
	var C: PackedVector3Array = PackedVector3Array()
	C.resize(ns)
	var curve_len: float = curve.get_baked_length()
	for j: int in range(ns):
		var t: float = float(j) / float(ns - 1)
		var p: Vector3 = curve.sample_baked(t * curve_len)
		var z_val: float = camber_z * sin(PI * t)
		C[j] = Vector3(p.x, p.y, z_val)

	# --- Frames along spine (RMF)
	var TNB: Dictionary[StringName, PackedVector3Array] = _rmf_frames(C)
	var T: PackedVector3Array = TNB["T"]
	var N: PackedVector3Array = TNB["N"]
	var B: PackedVector3Array = TNB["B"]

	# --- Bias field from all nodes projected onto spine (for asymmetry)
	var poly_xy: PackedVector2Array = PackedVector2Array()
	poly_xy.resize(ns)
	for j2: int in range(ns):
		poly_xy[j2] = Vector2(C[j2].x, C[j2].y)

	var total_xy_len: float = _polyline_length(poly_xy)

	var bias: PackedFloat32Array = PackedFloat32Array()
	bias.resize(ns)
	for j3: int in range(ns):
		bias[j3] = 0.0

	for idx_node: int in range(nodes.size()):
		var nid2: int = nodes[idx_node]
		var p2n: Vector2 = pos2d[nid2]
		var proj: PolylineProjection = _project_point_to_polyline(p2n, poly_xy)
		var s_i: float = 0.0 if total_xy_len <= 1e-6 else proj.cum_length / total_xy_len
		var side: int = proj.side_sign
		var deg: float = float(adj[nid2].size())
		var weight: float = pow(max(1.0, deg), degree_bias)
		for j4: int in range(ns):
			var s: float = float(j4) / float(ns - 1)
			var g: float = exp(-pow(s - s_i, 2.0) / max(1e-6, pow(node_sigma_s, 2.0)))
			bias[j4] += float(side) * weight * g

	# Normalize bias to [-1,1]
	var max_abs: float = 0.0
	for j5: int in range(ns):
		max_abs = max(max_abs, abs(bias[j5]))
	if max_abs > 1e-6:
		for j6: int in range(ns):
			bias[j6] = clamp(bias[j6] / max_abs, -1.0, 1.0)

	# --- Build swept body
	var verts: PackedVector3Array = PackedVector3Array()
	var norms: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()  # Store binormal direction for wiggle
	var idx: PackedInt32Array = PackedInt32Array()

	# Ensure sufficient ring sides for smooth, watertight geometry
	var ks: int = max(12, ring_sides)  # Minimum 12 sides for better connections
	var twist: float = deg_to_rad(twist_degrees)

	for j7: int in range(ns):
		var s_val: float = float(j7) / float(ns - 1)
		var gauss: float = bulge_amp * exp(-pow(s_val - bulge_center, 2.0) / max(1e-6, pow(bulge_sigma, 2.0)))
		var a_s: float = a0 * pow(1.0 - s_val, taper_a_power) * (1.0 + gauss) * complexity_scale
		var b_s: float = b0 * pow(1.0 - s_val, taper_b_power) * (1.0 + gauss) * complexity_scale
		b_s *= (1.0 + asymmetry_amp * bias[j7])

		# Apply minimum radius constraint to prevent degenerate triangles
		var min_scaled_radius: float = min_radius * complexity_scale
		a_s = max(a_s, min_scaled_radius)
		b_s = max(b_s, min_scaled_radius)

		var phi: float = twist * s_val
		var cph: float = cos(phi)
		var sph: float = sin(phi)
		var Nrot: Vector3 = (N[j7] * cph) + (B[j7] * sph)
		var Brot: Vector3 = (-N[j7] * sph) + (B[j7] * cph)

		for i2: int in range(ks):
			var theta: float = TAU * float(i2) / float(ks)
			var ct: float = cos(theta)
			var st: float = sin(theta)
			var offset: Vector3 = (Nrot * (a_s * ct)) + (Brot * (b_s * st))
			var p_vert: Vector3 = C[j7] + offset

			verts.push_back(p_vert)

			var n_vec: Vector3 = (Nrot * (ct / max(1e-6, a_s))) + (Brot * (st / max(1e-6, b_s)))
			norms.push_back(n_vec.normalized())

			uvs.push_back(Vector2(float(i2) / float(ks), s_val))

			# Store Brot (binormal after twist) as color for wiggle direction
			# RGB stores the binormal vector, A stores body position
			colors.push_back(Color(Brot.x, Brot.y, Brot.z, s_val))

	# Side faces
	for j8: int in range(ns - 1):
		for i3: int in range(ks):
			var i0: int = j8 * ks + i3
			var i1: int = j8 * ks + ((i3 + 1) % ks)
			var i2t: int = (j8 + 1) * ks + i3
			var i3t: int = (j8 + 1) * ks + ((i3 + 1) % ks)
			idx.append_array(PackedInt32Array([i0, i2t, i3t, i0, i3t, i1]))

	# End caps - use exact spine position for perfect closure
	var head_c: int = verts.size()
	# Use exact spine center point to ensure cap is watertight
	verts.push_back(C[ns - 1])
	norms.push_back(T[ns - 1])
	uvs.push_back(Vector2(0.5, 1.0))
	# Head binormal (at s=1.0)
	var phi_head: float = twist * 1.0
	var Brot_head: Vector3 = (-N[ns - 1] * sin(phi_head)) + (B[ns - 1] * cos(phi_head))
	colors.push_back(Color(Brot_head.x, Brot_head.y, Brot_head.z, 1.0))
	# Connect to ring with consistent winding order
	for i4: int in range(ks):
		var a_idx: int = (ns - 1) * ks + i4
		var b_idx: int = (ns - 1) * ks + ((i4 + 1) % ks)
		idx.append_array(PackedInt32Array([head_c, a_idx, b_idx]))

	var tail_c: int = verts.size()
	# Use exact spine center point for watertight tail cap
	verts.push_back(C[0])
	norms.push_back(-T[0])
	uvs.push_back(Vector2(0.5, 0.0))
	# Tail binormal (at s=0.0)
	var Brot_tail: Vector3 = B[0]
	colors.push_back(Color(Brot_tail.x, Brot_tail.y, Brot_tail.z, 0.0))
	# Connect to ring with proper winding for backface
	for i5: int in range(ks):
		var a2_idx: int = ((i5 + 1) % ks)
		var b2_idx: int = i5
		idx.append_array(PackedInt32Array([tail_c, a2_idx, b2_idx]))

	# --- Optional tubes for non-spine edges
	if add_edge_tubes:
		var spine_set: Dictionary[String, bool] = {}
		for i6: int in range(path.size() - 1):
			var a_id: int = path[i6]
			var b_id: int = path[i6 + 1]
			spine_set["%s_%s" % [str(a_id), str(b_id)]] = true
			spine_set["%s_%s" % [str(b_id), str(a_id)]] = true

		# Anchor per node: project to nearest spine sample, offset along local B by bias
		var node_anchor: Dictionary[int, Vector3] = {}
		for idx_node2: int in range(nodes.size()):
			var nid3: int = nodes[idx_node2]
			var p2q: Vector2 = pos2d[nid3]
			var proj2: PolylineProjection = _project_point_to_polyline(p2q, poly_xy)
			var s_i2: float = 0.0 if total_xy_len <= 1e-6 else proj2.cum_length / total_xy_len
			var j_idx: int = clamp(int(round(s_i2 * float(ns - 1))), 0, ns - 1)
			var bofs: float = 0.15 * asymmetry_amp * bias[j_idx]
			node_anchor[nid3] = C[j_idx] + B[j_idx] * bofs

		for e_idx: int in range(graph.size()):
			var e: Vector2i = graph[e_idx]
			var au: int = e.x
			var bv: int = e.y
			if spine_set.has("%s_%s" % [str(au), str(bv)]):
				continue
			if not node_anchor.has(au) or not node_anchor.has(bv):
				continue
			var pa: Vector3 = node_anchor[au]
			var pb: Vector3 = node_anchor[bv]
			var scaled_tube_radius: float = tube_radius * complexity_scale * tube_overlap_factor
			_append_cylinder(verts, norms, uvs, colors, idx, pa, pb, scaled_tube_radius, tube_segments, ring_sides)

	# --- Add fins
	if add_fins:
		_add_fins(verts, norms, uvs, colors, idx, C, N, B, T, bias, ns, complexity_scale)

	# ==============================================
	# STEP 1: Rotate fish so spine aligns to X-axis
	# ==============================================
	var rotation_transform: Transform3D = _calculate_spine_alignment_transform(C, T)
	_apply_transform_to_geometry(verts, norms, colors, C, N, B, T, rotation_transform)

	# ==============================================
	# STEP 2: Build mesh with improved connectivity
	# ==============================================
	var mesh: ArrayMesh = _build_optimized_mesh(verts, norms, uvs, colors, idx)

	# Attach mesh to instance
	_mesh_instance.mesh = mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Store spine data for wiggle calculations (after rotation)
	_spine_curve = C
	_spine_normals = N
	_spine_binormals = B
	_spine_tangents = T
	_spine_bias = bias
	_spine_segments = ns

	# ==============================================
	# STEP 3: Position eyes on the rotated mesh
	# ==============================================
	_position_eyes(C, N, B, T, bias, ns)

	# ==============================================
	# STEP 4: Setup wiggle shader
	# ==============================================
	_setup_wiggle_shader()

	# --- Debug visualization
	if debug_mode:
		_render_debug_visualization(C, nodes, pos2d, graph, adj, path)

# ====================
# Debug Visualization
# ====================
func _render_debug_visualization(spine: PackedVector3Array, nodes: Array[int],
	pos2d: Dictionary, edges: Array[Vector2i], _adj: Dictionary, _path: Array[int]) -> void:
	var verts: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()

	# Draw spine
	for i: int in range(spine.size() - 1):
		verts.push_back(spine[i])
		verts.push_back(spine[i + 1])
		colors.push_back(debug_spine_color)
		colors.push_back(debug_spine_color)

	# Create 3D positions for nodes (using same projection as tubes)
	var node_pos_3d: Dictionary = {}
	var poly_xy: PackedVector2Array = PackedVector2Array()
	poly_xy.resize(spine.size())
	for j: int in range(spine.size()):
		poly_xy[j] = Vector2(spine[j].x, spine[j].y)

	var total_xy_len: float = _polyline_length(poly_xy)

	for idx_node: int in range(nodes.size()):
		var nid: int = nodes[idx_node]
		var p2: Vector2 = pos2d[nid]
		var proj: PolylineProjection = _project_point_to_polyline(p2, poly_xy)
		var s_i: float = 0.0 if total_xy_len <= 1e-6 else proj.cum_length / total_xy_len
		var j_idx: int = clamp(int(round(s_i * float(spine.size() - 1))), 0, spine.size() - 1)
		node_pos_3d[nid] = spine[j_idx]

	# Draw graph edges
	for e_idx: int in range(edges.size()):
		var e: Vector2i = edges[e_idx]
		if node_pos_3d.has(e.x) and node_pos_3d.has(e.y):
			verts.push_back(node_pos_3d[e.x])
			verts.push_back(node_pos_3d[e.y])
			colors.push_back(debug_edge_color)
			colors.push_back(debug_edge_color)

	# Draw nodes as small crosses
	var node_size: float = 0.1
	for idx_node2: int in range(nodes.size()):
		var nid2: int = nodes[idx_node2]
		if node_pos_3d.has(nid2):
			var p: Vector3 = node_pos_3d[nid2]
			# X cross
			verts.push_back(p + Vector3(-node_size, 0, 0))
			verts.push_back(p + Vector3(node_size, 0, 0))
			colors.push_back(debug_node_color)
			colors.push_back(debug_node_color)
			# Y cross
			verts.push_back(p + Vector3(0, -node_size, 0))
			verts.push_back(p + Vector3(0, node_size, 0))
			colors.push_back(debug_node_color)
			colors.push_back(debug_node_color)
			# Z cross
			verts.push_back(p + Vector3(0, 0, -node_size))
			verts.push_back(p + Vector3(0, 0, node_size))
			colors.push_back(debug_node_color)
			colors.push_back(debug_node_color)

	# Build debug mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors

	var debug_mesh: ArrayMesh = ArrayMesh.new()
	debug_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)

	var debug_mat: StandardMaterial3D = StandardMaterial3D.new()
	debug_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_mat.vertex_color_use_as_albedo = true
	debug_mat.disable_depth_test = true  # Always visible on top
	debug_mat.no_depth_test = true
	debug_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debug_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	_debug_mesh_instance = MeshInstance3D.new()
	_debug_mesh_instance.mesh = debug_mesh
	_debug_mesh_instance.set_surface_override_material(0, debug_mat)
	_debug_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_debug_mesh_instance.sorting_offset = 1000.0  # Render after everything else
	add_child(_debug_mesh_instance)

# =================
# Eye Positioning
# =================
func _position_eyes(C: PackedVector3Array, N: PackedVector3Array, B: PackedVector3Array,
	T: PackedVector3Array, bias: PackedFloat32Array, ns: int) -> void:
	if left_fish_eye == null or right_fish_eye == null:
		return

	# Get complexity scale for consistent sizing
	var complexity_scale: float = _calculate_complexity_scale()

	# Position eyes at ~90% along spine (near head)
	var eye_s: float = 0.90
	var j_eye: int = clamp(int(eye_s * float(ns - 1)), 0, ns - 1)

	# Get spine position
	var pos: Vector3 = C[j_eye]

	# Calculate body dimensions at this point (same as mesh generation)
	var s_val: float = float(j_eye) / float(ns - 1)
	var gauss: float = bulge_amp * exp(-pow(s_val - bulge_center, 2.0) / max(1e-6, pow(bulge_sigma, 2.0)))
	var a_s: float = a0 * pow(1.0 - s_val, taper_a_power) * (1.0 + gauss) * complexity_scale
	var b_s: float = b0 * pow(1.0 - s_val, taper_b_power) * (1.0 + gauss) * complexity_scale
	b_s *= (1.0 + asymmetry_amp * bias[j_eye])  # Apply asymmetry like the mesh does

	# Apply twist rotation (same as mesh generation)
	var phi: float = deg_to_rad(twist_degrees) * s_val
	var cph: float = cos(phi)
	var sph: float = sin(phi)
	var Nrot: Vector3 = (N[j_eye] * cph) + (B[j_eye] * sph)
	var Brot: Vector3 = (-N[j_eye] * sph) + (B[j_eye] * cph)

	# Choose angle for eye placement (45 degrees = upper-front-side)
	var eye_angle: float = PI * 0.25
	var ct: float = cos(eye_angle)
	var st: float = sin(eye_angle)

	# Use the exact same offset formula as mesh generation
	# This guarantees the eye is exactly on the surface
	var eye_offset: Vector3 = (Nrot * (a_s * ct)) + (Brot * (b_s * st))

	left_fish_eye.position = pos + eye_offset
	right_fish_eye.position = pos - eye_offset  # Mirror to other side

	# Orient eyes to look outward and forward
	left_fish_eye.look_at(pos + eye_offset.normalized() + T[j_eye], Brot)
	right_fish_eye.look_at(pos - eye_offset.normalized() + T[j_eye], Brot)

# ==============================================
# Mesh transformation and optimization functions
# ==============================================

# Calculate transform to align spine to X-axis
func _calculate_spine_alignment_transform(C: PackedVector3Array, _T: PackedVector3Array) -> Transform3D:
	if C.size() < 2:
		return Transform3D.IDENTITY

	# Get the average direction of the spine (from tail to head)
	var spine_direction: Vector3 = (C[C.size() - 1] - C[0]).normalized()

	# Calculate rotation to align spine_direction to X-axis (Vector3.RIGHT)
	var target_axis: Vector3 = Vector3.RIGHT

	# If already aligned, return identity
	if spine_direction.dot(target_axis) > 0.9999:
		return Transform3D.IDENTITY

	# Calculate rotation axis and angle
	var rotation_axis: Vector3 = spine_direction.cross(target_axis)
	if rotation_axis.length() < 0.0001:
		# Spine is opposite to X-axis, rotate 180 degrees around any perpendicular axis
		rotation_axis = Vector3.UP if abs(spine_direction.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
	else:
		rotation_axis = rotation_axis.normalized()

	var angle: float = acos(clamp(spine_direction.dot(target_axis), -1.0, 1.0))

	# Create rotation basis
	var rotation_basis: Basis = Basis(rotation_axis, angle)

	# Calculate centroid for rotation pivot
	var centroid: Vector3 = Vector3.ZERO
	for point in C:
		centroid += point
	centroid /= float(C.size())

	# Create transform: move to origin, rotate, move back
	var final_transform: Transform3D = Transform3D.IDENTITY
	final_transform.origin = centroid
	var rotate_transform: Transform3D = Transform3D(rotation_basis, Vector3.ZERO)
	var move_to_origin: Transform3D = Transform3D.IDENTITY
	move_to_origin.origin = -centroid

	return final_transform * rotate_transform * move_to_origin

# Apply transform to all geometry
func _apply_transform_to_geometry(verts: PackedVector3Array, norms: PackedVector3Array,
	colors: PackedColorArray, C: PackedVector3Array, N: PackedVector3Array,
	B: PackedVector3Array, T: PackedVector3Array, xform: Transform3D) -> void:

	# Transform vertices
	for i in range(verts.size()):
		verts[i] = xform * verts[i]

	# Transform normals (only rotation, no translation)
	for i in range(norms.size()):
		norms[i] = xform.basis * norms[i]

	# Transform color data (binormal directions)
	for i in range(colors.size()):
		var binormal: Vector3 = Vector3(colors[i].r, colors[i].g, colors[i].b)
		binormal = xform.basis * binormal
		colors[i] = Color(binormal.x, binormal.y, binormal.z, colors[i].a)

	# Transform spine data
	for i in range(C.size()):
		C[i] = xform * C[i]
		N[i] = xform.basis * N[i]
		B[i] = xform.basis * B[i]
		T[i] = xform.basis * T[i]

# Build mesh with optimized connectivity to reduce gaps
func _build_optimized_mesh(verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:

	# Weld nearby vertices to ensure watertight mesh
	var weld_result: Dictionary = _weld_vertices(verts, norms, uvs, colors, idx, 0.001)
	verts = weld_result["verts"]
	norms = weld_result["norms"]
	uvs = weld_result["uvs"]
	colors = weld_result["colors"]
	idx = weld_result["indices"]

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]   = verts
	arrays[Mesh.ARRAY_NORMAL]   = norms
	arrays[Mesh.ARRAY_TEX_UV]   = uvs
	arrays[Mesh.ARRAY_COLOR]    = colors
	arrays[Mesh.ARRAY_INDEX]    = idx

	var mesh: ArrayMesh = ArrayMesh.new()
	# Use PRIMITIVE_TRIANGLES with proper winding for solid, gap-free mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	return mesh

# Weld vertices that are very close together to ensure watertight mesh
func _weld_vertices(verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array,
	threshold: float) -> Dictionary:

	var vert_count: int = verts.size()
	if vert_count == 0:
		return {"verts": verts, "norms": norms, "uvs": uvs, "colors": colors, "indices": indices}

	# Build a mapping from old vertex indices to new ones
	var vert_remap: Array[int] = []
	vert_remap.resize(vert_count)
	var new_verts: PackedVector3Array = PackedVector3Array()
	var new_norms: PackedVector3Array = PackedVector3Array()
	var new_uvs: PackedVector2Array = PackedVector2Array()
	var new_colors: PackedColorArray = PackedColorArray()

	# For each vertex, check if it's close to an already processed vertex
	for i in range(vert_count):
		var found_match: bool = false
		var v: Vector3 = verts[i]

		# Check against already added vertices
		for j in range(new_verts.size()):
			if v.distance_squared_to(new_verts[j]) < threshold * threshold:
				# This vertex is close enough to merge
				vert_remap[i] = j
				found_match = true
				break

		if not found_match:
			# Add as new unique vertex
			vert_remap[i] = new_verts.size()
			new_verts.push_back(verts[i])
			new_norms.push_back(norms[i])
			new_uvs.push_back(uvs[i])
			new_colors.push_back(colors[i])

	# Remap indices
	var new_indices: PackedInt32Array = PackedInt32Array()
	for i in range(indices.size()):
		new_indices.push_back(vert_remap[indices[i]])

	return {
		"verts": new_verts,
		"norms": new_norms,
		"uvs": new_uvs,
		"colors": new_colors,
		"indices": new_indices
	}

# Setup the wiggle shader with all parameters
func _setup_wiggle_shader() -> void:
	var shader: Shader = load("res://Scenes/fish_wiggle.gdshader")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	_shader_material.set_shader_parameter("wiggle_amplitude", wiggle_amplitude)
	_shader_material.set_shader_parameter("wiggle_frequency", wiggle_frequency)
	_shader_material.set_shader_parameter("wiggle_speed", wiggle_speed)
	_shader_material.set_shader_parameter("tail_amplification", tail_amplification)
	_shader_material.set_shader_parameter("base_color", base_color)
	_shader_material.render_priority = 0

	# Apply shader to mesh
	if _mesh_instance and _mesh_instance.mesh:
		_mesh_instance.set_surface_override_material(0, _shader_material)

# Calculate wiggle offset for a given position along the spine
func _calculate_wiggle_offset(body_position: float, binormal: Vector3, up_direction: Vector3) -> Vector3:
	var time: float = Time.get_ticks_msec() / 1000.0

	# Calculate wiggle strength - stronger at the tail
	var wiggle_strength: float = wiggle_amplitude * (1.0 - body_position) * tail_amplification

	# Create traveling wave along the body
	var wave: float = sin(body_position * wiggle_frequency - time * wiggle_speed)

	# Apply wiggle along the binormal direction (side-to-side)
	var lateral_offset: Vector3 = binormal * wave * wiggle_strength

	# Vertical undulation along the up direction
	var vertical_wave: float = sin(body_position * wiggle_frequency * 0.5 - time * wiggle_speed * 0.7)
	var vertical_offset: Vector3 = up_direction * vertical_wave * wiggle_strength * 0.2

	return lateral_offset + vertical_offset

# Update eye positions to follow the wiggle animation
func _update_wiggling_eyes() -> void:
	if _spine_curve.size() == 0:
		return

	# Get complexity scale for consistent sizing
	var complexity_scale: float = _calculate_complexity_scale()

	var ns: int = _spine_segments
	var C: PackedVector3Array = _spine_curve
	var N: PackedVector3Array = _spine_normals
	var B: PackedVector3Array = _spine_binormals
	var T: PackedVector3Array = _spine_tangents
	var bias: PackedFloat32Array = _spine_bias

	# Position eyes at ~90% along spine (near head)
	var eye_s: float = 0.90
	var j_eye: int = clamp(int(eye_s * float(ns - 1)), 0, ns - 1)

	# Get spine position
	var pos: Vector3 = C[j_eye]

	# Calculate body dimensions at this point (same as mesh generation)
	var s_val: float = float(j_eye) / float(ns - 1)
	var gauss: float = bulge_amp * exp(-pow(s_val - bulge_center, 2.0) / max(1e-6, pow(bulge_sigma, 2.0)))
	var a_s: float = a0 * pow(1.0 - s_val, taper_a_power) * (1.0 + gauss) * complexity_scale
	var b_s: float = b0 * pow(1.0 - s_val, taper_b_power) * (1.0 + gauss) * complexity_scale
	b_s *= (1.0 + asymmetry_amp * bias[j_eye])

	# Apply twist rotation to get the correct binormal direction
	var phi: float = deg_to_rad(twist_degrees) * s_val
	var cph: float = cos(phi)
	var sph: float = sin(phi)
	var Nrot: Vector3 = (N[j_eye] * cph) + (B[j_eye] * sph)
	var Brot: Vector3 = (-N[j_eye] * sph) + (B[j_eye] * cph)

	# Calculate up direction (perpendicular to binormal and spine)
	var up_direction: Vector3 = Brot.cross(T[j_eye]).normalized()

	# Calculate wiggle offset using the proper binormal direction
	var wiggle_offset: Vector3 = _calculate_wiggle_offset(eye_s, Brot, up_direction)

	# Apply wiggle to base position
	var wiggled_pos: Vector3 = pos + wiggle_offset

	# Choose angle for eye placement
	var eye_angle: float = PI * 0.25
	var ct: float = cos(eye_angle)
	var st: float = sin(eye_angle)

	# Calculate eye offset
	var eye_offset: Vector3 = (Nrot * (a_s * ct)) + (Brot * (b_s * st))

	# Position eyes with wiggle applied
	left_fish_eye.position = wiggled_pos + eye_offset
	right_fish_eye.position = wiggled_pos - eye_offset

	# Orient eyes to look outward and forward
	left_fish_eye.look_at(wiggled_pos + eye_offset.normalized() + T[j_eye], Brot)
	right_fish_eye.look_at(wiggled_pos - eye_offset.normalized() + T[j_eye], Brot)

# =========================
# Graph helpers / BFS / FR
# =========================
func _collect_nodes(edges: Array[Vector2i]) -> Array[int]:
	var set_map: Dictionary[int, bool] = {}
	for i: int in range(edges.size()):
		var e: Vector2i = edges[i]
		set_map[e.x] = true
		set_map[e.y] = true
	return set_map.keys()

func _build_undirected_adjacency(edges: Array[Vector2i]) -> Dictionary:
	var adj: Dictionary = {}
	for i: int in range(edges.size()):
		var e: Vector2i = edges[i]
		if not adj.has(e.x):
			adj[e.x] = [] as Array[int]
		if not adj.has(e.y):
			adj[e.y] = [] as Array[int]
		adj[e.x].append(e.y)
		adj[e.y].append(e.x)
	return adj

func _bfs_farthest(start: int, adj: Dictionary) -> BFSResult:
	var q: Array[int] = [start]
	var dist: Dictionary[int, int] = {}
	dist[start] = 0
	var far: int = start
	while q.size() > 0:
		var x: int = q.pop_front()
		var nbrs: Array[int] = adj[x]
		for i: int in range(nbrs.size()):
			var y: int = nbrs[i]
			if not dist.has(y):
				dist[y] = dist[x] + 1
				q.push_back(y)
				if dist[y] > dist[far]:
					far = y
	return BFSResult.new(far, dist[far])

func _bfs_path(a: int, b: int, adj: Dictionary) -> Array[int]:
	var q: Array[int] = [a]
	var parent: Dictionary[int, int] = {}
	parent[a] = -1
	while q.size() > 0:
		var x: int = q.pop_front()
		if x == b:
			break
		var nbrs: Array[int] = adj[x]
		for i: int in range(nbrs.size()):
			var y: int = nbrs[i]
			if not parent.has(y):
				parent[y] = x
				q.push_back(y)
	if not parent.has(b):
		return []
	var path: Array[int] = []
	var cur: int = b
	while cur != -1:
		path.append(cur)
		cur = parent[cur]
	path.reverse()
	return path

func _force_layout_2d(nodes: Array[int], adj: Dictionary, iters: int, area: float) -> Dictionary:
	var n: float = float(nodes.size())
	var k: float = sqrt(area / max(1.0, n))
	var pos: Dictionary[int, Vector2] = {}
	var rnd: RandomNumberGenerator = RandomNumberGenerator.new()
	rnd.randomize()

	for i: int in range(nodes.size()):
		var idv: int = nodes[i]
		var rx: float = rnd.randf_range(-0.5, 0.5)
		var ry: float = rnd.randf_range(-0.5, 0.5)
		pos[idv] = Vector2(rx, ry)

	var Tstep: float = 0.1
	for _it: int in range(iters):
		var disp: Dictionary[int, Vector2] = {}
		for i2: int in range(nodes.size()):
			disp[nodes[i2]] = Vector2.ZERO

		# Repulsion
		for a_idx: int in range(nodes.size()):
			var a_id: int = nodes[a_idx]
			for b_idx: int in range(a_idx + 1, nodes.size()):
				var b_id: int = nodes[b_idx]
				var delta: Vector2 = pos[a_id] - pos[b_id]
				var d2: float = max(1e-6, delta.length_squared())
				var d: float = sqrt(d2)
				var force: float = (k * k) / d
				var dir: Vector2 = delta / d
				disp[a_id] = disp[a_id] + dir * force
				disp[b_id] = disp[b_id] - dir * force

		# Attraction (process each undirected edge once)
		for a_idx2: int in range(nodes.size()):
			var a_id2: int = nodes[a_idx2]
			var nbrs2: Array[int] = adj[a_id2]
			for j: int in range(nbrs2.size()):
				var b_id2: int = nbrs2[j]
				if a_id2 < b_id2:
					var delta2: Vector2 = pos[a_id2] - pos[b_id2]
					var d_at: float = max(1e-6, delta2.length())
					var force2: float = (d_at * d_at) / k
					var dir2: Vector2 = delta2 / d_at
					disp[a_id2] = disp[a_id2] - dir2 * force2
					disp[b_id2] = disp[b_id2] + dir2 * force2

		# Move & cool
		for i3: int in range(nodes.size()):
			var nid: int = nodes[i3]
			var dvec: Vector2 = disp[nid]
			var m: float = dvec.length()
			if m > 1e-9:
				pos[nid] = pos[nid] + dvec / m * min(Tstep, m)
		Tstep *= 0.96
	return pos

func _normalize_layout(pos: Dictionary[int, Vector2], scale_factor: float) -> void:
	var minx: float = INF
	var miny: float = INF
	var maxx: float = -INF
	var maxy: float = -INF
	for k: int in pos.keys():
		var v: Vector2 = pos[k]
		minx = min(minx, v.x)
		miny = min(miny, v.y)
		maxx = max(maxx, v.x)
		maxy = max(maxy, v.y)
	var sx: float = max(1e-6, maxx - minx)
	var sy: float = max(1e-6, maxy - miny)
	for k2: int in pos.keys():
		var v2: Vector2 = pos[k2]
		var nx: float = ((v2.x - minx) / sx - 0.5) * 2.0
		var ny: float = ((v2.y - miny) / sy - 0.5) * 2.0
		pos[k2] = Vector2(nx, ny) * scale_factor

# ================
# Geometry helpers
# ================
func _polyline_length(poly: PackedVector2Array) -> float:
	var total: float = 0.0
	for i: int in range(poly.size() - 1):
		total += poly[i].distance_to(poly[i + 1])
	return total

func _project_point_to_polyline(p: Vector2, poly: PackedVector2Array) -> PolylineProjection:
	var best_len: float = 0.0
	var best_dist2: float = INF
	var best_side: int = 1
	var cum: float = 0.0
	for i: int in range(poly.size() - 1):
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[i + 1]
		var ab: Vector2 = b - a
		var t: float = 0.0
		var ab2: float = ab.length_squared()
		if ab2 > 0.0:
			t = clamp(((p - a).dot(ab)) / ab2, 0.0, 1.0)
		var q: Vector2 = a.lerp(b, t)
		var d2: float = (p - q).length_squared()
		if d2 < best_dist2:
			best_dist2 = d2
			best_len = cum + ab.length() * t
			var cross_z: float = ab.x * (p.y - a.y) - ab.y * (p.x - a.x)
			best_side = 1 if cross_z >= 0.0 else -1
		cum += ab.length()
	return PolylineProjection.new(best_len, best_side)

func _rmf_frames(C: PackedVector3Array) -> Dictionary[StringName, PackedVector3Array]:
	var n: int = C.size()
	var T: PackedVector3Array = PackedVector3Array()
	var N: PackedVector3Array = PackedVector3Array()
	var B: PackedVector3Array = PackedVector3Array()

	T.resize(n)
	N.resize(n)
	B.resize(n)

	# initial tangent
	var t0: Vector3 = (C[1] - C[0]).normalized()
	var N0: Vector3 = Vector3.UP
	if abs(t0.dot(N0)) > 0.95:
		N0 = Vector3.RIGHT
	var B0: Vector3 = t0.cross(N0).normalized()
	N0 = B0.cross(t0).normalized()
	T[0] = t0
	N[0] = N0
	B[0] = B0

	for j: int in range(1, n):
		var tcur: Vector3
		if j < n - 1:
			tcur = (C[j + 1] - C[j]).normalized()
		else:
			tcur = (C[j] - C[j - 1]).normalized()
		var q: Quaternion = _quat_shortest_arc(T[j - 1], tcur)
		var bas: Basis = Basis(q)
		T[j] = tcur
		N[j] = (bas * N[j - 1]).normalized()
		B[j] = (bas * B[j - 1]).normalized()

	var out: Dictionary[StringName, PackedVector3Array] = {}
	out["T"] = T
	out["N"] = N
	out["B"] = B
	return out

func _quat_shortest_arc(from: Vector3, to: Vector3) -> Quaternion:
	var f: Vector3 = from.normalized()
	var t: Vector3 = to.normalized()
	var d: float = clamp(f.dot(t), -1.0, 1.0)
	if d > 0.9995:
		return Quaternion()
	if d < -0.9995:
		var axis: Vector3 = f.cross(Vector3(1.0, 0.0, 0.0))
		if axis.length() < 1e-6:
			axis = f.cross(Vector3(0.0, 1.0, 0.0))
		return Quaternion(axis.normalized(), PI)
	var axis2: Vector3 = f.cross(t).normalized()
	var angle: float = acos(d)
	return Quaternion(axis2, angle)

func _append_cylinder(verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray, idx: PackedInt32Array,
	a: Vector3, b: Vector3, r: float, segs: int, sides: int) -> void:
	var dir: Vector3 = (b - a).normalized()
	var up: Vector3 = Vector3.RIGHT if abs(dir.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var e1: Vector3 = dir.cross(up).normalized()
	var e2: Vector3 = dir.cross(e1).normalized()

	var offset: int = verts.size()
	for j: int in range(segs + 1):
		var s: float = float(j) / float(segs)
		var pos: Vector3 = a.lerp(b, s)
		for i: int in range(sides):
			var th: float = TAU * float(i) / float(sides)
			var circle: Vector3 = e1 * (r * cos(th)) + e2 * (r * sin(th))
			verts.push_back(pos + circle)
			norms.push_back(circle.normalized())
			uvs.push_back(Vector2(float(i) / float(sides), s))
			# Tubes use e2 as binormal and position at 0.5 (moderate wiggle)
			colors.push_back(Color(e2.x, e2.y, e2.z, 0.5))

	for j2: int in range(segs):
		for i2: int in range(sides):
			var i0: int = offset + j2 * sides + i2
			var i1: int = offset + j2 * sides + ((i2 + 1) % sides)
			var i2q: int = offset + (j2 + 1) * sides + i2
			var i3q: int = offset + (j2 + 1) * sides + ((i2 + 1) % sides)
			idx.append_array(PackedInt32Array([i0, i2q, i3q, i0, i3q, i1]))

	# caps
	var cap_a: int = verts.size()
	verts.push_back(a)
	norms.push_back(-dir)
	uvs.push_back(Vector2(0.5, 0.0))
	colors.push_back(Color(e2.x, e2.y, e2.z, 0.5))
	for i3: int in range(sides):
		var ri: int = offset + i3
		var rj: int = offset + ((i3 + 1) % sides)
		idx.append_array(PackedInt32Array([cap_a, rj, ri]))

	var cap_b: int = verts.size()
	verts.push_back(b)
	norms.push_back(dir)
	uvs.push_back(Vector2(0.5, 1.0))
	colors.push_back(Color(e2.x, e2.y, e2.z, 0.5))
	var base: int = offset + segs * sides
	for i4: int in range(sides):
		var ri2: int = base + i4
		var rj2: int = base + ((i4 + 1) % sides)
		idx.append_array(PackedInt32Array([cap_b, ri2, rj2]))

# Add fins to the fish mesh
func _add_fins(verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray, idx: PackedInt32Array,
	C: PackedVector3Array, N: PackedVector3Array, B: PackedVector3Array,
	T: PackedVector3Array, _bias: PackedFloat32Array, ns: int, complexity_scale: float) -> void:

	# Add dorsal fin (top of fish)
	_add_dorsal_fin(verts, norms, uvs, colors, idx, C, N, B, T, ns, complexity_scale)

	# Add pectoral fins (side fins)
	_add_pectoral_fins(verts, norms, uvs, colors, idx, C, N, B, T, ns, complexity_scale)

	# Add tail fin (caudal fin)
	_add_tail_fin(verts, norms, uvs, colors, idx, C, N, B, T, ns, complexity_scale)

# Add dorsal fin on top of the fish
func _add_dorsal_fin(verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray, idx: PackedInt32Array,
	C: PackedVector3Array, N: PackedVector3Array, B: PackedVector3Array,
	T: PackedVector3Array, ns: int, complexity_scale: float) -> void:

	var fin_idx: int = clamp(int(dorsal_fin_position * float(ns - 1)), 0, ns - 1)
	var base_pos: Vector3 = C[fin_idx]
	var fin_normal: Vector3 = N[fin_idx]
	var fin_binormal: Vector3 = B[fin_idx]
	var fin_tangent: Vector3 = T[fin_idx]

	var fin_height: float = dorsal_fin_size * complexity_scale
	var fin_width: float = dorsal_fin_size * 0.6 * complexity_scale

	# Calculate body radius at this position for attachment
	var s_val: float = float(fin_idx) / float(ns - 1)
	var body_radius: float = a0 * pow(1.0 - s_val, taper_a_power) * complexity_scale
	body_radius = max(body_radius, min_radius * complexity_scale)

	# Base attachment points on the body
	var base_center: Vector3 = base_pos + fin_normal * body_radius
	var base_front: Vector3 = base_center + fin_tangent * fin_width * 0.5
	var base_back: Vector3 = base_center - fin_tangent * fin_width * 0.5

	# Tip of the fin
	var fin_tip: Vector3 = base_center + fin_normal * fin_height

	# Create triangular fin mesh
	var offset: int = verts.size()

	# Add vertices
	verts.push_back(base_front)
	verts.push_back(base_back)
	verts.push_back(fin_tip)

	# Calculate normal for the fin (pointing to the side)
	var fin_face_normal: Vector3 = (fin_binormal * 0.3 + fin_normal * 0.7).normalized()

	# Add normals
	norms.push_back(fin_face_normal)
	norms.push_back(fin_face_normal)
	norms.push_back(fin_face_normal)

	# Add UVs
	uvs.push_back(Vector2(0.0, 0.0))
	uvs.push_back(Vector2(1.0, 0.0))
	uvs.push_back(Vector2(0.5, 1.0))

	# Add colors (use binormal for wiggle)
	colors.push_back(Color(fin_binormal.x, fin_binormal.y, fin_binormal.z, s_val))
	colors.push_back(Color(fin_binormal.x, fin_binormal.y, fin_binormal.z, s_val))
	colors.push_back(Color(fin_binormal.x, fin_binormal.y, fin_binormal.z, s_val))

	# Add triangles (both sides for double-sided fin)
	idx.append_array(PackedInt32Array([offset, offset + 1, offset + 2]))
	idx.append_array(PackedInt32Array([offset + 2, offset + 1, offset]))

# Add pectoral fins on the sides
func _add_pectoral_fins(verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray, idx: PackedInt32Array,
	C: PackedVector3Array, N: PackedVector3Array, B: PackedVector3Array,
	T: PackedVector3Array, ns: int, complexity_scale: float) -> void:

	var fin_idx: int = clamp(int(pectoral_fin_position * float(ns - 1)), 0, ns - 1)
	var base_pos: Vector3 = C[fin_idx]
	var _fin_normal: Vector3 = N[fin_idx]
	var fin_binormal: Vector3 = B[fin_idx]
	var fin_tangent: Vector3 = T[fin_idx]

	var fin_length: float = pectoral_fin_size * complexity_scale
	var fin_width: float = pectoral_fin_size * 0.5 * complexity_scale

	var s_val: float = float(fin_idx) / float(ns - 1)
	var body_radius: float = b0 * pow(1.0 - s_val, taper_b_power) * complexity_scale
	body_radius = max(body_radius, min_radius * complexity_scale)

	# Create fins on both sides
	for side in [-1, 1]:
		var side_dir: Vector3 = fin_binormal * float(side)

		# Base attachment on body
		var base_attach: Vector3 = base_pos + side_dir * body_radius
		var base_front: Vector3 = base_attach + fin_tangent * fin_width * 0.3
		var base_back: Vector3 = base_attach - fin_tangent * fin_width * 0.3

		# Fin extends outward and slightly back
		var fin_tip: Vector3 = base_attach + side_dir * fin_length - fin_tangent * fin_width * 0.2

		var offset: int = verts.size()

		# Add vertices
		verts.push_back(base_front)
		verts.push_back(base_back)
		verts.push_back(fin_tip)

		# Normal points in the side direction
		var fin_normal_vec: Vector3 = side_dir
		norms.push_back(fin_normal_vec)
		norms.push_back(fin_normal_vec)
		norms.push_back(fin_normal_vec)

		# UVs
		uvs.push_back(Vector2(0.0, 0.0))
		uvs.push_back(Vector2(1.0, 0.0))
		uvs.push_back(Vector2(0.5, 1.0))

		# Colors
		colors.push_back(Color(fin_binormal.x, fin_binormal.y, fin_binormal.z, s_val))
		colors.push_back(Color(fin_binormal.x, fin_binormal.y, fin_binormal.z, s_val))
		colors.push_back(Color(fin_binormal.x, fin_binormal.y, fin_binormal.z, s_val))

		# Triangles (both sides)
		if side > 0:
			idx.append_array(PackedInt32Array([offset, offset + 1, offset + 2]))
			idx.append_array(PackedInt32Array([offset + 2, offset + 1, offset]))
		else:
			idx.append_array(PackedInt32Array([offset, offset + 2, offset + 1]))
			idx.append_array(PackedInt32Array([offset + 1, offset + 2, offset]))

# Add tail fin at the end
func _add_tail_fin(verts: PackedVector3Array, norms: PackedVector3Array,
	uvs: PackedVector2Array, colors: PackedColorArray, idx: PackedInt32Array,
	C: PackedVector3Array, N: PackedVector3Array, B: PackedVector3Array,
	T: PackedVector3Array, _ns: int, complexity_scale: float) -> void:

	# Tail fin at the very end (index 0 is tail)
	var base_pos: Vector3 = C[0]
	var fin_normal: Vector3 = N[0]
	var fin_binormal: Vector3 = B[0]
	var fin_tangent: Vector3 = -T[0]  # Points away from body

	var fin_span: float = tail_fin_size * complexity_scale
	var fin_length: float = tail_fin_size * 0.8 * complexity_scale

	# Create fan-shaped tail fin
	var base_center: Vector3 = base_pos
	var base_top: Vector3 = base_center + fin_normal * fin_span * 0.5
	var base_bottom: Vector3 = base_center - fin_normal * fin_span * 0.5
	var tip_top: Vector3 = base_top + fin_tangent * fin_length
	var tip_bottom: Vector3 = base_bottom + fin_tangent * fin_length

	var offset: int = verts.size()

	# Add vertices for a more detailed tail fin
	verts.push_back(base_center)
	verts.push_back(base_top)
	verts.push_back(tip_top)
	verts.push_back(tip_bottom)
	verts.push_back(base_bottom)

	# Normals (perpendicular to fin surface)
	var tail_normal: Vector3 = fin_binormal
	for i in range(5):
		norms.push_back(tail_normal)

	# UVs
	uvs.push_back(Vector2(0.5, 0.0))
	uvs.push_back(Vector2(0.0, 0.0))
	uvs.push_back(Vector2(0.0, 1.0))
	uvs.push_back(Vector2(1.0, 1.0))
	uvs.push_back(Vector2(1.0, 0.0))

	# Colors (tail position)
	for i in range(5):
		colors.push_back(Color(fin_binormal.x, fin_binormal.y, fin_binormal.z, 0.0))

	# Create triangles (double-sided)
	# Top half
	idx.append_array(PackedInt32Array([offset, offset + 1, offset + 2]))
	idx.append_array(PackedInt32Array([offset + 2, offset + 1, offset]))
	# Bottom half
	idx.append_array(PackedInt32Array([offset, offset + 3, offset + 4]))
	idx.append_array(PackedInt32Array([offset + 4, offset + 3, offset]))


# ======================
# Movement Functions
# ======================

# Pick a random destination within the bounds
func _pick_new_destination() -> void:
	if bounds_shape == null:
		push_warning("No bounds_shape set for fish movement")
		is_moving = false
		return

	var shape: Shape3D = bounds_shape.shape
	if shape == null:
		push_warning("bounds_shape has no shape resource")
		is_moving = false
		return

	# Get a random position within the bounds
	var random_pos: Vector3
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		var size: Vector3 = box.size
		random_pos = Vector3(
			randf_range(-size.x / 2.0, size.x / 2.0),
			randf_range(-size.y / 2.0, size.y / 2.0),
			randf_range(-size.z / 2.0, size.z / 2.0)
		)
		# Transform to world space
		random_pos = bounds_shape.global_transform * random_pos
	elif shape is SphereShape3D:
		var sphere: SphereShape3D = shape as SphereShape3D
		# Generate random point in sphere
		var theta: float = randf() * TAU
		var phi: float = acos(2.0 * randf() - 1.0)
		var r: float = pow(randf(), 1.0 / 3.0) * sphere.radius
		random_pos = Vector3(
			r * sin(phi) * cos(theta),
			r * sin(phi) * sin(theta),
			r * cos(phi)
		)
		random_pos = bounds_shape.global_transform * random_pos
	else:
		# Default to a simple box if shape type is unknown
		random_pos = bounds_shape.global_position + Vector3(
			randf_range(-5.0, 5.0),
			randf_range(-5.0, 5.0),
			randf_range(-5.0, 5.0)
		)

	current_target = random_pos
	is_moving = true

# Move the fish toward the current target
func _move_toward_target(delta: float) -> void:
	var direction: Vector3 = (current_target - global_position).normalized()
	var distance: float = global_position.distance_to(current_target)

	# Check if we've arrived
	if distance < arrival_distance:
		_pick_new_destination()
		return

	# Move toward target
	var movement: Vector3 = direction * move_speed * delta
	global_position += movement

	# Orient the fish toward the target (but keep it upright)
	_orient_toward_target(direction, delta)

# Orient the fish to face the target without flipping upside down
func _orient_toward_target(direction: Vector3, delta: float) -> void:
	if direction.length_squared() < 0.001:
		return

	# Create a target basis that faces the direction but stays upright
	var forward: Vector3 = direction.normalized()
	var world_up: Vector3 = Vector3.UP

	# If forward is too close to straight up or down, adjust the reference up vector
	if abs(forward.dot(world_up)) > 0.95:
		world_up = Vector3.FORWARD

	# Calculate right and up vectors
	var right: Vector3 = forward.cross(world_up).normalized()
	var up: Vector3 = right.cross(forward).normalized()

	# Create target basis (Godot uses X-forward after our mesh rotation)
	var target_basis: Basis = Basis(forward, up, right)

	# Smoothly interpolate rotation
	var current_basis: Basis = global_transform.basis
	var new_basis: Basis = current_basis.slerp(target_basis, delta * 2.0)

	# Apply the new rotation
	global_transform.basis = new_basis

# Make the eyes look at the current target
func _make_eyes_look_at_target() -> void:
	if left_fish_eye == null or right_fish_eye == null:
		return

	# Get the target in global space
	var target_global: Vector3 = current_target

	# Make each eye look at the target
	if is_instance_valid(left_fish_eye):
		var left_dir: Vector3 = (target_global - left_fish_eye.global_position).normalized()
		if left_dir.length_squared() > 0.001:
			# Keep the eye roughly upright
			left_fish_eye.look_at(left_fish_eye.global_position + left_dir, Vector3.UP)

	if is_instance_valid(right_fish_eye):
		var right_dir: Vector3 = (target_global - right_fish_eye.global_position).normalized()
		if right_dir.length_squared() > 0.001:
			right_fish_eye.look_at(right_fish_eye.global_position + right_dir, Vector3.UP)

func _on_button_pressed() -> void:
	graph = mutate_graph.mutate_one(graph)
	render_graph()

# Grow the fish by mutating its graph
func grow() -> void:
	print("Fish growing! Age: ", age)
	graph = mutate_graph.mutate_one(graph)
	render_graph()
	# Re-pick destination after growth to avoid getting stuck
	if is_moving:
		_pick_new_destination()

	# Notify parent tank to recalculate capacity
	if is_in_tank:
		_notify_tank_of_growth()

# ======================
# Surface Behavior
# ======================

# Handle the fish surfacing behavior
func _handle_surface_behavior(delta: float) -> void:
	surface_timer += delta

	if is_surfacing:
		# Fish is currently at the surface
		if surface_timer >= surface_duration:
			_submerge()
	else:
		# Fish is underwater, check if it's time to surface
		if surface_timer >= next_surface_time:
			_surface()

# Make the fish surface (become visible and look up)
func _surface() -> void:
	is_surfacing = true
	visible = true
	surface_timer = 0.0

	# Apply upward rotation to look up slightly
	var current_basis: Basis = global_transform.basis
	var look_up_rotation: Basis = Basis(Vector3.FORWARD, deg_to_rad(-surface_look_angle))
	global_transform.basis = current_basis * look_up_rotation

# Make the fish submerge (become hidden and return to normal orientation)
func _submerge() -> void:
	is_surfacing = false
	visible = false
	surface_timer = 0.0

	# Schedule next surface time
	next_surface_time = randf_range(surface_interval_min, surface_interval_max)

	# Return to normal orientation (remove the upward tilt)
	var current_basis: Basis = global_transform.basis
	var look_down_rotation: Basis = Basis(Vector3.FORWARD, deg_to_rad(surface_look_angle))
	global_transform.basis = current_basis * look_down_rotation

# Notify the parent tank that this fish has grown
func _notify_tank_of_growth() -> void:
	if parent_tank and is_instance_valid(parent_tank):
		if parent_tank.has_method("recalculate_capacity"):
			print("Fish grew! Notifying tank to recalculate capacity")
			parent_tank.recalculate_capacity()
		else:
			print("Warning: Parent tank doesn't have recalculate_capacity method")
	else:
		print("Warning: Fish has no valid parent tank reference")
