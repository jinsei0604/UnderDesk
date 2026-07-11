# UNDERDESK 開発ガイド（Claude Code向け）

デスクトップ常駐型 放置ダンジョン経営ゲーム。Godot 4.7 / GDScript。
**仕様の正は `docs/design.md`**（企画書）。迷ったら §12（規約）と §5（システム詳細）を優先。

## コマンド

```powershell
# テスト（変更したら必ず実行。全件グリーンを維持すること）
& C:\src\tools\godot\Godot_v4.7-stable_win64_console.exe --headless --path C:\src\underdesk -s res://addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit

# 新しい class_name / データファイル / PNG を追加したら再インポート必須
# （やらないとヘッドレスで「Identifier not declared」になる）
& C:\src\tools\godot\Godot_v4.7-stable_win64_console.exe --headless --path C:\src\underdesk --import

# スクリプト単体の構文チェック
& C:\src\tools\godot\Godot_v4.7-stable_win64_console.exe --headless --path C:\src\underdesk --check-only --script res://src/ui/main.gd

# 実行
& C:\src\tools\godot\Godot_v4.7-stable_win64.exe --path C:\src\underdesk
```

- コミット後は `git push origin main`（リモート: github.com/jinsei0604/UnderDesk, private）
- PowerShell 5.1 から git commit する際、**メッセージに二重引用符を入れない**（here-stringでも引数が壊れる）

## 鉄則（破ると進行破壊バグになる）

1. **決定性**: シミュレーションの乱数は必ず `UDSim._rng` から。`randi()`や`randomize()`をcoreで使わない。UI側でも sim の状態を変える乱数は禁止
2. **オフライン等価性**: リアルタイム進行とオフライン一括計算は同じ `tick()` を通る。tick外から sim 状態を変えるのは「プレイヤーコマンド」（add_dig_job / build_room / buy_* / apply_daily / collect_loot / prestige_reset）だけ。新コマンドを足したらセーブに載せて等価性を保つ
3. **セーブ互換**: `to_dict`/`from_dict` に項目を足すときは `d.get("key", default)` で旧セーブを許容。互換を壊す変更は `UD.SAVE_VERSION` を上げて from_dict 内で移行処理（例: v1→v2 資源→コイン換金、v2→v3 運搬手下の正規化）
4. **RNGのseed/stateはstringで保存**（JSONでint64がfloat化けするため）。同様に64bit整数をセーブに載せるときはstring化
5. **coreはGodotノード非依存**（RefCountedのみ）。OS依存は `src/window/`、表示は `src/ui/` に隔離
6. GDScriptは**静的型付け必須**・マジックナンバー禁止（`UD`定数 or データファイル）
7. typed Array に untyped `[]` を代入しない（ランタイムエラー）。空にするなら `.clear()`
8. テスト必須: 新しいコマンド/効果には「決定性」「セーブ往復」のテストを付ける。既存パターンは tests/core/ を参照

## アーキテクチャ

```
src/core/      純ロジック。UDSim が心臓部（tick制・2秒/tick）
  sim.gd       状態＋コマンド＋シリアライズ。全ゲームルールはここ
  constants.gd UD.* 定数・enum
  *_db.gd      データローダ（strata/room/item/shop は同じパターン。prestige は UDShopDB を再利用）
src/meta/      セーブ（世代バックアップ3つ）・オフライン計算・設定
src/daily/     日付→共通シード（FNV-1a自前実装）・調査書カード
src/narrative/ 文書DB・ローカライズ（locale/*.csv手動パース）
src/window/    常駐ウィンドウ（右下ミニ小窓⇔中央展開）・fps制御
src/ui/        main.gd（全UI）・art_library.gd（PNG差し替え）
data/          全コンテンツ（JSON）。コードを触らず追加できる
tests/core/    GUT。オフライン等価性とセーブ往復が最重要
```

UI構造: 常駐ミニ小窓（320×48、右下、クリックで展開）⇔ 中央管理ウィンドウ（1152×648、右側ボタンパネル、ESCで戻る）。
経済: 掘る→回収袋(pending_loot)→展開時に一括換金→コイン→ショップ/部屋。プレステージで結晶→恒久ツリー。

**パーティ制（プラン変更 2026-07-12）**: 手下制は廃止。主人公が1人で発掘を始め、
文書の発見数が data/companions/ の join_at_docs に達すると仲間が加入（最大4人、上限5人）。
仲間は物語で増えるものなので**ショップや部屋で増やしてはいけない**（宿舎はフレーバー、雇用は削除済み）。
現在定義済みなのは companion_2=リコ（文書5編で加入）のみ。残り3枠はプレースホルダごと削除済み
なので、新キャラのシートが届いたら data/companions/companion_N.json を追加するところから。

