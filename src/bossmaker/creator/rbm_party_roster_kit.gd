class_name RBMPartyRosterKit
extends RefCounted

## STEP4「攻略パーティ」（2026-10-17、ユーザーが案C を採用）の部品: 役割・説明・技の短い説明・能力のバー・役割のアイコン。
##
## 役割・説明は、マスターデータ（data_bossmaker/allies/*.json）と戦闘の処理（rbm_battle.gd・rbm_constants.gd）を
## 調べて決めた（推測で決めない）。技の短い説明は、そのキャラクターの今の値（HARDCORE の性能調整の後の値。
## RBMCreatorDraft.effective_character_def()）から作る。
##   勇者      炎  HP650 ATK240 SPD100 SP100  単体×1.5・全体×1.7・炎纏い（自分ATK×1.75、3ターン）・高威力×2.2 → 攻撃役・自己強化
##   老執事    氷  HP450 ATK220 SPD120 SP150  氷魔法×2.5・×2.8・大魔法×4.0、SP回復（自分以外1人+40）  → 魔法攻撃役・SP支援
##   少女      雷  HP800 ATK140 SPD110 SP120  雷×2.0、HP回復（1人+400・全員+200）、全体SP回復（自分以外+40）→ 回復役・SP支援
##   侍        風  HP700 ATK280 SPD 70 SP130  風×2.0・×2.5、居合（次の攻撃×2.5）、カウンター（受けた攻撃を防いで風×3.0）→ 攻撃役・一撃と反撃
##   ハンマー使い 無 HP950 ATK200 SPD140 SP100  強打×1.5（SP0）・渾身×3.0、かばう、防御強化（防御の軽減50→60%）、鉄壁（全員-10%）→ 防御役・かばう
## 役割は色だけで伝えない（アイコン＋文字）。属性も色の点＋文字。

const S := preload("res://src/bossmaker/challenge/rbm_challenge_list_style.gd")
const Palette := preload("res://src/bossmaker/visuals/rbm_attribute_vfx_palette.gd")

const IDS := ["hero", "butler", "healer", "samurai", "tank"]
const SHORT_NAMES := {"hero": "勇者", "butler": "老執事", "healer": "少女", "samurai": "侍", "tank": "ハンマー使い"}
const ROLE_KIND := {"hero": "attack", "butler": "magic", "healer": "heal", "samurai": "attack", "tank": "defend"}
const ROLE_TEXT := {"attack": "攻撃役", "magic": "魔法攻撃役", "heal": "回復役", "defend": "防御役"}
const ROLE_COLOR := {"attack": Color("ef9a78"), "magic": Color("b7a2f5"), "heal": Color("74dcaa"), "defend": Color("86b8ea")}
const SUB_ROLE := {"hero": "自己強化", "butler": "SP支援", "healer": "SP支援", "samurai": "一撃・反撃", "tank": "かばう"}
const DESCRIPTION := {
	"hero": "炎纏いで攻撃力を上げ、炎の剣技で攻め続ける。",
	"butler": "強力な氷魔法で大ダメージ。仲間のSPも回復するが、HPは最も低い。",
	"healer": "味方のHPを回復し、全員のSPも回復する。攻撃力は最も低い。",
	"samurai": "攻撃力が最も高い。居合とカウンターの一撃が重いが、最も遅い。",
	"tank": "味方をかばい、防御を固める。HPと速さが最も高い。",
}
## いちばんの持ち味の技（人物の札の「得意技」）。マスターデータの技 id。
const SIGNATURE := {"hero": "hero_flame_wrap", "butler": "butler_grand_ice", "healer": "healer_heal_all", "samurai": "samurai_counter", "tank": "tank_guard_swap"}
const STAT_KEYS := ["hp", "atk", "spd", "max_sp"]
const STAT_LABEL := {"hp": "HP", "atk": "ATK", "spd": "SPD", "max_sp": "SP"}

static var _stat_max: Dictionary = {}

static func name_of(id: String) -> String:
	return TranslationServer.translate(str(SHORT_NAMES.get(id, id)))

static func role_kind(id: String) -> String:
	return str(ROLE_KIND.get(id, "attack"))

static func role_text(id: String) -> String:
	return TranslationServer.translate(ROLE_TEXT[role_kind(id)])

