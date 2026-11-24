extends Control
## Multi-Snake - pantallas: menu principal (con perfil) -> offline | online/sala -> partida

const GameScript := preload("res://game.gd")
const MenuBg := preload("res://menu_bg.gd")
const GoogleAuth := preload("res://google_auth.gd")

const GAME_TITLE := "Multi-Snake"
const VERSION := "v0.5"
const NAVY := Color(0.10, 0.16, 0.30)
const GRAY := Color(0.78, 0.84, 0.92)
const RED := Color(1.0, 0.55, 0.55)
const GOLD := Color(1.0, 0.85, 0.30)
const C_BLUE := Color(0.20, 0.45, 0.95)
const C_GREEN := Color(0.20, 0.70, 0.40)
const C_ORANGE := Color(1.0, 0.58, 0.15)
const C_RED := Color(0.88, 0.32, 0.38)
const C_SLATE := Color(0.40, 0.47, 0.62)

var bg3d = null
var auth = null
var ui: Control
var game: Node2D = null
var screen := ""
var notice := ""
var tmp_avatar := 0


func _ready() -> void:
	theme = _make_theme()
	bg3d = MenuBg.new()
	add_child(bg3d)
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Session.lobby_changed.connect(_on_lobby_changed)
	Session.match_started.connect(_on_match_started)
	Session.connection_lost.connect(_on_connection_lost)
	auth = GoogleAuth.new()
	add_child(auth)
	_show_login()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and k.keycode == KEY_ESCAPE and screen == "game":
			_to_menu()


# ================================================================ tema y estilos
func _make_theme() -> Theme:
	var th := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Nunito", "Poppins", "Arial Rounded MT Bold", "Segoe UI", "Roboto", "Arial"])
	f.font_weight = 700
	th.default_font = f
	th.default_font_size = 24
	# botones redondeados
	th.set_stylebox("normal", "Button", _pill(C_BLUE, 34, false))
	th.set_stylebox("hover", "Button", _pill(C_BLUE.lightened(0.12), 34, false))
	th.set_stylebox("pressed", "Button", _pill(C_BLUE.darkened(0.15), 34, true))
	th.set_stylebox("disabled", "Button", _pill(Color(0.45, 0.50, 0.60), 34, false))
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(n, "Button", Color.WHITE)
	th.set_color("font_disabled_color", "Button", Color(1, 1, 1, 0.6))
	th.set_font_size("font_size", "Button", 28)
	# campos de texto redondeados
	var le := StyleBoxFlat.new()
	le.bg_color = Color.WHITE
	le.set_corner_radius_all(28)
	le.set_border_width_all(4)
	le.border_color = Color(0.70, 0.80, 0.95)
	le.content_margin_left = 24
	le.content_margin_right = 24
	le.content_margin_top = 12
	le.content_margin_bottom = 12
	th.set_stylebox("normal", "LineEdit", le)
	var lf: StyleBoxFlat = le.duplicate()
	lf.border_color = C_ORANGE
	th.set_stylebox("focus", "LineEdit", lf)
	th.set_color("font_color", "LineEdit", NAVY)
	th.set_color("font_placeholder_color", "LineEdit", Color(0.50, 0.55, 0.65))
	th.set_color("caret_color", "LineEdit", NAVY)
	th.set_color("font_selected_color", "LineEdit", Color.WHITE)
	th.set_color("selection_color", "LineEdit", C_BLUE)
	return th


func _pill(col: Color, radius: int, pressed: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	sb.border_width_bottom = 2 if pressed else 7
	sb.border_width_top = 5 if pressed else 0
	sb.border_color = col.darkened(0.3)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 3 if pressed else 9
	sb.shadow_offset = Vector2(0, 3 if pressed else 6)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _style_button(b: Button, col: Color) -> void:
	b.add_theme_stylebox_override("normal", _pill(col, 34, false))
	b.add_theme_stylebox_override("hover", _pill(col.lightened(0.12), 34, false))
	b.add_theme_stylebox_override("pressed", _pill(col.darkened(0.15), 34, true))


func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.12, 0.25, 0.88)
	sb.set_corner_radius_all(40)
	sb.set_border_width_all(3)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_size = 18
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	return sb


# ================================================================ utilidades de UI
func _clear_ui() -> void:
	for c in ui.get_children():
		ui.remove_child(c)
		c.queue_free()


