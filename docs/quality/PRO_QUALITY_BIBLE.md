# Makers & Challengers — Professional Quality System v1.0

Steamで販売する商用インディーゲームとして、プレイヤーが「個人制作だから仕方ない」と感じない完成度にするための基準。
**目的はルールに従わせることではなく、プレイヤーが感じる完成度を上げること。**

- 品質の知識の正本（Single Source of Truth）は `docs/quality/` の文書。Claude Code 用・Codex 用の Agent Skills（§8）は「どの文書のどの章を読むか」を案内するだけで、規約の本体を持たない。
- この文書は入口と共通ルールだけを持つ。作業内容に応じて、下の表の該当ファイル・該当章だけを読む（全文を毎回読まない）。

| 作業 | 先に読むもの | Skill |
|---|---|---|
| 新規ボス・新規攻撃・覚醒・味方の技・戦闘演出の修正 | [COMBAT_PRESENTATION.md](COMBAT_PRESENTATION.md) 全体、[ANIMATION_CRAFT.md](ANIMATION_CRAFT.md) の該当章、[ART_DIRECTION.md](ART_DIRECTION.md) §3・§6・§8、[PERFORMANCE.md](PERFORMANCE.md) §1〜§3 | mc-combat-presentation |
| キャラ・ボスの動き（ポーズ・待機・移動） | [ANIMATION_CRAFT.md](ANIMATION_CRAFT.md)、[COMBAT_PRESENTATION.md](COMBAT_PRESENTATION.md) §3 | mc-combat-presentation |
| VFX・Particle相当の描画・Shader | [COMBAT_PRESENTATION.md](COMBAT_PRESENTATION.md) §5〜§7、[ART_DIRECTION.md](ART_DIRECTION.md) §6、[PERFORMANCE.md](PERFORMANCE.md) §2 | mc-combat-presentation |
| Camera・揺れ・Hit Stop・Flash | [COMBAT_PRESENTATION.md](COMBAT_PRESENTATION.md) §4、[ACCESSIBILITY.md](ACCESSIBILITY.md) §4・§5 | mc-combat-presentation |
| 見た目の方向性・背景・ドット絵素材・ボスのテーマ | [ART_DIRECTION.md](ART_DIRECTION.md)、[COMBAT_PRESENTATION.md](COMBAT_PRESENTATION.md) §6 | mc-art-direction |
| UI・画面・画面遷移・文言・Loading | [UI_UX.md](UI_UX.md)、[ACCESSIBILITY.md](ACCESSIBILITY.md) | mc-ui-accessibility |
| 表示モード・拡大方式（全画面・integer） | [UI_UX.md](UI_UX.md) §10.1、[ACCESSIBILITY.md](ACCESSIBILITY.md) §1 | mc-ui-accessibility |
| タイトル画面・ボスの部屋（Codex担当） | [UI_UX.md](UI_UX.md) §7、[ANIMATION_CRAFT.md](ANIMATION_CRAFT.md) §13・§14、[ART_DIRECTION.md](ART_DIRECTION.md)、[PERFORMANCE.md](PERFORMANCE.md) §1 | mc-art-direction／mc-visual-review |
| SE・BGM | [AUDIO.md](AUDIO.md) | mc-audio |
| 性能の計測・改善 | [PERFORMANCE.md](PERFORMANCE.md)、本書 §5.1 | mc-godot-performance |
| 動画・一覧画像・スクリーンショットのレビュー | 本書 §3、[REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md)、[ANIMATION_CRAFT.md](ANIMATION_CRAFT.md)、[ART_DIRECTION.md](ART_DIRECTION.md)、[examples/README.md](examples/README.md) | mc-visual-review |
| どの作業でも、終わる前 | [REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md) の該当リスト | — |
| 何を直すかを決める | [QUALITY_AUDIT.md](QUALITY_AUDIT.md)、[QUALITY_AUDIT_STANDARD_DELTA.md](QUALITY_AUDIT_STANDARD_DELTA.md) | — |
| 外部資料の根拠を確かめる | [EXTERNAL_REFERENCES.md](EXTERNAL_REFERENCES.md) | — |
| Skill が本当に効いているか確かめる | [QUALITY_EVALS.md](QUALITY_EVALS.md) | — |

