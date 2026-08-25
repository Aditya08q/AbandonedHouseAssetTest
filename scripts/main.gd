extends Node3D

const PLAYER_SCENE := preload("res://scenes/explorer.tscn")
const HOUSE_PATH := "res://assets/abandoned_house/Abandoned_House/Models/Abandoned_House.glb"
const PROP_HUNT_SCRIPT := preload("res://scripts/prop_hunt.gd")
const PHONE_PLAYER_SCRIPT := preload("res://scripts/phone_player.gd")
const ROUND_RULES_SCRIPT := preload("res://scripts/round_rules.gd")
const BACKGROUND_MUSIC_PATH := "res://assets/audio/background_soft_piano.mp3"
const MOBILE_UI_PATH := "res://assets/ui/mobile/"
const HIDDEN_WORLD_GROUPS := ["grass", "Vecindario", "Casa.005", "Cylinder", "Cylinder.001", "Reseptor_Señal"]
# Open floor at the house entrance, verified as the original player spawn.
const HOUSE_ENTRANCE := Vector3(-35, 0.45, -123)
const CUBE_DEMO_ONLY := false
# One-screen test aid. Set false before a real round: hider arrows then stay private.
const SHOW_HIDER_ARROWS_FOR_SINGLE_SCREEN_TEST := true
const SOLO_ROLE_TEST := true
const HIDING_SECONDS := 10.0
const LAN_PORT := 7000
const LAN_DISCOVERY_PORT := 7001
const NETWORK_STATE_INTERVAL := 0.05
var seeker_attempts := 12
var seeker_mode := false
var solo_hider: Node3D
var hider_choice: Node3D
var hider_marker: Node3D
var phase := "Lobby"
var phase_seconds := 0.0
var announcement_seconds := 0.0
var background_music: AudioStreamPlayer
var music_target_db := -15.0
var mobile_hud: Control
var mobile_joystick_nub: TextureRect
var mobile_action_button: TextureButton
var mobile_action_label: Label
var mobile_up_button: TextureButton
var mobile_down_button: TextureButton
var mobile_menu_button: TextureButton
var mobile_joystick_touch := -1
var mobile_camera_touch := -1
var mobile_ui_test_enabled := false
var desktop_player: CharacterBody3D
var phone_player: CharacterBody3D
var player_roles: Dictionary = {}
var round_rules := ROUND_RULES_SCRIPT.new()
var player_avatars: Dictionary = {}
var active_local_player_id := "Player 1"
var lan_peer: ENetMultiplayerPeer
var lan_active := false
var lan_host := false
var lan_player_names: Dictionary = {}
var lan_state_elapsed := 0.0
var lan_round_elapsed := 0.0
var lan_joined := false
var lan_local_name := ""
var lan_discovery: PacketPeerUDP
var lan_discovery_elapsed := 0.0
var lan_discovered_address := ""
var lan_discovered_host_name := ""
var lan_scan_active := false
var lan_scan_next_host := 1
const ACTIVE_PLAYER_IDS: Array[String] = ["Player 1", "Player 2"]
@onready var round_info: Label = $Interface/RoundInfo
@onready var role_info: Label = $Interface/RoleInfo
@onready var status: Label = $Interface/Status
@onready var timer_label: Label = $Interface/Timer
@onready var lobby_info: Label = $Interface/LobbyInfo
@onready var add_request_button: Button = $Interface/AddRequest
@onready var accept_button: Button = $Interface/Accept
@onready var reject_button: Button = $Interface/Reject
@onready var remove_button: Button = $Interface/Remove
@onready var start_round_button: Button = $Interface/StartRound
@onready var player_select: OptionButton = $Interface/PlayerSelect
@onready var remove_confirm: ConfirmationDialog = $Interface/RemoveConfirm
@onready var hider_guide_button: Button = $Interface/HiderGuideButton
@onready var hider_guide_panel: Control = $Interface/HiderGuidePanel
@onready var hider_guide_close: Button = $Interface/HiderGuidePanel/Close
@onready var game_info_button: Button = $Interface/GameInfoButton
@onready var host_lobby_button: Button = $Interface/HostLobbyButton
@onready var round_banner: Control = $Interface/RoundBanner
@onready var round_banner_message: Label = $Interface/RoundBanner/Message
@onready var end_screen: Control = $Interface/EndScreen
@onready var end_winner: Label = $Interface/EndScreen/Winner
@onready var next_round_button: Button = $Interface/EndScreen/NextRound
@onready var lan_host_button: Button = $Interface/LanPanel/Host
@onready var lan_join_button: Button = $Interface/LanPanel/Join
@onready var lan_address: LineEdit = $Interface/LanPanel/Address
@onready var lan_name: LineEdit = $Interface/LanPanel/Name
@onready var lan_info: Label = $Interface/LanPanel/Info

func _process(delta: float) -> void:
	if background_music:
		background_music.volume_db = move_toward(background_music.volume_db, music_target_db, delta * 5.0)
	_process_lan_discovery(delta)
	if lan_active:
		_network_process(delta)
		if not lan_host:
			return
	if phase == "Lobby":
		timer_label.text = "Round timer: waiting for Host to start the game"
	elif phase != "Finished":
		phase_seconds = max(phase_seconds - delta, 0.0)
		timer_label.text = "%s phase: %ds · N skips to seeking for testing" % [phase, ceili(phase_seconds)]
		if phase == "Hiding":
			_show_round_banner("HIDERS HIDE — %ds\nSEEKER LOCKED" % ceili(phase_seconds))
		elif announcement_seconds > 0.0:
			announcement_seconds = max(announcement_seconds - delta, 0.0)
			if announcement_seconds <= 0.0:
				round_banner.hide()
	for lantern in get_tree().get_nodes_in_group("atmosphere_lantern"):
		var light := lantern as OmniLight3D
		var base_energy := float(light.get_meta("base_energy", 1.0))
		light.light_energy = base_energy * (0.9 + sin(Time.get_ticks_msec() * 0.007 + light.position.x) * 0.1)
	if phase != "Lobby" and phase != "Finished" and phase_seconds <= 0.0:
		if phase == "Hiding":
			_start_seeking()
		else:
			_finish_round("Hider wins — seeker time expired.")

