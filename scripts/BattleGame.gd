class_name BattleGame
extends Control

# レイアウト定数 (720x720解像度に最適化した大迫力・高視認性レイアウト)
const CELL_SIZE: float = 34.0
const FIELD_W: float = 204.0  # 6 * 34 = 204
const FIELD_H: float = 408.0  # 12 * 34 = 408

const P1_FIELD_X: float = 24.0
const P1_FIELD_Y: float = 190.0
const P2_FIELD_X: float = 492.0
const P2_FIELD_Y: float = 190.0

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

	# プレイヤー生成
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
		p["vel"].y += 360.0 * delta
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
		r["radius"] = lerp(4.0, r["max_radius"], t)
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
			"radius": 5.0,
			"max_radius": 28.0,
			"color": highlight,
			"life": 0.25,
			"max_life": 0.25
		})

		# スプラッシュ粒子
		var count = 7 + (chain_count * 2)
		for i in range(count):
			var angle = (TAU / count) * i + randf_range(-0.3, 0.3)
			var speed = randf_range(80.0, 180.0)
			var vel = Vector2(cos(angle), sin(angle)) * speed
			var p_col = color if (i % 2 == 0) else highlight
			active_particles.append({
				"pos": center + Vector2(randf_range(-4, 4), randf_range(-4, 4)),
				"vel": vel,
				"color": p_col,
				"size": randf_range(3.0, 5.5),
				"life": randf_range(0.22, 0.40),
				"max_life": 0.40
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
	result_score_p1.text = "SCORE: %07d" % p1.score
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
## 描画 (大迫力・見やすい2画面対戦レイアウト)
## -------------------------------------------------------------
func _draw() -> void:
	draw_rect(Rect2(0, 0, 720, 720), GameConstants.COLOR_BG)

	# 上部ヘッダー帯
	draw_rect(Rect2(0, 0, 720, 48), Color(0.06, 0.07, 0.10))
	draw_line(Vector2(0, 48), Vector2(720, 48), GameConstants.COLOR_PANEL_BORDER, 2.0)

	var p1_label = "CPU 1 (AI)" if is_demo else "1P (YOU)"
	var center_label = "DEMO PLAY" if is_demo else "VS CPU BATTLE"
	var p2_label = "CPU 2 (AI)" if is_demo else "CPU (AI)"

	draw_string(ThemeDB.fallback_font, Vector2(24, 32), p1_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GameConstants.COLOR_TEXT_PRIMARY)
	draw_string(ThemeDB.fallback_font, Vector2(270, 32), center_label, HORIZONTAL_ALIGNMENT_CENTER, 180, 18, GameConstants.COLOR_TEXT_ACCENT)
	draw_string(ThemeDB.fallback_font, Vector2(580, 32), p2_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.96, 0.40, 0.45))

	# 勝敗数表示
	var win_str = "%d  -  %d" % [p1_wins, cpu_wins]
	draw_string(ThemeDB.fallback_font, Vector2(300, 95), win_str, HORIZONTAL_ALIGNMENT_CENTER, 120, 32, GameConstants.COLOR_TEXT_PRIMARY)
	draw_string(ThemeDB.fallback_font, Vector2(300, 122), "WINS", HORIZONTAL_ALIGNMENT_CENTER, 120, 13, GameConstants.COLOR_TEXT_MUTED)

	# 1P & CPUフィールド描画
	_draw_player_field(p1, P1_FIELD_X, P1_FIELD_Y, p1_label)
	_draw_player_field(p2, P2_FIELD_X, P2_FIELD_Y, p2_label)

	# 中央情報 (NEXT)
	_draw_center_info()

	# パーティクル & ショックウェーブ描画
	_draw_particles_and_rings()

	# バナー描画
	if banner_timer > 0.0 and banner_text != "":
		var alpha = min(1.0, banner_timer / 0.3)
		var center_rect = Rect2(180, 340, 360, 56)
		draw_rect(center_rect, Color(0.04, 0.06, 0.12, 0.92 * alpha))
		draw_rect(center_rect, Color(0.98, 0.82, 0.15, alpha), false, 2.5)
		draw_string(ThemeDB.fallback_font, Vector2(190, 375), banner_text, HORIZONTAL_ALIGNMENT_CENTER, 340, 22, Color(1, 0.95, 0.4, alpha))

	# 下部フッター
	if is_demo:
		var blink = sin(game_time * 5.0) > 0.0
		var guide_col = GameConstants.COLOR_TEXT_ACCENT if blink else Color(0.6, 0.6, 0.7)
		draw_string(ThemeDB.fallback_font, Vector2(0, 698), "- PRESS ANY BUTTON TO TITLE -", HORIZONTAL_ALIGNMENT_CENTER, 720, 16, guide_col)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(0, 698), "D-Pad: Move / Down: Drop / A, B: Rotate / START: Pause", HORIZONTAL_ALIGNMENT_CENTER, 720, 14, GameConstants.COLOR_TEXT_MUTED)

