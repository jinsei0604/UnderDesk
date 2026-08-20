extends Control
## Resident-strip main view (2026-07-15 redesign: dig -> cave exploration +
## turn-based combat). Draws the idle battle view, hosts the boss-fight
## turn menu, and hosts every card dialog (shop/treasure/archive/altar/
## guild/dorm).

const HUD_HEIGHT: int = 22
const HUD_FONT_SIZE: int = 12

const COLOR_BACKGROUND := Color(0.05, 0.045, 0.07)
const COLOR_HUD_TEXT := Color(0.85, 0.82, 0.75)
const COLOR_HP_BAR_BG := Color(0.15, 0.05, 0.05)
const COLOR_HP_BAR := Color(0.75, 0.2, 0.2)
const COLOR_SP_BAR_BG := Color(0.05, 0.08, 0.15)
const COLOR_SP_BAR := Color(0.25, 0.45, 0.85)
const COLOR_ENEMY_HP_BAR := Color(0.8, 0.3, 0.15)
const COLOR_GATE_BADGE := Color(1.0, 0.5, 0.2)
const COLOR_DIG_ROCKMASS := Color(0.1, 0.09, 0.12)

var sim: UDSim
var settings: UDSettings
var locale: UDLocale
var doc_db: UDDocumentDB
var facility_db: UDShopDB
var item_db: UDItemDB
var weapon_db: UDShopDB
var enemy_db: UDEnemyDB
var stage_db: UDStageDB
var skill_db: UDSkillDB
var art: UDArtLibrary
var achievements: UDAchievements
## Document series defs (data/series/): filename order is display order.
var doc_series: Array = []
## "" = the series-selection shelf; otherwise the open series id.
var _archive_series: String = ""
## "" = the rank-selection shelf; otherwise the open rank (Z/S/A/B/C/D).
var _treasure_rank: String = ""
var companion_defs: Array = []
var _companion_by_id: Dictionary = {}
var _anim_frame: int = 0

## Slide-left backdrop handoff between kills (see _start_bg_transition).
var _bg_transition_timer: Timer
var _bg_transition_from_key: String = ""
var _bg_transition_to_key: String = ""
var _bg_transition_t: float = 0.0
var _bg_transition_active: bool = false
## Set when a kill wants to retarget the backdrop while a slide is already
## running (a fast-killing party can land two kills inside one slide's
## duration). Queued rather than restarting immediately, so a transition
## always finishes the way it started instead of jump-cutting mid-slide.
var _bg_transition_pending_to_key: String = ""

var _tally_text: String = ""
var _tally_until_tick: int = 0

const TALLY_SHOW_TICKS: int = 5

## Expanded-mode control panel: big, thumb-friendly buttons on the
## right; the battle view does not need the full width.
const PANEL_WIDTH: int = 260
const BUTTON_FONT_SIZE: int = 16
const BUTTON_MIN_SIZE := Vector2(118, 44)

## UI-side sprite animation cadence (does not touch the simulation).
const ANIM_FRAME_SECONDS: float = 0.4
var unread_docs: Array[String] = []
var offline_ticks_applied: int = 0
## Snapshot taken right before offline catch-up, so the welcome-back
## summary can report what was earned while away (UI-only bookkeeping;
## the sim itself has no "pending" concept to collect).
var _offline_gold_before: int = 0
var _offline_exp_before: int = 0

var _button_bar: Control
var _archive_button: Button
var _facility_buttons: Dictionary = {}  # facility id -> Button
var _fight_button: Button
var _height_button: Button
var _collapse_button: Button
var _locale_button: Button
var _quit_button: Button
var _archive_dialog: UDCardDialog
var _treasure_button: Button
var _treasure_dialog: UDCardDialog
var _shop_button: Button
var _shop_dialog: UDCardDialog
var _altar_dialog: UDCardDialog
var _guild_dialog: UDCardDialog
var _dorm_dialog: UDCardDialog
## Auto-picked consumption plan for the selected guild exchange target.
var _guild_plan: Dictionary = {}

## 宿屋 (新企画v1 §3, 2026-08-18): a purely cosmetic full-screen view —
## five party portraits over a placeholder backdrop, each with a small
## label that cycles through a fixed flavor-text activity list. No sim
## state, no gameplay effect (per spec: "戦闘のための場所というより、
## 5人への愛着を持ってもらう場所"). Not a UDCardDialog — that widget is
## built around a clickable card grid + detail panel, which doesn't fit
## "look at the room"; this is a plain Control instead. Placeholder art
## (existing minion_N sprites, flat background) until real inn art
## arrives — see CLAUDE.md.
var _inn_button: Button
var _inn_view: Control
var _inn_activity_labels: Array[Label] = []

## Boss encounter UI (expanded-mode only, 2026-07-19 card redesign):
## a top name+HP banner, a bottom command bar with one card per living
## unit, and a shared list-panel overlay for skill/item sub-menus.
var _boss_banner: Control
var _boss_banner_label: Label
var _boss_banner_hp_bar: ProgressBar
## Numeric "600/600"-style readout next to the main HP bar (新企画v1 §8
## playtest pass, 2026-08-21 — the bar alone didn't read as a number the
## player could reason about against a part's own HP).
var _boss_body_hp_label: Label
## Per-part compact rows (name + mini bar + hp/status text), one per
## entry in the boss's "parts" data, rebuilt by _refresh_boss_parts_
## column() whenever the boss panel refreshes. Replaces the single dense
## "tail 15/15 leg 15/15" line from the first part-destruction prototype
## (新企画v1 §8, 2026-08-18) — real playtesting on cave_troll (2026-08-21)
## found it unreadable and, worse, offered no way to actually pick a part
## as an attack target; see _target_confirm_panel's enemy_target_rows for
## the other half of that fix.
var _boss_parts_column: VBoxContainer
var _boss_part_rows: Dictionary = {}  # part id -> {"bar":ProgressBar,"name":Label,"text":Label}
## Shadow HP for the currently-playing round's damage, kept per part id —
## the exact same "reveal the already-decided result at hit-time, not
## instantly" pattern _battle_boss_hp_display already used for the main
## body (see _on_boss_resolve_round/_fire_battle_anim_hit). Populated by
## _on_boss_resolve_round() from sim.boss_part_hp *before* resolve_boss_
## round() mutates it.
var _battle_boss_part_hp_display: Dictionary = {}  # part id -> int
var _battle_bar: Control
var _battle_cards: Dictionary = {}  # unit id -> {panel: PanelContainer, style: StyleBoxFlat}
var _battle_attack_button: TextureButton
var _battle_skill_button: TextureButton
var _battle_item_button: TextureButton
var _battle_start_button: TextureButton
var _battle_list_panel: PanelContainer
## Top-right REWIND button (originally やめる/flee, 2026-07-19; repurposed
## 2026-08-18 for 新企画v1 §10 — sim.rewind_boss_fight() restarts THIS
## attempt from its checkpoint instead of leaving the encounter). No
## enable/disable state: always available mid-fight.
var _quit_battle_button: Button
## Directly below the REWIND button (2026-08-18, user report: once REWIND
## took over やめる's old slot there was no longer ANY way to leave the
## battle screen — _button_bar (宿屋/ギルド/etc.) only shows when
## _boss_screen_active() is false, and only a win or this button clears
## that). Calls the unchanged sim.flee_boss_fight() (still exits the
## encounter outright, gate stays uncleared) so the player can reach the
## other screens mid-fight instead of being stuck until they win.
var _leave_battle_button: Button
## Small centered もどる/決定 confirm panel shown when REWIND is pressed
## (新企画v1仕様書 v2 §25, 2026-08-20 — "REWINDを押すと、可能であれば確認
## ダイアログを表示してください"). Deliberately a plain Control overlay,
## not a native ConfirmationDialog/Window — this codebase moved its other
## popups (UDCardDialog) off Window nodes specifically to avoid ESC/focus
## edge cases (see card_dialog.gd's history), so a genuine sub-window here
## would reintroduce exactly that class of bug for a one-off Yes/No prompt.
var _rewind_confirm_panel: PanelContainer
## Currently shown entries for the skill/item picker panel, and which row
## is highlighted (select-then-confirm: highlighting previews the
## description, 決定 commits it). -1 = nothing selectable (empty list).
var _battle_list_entries: Array = []
var _battle_list_selected_index: int = -1
## unit_id -> {"action": "attack"/"skill", "skill_id": String}, filled in
## as the player picks a command per unit and submitted together via
## sim.resolve_boss_round() when 行動開始 is pressed.
var _battle_pending_actions: Dictionary = {}
## Fixed left-to-right seating (Sotiris, then companion_1..4 = Madoka,
## Vard, Shiba Yao, Sayu) regardless of join order, per the reference
## layout — not sim.minions' array order. Living units only; rebuilt on
## every _refresh_boss_panel so a death mid-fight drops that card.
var _battle_order: Array[int] = []
var _battle_selected_unit: int = -1
## Target selection (2026-07-19 addition). Phase names match the user's
## spec vocabulary verbatim (commandSelection/skillSelection/
## targetSelection/actionConfirmed/executing) so they map 1:1 to that
## design doc; UI visibility is driven off this rather than inferred from
## which panel happens to be visible.
var _battle_phase: String = "commandSelection"
## "attack" or "skill" — which command opened target selection, so もどる
## knows whether to return to the plain command view or reopen the skill
## list (see _on_target_back).
var _battle_target_source: String = ""
var _battle_pending_skill_id: String = ""
## "enemy" or "ally" — which pool _battle_selected_target_id/
## _battle_selected_ally_target draws from and which UI (enemy crosshair
## vs. party-card highlight) is active, set from the skill's own "target"
## field when target selection begins (_enter_target_selection).
var _battle_target_kind: String = "enemy"
## Id of the enemy currently highlighted by the crosshair. Only one enemy
## exists today (sim.boss_enemy_id), but this is a selection over
## _battle_enemy_targets() rather than a hardcoded single id so left/right
## cycling and click-to-target already work the moment a second enemy
## exists.
var _battle_selected_target_id: String = ""
## unit_id of the party card currently highlighted for an ally-target
## skill (e.g. Healing) — a selection over _battle_ally_targets() the
## same way _battle_selected_target_id is over _battle_enemy_targets().
var _battle_selected_ally_target: int = -1
var _commands_column: VBoxContainer
var _target_confirm_panel: PanelContainer

## --- Battle message (新企画v1仕様書, 2026-08-22〜22b) ---------------------
## 2026-08-22bで「複数行動者ぶんを溜めるログ」から「現在行動している
## 1キャラクター/敵の内容だけを表示するメッセージ」へ設計転換——実機
## 確認で「ログが戦闘画面を覆う」と判断されたため。新しい行動者の
## ターンが始まった瞬間に_clear_battle_message()で全消去してから積み
## 直す。1ターン内（宣言→命中→部位破壊 等）は最大BATTLE_MESSAGE_MAX_
## LINES行まで積み上がる——複数ターンを跨いでは絶対に蓄積しない。
## Direct references (not find_child string lookups) to the fixed row of
## Labels built once in _build_battle_bar() — see _refresh_battle_message_labels.
var _battle_message_panel: PanelContainer
var _battle_message_labels: Array[Label] = []
## Oldest-of-this-turn first, newest last (§3: 同一キャラクターの行動
## 結果は上から順に2〜3行). Each entry: {"text": String, "kind": "normal"|
## "special"}. UI-only, session-scoped state — never written to a save,
## never fed into boss_intel (§11「既存のboss_intelとは別システム」),
## and never a cross-turn history (§2「前の行動者の文章を残さない」)
## — REWINDと同じ理由で、プレイヤー自身の記憶が攻略要素であることを
## 壊さない設計。
var _battle_message_lines: Array[Dictionary] = []

## --- Battle motion sequencer (2026-07-19) --------------------------------
## Plays back each acting character's attack/skill as move-to-center ->
## act -> move-back, one unit at a time in _battle_order, AFTER
## sim.resolve_boss_round() has already resolved the whole round. The sim
## call stays a single synchronous, deterministic step (unchanged contract,
## still one call = one round, still what the determinism/save-roundtrip
## tests exercise) — this sequencer only re-times *when* the already-known
## result becomes visible, using resolve_boss_round's "log" to know what
## each step should show. See _on_boss_resolve_round/_advance_battle_anim_step.
var _battle_anim_queue: Array[Dictionary] = []
var _battle_anim_step: int = -1
var _battle_anim_phase: String = ""  # "move_in" / "act" / "move_out"
var _battle_anim_phase_elapsed: float = 0.0
var _battle_anim_frame_index: int = 0
var _battle_anim_motion_key: String = ""
var _battle_anim_hit_fired: bool = false
## True from 行動開始 (just before sim.resolve_boss_round) until
## _finish_battle_round. THE key playback flag (2026-07-20 bugfix): on a
## round that decides the fight, resolve_boss_round flips sim.boss_active
## to false immediately — before a single motion frame has drawn — so
## everything gated on sim.boss_active (the _draw() branch, _view_rect's
## full-window mode, _formation_pos's boss formation, _draw_party_row's
## animated-position override, the battle chrome) snapped back to the
## idle view mid-playback: the screen "switched to the idle screen" and
## characters "stood in place" (user report — looked skill-specific
## because 必殺技-heavy rounds are the ones that end fights). Every one of
## those checks now goes through _boss_screen_active() instead.
var _battle_playback_active: bool = false
## The boss being animated against, stashed at resolve time: on a won
## round sim.boss_enemy_id is already "" during playback, and the boss
## must stay visible while the killing blow plays out.
var _battle_playback_boss_id: String = ""
## For ATTACK entries (the only ones that still physically travel, see
## the "本物のRPG戦闘、第3弾" doc comment on _advance_battle_anim_step):
## where the character walks to. For SKILL entries: the actual target's
## reference point (boss position for an enemy target, the target ally's
## formation slot for an ally target) — used only for the small in-place
## step-in's direction and has no bearing on where the impact/projectile
## effect lands (those compute the boss's position independently; see
## _fire_battle_anim_hit/_launch_battle_projectile). View-fraction space,
## computed per action in _battle_anim_destination.
var _battle_anim_dest := Vector2.ZERO
## Where the current step's character started (view-fraction space, its
## resting formation slot) — skills step at most BATTLE_ANIM_SKILL_STEP_
## FRAC toward _battle_anim_dest and back, never actually traveling there.
var _battle_anim_origin := Vector2.ZERO
## Length of the current "act" phase: the motion clip's frame count times
## BATTLE_ANIM_ACT_FRAME_SECONDS, so the clip plays exactly once at a
## deliberate pace instead of looping at the redraw rate.
var _battle_anim_act_seconds: float = 1.0
## Horizontal flip for the currently-animating character: sheets face
## right natively, so only the walk back to formation (moving left) flips.
var _battle_anim_flip: bool = false
## Hit-reaction state (2026-07-20). No 被弾/ガード/勝利 rows exist on any
## character sheet and no enemy art has been delivered at all (both
## user-confirmed 2026-07-20) — so hit reactions are code-driven: flash +
## knockback + popup on whatever art or placeholder is standing there.
## All of these decay to 0 in _update_battle_anim_popups.
var _battle_enemy_knock_t: float = 0.0
## Per-hit override of the shared BATTLE_KNOCKBACK_PX/BATTLE_ENEMY_HIT_
## SECONDS (2026-07-26, soul_break's own spec: "敵を右へ約10pxノックバッ
## クし、約120msで戻す" — smaller/faster than every other skill's shared
## 18px/0.5s) — same "instance var defaulted to the shared constant,
## overridden per-hit via _fire_battle_anim_hit's own trailing params"
## pattern _battle_shake_duration/_peak_px already established for shake.
var _battle_knockback_px: float = BATTLE_KNOCKBACK_PX
var _battle_knockback_seconds: float = BATTLE_ENEMY_HIT_SECONDS
var _battle_impact_t: float = 0.0
## Where the burst actually appears (px): a projectile bursts at its own
## landing point, a melee hit at the boss's near side.
var _battle_impact_pos := Vector2.ZERO
## Boss counter-attack lunge (out-and-back toward the party), peaking at
## the moment its hit lands on the target ally.
var _battle_boss_lunge_t: float = 0.0
var _battle_ally_hit_unit: int = -1
var _battle_ally_hit_t: float = 0.0
## In-flight skill projectile (2026-07-20 user fix: ranged skills fire
## from center stage and the shot visibly TRAVELS to the enemy — the hit
## lands when it arrives, not when the cast animation reaches its peak).
## Pixel-space endpoints, captured at launch.
var _battle_proj_active: bool = false
var _battle_proj_t: float = 0.0
var _battle_proj_from := Vector2.ZERO
var _battle_proj_to := Vector2.ZERO
## The skill's own isolated-effect cell (SKILL_MOTION proj_frame), if it
## has one — drawn as the shot instead of the fallback code bolt.
var _battle_proj_tex: Texture2D = null
## Dedicated in-flight animation clip (SKILL_MOTION proj_key, from the
## 2026-07-20 asset pack): an 8-frame wobble loop that plays IN PLACE on
## the moving shot (per the pack README — the frames are not themselves
## the movement). Takes priority over _battle_proj_tex.
var _battle_proj_key: String = ""
## Which impact_* clip the current burst plays (caster element, see
## VARIANT_IMPACT); "" or missing art = the code-drawn radial burst.
var _battle_impact_key: String = ""
## unit_id -> Vector2 (view-fraction, same space as _formation_pos), set
## only for the one unit currently mid-animation. _draw_party_row draws
## that unit here instead of its resting formation slot.
var _battle_anim_pos: Dictionary = {}
## Floating "-N"/"+N" numbers riding up and fading out, and the boss
## icon's hit-flash decay. See _fire_battle_anim_hit/_draw_battle_anim_popups.
var _battle_anim_popups: Array[Dictionary] = []
var _battle_anim_boss_flash_t: float = 0.0
## Decay duration for _battle_anim_boss_flash_t above — 0.25s for every
## normal hit, overridden per-call by _fire_battle_anim_hit's new trailing
## params (currently only rapid_slash passes a different value, see
## RAPID_SLASH_FLASH_DECAY_SECONDS).
var _battle_boss_flash_decay_seconds: float = 0.25
## Brief freeze on every damaging hit (2026-07-20 polish, "hitstop"): the
## swing/shot was landing with no acknowledgment — flash and knockback
## fired, but the attacker's own animation and the world kept moving
## straight through the moment of impact, so it read as whooshing past
## rather than connecting. A short universal pause (position/frame
## advancement skipped, see _on_battle_anim_tick's top) sells the weight
## of the hit — a standard technique in action games. Kept short enough
## (BATTLE_HITSTOP_SECONDS) to be felt, not noticed as slowdown.
var _battle_hitstop_t: float = 0.0
## Brief screen shake on a damaging hit (2026-07-21, reference material:
## "画面を右2px→左6px→右3px→原点の順に、合計80ms程度で揺らす"). Purely
## a draw-time offset applied to the boss-battle view rect in
## _draw_boss_battle — never touches _view_rect() itself, so click hit-
## testing/target selection (which call _view_rect() separately) are
## unaffected by the shake.
var _battle_shake_t: float = 0.0
## Duration/peak-magnitude _battle_shake_offset() actually reads (set
## alongside _battle_shake_t on every hit, default = the shared BATTLE_
## SHAKE_SECONDS/a 6px peak so ordinary hits are unaffected) — lets one
## hit (currently only rapid_slash, see RAPID_SLASH_SHAKE_SECONDS/_PEAK_PX)
## request a shorter/gentler shake without a second shake system.
var _battle_shake_duration: float = BATTLE_SHAKE_SECONDS
var _battle_shake_peak_px: float = 6.0
## New effect (2026-07-26, rapid_slash VFX v2 only): a single-tick,
## low-opacity full-view white flash layered over everything else at the
## hit moment. Decays to 0 in _update_battle_anim_popups; drawn in
## _draw_boss_battle as a plain full-view rect when > 0.
var _battle_screen_flash_t: float = 0.0
var _battle_screen_flash_alpha: float = 0.0
## rapid_slash's 3 independent flying waves (2026-07-26 v3 rebuild) — one
## Dictionary per wave, seeded from RAPID_SLASH_WAVE_DEFS when rapid_slash's
## own act phase starts (_enter_battle_anim_act_phase) and updated every
## tick by _update_rapid_slash_waves. Each holds: key, label, active,
## arrived, launch_time, arrive_time, draw_px, y_offset, start_pos,
## target_pos, progress (0-1, the eased travel fraction), rotation,
## animation_frame, spark_t. Deliberately NOT a single shared "current vfx
## key" overwritten by elapsed time (see RAPID_SLASH_WAVE_DEFS' own doc
## comment) — all 3 can be, and are, drawn in the same frame.
var _rapid_slash_waves: Array[Dictionary] = []
## True once RAPID_SLASH_IMPACT_FRAMES' first breakpoint has been crossed
## THIS act phase — guards "RAPID impact started" so it logs exactly once.
var _rapid_slash_impact_started: bool = false
## message -> times printed this whole run (not reset between rapid_slash
## casts) — lets a test assert "each message fired exactly once" for one
## specific cast without needing to capture stdout (see
## tests/core/test_rapid_slash_vfx_logging.gd).
var _rapid_slash_debug_log_counts: Dictionary = {}
## 2026-07-26 (bugfix round: "消えたはずの大三日月が再び表示され...約1秒間
## 貼り付いています"). The actual bug: a wave's "active" flag was only ever
## set TRUE (on launch) and never reset — _draw_rapid_slash_wave's own gate
## checked nothing but "active", so an arrived wave kept drawing forever,
## frozen at target_pos (exactly the "big crescent stuck in front of the
## enemy" symptom). _rapid_impact_active is a THIRD, independent gate (on
## top of each wave's own active/arrived) that forcibly blanks every wave
## the instant the X-impact begins — see _start_rapid_impact().
var _rapid_impact_active: bool = false
var _rapid_impact_elapsed: float = 0.0
## Final-polish round (2026-07-26) additions — all reset in both
## _enter_battle_anim_act_phase (fresh cast) and _reset_rapid_slash_vfx_
## state (act end), same lifecycle as the vars above.
## Explicit charge-glow visibility gate (user spec item 1) — see RAPID_
## SLASH_CHARGE_END_SECONDS' doc comment for why this replaced the v3
## round's implicit "wave_a_launched" time-window check.
var _rapid_charge_active: bool = false
## Tiny per-launch position kick (user spec item 4) — time remaining and
## the peak px/direction it's currently decaying from, read by
## _rapid_recoil_offset_px().
var _rapid_recoil_t: float = 0.0
var _rapid_recoil_peak_px: float = 0.0
## Post-explosion drifting/spreading/fading particles (user spec item 6) —
## time remaining, read by _draw_rapid_slash_debris().
var _rapid_debris_t: float = 0.0
## SFX (2026-07-26 delivery) — key (RAPID_SLASH_SFX_PATHS) -> AudioStreamPlayer,
## built once in _build_rapid_slash_sfx() (called from _ready(), same
## "dynamic node, no .tscn changes" pattern every other Timer/Control in
## this file already uses). Missing files just leave stream null and
## _play_rapid_sfx() silently no-ops — same has_art()-style graceful
## fallback this project already uses for missing art.
var _rapid_sfx_players: Dictionary = {}
## Guards the one SFX (README "sparks", 1.50s) with no existing one-shot
## event to attach to — see RAPID_SLASH_SFX_SPARKS_SECONDS' doc comment.
var _rapid_sfx_sparks_played: bool = false
## エオスバースト竜出現 — 「召喚専用8コマ導入」(2026-08-01)でSubViewport+
## MeshInstance2D+カスタムシェーダーによる前回までの実装を完全に撤去し、
## 他の全キャラモーションと同じ「_eos_burst_texture()で個別PNGを直接ロード
## しdraw_texture_rectで描く」方式へ統一した。もう永続ノードを一切必要と
## しない(このvarブロック自体が丸ごと不要になった)——z順は_draw_eos_
## burst_back_vfx/_draw_party_row/_draw_eos_burst_front_vfxの既存の呼び
## 出し順そのままで担保される(SubViewportの中身が何であってもmain自身の
## _draw()呼び出し順が唯一の真実だった、という設計はそのまま維持)。
## ヒーリング (2026-07-26 overhaul) — its own state block, entirely
## separate from every _rapid_*/_battle_ally_hit_* var above. Reset both at
## cast start (_enter_battle_anim_act_phase) and cast end (_reset_healing_
## vfx_state), same dual-reset lifecycle rapid_slash's own state uses.
var _healing_target_unit: int = -1
## Decays from HEALING_TARGET_FLASH_SECONDS to 0 — see _draw_party_row's
## own separate (non-knockback) check for how this is consumed.
var _healing_target_flash_t: float = 0.0
## HP the target had BEFORE this cast's heal. Computed once at cast start
## (2026-07-26 round-2 fix — see _enter_battle_anim_act_phase's HEALING_
## SKILL_ID branch) as unit.hp - amount, since sim.resolve_boss_round()
## already applied the heal atomically before any animation plays. Used by
## _healing_display_hp (shared by _draw_party_row's on-field bar AND
## _sync_healing_target_card's command-bar card).
var _healing_hp_display_before: int = 0
## True from cast start until the animated hit-apply instant: while true,
## _healing_display_hp shows the FROZEN pre-heal value instead of the
## real (already-healed) sim.minions[].hp — without this, the target's
## displayed HP silently jumped to the post-heal number the moment the
## round resolved (well before the beam/impact even reach the target),
## a real bug this round's headless trace caught (a card read "70/70" at
## the very first animation tick, long before the 0.92s hit moment).
var _healing_hold_pre_heal: bool = false
var _healing_hp_anim_t: float = 0.0
## One-shot log guards for the 4 beats that have no OTHER natural one-shot
## event to attach to (unlike rapid_slash's waves/impact, none of these are
## stateful active/arrived objects — see the HEALING_* constants' own doc
## comments for why orb/beam/circle/pillar stay plain elapsed-time checks).
var _healing_orb_logged: bool = false
var _healing_beam_launch_logged: bool = false
var _healing_beam_arrive_logged: bool = false
var _healing_circle_logged: bool = false
var _healing_pillar_logged: bool = false
var _healing_pillar_end_logged: bool = false
var _healing_debug_log_counts: Dictionary = {}
## SFX (2026-07-26 v2 delivery) — key (HEALING_SFX_PATHS) -> AudioStreamPlayer,
## built once in _build_healing_sfx() (called from _ready(), same pattern
## _rapid_sfx_players already established). One-shot guards below since
## none of the 3 sounds has an existing stateful "just happened" event to
## piggyback on the way rapid_slash's did (that used wave active/arrived
## flags and _battle_anim_hit_fired; healing's own equivalents — the
## _healing_*_logged debug-log guards — are reused directly instead of
## adding a second redundant set, since a debug log firing IS "this beat
## just happened exactly once" already).
var _healing_sfx_players: Dictionary = {}
## ソウルブレイク v3 (2026-07-26 full rewrite) — its own state block,
## entirely separate from every _rapid_*/_healing_* var above (user spec:
## "ラピッドスラッシュとヒーリングは一切変更しません"). One-shot debug-log
## guards for the beats with no other stateful event to piggyback on (the
## damage-confirm beat reuses the existing _battle_anim_hit_fired guard).
var _soul_break_debug_log_counts: Dictionary = {}
var _soul_break_gather_logged: bool = false
var _soul_break_hold_logged: bool = false
var _soul_break_launch_logged: bool = false
var _soul_break_downswing_logged: bool = false
var _soul_break_followthrough_logged: bool = false
var _soul_break_impact_logged: bool = false
var _soul_break_burst_logged: bool = false
var _soul_break_return_logged: bool = false
## v16: guards the stage-4 contact cosmetic pre-flash (fires once, at
## SOUL_BREAK_CONTACT_SECONDS, separately from _battle_anim_hit_fired
## which now guards the LATER real hit at SOUL_BREAK_MAX_IMPACT_SECONDS)
## — see that dispatch site's own comment. Renamed from v7-v15's
## "_soul_break_freeze_fired" (the old deferred-hitstop-only mechanism it
## guarded is retired; this is a 2-beat cosmetic+real hit design now).
var _soul_break_contact_flash_fired: bool = false
## v13: a SEPARATE, genuinely continuous flight-progress timer (user spec:
## "位置はTimerやスプライトアニメーションのフレームで更新せず、_process
## (delta)などで毎描画フレーム更新する") — advances every rendered frame
## via _process() below, independent of the 20Hz battle-anim tick that
## everything else in this file (including this same skill's own 4-frame
## shell/fragment loop) reads. Only ever read/written while soul_break's
## own flight window is active; _reset_soul_break_state() and the enter-
## act-phase branch both zero it out for the next cast.
var _soul_break_proj_flight_active: bool = false
var _soul_break_proj_flight_elapsed: float = 0.0
## v16/v17: generic path->Texture2D cache for every soul_break VFX asset
## delivered outside UDArtLibrary's ART_DIR (assets/vfx/sotiris/) —
## the twin-cleave flight frames, the crescent-impact frames, and the
## launch arc all share this ONE cache instead of near-duplicate single-
## texture loaders. Loaded at most once per path per game session, null-
## safe if a file is ever missing.
var _soul_break_texture_cache: Dictionary = {}
## SFX (v1 delivery): key -> AudioStreamPlayer, built once in _build_soul_
## break_sfx() from _ready(), same lifecycle as rapid_slash's/healing's.
var _soul_break_sfx_players: Dictionary = {}
## key -> true once that cue has fired this cast; cleared alongside every
## other per-cast soul_break flag so a re-cast replays the full set.
var _soul_break_sfx_fired: Dictionary = {}
## --- エオスバースト per-cast state. The approach target is SOLVED ONCE at
## cast start and held, so the dash can't drift if the enemy's own rect
## shifts mid-animation (e.g. its knockback offset), and so the return
## always targets the same origin it left.
var _eos_burst_approach_offset_px: float = 0.0
## 「動きのカクつきを根本修正する」(2026-08-06、"Smooth motion + body-emitted
## aura + roar v3") — soul_breakの飛翔体(`_soul_break_proj_flight_elapsed`、
## _process内で実deltaを加算)と全く同じパターンをSotiris/竜のroot移動へ
## 適用。詳細は`_process`の該当ブロックと`_eos_burst_smooth_elapsed`参照。
var _eos_burst_smooth_root_active: bool = false
var _eos_burst_smooth_root_elapsed_value: float = 0.0
var _eos_burst_logged: Dictionary = {}
## 「タメ延長 + 専用SE」(2026-08-06) — key -> AudioStreamPlayer、built once
## in _build_eos_burst_sfx() from _ready(), same lifecycle as rapid_slash's/
## healing's/soul_break's own SFX. 「1個のAudioStreamPlayerで4音を順番に
## 差し替える実装は避ける」(README) を、rapid_slash以来のこのプロジェクトの
## 確立済みパターン(音ごとに専用player)でそのまま満たす——別音のtailが
## 途中で切られる心配がない。fired-once guardは新しい辞書を増やさず、この
## スキル自身が既に持つ`_eos_burst_logged`(has()チェック+"EOS assault
## contact hitstop"等の既存キー)をそのまま流用する。
var _eos_burst_sfx_players: Dictionary = {}
## 「Professional Mix / Impact Polish v1」(2026-08-07) — 旧`_eos_burst_
## impact_flash_t`/`_eos_burst_mega_shake_t`(発火時に満タンへセットし、
## `_on_battle_anim_tick`の20Hz tickごとに固定dt=0.05秒ずつ減算するカウント
## ダウン方式)を完全に撤去した。実測(`references/impact_flash_60fps.jpg`)
## で、フラッシュのピークが1 renderedフレームではなく丸ごと1game tick分
## (最大50ms)ベタ張りになり、爆発を洗い流していたことが判明——tick間の
## 複数回の実描画フレームでは`_eos_burst_impact_flash_t`の値が一切変化
## しないため、αが50ms間ずっとPEAKに固定されていたのが実体(headless
## テストは`age`を直接手計算しており、この「tick跨ぎでのみ減衰する」実際の
## 挙動を一度も検証していなかった)。新方式は「発火した瞬間の連続elapsed
## (`_eos_burst_smooth_elapsed`、前ラウンドのroot motion連続化と同じ機構)
## を1回だけ記録し、以後は`age := 現在の連続elapsed - この記録値`を毎
## 実描画フレームで計算し直す」——カウントダウン変数の`- dt`減算が不要に
## なり、`_on_battle_anim_tick`側の専用decayコードも同時に削除できる。
## フラッシュ・shake・busのduck解除ランプの3つが全てこの同じ1つの記録値を
## 共有する(「damage+巨大爆発+hitstopが発火する実contactイベント」という
## README自身の一体化した表現を、3つの個別タイマーではなく1つの共有
## マーカーとして構造的に体現)。-1.0=「このcastではまだ着弾していない」
## センチネル。
var _eos_burst_contact_trigger_elapsed: float = -1.0
## Lazily-generated, cached-forever teardrop "light spear" texture used by
## the flight attack (see `_eos_burst_spear_texture`) — no dedicated art
## asset was delivered, so this is a small procedural ImageTexture built
## once and reused every cast. (Replaces the old round's soft radial blob,
## retired with the beaded-stamp-chain approach it used to stamp.)
var _eos_burst_spear_cache: ImageTexture = null
## v16 stage 3 (飛翔): 2 STAMPED afterimage slots (user spec: "残像は本体
## の現在位置へ追従させず、生成された位置へ短時間残す" — genuinely held
## state, not recomputed from the live position every frame). Lazily
## seeded to 2 entries on first update (see _update_soul_break_afterimages)
## rather than in _enter_battle_anim_act_phase, so no extra wiring is
## needed there; reset to empty (auto-reseeds next cast) in _reset_soul_
## break_state.
var _soul_break_afterimages: Array[Dictionary] = []
## UI-only shadow of the boss's HP so its banner bar can visibly drain
## per-hit during playback instead of jumping straight to the post-round
## value the moment 行動開始 is pressed (sim.boss_hp is already final by
## then — resolve_boss_round resolves atomically, see above).
var _battle_boss_hp_display: int = 0
var _battle_pending_round_result: Dictionary = {}
var _battle_anim_timer: Timer
## Overnight motion-testing aid (2026-07-19, user request): press F9 during
## a boss fight to auto-restart the same encounter on win or loss instead
## of returning to the map, so a fresh full-HP attempt is always one
## keypress away while animation timing gets tuned. Purely a main.gd
## orchestration loop around the existing start_boss_fight()/rematch
## machinery — no sim-side "boss can't die" flag, nothing persisted.
## Defaults to OFF (2026-07-26 re-fix): it also force-heals the whole party
## every round (_debug_restore_party), which silently undid manual HP
## reductions set up to verify a heal skill's actual effect — exactly the
## kind of "real playtesting" this doc comment already said to turn it off
## for (the CODE never matched that until now; it had defaulted to true).
var _debug_boss_loop: bool = false

## The timer only drives movement lerp + phase transitions; sprite frame
## pacing is derived from elapsed time via the *_FRAME_SECONDS constants
## below (2026-07-20 rework — originally frames stepped once per timer
## tick, which played 8-frame clips in 0.4s: the "モーション速度が速すぎる"
## user report).
const BATTLE_ANIM_FPS: float = 20.0
## 0.6 -> 0.75 (2026-07-20): ~450px of travel reads clearly as running
## across the arena rather than a blink-and-miss reposition.
const BATTLE_ANIM_MOVE_SECONDS: float = 0.75
## Walk/dash cycle pace while running in/out.
const BATTLE_ANIM_MOVE_FRAME_SECONDS: float = 0.1
## Attack/skill clip pace: one clip pass = frame_count * this (8-frame
## clips ≈ 1.4s), played exactly once per action — the last frame holds
## until the phase ends instead of the clip wrapping around mid-pose.
const BATTLE_ANIM_ACT_FRAME_SECONDS: float = 0.18
const BATTLE_ANIM_ACT_MIN_SECONDS: float = 0.9
## Fraction into the "act" phase where a SKILL's hit lands (each skill
## row's effect peak sits at a slightly different frame, so a fraction is
## the honest generic answer). A normal attack instead fires exactly when
## the clip reaches BATTLE_ANIM_ATTACK_HIT_FRAME — on every basic sheet
## the attack row's baked-in slash/impact effect appears around the 5th
## cell (0-indexed 4; Vard's shield impact is one cell earlier, close
## enough until per-character tuning is worth it).
const BATTLE_ANIM_HIT_AT: float = 0.5
const BATTLE_ANIM_ATTACK_HIT_FRAME: int = 4
## The dash rows end with ~2 decelerate/stop cells: the run-in loops the
## clip minus this trim, then the "arrive" microphase plays the trimmed
## tail once while the character settles at its destination.
const BATTLE_ANIM_DASH_LOOP_TRIM: int = 2
const BATTLE_ANIM_ARRIVE_SECONDS: float = 0.2
## Boss counter-attack step: total length, and how far in its hit lands
## on the target ally (flash + knockback + damage popup, simultaneous).
const BATTLE_ANIM_COUNTER_SECONDS: float = 0.8
const BATTLE_ANIM_COUNTER_HIT_AT: float = 0.45
## Pre-hit frame stepping eases in rather than advancing at a flat rate
## (2026-07-21, reference material: real games hold the wind-up frames
## longer and rush the swing itself — "溜めは長く、攻撃部分は一瞬" — a
## uniform per-frame duration reads as limp no matter how many frames a
## clip has). > 1 = slow start, accelerating; only warps which frame is
## DISPLAYED, never the hit timing itself (BATTLE_ANIM_HIT_AT / hitstop /
## projectile launch all still run on the real clock, so tuned timings
## elsewhere are unaffected).
const BATTLE_ANIM_ANTICIPATION_EASE: float = 1.8
## Small forward weight-shift during a MELEE ATTACK's swing (2026-07-21;
## narrowed to attacks only 2026-07-24, see below): position was frozen
## for the whole "act" phase (only move_in/move_out moved the character),
## so the body looked static from the waist while only the sprite cycled —
## the reference material's "キャラクターの前進とスプライト内の踏み込み
## を別々の無関係な動きにしない" point. Peaks via sin(t*PI) at t=0.5,
## which lines up with BATTLE_ANIM_HIT_AT. Attacks still physically walk
## up to the boss (move_in/arrive), so this is a subtle accent on top of
## an already-completed approach.
const BATTLE_ANIM_LUNGE_FRAC: float = 0.018
## 2026-07-24 redesign ("RPGらしい正しい構成", user-relayed ChatGPT review):
## headless trajectory tracing (see CLAUDE.md) proved SKILL actions never
## actually jumped position — but they DID fully walk from formation to
## center-stage/the boss over BATTLE_ANIM_MOVE_SECONDS, which read as
## unwanted travel regardless of how smooth the walk itself was. Skills no
## longer travel at all: _advance_battle_anim_step skips move_in/arrive
## for them entirely and starts straight in "act" at the caster's own
## formation slot (_battle_anim_origin); this is the ENTIRE motion budget
## for a skill (windup -> tiny step -> swing -> tiny step back), not a
## subtle accent layered on top of a completed walk like the attack lunge
## above. The actual hit — damage, the boss flash, screen shake, and the
## impact burst drawn at the boss's own position — was ALREADY fully
## decoupled from the caster's position (_fire_battle_anim_hit computes
## the boss's position independently; see its doc comment), so none of
## that needed to change.
##
## 2026-07-24, rapid_slash 4-stage rebuild, stage 1: zeroed to isolate
## whether skill-time position control is even a factor before touching
## anything else — user spec ("まずスキル中の位置移動を完全に停止して
## ください"). Stage 4 raises this back to a small value (0.006, ~7px at
## a 1152px-wide view) once stages 1-3 (motion/size, the enemy-side slash
## effect, and the hit reaction) are each confirmed working on their own.
## This constant is shared by every skill's step-in (not rapid_slash-
## specific), so the value change applies uniformly — there was no
## per-skill step amount to begin with.
const BATTLE_ANIM_SKILL_STEP_FRAC: float = 0.0
const BATTLE_KNOCKBACK_PX: float = 18.0
const BATTLE_BOSS_LUNGE_PX: float = 46.0
const BATTLE_IMPACT_RADIUS_PX: float = 42.0
const COLOR_IMPACT := Color(1.0, 0.95, 0.75)
## 0.35 -> 0.6 (2026-07-20 user feedback: slower, readable flight).
const BATTLE_PROJ_SECONDS: float = 0.6
## Code-drawn fallback bolt (skills with neither proj_key nor proj_frame —
## effectively unused now that every offensive ranged skill has real
## sheet art, kept enlarged to match for whatever falls back to it next).
const BATTLE_PROJ_RADIUS_PX: float = 16.0
## 84 -> 190 (2026-07-20 user request: skills should read as a "big
## move" — party/boss icon sizes (PARTY_ICON_PX/BOSS_ICON_PX) are
## untouched, only the projectile itself grows).
const BATTLE_PROJ_SPRITE_PX: float = 190.0
## Draw width of a proj_key flight clip (height follows the clip's own
## aspect); its wobble loop pace.
## 140 -> 260 (same "big move" request as BATTLE_PROJ_SPRITE_PX above).
const BATTLE_PROJ_KEY_W: float = 260.0
const BATTLE_PROJ_FRAME_SECONDS: float = 0.1
## One full pass of an 8-frame impact_* clip; also the burst decay time.
const BATTLE_IMPACT_SECONDS: float = 0.45
const BATTLE_IMPACT_SPRITE_PX: float = 150.0
## Hit-reaction clip lengths (the pack rows play once over the reaction).
const BATTLE_ENEMY_HIT_SECONDS: float = 0.5
const BATTLE_ALLY_HIT_SECONDS: float = 0.6
const BATTLE_VICTORY_SECONDS: float = 1.6
const VICTORY_POSE_STAGGER_SECONDS: float = 0.07
const BATTLE_HITSTOP_SECONDS: float = 0.07
const BATTLE_SHAKE_SECONDS: float = 0.08
## Keyframed right/left pulse (px, at the reference material's scale) —
## sampled and scaled by BATTLE_SHAKE_SCALE in _battle_shake_offset().
const BATTLE_SHAKE_KEYS: Array[float] = [0.0, 2.0, -6.0, 3.0, 0.0]
const BATTLE_SHAKE_SCALE: float = 1.0
const COLOR_PROJECTILE := Color(1.0, 0.9, 0.55)
## Center-stage x for ally-target (heal/buff) skills — enemy-target
## actions run up to the boss itself instead (2026-07-20 user fix:
## stopping at center stage read as "not going at the opponent"); see
## _battle_anim_destination. y is unused there (feet follow the boss-mode
## ground line dynamically).
const BATTLE_ANIM_CENTER := Vector2(0.55, 0.66)
const BATTLE_ANIM_POPUP_SECONDS: float = 0.8
# Color(1.0,0.35,0.3) -> Color(1.0,0.55,0.25) (新企画v1仕様書 v2 §7,
# 2026-08-21 playtest fix): a real playthrough found the old coral-red
# too muted against the boss backdrop even with its existing dark outline
# (below) — shifted toward orange, which reads as brighter at the same
# saturation. Font size and outline width bumped alongside it in
# _draw_battle_anim_popups (18->22, outline 3->4) for more presence, per
# the same report ("少し存在感を強くする"). Not a rework of the popup
# system itself (unchanged: rise/fade timing, boss-vs-ally positioning).
# 視認性改善（2026-08-22, 実機報告「文字・ダメージ数値が薄い」）: 暖色の
# オレンジは背景/VFXの暖色トーンと衝突して沈みやすいため、通常ダメージ
# （敵本体/部位への被ダメージ、味方が受けたダメージの両方——このコード
# パスは方向を問わず同じ定数を共有している）を強い不透明白へ統一。色に
# よる区別はここではもう行わず、「白＋黒系アウトライン」の一点に絞る。
const COLOR_DAMAGE_POPUP := Color(1.0, 1.0, 1.0)
const COLOR_HEAL_POPUP := Color(0.4, 0.95, 0.5)
## Distinct from COLOR_DAMAGE_POPUP on purpose (新企画v1仕様書 v2 §9): a
## part breaking is a mechanically different moment from ordinary damage
## and needs to read as one at a glance, not just as a slightly bigger
## number. Bright gold rather than red/orange.
const COLOR_PART_BREAK_POPUP := Color(1.0, 0.85, 0.2)
## Lingers longer than a normal hit number (BATTLE_ANIM_POPUP_SECONDS)
## so "部位破壊時...プレイヤーが...確実に認識できる" (§9) isn't lost in a
## fast combo of hits.
const PART_BREAK_POPUP_EXTRA_SECONDS: float = 0.4

## skill_id -> {variant: 0 (protagonist) .. 4 (companion_4/Sayu, matching
## _minion_art_variant's numbering), suffix: the skill_minion_<variant>_
## <suffix> asset name}. A lookup table rather than a naming-convention
## derivation because the shipped sprite-sheet names don't always match
## the skill id spelling (e.g. skill_lif -> "...liv", skill_heitskjoldr ->
## "...heitskjold", skill_shigyaku -> "...shiigyaku" — see CLAUDE.md's
## slice_grid.gd pitfalls). Deliberately omits Madoka's 黄泉軍 (no skill
## json exists for it yet — story-gated, unlock not implemented).
##
## proj_frame (2026-07-20, v3 delivery): every skill clip is now a
## uniform 12-frame format (skill_motions_v3_manifest.json) where column
## index 7 (0-based) is the manifest's declared "impact_frame" — for
## RANGED skills that frame is a big isolated effect with no character
## drawn in it (verified by eye across several skills/characters, e.g.
## 玄火符/エオスバースト), used as the traveling projectile's texture.
## MELEE skills' own index-7 frame instead shows the character mid-swing
## (also verified, e.g. 瞬影斬) — there's nothing to extract, so melee
## and ally-target skills simply omit proj_frame and play the full clip.
## SKILL_MOTION_IMPACT_FRAME is the shared constant (kept as a per-entry
## field, not inlined, so a future skill with a different layout can
## still override it).
##
## cast_hold (2026-07-20, revised 2026-07-21): the LAST frame index where
## the caster is actually still drawn, before the effect takes over.
## Verified by eye per skill (not assumed as "proj_frame - 1"), and —
## critically — checking EVERY frame in the candidate range, not just its
## boundary. The first pass (2026-07-20) only spot-checked the frame
## right before the assumed cutoff and the frame right after it; that
## missed several skills with a character-FREE frame stranded in the
## MIDDLE of an otherwise character-visible run (heitskjoldr's frame 2 is
## a screen-filling wave with no character at all, sandwiched between
## frames 1 and 3-4 which do show Vard — the resulting clip only had 2
## safe frames of real motion, which read as "キャラがその場で平行移動
## して切り替わっただけ", the user's exact 2026-07-21 report). Re-checked
## every frame 0..(old cast_hold) for all 9 ranged skills; genkafu,
## yomotsuhirasaka_dan and heitskjoldr all had the same hidden-hole
## pattern and are lowered here. soul_break/eos_burst/jubaku/kagura were
## re-verified clean (every frame in range does show the character) and
## are unchanged. cast_hold is always the LAST SAFE frame before the
## FIRST bad one — a single hole partway through still cuts the whole
## range short, since caster display can only hold a contiguous prefix.
const SKILL_MOTION_IMPACT_FRAME: int = 7
const SKILL_MOTION: Dictionary = {
	"skill_rapid_slash": {"variant": 0, "suffix": "rapidslash"},
	"skill_healing": {"variant": 0, "suffix": "healing"},
	"skill_soul_break": {
		"variant": 0, "suffix": "soulbreak", "proj_frame": SKILL_MOTION_IMPACT_FRAME,
		"proj_key": "proj_soul_break", "cast_hold": 5},
	# frame index 7 is the same "two spike-bursts side by side with a gap"
	# shape as 弑逆's original frame 7 (same class of bug, user report
	# 2026-07-21: "球が変な切り取られ方してる") — index 8 is one
	# connected, genuinely circular starburst.
	"skill_eos_burst": {
		"variant": 0, "suffix": "eosburst", "proj_frame": 8,
		"cast_hold": 4},
	"skill_shunei_zan": {"variant": 1, "suffix": "shuneizan"},
	"skill_gekka_ranbu": {"variant": 1, "suffix": "gekkarambu"},
	"skill_tsukuyomi": {"variant": 1, "suffix": "tsukuyomi"},
	# 黄泉軍 (2026-07-21, wired for motion testing per user request — NOT
	# properly story-gated: the design doc has this unlocking mid-story
	# ("円編でボス戦直前、記憶を取り戻した際に新たに習得する") but no
	# unlock mechanism exists, so it's just a normal 5th skill in
	# companion_1.json for now. Also a placeholder for the effect itself:
	# the design doc describes a multi-hit/AOE mechanic scaling with enemy
	# count that resolve_boss_round has no support for (single-target
	# only) — this is wired as a plain single-target damage skill so the
	# MOTION can be tested, not the full described mechanic.
	# Frames 1, 2, 6, 8, 9, 10 have no Madoka in them (the summoned army
	# fills the whole cell) — cast_frames keeps just the ones that do.
	# proj_frame was originally 6 (2026-07-21) — re-inspected per user
	# report ("でてくる亡者がすごく変な切り取られ方してる") and found
	# frame 6 is a messy in-between blend (a barely-formed skull poking
	# out of crystal spikes on one side, a tiny sliver of Madoka on the
	# other) — it never reads as "an army", just an odd half-composed
	# blob. Frame 8 is a clean, unambiguous shot of the full ghost-soldier
	# squad marching with no character in it at all — a much better single
	# frame to represent "the summoned dead flying at the enemy".
	"skill_yomogun": {
		"variant": 1, "suffix": "yomogun", "proj_frame": 8,
		"cast_frames": [0, 2, 3, 4, 5, 7]},
	# frame index 2 is entirely effect (no character), but 3 and 4 are 円
	# clearly again (a real mid-spin/thrust pose, verified) — a single
	# cutoff would have thrown those away along with the bad frame, so
	# cast_frames explicitly skips just index 2 instead of stopping there.
	"skill_yomotsuhirasaka_dan": {
		"variant": 1, "suffix": "yomotsuhirasaka", "proj_frame": SKILL_MOTION_IMPACT_FRAME,
		"proj_key": "proj_yomotsuhirasaka", "cast_frames": [0, 1, 3, 4, 5]},
	"skill_heil": {"variant": 2, "suffix": "heil"},
	"skill_lif": {"variant": 2, "suffix": "liv"},
	"skill_skjaldborg": {"variant": 2, "suffix": "skjaldborg"},
	# frame index 2 is a screen-filling orb/wave with no Vard in it at
	# all, between frame 1 (shield up) and frames 3-4 (a real shield-
	# thrust motion, verified — Vard clearly visible, mid-action). The
	# original single-cutoff cast_hold=1 only had frames 0-1 to work
	# with, which barely differ and read as "その場で平行移動しただけ"
	# (user report, 2026-07-21) — skipping just the one bad frame
	# recovers the actual thrust animation instead.
	"skill_heitskjoldr": {
		"variant": 2, "suffix": "heitskjold", "proj_frame": SKILL_MOTION_IMPACT_FRAME,
		"cast_frames": [0, 1, 3, 4]},
	# frame index 4 is an isolated ward/rune symbol, no character — sits
	# between frames 0-3 (character present throughout, a real casting
	# motion) and frame 5 (character again, thrusting the staff/flame
	# forward — also verified). Skip just the rune frame.
	"skill_genkafu": {
		"variant": 3, "suffix": "genkafu", "proj_frame": SKILL_MOTION_IMPACT_FRAME,
		"cast_frames": [0, 1, 2, 3, 5]},
	# 呪縛/呪紋 are mostly-conjured effects (chain / seal) rather than a
	# character swing — the character itself is only in the first few
	# frames before the conjured shape takes over completely.
	"skill_jubaku": {
		"variant": 3, "suffix": "jubaku", "proj_frame": SKILL_MOTION_IMPACT_FRAME,
		"cast_hold": 3},
	# frame index 2 (not just index 3) is already a bare seal symbol, no
	# character — same hidden-hole pattern, one frame earlier than first
	# assumed.
	"skill_jumon": {
		"variant": 3, "suffix": "jumon", "proj_frame": SKILL_MOTION_IMPACT_FRAME,
		"cast_hold": 1},
	# frame index 7 is TWO separate spike-burst shapes side by side with a
	# gap between them — tight-cropping that (correctly) keeps both, but
	# drawn as a single projectile it reads as a lopsided pair of arrows,
	# not the round "球" the user expected ("完全に変な切り取り方に
	# なってる。円になってない", 2026-07-21). Index 9 is one connected,
	# genuinely circular burst — verified by eye and by connected-
	# component analysis (single component, no stray fragments).
	"skill_shigyaku": {
		"variant": 3, "suffix": "shiigyaku", "proj_frame": 9,
		"cast_hold": 5},
	"skill_shoukon": {"variant": 4, "suffix": "shoukon"},
	# 神楽 is the one exception to the uniform impact frame: index 7 still
	# has Sayu herself drawn in it (verified by eye), index 8 is the first
	# frame that's pure effect.
	"skill_kagura": {"variant": 4, "suffix": "kagura", "proj_frame": 8, "cast_hold": 7},
	"skill_hyoui": {"variant": 4, "suffix": "hyoui"},
	"skill_chinkon": {"variant": 4, "suffix": "chinkon"},
}
## Madoka's 黄泉軍 (5th row of her v3 sheet) is sliced to disk as
## skill_minion_1_yomogun but deliberately absent from SKILL_MOTION and
## _battle_motion_keys below — no skill json exists for it yet (story-
## gated: "円編でボス戦直前、記憶を取り戻した際に新たに習得する", no
## unlock mechanism implemented). Add both once that's built.


## Caster element per art variant, per RPG_SYSTEM_DESIGN_v5 §3's
## character-element table (円=闇, ヴァルド=水, 司馬燿=火, サユ=風;
## ソティリス覚醒前=無属性 -> the generic burst; impact_light stays
## reserved for his awakened form, which isn't implemented). Drives which
## impact_* clip a hit plays — the 2026-07-20 asset pack ships one row
## per element.
const VARIANT_IMPACT: Dictionary = {
	0: "impact_generic", 1: "impact_dark", 2: "impact_water",
	3: "impact_fire", 4: "impact_wind",
}


## Every motion sprite key the game might need, for UDArtLibrary.load_default
## (see its class doc). Missing files just mean has_art() stays false and
## playback falls back to the attack/idle sprite — see _skill_motion_key/
## _advance_battle_anim_step. The hit/guard/victory rows, elemental
## impacts, flight projectiles, and standalone enemy sheets all come from
## the 2026-07-20 UNDERDESK_sprite_asset_pack (tools/slice_asset_pack.gd).
## guard_minion_N is registered but has no gameplay hook yet — there is
## no defend command; wire it when one exists.
func _battle_motion_keys() -> Array[String]:
	var keys: Array[String] = []
	for i in 5:
		keys.append("walk_minion_%d" % i)
		keys.append("dash_minion_%d" % i)
		keys.append("attack_minion_%d" % i)
		keys.append("hit_minion_%d" % i)
		keys.append("guard_minion_%d" % i)
		keys.append("victory_minion_%d" % i)
	for skill_id: Variant in SKILL_MOTION:
		keys.append(_skill_motion_key(str(skill_id)))
	# 「新しいスプライトへ置き換え」(2026-08-05) — エオスバースト専用の
	# 6コマ突きシート。既存のSKILL_MOTION/generic機構は経由しない(eos_burst
	# は元々ダメージ・キャストフレームとも自前の専用関数群で処理しており、
	# SKILL_MOTION辞書へ登録する必要が無い)——ArtLibraryへキーだけ直接登録。
	keys.append(EOS_BURST_THRUST_POSE_KEY)
	keys.append(EOS_BURST_DOWNSLASH_POSE_KEY)
	keys.append(EOS_BURST_DOWNSLASH12_POSE_KEY)
	# 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — 納品の
	# 「暗色クリーン化(白縁除去)」12コマシート。UDArtLibraryの標準規約に
	# 合わせて`tools/`で12枚へ切り出し済み(`skill_minion_0_
	# eosdownslash12crisp`)。旧`EOS_BURST_DOWNSLASH12_POSE_KEY`とその定数群
	# は無改修のまま残置(削除しない)——このキーが新たに主導権を持つ。
	keys.append(EOS_BURST_DOWNSLASH12_CRISP_POSE_KEY)
	# 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — 納品の
	# 16コマシート(`sotiris_eos_downslash_16f_current_scale_v25.png`)。12コマ
	# のframe0-5/6-11(=新frame0-5/10-15)は画素単位で継承、新frame6-9だけ
	# 「現行ソティリスの制作条件(頭身・パレット・authoring scale)」で再作画
	# した4コマを追加(headlessで12/12継承フレームがbyte-identicalであること
	# を直接確認済み)。UDArtLibraryの標準規約で16枚へ切り出し済み
	# (`skill_minion_0_eosdownslash16currentscale`)。旧12コマキー
	# (`EOS_BURST_DOWNSLASH12_CRISP_POSE_KEY`)とその定数群は無改修のまま
	# 残置(削除しない)——このキーが新たに主導権を持つ。
	keys.append(EOS_BURST_DOWNSLASH16_POSE_KEY)
	for element in ["generic", "fire", "water", "wind", "light", "dark"]:
		keys.append("impact_%s" % element)
	keys.append("proj_soul_break")
	keys.append("proj_yomotsuhirasaka")
	keys.append(RAPID_SLASH_DUST_KEY)
	keys.append(RAPID_SLASH_CHARGE_KEY)
	for wave_def: Dictionary in RAPID_SLASH_WAVE_DEFS:
		keys.append(str(wave_def["key"]))
	keys.append(RAPID_SLASH_IMPACT_KEY)
	# v17: soul_break's own flying-spear/impact art no longer registers
	# here at all — every soul_break VFX asset (twin-cleave flight,
	# crescent impact, the v16 launch arc) lives outside UDArtLibrary's
	# ART_DIR and loads directly via _soul_break_load_texture instead. The
	# old impact_soul_break.png (18 frames) is no longer referenced
	# anywhere either, so it's dropped from this registration list too.
	# Delivered enemy sheets whose ids have no data/enemies entry yet
	# (穴の徘徊者/迷いの影/守人の追手) plus _hit rows for every enemy id —
	# an enemy json using one of these ids picks its art up automatically.
	keys.append_array([
		"enemy_hole_wanderer", "enemy_hole_wanderer_hit",
		"enemy_lost_shadow", "enemy_lost_shadow_hit",
		"enemy_guardian_pursuer", "enemy_guardian_pursuer_hit",
		"enemy_cave_bat_hit", "enemy_cave_rat_hit",
		"enemy_cave_spider_hit", "enemy_cave_troll_hit",
	])
	for enemy_id in ["hole_wanderer", "lost_shadow", "guardian_pursuer", "cave_troll"]:
		keys.append("enemy_%s_attack" % enemy_id)
		keys.append("enemy_%s_defeat" % enemy_id)
	return keys


func _skill_motion_key(skill_id: String) -> String:
	if not SKILL_MOTION.has(skill_id):
		return ""
	var entry: Dictionary = SKILL_MOTION[skill_id]
	return "skill_minion_%d_%s" % [int(entry["variant"]), str(entry["suffix"])]


## -1 if the skill has no isolated-effect frame reserved for the flying
## projectile (see SKILL_MOTION's proj_frame doc comment).
func _skill_proj_frame(skill_id: String) -> int:
	if not SKILL_MOTION.has(skill_id) or not (SKILL_MOTION[skill_id] as Dictionary).has("proj_frame"):
		return -1
	return int((SKILL_MOTION[skill_id] as Dictionary)["proj_frame"])


## The ordered list of frame indices the caster actually cycles through
## during "act" (2026-07-21, generalizes the old single cast_hold cutoff
## — see SKILL_MOTION's doc comment). Priority: explicit cast_frames list
## (non-contiguous, for skills with a bad frame stranded mid-sequence)
## > cast_hold (a plain 0..N contiguous prefix) > the full clip (melee/
## ally skills, which never lose the character at all).
func _skill_cast_frames(skill_id: String) -> Array[int]:
	var result: Array[int] = []
	if SKILL_MOTION.has(skill_id):
		var entry: Dictionary = SKILL_MOTION[skill_id]
		if entry.has("cast_frames"):
			for v: Variant in (entry["cast_frames"] as Array):
				result.append(int(v))
			return result
		if entry.has("cast_hold"):
			for i in int(entry["cast_hold"]) + 1:
				result.append(i)
			return result
	var full_frames := 0
	if SKILL_MOTION.has(skill_id):
		full_frames = art.frame_count(_skill_motion_key(skill_id))
	if full_frames <= 0:
		full_frames = 12
	for i in full_frames:
		result.append(i)
	return result

@onready var tick_timer: Timer = $TickTimer
@onready var autosave_timer: Timer = $AutosaveTimer


func _ready() -> void:
	settings = UDSettings.load_settings()
	locale = UDLocale.load_locale(settings.locale_code)
	doc_db = UDDocumentDB.load_from_dir("res://data/documents")
	facility_db = UDShopDB.load_from_dir("res://data/facilities")
	item_db = UDItemDB.load_from_dir("res://data/items")
	weapon_db = UDShopDB.load_from_dir("res://data/weapons")
	enemy_db = UDEnemyDB.load_from_dir("res://data/enemies")
	stage_db = UDStageDB.load_from_dir("res://data/stages")
	skill_db = UDSkillDB.load_from_dir("res://data/skills")
	doc_series = UDDataLoader.load_json_dir("res://data/series")
	var series_ids: Array[String] = []
	for def: Variant in doc_series:
		series_ids.append(str((def as Dictionary)["id"]))
	art = UDArtLibrary.load_default(
		facility_db.all_ids(), item_db.all_ids(), [], doc_db.all_ids(),
		series_ids, enemy_db.all_ids(), weapon_db.all_ids(), _battle_motion_keys()
	)
	achievements = UDAchievements.load_default(UDPlatform.create())
	companion_defs = UDDataLoader.load_json_dir("res://data/companions")
	for companion: Variant in companion_defs:
		_companion_by_id[(companion as Dictionary)["id"]] = companion

	var payload := UDSaveManager.load_game()
	if payload.is_empty():
		sim = UDSim.new_game(
			enemy_db, stage_db, int(Time.get_unix_time_from_system()),
			item_db.all_ids(), companion_defs, doc_db.conditions_by_id(),
			item_db.ranks_by_id(), skill_db, weapon_db
		)
	else:
		sim = UDSim.from_dict(
			payload["sim"], enemy_db, stage_db, item_db.all_ids(), companion_defs,
			doc_db.conditions_by_id(), item_db.ranks_by_id(), skill_db, weapon_db
		)
	_connect_sim_signals()
	if not payload.is_empty():
		_offline_gold_before = int(sim.inventory.get(UD.RES_GOLD, 0))
		_offline_exp_before = sim.exp_pool
		offline_ticks_applied = UDOffline.elapsed_ticks(
			int(payload["saved_unix_time"]),
			int(Time.get_unix_time_from_system())
		)
		sim.advance(offline_ticks_applied)
		if offline_ticks_applied > 0:
			_tally_text = _format_offline_summary()
			_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 4

	tick_timer.wait_time = UD.TICK_SECONDS
	tick_timer.timeout.connect(_on_tick)
	tick_timer.start()
	var anim_timer := Timer.new()
	anim_timer.wait_time = ANIM_FRAME_SECONDS
	anim_timer.autostart = true
	anim_timer.timeout.connect(_on_anim_tick)
	add_child(anim_timer)
	# Not autostart: only runs during the ~1s slide right after a kill
	# (_start_bg_transition/_on_bg_transition_tick), so it costs nothing
	# while idle between kills.
	_bg_transition_timer = Timer.new()
	_bg_transition_timer.wait_time = 1.0 / BG_TRANSITION_FPS
	_bg_transition_timer.timeout.connect(_on_bg_transition_tick)
	add_child(_bg_transition_timer)
	# Not autostart: only runs while a battle-motion step is actually
	# playing back (_advance_battle_anim_step starts it, _finish_battle_round
	# stops it), same idle-cost-zero pattern as _bg_transition_timer above.
	_battle_anim_timer = Timer.new()
	_battle_anim_timer.wait_time = 1.0 / BATTLE_ANIM_FPS
	_battle_anim_timer.timeout.connect(_on_battle_anim_tick)
	add_child(_battle_anim_timer)
	autosave_timer.wait_time = UD.AUTOSAVE_INTERVAL_SECONDS
	autosave_timer.timeout.connect(func() -> void: UDSaveManager.save_game(sim))
	autosave_timer.start()

	_build_rapid_slash_sfx()
	_build_healing_sfx()
	_build_soul_break_sfx()
	_build_eos_burst_sfx()
	_build_hud()
	_build_boss_banner()
	_build_battle_bar()
	_build_battle_list_panel()
	_build_quit_battle_button()
	_build_leave_battle_button()
	_build_rewind_confirm_panel()
	_build_archive_dialog()
	_build_treasure_dialog()
	_build_shop_dialog()
	_build_altar_dialog()
	_build_guild_dialog()
	_build_dorm_dialog()
	_build_inn_view()
	_refresh_button_texts()
	_apply_window_mode()
	# A save written mid-boss-fight (boss_active true) otherwise reopens to
	# an unbroken-looking but blank battle view: _draw_battle() only runs
	# when not boss_active, and nothing else shows the fight without a
	# click on "挑む" the player has no reason to make from a cold start.
	if sim.boss_active:
		_show_boss_panel()
	queue_redraw()


## v13, soul_break only (user spec: "位置は...毎描画フレーム更新する").
## This project otherwise deliberately avoids a per-frame _process() loop
## (CLAUDE.md §7.1's "描画は tick 毎の queue_redraw のみ" idle-CPU budget)
## — this is a narrow, explicit exception scoped to ONLY the ~0.48s window
## while soul_break's own projectile is actually flying, elsewhere a
## single cheap guard call (_soul_break_vfx_active(), already called every
## tick-driven redraw regardless) makes this a no-op. _battle_anim_phase_
## elapsed itself stays tick-quantized (unchanged, still read by
## everything else in this file); only _soul_break_proj_flight_elapsed
## advances continuously, and only position (never the shell/fragment
## frame-loop, per "位置移動は別管理にする") reads it — see
## _draw_soul_break_flight.
func _process(delta: float) -> void:
	# soul_break's own block — restructured from early-returns to a nested
	# `if` (2026-08-06, so an unrelated eos_burst block below can run on the
	# same call regardless of soul_break's own state) but behaviorally
	# identical to the prior early-return shape: every failing condition
	# still sets `_soul_break_proj_flight_active = false` and skips the
	# sync/accumulate/redraw below it.
	if _soul_break_vfx_active():
		var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
		if str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID:
			var elapsed := _battle_anim_phase_elapsed
			if elapsed >= SOUL_BREAK_LAUNCH_SECONDS and elapsed < SOUL_BREAK_FLIGHT_END_SECONDS:
				if not _soul_break_proj_flight_active:
					_soul_break_proj_flight_active = true
					# Sync to the tick-based value at the instant flight is
					# first detected (could already be up to 1 tick in,
					# since this check itself only runs once per rendered
					# frame) rather than snapping to 0 — avoids a visible
					# backward jump on the very first frame.
					_soul_break_proj_flight_elapsed = elapsed - SOUL_BREAK_LAUNCH_SECONDS
				else:
					_soul_break_proj_flight_elapsed = minf(
						_soul_break_proj_flight_elapsed + delta, SOUL_BREAK_FLIGHT_SECONDS)
				queue_redraw()
			else:
				_soul_break_proj_flight_active = false
		else:
			_soul_break_proj_flight_active = false
	else:
		_soul_break_proj_flight_active = false
	# 「動きのカクつきを根本修正する」(2026-08-06) — root cause diagnosis:
	# `_battle_anim_phase_elapsed`自体は`_battle_anim_timer`(BATTLE_ANIM_
	# FPS=20、timeoutでのみ)でしか進まない。位置カーブ自体は元々elapsedの
	# 純粋関数(段階的更新ではない)だったが、供給される"elapsed"が20fps
	# 刻みだったため結果的に20fpsでサンプリングしたカクついた動きになって
	# いた——README実測の「33〜50ms刻み」の直接原因。soul_breakの飛翔体
	# (上のブロック)と全く同じパターン: eos_burst active中だけ実deltaで
	# 連続進行するelapsedを維持し、毎フレームqueue_redraw()する。フェーズ
	# 境界の判定・ヒットストップ・接触・SFX・ダメージは引き続き
	# `_battle_anim_phase_elapsed`(tick基準)で駆動されるため無影響——
	# 詳細は`_eos_burst_smooth_elapsed`とその呼び出し元(`_eos_burst_
	# advance_offset_px`等)を参照。非アクティブ中は`_eos_burst_vfx_active()`
	# の即時false判定だけの安価なチェックなので、CLAUDE.md §7.1のアイドル
	# CPU予算には影響しない。
	if _eos_burst_vfx_active():
		if not _eos_burst_smooth_root_active:
			_eos_burst_smooth_root_active = true
			_eos_burst_smooth_root_elapsed_value = _battle_anim_phase_elapsed
		else:
			_eos_burst_smooth_root_elapsed_value += delta
		# 「Professional Mix / Impact Polish v1」(2026-08-07) — EosBuild/
		# EosReleaseのduckを同じ連続elapsed駆動で毎フレーム書き戻す(別
		# Timerを新設せず、既に確立済みのこの`_process`連続更新へ相乗り)。
		_eos_burst_set_bus_duck_db(_eos_burst_bus_duck_db())
		queue_redraw()
	else:
		if _eos_burst_smooth_root_active:
			# Fires exactly once, on the frame eos_burst's own act phase
			# actually ends — a safety net for an interrupted cast (mirrors
			# _reset_eos_burst_state's own explicit "必ず元へ戻す" pattern).
			# Normally the recovery ramp above already reaches 0dB well
			# before this branch is ever reached. Guarding on the flag
			# (rather than calling every idle frame forever) keeps this
			# AudioServer-touching call out of the CLAUDE.md §7.1 idle-CPU
			# budget entirely once the skill is done.
			_eos_burst_set_bus_duck_db(0.0)
		_eos_burst_smooth_root_active = false


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			if sim != null:
				UDSaveManager.save_game(sim)
		NOTIFICATION_APPLICATION_FOCUS_IN:
			UDResidentWindow.apply_focus_fps(true)
			RenderingServer.render_loop_enabled = true
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			UDResidentWindow.apply_focus_fps(false)


## Advances UI-side sprite animation only; the simulation is untouched.
## 「エオスバースト演出全面刷新」(2026-08-11) — 「味方、敵、背景の通常
## アニメーションを停止します」——`_anim_frame`はidleループ全般(仲間の
## 待機モーション・敵・ダンジョン背景)が共有する単一のグローバルカウンタ
## なので、Eos Burst中はこれの増分だけを止める(演出自体は`_battle_anim_
## phase_elapsed`という別のクロックで進むため無関係)。
func _on_anim_tick() -> void:
	if not _eos_burst_vfx_active():
		_anim_frame += 1
	if _battle_phase == "targetSelection" and _battle_target_kind == "enemy":
		_update_target_hp_bar_glow()
	queue_redraw()


## The boss HP bar itself is a real ProgressBar (_boss_banner_hp_bar, in
## the top banner), not part of the immediate-draw crosshair overlay, so
## its "glow" during target selection is a stylebox swap here instead.
## 視認性改善（2026-08-22）: 旧来は_draw_target_cursorと同じsin波で0.10〜
## 1.00の間を明滅させていた——「選択中は常時表示、点滅禁止」の指示に
## 従い固定値へ変更。呼び出し元(_on_anim_tick)は変更しない（毎tick同じ
## 値を再設定するだけなので実害はなく、既存の周期処理に相乗りする方が
## 新たなタイマー/呼び出し経路を増やすより安全）。
func _update_target_hp_bar_glow() -> void:
	_style_bar(_boss_banner_hp_bar, COLOR_HP_BAR_BG, COLOR_TARGET_CURSOR)


func _reset_boss_hp_bar_glow() -> void:
	_style_bar(_boss_banner_hp_bar, COLOR_HP_BAR_BG, COLOR_ENEMY_HP_BAR)


func _on_tick() -> void:
	# Snapshot the idle backdrop before ticking: if a kill lands this tick
	# and moves stage_index into the next seg1/seg2/normal phase, slide to
	# it instead of popping straight to the new picture. _draw_enemy stays
	# hidden for as long as _bg_transition_active holds regardless of how
	# many ticks that spans, so a fast-killing party queuing several
	# slides back to back (_start_bg_transition) never reveals a trash
	# mob mid-transition.
	# _boss_screen_active, not sim.boss_active: while the final round of a
	# fight is still animating, boss_active is already false but the boss
	# screen is up — starting an idle backdrop slide under it would then
	# play a stale half-finished transition when the idle view returns.
	var was_idle := not _boss_screen_active()
	var prev_idle_key := _idle_bg_key() if was_idle else ""
	sim.tick()
	if was_idle and not _boss_screen_active():
		var new_idle_key := _idle_bg_key()
		if new_idle_key != prev_idle_key:
			_start_bg_transition(prev_idle_key, new_idle_key)
	if not settings.tutorial_seen and sim.tick_count >= UD.TUTORIAL_TICKS:
		settings.tutorial_seen = true
		settings.save()
	var fresh_achievements := achievements.evaluate(sim)
	if not fresh_achievements.is_empty():
		achievements.save()
	for ach_id in fresh_achievements:
		var ach_name := ach_id
		for def: Variant in achievements.defs:
			if str((def as Dictionary)["id"]) == ach_id:
				ach_name = locale.text((def as Dictionary)["name_key"])
				break
		_tally_text = locale.text("UI_ACHIEVEMENT") % ach_name
		_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.distinct_items()]
	_refresh_fight_button()
	if _inn_view != null and _inn_view.visible:
		_refresh_inn_activities()
	UDResidentWindow.sync_render_loop(get_window())
	queue_redraw()


func _connect_sim_signals() -> void:
	sim.document_discovered.connect(_on_document_discovered)


func _on_document_discovered(doc_id: String) -> void:
	unread_docs.append(doc_id)
	_refresh_archive_button()


func _gui_input(event: InputEvent) -> void:
	if settings.resident_mode:
		# The strip is ambient: any click opens the management window.
		if event is InputEventMouseButton and event.pressed:
			_expand()
		return
	# Click-to-target (2026-07-19): only fires for clicks the target-confirm
	# panel's own buttons didn't already consume, i.e. clicks landing on
	# the enemy itself. _boss_icon_rect keeps this in sync with wherever
	# the icon is actually drawn. Ally-target clicks are handled by the
	# party cards themselves (_on_battle_card_input), not here.
	if _battle_phase == "targetSelection" and _battle_target_kind == "enemy" \
			and event is InputEventMouseButton \
			and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var click_pos: Vector2 = (event as InputEventMouseButton).position
		if _boss_icon_rect(_view_rect()).has_point(click_pos):
			var targets := _battle_enemy_targets()
			if not targets.is_empty():
				_battle_selected_target_id = targets[0]
				_refresh_target_panel()
				queue_redraw()


## Any of the 6 card-catalogue screens (archive/treasure/shop/altar/guild/
## dorm) that might currently be open full-screen — see UDCardDialog's
## 2026-07-19 Window -> Control conversion. A real popup Window used to
## eat ESC itself before it ever reached here; now that they're embedded
## Controls in this same window, _unhandled_input has to close whichever
## one is open explicitly instead of falling through to _collapse().
func _open_card_dialogs() -> Array[UDCardDialog]:
	return [
		_archive_dialog, _treasure_dialog, _shop_dialog,
		_altar_dialog, _guild_dialog, _dorm_dialog,
	]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		if _inn_view != null and _inn_view.visible:
			_inn_view.hide()
			return
		for dialog in _open_card_dialogs():
			if dialog.visible:
				dialog.hide()
				return
		if not settings.resident_mode:
			_collapse()
	if _battle_phase == "targetSelection" and event is InputEventKey and event.pressed:
		var keycode := (event as InputEventKey).keycode
		if keycode == KEY_LEFT:
			_cycle_target_selection(-1)
		elif keycode == KEY_RIGHT:
			_cycle_target_selection(1)
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_F9:
		_debug_boss_loop = not _debug_boss_loop
		queue_redraw()


## The strip has no HUD bar: the battle view uses the full height.
func _hud_offset() -> int:
	return 0 if settings.resident_mode else HUD_HEIGHT


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COLOR_BACKGROUND)
	if sim == null:
		return
	_draw_hud()
	if not _boss_screen_active():
		_draw_battle()
	elif not settings.resident_mode:
		# The resident strip stays plain during a boss fight (its whole
		# layout is getting redesigned separately); the expanded window
		# shows the boss arena behind the command panel.
		_draw_boss_battle()


const STRIP_FONT_SIZE: int = 11
const STRIP_BADGE := Color(1.0, 0.85, 0.3)
const STRIP_TEXT_BG := Color(0.0, 0.0, 0.0, 0.45)


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	if settings.resident_mode:
		_draw_strip_overlay(font)
		return
	# The battle screen (boss banner + card bar) replaces the whole HUD
	# readout — no stage/coin/EXP/tick text, no achievement/tutorial
	# banners layered over it (user direction, 2026-07-19).
	if _boss_screen_active():
		return
	var parts: Array[String] = [
		locale.text("APP_TITLE"),
		"%s %d" % [locale.text("RES_GOLD"), int(sim.inventory[UD.RES_GOLD])],
		"%s %d/%d" % [locale.text("UI_TREASURES"), sim.distinct_items(), item_db.all_ids().size()],
		"⛏ %d" % sim.minions.size(),
		"%s %d" % [locale.text("UI_STAGE"), sim.stage_index],
		"EXP %d" % sim.exp_pool,
		"tick %d" % sim.tick_count,
	]
	if offline_ticks_applied > 0:
		parts.append(locale.text("UI_OFFLINE_REPORT") % offline_ticks_applied)
	draw_string(
		font, Vector2(8, HUD_HEIGHT - 6), "  |  ".join(parts),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, HUD_FONT_SIZE, COLOR_HUD_TEXT
	)
	if _tally_text != "" and sim.tick_count <= _tally_until_tick:
		draw_string(
			font, Vector2(8, HUD_HEIGHT + 20), _tally_text,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 16, STRIP_BADGE
		)
	if _tutorial_active():
		draw_string(
			font, Vector2(8, size.y - 10), _tutorial_hint(),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 16, STRIP_BADGE
		)


## First-run only (§10): the pitch is that leaving the game alone is
## correct play, so the hints rotate quietly instead of interrupting.
func _tutorial_active() -> bool:
	return not settings.tutorial_seen and sim.tick_count < UD.TUTORIAL_TICKS


func _tutorial_hint() -> String:
	var index := int(sim.tick_count / UD.TUTORIAL_HINT_CYCLE_TICKS) \
		% UD.TUTORIAL_HINT_KEYS.size()
	return locale.text(UD.TUTORIAL_HINT_KEYS[index])


func _draw_strip_overlay(font: Font) -> void:
	var gate := " ⚠" if stage_db.is_boss_stage(sim.stage_index) else ""
	var text := "$%d  ステージ%d%s  ⛏%d" % [
		int(sim.inventory[UD.RES_GOLD]), sim.stage_index, gate, sim.minions.size(),
	]
	var text_width := font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT_SIZE
	).x
	draw_rect(Rect2(Vector2.ZERO, Vector2(text_width + 12, 16)), STRIP_TEXT_BG)
	draw_string(
		font, Vector2(6, 12), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT_SIZE, COLOR_HUD_TEXT
	)
	if not unread_docs.is_empty() and sim.tick_count % 2 == 0:
		draw_rect(Rect2(Vector2(size.x - 20, 4), Vector2(12, 12)), STRIP_BADGE)
	if _tutorial_active():
		var hint := _tutorial_hint()
		var hint_width := font.get_string_size(
			hint, HORIZONTAL_ALIGNMENT_LEFT, -1, STRIP_FONT_SIZE
		).x
		var hint_y := size.y - 14
		draw_rect(Rect2(Vector2(0, hint_y), Vector2(hint_width + 12, 14)), STRIP_TEXT_BG)
		draw_string(
			font, Vector2(6, hint_y + 11), hint,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, STRIP_FONT_SIZE, STRIP_BADGE
		)


## --- Idle battle view (no boss fight active) -------------------------
## A simple readout of the auto-battle loop: the current trash mob (icon
## + HP bar) and the party roster (portrait + HP/MP bar + level). Not
## interactive — the only input here is "click the strip to expand".

const ENEMY_ICON_PX: int = 96
const BOSS_ICON_PX: int = 176
const PARTY_ICON_PX: int = 64
## 「戦闘中の仲間キャラクター全体の表示サイズを見直す」(2026-08-02) —
## 唯一の共有スケール値。5人共通・全モーション共通（待機/被弾/通常攻撃/
## スキル/移動/帰還）で、これ以外の場所でキャラクターサイズを個別に
## いじらないこと。「戦闘中」限定（`_boss_screen_active()`のときだけ
## 適用、放置画面のPARTY_FORMATION/idle表示は今回のスコープ外につき
## 無改修）——`_ally_battle_icon_px()`経由でのみ参照する。
## ALLY_BATTLE_SCALE = 現在値(PARTY_ICON_PX=64) × 1.5 = 96px、ユーザー
## 指定の目標「通常キャラの見た目の高さ約90〜105px」の範囲内。
const ALLY_BATTLE_SCALE: float = 1.5
## Fixed draw size for a skill's own motion clip specifically (2026-07-24
## redesign), separate from PARTY_ICON_PX which every OTHER motion (idle/
## walk/dash/attack) still uses. Deliberately a plain constant, not a
## per-character or per-frame calculation — get_used_rect()-driven scaling
## (content height/bottom) was tried and reverted twice: it made a
## crouching or wide-effect frame compute a different draw size than a
## standing one, which is exactly the "shrinks/pops" flicker this whole
## saga was about. Every skill_minion_* frame is the same 222x222 canvas
## drawn at this same fixed size, always — a small frame looking smaller
## on-screen (e.g. a crouched pose) is correct, not a bug.
## 「表示サイズ見直し」(2026-08-02) — 旧来はPARTY_ICON_PXと独立した
## 別定数だった（64 vs 96、通常/スキルで別倍率という状態そのものが
## 今回ユーザーが明示的に禁止した"モーションごとに別倍率"の実例だった）。
## `_ally_battle_icon_px()`から導出する形に変更し、通常表示とスキル表示が
## 完全に同じ共有ボックスサイズを使うよう統一した。
const SKILL_ACTOR_DRAW_SIZE: float = 96.0


## 「共有VisualRootを拡大」(2026-08-02) — `_draw_party_row`の通常branch・
## skill_minion_ branchの両方がこの1つの関数だけを参照する。戦闘中
## (`_boss_screen_active()`)はPARTY_ICON_PX×ALLY_BATTLE_SCALE、それ以外
## (放置画面の idle party row)は今回のスコープ外につき従来のPARTY_ICON_PX
## のまま——足元(feet_y)はどちらの場合も不変、ボックスは常に
## `top = feet_y - icon_px`で上方向にのみ伸びるため、拡大の中心は自動的に
## 「画像中央」ではなく「足元」になる(ユーザー要求「拡大の中心を画像中央に
## しないでください...足の接地点が動かないように」を式の構造そのもので
## 満たす)。
func _ally_battle_icon_px() -> float:
	if _boss_screen_active():
		return float(PARTY_ICON_PX) * ALLY_BATTLE_SCALE
	return float(PARTY_ICON_PX)
const BAR_HEIGHT: int = 6
## Where the chapter-0 backgrounds' paved floor sits, as a fraction of
## the view height. Enemy/party icons plant their feet around here
## instead of floating over the scenery.
const GROUND_FRAC: float = 0.78
const SIDE_MARGIN_FRAC: float = 0.14
## Party formation, one (x_frac, feet_y_frac) per slot, matching the
## user's placement reference (ボス戦仲間配置.png): a loose two-row
## cluster on the left half - protagonist front and closest to the
## enemy, two flankers low behind, two more further back and higher
## (reads as depth). Used by both the idle view and the boss arena;
## drawn back-to-front so nearer sprites overlap farther ones.
## Slot index here is sim.minions' array position, i.e. raw join order —
## NOT the fixed companion_1..4 seating UD.BATTLE_CARD_COMPANION_ORDER
## gives the card row. Join order depends on which companion's
## join_at_docs threshold is crossed first for a given save, so which
## character actually stands in "slot 2" varies. (Verified 2026-07-19 via
## a debug script against the dev save: slot1=Madoka, slot2=Vard,
## slot3=Shiba Yao, slot4=Sayu for that save specifically.)
const PARTY_FORMATION: Array[Vector2] = [
	Vector2(0.36, 0.78),  # slot 0: protagonist, point position
	Vector2(0.27, 0.84),  # slot 1: front row, left of the protagonist
	Vector2(0.28, 0.63),  # slot 2: back row, center (swapped w/ slot 4 below,
	# 2026-07-19 user report: whoever was here read as "front row" and
	# wanted to trade places with whoever was in the back-row-center slot)
	Vector2(0.19, 0.66),  # slot 3: back row (higher = further away)
	Vector2(0.14, 0.80),  # slot 4: far left flank (was slot 2's spot)
]
## Boss-only Y values (originally the same x per slot as PARTY_FORMATION —
## only depth needed retuning). A uniform pixel lift (still used for the
## boss creature itself, see _ground_y) was tried first: it correctly
## grounded the front three (slots 0/1/4) but over-lifted the back two
## (2/3, Vard and Shiba Yao that save) off the visible pavement, since they
## had more clearance to begin with and didn't need the full shift (user
## report, 2026-07-19, round 2). These are hand-placed instead: front three
## kept at the values the uniform lift already got right, back two brought
## down near them with a deliberately narrower gap ("少し狭くしてもいい"
## — user said narrowing the party's depth spread was fine).
## 「表示サイズ見直し」(2026-08-02) — 仲間5人の戦闘中表示サイズが64→96px
## (ALLY_BATTLE_SCALE=1.5)へ拡大されたのに伴い、上の「同じxをPARTY_
## FORMATIONと共有」という前提が崩れる(旧64px前提の間隔だと拡大後の
## スプライト/HPバーが重なる) — このラウンドから x/y ともPARTY_FORMATION
## と完全に独立した専用値へ。全5点の重心を軸に水平方向へ×1.5(スプライト幅
## の拡大率と一致させ、隙間の相対比率を保ったまま拡大)、奥行き方向へ×1.2
## (「前列と後列の奥行きを残す」——スプライトが縦にも伸びた分、深さの
## 分離も少し強める)だけ広げた——ソティリス(slot 0、"point position")の
## 位置が大きく動かないよう、拡大の中心は個々の点ではなく全体の重心。
const PARTY_FORMATION_BOSS: Array[Vector2] = [
	Vector2(0.416, 0.651),  # slot 0 (protagonist, point position)
	Vector2(0.281, 0.723),  # slot 1 (front row, left)
	Vector2(0.296, 0.579),  # slot 2 (back row, center)
	Vector2(0.161, 0.604),  # slot 3 (back row, far)
	Vector2(0.085, 0.675),  # slot 4 (far left flank)
]


## The boss arena is a genuine full-window view (2026-07-19: was still
## reserving the HUD strip and the right-side button panel's width even
## though both are hidden during a fight, leaving a black gap on the top
## and right — and squeezing the party formation into that narrower area
## cut off one member). The idle view keeps reserving PANEL_WIDTH/HUD_HEIGHT
## since the button panel and HUD text are actually showing there.
## "The boss battle screen should be showing": the fight itself is live,
## OR its final round is still being played back by the motion sequencer
## (sim.boss_active already false on a decided round — see
## _battle_playback_active's comment). Every boss-vs-idle presentation
## switch must use this, never sim.boss_active directly.
func _boss_screen_active() -> bool:
	return sim.boss_active or _battle_playback_active


func _view_rect() -> Rect2 :
	if _boss_screen_active() and not settings.resident_mode:
		return Rect2(Vector2.ZERO, size)
	var view_right := size.x if settings.resident_mode else size.x - float(PANEL_WIDTH)
	var view_top := float(_hud_offset())
	return Rect2(Vector2(0, view_top), Vector2(view_right, size.y - view_top))


## Boss mode's view is the full window (see above), but the battle command
## bar (card row + attack/skill/item/start, ~168px — see _build_battle_bar)
## permanently covers its bottom edge. GROUND_FRAC/PARTY_FORMATION were
## tuned against the whole window height, so computing feet positions
## straight off `view` put them at or below the bar — Sotiris's lower body
## clipped, Madoka and Vard almost entirely hidden behind it (user report,
## 2026-07-19).
##
## First fix attempt shrank the view passed to the positioning math, which
## solved the clipping but broke ground alignment: it rescales the
## fraction-to-pixel mapping, so feet no longer land where GROUND_FRAC's
## fraction actually places the backdrop's paved floor — characters read
## as floating (second user report, same day). A uniform pixel lift fixed
## the boss creature (still applied below, via _ground_y -> _boss_icon_rect,
## so the crosshair and click-hit-test agree automatically) but was wrong
## for the party: it over-lifted whichever two units sit furthest back in
## PARTY_FORMATION, since they had more clearance to begin with and didn't
## need the full shift (third report, round 2) — party positioning now
## uses hand-tuned PARTY_FORMATION_BOSS instead, see its comment.
const BOSS_FEET_LIFT_PX: float = 85.0


func _draw_battle() -> void:
	var view := _view_rect()
	if _bg_transition_active:
		_draw_backdrop_transition(view)
	else:
		_draw_backdrop(view, _idle_bg_key(), view)
	_draw_enemy(view)
	_draw_party_row(view)


## The boss arena: same composition as the idle view (party formation
## left, opponent right) but on the boss background, with the gate's
## boss drawn large. The turn-command panel floats over this.
## Right2→left6→right3→origin over BATTLE_SHAKE_SECONDS (2026-07-21
## reference-material curve). Purely additive to the LOCAL `view` used
## for drawing in _draw_boss_battle — _view_rect() itself (used
## separately by _gui_input for click hit-testing) is never touched, so
## the shake never throws off target selection.
func _battle_shake_offset() -> float:
	if _battle_shake_t <= 0.0:
		return 0.0
	var phase := clampf(1.0 - _battle_shake_t / _battle_shake_duration, 0.0, 0.999)
	var seg := phase * float(BATTLE_SHAKE_KEYS.size() - 1)
	var idx := int(seg)
	var frac := seg - float(idx)
	var raw := lerpf(BATTLE_SHAKE_KEYS[idx], BATTLE_SHAKE_KEYS[idx + 1], frac)
	# BATTLE_SHAKE_KEYS' own peak is -6px at BATTLE_SHAKE_SCALE=1.0 — scale
	# by the requested peak's ratio to that so an override (currently only
	# rapid_slash, see RAPID_SLASH_SHAKE_PEAK_PX) reshapes the same curve
	# to a smaller/larger magnitude instead of needing its own keyframes.
	return raw * (_battle_shake_peak_px / 6.0) * BATTLE_SHAKE_SCALE


func _draw_boss_battle() -> void:
	var view := _view_rect()
	var eos_active := _eos_burst_vfx_active()
	var eos_unit_id := 0
	if eos_active:
		var eos_entry: Dictionary = _battle_anim_queue[_battle_anim_step]
		eos_unit_id = int(eos_entry.get("unit_id", 0))
	# 「着弾『大爆発』強化 v3」(2026-08-06) — `_battle_shake_offset()`
	# (共有・水平のみ)に、eos_burst着弾専用の2D揺れ`_eos_burst_mega_
	# shake_offset()`を加算する。着弾以外のスキルの揺れには一切影響しない
	# (eos_burst以外は`_eos_burst_mega_shake_offset()`が常にVector2.ZEROを
	# 返すため、かつeos_burst自身の着弾トリガーは共有shake_seconds/peak_pxに
	# 0.0を渡すため`_battle_shake_offset()`自体も着弾の瞬間は寄与しない
	# ——「既存の弱いshakeと二重に重ねない」を、共有機構を無効化した上で
	# 専用の2D関数だけを足す形で満たす)。両方ともview.positionへの単純な
	# 加算に留めているため、これらを使う全ての描画呼び出し(背景・敵・竜・
	# パーティ・`_eos_burst_impact_point`)が一体で動く一方、HP/コマンド等の
	# UIは元々このローカルview外の実Controlノードのため無関係のまま。
	var shake := _battle_shake_offset()
	var mega_shake := _eos_burst_mega_shake_offset()
	if shake != 0.0 or mega_shake != Vector2.ZERO:
		view = Rect2(view.position + Vector2(shake, 0.0) + mega_shake, view.size)
	# 「カメラを約1.08倍まで寄せ、ソティリスと攻撃対象が戦闘画面の中央へ
	# 入るようにする。突進中はカメラをソティリスへ追従させる」——
	# draw_set_transformでこの関数の残り全ての描画呼び出しをズームする。
	# pivotを中心に保つには position=pivot*(1-scale)(screen_result =
	# pivot + scale*(local_pos - pivot)の変形)。関数の最後で必ずidentity
	# へ戻す——このNode(self)がここより後に何も描かない呼び出し順(_draw()
	# 内でboss battleが最後の分岐)なので、他の描画への影響は無い。
	var zoom := 1.0
	if eos_active:
		zoom = _eos_burst_zoom_scale(_battle_anim_phase_elapsed)
	if zoom != 1.0:
		var pivot := _eos_burst_zoom_pivot(view, eos_unit_id, _battle_anim_phase_elapsed)
		draw_set_transform(pivot * (1.0 - zoom), 0.0, Vector2(zoom, zoom))
	_draw_backdrop(view, _chapter_bg_key("boss"), view)
	# Eos Burst's dim sits directly on the chapter backdrop and UNDER the
	# enemy/characters, so it darkens only the background — the package
	# forbids replacing or hiding the chapter art itself.
	_draw_eos_burst_dim(view)
	# 「突進frame2〜4の間だけ、戦闘背景へ速度線」——ソティリス・竜・敵より
	# 後ろ(背景の直後)に描く。
	if eos_active:
		_draw_eos_burst_speed_lines(view, _battle_anim_phase_elapsed)
	_draw_boss_enemy(view)
	_draw_rapid_slash_dust(view)
	_draw_healing_ground_vfx(view)
	# Dragon: behind the party row, so the caster always reads in front of
	# it (package: "DragonAnchor：ソティリスより後ろ、戦闘背景より前").
	_draw_eos_burst_back_vfx(view)
	_draw_party_row(view)
	# 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「②
	# オーラがソティリスの身体や地面に出ている。剣の刃だけにまとわせたい」
	# ——旧`_draw_eos_burst_charge_aura`(身体周囲の円+柱)と`_draw_eos_
	# burst_body_core_aura`(体表から噴き出す金色ドット層)の呼び出しを
	# ここから完全に削除した(関数本体・定数は無改修のまま残置、削除しない
	# ——このファイル全体の「使わなくなったコードは呼び出しだけ外す」慣習
	# のまま、active参照を0にする)。新しい剣追従オーラ(`_draw_eos_burst_
	# sword_aura`)は参照実装の`SwordAuraRoot.z_index = motion.z_index + 1`
	# (=常にキャラクター本体より前面)に対応するため、`_draw_party_row`
	# (Sotiris本人)の直後——旧アオーラが担っていた「party_rowの直前」位置
	# から意図的に入れ替えた。剣は腕の一部として体の輪郭内に収まるため、
	# 先に体を描いてからその上に発光を重ねないと、透明でない胴体ピクセル
	# に発光が隠れてしまう。
	if eos_active:
		_draw_eos_burst_sword_aura(view, eos_unit_id, _battle_anim_phase_elapsed)
	if _battle_phase == "targetSelection" and _battle_target_kind == "enemy":
		_draw_target_cursor(view)
	_draw_battle_projectile(view)
	_draw_battle_impact(view)
	_draw_rapid_slash_vfx(view)
	_draw_healing_caster_vfx(view)
	_draw_soul_break_vfx(view)
	_draw_eos_burst_front_vfx(view)
	_draw_battle_anim_popups(view)
	if _battle_screen_flash_t > 0.0:
		draw_rect(view, Color(1.0, 1.0, 1.0, _battle_screen_flash_alpha))
	# 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — 旧・独立した早期
	# フラッシュ(`_draw_eos_burst_slash_flash`、旧12コマ斬撃の到達時刻
	# 基準)は完全に削除した——TIMELINE_V8.csv「4.78,4.86,screen_flash」の
	# 単一の「接触時だけ短い反転フラッシュ」は、GrandCrescentの到達が
	# HIT_AT(4.78)と厳密に一致する設計のため、既存の`_draw_eos_burst_
	# impact_screen_flash`(`_eos_burst_contact_trigger_elapsed`基準)が
	# そのままこの役割を果たす。
	_draw_eos_burst_impact_screen_flash(view)
	# v19: soul_break's broken X-cross draws ON TOP of the screen flash so
	# the flash can't wash it out (see _draw_soul_break_top_layer). No-ops
	# for every other skill.
	_draw_soul_break_top_layer(view)
	if _debug_boss_loop:
		_draw_debug_boss_loop_badge(view)
	if zoom != 1.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Quest-map-style progression read (Monster Strike reference, 2026-07-19):
## each chapter's non-boss backdrop cycles seg1 -> seg2 -> normal -> seg1
## as stage_index advances, looping for the whole chapter regardless of
## how many stage bands it is split into (UDStageDB.chapter_origin_index).
## Mid-bosses are planned to live in the "normal" phase (user's design
## note); only the real gate boss (sim.boss_active) gets the dedicated
## boss backdrop, via _chapter_bg_key("boss") in _draw_boss_battle().
const CHAPTER_BG_CYCLE: Array[String] = ["seg1", "seg2", "normal"]

## How long the slide handoff between two idle backdrops takes, and how
## often it redraws while running. Comfortably under UD.TICK_SECONDS (2s)
## so it always finishes during the gap tick before the next trash mob
## spawns (see _on_tick's comment).
const BG_TRANSITION_SECONDS: float = 2.0
const BG_TRANSITION_FPS: float = 30.0
## The incoming scene starts this many px short of a flush handoff, so it
## always overlaps the outgoing one instead of the two ever butting edge
## to edge (user direction, 2026-07-19: hide the seam with an overlap +
## fade, not a hard join).
const BG_TRANSITION_OVERLAP_PX: float = 120.0
const BG_TRANSITION_DARKEN_ALPHA: float = 0.35


func _start_bg_transition(from_key: String, to_key: String) -> void:
	if _bg_transition_active:
		_bg_transition_pending_to_key = to_key
		return
	_bg_transition_from_key = from_key
	_bg_transition_to_key = to_key
	_bg_transition_pending_to_key = ""
	_bg_transition_t = 0.0
	_bg_transition_active = true
	_bg_transition_timer.start()


func _on_bg_transition_tick() -> void:
	_bg_transition_t += _bg_transition_timer.wait_time / BG_TRANSITION_SECONDS
	if _bg_transition_t >= 1.0:
		_bg_transition_t = 1.0
		_bg_transition_active = false
		_bg_transition_timer.stop()
		if _bg_transition_pending_to_key != "" \
				and _bg_transition_pending_to_key != _bg_transition_to_key:
			var settled_key := _bg_transition_to_key
			var queued_key := _bg_transition_pending_to_key
			_bg_transition_pending_to_key = ""
			_start_bg_transition(settled_key, queued_key)
			return
		_bg_transition_pending_to_key = ""
	queue_redraw()


## The outgoing scene glides off to the left while the incoming one enters
## from the right (party faces right, so the world reads as sliding past
## it leftward), overlapping by BG_TRANSITION_OVERLAP_PX instead of ever
## butting edge to edge. The incoming image's own left edge fades in
## (_draw_backdrop_masked) and a soft dark band rides over the overlap
## (_draw_seam_darken) so the join between two unrelated illustrations
## doesn't read as a hard cut or a visible ghost-double-exposure.
## Positions are rounded to whole pixels and filtering forced to nearest
## for these draws only (restored after) — sub-pixel positions plus
## linear filtering made the moving seam visibly shimmer.
func _draw_backdrop_transition(view: Rect2) -> void:
	var prev_filter := texture_filter
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var t := smoothstep(0.0, 1.0, _bg_transition_t)
	var from_x := roundf(view.position.x - view.size.x * t)
	var to_x := roundf(view.position.x + (view.size.x - BG_TRANSITION_OVERLAP_PX) * (1.0 - t))
	var to_pos := Vector2(to_x, view.position.y)
	_draw_backdrop(Rect2(Vector2(from_x, view.position.y), view.size), _bg_transition_from_key, view)
	_draw_backdrop_masked(
		Rect2(to_pos, view.size), _bg_transition_to_key, view, BG_TRANSITION_OVERLAP_PX)
	# sin(t*PI) fades 0 -> 1 -> 0 across the slide, so the shadow eases in
	# and back out instead of popping at the first/last frame. Keyed off
	# the SAME eased `t` the seam position itself uses (2026-07-21 fix:
	# was the raw linear _bg_transition_t) — the darken's intensity curve
	# was reaching its peak at a different moment than the seam actually
	# passing through the middle of the screen, since position moves on
	# the eased smoothstep curve but the shadow was pulsing on the clock.
	_draw_seam_darken(to_pos, view, BG_TRANSITION_OVERLAP_PX, sin(t * PI))
	texture_filter = prev_filter


## Same cover-fit crop as _draw_backdrop, but the leftmost `fade_width` px
## of `key` ramp from alpha 0 (outer edge) to 1 (fade_width in) via a
## vertex-colored quad instead of a flat draw, so the overlap with
## whatever is drawn underneath (the outgoing scene) cross-fades rather
## than occluding it outright.
func _draw_backdrop_masked(dest: Rect2, key: String, clip: Rect2, fade_width: float) -> void:
	if not art.has_art(key):
		var solid := dest.intersection(clip)
		if solid.size.x > 0.0 and solid.size.y > 0.0:
			draw_rect(solid, COLOR_DIG_ROCKMASS)
		return
	var tex := art.frame(key, _anim_frame)
	var scale := maxf(
		dest.size.x / float(tex.get_width()), dest.size.y / float(tex.get_height()))
	var displayed := Vector2(tex.get_width() * scale, tex.get_height() * scale)
	var offset := dest.position + (dest.size - displayed) / 2.0
	var tex_size := tex.get_size()

	var remainder := Rect2(
		dest.position + Vector2(fade_width, 0.0), dest.size - Vector2(fade_width, 0.0))
	var visible := remainder.intersection(clip)
	if visible.size.x > 0.0 and visible.size.y > 0.0:
		draw_texture_rect_region(
			tex, visible, Rect2((visible.position - offset) / scale, visible.size / scale))

	# The fade band sits entirely inside `dest`'s own footprint, which the
	# caller keeps within `clip` for its whole slide (see
	# _draw_backdrop_transition), so no further clipping is needed here.
	var p_tl := dest.position
	var p_tr := dest.position + Vector2(fade_width, 0.0)
	var p_br := dest.position + Vector2(fade_width, dest.size.y)
	var p_bl := dest.position + Vector2(0.0, dest.size.y)
	draw_primitive(
		PackedVector2Array([p_tl, p_tr, p_br, p_bl]),
		PackedColorArray([
			Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)]),
		PackedVector2Array([
			(p_tl - offset) / scale / tex_size, (p_tr - offset) / scale / tex_size,
			(p_br - offset) / scale / tex_size, (p_bl - offset) / scale / tex_size]),
		tex)


## A soft 0 -> BG_TRANSITION_DARKEN_ALPHA*envelope -> 0 shadow riding over
## the overlap band, on top of both backdrops: the alpha cross-fade alone
## still shows a faint double-exposure where two unrelated scenes
## overlap, and dimming that strip hides it without needing dedicated
## seam art (gate pillars etc.) for every chapter pairing. `envelope`
## (0..1, see the sin(t*PI) caller) eases the whole band in and back out
## over the slide instead of popping in at the first frame and vanishing
## at the last.
func _draw_seam_darken(to_pos: Vector2, view: Rect2, band_width: float, envelope: float) -> void:
	var band := Rect2(to_pos, Vector2(band_width, view.size.y)).intersection(view)
	if band.size.x <= 0.0 or band.size.y <= 0.0 or envelope <= 0.0:
		return
	var mid_x := to_pos.x + band_width / 2.0
	var top_y := view.position.y
	var bot_y := view.position.y + view.size.y
	var clear := Color(0.0, 0.0, 0.0, 0.0)
	var peak := Color(0.0, 0.0, 0.0, BG_TRANSITION_DARKEN_ALPHA * envelope)
	draw_primitive(
		PackedVector2Array([
			Vector2(to_pos.x, top_y), Vector2(mid_x, top_y),
			Vector2(mid_x, bot_y), Vector2(to_pos.x, bot_y)]),
		PackedColorArray([clear, peak, peak, clear]), PackedVector2Array(), null)
	draw_primitive(
		PackedVector2Array([
			Vector2(mid_x, top_y), Vector2(to_pos.x + band_width, top_y),
			Vector2(to_pos.x + band_width, bot_y), Vector2(mid_x, bot_y)]),
		PackedColorArray([peak, clear, clear, peak]), PackedVector2Array(), null)


func _chapter_bg_key(segment: String) -> String:
	return "chapter_bg_%d_%s" % [stage_db.chapter_for_index(sim.stage_index), segment]


func _idle_bg_key() -> String:
	var origin := stage_db.chapter_origin_index(sim.stage_index)
	var phase := CHAPTER_BG_CYCLE[(sim.stage_index - origin) % CHAPTER_BG_CYCLE.size()]
	return _chapter_bg_key(phase)


## Just the creature standing in the scene — name and HP now live in the
## top banner Control (_build_boss_banner/_refresh_boss_panel) instead of
## being drawn here, per the reference layout (2026-07-19).
## Shared by the icon draw call, the target-selection crosshair overlay,
## and click-to-target hit testing, so all three always agree on where
## the boss actually is (only one enemy today, but sized/positioned by
## formula rather than a literal rect so it keeps working if the
## icon size or ground line ever changes).
## Horizontal anchor of the boss, as a fraction of the (full-window) boss
## view. Measured off the reference mockup ボス戦戦闘用画面.png (troll
## body center ≈ x1290 of 1672 ≈ 0.77) — the old 1-SIDE_MARGIN_FRAC
## (0.86) sat ~100px too far right of it (user report 2026-07-20,
## "ボスの位置が右にずれていた"). SIDE_MARGIN_FRAC still positions the
## idle view's trash mob, whose view is narrower (button panel).
const BOSS_CENTER_X_FRAC: float = 0.77


func _boss_icon_rect(view: Rect2) -> Rect2:
	var icon_px := BOSS_ICON_PX
	var center_x := view.position.x + view.size.x * BOSS_CENTER_X_FRAC
	var ground_y := _ground_y(view)
	var top := maxf(view.position.y, ground_y - icon_px)
	return Rect2(Vector2(center_x - icon_px / 2.0, top), Vector2(icon_px, icon_px))


func _draw_boss_enemy(view: Rect2) -> void:
	# 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「ピーク
	# 6・7だけは敵を非表示にして完全被覆を保証します...敵ノードを削除しま
	# せん」——sim側の状態には一切触れず、この描画呼び出しだけをスキップ
	# する(既存の`_battle_victory_step_active()`と同じ「描画のみスキップ」
	# パターン)。ピーク以外の時間は無条件でfalseを返すため、eos_burst以外
	# は元の挙動のまま無改修。
	if _eos_burst_massive_burst_peak_active(_battle_anim_phase_elapsed):
		return
	# On a won round sim.boss_enemy_id is already "" while the killing
	# blow is still animating — keep drawing the boss stashed at resolve
	# time so it doesn't vanish before the hit that kills it lands.
	var boss_id := sim.boss_enemy_id
	if boss_id == "" and _battle_playback_active:
		boss_id = _battle_playback_boss_id
	if boss_id == "" or not enemy_db.has_enemy(boss_id):
		return
	# During the party's victory step the boss is down: its defeat clip
	# (2026-07-20 asset pack) plays once and holds its final rubble
	# frame; without one it simply disappears (previous behavior).
	if _battle_victory_step_active():
		var defeat_key := "enemy_%s_defeat" % boss_id
		if not art.has_art(defeat_key):
			return
		var defeat_frames := art.frame_count(defeat_key)
		var defeat_icon := art.frame(defeat_key, mini(
			int(_battle_anim_phase_elapsed / BATTLE_ANIM_ACT_FRAME_SECONDS),
			defeat_frames - 1))
		draw_texture_rect(defeat_icon, _boss_icon_rect(view), false)
		return
	# Real enemy art (2026-07-20 asset pack): idle row loops; the _hit
	# row plays once while the knockback decays. Without art the old
	# placeholder + red hit-flash remains.
	var idle_key := "enemy_%s" % boss_id
	var hit_key := "enemy_%s_hit" % boss_id
	var attack_key := "enemy_%s_attack" % boss_id
	var icon: Texture2D
	var modulate := Color.WHITE
	if _battle_enemy_knock_t > 0.0 and art.has_art(hit_key):
		var frames := art.frame_count(hit_key)
		icon = art.frame(
			hit_key, mini(int((1.0 - _battle_enemy_knock_t) * frames), frames - 1))
	elif _battle_boss_lunge_t > 0.0 and art.has_art(attack_key):
		# Counter step: the boss's own attack clip plays once across the
		# lunge (its decay doubles as the clip clock, like the hit clips).
		var frames := art.frame_count(attack_key)
		icon = art.frame(
			attack_key, mini(int((1.0 - _battle_boss_lunge_t) * frames), frames - 1))
	elif art.frame_count(idle_key) > 1:
		icon = art.frame(idle_key, _anim_frame)
	else:
		icon = art.icon_or_placeholder(idle_key, boss_id, "gem")
		if _battle_anim_boss_flash_t > 0.0:
			modulate = Color.WHITE.lerp(Color(3.0, 0.55, 0.55), _battle_anim_boss_flash_t)
	var rect := _boss_icon_rect(view)
	# Knockback on being hit (pushed away from the attacker), and an
	# out-and-back lunge toward the party on the boss's own counter step.
	# _battle_knockback_px defaults to BATTLE_KNOCKBACK_PX but can be
	# overridden per-hit (currently only soul_break, see SOUL_BREAK_
	# KNOCKBACK_PX) via _fire_battle_anim_hit's own trailing params.
	rect.position.x += _battle_knockback_px * _battle_enemy_knock_t
	rect.position.x -= BATTLE_BOSS_LUNGE_PX * sin((1.0 - _battle_boss_lunge_t) * PI) \
		if _battle_boss_lunge_t > 0.0 else 0.0
	draw_texture_rect(icon, rect, false, modulate)


## True while the queue's current step is the party-wide victory pose
## (appended only on won rounds — see _on_boss_resolve_round).
func _battle_victory_step_active() -> bool:
	return _battle_anim_phase == "victory" \
		and _battle_anim_step >= 0 and _battle_anim_step < _battle_anim_queue.size() \
		and str(_battle_anim_queue[_battle_anim_step].get("action", "")) == "party_victory"


# 視認性改善（2026-08-22）: 純赤寄りへ深化（0.95,0.2,0.15→0.88,0.14,0.1）。
# 細い線（クロスヘア）向けの色——大きな塗り面（行リストの選択背景）には
# 別に COLOR_TARGET_SELECTED_BG（暗め・白文字が乗っても読める濃さ）を
# 使う。両方とも同じ「選択中の赤」として視覚的に対応させている。
const COLOR_TARGET_CURSOR := Color(0.88, 0.14, 0.1)
const COLOR_TARGET_SELECTED_BG := Color(0.55, 0.09, 0.07)
const TARGET_BRACKET_MARGIN: float = 10.0
const TARGET_BRACKET_LEN: float = 18.0
const TARGET_BRACKET_WIDTH: float = 3.0


## Crosshair overlay for the currently-selected target: drawn as its own
## pass over _boss_icon_rect(view) every frame rather than baked into the
## enemy art, so it tracks the icon regardless of position/size (user
## direction, 2026-07-19) and works for any future second target.
## 視認性改善（2026-08-22, 実機報告「選択中の赤表示が出たり消えたりする」
## への対応）: これまで_anim_frame駆動のsin波でalpha(=不透明度)と矢印の
## 上下位置(bob)を揺らしていた——alphaが最低0.10まで落ちる瞬間があり、
## 「選択しているのに赤が消える」ように見えていた実体はこの明滅そのもの
## だった。「選択中は解除/対象変更まで常時表示、点滅・フェード禁止」の
## 明示指示に従い、alpha/位置とも完全に固定した静止表示へ変更。
func _draw_target_cursor(view: Rect2) -> void:
	if _battle_selected_target_id == "" \
			or not enemy_db.has_enemy(_target_enemy_id(_battle_selected_target_id)):
		return
	var rect := _boss_icon_rect(view).grow(TARGET_BRACKET_MARGIN)
	var color := COLOR_TARGET_CURSOR

	var tl := rect.position
	var tr := rect.position + Vector2(rect.size.x, 0.0)
	var bl := rect.position + Vector2(0.0, rect.size.y)
	var br := rect.position + rect.size
	var len := TARGET_BRACKET_LEN
	var w := TARGET_BRACKET_WIDTH
	draw_line(tl, tl + Vector2(len, 0.0), color, w)
	draw_line(tl, tl + Vector2(0.0, len), color, w)
	draw_line(tr, tr + Vector2(-len, 0.0), color, w)
	draw_line(tr, tr + Vector2(0.0, len), color, w)
	draw_line(bl, bl + Vector2(len, 0.0), color, w)
	draw_line(bl, bl + Vector2(0.0, -len), color, w)
	draw_line(br, br + Vector2(-len, 0.0), color, w)
	draw_line(br, br + Vector2(0.0, -len), color, w)

	var arrow_center_x := rect.position.x + rect.size.x / 2.0
	var arrow_top := rect.position.y - 22.0
	var arrow_half_w := 9.0
	var arrow_h := 12.0
	draw_primitive(
		PackedVector2Array([
			Vector2(arrow_center_x - arrow_half_w, arrow_top),
			Vector2(arrow_center_x + arrow_half_w, arrow_top),
			Vector2(arrow_center_x, arrow_top + arrow_h)]),
		PackedColorArray([color, color, color]), PackedVector2Array(), null)


## Scenic backdrop behind the battle view (chapter_bg_<N>_<segment>.png,
## picked by _idle_bg_key()/_chapter_bg_key()). These are single
## full-scene illustrations, not tiles: cover-fit (fill the view,
## preserve aspect, crop the overflow), no scrolling within a segment.
## The old tiled dig_background cave that crept sideways per kill is gone
## with the chapter-0 art direction (2026-07-19); its code lives in git
## history.
## `clip` bounds what actually gets drawn (must be passed as `view` for a
## plain, unclipped draw). Needed for _draw_backdrop_transition: sliding
## the same cover-fit image to a shifted `view` is enough to move it on
## screen (the scale/crop math only depends on view.size, not position),
## but the shifted rect spills outside the battle view into the button
## panel unless the draw itself is cropped to `clip` (CanvasItem has no
## draw-time clip-rect call to lean on instead).
func _draw_backdrop(view: Rect2, key: String, clip: Rect2) -> void:
	var visible := view.intersection(clip)
	if visible.size.x <= 0.0 or visible.size.y <= 0.0:
		return
	if not art.has_art(key):
		draw_rect(visible, COLOR_DIG_ROCKMASS)
		return
	# art.frame keeps the _fN animation convention working here (unused
	# by the current chapter-0 scenes, but free if frames ever ship).
	var tex := art.frame(key, _anim_frame)
	var scale := maxf(
		view.size.x / float(tex.get_width()),
		view.size.y / float(tex.get_height()))
	var displayed := Vector2(tex.get_width() * scale, tex.get_height() * scale)
	var offset := view.position + (view.size - displayed) / 2.0
	draw_texture_rect_region(
		tex,
		visible,
		Rect2((visible.position - offset) / scale, visible.size / scale))


func _ground_y(view: Rect2) -> float:
	var y := view.position.y + view.size.y * GROUND_FRAC
	if _boss_screen_active():
		y -= BOSS_FEET_LIFT_PX
	return y


## Icon size for the taskbar-look resident strip, shared by enemy and
## party so neither dwarfs the other in the cramped view.
func _resident_icon_px(view: Rect2) -> int:
	return mini(int(view.size.y) - 4, 32)


## Enemy stands on the right, facing the party across the cave floor.
## Hidden for the whole backdrop slide (not just sim.enemy_id == "") so a
## fast-killing party queuing several slides back to back (see
## _start_bg_transition) never reveals the next trash mob mid-transition.
func _draw_enemy(view: Rect2) -> void:
	if _bg_transition_active or sim.enemy_id == "" or not enemy_db.has_enemy(sim.enemy_id):
		return
	var def := enemy_db.get_enemy(sim.enemy_id)
	var icon_px := ENEMY_ICON_PX if not settings.resident_mode else _resident_icon_px(view)
	var center_x := view.position.x + view.size.x * (1.0 - SIDE_MARGIN_FRAC)
	var ground_y := _ground_y(view)
	var top := maxf(view.position.y, ground_y - icon_px)
	# Idle row loops when real enemy art is shipped (asset pack keys like
	# enemy_hole_wanderer bind automatically once a data/enemies json
	# uses that id); placeholder shape otherwise.
	var idle_key := "enemy_%s" % sim.enemy_id
	var icon := art.frame(idle_key, _anim_frame) if art.frame_count(idle_key) > 1 \
		else art.icon_or_placeholder(idle_key, sim.enemy_id, "gem")
	var rect := Rect2(Vector2(center_x - icon_px / 2.0, top), Vector2(icon_px, icon_px))
	draw_texture_rect(icon, rect, false)
	var max_hp := int(def["hp"])
	var bar_y := top - BAR_HEIGHT - 4
	var bar_rect := Rect2(Vector2(center_x - icon_px / 2.0, bar_y), Vector2(icon_px, BAR_HEIGHT))
	draw_rect(bar_rect, COLOR_HP_BAR_BG)
	var frac := clampf(float(sim.enemy_hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	draw_rect(Rect2(bar_rect.position, Vector2(bar_rect.size.x * frac, BAR_HEIGHT)), COLOR_ENEMY_HP_BAR)
	if not settings.resident_mode:
		var font := ThemeDB.fallback_font
		var name_text := locale.text(str(def["name_key"]))
		# The draw_string position is the text box's LEFT edge; to center
		# on the icon the box must start icon_px left of center.
		draw_string(
			font, Vector2(center_x - icon_px, bar_y - 6), name_text,
			HORIZONTAL_ALIGNMENT_CENTER, icon_px * 2, 14, COLOR_HUD_TEXT
		)


## Party stands on the left in the PARTY_FORMATION cluster (per the
## user's placement reference), facing the enemy on the right. The
## resident strip keeps the old compact row instead - its layout is
## getting redesigned separately.
func _draw_party_row(view: Rect2) -> void:
	if sim.minions.is_empty():
		return
	if settings.resident_mode:
		_draw_party_row_strip(view)
		return
	var icon_px := _ally_battle_icon_px()
	var font := ThemeDB.fallback_font
	# Back-to-front (higher feet = further away), so nearer units overlap.
	var order: Array[int] = []
	for slot_index in sim.minions.size():
		order.append(slot_index)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			return _formation_pos(a).y < _formation_pos(b).y
	)
	# The one character currently playing an attack/skill motion draws last
	# (on top) regardless of its resting-position sort order, so stepping
	# toward center stage never reads as ducking behind a party-mate who
	# hasn't moved (2026-07-19).
	if _boss_screen_active() and _battle_anim_step >= 0 and _battle_anim_step < _battle_anim_queue.size():
		var acting_id := int(_battle_anim_queue[_battle_anim_step].get("unit_id", -1))
		if order.has(acting_id):
			order.erase(acting_id)
			order.append(acting_id)
	var victory_pose := _battle_victory_step_active()
	for slot_index in order:
		var unit: UDMinion = sim.minions[slot_index]
		var pos := _formation_pos(slot_index)
		var icon: Texture2D = null
		var flip_h := false
		var modulate := Color.WHITE
		var x_offset := 0.0
		var y_offset := 0.0
		var art_variant := _minion_art_variant(slot_index)
		# 「ソティリスのサイズ統一・最終スプライト切替修正」(2026-08-06) —
		# EOS_BURST_THRUST_POSE_KEYへ差し替わった間だけtrue、下でsprite_
		# scaleの選択に使う。
		var uses_eos_thrust_sprite := false
		# 「natural dragon motion」(2026-08-07、README §1のソティリス側
		# ground-anchor補正) — 上のuses_eos_thrust_sprite=trueと同じガード
		# 内でセットされる、EOS_BURST_THRUST_GROUND_ANCHOR_X_PXへ引くための
		# 現在のコマ番号。
		var eos_thrust_frame_idx := 0
		# 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — `icon`単一
		# 描画をA/Bクロスフェードへ拡張するための追加スロット。デフォルトは
		# 「icon_bを描かない」(=既存の全モーション/全キャラで無改修)。
		# eos_burst downslash12だけがこれらへ実際の値を書き込む。
		var icon_a_alpha_mult := 1.0
		var icon_b: Texture2D = null
		var icon_b_alpha_mult := 0.0
		if _boss_screen_active() and _battle_anim_pos.has(slot_index):
			pos = _battle_anim_pos[slot_index]
			icon = art.frame(_battle_anim_motion_key, _battle_anim_frame_index)
			flip_h = _battle_anim_flip
			# 「現行ソティリス維持版 v3」(2026-08-12) — 納品の専用振り下ろし
			# シート(`EOS_BURST_DOWNSLASH_POSE_KEY`、6コマ)を、剣を掲げる〜
			# 振り下ろす〜着弾後の間(APPROACH_START〜EXIT_END)だけ`icon`を
			# 直接上書きする。`_battle_anim_motion_key`自体は変更しない
			# (HPバー等の他ロジックが参照するため)——タメ・竜出現・カット
			# インは既存の`attack_minion_0`のまま無改修。
			# 「Slower + Smooth + Massive Finish v5」(2026-08-12) — 6コマ→
			# 12コマ化された納品シート(`EOS_BURST_DOWNSLASH12_POSE_KEY`)へ
			# 差し替え。旧6コマキー(`EOS_BURST_DOWNSLASH_POSE_KEY`)・その
			# フレーム選択関数は無改修のまま残置(削除しない)——このブロック
			# だけが新キー/新関数(`_eos_burst_downslash12_frame_pair`)へ
			# 切り替わる。「12コマすべての足元はローカルY=214付近へ揃えて
			# ある。実装時に1コマごとのposition補正を追加しません」——
			# PowerShellで12コマ全ての接地帯Yを実測したところ全コマ
			# solidBottomY=213(ローカル、ほぼ一致)で完全に一定だったため、
			# 明示指定どおりX方向の補正テーブルは追加しない(eos_thrust_
			# frame_idxは以下でセットするが、この値からオフセットを引く
			# 処理自体を呼ばない——下記`if uses_eos_thrust_sprite:`ブロック
			# 参照)。
			# 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) —
			# 「①長く止まった後に一枚で切り替わるためカクついて見える」——
			# 単一frameの直接代入を、A/Bクロスフェードペアへ差し替えた。
			# 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) —
			# README「③輪郭が白っぽく二重に見える」を受け、A/Bを2回alpha
			# 描画する旧クロスフェードを廃止——`_eos_burst_downslash12_
			# dither_texture`が生成する「相補的binary reveal」の合成
			# テクスチャ1枚だけを描く(icon_b/icon_b_alpha_multは常に既定値
			# のまま=このブランチはもう使わない)。姿勢テーブル(RAISE/
			# SWING/BLEND_DURATIONS)自体は無改修のまま——`pair`の意味
			# (idx_a/idx_b/mix)は従来どおりで、alpha_bの値(=smootherstep
			# mix)をそのままdither量子化の入力に使うだけ。rim/afterimage
			# (下記`is_eos_burst_actor`ブロック)は主要フレーム(idx_a)の
			# シルエットだけを使う軽微な簡略化は変わらず(装飾的な副次効果
			# のため許容)。
			if _eos_burst_vfx_active():
				var thrust_age := _battle_anim_phase_elapsed - EOS_BURST_APPROACH_START_SECONDS
				var window_end := EOS_BURST_EXIT_END_SECONDS - EOS_BURST_APPROACH_START_SECONDS
				if thrust_age >= 0.0 and thrust_age < window_end \
						and art.has_art(EOS_BURST_DOWNSLASH16_POSE_KEY):
					var pair := _eos_burst_downslash12_frame_pair(_battle_anim_phase_elapsed)
					var idx_a: int = pair[0]
					var idx_b: int = pair[1]
					var mix_b: float = pair[3]
					eos_thrust_frame_idx = idx_a
					icon = _eos_burst_downslash12_dither_texture(idx_a, idx_b, mix_b)
					icon_a_alpha_mult = 1.0
					uses_eos_thrust_sprite = true
		# Battle won: each character strikes its victory pose (played once,
		# last frame held for the rest of the step). Staggered per slot
		# (2026-07-20 polish) — all five reading the exact same frame at
		# the exact same instant looked like a synchronized dance rather
		# than five individuals reacting; a slight per-slot delay before
		# each one starts reads as five separate reactions instead.
		if victory_pose:
			var victory_key := "victory_minion_%d" % art_variant
			if art.has_art(victory_key):
				var vframes := art.frame_count(victory_key)
				var staggered := maxf(
					0.0, _battle_anim_phase_elapsed - float(slot_index) * VICTORY_POSE_STAGGER_SECONDS)
				icon = art.frame(victory_key, mini(
					int(staggered / BATTLE_ANIM_ACT_FRAME_SECONDS), vframes - 1))
		if icon == null:
			var art_key := art.minion_key(art_variant)
			# Resting characters loop ONLY their idle row (user spec
			# 2026-07-20 — never cycle other motions automatically).
			# Staggered by slot so five characters don't breathe in
			# perfect sync.
			if art.frame_count(art_key) > 1:
				icon = art.frame(art_key, _anim_frame + slot_index)
			else:
				icon = art.icon_or_placeholder(art_key, "minion_%d" % slot_index, "rune")
		# Being hit by the boss's counter: the 被弾 clip (2026-07-20 asset
		# pack) plays once with a brief knockback; red flash only remains
		# as the no-art fallback.
		if slot_index == _battle_ally_hit_unit and _battle_ally_hit_t > 0.0:
			x_offset = -BATTLE_KNOCKBACK_PX * _battle_ally_hit_t
			var hit_key := "hit_minion_%d" % art_variant
			if art.has_art(hit_key):
				var hframes := art.frame_count(hit_key)
				icon = art.frame(hit_key, mini(
					int((1.0 - _battle_ally_hit_t) * hframes), hframes - 1))
			else:
				modulate = Color.WHITE.lerp(Color(2.5, 0.6, 0.6), _battle_ally_hit_t)
		# Healing's own target reaction (separate from the ally_hit system
		# above — user spec item 5, "回復対象の発光反応"): white-gold tint
		# only, deliberately NO x_offset (user spec: "ノックバックや画面
		# 揺れは使用しない").
		if slot_index == _healing_target_unit and _healing_target_flash_t > 0.0:
			var flash_frac := _healing_target_flash_t / HEALING_TARGET_FLASH_SECONDS
			modulate = Color.WHITE.lerp(Color(2.2, 2.0, 1.3), flash_frac)
		if _rapid_slash_vfx_active() and _battle_anim_pos.has(slot_index):
			# rapid_slash's own capped partial advance (2026-07-26) — a
			# pixel x_offset layered on top of the resting formation slot,
			# same mechanism knockback already uses, deliberately NOT the
			# generic melee lunge/skill step-in (user spec: "通常の近接
			# 攻撃で使う敵方向へのlungeを重ねないでください。ラピッド
			# スラッシュ専用の移動だけを使用してください") — _battle_anim_
			# pos[unit_id] itself stays at _battle_anim_origin throughout
			# (BATTLE_ANIM_SKILL_STEP_FRAC's generic skill step still runs
			# but contributes 0, see that constant). Gated on _rapid_slash_
			# vfx_active() (checks the queued step's own skill_id), not on
			# _battle_anim_motion_key — v3 dropped the dedicated clip, so
			# motion_key is now "attack_minion_N", the same key normal
			# attacks use, which carries no skill-specific information.
			x_offset += _rapid_slash_advance_offset_px(view, _battle_anim_phase_elapsed)
		if _soul_break_vfx_active() and _battle_anim_pos.has(slot_index):
			# Small step-in/return (user spec: "8〜12pxだけ前へ踏み込む").
			# Same draw-time x_offset mechanism as rapid_slash's own advance
			# above — _battle_anim_pos[unit_id] itself stays at _battle_
			# anim_origin the whole cast (see _on_battle_anim_tick's own
			# no-op SOUL_BREAK_SKILL_ID position branch).
			x_offset += _soul_break_advance_offset_px(_battle_anim_phase_elapsed)
		if _eos_burst_vfx_active() and _battle_anim_pos.has(slot_index):
			# The dash to the enemy and back. Same draw-time x_offset
			# mechanism rapid_slash/soul_break use — _battle_anim_pos and
			# feet_y are untouched, so scale and the foot line are constant
			# and the return lands exactly on the origin (package: "開始時
			# と帰還後の足裏Y差：1px以内 / X座標差：1px以内").
			x_offset += _eos_burst_advance_offset_px(view, slot_index, _battle_anim_phase_elapsed)
			# 「突きを作り直す」(2026-08-05、同日追加ラウンド): 踏み込み前の
			# 溜め→突き→保持→余韻反動の4段階、ダッシュ本体とは別レイヤー
			# として加算（_battle_anim_posは無変更）。
			x_offset += _eos_burst_thrust_offset_px(_battle_anim_phase_elapsed)
			# README §1「align the foot/waist ground anchor per frame」
			# (2026-08-07) — `sotiris_eos_thrust_6f.png`の実測(EOS_BURST_
			# THRUST_GROUND_ANCHOR_X_PX、上記const定義参照)に基づき、frame0
			# を基準とした水平方向の補正だけを加える。uses_eos_thrust_sprite
			# がfalseの間はeos_thrust_frame_idxが既定値0のままなので補正は
			# 常に0(no-op)——専用シート表示中だけの局所的な変更。
			# 「Visual Regression Cleanup v1」(2026-08-10) — README Part C。
			# 旧実装はこの補正をeos_thrust_frame_idx(tick量子化された離散
			# コマ番号)からそのまま計算していたため、コマが切り替わる瞬間に
			# world position(x_offset)が段階的にではなく一瞬でジャンプして
			# いた——headless実測でapproach開始直後の連続tickにわたり
			# 18.5px→21.9px→50.7px→51.7pxという離散ジャンプを直接確認
			# (詳細は`_eos_burst_thrust_ground_anchor_offset_px`のdoc
			# comment参照)。「どの絵を表示するか」はコマ単位でパッと切り
			# 替わって構わない(スプライトなので当然、tick基準のまま無改修)
			# が、この補正自体は"足の接地位置"という連続的なworld position
			# 量のため、隣接コマの補正値を滑らかに補間する専用関数へ分離
			# した。
			# 「Slower + Smooth + Massive Finish v5」(2026-08-12) — 12コマ
			# シートは全コマの接地帯Yが実測で完全に一定(213px)だったため、
			# README「実装時に1コマごとのposition補正を追加しません」の
			# 明示指示どおり、この補正呼び出し自体を撤去した(x_offsetは
			# 触らない)——旧6コマ用の補正関数(`_eos_burst_thrust_ground_
			# anchor_offset_px`)自体は無改修のまま残置するが、呼び出し元が
			# 無くなった。
			# v8 (this round): the タメ's own 2px body sink — a new y_offset
			# accumulator mirroring x_offset's own pattern, always 0.0 for
			# every other skill (only eos_burst's own windup ever writes to
			# it), so scale/feet stay exactly as before everywhere else.
			y_offset += _eos_burst_windup_sink_px(_battle_anim_phase_elapsed)
			# 「剣先を少し下げます」——余韻反動中だけの小さな垂直たわみ。
			y_offset += _eos_burst_recoil_dip_px(_battle_anim_phase_elapsed)
		var x := view.position.x + view.size.x * pos.x + x_offset
		var feet_y := view.position.y + view.size.y * pos.y + y_offset
		# サイズ補正はこのsprite_box_pxだけに閉じる——他キャラ/他モーション
		# は uses_eos_thrust_sprite=false のままなので sprite_box_px==icon_px
		# (無改修)。bottom-center基準(x中心・feet_y=底辺)は共通のまま、
		# ボックスの一辺だけをEOS_BURST_THRUST_SPRITE_SCALE倍する——足元の
		# Y座標(feet_y)自体には一切触れないため「足元が跳ねる」ことがない。
		var sprite_box_px := icon_px * EOS_BURST_DOWNSLASH12_SPRITE_SCALE if uses_eos_thrust_sprite else icon_px
		var top := maxf(view.position.y, feet_y - sprite_box_px)
		var is_eos_burst_actor := _eos_burst_vfx_active() and _battle_anim_pos.has(slot_index)
		if is_eos_burst_actor:
			# This round's own "視認性" fix: a thin dark/gold silhouette
			# outline UNDER Sotiris's own sprite, so he reads clearly
			# against the much larger, brighter dragon behind him — pure
			# readability aid, never changes his own draw size/position.
			_draw_eos_burst_sotiris_rim(
				icon, Rect2(Vector2(x - sprite_box_px / 2.0, top), Vector2(sprite_box_px, sprite_box_px)), flip_h)
			# This round's own step-in afterimages (max 2, alpha<=0.18),
			# drawn BEFORE the main sprite so the main body always reads on
			# top ("本体を常に最前面へ表示").
			_draw_eos_burst_attack_afterimages(view, slot_index, icon, x, top, sprite_box_px, flip_h)
		if _battle_anim_motion_key.begins_with("skill_minion_") and _battle_anim_pos.has(slot_index):
			# A skill's own motion clip draws at a fixed, larger size (see
			# SKILL_ACTOR_DRAW_SIZE's doc comment) — never resized per
			# frame or per character. 「表示サイズ見直し」(2026-08-02):
			# now the SAME shared `icon_px` (= _ally_battle_icon_px()) the
			# non-skill branch below uses — no separate skill-only scale.
			var draw_size := Vector2(sprite_box_px, sprite_box_px)
			var draw_pos := Vector2(x - draw_size.x / 2.0, feet_y - draw_size.y)
			var draw_rect := Rect2(draw_pos, draw_size)
			_draw_sprite(
				icon, draw_rect, flip_h,
				Color(modulate.r, modulate.g, modulate.b, modulate.a * icon_a_alpha_mult))
			if icon_b != null and icon_b_alpha_mult > 0.0:
				_draw_sprite(
					icon_b, draw_rect, flip_h,
					Color(modulate.r, modulate.g, modulate.b, modulate.a * icon_b_alpha_mult))
		else:
			# rapid_slash (v3, motion_key="attack_minion_N") falls through to
			# here like any other attack — fixed icon_px box, no bbox-based
			# scaling (user spec: "フレームのtight bboxを基準に拡大縮小しな
			# いでください"), since attack_minion_N already fills its own
			# 128x128 canvas edge to edge. eos_thrust uses sprite_box_px
			# instead (see EOS_BURST_THRUST_SPRITE_SCALE above); every other
			# asset routed through this branch still gets sprite_box_px==
			# icon_px, i.e. byte-identical to before.
			# 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — eos_burst
			# downslash12だけがicon_b/*_alpha_multへ実際の値を書き込む。他の
			# 全キャラ/全モーションはicon_a_alpha_mult==1.0・icon_b==nullの
			# ままなので、この分岐は既存と完全に同じ1回描画のまま(無改修)。
			var attack_rect := Rect2(
				Vector2(x - sprite_box_px / 2.0, top), Vector2(sprite_box_px, sprite_box_px))
			_draw_sprite(
				icon, attack_rect, flip_h,
				Color(modulate.r, modulate.g, modulate.b, modulate.a * icon_a_alpha_mult))
			if icon_b != null and icon_b_alpha_mult > 0.0:
				_draw_sprite(
					icon_b, attack_rect, flip_h,
					Color(modulate.r, modulate.g, modulate.b, modulate.a * icon_b_alpha_mult))
		var bar_w := icon_px
		var hp_y := top - BAR_HEIGHT - 4
		# 盤面の情報整理（2026-08-23、§6/§7「HPは下部キャラクター欄で確認
		# できるため盤面上には不要、Lvも常時表示の必要なし」）: 戦闘中
		# （_boss_screen_active()）はこの頭上HPバー＋Lv表示を丸ごと省略
		# する——下部の`_battle_bar`カード列（名前+HP+SP、無改修のまま
		# 常設）が同じ情報を既に持っているため。放置画面（探索中の党の
		# 頭上表示）は今回のスコープ外なので無改修のまま残す（放置画面
		# には代わりとなる常設パネルが存在しないため、そちらまで消すと
		# HP/SPを確認する手段が無くなってしまう）。
		if not _boss_screen_active():
			# エオスバーストv2 (2026-08-06): hide each unit's own overhead HP
			# bar for the skill's whole act phase (windup through recovery) —
			# user spec: "各ユニット頭上のワールド空間HPバーだけを一時的に
			# 非表示にし、終了後に必ず元へ戻してください。画面上部のボスHP
			# バーは残します。" _eos_burst_vfx_active() checks the currently-
			# queued act step's own skill_id, so it's already true/false for
			# the ENTIRE cast (not just the acting unit) and reverts to false
			# the instant the next queue step begins — no separate restore
			# logic needed. The boss banner's ProgressBar (_boss_banner_hp_bar)
			# lives entirely outside this loop and is untouched. Level text
			# stays visible ("だけ" = HP bar only).
			if not _eos_burst_vfx_active():
				draw_rect(Rect2(Vector2(x - bar_w / 2.0, hp_y), Vector2(bar_w, BAR_HEIGHT)), COLOR_HP_BAR_BG)
				var hp_display := _healing_display_hp(slot_index, unit.hp)
				var hp_frac := clampf(hp_display / float(maxi(1, sim.unit_max_hp(unit))), 0.0, 1.0)
				draw_rect(Rect2(Vector2(x - bar_w / 2.0, hp_y), Vector2(bar_w * hp_frac, BAR_HEIGHT)), COLOR_HP_BAR)
			draw_string(
				font, Vector2(x, hp_y - 6), "Lv.%d" % unit.level,
				HORIZONTAL_ALIGNMENT_CENTER, bar_w * 2, 13, COLOR_HUD_TEXT
			)
		# 味方対象選択マーク（2026-08-23、§8-§14）: 頭上HP/Lvを消した分の
		# 空きスペースへ、現在選択中の味方の頭上だけ▼型の三角形マーカーを
		# 表示する。プロトタイプ実装（指示どおり新規画像素材なし、
		# draw_primitiveのみ）——正式デザインは実機確認後。下部パネル側
		# の緑枠（COLOR_ALLY_TARGET_BORDER）と同じ色を使い、§14「UIを見
		# ても盤面を見ても同じ対象だと分かる」を色の一致で満たす。点滅・
		# フェード無し（§13）——描画するかしないかの二値のみ。
		if _boss_screen_active() and _battle_phase == "targetSelection" \
				and _battle_target_kind == "ally" and slot_index == _battle_selected_ally_target:
			_draw_ally_target_marker(x, top)


## 味方対象選択マーカー本体（2026-08-23）: `_draw_target_cursor`の敵側矢印
## (draw_primitiveで3頂点の三角形、`res://src/ui/main.gd`既存コード)と
## 同じ技法・同じ意味（現在の選択対象を指す）だが、対象がキャラクター
## 自身の頭上（`_draw_party_row`が計算済みのx/top、アニメーション中の
## オフセットも含めて既に反映済み）という点だけが異なる——新しい座標系や
## 追従ロジックを別途作らず、呼び出し側が既に持っている値をそのまま使う。
const ALLY_TARGET_MARKER_HALF_WIDTH_PX := 8.0
const ALLY_TARGET_MARKER_HEIGHT_PX := 11.0
const ALLY_TARGET_MARKER_GAP_PX := 8.0  # 三角形の先端(下端)と頭の間の隙間


func _draw_ally_target_marker(x: float, top: float) -> void:
	var apex_y := top - ALLY_TARGET_MARKER_GAP_PX
	var base_y := apex_y - ALLY_TARGET_MARKER_HEIGHT_PX
	draw_primitive(
		PackedVector2Array([
			Vector2(x - ALLY_TARGET_MARKER_HALF_WIDTH_PX, base_y),
			Vector2(x + ALLY_TARGET_MARKER_HALF_WIDTH_PX, base_y),
			Vector2(x, apex_y)]),
		PackedColorArray([COLOR_ALLY_TARGET_BORDER, COLOR_ALLY_TARGET_BORDER, COLOR_ALLY_TARGET_BORDER]),
		PackedVector2Array(), null)


## Idle-only nudge (2026-07-19 user request): after the front/back swap
## above, Vard reads as sitting a bit high in the idle view specifically —
## moved down a little there, but not in the boss arena (untouched, no
## complaint about that view). Keyed off the art variant (2 = companion_2
## = Vard) rather than a literal slot index, since — per PARTY_FORMATION's
## comment above — which slot Vard actually occupies depends on join
## order and isn't the same for every save.
const IDLE_VARD_Y_NUDGE: float = 0.03


func _formation_pos(slot_index: int) -> Vector2:
	if _boss_screen_active():
		return PARTY_FORMATION_BOSS[slot_index % PARTY_FORMATION_BOSS.size()]
	var pos := PARTY_FORMATION[slot_index % PARTY_FORMATION.size()]
	if _minion_art_variant(slot_index) == 2:
		pos.y += IDLE_VARD_Y_NUDGE
	return pos


## draw_texture_rect with optional horizontal mirroring: every sheet faces
## right natively, so walking back to formation (moving left) flips.
## Mirrors around the rect's own vertical center line via a canvas
## transform (scale.x = -1 maps x -> origin.x - x, so origin.x = left*2 +
## width makes the rect land back on itself, reversed).
func _draw_sprite(icon: Texture2D, rect: Rect2, flip_h: bool, modulate: Color = Color.WHITE) -> void:
	if flip_h:
		draw_set_transform(
			Vector2(rect.position.x * 2.0 + rect.size.x, 0.0), 0.0, Vector2(-1.0, 1.0))
		draw_texture_rect(icon, rect, false, modulate)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect(icon, rect, false, modulate)


## The old compact linear row, kept for the resident strip only.
func _draw_party_row_strip(view: Rect2) -> void:
	var icon_px := _resident_icon_px(view)
	var count := sim.minions.size()
	var spacing := minf(icon_px * 0.6, view.size.x / float(count + 1))
	var start_x := view.position.x + view.size.x * SIDE_MARGIN_FRAC
	var ground_y := _ground_y(view)
	var top := maxf(view.position.y, ground_y - icon_px)
	for slot_index in count:
		var unit: UDMinion = sim.minions[slot_index]
		var x := start_x + spacing * slot_index
		var art_variant := _minion_art_variant(slot_index)
		var art_key := art.minion_key(art_variant)
		var icon := art.icon_or_placeholder(art_key, "minion_%d" % slot_index, "rune")
		draw_texture_rect(
			icon, Rect2(Vector2(x - icon_px / 2.0, top), Vector2(icon_px, icon_px)), false)
		var hp_y := top - BAR_HEIGHT - 4
		draw_rect(Rect2(Vector2(x - icon_px / 2.0, hp_y), Vector2(icon_px, BAR_HEIGHT)), COLOR_HP_BAR_BG)
		var hp_frac := clampf(float(unit.hp) / float(maxi(1, sim.unit_max_hp(unit))), 0.0, 1.0)
		draw_rect(Rect2(Vector2(x - icon_px / 2.0, hp_y), Vector2(icon_px * hp_frac, BAR_HEIGHT)), COLOR_HP_BAR)


## Party slot -> art variant. Slot 0 is always the protagonist; slot N
## (N>=1) corresponds to sim.companions[N-1] in join order, so the art
## key is looked up by companion identity rather than the slot index
## (fixes companions rendering as an unnamed placeholder block).
func _minion_art_variant(slot_index: int) -> int:
	if slot_index == 0:
		return 0
	var companion_index := slot_index - 1
	if companion_index < sim.companions.size():
		return UDMinion.art_variant_for_companion(sim.companions[companion_index])
	return slot_index


func _build_hud() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -PANEL_WIDTH
	panel.offset_right = -4
	panel.offset_top = HUD_HEIGHT + 4
	panel.offset_bottom = -4
	add_child(panel)
	_button_bar = panel

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	panel.add_child(grid)

	_fight_button = _make_button("", _on_fight_button)
	grid.add_child(_fight_button)
	for facility_id in facility_db.all_ids():
		# 新企画v1 §24 (2026-08-18): 祭壇は廃止対象のためUI導線から外す —
		# sim側のaltar_levelフィールド・_build_altar_dialog()自体はまだ
		# 削除しない(宝物再設計と合わせてフェーズ3で扱う)。
		if facility_id == "altar":
			continue
		var button := _make_button("", _on_facility_button.bind(facility_id))
		_facility_buttons[facility_id] = button
		grid.add_child(button)
	_archive_button = _make_button("", _open_archive)
	grid.add_child(_archive_button)
	# 新企画v1 §16/§24 (2026-08-18): 従来型ショップ・宝箱は廃止対象。
	# _treasure_button/_shop_button自体はここで組み立てるが(他の関数が
	# null チェックなしで参照するため)、gridへ追加せずUI導線からだけ外す
	# — _build_shop_dialog()/_build_treasure_dialog()自体はまだ削除しない。
	_treasure_button = _make_button("", _open_treasures)
	_shop_button = _make_button("", _open_shop)
	_inn_button = _make_button("", _open_inn)
	grid.add_child(_inn_button)
	_height_button = _make_button("", _cycle_height)
	grid.add_child(_height_button)
	_locale_button = _make_button("", _toggle_locale)
	grid.add_child(_locale_button)
	_collapse_button = _make_button("", _collapse)
	grid.add_child(_collapse_button)
	_quit_button = _make_button("", _quit)
	grid.add_child(_quit_button)


func _make_button(label: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = BUTTON_MIN_SIZE
	button.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	button.pressed.connect(callback)
	return button


## Facility buttons: pressing the button unlocks the facility outright
## (one-time cost via buy_upgrade, max_level 1), then opens its screen.
func _on_facility_button(facility_id: String) -> void:
	if sim.upgrade_level(facility_id) <= 0 and not _auto_build(facility_id):
		return
	match facility_id:
		"altar":
			_open_altar()
		"tavern":
			_open_guild()
		"dorm":
			_open_dorm()


func _auto_build(facility_id: String) -> bool:
	var def := facility_db.get_good(facility_id)
	if sim.buy_upgrade(def):
		return true
	_tally_text = locale.text("UI_BUILD_CANNOT_AFFORD") % locale.text(def["name_key"])
	_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
	return false


func _refresh_archive_button() -> void:
	if _archive_button == null:
		return
	var label := locale.text("UI_ARCHIVE")
	if not unread_docs.is_empty():
		label += " (%d)" % unread_docs.size()
	_archive_button.text = label


func _refresh_fight_button() -> void:
	if _fight_button == null:
		return
	var at_gate := stage_db.is_boss_stage(sim.stage_index)
	var rematch := not at_gate \
		and stage_db.last_boss_id_at_or_below(sim.stage_index) != ""
	_fight_button.disabled = not (at_gate or rematch)
	if at_gate:
		_fight_button.text = locale.text("UI_FIGHT_GATE")
	elif rematch:
		_fight_button.text = locale.text("UI_FIGHT_REMATCH")
	else:
		_fight_button.text = locale.text("UI_FIGHT_NONE")


func _refresh_button_texts() -> void:
	for facility_id: String in _facility_buttons:
		var button: Button = _facility_buttons[facility_id]
		button.text = locale.text(facility_db.get_good(facility_id)["name_key"])
	_refresh_fight_button()
	_height_button.text = "%dpx" % UD.WINDOW_HEIGHTS[settings.height_index]
	_collapse_button.text = locale.text("UI_COLLAPSE")
	_treasure_button.text = "%s(%d)" % [locale.text("UI_TREASURES"), sim.distinct_items()]
	_shop_button.text = locale.text("UI_SHOP")
	_inn_button.text = locale.text("UI_INN")
	_locale_button.text = _next_locale_code().to_upper()
	_quit_button.text = locale.text("UI_QUIT")
	_refresh_archive_button()


func _next_locale_code() -> String:
	var index := UD.SUPPORTED_LOCALES.find(settings.locale_code)
	return UD.SUPPORTED_LOCALES[(index + 1) % UD.SUPPORTED_LOCALES.size()]


## Strip = taskbar-look ambient view. Expanded = centered window for
## reading documents and giving orders. Clicking the strip expands.
func _apply_window_mode() -> void:
	_sync_battle_chrome_visibility()
	if settings.resident_mode:
		UDResidentWindow.setup_resident(get_window(), settings.height_index)
	else:
		UDResidentWindow.setup_expanded(get_window())
	queue_redraw()


## The facility/menu button panel and the battle screen (boss banner,
## card bar, pause button) are mutually exclusive, and both are always
## hidden in resident mode (its own compact layout is a separate,
## intentionally-untouched design — see main.gd's file header). Centralized
## here so window-mode changes and battle start/end can't disagree about
## what should be showing.
func _sync_battle_chrome_visibility() -> void:
	var battle := _boss_screen_active() and not settings.resident_mode
	_button_bar.visible = not settings.resident_mode and not _boss_screen_active()
	_boss_banner.visible = battle
	_battle_bar.visible = battle
	_quit_battle_button.visible = battle
	_leave_battle_button.visible = battle
	if not battle:
		_battle_list_panel.visible = false
		_rewind_confirm_panel.visible = false


func _expand() -> void:
	settings.resident_mode = false
	settings.save()
	_apply_window_mode()
	_refresh_button_texts()
	if sim.boss_active:
		_refresh_boss_panel()


func _format_offline_summary() -> String:
	var gold_gained := int(sim.inventory.get(UD.RES_GOLD, 0)) - _offline_gold_before
	var exp_gained := sim.exp_pool - _offline_exp_before
	return locale.text("UI_OFFLINE_EARNED") % [maxi(0, exp_gained), maxi(0, gold_gained)]


func _collapse() -> void:
	settings.resident_mode = true
	settings.save()
	_apply_window_mode()


func _cycle_height() -> void:
	settings.height_index = (settings.height_index + 1) % UD.WINDOW_HEIGHTS.size()
	settings.save()
	if settings.resident_mode:
		UDResidentWindow.setup_resident(get_window(), settings.height_index)
	_refresh_button_texts()


func _toggle_locale() -> void:
	settings.locale_code = _next_locale_code()
	settings.save()
	locale = UDLocale.load_locale(settings.locale_code)
	_refresh_button_texts()
	queue_redraw()


## --- Boss encounter (turn-based, manual only) -------------------------

func _on_fight_button() -> void:
	if sim.boss_active:
		# Resuming an already-active encounter (not fled, not rewound) —
		# whatever's mid-turn is still relevant, unlike a genuinely fresh
		# attempt below.
		_show_boss_panel()
		return
	if sim.start_boss_fight():
		_clear_battle_message()
		_show_boss_panel()


## --- Boss banner (top: name + HP) --------------------------------------

## Bright, high-contrast text color shared by every HP-panel/part-row
## label in this banner (新企画v1 §8 playtest pass, 2026-08-21 — the first
## prototype's Color(0.85,0.85,0.85) read as too dim against real
## backgrounds during an actual playthrough).
# 視認性改善（2026-08-22）: 前回(0.85→0.97,0.95,0.88)でもまだ薄いという
# 実機報告——今回は純白まで踏み込む。あわせて、この定数を今まで使って
# いなかった周辺ラベル（ボス名・対象選択パネルの見出し/案内文/対象名・
# 行リストのボタン文字）にも新たに適用し、"一部だけ強いが他はGodotの
# テーマ既定色のまま"という不揃いを解消する。
const COLOR_BOSS_PANEL_TEXT := Color(1.0, 1.0, 1.0)
# 「破壊済」等の非アクティブ状態は意図的に少し控えめのまま（重要度の
# 低さを示す）だが、読めないほど暗くはしない——0.6台→0.68台へ底上げ。
const COLOR_BOSS_PART_DESTROYED_TEXT := Color(0.68, 0.63, 0.56)


func _build_boss_banner() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 220
	panel.offset_right = -220
	panel.offset_top = 10
	# レスポンシブUI基盤（2026-08-21）: 旧来はoffset_bottom=130の固定高
	# だった（cave_trollの部位2個ぶんに手動で合わせた値）——将来部位
	# 数の多いボスが増えると同じ理由で見切れる。_battle_barと同じ
	# パターンで、上端固定・内容（本体行＋_boss_parts_columnの実際の
	# 行数）に合わせて下へ自動的に伸びる形に変更し、何部位あっても
	# 決め打ちの高さと衝突しないようにする。
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.05, 0.09, 0.85)))
	add_child(panel)
	_boss_banner = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	panel.add_child(column)

	_boss_banner_label = Label.new()
	_boss_banner_label.add_theme_font_size_override("font_size", 18)
	_boss_banner_label.modulate = COLOR_BOSS_PANEL_TEXT
	_boss_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_boss_banner_label)

	var body_row := HBoxContainer.new()
	body_row.add_theme_constant_override("separation", 6)
	column.add_child(body_row)

	var body_name_label := Label.new()
	body_name_label.text = locale.text("UI_PART_MAIN_BODY")
	body_name_label.add_theme_font_size_override("font_size", 14)
	body_name_label.modulate = COLOR_BOSS_PANEL_TEXT
	body_row.add_child(body_name_label)

	_boss_banner_hp_bar = ProgressBar.new()
	_boss_banner_hp_bar.show_percentage = false
	_boss_banner_hp_bar.custom_minimum_size = Vector2(0, 14)
	_boss_banner_hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_bar(_boss_banner_hp_bar, COLOR_HP_BAR_BG, COLOR_ENEMY_HP_BAR)
	body_row.add_child(_boss_banner_hp_bar)

	_boss_body_hp_label = Label.new()
	_boss_body_hp_label.add_theme_font_size_override("font_size", 13)
	_boss_body_hp_label.modulate = COLOR_BOSS_PANEL_TEXT
	body_row.add_child(_boss_body_hp_label)

	_boss_parts_column = VBoxContainer.new()
	_boss_parts_column.add_theme_constant_override("separation", 3)
	_boss_parts_column.visible = false
	column.add_child(_boss_parts_column)


## margin省略時は10（既存の全呼び出し元と完全互換）。下部操作バー圧縮
## （2026-08-22c）で、バー本体/対象選択パネル/カード/バトルメッセージ
## パネルの4箇所だけ小さい値を明示的に渡す——それ以外（ボスバナー、
## スキル/どうぐ右ドッキングパネル、REWIND確認ダイアログ等）は無改修
## のまま既定の10を使い続ける。
## draw_border省略時はtrue（既存の全呼び出し元と完全互換）。下部UI再
## 整理（2026-08-23b、§3-§4「上端の3本線を1本に」）で`_battle_message_
## panel`だけfalseを渡す——原因は`bar`自身の上端border(2px)のすぐ内側
## （バー自身のcontent margin 5pxしか離れていない）に、メッセージが
## 0行のときほぼ潰れた高さのまま存在し続けるメッセージパネル自身の
## 上下2本のborder(各2px)が密集して重なって見えていたこと（3本目の
## 正体はメッセージパネル自身の下端border）。他のパネル（ボスバナー・
## カード・対象選択パネル等）はこの上端の境界に隣接していないため
## border自体は無改修のまま——「1つの重複箇所だけ整理する」判断。
func _panel_style(bg_color: Color, margin: int = 10, draw_border: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = Color(0.55, 0.42, 0.18)
	style.set_border_width_all(2 if draw_border else 0)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(margin)
	return style


func _style_bar(bar: ProgressBar, bg_color: Color, fill_color: Color) -> void:
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = bg_color
	bg_style.set_corner_radius_all(3)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = fill_color
	fill_style.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg_style)
	bar.add_theme_stylebox_override("fill", fill_style)


## Normal/hover/disabled StyleBoxFlats so a command button's usable state
## reads as a color change (gold 行動開始, blue にげる, dark when
## unusable) instead of relying on the default theme's dimming alone.
## content_margin省略時は8（既存の全呼び出し元と完全互換）。下部操作
## バー圧縮（2026-08-22c）で対象選択パネルのもどるボタンだけ小さい値
## を明示的に渡す。
func _style_button(button: Button, enabled_color: Color, content_margin: int = 8) -> void:
	var disabled_color := Color(0.14, 0.14, 0.18)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = enabled_color.lightened(0.12) if state == "hover" else enabled_color
		style.set_corner_radius_all(6)
		style.set_content_margin_all(content_margin)
		button.add_theme_stylebox_override(state, style)
	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color = disabled_color
	disabled_style.set_corner_radius_all(6)
	disabled_style.set_content_margin_all(content_margin)
	button.add_theme_stylebox_override("disabled", disabled_style)


## --- Battle command bar (bottom: cards + attack/skill/item + start) ----
## No flee command (removed 2026-07-19 — the only manual battles are gate
## bosses, and giving up is now the top-right やめる button instead, which
## reuses the same sim.flee_boss_fight() and always works rather than
## being conditionally enabled).

const COLOR_CARD_BORDER := Color(0.32, 0.34, 0.44)
const COLOR_CARD_BORDER_SELECTED := Color(1.0, 0.82, 0.25)
const COLOR_START_BUTTON := Color(0.72, 0.53, 0.12)


func _build_battle_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 12
	bar.offset_right = -12
	# 下部操作バー再調整（2026-08-22d、§1「少し縮めすぎた、以前と現在の
	# 中間程度へ」）: 12（以前）→6（圧縮直後）→4。ここはキャラクター情報
	# 側へ回した純粋な余白のため、視覚的な"存在感"には寄与しない部分から
	# 優先的に削った（円のクリアランス確保とカード拡大の綱引きの結果）。
	# 下部UI再整理（2026-08-23b）: -6は無改修（ウィンドウ下端との隙間は
	# §16「キャラクター配置」寄りの既存レイアウト、今回のスコープ外）。
	bar.offset_bottom = -6
	# レスポンシブUI基盤（2026-08-21）: 旧来はoffset_top=-168の固定高だっ
	# たため、対象選択パネルに部位ターゲット行(enemy_target_rows)を追加
	# した際、内容がこの固定枠を超えて決定ボタンごと画面外へ押し出さ
	# れていた（解像度に関係なく起きる本物のオーバーフローで、ウィン
	# ドウが小さいとさらに悪化していた）。offset_topを外しgrow_vertical
	# =BEGINにすると、GodotのContainerが「下端固定・現在表示中の子
	# （_commands_columnかtarget_confirm_panelか、非表示側は最小サイズ
	# 計算から自動的に除外される）の自然な最小高さぶんだけ上へ伸びる」
	# 形で毎回自動的にサイズを決め直す——部位数が何個でも、フォント
	# サイズが変わっても、二度とこの種のオーバーフローが起きない。
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.visible = false
	# 下部操作バー再調整（2026-08-22d）: 外周パネルの余白10（以前）→4
	# （圧縮直後）→3。純粋なchrome余白のため最小限に抑え、その分を
	# カードの立ち絵アイコン等の"見える"要素へ回した。
	# 下部UI再整理（2026-08-23b、§1/§2「増えた高さはpaddingではなく可読性
	# へ」）: 5→3。メッセージパネル自身の余白・outer_columnの間隔と合わせ
	# 縦方向のchromeをさらに切り詰め（合計約7px reclaim）、その分をカード/
	# コマンドの実コンテンツ側の高さ成長に充てる予算として使った——padding
	# を"増やして"高さを消費しているわけではなく、既存paddingを削って
	# 生まれた余地を可読性側へ回す方向（§2の趣旨どおり）。
	bar.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.05, 0.1, 0.92), 3))
	add_child(bar)
	_battle_bar = bar

	# バトルメッセージを既存の行の"下"に積む単一のVBoxContainerへ変更
	# （2026-08-22b、§4「さらに下へ」）——bar自身のgrow_vertical=BEGIN
	# (上記)は「唯一の子の自然な最小サイズ」から高さを決め直す設計の
	# ため、この1本の縦積みへ含めるだけで、対象選択の行数がいくつでも
	# メッセージを含めた全体が自動的に画面内へ収まる（新しい固定pxの
	# 高さ計算を一切増やさずに済む）。
	# 位置を元へ戻す（2026-08-22c、§1「バトルメッセージの位置は元の位置
	# へ戻す」）: 2026-08-22bで一度row（カード/コマンド）の下＝画面の
	# 一番下寄りへ移動したが、実機確認で違和感があったため撤回——
	# outer_columnの先頭（rowより前）へ戻す。メッセージの中身（現在
	# 行動中の1キャラクター/敵だけ表示・次の行動者で入れ替え・蓄積しない）
	# 自体は_append_battle_message/_clear_battle_messageのロジック側の
	# 話で、この位置変更とは無関係のため無改修のまま。
	var outer_column := VBoxContainer.new()
	# 下部操作バー再調整（2026-08-22d）: 6（以前）→2（圧縮直後）→1。
	# 下部UI再整理（2026-08-23b）: 2→1（chrome reclaim、上記bar余白と
	# 同じ理由）。
	outer_column.add_theme_constant_override("separation", 1)
	bar.add_child(outer_column)

	_build_battle_message_panel(outer_column)

	# 横方向の空白整理（2026-08-22d、§4-6「キャラクター欄とコマンド欄の
	# 間の巨大な空白をなくす」）: 真因はcards_row（下記）が
	# SIZE_EXPAND_FILLで`row`の余りの横幅を丸ごと占有し、その中で5枚の
	# カード自体は左詰めのまま——「カードの右端からcommands_columnまで」
	# の間に、cards_rowが確保したのに使っていない空間がそのまま空白として
	# 見えていた（画面の中央付近が広く空くほど、5人分のカード幅とコマンド
	# 幅の合計は1128px幅のバーよりずっと小さいため）。cards_row自体を
	# 自然幅（EXPAND_FILLを外す）にし、`row`全体をalignment=CENTERで
	# 中央寄せすることで、余った横幅は「カードとコマンドの間」ではなく
	# 「バー全体の左右」へ均等に逃がす——情報のまとまりとしては密集して
	# 見えつつ、中央に不自然な空白帯を作らない。
	# 下部UI再整理（2026-08-23b、§5-11「横幅いっぱいを使う、新情報を足さず
	# 既存の5人分/コマンドへ再配分」）: 上記の"中央寄せで余白を左右へ
	# 逃がす"方針自体はそのまま維持しつつ、cards_row/commands_columnの
	# **中身が実際に受け取る幅**を広げた——alignment=CENTERは無改修、
	# 固定separation(28)も無改修（「詰めるのではなく再配分」§11の"ブロック
	# 間の意図的な余白"はそのまま）。widthはcustom_minimum_size（Container
	# の"floor"、絶対座標ではない）＋各カードのSIZE_EXPAND_FILL（下記）で
	# Godot自身に配分させる——固定座標で5パネルを直接配置する方式は使わ
	# ない（§14の明示指示）。
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	# 「5人→すぐ隣にコマンド、というほど詰めない」（§5）: cards_rowと
	# commands_column/target_confirm_panelの間の意図的な余白として、
	# 単純な自動拡張ではなく固定量のseparationへ変更（10→28）。
	row.add_theme_constant_override("separation", 28)
	outer_column.add_child(row)

	var cards_row := HBoxContainer.new()
	cards_row.name = "cards"
	cards_row.add_theme_constant_override("separation", 8)
	# 下部UI再整理（2026-08-23b、§7/§8「5人分の幅を少し広げる、均等に」）:
	# cards_row自体にfloorとなる合計幅を与え（512→660、+148px）、その内側の
	# 5枚は下記_make_battle_card()で各々size_flags_horizontal=EXPAND_FILL
	# （既定stretch_ratio=1ずつ、全員同じ）にしてある——cards_rowが確保した
	# 660pxを5枚が均等に分け合う（1枚あたり約125.6px、旧96pxから+30px弱）。
	# 名前の文字数で幅がバラつく余地が構造的に無い（Godotの均等EXPAND_FILL
	# 分配そのものが保証する、個別に同じ定数を手で揃えていた旧実装より
	# 頑健）。
	cards_row.custom_minimum_size = Vector2(660, 0)
	row.add_child(cards_row)

	# こうげき/スキル/どうぐ in a row, 行動開始 spanning the same width
	# below them (not beside), per the reference layout.
	_commands_column = VBoxContainer.new()
	# 下部操作バー圧縮（2026-08-22c）: 6→2。
	_commands_column.add_theme_constant_override("separation", 4)
	# 下部UI再整理（2026-08-23b、§9「コマンドエリアも空いた横幅を少し
	# 利用」）: cards_rowと同じ考え方でfloorを与える（自然幅の約180px→
	# 260px）。アイコン自体は下記で少しだけ拡大するに留め（§9「巨大な
	# ボタンにする必要はない」）、増えた分の幅は主に「行動開始」ボタン
	# （既存のSIZE_EXPAND_FILLでこの列の全幅へ自動的に広がる）と、アイコン
	# 列を中央寄せする余白（下記commands_row.alignment）へ回る。
	_commands_column.custom_minimum_size = Vector2(260, 0)
	row.add_child(_commands_column)

	var commands_row := HBoxContainer.new()
	commands_row.add_theme_constant_override("separation", 6)
	# 下部UI再整理（2026-08-23b）: commands_columnがアイコン3個の自然幅
	# より広くなった分、アイコンが左詰めで浮かないよう中央寄せする
	# （cards側の"均等配分"とは違い、こちらは"密集したグループを広い
	# 列の中央へ"という役割——アイコン自体を引き伸ばして巨大化させない
	# ため、EXPAND_FILLではなくalignment=CENTERを選択）。
	commands_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_commands_column.add_child(commands_row)

	_battle_attack_button = _make_texture_command_button("battle_button_attack", _on_battle_attack)
	commands_row.add_child(_battle_attack_button)
	_battle_skill_button = _make_texture_command_button("battle_button_skill", _on_battle_skill)
	commands_row.add_child(_battle_skill_button)
	_battle_item_button = _make_texture_command_button("battle_button_item", _on_battle_item)
	commands_row.add_child(_battle_item_button)

	_battle_start_button = TextureButton.new()
	_battle_start_button.texture_normal = art.texture("battle_button_start")
	_battle_start_button.ignore_texture_size = true
	_battle_start_button.stretch_mode = TextureButton.STRETCH_SCALE
	# 下部操作バー再調整（2026-08-22d、§9「行動開始が操作UIとして弱く
	# 見えないように」）: 50→28（前ラウンド）→38。
	# 下部UI再整理（2026-08-23b、§1/§9）: 38→42→40→44→45→44。**42まで拡大
	# した時点の実測でアイコン(56)+42+separationの合計がcards_row(約99px)
	# を上回り、`row`全体の高さ（＝commandsが常にcards_rowと同時に表示
	# される状態Bの最悪ケース）を新たに押し上げ、円の足元マージンが一時的
	# にマイナスへ振れる不具合を実測で検出——一度40へ落として解消したが、
	# その後cards_row側の高さ自体をchrome再配分＋バー太さ増で伸びたため
	# 再び釣り合う値まで引き上げ、最後にバー太さを1段戻した（9、上記）の
	# に合わせてこちらも44へ1段戻した——最終的な余白は毎回probeで実測して
	# 確認する。
	_battle_start_button.custom_minimum_size = Vector2(0, 44)
	_battle_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_battle_start_button.pressed.connect(_on_boss_resolve_round)
	_commands_column.add_child(_battle_start_button)

	# Swaps into _commands_column's slot in `row` during target selection
	# (2026-07-19) rather than floating as a separate box, so it never
	# overlaps the card row and always sits where commands normally are.
	_target_confirm_panel = PanelContainer.new()
	_target_confirm_panel.visible = false
	# 下部操作バー圧縮（2026-08-22c）: 余白10→2。
	_target_confirm_panel.add_theme_stylebox_override(
		"panel", _panel_style(Color(0.06, 0.07, 0.12, 0.95), 1))
	row.add_child(_target_confirm_panel)

	var target_column := VBoxContainer.new()
	# 下部操作バー圧縮（2026-08-22c）: 4→0。加えて、enemy_target_rows
	# （下記、横並びFlowContainerへ変更）が折り返す前に十分な横幅を
	# 確保できるよう最小幅を明示（HBoxContainer内で自然幅のまま伸縮
	# しないと、行が伸び続けて折り返しが発生しない＝縦方向の節約効果が
	# 出ないため）。
	target_column.add_theme_constant_override("separation", 0)
	target_column.custom_minimum_size = Vector2(360, 0)
	_target_confirm_panel.add_child(target_column)

	var target_title := Label.new()
	target_title.name = "target_title"
	target_title.text = locale.text("UI_BOSS_TARGET_TITLE")
	# 下部操作バー圧縮（2026-08-22c）: 15→13（パネル内の他テキストと揃え、
	# 対象選択パネル自体の高さ予算を詰める）。
	target_title.add_theme_font_size_override("font_size", 13)
	target_title.modulate = COLOR_BOSS_PANEL_TEXT
	target_column.add_child(target_title)

	var target_instruction := Label.new()
	target_instruction.name = "target_instruction"
	target_instruction.text = locale.text("UI_BOSS_TARGET_INSTRUCTION")
	target_instruction.add_theme_font_size_override("font_size", 11)
	target_instruction.modulate = COLOR_BOSS_PANEL_TEXT
	target_column.add_child(target_instruction)

	# One clickable row per entry in _battle_enemy_targets() (新企画v1仕様書
	# v2 §2/§3, 2026-08-21 playtest fix): before this, picking a body part
	# as an attack target only worked via the crosshair's left/right-arrow
	# cycling, with no on-screen hint that it was even possible — real
	# playtesting confirmed this read as "parts can't be targeted at all".
	# Rebuilt per _refresh_target_panel() call; hidden for an ally-target
	# skill or a boss with nothing else to pick (_enter_target_selection
	# already skips straight past this whole panel when enemy_targets.
	# size()==1, so this stays empty and invisible for every non-parted
	# boss — untouched behavior).
	# レスポンシブUI基盤（2026-08-21）: barがgrow_vertical=BEGINで内容に
	# 合わせて自動的に高さを決め直すようになった（_build_battle_bar）
	# ため、この行リストは何行あっても見切れることが構造的に無くなっ
	# た——固定pxの高さ上限やScrollContainerでの人為的な打ち切りは、
	# 「将来また特定の行数を想定して壊れる」余地を残すだけなので採用
	# しない（通常のボスの部位数は多くない想定、§8の「詰め込みより
	# 操作性を優先」に対応）。
	# 下部操作バー圧縮（2026-08-22c）: VBoxContainer（本体/右腕/脚を縦に
	# 積む）からHFlowContainer（横に並べ、幅に収まらない分だけ自動的に
	# 折り返す）へ変更——選択肢の内容・個数・クリック挙動は無改修のまま、
	# 縦方向の占有だけを大きく削減する（3行→1〜2行）。折り返しは
	# target_columnのcustom_minimum_size.x（上記）が与える幅予算の中で
	# Godotが自動的に行うため、将来ボスの部位数が増えても固定行数の
	# 前提を壊さない（レスポンシブUI基盤の「決め打ちの高さ上限を作ら
	# ない」方針をそのまま継承）。
	var enemy_target_rows := HFlowContainer.new()
	enemy_target_rows.name = "enemy_target_rows"
	enemy_target_rows.add_theme_constant_override("h_separation", 4)
	enemy_target_rows.add_theme_constant_override("v_separation", 2)
	target_column.add_child(enemy_target_rows)

	# 下部操作バー圧縮（2026-08-22c）: 「スキル」「対象」を縦2行から
	# 横1行へ統合——文字情報は変えず、レイアウトだけで1行ぶん節約する。
	var target_info_row := HBoxContainer.new()
	target_info_row.add_theme_constant_override("separation", 14)
	target_column.add_child(target_info_row)

	var target_skill_line := Label.new()
	target_skill_line.name = "skill_line"
	target_skill_line.add_theme_font_size_override("font_size", 13)
	target_skill_line.modulate = COLOR_BOSS_PANEL_TEXT
	target_info_row.add_child(target_skill_line)

	var target_target_line := Label.new()
	target_target_line.name = "target_line"
	target_target_line.add_theme_font_size_override("font_size", 13)
	target_target_line.modulate = COLOR_BOSS_PANEL_TEXT
	target_info_row.add_child(target_target_line)

	var target_footer := HBoxContainer.new()
	target_footer.add_theme_constant_override("separation", 8)
	target_column.add_child(target_footer)
	var target_back_button := Button.new()
	target_back_button.text = locale.text("UI_BOSS_BACK")
	target_back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 下部操作バー圧縮（2026-08-22c）: 従来は無スタイルでGodotの既定
	# テーマ（既定フォント16pt・縦方向に大きめの余白を持つ）に頼って
	# いた——他の下部バーボタンと同じ薄型スタイル（もどるボタンと同系色）
	# ＋パネル内の他テキストと揃えた13ptを明示適用。
	_style_button(target_back_button, Color(0.28, 0.24, 0.32), 5)
	target_back_button.add_theme_font_size_override("font_size", 13)
	target_back_button.pressed.connect(_on_target_back)
	target_footer.add_child(target_back_button)
	var target_confirm_button := Button.new()
	target_confirm_button.text = locale.text("UI_BOSS_CONFIRM")
	target_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(target_confirm_button, COLOR_START_BUTTON, 5)
	target_confirm_button.add_theme_font_size_override("font_size", 13)
	target_confirm_button.pressed.connect(_on_target_confirm)
	target_footer.add_child(target_confirm_button)


## バトルメッセージ本体（新企画v1仕様書, 2026-08-22〜22c）: 「ソティリス
## のラピッドスラッシュ！」→「洞窟トロルの右腕に84ダメージ！」のような、ダメージ
## 数字（既存の頭上ポップアップ、無改修のまま維持）とは別に「今まさに
## 行動している1キャラクター/敵について、誰が・何をして・どこへ・何が
## 起きたか」を文章で確認できる領域。固定BATTLE_MESSAGE_MAX_LINES行の
## Labelを最初に一度だけ作り、以降は_refresh_battle_message_labels()が
## テキスト/色を書き換えるだけ（行の追加削除を毎回せず、既存の"固定
## 要素は固定サイズで良い"方針のまま——bar自体の自動拡張(grow_vertical)
## には行数一定でも変わらず参加する）。3行（旧4行から2026-08-22bで削減
## ——§5「履歴を表示しなくなるため大きな領域は不要」、1ターン最大の
## 例（宣言+ダメージ+部位破壊）がちょうど3行に収まる）。
const BATTLE_MESSAGE_MAX_LINES := 3
const COLOR_BATTLE_MESSAGE_SPECIAL := Color(1.0, 0.85, 0.2)  # COLOR_PART_BREAK_POPUPと同じ「特別な出来事」語彙を再利用


func _build_battle_message_panel(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	# 下部操作バー圧縮（2026-08-22c）: 余白10→4。文字サイズ(13pt)・
	# アウトラインは無改修——§11「必要以上に大きくしない」は余白側で
	# 対応し、メッセージ本文の可読性はそのまま維持する。
	# 下部UI再整理（2026-08-23b）: 3→2（chrome reclaim、border撤去と合わせ
	# メッセージパネル自身の縦方向フットプリントをさらに切り詰める）。
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.04, 0.05, 0.09, 0.72), 2, false))
	parent.add_child(panel)
	_battle_message_panel = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	_battle_message_labels.clear()
	for i in BATTLE_MESSAGE_MAX_LINES:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", COLOR_BOSS_PANEL_TEXT)
		# §8「文字のアウトライン...を必要に応じて」— 背景パネル自体が
		# 半透明の暗色（上のstylebox）なので黒アウトラインは薄めで足りる。
		label.add_theme_color_override("font_outline_color", COLOR_POPUP_OUTLINE)
		label.add_theme_constant_override("outline_size", 2)
		label.text = ""
		label.visible = false
		column.add_child(label)
		_battle_message_labels.append(label)


## 唯一の追加口（§4/§12「任意の戦闘メッセージを追加できる構造」）——
## ダメージ発生時の自動生成専用ではなく、いつでもどこからでも呼べる。
## 将来の特殊ボスAI/特殊条件はこの関数を直接呼ぶだけでよい。kind=
## "special"は§9の"少し目立たせる"扱い（現状は色を変えるだけ、専用の
## 演出は特殊ボス制作時に決める）。**新しい行動者のターンが始まる際は
## 必ず先に_clear_battle_message()を呼ぶこと**——この関数自体は積み
## 増すだけで、ターン境界の判定は呼び出し側（_advance_battle_anim_
## step等）の責任（2026-08-22b、§2「前の行動者の文章を残さない」）。
func _append_battle_message(text: String, kind: String = "normal") -> void:
	_battle_message_lines.append({"text": text, "kind": kind})
	while _battle_message_lines.size() > BATTLE_MESSAGE_MAX_LINES:
		_battle_message_lines.pop_front()
	_refresh_battle_message_labels()


## 行動者が切り替わった瞬間・REWIND・新しい遭遇の開始で呼ぶ——前の
## 内容を完全に消してから、必要なら呼び出し側が新しい1行目を積む。
func _clear_battle_message() -> void:
	_battle_message_lines.clear()
	_refresh_battle_message_labels()


func _refresh_battle_message_labels() -> void:
	if _battle_message_labels.is_empty():
		return
	for i in BATTLE_MESSAGE_MAX_LINES:
		var label := _battle_message_labels[i]
		if i < _battle_message_lines.size():
			var entry: Dictionary = _battle_message_lines[i]
			label.text = str(entry["text"])
			label.modulate = (
				COLOR_BATTLE_MESSAGE_SPECIAL if str(entry.get("kind", "normal")) == "special"
				else COLOR_BOSS_PANEL_TEXT)
			label.visible = true
		else:
			label.text = ""
			label.visible = false


## Real art from the delivered mockup (assets/art/battle_button_*.png,
## label already baked into the image) shown via TextureButton — Godot's
## built-in "image that's also a clickable hit target" node, the engine
## equivalent of overlaying a transparent click layer on an <img> (user
## direction, 2026-07-19: replace the StyleBoxFlat approximation with the
## real button art). No texture_disabled art exists, so unusable buttons
## are dimmed via modulate instead (_update_battle_buttons).
func _make_texture_command_button(art_key: String, callback: Callable) -> TextureButton:
	var button := TextureButton.new()
	var tex := art.texture(art_key)
	button.texture_normal = tex
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	# 下部操作バー再調整（2026-08-22d）: 64→38（前ラウンド）→50。
	# 下部UI再整理（2026-08-23b、§9）: 50→56→54→55→56→55。cards_row側の
	# 高さ（カード内間隔・バー太さ調整で伸びた）とおおよそ釣り合う値まで
	# 再調整——完全一致は不要（どちらが高くても`row`はその高い方に揃う
	# だけ）だが、極端に差が開くと"どちらかだけ浮いて見える"ため近い値を
	# 選ぶ。アイコンなのでフォントサイズには影響しない。
	var height := 55.0
	var aspect := float(tex.get_width()) / float(tex.get_height())
	button.custom_minimum_size = Vector2(height * aspect, height)
	button.pressed.connect(callback)
	return button


## Fixed left-to-right seating (Sotiris, then companion_1..4) regardless
## of join order — see _battle_order's declaration. Only living units.
func _battle_display_order() -> Array[int]:
	var order: Array[int] = []
	if sim.minions.size() > 0 and sim.minions[0].hp > 0:
		order.append(0)
	for companion_id in UD.BATTLE_CARD_COMPANION_ORDER:
		var companion_index := sim.companions.find(companion_id)
		if companion_index == -1:
			continue
		var unit_id := companion_index + 1
		if unit_id < sim.minions.size() and sim.minions[unit_id].hp > 0:
			order.append(unit_id)
	return order


func _make_battle_card(unit_id: int) -> PanelContainer:
	var unit: UDMinion = sim.minions[unit_id]
	var card := PanelContainer.new()
	# 盤面の情報整理（2026-08-23、§3-§5「立ち絵を削除しシンプルな名前+
	# HP+SP構成へ」＋§2「小さなバーではなく読みやすいバーへ」）: 立ち絵
	# アイコンを撤去した分、フロアの底上げではなく文字サイズ・バー太さ
	# 側へ再配分——§4「一瞬で誰の情報か分かる」ための名前フォント拡大が
	# 主目的。yは実コンテンツから逆算して再計算する（フロア自体が高さを
	# 決めてしまわないよう、常にコンテンツ実測より低く保つ、前ラウンドの
	# 教訓を踏襲）。
	# 下部UI再整理（2026-08-23b、§7/§8「横方向へ少し広げる、5人均等」）:
	# custom_minimum_size.xはあくまで最小フロア（84、旧96より低い値へ
	# 意図的に下げた）——実際に表示される幅は下のsize_flags_horizontal=
	# EXPAND_FILL（既定stretch_ratio=1、5枚とも同じ）が、親cards_rowの
	# floor幅（660、_build_battle_bar側）を5等分して受け取る形で決まる。
	# 個々のカードへ直接広い固定幅を書き込むのではなく、Godotの
	# Container分配に任せることで「名前の長さでバラつかない・将来6人目が
	# 増えても自動的に再分配される」を構造で保証する（§14の明示指示）。
	card.custom_minimum_size = Vector2(84, 60)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := _panel_style(Color(0.08, 0.09, 0.16, 0.9), 5)
	style.border_color = COLOR_CARD_BORDER
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(_on_battle_card_input.bind(unit_id))

	var column := VBoxContainer.new()
	# 下部UI再整理（2026-08-23b、§1/§2「もう一段バーを広げる、増えた高さは
	# 可読性へ」）: 2→3。name/HP行/HPバー/SP行/SPバーの4つの間隔がそれぞれ
	# 1pxずつ広がる分、カード全体の実測高が伸びる——外周の無駄な余白では
	# なくコンテンツ自身の呼吸幅として使う。
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)

	var name_label := Label.new()
	name_label.text = _unit_display_name(unit)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 盤面の情報整理（2026-08-23、§4「名前を今より見やすく」）: 13→16。
	name_label.add_theme_font_size_override("font_size", 16)
	column.add_child(name_label)

	# 盤面の情報整理（2026-08-23、§3）: 立ち絵/アイコンを削除——実際の
	# キャラクターは既に戦闘盤面に表示されているため、下部でもう一度
	# 表示する必要性が低いと判断（ユーザー指示）。旧`portrait`
	# TextureRectはこのカードからは完全に撤去（他画面—宿舎・カード式
	# ダイアログ等—の同種アイコン表示には一切影響しない、この関数の
	# ローカル変更のみ）。

	var hp_label := Label.new()
	hp_label.text = "HP %d/%d" % [unit.hp, sim.unit_max_hp(unit)]
	# 盤面の情報整理（2026-08-23、§5「HP/SPは維持、読みやすく」）: 11→14。
	hp_label.add_theme_font_size_override("font_size", 14)
	column.add_child(hp_label)

	var hp_bar := ProgressBar.new()
	hp_bar.show_percentage = false
	# 下部UI再整理（2026-08-23b、§1/§2「もう一段バーを広げる、増えた高さは
	# 読みやすさへ」）: 8→9→10→9。10まで試した実測で対象選択+3行メッセージ
	# の最悪ケース余白が3.5pxまで薄くなったため、既存の実績値（前ラウンド
	# までの4.5〜5.5px）に近い9へ戻した——バー総高はほぼ変わらない
	# （168px、旧169pxとほぼ同値）が、行の実コンテンツ高は97→103pxへ
	# 確実に伸びており、「余白の犠牲を最小限にしつつ中身を広げる」を優先。
	hp_bar.custom_minimum_size = Vector2(0, 9)
	hp_bar.max_value = maxi(1, sim.unit_max_hp(unit))
	hp_bar.value = unit.hp
	_style_bar(hp_bar, COLOR_HP_BAR_BG, COLOR_HP_BAR)
	column.add_child(hp_bar)

	var sp_label := Label.new()
	sp_label.text = "SP %d/%d" % [unit.sp, sim.unit_max_sp(unit)]
	sp_label.add_theme_font_size_override("font_size", 14)
	column.add_child(sp_label)

	var sp_bar := ProgressBar.new()
	sp_bar.show_percentage = false
	sp_bar.custom_minimum_size = Vector2(0, 9)
	sp_bar.max_value = maxi(1, sim.unit_max_sp(unit))
	sp_bar.value = unit.sp
	_style_bar(sp_bar, COLOR_SP_BAR_BG, COLOR_SP_BAR)
	column.add_child(sp_bar)

	_battle_cards[unit_id] = {
		"panel": card, "style": style, "hp_label": hp_label, "hp_bar": hp_bar,
	}
	return card


## During ally-target selection, clicking a card picks the heal/buff
## target instead of changing who's acting; otherwise it's the normal
## "command this character" click.
func _on_battle_card_input(event: InputEvent, unit_id: int) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if _battle_phase == "targetSelection" and _battle_target_kind == "ally":
			_battle_selected_ally_target = unit_id
			_refresh_target_panel()
			_update_card_selection()
			queue_redraw()
		else:
			_battle_selected_unit = unit_id
			_update_card_selection()
			_update_battle_buttons()


const COLOR_ALLY_TARGET_BORDER := Color(0.35, 0.85, 0.45)


## Two independent highlights share the same card row: gold = the
## character currently being commanded (_battle_selected_unit), green =
## the ally currently picked as a heal/buff target while ally-target
## selection is active (_battle_selected_ally_target). The ally-target
## glow takes priority while that sub-phase is active since it's the
## thing the player is actively choosing; it can land on the same card
## as the gold border (self-heal) without conflict since it's just a
## different border color, not a second overlapping frame.
func _update_card_selection() -> void:
	var ally_targeting := _battle_phase == "targetSelection" and _battle_target_kind == "ally"
	for unit_id: Variant in _battle_cards.keys():
		var entry: Dictionary = _battle_cards[unit_id]
		var style: StyleBoxFlat = entry["style"]
		if ally_targeting and int(unit_id) == _battle_selected_ally_target:
			style.border_color = COLOR_ALLY_TARGET_BORDER
			style.set_border_width_all(3)
		elif int(unit_id) == _battle_selected_unit:
			style.border_color = COLOR_CARD_BORDER_SELECTED
			style.set_border_width_all(3)
		else:
			style.border_color = COLOR_CARD_BORDER
			style.set_border_width_all(2)


const COLOR_TEXTURE_BUTTON_DISABLED := Color(0.45, 0.45, 0.45, 1.0)


## TextureButton has no texture_disabled art to fall back on, so "unusable"
## reads as a dimmed modulate instead of a StyleBoxFlat swap here.
func _set_texture_button_enabled(button: TextureButton, enabled: bool) -> void:
	button.disabled = not enabled
	button.modulate = Color.WHITE if enabled else COLOR_TEXTURE_BUTTON_DISABLED


func _update_battle_buttons() -> void:
	var all_set := not _battle_order.is_empty()
	for unit_id in _battle_order:
		if not _battle_pending_actions.has(unit_id):
			all_set = false
			break
	_set_texture_button_enabled(_battle_start_button, all_set)
	var has_selection := _battle_selected_unit != -1
	_set_texture_button_enabled(_battle_attack_button, has_selection)
	_set_texture_button_enabled(_battle_skill_button, has_selection)
	_set_texture_button_enabled(_battle_item_button, has_selection)


## こうげき always targets an enemy, so it always goes through target
## selection now (2026-07-19) instead of resolving immediately.
func _on_battle_attack() -> void:
	if _battle_selected_unit == -1:
		return
	_enter_target_selection("attack", "", "enemy")


func _on_battle_skill() -> void:
	if _battle_selected_unit == -1:
		return
	_battle_phase = "skillSelection"
	_commands_column.visible = true
	_target_confirm_panel.visible = false
	_reset_boss_hp_bar_glow()
	var unit: UDMinion = sim.minions[_battle_selected_unit]
	var entries: Array = []
	for skill_id in sim.unit_skills(unit):
		if not skill_db.has_skill(skill_id):
			continue
		var skill := skill_db.get_skill(skill_id)
		# sp_cost: null = not balanced yet (RPG_SYSTEM_DESIGN_v5 skills
		# without a number, e.g. Sotiris's pre-awakening set) — shown as
		# "SP --" and left selectable/free rather than guessing a figure.
		var raw_cost: Variant = skill.get("sp_cost", 0)
		var cost_text := locale.text("UI_SP_UNSET") if raw_cost == null else "SP %d" % int(raw_cost)
		var enabled := raw_cost == null or unit.sp >= int(raw_cost)
		# Every skill goes through target selection now (2026-07-19) —
		# enemy-target skills pick the enemy (crosshair), ally-target
		# skills (e.g. Healing) pick a party card instead. The skill's
		# own "target" field decides which pool _enter_target_selection
		# draws from.
		var target_kind := str(skill.get("target", "enemy"))
		entries.append({
			"label": locale.text(str(skill["name_key"])),
			"cost_text": cost_text,
			"description": locale.text(str(skill.get("desc_key", ""))),
			"enabled": enabled,
			"callback": _enter_target_selection.bind("skill", str(skill_id), target_kind),
		})
	_show_battle_list_panel(locale.text("UI_BOSS_SKILL_TITLE") % _unit_display_name(unit), entries)


## No battle-item system exists yet (data/items/ are treasure-collection
## only, not battle consumables) — opens the same generic panel with
## nothing to pick, so wiring real entries in later is a data change,
## not a new screen.
func _on_battle_item() -> void:
	if _battle_selected_unit == -1:
		return
	_show_battle_list_panel(locale.text("UI_BOSS_ITEM"), [])


## --- Target selection (2026-07-19) ---------------------------------------
## Enemy ids the crosshair can cycle through. Only ever one entry today
## (sim only tracks a single boss_enemy_id), but modeled as a list —
## rather than reading sim.boss_enemy_id directly wherever a "target"
## is needed — so left/right cycling and click-to-target already work
## once a second enemy exists.
## Selectable enemy-side targets: the boss's main body, plus one entry
## per still-standing body part (新企画v1 §8). A part target is encoded
## as "<enemy_id>#<part_id>" — kept as a single opaque string so the rest
## of this crosshair/target-cycling flow (already written to juggle a
## list of ids) needs no structural changes; see _target_enemy_id()/
## _target_part_id() below to decode one.
func _battle_enemy_targets() -> Array[String]:
	if sim.boss_enemy_id == "" or not enemy_db.has_enemy(sim.boss_enemy_id):
		return []
	var targets: Array[String] = [sim.boss_enemy_id]
	for part_id: Variant in sim.boss_part_hp.keys():
		if not sim.boss_parts_destroyed.has(str(part_id)):
			targets.append(sim.boss_enemy_id + "#" + str(part_id))
	return targets


func _target_enemy_id(target_id: String) -> String:
	var sep := target_id.find("#")
	return target_id if sep == -1 else target_id.substr(0, sep)


func _target_part_id(target_id: String) -> String:
	var sep := target_id.find("#")
	return "" if sep == -1 else target_id.substr(sep + 1)


## Ally ids a heal/ally-target skill can be aimed at: every living party
## member, same fixed seating as the card row.
func _battle_ally_targets() -> Array[int]:
	return _battle_display_order()


func _enter_command_selection() -> void:
	_battle_phase = "commandSelection"
	_commands_column.visible = true
	_target_confirm_panel.visible = false
	_reset_boss_hp_bar_glow()
	_update_card_selection()
	queue_redraw()


func _enter_target_selection(source: String, skill_id: String, target_kind: String) -> void:
	_battle_target_kind = target_kind
	if target_kind == "ally":
		var ally_targets := _battle_ally_targets()
		if ally_targets.is_empty():
			return
		# Defaults to the acting character (self) if they're a valid
		# target, matching the natural "heal myself" reading of picking
		# ヒーリング with nothing else chosen yet.
		if not ally_targets.has(_battle_selected_ally_target):
			_battle_selected_ally_target = \
				_battle_selected_unit if ally_targets.has(_battle_selected_unit) else ally_targets[0]
	else:
		var enemy_targets := _battle_enemy_targets()
		if enemy_targets.is_empty():
			return
		if not enemy_targets.has(_battle_selected_target_id):
			_battle_selected_target_id = enemy_targets[0]
		# Only one possible enemy = nothing to choose: skip the whole
		# target-selection screen and confirm immediately (user request
		# 2026-07-20). The crosshair flow stays untouched for the day a
		# second enemy exists — this is a shortcut, not a removal.
		if enemy_targets.size() == 1:
			_battle_target_source = source
			_battle_pending_skill_id = skill_id
			_on_target_confirm()
			return
	_battle_target_source = source
	_battle_pending_skill_id = skill_id
	_battle_phase = "targetSelection"
	_commands_column.visible = false
	_battle_list_panel.visible = false
	_refresh_target_panel()
	_update_card_selection()
	_target_confirm_panel.visible = true
	queue_redraw()


func _cycle_target_selection(direction: int) -> void:
	if _battle_target_kind == "ally":
		var ally_targets := _battle_ally_targets()
		if ally_targets.size() <= 1:
			return
		var index := ally_targets.find(_battle_selected_ally_target)
		_battle_selected_ally_target = ally_targets[posmod(index + direction, ally_targets.size())]
	else:
		var enemy_targets := _battle_enemy_targets()
		if enemy_targets.size() <= 1:
			return
		var index := enemy_targets.find(_battle_selected_target_id)
		_battle_selected_target_id = enemy_targets[posmod(index + direction, enemy_targets.size())]
	_refresh_target_panel()
	_update_card_selection()
	queue_redraw()


func _refresh_target_panel() -> void:
	var skill_name := locale.text("UI_BOSS_ATTACK")
	if _battle_target_source == "skill" and skill_db.has_skill(_battle_pending_skill_id):
		skill_name = locale.text(str(skill_db.get_skill(_battle_pending_skill_id)["name_key"]))
	var target_name := ""
	if _battle_target_kind == "ally":
		if _battle_selected_ally_target != -1 and _battle_selected_ally_target < sim.minions.size():
			target_name = _unit_display_name(sim.minions[_battle_selected_ally_target])
	elif enemy_db.has_enemy(_target_enemy_id(_battle_selected_target_id)):
		var boss_def := enemy_db.get_enemy(_target_enemy_id(_battle_selected_target_id))
		var part_id := _target_part_id(_battle_selected_target_id)
		# 新企画v1仕様書 v2 §5, 2026-08-21: parts now carry their own
		# localized name_key (data/enemies' "parts" entries) instead of the
		# raw internal id the first prototype showed the player directly.
		target_name = (
			locale.text(str(boss_def["name_key"])) if part_id == ""
			else _boss_part_display_name(boss_def, part_id))
	var skill_label: Label = _target_confirm_panel.find_child("skill_line", true, false)
	var target_label: Label = _target_confirm_panel.find_child("target_line", true, false)
	skill_label.text = "%s　%s" % [locale.text("UI_BOSS_TARGET_SKILL_LABEL"), skill_name]
	target_label.text = "%s　%s" % [locale.text("UI_BOSS_TARGET_LABEL"), target_name]
	# User report: the title/instruction read as enemy-only ("攻撃対象を選
	# 択"/"敵を選んでください") even while picking an ALLY target (e.g.
	# ヒーリング) — switch to the ally-flavored copy whenever _battle_
	# target_kind is "ally", same locale-lookup pattern as everything else
	# in this function.
	var title_label: Label = _target_confirm_panel.find_child("target_title", true, false)
	var instruction_label: Label = _target_confirm_panel.find_child("target_instruction", true, false)
	if _battle_target_kind == "ally":
		title_label.text = locale.text("UI_BOSS_TARGET_TITLE_ALLY")
		instruction_label.text = locale.text("UI_BOSS_TARGET_INSTRUCTION_ALLY")
	else:
		title_label.text = locale.text("UI_BOSS_TARGET_TITLE")
		instruction_label.text = locale.text("UI_BOSS_TARGET_INSTRUCTION")
	_refresh_enemy_target_rows()


## Rebuilds the clickable 本体/右腕/脚-style row list whenever there is more
## than one selectable enemy-side target (新企画v1仕様書 v2 §2/§3) — hidden
## for an ally-target skill and naturally never populated for a non-parted
## boss (_enter_target_selection's enemy_targets.size()==1 shortcut skips
## this whole panel before this function is ever reached in that case).
## Cheap full rebuild, same reasoning as _refresh_boss_parts_column(): at
## most a handful of rows, only rebuilt on a real selection-state change,
## never per frame.
func _refresh_enemy_target_rows() -> void:
	# 下部操作バー圧縮（2026-08-22c）でVBoxContainer→HFlowContainerへ
	# 変更（本体/部位を横並びで折り返し表示、縦方向を大きく節約）。
	var rows_container: HFlowContainer = _target_confirm_panel.find_child(
		"enemy_target_rows", true, false)
	for child in rows_container.get_children():
		child.queue_free()
	# レスポンシブUI基盤（2026-08-21）: 行リスト自体がクリック可能な
	# 選択肢を示している間は、同じ内容を繰り返すだけの案内文
	# （instruction_label）を隠して縦方向のスペースを取り戻す——固定
	# pxの高さ調整ではなく、単に不要な行を消すことで済ませる。
	var instruction_label: Label = _target_confirm_panel.find_child(
		"target_instruction", true, false)
	if _battle_target_kind == "ally":
		instruction_label.visible = true
		return
	var enemy_targets := _battle_enemy_targets()
	instruction_label.visible = enemy_targets.size() <= 1
	if enemy_targets.size() <= 1:
		return
	var boss_def := enemy_db.get_enemy(sim.boss_enemy_id)
	var boss_name := locale.text(str(boss_def["name_key"]))
	for target_id in enemy_targets:
		var part_id := _target_part_id(target_id)
		var label := (
			locale.text("UI_BOSS_TARGET_MAIN_BODY_LABEL") % boss_name if part_id == ""
			else _boss_part_display_name(boss_def, part_id))
		var row := Button.new()
		row.text = label
		row.toggle_mode = true
		row.button_pressed = (target_id == _battle_selected_target_id)
		# 下部操作バー圧縮（2026-08-22c）: 横並び用に内側余白を6→4へ
		# 縮小——文字サイズは他のボタン類と同じ13ptのまま変更しない。
		_style_list_row(row, COLOR_TARGET_SELECTED_BG, 4)
		row.add_theme_font_size_override("font_size", 13)
		row.pressed.connect(_on_enemy_target_row_selected.bind(target_id))
		rows_container.add_child(row)


func _on_enemy_target_row_selected(target_id: String) -> void:
	_battle_selected_target_id = target_id
	_refresh_target_panel()
	queue_redraw()


## もどる: skill-originated target selection reopens the skill list (same
## character); attack-originated returns straight to the command view.
func _on_target_back() -> void:
	if _battle_target_source == "skill":
		_on_battle_skill()
	else:
		_enter_command_selection()


## 決定: only stores targetId into pendingAction and completes this
## character's turn — no damage/attack resolution happens here (that's
## still sim.resolve_boss_round(), triggered later by 行動開始).
func _on_target_confirm() -> void:
	if _battle_selected_unit == -1:
		return
	if _battle_target_kind == "ally":
		if _battle_selected_ally_target == -1:
			return
		_battle_phase = "actionConfirmed"
		_set_battle_action(
			_battle_selected_unit, "skill", _battle_pending_skill_id,
			"ally", str(_battle_selected_ally_target))
	else:
		if _battle_selected_target_id == "":
			return
		_battle_phase = "actionConfirmed"
		var enemy_id := _target_enemy_id(_battle_selected_target_id)
		var part_id := _target_part_id(_battle_selected_target_id)
		if _battle_target_source == "skill":
			_set_battle_action(
				_battle_selected_unit, "skill", _battle_pending_skill_id,
				"enemy", enemy_id, part_id)
		else:
			_set_battle_action(
				_battle_selected_unit, "attack", "", "enemy", enemy_id, part_id)
	_enter_command_selection()


## pendingAction per the user's spec (characterId/actionType/skillId/
## targetType/targetId) — characterId is the dictionary key (unit_id,
## already the established convention here) rather than a redundant
## field, and actionType reuses the existing "action" key. target_id ""
## means no enemy was chosen (the ally-target skill path, e.g. Healing,
## which skips target selection entirely — see _on_battle_skill).
## target_part (新企画v1 §8, 2026-08-18) is "" for a body-targeted attack/
## skill, exactly the pre-part-destruction behavior.
func _set_battle_action(
		unit_id: int, action: String, skill_id: String,
		target_type: String = "", target_id: String = "", target_part: String = "") -> void:
	if action == "attack":
		_battle_pending_actions[unit_id] = {
			"action": "attack", "target_type": target_type,
			"target_id": target_id, "target_part": target_part,
		}
	else:
		_battle_pending_actions[unit_id] = {
			"action": "skill", "skill_id": skill_id, "target_type": target_type,
			"target_id": target_id, "target_part": target_part,
		}
	_advance_battle_selection()
	_update_card_selection()
	_update_battle_buttons()


## Jumps the gold highlight to the next unit without a pending action yet;
## leaves it where it is once everyone has one, so re-picking an
## already-set unit's command (by clicking its card) doesn't get yanked
## away from under the player.
func _advance_battle_selection() -> void:
	for unit_id in _battle_order:
		if not _battle_pending_actions.has(unit_id):
			_battle_selected_unit = unit_id
			return


## --- Shared skill/item picker overlay -----------------------------------
## Data-driven by design: both the スキル and どうぐ commands feed this
## the same {label, cost_text, description, enabled, callback} entry list
## instead of each owning a hardcoded sub-screen — a new skill or a future
## battle-item system is just a different entries array, never new UI.
## Select-then-confirm (reference image): clicking a row highlights it and
## previews its description below; 決定 commits the highlighted entry,
## もどる cancels without picking anything.

func _build_battle_list_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -420
	panel.offset_right = -12
	panel.offset_top = 70
	panel.offset_bottom = -180
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.07, 0.12, 0.97)))
	add_child(panel)
	_battle_list_panel = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)

	var title := Label.new()
	title.name = "title"
	title.add_theme_font_size_override("font_size", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(HSeparator.new())

	var rows := VBoxContainer.new()
	rows.name = "rows"
	rows.add_theme_constant_override("separation", 4)
	column.add_child(rows)

	column.add_child(HSeparator.new())

	var effect_title := Label.new()
	effect_title.text = locale.text("UI_BOSS_EFFECT")
	effect_title.add_theme_font_size_override("font_size", 13)
	column.add_child(effect_title)

	var effect_label := Label.new()
	effect_label.name = "effect"
	effect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	effect_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	column.add_child(effect_label)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	var back_button := Button.new()
	back_button.text = locale.text("UI_BOSS_BACK")
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(func() -> void: _battle_list_panel.visible = false)
	footer.add_child(back_button)
	var confirm_button := Button.new()
	confirm_button.name = "confirm"
	confirm_button.text = locale.text("UI_BOSS_CONFIRM")
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(confirm_button, COLOR_START_BUTTON)
	confirm_button.pressed.connect(_on_battle_list_confirm)
	footer.add_child(confirm_button)


## Distinct from _style_button: a toggle-mode list row needs its "pressed"
## (= currently highlighted) state to read as a clear selection, not the
## same color as normal like a regular command button's pressed flash.
## `pressed_color` defaults to the existing blue (_battle_list_panel's
## skill/item rows keep meaning "you're viewing this one's details" —
## unrelated to combat targeting, so it must NOT turn red just because
## this helper changed). _refresh_enemy_target_rows() passes
## COLOR_TARGET_SELECTED_BG explicitly so only the attack-target list
## gets the red "this is who I'm about to hit" language.
## 視認性改善（2026-08-22）: 実機報告「選択中でも赤表示が出たり消えたり
## する」の根本原因は、toggle_mode=trueのButtonが「選択済み(pressed)を
## マウスホバー中」に描画する専用state=hover_pressedをこの関数が一度も
## 上書きしていなかったこと——未指定のためGodotの既定テーマのhover_
## pressedスタイル（この配色と無関係な見た目）へ毎回フォールバックし、
## マウスが対象の上を通るたびに濃い選択色が消えて見えていた。hover=
## 一時的なホバー、pressed/hover_pressed=決定するまで持続する選択状態、
## として明示的に分離。あわせてfont_colorの明示指定（Godotのテーマ既定
## 色に頼らない）とfocus_mode=NONE（キーボードフォーカスの縁取りが選択
## 色と干渉する経路を構造的に除去）も追加。
## content_margin省略時は6（既存の全呼び出し元——スキル/どうぐ一覧の
## 右ドッキングパネル含む——と完全互換）。下部操作バー圧縮（2026-08-
## 22c）で対象選択の本体/部位行だけ小さい値を明示的に渡す。
func _style_list_row(
		button: Button, pressed_color: Color = Color(0.16, 0.36, 0.6),
		content_margin: int = 6) -> void:
	var by_state := {
		"normal": Color(0.1, 0.11, 0.18),
		"hover": Color(0.16, 0.17, 0.26),
		"pressed": pressed_color,
		"hover_pressed": pressed_color,
		"disabled": Color(0.08, 0.08, 0.1),
	}
	for state in by_state:
		var style := StyleBoxFlat.new()
		style.bg_color = by_state[state]
		style.set_corner_radius_all(4)
		style.set_content_margin_all(content_margin)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override("font_color", COLOR_BOSS_PANEL_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_BOSS_PANEL_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_BOSS_PANEL_TEXT)
	button.add_theme_color_override("font_hover_pressed_color", COLOR_BOSS_PANEL_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_BOSS_PART_DESTROYED_TEXT)
	button.focus_mode = Control.FOCUS_NONE


func _show_battle_list_panel(title: String, entries: Array) -> void:
	_battle_list_entries = entries
	(_battle_list_panel.find_child("title", true, false) as Label).text = title
	var rows: VBoxContainer = _battle_list_panel.find_child("rows", true, false)
	for child in rows.get_children():
		child.queue_free()
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = locale.text("UI_BOSS_ITEM_EMPTY")
		rows.add_child(empty_label)
		_battle_list_selected_index = -1
	else:
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var row := Button.new()
			row.text = "%s   %s" % [str(entry["label"]), str(entry.get("cost_text", ""))]
			row.toggle_mode = true
			row.disabled = not bool(entry.get("enabled", true))
			_style_list_row(row)
			row.pressed.connect(_on_battle_list_row_selected.bind(i))
			rows.add_child(row)
		_battle_list_selected_index = 0
	_update_battle_list_selection()
	_battle_list_panel.visible = true


func _on_battle_list_row_selected(index: int) -> void:
	_battle_list_selected_index = index
	_update_battle_list_selection()


func _update_battle_list_selection() -> void:
	var rows: VBoxContainer = _battle_list_panel.find_child("rows", true, false)
	for i in rows.get_child_count():
		var row := rows.get_child(i) as Button
		if row != null:
			row.button_pressed = (i == _battle_list_selected_index)
	var effect_label: Label = _battle_list_panel.find_child("effect", true, false)
	var confirm_button: Button = _battle_list_panel.find_child("confirm", true, false)
	if _battle_list_selected_index == -1 or _battle_list_entries.is_empty():
		effect_label.text = ""
		confirm_button.disabled = true
		return
	var entry: Dictionary = _battle_list_entries[_battle_list_selected_index]
	effect_label.text = str(entry.get("description", ""))
	confirm_button.disabled = not bool(entry.get("enabled", true))


func _on_battle_list_confirm() -> void:
	if _battle_list_selected_index == -1 or _battle_list_entries.is_empty():
		return
	var entry: Dictionary = _battle_list_entries[_battle_list_selected_index]
	if not bool(entry.get("enabled", true)):
		return
	_battle_list_panel.visible = false
	(entry["callback"] as Callable).call()


## --- REWIND button (top-right, battle screen only) -----------------------
## 新企画v1 §10: the player's own "任意REWIND" trigger, always available
## mid-fight. sim.rewind_boss_fight() restarts the current attempt from
## its checkpoint (HP/SP/boss HP/part durability) — this does NOT leave
## the encounter (unlike the old やめる/flee_boss_fight() behavior it
## replaced, 2026-08-18); the fight stays open, just reset.

func _build_quit_battle_button() -> void:
	var button := Button.new()
	button.text = locale.text("UI_BOSS_REWIND")
	button.custom_minimum_size = Vector2(90, 36)
	button.add_theme_font_size_override("font_size", 14)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -102
	button.offset_right = -12
	button.offset_top = 12
	button.offset_bottom = 48
	button.visible = false
	_style_button(button, Color(0.28, 0.24, 0.32))
	button.pressed.connect(_on_battle_rewind_pressed)
	add_child(button)
	_quit_battle_button = button


## Opens the もどる/決定 confirm prompt instead of rewinding immediately
## (新企画v1仕様書 v2 §25, 2026-08-20). NOと同義のもどる/ESC等は一切
## sim状態に触れずパネルを閉じるだけなので、キャンセルすれば戦闘は
## そのまま続行できる — 副作用は決定を押した _do_battle_rewind() 側だけ。
func _on_battle_rewind_pressed() -> void:
	_rewind_confirm_panel.visible = true


func _do_battle_rewind() -> void:
	_rewind_confirm_panel.visible = false
	_stop_battle_anim()
	if not sim.rewind_boss_fight():
		return
	_tally_text = locale.text("UI_REWIND")
	_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
	# §10: 手動REWINDでも表示中のメッセージはクリアして仕切りを1件だけ
	# 表示する——前ループの内容をそのまま持ち越すと"前回何が起きたか"
	# と"今回何が起きたか"が混ざり、プレイヤー自身の記憶という攻略要素
	# と衝突する。
	_clear_battle_message()
	_append_battle_message(locale.text("UI_BATTLE_MSG_REWIND_DIVIDER"), "special")
	_battle_pending_actions = {}
	_battle_selected_unit = -1
	_battle_selected_target_id = ""
	_battle_selected_ally_target = -1
	_enter_command_selection()
	_refresh_boss_panel()
	queue_redraw()


## Small centered もどる/決定 prompt for REWIND (see _rewind_confirm_panel's
## doc comment for why this is a plain Control, not a native dialog/Window).
## Built once and just toggled .visible, same idiom as _battle_list_panel.
func _build_rewind_confirm_panel() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -160
	panel.offset_right = 160
	panel.offset_top = -60
	panel.offset_bottom = 60
	panel.visible = false
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.06, 0.07, 0.12, 0.97)))
	add_child(panel)
	_rewind_confirm_panel = panel

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var text := Label.new()
	text.text = locale.text("UI_REWIND_CONFIRM_TEXT")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(text)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	column.add_child(footer)
	var back_button := Button.new()
	back_button.text = locale.text("UI_BOSS_BACK")
	back_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_button.pressed.connect(func() -> void: _rewind_confirm_panel.visible = false)
	footer.add_child(back_button)
	var confirm_button := Button.new()
	confirm_button.text = locale.text("UI_BOSS_CONFIRM")
	confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(confirm_button, COLOR_START_BUTTON)
	confirm_button.pressed.connect(_do_battle_rewind)
	footer.add_child(confirm_button)


## 2026-08-18 (user report): the only way out of the battle screen once
## REWIND took over やめる's slot was winning — _button_bar (宿屋/ギルド/
## 依頼掲示板/etc., once those exist) only shows when _boss_screen_active()
## is false. This restores a genuine exit, distinct from REWIND: leaves
## the encounter outright via the unchanged sim.flee_boss_fight() (gate
## stays uncleared, no penalty) and returns to the normal screen.
func _build_leave_battle_button() -> void:
	var button := Button.new()
	button.text = locale.text("UI_BOSS_QUIT")
	button.custom_minimum_size = Vector2(90, 36)
	button.add_theme_font_size_override("font_size", 14)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -102
	button.offset_right = -12
	button.offset_top = 54
	button.offset_bottom = 90
	button.visible = false
	_style_button(button, Color(0.24, 0.2, 0.2))
	button.pressed.connect(_on_battle_leave_pressed)
	add_child(button)
	_leave_battle_button = button


func _on_battle_leave_pressed() -> void:
	_stop_battle_anim()
	sim.flee_boss_fight()
	_hide_boss_panel()


## Stops mid-playback and drops all animation state — needed anywhere the
## fight can end out from under the sequencer (やめる, or _show_boss_panel
## re-entering on a save loaded mid-fight) so a stale timer callback never
## fires against a round that's no longer being resolved.
func _stop_battle_anim() -> void:
	_battle_anim_timer.stop()
	_battle_anim_step = -1
	_battle_anim_queue = []
	_battle_anim_pos = {}
	_battle_anim_popups = []
	_battle_pending_round_result = {}
	_battle_playback_active = false
	_battle_playback_boss_id = ""
	_battle_anim_flip = false
	_battle_enemy_knock_t = 0.0
	_battle_knockback_px = BATTLE_KNOCKBACK_PX
	_battle_knockback_seconds = BATTLE_ENEMY_HIT_SECONDS
	_battle_impact_t = 0.0
	_battle_boss_lunge_t = 0.0
	_battle_ally_hit_unit = -1
	_battle_ally_hit_t = 0.0
	_battle_proj_active = false
	_battle_proj_t = 0.0
	_battle_proj_tex = null
	_battle_proj_key = ""
	_battle_hitstop_t = 0.0
	_battle_shake_t = 0.0
	_battle_impact_key = ""


## --- Boss encounter lifecycle --------------------------------------------

## Debug-only (gated on _debug_boss_loop, the F9 motion-test mode): tops
## every unit back up to full HP/SP — including reviving downed ones — so
## repeated test fights never grind the party down (user request
## 2026-07-20: "HPとSPを減らないように"). This writes sim state from the
## UI, which is exactly what iron rule 2 forbids for real features; it is
## tolerable only because the whole path is a debug switch that must be
## OFF for release (see _debug_boss_loop's comment).
func _debug_restore_party() -> void:
	for unit: UDMinion in sim.minions:
		unit.hp = sim.unit_max_hp(unit)
		unit.sp = sim.unit_max_sp(unit)


func _show_boss_panel() -> void:
	if settings.resident_mode:
		_expand()
	if _debug_boss_loop:
		_debug_restore_party()
	_battle_pending_actions = {}
	_battle_selected_unit = -1
	_battle_selected_target_id = ""
	_battle_selected_ally_target = -1
	_stop_battle_anim()
	_enter_command_selection()
	_refresh_boss_panel()
	_sync_battle_chrome_visibility()
	queue_redraw()


func _hide_boss_panel() -> void:
	_sync_battle_chrome_visibility()
	queue_redraw()


## "尻尾 8/15  脚 0/15" — one line summarizing every body part's current
## durability against the boss def's own declared starting values (新企画
## v1 §8, 2026-08-18). A part at 0/max has been destroyed. Localized via
## the part's own optional "name_key" (data/enemies' "parts" entries);
## falls back to the raw id for a boss whose data doesn't have one yet.
func _boss_part_display_name(boss_def: Dictionary, part_id: String) -> String:
	for entry: Variant in boss_def.get("parts", []) as Array:
		var part := entry as Dictionary
		if str(part["id"]) == part_id:
			var name_key := str(part.get("name_key", ""))
			return locale.text(name_key) if name_key != "" else part_id
	return part_id


## Rebuilds _boss_parts_column's rows from scratch against the active
## boss's "parts" data — cheap and simple over incremental diffing since
## a boss has at most a handful of parts and this only runs when the
## boss panel itself refreshes (fight start/round end/REWIND), never per
## frame. A destroyed part keeps its row (dimmed, "破壊済") rather than
## disappearing — 新企画v1仕様書 v2 §10: the player should be able to see
## what they already broke, not just what's still standing (the separate
## attack-target list in _refresh_target_panel() DOES drop it, per §10's
## other half — a destroyed part is only unselectable, not invisible).
func _refresh_boss_parts_column() -> void:
	for child in _boss_parts_column.get_children():
		child.queue_free()
	_boss_part_rows.clear()
	_boss_parts_column.visible = not sim.boss_part_hp.is_empty()
	if sim.boss_part_hp.is_empty():
		return
	var boss := enemy_db.get_enemy(sim.boss_enemy_id)
	var max_hp_by_id: Dictionary = {}
	for entry: Variant in boss.get("parts", []) as Array:
		var part := entry as Dictionary
		max_hp_by_id[str(part["id"])] = int(part["hp"])
	for part_id: Variant in sim.boss_part_hp.keys():
		var id := str(part_id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_boss_parts_column.add_child(row)

		# Font sizes 13/12 -> 15/14 (新企画v1仕様書 v2 §5, 2026-08-21: "フォン
		# トサイズを少し大きくする" as its own explicit item, distinct from
		# the color/contrast fix above — the first prototype's sizes barely
		# differed from the old single dim line this replaces).
		var name_label := Label.new()
		name_label.text = _boss_part_display_name(boss, id)
		name_label.add_theme_font_size_override("font_size", 15)
		row.add_child(name_label)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.max_value = int(max_hp_by_id.get(id, 0))
		_style_bar(bar, COLOR_HP_BAR_BG, COLOR_ENEMY_HP_BAR)
		row.add_child(bar)

		var text_label := Label.new()
		text_label.add_theme_font_size_override("font_size", 14)
		row.add_child(text_label)

		_boss_part_rows[id] = {"bar": bar, "name": name_label, "text": text_label}
	# Ground truth (sim.boss_part_hp), not the animation shadow — mirrors
	# _refresh_boss_panel()'s own "_boss_banner_hp_bar.value = sim.boss_hp"
	# line, which likewise bypasses _battle_boss_hp_display entirely. The
	# shadow dict only matters mid-round-animation (_fire_battle_anim_hit
	# below); a fresh boss-panel refresh (fight start, round end, REWIND)
	# must always show what sim actually has right now, not a stale value
	# left over from a previous round's playback or a REWIND that just
	# reset a part sim already restored but this dict doesn't know about.
	for part_id: Variant in sim.boss_part_hp.keys():
		_set_boss_part_row_display(str(part_id), int(sim.boss_part_hp[part_id]))


## Sets exactly one part row's bar/text/color from a caller-supplied value
## — deliberately not sim.boss_parts_destroyed for the "destroyed" check:
## resolve_boss_round() resolves the WHOLE round atomically before any
## animation plays, so boss_parts_destroyed already reflects the round's
## final state from the first hit's popup onward. Using it here would mark
## a part "破壊済" the instant animation starts even while its bar is
## still visibly draining toward zero. `value <= 0` is self-sufficient in
## both contexts this is called from — mid-animation shadow draining
## (_fire_battle_anim_hit) and ground-truth refresh
## (_refresh_boss_parts_column) — because sim's own _apply_boss_damage()
## uses that exact same threshold to decide destruction in the first
## place.
func _set_boss_part_row_display(part_id: String, value: int) -> void:
	if not _boss_part_rows.has(part_id):
		return
	var row: Dictionary = _boss_part_rows[part_id]
	var bar: ProgressBar = row["bar"]
	var name_label: Label = row["name"]
	var text_label: Label = row["text"]
	bar.value = value
	if value <= 0:
		text_label.text = locale.text("UI_PART_STATUS_DESTROYED")
		name_label.modulate = COLOR_BOSS_PART_DESTROYED_TEXT
		text_label.modulate = COLOR_BOSS_PART_DESTROYED_TEXT
	else:
		text_label.text = "%d/%d" % [value, int(bar.max_value)]
		name_label.modulate = COLOR_BOSS_PANEL_TEXT
		text_label.modulate = COLOR_BOSS_PANEL_TEXT


func _refresh_boss_panel() -> void:
	if not sim.boss_active:
		return
	# The fight's own boss id, NOT the current band's boss_id: during a
	# rematch the party is past the gate and the current band has none.
	var boss := enemy_db.get_enemy(sim.boss_enemy_id)
	_boss_banner_label.text = locale.text(str(boss["name_key"]))
	_boss_banner_hp_bar.max_value = int(boss["hp"])
	_boss_banner_hp_bar.value = sim.boss_hp
	_boss_body_hp_label.text = "%d/%d" % [sim.boss_hp, int(boss["hp"])]
	_refresh_boss_parts_column()

	_battle_order = _battle_display_order()
	for unit_id: Variant in _battle_pending_actions.keys().duplicate():
		if not _battle_order.has(int(unit_id)):
			_battle_pending_actions.erase(unit_id)
	if not _battle_order.has(_battle_selected_unit):
		_battle_selected_unit = _battle_order[0] if not _battle_order.is_empty() else -1

	var cards_row: HBoxContainer = _battle_bar.find_child("cards", true, false)
	for child in cards_row.get_children():
		child.queue_free()
	_battle_cards.clear()
	for unit_id in _battle_order:
		cards_row.add_child(_make_battle_card(unit_id))
	_update_card_selection()
	_update_battle_buttons()


func _unit_display_name(unit: UDMinion) -> String:
	if unit.id == 0:
		return locale.text("UNIT_PROTAGONIST_NAME")
	var companion_index := unit.id - 1
	if companion_index >= 0 and companion_index < sim.companions.size():
		var companion_id: String = sim.companions[companion_index]
		if _companion_by_id.has(companion_id):
			return locale.text(_companion_by_id[companion_id]["name_key"])
	return "?"


## Resolves the whole round immediately (sim.resolve_boss_round is one
## atomic, deterministic call, same as before) but does not reveal the
## result yet — it hands the round's log to the motion sequencer, which
## plays each acting character's attack/skill in seating order and only
## then runs the old won/lost/continue tail (_finish_battle_round).
func _on_boss_resolve_round() -> void:
	_battle_phase = "executing"
	_commands_column.visible = false
	_target_confirm_panel.visible = false
	var actions: Array = []
	for unit_id: Variant in _battle_pending_actions.keys():
		var entry: Dictionary = _battle_pending_actions[unit_id]
		# 新企画v1 §8 (2026-08-18): "" (no part chosen) hits the boss's main
		# HP exactly as before this system existed — see sim's
		# _apply_boss_damage().
		var target_part := str(entry.get("target_part", ""))
		if str(entry["action"]) == "attack":
			var attack_entry := {"unit_id": unit_id, "action": "attack"}
			if target_part != "":
				attack_entry["target_part"] = target_part
			actions.append(attack_entry)
		else:
			var action_entry := {"unit_id": unit_id, "action": "skill", "skill_id": entry["skill_id"]}
			# Only ally-target skills need this — sim only ever has one
			# boss to hit, so enemy-target skills don't read target_id.
			if str(entry.get("target_type", "")) == "ally" and str(entry.get("target_id", "")) != "":
				action_entry["target_id"] = int(entry["target_id"])
			elif target_part != "":
				action_entry["target_part"] = target_part
			actions.append(action_entry)
	_battle_boss_hp_display = sim.boss_hp
	# Same snapshot-before-resolving reasoning, extended to parts (新企画
	# v1仕様書 v2 §8/§12): resolve_boss_round() is one atomic, synchronous
	# call — by the time it returns, sim.boss_part_hp already reflects the
	# WHOLE round's outcome, so the part-hit animation needs its own "as
	# it stood before this round" starting point to drain from, same as
	# the main body's _battle_boss_hp_display above.
	_battle_boss_part_hp_display = sim.boss_part_hp.duplicate()
	# Both set BEFORE resolving: a decided round clears boss_active and
	# boss_enemy_id inside resolve_boss_round, and playback still needs
	# the boss screen up and the boss drawn (see the vars' comments).
	_battle_playback_active = true
	_battle_playback_boss_id = sim.boss_enemy_id
	var result := sim.resolve_boss_round(actions)
	# Motion-test mode: undo the round's HP/SP wear immediately (the log
	# still carries the real amounts, so popups/animations show real
	# numbers — only the lasting drain is cancelled).
	if _debug_boss_loop:
		_debug_restore_party()
	_battle_pending_round_result = result
	_battle_pending_actions = {}
	_battle_anim_queue = _build_battle_anim_queue(result.get("log", []))
	# The boss's counter-attack plays as one more queued step after every
	# party action, so its target's flash/knockback/damage-popup land in
	# sequence instead of silently pre-applied. Absent on won rounds
	# (resolve returns before the boss gets to counter).
	var counter: Dictionary = result.get("boss_counter", {})
	if not counter.is_empty():
		_battle_anim_queue.append({
			"action": "boss_counter", "unit_id": -1,
			"target_id": int(counter.get("target_unit_id", -1)),
			"amount": int(counter.get("amount", 0)),
			# 新企画v1仕様書 戦闘ログ (2026-08-22): sim.gd's boss_counter
			# already carries action_id (see resolve_boss_round's doc
			# comment) — just wasn't being forwarded into the queue entry
			# before there was a reason to (the animation itself doesn't
			# care which named action fired, only the log text does).
			"action_id": str(counter.get("action_id", "attack")),
		})
	# Battle won: the whole party strikes its victory pose once after the
	# killing blow lands (pack README: play at battle end only, never mix
	# into the idle loop).
	if result.get("won", false) and not _battle_anim_queue.is_empty():
		_battle_anim_queue.append({"action": "party_victory", "unit_id": -1})
	if _battle_anim_queue.is_empty():
		_finish_battle_round()
	else:
		_battle_anim_step = -1
		_advance_battle_anim_step()


## One queue entry per unit that actually acted, drawn from the round's
## log (result["log"]) but reordered into _battle_order's fixed left-to-
## right seating so playback always reads left-to-right regardless of
## which order sim.resolve_boss_round happened to process the actions in.
func _build_battle_anim_queue(log: Array) -> Array[Dictionary]:
	var log_by_unit: Dictionary = {}
	for entry: Variant in log:
		var d := entry as Dictionary
		log_by_unit[int(d["unit_id"])] = d
	var queue: Array[Dictionary] = []
	for unit_id in _battle_order:
		if log_by_unit.has(unit_id):
			queue.append(log_by_unit[unit_id] as Dictionary)
	return queue


## --- Motion playback state machine ---------------------------------------
## Each queued unit goes move_in (dash/walk to BATTLE_ANIM_CENTER) -> act
## (attack_minion_N or the skill's own skill_minion_N_<name> clip, in
## place) -> move_out (walk/dash back to its formation slot), then the
## next queued unit starts. _on_battle_anim_tick drives frame stepping and
## phase transitions; _draw_party_row reads _battle_anim_pos/_battle_anim_
## motion_key/_battle_anim_frame_index to know where and how to draw the
## one character currently animating.

func _advance_battle_anim_step() -> void:
	_battle_anim_step += 1
	if _battle_anim_step >= _battle_anim_queue.size():
		_finish_battle_round()
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	if str(entry.get("action", "")) == "boss_counter":
		# No party character moves: the boss (or its placeholder) lunges
		# toward the party and the target ally reacts at the hit moment —
		# see the "counter" case in _on_battle_anim_tick.
		# 新しい行動者（ここでは敵）のターンが始まる瞬間——前の行動者の
		# 文章を必ず消してから、敵自身の宣言を積み直す（§2/§8）。
		_clear_battle_message()
		_append_battle_message(_battle_message_boss_attack_announce_text(str(entry.get("action_id", "attack"))))
		_battle_anim_phase = "counter"
		_battle_anim_phase_elapsed = 0.0
		_battle_anim_hit_fired = false
		_battle_boss_lunge_t = 1.0
		_battle_anim_timer.start()
		queue_redraw()
		return
	if str(entry.get("action", "")) == "party_victory":
		_battle_anim_phase = "victory"
		_battle_anim_phase_elapsed = 0.0
		_battle_anim_timer.start()
		queue_redraw()
		return
	var unit_id := int(entry["unit_id"])
	# 「ソティリスのラピッドスラッシュ！」のような行動宣言——ヒット時の
	# ダメージ文（_fire_battle_anim_hit）より先に、その行動の再生が始まる
	# この瞬間に出す（DQ的な「まず宣言、次に結果」の2行パターン）。新しい
	# 行動者のターンが始まる瞬間でもあるので、前の行動者の文章を必ず
	# 消してから積み直す（§2「前の行動者の文章を残さない」）。
	_clear_battle_message()
	_append_battle_message(_battle_message_action_announce_text(entry, unit_id))
	var art_variant := _minion_art_variant(unit_id)
	_battle_anim_hit_fired = false
	_battle_anim_flip = false
	_battle_anim_dest = _battle_anim_destination(entry)
	_battle_anim_origin = _formation_pos(unit_id)
	_battle_anim_pos[unit_id] = _battle_anim_origin
	# 2026-07-24 redesign: skills no longer travel to center-stage/the boss
	# at all — go straight into "act" at the caster's own formation slot.
	# See BATTLE_ANIM_SKILL_STEP_FRAC's doc comment. Attacks are unchanged
	# (still walk up to the boss via move_in/arrive).
	if str(entry.get("action", "")) == "skill":
		_enter_battle_anim_act_phase(entry, unit_id)
	else:
		_battle_anim_motion_key = "dash_minion_%d" % art_variant
		if not art.has_art(_battle_anim_motion_key):
			_battle_anim_motion_key = "walk_minion_%d" % art_variant
		_battle_anim_phase = "move_in"
		_battle_anim_phase_elapsed = 0.0
		_battle_anim_frame_index = 0
	_battle_anim_timer.start()
	queue_redraw()


## 「ソティリスの攻撃！」/「ソティリスのラピッドスラッシュ！」——
## _battle_anim_queueの1エントリ(=1ユニットの行動)から行動宣言文を作る。
func _battle_message_action_announce_text(entry: Dictionary, unit_id: int) -> String:
	var unit_name := _unit_display_name(sim.minions[unit_id])
	if str(entry.get("action", "")) == "skill":
		var skill_id := str(entry.get("skill_id", ""))
		var skill_name := skill_id
		if skill_db.has_skill(skill_id):
			skill_name = locale.text(str(skill_db.get_skill(skill_id)["name_key"]))
		return locale.text("UI_BATTLE_MSG_SKILL") % [unit_name, skill_name]
	return locale.text("UI_BATTLE_MSG_ATTACK") % unit_name


## ボスの行動データ(data/enemies "actions"配列)の任意フィールド
## "name_key"を読む——部位の"parts[].name_key"と同じ、無ければ空文字
## フォールバックの任意項目パターン。名前を持たないボス（cave_troll以外
## 全て、フラットなatk一発のみ）は常に空文字になり、汎用の「%sの攻撃！」
## へ自然にフォールバックする。
func _boss_action_display_name(boss_def: Dictionary, action_id: String) -> String:
	for entry: Variant in boss_def.get("actions", []) as Array:
		var action := entry as Dictionary
		if str(action.get("id", "")) == action_id:
			var key := str(action.get("name_key", ""))
			return locale.text(key) if key != "" else ""
	return ""


## 「洞窟トロルの棍棒攻撃！」（名前付き行動）/「洞窟トロルの攻撃！」
## （名前の無い汎用行動）——boss_counterキューエントリの行動宣言文。
func _battle_message_boss_attack_announce_text(action_id: String) -> String:
	var boss_def := enemy_db.get_enemy(sim.boss_enemy_id)
	var boss_name := locale.text(str(boss_def["name_key"]))
	var action_name := _boss_action_display_name(boss_def, action_id)
	if action_name != "":
		return locale.text("UI_BATTLE_MSG_BOSS_ATTACK_NAMED") % [boss_name, action_name]
	return locale.text("UI_BATTLE_MSG_BOSS_ATTACK_GENERIC") % boss_name


## Melee ATTACKS physically close the distance (unchanged). Skills never
## travel at all as of the 2026-07-24 redesign (see BATTLE_ANIM_SKILL_STEP_
## FRAC's doc comment) — this now only matters for whether a skill's hit
## arrives instantly (melee: e.g. rapid_slash, a direct _fire_battle_anim_
## hit at the boss's position) or travels as a projectile (ranged). A
## skill json opts into the instant/melee delivery with "motion": "melee".
func _battle_anim_entry_is_melee(entry: Dictionary) -> bool:
	if str(entry.get("action", "")) == "attack":
		return true
	var skill_id := str(entry.get("skill_id", ""))
	if skill_db.has_skill(skill_id):
		return str(skill_db.get_skill(skill_id).get("motion", "ranged")) == "melee"
	return false


## For an ATTACK: where the character walks to (view-fraction space, like
## _formation_pos) — right up to the boss, center of the icon's near edge,
## feet on the boss's own ground line. Computed from _boss_icon_rect
## rather than a hardcoded spot so it keeps tracking the boss if its size
## or position formula ever changes.
##
## For a SKILL (2026-07-24 redesign): skills don't walk anywhere anymore,
## so this instead returns the actual TARGET's own position — the boss's,
## for an enemy-targeted skill; the target ally's formation slot, for an
## ally-targeted one. Used only to pick which way the small in-place
## step-in leans (see the "act" phase's skill branch) — never interpolated
## into like a walk destination. The actual hit/impact/projectile doesn't
## read this at all; it independently computes the boss's position (see
## _fire_battle_anim_hit's doc comment).
func _battle_anim_destination(entry: Dictionary) -> Vector2:
	var view := _view_rect()
	var ground_frac := clampf((_ground_y(view) - view.position.y) / view.size.y, 0.0, 1.0)
	if str(entry.get("action", "")) == "attack":
		var boss_rect := _boss_icon_rect(view)
		var x_px := boss_rect.position.x - PARTY_ICON_PX * 0.5 - 4.0
		var x_frac := clampf((x_px - view.position.x) / maxf(1.0, view.size.x), 0.0, 1.0)
		return Vector2(x_frac, ground_frac)
	if str(entry.get("target_type", "enemy")) == "ally":
		var target_id := int(entry.get("target_id", int(entry.get("unit_id", 0))))
		return _formation_pos(target_id)
	var boss_rect := _boss_icon_rect(view)
	var x_frac := clampf(
		(boss_rect.position.x + boss_rect.size.x * 0.3 - view.position.x) / maxf(1.0, view.size.x),
		0.0, 1.0)
	return Vector2(x_frac, ground_frac)


## 2026-07-24, staged rebuild of skill_rapid_slash ONLY (user spec: separate
## the character body, the enemy-side slash effect, the caster's short
## step-in, and the enemy's hit reaction into four independent things,
## instead of one 12-frame clip that bakes the pose + slash + explosion
## together — which is what made the caster read as "the same running
## pose sliding across the screen for a long time"). Stage 1: the
## character body no longer plays its own skill_minion_0_rapidslash clip
## at all — it plays the EXISTING attack_minion_N clip, for a fixed
## duration, same as this same character's own basic attack. Confirmed
## working by the user 2026-07-24 ("敵まで走らなくなった/キャラサイズが
## 固定された/元の位置で攻撃している/二重表示がない").
##
## Stages 2-3 (this change): a dedicated VFX plays independently at the
## BOSS's position (not the caster's) for the slash/explosion look, and
## the single damage hit is dispatched at an exact elapsed time instead of
## the generic BATTLE_ANIM_HIT_AT fraction. No other skill is touched;
## every other skill_id still resolves motion key/hit timing/impact burst
## exactly as before — see the RAPID_SLASH_SKILL_ID guards on each.
const RAPID_SLASH_SKILL_ID := "skill_rapid_slash"
## 2026-07-26 (3rd re-time, same day): the 0.90s version's whole advance
## completed in 0.14s — at BATTLE_ANIM_FPS=20 (1 tick = 0.05s) that's only
## 2-3 redraws, which the user reported watching real footage of and
## described as looking like teleporting, not walking ("0.04〜0.07秒で
## 140px前後移動しており、人間の動作ではなく瞬間移動に見えます"). This
## round is deliberately much slower and more staged — see RAPID_SLASH_
## MOVE_OUT_SECONDS etc. below — 1.70s is the new performance length.
## 2026-07-26 (VFX v3, user report: "wave_a/b/cが1個のVFXのフレーム切替に
## 見えている"): the v2 delivery DID draw 3 separate sprites, but they all
## traveled the exact same straight line (same launch point, same impact
## point, only staggered ~0.1s apart) while growing in draw_px — reading as
## one shape swelling, not 3 slashes. v3 fixes this with explicit per-wave
## STATE (see _rapid_slash_waves below) — distinct Y-offset endpoints,
## wider launch spacing (>=0.18s), and a genuinely independent (not just
## independently-timestamped) travel path each. ACT_SECONDS now covers the
## whole performance through the return walk (0.00-2.05s).
## 2026-07-26 (final polish round, "基本構成が完成しています...最終ポリッ
## シュだけ行ってください"): re-timed to fit the requested ~2.0-2.2s total
## while adding an explicit 0.08s "hold the follow-through pose" beat
## before the return walk (user spec item 7) — see RAPID_SLASH_RETURN_*.
const RAPID_SLASH_ACT_SECONDS := 1.98
## Added on top of RAPID_SLASH_ACT_SECONDS (not folded into it) — unchanged
## from the v2 delivery, not touched by this round's spec. Total performance
## (1.98 + 0.14 = 2.12s) sits inside the user's "約2.0～2.2秒以内" budget.
const RAPID_SLASH_POST_ACT_GAP_SECONDS := 0.14
## Exact elapsed-second mark where the (single) damage hit fires — the
## X-impact's F5 (user spec table: "F5: 1.38秒...最大爆発"), after all 3
## waves have landed and the crossed blades have visibly burst (F4, 1.34s).
const RAPID_SLASH_HIT_AT_SECONDS := 1.38
## rapid_slash's hit moment uses its own hitstop/shake/flash numbers
## instead of the shared BATTLE_HITSTOP_SECONDS/BATTLE_SHAKE_SECONDS/0.25s-
## flash-decay every other attack and skill uses — unchanged from the v2
## delivery (this round's spec didn't touch these), passed as explicit
## overrides into _fire_battle_anim_hit (see its trailing params) so
## nothing else's hit-feel changes.
const RAPID_SLASH_HITSTOP_SECONDS := 0.08
const RAPID_SLASH_SHAKE_SECONDS := 0.12
const RAPID_SLASH_SHAKE_PEAK_PX := 4.0
const RAPID_SLASH_FLASH_DECAY_SECONDS := 0.10
## New effect (not used by any other attack/skill): a single-tick, low-
## opacity full-view white flash on top of everything else at the hit
## moment. Unchanged from the v2 delivery.
const RAPID_SLASH_SCREEN_FLASH_ALPHA := 0.18
## (elapsed-seconds-this-frame-starts-showing, frame index) pairs — user
## spec v3: "既存のattack_minion_0の使用可能なフレームを組み合わせ...
## フレームのtight bboxを基準に拡大縮小しないでください", i.e. drop the
## dedicated skill_actor_rapidslash clip (and its bbox-derived fixed-scale
## draw, see _draw_party_row) entirely and reuse the same attack_minion_N
## clip/fixed-PARTY_ICON_PX-box every normal attack already draws with —
## _draw_party_row's generic (fixed icon_px box) branch already does
## exactly "draw sized/anchored the same as every frame", with zero extra
## code. attack_minion_N is 8 frames (headless-confirmed):
## 0-2 windup, ~4 the baked-in slash-effect frame, 5-7 recovery (see
## CLAUDE.md's own note on the sheet's layout). Not asked to hold a single
## pose through the whole windup/swing/impact/return like the old 6-frame
## clip did — user spec explicitly wants 3 DIFFERENT swing poses timed to
## the 3 wave launches (0.48/0.66/0.84s), so this table cycles through more
## of the 8 frames than the old one did. Frame choices themselves are a
## judgment call (the user gave exact times but not exact frame numbers).
## Re-timed to match this round's tighter impact/return schedule (last two
## breakpoints only — the first 4, tied to the advance/charge/3 swings, are
## unchanged and already exactly synchronized with each wave's own launch,
## see RAPID_SLASH_WAVE_DEFS' "launch" times — user spec item 3 asked for
## this synchronization, which the shared elapsed clock already provided).
const RAPID_SLASH_ACTOR_FRAMES: Array[Array] = [
	[0.00, 0], [0.28, 1], [0.48, 2], [0.66, 3], [0.84, 4], [1.65, 5], [1.98, 0],
]
## Parallel (elapsed, flip) breakpoint table — user spec: "0.66秒：逆方向の
## 斬り" for the 2nd swing. attack_minion_N has only one swing direction
## baked in; mirroring it for just this one beat is a lightweight way to
## read as an opposite-direction cut without needing new art (same
## draw_set_transform mirroring _draw_sprite already does for the walk-
## back motion, just applied to one specific beat here instead).
const RAPID_SLASH_ACTOR_FLIP_FRAMES: Array[Array] = [
	[0.00, false], [0.66, true], [0.84, false],
]
## --- Footstep dust (README "足元の砂ぼこり", unchanged from v2): 4
## frames, visible only during the advance, trailing behind the caster.
## END_SECONDS follows MOVE_OUT_SECONDS down to 0.24 -> keep the dust
## confined to the (now shorter, 0.28s) advance window.
const RAPID_SLASH_DUST_KEY := "skill_vfx_rapidslash_dust"
const RAPID_SLASH_DUST_END_SECONDS := 0.24
const RAPID_SLASH_DUST_FRAME_SECONDS := 0.06
const RAPID_SLASH_DUST_BACK_OFFSET_PX := 8.0
const RAPID_SLASH_DUST_DRAW_W := 90.0
const RAPID_SLASH_DUST_DRAW_H := 54.0
## --- Sword charge glow: 4 frames at the caster's own blade, shown only
## while stationary and winding up. Final-polish re-time: user spec "charge
## 表示: 0.28～0.48秒" (was 0.28-0.44) — the window's own end now lands
## exactly ON wave_a's launch (0.48s).
##
## User report this round: "斬撃発射後も長く残っています" — despite the
## v3 round already adding a "wave_a_launched" check specifically to guard
## against this, the window-end-based cutoff apparently wasn't reliable
## enough for the user's own footage. Per the explicit spec ("wave_a発射時:
## charge_active = false. 以降は再表示しないでください"), the elapsed-time
## window is now ONLY used to pick which of the 4 frames to show — actual
## VISIBILITY is gated by _rapid_charge_active (new bool state), which
## _update_rapid_slash_waves turns on once at RAPID_SLASH_CHARGE_START_
## SECONDS and turns off EXACTLY when wave_a's own "active" flips true (not
## indirectly inferred at draw time) — see _draw_rapid_slash_vfx's charge
## block and _reset_rapid_slash_vfx_state (act-end reset, user spec item 1).
const RAPID_SLASH_CHARGE_KEY := "skill_vfx_rapidslash_charge"
const RAPID_SLASH_CHARGE_START_SECONDS := 0.28
const RAPID_SLASH_CHARGE_END_SECONDS := 0.48
const RAPID_SLASH_CHARGE_FRAME_SECONDS := 0.05
const RAPID_SLASH_CHARGE_DRAW_PX := 64.0
## Sword-tip point shared by the charge glow and all 3 waves' launch point.
const RAPID_SLASH_SWORD_TIP_OFFSET_PX := 45.0
## --- SFX (2026-07-26, "sotiris_rapidslash_sfx_ClaudeCode" delivery): 7
## one-shot WAVs, each keyed to an EXISTING event in the now-frozen visual
## timeline (README's own "act開始基準" times match RAPID_SLASH_WAVE_DEFS'
## launch times, RAPID_SLASH_IMPACT_FRAMES[0][0], and RAPID_SLASH_HIT_AT_
## SECONDS exactly — no visual retiming needed for this round). The
## delivered full_preview.wav/.ogg are audition-only (README: "ゲーム内で
## は個別ファイルをイベントに同期して再生してください") and are not copied
## into assets/ or referenced here.
const RAPID_SLASH_SFX_PATHS: Dictionary = {
	"move": "res://assets/audio/sfx/rapidslash_move.wav",
	"slash_1": "res://assets/audio/sfx/rapidslash_slash_1.wav",
	"slash_2": "res://assets/audio/sfx/rapidslash_slash_2.wav",
	"slash_3": "res://assets/audio/sfx/rapidslash_slash_3.wav",
	"cross": "res://assets/audio/sfx/rapidslash_cross.wav",
	"impact": "res://assets/audio/sfx/rapidslash_impact.wav",
	"sparks": "res://assets/audio/sfx/rapidslash_sparks.wav",
}
## wave label -> its own slash SFX key (README: "slash_1/2/3を同時再生し
## ないでください" — trivially satisfied since each only ever plays at its
## own wave's launch, a single already-one-shot event, see RAPID_SLASH_
## WAVE_DEFS' "launch" times).
const RAPID_SLASH_SFX_SLASH_KEY_BY_LABEL: Dictionary = {
	"wave_a": "slash_1", "wave_b": "slash_2", "wave_c": "slash_3",
}
## "sparks" (README: "金色の余韻", 1.50s) is the only one of the 7 with no
## existing one-shot event to piggyback on — the other 6 reuse an existing
## state transition (act-phase entry, a wave's own "active" flip,
## _start_rapid_impact, the hit fire) as their own natural once-per-cast
## guard. See _rapid_sfx_sparks_played.
const RAPID_SLASH_SFX_SPARKS_SECONDS := 1.50
## Muzzle flash (added in the prior polish round, REMOVED 2026-07-26: user
## report — a round white circle at the sword tip read as "a magic orb
## being fired", not a sword strike ("ラピッドスラッシュは剣技なので、円
## 形・球状の発光は使用しません"). No replacement shape was added either —
## the user's own explicit fallback ("うまく作れない場合は、何も追加せず
## 球だけ削除してください。既存の飛翔waveだけで発射は十分に伝わります")
## was taken, since a directional slash-streak's exact shape/proportions
## can't be verified visually in this headless-only environment, and
## getting it wrong risks the same "円形に見える" complaint in a new form.
## _draw_rapid_slash_muzzle, its state (per-wave "muzzle_t"), and its
## trigger at each wave's own launch are all gone — see this round's
## CLAUDE.md entry.
## --- Recoil (new, user spec item 4): a tiny, per-launch position kick —
## NOT the same kind of thing as the anticipation/overshoot effects removed
## in an earlier round (those were a generic pre-advance dip/arrival
## overshoot the user explicitly banned; this is a much smaller, launch-
## triggered, differently-motivated beat the user is now explicitly asking
## for). Values are the user's own exact numbers: wave_a +1px (forward),
## wave_b -1px (backward), wave_c +2px (forward) — see RAPID_SLASH_WAVE_
## DEFS' own "recoil_px" field. Settles back to 0 over RECOIL_SECONDS via
## the same smoothstep ease already used elsewhere in this file.
const RAPID_SLASH_RECOIL_SECONDS := 0.07
## --- Post-explosion debris (new, user spec item 6): "金色の火花・破片を
## 約0.20～0.25秒かけて減衰...少し上へ流れる/外側へ広がる/徐々に透明にな
## る". The delivered impact sprite's own F6-F8 frames already carry some
## of this ("光片"/"残光"/"最後の粒子" per their own doc comment), but they
## don't drift/spread on their own (a static sprite can't) — this adds a
## small code-drawn particle layer with exactly the 3 described motions,
## triggered at the SAME instant as the hit itself (RAPID_SLASH_HIT_AT_
## SECONDS, "最大爆発の瞬間"), layered on top of (not replacing) the
## delivered impact frames.
const RAPID_SLASH_DEBRIS_COUNT := 8
const RAPID_SLASH_DEBRIS_SECONDS := 0.22
const RAPID_SLASH_DEBRIS_DRIFT_PX := 26.0
const RAPID_SLASH_DEBRIS_SPREAD_PX := 34.0
## --- The 3 flying slashes (v3 rebuild, "wave_a/b/cが1個のVFXのフレーム
## 切替に見えている" fix): each is a fully independent, EXPLICITLY STATED
## runtime object (see _rapid_slash_waves) — active/elapsed/launch_time/
## start_position/target_position/rotation/draw_size/animation_frame all
## held per-wave, populated once when _enter_battle_anim_act_phase starts
## rapid_slash's own act phase and updated every tick by
## _update_rapid_slash_waves (see its own doc comment for why a genuinely
## independent travel path — not just independently-timestamped draws
## along the SAME line — is what actually fixes the "one shape growing"
## look). This const array is only the static PER-WAVE CONFIG (key/launch/
## arrive/draw_px/y_offset) _enter_battle_anim_act_phase seeds the runtime
## array from — not itself mutated.
##
## Launch spacing is 0.18s (the user's own stated minimum) apart — 0.48,
## 0.66, 0.84s. y_offset is the user's own exact numbers, applied at the
## wave's OWN impact point so the 3 slashes visibly converge on 3 different
## points instead of one.
##
## draw_px (final polish round): the user's own exact percentage deltas off
## the PREVIOUS round's sizes — wave_a 130*1.15=149.5→150 (+15%), wave_b
## 155*1.10=170.5→170 (+10%), wave_c 190*0.94≈178.6→178 (-6.3%, within the
## given 5-8% range). The same message also asked for the 3 to read as a
## roughly 25/30/45 "strength" balance — that target and these literal
## per-wave % deltas can't both be hit exactly by draw_px alone (solving
## for wave_c/total=0.45 given the other two's mandated growth would need
## wave_c near 260px, undoing "維持するのは最も大きい状態" into something
## far larger than before) — the literal deltas are implemented as given;
## see this round's CLAUDE.md entry for the honest math on why the 25/30/45
## framing is closer to a qualitative goal than a third, independently
## satisfiable constraint.
##
## recoil_px: the user's own exact numbers (see RAPID_SLASH_RECOIL_SECONDS'
## doc comment) — positive = toward the boss ("前"), negative = away ("後
## ろ"), applied via _rapid_slash_advance_offset_px at each wave's own
## launch instant.
const RAPID_SLASH_WAVE_DEFS: Array[Dictionary] = [
	{"key": "skill_vfx_rapidslash_wave_a", "label": "wave_a",
		"launch": 0.48, "arrive": 1.02, "draw_px": 150.0, "y_offset": -18.0, "recoil_px": 1.0},
	{"key": "skill_vfx_rapidslash_wave_b", "label": "wave_b",
		"launch": 0.66, "arrive": 1.12, "draw_px": 170.0, "y_offset": 12.0, "recoil_px": -1.0},
	{"key": "skill_vfx_rapidslash_wave_c", "label": "wave_c",
		"launch": 0.84, "arrive": 1.22, "draw_px": 178.0, "y_offset": 0.0, "recoil_px": 2.0},
]
## Each wave arrives a little short of the boss's own center (X only — Y
## comes from the wave's own y_offset above), same distance the old single
## crescent used.
const RAPID_SLASH_WAVE_IMPACT_OFFSET_PX := 25.0
## ease_out shape for each wave's own travel (user spec: "補間は一定速で
## はなくease_outを使用してください。ただし発射直後から一瞬で敵へ到達させ
## ないでください") — classic quadratic ease-out (1-(1-t)^2): starts at
## roughly 2x the average rate (not an instant jump) and tapers into the
## landing, satisfying both halves of that spec in one curve.
const RAPID_SLASH_WAVE_EASE_OUT_POWER := 2.0
## Small code-drawn spark at each wave's own arrival (user spec: "各wave
## の到着時には、小さな火花だけを表示してください。ダメージ処理はまだ発生
## させません") — no dedicated spark asset was delivered this round, so
## this follows the project's established fallback (see _draw_battle_
## impact's own code-drawn radial burst) rather than inventing a new image
## dependency for a one-off effect.
const RAPID_SLASH_SPARK_SECONDS := 0.15
const RAPID_SLASH_SPARK_RADIUS_PX := 14.0
## --- X-shape impact: fixed at the boss's own center, fixed draw size for
## all 8 frames (never scaled in code — the asset's own art bakes in the
## size/intensity change). v3 re-time, user's own exact per-frame seconds
## (F1..F8); F5 (RAPID_SLASH_HIT_AT_SECONDS) is the only frame that fires
## the actual hit. Draw size 300 -> 225 (a clean 25%, within the user's
## given 20-25% range: "敵を完全に覆い隠さず、敵のシルエットが少し確認で
## きる大きさに").
const RAPID_SLASH_IMPACT_KEY := "skill_vfx_rapidslash_impact"
const RAPID_SLASH_IMPACT_FRAMES: Array[Array] = [
	[1.22, 0], [1.26, 1], [1.30, 2], [1.34, 3], [1.38, 4], [1.44, 5], [1.51, 6], [1.59, 7],
]
## 1.66 -> 1.65: keeps F8 (1.59s) comfortably reachable on the 20fps tick
## grid (a 0.06s window, [1.59,1.65)) while landing the "~0.20-0.25s decay
## after the 1.38s max explosion" the user asked for (1.65-1.38=0.27s —
## slightly over the top of that range on purpose, not 1.63/0.25s exactly,
## specifically to avoid recreating the exact "window narrower than one
## tick, frame silently never shows" bug this project has hit twice
## already on this one skill — see this round's CLAUDE.md entry).
const RAPID_SLASH_IMPACT_END_SECONDS := 1.65
const RAPID_SLASH_IMPACT_DRAW_PX := 225.0
## --- Position: Sotiris advances only PART of the way toward the boss,
## never up to it — capped both by a fraction of the actual on-screen
## distance AND an absolute pixel ceiling (unchanged from the previous
## round — user spec: "stage_posの計算方法は現在のままで構いません").
## Computed fresh each draw call from the caster's resting position and
## the boss's current on-screen rect (both stable per-frame already; no
## need to cache actor_start/stage_pos as extra state — recomputing them
## from _battle_anim_origin each call is equivalent and simpler).
const RAPID_SLASH_ADVANCE_FRAC := 0.28
const RAPID_SLASH_ADVANCE_MAX_PX := 140.0
## Move-out (0 -> full) and return (full -> 0) BOTH use the user's own
## smoothstep-shaped ease-in-out formula (move_t*move_t*(3-2*move_t),
## identical to Godot's built-in smoothstep()) — the previous round used a
## faster ease-OUT curve for the advance specifically, which (combined
## with too short a duration) contributed to the "teleport" look; this
## round uses the same gentle in-out shape both ways, per the user's
## pseudocode for both phases. 0.14s -> 0.30s advance (>= the user's "最
## 低18フレーム" spec's 0.30s span, even though this engine's actual
## redraw rate is 20fps/1 tick=0.05s, not 60fps — see the CLAUDE.md entry
## for this round for the honest 18-vs-6-real-redraws distinction).
## v3 re-time: user spec "0.00～0.28秒 ソティリスが中央付近へ移動する".
const RAPID_SLASH_MOVE_OUT_SECONDS := 0.28
## Final-polish re-time, user spec item 7: "帰還開始前に0.08秒だけ振り抜き
## 姿勢を保持してください" — RETURN_START is now literally IMPACT_END_
## SECONDS + 0.08 (1.65+0.08=1.73), not a separately-chosen number, so the
## hold duration is exact regardless of any future IMPACT_END retiming.
## RETURN_END keeps the previous round's ~0.25s span (1.73+0.25=1.98).
## Move-out (0 -> full) and return (full -> 0) both already use smoothstep
## (move_t*move_t*(3-2*move_t)) — ease-in-out by construction, satisfying
## item 7's "ease_in_outを使用し、移動開始・停止を急にしないでください"
## with no shape change needed, only these two retimed endpoints.
const RAPID_SLASH_RETURN_START_SECONDS := RAPID_SLASH_IMPACT_END_SECONDS + 0.08
const RAPID_SLASH_RETURN_END_SECONDS := RAPID_SLASH_RETURN_START_SECONDS + 0.25


## ================= ヒーリング (2026-07-26 full overhaul) =================
## Rebuilt using rapid_slash's own implementation structure as the explicit
## reference (user spec: "完成済みの「ラピッドスラッシュ」を実装構造の基準
## にしてください") — its own dedicated constants/state/functions, entirely
## separate from the generic skill path AND from every RAPID_SLASH_* symbol
## (none of which are read, written, or otherwise touched anywhere below).
##
## Old bugs this replaces: the generic path played skill_minion_0_healing's
## whole 12-frame clip (character AND its baked-in yellow glow drawn as one
## image) AT THE CASTER's own position, regardless of which ally was
## selected — so the "heal" glow visibly happened on Sotiris, never on the
## target, and read as an attack/explosion rather than a heal. Fixed by
## separating into 6 independently-drawn/managed pieces (user spec's own
## list): ①caster casting motion ②caster-side cast VFX ③a light that
## travels from caster to target ④target-side heal VFX ⑤the target's own
## glow reaction ⑥HP number + HP bar.
const HEALING_SKILL_ID := "skill_healing"
const HEALING_ACT_SECONDS := 1.70
## Added on top of HEALING_ACT_SECONDS (not folded into it) — same
## "brief gap before the next character starts" convention RAPID_SLASH_
## POST_ACT_GAP_SECONDS established. User spec (2026-07-26 round 2):
## "ヒーリング終了後、0.5秒ほど別キャラクターを行動させないでください".
const HEALING_POST_ACT_GAP_SECONDS := 0.50
## User spec: "0.92秒で回復を一度だけ適用する".
const HEALING_HIT_AT_SECONDS := 0.92
## User spec: "0.5〜0.7秒かけて上昇・フェードさせる" for the "+回復量"
## popup — narrower than the shared BATTLE_ANIM_POPUP_SECONDS (0.8s) every
## other popup (damage numbers, and the other 3 heal-effect skills' own
## popups) still uses; see _fire_battle_anim_hit's heal branch for how this
## is applied ONLY when skill_id is healing's own, via the popup dict's new
## optional "duration" field (backward compatible — omitting it keeps the
## shared 0.8s default everywhere else, unchanged).
const HEALING_HEAL_POPUP_SECONDS := 0.6

## --- SFX (2026-07-26 v2 delivery, README_ClaudeCode.md) — 3 sounds, each
## played once per cast, no looping. The README's own default timeline
## (0.00/0.46/0.60s from "演出開始") is explicitly a FALLBACK — its own
## §"演出コード側の実時間が異なる場合は、次の視覚イベントを優先して合わせ
## ます" instructs matching the DESCRIBED visual beat instead, and this
## implementation's actual beats already land on named one-shot events:
## - charge  = "ソティリスの光が立ち上がる最初のフレーム" -> the orb's own
##   start (HEALING_ORB_START_SECONDS, 0.28s) — "HEALING orb formed" log.
## - bloom   = "対象側の魔法陣が開き、HP更新が成立するフレーム" -> the
##   exact instant HP actually updates (HEALING_HIT_AT_SECONDS, 0.92s,
##   well after the circle already finished opening at 0.82s but the ONLY
##   instant "HP更新が成立" literally happens) — "HEALING heal applied" log.
## - afterglow = "対象の発光が最大になり、光が残り始めるフレーム" -> the
##   target's flash is already at its single peak value the instant it's
##   set (also 0.92s, same as bloom), and "光が残り始める" (light starts
##   to LINGER) is precisely when the hold-then-fade window begins
##   (HEALING_CIRCLE_FADE_START_SECONDS, 1.02s) — "HEALING pillar ended"
##   log. Landing 0.10s after bloom (not simultaneous) also avoids the two
##   sounds firing on the exact same tick.
## Played from _update_healing_state, right alongside the 3 existing debug
## logs at these SAME instants — no new one-shot guard state needed, a
## debug log firing already means "this beat is happening for the first
## and only time this cast" (see this file's own healing debug-log block).
const HEALING_SFX_PATHS: Dictionary = {
	"charge": "res://assets/audio/sfx/healing_charge.wav",
	"bloom": "res://assets/audio/sfx/healing_bloom.wav",
	"afterglow": "res://assets/audio/sfx/healing_afterglow.wav",
}

## --- Caster casting motion (2026-07-26 re-fix): NO dedicated clip any
## more. The delivered 12-frame skill_minion_0_healing clip's own hand-
## picked "clean" frames (1/2/11/12, the previous approach) still visibly
## showed the body and sword as disconnected pieces plus a stray dark
## fragment when actually watched in-game (not something the earlier
## headless-only numeric verification could catch), and the clip's
## per-frame bbox differences made Sotiris's size/pose/footing wobble
## during the cast. User spec: "使用できるきれいなキャラクター単体フレー
## ムがない場合は...通常の戦闘立ち絵を詠唱中も表示する" — so the caster
## now simply keeps rendering via _draw_party_row's normal resting/idle
## path for the whole cast (see _enter_battle_anim_act_phase's
## HEALING_SKILL_ID branch, which deliberately never touches
## _battle_anim_motion_key/_battle_anim_pos for this unit). No constants
## needed here any more; the asset files themselves are left in place
## (git history has the old wiring if this ever needs revisiting).

## --- Caster-side orb / pre-cast windup (user spec, 2026-07-26 round 2:
## "発射前の約0.20秒、剣先または手元へ小さな金白色の光を集める。小さな光
## 粒子を3〜4個だけ吸い込ませる。光球が一度だけ少し膨らんでから対象へ飛
## ぶ") — entirely code-drawn, no delivered asset for this (same "no
## asset, code-drawn fallback" precedent RAPID_SLASH_SPARK_*/_DEBRIS_*
## already established). Window ends exactly at HEALING_BEAM_START_SECONDS
## so the swell reads as the same light launching, not two separate
## effects — was previously 0.18-0.48 (0.30s, particles rising AWAY);
## narrowed to the requested ~0.20s and the particles now converge INWARD
## ("吸い込ませる" = drawn IN, not rising off).
const HEALING_ORB_START_SECONDS := 0.28
const HEALING_ORB_END_SECONDS := 0.48
const HEALING_ORB_RADIUS_PX := 9.0
const HEALING_ORB_PARTICLE_COUNT := 4
## The last stretch of the gather window where particles are drawn inward
## instead of orbiting, and the swell-before-launch pulse plays.
const HEALING_ORB_CONVERGE_SECONDS := 0.16
const HEALING_ORB_SWELL_SECONDS := 0.06
const HEALING_ORB_SWELL_SCALE := 1.45

## --- Travelling light (user spec, 2026-07-26 re-fix: "剣先から回復対象の
## 胸元まで、金白色の曲線状の光を伸ばす。先端には白い核と金色の外光。後ろ
## に2〜3個の光粒子。直線ではなく緩やかな弧を描く。移動時間は約0.30秒。現
## 在より2〜3倍明るく"). Unlike rapid_slash's 3 STAGGERED waves, there is
## only ever ONE of these per cast with one fixed timing window — the
## "looks like one shared object" failure mode that forced the waves into
## stateful runtime objects doesn't apply here, so this stays a plain
## stateless function of elapsed time + the entry's own target_id
## (recomputed fresh every draw call, same pattern rapid_slash's OWN charge
## glow/dust/impact already use for their own single-instance effects).
const HEALING_BEAM_START_SECONDS := 0.48
const HEALING_BEAM_DURATION_SECONDS := 0.30
const HEALING_BEAM_END_SECONDS := HEALING_BEAM_START_SECONDS + HEALING_BEAM_DURATION_SECONDS
## How far the arc bulges above the straight caster->target line, as a
## fraction of the horizontal distance between them — a plain lerp read as
## "a straight bullet", not the requested "緩やかな弧".
const HEALING_BEAM_ARC_FRAC := 0.22
const HEALING_BEAM_ARC_MIN_PX := 18.0
const HEALING_BEAM_HEAD_RADIUS_PX := 13.0
## Trailing particles sampled BEHIND the head along the same curve (user
## spec: "後ろに2〜3個の小さな光粒子を残す").
const HEALING_BEAM_TRAIL_COUNT := 3
const HEALING_BEAM_TRAIL_GAP_T := 0.10

## --- Target-side magic circle (user spec: "キャラ幅の約1.4倍の金白色の魔
## 法陣...色は金白色を中心に...淡い緑を加える", round-2 addendum: "最大時
## の明るさを現在より少し上げる"). Sized off PARTY_ICON_PX (the character's
## own draw box) so it visibly scales with the character instead of a small
## fixed radius that used to read as "ほとんど見えない" once the target's
## own sprite mostly covered it. Drawn BEHIND _draw_party_row (user spec:
## "魔法陣は対象の後ろ"), visible through the lingering window before
## fading out entirely.
##
## Round-2 retiming: FADE_START/END now derive from HEALING_HIT_AT_SECONDS
## (the instant the heal actually lands) instead of standalone absolute
## seconds — user spec: "回復成立後も約0.4秒、細かな粒子を上へ残す". A
## short 0.10s hold at full brightness right after the heal registers,
## then a 0.30s fade (0.10+0.30 = the requested ~0.4s), shared by the
## circle/pillar-column/rising-particles so the whole VFX group fades out
## together (user spec: "回復VFX全体を一瞬で消さず、滑らかにフェードさせ
## る") rather than each piece cutting off on its own separate schedule.
const HEALING_CIRCLE_START_SECONDS := 0.62
const HEALING_CIRCLE_GROW_END_SECONDS := 0.82
const HEALING_POST_HEAL_HOLD_SECONDS := 0.10
const HEALING_POST_HEAL_FADE_SECONDS := 0.30
const HEALING_CIRCLE_FADE_START_SECONDS := HEALING_HIT_AT_SECONDS + HEALING_POST_HEAL_HOLD_SECONDS
const HEALING_CIRCLE_END_SECONDS := HEALING_CIRCLE_FADE_START_SECONDS + HEALING_POST_HEAL_FADE_SECONDS
const HEALING_CIRCLE_MIN_RADIUS_PX := 26.0
const HEALING_CIRCLE_MAX_RADIUS_PX := float(PARTY_ICON_PX) * 0.7  ## diameter = 1.4x character width

## --- Light pillar (user spec: "身長の約1.5倍まで伸びる柔らかな光柱").
## Round-2 addendum EXPLICITLY moves this back to the ground/BEHIND layer
## ("対象の後ろに柔らかな縦方向の光柱を追加する") — the prior round had
## moved the pillar (column + rising particles bundled together) to the
## FRONT layer to fix a real occlusion bug (a narrow column directly behind
## an icon_px-wide sprite was mostly hidden). This round's own spec is
## explicit about the column specifically going behind again, so
## HEALING_PILLAR_ALPHA is raised (0.45->0.58) to stay visible past the
## character's own silhouette — the RISING PARTICLES stay in front (see
## _draw_healing_rising_particles/_draw_healing_caster_vfx), since nothing
## in this round's spec asked to move those back, and thin bright motes
## read fine over a sprite even when the broader glow column doesn't.
const HEALING_PILLAR_START_SECONDS := 0.78
const HEALING_PILLAR_FADE_IN_SECONDS := 0.08
const HEALING_PILLAR_WIDTH_PX := 38.0
const HEALING_PILLAR_HEIGHT_PX := float(PARTY_ICON_PX) * 1.5
const HEALING_PILLAR_ALPHA := 0.58

## --- Rising particles, front layer, spanning both the pillar-active
## window AND the post-heal lingering window (user spec: "上へ昇る金白色の
## 粒子"; "回復成立後も約0.4秒、細かな粒子を上へ残す").
const HEALING_LINGER_END_SECONDS := HEALING_CIRCLE_END_SECONDS
const HEALING_LINGER_PARTICLE_COUNT := 6
const HEALING_LINGER_PARTICLE_CYCLE_SECONDS := 0.6

## --- Encircling ring, front layer (user spec: "対象の周囲を一周する淡い
## 緑色の光") — a short comet of fading dots that sweeps once around an
## ellipse centered on the target's chest, rather than a static ring, so it
## actually reads as light traveling AROUND the character rather than a
## motionless halo.
const HEALING_RING_START_SECONDS := 0.68
const HEALING_RING_DURATION_SECONDS := 0.55
const HEALING_RING_RADIUS_X := float(PARTY_ICON_PX) * 0.60
const HEALING_RING_RADIUS_Y := float(PARTY_ICON_PX) * 0.85
const HEALING_RING_TRAIL_COUNT := 16
const HEALING_RING_TRAIL_GAP_T := 0.014

## --- Target reaction (user spec item 5, "回復対象の発光反応...約0.12秒だ
## け白金色に発光"): a plain white-gold tint via _draw_party_row's
## modulate — deliberately separate from the existing _battle_ally_hit_t/
## _battle_ally_hit_unit system (that one is knockback-coupled; user spec
## explicitly forbids knockback/shake for healing's own target reaction).
const HEALING_TARGET_FLASH_SECONDS := 0.12
## HP bar smooth fill duration (user spec: "HPバーも滑らかに増加させる" —
## no exact seconds given, a judgment call sized to read clearly within the
## 0.92-1.12s pillar-active window without racing ahead of it).
const HEALING_HP_BAR_ANIM_SECONDS := 0.3


## ================= ソウルブレイク v3 (2026-07-26 full rewrite) ===========
## v2 (draw_circle-based core/flight/ring/burst, texture-reused trailing
## wisp) was rejected by the user as "not finished" — a fully separate
## visual language replaces it this round (user spec: "白い中心を持つ大き
## な真円...滑らかなグラデーション円...を廃止...輪郭はギザギザしたドット
## で構成する"). Same THIRD-dedicated-skill-block convention rapid_slash/
## healing established (user spec: "ラピッドスラッシュとヒーリングは一切
## 変更しません" — no RAPID_SLASH_*/HEALING_* symbol read or written here).
## The character STILL keeps playing its own delivered clip (unchanged
## from v2's own reasoning — no reported asset defect for this skill), so
## _draw_party_row's existing generic "skill_minion_" branch still applies
## (fixed SKILL_ACTOR_DRAW_SIZE box, no per-frame get_used_rect scaling).
##
## New visual language (user spec's own 4-stage read): "3つの魂片を剣へ集
## める" -> "方向性のある魂槍として撃ち出す" -> "敵の内部で三重円環が順番
## に収縮する" -> "魂が放射状に砕ける". Every shape below is a jittered,
## hard-banded (no gradient) polygon or a small dot/square — never
## draw_circle/draw_arc, never GradientTexture, never texture_filter
## LINEAR (this file's project-wide default is NEAREST; nothing here
## overrides it, unlike v2's reused proj_soul_break clip which explicitly
## switched to LINEAR).
const SOUL_BREAK_SKILL_ID := "skill_soul_break"
## v13 (2026-07-27, final tuning pass #6): user spec restricts scope to
## "飛翔体と発射モーションのみ修正する" — impact-side rings/white core/
## crack/damage/enemy flash/knockback/shake/hitstop AND the downswing's
## own TIMING (DOWNSWING_START/SWING_C_SECONDS/LAUNCH_SECONDS) are ALL
## untouched. What changes: (1) the projectile's on-screen size roughly
## doubles (CANVAS_SIZE); (2) flight duration 0.24->0.48s, now driven by a
## genuinely continuous per-render-frame timer instead of the tick-
## quantized elapsed (see SOUL_BREAK_PROJ_FLIGHT_* below and _process());
## (3) the silhouette is rebuilt again — much shorter exposed white tip
## (20-30px, down from 86px), front-center mass bias, a smaller/separate
## jagged lower fragment instead of a matching shell; (4) the spawn offset
## grows to keep clearing the now-much-taller sprite; (5) the slash trail
## shrinks (~40% less area, 2 thin broken strands instead of one 6px-wide
## double-layer arc) and its own visible window narrows from 4 ticks to 3;
## (6) the post-launch hold-before-recovery becomes a FRACTION of the new
## flight duration (65-70%) instead of a fixed short beat. Net effect:
## everything from launch onward shifts later (flight alone adds +0.24s);
## ACT_SECONDS grows to keep the same 0.25s return tail after that.
## v16 (rapid_slash 5-stage structure ported in) shortened this a lot
## from the old 18-frame sprite's 0.90s runtime; every round since has
## retimed it — kept as a literal (not a formula) since this constant is
## defined before the values it derives from. v20: the whole pre-launch
## sequence compressed to LAUNCH_SECONDS=0.40 (was 0.65), so CONTACT/MAX_
## IMPACT/FLIGHT_END all shift to 0.82 (was 1.07) and SOUL_BREAK_RETURN_
## END_SECONDS follows to 1.07 (was 1.32) — this is that new RETURN_END
## plus the same +0.04 buffer every prior round has used, so the return
## walk always finishes within this window.
const SOUL_BREAK_ACT_SECONDS := 1.11
## Handoff buffer before the next character starts — same convention
## RAPID_SLASH_POST_ACT_GAP_SECONDS/HEALING_POST_ACT_GAP_SECONDS use.
const SOUL_BREAK_POST_ACT_GAP_SECONDS := 0.15

## --- Stance / step-in (user spec: "0.00〜0.12 構え" — shortened from
## v4's 0.15s). Applied as a draw-time x_offset in _draw_party_row
## (_soul_break_advance_offset_px) — _battle_anim_pos itself stays at
## _battle_anim_origin the whole cast. No VFX at all is drawn during this
## window (every draw function's own window starts AT or AFTER SOUL_
## BREAK_GATHER_START_SECONDS), which is what keeps "黒い分身や残像を表示
## しない" true by construction — nothing drawn there at all, asset-based
## or code-drawn.
const SOUL_BREAK_STANCE_SECONDS := 0.12
const SOUL_BREAK_STEP_PX := 10.0

## --- Sword-tip anchor (v7, user spec: "ActorRootにMarker2D「SoulBreak
## SwordTip」を追加...ローカル座標で管理...集魂・魂核・飛翔体の開始位置は
## すべてこれを基準にする"). This codebase has no Sprite2D/Marker2D scene
## nodes at all (pure _draw() rendering throughout, see CLAUDE.md) — a
## real Marker2D with a local transform isn't expressible here, so the
## same intent (a single named anchor point, defined relative to the
## character rather than the screen, that every launch-point reads) is
## expressed as a fixed pixel offset from the caster's own current draw
## anchor (_soul_break_caster_pos — already relative to the character's
## current position/step-in offset) via _soul_break_sword_tip_pos below.
## Every gather/core/projectile function in this file was rewritten this
## round to read THAT function instead of computing its own ad-hoc
## center, so they can never drift apart from one another. Offsets are
## an approximation of where the blade tip sits in the current "構え"
## stance art — untunable without seeing the actual sprite pixels
## (headless Godot renders nothing); retune these 2 consts first if the
## user reports the anchor doesn't line up with the sword in-game.
const SOUL_BREAK_SWORD_TIP_OFFSET_X_PX := 14.0
const SOUL_BREAK_SWORD_TIP_OFFSET_Y_PX := -10.0
## v9: the tip no longer sits at ONE fixed point for the whole cast — once
## the downswing (C) begins, it sweeps through 3 more local-space key
## points (顔の横→胸の前→右下, user spec's own downswing path) before
## settling at the last one for D/launch. All in the SAME facing-local
## space as the offset above (x mirrored by facing, y absolute) — see
## _soul_break_sword_tip_pos's own v9 branch.
const SOUL_BREAK_SWING_TIP_OFFSETS: Array[Vector2] = [
	Vector2(SOUL_BREAK_SWORD_TIP_OFFSET_X_PX, SOUL_BREAK_SWORD_TIP_OFFSET_Y_PX),  ## overhead (unchanged start)
	Vector2(20.0, -8.0),   ## 顔の横
	Vector2(16.0, 6.0),    ## 胸の前
	Vector2(10.0, 22.0),   ## 右下 — where the projectile ends up launching from
]

## --- Soul-shard gather, v8 retime (user spec: "剣先に紫色が突然出現し
## たように見える...魂片の収束を通常速度でも読めるようにする"). v7's
## "staggered start, synced arrival" design is replaced with "staggered
## start, EACH shard's own fixed 0.16-0.20s travel time" (user spec:
## "開始を0.06秒ずつずらす...各魂片の移動時間を0.16〜0.20秒にする") — a
## uniform 0.18s travel per shard both sits in the middle of that range
## AND guarantees the "3個すべての軌道が一度は同時に見える時間" window
## below safely straddles at least one engine tick regardless of exact
## alignment (see SOUL_BREAK_SHARD_TRAVEL_SECONDS' own note).
## v20: user spec compresses the whole pre-launch gather+core-hold span
## into a 0.18s budget ("0.00～0.18秒: 剣を頭上へ構える、白紫の光を剣へ集
## める", down from the old 0.50s). Every gather/core-hold const below is
## scaled by 0.18/0.50 ≈ 0.36 to compress the SAME choreography rather
## than redesign it, landing CORE_HOLD_END exactly on the user's own 0.18
## boundary. Disclosed tradeoff: this drops the shard-overlap window below
## the 1-tick safety margin the comment above relied on for "all 3 shards
## visible together" — not restated this round, so relaxed in favor of the
## new overall length target.
const SOUL_BREAK_GATHER_START_SECONDS := 0.02
const SOUL_BREAK_SHARD_COUNT := 3
## user spec: "開始を0.06秒ずつずらす" (up from v7's 0.05s).
const SOUL_BREAK_SHARD_START_STAGGER_SECONDS := 0.02
## user spec: "各魂片の移動時間を0.16〜0.20秒にする" — 0.18s, the range's
## midpoint. With the 0.06s stagger above, shard windows are [start_i,
## start_i+0.18) — the 3 windows overlap in [start_C, arrive_A) =
## [0.24, 0.30), a 0.06s span comfortably wider than one 0.05s engine
## tick, so at least one tick is guaranteed to render all 3 simulta-
## neously regardless of exact sub-tick alignment (user spec: "3個すべ
## ての軌道が一度は同時に見える時間を作る").
const SOUL_BREAK_SHARD_TRAVEL_SECONDS := 0.07
## Each shard's LAST arrival (C, the latest starter) — the instant the
## last shard reaches the sword tip and the just-formed core can begin
## its own hold. = GATHER_START + 2*STAGGER + TRAVEL.
const SOUL_BREAK_SHARD_LAST_ARRIVE_SECONDS := \
	SOUL_BREAK_GATHER_START_SECONDS + 2.0 * SOUL_BREAK_SHARD_START_STAGGER_SECONDS \
		+ SOUL_BREAK_SHARD_TRAVEL_SECONDS  ## 0.42
## Each shard's FIXED starting offset in facing-LOCAL space (x measured
## toward the enemy, mirrored by facing) — user spec: "キャラの輪郭外に
## ある上・後方・下の3地点から開始" (above / behind / below, all clear
## of the ~64px-tall sprite's own silhouette; exact clearance is an
## approximation — untunable without seeing the actual sprite pixels,
## same caveat as the sword-tip anchor above). Straight-line distance
## from each of these 3 points to the sword tip all exceed the user's
## 24px minimum (~26px/~50px/~47px respectively, computed not measured).
const SOUL_BREAK_SHARD_LOCAL_OFFSETS: Array[Vector2] = [
	Vector2(0.0, -32.0), Vector2(-34.0, 4.0), Vector2(4.0, 36.0),
]
## Bezier control-point offset straight up/down from each shard's own
## straight-line midpoint (user spec: "キャラの胴体上には重ねない") — A
## (above) arcs further up over the head/shoulder before diving to the
## tip, B (behind) arcs up and over the side, C (below) arcs further
## down under the hip/legs before rising — none cut straight through the
## torso's own center.
const SOUL_BREAK_SHARD_BULGE_PX: Array[float] = [-10.0, -14.0, 14.0]
## user spec: "それぞれ7×5px程度の欠けた菱形／炎片にする" — one uniform
## size this round (v7 had 3 distinct sizes; not asked for again here).
const SOUL_BREAK_SHARD_SIZE_PX := 7.0

## --- Core hold + compression, v10 retime (user spec: "到着後、頭上の構
## えを0.06〜0.08秒保持する。この保持中に魂核を細長く圧縮する" — shrunk
## from v9's 0.20s hold+squeeze+stretch sequence down to a single ~0.08s
## beat, matching this round's explicit "接続だけを修正する" scope: a
## single "already compressed, thin and long" core shown for the WHOLE
## short hold, rather than v9's 2-stage squeeze->stretch snap (that
## 2-stage distinction wasn't restated this round, and trying to keep it
## inside an 0.08s window would reintroduce the same "segment narrower
## than 1 tick" risk this file has repeatedly had to work around —
## simplifying to 1 state sidesteps it entirely, disclosed here rather
## than silently dropped).
const SOUL_BREAK_CORE_HOLD_SECONDS := 0.05  ## v20: compressed, 1-tick floor kept
const SOUL_BREAK_CORE_HOLD_END_SECONDS := \
	SOUL_BREAK_SHARD_LAST_ARRIVE_SECONDS + SOUL_BREAK_CORE_HOLD_SECONDS  ## 0.50
const SOUL_BREAK_CORE_HOLD_LENGTH_PX := 26.0
const SOUL_BREAK_CORE_HOLD_WIDTH_PX := 6.0

## --- Sword downswing, v10 retime (user spec: "振り下ろしを4段階で明確
## に表示する...頭上の構え／顔の横45度／胸の前水平／右下への振り抜き姿勢
## を0.12〜0.15秒で順番に表示する"). Pose 1 ("頭上の構え") is simply
## frame 2 continuing to hold — no new breakpoint needed, it's already
## displayed the instant the hold above ends. Poses 2-4 (frames 3,4,5) use
## 3 equal SEGMENTS of EXACTLY one engine tick (0.05s) each — a half-open
## window of length EXACTLY one tick period ALWAYS contains exactly 1
## tick regardless of alignment — so all 3 are STRUCTURALLY guaranteed
## visible; total 0.15s lands exactly at this round's own upper bound (no
## deviation needed, unlike v9's version of this same tradeoff).
## v20: DOWNSWING_START now lands on the user's own 0.18 boundary
## ("0.18～0.32秒: 剣を上から下へ...振り下ろす") via the compressed gather
## chain above (CORE_HOLD_END_SECONDS = 0.02+2*0.02+0.07+0.05 = 0.18,
## exact). SWING_SEGMENT_SECONDS is kept at 0.05s (1 full engine tick,
## BATTLE_ANIM_FPS=20) rather than compressed further to the user's
## literal 0.14s window for this stage — each of the 3 downswing poses
## (顔の横/胸の前/右下) is selected from the TICK-quantized elapsed clock
## (_on_battle_anim_tick, 0.05s cadence), so any segment narrower than one
## tick risks that pose never actually being rendered on some runs (this
## file's own established "1-tick floor" rule, e.g. SOUL_BREAK_CORE_HOLD_
## SECONDS above). Landing at 0.15s total instead of 0.14s is a 0.01s
## deviation, disclosed rather than risking a dropped pose.
const SOUL_BREAK_DOWNSWING_START_SECONDS := SOUL_BREAK_CORE_HOLD_END_SECONDS  ## 0.18
const SOUL_BREAK_SWING_SEGMENT_SECONDS := 0.05
const SOUL_BREAK_SWING_C_SECONDS := SOUL_BREAK_SWING_SEGMENT_SECONDS * 3.0  ## 0.15
const SOUL_BREAK_DOWNSWING_END_SECONDS := \
	SOUL_BREAK_DOWNSWING_START_SECONDS + SOUL_BREAK_SWING_C_SECONDS  ## 0.33

## --- v20 NEW: separation. User spec section 4: "0.32～0.40秒: 振り切っ
## た剣先から飛翔体が分離...最初のフレームでは剣先と飛翔体を接触させる、
## 次のフレームから前方へ離す" — a distinct micro-phase between the
## downswing finishing and the blade being fully independent, so "キャラ
## が振る／剣先から生まれる／敵へ向かって飛ぶ" reads as one continuous
## motion instead of the blade just popping into existence at LAUNCH. See
## _draw_soul_break_separation: draws the SAME blade texture, lerping from
## the LIVE sword-tip position (t=0, touching) to the fixed flight spawn
## point (t=1, LAUNCH_SECONDS) — the flight draw function itself still
## only takes over once actual flight begins, unchanged.
const SOUL_BREAK_SEPARATION_SECONDS := 0.07

## --- Launch + flight. Launch now fires at the end of the new separation
## micro-phase above (was: the instant the downswing's own last pose was
## reached). The flight DURATION and impact position stay untouched this
## round — only WHEN launch fires moves, same principle as the v9 comment
## this replaces.
const SOUL_BREAK_LAUNCH_SECONDS := \
	SOUL_BREAK_DOWNSWING_END_SECONDS + SOUL_BREAK_SEPARATION_SECONDS  ## 0.40
const SOUL_BREAK_RECOIL_PX := 5.0
const SOUL_BREAK_RECOIL_SECONDS := 0.08
## Holds the final "右下" pose for a beat AFTER launch. v18 retime: user
## spec section 1: "発射後は0.10～0.14秒ほど振り切った姿勢を残してくださ
## い" — a flat absolute duration this round (0.12 = the range's
## midpoint), superseding v13's "fraction of flight" formula (which no
## longer cleanly maps onto a spec now stated in plain seconds).
const SOUL_BREAK_POST_LAUNCH_HOLD_SECONDS := 0.12
## Recovery frames 6-7 (the shared clip's own "戻り") play AFTER the post-
## launch hold, over ~0.12s total (user spec's own figure) — 2 segments of
## 0.06s each, comfortably above the 1-tick (0.05s) guarantee floor.
const SOUL_BREAK_RECOVER_START_SECONDS := \
	SOUL_BREAK_LAUNCH_SECONDS + SOUL_BREAK_POST_LAUNCH_HOLD_SECONDS  ## 0.77
const SOUL_BREAK_RECOVER_SEGMENT_SECONDS := 0.06

## --- Slash trail (user spec restates the "no filled fan" intent as: "現
## 在の大きな白い扇形は面積を約40%減らす...内部が透明な白紫の途切れた2本
## の軌跡にする。表示は2〜3フレームだけ" — v10's own doc comment already
## attributed the ORIGINAL "白い半円" complaint to the retired radial
## launch-burst, but headless review of v10's own trail-arc technique
## found a second real contributor: 12 densely-packed 6px-wide overlapping
## quads along a bowed path DOES paint as a solid swept wedge, not a thin
## trail, once wide enough — so this round both shrinks it AND narrows its
## own visible window). v13: TRAIL_START moves from DOWNSWING_START+1
## segment to LAUNCH_SECONDS-1 segment — still fully inside the
## UNCHANGED, protected downswing schedule (0.50-0.65), just a narrower
## slice of it — cutting total visible ticks from 4 down to 3 (user spec:
## "2〜3フレームだけ"). PEAK still lands exactly on SOUL_BREAK_LAUNCH_
## SECONDS (user spec: "斬撃軌跡が最大になるフレームと発射を同期する").
const SOUL_BREAK_TRAIL_START_SECONDS := \
	SOUL_BREAK_LAUNCH_SECONDS - SOUL_BREAK_SWING_SEGMENT_SECONDS  ## 0.60
const SOUL_BREAK_TRAIL_PEAK_SECONDS := SOUL_BREAK_LAUNCH_SECONDS  ## 0.65
const SOUL_BREAK_TRAIL_BREAK_SECONDS := \
	SOUL_BREAK_TRAIL_PEAK_SECONDS + SOUL_BREAK_SWING_SEGMENT_SECONDS  ## 0.70
const SOUL_BREAK_TRAIL_END_SECONDS := \
	SOUL_BREAK_TRAIL_BREAK_SECONDS + SOUL_BREAK_SWING_SEGMENT_SECONDS  ## 0.75

## User spec: "飛行時間を0.48秒にする...現在は約0.25秒で着弾しており、形
## を認識できない" — up from 0.24s. Position during this window no longer
## comes from the tick-quantized `elapsed` at all (see SOUL_BREAK_PROJ_
## FLIGHT_* instance vars and _process() below, user spec: "Timerやスプ
## ライトアニメーションのフレームで更新せず、_process(delta)などで毎描
## 画フレーム更新する...移動が5段階のワープに見えず、毎フレーム滑らかに"
## — at the OLD 0.24s flight and BATTLE_ANIM_FPS=20 (0.05s/tick), position
## only ever advanced ~5 times across the whole flight, reading as a
## discrete warp between waypoints instead of motion).
## v18 retime: user spec then: "飛翔時間：0.38～0.46秒" — 0.42s, the
## range's midpoint.
## v19: the round's lock list names "飛翔時間0.48秒" as a LOCKED value,
## but the actual current value is 0.42s (set last round from that
## round's own explicit 0.38-0.46 range). The operative instruction is
## "以下は現在のまま固定してください" — keep things AS THEY CURRENTLY
## ARE — so 0.42 is kept untouched rather than "restored" to 0.48, which
## would silently revert a deliberate prior request. Flagged to the user.
const SOUL_BREAK_FLIGHT_SECONDS := 0.42
const SOUL_BREAK_FLIGHT_END_SECONDS := SOUL_BREAK_LAUNCH_SECONDS + SOUL_BREAK_FLIGHT_SECONDS  ## 1.07
## --- Flying spear, v18 FULL REDESIGN (user report on v17-fix's blade:
## "巨大な紫色の矢印・マウスカーソルに見えます" — a single closed
## silhouette, however hard-edged, still read as a symmetric arrow/
## cursor). New concept: "引き裂かれた魂をまとった、欠けた大剣型のエネ
## ルギー刃" — an OFF-CENTER tip, 2 genuinely SEPARATE shard pieces
## (upper larger/longer-reaching, lower shorter — user spec: "外周を完全
## に閉じた輪郭にしない") with a real transparent notch between them, a
## short diagonal (not horizontal) white-purple spine floating mostly
## WITHIN that gap rather than spanning the whole body, and 3 scattered
## detached "soul tear" fragments trailing behind at varied distances/
## angles. Generated at GENUINELY low native resolution (76x26 — user
## spec: "元画像サイズ：72×24pxまたは80×28px...ゲーム内で2倍前後に拡大
## ...低解像度Imageに描画してNearestで拡大") rather than authored at
## display resolution and only claiming to be hard-edged; every fill is a
## flat polygon rasterized at that small native size, so the display-time
## 2x Nearest upscale reads as genuinely blocky pixel art rather than a
## smoothed-down vector shape. 5 exact flat RGBA values (headless-
## verified zero anti-aliasing), content 138x52px at 2x display (user
## target: 135-155 x 42-52px). Single static frame (no animation was
## asked for; a static frame also trivially satisfies "最初から最後まで
## 同じ大きさを保ってください" and avoids this session's repeated multi-
## frame consistency bugs). Loaded through the same bypass-UDArtLibrary
## _soul_break_load_texture cache every other soul_break VFX asset uses.
## v19 REPLACEMENT (user report: the v18 multi-fin blade read as "黒紫の3
## 本線 / 爪痕 / 細い棒 / 重なったブーメラン" — its separate shards plus
## 2 same-shaped afterimages were indistinguishable from each other).
## User spec this round: "ラピッドスラッシュの飛翔VFXを直接基準に...その
## 飛翔体の形状を複製し...新しい形状をゼロから複雑なポリゴンで発明せず".
##
## soulbreak_wave.png is therefore a pixel-for-pixel RECOLOR of rapid_
## slash's own skill_vfx_rapidslash_wave_c_f4.png — shape, thickness,
## alpha channel and every edge bit-identical; only hue is remapped
## (luminance-driven gradient, same technique the v16 launch-arc recolor
## used). rapid_slash's file is READ, never written.
##
## Source frame chosen by headless analysis: of wave_c's 4 frames, f4 has
## the highest single-connected-blob ratio (98% of opaque pixels vs
## 89-96%), directly satisfying "シルエットが1つにつながっている" and
## avoiding the scattered specks the other frames carry. wave_c is also
## rapid_slash's own LARGEST wave (draw_px 178 vs 150/170) — user spec:
## "最も大きく、太い光の弧をベースにしてください".
##
## Measured output area ratios (v19): pale/white core 60% (target
## "55～65%"), main purple 35% (target "20～30%" — 5 points over, see the
## user report for the disclosed tradeoff), near-black outer 5% (target
## "必要最小限"). Headless-verified that the crescent's dark-looking inner
## concave region contains ZERO opaque dark pixels — it is the background
## showing through the shape's own open side, structurally identical to
## rapid_slash's original.
##
## v20 (this round): user confirms the SHAPE is good as-is ("土台として
## 残してください...ゼロから別の画像へ作り直さないでください") and asks
## only for a bigger on-screen size, a thicker core, and soul_break's own
## dedicated purple palette (5 exact hex values, replacing v19's slightly
## different set) — no gold/cyan anywhere. gen_v20_wave.gd re-runs the
## SAME luminance-remap of rapid_slash's wave_c_f4 (still read-only, still
## bit-identical shape/alpha/edges) with the new 5 colors, and SOLVES the
## core-band luminance threshold from the source's own histogram so the
## output core area is exactly 1.15x v19's measured 60% (=69%, headless-
## verified) rather than picking a threshold and eyeballing the result.
const SOUL_BREAK_BLADE_KEY := "soulbreak_wave"
## Local (0,0) = inside the crescent's trailing arms, behind the bright
## core — the "back end near the character" role every prior round's
## anchor has played. Scaled from v19's (40,38) by the SAME factor as the
## canvas resize below (v19's anchor was at 20.0%/41.3% of its own dest
## rect; this is that same fraction of the new, larger rect), so the
## anchor stays at the identical RELATIVE point on the unchanged shape.
const SOUL_BREAK_BLADE_ANCHOR_PX := Vector2(50.8, 50.0)
## Destination rect. v20: user asks for "現在より横幅を1.20倍、縦幅を
## 1.15倍" AND an absolute on-screen target (190-220 x 64-76px) — headless
## measurement of v19's own actual rendered content (160.9x53.2px, not the
## slightly-stale 158x53 the v19 comment estimated) showed a literal
## 1.20x/1.15x scale undershoots the absolute floor (193.1x61.2, below the
## 64px height minimum). The absolute range is the more concrete,
## verifiable acceptance criterion, so this rect is solved to land near
## the MIDDLE of both target ranges instead (headless-verified content
## bbox at this size: 204x70px) — width ends up +27% over v19, height
## +31%, both a bit past the literal 1.20/1.15 multipliers; disclosed
## rather than silently picked.
const SOUL_BREAK_BLADE_CANVAS_SIZE := Vector2(254.0, 121.0)
## --- Spawn position (unchanged from v15/v16 — user spec then: "原点を
## 剣先から進行方向へ12px進めた位置に置く"; this round doesn't revisit
## the spawn point, only the art itself and the impact-side direction).
const SOUL_BREAK_PROJ_SPAWN_OFFSET_X_PX := 12.0

## --- v17-fix's core bug fix stays (user reconfirms it worked: "「斜め
## 上へ飛んだ飛翔体が、命中時だけ横向きになる」という問題は消えました")
## — _soul_break_hit_dir() is still the ONE shared source every stage
## (flight, penetration, all 4 impact layers) reads. v18 changes WHAT
## that function points at, not the sharing mechanism itself: user report
## — "正しく角度を接続したのではなく、飛翔体の移動そのものを水平に変更
## して回避した状態です" (the raw enemy-center angle was apparently too
## shallow, ~10°, to visually read as "diagonal" once actually rendered).
## User spec section 4's own pseudocode biases the AIM point upward:
## "target_pos := enemy.global_position + Vector2(0, -enemy_height*0.12)".
## _soul_break_hit_target_pos() (below _soul_break_target_pos's own
## definition) is this offset point — used ONLY for the flight's own
## destination and for computing hit_dir/hit_angle, NEVER for where the
## impact-side VISUALS are centered (see section 7's own "貫通終了位置を
## 着弾演出の中心にせず、敵の胴体中央を破壊エフェクトの中心にしてくださ
## い" — the 4 impact layers below all anchor at the TRUE, un-offset
## _soul_break_target_pos instead).
##
## --- v19 STOP POINT (user report: "飛翔体が敵の左側へ到達したあとも移
## 動を続け、敵の身体をほぼ完全に通過してから消えています...攻撃が敵を
## すり抜けたように見えます"). Root cause: the flight's destination was
## the ENEMY CENTRE, but the destination positions the blade's ANCHOR,
## and this sprite's tip leads its anchor by ~135px — so by the time the
## anchor reached the centre the tip was already far out the enemy's back
## side. Fixed by solving for the ANCHOR position that puts the TIP at
## the requested bite depth (see _soul_break_flight_end_pos), computed
## from _boss_icon_rect rather than any fixed coordinate, so it adapts if
## the enemy's display size ever changes ("敵の大きさが変わっても対応で
## きるように、固定座標ではなく敵の表示範囲...から...計算してください").
##
## Distance from the blade's anchor to its own leading tip, along the
## blade's forward axis, in DRAW-RECT pixels. v20: scaled by the same
## factor as the canvas resize (135.0 * 254/200 = 171.45), since the tip
## sits at the same RELATIVE position (87.5% of rect width) on the
## unchanged shape.
const SOUL_BREAK_BLADE_TIP_OFFSET_PX := 171.45
## How far the tip bites into the enemy, as a fraction of the enemy's own
## displayed width, measured from its front (caster-facing) face — user
## spec: "飛翔体の先端が敵の正面側へ20～25%ほど食い込んだ瞬間を正式な着
## 弾地点に". 0.225 = the range's midpoint.
const SOUL_BREAK_ENEMY_BITE_FRAC := 0.225
## v19: the separate post-arrival penetration glide is REMOVED — user
## spec now wants the blade gone the instant its tip bites in ("その場で
## 飛翔体を消す...同じフレームで着弾X字を発生"), with the bite depth
## baked into where the flight ENDS instead of continuing past it. The
## constants are kept at 0 rather than deleted so the flight-draw's own
## end gate keeps its shape (penetration_end == FLIGHT_END).
const SOUL_BREAK_PENETRATION_SECONDS := 0.0
const SOUL_BREAK_PENETRATION_DIST_PX := 0.0
## Fraction of the enemy's own icon height the aim point is biased UPWARD
## from center — user spec's own exact figure (0.12), applied via
## BOSS_ICON_PX (this project's fixed boss-sprite display height, the
## closest available analogue to the user's "enemy_height").
const SOUL_BREAK_HIT_TARGET_UP_FRAC := 0.12

## --- V16 stage 1 (予備動作): a NEW small white soul-light at the sword
## tip, purely additive to the existing gather/core-hold/downswing (none
## of those functions/timings change) — user spec: "発射の約0.16秒前:
## ...剣先に小さな白い魂光を表示する。発射の約0.06秒前:...白い魂光を
## 1.25倍まで膨らませる". Both offsets are FROM SOUL_BREAK_LAUNCH_SECONDS
## (0.65), landing at 0.49/0.59 — both safely inside the existing,
## unchanged downswing window (0.50-0.65 is protected; this light simply
## overlays on top of it, one tick earlier than downswing itself starts,
## through launch).
const SOUL_BREAK_TIP_LIGHT_START_SECONDS := SOUL_BREAK_LAUNCH_SECONDS - 0.16  ## 0.49
const SOUL_BREAK_TIP_LIGHT_SWELL_SECONDS := SOUL_BREAK_LAUNCH_SECONDS - 0.06  ## 0.59
const SOUL_BREAK_TIP_LIGHT_RADIUS_PX := 4.0
const SOUL_BREAK_TIP_LIGHT_SWELL_SCALE := 1.25

## --- Launch-instant spark (user spec: "剣軌跡が消えるフレームで、剣先
## に小さな紫白の発射光を2フレーム表示する"). v16 retime: user spec now
## additionally requires this, the NEW launch arc, and the projectile to
## all begin from "同じ位置、同じフレームから" (the same place, the same
## frame) — moved from the slash trail's own end (0.75) to LAUNCH_SECONDS
## itself (0.65) so all 3 elements share one single trigger instant.
const SOUL_BREAK_MUZZLE_FLASH_START_SECONDS := SOUL_BREAK_LAUNCH_SECONDS  ## 0.65
const SOUL_BREAK_MUZZLE_FLASH_SECONDS := 0.10  ## 2 ticks @ 0.05s/tick = "2フレーム"
const SOUL_BREAK_MUZZLE_FLASH_END_SECONDS := \
	SOUL_BREAK_MUZZLE_FLASH_START_SECONDS + SOUL_BREAK_MUZZLE_FLASH_SECONDS  ## 0.75

## --- V16 stage 2 (発射): the recolored rapid_slash wave_a crescent
## (pixel-for-pixel recolor, see this block's own top-level doc comment)
## shown briefly at launch, anchored at the SAME origin point the
## projectile spawns from (user spec: "剣閃の終点と飛翔体の後端を完全に
## 接続する") so the 2 assets visibly share one seam instead of the
## projectile just popping into existence. User spec: "斬撃弧は2～3フレ
## ームで消す" — 0.12s ≈ 2.4 ticks, squarely in that range.
const SOUL_BREAK_LAUNCH_ARC_KEY := "soulbreak_launch_arc"
const SOUL_BREAK_LAUNCH_ARC_START_SECONDS := SOUL_BREAK_LAUNCH_SECONDS  ## 0.65
const SOUL_BREAK_LAUNCH_ARC_SECONDS := 0.12
const SOUL_BREAK_LAUNCH_ARC_END_SECONDS := \
	SOUL_BREAK_LAUNCH_ARC_START_SECONDS + SOUL_BREAK_LAUNCH_ARC_SECONDS  ## 0.77
const SOUL_BREAK_LAUNCH_ARC_DRAW_PX := 130.0

## --- V16 stage 3 (飛翔), v17-fix retuned: 2 afterimages of the SAME
## blade texture (user spec: "残像は最大2枚...現在位置に追従させず、生成
## 地点に固定...拡大しない...ブラーを使わない" — genuinely stamped/held
## state, not recomputed from the live position every frame, see _soul_
## break_afterimages). Refresh interval == the slot's own lifetime, so a
## fresh stamp appears the instant the previous one has fully faded
## (never overlapping 3+ deep). User spec's own exact alpha values (0.22/
## 0.10, down from the prior round's 0.32/0.14 — "半透明の紫が重なりすぎ
## て...ぼやけた塊に見えます") and a single shared lifetime picked from
## the middle of "0.08～0.12秒". No SCALE array any more (user spec:
## "拡大しない" — always drawn at native size, not merely "smaller than
## before" as the prior round's 0.92/0.84 was).
## v19: cut from 2 ghosts to exactly ONE (user spec: "残像は1つだけにし
## てください...同じ飛翔体を複数並べない") — the 2-ghost version was a
## direct cause of the "同じ形の飛翔体が3つ並ぶ / 本体と残像を区別できな
## い" report. All 3 arrays keep their Array[float] shape (the stamping/
## drawing loops iterate over _soul_break_afterimages, sized from these)
## so no call site needed restructuring — only the entry count changes.
## Values are the user's own: 16px behind (range "14～18px"), alpha 0.20
## (range "0.18～0.22"), lifetime 0.07s (range "0.06～0.08秒").
## Draw ORDER is what enforces "本体のz_indexは残像より必ず高く": this
## file has no per-element z_index (everything is one shared _draw()), so
## the dispatcher calls _draw_soul_break_afterimages BEFORE _draw_soul_
## break_flight — later draws land on top, giving the body strict
## priority over the ghost.
const SOUL_BREAK_AFTERIMAGE_DIST_PX: Array[float] = [16.0]
const SOUL_BREAK_AFTERIMAGE_ALPHA: Array[float] = [0.20]
const SOUL_BREAK_AFTERIMAGE_LIFETIME: Array[float] = [0.07]

## ================= V17-fix: impact rebuilt as 4 short hit_angle-aligned =====
## ================= code-drawn layers, replacing the single delivered ========
## ================= crescent (both direction-locked AND vector-smooth) =======
## v18 FULL RESTRUCTURE (user report: "現在の小さな白い菱形だけの着弾は
## 廃止してください" — v17-fix's own attempt at hit_angle-aligned code-
## drawn layers still under-delivered "「貫通した魂が割れる瞬間」がほと
## んど見えません"). New explicit A/B/C/D structure — user spec: "A.接触
## 閃光 B.魂の亀裂 C.欠けた魂の輪 D.破片", given as absolute (start,end)
## windows measured FROM SOUL_BREAK_CONTACT_SECONDS (evidenced by B's own
## end, 0.16, landing EXACTLY on C's own start, 0.16 — not a coincidence
## for a set of independent duration ranges). ALL 4 still rotate to the
## ONE shared hit_angle (_soul_break_hit_dir), and all 4 now anchor at
## the TRUE _soul_break_target_pos (not the penetration end point — see
## that function's own doc comment for the section-7 reversal). The old
## "layer B, white core diamond" from v17-fix has NO direct successor in
## this round's A/B/C/D list — replaced outright by the new branching
## crack (this round's own "B").
##
## v19 UNIFICATION (user spec section 2: "着弾処理を1つのイベントに統合
## ...飛翔体が消えてから着弾するまでの空白時間を完全に無くしてくださ
## い"). Previously CONTACT (blade arrival) and MAX_IMPACT (damage/flash/
## knockback/ring) were 0.16s apart — a visible dead gap. They are now
## the SAME instant, so blade-vanish, X-cross, enemy flash, hitstop,
## knockback, shake and damage all land on one tick. The separate
## cosmetic "contact pre-flash" block that used to fire at CONTACT is
## removed outright (it would now be a duplicate of the real hit).
const SOUL_BREAK_CONTACT_SECONDS := SOUL_BREAK_FLIGHT_END_SECONDS  ## 1.07
const SOUL_BREAK_MAX_IMPACT_SECONDS := SOUL_BREAK_CONTACT_SECONDS  ## 1.07 — same instant
const SOUL_BREAK_HIT_AT_SECONDS := SOUL_BREAK_MAX_IMPACT_SECONDS

## A. 接触閃光 — v19: fires AT contact (offset 0.0, was +0.04) so nothing
## precedes or lags the single unified arrival event.
const SOUL_BREAK_IMPACT_LINE_START_OFFSET := 0.0
const SOUL_BREAK_IMPACT_LINE_SECONDS := 0.06
const SOUL_BREAK_IMPACT_LINE_LENGTH_PX := 70.0
const SOUL_BREAK_IMPACT_LINE_WIDTH_PX := 3.0

## B. 壊れたX字 (v19: the branching crack is reshaped into the explicit
## BROKEN X the user has been calling "壊れたX字" — user spec section 3
## gives it exact numbers). Fires AT contact. Scale animates 0.75 ->
## 1.12 over GROW_SECONDS, then fades over FADE_SECONDS; total 0.18s,
## comfortably above the "最低0.10～0.14秒 / 30fps動画で3～4コマ" floor
## (0.18s = 5-6 frames at 30fps). Drawn in a TOP layer that runs AFTER
## the shared white screen flash — see _draw_soul_break_top_layer.
const SOUL_BREAK_IMPACT_CRACK_START_OFFSET := 0.0
const SOUL_BREAK_IMPACT_X_GROW_SECONDS := 0.08
const SOUL_BREAK_IMPACT_X_FADE_SECONDS := 0.10
const SOUL_BREAK_IMPACT_X_SECONDS := \
	SOUL_BREAK_IMPACT_X_GROW_SECONDS + SOUL_BREAK_IMPACT_X_FADE_SECONDS  ## 0.18
const SOUL_BREAK_IMPACT_X_SCALE_FROM := 0.75
const SOUL_BREAK_IMPACT_X_SCALE_TO := 1.12  ## middle of "1.10～1.15"
## Arm half-length at scale 1.0, and how far each arm sits from the
## flight axis (an X, not a plus: both arms straddle hit_angle). v20:
## user spec gives an absolute max-size target this round ("X字の最大サ
## イズ：横幅220～250px、高さ180～220px") — solved (not guessed) from the
## X's own geometry at its PEAK scale (SOUL_BREAK_IMPACT_X_SCALE_TO=1.12):
## bbox width = 2*ARM_PX*scale*cos(spread), height = 2*ARM_PX*scale*
## sin(spread); with spread=0.70 rad unchanged, solving width=235 (this
## range's midpoint) gives ARM_PX=137.0, which independently lands height
## at 197px — inside 180-220 without needing its own separate solve, since
## the existing spread angle already sits close to this target's own
## aspect ratio (tan(0.70)=0.84 vs the target's 200/235=0.85).
const SOUL_BREAK_IMPACT_X_ARM_PX := 137.0
const SOUL_BREAK_IMPACT_X_ARM_SPREAD_RAD := 0.70  ## ~40 degrees each side

## C. 欠けた魂の輪 — v19: also starts AT contact (was +0.16).
const SOUL_BREAK_IMPACT_RING_SECONDS := 0.14
const SOUL_BREAK_IMPACT_RING_PEAK_DIAMETER_PX := 128.0  ## middle of 110-145
const SOUL_BREAK_IMPACT_RING_GAP_COUNT := 5  ## middle of "4～6個"

## D. 破片 (user spec: "紫白の角張った魂片を8～12個...hit_dirの前方に多
## く...後方にも少量だけ...丸いパーティクルは禁止") — v19: trails the
## unified impact by a short beat, so debris still reads as thrown OUT of
## the burst rather than appearing simultaneously with it.
const SOUL_BREAK_IMPACT_FRAGMENT_START_OFFSET_FROM_MAX := 0.04
## v20: user spec narrows the count to "6～8個" (down from v19's "8～12
## 個") — 7, that range's midpoint.
const SOUL_BREAK_IMPACT_FRAGMENT_COUNT := 7
const SOUL_BREAK_IMPACT_FRAGMENT_SECONDS := 0.12  ## 0.32-0.20
const SOUL_BREAK_IMPACT_FRAGMENT_SPREAD_PX := 42.0
const SOUL_BREAK_IMPACT_FRAGMENT_DRIFT_PX := 16.0
## Half-angle of the forward cone most fragments scatter into, centered
## on hit_dir (user spec: "hit_dirの前方に多く飛ばす" — most, not all).
const SOUL_BREAK_IMPACT_FRAGMENT_CONE_RAD := 1.05  ## ~60 degrees each side
## Fraction of the FRAGMENT_COUNT that scatter backward instead (user
## spec: "後方にも少量だけ飛ばす" — a small minority).
const SOUL_BREAK_IMPACT_FRAGMENT_BACKWARD_FRAC := 0.2

## --- Hit-feel: mostly UNCHANGED — user spec locks "敵の白フラッシュ、
## 敵のノックバックと倒れ方、ヒットストップ、画面揺れ" explicitly this
## round (the enemy's own local flash/knockback/hitstop/shake all still
## borrow rapid_slash's exact numbers, byte-identical). The ONE exception
## user spec section 8 explicitly asks to change is the shared FULL-VIEW
## screen flash (a different mechanic from the enemy's own local flash) —
## see SOUL_BREAK_SCREEN_FLASH_ALPHA below.
## v19: user spec section 3 restates the range as "最大alpha：0.35～0.45"
## while ALSO reporting the flash currently hides the X-cross. Those pull
## opposite ways (the previous value, 0.26, was already below the new
## range's floor), so the flash alpha is set to the range's LOW end and
## the actual visibility fix is structural instead: the X-cross now draws
## in a layer that runs AFTER the flash rect (see _draw_soul_break_top_
## layer), which is the "X字をより上のCanvasLayerへ置く" option the spec
## itself offers as the preferred alternative to dimming.
## v20: this round's own range (0.18-0.22) is entirely BELOW v19's
## (0.35-0.45), so it simply wins outright, no conflict to resolve — the
## X-cross's own visibility comes from the structural draw-order fix
## below (_draw_soul_break_top_layer, running after the flash rect), not
## from the flash being dim, so lowering the alpha further doesn't reopen
## that fixed bug.
const SOUL_BREAK_SCREEN_FLASH_ALPHA := 0.20
## User spec also asks for "白フラッシュは0.05秒程度" — the SHARED
## _battle_screen_flash_t mechanic (used by every skill, not soul_break-
## specific) already hardcodes exactly 1 tick (0.05s) of visibility
## regardless of what's passed in, which already satisfies this without
## needing to touch that shared mechanic at all — only the ALPHA changes.
##
## Hitstop: user spec step 2, "0.05～0.06秒の短いヒットストップ" — a
## dedicated soul_break value (this round's own midpoint), no longer
## borrowing RAPID_SLASH_HITSTOP_SECONDS (0.08s, outside this round's
## target range). Section 7's "ヒットストップは現在の処理を維持してく
## ださい" is read as "reuse the existing _fire_battle_anim_hit call, not
## a separate mechanism" — the same established pattern EOS_BURST_
## HITSTOP_SECONDS already uses to override the shared default — not as
## "keep the old numeric value", which would directly contradict step 2's
## own explicit range.
const SOUL_BREAK_HITSTOP_SECONDS := 0.055

## --- Return: the PATTERN stays locked (user spec: "攻撃後の帰還処理"
## — hold until max impact, then return during the aftermath), but the
## absolute VALUES cascade from the new MAX_IMPACT_SECONDS above rather
## than staying pinned to the prior round's numbers, since this round's
## lock list no longer separately pins "発射から命中までの時間".
const SOUL_BREAK_RETURN_START_SECONDS := SOUL_BREAK_MAX_IMPACT_SECONDS  ## 1.07
const SOUL_BREAK_RETURN_END_SECONDS := SOUL_BREAK_RETURN_START_SECONDS + 0.25  ## 1.32

## --- SFX ("soulbreak_sfx_v1_ClaudeCode" delivery). One AudioStreamPlayer
## per WAV, exactly the pattern _build_rapid_slash_sfx/_build_healing_sfx
## already established — which also satisfies the README's own "同一フレ
## ームで開始するcrossとimpactは、別々のAudioStreamPlayerで重ねて再生し
## てください" for free, since no two cues ever share a channel.
## The delivered soulbreak_full_preview_v1.wav/.mp3 are audition-only
## ("確認用です") and are deliberately NOT copied into assets/.
const SOUL_BREAK_SFX_PATHS: Dictionary = {
	"move": "res://assets/audio/sfx/soulbreak_move.wav",
	"charge": "res://assets/audio/sfx/soulbreak_charge.wav",
	"launch": "res://assets/audio/sfx/soulbreak_launch.wav",
	"flight": "res://assets/audio/sfx/soulbreak_flight.wav",
	"cross": "res://assets/audio/sfx/soulbreak_cross.wav",
	"impact": "res://assets/audio/sfx/soulbreak_impact.wav",
	"soul_tail": "res://assets/audio/sfx/soulbreak_soul_tail.wav",
}
## (key, act-relative second) cues, fired one-shot from _update_soul_
## break_state.
##
## MOST of the README's table lands exactly on this build's own visual
## events and is used verbatim: move 0.00 = act start; cross 1.07 =
## SOUL_BREAK_CONTACT_SECONDS; impact 1.075 = the same tick as contact;
## soul_tail 1.09 = contact + 0.02. charge 0.29 sits inside the existing
## shard-gather window (0.12-0.42) and conflicts with nothing, so it is
## kept literally too.
##
## The TWO exceptions are launch (README 0.89) and flight (0.91). This
## build releases the blade at SOUL_BREAK_LAUNCH_SECONDS = 0.65, so the
## literal times would play the "剣を振り下ろして魂刃を放つ瞬間" sound
## 0.24s AFTER the sword has already released — the README's own stated
## purpose for that cue contradicts its own number. Both are therefore
## anchored to the real launch event instead, preserving the README's own
## 0.02s launch->flight spacing. Reported to the user rather than applied
## silently; if the intent really was a deliberately late launch sound,
## these two entries are the only thing to change back.
const SOUL_BREAK_SFX_CUES: Array[Array] = [
	["move", 0.0],
	["charge", 0.29],
	["launch", SOUL_BREAK_LAUNCH_SECONDS],           ## README 0.89 -> 0.65 (real launch)
	["flight", SOUL_BREAK_LAUNCH_SECONDS + 0.02],    ## README 0.91 -> 0.67 (same +0.02 spacing)
	["cross", SOUL_BREAK_CONTACT_SECONDS],           ## README 1.07 (exact match)
	["impact", SOUL_BREAK_CONTACT_SECONDS],          ## README 1.075 (same tick)
	["soul_tail", SOUL_BREAK_CONTACT_SECONDS + 0.02],## README 1.09 (exact match)
]

## --- Actor frame timeline (absolute seconds from act start), v10 retime.
## Frames 0-2 (windup, reaching the "頭上の構え" peak by 0.10s) are byte-
## for-byte unchanged from every prior version; frame 2 holds through the
## shard-convergence + core-hold span (until SOUL_BREAK_DOWNSWING_START_
## SECONDS) — this same held pose IS the downswing's own "頭上の構え" 1st
## pose, no separate breakpoint needed for it. Frames 3-5 play poses 2-4
## of the downswing (顔の横45度→胸の前水平→右下, user spec's own 4-stage
## list). LAUNCH fires the instant frame 5 is reached (no gap). Frames 6-7
## (the shared clip's own recovery) now play AFTER the post-launch hold —
## a v10 reordering from v9, where they played BEFORE launch instead —
## and hold at 7 for the remaining flight/impact/return. attack_minion_N's
## own 8-frame structure (0-2 windup, ~4 hit/slash-effect-baked-in, 5-7
## recovery, per this file's own established convention for the clip) is
## what every breakpoint below maps onto; no new art was needed.
const SOUL_BREAK_ACTOR_FRAMES: Array[Array] = [
	[0.00, 0], [0.05, 1], [0.10, 2],
	[0.55, 3], [0.60, 4], [0.65, 5],  ## downswing poses 2-4 (=DOWNSWING_START..+3*SEGMENT)
	[0.77, 6], [0.83, 7],  ## v18: recovery, AFTER the new flat 0.12s post-launch hold
]


## ================= エオスバースト (Eos Burst) v2 =======================
## "UNDERDESK_EOS_BURST_CLAUDE_CODE_v1" delivery. Replaces the generic
## ranged-skill path this skill used to share (a plain cast + _launch_
## battle_projectile shot) with a dedicated 4th skill block, same
## convention rapid_slash/healing/soul_break each established.
##
## v1 -> v2: v1 read `references/eos_burst_dragon_first_sequence_
## transparent.png` (a single fully-manifested dragon) and faded its alpha
## in over time. The package's own 01_CLAUDE_CODE_PROMPT.md, read in full
## this round, explicitly FORBIDS exactly that ("薄い完成形の竜全体を最初
## から置き、alphaだけを徐々に上げる" is in its own list of forbidden
## orderings) — the required staging is a piece-by-piece emergence through
## a fixed gate behind Sotiris's shoulder (snout+eye -> head+horns ->
## neck+mane -> upper body+first coil -> lower coil+tail -> full), with
## every visible part already solid/opaque, never a fade. The package's
## own `references/summon_frames/01_brace.png`..`08_full_dragon_ready.png`
## are that exact 8-stage progression (confirmed 1:1 against 01_CLAUDE_
## CODE_PROMPT.md's own 8-item list by content), so this version extracts
## all 8 (masking Sotiris's own silhouette out of each by luminance, not a
## fixed rect — see extract_summon_stages2.gd; a first rect-based attempt
## smeared his drop-shadow into a solid dark box, caught via contact-sheet
## review before ever installing it) and switches between them as discrete
## frames (the package explicitly permits "段階スプライトを切り替える" as
## an alternative to a literal gate clip/mask), never fading any of them.
##
## The package's own mandatory order (00_README + 01_PROMPT): summon the
## dragon AT THE ORIGINAL POSITION -> hold it fully manifested -> dash to
## the enemy WITH the dragon still visible -> only then thrust and fire
## the beam -> impact -> dragon collapses -> return. Explicitly forbidden:
## summoning after moving, dashing with the dragon hidden, firing the beam
## while approaching, firing from the home position, or overlapping the
## enemy.
##
## Character handling follows the package's hard constraints ("必殺技専用
## の大きなソティリス画像を新規表示しないでください...scaleを拡大・縮小
## する[禁止]"): this skill plays the SHARED attack_minion_N clip at the
## SAME PARTY_ICON_PX box every normal attack uses — NOT the 96px
## SKILL_ACTOR_DRAW_SIZE box the other skills' own skill_minion_* clips
## get — so the on-screen size is byte-identical to idle. This is exactly
## the precedent rapid_slash set when it dropped its own dedicated clip.
## Movement is a draw-time x_offset (see _eos_burst_advance_offset_px),
## so _battle_anim_pos/feet_y are never touched and the return lands on
## the origin by construction, satisfying the package's "開始時と帰還後
## の足裏Y差：1px以内 / X座標差：1px以内".
const EOS_BURST_SKILL_ID := "skill_eos_burst"
## 「タメ延長 + 専用SE」(2026-08-06) — 4つのオリジナルSE(48kHz/stereo/PCM
## WAV、風・炎・圧力・低いエネルギー・重い爆発を中心に、動物の咆哮や本編
## 音源は不使用)。rapid_slash/healing/soul_breakと同じ命名規約
## (`res://assets/audio/sfx/`配下、機能名のみ、配信物の"_v1"サフィックスは
## 落とす)で配置。同梱の`eos_burst_audio_preview_v1.wav`(4音を連結した
## 確認用プレビュー)は「ゲームへ1本の音として実装する用途ではない」との
## 明記どおりコピーしていない。
## 「Aura density + audio polish v2」(2026-08-06) — `charge`(=風切り/ライザー、
## ユーザーが気に入っているため据え置き)はそのまま、新規`aura_core`(オーラ
## そのものの低い脈動・圧力)を追加。`dash`は同じキー・同じ再生イベントの
## ままファイルだけを新しいクリーンなwhooshへ差し替え(旧ザーザー音は
## `eosburst_dash_v1.wav`として残置、コードからは未参照)。
## 「Colossal impact + aura-dragon roar」(2026-08-06、同日追加ラウンド) —
## 新規`roar`(竜ではなくソティリスのオーラの咆哮、approach開始と完全同時)
## を追加。`impact`は同じキー・同じ再生イベントのままファイルだけをより
## 重厚な新爆発音へ差し替え(旧爆発音は`eosburst_impact_v1.wav`として残置)。
## roar/impactは元々別々のAudioStreamPlayer(このdict自体がkeyごとに1台
## 生成する設計)を持つため、「両者は絶対に重ねる、片方が片方を止めない」
## というREADME要求は新しい配線を追加せず構造的に満たされる。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い
## `dragon_form`(竜出現音)・`roar`(竜の咆哮)の2キーを削除した。README
## 「竜専用の"roar"SFXが、キャストの一連の流れの中で1回も再生されないこと」
## を、トリガー呼び出し自体を撤去することで満たす(合格条件そのもの)。
## 実ファイル(`eosburst_dragon_form.wav`/`eosburst_roar.wav`)は削除しない、
## 既定方針どおり。残る4キーの再生イベント・タイミング・音量は無改修。
const EOS_BURST_SFX_PATHS: Dictionary = {
	"charge": "res://assets/audio/sfx/eosburst_charge.wav",
	"aura_core": "res://assets/audio/sfx/eosburst_aura_core.wav",
	"dash": "res://assets/audio/sfx/eosburst_dash.wav",
	"impact": "res://assets/audio/sfx/eosburst_impact.wav",
}
## 「Professional Mix / Impact Polish v1」(2026-08-07) — README「Impact >
## roar/dash > aura/charge」の階層をbus単位で実現するため、6キーを3つの
## 専用bus(`EosBuild`/`EosRelease`/`EosImpact`)へ割り振る対応表。
## `EosBuild`=charge/body aura/dragon-forming texture、`EosRelease`=clean
## dash whoosh+dragon roar、`EosImpact`=巨大爆発——README §Aの役割分担
## そのまま。既存bus構成には専用busが1つも無かった(`AudioServer.bus_count
## == 1`、Masterのみ、grep監査でも確認済み)ため、`_ensure_eos_burst_audio_
## buses()`が起動時にこの3busを新設する(既存busの再利用は不可能だった、
## と明示的に確認した上での新設)。
const EOS_BURST_SFX_BUS: Dictionary = {
	"charge": "EosBuild",
	"aura_core": "EosBuild",
	"dash": "EosRelease",
	"impact": "EosImpact",
}
## 「grounded dragon + continuous motion + scream roar v6」(2026-08-07) —
## README「横突進開始で1回だけ再生、初期値はvolume_db=+1.0dB...着弾前に
## 明確に聞かせるためで、着弾後の爆発より大きくするためではない」。roar v2
## の-2dB(2ラウンド前に撤回)・v3〜v5の0dB(直近2ラウンド)からの3代目の
## 変更——毎回「その回の素材が指定するdB」をそのまま反映するだけの
## エントリで、比較・累積のような特別な計算は行わない。
## 「Professional Mix / Impact Polish v1」(2026-08-07) — 「咆哮を『主音』
## から『竜の質感』へ1段下げる...現在の+1.0dB再生をやめ、volume_db=-3.0dB
## を開始値にする。pitch shift/retrigger/duplicate layeringは禁止」——
## エントリの値を1.0→-3.0へ更新するだけ(トリガー箇所・再生イベント自体は
## 無改修、旧roarを重ねる新しい再生経路も追加していない)。
## 「Unified Assault Rig + Audio v1」(2026-08-08) — README §B「charge:
## eos_charge_build_v1.wavは-4dB開始、new resonanceは-1dB開始」「dash:
## -1.5dB開始」「release: dragon cryは-2.5dB開始」に合わせて4キー分を
## 追加/更新。`charge`(=`eosburst_charge.wav`、中身は無改修のまま`eos_
## charge_build_v1.wav`を維持)・`dash`(=クリーンなwhoosh、ファイルも
## 無改修)は今回初めてエントリを追加(旧・両方とも既定の0dBのままだった)。
## `aura_core`は物理ファイル自体を`eos_charge_resonance_v1.wav`へ差し替え
## た(旧`eos_aura_core_v2.wav`由来の内容は`eosburst_aura_core_v1.wav`
## として残置、コードからは未参照——「旧aura_coreをEos経路から外す」を
## キーを消すのではなく同じキーの中身を差し替えることで満たした、SHA256
## で新素材と一致することを確認済み)。`roar`もファイルを`eos_dragon_cry_
## v8_hybrid.wav`へ差し替え(旧v6の内容は`eosburst_roar_v6.wav`として
## 残置)、dBだけ-3.0→-2.5へ更新——「v3〜v6を別playerで重ねない」は元々
## key毎に専用playerを1台持つ設計(このdict自体がkeyごとに1台生成)のため
## 構造的に満たされる。`dragon_form`(REVEAL_START同期の竜出現音)・
## `impact`(巨大爆発音)は今回のREADMEに変更の言及が無いため無改修。
const EOS_BURST_SFX_VOLUME_DB: Dictionary = {
	"charge": -4.0,
	"aura_core": -1.0,
	"dash": -1.5,
}

## v3 -> v4 (this round, "V20緊急復元"): v3's canvas_item-shader dissolve
## reveal was reported as a near-instant 1-frame pop in actual gameplay
## (not the smooth dissolve headless testing's own math confirmed) — the
## most likely cause is CanvasItem.material not applying per sub-draw-call
## the way v3 assumed (swapping `material` between draw_texture_rect calls
## within one _draw() and expecting it scoped to just that one call was
## never actually verified against real rendering, only against headless
## dummy-renderer math). v3's 3-layer additive-blend beam was ALSO
## reported broken ("黄白色の硬い長方形...先端と根元が四角い"). The
## user's own explicit instruction this round: no shader, no dissolve, no
## additive-material beam — go back to what is known to have worked
## (v1's own texture-stretch beam + star impact + 8-stage timeline shape)
## and layer in ONLY 2 new things using this file's own PROVEN technique
## (draw_texture_rect's own `modulate` alpha parameter + rect-size
## scaling, driven by `elapsed` — the exact same approach every other
## working VFX element in this file already uses, never a real Tween node
## and never a shader): (1) the dragon's reveal/dismiss becomes a plain
## scale+alpha+position ease instead of the v2 8-stage sprite switch OR
## the v3 shader dissolve, (2) the beam's own EXISTING texture-stretch
## draw stays visible for longer after the hit, with a gentle height
## pulse and a fade-out, rather than being replaced by new geometry.
##
## assets/shaders/eos_dragon_reveal.gdshader is DELETED (not left
## orphaned like v2's stage1-7 PNGs) — a shader built for one abandoned
## approach has no future reuse value, unlike an image asset.
## (This whole comment block's own v4-v7 "baked stage-frame" history is
## now itself superseded twice over — first by the SubViewport+shader
## system, then by 「召喚専用8コマ導入」's delivered 8-frame sheet — see
## that section below for the CURRENT approach. Kept only as far as the
## surrounding EOS_BURST_SKILL_ID/beam-timeline comments that are still
## live; git history has the full narrative if ever needed.)
## 「間違った竜素材を使わない」(2026-08-02、同日4ラウンド目) — 検証済み
## の正しい素材(assets/art/eos_dragon_pixel_v2.png、222x222)を基準に
## EYE_FRAC/MOUTH_FRACを再実測(PowerShell+System.Drawingでシアン系
## ピクセルの重心を実測——目box=x[145..175] y[45..65]で重心(163.6,54.3)
## →frac(0.737,0.245)、口(開いた顎内側のシアン発光)box=x[140..185]
## y[65..100]で重心(160.5,74.7)→frac(0.723,0.336)。4倍ズームクロップで
## 目視確認済み)。旧320x416画像基準の値(0.764,0.257)/(0.729,0.353)は
## 使用しない。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 「ソティリス背後の
## 竜は不要になったため、完全に削除する」。`EOS_BURST_DRAGON_EYE_FRAC`/
## `_MOUTH_FRAC`(竜の目・口位置を示すfrac座標)は竜描画関数群だけが参照
## していたため、それらと一緒に完全削除した(grep確認済み、旧
## `EOS_BURST_DRAGON_MASTER_PATH`等の同種の竜専用定数群も後述の通り
## まとめて削除)。

## 「召喚専用8コマ導入」(2026-08-01) — ユーザーから正式な8コマ召喚
## シート(eos_dragon_emergence_8f_sheet.png、443x443/コマ、4列×2行、
## frames/eos_dragon_emergence_00~07.pngとして個別ファイルも同梱)が
## 納品され、それまでのコード生成の出現アニメーション一式(「竜出現方向
## の修正」で作ったDragonEmergenceOrigin+3制御点bezier+head/neck/body/
## tail_offset_pxのシェーダーブレンド、および「ラピッドスラッシュ同等の
## 完成度」修正のpath_mask_texベースreveal_threshold)を完全に撤去した。
## ユーザー指摘: 「頭の移動中にscaleが変化し、その後に首・胴の完成画像が
## 大きな塊で追加されるため、自然な生物の動きにはならない」。画像側で
## 既に「発生点→頭→首→胴→尾→完成」の流れができているため、コード側は
## 単純に「どのコマを、どの時刻に、固定位置で見せるか」だけを担当する
## ——召喚中のSprite全体のposition/scale/rotation/alphaは一切Tweenしない
## (ユーザー明示指示)。SubViewport+MeshInstance2D+カスタムシェーダー
## (eos_dragon_dissolve.gdshader)による前回までの実装は全廃し、他の
## 全キャラモーション(attack_minion_N等)と同じ「_eos_burst_texture()で
## 個別PNGを直接ロードしdraw_texture_rectで描く」というこのファイル内で
## 最も確立された単純な方式に統一した。
## 「竜召喚演出の速度と実体化方法の再修正」(2026-08-01、同日中の追加
## 修正) — ユーザー報告: 「小さい完成済みの竜頭が足元に出現し、頭が上へ
## 移動しながら巨大化する」。直前ラウンドの8コマcelアニメーション(各
## フレーム自身に竜の絵が段々大きく描かれている)を同じ固定rectへ引き
## 伸ばして表示していたため、コード側は一切scale/positionをtweenして
## いなくても、絵の中身が育っていく都合で「拡大しているように見える」
## 結果になっていた。今回はcelアニメーションを完全に放棄し、常に同じ
## 完成画像(frame7)を同じ固定rectへ、ピクセル単位のalphaだけで少しずつ
## 実体化させるディゾルブ方式に作り直した——position/scale/rotationは
## 一切animateしない(ユーザー明示要求)。
##
## ディゾルブの順序(尾→胴→首→頭)はgen_materialize_frames.gd(scratch
## script)でオフラインに焼き込んだ: frame7自身の不透明シルエットに対し
## geodesic BFS(目の位置近くをシードに最遠点=尾の先端を検出→その尾から
## 改めてBFSして「尾からの距離」を全ピクセルに割り当てる、旧dragon_
## reveal_path_mask.pngと同じ手法をframe7自身に再適用)で「尾から頭への
## 順序値」を算出し、ピクセルごとの実体化タイミングへ変換(尾/胴=0.28-
## 0.72秒、首/頭=0.72-0.90秒、smoothstepでease-in-out)——境界には白金/
## 水色の加算風グロー、ノイズジッターで直線的でない不規則な輪郭にした。
## N=16枚のPNGとして焼き出し、既存の_eos_burst_texture()で個別ロードする
## (このファイルの確立済み「1キー=1ファイル」パターンをそのまま踏襲——
## シェーダーは使わない。「シェーダーのmaterialは_draw()内のdraw_
## texture_rect呼び出し単位では正しく適用されない」というこのファイル
## 自身の過去の教訓(v3->v4 "V20緊急復元")があるため、今回もシェーダーに
## は戻さず静的PNGの差し替えだけで実現する設計を維持した)。
## frame N は assets/vfx/sotiris/eos_dragon_emergence_<N>.png (N=0..7、
## _eos_burst_texture()経由でロード) — 直前ラウンドから維持。今回は
## frame7("完成した竜")だけを引き続き参照する(ghost下地+materialize
## 完了後のhold描画)——frame0-6のcelアニメーション自体はもう再生しない。
## 「竜召喚演出をリリース品質へ作り直す」(release-quality rebuild) — this
## is NOT another layer of effects on top of the previous rounds' work; the
## old per-pixel dissolve (materialize/exit), the flat-color Line2D-style
## beam, and the disc-shaped impact texture are ALL retired (see the
## gen_chunk_frames.gd bake script and the draw functions below). A single
## named timeline (DragonSkillTimeline, expressed here the same way every
## other skill's own breakpoint table in this file already is — an ordered
## Array[Array] plus one lookup function, `_eos_burst_phase()`) is now the
## one source of truth for anticipation/materialize/charge/release/impact/
## vanish; every other constant in this block is chained from it, never a
## second independent clock. Full narrative history of every prior attempt
## (shader dissolve, 8-frame cel sheet, per-pixel noise dissolve, joint
## surge, etc.) is in git log / earlier CLAUDE.md entries, not repeated
## here — see "竜召喚演出をリリース品質へ作り直す" in CLAUDE.md for the
## rebuild's own changelog. EOS_BURST_DRAGON_EYE_FRAC/_MOUTH_FRAC are
## declared just above (with EOS_BURST_SKILL_ID), unchanged this round.
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## `EOS_BURST_DRAGON_EMERGENCE_KEY_PREFIX`(既に何ラウンドも前から死蔵、
## 呼び出し元ゼロだった歴史的な名前解決用の残置)・`EOS_BURST_DRAGON_
## MASTER_PATH`/`_MASTER_EXPECTED_SIZE`(専用ローダー`_eos_burst_dragon_
## master_texture()`もろとも呼び出し元ゼロだった、これも既に死蔵)を
## まとめて削除した。実ファイル(`eos_dragon_pixel_v2.png`等)は削除しない、
## 既定方針どおり。

## --- Master timeline. 「エオスバースト召喚を最初の構想へ戻す」
## (2026-08-04) — 直近2ラウンド(出現/消滅のリビルド)で確立した「単一
## テクスチャのalpha/色modulateだけで表現する」手法は消滅側では正しかっ
## たが、出現側については誤りだったと判明した。ユーザーの本来の構想は、
## 完成済み1枚絵をフェードさせることではなく、実際に頭→首→胴→尾と身体
## そのものが増えていく8枚の絵(セルアニメーション)を順番に見せること
## だった。既に`assets/vfx/sotiris/eos_dragon_emergence_0..7.png`として
## プロジェクト内に格納済みの8コマ(「召喚専用8コマ導入」ラウンドで一度
## 使われたが、「小さい完成竜が足元で拡大する」という別の実装上の不具合
## により後続ラウンドでalphaディゾルブへ置き換えられ、以来死蔵されて
## いた)を今回1枚ずつ目視確認——frame0-1=火花のみ(竜の形はまだ無い)、
## frame2=頭部が明瞭に出現、frame3=頭+首+胴体の一部、frame4-6=S字の胴体
## が徐々に巻いて完成へ近づく、frame7=完全体——正しく「頭→首→胴→尾」の
## 段階的増加を描いた素材であり、以前の不具合はこの絵自体の欠陥ではなく
## 実装(固定rectへのマッピング方法)側にあったと判断した。今回は絵の
## 切り貼り・部位マスクは一切行わず、8枚をそのまま時間順に切り替えるだけ
## (ユーザー自身の指示:「画像側で頭→首→胴→尾の流れができているため、
## コード側で部位を切り貼りしない」)——`_eos_burst_dragon_cel_frame_
## index`/`_draw_eos_burst_dragon`参照。
##
## タイムラインもユーザー自身の8段階の指定秒数をそのまま採用した——
## 「召喚が現在よりゆっくり見える」という明示的な合格条件のため、以前の
## 0.12秒(ANTICIPATION)+0.38秒(materialize)+0.04秒(flash)=0.54秒から、
## 0.34秒(第1-2段階、ソティリスのみ、竜はまだ見えない)+1.02秒(第3-7
## 段階、竜のセルアニメーション)+第8段階内のflashという、大幅に長い尺
## へ変更した。
##
## 「エオスバーストの最終仕上げ修正」(2026-08-05) §1: 溜めの間が
## 「暗いだけの空白」に見えるという報告に対し、WINDUPを0.34→0.42秒へ
## さらに延長し、既存の第1段階(剣を引く/腰を落とす)と第2段階(足元の
## 光輪/剣先への収束)の区切りを、ユーザー指定の「0.00-0.18秒: 構え」
## 「0.18-0.42秒: 足元の光輪+肩の光球+収束」に合わせて再配分した
## (中身の描画メカニズム自体は`_draw_eos_burst_windup_glow`のまま、
## 窓の秒数だけを変更)。
## 「12コマ方式への置き換え」— 「現在は同じ姿勢を停止しているだけで、
## タメモーションになっていません」との再指摘を受け、姿勢の切替を明確な
## 3段階へ再設計した。①PULLBACK: frame0(通常姿勢)→frame1
## (`attack_minion_0_f2`、剣を振り上げる動作)②CHARGE: frame1
## →frame2(`attack_minion_0_f3`、前脚を踏み込んだ低い構え)への遷移
## ③HOLD: frame2で完全静止。
## 「既存フレームに剣を引く動きがある場合は必ずそれを使ってください」—
## 納品済みの`skill_minion_0_eosburst*`(12コマ、専用モーション)も確認
## したが、frame1に竜と紛らわしい小さなシルエットが写り込んでおり
## ("竜はタメ終了まで表示しない"に抵触するリスク)、かつ「腰の後ろへ
## 剣を引く」動作そのものは既存の全アセットのどこにも存在しなかった
## (attack_minion_0の予備動作は振り上げ→踏み込みの2段、eosburst専用
## シートも振り上げ→ダッシュ→突き)——このため「剣を腰へ引く」の文言を
## 文字通り満たす画像は無いと判断し、既存のattack_minion_0(=このスキル
## 自身が元々使っている共有クリップ)の中で最も明確に異なる2つの予備動作
## コマ(振り上げ→踏み込み)を採用した。judgment callであることをここに
## 明記する。
## 「タメと出現の滑らかさだけを修正」(2026-08-05、同日2ラウンド目)—
## 「構えた直後に竜が出ている、タメが短すぎる」との報告に対し、ユーザー
## 指定の秒数(0.00-0.18/0.18-0.38/0.38-0.65)へ完全一致させた
## (0.2/0.25/0.2の旧内訳から再配分、合計0.65秒自体は不変)。姿勢の
## 切替ポイント(PULLBACK終了・PULLBACK+CHARGE終了)は`EOS_BURST_
## ACTOR_FRAMES`が両定数を参照しているため、この2つの値を変えるだけで
## 自動的に0.18秒・0.38秒へ再カスケードされる(手動再配線不要)。
## 「オーラのクオリティと着弾の迫力を修正」(2026-08-05、同日追加ラウンド)
## — タメ中の手続き型「トゲトゲした金色の塊」(_draw_eos_burst_windup_
## glow、削除済み)と旧4コマ手描きオーラ(sotiris_eos_aura_4f.png、削除
## 済み)を、新規6コマ手描き炎オーラ`eos_charge_aura_6f.png`(222×222×6)
## へ全面差し替えた。ユーザー指定の6コマ分の表示時間([0.08,0.08,0.09,
## 0.09,0.09,0.11])を単純合計すると0.54秒——「最終フレームの炎が上方向
## へ流れた直後に竜の頭が出現するよう接続する」を文字通り満たすため、
## この0.54秒を新しいWINDUP_SECONDS(=REVEAL_START)の実測根拠そのもの
## として採用した(旧HOLDの0.27秒を0.16秒へ短縮するだけで済み、PULLBACK/
## CHARGEの秒数・姿勢切替ポイントは無改修)。結果、竜の出現開始が旧0.65
## 秒→0.54秒(-0.11秒)前倒しになる——ダウンストリームの全タイミング
## (接近・突き・着弾)は全て単一の定数チェーンでこの新しいREVEAL_START
## から再カスケードされるため、相対的な長さ・構成は一切無改修のまま、
## 絶対時刻だけが一律0.11秒早まる。「攻撃タイミングは変更しない」の
## 対象はあくまで各段階の"長さ・構成"であり、タメの絵が変わったことに
## 伴うタメ自体の絶対長の変化は今回の明示指示("最終フレーム→竜出現の
## 直結")が求める直接の帰結と判断した。
## 「エオスバースト・プロフェッショナル・ポリッシュ」(2026-08-06) — 「0.85
## 秒のタメ全体で0→5へ徐々に成長させる、ループさせない」との明示指示に
## より、この配列を「elapsed=0からの一回再生テーブル」から「HOLD開始
## (=PULLBACK+CHARGE終了)からの一方向成長テーブル」へ意味を変更した
## (新しい定数を二重に作らず、既存の同じ役割の定数の値を調整——README表
## の秒数[0.13,0.14,0.14,0.15,0.15,0.14]をそのまま採用、合計0.85秒は
## `EOS_BURST_SUMMON_HOLD_SECONDS`と完全一致し、frame5への到達が
## `EOS_BURST_REVEAL_START_SECONDS`ちょうどになるよう設計されている)。
## HOLD開始前(PULLBACK+CHARGE中、elapsed<成長開始点)はframe0を静止
## 保持——「タメ開始と同じタイミングでaura frame0を出す」を、この最初の
## テーブルエントリがそのまま延長されるだけの形で満たす(継ぎ目なし)。
## ループ機構(旧`EOS_BURST_CHARGE_AURA_LOOP_FRAMES`/`_LOOP_STEP_SECONDS`)
## は「オーラの6コマをループさせず一方向に成長させる」との明示指示により
## 完全に撤去した——呼び出し元が無くなったため削除(この2定数はコードで
## あって画像アセットではないため、ファイルの「アセットは消さない」規約の
## 対象外と判断)。
## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — README「現在の炎型
## オーラがソティリスの必殺技として格好よく見えない」——旧`charge_aura_
## anchored`(炎、4コマ)を完全に撤去し、新規`solar_sword_aura_v13`(白金の
## 縦方向の剣光・青金の足元リング・光リボン・上昇粒子、人物を含まない
## 透明素材)へ全面差し替え。旧`assets/eos_charge_aura_4f.png`/`frames/
## charge_aura_anchored/`はactive参照から外す(実ファイルは削除しない、
## 既定方針どおり)。位置は引き続き共通足元anchor(`_eos_burst_rear_
## anchor_pos`、Sotirisと同じ足元Node2Dの子という要求を、実ノード階層を
## 持たないこのアーキテクチャでは「同じ関数を同じelapsedで呼ぶ」ことで
## 満たす、このsaga確立済みのパターン)+固定オフセット——README
## 「192×224セルの水平中心X=96を人物足元X=0へ、素材の接地下端Y=220を
## 人物足元Y=0へ合わせる」を`centered=false`/`offset=ZERO`相当の単純な
## `anchor + LOCAL_POSITION`だけで満たす(全4コマの可視下端Y=220・alpha
## 重心X=96±0.5pxで統一済みの新素材のため、per-frame補正は不要)。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — README
## 「維持するもの: v13の新オーラ...と現在の位置・時間」——絵・タイミング
## とも無改修、パスだけv14コピー先へ切替(SHA256一致確認済み)。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — README「v14から
## 変更しないもの: v13の白金剣光オーラ」——絵・タイミングとも無改修、
## パスだけv15コピー先へ切替。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — README「維持するもの: 白金
## 剣光オーラ」——絵・タイミングとも無改修、パスだけv16コピー先へ切替。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — README「②オーラが
## ソティリスより右へずれている」——AURA_ALIGNMENT_V19.tsvの実測(4コマとも
## alpha重心X≈96px、192pxキャンバスの中央付近)により、旧`(-96,-220)`が
## ほぼ親原点の真上を指していたことを確認。最新の見た目に合わせ全コマ
## 一律16px左の`(-112,-220)`へ固定——`centered=false`のまま毎描画フレーム
## この同じ値を再代入する(親のTween・sprite幅・pivot差による横ドリフトを
## 構造的に排除、参照実装`play_smooth_locked_aura`が"reapply every draw"と
## 明記する設計をそのまま踏襲)。パスもv19コピー先へ切替。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — 絵は無改修
## (PRESERVED_ASSET_SHA256_V20.tsvでv19と同一4ファイルであることを確認済み)、
## パスだけv20コピー先へ切替(タイミング・gammaクロスフェードの変更はコード
## 側のみ)。
const EOS_BURST_SOLAR_AURA_DIR := "res://assets/vfx/eos_burst/v20/frames/solar_sword_aura_v13/aura_"
const EOS_BURST_SOLAR_AURA_FRAME_COUNT := 4
const EOS_BURST_SOLAR_AURA_FRAME_SIZE := Vector2(192.0, 224.0)
const EOS_BURST_SOLAR_AURA_LOCAL_POSITION := Vector2(-112.0, -220.0)
## 「①一つ一つの姿勢とVFXのつながりが滑らかでなく...Timer単位で切り替わり」
## ——旧・discrete-jumpの1回再生テーブル(`_eos_burst_frame_index_from_
## table`消費)を、TRANSITION_TIMES_V19.tsv「aura 0〜3」が指定する
## 00→01→02→03→02の巡回(5要素、4遷移×0.180秒均等)へのA/Bクロスフェード
## へ全面差し替えた——「最大出力(frame3)へ到達したら一度frame2へ戻ってから
## フェードする」という、旧FADE_FRAME_INDEXが暗黙に前提としていた挙動を
## 遷移列自体に明示的に組み込んだ形。
const EOS_BURST_SOLAR_AURA_ORDER: Array[int] = [0, 1, 2, 3, 2]
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) —
## TRANSITION_TIMES_V20.tsv「aura 0〜3」——4遷移×0.180秒→4遷移×0.200秒
## (合計0.720→0.800秒)へ更新。
const EOS_BURST_SOLAR_AURA_TRANSITION_SECONDS := 0.200
const EOS_BURST_SOLAR_AURA_CROSSFADE_SECONDS := 0.800  ## 4遷移×0.200秒
## README「alphaは0.82(最大出力に統一)」——参照実装`AURA_MAX_ALPHA`は
## 前半/後半の区別を廃止し、巡回中は常に同じ最大値を使う(旧ALPHA_LOW/
## _HIGHの2値制は撤去)。
const EOS_BURST_SOLAR_AURA_MAX_ALPHA := 0.82
## TIMELINE_V19.csv「0.720,1.020,0.300,aura,同じ位置でFadeOut...downslash
## frame6と0.120s」——旧0.20秒から0.30秒へ延長。巡回完了(frame2)から直接
## フェードへ入る(旧・巡回完了→APPROACH_ENDまで静止保持、という中間段階は
## 撤去——巡回自体の合計0.720秒がそのままフェード開始点になる)。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「その後0.320秒FadeOutします。合計1.120秒なのでreleaseと同時に終了し、
## frame6とは0.110秒重なります」——0.30→0.32秒へ更新。
const EOS_BURST_SOLAR_AURA_FADE_SECONDS := 0.32
const EOS_BURST_SOLAR_AURA_FADE_FRAME_INDEX := 2
const EOS_BURST_SOLAR_AURA_VISIBLE_START_SECONDS := EOS_BURST_APPROACH_START_SECONDS  ## 0.08
const EOS_BURST_SOLAR_AURA_VISIBLE_END_SECONDS := \
	EOS_BURST_SOLAR_AURA_VISIBLE_START_SECONDS + EOS_BURST_SOLAR_AURA_CROSSFADE_SECONDS \
		+ EOS_BURST_SOLAR_AURA_FADE_SECONDS  ## 1.20(=start+1.120、SLASH_STARTとちょうど一致)
## 「エオスバースト演出全面刷新」(2026-08-11) — 崩壊:スターレイル版セイバー
## の必殺技構成(剣へ力を集める→キャラクターの見せ場(漫画カットイン)→
## 一振り→巨大な光の奔流)を参考に、UNDERDESK独自の演出へ全面再構築した。
## 最大の変更点: ①ソティリスと竜が敵まで別々に突進する処理を撤去し、
## ソティリスは元の位置付近(前進20-30px程度)で光を放つ形にした
## (`_eos_burst_solve_approach_offset`参照)②タメと竜の頭出現の間に
## 漫画風カットイン(`EOS_CUTIN_*`、下記)を挿入③光撃を細い光槍から
## 太い光の奔流(fan beam)へ拡大し、竜をその内部の金色半透明シルエット
## として同じ基準(`_eos_burst_beam_state`)で追従させた④着弾後、竜を
## 出現シートの逆再生(尻尾→頭)で消す。既存の竜/オーラ/爆発/フラッシュ/
## 揺れ/ノックバック/ダメージ判定/SP消費/対象選択はすべて再利用・無改修
## (呼び出しタイミングだけを新しいタイムラインへ再接続)。
## 「現行ソティリス維持版 v3」(2026-08-12) — 納品README「0.00〜0.12秒:
## 戦闘画面を暗くして入力停止。現在のソティリスはそのまま表示」に合わせ、
## PULLBACK単独をこのフェーズ全体(0.12秒)とした——ソティリスの姿勢自体は
## この間ずっとidle(frame0相当)のまま変化しない。CHARGEは0(この段階では
## ポーズ遷移が無い、次のオーラ+竜出現フェーズへ直結)。
## 「Slower + New Impact v4」(2026-08-12) — 「必殺技が速すぎる」ため全体を
## 4.48秒の固定タイムラインへ retiming。①暗転・入力停止(0.00〜0.18秒)
## の長さそのものをPULLBACKへ割り当てる——この間ソティリスの姿勢はidle
## のまま変化しない設計は無改修。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — 「実際に動く区間へ
## 時間を再配分する」ためタイムライン全体を4.48秒→6.40秒へ再retiming。
## README「0.00〜0.25秒: 入力停止、画面を暗くする」——0.18→0.25秒。
const EOS_BURST_SUMMON_PULLBACK_SECONDS := 0.25
const EOS_BURST_SUMMON_CHARGE_SECONDS := 0.0
## 「ソティリスのタメ延長」(2026-08-06) — 「金色タメ状態→竜の頭が最初に
## 見え始めるまでの実時間を約0.85秒(許容0.80〜0.90秒)にする」との指定を
## 直接この定数へ反映(旧0.16、CHARGE_AURA_SECONDSからの残り時間として
## 導出していたderived formulaを撤去し、独立したリテラル値へ変更)。
## 「既存コードに同じ意味の定数がある場合、その値を調整する」との指示
## どおり、新規定数(`EOS_PRE_DRAGON_CHARGE_SEC`)は作らずこの値自体を
## 目標値へ合わせた——このHOLD窓こそが①タメ姿勢→②オーラが出る→
## ③追加で溜める→④竜の頭、の「③」に正確に対応する(PULLBACK=①終了、
## CHARGE=②のランプ、HOLD=③)。結果、WINDUP_SECONDS(=REVEAL_START)は
## 0.54→1.23秒(+0.69秒)——「約+0.60秒」からはやや超過するが、指示自身が
## 「最終的な実時間0.80〜0.90秒が唯一の基準」と明言しているため、델타の
## 近似より目標窓への一致を優先した(報告書に開示)。
## 「タメ延長 + 専用SE」(2026-08-06、同日追加ラウンド) — `EOS_PRE_DRAGON_
## CHARGE_SEC`をREADME指定どおり0.85→1.30へ再度延長(+0.45秒)。この定数が
## 引き続き`EOS_PRE_DRAGON_CHARGE_SEC`そのものであることは前ラウンドの
## コメントで確定済みのため、二重定義せずそのまま値だけを更新した。
## WINDUP_SECONDS(=REVEAL_START)は1.23→1.68秒(+0.45秒)——下流の全タイミング
## (竜出現・接近・突進・接触・大爆発)は既存の単一定数チェーンでこの新しい
## REVEAL_STARTから自動的に再カスケードされ、各フェーズ自身の内部相対長は
## 一切無改修のまま絶対時刻だけが一律+0.45秒後ろへずれる。
## 「現行ソティリス維持版 v3」(2026-08-12) — README「0.12〜0.55秒:
## eos_charge_aura_4f.pngとeos_dragon_emergence_8f.pngを人物の背面で
## 再生」——オーラ4コマ+竜出現8コマの**両方**をこの0.43秒の共有ウィンドウ
## 内で完結させる(前ラウンドの「カットイン前に頭だけ、閉じたら残りを
## 再生」という一時停止方式は、今回のREADMEが竜の出現をカットインより
## 前に完全に終える設計へ変更したため撤去——`_eos_burst_emerge_age`は
## 単純なelapsed-REVEAL_STARTへ差し戻す、下記参照)。
## 「Slower + New Impact v4」(2026-08-12) — README「0.18〜0.78秒: オーラと
## 背後の竜。前回より溜めを見せる」——0.43→0.60秒(+0.17秒)。オーラ4コマ・
## 竜出現8コマともこの共有ウィンドウ全体で1回だけ再生する設計は無改修
## (下のEOS_BURST_CHARGE_AURA_FRAME_DURATIONS/EOS_BURST_EMERGE_FRAME_
## DURATIONSの合計もこの値に合わせて再配分)。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「0.25〜1.15
## 秒: 溜めオーラと背後の竜を0.90秒かけて出現。竜を途中で横倒しにしない」
## ——0.60→0.90秒。「竜を横倒しにしない」は既存設計で既に満たされている
## ことをheadlessで確認済み(下記`_eos_burst_swing_pose_progress`の項参照
## ——アサルトシートへの切替自体はREVEAL_END直後だがframe0=直立姿勢の
## ままTHRUST_LUNGE_START(振り下ろし開始)まで一切進行せず、横倒しへの
## 変化は振り下ろしと完全に同期する。今回の変更でこの区間が伸びても
## この不変条件は無改修のまま保たれる)。
## 「HDDragonCharge v7」(2026-08-13) — README「0.25〜1.25秒: 高密度竜を
## 1.00秒で出現」——0.90→1.00秒(EOS_BURST_EMERGENCE_SECONDSと合わせて
## 更新、両者を独立に等しい値へ保つ既存の慣習を継続)。
const EOS_BURST_SUMMON_HOLD_SECONDS := 1.00
const EOS_BURST_WINDUP_SECONDS := \
	EOS_BURST_SUMMON_PULLBACK_SECONDS + EOS_BURST_SUMMON_CHARGE_SECONDS \
		+ EOS_BURST_SUMMON_HOLD_SECONDS  ## 1.15
const EOS_BURST_REVEAL_START_SECONDS := EOS_BURST_SUMMON_PULLBACK_SECONDS + EOS_BURST_SUMMON_CHARGE_SECONDS  ## 0.25、竜の出現が始まる
## --- EOS_CUTIN: 漫画風カットイン——「戦闘画面へ斬撃が切り込むように
## 表示する」の①斬撃線→②開く→③保持→④閉じる→⑤抜ける、という既存実装
## 済みの斜めクリッピング機構(`draw_polygon`によるパララログラム)は
## そのまま維持し、今回は①中身を納品の`eos_cutin_sword_closeup.png`
## 1枚だけに固定②タイミングをREADME「0.55〜0.95秒」(0.40秒)へ再スケール
## しただけ——旧5段階の秒数比率を保ったまま合計0.84秒→0.40秒へ比例縮小。
## 「Slower + New Impact v4」(2026-08-12) — README「0.78〜1.48秒:
## 0.10秒で入り、0.48秒静止、0.12秒で抜く」——「入り」(slash_in+open)/
## 「抜け」(close+slash_out)は前ラウンドの比率(約40:60/約50:50)を保った
## まま0.10秒・0.12秒へ再配分。合計0.70秒。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「1.15〜
## 2.10秒: 0.16秒で入り、0.61秒静止、0.18秒で抜く」——同じ比率(入り
## 約40:60/抜け50:50)のまま0.16秒・0.18秒へ再配分。合計0.95秒。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 「③カットイン中に
## 一度モーションが止まり、カットインだけを見せる直列処理になっている」
## ——旧「①斬撃線→②開く→③保持→④閉じる→⑤抜ける」という5段階の"帯の
## 開閉"ワイプ演出(`_eos_cutin_stage`、下記)を完全に撤去し、「帯は常に
## 全開のまま、alphaのenter/exitと横方向の連続移動だけで見せる」という
## 単純な新モデルへ全面差し替えた——参照実装`play_moving_cutin`が
## Enter0.140秒/Exit0.160秒のalphaフェードと"stationary Hold=0秒"しか
## 定義しておらず、帯の開閉に相当する形状パラメータが存在しないため。
## 「既存の斜めクリップ形状...は変更しません」は、斜め角度の計算基盤
## (`_eos_cutin_band_axes`/`_eos_cutin_quad`/screen-fixed UVマッピング)
## 自体はそのまま維持し、"その形状を時間とともにどう開閉させるか"という
## アニメーションのレイヤーだけを差し替える、という意味で解釈した。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「①カットイン画像が横へ移動している。本来はカットイン自体を完全固定
## し、その表示中にも背面のソティリスとオーラだけを進める」「時間は
## character local0.200秒開始、0.720秒継続。Enter alpha:0.100秒
## Smootherstep。Full alpha:0.480秒。Exit alpha:0.140秒Smootherstep。
## character local0.920秒で完全終了」——ENTER/EXIT/DURATIONを更新
## (0.140/0.160/0.800→0.100/0.140/0.720、hold=0.720-0.100-0.140=0.480秒は
## 既存の`_eos_cutin_alpha`が「enter/exit以外は1.0を返す」構造でそのまま
## 表現できるため専用定数は不要)。「禁止: v19の`play_moving_cutin`、
## viewport -11%→+9%、offset_x、cutin position lerp」——旧`EOS_CUTIN_
## START_VIEWPORT_RATIO`/`_END_VIEWPORT_RATIO`と`_eos_cutin_offset_x()`
## (下記)を完全に削除し、`_draw_eos_burst_cutin`は常に無改修の`view`
## そのものへ描く(帯の幾何・UVサンプリングとも移動しない)——「MotionAnchor、
## キャラクターRoot、world camera、screen shake対象の子にしない」は、
## そもそもこのファイルにCanvasLayer/実ノード階層が無く(単一の同期
## `_draw()`ディスパッチ、呼び出し順=描画順)、カットインの描画関数
## (`_draw_eos_burst_cutin`)は既存の`_battle_shake_offset()`が加算された
## 後の`view`(戦闘ワールド全体の共有揺れ)を一切経由しない別の描画経路
## (UI相当の最前面レイヤー、既存の呼び出し位置のまま無改修)であることを
## 確認済み——構造的に画面揺れ・MotionAnchorの影響を受けない。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「カット
## インはcharacter local0.300秒開始、1.050秒継続です。Enter alpha:0.140秒
## Smootherstep。Full:0.730秒。Exit alpha:0.180秒Smootherstep」。
const EOS_CUTIN_ENTER_SECONDS := 0.140
const EOS_CUTIN_EXIT_SECONDS := 0.180
const EOS_CUTIN_DURATION_SECONDS := 1.050
## 「その0.200秒後にplay_fixed_cutin(cutin_root)をawaitなしで開始」——
## v19の0.180秒から0.200秒へ更新。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README
## 「character local 0.300秒開始」——0.200→0.300。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — README「character
## local0.800秒、skill global0.920秒で開始します」——character frame times
## 延長(下記RAISE/SWING参照)に合わせ0.300→0.800。カットイン自体の
## duration/enter/exit(直上3定数)は「v21のまま」なので無改修。
const EOS_CUTIN_START_AFTER_APPROACH_SECONDS := 0.800
const EOS_CUTIN_START_SECONDS := \
	EOS_BURST_APPROACH_START_SECONDS + EOS_CUTIN_START_AFTER_APPROACH_SECONDS
const EOS_CUTIN_END_SECONDS := EOS_CUTIN_START_SECONDS + EOS_CUTIN_DURATION_SECONDS
## README「カットイン終了からreleaseまで可視ブリッジ0.200秒」——
## `EOS_BURST_SLASH_START_SECONDS`(release=frame7満alpha+grand00初表示の
## 瞬間)との差分として直接検証できる形で明示的に保持する(headless検証・
## 報告の両方で参照する named constant、値自体は上記2つの定数から自動的に
## 導出されるため、この定数自身はロジックに使わず確認専用)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「release
## local 1.800秒まで通常戦闘画面の可視bridge：0.450秒」——0.200→0.450。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — README「releaseまでの
## 可視charge bridge：1.110秒」——release local2.960秒(下記THRUST_LUNGE
## 参照)からCUTIN_END(=0.800+1.050=1.850)を引いた値と厳密一致。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — README
## 「visible charge bridge：1.230s(unchanged from v24)」——cutinのstart-
## after-approach/durationとも今回無改修(0.800/1.050、CUTIN_END=1.850は
## 不変)のため、新しいrelease local(3.080秒)からCUTIN_ENDを引いた値
## (1.230)だけが変化する。
const EOS_CUTIN_TO_RELEASE_VISIBLE_BRIDGE_SECONDS := 1.230
## パネルの見た目(画面比率ベース、固定pxだけに頼らない——画面サイズが
## 変わってもレイアウトが崩れないように)。
const EOS_CUTIN_ANGLE_RAD := -0.19  ## 左下から右上、約-11°
const EOS_CUTIN_BAND_HEIGHT_FRAC := 0.50  ## 全開時のパネル高さ(画面高さに対する比率)
const EOS_CUTIN_BORDER_GOLD_PX := 8.0  ## 白金色の太い縁(プレースホルダー限定、下記参照)
const EOS_CUTIN_BORDER_CYAN_PX := 3.0  ## 内側の細い水色の縁(プレースホルダー限定)
const EOS_CUTIN_TITLE_TEXT := "エオスバースト"
const EOS_CUTIN_TITLE_FONT_SIZE := 46
## 「現行ソティリス維持版 v3」(2026-08-12) — 納品された最終画像
## `eos_cutin_sword_closeup.png`(1152×648、画面と完全に同じ解像度)へ
## 差し替え。「前回の01・03・04・05・06・07の全画面イラストは使用しない
## ...カットイン画像はこの1枚だけ」——画面サイズと同一寸法のため、UV
## マッピングは(下記`_eos_cutin_quad`で)帯自身の座標系ではなく画面座標
## そのものへ変更した(画像が常に画面へ固定表示され、斜め窓だけが動く
## 正しい「ワイプ」になる、前回の帯基準UVは絵が伸縮して見える簡易実装
## だったため置き換えた)。旧`assets/vfx/sotiris/eos_cutin_final.png`
## (1920×640想定)は未参照のまま——今後another final imageに差し替える
## 場合はこのパスと`EOS_CUTIN_IMAGE_SIZE`を更新するだけでよい。
const EOS_CUTIN_FINAL_IMAGE_PATH := "res://assets/art/eos_cutin_sword_closeup.png"
const EOS_CUTIN_IMAGE_SIZE := Vector2(1152.0, 648.0)

## 「竜召喚モーションの最終構造修正」(2026-08-05、同日3ラウンド目) — 実写
## 確認で①依然「小さい完成画像をscaleで拡大して登場させる処理」に見える
## ②巨大な竜召喚の直後に単純な楕円光弾が胴体下部から飛び、召喚・攻撃・
## 着弾が別々の演出に見える、と報告された。§0の事前調査(position/scale/
## pivot_offset/transform/modulate.a/Tween/create_tweenをgrep)の結果、
## 竜のscaleを変更するコードはプロジェクト全体に一切存在しない
## (`EOS_BURST_DRAGON_SCALE`は定数0.85のまま、`create_tween`は0件)——
## 「ズームしているように見える」の実体はscale変更ではなく、wipe reveal
## そのものの性質(絵の不透明ピクセル範囲が尾の小さな領域から頭を含む
## 全範囲へ物理的に広がる)による視覚的錯覚と判断した。今回はこの錯覚を
## 構造的に断つため、①最終rect(position/scale)と完全に同一の薄い全身
## 輪郭を、竜本体が実体化し始める前から重ねて表示("最初から最終サイズが
## わかる")②進行方向を「尾→頭」(前ラウンド)から「下→上」(今回の明示
## 指定、`tools/gen_dragon_bottomup_frames.gd`でY座標ベース+低解像度
## ノイズによる不規則境界のディゾルブへ全面差し替え)③タイムラインを
## 0.86秒→0.62秒の5段階(footlight/tail_to_neck/head/flash/settle)へ
## 再構成——の3点を実施した。
##
## 累積マスクの生成は`tools/gen_dragon_bottomup_frames.gd`(scratch
## script、使用後削除)——frame7の不透明シルエットに対しY座標のみで
## base_order(下端=0で最初、上端=1で最後)を算出し、`FastNoiseLite`
## (低周波Perlin、frequency=0.012)を加算して境界を不規則化
## (`noisy_order = clamp(base_order + noise*0.09, 0, 1)`)。各フレームは
## frontier=reveal_tとの差分dから①d>+edge_half(未到達、透明)②|d|<=
## edge_half(境界帯、completeの元の色へ白金/水色の加算風グローをブレンド)
## ③d<-edge_half(通過済み、completeの元の色そのまま)を1回のループで
## 同時に計算——前ラウンドと同じ「輪郭のみ→内部塗りつぶし」に戻れない
## 設計を維持しつつ、基準軸だけをBFS距離場からY座標+ノイズへ変更した。
## 「エオスバーストを18:32版の自然な出現へ戻す」(2026-08-02、同日3
## ラウンド目) — ユーザーから、ここまでの複数ラウンドで積み重ねた修正が
## 「当初の理想から離れている」との明確な指摘。基準は過去の実機動画
## (UNDERDESK (DEBUG) 2026-08-01 18-32-39.mp4)——「竜を小さい状態から
## 拡大せず、最終サイズを固定したまま、薄い輪郭から金色とシアンの光が
## 満ちて竜が現れる」。git logはmain.gdへのeos_burst関連コミットが1件も
## 無いことを確認済み(このプロジェクトはセッション内の全作業が長期間
## 未コミットのまま)——コミット履歴からの復元は不可能と判断し、ユーザー
## 指定の仕様どおりゼロから再構成した。
## 前ラウンドまでの2速度ディゾルブ(尾→首→頭)+SETTLE小休止という構成を
## 撤去し、①単一速度の頭→尾の連続した流れ(「最初に頭部の薄い輪郭...
## そこから胴体、一本の尻尾へ光が流れる」、部位を別々に出さない)②
## 0.9-1.0秒かけて自然に完成させる③完成後に0.45-0.55秒の明示的な「タメ」
## を置いてから接近を始める(以前は接近がREVEAL_END直後に即座に始まって
## いた)、の3点に作り直した。ディゾルブの技法自体(Y座標+ノイズによる
## 不規則な境界、境界帯の金色/水色グロー)は維持——軸だけを尾優先から
## 頭優先へ反転させたのがtools/gen_dragon_v2_headfirst_frames.gd(scratch、
## 使用後削除、同じ34枚のeos_dragon_v2_bottomup_N.pngを上書き再生成)。
## 「エオスバースト竜召喚の出現方式を修正」(2026-08-05、5ラウンド目) —
## 「頭・胴体・尻尾の全身が最初から薄く表示される」——直前ラウンドの
## 一様クロスフェード(`_eos_burst_dragon_crossfade_t`、空間的な閾値を
## 一切持たない単一alpha)は、まさにこの「全身が同時にうっすら見える」
## 症状そのものだった(要件を読み違えたのではなく、選んだ技法が要件と
## 相容れなかった)。撤去し、竜自身の体形(S字コイル)に沿った8段階の
## 累積マスクへ全面差し替えた。マスクは`tools/gen_dragon_pixel_v2_stages.gd`
## (scratch、使用後削除)——頭/目(`EYE_SEED`)を起点とした測地線BFS
## (8近傍、直交1.0/斜め√2の重み、不透明ピクセルのみを辿る)距離を
## 全不透明ピクセルに割り当て、"距離のランク(percentile)" で8等分の
## 累積カットオフを取る。距離の絶対値ではなくランクで切ったのは、コイル
## 遠回りで生じる外れ値ピクセル(頭からの最長到達距離が実際の尾先端より
## 大きい迂回経路)に閾値がスキュー(斜めに歪む)されないようにするため
## ——距離ベースの半径バブル方式(前段階で試した2パスBFS)は尾/胴の境界が
## 安定せず(半径55だと尾が11%しか捕捉されず段階6で尾が見えてしまい、
## 半径230だと逆に72%が尾判定されて頭胴すら段階6までに収まらなくなった)
## 採用を見送った。8段階は頭・目/角・たてがみ/首/上半身/中間部/下半身/
## 尾の付け根/尾の先端の順に自然と対応する(ランクで見て段階6=78%点まで
## 尾の先端が未到達、段階7=90%点で尾の大部分が繋がり、段階8=100%で
## 尾先端が完全に接続、を目視で確認済み)。BFSに届かない孤立ピクセル
## (アンチエイリアスの1px程度の島、7個検出)は最近傍の到達済みピクセルの
## 距離を継承させ、段階1に誤って先出しされないようにした。
## 「12コマ方式への置き換え」(2026-08-05) — 前ラウンドの「頭が独立して
## BackShoulderから最終位置まで動くLine2D軌跡+trailing polyline」方式が
## 「細いLine2Dの先端に竜の頭が付いて伸びている、頭の付いた発光チューブに
## 見える」と明確に否定された。手続き型の生成(moving sprite + procedural
## line)を完全に廃止し、**手作業で合成した12コマのスプライトシート**
## (`res://assets/art/eos_dragon_emerge_12f.png`、222×222×12コマ=
## 3996×222)へ拡張した。12コマ方式自体("Line2D方式には戻らず、竜の
## ドット絵・最終サイズ・最終位置・頭→首→胴体→尻尾の順番は維持")は
## ユーザーが明示的に「残してください」と指定した合格ラインだったため、
## 生成技法は完全に同じ(測地線BFS→ランクカットオフ→単一剛体シフト)まま、
## パラメータだけを今回の指摘("竜出現が速すぎる/20fps相当/頭が小さい
## 状態から一気に完成/首→胴体で大きな面積が一気に追加/頭がソティリスに
## 十分隠れない")に合わせて作り直した。
## 「頭の位置だけを修正」(2026-08-05、同日3ラウンド目) — ユーザーが
## `eos_dragon_emerge_12f.png`のファイル名を明示指定し「再生処理(コード)
## は変更せず、現在の再生速度を維持」と述べたため、**フレーム数・fpsを
## 12コマ/10fps(18fps化する直前の値)へ差し戻した**——18コマ化ラウンド
## 自体が誤りだったからではなく、今回のユーザー指示が明示的にこのファイル
## 名/構造を指定したための対応。判断根拠と、もし18コマの方が意図だった
## 場合はすぐ差し戻せる旨を報告書に明記。
## それとは別に、12コマ「内」の絵作り自体を全面的に作り直した。旧12コマ版
## (剛体一括シフト、測地線BFS→ランクカットオフ→単一offset)は「頭が早い
## 段階で最終位置へ到着し停止、その後は首・胴体・尻尾が下へ追加されるだけ
## /頭が拡大して見える」と報告された——原因は、フレームが進むごとに
## 「その時点までの累積ピクセル全部」を**1つの共有offsetで**動かす設計
## そのもので、新しい部位が追加されるたびにoffsetの縮小幅が小さくなり、
## 実質的に頭が数フレームで到着してしまっていた。
## `tools/gen_dragon_emerge_12f_trailing.gd`(scratch・使用後削除)で
## 全面書き換え: ①頭(nose+eyes+head+mane、ranks[0,0.24])は**常に完成時と
## 同一の固定形状**として扱い、フレームごとに縮小/拡大しない——ユーザー
## 指定の11点(フレーム2〜12)絶対位置テーブルをBackShoulder基準の画面
## オフセットとして直接使用(frame12だけ実測した幾何学的な真の最終位置
## へ差し替え、他は同じ形状を保ったまま一律スケール補正)。②首/上半身/
## 胴体中央/下半身/尾の付け根/尾の先端の残り6領域は、それぞれ**頭自身の
## 軌跡を1〜6フレーム遅れでサンプリングした位置**を使う("首は頭の1フレーム
## 前、上半身は2フレーム前"式)——ただしこの遅れはフレーム12に向けて
## 線形に0へ収束させる(そうしないと最終フレームで胴体・尾が頭の軌跡に
## 引きずられたまま真の位置に定着せず、"フレーム12=完成画像と完全一致"
## が満たせなくなる)。③境界の"二重頭"アーティファクト(首の背びれが
## 頭と別offsetで単独に描画されると、それ自体が小さな頭のように見える
## 実害を目視で確認)を、rank境界±0.03の狭い帯だけをオフセット補間で
## 滑らかに繋ぐ方式(帯の外側は各領域が完全にそれ自身のoffsetを保つ、
## "頭の輪郭を変えない"を守るため帯を広げすぎない)で解消。④頭の全体を
## BackShoulder(`EOS_BURST_DRAGON_STAGE_ANCHOR_PX`)へ完全一致させると、
## そのアンカー点がcanvas下端からわずか10pxしか離れておらず頭の顎が
## canvas外へクリップされることを実測で確認(y=[17,89]+offset158=[175,247]、
## canvas高さ221を大幅超過)——offsetのY成分に安全上限(130px)を設け、
## 顎を含む頭全体が常にcanvas内に収まるよう調整(フレーム2の到達点が
## 厳密にBackShoulderそのものからわずかに上寄りになる、数px単位の
## トレードオフとして報告書に明記)。
## 「新しいスプライトへ置き換え」(2026-08-05、同日追加ラウンド) — ユーザー
## から手描きの8コマ竜出現シート`eos_dragon_emergence_8f.png`(1776×222、
## 222×222×8、頭→首・胴体→四肢→一本の尻尾の順に姿勢が変化)が届き、旧
## 12コマシートを置き換えた。**旧実装は既に純粋なcelフレーム切替方式
## だった**(スライド/ワイプ/マスクではない、上のdoc commentの通り)ため、
## 「旧方式の削除」は実質的には無改修で満たされている——変更点はアセット
## パス・フレーム数・タイミングのみ。フレームごとの表示時間は等間隔FPSから
## ユーザー指定の可変デュレーション表へ変更(`EOS_BURST_EMERGE_FRAME_
## DURATIONS`、0.11/0.10/0.10/0.11/0.11/0.12/0.12/0.20秒)。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 旧`EOS_BURST_
## EMERGE_SHEET_PATH`/`_FRAME_COUNT`/`_FRAME_DURATIONS`(竜出現8コマシート
## 専用、既に死蔵だった`_eos_burst_emerge_sheet_texture`/`_draw_eos_burst_
## dragon_emerge_sheet`一式とセットで削除)は完全に削除した。**重要**:
## `EOS_BURST_EMERGENCE_SECONDS`(直下、値1.00)は名前こそ紛らわしいが
## これらとは別物の生きた定数——`EOS_BURST_MATERIALIZE_SECONDS`/
## `REVEAL_END_SECONDS`が直接依存する、汎用の「0.25〜1.25秒(1.00秒)」
## タイムライン窓を表す値のため、竜を削除した今回も無改修のまま維持する
## (README「竜に使っていた0.25〜1.25秒を空白にしません」——窓の長さ
## 自体は同じ、中身だけを弱いオーラ脈動へ差し替える)。
const EOS_BURST_EMERGENCE_SECONDS := 1.00  ## 0.25〜1.25秒の窓の長さ(竜削除後も無改修で維持)
## 「再生終了後は最終フレームをそのまま完成状態として使用」——8コマシートの
## frame7(最後)を`_eos_burst_dragon_master_texture()`が返す「完成竜」
## テクスチャそのものとして使う(`AtlasTexture`でこのシートのframe7領域を
## そのまま切り出す、別ファイルを持たない)。これにより出現→保持の切替
## 瞬間に絵が一切変化しない("別の完成版Sprite2Dへ切り替えない")という
## 旧12コマ版と同じ無縫性を、新しい8コマシートでも維持する。
## 「エオスバースト演出全面刷新」(2026-08-11) — 竜出現(EMERGENCE_SECONDS)
## の途中にカットイン(CUTIN_TOTAL_SECONDS)が丸ごと挟まるため、
## REVEAL_START→REVEAL_END間の実時間はこの2つの合計になる
## (`_eos_burst_emerge_age`が内部で一時停止を処理するので、この定数
## 自体は単に「その間、何秒経過したか」を表すだけ)。
## 「現行ソティリス維持版 v3」(2026-08-12) — 竜出現がカットインより前に
## 完全に終わる設計のため、もうCUTIN_TOTAL_SECONDSを足し込む必要はない
## (前ラウンドの「一時停止」方式の撤去に伴う変更)。
const EOS_BURST_MATERIALIZE_SECONDS := EOS_BURST_EMERGENCE_SECONDS  ## 0.43
const EOS_BURST_REVEAL_END_SECONDS := \
	EOS_BURST_REVEAL_START_SECONDS + EOS_BURST_MATERIALIZE_SECONDS  ## 0.55
## 「間違った竜素材を使わない」(2026-08-02、同日4ラウンド目) — 旧
## ディゾルブ用34枚(eos_dragon_v2_bottomup_*.png、頭優先バージョン)は
## 「クロップ/ワイプ禁止」により出現・消滅のどちらからも参照されなくなった
## ため未参照のまま残置(削除しない)。EOS_BURST_BOTTOMUP_FRAME_COUNT/
## _KEY_PREFIXも消費先が無くなったため削除した。
##
## 「タメ」(HOLD) — 竜が完成してから接近が始まるまでの明示的な静止窓。
## 「竜が完成したら約0.45〜0.55秒タメを維持し、咆哮の余韻を途中で切ら
## ない」——前ラウンドはAPPROACH_START=REVEAL_ENDで接近が完成と同時に
## 始まっていたが、今回は間にこの待機を挟む。ロールは「何かを新しく
## 演じる」のではなく単純に時間を置くことだけ(前々ラウンドで明確に拒否
## された「口を開けて見せる」独立した演技は追加しない、既存のGlowの
## 呼吸だけが自然に続く)。
## 「現行ソティリス維持版 v3」(2026-08-12) — カットイン(0.55〜0.95)が
## 竜完成と剣を掲げる動作の間を直接埋めるため、この待機は不要になった
## (`EOS_BURST_APPROACH_START_SECONDS`がCUTIN_ENDから直接始まる、下記)。
## 定数自体は経緯として残置。
const EOS_BURST_HOLD_SECONDS := 0.0
## 「竜とソティリスの突きを作り直す」(2026-08-05、同日追加ラウンド) —
## 「ソティリスが同じ構えのまま直線移動し...太い四角形の光撃が突然表示
## される」という報告に対し、APPROACH(接近)+STRIKE_PREP(発射準備)の
## 単純な2段階を、ユーザー指定の5段階(接近/踏み込み前の溜め/突き/光撃と
## 命中/余韻と反動)へ全面再構成した。定数名は既存の呼び出し元(mouth
## converge系の窓、ACTOR_FRAMESの折れ線)との互換を保つため極力維持し、
## 意味・値だけを更新している——`EOS_BURST_APPROACH_SECONDS`=①接近、
## `EOS_BURST_STRIKE_PREP_SECONDS`=②踏み込み前の溜め(旧: 接近完了後の
## 最終収束全体を指していたが、③を独立させたことで意味が狭まった)、
## 新設`EOS_BURST_THRUST_LUNGE_SECONDS`=③突き、`EOS_BURST_RELEASE_
## SECONDS`=④光撃と命中(旧0.12→大幅短縮、剣先から敵までの距離を①②③で
## 事前に詰めておくため短い光撃で足りる)、新設`EOS_BURST_THRUST_RECOIL_
## SECONDS`=⑤余韻と反動(着弾直後のキャラクター位置の戻り、着弾VFX自体の
## 長い残光`EOS_BURST_IMPACT_SECONDS`=0.577秒とは別軸で独立に短い)。
## 「竜の接近モーション修正」(2026-08-06) — 「移動開始から最初の接触まで
## 縦向きのまま移動し、到着してから横向きへ差し替わる」という報告への
## 対応で0.32→0.38へ retiming。併せてイージングを`_eos_burst_ease_out_
## cubic`(減速、前半に速度が集中)から`_eos_burst_ease_in_quad`(加速、
## 後半に速度が集中)へ変更——「movement速度が上がる前から竜が自然に体を
## 倒し始める」("穏やかな加速")を狙った、位置イージングのみの変更(下記
## フレーム選択はイージング前の生の進行度を使うため無関係)。
##
## 「接近タイミングの最終調整」(2026-08-06、同日追加ラウンド) — 「横移動
## 開始→最初の接触まで約0.65〜0.70秒ある」というユーザー報告を受けて
## 実際に計算したところ、上記ラウンドは`EOS_BURST_APPROACH_SECONDS`(接近
## 本体)は0.38秒に直したが、その**後ろに** `STRIKE_PREP_SECONDS`(0.18)+
## `THRUST_LUNGE_SECONDS`(0.06)+`RELEASE_SECONDS`(0.06)=0.30秒が無改修の
## まま**加算**され続けていたため、実際の「移動開始→接触」合計は
## 0.38+0.30=0.68秒だった(報告の「0.65〜0.70秒」と正確に一致——ユーザーは
## これを「0.38秒と0.55倍速の二重適用」と表現したが、実体はTweenの
## speed_scaleではなく、この単純な後方への加算だった)。今回`EOS_APPROACH_
## DURATION_SEC`という単一の基準(=0.42秒)だけで「移動開始→接触」の
## 合計を管理するよう修正——0.38→0.42へ変更した上で、下のSTRIKE_PREP_
## START_SECONDS自体の定義を「接近完了後に追加で待つ」方式から「接触の
## 一定時間前」方式へ作り直し、この定数(および連鎖するTHRUST_LUNGE_
## START/BEAM_START/HIT_AT)がAPPROACH_SECONDSの外側に一切はみ出さない
## ようにした(詳細は下のEOS_BURST_THRUST_STAGE_SECONDSのコメント参照)。
## 前回追加した「竜が移動中に横向きになる」修正(ease-in-quad・接近進行度
## テーブル)自体は絶対に戻さない——今回は合計時間だけを直す。
## 「現行ソティリス維持版 v3」(2026-08-12) — README「0.95〜1.18秒:
## 戦闘画面へ戻り、sotiris_eos_downslash_6f.pngのフレーム0→1→2で剣を
## 頭上へ掲げる」——①「敵まで歩いて突進する」処理はもう存在しない
## (`_eos_burst_solve_approach_offset`は常に0を返す、今回は前進すら
## 行わない、下記参照)。この定数はカットインが閉じてから剣を掲げ終える
## までの長さとして再利用する(名前(APPROACH)は下流定数チェーンを
## 書き換えずに済むよう維持)。
## 「Slower + New Impact v4」(2026-08-12) — README「1.48〜1.87秒: 剣を
## 頭上へ掲げる」——0.23→0.39秒。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — 6コマ→12コマ化に
## 伴い、README「2.10〜2.75秒: ソティリス12コマ前半で掲げる」——0.39→0.65秒
## (README個別フレーム時間[0.12,0.11,0.11,0.10,0.10,0.11]の合計と厳密一致
## ——下のEOS_BURST_DOWNSLASH12_RAISE_DURATIONS参照)。
## 「HDDragonCharge v7」(2026-08-13) — README「2.20〜3.05秒: ソティリス
## 12コマ前半でゆっくり掲剣」——0.65→0.85秒(個別フレーム時間[0.15,0.14,
## 0.14,0.14,0.14,0.14]の合計と厳密一致——下のEOS_BURST_DOWNSLASH12_
## RAISE_DURATIONS参照)。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — TRANSITION_
## TIMES_V19.tsvの合計(0.900秒、上のRAISE_DURATIONS参照)へ更新。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) —
## TRANSITION_TIMES_V20.tsvの新フレーム時間表の合計(1.010秒、下の
## RAISE_DURATIONS参照)へ更新。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「全体が
## 速すぎて、構え・カットイン・振り下ろし・斬撃の関係が分からない」——
## character合計を2.640秒(1.550+1.090、下記RAISE/SWING参照)へ大幅延長。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — README「斬撃を撃って
## からは明確に良くなっている。問題はタメモーションが短く、releaseまでが
## まだ早いこと」——release前(のみ)をさらに延長。character合計を3.900秒
## (2.540+1.360、下記RAISE/SWING参照)へ再延長。
const EOS_BURST_APPROACH_SECONDS := 2.54  ## ①剣を頭上へ掲げる(12コマ前半、フレーム0〜5)
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 「③カットイン中に
## 一度モーションが止まり、カットインだけを見せる直列処理になっている」
## ——旧`CUTIN_END_SECONDS`依存(カットインが閉じるまで剣を掲げ始めない)を
## 完全に撤廃し、WINDUP終了(タメ完了)と同時に剣を掲げ始めるよう変更した。
## カットイン自体は今回`APPROACH_START_SECONDS`からの相対オフセットへ
## 依存を逆転させ、掲剣の"途中で"重なるようにする(下記EOS_CUTIN_START_
## SECONDS参照)——「呼び出し側では、ソティリスとオーラを0.000秒で開始し、
## 0.180秒後にplay_moving_cutin(...)をawaitなしで開始」を、参照実装の
## local 0.000=このAPPROACH_START_SECONDSとして解釈した(aura自身も同じ
## 0.000起点=APPROACH_START_SECONDSであることを`SOLAR_AURA_VISIBLE_START`
## の既存の等式で確認済み)。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「暗転後に約1.0秒ほぼ何も動かない」「エオスバースト開始からcharacter/
## aura開始までの待ちは0.080秒だけです。既存の約1.0秒Timer...を削除」。
## 参照実装`play_v20_eos_burst`は`await get_tree().create_timer(BURST_
## LEAD_IN).timeout`(=0.08秒)の直後にcharacter/auraを起動し、コメントで
## 明示: 「Dimming/input lock may start at t=0, but character and aura
## begin after only this 0.08s lead-in」——つまり参照実装のlocal t=0は
## このファイルの`elapsed=0`(暗転/入力ロック=`EOS_BURST_SUMMON_PULLBACK_
## SECONDS`が始まる瞬間)そのもの。真因は、旧`EOS_BURST_WINDUP_SECONDS`
## (=PULLBACK+CHARGE+HOLD=1.25秒、竜削除後もSUMMON_HOLD_SECONDS=1.00秒の
## 弱いオーラ脈動窓としてそのまま生き残っていた)を`APPROACH_START_
## SECONDS`の依存元にしていたこと——character/auraが実際に動き出すまで、
## この1.00秒の「脈動だけの静止窓」を毎回まるごと待たされていた。今回、
## `APPROACH_START_SECONDS`の依存を`WINDUP_SECONDS`から独立させ、新設の
## `EOS_BURST_LEAD_IN_SECONDS`(elapsed=0からの絶対値)へ直接繋ぎ直した
## ——`EOS_BURST_SUMMON_PULLBACK_SECONDS`/`_SUMMON_HOLD_SECONDS`/
## `WINDUP_SECONDS`/`REVEAL_START/_END_SECONDS`/`EMERGENCE_SECONDS`自体は
## 無改修のまま維持(画面暗転のランプ・`_eos_burst_charge_extra_dim`等の
## 別の装飾がこの後もこれらを参照し続けるため)——「暗転/入力ロックは
## t=0で始まってよいが、character/auraだけは0.08秒だけ待てばよい」を、
## 2つの独立した絶対時刻チェーンへ分離することで実現した(暗転側は今まで
## 通りゆっくり1秒超かけて明るさを整えても構わないが、キャラクターは
## それを待たない)。この変更に伴う2件の巻き添え修正は別途参照:
## ①`_eos_burst_windup_sink_px`のゲートをWINDUP_SECONDSからAPPROACH_
## START_SECONDSへ変更(旧ゲートのままだと、character motionが既に始まって
## いる1.09-1.25秒の間もこの2px沈み込みが残り続け、斬撃build中に唐突な
## 2pxポップが起きるところだった)②`_draw_eos_burst_summon_window_pulse`
## を完全削除(「WINDUP_SECONDSまでの空白窓を埋める」という前提そのものが
## 消え、実際のオーラ本体と同じ位置・同じframe0を同時に描く二重発光バグに
## なるところだった、詳細は削除箇所のコメント参照)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — 参照実装
## `BURST_LEAD_IN := 0.100`(v20の0.080から変更)。character/aura開始までの
## 最小待ちがわずかに伸びた——「暗転後にほぼ何も動かない」問題自体は
## v20で解決済みのため、この変更は「読める速度へ」の一部としてそのまま
## 採用した。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — README「lead-in：
## 0.120秒」。斬撃を撃ってからは良くなったが、タメが短くreleaseまでが
## 早い、という評価に対応する今回の変更範囲6項目のうちの1つ——値だけ
## 更新(0.100→0.120)。
const EOS_BURST_LEAD_IN_SECONDS := 0.120
const EOS_BURST_APPROACH_START_SECONDS := EOS_BURST_LEAD_IN_SECONDS  ## 0.100、暗転直後の最小リード
const EOS_BURST_APPROACH_END_SECONDS := \
	EOS_BURST_APPROACH_START_SECONDS + EOS_BURST_APPROACH_SECONDS  ## 2.05
## README「1.18〜1.32秒: フレーム2を短くホールドし、竜と剣の発光を
## 最大化」。
## 「Slower + New Impact v4」(2026-08-12) — README「1.87〜2.15秒:
## フレーム2を0.28秒ホールド」——0.14→0.28秒(「剣の重さが見える」)。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「2.75〜
## 3.20秒: フレーム5を0.45秒保持。人物・カメラ・竜の大移動を止め、光量
## だけ上げる」——0.28→0.45秒(12コマ化に伴いホールド対象がframe2→frame5
## (前半の最終コマ)へ移った)。
## 「HDDragonCharge v7」(2026-08-13) — README「3.05〜3.45秒: 掲剣頂点
## ホールド・竜が構える」——0.45→0.40秒。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — TRANSITION_
## TIMES_V19.tsvの新モデルには「フレーム5を静止保持する」区間が存在しない
## (frame5自身の0.180秒の中に、末尾0.050秒のframe6へのブレンドが既に
## 含まれる、上のRAISE_DURATIONS参照)——この静止ホールド区間を0秒へ
## collapseした。STRIKE_PREP_START_SECONDS(=APPROACH_END_SECONDS)と
## THRUST_LUNGE_START_SECONDS(下記)が同じ瞬間になり、「フレーム5→6が
## 継続的にブレンドされ、途中に静止が挟まらない」を満たす。この定数の
## 唯一の生きた消費者だった`_eos_burst_thrust_offset_px_disabled`は既に
## 呼び出し元ゼロの死蔵関数(v3ラウンドで無効化済み)、`EOS_BURST_MOUTH_
## CONVERGE_SECONDS`(=STRIKE_PREP_SECONDS+THRUST_LUNGE_SECONDS)は値が
## 0になった分だけ自動的にTHRUST_LUNGE_SECONDS単独へ縮む(式自体は無改修)。
const EOS_BURST_STRIKE_PREP_SECONDS := 0.0  ## 旧②フレーム5静止ホールド、v19で撤廃
const EOS_BURST_STRIKE_PREP_START_SECONDS := EOS_BURST_APPROACH_END_SECONDS  ## 2.05
## README「1.32〜1.55秒: フレーム3→4→5で振り下ろす。同時にeos_downslash_
## wave_6f.pngとeos_dragon_assault_6f.pngを同じ方向へ再生する」。
## 「Slower + New Impact v4」(2026-08-12) — README「2.15〜2.46秒:
## フレーム3→4→5で振り下ろす」——0.23→0.31秒。「斬撃はまだ敵へ先行
## させない」ため、斬撃自体(eos_sword_crescent_6f.png)はこの振り下ろし
## 窓の途中(2.30秒、絶対時刻)から独立して始まり、振り下ろし完了後も
## 0.26秒だけ続く——下のEOS_BURST_CRESCENT_*を参照。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「3.20〜
## 3.80秒: フレーム6→7→8→9→10→11で振り下ろす」——0.31→0.60秒(個別
## フレーム時間[0.11,0.10,0.08,0.07,0.10,0.14]の合計と厳密一致——下の
## EOS_BURST_DOWNSLASH12_SWING_DURATIONS参照)。三日月斬撃(12コマ化)は
## 引き続きこの窓の途中(3.55秒、絶対時刻)から独立して始まる。
## 「HDDragonCharge v7」(2026-08-13) — README「3.45〜4.15秒: ソティリス
## 12コマ後半で振り下ろし・竜が突進姿勢へ」——0.60→0.70秒(個別フレーム
## 時間[0.13,0.12,0.11,0.10,0.11,0.13]の合計と厳密一致——下のEOS_BURST_
## DOWNSLASH12_SWING_DURATIONS参照)。
## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — 竜はもう突進しない
## (`EOS_BURST_DRAGON_CHARGE_START_SECONDS`一式は完全削除、上記コメント
## 「竜が突進姿勢へ」は経緯として残置)——GrandCrescent(五層斬撃の②、
## `EOS_BURST_GRAND_CRESCENT_START_SECONDS`=3.58)がこの振り下ろし窓の
## 途中から始まる後継として同じ役割を果たす。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — TRANSITION_
## TIMES_V19.tsvの合計(0.500秒、上のSWING_DURATIONS参照)へ更新。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) —
## TRANSITION_TIMES_V20.tsvの新フレーム時間表の合計(0.590秒、下の
## SWING_DURATIONS参照)へ更新。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — SWING_
## DURATIONSの合計(1.090秒、下記参照)へ更新。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — SWING_DURATIONSの
## 新しい合計(1.360秒、下記参照)へ更新。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — SWING_
## DURATIONSが6→10要素へ拡張された新しい合計(1.480秒、下記参照)へ更新。
const EOS_BURST_THRUST_LUNGE_SECONDS := 1.48  ## ③振り下ろし(16コマ後半、フレーム6〜15)
const EOS_BURST_THRUST_LUNGE_START_SECONDS := \
	EOS_BURST_STRIKE_PREP_START_SECONDS + EOS_BURST_STRIKE_PREP_SECONDS  ## 2.05(STRIKE_PREP=0のためAPPROACH_ENDと同値)
const EOS_BURST_BEAM_START_SECONDS := \
	EOS_BURST_THRUST_LUNGE_START_SECONDS + EOS_BURST_THRUST_LUNGE_SECONDS  ## 2.55(v19)、振り下ろし完了
## 「斬撃は必ず下げた刀身から始め、竜の口から別のビームを出さない」——
## 前ラウンドの独立した光撃(EOS_BEAM、剣先から0.80秒かけて伸びる光の
## 奔流)は撤去した。斬撃効果は新規`eos_sword_crescent_6f.png`(下記
## EOS_BURST_CRESCENT_*)が担う。
## 「Slower + New Impact v4」(2026-08-12) — README「3.20：ダメージ表示と
## 敵ノックバック」——振り下ろし完了(BEAM_START=2.46)から斬撃到達
## (2.72)・白フラッシュ・縦の竜牙命中(2.74〜3.20)を経て、ダメージ自体は
## 3.20の絶対時刻で発生する。RELEASE_SECONDSはこの間隔(0.74秒)を表す
## だけの値へ意味を変更(旧: 光撃の飛翔時間)。実際の`_battle_hitstop_t`
## (0.08秒、変更禁止)により、ヒットストップ解除の実時間はここから
## さらに約0.08秒後になる——他スキル同様、この既存の仕組みへ数値を
## 逆算せずそのまま乗せる(headless実測値は報告に開示)。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「4.63：
## ダメージ確定、敵ノックバック開始。爆発表示より前にダメージを出さない」
## ——振り下ろし完了(BEAM_START=3.80)から斬撃到達(4.35)・反転フラッシュ
## (4.35-4.43)を経て、大型ドラゴンバースト開始(4.40)の0.23秒後、絶対時刻
## 4.63でダメージが発生する。フレーム累積で確認すると4.63はバーストの
## frame3(4.61-4.69)にあたり、敵を完全に覆い隠すframe6/7のピーク
## (4.88-5.16、下記EOS_BURST_MASSIVE_FRAME_DURATIONS参照)より前——「爆発
## 表示より前にダメージを出さない」は満たすが、「ピークによる完全被覆と
## 同時にダメージが出る」わけではない(README自身がこの2つを別の指定と
## して与えているため、両者を無理に同期させずそれぞれ独立に絶対時刻へ
## 従った)。RELEASE_SECONDSはこの間隔を表すだけの値(旧: 光撃の飛翔時間)。
## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — GrandCrescent(新規
## 五層斬撃の②)が敵ground anchorへ到達する瞬間(3.58+1.20=4.78)と、
## TIMELINE_V8.csv自身の「4.78,4.86,screen_flash」行の両方がHIT_AT=4.78
## を指す——BEAM_START(振り下ろし完了、3.45+0.70=4.15)から接触までの
## 間隔としてRELEASE_SECONDSを0.57→0.63(=4.78-4.15)へ更新するだけで、
## 既存の`HIT_AT := BEAM_START + RELEASE_SECONDS`という式自体・
## ヒットストップ・ダメージ発火機構は無改修のまま新しい絶対時刻へ自動
## 追従する。
## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — TIMELINE_V13.csv
## 「3.92,4.74,0.82,travel」——水平斬撃の到達(=MotionAnchorがtarget_tip_x
## へ着いた瞬間)と着弾閃光frame0の表示が完全に同時になるよう、HIT_AT
## (=このダメージ確定の瞬間)を水平斬撃の終了時刻(4.74)へ厳密に一致させる。
## BEAM_START(振り下ろし完了、無改修のまま4.15)から接触までの間隔として
## RELEASE_SECONDSを0.63→0.59(=4.74-4.15)へ更新するだけで、既存の
## `HIT_AT := BEAM_START + RELEASE_SECONDS`という式自体・ヒットストップ・
## `_battle_anim_hit_fired`一回性ガード・ダメージ発火機構は無改修のまま
## 新しい絶対時刻へ自動追従する(「damage_apply_countが0→1」は、この
## 既存の共有フラグそのものが元から満たしている要件——新しい状態変数は
## 追加していない)。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — TIMELINE_V14
## .csv「3.58,4.78,1.20,travel」——復元した大斬撃(Main/Echo)の到達時刻
## (4.78)へHIT_ATを再び一致させるよう0.59→0.63(=4.78-4.15)へ更新。同じ
## 仕組み(`_battle_anim_hit_fired`一回性ガード)がそのまま新しい絶対時刻へ
## 自動追従する。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — TIMELINE_V15.csv
## 「3.92,4.70,0.78,travel」——大斬撃を0.78秒へ高速化したことに伴い到達
## 時刻が4.70へ前倒しされたため、HIT_ATを同じ4.70へ一致させるよう0.63→
## 0.55(=4.70-4.15)へ更新。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-16) — 「着弾開始をソティリス
## のframe8..11再生終了後まで待たないでください。斬撃→接触→ダメージ→
## 着弾→爆発の非同期チェーンをframe7で開始し、ソティリスの残り
## フォロースルーとは並行させてください」という明示要求により、HIT_AT
## (=ダメージが発生する瞬間)の定義を`BEAM_START + RELEASE_SECONDS`(=
## ソティリスの振り下ろし完了=frame11到達、v12以来の"downslash-gated"
## モデル)から、斬撃自身の動的タイムライン`EOS_BURST_SLASH_END_SECONDS`
## (下記参照、release-frame変更+距離ベースduration計算から独立に導出
## される)へ完全に切り離した。v18では実測でSLASH_END(4.08)がBEAM_START
## (4.15、無改修のまま——ソティリスの振り下ろしポーズ選択専用の指標
## として維持)より**先に**来る——これは意図的: 斬撃の到達距離が短い
## (実測149px、速度換算0.20秒)ためMIN_DURATION(0.50秒)でクランプされ、
## SLASH_START(3.58、frame7基準)+0.50=4.08が、ソティリス自身のフォロー
## スルー完了(4.15)より早く終わる。これにより「着弾チェーンがframe7で
## 独立して始まり、ソティリスの残りポーズ再生を待たない」という要求を、
## 新しいコルーチン/タスク機構を追加せず、単に両者が別々の絶対時刻から
## 独立に駆動される(このファイル全体が元々そうである)既存アーキテク
## チャのまま満たす。`EOS_BURST_RELEASE_SECONDS`(0.33)自体は、もう
## HIT_ATの導出には使わないが、値は変更せず残置——`EOS_BURST_BEAM_
## TRAVEL_SECONDS`(旧・独立ビーム`_draw_eos_burst_breath`専用、呼び出し
## 元ゼロの死蔵コード)と`EOS_BURST_ASSAULT_TOTAL_SECONDS`(旧・icon
## override窓専用、これも呼び出し元ゼロ)だけが今も参照する——これらは
## 削除するとGDScriptの未定義参照エラーになるためコンパイルを通すために
## 残す必要があり、いずれも到達不能なので値自体に意味はもう無い。
## `_draw_eos_burst_mouth_tip_charge`(下記、剣先の点光源)だけが唯一
## `RELEASE_SECONDS`をBEAM_START..HIT_AT間隔として実際に使っていたが、
## この窓は今回`BEAM_START(4.15) > HIT_AT(4.08)`により空になってしまう
## ため、その関数は`EOS_BURST_SLASH_START/_END_SECONDS`(斬撃自身の実際の
## 発射〜命中窓)を直接参照するよう合わせて更新した——「剣先の光は突撃〜
## 命中の間ずっと育つ」という元の演出意図を、正しい(今回大幅に早まった)
## 窓へ再接続するための巻き添え修正であり、パック自身の指定範囲外だが
## 何もしないと表示が完全に消えるため実施した(報告に開示)。
const EOS_BURST_RELEASE_SECONDS := 0.33
const EOS_BURST_HIT_AT_SECONDS := EOS_BURST_SLASH_END_SECONDS  ## 斬撃自身の動的終了(4.08)、BEAM_STARTから独立
## ⑤余韻と反動(位置のみ、接触後=着弾VFX自体の残光とは別軸)——今回は
## ソティリスの前進/突き物理オフセットを撤去した(下記
## `_eos_burst_thrust_offset_px`参照)ため、実質無効化されている。
const EOS_BURST_THRUST_RECOIL_SECONDS := 0.0
## 「新しいスプライトへ置き換え」(2026-08-05、同日追加ラウンド) — ソティリス
## の突きモーションを専用の6コマシート`sotiris_eos_thrust_6f.png`(222×222
## ×6、溜め→踏み込み→最大突き→振り抜き→復帰)へ全面置換。UDArtLibraryの
## 標準規約(`<key>.png`+`_f2..f6.png`)に合わせて6枚へ切り出し済み
## (`skill_minion_0_eosthrust`、`_battle_motion_keys()`へ登録)——「begins_
## with("skill_minion_")」分岐に頼らず`_draw_party_row`内で`icon`を直接
## 上書きする方式(下記参照)を採る。index3(0始まり、4枚目)が「最大突き・
## 光槍の発射フレーム」でBEAM_STARTにちょうど一致する(コマ0+1+2=
## 0.10+0.08+0.06=0.24秒=STRIKE_PREP_SECONDS+THRUST_LUNGE_SECONDS)。
## 「エオスバースト・煉獄型の総仕上げ」(2026-08-05、同日追加ラウンド) —
## この配列のindex0-2(0.10/0.08/0.06)は新しい「3素材を同期する」表と
## 完全に一致していたため無改修のまま流用(`_eos_burst_assault_frame_
## index`経由)——index3-5(0.07/0.08/0.12、旧「振り抜き→復帰」の固定
## 秒数)はもう参照されない(接触/最大爆発/余韻は動的なヒットストップ・
## 着弾sprite自身の秒数で駆動するため)。配列自体は削らず残置——index0-2
## だけが生きたまま使われている状態。旧・icon override窓の終了点
## `EOS_BURST_THRUST_TOTAL_SECONDS`(6コマ単純合計0.51秒)は死蔵定数に
## なったため削除、`EOS_BURST_ASSAULT_TOTAL_SECONDS`(上記参照)へ置換。
## 旧・突き用スプライト(前ラウンド以前の旧タイムラインでのみ使用)。
## 今回のREADMEはこのキー自体には触れず、専用の振り下ろしシートへ完全
## 置換したため、下記の新キーへ主導権を譲る——このキー自体は削除しない
## (art asset自体は既存のまま、コードからの参照だけが移る)。
const EOS_BURST_THRUST_POSE_KEY := "skill_minion_0_eosthrust"
const EOS_BURST_THRUST_SPRITE_SCALE: float = 222.0 / 128.0
const EOS_BURST_THRUST_FRAME_DURATIONS: Array[float] = [0.10, 0.08, 0.06, 0.07, 0.08, 0.12]
const EOS_BURST_THRUST_GROUND_ANCHOR_X_PX: Array[float] = [
	130.64, 119.96, 107.36, 78.10, 48.27, 92.99,
]
## 「現行ソティリス維持版 v3」(2026-08-12) — 納品の専用6コマ
## `sotiris_eos_downslash_6f.png`(1332×222、222×222/コマ)。UDArtLibrary
## の標準規約(`<key>.png`+`_f2..f6.png`)に合わせて`tools/`で6枚へ切り出し
## 済み(`skill_minion_0_eosdownslash`、`_battle_motion_keys()`へ登録)。
## 「既存の`sotiris_eos_thrust_6f.png`と同じtransformとground anchorを
## そのまま引き継いでください」——キャンバスサイズ・スケール算出方法
## (222/128、頭部ピクセル密度基準)は同一のまま踏襲(README「身体高は
## 既存約94px、新規約95pxです」——ほぼ同一のため同じスケール定数で正しい)。
const EOS_BURST_DOWNSLASH_POSE_KEY := "skill_minion_0_eosdownslash"
const EOS_BURST_DOWNSLASH_SPRITE_SCALE: float = 222.0 / 128.0
## PowerShellで6コマ全ての content bbox・最下8行の重心Xを実測
## (`tools/`の使い捨てスクリプト、確認後削除)。y方向はどのコマも
## bbox下端が208-209px——README指定の「全コマの足元基準はローカルY=210」
## とほぼ一致するため、Yは既存の突きシートと同様に補正不要(定数化のみ)。
const EOS_BURST_DOWNSLASH_GROUND_Y_PX := 210.0
const EOS_BURST_DOWNSLASH_GROUND_ANCHOR_X_PX: Array[float] = [
	127.45, 109.56, 109.91, 111.16, 71.67, 84.72,
]
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — 納品の専用12コマ
## `sotiris_eos_downslash_12f.png`(2664×222、222×222/コマ)。UDArtLibrary
## の標準規約に合わせて`tools/`で12枚へ切り出し済み
## (`skill_minion_0_eosdownslash12`、`_battle_motion_keys()`へ登録)。旧
## 6コマキー(`EOS_BURST_DOWNSLASH_POSE_KEY`)・その定数群は無改修のまま
## 残置(削除しない)——このキーが新たに主導権を持つ。
const EOS_BURST_DOWNSLASH12_POSE_KEY := "skill_minion_0_eosdownslash12"
const EOS_BURST_DOWNSLASH12_SPRITE_SCALE: float = 222.0 / 128.0
## PowerShellで12コマ全ての接地帯(alpha>128が8px以上連続する最下段行)の
## Yを実測したところ、全コマでsolidBottomY=213(ローカル)と完全に一致
## していた——README「12コマすべての足元はローカルY=214付近へ揃えて
## あります」とほぼ一致。「実装時に1コマごとのposition補正を追加しません」
## との明示指示どおり、X方向の補正テーブルもここでは作らない(旧6コマ版
## にあった`EOS_BURST_DOWNSLASH_GROUND_ANCHOR_X_PX`に相当するものは無い
## ——`_draw_party_row`側でこのキー使用時だけ補正呼び出し自体を省略する、
## 上記コード参照)。この定数自体は記録用(実際のposition式では未使用、
## 既存の`EOS_BURST_DOWNSLASH_GROUND_Y_PX`が旧6コマ版でも同じ「記録用のみ、
## 実装には使わない」扱いだった前例をそのまま踏襲)。
const EOS_BURST_DOWNSLASH12_GROUND_Y_PX := 213.0
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「③
## ソティリスの輪郭が白っぽく二重に見える」の真因は①同じ姿勢2枚を全身
## 単位で半透明に重ねる旧クロスフェード自体が二重化を生んでいたこと②
## 輪郭の一部に明るい無彩色ピクセルがあり暗い戦闘背景で強調されていた
## こと(alpha自体は元sheetと不変、輪郭色だけを暗色clean copyへ置換した
## 新sheetが届いた)。`sotiris_eos_downslash_12f_crisp_v21.png`
## (2664×222、222×222/コマ、SOTIRIS_ALPHA_CONTRACT_V21.tsvで12/12とも
## 旧v20 sheetとalpha完全一致(12/12)を確認済み——顔・服・配色・剣・
## 姿勢・canvasは無改修)を`tools/`で12枚へ切り出し済み。旧クロス
## フェード自体(alpha0.5の重ね描き)も、下記の複合ダイザー方式(4x4
## ordered ditherと数学的に等価、キャッシュ済みコンポジットテクスチャ
## を1枚だけ描く)へ全面差し替えた——詳細は`_eos_burst_downslash12_
## dither_texture`のdoc comment参照。
const EOS_BURST_DOWNSLASH12_CRISP_POSE_KEY := "skill_minion_0_eosdownslash12crisp"
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — README
## 「v24で上段振り下ろしの運動自体は成立しましたが、追加4コマだけ別々の
## 生成画像から作られており、現行ソティリスより大きいコマと小さいコマ、
## 異なるドット密度が混在していました」。12コマ(旧frame0-11)は画素単位で
## 継承しつつ、新frame6-9だけ現行12コマの3倍editマスターから再作画した
## 16コマシートへ全面差替え(v23/v24自体はこのプロジェクトに実装された
## ことが無く、今回のパックが同梱するv24 baseline資料から直接v25の最終
## 状態を構築した——詳細は本ラウンドのCLAUDE.md記載を参照)。
const EOS_BURST_DOWNSLASH16_POSE_KEY := "skill_minion_0_eosdownslash16currentscale"
## 「HDDragonCharge v7」(2026-08-13) — README「人物前半フレーム0〜5：
## [0.15, 0.14, 0.14, 0.14, 0.14, 0.14](合計0.85秒)。フレーム5頂点保持：
## 0.40秒」——合計0.85秒はEOS_BURST_APPROACH_SECONDSと厳密一致。「最速でも
## 1コマ0.10秒を確保」——最小値0.14秒で余裕を持って満たす。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — TRANSITION_
## TIMES_V19.tsv「character 0〜4」——[0.140,0.140,0.140,0.140,0.160,0.180]
## (合計0.900秒、旧0.85秒から+0.05秒)へ更新。フレーム5(頂点)の静止ホールド
## は今回廃止(下記STRIKE_PREP_SECONDS参照)——frame5自身の0.180秒の中に
## 末尾0.050秒のframe6への滑らかなブレンドが含まれるため、「静止してから
## 一枚で切り替わる」段差がここでも解消される。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) —
## TRANSITION_TIMES_V20.tsv「character 0〜4」——[0.160,0.150,0.150,0.150,
## 0.180,0.220](合計1.010秒、旧0.900秒から+0.110秒)へ更新——README
## 「②カットイン終了→releaseまでを0.200秒の可視ブリッジにする」ための
## 尺の一部がここに含まれる(frame5→6の境界=index5=0.220秒、下記参照)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — 参照実装
## `CHARACTER_FRAME_TIMES`前半6要素——[0.250,0.240,0.240,0.240,0.260,0.320]
## (合計1.550秒、旧1.010秒から+0.540秒)。「読める速度へ」を、各姿勢の
## 保持時間を全体的に伸ばすことで実現。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — 参照実装
## `CHARACTER_FRAME_TIMES`前半6要素——[0.380,0.360,0.360,0.380,0.460,0.600]
## (合計2.540秒、旧1.550秒から+0.990秒)。pose0-2はカットイン前の見える
## 構え、pose3-4はカットイン背面で剣を上げる区間(PROCESSING_NOTES_V22.md)。
const EOS_BURST_DOWNSLASH12_RAISE_DURATIONS: Array[float] = [0.380, 0.360, 0.360, 0.380, 0.460, 0.600]
## README「人物後半フレーム6〜11：[0.13, 0.12, 0.11, 0.10, 0.11, 0.13]
## (合計0.70秒)」——合計0.70秒はEOS_BURST_THRUST_LUNGE_SECONDSと厳密
## 一致。「8→9だけ急に0.07秒へ縮めません」——最小値0.10秒で満たす。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — TRANSITION_
## TIMES_V19.tsv「character 6〜10」——[0.085,0.075,0.070,0.070,0.085,0.115]
## (合計0.500秒、旧0.70秒から-0.20秒)へ更新。frame6の表示時間(0.085)は
## `EOS_BURST_DOWNSLASH12_RELEASE_OFFSET_SECONDS`(=SWING_DURATIONS[0])の
## 定義式を無改修のまま自動的に0.13→0.085へ反映する。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) —
## TRANSITION_TIMES_V20.tsv「character 6〜10」——[0.110,0.090,0.080,0.080,
## 0.100,0.130](合計0.590秒、旧0.500秒から+0.090秒)へ更新。frame6→7の
## 表示時間(0.110)は`EOS_BURST_DOWNSLASH12_RELEASE_OFFSET_SECONDS`の
## 定義式を無改修のまま自動的に0.085→0.110へ反映する。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — 参照実装
## `CHARACTER_FRAME_TIMES`後半6要素——[0.250,0.160,0.140,0.140,0.180,0.220]
## (合計1.090秒、旧0.590秒から+0.500秒)。frame6の表示時間(0.250)は
## `EOS_BURST_DOWNSLASH12_RELEASE_OFFSET_SECONDS`の定義式を無改修のまま
## 自動的に0.110→0.250へ反映する。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — 参照実装
## `CHARACTER_FRAME_TIMES`後半6要素——[0.420,0.180,0.160,0.160,0.200,0.240]
## (合計1.360秒、旧1.090秒から+0.270秒)。frame6の表示時間(0.420)は
## `EOS_BURST_DOWNSLASH12_RELEASE_OFFSET_SECONDS`の定義式を無改修のまま
## 自動的に0.250→0.420へ反映する——pose5(最大チャージ)保持0.600秒(上記
## RAISE末尾)からpose6の0.420秒振り下ろしを経てreleaseへ、という
## PROCESSING_NOTES_V22.mdの記述と一致。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — README
## 「16コマ全体のcharacter frame times：[0.380,...,0.600,0.110,0.110,0.100,
## 0.100,0.120,0.180,0.160,0.160,0.200,0.240]」——旧pose6(0.420秒、頭上→
## 腰までの振り下ろしを1枚で表現していた)が、現行ソティリスの制作条件で
## 再作画した4コマの中割り(新frame6-9、[0.110,0.110,0.100,0.100]、合計
## 0.420秒=旧pose6と厳密一致)+新frame10(0.120秒、旧pose6の続きに相当する
## 最終フォロースルー前の1コマ)へ分解された。旧pose7-11(=新frame11-15)は
## 画素・秒数とも無改修のまま新frame11-15へスライドしただけ——6要素→10
## 要素への拡張だが、末尾5要素[0.180,0.160,0.160,0.200,0.240]は旧SWING[1..5]
## と完全に同じ値。
const EOS_BURST_DOWNSLASH12_SWING_DURATIONS: Array[float] = [
	0.110, 0.110, 0.100, 0.100, 0.120, 0.180, 0.160, 0.160, 0.200, 0.240,
]
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 「①一つ一つの
## 姿勢とVFXのつながりが滑らかでなく、長く止まった後に一枚で切り替わる
## ためカクついて見える」——各frameを`min(0.050, interval*0.65)`秒だけ
## SmootherstepでA/Bクロスフェードする(下記`_eos_burst_downslash12_hold_
## blend`)。RAISE(6)+SWING(6)を単純連結した12要素の専用テーブル——
## フレーム5→6の境界(旧STRIKE_PREP hold、下記で0秒へ collapse)を含めた
## 全11境界を1つの配列・1つの走査ループで均一に扱うための構成(RAISE/
## SWING個別の配列のままだと、5→6の境界だけ「次の配列の先頭」を跨ぐため
## 単純な走査では表現できない)。値自体は上記RAISE/SWING配列と重複するが、
## 意味が異なる(位相境界の名前付き秒数 vs. ブレンド走査用の連結テーブル)
## ため二重管理と見なさない。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — RAISE/
## SWINGの更新をそのまま連結(合計1.600秒)。`BLEND_MAX_SECONDS`も
## README「各interval末尾min(0.055, interval*0.65)秒」に合わせ0.050→
## 0.055秒へ更新。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — RAISE/SWINGの
## 更新をそのまま連結(合計2.640秒)。`BLEND_MAX_SECONDS`もREADME「各
## interval末尾最大0.067秒」に合わせ0.055→0.067秒へ更新——参照実装
## `CHARACTER_DITHER_MAX := 0.067`と一致。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — RAISE/SWINGの更新を
## そのまま連結(合計3.900秒)。`BLEND_MAX_SECONDS`もREADME「ordered dither
## 最大時間：0.080秒」に合わせ0.067→0.080秒へ更新——参照実装
## `CHARACTER_DITHER_MAX := 0.080`と一致。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — RAISE
## (6要素、無改修)+SWING(10要素、上記参照)をそのまま連結(合計4.020秒)。
## `BLEND_MAX_SECONDS`自体は0.080のまま無改修——参照実装`CHARACTER_
## DITHER_MAX := 0.080`も無改修。ただしCHANGE_MAP_V24_TO_V25.tsv「dither
## transition: min(0.080s, interval×0.45)」——新設4コマがどれも0.10-0.12秒
## という短い持ち時間のため、旧倍率0.65のままだと単一interval内でblend
## 窓が重複しうる(0.110*0.65=0.0715秒、これ自体は0.080未満で収まるが、
## 参照実装が明示的に0.65→0.45へ変更したためそのまま踏襲)——下記
## `_eos_burst_downslash12_hold_blend`の乗数を新設の比率定数へ差し替える。
const EOS_BURST_DOWNSLASH12_BLEND_DURATIONS: Array[float] = [
	0.380, 0.360, 0.360, 0.380, 0.460, 0.600,
	0.110, 0.110, 0.100, 0.100, 0.120,
	0.180, 0.160, 0.160, 0.200, 0.240,
]
const EOS_BURST_DOWNSLASH12_BLEND_MAX_SECONDS := 0.080
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — 参照実装
## `CHARACTER_DITHER_INTERVAL_RATIO := 0.45`(v22以前は0.65固定でハード
## コードされていた——今回初めてnamed constant化)。
const EOS_BURST_DOWNSLASH12_BLEND_RATIO := 0.45
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 「ソティリスが剣を振り下ろ
## した瞬間と斬撃が出る瞬間がずれている(約0.25秒、60fps換算で約15フレ
## ーム遅れ)」という報告。真因はEOS_BURST_SLASH_START_SECONDS(斬撃開始)
## が、この振り下ろしスケジュールから完全に独立した固定絶対値(3.92)
## だったこと——headless実測(下のfrom_release_offsetとTHRUST_LUNGE_
## START_SECONDSから計算)では、実際にframe8(0始まり、参照実装の
## RELEASE_FRAME_INDEXと同じ、"release"フレーム)が始まる絶対時刻は3.70
## で、0.22秒(約13フレーム)ものズレがあった。「時刻ではなくアニメフレーム
## へ同期」——このファイルには実コルーチン/await機構が無い(単一の同期
## `_draw()`ディスパッチ、`elapsed`のみで駆動)ため、"同じ描画フレームで
## 2つのイベントを発火する"という要求は、"同じ絶対時刻の式から両方を
## 導出する"ことで構造的に満たす。frame8が始まる絶対時刻を、
## `_eos_burst_downslash12_frame_index`が使うのと全く同じ累積和(frame6
## +frame7の表示時間、release=frame8はSWING_DURATIONSのindex2=6+2に
## 対応するためindex0とindex1の合計)で計算し、SWING_DURATIONSが将来
## 変更されても自動的に追従する式にする(ハードコードした絶対秒定数を
## 廃止)。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — 「ソティリスが剣を
## 振り下ろした後に斬撃が出ており、発生が遅い」(30fps抽出で振り下ろし後
## 姿勢=フレーム29、斬撃初表示=フレーム33、約4フレーム=0.133秒遅れ)。
## 参照実装の新しいRELEASE_FRAME_INDEX(=7、"最初の完全な振り下ろし後・
## フォロースルー姿勢")に合わせ、release対象をframe8→frame7へ変更した。
## frame7が始まる絶対時刻はframe6の表示時間(SWING_DURATIONS[0])だけの
## 累積和——旧v16のframe8版(SWING_DURATIONS[0]+[1])から[1]を除くだけで
## 同じ「累積和で自動追従する」設計を維持する。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — 参照実装
## `RELEASE_FRAME_INDEX := 7`(無改修)。SWING_DURATIONS[0]の更新(0.13→
## 0.25)がこの式自体を無改修のまま自動的に反映する——「時刻ではなく
## アニメフレームへ同期」を今回も継続。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — 参照実装
## `RELEASE_FRAME_INDEX := 11`(旧7から+4、新設frame6-9の挿入分だけ
## スライドしただけで、その先の相対位置=「SWINGの2番目の姿勢」という
## 意味自体は不変)。CONTINUITY_CONTRACT_V25.tsv「release: pose11とgrand_00
## first visibleが同じdraw」。RELEASE_OFFSET_SECONDSの式も、旧「SWING配列
## の先頭1要素」から「release直前までのSWING配列先頭5要素の累積和」へ
## 一般化——release対象のframeがSWING配列内で何番目かが変わっても(旧: 1
## 番目、新: 6番目)、この式は「releaseフレームが表示され始める瞬間の
## THRUST_LUNGE_START相対オフセット」という同じ意味をそのまま保つ。
const EOS_BURST_DOWNSLASH12_RELEASE_FRAME_INDEX := 11  ## 0始まり
const EOS_BURST_DOWNSLASH12_RELEASE_OFFSET_SECONDS := \
	EOS_BURST_DOWNSLASH12_SWING_DURATIONS[0] + EOS_BURST_DOWNSLASH12_SWING_DURATIONS[1] \
	+ EOS_BURST_DOWNSLASH12_SWING_DURATIONS[2] + EOS_BURST_DOWNSLASH12_SWING_DURATIONS[3] \
	+ EOS_BURST_DOWNSLASH12_SWING_DURATIONS[4]  ## frame6-10の累積表示時間=0.540
## 「エオスバースト最終仕上げ: 攻撃後半の完成」— 「着弾地点の光を約
## 0.4〜0.5秒残す」(旧0.25秒から延長)で確定した合計0.577秒。当時の
## CONTACT/BURST/AFTERMATHという3段階の手続き描画による内訳は、「オーラ
## のクオリティと着弾の迫力を修正」(2026-08-05)で専用6コマスプライトへ
## 全面差し替えられ撤去済み。「エオスバースト・煉獄型の総仕上げ」(同日
## 追加ラウンド)で、この0.577秒自体も新しい「接触→0.08秒停止→解放」
## 構造に合わせて再計算した——解放から着弾sprite自身のframe5(余韻)終了
## までの合計(0.10+0.09+0.10+0.14、下の`EOS_BURST_IMPACT_POST_RELEASE_
## FRAME_DURATIONS`の合計と完全一致——GDScriptのconstは前方参照できない
## ためこの値へ直接反映し、headless検証で両者が一致することを確認済み)
## とちょうど揃え、着弾演出が終わったその瞬間にVANISH_STARTへ接続する
## ようにした(旧0.577秒は「予算」で余りがあったが、今回はユーザー自身の
## 詳細な秒数指定により余りの無い正確な値になった)。
## 「現行ソティリス維持版 v3」(2026-08-12) — README「1.55〜1.62秒:
## eos_impact_flash_6f.png(白黒反転は60fpsで1〜2フレームだけ)」+
## 「1.62〜1.95秒: eos_impact_explosion_6f.pngを再生し、画面揺れとノック
## バック」——0.07秒(閃光)+0.33秒(爆発)。爆発本体は既存の巨大爆発6コマ
## (`eos_impact_mega_explosion_6f_v3.png`、納品の`eos_impact_explosion_
## 6f.png`とSHA256完全一致=既に導入済みの同一ファイル)をそのまま再利用。
## 「Slower + New Impact v4」(2026-08-12) — README「以前の
## eos_impact_flash_6f.png」「以前のeos_impact_explosion_6f.png」を
## どちらも【必ず撤去するもの】として明示的に除去対象へ挙げているため、
## 前ラウンドの「変更禁止」保護は今回のプロンプトが上書きする。閃光は
## 新規`eos_sword_crescent_6f.png`到達時の手続き白フラッシュ(下記
## EOS_BURST_SLASH_FLASH_*)へ、爆発は縦の竜牙命中(`eos_dragon_fang_
## impact_6f.png`)+上昇する残光(`eos_dragon_afterglow_6f.png`)へ完全に
## 置換した——この2定数自体は「ダメージ発生(HIT_AT)後、竜/オーラの
## 大きな姿勢を保持する時間の予算」という意味へ repurpose し、値は新しい
## 実測タイムラインに合わせて設定した(旧`_draw_eos_burst_impact_sprite`/
## `_draw_eos_burst_impact_flash_sprite`はdispatcherから完全に削除——
## 詳細は該当関数の削除コメント参照)。
const EOS_BURST_IMPACT_FLASH_SPRITE_SECONDS := 0.07  ## 経緯として残置、もう未使用
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — HIT_AT(4.63)後、
## 竜が伸びきった姿勢を保持する時間。竜残光(AFTERGLOW_START=5.25)が
## 始まるまで保持する設計で0.62秒——大型爆発(4.40〜5.45)がほぼ収まる。
## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — TIMELINE_V8.csv
## 「5.97,6.35,0.38,爆発を完全消去・振り抜きから通常待機」——VANISH_START
## (=HIT_AT+この値)がこの行の開始時刻5.97にちょうど揃うよう1.19へ更新
## (=5.97-4.78)。竜は既にFADE_END(2.50)で完全に消えており、この窓には
## 一切登場しない——定数名の「竜が到達姿勢を保ちながらフェードする時間」
## という説明は旧v7時代のもので、v8では「大型爆発が敵を覆っている間の
## 尺」という単純な意味に戻った(値はVANISH_START算出にのみ使われる)。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — TIMELINE_V12.csv
## 「4.84,6.04,1.20,v8外周と抑制した白熱核を全区間補間」——爆発本体の
## 終了時刻(=新VANISH_START)が6.04になるよう1.26へ更新(=6.04-4.78)。
## HIT_AT(4.78)・MASSIVE_START(4.84)は無改修のまま——爆発開始が着弾より
## 0.06秒後ろにずれる形は#102から継続。
## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — TIMELINE_V13.csv
## 「4.98,6.18,1.20,burst」+「6.18,6.35,0.17,cleanup」——VANISH_START(=
## HIT_AT+この値)が爆発本体の終了時刻(=新MASSIVE_END=4.98+1.20=6.18)に
## ちょうど揃うよう1.44へ更新(=6.18-4.74)。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — TIMELINE_V14
## .csv「5.02,6.22,1.20,burst」——新HIT_AT(4.78)+新MASSIVE_END(5.02+1.20
## =6.22)=1.44。HIT_AT・MASSIVE_STARTがどちらも同じ+0.04秒だけ後ろへ
## ずれたため、この値自体は偶然にも無改修のまま(1.44)で新しいVANISH_
## STARTが正しく再カスケードされる。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — TIMELINE_V15.csv
## 「4.94,6.14,1.20,burst」——新HIT_AT(4.70)+新MASSIVE_END(4.94+1.20=
## 6.14)=1.44。HIT_AT・MASSIVE_STARTがどちらも同じ-0.08秒だけ前へ
## ずれたため、この値も再び無改修のまま(1.44)で新しいVANISH_STARTが
## 正しく再カスケードされる。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 新HIT_AT(4.48)+新MASSIVE_
## END(4.72+1.20=5.92)=1.44。HIT_AT(-0.22秒)・MASSIVE_START(-0.22秒)が
## 同じ量だけ前へずれたため、この値も再び無改修のまま(1.44)で新しい
## VANISH_STARTが正しく再カスケードされる(impact/outer_burst自体の
## 長さは「維持するもの」——CHANGE_MAP_V15_TO_V16.tsvどおり無改修)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — パックはこの
## 「HIT_ATから何秒後にVANISH(消滅開始)するか」を明示していないため、
## 過去複数ラウンドの方針(v5等)と同じく「外周爆発が自分自身の演出を
## 終える瞬間とVANISH_STARTを一致させる」設計を踏襲——ハードコードでは
## なく`OUTER_START_AFTER_CONTACT_SECONDS + MASSIVE_SECONDS`という式へ
## 変更した(0.140+1.500=1.640)。これによりVANISH_START=HIT_AT+1.640は
## 数式的に必ずMASSIVE_ENDと一致する(headlessで確認)。
const EOS_BURST_IMPACT_EXPLOSION_SECONDS := \
	EOS_BURST_OUTER_START_AFTER_CONTACT_SECONDS + EOS_BURST_MASSIVE_SECONDS  ## 1.640
const EOS_BURST_IMPACT_SECONDS := EOS_BURST_IMPACT_EXPLOSION_SECONDS
const EOS_BURST_VANISH_START_SECONDS := \
	EOS_BURST_HIT_AT_SECONDS + EOS_BURST_IMPACT_SECONDS  ## 5.92
## 「エオスバーストを18:32版の自然な出現へ戻す」(2026-08-02、同日3
## ラウンド目)「竜の消滅」——ユーザーの禁止事項に明示的に含まれる
## 「縮小・分解・集合体表現による消滅」に、直前ラウンドまでの「頭→尾へ
## ディゾルブフレームを逆再生する」方式(旧`_draw_eos_burst_dragon_vanish`
## /`_eos_burst_vanish_reveal_t`)がまさに該当するため完全撤去した。
## 「竜はサイズと位置を固定したまま、約0.25〜0.35秒の単純な透明フェード
## で消す」という明示指定どおり、`_eos_burst_dragon_fade_alpha`が返す
## alpha(HOLD_ALPHA→0.0への単純smoothstep)だけで同じcomplete_texを
## 同じrectのまま描き続ける——ディゾルブ用の34フレームは一切参照しない
## (出現側でのみ引き続き使用)。
## 「Slower + New Impact v4」(2026-08-12) — README「3.78〜4.18秒:
## ソティリスはフレーム5の振り抜き姿勢を0.12秒残してから通常待機へ戻す」
## ——EXIT_ENDがちょうど4.18になるよう0.30へ調整(3.68+0.50=4.18)。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「5.45〜
## 5.95秒: ソティリスの振り抜きフレーム11を0.18秒残し、通常待機へ戻す」
## ——EXIT_ENDがちょうど5.95になるよう0.70へ調整(5.25+0.70=5.95)。
## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — TIMELINE_V8.csv
## 「5.97,6.35,0.38,爆発を完全消去・振り抜きから通常待機」——EXIT_ENDが
## ちょうど6.35になるよう0.38へ調整(5.97+0.38=6.35)。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — TIMELINE_V12.csv
## 「6.04,6.35,0.31,爆発消去・振り抜きから通常待機」——新VANISH_START
## (6.04)からEXIT_ENDが同じ6.35になるよう0.31へ再計算(=6.35-6.04)。
## EXIT_END自体の値(6.35)はv8以来無改修——結果としてDISMISS/RETURN/
## ACT_SECONDS一式(全てEXIT_ENDから連結する既存の定数チェーン)は
## この回のdiffに一切含まれない。
## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — TIMELINE_V13.csv
## 「6.18,6.35,0.17,cleanup」——新VANISH_START(6.18)からEXIT_ENDが同じ
## 6.35になるよう0.17へ再計算(=6.35-6.18)。EXIT_END自体の値(6.35)は
## v8以来ここでも無改修のまま——DISMISS/RETURN/ACT_SECONDS一式(既存の
## 定数チェーン)は今回のdiffにも一切含まれない(TIMELINE_V13.csv「6.20,
## 6.70,0.50,restore」と、この既存チェーンから自動導出されるRETURN_
## START(6.20)/RETURN_END(6.70)が偶然ではなく必然的に一致することを
## headlessで確認済み)。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — TIMELINE_V14
## .csv「6.22,6.35,0.13,cleanup」——新VANISH_START(6.22)からEXIT_ENDが
## 同じ6.35になるよう0.13へ再計算(=6.35-6.22)。EXIT_END(6.35)は今回も
## 無改修のまま——DISMISS/RETURN/ACT_SECONDS一式は今回のdiffにも一切
## 含まれず、TIMELINE_V14.csv「6.20,6.70,0.50,restore」と必然的に一致
## することをheadlessで確認する。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — TIMELINE_V15.csv
## 「6.14,6.35,0.21,cleanup」——新VANISH_START(6.14)からEXIT_ENDが同じ
## 6.35になるよう0.21へ再計算(=6.35-6.14)。EXIT_END(6.35)は今回も無改修
## のまま——DISMISS/RETURN/ACT_SECONDS一式は今回のdiffにも一切含まれず、
## TIMELINE_V15.csv「6.20,6.70,0.50,restore」と必然的に一致する。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 斬撃開始が0.22秒早まった
## ことで生まれたVANISH_START側の-0.22秒(6.14→5.92)を、「全体6.70秒で
## UIと入力を1回だけ復帰」という明示的な不変条件(プロンプトの「v15から
## 変更しないもの」に含まれる)を保つため、この定数(スラック吸収役)で
## 相殺する——新VANISH_START(5.92)からEXIT_ENDが同じ6.35になるよう
## 0.43へ再計算(=6.35-5.92)。EXIT_END(6.35)は今回も無改修のまま——
## DISMISS/RETURN/ACT_SECONDS一式(既存の定数チェーン)は今回のdiffにも
## 一切含まれない(v8以来この回で9回目、TIMELINE_V16.csv自身には無い
## 「6.20,6.70,0.50,restore」相当の値がこの既存チェーンから偶然ではなく
## 必然的に再現されることをheadlessで確認する)。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-16) — v16以来9回連続で維持
## してきた「全体6.70秒固定」というスラック吸収は、今回のパック自身の
## 【維持するもの】リストから**明示的に外れている**(README§17も参照)
## ——TIMELINE_V18.csv自身が「5.490,5.700,0.210,cleanup」という短い
## cleanup区間を明記しており、総尺自体が約6.20秒へ短縮される設計だと
## 読める。今回はTIMELINE_V18.csv自身のcleanup区間の**長さ**(0.210秒、
## impact/outer_burstと同じ「リテラル区間長をそのまま採用する」既存
## パターン)を直接採用し、6.70秒維持のための逆算はしない——新VANISH_
## START(5.52)から0.21秒後、新EXIT_ENDは5.73になる(TIMELINE自身の絶対
## 値5.700とは0.03秒差——これはSLASH_START自体がTIMELINEの近似値
## 「around 3.55」ではなく実測式由来の3.58を採用したことに由来する差分
## が、そのままここまで伝播したもの、報告に開示)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — パックは
## vanish/dismiss/return等の後始末シーケンスの尺を今回も明示していない。
## v18以来のこの巨大ファイルの慣習(「6.70秒固定」は既にv18で放棄済み、
## 以後は素直にVANISH_STARTからの妥当な一時停止として扱う)を踏襲し、
## 判断値として0.30秒(過去ラウンドの実績値0.13〜0.43秒の範囲内)を採用
## ——報告に開示。
const EOS_BURST_VANISH_FADE_SECONDS := 0.30
const EOS_BURST_EXIT_END_SECONDS := \
	EOS_BURST_VANISH_START_SECONDS + EOS_BURST_VANISH_FADE_SECONDS  ## 5.73

## Single lookup table (DragonSkillTimeline) — every draw function below
## either gates directly on the absolute-second constants above (matching
## this file's own established per-skill breakpoint-table idiom) or, for
## logging/debugging, can ask `_eos_burst_phase()` which of the 6 named
## phases is currently active. There is exactly one clock
## (_battle_anim_phase_elapsed, the shared battle sequencer tick) driving
## all of it — no independent Tween, no independent Timer.
const EOS_BURST_TIMELINE: Array[Array] = [
	[0.0, "anticipation"],
	[EOS_BURST_REVEAL_START_SECONDS, "materialize"],
	[EOS_BURST_REVEAL_END_SECONDS, "charge"],
	[EOS_BURST_BEAM_START_SECONDS, "release"],
	[EOS_BURST_HIT_AT_SECONDS, "impact"],
	[EOS_BURST_VANISH_START_SECONDS, "vanish"],
]


func _eos_burst_phase(elapsed: float) -> String:
	var result := "anticipation"
	for pair: Array in EOS_BURST_TIMELINE:
		if elapsed >= float(pair[0]):
			result = str(pair[1])
		else:
			break
	return result


## --- 「エオスバーストの攻撃主体をソティリスへ一本化」(2026-08-02、
## 同日2ラウンド目) — `_eos_burst_solve_approach_offset`(敵の実座標まで
## 歩ききる距離の算出、以前は死蔵されていた)が`_eos_burst_advance_
## offset_px`の実装として正式に採用され、Sotirisと竜が実際に敵へ接近する
## 動きへ戻った。「竜とソティリスの突きを作り直す」(2026-08-05、同日
## 追加ラウンド)——「敵の約90〜110px手前まで加速して接近」に合わせて
## 36.0→100.0(mid)へ拡大。以前より遠くで止まる分、②③(踏み込み前の溜め・
## 突き)で残りの距離を詰める設計。
const EOS_BURST_APPROACH_MARGIN_PX := 100.0  ## mid of "90-110px"
const EOS_BURST_ATTACK_AFTERIMAGE_COUNT := 2
const EOS_BURST_ATTACK_AFTERIMAGE_ALPHA := 0.16
const EOS_BURST_ATTACK_AFTERIMAGE_STEP_SECONDS := 0.035
## 「表示サイズ見直し」(2026-08-02、"SwordTipなどのアタッチ位置も新しい
## キャラクターサイズへ正しく追従させてください") — ソティリスの足元から
## 剣先までの相対位置は、キャラクター本体と同じ`ALLY_BATTLE_SCALE`で
## 一緒に伸びる(30,-34)→(45,-51)。エオスバーストは戦闘中のみ発火するため
## 条件分岐は不要——定数同士の掛け算で足りる。
const EOS_BURST_SWORD_TIP_OFFSET := Vector2(30.0, -34.0) * ALLY_BATTLE_SCALE
## 「竜とソティリスの突きを作り直す」(2026-08-05、同日追加ラウンド) —
## 旧`EOS_BURST_CHARGE_PULLBACK_PX`(8px、STRIKE_PREP窓全体でsin波形に
## 引いて戻すだけ=踏み込みが存在しなかった)を全面撤去し、②踏み込み前の
## 溜め(引く)→③突き(踏み込む、剣を最大伸長)→④保持→⑤余韻反動(戻す)の
## 4段階を持つ`_eos_burst_thrust_offset_px`へ置き換えた。ソティリス自身の
## 移動量は竜よりずっと大きい("剣を引く→踏み込む→最大まで伸ばす→反動"の
## 主役はソティリス本人、竜はそれに"遅れて"追従する別の小さな動きを持つ
## ——両者を意図的に非対称にすることで「竜が親Transformに固定されて
## 平行移動しているだけ」に見える問題を解消する)。
const EOS_BURST_THRUST_PULLBACK_PX := 6.0  ## mid of "5-7px"、②(今回のスコープ外、無改修)
## 「新しいスプライトへ置き換え」(2026-08-05、同日追加ラウンド) —
## 「スプライト自体に踏み込みが描かれているため、キャラクターノード全体の
## 前進量は18〜26px程度に抑える」——旧32px(前ラウンドの、絵に踏み込みが
## 無かった時代の値)から縮小。
const EOS_BURST_THRUST_LUNGE_PX := 22.0  ## mid of "18-26px"、③
const EOS_BURST_THRUST_RECOIL_PX := 5.0  ## mid of "4-6px"、⑤(伸びきった位置からの戻り幅、今回のスコープ外・無改修)
## 「竜も8〜12pxだけ右へ勢いを乗せ...」という旧・竜専用の水平オフセット
## (回転/伸縮撤去後の簡略版)は、「エオスバースト・煉獄型の総仕上げ」
## (2026-08-05、同日追加ラウンド)の「6枚の異なる身体姿勢を使う、rectを
## 滑らせない」方針により完全撤去した(EOS_BURST_DRAGON_LUNGE_OFFSET_PX/
## _RECOIL_PXごと削除)。
## 「剣先を少し下げます」——余韻反動中の小さな垂直方向のたわみ。範囲指定
## が無かったため判断値(反動の水平量5pxに対して控えめな比率)。今回の
## スコープ外・無改修。
const EOS_BURST_RECOIL_DIP_PX := 2.5  ## 判断値(指定なし)

## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## 竜のジオメトリ・輪郭・Core/Glow二層合成・オーラ色/明滅を記述していた
## 定数群(`EOS_BURST_DRAGON_STAGE_CANVAS`/`_STAGE_ANCHOR_PX`/`_SCALE`/
## `_REAR_LOCAL_POSITION`/`_CORE_ALPHA`/`_GLOW_ALPHA`/`_GLOW_SCALE`、
## `EOS_BURST_AURA_CORE_ALPHA`/`_RIM_ALPHA`/`_GOLD`/`_CYAN`/`_FLICKER_STEP_
## SECONDS`/`_FLICKER_LEVELS`、`EOS_BURST_OUTLINE_KEY_PREFIX`、
## `EOS_BURST_IDLE_BRIGHTNESS`)を全て完全削除した(いずれも竜描画関数群
## だけが参照していた、grep確認済み)。`EOS_BURST_COMPLETION_SHAKE_SECONDS`/
## `_PEAK_PX`(REVEAL_END到達時の汎用な小さな画面揺れトリガー、竜の geometry
## には依存しない)は生き残る呼び出し元があるため無改修のまま維持。
const EOS_BURST_COMPLETION_SHAKE_SECONDS := 0.10
const EOS_BURST_COMPLETION_SHAKE_PEAK_PX := 2.0

## --- §5/§6: 「腰を低くする、剣を身体の後ろへ引く、0.10〜0.14秒溜める」
## — the OLD "energy mass traveling within the dragon's own body, then a
## charge orb growing at the dragon's OWN mouth, handed off to the sword
## tip" concept is retired entirely this round (2026-08-05, 竜召喚モーシ
## ョンの最終構造修正) — 「攻撃起点を口へ接続」に伴い、力は口元
## (`_eos_burst_dragon_mouth_pos`)に留まったまま育ち、そこから直接発射
## される。旧`EOS_BURST_CHARGE_ORB_START_PX`/`_PEAK_PX`(剣先で育つ
## オーブ)・`EOS_BURST_HANDOFF_SECONDS`(口→剣先の受け渡し窓)は、
## §3の`EOS_BURST_MOUTH_ORB_MID_PX`/`_PEAK_PX`/`_CONVERGE_SECONDS`へ
## 置き換わり不要——値そのものも削除した。
## EOS_BURST_BODY_FLICKER_SECONDS/`_eos_burst_body_flicker` (the old
## one-shot "signal" flicker) is retired — the structured brightness ramp
## (idle -> strike-prep boost -> flight-dim -> impact peak -> idle) already
## communicates "the dragon is channelling power" without an extra ad-hoc
## pulse.
const EOS_BURST_CHARGE_SPARK_COUNT := 5
const EOS_BURST_AIM_LIGHT_SECONDS := 0.06
const EOS_BURST_CHARGE_EXTRA_DIM_ALPHA := 0.065

## --- §4「楕円光弾を竜の光撃へ変更」(2026-08-05、竜召喚モーションの最終
## 構造修正) — 前ラウンドの涙滴形spearは「単一の大きな光槍」という設計
## 自体は正しかったが、実写で「単純な楕円・カプセル型光弾」に見えると
## 再報告された(発射元が剣先/胴体下部で、竜との連携が薄いことも一因)。
## 今回は形状パラメータを新仕様(横幅170-210px・高さ38-52px・口側が細く
## 進行方向へ広がってから鋭く尖る・白コア55-65%・金縁・水色外光)へ再設計
## し、かつ発射元を口(`_eos_burst_dragon_mouth_pos`)へ接続することで
## 「竜の光撃」として一体化させた。テクスチャ生成の技法自体
## (`_eos_burst_spear_texture`、ランタイムプロシージャル生成+キャッシュ、
## `draw_set_transform`+`draw_texture_rect`の単一スタンプ)は前ラウンドの
## ものを維持——「1本の大きな図形」という核心の解決策は変えず、中身の
## 寸法/配色/発射元だけを今回の仕様に合わせた。
## 「エオスバースト最終仕上げ: 攻撃後半の完成」——「竜の全身出現・タメ・
## 接近は完成済みなので触らず、そこから先(剣からの主砲・着弾・余韻・
## 帰還)を完成させてほしい」との明示指示。主砲を全面再設計:
## ①「小さな白い葉形弾は使用しない」「ソティリスの剣先から敵まで連続して
## つながる」——旧spear(固定260x72pxの離散オブジェクトが剣元との間に常に
## 隙間を残したまま飛ぶ)を廃止し、SwordTip(生の毎フレーム位置)から着弾点
## まで実際に**伸び続ける可変長ビーム**に変更した(`_draw_eos_burst_
## breath`の全面書き換え、下記参照)。
## ②「中心:白〜明るいシアン、外側:金色」——旧配色(中心白→中間金→外周
## シアン)から反転。
## ③「ドット絵の輪郭を維持...ぼかした高解像度エフェクトは禁止」——旧実装
## はプロシージャル生成のグラデーションを`TEXTURE_FILTER_LINEAR`で滑らかに
## 見せる意図的な例外だったが、今回は明示的に禁止されたため撤去し、
## プロジェクト全体のデフォルト(NEAREST)へ統一。テクスチャ自体も低解像度
## (キャンバス24x8)で焼き、色帯も滑らかなlerpではなく数段階の塗り分けに
## することで、拡大表示時に意図的にブロック状のドット絵として見えるように
## した。
## 「太い四角形・カプセル状の光撃を削除し、剣先を原点として短い状態から
## 前方へ伸びる細長い光槍にする」(2026-08-05、同日追加ラウンド) — 旧
## HEIGHT_PXはALLY_BATTLE_SCALEから逆算した67.2pxの太い固定太さだったが、
## 今回はユーザー指定の明示px値(最大部分18-24px)に置き換え、ALLY_BATTLE_
## SCALEとは独立させた。形状は根本(8-12px)→最大(18-24px、根元寄り35%
## 地点)→先端(鋭く0)という非対称な"葉"型(`_eos_burst_spear_texture`で
## 再生成)。**MAX_LENGTH_PXは硬い上限キャップではない**——headless実測で
## ①②③(接近・溜め・突き)通過後もSwordTip-敵間の実距離が148px前後(この
## 目安の96-128pxをやや超える)になるケースを確認したため、最終到達長は
## 常に敵までの実距離(`full_length`)を使い、MAX_LENGTH_PXは「起点(10%)
## サイズ」の基準値としてのみ機能する——「敵までの実距離だけキャップして
## 隙間を残す」設計にすると、このスキルが何ラウンドも前から保護してきた
## 「剣先から敵まで連続してつながる」不変条件を壊すため、そちらを優先した。
## 「エオスバースト演出全面刷新」(2026-08-11) — 「円形の弾ではなく、
## 画面右方向へ伸びる太い光線または扇形の光波にする」との明示指示により
## 太さを大幅拡大(21px→72px)、かつ「発射直後は細く、0.10〜0.15秒で太く
## なる」を表現する専用の太さランプ(EOS_BEAM_WIDEN_SECONDS、下記
## `_draw_eos_burst_breath`で消費)を新設した。中心/内側/外側の配色は
## 「中心は白、内側は水色、外側は金色」へ再構成(旧: 白→金→水色)。
const EOS_BURST_BEAM_HEIGHT_PX := 72.0  ## 太い光の奔流(mid of "60-84px"程度、扇形基部)
const EOS_BEAM_WIDEN_SECONDS := 0.13  ## mid of "0.10-0.15秒"——発射直後、太さがここまでにフル幅へ
const EOS_BURST_SPEAR_MAX_LENGTH_PX := 112.0  ## mid of "96-128px"、起点サイズの基準値(硬い上限ではない)
const EOS_BURST_SPEAR_ROOT_FRAC := 10.0 / 21.0  ## 根元幅(mid 10px)/最大幅(mid 21px)
const EOS_BURST_SPEAR_PEAK_X_FRAC := 0.35  ## 判断値(指定なし)——最大幅の位置
const EOS_BURST_SPEAR_START_FRAC := 0.1  ## "scale.x = 0.1 -> 1.0"
## 飛翔(ビームがSwordTipから着弾点まで伸びきる)時間は、BEAM_START→HIT_AT
## という既存のチェーン(RELEASE_SECONDS)にそのまま一致させる——旧
## `EOS_BURST_SPEAR_TRAVEL_SECONDS`(0.34秒)は`HIT_AT - TRAVEL_SECONDS`
## で逆算されており、実際にはBEAM_STARTより0.22秒も前(=まだ「発射」フェーズ
## にすら入っていないタイミング)から飛び始めるという矛盾したタイミングに
## なっていた(旧スピア設計の名残、RELEASE_SECONDSが後から追加された際に
## 未調整のまま残っていたバグ)。今回はRELEASE_SECONDS自体を飛翔時間として
## 直接使うことでこの矛盾を解消する。
const EOS_BURST_BEAM_TRAVEL_SECONDS := EOS_BURST_RELEASE_SECONDS  ## == 0.12、BEAM_START..HIT_ATにちょうど一致
## 命中後の余韻: ①主砲の明るい芯を保持(「0.15-0.2秒」の下限)②細く弱く
## なりながら消える(「0.3-0.4秒」の下限)——下限同士を選んだのは、着弾
## 地点自身の残光(`EOS_BURST_IMPACT_AFTERMATH_SECONDS`)と合計0.45秒で
## ちょうど揃うようにするため(主砲の余韻と着弾地点の残光が同時に終わり、
## それから竜の消滅が始まる、という一体感のある終わり方にする判断)。
## 余韻中も「光線はSwordTipと敵の着弾地点をつないだ状態」を維持する——
## originを毎フレーム`_eos_burst_sword_tip_pos`から生で読み直す(固定
## キャッシュしない)ことでこれを満たす。
const EOS_BURST_BEAM_BRIGHT_HOLD_SECONDS := 0.15  ## mid-low of "0.15-0.2秒"
const EOS_BURST_BEAM_THIN_SECONDS := 0.30  ## mid-low of "0.3-0.4秒"
const EOS_BURST_BEAM_AFTERGLOW_SECONDS := \
	EOS_BURST_BEAM_BRIGHT_HOLD_SECONDS + EOS_BURST_BEAM_THIN_SECONDS  ## 0.45、IMPACT_AFTERMATH_SECONDSと同値
const EOS_BURST_BEAM_THIN_HEIGHT_FRAC := 0.22  ## 「細く」——薄くなった状態の残存太さ(元の22%)
## §6's own "剣先付近で大きな星状フラッシュ" — a one-shot star-burst at
## the sword tip right as release begins.
const EOS_BURST_RELEASE_FLASH_SECONDS := 0.10
## 「竜全体が一瞬強く発光する」— `_eos_burst_dragon_brightness`が
## `EOS_BURST_RELEASE_FLASH_SECONDS`と同じ窓・同じタイミングで使う
## ピーク値(1.0=命中の瞬間と同じ最大輝度、既存の序列"召喚完成<発射<
## 着弾"の"発射"段をこの一瞬だけ着弾と同じ高さまで持ち上げる判断)。
const EOS_BURST_RELEASE_FLASH_PEAK := 1.0
## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — 旧`EOS_BURST_LIGHT_
## FEED_LEAD_SECONDS`/`_TAIL_SECONDS`(竜の口から剣先へ光が流れ込む
## 装飾`_draw_eos_burst_dragon_light_feed`専用)は、その関数ごと完全に
## 削除した——詳細は同関数の削除コメント(旧位置、front_vfx dispatcher
## 直前)を参照。

## --- §5/§8: 3-stage rapid_slash-style impact, replacing the old single
## disc texture (`eos_impact`, no longer referenced anywhere) entirely.
## §3「白いXとひし形を撤去」(2026-08-05、エオスバーストの仕上げ修正) —
## the old stage 1 drew a diagonal X plus a diamond-shaped dot
## (`_fill_soul_break_dot`'s own 4-point shape IS a diamond, not a circle —
## the true source of "白い正方形またはひし形"), and stage 2 covered the
## enemy with another large diamond ("白カバー"). Both are retired
## entirely. New construction, matching the user's own numbered list:
## 1. contact: a THICK platinum CROSS (not a diagonal X — a different
##    silhouette makes it visually distinct from the retired shape) + a
##    soft round glow at the center (drawn as a filled polygon circle via
##    `_eos_burst_ellipse_points`, never `_fill_soul_break_dot`'s diamond).
## 2. burst: a gold+cyan circular shockwave (two concentric ring outlines,
##    genuinely round via `_eos_burst_ellipse_points`) PLUS the existing
## §5「着弾を召喚より強くする」(2026-08-05、竜召喚モーションの最終構造
## 修正) — ユーザー自身の着弾順リストにそのまま対応する3段階へ再構築:
## 1. contact: 直径120-150pxの白金サンバースト(放射状の光条+中心の白い
##    コア、コアは4フレーム=0.067秒)——前ラウンドの「太い十字」を撤去し、
##    より竜技らしい放射状の形へ。敵自身の白フラッシュ(3フレーム、
##    `EOS_BURST_FLASH_DECAY_SECONDS`参照)は`_battle_anim_boss_flash_t`
##    (無改修、Sprite自体のmodulateを書き換える既存機構)が別途担う。
## 2. burst: 水色の衝撃リングを1つだけ(前ラウンドの金+水色2重リングから
##    金リングを撤去)+ 金と水色の破片10-14個(点として放射、線のシャードは
##    撤去)。
## 3. aftermath: 「着弾地点の光を約0.4〜0.5秒残す」(最終仕上げラウンドで
##    0.25秒から延長)——既存の薄いリング+破片の仕組みはそのまま維持し、
##    この段階の尺だけを新しい秒数にした。
## knockback/hitstop/shake(`_fire_battle_anim_hit`)は全てこのファイルの
## 描画とは別——「2〜3フレームのヒットストップ」はEOS_BURST_HITSTOP_
## SECONDS自体を60fps換算2-3フレームへ再調整(既存の別セクション参照)。
## 「着弾を専用6コマ演出へ差し替え」(2026-08-05、同日追加ラウンド) — 上の
## 3段階の手続き描画(contactのサンバースト、burstの衝撃波、aftermathの
## 残光リング)を、ユーザーが「汎用的な白い放射状の星」「大きな白い半円
## 斬撃」と評した視覚として全廃し、新規手描き6コマ`eos_impact_burst_6f.
## png`(222×222×6)へ全面差し替えた。3関数(_draw_eos_burst_impact_
## contact/burst/aftermath)自体を削除し、単一の_draw_eos_burst_impact_
## spriteへ統合。
## 「エオスバースト・煉獄型の総仕上げ」(2026-08-05、同日追加ラウンド) —
## 「ソティリスの剣先が敵へ接触したframe3で...約0.08秒停止...停止解除と
## 同時にeos_impact_burstの最大爆発へ進める」——旧(frame1の圧縮光で
## 0.06秒)から、①トリガー地点をHIT_AT自体(接触の瞬間そのもの)へ、
## ②ヒットストップの長さを0.08秒へ、それぞれ変更。impactシート自身の
## 6コマは「解除前(圧縮光)」と「解除後(最大爆発〜余韻)」の2つの独立した
## サブフェーズへ分割し直した——elapsedはヒットストップ中HIT_ATに凍結
## されるため、frame0/1の"時間経過"は`_battle_hitstop_t`自身のカウント
## ダウン(実時間で0.08秒→0秒)を疑似クロックとして使う(elapsedに頼ると
## 凍結中は一切進行しないため)。解除後はelapsed-HIT_ATが自然に0から
## 再カウントを始める(elapsedはHIT_ATに凍結されたまま解除されるため)ので、
## 「最大爆発(frame2)から即座に開始」を追加のスキップ処理なしで実現できる。
## 「着弾の最終仕上げ」(2026-08-06、同日追加ラウンド) — 「同梱の新しい
## 透過6コマ素材`eos_impact_explosion_6f_v2.png`に変更する」——旧
## `eos_impact_burst_6f.png`から差し替え(旧ファイルは削除せず残置)。
## 新シートも6コマ・222×222で寸法は完全一致(PowerShellで実測・SHA256
## 確認済み)のため、frame数/サイズ/枠組み(圧縮光2コマ+解除後4コマの
## 2段階)自体は無改修。新シートの中身は目視確認済み: frame0=小さな星、
## frame1=やや大きい星、frame2=中規模の爆発、frame3=最大の爆発(シアンの
## 火花を含む、6コマ中最大)、frame4=減衰中の中規模爆発、frame5=飛散する
## 破片——単調増加→ピーク→減衰という一本道の構成で、旧素材が持っていた
## 円形リング状の要素は無い(「旧エフェクトの円形リングは出しません」は
## 新シート自体が既にリングを含まないことと、リングを描く独立した手続き
## コードも既に存在しないこと=grep確認済みの両方で満たされる)。
## 「着弾『大爆発』強化 v3」(2026-08-06、同日追加ラウンド) — 「同梱の
## 新しい透過6コマ素材`eos_impact_mega_explosion_6f_v3.png`に変更する」
## ——旧`eos_impact_explosion_6f_v2.png`から差し替え(旧ファイルは削除・
## 上書きしないでください、と明示指定されたため確実に残置)。新シートは
## 1フレーム384×384(旧222×222から意図的に拡大、README「新素材を222px
## 相当へ自動縮小しない」)、2304×384=384×6で寸法実測・SHA256確認済み。
## 「Slower + New Impact v4」(2026-08-12) — `eos_impact_mega_explosion_
## 6f_v3.png`(丸い巨大爆発、README「必ず撤去するもの」の1つ)を再生して
## いた`_draw_eos_burst_impact_sprite`と、その専用パス/フレームタイム
## ライン定数一式を削除した(呼び出し元も撤去、下記dispatcher参照)。
## 素材ファイル自体は削除しない(このプロジェクトの既定方針)。
## `EOS_BURST_ASSAULT_FRAME5_SECONDS`/`_FRAME4_HOLD_SECONDS`(竜/オーラ/
## ソティリスの姿勢保持タイミングが今も依存)は、旧・爆発スプライート自身
## の秒数から逆算する式をやめ、新しいタイムラインに合わせた独立リテラル
## 値へ変更した——「フレーム4(最大突進)を命中〜画面揺れ収束(0.20秒)の
## 間保持し、フレーム5(余韻)へ移る」。
const EOS_BURST_ASSAULT_FRAME4_HOLD_SECONDS := 0.20
const EOS_BURST_ASSAULT_FRAME5_SECONDS := 0.28
const EOS_BURST_IMPACT_HITSTOP_SECONDS := 0.08  ## 「現在のhitstopの値・長さ」変更禁止
## 「右方向へ約10pxのカメラキック」——単発の減衰オフセット。継続時間は
## 指定が無いため判断値(素早い一撃として0.05秒、その後§着弾7の揺れへ
## 引き継ぐ)。
const EOS_BURST_IMPACT_KICK_PX := 10.0
const EOS_BURST_IMPACT_KICK_SECONDS := 0.05
## 「着弾の最終仕上げ」(2026-08-06) で導入した、共有揺れ機構(`_battle_
## shake_offset()`)へ渡していたeos_burst専用の値。「着弾『大爆発』強化
## v3」(2026-08-06、同日追加ラウンド)で、この2つを共有機構へ渡すのを
## やめ(値を0.0へ)、代わりに専用の2D折れ線揺れ(下のEOS_BURST_MEGA_
## SHAKE_*、`_eos_burst_mega_shake_offset()`)へ完全に差し替えた——
## 「既存の弱いshakeと二重に重ねない...専用プリセットへ差し替える」を
## 文字通り実装。もう参照されないが経緯として残置(削除しない)。
const EOS_BURST_IMPACT_SHAKE_SECONDS := 0.34  ## 旧設計、もう未使用
const EOS_BURST_IMPACT_SHAKE_PEAK_PX := 14.0  ## 旧設計、もう未使用
## 「着弾『大爆発』強化 v3」(2026-08-06、同日追加ラウンド) — 「約0.44秒の
## 大きい初震→減衰する余震...大きく左右へ振り返してから減衰する」——
## README指定の11キーフレーム(経過秒, (X,Y)px)をそのまま定数化。不等間隔
## (0, 0.017, 0.050, 0.083, 0.117, 0.155, 0.205, 0.260, 0.325, 0.390, 0.440)
## のため、`_eos_burst_mega_shake_offset()`が折れ線補間で処理する。
## 1152×648基準・X最大30px/Y最大18px(いずれもテーブル自身の値、追加の
## スケーリングはしない)。最後のキーフレームは(0,0)——「終了・中断時には
## 必ず開始前offsetへ完全復帰」を、テーブル自身の終端値として保証する
## (復帰用の別ロジックは不要)。
## 「Professional Mix / Impact Polish v1」(2026-08-07) — README「contact
## 1発目に最大級のkick...以降のamplitudeは`pow(1.0-u, 2.0)`相当で急減衰」
## に合わせ全面再計算。旧テーブルは1発目(28,-16)より2発目(-30,18)の方が
## 大きく("最初の1発を最大級に"と矛盾)、減衰形状も検証されたpow(1-u,2)
## カーブそのものではなかった。新テーブルは①ピークをt=0.000の1発目へ
## 移動(旧テーブルの実測最大30.0/18.0はそのまま維持、"最大振幅を今以上に
## 増やさない"を満たす)②各キーフレームの時刻(旧テーブルと完全同一の
## 11点、0.000〜0.440秒)ごとに`envelope := pow(1.0 - t/0.440, 2.0)`を
## 計算し、X=30.0*envelope・Y=18.0*envelope(小数第1位で丸め)を符号
## 交互(旧テーブルと同じ交互パターン)で配置——`pow(1-u,2)`という連続
## 関数の値をそのままテーブル化したものであり、恣意的な手打ち数値ではない
## (envelope値: 1.000/0.925/0.786/0.658/0.539/0.420/0.285/0.167/0.068/
## 0.013/0.000、`t/TOTAL_SECONDS`から直接算出・headless検証で再確認済み)。
## 決定論的な折れ線のまま(ランダム要素は追加していない、「毎frame同じ
## 強さのrandom quakeは禁止」は元々ランダム自体が無いことで満たされていた
## ——今回は形状の修正のみ)。
## 「Slower + New Impact v4」(2026-08-12) — README「3.20〜3.40：画面揺れ。
## 最初の0.08秒は強め、その後0.12秒で減衰。最大振幅は6px」——旧・約0.44秒
## /最大30px(丸い巨大爆発向けに調整済みだった値)を全面差し替え。0.00〜
## 0.08秒は最大振幅6.0px(envelope=1.0)を交互の符号で保持、0.08〜0.20秒は
## 同じ`pow(1.0-u,2.0)`カーブ(u=(t-0.08)/0.12)で0まで減衰——上の「大爆発」
## ラウンドで確立した"恣意的な手打ち数値ではなくpow(1-u,2)から計算する"
## 方針をそのまま踏襲。X:Y比は旧テーブルと同じ約5:3。最後のキーフレームは
## (0,0)——「終了・中断時には必ず開始前offsetへ完全復帰」を保証。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「4.45〜
## 4.75秒：画面揺れ。最初の0.10秒は8px、その後0.20秒で0pxへ減衰。座標は
## 整数丸め」——0.00〜0.10秒は最大振幅8.0px(envelope=1.0)を交互の符号で
## 保持、0.10〜0.30秒は同じ`pow(1.0-u,2.0)`カーブ(u=(t-0.10)/0.20)で0まで
## 減衰(envelope値: 0.64/0.36/0.16/0.04/0.000、t/TOTAL_SECONDSから算出)。
## 「絶対時刻4.45秒開始」は、旧v3/v4の"contact_trigger基準"(ヒットストップ
## 解除の瞬間)とは異なる新しい要求——4.45はダメージ発生(HIT_AT=4.63)
## より0.18秒前であり、hitstop解除を待つ設計では表現できないため、
## 下記`_eos_burst_mega_shake_offset()`自体をEOS_BURST_SHAKE_START_
## SECONDS基準の絶対時刻ゲートへ作り直した(旧6px/0.44秒版の履歴も含め
## 経緯としてこの上のコメント群は残置)。
## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — TIMELINE_V8.csv「4.97,
## 5.31,0.34,強→中→弱へ減衰する画面揺れ」、プロンプト「4.97秒ピークを
## 1.0とし、0.34秒で0へ減衰。最初0.08秒だけ強、次0.10秒中、残りは弱」——
## 3段階の明示的な秒数指定(0.08/0.10/0.16=0.34)に合わせ、単一の
## pow(1-u,2)減衰(旧v5〜v7、0.30秒)から作り直した。①強(0.00〜0.08秒)
## は振幅を維持したまま交互に振動(旧テーブルと同じパターン)②中
## (0.08〜0.18秒)はenvelope=1.0→0.35へ線形減衰(frac=(t-0.08)/0.10、
## env=1.0-0.65*frac)③弱(0.18〜0.34秒)はenvelope=0.35→0へpow(1-u,2)
## 減衰(u=(t-0.18)/0.16、env=0.35*pow(1-u,2))——3段階とも計算式から
## 直接導出した値であり、恣意的な手打ち数値ではない。ピーク振幅
## (8.0px/4.8px)自体はv8で新しい数値指定が無いため前ラウンド(v7)の値を
## そのまま継続(判断値として報告に開示)。最後のキーフレームは(0,0)——
## 「終了・中断時には必ず開始前offsetへ完全復帰」を保証。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — TIMELINE_V12.csv
## 「4.84,5.46,0.62,画面揺れを強から弱へ単調減衰」。START_SECONDSを新
## MASSIVE_START_SECONDS(4.84)へ揃え、合計を0.34→0.62秒(比率0.62/0.34
## ≈1.823529)へ延長。README・CLAUDE_CODE_PROMPT_JA.txtとも新しい個別
## キーフレーム値・振幅の指定が無いため、既存の13点の**時刻だけ**を
## この比率で一律スケールし、振幅(Vector2の値)・強→中→弱という形状・
## 「途中で再び強くしない」単調減衰は無改修のまま維持する判断とした
## (v8時代に確立した「新数値指定が無ければ前ラウンドの値を維持」判断を
## 踏襲、報告に開示)。最後のキーフレーム(0,0)は比率を掛けても厳密に
## 0.620(=0.34*0.62/0.34)になる——「終了・中断時には必ず開始前offsetへ
## 完全復帰」は無改修のまま保証される。
## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — 新MASSIVE_START_
## SECONDS(4.98)へ揃えた(旧4.84から変更、他の値・形状は無改修)。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — 新MASSIVE_
## START_SECONDS(5.02)へ揃えた(旧4.98から変更、他の値・形状は無改修)。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — 新MASSIVE_START_
## SECONDS(4.94)へ揃えた(旧5.02から変更、他の値・形状は無改修)。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 新MASSIVE_START_SECONDS
## (4.72)へ揃えた(旧4.94から-0.22秒、他の値・形状は無改修)。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-16) — 新MASSIVE_START_
## SECONDS(4.32)へ揃えた(旧4.72から-0.40秒、他の値・形状は無改修)。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — MASSIVE_START_
## SECONDSが手打ちリテラルからimpact重複を含む派生式へ変わったため、
## こちらもリテラル値の追従ではなく`EOS_BURST_MASSIVE_START_SECONDS`への
## 直接参照へ変更(値自体は無改修のまま自動的に一致し続ける)。
const EOS_BURST_SHAKE_START_SECONDS := EOS_BURST_MASSIVE_START_SECONDS
const EOS_BURST_MEGA_SHAKE_KEYFRAMES: Array = [
	[0.000, Vector2(8.0, -4.8)],
	[0.036, Vector2(-8.0, 4.8)],
	[0.073, Vector2(8.0, -4.8)],
	[0.109, Vector2(-8.0, 4.8)],
	[0.146, Vector2(8.0, -4.8)],
	[0.191, Vector2(-6.7, 4.0)],
	[0.237, Vector2(5.4, -3.2)],
	[0.283, Vector2(-4.1, 2.5)],
	[0.328, Vector2(2.8, -1.7)],
	[0.401, Vector2(-1.6, 0.9)],
	[0.474, Vector2(0.7, -0.4)],
	[0.547, Vector2(-0.2, 0.1)],
	[0.620, Vector2(0.0, 0.0)],
]
const EOS_BURST_MEGA_SHAKE_TOTAL_SECONDS := 0.620  ## last keyframe's own time
## 「最大不透明度は約0.40、立ち上がり0.02秒、消えるまで0.12秒。UIは
## 光らせない」——既存の共有_battle_screen_flash_t(1tick矩形フラッシュ、
## 立ち上がり/減衰の形状を持たない)とは別に、専用のランプ形状を持つ
## 新しい画面フラッシュを追加した。draw_rect(view, ...)——viewは戦闘
## ビュー矩形自身であり、UI/ボタンパネルは元々このrect外なので「UIは
## 光らせない」は描画範囲そのもので自動的に満たされる。
## 「着弾『大爆発』強化 v3」(2026-08-06、同日追加ラウンド) — 「白い時間を
## 長くする＝迫力ではない...短い閃光と、その直後に残る巨大な爆発の
## コントラストで重さを出す」——旧0.40/0.02s立ち上がり/0.12s消滅は
## 大爆発と重なる時間が長すぎたため、①PEAKを0.65(mid of "0.60-0.70")へ
## 引き上げ②RISEを0.0(接触と同一フレームで即ピーク、"立ち上がり"自体を
## 廃止)③TOTALを0.033秒(60fps換算ほぼ2フレーム、"+2〜3fまでに0へ")へ
## 大幅短縮。既存の関数(`_eos_burst_impact_flash_alpha`)自体は無改修——
## RISE=0.0だと`age < RISE`が常にfalseになり自然にdecay分岐だけを通る
## ため、コード変更なしで「即ピーク→急減衰」の形になる。headless実測で
## age=1/60秒(1フレーム後)のalphaが0.25-0.35の範囲内(≈0.32)、
## age>=TOTALで0になることを確認済み。
## 「Professional Mix / Impact Polish v1」(2026-08-07) — README「最も白い
## 状態はengine側1 rendered frame程度、そこから45〜60msで急fade...全画面
## overlayの最大alphaを0.50〜0.60から開始」を反映し、①PEAKを0.65→0.55
## (mid of "0.50-0.60")②即ピーク後、1 rendered frame(60fps基準
## 1/60≈0.0167秒)だけそのまま保持する明示的なHOLD区間を新設(旧RISE=0.0の
## 「同一フレームで即ピーク」自体は維持、ただし旧実装はそのままdecayへ
## 突入していたため"1フレーム保持"が無かった)③そこから
## DECAY_SECONDS=0.0525秒(mid of "45-60ms")で0へ滑らかに減衰。
## 「現行ソティリス維持版 v3」(2026-08-12) — README「白黒反転は60fpsで
## 1〜2フレームだけ」——このプロジェクトはeos_burst用にシェーダーを
## 導入しない方針(過去ラウンドの確立済み判断)のため、真の色反転ではなく
## 既存の白フラッシュ機構を強め(peak alpha上昇)、保持を2フレーム
## (0.033秒)へ延ばすことで近似する——報告書に明記。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — TIMELINE_V12.csv
## 「4.78,4.90,0.12,短い画面フラッシュを滑らかに減衰」——合計を0.0855→
## 0.12秒へ延長。HOLD(2 rendered frames @60fps、確立済みの固定アンカー
## 値)は無改修のまま維持し、DECAYだけを0.12-0.033=0.087秒へ再計算。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「接触drawから同時にscreen-space白ColorRectのflashを開始します。
## rise:0.035秒、alpha0→0.50。fall:0.115秒、alpha0.50→0。合計0.150秒。
## 旧来の遅延Tween、delayed callback、ほぼ全白の強いflashは削除」——
## 参照実装`play_contact_flash`と同じ「即ピーク保持」ではなく「立ち上がり
## →減衰」の2段Smootherstep envelopeへ全面書き換えた(旧HOLD+DECAY方式は
## 「同一フレームで即座に最大alphaへ達しそのまま数フレーム保持」する形
## だったが、v20は最大alphaへ**滑らかに立ち上がる**ことを明示的に要求)。
## トリガー機構自体(接触の瞬間に記録される`_eos_burst_contact_trigger_
## elapsed`基準点、下記`_eos_burst_impact_flash_alpha`)は無改修——
## 「delayed Tween/callbackを使わない」という要求は元からこの一回性
## マーカー方式で満たされていたため変更不要。ピークalphaも0.85→0.50
## (README「ほぼ全白の強いflashは削除」を、ピーク自体を弱めることで反映)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「contact
## flash：rise 0.050秒、fall 0.150秒、peak alpha0.42」。
const EOS_BURST_IMPACT_FLASH_PEAK_ALPHA := 0.42
const EOS_BURST_IMPACT_FLASH_RISE_SECONDS := 0.050
const EOS_BURST_IMPACT_FLASH_FALL_SECONDS := 0.150
const EOS_BURST_IMPACT_FLASH_TOTAL_SECONDS := \
	EOS_BURST_IMPACT_FLASH_RISE_SECONDS + EOS_BURST_IMPACT_FLASH_FALL_SECONDS  ## 0.200
## 「敵を右へ20〜26pxノックバック」——既存の共有デフォルト
## (BATTLE_KNOCKBACK_PX=18.0)を超えるため、今回はeos_burst専用の明示的な
## 上書き値を`_fire_battle_anim_hit`へ渡す。
const EOS_BURST_KNOCKBACK_PX := 23.0  ## mid of "20-26px"
## 「Professional Mix / Impact Polish v1」(2026-08-07) — README §C「着弾
## 直前55msだけ『吸い込み』」。時刻はいずれもAPPROACH_START基準の相対秒
## (README自身の"t"表記そのまま)——`EOS_BURST_HIT_AT_SECONDS`が定数チェーン
## により厳密に`APPROACH_START+APPROACH_SECONDS(0.42)`と一致することを
## 確認済みのため、"t=0.420"はHIT_AT(=hitstop開始)を指す。ただし実際の
## damage/巨大爆発/flash/shakeはhitstop解除の瞬間(`_eos_burst_assault_
## released()`、HIT_ATから約`EOS_BURST_IMPACT_HITSTOP_SECONDS`=0.08秒後)
## に発火する——「damage timing、既存hitstopは変更しない」という保護
## リストのため、duckの「解除」自体はREADMEの文字通りのt=0.420ではなく、
## この既存の・保護された実contactイベントを基準にする(README自身の
## 「既存のdamage+explosion+hitstopが発火する実contactイベントを基準に
## する」という上位方針を、t=0.420という個別の数字より優先した判断)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17、パック自身は
## 音声に触れていないが、この回が変更するAPPROACH_SECONDS/THRUST_LUNGE_
## SECONDSがまさにこの2定数の計算基盤であるため、開示付きの巻き添え
## 修正として実施) — 旧値(0.350/0.405)は「APPROACH_START から0.35秒後に
## duckし、そのまま接触までずっと保持する」という設計で、v20時点の短い
## windup(接触までt_rel≈4.70)では"接触前の大半をhushする"という意図に
## そこそこ合っていたが、v21でwindupが2.64秒(character全体)まで伸びた
## ことで、"windupの序盤0.35秒だけ通常、残り約87%をずっとhushしたまま"
## という、明らかに意図とズレた挙動になるところだった。「短い55msの
## ランプ→接触の少し前でduck完了」という元の"音の形"自体は変えず、
## 位置だけを新しい(はるかに遅い)接触点の直前へ再アンカーした——
## `EOS_BURST_HIT_AT_SECONDS`(接触の絶対時刻)から`APPROACH_START_
## SECONDS`を引いたt_rel値を終点とし、そこから元のランプ長(0.055秒=
## 旧0.405-0.350)だけ遡った点を開始点とする式へ作り直した。
const EOS_BURST_DUCK_RAMP_SECONDS := 0.055  ## 旧設計のランプ長(0.405-0.350)を維持
const EOS_BURST_DUCK_RAMP_END_SECONDS := \
	EOS_BURST_HIT_AT_SECONDS - EOS_BURST_APPROACH_START_SECONDS  ## 接触のt_rel(=2.380)
const EOS_BURST_DUCK_START_SECONDS := \
	EOS_BURST_DUCK_RAMP_END_SECONDS - EOS_BURST_DUCK_RAMP_SECONDS  ## 2.325
const EOS_BURST_DUCK_PEAK_DB := -7.0
const EOS_BURST_DUCK_RECOVER_SECONDS := 0.140  ## mid of "120-160ms"
## 「タメ中の背景暗転は維持し、最大爆発の瞬間から通常の明るさへ戻す」
## ——解除の瞬間(`_eos_burst_assault_released()`)をトリガーに変更、
## フェード自体はこの専用の短い固定秒数(判断値、暗転解除の速さの指定は
## 無いため)。
## 「Slower + New Impact v4」(2026-08-12) — `_draw_eos_burst_dim`が
## RETURN_START/RETURN_SECONDS基準の解除へ変更されたため、この定数は
## もう未使用(経緯として残置、削除しない)。
const EOS_BURST_IMPACT_DIM_RELEASE_SECONDS := 0.12  ## 旧設計、もう未使用

## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## `EOS_BURST_MANIFEST_DIR`/`_FRAME_COUNT`/`_FRAME_DURATIONS`・`EOS_BURST_
## IDLE_DIR`/`_FRAME_COUNT`/`_FRAME_SECONDS`・`EOS_BURST_DRAGON_FADE_START_
## SECONDS`/`_FADE_SECONDS`/`_FADE_END_SECONDS`を全て完全削除した(いずれも
## `_eos_burst_manifest_frame_texture`/`_eos_burst_idle_frame_texture`/
## `_eos_burst_idle_frame_index`/`_eos_burst_dragon_fade_mult`(全て削除済み)
## だけが参照していた、grep確認済み)。実素材(`dragon_manifest_safe/`・
## `dragon_idle_safe/`)は削除しない、既定方針どおり。
## 旧・charge_auraのタメ延長ループ([2,3,4,3]、0.09秒/コマ)は
## 「プロフェッショナル・ポリッシュ」ラウンド(2026-08-06)の「6コマを
## ループさせず0→5へ一方向に成長させる」明示指示により削除した——
## `git log`で経緯を参照可能。
## §「必要なるものは維持する」— frame0(0.10)+frame1(0.08)+frame2(0.06、
## 頭が飛び出す動作)+光槍飛翔(EOS_BURST_RELEASE_SECONDS=0.06、frame2の
## ポーズのまま見せる)+ヒットストップ0.08秒(elapsed空間では0秒——elapsed
## はHIT_ATに凍結されるため、ここでの合計には寄与しない)+解放後の
## frame4/5(EOS_BURST_IMPACT_POST_RELEASE_TOTAL_SECONDS=0.43)。elapsed
## 空間での合計は0.10+0.08+0.06+0.06+0.43=0.73秒——`_draw_party_row`の
## icon override窓の終了点として使う(旧EOS_BURST_THRUST_TOTAL_SECONDS
## =0.51秒から拡張)。
## 「エオスバースト演出全面刷新」(2026-08-11) — 旧・固定リテラル合計
## (0.73秒、旧RELEASE_SECONDS=0.06基準で組まれていた)は今回のRELEASE_
## SECONDS大幅延長(0.80秒、光撃本体の飛翔時間)に追従しないため、実際の
## 定数への参照へ作り直した——スイング開始(STRIKE_PREP)から着弾演出
## (IMPACT)終了まで、専用の6コマ突きスプライトを表示し続ける。
const EOS_BURST_ASSAULT_TOTAL_SECONDS := \
	EOS_BURST_STRIKE_PREP_SECONDS + EOS_BURST_THRUST_LUNGE_SECONDS \
		+ EOS_BURST_RELEASE_SECONDS + EOS_BURST_IMPACT_SECONDS  ## 1.31
## 「竜の接近モーション修正」(2026-08-06) — 上のASSAULT_TOTAL_SECONDSは
## STRIKE_PREP_START(到着)起点の長さ(elapsed空間で0.73秒)。icon override
## 窓が接近そのものもカバーするよう起点をAPPROACH_START(移動開始)へ前倒し
## したため、窓の長さにもAPPROACH_SECONDSの分だけ足す必要がある——中身は
## 変えず起点だけ動かすので、単純にAPPROACH_SECONDSを加算するだけでよい。
const EOS_BURST_ASSAULT_ICON_WINDOW_SECONDS := \
	EOS_BURST_APPROACH_SECONDS + EOS_BURST_ASSAULT_TOTAL_SECONDS  ## 1.11

## --- §「必殺技中の画面演出」(2026-08-05、同日追加ラウンド) — 「常に
## 戦闘画面全体と下部UIが見えているため、必殺技が小さく見える」への対応。
## ①下部のコマンド・仲間カードUI(`_battle_bar`)をalpha 0.15まで薄くする
## (上部の敵HPバー`_boss_banner`は別ノードのため無改修のまま残る)②
## カメラを1.08倍まで寄せる(このファイルにズーム機構は前ラウンドまで
## 存在しなかった——前ラウンドの着弾限定の1.025xパルスは今回のこの
## 持続的な1.08xズームに完全に置き換わる、旧EOS_BURST_IMPACT_ZOOM_PEAK/
## _SECONDSは削除)。どちらも同じ0.15秒の立ち上がりを共有。
const EOS_BURST_UI_DIM_ALPHA := 0.15
const EOS_BURST_UI_DIM_IN_SECONDS := 0.25  ## 「0.00-0.25秒: 入力停止、画面を暗くする」と揃える(v5)
const EOS_BURST_ZOOM_SCALE := 1.08
const EOS_BURST_ZOOM_IN_SECONDS := 0.15  ## 「約0.15秒で」(UI dimと同時)
## 「突進frame2〜4の間だけ、戦闘背景へ8〜12本程度の横長ドット速度線」
## ——右から左へ、太さ2〜4px、金/白/少量シアン、整数座標、ぼかし・
## アンチエイリアス禁止。本数は「8-12本程度」の中央値、太さは1本ごとに
## 2-4pxの範囲でばらつかせる(判断値、単調にならないための可変幅)。
const EOS_BURST_SPEED_LINE_COUNT := 10
const EOS_BURST_SPEED_LINE_MIN_THICKNESS_PX := 2.0
const EOS_BURST_SPEED_LINE_MAX_THICKNESS_PX := 4.0
const EOS_BURST_SPEED_LINE_MIN_LENGTH_PX := 70.0
const EOS_BURST_SPEED_LINE_MAX_LENGTH_PX := 150.0
const EOS_BURST_SPEED_LINE_CYCLE_SECONDS := 0.30  ## 判断値——1本が画面を横切る速さ

## --- §6 (retired this round, see the note at EOS_BURST_VANISH_START_
## SECONDS above): the chunk-based vanish assets (eos_dragon_chunk_vanish_
## <0..9>.png, baked by gen_chunk_frames.gd) are no longer loaded anywhere
## — left on disk unreferenced per this project's own convention of never
## deleting delivered/generated art. If a block-style dissolve is ever
## wanted again for a DIFFERENT effect, `git log` has the full bake script
## and the draw code that used to consume it.

## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の足元フレア
## (`EOS_BURST_GROUND_LIGHT_ALPHA`/`_SHRINK`/`_RX`/`_RY`、唯一の消費者
## だった`_draw_eos_burst_ground_glow`と一緒に完全削除)を完全削除した。

## --- Screen dim (fades in across ANTICIPATION). 「タメ中は戦闘世界だけを
## 約55〜60%まで暗くする」(2026-08-05、同日追加ラウンド、旧0.34から
## 更新)——"Xまで暗くする"を「黒のオーバーレイalpha a に対し明るさは
## (1-a)」という関係で逆算(1-0.575≈0.425、55-60%の中央値から)。フェード
## 解除の条件はDIM_IN後の`_eos_burst_assault_released()`(下記参照)へ
## 変更。
## 「エオスバースト演出全面刷新」(2026-08-11) — 「背景とカットイン外の
## 戦闘画面は通常の約35%の明るさまで暗くしてください」——alpha=1-0.35。
## 立ち上がりも0.30秒(第1段階そのもの)へ延長。
const EOS_BURST_DIM_ALPHA := 0.65  ## 1-0.35 (35%の明るさまで暗く)
## 「Slower + New Impact v4」(2026-08-12) — README「0.00〜0.18秒: 入力
## 停止、戦闘画面を暗くする」——0.12→0.18秒。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「0.00〜
## 0.25秒: 入力停止、画面を暗くする」——0.18→0.25秒。
const EOS_BURST_DIM_IN_SECONDS := 0.25

## --- Hit-feel. 「敵を右へ20〜26pxノックバック」は上のEOS_BURST_
## KNOCKBACK_PXで新規に明示上書き(既存デフォルトBATTLE_KNOCKBACK_PX=
## 18.0を超えるため)。「敵を1〜2フレームだけ白く発光」(2026-08-05、
## 同日追加ラウンド、旧「3フレーム」から短縮)——60fps換算1.5フレーム
## (中央値)。ヒットストップ・共有揺れの秒数/振幅・画面フラッシュの
## alphaはEOS_BURST_IMPACT_*(上の着弾セクション参照)。
const EOS_BURST_FLASH_DECAY_SECONDS := 0.025  ## "敵の白フラッシュ：1-2フレーム" at 60fps (mid=1.5f)

## --- Post-vanish: Sotiris's own return-to-formation (his OWN mechanic,
## untouched — only retimed to start immediately once the dragon has
## genuinely finished vanishing, EOS_BURST_EXIT_END_SECONDS, rather than
## the old ~1.3s-later handoff).
## 「現行ソティリス維持版 v3」(2026-08-12) — 今回のREADMEはソティリスの
## 移動を一切含まない(現在の座標のまま演出が完結する)ため、この"歩いて
## 戻る"別メカニズム自体が不要になった——GAP/DISMISSは0へ(帰還すべき
## 移動が無いため)、RETURNだけUI dim復帰の滑らかさのため短く残す。
## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — TIMELINE_V8.csvは
## 「5.97,6.35,...爆発を完全消去・振り抜きから通常待機」と「6.20,6.70,
## ...画面・UI・入力復帰」という2行が0.15秒重なる(6.20〜6.35)設計——
## UI/入力の復帰は、Sotirisの振り抜き姿勢が完全に通常待機へ戻り切る
## (EXIT_END=6.35)より0.15秒早く始まる。既存の「RETURN_START=DISMISS_
## END=EXIT_END+GAP+DISMISS」という定数チェーンはそのまま使い、GAPへ
## 負の値(-0.15)を入れるだけでこの意図的な重なりを表現する——新しい
## 独立したタイムライン変数を増やさない。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-16) — TIMELINE_V18.csvの
## cleanup行(5.490,5.700)とrestore行(5.700,6.200)はぴったり隣接して
## おり、v8以来続いてきた0.15秒の重なり演出がこの回のパックには存在
## しない(【維持するもの】にも言及なし)——GAPを0.0へ戻し、UI/入力の
## 復帰はSotirisの振り抜き姿勢が通常待機へ戻り切るのと同時に始まる形へ
## 単純化した。
const EOS_BURST_DISMISS_GAP_SECONDS := 0.0
const EOS_BURST_DISMISS_SECONDS := 0.0
const EOS_BURST_DISMISS_START_SECONDS := \
	EOS_BURST_EXIT_END_SECONDS + EOS_BURST_DISMISS_GAP_SECONDS
const EOS_BURST_DISMISS_END_SECONDS := \
	EOS_BURST_DISMISS_START_SECONDS + EOS_BURST_DISMISS_SECONDS
## RETURN_STARTは上のDISMISS_END(=新EXIT_END、5.73)からそのまま自動
## 追従。RETURN_SECONDS(0.50)自体はTIMELINE_V18.csvの「5.700,6.200,
## 0.500,restore」行の区間長と厳密に一致しており、今回も無改修——上流
## (HIT_AT以前)のタイミングがどれだけ動いても、この「復帰演出自体に
## かかる長さ」は一貫して0.50秒のまま変わらないという、v14以来何度も
## 確認されてきたこの定数の安定性を今回も裏付ける形になった。
const EOS_BURST_RETURN_SECONDS := 0.50
const EOS_BURST_RETURN_START_SECONDS := EOS_BURST_DISMISS_END_SECONDS
const EOS_BURST_RETURN_END_SECONDS := \
	EOS_BURST_RETURN_START_SECONDS + EOS_BURST_RETURN_SECONDS  ## 6.23(v18、旧6.70から短縮)
const EOS_BURST_ACT_SECONDS := EOS_BURST_RETURN_END_SECONDS + 0.04
const EOS_BURST_POST_ACT_GAP_SECONDS := 0.15
## 「タメ中の背景暗転は維持し、最大爆発の瞬間から通常の明るさへ戻す」
## (2026-08-05、同日追加ラウンド) — 固定elapsedしきい値ではなく
## `_eos_burst_assault_released()`(ヒットストップが解除された瞬間)を
## トリガーに変更(`_draw_eos_burst_dim`側で直接判定、下記参照)——
## 「最大爆発」は解除された瞬間に現れるものであり、接触(HIT_AT)自体の
## 瞬間ではないため、固定elapsed定数では表現できない。

## --- Rim/afterimage cosmetics on Sotiris himself during the rush (his own
## readability aid, mechanism untouched). §3: widened/darkened slightly for
## stronger contrast against the now much larger, brighter dragon behind
## him ("剣士の姿と構えが読みにくい").
const EOS_BURST_RIM_PX := 2.6
const EOS_BURST_RIM_FLASH_SECONDS := 0.06

## 「エオスバーストを18:32版の自然な出現へ戻す」(2026-08-02、同日3
## ラウンド目) — 旧"soul light"の尾→頭パス(EOS_BURST_SOUL_LIGHT_PATH/
## _LEGACY_CANVAS、`_eos_burst_path_point_for_progress`とその補助2関数)
## は、以前これを消費していたlunge light band・vanish tail dot・
## surge-to-tipが全ラウンドにわたって撤去された結果、呼び出し元が1つも
## 無くなったため削除した(単なる未使用データではなく、もう存在しない
## 演出専用の座標変換ロジックだったため、アセットではなくコードとして
## 削除対象と判断)。

## Reusable skill-motion phase vocabulary (added in an earlier round for
## FUTURE skills to opt into; NOT used by eos_burst's own dedicated
## DragonSkillTimeline above, which uses its own vocabulary matching the
## user's own spec verbatim — kept here unchanged, zero behavior risk).
enum UDSkillMotionPhase {
	APPROACH, ANTICIPATION, RELEASE, TRAVEL, IMPACT, RECOVERY, RETURN,
}


func _skill_phase_for_elapsed(
		breakpoints: Array[Array], elapsed: float,
		default_phase: UDSkillMotionPhase) -> UDSkillMotionPhase:
	var result := default_phase
	for pair: Array in breakpoints:
		if elapsed >= float(pair[0]):
			result = pair[1]
		else:
			break
	return result


## Actor frames over the shared attack_minion_N clip — mechanism untouched
## ("キャラクターは別管理のまま変更しない"). §1/§2/§4 (this round)
## extended almost every upstream duration this table depends on, so it's
## now expressed as const-chain REFERENCES rather than hand-computed
## literals (this file's own "single source of truth" idiom — avoids the
## kind of silent literal-drift this skill has repeatedly had to debug).
## 「新しいスプライトへ置き換え」(2026-08-05) — 突き(②踏み込み前の溜め
## 〜⑤余韻)は`_draw_party_row`側で専用の`skill_minion_0_eosthrust`6コマ
## へ`icon`を直接差し替えるため、この表自身が②③④⑤の細かい折れ線を持つ
## 必要は無い(`icon`が上書きされている間はこの表の値を一切参照しない
## ため無害だが、死んだ複雑さを残さないため削除)。①タメ(frame0→1→2)は
## 無改修。「エオスバースト・煉獄型の総仕上げ」(2026-08-05、同日追加
## ラウンド) — icon override窓の終了点(`STRIKE_PREP_START_SECONDS+
## EOS_BURST_ASSAULT_TOTAL_SECONDS`)が、新しいタイミング構造の結果として
## `EOS_BURST_VANISH_START_SECONDS`とちょうど同じ瞬間になった(headless
## 検証で確認済み)——旧・frame4への一度だけのbaton-passエントリは、
## その直後の`[VANISH_START,5]`エントリと同時発火になり実質可視時間ゼロ
## のため削除した(overrideが終わった直後、間を置かずframe5が見える)。
const EOS_BURST_ACTOR_FRAMES: Array[Array] = [
	[0.00, 0],
	[EOS_BURST_SUMMON_PULLBACK_SECONDS, 1],
	[EOS_BURST_SUMMON_PULLBACK_SECONDS + EOS_BURST_SUMMON_CHARGE_SECONDS, 2],
	[EOS_BURST_VANISH_START_SECONDS, 5],
	[EOS_BURST_RETURN_START_SECONDS, 6],
	[EOS_BURST_RETURN_END_SECONDS, 0],
]

func _enter_battle_anim_act_phase(entry: Dictionary, unit_id: int) -> void:
	_battle_anim_phase = "act"
	_battle_anim_phase_elapsed = 0.0
	_battle_anim_frame_index = 0
	_battle_anim_hit_fired = false
	var art_variant := _minion_art_variant(unit_id)
	var is_skill := str(entry.get("action", "")) == "skill"
	if is_skill and str(entry.get("skill_id", "")) == RAPID_SLASH_SKILL_ID:
		# 2026-07-26 v3: back to the shared attack_minion_N clip (user spec
		# — see RAPID_SLASH_ACTOR_FRAMES' doc comment for why the dedicated
		# skill_actor_rapidslash clip from the 2026-07-24 stage was dropped).
		# The phase itself runs RAPID_SLASH_POST_ACT_GAP_SECONDS longer than
		# the performance needs — both timing functions already hold at
		# their last breakpoint for any elapsed time past it.
		_battle_anim_motion_key = "attack_minion_%d" % art_variant
		_battle_anim_act_seconds = RAPID_SLASH_ACT_SECONDS + RAPID_SLASH_POST_ACT_GAP_SECONDS
		_rapid_slash_waves = []
		for wave_def: Dictionary in RAPID_SLASH_WAVE_DEFS:
			_rapid_slash_waves.append({
				"key": str(wave_def["key"]), "label": str(wave_def["label"]),
				"launch_time": float(wave_def["launch"]), "arrive_time": float(wave_def["arrive"]),
				"draw_px": float(wave_def["draw_px"]), "y_offset": float(wave_def["y_offset"]),
				"recoil_px": float(wave_def["recoil_px"]),
				"active": false, "arrived": false,
				"start_pos": Vector2.ZERO, "target_pos": Vector2.ZERO,
				"progress": 0.0, "rotation": 0.0, "animation_frame": 0,
				"spark_t": 0.0,
			})
		_rapid_slash_impact_started = false
		_rapid_impact_active = false
		_rapid_impact_elapsed = 0.0
		_rapid_charge_active = false
		_rapid_recoil_t = 0.0
		_rapid_recoil_peak_px = 0.0
		_rapid_debris_t = 0.0
		_rapid_sfx_sparks_played = false
		_rapid_slash_debug_log_counts = {}
		# README: "rapidslash_move.wav | 中央へ踏み込む風切り音 | 0.00秒" —
		# this branch only ever runs once per act-phase entry, already a
		# natural one-shot event (no extra guard needed).
		_play_rapid_sfx("move")
		return
	if is_skill and str(entry.get("skill_id", "")) == HEALING_SKILL_ID:
		# 2026-07-26 full overhaul, structured after rapid_slash's own
		# dedicated (not generic-skill-path) implementation — see the
		# HEALING_* block's own doc comments for the full design. Sotiris
		# never leaves his own formation slot (no advance, no lunge — user
		# spec item "中央へ移動しない"), so unlike rapid_slash there is no
		# position-offset function to wire in here at all.
		#
		# 2026-07-26 re-fix: the caster no longer plays the dedicated
		# skill_minion_0_healing clip at all — _battle_anim_pos.erase below
		# means _draw_party_row's "resting characters loop their own idle"
		# path (the same one every non-acting party member already uses)
		# draws Sotiris for the whole cast instead. User report: individual
		# frames of that clip had the body and sword rendering as visibly
		# disconnected pieces plus a stray dark fragment, and the clip's
		# per-frame bbox differences made his size/pose/footing wobble
		# during the cast — "使用できるきれいなキャラクター単体フレームが
		# ない場合は...通常の戦闘立ち絵を詠唱中も表示する". The idle path
		# is the same code used before/after the cast, so position, scale,
		# and the feet anchor are identical throughout by construction —
		# nothing left to keep in sync by hand.
		#
		# The erase is NOT optional/defensive: _advance_battle_anim_step
		# unconditionally sets _battle_anim_pos[unit_id] = _battle_anim_
		# origin for EVERY queued entry (skills included) before calling
		# this function, specifically so _draw_party_row knows who's
		# currently acting. Leaving that entry in place would make _draw_
		# party_row's `_battle_anim_pos.has(slot_index)` check true and
		# route Sotiris through `art.frame(_battle_anim_motion_key, ...)`
		# instead of the idle path — _battle_anim_motion_key isn't set in
		# this branch, so it would silently replay whatever motion_key the
		# PREVIOUS queue entry left behind (a headless trace caught this:
		# it only read as "harmless empty string" because Sotiris happened
		# to act first in turn order that round, before any motion_key had
		# ever been set).
		_battle_anim_pos.erase(unit_id)
		_battle_anim_act_seconds = HEALING_ACT_SECONDS + HEALING_POST_ACT_GAP_SECONDS
		_healing_target_unit = int(entry.get("target_id", unit_id))
		_healing_target_flash_t = 0.0
		# Computed HERE, at cast start, not at the animated hit-apply
		# instant (2026-07-26 round-2 fix) — sim.resolve_boss_round()
		# already ran synchronously before this function was ever called,
		# so entry["amount"] (the real, already-computed heal delta) and
		# the target's post-heal sim.minions[].hp are BOTH available
		# immediately. _healing_hold_pre_heal freezes the display at this
		# reconstructed pre-heal value until the hit actually lands (see
		# _healing_display_hp) — without it, the card/on-field bar showed
		# the post-heal number from frame one, well before the beam even
		# reaches the target.
		_healing_hp_display_before = 0
		if _healing_target_unit >= 0 and _healing_target_unit < sim.minions.size():
			_healing_hp_display_before = \
				sim.minions[_healing_target_unit].hp - int(entry.get("amount", 0))
		_healing_hold_pre_heal = true
		_healing_hp_anim_t = 0.0
		_healing_orb_logged = false
		_healing_beam_launch_logged = false
		_healing_beam_arrive_logged = false
		_healing_circle_logged = false
		_healing_pillar_logged = false
		_healing_pillar_end_logged = false
		_healing_debug_log_counts = {}
		_healing_debug_log("HEALING cast started")
		return
	if is_skill and str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID:
		# v4 (2026-07-26) — see the SOUL_BREAK_* block's own doc comments
		# for the full design. v2/v3 kept using the skill's own delivered
		# clip (skill_minion_0_soulbreak) on the assumption it had "no
		# reported asset defect" — user reports of character splitting/
		# black-afterimage-looking artifacts PERSISTED even after v3
		# removed every other possible cause (the old generic-projectile
		# overlap, the smooth-circle VFX), which only makes sense if the
		# clip itself has the SAME kind of disconnected-region defect
		# healing's own dedicated clip turned out to have. Fix: abandon it
		# entirely and use attack_minion_N instead — the SAME shared,
		# already-verified-clean clip rapid_slash's own actor uses, at the
		# SAME fixed PARTY_ICON_PX box (not SKILL_ACTOR_DRAW_SIZE) — user
		# spec v4: "ラピッドスラッシュと同じキャラサイズ・足元基準". Since
		# "attack_minion_N" doesn't start with "skill_minion_", _draw_
		# party_row's dedicated-skill-clip branch no longer applies at
		# all; the character falls through to the exact same plain
		# fixed-icon_px branch a normal attack (and rapid_slash) already
		# uses — no per-frame scaling, no cropping, nothing skill-specific
		# in the render path at all.
		_battle_anim_motion_key = "attack_minion_%d" % art_variant
		_battle_anim_act_seconds = SOUL_BREAK_ACT_SECONDS + SOUL_BREAK_POST_ACT_GAP_SECONDS
		_soul_break_gather_logged = false
		_soul_break_hold_logged = false
		_soul_break_launch_logged = false
		_soul_break_downswing_logged = false
		_soul_break_followthrough_logged = false
		_soul_break_impact_logged = false
		_soul_break_burst_logged = false
		_soul_break_return_logged = false
		_soul_break_contact_flash_fired = false
		_soul_break_sfx_fired.clear()
		_soul_break_proj_flight_active = false
		_soul_break_proj_flight_elapsed = 0.0
		_soul_break_debug_log_counts = {}
		_soul_break_debug_log("SOUL_BREAK cast started")
		return
	if is_skill and str(entry.get("skill_id", "")) == EOS_BURST_SKILL_ID:
		# Uses the SHARED attack_minion_N clip at the SHARED PARTY_ICON_PX
		# box, exactly like rapid_slash/soul_break — this is what makes the
		# package's "必殺技中にscaleを拡大・縮小する[禁止]" / "スキル開始前
		# と全演出中のscale差：0" true by construction rather than by
		# tuning, since "attack_minion_N" doesn't start with "skill_minion_"
		# and so never reaches _draw_party_row's larger dedicated-clip box.
		_battle_anim_motion_key = "attack_minion_%d" % art_variant
		_battle_anim_act_seconds = EOS_BURST_ACT_SECONDS + EOS_BURST_POST_ACT_GAP_SECONDS
		_eos_burst_approach_offset_px = 0.0
		_eos_burst_logged.clear()
		print("EOS cast started")
		return
	var motion_key := ""
	if is_skill:
		motion_key = _skill_motion_key(str(entry.get("skill_id", "")))
	if motion_key != "" and art.has_art(motion_key):
		_battle_anim_motion_key = motion_key
	else:
		_battle_anim_motion_key = "attack_minion_%d" % art_variant
	_battle_anim_act_seconds = maxf(
		BATTLE_ANIM_ACT_MIN_SECONDS,
		maxi(1, art.frame_count(_battle_anim_motion_key)) * BATTLE_ANIM_ACT_FRAME_SECONDS)


func _on_battle_anim_tick() -> void:
	if _battle_anim_step < 0 or _battle_anim_step >= _battle_anim_queue.size():
		_battle_anim_timer.stop()
		return
	var dt := _battle_anim_timer.wait_time
	# Decayed here, at the TOP of the tick — same reason hitstop is only
	# ever decremented here and never inside _update_battle_anim_popups: a
	# value _fire_battle_anim_hit sets LATER in THIS SAME call must survive
	# unmodified through to this tick's own queue_redraw() at the bottom.
	# Decaying it in _update_battle_anim_popups (called every tick,
	# including the one that just set it) zeroed it out before any actual
	# render ever saw it above 0 — a real bug caught by headless trace
	# (screen_flash_seen was false even though the hit itself fired
	# correctly), not a sampling artifact.
	_battle_screen_flash_t = maxf(0.0, _battle_screen_flash_t - dt)
	# 「Professional Mix / Impact Polish v1」(2026-08-07) — eos_burstの
	# フラッシュ/shakeはもうここで減衰させない(旧`_eos_burst_impact_flash_t`
	# /`_eos_burst_mega_shake_t`の tick-dt 減算方式を撤去、詳細は
	# `_eos_burst_contact_trigger_elapsed`の宣言コメント参照)——hitstop中も
	# 実時間で進む要件は、`_process`側で毎フレーム継続する連続elapsed
	# (`_eos_burst_smooth_elapsed`)から`age`を計算し直す新方式で自動的に
	# 満たされる(hitstop中もこの連続elapsedは進み続けるため、フラッシュ/
	# shake自身はhitstopの影響を一切受けない)。
	if _battle_hitstop_t > 0.0:
		_battle_hitstop_t = maxf(0.0, _battle_hitstop_t - dt)
		queue_redraw()
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	var unit_id := int(entry["unit_id"])
	_battle_anim_phase_elapsed += dt
	# A shot in flight travels regardless of the caster's own phase; its
	# arrival — not the cast animation — is the hit moment. The act phase
	# below refuses to end while this is still true, so `entry` is always
	# the projectile's own step.
	if _battle_proj_active:
		_battle_proj_t += dt / BATTLE_PROJ_SECONDS
		if _battle_proj_t >= 1.0:
			_battle_proj_active = false
			_fire_battle_anim_hit(entry, unit_id, _battle_proj_to)
	match _battle_anim_phase:
		"move_in":
			# Frame progress follows the SAME eased curve as position, not
			# raw elapsed time (2026-07-20 polish — "foot sliding"): the
			# body eases in and out via smoothstep, but indexing frames by
			# elapsed time alone advances the run cycle at a constant rate
			# regardless, so the legs kept cycling at full speed while the
			# body was barely moving at the start/end of every dash-in —
			# reading as the character sliding across the ground rather
			# than running. eased_t already IS the fraction of the total
			# distance covered (it's what position.lerp uses), so using it
			# to drive frame progress ties stride rate to ground actually
			# covered instead of the clock.
			var frames := maxi(1, art.frame_count(_battle_anim_motion_key))
			var loop_frames := maxi(1, frames - BATTLE_ANIM_DASH_LOOP_TRIM)
			var t := clampf(_battle_anim_phase_elapsed / BATTLE_ANIM_MOVE_SECONDS, 0.0, 1.0)
			var eased_t := smoothstep(0.0, 1.0, t)
			_battle_anim_frame_index = int(
				eased_t * (BATTLE_ANIM_MOVE_SECONDS / BATTLE_ANIM_MOVE_FRAME_SECONDS)) % loop_frames
			var rest_pos := _formation_pos(unit_id)
			_battle_anim_pos[unit_id] = rest_pos.lerp(_battle_anim_dest, eased_t)
			if t >= 1.0:
				_battle_anim_phase = "arrive"
				_battle_anim_phase_elapsed = 0.0
				# Jump straight to the decelerate cells: leaving the index
				# at the run loop's last value flashed one mid-run frame at
				# a standstill (seen in the coordinate-verification log).
				_battle_anim_frame_index = maxi(0, frames - BATTLE_ANIM_DASH_LOOP_TRIM)
		"arrive":
			# The dash clip's trimmed decelerate/stop cells play once while
			# the character settles at the destination.
			var frames := maxi(1, art.frame_count(_battle_anim_motion_key))
			_battle_anim_frame_index = mini(
				maxi(0, frames - BATTLE_ANIM_DASH_LOOP_TRIM)
					+ int(_battle_anim_phase_elapsed / BATTLE_ANIM_MOVE_FRAME_SECONDS),
				frames - 1)
			if _battle_anim_phase_elapsed >= BATTLE_ANIM_ARRIVE_SECONDS:
				_enter_battle_anim_act_phase(entry, unit_id)
		"act":
			var t := clampf(_battle_anim_phase_elapsed / _battle_anim_act_seconds, 0.0, 1.0)
			# Anticipation eases in (2026-07-21, reference material: "溜め
			# は長く、攻撃部分は一瞬" — hold the early wind-up frames,
			# then rush through the swing). Only the DISPLAYED frame is
			# warped by this; hit_now below still checks the real `t`
			# (skills) or the real frame index (attacks), so hitstop/
			# projectile-launch timing is unaffected — a slower-feeling
			# wind-up, not a slower hit.
			var eased_elapsed := _battle_anim_act_seconds * pow(t, BATTLE_ANIM_ANTICIPATION_EASE)
			# Clamped, not wrapped: the clip plays once at ACT_FRAME_SECONDS
			# pace (now warped by the eased curve above) and holds its
			# final pose for the remainder of the phase. For skill actions,
			# the DISPLAYED frame comes from _skill_cast_frames — an
			# explicit, possibly non-contiguous list of "character actually
			# visible here" indices (2026-07-21 generalization: a single
			# cutoff couldn't reach good footage that sits AFTER one bad
			# frame, e.g. heitskjoldr's frames 3-4 are a clean shield-thrust
			# but frame 2 alone has no Vard in it — the old single-cutoff
			# scheme threw away 3-4 along with 2, leaving only frames 0-1
			# to hold on, which barely differ and read as "ヴァルドがその
			# 場で平行移動しただけ" (user report). Attack actions have no
			# SKILL_MOTION entry at all, so they keep the simple frames-1
			# clamp.
			var frames := maxi(1, art.frame_count(_battle_anim_motion_key))
			# rapid_slash plays the shared attack_minion_N clip (v3: no
			# longer a dedicated clip, see RAPID_SLASH_ACTOR_FRAMES' doc
			# comment) but on its OWN explicit absolute-second beat sheet
			# (RAPID_SLASH_ACTOR_FRAMES) — not _skill_cast_frames (sized for
			# an unrelated 12-frame skill_minion_ clip) and not the generic
			# eased/proportional pacing every other clip uses (the user
			# specified exact seconds, same treatment as the VFX and the
			# hit timing below).
			if str(entry.get("skill_id", "")) == RAPID_SLASH_SKILL_ID:
				_battle_anim_frame_index = _rapid_slash_actor_frame_index(_battle_anim_phase_elapsed)
				_battle_anim_flip = _rapid_slash_actor_flip(_battle_anim_phase_elapsed)
				_update_rapid_slash_waves(dt, _battle_anim_phase_elapsed)
			elif str(entry.get("skill_id", "")) == HEALING_SKILL_ID:
				# 2026-07-26 re-fix: the caster plays no dedicated clip at all
				# any more (see _enter_battle_anim_act_phase's HEALING_SKILL_ID
				# branch) — _battle_anim_frame_index is left alone since
				# nothing ever reads it for this skill. Still ticks the
				# VFX-only timers/one-shot logs every frame of the act phase.
				_update_healing_state(dt, _battle_anim_phase_elapsed)
			elif str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID:
				# Own explicit absolute-second beat sheet (SOUL_BREAK_ACTOR_
				# FRAMES / SOUL_BREAK_RETURN_FRAMES), same "own timeline"
				# treatment rapid_slash/healing already use — not the generic
				# eased/cast_frames pacing every other not-yet-dedicated
				# skill still shares.
				_battle_anim_frame_index = _soul_break_actor_frame_index(_battle_anim_phase_elapsed)
				_update_soul_break_state(dt, _battle_anim_phase_elapsed, unit_id)
			elif str(entry.get("skill_id", "")) == EOS_BURST_SKILL_ID:
				if _battle_anim_phase_elapsed < EOS_BURST_WINDUP_SECONDS:
					# v8 (this round): the タメ must NOT use any attack-clip
					# pose (attack_minion_N frames 0-2 are that clip's own
					# "raise sword overhead, then swing down" windup — an
					# ATTACK motion, not a charging stance, per the user's own
					# explicit correction). A single fixed frame of the
					# ordinary idle clip stands in instead, matching the
					# user's own fallback instruction ("適切なタメ姿勢の画
					# 像が存在しない場合は、攻撃フレームで代用せず、通常の
					# 待機姿勢を1枚固定して使用してください") — all motion
					# comes from the 2px sink + particles/ring instead of any
					# frame change.
					_battle_anim_motion_key = "minion_%d" % _minion_art_variant(unit_id)
					_battle_anim_frame_index = 0
				else:
					# UNCHANGED — attack_minion_N's own frame 2 (already
					# reached and held by this same breakpoint table before
					# elapsed ever reaches here) continues to drive the
					# reveal/dash/beam poses exactly as every prior round.
					_battle_anim_motion_key = "attack_minion_%d" % _minion_art_variant(unit_id)
					_battle_anim_frame_index = \
						_eos_burst_actor_frame_index(_battle_anim_phase_elapsed)
				_update_eos_burst_state(_battle_anim_phase_elapsed, unit_id)
			elif str(entry.get("action", "")) == "skill":
				var cast_frames := _skill_cast_frames(str(entry.get("skill_id", "")))
				var pos := mini(
					int(eased_elapsed / BATTLE_ANIM_ACT_FRAME_SECONDS),
					cast_frames.size() - 1)
				_battle_anim_frame_index = cast_frames[maxi(0, pos)] if not cast_frames.is_empty() else 0
			else:
				_battle_anim_frame_index = mini(
					int(eased_elapsed / BATTLE_ANIM_ACT_FRAME_SECONDS), frames - 1)
			# Position during "act" (2026-07-24 redesign): a SKILL never
			# left its own formation slot (_advance_battle_anim_step skips
			# move_in/arrive for skills entirely) — it leans up to
			# BATTLE_ANIM_SKILL_STEP_FRAC toward the target and back,
			# peaking at t=0.5 via sin(t*PI) (naturally 0 again at t=1, so
			# no separate "walk back" is needed — see the move_out skip
			# below). An ATTACK already fully walked to the boss via move_
			# in/arrive, so it keeps the old subtle weight-shift AT that
			# arrival point instead.
			if str(entry.get("skill_id", "")) == HEALING_SKILL_ID:
				# User spec: "中央へ移動しない。キャラの外側コンテナも移動さ
				# せない". 2026-07-26 re-fix: deliberately leaves
				# _battle_anim_pos WITHOUT an entry for this unit (not even a
				# no-op one equal to _battle_anim_origin) — an entry existing
				# at all is what used to route _draw_party_row into playing a
				# skill clip; omitting it is what keeps Sotiris on the plain
				# resting/idle render path for the whole cast (see this
				# function's HEALING_SKILL_ID branch). Falling into the
				# generic "skill" elif below would set an entry again (even
				# at zero offset, since BATTLE_ANIM_SKILL_STEP_FRAC is 0), so
				# healing needs its own branch here that does nothing.
				pass
			elif str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID:
				# Same reasoning as healing's own branch above — soul_break's
				# small step-in/return is a draw-time x_offset in _draw_
				# party_row (_soul_break_advance_offset_px), not a
				# _battle_anim_pos mutation, so this stays a no-op (the
				# origin _advance_battle_anim_step already set is correct).
				pass
			elif str(entry.get("action", "")) == "skill":
				var direction := signf(_battle_anim_dest.x - _battle_anim_origin.x)
				var step := sin(t * PI) * BATTLE_ANIM_SKILL_STEP_FRAC
				_battle_anim_pos[unit_id] = _battle_anim_origin + Vector2(direction * step, 0.0)
			elif _battle_anim_entry_is_melee(entry):
				var lunge := sin(t * PI) * BATTLE_ANIM_LUNGE_FRAC
				_battle_anim_pos[unit_id] = Vector2(_battle_anim_dest.x + lunge, _battle_anim_dest.y)
			# A normal attack's hit is keyed to the clip reaching its
			# baked-in slash frame; skills use the generic time fraction
			# (see the constants' comment).
			var hit_now := false
			if str(entry.get("skill_id", "")) == RAPID_SLASH_SKILL_ID:
				# Exact elapsed-second mark (user spec: "最後の0.34秒地点で
				# 1回だけ"), not the generic BATTLE_ANIM_HIT_AT fraction —
				# the two earlier slash beats (0.16/0.23s) are visual only
				# (see _draw_rapid_slash_vfx) and never reach here.
				hit_now = _battle_anim_phase_elapsed >= RAPID_SLASH_HIT_AT_SECONDS
			elif str(entry.get("skill_id", "")) == HEALING_SKILL_ID:
				# User spec: "0.92秒で回復を一度だけ適用する" — exact
				# elapsed-second mark, same treatment as rapid_slash's own
				# hit timing (not the generic BATTLE_ANIM_HIT_AT fraction).
				hit_now = _battle_anim_phase_elapsed >= HEALING_HIT_AT_SECONDS
			elif str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID:
				# User spec: "フレーム09の1フレーム目と完全に同時にダメー
				# ジ処理を開始する" — the impact sprite's own frame-9
				# instant. No separate "launch" step in the generic sense —
				# flight/impact are managed by this skill's own stateless
				# draw functions, not _battle_proj_*, so damage fires
				# directly here instead of waiting for a projectile-arrival
				# tick elsewhere.
				hit_now = _battle_anim_phase_elapsed >= SOUL_BREAK_HIT_AT_SECONDS
			elif str(entry.get("skill_id", "")) == EOS_BURST_SKILL_ID:
				# Package: damage lands ONLY once the beam connects after the
				# approach — never along the dash path ("突進経路ではダメージ
				# を与えないでください")。「ヒットストップ解除と同時に
				# frame2の最大爆発・ダメージ・ノックバックを発生させる」
				# (2026-08-05) — raw HIT_AT到達の瞬間ではなく、
				# _update_eos_burst_state側の専用トリガーが一度だけ立てる
				# フラグと、共有hitstopが自然に0まで減衰し切ったことの両方
				# を条件にする。ヒットストップが有効な間はこの関数自体が
				# 呼ばれない(_on_battle_anim_tickの早期return)ため、これは
				# 「ヒットストップが明けた最初のtick」で正確に一度だけtrue
				# になる。
				hit_now = _eos_burst_assault_released()
			elif str(entry.get("action", "")) == "attack":
				hit_now = _battle_anim_frame_index >= mini(BATTLE_ANIM_ATTACK_HIT_FRAME, frames - 1)
			else:
				hit_now = t >= BATTLE_ANIM_HIT_AT
			if not _battle_anim_hit_fired and hit_now:
				# Ranged enemy-target skills don't hit here — the cast's
				# peak LAUNCHES the shot, and the flight block above fires
				# the hit when it lands on the boss.
				if str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID:
					# Own dedicated flight (a stateless straight-line lerp in
					# _draw_soul_break_flight, not _battle_proj_*) — never
					# goes through the generic ranged-skill projectile
					# launch below, even though action/target_type/motion
					# would otherwise qualify it for that path. v16: this now
					# fires AT SOUL_BREAK_MAX_IMPACT_SECONDS (HIT_AT_SECONDS
					# is redefined to equal it) — the REAL hit (damage/
					# knockback/2nd flash/max hitstop), borrowing rapid_
					# slash's own exact hitstop/shake/flash numbers (user
					# spec: "ラピッドスラッシュと同じ最大ヒットストップ...
					# 画面揺れ...同系統のノックバック" — knockback left at
					# the shared defaults, matching rapid_slash's own choice
					# not to override them either). The EARLIER contact-
					# instant cosmetic pre-flash (stage 4, no damage) is a
					# separate manual block below, not a 2nd call here.
					# v18: the screen-flash ALPHA is now soul_break's own
					# value (user spec section 8), NOT borrowed from
					# rapid_slash any more — see SOUL_BREAK_SCREEN_FLASH_
					# ALPHA's own doc comment. v20: hitstop is ALSO now
					# soul_break's own dedicated value (SOUL_BREAK_HITSTOP_
					# SECONDS, user spec step 2) — shake/knockback stay on
					# rapid_slash's shared numbers (section 7: "画面揺れ...
					# は現在の処理を維持してください").
					_fire_battle_anim_hit(
						entry, unit_id, Vector2.INF,
						SOUL_BREAK_HITSTOP_SECONDS, RAPID_SLASH_SHAKE_SECONDS,
						RAPID_SLASH_SHAKE_PEAK_PX, RAPID_SLASH_FLASH_DECAY_SECONDS,
						SOUL_BREAK_SCREEN_FLASH_ALPHA)
					_soul_break_debug_log("SOUL_BREAK damage fired")
				elif str(entry.get("skill_id", "")) == EOS_BURST_SKILL_ID:
					# Bypasses the generic ranged-skill projectile launch
					# below (which this skill used to take) — the beam and
					# impact are drawn by this skill's own dedicated
					# functions, so the hit fires directly here.
					# 「オーラのクオリティと着弾の迫力を修正」(2026-08-05) —
					# ヒットストップは既にEOS_BURST_IMPACT_BURST_TRIGGER_
					# SECONDSの瞬間に_update_eos_burst_state側の専用トリガー
					# で消化済みのため0.0を渡す(ここで再度セットすると着弾の
					# 直後にもう一度停止する二重ヒットストップになる)。
					# 画面フラッシュも専用のランプ形状を持つ_draw_eos_burst_
					# impact_screen_flashに置き換えたため0.0を渡す(共有の
					# 単純な1tick矩形フラッシュとの二重発火を避ける)。
					# 「着弾『大爆発』強化 v3」(2026-08-06) — 共有揺れ
					# (shake_seconds/peak_px)も0.0へ変更し、eos_burst専用の
					# 2D揺れ`_eos_burst_mega_shake_t`だけをトリガーする形へ
					# 差し替えた(「既存の弱いshakeと二重に重ねない...専用
					# プリセットへ差し替える」を直接反映)。
					# 「敵を右へ20〜26pxノックバック」——共有デフォルト(18.0)
					# を超えるためEOS_BURST_KNOCKBACK_PXを明示指定。
					_fire_battle_anim_hit(
						entry, unit_id, Vector2.INF,
						0.0, 0.0,
						0.0, EOS_BURST_FLASH_DECAY_SECONDS,
						0.0, EOS_BURST_KNOCKBACK_PX)
					# 「Professional Mix / Impact Polish v1」(2026-08-07) —
					# フラッシュ・shake・busのduck解除の3つ全てがこの1回だけの
					# 記録(連続elapsed)を共有する。旧`_play_eos_burst_sfx(
					# "impact")`は_update_eos_burst_state側のHIT_AT到達(=
					# hitstop開始の瞬間)で独立して鳴っていたが、実際のdamage/
					# 巨大爆発/shake/flashは全てヒットストップが自然に解けた
					# この瞬間(_eos_burst_assault_released())に発火する——
					# 「別Timerで着弾時刻を推測せず、既存のdamage+explosion+
					# hitstopが発火する実contactイベントを基準にする」を、
					# 新しい時刻計算を増やさずこのSAMEブロックへ相乗りさせる
					# ことで満たす。impact用playerは独立しているため、
					# recoveryへ移っても余韻は途中で切られない。
					_eos_burst_contact_trigger_elapsed = _eos_burst_smooth_elapsed(_battle_anim_phase_elapsed)
					_play_eos_burst_sfx("impact")
					_eos_burst_log("EOS damage fired")
				elif str(entry.get("action", "")) == "skill" \
						and str(entry.get("target_type", "")) == "enemy" \
						and not _battle_anim_entry_is_melee(entry):
					_launch_battle_projectile(entry, unit_id)
				elif str(entry.get("skill_id", "")) == RAPID_SLASH_SKILL_ID:
					_fire_battle_anim_hit(
						entry, unit_id, Vector2.INF,
						RAPID_SLASH_HITSTOP_SECONDS, RAPID_SLASH_SHAKE_SECONDS,
						RAPID_SLASH_SHAKE_PEAK_PX, RAPID_SLASH_FLASH_DECAY_SECONDS,
						RAPID_SLASH_SCREEN_FLASH_ALPHA)
					_rapid_slash_debug_log("RAPID damage fired")
					# README: "impactはダメージ・白フラッシュ・ノックバック・
					# 最大爆発と同じ更新で1回だけ再生します" — same branch,
					# same _battle_anim_hit_fired guard as everything else here.
					_play_rapid_sfx("impact")
					# User spec item 6: the drifting/spreading/fading debris
					# starts at the EXACT same instant as the hit itself
					# ("最大爆発の瞬間"), not a separately-timed beat.
					_rapid_debris_t = RAPID_SLASH_DEBRIS_SECONDS
				elif str(entry.get("skill_id", "")) == HEALING_SKILL_ID:
					# _fire_battle_anim_hit's existing heal branch already
					# appends the "+N" popup and lets sim.unit's own .hp read
					# through immediately — this call is unchanged from the
					# generic case. _healing_hp_display_before was already
					# reconstructed at cast start (see _enter_battle_anim_
					# act_phase); what happens HERE is releasing the freeze
					# (_healing_hold_pre_heal) and starting the reveal
					# animation from that already-known baseline, plus
					# arming the target's own flash — all keyed to this
					# exact same instant.
					_fire_battle_anim_hit(entry, unit_id)
					_healing_hold_pre_heal = false
					_healing_hp_anim_t = HEALING_HP_BAR_ANIM_SECONDS
					_healing_target_flash_t = HEALING_TARGET_FLASH_SECONDS
					_healing_debug_log("HEALING heal applied")
					_play_healing_sfx("bloom")
				else:
					_fire_battle_anim_hit(entry, unit_id)
				_battle_anim_hit_fired = true
			# v19: the old stage-4 "cosmetic contact pre-flash" block that
			# used to sit here is REMOVED. It existed only because CONTACT
			# and MAX_IMPACT were 0.16s apart and the arrival needed some
			# immediate feedback; now that user spec section 2 unifies them
			# into one instant ("着弾処理を1つのイベントに統合"), the real
			# hit above already fires the enemy flash / hitstop / shake /
			# knockback / damage on that exact tick, and a second block
			# here would just double-set the same state in the same frame.
			# _soul_break_contact_flash_fired is kept (reset in both the
			# usual places) purely as a one-shot guard slot in case a
			# separate pre-contact beat is ever wanted again.
			if t >= 1.0 and not _battle_proj_active:
				# A skill's position already eased back to _battle_anim_
				# origin at t=1 (sin(PI)=0 above) — there's no distance
				# left to walk back, so go straight to the next step
				# instead of a move_out phase that would replay a walk
				# cycle in place.
				if str(entry.get("action", "")) == "skill":
					_battle_anim_pos.erase(unit_id)
					if str(entry.get("skill_id", "")) == RAPID_SLASH_SKILL_ID:
						_reset_rapid_slash_vfx_state()
					elif str(entry.get("skill_id", "")) == HEALING_SKILL_ID:
						_reset_healing_vfx_state()
					elif str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID:
						_reset_soul_break_state()
					elif str(entry.get("skill_id", "")) == EOS_BURST_SKILL_ID:
						_reset_eos_burst_state()
					_advance_battle_anim_step()
					return
				_battle_anim_phase = "move_out"
				_battle_anim_phase_elapsed = 0.0
				_battle_anim_frame_index = 0
				_battle_anim_flip = true  # walking back = moving left
				var art_variant := _minion_art_variant(unit_id)
				_battle_anim_motion_key = "walk_minion_%d" % art_variant
				if not art.has_art(_battle_anim_motion_key):
					_battle_anim_motion_key = "dash_minion_%d" % art_variant
		"move_out":
			# Same eased-frame-progress fix as move_in, mirrored.
			var frames := maxi(1, art.frame_count(_battle_anim_motion_key))
			var t := clampf(_battle_anim_phase_elapsed / BATTLE_ANIM_MOVE_SECONDS, 0.0, 1.0)
			var eased_t := smoothstep(0.0, 1.0, t)
			_battle_anim_frame_index = int(
				eased_t * (BATTLE_ANIM_MOVE_SECONDS / BATTLE_ANIM_MOVE_FRAME_SECONDS)) % frames
			var rest_pos := _formation_pos(unit_id)
			_battle_anim_pos[unit_id] = _battle_anim_dest.lerp(rest_pos, eased_t)
			if t >= 1.0:
				_battle_anim_pos.erase(unit_id)
				_battle_anim_flip = false
				_advance_battle_anim_step()
				return
		"counter":
			var hit_time := BATTLE_ANIM_COUNTER_SECONDS * BATTLE_ANIM_COUNTER_HIT_AT
			if not _battle_anim_hit_fired and _battle_anim_phase_elapsed >= hit_time:
				_battle_anim_hit_fired = true
				_battle_ally_hit_unit = int(entry.get("target_id", -1))
				_battle_ally_hit_t = 1.0
				# The boss's blow bursts on the ally it struck. Element
				# unknown for enemies (no data field yet) -> generic.
				var view := _view_rect()
				var target_frac := _formation_pos(_battle_ally_hit_unit)
				_battle_impact_key = "impact_generic"
				_battle_impact_t = 1.0
				_battle_impact_pos = Vector2(
					view.position.x + view.size.x * target_frac.x,
					view.position.y + view.size.y * target_frac.y - PARTY_ICON_PX * 0.5)
				_battle_anim_popups.append({
					"kind": "ally", "unit_id": _battle_ally_hit_unit,
					"text": "-%d" % int(entry.get("amount", 0)),
					"color": COLOR_DAMAGE_POPUP, "t": 0.0,
				})
				# ターン開始（_advance_battle_anim_stepのboss_counter分岐）で
				# 既に_clear_battle_message()済み——ここは同じ敵ターン内の
				# 続きとして積み増すだけ。
				_append_battle_message(locale.text("UI_BATTLE_MSG_DAMAGE_ALLY") % [
					_unit_display_name(sim.minions[_battle_ally_hit_unit]),
					int(entry.get("amount", 0)),
				])
				_battle_hitstop_t = BATTLE_HITSTOP_SECONDS
				_battle_shake_t = BATTLE_SHAKE_SECONDS
				# Reset in case the previous hit was rapid_slash's (which
				# overrides these via _fire_battle_anim_hit's trailing
				# params) — the counter step doesn't go through that
				# function, so it must restore the shared defaults itself.
				_battle_shake_duration = BATTLE_SHAKE_SECONDS
				_battle_shake_peak_px = 6.0
			if _battle_anim_phase_elapsed >= BATTLE_ANIM_COUNTER_SECONDS:
				_advance_battle_anim_step()
				return
		"victory":
			# Party-wide pose drawn by _draw_party_row (clip frames come
			# from this phase's elapsed time); nothing moves.
			if _battle_anim_phase_elapsed >= BATTLE_VICTORY_SECONDS:
				_advance_battle_anim_step()
				return
	_update_battle_anim_popups(dt)
	queue_redraw()


## Fires once per queued step, at BATTLE_ANIM_HIT_AT into the "act" phase:
## a floating number over the target, and — for damage — the boss banner's
## HP bar draining toward the round's already-resolved final value plus a
## hit-flash. buff_atk/buff_def/debuff/special fire no popup (nothing
## numeric happened, see _apply_skill) but the motion still plays in full.
## `impact_pos` places the burst (a landing projectile passes its own
## endpoint); Vector2.INF = default to the boss's near side (melee). The 5
## trailing params all default to this project's shared hit-feel constants
## — every existing call site (positional, no trailing args) is completely
## unaffected; only rapid_slash's own call (see RAPID_SLASH_HITSTOP_
## SECONDS etc.) passes different numbers, per its VFX v2 spec's own §F5の
## 命中処理.
func _fire_battle_anim_hit(
		entry: Dictionary, unit_id: int, impact_pos: Vector2 = Vector2.INF,
		hitstop_seconds: float = BATTLE_HITSTOP_SECONDS,
		shake_seconds: float = BATTLE_SHAKE_SECONDS, shake_peak_px: float = 6.0,
		flash_decay_seconds: float = 0.25, screen_flash_alpha: float = 0.0,
		knockback_px: float = BATTLE_KNOCKBACK_PX,
		knockback_seconds: float = BATTLE_ENEMY_HIT_SECONDS) -> void:
	var amount := int(entry.get("amount", 0))
	var effect := str(entry.get("effect", "damage"))
	var target_type := str(entry.get("target_type", "enemy"))
	if effect == "heal" and target_type == "ally":
		# amount is now sim.gd's ACTUAL post-clamp hp delta (2026-07-26 fix,
		# see _apply_skill's heal branch) — 0 for an already-full-hp target.
		# User spec: "restored_amount > 0の場合だけ「+回復量」を表示...HP満
		# タンの場合は+1などの数値を表示しない" — a no-op heal still plays
		# its full motion/VFX (the caster doesn't know in advance), it just
		# shows no popup.
		if amount > 0:
			var target_id := int(entry.get("target_id", unit_id))
			_append_battle_message(
				locale.text("UI_BATTLE_MSG_HEAL") % [_unit_display_name(sim.minions[target_id]), amount])
			var popup := {
				"kind": "ally", "unit_id": target_id,
				"text": "+%d" % amount, "color": COLOR_HEAL_POPUP, "t": 0.0,
			}
			# ヒーリング only: user spec "0.5〜0.7秒かけて上昇・フェードさせる"
			# — narrower than the shared BATTLE_ANIM_POPUP_SECONDS (0.8s) every
			# other popup (including this same branch for the other 3 heal
			# skills — chinkon/lif/heil) still uses by default. "duration" is a
			# new OPTIONAL popup field (see _update_battle_anim_popups/_draw_
			# battle_anim_popups), backward compatible — any popup without it
			# behaves exactly as before.
			if str(entry.get("skill_id", "")) == HEALING_SKILL_ID:
				popup["duration"] = HEALING_HEAL_POPUP_SECONDS
			_battle_anim_popups.append(popup)
	elif effect == "damage":
		# 新企画v1仕様書 v2 §8/§9/§12, 2026-08-21: a part-targeted hit drains
		# that part's OWN shadow HP, not the main body's — mirroring sim's
		# _apply_boss_damage(), which keeps a part's pool entirely separate
		# from boss_hp. "already <= 0 heading into this hit" means an
		# earlier action THIS SAME ROUND already destroyed the part (sim
		# processes actions in order and silently redirects any further
		# hits on an already-broken part to boss_hp, see _apply_boss_
		# damage) — falling through to the main-body branch below mirrors
		# that redirect exactly instead of showing a misleading part popup
		# for damage that didn't actually land on the part.
		var target_part := str(entry.get("target_part", ""))
		var part_shadow_hp := int(_battle_boss_part_hp_display.get(target_part, 0))
		var boss_def_for_log := enemy_db.get_enemy(sim.boss_enemy_id)
		var boss_name_for_log := locale.text(str(boss_def_for_log["name_key"]))
		if target_part != "" and _battle_boss_part_hp_display.has(target_part) and part_shadow_hp > 0:
			var remaining := maxi(0, part_shadow_hp - amount)
			_battle_boss_part_hp_display[target_part] = remaining
			_set_boss_part_row_display(target_part, remaining)
			var part_name := _boss_part_display_name(enemy_db.get_enemy(sim.boss_enemy_id), target_part)
			if remaining <= 0:
				_append_battle_message(
					locale.text("UI_BATTLE_MSG_PART_DESTROYED") % [boss_name_for_log, part_name])
				# 特殊メッセージ機構の動作確認用デモ（§13, 2026-08-22）——正式
				# な特殊ボスの文章・発火条件はそのボス制作時に別途設計する。
				# _append_battle_message(text, "special") がいつでもどこから
				# でも呼べることを示す最小限の例として、洞窟トロルの部位破壊
				# にだけ紐付けた（ボスidで明示的にガード、他ボスへは波及しない）。
				if sim.boss_enemy_id == "cave_troll":
					_append_battle_message(locale.text("UI_BATTLE_MSG_DEMO_TROLL_ENRAGED"), "special")
				_battle_anim_popups.append({
					"kind": "boss",
					"text": "%s %s" % [part_name, locale.text("UI_PART_BROKEN_POPUP")],
					"color": COLOR_PART_BREAK_POPUP, "t": 0.0,
					"duration": BATTLE_ANIM_POPUP_SECONDS + PART_BREAK_POPUP_EXTRA_SECONDS,
				})
			else:
				_append_battle_message(
					locale.text("UI_BATTLE_MSG_DAMAGE_PART") % [boss_name_for_log, part_name, amount])
				_battle_anim_popups.append({
					"kind": "boss", "text": "%s -%d" % [part_name, amount],
					"color": COLOR_DAMAGE_POPUP, "t": 0.0,
				})
		else:
			_append_battle_message(locale.text("UI_BATTLE_MSG_DAMAGE_BOSS") % [boss_name_for_log, amount])
			_battle_boss_hp_display = maxi(0, _battle_boss_hp_display - amount)
			_boss_banner_hp_bar.value = _battle_boss_hp_display
			_battle_anim_popups.append({
				"kind": "boss", "text": "-%d" % amount, "color": COLOR_DAMAGE_POPUP, "t": 0.0,
			})
		# Everything the hit moment owes the player, all at once (user
		# spec 2026-07-20): flash, impact burst, knockback, damage number,
		# and a brief universal freeze (hitstop) so the swing reads as
		# connecting instead of passing through.
		_battle_anim_boss_flash_t = 1.0
		_battle_boss_flash_decay_seconds = flash_decay_seconds
		_battle_enemy_knock_t = 1.0
		_battle_knockback_px = knockback_px
		_battle_knockback_seconds = knockback_seconds
		_battle_hitstop_t = hitstop_seconds
		_battle_shake_t = shake_seconds
		_battle_shake_duration = shake_seconds
		_battle_shake_peak_px = shake_peak_px
		if screen_flash_alpha > 0.0:
			_battle_screen_flash_alpha = screen_flash_alpha
			_battle_screen_flash_t = 1.0 / BATTLE_ANIM_FPS
		# rapid_slash/soul_break draw their own dedicated explosions instead
		# of the shared elemental burst (2026-07-24 stage 2/3 for rapid_
		# slash, see _draw_rapid_slash_vfx; 2026-07-26 for soul_break, user
		# spec: "現在の汎用的な白い星だけの着弾は廃止", see _draw_soul_
		# break_burst) — showing both at the same spot at once would double
		# up two explosions. Everything else above (flash/knockback/
		# hitstop/shake/damage number) still fires the same.
		if str(entry.get("skill_id", "")) != RAPID_SLASH_SKILL_ID \
				and str(entry.get("skill_id", "")) != SOUL_BREAK_SKILL_ID \
				and str(entry.get("skill_id", "")) != EOS_BURST_SKILL_ID:
			_battle_impact_t = 1.0
			_battle_impact_key = str(VARIANT_IMPACT.get(
				_minion_art_variant(unit_id), "impact_generic"))
			if impact_pos != Vector2.INF:
				_battle_impact_pos = impact_pos
			else:
				var rect := _boss_icon_rect(_view_rect())
				_battle_impact_pos = Vector2(
					rect.position.x + rect.size.x * 0.3, rect.position.y + rect.size.y * 0.5)


func _update_battle_anim_popups(dt: float) -> void:
	for i in range(_battle_anim_popups.size() - 1, -1, -1):
		var popup: Dictionary = _battle_anim_popups[i]
		popup["t"] = float(popup["t"]) + dt
		var duration: float = float(popup.get("duration", BATTLE_ANIM_POPUP_SECONDS))
		if float(popup["t"]) >= duration:
			_battle_anim_popups.remove_at(i)
	_battle_anim_boss_flash_t = maxf(
		0.0, _battle_anim_boss_flash_t - dt / _battle_boss_flash_decay_seconds)
	_battle_impact_t = maxf(0.0, _battle_impact_t - dt / BATTLE_IMPACT_SECONDS)
	# Knock/hit decay doubles as the hit-reaction clip's playback clock
	# (frame index derives from 1 - t in the draw code). _battle_knockback_
	# seconds defaults to BATTLE_ENEMY_HIT_SECONDS but can run faster
	# per-hit (currently only soul_break, see SOUL_BREAK_KNOCKBACK_SECONDS)
	# — a shorter window also plays the hit-reaction clip faster, which
	# reads as appropriate for a quick decisive burst rather than every
	# other skill's shared slower knockback.
	_battle_enemy_knock_t = maxf(0.0, _battle_enemy_knock_t - dt / _battle_knockback_seconds)
	# Lunge decays over hit_time/COUNTER_HIT_AT * ... — concretely 0.72s,
	# chosen so sin((1-t)*PI)'s peak (t=0.5) lands exactly on the counter
	# step's hit moment (0.8s * 0.45 = 0.36s in).
	_battle_boss_lunge_t = maxf(0.0, _battle_boss_lunge_t - dt / 0.72)
	_battle_ally_hit_t = maxf(0.0, _battle_ally_hit_t - dt / BATTLE_ALLY_HIT_SECONDS)
	_battle_shake_t = maxf(0.0, _battle_shake_t - dt)


## User spec (2026-07-26, healing polish round 2): "回復数値をキャラクター
## やHPバーより高いz_index...で表示する。対象の頭上へ表示する...暗い縁取
## り...他の味方と重なっても数値だけは必ず読めるように". This function was
## already the LAST thing drawn in _draw_boss_battle (on top of every
## sprite/VFX in the custom-drawn layer), but its old anchor Y
## (PARTY_ICON_PX + 10) landed EXACTLY on the character's own on-field HP
## bar (_draw_party_row's hp_y is also `top - 10`) — the "+14" started
## life sitting directly on top of that thin bar (and the Lv label just
## above it), reading as "hidden" even though it was technically frontmost.
## Raised clear of both, and given a dark outline (draw_string_outline)
## so it stays legible over any sprite/background regardless of position.
const BATTLE_ANIM_POPUP_HEAD_CLEARANCE_PX := 30.0
const BATTLE_ANIM_POPUP_RISE_PX := 34.0
const COLOR_POPUP_OUTLINE := Color(0.05, 0.05, 0.05, 1.0)


func _draw_battle_anim_popups(view: Rect2) -> void:
	if _battle_anim_popups.is_empty():
		return
	var font := ThemeDB.fallback_font
	for popup: Dictionary in _battle_anim_popups:
		var t: float = popup["t"]
		var duration: float = float(popup.get("duration", BATTLE_ANIM_POPUP_SECONDS))
		var alpha := clampf(1.0 - t / duration, 0.0, 1.0)
		var rise := t * BATTLE_ANIM_POPUP_RISE_PX
		var color: Color = popup["color"]
		color.a = alpha
		var base_pos: Vector2
		if str(popup["kind"]) == "boss":
			var rect := _boss_icon_rect(view)
			base_pos = Vector2(rect.position.x + rect.size.x / 2.0, rect.position.y - 10.0)
		else:
			var frac := _formation_pos(int(popup["unit_id"]))
			base_pos = Vector2(
				view.position.x + view.size.x * frac.x,
				view.position.y + view.size.y * frac.y
					- PARTY_ICON_PX - BATTLE_ANIM_POPUP_HEAD_CLEARANCE_PX)
		# Width 40->90 / offset -20->-45 (新企画v1仕様書 v2 §8, 2026-08-21):
		# a part-tagged popup ("右腕 -35") runs noticeably longer than a
		# plain "-35" — widened the box so it doesn't clip, keeping it
		# centered on base_pos.x the same way the old 40/-20 pair did
		# (offset is always -width/2, so a short ally "+14" still lands in
		# exactly the same visual spot as before). Font size 18->22 and
		# outline width 3->4 (§7, "現在より少し存在感を強くする").
		var text_pos := base_pos + Vector2(-45, -rise)
		var outline_color := COLOR_POPUP_OUTLINE
		outline_color.a = alpha
		# アウトライン幅 4->5（2026-08-22, 視認性改善）: 通常ダメージが白へ
		# 統一されたため（薄いオレンジより明背景に埋もれやすい）、黒縁を
		# 少し太くして保険を厚くする。
		draw_string_outline(
			font, text_pos, str(popup["text"]),
			HORIZONTAL_ALIGNMENT_CENTER, 90, 22, 5, outline_color)
		draw_string(
			font, text_pos, str(popup["text"]),
			HORIZONTAL_ALIGNMENT_CENTER, 90, 22, color)


## Captures the shot's pixel endpoints at launch: from the caster's
## current hands-height position (wherever the animation actually has
## them standing — center stage for ranged casts) to the boss icon's
## near side. Window geometry can't change mid-flight, so pixel space
## is safe for the ~0.35s trip.
func _launch_battle_projectile(entry: Dictionary, unit_id: int) -> void:
	var view := _view_rect()
	var pos_frac: Vector2 = _battle_anim_pos.get(unit_id, _formation_pos(unit_id))
	_battle_proj_from = Vector2(
		view.position.x + view.size.x * pos_frac.x + PARTY_ICON_PX * 0.4,
		view.position.y + view.size.y * pos_frac.y - PARTY_ICON_PX * 0.55)
	# Dead-flat flight (2026-07-20 user fix: aiming at the boss icon's
	# vertical center made every shot climb diagonally): the shot stays at
	# the caster's hands height all the way. That height is within the
	# boss's 176px body, so it still visibly connects.
	var rect := _boss_icon_rect(view)
	_battle_proj_to = Vector2(rect.position.x + rect.size.x * 0.3, _battle_proj_from.y)
	_battle_proj_t = 0.0
	# What flies: a dedicated flight-loop clip (proj_key, the asset
	# pack's soul break / yomotsuhirasaka rows) beats a single
	# isolated-effect cell (proj_frame, e.g. 玄火符's flying talisman
	# flame) beats the code-drawn bolt.
	_battle_proj_tex = null
	_battle_proj_key = ""
	var skill_id := str(entry.get("skill_id", ""))
	if SKILL_MOTION.has(skill_id):
		var motion: Dictionary = SKILL_MOTION[skill_id]
		if motion.has("proj_key") and art.has_art(str(motion["proj_key"])):
			_battle_proj_key = str(motion["proj_key"])
		else:
			var proj_frame := _skill_proj_frame(skill_id)
			if proj_frame >= 0:
				var key := _skill_motion_key(skill_id)
				if art.has_art(key):
					# The clip's frames are the FULL uncropped 222x222 cell
					# (v4 delivery, 2026-07-22 — see SKILL_MOTION_REF_* doc
					# comment), so most of this canvas is transparent
					# padding around the actual burst. A flying projectile
					# is a single standalone image, not part of a multi-
					# frame clip that needs consistent scale/anchor across
					# frames — so unlike the caster's own motion, it's safe
					# and correct to tight-crop just this one texture here,
					# to its own content, before it's drawn at
					# BATTLE_PROJ_SPRITE_PX (otherwise the burst would
					# render tiny inside a mostly-empty box, the "ball is
					# small" bug from 2026-07-20 recurring for a new reason).
					var raw_tex := art.frame(key, proj_frame)
					var img := raw_tex.get_image()
					var used := img.get_used_rect()
					if used.size.x > 0 and used.size.y > 0:
						_battle_proj_tex = ImageTexture.create_from_image(img.get_region(used))
					else:
						_battle_proj_tex = raw_tex
	_battle_proj_active = true


## The shot in flight. With a proj_frame cell available this is the
## skill's own delivered illustration flying across the arena (the cells
## are drawn pointing right = the direction of travel, so no flip);
## otherwise a code-drawn bolt with a fading trail (substitute policy —
## same as the impact burst).
##
## Drawn with LINEAR filtering, not the project's default NEAREST (2026-
## 07-20 user report: "画質が良くない" — the project renders pixel art at
## default_texture_filter=0/NEAREST, which keeps characters crisp at
## their native-ish sizes, but this 128px source blown up to
## BATTLE_PROJ_SPRITE_PX (~1.5x, not a clean integer multiple) scaled
## unevenly under nearest-neighbor: some source pixels landed on 1 screen
## pixel, others on 2, reading as jagged/low-quality. These are soft
## glowing light/particle effects, not pixel-perfect character art, so
## smoothing them (same technique already used for crisp movement in
## _draw_backdrop_transition, just the opposite direction) reads as
## correct rather than off-style.
func _draw_battle_projectile(view: Rect2) -> void:
	if not _battle_proj_active:
		return
	var t := clampf(_battle_proj_t, 0.0, 1.0)
	var pos := _battle_proj_from.lerp(_battle_proj_to, t)
	if _battle_proj_key != "" and art.has_art(_battle_proj_key):
		# Flight loop: the clip wobbles in place (README) while this
		# single moving object carries it across; natural aspect kept
		# (these rows are wide streaks, squashing them square reads
		# wrong).
		var elapsed := t * BATTLE_PROJ_SECONDS
		var tex := art.frame(_battle_proj_key, int(elapsed / BATTLE_PROJ_FRAME_SECONDS))
		var draw_w := BATTLE_PROJ_KEY_W
		var draw_h := draw_w * float(tex.get_height()) / maxf(1.0, float(tex.get_width()))
		var prev_filter := texture_filter
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		draw_texture_rect(
			tex, Rect2(pos - Vector2(draw_w, draw_h) / 2.0, Vector2(draw_w, draw_h)), false)
		texture_filter = prev_filter
		return
	if _battle_proj_tex != null:
		# Aspect-preserving, not a forced square (2026-07-21 fix): these
		# frames are now tightly cropped to their own content (see
		# slice_skill_motions_v3.gd), so most aren't square — e.g. 玄火符
		# crops to ~217x153. Forcing a square stretched them ("変な切り
		# 取られ方" — the user's report). Width pinned to
		# BATTLE_PROJ_SPRITE_PX, height derived from the texture's own
		# aspect, same approach _draw_battle_projectile already uses for
		# the dedicated proj_key flight-loop clips below.
		var draw_w := BATTLE_PROJ_SPRITE_PX
		var draw_h := draw_w * float(_battle_proj_tex.get_height()) \
			/ maxf(1.0, float(_battle_proj_tex.get_width()))
		var prev_filter := texture_filter
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		draw_texture_rect(
			_battle_proj_tex,
			Rect2(pos - Vector2(draw_w, draw_h) / 2.0, Vector2(draw_w, draw_h)),
			false)
		texture_filter = prev_filter
		return
	for i in 4:
		var trail_t := t - 0.06 * float(i + 1)
		if trail_t <= 0.0:
			break
		var trail_color := COLOR_PROJECTILE
		trail_color.a = 0.5 - 0.1 * float(i)
		draw_circle(
			_battle_proj_from.lerp(_battle_proj_to, trail_t),
			BATTLE_PROJ_RADIUS_PX * (0.8 - 0.15 * float(i)), trail_color)
	draw_circle(pos, BATTLE_PROJ_RADIUS_PX, COLOR_PROJECTILE)
	draw_circle(pos, BATTLE_PROJ_RADIUS_PX * 0.5, Color(1.0, 1.0, 1.0, 0.9))


## Same lookup shape used throughout this skill's timing tables. Always
## resolves to frame 0 before the first breakpoint (0.00s) — unlike the
## old VFX table, the character is always on screen, there's no "nothing
## shown yet" state.
func _rapid_slash_actor_frame_index(elapsed: float) -> int:
	var result := 0
	for pair: Array in RAPID_SLASH_ACTOR_FRAMES:
		if elapsed >= float(pair[0]):
			result = int(pair[1])
		else:
			break
	return result


## Parallel lookup for RAPID_SLASH_ACTOR_FLIP_FRAMES — the one mirrored
## beat that stands in for the 2nd swing's "逆方向の斬り" (see that
## constant's doc comment).
func _rapid_slash_actor_flip(elapsed: float) -> bool:
	var result := false
	for pair: Array in RAPID_SLASH_ACTOR_FLIP_FRAMES:
		if elapsed >= float(pair[0]):
			result = bool(pair[1])
		else:
			break
	return result


## 0.0 at rest (at the caster's own formation slot), smoothstep-ramping to
## 1.0 by RAPID_SLASH_MOVE_OUT_SECONDS, held at 1.0, then the same shape
## back to 0.0 across [RAPID_SLASH_RETURN_START_SECONDS, _END_SECONDS] —
## see RAPID_SLASH_ADVANCE_*/_MOVE_OUT_SECONDS' doc comment for why this
## exists as a fraction rather than a direct pixel value (the actual pixel
## distance depends on the boss's on-screen position, computed by the
## caller).
func _rapid_slash_advance_frac(elapsed: float) -> float:
	if elapsed < RAPID_SLASH_MOVE_OUT_SECONDS:
		var t := elapsed / RAPID_SLASH_MOVE_OUT_SECONDS
		return smoothstep(0.0, 1.0, t)  # user's move_eased formula
	elif elapsed < RAPID_SLASH_RETURN_START_SECONDS:
		return 1.0
	elif elapsed < RAPID_SLASH_RETURN_END_SECONDS:
		var t := (elapsed - RAPID_SLASH_RETURN_START_SECONDS) \
			/ (RAPID_SLASH_RETURN_END_SECONDS - RAPID_SLASH_RETURN_START_SECONDS)
		return 1.0 - smoothstep(0.0, 1.0, t)  # same shape, back to rest
	else:
		return 0.0


## The caster's target x on-screen (pixels) — its OWN resting formation
## slot's x plus the current advance offset, direction-aware. Shared by
## the position-offset function below and the flying slash's launch point
## (RAPID_SLASH_PROJ_LAUNCH_OFFSET_PX is measured from here), so both
## agree on exactly where the blade is at any given moment.
func _rapid_slash_stage_x_px(view: Rect2, elapsed: float) -> float:
	var actor_start_x := view.position.x + view.size.x * _battle_anim_origin.x
	var target_x := _rapid_slash_target_x_px(view)
	var direction := signf(target_x - actor_start_x)
	var advance_px := minf(absf(target_x - actor_start_x) * RAPID_SLASH_ADVANCE_FRAC, RAPID_SLASH_ADVANCE_MAX_PX)
	return actor_start_x + direction * advance_px * _rapid_slash_advance_frac(elapsed)


## The boss's on-screen reference x (pixels) that both the caster's own
## advance target and the flying slash's arrival point are measured
## against — same "slightly left of the boss's center" spot _fire_battle_
## anim_hit's default melee impact already uses, for consistency between
## where the hit visually lands and where everything else in this skill
## aims.
func _rapid_slash_target_x_px(view: Rect2) -> float:
	var rect := _boss_icon_rect(view)
	return rect.position.x + rect.size.x * 0.3


## Current recoil contribution (user spec item 4) — decays from whatever
## px/direction the most recent launch set (_rapid_recoil_peak_px) back to
## 0 over RAPID_SLASH_RECOIL_SECONDS, same smoothstep ease used everywhere
## else in this file. Explicitly NOT the anticipation/overshoot dip an
## earlier round added and then removed on user request — this is smaller
## (1-2px vs 4-5px), always launch-triggered (never during the advance
## itself), and requested fresh this round.
func _rapid_recoil_offset_px() -> float:
	if _rapid_recoil_t <= 0.0:
		return 0.0
	var frac := _rapid_recoil_t / RAPID_SLASH_RECOIL_SECONDS
	return _rapid_recoil_peak_px * smoothstep(0.0, 1.0, frac)


## Pixel x_offset for _draw_party_row's rapid_slash draw — the DIFFERENCE
## between the caster's resting x and its current staged x, plus the tiny
## per-launch recoil above, so it composes with x through the same x_offset
## mechanism knockback already uses rather than touching _battle_anim_pos
## (which stays the resting formation slot throughout — see RAPID_SLASH_
## ADVANCE_* doc comment). The base advance itself still only ever moves
## one direction from actor_start to stage_pos and back — no anticipation
## dip, no overshoot past stage_pos; y is untouched (fixed at actor_start.y)
## for the whole advance. recoil_px's sign is relative to the travel
## direction (positive = toward the boss, "前"; negative = away, "後ろ"),
## same convention _rapid_slash_stage_x_px itself already uses.
func _rapid_slash_advance_offset_px(view: Rect2, elapsed: float) -> float:
	var actor_start_x := view.position.x + view.size.x * _battle_anim_origin.x
	var base := _rapid_slash_stage_x_px(view, elapsed) - actor_start_x
	var target_x := _rapid_slash_target_x_px(view)
	var direction := signf(target_x - actor_start_x)
	return base + direction * _rapid_recoil_offset_px()


## True while the current queued step is rapid_slash's own "act" phase —
## shared guard for _draw_rapid_slash_dust/_draw_rapid_slash_vfx (both need
## the exact same check, but are called from two different points in
## _draw_boss_battle's draw order — dust behind the character, the rest on
## top of everything — so this can't just be one function's early-out).
func _rapid_slash_vfx_active() -> bool:
	if _battle_anim_phase != "act" or _battle_anim_step < 0 \
			or _battle_anim_step >= _battle_anim_queue.size():
		return false
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	return str(entry.get("skill_id", "")) == RAPID_SLASH_SKILL_ID


## The sword-tip point the charge glow and all 3 waves launch from —
## stage_x (the caster's current on-screen x, mid-advance or fully staged)
## offset toward the boss, at hand height. Shared so the charge glow and
## the waves that follow it visibly originate from the same spot.
func _rapid_slash_sword_tip_pos(view: Rect2, elapsed: float) -> Vector2:
	var stage_x := _rapid_slash_stage_x_px(view, elapsed)
	var target_x := _rapid_slash_target_x_px(view)
	var direction := signf(target_x - stage_x)
	var feet_y := view.position.y + view.size.y * _battle_anim_origin.y
	return Vector2(
		stage_x + direction * RAPID_SLASH_SWORD_TIP_OFFSET_PX, feet_y - float(PARTY_ICON_PX) * 0.5)


## Footstep dust (README "足元の砂ぼこり") — drawn from _draw_boss_battle
## BEFORE _draw_party_row, so the character's own sprite always layers on
## top of it. Visible only during the advance (0.00-0.24s), trailing 8px
## behind the caster's ground position (opposite its direction of travel).
func _draw_rapid_slash_dust(view: Rect2) -> void:
	if not _rapid_slash_vfx_active() or not art.has_art(RAPID_SLASH_DUST_KEY):
		return
	var elapsed := _battle_anim_phase_elapsed
	if elapsed >= RAPID_SLASH_DUST_END_SECONDS:
		return
	var frame_count := art.frame_count(RAPID_SLASH_DUST_KEY)
	var frame := mini(int(elapsed / RAPID_SLASH_DUST_FRAME_SECONDS), frame_count - 1)
	var tex := art.frame(RAPID_SLASH_DUST_KEY, frame)
	var stage_x := _rapid_slash_stage_x_px(view, elapsed)
	var target_x := _rapid_slash_target_x_px(view)
	var direction := signf(target_x - stage_x)
	var feet_y := view.position.y + view.size.y * _battle_anim_origin.y
	var dust_x := stage_x - direction * RAPID_SLASH_DUST_BACK_OFFSET_PX
	var draw_size := Vector2(RAPID_SLASH_DUST_DRAW_W, RAPID_SLASH_DUST_DRAW_H)
	var prev_filter := texture_filter
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	draw_texture_rect(
		tex, Rect2(Vector2(dust_x - draw_size.x / 2.0, feet_y - draw_size.y), draw_size), false)
	texture_filter = prev_filter


## User spec item 7: fully clear rapid_slash's own VFX state the moment its
## act phase ends — belt-and-suspenders on top of _enter_battle_anim_act_
## phase's own fresh seed at the START of the NEXT cast (this guarantees no
## stale wave/impact state can leak into whatever draws in between, e.g. a
## re-open of the boss screen mid-sequence).
func _reset_rapid_slash_vfx_state() -> void:
	_rapid_slash_waves = []
	_rapid_slash_impact_started = false
	_rapid_impact_active = false
	_rapid_impact_elapsed = 0.0
	_rapid_charge_active = false
	_rapid_recoil_t = 0.0
	_rapid_recoil_peak_px = 0.0
	_rapid_debris_t = 0.0
	_rapid_sfx_sparks_played = false
	_rapid_slash_debug_log("RAPID VFX state reset")


## Counts + prints a debug line (user spec: exact literal messages, each
## expected to fire exactly once per cast) — see _rapid_slash_debug_log_
## counts' own doc comment for why this is also state, not just print().
func _rapid_slash_debug_log(msg: String) -> void:
	_rapid_slash_debug_log_counts[msg] = int(_rapid_slash_debug_log_counts.get(msg, 0)) + 1
	print(msg)


## Called once from _ready() — one AudioStreamPlayer per delivered WAV
## (README: "slash_1/2/3を同時再生しないでください" is naturally satisfied
## by giving each sound its OWN player, so an overlapping tail never steals
## another sound's channel). Missing files leave stream null; _play_rapid_
## sfx() then silently no-ops (same has_art()-style tolerance this project
## already applies to missing art).
func _build_rapid_slash_sfx() -> void:
	for key: String in RAPID_SLASH_SFX_PATHS:
		var path := str(RAPID_SLASH_SFX_PATHS[key])
		var player := AudioStreamPlayer.new()
		if ResourceLoader.exists(path):
			player.stream = load(path)
		add_child(player)
		_rapid_sfx_players[key] = player


func _play_rapid_sfx(key: String) -> void:
	var player: AudioStreamPlayer = _rapid_sfx_players.get(key)
	if player != null and player.stream != null:
		player.play()


## ================= ヒーリング helpers ================================

## Same "one AudioStreamPlayer per delivered WAV" pattern _build_rapid_
## slash_sfx uses — 3 independent players so charge/bloom/afterglow can
## never steal each other's channel even if their windows ever overlap.
## Missing files leave stream null; _play_healing_sfx() then silently
## no-ops (same has_art()-style tolerance this project already applies to
## missing art).
func _build_healing_sfx() -> void:
	for key: String in HEALING_SFX_PATHS:
		var path := str(HEALING_SFX_PATHS[key])
		var player := AudioStreamPlayer.new()
		if ResourceLoader.exists(path):
			player.stream = load(path)
		add_child(player)
		_healing_sfx_players[key] = player


func _play_healing_sfx(key: String) -> void:
	var player: AudioStreamPlayer = _healing_sfx_players.get(key)
	if player != null and player.stream != null:
		player.play()


## Same "one AudioStreamPlayer per delivered WAV" pattern as rapid_slash/
## healing/soul_break above — charge/dragon_form/dash/impact each get their
## own independent player so a later sound starting never cuts off an
## earlier one's tail (README: "impactの余韻をrecoveryで切らないでください").
## Missing files leave stream null; _play_eos_burst_sfx() then silently
## no-ops (same has_art()-style tolerance this project already applies to
## missing art). 「Professional Mix / Impact Polish v1」(2026-08-07) —
## 各playerを`EOS_BURST_SFX_BUS`の対応表どおり専用busへルーティング
## (`_ensure_eos_burst_audio_buses()`を先に呼び、bus自体が存在することを
## 保証してから)。
func _build_eos_burst_sfx() -> void:
	_ensure_eos_burst_audio_buses()
	for key: String in EOS_BURST_SFX_PATHS:
		var path := str(EOS_BURST_SFX_PATHS[key])
		var player := AudioStreamPlayer.new()
		if ResourceLoader.exists(path):
			player.stream = load(path)
		player.volume_db = float(EOS_BURST_SFX_VOLUME_DB.get(key, 0.0))
		player.bus = str(EOS_BURST_SFX_BUS.get(key, "Master"))
		add_child(player)
		_eos_burst_sfx_players[key] = player


func _play_eos_burst_sfx(key: String) -> void:
	var player: AudioStreamPlayer = _eos_burst_sfx_players.get(key)
	if player != null and player.stream != null:
		player.play()


## 「既存audio bus構成を先に確認し、同等の専用busが無い場合だけ作る」
## (README) — このプロジェクトはproject.godotに`[audio]`セクション自体を
## 持たず(grep監査で確認済み)、起動時のbus構成はMaster1本のみ
## (`AudioServer.bus_count==1`)。役割が同じ既存busも無いため、`EosBuild`/
## `EosRelease`/`EosImpact`の3busを新設する。`AudioServer.get_bus_index`が
## -1以外を返せば既に存在する(2回目以降の呼び出し・テストでの再呼び出し
## に対して冪等)ため無条件に追加し直さない。
## D節「Impact sidechain」——EosBuild/EosReleaseへAudioEffectCompressorを
## 追加、sidechain=EosImpact、threshold=-18dB、ratio=6:1、attack=1000us
## (Godotのpropertyはmicroseconds単位、`attack_us`)、release=140ms
## (`release_ms`)、gain=0dB、mix=1.0——README開始値をそのまま設定。
## E節「Master safety」——Master末尾に既存Limiter/HardLimiterが無い場合
## だけ`AudioEffectHardLimiter`(このGodot 4.7には実在することを`ClassDB.
## class_exists`で確認済み)をceiling_db=-0.3・pre_gain_db=0.0(いずれも
## このクラスの実際のデフォルト値と一致、README開始値そのもの)で追加。
## 旧Godotでこのクラスが無い場合はこの調整のためだけにengine upgradeを
## しない(README明示指定)——`class_exists`チェックで自然にno-opになる。
func _ensure_eos_burst_audio_buses() -> void:
	var build_idx := _eos_burst_ensure_bus("EosBuild")
	var release_idx := _eos_burst_ensure_bus("EosRelease")
	# EosImpactはsidechainのsource/送り先busとして存在させるだけで、
	# それ自身にeffectは不要(README §Aの役割分担どおり)。
	_eos_burst_ensure_bus("EosImpact")
	for bus_idx in [build_idx, release_idx]:
		if AudioServer.get_bus_effect_count(bus_idx) == 0:
			var comp := AudioEffectCompressor.new()
			comp.threshold = -18.0
			comp.ratio = 6.0
			comp.attack_us = 1000.0
			comp.release_ms = 140.0
			comp.gain = 0.0
			comp.mix = 1.0
			comp.sidechain = "EosImpact"
			AudioServer.add_bus_effect(bus_idx, comp)
	var master_idx := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for i in AudioServer.get_bus_effect_count(master_idx):
		var fx := AudioServer.get_bus_effect(master_idx, i)
		if fx is AudioEffectLimiter or fx is AudioEffectHardLimiter:
			has_limiter = true
			break
	if not has_limiter and ClassDB.class_exists("AudioEffectHardLimiter"):
		var limiter: AudioEffectHardLimiter = ClassDB.instantiate("AudioEffectHardLimiter")
		limiter.ceiling_db = -0.3
		limiter.pre_gain_db = 0.0
		AudioServer.add_bus_effect(master_idx, limiter)


func _eos_burst_ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx != -1:
		return idx
	idx = AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


## 「着弾直前55msだけ『吸い込み』を作る」(README §C) — approach開始から
## の相対秒`t_rel`で①`t_rel<0.350`: 通常(0dB)②`0.350〜0.405`: -7dBまで
## smoothstepで滑らかにduck③`0.405`以降、実contactイベント
## (`_eos_burst_assault_released()`)が来るまでは-7dBのまま保持(hitstopの
## 間、tick基準elapsedが凍結されるため`t_rel`もこの区間ずっと0.420で
## 止まったまま——別Timerで0.42秒を推測しない、既存のhitstop自体が
## 「保持」を作る)④解除された瞬間から120〜160msでduckを解く(mid値
## 140ms、`_eos_burst_contact_trigger_elapsed`を共有基準点に使う——
## フラッシュ・shakeと同じ1つの記録値)。戻り値は加算するdB(0.0=無変化、
## 負値=duck中)。
func _eos_burst_bus_duck_db() -> float:
	var t_rel := _eos_burst_smooth_elapsed(_battle_anim_phase_elapsed) - EOS_BURST_APPROACH_START_SECONDS
	if t_rel < EOS_BURST_DUCK_START_SECONDS:
		return 0.0
	if _eos_burst_contact_trigger_elapsed >= 0.0:
		var age := _eos_burst_smooth_elapsed(_battle_anim_phase_elapsed) - _eos_burst_contact_trigger_elapsed
		var t := clampf(age / EOS_BURST_DUCK_RECOVER_SECONDS, 0.0, 1.0)
		return lerpf(EOS_BURST_DUCK_PEAK_DB, 0.0, smoothstep(0.0, 1.0, t))
	if t_rel < EOS_BURST_DUCK_RAMP_END_SECONDS:
		var t2 := (t_rel - EOS_BURST_DUCK_START_SECONDS) \
			/ (EOS_BURST_DUCK_RAMP_END_SECONDS - EOS_BURST_DUCK_START_SECONDS)
		return lerpf(0.0, EOS_BURST_DUCK_PEAK_DB, smoothstep(0.0, 1.0, clampf(t2, 0.0, 1.0)))
	return EOS_BURST_DUCK_PEAK_DB  ## held through 0.405〜hitstop release


func _eos_burst_set_bus_duck_db(db: float) -> void:
	var build_idx := AudioServer.get_bus_index("EosBuild")
	var release_idx := AudioServer.get_bus_index("EosRelease")
	if build_idx != -1:
		AudioServer.set_bus_volume_db(build_idx, db)
	if release_idx != -1:
		AudioServer.set_bus_volume_db(release_idx, db)


## True while the current queued step is healing's own "act" phase — same
## guard shape as _rapid_slash_vfx_active(), used by every draw/update
## function below.
func _healing_vfx_active() -> bool:
	if _battle_anim_phase != "act" or _battle_anim_step < 0 \
			or _battle_anim_step >= _battle_anim_queue.size():
		return false
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	return str(entry.get("skill_id", "")) == HEALING_SKILL_ID


func _healing_debug_log(msg: String) -> void:
	_healing_debug_log_counts[msg] = int(_healing_debug_log_counts.get(msg, 0)) + 1
	print(msg)


## Sotiris's own hand/sword height — he never moves during this cast (user
## spec: "中央へ移動しない"), so this is just his resting formation slot,
## not a staged/advanced position like rapid_slash's caster.
func _healing_caster_pos(view: Rect2, unit_id: int) -> Vector2:
	var frac := _formation_pos(unit_id)
	return Vector2(
		view.position.x + view.size.x * frac.x,
		view.position.y + view.size.y * frac.y - float(PARTY_ICON_PX) * 0.5)


## The selected ally's own on-screen position — computed from target_id
## EVERY call, never a fixed/cached coordinate and never the caster's own
## position (user spec's core bug-fix requirement: "回復VFXの位置は、固定
## 座標やソティリスではなく、実際に選択されたtarget_idの足元・中央位置か
## ら計算する"). feet=true returns the ground point (magic circle/pillar
## base); feet=false returns chest height (beam's own arrival point).
func _healing_target_pos(view: Rect2, target_id: int, feet: bool = true) -> Vector2:
	var frac := _formation_pos(target_id)
	var y_offset := 0.0 if feet else -float(PARTY_ICON_PX) * 0.5
	return Vector2(
		view.position.x + view.size.x * frac.x, view.position.y + view.size.y * frac.y + y_offset)


## The value _draw_party_row's on-field HP bar (and, via _sync_healing_
## target_card, the bottom command-bar card) show for a given slot: the
## real hp for everyone except the heal's own target, which goes through 2
## stages — sim.minions[].hp already reads the POST-heal value the instant
## resolve_boss_round() ran (same "sim resolves atomically, display
## catches up" gap rapid_slash's own boss HP bar has always had to
## bridge), so:
## 1. From cast start until the hit lands, _healing_hold_pre_heal freezes
##    the display at the reconstructed PRE-heal value — without this the
##    display jumped to the post-heal number from frame one, well before
##    the beam even reaches the target (2026-07-26 round-2 fix, caught by
##    this round's own headless trace: a card read "70/70" at t=0.05s,
##    long before the 0.92s hit moment).
## 2. Once the hit lands, _healing_hp_anim_t drives a short lerp UP from
##    that same pre-heal value to real_hp instead of an instant jump.
func _healing_display_hp(unit_id: int, real_hp: int) -> float:
	if unit_id != _healing_target_unit:
		return float(real_hp)
	if _healing_hold_pre_heal:
		return float(_healing_hp_display_before)
	if _healing_hp_anim_t > 0.0:
		var reveal := 1.0 - clampf(_healing_hp_anim_t / HEALING_HP_BAR_ANIM_SECONDS, 0.0, 1.0)
		return lerpf(float(_healing_hp_display_before), float(real_hp), smoothstep(0.0, 1.0, reveal))
	return float(real_hp)


## User spec (2026-07-26, round 2): "戦場上のHPバーと下部カードのHP表示を
## 両方更新する". The bottom command-bar card is a real Control built ONCE
## when command selection opens (_make_battle_card) and otherwise never
## touched again mid-round — without this, it kept showing the PRE-heal
## number for the rest of the round, and forever if the round happened to
## end in victory (_finish_battle_round's "won" branch hides the whole
## panel without ever rebuilding cards, since the party usually also kills
## the boss the same round it heals). Runs every "act"-phase tick via
## _update_healing_state, reusing the exact same smoothed value the
## on-field bar uses so both climb in sync; a harmless no-op once _healing_
## hp_anim_t has decayed (falls through to plain unit.hp, matching what a
## freshly-rebuilt card would already show).
func _sync_healing_target_card() -> void:
	if _healing_target_unit < 0 or _healing_target_unit >= sim.minions.size():
		return
	if not _battle_cards.has(_healing_target_unit):
		return
	var unit: UDMinion = sim.minions[_healing_target_unit]
	var display := _healing_display_hp(_healing_target_unit, unit.hp)
	var entry: Dictionary = _battle_cards[_healing_target_unit]
	var hp_label: Label = entry.get("hp_label")
	var hp_bar: ProgressBar = entry.get("hp_bar")
	if hp_label != null:
		hp_label.text = "HP %d/%d" % [int(round(display)), sim.unit_max_hp(unit)]
	if hp_bar != null:
		hp_bar.value = display


## Per-tick housekeeping: decays the 2 timers healing owns, keeps the
## command-bar card's HP display in sync, and fires the one-shot debug
## logs for the 4 beats with no other natural one-shot event to attach to
## (orb/beam/circle/pillar are otherwise plain elapsed-time checks in the
## draw functions below, not stateful objects — see the HEALING_*
## constants' own doc comments for why that's sufficient here, unlike
## rapid_slash's 3 staggered waves).
func _update_healing_state(dt: float, elapsed: float) -> void:
	if _healing_target_flash_t > 0.0:
		_healing_target_flash_t = maxf(0.0, _healing_target_flash_t - dt)
	if _healing_hp_anim_t > 0.0:
		_healing_hp_anim_t = maxf(0.0, _healing_hp_anim_t - dt)
	_sync_healing_target_card()
	if not _healing_orb_logged and elapsed >= HEALING_ORB_START_SECONDS:
		_healing_orb_logged = true
		_healing_debug_log("HEALING orb formed")
		_play_healing_sfx("charge")
	if not _healing_beam_launch_logged and elapsed >= HEALING_BEAM_START_SECONDS:
		_healing_beam_launch_logged = true
		_healing_debug_log("HEALING beam launched")
	if not _healing_beam_arrive_logged and elapsed >= HEALING_BEAM_END_SECONDS:
		_healing_beam_arrive_logged = true
		_healing_debug_log("HEALING beam arrived")
	if not _healing_circle_logged and elapsed >= HEALING_CIRCLE_START_SECONDS:
		_healing_circle_logged = true
		_healing_debug_log("HEALING circle appeared")
	if not _healing_pillar_logged and elapsed >= HEALING_PILLAR_START_SECONDS:
		_healing_pillar_logged = true
		_healing_debug_log("HEALING pillar started")
	if not _healing_pillar_end_logged and elapsed >= HEALING_CIRCLE_FADE_START_SECONDS:
		_healing_pillar_end_logged = true
		_healing_debug_log("HEALING pillar ended")
		_play_healing_sfx("afterglow")


## User spec item 7: fully clear healing's own VFX state the moment its act
## phase ends — same belt-and-suspenders dual-reset lifecycle rapid_slash's
## _reset_rapid_slash_vfx_state uses (fresh state is ALSO seeded at the
## START of the next cast, in _enter_battle_anim_act_phase; this call is
## what actually logs the reset and guarantees no stale state lingers in
## between casts).
func _reset_healing_vfx_state() -> void:
	_healing_target_unit = -1
	_healing_target_flash_t = 0.0
	_healing_hp_display_before = 0
	_healing_hold_pre_heal = false
	_healing_hp_anim_t = 0.0
	_healing_orb_logged = false
	_healing_beam_launch_logged = false
	_healing_beam_arrive_logged = false
	_healing_circle_logged = false
	_healing_pillar_logged = false
	_healing_pillar_end_logged = false
	_healing_debug_log("HEALING VFX state reset")


## Caster-side gathering orb (user spec: "0.18〜0.48秒...小さな金白色の光
## 球が集まる。細かな光粒子を少量だけ上昇させる").
func _draw_healing_orb(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < HEALING_ORB_START_SECONDS or elapsed >= HEALING_ORB_END_SECONDS:
		return
	var pos := _healing_caster_pos(view, unit_id)
	var window := HEALING_ORB_END_SECONDS - HEALING_ORB_START_SECONDS
	var t := clampf((elapsed - HEALING_ORB_START_SECONDS) / window, 0.0, 1.0)
	var grow := clampf(t / 0.5, 0.0, 1.0)
	# Swell-before-launch pulse (user spec: "光球が一度だけ少し膨らんでから
	# 対象へ飛ぶ") — one smoothstep-shaped bump peaking exactly at the
	# window's end, immediately before the beam takes over (HEALING_BEAM_
	# START_SECONDS == HEALING_ORB_END_SECONDS, so there's no gap between
	# "swells" and "launches").
	var swell_t := clampf(
		(elapsed - (HEALING_ORB_END_SECONDS - HEALING_ORB_SWELL_SECONDS)) / HEALING_ORB_SWELL_SECONDS,
		0.0, 1.0)
	var swell := 1.0 + (HEALING_ORB_SWELL_SCALE - 1.0) * sin(swell_t * PI * 0.5)
	var radius := HEALING_ORB_RADIUS_PX * grow * swell
	draw_circle(pos, radius, Color(1.0, 0.95, 0.75, 0.55 * grow))
	draw_circle(pos, radius * 0.5, Color(1.0, 1.0, 0.92, 0.85 * grow))
	# Particles converge INWARD toward the gathering point over the final
	# stretch of the window (user spec: "小さな光粒子を3〜4個だけ吸い込ま
	# せる" — drawn IN, not rising away like the old version).
	var converge_start := HEALING_ORB_END_SECONDS - HEALING_ORB_CONVERGE_SECONDS
	var converge_t := clampf((elapsed - converge_start) / HEALING_ORB_CONVERGE_SECONDS, 0.0, 1.0)
	for i in HEALING_ORB_PARTICLE_COUNT:
		var angle := TAU * float(i) / float(HEALING_ORB_PARTICLE_COUNT) + 0.6
		var dist := lerpf(15.0, 0.0, converge_t)
		var p := pos + Vector2(cos(angle), sin(angle)) * dist
		draw_circle(p, 1.4, Color(1.0, 0.95, 0.7, 0.3 + 0.6 * converge_t))


## Quadratic-Bezier control point for the beam's curved arc (user spec:
## "直線的な弾ではなく、緩やかな弧を描いて対象へ届く") — bulges upward off
## the straight caster->target line, scaled to the travel distance so a
## short hop still visibly arcs.
func _healing_beam_control(start: Vector2, target: Vector2) -> Vector2:
	var mid := (start + target) * 0.5
	var bulge := maxf(HEALING_BEAM_ARC_MIN_PX, absf(target.x - start.x) * HEALING_BEAM_ARC_FRAC)
	return mid + Vector2(0.0, -bulge)


func _healing_beam_point(start: Vector2, control: Vector2, target: Vector2, t: float) -> Vector2:
	var a := start.lerp(control, t)
	var b := control.lerp(target, t)
	return a.lerp(b, t)


## Travelling light from the caster's own sword tip to the SELECTED ally's
## chest height (user spec, 2026-07-26 re-fix: "剣先から回復対象の胸元ま
## で、金白色の曲線状の光を伸ばす。先端には白い核と金色の外光。後ろに2〜
## 3個の光粒子。直線ではなく緩やかな弧を描く。移動時間は約0.30秒。現在よ
## り2〜3倍見やすく") — a curved trail (sampled along the same Bezier the
## head travels) plus a bright two-tone head and a short fading comet tail,
## growing from the caster toward the target as it travels (never the
## reverse, never past the target).
func _draw_healing_beam(view: Rect2, unit_id: int, elapsed: float, entry: Dictionary) -> void:
	if elapsed < HEALING_BEAM_START_SECONDS or elapsed >= HEALING_BEAM_END_SECONDS:
		return
	var target_id := int(entry.get("target_id", unit_id))
	var start := _healing_caster_pos(view, unit_id)
	var target := _healing_target_pos(view, target_id, false)
	var control := _healing_beam_control(start, target)
	var t := clampf((elapsed - HEALING_BEAM_START_SECONDS) / HEALING_BEAM_DURATION_SECONDS, 0.0, 1.0)
	var eased := smoothstep(0.0, 1.0, t)
	var segments := 14
	var last := start
	for i in range(1, segments + 1):
		var p := _healing_beam_point(start, control, target, eased * float(i) / float(segments))
		draw_line(last, p, Color(1.0, 0.92, 0.6, 0.85), 5.0)
		last = p
	var head := last
	# User spec (2026-07-26 round 2): "白い核を少し小さくし、後ろに柔らかな
	# 金色の粒子を残してください" — the trajectory/timing stay as-is (user
	# spec: "現在の光の軌道は良いため維持してください"), only the core size
	# (0.55->0.34 of the outer glow) and trail softness change, so the head
	# reads as a gentle light rather than a hard attack projectile.
	draw_circle(head, HEALING_BEAM_HEAD_RADIUS_PX, Color(1.0, 0.8, 0.32, 0.5))  # gold outer glow
	draw_circle(head, HEALING_BEAM_HEAD_RADIUS_PX * 0.34, Color(1.0, 0.98, 0.9, 1.0))  # white core
	for i in HEALING_BEAM_TRAIL_COUNT:
		var trail_t := eased - float(i + 1) * HEALING_BEAM_TRAIL_GAP_T
		if trail_t <= 0.0:
			continue
		var tp := _healing_beam_point(start, control, target, trail_t)
		var falloff := 1.0 - float(i) / float(HEALING_BEAM_TRAIL_COUNT)
		# A soft, larger low-alpha halo behind each trailing particle's
		# brighter core reads as "soft gold" rather than a row of hard dots.
		draw_circle(tp, HEALING_BEAM_HEAD_RADIUS_PX * 0.5 * falloff, Color(1.0, 0.85, 0.55, 0.28 * falloff))
		draw_circle(tp, HEALING_BEAM_HEAD_RADIUS_PX * 0.26 * falloff, Color(1.0, 0.92, 0.68, 0.6 * falloff))


## Magic circle at the target's own feet (user spec, 2026-07-26 re-fix:
## "キャラ幅の約1.4倍の金白色の魔法陣...色は金白色を中心に...淡い緑を加え
## る"; size comes from HEALING_CIRCLE_MAX_RADIUS_PX, which is itself
## derived from PARTY_ICON_PX), held at full size through the pillar phase,
## then fades out during the lingering window. Stays in the ground layer —
## this is the one element the user spec explicitly keeps BEHIND the
## target ("魔法陣は対象の後ろ").
func _draw_healing_circle(view: Rect2, unit_id: int, elapsed: float, entry: Dictionary) -> void:
	if elapsed < HEALING_CIRCLE_START_SECONDS or elapsed >= HEALING_CIRCLE_END_SECONDS:
		return
	var target_id := int(entry.get("target_id", unit_id))
	var pos := _healing_target_pos(view, target_id, true)
	var radius := HEALING_CIRCLE_MAX_RADIUS_PX
	if elapsed < HEALING_CIRCLE_GROW_END_SECONDS:
		var grow_t := (elapsed - HEALING_CIRCLE_START_SECONDS) \
			/ (HEALING_CIRCLE_GROW_END_SECONDS - HEALING_CIRCLE_START_SECONDS)
		radius = lerpf(HEALING_CIRCLE_MIN_RADIUS_PX, HEALING_CIRCLE_MAX_RADIUS_PX, smoothstep(0.0, 1.0, grow_t))
	var alpha := 1.0
	if elapsed >= HEALING_CIRCLE_FADE_START_SECONDS:
		alpha = 1.0 - clampf(
			(elapsed - HEALING_CIRCLE_FADE_START_SECONDS)
				/ (HEALING_CIRCLE_END_SECONDS - HEALING_CIRCLE_FADE_START_SECONDS),
			0.0, 1.0)
	draw_arc(pos, radius, 0.0, TAU, 32, Color(1.0, 0.92, 0.6, 0.78 * alpha), 4.0)
	draw_arc(pos, radius * 0.68, 0.0, TAU, 24, Color(0.75, 1.0, 0.78, 0.44 * alpha), 2.5)


## Light pillar COLUMN only (user spec round 2: "対象の後ろに柔らかな縦方
## 向の光柱を追加する" — explicitly back in the ground/BEHIND layer, see
## HEALING_PILLAR_ALPHA's own doc comment). Fades in from HEALING_PILLAR_
## START_SECONDS, holds, then fades out over the SAME post-heal window the
## circle uses (HEALING_CIRCLE_FADE_START/END_SECONDS) so the column and
## circle disappear together rather than the column cutting off on its own
## separate schedule (user spec: "回復VFX全体を...滑らかにフェードさせる").
func _draw_healing_pillar_column(view: Rect2, unit_id: int, elapsed: float, entry: Dictionary) -> void:
	if elapsed < HEALING_PILLAR_START_SECONDS or elapsed >= HEALING_CIRCLE_END_SECONDS:
		return
	var target_id := int(entry.get("target_id", unit_id))
	var pos := _healing_target_pos(view, target_id, true)
	var fade_in := clampf(
		(elapsed - HEALING_PILLAR_START_SECONDS) / HEALING_PILLAR_FADE_IN_SECONDS, 0.0, 1.0)
	var fade_out := 1.0
	if elapsed >= HEALING_CIRCLE_FADE_START_SECONDS:
		fade_out = 1.0 - clampf(
			(elapsed - HEALING_CIRCLE_FADE_START_SECONDS)
				/ (HEALING_CIRCLE_END_SECONDS - HEALING_CIRCLE_FADE_START_SECONDS),
			0.0, 1.0)
	var rect := Rect2(
		pos + Vector2(-HEALING_PILLAR_WIDTH_PX * 0.5, -HEALING_PILLAR_HEIGHT_PX),
		Vector2(HEALING_PILLAR_WIDTH_PX, HEALING_PILLAR_HEIGHT_PX))
	draw_rect(rect, Color(1.0, 0.95, 0.72, HEALING_PILLAR_ALPHA * fade_in * fade_out))


## Rising particles ONLY (user spec: "上へ昇る金白色の粒子"; "回復成立後も
## 約0.4秒、細かな粒子を上へ残す") — stays in the FRONT layer (see
## HEALING_PILLAR_ALPHA's doc comment for why only the column moved back).
func _draw_healing_rising_particles(view: Rect2, unit_id: int, elapsed: float, entry: Dictionary) -> void:
	if elapsed < HEALING_PILLAR_START_SECONDS or elapsed >= HEALING_LINGER_END_SECONDS:
		return
	var target_id := int(entry.get("target_id", unit_id))
	var pos := _healing_target_pos(view, target_id, true)
	var linger_fade := 1.0
	if elapsed >= HEALING_CIRCLE_FADE_START_SECONDS:
		linger_fade = 1.0 - clampf(
			(elapsed - HEALING_CIRCLE_FADE_START_SECONDS)
				/ (HEALING_LINGER_END_SECONDS - HEALING_CIRCLE_FADE_START_SECONDS),
			0.0, 1.0)
	var cycle := HEALING_LINGER_PARTICLE_CYCLE_SECONDS
	for i in HEALING_LINGER_PARTICLE_COUNT:
		var phase := fmod(
			(elapsed - HEALING_PILLAR_START_SECONDS) + float(i) * cycle / float(HEALING_LINGER_PARTICLE_COUNT),
			cycle) / cycle
		var py := pos.y - phase * HEALING_PILLAR_HEIGHT_PX * 1.15
		var px := pos.x + sin(phase * TAU + float(i) * 1.3) * 6.0
		var falpha := (1.0 - phase) * 0.85 * linger_fade
		draw_circle(Vector2(px, py), 1.8, Color(1.0, 0.95, 0.75, falpha))


## Encircling ring (user spec: "対象の周囲を一周する淡い緑色の光") — a
## short comet of fading dots that sweeps once around an ellipse centered
## on the target's chest, so it reads as light travelling AROUND the
## character rather than a motionless halo. Front layer.
func _draw_healing_ring(view: Rect2, unit_id: int, elapsed: float, entry: Dictionary) -> void:
	if elapsed < HEALING_RING_START_SECONDS \
			or elapsed >= HEALING_RING_START_SECONDS + HEALING_RING_DURATION_SECONDS:
		return
	var target_id := int(entry.get("target_id", unit_id))
	var center := _healing_target_pos(view, target_id, true) + Vector2(0.0, -float(PARTY_ICON_PX) * 0.5)
	var t := (elapsed - HEALING_RING_START_SECONDS) / HEALING_RING_DURATION_SECONDS
	for i in HEALING_RING_TRAIL_COUNT:
		var trail_t := t - float(i) * HEALING_RING_TRAIL_GAP_T
		if trail_t < 0.0 or trail_t > 1.0:
			continue
		var angle := trail_t * TAU - PI * 0.5
		var p := center + Vector2(
			cos(angle) * HEALING_RING_RADIUS_X, sin(angle) * HEALING_RING_RADIUS_Y)
		var alpha := (1.0 - float(i) / float(HEALING_RING_TRAIL_COUNT)) * 0.6
		draw_circle(p, 2.4, Color(0.65, 1.0, 0.72, alpha))


## Ground-layer dispatcher (magic circle + pillar COLUMN — user spec round
## 2: "魔法陣は対象の後ろ" / "対象の後ろに柔らかな縦方向の光柱を追加す
## る", both explicitly BEHIND) — called BEFORE _draw_party_row in
## _draw_boss_battle so the target's own sprite always layers on top, same
## "dust drawn behind the character" precedent RAPID_SLASH_DUST established.
func _draw_healing_ground_vfx(view: Rect2) -> void:
	if not _healing_vfx_active():
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	var unit_id := int(entry.get("unit_id", 0))
	var elapsed := _battle_anim_phase_elapsed
	_draw_healing_circle(view, unit_id, elapsed, entry)
	_draw_healing_pillar_column(view, unit_id, elapsed, entry)


## Front-layer dispatcher (caster orb + travelling beam + the target-side
## rising-particles/ring) — called AFTER _draw_party_row, same position
## rapid_slash's own charge/wave/impact drawing occupies. User spec: "光粒
## 子と発光は対象の前に表示してください" — only the rising particles/ring
## stay here now; the pillar's own column moved back to the ground layer
## this round (see HEALING_PILLAR_ALPHA's doc comment).
func _draw_healing_caster_vfx(view: Rect2) -> void:
	if not _healing_vfx_active():
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	var unit_id := int(entry.get("unit_id", 0))
	var elapsed := _battle_anim_phase_elapsed
	_draw_healing_orb(view, unit_id, elapsed)
	_draw_healing_beam(view, unit_id, elapsed, entry)
	_draw_healing_rising_particles(view, unit_id, elapsed, entry)
	_draw_healing_ring(view, unit_id, elapsed, entry)


## ================= ソウルブレイク helpers ==============================

## True while the current queued step is soul_break's own "act" phase —
## same guard shape as _rapid_slash_vfx_active()/_healing_vfx_active(),
## used by every draw/update function below.
func _soul_break_vfx_active() -> bool:
	if _battle_anim_phase != "act" or _battle_anim_step < 0 \
			or _battle_anim_step >= _battle_anim_queue.size():
		return false
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	return str(entry.get("skill_id", "")) == SOUL_BREAK_SKILL_ID


func _soul_break_debug_log(msg: String) -> void:
	_soul_break_debug_log_counts[msg] = int(_soul_break_debug_log_counts.get(msg, 0)) + 1
	print(msg)


## One AudioStreamPlayer per delivered WAV — same pattern _build_rapid_
## slash_sfx/_build_healing_sfx use. A missing file leaves stream null and
## _play_soul_break_sfx() then silently no-ops, the same "quietly skip if
## the asset isn't there" tolerance this project applies everywhere.
func _build_soul_break_sfx() -> void:
	for key: String in SOUL_BREAK_SFX_PATHS:
		var path := str(SOUL_BREAK_SFX_PATHS[key])
		var player := AudioStreamPlayer.new()
		if ResourceLoader.exists(path):
			player.stream = load(path)
		add_child(player)
		_soul_break_sfx_players[key] = player


func _play_soul_break_sfx(key: String) -> void:
	var player: AudioStreamPlayer = _soul_break_sfx_players.get(key)
	if player != null and player.stream != null:
		player.play()


## Fires every cue whose act-relative time has been reached, once each per
## cast (guarded by _soul_break_sfx_fired). Driven from _update_soul_
## break_state so it shares the exact same elapsed clock the visuals read
## — there is no separate audio timer that could drift from the animation.
func _update_soul_break_sfx(elapsed: float) -> void:
	for cue: Array in SOUL_BREAK_SFX_CUES:
		var key := str(cue[0])
		if _soul_break_sfx_fired.has(key):
			continue
		if elapsed >= float(cue[1]):
			_soul_break_sfx_fired[key] = true
			_play_soul_break_sfx(key)


## Stance-step/hold/recoil/return-out x_offset (user spec: "0.00〜0.15秒
## 約10pxだけ前へ踏み込む"; "0.42〜0.50秒...上半身を少しだけ後ろへ反動さ
## せる"; "1.15〜1.45秒...元の位置へ戻り始める...正確に戻す") — the SAME
## draw-time x_offset mechanism knockback/rapid_slash's own advance
## already use. _battle_anim_pos[unit_id] itself never moves (see _enter_
## battle_anim_act_phase and the "act" phase position block's own no-op
## SOUL_BREAK_SKILL_ID branches) — only this pixel offset does, so "キャラ
## サイズと足元アンカーは固定"/"キャラクター本体は拡大縮小しない" hold by
## construction (position offset only, never a scale change).
func _soul_break_advance_offset_px(elapsed: float) -> float:
	var base := 0.0
	if elapsed < SOUL_BREAK_STANCE_SECONDS:
		base = SOUL_BREAK_STEP_PX * smoothstep(0.0, 1.0, elapsed / SOUL_BREAK_STANCE_SECONDS)
	elif elapsed < SOUL_BREAK_RETURN_START_SECONDS:
		base = SOUL_BREAK_STEP_PX
	elif elapsed < SOUL_BREAK_RETURN_END_SECONDS:
		var t := (elapsed - SOUL_BREAK_RETURN_START_SECONDS) \
			/ (SOUL_BREAK_RETURN_END_SECONDS - SOUL_BREAK_RETURN_START_SECONDS)
		base = SOUL_BREAK_STEP_PX * (1.0 - smoothstep(0.0, 1.0, t))
	# Launch recoil (user spec: "ソティリスの上半身を少しだけ後ろへ反動さ
	# せる") — a brief negative dip layered on TOP of the held step-in,
	# peaking mid-launch-window and settling back to the held value by
	# the window's own end, so it never fights with the stance/return
	# easing above.
	if elapsed >= SOUL_BREAK_LAUNCH_SECONDS and elapsed < SOUL_BREAK_LAUNCH_SECONDS + SOUL_BREAK_RECOIL_SECONDS:
		var lt := (elapsed - SOUL_BREAK_LAUNCH_SECONDS) / SOUL_BREAK_RECOIL_SECONDS
		base -= SOUL_BREAK_RECOIL_PX * sin(lt * PI)
	return base


## Same lookup shape RAPID_SLASH_ACTOR_FRAMES/HEALING_ACTOR_FRAMES-style
## absolute-second breakpoint tables use — holds at the last breakpoint
## (frame 2) for the whole rest of the cast; see SOUL_BREAK_ACTOR_FRAMES'
## own doc comment for why no separate return table is needed this time.
## v10 fix: `elapsed` accumulates via repeated += dt at runtime, while each
## breakpoint here is a one-shot literal — headless verification caught a
## real skipped frame from this (elapsed landed at 0.549999999999999993
## for the tick meant to show frame 3 at breakpoint 0.55, comparing false
## by one bit, so frame 3 was silently skipped and the display jumped
## straight from 2 to 4). A tiny epsilon absorbs that float-accumulation
## noise without meaningfully shifting any real breakpoint.
const SOUL_BREAK_FRAME_EPSILON := 0.0005

func _soul_break_actor_frame_index(elapsed: float) -> int:
	var result := 0
	for pair: Array in SOUL_BREAK_ACTOR_FRAMES:
		if elapsed >= float(pair[0]) - SOUL_BREAK_FRAME_EPSILON:
			result = int(pair[1])
		else:
			break
	return result


## Sotiris's own hand/sword height, INCLUDING the current step-in offset
## (unlike healing's caster, which never moves at all) — the gather VFX
## should visually originate from wherever the character actually is at
## that instant, not the pre-step formation slot.
func _soul_break_caster_pos(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var frac := _formation_pos(unit_id)
	return Vector2(
		view.position.x + view.size.x * frac.x + _soul_break_advance_offset_px(elapsed),
		view.position.y + view.size.y * frac.y - float(PARTY_ICON_PX) * 0.5)


## Auto-adapts to whichever enemy is currently active (user spec: "対象敵
## が変わっても、敵の胴体中央を自動的に着弾位置として使用してください") —
## _boss_icon_rect already reads the CURRENT boss/enemy consistently, so
## its geometric center needs no per-enemy special-casing.
func _soul_break_target_pos(view: Rect2) -> Vector2:
	var rect := _boss_icon_rect(view)
	return rect.position + rect.size * 0.5


## v18: the AIM point (user spec section 4: "命中地点は敵の胴体中央よ
## り少し上にしてください...target_pos := enemy.global_position +
## Vector2(0, -enemy_height*0.12)") — used ONLY for the flight's own
## destination and for computing hit_dir/hit_angle (see _soul_break_hit_
## dir below), never for where the impact-side visuals are centered
## (those still anchor at the TRUE _soul_break_target_pos above — see
## section 7's own "敵の胴体中央を破壊エフェクトの中心にしてください").
func _soul_break_hit_target_pos(view: Rect2) -> Vector2:
	var target := _soul_break_target_pos(view)
	return target + Vector2(0.0, -float(BOSS_ICON_PX) * SOUL_BREAK_HIT_TARGET_UP_FRAC)


## v19: where the blade's ANCHOR stops — solved so the blade's own TIP
## ends up biting SOUL_BREAK_ENEMY_BITE_FRAC into the enemy from its
## front (caster-facing) face, instead of driving the anchor all the way
## to the enemy's centre and letting the tip shoot out the far side (the
## "敵の身体をほぼ完全に通過してから消えています" bug).
##
## Derivation, all along hit_dir:
##   tip_end     = aim_point - hit_dir * front_inset
##   anchor_end  = tip_end   - hit_dir * BLADE_TIP_OFFSET_PX
## where front_inset is how far back from the enemy's CENTRE the desired
## bite point sits, measured from the enemy's own displayed width — so
## this scales automatically with the enemy's size rather than using any
## fixed coordinate (user spec: "固定座標ではなく敵の表示範囲...から...
## 計算してください").
func _soul_break_flight_end_pos(view: Rect2, unit_id: int) -> Vector2:
	var aim := _soul_break_hit_target_pos(view)
	var hit_dir := _soul_break_hit_dir(view, unit_id)
	var rect := _boss_icon_rect(view)
	var front_inset := rect.size.x * (0.5 - SOUL_BREAK_ENEMY_BITE_FRAC)
	return aim - hit_dir * (front_inset + SOUL_BREAK_BLADE_TIP_OFFSET_PX)


## v7's "SoulBreakSwordTip" anchor (see its consts' own doc comment for
## why this is a function, not a real Marker2D node) — a fixed pixel
## offset from the caster's current hand/chest point, offset toward the
## enemy along x (mirrored by facing) and up along y. EVERY gather shard,
## the core, and the projectile's launch point all read this SAME
## function, so they can never drift apart from one another (user spec:
## "すべてSoulBreakSwordTip.global_positionを基準にする").
func _soul_break_sword_tip_pos(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var base := _soul_break_caster_pos(view, unit_id, elapsed)
	var target := _soul_break_target_pos(view)
	var direction := signf(target.x - base.x)
	if direction == 0.0:
		direction = 1.0
	var local_offset: Vector2
	if elapsed < SOUL_BREAK_DOWNSWING_START_SECONDS:
		# Overhead — unchanged for the whole windup/hold/gather/core span
		# (user spec protects the shard-convergence performance, which
		# reads THIS same anchor the entire time it runs).
		local_offset = SOUL_BREAK_SWING_TIP_OFFSETS[0]
	else:
		# Sweeps smoothly through the 3 downswing key points (overhead-
		# >face->chest->lower-right) as a piecewise-linear path, decoupled
		# from which discrete attack_minion_N FRAME is showing (same
		# "continuous position, discrete sprite" split rapid_slash/healing
		# already established) — settles at the last point once C ends,
		# which is also where D/launch read it from.
		var t := clampf(
			(elapsed - SOUL_BREAK_DOWNSWING_START_SECONDS) / SOUL_BREAK_SWING_C_SECONDS, 0.0, 1.0)
		var seg_count := SOUL_BREAK_SWING_TIP_OFFSETS.size() - 1
		var scaled := t * float(seg_count)
		var seg := clampi(int(scaled), 0, seg_count - 1)
		var seg_t := clampf(scaled - float(seg), 0.0, 1.0)
		local_offset = SOUL_BREAK_SWING_TIP_OFFSETS[seg].lerp(SOUL_BREAK_SWING_TIP_OFFSETS[seg + 1], seg_t)
	return base + Vector2(local_offset.x * direction, local_offset.y)


## Per-tick housekeeping: fires the one-shot debug logs for the beats with
## no other natural one-shot event to attach to (the damage-confirm beat
## logs its own "SOUL_BREAK damage fired" directly from _on_battle_anim_
## tick's hit_now branch, guarded by the existing _battle_anim_hit_fired,
## not duplicated here). v16: also updates the 2 afterimage stamps here
## (a TICK-driven update, not a draw-time one) so their spawn cadence
## tracks real elapsed time consistently regardless of how many times
## _draw() itself gets invoked per tick.
func _update_soul_break_state(_dt: float, elapsed: float, unit_id: int) -> void:
	_update_soul_break_afterimages(_view_rect(), unit_id, elapsed)
	_update_soul_break_sfx(elapsed)
	if not _soul_break_gather_logged and elapsed >= SOUL_BREAK_GATHER_START_SECONDS:
		_soul_break_gather_logged = true
		_soul_break_debug_log("SOUL_BREAK gather started")
	if not _soul_break_hold_logged and elapsed >= SOUL_BREAK_SHARD_LAST_ARRIVE_SECONDS:
		_soul_break_hold_logged = true
		_soul_break_debug_log("SOUL_BREAK core hold started")
	if not _soul_break_downswing_logged and elapsed >= SOUL_BREAK_DOWNSWING_START_SECONDS:
		_soul_break_downswing_logged = true
		_soul_break_debug_log("SOUL_BREAK downswing started")
	if not _soul_break_launch_logged and elapsed >= SOUL_BREAK_LAUNCH_SECONDS:
		_soul_break_launch_logged = true
		_soul_break_debug_log("SOUL_BREAK launched and flying")
	if not _soul_break_followthrough_logged and elapsed >= SOUL_BREAK_RECOVER_START_SECONDS:
		_soul_break_followthrough_logged = true
		_soul_break_debug_log("SOUL_BREAK recovery started")
	if not _soul_break_impact_logged and elapsed >= SOUL_BREAK_CONTACT_SECONDS:
		_soul_break_impact_logged = true
		_soul_break_debug_log("SOUL_BREAK impact sprite started")
	if not _soul_break_burst_logged and elapsed >= SOUL_BREAK_HIT_AT_SECONDS:
		_soul_break_burst_logged = true
		_soul_break_debug_log("SOUL_BREAK burst started")
	if not _soul_break_return_logged and elapsed >= SOUL_BREAK_RETURN_START_SECONDS:
		_soul_break_return_logged = true
		_soul_break_debug_log("SOUL_BREAK return started")


func _reset_soul_break_state() -> void:
	_soul_break_gather_logged = false
	_soul_break_hold_logged = false
	_soul_break_launch_logged = false
	_soul_break_downswing_logged = false
	_soul_break_followthrough_logged = false
	_soul_break_impact_logged = false
	_soul_break_burst_logged = false
	_soul_break_return_logged = false
	_soul_break_contact_flash_fired = false
	_soul_break_sfx_fired.clear()
	_soul_break_proj_flight_active = false
	_soul_break_proj_flight_elapsed = 0.0
	_soul_break_afterimages.clear()
	_soul_break_debug_log("SOUL_BREAK VFX state reset")


## Deterministic pseudo-random 0..1 (a fixed trig-based hash, NOT UDSim._
## rng — this is pure UI decoration with zero gameplay effect, same
## category as terrain variant selection's hash(cell) seeding). Every
## jagged shape below calls this so the SAME seed always produces the SAME
## jitter (stable across every replay of the same cast), never true
## randomness.
func _soul_break_jag(seed_i: int) -> float:
	var x := sin(float(seed_i) * 12.9898) * 43758.5453
	return x - floor(x)


## Quadratic-Bezier point — used by the gather's curved shard motion
## (user spec: "曲線を描きながら...集まる", same technique HEALING_BEAM_*
## already established for its own curved travelling light).
func _soul_break_bezier_point(start: Vector2, control: Vector2, target: Vector2, t: float) -> Vector2:
	var a := start.lerp(control, t)
	var b := control.lerp(target, t)
	return a.lerp(b, t)


## A small rotated square — the "崩れる" (crumbling) dot-fragment unit
## reused for both the flight's trailing shards and the afterglow's
## lingering motes. NOT a circle, NOT blurred.
func _draw_soul_break_shard_square(pos: Vector2, size: float, rotation: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in 4:
		var angle := rotation + PI * 0.5 * float(i)
		pts.append(pos + Vector2(cos(angle), sin(angle)) * size * 0.7071)
	draw_colored_polygon(pts, color)


## Jagged NEEDLE silhouette (user spec v4: "現在の大きな紫色の三角形は廃
## 止...白紫の細い魂核＋不規則な尖った外周＋短い破片尾にする。閉じた三角
## 形、カーソル形、巨大な白い穴は使わない") — a thin zigzagging outline
## (in-out-in-out along its length) rather than a smoothly widening
## triangle/comet, so the silhouette itself reads as broken/jagged instead
## of a single solid wedge.
func _soul_break_needle_points(
		pos: Vector2, dir: Vector2, length: float, width: float, seed_offset: int) -> PackedVector2Array:
	var perp := Vector2(-dir.y, dir.x)
	var base_offsets := [
		Vector2(0.6, 0.0), Vector2(0.05, 0.28), Vector2(-0.35, 0.12),
		Vector2(-0.55, 0.0), Vector2(-0.35, -0.12), Vector2(0.05, -0.28),
	]
	var pts := PackedVector2Array()
	for i in base_offsets.size():
		var o: Vector2 = base_offsets[i]
		var jag := 0.85 + _soul_break_jag(i * 5 + seed_offset) * 0.3
		pts.append(pos + (dir * o.x * length + perp * o.y * width) * jag)
	return pts


## A single soul-shard "flame", v8 redesign (user spec: "3個の魂片を、そ
## れぞれ7×5px程度の欠けた菱形／炎片にする...白紫の1〜2pxの核と、濃紫の
## 不規則な外殻を持たせる" — the shard's own BODY is now the irregular
## dark-purple shell itself (v7's mid-purple filled diamond is gone), with
## a NOTCH (a point pulled inward, `mid_back`) breaking the outline so it
## reads as "欠けた" (chipped/broken) rather than a clean closed diamond.
## `dir` is the shard's current direction of travel (nose points this
## way); `bend` perturbs the upper/lower silhouette asymmetrically so the
## 3 calls (A/B/C) don't read as identical stamped copies.
func _draw_soul_break_shard_flame(pos: Vector2, size: float, dir: Vector2, bend: float, alpha: float) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var nose := pos + dir * size * 0.6
	var upper := pos + dir * size * (0.1 + bend) + perp * size * (0.36 - bend * 0.2)
	var notch := pos - dir * size * 0.15 + perp * size * 0.12  ## the "chip" — pulled inward
	var tail := pos - dir * size * 0.55
	var lower := pos + dir * size * (0.1 - bend) - perp * size * (0.32 + bend * 0.2)
	var outline := PackedVector2Array([nose, upper, notch, tail, lower])
	draw_colored_polygon(outline, Color(0.32, 0.14, 0.45, alpha))
	# 1-2px white-purple core, biased toward the nose — user spec: "白紫
	# の1〜2pxの核".
	_fill_soul_break_dot(pos + dir * size * 0.2, 1.5, Color(0.92, 0.85, 1.0, alpha))


## Small filled polygon standing in for a "dot" without ever being a true
## circle (user spec bans perfect circles for every soul_break element) —
## a compact diamond, cheap to fill via draw_colored_polygon.
func _fill_soul_break_dot(pos: Vector2, radius: float, color: Color) -> void:
	var pts := PackedVector2Array([
		pos + Vector2(0.0, -radius), pos + Vector2(radius, 0.0),
		pos + Vector2(0.0, radius), pos + Vector2(-radius, 0.0),
	])
	draw_colored_polygon(pts, color)


## Soul-shard gather, v8 redesign (user spec: "剣先に紫色が突然出現した
## ように見える...魂片の収束を通常速度でも読めるようにする"). Each shard
## now has its OWN fixed 0.18s travel window starting at its own staggered
## time — arrivals are staggered too (unlike v7's synced-arrival design),
## which is exactly what makes the convergence itself readable as 3
## separate, individually-timed objects rather than a single instantaneous
## pop. See SOUL_BREAK_SHARD_TRAVEL_SECONDS' own doc comment for why the
## overlap window ("3個すべての軌道が一度は同時に見える時間") is
## guaranteed regardless of tick alignment.
func _draw_soul_break_gather(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_GATHER_START_SECONDS or elapsed >= SOUL_BREAK_SHARD_LAST_ARRIVE_SECONDS:
		return
	var tip := _soul_break_sword_tip_pos(view, unit_id, elapsed)
	var target := _soul_break_target_pos(view)
	var facing := signf(target.x - tip.x)
	if facing == 0.0:
		facing = 1.0
	for i in SOUL_BREAK_SHARD_COUNT:
		var start_time := SOUL_BREAK_GATHER_START_SECONDS \
			+ float(i) * SOUL_BREAK_SHARD_START_STAGGER_SECONDS
		var arrive_time := start_time + SOUL_BREAK_SHARD_TRAVEL_SECONDS
		if elapsed < start_time or elapsed >= arrive_time:
			continue
		var local_offset: Vector2 = SOUL_BREAK_SHARD_LOCAL_OFFSETS[i]
		var start_pos := tip + Vector2(local_offset.x * facing, local_offset.y)
		var t := clampf((elapsed - start_time) / SOUL_BREAK_SHARD_TRAVEL_SECONDS, 0.0, 1.0)
		var eased := smoothstep(0.0, 1.0, t)
		var mid := (start_pos + tip) * 0.5 + Vector2(0.0, SOUL_BREAK_SHARD_BULGE_PX[i])
		var shard_pos := _soul_break_bezier_point(start_pos, mid, tip, eased)
		# Analytic quadratic-bezier derivative (ignoring the constant *2.0
		# factor, irrelevant after normalize) — the shard's true direction
		# of travel at this instant, so its flame nose always points the
		# right way instead of a fixed/guessed direction.
		var deriv := (mid - start_pos) * (1.0 - eased) + (tip - mid) * eased
		var dir := deriv.normalized() if deriv.length() > 0.001 else (tip - start_pos).normalized()
		var bend := (float(i) - 1.0) * 0.12  ## -0.12/0.0/0.12: 3 distinct silhouettes
		_draw_soul_break_shard_flame(shard_pos, SOUL_BREAK_SHARD_SIZE_PX, dir, bend, 0.9)


## Core hold, v10 redesign (user spec: "到着後、頭上の構えを0.06〜0.08秒
## 保持する。この保持中に魂核を細長く圧縮する" — a SINGLE already-
## compressed state for the whole short hold, replacing v9's 2-stage
## squeeze(12x6)->stretch(28x6) snap — see SOUL_BREAK_CORE_HOLD_SECONDS'
## own doc comment for why). Guard starts at SOUL_BREAK_SHARD_LAST_
## ARRIVE_SECONDS (the moment the LAST shard reaches the tip) and ends at
## SOUL_BREAK_CORE_HOLD_END_SECONDS (when the downswing begins).
func _draw_soul_break_core_compress(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_SHARD_LAST_ARRIVE_SECONDS or elapsed >= SOUL_BREAK_CORE_HOLD_END_SECONDS:
		return
	var tip := _soul_break_sword_tip_pos(view, unit_id, elapsed)
	var target := _soul_break_target_pos(view)
	var facing := signf(target.x - tip.x)
	if facing == 0.0:
		facing = 1.0
	var dir := Vector2(facing, 0.0)
	var length := SOUL_BREAK_CORE_HOLD_LENGTH_PX
	var width := SOUL_BREAK_CORE_HOLD_WIDTH_PX
	var outer := _soul_break_needle_points(tip, dir, length, width, 21)
	draw_colored_polygon(outer, Color(0.45, 0.22, 0.6, 0.85))
	var mid := _soul_break_needle_points(tip, dir, length * 0.7, width * 0.75, 27)
	draw_colored_polygon(mid, Color(0.72, 0.52, 0.9, 0.9))
	var inner := _soul_break_needle_points(tip, dir, length * 0.4, width * 0.45, 33)
	draw_colored_polygon(inner, Color(1.0, 0.98, 1.0, 1.0))
	# 2 small dark-purple fragments around the core (user spec: "周囲：小
	# さな破片2個", carried over unchanged from v7).
	_draw_soul_break_shard_square(
		tip + Vector2(-width * 0.6, -width * 0.9), 2.5, elapsed * 3.0, Color(0.32, 0.14, 0.45, 0.8))
	_draw_soul_break_shard_square(
		tip + Vector2(width * 0.5, width * 0.9), 2.2, elapsed * 3.0 + 1.5, Color(0.32, 0.14, 0.45, 0.8))


## v18: the flight's own speed profile (user spec section 4: "最初の15%
## で素早く加速、中盤はほぼ等速、命中直前は減速させない") — a uniformly-
## accelerated ramp for the first 15% of t (0.5*a*t^2, classic constant-
## acceleration kinematics) reaching a cruise velocity exactly AT the 15%
## mark, then constant velocity (linear) for the remaining 85%, with the
## cruise velocity solved so total distance covered still sums to
## EXACTLY 1.0 at t=1.0 (no position discontinuity at the handoff, and no
## deceleration anywhere — the linear tail never eases out).
func _soul_break_flight_ease(t: float) -> float:
	var accel_frac := 0.15
	var v_cruise := 1.0 / (1.0 - 0.5 * accel_frac)
	if t <= accel_frac:
		return 0.5 * (v_cruise / accel_frac) * t * t
	return 0.5 * v_cruise * accel_frac + v_cruise * (t - accel_frac)


## v20 NEW: separation. Draws the SAME blade texture during the new
## SOUL_BREAK_SEPARATION_SECONDS window (downswing-end to LAUNCH_SECONDS)
## — user spec: "最初のフレームでは剣先と飛翔体を接触させる、次のフレー
## ムから前方へ離す". At t=0 the blade's own anchor sits exactly on the
## LIVE sword tip (_soul_break_sword_tip_pos, the same point the downswing
## pose itself is drawn from, so it visibly touches the blade the sword
## just swung), then eases toward the fixed flight spawn point
## (_soul_break_proj_origin_pos) it will actually launch from — by t=1 it
## is already sitting exactly where _draw_soul_break_flight's own first
## frame begins, so there is no pop when that function takes over one
## tick later. Rotation blends from the downswing's own final swing
## direction to the shared hit_dir, so the blade doesn't snap-rotate
## either.
func _draw_soul_break_separation(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_DOWNSWING_END_SECONDS or elapsed >= SOUL_BREAK_LAUNCH_SECONDS:
		return
	var tex := _soul_break_blade_texture()
	if tex == null:
		return
	var t := clampf(
		(elapsed - SOUL_BREAK_DOWNSWING_END_SECONDS) / SOUL_BREAK_SEPARATION_SECONDS, 0.0, 1.0)
	var tip := _soul_break_sword_tip_pos(view, unit_id, elapsed)
	var spawn := _soul_break_proj_origin_pos(view, unit_id)
	var pos := tip.lerp(spawn, smoothstep(0.0, 1.0, t))
	var hit_dir := _soul_break_hit_dir(view, unit_id)
	var swing_dir := (spawn - tip).normalized() if tip.distance_to(spawn) > 0.5 else hit_dir
	var rotation := swing_dir.lerp(hit_dir, smoothstep(0.0, 1.0, t)).angle()
	var local_rect := Rect2(-SOUL_BREAK_BLADE_ANCHOR_PX, SOUL_BREAK_BLADE_CANVAS_SIZE)
	draw_set_transform(pos, rotation, Vector2.ONE)
	draw_texture_rect(tex, local_rect, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Flight, v19: the blade travels from the sword tip to _soul_break_
## flight_end_pos — the anchor position that leaves its own TIP biting
## ~22.5% into the enemy's front face (see that function's derivation).
## It is then GONE: the draw gate ends exactly at SOUL_BREAK_FLIGHT_END_
## SECONDS, which is also SOUL_BREAK_CONTACT_SECONDS/MAX_IMPACT_SECONDS,
## so blade-vanish and the whole impact event share one instant with no
## gap between them (user spec: "その場で飛翔体を消す...同じフレームで着
## 弾X字を発生...空白時間を完全に無くしてください"). v17-fix's separate
## post-arrival penetration glide is removed — the bite depth now lives
## in where the flight ENDS rather than in a continuation past it.
## Drawn with only a rotation transform — no scale, no modulate, no extra
## outline; the blade's art/size/colour are frozen this round.
func _draw_soul_break_flight(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_LAUNCH_SECONDS or elapsed >= SOUL_BREAK_FLIGHT_END_SECONDS:
		return
	var tex := _soul_break_blade_texture()
	if tex == null:
		return
	# v14: origin/back-end (user spec: "projectile_visualの原点を本体の
	# 後端にする") — the launch-instant sword tip, not a live position, so
	# this stays decoupled from anything the character does for the rest
	# of the cast, same as every prior round.
	var start := _soul_break_proj_origin_pos(view, unit_id)
	var target := _soul_break_flight_end_pos(view, unit_id)
	var hit_dir := _soul_break_hit_dir(view, unit_id)
	var rotation := hit_dir.angle()
	# v13: POSITION reads the continuous, _process()-driven timer (user
	# spec: "移動が5段階のワープに見えず、毎フレーム滑らかに") instead of
	# the tick-quantized `elapsed` — deliberately on separate clocks
	# ("位置移動は別管理にする"). Falls back to the tick-based fraction if
	# _process() somehow hasn't run yet this instant (e.g. the very first
	# redraw), so this never divides by a stale/zero state.
	var flight_t: float = _soul_break_proj_flight_elapsed if _soul_break_proj_flight_active \
		else (elapsed - SOUL_BREAK_LAUNCH_SECONDS)
	var t := clampf(flight_t / SOUL_BREAK_FLIGHT_SECONDS, 0.0, 1.0)
	# v18 speed profile (user spec: "最初の15%で素早く加速、中盤はほぼ等
	# 速、命中直前は減速させない") — see _soul_break_flight_ease's own doc
	# comment for the construction.
	var pos := start.lerp(target, _soul_break_flight_ease(t))
	# The art's own local (0,0) = SOUL_BREAK_BLADE_ANCHOR_PX (the body's
	# own back end); draw_set_transform makes that point land exactly on
	# `pos`, then the texture rect is expressed in that same local space
	# (same "draw_set_transform(pos, rotation, ONE), draw at local
	# origin, reset" pattern _draw_rapid_slash_wave already uses). Scale
	# stays Vector2.ONE and the destination rect matches the texture's
	# own native size 1:1 throughout, so the blade never grows/shrinks.
	var local_rect := Rect2(-SOUL_BREAK_BLADE_ANCHOR_PX, SOUL_BREAK_BLADE_CANVAS_SIZE)
	draw_set_transform(pos, rotation, Vector2.ONE)
	draw_texture_rect(tex, local_rect, false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _soul_break_blade_texture() -> Texture2D:
	return _soul_break_load_texture("res://assets/vfx/sotiris/%s.png" % SOUL_BREAK_BLADE_KEY)


## v17: _soul_break_proj_texture() (the v15 single-static-texture loader)
## is retired outright — the main flying body is now the animated 4-frame
## twin-cleave (_soul_break_twin_cleave_frame above), loaded through the
## same generic _soul_break_load_texture cache every other v16/v17 VFX
## asset already uses.


## v16: generic cached loader for the 2 NEW recolored VFX assets (see
## _soul_break_texture_cache's own doc comment) — same null-safe,
## ResourceLoader.exists()-gated pattern as _soul_break_proj_texture, just
## keyed by path so it covers more than one file without near-duplicate
## functions.
func _soul_break_load_texture(path: String) -> Texture2D:
	if not _soul_break_texture_cache.has(path):
		var tex: Texture2D = null
		if ResourceLoader.exists(path):
			tex = load(path)
		_soul_break_texture_cache[path] = tex
	return _soul_break_texture_cache[path]


## v16 stage 1 (予備動作): a small white soul-light at the sword tip,
## swelling 1.25x in the last ~0.06s before launch (see SOUL_BREAK_TIP_
## LIGHT_* consts' own doc comment) — purely additive on top of the
## existing, unchanged gather/core-hold/downswing.
func _draw_soul_break_tip_light(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_TIP_LIGHT_START_SECONDS or elapsed >= SOUL_BREAK_LAUNCH_SECONDS:
		return
	var tip := _soul_break_sword_tip_pos(view, unit_id, elapsed)
	var scale := SOUL_BREAK_TIP_LIGHT_SWELL_SCALE if elapsed >= SOUL_BREAK_TIP_LIGHT_SWELL_SECONDS else 1.0
	_fill_soul_break_dot(tip, SOUL_BREAK_TIP_LIGHT_RADIUS_PX * scale, Color(0.95, 0.9, 1.0, 0.9))


## v16 stage 2 (発射): the recolored rapid_slash wave_a crescent, shown
## briefly at launch and anchored to the SAME origin the projectile
## spawns from (user spec: "剣閃の終点と飛翔体の後端を完全に接続する") —
## centered a quarter of its own width forward of that shared origin so
## it visibly extends OUT from that seam rather than straddling the
## character.
func _draw_soul_break_launch_arc(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_LAUNCH_ARC_START_SECONDS or elapsed >= SOUL_BREAK_LAUNCH_ARC_END_SECONDS:
		return
	var tex := _soul_break_load_texture("res://assets/vfx/sotiris/%s.png" % SOUL_BREAK_LAUNCH_ARC_KEY)
	if tex == null:
		return
	var origin := _soul_break_proj_origin_pos(view, unit_id)
	# v18: reads the SAME shared hit_dir the flight/impact layers use
	# (previously computed its own separate direction toward the true
	# target) — keeps every visual element pointed the same way.
	var forward := _soul_break_hit_dir(view, unit_id)
	var rotation := forward.angle()
	var draw_size := Vector2(SOUL_BREAK_LAUNCH_ARC_DRAW_PX, SOUL_BREAK_LAUNCH_ARC_DRAW_PX)
	var center := origin + forward * draw_size.x * 0.25
	draw_set_transform(center, rotation, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-draw_size / 2.0, draw_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## v16 stage 3 (飛翔): updates the 2 STAMPED afterimage slots — called
## once per TICK (from _update_soul_break_state), never from a draw call,
## so spawn cadence tracks real elapsed time regardless of how many times
## _draw() itself fires per tick. Each slot re-stamps (spawn position +
## rotation reset) the instant its OWN previous stamp has fully aged out
## (refresh interval == that slot's own lifetime), matching user spec:
## "残像は本体の現在位置へ追従させず、生成された位置へ短時間残す" — once
## stamped, a slot's position is held fixed until it next re-stamps, never
## recomputed from the live body position in between.
func _update_soul_break_afterimages(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_LAUNCH_SECONDS or elapsed >= SOUL_BREAK_FLIGHT_END_SECONDS:
		return
	if _soul_break_afterimages.is_empty():
		# v19: seeded FROM the const arrays' own size (was a hardcoded 2
		# entries) so changing the ghost count is a one-line const edit —
		# this round drops it to exactly 1, see SOUL_BREAK_AFTERIMAGE_
		# DIST_PX's own doc comment.
		for _i in SOUL_BREAK_AFTERIMAGE_DIST_PX.size():
			_soul_break_afterimages.append(
				{"pos": Vector2.ZERO, "rotation": 0.0, "spawn_time": -999.0})
	var origin := _soul_break_proj_origin_pos(view, unit_id)
	# v19: same stop point the blade itself now uses, so the ghost tracks
	# the real path instead of the old (further) enemy-centre aim.
	var target := _soul_break_flight_end_pos(view, unit_id)
	var hit_dir := _soul_break_hit_dir(view, unit_id)
	var rotation := hit_dir.angle()
	var flight_t: float = _soul_break_proj_flight_elapsed if _soul_break_proj_flight_active \
		else (elapsed - SOUL_BREAK_LAUNCH_SECONDS)
	var t := clampf(flight_t / SOUL_BREAK_FLIGHT_SECONDS, 0.0, 1.0)
	# v18: same eased speed profile the main blade uses (see _soul_break_
	# flight_ease's own doc comment) — stamps land on the ACTUAL blade
	# path, not a naive linear lerp.
	var body_pos := origin.lerp(target, _soul_break_flight_ease(t))
	for i in _soul_break_afterimages.size():
		var slot: Dictionary = _soul_break_afterimages[i]
		var lifetime: float = SOUL_BREAK_AFTERIMAGE_LIFETIME[i]
		if elapsed - float(slot["spawn_time"]) >= lifetime:
			slot["pos"] = body_pos - hit_dir * SOUL_BREAK_AFTERIMAGE_DIST_PX[i]
			slot["rotation"] = rotation
			slot["spawn_time"] = elapsed
			_soul_break_afterimages[i] = slot


## Draws whichever afterimage slots are still within their own lifetime
## (see _update_soul_break_afterimages' own doc comment for the stamping
## rule) — the SAME blade texture at native size (user spec: "拡大しな
## い"), fading out over its own fixed lifetime.
func _draw_soul_break_afterimages(elapsed: float) -> void:
	if _soul_break_afterimages.is_empty():
		return
	var tex := _soul_break_blade_texture()
	if tex == null:
		return
	var local_rect := Rect2(-SOUL_BREAK_BLADE_ANCHOR_PX, SOUL_BREAK_BLADE_CANVAS_SIZE)
	for i in _soul_break_afterimages.size():
		var slot: Dictionary = _soul_break_afterimages[i]
		var age := elapsed - float(slot["spawn_time"])
		var lifetime: float = SOUL_BREAK_AFTERIMAGE_LIFETIME[i]
		if age < 0.0 or age >= lifetime:
			continue
		var alpha_base: float = SOUL_BREAK_AFTERIMAGE_ALPHA[i]
		var alpha := alpha_base * (1.0 - age / lifetime)
		draw_set_transform(slot["pos"], float(slot["rotation"]), Vector2.ONE)
		draw_texture_rect(tex, local_rect, false, Color(1.0, 1.0, 1.0, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## v18, layer A (接触閃光): a short white-purple line drawn THROUGH the
## TRUE enemy center along hit_angle — user spec: "敵の中心に細い白紫の
## 切断線...向きはhit_angleと同じ". A thin tapered quad, same technique
## _draw_soul_break_trail_quad already uses elsewhere in this file for
## thin line strokes.
func _draw_soul_break_impact_line(view: Rect2, unit_id: int, elapsed: float) -> void:
	var start_t := SOUL_BREAK_CONTACT_SECONDS + SOUL_BREAK_IMPACT_LINE_START_OFFSET
	if elapsed < start_t or elapsed >= start_t + SOUL_BREAK_IMPACT_LINE_SECONDS:
		return
	var age := elapsed - start_t
	var alpha := 1.0 - age / SOUL_BREAK_IMPACT_LINE_SECONDS
	var anchor := _soul_break_target_pos(view)
	var hit_dir := _soul_break_hit_dir(view, unit_id)
	var half := hit_dir * SOUL_BREAK_IMPACT_LINE_LENGTH_PX * 0.5
	_draw_soul_break_trail_quad(
		anchor - half, anchor + half, SOUL_BREAK_IMPACT_LINE_WIDTH_PX, alpha * 0.9)


## v19, layer B — the BROKEN X ("壊れたX字"). Replaces v18's branching
## crack, which never read as an X. Two arms straddling hit_angle at
## +/-SOUL_BREAK_IMPACT_X_ARM_SPREAD_RAD, so the cross is always oriented
## to the flight direction (never a fixed horizontal X). Each arm is
## drawn as 3 stacked passes — outer deep purple (thickest), inner pale
## purple, centre white (thinnest) — matching the user's "中央：白 /
## 内側：薄紫 / 外側：濃い紫". "Broken" comes from each arm being split
## into segments with deterministic gaps rather than one solid stroke.
## Scale animates 0.75 -> 1.12 over GROW_SECONDS then holds while fading
## over FADE_SECONDS (user spec section 3's exact numbers).
##
## Drawn from _draw_soul_break_top_layer, which runs AFTER the shared
## white screen flash — this is what keeps the X readable instead of
## being washed out (the actual cause of "壊れたX字がほとんど見えませ
## ん": the flash rect was painted over it every time).
func _draw_soul_break_impact_crack(view: Rect2, unit_id: int, elapsed: float) -> void:
	var start_t := SOUL_BREAK_CONTACT_SECONDS + SOUL_BREAK_IMPACT_CRACK_START_OFFSET
	if elapsed < start_t or elapsed >= start_t + SOUL_BREAK_IMPACT_X_SECONDS:
		return
	var age := elapsed - start_t
	var scale := SOUL_BREAK_IMPACT_X_SCALE_TO
	var alpha := 1.0
	if age < SOUL_BREAK_IMPACT_X_GROW_SECONDS:
		var g := age / SOUL_BREAK_IMPACT_X_GROW_SECONDS
		scale = lerpf(SOUL_BREAK_IMPACT_X_SCALE_FROM, SOUL_BREAK_IMPACT_X_SCALE_TO,
			smoothstep(0.0, 1.0, g))
	else:
		var f := (age - SOUL_BREAK_IMPACT_X_GROW_SECONDS) / SOUL_BREAK_IMPACT_X_FADE_SECONDS
		alpha = 1.0 - clampf(f, 0.0, 1.0)
	var center := _soul_break_target_pos(view)
	var hit_angle := _soul_break_hit_dir(view, unit_id).angle()
	var arm := SOUL_BREAK_IMPACT_X_ARM_PX * scale
	for side in 2:
		var a := hit_angle + (SOUL_BREAK_IMPACT_X_ARM_SPREAD_RAD if side == 0
			else -SOUL_BREAK_IMPACT_X_ARM_SPREAD_RAD)
		var dir := Vector2(cos(a), sin(a))
		var tip_a := center - dir * arm
		var tip_b := center + dir * arm
		# 3 colour passes, thickest/darkest first so the white centre
		# lands on top (user spec's own inside-out ordering).
		_draw_soul_break_broken_stroke(tip_a, tip_b, 9.0, Color(0.35, 0.08, 0.60, alpha * 0.95), side)
		_draw_soul_break_broken_stroke(tip_a, tip_b, 5.0, Color(0.85, 0.72, 1.0, alpha * 0.95), side)
		_draw_soul_break_broken_stroke(tip_a, tip_b, 2.0, Color(1.0, 0.99, 1.0, alpha), side)


## One arm of the broken X: a straight run split into segments with
## deterministic gaps punched out, so the stroke reads as fractured
## rather than a clean drawn line. Reuses the existing jag hash for the
## gap pattern (no RNG — this project's determinism convention).
func _draw_soul_break_broken_stroke(
		a: Vector2, b: Vector2, width: float, color: Color, seed_i: int) -> void:
	var segments := 7
	for i in segments:
		# Punch out 2 deterministic gaps per arm.
		var j := _soul_break_jag(i * 13 + seed_i * 31 + 5)
		if j < 0.28:
			continue
		var t0 := float(i) / float(segments)
		var t1 := float(i + 1) / float(segments)
		var p0 := a.lerp(b, t0)
		var p1 := a.lerp(b, t1)
		var dir := p1 - p0
		if dir.length() < 0.01:
			continue
		var perp := Vector2(-dir.y, dir.x).normalized()
		draw_colored_polygon(PackedVector2Array([
			p0 + perp * width * 0.5, p1 + perp * width * 0.5,
			p1 - perp * width * 0.5, p0 - perp * width * 0.5,
		]), color)


## v19: the soul_break elements that must survive the shared white screen
## flash. _draw_boss_battle paints that flash AFTER every skill's own VFX
## pass, so anything drawn inside _draw_soul_break_vfx is behind it — the
## direct cause of the user's "白い画面フラッシュが強く、壊れたX字がほと
## んど見えません" report. This runs after the flash rect instead, which
## is the "X字をより上のCanvasLayerへ置く" remedy the spec asks for,
## expressed in this file's single-_draw() architecture as draw order.
## Only soul_break's own X-cross moves up; nothing else changes layer, so
## no other skill's visuals are affected.
func _draw_soul_break_top_layer(view: Rect2) -> void:
	if not _soul_break_vfx_active():
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	_draw_soul_break_impact_crack(view, int(entry.get("unit_id", 0)), _battle_anim_phase_elapsed)


## ================= エオスバースト helpers =============================

## Same guard shape as _soul_break_vfx_active()/_rapid_slash_vfx_active().
func _eos_burst_vfx_active() -> bool:
	if _battle_anim_phase != "act" or _battle_anim_step < 0 \
			or _battle_anim_step >= _battle_anim_queue.size():
		return false
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	return str(entry.get("skill_id", "")) == EOS_BURST_SKILL_ID


func _eos_burst_log(msg: String) -> void:
	if _eos_burst_logged.has(msg):
		return
	_eos_burst_logged[msg] = true
	print(msg)


func _eos_burst_log_at(key: String, elapsed: float) -> void:
	if _eos_burst_logged.has(key):
		return
	_eos_burst_logged[key] = elapsed
	print("%s t=%.3f" % [key, elapsed])


## Same breakpoint-table lookup shape (and the same float-accumulation
## epsilon) the other dedicated skills' own frame tables use.
func _eos_burst_actor_frame_index(elapsed: float) -> int:
	var result := 0
	for pair: Array in EOS_BURST_ACTOR_FRAMES:
		if elapsed >= float(pair[0]) - SOUL_BREAK_FRAME_EPSILON:
			result = int(pair[1])
		else:
			break
	return result


## Solves how far the caster must travel to stand just clear of the
## enemy's near edge — from the CURRENT enemy rect, never a fixed screen
## coordinate. Clamped so the caster can never be pushed off-screen or end
## up BEHIND its own origin if the enemy is somehow already close.
## 「動きのカクつきを根本修正する」(2026-08-06) — `_process`が維持する
## 連続elapsed(実delta加算、tick基準elapsedへ活性化の瞬間に同期)を返す。
## `_eos_burst_smooth_root_active`がfalseの間(例えば`_process`が一度も
## 呼ばれていないheadlessテスト——このsagaの検証テストの大半は`_on_
## battle_anim_tick()`だけを手動ループで呼ぶ)はtick基準の`tick_elapsed`
## そのものへフォールバックする——退行にはならず、従来どおりの(段階的
## だが正しい)動作を保つ。位置カーブを計算する各関数の"どの分岐に入るか"
## というフェーズ境界判定には使わない(常にtick_elapsed自身で判定)——
## 分岐内の補間係数(t)の計算にだけ使うことで、ヒットストップ・接触・SFX
## のタイミングには一切影響しない。
func _eos_burst_smooth_elapsed(tick_elapsed: float) -> float:
	if _eos_burst_smooth_root_active:
		return _eos_burst_smooth_root_elapsed_value
	return tick_elapsed


## 「現行ソティリス維持版 v3」(2026-08-12) — 「現行ソティリスの座標...を
## 維持してください」「新しいCharacterBody2Dや...拡大したソティリスを
## 新しく作らないでください」という最優先指示により、今回は前進すら
## 行わない(前ラウンドの20-30px許容も含め完全に撤去、常に0.0px)。竜
## (`_eos_burst_dragon_advance_offset_px`)もこの同じ関数を経由するため、
## ソティリスと竜は常に同じだけ動かない(分離しない、という不変条件は
## 「動かない」場合にも当然成立する)。
const EOS_BURST_APPROACH_MAX_PX := 0.0
func _eos_burst_solve_approach_offset(_view: Rect2, _unit_id: int) -> float:
	return EOS_BURST_APPROACH_MAX_PX


## 「エオスバーストの攻撃主体をソティリスへ一本化」(2026-08-02、同日
## 2ラウンド目) — the previous round's "always 0.0" (dragon stays put and
## roars in place) is exactly what made it read as an independent summoned
## creature rather than Sotiris's own light. Restored to real movement:
## Sotiris eases from his formation position to just short of the enemy
## across APPROACH_SECONDS, holds there through release/impact/vanish, then
## eases back across the existing (protected, unchanged-duration) RETURN
## window. Distance comes from `_eos_burst_solve_approach_offset` — solved
## live from the CURRENT enemy rect every call, never a cached/fixed value,
## so it still tracks correctly even if the boss rect's own geometry ever
## changes.
## 「natural dragon motion」(2026-08-07) — 竜はもうこの関数を直接は呼ばない
## (`_eos_burst_dragon_advance_offset_px`、下記、を呼ぶ)——README「竜の頭は
## ソティリスの約0.035秒後に追従を開始する視覚的な遅延」を実現するため。
## ただしAPPROACH区間の外(hold/return/vanish)ではその新関数がこの関数へ
## そのままフォールバックするため、「2つは絶対に分離しない」という不変
## 条件はAPPROACH区間の外では今も保たれている——APPROACH中だけ、README
## 自身が明示的に許可した意図的な例外。
func _eos_burst_advance_offset_px(view: Rect2, unit_id: int, elapsed: float) -> float:
	if elapsed < EOS_BURST_APPROACH_START_SECONDS:
		return 0.0
	var target := _eos_burst_solve_approach_offset(view, unit_id)
	if elapsed < EOS_BURST_APPROACH_END_SECONDS:
		# 「動きのカクつきを根本修正する」(2026-08-06) — tは連続elapsed
		# (`_eos_burst_smooth_elapsed`)から計算(=毎レンダーフレームで滑らか
		# に進行)、どの分岐に入るかの判定自体は上の`elapsed`(tick基準)の
		# まま——フェーズ境界・ヒットストップ・接触タイミングは無影響。
		var t := clampf(
			(_eos_burst_smooth_elapsed(elapsed) - EOS_BURST_APPROACH_START_SECONDS)
				/ EOS_BURST_APPROACH_SECONDS,
			0.0, 1.0)
		# 「竜の接近モーション修正」(2026-08-06) — ease-out-cubic(前半に速度
		# 集中)からease-in-quad(後半に速度集中、"穏やかな加速")へ。RETURN
		# (帰還、下のease-out-cubic)は既存のまま無改修。
		return target * _eos_burst_ease_in_quad(t)
	if elapsed < EOS_BURST_RETURN_START_SECONDS:
		return target
	if elapsed < EOS_BURST_RETURN_END_SECONDS:
		var t2 := clampf(
			(_eos_burst_smooth_elapsed(elapsed) - EOS_BURST_RETURN_START_SECONDS)
				/ EOS_BURST_RETURN_SECONDS,
			0.0, 1.0)
		return target * (1.0 - _eos_burst_ease_out_cubic(t2))
	return 0.0


## 「Dragon / Aura Lock-step Follow Fix v1」(2026-08-07) — 前々ラウンド
## 「SMALLER_REAR_DRAGON_ANCHORED_AURA_SMOOTH_SLASH v11」(2026-08-14) —
## 旧`_eos_burst_dragon_advance_offset_px`(`_eos_burst_advance_offset_px`
## への薄いパススルー、旧`_eos_burst_dragon_rect`だけが呼んでいた)は、
## 竜の位置決めを共通足元anchor方式(`_eos_burst_rear_anchor_pos`が
## `_eos_burst_advance_offset_px`を直接呼ぶ)へ全面書き換えたことで
## 呼び出し元が無くなったため削除した(grep確認済み)。
## 「grounded dragon + continuous motion + scream roar v6」(2026-08-07) —
## 前ラウンドの「小さい弧」(`local_y = -5*sin(PI*p_dragon)`)は、実際の座標/
## scaleでは演出量ではなく竜全体(胴・尻尾を含む単一矩形の平行移動)を
## 上へ持ち上げる結果になっていたため完全撤去した(`_eos_burst_dragon_
## head_arc_offset_px`/`EOS_BURST_DRAGON_ARC_PEAK_PX`ごと削除)。竜のroot
## Yは下記`_eos_burst_dragon_rect`で「頭のX方向補正だけを使い、Y方向補正は
## 一切使わない」設計に変更——竜のroot Yは今後、接近区間を通じて常に一定
## (詳細はそちらのdoc comment参照)。旧関数を復元する場合は`git log`を参照。


## 「完成した竜画像全体をTweenで右へ滑らせる方式は禁止です。6枚の異なる
## 身体姿勢を使ってください」(2026-08-05、同日追加ラウンド) — 旧・竜
## 専用の反動オフセット(発射フレームで後方へ3px、0.08秒で復帰)は、単一
## 静止ポーズの絵を手続き的な動きで補う旧世代の仕組みだった。新しい6コマ
## `eos_dragon_assault_6f.png`自身が既に反動を含む一連の動きを持つため
## 撤去した(`_eos_burst_dragon_recoil_offset_px`ごと削除、`git log`に
## 経緯が残る)。


## 可変デュレーション表を消費する汎用フレームインデックス・ルックアップ
## (2026-08-05、同日追加ラウンドでDRY化——竜の出現・ソティリスの突き・
## タメオーラ・着弾の4つがそれぞれ独自の累積走査ループを持っていたのを
## この1関数へ統合)。`durations`の先頭から順に累積し、`age`がその累積を
## 下回った最初のインデックスを返す。`age`が表の合計を超えたら最終コマで
## クランプ。
func _eos_burst_frame_index_from_table(durations: Array[float], age: float) -> int:
	var acc := 0.0
	for i in durations.size():
		acc += durations[i]
		if age < acc:
			return i
	return durations.size() - 1


## 「竜の接近モーション修正」(2026-08-06) — 旧`_eos_burst_thrust_pose_
## frame_index`(EOS_BURST_THRUST_FRAME_DURATIONS消費)は、到着後
## (STRIKE_PREP_START以降)の静止した0.24秒間だけをコマ送りする仕組み
## だった——移動中は常にframe0(竜が縦向きのまま移動して見えるバグの
## 直接の原因)。ここでは呼び出し元を持たなくなったが、`EOS_BURST_THRUST_
## FRAME_DURATIONS`自体は削らず残置(前ラウンドの「配列自体は削らず残置」
## 方針を踏襲、index0-2は下記の新関数の秒数と依然一致する)。
##
## 新設`_eos_burst_approach_pose_progress`: 移動開始(APPROACH_START)から
## 0.0、到着(APPROACH_END)で1.0に達し、以降は1.0のまま(STRIKE_PREP/
## LUNGE/RELEASEの間も1.0で held——「48-100%/65-100%: 長い突進姿勢を
## 保ったまま敵へ進む」をこの1本のクランプ式だけで満たす、以降HIT_AT
## までの間に別の分岐は不要)。位置移動のイージング(ease-in-quad)とは
## 独立した生の(un-eased)線形進行度——README: 「フレーム切替はイージング
## 後の位置ではなく、イージング前のapproach_progressで決めます」。
func _eos_burst_approach_pose_progress(elapsed: float) -> float:
	if elapsed < EOS_BURST_APPROACH_START_SECONDS:
		return 0.0
	return clampf(
		(elapsed - EOS_BURST_APPROACH_START_SECONDS) / EOS_BURST_APPROACH_SECONDS, 0.0, 1.0)


## 「Unified Assault Rig + Audio v1」(2026-08-08) — README PART A §1
## 「approach中の独立AnimationPlayerをやめる」。旧来は竜(`_eos_burst_
## dragon_approach_frame`)とソティリス/オーラ(`_eos_burst_sotiris_aura_
## approach_frame`)がそれぞれ別々の区切り値を持っていた(前ラウンドまで
## の竜は0.20までに全5コマ完了、ソティリス/オーラは0.65までかけて完了)
## ——同じ連続progressを読んではいても区切りが揃っていないため、竜が
## 既にfull horizontal突進姿勢なのにソティリスはまだ前傾途中、という
## ポーズの組合せが崩れた瞬間が生じていた。今回はREADME §1のphase表
## (0.00-0.10/0.10-0.25/0.25-0.45/0.45-0.72/0.72-1.00の5段階、各資産とも
## ちょうど5枚の接近前コマを持つため1段階=1コマで自然に対応)をこの1つの
## 配列に集約し、竜・ソティリス・オーラの3つの旧個別関数は全てここへ
## 委譲する薄いラッパーへ縮小した——「3者が同じ拍で変化する」を、値を
## 揃えたコピーではなく単一の参照元を共有する形で構造的に保証する。
## 「Visual Regression Cleanup v1」(2026-08-10) — README Part Dが新しい
## breakpoint値[0.08,0.22,0.42,0.70,1.00]を指定。frame_idxの割当てそのもの
## (phase_idx==frame_idx、竜/ソティリス/オーラともapproach中は0-4を
## そのまま使う)は据え置き——README表は竜/オーラについて「frame 1から
## 開始」(1-indexed寄りの記法)と読める一方、実測(emergence最終フレーム
## とassault frame0のbbox比較、`EOS_BURST_DRAGON_ASSAULT_SCALE_
## CORRECTION`のdoc comment参照)でframe0こそがemergenceの最終ポーズと
## 一致することを確認済みのため、「意味が違えば番号を直してください」
## というREADME自身の許可に基づきphase0→frame0のまま維持する(README
## との齟齬を報告に明記)。breakpoint自体の値(タイミング)は実測と無関係
## な純粋なretimingのため、そのまま採用した。
const EOS_BURST_ASSAULT_PHASE_BREAKS: Array[float] = [0.08, 0.22, 0.42, 0.70, 1.0]


func _eos_burst_assault_phase_index(progress: float) -> int:
	for i in EOS_BURST_ASSAULT_PHASE_BREAKS.size():
		if progress < EOS_BURST_ASSAULT_PHASE_BREAKS[i]:
			return i
	return EOS_BURST_ASSAULT_PHASE_BREAKS.size() - 1


## 竜のフレーム割り当て——`_eos_burst_assault_phase_index`への薄い委譲
## (旧・竜専用の区切り値は撤去、上記コメント参照)。
func _eos_burst_dragon_approach_frame(progress: float) -> int:
	return _eos_burst_assault_phase_index(progress)


## ソティリス/オーラのフレーム割り当て——同じく`_eos_burst_assault_
## phase_index`への薄い委譲(旧・ソティリス/オーラ専用の区切り値は撤去)。
func _eos_burst_sotiris_aura_approach_frame(progress: float) -> int:
	return _eos_burst_assault_phase_index(progress)


## 接触(HIT_AT)以降の共有ロジック——旧`_eos_burst_assault_frame_index`
## から無改修のまま移設。旧来は接触直前を「2」(飛翔中)→「3」(接触保持)
## という別々のコマで表現していたが、新しい接近テーブルは既に48%/65%
## 時点で最終姿勢「4」に到達し、そのままHIT_ATまで保持されるため、
## 「4」を接触の瞬間も含めてそのまま保持するのが新設計と整合する(接触
## の瞬間にコマが後退して見える回帰を避ける、2026-08-06の設計判断として
## 開示)。解放後は`elapsed - HIT_AT`が0から再カウントを始める(elapsedは
## ヒットストップ中HIT_ATに凍結されるため)ので、着弾sprite自身の解放後
## タイムライン(EOS_BURST_IMPACT_POST_RELEASE_*)とそのまま揃えられる。
func _eos_burst_assault_post_contact_frame(elapsed: float) -> int:
	if elapsed < EOS_BURST_HIT_AT_SECONDS:
		return 4
	if not _eos_burst_assault_released():
		return 4
	var post := elapsed - EOS_BURST_HIT_AT_SECONDS
	if post < EOS_BURST_ASSAULT_FRAME4_HOLD_SECONDS:
		return 4
	return 5


## 竜(`eos_dragon_assault_6f.png`)専用のフレームインデックス。
func _eos_burst_dragon_assault_frame_index(elapsed: float) -> int:
	if elapsed < EOS_BURST_HIT_AT_SECONDS:
		return _eos_burst_dragon_approach_frame(_eos_burst_approach_pose_progress(elapsed))
	return _eos_burst_assault_post_contact_frame(elapsed)


## 「SizeDragonFix v6」(2026-08-12) — 旧`_eos_burst_swing_pose_progress`/
## `_eos_burst_dragon_display_frame_index`(竜の描画テクスチャ選択を
## `eos_dragon_assault_6f.png`の frame0-4 へマッピングしていた専用関数群)
## を削除した——竜の描画は新設`_draw_eos_burst_dragon`が manifest/idle/
## release の3段階を直接切り替えるだけになり、独立したframe-index選択
## ヘルパーが不要になったため。速度線が参照する共有の`_eos_burst_dragon_
## assault_frame_index`(タイミングのみのゲート、テクスチャ読み込みを
## 一切伴わない)は無改修のまま維持——「速度線を壊さない」不変条件を継続。


## ソティリス(`sotiris_eos_thrust_6f.png`)専用のフレームインデックス。
## approach中の区切りはAuraと共有する(`_eos_burst_sotiris_aura_approach_
## frame`)が、接触後は`_eos_burst_assault_post_contact_frame`(frame4保持
## →frame5=recovery)をそのまま経由する——ソティリス自身にとってframe5は
## 「戦技を終えて構えを解く」正当なrecoveryポーズであり、竜が経由を避けた
## のとは逆に、ここでは共有関数の遷移をそのまま使うのが正しい。
## 「Visual Regression Cleanup v1」(2026-08-10) — 旧関数名は「ソティリス・
## オーラ共有」だったが、Aura側はframe5が"縦炎"で意味が異なる(下記
## `_eos_burst_aura_display_frame_index`参照)ため分離した——この関数は
## ソティリス専用として残す。
func _eos_burst_sotiris_aura_assault_frame_index(elapsed: float) -> int:
	if elapsed < EOS_BURST_HIT_AT_SECONDS:
		return _eos_burst_sotiris_aura_approach_frame(_eos_burst_approach_pose_progress(elapsed))
	return _eos_burst_assault_post_contact_frame(elapsed)


## Aura(`eos_assault_aura_6f.png`)専用のフレームインデックス。approach中
## の区切りはソティリスと共有するが、接触後は共有の`_eos_burst_assault_
## post_contact_frame`(frame4→frame5)を経由せず、竜と同じパターンで
## frame4に固定し続ける——Aura自身のframe5は縦2本柱の炎(frame0/1と
## ほぼ同一の意匠)で、ソティリスのframe5(recoveryポーズ)とは全く別の
## 意味を持つため、共有関数をそのまま使うとcontact後に"縦炎"へ逆戻り
## してしまう(README Part Fが報告した「金色の縦オーラが着弾地点の後方に
## 残る」の直接原因)。実際にはAura自身のalpha(`_eos_burst_aura_alpha`)が
## 接触後ごく短時間でフェードアウトするため、この固定はその短い残り時間
## 用の保険でもある。
## 「SMALLER_REAR_DRAGON_ANCHORED_AURA_SMOOTH_SLASH v11」(2026-08-14) —
## 旧`_eos_burst_aura_display_frame_index`(assault_aura=`eos_assault_
## aura_6f.png`専用のフレーム選択、掲剣〜接触までの区間で使われていた)
## は、掲剣中のオーラ表示自体を`charge_aura_anchored`4コマへ全面差し替え
## たことで完全に不要になったため削除した。`EOS_BURST_ASSAULT_AURA_
## CONTACT_FRAME`(この関数だけが参照していた)も道連れに削除。
## 「振りかぶり中の溜めオーラがソティリスの左下へ外れている」の真因は
## この関数が経由していた`EOS_BURST_ASSAULT_AURA_FRAME_OFFSET`(6コマ分の
## per-frame補正テーブル、実測でframe3-5だけ最大35px横・34px縦もずれる)
## だった——補正済みの新4コマ(`charge_aura_anchored`)は全フレームで
## 可視中心が統一済みのため、per-frame補正テーブル自体が不要になった。


## 「Visual Regression Cleanup v1」(2026-08-10) — README Part C「6.983→
## 7.000秒相当でソティリスが通常のapproach増分より大きく前へ飛ぶ」。
## 実測(headlessトレース、tick=0.05秒刻み)で真因を特定: `EOS_BURST_
## THRUST_GROUND_ANCHOR_X_PX`によるfoot-anchor補正が、離散的な`eos_
## thrust_frame_idx`(=`_eos_burst_sotiris_aura_assault_frame_index`が
## tick基準elapsedから返す、コマ単位で切り替わる整数)からそのまま計算
## されていた——`EOS_BURST_ASSAULT_PHASE_BREAKS`の最初の区間(進行度
## 0〜0.08、実時間にして0.42*0.08=0.0336秒)が1tick(0.05秒)より短いため、
## frame0の表示区間をtickの粒度が実質1回しか捉えられず、次のtickでは
## 早くもframe1・frame2相当まで進んでしまう——結果、x_offsetが1tickの
## 間に+18.5px、次のtickでさらに+21.9px、次で+50.7px、+51.7pxと、
## 「通常のapproach増分」を大きく上回る跳躍を続けて起こしていた(headless
## 実測値、旧実装での再現)。
##
## 「どの絵(スプライトのコマ)を表示するか」はコマ単位でパッと切り替わって
## 構わない(スプライトなので当然、既存方針どおりtick基準の離散選択の
## まま無改修)が、この関数が返す量は"足の接地位置"というworld position
## であり、連続的に動くべき量——`EOS_BURST_THRUST_GROUND_ANCHOR_X_PX`の
## 隣接コマ間を、コマの切り替わりを跨いで滑らかに補間する。`_eos_burst_
## smooth_elapsed`(既存の連続elapsed、`_eos_burst_advance_offset_px`が
## world root自体の移動に使っているのと同じ時計)から求めたprogressを
## `EOS_BURST_ASSAULT_PHASE_BREAKS`の区間ごとにlerpし、各区間の終わり
## (=次のコマへ切り替わる瞬間)にちょうど次コマのanchor値へ到達するよう
## 設計——「離散フレームXの絵が実際に表示される瞬間には、位置補正も
## 既にフレームXの値に一致している」ため、コマ切り替えそのものによる
## 新しい位置ジャンプを一切生まない(値をキャプチャする特別な状態は
## 不要、毎回elapsedから計算し直す純関数のまま)。接触後(HIT_AT以降)は
## 離散のfreeze/recoveryのみのため補間せず、そのままのフレーム値を使う
## (Sotiris自身のrecoveryへの遷移という既存の正当な離散変化のため)。
## 「現行ソティリス維持版 v3」(2026-08-12) — README「フレーム0→1→2で
## 剣を頭上へ掲げる」「3コマ目を短く静止」「4→5→6で振り下ろす」(0-indexed
## で0→1→2/2ホールド/3→4→5)という絶対時刻ベースの新しいコマ送りへ
## 全面書き換え。旧・進行度ベース(`EOS_BURST_ASSAULT_PHASE_BREAKS`)の
## システムは今回の「接近」概念自体が撤去されたため使わない。
func _eos_burst_downslash_frame_index(elapsed: float) -> int:
	if elapsed < EOS_BURST_APPROACH_START_SECONDS:
		return 0
	if elapsed < EOS_BURST_APPROACH_END_SECONDS:
		var t := (elapsed - EOS_BURST_APPROACH_START_SECONDS) / EOS_BURST_APPROACH_SECONDS
		return clampi(int(t * 3.0), 0, 2)
	if elapsed < EOS_BURST_THRUST_LUNGE_START_SECONDS:
		return 2
	if elapsed < EOS_BURST_BEAM_START_SECONDS:
		var t2 := (elapsed - EOS_BURST_THRUST_LUNGE_START_SECONDS) / EOS_BURST_THRUST_LUNGE_SECONDS
		return 3 + clampi(int(t2 * 3.0), 0, 2)
	return 5


## 「足元が全フレームで跳ねない」——上の`_eos_burst_downslash_frame_index`
## と全く同じフェーズ境界を使うが、こちらは連続elapsed
## (`_eos_burst_smooth_elapsed`)で"どの2コマの間のどの位置か"を分数で
## 求め、隣接するground anchor値の間を線形補間する。「表示するコマ番号」
## (tick量子化されたまま、パッと切り替わってよい)と「足元の接地位置」
## (連続的なworld position量)を分離する、このスキルが過去に踏んだ
## テレポート系バグ(Visual Regression Cleanup v1 Part C参照)と同じ
## 再発防止パターン。
func _eos_burst_downslash_continuous_frame(elapsed: float) -> float:
	var smooth := _eos_burst_smooth_elapsed(elapsed)
	if elapsed < EOS_BURST_APPROACH_START_SECONDS:
		return 0.0
	if elapsed < EOS_BURST_APPROACH_END_SECONDS:
		var t := clampf(
			(smooth - EOS_BURST_APPROACH_START_SECONDS) / EOS_BURST_APPROACH_SECONDS, 0.0, 1.0)
		return clampf(t * 3.0, 0.0, 2.0)
	if elapsed < EOS_BURST_THRUST_LUNGE_START_SECONDS:
		return 2.0
	if elapsed < EOS_BURST_BEAM_START_SECONDS:
		var t2 := clampf(
			(smooth - EOS_BURST_THRUST_LUNGE_START_SECONDS) / EOS_BURST_THRUST_LUNGE_SECONDS, 0.0, 1.0)
		return 3.0 + clampf(t2 * 3.0, 0.0, 2.0)
	return 5.0


## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 「①一つ一つの
## 姿勢とVFXのつながりが滑らかでなく、長く止まった後に一枚で切り替わる
## ためカクついて見える」——旧discrete-jumpの単一フレーム選択(`_eos_
## burst_downslash12_frame_index`、唯一の呼び出し元だった`_draw_party_
## row`のicon計算)を、A/Bクロスフェード用の(idx_a, idx_b, alpha_a,
## alpha_b)ペアを返す関数へ全面差し替えた。RAISE_DURATIONS(6)は
## STRIKE_PREP_SECONDS=0(上記const参照、旧「フレーム5静止ホールド」を
## 撤廃)によりSWING_DURATIONS(6)へ継ぎ目なく直結するため、両者を単純
## 連結した`EOS_BURST_DOWNSLASH12_BLEND_DURATIONS`(12要素)1本を、
## `EOS_BURST_APPROACH_START_SECONDS`を起点(age=0)とした単一の走査
## ループで処理する——フレーム5→6の境界(旧・静止ホールドの直前直後)も
## 他の10境界と全く同じ扱いになり、「静止してから一枚で切り替わる」
## 段差が構造的に発生しなくなる。
func _eos_burst_downslash12_frame_pair(elapsed: float) -> Array:
	if elapsed < EOS_BURST_APPROACH_START_SECONDS:
		return [0, -1, 1.0, 0.0]
	return _eos_burst_downslash12_hold_blend(elapsed - EOS_BURST_APPROACH_START_SECONDS)


## 各フレームiは自分の持ち時間`durations[i]`の末尾`min(BLEND_MAX,
## durations[i]*0.65)`秒だけ、次のフレームへSmootherstepでブレンドする
## (それより前は完全不透明のまま保持)——参照実装`play_smooth_character_
## motion`の「hold, then blend the tail」構造そのもの。斬撃/着弾/爆発が
## 使う`_eos_burst_frame_crossfade_pair`(区間全体が遷移になる別の形)とは
## 意図的に別のヘルパーとして持つ。
func _eos_burst_downslash12_hold_blend(age: float) -> Array:
	var durations := EOS_BURST_DOWNSLASH12_BLEND_DURATIONS
	var n := durations.size()
	var cursor := 0.0
	for i in n:
		var d: float = durations[i]
		var seg_end := cursor + d
		if age < seg_end or i == n - 1:
			if i >= n - 1:
				return [i, -1, 1.0, 0.0]
			var blend: float = minf(
				EOS_BURST_DOWNSLASH12_BLEND_MAX_SECONDS, d * EOS_BURST_DOWNSLASH12_BLEND_RATIO)
			var blend_start := seg_end - blend
			if age < blend_start:
				return [i, -1, 1.0, 0.0]
			var t := clampf((age - blend_start) / blend, 0.0, 1.0)
			var mix := _eos_burst_ease_smootherstep(t)
			return [i, i + 1, 1.0 - mix, mix]
		cursor = seg_end
	return [n - 1, -1, 1.0, 0.0]


## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「③
## ソティリスの輪郭が白っぽく二重に見える」の対策。参照実装
## `godot/sprite_dither_v21.gdshader`が要求する「4x4 ordered dither、
## 相補的binary reveal(alpha0か255のみ、1描画あたり1ピクセルにつき
## current/nextどちらか一方だけ)」は、Godot 4のCanvasItem shaderが
## ノード単位の`material`プロパティにしか適用できず、単一の`_draw()`
## ディスパッチ(このファイル全体の既存アーキテクチャ)では「一部の
## テクスチャだけ別のshaderで描く」ことが構造的にできないため、参照
## 実装が要求する2枚のSprite2D(MotionA/MotionB)+ShaderMaterialを実
## ノードとして追加する案は不採用とした——このファイルは背景/敵/party_
## row/斬撃/着弾/爆発を全て単一の同期`_draw()`呼び出しの中で「呼び出し
## 順=描画順」として管理しており、Sotirisだけ実Sprite2Dノード化すると
## 常にシーンツリーの子として親の`_draw()`より後に描画されてしまい
## (z_indexで調整しても「一部だけ前・一部だけ後」を表現できない)、
## 斬撃/着弾/爆発がSotirisの手前に重なる既存の重なり順を壊すため
## (コピーした`sprite_dither_v21.gdshader`は資産として保存のみ、実行時
## には未使用——報告に開示)。
##
## 代わりに、同じ「相補的binary reveal」を**CPU側で1回だけ焼き込んだ
## 合成テクスチャ**として実現する——shaderのbayer4()と数式的に同じ
## 4x4順序ディザ閾値テーブルで、pose Aとpose Bの生RGBAバイトをピクセル
## 単位でどちらか一方だけコピーする(どちらの元画像も、シルエット外は
## 既にalpha=0のため「alpha0のtexelはdiscard」も自動的に満たす——別途
## しきい値判定は不要)。1枚のcomposite textureとして`draw_texture_rect`
## 1回で描くだけなので、①「一つのsource座標にはcurrentかnextのどちらか
## 一方だけ」を構造的に保証②self_modulate alphaは常に1.0(部分アルファの
## 重ね描きが一切存在しない)③z順は完全に既存のまま(単一のdraw呼び出し
## がparty_row内の他の描画と同じ順序ルールに従う)、の3点を同時に満たす。
##
## 遷移窓(最大0.067秒)の間、参照実装のprogress(0→1連続値)を"どちらの
## 閾値グループがどちら側に倒れるか"という17段階の整数revealed_countへ
## 量子化する(4x4=16個の閾値が1つ増えるたびに1グループがA→Bへ切り替わる
## ため、視覚的に意味のある離散状態は17個しかない——16段階に量子化しても
## 参照のリアルタイムshaderと視覚的に不可分)。各(pose_a, pose_b,
## revealed_count)の組み合わせは初回生成時にのみ計算し、以後はプロセス
## 存続期間中ずっとキャッシュする(`_eos_burst_dither_cache`)——遷移が
## 11箇所×最大17状態=最大187通りしか存在しないため、実際のプレイでは
## 数msのバーストが数回発生するだけで、2回目以降のキャストでは完全に
## キャッシュ済みになる。
const EOS_BURST_DITHER_BAYER: Array[int] = [
	0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5,
]
var _eos_burst_dither_cache: Dictionary = {}


func _eos_burst_dither_reveal_count(mix: float) -> int:
	return clampi(int(round(clampf(mix, 0.0, 1.0) * 16.0)), 0, 16)


## `idx_b < 0`(遷移窓の外)なら生のposeテクスチャをそのまま返す——新規
## 合成は一切発生しない。`revealed_count`が0/16の端点でも同様(数式上
## 完全にA/Bどちらか一方のみのため、生テクスチャと画素単位で同一)。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — pose key
## だけをEOS_BURST_DOWNSLASH16_POSE_KEY(16コマ)へ差し替え。この関数自体は
## 元からposeのフレーム数に依存しない汎用実装(revealed_countの量子化・
## キャッシュ機構とも12/16どちらでも同一に機能する)ため、他は無改修。
func _eos_burst_downslash12_dither_texture(idx_a: int, idx_b: int, mix: float) -> Texture2D:
	if idx_b < 0:
		return art.frame(EOS_BURST_DOWNSLASH16_POSE_KEY, idx_a)
	var revealed := _eos_burst_dither_reveal_count(mix)
	if revealed <= 0:
		return art.frame(EOS_BURST_DOWNSLASH16_POSE_KEY, idx_a)
	if revealed >= 16:
		return art.frame(EOS_BURST_DOWNSLASH16_POSE_KEY, idx_b)
	var cache_key := "%d_%d_%d" % [idx_a, idx_b, revealed]
	if _eos_burst_dither_cache.has(cache_key):
		return _eos_burst_dither_cache[cache_key]
	var tex_a := art.frame(EOS_BURST_DOWNSLASH16_POSE_KEY, idx_a)
	var tex_b := art.frame(EOS_BURST_DOWNSLASH16_POSE_KEY, idx_b)
	if tex_a == null or tex_b == null:
		return tex_a
	var img_a := tex_a.get_image()
	var img_b := tex_b.get_image()
	img_a.convert(Image.FORMAT_RGBA8)
	img_b.convert(Image.FORMAT_RGBA8)
	var w := img_a.get_width()
	var h := img_a.get_height()
	var bytes_a := img_a.get_data()
	var bytes_b := img_b.get_data()
	var out := PackedByteArray()
	out.resize(bytes_a.size())
	for y in h:
		var row_base := y * w * 4
		var bayer_row := (y % 4) * 4
		for x in w:
			var threshold: int = EOS_BURST_DITHER_BAYER[bayer_row + (x % 4)]
			var px := row_base + x * 4
			if threshold < revealed:
				out[px] = bytes_b[px]
				out[px + 1] = bytes_b[px + 1]
				out[px + 2] = bytes_b[px + 2]
				out[px + 3] = bytes_b[px + 3]
			else:
				out[px] = bytes_a[px]
				out[px + 1] = bytes_a[px + 1]
				out[px + 2] = bytes_a[px + 2]
				out[px + 3] = bytes_a[px + 3]
	var composite := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
	var result := ImageTexture.create_from_image(composite)
	_eos_burst_dither_cache[cache_key] = result
	return result


func _eos_burst_thrust_ground_anchor_offset_px(elapsed: float) -> float:
	var thrust_age := elapsed - EOS_BURST_APPROACH_START_SECONDS
	var window_end := EOS_BURST_EXIT_END_SECONDS - EOS_BURST_APPROACH_START_SECONDS
	if thrust_age < 0.0 or thrust_age >= window_end:
		return 0.0
	var cf := _eos_burst_downslash_continuous_frame(elapsed)
	var lo := clampi(int(floor(cf)), 0, EOS_BURST_DOWNSLASH_GROUND_ANCHOR_X_PX.size() - 1)
	var hi := clampi(lo + 1, 0, EOS_BURST_DOWNSLASH_GROUND_ANCHOR_X_PX.size() - 1)
	var frac := cf - float(lo)
	var anchor := lerpf(
		EOS_BURST_DOWNSLASH_GROUND_ANCHOR_X_PX[lo], EOS_BURST_DOWNSLASH_GROUND_ANCHOR_X_PX[hi], frac)
	return (EOS_BURST_DOWNSLASH_GROUND_ANCHOR_X_PX[0] - anchor) * EOS_BURST_DOWNSLASH_SPRITE_SCALE


## 「ソティリスの剣先が敵へ接触したframe3で...停止...停止解除と同時に」
## ——接触(HIT_AT)に到達しており、かつ現在ヒットストップが有効でない
## (=既に解除済み)ことを表す。ダメージ発火(`hit_now`)・竜/オーラの
## frame4進行・着弾spriteの解放後フェーズ・暗転解除、全てがこの1つの
## 判定を共有する("同じ瞬間に"を、複数箇所で別々に時刻を計算せず単一の
## 真偽値で保証する設計)。
func _eos_burst_assault_released() -> bool:
	return _eos_burst_logged.has("EOS assault contact hitstop") and _battle_hitstop_t <= 0.0


## 「オーラノードはソティリスに追従させます。ソティリスだけが前進して
## オーラが元の場所へ残らないようにしてください」——`_eos_burst_caster_
## feet`(接近/帰還offsetのみ)に、ソティリス自身の描画が使うのと全く同じ
## 追加オフセット(突きの物理lunge`_eos_burst_thrust_offset_px`、タメの
## 沈み込み`_eos_burst_windup_sink_px`、余韻反動の垂直たわみ`_eos_burst_
## recoil_dip_px`)を足し込む——`_draw_party_row`がソティリス自身の足元を
## 計算する式と完全に同じ式(4つの関数呼び出しをそのまま再利用、式の
## 複製ではなく関数の再利用)。
func _eos_burst_sotiris_live_feet(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var feet := _eos_burst_caster_feet(view, unit_id, elapsed)
	feet.x += _eos_burst_thrust_offset_px(elapsed)
	feet.y += _eos_burst_windup_sink_px(elapsed)
	feet.y += _eos_burst_recoil_dip_px(elapsed)
	return feet


## 「竜とソティリスの突きを作り直す」(2026-08-05、同日追加ラウンド) —
## ソティリス自身の水平方向オフセット。旧`_eos_burst_charge_pullback_
## offset_px`(STRIKE_PREP窓全体でsin波形に引いて戻すだけ=物理的な踏み
## 込みが存在しなかった)を全面置換し、②踏み込み前の溜め(引く)→③突き
## (Cubic Ease Outで前方へ踏み込み、剣を最大まで伸ばす)→④保持(光撃と
## 命中の間、伸びきった位置のまま)→⑤余韻反動(命中直後に少しだけ後ろへ
## 戻す)→復帰(RETURN開始=`_eos_burst_advance_offset_px`自身のRETURN
## ロジックと衝突しないよう、VANISH_START到達までにこの追加オフセット
## 自体を0へ滑らかに戻しておく)の4段階を持つ。
## 「現行ソティリス維持版 v3」(2026-08-12) — 「現行ソティリスの座標を
## 維持する」という最優先指示により、突き込みの物理オフセットは今回
## 完全に無効化した(常に0.0を返す)。振り下ろしは`_draw_party_row`側の
## `EOS_BURST_DOWNSLASH_POSE_KEY`アイコン差し替え(コマ送りだけで表現)
## が担うため、ルート位置自体を動かす必要が無い。
func _eos_burst_thrust_offset_px(_elapsed: float) -> float:
	return 0.0


func _eos_burst_thrust_offset_px_disabled(elapsed: float) -> float:
	# 「動きのカクつきを根本修正する」(2026-08-06) — 分岐(どの段階か)は
	# tick基準のelapsed自身で判定、各段階内の補間係数だけ連続elapsedを使う
	# ——`_eos_burst_advance_offset_px`と同じ設計。
	var smooth := _eos_burst_smooth_elapsed(elapsed)
	if elapsed < EOS_BURST_STRIKE_PREP_START_SECONDS:
		return 0.0
	if elapsed < EOS_BURST_THRUST_LUNGE_START_SECONDS:
		# ②踏み込み前の溜め: 0 -> -PULLBACK
		var t := (smooth - EOS_BURST_STRIKE_PREP_START_SECONDS) / EOS_BURST_STRIKE_PREP_SECONDS
		return -EOS_BURST_THRUST_PULLBACK_PX * smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	if elapsed < EOS_BURST_BEAM_START_SECONDS:
		# ③突き: -PULLBACK -> +LUNGE、Cubic Ease Out(最後だけ急停止)
		var t2 := (smooth - EOS_BURST_THRUST_LUNGE_START_SECONDS) / EOS_BURST_THRUST_LUNGE_SECONDS
		return lerpf(
			-EOS_BURST_THRUST_PULLBACK_PX, EOS_BURST_THRUST_LUNGE_PX,
			_eos_burst_ease_out_cubic(clampf(t2, 0.0, 1.0)))
	if elapsed < EOS_BURST_HIT_AT_SECONDS:
		# ④光撃と命中: 伸びきった位置のまま保持
		return EOS_BURST_THRUST_LUNGE_PX
	var recoil_end := EOS_BURST_HIT_AT_SECONDS + EOS_BURST_THRUST_RECOIL_SECONDS
	if elapsed < recoil_end:
		# ⑤余韻と反動: +LUNGE -> +LUNGE-RECOIL(4-6pxだけ後ろへ)
		var t3 := (smooth - EOS_BURST_HIT_AT_SECONDS) / EOS_BURST_THRUST_RECOIL_SECONDS
		return lerpf(
			EOS_BURST_THRUST_LUNGE_PX, EOS_BURST_THRUST_LUNGE_PX - EOS_BURST_THRUST_RECOIL_PX,
			smoothstep(0.0, 1.0, clampf(t3, 0.0, 1.0)))
	if elapsed < EOS_BURST_VANISH_START_SECONDS:
		# 復帰: 既存のRETURNロジック(_eos_burst_advance_offset_px)と二重に
		# ならないよう、この追加項自体はVANISH_START到達までに0へ収束させる
		# (ユーザー指定の範囲外だが、既存のRETURN機構と整合させるために必要)。
		var settle_start := recoil_end
		var settle_span := EOS_BURST_VANISH_START_SECONDS - settle_start
		var t4 := (smooth - settle_start) / maxf(0.0001, settle_span)
		return lerpf(
			EOS_BURST_THRUST_LUNGE_PX - EOS_BURST_THRUST_RECOIL_PX, 0.0,
			smoothstep(0.0, 1.0, clampf(t4, 0.0, 1.0)))
	return 0.0


## 「剣先を少し下げます」——余韻反動中だけの小さな垂直方向のたわみ
## (y_offset accumulatorへ加算、既存の`_eos_burst_windup_sink_px`と同じ
## 仕組みを反動フェーズ用に流用)。
func _eos_burst_recoil_dip_px(elapsed: float) -> float:
	var recoil_end := EOS_BURST_HIT_AT_SECONDS + EOS_BURST_THRUST_RECOIL_SECONDS
	if elapsed < EOS_BURST_HIT_AT_SECONDS or elapsed >= recoil_end:
		return 0.0
	var t := (_eos_burst_smooth_elapsed(elapsed) - EOS_BURST_HIT_AT_SECONDS) / EOS_BURST_THRUST_RECOIL_SECONDS
	return EOS_BURST_RECOIL_DIP_PX * sin(clampf(t, 0.0, 1.0) * PI)


## 「竜も8〜12pxだけ右へ勢いを乗せ...」という旧・竜専用LUNGE進行度
## (`_eos_burst_dragon_lunge_progress`/`_eos_burst_dragon_lunge_offset_px`)
## は、「6枚の異なる身体姿勢を使ってください」(2026-08-05、同日追加
## ラウンド)により、rectを動かす代わりにコマ切り替えで動きを表現する
## 方針へ全面移行したため撤去した(`_eos_burst_dragon_rect`はもう呼ばない、
## `git log`に経緯が残る)。


func _eos_burst_sword_tip_pos(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var feet := _eos_burst_caster_feet(view, unit_id, elapsed)
	return feet + EOS_BURST_SWORD_TIP_OFFSET


func _draw_eos_burst_sotiris_rim(icon: Texture2D, rect: Rect2, flip_h: bool) -> void:
	var elapsed := _battle_anim_phase_elapsed
	var flash_t := 0.0
	if elapsed >= EOS_BURST_BEAM_START_SECONDS \
			and elapsed < EOS_BURST_BEAM_START_SECONDS + EOS_BURST_RIM_FLASH_SECONDS:
		flash_t = 1.0 - (elapsed - EOS_BURST_BEAM_START_SECONDS) / EOS_BURST_RIM_FLASH_SECONDS
	var col := Color(0.1, 0.07, 0.03, 0.72).lerp(Color(1.0, 0.92, 0.65, 0.9), flash_t)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var off := Vector2(cos(a), sin(a)) * EOS_BURST_RIM_PX
		_draw_sprite(icon, Rect2(rect.position + off, rect.size), flip_h, col)


func _draw_eos_burst_attack_afterimages(
		view: Rect2, unit_id: int, icon: Texture2D, x: float, top: float, icon_px: int, flip_h: bool) -> void:
	var elapsed := _battle_anim_phase_elapsed
	if elapsed < EOS_BURST_BEAM_START_SECONDS or elapsed >= EOS_BURST_HIT_AT_SECONDS:
		return
	var cur_off := _eos_burst_advance_offset_px(view, unit_id, elapsed)
	for i in EOS_BURST_ATTACK_AFTERIMAGE_COUNT:
		var back_elapsed := elapsed - float(i + 1) * EOS_BURST_ATTACK_AFTERIMAGE_STEP_SECONDS
		if back_elapsed < EOS_BURST_BEAM_START_SECONDS:
			continue
		var back_off := _eos_burst_advance_offset_px(view, unit_id, back_elapsed)
		var ghost_x := x - (cur_off - back_off)
		var a := EOS_BURST_ATTACK_AFTERIMAGE_ALPHA \
			* (1.0 - float(i) / float(EOS_BURST_ATTACK_AFTERIMAGE_COUNT))
		_draw_sprite(
			icon, Rect2(Vector2(ghost_x - icon_px / 2.0, top), Vector2(icon_px, icon_px)),
			flip_h, Color(1.0, 1.0, 1.0, a))


## easeOutCubic — TRANS_CUBIC + EASE_OUT (1-(1-t)^3).
func _eos_burst_ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0.0, 1.0), 3.0)


## easeInQuad — TRANS_QUAD + EASE_IN (t^2). 「竜の接近モーション修正」
## (2026-08-06) — 位置移動だけをこの穏やかな加速カーブへ切り替えた
## (README: "位置移動は一定速ではなく、穏やかな加速になるTRANS_QUAD +
## EASE_IN相当を使ってください")。フレーム選択は別の生の進行度
## (`_eos_burst_approach_pose_progress`)を使うため、このイージングの
## 影響を受けない。
func _eos_burst_ease_in_quad(t: float) -> float:
	var c := clampf(t, 0.0, 1.0)
	return c * c


func _eos_burst_caster_feet(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var frac := _formation_pos(unit_id)
	return Vector2(
		view.position.x + view.size.x * frac.x + _eos_burst_advance_offset_px(view, unit_id, elapsed),
		view.position.y + view.size.y * frac.y)


func _eos_burst_texture(key: String) -> Texture2D:
	return _soul_break_load_texture("res://assets/vfx/sotiris/%s.png" % key)


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## 旧`_eos_burst_dragon_master_texture()`(既に唯一の呼び出し元だった旧
## `_draw_eos_burst_dragon`が削除済みのため死蔵)・その2つのキャッシュ
## 変数・`_eos_burst_emerge_sheet_texture()`(唯一の残存呼び出し元だった
## 旧`_draw_eos_burst_dragon_emerge_sheet`もこの後まとめて削除)・
## `EOS_BURST_EMERGE_SHEET_PATH`/`EOS_BURST_EMERGE_FRAME_COUNT`を全て
## 削除した(grep確認済み、呼び出し元ゼロ)。


## 「竜のCore+Glow二層化」(2026-08-05、同日追加ラウンド)により、竜本体の
## リム(高alpha輪郭)重ね描きは廃止された——ここにあった`_eos_burst_
## outline_texture()`(竜のCore/Glow用の輪郭専用テクスチャローダー)は
## 唯一の呼び出し元(`_draw_eos_burst_dragon_aura_layers`)ごと不要になった
## ため削除した。同じ資産(`eos_dragon_pixel_v2_outline_0.png`)自体は
## `_draw_eos_burst_mouth_converge_rim_flash`(発射直前0.12秒だけの別
## 演出、`_eos_burst_texture()`経由で独立にロード)で引き続き使用中
## のため、ファイルは削除していない。


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 旧`_eos_burst_aura_
## flicker`(唯一の呼び出し元だった`_draw_eos_burst_connecting_bands`が
## 竜の完全削除で既に消滅)を完全削除した。


## Local quad-strip drawer — used for glow rings/streams/rays/shards.
func _draw_eos_burst_quad(a: Vector2, b: Vector2, width: float, color: Color) -> void:
	var dir := b - a
	if dir.length() < 0.01:
		return
	var perp := Vector2(-dir.y, dir.x).normalized()
	draw_colored_polygon(PackedVector2Array([
		a + perp * width * 0.5, b + perp * width * 0.5,
		b - perp * width * 0.5, a - perp * width * 0.5,
	]), color)


## Translucent navy overlay drawn straight onto the existing chapter
## backdrop — the ONLY darkening the package permits.
func _draw_eos_burst_dim(view: Rect2) -> void:
	if not _eos_burst_vfx_active():
		return
	var elapsed := _battle_anim_phase_elapsed
	var a := EOS_BURST_DIM_ALPHA
	if elapsed < EOS_BURST_DIM_IN_SECONDS:
		a *= elapsed / EOS_BURST_DIM_IN_SECONDS
	elif elapsed >= EOS_BURST_RETURN_START_SECONDS:
		# 「Slower + New Impact v4」(2026-08-12) — README「4.18〜4.48秒:
		# 暗転・UI・入力を通常へ戻す」。旧実装は`_eos_burst_assault_
		# released()`(ヒットストップ解除、実時間で約HIT_AT+0.08秒)を
		# トリガーにしていたが、v4は縦の竜牙命中(〜3.20)・上昇する残光
		# (〜3.78)・振り抜きから通常待機(〜4.18)という着弾後の長い
		# シーケンスの間ずっと暗転を維持し、最後のRETURN窓でだけ解除する
		# よう明示指定されているため、UI dim(`_eos_burst_ui_dim_alpha`)と
		# 同じRETURN_START/RETURN_ENDへ揃えた。
		var t := (elapsed - EOS_BURST_RETURN_START_SECONDS) / EOS_BURST_RETURN_SECONDS
		a *= 1.0 - clampf(t, 0.0, 1.0)
	a += _eos_burst_charge_extra_dim(elapsed)
	if a <= 0.0:
		return
	draw_rect(view, Color(0.04, 0.06, 0.16, a))


## 「突進frame2〜4の間だけ、戦闘背景へ8〜12本程度の横長ドット速度線」
## (2026-08-05、同日追加ラウンド)——右から左へ、太さ2〜4px、金色/白/
## 少量シアン、整数座標、ぼかし・アンチエイリアス禁止(`_draw_eos_burst_
## quad`は`draw_colored_polygon`による塗りつぶしのみでantialiased引数を
## 使わないため元から非AA)。ソティリス・竜・敵より後ろ(呼び出し元の
## `_draw_boss_battle`で背景描画の直後・敵描画の前に配置)。各線は
## `_eos_burst_hash01`による決定論的な擬似乱数でY座標・長さ・太さ・色を
## 固定し(フレームごとに位置が飛ばない)、elapsedに応じたX方向の進行だけ
## を変化させる——毎フレーム新しい乱数を引く設計ではないため、この関数
## 自体はステートレス。
func _draw_eos_burst_speed_lines(view: Rect2, elapsed: float) -> void:
	var frame_idx := _eos_burst_dragon_assault_frame_index(elapsed)
	if frame_idx < 2 or frame_idx > 4:
		return
	for i in EOS_BURST_SPEED_LINE_COUNT:
		var stagger := float(i) / float(EOS_BURST_SPEED_LINE_COUNT)
		var length := lerpf(
			EOS_BURST_SPEED_LINE_MIN_LENGTH_PX, EOS_BURST_SPEED_LINE_MAX_LENGTH_PX,
			_eos_burst_hash01(i, 907))
		var phase := fmod(elapsed / EOS_BURST_SPEED_LINE_CYCLE_SECONDS + stagger, 1.0)
		var span := view.size.x + length
		var head_x := view.position.x + view.size.x - phase * span
		var y := view.position.y + _eos_burst_hash01(i, 701) * view.size.y
		var thickness := lerpf(
			EOS_BURST_SPEED_LINE_MIN_THICKNESS_PX, EOS_BURST_SPEED_LINE_MAX_THICKNESS_PX,
			_eos_burst_hash01(i, 313))
		var p0 := Vector2(roundf(head_x), roundf(y))
		var p1 := Vector2(roundf(head_x + length), roundf(y))
		var col_pick := _eos_burst_hash01(i, 555)
		var col: Color
		if col_pick < 0.45:
			col = Color(1.0, 0.85, 0.35, 0.6)  ## 金色
		elif col_pick < 0.85:
			col = Color(1.0, 1.0, 1.0, 0.5)  ## 白
		else:
			col = Color(0.55, 0.94, 1.0, 0.55)  ## 少量シアン
		_draw_eos_burst_quad(p0, p1, thickness, col)


## 「オーラのクオリティと着弾の迫力を修正」(2026-08-05) — タメ中の
## 手続き型「トゲトゲした金色の塊」(旧`_draw_eos_burst_windup_glow`、
## 剣先/身体中心への収束粒子+足元リング)は「完全に削除する」との明示
## 指示により全廃した。タメの視覚は新規6コマ手描き炎`_draw_eos_burst_
## charge_aura`(下記)に一本化され、ソティリス自身の姿勢の沈み込み
## (`_eos_burst_windup_sink_px`、body-only、削除対象ではない)だけが
## 残る。
const EOS_BURST_WINDUP_SINK_PX := 2.0
const EOS_BURST_WINDUP_SINK_RAMP_SECONDS := 0.06


## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — 旧ゲート
## `EOS_BURST_WINDUP_SECONDS`(1.25秒)は「character/aura開始=WINDUP_SECONDS」
## だった前提の名残——v20でAPPROACH_START_SECONDSがWINDUP_SECONDSから独立
## した短い値(0.08秒+接近前置き)へ切り離されたため、この沈み込みが
## WINDUP_SECONDSまで(=キャラクターが既に動き出した後も)残り続け、
## elapsed=WINDUP_SECONDSで斬撃build中に2pxが唐突に消えるポップになる
## ところだった。ゲートを`EOS_BURST_APPROACH_START_SECONDS`(=キャラクター
## が実際に動き出す瞬間)へ変更——「タメ中(まだ動いていない間)だけ沈む」
## という元の意図をそのまま保ちつつ、新しい短いタメ窓に自動的に追従する。
func _eos_burst_windup_sink_px(elapsed: float) -> float:
	if elapsed >= EOS_BURST_APPROACH_START_SECONDS:
		return 0.0
	var t := clampf(_eos_burst_smooth_elapsed(elapsed) / EOS_BURST_WINDUP_SINK_RAMP_SECONDS, 0.0, 1.0)
	return EOS_BURST_WINDUP_SINK_PX * smoothstep(0.0, 1.0, t)


## 「SMALLER_REAR_DRAGON_ANCHORED_AURA_SMOOTH_SLASH v11」(2026-08-14) —
## 「振りかぶり中の溜めオーラがソティリスの左下へ外れている。人物の
## 足元anchorへ固定する」。旧2段構成(タメ開始直後の4コマ成長+補助2枚→
## 掲剣〜接触まで表示され続ける6コマ`eos_assault_aura_6f.png`、後者が
## 実際にドリフトの原因だった)を全面撤去し、README指定の単純な単一
## ライフサイクルへ作り直した: ①[VISIBLE_START,APPROACH_END)=[2.20,3.05)
## 4コマを均等ループ②[APPROACH_END,VISIBLE_END)=[3.05,3.35) ループ終了
## 時点のフレームで静止したままalpha 1→0③[VISIBLE_END,...) 非表示、以後
## 振り下ろし中も含め一切再表示しない。位置は共通足元anchor(竜と同じ
## `_eos_burst_rear_anchor_pos`)+固定オフセット(-64,-205)——README
## 「128pxセルの水平中心X=64を人物足元X=0へ、素材の接地Y=205を人物足元
## Y=0へ合わせる」を、新素材(全4コマの可視中心が統一済み)に対しては
## per-frame補正なしの単純な`anchor + LOCAL_POSITION`だけで満たせる。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 旧discrete-jump
## 1回再生(`_eos_burst_frame_index_from_table`、単一テクスチャ描画)を
## A/Bクロスフェードへ全面書き直し。「00→01→02→03→02を0.180秒ずつA/Bで
## Smootherstep補間」——巡回列(`EOS_BURST_SOLAR_AURA_ORDER`)の連続する
## 2要素をこの関数内で直接補間する(汎用`_eos_burst_frame_crossfade_pair`
## は「配列インデックスがそのままフレーム番号」という前提のため、
## 00→01→02→03→02という非単調な巡回列には使えない——斬撃/着弾/爆発とは
## 別の専用ロジックとして書く)。位置は「全てのdraw frameでA/B双方へ同じ
## local positionを再設定」を、`_eos_burst_rear_anchor_pos`(elapsedの
## 純関数、キャッシュしない)から毎回ゼロ計算することで構造的に満たす。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「②
## オーラがソティリスの身体や地面に出ている。剣の刃だけにまとわせたい」。
## 新素材`frames/sword_blade_aura_v21/aura_00..03.png`(48×144、true
## transparency)は、12姿勢それぞれの「剣base→tip」座標(`SWORD_SEGMENTS_
## V21.tsv`、222×222セルのローカル座標)へ追従させる設計——参照実装
## `_update_sword_aura`のTransform2D連鎖(root.position=base、
## root.rotation=blade角度+PI/2、root.scale=blade長/126)を、実ノードでは
## なく`draw_set_transform`(このファイル既存の`_draw_sprite`のflip_h
## 実装・`_draw_boss_battle`のzoomと同じ、CanvasItemの一時変換を使う
## 確立済みイディオム)で再現する。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — README「素材path：
## 同梱内容をres://assets/vfx/eos_burst/v22/へコピーし、preloadを/v22/へ
## 切り替えてください。v21以前を削除・上書きしないでください」——画像
## content自体はv21からbyte-identical(パック自身のASSET_MANIFEST_V22.tsv/
## LOCKED_FINISH_SHA256_V22.tsvで確認済み)、パスだけ切替。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — 画像
## content自体はv22からbyte-identical(LOCKED_FINISH_SHA256_V25.tsvで
## 確認済み、剣オーラ4枚自体は今回の変更範囲に含まれない)、パスだけv25
## コピー先へ切替。
const EOS_BURST_SWORD_AURA_DIR := "res://assets/vfx/eos_burst/v25/frames/sword_blade_aura_v21/aura_"
const EOS_BURST_SWORD_AURA_FRAME_COUNT := 4
const EOS_BURST_SWORD_AURA_CELL_SIZE := Vector2(48.0, 144.0)
## README「pivot source (24,140)」——AuraA/Bのposition=-pivotとして描く
## (参照実装`SWORD_AURA_CHILD_OFFSET := Vector2(-24,-140)`と同じ)。
const EOS_BURST_SWORD_AURA_PIVOT := Vector2(24.0, 140.0)
const EOS_BURST_SWORD_AURA_SOURCE_LENGTH := 126.0
const EOS_BURST_SWORD_AURA_MAX_ALPHA := 0.86
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — README「剣オーラ：
## 画像とbase→tip追従はv21のまま。stage timesだけを[0.450,0.550,0.700,
## 1.190]へ変更。stage間blend：0.140秒。最後のfade：0.070秒(無改修)。
## 合計：2.960秒、releaseと同時に終了」——合計はcharacter release local
## (2.960秒、上記THRUST_LUNGE_SECONDS参照)と厳密一致。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — 参照実装
## `SWORD_AURA_STAGE_TIMES := [0.450,0.550,0.700,1.310]`——最後の要素だけ
## 1.190→1.310(+0.120)、他の3要素・BLEND/FADE_SECONDSは無改修。新しい合計
## (2.890+0.070=2.960→3.080)がcharacter release localの新しい値(3.080、
## 下記EOS_BURST_DOWNSLASH12_RELEASE_OFFSET_SECONDS参照)とちょうど一致する
## よう、最終stageの尺だけが+0.120された——この+0.120は新設4コマ挿入に
## 伴うreleaseの遅延量そのものと一致(character側・aura側それぞれ独立に
## 同じ値へ収束させた設計、二重管理ではなく意図した対称性)。
const EOS_BURST_SWORD_AURA_STAGE_TIMES: Array[float] = [0.450, 0.550, 0.700, 1.310]
const EOS_BURST_SWORD_AURA_BLEND_SECONDS := 0.140
const EOS_BURST_SWORD_AURA_FADE_SECONDS := 0.070
## `SWORD_SEGMENTS_V21.tsv`(base_x,base_y,tip_x,tip_y、222×222セルの
## ローカル座標、12姿勢分)——参照実装`SWORD_SEGMENTS: Array[Vector4]`と
## 同じ内容をVector2の対で保持する(GDScriptのVector4はコンストラクタ引数
## の可読性が低いため、base/tip2本のArray[Vector2]へ分けて持つ判断)。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) —
## `SWORD_SEGMENTS_V25.tsv`(16姿勢分)。旧index0-5は無改修のまま新
## index0-5へ、旧index6-11は無改修のまま新index10-15へスライド。新設
## frame6-9の4本(README「新規frame 6〜9の剣segment角度は、画面右を0度と
## して-71.7°→-35.9°→+24.4°→+45.6°。角度は一方向へ進み、水平停止は
## ありません」)だけが今回の実データ。
const EOS_BURST_SWORD_BASE: Array[Vector2] = [
	Vector2(106, 165), Vector2(106, 157), Vector2(108, 154), Vector2(110, 154),
	Vector2(110, 154), Vector2(111, 154),
	Vector2(105, 167), Vector2(97, 135), Vector2(105, 161), Vector2(116, 162),
	Vector2(118, 164), Vector2(119, 165),
	Vector2(119, 165), Vector2(120, 169), Vector2(120, 173), Vector2(119, 162),
]
const EOS_BURST_SWORD_TIP: Array[Vector2] = [
	Vector2(54, 191), Vector2(72, 120), Vector2(69, 103), Vector2(67, 78),
	Vector2(74, 64), Vector2(101, 58),
	Vector2(137, 70), Vector2(166, 85), Vector2(182, 196), Vector2(165, 212),
	Vector2(165, 208), Vector2(177, 205),
	Vector2(175, 204), Vector2(177, 206), Vector2(177, 210), Vector2(159, 191),
]


## 4段階(00→01→02→03)を各stage末尾0.100秒だけA/Bでsmootherstep補間し、
## 最後は0.070秒でfully-transparentへfadeする——参照実装`_sword_aura_
## state`と同じ構造。`{}`を返す=非表示(呼び出し側でclear)。
func _eos_burst_sword_aura_state(age: float) -> Dictionary:
	var cursor := 0.0
	for stage in EOS_BURST_SWORD_AURA_STAGE_TIMES.size():
		var interval: float = EOS_BURST_SWORD_AURA_STAGE_TIMES[stage]
		if age < cursor + interval:
			if stage < EOS_BURST_SWORD_AURA_FRAME_COUNT - 1:
				var blend_start := cursor + interval - EOS_BURST_SWORD_AURA_BLEND_SECONDS
				if age >= blend_start:
					var t := clampf((age - blend_start) / EOS_BURST_SWORD_AURA_BLEND_SECONDS, 0.0, 1.0)
					return {
						"from": stage, "to": stage + 1,
						"mix": _eos_burst_ease_smootherstep(t),
						"alpha": EOS_BURST_SWORD_AURA_MAX_ALPHA,
					}
			return {"from": stage, "to": stage, "mix": 0.0, "alpha": EOS_BURST_SWORD_AURA_MAX_ALPHA}
		cursor += interval
	if age < cursor + EOS_BURST_SWORD_AURA_FADE_SECONDS:
		var fade := 1.0 - _eos_burst_ease_smootherstep(
			(age - cursor) / EOS_BURST_SWORD_AURA_FADE_SECONDS)
		return {"from": 3, "to": 3, "mix": 0.0, "alpha": EOS_BURST_SWORD_AURA_MAX_ALPHA * fade}
	return {}


## 剣の現在位置(base→tip)を、キャラクター本体の描画と全く同じ
## local-cell→screen変換(`_draw_party_row`のsprite_box_px/x/top/flip_h
## 計算式をそのまま複製、式の共有ではなく同一定数(`_ally_battle_icon_px`
## /`EOS_BURST_DOWNSLASH12_SPRITE_SCALE`)・同一のfeet取得関数(`_eos_
## burst_sotiris_live_feet`、突き/沈み込み/反動オフセットを含む本体描画と
## 完全に同じ値)を使うことで、本体と剣の追従がズレる経路自体をなくす)で
## スクリーン座標へ写す。
func _eos_burst_sword_aura_screen_points(
		view: Rect2, unit_id: int, elapsed: float, base_local: Vector2, tip_local: Vector2
) -> Dictionary:
	var icon_px := _ally_battle_icon_px()
	var sprite_box_px := icon_px * EOS_BURST_DOWNSLASH12_SPRITE_SCALE
	var feet := _eos_burst_sotiris_live_feet(view, unit_id, elapsed)
	var x := feet.x
	var top := maxf(view.position.y, feet.y - sprite_box_px)
	var scale_factor := sprite_box_px / 222.0
	var flip_h := _battle_anim_flip
	var base_screen := Vector2(
		x - sprite_box_px / 2.0 + base_local.x * scale_factor, top + base_local.y * scale_factor)
	var tip_screen := Vector2(
		x - sprite_box_px / 2.0 + tip_local.x * scale_factor, top + tip_local.y * scale_factor)
	if flip_h:
		base_screen.x = 2.0 * x - base_screen.x
		tip_screen.x = 2.0 * x - tip_screen.x
	return {"base": base_screen, "tip": tip_screen, "scale_factor": scale_factor}


func _eos_burst_sword_aura_texture(frame_index: int) -> Texture2D:
	return _eos_burst_indexed_frame_texture(EOS_BURST_SWORD_AURA_DIR, frame_index)


## 剣base→tipへ追従させたAuraA/Bを、`draw_set_transform`による一時的な
## CanvasItem変換(root position=base、rotation=blade角度+PI/2、
## scale=blade長/126、参照実装のTransform2D連鎖と数式的に同一)で描く。
## 発光VFX共通のgamma0.70クロスフェード(`_eos_burst_luminous_weights`)を
## 使う——README「発光VFXのA/B weightは...Aura、Main、Impact、Outerだけ」。
func _draw_eos_burst_sword_aura(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < EOS_BURST_APPROACH_START_SECONDS:
		return
	var age := _eos_burst_smooth_elapsed(elapsed) - EOS_BURST_APPROACH_START_SECONDS
	var state := _eos_burst_sword_aura_state(age)
	if state.is_empty():
		return
	var pair := _eos_burst_downslash12_frame_pair(elapsed)
	var idx_a: int = pair[0]
	var idx_b: int = pair[1]
	var frame_mix: float = pair[3]
	var effective_b := idx_b if idx_b >= 0 else idx_a
	var base_local: Vector2 = EOS_BURST_SWORD_BASE[idx_a].lerp(
		EOS_BURST_SWORD_BASE[effective_b], frame_mix)
	var tip_local: Vector2 = EOS_BURST_SWORD_TIP[idx_a].lerp(
		EOS_BURST_SWORD_TIP[effective_b], frame_mix)
	var points := _eos_burst_sword_aura_screen_points(view, unit_id, elapsed, base_local, tip_local)
	var base_screen: Vector2 = points["base"]
	var tip_screen: Vector2 = points["tip"]
	var blade_vector := tip_screen - base_screen
	var blade_length := blade_vector.length()
	if blade_length < 0.001:
		return
	var root_rotation := blade_vector.angle() + PI * 0.5
	var root_scale := blade_length / EOS_BURST_SWORD_AURA_SOURCE_LENGTH
	var from_index: int = state["from"]
	var to_index: int = state["to"]
	var mix: float = state["mix"]
	var alpha: float = state["alpha"]
	var draw_rect := Rect2(-EOS_BURST_SWORD_AURA_PIVOT, EOS_BURST_SWORD_AURA_CELL_SIZE)
	draw_set_transform(base_screen, root_rotation, Vector2(root_scale, root_scale))
	if from_index == to_index:
		var tex := _eos_burst_sword_aura_texture(from_index)
		if tex != null:
			draw_texture_rect(tex, draw_rect, false, Color(1, 1, 1, alpha))
	else:
		var weights := _eos_burst_luminous_weights(mix)
		var tex_a := _eos_burst_sword_aura_texture(from_index)
		var tex_b := _eos_burst_sword_aura_texture(to_index)
		if tex_a != null:
			draw_texture_rect(tex_a, draw_rect, false, Color(1, 1, 1, alpha * weights.x))
		if tex_b != null:
			draw_texture_rect(tex_b, draw_rect, false, Color(1, 1, 1, alpha * weights.y))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_eos_burst_charge_aura(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < EOS_BURST_SOLAR_AURA_VISIBLE_START_SECONDS \
			or elapsed >= EOS_BURST_SOLAR_AURA_VISIBLE_END_SECONDS:
		return
	var age := elapsed - EOS_BURST_SOLAR_AURA_VISIBLE_START_SECONDS
	var idx_a: int
	var idx_b := -1
	var alpha_a: float
	var alpha_b := 0.0
	if age < EOS_BURST_SOLAR_AURA_CROSSFADE_SECONDS:
		var order := EOS_BURST_SOLAR_AURA_ORDER
		var seg := clampi(
			int(age / EOS_BURST_SOLAR_AURA_TRANSITION_SECONDS), 0, order.size() - 2)
		var seg_start := float(seg) * EOS_BURST_SOLAR_AURA_TRANSITION_SECONDS
		var t := clampf((age - seg_start) / EOS_BURST_SOLAR_AURA_TRANSITION_SECONDS, 0.0, 1.0)
		var mix := _eos_burst_ease_smootherstep(t)
		var weights := _eos_burst_luminous_weights(mix)
		idx_a = order[seg]
		idx_b = order[seg + 1]
		alpha_a = EOS_BURST_SOLAR_AURA_MAX_ALPHA * weights.x
		alpha_b = EOS_BURST_SOLAR_AURA_MAX_ALPHA * weights.y
	else:
		# フェード窓——巡回完了(frame2)から直接フェードへ入る(参照実装
		# `play_smooth_locked_aura`のフェード段と同じ、同じ足元位置のまま
		# Smootherstepでalphaを0へ落とす)。
		idx_a = EOS_BURST_SOLAR_AURA_FADE_FRAME_INDEX
		var fade_t := clampf(
			(age - EOS_BURST_SOLAR_AURA_CROSSFADE_SECONDS) / EOS_BURST_SOLAR_AURA_FADE_SECONDS,
			0.0, 1.0)
		alpha_a = EOS_BURST_SOLAR_AURA_MAX_ALPHA * (1.0 - _eos_burst_ease_smootherstep(fade_t))
	var anchor := _eos_burst_rear_anchor_pos(view, unit_id, elapsed)
	var top_left := (anchor + EOS_BURST_SOLAR_AURA_LOCAL_POSITION).round()
	var rect := Rect2(top_left, EOS_BURST_SOLAR_AURA_FRAME_SIZE)
	if alpha_a > 0.001:
		var tex_a := _eos_burst_indexed_frame_texture(EOS_BURST_SOLAR_AURA_DIR, idx_a)
		if tex_a != null:
			draw_texture_rect(tex_a, rect, false, Color(1.0, 1.0, 1.0, alpha_a))
	if idx_b >= 0 and alpha_b > 0.001:
		var tex_b := _eos_burst_indexed_frame_texture(EOS_BURST_SOLAR_AURA_DIR, idx_b)
		if tex_b != null:
			draw_texture_rect(tex_b, rect, false, Color(1.0, 1.0, 1.0, alpha_b))


## 「オーラを『ソティリスの体から湧き出る』見え方へ強化する」(2026-08-06、
## "Smooth motion + body-emitted aura + roar v3") — 既存の外側オーラ画像を
## 拡大するのは禁止(「巨大な単一オーラ」再発防止)なので、その内側(描画順
## では直後、レイヤー的にはSotirisにより近い)に、体表(足元→背中/胴→肩)
## から次々噴き出す小さな金色ドット/炎片の層を追加した。ノード(Particle2D
## 等)は一切使わず、この巨大ファイル全体の確立済みイディオム(speed_lines/
## breath ribbonと同じ「固定個数のスロットをハッシュ関数で決定論的に配置し
## elapsedの純粋関数として毎フレーム再計算するだけ、ランタイムの配列変更・
## resource生成なし」)をそのまま踏襲——「毎フレームparticle nodeを生成・
## 破棄しない」というREADME要求を、そもそもノード自体が存在しない設計で
## 満たす。全32スロット(EOS_BURST_BODY_AURA_COUNT、README「ピーク28〜36
## 個程度」の範囲内)は固定のfor-loop、`_eos_burst_hash01(i,salt)`が各
## スロットの体上の位置(region_t、0=足元/1=肩)・左右位置・背面バイアス・
## 粒サイズ(2x2/3x3)・色(暗いオレンジ金/強い金/少数の白熱コア)を決定論的
## に固定する——毎フレーム違う乱数を引かないので明滅しない。
const EOS_BURST_BODY_AURA_COUNT := 32
const EOS_BURST_BODY_AURA_BODY_WIDTH_PX := 46.0
const EOS_BURST_BODY_AURA_BACK_BIAS_PX := 7.0
## 判断値——1粒が湧き出て消えるまでの周期。短すぎるとチカチカ、長すぎると
## 湧き出て見えないバランスとして選定。
const EOS_BURST_BODY_AURA_CYCLE_SECONDS := 0.6
const EOS_BURST_BODY_AURA_RISE_PX := 10.0
## 「竜が現れても消さず70〜80%を維持」——中央値。
const EOS_BURST_BODY_AURA_DRAGON_HOLD_MULT := 0.75
## 判断値——0.42秒の突進中、粒子が左後方へどれだけ流れて見えるか。
const EOS_BURST_BODY_AURA_DASH_DRIFT_PX := 22.0
## 「着弾後0.25〜0.35秒かけて薄く」——中央値。ダメージ/hitstop/画面揺れ等
## 保護対象の着弾タイミング自体には一切触れない、このオーラ専用の独立した
## フェード秒数(竜自身のEOS_BURST_DRAGON_ASSAULT_FADE_SECONDS等、保護対象の
## 定数とは意図的に共有しない)。
const EOS_BURST_BODY_AURA_FADE_SECONDS := 0.30


## タメ全体(0→WINDUP_SECONDS)を通じた0〜1の強度——0-30%は薄く・30-70%で
## 増加・70-100%で最大に近づく、という3段階のブレークポイントではなく
## `elapsed/WINDUP_SECONDS`を直接使う単一の連続ランプにした(région_gate
## 側の閾値スイープと組み合わさることで、結果的に「足元→背中→肩」の
## 段階的な解放と「全体的に薄い→濃い」の両方が同時に、かつ滑らかに
## 表現される——今回のタスク1「カクつき除去」の精神とも一致するため、
## あえて3段階の離散ジャンプにしなかった判断)。竜出現後はDRAGON_HOLD_MULT
## で一定、着弾後はそこからフェード。
func _eos_burst_body_aura_overall_mult(elapsed: float) -> float:
	if elapsed < EOS_BURST_WINDUP_SECONDS:
		return clampf(elapsed / EOS_BURST_WINDUP_SECONDS, 0.0, 1.0)
	if elapsed < EOS_BURST_HIT_AT_SECONDS:
		return EOS_BURST_BODY_AURA_DRAGON_HOLD_MULT
	var age := _eos_burst_smooth_elapsed(elapsed) - EOS_BURST_HIT_AT_SECONDS
	if age >= EOS_BURST_BODY_AURA_FADE_SECONDS:
		return 0.0
	return EOS_BURST_BODY_AURA_DRAGON_HOLD_MULT \
		* (1.0 - smoothstep(0.0, 1.0, age / EOS_BURST_BODY_AURA_FADE_SECONDS))


## 32スロットを全て評価し、体表から湧き出る硬いエッジの金色ドット/炎片を
## `draw_rect`で描く(ぼかし・グラデーションテクスチャなし、Nearestのまま)。
## 楕円/輪/檻/バブル/魔法陣/巨大な一枚オーラ/シアンは一切使わない——単純な
## 正方形ピクセルの集合のみ。必ず`_eos_burst_sotiris_live_feet`(タスク1で
## 滑らかにした同じroot追従アンカー)を毎フレーム参照するため、固定ポーズ
## ではなくSotiris自身のtransformに追従する。
func _draw_eos_burst_body_core_aura(view: Rect2, unit_id: int, elapsed: float) -> void:
	var overall_mult := _eos_burst_body_aura_overall_mult(elapsed)
	if overall_mult <= 0.001:
		return
	var charge_p := clampf(elapsed / EOS_BURST_WINDUP_SECONDS, 0.0, 1.0)
	var feet := _eos_burst_sotiris_live_feet(view, unit_id, elapsed)
	var body_h := _ally_battle_icon_px()
	var smooth := _eos_burst_smooth_elapsed(elapsed)
	# 「横突進中は左後方へ流す」——0.42秒のAPPROACH窓の間だけsmoothstepで
	# ランプイン、その後は保持(命中まで彼は敵の前で静止するが、噴き出す
	# エネルギー自体は"後方へ流れ続けている"という設定的な継続を優先)。
	var dash_drift := 0.0
	if elapsed >= EOS_BURST_APPROACH_START_SECONDS and elapsed < EOS_BURST_APPROACH_END_SECONDS:
		var dt := clampf(
			(smooth - EOS_BURST_APPROACH_START_SECONDS) / EOS_BURST_APPROACH_SECONDS, 0.0, 1.0)
		dash_drift = -EOS_BURST_BODY_AURA_DASH_DRIFT_PX * smoothstep(0.0, 1.0, dt)
	elif elapsed >= EOS_BURST_APPROACH_END_SECONDS and elapsed < EOS_BURST_HIT_AT_SECONDS:
		dash_drift = -EOS_BURST_BODY_AURA_DASH_DRIFT_PX
	for i in EOS_BURST_BODY_AURA_COUNT:
		var region_t := _eos_burst_hash01(i, 211)  ## 0=足元, 1=肩
		# 「足元→背中→肩」の段階的解放をcharge_pに対する滑らかな閾値
		# スイープで表現(0.30秒相当の遷移幅)——ポップインしない。
		var region_gate := clampf((charge_p - region_t + 0.15) / 0.30, 0.0, 1.0)
		if region_gate <= 0.001:
			continue
		var cycle_offset := _eos_burst_hash01(i, 433)
		var cycle_t := fmod(elapsed / EOS_BURST_BODY_AURA_CYCLE_SECONDS + cycle_offset, 1.0)
		var life_alpha := sin(cycle_t * PI)  ## 0→1→0、湧いて消える1周期
		var side_t := _eos_burst_hash01(i, 619)
		var back_weight := _eos_burst_hash01(i, 337)
		var base_y := lerpf(feet.y, feet.y - body_h * 0.92, region_t)
		var base_x := feet.x + lerpf(
			-EOS_BURST_BODY_AURA_BODY_WIDTH_PX * 0.5, EOS_BURST_BODY_AURA_BODY_WIDTH_PX * 0.5, side_t)
		# 「一部の粒子を体の背面/左端へ寄せる」——全員ではなく重み付き。
		base_x -= EOS_BURST_BODY_AURA_BACK_BIAS_PX * back_weight
		base_x += dash_drift
		var rise := EOS_BURST_BODY_AURA_RISE_PX * cycle_t
		var alpha := life_alpha * region_gate * overall_mult
		if alpha <= 0.02:
			continue
		var size_pick := _eos_burst_hash01(i, 809)
		var mote_size := 2.0 if size_pick < 0.55 else 3.0
		var color_pick := _eos_burst_hash01(i, 971)
		var col: Color
		if color_pick < 0.12:
			col = Color(1.0, 0.97, 0.78)  ## 少数の白熱コア
		elif color_pick < 0.55:
			col = Color(1.0, 0.75, 0.18)  ## 強い金(本体)
		else:
			col = Color(0.82, 0.42, 0.08)  ## 暗いオレンジ金(外側)
		col.a = alpha
		var px := roundf(base_x)
		var py := roundf(base_y - rise)
		draw_rect(Rect2(px, py, mote_size, mote_size), col, true)


## タメ開始(PULLBACK終了=CHARGE開始)からオーラが立ち上がり竜の余韻
## フェードまで一緒にフェードする**元の**強度カーブ——このラウンドでは
## オーラ本体の描画からは切り離したが、接続する光の帯・竜内部のエネルギー
## 循環(前ラウンドで新設、今回はスコープ外)は引き続きこの関数をvanish時の
## フェード共有に使っているため無改修のまま維持する。
func _eos_burst_sotiris_aura_intensity(elapsed: float) -> float:
	if elapsed >= EOS_BURST_VANISH_START_SECONDS:
		# 竜と同じ0.3秒フェード窓をそのまま流用(_eos_burst_dragon_fade_alpha
		# と同じ式、竜とオーラを"一緒に"フェードさせる要求を直接満たす)。
		var age := elapsed - EOS_BURST_VANISH_START_SECONDS
		if age >= EOS_BURST_VANISH_FADE_SECONDS:
			return 0.0
		return 1.0 - smoothstep(0.0, 1.0, age / EOS_BURST_VANISH_FADE_SECONDS)
	var charge_start := EOS_BURST_SUMMON_PULLBACK_SECONDS
	if elapsed < charge_start:
		return 0.0
	var charge_end := EOS_BURST_SUMMON_PULLBACK_SECONDS + EOS_BURST_SUMMON_CHARGE_SECONDS
	if elapsed < charge_end:
		return smoothstep(0.0, 1.0, (elapsed - charge_start) / maxf(0.0001, EOS_BURST_SUMMON_CHARGE_SECONDS))
	return 1.0


## ソティリスの"肩"点の生きた(接近offset込み)スクリーン座標——竜の
## `_eos_burst_dragon_rect`が使う起点(`_eos_burst_emergence_origin`+
## 生の水平advance offset)と全く同じ式にすることで、両者が接近中も
## 完全に同期して動く(数式が同じであれば、独立に計算しても常に一致する)。
## 「肩」の生きたスクリーン座標——ソティリス本人の身体上の点(足元から
## icon_pxの55%上、`_draw_eos_burst_windup_glow`の`body_center`と同じ
## 定義)を使う。**注意**: `_eos_burst_emergence_origin`(BackShoulder=
## 竜のANCHOR_PXがちょうど一致するよう設計された抽象アンカー点)は、
## headlessトレースで実測した結果ここでは使わない——竜のANCHOR_PXは
## 定義上この点と常にほぼ完全一致する(差はサブピクセルの丸め誤差のみ)
## ため、両方をそのまま繋ぐと帯の長さが実質ゼロになり見えなくなる
## ("空白ができたら失敗"の逆に、"帯が短すぎて見えない"別の失敗を招く
## ところだった)。本人の身体上の実在する点を使うことで、実際に長さの
## ある帯として描画できる。
func _eos_burst_shoulder_pos(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var feet := _eos_burst_caster_feet(view, unit_id, elapsed)
	var icon_px := _ally_battle_icon_px()
	return feet - Vector2(0.0, icon_px * 0.55)


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## 旧`_eos_burst_dragon_root_pos`・`_draw_eos_burst_connecting_bands`
## (+`EOS_BURST_CONNECT_BAND_*`)・`_draw_eos_burst_internal_energy_flow`
## (+`EOS_BURST_ENERGY_FLOW_*`)・`_eos_burst_dragon_anchor_feet`を全て
## 完全削除した(いずれも竜専用、grep確認済みで呼び出し元ゼロ)。0.25〜
## 1.25秒の窓は空白にせず、新しい弱い足元オーラ脈動(後述、`_draw_eos_
## burst_dragon_prelight`の直後で発火)へ差し替える。


## 「SizeDragonFix v6」(2026-08-12) — README「manifestフレーム11、idle
## フレーム0・7、releaseフレーム0は同じ竜、同じ102×170の可視領域、同じ
## ローカル座標(78,28)で作成済みです...竜のscaleは3素材すべて同じ
## Vector2.ONEです。必殺技中のscale Tweenは禁止です」。旧・竜専用の頭部
## 追跡(`EOS_BURST_DRAGON_HEAD_ANCHOR_PX`ほか)とassault専用scale補正
## (`EOS_BURST_DRAGON_ASSAULT_SCALE_CORRECTION`)は、いずれも旧
## `eos_dragon_assault_6f.png`固有の登録ズレ(コマごとに頭の位置・
## コンテンツscaleが違う)を手続き的に補うための仕組みだった——新素材は
## PowerShellで4点(manifest[11]/idle[0]/idle[7]/release[0]の222×222
## クロップ)を`Bitmaps-Equal`で直接比較し、いずれも真(ピクセル差分0)で
## あることを確認済みのため、この種の補正は一切不要になった。rectは
## `elapsed`に依存する項が`_eos_burst_dragon_advance_offset_px`(接近/
## 帰還、詳細はそちらのdoc comment参照)しか残らない——つまり
## manifest/idle/releaseの3段階を通じて、position・scale・rotationは
## 完全に不変(接近/帰還区間の外では文字通り1ピクセルも動かない)。
## 「DragonとAuraはソティリスと同じ専用の足元Node2Dを親にする。画面座標
## へ直接置かない」——実ノード階層を持たないこのファイルの単一`_draw()`
## ディスパッチでは、"共有の親Node2D"を「Dragon/Auraの両方が同じ関数を
## 同じelapsedで呼ぶ」ことで模倣する(このsaga で竜/オーラ/爆発の各ラウンド
## で繰り返し確立済みのパターン——2つの独立した計算ではなく単一の共有
## 呼び出しにすることで、数値が食い違う経路自体を無くす)。中身は
## Sotiris自身の実際の描画位置(`_draw_party_row`の`x_offset`と同じ
## `_eos_burst_advance_offset_px`込み)そのもの——「人物が移動する場合は
## 共通の足元親だけを動かす」を、Sotiris自身が動く式をそのまま再利用する
## ことで満たす(将来approach offsetが0以外に戻っても正しく追従する)。
func _eos_burst_rear_anchor_pos(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var feet := _eos_burst_sotiris_live_feet(view, unit_id, elapsed)
	feet.x += _eos_burst_advance_offset_px(view, unit_id, elapsed)
	return feet


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## 旧`_eos_burst_dragon_rect`(竜のtransform)・`_eos_burst_dragon_mouth_pos`
## (既に呼び出し元ゼロだった死蔵、口位置解決)を完全削除した。`_eos_burst_
## rear_anchor_pos`(直前の関数、Sotiris自身の生きた足元)は今もオーラが
## 参照するため無改修のまま維持。


func _eos_burst_ellipse_points(center: Vector2, rx: float, ry: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## The shared attack target — both the breath and the impact stages read
## this one function, so they can never disagree about where the attack
## actually lands.
func _eos_burst_impact_point(view: Rect2) -> Vector2:
	var target := _boss_icon_rect(view)
	return target.position + target.size * 0.5


## Deterministic pseudo-random in [0,1] from an integer index + salt —
## used by the breath ribbon's own per-stamp jitter (irregular, flame-like
## edge, never a perfectly smooth strip).
func _eos_burst_hash01(i: int, salt: int) -> float:
	var n := sin(float(i) * 12.9898 + float(salt) * 78.233) * 43758.5453
	return n - floor(n)


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 旧`_eos_burst_form_
## overall_progress`(唯一の呼び出し元だった`_draw_eos_burst_ground_glow`が
## 竜の完全削除で消滅)を完全削除した。


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## `_draw_eos_burst_wipe_footlight`(+`EOS_BURST_WIPE_FOOTLIGHT_MOTE_COUNT`)・
## `_eos_burst_dragon_brightness`(+`EOS_BURST_DRAGON_FLIGHT_DIM_BRIGHTNESS`/
## `_COMPLETION_FLASH_SECONDS`/`_PEAK`)・`_eos_burst_manifest_frame_texture`/
## `_eos_burst_idle_frame_texture`/`_eos_burst_idle_frame_index`・
## `_eos_burst_dragon_fade_mult`・`_draw_eos_burst_dragon`・`_draw_eos_burst_
## dragon_aura_layers`・既に呼び出し元ゼロだった死蔵の`_eos_burst_emerge_
## sheet_texture`/`_eos_burst_emerge_frame_texture`/`_eos_burst_emerge_
## frame_index`/`_eos_burst_emerge_age`/`_draw_eos_burst_dragon_emerge_
## sheet`(+`EOS_BURST_EMERGE_SHEET_PATH`/`_FRAME_COUNT`/`_FRAME_DURATIONS`、
## いずれも冒頭で既に削除済み)を、まとめて完全削除した(全てgrep確認済み、
## 呼び出し元ゼロ)。下記`_eos_burst_head_reveal_start_seconds`/`_eos_burst_
## mouth_orb_diameter_px`/`EOS_BURST_MOUTH_*`(剣先の光球収束、竜とは無関係)
## は`_draw_eos_burst_mouth_charge`(ソティリスの剣先演出、保護対象)が
## 引き続き参照するため無改修のまま維持。


## §3: 「攻撃起点を口へ接続」(2026-08-05、竜召喚モーションの最終構造修正)
## ——竜→ソティリス→剣先→敵という力の流れ(旧`_draw_eos_burst_dragon_to_
## sword_handoff`)を廃止し、飛翔体は必ず竜の口(`_eos_burst_dragon_mouth_
## pos`、MouthSocket相当——実ノードではなく既存の"口の中心を返す関数"を
## そのまま流用、値としては同じ)から発射する設計に統一した。口元の光は
## 単一の連続したカーブで2段階に育つ: ①頭部が実体化し始める瞬間
## ("0.34-0.46秒: ...口元へ光を集め始める")から、0px→MID_PXへ緩やかに
## 立ち上がる下地②発射直前(§2「竜召喚モーションの追加修正」で0.12→
## 0.14-0.18秒=mid0.16秒へ再調整)でMID_PX→PEAK_PXへ最終収束する。
## §2: 「発射前のタメを見えるようにする」——CONVERGE_SECONDS/ORB_MID_PX/
## _PEAK_PXを新数値へ、粒子を金色のみから金+水色の2色へ、発射直前に
## 光点全体を白くする仕上げを追加した。
## 「エオスバーストの攻撃主体をソティリスへ一本化」(2026-08-02、同日
## 2ラウンド目) — CONVERGE_SECONDSは新しいSTRIKE_PREP窓(接近完了直後の
## 短い最終収束)とそのまま一致させる——`converge_start := BEAM_
## START - CONVERGE_SECONDS`という既存の式そのままで、境界がSTRIKE_PREP_
## START_SECONDS(=接近完了の瞬間)にちょうど一致する。WHITEN_SECONDSは
## 元々0.05秒でこの窓より短いため無変更のまま収まる。
## 「竜とソティリスの突きを作り直す」(2026-08-05、同日追加ラウンド) —
## STRIKE_PREP(②踏み込み前の溜め)がTHRUST_LUNGE(③突き)へ分割された
## ため、PREP_STARTからBEAM_STARTまでの全区間(②+③)をカバーするよう
## 合算した——口元の光が"タメと突きの間ずっと"集まり続ける見た目を維持する。
const EOS_BURST_MOUTH_CONVERGE_SECONDS := \
	EOS_BURST_STRIKE_PREP_SECONDS + EOS_BURST_THRUST_LUNGE_SECONDS  ## 0.21
const EOS_BURST_MOUTH_ORB_MID_PX := 8.0  ## "8pxから" の起点
const EOS_BURST_MOUTH_ORB_PEAK_PX := 26.0  ## "26pxへ" の到達点
const EOS_BURST_MOUTH_CONVERGE_PARTICLE_COUNT := 7  ## "周囲から水色と金色の粒子が集まる"
const EOS_BURST_MOUTH_WHITEN_SECONDS := 0.05  ## "発射直前に光点を白くする" — == ROAR_LAUNCH_PREP_SECONDS, unchanged


## Renamed in spirit only (kept the name to avoid touching every call site)
## — with the two-speed tail/head split retired, there's no longer a
## distinct "head sub-phase"; the sword-tip charge orb's own 0->MID_PX
## base-rise now simply begins as soon as the dragon starts becoming
## visible at all (footlight_end, the moment the reveal sweep itself
## begins).
func _eos_burst_head_reveal_start_seconds() -> float:
	return EOS_BURST_REVEAL_START_SECONDS


func _eos_burst_mouth_orb_diameter_px(elapsed: float) -> float:
	var head_start := _eos_burst_head_reveal_start_seconds()
	var converge_start := EOS_BURST_BEAM_START_SECONDS - EOS_BURST_MOUTH_CONVERGE_SECONDS
	if elapsed < head_start or elapsed >= EOS_BURST_BEAM_START_SECONDS:
		return 0.0
	if elapsed < converge_start:
		var t := (elapsed - head_start) / maxf(0.0001, converge_start - head_start)
		return lerpf(0.0, EOS_BURST_MOUTH_ORB_MID_PX, smoothstep(0.0, 1.0, t))
	var t2 := (elapsed - converge_start) / EOS_BURST_MOUTH_CONVERGE_SECONDS
	return lerpf(EOS_BURST_MOUTH_ORB_MID_PX, EOS_BURST_MOUTH_ORB_PEAK_PX, smoothstep(0.0, 1.0, t2))


## §3: 剣先の光球+収束粒子——「エオスバーストの攻撃主体をソティリスへ
## 一本化」(2026-08-02、同日2ラウンド目)でこの光の集約点を竜の口から
## ソティリスの剣先(`_eos_burst_sword_tip_pos`、実際の発射点)へ変更した
## ——「主砲がSotiris/SwordTipから出る」ためには、力が集まる場所自体も
## そこでなければならない。窓・粒子数・色の仕組みは無改修。
func _draw_eos_burst_mouth_charge(view: Rect2, unit_id: int, elapsed: float) -> void:
	var head_start := _eos_burst_head_reveal_start_seconds()
	if elapsed < head_start or elapsed >= EOS_BURST_BEAM_START_SECONDS:
		return
	var tip := _eos_burst_sword_tip_pos(view, unit_id, elapsed)
	var orb_d := _eos_burst_mouth_orb_diameter_px(elapsed)
	if orb_d > 0.01:
		# §2: "発射直前に光点を白くする" — the outer ring blends from cyan
		# toward pure white across the WHITEN window at the very end of
		# converge, instead of staying cyan all the way to BEAM_START.
		var whiten_start := EOS_BURST_BEAM_START_SECONDS - EOS_BURST_MOUTH_WHITEN_SECONDS
		var whiten_t := 0.0
		if elapsed >= whiten_start:
			whiten_t = smoothstep(0.0, 1.0, (elapsed - whiten_start) / EOS_BURST_MOUTH_WHITEN_SECONDS)
		var outer_col := Color(0.55, 0.9, 1.0, 0.5).lerp(Color(1.0, 1.0, 1.0, 0.9), whiten_t)
		_fill_soul_break_dot(tip, orb_d * 0.5, Color(1.0, 1.0, 1.0, 0.95))
		_fill_soul_break_dot(tip, orb_d * 0.5 + 3.0, outer_col)
	var converge_start := EOS_BURST_BEAM_START_SECONDS - EOS_BURST_MOUTH_CONVERGE_SECONDS
	if elapsed < converge_start:
		return
	var ct := (elapsed - converge_start) / EOS_BURST_MOUTH_CONVERGE_SECONDS
	for i in EOS_BURST_MOUTH_CONVERGE_PARTICLE_COUNT:
		var seed_f := float(i) * 23.0 + 11.0
		var ang := fmod(seed_f, TAU)
		var start_r := lerpf(40.0, 70.0, fmod(seed_f * 3.1, 1.0))
		var start_pt := tip + Vector2(cos(ang), sin(ang)) * start_r
		var local_t := clampf(ct * 1.3 - fmod(seed_f, 1.0) * 0.25, 0.0, 1.0)
		var p := start_pt.lerp(tip, smoothstep(0.0, 1.0, local_t))
		var alpha := (1.0 - local_t * 0.2) * 0.85
		# §2: "水色と金色の粒子が集まる" — alternate gold/cyan (was gold only).
		var col := Color(1.0, 0.85, 0.4, alpha) if i % 2 == 0 else Color(0.55, 0.94, 1.0, alpha)
		_fill_soul_break_dot(p, 2.2, col)


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
## `_draw_eos_burst_mouth_converge_rim_flash`(竜の輪郭発光、+`EOS_BURST_
## OUTLINE_KEY_PREFIX`)・`_draw_eos_burst_eye_glow`(竜の目の発光)を完全
## 削除した(いずれも竜のrect/EYE_FRACに依存する専用演出、grep確認済み)。
## `_eos_burst_charge_extra_dim`(CHARGE窓の背景暗転、竜のgeometryとは無関係
## な汎用演出)は無改修のまま維持。
func _eos_burst_charge_extra_dim(elapsed: float) -> float:
	if elapsed < EOS_BURST_REVEAL_END_SECONDS or elapsed >= EOS_BURST_BEAM_START_SECONDS:
		return 0.0
	var span := EOS_BURST_BEAM_START_SECONDS - EOS_BURST_REVEAL_END_SECONDS
	var t := (elapsed - EOS_BURST_REVEAL_END_SECONDS) / maxf(0.0001, span)
	return EOS_BURST_CHARGE_EXTRA_DIM_ALPHA * smoothstep(0.0, 1.0, t)


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — README「0.25〜1.25秒
## の窓(旧・竜のsummon time)を空白にしない。同じ入力ロック/暗転は維持した
## まま、ソティリスの足元で弱く脈動する地面のオーラへ差し替える。alpha
## 0→0.32→0を一度だけ、新しい召喚っぽい生物/物体を作らない」。
## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — TIMELINE_V13.csv
## 「0.25〜1.25秒: ソティリスだけの弱い予備光、solar aura frame0 alpha
## max0.24」——素材を新規`solar_sword_aura_v13`へ差し替え、①frame0だけを
## 使う(旧v12の「全4コマを巡回」から変更、README「最大出力(掲剣中)の
## 表示と混同しない、明確に控えめな別演出にする」を反映)②ピークalphaを
## 0.32→0.24へ弱める、の2点を更新。`sin(t*PI)`による単発の0→ピーク→0
## (ループ再生の定常オーラにしない)は無改修のまま維持。位置は掲剣中の
## オーラと同じ`_eos_burst_rear_anchor_pos`+`EOS_BURST_SOLAR_AURA_LOCAL_
## POSITION`を共有(新しい定数を増やさない)。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) —
## `_draw_eos_burst_summon_window_pulse`(この関数、REVEAL_START〜
## REVEAL_END=0.25〜1.25秒の窓を埋める予備光)を呼び出しごと完全に削除
## した。この演出は「character/aura本体がWINDUP_SECONDS(1.25秒)まで
## 動き出さない」という**旧タイムライン**の前提のもとで「その間の空白窓を
## 埋める」ために作られたものだったが、v20は`EOS_BURST_APPROACH_START_
## SECONDS`をWINDUP_SECONDSから完全に切り離し、character/aura本体を
## わずか0.08秒後には動かし始める(下記`EOS_BURST_LEAD_IN_SECONDS`)——
## この予備光自身のウィンドウ(0.25〜1.25秒)は実際のオーラ本体
## (`_draw_eos_burst_charge_aura`、0.08〜1.20秒相当、同じ`EOS_BURST_
## SOLAR_AURA_DIR`/`_LOCAL_POSITION`/frame0を使う)とほぼ完全に重なって
## しまい、同じ画面位置へ2枚のaura_00.pngを同時に描く二重発光バグになる
## ところだった(headless検証でこの重複を直接確認)。埋めるべき「空白窓」
## 自体がv20の設計で解消された以上、この演出を残す理由も同時に無くなった
## と判断——旧関数・定数(`EOS_BURST_SUMMON_PULSE_PEAK_ALPHA`)ごと削除した。
## ソティリス自身の足元グロー(`_draw_eos_burst_dragon_prelight`——竜の
## geometryとは無関係、タメ開始前から光る演出、window自体が既に空幅
## `[SUMMON_PULLBACK,SUMMON_PULLBACK+SUMMON_CHARGE)`=`SUMMON_CHARGE=0`
## のため元々no-op)は無改修のまま維持。
func _draw_eos_burst_back_vfx(view: Rect2) -> void:
	if not _eos_burst_vfx_active():
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	var unit_id := int(entry.get("unit_id", 0))
	var elapsed := _battle_anim_phase_elapsed
	_draw_eos_burst_dragon_prelight(view, unit_id, elapsed)


## §3/§5: 「発射直前の0.12秒間」の照準線——主砲は剣先(`_eos_burst_sword_
## tip_pos`)から出るため、照準もそこから敵へ向ける。
func _draw_eos_burst_mouth_aim_light(view: Rect2, unit_id: int, elapsed: float) -> void:
	var aim_start := EOS_BURST_BEAM_START_SECONDS - EOS_BURST_AIM_LIGHT_SECONDS
	if elapsed < aim_start or elapsed >= EOS_BURST_BEAM_START_SECONDS:
		return
	var aim_t := (elapsed - aim_start) / EOS_BURST_AIM_LIGHT_SECONDS
	var aim_alpha := sin(clampf(aim_t, 0.0, 1.0) * PI) * 0.7
	var tip := _eos_burst_sword_tip_pos(view, unit_id, elapsed)
	var target := _eos_burst_impact_point(view)
	var aim_len := tip.distance_to(target) * 0.35
	var aim_dir := (target - tip).normalized()
	_draw_eos_burst_quad(tip, tip + aim_dir * aim_len, 1.5, Color(0.75, 0.95, 1.0, aim_alpha))


## 「エオスバースト最終仕上げ: 攻撃後半の完成」——主砲テクスチャの全面
## 再設計。①配色を「中心:白〜明るいシアン、外側:金色」へ反転(旧: 中心
## 白→中間金→外周シアン)。②「ドット絵の輪郭を維持...ぼかした高解像度
## エフェクトは禁止」——低解像度キャンバス(24x8)で焼き、色帯も滑らかな
## lerpではなく3段階の塗り分け(白/シアン/金、境界は硬いカットオフ)にする
## ことで、NEARESTで拡大表示した時に意図的にブロック状のドット絵として
## 見えるようにした(旧実装は400x112の滑らかなグラデーション+LINEARフィルタ
## で、これ自体が今回禁止された"ぼかした高解像度エフェクト"に該当した)。
## 「光撃は剣先を原点として、短い状態から前方へ伸びる細長い光槍にする」
## (2026-08-05、同日追加ラウンド) — 旧形状(根本70%が一定幅、先端30%
## だけ収束する太いカプセル)を、根元(8-12px)→最大幅(18-24px、根元寄り
## `PEAK_X_FRAC`地点)→先端(鋭く0)という非対称な"葉/刃"型へ全面差し替え。
## 配色も「白い芯、金色の本体、水色の細い外縁」の順(中心から外側)に更新
## ——旧配色(中心白→中間シアン→外周金)から入れ替え、シアンは外周の
## 細い縁取りだけに縮小した。低解像度キャンバス+硬いカットオフ(グラ
## デーションlerpなし)でNEARESTドット絵の輪郭を維持する方針は前ラウンド
## から継続。
func _eos_burst_spear_texture() -> Texture2D:
	if _eos_burst_spear_cache != null:
		return _eos_burst_spear_cache
	var w := 32
	var h := 12
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	## 「エオスバースト演出全面刷新」(2026-08-11) — 「中心は白、内側は水色、
	## 外側は金色」——旧配色(白→金→水色)から中間/外側を入れ替えた。
	var col_white := Color(1.0, 1.0, 1.0)
	var col_cyan := Color(0.55, 0.94, 1.0)
	var col_gold := Color(1.0, 0.82, 0.25)
	var root_frac := EOS_BURST_SPEAR_ROOT_FRAC
	var peak_x := EOS_BURST_SPEAR_PEAK_X_FRAC
	for px in w:
		var x := float(px) / float(w - 1)
		var half_h: float
		if x < peak_x:
			half_h = lerpf(root_frac, 1.0, smoothstep(0.0, 1.0, x / peak_x))  ## 根元 -> 最大幅
		else:
			half_h = lerpf(1.0, 0.0, smoothstep(0.0, 1.0, (x - peak_x) / (1.0 - peak_x)))  ## 最大幅 -> 先端(鋭く0)
		if half_h < 0.03:
			continue
		for py in h:
			var cy := (float(py) - (h - 1) * 0.5) / ((h - 1) * 0.5)
			var d := absf(cy) / half_h
			if d > 1.0:
				continue
			var col: Color
			if d < 0.45:  ## 中心: 白い芯
				col = col_white
			elif d < 0.85:  ## 内側: 水色
				col = col_cyan
			else:  ## 外側: 金色
				col = col_gold
			img.set_pixel(px, py, Color(col.r, col.g, col.b, 1.0))
	var tex := ImageTexture.create_from_image(img)
	_eos_burst_spear_cache = tex
	return tex


## 「エオスバースト最終仕上げ: 攻撃後半の完成」— 「主砲はソティリスの剣先
## から敵まで連続してつながる」——旧実装(固定260x72pxの離散オブジェクトが
## 剣元とのあいだに常に隙間を残したまま飛ぶ、短い後方トレイルで隙間を
## ごまかす設計)を全面撤去し、SwordTip(毎フレーム生の位置)から着弾点まで
## 実際に伸び続ける**可変長ビーム**に作り直した——テクスチャの根本(x=0、
## 一定幅)を常にoriginへ固定し、先端(x=1、鋭く収束)だけが伸びる/縮む
## ことで「連続してつながる」を構造そのもので保証する(隙間を作りうる
## コードパスが存在しない)。
## 3段階: ①[BEAM_START, HIT_AT) 飛翔——beam_lengthがMAX_LENGTH_PXの
## `START_FRAC`(10%)相当の短い状態から、min(MAX_LENGTH_PX, 敵までの実
## 距離)へease-outで伸びる("scale.x = 0.1 -> 1.0のように剣先から伸ばす"、
## "長さ96-128px程度"、①②③の接近で事前に距離を詰めてあるため多くの場合
## 実距離のほうが短く、実質的に実距離いっぱいまで伸びる)②[HIT_AT,
## +BRIGHT_HOLD) 明るい芯を保持(beam_lengthはmin(MAX_LENGTH_PX, 実距離)に
## 固定=着弾点まで完全接続)③[+BRIGHT_HOLD, +BRIGHT_HOLD+THIN) 太さを
## THIN_HEIGHT_FRACまで、alphaを0まで線形に弱める(「細く弱くなる光線」)。
## 全区間、originを毎フレーム`_eos_burst_sword_tip_pos`から読み直すため
## 「光線はSwordTipと敵の着弾地点をつないだ状態」が常に成立する。NEAREST
## フィルタ(上書きなし、プロジェクト全体のデフォルトのまま)——「ドット絵
## の輪郭を維持」。
## 「エオスバースト演出全面刷新」(2026-08-11) — 光撃(EOS_BEAM)本体と、
## 光の内部/先端に乗せる竜のシルエット(`_draw_eos_burst_beam_dragon_
## wisp`、下記)の両方が「同じ基準ノード」から位置を取れるよう、幾何
## (origin/target/回転/長さ/太さ/alpha)をこの1つの関数へ集約した——
## 別々のTweenや別々の計算式で２つを動かすと、竜が光やソティリスから
## 遅れて見えるリスクが生じるため、両方がこの同じ戻り値だけを参照する。
func _eos_burst_beam_state(view: Rect2, unit_id: int, elapsed: float) -> Dictionary:
	var origin := _eos_burst_sword_tip_pos(view, unit_id, elapsed)
	var target := _eos_burst_impact_point(view)
	var span := target - origin
	var full_length := span.length()
	if full_length < 1.0:
		return {"active": false}
	var rot := span.angle()
	var traveling := elapsed < EOS_BURST_HIT_AT_SECONDS
	# 「連続してつながる」— headless実測でSwordTip-敵間の実距離が148px前後
	# (MAX_LENGTH_PXの96-128px想定より大きい)ケースを確認したため、最終
	# 到達長は**常に`full_length`(実距離)**とし、MAX_LENGTH_PX/START_FRACは
	# 「短い状態から伸ばす」の起点サイズ(típicalな112pxの10%≈11px)としてのみ
	# 使う——「96-128px程度」は代表的なケースの目安と解釈し、隙間を作らない
	# という何ラウンドも前から保護されてきたこのビーム自身の不変条件("剣先
	# から敵まで連続してつながる...隙間を作りうるコードパスが存在しない")を
	# 優先した。実距離が長い場合でも起点は小さいまま(急に画像全体を表示しない)
	# ので、旧来の「画面を横断する太いカプセル」の見た目には戻らない。
	var beam_length := full_length
	var height_scale := 1.0
	var alpha := 1.0
	if traveling:
		var raw_t := clampf(
			(elapsed - EOS_BURST_BEAM_START_SECONDS) / EOS_BURST_BEAM_TRAVEL_SECONDS, 0.0, 1.0)
		var start_len := EOS_BURST_SPEAR_MAX_LENGTH_PX * EOS_BURST_SPEAR_START_FRAC
		beam_length = lerpf(start_len, full_length, _eos_burst_ease_out_cubic(raw_t))
		# 「発射直後は細く、0.10〜0.15秒で太くなる」——長さの伸びとは独立した
		# 太さだけのランプ(BEAM_STARTからの絶対秒、travelの尺とは別軸)。
		var widen_t := clampf(
			(elapsed - EOS_BURST_BEAM_START_SECONDS) / EOS_BEAM_WIDEN_SECONDS, 0.0, 1.0)
		height_scale = lerpf(0.15, 1.0, smoothstep(0.0, 1.0, widen_t))
	else:
		var post := elapsed - EOS_BURST_HIT_AT_SECONDS
		if post >= EOS_BURST_BEAM_BRIGHT_HOLD_SECONDS:
			var thin_t := clampf(
				(post - EOS_BURST_BEAM_BRIGHT_HOLD_SECONDS) / EOS_BURST_BEAM_THIN_SECONDS, 0.0, 1.0)
			height_scale = lerpf(1.0, EOS_BURST_BEAM_THIN_HEIGHT_FRAC, thin_t)
			alpha = lerpf(1.0, 0.0, thin_t)
	return {
		"active": true, "origin": origin, "target": target, "rot": rot,
		"beam_length": beam_length, "height_scale": height_scale, "alpha": alpha,
		"traveling": traveling,
	}


func _draw_eos_burst_breath(view: Rect2, unit_id: int, elapsed: float) -> void:
	var start := EOS_BURST_BEAM_START_SECONDS
	var end_window := EOS_BURST_HIT_AT_SECONDS + EOS_BURST_BEAM_AFTERGLOW_SECONDS
	if elapsed < start or elapsed >= end_window:
		return
	var st := _eos_burst_beam_state(view, unit_id, elapsed)
	if not bool(st.get("active", false)):
		return
	var beam_length: float = st["beam_length"]
	var alpha: float = st["alpha"]
	if beam_length < 1.0 or alpha <= 0.01:
		return
	var beam := _eos_burst_spear_texture()
	var draw_size := Vector2(beam_length, EOS_BURST_BEAM_HEIGHT_PX * float(st["height_scale"]))
	# Texture's wide root sits at its own x=0 (left edge) — position the
	# rect so that edge lands exactly at origin (SwordTip), extending along
	# +local-x (== dir after rotation) toward the tapered tip.
	draw_set_transform(st["origin"], st["rot"], Vector2.ONE)
	draw_texture_rect(
		beam, Rect2(Vector2(0.0, -draw_size.y * 0.5), draw_size),
		false, Color(1.0, 1.0, 1.0, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 「SizeDragonFix v6」(2026-08-12) — 旧`_draw_eos_burst_beam_dragon_wisp`
## (光撃の先端へ`eos_dragon_assault_6f.png`の1コマを金色半透明で重ねる
## 追加レイヤー)を削除した——dispatcher(`_draw_eos_burst_front_vfx`)から
## 元々一度も呼ばれていない死んだ関数だった上、旧assaultシート専用の
## ローダーに依存していたため、「旧`eos_dragon_assault_6f.png`への参照が
## 0件」を満たすためここで完全に削除する。


## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — 旧`_draw_eos_burst_
## dragon_light_feed`(竜の口/頭部からSwordTipへ短い光の奔流を流し、
## 「竜の光が主砲へ合流して威力を増幅する」ことを表現していた装飾)は
## 完全に削除した。README「竜を主斬撃へ合成、差し替え、子ノード化する
## 処理」の禁止対象に該当する——竜は既にBEAM_START(4.15)より遥か前の
## FADE_END(2.50)で完全に消えているため、この効果は実際には常に
## 「もう存在しない竜の口」から発光する残留グローとしてしか機能し得ず、
## かつ「竜が斬撃(の発射)に寄与している」ように見える演出そのものが
## 今回の確定方針(「竜は背後へ出現するだけ」)と矛盾する。dispatcher
## (`_draw_eos_burst_front_vfx`)からの呼び出しも削除、`EOS_BURST_LIGHT_
## FEED_LEAD_SECONDS`/`_TAIL_SECONDS`も呼び出し元が無くなったため削除。


## §6's own "剣先付近で大きな星状フラッシュ" — a one-shot 8-ray starburst
## right at the sword tip as release begins (BEAM_START), independent of
## the breath ribbon's own travel.
func _draw_eos_burst_release_flash(view: Rect2, unit_id: int, elapsed: float) -> void:
	var age := elapsed - EOS_BURST_BEAM_START_SECONDS
	if age < 0.0 or age >= EOS_BURST_RELEASE_FLASH_SECONDS:
		return
	var tip := _eos_burst_sword_tip_pos(view, unit_id, elapsed)
	var e := 1.0 - clampf(age / EOS_BURST_RELEASE_FLASH_SECONDS, 0.0, 1.0)
	_fill_soul_break_dot(tip, lerpf(10.0, 46.0, 1.0 - e), Color(1.0, 0.98, 0.9, e * 0.85))
	for i in 8:
		var ang := TAU * float(i) / 8.0
		var ray_len := (1.0 - e) * 34.0
		var ray_end := tip + Vector2(cos(ang), sin(ang)) * ray_len
		_draw_eos_burst_quad(tip, ray_end, lerpf(4.0, 1.0, 1.0 - e), Color(1.0, 0.95, 0.7, e * 0.7))


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 旧`_draw_eos_burst_
## ground_glow`(竜の足元フレア、`_eos_burst_dragon_anchor_feet`依存)を
## 完全削除した。


## ANTICIPATION: Sotiris's own pre-summon glow at his feet (unchanged
## mechanism, window unchanged — sits inside SUMMON_CHARGE, before the
## dragon even starts appearing).
const EOS_BURST_PRELIGHT_MOTE_COUNT := 10
const EOS_BURST_PRELIGHT_RISE_PX := 90.0


func _draw_eos_burst_dragon_prelight(view: Rect2, unit_id: int, elapsed: float) -> void:
	var window_start := EOS_BURST_SUMMON_PULLBACK_SECONDS
	if elapsed < window_start or elapsed >= window_start + EOS_BURST_SUMMON_CHARGE_SECONDS:
		return
	var feet := _eos_burst_caster_feet(view, unit_id, elapsed)
	var t := (elapsed - window_start) / EOS_BURST_SUMMON_CHARGE_SECONDS
	var ring_r := lerpf(4.0, 26.0, smoothstep(0.0, 1.0, t))
	var ring_a := lerpf(0.0, 0.6, smoothstep(0.0, 1.0, t))
	for i in 10:
		var a := TAU * float(i) / 10.0
		var dir := Vector2(cos(a), sin(a) * 0.34)
		var col := Color(1.0, 0.9, 0.55, ring_a) if i % 2 == 0 else Color(0.5, 0.93, 1.0, ring_a)
		_draw_eos_burst_quad(feet + dir * ring_r, feet + dir * (ring_r + 4.0), 2.0, col)
	var mote_a := smoothstep(0.0, 1.0, t)
	for i in EOS_BURST_PRELIGHT_MOTE_COUNT:
		var seed_f := float(i) * 17.0 + 3.0
		var phase := fmod(t * 1.3 + fmod(seed_f, 1.0), 1.0)
		var px := feet.x + (fmod(seed_f * 3.7, 1.0) - 0.5) * 40.0
		var py := feet.y - phase * EOS_BURST_PRELIGHT_RISE_PX
		var alpha := (1.0 - phase) * 0.85 * mote_a
		var col2 := Color(1.0, 0.85, 0.4, alpha) if i % 2 == 0 else Color(0.5, 0.92, 1.0, alpha)
		_fill_soul_break_dot(Vector2(px, py), 2.2, col2)


## 「Slower + New Impact v4」(2026-08-12) — 旧`_draw_eos_burst_impact_
## sprite`(丸い巨大爆発`eos_impact_mega_explosion_6f_v3.png`)・旧
## `_draw_eos_burst_impact_flash_sprite`(`eos_impact_flash_6f.png`)・
## 旧`_draw_eos_burst_downslash_wave`(画面を横切る細い直線斬撃
## `eos_downslash_wave_6f.png`)は、README「必ず撤去するもの」により
## この3関数ごと完全に削除した(呼び出し元もdispatcherから撤去、下記
## 参照)。素材ファイル自体は削除しない(このプロジェクトの既定方針)。
## 代わりに新規3素材(三日月斬撃・縦の竜牙命中・上昇する残光)を導入する。


## 敵の「ground anchor」(足元中央) — `_boss_icon_rect`のbottom-center。
## 「敵の中心ではなく足元基準」を、既存の`_eos_burst_impact_point`
## (rect中心)とは別の新しいヘルパーとして満たす。
func _eos_burst_enemy_ground_anchor(view: Rect2) -> Vector2:
	var rect := _boss_icon_rect(view)
	return Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y)


## === 三日月斬撃(`eos_sword_crescent_6f.png`、384×256×6) ===
## README「フレーム0はソティリスの下げた刀身先端に置き、敵へ向けて
## 移動させる」——③振り下ろし窓の途中(絶対時刻2.30秒)から始まり、
## 振り下ろし完了後も0.26秒続く独立したタイムライン。
const EOS_BURST_CRESCENT_SHEET_PATH := "res://assets/art/eos_sword_crescent_6f.png"
const EOS_BURST_CRESCENT_FRAME_COUNT := 6
const EOS_BURST_CRESCENT_FRAME_SIZE := Vector2(384.0, 256.0)
## README指定のコマ時間そのまま(斬撃は3・4コマ目をやや長く見せる)。
const EOS_BURST_CRESCENT_FRAME_DURATIONS: Array[float] = [0.05, 0.06, 0.08, 0.09, 0.07, 0.07]
const EOS_BURST_CRESCENT_SECONDS := 0.42  ## sum of the above
const EOS_BURST_CRESCENT_START_SECONDS := 2.30  ## README絶対時刻(振り下ろし窓の途中)
const EOS_BURST_CRESCENT_END_SECONDS := \
	EOS_BURST_CRESCENT_START_SECONDS + EOS_BURST_CRESCENT_SECONDS  ## 2.72
## PowerShellでシート6コマ全ての「alpha加重centroid」を実測——単純な
## bbox中心は装飾的な火花の散らばりに引きずられ不安定だったため、alphaを
## 重みにした重心を採用(`f0=(170.6,120.5)`〜`f5=(204.6,130.5)`)。この値を
## 「フレームiが表示される瞬間、シートの中身のうちどこが視覚的な芯か」
## として使い、`アンカー座標(t) - centroid[i]`をdraw矩形のtop-leftにする
## ——これにより、絵自体の芯(centroid)を計算した移動経路(sword tip→敵)
## へ正確に一致させ続けられる(コマ切り替えのたびに芯が変な位置へ跳ねない)。
const EOS_BURST_CRESCENT_FRAME_CENTROID: Array[Vector2] = [
	Vector2(170.6, 120.5),
	Vector2(187.4, 131.4),
	Vector2(207.6, 125.7),
	Vector2(220.6, 120.8),
	Vector2(203.9, 127.8),
	Vector2(204.6, 130.5),
]

var _eos_burst_crescent_tex_cache: Texture2D = null
func _eos_burst_crescent_texture() -> Texture2D:
	if _eos_burst_crescent_tex_cache == null:
		_eos_burst_crescent_tex_cache = _soul_break_load_texture(EOS_BURST_CRESCENT_SHEET_PATH)
	return _eos_burst_crescent_tex_cache


func _draw_eos_burst_crescent_slash(view: Rect2, unit_id: int, elapsed: float) -> void:
	var age := elapsed - EOS_BURST_CRESCENT_START_SECONDS
	if age < 0.0 or age >= EOS_BURST_CRESCENT_SECONDS:
		return
	var tex := _eos_burst_crescent_texture()
	if tex == null:
		return
	var frame_idx := _eos_burst_frame_index_from_table(EOS_BURST_CRESCENT_FRAME_DURATIONS, age)
	var t := clampf(age / EOS_BURST_CRESCENT_SECONDS, 0.0, 1.0)
	var origin := _eos_burst_sword_tip_pos(view, unit_id, elapsed)
	var dest := _eos_burst_impact_point(view)
	var anchor := origin.lerp(dest, _eos_burst_ease_out_cubic(t))
	var centroid: Vector2 = EOS_BURST_CRESCENT_FRAME_CENTROID[frame_idx]
	var top_left := (anchor - centroid).round()
	var src := Rect2(
		float(frame_idx) * EOS_BURST_CRESCENT_FRAME_SIZE.x, 0.0,
		EOS_BURST_CRESCENT_FRAME_SIZE.x, EOS_BURST_CRESCENT_FRAME_SIZE.y)
	draw_texture_rect_region(tex, Rect2(top_left, EOS_BURST_CRESCENT_FRAME_SIZE), src)


## === MANIFEST_ONLY_GRAND_SLASH v8: 五層斬撃 ===
## 「今回の確定方針は『竜は背後へ出現するだけ』です。竜を攻撃へ参加させ
## ず、その分ソティリス自身の斬撃を五層へ強化してください」——竜が敵へ
## 移動しながら斬撃と並走する旧`_draw_eos_burst_dragon_charge_overlay`
## (v7)、竜と剣を結ぶ意匠だった旧`eos_sword_crescent_12f.png`ベースの
## 三日月斬撃(`_draw_eos_burst_crescent_slash12`/`EOS_BURST_CRESCENT12_
## *`/`_eos_burst_ease_in_out_sine`、v5)、それに紐づく早期の独立フラッシュ
## (`_draw_eos_burst_slash_flash`、CRESCENT12_END基準)を、ここで丸ごと
## 完全に削除した(README「旧`eos_sword_crescent_12f.png`への参照が0件」
## を満たす、`_eos_burst_ease_in_out_sine`は他に呼び出し元が無いことを
## grepで確認した上で道連れに削除)。かわりにSotiris自身の刀身から発する
## 新規4レイヤー(+既存の大型爆発2レイヤーを合わせて計5層)へ置き換える。
## 「接触時だけ短い反転フラッシュ」(TIMELINE_V8「4.78,4.86,screen_flash」)
## は、GrandCrescentの到達がHIT_AT(4.78)と厳密に一致する設計のため、
## 既存の`_draw_eos_burst_impact_screen_flash`(`_eos_burst_contact_
## trigger_elapsed`基準、hitstop解除の瞬間に発火、無改修)がそのまま
## この役割を果たす——2つの独立したフラッシュを近接した時刻に重ねる必要が
## 無くなったため、旧`_draw_eos_burst_slash_flash`は復活させない。
##
## 「CanvasItemMaterial.BLEND_MODE_ADDで重ねます」——このファイルは単一の
## 同期`_draw()`ディスパッチ(VFX用の実Sprite2D/Node2Dノードを一切持たず、
## `elapsed`の純関数として毎フレーム描画し直す設計、このsaga全体で確立
## 済みのアーキテクチャ)のため、個々のdraw呼び出しへノード単位の
## BlendModeを適用することができない(過去何ラウンドも前から繰り返し
## 確認・開示済みの制約)。今回も新規ノードを増設せず、このファイルの
## 他の全スプライトVFX(fang/afterglow/massive_burst等)と同じ通常の
## `draw_texture_rect_region(tex, rect, src)`(modulateなし=Color(1,1,1,1)
## 相当)で描く——加算合成の見た目は素材自身が既に暗い背景+明るい光の
## 意匠として作られていることに委ね、コード側で追加のRGB増幅は行わない
## (この判断・制約は報告書に明記する)。

## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — README「斜めの画面
## 横断線、大三日月、追従波をactive演出から外し」——旧`_eos_burst_slash_
## lane_y`/`_eos_burst_slash_start_target_x`(GrandCrescent/TwinShockwave/
## BladeReleaseFlashだけが使っていた、いずれもこの回で完全削除)を完全に
## 削除した(grep確認済み、呼び出し元ゼロ)。新規`_draw_eos_burst_
## horizontal_slash`は自前の固定Yの式・start/target計算を持つ独立実装
## のため、この2関数は再利用していない。


## 新素材は1コマ=1ファイルで納品されているため(v8の横長シート+region切り
## 出しとは異なる)、この共有ヘルパーだけで①②③④の全レイヤーをカバー
## する——`_soul_break_load_texture`自身がpath文字列キーの汎用キャッシュ
## のため専用キャッシュ変数は不要(竜のmanifest/idleローダーと同じ設計)。
func _eos_burst_indexed_frame_texture(dir_prefix: String, frame_idx: int) -> Texture2D:
	return _soul_break_load_texture("%s%02d.png" % [dir_prefix, frame_idx])


## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — README「次を検索
## してください: blade_release_v8」——旧`_draw_eos_burst_blade_flash`
## (+`EOS_BURST_BLADE_FLASH_DIR`/`_FRAME_COUNT`/`_CELL_SIZE`/`_FRAME_
## DURATIONS`/`_SECONDS`/`_START_SECONDS`)を完全に削除した(grep確認済み、
## 呼び出し元ゼロ)。「v13のactive `frames/`にはblade_release_v8を同梱
## していない」——`res://assets/vfx/eos_burst/v13/`にこのフォルダ自体を
## コピーしていないことと合わせて二重に保証。


## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — README「各コマ末尾
## だけの45〜50msクロスフェードを廃止し、各コマ時間全体で隣接2枚を
## Smootherstep補間」——旧`_eos_burst_slash_crossfade_pair`(末尾クロス
## フェードのみ、Sine InOut)を完全に置き換える汎用版。新設`_eos_burst_
## ease_smootherstep`(quintic、`t*t*t*(t*(t*6-15)+10)`、`Tween.TRANS_
## QUINT`相当ではなく明示的にSmootherstep曲線)を使う。フレームiの**表示
## 時間全体**が「i→i+1への遷移」そのものになる設計——保持区間は無い。
## `curve`は各コマのmax alpha配列(Main/Echoのように全コマ同一値でも、
## 後述の爆発(#102)のように毎コマ異なる値でもよい、呼び出し側が正規化
## 済みの配列を渡す)。エネルギー正規化: `from_alpha=curve[i]*(1-mix)`、
## `to_alpha=curve[i+1]*mix`——curveが定数配列なら常にfrom+to=定数値
## (README「alpha合計は一定」)。最終コマ(N-1)だけは「i+1」が存在しない
## ため別扱い——自分自身の表示時間全体を使い、Quad EaseOut(`(1-t)^2`、
## 「素早く立ち上がり終盤でゆっくり0へ近づく」典型的な減衰カーブ)で
## `curve[N-1]`から0へフェードする(README「最終コマだけ最後のコマ時間
## を使ってQuad EaseOutで0へ消します」)。`_eos_burst_ease_sine_in_out`
## (burst側`_eos_burst_massive_burst_crossfade_pair`が今も使用中、#102で
## 未着手のため無改修のまま残置)とは別の独立した新関数として追加した。
func _eos_burst_ease_smootherstep(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * x * (x * (x * 6.0 - 15.0) + 10.0)


## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 参照実装
## `_edge_smoothed_linear`の移植。t=0/edge/1-edge/1でC1連続、区間境界の
## 各`EOS_BURST_MAIN_EDGE_EASE_RATIO`(10%)だけ2次のease-in/out
## (`edge*(2u²-u³)`)、中央80%は素のLinearのまま——「発進と停止だけ
## 柔らかくし、中間速度は変えない」を1つの式で表現する。
func _eos_burst_edge_smoothed_linear(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	var edge := EOS_BURST_MAIN_EDGE_EASE_RATIO
	if t < edge:
		var u := t / edge
		return edge * (2.0 * u * u - u * u * u)
	if t > 1.0 - edge:
		var u := (1.0 - t) / edge
		return 1.0 - edge * (2.0 * u * u - u * u * u)
	return t


## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — 旧`_eos_burst_
## constant_curve`(唯一の呼び出し元だったGrandCrescent/TwinShockwaveが
## この回で完全削除)を完全に削除した——爆発(`_draw_eos_burst_massive_
## burst`)は元々自前のper-frame配列(`OUTER_ALPHA_CURVE`/`CORE_ALPHA_
## CURVE`)をこの関数を介さず直接渡す設計だったため無影響。


## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「発光VFXでA/Bを交差させる際は通常の1-mix/mixではなく、A:pow(1-mix,0.70)
## /B:pow(mix,0.70)を使う。対象はAura、Main slash、Impact、Outer。ソティリス
## 本体は通常alpha補間のまま」——参照実装`_luminous_weights`と同数式。通常の
## 線形crossfadeでは中間点でA・Bとも約0.5倍になり両方薄くなる(=見た目の
## 明るさが谷になる)が、0.70乗のgamma補正は中間点でA・Bとも約0.616倍と
## なり、両者の合計輝度が中間点で不必要に沈まないようにする。`curve[i]`
## (Outerの`OUTER_ALPHA`など、絵ごとに定義された基準alpha)へこの重みを
## 掛けるだけなので、既存の呼び出し元(Main/Impact/Outerの3者が共有する
## この1関数)を書き換えるだけで3つ同時に直る。
const EOS_BURST_VFX_CROSSFADE_GAMMA := 0.70


func _eos_burst_luminous_weights(mix_value: float) -> Vector2:
	var mix := clampf(mix_value, 0.0, 1.0)
	return Vector2(
		pow(1.0 - mix, EOS_BURST_VFX_CROSSFADE_GAMMA),
		pow(mix, EOS_BURST_VFX_CROSSFADE_GAMMA))


func _eos_burst_frame_crossfade_pair(
		age: float, durations: Array[float], curve: Array[float]) -> Array:
	var n := durations.size()
	var cursor := 0.0
	for i in n - 1:
		var frame_time: float = durations[i]
		var seg_end := cursor + frame_time
		if age < seg_end:
			var t := clampf((age - cursor) / maxf(0.0001, frame_time), 0.0, 1.0)
			var mix := _eos_burst_ease_smootherstep(t)
			var weights := _eos_burst_luminous_weights(mix)
			var from_alpha: float = curve[i] * weights.x
			var to_alpha: float = curve[i + 1] * weights.y
			return [i, i + 1, from_alpha, to_alpha]
		cursor = seg_end
	var last := n - 1
	var last_dur: float = durations[last]
	var tail_t := clampf((age - cursor) / maxf(0.0001, last_dur), 0.0, 1.0)
	var decay := (1.0 - tail_t) * (1.0 - tail_t)  ## Quad EaseOut fade-to-0
	return [last, -1, curve[last] * decay, 0.0]


## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — README「以前
## あった高品質な金青の大斬撃が消え、細い水平線だけになっています...新しく
## 描いたり加工したりせず、同梱したv12承認版をそのまま戻してください」。
## v13の`horizontal_slash_v13`(細い水平線本体+残光、旧`_draw_eos_burst_
## horizontal_slash`とその専用定数・ヘルパー一式)を完全に削除した(grep
## 確認済み、呼び出し元ゼロ)。代わりに、v12承認版のgrand_crescent(Main、
## 16コマ)+twin_shockwave(Echo、12コマ)をバイト単位無加工で復元する
## (RESTORED_SLASH_SHA256_V12.tsvで実装前後とも一致を確認済み——コード側
## で画像を一切加工しない、既定方針そのもの)。


## === 復元された大斬撃(Main=`grand_crescent_v12_tip_locked/grand_00..15
## .png`、768×448×16) ===
## README「4つ(MainA/B, EchoA/B)はSprite2D...A/Bは隣接コマの全区間
## Smootherstepクロスフェード用」——既存の汎用`_eos_burst_frame_
## crossfade_pair()`(#101で新設、v10/v12の爆発でも使用中の共有関数、
## 参照実装`_apply_sequence_time`/`_apply_outer_time`と数式的に同一の
## 「フレームの表示時間全体がそのまま次フレームへの遷移になる、最終フレーム
## だけQuad EaseOutでalpha0へ」設計)をMainにもそのまま再利用する。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — 上記参照。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14、v14の直後) —
## README「v14は各画像の右端X=736を共有基準にしていました。ところが
## 大斬撃はコマごとに見える幅が変わります。右端だけが一定速度で前進
## しても、発光の中心はフレーム切替のたびに前後へ動き、左へ大きく膨らむ
## ため、水平飛翔ではなくその場変形に見えます」——`MAIN_FRONT_X`/`ECHO_
## FRONT_X`/`_CENTER_Y`(全コマ共有の固定local origin)を完全に廃止し、
## SLASH_CENTROID_PIVOTS_V15.tsv(各PNGを一切加工せず実測したalpha加重
## 重心)による**コマごとに異なる**local originへ置き換えた。top_left=
## anchor-pivot[idx]*scaleとすることで、描画後の実際の重心位置は常に
## `top_left+pivot*scale=anchor`——pivotの値に関わらず数式として厳密に
## anchorへ一致する(近似ではない)。A/Bクロスフェード中は各テクスチャが
## 自分自身のpivotを使う(README「A/Bを同じlocal_positionにしない」)。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — README「主斬撃の右斜め下に、
## 細い線状の追従画像が重なって不自然に見える。線の正体は主斬撃ではなく
## v15で追加した別レイヤー(`twin_shockwave_v12_tip_locked/echo_00..11
## .png`、`ECHO_TEXTURES`/`ECHO_TIMES`/`ECHO_PIVOTS`/`ECHO_DELAY`/
## `ECHO_MAX_ALPHA`/EchoA/EchoB)。以上をactive実装から全て削除して
## ください。v16フォルダにはEcho画像自体をコピーしません」——Echoレイヤー
## 一式(定数7個+`_draw_eos_burst_slash`内の呼び出し)を完全に削除した。
## Main(grand_crescent)自身の絵・色・ドット品質・scale・rotation・コマ順
## ・移動速度・水平軌道・0.78秒・重心ロックは全て「変更禁止」対象のまま
## 無改修——MAIN_SLASH_SHA256_V16.tsvで16枚全てのSHA-256が承認値(v15/v12
## と同一)と一致することを確認済み。旧v8〜v15の素材自体は物理削除せず
## (このファイル全体の既定方針)、パスだけをv16コピー先へ切替。
## 「CLEAN_HOLD_EXTENDED_REACH v17」(2026-08-15、"RELEASE_SYNC_NO_ECHO v16"
## の直後) — README「Echoを削除した後も、主斬撃の右斜め下に青白い小さな
## 別画像が残っている」——真因はEchoではなく、`grand_10.png`ほか後半コマ
## 自体に元々含まれていた分離小片(source座標x657..735,y312..348)だった。
## 絵を再生成・消しゴム加工すると承認済みの主斬撃自体が崩れるため、v17は
## 問題の無い原本8枚(`grand_00..05,07,08`)だけをactive再生から使う——
## `grand_06`/`grand_09..15`は禁止コマとしてv17フォルダに一切コピーせず、
## GDScriptのpreload/Array/active参照からも完全に外した。使用する8枚は
## ACTIVE_MAIN_SHA256_V17.tsvで実装前後ともSHA-256一致を確認済み(v16の
## 同じ8ファイルとバイト単位で同一)。「斬撃の後半が細くなり敵へ届く前に
## 消えたように見える」の対応として、7枚の遷移(0.46秒)で`grand_08`へ
## 到達した後、`grand_08`をalpha1.00で0.27秒保持してから最後の0.05秒
## だけFadeOutする「build→hold→fade」の3段階構造へ全面作り直した——旧
## `_draw_eos_burst_slash_layer`(汎用`_eos_burst_frame_crossfade_pair`を
## 呼ぶだけの単純なクロスフェード連鎖、最終コマも自分の持ち時間で即座に
## フェードを開始する設計)ではこの「一定時間フルアルファのまま静止する
## hold区間」を表現できないため、専用の描画関数(下記`_draw_eos_burst_
## slash_layer`)へ全面書き換えた——`_eos_burst_frame_crossfade_pair`
## 自体は爆発(`_draw_eos_burst_massive_burst`)が今も使用中のため無改修
## のまま維持、Main専用だった`_eos_burst_flat_curve`(このcurve引数を
## 埋めるためだけの補助関数)は呼び出し元が無くなったため完全に削除した。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — README「使用する主
## 斬撃は次の8枚だけです」——絵自体は無改修(ACTIVE_MAIN_SHA256_V18.tsvで
## v17と同一の8ファイルであることを確認済み)、パスだけv18コピー先へ切替。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 絵は無改修
## (ACTIVE_MAIN_SHA256_V19.tsvでv18と同一の8ファイルであることを確認済み、
## PRESERVED_ASSET_SHA256_V19.tsvでも同じ8枚が"preserved"扱い)、パスだけ
## v19コピー先へ切替(重心ロック方式=`_eos_burst_slash_center_x`のedge-
## easing化・接触後フェード尾の追加はコード側のみの変更)。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — 絵は無改修
## (ACTIVE_MAIN_SHA256_V20.tsvでv19と同一8ファイルであることを確認済み)、
## パスだけv20コピー先へ切替。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — README「Main slash、
## Impact、Outer、ContactFlash、damage、contact geometryの関数と定数は
## 変更禁止」——絵・build/travel/damage関連の定数は全て無改修のまま、
## LOCKED_FINISH_SHA256_V22.tsvで8/8ファイルがv21と完全一致(byte-
## identical)することを確認済み、パスだけv22コピー先へ切替。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — Main
## slash定数・PNGは変更禁止対象、LOCKED_FINISH_SHA256_V25.tsvで8/8
## ファイルがv22と完全一致することを確認済み、パスだけv25コピー先へ切替。
const EOS_BURST_MAIN_DIR := "res://assets/vfx/eos_burst/v25/frames/grand_crescent_v12_tip_locked/grand_"
## README「使用する主斬撃は次の8枚だけです: grand_00..05,07,08」——
## `_eos_burst_indexed_frame_texture`は"%02d"でファイル名を組み立てる
## 汎用ヘルパーのため、配列位置(0始まり、8要素)をそのまま渡すと位置6が
## 存在しない(禁止された)`grand_06.png`を、位置7が`grand_07.png`
## (実際は`grand_08.png`のはず)を誤って要求してしまう——v14の
## `EOS_BURST_MASSIVE_OUTER_FRAME_NUMBERS`と同じ「配列位置→実ファイル
## 番号」対応表(下記`_eos_burst_main_active_texture`)で解決する。
const EOS_BURST_MAIN_ACTIVE_FRAME_NUMBERS: Array[int] = [0, 1, 2, 3, 4, 5, 7, 8]
const EOS_BURST_MAIN_FRAME_COUNT := 8
const EOS_BURST_MAIN_FRAME_SIZE := Vector2(768.0, 448.0)
## FRAME_TIMES_V17.tsv「build」行(7遷移、grand_00→01→02→03→04→05→07→08)。
const EOS_BURST_MAIN_BUILD_DURATIONS: Array[float] = [
	0.055, 0.055, 0.060, 0.065, 0.070, 0.075, 0.080,
]
const EOS_BURST_MAIN_BUILD_SECONDS := 0.46  ## sum of the above
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — README「grand_08は
## 接触までalpha1.00。接触前FadeOutは禁止」——v17のhold(0.27秒)→fade
## (0.05秒)という2段階を廃止し、「build完了後は接触(=SLASH_DURATION_
## SECONDS)まで単純にalpha1.00で保持し続けるだけ、フェードは一切無い」
## 構造へ簡略化した。旧`EOS_BURST_MAIN_HOLD_END_SECONDS`/`_FADE_SECONDS`
## は削除——接触の瞬間は`_draw_eos_burst_slash`が窓外へ出た次のtickで
## `_eos_burst_slash_active`が即falseを返しMainA/Bが消える(このファイル
## 全体の全VFXが共有する既定のidiom)ことで自然に実現するため、明示的な
## フェード計算そのものが不要になった。
const EOS_BURST_MAIN_MAX_ALPHA := 1.0
## ACTIVE_MAIN_CENTROIDS_V17.tsv——8枚のalpha加重重心。v16のMAIN_PIVOTS
## から使用する8個(index0-5,7,8)だけをそのまま抜き出した値(絵がバイト
## 単位で不変なので重心も不変、再測定なし)。v18でも無改修(ACTIVE_MAIN_
## CENTROIDS_V18.tsvが同一の8値を再掲)。
const EOS_BURST_MAIN_PIVOTS: Array[Vector2] = [
	Vector2(604.836, 223.654), Vector2(616.036, 223.957), Vector2(639.637, 223.840), Vector2(629.025, 223.731),
	Vector2(609.844, 223.618), Vector2(592.873, 224.175), Vector2(554.140, 224.066), Vector2(537.265, 223.995),
]
## README「clean grand_08のalpha boundsの右端はsource x736、発光重心
## pivotはx537.265です。先端差198.735pxへfixed_scaleを掛け、敵中心から
## 差し引いてAnchor終点を決めてください」——`EOS_BURST_MAIN_PIVOTS[7].x`
## (537.265、既存の実測値そのもの)からの差分として導出し、198.735を
## 独立したハードコード値として重複させない。
const EOS_BURST_MAIN_FRAME08_ALPHA_BOUNDS_RIGHT_X := 736.0
const EOS_BURST_MAIN_FRAME08_TIP_OFFSET_SOURCE_X := \
	EOS_BURST_MAIN_FRAME08_ALPHA_BOUNDS_RIGHT_X - EOS_BURST_MAIN_PIVOTS[7].x  ## 198.735


## README「配列位置→実ファイル番号」変換(`EOS_BURST_MASSIVE_OUTER_FRAME_
## NUMBERS`と同じ発想) — array_index(0-7、pivots/build-durationsが使う
## のと同じ添字)をEOS_BURST_MAIN_ACTIVE_FRAME_NUMBERSで実際のgrand_NN
## 番号へ変換してからロードする。
func _eos_burst_main_active_texture(array_index: int) -> Texture2D:
	if array_index < 0 or array_index >= EOS_BURST_MAIN_ACTIVE_FRAME_NUMBERS.size():
		return null
	var frame_number: int = EOS_BURST_MAIN_ACTIVE_FRAME_NUMBERS[array_index]
	return _eos_burst_indexed_frame_texture(EOS_BURST_MAIN_DIR, frame_number)

## fixed_scale自体はv14から無改修(引き続き判断値、報告に開示)。
const EOS_BURST_SLASH_FIXED_SCALE := 0.82
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 「ソティリスが剣を振り下ろ
## した瞬間と斬撃が出る瞬間がずれている」という報告に対し、v15までの
## 独立した固定絶対値(3.92)を廃止し、`EOS_BURST_THRUST_LUNGE_START_
## SECONDS`(振り下ろし=frame6..11開始、3.45)+`EOS_BURST_DOWNSLASH12_
## RELEASE_OFFSET_SECONDS`から導出する式へ置き換えた——SWING_DURATIONS
## が将来変更されても、この式が指すreleaseフレーム開始時刻へ自動的に
## 追従する(「時刻ではなくアニメフレームへ同期」を、実コルーチンの無い
## このファイルでは"同じ絶対時刻の式から両方を導出する"ことで満たす、
## 詳細は上のDOWNSLASH12_RELEASE_OFFSET_SECONDS宣言のコメント参照)。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — releaseがframe8→
## frame7へ変わったことでRELEASE_OFFSET_SECONDS自体が0.25→0.13へ変更
## されたため、この式の値も自動的に3.70→3.58(=3.45+0.13)へ再カスケード
## される(この定数自体は式もコメントも無改修——上流の1箇所を直すだけで
## 正しく追従する、既存の単一derived-const-chain設計そのもの)。
const EOS_BURST_SLASH_START_SECONDS := \
	EOS_BURST_THRUST_LUNGE_START_SECONDS + EOS_BURST_DOWNSLASH12_RELEASE_OFFSET_SECONDS  ## 3.58
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — README「開始前に1回
## だけ`travel_duration = clamp(distance/733.333333, 0.50, 0.62)`を計算」
## ——v17までの固定0.78秒を廃止し、実際の開始点/到達点の距離から動的に
## 導出する式へ変更。ただしこのゲームの戦闘画面は常に固定サイズ
## (`UD.NORMAL_WINDOW_SIZE`=1152×648、CLAUDE.md「中央管理ウィンドウ」)
## であり、敵アイコンの画面位置(`BOSS_CENTER_X_FRAC`基準)もソティリスの
## 陣形位置も対戦相手によらず常に同じ値を返すため、この式の結果は実際
## には全戦闘を通じて完全に一定——このファイルの他の全ての絶対時刻定数と
## 同じ「単一derived-const-chain」設計を維持できる。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — 主斬撃の絵・
## scale・水平lane・敵中心停止のロジック自体は無改修(README「変更しま
## せん」)。速度・clamp範囲だけを参照実装の新値へ更新——
## `MAIN_TRAVEL_SPEED_PX_PER_SEC`733.333333→700.0、`MAIN_MIN_CONTACT_
## HOLD_SECONDS`0.04→0.12(BUILD(0.46)+HOLD(0.12)=0.58、参照実装の
## `MAIN_MIN_DURATION := 0.580`と一致)、`MAIN_MAX_DURATION_SECONDS`
## 0.62→0.70。
const EOS_BURST_MAIN_TRAVEL_SPEED_PX_PER_SEC := 700.0
const EOS_BURST_MAIN_MIN_CONTACT_HOLD_SECONDS := 0.12
const EOS_BURST_MAIN_MIN_DURATION_SECONDS := \
	EOS_BURST_MAIN_BUILD_SECONDS + EOS_BURST_MAIN_MIN_CONTACT_HOLD_SECONDS  ## 0.58
const EOS_BURST_MAIN_MAX_DURATION_SECONDS := 0.70
## headlessで`_eos_burst_slash_travel_duration()`(実際の本番ジオメトリ
## 関数、描画位置の計算にも使う本物のランタイム関数)を実行し、実測した
## 距離149px(start_x=575→target_x=724、この戦闘画面の陣形/敵アイコン
## 位置から)を速度733.333px/sで割ると0.2032秒——MIN_DURATION_SECONDS
## (0.50)の床に確実にクランプされる(距離149pxはMIN_DURATION*speed=
## 366.67pxを大きく下回るため、今後この2つの位置定数が多少変わっても
## クランプが外れることはまず無い)。したがって「measure once, bake as
## const」ではなく、クランプ結果と数式的に同一であることが保証された
## `EOS_BURST_MAIN_MIN_DURATION_SECONDS`そのものを直接使う——パックの
## 1152×648確認値(0.500秒)の転記ではなく、この実装自身の関数を実際に
## 実行して得た値と定数チェーンの両方が同じ0.50に帰着することをheadless
## 検証で直接確認する。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — start_x/
## target_x自体は無改修のため距離149pxも不変、新速度700px/sで0.213秒
## (=速度換算)——新MIN_DURATION_SECONDS(0.58)の床に確実にクランプ
## される(距離149pxはMIN*speed=406pxを大きく下回る)。パックの1152×648
## 確認値もこの新床(0.580秒)と一致することを確認済み。
const EOS_BURST_SLASH_DURATION_SECONDS := EOS_BURST_MAIN_MIN_DURATION_SECONDS  ## 0.58
const EOS_BURST_SLASH_END_SECONDS := \
	EOS_BURST_SLASH_START_SECONDS + EOS_BURST_SLASH_DURATION_SECONDS
## README「start_center_x = round(sotiris_ground_x + 96)を初期値とし、
## 現在の人物サイズに合わせて開始前に一度だけ調整」——今回は具体的な
## 加算値96自体がプロンプトから直接与えられている(v13/v14のような判断値
## ではない)。
const EOS_BURST_SLASH_START_CENTER_OFFSET_PX := 96.0
## README「frozen_lane_y = round(sotiris_ground_y - 48)」——v13で最初に
## 採用していた式(旧`_eos_burst_horizontal_slash_lane_y`)と同じ形——v14で
## 一度sword-tipのYへ変更していたが、今回プロンプトが明示的にこの式を
## 与えたため、より確実な出典のあるこちらへ戻した(判断値ではなく指定値)。
const EOS_BURST_SLASH_LANE_Y_OFFSET_PX := -48.0
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — README「開始と
## 終了の各10%だけ`_edge_smoothed_linear`を使い、中央80%はscalar
## Linearです」——参照実装の`_edge_smoothed_linear`(C1連続、区間境界の
## 各10%だけ2次のease-in/outを掛け、中央80%は素のLinearのまま)を移植。
const EOS_BURST_MAIN_EDGE_EASE_RATIO := 0.100
## README「slash→impact重複0.060秒」——接触(grand_08 alpha1.0)から
## この秒数だけ、斬撃自身がalpha1→0でフェードしながら着弾(alpha0.08→
## 1.00)と同時に描画され続ける、旧v18の「即0/1描画フレームで消える」を
## 撤廃。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「着弾
## 12枚...斬撃末尾と0.080秒重ねます」——0.060→0.080。
const EOS_BURST_SLASH_TO_IMPACT_OVERLAP_SECONDS := 0.080

## README「旧変数名(start_tip_x/target_tip_x)を残さないでください」——
## 「開始X/到達Xは見た目中心として渡す」という意味の変更に合わせ、
## center命名へ全面リネーム。"1回だけ"の凍結は、常にEOS_BURST_SLASH_
## START_SECONDSという固定時刻でSotiris自身の足元を評価することで表現
## する(v13から継続する「elapsed固定で凍結する」イディオム)。
func _eos_burst_slash_start_center_x(view: Rect2, unit_id: int) -> float:
	return roundf(
		_eos_burst_sotiris_live_feet(view, unit_id, EOS_BURST_SLASH_START_SECONDS).x
			+ EOS_BURST_SLASH_START_CENTER_OFFSET_PX)


## 「CLEAN_HOLD_EXTENDED_REACH v17」(2026-08-15) — README「到達点を敵
## グループ右端＋112pxへ延長」——旧`_boss_icon_rect(view).get_center().x`
## (敵中心)から、`max(enemy_right+112, start+480)`をviewport幅+96pxで
## 上限クランプする式へ全面差し替えた(v17時点の説明)。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — 「斬撃が敵へ接触した
## 後も右へ進み、敵を通り過ぎてから着弾している」——v17の延長仕様
## (`enemy_right+112`/`TARGET_OVERSHOOT_PX`/`MIN_TRAVEL_DISTANCE_PX`/
## `TARGET_VIEWPORT_MARGIN_PX`/確認値1092)を全て削除し、「grand_08の
## 先端(source右端x736、pivotからの差198.735px)が敵グループ中心へ
## ちょうど触れる位置でMotionAnchorを止める」式へ全面差し替えた——
## `target_anchor_x = round(enemy_center.x - tip_offset)`。MotionAnchor
## 自体を敵中心へ置くと(=tip_offsetを引かないと)大きな斬撃本体が敵を
## 通過して見えるため禁止(README「MotionAnchor自体を敵中心へ置くと
## 大きな斬撃が再び敵を通過して見えるため禁止」)——先端が中心に届いた
## 瞬間、MotionAnchor自体(=pivotの位置)は敵中心よりtip_offset分手前に
## 留まる設計。`start_center_x`への依存が無くなったためパラメータから
## 削除(v17は`start+480`の最低移動距離チェックのため必要だったが、v18
## の最低距離保証は下記`_eos_burst_slash_travel_duration`のMIN_DURATION
## クランプへ役割が移った)。「斬撃再生中に敵位置から再計算しない」は、
## 敵アイコンの位置がこのゲームでは戦闘全体を通じ不変であるため、この
## 関数を毎フレーム呼び直しても結果が数式的に不変であることで満たす
## (v17から継続する「elapsed非依存でも実質不変」の理屈、headless実測で
## 再確認する)。
func _eos_burst_slash_target_center_x(view: Rect2) -> float:
	var tip_offset := EOS_BURST_MAIN_FRAME08_TIP_OFFSET_SOURCE_X * EOS_BURST_SLASH_FIXED_SCALE
	return roundf(_boss_icon_rect(view).get_center().x - tip_offset)


## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — README「開始前に1回
## だけ`travel_duration = clamp(distance/733.333333, 0.50, 0.62)`を計算」
## ——移動距離(開始点から敵接触停止点まで)を実測の水平速度で割り、
## 「build(0.46秒)を必ず収める最低秒数」〜「読みやすさの上限」でクランプ
## する。この関数自体は`start_center_x`/`target_center_x`という、既に
## 「elapsed固定で凍結・戦闘中不変」な2つの値だけから導出するため、
## 結果もまた戦闘中不変(headless実測で確認する)——`EOS_BURST_SLASH_
## DURATION_SECONDS`定数は、この関数を実際に1回呼び出して得た値をその
## まま焼き込んだもの(パックの1152×648確認値0.500秒の転記ではなく、
## この実装自身のジオメトリ関数から得た実測値)。
func _eos_burst_slash_travel_duration(view: Rect2, unit_id: int) -> float:
	var start_x := _eos_burst_slash_start_center_x(view, unit_id)
	var target_x := _eos_burst_slash_target_center_x(view)
	var distance := target_x - start_x
	var speed_duration := distance / EOS_BURST_MAIN_TRAVEL_SPEED_PX_PER_SEC
	return clampf(
		speed_duration, EOS_BURST_MAIN_MIN_DURATION_SECONDS, EOS_BURST_MAIN_MAX_DURATION_SECONDS)


func _eos_burst_slash_lane_y(view: Rect2, unit_id: int) -> float:
	return roundf(
		_eos_burst_sotiris_live_feet(view, unit_id, EOS_BURST_SLASH_START_SECONDS).y
			+ EOS_BURST_SLASH_LANE_Y_OFFSET_PX)


## 「CONTACT_SYNC_STOP_ON_ENEMY v18」の接触window(SLASH_START..SLASH_END)
## に加え、「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) —
## 「slash→impact重複0.060秒」のため、接触後もこの秒数だけ描画を継続
## する(この間、`_draw_eos_burst_slash`は接触フレーム=grand_08を
## alpha1→0でフェードしながら描き続ける)。
func _eos_burst_slash_active(elapsed: float) -> bool:
	return elapsed >= EOS_BURST_SLASH_START_SECONDS \
		and elapsed < EOS_BURST_SLASH_END_SECONDS + EOS_BURST_SLASH_TO_IMPACT_OVERLAP_SECONDS


## README「Xは...TRANS_LINEARで移動」——参照実装`play_restored_grand_
## slash`のprogress計算(`elapsed/MAIN_TOTAL_DURATION`、イージングなし)と
## 数式的に同一。`_eos_burst_smooth_elapsed`(既存の連続時計、tick境界に
## 縛られず実フレームレートで進む)を分子にすることで60fps相当の滑らかさ
## を維持する(v13から継続する既存手法)。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — README「開始と
## 終了の各10%だけ`_edge_smoothed_linear`を使い、中央80%はscalar
## Linear」——`lerpf`へ渡す進行度を素のtから`_eos_burst_edge_smoothed_
## linear(t)`へ差し替えた。「Timerや整数座標の段階更新にせず毎process_
## frameのfloatで更新」——`roundf()`をここでは呼ばない(最終的なピクセル
## スナップは`_draw_eos_burst_slash`側の`top_left...round()`が描画直前に
## 1回だけ行う、既存パターンのまま)。
func _eos_burst_slash_center_x(elapsed: float, start_center_x: float, target_center_x: float) -> float:
	var t := clampf(
		(_eos_burst_smooth_elapsed(elapsed) - EOS_BURST_SLASH_START_SECONDS)
			/ EOS_BURST_SLASH_DURATION_SECONDS,
		0.0, 1.0)
	return lerpf(start_center_x, target_center_x, _eos_burst_edge_smoothed_linear(t))


## README「MotionAnchor.global_positionのXだけをTween.TRANS_LINEARで
## 移動」——Mainは1つの`anchor`(共有MotionAnchor相当)を読む。
## 「SlashMotionAnchorをソティリス、剣、CharacterBody2D、移動中の
## AnimationRootの子にしない」——このファイルは実ノード階層自体を持たず
## (単一の同期`_draw()`ディスパッチ)、`anchor`は毎回このスコープ内で
## Sotiris自身の生きたtransformを一切参照せずゼロから計算されるため、
## 継承・reparentという概念そのものが構造的に発生し得ない。「斬撃終了
## フレームでSpriteをtexture=null、visible=falseにする」は、`_eos_burst_
## slash_active`が窓外で即returnすること(=このファイル全体の全VFXが
## 共有する既定のidiom)で満たす。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — Echo(twin_shockwave)の
## 呼び出しを完全に削除した。Mainだけを描画する——「右斜め下の細い線」
## はこのEcho呼び出し自体が無くなったことで構造的に0回になる。
## 「CLEAN_HOLD_EXTENDED_REACH v17」(2026-08-15) — 参照実装`_apply_clean_
## main_time`と同じ「build(7遷移、全区間Smootherstep)→hold(0.27秒、
## grand_08をalpha1.00固定)→fade(0.05秒、grand_08だけSmootherstepで
## alpha→0)」構造を、このfunctionへ直接インライン実装した(idx_a/idx_bを
## この関数内で決め、`_eos_burst_main_active_texture`経由で禁止コマを
## 一切要求しない)。旧`_draw_eos_burst_slash_layer`(汎用`_eos_burst_
## frame_crossfade_pair`頼み、最終コマは自分の持ち時間で即座にフェード
## を開始する設計)ではholdという「一定時間フルアルファのまま静止する」
## 区間を表現できないため丸ごと削除し、そのcurve引数を埋めるためだけの
## 補助`_eos_burst_flat_curve`も呼び出し元が無くなり完全に削除した
## (`_eos_burst_frame_crossfade_pair`自体は爆発が今も使用中のため無改修
## のまま維持)。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-15) — README「grand_08は
## 接触までalpha1.00。接触前FadeOutは禁止」——v17のhold/fadeの2段階を
## 「build完了後は接触まで単純にalpha1.00のまま」の1段階へ簡略化した。
## `EOS_BURST_MAIN_SECONDS`/`_HOLD_END_SECONDS`/`_FADE_SECONDS`(いずれも
## 固定0.78秒前提の定数)への参照を削除し、動的な`EOS_BURST_SLASH_
## DURATION_SECONDS`(=`travel_duration`)を直接使う。`target_center_x`
## は`start_center_x`への依存が無くなったため引数を1つ減らした(v17の
## `start+480`最低距離ガードはtravel_duration自身のMIN_DURATIONクランプ
## へ移管済み)。
func _draw_eos_burst_slash(view: Rect2, unit_id: int, elapsed: float) -> void:
	if not _eos_burst_slash_active(elapsed):
		return
	var start_center_x := _eos_burst_slash_start_center_x(view, unit_id)
	var target_center_x := _eos_burst_slash_target_center_x(view)
	var lane_y := _eos_burst_slash_lane_y(view, unit_id)
	var center_x := _eos_burst_slash_center_x(elapsed, start_center_x, target_center_x)
	var anchor := Vector2(center_x, lane_y)
	var local_time := elapsed - EOS_BURST_SLASH_START_SECONDS
	if local_time < 0.0:
		return
	var idx_a := -1
	var idx_b := -1
	var alpha_a := 0.0
	var alpha_b := 0.0
	if local_time < EOS_BURST_MAIN_BUILD_SECONDS:
		var cursor := 0.0
		for i in EOS_BURST_MAIN_BUILD_DURATIONS.size():
			var interval: float = EOS_BURST_MAIN_BUILD_DURATIONS[i]
			if local_time < cursor + interval:
				var t := clampf((local_time - cursor) / maxf(0.0001, interval), 0.0, 1.0)
				var mix := _eos_burst_ease_smootherstep(t)
				idx_a = i
				idx_b = i + 1
				alpha_a = EOS_BURST_MAIN_MAX_ALPHA * (1.0 - mix)
				alpha_b = EOS_BURST_MAIN_MAX_ALPHA * mix
				break
			cursor += interval
	elif local_time < EOS_BURST_SLASH_DURATION_SECONDS:
		## Clean full crescent (grand_08, array index 7) stays visible at full
		## alpha for the contact-hold window (TIMELINE_V19「grand08 full
		## alpha hold, enemy center contact, 通過なし」) — no pre-impact
		## fade during this stretch.
		idx_a = EOS_BURST_MAIN_FRAME_COUNT - 1
		alpha_a = EOS_BURST_MAIN_MAX_ALPHA
	elif local_time < EOS_BURST_SLASH_DURATION_SECONDS + EOS_BURST_SLASH_TO_IMPACT_OVERLAP_SECONDS:
		## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) —
		## README「接触したgrand08を一描画フレーム見せた後、Mainを即
		## clearせず、crossflash00と0.060秒重ねてSmootherstepで渡して
		## ください」。参照実装`play_impact_with_overlaps`の
		## `slash_alpha = 1 - smootherstep(elapsed/SLASH_TO_IMPACT_
		## OVERLAP)`と同じ「接触からの経過時間」を分子に、grand_08の
		## alphaをMAX→0へ滑らかに落とす——同じ窓の間、Impact側
		## (`_draw_eos_burst_enemy_crossflash`)は0.08→1.0へ立ち上がる
		## ため、両者が重なって描かれ「1描画フレームで置き換わる」
		## ポップが消える。
		var fade_t := (local_time - EOS_BURST_SLASH_DURATION_SECONDS) \
			/ EOS_BURST_SLASH_TO_IMPACT_OVERLAP_SECONDS
		idx_a = EOS_BURST_MAIN_FRAME_COUNT - 1
		alpha_a = EOS_BURST_MAIN_MAX_ALPHA * (1.0 - _eos_burst_ease_smootherstep(clampf(fade_t, 0.0, 1.0)))
	else:
		return
	var draw_size := EOS_BURST_MAIN_FRAME_SIZE * EOS_BURST_SLASH_FIXED_SCALE
	if idx_a >= 0 and alpha_a > 0.0:
		var tex_a := _eos_burst_main_active_texture(idx_a)
		if tex_a != null:
			var top_left_a := (anchor - EOS_BURST_MAIN_PIVOTS[idx_a] * EOS_BURST_SLASH_FIXED_SCALE).round()
			draw_texture_rect(tex_a, Rect2(top_left_a, draw_size), false, Color(1.0, 1.0, 1.0, alpha_a))
	if idx_b >= 0 and alpha_b > 0.0:
		var tex_b := _eos_burst_main_active_texture(idx_b)
		if tex_b != null:
			var top_left_b := (anchor - EOS_BURST_MAIN_PIVOTS[idx_b] * EOS_BURST_SLASH_FIXED_SCALE).round()
			draw_texture_rect(tex_b, Rect2(top_left_b, draw_size), false, Color(1.0, 1.0, 1.0, alpha_b))


## --- EnemyCrossFlash(`frames/enemy_crossflash_v8/crossflash_00..11.png`、384×256×12) ---
## v10: 絵はv8と同一(README「v8と同一のためパスのみ切替」)、サイズ・
## タイミングとも無改修——DIRのパス文字列だけをv10コピー先へ更新。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 絵は無改修のまま
## (「維持するもの」に明示、SHA256一致確認済み)パスだけv12コピー先へ
## 切替。TIMELINE_V12.csv「4.70,5.08,0.38,敵側X交差閃光を着弾から爆発へ
## 重ねる」——START_SECONDSを4.74→4.70、FRAME_DURATIONS/SECONDSを
## FRAME_TIMES_V12.tsvの`enemy_crossflash_v8`行(合計0.38秒)へ更新。
## 「NEW_AURA_HORIZONTAL_HIT_BURST v13」(2026-08-14) — 絵は無改修(ASSET_
## MANIFEST_V13.tsv「unchanged art」)、パスだけv13コピー先へ切替。
## TIMELINE_V13.csv「4.74,4.98,0.24,impact」+CLAUDE_CODE_PROMPT_JA.txt
## 「時間[0.02,0.02,0.02,0.02,0.025,0.025,0.025,0.025,0.02,0.015,0.015,
## 0.01]、合計0.24秒」——水平斬撃の到達(4.74=新HIT_AT)と完全に同時に
## 開始するよう再retiming(旧v12の4.70/合計0.38秒から変更)。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — 絵・時間表は
## 無改修(README「着弾閃光: crossflash_00..11.png...時間[同じ配列]、
## 合計0.24秒」——v13と完全同一の値)。パスだけv14コピー先へ切替、開始
## 時刻を復元した大斬撃の到達時刻(4.78=新HIT_AT)へ再一致させる。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — 絵・時間表は無
## 改修(README「v14から変更しないもの: 着弾閃光12枚と0.24秒」)。パスだけ
## v15コピー先へ切替、開始時刻を高速化した大斬撃の新到達時刻(4.70=新
## HIT_AT)へ再一致させる。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 絵・時間表は無改修
## (CHANGE_MAP_V15_TO_V16.tsv「impact: 0.24 sec: unchanged」)。パスだけ
## v16コピー先へ切替、開始時刻を斬撃開始のframe8同期に伴う新到達時刻
## (4.48=新HIT_AT)へ再一致させる。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-16) — 絵・時間表は無改修
## (「維持するもの: 着弾閃光12枚・0.24秒」)。パスも無改修(v16コピー先を
## 引き続き参照)、開始時刻だけをrelease-frame変更(frame8→frame7)+
## 距離ベースduration計算に伴う新HIT_AT(4.08)へ再一致させる。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — README「着弾は
## process-frameクロスフェード、直接swapではありません」——旧・1枚ずつの
## 瞬時差し替え(`_eos_burst_frame_index_from_table`単独)を撤回し、Main/
## Outerと同じ`_eos_burst_frame_crossfade_pair()`(既存の汎用ヘルパー、
## 全区間Smootherstep+最終コマQuad EaseOut)によるA/Bブレンドへ全面差し替え。
## 参照実装`IMPACT_FRAME_TIMES`(合計0.320秒、旧0.240秒から拡張——README
## 「12枚全部が読める補間を受け取れるよう、旧v18の固い0.24秒より少し
## 長くする」)をそのまま採用。開始時刻も従来の手打ちリテラルから
## `EOS_BURST_HIT_AT_SECONDS`への直接参照へ変更(参照実装`play_impact_
## with_overlaps`が斬撃接触の直後の同一描画フレームでimpactを起動する
## のと同じ設計、値自体は既存のSLASH_END=HIT_ATと従来通り一致)。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 絵は無改修
## (PRESERVED_ASSET_SHA256_V19.tsvで12枚全てv16と同一と確認済み)、パス
## だけv19コピー先へ切替(A/Bブレンド化・entry-alphaランプの追加はコード
## 側のみの変更)。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — 絵は無改修
## (PRESERVED_ASSET_SHA256_V20.tsvでv19と同一12ファイルであることを確認済み)、
## パスだけv20コピー先へ切替。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — Impact定数・PNGは
## 変更禁止対象、LOCKED_FINISH_SHA256_V22.tsvで12/12ファイルがv21と完全
## 一致することを確認済み、パスだけv22コピー先へ切替。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — Impact
## 定数・PNGは変更禁止対象、LOCKED_FINISH_SHA256_V25.tsvで12/12ファイルが
## v22と完全一致することを確認済み、パスだけv25コピー先へ切替。
const EOS_BURST_ENEMY_CROSSFLASH_DIR := "res://assets/vfx/eos_burst/v25/frames/enemy_crossflash_v8/crossflash_"
const EOS_BURST_ENEMY_CROSSFLASH_FRAME_COUNT := 12
const EOS_BURST_ENEMY_CROSSFLASH_CELL_SIZE := Vector2(384.0, 256.0)
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「着弾
## 12枚の時間: [0.030,0.030,0.033,0.033,0.035,0.038,0.040,0.040,0.038,
## 0.033,0.027,0.023] 合計0.400秒」——絵は無改修、時間だけ更新。
const EOS_BURST_ENEMY_CROSSFLASH_FRAME_DURATIONS: Array[float] = [
	0.030, 0.030, 0.033, 0.033, 0.035, 0.038, 0.040, 0.040, 0.038, 0.033, 0.027, 0.023,
]
const EOS_BURST_ENEMY_CROSSFLASH_SECONDS := 0.400  ## sum of the above
const EOS_BURST_ENEMY_CROSSFLASH_START_SECONDS := EOS_BURST_HIT_AT_SECONDS
## 参照実装`_apply_impact_time`のopacityは全12コマ均一(1.0)——Outerと
## 違い個別のalphaカーブを持たない、時間変動する要素は下の
## `ENTRY_MIN_ALPHA`ランプだけ。
const EOS_BURST_ENEMY_CROSSFLASH_ALPHA_CURVE: Array[float] = [
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
]
## README「slash→impact重複0.060秒、impactのalphaは0.08→1.00へ立ち上がる、
## 1描画フレームでの置き換わりを消す」——参照実装`impact_entry_alpha :=
## lerp(IMPACT_ENTRY_MIN_ALPHA, 1.0, smootherstep(impact自身のage /
## SLASH_TO_IMPACT_OVERLAP))`と同数式。斬撃側の`_eos_burst_slash_active`
## フェード尾(`EOS_BURST_SLASH_TO_IMPACT_OVERLAP_SECONDS`、同じ0.060秒)
## と同じ窓の間、両者が同時に描かれることでポップを消す。
const EOS_BURST_ENEMY_CROSSFLASH_ENTRY_MIN_ALPHA := 0.080

## 「敵グループ全体のground bounds中心に固定し、移動させません」——下記の
## `_draw_eos_burst_massive_burst`と同じbottom-center anchoring(ground点
## から上方向へ矩形を伸ばす)を使い、GrandCrescent/TwinShockwaveが実際に
## 到達する`_eos_burst_enemy_ground_anchor`と同じ基準点に揃える(斬撃の
## 着地点とX閃光の中心がズレて見えないように)。位置・回転とも今回の
## 3点修正の対象外(独立した停止表示のため軌道の傾き問題は元々発生し
## 得ない)——素材の差し替えのみ。
func _eos_burst_enemy_crossflash_active(elapsed: float) -> bool:
	var age := elapsed - EOS_BURST_ENEMY_CROSSFLASH_START_SECONDS
	return age >= 0.0 and age < EOS_BURST_ENEMY_CROSSFLASH_SECONDS


func _draw_eos_burst_enemy_crossflash(view: Rect2, elapsed: float) -> void:
	if not _eos_burst_enemy_crossflash_active(elapsed):
		return
	var smooth_age := _eos_burst_smooth_elapsed(elapsed) - EOS_BURST_ENEMY_CROSSFLASH_START_SECONDS
	var pair := _eos_burst_frame_crossfade_pair(
		smooth_age, EOS_BURST_ENEMY_CROSSFLASH_FRAME_DURATIONS, EOS_BURST_ENEMY_CROSSFLASH_ALPHA_CURVE)
	var entry_mult := lerpf(
		EOS_BURST_ENEMY_CROSSFLASH_ENTRY_MIN_ALPHA, 1.0,
		_eos_burst_ease_smootherstep(clampf(smooth_age / EOS_BURST_SLASH_TO_IMPACT_OVERLAP_SECONDS, 0.0, 1.0)))
	var ground := _eos_burst_enemy_ground_anchor(view)
	var size := EOS_BURST_ENEMY_CROSSFLASH_CELL_SIZE
	var top_left := (ground - Vector2(size.x * 0.5, size.y)).round()
	var idx_a: int = pair[0]
	var idx_b: int = pair[1]
	var alpha_a: float = pair[2] * entry_mult
	var alpha_b: float = pair[3] * entry_mult
	if idx_a >= 0 and alpha_a > 0.0:
		var tex_a := _eos_burst_indexed_frame_texture(EOS_BURST_ENEMY_CROSSFLASH_DIR, idx_a)
		if tex_a != null:
			draw_texture_rect(tex_a, Rect2(top_left, size), false, Color(1, 1, 1, alpha_a))
	if idx_b >= 0 and alpha_b > 0.0:
		var tex_b := _eos_burst_indexed_frame_texture(EOS_BURST_ENEMY_CROSSFLASH_DIR, idx_b)
		if tex_b != null:
			draw_texture_rect(tex_b, Rect2(top_left, size), false, Color(1, 1, 1, alpha_b))


## === 外周+白熱核 2レイヤー爆発(`frames/burst_outer_v8_clean/outer_00..11.png`
## + `frames/burst_core_v8/core_00..11.png`、384×384×12、独立PNG・A/B
## クロスフェード) ===
## 「V8_ART_LEVEL_PATH_SMOOTH_BURST v10」(2026-08-13) — README「v9の
## 縦へ膨らむ一体型爆発は採用しません。見た目はv8の外周+白熱核2レイヤー
## へ戻します。ただしv8実装にあったコマ境界のカクつき(隣コマの断片が
## 右端に見える)は戻さず修正してください」。v8の元絵は横長シートの
## `draw_texture_rect_region`スライスだったため隣接コマの発光が漏れる
## リスクを構造的に抱えていた(v9で特定・修正済みの原因)——v10は
## 「絵はv8」「切り出し方式はv9で確立した独立PNG方式のまま」という
## ハイブリッドで両立させる。同梱の`burst_outer_v8_clean`は、v8の元
## シートから連結成分解析で各コマ自身の中心へ属する部分だけを抽出し
## (`CLEANING_REPORT_V10.tsv`で全12コマの境界漏れピクセルが0であること
## を確認済み)、色・線・グロー・シルエットはv8のまま・新しい絵は一切
## 生成していない(README「色、線、光、シルエットはv8元絵を使用」)。
## `burst_core_v8`はv8と完全に同一(再クロップなし)。region/AtlasTexture/
## hframes/vframesは一切使わず(v9から継続)、`draw_texture_rect`のみで
## 1枚ずつ描く——「隣コマが露出する経路そのものをなくす」設計は無改修。
##
## 新要件: outer/coreの各12コマをA/Bの2バッファでクロスフェードする
## (README・参照実装`godot/eos_burst_v10_reference.gd`の`play_smooth_
## v8_burst()`)。このプロジェクトは単一の`_draw()`ディスパッチで実
## Sprite2Dノード・Tweenを持たないため、「2つの永続バッファが時間と共に
## active/inactiveの役割を交代する」という参照実装のノード常駐state
## machineを、`elapsed`だけから毎描画フレーム計算し直す純関数として
## 再実装した——`_eos_burst_massive_burst_crossfade_pair()`が返す
## (from_idx, to_idx, alpha_from, alpha_to)を**outer/coreの両方が
## 同じ1回の呼び出しから受け取る**ことで、「outerとcoreは常に同じ
## フレーム番号・同じクロスフェード進捗を共有する」という要件を、
## 2つの独立した状態ではなく単一の共有計算結果として構造的に保証する
## (数値がズレる経路自体が存在しない)。クロスフェード秒数は参照実装と
## 同じ`min(0.035, 現在フレームの表示時間*0.45)`、イージングは
## `Tween.TRANS_SINE/EASE_IN_OUT`と数式的に同一の
## `_eos_burst_ease_sine_in_out()`——「クロスフェード中に見えるのは
## 常に隣接する2コマだけ」は、このpair関数がfrom/toとして隣接インデックス
## (i, i+1)以外を返す経路を持たないことで保証される。
## 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — README「爆発12コマ
## も各コマ時間全体で連続補間。合計を1.05秒から1.20秒へ延長」「白熱核は
## 専用alphaカーブで最大0.58に抑え、突然大きな白丸へ切り替わる見え方を
## 修正」。絵自体(`burst_outer_v8_clean`/`burst_core_v8`)はv11から無改修
## のピクセル(SHA256一致確認済み)——パスだけをv12コピー先へ切り替える。
## クロスフェード機構は#101で新設した汎用`_eos_burst_frame_crossfade_
## pair()`(全区間Smootherstep+最終コマQuad EaseOut)へ統一し、旧・末尾
## 35msクロスフェード専用の`_eos_burst_massive_burst_crossfade_pair()`
## (+`EOS_BURST_MASSIVE_CROSSFADE_MAX_SECONDS`)は完全に削除した。
## 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — README「爆発の
## 後半に白っぽい円形物が残ります。原因は独立した白い楕円核レイヤーと、
## 爆発外周の`outer_08.png`に含まれる白い円盤です。両方をactive演出から
## 完全に外してください」。旧・白熱核レイヤー(`EOS_BURST_MASSIVE_CORE_
## DIR`/`_CORE_ALPHA_CURVE`/`EOS_BURST_CORE_SCALE_RATIO`、core_a/core_bの
## 描画一式)を完全に削除し、爆発は`BurstAnchor/OuterA`+`OuterB`の2枚だけ
## になった。素材も`outer_08.png`を含まない11枚(`burst_outer_v14_no_
## white_disc/outer_00..07,09..11.png`)へ差し替え——ASSET_MANIFEST_V14
## .tsvが明示する「00..07 and 09..11; image pixels unchanged」どおり、
## 残る11枚のピクセル自体は無加工。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — README「v14から
## 変更しないもの: 白い円形物を除去した外周爆発11枚と1.20秒」——絵・時間
## 表とも無改修、パスだけv15コピー先へ切替。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 絵・時間表は無改修
## (CHANGE_MAP_V15_TO_V16.tsv「outer_burst: 1.20 sec outer-only:
## unchanged」)。パスだけv16コピー先へ切替。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 絵は無改修
## (PRESERVED_ASSET_SHA256_V19.tsvで11枚全てv16と同一と確認済み)、パス
## だけv19コピー先へ切替(開始時刻をImpact末尾との0.100秒重複から導出+
## entry-alphaランプの追加はコード側のみの変更)。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — 絵は無改修
## (PRESERVED_ASSET_SHA256_V20.tsvでv19と同一11ファイルであることを確認済み)、
## パスだけv20コピー先へ切替。
## 「EXTENDED_CHARGE_LOCKED_FINISH v22」(2026-08-17) — Outer定数・PNGは
## 変更禁止対象、LOCKED_FINISH_SHA256_V22.tsvで11/11ファイルがv21と完全
## 一致することを確認済み、パスだけv22コピー先へ切替。
## 「CURRENT_SOTIRIS_SCALE_PIXEL_LOCKED_FINISH v25」(2026-08-18) — Outer
## 定数・PNGは変更禁止対象、LOCKED_FINISH_SHA256_V25.tsvで11/11ファイルが
## v22と完全一致することを確認済み、パスだけv25コピー先へ切替。
const EOS_BURST_MASSIVE_OUTER_DIR := "res://assets/vfx/eos_burst/v25/frames/burst_outer_v15_no_white_disc/outer_"
const EOS_BURST_MASSIVE_FRAME_COUNT := 11
## v8オリジナルの384×384から無改修。
const EOS_BURST_MASSIVE_FRAME_SIZE := Vector2(384.0, 384.0)
## README「配置先が`outer_08.png`を含まない11枚のため、配列の位置
## (0始まり)と実際のファイル番号(00,01..07,09,10,11)がindex7以降で
## ズレる」——`_eos_burst_indexed_frame_texture`は"%02d"でファイル名を
## 組み立てる汎用ヘルパーのため、配列位置をそのまま渡すとindex8が
## 存在しない`outer_08.png`を要求してしまう。この対応表で配列位置→実
## ファイル番号を明示的に変換する。
const EOS_BURST_MASSIVE_OUTER_FRAME_NUMBERS: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 9, 10, 11]
## FRAME_TIMES_V14.tsvの`outer`行(11コマ、合計1.20秒)——07→09の遷移だけ
## 0.18秒(README「07→09は0.18秒で補間。08を飛ばした境界を瞬間切替に
## しない」)。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「外周
## 爆発11枚の時間: [0.075,0.0875,0.100,0.1125,0.1375,0.150,0.175,0.225,
## 0.175,0.1375,0.125] 合計1.500秒」——絵は無改修(outer_08抜き11枚の
## まま)、時間だけ更新。
const EOS_BURST_MASSIVE_FRAME_DURATIONS: Array[float] = [
	0.075, 0.0875, 0.100, 0.1125, 0.1375, 0.150, 0.175, 0.225, 0.175, 0.1375, 0.125,
]
const EOS_BURST_MASSIVE_SECONDS := 1.500  ## sum of the above
## TIMELINE_V14.csv「5.02,6.22,1.20,burst,白い核と円盤なしの外周爆発」
## ——着弾閃光(4.78〜5.02)が完全に終わった直後から開始、EnemyCrossFlashの
## END_SECONDS(4.78+0.24=5.02)とちょうど一致することをheadlessで確認済み
## ——これが「travel→impact→burst」を並列Tweenや同一トラックではなく
## 非重複の絶対時刻窓だけで排他化する、この巨大ファイル全体の確立済み
## 手法そのもの。
## 「FAST_CENTROID_LOCKED_HORIZONTAL v15」(2026-08-14) — TIMELINE_V15.csv
## 「4.94,6.14,1.20,burst」——大斬撃の高速化(HIT_AT 4.78→4.70)に伴い
## EnemyCrossFlash終了時刻も4.70+0.24=4.94へ前倒しされたため、それに
## 一致するよう5.02→4.94へ更新。
## 「RELEASE_SYNC_NO_ECHO v16」(2026-08-15) — 斬撃開始をframe8の実際の
## 絶対時刻へ同期したことでHIT_AT(=新斬撃終了)が4.48へ前倒しされ、
## EnemyCrossFlash終了時刻も4.48+0.24=4.72へ前倒しされたため、それに
## 一致するよう4.94→4.72へ更新。
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-16) — release-frame変更
## (frame8→frame7)+距離ベースduration計算により新HIT_AT=4.08、新
## EnemyCrossFlash終了時刻=4.08+0.24=4.32へ前倒しされたため4.72→4.32へ
## 更新。
## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — README「impact
## →outer重複0.100秒。impactが終わる前にouterが薄く始まる」——参照実装
## `outer_start_time := impact_duration - IMPACT_TO_OUTER_OVERLAP`(impact
## 自身の"local"時計基準)と同じ関係を、このファイルの「絶対時刻の連結
## チェーン」設計へそのまま翻訳: `MASSIVE_START := ENEMY_CROSSFLASH_START
## + ENEMY_CROSSFLASH_SECONDS - IMPACT_TO_OUTER_OVERLAP`。手打ちリテラル
## から派生式へ変更したことで、以後EnemyCrossFlashの開始/尺が変わっても
## Outerの開始が自動的に追従する(この巨大ファイル全体の「単一derived
## const-chain」規律への統一)。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「外周爆発は接触から0.120秒後にawaitなしで開始してください。Impactは
## 接触から0.320秒まで続くため、ImpactとOuterが0.200秒重なります」——
## 参照実装`play_v20_eos_burst`は`outer_start_time := OUTER_START_AFTER_
## CONTACT`(定数、接触基準の直接値)を主定義とし、重複幅は
## `assert(is_equal_approx(impact_duration - outer_start_time,
## IMPACT_TO_OUTER_OVERLAP))`という**導出された確認**として扱っている
## (v19の「重複幅を主定義にしてMASSIVE_STARTを逆算する」設計と主従が
## 入れ替わった)——このファイルもそれに合わせ、`MASSIVE_START`の
## derivationを「接触+0.120秒」の直接式へ変更した。
## 「READABLE_SWORD_AURA_CRISP_SCALE_LOCK v21」(2026-08-17) — README「外周
## 爆発は接触から0.140秒後にawaitなしで開始してください」——0.120→0.140。
const EOS_BURST_OUTER_START_AFTER_CONTACT_SECONDS := 0.140
## 「新しいderivationのもとでも、ImpactとOuterが実際に0.260秒重なる」
## ことをheadless検証で直接確認する基準値として維持(現在は直接の
## derivationには使わない、確認用の named constant)——IMPACT_SECONDS
## (0.400)-OUTER_START_AFTER_CONTACT(0.140)=0.260と一致(README「impact
## と0.260秒重ねます」)。
const EOS_BURST_IMPACT_TO_OUTER_OVERLAP_SECONDS := 0.260
## README「開始alphaは0.160秒Smootherstepで上げます」——参照実装
## `entry_alpha := smootherstep(elapsed/OUTER_ENTRY_FADE)`(elapsedはouter
## 自身のローカル時計)と同数式、値だけ0.120→0.160へ更新。
const EOS_BURST_OUTER_ENTRY_FADE_SECONDS := 0.160
const EOS_BURST_MASSIVE_START_SECONDS := \
	EOS_BURST_HIT_AT_SECONDS + EOS_BURST_OUTER_START_AFTER_CONTACT_SECONDS
const EOS_BURST_MASSIVE_END_SECONDS := \
	EOS_BURST_MASSIVE_START_SECONDS + EOS_BURST_MASSIVE_SECONDS  ## 相当
## README「外周のalphaカーブ」——#101の汎用`_eos_burst_frame_crossfade_
## pair()`の`curve`引数へそのまま渡す。
const EOS_BURST_MASSIVE_OUTER_ALPHA_CURVE: Array[float] = [
	0.70, 0.82, 0.92, 1.00, 1.00, 1.00, 1.00, 0.98, 0.72, 0.42, 0.18,
]
## 「敵を完全に覆う」ピーク判定(既存の`_draw_boss_enemy`側ゲート)は白熱核
## 削除後も維持——新カーブ自体がalpha1.00で飽和する配列位置(3〜6、外周
## 単独の実測値からそのまま導出、恣意的な個数指定ではない)をピーク窓と
## する。
const EOS_BURST_MASSIVE_PEAK_FRAME_LO := 3
const EOS_BURST_MASSIVE_PEAK_FRAME_HI := 6
## README新スケール式(v9の単層0.82〜1.20/pad96/ref400とは別物)——
## `outer_scale = clamp((enemy_group_bounds.size.x+144)/340, 1.05, 1.45)`。
## このゲームの敵は常に`BOSS_ICON_PX`(176)固定サイズ: outer=clamp((176+
## 144)/340,1.05,1.45)=clamp(0.941,...)=1.05(下限クランプ)——実測で
## この式が常にこの値を返すことを確認済み。将来敵アイコンサイズが変わって
## も正しく追従する設計は旧v5〜v9のスケール式と同じ判断を踏襲。
const EOS_BURST_OUTER_SCALE_MIN := 1.05
const EOS_BURST_OUTER_SCALE_MAX := 1.45
const EOS_BURST_OUTER_SCALE_BOUNDS_PAD_PX := 144.0
const EOS_BURST_OUTER_SCALE_REF_W := 340.0

func _eos_burst_massive_burst_active(elapsed: float) -> bool:
	var age := elapsed - EOS_BURST_MASSIVE_START_SECONDS
	return age >= 0.0 and age < EOS_BURST_MASSIVE_SECONDS


## 敵visible-hideゲート専用の粗いフレーム判定(tick基準で十分、既存の
## 汎用ヘルパーをそのまま流用)——クロスフェード自体の精密な計算は
## `_draw_eos_burst_massive_burst`が`_eos_burst_frame_crossfade_pair()`
## (#101で新設した汎用関数)を別途連続時計で呼んで担う。返り値は配列位置
## (0〜10)であり実ファイル番号ではない——`EOS_BURST_MASSIVE_OUTER_FRAME_
## NUMBERS`経由で変換するのは描画関数側の責務。
func _eos_burst_massive_burst_frame_index(elapsed: float) -> int:
	return _eos_burst_frame_index_from_table(
		EOS_BURST_MASSIVE_FRAME_DURATIONS, elapsed - EOS_BURST_MASSIVE_START_SECONDS)


## 「配列位置3〜6(alpha1.00で飽和する区間)のピーク中は対象敵のvisibleを
## falseにして構いませんが、敵ノードを削除しません」——`_draw_boss_enemy`
## 側で呼ばれるゲート判定。敵ノード自体(sim側の状態)には一切触れず、この
## 1フレームの描画呼び出しをスキップするだけ(既存の`_battle_victory_
## step_active()`等と同じ「描画だけをスキップする」パターン)。
func _eos_burst_massive_burst_peak_active(elapsed: float) -> bool:
	if not _eos_burst_vfx_active():
		return false
	if not _eos_burst_massive_burst_active(elapsed):
		return false
	var idx := _eos_burst_massive_burst_frame_index(elapsed)
	return idx >= EOS_BURST_MASSIVE_PEAK_FRAME_LO and idx <= EOS_BURST_MASSIVE_PEAK_FRAME_HI


func _eos_burst_massive_outer_scale(view: Rect2) -> float:
	var rect := _boss_icon_rect(view)
	return clampf(
		(rect.size.x + EOS_BURST_OUTER_SCALE_BOUNDS_PAD_PX) / EOS_BURST_OUTER_SCALE_REF_W,
		EOS_BURST_OUTER_SCALE_MIN, EOS_BURST_OUTER_SCALE_MAX)


func _eos_burst_massive_outer_texture(array_index: int) -> Texture2D:
	if array_index < 0 or array_index >= EOS_BURST_MASSIVE_OUTER_FRAME_NUMBERS.size():
		return null
	var frame_number: int = EOS_BURST_MASSIVE_OUTER_FRAME_NUMBERS[array_index]
	return _eos_burst_indexed_frame_texture(EOS_BURST_MASSIVE_OUTER_DIR, frame_number)


## 「爆発ノードは`BurstAnchor/OuterA`と`BurstAnchor/OuterB`の2Spriteだけ
## です」——旧・core_a/core_bの描画は完全に削除、outerのみを`_eos_burst_
## frame_crossfade_pair()`(#101で新設、全区間Smootherstep+最終コマQuad
## EaseOut)で1回呼ぶ。「position、scale、rotationは全11コマ中不変」
## ・bottom-center anchoringは無改修のまま維持。
func _draw_eos_burst_massive_burst(view: Rect2, elapsed: float) -> void:
	if not _eos_burst_massive_burst_active(elapsed):
		return
	var smooth_age := _eos_burst_smooth_elapsed(elapsed) - EOS_BURST_MASSIVE_START_SECONDS
	var outer_pair := _eos_burst_frame_crossfade_pair(
		smooth_age, EOS_BURST_MASSIVE_FRAME_DURATIONS, EOS_BURST_MASSIVE_OUTER_ALPHA_CURVE)
	## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — Outerは
	## Impactの末尾と0.100秒重なるため、開始直後は薄く立ち上げる(いきなり
	## 全開alphaで割り込まない)。
	var entry_mult := _eos_burst_ease_smootherstep(
		clampf(smooth_age / EOS_BURST_OUTER_ENTRY_FADE_SECONDS, 0.0, 1.0))
	var outer_scale := _eos_burst_massive_outer_scale(view)
	var ground := _eos_burst_enemy_ground_anchor(view)
	var outer_size := EOS_BURST_MASSIVE_FRAME_SIZE * outer_scale
	var outer_top_left := (ground - Vector2(outer_size.x * 0.5, outer_size.y)).round()
	var outer_idx_a: int = outer_pair[0]
	var outer_idx_b: int = outer_pair[1]
	var outer_alpha_a: float = outer_pair[2] * entry_mult
	var outer_alpha_b: float = outer_pair[3] * entry_mult
	if outer_idx_a >= 0 and outer_alpha_a > 0.0:
		var outer_tex_a := _eos_burst_massive_outer_texture(outer_idx_a)
		if outer_tex_a != null:
			draw_texture_rect(outer_tex_a, Rect2(outer_top_left, outer_size), false, Color(1, 1, 1, outer_alpha_a))
	if outer_idx_b >= 0 and outer_alpha_b > 0.0:
		var outer_tex_b := _eos_burst_massive_outer_texture(outer_idx_b)
		if outer_tex_b != null:
			draw_texture_rect(outer_tex_b, Rect2(outer_top_left, outer_size), false, Color(1, 1, 1, outer_alpha_b))


## === 縦の竜牙命中(`eos_dragon_fang_impact_6f.png`、256×256×6) ===
## README「敵位置を縦に裂き、4コマ目だけ竜頭が現れる命中...敵のground
## anchor中央へ固定して再生。移動させない」。
const EOS_BURST_FANG_SHEET_PATH := "res://assets/art/eos_dragon_fang_impact_6f.png"
const EOS_BURST_FANG_FRAME_COUNT := 6
const EOS_BURST_FANG_FRAME_SIZE := Vector2(256.0, 256.0)
const EOS_BURST_FANG_FRAME_DURATIONS: Array[float] = [0.06, 0.07, 0.08, 0.10, 0.08, 0.07]
const EOS_BURST_FANG_SECONDS := 0.46  ## sum of the above
const EOS_BURST_FANG_START_SECONDS := 2.74  ## README絶対時刻
const EOS_BURST_FANG_END_SECONDS := \
	EOS_BURST_FANG_START_SECONDS + EOS_BURST_FANG_SECONDS  ## 3.20、== HIT_AT
## PowerShellで実測: 各コマの「接地帯」(alpha>128が8px以上連続する最下段
## 行)のX重心・そのY座標。同じ256×256キャンバス内でこの「炎の根元」が
## コマごとに大きく水平移動していた(素材側の実測content-registration
## ずれ、このプロジェクトの多くのシートで繰り返し見つかっているのと同種)
## ため、`ground_anchor - anchor[i]`をtop-leftにして根元を敵のground
## anchorへ毎コマ固定する。
const EOS_BURST_FANG_FRAME_ANCHOR: Array[Vector2] = [
	Vector2(174.3, 233.0),
	Vector2(124.7, 238.0),
	Vector2(72.4, 234.0),
	Vector2(175.6, 222.0),
	Vector2(123.9, 222.0),
	Vector2(78.8, 219.0),
]

var _eos_burst_fang_tex_cache: Texture2D = null
func _eos_burst_fang_texture() -> Texture2D:
	if _eos_burst_fang_tex_cache == null:
		_eos_burst_fang_tex_cache = _soul_break_load_texture(EOS_BURST_FANG_SHEET_PATH)
	return _eos_burst_fang_tex_cache


func _draw_eos_burst_fang_impact(view: Rect2, elapsed: float) -> void:
	var age := elapsed - EOS_BURST_FANG_START_SECONDS
	if age < 0.0 or age >= EOS_BURST_FANG_SECONDS:
		return
	var tex := _eos_burst_fang_texture()
	if tex == null:
		return
	var frame_idx := _eos_burst_frame_index_from_table(EOS_BURST_FANG_FRAME_DURATIONS, age)
	var ground := _eos_burst_enemy_ground_anchor(view)
	var anchor: Vector2 = EOS_BURST_FANG_FRAME_ANCHOR[frame_idx]
	var top_left := (ground - anchor).round()
	var src := Rect2(
		float(frame_idx) * EOS_BURST_FANG_FRAME_SIZE.x, 0.0,
		EOS_BURST_FANG_FRAME_SIZE.x, EOS_BURST_FANG_FRAME_SIZE.y)
	draw_texture_rect_region(tex, Rect2(top_left, EOS_BURST_FANG_FRAME_SIZE), src)


## 「MANIFEST_ONLY_GRAND_SLASH v8」(2026-08-13) — README「eos_dragon_
## afterglow_6f.pngへの参照」「爆発後に竜の残光を出す処理」は【完全削除】
## 対象——竜は攻撃へ一切参加しないため、爆発後に竜由来の残光を表示する
## 演出自体が確定方針と矛盾する。旧`EOS_BURST_AFTERGLOW_*`一式・
## `_eos_burst_afterglow_texture`・`_draw_eos_burst_afterglow`をここで
## 完全に削除し、dispatcher(`_draw_eos_burst_front_vfx`)からの呼び出しも
## 削除した。


## 「Professional Mix / Impact Polish v1」(2026-08-07) — 旧カウントダウン
## 方式(`_eos_burst_impact_flash_t`を`_on_battle_anim_tick`のtick-dt=0.05秒
## 刻みで減算)は、`_draw()`が呼ばれる実描画フレームの間ずっと同じ値を
## 保持したまま次tickまで一切変化しないため、実際にはピークαが1
## rendered frameではなく丸ごと1game tick分(最大50ms)ベタ張りになって
## いた(`references/impact_flash_60fps.jpg`で確認、爆発を白く洗い流す
## 直接原因)。新方式は接触の瞬間に記録した連続elapsed基準点
## (`_eos_burst_contact_trigger_elapsed`)から、この関数が呼ばれるたびに
## `age`を計算し直す——`_process`が毎実フレーム呼ばれる限りageも毎フレーム
## 連続的に進み、「最も白い状態はengine側1 rendered frame程度、そこから
## 45〜60msで急fade」を文字通り実現する。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) —
## rise(0.035秒、Smootherstepで0→PEAK)→fall(0.115秒、Smootherstepで
## PEAK→0)の2段envelope。旧「同一フレームで即ピーク保持→減衰」から、
## ピークへも滑らかに立ち上がる形へ変更(参照実装`play_contact_flash`と
## 同じ形状)——トリガー基準点(`_eos_burst_contact_trigger_elapsed`、
## 接触の瞬間に1回だけ記録される既存の一回性マーカー)自体は無改修。
func _eos_burst_impact_flash_alpha() -> float:
	if _eos_burst_contact_trigger_elapsed < 0.0:
		return 0.0
	var age := _eos_burst_smooth_elapsed(_battle_anim_phase_elapsed) - _eos_burst_contact_trigger_elapsed
	if age < 0.0 or age >= EOS_BURST_IMPACT_FLASH_TOTAL_SECONDS:
		return 0.0
	if age < EOS_BURST_IMPACT_FLASH_RISE_SECONDS:
		var rise_t := age / EOS_BURST_IMPACT_FLASH_RISE_SECONDS
		return EOS_BURST_IMPACT_FLASH_PEAK_ALPHA * smoothstep(0.0, 1.0, rise_t)
	var fall_t := (age - EOS_BURST_IMPACT_FLASH_RISE_SECONDS) / EOS_BURST_IMPACT_FLASH_FALL_SECONDS
	return EOS_BURST_IMPACT_FLASH_PEAK_ALPHA * (1.0 - smoothstep(0.0, 1.0, clampf(fall_t, 0.0, 1.0)))


## 「UIは光らせない」——`view`は戦闘ビュー矩形自身(UI/ボタンパネルは
## この矩形の外)なので、`draw_rect(view, ...)`で描く時点で描画範囲が
## 自動的にUIを除外する。
## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「screen-space白ColorRectのflash」——参照実装`play_contact_flash`が
## `flash_overlay.color = Color.WHITE`(純白、alphaのみ変化)を使うのに
## 合わせ、旧・暖色寄りのtint(1.0,0.95,0.85)から純白へ変更した。
func _draw_eos_burst_impact_screen_flash(view: Rect2) -> void:
	var a := _eos_burst_impact_flash_alpha()
	if a <= 0.0:
		return
	draw_rect(view, Color(1.0, 1.0, 1.0, a))


## 「着弾『大爆発』強化 v3」(2026-08-06)〜「Professional Mix / Impact
## Polish v1」(2026-08-07) — 「最初にドン、すぐpow(1-u,2)相当で急減衰する」
## 地震のような揺れ。11個の(経過秒, offsetpx)キーフレームを折れ線補間する
## ——`毎フレーム完全ランダムな細かいバイブレーションは禁止`のため、ノイズ
## ではなく決定論的な折れ線(値自体はpow(1-u,2)から計算済み、上のテーブル
## 定義コメント参照)。
## 「Slower + Smooth + Massive Finish v5」(2026-08-12) — README「4.45〜
## 4.75秒」はダメージ発生(HIT_AT=4.63)より0.18秒前に開始する——旧v3/v4の
## `_eos_burst_contact_trigger_elapsed`(ヒットストップ解除の瞬間にしか
## 記録されない)を基準にしたままでは表現できないため、`EOS_BURST_SHAKE_
## START_SECONDS`という絶対時刻ゲートへ作り直した。連続性(hitstop中も
## tick境界に縛られず滑らかに進む)は引き続き`_eos_burst_smooth_elapsed`
## から`age`を毎実描画フレームで計算し直すことで保つ——基準点が「接触
## イベント」から「固定の絶対秒」に変わっただけで、"連続elapsedから
## 毎フレーム計算し直す"という設計自体は無改修。最終offsetは`round()`で
## 整数化(「座標は整数丸め」)。
func _eos_burst_mega_shake_offset() -> Vector2:
	if not _eos_burst_vfx_active():
		return Vector2.ZERO
	var age := _eos_burst_smooth_elapsed(_battle_anim_phase_elapsed) - EOS_BURST_SHAKE_START_SECONDS
	if age < 0.0 or age >= EOS_BURST_MEGA_SHAKE_TOTAL_SECONDS:
		return Vector2.ZERO
	var keys := EOS_BURST_MEGA_SHAKE_KEYFRAMES
	if age <= float(keys[0][0]):
		var v0: Vector2 = keys[0][1]
		return Vector2(roundf(v0.x), roundf(v0.y))
	for i in range(keys.size() - 1):
		var t0: float = keys[i][0]
		var t1: float = keys[i + 1][0]
		if age <= t1:
			var v_from: Vector2 = keys[i][1]
			var v_to: Vector2 = keys[i + 1][1]
			var frac := clampf((age - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)
			var v := v_from.lerp(v_to, frac)
			return Vector2(roundf(v.x), roundf(v.y))
	return Vector2.ZERO  ## past the last keyframe (already (0,0) there anyway)


## 「約0.15秒で下部のコマンド・仲間カードUIを透明度0.15まで薄くする」
## ——`_battle_bar.modulate.a`に直接使う0-1のalpha。カメラズームと同じ
## 立ち上がり秒数を共有、RETURN窓で1.0へ戻す(帰還開始時に元へ戻す、を
## 直接満たす)。
func _eos_burst_ui_dim_alpha(elapsed: float) -> float:
	if elapsed < EOS_BURST_UI_DIM_IN_SECONDS:
		return lerpf(1.0, EOS_BURST_UI_DIM_ALPHA, smoothstep(0.0, 1.0, elapsed / EOS_BURST_UI_DIM_IN_SECONDS))
	if elapsed < EOS_BURST_RETURN_START_SECONDS:
		return EOS_BURST_UI_DIM_ALPHA
	if elapsed < EOS_BURST_RETURN_END_SECONDS:
		var t := (elapsed - EOS_BURST_RETURN_START_SECONDS) / EOS_BURST_RETURN_SECONDS
		return lerpf(EOS_BURST_UI_DIM_ALPHA, 1.0, smoothstep(0.0, 1.0, t))
	return 1.0


## 「カメラを約1.08倍まで寄せ、ソティリスと攻撃対象が戦闘画面の中央へ
## 入るようにする。突進中はカメラをソティリスへ追従させる」(2026-08-05、
## 同日追加ラウンド) — 前ラウンドの着弾限定の短いズームパルス(1.025x、
## 旧`_eos_burst_impact_zoom_scale`/`_eos_burst_impact_zoom_t`)を完全に
## 置き換える持続的なズーム。elapsed=0(タメ開始)からEOS_BURST_ZOOM_IN_
## SECONDS(0.15秒、UI dimと同じ立ち上がり)で1.0→1.08まで寄り、
## RETURN_STARTまで保持、RETURN窓(既存のEOS_BURST_RETURN_SECONDS)で
## 1.0へ戻す——「帰還開始時にカメラ倍率を必ず元へ戻す」を直接満たす。
## 「エオスバースト演出全面刷新」(2026-08-11) — 「カットインが閉じた
## 直後に戦闘画面へ戻ります...カメラはソティリスを中心に約1.05〜1.08倍
## まで軽くズームしてください」——ズームの開始点をelapsed=0からREVEAL_END
## (=竜が完成し、カットインが閉じた直後)へ変更。カットイン表示中は
## ズーム1.0のまま(カットイン自身は画面比率ベースの平面パネルなので、
## 背後のカメラがズームしていても・していなくても見た目は変わらないが、
## 「カットインが閉じた直後にズームする」という時系列を明確にするため
## ここで区切る)。
## 「現行ソティリス維持版 v3」(2026-08-12) — 「ソティリスの現在の見た目
## (座標、表示倍率、向き、z_index、ピクセル密度)を維持してください」との
## 最優先指示により、カメラズームは今回廃止し常に等倍(1.0)を返す
## (`EOS_BURST_ZOOM_SCALE`定数自体は経緯として残置、無参照)。
func _eos_burst_zoom_scale(_elapsed: float) -> float:
	return 1.0


## ズームのピボット——「カメラはソティリスを中心に」——ソティリスの
## 生きた足元よりやや上(頭・胸のあたり)を中心に据える(足元そのものを
## ピボットにすると、ズーム時に頭が画面上端へ寄ってしまうため)。敵は
## もうピボットに影響しない(旧: ソティリスと敵の中点)。
const EOS_BURST_ZOOM_PIVOT_LIFT_PX := 60.0
func _eos_burst_zoom_pivot(view: Rect2, unit_id: int, elapsed: float) -> Vector2:
	var sotiris := _eos_burst_sotiris_live_feet(view, unit_id, elapsed)
	return sotiris - Vector2(0.0, EOS_BURST_ZOOM_PIVOT_LIFT_PX)


## §7: front layer dispatcher — everything drawn IN FRONT of the party row
## (glow, breath, impact stages).
func _draw_eos_burst_front_vfx(view: Rect2) -> void:
	if not _eos_burst_vfx_active():
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	var unit_id := int(entry.get("unit_id", 0))
	var elapsed := _battle_anim_phase_elapsed
	_draw_eos_burst_mouth_tip_charge(view, unit_id, elapsed)
	_draw_eos_burst_mouth_charge(view, unit_id, elapsed)
	_draw_eos_burst_mouth_aim_light(view, unit_id, elapsed)
	_draw_eos_burst_release_flash(view, unit_id, elapsed)
	# 「RESTORE_GRAND_SLASH_NO_WHITE_CIRCLE v14」(2026-08-14) — v13の細い
	# 水平線(horizontal_slash)を撤去し、v12承認版の大斬撃(Main+Echo)へ
	# 戻した(呼び出しごと削除、対応する関数群も完全削除済み——上のコード
	# 参照)。slash(travel, [3.58,4.78))→enemy_crossflash(impact,
	# [4.78,5.02))→massive_burst(burst, [5.02,6.22))の3関数を並べる——
	# いずれも自分の絶対時刻窓の外では即returnする既存idiomのため、3つの
	# 窓が互いに重複しない(TIMELINE_V14.csv準拠へ再retiming済み)ことだけ
	# で「並列Tween/同時coroutineで開始しない」「同一フレームで2phaseが
	# visibleにならない」を満たす——新しいstate machine/phase変数は追加
	# していない(このファイル全体の全VFXが共有する確立済み手法)。
	_draw_eos_burst_slash(view, unit_id, elapsed)
	_draw_eos_burst_enemy_crossflash(view, elapsed)
	_draw_eos_burst_massive_burst(view, elapsed)
	_draw_eos_burst_cutin(view, unit_id, elapsed)


## === EOS_CUTIN: 漫画風カットイン (2026-08-11新設) ===
## 「最初から長方形の画像を表示するのではなく、戦闘画面へ斬撃が切り込む
## ように表示する」。タイムライン秒数(EOS_CUTIN_*)はマスタータイムライン
## 付近で宣言済み。ここでは幾何(斜めの帯=パララログラム、画面比率ベース)
## とテクスチャ供給(最終画像への差し替え口+プレースホルダー合成)を実装
## する。

## 最終カットイン画像(1920×640、透明背景)への差し替え口。存在すれば
## それを最優先で使う——ResourceLoader.existsで判定するだけで、preload
## は一切使わないため、ファイルが未納品でもエラーにならない。
var _eos_cutin_final_tex_cache: Texture2D = null
var _eos_cutin_final_checked := false
func _eos_cutin_final_texture() -> Texture2D:
	if not _eos_cutin_final_checked:
		_eos_cutin_final_checked = true
		if ResourceLoader.exists(EOS_CUTIN_FINAL_IMAGE_PATH):
			_eos_cutin_final_tex_cache = load(EOS_CUTIN_FINAL_IMAGE_PATH)
	return _eos_cutin_final_tex_cache


## 最終画像が届くまでの仮カットイン——既存のソティリス/竜アセット+
## 手続き背景・集中線を1枚のImageへ一度だけ合成してキャッシュする(重い
## 処理を毎フレーム行わない、このファイル全体の確立済みイディオム)。
## NEARESTでリサイズしドット絵の質感を保つ。
var _eos_cutin_placeholder_cache: ImageTexture = null
func _eos_cutin_placeholder_texture() -> Texture2D:
	if _eos_cutin_placeholder_cache != null:
		return _eos_cutin_placeholder_cache
	var w := int(EOS_CUTIN_IMAGE_SIZE.x)
	var h := int(EOS_CUTIN_IMAGE_SIZE.y)
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.03, 0.10, 1.0))
	# 集中線/速度線——中心よりやや左寄りの焦点から放射する漫画調の線。
	var focus := Vector2(w * 0.40, h * 0.55)
	for i in 46:
		var a := TAU * float(i) / 46.0
		var dir := Vector2(cos(a), sin(a))
		var len_px := 220.0 + fmod(float(i) * 57.0, 260.0)
		var col := Color(1.0, 0.9, 0.6, 0.11) if i % 3 != 0 else Color(0.55, 0.9, 1.0, 0.09)
		var steps := int(len_px)
		for s in steps:
			var p := focus + dir * float(s)
			var px := int(p.x)
			var py := int(p.y)
			if px < 0 or px >= w or py < 0 or py >= h:
				break
			var falloff := 1.0 - float(s) / len_px
			var c := col
			c.a *= falloff
			img.set_pixel(px, py, img.get_pixel(px, py).lerp(c, c.a))
	# 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 竜の完全削除に伴い、
	# このプレースホルダー(実カットイン画像`eos_cutin_sword_closeup.png`が
	# 常に存在するため実際には呼ばれないフォールバック専用)からも竜の
	# 頭〜首の合成を撤去した。「竜のtexture参照が一切残らない」を、この
	# 到達不能なフォールバック経路も含めて満たす。
	# ソティリス(顔〜上半身)——右側、大きめ。
	var sotiris_tex := _soul_break_load_texture("res://assets/art/attack_minion_0.png")
	if sotiris_tex != null:
		var simg := sotiris_tex.get_image()
		if simg != null:
			simg = simg.duplicate()
			simg.resize(600, 600, Image.INTERPOLATE_NEAREST)
			img.blend_rect(simg, Rect2i(Vector2i.ZERO, simg.get_size()), Vector2i(w - 660, 20))
	var tex := ImageTexture.create_from_image(img)
	_eos_cutin_placeholder_cache = tex
	return tex


func _eos_cutin_texture() -> Texture2D:
	var final_tex := _eos_cutin_final_texture()
	if final_tex != null:
		return final_tex
	return _eos_cutin_placeholder_texture()


## 帯(パララログラム)の基準軸——画面「比率」ベース(view.size由来)なので
## 1152×648以外の画面サイズでもレイアウトが崩れない。
func _eos_cutin_band_axes(view: Rect2) -> Dictionary:
	var dir := Vector2(cos(EOS_CUTIN_ANGLE_RAD), sin(EOS_CUTIN_ANGLE_RAD))
	var perp := Vector2(-dir.y, dir.x)
	var length := view.size.x + view.size.y * absf(tan(EOS_CUTIN_ANGLE_RAD)) + 40.0
	var center := view.position + view.size * 0.5
	var origin := center - dir * length * 0.5
	return {"dir": dir, "perp": perp, "length": length, "origin": origin}


func _eos_cutin_quad(axes: Dictionary, u_left: float, u_right: float, half_h_px: float) -> Dictionary:
	var origin: Vector2 = axes["origin"]
	var dir: Vector2 = axes["dir"]
	var perp: Vector2 = axes["perp"]
	var length: float = axes["length"]
	var p_bl := origin + dir * (u_left * length) - perp * half_h_px
	var p_br := origin + dir * (u_right * length) - perp * half_h_px
	var p_tr := origin + dir * (u_right * length) + perp * half_h_px
	var p_tl := origin + dir * (u_left * length) + perp * half_h_px
	var points := PackedVector2Array([p_bl, p_br, p_tr, p_tl])
	return {"points": points}


## 「現行ソティリス維持版 v3」(2026-08-12) — 納品の`eos_cutin_sword_
## closeup.png`は画面と完全に同じ寸法(1152×648)。旧実装は帯自身の(u,v)
## パラメータ空間をテクスチャUVとして直接使っていたため、開閉に伴い絵が
## 伸縮して見える簡易実装だった——今回は各頂点の"実際の画面上の位置"から
## UVを計算する(`(point-view.position)/view.size`)方式へ差し替え、絵が
## 画面に固定されたまま、斜めの窓だけが動く正しい「ワイプ」になるように
## した(斜めクリッピング機構自体は無改修、UV計算だけを変更)。
func _eos_cutin_view_uv(view: Rect2, point: Vector2) -> Vector2:
	return (point - view.position) / view.size


## 「CONTINUOUS_MOTION_CUTIN_AURA_LOCK v19」(2026-08-16) — 旧5段階ワイプ
## (`_eos_cutin_stage`)を完全に削除し、alpha envelope(enter/hold/exit)
## だけを返す単純な関数へ置き換えた——帯自体の開閉形状(u_left/u_right/
## half_h)はもう時間で変化させない(常に全開)。
func _eos_cutin_alpha(age: float) -> float:
	if age < EOS_CUTIN_ENTER_SECONDS:
		return _eos_burst_ease_smootherstep(age / EOS_CUTIN_ENTER_SECONDS)
	var exit_start := EOS_CUTIN_DURATION_SECONDS - EOS_CUTIN_EXIT_SECONDS
	if age >= exit_start:
		var t := (age - exit_start) / EOS_CUTIN_EXIT_SECONDS
		return 1.0 - _eos_burst_ease_smootherstep(clampf(t, 0.0, 1.0))
	return 1.0


## 「FIXED_CUTIN_VISIBLE_BRIDGE_UNIFIED_FINISH v20」(2026-08-16) — README
## 「CutinRootの開始時global transformを保存し、表示中の全process_frameで
## 同じ値を再設定します。position差:0px、scale差:0、rotation差:0、
## skew差:0」——v19の`_eos_cutin_offset_x()`(viewport幅の-11%→+9%へ毎
## フレーム再計算していた水平位置)を完全に削除した。`_draw_eos_burst_
## cutin`は今回`view`そのもの(帯の幾何・UVサンプリングとも一切変更しない)
## を使うだけの構造にしたため、「開始時のtransformを保存して毎フレーム
## 再設定する」という参照実装のパターンを、そもそも動かす計算式自体が
## 存在しないことで構造的に(近似ではなく厳密に)満たす——`view`は
## `_draw_boss_battle`の冒頭で1回だけ計算される共有の戦闘ビュー矩形で、
## カットインの描画中に別の値へ書き換わることは無い。


func _draw_eos_burst_cutin(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < EOS_CUTIN_START_SECONDS or elapsed >= EOS_CUTIN_END_SECONDS:
		return
	var age := elapsed - EOS_CUTIN_START_SECONDS
	var alpha := _eos_cutin_alpha(age)
	if alpha <= 0.001:
		return
	# 「カットインは完全固定」——帯の幾何(band_axes)・UVサンプリング
	# (view_uv)とも、時間/進捗/viewport比率から計算する水平offsetを一切
	# 適用しない、無改修の`view`だけを使う(v19までのshifted_viewは撤去)。
	var axes := _eos_cutin_band_axes(view)
	var full_half_h := view.size.y * EOS_CUTIN_BAND_HEIGHT_FRAC * 0.5
	var q := _eos_cutin_quad(axes, 0.0, 1.0, full_half_h)
	var points: PackedVector2Array = q["points"]
	var tex := _eos_cutin_texture()
	var uvs := PackedVector2Array([
		_eos_cutin_view_uv(view, points[0]), _eos_cutin_view_uv(view, points[1]),
		_eos_cutin_view_uv(view, points[2]), _eos_cutin_view_uv(view, points[3])])
	var tint := Color(1.0, 1.0, 1.0, alpha)
	var colors := PackedColorArray([tint, tint, tint, tint])
	if tex != null:
		draw_polygon(points, colors, uvs, tex)
	else:
		draw_polygon(points, colors)
	# 「最優先条件: 前回の全画面イラストは使用しない。カットイン画像は
	# この1枚だけ」——納品の実画像を使っている間は、手続き生成の縁取り/
	# タイトル文字を重ねない(絵自体が完成した1枚の構図のため)。これらの
	# 装飾は最終画像が万一見つからずプレースホルダーへ落ちた場合のみ
	# 表示する安全策として残す。
	if _eos_cutin_final_texture() == null:
		# 白金色の太い縁、内側に細い水色の縁。
		var gold := Color(1.0, 0.92, 0.55, 0.95 * alpha)
		var cyan := Color(0.55, 0.94, 1.0, 0.9 * alpha)
		for i in 4:
			_draw_eos_burst_quad(points[i], points[(i + 1) % 4], EOS_CUTIN_BORDER_GOLD_PX, gold)
		var inset := EOS_CUTIN_BORDER_GOLD_PX * 0.5 + EOS_CUTIN_BORDER_CYAN_PX * 0.5
		var qi := _eos_cutin_quad(axes, 0.0, 1.0, maxf(0.0, full_half_h - inset))
		var pi: PackedVector2Array = qi["points"]
		for i in 4:
			_draw_eos_burst_quad(pi[i], pi[(i + 1) % 4], EOS_CUTIN_BORDER_CYAN_PX, cyan)
		# スキル名「エオスバースト」——enter/exitの短いフェード窓を除いた
		# ほぼ全表示区間で左側へ斜めに表示(旧「保持」区間相当)。
		if age >= EOS_CUTIN_ENTER_SECONDS - 0.05 \
				and age < EOS_CUTIN_DURATION_SECONDS - EOS_CUTIN_EXIT_SECONDS + 0.05:
			var title_pos: Vector2 = \
				Vector2(axes["origin"]) + Vector2(axes["dir"]) * (float(axes["length"]) * 0.14)
			draw_set_transform(title_pos, EOS_CUTIN_ANGLE_RAD, Vector2.ONE)
			var font := ThemeDB.fallback_font
			draw_string(
				font, Vector2(-4.0, 12.0), EOS_CUTIN_TITLE_TEXT,
				HORIZONTAL_ALIGNMENT_LEFT, -1, EOS_CUTIN_TITLE_FONT_SIZE,
				Color(1.0, 0.95, 0.75, alpha))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 剣先の光 — spans SLASH_START..SLASH_END, a steady white-gold-cyan point
## at the sword tip through the whole rush+strike, growing from nothing at
## SLASH_START. Follows the LIVE sword-tip position.
## 「CONTACT_SYNC_STOP_ON_ENEMY v18」(2026-08-16) — 旧`[BEAM_START,
## HIT_AT)`窓は、release-frame変更によりHIT_AT(=SLASH_END、4.08)が
## BEAM_START(4.15、無改修)より先に来るようになったため空になり、この
## 剣先の点光源が完全に消えるところだった。実際の発射〜命中窓
## (`EOS_BURST_SLASH_START/_END_SECONDS`)へ直接繋ぎ直し、成長比率も
## その窓自体の長さ(`EOS_BURST_SLASH_DURATION_SECONDS`)で正規化する
## ことで、「突撃〜命中の間ずっと育つ」という元の演出意図を保つ。
func _draw_eos_burst_mouth_tip_charge(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < EOS_BURST_SLASH_START_SECONDS or elapsed >= EOS_BURST_SLASH_END_SECONDS:
		return
	var t := clampf(
		(elapsed - EOS_BURST_SLASH_START_SECONDS) / EOS_BURST_SLASH_DURATION_SECONDS, 0.0, 1.0)
	var tip := _eos_burst_sword_tip_pos(view, unit_id, elapsed)
	_fill_soul_break_dot(tip, lerpf(2.0, 12.0, t), Color(1.0, 0.9, 0.55, lerpf(0.25, 0.95, t)))
	_fill_soul_break_dot(tip, lerpf(1.0, 5.5, t), Color(0.6, 0.95, 1.0, lerpf(0.25, 0.95, t)))
	_fill_soul_break_dot(tip, lerpf(0.5, 3.0, t), Color(1.0, 0.98, 0.94, lerpf(0.25, 1.0, t)))


## Per-tick housekeeping: solves the approach offset once, fires shake and
## debug-log checkpoints named after the 6 DragonSkillTimeline phases.
func _update_eos_burst_state(elapsed: float, unit_id: int) -> void:
	# 「必殺技中の画面演出」(2026-08-05、同日追加ラウンド) — 下部の
	# コマンド・仲間カードUI(`_battle_bar`)を薄くする。上部の敵HPバー
	# (`_boss_banner`)は別ノードのため無改修のまま。真の描画関数ではなく
	# この per-tick state-update 関数で`.modulate.a`を直接書き換える——
	# `_battle_bar`はCanvasItemの実ノードであり、このファイルのカスタム
	# `_draw()`ディスパッチとは別レイヤーで自動的に描画されるため。
	_battle_bar.modulate.a = _eos_burst_ui_dim_alpha(elapsed)
	if _eos_burst_approach_offset_px <= 0.0 and elapsed < EOS_BURST_REVEAL_END_SECONDS:
		_eos_burst_approach_offset_px = _eos_burst_solve_approach_offset(_view_rect(), unit_id)
	_eos_burst_log_at("EOS phase anticipation", 0.0)
	# 「タメ延長 + 専用SE」(2026-08-06) — 「charge開始と同じフレームで
	# 再生する。EOS_PRE_DRAGON_CHARGE_SECと長さが一致している」——charge
	# フェーズ(=`EOS_BURST_SUMMON_HOLD_SECONDS`本人)が実際に始まる瞬間
	# (HOLD開始=PULLBACK+CHARGE終了)で1回だけ再生。オーラ自身の成長
	# テーブルが同じ`hold_start`を基準点に使っている(`_draw_eos_burst_
	# charge_aura`参照)ため、音と絵は構造的に同期する。
	var eos_sfx_hold_start := EOS_BURST_SUMMON_PULLBACK_SECONDS + EOS_BURST_SUMMON_CHARGE_SECONDS
	if elapsed >= eos_sfx_hold_start and not _eos_burst_logged.has("EOS SFX charge"):
		_eos_burst_logged["EOS SFX charge"] = true
		_play_eos_burst_sfx("charge")
		# 「タメ開始と完全同時に、既存のwind/riser(charge)へ新しいaura_core
		# (低い脈動・圧力)を重ねる」(v2 pack) — 同じ一回性ガード内で両方
		# `.play()`するので、構造的に同一tickで発火し絶対にズレない。
		_play_eos_burst_sfx("aura_core")
	if elapsed >= EOS_BURST_REVEAL_START_SECONDS:
		_eos_burst_log_at("EOS phase materialize", elapsed)
		# 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 旧「dragon_form」
		# SFXトリガー(竜の頭出現に同期していた音)を削除。竜が完全に無くなった
		# ため、この音を鳴らす対象自体が存在しない。"EOS phase materialize"の
		# ログ自体(0.25〜1.25秒窓の開始マーカー)は汎用のタイムライン計測用
		# なので無改修のまま維持。
	# 「approach_progress = 0.0」——接近が実際に始まる瞬間、ソティリスが
	# 敵へ踏み出すタイミングにwhooshを同期させる。
	if elapsed >= EOS_BURST_APPROACH_START_SECONDS and not _eos_burst_logged.has("EOS SFX dash"):
		_eos_burst_logged["EOS SFX dash"] = true
		_play_eos_burst_sfx("dash")
		# 「NO_DRAGON_NATURAL_SLASH_BURST v12」(2026-08-14) — 旧「roar」SFX
		# トリガー(竜オーラの咆哮、dashと完全同時に発火)を削除。README合格
		# 条件「竜専用の"roar"SFXが、キャストの一連の流れの中で1回も再生
		# されないこと」を、この呼び出し自体を消すことで満たす。
	if elapsed >= EOS_BURST_REVEAL_END_SECONDS:
		_eos_burst_log_at("EOS phase charge", elapsed)
	if elapsed >= EOS_BURST_REVEAL_END_SECONDS and not _eos_burst_logged.has("EOS completion shake"):
		_eos_burst_logged["EOS completion shake"] = true
		_battle_shake_t = EOS_BURST_COMPLETION_SHAKE_SECONDS
		_battle_shake_duration = EOS_BURST_COMPLETION_SHAKE_SECONDS
		_battle_shake_peak_px = EOS_BURST_COMPLETION_SHAKE_PEAK_PX
	if elapsed >= EOS_BURST_BEAM_START_SECONDS:
		_eos_burst_log_at("EOS phase release", elapsed)
	if elapsed >= EOS_BURST_HIT_AT_SECONDS:
		_eos_burst_log_at("EOS phase impact", elapsed)
	# 「frame1の圧縮光で約0.06秒のヒットストップを入れる」——一回だけの
	# トリガー(既存の_eos_burst_loggedガード・idiomを流用)。この関数は
	# ヒットストップが有効な間は_on_battle_anim_tickの早期returnにより
	# 一切呼ばれない(elapsedが凍結される)ため、再トリガーの心配が無い。
	# 実際のダメージ発火(hit_now)はヒットストップが自然に解け切った後の
	# 最初のtickで、このフラグとヒットストップ残量だけを見て判定する
	# (下のEOS_BURST_SKILL_ID分岐参照)——「ヒットストップ解除と同時に」
	# を、時刻の再計算なしにそのまま満たす。
	if elapsed >= EOS_BURST_HIT_AT_SECONDS and not _eos_burst_logged.has("EOS assault contact hitstop"):
		_eos_burst_logged["EOS assault contact hitstop"] = true
		_battle_hitstop_t = EOS_BURST_IMPACT_HITSTOP_SECONDS
		# 「Professional Mix / Impact Polish v1」(2026-08-07) — impact SFXの
		# 再生はここ(hitstop開始の瞬間)から、実際にdamage/巨大爆発/flash/
		# shakeが発火する_on_battle_anim_tickのhit_nowブロック
		# (`_eos_burst_assault_released()`が真になる、hitstop解除の瞬間)へ
		# 移設した——このHIT_AT到達の瞬間はまだhitstopの「予備動作」段階に
		# 過ぎず、README「damage+巨大爆発+hitstopが発火する実contactイベント
		# と完全同時にImpactを鳴らす」の対象ではないと判断したため。
	if elapsed >= EOS_BURST_VANISH_START_SECONDS:
		_eos_burst_log_at("EOS phase vanish", elapsed)
	if elapsed >= EOS_BURST_DISMISS_START_SECONDS:
		_eos_burst_log("EOS dismiss started")
	if elapsed >= EOS_BURST_DISMISS_END_SECONDS:
		_eos_burst_log("EOS dismiss complete")
	if elapsed >= EOS_BURST_RETURN_START_SECONDS:
		_eos_burst_log("EOS return started")
	if elapsed >= EOS_BURST_RETURN_END_SECONDS:
		_eos_burst_log("EOS returned home")


## Cleanup path — also reached when a cast is cut short.
func _reset_eos_burst_state() -> void:
	_eos_burst_approach_offset_px = 0.0
	_eos_burst_logged.clear()
	_eos_burst_contact_trigger_elapsed = -1.0
	# 「帰還開始時にカメラ倍率、UI透明度、背景色、キャラクターの描画状態を
	# 必ず元へ戻す」——elapsedベースのランプは通常RETURN_ENDまでに自然に
	# 1.0へ収束するが、キャストが途中で打ち切られた場合の安全策として
	# ここでも明示的に戻す("also reached when a cast is cut short")。
	_battle_bar.modulate.a = 1.0
	# 「Professional Mix / Impact Polish v1」(2026-08-07) — busのduckは
	# elapsed駆動で毎フレーム`_process`から書き戻されるが、キャストが
	# 途中で打ち切られた場合に備えここでも明示的に0dBへ戻す。
	_eos_burst_set_bus_duck_db(0.0)
	print("EOS VFX state reset")


## v18, layer C (欠けた魂の輪): same gapped-loop technique as the prior
## round's ring, rotated so the gap PATTERN's own orientation is tied to
## hit_angle — user spec: "亀裂の主軸はhit_angleに合わせる...完全な円で
## はなく4～6個に分断...ドット状・角張った輪郭にする" (dotted/angular,
## not a smooth line this time — small square studs instead of draw_line
## segments).
func _draw_soul_break_impact_ring(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_MAX_IMPACT_SECONDS \
			or elapsed >= SOUL_BREAK_MAX_IMPACT_SECONDS + SOUL_BREAK_IMPACT_RING_SECONDS:
		return
	var age := elapsed - SOUL_BREAK_MAX_IMPACT_SECONDS
	var grow_t := clampf(age / 0.05, 0.0, 1.0)
	var diameter := SOUL_BREAK_IMPACT_RING_PEAK_DIAMETER_PX * smoothstep(0.0, 1.0, grow_t)
	var fade_t := clampf(age / SOUL_BREAK_IMPACT_RING_SECONDS, 0.0, 1.0)
	var alpha := lerpf(0.85, 0.15, fade_t)
	var center := _soul_break_target_pos(view)
	var hit_angle := _soul_break_hit_dir(view, unit_id).angle()
	var radius := diameter * 0.5
	var studs := 20
	var gap_count := SOUL_BREAK_IMPACT_RING_GAP_COUNT
	var gap_width := 1.0 / float(gap_count) * 0.35
	for i in studs:
		var frac := float(i) / float(studs)
		var in_gap := false
		for g in gap_count:
			var gap_center := float(g) / float(gap_count)
			var d := absf(frac - gap_center)
			d = minf(d, 1.0 - d)
			if d < gap_width * 0.5:
				in_gap = true
				break
		if in_gap:
			continue
		var jitter := 1.0 + (_soul_break_jag(i * 7 + 3) - 0.5) * 0.14
		var angle := hit_angle + frac * TAU
		var pt := center + Vector2(cos(angle), sin(angle)) * radius * jitter
		_draw_soul_break_shard_square(pt, 3.0, angle, Color(0.53, 0.15, 0.85, alpha))


## v18, layer D (破片): reuses the existing shard-square helper, MOSTLY
## biased into a forward cone around hit_dir with a small minority
## scattering backward instead — user spec: "紫白の角張った魂片を8～12
## 個...hit_dirの前方に多く...後方にも少量だけ飛ばす...丸いパーティクル
## は禁止" (never draw_circle, only the existing angular shard helper).
func _draw_soul_break_impact_fragments(view: Rect2, unit_id: int, elapsed: float) -> void:
	var start_t := SOUL_BREAK_MAX_IMPACT_SECONDS + SOUL_BREAK_IMPACT_FRAGMENT_START_OFFSET_FROM_MAX
	if elapsed < start_t or elapsed >= start_t + SOUL_BREAK_IMPACT_FRAGMENT_SECONDS:
		return
	var age := elapsed - start_t
	var center := _soul_break_target_pos(view)
	var hit_angle := _soul_break_hit_dir(view, unit_id).angle()
	var backward_count := roundi(
		float(SOUL_BREAK_IMPACT_FRAGMENT_COUNT) * SOUL_BREAK_IMPACT_FRAGMENT_BACKWARD_FRAC)
	for i in SOUL_BREAK_IMPACT_FRAGMENT_COUNT:
		var lifetime := SOUL_BREAK_IMPACT_FRAGMENT_SECONDS \
			- _soul_break_jag(i * 3 + 11) * 0.05
		if age >= lifetime:
			continue
		var frac := age / lifetime
		var base_angle := hit_angle + PI if i < backward_count else hit_angle
		var spread_angle := base_angle \
			+ (_soul_break_jag(i * 5 + 2) - 0.5) * 2.0 * SOUL_BREAK_IMPACT_FRAGMENT_CONE_RAD
		var dir := Vector2(cos(spread_angle), sin(spread_angle))
		var spread := dir * SOUL_BREAK_IMPACT_FRAGMENT_SPREAD_PX * frac
		var perp := Vector2(-dir.y, dir.x)
		var drift := perp * SOUL_BREAK_IMPACT_FRAGMENT_DRIFT_PX \
			* (_soul_break_jag(i * 9 + 41) - 0.5) * frac
		var alpha := 1.0 - frac
		_draw_soul_break_shard_square(
			center + spread + drift, 2.0 + 2.0 * (1.0 - frac), spread_angle,
			Color(0.55, 0.2, 0.85, alpha))


## A thin quad segment between 2 points — the slash trail's own line unit
## (a vector draw_colored_polygon strip, not a raster asset; the "no
## circle/gradient" bans this skill otherwise follows are about avoiding
## smooth radial bursts, not thin connective line segments — the same
## technique _soul_break_needle_points already uses elsewhere in this
## file).
func _draw_soul_break_trail_quad(a: Vector2, b: Vector2, width: float, alpha: float) -> void:
	var dir := b - a
	if dir.length() < 0.01:
		return
	var perp := Vector2(-dir.y, dir.x).normalized()
	var pts := PackedVector2Array([
		a + perp * width * 0.5, b + perp * width * 0.5,
		b - perp * width * 0.5, a - perp * width * 0.5,
	])
	draw_colored_polygon(pts, Color(0.92, 0.85, 1.0, alpha))


## Fixed on-screen position for one of the 4 downswing key points (user
## spec: "SwordTip Marker2Dの位置から生成する" — reads a STABLE reference
## elapsed (SOUL_BREAK_LAUNCH_SECONDS, by which the caster's own step-in
## has already settled) rather than the CURRENT elapsed, so the trail's
## endpoints don't jitter as elapsed ticks forward within a single state's
## lifetime — same "decouple from live elapsed" pattern _draw_soul_break_
## flight already uses for its own start point).
func _soul_break_key_point_pos(view: Rect2, unit_id: int, key_index: int) -> Vector2:
	var base := _soul_break_caster_pos(view, unit_id, SOUL_BREAK_LAUNCH_SECONDS)
	var target := _soul_break_target_pos(view)
	var direction := signf(target.x - base.x)
	if direction == 0.0:
		direction = 1.0
	var off: Vector2 = SOUL_BREAK_SWING_TIP_OFFSETS[key_index]
	return base + Vector2(off.x * direction, off.y)


## v14: the projectile's OWN origin/pivot — user spec: "projectile_visual
## の原点を本体の後端にする...原点を剣先から進行方向へ12px進めた位置に
## 置く". Also doubles as the slash trail's own endpoint (user spec: "白
## い剣軌跡の終点と飛翔体の後端を同じ位置にする") and the muzzle-flash
## position — all 3 callers share this ONE function so they're byte-
## identical by construction rather than 3 separately-tuned numbers that
## could drift apart.
func _soul_break_proj_origin_pos(view: Rect2, unit_id: int) -> Vector2:
	var tip := _soul_break_sword_tip_pos(view, unit_id, SOUL_BREAK_LAUNCH_SECONDS)
	var target := _soul_break_target_pos(view)
	var facing := signf(target.x - tip.x)
	if facing == 0.0:
		facing = 1.0
	return tip + Vector2(SOUL_BREAK_PROJ_SPAWN_OFFSET_X_PX * facing, 0.0)


## v17-fix: the ONE shared attack direction — user spec: "発射・飛翔・着
## 弾・破片・ノックバックまですべて同じhit_dir/hit_angleを使用してくださ
## い". Computed from _soul_break_proj_origin_pos/_soul_break_target_pos,
## the SAME 2 points _draw_soul_break_flight already uses for its own
## lerp — both are stable for the whole cast (the origin reads a FIXED
## elapsed instant, the target reads the boss's on-screen rect, which
## doesn't move mid-battle), so calling this again during the impact
## phase yields the byte-identical vector flight itself used, without
## needing a separate captured/frozen state variable — this is what
## structurally prevents flight and impact from ever reading different
## angles again, rather than relying on remembering to keep 2 numbers in
## sync by hand.
func _soul_break_hit_dir(view: Rect2, unit_id: int) -> Vector2:
	var start := _soul_break_proj_origin_pos(view, unit_id)
	var target := _soul_break_hit_target_pos(view)
	var dir := target - start
	return dir.normalized() if dir.length() > 0.01 else Vector2(1.0, 0.0)


## v18: _soul_break_impact_anchor_pos (v17-fix's "center impact on the
## penetration end point") is RETIRED — user spec section 7 explicitly
## reverses this: "貫通終了位置を着弾演出の中心にせず、敵の胴体中央を破
## 壊エフェクトの中心にしてください". All 4 impact layers now anchor at
## _soul_break_target_pos (the TRUE, un-offset enemy center) directly —
## only their ORIENTATION still reads hit_angle, not their position.


## Thin broken arc between 2 fixed points (user spec: "細く欠けた円弧に
## する...最大サイズは約48×32px...軌跡の太さは4〜6px以内...塗りつぶした
## 扇形にしない...太い白い半月にしない"). Unlike a filled fan/pie-slice,
## this is a chain of separate thin quads tracing a bowed curve — no wide
## base near the origin, no closed silhouette. `break_gaps` punches ~3
## holes along the curve for the "3か所ほど千切れて消える" fading state.
func _draw_soul_break_trail_arc(
		a: Vector2, b: Vector2, bow_frac: float, width: float, color: Color, alpha: float,
		break_gaps: bool) -> void:
	var path := b - a
	if path.length() < 1.0:
		return
	var perp := Vector2(-path.y, path.x).normalized()
	var control := (a + b) * 0.5 + perp * path.length() * bow_frac
	var steps := 12
	var prev := a
	var prev_valid := true
	var gaps := [0.22, 0.5, 0.78]
	for i in range(1, steps + 1):
		var s := float(i) / float(steps)
		var in_gap := false
		if break_gaps:
			for g in gaps:
				if absf(s - g) < 0.07:
					in_gap = true
					break
		var p := _soul_break_bezier_point(a, control, b, s)
		if not in_gap and prev_valid:
			_draw_soul_break_trail_quad(prev, p, width, alpha)
		prev = p
		prev_valid = not in_gap


## Slash trail, v10 full redesign (user spec: "現在の塗りつぶされた大きな
## 白い半円は削除する...1フレーム目：短く薄い紫白の軌跡／2フレーム目：最
## 長。白い2〜3pxの核＋薄紫の外縁／3フレーム目：途中が3か所ほど千切れて
## 消える"). 3 DISTINCT states gated by the trail consts' own timing (see
## their doc comment) — NOT a continuously-interpolated single shape.
## State 1's endpoints are the FIXED downswing key points (index 0=頭上,
## 1=顔の横). States 2/3's "b" endpoint is v14's shared _soul_break_proj_
## origin_pos (user spec: "白い剣軌跡の終点と飛翔体の後端を同じ位置にす
## る") instead of key index 3 directly — both used to evaluate to the
## same value, but v14 moved the projectile's own origin 12px further
## along the facing direction than the bare sword-tip key point, so this
## trail needs to follow that same point to stay literally coincident.
func _draw_soul_break_slash_trail(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_TRAIL_START_SECONDS or elapsed >= SOUL_BREAK_TRAIL_END_SECONDS:
		return
	if elapsed < SOUL_BREAK_TRAIL_PEAK_SECONDS:
		# State 1: short, thin, pale purple-white — overhead to 顔の横.
		var a := _soul_break_key_point_pos(view, unit_id, 0)
		var b := _soul_break_key_point_pos(view, unit_id, 1)
		_draw_soul_break_trail_arc(a, b, 0.18, 2.5, Color(0.75, 0.65, 0.9, 1.0), 0.5, true)
	elif elapsed < SOUL_BREAK_TRAIL_BREAK_SECONDS:
		# State 2: PEAK, synced with launch (user spec: "現在の大きな白い
		# 扇形は面積を約40%減らす...内部が透明な白紫の途切れた2本の軌跡
		# にする" — TWO separate thin, BROKEN strands offset perpendicular
		# from each other, replacing the old single 6px-wide double-layer
		# arc that drew all 12 segments solid with no gaps — THAT'S what
		# actually read as a filled fan, see this const block's own doc
		# comment). ~43% less painted area than the old version (9 gapped
		# segments x ~6.5px combined width vs 12 solid segments x 8.5px).
		var a := _soul_break_key_point_pos(view, unit_id, 1)
		var b := _soul_break_proj_origin_pos(view, unit_id)
		var path := b - a
		var perp := Vector2(-path.y, path.x).normalized() if path.length() > 0.01 else Vector2.ZERO
		_draw_soul_break_trail_arc(
			a + perp * 3.5, b + perp * 3.5, 0.13, 4.0, Color(0.85, 0.75, 0.95, 1.0), 0.55, true)
		_draw_soul_break_trail_arc(
			a - perp * 2.5, b - perp * 2.5, 0.17, 2.5, Color(0.98, 0.96, 1.0, 1.0), 0.7, true)
	else:
		# State 3: same 2-strand shape, broken further and fading.
		var a := _soul_break_key_point_pos(view, unit_id, 1)
		var b := _soul_break_proj_origin_pos(view, unit_id)
		var path := b - a
		var perp := Vector2(-path.y, path.x).normalized() if path.length() > 0.01 else Vector2.ZERO
		_draw_soul_break_trail_arc(
			a + perp * 3.5, b + perp * 3.5, 0.13, 3.0, Color(0.75, 0.65, 0.9, 1.0), 0.25, true)
		_draw_soul_break_trail_arc(
			a - perp * 2.5, b - perp * 2.5, 0.17, 2.0, Color(0.85, 0.8, 0.95, 1.0), 0.3, true)


## v14: a small 2-frame launch spark (user spec: "剣軌跡が消えるフレーム
## で、剣先に小さな紫白の発射光を2フレーム表示する") at the shared
## origin point, timed to fire exactly as the slash trail's own window
## ends — a small code-drawn diamond flash, not a raster asset (no new
## art delivered for this specific beat, and it's simple/small enough that
## a vector shape reads fine at this scale, same judgment call rapid_
## slash's own landing-spark used).
func _draw_soul_break_muzzle_flash(view: Rect2, unit_id: int, elapsed: float) -> void:
	if elapsed < SOUL_BREAK_MUZZLE_FLASH_START_SECONDS \
			or elapsed >= SOUL_BREAK_MUZZLE_FLASH_END_SECONDS:
		return
	var origin := _soul_break_proj_origin_pos(view, unit_id)
	var outer := PackedVector2Array([
		origin + Vector2(-6.0, 0.0), origin + Vector2(0.0, -4.0),
		origin + Vector2(7.0, 0.0), origin + Vector2(0.0, 4.0),
	])
	draw_colored_polygon(outer, Color(0.95, 0.9, 1.0, 0.85))
	var inner := PackedVector2Array([
		origin + Vector2(-3.0, 0.0), origin + Vector2(0.0, -2.0),
		origin + Vector2(3.5, 0.0), origin + Vector2(0.0, 2.0),
	])
	draw_colored_polygon(inner, Color(1.0, 0.98, 1.0, 1.0))


## Front-layer dispatcher — called AFTER _draw_party_row, same position
## rapid_slash's/healing's own front dispatchers occupy. Every soul_break
## element is "in front" (nothing in this skill's spec asks for a behind-
## the-character layer the way healing's magic circle does). v16: the
## rapid_slash 5-stage structure port — see this function's own new call
## order below for stage 1 (tip light) through stage 6 (aftermath
## debris). _draw_soul_break_impact (the old single-layer 18-frame-only
## dispatch) is retired; the SAME delivered asset now plays via _draw_
## soul_break_outer_crack instead, as one of 3 simultaneous impact layers.
func _draw_soul_break_vfx(view: Rect2) -> void:
	if not _soul_break_vfx_active():
		return
	var entry: Dictionary = _battle_anim_queue[_battle_anim_step]
	var unit_id := int(entry.get("unit_id", 0))
	var elapsed := _battle_anim_phase_elapsed
	_draw_soul_break_gather(view, unit_id, elapsed)
	_draw_soul_break_core_compress(view, unit_id, elapsed)
	_draw_soul_break_tip_light(view, unit_id, elapsed)
	_draw_soul_break_slash_trail(view, unit_id, elapsed)
	_draw_soul_break_muzzle_flash(view, unit_id, elapsed)
	_draw_soul_break_launch_arc(view, unit_id, elapsed)
	_draw_soul_break_afterimages(elapsed)
	_draw_soul_break_separation(view, unit_id, elapsed)
	_draw_soul_break_flight(view, unit_id, elapsed)
	_draw_soul_break_impact_line(view, unit_id, elapsed)
	_draw_soul_break_impact_ring(view, unit_id, elapsed)
	_draw_soul_break_impact_fragments(view, unit_id, elapsed)
	# NOTE: the broken X-cross is deliberately NOT drawn here — it runs in
	# _draw_soul_break_top_layer, after the shared screen flash. See that
	# function's own doc comment.


## Immediately blanks one wave (user spec item 1: "各waveはtarget_position
## へ到着した瞬間にactive=falseにする") — the actual fix for the "stuck
## crescent" bug: _draw_rapid_slash_wave's gate checks active (see its own
## doc comment), so once this runs a wave can never be drawn again, however
## long the round has left to play. Guarded on the PRIOR active state so
## calling it twice (natural arrival, then the impact-start safety sweep in
## _start_rapid_impact) logs "deactivated" exactly once, not twice.
func _deactivate_rapid_wave(w: Dictionary) -> void:
	if bool(w["active"]):
		w["active"] = false
		w["arrived"] = true
		_rapid_slash_debug_log("RAPID %s deactivated" % str(w["label"]))


## User spec item 4: force every wave inactive the instant the X-impact
## begins — belt-and-suspenders on top of item 1's per-wave deactivation
## (by design all 3 should already be arrived/inactive by this point, since
## wave_c's own arrive_time IS RAPID_SLASH_IMPACT_FRAMES' first breakpoint,
## checked earlier in the SAME tick — but this guarantees it regardless of
## any future re-timing that breaks that coincidence).
func _start_rapid_impact() -> void:
	for w: Dictionary in _rapid_slash_waves:
		_deactivate_rapid_wave(w)
	_rapid_slash_debug_log("RAPID all waves cleared before impact")
	_rapid_impact_active = true
	_rapid_impact_elapsed = 0.0
	_rapid_slash_debug_log("RAPID impact started")
	# README: "rapidslash_cross.wav | X字形成音 | 1.22秒" — this function
	# only ever runs once per cast (guarded by _rapid_slash_impact_started
	# at its own call site).
	_play_rapid_sfx("cross")


## Advances every wave in _rapid_slash_waves by one tick (called from
## _on_battle_anim_tick's "act" case, so geometry queries like _view_rect()
## are safe here — same reasoning _launch_battle_projectile already
## established for the generic projectile system). Each wave's start_pos/
## target_pos/rotation are captured ONCE, at that wave's own launch_time,
## and never recomputed afterward — so 3 genuinely different trajectories
## exist simultaneously (distinct y_offset endpoints), not 3 draws of the
## same lerp sampled at 3 slightly different times (the original "looks
## like 1 VFX" bug). This round's fix is entirely about what happens AFTER
## arrival — see _deactivate_rapid_wave/_start_rapid_impact above.
func _update_rapid_slash_waves(dt: float, elapsed: float) -> void:
	var view := _view_rect()
	# User spec item 1: charge is visible starting here...
	if not _rapid_charge_active and elapsed >= RAPID_SLASH_CHARGE_START_SECONDS \
			and elapsed < RAPID_SLASH_CHARGE_END_SECONDS:
		_rapid_charge_active = true
	if _rapid_recoil_t > 0.0:
		_rapid_recoil_t = maxf(0.0, _rapid_recoil_t - dt)
	if _rapid_debris_t > 0.0:
		_rapid_debris_t = maxf(0.0, _rapid_debris_t - dt)
	for w: Dictionary in _rapid_slash_waves:
		if float(w.get("spark_t", 0.0)) > 0.0:
			w["spark_t"] = maxf(0.0, float(w["spark_t"]) - dt)
		var launch_time := float(w["launch_time"])
		if not bool(w["active"]):
			if bool(w["arrived"]) or elapsed < launch_time:
				continue
			w["active"] = true
			var start := _rapid_slash_sword_tip_pos(view, elapsed)
			var target_x := _rapid_slash_target_x_px(view)
			var direction := signf(target_x - start.x)
			var boss_rect := _boss_icon_rect(view)
			var target := Vector2(
				target_x - direction * RAPID_SLASH_WAVE_IMPACT_OFFSET_PX,
				boss_rect.position.y + boss_rect.size.y * 0.5 + float(w["y_offset"]))
			w["start_pos"] = start
			w["target_pos"] = target
			w["rotation"] = (target - start).angle()
			w["progress"] = 0.0
			w["animation_frame"] = 0
			# User spec item 4: a tiny per-launch position kick.
			_rapid_recoil_t = RAPID_SLASH_RECOIL_SECONDS
			_rapid_recoil_peak_px = float(w["recoil_px"])
			# User spec item 1: ...and ends EXACTLY here, at wave_a's own
			# launch — an explicit event, not an inferred time-window edge.
			if str(w["label"]) == "wave_a":
				_rapid_charge_active = false
			_rapid_slash_debug_log("RAPID %s launched" % str(w["label"]))
			# README: slash_1/2/3 each fire once, exactly at their own
			# wave's launch — this whole branch already only runs once per
			# wave (the "active" flip itself is the one-shot guard).
			var sfx_key: String = str(RAPID_SLASH_SFX_SLASH_KEY_BY_LABEL.get(str(w["label"]), ""))
			if sfx_key != "":
				_play_rapid_sfx(sfx_key)
		if bool(w["arrived"]):
			continue
		var arrive_time := float(w["arrive_time"])
		var dur := maxf(0.001, arrive_time - launch_time)
		var t := clampf((elapsed - launch_time) / dur, 0.0, 1.0)
		# ease_out (user spec: "補間は一定速ではなくease_outを使用して...
		# ただし発射直後から一瞬で敵へ到達させないでください") — see
		# RAPID_SLASH_WAVE_EASE_OUT_POWER's doc comment for the curve choice.
		var eased := 1.0 - pow(1.0 - t, RAPID_SLASH_WAVE_EASE_OUT_POWER)
		w["progress"] = eased
		var key := str(w["key"])
		var frame_count := maxi(1, art.frame_count(key))
		w["animation_frame"] = mini(int(eased * float(frame_count)), frame_count - 1)
		if elapsed >= arrive_time:
			# User spec item 3: a short spark on arrival — set BEFORE
			# deactivating (spark_t is independent of active/arrived, see
			# _draw_rapid_slash_vfx's spark loop).
			w["spark_t"] = RAPID_SLASH_SPARK_SECONDS
			_rapid_slash_debug_log("RAPID %s arrived" % str(w["label"]))
			_deactivate_rapid_wave(w)
	if not _rapid_slash_impact_started \
			and elapsed >= float(RAPID_SLASH_IMPACT_FRAMES[0][0]):
		_rapid_slash_impact_started = true
		_start_rapid_impact()
	if _rapid_impact_active:
		_rapid_impact_elapsed += dt
		if elapsed >= RAPID_SLASH_IMPACT_END_SECONDS:
			_rapid_impact_active = false
			_rapid_slash_debug_log("RAPID impact finished")
	# README: "rapidslash_sparks.wav | 金色の余韻 | 1.50秒" — the only one
	# of the 7 SFX with no existing one-shot event to attach to.
	if not _rapid_sfx_sparks_played and elapsed >= RAPID_SLASH_SFX_SPARKS_SECONDS:
		_rapid_sfx_sparks_played = true
		_play_rapid_sfx("sparks")


func _rapid_slash_impact_frame_index(elapsed: float) -> int:
	var result := -1
	for pair: Array in RAPID_SLASH_IMPACT_FRAMES:
		if elapsed >= float(pair[0]):
			result = int(pair[1])
		else:
			break
	return result


## Draws one wave from its OWN held state — never recomputes position from
## elapsed time (see _update_rapid_slash_waves' doc comment). Rotated to
## face its own travel direction (start_pos -> target_pos), so wave_b's
## slightly-upward path and wave_a's near-horizontal one visibly read as
## different throws, not just different sizes on the same line.
func _draw_rapid_slash_wave(w: Dictionary) -> void:
	if not bool(w["active"]):
		return
	var key := str(w["key"])
	if not art.has_art(key):
		return
	var tex := art.frame(key, int(w["animation_frame"]))
	var start: Vector2 = w["start_pos"]
	var target: Vector2 = w["target_pos"]
	var pos := start.lerp(target, float(w["progress"]))
	var draw_px := float(w["draw_px"])
	var draw_size := Vector2(draw_px, draw_px)
	var prev_filter := texture_filter
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	draw_set_transform(pos, float(w["rotation"]), Vector2.ONE)
	draw_texture_rect(tex, Rect2(-draw_size / 2.0, draw_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	texture_filter = prev_filter


## Small code-drawn spark at a wave's own arrival point (no dedicated spark
## asset delivered this round — see RAPID_SLASH_SPARK_SECONDS' doc
## comment). Deliberately NOT the shared _draw_battle_impact burst (that
## one fires damage/knockback; this is purely a landing flourish, no
## gameplay effect, 3 of them can be on screen at once).
func _draw_rapid_slash_spark(pos: Vector2, t: float) -> void:
	if t <= 0.0:
		return
	var frac := t / RAPID_SLASH_SPARK_SECONDS
	var color := Color(1.0, 0.95, 0.75, frac)
	var radius := RAPID_SLASH_SPARK_RADIUS_PX * (0.4 + 0.6 * (1.0 - frac))
	for i in 6:
		var angle := TAU * float(i) / 6.0
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(pos, pos + dir * radius, color, 2.0)
	draw_circle(pos, radius * 0.3, Color(1.0, 1.0, 1.0, frac))


## Post-explosion debris (user spec item 6): drifts up, spreads outward,
## fades — 3 motions a static sprite frame can't provide on its own, layered
## on top of (not replacing) the delivered impact clip's own F6-F8 tail.
func _draw_rapid_slash_debris(view: Rect2) -> void:
	if _rapid_debris_t <= 0.0:
		return
	var frac := _rapid_debris_t / RAPID_SLASH_DEBRIS_SECONDS  # 1 -> 0
	var age := 1.0 - frac  # 0 -> 1 as the burst ages
	var rect := _boss_icon_rect(view)
	var center := Vector2(rect.position.x + rect.size.x * 0.3, rect.position.y + rect.size.y * 0.5)
	var color := Color(1.0, 0.85, 0.35, frac)
	for i in RAPID_SLASH_DEBRIS_COUNT:
		var angle := TAU * float(i) / float(RAPID_SLASH_DEBRIS_COUNT) + 0.3
		var dir := Vector2(cos(angle), sin(angle))
		var spread := dir * RAPID_SLASH_DEBRIS_SPREAD_PX * age
		var drift := Vector2(0.0, -RAPID_SLASH_DEBRIS_DRIFT_PX * age)
		draw_circle(center + spread + drift, 1.0 + 2.5 * frac, color)


## rapid_slash VFX (2026-07-26): the sword charge glow, the 3
## independently-STATEFUL flying waves (drawn from _rapid_slash_waves — all
## 3 in the same frame when their windows overlap, never a single
## overwritten "current" key), their landing sparks, the X-shape impact,
## and the post-explosion debris. No round muzzle flash at launch — removed
## per user report ("剣で斬撃を飛ばしているのではなく、魔法の光球を発射し
## ているように見えます"), no replacement shape added (see RAPID_SLASH_
## SWORD_TIP_OFFSET_PX's doc comment for why). Dust
## is drawn separately (see _draw_rapid_slash_dust's own doc comment on WHY
## it can't live in this function).
func _draw_rapid_slash_vfx(view: Rect2) -> void:
	if not _rapid_slash_vfx_active():
		return
	var elapsed := _battle_anim_phase_elapsed
	var prev_filter := texture_filter

	# Charge glow: gated on the explicit _rapid_charge_active bool (user
	# spec item 1), not an elapsed-time window — see RAPID_SLASH_CHARGE_
	# END_SECONDS' doc comment for why the window-based cutoff wasn't
	# reliable enough on its own.
	if _rapid_charge_active and art.has_art(RAPID_SLASH_CHARGE_KEY):
		# Sword charge glow, at the caster's own blade — never at the boss.
		var frame_count := art.frame_count(RAPID_SLASH_CHARGE_KEY)
		var frame := mini(
			int(maxf(0.0, elapsed - RAPID_SLASH_CHARGE_START_SECONDS) / RAPID_SLASH_CHARGE_FRAME_SECONDS),
			frame_count - 1)
		var tex := art.frame(RAPID_SLASH_CHARGE_KEY, frame)
		var center := _rapid_slash_sword_tip_pos(view, elapsed)
		var draw_size := Vector2(RAPID_SLASH_CHARGE_DRAW_PX, RAPID_SLASH_CHARGE_DRAW_PX)
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		draw_texture_rect(tex, Rect2(center - draw_size / 2.0, draw_size), false)
		texture_filter = prev_filter

	# User spec's exact draw gate (items 2/5/6): active AND not-yet-arrived
	# AND impact hasn't started — a wave that's landed, or that impact has
	# forcibly cleared, is never drawn again, however long the round has
	# left to run. This is the actual fix for the "stuck crescent" bug —
	# _draw_rapid_slash_wave's own body only checked "active" before, which
	# an arrived-but-never-deactivated wave still satisfied forever.
	for w: Dictionary in _rapid_slash_waves:
		if bool(w.get("active", false)) \
				and not bool(w.get("arrived", false)) \
				and not _rapid_impact_active:
			_draw_rapid_slash_wave(w)
	for w: Dictionary in _rapid_slash_waves:
		if bool(w["arrived"]):
			var target: Vector2 = w["target_pos"]
			_draw_rapid_slash_spark(target, float(w.get("spark_t", 0.0)))

	if elapsed >= float(RAPID_SLASH_IMPACT_FRAMES[0][0]) and elapsed < RAPID_SLASH_IMPACT_END_SECONDS \
			and art.has_art(RAPID_SLASH_IMPACT_KEY):
		# X-shape impact, fixed at the boss's own center — the asset's own
		# 8 frames bake in the size/intensity growth; never scaled here
		# (user spec: "爆発画像をコードで110%へ拡大しない").
		var frame := _rapid_slash_impact_frame_index(elapsed)
		if frame >= 0:
			var tex := art.frame(RAPID_SLASH_IMPACT_KEY, frame)
			var rect := _boss_icon_rect(view)
			var center := Vector2(
				rect.position.x + rect.size.x * 0.3, rect.position.y + rect.size.y * 0.5)
			var draw_size := Vector2(RAPID_SLASH_IMPACT_DRAW_PX, RAPID_SLASH_IMPACT_DRAW_PX)
			texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			draw_texture_rect(tex, Rect2(center - draw_size / 2.0, draw_size), false)
			texture_filter = prev_filter

	_draw_rapid_slash_debris(view)


## Code-drawn impact burst at the hit point (no effect sprites exist yet;
## the attack rows' slash arcs are baked into the character cells, this
## adds the "landing on the enemy" half): radial spikes + a ring,
## expanding and fading over ~0.3s. Positioned toward the boss icon's
## near (left) edge, where a melee swing actually connects.
func _draw_battle_impact(_view: Rect2) -> void:
	if _battle_impact_t <= 0.0:
		return
	var center := _battle_impact_pos
	# Elemental burst clip (asset pack): plays exactly once at the hit
	# point, gone after its last frame (README) — frame index rides the
	# same decaying t the code burst uses.
	if _battle_impact_key != "" and art.has_art(_battle_impact_key):
		var frames := art.frame_count(_battle_impact_key)
		var tex := art.frame(
			_battle_impact_key, mini(int((1.0 - _battle_impact_t) * frames), frames - 1))
		var half := BATTLE_IMPACT_SPRITE_PX / 2.0
		draw_texture_rect(
			tex,
			Rect2(center - Vector2(half, half),
				Vector2(BATTLE_IMPACT_SPRITE_PX, BATTLE_IMPACT_SPRITE_PX)),
			false)
		return
	var grow := 1.0 - _battle_impact_t
	var radius := BATTLE_IMPACT_RADIUS_PX * (0.45 + 0.55 * grow)
	var color := COLOR_IMPACT
	color.a = _battle_impact_t
	for i in 8:
		var angle := TAU * float(i) / 8.0 + 0.4
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(center + dir * radius * 0.45, center + dir * radius, color, 3.0)
	draw_arc(center, radius * 0.6, 0.0, TAU, 20, color, 2.0)


func _draw_debug_boss_loop_badge(view: Rect2) -> void:
	draw_string(
		ThemeDB.fallback_font, Vector2(view.position.x + 12, view.position.y + 20),
		"TEST MODE (F9): boss auto-restarts on win/loss",
		HORIZONTAL_ALIGNMENT_LEFT, view.size.x, 13, STRIP_BADGE)


## Plays the old won/lost/continue tail once the motion queue is empty —
## unchanged from before the sequencer existed except it now reads the
## result stashed by _on_boss_resolve_round instead of a fresh local, and
## _debug_boss_loop reopens the same encounter instead of returning to the
## map.
func _finish_battle_round() -> void:
	var result := _battle_pending_round_result
	_stop_battle_anim()
	if result.get("won", false):
		_tally_text = locale.text("UI_BOSS_WON")
		_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
		if _debug_boss_loop:
			_restart_debug_boss_loop()
			return
		_hide_boss_panel()
		_refresh_fight_button()
		queue_redraw()
		return
	if result.get("lost", false):
		# 新企画v1 §10: a party wipe no longer ends the encounter — sim
		# already rewound itself back to the fight's checkpoint inside
		# resolve_boss_round() (result["rewound"] == true), so boss_active
		# is still true here and the fight simply restarts in place.
		if result.get("rewound", false):
			# 全滅による自動REWINDも、任意REWIND（_do_battle_rewind）と同じ
			# 「表示中のメッセージをクリアして仕切りを表示」扱いにする——
			# トリガーが自動か手動かでプレイヤーへ見せる情報が変わっては
			# いけない。
			_clear_battle_message()
			_append_battle_message(locale.text("UI_BATTLE_MSG_REWIND_DIVIDER"), "special")
		_tally_text = locale.text("UI_REWIND_LOST" if result.get("rewound", false) else "UI_BOSS_LOST")
		_tally_until_tick = sim.tick_count + TALLY_SHOW_TICKS * 2
		if _debug_boss_loop:
			_restart_debug_boss_loop()
			return
		if sim.boss_active:
			_battle_pending_actions = {}
			_battle_selected_unit = -1
			_battle_selected_target_id = ""
			_battle_selected_ally_target = -1
			_enter_command_selection()
			_refresh_boss_panel()
			queue_redraw()
			return
		_hide_boss_panel()
		queue_redraw()
		return
	_enter_command_selection()
	_refresh_boss_panel()


## _debug_boss_loop's whole trick: start_boss_fight() reopens a fresh
## rematch against the just-cleared gate's boss on a WIN (existing, tested
## sim behavior, see test_cleared_gate_boss_can_be_rematched); on a LOSS
## (新企画v1 §10, 2026-08-18) the sim has already rewound the same
## encounter back to its checkpoint by itself (boss_active stays true), so
## start_boss_fight() here is a harmless no-op (it refuses to start while
## already active) and this function's real job on that path is just
## resetting the UI's own pending-action state. Either way this calls it
## again immediately instead of waiting for the player to press 挑む/再戦/
## REWIND, so the boss is effectively unkillable for as long as F9 stays on.
func _restart_debug_boss_loop() -> void:
	_debug_restore_party()
	sim.start_boss_fight()
	_battle_pending_actions = {}
	_battle_selected_unit = -1
	_battle_selected_target_id = ""
	_battle_selected_ally_target = -1
	_enter_command_selection()
	_refresh_boss_panel()
	queue_redraw()


## The animation frames shipped for a dialog backdrop key (dialog_bg_*),
## in order: the base PNG plus any _f2/_f3/… siblings. One entry means a
## static backdrop; drop in _fN files to make it loop (e.g. a flickering
## candle in the archive). Reuses the same frame convention as sprites.
func _dialog_bg_frames(key: String) -> Array:
	var frames: Array = []
	for i in art.frame_count(key):
		frames.append(art.frame(key, i))
	return frames


func _build_archive_dialog() -> void:
	_archive_dialog = UDCardDialog.create(locale.text("UI_ARCHIVE"), false)
	_archive_dialog.card_selected.connect(_on_archive_card_selected)
	_archive_dialog.back_pressed.connect(_show_archive_series_shelf)
	_archive_dialog.set_background_frames(_dialog_bg_frames("dialog_bg_archive"))
	_archive_dialog.enable_art_chrome(locale.text("UI_ARCHIVE"), locale.text("UI_CLOSE"))
	add_child(_archive_dialog)


func _build_treasure_dialog() -> void:
	_treasure_dialog = UDCardDialog.create(locale.text("UI_TREASURES"), false)
	_treasure_dialog.card_selected.connect(_on_treasure_card_selected)
	_treasure_dialog.back_pressed.connect(_show_treasure_rank_shelf)
	_treasure_dialog.set_background_frames(_dialog_bg_frames("dialog_bg_treasure"))
	_treasure_dialog.enable_art_chrome(locale.text("UI_TREASURES"), locale.text("UI_CLOSE"))
	add_child(_treasure_dialog)


## Two-level treasure shelf (same UX as the archive): the shelf shows
## one card per rank (Z/S/A/B/C/D), opening a rank lists its items as
## owned cards or locked ????? slots.
func _open_treasures() -> void:
	if settings.resident_mode:
		_expand()
	_show_treasure_rank_shelf()
	_treasure_dialog.open()


func _rank_item_ids(rank: String) -> Array[String]:
	var ids: Array[String] = []
	for item_id in item_db.all_ids():
		if item_db.rank(item_id) == rank:
			ids.append(item_id)
	return ids


func _show_treasure_rank_shelf() -> void:
	_treasure_rank = ""
	_treasure_dialog.clear_cards()
	for rank in UD.ITEM_RANKS:
		var item_ids := _rank_item_ids(rank)
		if item_ids.is_empty():
			continue
		var owned := 0
		for item_id in item_ids:
			if sim.item_count(item_id) > 0:
				owned += 1
		_treasure_dialog.add_card(
			rank, locale.text("UI_RANK_LABEL") % rank, "%d / %d" % [owned, item_ids.size()],
			art.icon_or_placeholder("item_rank_%s" % rank, rank, "gem"), false
		)
	_treasure_dialog.set_back(locale.text("UI_BACK"), false)
	_treasure_dialog.set_progress(
		locale.text("UI_PROGRESS_ITEMS") % [sim.distinct_items(), item_db.all_ids().size()]
	)
	# Same as the archive shelf: nothing is selected here (rank cards just
	# drill in), so drop the detail panel instead of showing a hint no one
	# asked for yet.
	_treasure_dialog.set_detail_visible(false)


func _show_treasure_rank(rank: String) -> void:
	_treasure_rank = rank
	_treasure_dialog.clear_cards()
	var item_ids := _rank_item_ids(rank)
	var owned := 0
	for item_id in item_ids:
		var is_owned := sim.item_count(item_id) > 0
		if is_owned:
			owned += 1
		var icon := art.icon_or_placeholder("item_%s" % item_id, item_id, "gem")
		var title_text := locale.text(item_db.get_item(item_id)["name_key"]) \
			if is_owned else ""
		var subtitle := "×%d" % sim.item_count(item_id) if is_owned else ""
		_treasure_dialog.add_card(item_id, title_text, subtitle, icon, not is_owned)
	_treasure_dialog.set_back(locale.text("UI_BACK"), true)
	_treasure_dialog.set_progress(
		"%s   %d / %d" % [locale.text("UI_RANK_LABEL") % rank, owned, item_ids.size()]
	)
	_treasure_dialog.set_detail_visible(true)
	_treasure_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	var first := _treasure_dialog.first_unlocked_id()
	if first != "":
		_treasure_dialog.select_card(first)


func _on_treasure_card_selected(card_id: String) -> void:
	if _treasure_rank == "":
		_show_treasure_rank(card_id)
		return
	var item := item_db.get_item(card_id)
	var body := locale.text(item["desc_key"])
	body += "\n\n[b]%s: %s[/b]   ×%d / %d" % [
		locale.text("UI_RANK"), item_db.rank(card_id),
		sim.item_count(card_id), sim.item_cap(card_id),
	]
	_treasure_dialog.show_detail(
		locale.text(item["name_key"]), body,
		art.icon_or_placeholder("item_%s" % card_id, card_id, "gem")
	)


## --- Shop (weapon shop + item trading) ---------------------------------
## Fully art-driven, like the guild: dialog_bg_shop.png bakes in its own
## title, four signed counters, and a close plaque, so the dialog runs
## with its native OK/titlebar-X hidden (hide_native_chrome()) and the
## art's own click targets do the navigating. The mockup's second (gem)
## currency was placeholder decoration and was never shipped — only the
## real coin count is live, overlaid on the coin badge's number.
## pickaxe/survey (the old shop_db goods) are retired as of this redesign
## (2026-07-15): atk now grows only through leveling and the weapon
## below; document_chance_bonus()'s equivalent moved to the altar.

var _shop_mode: String = ""

## dialog_bg_shop.png has 160px of solid padding above its original top
## edge (2026-07-15, reduced from an earlier 280px): the background
## fills the whole dialog regardless of the detail panel, and
## STRETCH_KEEP_ASPECT_COVERED's centered crop slices a chunk off both
## top and bottom at typical dialog sizes — enough top padding to keep
## the coin badge and close plaque on screen, but no more than that,
## since every extra pixel of top padding taxes the *bottom* crop too
## (280px was cutting the rug/floor row off entirely). Rects below are
## normalized against the padded 1536x1184 image.
const SHOP_BUY_WEAPON_HOTSPOT := Rect2(0.0052, 0.2889, 0.2174, 0.0777)
const SHOP_UPGRADE_WEAPON_HOTSPOT := Rect2(0.0052, 0.4037, 0.2174, 0.0777)
const SHOP_BUY_ITEM_HOTSPOT := Rect2(0.0052, 0.5186, 0.2174, 0.0777)
const SHOP_SELL_ITEM_HOTSPOT := Rect2(0.0052, 0.6368, 0.2174, 0.0777)
const SHOP_CLOSE_HOTSPOT := Rect2(0.7982, 0.1478, 0.1888, 0.0676)
const SHOP_GOLD_OVERLAY := Rect2(0.0534, 0.1537, 0.1452, 0.0405)
const SHOP_GOLD_COLOR := Color(0.95, 0.82, 0.55)


func _build_shop_dialog() -> void:
	_shop_dialog = UDCardDialog.create(locale.text("UI_SHOP"), true)
	_shop_dialog.card_selected.connect(_on_shop_card_selected)
	_shop_dialog.action_pressed.connect(_on_shop_action)
	_shop_dialog.back_pressed.connect(_show_shop_front)
	_shop_dialog.set_background_frames(_dialog_bg_frames("dialog_bg_shop"))
	_shop_dialog.hide_native_chrome()
	_shop_dialog.set_frame_visible(false)
	add_child(_shop_dialog)


func _open_shop() -> void:
	if settings.resident_mode:
		_expand()
	_show_shop_front()
	_shop_dialog.open()


## Digit-group a coin amount ("123456" -> "123,456"); RES_GOLD has no
## symbol prefix in this game, so plain grouping is all formatting needs.
func _format_gold(amount: int) -> String:
	var digits := str(amount)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


## Landing page: the four signed counters ("武器の購入" etc.) and the
## "閉じる" plaque are the click targets, baked into dialog_bg_shop.png —
## no cards. Only the coin count is live, masked over the art's baked
## placeholder number.
func _show_shop_front() -> void:
	_shop_mode = "front"
	_shop_dialog.clear_cards()
	_shop_dialog.clear_hotspots()
	_shop_dialog.set_back("", false)
	_shop_dialog.set_action(locale.text("UI_BUY"), true)
	# Nothing on this page ever populates the detail panel (it's all
	# hotspots over art, no cards to select), so hide it and let
	# card_area — and the background art's cover-scale crop — use the
	# full dialog width instead of losing ~300px to an empty panel.
	_shop_dialog.set_detail_visible(false)
	var gold_label := Label.new()
	gold_label.add_theme_font_size_override("font_size", 22)
	gold_label.add_theme_color_override("font_color", SHOP_GOLD_COLOR)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_label.text = _format_gold(int(sim.inventory.get(UD.RES_GOLD, 0)))
	_shop_dialog.add_overlay(SHOP_GOLD_OVERLAY, gold_label)
	_shop_dialog.add_hotspot(SHOP_BUY_WEAPON_HOTSPOT, _show_shop_buy_weapon)
	_shop_dialog.add_hotspot(SHOP_UPGRADE_WEAPON_HOTSPOT, _show_shop_upgrade_weapon)
	_shop_dialog.add_hotspot(SHOP_BUY_ITEM_HOTSPOT, _show_shop_buy_item)
	_shop_dialog.add_hotspot(SHOP_SELL_ITEM_HOTSPOT, _show_shop_sell_item)
	_shop_dialog.add_hotspot(SHOP_CLOSE_HOTSPOT, _shop_dialog.hide)


## --- Buy weapon: a shelf of every weapon; buying replaces whichever's
## equipped (no inventory, no separate equip step). ---------------------

func _show_shop_buy_weapon() -> void:
	_shop_mode = "buy_weapon"
	_shop_dialog.clear_cards()
	_shop_dialog.clear_hotspots()
	_shop_dialog.set_detail_visible(true)
	# A real close button pinned to the same rect as the front page's
	# "閉じる" plaque hotspot: the plaque itself is mostly hidden behind the
	# detail panel here, leaving a confusing sliver of art poking out above
	# it, so this draws over that whole rect instead of adding a second,
	# differently-positioned close control.
	_shop_dialog.add_solid_hotspot(SHOP_CLOSE_HOTSPOT, locale.text("UI_CLOSE"), _shop_dialog.hide)
	_shop_dialog.set_back(locale.text("UI_BACK"), true)
	_shop_dialog.set_action(locale.text("UI_BUY"), true)
	for weapon_id in weapon_db.all_ids():
		var weapon := weapon_db.get_good(weapon_id)
		var equipped := weapon_id == sim.equipped_weapon_id
		var subtitle := locale.text("UI_EQUIPPED") if equipped else (
			"%s %d" % [locale.text("RES_GOLD"), int(weapon["buy_cost"])]
		)
		_shop_dialog.add_card(
			weapon_id, locale.text(weapon["name_key"]), subtitle,
			art.icon_or_placeholder("weapon_%s" % weapon_id, weapon_id, "rune"), false
		)
	_shop_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	var select_id := _shop_dialog.first_unlocked_id()
	if select_id != "":
		_shop_dialog.select_card(select_id)


func _show_weapon_buy_detail(weapon_id: String) -> void:
	var weapon := weapon_db.get_good(weapon_id)
	var equipped := weapon_id == sim.equipped_weapon_id
	var body := locale.text(weapon["desc_key"])
	body += "\n\n[b]ATK +%d[/b]" % int(weapon["base_atk"])
	body += "\n\n%s" % (
		locale.text("UI_EQUIPPED") if equipped
		else locale.text("UI_BUY_COST") % int(weapon["buy_cost"])
	)
	_shop_dialog.show_detail(
		locale.text(weapon["name_key"]), body,
		art.icon_or_placeholder("weapon_%s" % weapon_id, weapon_id, "rune")
	)
	var affordable := not equipped and int(sim.inventory[UD.RES_GOLD]) >= int(weapon["buy_cost"])
	_shop_dialog.set_action(locale.text("UI_BUY"), not affordable)


## --- Upgrade weapon: no grid, just the equipped weapon's own stat card -

func _show_shop_upgrade_weapon() -> void:
	_shop_mode = "upgrade_weapon"
	_shop_dialog.clear_cards()
	_shop_dialog.clear_hotspots()
	_shop_dialog.set_detail_visible(true)
	# A real close button pinned to the same rect as the front page's
	# "閉じる" plaque hotspot: the plaque itself is mostly hidden behind the
	# detail panel here, leaving a confusing sliver of art poking out above
	# it, so this draws over that whole rect instead of adding a second,
	# differently-positioned close control.
	_shop_dialog.add_solid_hotspot(SHOP_CLOSE_HOTSPOT, locale.text("UI_CLOSE"), _shop_dialog.hide)
	_shop_dialog.set_back(locale.text("UI_BACK"), true)
	if sim.equipped_weapon_id == "":
		_shop_dialog.show_detail("", locale.text("UI_WEAPON_NONE"), null)
		_shop_dialog.set_action(locale.text("UI_SHOP_UPGRADE_WEAPON"), true, false)
		return
	var weapon := weapon_db.get_good(sim.equipped_weapon_id)
	var max_level := int(weapon["max_level"])
	var maxed := sim.weapon_level >= max_level
	var body := locale.text(weapon["desc_key"])
	body += "\n\n[b]Lv.%d/%d[/b]   ATK +%d" % [sim.weapon_level, max_level, sim.weapon_atk_bonus()]
	var cost := 0
	if maxed:
		body += "\n\nMAX"
	else:
		cost = UDSim.weapon_upgrade_cost(weapon, sim.weapon_level)
		body += "\n\n%s" % (locale.text("UI_WEAPON_UPGRADE_COST") % cost)
	_shop_dialog.show_detail(
		locale.text("UI_WEAPON_EQUIPPED") % [locale.text(weapon["name_key"]), sim.weapon_level, max_level],
		body, art.icon_or_placeholder("weapon_%s" % sim.equipped_weapon_id, sim.equipped_weapon_id, "rune")
	)
	var affordable := not maxed and int(sim.inventory[UD.RES_GOLD]) >= cost
	_shop_dialog.set_action(locale.text("UI_SHOP_UPGRADE_WEAPON"), not affordable, false)


## --- Buy item: every collectible, priced by rank ----------------------

func _show_shop_buy_item() -> void:
	_shop_mode = "buy_item"
	_shop_dialog.clear_cards()
	_shop_dialog.clear_hotspots()
	_shop_dialog.set_detail_visible(true)
	# A real close button pinned to the same rect as the front page's
	# "閉じる" plaque hotspot: the plaque itself is mostly hidden behind the
	# detail panel here, leaving a confusing sliver of art poking out above
	# it, so this draws over that whole rect instead of adding a second,
	# differently-positioned close control.
	_shop_dialog.add_solid_hotspot(SHOP_CLOSE_HOTSPOT, locale.text("UI_CLOSE"), _shop_dialog.hide)
	_shop_dialog.set_back(locale.text("UI_BACK"), true)
	_shop_dialog.set_action(locale.text("UI_BUY"), true)
	for item_id in item_db.all_ids():
		var rank := item_db.rank(item_id)
		var at_cap := sim.item_count(item_id) >= sim.item_cap(item_id)
		var subtitle := "%s %d" % [locale.text("RES_GOLD"), int(UD.ITEM_BUY_COST_BY_RANK.get(rank, 0))]
		if at_cap:
			subtitle += "  MAX"
		_shop_dialog.add_card(
			item_id, locale.text(item_db.get_item(item_id)["name_key"]), subtitle,
			art.icon_or_placeholder("item_%s" % item_id, item_id, "gem"), false
		)
	_shop_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	var select_id := _shop_dialog.first_unlocked_id()
	if select_id != "":
		_shop_dialog.select_card(select_id)


func _show_item_buy_detail(item_id: String) -> void:
	var item := item_db.get_item(item_id)
	var rank := item_db.rank(item_id)
	var cost := int(UD.ITEM_BUY_COST_BY_RANK.get(rank, 0))
	var body := locale.text(item["desc_key"])
	body += "\n\n[b]%s: %s[/b]   ×%d / %d" % [
		locale.text("UI_RANK"), rank, sim.item_count(item_id), sim.item_cap(item_id),
	]
	body += "\n\n%s" % (locale.text("UI_BUY_COST") % cost)
	_shop_dialog.show_detail(
		locale.text(item["name_key"]), body,
		art.icon_or_placeholder("item_%s" % item_id, item_id, "gem")
	)
	var at_cap := sim.item_count(item_id) >= sim.item_cap(item_id)
	var affordable := not at_cap and int(sim.inventory[UD.RES_GOLD]) >= cost
	_shop_dialog.set_action(locale.text("UI_BUY"), not affordable)


## --- Sell item: only what's actually owned, selling the full stack ----

func _show_shop_sell_item() -> void:
	_shop_mode = "sell_item"
	_shop_dialog.clear_cards()
	_shop_dialog.clear_hotspots()
	_shop_dialog.set_detail_visible(true)
	# A real close button pinned to the same rect as the front page's
	# "閉じる" plaque hotspot: the plaque itself is mostly hidden behind the
	# detail panel here, leaving a confusing sliver of art poking out above
	# it, so this draws over that whole rect instead of adding a second,
	# differently-positioned close control.
	_shop_dialog.add_solid_hotspot(SHOP_CLOSE_HOTSPOT, locale.text("UI_CLOSE"), _shop_dialog.hide)
	_shop_dialog.set_back(locale.text("UI_BACK"), true)
	_shop_dialog.set_action(locale.text("UI_SELL"), true)
	for item_id in item_db.all_ids():
		var count := sim.item_count(item_id)
		if count <= 0:
			continue
		_shop_dialog.add_card(
			item_id, locale.text(item_db.get_item(item_id)["name_key"]), "×%d" % count,
			art.icon_or_placeholder("item_%s" % item_id, item_id, "gem"), false
		)
	if not _shop_dialog.has_cards():
		_shop_dialog.show_detail("", locale.text("UI_SELL_NONE"), null)
		return
	_shop_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	var select_id := _shop_dialog.first_unlocked_id()
	if select_id != "":
		_shop_dialog.select_card(select_id)


func _show_item_sell_detail(item_id: String) -> void:
	var item := item_db.get_item(item_id)
	var rank := item_db.rank(item_id)
	var value := int(UD.ITEM_SELL_VALUE_BY_RANK.get(rank, 0))
	var count := sim.item_count(item_id)
	var body := locale.text(item["desc_key"])
	body += "\n\n[b]%s: %s[/b]   ×%d" % [locale.text("UI_RANK"), rank, count]
	body += "\n\n%s" % (locale.text("UI_SELL_VALUE") % value)
	body += "\n%s" % (locale.text("UI_SELL_TOTAL") % (value * count))
	_shop_dialog.show_detail(
		locale.text(item["name_key"]), body,
		art.icon_or_placeholder("item_%s" % item_id, item_id, "gem")
	)
	_shop_dialog.set_action(locale.text("UI_SELL"), false)


func _on_shop_card_selected(card_id: String) -> void:
	match _shop_mode:
		"buy_weapon":
			_show_weapon_buy_detail(card_id)
		"buy_item":
			_show_item_buy_detail(card_id)
		"sell_item":
			_show_item_sell_detail(card_id)


func _on_shop_action(card_id: String) -> void:
	match _shop_mode:
		"buy_weapon":
			if sim.buy_weapon(card_id):
				_show_shop_buy_weapon()
				queue_redraw()
		"upgrade_weapon":
			if sim.upgrade_weapon():
				_show_shop_upgrade_weapon()
				queue_redraw()
		"buy_item":
			if sim.buy_item(card_id):
				_show_shop_buy_item()
				queue_redraw()
		"sell_item":
			if sim.sell_item(card_id, sim.item_count(card_id)):
				_show_shop_sell_item()
				queue_redraw()


## --- Dorm ---------------------------------------------------------
## Party roster: Lv/HP/MP per member, with a level-up button that
## spends the shared exp_pool banked from idle combat.

func _build_dorm_dialog() -> void:
	_dorm_dialog = UDCardDialog.create(locale.text("ROOM_DORM"), true)
	_dorm_dialog.card_selected.connect(_on_dorm_card_selected)
	_dorm_dialog.action_pressed.connect(_on_dorm_level_up)
	_dorm_dialog.set_background_frames(_dialog_bg_frames("dialog_bg_dorm"))
	_dorm_dialog.enable_art_chrome(locale.text("ROOM_DORM"), locale.text("UI_CLOSE"))
	add_child(_dorm_dialog)


func _open_dorm() -> void:
	if settings.resident_mode:
		_expand()
	_populate_dorm("")
	_dorm_dialog.open()


## The dorm shows the same standing pixel-art idle sprite used everywhere
## else (party row, battle cards). The illustrated "立ち絵" portraits this
## once preferred (portrait_minion_N) were retired 2026-07-19 — see
## CLAUDE.md — so this is now just the plain minion_N lookup.
func _dorm_icon(art_variant: int, minion_id: String) -> Texture2D:
	return art.icon_or_placeholder("minion_%d" % art_variant, minion_id, "rune")


func _populate_dorm(keep_selection: String) -> void:
	_dorm_dialog.clear_cards()
	for slot_index in sim.minions.size():
		var unit: UDMinion = sim.minions[slot_index]
		var art_variant := _minion_art_variant(slot_index)
		var minion_id := "minion_%d" % slot_index
		var display_name := _unit_display_name(unit)
		_dorm_dialog.add_card(
			minion_id, display_name, "Lv.%d" % unit.level,
			_dorm_icon(art_variant, minion_id), false
		)
	_dorm_dialog.set_progress("%s %d/%d   EXP %d" % [
		locale.text("UI_PARTY"), sim.minions.size(), UD.MINION_MAX, sim.exp_pool,
	])
	_dorm_dialog.set_action(locale.text("UI_LEVEL_UP"), true)
	var select_id := keep_selection
	if select_id == "" and sim.minions.size() > 0:
		select_id = "minion_0"
	if select_id != "":
		_dorm_dialog.select_card(select_id)
	else:
		_dorm_dialog.show_detail("", locale.text("FACILITY_DORM_DESC"), null)


func _on_dorm_card_selected(minion_id: String) -> void:
	var slot_index := int(minion_id.trim_prefix("minion_"))
	var unit: UDMinion = sim.minions[slot_index]
	var art_variant := _minion_art_variant(slot_index)
	var display_name := _unit_display_name(unit)
	var cost := UDSim.exp_cost_for_level(unit.level)
	var body := "%s\n\nLv.%d   HP %d/%d   SP %d/%d\n\n%s: %d / %d" % [
		locale.text("FACILITY_DORM_DESC"), unit.level, unit.hp, sim.unit_max_hp(unit),
		unit.sp, sim.unit_max_sp(unit), locale.text("UI_LEVEL_UP_COST"), sim.exp_pool, cost,
	]
	_dorm_dialog.show_detail(display_name, body, _dorm_icon(art_variant, minion_id))
	_dorm_dialog.set_action(locale.text("UI_LEVEL_UP"), sim.exp_pool < cost)


func _on_dorm_level_up(minion_id: String) -> void:
	var slot_index := int(minion_id.trim_prefix("minion_"))
	var unit: UDMinion = sim.minions[slot_index]
	if sim.level_up_companion(unit.id):
		_populate_dorm(minion_id)
		_on_dorm_card_selected(minion_id)
		queue_redraw()


## --- 宿屋 (新企画v1 §3, 2026-08-18) ------------------------------------
## Purely cosmetic: no sim state, no gameplay effect. Each portrait's
## activity line advances off sim.tick_count (the game's existing 2s-per-
## tick clock, UD.TICK_SECONDS) rather than a new per-frame/real-time
## timer — "一定時間ごとに行動が変化する" without adding to the §7.1 idle
## CPU budget. INN_ACTIVITY_PERIOD_TICKS=15 -> every ~30s of active play;
## an offline catch-up jumps tick_count the same way it always does, so
## reopening after time away just shows wherever the cycle landed, same
## as any other tick-driven display in this game.
const INN_ACTIVITY_COUNT: int = 7
const INN_ACTIVITY_PERIOD_TICKS: int = 15
const INN_ICON_PX: int = 72

func _build_inn_view() -> void:
	var root := PanelContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	# Placeholder backdrop (本番アートが届くまでの仮実装、CLAUDE.md参照):
	# a flat warm wood-toned panel standing in for the real horizontal
	# room scene until dedicated inn art exists.
	root.add_theme_stylebox_override("panel", _panel_style(Color(0.20, 0.15, 0.11)))
	add_child(root)
	_inn_view = root

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	root.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = locale.text("UI_INN")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close_btn := Button.new()
	close_btn.text = "✕ " + locale.text("UI_CLOSE")
	close_btn.custom_minimum_size = Vector2(96, 34)
	close_btn.pressed.connect(func() -> void: _inn_view.hide())
	header.add_child(close_btn)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)

	_inn_activity_labels.clear()
	for slot_index in UD.MINION_MAX:
		var slot := VBoxContainer.new()
		slot.alignment = BoxContainer.ALIGNMENT_CENTER
		slot.add_theme_constant_override("separation", 6)
		row.add_child(slot)

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(INN_ICON_PX, INN_ICON_PX)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		icon.name = "icon_%d" % slot_index
		slot.add_child(icon)

		var name_label := Label.new()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 15)
		name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.75))
		name_label.name = "name_%d" % slot_index
		slot.add_child(name_label)

		var activity_label := Label.new()
		activity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		activity_label.add_theme_font_size_override("font_size", 13)
		activity_label.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
		activity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		activity_label.custom_minimum_size = Vector2(120, 0)
		slot.add_child(activity_label)
		_inn_activity_labels.append(activity_label)

		slot.visible = false  # only as many slots as sim.minions.size() are shown


func _open_inn() -> void:
	_refresh_inn_portraits()
	_refresh_inn_activities()
	_inn_view.show()
	_inn_view.move_to_front()


## Portraits/names only change when the roster itself changes (a full
## rebuild on level-up etc. is unnecessary) — split out from the activity
## refresh below, which runs every tick while the view is open.
func _refresh_inn_portraits() -> void:
	for slot_index in UD.MINION_MAX:
		var slot: Control = _inn_activity_labels[slot_index].get_parent()
		slot.visible = slot_index < sim.minions.size()
		if not slot.visible:
			continue
		var unit: UDMinion = sim.minions[slot_index]
		var art_variant := _minion_art_variant(slot_index)
		var minion_id := "minion_%d" % slot_index
		(slot.find_child("icon_%d" % slot_index, false, false) as TextureRect).texture = \
			art.icon_or_placeholder("minion_%d" % art_variant, minion_id, "rune")
		(slot.find_child("name_%d" % slot_index, false, false) as Label).text = \
			_unit_display_name(unit)


func _refresh_inn_activities() -> void:
	for slot_index in sim.minions.size():
		if slot_index >= _inn_activity_labels.size():
			break
		var cycle := sim.tick_count / INN_ACTIVITY_PERIOD_TICKS + slot_index
		var activity_index := posmod(cycle, INN_ACTIVITY_COUNT) + 1
		_inn_activity_labels[slot_index].text = locale.text("INN_ACTIVITY_%d" % activity_index)


## --- Altar offerings -------------------------------------------------
## Coins (and at higher levels a treasure of the demanded rank) buy
## permanent-for-this-save attack (party_atk_bonus()).

func _build_altar_dialog() -> void:
	_altar_dialog = UDCardDialog.create(locale.text("UI_ALTAR"), true)
	_altar_dialog.card_selected.connect(_on_altar_card_selected)
	_altar_dialog.action_pressed.connect(_on_altar_offer)
	_altar_dialog.set_background_frames(_dialog_bg_frames("dialog_bg_altar"))
	# Whichever party member is being enhanced stands on the altar table;
	# hardcoded to the hero (minion 0) until per-companion altar upgrades
	# and their effects are designed. Coordinates are the altar's stone
	# top surface, read off dialog_bg_altar.png's own pixel grid (760x770)
	# — normalized like a hotspot, not centered in the (narrower) card
	# area, so the hero actually stands on the pedestal in the art instead
	# of floating to its side.
	_altar_dialog.set_character(art.texture(art.minion_key(0)), 0.5, 0.643)
	_altar_dialog.enable_art_chrome(locale.text("UI_ALTAR"), locale.text("UI_CLOSE"))
	add_child(_altar_dialog)


func _open_altar() -> void:
	if settings.resident_mode:
		_expand()
	_populate_altar()
	_altar_dialog.open()


func _populate_altar() -> void:
	_altar_dialog.clear_cards()
	_altar_dialog.set_back("", false)
	_altar_dialog.set_progress("%s   %s %d" % [
		locale.text("UI_ALTAR_LEVEL") % sim.altar_level,
		locale.text("RES_GOLD"), int(sim.inventory[UD.RES_GOLD]),
	])
	_altar_dialog.set_action(locale.text("UI_ALTAR_OFFER"), true)
	if not sim.altar_built():
		_altar_dialog.show_detail("", locale.text("UI_ALTAR_NEEDS_ROOM"), null)
		return
	var required_rank := sim.altar_required_item_rank()
	if required_rank == "":
		_altar_dialog.add_card(
			"__coins__", locale.text("UI_ALTAR_COINS"),
			"$%d" % sim.altar_offer_cost(),
			art.icon_or_placeholder("room_altar", "altar_offer", "rune"), false
		)
	else:
		for item_id in item_db.ids_of_rank(required_rank):
			if sim.item_count(item_id) <= 0:
				continue
			_altar_dialog.add_card(
				item_id, locale.text(item_db.get_item(item_id)["name_key"]),
				"%s  ×%d" % [required_rank, sim.item_count(item_id)],
				art.icon_or_placeholder("item_%s" % item_id, item_id, "gem"),
				false
			)
		if not _altar_dialog.has_cards():
			_altar_dialog.show_detail("", "%s\n%s" % [
				locale.text("UI_ALTAR_NEED_RANK") % required_rank,
				locale.text("UI_ALTAR_NO_ITEM") % required_rank,
			], null)
			return
	var first := _altar_dialog.first_unlocked_id()
	if first != "":
		_altar_dialog.select_card(first)


func _on_altar_card_selected(card_id: String) -> void:
	var cost := sim.altar_offer_cost()
	var body := "%s\n\n[b]$%d[/b]" % [locale.text("UI_ALTAR_EFFECT"), cost]
	var required_rank := sim.altar_required_item_rank()
	var title := locale.text("UI_ALTAR_COINS")
	var icon := art.icon_or_placeholder("room_altar", "altar_offer", "rune")
	if required_rank != "" and card_id != "__coins__":
		body += "\n%s" % (locale.text("UI_ALTAR_NEED_RANK") % required_rank)
		title = locale.text(item_db.get_item(card_id)["name_key"])
		icon = art.icon_or_placeholder("item_%s" % card_id, card_id, "gem")
	_altar_dialog.show_detail(title, body, icon)
	var affordable := int(sim.inventory[UD.RES_GOLD]) >= cost
	_altar_dialog.set_action(locale.text("UI_ALTAR_OFFER"), not affordable)


func _on_altar_offer(card_id: String) -> void:
	var item_id := "" if card_id == "__coins__" else card_id
	if sim.offer_at_altar(item_id):
		_populate_altar()
		queue_redraw()


## --- Guild exchange ---------------------------------------------------
## Rank-up exchange runs locally today; person-to-person trading rides
## on Steam later through the same sim command (UDPlatform).

func _build_guild_dialog() -> void:
	_guild_dialog = UDCardDialog.create(locale.text("UI_GUILD"), true)
	_guild_dialog.card_selected.connect(_on_guild_card_selected)
	_guild_dialog.action_pressed.connect(_on_guild_exchange)
	_guild_dialog.back_pressed.connect(_show_guild_front)
	_guild_dialog.set_background_frames(_dialog_bg_frames("dialog_bg_guild"))
	_guild_dialog.enable_art_chrome(locale.text("UI_GUILD"), locale.text("UI_CLOSE"))
	add_child(_guild_dialog)


func _open_guild() -> void:
	if settings.resident_mode:
		_expand()
	_show_guild_front()
	_guild_dialog.open()


## Landing page: the room art's two painted signs ("アイテム交換" /
## "交換カウンター") are the actual click targets — no parchment cards
## floating over the scene. Rects are normalized to dialog_bg_guild.png's
## own pixel size (1536x1024), read off the shipped art itself.
const GUILD_ITEM_EXCHANGE_HOTSPOT := Rect2(0.8301, 0.4248, 0.1367, 0.0615)
const GUILD_COUNTER_HOTSPOT := Rect2(0.0618, 0.3828, 0.2148, 0.0645)


func _show_guild_front() -> void:
	_guild_dialog.clear_cards()
	_guild_dialog.clear_hotspots()
	_guild_dialog.set_back("", false)
	_guild_dialog.set_action(locale.text("UI_EXCHANGE"), true)
	if not sim.guild_built():
		_guild_dialog.set_detail_visible(true)
		_guild_dialog.show_detail("", locale.text("UI_GUILD_NEEDS_ROOM"), null)
		return
	# No cards on this page — the two painted signs are the whole UI — so
	# the detail panel has nothing to show and only ate into card_area's
	# width. That width matters here specifically: card_area (and the
	# background behind it) used to stop short of the panel, but now the
	# background spans the WHOLE dialog, so with the panel left visible the
	# "アイテム交換" sign (painted near the art's right edge) landed
	# underneath it — clickable in theory, but covered and confusing, and
	# in practice hard to hit exactly under the panel's own controls.
	_guild_dialog.set_detail_visible(false)
	_guild_dialog.add_hotspot(GUILD_ITEM_EXCHANGE_HOTSPOT, func() -> void: _populate_guild(""))
	_guild_dialog.add_hotspot(GUILD_COUNTER_HOTSPOT, _show_guild_counter_soon)


## The counter sign is clickable, but real player-to-player trading needs
## the network backend this project doesn't have yet (§ platform notes,
## CLAUDE.md) — so it opens a plain "not yet" page instead of doing
## nothing when pressed.
func _show_guild_counter_soon() -> void:
	_guild_dialog.clear_cards()
	_guild_dialog.clear_hotspots()
	_guild_dialog.set_detail_visible(true)
	_guild_dialog.set_back(locale.text("UI_BACK"), true)
	_guild_dialog.set_action(locale.text("UI_EXCHANGE"), true)
	_guild_dialog.show_detail(
		locale.text("UI_GUILD_COUNTER"), locale.text("UI_GUILD_COUNTER_SOON"), null
	)


func _populate_guild(keep_selection: String) -> void:
	_guild_dialog.clear_cards()
	_guild_dialog.clear_hotspots()
	_guild_dialog.set_detail_visible(true)
	_guild_dialog.set_back(locale.text("UI_BACK"), true)
	_guild_dialog.set_action(locale.text("UI_EXCHANGE"), true)
	if not sim.guild_built():
		_guild_dialog.show_detail("", locale.text("UI_GUILD_NEEDS_ROOM"), null)
		return
	for item_id in item_db.all_ids():
		var rank := item_db.rank(item_id)
		if not UD.ITEM_EXCHANGE_COSTS.has(rank):
			continue
		var fodder_rank := sim.rank_below(rank)
		_guild_dialog.add_card(
			item_id, locale.text(item_db.get_item(item_id)["name_key"]),
			"%s ← %s×%d" % [rank, fodder_rank, int(UD.ITEM_EXCHANGE_COSTS[rank])],
			art.icon_or_placeholder("item_%s" % item_id, item_id, "gem"),
			false
		)
	_guild_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	var select_id := keep_selection
	if select_id == "":
		select_id = _guild_dialog.first_unlocked_id()
	if select_id != "":
		_guild_dialog.select_card(select_id)


## Greedy auto-pick: spend the most plentiful fodder first so rare
## spares survive. Returns {} when the player cannot cover the cost.
func _guild_exchange_plan(target_id: String) -> Dictionary:
	var rank := item_db.rank(target_id)
	if not UD.ITEM_EXCHANGE_COSTS.has(rank):
		return {}
	var needed := int(UD.ITEM_EXCHANGE_COSTS[rank])
	var fodder_rank := sim.rank_below(rank)
	var owned: Array[String] = []
	for item_id in item_db.ids_of_rank(fodder_rank):
		if item_id != target_id and sim.item_count(item_id) > 0:
			owned.append(item_id)
	owned.sort_custom(
		func(a: String, b: String) -> bool:
			return sim.item_count(a) > sim.item_count(b)
	)
	var plan: Dictionary = {}
	for item_id in owned:
		if needed <= 0:
			break
		var take := mini(needed, sim.item_count(item_id))
		plan[item_id] = take
		needed -= take
	if needed > 0:
		return {}
	return plan


func _on_guild_card_selected(target_id: String) -> void:
	var item := item_db.get_item(target_id)
	var rank := item_db.rank(target_id)
	var fodder_rank := sim.rank_below(rank)
	var needed := int(UD.ITEM_EXCHANGE_COSTS[rank])
	var body := locale.text(item["desc_key"])
	body += "\n\n[b]%s[/b]" % (locale.text("UI_GUILD_COST") % [fodder_rank, needed])
	body += "\n%s ×%d / %d" % [
		locale.text("UI_RANK") + " " + rank,
		sim.item_count(target_id), sim.item_cap(target_id),
	]
	_guild_plan = _guild_exchange_plan(target_id)
	var at_cap := sim.item_count(target_id) >= sim.item_cap(target_id)
	if _guild_plan.is_empty():
		body += "\n\n%s" % (locale.text("UI_GUILD_SHORT") % [fodder_rank, needed])
	else:
		body += "\n\n%s" % locale.text("UI_GUILD_CONSUMES")
		for consume_id: Variant in _guild_plan.keys():
			body += "\n  %s ×%d" % [
				locale.text(item_db.get_item(str(consume_id))["name_key"]),
				int(_guild_plan[consume_id]),
			]
	_guild_dialog.show_detail(
		locale.text(item["name_key"]), body,
		art.icon_or_placeholder("item_%s" % target_id, target_id, "gem")
	)
	_guild_dialog.set_action(
		locale.text("UI_EXCHANGE"), _guild_plan.is_empty() or at_cap
	)


func _on_guild_exchange(target_id: String) -> void:
	if sim.exchange_item(target_id, _guild_plan):
		_populate_guild(target_id)
		queue_redraw()


## Two-level archive: the shelf shows one card per series (data/series/);
## opening a series lists its documents in number order, unfound ones
## blacked out as ?????.
func _open_archive() -> void:
	if settings.resident_mode:
		# Documents are unreadable in a 48px strip: expand first.
		_expand()
	_show_archive_series_shelf()
	_archive_dialog.open()


func _series_doc_ids(series_id: String) -> Array[String]:
	var ids: Array[String] = []
	for doc_id in doc_db.all_ids():
		if str(doc_db.get_doc(doc_id).get("series", "other")) == series_id:
			ids.append(doc_id)
	return ids


func _show_archive_series_shelf() -> void:
	_archive_series = ""
	_archive_dialog.clear_cards()
	for def: Variant in doc_series:
		var series := def as Dictionary
		var series_id := str(series["id"])
		var doc_ids := _series_doc_ids(series_id)
		if doc_ids.is_empty():
			continue
		var found := 0
		var has_unread := false
		for doc_id in doc_ids:
			if sim.discovered_documents.has(doc_id):
				found += 1
			if unread_docs.has(doc_id):
				has_unread = true
		var subtitle := "%d / %d" % [found, doc_ids.size()]
		if has_unread:
			subtitle += " ✦"
		_archive_dialog.add_card(
			series_id, locale.text(series["name_key"]), subtitle,
			art.icon_or_placeholder("series_%s" % series_id, series_id, "book"),
			false
		)
	_archive_dialog.set_back(locale.text("UI_BACK"), false)
	_archive_dialog.set_progress(locale.text("UI_PROGRESS_DOCS") % [
		sim.discovered_documents.size(), doc_db.count(),
	])
	# Nothing is selected on the shelf itself (only a series card, which
	# immediately drills in), so the detail panel would otherwise just show
	# a generic hint before the player has touched anything.
	_archive_dialog.set_detail_visible(false)


func _show_archive_series(series_id: String) -> void:
	_archive_series = series_id
	var fresh := unread_docs.duplicate()
	_archive_dialog.clear_cards()
	var found := 0
	var doc_ids := _series_doc_ids(series_id)
	for doc_id in doc_ids:
		var is_found := sim.discovered_documents.has(doc_id)
		if is_found:
			found += 1
		var doc := doc_db.get_doc(doc_id)
		var subtitle := _doc_number_label(doc_id)
		if fresh.has(doc_id):
			subtitle += " ✦"
		_archive_dialog.add_card(
			doc_id, locale.text(doc["title_key"]) if is_found else "",
			subtitle, art.icon_or_placeholder(doc_id, doc_id, "book"),
			not is_found
		)
		# Entering the shelf marks this series' pages as read.
		unread_docs.erase(doc_id)
	_refresh_archive_button()
	var series_name := series_id
	for def: Variant in doc_series:
		if str((def as Dictionary)["id"]) == series_id:
			series_name = locale.text((def as Dictionary)["name_key"])
			break
	_archive_dialog.set_back(locale.text("UI_BACK"), true)
	_archive_dialog.set_progress("%s   %d / %d" % [series_name, found, doc_ids.size()])
	_archive_dialog.set_detail_visible(true)
	_archive_dialog.show_detail("", locale.text("UI_SELECT_HINT"), null)
	# Open on the newest unread page in this series, else the first found.
	var select_id := ""
	for doc_id in doc_ids:
		if fresh.has(doc_id):
			select_id = doc_id
			break
	if select_id == "":
		select_id = _archive_dialog.first_unlocked_id()
	if select_id != "":
		_archive_dialog.select_card(select_id)


## doc_007 -> "No.7" (matches the reference catalogue numbering).
func _doc_number_label(doc_id: String) -> String:
	var digits := ""
	for i in range(doc_id.length() - 1, -1, -1):
		if not doc_id[i].is_valid_int():
			break
		digits = doc_id[i] + digits
	return ("No.%d" % int(digits)) if digits != "" else doc_id


func _on_archive_card_selected(card_id: String) -> void:
	if _archive_series == "":
		_show_archive_series(card_id)
		return
	var doc := doc_db.get_doc(card_id)
	_archive_dialog.show_detail(
		locale.text(doc["title_key"]),
		locale.text(doc["body_key"]),
		art.icon_or_placeholder(card_id, card_id, "book")
	)


func _quit() -> void:
	UDSaveManager.save_game(sim)
	get_tree().quit()
