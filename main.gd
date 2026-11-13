extends Node2D
## Mult Snake - Snake 2 vs 2 (4 jugadores en la misma pantalla)

const COLS := 50
const ROWS := 26
const CELL := 24
const ORIGIN := Vector2(40, 70)
const SCREEN := Vector2(1280, 720)

const GAME_TIME := 120.0
const PHASE2_AT := 60.0          # segundos transcurridos
const PHASE3_AT := 90.0
const BASE_STEP := 0.14          # segundos por casilla a velocidad normal
const SPEED_FACTOR := 0.25       # +-1/4 de velocidad
const SPEED_EFFECT_TIME := 6.0
const RESPAWN_TIME := 5.0
const MAX_FOOD := 14
const MAX_WALLS := 40
const BIG_CHANCE := 5            # 1 de cada 5
const SPEED_CHANCE := 5          # 1 de cada 5

enum State { MENU, PLAYING, ENDED }
enum Item { FOOD, BIG, SLOW, FAST }

const START_POS := [Vector2i(4, 4), Vector2i(4, 21), Vector2i(45, 4), Vector2i(45, 21)]
const START_DIR := [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.LEFT]
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

# Teclado: [jugador, direccion]
const KEYMAP := {
	KEY_W: [0, Vector2i.UP], KEY_S: [0, Vector2i.DOWN], KEY_A: [0, Vector2i.LEFT], KEY_D: [0, Vector2i.RIGHT],
	KEY_T: [1, Vector2i.UP], KEY_G: [1, Vector2i.DOWN], KEY_F: [1, Vector2i.LEFT], KEY_H: [1, Vector2i.RIGHT],
	KEY_I: [2, Vector2i.UP], KEY_K: [2, Vector2i.DOWN], KEY_J: [2, Vector2i.LEFT], KEY_L: [2, Vector2i.RIGHT],
	KEY_UP: [3, Vector2i.UP], KEY_DOWN: [3, Vector2i.DOWN], KEY_LEFT: [3, Vector2i.LEFT], KEY_RIGHT: [3, Vector2i.RIGHT],
}

var colors := [Color(0.29, 0.64, 1.0), Color(0.18, 0.90, 0.84), Color(1.0, 0.35, 0.35), Color(1.0, 0.70, 0.28)]
var team_names := ["AZUL", "ROJO"]

var state: int = State.MENU
var snakes: Array = []
var walls := {}
var items := {}
var time_left := GAME_TIME
var spawn_item_t := 0.0
var spawn_wall_t := 0.0
var ended_lock := 0.0
var touch_start := {}


func _ready() -> void:
	randomize()


# ---------------------------------------------------------------- partida
func start_game() -> void:
	walls.clear()
	items.clear()
	snakes.clear()
	time_left = GAME_TIME
	spawn_item_t = 0.0
	spawn_wall_t = 0.0
	for i in 4:
		var s := {
			"alive": true, "body": [], "dir": START_DIR[i], "next_dir": START_DIR[i],
			"score": 0, "acc": 0.0, "mult": 1.0, "mult_t": 0.0, "grow": 0, "respawn_t": 0.0,
		}
		_place(s, START_POS[i], START_DIR[i])
		snakes.append(s)
	for k in 5:
		_spawn_item(Item.FOOD)
	state = State.PLAYING


func _place(s: Dictionary, pos: Vector2i, dir: Vector2i) -> void:
	s["alive"] = true
	s["dir"] = dir
	s["next_dir"] = dir
	s["body"] = [pos, pos - dir, pos - dir * 2]
	s["grow"] = 0
	s["acc"] = 0.0
	s["mult"] = 1.0
	s["mult_t"] = 0.0


func _process(delta: float) -> void:
	if ended_lock > 0.0:
		ended_lock -= delta
	if state == State.PLAYING:
		time_left -= delta
		if time_left <= 0.0:
			time_left = 0.0
			state = State.ENDED
			ended_lock = 1.0
		else:
			_update_spawns(delta)
			for i in 4:
				_update_snake(i, delta)
	queue_redraw()


