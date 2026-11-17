# 金環の聖獣／日蝕の獅皇 — 本番への組み込み（2026-11-12〜13）

- 外見ID `appearance_lion`、通常 `lion`、覚醒後 `lion_awakened`。既存11体の後ろ（12体目）に追加。表示名「金環の聖獣」（英語は仮に「Haloed Sacred Beast」）。覚醒あり。既存の Creator の条件・回復・強化・保存の方式をそのまま使い、技の性能値は固定しない。戦闘の計算・乱数・行動順・保存の仕様は変えていない。
- 本体は Codex のキーポーズ（2026-11-11、`assets_bossmaker/battle/lion/motion/<技>/<番号>.png`、320×180、足元 (176,155)、各技4〜5枚）をそのまま切り替えるだけ。中割り・変形・パーツ分割はしない（ヒーローで動きを滑らかにつなぎすぎて体がうにょうにょした反省）。動きはキーポーズの切り替え・位置の移動・命中のヒットストップ・残像だけ。
- エフェクト・音・画面の演出は Claude。2026-11-11〜12 に確認動画（`prototypes/four_bosses_2026-11-11/out/lion_v5.mp4`）でユーザーが採用した内容をそのまま移した。
- 立ち絵: 覚醒前＝覚醒の1枚目、覚醒後＝覚醒後全体の余韻のポーズ（ユーザー指定）。`RBMLionMotion.STANCE_CROP` で切り出して12ポーズに置く。体の高さ（覚醒前90・覚醒後120ドット）を2倍で表示（`RBMVisualAssets.HEIGHTS` 180・240）。

## 技と振り分け
| 戦闘の行動 | 演出（`src/bossmaker/visuals/lion/`） | 最後の一撃（impact） | 音（`assets_bossmaker/audio/lion/`） |
|---|---|---|---|
| 覚醒前の単体 | 飛びかかり（`rbm_lion_fx_pre_single.gd`）: 背の金の光輪 → 飛びかかり（残像）→ 金の三本爪 | 0.80秒 | `single.wav` |
| 覚醒前の全体 | 王獣の咆哮（`pre_all`）: 頭上の金環 → 三重の衝撃波 → 金の光の爆発 | 2.14秒 | `all.wav` |
| 覚醒 | 王衣の目覚め（`awaken`）: 背に金の太陽 → 黒い月がゆっくり重なる日蝕 → 皆既で闇が落ち、姿は影になり目だけが光る（機械武者の覚醒の目と同じ光り方）→ 深紅の王衣・咆哮 → 光冠が爆ぜて覚醒 | なし | `awakening.wav` |
| 覚醒後の単体 | 断罪の爪撃（`post_single`）: 一度消えて、相手の前に急に現れた時にはもう斬っている → 叩きつけ → また消えて戻る | 1.22秒 | `awakened_single.wav` |
| 覚醒後の全体 | 獅皇の踏破（`post_all`）: 立ち姿のまま四人の頭上に日蝕 → 破滅の光が一人ずつ → 太陽が落ちてくる所で1回だけ咆哮（後脚で立つポーズは使わない）→ 大爆発 | 3.55秒 | `awakened_all.wav` |

| 支援（回復・強化、2026-11-13） | 金環の祈り（`rbm_lion_fx_support.gd`）: 立ち姿 → 支援のポーズ（覚醒前＝覚醒前全体の4枚目の頭を上げた姿、覚醒後＝覚醒の4枚目の咆哮）→ 立ち姿。切り替えは1回だけ。頭の上に小さな金環日食（覚醒後は深紅）が現れて光を集め、回復は空から光の柱が降りて光の粒が降り注ぐ、強化は足元から光の筋と火の粉が立ち上る | 1.20秒 | `heal.wav`・`buff.wav`・`awakened_heal.wav`・`awakened_buff.wav` |

- 咆哮の声は竜の登場・覚醒と同じ `dragon_roar` を高さを変えずに使う（ユーザー指定）。
- 支援の振り分けは `BOSS_SUPPORT_PRESENTATIONS`（入口 `rbm_lion_support.gd`）。回復か強化かは `stage._skill.effect`（`heal`・`self_heal` なら回復）。ポーズは他の技のキーポーズを1枚借りる（`rbm_lion_presentation.gd` の `SUPPORT_POSE`・`pose_source()`）。

