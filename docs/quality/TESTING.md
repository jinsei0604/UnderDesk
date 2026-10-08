# テストの選び方（Test Selection）

**テストの実行範囲の決まりは、この文書が唯一の正本。** [PRO_QUALITY_BIBLE.md](PRO_QUALITY_BIBLE.md) §5・[REVIEW_CHECKLIST.md](REVIEW_CHECKLIST.md)・[PERFORMANCE.md](PERFORMANCE.md) §5・[QUALITY_EVALS.md](QUALITY_EVALS.md)・Agent Skills・`CLAUDE.md` は、ここを参照する（同じ決まりを書き写さない）。

---

## 1. 目的と原則
- 目的は、変更で壊れる可能性がある範囲を、**必要十分な**テストで確かめること。関係のないテストの繰り返し・不要な全GUTに使っていた時間を、実機の確認・動画・Visual Review・実GPU・変更箇所の深いテストに回す。
- **テストを減らすこと自体を良いとしない。** 評価するのは「必要なリスクを覆えたか」。1ファイルの変更でも全GUTが要ることがあり、10ファイルの変更でも関連テストで足りることがある。
- 範囲は「変更したファイルの数」ではなく、**「変更で壊れる可能性がある範囲」**で決める。1ファイルでも全戦闘が通る共有の部分なら範囲は広い。10ファイルでも1体のボスの専用の演出・素材・テストだけなら範囲は狭い。
- 見た目・音の作業は、GUTが全部通っても完了にしない（§6）。**全GUTを省いた分、実機・映像の確認を省かない。**
- テストを削る・弱める、テストのために本番を変えてPASSさせることはしない（PRO_QUALITY_BIBLE §6）。**失敗を未解決のまま「合格」として扱わない**（§4）。
- この文書の件数・所要時間は参考値。テストの合否や、実行の要否の判定には使わない（合否は、そのときの実行結果で決める）。

---

## 2. 手順

```
変更を確かめる（自分の変更と、ほかの作業者の変更を分ける）
↓
影響範囲を特定する（呼び出し元・依存先・共有している状態）
↓
テストのレベルを決め、§5 の対応表から最低限のテストを選び、変更に合わせて足す
↓
実行して結果を確かめる
↓
想定外の結果は §4 の順に調べ、必要なら範囲を広げる
↓
§7 の形で報告する
```

1. **変更を確かめる。** 必要に応じて次を見る。`git diff` だけでは、stage 済みの変更と新しい未追跡のファイルを見落とす。
   - `git status --short`（変更・stage・未追跡（`??`）の一覧）
   - `git diff`（未 stage の変更）
   - `git diff --cached`（stage 済みの変更）
   - 未追跡の新しいファイル（`git status --short` の `??`。中身も読む）
   - Claude Code と Codex の未コミットの変更が同じ作業ツリーに混ざっている。**ほかの作業者の変更を、自分の変更と混同しない。**
   - 誰の変更か区別できない変更は **「未確認の変更」** として扱う。誰の変更か分からなくても、今の作業ツリーの動きやテストの結果に影響しうるので、自分の変更と同じように呼び出し元・依存先を調べ、影響の可能性を確かめる。テストの失敗が未確認の変更によるものかもしれない時は、§4.1 で切り分ける。
   - 未確認の変更を、自分の変更として編集・stage しない。切り分けられない時は、その旨を報告する。
   - ほかの作業者の変更を reset・checkout・stash・clean しない。
2. **影響範囲を調べる。** 変えた関数・クラス・定数・シグナル・データの形ごとに、呼び出し元と依存先、共有している状態（static・cache・singleton・autoload・シグナル・シーンの生成と破棄）を `grep` などで確かめる。
   - ファイル名だけで決めない。例: 「`rbm_battle_stage.gd` を触ったから全GUT」も「1行だけだから関連テストだけ」もしない。変えた処理が実際にどこから使われるかで決める。
   - 安全な境界が分からない時は Level 4（§3 B）。「たぶんここだけ」で決めない。
3. **レベルを決めてテストを選ぶ**（§3・§5）。
4. **実行して確かめる。** 想定外の失敗は §4 の順に扱う。
5. **報告する**（§7）。

作業を始める時に、次を決めておく（軽い作業では報告に書かなくてよい）。

