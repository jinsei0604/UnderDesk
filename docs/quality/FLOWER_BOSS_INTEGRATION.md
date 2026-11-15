# 白磁のカラー／喪華のカラー女王 — 本番への組み込み（2026-11-16）

- 外見ID `appearance_flower`、通常 `flower`、覚醒後 `flower_awakened`。金環の聖獣の後ろ（13体目）に追加。表示名「白磁のカラー」（英語は仮に「Porcelain Calla」）。覚醒あり。既存の Creator の条件・回復・強化・保存の方式をそのまま使い、技の性能値は固定しない。戦闘の計算・乱数・行動順・保存の仕様は変えていない。
- 2026-11-11〜16 に試作（`prototypes/four_bosses_2026-11-11/`、確認動画 `out/flower_v4.mp4`・`out/flower_extras_v2.mp4`）でユーザーが採用した内容をそのまま移した（2026-11-16 ユーザー「どちらも実装して大丈夫」）。作りは金環の聖獣（[LION_BOSS_INTEGRATION.md](LION_BOSS_INTEGRATION.md)）と同じ。
- 本体は Codex のキーポーズ（2026-11-11、`assets_bossmaker/battle/flower/motion/<技>/<番号>.png`、320×180、足元 (176,155)）をそのまま切り替えるだけ。中割り・変形・パーツ分割はしない。
- 立ち絵: 覚醒前＝覚醒の1枚目、覚醒後＝覚醒の5枚目（`RBMFlowerMotion.STANCE`）。`STANCE_CROP` で切り出して12ポーズに置く。体の高さ（覚醒前85・覚醒後96ドット）を2倍で表示（`RBMVisualAssets.HEIGHTS` 170・192）。

## 技と振り分け（`src/bossmaker/visuals/flower/`）
| 戦闘の行動 | 演出 | 最後の一撃（impact） | 音（`assets_bossmaker/audio/flower/`） |
|---|---|---|---|
| 覚醒前の単体 | 棘指の突き（`rbm_flower_fx_pre_single.gd`）: 茎をひねって溜め → 指先を突き出し、蔦が一直線に伸びて突く | `T.contact` | `single.wav` |
| 覚醒前の全体 | 開花の祝福（`pre_all`）: 光が花の顔へ集まり足元に白磁の花 → 四人の足元に白磁の睡蓮が咲く → お辞儀（覚醒の2枚目を借りる） | `T.burst` | `all.wav` |
| 覚醒 | 喪色の開花（`awaken`）: 大きな花の咲く木に変わり、一気に枯れて砕け、花びらの嵐の中から覚醒後（背に暗い喪華） | なし | `awakening.wav` |
| 覚醒後の単体 | 女王の鉤指（`post_single`）: 両手の蔦・地面から2本・螺旋の巻き付き | `T.squeeze` | `awakened_single.wav` |
| 覚醒後の全体 | 喪華の勅令（`post_all`）: 喪色に沈む → 花びらが四人を囲む → 蔦 → 蕾 → 一斉に開花 → 喪色の光（背の巨大な喪華） | `T.burst` | `awakened_all.wav` |
| 支援（回復・強化） | `rbm_flower_fx_support.gd`: 回復＝全体の2枚目を借り、足元に白磁の睡蓮・光の筋・回る花びら。強化＝全体の3枚目を借り、花の冠が回って花びらに弾ける。覚醒後は喪華の色・オーラが燃え上がる | `T.impact` | `heal.wav`・`buff.wav`・`awakened_heal.wav`・`awakened_buff.wav` |

- 花は `shaders/bloom.gdshader`（立体の花: 花びらを3Dで起こして奥行きで重ね、光の向きで明暗）。花びらは先の丸いしずく形（尖らせると星形に見える）。
- 他の技のキーポーズを借りる技（全体のお辞儀・支援・登場・撃破）は、エフェクトの `extra_poses()` に `{番号: [技, 何枚目]}` を書く（番号は 9 など技の絵と重ならない数）。つなぎ（`rbm_flower_presentation.gd`）がその絵を読み、**覚醒後のオーラの形も借りた元の絵の距離を使う**（2026-11-15 ユーザー「覚醒後のときオーラ消えてるときある」: 借りたポーズに距離が無く消えていた）。支援の事前読み込みは `SUPPORT_POSES`（テストで `extra_poses()` とそろうことを確かめる）。
- エフェクトの土台は `rbm_flower_fx_base.gd`（ヒーローの部品 `RBMHeroFxBase` をそのまま使い、試作の部品のうち花が使う物だけを移した: 花・カラー・花びら・蔦・光の筋）。

## 登場（2026-11-14 ユーザーの案。挑戦・クリアチェックの画面）
- `encounter/intro/rbm_intro_flower.gd`（つなぎ）＋ `rbm_flower_fx_intro.gd`（中身）。登録は `RBMIntroPlayer.CHOREO`。
- 画面全体に花びらが舞い始め、最初は少しだけ → だんだん多くなる → やがて全画面を覆い隠す → 一陣の風で晴れると、光の中でお辞儀をしている（覚醒の2枚目）→ 顔を上げて構え・題字。カメラは寄らない（揺れだけ）。
- 花びらは `shaders/petal_veil.gdshader`。2026-11-15 ユーザー「花びらがありすぎて気持ち悪い」で、小さな花びら数千枚 → 大きな花びら数十枚＋網点で埋まる淡い花びらのもやに直した（半透明の霧は灰色、なめらかなまだらは牛柄に見えた）。
- 演出は画面が黒から出た所（`LEAD` 0.36秒）から始め、音（`intro.wav`）も同じ時刻から鳴らす。構えの後に題字を読めるだけ待つ（`HOLD`）。

