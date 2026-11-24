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
const AVATAR_COUNT := 10
const ACCOUNT_PATH := "user://last_account.cfg"

var palette: Array = [
	Color(0.16, 0.45, 0.95), Color(0.05, 0.68, 0.62), Color(0.25, 0.75, 0.30), Color(0.98, 0.80, 0.10),
	Color(1.00, 0.55, 0.15), Color(0.92, 0.22, 0.25), Color(0.95, 0.40, 0.70), Color(0.55, 0.35, 0.90),
]
var palette_names: Array = ["Azul", "Turquesa", "Verde", "Amarillo", "Naranja", "Rojo", "Rosa", "Morado"]

var player_name := ""
var my_color := 0
var last_ip := ""
var avatar := 0
var account: Dictionary = {}        # cuenta con la sesion iniciada
var last_account: Dictionary = {}   # ultima cuenta de Google usada en este dispositivo
var _avatar_cache := {}
var online := false
var is_host := false
var in_match := false
# Cada hueco: {"name": String, "color": int, "peer": int, "avatar": int}
# peer: -1 = vacio, 0 = IA, >=1 = jugador humano (el anfitrion es 1)
var slots: Array = []
var my_slot := 0


func _ready() -> void:
	randomize()
	reset_slots()
	_load_last_account()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- cuenta y perfil
func _profile_path() -> String:
	if account.is_empty() or bool(account.get("guest", true)):
		return "user://profile.cfg"
	return "user://profile_%s.cfg" % str(account["id"]).validate_filename()


func _reset_profile() -> void:
	player_name = ""
	my_color = 0
	last_ip = ""
	avatar = 0


func _load_profile() -> void:
	_reset_profile()
	var cf := ConfigFile.new()
	if cf.load(_profile_path()) == OK:
		player_name = str(cf.get_value("profile", "name", ""))
		my_color = int(cf.get_value("profile", "color", 0)) % palette.size()
		last_ip = str(cf.get_value("profile", "ip", ""))
		avatar = clampi(int(cf.get_value("profile", "avatar", 0)), 0, AVATAR_COUNT - 1)


func save_profile() -> void:
	var cf := ConfigFile.new()
	cf.set_value("profile", "name", player_name)
	cf.set_value("profile", "color", my_color)
	cf.set_value("profile", "ip", last_ip)
	cf.set_value("profile", "avatar", avatar)
	cf.save(_profile_path())


func _load_last_account() -> void:
	var cf := ConfigFile.new()
	if cf.load(ACCOUNT_PATH) == OK:
		var id := str(cf.get_value("account", "id", ""))
		if id != "":
			last_account = {"id": id, "name": str(cf.get_value("account", "name", "")),
				"email": str(cf.get_value("account", "email", "")), "guest": false}


func _save_last_account() -> void:
	var cf := ConfigFile.new()
	cf.set_value("account", "id", last_account["id"])
	cf.set_value("account", "name", last_account["name"])
	cf.set_value("account", "email", last_account["email"])
	cf.save(ACCOUNT_PATH)


func login_guest() -> void:
	account = {"id": "guest", "name": "Invitado", "email": "", "guest": true}
	_load_profile()


## `user` = respuesta de Google (sub, name, given_name, email...)
func login_google(user: Dictionary) -> void:
	account = {"id": str(user.get("sub", "")), "name": str(user.get("name", "")),
		"email": str(user.get("email", "")), "guest": false}
	_load_profile()
	if player_name == "":
		player_name = str(user.get("given_name", user.get("name", ""))).strip_edges().substr(0, NAME_MAX)
		save_profile()
	last_account = account.duplicate()
	_save_last_account()


func continue_last() -> void:
	account = last_account.duplicate()
	_load_profile()


func logout() -> void:
	account = {}
	last_account = {}
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ACCOUNT_PATH))
	_reset_profile()


# ---------------------------------------------------------------- huecos y colores
func _empty_slot() -> Dictionary:
	return {"name": "", "color": -1, "peer": -1, "avatar": 0}


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
			slots[i] = {"name": "IA %d" % n, "color": random_free_color(i), "peer": 0, "avatar": randi() % AVATAR_COUNT}
			n += 1


## Imagen de perfil. `px` > 0 devuelve una copia reducida con buena calidad (evita dientes de sierra).
func avatar_texture(i: int, px: int = 0) -> Texture2D:
	i = clampi(i, 0, AVATAR_COUNT - 1)
	var key := "%d_%d" % [i, px]
	if _avatar_cache.has(key):
		return _avatar_cache[key]
	var path := "res://avatars/avatar_%02d.png" % (i + 1)
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
		if tex != null and px > 0 and px < tex.get_width():
			var img := tex.get_image()
			if img != null:
				if img.is_compressed():
					img.decompress()
				img.resize(px, px, Image.INTERPOLATE_LANCZOS)
				tex = ImageTexture.create_from_image(img)
	_avatar_cache[key] = tex
	return tex


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
	slots[0] = {"name": player_name, "color": my_color, "peer": 1, "avatar": avatar}
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
	slots[0] = {"name": player_name, "color": my_color, "peer": 1, "avatar": avatar}
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
	_srv_hello.rpc_id(1, player_name, my_color, avatar)


func _on_connect_failed() -> void:
	connection_lost.emit("No se pudo conectar con el anfitrión")


func _on_server_disconnected() -> void:
	connection_lost.emit("El anfitrión se ha desconectado")


# ---------------------------------------------------------------- RPC: cliente -> servidor
@rpc("any_peer", "call_remote", "reliable")
func _srv_hello(pname: String, pref: int, av: int) -> void:
	if not is_host or in_match:
		return
	var id := multiplayer.get_remote_sender_id()
	if _slot_of_peer(id) >= 0:
		return
	var i := _free_slot()
	if i < 0:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	slots[i] = {"name": pname.strip_edges().substr(0, NAME_MAX), "color": free_color(pref, i), "peer": id, "avatar": clampi(av, 0, AVATAR_COUNT - 1)}
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
