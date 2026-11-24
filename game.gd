extends Node2D
## Partida. Offline o anfitrion: simula (con IA). Cliente online: solo dibuja el estado recibido.

signal match_finished

const COLS := 50
const ROWS := 26
const CELL := 24
const ORIGIN := Vector2(40, 70)
const SCREEN := Vector2(1280, 720)

const GAME_TIME := 120.0
const PHASE2_AT := 60.0
const PHASE3_AT := 90.0
const COUNTDOWN := 3.0
const BASE_STEP := 0.14
const SPEED_FACTOR := 0.25
const SPEED_EFFECT_TIME := 6.0
const RESPAWN_TIME := 5.0
const MAX_FOOD := 14
const MAX_WALLS := 40
const BIG_CHANCE := 5
const SPEED_CHANCE := 5

enum State { PLAYING, ENDED }
enum Item { FOOD, BIG, SLOW, FAST }

const START_POS := [Vector2i(4, 4), Vector2i(4, 21), Vector2i(45, 4), Vector2i(45, 21)]
const START_DIR := [Vector2i.RIGHT, Vector2i.RIGHT, Vector2i.LEFT, Vector2i.LEFT]
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const KEYMAP := {
	KEY_W: Vector2i.UP, KEY_UP: Vector2i.UP,
	KEY_S: Vector2i.DOWN, KEY_DOWN: Vector2i.DOWN,
	KEY_A: Vector2i.LEFT, KEY_LEFT: Vector2i.LEFT,
	KEY_D: Vector2i.RIGHT, KEY_RIGHT: Vector2i.RIGHT,
}
const DARK := Color(0.08, 0.08, 0.10)
const NAVY := Color(0.10, 0.16, 0.30)
const BG_COLOR := Color(0.62, 0.75, 0.90)      # fondo general (azul pastel algo mas intenso)
const ARENA_COLOR := Color(0.80, 0.90, 0.98)   # tablero (azul pastel)
const GRID_COLOR := Color(0.72, 0.83, 0.94)
const BORDER_COLOR := Color(0.35, 0.50, 0.70)

var authoritative := true
var local_slot := 0
var state: int = State.PLAYING
var snakes: Array = []
var walls := {}
var items := {}
var time_left := GAME_TIME
var countdown := COUNTDOWN
var spawn_item_t := 0.0
var spawn_wall_t := 0.0
var net_acc := 0.0
var finished_emitted := false
var touch_start := {}
var item_tex := {}
var tex_brick: Texture2D = null


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	return null


func _ready() -> void:
	item_tex[Item.FOOD] = _load_tex("res://items/apple.png")          # manzana roja: +1
	item_tex[Item.BIG] = _load_tex("res://items/watermelon.png")      # sandia: +2
	item_tex[Item.SLOW] = _load_tex("res://items/slow.png")           # - rojo: velocidad -1/4
	item_tex[Item.FAST] = _load_tex("res://items/fast.png")           # + verde: velocidad +1/4
	tex_brick = _load_tex("res://items/brick.png")                    # ladrillo: muro
	authoritative = (not Session.online) or Session.is_host
	local_slot = Session.my_slot
	if authoritative:
		Session.remote_input.connect(_on_remote_input)
		_start_game()
	else:
		Session.state_received.connect(_on_state)


# ================================================================ simulacion
func _start_game() -> void:
	walls.clear()
	items.clear()
	snakes.clear()
	time_left = GAME_TIME
	countdown = COUNTDOWN
	state = State.PLAYING
	for i in 4:
		var s := {
			"alive": true, "body": [], "dir": START_DIR[i], "next_dir": START_DIR[i],
			"score": 0, "acc": 0.0, "mult": 1.0, "mult_t": 0.0, "grow": 0, "respawn_t": 0.0,
		}
		_place(s, START_POS[i], START_DIR[i])
		snakes.append(s)
	for k in 5:
		_spawn_item(Item.FOOD)


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
	if authoritative:
		_simulate(delta)
		if Session.online:
			net_acc += delta
			if net_acc >= 0.05:
				net_acc = 0.0
				Session.broadcast_state(_pack_state())
	if state == State.ENDED and not finished_emitted:
		finished_emitted = true
		match_finished.emit()
	queue_redraw()