---

## 1. 判断基準（最重要）

「この規約に違反しているから直す」ではなく、**「直すことでプレイヤーが感じる完成度が本当に上がるか」**で判断する。

- すでに良いものを壊さない。過剰に直さない。一括リファクタリングしない。
- ゲーム仕様（ダメージ計算・行動ルール・覚醒条件・Clear Check・オンライン・ランキング・Supabase・Steamworks・保存データ・Creatorデータ形式）を、見た目の改善のために変えない。
- 既存の承認済み演出（ユーザーが動画で確認して承認したもの）を、この規約の数値に合わせるためだけに作り直さない。数値は**新規制作と、明確な問題がある既存箇所の改修**の目安。
- コードの見た目の美しさだけを理由に既存コードを変えない。

### 1.1 Release Gate と Polish Priority
以前の「見た目→操作感→…→安定性→コード内部品質」という1本の優先順は廃止した。「見た目の方が性能や安定性より大事」と読めてしまうため。

**Release Gate（発売品質として必ず満たす条件）**

| 条件 | 確かめ方 |
|---|---|
| Crash がない | 実際の操作・全GUT |
| Softlock（進行不能）がない | 実際の操作 |
| 入力が効かなくなる状態がない | 実際の操作 |
| 重大な表示欠けがない（大事な情報が欠ける・隠れる・崩れる） | 実画面（日本語・英語、1280×720以外のウィンドウ） |
| 保存データ・Creatorデータを壊さない | 保存→読み込みのテスト |
| ゲームロジックの退行がない | 全GUT、演出の前後で戦闘の snapshot が変わらない（`simulation_unchanged`） |
| 許容できない frame-time spike がない | [PERFORMANCE.md](PERFORMANCE.md) §1 の予算。満たせない時は実測と理由を示してユーザーの承認を得る |
| 読めないUIがない | [ACCESSIBILITY.md](ACCESSIBILITY.md) §1・§2 |
| 重大な Accessibility 問題がない | [ACCESSIBILITY.md](ACCESSIBILITY.md) §7（光過敏の失敗条件・色だけで伝える必須情報） |

- Release Gate を満たさないものは、**見た目が良くても完成扱いにしない。**
- Release Gate に反する問題は P0 か P1 として扱う（§2）。
- 処理落ちは「見た目」と「操作感」を直接壊すので、演出の品質改善で処理落ちを増やすことは認めない（[PERFORMANCE.md](PERFORMANCE.md)）。

**Polish Priority（Release Gate を満たしたものを磨く）**
- Art Direction／Animation／Combat Feel／VFX／UI/UX／Audio／Presentation。
- この中に固定の順位は付けない。§1 の判断基準（プレイヤーが感じる差）、修正のリスク、そのものを見る頻度（毎ターン見るものほど効く）で、何から直すかを決める。

### 1.2 既存実装を直してよい条件
次のどれかに当てはまる時だけ直す。
- プレイヤーから見える品質が上がる
- 操作感が上がる
- 安定性が上がる
- パフォーマンスが上がる
- 今後の制作を著しく妨げる構造問題がある

### 1.3 数値の扱い
- 規約に出てくる数値（演出の秒数、Hit Stop の秒数、揺れの px、UIの遷移の秒数、Particle の数、ドローコール、VFXの層の数など）は「絶対的なプロ品質の正解」ではない。**現在のゲーム・実測・採用済みの演出・1280×720を基準にした目安**。
- 数値より、**意図と最終結果**（実際の映像）を優先する。数値に合わせるためだけに直さない。
- 例外として、測定値そのものが大事なものは測って判断する: [PERFORMANCE.md](PERFORMANCE.md) §1 の予算、[ACCESSIBILITY.md](ACCESSIBILITY.md) の基準（光過敏の失敗条件、文字の大きさ、コントラスト）。