func _stop_game() -> void:
	if game != null and is_instance_valid(game):
		game.queue_free()
	game = null


func _show_bg(on: bool) -> void:
	if bg3d != null:
		bg3d.set_active(on)


## Prepara una pantalla de menu. Con `card` el contenido va dentro de una tarjeta redondeada.
func _screen(card: bool = true) -> VBoxContainer:
	_stop_game()
	_clear_ui()
	_show_bg(true)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	if card:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _card_style())
		cc.add_child(panel)
		panel.add_child(vb)
	else:
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


func _button(text: String, cb: Callable, size: Vector2 = Vector2(420, 68), col: Color = Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = size
	b.pressed.connect(cb)
	if col.a > 0.0:
		_style_button(b, col)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Etiqueta dentro de una "pastilla" redondeada (legible sobre el fondo 3D).
func _pill_label(text: String, size: int, bg: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(30)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 6
	sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(_label(text, size, Color.WHITE))
	return p


func _avatar_rect(i: int, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Session.avatar_texture(i, mini(int(size * 2.0), 256))
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


func _color_style(c: Color, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(18)
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


# ================================================================ login
func _add_title(vb: VBoxContainer) -> void:
	var title := _label(GAME_TITLE, 124, Color.WHITE)
	title.add_theme_color_override("font_outline_color", NAVY)
	title.add_theme_constant_override("outline_size", 20)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	title.add_theme_constant_override("shadow_offset_y", 8)
	vb.add_child(title)
	vb.add_child(_pill_label("Snake  2 vs 2", 28, Color(0.10, 0.16, 0.30, 0.80)))


func _google_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(500, 84)
	b.pressed.connect(cb)
	var tex = null
	if ResourceLoader.exists("res://ui/google_g.png"):
		tex = load("res://ui/google_g.png")
	if tex != null:
		b.icon = tex
		b.add_theme_constant_override("h_separation", 18)
	b.add_theme_stylebox_override("normal", _pill(Color(1, 1, 1), 34, false))
	b.add_theme_stylebox_override("hover", _pill(Color(0.93, 0.96, 1.0), 34, false))
	b.add_theme_stylebox_override("pressed", _pill(Color(0.86, 0.91, 0.98), 34, true))
	for n in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(n, NAVY)
	return b


func _show_login() -> void:
	screen = "login"
	Session.leave()
	if auth != null:
		auth.cancel()
	var vb := _screen(false)
	vb.add_theme_constant_override("separation", 14)
	_add_title(vb)
	vb.add_child(_spacer(10))
	if notice != "":
		vb.add_child(_pill_label(notice, 22, Color(0.78, 0.22, 0.30, 0.92)))
		notice = ""
	if not Session.last_account.is_empty():
		var who := str(Session.last_account.get("name", ""))
		var cont := _button("CONTINUAR COMO %s" % who.to_upper(), func(): _continue_last(), Vector2(500, 84), C_GREEN)
		cont.add_theme_font_size_override("font_size", 24)
		vb.add_child(cont)
	vb.add_child(_google_button("ENTRAR CON GOOGLE", func(): _start_google_login()))
	vb.add_child(_button("JUGAR COMO INVITADO", func(): _login_guest(), Vector2(500, 60), C_SLATE))


func _continue_last() -> void:
	Session.continue_last()
	_after_login()


func _login_guest() -> void:
	Session.login_guest()
	_after_login()


func _after_login() -> void:
	_show_menu()
	if Session.player_name == "":
		_show_profile(true)


func _logout() -> void:
	Session.logout()
	_show_login()


func _account_text() -> String:
	if bool(Session.account.get("guest", true)):
		return "Jugando como invitado"
	return "Cuenta de Google: %s" % str(Session.account.get("email", ""))


func _start_google_login() -> void:
	if not auth.load_config():
		notice = "Falta configurar google_oauth.cfg (mira el README)"
		_show_login()
		return
	screen = "google"
	var vb := _screen()
	vb.add_child(_label("Conectando con Google...", 40, Color.WHITE))
	vb.add_child(_button("CANCELAR", func(): _cancel_google(), Vector2(420, 60), C_SLATE))
	var info: Dictionary = await auth.request_device_code()
	if screen != "google" or int(info.get("_flow", -1)) != auth.flow:
		return   # cancelado mientras esperaba
	if info.has("error"):
		notice = str(info["error"])
		_show_login()
		return
	_show_google_code(info)
	var user: Dictionary = await auth.poll_for_token(info)
	if user.has("cancelled") or screen != "google":
		return
	if user.has("error"):
		notice = str(user["error"])
		_show_login()
		return
	Session.login_google(user)
	_after_login()


func _show_google_code(info: Dictionary) -> void:
	var url := str(info.get("verification_url", "https://www.google.com/device"))
	var code := str(info.get("user_code", ""))
	var vb := _screen()
	vb.add_child(_label("Inicia sesión con Google", 42, Color.WHITE))
	vb.add_child(_note("1. Abre  %s  en un navegador (puede ser el de tu móvil)\n2. Introduce este código y acepta:" % url, 22, GRAY, 600))
	vb.add_child(_pill_label(code, 72, Color(0.20, 0.30, 0.65, 1.0)))
	vb.add_child(_label("Esperando a que confirmes en Google...", 20, GOLD))
	vb.add_child(_button("ABRIR GOOGLE Y COPIAR CÓDIGO", func(): _open_google(url, code), Vector2(520, 64), C_BLUE))
	vb.add_child(_button("CANCELAR", func(): _cancel_google(), Vector2(520, 58), C_SLATE))


func _open_google(url: String, code: String) -> void:
	DisplayServer.clipboard_set(code)
	OS.shell_open(url)


func _cancel_google() -> void:
	auth.cancel()
	_show_login()


# ================================================================ menu principal
func _show_menu() -> void:
	screen = "menu"
	Session.leave()
	var vb := _screen(false)
	vb.add_theme_constant_override("separation", 16)

	_add_title(vb)
	vb.add_child(_spacer(14))
	if notice != "":
		vb.add_child(_pill_label(notice, 22, Color(0.78, 0.22, 0.30, 0.92)))
		notice = ""
	vb.add_child(_button("JUGAR ONLINE", func(): _show_online_menu(), Vector2(500, 92), C_BLUE))
	vb.add_child(_button("JUGAR OFFLINE  (vs IA)", func(): _show_offline_setup(), Vector2(500, 92), C_ORANGE))
	if not OS.has_feature("web"):
		vb.add_child(_button("SALIR", func(): get_tree().quit(), Vector2(500, 64), C_RED))

	ui.add_child(_profile_chip())
	var ver := _label(VERSION, 18, NAVY)
	ui.add_child(ver)
	ver.position = Vector2(18, 690)


# ---------------------------------------------------------------- perfil
func _profile_chip() -> Button:
	var w := 330.0
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, 80)
	b.add_theme_stylebox_override("normal", _pill(Color(1, 1, 1, 0.95), 40, false))
	b.add_theme_stylebox_override("hover", _pill(Color(0.92, 0.96, 1.0, 1.0), 40, false))
	b.add_theme_stylebox_override("pressed", _pill(Color(0.85, 0.92, 1.0, 1.0), 40, true))
	b.pressed.connect(func(): _show_profile(false))
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 22)
	m.add_theme_constant_override("margin_top", 8)
	m.add_theme_constant_override("margin_bottom", 10)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 14)
	m.add_child(hb)
	hb.add_child(_avatar_rect(Session.avatar, 60))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -2)
	hb.add_child(col)
	var nm := _label(Session.player_name if Session.player_name != "" else "Jugador", 26, NAVY)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)
	var ed := _label("Editar perfil", 15, Color(0.35, 0.45, 0.65))
	ed.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(ed)
	b.position = Vector2(1280.0 - w - 24.0, 20.0)
	return b


