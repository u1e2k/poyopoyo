class_name GameConstants
extends RefCounted

## フィールド & 画面レイアウト定数
const SCREEN_WIDTH: float = 720.0
const SCREEN_HEIGHT: float = 720.0

const COLS: int = 6
const ROWS: int = 13  # 0行目: 出現/窒息枠（非表示または枠外）、1〜12行目: 表示盤面
const VISIBLE_ROWS: int = 12
const CELL_SIZE: float = 48.0

const FIELD_X: float = 216.0  # (720 - 288) / 2 = 216
const FIELD_Y: float = 48.0   # 上マージン48px
const FIELD_WIDTH: float = 288.0   # 6 * 48
const FIELD_HEIGHT: float = 624.0  # 13 * 48 (表示は 12 * 48 = 576px, 上部1マス48px)

# ツモの初期出現位置 (0-indexed: 3列目=2, 軸ぷよ=1段目, 回転ぷよ=0段目)
const SPAWN_COL: int = 2
const SPAWN_ROW_PIVOT: int = 1
const SPAWN_ROW_CHILD: int = 0

## ぷよの種類
enum PuyoType {
	EMPTY = 0,
	RED = 1,
	GREEN = 2,
	BLUE = 3,
	YELLOW = 4,
	GARBAGE = 5
}

## ぷよの回転方向 (軸ぷよに対する子ぷよの位置)
enum Direction {
	UP = 0,     # 上 (0, -1)
	RIGHT = 1,  # 右 (1, 0)
	DOWN = 2,   # 下 (0, 1)
	LEFT = 3    # 左 (-1, 0)
}

## 方向オフセット (Vector2i(col_offset, row_offset))
const DIR_OFFSETS = {
	Direction.UP: Vector2i(0, -1),
	Direction.RIGHT: Vector2i(1, 0),
	Direction.DOWN: Vector2i(0, 1),
	Direction.LEFT: Vector2i(-1, 0)
}

## カラーパレット (ジェリー質感・多層シェーディング用)
const PUYO_COLORS = {
	PuyoType.EMPTY: Color(0, 0, 0, 0),
	PuyoType.RED: Color(0.96, 0.22, 0.32),       # ベース
	PuyoType.GREEN: Color(0.18, 0.85, 0.40),     # ベース
	PuyoType.BLUE: Color(0.16, 0.58, 0.98),      # ベース
	PuyoType.YELLOW: Color(0.99, 0.82, 0.12),    # ベース
	PuyoType.GARBAGE: Color(0.72, 0.76, 0.84)    # ベース
}

const PUYO_SHADOW_COLORS = {
	PuyoType.EMPTY: Color(0, 0, 0, 0),
	PuyoType.RED: Color(0.65, 0.08, 0.16),
	PuyoType.GREEN: Color(0.08, 0.52, 0.22),
	PuyoType.BLUE: Color(0.08, 0.32, 0.68),
	PuyoType.YELLOW: Color(0.78, 0.54, 0.05),
	PuyoType.GARBAGE: Color(0.45, 0.48, 0.55)
}

const PUYO_HIGHLIGHT_COLORS = {
	PuyoType.EMPTY: Color(0, 0, 0, 0),
	PuyoType.RED: Color(1.0, 0.50, 0.58),
	PuyoType.GREEN: Color(0.55, 0.98, 0.68),
	PuyoType.BLUE: Color(0.52, 0.80, 1.0),
	PuyoType.YELLOW: Color(1.0, 0.95, 0.55),
	PuyoType.GARBAGE: Color(0.90, 0.92, 0.96)
}

## UI/背景テーマカラー
const COLOR_BG = Color(0.08, 0.09, 0.13)
const COLOR_FIELD_BG = Color(0.12, 0.14, 0.20, 0.95)
const COLOR_FIELD_BORDER = Color(0.35, 0.40, 0.55)
const COLOR_GRID_LINE = Color(1.0, 1.0, 1.0, 0.05)
const COLOR_PANEL_BG = Color(0.14, 0.16, 0.24, 0.85)
const COLOR_PANEL_BORDER = Color(0.28, 0.33, 0.46)
const COLOR_TEXT_PRIMARY = Color(0.95, 0.96, 1.0)
const COLOR_TEXT_ACCENT = Color(0.98, 0.82, 0.15)
const COLOR_TEXT_MUTED = Color(0.55, 0.60, 0.72)

## タイマー & レスポンス定数 (秒)
const DAS_DELAY: float = 0.18       # 長押し判定ディレイ
const ARR_INTERVAL: float = 0.033   # 連続移動間隔
const SOFT_DROP_INTERVAL: float = 0.04
const BASE_FALL_INTERVAL: float = 0.75
const LOCK_DELAY: float = 0.5
const CLEAR_ANIM_DURATION: float = 0.35
const DROP_ANIM_DURATION: float = 0.16

## スコア計算テーブル (ぷよぷよ通準拠)
const CHAIN_POWERS = [0, 0, 8, 16, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 480, 512]
const CONNECT_BONUS = [0, 0, 0, 0, 0, 2, 3, 4, 5, 6, 7, 10]  # 4個連結=0, 5個=2, 6個=3... 11個以上=10
const COLOR_BONUS = [0, 0, 3, 6, 12, 24]  # 1色=0, 2色=3, 3色=6, 4色=12

## 保存ファイルパス
const SAVE_PATH = "user://highscore.save"

## デモモードフラグ (CPU vs CPU)
static var is_demo_mode: bool = false