---

## 2. 問題の優先度

| 区分 | 内容 | 対応 |
|---|---|---|
| **P0** | crash／softlock／入力が効かない／深刻な処理落ち／表示崩れ／進行不能 | 即修正 |
| **P1** | プレイヤーから見て明確に品質が低い（不自然な動き・キャラの歪み・カクつき・タイミングの違和感・弱いimpact・UIとVFXの干渉・不自然なカメラ・音ズレ・明らかに安っぽい演出、表示の欠け・未翻訳） | 優先して修正 |
| **P2** | 直すと商用品質が大きく上がるが、今でもゲームは成立している | 時間とリスクを見て修正 |
| **P3** | 規約と違うが、プレイヤー視点では十分成立している | 原則変更しない |

デザイン（見た目の方向性・承認済み演出の構成）に関わるものは、優先度に関係なく**ユーザーの採用判断の後**に着手する。
Release Gate（§1.1）に反するものは、P0 か P1 のどちらかにする（P2・P3 にしない）。

---

## 3. Professional Quality Review（主要演出すべてに対して問う）

| | 質問 |
|---|---|
| A | 正常に動作するか |
| B | 見ていて気持ちいいか |
| C | 動きに重量・慣性・意図があるか |
| D | 演出の開始・ピーク・終了が分かるか |
| E | プレイヤーがどこを見るべきか明確か |
| F | エフェクトを減らしても成立する動きか |
| **G** | **Steamの商品ページの動画に映して問題ない品質か（最重要）** |

G は「1280×720の実画面を、実時間（処理落ち込み）で見て」判断する。録画モード（Movie Maker）の映像だけで判断しない（§5）。

戦闘演出・タイトル・大きな画面の変更では、次も問う（毎回すべての作業で問う必要はない）。

| | 質問 | 詳しくは |
|---|---|---|
| H | 1コマ止めても、ポーズと構図が成り立っているか | ANIMATION_CRAFT §2、COMBAT_PRESENTATION §5.4 |
| I | 一番見てほしい場所が明確か | ART_DIRECTION §8、COMBAT_PRESENTATION §5.5 |
| J | そのボス・キャラ固有の演出になっているか | ART_DIRECTION §1・§3.1 |
| K | 豪華さを減らさずに Visual Clutter を減らせる余地はないか | COMBAT_PRESENTATION §5.7 |
| L | Animation・VFX・Audio・Camera が同じ Impact を支えているか | COMBAT_PRESENTATION §1、AUDIO §6 |

- B・C・G・H・J のような「見て気持ちいいか」「プロっぽいか」は、AIの自己評価だけで合格にしない。実際の映像・一覧画像・Before／After をユーザーが見て決める。

---

## 4. このプロジェクトの前提（変えない土台）

- 起動ルート `src/bossmaker/rbm_game_root.tscn`。内部識別子 `bossmaker`/`RBM` は残す。Godot 4.7、`gl_compatibility`。
- 論理解像度 1280×720、`window/stretch/mode="canvas_items"`（大きいウィンドウでは拡大、比率が違えば黒帯）。
- **表示・SEは確定済みの戦闘イベントを読むだけ。** 表示のために戦闘状態や戦闘乱数を進めない。演出は `impact`／`finished` の契約を守る。
- 演出の構造: `rbm_battle_stage.gd`（振り分け）→ 技ごとの専用スクリプト（固有の時間割）→ 共通部品（揺れ・Hit Stop・残像・衝撃波・破片・移動・SE・Flash・後始末）。**属性が同じでも演出を共有しない**（技・キャラ・ボスごとに固有）。
- 属性の色は `rbm_attribute_vfx_palette.gd`（無=灰 #b7bbc2・炎 #ef4847・氷 #509cf5・雷 #f2cd55・風 #a4f255）。支援は強化=赤 #ef4847・回復=緑 #71da87（`rbm_boss_support_vfx.gd`）。
- タイトル画面とボスの部屋はCodexの担当。Claude Codeはデザイン・演出を変えない（技術的な修正は依頼があった時だけ）。
- 戦闘UI（BattleHUD）はz=20で戦場（z=1〜7）の上にある。演出をUIの上に出すのは「意図した全画面演出の瞬間だけ」（武者の着弾の前例、`rbm_fullscreen_battle_ui.gd` が stage に meta `battle_hud` を渡す）。
- ユーザーが決めた見た目の方向性・承認済みのテーマと、未決定の事項は [ART_DIRECTION.md](ART_DIRECTION.md) にまとめてある。そこにない方向性をAIが決めない。

