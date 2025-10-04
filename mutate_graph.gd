class_name MutateGraph

# Public API ---------------------------------------------------------------

## Apply the production rule to every match in `graph`.
## Returns an array of mutated graphs (one per match).
func mutate(graph: Array[Vector2i]) -> Array:
	var results: Array = []
	var clean_graph: Array[Vector2i] = _unique_edges(graph)
	var triples: Array[Vector3i] = _find_matches(clean_graph) # each = (x, y, z) with y < z

	if triples.is_empty():
		return results

	var base_max: int = _max_node_id(clean_graph)

	for i in range(triples.size()):
		var t: Vector3i = triples[i]
		var x: int = t.x
		var y: int = t.y
		var z: int = t.z
		var w: int = base_max + i + 1  # fresh node per produced graph

		# Start from original graph, then replace LHS with RHS for this match
		var gcopy: Array[Vector2i] = clean_graph.duplicate()
		_remove_edge(gcopy, Vector2i(x, y))
		_remove_edge(gcopy, Vector2i(x, z))

		_add_unique(gcopy, Vector2i(x, z)) # restored as per RHS
		_add_unique(gcopy, Vector2i(x, w))
		_add_unique(gcopy, Vector2i(y, w))
		_add_unique(gcopy, Vector2i(z, w))

		results.append(gcopy)
	return results


## Convenience: randomly apply a single match or return the original graph if none.
func mutate_one(graph: Array[Vector2i]) -> Array[Vector2i]:
	var clean_graph: Array[Vector2i] = _unique_edges(graph)
	var triples: Array[Vector3i] = _find_matches(clean_graph)
	if triples.is_empty():
		return clean_graph

	var random_idx: int = randi() % triples.size()
	var t: Vector3i = triples[random_idx]
	var x: int = t.x
	var y: int = t.y
	var z: int = t.z
	var w: int = _max_node_id(clean_graph) + 1

	var gcopy: Array[Vector2i] = clean_graph.duplicate()
	_remove_edge(gcopy, Vector2i(x, y))
	_remove_edge(gcopy, Vector2i(x, z))
	_add_unique(gcopy, Vector2i(x, z))
	_add_unique(gcopy, Vector2i(x, w))
	_add_unique(gcopy, Vector2i(y, w))
	_add_unique(gcopy, Vector2i(z, w))
	return gcopy


# Internals ----------------------------------------------------------------

# Find all (x, y, z) such that (x,y) and (x,z) are edges, with y != z.
# We emit y < z to avoid duplicate permutations.
func _find_matches(graph: Array[Vector2i]) -> Array[Vector3i]:
	var adj: Dictionary = {} # Dictionary[int] -> PackedInt32Array of neighbors
	for i in range(graph.size()):
		var e: Vector2i = graph[i]
		if not adj.has(e.x):
			adj[e.x] = PackedInt32Array()
		var arr: PackedInt32Array = adj[e.x]
		arr.append(e.y)
		adj[e.x] = arr

	var triples: Array[Vector3i] = []
	var keys: Array = adj.keys()
	for ki in range(keys.size()):
		var x: int = int(keys[ki])
		var nbrs: PackedInt32Array = adj[x]
		nbrs = _unique_sorted_ints(nbrs)
		for i in range(nbrs.size()):
			for j in range(i + 1, nbrs.size()):
				var y: int = nbrs[i]
				var z: int = nbrs[j]
				triples.append(Vector3i(x, y, z))
	return triples


# Remove duplicates from edge list (treat edges as ordered pairs)
func _unique_edges(edges: Array[Vector2i]) -> Array[Vector2i]:
	var seen: Dictionary = {} # key:int -> true
	var out: Array[Vector2i] = []
	out.resize(0)
	for i in range(edges.size()):
		var e: Vector2i = edges[i]
		var k: int = _edge_key(e)
		if not seen.has(k):
			seen[k] = true
			out.append(e)
	return out


# Deterministic removal of the first occurrence of an edge (if present)
func _remove_edge(edges: Array[Vector2i], e: Vector2i) -> void:
	var key: int = _edge_key(e)
	for i in range(edges.size()):
		var cur: Vector2i = edges[i]
		if _edge_key(cur) == key:
			edges.remove_at(i)
			return


# Append only if not present
func _add_unique(edges: Array[Vector2i], e: Vector2i) -> void:
	var key: int = _edge_key(e)
	for i in range(edges.size()):
		if _edge_key(edges[i]) == key:
			return
	edges.append(e)


# Hash an ordered edge (a,b) into a 64-bit key (works for non-negative ids)
func _edge_key(e: Vector2i) -> int:
	# Shift a into high 32 bits, xor b in low 32 bits
	return (int(e.x) << 32) ^ int(e.y)


# Get maximum node id present (returns -1 if graph empty)
func _max_node_id(graph: Array[Vector2i]) -> int:
	var mx: int = -1
	for i in range(graph.size()):
		var e: Vector2i = graph[i]
		if e.x > mx:
			mx = e.x
		if e.y > mx:
			mx = e.y
	return mx


# Utilities for neighbor lists
func _unique_sorted_ints(arr: PackedInt32Array) -> PackedInt32Array:
	arr.sort()
	var out: PackedInt32Array = PackedInt32Array()
	out.resize(0)
	var last: int = -2147483648
	for i in range(arr.size()):
		var v: int = arr[i]
		if i == 0 or v != last:
			out.append(v)
			last = v
	return out
