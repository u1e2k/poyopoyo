class_name BattleGame
extends Control

const CELL_SIZE: float = 26.0
const P1_FIELD_X: float = 44.0
const P1_FIELD_Y: float = 180.0
const P2_FIELD_X: float = 520.0
const P2_FIELD_Y: float = 180.0
const FIELD_W: float = 156.0  # 6 * 26
const FIELD_H: float = 312.0  # 12 * 26

var p1: BattlePlayer
var p2: BattlePlayer
var input_handler: InputHandler

# 勝敗スコア
var p1_wins: int = 0
var cpu_wins: int = 0

var game_time: float = 0.0
var is_game_active: bool = false
var is_demo: bool = false
var demo_end_timer: float = 0.0

# パーティクル & エフェクト
var active_particles: Array = []
var active_rings: Array = []

# UIノード参照
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var result_panel: Panel = $ResultPanel
@onready var result_title: Label = $ResultPanel/ResultTitle
@onready var result_score_p1: Label = $ResultPanel/P1Score
@onready var result_score_cpu: Label = $ResultPanel/CPUScore
@onready var retry_button: Button = $ResultPanel/VBoxContainer/RetryButton
@onready var title_button: Button = $ResultPanel/VBoxContainer/TitleButton

# バナー演出
var banner_text: String = ""
var banner_timer: float = 0.0

func _ready() -> void:
	randomize()

	is_demo = GameConstants.is_demo_mode

	# 入力ハンドラー
	input_handler = InputHandler.new()
	add_child(input_handler)

	if not is_demo:
		input_handler.move_left_pressed.connect(_on_p1_move_left)
		input_handler.move_right_pressed.connect(_on_p1_move_right)
		input_handler.rotate_left_pressed.connect(_on_p1_rotate_left)
		input_handler.rotate_right_pressed.connect(_on_p1_rotate_right)
		input_handler.hard_drop_pressed.connect(_on_p1_hard_drop)
		input_handler.pause_pressed.connect(_on_pause_requested)

	# プレイヤー生成 (デモ時はP1もCPU AIに設定)
	p1 = BattlePlayer.new()
	p1.player_type = BattlePlayer.PlayerType.CPU if is_demo else BattlePlayer.PlayerType.HUMAN
	add_child(p1)

	p2 = BattlePlayer.new()
	p2.player_type = BattlePlayer.PlayerType.CPU
	add_child(p2)

	p1.garbage_sent.connect(_on_p1_send_garbage)
	p2.garbage_sent.connect(_on_p2_send_garbage)

	p1.clear_popped.connect(_on_p1_popped)
	p2.clear_popped.connect(_on_p2_popped)

	p1.player_died.connect(_on_p1_died)
	p2.player_died.connect(_on_p2_died)

	# ポーズ & リザルト
	pause_menu.resume_requested.connect(_on_pause_resume)
	pause_menu.retry_requested.connect(start_match)
	pause_menu.title_requested.connect(_on_back_to_title)

	retry_button.pressed.connect(start_match)
	title_button.pressed.connect(_on_back_to_title)

	retry_button.focus_neighbor_top = retry_button.get_path_to(title_button)
	retry_button.focus_neighbor_bottom = retry_button.get_path_to(title_button)
	title_button.focus_neighbor_top = title_button.get_path_to(retry_button)
	title_button.focus_neighbor_bottom = title_button.get_path_to(retry_button)

	result_panel.visible = false
	start_match()

func _input(event: InputEvent) -> void:
	if is_demo and event.is_pressed():
		get_viewport().set_input_as_handled()
		_on_back_to_title()

func _process(delta: float) -> void:
	if not get_tree().paused:
		game_time += delta
		if banner_timer > 0.0:
			banner_timer -= delta

		_update_effects(delta)

		if is_game_active:
			p1.process_turn(delta)
			p2.process_turn(delta)
		elif is_demo:
			demo_end_timer += delta
			if demo_end_timer >= 2.5:
				_on_back_to_title()

	queue_redraw()

func _update_effects(delta: float) -> void:
	var i = active_particles.size() - 1
	while i >= 0:
		var p = active_particles[i]
		p["pos"] += p["vel"] * delta
		p["vel"].y += 340.0 * delta
		p["vel"].x *= 0.96
		p["life"] -= delta
		if p["life"] <= 0.0:
			active_particles.remove_at(i)
		i -= 1

	var j = active_rings.size() - 1
	while j >= 0:
		var r = active_rings[j]
		r["life"] -= delta
		var t = 1.0 - (r["life"] / r["max_life"])
		r["radius"] = lerp(3.0, r["max_radius"], t)
		if r["life"] <= 0.0:
			active_rings.remove_at(j)
		j -= 1