func _simulate(delta: float) -> void:
	if state != State.PLAYING:
		return
	if countdown > 0.0:
		countdown -= delta
		return
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		state = State.ENDED
		return
	_update_spawns(delta)
	for i in 4:
		_update_snake(i, delta)


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
	if int(Session.slots[i]["peer"]) == 0:
		_ai_choose(i)
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
	s["score"] = 0   # al morir pierde sus puntos (se restan del total del equipo)
	s["grow"] = 0
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
	snakes[i]["respawn_t"] = 0.3


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
			for k in range(0, 6):   # nunca justo delante de una cabeza
				if h + d * k == c:
					ok = false
		if ok:
			walls[c] = true
			return


# ---------------------------------------------------------------- IA
func _ai_choose(i: int) -> void:
	var s: Dictionary = snakes[i]
	var cur: Vector2i = s["dir"]
	var head: Vector2i = s["body"][0]
	var options: Array = []
	for d in [cur, Vector2i(cur.y, -cur.x), Vector2i(-cur.y, cur.x)]:
		var dd: Vector2i = d
		if not _blocked(head + dd):
			options.append(dd)
	if options.is_empty():
		return
	var best: Vector2i = options[0]
	var best_score := -1000000.0
	for d in options:
		var dd: Vector2i = d
		var c: Vector2i = head + dd
		var sc := float(mini(_flood(c, 40), 30)) * 2.0
		sc -= _dist_to_target(c)
		if dd == cur:
			sc += 0.5
		if items.get(c, -1) == Item.SLOW:
			sc -= 8.0
		for j in 4:
			if j != i and snakes[j]["alive"]:
				var oh: Vector2i = snakes[j]["body"][0]
				if absi(oh.x - c.x) + absi(oh.y - c.y) <= 1:
					sc -= 6.0
		if randf() < 0.05:
			sc += randf() * 6.0
		if sc > best_score:
			best_score = sc
			best = dd
	s["next_dir"] = best


func _flood(start: Vector2i, limit: int) -> int:
	var seen := {}
	seen[start] = true
	var q: Array = [start]
	var n := 0
	while not q.is_empty() and n < limit:
		var c: Vector2i = q.pop_front()
		n += 1
		for d in DIRS:
			var nx: Vector2i = c + d
			if seen.has(nx) or _blocked(nx):
				continue
			seen[nx] = true
			q.append(nx)
	return n


func _dist_to_target(c: Vector2i) -> float:
	var best := 999.0
	for p in items.keys():
		var t: int = items[p]
		if t == Item.SLOW:
			continue
		var pc: Vector2i = p
		var d := float(absi(pc.x - c.x) + absi(pc.y - c.y))
		if t == Item.BIG:
			d -= 4.0
		best = minf(best, d)
	return best if best < 999.0 else 0.0


# ================================================================ red
func _idx(c: Vector2i) -> int:
	return c.y * COLS + c.x


@warning_ignore("integer_division")
func _cell(v: int) -> Vector2i:
	return Vector2i(v % COLS, v / COLS)


func _pack_state() -> Dictionary:
	var w := PackedInt32Array()
	for c in walls.keys():
		w.append(_idx(c))
	var it := PackedInt32Array()
	for c in items.keys():
		it.append(_idx(c))
		it.append(int(items[c]))
	var ss: Array = []
	for s in snakes:
		var b := PackedInt32Array()
		for c in s["body"]:
			b.append(_idx(c))
		ss.append({"a": s["alive"], "b": b, "sc": s["score"], "m": s["mult"], "r": s["respawn_t"]})
	return {"t": time_left, "st": state, "cd": countdown, "w": w, "i": it, "s": ss}


func _on_state(st: Dictionary) -> void:
	time_left = st["t"]
	state = st["st"]
	countdown = st["cd"]
	walls.clear()
	for v in st["w"]:
		walls[_cell(v)] = true
	items.clear()
	var it: PackedInt32Array = st["i"]
	for k in range(0, it.size(), 2):
		items[_cell(it[k])] = it[k + 1]
	snakes.clear()
	for e in st["s"]:
		var body: Array = []
		for v in e["b"]:
			body.append(_cell(v))
		snakes.append({"alive": e["a"], "body": body, "score": e["sc"], "mult": e["m"], "respawn_t": e["r"]})