```
変更内容：
想定影響範囲：
テストのレベル：
予定しているテスト：
全GUTが必要／不要な理由：
```

---

## 3. テストのレベル

### Level 1 局所
- 対象: 1体のボス・1人の味方だけが使う演出（専用の presentation・VFX・素材）、専用のヘルパー、特定の UI 部品・SE、ほかから使われていない処理、1つのテストファイルだけの変更。
- 実行: 直接のテスト ＋ その機能を呼ぶ直近の契約テスト ＋ §6 で必要な実画面・実GPU・音の確認。全GUTは求めない。

### Level 2 関連範囲
- 対象: 複数の演出が使う部品、ボスの演出の共通処理の一部、ボスの一覧・ランキングの一部、Creator の中の共有処理の一部、戦闘UIの一部、共通の音の処理の限られた部分、複数のテストが使うテストの補助。
- 実行: Level 1 ＋ 呼び出し元・使う側のテスト ＋ 同じ部品を使う代表のケース ＋ 必要な統合テスト。
- 「同じフォルダだから全部」ではなく、依存関係から選ぶ。

### Level 3 サブシステムの回帰
- 対象: 戦闘演出の全体、Creator の全体、オンラインの一覧・ランキングの全体、音のサブシステム、ホーム・タイトル、など。
- 実行: そのサブシステムのテスト群（§5）を広めに。独立した別のサブシステムまでは実行しなくてよい。

### Level 4 全GUT
次のどれかに当たる時は、全GUTを実行する。
- **A. 広い共有の土台を変えた。** 例: 戦闘ロジック（`rbm_battle.gd` 等。行動順・乱数・ダメージ・覚醒の条件）、演出の進め方の契約（`rbm_battle_presenter.gd`、`rbm_battle_stage.gd` の `play_entry()`・`_start_dedicated()`・`cancel()`・`is_playing()`、`impact`／`finished` を出す時期）、`rbm_game_root.gd`、`rbm_definition_loader.gd`、共通の素材の読み込みの API・ready の判定の意味（§3.1）、入力の共有処理、保存と読み込み、画面の切り替え、全ボス・全味方が通る処理、多くのサブシステムが使う共通の API・autoload、GUT そのもの（`addons/gut/`）とその起動のしかた。`CLAUDE.md` が変えないと決めている仕様（戦闘性能・乱数・行動順・SIMPLE/HARDCORE・action_sequence・保存／復元）に触れた時もここ。
- **B. 影響範囲を十分に特定できない。** コードを調べても安全な境界が分からない時。
- **C. 想定外の失敗を調べた結果、安全な境界が分からない、または影響が広いと分かった時**（§4 の手順の6）。想定外の失敗が1つ出たことだけでは、ここに当たらない。
- **D. 大きな節目。** 大きな機能の完了、複数の QA 修正の統合、マージ、リリース候補、Steam への提出の前、大規模なリファクタの後。**commit の前というだけでは当たらない。**
- **E. 個別の規約が全GUTを求める変更。**

**「念のため全GUT」はしない。** 全GUTを実行した時は、A〜E のどれに当たったかを具体的に書く（B なら、何が分からなかったか）。

### 3.1 レベルの境界の例: 素材の事前読み込み
ファイル名や「非同期」という言葉だけでレベルを決めず、実際の変更の影響範囲で決める。
- **Level 3**: 事前読み込みの優先順位・内部の cache・保持・解放など、**今の ready の判定（その演出の素材が揃ったと判断する条件）と、戦闘の進め方の契約を変えない内部の最適化**。変更がその中で閉じていることを、呼び出し元と共有の状態を見て確かめたうえで（例: `rbm_presentation_warmup.gd` の読む順だけを変える）。
- **Level 4（A）**: 共通の素材の読み込みの API（多くの画面が使う読み込み・cache の入口）、**ready の判定の意味**、演出を始める時期・行動の進め方、`impact`／`finished` の契約に影響する変更（例: `rbm_battle_stage.gd` の `_start_dedicated()` で、素材を待つ条件や待った後に始める時期を変える。`ensure()` が「揃った」と返す条件を変える）。
- どちらでも、最速の操作の経路・単独起動（§8）・実GPUの確認（§5 の該当の行）は省かない。

---

## 4. 想定外の失敗と、範囲を広げる時