## 撃破（2026-11-14〜16）
- `rbm_flower_defeat.gd`（つなぎ。`RBMVictoryPlayer.DEFEAT` の `flower`・`flower_awakened`）＋ `rbm_flower_fx_fall.gd`（覚醒前）・`rbm_flower_fx_fall_awakened.gd`（覚醒後）。全ボス共通のとどめのスローの後に続く（胸の光の円と火花は出さない。聖獣と同じ）。
- 覚醒前: うなだれた姿（覚醒の2枚目）→ 乾いた色に褪せて震え、ドレスから花びら → 上から四角い粒でほどけ、花びらになって風に吹かれる → 床にカラーが一輪残る。
- 覚醒後（覚醒前より派手に）: 深紅の花びらの渦・オーラが燃え上がる → 背に巨大な喪華が開き、一気に枯れて弾ける → 女王がほどけて花びらに → 暗いカラーが一輪残る。
- 残った花は光を消さずに照らし続ける（2026-11-16 ユーザー「最後の花が出た時に光を消さないで聖獣と同じように照らして」。光の筋・床の淡い光・昇る粒。結果の画面まで残り、勝利の層が片付く時に一緒に消える）。
- 本体の色・震え・消え方はエフェクトの値（`body`・`view["hero"]`）を、共通の撃破の描き方（`bs.mod`・`dissolve`・`rise`・`block`・`edge`）へ移す。色の指定（褪せる・染まる）は掛け算の色に近づけて移す（共通の描き方には彩度を落とす仕組みが無い）。
- 花びらの数は 2026-11-15 に約半分にした（「花びらがありすぎて気持ち悪い」）。

## 覚醒後の常時オーラ
- `rbm_flower_sun_aura.gd`＋`shaders/sun_aura.gdshader`（金環の聖獣の太陽のオーラと同じ作り方で、色だけ喪華の深紅紫。2026-11-14 ユーザー「覚醒後はオーラ。それぞれのボスに合った色で」）。距離はポーズごとに事前に焼いた物（`assets_bossmaker/battle/flower/aura_fields/`）。待機の立ち絵（`rbm_flower_visual.gd`）・覚醒後の技・支援・撃破の間ずっと付く。

## 性能（参照機・実時間・挑戦の画面・同じ起動で各2回、2026-11-16）
- 1280×720: 5技の平均 58.4〜60.0fps。33ms超は技ごとに0〜2、覚醒は2〜3。登場・支援4種・撃破2種は平均 59.9〜60.0fps で33ms超0（20ms超も支援で1回だけ）。
- 1920×1080: 平均 57.4〜60.0fps。覚醒後の全体（背の喪華の大輪と光の解放の間）で33ms超6〜9、覚醒で4。登場は33ms超0〜1（最悪33ms）、支援・撃破は0。
- 予算の「33ms超は0」は、覚醒後の全体と覚醒（1080p）でまだ満たしていない（金環の聖獣・ヒーローと同じ種類の、画面の広い範囲の塗りの重さ）。音の最大は -4.8dB（音割れなし）。

## まだ無い物
- 専用の背景・BGM（ユーザーが後でまとめて送る。置き場所は `assets_bossmaker/battle/flower/background.png`・`assets_bossmaker/audio/bgm/flower/`）。
- ボス選択のプレビュー動画。

## 確かめ方
- テスト: `test_flower_presentations.gd`（登録・キーポーズとデータのそろい・借りるポーズ・宣言した素材・支援のポーズとオーラ・登場の花びらの増え方とお辞儀・撃破の残る花と光・数字と impact・確定した対象・中断とカウンター・覚醒でオーラ・選択と保存）、`test_rbm_presentation_warmup.gd`、ボスの一覧のテスト（`test_rbm_boss_awakening_support`・`test_rbm_appearance_picker_awakening_preview`・`test_rbm_musha_boss_selection`・`test_rbm_hardcore_victory_conditions`）。
- 実GPU: `godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_flower_gpu.gd --output=<dir>`（使い方は `verify_lion_gpu` と同じ: `--perf`（`--1080`）・`--capture`・`--selection-only`・`--defeat-only`・`--awakened-defeat`・`--new-only`・`--intro-only`）。
- 素材を作り直した時: キーポーズを `assets_bossmaker/battle/flower/motion/` に置き → `godot --headless --path . --script res://tools/flower/bake_flower_assets.gd`（立ち絵・オーラの距離・エフェクトの位置）→ `--import`。
- 音を作り直した時: `godot --headless --path . --script res://tools/flower/dump_flower_timing.gd` → `node tools/flower/audio/build.mjs`（技の名前を並べるとその音だけ）→ `tools/flower/audio/out/` の音を同じ名前で `assets_bossmaker/audio/flower/` へ → `--import`。2026-11-16 に12本とも採用した音とバイト一致を確かめた。
