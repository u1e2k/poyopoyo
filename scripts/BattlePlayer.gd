class_name BattlePlayer
extends Node

signal garbage_sent(amount: int)
signal player_died

enum PlayerType { HUMAN, CPU }
enum State {
	SPAWN,
	FALLING,
	LOCKING,
	DROP_FREE,
	CLEAR_ANIM,
	MATCH_CHECK,
	GARBAGE_DROP,
	GAME_OVER
}

var player_type: PlayerType = PlayerType.HUMAN
var current_state: State = State.SPAWN

var grid_model: GridModel
var ai: PuyoAI

# 操作中ツモ
var pivot_pos: Vector2i = Vector2i(GameConstants.SPAWN_COL, GameConstants.SPAWN_ROW_PIVOT)
var child_dir: int = GameConstants.Direction.UP
var pivot_type: int = GameConstants.PuyoType.EMPTY
var child_type: int = GameConstants.PuyoType.EMPTY

# NEXTキュー
var next_queue: Array = []

# お邪魔ぷよ管理
var pending_garbage: int = 0      # 相手から送られて保留中のお邪魔ぷよ数
var total_chain_score: int = 0   # 1連鎖中の累積獲得スコア
var current_chain: int = 0
var max_chain: int = 0
var score: int = 0

# タイマー
var fall_timer: float = 0.0
var lock_timer: float = 0.0
var state_timer: float = 0.0
var is_grounded: bool = false

# CPU AI操作用
var target_col: int = 2
var target_rot: int = GameConstants.Direction.UP
var ai_action_timer: float = 0.0
var ai_decision_made: bool = false

# アニメーション用
var last_cleared_info: Dictionary = {}
var clear_anim_progress: float = 0.0
var is_alive: bool = true

func _ready() -> void:
	grid_model = GridModel.new()
	if player_type == PlayerType.CPU:
		ai = PuyoAI.new()

func init_game() -> void:
	grid_model.clear()
	score = 0
	current_chain = 0
	max_chain = 0
	pending_garbage = 0
	total_chain_score = 0
	is_alive = true

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

func process_turn(delta: float) -> void:
	if not is_alive:
		return

	match current_state:
		State.FALLING, State.LOCKING:
			if player_type == PlayerType.CPU:
				_process_cpu_ai(delta)
			_process_falling(delta)
		State.DROP_FREE:
			_process_drop_free(delta)
		State.CLEAR_ANIM:
			_process_clear_anim(delta)
		State.GARBAGE_DROP:
			_process_garbage_drop(delta)

func _transition_to_spawn() -> void:
	current_state = State.SPAWN

	if grid_model.is_choked():
		_die()
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
	total_chain_score = 0

	# CPUのターゲット手決定
	if player_type == PlayerType.CPU:
		var best_move = ai.evaluate_best_move(grid_model, pivot_type, child_type)
		target_col = best_move["col"]
		target_rot = best_move["rot"]
		ai_action_timer = 0.0
		ai_decision_made = true

	_update_grounded_state()
	current_state = State.FALLING

func _process_falling(delta: float) -> void:
	var fall_speed = GameConstants.BASE_FALL_INTERVAL
	fall_timer += delta

	if fall_timer >= fall_speed:
		fall_timer = 0.0
		if _can_move(pivot_pos + Vector2i(0, 1), child_dir):
			pivot_pos.y += 1
			_update_grounded_state()
		else:
			is_grounded = true

	_update_grounded_state()
	if is_grounded:
		current_state = State.LOCKING
		lock_timer += delta
		if lock_timer >= GameConstants.LOCK_DELAY:
			_lock_active_pair()
	else:
		current_state = State.FALLING
		lock_timer = 0.0

func _process_cpu_ai(delta: float) -> void:
	ai_action_timer += delta
	# 0.08秒ごとに1ステップ操作（人間らしいスムーズな動作）
	if ai_action_timer >= 0.08:
		ai_action_timer = 0.0

		# 回転操作
		if child_dir != target_rot:
			rotate_right()
			return

		# 左右移動操作
		if pivot_pos.x < target_col:
			move_right()
		elif pivot_pos.x > target_col:
			move_left()
		else:
			# 目標位置に到達したら少し加速（ソフトドロップ相当）
			if _can_move(pivot_pos + Vector2i(0, 1), child_dir):
				pivot_pos.y += 1
				_update_grounded_state()

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

func move_left() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	if _can_move(pivot_pos + Vector2i(-1, 0), child_dir):
		pivot_pos.x -= 1
		_reset_lock_timer()
		_update_grounded_state()