### 4.1 想定外の失敗を見つけた時
1. 失敗を見つけたら、その場で止めて記録する（テスト名・メッセージ・その時の実行条件）。
2. 失敗の内容を調べる（メッセージ・スタック・該当のテストと本番のコード）。
3. 次のどれかに切り分ける。
   - **既知の不合格**: [PERFORMANCE.md](PERFORMANCE.md) §5 や [QUALITY_AUDIT.md](QUALITY_AUDIT.md) に記録があり、内容が記録と一致する。変更の前（HEAD など）でも同じに失敗することを確かめる。「既知らしい」では済ませない。
   - **変更による退行**: 自分の変更が原因。直す。
   - **実行環境の問題**: PC のスリープ、ほかのプロセスとの競合、GPU・ウィンドウの状態、テストの実行順への依存（§8）など。原因を取り除いて再実行し、同じ失敗が出ないことを確かめる。
4. 影響範囲を見直す（その失敗が、変更の影響が思ったより広いことを示していないか）。
5. 局所的な原因が確かめられたら、原因に関係するテストを足して確かめる（Level を必要なだけ上げる）。
6. 安全な境界が分からない時、または広い影響が分かった時は、全GUT（Level 4 C）。

- 想定外の失敗を「関係なさそうだから」と無視しない。未解決の失敗を残したまま「合格」として報告しない。解決できない時は、未解決として報告する。
- 「1つ落ちたから無条件に全GUT」もしない（上の 2〜5 を飛ばさない）。

### 4.2 範囲を広げる時
関連テストだけで始めても、次が起きたら範囲を広げる（必要に応じて Level 2 → 3 → 4）。広げたことと理由は報告に書く。
- 想定外のテストの失敗（§4.1 の手順で）
- 別の機能への影響を見つけた
- 共有のコードを変える必要が出た
- 作業の途中で、当初の範囲を超えた
- テストの実行順への依存を見つけた（§8）
- singleton・static・cache・autoload などの共有の状態に影響する
- シーンの生成と破棄（`_ready`・`_exit_tree`・付け替え・free）に影響する
- 素材の読み込み・非同期・スレッドに影響する

---

## 5. 対応表（変更の領域 → 最低限のテスト）
2026-10-09 時点で `tests/bossmaker/` と `tools/` に実在するファイル（テスト名は `.gd` を省く）。新しい領域のテストを足したら、この表にも足す。件数・時間は参考値（参照機の全GUT 95ファイル・1,693件・約10分の記録）。