func start_match() -> void:
	result_panel.visible = false
	banner_text = ""
	banner_timer = 0.0
	demo_end_timer = 0.0
	active_particles.clear()
	active_rings.clear()
	is_game_active = true
	input_handler.is_enabled = not is_demo
	input_handler.reset_state()

	p1.init_game()
	p2.init_game()

## -------------------------------------------------------------
## 消去ポップ & パーティクル生成
## -------------------------------------------------------------
func _on_p1_popped(cleared_cells: Array, cell_types: Dictionary, chain_count: int) -> void:
	_spawn_pop_effects(P1_FIELD_X, P1_FIELD_Y, cleared_cells, cell_types, chain_count)

func _on_p2_popped(cleared_cells: Array, cell_types: Dictionary, chain_count: int) -> void:
	_spawn_pop_effects(P2_FIELD_X, P2_FIELD_Y, cleared_cells, cell_types, chain_count)

func _spawn_pop_effects(fx: float, fy: float, cleared_cells: Array, cell_types: Dictionary, chain_count: int) -> void:
	for cell in cleared_cells:
		var center = Vector2(fx + (cell.x + 0.5) * CELL_SIZE, fy + (cell.y - 1 + 0.5) * CELL_SIZE)
		var type = cell_types.get(cell, GameConstants.PuyoType.RED)
		var color = GameConstants.PUYO_COLORS.get(type, Color.WHITE)
		var highlight = GameConstants.PUYO_HIGHLIGHT_COLORS.get(type, Color.WHITE)

		# 衝撃波リング
		active_rings.append({
			"pos": center,
			"radius": 4.0,
			"max_radius": 22.0,
			"color": highlight,
			"life": 0.25,
			"max_life": 0.25
		})

		# スプラッシュ粒子
		var count = 6 + (chain_count * 2)
		for i in range(count):
			var angle = (TAU / count) * i + randf_range(-0.3, 0.3)
			var speed = randf_range(70.0, 160.0)
			var vel = Vector2(cos(angle), sin(angle)) * speed
			var p_col = color if (i % 2 == 0) else highlight
			active_particles.append({
				"pos": center + Vector2(randf_range(-3, 3), randf_range(-3, 3)),
				"vel": vel,
				"color": p_col,
				"size": randf_range(2.5, 4.5),
				"life": randf_range(0.20, 0.38),
				"max_life": 0.38
			})

## -------------------------------------------------------------
## お邪魔ぷよ送信 & 相殺 (Offsetting) ロジック
## -------------------------------------------------------------
func _on_p1_send_garbage(amount: int) -> void:
	if p1.pending_garbage > 0:
		var offset = min(p1.pending_garbage, amount)
		p1.pending_garbage -= offset
		amount -= offset

	if amount > 0:
		p2.pending_garbage += amount
		var sender_name = "CPU 1" if is_demo else "1P"
		_show_banner("%s: %d GARBAGE!" % [sender_name, amount])

func _on_p2_send_garbage(amount: int) -> void:
	if p2.pending_garbage > 0:
		var offset = min(p2.pending_garbage, amount)
		p2.pending_garbage -= offset
		amount -= offset

	if amount > 0:
		p1.pending_garbage += amount
		var sender_name = "CPU 2" if is_demo else "CPU"
		_show_banner("%s: %d GARBAGE!" % [sender_name, amount])

func _show_banner(txt: String) -> void:
	banner_text = txt
	banner_timer = 1.0

## -------------------------------------------------------------
## 勝敗判定
## -------------------------------------------------------------
func _on_p1_died() -> void:
	if not is_game_active:
		return
	is_game_active = false
	cpu_wins += 1

	if is_demo:
		_show_banner("CPU 2 WIN!!")
	else:
		_show_result("YOU LOSE...", Color(0.96, 0.26, 0.35))

func _on_p2_died() -> void:
	if not is_game_active:
		return
	is_game_active = false
	p1_wins += 1

	if is_demo:
		_show_banner("CPU 1 WIN!!")
	else:
		_show_result("YOU WIN!!", Color(0.98, 0.82, 0.15))

