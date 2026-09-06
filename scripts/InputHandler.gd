class_name InputHandler
extends Node

## シグナル定義
signal move_left_pressed
signal move_right_pressed
signal rotate_left_pressed
signal rotate_right_pressed
signal hard_drop_pressed
signal pause_pressed

## 内部状態管理
enum MoveDir { NONE = 0, LEFT = -1, RIGHT = 1 }

var current_dir: MoveDir = MoveDir.NONE
var das_timer: float = 0.0
var arr_timer: float = 0.0
var is_das_active: bool = false

var is_enabled: bool = true

func _unhandled_input(event: InputEvent) -> void:
	if not is_enabled:
		return

	if event.is_action_pressed("pause"):
		pause_pressed.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("rotate_left"):
		rotate_left_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("rotate_right"):
		rotate_right_pressed.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hard_drop"):
		hard_drop_pressed.emit()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_enabled:
		return

	_update_horizontal_movement(delta)

func _update_horizontal_movement(delta: float) -> void:
	var left_pressed = Input.is_action_pressed("move_left")
	var right_pressed = Input.is_action_pressed("move_right")

	var target_dir = MoveDir.NONE
	if left_pressed and not right_pressed:
		target_dir = MoveDir.LEFT
	elif right_pressed and not left_pressed:
		target_dir = MoveDir.RIGHT
	elif left_pressed and right_pressed:
		# 両方押されている場合は最新の入力（既存の向きを維持）
		target_dir = current_dir if current_dir != MoveDir.NONE else MoveDir.RIGHT

	# 押下開始
	if target_dir != current_dir:
		current_dir = target_dir
		das_timer = 0.0
		arr_timer = 0.0
		is_das_active = false

		if current_dir == MoveDir.LEFT:
			move_left_pressed.emit()
		elif current_dir == MoveDir.RIGHT:
			move_right_pressed.emit()
	elif current_dir != MoveDir.NONE:
		# 長押し中
		if not is_das_active:
			das_timer += delta
			if das_timer >= GameConstants.DAS_DELAY:
				is_das_active = true
				arr_timer = 0.0
		else:
			arr_timer += delta
			while arr_timer >= GameConstants.ARR_INTERVAL:
				arr_timer -= GameConstants.ARR_INTERVAL
				if current_dir == MoveDir.LEFT:
					move_left_pressed.emit()
				elif current_dir == MoveDir.RIGHT:
					move_right_pressed.emit()

func is_soft_dropping() -> bool:
	if not is_enabled:
		return false
	return Input.is_action_pressed("soft_drop")

func reset_state() -> void:
	current_dir = MoveDir.NONE
	das_timer = 0.0
	arr_timer = 0.0
	is_das_active = false
