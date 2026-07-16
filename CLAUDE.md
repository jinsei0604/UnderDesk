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
2. **オフライン等価性**: リアルタイム進行とオフライン一括計算は同じ `tick()` を通る。tick外から sim 状態を変えるのは「プレイヤーコマンド」（add_dig_job / buy_upgrade / apply_daily / collect_loot / offer_at_altar / exchange_item）だけ。新コマンドを足したらセーブに載せて等価性を保つ
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
  *_db.gd      データローダ（strata/item/shop は同じパターン。facility も UDShopDB を再利用）
src/meta/      セーブ（世代バックアップ3つ）・オフライン計算・設定
src/narrative/ 文書DB・ローカライズ（locale/*.csv手動パース）
src/window/    常駐ウィンドウ（右下ミニ小窓⇔中央展開）・fps制御
src/ui/        main.gd（全UI）・art_library.gd（PNG差し替え）
data/          全コンテンツ（JSON）。コードを触らず追加できる
tests/core/    GUT。オフライン等価性とセーブ往復が最重要
```

UI構造: 常駐ミニ小窓（320×48、右下、クリックで展開）⇔ 中央管理ウィンドウ（1152×648、右側ボタンパネル、ESCで戻る）。
経済: 掘る→回収袋(pending_loot)→展開時に一括換金→コイン→ショップ/部屋。**プレステージ（埋め戻し）は削除済み**（2026-07-12、ユーザー判断: 「先の見えない土を延々と掘り続ける」世界観に、坑道を放棄して最初からやり直す仕組みは合わないため）。坑道は一切リセットされず、無限に続く。

**掘削は横穴に転換（2026-07-14、ユーザー判断・リファレンス画像準拠）**: 旧来の「下へ掘り下げる縦穴＋蛇行」を廃止し、**固定高さ(`UD.CORRIDOR_HEIGHT`=3)の横穴を右へ無限に掘り進める**方式に。`UDGrid`は高さ固定・`append_column`で右へ成長（行主格納なので追加時に再構築、アイドル頻度なら安価）。地層は`depth_from/to`を**入口からの水平距離**として解釈（`UDStrataDB.*_for_distance`）。自動掘削`RIGHT`ポリシー(旧`DOWN`、enum値1のまま=セーブ互換)は**面の1列を上下フルに掘り切ってから右へ進む**(`_face_column`)。左掘り・蛇行なし。進捗/カメラ/実績の「深さ」指標=`frontier_distance()`(=掘った水平距離)。`main.gd`は縦スクロール廃止(3行が画面に収まる)・カメラは主人公を横追尾・可視列だけ描画(トンネルは数千セル長になりうるのでカリング必須)。地形は全ソリッドが`terrain_rock`(§下記アート)で描画、AIRは背景=掘削済み。**セーブv6→v7**: 旧縦穴はグリッド形状が別物なので`from_dict`で新しい横穴に作り直し(コイン/宝物/文書/仲間/強化は保持)。

**パーティ制（プラン変更 2026-07-12）**: 手下制は廃止。主人公が1人で発掘を始め、
文書の発見数が data/companions/ の join_at_docs に達すると仲間が加入（最大4人、上限5人）。
仲間は物語で増えるものなので**ショップや部屋で増やしてはいけない**（宿舎はフレーバー、雇用は削除済み）。
**現在 data/companions/ は空**（2026-07-15、ユーザー判断でリコ=companion_2 を一旦全削除。作り直したものを後で渡すとのこと。`.gitkeep`で空ディレクトリ維持）。データ・アート(minion_2*/riko_*/assets/reference/riko_sheet.png)・locale(COMPANION_2_NAME)を削除。物語設定 docs/characters/riko.md とストーリーバイブルの記述は再制作の参考に残置。既存セーブでリコが加入済みでも、`from_dict`のプルーン処理(companion defs が空でも実行)で主人公1人に戻る。新キャラのシートが届いたら data/companions/companion_N.json ＋ minion_N.png を追加するところから。`UDMinion.art_variant_for_companion`(idの末尾数字→variant)は汎用なので残置。

アート: **minion_0（主人公）はユーザーがPixeloramaで直接描いた手描き素材**
（2026-07-13〜、詳細は下の「掘削アニメ」項目）。ユーザーが画像をチャットに貼ってもファイル化はできない
（見ることはできるが組み込みには使えない）ので、デスクトップにファイル保存 or Pixeloramaの`.pxo`
プロジェクトファイルのパスを教えてもらう（.pxoはZIPなので unzip して data.json/preview.png/
image_data/frames/N/layer_1 を読める）。地形/部屋はまだ生成ドット絵。