func _avatar_style(selected: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.30 if selected else (0.20 if hover else 0.10))
	sb.set_corner_radius_all(50)
	if selected:
		sb.set_border_width_all(6)
		sb.border_color = GOLD
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _show_profile(forced: bool) -> void:
	tmp_avatar = Session.avatar
	var layer := Control.new()
	layer.name = "ProfileLayer"
	ui.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.12, 0.62)
	layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _card_style())
	cc.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)

	vb.add_child(_label("¡BIENVENIDO A %s!" % GAME_TITLE.to_upper() if forced else "TU PERFIL", 38, Color.WHITE))
	vb.add_child(_label(_account_text(), 18, GRAY))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 40)
	vb.add_child(body)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(330, 0)
	body.add_child(left)
	var preview := _avatar_rect(tmp_avatar, 130)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	left.add_child(preview)
	left.add_child(_label("Tu nombre", 22, GRAY))
	var edit := LineEdit.new()
	edit.text = Session.player_name
	edit.placeholder_text = "Escribe tu nombre"
	edit.max_length = Session.NAME_MAX
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(330, 62)
	edit.add_theme_font_size_override("font_size", 28)
	left.add_child(edit)
	var err := _label("", 20, RED)
	left.add_child(err)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	body.add_child(right)
	right.add_child(_label("Elige tu imagen", 22, GRAY))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	right.add_child(grid)
	var btns: Array = []
	for i in Session.AVATAR_COUNT:
		var b := Button.new()
		b.custom_minimum_size = Vector2(88, 88)
		b.icon = Session.avatar_texture(i, 160)
		b.expand_icon = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _pick_avatar(i, btns, preview))
		grid.add_child(b)
		btns.append(b)
	_refresh_avatars(btns, preview)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	vb.add_child(row)
	row.add_child(_button("GUARDAR", func(): _save_profile(edit, err), Vector2(220, 60), C_GREEN))
	if not forced:
		row.add_child(_button("CANCELAR", func(): _close_profile(), Vector2(220, 60), C_SLATE))
	row.add_child(_button("CERRAR SESIÓN", func(): _logout(), Vector2(260, 60), C_RED))
	edit.text_submitted.connect(func(_t: String): _save_profile(edit, err))
	if not OS.has_feature("mobile"):
		edit.grab_focus()


