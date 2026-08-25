extends CharacterBody3D

signal inspect_requested(actor: Node3D)

var udp := PacketPeerUDP.new()
var keys := {}
const SPEED := 2.5
const GRAVITY := 18.0
const FLOOR_Y := 0.45
const POSSESSION_LIFT := 0.3
const HEIGHT_SPEED := 1.5
const MAGE_PATH := "res://assets/kaykit_reference/Mage.glb"
const MOVEMENT_PATH := "res://assets/kaykit_reference/Rig_Medium_MovementBasic.glb"
const GENERAL_PATH := "res://assets/kaykit_reference/Rig_Medium_General.glb"
var character: Node3D
var animation_player: AnimationPlayer
var possessed_prop: Node3D
var prop_world: Node3D
var possessed_floor_offset := 0.0
var possessed_height := 0.0
var round_role := "hider"

func _ready() -> void:
	udp.bind(5005)
	character = (load(MAGE_PATH) as PackedScene).instantiate()
	character.scale = Vector3(0.42, 0.42, 0.42)
	add_child(character)
	var movement_source := (load(MOVEMENT_PATH) as PackedScene).instantiate()
	animation_player = (movement_source.get_node("AnimationPlayer") as AnimationPlayer).duplicate()
	character.add_child(animation_player)
	var general_source := (load(GENERAL_PATH) as PackedScene).instantiate()
	animation_player.add_animation_library("general", (general_source.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library("").duplicate())
	animation_player.play("general/Idle_A")
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.18
	shape.height = 0.75
	collision.shape = shape
	collision.position.y = 0.38
	add_child(collision)

func _physics_process(delta: float) -> void:
	while udp.get_available_packet_count() > 0:
		var data = JSON.parse_string(udp.get_packet().get_string_from_utf8())
		if data is Dictionary:
			var key := str(data.get("key", ""))
			var down := bool(data.get("down", false))
			_show_phone_input(key, down)
			if key == "e" and down and round_role == "hider":
				_toggle_possession()
			if key == "q" and down and round_role == "seeker":
				inspect_requested.emit(self)
			keys[key] = down
	if not is_on_floor(): velocity.y -= GRAVITY * delta
	else: velocity.y = -0.1
	if keys.get("jump", false) and is_on_floor(): velocity.y = 5.0
	var input := Vector3(float(keys.get("d", false)) - float(keys.get("a", false)), 0, float(keys.get("s", false)) - float(keys.get("w", false)))
	velocity.x = input.x * SPEED
	velocity.z = input.z * SPEED
	move_and_slide()
	if possessed_prop:
		var vertical_input := float(keys.get("up", false)) - float(keys.get("down", false))
		possessed_height = clamp(possessed_height + vertical_input * HEIGHT_SPEED * delta, possessed_floor_offset, 2.5)
		possessed_prop.position.y = possessed_height
	if input.length() > 0.1:
		character.rotation.y = lerp_angle(character.rotation.y, atan2(input.x, input.z), 0.15)
		if animation_player.current_animation != "Walking_A": animation_player.play("Walking_A", 0.15)
	elif animation_player.current_animation != "general/Idle_A":
		animation_player.play("general/Idle_A", 0.15)

func _toggle_possession() -> void:
	if possessed_prop:
		var source := possessed_prop.get_node("Visual") as MeshInstance3D
		possessed_prop.set_meta("is_hider", true)
		var bounds := source.mesh.get_aabb()
		var offset := -source.mesh.get_aabb().position.y * source.scale.y + 0.03
		var clearance: float = max(bounds.size.x * source.scale.x, bounds.size.z * source.scale.z) * 0.55 + 0.65
		# Return the real sofa to the map before revealing the Mage beside it.
		possessed_prop.reparent(prop_world, true)
		possessed_prop.global_position = Vector3(global_position.x, FLOOR_Y + offset, global_position.z)
		global_position = possessed_prop.global_position + Vector3(clearance, -offset, 0)
		_set_prop_collision(possessed_prop, true)
		possessed_prop = null
		character.visible = true
		return
	var closest: Node3D
	# The sofa is at its authored location; this one-screen test has no second
	# camera for Player 2, so it can be selected from the shared starting area.
	var closest_distance := 15.0
	for candidate in get_tree().get_nodes_in_group("possessable_prop"):
		var prop := candidate as Node3D
		var distance := global_position.distance_to(prop.global_position)
		if prop.visible and distance < closest_distance:
			closest = prop
			closest_distance = distance
	if closest == null:
		return
	global_position = Vector3(closest.global_position.x, global_position.y, closest.global_position.z)
	possessed_prop = closest
	possessed_prop.set_meta("is_hider", true)
	_set_prop_collision(possessed_prop, false)
	prop_world = possessed_prop.get_parent() as Node3D
	# Attach the actual prop to Player 2. This is more reliable than moving a
	# separate visual copy and guarantees it follows every controller movement.
	possessed_prop.reparent(self, false)
	var source := possessed_prop.get_node("Visual") as MeshInstance3D
	possessed_floor_offset = -source.mesh.get_aabb().position.y * source.scale.y + 0.03
	possessed_height = possessed_floor_offset + POSSESSION_LIFT
	possessed_prop.position = Vector3(0, possessed_height, 0)
	character.visible = false

func _set_prop_collision(prop: Node3D, enabled: bool) -> void:
	var body := prop.get_node_or_null("StaticBody3D") as StaticBody3D
	if body:
		body.collision_layer = 1 if enabled else 0
		body.collision_mask = 1 if enabled else 0

func _show_phone_input(key: String, down: bool) -> void:
	if not down:
		return
	var status := get_node_or_null("../Interface/Status") as Label
	if status:
		status.text = "Phone Player 2 input received: " + key.to_upper()

func set_round_role(new_role: String) -> void:
	round_role = new_role
