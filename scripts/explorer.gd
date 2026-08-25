extends CharacterBody3D

const KNIGHT_PATH := "res://assets/kaykit_reference/Knight.glb"
const GENERAL_PATH := "res://assets/kaykit_reference/Rig_Medium_General.glb"
const MOVEMENT_PATH := "res://assets/kaykit_reference/Rig_Medium_MovementBasic.glb"
const WALK_SPEED := 2.0
const RUN_SPEED := 3.6
const ACCELERATION := 16.0
const GRAVITY := 18.0
const JUMP_VELOCITY := 5.2
const MOUSE_SENSITIVITY := 0.003

# These are positions of the actual exported house/furniture area in this pack.
const VILLAGE_START := Vector3(-35, 0.45, -123)
# The building itself occupies this low, central area.  The furniture source
# groups are placed above it by the original asset author, so they are not used
# as spawn points.
const HOUSE_INTERIOR := Vector3(-35, 0.45, -126)
const BATH_AND_LAUNDRY := Vector3(-39, 0.45, -129)

@onready var visual_mount: Node3D = $Visual
@onready var camera_pivot: Node3D = $CameraPivot

var character: Node3D
var animation_player: AnimationPlayer
var possessed_prop: Node3D
var possessed_visual: MeshInstance3D
var can_possess := true
var character_path := KNIGHT_PATH
var locally_controlled := true
var round_movement_locked := false
var footstep_cooldown := 0.0
var sound_player: AudioStreamPlayer
var mobile_move_input := Vector2.ZERO
var mobile_jump_requested := false
var prop_hover_seconds := 0.0
var replicated_prop: Node3D
var network_moving := false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var knight_scene := load(character_path) as PackedScene
	var movement_scene := load(MOVEMENT_PATH) as PackedScene
	var general_scene := load(GENERAL_PATH) as PackedScene
	if knight_scene == null or movement_scene == null or general_scene == null:
		push_error("KayKit comparison assets did not import yet.")
		return
	character = knight_scene.instantiate()
	visual_mount.add_child(character)
	visual_mount.scale = Vector3(0.42, 0.42, 0.42)
	var explorer_light := OmniLight3D.new()
	explorer_light.position = Vector3(0, 0.9, 0.3)
	explorer_light.light_color = Color(1.0, 0.84, 0.62)
	explorer_light.light_energy = 2.4
	explorer_light.omni_range = 6.0
	add_child(explorer_light)
	sound_player = AudioStreamPlayer.new()
	add_child(sound_player)
	var movement_source := movement_scene.instantiate()
	animation_player = (movement_source.get_node("AnimationPlayer") as AnimationPlayer).duplicate() as AnimationPlayer
	character.add_child(animation_player)
	movement_source.queue_free()
	var general_source := general_scene.instantiate()
	animation_player.add_animation_library("general", (general_source.get_node("AnimationPlayer") as AnimationPlayer).get_animation_library("").duplicate() as AnimationLibrary)
	general_source.queue_free()
	animation_player.play("general/Idle_A")

func _unhandled_input(event: InputEvent) -> void:
	if not locally_controlled or round_movement_locked:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_pivot.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-55.0), deg_to_rad(35.0))
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_toggle_possession()
		if event.keycode == KEY_1:
			_teleport_to(VILLAGE_START)
		elif event.keycode == KEY_2:
			_teleport_to(HOUSE_INTERIOR)
		elif event.keycode == KEY_3:
			_teleport_to(BATH_AND_LAUNDRY)

func _teleport_to(destination: Vector3) -> void:
	global_position = destination
	velocity = Vector3.ZERO

func set_mobile_move_input(value: Vector2) -> void:
	mobile_move_input = value.limit_length(1.0)

func mobile_camera_drag(delta: Vector2) -> void:
	camera_pivot.rotate_y(-delta.x * MOUSE_SENSITIVITY)
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x - delta.y * MOUSE_SENSITIVITY, deg_to_rad(-55.0), deg_to_rad(35.0))

func mobile_jump() -> void:
	mobile_jump_requested = true

func mobile_raise_or_lower(amount: float) -> void:
	if possessed_prop:
		global_position.y = clamp(global_position.y + amount, 0.35, 2.2)
		velocity.y = 0.0
		prop_hover_seconds = 0.35

func _toggle_possession() -> void:
	if not can_possess:
		return
	if possessed_prop:
		var prop_visual := possessed_prop.get_node("Visual") as MeshInstance3D
		var released_position := global_position
		released_position.y += _prop_floor_offset(prop_visual)
		possessed_prop.global_position = released_position
		# Reveal the character clear of the object rather than inside its mesh.
		var exit_direction := -camera_pivot.global_transform.basis.z
		exit_direction.y = 0.0
		exit_direction = exit_direction.normalized()
		var bounds := prop_visual.mesh.get_aabb()
		var prop_width: float = max(bounds.size.x * prop_visual.scale.x, bounds.size.z * prop_visual.scale.z)
		global_position = Vector3(released_position.x, global_position.y, released_position.z) + exit_direction * (prop_width * 0.55 + 0.65)
		possessed_prop.visible = true
		possessed_prop.set_meta("possessed_by", "")
		possessed_visual.queue_free()
		possessed_visual = null
		possessed_prop = null
		character.visible = true
		_play_tone(420.0, 0.08, 0.10)
		_notify_network_state_changed()
		return
	var closest: Node3D
	var closest_distance := 2.1
	for candidate in get_tree().get_nodes_in_group("possessable_prop"):
		var prop := candidate as Node3D
		if not str(prop.get_meta("possessed_by", "")).is_empty():
			continue
		var distance := global_position.distance_to(prop.global_position)
		if distance < closest_distance:
			closest = prop
			closest_distance = distance
	if closest == null:
		return
	global_position = closest.global_position
	possessed_prop = closest
	possessed_prop.set_meta("possessed_by", str(get_meta("network_player_id", "local")))
	possessed_prop.set_meta("is_hider", true)
	possessed_prop.visible = false
	possessed_visual = (possessed_prop.get_node("Visual") as MeshInstance3D).duplicate() as MeshInstance3D
	visual_mount.add_child(possessed_visual)
	# Prop models use different origins. Lift the copy by its real mesh bottom so
	# a sofa, chair, or barrel sits on the floor while the player controls it.
	possessed_visual.position = Vector3(0, _prop_floor_offset(possessed_visual), 0)
	character.visible = false
	_play_tone(760.0, 0.10, 0.12)
	_notify_network_state_changed()