func _show_result(title_str: String, col: Color) -> void:
	input_handler.is_enabled = false
	result_title.text = title_str
	result_title.add_theme_color_override("font_color", col)
	result_score_p1.text = "1P SCORE: %07d" % p1.score
	result_score_cpu.text = "CPU SCORE: %07d" % p2.score
	result_panel.visible = true
	retry_button.call_deferred("grab_focus")

## -------------------------------------------------------------
## 1P コントローラー入力
## -------------------------------------------------------------
func _on_p1_move_left() -> void:
	if is_game_active and not is_demo:
		p1.move_left()

func _on_p1_move_right() -> void:
	if is_game_active and not is_demo:
		p1.move_right()

func _on_p1_rotate_left() -> void:
	if is_game_active and not is_demo:
		p1.rotate_left()

func _on_p1_rotate_right() -> void:
	if is_game_active and not is_demo:
		p1.rotate_right()

func _on_p1_hard_drop() -> void:
	if is_game_active and not is_demo:
		p1.hard_drop()

func _on_pause_requested() -> void:
	if is_game_active and not is_demo:
		pause_menu.open_menu()

func _on_pause_resume() -> void:
	pass

func _on_back_to_title() -> void:
	GameConstants.is_demo_mode = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

## -------------------------------------------------------------
## 描画 (2画面対戦レイアウト & デモ演出 & パーティクル)
## -------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(0, 0, 720, 720), GameConstants.COLOR_BG)

	# 上部ヘッダー
	draw_rect(Rect2(0, 0, 720, 50), Color(0.06, 0.07, 0.10))
	draw_line(Vector2(0, 50), Vector2(720, 50), GameConstants.COLOR_PANEL_BORDER, 2.0)

	var p1_label = "CPU 1 (AI)" if is_demo else "1P (YOU)"
	var center_label = "DEMO PLAY" if is_demo else "VS CPU"
	var p2_label = "CPU 2 (AI)" if is_demo else "CPU (AI)"

	draw_string(ThemeDB.fallback_font, Vector2(24, 32), p1_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GameConstants.COLOR_TEXT_PRIMARY)
	draw_string(ThemeDB.fallback_font, Vector2(300, 32), center_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GameConstants.COLOR_TEXT_ACCENT)
	draw_string(ThemeDB.fallback_font, Vector2(600, 32), p2_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.96, 0.40, 0.45))

	var win_str = "%d  -  %d" % [p1_wins, cpu_wins]
	draw_string(ThemeDB.fallback_font, Vector2(330, 80), win_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, GameConstants.COLOR_TEXT_PRIMARY)

	# 1P & CPUフィールド描画
	_draw_player_field(p1, P1_FIELD_X, P1_FIELD_Y, p1_label)
	_draw_player_field(p2, P2_FIELD_X, P2_FIELD_Y, p2_label)

	# 中央情報
	_draw_center_info()

	# パーティクル & ショックウェーブ描画
	_draw_particles_and_rings()

	# バナー描画
	if banner_timer > 0.0 and banner_text != "":
		var alpha = min(1.0, banner_timer / 0.3)
		var center_rect = Rect2(200, 320, 320, 50)
		draw_rect(center_rect, Color(0.05, 0.08, 0.15, 0.9 * alpha))
		draw_rect(center_rect, Color(0.98, 0.82, 0.15, alpha), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(210, 352), banner_text, HORIZONTAL_ALIGNMENT_CENTER, 300, 20, Color(1, 0.95, 0.4, alpha))

	# 下部操作ガイド
	if is_demo:
		var blink = sin(game_time * 5.0) > 0.0
		var guide_col = GameConstants.COLOR_TEXT_ACCENT if blink else Color(0.6, 0.6, 0.7)
		draw_string(ThemeDB.fallback_font, Vector2(0, 690), "- PRESS ANY BUTTON TO TITLE -", HORIZONTAL_ALIGNMENT_CENTER, 720, 16, guide_col)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(0, 690), "D-Pad: Move / Down: Drop / A, B: Rotate / START: Pause", HORIZONTAL_ALIGNMENT_CENTER, 720, 14, GameConstants.COLOR_TEXT_MUTED)