static func role_color(id: String) -> Color:
	return ROLE_COLOR[role_kind(id)]

static func sub_role_text(id: String) -> String:
	return TranslationServer.translate(str(SUB_ROLE.get(id, "")))

static func description(id: String) -> String:
	return TranslationServer.translate(str(DESCRIPTION.get(id, "")))

static func attribute_text(attribute: String) -> String:
	return TranslationServer.translate(str(RBMDefinitionLoader.ATTRIBUTE_LABELS.get(attribute, "無")))

static func attribute_color(attribute: String) -> Color:
	return Palette.color_for(attribute)

## 5人の標準の値の中での割合（バーの長さ）。調整で標準の最大を超えたら1。
static func stat_ratio(def: Dictionary, key: String) -> float:
	if _stat_max.is_empty():
		for k in STAT_KEYS:
			var m := 1
			for id in IDS:
				m = maxi(m, int(RBMDataLoader.load_dict(str(RBMDefinitionLoader.KNOWN_ALLY_PATHS[id])).get(k, 0)))
			_stat_max[k] = m
	return clampf(float(def.get(key, 0)) / float(_stat_max[key]), 0.0, 1.0)

static func skill_by_id(def: Dictionary, skill_id: String) -> Dictionary:
	for s in def.get("skills", []):
		if s is Dictionary and str((s as Dictionary).get("id", "")) == skill_id:
			return s
	return {}

static func skill_name(skill: Dictionary) -> String:
	return TranslationServer.translate(str(skill.get("display_name", skill.get("id", ""))))

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, round(v)) else String.num(v, 2).rstrip("0").rstrip(".")

## 技の短い説明（その技の今の値から作る）。
static func skill_effect(skill: Dictionary) -> String:
	var mult := _num(float(skill.get("atk_multiplier", skill.get("buff_multiplier", 1.0))))
	var attr := attribute_text(str(skill.get("attribute", "NEUTRAL")))
	var turns := int(skill.get("duration_turns", 1))
	match str(skill.get("effect", "")):
		"damage":
			return TranslationServer.translate("%s・攻撃力×%s") % [attr, mult]
		"heal":
			var n := int(skill.get("heal_amount", 0))
			return (TranslationServer.translate("味方全員のHP+%d") if str(skill.get("target", "")) == "ally_all" else TranslationServer.translate("味方1人のHP+%d")) % n
		"sp_recover_single_no_self":
			return TranslationServer.translate("自分以外の1人のSP+%d") % int(skill.get("sp_amount", 0))
		"sp_recover_all_no_self":
			return TranslationServer.translate("自分以外の全員のSP+%d") % int(skill.get("sp_amount", 0))
		"buff_atk_self":
			return TranslationServer.translate("自分の攻撃力×%s（%dターン）") % [mult, turns]
		"buff_next_attack":
			return TranslationServer.translate("次の攻撃×%s") % mult
		"counter_stance":
			return TranslationServer.translate("受けた攻撃を防いで%s・攻撃力×%sで反撃") % [attr, mult]
		"guard_redirect":
			return TranslationServer.translate("選んだ味方への攻撃を代わりに受ける")
		"guard_boost":
			return TranslationServer.translate("防御の軽減を%d%%に（%dターン）") % [int(round(float(skill.get("new_rate", 0.6)) * 100.0)), turns]
		"party_damage_reduction":
			return TranslationServer.translate("味方全員の被ダメージ-%d%%（%dターン）") % [int(round(float(skill.get("reduction_rate", 0.1)) * 100.0)), turns]
		RBMDataLoader.AWAKENING_EFFECT:
			return TranslationServer.translate("全能力×%s（%dターン）") % [_num(float(skill.get("awakening_multiplier", 1.5))), int(skill.get("awakening_turns", 3))]
	return ""

static func sp_text(skill: Dictionary) -> String:
	# 味方の覚醒の SP は最大SPの割合。
	if str(skill.get("effect", "")) == RBMDataLoader.AWAKENING_EFFECT:
		return "SP %d%%" % int(skill.get("awakening_sp_percent", 0))
	return "SP %d" % int(skill.get("sp_cost", 0))

# ---------------------------------------------------------------------------
# 見た目の部品（RBMChallengeListStyle と同じ紺＋水色）