func get_network_state() -> Dictionary:
	var visual_rotation := 0.0
	if character:
		visual_rotation = character.global_rotation.y
	return {
		"position": global_position,
		"rotation_y": visual_rotation,
		"moving": velocity.length() > 0.12,
		"possessed_prop": possessed_prop.name if possessed_prop else "",
		"prop_position": global_position,
	}

func apply_network_state(state: Dictionary, owner_id: String) -> void:
	var target_position := state.get("position", global_position) as Vector3
	global_position = global_position.lerp(target_position, 0.68)
	network_moving = bool(state.get("moving", false))
	if character:
		character.global_rotation.y = float(state.get("rotation_y", character.global_rotation.y))
	var next_prop_name := str(state.get("possessed_prop", ""))
	if replicated_prop and (next_prop_name.is_empty() or replicated_prop.name != next_prop_name):
		replicated_prop.set_meta("possessed_by", "")
		replicated_prop.visible = true
		replicated_prop = null
	if next_prop_name.is_empty():
		if character:
			character.visible = true
		return
	var prop := get_tree().root.find_child(next_prop_name, true, false) as Node3D
	if prop == null:
		return
	replicated_prop = prop
	prop.global_position = state.get("prop_position", global_position) as Vector3
	prop.set_meta("possessed_by", owner_id)
	prop.set_meta("is_hider", true)
	# Remote machines render the real prop at its synced position; the hidden
	# character is only a local representation of the hider inside it.
	prop.visible = true
	if character:
		character.visible = false

func _notify_network_state_changed() -> void:
	var game := get_parent()
	if game and game.has_method("_network_send_local_state"):
		game.call_deferred("_network_send_local_state")

func _prop_floor_offset(visual: MeshInstance3D) -> float:
	if visual.mesh == null:
		return 0.0
	var bounds := visual.mesh.get_aabb()
	return -bounds.position.y * visual.scale.y + 0.03

func _physics_process(delta: float) -> void:
	footstep_cooldown = max(footstep_cooldown - delta, 0.0)
	prop_hover_seconds = max(prop_hover_seconds - delta, 0.0)
	if not locally_controlled:
		if animation_player:
			var remote_clip := "Walking_A" if network_moving else "general/Idle_A"
			if animation_player.current_animation != remote_clip:
				animation_player.play(remote_clip, 0.15)
		return
	if prop_hover_seconds > 0.0:
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
		if Input.is_key_pressed(KEY_SPACE) or mobile_jump_requested:
			velocity.y = JUMP_VELOCITY
	mobile_jump_requested = false
	var input_x := float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A))
	var input_z := float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	var input_vector := (Vector2(input_x, input_z) + mobile_move_input).limit_length(1.0)
	var direction := Vector3.ZERO
	if input_vector.length() > 0.0:
		var forward := -camera_pivot.global_transform.basis.z
		var right := camera_pivot.global_transform.basis.x
		forward.y = 0.0
		right.y = 0.0
		direction = (right.normalized() * input_vector.x + forward.normalized() * input_vector.y).normalized()
	var speed := RUN_SPEED if Input.is_key_pressed(KEY_SHIFT) else WALK_SPEED
	velocity.x = move_toward(velocity.x, direction.x * speed, ACCELERATION * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, ACCELERATION * delta)
	move_and_slide()
	if direction.length() > 0.1:
		character.global_rotation.y = lerp_angle(character.global_rotation.y, atan2(direction.x, direction.z), 0.15)
		var clip := "Running_A" if speed == RUN_SPEED else "Walking_A"
		if animation_player.current_animation != clip:
			animation_player.play(clip, 0.15)
		if is_on_floor() and footstep_cooldown <= 0.0:
			_play_tone(125.0 if speed == WALK_SPEED else 155.0, 0.035, 0.035)
			footstep_cooldown = 0.42 if speed == WALK_SPEED else 0.28
	elif animation_player.current_animation != "general/Idle_A":
		animation_player.play("general/Idle_A", 0.15)

func _play_tone(frequency: float, duration: float, volume: float) -> void:
	if sound_player == null:
		return
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 22050.0
	stream.buffer_length = max(duration + 0.05, 0.12)
	sound_player.stream = stream
	sound_player.play()
	var playback := sound_player.get_stream_playback()
	if playback:
		var samples := int(stream.mix_rate * duration)
		for sample_index in range(samples):
			var fade := 1.0 - float(sample_index) / float(samples)
			var sample := sin(TAU * frequency * float(sample_index) / stream.mix_rate) * volume * fade
			playback.push_frame(Vector2(sample, sample))
