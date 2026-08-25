extends RefCounted

const MIN_PLAYERS := 2
const MAX_PLAYERS := 6
const CHARACTER_MODELS := {
	"Player 1": "res://assets/kaykit_reference/Knight.glb",
	"Player 2": "res://assets/kaykit_reference/Mage.glb",
	"Player 3": "res://assets/kaykit_reference/Rogue.glb",
	"Player 4": "res://assets/kaykit_reference/Rogue_Hooded.glb",
	"Player 5": "res://assets/kaykit_reference/Ranger.glb",
	"Player 6": "res://assets/kaykit_reference/Barbarian.glb",
}

var roles: Dictionary = {}
var roles_locked := false
var pending_players: Array[String] = []
var accepted_players: Array[String] = []

func request_join(player_id: String) -> bool:
	if roles_locked or player_id in pending_players or player_id in accepted_players:
		return false
	if pending_players.size() + accepted_players.size() >= MAX_PLAYERS:
		return false
	pending_players.append(player_id)
	return true

func host_accept(player_id: String) -> bool:
	if not player_id in pending_players or accepted_players.size() >= MAX_PLAYERS:
		return false
	pending_players.erase(player_id)
	accepted_players.append(player_id)
	return true

func host_reject(player_id: String) -> void:
	pending_players.erase(player_id)

func host_remove(player_id: String) -> void:
	pending_players.erase(player_id)
	accepted_players.erase(player_id)
	roles.erase(player_id)

func assign_roles(player_ids: Array[String]) -> Dictionary:
	if player_ids.size() < MIN_PLAYERS or player_ids.size() > MAX_PLAYERS:
		push_error("Rounds require 2 to 6 players.")
		return {}
	var shuffled := player_ids.duplicate()
	shuffled.shuffle()
	roles.clear()
	for player_id in shuffled:
		roles[player_id] = "hider"
	roles[shuffled[0]] = "seeker"
	roles_locked = true
	return roles.duplicate()

func role_for(player_id: String) -> String:
	return str(roles.get(player_id, ""))

func character_for(player_id: String) -> String:
	return str(CHARACTER_MODELS.get(player_id, ""))

func clear() -> void:
	roles.clear()
	roles_locked = false
	pending_players.clear()
	accepted_players.clear()
