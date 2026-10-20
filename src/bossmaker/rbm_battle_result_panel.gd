extends Control
## 戦闘の結果の画面（3つの戦闘画面の OutcomeArea。2026-10-18 ユーザーの決定、比較の資料は prototypes/result_screens_2026-10-17/）。
## - 挑戦・TEST BATTLE は案C「シネマティック」: 上下の黒い帯が入る → 倒したボスが右で暗く沈む（負けた時は立ちはだかる）→
##   字間の広い大きな見出し（OutcomeLabel の「CLEAR」「DEFEAT」）→「○○を倒した！」→ 数字を1行 → 下の帯の右にボタン
##   （試作の文字だけのボタンは薄くて見づらかったため、挑戦トップと同じ枠付きのボタンを大きく明るく）。
## - クリアチェックは案A「王道RPG」: 大きな見出し（CLEAR! / FAILED…）が落ちる → 小見出し（OutcomeLabel の「クリアチェック成功／失敗」）
##   → 金の二重枠の「戦闘結果」の窓（「撃破ターン ……… 16」の行が1行ずつ出る）→ 味方が並ぶ →「▶」で選ぶメニュー。
## 呼び出し元（戦闘画面）は今までどおり OutcomeLabel・もう一度・戻るのボタンをこの子に足し、表示／非表示・文字・押した時の処理を
## 決める（ボタンの名前と処理は変えない）。この部品は位置・見た目・出方だけを受け持つ。戦闘の状態は読むだけで、進めない。

const Kit = preload("res://src/bossmaker/rbm_result_screen_kit.gd")
const S = Kit.S

const STYLE_CINEMATIC := "cinematic"
const STYLE_RPG := "rpg"
## 案Cの上下の黒い帯の高さ。
const BAR := 92.0
## 案Cのボスの絵を収める大きさ（右側）。
const BOSS_RECT := Rect2(760, 120, 460, 470)
## 案Aの味方の絵を収める大きさ。
const ALLY_SIZE := Vector2(56, 72)
## 絵の切り出しを前もって作り始めるまでのフレーム数（戦闘画面を開いた直後の重いフレームを避ける。PERFORMANCE.md §2.1）。
const WARM_DELAY_FRAMES := 30

var style := STYLE_CINEMATIC
## challenge / test / clear_check（出す行・文が少し違う）
var route := "challenge"
## 結果を出す時に読む情報を返す（context_for() の形）。
var context_fn: Callable

var _deco: Control
var _shown := false
var _generation := 0
var _warm_delay := -1
## 呼び出し元の文字・ボタン（作り直さない物）に付けた動き。消す時・出し直す時に止める。
var _tweens: Array[Tween] = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 金への再配色・枠の差し替え（RBMWorldUi.walk）を受けない（この画面は自分で見た目を持つ）
	set_meta("world_skip", true)

func _ready() -> void:
	set_process(false)

## 結果の画面に出す情報（戦闘画面から読むだけ）。
## won: 味方の勝ち / turns: 撃破ターン（負けた時は倒れたターン）/ clear_seconds: クリアタイム（勝利演出が測った時だけ。無ければ -1）/
## mode: SIMPLE・HARDCORE（分からなければ空）/ author: 制作者（空なら出さない）/ boss_name / boss_asset（今の絵。覚醒後なら覚醒後）/ party
static func context_for(view: Control, mode: String, author: String) -> Dictionary:
	var ctx := {"won": false, "turns": 0, "clear_seconds": -1.0, "mode": mode, "author": author, "boss_name": "", "boss_asset": "", "party": []}
	var session = view.get("session")
	if session == null or session.get("battle") == null:
		return ctx
	var battle: RBMBattle = session.battle
	ctx.won = battle.winner == "ally"
	ctx.turns = battle.current_turn
	ctx.boss_name = battle.boss.display_name if battle.boss != null else ""
	ctx.boss_asset = _boss_asset(view, battle)
	var party: Array = []
	for unit in battle.party:
		party.append(unit.character_id)
	ctx.party = party
	# 勝利演出が測った撃破ターン・クリアタイム（勝利の帯と同じ値）
	var encounter = view.get("_encounter")
	if bool(ctx.won) and is_instance_valid(encounter) and bool(encounter.active) and int(encounter.final_turn) > 0:
		ctx.turns = int(encounter.final_turn)
		ctx.clear_seconds = float(encounter.clear_seconds)
	return ctx