func _on_remote_input(slot: int, dir: Vector2i) -> void:
	_set_dir(slot, dir)


# ================================================================ entrada
func _set_dir(i: int, dir: Vector2i) -> void:
	if i < 0 or i >= snakes.size():
		return
	var s: Dictionary = snakes[i]
	if not s["alive"]:
		return
	var cur: Vector2i = s["dir"]
	if dir == -cur:
		return
	s["next_dir"] = dir


func _local_dir(dir: Vector2i) -> void:
	if state != State.PLAYING:
		return
	if authoritative:
		_set_dir(local_slot, dir)
	else:
		Session.send_input(dir)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo and KEYMAP.has(k.keycode):
			_local_dir(KEYMAP[k.keycode])
	elif event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			touch_start[t.index] = t.position
		else:
			touch_start.erase(t.index)
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if touch_start.has(d.index):
			var origin: Vector2 = touch_start[d.index]
			var delta: Vector2 = d.position - origin
			if delta.length() >= 28.0:
				var dir: Vector2i
				if absf(delta.x) > absf(delta.y):
					dir = Vector2i.RIGHT if delta.x > 0.0 else Vector2i.LEFT
				else:
					dir = Vector2i.DOWN if delta.y > 0.0 else Vector2i.UP
				_local_dir(dir)
				touch_start[d.index] = d.position


# ================================================================ dibujo
func _pcolor(i: int) -> Color:
	var c: int = Session.slots[i]["color"]
	return Session.palette[c] if c >= 0 else Color.GRAY


func _team_score(t: int) -> int:
	if snakes.size() < 4:
		return 0
	return int(snakes[t * 2]["score"]) + int(snakes[t * 2 + 1]["score"])


func _rect(c: Vector2i, inset: float) -> Rect2:
	return Rect2(ORIGIN + Vector2(c) * CELL + Vector2(inset, inset), Vector2(CELL - inset * 2.0, CELL - inset * 2.0))


func _text(txt: String, pos: Vector2, size: int, col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	draw_string(ThemeDB.fallback_font, pos, txt, align, width, size, col)


## Icono del jugador rodeado por el color de su serpiente.
func _draw_avatar(center: Vector2, slot: int, r: float, dim: bool = false) -> void:
	var col := _pcolor(slot)
	draw_circle(center, r + 5.0, NAVY)
	draw_circle(center, r + 3.5, col)
	var tex := Session.avatar_texture(int(Session.slots[slot]["avatar"]), int(r * 4.0))
	if tex != null:
		draw_texture_rect(tex, Rect2(center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false,
			Color(1, 1, 1, 0.45 if dim else 1.0))
	else:
		draw_circle(center, r, Color.WHITE)


func _draw_legend(y: float) -> void:
	var entries: Array = [
		[item_tex.get(Item.FOOD), "+1 punto"],
		[item_tex.get(Item.BIG), "+2 puntos"],
		[tex_brick, "Muro: te elimina"],
		[item_tex.get(Item.SLOW), "Velocidad -1/4"],
		[item_tex.get(Item.FAST), "Velocidad +1/4"],
	]
	var widths := [150.0, 160.0, 230.0, 215.0, 215.0]
	var total := 0.0
	for w in widths:
		total += w
	var x := 640.0 - total / 2.0
	for k in entries.size():
		var tex: Texture2D = entries[k][0]
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2(x, y - 30.0), Vector2(36, 36)), false)
		_text(str(entries[k][1]), Vector2(x + 44.0, y), 18, Color.WHITE)
		x += widths[k]


func _team_icon(pos: Vector2, team: int) -> void:
	draw_rect(Rect2(pos, Vector2(24, 24)), Color(0.97, 0.98, 1.0))
	draw_rect(Rect2(pos, Vector2(24, 24)), NAVY, false, 2.0)
	var inner := Rect2(pos + Vector2(7, 7), Vector2(10, 10))
	if team == 0:
		draw_rect(inner, DARK)
	else:
		draw_rect(inner, DARK, false, 2.0)


func _text_o(txt: String, pos: Vector2, size: int, col: Color, outline_col: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, txt, align, width, size, 3, outline_col)
	draw_string(f, pos, txt, align, width, size, col)