func _ready() -> void:
	# One seeker is selected randomly; every other active player is a hider.
	round_rules.accepted_players = ["Player 1"]
	add_request_button.pressed.connect(_add_test_join_request)
	accept_button.pressed.connect(_accept_next_request)
	reject_button.pressed.connect(_reject_next_request)
	remove_button.pressed.connect(_remove_last_player)
	player_select.item_selected.connect(_on_player_selected)
	remove_confirm.confirmed.connect(_confirm_remove_player)
	start_round_button.pressed.connect(_start_host_round)
	hider_guide_button.pressed.connect(_toggle_hider_guide)
	hider_guide_close.pressed.connect(_hide_hider_guide)
	game_info_button.pressed.connect(_toggle_game_info)
	host_lobby_button.pressed.connect(_toggle_host_lobby)
	next_round_button.pressed.connect(_start_next_round)
	lan_host_button.pressed.connect(_start_lan_host)
	lan_join_button.pressed.connect(_join_lan_host)
	multiplayer.peer_connected.connect(_on_lan_peer_connected)
	multiplayer.peer_disconnected.connect(_on_lan_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_lan_connected_to_server)
	multiplayer.connection_failed.connect(_on_lan_connection_failed)
	multiplayer.server_disconnected.connect(_on_lan_server_disconnected)
	_set_game_info_visible(false)
	_set_host_lobby_visible(false)
	_update_lobby_display()
	_setup_background_music()
	_setup_mobile_controls()
	_setup_lan_discovery()
	lan_name.text = "Player"
	lan_info.text = "Nearby room search is on. Host a room or wait for one to appear."
	lan_join_button.disabled = true
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("02050d")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("283c6c")
	settings.ambient_light_energy = 0.32
	settings.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	settings.glow_enabled = not OS.has_feature("mobile")
	settings.glow_intensity = 0.9
	settings.fog_enabled = true
	settings.fog_light_color = Color("0c1630")
	settings.fog_light_energy = 0.55
	settings.fog_density = 0.0035
	environment.environment = settings
	add_child(environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 35, 0)
	sun.light_color = Color("7799df")
	sun.light_energy = 0.55
	sun.shadow_enabled = not OS.has_feature("mobile")
	add_child(sun)

	# Small warm pools of light keep the dark map explorable and mark the house area.
	_add_lantern(Vector3(-30, 6.0, -124), 2.2, 15.0)
	_add_lantern(Vector3(-36, 8.2, -128), 2.0, 12.0)
	_add_lantern(Vector3(-40, 6.0, -130), 1.7, 10.0)
	_add_lantern(Vector3(-34, 3.0, -126), 1.35, 7.0)
	_add_lantern(Vector3(-38, 3.0, -128), 1.2, 6.0)
	_add_lantern(Vector3(-41, 3.0, -131), 1.15, 6.0)

	var house_scene := load(HOUSE_PATH) as PackedScene
	if house_scene == null:
		push_error("Abandoned House GLB did not import yet.")
		return
	var house := house_scene.instantiate() as Node3D
	add_child(house)
	if CUBE_DEMO_ONLY:
		house.visible = false
	else:
		_hide_non_playable_world(house)
		_add_collision_to_meshes(house)
	_add_prop_hunt_candidates(house)
	status.text = "Hiding phase — Player 2 is hiding. Player 1 waits for seeking phase."
	print("House bounds: ", _get_house_bounds(house))

	var safety_floor := StaticBody3D.new()
	safety_floor.position = Vector3(-35, -4.7, -130)
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(60, 0.2, 60)
	floor_collision.shape = floor_shape
	safety_floor.add_child(floor_collision)
	add_child(safety_floor)

	desktop_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	desktop_player.position = HOUSE_ENTRANCE
	add_child(desktop_player)
	player_avatars["Player 1"] = desktop_player
	if not SOLO_ROLE_TEST:
		phone_player = CharacterBody3D.new()
		phone_player.name = "PhonePlayer"
		phone_player.position = HOUSE_ENTRANCE
		phone_player.set_script(PHONE_PLAYER_SCRIPT)
		add_child(phone_player)
		phone_player.inspect_requested.connect(_inspect_nearby_prop.bind(phone_player))
	_assign_locked_roles()
	# The shared Mac screen needs this test-only target marker.
	for marker in get_tree().get_nodes_in_group("hider_marker"):
		marker.visible = SHOW_HIDER_ARROWS_FOR_SINGLE_SCREEN_TEST
	_update_active_role_view()

func _add_test_join_request() -> void:
	if lan_active:
		status.text = "Real players join from their own phone using the host Wi-Fi IP."
		return
	for slot_number in range(2, 7):
		var player_id := "Player %d" % slot_number
		if not player_id in round_rules.pending_players and not player_id in round_rules.accepted_players:
			round_rules.request_join(player_id)
			status.text = player_id + " requested to join. Host decide: Accept or Reject."
			break
	_update_lobby_display()

func _accept_next_request() -> void:
	print("LAN ACCEPT clicked; pending=", round_rules.pending_players, " accepted=", round_rules.accepted_players)
	if round_rules.pending_players.is_empty():
		status.text = "No pending player request to accept."
		return
	var player_id := round_rules.pending_players[0]
	if not round_rules.host_accept(player_id):
		status.text = "Could not accept " + _player_label(player_id) + "."
		return
	status.text = player_id + " accepted by host."
	print("LAN ACCEPTED player id=", player_id)
	round_banner.hide()
	_update_lobby_display()
	if lan_active:
		# Send the decision directly to the joining phone first, then refresh
		# every connected client's lobby view.
		rpc_id(int(player_id), "_client_receive_lobby", round_rules.accepted_players, round_rules.pending_players, lan_player_names)
		_network_broadcast_lobby()

func _reject_next_request() -> void:
	if round_rules.pending_players.is_empty():
		return
	var player_id := round_rules.pending_players[0]
	round_rules.host_reject(player_id)
	status.text = player_id + " rejected by host."
	round_banner.hide()
	_update_lobby_display()
	if lan_active:
		_network_reject_or_remove_peer(player_id, "Join request rejected by host.")

func _remove_last_player() -> void:
	if player_select.selected < 1:
		return
	remove_confirm.popup_centered()

func _on_player_selected(index: int) -> void:
	remove_button.visible = index > 0

func _confirm_remove_player() -> void:
	if player_select.selected < 1:
		return
	var player_id: String = player_select.get_item_text(player_select.selected)
	round_rules.host_remove(player_id)
	status.text = player_id + " removed by host."
	_update_lobby_display()
	if lan_active:
		_network_reject_or_remove_peer(player_id, "You were removed by the host.")

func _start_host_round() -> void:
	if lan_active and not lan_host:
		status.text = "Only the host can start a round."
		return
	if round_rules.accepted_players.size() < round_rules.MIN_PLAYERS:
		status.text = "Need at least 2 accepted players to start."
		return
	player_roles = round_rules.assign_roles(round_rules.accepted_players)
	music_target_db = -15.0
	_spawn_accepted_players()
	phase = "Hiding"
	phase_seconds = HIDING_SECONDS
	end_screen.hide()
	for player_id in player_avatars:
		var avatar: CharacterBody3D = player_avatars[player_id]
		avatar.round_movement_locked = str(player_roles.get(player_id, "")) == "seeker"
	_update_active_role_view()
	role_info.text = "ROUND STARTED · roles locked · " + str(player_roles)
	status.text = "Host started the round. Hiders have 10 seconds to hide."
	_update_lobby_display()
	if lan_active:
		_set_host_lobby_visible(false)
		_network_send_round_start()

func _spawn_accepted_players() -> void:
	for index in range(round_rules.accepted_players.size()):
		var player_id: String = round_rules.accepted_players[index]
		var avatar: CharacterBody3D = player_avatars.get(player_id)
		if avatar == null:
			avatar = PLAYER_SCENE.instantiate() as CharacterBody3D
			avatar.character_path = _character_for_network_player(player_id, index)
			avatar.position = HOUSE_ENTRANCE + Vector3(1.4 * index, 0, 1.5)
			add_child(avatar)
			player_avatars[player_id] = avatar
		avatar.set("can_possess", str(player_roles.get(player_id, "")) == "hider")
		avatar.locally_controlled = player_id == active_local_player_id
		avatar.get_node("CameraPivot/CameraSpring/Camera").current = player_id == active_local_player_id

func _select_local_player(slot: int) -> void:
	var player_id := "Player %d" % slot
	if not player_avatars.has(player_id):
		return
	active_local_player_id = player_id
	for id in player_avatars:
		var avatar: CharacterBody3D = player_avatars[id]
		var active: bool = id == player_id
		avatar.locally_controlled = active
		avatar.get_node("CameraPivot/CameraSpring/Camera").current = active
	_update_active_role_view()

