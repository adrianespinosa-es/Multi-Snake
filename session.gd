extends Node
## Autoload "Session": perfil del jugador, sala (lobby) y red (ENet).

signal lobby_changed
signal match_started
signal state_received(st: Dictionary)
signal remote_input(slot: int, dir: Vector2i)
signal connection_lost(reason: String)

const PORT := 24567
const NAME_MAX := 12
const PROFILE_PATH := "user://profile.cfg"

var palette: Array = [
	Color(0.29, 0.64, 1.00), Color(0.18, 0.90, 0.84), Color(0.35, 0.85, 0.35), Color(1.00, 0.90, 0.25),
	Color(1.00, 0.60, 0.20), Color(1.00, 0.30, 0.30), Color(1.00, 0.50, 0.80), Color(0.65, 0.45, 1.00),
]
var palette_names: Array = ["Azul", "Cian", "Verde", "Amarillo", "Naranja", "Rojo", "Rosa", "Morado"]

var player_name := ""
var my_color := 0
var last_ip := ""
var online := false
var is_host := false
var in_match := false
# Cada hueco: {"name": String, "color": int, "peer": int}
# peer: -1 = vacio, 0 = IA, >=1 = jugador humano (el anfitrion es 1)
var slots: Array = []
var my_slot := 0


func _ready() -> void:
	randomize()
	reset_slots()
	_load_profile()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- perfil
func _load_profile() -> void:
	var cf := ConfigFile.new()
	if cf.load(PROFILE_PATH) == OK:
		player_name = str(cf.get_value("profile", "name", ""))
		my_color = int(cf.get_value("profile", "color", 0)) % palette.size()
		last_ip = str(cf.get_value("profile", "ip", ""))


func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "name", player_name)
	cf.set_value("profile", "color", my_color)
	cf.set_value("profile", "ip", last_ip)
	cf.save(PROFILE_PATH)


# ---------------------------------------------------------------- huecos y colores
func _empty_slot() -> Dictionary:
	return {"name": "", "color": -1, "peer": -1}


func reset_slots() -> void:
	slots = [_empty_slot(), _empty_slot(), _empty_slot(), _empty_slot()]
	my_slot = 0


func used_colors(except_slot: int = -1) -> Array:
	var u: Array = []
	for i in slots.size():
		if i != except_slot and int(slots[i]["color"]) >= 0:
			u.append(int(slots[i]["color"]))
	return u


func free_color(pref: int, except_slot: int = -1) -> int:
	var u := used_colors(except_slot)
	if pref >= 0 and not (pref in u):
		return pref
	return random_free_color(except_slot)


func random_free_color(except_slot: int = -1) -> int:
	var u := used_colors(except_slot)
	var avail: Array = []
	for c in palette.size():
		if not (c in u):
			avail.append(c)
	if avail.is_empty():
		return 0
	return avail[randi() % avail.size()]


func _free_slot() -> int:
	for i in slots.size():
		if int(slots[i]["peer"]) == -1:
			return i
	return -1


func _slot_of_peer(id: int) -> int:
	for i in slots.size():
		if int(slots[i]["peer"]) == id:
			return i
	return -1


func _fill_ai() -> void:
	var n := 1
	for i in slots.size():
		if int(slots[i]["peer"]) == -1:
			slots[i] = {"name": "IA %d" % n, "color": random_free_color(i), "peer": 0}
			n += 1


func local_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		var s: String = a
		if s.count(".") == 3 and not s.begins_with("127.") and not s.begins_with("169.254."):
			out.append(s)
	return out


# ---------------------------------------------------------------- offline
func start_offline() -> void:
	leave()
	online = false
	is_host = true
	reset_slots()
	slots[0] = {"name": player_name, "color": my_color, "peer": 1}
	my_slot = 0
	_fill_ai()
	in_match = true
	match_started.emit()


