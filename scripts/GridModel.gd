class_name GridModel
extends RefCounted

## 盤面データ: grid[col][row] (0 <= col < 6, 0 <= row < 13)
var grid: Array = []

func _init() -> void:
	clear()

## 盤面の初期化
func clear() -> void:
	grid.clear()
	for c in range(GameConstants.COLS):
		var col_arr: Array[int] = []
		for r in range(GameConstants.ROWS):
			col_arr.append(GameConstants.PuyoType.EMPTY)
		grid.append(col_arr)

## 座標が盤面内かチェック
func is_valid_coord(col: int, row: int) -> bool:
	return col >= 0 and col < GameConstants.COLS and row >= 0 and row < GameConstants.ROWS

## マスが空かチェック
func is_empty(col: int, row: int) -> bool:
	if not is_valid_coord(col, row):
		return false
	return grid[col][row] == GameConstants.PuyoType.EMPTY

## ぷよの種類を取得
func get_cell(col: int, row: int) -> int:
	if not is_valid_coord(col, row):
		return GameConstants.PuyoType.EMPTY
	return grid[col][row]

## ぷよの種類を設定
func set_cell(col: int, row: int, type: int) -> void:
	if is_valid_coord(col, row):
		grid[col][row] = type

## 窒息チェック（3列目の最上段が出現時に埋まっているか）
func is_choked() -> bool:
	# 3列目（インデックス2）の出現マス（row=1またはrow=0）が埋まっている場合
	return grid[GameConstants.SPAWN_COL][GameConstants.SPAWN_ROW_PIVOT] != GameConstants.PuyoType.EMPTY or \
		   grid[GameConstants.SPAWN_COL][GameConstants.SPAWN_ROW_CHILD] != GameConstants.PuyoType.EMPTY

## 自由落下（ちぎり落下）の実行
## 戻り値: 落下が発生した移動情報のアレイ [{col, from_row, to_row, type}]
func apply_gravity() -> Array:
	var drops: Array = []
	for c in range(GameConstants.COLS):
		var write_row = GameConstants.ROWS - 1
		# 下から上へ探索
		for r in range(GameConstants.ROWS - 1, -1, -1):
			var puyo = grid[c][r]
			if puyo != GameConstants.PuyoType.EMPTY:
				if r != write_row:
					drops.append({
						"col": c,
						"from_row": r,
						"to_row": write_row,
						"type": puyo
					})
					grid[c][write_row] = puyo
					grid[c][r] = GameConstants.PuyoType.EMPTY
				write_row -= 1
	return drops

## 連結消去の判定 (BFS)
## 戻り値: 消去情報辞書 {
##   "cleared_cells": [Vector2i, ...],
##   "groups": [[Vector2i, ...], ...],
##   "total_cleared": int,
##   "color_count": int,
##   "max_connect": int,
##   "cleared_types": Array[int]
## }
func check_and_clear_matches() -> Dictionary:
	var visited: Array = []
	for c in range(GameConstants.COLS):
		var v_col: Array[bool] = []
		for r in range(GameConstants.ROWS):
			v_col.append(false)
		visited.append(v_col)

	var all_cleared_cells: Array[Vector2i] = []
	var groups: Array = []
	var cleared_colors: Dictionary = {}
	var cell_types: Dictionary = {}
	var max_connect: int = 0

	for c in range(GameConstants.COLS):
		for r in range(GameConstants.ROWS):
			var type = grid[c][r]
			# 通常色ぷよのみ対象（EMPTYとお邪魔は探索起点にしない）
			if type == GameConstants.PuyoType.EMPTY or type == GameConstants.PuyoType.GARBAGE:
				continue
			if visited[c][r]:
				continue

			# BFS で同色グループを収集
			var group: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(c, r)]
			visited[c][r] = true

			while queue.size() > 0:
				var curr: Vector2i = queue.pop_front()
				group.append(curr)

				var neighbors = [
					Vector2i(curr.x + 1, curr.y),
					Vector2i(curr.x - 1, curr.y),
					Vector2i(curr.x, curr.y + 1),
					Vector2i(curr.x, curr.y - 1)
				]

				for n in neighbors:
					if is_valid_coord(n.x, n.y) and not visited[n.x][n.y]:
						if grid[n.x][n.y] == type:
							visited[n.x][n.y] = true
							queue.append(n)

			# 4個以上連結していれば消去対象
			if group.size() >= 4:
				groups.append(group)
				cleared_colors[type] = true
				if group.size() > max_connect:
					max_connect = group.size()
				for cell in group:
					all_cleared_cells.append(cell)
					cell_types[cell] = type

	# 該当セルを盤面から消去
	for cell in all_cleared_cells:
		grid[cell.x][cell.y] = GameConstants.PuyoType.EMPTY

	return {
		"has_cleared": all_cleared_cells.size() > 0,
		"cleared_cells": all_cleared_cells,
		"cell_types": cell_types,
		"groups": groups,
		"total_cleared": all_cleared_cells.size(),
		"color_count": cleared_colors.keys().size(),
		"max_connect": max_connect,
		"cleared_types": cleared_colors.keys()
	}

## 全マスが空かどうか（全消し判定）
func is_field_empty() -> bool:
	for c in range(GameConstants.COLS):
		for r in range(GameConstants.ROWS):
			if grid[c][r] != GameConstants.PuyoType.EMPTY:
				return false
	return true