func _pick_avatar(i: int, btns: Array, preview: TextureRect) -> void:
	tmp_avatar = i
	_refresh_avatars(btns, preview)


func _refresh_avatars(btns: Array, preview: TextureRect) -> void:
	for i in btns.size():
		var b: Button = btns[i]
		var sel := i == tmp_avatar
		b.add_theme_stylebox_override("normal", _avatar_style(sel, false))
		b.add_theme_stylebox_override("hover", _avatar_style(sel, true))
		b.add_theme_stylebox_override("pressed", _avatar_style(true, true))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	preview.texture = Session.avatar_texture(tmp_avatar, 260)


func _save_profile(edit: LineEdit, err: Label) -> void:
	var n := edit.text.strip_edges()
	if n.is_empty():
		err.text = "Escribe un nombre para entrar"
		return
	Session.player_name = n
	Session.avatar = tmp_avatar
	Session.save_profile()
	_show_menu()   # reconstruye el menu: cierra el perfil y actualiza el icono


func _close_profile() -> void:
	var layer := ui.get_node_or_null("ProfileLayer")
	if layer != null:
		ui.remove_child(layer)
		layer.queue_free()


# ================================================================ offline
func _show_offline_setup() -> void:
	screen = "offline"
	var vb := _screen()
	vb.add_child(_label("JUGAR OFFLINE", 52, Color.WHITE))
	vb.add_child(_label("Tu equipo: tú + 1 IA     contra     2 IA", 24, GRAY))
	vb.add_child(_label("Elige tu color", 28, Color.WHITE))
	vb.add_child(_color_grid(Session.my_color, [], func(i: int): _pick_offline(i)))
	vb.add_child(_label("Las IA usarán colores distintos al tuyo y entre ellas", 20, GRAY))
	vb.add_child(_button("¡JUGAR!", func(): Session.start_offline(), Vector2(420, 68), C_GREEN))
	vb.add_child(_button("VOLVER", func(): _show_menu(), Vector2(420, 60), C_SLATE))


func _pick_offline(i: int) -> void:
	Session.my_color = i
	Session.save_profile()
	_show_offline_setup()


