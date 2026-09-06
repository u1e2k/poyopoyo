class_name PuyoAI
extends RefCounted

## AI 難易度設定
enum Difficulty { EASY, NORMAL, HARD }

var difficulty: Difficulty = Difficulty.NORMAL

## AI思考ルーチン
## 最適なターゲット { "col": int, "rot": int } を算出
func evaluate_best_move(grid_model: GridModel, pivot_type: int, child_type: int) -> Dictionary:
	var best_score: float = -999999.0
	var best_move: Dictionary = { "col": 2, "rot": GameConstants.Direction.UP }

	var valid_moves: Array = []

	# 全ての配置候補 (列 0〜5 × 向き 0〜3) を探索
	for col in range(GameConstants.COLS):
		for rot in [
			GameConstants.Direction.UP,
			GameConstants.Direction.RIGHT,
			GameConstants.Direction.DOWN,
			GameConstants.Direction.LEFT
		]:
			var sim_result = _simulate_placement(grid_model, col, rot, pivot_type, child_type)
			if sim_result["valid"]:
				var score = _score_board(sim_result["grid_model"], sim_result["chain_count"], sim_result["cleared_count"])
				# 難易度に応じたランダムノイズ
				if difficulty == Difficulty.EASY:
					score += randf_range(-40.0, 40.0)
				elif difficulty == Difficulty.NORMAL:
					score += randf_range(-10.0, 10.0)

				valid_moves.append({ "col": col, "rot": rot, "score": score })
				if score > best_score:
					best_score = score
					best_move = { "col": col, "rot": rot }

	if valid_moves.size() == 0:
		return { "col": 2, "rot": GameConstants.Direction.UP }

	return best_move

## 盤面シミュレーション
func _simulate_placement(original_grid: GridModel, col: int, rot: int, pivot_type: int, child_type: int) -> Dictionary:
	var sim_grid = GridModel.new()
	# 盤面コピー
	for c in range(GameConstants.COLS):
		for r in range(GameConstants.ROWS):
			sim_grid.set_cell(c, r, original_grid.get_cell(c, r))

	var offset = GameConstants.DIR_OFFSETS[rot]
	var p_col = col
	var c_col = col + offset.x

	# 枠外チェック
	if p_col < 0 or p_col >= GameConstants.COLS or c_col < 0 or c_col >= GameConstants.COLS:
		return { "valid": false }

	# 最上段が既に埋まっているかチェック
	if not sim_grid.is_empty(p_col, 1) or not sim_grid.is_empty(c_col, 1):
		return { "valid": false }

	# 軸ぷよと回転ぷよの着地位置を計算
	var p_row = 1
	while p_row + 1 < GameConstants.ROWS and sim_grid.is_empty(p_col, p_row + 1):
		p_row += 1

	var c_row = 1
	while c_row + 1 < GameConstants.ROWS and sim_grid.is_empty(c_col, c_row + 1):
		c_row += 1

	# 上下配置の場合の重なり補正
	if p_col == c_col:
		if rot == GameConstants.Direction.UP:
			# 子が上、軸が下
			sim_grid.set_cell(p_col, p_row, pivot_type)
			if p_row - 1 >= 0:
				sim_grid.set_cell(c_col, p_row - 1, child_type)
			else:
				return { "valid": false }
		elif rot == GameConstants.Direction.DOWN:
			# 軸が上、子が下
			sim_grid.set_cell(c_col, c_row, child_type)
			if c_row - 1 >= 0:
				sim_grid.set_cell(p_col, c_row - 1, pivot_type)
			else:
				return { "valid": false }
	else:
		sim_grid.set_cell(p_col, p_row, pivot_type)
		sim_grid.set_cell(c_col, c_row, child_type)

	# 自由落下
	sim_grid.apply_gravity()

	# 連鎖・消去シミュレーション
	var chain_count = 0
	var total_cleared = 0
	while true:
		var match_res = sim_grid.check_and_clear_matches()
		if match_res["has_cleared"]:
			chain_count += 1
			total_cleared += match_res["total_cleared"]
			sim_grid.apply_gravity()
		else:
			break

	return {
		"valid": true,
		"grid_model": sim_grid,
		"chain_count": chain_count,
		"cleared_count": total_cleared
	}

## 盤面評価スコア計算
func _score_board(grid: GridModel, chain_count: int, cleared_count: int) -> float:
	var score: float = 0.0

	# 1. 連鎖評価 (連鎖が発生すれば非常に高い評価)
	if chain_count >= 2:
		score += chain_count * 120.0 + cleared_count * 10.0
	elif chain_count == 1:
		# 単発消去は連鎖タネを崩す可能性があるので控えめの評価
		score += 15.0

	# 2. 窒息マス（3列目最上段付近）の高さペナルティ
	for r in range(0, 5):
		if grid.get_cell(GameConstants.SPAWN_COL, r) != GameConstants.PuyoType.EMPTY:
			score -= (5 - r) * 35.0

	# 3. 各列の高さと平坦度評価
	var heights: Array[int] = []
	for c in range(GameConstants.COLS):
		var h = 0
		for r in range(1, GameConstants.ROWS):
			if grid.get_cell(c, r) != GameConstants.PuyoType.EMPTY:
				h = GameConstants.ROWS - r
				break
		heights.append(h)
		# 高すぎる列へのペナルティ
		if h >= 10:
			score -= (h - 9) * 20.0

	# 隣り合う列の高低差ペナルティ（滑らかな階段状・平坦が望ましい）
	for c in range(GameConstants.COLS - 1):
		var diff = abs(heights[c] - heights[c + 1])
		if diff >= 3:
			score -= diff * 4.0

	# 4. 同色の連結（2連結・3連結）ボーナス（連鎖タネの構築）
	var visited: Array = []
	for c in range(GameConstants.COLS):
		var col_v: Array[bool] = []
		for r in range(GameConstants.ROWS):
			col_v.append(false)
		visited.append(col_v)

	for c in range(GameConstants.COLS):
		for r in range(1, GameConstants.ROWS):
			var type = grid.get_cell(c, r)
			if type == GameConstants.PuyoType.EMPTY or type == GameConstants.PuyoType.GARBAGE or visited[c][r]:
				continue

			var count = 0
			var queue = [Vector2i(c, r)]
			visited[c][r] = true

			while queue.size() > 0:
				var curr = queue.pop_front()
				count += 1
				var neighbors = [
					Vector2i(curr.x + 1, curr.y),
					Vector2i(curr.x - 1, curr.y),
					Vector2i(curr.x, curr.y + 1),
					Vector2i(curr.x, curr.y - 1)
				]
				for n in neighbors:
					if grid.is_valid_coord(n.x, n.y) and not visited[n.x][n.y]:
						if grid.get_cell(n.x, n.y) == type:
							visited[n.x][n.y] = true
							queue.append(n)

			if count == 2:
				score += 6.0
			elif count == 3:
				score += 16.0

	return score
