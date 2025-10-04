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
@export var graph: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(3, 4)]

@export var body_segments: int = 64
@export var ring_sides: int = 32
@export var body_length_scale: float = 1.0
@export var camber_z: float = 0.18
@export var twist_degrees: float = 14.0

@export var a0: float = 0.40
@export var b0: float = 0.34
@export var taper_a_power: float = 0.35
@export var taper_b_power: float = 0.20
@export var bulge_amp: float = 0.30
@export var bulge_center: float = 0.40
@export var bulge_sigma: float = 0.18

@export var asymmetry_amp: float = 0.22
@export var node_sigma_s: float = 0.20
@export var degree_bias: float = 0.60

@export var add_edge_tubes: bool = true
@export var tube_radius: float = 0.05
@export var tube_segments: int = 8

@export var layout_iterations: int = 120
@export var layout_area: float = 9.0

@export var base_color: Color = Color(0.78, 0.9, 1.0)

@export_group("Wiggle")
@export var wiggle_amplitude: float = 0.15
@export var wiggle_frequency: float = 2.0
@export var wiggle_speed: float = 1.5
@export var tail_amplification: float = 2.5

@export_group("Debug")
@export var debug_mode: bool = true
@export var debug_spine_color: Color = Color(1.0, 0.0, 0.0)
@export var debug_node_color: Color = Color(0.0, 1.0, 0.0)
@export var debug_edge_color: Color = Color(0.0, 0.5, 1.0)

@onready var left_fish_eye: Node3D = $LeftFishEye
@onready var right_fish_eye: Node3D = $RightFishEye

const TAU: float = PI * 2.0

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
	render_graph()

func _process(_delta: float) -> void:
	# Update eye positions to match the wiggle animation
	if _spine_curve.size() > 0 and left_fish_eye != null and right_fish_eye != null:
		_update_wiggling_eyes()

func render_graph() -> void:
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

	var ks: int = max(8, ring_sides)
	var twist: float = deg_to_rad(twist_degrees)

	for j7: int in range(ns):
		var s_val: float = float(j7) / float(ns - 1)
		var gauss: float = bulge_amp * exp(-pow(s_val - bulge_center, 2.0) / max(1e-6, pow(bulge_sigma, 2.0)))
		var a_s: float = a0 * pow(1.0 - s_val, taper_a_power) * (1.0 + gauss)
		var b_s: float = b0 * pow(1.0 - s_val, taper_b_power) * (1.0 + gauss)
		b_s *= (1.0 + asymmetry_amp * bias[j7])

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

	# End caps
	var head_c: int = verts.size()
	verts.push_back(C[ns - 1])
	norms.push_back(T[ns - 1])
	uvs.push_back(Vector2(0.5, 1.0))
	# Head binormal (at s=1.0)
	var phi_head: float = twist * 1.0
	var Brot_head: Vector3 = (-N[ns - 1] * sin(phi_head)) + (B[ns - 1] * cos(phi_head))
	colors.push_back(Color(Brot_head.x, Brot_head.y, Brot_head.z, 1.0))
	for i4: int in range(ks):
		var a_idx: int = (ns - 1) * ks + i4
		var b_idx: int = (ns - 1) * ks + ((i4 + 1) % ks)
		idx.append_array(PackedInt32Array([head_c, a_idx, b_idx]))

	var tail_c: int = verts.size()
	verts.push_back(C[0])
	norms.push_back(-T[0])
	uvs.push_back(Vector2(0.5, 0.0))
	# Tail binormal (at s=0.0)
	var Brot_tail: Vector3 = B[0]
	colors.push_back(Color(Brot_tail.x, Brot_tail.y, Brot_tail.z, 0.0))
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
			_append_cylinder(verts, norms, uvs, colors, idx, pa, pb, tube_radius, tube_segments, ring_sides)

	# --- Build ArrayMesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]   = verts
	arrays[Mesh.ARRAY_NORMAL]   = norms
	arrays[Mesh.ARRAY_TEX_UV]   = uvs
	arrays[Mesh.ARRAY_COLOR]    = colors
	arrays[Mesh.ARRAY_INDEX]    = idx

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Load and setup the wiggle shader
	var shader: Shader = load("res://Scenes/fish_wiggle.gdshader")
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	_shader_material.set_shader_parameter("wiggle_amplitude", wiggle_amplitude)
	_shader_material.set_shader_parameter("wiggle_frequency", wiggle_frequency)
	_shader_material.set_shader_parameter("wiggle_speed", wiggle_speed)
	_shader_material.set_shader_parameter("tail_amplification", tail_amplification)
	_shader_material.set_shader_parameter("base_color", base_color)

	# Set render mode
	_shader_material.render_priority = 0

	_mesh_instance.mesh = mesh
	_mesh_instance.set_surface_override_material(0, _shader_material)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Store spine data for wiggle calculations
	_spine_curve = C
	_spine_normals = N
	_spine_binormals = B
	_spine_tangents = T
	_spine_bias = bias
	_spine_segments = ns

	# --- Position eyes
	_position_eyes(C, N, B, T, bias, ns)

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

	# Position eyes at ~90% along spine (near head)
	var eye_s: float = 0.90
	var j_eye: int = clamp(int(eye_s * float(ns - 1)), 0, ns - 1)

	# Get spine position
	var pos: Vector3 = C[j_eye]

	# Calculate body dimensions at this point (same as mesh generation)
	var s_val: float = float(j_eye) / float(ns - 1)
	var gauss: float = bulge_amp * exp(-pow(s_val - bulge_center, 2.0) / max(1e-6, pow(bulge_sigma, 2.0)))
	var a_s: float = a0 * pow(1.0 - s_val, taper_a_power) * (1.0 + gauss)
	var b_s: float = b0 * pow(1.0 - s_val, taper_b_power) * (1.0 + gauss)
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
	var a_s: float = a0 * pow(1.0 - s_val, taper_a_power) * (1.0 + gauss)
	var b_s: float = b0 * pow(1.0 - s_val, taper_b_power) * (1.0 + gauss)
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


func _on_button_pressed() -> void:
	graph = mutate_graph.mutate(graph)[0]
	render_graph()
