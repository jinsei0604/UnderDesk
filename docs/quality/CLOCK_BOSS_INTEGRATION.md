# 振り子の給仕長／終刻の給仕長 — 本番への組み込み（2026-11-16）

- 外見ID `appearance_clock`、通常 `clock`、覚醒後 `clock_awakened`。熔鉱炉の番人の後ろ（15体目）に追加。表示名「振り子の給仕長」（英語は仮に「Pendulum Steward」）。覚醒あり。既存の Creator の条件・回復・強化・保存の方式をそのまま使い、技の性能値は固定しない。戦闘の計算・乱数・行動順・保存の仕様は変えていない。
- 2026-11-11〜16 に試作（`prototypes/four_bosses_2026-11-11/`、確認動画 `out/clock_v3.mp4`・直しの `out/clock_v4.mp4`）でユーザーが採用した5技をそのまま移した（2026-11-16 ユーザー「これが終わったら実装していいよ」）。作りは金環の聖獣・白磁のカラー・熔鉱炉の番人（[LION_BOSS_INTEGRATION.md](LION_BOSS_INTEGRATION.md)・[FLOWER_BOSS_INTEGRATION.md](FLOWER_BOSS_INTEGRATION.md)）と同じ。
- **登場・支援・撃破はまだ専用の物が無い**（ユーザーが試作の動画を見て決めてから入れる）。それまでは全ボス共通の登場・支援・倒れ方（`RBMVictoryPlayer.DEFEAT` の `clock`・`clock_awakened` に共通の `rbm_defeat_generic.gd`）。
- 本体は Codex のキーポーズ（`assets_bossmaker/battle/clock/motion/<技>/<番号>.png`）をそのまま切り替えるだけ。立ち絵: 覚醒前＝覚醒の1枚目、覚醒後＝覚醒の5枚目。体の高さ（88・94ドット）を2倍で表示（176・188）。

## 技（`src/bossmaker/visuals/clock/`）— 技ごとに「意味」を一本通す（2026-11-16 ユーザー「ぽい物をつなげているように見える。一つ一つに意味を」）
給仕長はクールで精密なキャラクター。迫力は緩急で出す: 止まる前は時計が刻む → 止まっている間は静寂 → 動き出した瞬間に止めていた一撃がまとめて届く（色が一気に戻る・閃光・ヒットストップ・大きな揺れ）。

| 戦闘の行動 | 意味と流れ | 最後の一撃 | 音（`assets_bossmaker/audio/clock/`） |
|---|---|---|---|
| 覚醒前の単体「指針突き」 | 定められた時刻: 懐中時計の12時が光る → 秒針が三つ刻んで12時で時が止まる → 針を胸の手前で止める → 動いた瞬間に貫く | `T.resume` | `single.wav` |
| 覚醒前の全体「時刻の指揮」 | 彼の腕が大時計の針: 4拍の指揮で分針が一人ずつの上へ跳び、針が貫く → 両針が12時で鐘 → 大時計が砕ける | `T.chime` | `all.wav` |
| 覚醒「振り子の分岐」 | 顔の時計の針が狂う（描かれた顔と同じ大きさの文字盤を重ねて針だけ回す）→ 時が止まる → 大時計にひび → 一本の振り子が過去（青緑）と未来（深紅）に分かれる → 二つが12時でぶつかり大時計が砕ける | なし | `awakening.wav` |
| 覚醒後の単体「狂針の宣告」 | 宣告（秒針が12時でぴたり・深紅の目盛り）→ 止まった時の中で六か所から針を打ち込む連撃 → 動くと6回当たる（小さな数字）→ 頭上から振り子のおもりで執行 | `T.pendulum` | `awakened_single.wav` |
| 覚醒後の全体「終刻の制止」 | 四人の頭上に鎖で吊られた「その人の時計」→ 空の大時計が12時で時が止まる → 一つずつ砕く（かけらは宙で止まる）→ 動くとかけらが持ち主へ飛び込む → 空の大時計が砕ける | `T.burst` | `awakened_all.wav` |

- 部品（`rbm_clock_fx_base.gd`）: `shaders/clockface.gdshader`（厚みのある懐中時計: 浮き彫りの真鍮の縁・側面・白磁の盤・目盛り・ブレゲ針・照り返し・定められた時刻の目盛り `hot_mark`。`plain` で振り子のおもり。ひびは割れた点 `crack_at` から伸びるガラスのひびで、かけらもそのひびの線で分かれる＝2026-11-16 ユーザー「ひび割れが少し不自然」の直し）、`shaders/gear.gdshader`（真鍮の歯車）、ブレゲ針・ガラスのかけら（三角を作らない）・時が止まる見た目（`time_stop_post`）・画面を横切る巨大な秒針（`sweep_hand`）・振り子（`pendulum`）。
- 平らな光の円・輪、体や大きな物の近くの熱のゆがみ（`refract_wave`。振り子のおもりがゆがんだ）は使わない。
- 覚醒後の常時オーラ: `rbm_clock_sun_aura.gd`（真夜中の青緑。金・深紅・溶岩色と重ならない）。

## まだ無い物
- 専用の登場・支援・撃破（試作して動画で確認してから）。
- 専用のBGM（背景は 2026-11-16 に追加済み: 時計塔の大広間。ボス選択のプレビュー動画も同日追加）。

## 確かめ方
- テスト: `test_clock_presentations.gd`（登録・キーポーズとデータのそろい・宣言した素材・数字と impact・覚醒後の単体の連撃・確定した対象・中断とカウンター・覚醒でオーラ・選択と保存）、`test_rbm_presentation_warmup.gd`、ボスの一覧のテスト。
- 実GPU: `godot --path . res://tools/gpu_runner.tscn -- --tool=res://tools/verify_clock_gpu.gd --output=<dir>`（`verify_lion_gpu` と同じ使い方。登場・支援の場合は専用の物ができてから）。
- 素材を作り直した時: `godot --headless --path . --script res://tools/clock/bake_clock_assets.gd` → `--import`。
- 音を作り直した時: `godot --headless --path . --script res://tools/clock/dump_clock_timing.gd` → `node tools/clock/audio/build.mjs` → `tools/clock/audio/out/` の音を同じ名前で `assets_bossmaker/audio/clock/` へ → `--import`（2026-11-16 に5本とも採用した音とバイト一致）。