# ================================================================ online
func _show_online_menu() -> void:
	screen = "online"
	Session.leave()
	var vb := _screen()
	vb.add_child(_label("JUGAR ONLINE", 52, Color.WHITE))
	vb.add_child(_label("4 jugadores - 2 vs 2", 24, GRAY))
	if notice != "":
		vb.add_child(_label(notice, 22, RED))
		notice = ""
	vb.add_child(_button("CREAR PARTIDA", func(): _host(), Vector2(420, 68), C_GREEN))
	vb.add_child(_label("o únete a la partida de otro jugador:", 24, Color.WHITE))
	var ip := LineEdit.new()
	ip.text = Session.last_ip
	ip.placeholder_text = "IP del anfitrión (ej. 192.168.1.20)"
	ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip.custom_minimum_size = Vector2(420, 62)
	ip.add_theme_font_size_override("font_size", 24)
	vb.add_child(ip)
	vb.add_child(_button("UNIRSE", func(): _join(ip.text), Vector2(420, 64)))
	vb.add_child(_note("Misma WiFi/red: funciona directo. Por Internet, el anfitrión debe abrir el puerto UDP %d en su router." % Session.PORT, 18, GRAY, 460))
	vb.add_child(_button("VOLVER", func(): _show_menu(), Vector2(420, 58), C_SLATE))


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
	vb.add_child(_button("CANCELAR", func(): _show_online_menu(), Vector2(420, 64), C_SLATE))


func _show_lobby() -> void:
	screen = "lobby"
	var vb := _screen()
	var humans := 0
	for s in Session.slots:
		if int(s["peer"]) > 0:
			humans += 1
	vb.add_child(_label("SALA ONLINE  (%d/4)" % humans, 46, Color.WHITE))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 46)
	vb.add_child(cols)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	cols.add_child(left)
	if Session.is_host:
		var ips := Session.local_ips()
		var ip_txt := ", ".join(ips) if not ips.is_empty() else "desconocida"
		left.add_child(_note("Comparte tu IP: %s  (puerto %d)" % [ip_txt, Session.PORT], 20, GOLD, 520))
	else:
		left.add_child(_note("Conectado a la sala", 20, GOLD, 520))
	for i in 4:
		left.add_child(_slot_row(i))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	cols.add_child(right)
	right.add_child(_label("Elige tu color (no se pueden repetir)", 22, Color.WHITE))
	right.add_child(_color_grid(Session.my_color, Session.used_colors(Session.my_slot), func(i: int): Session.pick_color(i)))
	if Session.is_host:
		right.add_child(_button("EMPEZAR PARTIDA", func(): Session.start_online_match(), Vector2(420, 68), C_GREEN))
		right.add_child(_note("Los huecos libres los ocupará la IA", 18, GRAY, 400))
	else:
		right.add_child(_note("Esperando a que el anfitrión empiece...", 22, GRAY, 400))
	right.add_child(_button("SALIR DE LA SALA", func(): _show_online_menu(), Vector2(420, 60), C_RED))


func _slot_row(i: int) -> HBoxContainer:
	var s: Dictionary = Session.slots[i]
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.custom_minimum_size = Vector2(520, 50)
	var team := _label("EQ.%d" % ((i >> 1) + 1), 22, GRAY)
	team.custom_minimum_size = Vector2(62, 0)
	hb.add_child(team)
	if int(s["peer"]) >= 0:
		hb.add_child(_avatar_rect(int(s["avatar"]), 46))
	else:
		hb.add_child(_spacer(0))
		hb.get_child(hb.get_child_count() - 1).custom_minimum_size = Vector2(46, 46)
	var sw := ColorRect.new()
	sw.custom_minimum_size = Vector2(30, 30)
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var c: int = s["color"]
	sw.color = Session.palette[c] if c >= 0 else Color(0.25, 0.28, 0.32)
	hb.add_child(sw)
	var txt := "Esperando jugador..."
	var col := Color(0.55, 0.60, 0.68)
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
	_show_bg(false)
	game = GameScript.new()
	add_child(game)
	move_child(game, 1)   # entre el fondo 3D y la UI
	game.match_finished.connect(_on_match_finished)
	var x := _button("X", func(): _to_menu(), Vector2(34, 34), C_SLATE)
	x.add_theme_font_size_override("font_size", 16)
	ui.add_child(x)
	x.position = Vector2(4, 4)


func _on_match_finished() -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	ui.add_child(hb)
	var w := 320.0
	if not Session.online:
		hb.add_child(_button("JUGAR OTRA VEZ", func(): _play_again(), Vector2(320, 64), C_GREEN))
		w = 660.0
	hb.add_child(_button("MENÚ", func(): _to_menu(), Vector2(320, 64), C_BLUE))
	hb.position = Vector2(640.0 - w / 2.0, 625.0)


func _play_again() -> void:
	_stop_game()
	Session.start_offline()


func _to_menu() -> void:
	_show_menu()
