class_name MainGame
extends Control

## ゲーム状態
enum State {
	STARTUP,
	SPAWN,
	FALLING,
	LOCKING,
	DROP_FREE,
	CLEAR_ANIM,
	MATCH_CHECK,
	GAME_OVER
}

var current_state: State = State.STARTUP

## コアロジック・モデル
var grid_model: GridModel
var input_handler: InputHandler

## 操作中のツモ (Active Pair)
var pivot_pos: Vector2i = Vector2i(GameConstants.SPAWN_COL, GameConstants.SPAWN_ROW_PIVOT)
var child_dir: int = GameConstants.Direction.UP
var pivot_type: int = GameConstants.PuyoType.EMPTY
var child_type: int = GameConstants.PuyoType.EMPTY

## NEXTキュー (2組)
var next_queue: Array = []

## タイマー & ゲーム進行
var fall_timer: float = 0.0
var lock_timer: float = 0.0
var state_timer: float = 0.0
var game_time: float = 0.0

var is_grounded: bool = false

## 連鎖・スコア管理
var current_chain: int = 0
var max_chain: int = 0
var score: int = 0
var hi_score: int = 0
var total_cleared_puyos: int = 0
var last_cleared_info: Dictionary = {}
var active_drops: Array = []

## パーティクル & エフェクト
var active_particles: Array = []  # 各要素: {pos: Vector2, vel: Vector2, color: Color, size: float, life: float, max_life: float}
var active_rings: Array = []      # 各要素: {pos: Vector2, radius: float, max_radius: float, color: Color, life: float, max_life: float}
var has_spawned_pop_particles: bool = false

## UIノード参照
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var game_over_panel: Panel = $GameOverPanel
@onready var retry_button: Button = $GameOverPanel/VBoxContainer/RetryButton
@onready var title_button: Button = $GameOverPanel/VBoxContainer/TitleButton
@onready var final_score_label: Label = $GameOverPanel/ScoreValue
@onready var final_hiscore_label: Label = $GameOverPanel/HiScoreValue
@onready var final_chain_label: Label = $GameOverPanel/ChainValue

# アニメーション用
var clear_anim_progress: float = 0.0
var drop_anim_progress: float = 0.0
var chain_banner_text: String = ""
var chain_banner_timer: float = 0.0

func _ready() -> void:
	randomize()

	grid_model = GridModel.new()
	input_handler = InputHandler.new()
	add_child(input_handler)

	input_handler.move_left_pressed.connect(_on_move_left)
	input_handler.move_right_pressed.connect(_on_move_right)
	input_handler.rotate_left_pressed.connect(_on_rotate_left)
	input_handler.rotate_right_pressed.connect(_on_rotate_right)
	input_handler.hard_drop_pressed.connect(_on_hard_drop)
	input_handler.pause_pressed.connect(_on_pause_requested)

	pause_menu.resume_requested.connect(_on_pause_resume)
	pause_menu.retry_requested.connect(start_new_game)
	pause_menu.title_requested.connect(_on_back_to_title)

	retry_button.pressed.connect(start_new_game)
	title_button.pressed.connect(_on_back_to_title)

	retry_button.focus_neighbor_top = retry_button.get_path_to(title_button)
	retry_button.focus_neighbor_bottom = retry_button.get_path_to(title_button)
	title_button.focus_neighbor_top = title_button.get_path_to(retry_button)
	title_button.focus_neighbor_bottom = title_button.get_path_to(retry_button)

	game_over_panel.visible = false

	_load_hi_score()
	start_new_game()

func _process(delta: float) -> void:
	if current_state != State.GAME_OVER and not get_tree().paused:
		game_time += delta

	if chain_banner_timer > 0.0:
		chain_banner_timer -= delta

	_update_effects(delta)

	match current_state:
		State.FALLING, State.LOCKING:
			_process_falling(delta)
		State.DROP_FREE:
			_process_drop_free(delta)
		State.CLEAR_ANIM:
			_process_clear_anim(delta)

	queue_redraw()

func _update_effects(delta: float) -> void:
	# パーティクル更新
	var i = active_particles.size() - 1
	while i >= 0:
		var p = active_particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"].y += 380.0 * delta  # 重力
		p["vel"].x *= 0.96           # 空気抵抗
		p["life"] -= delta
		if p["life"] <= 0.0:
			active_particles.remove_at(i)
		i -= 1

	# ショックウェーブリング更新
	var j = active_rings.size() - 1
	while j >= 0:
		var r = active_rings[j]
		r["life"] -= delta
		var t = 1.0 - (r["life"] / r["max_life"])
		r["radius"] = lerp(4.0, r["max_radius"], t)
		if r["life"] <= 0.0:
			active_rings.remove_at(j)
		j -= 1

## -------------------------------------------------------------
## ゲーム開始 & ツモ管理
## -------------------------------------------------------------
func start_new_game() -> void:
	grid_model.clear()
	score = 0
	current_chain = 0
	max_chain = 0
	total_cleared_puyos = 0
	game_time = 0.0
	chain_banner_text = ""
	chain_banner_timer = 0.0
	active_particles.clear()
	active_rings.clear()

	game_over_panel.visible = false
	input_handler.is_enabled = true
	input_handler.reset_state()

	next_queue.clear()
	next_queue.append(_generate_random_pair())
	next_queue.append(_generate_random_pair())

	_transition_to_spawn()

