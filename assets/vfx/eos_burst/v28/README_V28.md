# ソティリス Eos Burst V28 表示所有ロック

V27の実機動画で発生した「剣オーラだけが動き、ソティリスは待機姿勢のまま」という表示競合を修正する版です。

## 原因

17コマのEos用モーションは進行していましたが、通常戦闘の待機Sprite2Dが同じ位置の上側へ再表示され、動いているモーションSprite2Dを隠していました。剣オーラは別ノードなので、そのまま動いて見えていました。

## 修正

- 通常ソティリス、MotionA、MotionBを必ず別々のSprite2Dとして扱う
- MotionAとMotionBを通常ソティリスよりZ値20だけ上へ固定
- 通常ソティリスをZ値20だけ下げ、毎フレーム非表示へ戻す
- MotionAとMotionBのtexture、hframes、frame、visible、Z値を毎フレーム再設定
- オーラとキャラクターが同じframe_indexとnext_frameを使う
- 終了時は通常ソティリスの元のtexture、frame、transform、Z値、表示状態を復元

カットインなし、前方振り下ろし、溜め、斬撃、着弾、爆発の内容と時間はV27から変更していません。

参照実装は godot/eos_burst_v28_reference.gd です。期待する動きは previews/v28_expected_character_motion_preview.mp4 です。

Claude Code用の指示は CLAUDE_CODE_PROMPT_V28_JA.txt です。実装専用で、テスト・ゲーム起動・ビルド・検証実行は禁止しています。