func _update_active_role_view() -> void:
	var role := str(player_roles.get(active_local_player_id, "hider"))
	_refresh_hider_arrow_visibility()
	hider_guide_button.visible = role == "hider"
	if role != "hider":
		hider_guide_panel.hide()
	status.text = "Controlling " + active_local_player_id + " (" + role.to_upper() + ")"
	_update_mobile_controls_for_role()

func _toggle_hider_guide() -> void:
	if str(player_roles.get(active_local_player_id, "")) != "hider":
		return
	hider_guide_panel.visible = not hider_guide_panel.visible

func _hide_hider_guide() -> void:
	hider_guide_panel.hide()

func _refresh_hider_arrow_visibility() -> void:
	# Each player sees arrows only while their own locked role is Hider.
	# Selecting a different local test player simulates that player's private view.
	var arrows_visible := str(player_roles.get(active_local_player_id, "")) == "hider"
	for marker in get_tree().get_nodes_in_group("hider_marker"):
		marker.visible = arrows_visible

func _show_round_banner(message: String, seconds := 0.0) -> void:
	round_banner_message.text = message
	round_banner.show()
	announcement_seconds = seconds

func _toggle_game_info() -> void:
	_set_game_info_visible(not $Interface/GameInfoFrame.visible)

func _set_game_info_visible(is_visible: bool) -> void:
	for node_name in ["GameInfoFrame", "Title", "Help", "Note", "RoundInfo", "RoleInfo", "PropHelp", "Timer", "Status"]:
		$Interface.get_node(node_name).visible = is_visible
	game_info_button.text = "Close Info" if is_visible else "Game Info"

func _toggle_host_lobby() -> void:
	_set_host_lobby_visible(not $Interface/LobbyFrame.visible)

func _set_host_lobby_visible(is_visible: bool) -> void:
	if lan_active and not lan_host:
		is_visible = false
	for node_name in ["LobbyFrame", "LobbyInfo", "AddRequest", "Accept", "Reject", "PlayerSelect", "Remove", "StartRound"]:
		$Interface.get_node(node_name).visible = is_visible
	if not is_visible:
		remove_confirm.hide()
	host_lobby_button.text = "Close Lobby" if is_visible else "Host Lobby"

func _update_lobby_display() -> void:
	var accepted_labels: Array[String] = []
	for player_id in round_rules.accepted_players:
		accepted_labels.append(_player_label(player_id))
	var pending_labels: Array[String] = []
	for player_id in round_rules.pending_players:
		pending_labels.append(_player_label(player_id))
	lobby_info.text = "HOST LOBBY\nAccepted (%d/6): %s\nPending: %s" % [round_rules.accepted_players.size(), ", ".join(accepted_labels), ", ".join(pending_labels)]
	start_round_button.disabled = round_rules.accepted_players.size() < round_rules.MIN_PLAYERS or (lan_active and not lan_host)
	player_select.clear()
	player_select.add_item("Select accepted player")
	player_select.set_item_disabled(0, true)
	for player_id in round_rules.accepted_players:
		if player_id != active_local_player_id:
			player_select.add_item(player_id)
	player_select.select(0)
	remove_button.visible = false
	add_request_button.visible = not lan_active
	accept_button.visible = not lan_active or lan_host
	reject_button.visible = not lan_active or lan_host
	remove_button.visible = false

func _player_label(player_id: String) -> String:
	return str(lan_player_names.get(player_id, player_id))

func _character_for_network_player(player_id: String, index: int) -> String:
	if not lan_active:
		return round_rules.character_for(player_id)
	var paths := [
		"res://assets/kaykit_reference/Knight.glb",
		"res://assets/kaykit_reference/Mage.glb",
		"res://assets/kaykit_reference/Rogue.glb",
		"res://assets/kaykit_reference/Rogue_Hooded.glb",
		"res://assets/kaykit_reference/Ranger.glb",
		"res://assets/kaykit_reference/Barbarian.glb",
	]
	return paths[index % paths.size()]

func _assign_locked_roles() -> void:
	if SOLO_ROLE_TEST:
		player_roles = {"Player 1": "hider"}
		desktop_player.set("can_possess", true)
		seeker_mode = false
		role_info.text = "Solo role test · G switches Player 1 between HIDER and SEEKER"
		status.text = "Solo test: Player 1 is HIDER. Press E to possess."
		_update_solo_marker_visibility()
		_update_active_role_view()
		return
	player_roles = round_rules.assign_roles(ACTIVE_PLAYER_IDS)
	if player_roles.is_empty():
		return
	var desktop_role := str(player_roles["Player 1"])
	var phone_role := str(player_roles["Player 2"])
	desktop_player.set("can_possess", desktop_role == "hider")
	phone_player.set_round_role(phone_role)
	seeker_mode = desktop_role == "seeker"
	role_info.text = "Lobby: %d / 6 players · roles locked for this round · P1: %s · P2: %s" % [ACTIVE_PLAYER_IDS.size(), desktop_role.to_upper(), phone_role.to_upper()]
	status.text = "Roles assigned randomly and locked until this round ends."

func _switch_solo_role() -> void:
	if not SOLO_ROLE_TEST:
		return
	var new_role := "seeker" if str(player_roles.get("Player 1", "hider")) == "hider" else "hider"
	player_roles["Player 1"] = new_role
	seeker_mode = new_role == "seeker"
	music_target_db = -23.0 if seeker_mode else -15.0
	desktop_player.set("can_possess", new_role == "hider")
	role_info.text = "Solo role test · Player 1 is now " + new_role.to_upper()
	status.text = "Press Q to inspect." if seeker_mode else "Press E to possess."
	_update_solo_marker_visibility()
	_update_active_role_view()

func _update_solo_marker_visibility() -> void:
	_refresh_hider_arrow_visibility()

func _add_prop_hunt_candidates(house: Node3D) -> void:
	# Verified furniture meshes only. Structural house pieces remain fixed.
	solo_hider = _add_prop_candidate(house, "Sillon", "Sofa", Vector3.ZERO)
	_add_prop_candidate(house, "Silla", "Chair", Vector3.ZERO)
	_add_prop_candidate(house, "Lampara1", "Lamp", Vector3.ZERO)
	_add_prop_candidate(house, "Barril", "Barrel", Vector3.ZERO)
	_add_prop_candidate(house, "Caja", "Box", Vector3.ZERO)
	_add_prop_candidate(house, "Mesa", "Table", Vector3.ZERO)
	_add_prop_candidate(house, "Tele", "TV", Vector3.ZERO)
	_add_prop_candidate(house, "Ventilador", "Fan", Vector3.ZERO)
	# Extra furniture from bedroom, storage and utility sections of this same house pack.
	_add_prop_candidate(house, "Cama", "Bed", Vector3.ZERO)
	_add_prop_candidate(house, "Closet", "Wardrobe", Vector3.ZERO)
	_add_prop_candidate(house, "Estante", "Shelf", Vector3.ZERO)
	_add_prop_candidate(house, "Bote_Basura", "Trash Bin", Vector3.ZERO)
	if solo_hider:
		solo_hider.set_meta("original_position", solo_hider.global_position)

func _add_demo_cube(location: Vector3) -> Node3D:
	var prop := Node3D.new()
	prop.name = "Prop_DemoCube"
	prop.position = location
	prop.set_script(PROP_HUNT_SCRIPT)
	prop.set("prop_name", "Demo Cube")
	prop.add_to_group("possessable_prop")
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	var cube := BoxMesh.new()
	cube.size = Vector3(0.7, 0.7, 0.7)
	visual.mesh = cube
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("b44dff")
	material.metallic = 0.15
	material.roughness = 0.35
	visual.material_override = material
	prop.add_child(visual)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.7, 0.7)
	collision.shape = shape
	body.add_child(collision)
	# No collision in this demo: the cube cannot get caught on the house.
	body.collision_layer = 0
	body.collision_mask = 0
	prop.add_child(body)
	_add_hider_arrow(prop)
	add_child(prop)
	return prop