func move_right() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	if _can_move(pivot_pos + Vector2i(1, 0), child_dir):
		pivot_pos.x += 1
		_reset_lock_timer()
		_update_grounded_state()

func rotate_right() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	var new_dir = (child_dir + 1) % 4
	_try_rotate(new_dir)

func rotate_left() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	var new_dir = (child_dir + 3) % 4
	_try_rotate(new_dir)

func _try_rotate(target_dir: int) -> void:
	if _can_move(pivot_pos, target_dir):
		child_dir = target_dir
		_reset_lock_timer()
		_update_grounded_state()
		return

	if _can_move(pivot_pos + Vector2i(-1, 0), target_dir):
		pivot_pos.x -= 1
		child_dir = target_dir
		_reset_lock_timer()
		_update_grounded_state()
		return

	if _can_move(pivot_pos + Vector2i(1, 0), target_dir):
		pivot_pos.x += 1
		child_dir = target_dir
		_reset_lock_timer()
		_update_grounded_state()
		return

	if _can_move(pivot_pos + Vector2i(0, -1), target_dir):
		pivot_pos.y -= 1
		child_dir = target_dir
		_reset_lock_timer()
		_update_grounded_state()
		return

func hard_drop() -> void:
	if current_state != State.FALLING and current_state != State.LOCKING:
		return
	while _can_move(pivot_pos + Vector2i(0, 1), child_dir):
		pivot_pos.y += 1
		score += 2
	_lock_active_pair()

func _reset_lock_timer() -> void:
	if is_grounded:
		lock_timer = min(lock_timer, GameConstants.LOCK_DELAY * 0.5)

func _lock_active_pair() -> void:
	var child_pos = pivot_pos + GameConstants.DIR_OFFSETS[child_dir]
	grid_model.set_cell(pivot_pos.x, pivot_pos.y, pivot_type)
	grid_model.set_cell(child_pos.x, child_pos.y, child_type)

	pivot_type = GameConstants.PuyoType.EMPTY
	child_type = GameConstants.PuyoType.EMPTY

	_start_drop_free()

func _start_drop_free() -> void:
	current_state = State.DROP_FREE
	var drops = grid_model.apply_gravity()
	if drops.size() > 0:
		state_timer = 0.0
	else:
		_start_match_check()

func _process_drop_free(delta: float) -> void:
	state_timer += delta
	if state_timer >= GameConstants.DROP_ANIM_DURATION:
		_start_match_check()

func _start_match_check() -> void:
	current_state = State.MATCH_CHECK
	var match_result = grid_model.check_and_clear_matches()

	if match_result["has_cleared"]:
		current_chain += 1
		if current_chain > max_chain:
			max_chain = current_chain

		var gained = _calculate_score(match_result)
		total_chain_score += gained
		score += gained

		last_cleared_info = match_result
		current_state = State.CLEAR_ANIM
		state_timer = 0.0
		clear_anim_progress = 0.0
	else:
		# 連鎖終了：獲得スコアに応じたお邪魔ぷよ数を計算して相手へ送信
		if total_chain_score > 0:
			var garbage_to_send = total_chain_score / 70  # 70点 = 1個
			if garbage_to_send > 0:
				garbage_sent.emit(garbage_to_send)
			total_chain_score = 0

		# 保留されているお邪魔ぷよがあれば落下処理
		if pending_garbage > 0:
			_start_garbage_drop()
		else:
			_transition_to_spawn()

func _process_clear_anim(delta: float) -> void:
	state_timer += delta
	clear_anim_progress = min(1.0, state_timer / 0.40)
	if state_timer >= 0.40:
		last_cleared_info.clear()
		_start_drop_free()

func _start_garbage_drop() -> void:
	current_state = State.GARBAGE_DROP
	state_timer = 0.0

	# 最大30個（5段分）ずつ落下
	var drop_amount = min(pending_garbage, 30)
	pending_garbage -= drop_amount

	# 列に均等に配置
	var cols_order = [0, 1, 2, 3, 4, 5]
	cols_order.shuffle()

	var placed = 0
	while placed < drop_amount:
		for c in cols_order:
			if placed >= drop_amount:
				break
			# 0段目（最上段）に配置
			if grid_model.is_empty(c, 0):
				grid_model.set_cell(c, 0, GameConstants.PuyoType.GARBAGE)
				placed += 1

	grid_model.apply_gravity()

func _process_garbage_drop(delta: float) -> void:
	state_timer += delta
	if state_timer >= 0.25:
		_transition_to_spawn()

func _calculate_score(info: Dictionary) -> int:
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

	return (10 * cleared_count) * total_multiplier

func _die() -> void:
	is_alive = false
	current_state = State.GAME_OVER
	player_died.emit()