---

## 5. 進め方（品質改善の作業手順）

1. **作業前**: `git status`／`git diff` で、他セッションの未コミット変更と自分の変更を区別する。reset／checkout／stash／clean は使わない。
2. 関連する規約の章と [QUALITY_AUDIT.md](QUALITY_AUDIT.md) の該当項目を読む（Skill を使う場合は、Skill が示す章だけ）。
3. **1つの問題だけ**を直す。一度に大量のファイルを書き換えない。
4. 確認を3つ行ってから次へ進む。
   - **Test**: テストの実行範囲の決まりはここが正本（他の文書・Skill はここを参照する）。
     - 通常の作業の繰り返しでは、**変更範囲に関係するGUT**を優先して実行する。全GUTを毎回機械的には実行しない。
     - **全GUT**は必要な時に実行する: 影響範囲が広い変更（共通部品・戦闘ロジック・保存と読み込み・多くの画面にまたがる変更など）、まとまった作業の最終的な回帰確認（Release Gate の確認・commit の前など）。
     - 見た目・演出・音の作業では、GUTの件数より **Runtime（実GPU・実時間）と Video の確認**を重視する。GUTの合格だけで見た目の品質を判断しない。
     - 報告では、実行したテストと、全GUTを実行した／しなかった理由を書く。
     - テストを削ってPASSさせない。前提が古くなったテストは「なぜ無効になったか」を確かめてから直す。
   - **Runtime**: 実GPUで実際の画面を動かす。演出は**実時間のフレーム時間**も測る（[PERFORMANCE.md](PERFORMANCE.md) §3）。
   - **Video**: 動き・タイミング・impact・camera・loop・変形・読みやすさは、実際の映像（またはコマ送りの一覧画像）で最終判断する。コードだけで完成と判断しない。承認・却下の比較は [examples/README.md](examples/README.md) の運用で残す。
5. 意味のある単位でcommitする（commitはユーザーの依頼がある時だけ）。大量の変更を1commitにまとめない。
6. 報告は日本語。何を確認し、何を確認していないかを分けて書く。

### 5.1 検証で分かっている落とし穴（必読）
- **録画モードは処理落ちを隠す。** `--write-movie` や `--fixed-fps` の映像は毎コマ完全に描かれるので、実時間で20fpsに落ちる演出も滑らかに見える。見た目の確認には使ってよいが、性能の判断には必ず実時間の計測を使う。
- **検証ツールが自分で処理を止める。** 再生中の画面の読み出し（`get_image()`）やPNG保存は、1回で数十〜260msフレームを止める。色の判定を「固定の1時点」だけで行うと、この停止で判定の瞬間がずれて誤判定する（スライム・騎士の検証で実際に起きた）。判定は短い時間帯の複数フレームで行い、PNG保存は再生後にまとめる。
- **大きいウィンドウでは画面テクスチャを読むシェーダーの座標がずれる。** `canvas_items` の拡大を考慮しないと、下・右が引き延ばされる（宇宙飛行士の重力演出で実際に起きた）。1280×720以外（1920×1080・1600×900・4:3寄り・縮小）でも確認する。
- 実GPUの確認は `tools/gpu_runner.tscn -- --tool=...`（`run_gpu_verification()` と `_gpu_verification_completed` を持つツール）、または `verify_battle_visuals_gpu.gd` を継承したツールを `-s` で起動する（ゴーレム全体・支援、狼など）。