static func _boss_asset(view: Control, battle: RBMBattle) -> String:
	var row = view.get("_battlefield_ally_row")
	if is_instance_valid(row) and row.has_meta("visual_stage"):
		var stage = row.get_meta("visual_stage")
		if is_instance_valid(stage) and stage.get("_asset_ids") is Dictionary:
			var shown := str((stage.get("_asset_ids") as Dictionary).get("boss", ""))
			if not shown.is_empty():
				return shown
	var asset := RBMVisualAssets.boss_asset(str(view.get("_boss_appearance_id")))
	if battle.is_awakened and RBMVisualAssets.known(asset + RBMVisualAssets.AWAKENED_SUFFIX):
		asset += RBMVisualAssets.AWAKENED_SUFFIX
	return asset

## 結果の画面で使う絵（案C はボス、覚醒するボスは覚醒後も。案A は味方）を、戦闘中に裏で少しずつ作る（大きなボスの絵は
## 切り出しに 30ms 前後かかる。結果の画面を出す瞬間にも、戦闘を始める瞬間にも止まらないように。PERFORMANCE.md §2.1）。
## 戦闘を始める時に呼ぶ。作り始めるのは WARM_DELAY_FRAMES 後から、1フレームに1つ。表示専用。
func warm_up(view: Control) -> void:
	var session = view.get("session")
	if session == null or session.get("battle") == null:
		return
	var battle: RBMBattle = session.battle
	if style == STYLE_RPG:
		for unit in battle.party:
			Kit.request_fitted(unit.character_id, ALLY_SIZE)
	else:
		var base := RBMVisualAssets.boss_asset(str(view.get("_boss_appearance_id")))
		if base.is_empty():
			return
		Kit.request_fitted(base, BOSS_RECT.size)
		var awakened := RBMVisualAssets.awakened_asset_id(base)
		if not battle.awakening.is_empty() and RBMVisualAssets.known(awakened):
			Kit.request_fitted(awakened, BOSS_RECT.size)
	_warm_delay = WARM_DELAY_FRAMES
	set_process(true)

func _process(_delta: float) -> void:
	if _warm_delay > 0:
		_warm_delay -= 1
		return
	if not Kit.advance_fitted():
		set_process(false)

func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED:
		return
	# 自分の表示が切り替わった時だけ（画面ごと隠れて戻った時は、出した結果をそのまま見せる）
	if visible and not _shown:
		_shown = true
		# 呼び出し元は表示にしてから文字・ボタンを決めるので、同じフレームの終わりに組み立てる（その間は見せない）
		modulate.a = 0.0
		_present.call_deferred()
	elif not visible and _shown:
		_shown = false
		_clear()

func _clear() -> void:
	_generation += 1
	for tw in _tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_tweens.clear()
	for c in get_children():
		if c is Control and c != _deco:
			(c as Control).modulate.a = 1.0
			(c as Control).scale = Vector2.ONE
	var title := _title_label()
	if title != null:
		title.visible = true
	if is_instance_valid(_deco):
		remove_child(_deco)
		_deco.queue_free()
	_deco = null

func _present() -> void:
	if not visible or not _shown or not is_inside_tree():
		modulate.a = 1.0
		return
	_clear()
	var ctx: Dictionary = context_fn.call() if context_fn.is_valid() else {}
	_deco = Control.new()
	_deco.name = "ResultDecoration"
	_deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_deco)
	move_child(_deco, 0)
	_deco.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if style == STYLE_RPG:
		_present_rpg(ctx)
	else:
		_present_cinematic(ctx)
	modulate.a = 1.0

func _title_label() -> Label:
	return get_node_or_null("OutcomeLabel") as Label

## 今出しているボタン（並びは呼び出し元が足した順。先頭が主の操作）。
func visible_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for c in get_children():
		if c is Button and (c as Button).visible:
			out.append(c)
	return out

## delay 秒後に fn を呼ぶ（その時もまだ同じ結果を出していれば）。後から出る飾りは、出る時に作る（結果の画面を出す
## 1フレームに、部品の作成と文字の準備を集めないため。PERFORMANCE.md §1）。
func _later(delay: float, fn: Callable) -> void:
	var generation := _generation
	get_tree().create_timer(delay).timeout.connect(func():
		if generation == _generation and _shown and is_instance_valid(_deco):
			fn.call())

## ボタンが出てから、最初のフォーカスを主の操作に置く（出る前に Enter で押されないように、出た後で）。
func _focus_when_shown(buttons: Array[Button], delay: float) -> void:
	if buttons.is_empty() or not is_inside_tree():
		return
	var generation := _generation
	get_tree().create_timer(delay).timeout.connect(func():
		if generation == _generation and is_visible_in_tree() and is_instance_valid(buttons[0]) and buttons[0].is_visible_in_tree():
			buttons[0].grab_focus())