## コンテンツ追加レシピ（コード変更不要）

- **地層**: `data/strata/NNN_name.json`（depth_from/to, terrain, hardness, yield, documents, document_chance）。新terrainが要る場合のみ `UD.Terrain` と `TERRAIN_BY_NAME`、`main.gd` の色/アートキー追加
- **文書**: `data/documents/doc_NNN.json` ＋ `locale/ja.csv`・`en.csv` に TITLE/BODY。どこかの地層の documents 配列に入れないと出土しない。**本文はストーリー確定後に書く。勝手に増やさない**（`docs/STORY_BIBLE_v2_foreshadowing.md`＋`docs/STORY_BIBLE_v5.md`（v5は行商人アナスタス/世界名アビュソス/ソストラトス初出エピソードの確定＋v2からの追記）を合わせて参照。v2の§2・§4（核心の真実・伏線カタログ）とv5の§4（仲間のストーリー設定など）はまだ未確定なので、最終テキスト・伏線回収は書かない。データ構造・システム側の実装には使ってよい）
  - 任意フィールド（story bible §5.1、テストで書式検証済み）: `companion_tag`, `foreshadow_ids`（["F01"…]）, `reveal_stage`（surface/mid/payoff）, `conditions`（`min_docs` / `requires_companions` / `requires_items`。条件を満たすまで出土しない。sim には `UDDocumentDB.conditions_by_id()` で注入、セーブには載せない）
  - `series`フィールド必須（書庫の2階層表示用）: `data/series/NNN_xxx.json`（id, name_key）にシリーズを定義し、文書側で参照。ファイル名順が棚の表示順。現在の分類は仮。ストーリー確定後に「メインストーリー」「◯◯外伝」等へJSON+localeだけで差し替え可