func _update_snake(i: int, delta: float) -> void:
	var s: Dictionary = snakes[i]
	if not s["alive"]:
		s["respawn_t"] -= delta
		if s["respawn_t"] <= 0.0:
			_try_respawn(i)
		return
	if s["mult_t"] > 0.0:
		s["mult_t"] -= delta
		if s["mult_t"] <= 0.0:
			s["mult"] = 1.0
	s["acc"] += delta
	var interval: float = BASE_STEP / float(s["mult"])
	if s["acc"] >= interval:
		s["acc"] -= interval
		_step(i)


func _step(i: int) -> void:
	var s: Dictionary = snakes[i]
	var dir: Vector2i = s["next_dir"]
	s["dir"] = dir
	var body: Array = s["body"]
	var head: Vector2i = body[0] + dir
	if s["grow"] > 0:
		s["grow"] -= 1
	else:
		body.pop_back()
	if _blocked(head):
		_kill(i)
		return
	body.push_front(head)
	if items.has(head):
		var t: int = items[head]
		if t == Item.FOOD:
			s["grow"] += 1
			s["score"] += 1
		elif t == Item.BIG:
			s["grow"] += 2
			s["score"] += 2
		elif t == Item.SLOW:
			s["mult"] = 1.0 - SPEED_FACTOR
			s["mult_t"] = SPEED_EFFECT_TIME
		elif t == Item.FAST:
			s["mult"] = 1.0 + SPEED_FACTOR
			s["mult_t"] = SPEED_EFFECT_TIME
		items.erase(head)


func _kill(i: int) -> void:
	var s: Dictionary = snakes[i]
	s["alive"] = false
	s["body"] = []
	s["respawn_t"] = RESPAWN_TIME