func _add_prop_candidate(house: Node3D, source_name: String, label: String, location: Vector3) -> Node3D:
	var source := house.find_child(source_name, true, false) as MeshInstance3D
	if source == null or source.mesh == null:
		push_warning("Could not find prop source: " + source_name)
		return null
	var prop := Node3D.new()
	prop.name = "Prop_" + label
	# Different imported models have different origins. Place their actual bottom on
	# the floor rather than trusting a guessed Y coordinate.
	var visual_scale := source.global_transform.basis.get_scale()
	var floor_offset := -source.mesh.get_aabb().position.y * visual_scale.y + 0.03
	var prop_position := Vector3(location.x, location.y + floor_offset, location.z)
	if location == Vector3.ZERO:
		# Use each furniture mesh's authored transform, not a guessed placement.
		prop_position = source.global_position
		source.visible = false
		var authored_sofa_collision := source.get_node_or_null("StaticBody3D") as StaticBody3D
		if authored_sofa_collision:
			authored_sofa_collision.collision_layer = 0
			authored_sofa_collision.collision_mask = 0
	prop.position = prop_position
	prop.set_script(PROP_HUNT_SCRIPT)
	prop.set("prop_name", label)
	prop.set_meta("switchable", false)
	prop.add_to_group("possessable_prop")
	var visual := MeshInstance3D.new()
	visual.name = "Visual"
	visual.mesh = source.mesh
	visual.scale = visual_scale
	prop.add_child(visual)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = source.mesh.create_trimesh_shape()
	collision.scale = visual.scale
	body.add_child(collision)
	prop.add_child(body)
	_add_hider_arrow(prop)
	add_child(prop)
	return prop

func _add_hider_arrow(prop: Node3D) -> void:
	var marker := MeshInstance3D.new()
	marker.name = "HiderArrow"
	marker.add_to_group("hider_marker")
	marker.position = Vector3(0, 1.6, 0)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.38
	mesh.bottom_radius = 0.0
	mesh.height = 0.8
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("39ff66")
	material.emission_enabled = true
	material.emission = Color("39ff66")
	material.emission_energy_multiplier = 2.0
	marker.material_override = material
	prop.add_child(marker)

func _choose_hider_prop() -> void:
	var candidates := get_tree().get_nodes_in_group("possessable_prop")
	if candidates.is_empty():
		return
	for candidate in candidates:
		(candidate as Node3D).set_meta("switchable", false)
	hider_choice = candidates[randi_range(0, candidates.size() - 1)] as Node3D
	hider_choice.set_meta("switchable", true)
	if hider_marker:
		hider_marker.queue_free()
	hider_marker = Node3D.new()
	hider_marker.position = hider_choice.global_position + Vector3(0, 1.6, 0)
	var arrow := MeshInstance3D.new()
	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.38
	arrow_mesh.bottom_radius = 0.0
	arrow_mesh.height = 0.8
	arrow.mesh = arrow_mesh
	var arrow_material := StandardMaterial3D.new()
	arrow_material.albedo_color = Color("39ff66")
	arrow_material.emission_enabled = true
	arrow_material.emission = Color("39ff66")
	arrow_material.emission_energy_multiplier = 2.0
	arrow.material_override = arrow_material
	hider_marker.add_child(arrow)
	add_child(hider_marker)
	status.text = "HIDER ONLY — USE THIS DISGUISE: " + str(hider_choice.get("prop_name"))

func _setup_mobile_controls() -> void:
	mobile_hud = Control.new()
	mobile_hud.name = "MobileControls"
	mobile_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mobile_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_hud.modulate = Color(1.0, 1.0, 1.0, 0.68)
	mobile_hud.visible = OS.has_feature("mobile")
	$Interface.add_child(mobile_hud)
	var joystick_pad := TextureRect.new()
	joystick_pad.texture = load(MOBILE_UI_PATH + "joystick_circle_pad_a.png")
	joystick_pad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	joystick_pad.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	joystick_pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick_pad.position = Vector2(28, -225)
	joystick_pad.size = Vector2(190, 190)
	joystick_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_hud.add_child(joystick_pad)
	mobile_joystick_nub = TextureRect.new()
	mobile_joystick_nub.texture = load(MOBILE_UI_PATH + "joystick_circle_nub_a.png")
	mobile_joystick_nub.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mobile_joystick_nub.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mobile_joystick_nub.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	mobile_joystick_nub.position = Vector2(75, -178)
	mobile_joystick_nub.size = Vector2(96, 96)
	mobile_joystick_nub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mobile_hud.add_child(mobile_joystick_nub)
	mobile_menu_button = _mobile_make_button("Menu", Vector2.ZERO, Vector2(74, 74), "icon_menu.png", "MENU", _toggle_game_info)
	mobile_menu_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mobile_menu_button.position = Vector2(542, 18)
	mobile_action_button = _mobile_make_button("Action", Vector2(-190, -210), Vector2(125, 125), "icon_hand.png", "POSSESS", _mobile_primary_action)
	mobile_action_label = mobile_action_button.get_node("Label") as Label
	_mobile_make_button("Jump", Vector2(-70, -118), Vector2(64, 64), "icon_jump.png", "JUMP", _mobile_jump)
	mobile_up_button = _mobile_make_button("Up", Vector2(-270, -210), Vector2(58, 58), "icon_arrow.png", "UP", _mobile_raise)
	mobile_down_button = _mobile_make_button("Down", Vector2(-270, -130), Vector2(58, 58), "icon_arrow.png", "DOWN", _mobile_lower)
	mobile_down_button.get_node("Icon").rotation = PI

func _mobile_make_button(button_name: String, bottom_right_offset: Vector2, button_size: Vector2, icon_file: String, label_text: String, action: Callable) -> TextureButton:
	var button := TextureButton.new()
	button.name = button_name
	button.texture_normal = load(MOBILE_UI_PATH + "button_circle.png")
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_SCALE
	button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button.position = bottom_right_offset
	button.size = button_size
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.pressed.connect(action)
	mobile_hud.add_child(button)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = load(MOBILE_UI_PATH + icon_file)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(button_size.x * 0.28, button_size.y * 0.18)
	icon.size = Vector2(button_size.x * 0.44, button_size.y * 0.44)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var label := Label.new()
	label.name = "Label"
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, button_size.y * 0.67)
	label.size = Vector2(button_size.x, button_size.y * 0.24)
	label.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0, 1.0))
	label.add_theme_font_size_override("font_size", 14)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)
	return button

func _update_mobile_controls_for_role() -> void:
	if mobile_hud == null:
		return
	var role := str(player_roles.get(active_local_player_id, "hider"))
	mobile_action_label.text = "INSPECT" if role == "seeker" else "POSSESS"
	(mobile_action_button.get_node("Icon") as TextureRect).texture = load(MOBILE_UI_PATH + ("icon_crosshair.png" if role == "seeker" else "icon_hand.png"))
	var hider := role == "hider"
	mobile_up_button.visible = hider
	mobile_down_button.visible = hider

func _mobile_primary_action() -> void:
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar == null:
		return
	if str(player_roles.get(active_local_player_id, "")) == "seeker":
		_request_inspect(avatar)
	else:
		avatar.call("_toggle_possession")