## 登場（2026-11-13 ユーザーの案。挑戦・クリアチェックの画面）
- `encounter/intro/rbm_intro_lion.gd`（つなぎ）＋ `rbm_lion_fx_intro.gd`（中身）。登録は `RBMIntroPlayer.CHOREO`。
- 戦場が少し暗くなる → 聖獣が現れる場所に金色のオーラをまとった剣が8本、次々と突き刺さる（刺さるたびに火花・金の輪・剣の円陣が強くなる）→ 巨大な剣が空に現れて光を集め、一気に突き刺さる（ヒットストップ0.1秒）→ 金の大爆発（剣は光になって砕ける）→ 爆発の中から聖獣が現れて咆哮（竜と同じ声）→ 立ち姿・題字。カメラは寄らない（揺れだけ）。
- 剣の描き方は `RBMLionFxBase.draw_sword()`（撃破の後に残る剣と共通）。音は `intro.wav`（登場の再生の0.34秒から）。

## 撃破（2026-11-13 ユーザーの案）
- `rbm_lion_defeat.gd`（つなぎ。`RBMVictoryPlayer.DEFEAT` の `lion`・`lion_awakened`）＋ `rbm_lion_fx_fall.gd`（中身。覚醒前の時刻 `T`、覚醒後の時刻 `TA`）。
- 覚醒前: 倒れた聖獣の背に金環日食 → 金の輪が上から両側へ欠けていき、欠けた所から金の破片がこぼれる → 輪に合わせて聖獣も光の粒にほどける → 最後のかけらが光の剣になって、聖獣のいた床へ刺さる。
- 覚醒後（ユーザー「覚醒後はもっと派手に」）: 大きな深紅の日蝕 → 光冠が一度燃え上がる → 欠けていく間も深紅の閃光が脈打つ → 最後のかけらで深紅の大爆発（衝撃波・閃光）→ 煙の中から深紅の大剣が空から落ちて突き刺さる。音は覚醒前 `defeat.wav`、覚醒後 `defeat_awakened.wav`。
- 消えた後も剣は床に刺さったまま残り、静かに光る（ユーザー指定。結果の画面まで。勝利の層が片付く時に一緒に消える）。輪が欠けるのに合わせて月の黒い円盤も薄くする（`eclipse.gdshader` の `disc_fade`。ほかの技は既定の1のまま）。
- 2026-11-14 ユーザー「ボスの中心に変なマークが出る」: 全ボス共通のとどめ（`final_blow`）の胸の小さな光の円と火花を、`rbm_lion_defeat.gd` で上書きして出さない（白く光る体の真ん中に印のように見えた）。`rbm_lion_fx_fall.gd` も、聖獣のいた所に出る平らな光の丸（飛ぶ剣の先・最後のかけら・刺さる瞬間・覚醒後の爆発の中心）と刺さる所の平らな光の輪をやめ、覚醒後の光冠の火花は中心の1点ではなく縁から外へ出す。1280×720 の実時間で撃破2種とも20ms超0。
- 振り分けは `rbm_battle_stage.gd` の `BOSS_SINGLE_PRESENTATIONS`・`BOSS_ALL_PRESENTATIONS`・`BOSS_AWAKENING_PRESENTATIONS`。入口は `rbm_lion_presentation.gd`（ステージとのつなぎ）と `rbm_lion_single/all/awakening.gd`。エフェクトの土台は `rbm_lion_fx_base.gd`（ヒーローの部品 `RBMHeroFxBase` をそのまま使い、日蝕・暗がりの目を足す）。
- 覚醒後の常時の太陽のオーラ: `rbm_lion_sun_aura.gd`＋`shaders/sun_aura.gdshader`。体の輪郭から立ち上る炎の形はヒーローの黒い炎と同じ作り方で、色は体に近いほど白金→外へ金・橙・紅。距離はポーズごとに事前に焼いた物（`assets_bossmaker/battle/lion/aura_fields/`）。待機の立ち絵（`rbm_lion_visual.gd`）と覚醒後の技の間ずっと付く。
- 途中の当たりは小さな数字、最後の一撃で合計（`begin_multi_hit`）。単体は確定した対象へ踏み込み先をずらす（`focus_delta`）。全体は実際の対象の位置へ基準の4か所を割り当てる。かばう・侍のカウンター・中断・巻き戻しはヒーローと同じ流れで元へ戻す。

