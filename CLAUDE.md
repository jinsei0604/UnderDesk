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
2. **オフライン等価性**: リアルタイム進行とオフライン一括計算は同じ `tick()` を通る。tick外から sim 状態を変えるのは「プレイヤーコマンド」（add_dig_job / build_room / buy_* / apply_daily / collect_loot / offer_at_altar / exchange_item）だけ。新コマンドを足したらセーブに載せて等価性を保つ
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
  *_db.gd      データローダ（strata/room/item/shop は同じパターン）
src/meta/      セーブ（世代バックアップ3つ）・オフライン計算・設定
src/daily/     日付→共通シード（FNV-1a自前実装）
src/narrative/ 文書DB・ローカライズ（locale/*.csv手動パース）
src/window/    常駐ウィンドウ（右下ミニ小窓⇔中央展開）・fps制御
src/ui/        main.gd（全UI）・art_library.gd（PNG差し替え）
data/          全コンテンツ（JSON）。コードを触らず追加できる
tests/core/    GUT。オフライン等価性とセーブ往復が最重要
```

UI構造: 常駐ミニ小窓（320×48、右下、クリックで展開）⇔ 中央管理ウィンドウ（1152×648、右側ボタンパネル、ESCで戻る）。
経済: 掘る→回収袋(pending_loot)→展開時に一括換金→コイン→ショップ/部屋。**プレステージ（埋め戻し）は削除済み**（2026-07-12、ユーザー判断: 「先の見えない土を延々と掘り続ける」世界観に、坑道を放棄して最初からやり直す仕組みは合わないため）。坑道は一切リセットされず、地層は深く掘るほど無限に続く（`_ensure_rows`が深度に応じて自動で行を追加、最深部の地層が繰り返される）。

**パーティ制（プラン変更 2026-07-12）**: 手下制は廃止。主人公が1人で発掘を始め、
文書の発見数が data/companions/ の join_at_docs に達すると仲間が加入（最大4人、上限5人）。
仲間は物語で増えるものなので**ショップや部屋で増やしてはいけない**（宿舎はフレーバー、雇用は削除済み）。
現在定義済みなのは companion_2=リコ（文書5編で加入）のみ。残り3枠はプレースホルダごと削除済み
なので、新キャラのシートが届いたら data/companions/companion_N.json を追加するところから。

アート: minion_2.png=リコは参照シートから抽出した実素材（tools/extract_sprites.gd、原本は
assets/reference/*_sheet.png）。**minion_0（主人公）はユーザーがPixeloramaで直接描いた手描き素材**
（2026-07-13〜、詳細は下の「掘削アニメ」項目）。ユーザーが画像をチャットに貼ってもファイル化はできない
（見ることはできるが組み込みには使えない）ので、デスクトップにファイル保存 or Pixeloramaの`.pxo`
プロジェクトファイルのパスを教えてもらう（.pxoはZIPなので unzip して data.json/preview.png/
image_data/frames/N/layer_1 を読める）。地形/部屋はまだ生成ドット絵。

## コンテンツ追加レシピ（コード変更不要）

- **地層**: `data/strata/NNN_name.json`（depth_from/to, terrain, hardness, yield, documents, document_chance）。新terrainが要る場合のみ `UD.Terrain` と `TERRAIN_BY_NAME`、`main.gd` の色/アートキー追加
- **文書**: `data/documents/doc_NNN.json` ＋ `locale/ja.csv`・`en.csv` に TITLE/BODY。どこかの地層の documents 配列に入れないと出土しない。**本文はストーリー確定後に書く。勝手に増やさない**（`docs/STORY_BIBLE_v2_foreshadowing.md` は仮案。§2・§4が確定するまで最終テキスト・伏線回収は書かない。データ構造・システム側の実装には使ってよい）
  - 任意フィールド（story bible §5.1、テストで書式検証済み）: `companion_tag`, `foreshadow_ids`（["F01"…]）, `reveal_stage`（surface/mid/payoff）, `conditions`（`min_docs` / `requires_companions` / `requires_items`。条件を満たすまで出土しない。sim には `UDDocumentDB.conditions_by_id()` で注入、セーブには載せない）
  - `series`フィールド必須（書庫の2階層表示用）: `data/series/NNN_xxx.json`（id, name_key）にシリーズを定義し、文書側で参照。ファイル名順が棚の表示順。現在の分類は仮。ストーリー確定後に「メインストーリー」「◯◯外伝」等へJSON+localeだけで差し替え可
- **コレクション（宝箱アイテム）**: `data/items/xxx.json`（id, name_key, desc_key, **rank**: Z/S/A/B/C/D）＋locale 2行×2言語。目標約100種、アップデートで追加。Z・Sランクの実アイテムは未定義（ストーリー確定後にユーザーと相談して追加）
- **ショップ商品**: `data/shop/xxx.json`（base_cost, cost_mult, effect, max_level）。effect は sim 側実装が必要なら `dig_power()` / `document_chance_bonus()` / `buy_upgrade()` を参照
- **デイリー異変**: `data/anomalies/xxx.json`（effect: dig_power_add / doc_chance_add / gold_per_dig。新効果は sim に分岐追加＋テスト）
- **アート**: `assets/art/` に PNG を置くだけ（terrain_soil.png, minion_0..5.png, room_dorm.png, depot.png）。無ければ色矩形にフォールバック。置いたら `--import`
- **アニメ**: `<key>_f2.png, _f3.png...` を置くと自動でフレーム再生（基本ファイル=1フレーム目、0.4秒/コマ、IDLE中は1フレーム目固定）。アニメはUI側のみでシミュレーションに影響しない
- **キャラの向き**: スプライトは全フレーム同じ向きに統一し（tools/extract_sprites.gd の FLIP_X_OUTPUTS で調整）、main.gd の MINION_NATIVE_FACING に素材の向きを登録。逆方向は描画時に自動反転。掘削の破片は _draw_debris が対象地形の色で生成するので、素材に土煙を焼き込まないこと
- **掘削アニメ（2026-07-13更新）**: minion_0 は5コマ（idle + 振り上げ + 頂点 + 打ち込み開始 + ピーク/砂煙）。ユーザーがPixeloramaで直接描いた手描き素材に差し替え済み（旧AI生成シート版は破棄）
  - **ハマった罠1（向き不一致）**: 複数コマの素材を追加するときは全フレーム同じ向きに統一し、`FLIP_X_OUTPUTS`にも過不足なく列挙すること。逆だと掘削中だけ体が反転して見える致命的なバグになる
  - **ハマった罠2（アニメ開始位置）**: `_anim_frame`はグローバルな経過時間カウンタなので、そのままdig中のフレームインデックスに使うと**掘り始めた瞬間のアニメ位置がランダムになり、いきなり打撃コマから始まる**ことがある。main.gdの`_dig_anim_start`（IDLE/MOVING→DIGGING遷移をtickごとに検知して`_anim_frame`を記録）で、スイングは必ず振り上げ(frame 1)から始まるようにしている
  - **ハマった罠3（背景の不透明化・スケール不一致）**: Pixeloramaで書き出したPNGは、①レイヤーの背景が黒で塗りつぶされたまま不透明で保存される場合があり、Godotの`get_pixel().a`で確認しないと見た目だけでは気づきにくい ②手描きだとコマごとにキャラの大きさが微妙にズレやすく、ループ再生すると「膨張と収縮」に見える。**新規に複数コマの素材を受け取ったら、必ずコマごとに背景を透明化（角ピクセル基準でフラッドフィル、tools/extract_sprites.gd と同じ許容誤差0.06〜0.075）→トリムしてコンテンツの高さを測る→全コマが同じ高さになるよう拡大縮小してから128×128に配置し直すこと**（1コマだけ極端に小さい/大きいと一発でわかる）
- **新しい参照シート（10×4グリッド等、番号バッジ付き）を追加する場合**: extract_sprites.gd に "grid"+"cell_crops" 形式のプリセットを足せば、セル番号→出力名の指定だけで自動クロップできる（ERASE_TOP_LEFTでバッジを消去）。ただしAI生成シートは列幅が均一グリッド計算どおりにならないことがあるので、生成後は必ず全コマを目視確認し、隣接ポーズがにじんだフレームは別インデックスに差し替えること（実例: miner_sheet_v2.png の idx20・idx27はどう幅を絞ってもにじんだため採用を見送った）
- locale CSV は `key,text` 形式（FileAccess.get_csv_line でパース、カンマを含む本文は引用符で囲む）

## 実装済みの主要システム（2026-07-12〜13セッションで追加）

- **侵入者イベントは実装後に削除された**（ユーザー判断、2026-07-12夕）。復活させないこと。旧セーブの罠部屋は main.gd の _ready で未知部屋として除去される
- **アイテムランク＋スタック所持（セーブv5）**: 宝物は rank（Z>S>A>B>C>D、items JSONの`rank`フィールド）と所持数を持つ。上限 UD.ITEM_RANK_CAPS（Z10/S50/A100/B200/C・D500）。`sim.items` は id→count 辞書（v4配列から自動移行）。ランク表は `UDItemDB.ranks_by_id()` で sim に注入
- **祭壇のお供え**: `sim.offer_at_altar(item_id)`。コイン費用は UD.ALTAR_OFFER_BASE_COST×1.4^Lv、+1掘削力/Lv、Lv5からは UD.ALTAR_ITEM_RANK_TIERS のランクの宝物1個も消費。祭壇建設が前提。プレステージ削除に伴い、坑道と同様に一切リセットされない永続効果
- **ギルド交換**: 酒場はギルドに改名（room idは`tavern`のまま、locale名のみ変更）。`sim.exchange_item(target, consume)` で下位ランク消費→上位1個（レートは UD.ITEM_EXCHANGE_COSTS: Z←S×3/S←A×5/A←B×7/B←C×10、C・Dは宝箱限定）。**配信プラットフォームはitch.ioに決定（2026-07-12）。対人交換は将来のネットワーク連携で同じコマンドに載せる設計**（itch.ioにはSteamのようなインベントリ/実績APIが無いため、実装時は自前サーバーか外部サービスを想定）。UIの消費内訳は所持数の多い順に自動選択
- **チュートリアル**: settings.tutorial_seen ＋ 最初の UD.TUTORIAL_TICKS の間、帯/大画面にローテーションヒント（TUT_HINT_*）
- **文書の出土条件**: documents JSON の conditions（min_docs/requires_companions/requires_items）を `_roll_document` で判定
- **調査書カード機能は削除済み（2026-07-12、ユーザー判断）**: 公開前は見せる相手がいないため撤去。マーケティング施策で必要になったら `git log` から `src/daily/survey_card.gd` / `src/window/clipboard.gd` を復元すること。デイリー異変システム自体（`UDDaily`・`data/anomalies/`）は現役
- **手下の見た目バグ修正(2026-07-12)**: 仲間の描画アート/向きは`minion.id`（パーティ内の並び順）ではなく**companion_id由来のart_variant**（`UDMinion.art_variant_for_companion`、main.gdの`_minion_art_variant`）で決める。IDがずれると仲間が無名のプレースホルダー四角として表示される
- **ダイアログのイラスト化**: ショップ/宝物/書庫は`UDCardDialog`（羊皮紙カードグリッド＋右の詳細パネル、src/ui/card_dialog.gd）。祭壇・ギルドも同じウィジェットを使用。カードのアイコンは`UDArtLibrary.icon_or_placeholder(key, seed, shape)`が実アート（`item_<id>.png`/`shop_<id>.png`/`<doc_id>.png`）があればそれを使い、無ければ`placeholder_icon`で手続き生成（gem/rune/book形状、seedからHSVで色決定）。実アートを置くだけで自動的に差し替わる
- **祭壇/ギルドはワンクリックで開く（2026-07-13、手動配置は撤廃）**: 未建設ならボタン押下時に`_auto_build`が拠点(depot)近くの掘削済み空きマスを自動検索して即建設し、そのままダイアログを開く（コスト消費は従来どおり、置き場所選択の手間だけ排除）。建設済みならダイアログを直接開く。手動配置(`_select_build_room`→掘削済みマスをクリックして配置)は**宿舎(dorm、フレーバー専用)にのみ残存**。ダンジョン画面上に建てたタイル自体をクリックしても画面が開く（main.gdの`_room_id_at_cell`、DIGモードでのクリック時にまず建物判定してから掘削判定に落ちる）

## 未実装（設計図）

1. **配信プラットフォーム連携**（配信プラットフォームはitch.ioに決定、2026-07-12）: `src/platform/` に抽象化済み（`UDPlatform`）。itch.ioにはSteamworksのような実績/クラウドセーブAPIが無いため、実績（`UDAchievements`）は当面ローカル保存のみで運用。将来ネットワーク機能（ギルドの対人交換など）が必要になったら自前サーバーか外部サービスの検討が必要
2. **手記書き直し**: ストーリーバイブル（docs/STORY_BIBLE_v2_foreshadowing.md、現状は仮案）の§2・§4確定後。既存13編は仮
3. **地形/部屋の本番アート**: 現在は生成ドット絵。assets/art/ に規約名PNGを置くだけで差し替わる
4. **部屋の隣接ボーナス**（§5.2、MVPチェックリスト）: 未着手

## パフォーマンス予算（§7.1、超えたら実装を差し戻す）

アイドルCPU 1%未満（実測0.2〜0.3%）・メモリ200MB目標。毎フレーム処理を追加しない。
描画は tick 毎の queue_redraw のみ。非フォーカス時 fps10、最小化時は描画停止。