func _draw_player_field(pl: BattlePlayer, fx: float, fy: float, label: String) -> void:
	# フィールド背景パネル
	var f_rect = Rect2(fx, fy, FIELD_W, FIELD_H)
	draw_rect(f_rect, GameConstants.COLOR_FIELD_BG)
	draw_rect(f_rect, GameConstants.COLOR_FIELD_BORDER, false, 3.0)

	# グリッド線
	for c in range(1, GameConstants.COLS):
		var x = fx + c * CELL_SIZE
		draw_line(Vector2(x, fy), Vector2(x, fy + FIELD_H), GameConstants.COLOR_GRID_LINE, 1.0)
	for r in range(1, GameConstants.VISIBLE_ROWS):
		var y = fy + r * CELL_SIZE
		draw_line(Vector2(fx, y), Vector2(fx + FIELD_W, y), GameConstants.COLOR_GRID_LINE, 1.0)

	# 窒息警告線
	var choke_x = fx + GameConstants.SPAWN_COL * CELL_SIZE
	draw_line(Vector2(choke_x, fy), Vector2(choke_x + CELL_SIZE, fy), Color(0.96, 0.26, 0.35, 0.8), 3.0)

	# 自由落下中の補間マッピング
	var falling_map: Dictionary = {}
	if pl.current_state == BattlePlayer.State.DROP_FREE and pl.active_drops.size() > 0:
		var ease_t = pl.drop_anim_progress * pl.drop_anim_progress
		for d in pl.active_drops:
			falling_map[Vector2i(d["col"], d["to_row"])] = lerp(float(d["from_row"]), float(d["to_row"]), ease_t)

	# 確定ぷよ描画 (同色連結・質感・落下補間付き)
	for c in range(GameConstants.COLS):
		for r in range(1, GameConstants.ROWS):
			var type = pl.grid_model.get_cell(c, r)
			if type != GameConstants.PuyoType.EMPTY:
				var cell_key = Vector2i(c, r)
				if falling_map.has(cell_key):
					var interp_row = falling_map[cell_key]
					var center = Vector2(fx + (c + 0.5) * CELL_SIZE, fy + (interp_row - 1 + 0.5) * CELL_SIZE)
					# 落下中は着地するまでコネクタを出さない
					_draw_battle_puyo(center, type, pl, -1, -1, false, Vector2(0.94, 1.06))
				else:
					var center = Vector2(fx + (c + 0.5) * CELL_SIZE, fy + (r - 1 + 0.5) * CELL_SIZE)
					_draw_battle_puyo(center, type, pl, c, r, false, Vector2.ONE, falling_map)

	# 消去中ぷよの膨張・振動・痛がり目描画 (アニメーション前半)
	if pl.current_state == BattlePlayer.State.CLEAR_ANIM and pl.last_cleared_info.has("cleared_cells"):
		if pl.clear_anim_progress < 0.45:
			var p_t = pl.clear_anim_progress / 0.45
			var pop_scale = 1.0 + sin(p_t * PI * 0.5) * 0.28
			var shake = Vector2(sin(game_time * 60.0) * 1.5, cos(game_time * 60.0) * 1.5)

			for cell in pl.last_cleared_info["cleared_cells"]:
				var cell_type = pl.last_cleared_info.get("cell_types", {}).get(cell, GameConstants.PuyoType.RED)
				var center = Vector2(fx + (cell.x + 0.5) * CELL_SIZE, fy + (cell.y - 1 + 0.5) * CELL_SIZE) + shake
				_draw_battle_puyo(center, cell_type, pl, cell.x, cell.y, true, Vector2(pop_scale, pop_scale))

	# 上空から落下中のお邪魔ぷよ描画
	for g in pl.active_falling_garbage:
		if not g["is_landed"] and g["delay"] <= 0.0:
			var center = Vector2(fx + (g["col"] + 0.5) * CELL_SIZE, fy + g["current_y"])
			_draw_battle_puyo(center, GameConstants.PuyoType.GARBAGE, pl, -1, -1, false, Vector2(0.92, 1.08))

	# 操作中ツモ描画
	if pl.pivot_type != GameConstants.PuyoType.EMPTY:
		var c_pos = pl.pivot_pos + GameConstants.DIR_OFFSETS[pl.child_dir]
		var fall_scale = Vector2(0.96, 1.04) if not pl.is_grounded else Vector2(1.06, 0.94)

		if pl.pivot_pos.y >= 1:
			var p_center = Vector2(fx + (pl.pivot_pos.x + 0.5) * CELL_SIZE, fy + (pl.pivot_pos.y - 1 + 0.5) * CELL_SIZE)
			_draw_battle_puyo(p_center, pl.pivot_type, pl, -1, -1, false, fall_scale)
		if c_pos.y >= 1:
			var c_center = Vector2(fx + (c_pos.x + 0.5) * CELL_SIZE, fy + (c_pos.y - 1 + 0.5) * CELL_SIZE)
			_draw_battle_puyo(c_center, pl.child_type, pl, -1, -1, false, fall_scale)

	# スコア表示 (1Pのみ表示、CPU側やデモプレイ時は非表示にして画面をすっきりさせる)
	if pl == p1 and not is_demo:
		draw_string(ThemeDB.fallback_font, Vector2(fx, fy + FIELD_H + 28), "SCORE  %07d" % pl.score, HORIZONTAL_ALIGNMENT_LEFT, int(FIELD_W), 18, GameConstants.COLOR_TEXT_PRIMARY)

	# お邪魔予告表示トレイ (頭上)
	var g_box = Rect2(fx, fy - 48, FIELD_W, 36)
	draw_rect(g_box, Color(0.12, 0.15, 0.22, 0.9))
	draw_rect(g_box, GameConstants.COLOR_PANEL_BORDER, false, 1.5)

	if pl.pending_garbage > 0:
		# 予告お邪魔アイコン & 数値
		_draw_garbage_tray(fx + 8, fy - 30, pl.pending_garbage)
	else:
		draw_string(ThemeDB.fallback_font, Vector2(fx + 12, fy - 24), "SAFE (0)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GameConstants.COLOR_TEXT_MUTED)

func _draw_garbage_tray(x: float, y: float, count: int) -> void:
	# お邪魔予告アイコン (四角い石ブロック)
	var icon_rect = Rect2(x + 2, y - 8, 16, 16)
	draw_rect(icon_rect, Color(0.28, 0.30, 0.36))
	draw_rect(Rect2(x + 3.5, y - 6.5, 13, 13), Color(0.56, 0.60, 0.68))
	draw_line(Vector2(x + 3.5, y - 6.5), Vector2(x + 16.5, y - 6.5), Color(0.82, 0.86, 0.94), 1.5)
	draw_line(Vector2(x + 3.5, y - 6.5), Vector2(x + 3.5, y + 6.5), Color(0.82, 0.86, 0.94), 1.5)
	draw_string(ThemeDB.fallback_font, Vector2(x + 26, y + 6), "× %d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.98, 0.35, 0.45))

func _draw_center_info() -> void:
	var p1_next_label = "CPU 1" if is_demo else "1P NEXT"
	var p2_next_label = "CPU 2" if is_demo else "CPU NEXT"

	# 1P NEXT (中央左: X=240〜330)
	draw_string(ThemeDB.fallback_font, Vector2(244, 180), p1_next_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameConstants.COLOR_TEXT_PRIMARY)
	var n1_box = Rect2(240, 192, 90, 140)
	draw_rect(n1_box, GameConstants.COLOR_PANEL_BG)
	draw_rect(n1_box, GameConstants.COLOR_PANEL_BORDER, false, 2.0)
	if p1.next_queue.size() > 0:
		var n = p1.next_queue[0]
		_draw_battle_puyo(Vector2(285, 235), n["child"], null, -1, -1, false)
		_draw_battle_puyo(Vector2(285, 285), n["pivot"], null, -1, -1, false)

	# CPU NEXT (中央右: X=390〜480)
	draw_string(ThemeDB.fallback_font, Vector2(394, 180), p2_next_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.96, 0.40, 0.45))
	var n2_box = Rect2(390, 192, 90, 140)
	draw_rect(n2_box, GameConstants.COLOR_PANEL_BG)
	draw_rect(n2_box, GameConstants.COLOR_PANEL_BORDER, false, 2.0)
	if p2.next_queue.size() > 0:
		var n2 = p2.next_queue[0]
		_draw_battle_puyo(Vector2(435, 235), n2["child"], null, -1, -1, false)
		_draw_battle_puyo(Vector2(435, 285), n2["pivot"], null, -1, -1, false)

## -------------------------------------------------------------
## 質感・同色連結・目つき付きのバトルぷよ描画
## -------------------------------------------------------------
func _draw_battle_puyo(center_pos: Vector2, type: int, pl: BattlePlayer, col: int = -1, row: int = -1, is_clearing: bool = false, custom_scale: Vector2 = Vector2.ONE, falling_map: Dictionary = {}) -> void:
	if type == GameConstants.PuyoType.EMPTY:
		return

	# お邪魔ぷよは四角い石ブロックとして描画
	if type == GameConstants.PuyoType.GARBAGE:
		_draw_stone_block(center_pos, CELL_SIZE, is_clearing, custom_scale, col, row)
		return

	var base_col: Color = GameConstants.PUYO_COLORS.get(type, Color.WHITE)
	var shadow_col: Color = GameConstants.PUYO_SHADOW_COLORS.get(type, Color(0.2, 0.2, 0.2))
	var highlight_col: Color = GameConstants.PUYO_HIGHLIGHT_COLORS.get(type, Color.WHITE)

	var base_radius = (CELL_SIZE / 2.0) - 1.5

	# 呼吸アニメーション
	var breath = 0.0
	if not is_clearing:
		var phase = (col * 1.3 + row * 0.9) if (col >= 0 and row >= 0) else 0.0
		breath = sin(game_time * 4.5 + phase) * 0.035

	var rx = base_radius * (1.0 + breath) * custom_scale.x
	var ry = base_radius * (1.0 - breath) * custom_scale.y

	if is_clearing:
		if int(game_time * 24.0) % 2 == 0:
			base_col = highlight_col

	# 1. ドロップシャドウ
	draw_circle(center_pos + Vector2(0, 2.5), rx * 0.9, Color(0, 0, 0, 0.28))

	# 2. 同色ぷよ同士の有機的ゼリーコネクタ (連結の見える化)
	if pl != null and col != -1 and row != -1 and not is_clearing and type != GameConstants.PuyoType.GARBAGE:
		var neighbors = [
			{"dir": Vector2i(1, 0), "offset": Vector2(CELL_SIZE / 2.0, 0)},
			{"dir": Vector2i(-1, 0), "offset": Vector2(-CELL_SIZE / 2.0, 0)},
			{"dir": Vector2i(0, 1), "offset": Vector2(0, CELL_SIZE / 2.0)},
			{"dir": Vector2i(0, -1), "offset": Vector2(0, -CELL_SIZE / 2.0)}
		]
		for n in neighbors:
			var nc = col + n["dir"].x
			var nr = row + n["dir"].y
			# 隣接セルが落下中 (まだ着地していない) ならコネクタを繋がない
			if falling_map.has(Vector2i(nc, nr)):
				continue
			if pl.grid_model.is_valid_coord(nc, nr) and pl.grid_model.get_cell(nc, nr) == type:
				var half_w = 9.0
				if n["dir"].x != 0:
					var bridge_rect = Rect2(center_pos.x + min(0, n["offset"].x), center_pos.y - half_w, abs(n["offset"].x), half_w * 2)
					draw_rect(bridge_rect, shadow_col)
					var inner_rect = Rect2(center_pos.x + min(0, n["offset"].x), center_pos.y - half_w + 1.2, abs(n["offset"].x), (half_w - 1.2) * 2)
					draw_rect(inner_rect, base_col)
				elif n["dir"].y != 0:
					var bridge_rect = Rect2(center_pos.x - half_w, center_pos.y + min(0, n["offset"].y), half_w * 2, abs(n["offset"].y))
					draw_rect(bridge_rect, shadow_col)
					var inner_rect = Rect2(center_pos.x - half_w + 1.2, center_pos.y + min(0, n["offset"].y), (half_w - 1.2) * 2, abs(n["offset"].y))
					draw_rect(inner_rect, base_col)

	# 3. 外枠 / 立体アンダーシャドウ
	draw_circle(center_pos, rx, shadow_col)

	# 4. メインボディ
	draw_circle(center_pos + Vector2(0, -1.2), rx - 1.0, base_col)

	# 5. 上部インナーグロー
	var glow_col = highlight_col
	glow_col.a = 0.42
	draw_circle(center_pos + Vector2(0, -ry * 0.35), rx * 0.65, glow_col)

	# 6. 下部リムライト
	var rim_col = highlight_col
	rim_col.a = 0.32
	draw_circle(center_pos + Vector2(0, ry * 0.5), rx * 0.45, rim_col)

	# 7. メイン・スペキュラハイライト
	var main_spec = center_pos + Vector2(-rx * 0.38, -ry * 0.38)
	draw_circle(main_spec, rx * 0.28, Color(1, 1, 1, 0.85))
	draw_circle(main_spec + Vector2(-0.8, -0.8), rx * 0.14, Color(1, 1, 1, 0.95))

	# 8. サブハイライト
	draw_circle(center_pos + Vector2(rx * 0.4, ry * 0.32), rx * 0.12, Color(1, 1, 1, 0.5))

	# 9. 目 (キャッチライト・まばたき・痛がり目)
	if type != GameConstants.PuyoType.GARBAGE:
		var eye_offset_x = rx * 0.34
		var eye_offset_y = -ry * 0.08
		var eye_w = rx * 0.24

		var left_eye = center_pos + Vector2(-eye_offset_x, eye_offset_y)
		var right_eye = center_pos + Vector2(eye_offset_x, eye_offset_y)

		if is_clearing:
			var sz = eye_w * 1.1
			draw_line(left_eye + Vector2(-sz, -sz), left_eye + Vector2(sz * 0.4, 0), Color(0.12, 0.12, 0.18), 2.2)
			draw_line(left_eye + Vector2(sz * 0.4, 0), left_eye + Vector2(-sz, sz), Color(0.12, 0.12, 0.18), 2.2)
			draw_line(right_eye + Vector2(sz, -sz), right_eye + Vector2(-sz * 0.4, 0), Color(0.12, 0.12, 0.18), 2.2)
			draw_line(right_eye + Vector2(-sz * 0.4, 0), right_eye + Vector2(sz, sz), Color(0.12, 0.12, 0.18), 2.2)
		else:
			var blink_phase = (col * 2.7 + row * 1.9) if (col >= 0 and row >= 0) else 0.0
			var is_blinking = sin(game_time * 2.5 + blink_phase) > 0.94

			if is_blinking:
				draw_arc(left_eye + Vector2(0, 1), eye_w * 0.9, PI * 0.1, PI * 0.9, 8, Color(0.12, 0.12, 0.18), 2.0)
				draw_arc(right_eye + Vector2(0, 1), eye_w * 0.9, PI * 0.1, PI * 0.9, 8, Color(0.12, 0.12, 0.18), 2.0)
			else:
				draw_circle(left_eye + Vector2(0, 0.5), eye_w + 0.8, Color(0.12, 0.14, 0.20))
				draw_circle(right_eye + Vector2(0, 0.5), eye_w + 0.8, Color(0.12, 0.14, 0.20))
				draw_circle(left_eye, eye_w, Color.WHITE)
				draw_circle(right_eye, eye_w, Color.WHITE)

				var pupil_r = eye_w * 0.55
				var look_offset = Vector2(0.5, 0.5)
				var left_pupil = left_eye + look_offset
				var right_pupil = right_eye + look_offset

				draw_circle(left_pupil, pupil_r, Color(0.10, 0.12, 0.18))
				draw_circle(right_pupil, pupil_r, Color(0.10, 0.12, 0.18))

				draw_circle(left_pupil + Vector2(-pupil_r * 0.35, -pupil_r * 0.35), pupil_r * 0.4, Color.WHITE)
				draw_circle(right_pupil + Vector2(-pupil_r * 0.35, -pupil_r * 0.35), pupil_r * 0.4, Color.WHITE)

func _draw_particles_and_rings() -> void:
	for r in active_rings:
		var alpha = r["life"] / r["max_life"]
		var col = Color(r["color"].r, r["color"].g, r["color"].b, alpha * 0.85)
		draw_arc(r["pos"], r["radius"], 0, TAU, 20, col, 2.2)

	for p in active_particles:
		var alpha = p["life"] / p["max_life"]
		var col = Color(p["color"].r, p["color"].g, p["color"].b, alpha)
		draw_circle(p["pos"], p["size"] * alpha, col)

## -------------------------------------------------------------
## 四角い石ブロック (お邪魔ぷよ) 描画
## -------------------------------------------------------------
func _draw_stone_block(center_pos: Vector2, size: float, is_clearing: bool = false, custom_scale: Vector2 = Vector2.ONE, col: int = -1, row: int = -1) -> void:
	var half_w = (size * 0.5 - 1.5) * custom_scale.x
	var half_h = (size * 0.5 - 1.5) * custom_scale.y

	# 1. 影 (ドロップシャドウ)
	var shadow_rect = Rect2(center_pos.x - half_w, center_pos.y - half_h + 2.5, half_w * 2.0, half_h * 2.0)
	draw_rect(shadow_rect, Color(0, 0, 0, 0.32))

	# 石の色設定
	var stone_dark = Color(0.24, 0.26, 0.32)       # 外枠・底面シャドウ
	var stone_body = Color(0.55, 0.58, 0.65)       # 石表面ベース
	var stone_light = Color(0.84, 0.88, 0.95)      # 上部面取りハイライト
	var stone_bevel_shadow = Color(0.34, 0.37, 0.44) # 下部面取り

	if is_clearing:
		if int(game_time * 24.0) % 2 == 0:
			stone_body = Color(0.96, 0.96, 1.0)
			stone_light = Color(1.0, 1.0, 1.0)

	# 2. 外枠・アンダーシャドウ
	var base_rect = Rect2(center_pos.x - half_w, center_pos.y - half_h, half_w * 2.0, half_h * 2.0)
	draw_rect(base_rect, stone_dark)

	# 3. メイン石ブロックボディ (少し内側)
	var inner_rect = Rect2(center_pos.x - half_w + 1.5, center_pos.y - half_h + 1.5, (half_w - 1.5) * 2.0, (half_h - 1.5) * 2.0)
	draw_rect(inner_rect, stone_body)

	# 4. 立体的な石の面取り (Bevel edges)
	# 上面・左面ハイライトライン
	draw_line(Vector2(inner_rect.position.x, inner_rect.position.y), Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y), stone_light, 1.8)
	draw_line(Vector2(inner_rect.position.x, inner_rect.position.y), Vector2(inner_rect.position.x, inner_rect.position.y + inner_rect.size.y), stone_light, 1.8)
	# 下面・右面シャドウライン
	draw_line(Vector2(inner_rect.position.x, inner_rect.position.y + inner_rect.size.y), Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y + inner_rect.size.y), stone_bevel_shadow, 1.8)
	draw_line(Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y), Vector2(inner_rect.position.x + inner_rect.size.x, inner_rect.position.y + inner_rect.size.y), stone_bevel_shadow, 1.8)

	# 5. 石の表面テクスチャ (彫り込みクラック & 斑点)
	var crack_pts: Array[Vector2] = [
		center_pos + Vector2(-half_w * 0.45, -half_h * 0.4),
		center_pos + Vector2(-half_w * 0.1, -half_h * 0.05),
		center_pos + Vector2(half_w * 0.15, -half_h * 0.3),
		center_pos + Vector2(half_w * 0.5, half_h * 0.45)
	]
	for i in range(crack_pts.size() - 1):
		draw_line(crack_pts[i], crack_pts[i+1], Color(0.18, 0.20, 0.25, 0.85), 1.6)
		draw_line(crack_pts[i] + Vector2(0.8, 0.8), crack_pts[i+1] + Vector2(0.8, 0.8), Color(0.88, 0.92, 0.98, 0.55), 1.0)

	# 小さな窪み
	draw_circle(center_pos + Vector2(-half_w * 0.35, half_h * 0.35), 1.5, Color(0.24, 0.27, 0.33, 0.75))
	draw_circle(center_pos + Vector2(half_w * 0.32, -half_h * 0.35), 1.2, Color(0.24, 0.27, 0.33, 0.75))
