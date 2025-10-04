extends Node3D

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

# Attach to a Node3D, or run in an editor utility script
func _ready():
  var radius := 2            # hex face "radius" (center to corner)
  var length := 1.0           # how long you want it
  var mesh := CylinderMesh.new()
  mesh.top_radius = radius
  mesh.bottom_radius = radius
  mesh.height = length
  mesh.radial_segments = 6     # <- hexagon
  mesh.rings = 10              # more segments for smoother waves
  mesh.cap_top = true
  mesh.cap_bottom = true
  #mesh.smooth_faces = false    # crisp, flat hex sides (no rounding)

  var mi := MeshInstance3D.new()
  mi.mesh = mesh
  add_child(mi)

  # Apply wave shader
  var shader = load("res://Scenes/sea_wave.gdshader")
  var mat := ShaderMaterial.new()
  mat.shader = shader
  mi.set_surface_override_material(0, mat)