func _generate_random_pair() -> Dictionary:
	var colors = [
		GameConstants.PuyoType.RED,
		GameConstants.PuyoType.GREEN,
		GameConstants.PuyoType.BLUE,
		GameConstants.PuyoType.YELLOW
	]
	return {
		"pivot": colors[randi() % colors.size()],
		"child": colors[randi() % colors.size()]
	}

func _transition_to_spawn() -> void:
	current_state = State.SPAWN

	if grid_model.is_choked():
		_game_over()
		return

	var current_pair = next_queue.pop_front()
	next_queue.append(_generate_random_pair())

	pivot_type = current_pair["pivot"]
	child_type = current_pair["child"]
	pivot_pos = Vector2i(GameConstants.SPAWN_COL, GameConstants.SPAWN_ROW_PIVOT)
	child_dir = GameConstants.Direction.UP

	fall_timer = 0.0
	lock_timer = 0.0
	is_grounded = false
	current_chain = 0

	_update_grounded_state()
	current_state = State.FALLING

## -------------------------------------------------------------
## 操作フェーズ (FALLING / LOCKING)
## -------------------------------------------------------------
func _process_falling(delta: float) -> void:
	var is_soft_drop = input_handler.is_soft_dropping()
	var fall_speed = GameConstants.SOFT_DROP_INTERVAL if is_soft_drop else GameConstants.BASE_FALL_INTERVAL

	fall_timer += delta
	if fall_timer >= fall_speed:
		fall_timer = 0.0
		if _can_move(pivot_pos + Vector2i(0, 1), child_dir):
			pivot_pos.y += 1
			if is_soft_drop:
				score += 1
			_update_grounded_state()
		else:
			is_grounded = true

	_update_grounded_state()
	if is_grounded:
		current_state = State.LOCKING
		lock_timer += delta
		if lock_timer >= GameConstants.LOCK_DELAY or is_soft_drop:
			_lock_active_pair()
	else:
		current_state = State.FALLING
		lock_timer = 0.0

func _update_grounded_state() -> void:
	var can_fall = _can_move(pivot_pos + Vector2i(0, 1), child_dir)
	is_grounded = not can_fall

func _can_move(test_pivot: Vector2i, test_dir: int) -> bool:
	var offset = GameConstants.DIR_OFFSETS[test_dir]
	var test_child = test_pivot + offset

	if not grid_model.is_valid_coord(test_pivot.x, test_pivot.y):
		return false
	if not grid_model.is_empty(test_pivot.x, test_pivot.y):
		return false

	if not grid_model.is_valid_coord(test_child.x, test_child.y):
		return false
	if not grid_model.is_empty(test_child.x, test_child.y):
		return false

	return true

func _on_move_left() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	if _can_move(pivot_pos + Vector2i(-1, 0), child_dir):
		pivot_pos.x -= 1
		_reset_lock_timer_on_move()
		_update_grounded_state()

func _on_move_right() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	if _can_move(pivot_pos + Vector2i(1, 0), child_dir):
		pivot_pos.x += 1
		_reset_lock_timer_on_move()
		_update_grounded_state()

func _on_rotate_right() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	var new_dir = (child_dir + 1) % 4
	_try_rotate(new_dir)

func _on_rotate_left() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	var new_dir = (child_dir + 3) % 4
	_try_rotate(new_dir)

func _try_rotate(target_dir: int) -> void:
	if _can_move(pivot_pos, target_dir):
		child_dir = target_dir
		_reset_lock_timer_on_move()
		_update_grounded_state()
		return

	if _can_move(pivot_pos + Vector2i(-1, 0), target_dir):
		pivot_pos.x -= 1
		child_dir = target_dir
		_reset_lock_timer_on_move()
		_update_grounded_state()
		return

	if _can_move(pivot_pos + Vector2i(1, 0), target_dir):
		pivot_pos.x += 1
		child_dir = target_dir
		_reset_lock_timer_on_move()
		_update_grounded_state()
		return

	if _can_move(pivot_pos + Vector2i(0, -1), target_dir):
		pivot_pos.y -= 1
		child_dir = target_dir
		_reset_lock_timer_on_move()
		_update_grounded_state()
		return

func _on_hard_drop() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return

	while _can_move(pivot_pos + Vector2i(0, 1), child_dir):
		pivot_pos.y += 1
		score += 2

	_lock_active_pair()

func _reset_lock_timer_on_move() -> void:
	if is_grounded:
		lock_timer = min(lock_timer, GameConstants.LOCK_DELAY * 0.5)

## -------------------------------------------------------------
## 接地・自由落下・連鎖処理
## -------------------------------------------------------------
func _lock_active_pair() -> void:
	var child_pos = pivot_pos + GameConstants.DIR_OFFSETS[child_dir]

	grid_model.set_cell(pivot_pos.x, pivot_pos.y, pivot_type)
	grid_model.set_cell(child_pos.x, child_pos.y, child_type)

	pivot_type = GameConstants.PuyoType.EMPTY
	child_type = GameConstants.PuyoType.EMPTY

	_start_drop_free()

func _start_drop_free() -> void:
	current_state = State.DROP_FREE
	active_drops = grid_model.apply_gravity()

	if active_drops.size() > 0:
		state_timer = 0.0
		drop_anim_progress = 0.0
	else:
		_start_match_check()

