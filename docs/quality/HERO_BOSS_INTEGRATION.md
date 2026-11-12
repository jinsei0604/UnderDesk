# ヒーローボス — 本番への組み込み（2026-11-10）

- 外見ID `appearance_hero_boss`、通常 `hero_boss`、覚醒後 `hero_boss_awakened`。既存10体の後ろ（11体目）に追加。表示名「ヒーロー」（英語は仮に「Hero of Light」。味方の勇者が「Hero」のため）。覚醒あり。既存の Creator の条件・回復・強化・保存の方式をそのまま使い、技の性能値は固定しない。戦闘の計算・乱数・行動順・保存の仕様は変えていない。
- 本体の動きは Codex の正式モーション（2026-11-09 正式採用。`assets_bossmaker/battle/hero_boss/motion/cels.png`・`exposures.json`、受け渡しの物と同じ）。エフェクト・音・画面の演出は Claude（2026-11-09〜10 にユーザーが1つずつ採用）。本体の絵と座標は変えず、技の時刻表 `rbm_hero_fx_timing.gd` の `tame_hold`（指定のコマを止める長さ）と `body_swap`（④の切った後の直立をやめた差し替え）だけを足す。
- 体高は正式モーションの立ち姿90ドットを2倍の180px（`RBMVisualAssets.HEIGHTS`）。待機・被弾の12ポーズは立ち姿1枚（覚醒前 `normal`、覚醒後 `omega`）を足元で揃えて置いたもの（`tools/hero_boss/bake_hero_boss_assets.gd` が作る）。

## 技と振り分け
| 戦闘の行動 | 演出（`src/bossmaker/visuals/hero_boss/`） | 最後の一撃（impact） | 音 |
|---|---|---|---|
| 覚醒前の単体 | ① blade（光の刃の突進） | `seam` 2.063秒 | `audio/hero_boss/single.wav` |
| 覚醒前の全体 | ② array（タメてほぼ水平のビーム→外へ噴き出す炎） | `final` 4.50秒 | `all.wav` |
| 覚醒 | ③ breach（黒い炎が這い上がる→2段階目→覚醒後の姿） | なし（`_finish_awakening_entry`） | `awakening.wav` |
| 覚醒後の単体 | ④ shear（前に細い斬線・後ろに太い帯） | `final` 2.24秒 | `awakened_single.wav` |
| 覚醒後の全体 | ⑤ press（振り下ろしの瞬間に画面が切れる・地面から炎の柱） | `rupture` 3.85秒 | `awakened_all.wav` |

- 振り分けは `rbm_battle_stage.gd` の `BOSS_SINGLE_PRESENTATIONS`・`BOSS_ALL_PRESENTATIONS`・`BOSS_AWAKENING_PRESENTATIONS`。入口は `rbm_hero_boss_presentation.gd`（ステージとのつなぎ）と `rbm_hero_boss_single/all/awakening.gd`。エフェクト本体は技ごとに1ファイル（`rbm_hero_fx_blade/array/breach/shear/press.gd`）とシェーダー（`shaders/`）。
- 途中の当たりは小さな数字、最後の一撃で合計（`begin_multi_hit`）。単体は確定した対象へ向けて刃先・突進の先をずらす（`focus_delta`）。全体は実際の対象の位置へエフェクトの基準の4か所を割り当て、倒れている味方の所には当てない（`present`）。
- かばう・侍のカウンターは紳士と同じ流れ（演出の後に元の位置へ戻してからカウンター）。中断・巻き戻しで、カメラ・本体・味方の色・音・層を元へ戻す。
- 覚醒後の常時オーラ: `rbm_hero_boss_visual.gd`（汎用の立ち絵 `rbm_character_visual.gd` を継承）が `RBMHeroDarkAura` を本体の後ろに付ける。距離は `assets_bossmaker/battle/hero_boss/aura_fields/<コマ名>.res` に事前に焼いた物を読む（戦闘中に計算しない）。
- 音は専用の1本のトラックを演出の開始で1回鳴らす（`play_sound_phase()` が true を返し、汎用の SE は鳴らさない）。音量 −8dB。音の作り方は `tools/hero_boss/audio/build.mjs`（既存のゲームの効果音の切り出しと合成の層。種つきの乱数で毎回同じ音になり、置いてある5本とバイト単位で一致することを確認済み）。

## 既存のボスと違う所・まだ無い物
- **支援（回復・強化）**: 専用の演出は無い。汎用の流れ（立ち姿のまま・汎用の SE）。
- **登場の演出**: 無い（ぬいぐるみと同じ。`rbm_intro_player.gd` の `CHOREO` に無い）。
- **撃破（覚醒前）**: 専用の倒れ方は無く、共通の倒れ方 `rbm_defeat_generic.gd`（ほどける縁は青 `#5cc6fa`）。立ち姿しか無いので姿勢の変化は無く、砂ぼこり → 粒になってほどける。
- **撃破（覚醒後、2026-11-11）**: 専用 `rbm_hero_boss_defeat_awakened.gd`（エフェクト `rbm_hero_fx_fall.gd`、時刻 `RBMHeroFxTiming.FALL`、3.1秒、音 `audio/hero_boss/awakened_defeat.wav`）。とどめのスロー（共通）→ 膝をつく（release2）→ 闇が暴れ、内から青い稲妻が漏れる（鼓動3回、オーラは途中で弱めない）→ 1.04秒に黒紅の炎が外へ噴き出し、紅いひびが走り、青い光の柱が立つ（release3）→ 1.3秒に元の青い姿で膝をつく（release1）→ 青い光の粒になって昇る（共通の四角い粒の消え方）。本体のコマは `tools/hero_boss/bake_hero_boss_assets.gd` が `hero_boss_awakened/defeat/` に1枚ずつ切り出す。実測（2回目、33ms超）: 1280×720 で1、1920×1080 で9（最悪34ms）。
- **耐久勝利**: 共通の `SURVIVAL_GENERIC`（全ボス共通）。
- **ボス選択のプレビュー動画**: まだ無い（「プレビュー準備中」。紳士・ぬいぐるみなどと同じ）。