## 1行の文。切り詰めの設定を先にしてから大きさと文を入れる（先に文を入れると欄が文の長さまで広がる）。
static func label(parent: Node, text: String, rect: Rect2, size: int, color: Color, node_name: String = "") -> Label:
	var l := S.label(parent, "", rect, size, color, node_name)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size = rect.size
	l.text = text
	return l

## 折り返す文（折り返しを先に設定する）。
static func wrap_label(parent: Node, text: String, rect: Rect2, size: int, color: Color, node_name: String = "") -> Label:
	var l := S.label(parent, "", rect, size, color, node_name)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.text = text
	return l

static func panel(parent: Node, rect: Rect2, fill: Color, edge: Color, node_name: String = "") -> Panel:
	var p := Panel.new()
	if not node_name.is_empty():
		p.name = node_name
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", S.box(fill, edge))
	parent.add_child(p)
	return p

## ドット絵（足元の影つき）。rect の中に収め、下端をそろえる。
static func sprite(parent: Node, id: String, rect: Rect2, dim: bool = false, node_name: String = "") -> TextureRect:
	var tex := S.fitted_sprite(id, rect.size)
	var fit := S.fitted_size(tex, rect.size)
	S.floor_shadow(parent, Rect2(rect.position.x + rect.size.x * 0.5 - fit.x * 0.42, rect.end.y - 9, fit.x * 0.84, 14))
	var r := TextureRect.new()
	if not node_name.is_empty():
		r.name = node_name
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.texture = tex
	r.position = Vector2(rect.position.x + (rect.size.x - fit.x) * 0.5, rect.end.y - fit.y)
	r.size = fit
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if dim:
		r.modulate = Color(0.55, 0.6, 0.64, 0.85)
	parent.add_child(r)
	return r

## 属性の札（色の点＋文字）。返り値は札の幅。
static func attribute_chip(parent: Node, attribute: String, at: Vector2, size: int = 14) -> float:
	var color := attribute_color(attribute)
	var l := Label.new()
	l.name = "AttributeChip"
	l.text = attribute_text(attribute)
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color.lerp(Color.WHITE, 0.25))
	var style := S.box(Color(color, 0.12), Color(color, 0.55))
	style.content_margin_left = 20
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", style)
	parent.add_child(l)
	var dot := Diamond.new()
	dot.color = color
	dot.position = at + Vector2(7, (l.get_combined_minimum_size().y - 8) * 0.5)
	dot.size = Vector2(8, 8)
	parent.add_child(dot)
	return l.get_combined_minimum_size().x

## 役割の札（アイコン＋文字）。with_sub で副の役割も添える（max_w を超える時は省く。主の役割は必ず出す）。返り値は札の幅。
static func role_chip(parent: Node, id: String, at: Vector2, size: int = 14, with_sub: bool = false, max_w: float = INF) -> float:
	var color := role_color(id)
	var l := Label.new()
	l.name = "RoleChip"
	l.add_theme_font_size_override("font_size", size)
	var text := role_text(id) + ("　" if TranslationServer.get_locale().begins_with("ja") else "  ·  ") + sub_role_text(id) if with_sub else role_text(id)
	if with_sub and max_w < INF:
		var full := l.get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + size + 20
		if full > max_w:
			text = role_text(id)
	l.text = text
	l.position = at
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	var style := S.box(Color(color, 0.1), Color(color, 0.5))
	style.content_margin_left = size + 12
	style.content_margin_right = 8
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", style)
	parent.add_child(l)
	var icon := RoleIcon.new()
	icon.kind = role_kind(id)
	icon.color = color
	icon.position = at + Vector2(5, (l.get_combined_minimum_size().y - size) * 0.5)
	icon.size = Vector2(size, size)
	parent.add_child(icon)
	return l.get_combined_minimum_size().x

