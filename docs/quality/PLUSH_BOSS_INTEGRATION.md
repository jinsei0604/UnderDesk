# ぬいぐるみボス — 承認済みv12

- 外見ID `appearance_plush`、通常 `plush`、覚醒後 `plush_awakened`。既存9体の後ろに追加。既存Creatorの条件・回復・強化・保存方式を使用し、技の性能値は固定しない。
- 体高170/200論理px。承認済みネイティブ素材、最近傍・整数座標。キャラクターの待機アニメーションは追加せず、承認済みの紫の薄い霧を使用する。
- 既存の単体・全体・支援・覚醒登録と `warm_paths()` に接続。共通の戦闘計算・乱数・保存の仕様は変更しない。通常攻撃、単体攻撃、支援、被弾、撃破は承認済みの内容を保持。
- 覚醒はv9で承認された順序と時間割。v7のタメ→完全暗転→3.40秒で明転と顔アップ・叫び声→3.68秒から全身へ接続→6.50秒で終了。
- 覚醒SEは承認されたv12 WAVをGodot対応16bit PCMへ形式変換したもの（最大波形差1/32768未満、音量・長さ・ピッチは不変）。`v12/audio/awakening_scream.wav`。既存のJUMP境界で1回再生し、既存のローカル音量−10dBを保持。出典・CC0許諾・加工は同フォルダの `LICENSE.md` と `PROVENANCE.json`。独立したタイマーは追加しない。
- 覚醒後全体攻撃は6.60秒。腹の脈動と裂け目の気配→1.18〜2.10秒に腹を起点として闇が広がる→固定されたほぼ見えない本体から巨大腕が12連打→4.48秒に締めの一撃とダメージ表示→5.45〜6.30秒に暗闇が晴れる。
- 本体は暗闇中の位置・姿勢を固定。巨大な腕だけが伸び、振り下ろし、肩へ戻る。全身の突進、分身、明るい全画面フラッシュはない。腕は既存単体攻撃の布の袖と巨大爪を使用。12回の視覚的打撃が戦闘ダメージを増殖させることはない。
- ダメージ数値・HP・かばう・カウンターは既存stage経路。全画面の闇はz=90、暗闇中の描画は92、DamageNumbersは120。中断・巻き戻しで描画、音、カメラ、対象の姿を元へ戻す。
- Rendererのv7/v8/v9/v11/v12という名前は承認履歴と依存層を残すためのもの。試作動画やレビュー用の古いゲームコピーはGitに含めない。

検証：`test_plush_presentations.gd`、`test_rbm_presentation_warmup.gd`、選択・保存・覚醒関連および全GUT。実GPUは正式の `tools/gpu_runner.tscn` から `tools/verify_plush_release_gpu.gd` を実行。`--selection-only --english` は英語の選択画面、`--perf --1080` は1920×1080の実時間確認。確認動画の録画速度を性能値として使用しない。

## 登場「縫い直し」（2026-11-17 試作、2026-11-19 ユーザーの指摘で部位ごとの糸に作り直し、同日 針で縫い付ける動きを足してユーザーが採用）
- `src/bossmaker/visuals/encounter/intro/rbm_intro_plush.gd`（`rbm_intro_player.gd` の `CHOREO["plush"]`）。音は `assets_bossmaker/audio/plush/intro.wav`（`node tools/plush/audio/build.mjs` → `tools/plush/audio/out/intro.wav` を置いて `--import`。時刻は intro の `T` を読む）。5.1秒。
- 意味: 裁縫部屋の床に頭・胴・両腕・両足がバラバラに散らばっている → 胴の縫い目から部位ごとに赤い糸が飛んで各部位を刺す → 糸が張り、足・腕・頭の順に引き寄せる（両足が付く間に胴が立ち上がる。付いた所に綿のくず）→ 付いた所を、赤い糸を通した1本の針が縫い目に沿って3針ずつ縫って回る（初版の針の縫い方。1針ごとに体がびくっと動き、赤い縫い跡が1つずつ増える）→ 頭を縫い終えると針が上へ抜け、糸がぷつっと切れる → 全身がそろう → 色が戻り、ボタンの目が一瞬だけ赤く光る（覚醒後の予告）→ 手を振る → 立ち姿・題字。
- 部位の絵: `assets_bossmaker/battle/plush/intro_parts/`（head・torso・arm_l・arm_r・leg_l・leg_r。どれもコマ 0 と同じ 106×170）。`godot --headless --path . --script res://tools/plush/bake_intro_parts.gd` で作り直す（黒い輪郭を壁にして塗りを部位へ割り当て、輪郭は隣り合う部位の両方に入れる。6つを重ねるとコマ 0 と画素が一致することを確かめ、縫い目の点を出す。股の右側の輪郭の切れ目3画素は壁として扱う）。部位は動かすだけで、伸縮・回転しない。全部そろった所で立ち姿のコマ 0 に替える（同じ絵）。手を振るのは全体攻撃のコマ 57/53/57。
- 最後の立ち姿は戦闘中の立ち姿と同じ絵・同じ足元（`frames.json` の bbox と ANIMATION の offset が一致。テストで確かめる）。体を白く重ねる光は使わない（等倍の絵に重ねると透けて見える）。カメラは寄らない（揺れだけ）。
- 確かめ方: `test_plush_presentations.gd` の `test_intro_sews_the_scattered_parts_together_and_ends_on_the_battle_stance`、`test_rbm_encounter`。実GPU は `tools/verify_boss_intro_gpu.gd --boss=plush`（時刻ごとの画像、`--perf`（`--1080`）で実時間、`--capture` で確認動画）。
