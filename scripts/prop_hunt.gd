extends Node3D

@export var prop_name := "Prop"

func visual() -> MeshInstance3D:
	return $Visual as MeshInstance3D