## 既存のボスと違う所・まだ無い物
- **専用の背景**: 2026-11-16 に追加（雲海と朝焼けの断崖を見渡す高原。`assets_bossmaker/battle/backgrounds/lion/background.png`）。
- **専用のBGM**: まだ無い（対象外。置く場所は `assets_bossmaker/audio/bgm/lion/`）。
- **ボス選択のプレビュー動画**: 2026-11-16 に追加（通常・覚醒後の単体・全体の4本）。

## 性能（参照機・実時間・挑戦の画面・同じ起動で各技2回）
- 1280×720: 平均 59.0〜60.0fps。33ms超は技ごとに0〜3（最悪34ms）。
- 1920×1080: 平均 58.1〜60.0fps。覚醒前の2技・覚醒後の単体は33ms超0。覚醒後の全体（日蝕が崩れ落ちた後の大爆発の間、最悪38ms）と覚醒で33ms超が11（34〜35ms がほとんど）。ヒーローの爆炎と同じ種類の重さ（画面の広い範囲の爆炎の塗り）。予算の「33ms超は0」をまだ満たしていない。

- 登場・支援・撃破（2026-11-13、同じ起動で各2回）: 1280×720 は 33ms超がほぼ0（初回などにまれに1回、最悪36ms）。1920×1080 は支援・覚醒前の撃破が0〜1、覚醒後の撃破が0〜2（最悪40ms）、登場が4〜6（最悪42ms。巨大な剣の後の金の大爆発の間、覚醒後全体と同じ種類の重さ。爆発の大きさを覚醒前全体くらいへ少し小さくした後の値）。

## 確かめ方
- テスト: `test_lion_presentations.gd`（登録・キーポーズとデータのそろい・覚醒後全体の咆哮は1回で後脚で立たない・宣言した素材・数字と impact・確定した対象・中断とカウンター・覚醒で影と太陽のオーラ・選択と保存）、`test_rbm_presentation_warmup.gd`（初回の再生で新しく読まない）、ボスの一覧のテスト（`test_rbm_boss_awakening_support`・`test_rbm_appearance_picker_awakening_preview`・`test_rbm_musha_boss_selection`・`test_rbm_hardcore_victory_conditions`）。
- 実GPU: `godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_lion_gpu.gd --output=<dir>`（3つの戦闘画面・覚醒前後の単体と全体・カウンター・覚醒・撃破・ボス選択）。`--perf`（`--1080`）・`--capture`・`--selection-only`（`--english`）・`--defeat-only`・`--awakened-defeat`。登場・支援4種・撃破2種だけは `--new-only`、登場だけは `--intro-only`（`--perf` で遅いコマの時刻も出す）。`--capture` では切り出し用に `LION_MARK <場面> start/end <コマ>` を出す。
- 確認動画（2026-11-13）: `prototypes/four_bosses_2026-11-11/out/lion_intro_support_defeat.mp4`（登場・支援4種・撃破2種、見出しつき）。
- 素材を作り直した時: キーポーズを `assets_bossmaker/battle/lion/motion/` に置き → `godot --headless --path . --script res://tools/lion/bake_lion_assets.gd`（立ち絵・オーラの距離・エフェクトの位置）→ `--import`。
- 音を作り直した時: `godot --headless --path . --script res://tools/lion/dump_lion_timing.gd` → `node tools/lion/audio/build.mjs`（技の名前を並べるとその音だけ）→ `out/` の音を名前の対応（build.mjs の先頭）どおりに `assets_bossmaker/audio/lion/` へ → `--import`。技の5本・登場・撃破2本・支援4本の計12本。