アート: minion_0.png=主人公、minion_2.png=リコ。どちらも**本物のイラストから抽出した実素材**
（tools/extract_sprites.gd、原本は assets/reference/*_sheet.png）。ユーザーが画像をコピーしたら
「コピーした」の一言で合図してもらい、PowerShellの [Windows.Forms.Clipboard]::GetImage() で
保存→ツールでクロップ・背景透過・128pxリサイズ・必要なら左右反転。地形/部屋はまだ生成ドット絵。

## コンテンツ追加レシピ（コード変更不要）

- **地層**: `data/strata/NNN_name.json`（depth_from/to, terrain, hardness, yield, documents, document_chance）。新terrainが要る場合のみ `UD.Terrain` と `TERRAIN_BY_NAME`、`main.gd` の色/アートキー追加
- **文書**: `data/documents/doc_NNN.json` ＋ `locale/ja.csv`・`en.csv` に TITLE/BODY。どこかの地層の documents 配列に入れないと出土しない。**本文はストーリー確定後に書く。勝手に増やさない**（`docs/STORY_BIBLE_v2_foreshadowing.md` は仮案。§2・§4が確定するまで最終テキスト・伏線回収は書かない。データ構造・システム側の実装には使ってよい）
  - 任意フィールド（story bible §5.1、テストで書式検証済み）: `companion_tag`, `foreshadow_ids`（["F01"…]）, `reveal_stage`（surface/mid/payoff）, `conditions`（`min_docs` / `requires_companions` / `requires_items`。条件を満たすまで出土しない。sim には `UDDocumentDB.conditions_by_id()` で注入、セーブには載せない）
- **コレクション（宝箱アイテム）**: `data/items/xxx.json`（id, name_key, desc_key）＋locale 2行×2言語。目標約100種、アップデートで追加
- **ショップ商品**: `data/shop/xxx.json`（base_cost, cost_mult, effect, max_level）。effect は sim 側実装が必要なら `dig_power()` / `document_chance_bonus()` / `buy_upgrade()` を参照
- **恒久ツリー**: `data/prestige/xxx.json`（同スキーマ、通貨は結晶）
- **デイリー異変**: `data/anomalies/xxx.json`（effect: dig_power_add / doc_chance_add / gold_per_dig。新効果は sim に分岐追加＋テスト）。任意で `card_color`（#rrggbb）を持たせると調査書カードの紙がその色に染まる
- **防衛部屋**: 部屋 JSON の effect を `defense_add` にすると侵入者防衛+1（例: data/rooms/trap.json）
- **アート**: `assets/art/` に PNG を置くだけ（terrain_soil.png, minion_0..5.png, room_dorm.png, depot.png）。無ければ色矩形にフォールバック。置いたら `--import`
- **アニメ**: `<key>_f2.png, _f3.png...` を置くと自動でフレーム再生（基本ファイル=1フレーム目、0.4秒/コマ、IDLE中は1フレーム目固定）。アニメはUI側のみでシミュレーションに影響しない
- **キャラの向き**: スプライトは全フレーム同じ向きに統一し（tools/extract_sprites.gd の FLIP_X_OUTPUTS で調整）、main.gd の MINION_NATIVE_FACING に素材の向きを登録。逆方向は描画時に自動反転。掘削の破片は _draw_debris が対象地形の色で生成するので、素材に土煙を焼き込まないこと
- locale CSV は `key,text` 形式（FileAccess.get_csv_line でパース、カンマを含む本文は引用符で囲む）

## 実装済みの主要システム（2026-07-12夜間セッションで追加）

- **侵入者イベント**（§5.2）: UD.INTRUDER_INTERVAL_TICKS 毎に tick 内で決定的に発生。防御=defense_add部屋数+ショップ/恒久のdefense_add、撃退で戦利品コイン・突破でコイン強奪（0未満にはならない）。結果は `sim.event_log`（上限 UD.EVENT_LOG_MAX、セーブ互換は d.get）。UIは「事件簿」ダイアログ＋帯トースト
- **チュートリアル**: settings.tutorial_seen ＋ 最初の UD.TUTORIAL_TICKS の間、帯/大画面にローテーションヒント（TUT_HINT_*）
- **文書の出土条件**: documents JSON の conditions（min_docs/requires_companions/requires_items）を `_roll_document` で判定
- **調査書カードv2**: 異変色の紙・調査済スタンプ・宝物/結晶行・クリップボード自動コピー（UDClipboard、OS依存はsrc/window/）

## 未実装（設計図）

1. **Steam連携**（P4以降）: `src/platform/` に抽象化。実績は discovered_documents / resets / items.size() に連動
2. **手記書き直し**: ストーリーバイブル（docs/STORY_BIBLE_v2_foreshadowing.md、現状は仮案）の§2・§4確定後。既存13編は仮
3. **地形/部屋の本番アート**: 現在は生成ドット絵。assets/art/ に規約名PNGを置くだけで差し替わる
4. **部屋の隣接ボーナス**（§5.2、MVPチェックリスト）: 未着手

## パフォーマンス予算（§7.1、超えたら実装を差し戻す）

アイドルCPU 1%未満（実測0.2〜0.3%）・メモリ200MB目標。毎フレーム処理を追加しない。
描画は tick 毎の queue_redraw のみ。非フォーカス時 fps10、最小化時は描画停止。
