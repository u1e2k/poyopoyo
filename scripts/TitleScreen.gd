class_name TitleScreen
extends Control

@onready var start_button: Button = $VBoxContainer/StartButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var hiscore_label: Label = $HiScoreLabel

var anim_time: float = 0.0

func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	start_button.focus_neighbor_top = start_button.get_path_to(quit_button)
	start_button.focus_neighbor_bottom = start_button.get_path_to(quit_button)
	quit_button.focus_neighbor_top = quit_button.get_path_to(start_button)
	quit_button.focus_neighbor_bottom = quit_button.get_path_to(start_button)

	start_button.call_deferred("grab_focus")
	_display_hiscore()

func _process(delta: float) -> void:
	anim_time += delta
	queue_redraw()

func _on_start_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/MainGame.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _display_hiscore() -> void:
	var hi_score = 0
	if FileAccess.file_exists(GameConstants.SAVE_PATH):
		var file = FileAccess.open(GameConstants.SAVE_PATH, FileAccess.READ)
		if file:
			var json_str = file.get_as_text()
			var data = JSON.parse_string(json_str)
			if data is Dictionary and data.has("hi_score"):
				hi_score = int(data["hi_score"])

	hiscore_label.text = "HI-SCORE: %07d" % hi_score

func _draw() -> void:
	draw_rect(Rect2(0, 0, 720, 720), GameConstants.COLOR_BG)

	# タイトル装飾用アニメーションぷよ
	var colors = [
		GameConstants.PuyoType.RED,
		GameConstants.PuyoType.GREEN,
		GameConstants.PuyoType.BLUE,
		GameConstants.PuyoType.YELLOW
	]

	for i in range(8):
		var x = 90 * i + 45
		var float_offset = sin(anim_time * 2.8 + i * 0.9) * 14.0
		var y = 620 + float_offset
		var p_type = colors[i % colors.size()]

		var base_col: Color = GameConstants.PUYO_COLORS[p_type]
		var shadow_col: Color = GameConstants.PUYO_SHADOW_COLORS[p_type]
		var highlight_col: Color = GameConstants.PUYO_HIGHLIGHT_COLORS[p_type]

		var r = 26.0
		var breath = sin(anim_time * 5.0 + i * 1.2) * 0.05
		var rx = r * (1.0 + breath)
		var ry = r * (1.0 - breath)
		var center_pos = Vector2(x, y)

		# ドロップシャドウ
		draw_circle(center_pos + Vector2(0, 4.0), rx * 0.9, Color(0, 0, 0, 0.3))

		# 外枠/下部シャドウ
		draw_circle(center_pos, rx, shadow_col)

		# メインボディ
		draw_circle(center_pos + Vector2(0, -1.8), rx - 1.5, base_col)

		# 上部内側グロー
		var glow_col = highlight_col
		glow_col.a = 0.45
		draw_circle(center_pos + Vector2(0, -ry * 0.35), rx * 0.65, glow_col)

		# 下部リムライト
		var rim_col = highlight_col
		rim_col.a = 0.35
		draw_circle(center_pos + Vector2(0, ry * 0.5), rx * 0.45, rim_col)

		# メイン・スペキュラハイライト
		var spec_pos = center_pos + Vector2(-rx * 0.38, -ry * 0.38)
		draw_circle(spec_pos, rx * 0.28, Color(1, 1, 1, 0.85))
		draw_circle(spec_pos + Vector2(-1, -1), rx * 0.14, Color(1, 1, 1, 0.95))

		# サブハイライト
		draw_circle(center_pos + Vector2(rx * 0.4, ry * 0.32), rx * 0.12, Color(1, 1, 1, 0.55))

		# 目 & まばたき
		var eye_offset_x = rx * 0.34
		var eye_offset_y = -ry * 0.08
		var eye_w = rx * 0.24

		var left_eye = center_pos + Vector2(-eye_offset_x, eye_offset_y)
		var right_eye = center_pos + Vector2(eye_offset_x, eye_offset_y)

		var is_blinking = sin(anim_time * 2.2 + i * 1.7) > 0.93
		if is_blinking:
			draw_arc(left_eye + Vector2(0, 1), eye_w * 0.9, PI * 0.1, PI * 0.9, 8, Color(0.12, 0.12, 0.18), 2.2)
			draw_arc(right_eye + Vector2(0, 1), eye_w * 0.9, PI * 0.1, PI * 0.9, 8, Color(0.12, 0.12, 0.18), 2.2)
		else:
			draw_circle(left_eye + Vector2(0, 0.5), eye_w + 1.0, Color(0.12, 0.14, 0.20))
			draw_circle(right_eye + Vector2(0, 0.5), eye_w + 1.0, Color(0.12, 0.14, 0.20))
			draw_circle(left_eye, eye_w, Color.WHITE)
			draw_circle(right_eye, eye_w, Color.WHITE)

			var pupil_r = eye_w * 0.55
			draw_circle(left_eye, pupil_r, Color(0.10, 0.12, 0.18))
			draw_circle(right_eye, pupil_r, Color(0.10, 0.12, 0.18))

			# キャッチライト
			draw_circle(left_eye + Vector2(-pupil_r * 0.35, -pupil_r * 0.35), pupil_r * 0.4, Color.WHITE)
			draw_circle(right_eye + Vector2(-pupil_r * 0.35, -pupil_r * 0.35), pupil_r * 0.4, Color.WHITE)
			draw_circle(left_eye + Vector2(pupil_r * 0.3, pupil_r * 0.3), pupil_r * 0.2, Color.WHITE)
			draw_circle(right_eye + Vector2(pupil_r * 0.3, pupil_r * 0.3), pupil_r * 0.2, Color.WHITE)