| 変更の領域 | 最低限のテスト | 実画面・実GPU・音（§6） | 目安のレベル |
|---|---|---|---|
| 1体のボスの専用の演出（`rbm_<ボス>_*.gd`、`assets_bossmaker/battle/<ボス>/`） | そのボスのテスト（`test_astronaut_presentations`・`test_dragon_presentations`・`test_gentleman_presentations`・`test_ghost_presentations`・`test_golem_ground_slam`／`test_golem_single_punch`／`test_golem_support`・`test_knight_presentations`・`test_slime_presentations`・`test_wolf_presentations`、武者は `test_musha_presentations`・`test_musha_awakening`・`test_musha_aura`・`test_rbm_musha_ink_integration`・`test_musha_audio_levels`）。覚醒に触れたら `test_rbm_awakening_presentation`・`test_rbm_boss_awakening_support`。`warm_paths()` に触れたら `test_rbm_presentation_warmup` | 実画面か動画。そのボスの `tools/verify_<ボス>_gpu.gd`（武者は `verify_musha_gpu`・`verify_musha_awakening_gpu`・`verify_musha_aura_gpu`、ゴーレムは `verify_golem_single_gpu`・`verify_golem_aoe_gpu`・`verify_golem_support_gpu`） | 1 |
| 1人の味方の決め技 | `test_butler_ice_finish`・`test_healer_lightning_finish`・`test_healer_saint_finish`・`test_hero_fire_finish`・`test_samurai_wind_finish`・`test_tank_hammer_finish` の該当 | 実画面か動画。`verify_butler_ice_gpu`・`verify_healer_lightning_gpu`・`verify_healer_saint_gpu`・`verify_hero_fire_gpu`・`verify_tank_hammer_gpu` の該当（侍は `verify_real_skills_gpu` の侍のケース） | 1 |
| 振り分けの表に1体分を足す・替える（`BOSS_*_PRESENTATIONS` など） | そのボスの行のテスト ＋ `test_battle_presentation` | その演出の実画面と `verify_*` | 1〜2 |
| 複数の演出が使う部品（属性の色 `rbm_attribute_vfx_palette.gd`、`rbm_boss_support_vfx.gd`、揺れ・残像などの共通部品） | `grep` で使っている演出を探し、そのテスト ＋ `test_battle_presentation` | 使っている代表の演出の実画面と `verify_*`、`verify_battle_visuals_gpu` | 2 |
| 事前読み込みの内部の最適化（優先順位・内部の cache・保持・解放。ready の判定と戦闘の進め方の契約を変えない。§3.1） | 戦闘演出のテスト群（上の行のすべて ＋ `test_battle_presentation`・`test_rbm_presentation_warmup`・`test_rbm_awakening_presentation`・`test_rbm_boss_awakening_support`・`test_rbm_home_top_monitor_battle`。参考: 26ファイル・約210件・約40秒）＋ 戦闘の画面（`test_rbm_clear_check`・`test_rbm_challenge_flow`・`test_rbm_creator_flow`・`test_rbm_battle_backgrounds`・`test_rbm_phase35_step4_battle_ui`）＋ 契約テストの単独起動（§8） | 最速の操作の経路（戦闘を始める前の画面からすぐに戦闘・最初の入力）での実時間の計測、関係するボスの `verify_*`、`verify_battle_visuals_gpu` | 3 |
| ready の判定の意味・演出を始める時期・行動の進め方・`impact`／`finished` の契約・共通の素材の読み込みの API（`rbm_battle_presenter.gd`、`rbm_battle_stage.gd` の `play_entry()`・`_start_dedicated()`・`cancel()`・`is_playing()` など。§3.1） | 全GUT ＋ 上の行の単独起動 | 上の行と同じ ＋ `verify_real_skills_gpu` | 4（A） |
| 戦闘ロジック（`rbm_battle.gd` など） | 全GUT。先に速い確認として `test_rbm_battle`・`test_rbm_battle_sequential`・`test_rbm_battle_snapshot`・`test_rbm_battle_rewind_boundary`・`test_rbm_advanced_battle`・`test_rbm_awakening`・`test_rbm_multi_attribute`・`test_rbm_phase3_hardcore_overrides`・`test_rbm_creator_test_session`・`test_rbm_challenge_session`（参考: 10ファイル・約200件・数秒） | 実際の戦闘 | 4（A） |
| 定義の読み込み（`rbm_definition_loader.gd`） | 全GUT（先に `test_rbm_definition_loader`・`test_rbm_advanced_definition_loader`） | — | 4（A） |
| 保存と読み込み（`rbm_local_stage_repository.gd`、下書きの保存の形） | 全GUT（先に `test_rbm_local_stage_repository`・`test_rbm_creator_save_load`・`test_rbm_advanced_creator_save_load`・`test_rbm_creator_save_reopen_lifecycle_regression`・`test_rbm_canonical_json`） | `verify_creator_save_reopen_lifecycle_gpu`、実機で保存→再読み込み | 4（A） |
| Creator の1画面（`src/bossmaker/creator/` の特定の STEP・部品） | その画面のテスト ＋ `test_rbm_creator_flow`（例: 条件の編集なら `test_rbm_condition_editor_immediate`・`test_rbm_condition_list_restrictions`、STEP4 のパーティなら `test_rbm_creator_step4_party_footer`） | 実画面（影響する解像度）。その画面の `verify_*` があれば（例: `verify_step3_action_name_update_gpu`・`verify_step3_vertical_scroll_gpu`・`verify_appearance_picker_awakening_gpu`・`verify_musha_picker_gpu`） | 2 |
| Creator の共有の処理（`rbm_creator_main.gd`・`rbm_creator_draft.gd` など） | Creator のテスト群（`test_rbm_creator_*`・`test_rbm_advanced_creator_*`・`test_rbm_condition_*`・`test_rbm_awakening_creator_ui`・`test_rbm_step3_action_name_update_regression`・`test_rbm_step8_layout_regressions`・`test_rbm_step10_card_ui`・`test_rbm_codex_review2_skill_lifecycle`・`test_rbm_appearance_picker_awakening_preview`・`test_rbm_musha_boss_selection`。参考: 17ファイル・約450件・約4分）。下書きの形・保存に触れたら「保存と読み込み」の行 | 実画面、`verify_world_ui_install_gpu` | 3 |
| 挑戦・オンライン（`src/bossmaker/challenge/`、Supabase の呼び出し） | `test_rbm_challenge_flow`・`test_rbm_challenge_hub_and_discovery`・`test_rbm_challenge_session`・`test_rbm_online_boss_list_view`・`test_rbm_online_boss_payload`・`test_rbm_online_challenge_loader`・`test_rbm_online_challenge_recorder`・`test_rbm_loading_state`・`test_rbm_publish_flow`・`test_rbm_boss_publisher`・`test_rbm_creator_online_publish_ui`・`test_rbm_supabase_client`・`test_rbm_supabase_config`・`test_rbm_supabase_response`（参考: 14ファイル・約300件・約1分）から、変更に関係するもの | 実画面（実際のサーバーで確かめる時はユーザーの了承を得る） | 2〜3 |
| 戦闘画面のUI（戦闘の画面・HUD） | `test_rbm_phase35_step3_battle_input_validity`・`test_rbm_phase35_step4_battle_ui`・`test_rbm_realplay1_ui_polish`・`test_rbm_world_ui`・`test_rbm_clear_check`・`test_rbm_challenge_flow`・`test_rbm_battle_backgrounds` から関係するもの。`rbm_battle_ui_kit.gd` の共有の関数なら、`grep` で呼び出し元（presenter・3つの戦闘の画面・演出）を確かめて範囲を決める | 実画面（影響する解像度）、`verify_battle_ui_gpu` | 2〜3 |
| ホーム・タイトル（`rbm_game_root.gd` 以外） | `test_rbm_home_monitor_transition`・`test_rbm_home_top_monitor_battle`・`test_rbm_phase35_title_screen`・`test_rbm_title_effects` | 実画面か動画、`verify_home_monitor_gpu` | 2〜3 |
| `rbm_game_root.gd`・画面の切り替え | 全GUT | `verify_world_ui_install_gpu`・`verify_window_close_gpu`、実機 | 4（A） |
| 音（`rbm_audio.gd`・`rbm_audio_catalog.gd`・音源） | `test_rbm_audio`・`test_musha_audio_levels`・その音を鳴らす演出・画面のテスト | 実際のゲームの音量での再生と音量のバランス（[AUDIO.md](AUDIO.md)）、`verify_se_playback` | 音源だけは 1、再生の仕組みは 3（全画面が使う API を変えたら 4） |
| 翻訳・文字（`localization/ui_strings.csv`） | `test_rbm_locale_switch`・`test_rbm_creator_localization_audit_fixes`・`test_rbm_realplay3_ui_japanese_and_flow`・`test_rbm_ally_display_names` | 日本語・英語の実画面 | 2 |
| Steam | `test_rbm_steam_auth`・`test_rbm_steam_config` | — | 2 |
| 1つのテストファイルだけの変更 | 変えたテスト ＋ そのテストと関係するテスト（同じ機能の契約テスト・同じ補助を使うテスト）＋ 必要に応じて単独起動（§8）。全GUTは Level 4 に当たる時だけ | — | 1 |
| 検証ツール（`tools/verify_*`）だけの変更 | 変えたツールを実際に流す。共有のツール（`verify_battle_visuals_gpu.gd` を継承するツール、`tools/gpu_runner.tscn`）なら、それを使うツールも流す | 変えたツールそのもの | 1〜2 |
| テストの共有の土台（`tests/bossmaker/presentation_assets_ready.gd` など、複数のテストが使う補助） | それを使うテストすべて（`grep` で探す）＋ 単独起動（§8） | — | 2 |
| GUT そのもの（`addons/gut/`）・GUT の起動のしかた | 全GUT | — | 4（A） |
| 品質文書（Markdown）だけ | GUT は不要。リンクの切れ・ファイル名を確かめる | — | — |