# ---------------------------------------------------------------------------
# 案C シネマティック（挑戦・TEST BATTLE）

func _present_cinematic(ctx: Dictionary) -> void:
	var won := bool(ctx.get("won", false))
	var shade := Kit.dim(_deco, 0.0)
	shade.create_tween().tween_property(shade, "color:a", 0.8, 0.8)
	Kit.hgradient(_deco, Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55), 0.35, 1.0)
	# ボス: 勝ったら右で暗く沈む、負けたら大きく立ちはだかる
	var boss := Kit.boss_sprite(_deco, str(ctx.get("boss_asset", "")), BOSS_RECT, Color(0.35, 0.38, 0.44, 0.9) if won else Color.WHITE)
	if boss != null:
		var tw := boss.create_tween()
		if won:
			tw.tween_property(boss, "modulate", Color(0.22, 0.25, 0.3, 0.55), 2.2)
		else:
			boss.modulate.a = 0.0
			tw.tween_property(boss, "modulate:a", 1.0, 1.2)
	_letterbox()
	# 見出し（OutcomeLabel。大きく字間の広い字が、ゆっくり現れて少し流れる）
	var title := _title_label()
	if title != null:
		var color := S.TEXT if won else Kit.RED
		Kit.style_label(title, Rect2(80, 210, 1000, 100), 76, color, HORIZONTAL_ALIGNMENT_LEFT, Kit.spaced_font(20))
		title.add_theme_color_override("font_shadow_color", Color(color, 0.35))
		title.add_theme_constant_override("shadow_outline_size", 10)
		title.modulate.a = 0.0
		title.visible = false
		var tw := title.create_tween().set_parallel(true)
		tw.tween_callback(func(): title.visible = true).set_delay(0.5)
		tw.tween_property(title, "modulate:a", 1.0, 1.0).set_delay(0.5)
		tw.tween_property(title, "position:x", 86.0, 2.4).from(62.0).set_delay(0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_tweens.append(tw)
	var name_text := str(ctx.get("boss_name", ""))
	var sub := (tr("%s を倒した！") % name_text) if won else tr("全滅してしまった……")
	_later(1.2, func():
		var s := Kit.label(_deco, sub, Rect2(86, 318, 680, 36), 22, S.EMPHASIS if won else S.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "ResultSubtitle")
		Kit.enter(s, 0.0, 0.8))
	_later(1.3, func():
		var rule := S.rect(_deco, Rect2(86, 366, 0, 1), S.ACCENT_SOFT, "Rule")
		rule.create_tween().tween_property(rule, "size:x", 420.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	# 数字は1行で
	var parts: Array = []
	parts.append((tr("撃破ターン") if won else tr("倒れたターン")) + "  " + str(int(ctx.get("turns", 0))))
	if won and float(ctx.get("clear_seconds", -1.0)) >= 0.0:
		parts.append(tr("クリアタイム") + "  " + Kit.time_text(float(ctx.clear_seconds)))
	if not str(ctx.get("mode", "")).is_empty():
		parts.append(RBMChallengeUiKit.mode_display_text(str(ctx.mode)))
	_later(1.6, func():
		var stats := Kit.label(_deco, "   ｜   ".join(parts), Rect2(86, 384, 700, 30), 18, S.SILVER, HORIZONTAL_ALIGNMENT_LEFT, "ResultStats", S.number_font())
		Kit.enter(stats, 0.0, 0.8))
	if route == "challenge" and not str(ctx.get("author", "")).is_empty():
		var author := str(ctx.author)
		_later(1.9, func():
			var by := Kit.label(_deco, tr("制作") + "  " + author, Rect2(86, 430, 600, 28), 15, S.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "ResultAuthor")
			Kit.enter(by, 0.0, 0.6))
	_bar_buttons(2.2)

## 上下の黒い帯（外から入ってくる）。
func _letterbox() -> void:
	var top := ColorRect.new()
	top.name = "TopBar"
	top.color = Color(0, 0, 0, 0.92)
	top.position = Vector2(0, -BAR)
	top.size = Vector2(1280, BAR)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.add_child(top)
	var bottom := ColorRect.new()
	bottom.name = "BottomBar"
	bottom.color = Color(0, 0, 0, 0.92)
	bottom.position = Vector2(0, 720)
	bottom.size = Vector2(1280, BAR)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_deco.add_child(bottom)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(top, "position:y", 0.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bottom, "position:y", 720.0 - BAR, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## 下の帯の右に、右詰めでボタンを並べる（先頭＝主の操作が左、次の操作が右）。
func _bar_buttons(delay: float) -> void:
	var shown := visible_buttons()
	var x := 1280.0 - 40.0
	for i in range(shown.size() - 1, -1, -1):
		var b := shown[i]
		Kit.bar_button_style(b, i == 0)
		var w := maxf(240.0 if i == 0 else 200.0, b.get_combined_minimum_size().x + 24.0)
		x -= w
		b.position = Vector2(x, 720.0 - BAR + 20.0)
		b.size = Vector2(w, 52)
		_tweens.append(Kit.enter(b, delay + 0.12 * i, 0.5))
		x -= 16.0
	_focus_when_shown(shown, delay + 0.5)

# ---------------------------------------------------------------------------
# 案A 王道RPG（クリアチェック）

func _present_rpg(ctx: Dictionary) -> void:
	var won := bool(ctx.get("won", false))
	Kit.dim(_deco, 0.6)
	var head := Kit.label(_deco, "CLEAR!" if won else "FAILED…", Rect2(0, 54, 1280, 84), 64, S.GOLD if won else Kit.RED, HORIZONTAL_ALIGNMENT_CENTER, "ResultTitle", S.number_font())
	head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	head.add_theme_constant_override("shadow_offset_x", 4)
	head.add_theme_constant_override("shadow_offset_y", 4)
	Kit.enter(head, 0.0, 0.45, Vector2(0, -40))
	# 小見出し（OutcomeLabel: クリアチェック成功／失敗）
	var sub := _title_label()
	if sub != null:
		Kit.style_label(sub, Rect2(0, 138, 1280, 32), 20, S.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		sub.visible = false
		var tw := Kit.enter(sub, 0.35, 0.3)
		tw.tween_callback(func(): sub.visible = true).set_delay(0.35)
		_tweens.append(tw)
	var lines: Array = []
	lines.append([tr("撃破ターン") if won else tr("倒れたターン"), str(int(ctx.get("turns", 0)))])
	if won and float(ctx.get("clear_seconds", -1.0)) >= 0.0:
		lines.append([tr("クリアタイム"), Kit.time_text(float(ctx.clear_seconds))])
	if not str(ctx.get("mode", "")).is_empty():
		lines.append([tr("挑戦モード"), RBMChallengeUiKit.mode_display_text(str(ctx.mode))])
	var note_text := tr("クリアチェックが完了しました。") if won else tr("ボスが強すぎる時は、能力（HP・ATK）か行動を見直しましょう")
	var party: Array = ctx.get("party", [])
	# 「戦闘結果」の窓（0.3秒）→ 行が1行ずつ → 一言 → 味方が並ぶ。それぞれ出る時に作る
	_later(0.3, func():
		var w := Kit.window(_deco, Rect2(330, 188, 620, 300), tr("戦闘結果"), "ResultWindow")
		_deco.move_child(w, 1)
		Kit.enter(w, 0.0, 0.35, Vector2.ZERO, 0.92)
		for i in lines.size():
			_later(0.35 + 0.18 * i, func():
				var row := Kit.leader_line(w, lines[i][0], lines[i][1], Rect2(40, 58 + 34 * i, 540, 30), 17, S.MUTED, S.TEXT, "ResultLine%d" % i)
				Kit.enter(row, 0.0, 0.2, Vector2(-10, 0)))
		_later(0.4 + 0.18 * lines.size(), func():
			var note := Kit.wrap(w, note_text, Rect2(40, 60 + 34 * lines.size(), 540, 44), 15, S.EMPHASIS if won else S.MUTED, HORIZONTAL_ALIGNMENT_LEFT, "ResultNote")
			Kit.enter(note, 0.0, 0.25))
		# 味方が並ぶ（勝ったら明るく、負けたら暗く）
		var px := 310.0 - 64.0 * party.size() * 0.5
		_later(0.8, func():
			for i in party.size():
				var sp := Kit.ally_sprite(w, str(party[i]), Rect2(Vector2(px + 64 * i + 20, 210), ALLY_SIZE), not won)
				if sp != null:
					Kit.enter(sp, 0.08 * i, 0.25, Vector2(0, 10), 1.0, true)))
	_menu(Rect2(440, 506, 400, 0), 1.5)

## 「▶」のカーソルで選ぶメニュー（ボタンはこの部品の子のまま、窓の中の行に置く）。
func _menu(rect: Rect2, delay: float) -> void:
	var shown := visible_buttons()
	var w := Kit.menu(_deco, rect, shown, "ResultMenu")
	for b in shown:
		_tweens.append(Kit.enter(b, delay, 0.25, Vector2(0, 12)))
	Kit.enter(w, delay, 0.25, Vector2(0, 12), 1.0, true)
	_focus_when_shown(shown, delay + 0.25)
