extends Node3D

@onready var camera: Camera3D = get_viewport().get_camera_3d()
@export var ground_y := 0.0
@export var speed := 6.0


var target := Vector3.ZERO
var has_target := false

func _process(delta):
	if has_target:
		var pos := global_position
		var to  := Vector3(target.x, ground_y, target.z)
		var d   := to - pos
		if d.length() < 0.05:
			has_target = false
		else:
			global_position = pos + d.normalized() * speed * delta
			look_at(global_position + d.normalized(), Vector3.UP)