func _process_drop_free(delta: float) -> void:
	state_timer += delta
	drop_anim_progress = min(1.0, state_timer / GameConstants.DROP_ANIM_DURATION)

	if state_timer >= GameConstants.DROP_ANIM_DURATION:
		active_drops.clear()
		_start_match_check()

func _start_match_check() -> void:
	current_state = State.MATCH_CHECK
	var match_result = grid_model.check_and_clear_matches()

	if match_result["has_cleared"]:
		current_chain += 1
		if current_chain > max_chain:
			max_chain = current_chain

		total_cleared_puyos += match_result["total_cleared"]
		_calculate_score(match_result)

		chain_banner_text = "%d CHAIN!" % current_chain
		chain_banner_timer = 1.2

		last_cleared_info = match_result
		current_state = State.CLEAR_ANIM
		state_timer = 0.0
		clear_anim_progress = 0.0
		has_spawned_pop_particles = false
	else:
		if current_chain > 0 and grid_model.is_field_empty():
			score += 2100
			chain_banner_text = "ALL CLEAR! (+2100)"
			chain_banner_timer = 1.6

		_transition_to_spawn()

func _process_clear_anim(delta: float) -> void:
	state_timer += delta
	clear_anim_progress = min(1.0, state_timer / 0.42)

	# アニメーション前半(0.20秒時点)で一斉にポンッと弾けパーティクルを発生
	if clear_anim_progress >= 0.45 and not has_spawned_pop_particles:
		has_spawned_pop_particles = true
		_spawn_clear_effects()

	if state_timer >= 0.42:
		last_cleared_info.clear()
		_start_drop_free()

func _spawn_clear_effects() -> void:
	if not last_cleared_info.has("cleared_cells"):
		return

	for cell in last_cleared_info["cleared_cells"]:
		var center = _grid_to_screen(cell.x, cell.y)
		var cell_type = last_cleared_info.get("cell_types", {}).get(cell, GameConstants.PuyoType.RED)
		var color = GameConstants.PUYO_COLORS.get(cell_type, Color.WHITE)
		var highlight = GameConstants.PUYO_HIGHLIGHT_COLORS.get(cell_type, Color.WHITE)

		# 1. 衝撃波リング
		active_rings.append({
			"pos": center,
			"radius": 6.0,
			"max_radius": 34.0,
			"color": highlight,
			"life": 0.28,
			"max_life": 0.28
		})

		# 2. ジューシーな飛沫・星型パーティクル
		var count = 8 + (current_chain * 2)
		for i in range(count):
			var angle = (TAU / count) * i + randf_range(-0.3, 0.3)
			var speed = randf_range(90.0, 220.0)
			var vel = Vector2(cos(angle), sin(angle)) * speed
			var p_col = color if (i % 2 == 0) else highlight
			active_particles.append({
				"pos": center + Vector2(randf_range(-4, 4), randf_range(-4, 4)),
				"vel": vel,
				"color": p_col,
				"size": randf_range(3.5, 6.5),
				"life": randf_range(0.25, 0.45),
				"max_life": 0.45
			})

func _calculate_score(info: Dictionary) -> void:
	var cleared_count = info["total_cleared"]
	var chain_idx = clamp(current_chain, 1, GameConstants.CHAIN_POWERS.size() - 1)
	var chain_bonus = GameConstants.CHAIN_POWERS[chain_idx]

	var connect_idx = clamp(info["max_connect"], 0, GameConstants.CONNECT_BONUS.size() - 1)
	var connect_bonus = GameConstants.CONNECT_BONUS[connect_idx]

	var color_idx = clamp(info["color_count"], 0, GameConstants.COLOR_BONUS.size() - 1)
	var color_bonus = GameConstants.COLOR_BONUS[color_idx]

	var total_multiplier = chain_bonus + connect_bonus + color_bonus
	if total_multiplier == 0:
		total_multiplier = 1

	var gained_score = (10 * cleared_count) * total_multiplier
	score += gained_score

	if score > hi_score:
		hi_score = score
		_save_hi_score()

## -------------------------------------------------------------
## ポーズ & ゲームオーバー
## -------------------------------------------------------------
func _on_pause_requested() -> void:
	if current_state != State.GAME_OVER:
		pause_menu.open_menu()

func _on_pause_resume() -> void:
	pass

func _on_back_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

func _game_over() -> void:
	current_state = State.GAME_OVER
	input_handler.is_enabled = false

	if score > hi_score:
		hi_score = score
		_save_hi_score()

	final_score_label.text = "%d" % score
	final_hiscore_label.text = "%d" % hi_score
	final_chain_label.text = "%d" % max_chain

	game_over_panel.visible = true
	retry_button.call_deferred("grab_focus")

## -------------------------------------------------------------
## セーブ & ロード (ハイスコア)
## -------------------------------------------------------------
func _load_hi_score() -> void:
	if FileAccess.file_exists(GameConstants.SAVE_PATH):
		var file = FileAccess.open(GameConstants.SAVE_PATH, FileAccess.READ)
		if file:
			var json_str = file.get_as_text()
			var data = JSON.parse_string(json_str)
			if data is Dictionary and data.has("hi_score"):
				hi_score = int(data["hi_score"])

