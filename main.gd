extends Control
## Pantallas: login -> menu -> (offline | online/sala) -> partida

const GameScript := preload("res://game.gd")
const GRAY := Color(0.70, 0.75, 0.80)
const RED := Color(1.0, 0.45, 0.45)
const GOLD := Color(1.0, 0.85, 0.30)

var ui: Control
var game: Node2D = null
var screen := ""
var notice := ""


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.08, 0.10)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Session.lobby_changed.connect(_on_lobby_changed)
	Session.match_started.connect(_on_match_started)
	Session.connection_lost.connect(_on_connection_lost)
	_show_login()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_ESCAPE and screen == "game":
			_to_menu()


# ================================================================ utilidades de UI
func _clear_ui() -> void:
	for c in ui.get_children():
		ui.remove_child(c)
		c.queue_free()


func _stop_game() -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
	game = null


func _screen() -> VBoxContainer:
	_stop_game()
	_clear_ui()
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	cc.add_child(vb)
	return vb


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _note(text: String, size: int, col: Color, width: float) -> Label:
	var l := _label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _button(text: String, cb: Callable, size: Vector2 = Vector2(420, 68)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.add_theme_font_size_override("font_size", 28)
	b.pressed.connect(cb)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _color_style(c: Color, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(10)
	if selected:
		sb.set_border_width_all(6)
		sb.border_color = Color.WHITE
	return sb


## Cuadricula de colores. `taken` = colores ocupados por otros (deshabilitados).
func _color_grid(selected: int, taken: Array, cb: Callable) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 4
	g.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	for i in Session.palette.size():
		var b := Button.new()
		b.text = Session.palette_names[i]
		b.custom_minimum_size = Vector2(130, 64)
		b.add_theme_font_size_override("font_size", 20)
		for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(n, Color.BLACK)
		b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))
		var c: Color = Session.palette[i]
		var sel := i == selected
		b.add_theme_stylebox_override("normal", _color_style(c, sel))
		b.add_theme_stylebox_override("hover", _color_style(c.lightened(0.15), sel))
		b.add_theme_stylebox_override("pressed", _color_style(c.darkened(0.15), sel))
		b.add_theme_stylebox_override("disabled", _color_style(c.darkened(0.6), false))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if i in taken:
			b.disabled = true
			b.text = "Ocupado"
		b.pressed.connect(cb.bind(i))
		g.add_child(b)
	return g


# ================================================================ pantallas
func _show_login() -> void:
	screen = "login"
	Session.leave()
	var vb := _screen()
	vb.add_child(_label("MULT SNAKE", 96, Color.WHITE))
	vb.add_child(_label("Snake 2 vs 2", 30, GRAY))
	vb.add_child(_spacer(20))
	vb.add_child(_label("Introduce tu nombre", 26, Color.WHITE))
	var edit := LineEdit.new()
	edit.text = Session.player_name
	edit.placeholder_text = "Tu nombre"
	edit.max_length = Session.NAME_MAX
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(420, 68)
	edit.add_theme_font_size_override("font_size", 30)
	vb.add_child(edit)
	var err := _label("", 20, RED)
	vb.add_child(err)
	vb.add_child(_button("ENTRAR", func(): _do_login(edit, err)))
	edit.text_submitted.connect(func(_t: String): _do_login(edit, err))
	if not OS.has_feature("mobile"):
		edit.grab_focus()


func _do_login(edit: LineEdit, err: Label) -> void:
	var n := edit.text.strip_edges()
	if n.length() < 1:
		err.text = "Escribe un nombre para entrar"
		return
	Session.player_name = n
	Session.save_profile()
	_show_menu()


func _show_menu() -> void:
	screen = "menu"
	Session.leave()
	var vb := _screen()
	vb.add_child(_label("MULT SNAKE", 72, Color.WHITE))
	vb.add_child(_label("Hola, %s" % Session.player_name, 30, GRAY))
	if notice != "":
		vb.add_child(_label(notice, 22, RED))
		notice = ""
	vb.add_child(_spacer(10))
	vb.add_child(_button("JUGAR ONLINE", func(): _show_online_menu()))
	vb.add_child(_button("JUGAR OFFLINE (vs IA)", func(): _show_offline_setup()))
	vb.add_child(_button("CAMBIAR NOMBRE", func(): _show_login()))
	if not OS.has_feature("web"):
		vb.add_child(_button("SALIR", func(): get_tree().quit()))


# ---------------------------------------------------------------- offline
func _show_offline_setup() -> void:
	screen = "offline"
	var vb := _screen()
	vb.add_child(_label("JUGAR OFFLINE", 56, Color.WHITE))
	vb.add_child(_label("Tu equipo: tú + 1 IA     contra     2 IA", 24, GRAY))
	vb.add_child(_label("Elige tu color", 28, Color.WHITE))
	vb.add_child(_color_grid(Session.my_color, [], func(i: int): _pick_offline(i)))
	vb.add_child(_label("Las IA usarán colores distintos al tuyo y entre ellas", 20, GRAY))
	vb.add_child(_button("¡JUGAR!", func(): Session.start_offline()))
	vb.add_child(_button("VOLVER", func(): _show_menu()))


func _pick_offline(i: int) -> void:
	Session.my_color = i
	Session.save_profile()
	_show_offline_setup()