func _mobile_jump() -> void:
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar:
		avatar.mobile_jump()

func _mobile_raise() -> void:
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar:
		avatar.mobile_raise_or_lower(0.22)

func _mobile_lower() -> void:
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar:
		avatar.mobile_raise_or_lower(-0.22)

func _set_mobile_joystick(screen_position: Vector2) -> void:
	var center := Vector2(123, get_viewport().get_visible_rect().size.y - 130)
	var offset := (screen_position - center).limit_length(67.0)
	mobile_joystick_nub.position = Vector2(75, -178) + offset
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar:
		# Screen Y grows downward; game forward must be upward on the joystick.
		avatar.set_mobile_move_input(Vector2(offset.x / 67.0, -offset.y / 67.0))

func _release_mobile_joystick() -> void:
	mobile_joystick_nub.position = Vector2(75, -178)
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar:
		avatar.set_mobile_move_input(Vector2.ZERO)

func _input(event: InputEvent) -> void:
	if mobile_hud and mobile_hud.visible:
		if event is InputEventScreenTouch:
			var touch_position: Vector2 = event.position
			if event.pressed and touch_position.x < get_viewport().get_visible_rect().size.x * 0.34 and touch_position.y > get_viewport().get_visible_rect().size.y * 0.5:
				mobile_joystick_touch = event.index
				_set_mobile_joystick(touch_position)
			elif not event.pressed:
				if event.index == mobile_joystick_touch:
					mobile_joystick_touch = -1
					_release_mobile_joystick()
				if event.index == mobile_camera_touch:
					mobile_camera_touch = -1
		elif event is InputEventScreenDrag:
			if event.index == mobile_joystick_touch:
				_set_mobile_joystick(event.position)
			elif event.position.x > get_viewport().get_visible_rect().size.x * 0.38:
				var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
				if avatar:
					avatar.mobile_camera_drag(event.relative)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_G:
		if not lan_active:
			_switch_solo_role()
	elif event.keycode == KEY_Q and str(player_roles.get(active_local_player_id, "")) == "seeker":
		_request_inspect(player_avatars.get(active_local_player_id) as Node3D)
	elif event.keycode >= KEY_1 and event.keycode <= KEY_6:
		_select_local_player(event.keycode - KEY_0)
	elif event.keycode == KEY_R:
		if not lan_active:
			_reset_round()
	elif event.keycode == KEY_N and phase == "Hiding":
		if not lan_active or lan_host:
			_start_seeking()
	elif event.keycode == KEY_M:
		mobile_ui_test_enabled = not mobile_ui_test_enabled
		mobile_hud.visible = mobile_ui_test_enabled or OS.has_feature("mobile")

func _start_seeking() -> void:
	phase = "Seeking"
	phase_seconds = 120.0
	seeker_mode = true
	music_target_db = -23.0
	for player_id in player_avatars:
		if str(player_roles.get(player_id, "")) == "seeker":
			(player_avatars[player_id] as CharacterBody3D).round_movement_locked = false
	_refresh_hider_arrow_visibility()
	status.text = "Seeking phase — seeker released. Inspect hiders and possessed props."
	_show_round_banner("SEEKER RELEASED!\nFIND THE HIDERS", 2.8)
	if lan_active and lan_host:
		_network_broadcast_round_state()

func _finish_round(message: String) -> void:
	phase = "Finished"
	music_target_db = -17.0
	status.text = message + " Press R to start again."
	round_banner.hide()
	end_winner.text = message
	end_screen.show()
	if lan_active and lan_host:
		_network_broadcast_round_state(message)

func _start_next_round() -> void:
	if lan_active and not lan_host:
		return
	end_screen.hide()
	seeker_attempts = 12
	seeker_mode = false
	music_target_db = -15.0
	phase = "Hiding"
	phase_seconds = HIDING_SECONDS
	for player_id in player_avatars:
		var avatar: CharacterBody3D = player_avatars[player_id]
		if avatar.get("possessed_prop"):
			avatar.call("_toggle_possession")
		avatar.visible = true
		avatar.set_physics_process(true)
		avatar.get_node("Collision").set_deferred("disabled", false)
	if round_rules.accepted_players.size() >= round_rules.MIN_PLAYERS:
		player_roles = round_rules.assign_roles(round_rules.accepted_players)
		_spawn_accepted_players()
		for player_id in player_avatars:
			var avatar: CharacterBody3D = player_avatars[player_id]
			avatar.round_movement_locked = str(player_roles.get(player_id, "")) == "seeker"
		role_info.text = "NEW ROUND · roles locked · " + str(player_roles)
	else:
		_assign_locked_roles()
	_update_active_role_view()
	round_info.text = "Seeker attempts: 12 · Each elimination gives +2 attempts"
	status.text = "New round started. Hiders have 10 seconds to hide."
	if lan_active:
		_network_send_round_start()

func _toggle_seeker_mode() -> void:
	seeker_mode = not seeker_mode
	var explorer := find_child("Explorer", false, false)
	if explorer:
		explorer.set("can_possess", not seeker_mode)
	if seeker_mode:
		for marker in get_tree().get_nodes_in_group("hider_marker"):
			marker.visible = false
		status.text = "Seeker mode — press Q near a prop to inspect it."
	else:
		for marker in get_tree().get_nodes_in_group("hider_marker"):
			marker.visible = true
		status.text = "Hider mode — press E near a prop to possess it."

func _request_inspect(actor: Node3D) -> void:
	if lan_active and not lan_host:
		rpc_id(1, "_server_request_inspect")
		return
	_inspect_nearby_prop(actor, active_local_player_id)

func _inspect_nearby_prop(actor: Node3D, seeker_id := "") -> void:
	if phase != "Seeking" and not SOLO_ROLE_TEST:
		status.text = "Wait for the hiding phase to end before inspecting."
		return
	if actor == null or seeker_attempts <= 0:
		return
	# A seeker can capture a hider whether that hider is visible as a character
	# or hidden inside a possessed prop (the avatar root stays at that prop).
	for player_id in player_avatars:
		if player_id == seeker_id or str(player_roles.get(player_id, "")) != "hider":
			continue
		var hider_avatar: CharacterBody3D = player_avatars[player_id]
		if hider_avatar.visible and actor.global_position.distance_to(hider_avatar.global_position) < 2.6:
			_eliminate_hider(player_id)
			return
		if not hider_avatar.visible and actor.global_position.distance_to(hider_avatar.global_position) < 2.6:
			_eliminate_hider(player_id)
			return
	var closest: Node3D
	var distance_limit := 2.6
	for candidate in get_tree().get_nodes_in_group("possessable_prop"):
		var prop := candidate as Node3D
		var distance := actor.global_position.distance_to(prop.global_position)
		if prop.visible and distance < distance_limit:
			closest = prop
			distance_limit = distance
	if closest and bool(closest.get_meta("is_hider", false)):
		seeker_attempts += 2
		closest.global_position = closest.get_meta("original_position", closest.global_position) as Vector3
		closest.visible = true
		_finish_round("Seeker wins! Hider returned to its original place. +2 attempts.")
	else:
		seeker_attempts -= 1
		status.text = "Wrong prop. One attempt used."
		if seeker_attempts <= 0:
			_finish_round("Hider wins — seeker has no attempts left.")
	round_info.text = "Seeker attempts: %d · Each elimination gives +2 attempts" % seeker_attempts