---

## 6. AIで作業する時のルール（Codex / Claude Code）

次の作業を始める時は、必ず冒頭の表から該当する章を開いてから作業する（全文は不要）。対応する Skill（§8）があれば使う。
- 新規ボス・新規攻撃・覚醒・VFX・Animation・UI・Title Screen・Camera・SE・キャラクターの移動・背景演出・戦闘演出

作業の最後に [REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md) の該当リストを埋めて報告に含める。

してはいけないこと:
- 規約と違うという理由だけで、既存の承認済み演出・画面を作り直す
- 「HPと同じだから」のように、関係ない数値・仕様を連動させて変える
- ユーザーが採用を決めていないデザイン案を実装する
- Codex担当のタイトル画面・ボスの部屋の見た目を変える
- テストを削る・弱めることでPASSさせる
- 「プロっぽくする」という理由だけで Particle を増やす
- 「迫力を出す」という理由だけで画面揺れを強くする
- 全攻撃へ Hit Stop を入れる
- 全画面の Flash を多用する
- すべての Animation に同じ ease を使う
- Secondary Motion を全部の部位へ入れる
- ドット絵という理由だけで、高解像度のエフェクトを全面禁止する
- Accessibility 対応という理由だけで、既存のデザインを勝手に変える
- 見た目を削っただけで fps を上げ、それを改善と呼ぶ（[PERFORMANCE.md](PERFORMANCE.md) §1.2）
- 外部のゲームの演出をそのままコピーする。参考作品の固有のデザインを複製する
- Skill や規約を読んだだけで「プロ品質」と自己認定する（最終判断は実際の映像とユーザー）

---

## 7. 用語

| 用語 | 意味 |
|---|---|
| 演出（presentation） | 技・覚醒などの再生。`rbm_*_presentation.gd`／`rbm_*_finish.gd` 等 |
| impact | 命中が確定し、ダメージ表示・被弾反応を始める瞬間（`stage.impact` シグナル） |
| Hit Stop | 命中の瞬間に動きを短く止めて重さを出す手法 |
| 一覧画像 | 演出を一定間隔で切り出して並べた確認用画像（コマ送りの代わり） |
| 参照機 | 性能を判断する基準のPC（現在の開発機: Intel UHD Graphics・gl_compatibility） |
| Release Gate | 発売品質として必ず満たす条件（§1.1）。満たさないものは完成扱いにしない |
| Polish | Release Gate を満たしたものを、見た目・動き・音などで磨くこと |
| Key pose | 動きの要になるポーズ。止めても何をしているか分かる（ANIMATION_CRAFT §2） |
| Spacing | 途中のコマで位置がどれだけ動いたかの間隔（ANIMATION_CRAFT §4） |
| Primary Shape | その技を代表する形（COMBAT_PRESENTATION §5.4） |
| Value hierarchy | 明暗の強さで作る、見る順番（COMBAT_PRESENTATION §5.5） |
| Visual clutter | 目的のない見た目の雑音 |

---

## 8. Agent Skills（Claude Code／Codex）

| Skill | 使う時 |
|---|---|
| mc-combat-presentation | 戦闘演出（ボスの技・覚醒・味方の技・VFX・揺れ・Hit Stop・Flash・キャラの動き）を作る・直す |
| mc-art-direction | 見た目の方向性・背景・ドット絵素材・ボスのテーマ・タイトルの部屋の見た目を扱う |
| mc-ui-accessibility | 画面・UI・遷移・文言・文字の大きさ・コントラスト・表示モードを扱う |
| mc-godot-performance | 処理落ち・停止の計測と改善 |
| mc-audio | SE・BGM・ミックス |
| mc-visual-review | 動画・一覧画像・スクリーンショットをレビューする |

