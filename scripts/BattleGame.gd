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

	# 入力ハンドラー
	input_handler = InputHandler.new()
	add_child(input_handler)

	input_handler.move_left_pressed.connect(_on_p1_move_left)
	input_handler.move_right_pressed.connect(_on_p1_move_right)
	input_handler.rotate_left_pressed.connect(_on_p1_rotate_left)
	input_handler.rotate_right_pressed.connect(_on_p1_rotate_right)
	input_handler.hard_drop_pressed.connect(_on_p1_hard_drop)
	input_handler.pause_pressed.connect(_on_pause_requested)

	# プレイヤー生成
	p1 = BattlePlayer.new()
	p1.player_type = BattlePlayer.PlayerType.HUMAN
	add_child(p1)

	p2 = BattlePlayer.new()
	p2.player_type = BattlePlayer.PlayerType.CPU
	add_child(p2)

	p1.garbage_sent.connect(_on_p1_send_garbage)
	p2.garbage_sent.connect(_on_p2_send_garbage)

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

func _process(delta: float) -> void:
	if not get_tree().paused:
		game_time += delta
		if banner_timer > 0.0:
			banner_timer -= delta

		if is_game_active:
			p1.process_turn(delta)
			p2.process_turn(delta)

	queue_redraw()

func start_match() -> void:
	result_panel.visible = false
	banner_text = ""
	banner_timer = 0.0
	is_game_active = true
	input_handler.is_enabled = true
	input_handler.reset_state()

	p1.init_game()
	p2.init_game()

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
		_show_banner("1P: %d GARBAGE!" % amount)

func _on_p2_send_garbage(amount: int) -> void:
	if p2.pending_garbage > 0:
		var offset = min(p2.pending_garbage, amount)
		p2.pending_garbage -= offset
		amount -= offset

	if amount > 0:
		p1.pending_garbage += amount
		_show_banner("CPU: %d GARBAGE!" % amount)

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
	_show_result("YOU LOSE...", Color(0.96, 0.26, 0.35))

func _on_p2_died() -> void:
	if not is_game_active:
		return
	is_game_active = false
	p1_wins += 1
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
	if is_game_active:
		p1.move_left()

func _on_p1_move_right() -> void:
	if is_game_active:
		p1.move_right()

func _on_p1_rotate_left() -> void:
	if is_game_active:
		p1.rotate_left()

func _on_p1_rotate_right() -> void:
	if is_game_active:
		p1.rotate_right()

func _on_p1_hard_drop() -> void:
	if is_game_active:
		p1.hard_drop()

func _on_pause_requested() -> void:
	if is_game_active:
		pause_menu.open_menu()

func _on_pause_resume() -> void:
	pass

func _on_back_to_title() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

## -------------------------------------------------------------
## 描画 (2画面対戦レイアウト)
## -------------------------------------------------------------
func _draw() -> void:
	# 全体背景
	draw_rect(Rect2(0, 0, 720, 720), GameConstants.COLOR_BG)

	# 上部ヘッダー
	draw_rect(Rect2(0, 0, 720, 50), Color(0.06, 0.07, 0.10))
	draw_line(Vector2(0, 50), Vector2(720, 50), GameConstants.COLOR_PANEL_BORDER, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(24, 32), "1P (YOU)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GameConstants.COLOR_TEXT_PRIMARY)
	draw_string(ThemeDB.fallback_font, Vector2(310, 32), "VS CPU", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, GameConstants.COLOR_TEXT_ACCENT)
	draw_string(ThemeDB.fallback_font, Vector2(610, 32), "CPU (AI)", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.96, 0.40, 0.45))

	# 勝敗数表示
	var win_str = "%d  -  %d" % [p1_wins, cpu_wins]
	draw_string(ThemeDB.fallback_font, Vector2(330, 80), win_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, GameConstants.COLOR_TEXT_PRIMARY)

	# 1Pフィールド描画
	_draw_player_field(p1, P1_FIELD_X, P1_FIELD_Y, "1P FIELD")
	# CPUフィールド描画
	_draw_player_field(p2, P2_FIELD_X, P2_FIELD_Y, "CPU FIELD")

	# 中央情報 (NEXT & お邪魔予告)
	_draw_center_info()

	# バナー描画
	if banner_timer > 0.0 and banner_text != "":
		var alpha = min(1.0, banner_timer / 0.3)
		var center_rect = Rect2(200, 320, 320, 50)
		draw_rect(center_rect, Color(0.05, 0.08, 0.15, 0.9 * alpha))
		draw_rect(center_rect, Color(0.98, 0.82, 0.15, alpha), false, 2.0)
		draw_string(ThemeDB.fallback_font, Vector2(210, 352), banner_text, HORIZONTAL_ALIGNMENT_CENTER, 300, 20, Color(1, 0.95, 0.4, alpha))

	# 下部操作ガイド
	draw_string(ThemeDB.fallback_font, Vector2(0, 690), "D-Pad: Move / Down: Drop / A, B: Rotate / START: Pause", HORIZONTAL_ALIGNMENT_CENTER, 720, 14, GameConstants.COLOR_TEXT_MUTED)