- 表は最低限の目安。§2 で調べた呼び出し元・共有の状態に応じて足す。
- 迷った時は上のレベルを選んでよいが、何が分からなかったかを書く（§3 B）。

---

## 6. 実画面・映像・音の確認（GUT だけで完了にしない）
次の区分で、必要な確認を選ぶ。**「GUTが通ったから実画面・動画の確認は不要」とは判断しない。**

| 変更の種類 | 必要な確認 |
|---|---|
| 見た目の変更（タイトル画面・ドット絵のアニメーション・VFX・戦闘演出・背景の見た目） | 実画面か動画での目視を原則必須（PRO_QUALITY_BIBLE §5 の Video。動きはコマ送りも）。その対象の `tools/verify_*` があれば、それも流す（`CLAUDE.md`） |
| UI の配置の変更 | 実画面と、影響する解像度（1280×720 と、その変更で崩れうるもの。例: 1920×1080・縮小・4:3寄り）。その画面の `tools/verify_*` があれば、それも流す（`CLAUDE.md`） |
| GPU の描画の変更（シェーダー・SubViewport・描画の順・合成） | 関連する実GPU検証（`tools/verify_*`）と、実時間のフレーム時間（[PERFORMANCE.md](PERFORMANCE.md) §3） |
| 音の変更 | 実際のゲームの音量での再生と、音量のバランス（[AUDIO.md](AUDIO.md)） |
| ロジックだけの変更 | 影響範囲に応じて選ぶ。画面に出る結果が変わりうるなら、実機で1回確かめる |