func _draw_player_field(pl: BattlePlayer, fx: float, fy: float, label: String) -> void:
	var f_rect = Rect2(fx, fy, FIELD_W, FIELD_H)
	draw_rect(f_rect, GameConstants.COLOR_FIELD_BG)
	draw_rect(f_rect, GameConstants.COLOR_FIELD_BORDER, false, 3.0)

	for c in range(1, GameConstants.COLS):
		var x = fx + c * CELL_SIZE
		draw_line(Vector2(x, fy), Vector2(x, fy + FIELD_H), GameConstants.COLOR_GRID_LINE, 1.0)
	for r in range(1, GameConstants.VISIBLE_ROWS):
		var y = fy + r * CELL_SIZE
		draw_line(Vector2(fx, y), Vector2(fx + FIELD_W, y), GameConstants.COLOR_GRID_LINE, 1.0)

	var choke_x = fx + GameConstants.SPAWN_COL * CELL_SIZE
	draw_line(Vector2(choke_x, fy), Vector2(choke_x + CELL_SIZE, fy), Color(0.96, 0.26, 0.35, 0.8), 2.5)

	# 確定ぷよ描画
	for c in range(GameConstants.COLS):
		for r in range(1, GameConstants.ROWS):
			var type = pl.grid_model.get_cell(c, r)
			if type != GameConstants.PuyoType.EMPTY:
				var center = Vector2(fx + (c + 0.5) * CELL_SIZE, fy + (r - 1 + 0.5) * CELL_SIZE)
				_draw_mini_puyo(center, type, false)

	# 消去中ぷよの膨張・振動・痛がり目描画 (アニメーション前半)
	if pl.current_state == BattlePlayer.State.CLEAR_ANIM and pl.last_cleared_info.has("cleared_cells"):
		if pl.clear_anim_progress < 0.45:
			var p_t = pl.clear_anim_progress / 0.45
			var pop_scale = 1.0 + sin(p_t * PI * 0.5) * 0.28
			var shake = Vector2(sin(game_time * 60.0) * 1.2, cos(game_time * 60.0) * 1.2)

			for cell in pl.last_cleared_info["cleared_cells"]:
				var cell_type = pl.last_cleared_info.get("cell_types", {}).get(cell, GameConstants.PuyoType.RED)
				var center = Vector2(fx + (cell.x + 0.5) * CELL_SIZE, fy + (cell.y - 1 + 0.5) * CELL_SIZE) + shake
				_draw_mini_puyo(center, cell_type, true, pop_scale)

	# 上空から落下中のお邪魔ぷよ描画
	for g in pl.active_falling_garbage:
		if not g["is_landed"] and g["delay"] <= 0.0:
			var center = Vector2(fx + (g["col"] + 0.5) * CELL_SIZE, fy + g["current_y"])
			_draw_mini_puyo(center, GameConstants.PuyoType.GARBAGE, false)

	# 操作中ツモ描画
	if pl.pivot_type != GameConstants.PuyoType.EMPTY:
		var c_pos = pl.pivot_pos + GameConstants.DIR_OFFSETS[pl.child_dir]
		if pl.pivot_pos.y >= 1:
			var p_center = Vector2(fx + (pl.pivot_pos.x + 0.5) * CELL_SIZE, fy + (pl.pivot_pos.y - 1 + 0.5) * CELL_SIZE)
			_draw_mini_puyo(p_center, pl.pivot_type, false)
		if c_pos.y >= 1:
			var c_center = Vector2(fx + (c_pos.x + 0.5) * CELL_SIZE, fy + (c_pos.y - 1 + 0.5) * CELL_SIZE)
			_draw_mini_puyo(c_center, pl.child_type, false)

	# スコア表示
	draw_string(ThemeDB.fallback_font, Vector2(fx, fy + FIELD_H + 26), "%07d" % pl.score, HORIZONTAL_ALIGNMENT_LEFT, int(FIELD_W), 18, GameConstants.COLOR_TEXT_PRIMARY)

	# お邪魔予告表示（頭上）
	var g_box = Rect2(fx, fy - 40, FIELD_W, 30)
	draw_rect(g_box, Color(0.12, 0.14, 0.20, 0.7))
	draw_rect(g_box, GameConstants.COLOR_PANEL_BORDER, false, 1.0)
	if pl.pending_garbage > 0:
		draw_string(ThemeDB.fallback_font, Vector2(fx + 8, fy - 18), "⚠ %d" % pl.pending_garbage, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.96, 0.35, 0.40))
	else:
		draw_string(ThemeDB.fallback_font, Vector2(fx + 8, fy - 18), "SAFE", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameConstants.COLOR_TEXT_MUTED)