# ---------------------------------------------------------------- online
func _show_online_menu() -> void:
	screen = "online"
	Session.leave()
	var vb := _screen()
	vb.add_child(_label("JUGAR ONLINE", 56, Color.WHITE))
	vb.add_child(_label("4 jugadores - 2 vs 2", 24, GRAY))
	vb.add_child(_label(notice, 22, RED))
	notice = ""
	vb.add_child(_button("CREAR PARTIDA", func(): _host()))
	vb.add_child(_label("o únete a la partida de otro jugador:", 24, Color.WHITE))
	var ip := LineEdit.new()
	ip.text = Session.last_ip
	ip.placeholder_text = "IP del anfitrión (ej. 192.168.1.20)"
	ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip.custom_minimum_size = Vector2(420, 64)
	ip.add_theme_font_size_override("font_size", 24)
	vb.add_child(ip)
	vb.add_child(_button("UNIRSE", func(): _join(ip.text)))
	vb.add_child(_note("Misma WiFi/red: funciona directo. Por Internet, el anfitrión debe abrir el puerto UDP %d en su router." % Session.PORT, 18, GRAY, 460))
	vb.add_child(_button("VOLVER", func(): _show_menu()))


func _host() -> void:
	if Session.host_game() != OK:
		notice = "No se pudo crear la partida (¿puerto %d ocupado?)" % Session.PORT
		_show_online_menu()
		return
	_show_lobby()


func _join(ip_text: String) -> void:
	var ip := ip_text.strip_edges()
	if ip == "":
		notice = "Escribe la IP del anfitrión"
		_show_online_menu()
		return
	Session.last_ip = ip
	Session.save_profile()
	if Session.join_game(ip) != OK:
		notice = "IP no válida"
		_show_online_menu()
		return
	_show_connecting(ip)


func _show_connecting(ip: String) -> void:
	screen = "connecting"
	var vb := _screen()
	vb.add_child(_label("Conectando con %s ..." % ip, 36, Color.WHITE))
	vb.add_child(_button("CANCELAR", func(): _show_online_menu()))


func _show_lobby() -> void:
	screen = "lobby"
	var vb := _screen()
	var humans := 0
	for s in Session.slots:
		if int(s["peer"]) > 0:
			humans += 1
	vb.add_child(_label("SALA ONLINE  (%d/4)" % humans, 48, Color.WHITE))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 50)
	vb.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	if Session.is_host:
		var ips := Session.local_ips()
		var ip_txt := ", ".join(ips) if not ips.is_empty() else "desconocida"
		left.add_child(_note("Comparte tu IP: %s  (puerto %d)" % [ip_txt, Session.PORT], 20, GOLD, 480))
	else:
		left.add_child(_note("Conectado a la sala", 20, GOLD, 480))
	for i in 4:
		left.add_child(_slot_row(i))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	cols.add_child(right)
	right.add_child(_label("Elige tu color (no se pueden repetir)", 22, Color.WHITE))
	right.add_child(_color_grid(Session.my_color, Session.used_colors(Session.my_slot), func(i: int): Session.pick_color(i)))
	if Session.is_host:
		right.add_child(_button("EMPEZAR PARTIDA", func(): Session.start_online_match()))
		right.add_child(_note("Los huecos libres los ocupará la IA", 18, GRAY, 400))
	else:
		right.add_child(_note("Esperando a que el anfitrión empiece...", 22, GRAY, 400))
	right.add_child(_button("SALIR DE LA SALA", func(): _show_online_menu()))


func _slot_row(i: int) -> HBoxContainer:
	var s: Dictionary = Session.slots[i]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.custom_minimum_size = Vector2(480, 46)
	var team := _label("EQ.%d" % ((i >> 1) + 1), 22, GRAY)
	team.custom_minimum_size = Vector2(70, 0)
	hb.add_child(team)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(36, 36)
	var c: int = s["color"]
	sw.color = Session.palette[c] if c >= 0 else Color(0.25, 0.28, 0.32)
	hb.add_child(sw)
	var txt := "Esperando jugador..."
	var col := Color(0.5, 0.55, 0.6)
	if int(s["peer"]) >= 0:
		txt = str(s["name"])
		col = Color.WHITE
	if i == Session.my_slot:
		txt += "  (tú)"
	var nm := _label(txt, 26, col)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hb.add_child(nm)
	return hb


# ================================================================ eventos
func _on_lobby_changed() -> void:
	if screen == "lobby":
		_show_lobby()
	elif screen == "connecting" and Session.my_slot >= 0 and int(Session.slots[Session.my_slot]["peer"]) > 0:
		_show_lobby()


func _on_connection_lost(reason: String) -> void:
	notice = reason
	_show_menu()


func _on_match_started() -> void:
	screen = "game"
	_stop_game()
	_clear_ui()
	game = GameScript.new()
	add_child(game)
	move_child(game, 1)   # entre el fondo y la UI
	game.match_finished.connect(_on_match_finished)
	var x := _button("X", func(): _to_menu(), Vector2(32, 32))
	x.add_theme_font_size_override("font_size", 16)
	ui.add_child(x)
	x.position = Vector2(4, 4)


func _on_match_finished() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	ui.add_child(hb)
	var w := 320.0
	if not Session.online:
		hb.add_child(_button("JUGAR OTRA VEZ", func(): _play_again(), Vector2(320, 64)))
		w = 660.0
	hb.add_child(_button("MENÚ", func(): _to_menu(), Vector2(320, 64)))
	hb.position = Vector2(640.0 - w / 2.0, 625.0)


func _play_again() -> void:
	_stop_game()
	Session.start_offline()


func _to_menu() -> void:
	_show_menu()