- すべての変更で、全部の GPU 検証ツール・全部の解像度を機械的に確かめる必要はない。変更に関係するものを選ぶ。
- 確認を省く時は、その理由を報告に書く（例: 「表示が変わらないことを画素の比較で確かめた」「変更は内部の名前だけで、画面に届く値は変わらない」）。理由を書けない時は省かない。
- 全GUTを省いた分、Visual Review を省くことはしない。見た目・動きの良し悪しは、映像をユーザーが見て決める（PRO_QUALITY_BIBLE §3）。

---

## 7. 報告
作業の完了の報告には、少なくとも次を書く。

```
実行したテスト：
結果：
全GUTを実行したか：
その理由：
```

例（全GUTを実行した時）:
```
全GUTを実行した理由：
rbm_battle_stage.gd の行動の進め方を変え、全ボス・全味方・通常の戦闘・クリアチェックが通るため（Level 4 A）。
```

例（関連テストだけの時）:
```
実行したテスト：武者の演出の関連 5ファイル・78件、verify_musha_gpu、単体の動画
全GUTを省いた理由：
変更は武者の専用の presentation の中に閉じていて、共有の戦闘の状態・UI・素材の読み込みは変えていないため（Level 1）。
```

- 想定外の失敗があった時は、§4.1 のどれに切り分けたか（既知・退行・実行環境）と、その根拠を書く。未解決の失敗は未解決と書く。
- §6 の確認を省いた時は、その理由を書く。

---

## 8. テストの実行順への依存
- テストの実行順のおかげでたまたま通る状態を作らない・残さない（QA-06 で、全GUTでは通るのに1ファイルだけ起動すると落ちる演出のテストが見つかった）。
- 大事な契約テストは、必要に応じて単独起動（1ファイルを1回の起動で）・きれいな状態でも通ることを確かめる。
- 毎回すべてを別々に起動する必要はない。重点を置く時: 実行順への依存が疑われる時、共有の cache・事前読み込み・static・autoload・テストの共有の補助を変えた時。
- 起動のしかた（リポジトリのルートで）:
  - 1ファイル: `Godot_v4.7-stable_win64_console.exe --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest=res://tests/bossmaker/<ファイル>.gd -gexit`
  - 複数のファイル（1回の起動で）: `-gtest=` を並べる
  - 全GUT: [README.md](../../README.md) の「全テスト」

---

## 9. 全GUTの役割
- 毎回の変更では実行しなくても、全GUTはなくさない。大きな節目・統合の後・リリースの前・広い変更・影響範囲が分からない時の、最後の回帰の安全網。
- [PRO_QUALITY_BIBLE.md](PRO_QUALITY_BIBLE.md) §1.1 の Release Gate の「全GUT」は、リリース候補・大きな統合の時（§3 Level 4 D）の確認。個々の作業では、その作業のレベルのテストで、Release Gate に関わる部分（クラッシュ・ゲームロジックの退行など）を確かめる。
- 全GUTの規模（参考値。2026-10-08、作業ツリー全体）: 95ファイル／1,693件／40,872 assert、失敗0・エラー0。参照機で約10分。PC がスリープすると GUT の表示時間が大きく伸びるので、時間を比べる時はスリープの有無を確かめる。