func _eliminate_hider(player_id: String) -> void:
	var hider_avatar: CharacterBody3D = player_avatars[player_id]
	# Release a possessed prop before removing the player, so it does not remain
	# hidden or block the room.
	if hider_avatar.get("possessed_prop"):
		hider_avatar.call("_toggle_possession")
	hider_avatar.visible = false
	hider_avatar.set_physics_process(false)
	hider_avatar.get_node("Collision").disabled = true
	player_roles[player_id] = "eliminated"
	seeker_attempts += 2
	_show_capture_feedback(player_id, hider_avatar.global_position)
	var remaining_hiders := 0
	for role in player_roles.values():
		if role == "hider":
			remaining_hiders += 1
	if remaining_hiders == 0:
		_finish_round("Seeker wins! All hiders eliminated. +2 attempts.")
	else:
		status.text = player_id + " eliminated. " + str(remaining_hiders) + " hider(s) remain."
	round_info.text = "Seeker attempts: %d · Each elimination gives +2 attempts" % seeker_attempts
	if lan_active and lan_host:
		rpc("_client_eliminated", player_id, hider_avatar.global_position)
		_network_broadcast_round_state()

func _reset_round() -> void:
	seeker_attempts = 12
	seeker_mode = false
	music_target_db = -15.0
	phase = "Hiding"
	phase_seconds = HIDING_SECONDS
	if solo_hider:
		solo_hider.visible = true
		solo_hider.global_position = solo_hider.get_meta("original_position", solo_hider.global_position) as Vector3
	if hider_marker:
		hider_marker.visible = false
	round_info.text = "Seeker attempts: 12 · Each elimination gives +2 attempts"
	status.text = "New round: roles are being assigned."
	_refresh_hider_arrow_visibility()
	timer_label.text = "Hiding phase: %ds · N skips to seeking for testing" % HIDING_SECONDS
	_assign_locked_roles()
	_update_active_role_view()

func _show_capture_feedback(player_id: String, location: Vector3) -> void:
	_play_capture_sound()
	_show_round_banner("CAPTURED!\n%s ELIMINATED" % player_id.to_upper(), 2.4)
	var label := Label3D.new()
	label.text = "ELIMINATED\n" + player_id
	label.font_size = 64
	label.outline_size = 12
	label.modulate = Color(1.0, 0.18, 0.18, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.pixel_size = 0.006
	label.global_position = location + Vector3(0, 2.2, 0)
	add_child(label)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.05, 0.05)
	flash.light_energy = 9.0
	flash.omni_range = 7.0
	flash.global_position = location + Vector3(0, 1.1, 0)
	add_child(flash)
	get_tree().create_timer(2.4).timeout.connect(label.queue_free)
	get_tree().create_timer(0.45).timeout.connect(flash.queue_free)

func _play_capture_sound() -> void:
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = 44100.0
	stream.buffer_length = 0.5
	player.stream = stream
	add_child(player)
	player.play()
	var playback := player.get_stream_playback()
	if playback:
		for sample_index in range(15000):
			var frequency := 780.0 if sample_index < 7500 else 1040.0
			var sample := sin(TAU * frequency * float(sample_index) / stream.mix_rate) * 0.22
			playback.push_frame(Vector2(sample, sample))
	get_tree().create_timer(0.5).timeout.connect(player.queue_free)

func _setup_background_music() -> void:
	var stream := load(BACKGROUND_MUSIC_PATH) as AudioStream
	if stream == null:
		push_warning("Background music did not import yet.")
		return
	background_music = AudioStreamPlayer.new()
	background_music.stream = stream
	background_music.volume_db = music_target_db
	background_music.finished.connect(_restart_background_music)
	add_child(background_music)
	background_music.play()

func _restart_background_music() -> void:
	if background_music:
		background_music.play()

func _hide_non_playable_world(house: Node3D) -> void:
	for group_name in HIDDEN_WORLD_GROUPS:
		var group := house.find_child(group_name, true, false) as Node3D
		if group:
			group.visible = false

func _add_lantern(location: Vector3, energy: float, light_range: float) -> void:
	var lantern := OmniLight3D.new()
	lantern.position = location
	lantern.light_color = Color("ff9d4d")
	lantern.light_energy = energy
	lantern.omni_range = light_range
	# Mobile keeps the nearby important lights but avoids six expensive dynamic shadows.
	lantern.shadow_enabled = not OS.has_feature("mobile") or energy >= 2.0
	lantern.set_meta("base_energy", energy)
	lantern.add_to_group("atmosphere_lantern")
	add_child(lantern)

func _add_collision_to_meshes(node: Node) -> void:
	if node is Node3D and not node.visible:
		return
	if node is MeshInstance3D and node.mesh:
		var body := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		collision.shape = node.mesh.create_trimesh_shape()
		body.add_child(collision)
		node.add_child(body)
	for child in node.get_children():
		if child is StaticBody3D:
			continue
		_add_collision_to_meshes(child)

func _get_house_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var has_mesh := false
	if node is MeshInstance3D and node.mesh:
		bounds = node.global_transform * node.mesh.get_aabb()
		has_mesh = true
	for child in node.get_children():
		if child is StaticBody3D:
			continue
		var child_bounds := _get_house_bounds(child)
		if child_bounds.size.length() > 0.0:
			bounds = child_bounds if not has_mesh else bounds.merge(child_bounds)
			has_mesh = true
	return bounds

# --- Real Wi-Fi multiplayer -------------------------------------------------
# The host owns lobby decisions, role assignment, timer, attempts, captures and
# the final result. Clients only send their own movement/possession state.

func _start_lan_host() -> void:
	if lan_active:
		return
	lan_peer = ENetMultiplayerPeer.new()
	var result := lan_peer.create_server(LAN_PORT, round_rules.MAX_PLAYERS - 1)
	if result != OK:
		lan_info.text = "Could not host on port %d (error %d)." % [LAN_PORT, result]
		return
	multiplayer.multiplayer_peer = lan_peer
	lan_active = true
	lan_host = true
	lan_joined = true
	lan_local_name = _clean_player_name(lan_name.text, "Host")
	_network_prepare_local_player("1")
	lan_player_names = {"1": lan_local_name}
	round_rules.clear()
	round_rules.accepted_players = ["1"]
	player_roles = {"1": "hider"}
	lan_info.text = "Room is visible to nearby players. They only tap Join Nearby."
	status.text = "LAN host ready. Players on this Wi-Fi/hotspot can find your room automatically."
	# The host must see the Host Lobby (pending/accepted players), not the join panel.
	$Interface/LanPanel.hide()
	_set_host_lobby_visible(true)
	_update_lobby_display()

func _join_lan_host() -> void:
	if lan_active:
		return
	var address := lan_discovered_address
	if address.is_empty():
		lan_info.text = "No nearby room found yet. Make sure the host started a room and both devices use the same Wi-Fi/hotspot."
		return
	lan_peer = ENetMultiplayerPeer.new()
	var result := lan_peer.create_client(address, LAN_PORT)
	if result != OK:
		lan_info.text = "Could not connect to %s (error %d)." % [address, result]
		return
	multiplayer.multiplayer_peer = lan_peer
	lan_active = true
	lan_host = false
	lan_joined = false
	lan_local_name = _clean_player_name(lan_name.text, "Guest")
	lan_info.text = "Joining %s…" % lan_discovered_host_name
	lan_host_button.disabled = true
	lan_join_button.disabled = true
	desktop_player.locally_controlled = false
	desktop_player.visible = false

func _on_lan_connected_to_server() -> void:
	lan_info.text = "Connected. Sending join request to the host…"
	rpc_id(1, "_server_join_request", lan_local_name)

