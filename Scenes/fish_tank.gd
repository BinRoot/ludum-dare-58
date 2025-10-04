extends Node3D

@export var width: float = 1
@export var height: float = 1
@export var row: int = ceil(Global.house_cell_size / 2)
@export var col: int = ceil(Global.house_cell_size / 2)

@export var bounds_shape: CollisionShape3D