func _center(c: Vector2i) -> Vector2:
	return ORIGIN + Vector2(c) * CELL + Vector2(CELL, CELL) * 0.5


## Rectangulo que une dos centros contiguos (ancho 2*r), para que el cuerpo sea continuo.
func _link(a: Vector2, b: Vector2, r: float, col: Color) -> void:
	if absf(a.x - b.x) > absf(a.y - b.y):
		draw_rect(Rect2(Vector2(minf(a.x, b.x), a.y - r), Vector2(absf(a.x - b.x), r * 2.0)), col)
	else:
		draw_rect(Rect2(Vector2(a.x - r, minf(a.y, b.y)), Vector2(r * 2.0, absf(a.y - b.y))), col)


func _draw_snake(i: int) -> void:
	var body: Array = snakes[i]["body"]
	var n := body.size()
	if n == 0:
		return
	var base := _pcolor(i)
	var light := base.lightened(0.45)     # morro
	var dark := base.darkened(0.45)       # cola
	var outline := base.darkened(0.65)
	var r := CELL * 0.5 - 1.5
	var cols: Array = []
	for j in n:
		cols.append(light.lerp(dark, float(j) / float(maxi(n - 1, 1))))
	# contorno
	for j in range(n - 1, -1, -1):
		var rr := r + 1.0 if j == 0 else r
		var p := _center(body[j])
		draw_circle(p, rr + 2.0, outline)
		if j < n - 1:
			_link(p, _center(body[j + 1]), r + 2.0, outline)
	# relleno con degradado
	for j in range(n - 1, -1, -1):
		var rr := r + 1.0 if j == 0 else r
		var p := _center(body[j])
		if j < n - 1:
			_link(p, _center(body[j + 1]), r, cols[j].lerp(cols[j + 1], 0.5))
		draw_circle(p, rr, cols[j])
	# marca de equipo en la cabeza: cuadrado (equipo 1) o aro (equipo 2)
	var hc := _center(body[0])
	var mark := Rect2(hc - Vector2(5, 5), Vector2(10, 10))
	if (i >> 1) == 0:
		draw_rect(mark, DARK)
	else:
		draw_rect(mark, DARK, false, 2.0)
	_text_o(str(Session.slots[i]["name"]), hc + Vector2(-40, -16), 13, Color.WHITE, NAVY,
		HORIZONTAL_ALIGNMENT_CENTER, 80.0)
	if i == local_slot and (countdown > 0.0 or GAME_TIME - time_left < 4.0):
		draw_arc(hc, r + 6.0, 0.0, TAU, 32, NAVY, 3.0)