- **コレクション（宝箱アイテム）**: `data/items/xxx.json`（id, name_key, desc_key, **rank**: Z/S/A/B/C/D）＋locale 2行×2言語。目標約100種、アップデートで追加。Z・Sランクの実アイテムは未定義（ストーリー確定後にユーザーと相談して追加）
- **ショップ商品**: `data/shop/xxx.json`（base_cost, cost_mult, effect, max_level）。effect は sim 側実装が必要なら `dig_power()` / `document_chance_bonus()` / `buy_upgrade()` を参照
- **施設（祭壇/ギルド/宿舎）**: `data/facilities/xxx.json`（ショップと同スキーマ、max_level常に1の一回限り解禁）。地図配置は無く、ボタン一つで`buy_upgrade()`→即座にダイアログが開く。新しい施設を足す場合は`main.gd`の`_on_facility_button`にmatch節を1つ追加するだけ
- **アート**: `assets/art/` に PNG を置くだけ（terrain_soil.png, minion_0..5.png, room_altar.png/room_tavern.png/room_dorm.png（施設アイコン、キー接頭辞は`room_`のまま）, depot.png）。無ければ色矩形/プレースホルダーアイコンにフォールバック。置いたら `--import`
- **書庫のシリーズアイコン**: `assets/art/series_<series_id>.png`（data/series/のid、例: series_journal.png）。`UDCardDialog`のシリーズ棚カードに使われる。`UDArtLibrary.load_default()`に`series_ids`（`doc_series`から抽出）を渡さないと認識されないので注意
- **ダイアログの背景イラスト（2026-07-13〜、ユーザーの自作ドット絵を6画面に順次組み込む予定の1本目）**: `assets/art/dialog_bg_<archive|treasure|shop|altar|guild|dorm>.png` を置くと、対応する`UDCardDialog`のカードグリッド背後に敷かれる。**背景はダイアログ全体を覆う**（`_background_rect`は`root`直下・全面、`STRETCH_KEEP_ASPECT_COVERED`）。6画面すべて`enable_art_chrome(title, close)`で**枠なし＋中央タイトル＋右上「✕ 閉じる」ボタン**のアート主導UIに統一済み（ショップはタイトル/閉じる/コインが画像に焼き込み＋看板ホットスポット、他5枚はコードでクロームを重ねる）。`main.gd`の各`_build_xxx_dialog()`で`set_background_frames(_dialog_bg_frames("dialog_bg_xxx"))`を渡すだけ。未配置なら非表示（従来通りの暗いキャビネット地）。合成済みのモックアップ画像しか届かない場合は、Godotの`Image.get_region()`でカード領域・背景領域を切り出し、アイコン部分は`tools/extract_sprites.gd`と同じフラッドフィル透明化＋トリム＋正方形化を再利用する
  - **背景アニメ（2026-07-15〜、全画面にアニメを付ける計画の土台）**: `dialog_bg_xxx_f2.png, _f3.png...`を置くと、そのダイアログが開いている間だけ背景がフレーム連番でループ再生する（例: 書庫のロウソクの炎が揺れる）。`UDCardDialog`が自前のTimer（`BG_ANIM_SECONDS`=0.22秒/コマ）で回し、**閉じている間は停止**するので§7.1のアイドルCPU予算に影響しない。スプライトの`_fN`規約と同じ仕組みを`art.frame_count`/`art.frame`経由で流用。フレームを置かなければ従来通り静止（1枚）。**ホットスポットのクリック判定について**: 背景の上に重ねる透明ボタン層`_hotspot_layer`は必ず`MOUSE_FILTER_IGNORE`（`PASS`だとイベントを親にだけ渡し、背後の`column`のカード/戻る/閉じる/購入ボタンが全部押せなくなる。2026-07-15に踏んだ罠）。**コードだけの疑似アニメ（`enable_flicker()`）は2026-07-15に一度追加して同日中に削除済み**（絵無しで背景の明るさを正弦波で揺らすロウソク代替。ユーザーが実アニメ用の絵を用意する方針になったため撤去。同じ発想が再度必要になったら`git log`で`Add code-only flicker pseudo-animation`のコミットを参照）
  - **ダイアログの額縁オーバーレイ（2026-07-16実装）**: `assets/art/dialog_frame.png`（ユーザー提供の1536x1024イラストを黒背景flood-fill透明化→28%に縮小した430x287版）を`UDCardDialog.set_frame_overlay(tex)`で書庫/宝物/祭壇/ギルド/宿舎の5画面に適用。**ショップだけ意図的に対象外**（2026-07-16、実装後にプレビュー画像で確認して判断）: `dialog_bg_shop.png`は看板ボタン/コインバッジ/閉じるプラークが画像の端近くまで焼き込まれており、額縁の~53px枠がそれらを物理的に覆い隠す（コインバッジは半分近く隠れた）。既存背景画像は変更しない方針のため画像側を調整できず、他5画面（汎用アート＋コード描画UIで端に固定コンテンツが無い）だけに適用。GodotネイティブのNinePatchRect（`_frame_overlay`、`FRAME_PATCH_MARGIN`=53px、`content`直下の最後の子＝最前面）で角の意匠を保ったまま辺だけ伸縮する。**縮小率の選定が重要**: 原寸(margin=190px)のままだと960x560ダイアログでは枠が太すぎてヘッダー(タイトル/閉じるボタン)や角のカードを覆い隠す。28%縮小(margin=53px)がちょうどよいバランスだった。**中身は枠の内側に収める**: `_content_margin`(MarginContainer、`column`を包む)に`FRAME_PATCH_MARGIN+FRAME_CONTENT_GAP`(=59px)の余白を設定し、ヘッダー/カード/詳細パネルを枠の窓の内側に収める。ただし単純に余白を足すとカードグリッドの実質幅が減って4列(`GRID_COLUMNS`)が収まらなくなるため、`set_frame_overlay()`はダイアログの`min_size`自体も同じ分だけ拡大する（960x560→1078x678相当）——中身の使える面積は額縁なし時と同じに保ったまま、外側の額縁ぶんだけダイアログが一回り大きくなる設計。背景アート(`_background_rect`)は額縁の下に潜り込む形でダイアログ全体を覆ったまま（額縁が写真の縁を隠すのと同じ発想）
  - **炎アニメの合成レシピ（書庫のロウソク2026-07-16、洞窟のランタン2026-07-16、確立済みの手順）**: ユーザーから届く炎の参照シート（8列×2行グリッド、コマごとに数字ラベル付き、黒背景）は次の手順で対象画面に組み込む。①シートの各セルを連結成分ラベリングで切り出し（黒背景をボーダーからflood-fillで透明化→最大の連結成分だけ残してトリム。これで離れた場所の数字ラベルや火の粉の点が誤って本体扱いされるのを防げる）②既存の絵（ロウソクの土台、ランタンの金属枠など「燃えない部分」）は**一切上書きしない**。元の背景画像はそのまま残し、切り出した炎だけを**アルファブレンドで直接重ねる**（塗りつぶし色で一度消してから貼るやり方は、周辺と微妙に色が合わない・継ぎ目が固定境界になるなど問題が出やすく2026-07-16に廃止）③炎スプライトの下端は`FadeBottom()`でアルファを0まで滑らかにフェードさせ、**フェードが完全に0になる位置を「燃えない部分」の境界より上（またはちょうど同じ）に収める**——境界をわずかでも炎側が越えると、フレームごとに炎の形が違う分だけ土台側がちらついて見える（書庫のロウソクで発生した実際のバグ、2026-07-16）。適用後は必ず境界より下のピクセルが全フレームでバイト単位一致することをスクリプトで検証してから確定する。④PowerShellで`New-Object Type($a,$b)`のような「関数呼び出し風」構文や`$a/$b`からの`[int]`キャストは罠（前者は構文エラー、後者は切り捨てでなく四捨五入されるため整数除算のつもりが1ズレる）。座標計算やビットマップ処理はC#を`Add-Type -TypeDefinition`でコンパイルして呼ぶ方が確実
  - **洞窟背景`dig_background.png`のランタン（2026-07-16実装）**: `main.gd`の`_draw_backdrop()`がこの1枚をタイル状に横スクロール表示するため、画面内には同じ絵の中の**複数のランタン**（手前の大きいもの1つ＋奥の小さいもの3つ）が同時に見える。全部に同じ炎合成レシピを適用しないと一部だけ静止して不自然になる。ランタン位置はシートと同じ「明るい暖色の連結成分」検出（`LanternTool.FindBrightClusters`、しきい値はロウソクより高め`R>=235,G>=170`にして炎本体だけを拾い、金属枠の照り返しを除外）で自動検出できる
  - **`enable_art_chrome()`の閉じるボタンが最初から見えないバグ（2026-07-15に発見・修正）**: `add_header_close_button()`はボタンを`visible=false`で作るだけで、`enable_art_chrome()`はそれを呼ぶだけで表示に切り替えていなかった。ショップだけはページごとに`set_header_close_visible()`を明示的に呼んでいたため気づかれず、書庫/宝物/祭壇/ギルド/宿舎の5画面は導入当初から閉じるボタンが常に非表示だった。`enable_art_chrome()`の最後で`set_header_close_visible(true)`を呼ぶよう修正。回帰防止に`tests/core/test_card_dialog_chrome.gd`を追加（`UDCardDialog`はNode/Windowでも`--headless`でインスタンス化してプロパティ検証できることを確認済み）。**同種の「デフォルトで隠れたまま」系バグを疑ったら、まずこのテストパターンで検証できないか考える**
  - **ショップの「閉じる」二重表示（2026-07-15に修正）**: 旧実装は`enable_art_chrome()`と同じ`add_header_close_button()`をヘッダー行に置いていたが、ヘッダー行はショップの背景に焼き込まれた「閉じる」看板（`SHOP_CLOSE_HOTSPOT`）とほぼ同じ画面位置に重なり、詳細パネルの陰から看板の端が薄く覗いて二重に見えていた。`UDCardDialog.add_solid_hotspot(rect_norm, label, on_pressed)`（`add_hotspot`と同じテクスチャ正規化配置だが、透明ではなく実際に塗られたボタンを描く）を新設し、ショップの各アイテム一覧ページではヘッダー行の閉じるボタンをやめて`SHOP_CLOSE_HOTSPOT`にこれを重ねる方式に変更。看板の矩形をそのまま覆うので隙間なく一枚のボタンに見える