# ---------------------------------------------------------------- online
func host_game() -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 3)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = true
	in_match = false
	reset_slots()
	slots[0] = {"name": player_name, "color": my_color, "peer": 1}
	my_slot = 0
	lobby_changed.emit()
	return OK


func join_game(ip: String) -> int:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	is_host = false
	in_match = false
	return OK


func leave() -> void:
	var p := multiplayer.multiplayer_peer
	if p != null and not (p is OfflineMultiplayerPeer):
		p.close()
	multiplayer.multiplayer_peer = null
	online = false
	is_host = false
	in_match = false
	reset_slots()


func pick_color(c: int) -> void:
	if not online:
		my_color = c
	elif is_host:
		_apply_color(0, c)
	else:
		_srv_pick_color.rpc_id(1, c)


func start_online_match() -> void:
	if not (online and is_host) or in_match:
		return
	_fill_ai()
	in_match = true
	_cl_start.rpc(slots)
	match_started.emit()


func send_input(dir: Vector2i) -> void:
	if online and not is_host:
		_srv_input.rpc_id(1, dir)


func broadcast_state(st: Dictionary) -> void:
	if online and is_host:
		_cl_state.rpc(st)


# ---------------------------------------------------------------- senales de red
func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	if in_match or _free_slot() < 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	for i in slots.size():
		if int(slots[i]["peer"]) == id:
			if in_match:
				slots[i]["peer"] = 0   # su serpiente pasa a ser controlada por la IA
				slots[i]["name"] = str(slots[i]["name"]) + " (IA)"
			else:
				slots[i] = _empty_slot()
	if not in_match:
		_broadcast_lobby()


func _on_connected_ok() -> void:
	_srv_hello.rpc_id(1, player_name, my_color)


func _on_connect_failed() -> void:
	connection_lost.emit("No se pudo conectar con el anfitrión")


func _on_server_disconnected() -> void:
	connection_lost.emit("El anfitrión se ha desconectado")


# ---------------------------------------------------------------- RPC: cliente -> servidor
@rpc("any_peer", "call_remote", "reliable")
func _srv_hello(pname: String, pref: int) -> void:
	if not is_host or in_match:
		return
	var id := multiplayer.get_remote_sender_id()
	if _slot_of_peer(id) >= 0:
		return
	var i := _free_slot()
	if i < 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	slots[i] = {"name": pname.strip_edges().substr(0, NAME_MAX), "color": free_color(pref, i), "peer": id}
	_broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _srv_pick_color(c: int) -> void:
	if not is_host or in_match:
		return
	_apply_color(_slot_of_peer(multiplayer.get_remote_sender_id()), c)


@rpc("any_peer", "call_remote", "reliable")
func _srv_input(dir: Vector2i) -> void:
	if not is_host:
		return
	if absi(dir.x) + absi(dir.y) != 1:
		return
	var i := _slot_of_peer(multiplayer.get_remote_sender_id())
	if i >= 0:
		remote_input.emit(i, dir)


func _apply_color(i: int, c: int) -> void:
	if i < 0 or c < 0 or c >= palette.size():
		return
	if c in used_colors(i):
		return   # color repetido: se rechaza
	slots[i]["color"] = c
	if i == 0:
		my_color = c
	_broadcast_lobby()


func _broadcast_lobby() -> void:
	_cl_lobby.rpc(slots)
	lobby_changed.emit()


# ---------------------------------------------------------------- RPC: servidor -> clientes
@rpc("authority", "call_remote", "reliable")
func _cl_lobby(s: Array) -> void:
	slots = s
	my_slot = _slot_of_peer(multiplayer.get_unique_id())
	if my_slot >= 0:
		my_color = int(slots[my_slot]["color"])
	lobby_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _cl_start(s: Array) -> void:
	slots = s
	my_slot = maxi(_slot_of_peer(multiplayer.get_unique_id()), 0)
	in_match = true
	match_started.emit()


@rpc("authority", "call_remote", "unreliable_ordered")
func _cl_state(st: Dictionary) -> void:
	state_received.emit(st)