- 置き場所: Claude Code は `.claude/skills/<name>/SKILL.md`、Codex は `.agents/skills/<name>/SKILL.md`（`[S2]` `[S3]`）。
- **2か所の SKILL.md は同じ内容（バイト単位で一致）にする。** 片方だけ直さない。直したら `diff -r .claude/skills .agents/skills` で差がないことを確かめる。
- Skill には規約の本文を書き足さない。規約を変える時は `docs/quality/` を直し、Skill は「どこを読むか」だけを持つ。
- name は英小文字・数字・ハイフン（64字まで、フォルダ名と同じ）、description は1024字まで。description には「何をするか」と「いつ使うか・使わないか」を、主な用途から先に書く（`[S1]`〜`[S4]`）。
- Skill を増やしすぎない。新しい Skill は、6つで扱えない作業が繰り返し出てきた時だけ作る。
- Skill が本当に出力を良くしているかは [QUALITY_EVALS.md](QUALITY_EVALS.md) で確かめる。Skill を作っただけで品質が上がったと判断しない。

---

## 改訂履歴
- 2026-10-08 追記（同日3回目）: QA-06 の第3段。PERFORMANCE §2.1 に「間に合わない時は、演出の開始の境界で、その演出の素材が揃うまで待つ（固定の時間ではなく実際に読み終えるまで。待つ間に HP の表示・次の行動を進めない。今の PC で間に合っても外さない）」を追加。§2 の `get_image()` の例外から、武者オーラの直接の読み出し（写しが無い時の代わり）を削除した記録に更新。VRAM の基準値は QA-06 の値として承認（将来の絶対の予算ではない）。COMBAT_PRESENTATION §9・REVIEW_CHECKLIST C に同じ規則への参照を追加。
- 2026-10-08 追記（同日2回目）: QA-06 を再オープン。完了の条件を「通常の操作で到達できる最速の経路を含め、初回の演出の最中に同期の読み込み・初めてのデコード・初めての解析・同期の GPU 読み出しを起こさない」とした（QUALITY_AUDIT_STANDARD_DELTA の QA-06 の記録）。
- 2026-10-08 追記: PERFORMANCE §2.1（演出の素材は再生中に初めて読み込まない。開始フレームで同期の読み込み・初めてのデコード・初めての解析を起こさない、停止を別の瞬間へ移さない、VRAM の管理、GPU 側の初回の準備は計測してから）を追加（QA-06 の完了に合わせて）。COMBAT_PRESENTATION §9・REVIEW_CHECKLIST C・AUDIO §5 は PERFORMANCE §2.1 を参照する形に変更（「戦闘開始時に読み込む」の書き方を、停止を移さない書き方にそろえた）。同日、VRAM の基準値を「絶対の上限ではなく判断の基準」と明記し、`get_image()` の例外を武者オーラの用途と条件に限定し、§2.1 に「現在の実装との差」（事前読み込みより前に始まる演出・戦闘後も保持・オーラの直接読み出し）を追記。
- 2026-10-07 追記: §5 の Test にテストの実行範囲の方針（関連GUTを優先・全GUTは影響が広い時と最終的な回帰確認で実行・見た目の作業は Runtime と Video を重視）を正本として記載。PERFORMANCE §5・REVIEW_CHECKLIST A・mc-combat-presentation はここを参照する形に変更。
- v1.0（2026-10-07）: 単一の優先順を Release Gate と Polish Priority に分けた。数値の扱い（§1.3）、Review H〜L、AIの禁止事項、Agent Skills（§8）を追加。ANIMATION_CRAFT／ART_DIRECTION／ACCESSIBILITY／EXTERNAL_REFERENCES／QUALITY_EVALS／QUALITY_AUDIT_STANDARD_DELTA／examples を追加。