func _blocked(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= COLS or c.y >= ROWS:
		return true
	if walls.has(c):
		return true
	for s in snakes:
		if s["alive"] and c in s["body"]:
			return true
	return false


func _try_respawn(i: int) -> void:
	for attempt in 200:
		var c := Vector2i(randi_range(5, COLS - 6), randi_range(5, ROWS - 6))
		if _area_free(c, 4):
			var d: Vector2i = DIRS[randi() % 4]
			_place(snakes[i], c, d)
			items.erase(c)
			return
	snakes[i]["respawn_t"] = 0.3   # reintentar enseguida


func _area_free(c: Vector2i, r: int) -> bool:
	for x in range(-r, r + 1):
		for y in range(-r, r + 1):
			var cell := c + Vector2i(x, y)
			if walls.has(cell):
				return false
			for s in snakes:
				if s["alive"] and cell in s["body"]:
					return false
	return true


# ---------------------------------------------------------------- aparicion de cubos
func _update_spawns(delta: float) -> void:
	var elapsed := GAME_TIME - time_left
	spawn_item_t -= delta
	if spawn_item_t <= 0.0:
		spawn_item_t = 1.0
		if _count_food() < MAX_FOOD:
			if elapsed >= PHASE2_AT and randi() % BIG_CHANCE == 0:
				_spawn_item(Item.BIG)
			else:
				_spawn_item(Item.FOOD)
		if elapsed >= PHASE3_AT and randi() % SPEED_CHANCE == 0:
			_spawn_item(Item.SLOW if randi() % 2 == 0 else Item.FAST)
	if elapsed >= PHASE3_AT:
		spawn_wall_t -= delta
		if spawn_wall_t <= 0.0:
			spawn_wall_t = 2.0
			if walls.size() < MAX_WALLS:
				_spawn_wall()


func _count_food() -> int:
	var n := 0
	for t in items.values():
		if t == Item.FOOD or t == Item.BIG:
			n += 1
	return n


func _is_free(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= COLS or c.y >= ROWS:
		return false
	if walls.has(c) or items.has(c):
		return false
	for s in snakes:
		if s["alive"] and c in s["body"]:
			return false
	return true


func _random_free() -> Vector2i:
	for attempt in 100:
		var c := Vector2i(randi() % COLS, randi() % ROWS)
		if _is_free(c):
			return c
	return Vector2i(-1, -1)


func _spawn_item(t: int) -> void:
	var c := _random_free()
	if c.x >= 0:
		items[c] = t


func _spawn_wall() -> void:
	for attempt in 50:
		var c := _random_free()
		if c.x < 0:
			return
		var ok := true
		for s in snakes:
			if not s["alive"]:
				continue
			var h: Vector2i = s["body"][0]
			var d: Vector2i = s["dir"]
			for k in range(0, 6):   # no aparecer justo delante de una cabeza
				if h + d * k == c:
					ok = false
		if ok:
			walls[c] = true
			return


# ---------------------------------------------------------------- entrada
func _set_dir(i: int, dir: Vector2i) -> void:
	if i >= snakes.size():
		return
	var s: Dictionary = snakes[i]
	if not s["alive"]:
		return
	var cur: Vector2i = s["dir"]
	if dir == -cur:
		return
	s["next_dir"] = dir


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if not k.pressed or k.echo:
			return
		if state != State.PLAYING:
			if k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and ended_lock <= 0.0:
				start_game()
			return
		if KEYMAP.has(k.keycode):
			var m: Array = KEYMAP[k.keycode]
			_set_dir(m[0], m[1])
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.pressed and state != State.PLAYING and ended_lock <= 0.0:
			start_game()
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			if state != State.PLAYING:
				if ended_lock <= 0.0:
					start_game()
				return
			touch_start[t.index] = t.position
		else:
			touch_start.erase(t.index)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if state == State.PLAYING and touch_start.has(d.index):
			var origin: Vector2 = touch_start[d.index]
			var delta: Vector2 = d.position - origin
			if delta.length() >= 28.0:
				var dir: Vector2i
				if absf(delta.x) > absf(delta.y):
					dir = Vector2i.RIGHT if delta.x > 0.0 else Vector2i.LEFT
				else:
					dir = Vector2i.DOWN if delta.y > 0.0 else Vector2i.UP
				# Cuadrantes de pantalla: J1 arriba-izq, J2 abajo-izq, J3 arriba-der, J4 abajo-der
				var col := 0 if origin.x < SCREEN.x / 2.0 else 1
				var row := 0 if origin.y < SCREEN.y / 2.0 else 1
				_set_dir(col * 2 + row, dir)
				touch_start[d.index] = d.position


# ---------------------------------------------------------------- dibujo
func _team_score(t: int) -> int:
	if snakes.size() < 4:
		return 0
	return int(snakes[t * 2]["score"]) + int(snakes[t * 2 + 1]["score"])


func _rect(c: Vector2i, inset: float) -> Rect2:
	return Rect2(ORIGIN + Vector2(c) * CELL + Vector2(inset, inset), Vector2(CELL - inset * 2.0, CELL - inset * 2.0))


func _text(txt: String, pos: Vector2, size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(ThemeDB.fallback_font, pos, txt, align, width, size, col)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.06, 0.08, 0.10))
	var arena := Rect2(ORIGIN, Vector2(COLS * CELL, ROWS * CELL))
	draw_rect(arena, Color(0.09, 0.12, 0.15))
	draw_rect(arena, Color(0.36, 0.40, 0.45), false, 3.0)
	# guias de cuadrantes tactiles
	var faint := Color(1, 1, 1, 0.05)
	draw_line(Vector2(SCREEN.x / 2.0, ORIGIN.y), Vector2(SCREEN.x / 2.0, ORIGIN.y + ROWS * CELL), faint, 2.0)
	draw_line(Vector2(ORIGIN.x, SCREEN.y / 2.0), Vector2(ORIGIN.x + COLS * CELL, SCREEN.y / 2.0), faint, 2.0)

	# paredes
	for c in walls.keys():
		draw_rect(_rect(c, 1.0), Color(0.30, 0.32, 0.36))
		draw_rect(_rect(c, 4.0), Color(0.55, 0.58, 0.64))
	# items
	for c in items.keys():
		var t: int = items[c]
		if t == Item.FOOD:
			draw_rect(_rect(c, 6.0), Color(0.40, 0.90, 0.40))
		elif t == Item.BIG:
			draw_rect(_rect(c, 3.0), Color(1.0, 0.85, 0.20))
		elif t == Item.SLOW:
			draw_rect(_rect(c, 3.0), Color(0.60, 0.42, 1.0))
			_text("-", _rect(c, 0.0).position + Vector2(0, 18), 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, CELL)
		elif t == Item.FAST:
			draw_rect(_rect(c, 3.0), Color(0.20, 0.85, 1.0))
			_text("+", _rect(c, 0.0).position + Vector2(0, 18), 20, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, CELL)
	# serpientes
	for i in snakes.size():
		var s: Dictionary = snakes[i]
		if not s["alive"]:
			continue
		var body: Array = s["body"]
		for j in body.size():
			var col: Color = colors[i]
			if j == 0:
				col = col.lightened(0.45)
			draw_rect(_rect(body[j], 1.0), col)

	_draw_hud()
	if state == State.MENU:
		_draw_menu()
	elif state == State.ENDED:
		_draw_end()


func _draw_hud() -> void:
	_text("%s: %d" % [team_names[0], _team_score(0)], Vector2(40, 36), 28, colors[0])
	_text("%s: %d" % [team_names[1], _team_score(1)], Vector2(40, 36), 28, colors[2], HORIZONTAL_ALIGNMENT_RIGHT, 1200.0)
	var secs := int(ceil(time_left))
	_text("%d:%02d" % [secs / 60, secs % 60], Vector2(0, 36), 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	var elapsed := GAME_TIME - time_left
	var phase := "Fase 1: puntos +1"
	if elapsed >= PHASE3_AT:
		phase = "Fase 3: paredes y velocidad"
	elif elapsed >= PHASE2_AT:
		phase = "Fase 2: puntos +2 (1/5)"
	_text(phase, Vector2(0, 58), 16, Color(0.7, 0.75, 0.8), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	var xs := [40.0, 210.0, 880.0, 1050.0]
	for i in snakes.size():
		var s: Dictionary = snakes[i]
		var txt := "J%d: %d" % [i + 1, s["score"]]
		if not s["alive"]:
			txt += "  (reaparece %d)" % int(ceil(s["respawn_t"]))
		elif s["mult"] > 1.0:
			txt += " [+]"
		elif s["mult"] < 1.0:
			txt += " [-]"
		_text(txt, Vector2(xs[i], 58), 16, colors[i])


func _draw_menu() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, 0.7))
	_text("MULT SNAKE", Vector2(0, 220), 72, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("2 vs 2  -  2 minutos", Vector2(0, 270), 28, Color(0.8, 0.85, 0.9), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("PC:  J1 WASD   J2 TFGH   J3 IJKL   J4 Flechas", Vector2(0, 350), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("Movil: desliza el dedo en tu cuadrante (J1 arriba-izq, J2 abajo-izq, J3 arriba-der, J4 abajo-der)",
		Vector2(0, 385), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("Equipo AZUL: J1 + J2     Equipo ROJO: J3 + J4", Vector2(0, 440), 24, Color(0.8, 0.85, 0.9), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("Pulsa ESPACIO o toca la pantalla para empezar", Vector2(0, 520), 30, Color(1.0, 0.85, 0.2), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)


func _draw_end() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, 0.7))
	var a := _team_score(0)
	var b := _team_score(1)
	var title := "EMPATE"
	var col := Color.WHITE
	if a > b:
		title = "GANA EL EQUIPO AZUL"
		col = colors[0]
	elif b > a:
		title = "GANA EL EQUIPO ROJO"
		col = colors[2]
	_text("FIN DE LA PARTIDA", Vector2(0, 230), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text(title, Vector2(0, 310), 64, col, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("AZUL %d  -  %d ROJO" % [a, b], Vector2(0, 370), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	for i in 4:
		_text("J%d: %d" % [i + 1, snakes[i]["score"]], Vector2(0, 420 + i * 28), 22, colors[i], HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("Pulsa ESPACIO o toca la pantalla para jugar otra vez", Vector2(0, 590), 26, Color(1.0, 0.85, 0.2), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