func _draw_center_info() -> void:
	var p1_next_label = "CPU 1" if is_demo else "1P NEXT"
	var p2_next_label = "CPU 2" if is_demo else "CPU NEXT"

	# 1P NEXT
	draw_string(ThemeDB.fallback_font, Vector2(235, 120), p1_next_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameConstants.COLOR_TEXT_PRIMARY)
	var n1_box = Rect2(230, 130, 75, 120)
	draw_rect(n1_box, GameConstants.COLOR_PANEL_BG)
	draw_rect(n1_box, GameConstants.COLOR_PANEL_BORDER, false, 1.5)
	if p1.next_queue.size() > 0:
		var n = p1.next_queue[0]
		_draw_mini_puyo(Vector2(267, 165), n["child"])
		_draw_mini_puyo(Vector2(267, 205), n["pivot"])

	# CPU NEXT
	draw_string(ThemeDB.fallback_font, Vector2(415, 120), p2_next_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.96, 0.40, 0.45))
	var n2_box = Rect2(415, 130, 75, 120)
	draw_rect(n2_box, GameConstants.COLOR_PANEL_BG)
	draw_rect(n2_box, GameConstants.COLOR_PANEL_BORDER, false, 1.5)
	if p2.next_queue.size() > 0:
		var n2 = p2.next_queue[0]
		_draw_mini_puyo(Vector2(452, 165), n2["child"])
		_draw_mini_puyo(Vector2(452, 205), n2["pivot"])

func _draw_mini_puyo(center_pos: Vector2, type: int, is_clearing: bool = false, scale_factor: float = 1.0) -> void:
	if type == GameConstants.PuyoType.EMPTY:
		return

	var base_col = GameConstants.PUYO_COLORS.get(type, Color.WHITE)
	var shadow_col = GameConstants.PUYO_SHADOW_COLORS.get(type, Color(0.2, 0.2, 0.2))
	var highlight_col = GameConstants.PUYO_HIGHLIGHT_COLORS.get(type, Color.WHITE)

	var r = ((CELL_SIZE / 2.0) - 1.5) * scale_factor
	if is_clearing:
		if int(game_time * 24.0) % 2 == 0:
			base_col = highlight_col

	draw_circle(center_pos + Vector2(0, 2), r * 0.9, Color(0, 0, 0, 0.25))
	draw_circle(center_pos, r, shadow_col)
	draw_circle(center_pos + Vector2(0, -1), r - 1.0, base_col)
	draw_circle(center_pos + Vector2(-r * 0.35, -r * 0.35), r * 0.3, Color(1, 1, 1, 0.8))

	if type != GameConstants.PuyoType.GARBAGE:
		var eye_w = r * 0.25
		var left_eye = center_pos + Vector2(-r * 0.35, -r * 0.05)
		var right_eye = center_pos + Vector2(r * 0.35, -r * 0.05)

		if is_clearing:
			# 消去時の「＞＜」目
			var sz = eye_w * 1.1
			draw_line(left_eye + Vector2(-sz, -sz), left_eye + Vector2(sz * 0.4, 0), Color(0.12, 0.12, 0.18), 2.0)
			draw_line(left_eye + Vector2(sz * 0.4, 0), left_eye + Vector2(-sz, sz), Color(0.12, 0.12, 0.18), 2.0)
			draw_line(right_eye + Vector2(sz, -sz), right_eye + Vector2(-sz * 0.4, 0), Color(0.12, 0.12, 0.18), 2.0)
			draw_line(right_eye + Vector2(-sz * 0.4, 0), right_eye + Vector2(sz, sz), Color(0.12, 0.12, 0.18), 2.0)
		else:
			draw_circle(left_eye, eye_w, Color.WHITE)
			draw_circle(right_eye, eye_w, Color.WHITE)
			draw_circle(left_eye + Vector2(0.5, 0.5), eye_w * 0.6, Color(0.1, 0.1, 0.15))
			draw_circle(right_eye + Vector2(0.5, 0.5), eye_w * 0.6, Color(0.1, 0.1, 0.15))

func _draw_particles_and_rings() -> void:
	for r in active_rings:
		var alpha = r["life"] / r["max_life"]
		var col = Color(r["color"].r, r["color"].g, r["color"].b, alpha * 0.85)
		draw_arc(r["pos"], r["radius"], 0, TAU, 18, col, 2.0)

	for p in active_particles:
		var alpha = p["life"] / p["max_life"]
		var col = Color(p["color"].r, p["color"].g, p["color"].b, alpha)
		draw_circle(p["pos"], p["size"] * alpha, col)
		draw_circle(p["pos"] + Vector2(-0.8, -0.8), p["size"] * alpha * 0.4, Color(1, 1, 1, alpha * 0.9))