- **アニメ**: `<key>_f2.png, _f3.png...` を置くと自動でフレーム再生（基本ファイル=1フレーム目、0.4秒/コマ、IDLE中は1フレーム目固定）。アニメはUI側のみでシミュレーションに影響しない
- **地形の空間バリエーション（2026-07-14〜）**: `<key>_v2.png, _v3.png...`（`_fN`とは別物、時間経過で切り替わらない）を置くと、`UDArtLibrary.variant_texture(key, seed)`でセル座標由来のseedから決定的に1枚選ばれる（`main.gd`の`_draw_grid()`が`hash(cell)`をseedに使用）。実例: `terrain_rock.png`＋`terrain_rock_v2..v25.png`（岩片イラストシートを5×5グリッドとして切り出したもの、ユーザーからの合成シートは固定グリッドか浮遊した不規則形状かをまず確認すること——今回は「全25セルに柄が入っている」ことをセルごとの非背景色ピクセル数で検証してから確定した）。未配置なら`texture(key)`にフォールバック（1枚だけの従来動作）
- **キャラの向き**: スプライトは全フレーム同じ向きに統一し（tools/extract_sprites.gd の FLIP_X_OUTPUTS で調整）、main.gd の MINION_NATIVE_FACING に素材の向きを登録。逆方向は描画時に自動反転。掘削の破片は _draw_debris が対象地形の色で生成するので、素材に土煙を焼き込まないこと
- **掘削アニメ（2026-07-13更新）**: minion_0 は5コマ（idle + 振り上げ + 頂点 + 打ち込み開始 + ピーク/砂煙）。ユーザーがPixeloramaで直接描いた手描き素材に差し替え済み（旧AI生成シート版は破棄）
  - **ハマった罠1（向き不一致）**: 複数コマの素材を追加するときは全フレーム同じ向きに統一し、`FLIP_X_OUTPUTS`にも過不足なく列挙すること。逆だと掘削中だけ体が反転して見える致命的なバグになる
  - **ハマった罠2（アニメ開始位置）**: `_anim_frame`はグローバルな経過時間カウンタなので、そのままdig中のフレームインデックスに使うと**掘り始めた瞬間のアニメ位置がランダムになり、いきなり打撃コマから始まる**ことがある。main.gdの`_dig_anim_start`（IDLE/MOVING→DIGGING遷移をtickごとに検知して`_anim_frame`を記録）で、スイングは必ず振り上げ(frame 1)から始まるようにしている
  - **ハマった罠3（背景の不透明化・スケール不一致）**: Pixeloramaで書き出したPNGは、①レイヤーの背景が黒で塗りつぶされたまま不透明で保存される場合があり、Godotの`get_pixel().a`で確認しないと見た目だけでは気づきにくい ②手描きだとコマごとにキャラの大きさが微妙にズレやすく、ループ再生すると「膨張と収縮」に見える。**新規に複数コマの素材を受け取ったら、必ずコマごとに背景を透明化（角ピクセル基準でフラッドフィル、tools/extract_sprites.gd と同じ許容誤差0.06〜0.075）→トリムしてコンテンツの高さを測る→全コマが同じ高さになるよう拡大縮小してから128×128に配置し直すこと**（1コマだけ極端に小さい/大きいと一発でわかる）