func _save_hi_score() -> void:
	var file = FileAccess.open(GameConstants.SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = { "hi_score": hi_score }
		file.store_string(JSON.stringify(data))

## -------------------------------------------------------------
## 描画
## -------------------------------------------------------------
func _draw() -> void:
	_draw_background_and_panels()
	_draw_grid_field()
	_draw_ghost_puyo()
	_draw_placed_puyos()
	_draw_clearing_puyos()
	_draw_falling_puyo()
	_draw_particles_and_rings()
	_draw_next_panel()
	_draw_side_ui()
	_draw_effects()

func _draw_background_and_panels() -> void:
	draw_rect(Rect2(0, 0, GameConstants.SCREEN_WIDTH, GameConstants.SCREEN_HEIGHT), GameConstants.COLOR_BG)

	var left_panel = Rect2(16, 48, 184, 624)
	draw_rect(left_panel, GameConstants.COLOR_PANEL_BG)
	draw_rect(left_panel, GameConstants.COLOR_PANEL_BORDER, false, 2.0)

	var right_panel = Rect2(520, 48, 184, 624)
	draw_rect(right_panel, GameConstants.COLOR_PANEL_BG)
	draw_rect(right_panel, GameConstants.COLOR_PANEL_BORDER, false, 2.0)

	draw_rect(Rect2(0, 0, 720, 44), Color(0.06, 0.07, 0.10))
	draw_line(Vector2(0, 44), Vector2(720, 44), GameConstants.COLOR_PANEL_BORDER, 2.0)

func _draw_grid_field() -> void:
	var visible_field_rect = Rect2(
		GameConstants.FIELD_X,
		GameConstants.FIELD_Y,
		GameConstants.FIELD_WIDTH,
		GameConstants.VISIBLE_ROWS * GameConstants.CELL_SIZE
	)
	draw_rect(visible_field_rect, GameConstants.COLOR_FIELD_BG)
	draw_rect(visible_field_rect, GameConstants.COLOR_FIELD_BORDER, false, 3.0)

	for c in range(1, GameConstants.COLS):
		var x = GameConstants.FIELD_X + c * GameConstants.CELL_SIZE
		draw_line(Vector2(x, GameConstants.FIELD_Y), Vector2(x, GameConstants.FIELD_Y + GameConstants.VISIBLE_ROWS * GameConstants.CELL_SIZE), GameConstants.COLOR_GRID_LINE, 1.0)

	for r in range(1, GameConstants.VISIBLE_ROWS):
		var y = GameConstants.FIELD_Y + r * GameConstants.CELL_SIZE
		draw_line(Vector2(GameConstants.FIELD_X, y), Vector2(GameConstants.FIELD_X + GameConstants.FIELD_WIDTH, y), GameConstants.COLOR_GRID_LINE, 1.0)

	var choke_x = GameConstants.FIELD_X + GameConstants.SPAWN_COL * GameConstants.CELL_SIZE
	draw_line(Vector2(choke_x, GameConstants.FIELD_Y), Vector2(choke_x + GameConstants.CELL_SIZE, GameConstants.FIELD_Y), Color(0.96, 0.26, 0.35, 0.8), 3.0)

func _draw_placed_puyos() -> void:
	# 自由落下中の移動ぷよマッピング
	var falling_map: Dictionary = {}
	if current_state == State.DROP_FREE and active_drops.size() > 0:
		var ease_t = drop_anim_progress * drop_anim_progress # 重力加速カーブ
		for d in active_drops:
			falling_map[Vector2i(d["col"], d["to_row"])] = lerp(float(d["from_row"]), float(d["to_row"]), ease_t)

	for c in range(GameConstants.COLS):
		for r in range(1, GameConstants.ROWS):
			var type = grid_model.get_cell(c, r)
			if type != GameConstants.PuyoType.EMPTY:
				var cell_key = Vector2i(c, r)
				if falling_map.has(cell_key):
					var interp_row = falling_map[cell_key]
					var x = GameConstants.FIELD_X + (c + 0.5) * GameConstants.CELL_SIZE
					var y = GameConstants.FIELD_Y + (interp_row - 1 + 0.5) * GameConstants.CELL_SIZE
					# 落下中は着地するまでコネクタを出さない
					_draw_single_puyo(Vector2(x, y), type, -1, -1, false, Vector2(0.94, 1.06))
				else:
					var pos = _grid_to_screen(c, r)
					_draw_single_puyo(pos, type, c, r, false, Vector2.ONE, falling_map)

func _draw_clearing_puyos() -> void:
	if current_state != State.CLEAR_ANIM or not last_cleared_info.has("cleared_cells"):
		return

	# 消去中ぷよのアニメーション (前半: 膨らみ&震え / 後半: 弾けて消滅)
	if clear_anim_progress < 0.45:
		var p_t = clear_anim_progress / 0.45
		# ぷよが1.0から1.28倍へポヨンと膨張
		var pop_scale = 1.0 + sin(p_t * PI * 0.5) * 0.28
		# ブルブルした振動
		var shake = Vector2(sin(game_time * 60.0) * 1.5, cos(game_time * 60.0) * 1.5)

		for cell in last_cleared_info["cleared_cells"]:
			var cell_type = last_cleared_info.get("cell_types", {}).get(cell, GameConstants.PuyoType.RED)
			var pos = _grid_to_screen(cell.x, cell.y) + shake
			_draw_single_puyo(pos, cell_type, cell.x, cell.y, true, Vector2(pop_scale, pop_scale))

## -------------------------------------------------------------
## 単体ぷよのプロシージャル・ジェリー描画
## -------------------------------------------------------------
func _draw_single_puyo(center_pos: Vector2, type: int, col: int = -1, row: int = -1, is_clearing: bool = false, custom_scale: Vector2 = Vector2.ONE, falling_map: Dictionary = {}) -> void:
	if type == GameConstants.PuyoType.EMPTY:
		return

	# お邪魔ぷよは四角い石ブロックとして描画
	if type == GameConstants.PuyoType.GARBAGE:
		_draw_stone_block(center_pos, GameConstants.CELL_SIZE, is_clearing, custom_scale, col, row)
		return

	var base_col: Color = GameConstants.PUYO_COLORS.get(type, Color.WHITE)
	var shadow_col: Color = GameConstants.PUYO_SHADOW_COLORS.get(type, Color(0.2, 0.2, 0.2))
	var highlight_col: Color = GameConstants.PUYO_HIGHLIGHT_COLORS.get(type, Color.WHITE)

	var base_radius = (GameConstants.CELL_SIZE / 2.0) - 2.0

	var breath = 0.0
	if not is_clearing:
		var phase = (col * 1.3 + row * 0.9) if (col >= 0 and row >= 0) else 0.0
		breath = sin(game_time * 4.5 + phase) * 0.035

	var scale_x = (1.0 + breath) * custom_scale.x
	var scale_y = (1.0 - breath) * custom_scale.y

	if is_clearing:
		# 消去前点滅
		if int(clear_anim_progress * 24.0) % 2 == 0:
			base_col = highlight_col
			shadow_col = base_col

	var rx = base_radius * scale_x
	var ry = base_radius * scale_y

	# 有効な同色隣接セルの検索 (消去中や落下中を除く)
	var valid_neighbors: Array[Dictionary] = []
	if col != -1 and row != -1 and not is_clearing:
		var check_dirs = [
			{"dir": Vector2i(1, 0), "offset": Vector2(GameConstants.CELL_SIZE / 2.0, 0)},
			{"dir": Vector2i(-1, 0), "offset": Vector2(-GameConstants.CELL_SIZE / 2.0, 0)},
			{"dir": Vector2i(0, 1), "offset": Vector2(0, GameConstants.CELL_SIZE / 2.0)},
			{"dir": Vector2i(0, -1), "offset": Vector2(0, -GameConstants.CELL_SIZE / 2.0)}
		]
		for n in check_dirs:
			var nc = col + n["dir"].x
			var nr = row + n["dir"].y
			if not falling_map.has(Vector2i(nc, nr)) and grid_model.is_valid_coord(nc, nr) and grid_model.get_cell(nc, nr) == type:
				valid_neighbors.append(n)

	# 1. ドロップシャドウ (本体 + 接続部)
	var shadow_offset = Vector2(0, 3.5)
	draw_circle(center_pos + shadow_offset, rx * 0.92, Color(0, 0, 0, 0.28))
	for n in valid_neighbors:
		var bridge_half = rx * 0.82
		if n["dir"].x != 0:
			var s_rect = Rect2(center_pos.x + min(0, n["offset"].x), center_pos.y + shadow_offset.y - bridge_half * 0.9, abs(n["offset"].x), bridge_half * 1.8)
			draw_rect(s_rect, Color(0, 0, 0, 0.28))
		elif n["dir"].y != 0:
			var s_rect = Rect2(center_pos.x - bridge_half * 0.9, center_pos.y + shadow_offset.y + min(0, n["offset"].y), bridge_half * 1.8, abs(n["offset"].y))
			draw_rect(s_rect, Color(0, 0, 0, 0.28))

	# 2. 外枠 / 立体アンダーシャドウ (本体 + 接続部)
	draw_circle(center_pos, rx, shadow_col)
	for n in valid_neighbors:
		var bridge_half = rx * 0.82
		if n["dir"].x != 0:
			var b_rect = Rect2(center_pos.x + min(0, n["offset"].x), center_pos.y - bridge_half, abs(n["offset"].x), bridge_half * 2.0)
			draw_rect(b_rect, shadow_col)
		elif n["dir"].y != 0:
			var b_rect = Rect2(center_pos.x - bridge_half, center_pos.y + min(0, n["offset"].y), bridge_half * 2.0, abs(n["offset"].y))
			draw_rect(b_rect, shadow_col)

	# 3. メインボディ (本体 + 接続部が完全に溶け合って一体化)
	var body_pos = center_pos + Vector2(0, -1.5)
	draw_circle(body_pos, rx - 1.2, base_col)
	for n in valid_neighbors:
		var inner_half = rx * 0.82 - 1.4
		if n["dir"].x != 0:
			var in_rect = Rect2(center_pos.x + min(0, n["offset"].x), center_pos.y - 1.5 - inner_half, abs(n["offset"].x), inner_half * 2.0)
			draw_rect(in_rect, base_col)
		elif n["dir"].y != 0:
			var in_rect = Rect2(center_pos.x - inner_half, center_pos.y - 1.5 + min(0, n["offset"].y), inner_half * 2.0, abs(n["offset"].y))
			draw_rect(in_rect, base_col)

	# 4. 上部内側グロー
	var top_glow_pos = center_pos + Vector2(0, -ry * 0.35)
	var glow_col = highlight_col
	glow_col.a = 0.45
	draw_circle(top_glow_pos, rx * 0.65, glow_col)

	# 5. 下部リムライト
	var rim_pos = center_pos + Vector2(0, ry * 0.5)
	var rim_col = highlight_col
	rim_col.a = 0.35
	draw_circle(rim_pos, rx * 0.45, rim_col)

	# 6. メイン・スペキュラハイライト
	var main_spec_pos = center_pos + Vector2(-rx * 0.38, -ry * 0.38)
	draw_circle(main_spec_pos, rx * 0.28, Color(1, 1, 1, 0.85))
	draw_circle(main_spec_pos + Vector2(-1, -1), rx * 0.14, Color(1, 1, 1, 0.95))

	# 7. サブ・ハイライト
	var sub_spec_pos = center_pos + Vector2(rx * 0.42, ry * 0.32)
	draw_circle(sub_spec_pos, rx * 0.12, Color(1, 1, 1, 0.55))

	# 8. 表情
	if type != GameConstants.PuyoType.GARBAGE:
		_draw_puyo_face(center_pos, rx, ry, col, row, is_clearing)

func _draw_puyo_face(center_pos: Vector2, rx: float, ry: float, col: int, row: int, is_clearing: bool) -> void:
	var eye_offset_x = rx * 0.34
	var eye_offset_y = -ry * 0.08
	var eye_w = rx * 0.24

	var left_eye_pos = center_pos + Vector2(-eye_offset_x, eye_offset_y)
	var right_eye_pos = center_pos + Vector2(eye_offset_x, eye_offset_y)

	if is_clearing:
		# 消去時の「＞＜」痛がり・驚き目
		var sz = eye_w * 0.95
		# 左目「＞」
		draw_line(left_eye_pos + Vector2(-sz, -sz), left_eye_pos + Vector2(sz * 0.4, 0), Color(0.12, 0.12, 0.18), 2.5)
		draw_line(left_eye_pos + Vector2(sz * 0.4, 0), left_eye_pos + Vector2(-sz, sz), Color(0.12, 0.12, 0.18), 2.5)
		# 右目「＜」
		draw_line(right_eye_pos + Vector2(sz, -sz), right_eye_pos + Vector2(-sz * 0.4, 0), Color(0.12, 0.12, 0.18), 2.5)
		draw_line(right_eye_pos + Vector2(-sz * 0.4, 0), right_eye_pos + Vector2(sz, sz), Color(0.12, 0.12, 0.18), 2.5)
		return

	var blink_phase = (col * 2.7 + row * 1.9) if (col >= 0 and row >= 0) else 0.0
	var is_blinking = sin(game_time * 2.5 + blink_phase) > 0.94

	if is_blinking:
		draw_arc(left_eye_pos + Vector2(0, 1), eye_w * 0.9, PI * 0.1, PI * 0.9, 8, Color(0.12, 0.12, 0.18), 2.2)
		draw_arc(right_eye_pos + Vector2(0, 1), eye_w * 0.9, PI * 0.1, PI * 0.9, 8, Color(0.12, 0.12, 0.18), 2.2)
	else:
		draw_circle(left_eye_pos + Vector2(0, 0.5), eye_w + 1.0, Color(0.12, 0.14, 0.20))
		draw_circle(right_eye_pos + Vector2(0, 0.5), eye_w + 1.0, Color(0.12, 0.14, 0.20))
		draw_circle(left_eye_pos, eye_w, Color.WHITE)
		draw_circle(right_eye_pos, eye_w, Color.WHITE)

		var pupil_r = eye_w * 0.55
		var look_offset = Vector2(0.5, 0.5)
		var left_pupil = left_eye_pos + look_offset
		var right_pupil = right_eye_pos + look_offset

		draw_circle(left_pupil, pupil_r, Color(0.10, 0.12, 0.18))
		draw_circle(right_pupil, pupil_r, Color(0.10, 0.12, 0.18))

		draw_circle(left_pupil + Vector2(-pupil_r * 0.35, -pupil_r * 0.35), pupil_r * 0.4, Color.WHITE)
		draw_circle(right_pupil + Vector2(-pupil_r * 0.35, -pupil_r * 0.35), pupil_r * 0.4, Color.WHITE)
		draw_circle(left_pupil + Vector2(pupil_r * 0.3, pupil_r * 0.3), pupil_r * 0.2, Color.WHITE)
		draw_circle(right_pupil + Vector2(pupil_r * 0.3, pupil_r * 0.3), pupil_r * 0.2, Color.WHITE)

func _draw_particles_and_rings() -> void:
	# ショックウェーブリング描画
	for r in active_rings:
		var alpha = r["life"] / r["max_life"]
		var col = Color(r["color"].r, r["color"].g, r["color"].b, alpha * 0.85)
		draw_arc(r["pos"], r["radius"], 0, TAU, 24, col, 2.5)

	# 飛び散る飛沫・パーティクル描画
	for p in active_particles:
		var alpha = p["life"] / p["max_life"]
		var col = Color(p["color"].r, p["color"].g, p["color"].b, alpha)
		draw_circle(p["pos"], p["size"] * alpha, col)
		draw_circle(p["pos"] + Vector2(-1, -1), p["size"] * alpha * 0.4, Color(1, 1, 1, alpha * 0.9))

func _draw_ghost_puyo() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return

	var ghost_pivot = pivot_pos
	while _can_move(ghost_pivot + Vector2i(0, 1), child_dir):
		ghost_pivot.y += 1

	if ghost_pivot == pivot_pos:
		return

	var ghost_child = ghost_pivot + GameConstants.DIR_OFFSETS[child_dir]

	var p_pos = _grid_to_screen(ghost_pivot.x, ghost_pivot.y)
	var c_pos = _grid_to_screen(ghost_child.x, ghost_child.y)

	var p_color = GameConstants.PUYO_COLORS.get(pivot_type, Color.WHITE)
	var c_color = GameConstants.PUYO_COLORS.get(child_type, Color.WHITE)
	p_color.a = 0.35
	c_color.a = 0.35

	if ghost_pivot.y >= 1:
		draw_circle(p_pos, (GameConstants.CELL_SIZE / 2.0) - 3.0, Color(p_color.r, p_color.g, p_color.b, 0.15))
		draw_arc(p_pos, (GameConstants.CELL_SIZE / 2.0) - 3.0, 0, TAU, 24, p_color, 2.0)
	if ghost_child.y >= 1:
		draw_circle(c_pos, (GameConstants.CELL_SIZE / 2.0) - 3.0, Color(c_color.r, c_color.g, c_color.b, 0.15))
		draw_arc(c_pos, (GameConstants.CELL_SIZE / 2.0) - 3.0, 0, TAU, 24, c_color, 2.0)

func _draw_falling_puyo() -> void:
	if pivot_type == GameConstants.PuyoType.EMPTY:
		return

	var child_pos = pivot_pos + GameConstants.DIR_OFFSETS[child_dir]
	var fall_scale = Vector2(0.96, 1.04) if not is_grounded else Vector2(1.06, 0.94)

	if pivot_pos.y >= 1:
		var p_screen = _grid_to_screen(pivot_pos.x, pivot_pos.y)
		_draw_single_puyo(p_screen, pivot_type, pivot_pos.x, pivot_pos.y, false, fall_scale)

	if child_pos.y >= 1:
		var c_screen = _grid_to_screen(child_pos.x, child_pos.y)
		_draw_single_puyo(c_screen, child_type, child_pos.x, child_pos.y, false, fall_scale)

func _draw_next_panel() -> void:
	draw_string(ThemeDB.fallback_font, Vector2(30, 80), "NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GameConstants.COLOR_TEXT_PRIMARY)

	if next_queue.size() > 0:
		var n1 = next_queue[0]
		var box1 = Rect2(30, 100, 156, 170)
		draw_rect(box1, Color(0.18, 0.20, 0.30, 0.6))
		draw_rect(box1, GameConstants.COLOR_PANEL_BORDER, false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(40, 124), "NEXT 1", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameConstants.COLOR_TEXT_MUTED)

		var c_pos = Vector2(108, 165)
		var p_pos = Vector2(108, 215)
		_draw_single_puyo(c_pos, n1["child"])
		_draw_single_puyo(p_pos, n1["pivot"])

	if next_queue.size() > 1:
		var n2 = next_queue[1]
		var box2 = Rect2(30, 290, 156, 170)
		draw_rect(box2, Color(0.18, 0.20, 0.30, 0.6))
		draw_rect(box2, GameConstants.COLOR_PANEL_BORDER, false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(40, 314), "NEXT 2", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameConstants.COLOR_TEXT_MUTED)

		var c_pos2 = Vector2(108, 355)
		var p_pos2 = Vector2(108, 405)
		_draw_single_puyo(c_pos2, n2["child"])
		_draw_single_puyo(p_pos2, n2["pivot"])

	var help_box = Rect2(30, 480, 156, 175)
	draw_rect(help_box, Color(0.10, 0.12, 0.18, 0.8))
	draw_rect(help_box, GameConstants.COLOR_PANEL_BORDER, false, 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(40, 506), "CONTROLS", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameConstants.COLOR_TEXT_ACCENT)
	draw_string(ThemeDB.fallback_font, Vector2(40, 532), "D-Pad: Move / Drop", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(40, 554), "A Button: Rot Right", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(40, 576), "B Button: Rot Left", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(40, 598), "Up: Hard Drop", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(40, 620), "START: Pause", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, GameConstants.COLOR_TEXT_MUTED)

func _draw_side_ui() -> void:
	var x = 536
	draw_string(ThemeDB.fallback_font, Vector2(x, 85), "SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(x, 118), "%07d" % score, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, GameConstants.COLOR_TEXT_PRIMARY)

	draw_string(ThemeDB.fallback_font, Vector2(x, 175), "HI-SCORE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(x, 208), "%07d" % hi_score, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, GameConstants.COLOR_TEXT_ACCENT)

	draw_string(ThemeDB.fallback_font, Vector2(x, 265), "MAX CHAIN", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(x, 298), "%d CHAIN" % max_chain, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GameConstants.COLOR_TEXT_PRIMARY)

	draw_string(ThemeDB.fallback_font, Vector2(x, 355), "TOTAL CLEARED", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(x, 388), "%d PUYOS" % total_cleared_puyos, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GameConstants.COLOR_TEXT_PRIMARY)

	var mins = int(game_time) / 60
	var secs = int(game_time) % 60
	draw_string(ThemeDB.fallback_font, Vector2(x, 445), "TIME", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameConstants.COLOR_TEXT_MUTED)
	draw_string(ThemeDB.fallback_font, Vector2(x, 478), "%02d:%02d" % [mins, secs], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, GameConstants.COLOR_TEXT_PRIMARY)

	draw_string(ThemeDB.fallback_font, Vector2(24, 28), "1P ENDLESS MODE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameConstants.COLOR_TEXT_ACCENT)
	draw_string(ThemeDB.fallback_font, Vector2(536, 28), "GODOT 4 PUZZLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GameConstants.COLOR_TEXT_MUTED)

func _draw_effects() -> void:
	if chain_banner_timer > 0.0 and chain_banner_text != "":
		var alpha = min(1.0, chain_banner_timer / 0.3)
		var center_y = GameConstants.SCREEN_HEIGHT / 2.0
		# バウンススケール
		var banner_rect = Rect2(GameConstants.FIELD_X, center_y - 32, GameConstants.FIELD_WIDTH, 64)
		draw_rect(banner_rect, Color(0.04, 0.06, 0.12, 0.88 * alpha))
		draw_rect(banner_rect, Color(0.98, 0.82, 0.15, alpha), false, 2.5)
		draw_string(ThemeDB.fallback_font, Vector2(GameConstants.FIELD_X + 20, center_y + 10), chain_banner_text, HORIZONTAL_ALIGNMENT_LEFT, int(GameConstants.FIELD_WIDTH - 40), 30, Color(1, 0.95, 0.4, alpha))

## -------------------------------------------------------------
## ユーティリティ
## -------------------------------------------------------------
func _grid_to_screen(col: int, row: int) -> Vector2:
	var x = GameConstants.FIELD_X + (col + 0.5) * GameConstants.CELL_SIZE
	var y = GameConstants.FIELD_Y + (row - 1 + 0.5) * GameConstants.CELL_SIZE
	return Vector2(x, y)

## -------------------------------------------------------------
## 四角い石ブロック (お邪魔ぷよ) 描画
## -------------------------------------------------------------
func _draw_stone_block(center_pos: Vector2, size: float, is_clearing: bool = false, custom_scale: Vector2 = Vector2.ONE, col: int = -1, row: int = -1) -> void:
	var half_w = (size * 0.5 - 2.0) * custom_scale.x
	var half_h = (size * 0.5 - 2.0) * custom_scale.y

	# 1. 影 (ドロップシャドウ)
	var shadow_rect = Rect2(center_pos.x - half_w, center_pos.y - half_h + 3.0, half_w * 2.0, half_h * 2.0)
	draw_rect(shadow_rect, Color(0, 0, 0, 0.32))

	# 石の色設定
	var stone_dark = Color(0.24, 0.26, 0.32)       # 外枠・底面シャドウ
	var stone_body = Color(0.55, 0.58, 0.65)       # 石表面ベース
	var stone_light = Color(0.84, 0.88, 0.95)      # 上部面取りハイライト
	var stone_bevel_shadow = Color(0.34, 0.37, 0.44) # 下部面取り

	if is_clearing:
		if int(clear_anim_progress * 24.0) % 2 == 0:
			stone_body = Color(0.96, 0.96, 1.0)
			stone_light = Color(1.0, 1.0, 1.0)

	# 2. 外枠・アンダーシャドウ
	var base_rect = Rect2(center_pos.x - half_w, center_pos.y - half_h, half_w * 2.0, half_h * 2.0)
	draw_rect(base_rect, stone_dark)

	# 3. メイン石ブロックボディ (少し内側)
	var inner_rect = Rect2(center_pos.x - half_w + 2.0, center_pos.y - half_h + 2.0, (half_w - 2.0) * 2.0, (half_h - 2.0) * 2.0)
	draw_rect(inner_rect, stone_body)

	# 4. 立体的な石の面取り (Bevel edges)
	# 上面・左面ハイライトライン
	draw_line(Vector2(inner_rect.position.x, inner_rect.position.y), Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y), stone_light, 2.2)
	draw_line(Vector2(inner_rect.position.x, inner_rect.position.y), Vector2(inner_rect.position.x, inner_rect.position.y + inner_rect.size.y), stone_light, 2.2)
	# 下面・右面シャドウライン
	draw_line(Vector2(inner_rect.position.x, inner_rect.position.y + inner_rect.size.y), Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y + inner_rect.size.y), stone_bevel_shadow, 2.2)
	draw_line(Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y), Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y + inner_rect.size.y), stone_bevel_shadow, 2.2)

	# 5. 石の表面テクスチャ (彫り込みクラック & 斑点)
	var crack_pts: Array[Vector2] = [
		center_pos + Vector2(-half_w * 0.45, -half_h * 0.4),
		center_pos + Vector2(-half_w * 0.1, -half_h * 0.05),
		center_pos + Vector2(half_w * 0.15, -half_h * 0.3),
		center_pos + Vector2(half_w * 0.5, half_h * 0.45)
	]
	for i in range(crack_pts.size() - 1):
		draw_line(crack_pts[i], crack_pts[i+1], Color(0.18, 0.20, 0.25, 0.85), 2.0)
		draw_line(crack_pts[i] + Vector2(1.0, 1.0), crack_pts[i+1] + Vector2(1.0, 1.0), Color(0.88, 0.92, 0.98, 0.55), 1.2)

	# 小さな窪み
	draw_circle(center_pos + Vector2(-half_w * 0.35, half_h * 0.35), 2.0, Color(0.24, 0.27, 0.33, 0.75))
	draw_circle(center_pos + Vector2(half_w * 0.32, -half_h * 0.35), 1.6, Color(0.24, 0.27, 0.33, 0.75))