func _on_lan_connection_failed() -> void:
	lan_info.text = "Connection failed. Check the IP and make sure both devices use the same Wi-Fi."
	_network_stop(false)

func _on_lan_server_disconnected() -> void:
	lan_info.text = "The host disconnected."
	status.text = "LAN session ended."
	_network_stop(false)

func _on_lan_peer_connected(peer_id: int) -> void:
	if lan_host:
		lan_info.text = "Player connected — waiting for their join request."

func _on_lan_peer_disconnected(peer_id: int) -> void:
	if not lan_host:
		return
	var player_id := str(peer_id)
	if player_id in round_rules.accepted_players or player_id in round_rules.pending_players:
		round_rules.host_remove(player_id)
		lan_player_names.erase(player_id)
		var avatar := player_avatars.get(player_id) as CharacterBody3D
		if avatar:
			player_avatars.erase(player_id)
			avatar.queue_free()
		if phase != "Finished" and round_rules.roles_locked:
			_finish_round("Round ended — %s disconnected." % player_id)
		_network_broadcast_lobby()
		_update_lobby_display()

@rpc("any_peer", "reliable")
func _server_join_request(requested_name: String) -> void:
	if not lan_active or not lan_host:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	var player_id := str(peer_id)
	print("LAN JOIN REQUEST from id=", player_id, " name=", requested_name)
	if round_rules.roles_locked:
		rpc_id(peer_id, "_client_join_message", "A round is already running. Try again after it ends.")
		return
	lan_player_names[player_id] = _clean_player_name(requested_name, "Guest %d" % peer_id)
	if not round_rules.request_join(player_id):
		rpc_id(peer_id, "_client_join_message", "This room is full or you already requested entry.")
		return
	status.text = _player_label(player_id) + " requested to join. Accept or reject in Host Lobby."
	$Interface/LanPanel.hide()
	_set_host_lobby_visible(true)
	_show_round_banner("PLAYER REQUEST\n%s wants to join\nTap ACCEPT in Host Lobby" % _player_label(player_id))
	_network_broadcast_lobby()
	_update_lobby_display()

@rpc("authority", "reliable")
func _client_join_message(message: String) -> void:
	lan_info.text = message

@rpc("authority", "reliable")
func _client_receive_lobby(accepted: Array, pending: Array, names: Dictionary) -> void:
	if not lan_active:
		return
	round_rules.accepted_players.clear()
	for player_id in accepted:
		round_rules.accepted_players.append(str(player_id))
	round_rules.pending_players.clear()
	for player_id in pending:
		round_rules.pending_players.append(str(player_id))
	lan_player_names = names.duplicate()
	var local_id := str(multiplayer.get_unique_id())
	_network_prepare_local_player(local_id)
	_network_sync_avatars()
	lan_joined = local_id in round_rules.accepted_players
	if lan_joined:
		desktop_player.visible = true
		desktop_player.locally_controlled = phase != "Finished"
		lan_info.text = "Accepted as %s. Waiting for the host to start." % _player_label(local_id)
		$Interface/LanPanel.hide()
		_set_host_lobby_visible(false)
	else:
		player_roles.clear()
		desktop_player.visible = false
		desktop_player.locally_controlled = false
		lan_info.text = "Waiting for host approval…"
	_update_lobby_display()

func _network_broadcast_lobby() -> void:
	if not lan_host:
		return
	# _client_receive_lobby rebuilds its local lists. Give it snapshots so the
	# host does not accidentally clear its authoritative accepted/pending lists.
	var accepted_snapshot: Array = round_rules.accepted_players.duplicate()
	var pending_snapshot: Array = round_rules.pending_players.duplicate()
	var names_snapshot: Dictionary = lan_player_names.duplicate()
	_client_receive_lobby(accepted_snapshot, pending_snapshot, names_snapshot)
	rpc("_client_receive_lobby", accepted_snapshot, pending_snapshot, names_snapshot)

func _network_reject_or_remove_peer(player_id: String, message: String) -> void:
	var peer_id := int(player_id)
	if peer_id <= 0:
		return
	rpc_id(peer_id, "_client_join_message", message)
	multiplayer.multiplayer_peer.disconnect_peer(peer_id)
	lan_player_names.erase(player_id)
	_network_broadcast_lobby()

func _network_prepare_local_player(local_id: String) -> void:
	if desktop_player == null:
		return
	for player_id in player_avatars.keys():
		if player_id != local_id and player_avatars[player_id] == desktop_player:
			player_avatars.erase(player_id)
	active_local_player_id = local_id
	player_avatars[local_id] = desktop_player
	desktop_player.set_meta("network_player_id", local_id)
	desktop_player.locally_controlled = true
	desktop_player.get_node("CameraPivot/CameraSpring/Camera").current = true

func _network_sync_avatars() -> void:
	var local_id := str(multiplayer.get_unique_id())
	var kept: Dictionary = {local_id: true}
	for index in range(round_rules.accepted_players.size()):
		var player_id := round_rules.accepted_players[index]
		kept[player_id] = true
		if player_id == local_id:
			continue
		if player_avatars.has(player_id):
			continue
		var avatar := PLAYER_SCENE.instantiate() as CharacterBody3D
		avatar.character_path = _character_for_network_player(player_id, index)
		avatar.position = HOUSE_ENTRANCE + Vector3(1.4 * index, 0, 1.5)
		avatar.locally_controlled = false
		avatar.set_meta("network_player_id", player_id)
		add_child(avatar)
		player_avatars[player_id] = avatar
	for player_id in player_avatars.keys():
		if player_id != local_id and not kept.has(player_id):
			var old_avatar := player_avatars[player_id] as CharacterBody3D
			player_avatars.erase(player_id)
			if old_avatar:
				old_avatar.queue_free()

func _network_send_round_start() -> void:
	if not lan_host:
		return
	for player_id in round_rules.accepted_players:
		var own_role := str(player_roles.get(player_id, "hider"))
		if player_id == "1":
			_network_apply_round_start(own_role, player_id, phase, phase_seconds, seeker_attempts)
		else:
			rpc_id(int(player_id), "_client_start_round", own_role, player_id, phase, phase_seconds, seeker_attempts)
	_network_broadcast_round_state()

@rpc("authority", "reliable")
func _client_start_round(own_role: String, own_id: String, new_phase: String, seconds: float, attempts: int) -> void:
	if lan_host:
		return
	_network_apply_round_start(own_role, own_id, new_phase, seconds, attempts)

func _network_apply_round_start(own_role: String, own_id: String, new_phase: String, seconds: float, attempts: int) -> void:
	if not lan_host:
		player_roles = {own_id: own_role}
	active_local_player_id = own_id
	phase = new_phase
	phase_seconds = seconds
	seeker_attempts = attempts
	seeker_mode = own_role == "seeker"
	var avatar := player_avatars.get(own_id) as CharacterBody3D
	if avatar:
		avatar.visible = true
		avatar.locally_controlled = true
		avatar.round_movement_locked = own_role == "seeker" and new_phase == "Hiding"
		avatar.set("can_possess", own_role == "hider")
	_set_host_lobby_visible(false)
	end_screen.hide()
	status.text = "Round started. You are %s." % own_role.to_upper()
	role_info.text = "Your locked role: " + own_role.to_upper()
	_update_active_role_view()

func _network_broadcast_round_state(message := "") -> void:
	if not lan_host:
		return
	_client_receive_round_state(phase, phase_seconds, seeker_attempts, message)
	rpc("_client_receive_round_state", phase, phase_seconds, seeker_attempts, message)