func _draw_player_field(pl: BattlePlayer, fx: float, fy: float, label: String) -> void:
	# フィールド背景
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
	draw_line(Vector2(choke_x, fy), Vector2(choke_x + CELL_SIZE, fy), Color(0.96, 0.26, 0.35, 0.8), 2.5)

	# 確定ぷよ描画 (落下完了済み)
	for c in range(GameConstants.COLS):
		for r in range(1, GameConstants.ROWS):
			var type = pl.grid_model.get_cell(c, r)
			if type != GameConstants.PuyoType.EMPTY:
				var center = Vector2(fx + (c + 0.5) * CELL_SIZE, fy + (r - 1 + 0.5) * CELL_SIZE)
				var is_clearing = false
				if pl.current_state == BattlePlayer.State.CLEAR_ANIM and pl.last_cleared_info.has("cleared_cells"):
					if Vector2i(c, r) in pl.last_cleared_info["cleared_cells"]:
						is_clearing = true
				_draw_mini_puyo(center, type, is_clearing)

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
	# 1P NEXT
	draw_string(ThemeDB.fallback_font, Vector2(235, 120), "1P NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GameConstants.COLOR_TEXT_PRIMARY)
	var n1_box = Rect2(230, 130, 75, 120)
	draw_rect(n1_box, GameConstants.COLOR_PANEL_BG)
	draw_rect(n1_box, GameConstants.COLOR_PANEL_BORDER, false, 1.5)
	if p1.next_queue.size() > 0:
		var n = p1.next_queue[0]
		_draw_mini_puyo(Vector2(267, 165), n["child"])
		_draw_mini_puyo(Vector2(267, 205), n["pivot"])

	# CPU NEXT
	draw_string(ThemeDB.fallback_font, Vector2(415, 120), "CPU NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.96, 0.40, 0.45))
	var n2_box = Rect2(415, 130, 75, 120)
	draw_rect(n2_box, GameConstants.COLOR_PANEL_BG)
	draw_rect(n2_box, GameConstants.COLOR_PANEL_BORDER, false, 1.5)
	if p2.next_queue.size() > 0:
		var n2 = p2.next_queue[0]
		_draw_mini_puyo(Vector2(452, 165), n2["child"])
		_draw_mini_puyo(Vector2(452, 205), n2["pivot"])

func _draw_mini_puyo(center_pos: Vector2, type: int, is_clearing: bool = false) -> void:
	if type == GameConstants.PuyoType.EMPTY:
		return

	var base_col = GameConstants.PUYO_COLORS.get(type, Color.WHITE)
	var shadow_col = GameConstants.PUYO_SHADOW_COLORS.get(type, Color(0.2, 0.2, 0.2))
	var highlight_col = GameConstants.PUYO_HIGHLIGHT_COLORS.get(type, Color.WHITE)

	var r = (CELL_SIZE / 2.0) - 1.5
	if is_clearing:
		base_col = Color.WHITE
		r *= 1.1

	# ドロップシャドウ
	draw_circle(center_pos + Vector2(0, 2), r * 0.9, Color(0, 0, 0, 0.25))

	# 外枠/シャドウ
	draw_circle(center_pos, r, shadow_col)

	# メインボディ
	draw_circle(center_pos + Vector2(0, -1), r - 1.0, base_col)

	# グロス光沢
	draw_circle(center_pos + Vector2(-r * 0.35, -r * 0.35), r * 0.3, Color(1, 1, 1, 0.8))

	# 目
	if type != GameConstants.PuyoType.GARBAGE and not is_clearing:
		var eye_w = r * 0.25
		var left_eye = center_pos + Vector2(-r * 0.35, -r * 0.05)
		var right_eye = center_pos + Vector2(r * 0.35, -r * 0.05)

		draw_circle(left_eye, eye_w, Color.WHITE)
		draw_circle(right_eye, eye_w, Color.WHITE)
		draw_circle(left_eye + Vector2(0.5, 0.5), eye_w * 0.6, Color(0.1, 0.1, 0.15))
		draw_circle(right_eye + Vector2(0.5, 0.5), eye_w * 0.6, Color(0.1, 0.1, 0.15))
