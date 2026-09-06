class_name PauseMenu
extends Control

signal resume_requested
signal retry_requested
signal title_requested

@onready var resume_button: Button = $Panel/VBoxContainer/ResumeButton
@onready var retry_button: Button = $Panel/VBoxContainer/RetryButton
@onready var title_button: Button = $Panel/VBoxContainer/TitleButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# ボタン接続
	resume_button.pressed.connect(_on_resume_pressed)
	retry_button.pressed.connect(_on_retry_pressed)
	title_button.pressed.connect(_on_title_pressed)

	# フォーカスループ設定
	resume_button.focus_neighbor_top = resume_button.get_path_to(title_button)
	resume_button.focus_neighbor_bottom = resume_button.get_path_to(retry_button)

	retry_button.focus_neighbor_top = retry_button.get_path_to(resume_button)
	retry_button.focus_neighbor_bottom = retry_button.get_path_to(title_button)

	title_button.focus_neighbor_top = title_button.get_path_to(retry_button)
	title_button.focus_neighbor_bottom = title_button.get_path_to(resume_button)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		_on_resume_pressed()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	visible = true
	get_tree().paused = true
	# 次のフレームまたは即時にRESUMEボタンへフォーカス
	resume_button.call_deferred("grab_focus")

func close_menu() -> void:
	visible = false
	get_tree().paused = false

func _on_resume_pressed() -> void:
	close_menu()
	resume_requested.emit()

func _on_retry_pressed() -> void:
	close_menu()
	retry_requested.emit()

func _on_title_pressed() -> void:
	close_menu()
	title_requested.emit()