## 能力のバー（名前・数・5人の標準の中での割合）。
static func stat_bar(parent: Node, def: Dictionary, key: String, rect: Rect2, node_name: String = "") -> void:
	var lw := 34.0
	var nw := 40.0
	var name_label := label(parent, STAT_LABEL[key], Rect2(rect.position.x, rect.position.y, lw, rect.size.y), 12, S.MUTED)
	name_label.add_theme_font_override("font", S.number_font())
	var value := label(parent, str(int(def.get(key, 0))), Rect2(rect.end.x - nw, rect.position.y, nw, rect.size.y), 13, S.TEXT, node_name)
	value.add_theme_font_override("font", S.number_font())
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bar := Rect2(rect.position.x + lw, rect.position.y + rect.size.y * 0.5 - 3, rect.size.x - lw - nw - 8, 6)
	S.rect(parent, bar, Color("16222a"))
	S.rect(parent, Rect2(bar.position, Vector2(bar.size.x * stat_ratio(def, key), bar.size.y)), Color(S.ACCENT_SOFT.lightened(0.2), 0.95))

static func button(parent: Node, text: String, rect: Rect2, primary: bool, node_name: String, callback: Callable, font_size: int = 14) -> Button:
	var b := Button.new()
	b.name = node_name
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	S.button_style(b, primary)
	b.position = rect.position
	b.focus_mode = Control.FOCUS_ALL
	parent.add_child(b)
	b.size = Vector2(maxf(rect.size.x, b.get_combined_minimum_size().x), rect.size.y)
	b.pressed.connect(callback)
	return b

## 押せる地（カード・仲間の札・並んだキャラ）。selected で青い枠。
static func card_button(parent: Node, rect: Rect2, selected: bool, node_name: String, callback: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_ALL
	b.toggle_mode = true
	b.button_pressed = selected
	var normal := S.box(S.CARD_SELECTED if selected else S.CARD, S.ACCENT if selected else S.CARD_EDGE)
	var hover := S.box(Color("13262f") if selected else S.CARD_HOVER, S.ACCENT if selected else S.SILVER)
	if selected:
		normal.shadow_color = Color(S.ACCENT, 0.14)
		normal.shadow_size = 5
	for key in ["normal", "pressed"]:
		b.add_theme_stylebox_override(key, normal)
	for key in ["hover", "hover_pressed"]:
		b.add_theme_stylebox_override(key, hover)
	b.add_theme_stylebox_override("focus", S.focus_ring())
	b.pressed.connect(callback)
	parent.add_child(b)
	return b

## 色の点（ひし形）
class Diamond:
	extends Control
	var color := Color.WHITE
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(c.x, 0), Vector2(size.x, c.y), Vector2(c.x, size.y), Vector2(0, c.y)]), color)

## 役割のアイコン（剣・星・十字・盾）。図形で描く（フォントに頼らない）。
class RoleIcon:
	extends Control
	var kind := "attack"
	var color := Color.WHITE
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		match kind:
			"attack":
				draw_line(Vector2(w * 0.18, h * 0.82), Vector2(w * 0.86, h * 0.14), color, maxf(2.0, w * 0.14))
				draw_line(Vector2(w * 0.12, h * 0.56), Vector2(w * 0.44, h * 0.88), color, maxf(2.0, w * 0.12))
			"magic":
				var c := Vector2(w, h) * 0.5
				var pts := PackedVector2Array()
				for i in 8:
					var r := (0.5 if i % 2 == 0 else 0.18) * w
					var a := -PI / 2 + i * PI / 4
					pts.append(c + Vector2(cos(a), sin(a)) * r)
				draw_colored_polygon(pts, color)
			"heal":
				draw_rect(Rect2(w * 0.38, h * 0.1, w * 0.24, h * 0.8), color)
				draw_rect(Rect2(w * 0.1, h * 0.38, w * 0.8, h * 0.24), color)
			"defend":
				draw_colored_polygon(PackedVector2Array([Vector2(w * 0.5, h * 0.04), Vector2(w * 0.92, h * 0.2), Vector2(w * 0.84, h * 0.62), Vector2(w * 0.5, h * 0.96), Vector2(w * 0.16, h * 0.62), Vector2(w * 0.08, h * 0.2)]), color)

## 足元の属性の輪（楕円）。
class Ring:
	extends Control
	var color := Color.WHITE
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var pts := PackedVector2Array()
		for i in 33:
			var a := TAU * i / 32.0
			pts.append(c + Vector2(cos(a) * c.x, sin(a) * c.y))
		draw_colored_polygon(pts, Color(color, 0.18))
		draw_polyline(pts, Color(color, 0.85), 2.0)
