# ボス選択画面用プレビュー

収録対象はスライム・朽ちた機械武者・宇宙飛行士・幽霊・竜のみ。
単体攻撃 / 全体攻撃の各2本。武者と宇宙飛行士は覚醒後も各2本（合計14本）。竜は通常（覚醒前）の2本だけ（2026-10-29 追加。
撮り方は同じ capture_case()、prototypes/dragon_preview_2026-10-29/tools/capture_dragon_previews.gd）。
既存の RBMBattleStage と専用の戦闘演出・背景・キャラクター素材を実GPUで録画したもの。
新規のキャラクター画像・攻撃演出は制作していない。Steam紹介動画とは独立した素材。

## 形式・UI

- Ogg Theora、640×360、30fps、音声トラックなし。Godot標準のVideoStreamPlayerで再生。
- 攻撃の前後に待機を含む。演出の途中はカットせず、終了して通常の配置へ戻るまで収録。
- 通常 / 覚醒後、単体 / 全体はファイル名に対応。
- 対象外は読み込まない。動画のないボスは既存の準備中表示。
- UIは2枠のアスペクト比を維持し、一時停止と非表示時の停止に対応。
- 戦闘ロジック・乱数・保存データをUI再生に使用しない。

## 再収録

作業用プロジェクトで以下を実行する（本番の保存先とは別のAPPDATAを使用）。

```text
godot --path <作業用プロジェクト> --windowed --resolution 960x540 --fixed-fps 30 --audio-driver Dummy res://tools/gpu_runner.tscn -- --tool=res://tools/capture_boss_picker_previews.gd --output=<フレーム出力先>
ffmpeg -framerate 30 -i <出力先>/<id>/%04d.png -vf scale=640:360:flags=lanczos -c:v libtheora -q:v 8 -pix_fmt yuv420p -an <id>.ogv
```

capture.jsonで各演出の完走、impactが1回、simulation_unchangedを確認する。
manifest.jsonに今回の動画と撮影に使用したソースのハッシュを記録。
固定fpsの撮影は映像確認用。UI再生性能はverify_boss_picker_video_gpu.gdを固定fpsなしで別途検証する。