func _draw_item_fallback(c: Vector2i, t: int) -> void:
	var base := _rect(c, 0.0).position + Vector2(0, 18)
	if t == Item.FOOD:
		draw_rect(_rect(c, 7.0), Color(0.85, 0.15, 0.15))
	elif t == Item.BIG:
		draw_rect(_rect(c, 3.0), Color(0.25, 0.65, 0.30))
	elif t == Item.SLOW:
		draw_rect(_rect(c, 3.0), Color(0.85, 0.15, 0.20))
		_text("-", base, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, CELL)
	elif t == Item.FAST:
		draw_rect(_rect(c, 3.0), Color(0.20, 0.70, 0.35))
		_text("+", base, 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, CELL)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), BG_COLOR)
	var arena := Rect2(ORIGIN, Vector2(COLS * CELL, ROWS * CELL))
	draw_rect(arena, ARENA_COLOR)
	for x in range(1, COLS):
		var px := ORIGIN.x + x * CELL
		draw_line(Vector2(px, ORIGIN.y), Vector2(px, ORIGIN.y + ROWS * CELL), GRID_COLOR, 1.0)
	for y in range(1, ROWS):
		var py := ORIGIN.y + y * CELL
		draw_line(Vector2(ORIGIN.x, py), Vector2(ORIGIN.x + COLS * CELL, py), GRID_COLOR, 1.0)
	draw_rect(arena, BORDER_COLOR, false, 4.0)

	for c in walls.keys():
		var r := _rect(c, 0.0)
		if tex_brick != null:
			draw_texture_rect(tex_brick, r, false)
		else:
			draw_rect(r.grow(-1.0), Color(0.30, 0.16, 0.14))
			draw_line(r.position, r.end, Color(0.85, 0.50, 0.38), 2.0)
			draw_line(Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), Color(0.85, 0.50, 0.38), 2.0)

	for c in items.keys():
		var t: int = items[c]
		var tex: Texture2D = item_tex.get(t)
		if tex != null:
			draw_texture_rect(tex, _rect(c, 1.0), false)
		else:
			_draw_item_fallback(c, t)

	if Session.slots.size() == 4:
		for i in snakes.size():
			if snakes[i]["alive"]:
				_draw_snake(i)
		_draw_hud()

	if countdown > 0.0 and state == State.PLAYING:
		draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, 0.45))
		_text(str(int(ceil(countdown))), Vector2(0, 400), 160, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
		_text("¡Prepárate!", Vector2(0, 250), 44, Color(1.0, 0.85, 0.2), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
		_text("Tu serpiente está marcada con un círculo. Muévela con flechas/WASD o deslizando el dedo",
			Vector2(0, 470), 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
		_text("Si mueres pierdes los puntos que llevabas",
			Vector2(0, 505), 22, Color(1.0, 0.85, 0.2), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
		_draw_legend(580.0)
	elif state == State.ENDED:
		_draw_end()


func _draw_hud() -> void:
	_team_icon(Vector2(40, 12), 0)
	_text("EQUIPO 1: %d" % _team_score(0), Vector2(72, 36), 28, NAVY)
	_team_icon(Vector2(1216, 12), 1)
	_text("EQUIPO 2: %d" % _team_score(1), Vector2(0, 36), 28, NAVY, HORIZONTAL_ALIGNMENT_RIGHT, 1208.0)
	var secs := int(ceil(time_left))
	_text("%d:%02d" % [secs / 60, secs % 60], Vector2(0, 36), 32, NAVY, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	var elapsed := GAME_TIME - time_left
	var phase := "Fase 1: puntos +1"
	if elapsed >= PHASE3_AT:
		phase = "Fase 3: muros y velocidad"
	elif elapsed >= PHASE2_AT:
		phase = "Fase 2: sandías +2 (1/5)"
	_text(phase, Vector2(0, 62), 14, Color(0.25, 0.33, 0.50), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	var xs := [40.0, 290.0, 740.0, 990.0]
	for i in snakes.size():
		var s: Dictionary = snakes[i]
		var txt := "%s: %d" % [Session.slots[i]["name"], s["score"]]
		if i == local_slot:
			txt += " (tú)"
		if not s["alive"]:
			txt += "  (%ds)" % int(ceil(s["respawn_t"]))
		elif s["mult"] > 1.0:
			txt += " [+]"
		elif s["mult"] < 1.0:
			txt += " [-]"
		_draw_avatar(Vector2(xs[i] + 17.0, 55.0), i, 12.0, not s["alive"])
		_text_o(txt, Vector2(xs[i] + 42.0, 61), 16, _pcolor(i), NAVY)


func _draw_end() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, 0.75))
	var a := _team_score(0)
	var b := _team_score(1)
	var my_team := local_slot >> 1
	var title := "EMPATE"
	var col := Color.WHITE
	if a != b:
		var win := 0 if a > b else 1
		if win == my_team:
			title = "¡VICTORIA!"
			col = Color(0.4, 0.95, 0.5)
		else:
			title = "DERROTA"
			col = Color(1.0, 0.45, 0.45)
	_text("FIN DE LA PARTIDA", Vector2(0, 160), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text(title, Vector2(0, 250), 72, col, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	_text("EQUIPO 1   %d  -  %d   EQUIPO 2" % [a, b], Vector2(0, 320), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
	var font := ThemeDB.fallback_font
	for i in snakes.size():
		var line := "Equipo %d  -  %s: %d" % [(i >> 1) + 1, Session.slots[i]["name"], snakes[i]["score"]]
		var y := 395.0 + i * 46.0
		var w := font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
		_draw_avatar(Vector2(640.0 - w / 2.0 - 34.0, y - 8.0), i, 16.0)
		_text(line, Vector2(0, y), 24, _pcolor(i), HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x)
