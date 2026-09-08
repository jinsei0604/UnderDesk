# Makers & Challengers 開発ガイド

このリポジトリはMakers & Challengers専用です。Godot 4.7を使用します。
起動・インポート・全GUTコマンドと構成はREADME.mdを参照してください。作業ディレクトリ基準の`--path .`を優先し、個人の一時フォルダをコードへ固定しないでください。

## 変更時の規則

- `src/bossmaker/rbm_game_root.tscn`が起動ルート。`bossmaker`/`RBM`は既存識別子として保持。
- 戦闘性能・乱数・行動順・SIMPLE/HARDCORE・action_sequence・保存/復元仕様は、依頼の対象でない限り変更しない。
- 表示/SEは確定済み戦闘イベントを読む。表示のために戦闘状態や戦闘乱数を進めない。
- 既存のユーザー変更を破棄しない。作業前にGit状態を確認。コミット/プッシュは依頼があるときだけ行う。
- 変更範囲に適した既存テストを実行。今回の基準は42 scripts / 1046 tests / 12205 assertions / failures 0。
- 新規リソースはインポートし、missing resource / parser error / invalid pathを確認。
- UI/戦闘演出の変更は関連するtools/verify_*の実GPU検証も行う。テストのために本番ロジックを変更してPASSさせない。
- `.env`等のローカル秘密情報を出力・コミットしない。Supabase設定とAPI互換識別子を名称整理だけで変更しない。

現行仕様は実装・data_bossmaker・tests/bossmakerで確認してください。src/bossmaker/README.mdには旧フェーズの履歴も含むため、古い記録と現状を区別してください。