## 性能（参照機・実時間・同じ起動で各技2回）
組み込みの時に直した物（見た目は変えない）:
1. **演出の開始の停止**: Godot は読み込んだだけのシェーダーの中身の準備（`Shader.get_rid()`）を最初に使う瞬間まで遅らせ、1本 1.6〜4.4ms ずつ技の開始のフレームに重なっていた（最初の技の開始の処理 22.9ms、そのフレーム 36.3ms）。共通の事前読み込み `rbm_presentation_warmup.gd` が、持ったシェーダーの準備も1フレームに1本ずつ済ませ、済むまではその演出の素材が揃っていない扱いにした（演出の開始の境界で待つ、§2.1 と同じ形）。→ 開始の処理 3.7ms、そのフレーム 20.6ms。宣言されたシェーダーを持つ演出（ぬいぐるみの宇宙・撃破の演出など）にも同じく効く。
2. **爆炎の矩形**: 爆炎のシェーダー（`blast.gdshader`）の矩形を、色が付きうる範囲だけに縮めた（`rbm_hero_fx_base.gd` の `blast_area()`。範囲の外は今も透明を出しているだけ）。コマ数を固定して撮った85枚で、60枚が完全に一致、残りも数画素が 1/255 違うだけ（浮動小数の丸め）。挑戦の単体だけ大きく違ったのは、乱数で狙われた味方が違ったため。

実測（参照機・挑戦の画面・同じ起動の2回目。33ms超の数／最悪のフレーム）:

| 技 | 1280×720 直す前 → 直した後 | 1920×1080 直す前 → 直した後 |
|---|---|---|
| ① 覚醒前の単体 | 7 / 35ms → 1 / 34ms | 8 / 34ms → 1 / 34ms |
| ② 覚醒前の全体 | 8 / 46ms → 2 / 36ms | 19 / 57ms → 10 / 35ms |
| ③ 覚醒 | 8 / 34ms → 3 / 35ms | 17 / 49ms → 13 / 37ms |
| ④ 覚醒後の単体 | 6 / 34ms → 1 / 34ms | 9 / 47ms → 2 / 35ms |
| ⑤ 覚醒後の全体 | 8 / 55ms → 2 / 39ms | 21 / 80ms → 13 / 35ms |

平均は 1280×720 で 59.3〜59.7fps、1920×1080 で 56.7〜59.7fps。最初の技の開始の停止は無くなった。事前読み込みのテクスチャメモリは、戦闘を開いてから読み終えるまで +93〜94MB（味方の分が大半。同じ味方のスライムは +101MB なので、ヒーロー自身の分は小さい）。

残り（予算の「33ms超は0」をまだ満たしていない）: 33ms を少し超えるフレーム（34〜35ms。描画が 16.7ms を少し超えて1回分の画面の更新を逃したもの）が、1920×1080 の ②の爆発（4.5〜5.1秒）・⑤の炎の柱（3.9〜4.7秒）・③で続く。1280×720 では技ごとに1〜3フレーム。

重さの原因は奥の層（HeroBack）の爆炎の塗り（画面の広い範囲を、玉の数だけ計算する）。後処理・暗幕・手前の層・本体を隠しても変わらず、奥の層を隠すと0になる。爆炎の光が届く範囲が広い（見た目の一部）ので、矩形を縮めるだけでは足りない。さらに軽くするには、爆炎を半分の解像度で描いて拡大する等、見た目の画素が変わる方法になるため、前後の映像をユーザーが見て判断する（PERFORMANCE §1.2）。

## 確かめ方
- テスト: `test_hero_boss_presentations.gd`（登録・正式モーションの並び・宣言した素材・数字と impact・確定した対象・中断とカウンター・覚醒と常時オーラ・選択と保存）、`test_rbm_presentation_warmup.gd`（初回の再生で新しく読まない・シェーダーの準備）、`test_rbm_boss_awakening_support`・`test_rbm_appearance_picker_awakening_preview`・`test_rbm_musha_boss_selection`・`test_rbm_hardcore_victory_conditions`（ボスの一覧）、全GUT。
- 実GPU: `godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_hero_boss_gpu.gd --output=<dir>`。本番の3つの戦闘画面（TEST・クリアチェック・挑戦）で、覚醒前後の単体・全体・カウンター・覚醒・撃破と、ボス選択（一覧・覚醒後の切り替え・作成画面への反映）。`--perf`（`--1080`）は実時間の計測、`--capture` は確認動画（`--write-movie` と一緒に。録画の速さを性能の値に使わない）、`--selection-only`（`--english`）・`--defeat-only`。
- 素材を作り直した時: `godot --headless --path . --script res://tools/hero_boss/bake_hero_boss_assets.gd` → `--import`。音は `node tools/hero_boss/audio/build.mjs` → `out/` の5本を `assets_bossmaker/audio/hero_boss/` へ（名前の対応は build.mjs の先頭）→ `--import`。