@rpc("authority", "reliable")
func _client_receive_round_state(new_phase: String, seconds: float, attempts: int, message: String) -> void:
	if not lan_active:
		return
	phase = new_phase
	phase_seconds = seconds
	seeker_attempts = attempts
	var own_role := str(player_roles.get(active_local_player_id, ""))
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar:
		avatar.round_movement_locked = own_role == "seeker" and new_phase == "Hiding"
	if new_phase == "Seeking":
		_show_round_banner("SEEKER RELEASED!\nFIND THE HIDERS", 2.8)
	if new_phase == "Finished":
		end_winner.text = message
		end_screen.show()
		status.text = message
	_refresh_hider_arrow_visibility()

func _network_process(delta: float) -> void:
	if not lan_joined:
		return
	# In the lobby, accepted players may move for multiplayer testing. Keep this
	# deliberately low-rate and do not run the round timer/state broadcaster.
	if phase == "Lobby":
		if lan_host and round_rules.accepted_players.size() < round_rules.MIN_PLAYERS:
			return
		lan_state_elapsed += delta
		if lan_state_elapsed >= 0.05:
			lan_state_elapsed = 0.0
			_network_send_local_state()
		return
	lan_state_elapsed += delta
	lan_round_elapsed += delta
	if lan_state_elapsed >= NETWORK_STATE_INTERVAL:
		lan_state_elapsed = 0.0
		_network_send_local_state()
	if lan_host and lan_round_elapsed >= 0.25:
		lan_round_elapsed = 0.0
		_network_broadcast_round_state()

func _network_send_local_state() -> void:
	if not lan_active or not lan_joined:
		return
	var avatar := player_avatars.get(active_local_player_id) as CharacterBody3D
	if avatar == null:
		return
	var state: Dictionary = avatar.get_network_state()
	if lan_host:
		rpc("_client_receive_avatar_state", active_local_player_id, state)
	else:
		rpc_id(1, "_server_receive_avatar_state", state)

@rpc("any_peer", "unreliable")
func _server_receive_avatar_state(state: Dictionary) -> void:
	if not lan_active or not lan_host:
		return
	var player_id := str(multiplayer.get_remote_sender_id())
	if not player_id in round_rules.accepted_players:
		return
	var avatar := player_avatars.get(player_id) as CharacterBody3D
	if avatar:
		avatar.apply_network_state(state, player_id)
	rpc("_client_receive_avatar_state", player_id, state)

@rpc("authority", "unreliable")
func _client_receive_avatar_state(player_id: String, state: Dictionary) -> void:
	if player_id == active_local_player_id:
		return
	var avatar := player_avatars.get(player_id) as CharacterBody3D
	if avatar:
		avatar.apply_network_state(state, player_id)

@rpc("any_peer", "reliable")
func _server_request_inspect() -> void:
	if not lan_active or not lan_host or phase != "Seeking":
		return
	var player_id := str(multiplayer.get_remote_sender_id())
	if str(player_roles.get(player_id, "")) != "seeker":
		return
	_inspect_nearby_prop(player_avatars.get(player_id) as Node3D, player_id)
	_network_broadcast_round_state()

@rpc("authority", "reliable")
func _client_eliminated(player_id: String, location: Vector3) -> void:
	var avatar := player_avatars.get(player_id) as CharacterBody3D
	if avatar:
		avatar.visible = false
		avatar.set_physics_process(false)
		avatar.get_node("Collision").set_deferred("disabled", true)
	if player_id == active_local_player_id:
		player_roles[player_id] = "eliminated"
		status.text = "You were eliminated."
	_show_capture_feedback(_player_label(player_id), location)

@rpc("authority", "reliable")
func _client_kicked(message: String) -> void:
	lan_info.text = message
	status.text = message
	_network_stop(false)

func _network_stop(show_message := true) -> void:
	lan_active = false
	lan_host = false
	lan_joined = false
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	lan_host_button.disabled = false
	lan_join_button.disabled = false
	if show_message:
		lan_info.text = "LAN session closed."

func _clean_player_name(value: String, fallback: String) -> String:
	var clean := value.strip_edges().replace("\n", " ")
	return clean.left(16) if not clean.is_empty() else fallback

func _local_lan_ip() -> String:
	for address in IP.get_local_addresses():
		if address.begins_with("192.168.") or address.begins_with("10."):
			return address
	return "Use your Mac Wi-Fi IP"

func _setup_lan_discovery() -> void:
	lan_discovery = PacketPeerUDP.new()
	var result := lan_discovery.bind(LAN_DISCOVERY_PORT, "*")
	if result != OK:
		push_warning("LAN discovery listener could not start: " + str(result))
		return
	lan_discovery.set_broadcast_enabled(true)

func _process_lan_discovery(delta: float) -> void:
	if lan_discovery == null:
		return
	if lan_host:
		lan_discovery_elapsed += delta
		if lan_discovery_elapsed >= 0.8:
			lan_discovery_elapsed = 0.0
			lan_discovery.set_dest_address("255.255.255.255", LAN_DISCOVERY_PORT)
			var room := {"game": "abandoned-house", "host": lan_local_name, "address": _local_lan_ip(), "port": LAN_PORT}
			lan_discovery.put_packet(JSON.stringify(room).to_utf8_buffer())
	elif not lan_active and lan_discovered_address.is_empty():
		# Some Android hotspots discard broadcasts. Search without sending a full
		# 254-address burst in one frame, which can stall the host.
		if not lan_scan_active:
			lan_discovery_elapsed += delta
			if lan_discovery_elapsed >= 1.2:
				lan_discovery_elapsed = 0.0
				lan_scan_active = true
				lan_scan_next_host = 1
		if lan_scan_active:
			_send_local_room_search()
	while lan_discovery.get_available_packet_count() > 0:
		var packet: PackedByteArray = lan_discovery.get_packet()
		var sender_ip := lan_discovery.get_packet_ip()
		var sender_port := lan_discovery.get_packet_port()
		var payload: Variant = JSON.parse_string(packet.get_string_from_utf8())
		if not (payload is Dictionary) or str(payload.get("game", "")) != "abandoned-house":
			continue
		if lan_host and str(payload.get("type", "")) == "discover":
			lan_discovery.set_dest_address(sender_ip, sender_port)
			var reply := {"game": "abandoned-house", "type": "room", "host": lan_local_name, "address": _local_lan_ip(), "port": LAN_PORT}
			lan_discovery.put_packet(JSON.stringify(reply).to_utf8_buffer())
			continue
		if lan_active:
			continue
		lan_discovered_address = str(payload.get("address", ""))
		lan_discovered_host_name = str(payload.get("host", "Host"))
		if not lan_discovered_address.is_empty():
			lan_address.text = lan_discovered_address
			lan_join_button.disabled = false
			lan_info.text = "Nearby room found: %s · Tap Join Nearby." % lan_discovered_host_name

func _send_local_room_search() -> void:
	var own_ip := _local_lan_ip()
	var pieces := own_ip.split(".")
	if pieces.size() != 4:
		return
	var prefix := "%s.%s.%s." % [pieces[0], pieces[1], pieces[2]]
	var request := JSON.stringify({"game": "abandoned-house", "type": "discover"}).to_utf8_buffer()
	# Eight requests per rendered frame keeps discovery quick without freezing
	# the host when a phone joins through a hotspot.
	for unused_index in range(8):
		if lan_scan_next_host >= 255:
			lan_scan_active = false
			break
		lan_discovery.set_dest_address(prefix + str(lan_scan_next_host), LAN_DISCOVERY_PORT)
		lan_discovery.put_packet(request)
		lan_scan_next_host += 1