- **新しい参照シート（10×4グリッド等、番号バッジ付き）を追加する場合**: extract_sprites.gd に "grid"+"cell_crops" 形式のプリセットを足せば、セル番号→出力名の指定だけで自動クロップできる（ERASE_TOP_LEFTでバッジを消去）。ただしAI生成シートは列幅が均一グリッド計算どおりにならないことがあるので、生成後は必ず全コマを目視確認し、隣接ポーズがにじんだフレームは別インデックスに差し替えること（実例: miner_sheet_v2.png の idx20・idx27はどう幅を絞ってもにじんだため採用を見送った）
- locale CSV は `key,text` 形式（FileAccess.get_csv_line でパース、カンマを含む本文は引用符で囲む）

## 実装済みの主要システム（2026-07-12〜13セッションで追加）

- **侵入者イベントは実装後に削除された**（ユーザー判断、2026-07-12夕）。復活させないこと
- **アイテムランク＋スタック所持（セーブv5）**: 宝物は rank（Z>S>A>B>C>D、items JSONの`rank`フィールド）と所持数を持つ。上限 UD.ITEM_RANK_CAPS（Z10/S50/A100/B200/C・D500）。`sim.items` は id→count 辞書（v4配列から自動移行）。ランク表は `UDItemDB.ranks_by_id()` で sim に注入
- **施設は地図配置を廃止、ボタン一つで解禁（2026-07-13、ユーザー判断）**: 「掘って戻ってこられる場所を探す」手間自体が不要と判断され、祭壇/ギルド/宿舎は`data/facilities/`のショップ型定義になった。未解禁ならボタン押下で`sim.buy_upgrade(def)`（コストはコイン、max_level=1）→そのままダイアログが開く。解禁済みならダイアログを直接開く（`main.gd`の`_on_facility_button`）。旧セーブ（v5以前の`rooms`配列）は`from_dict`内でupgradesへ自動移行、`sim.rooms`自体が撤廃されているので`build_room`/`room_footprint`/ダンジョン画面上の部屋タイル描画も全て削除済み
- **祭壇のお供え**: `sim.offer_at_altar(item_id)`。コイン費用は UD.ALTAR_OFFER_BASE_COST×1.4^Lv、+1掘削力/Lv、Lv5からは UD.ALTAR_ITEM_RANK_TIERS のランクの宝物1個も消費。`sim.altar_built()`は`upgrade_level("altar")>0`で判定。一切リセットされない永続効果
- **ギルド交換**: 酒場はギルドに改名（facility idは`tavern`のまま、locale名のみ変更）。`sim.guild_built()`は`upgrade_level("tavern")>0`で判定。`sim.exchange_item(target, consume)` で下位ランク消費→上位1個（レートは UD.ITEM_EXCHANGE_COSTS: Z←S×3/S←A×5/A←B×7/B←C×10、C・Dは宝箱限定）。**配信プラットフォームはitch.ioに決定（2026-07-12）。対人交換は将来のネットワーク連携で同じコマンドに載せる設計**（itch.ioにはSteamのようなインベントリ/実績APIが無いため、実装時は自前サーバーか外部サービスを想定）。UIの消費内訳は所持数の多い順に自動選択
- **宿舎**: 純フレーバー（ゲームプレイ効果なし）。解禁するとパーティ全員の顔ぶれをカードで見られるだけの画面（`_open_dorm`）。将来のドット絵UI差し替え先の一つ
- **チュートリアル**: settings.tutorial_seen ＋ 最初の UD.TUTORIAL_TICKS の間、帯/大画面にローテーションヒント（TUT_HINT_*）
- **文書の出土条件**: documents JSON の conditions（min_docs/requires_companions/requires_items）を `_roll_document` で判定
- **調査書カード機能は削除済み（2026-07-12、ユーザー判断）**: 公開前は見せる相手がいないため撤去。マーケティング施策で必要になったら `git log` から `src/daily/survey_card.gd` / `src/window/clipboard.gd` を復元すること
- **デイリー異変システムは削除済み（2026-07-15、ユーザー判断：不要と判断）**: `UDDaily`・`data/anomalies/`・`sim.daily_*`・HUDの「今日の異変」表示を全廃。復元する場合は `git log` から該当コミット以前を参照
- **手下の見た目バグ修正(2026-07-12)**: 仲間の描画アート/向きは`minion.id`（パーティ内の並び順）ではなく**companion_id由来のart_variant**（`UDMinion.art_variant_for_companion`、main.gdの`_minion_art_variant`）で決める。IDがずれると仲間が無名のプレースホルダー四角として表示される
- **ダイアログのイラスト化**: ショップ/宝物/書庫は`UDCardDialog`（羊皮紙カードグリッド＋右の詳細パネル、src/ui/card_dialog.gd）。祭壇・ギルドも同じウィジェットを使用。カードのアイコンは`UDArtLibrary.icon_or_placeholder(key, seed, shape)`が実アート（`item_<id>.png`/`shop_<id>.png`/`<doc_id>.png`）があればそれを使い、無ければ`placeholder_icon`で手続き生成（gem/rune/book形状、seedからHSVで色決定）。実アートを置くだけで自動的に差し替わる

## 未実装（設計図）

1. **配信プラットフォーム連携**（配信プラットフォームはitch.ioに決定、2026-07-12）: `src/platform/` に抽象化済み（`UDPlatform`）。itch.ioにはSteamworksのような実績/クラウドセーブAPIが無いため、実績（`UDAchievements`）は当面ローカル保存のみで運用。将来ネットワーク機能（ギルドの対人交換など）が必要になったら自前サーバーか外部サービスの検討が必要
2. **手記書き直し**: ストーリーバイブル（docs/STORY_BIBLE_v2_foreshadowing.md＋docs/STORY_BIBLE_v5.md、仲間のストーリー設定はまだ未確定）確定後。既存13編は仮。v5で【確定】したタイトル副題「〜忘却の底で〜」・世界名アビュソス・行商人アナスタスの正体とセリフ変化・序章のソストラトス初出エピソードは実装OK、それ以外（仲間ストーリー、F17意匠、エンディング分岐、MVP文書圧縮）はまだ手を付けない
3. **地形/部屋の本番アート**: 現在は生成ドット絵。assets/art/ に規約名PNGを置くだけで差し替わる
4. ~~部屋の隣接ボーナス~~: 2026-07-13に施設の地図配置自体を廃止したため対象消滅（design.md §5.2も更新済み）

## パフォーマンス予算（§7.1、超えたら実装を差し戻す）

アイドルCPU 1%未満（実測0.2〜0.3%）・メモリ200MB目標。毎フレーム処理を追加しない。
描画は tick 毎の queue_redraw のみ。非フォーカス時 fps10、最小化時は描画停止。
