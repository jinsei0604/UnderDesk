# Makers & Challengers — 戦闘コア（分離境界）

このディレクトリ（`src/bossmaker/`）と `data_bossmaker/` は、Makers & Challengers専用の
戦闘コアです（内部ディレクトリ名/クラス接頭辞`bossmaker`/`RBM`は開発時の作業名"RPG Boss
Maker"に由来し、内部識別子としてそのまま維持している——現在の正式なゲーム名は
Makers & Challengers）。既存UNDERDESKの `src/core/sim.gd` / `src/ui/main.gd` とは意図的に
分離されており、どちらの方向にも依存しません。

## なぜ分離しているか

既存 `UDSim` にはUNDERDESK進行・DEF・REWIND・REWINDⅡ・部位破壊・どうぐ・報酬・ステージ進行・
既存ボスAIが強く結合しており、これらを少しずつMakers & Challengers仕様へ改造する方式は採用しない
（Step 1調査結果／Step 2指示 §1参照）。代わりに、同じGodotプロジェクト内に新しい戦闘境界を
作り、将来的にUI/Creator/Clear Checkを接続したのち、不要になった旧コードを削除する。

## この戦闘コアがUNDERDESKと違う点

- **DEFステータスが存在しない**。ダメージは `ATK × スキル倍率 × 属性補正 × 軽減` の乗算式
  （UNDERDESKの `max(1, ATK - DEF)` 方式は使わない）。
- **レベル成長がない**。5人の味方キャラクターは完全固定ステータス。
- **属性システムを持つ**（炎/氷/雷/風/無、弱点1.2倍・耐性0.8倍）。UNDERDESK側にはこの仕組み
  自体が存在しない。
- **REWIND/REWINDⅡ/逃走/部位破壊/どうぐが存在しない**。仕様書 v0.1〜v0.1-Bのどこにもこれらへ
  の言及はなく、UNDERDESK「新企画v1」固有の別ゲームの仕組みである。

## 命名規約

クラス名は `RBM` プレフィックス（RPG Boss Maker）を使用し、`UD` プレフィックスのUNDERDESK側
クラスと明確に区別する。

## 現状（Step 3修正版時点）

- UI非依存の戦闘コア（`RBMBattle`/`RBMUnit`/`RBMConstants`/`RBMDataLoader`）— Step 2から
  「無改修」の方針だったが、指定行動（§下記）の追加のため今回のみ`rbm_battle.gd`へ最小限の
  追加を行った（既存の戦闘ロジック・既存51テストの挙動は一切変更していない）
- 固定5キャラクター・全20スキルのデータ定義（`data_bossmaker/allies/*.json`）
- **`BossBattleDefinition`解決レイヤー（`RBMDefinitionLoader`）**：Definition→検証・解決→
  戦闘用データ→既存`RBMBattle`という流れを担う。Definitionそのものは
  `data_bossmaker/definitions/*.json`
- 自動テスト（`tests/bossmaker/`）

### Step 3修正版：BossBattleDefinition（設計訂正あり）

最初のStep 3実装はボスを「マスターenemyファイル参照＋許可スキルで絞り込む」方式にしていたが、
これはv0.1-B §2/§3の確定仕様と矛盾していた（Codex再レビューでFAIL）。確定仕様では、ボスの
HP/ATK/SPD/弱点/耐性も、ボスが持つスキル（攻撃/自己回復/ATK自己強化の3種のみ）も、**すべて
作者がそのボス戦のために直接作成する**——味方キャラのような「ゲーム固定のマスターデータ」は
ボス側には存在しない。そのため：

- **味方**：引き続きゲーム固定マスター参照（`data_bossmaker/allies/*.json`、5人固定）。
  `allowed_skill_ids`を省略すると「全スキル使用可能」がデフォルト。指定した場合はそれが唯一の
  正とし、許可されていないスキルは`RBMUnit.skills`自体に存在しないため、既存の`_find_skill`/
  `unknown_skill`拒否機構がコード変更なしにそのまま戦闘ロジック側の拒否を担う。
- **ボス**：マスターファイル参照（`RBMDefinitionLoader`経由）を廃止し、Definitionの`boss`オブジェクト
  内に全てを直接記述する。`data_bossmaker/enemies/test_boss.json`は`RBMDefinitionLoader`からは
  参照されなくなったが、`tests/bossmaker/test_rbm_battle.gd`（Step 2自身の既存フィクスチャ、
  Definition解決とは無関係）から今も直接読み込まれているため、プロジェクト全体では未参照では
  ない。`frost_sentinel.json`は本当にどこからも参照されなくなったが、削除はしていない。
  - `hp`/`atk`/`spd`：範囲検証あり（HP 1〜1,000,000・ATK 1〜9,999・SPD 1〜500）、範囲外・未指定
    は補正せず拒否
  - `weak_attributes`/`resist_attributes`：任意（v0.1-C 多属性対応）。5属性
    （`FIRE`/`ICE`/`LIGHTNING`/`WIND`/`NEUTRAL`、`NEUTRAL`＝無属性も他と同じ1属性として
    複数配列へ保持・判定される）のいずれかを0個以上、両方の配列でそれぞれ独立に指定可能。
    旧形式の単数キー`weak_attribute`/`resist_attribute`（単一の属性名文字列 or 省略）も
    引き続き読み込め、内部的には1要素の配列として扱われる（後方互換、Step 3までの
    既存Definition/テストはそのまま動作）。両方指定された場合は複数形キーを優先
  - `skills`：作者作成スキルの配列。`type`が`"attack"`/`"self_heal"`/`"atk_self_buff"`のいずれか
    のみで、それぞれ必須フィールドが異なる（`_resolve_author_boss_skill`参照）。内部的には
    Step 2から存在する`"damage"`/`"heal"`/`"buff_atk_self"`へそのまま変換される（この3種の
    エフェクト自体はStep 2から実装済みなので、エンジン側の変更は不要だった）
  - `normal_actions`：`skills`のうち「通常ターンでランダム候補になるスキル」と、その重み
    （省略時は等確率）。`skills`に定義されているが`normal_actions`に無いスキルは「使用可能だが
    通常候補ではない」——指定行動でのみ発動できる
  - `scripted_actions`（指定行動、v0.1-B §5）：`{"turn":int,"skill_id":String,
    "timing":"replace"|"turn_start_interrupt"|"turn_end_interrupt","order":int}`の配列。
    `"replace"`はボスのNORMAL ACTION PHASEの1回の行動枠を差し替える。2種の`"...interrupt"`は
    SPDを無視した追加行動（ボスの通常行動を置き換えない）。同一ターン・同一タイミングが複数
    ある場合は`order`昇順で解決する（同一ターン・同一タイミングに`"replace"`が複数ある場合も、
    最初の1件だけでなく全件がorder昇順で実行され、その場合ボスの通常行動は発生しない——
    Step 3最終修正指示 §1）。**これはStep 2が「将来の指定行動用の縫い目」とだけ用意していた
    箇所に、既存戦闘ロジックには存在しなかった仕組みを最小限追加したもの**——
    `rbm_battle.gd`の`resolve_turn()`に2つの新しいループ（TURN START直後／NORMAL ACTION PHASE
    直後）、ボスの通常行動枠を担う`_resolve_boss_turn_actions()`（該当ターンの`"replace"`が
    1件でもあればそれを全件order昇順で実行し、無ければ従来通り`_pick_boss_normal_action()`に
    委ねる）、および`_apply_boss_skill()`/`_scripted_actions_for()`/
    `_resolve_scripted_boss_action()`を追加したのみで、他の既存経路（味方行動・防御・かばう・
    カウンター・ダメージ式・TURN END等）は一切変更していない。`scripted_actions`が空/未指定
    なら両ループ・`_resolve_boss_turn_actions()`の分岐とも完全なno-opになるため、既存の
    Definitionやテストの挙動には影響しない。

不正なDefinition（存在しないID・範囲外のボス数値・未知の属性・パーティ人数1〜4の範囲外・
パーティ内の重複キャラID等）は`RBMDefinitionLoader.resolve()`がその場で失敗を返し、黙って
補正した戦闘データを返すことはない。

### Step 4：SIMPLE Creator + TEST BATTLE + Turn REWIND

`src/bossmaker/creator/`。STEP1〜7のステップ式UI（`RBMCreatorMain`が編集中データ
`RBMCreatorDraft`を保持し、各STEPビューはそこへ直接読み書きする）＋TEST BATTLE
（`RBMCreatorTestSession`、`RBMBattle.snapshot()`/`restore()`ベースのTurn REWIND、回数無制限・
単一タイムライン）。詳細はStep4完了報告を参照。

### Step 5：Clear Check

「Creatorで作成したボス戦を作者自身が正式な勝利条件で攻略できるか」を確認する機能
（`src/bossmaker/creator/rbm_creator_clear_check_view.gd`）。TEST BATTLEとの違いは、勝利
（`RBMBattle.winner == "ally"`、既存の`_check_battle_over()`が設定する値をそのまま読むだけで、
`boss.hp<=0`等の独自判定は一切持たない）の瞬間に`RBMCreatorDraft.record_clear_check_success()`
が呼ばれる点のみ——戦闘セッション自体は`RBMCreatorTestSession`を無改修のまま再利用している
（TEST BATTLE専用の要素を元々持たない汎用クラスだったため）。

**Clear Check成功状態の保持と比較**（`RBMCreatorDraft._clear_check_success_snapshot`）：
成功した瞬間の「戦闘内容」（`battle_content_snapshot()`）をdeep copyして保持し、以後は
Draftの現在値から都度生成した`battle_content_snapshot()`と生のDictionary比較（`==`）で
「まだ有効か」をライブ判定する（キャッシュしない——編集して元の値へ戻せば、追加の復元処理
なしに自動的に再び一致する）。ハッシュ化やrevision番号方式は採用していない（Step 5技術調査で
比較検討済み）。

比較対象に**含まれない**もの：`boss_id`／`boss_name`／`appearance_id`（いずれも戦闘結果へ
影響しない識別・表示専用フィールド）。パーティは配列順序ではなく`character_id`をキーとした
Dictionaryへ変換してから比較するため、パーティの並び替えだけではClear Checkは無効化されない
（メンバー構成そのものが変われば無効化される）。各キャラクターの`allowed_skill_ids`も同様に
ソート済み配列として比較し、スキル一覧の並び順自体は無視する（`rbm_battle.gd`側の唯一の
消費経路が`_find_skill()`のid指定線形探索であり、順序が戦闘結果へ影響しないことを確認済み）。
一方、`normal_actions`（配列順序自体が`_pick_boss_normal_action()`の累積重み判定に影響しうる
ため）と`scripted_actions`（`order`フィールドが同一(turn,timing)グループ内の実行順を左右する
ため）は、`to_definition()`が使うのと同じ生成ロジックをそのまま再利用し、順序を保持したまま
比較する。

**`skill_id`の扱い（Step 5完了報告への追記、ユーザー確定 2026-08-29）**：ボス自身の各スキルは
`skill_id`（`RBMCreatorDraft.add_skill()`が呼ばれるたび単調増加するカウンタから生成される
内部識別子）込みで比較対象に含める、と確定した。これは`boss_id`（比較対象外、識別用のみ）とは
異なる扱いであり、意図的な非対称——`normal_actions`/`scripted_actions`の各エントリが
この`skill_id`でスキルを参照する、という既存のDefinitionスキーマ設計をそのまま維持するための
確定仕様である。結果として：
- 既存スキルをSTEP3の編集画面で値だけ変更する場合（`RBMCreatorDraft.update_skill()`、
  `skill_id`は変わらない）：A→B→Aと値を戻せば、Clear Check成功状態は自動的に復元される。
- スキルを一度削除して同じ内容で作り直す場合：新しい`skill_id`が発行されるため、最終的な
  設定値が完全に同一であっても「別のスキル」として扱われ、再Clear Checkが必要になる。

### Step 6：ローカル保存・再編集

Creatorで作成したボス戦をローカルへ保存し、後から再編集できるようにする機能。
`src/bossmaker/creator/rbm_local_stage_repository.gd`（保存I/O層）・
`rbm_creator_save_view.gd`（保存フローUI）・`rbm_creator_entry.gd`（CREATE入口・
保存stage一覧・検索・削除）を新設し、`rbm_creator_draft.gd`/`rbm_creator_main.gd`/
`rbm_creator_step7_summary.gd`へ最小限の追加を行った。

**保存条件（§0-1、重要な確定仕様）**：Clear Checkの有無に関係なく保存できる。
Clear Checkは保存許可条件ではなく「作者自身がこの戦闘内容を実際にクリアした証明」
であり、Definition validationに失敗する未完成の下書きも保存できる（保存処理自体は
`RBMDefinitionLoader`を一切呼ばない）。

**1 stage = 1 JSONファイル**（`user://bossmaker/stages/<stage_id>.json`）。全stageを
1ファイルへまとめる方式やSQLite等は採用していない（Step 6技術調査報告での比較検討
の結果、削除/保存のコストがstage数に依存しない・1ファイル破損時の影響が他stageへ
波及しないという理由）。

**atomic save**：`<stage_id>.json.tmp`へ書き込んでから`DirAccess.rename()`で本番
ファイルへ置換する（実機のWindows環境で動作確認済み）。書き込み途中でクラッシュ
しても既存の本番ファイルは無傷のまま残る。世代バックアップはPhase 1では未実装。

**stage_id**：10桁固定・数字のみ・String型（先頭0許容、`"0123456789"`のような
内部Stringとして扱う——10桁の`int`として丸めると先頭0が失われるため）。各桁を
0〜9のランダム値として生成し10文字連結、ローカルの既存stage_id集合と照合して
衝突していれば再生成する（`RBMLocalStageRepository.generate_unique_stage_id()`）。
新規保存時のみ新しいidを発行し、上書き保存では既存idを維持する。**ローカルの
stage_idは、将来Phase 4でオンライン公開する際のグローバル公開IDとしてそのまま
転用できるものではない**——複数ユーザーがそれぞれ独立にローカルで採番するため、
ユーザー数が増えれば衝突確率が現実的な水準に達しうる（誕生日問題）。Phase 4の
具体的な公開ID設計はまだ確定していない。

**保存の正データ（§7、二重保存回避）**：`BossBattleDefinition`はJSONへ保存しない
——`RBMCreatorDraft.to_definition()`から副作用なく再生成できるうえ、Draft自身の
生の著作フィールド（例：self_healの`heal_mode`/`heal_fixed_amount`/`heal_percent`）は
Definitionへ変換すると失われるため、そちらを保存の正とする。`RBMCreatorDraft`へ
`to_saved_dict()`（生の著作フィールド一式）・`full_authoring_snapshot()`
（`to_saved_dict()`の範囲＋Clear Check成功snapshot自体を含む、未保存変更判定専用）・
`restore_from_saved_dict()`（JSON数値型正規化を含む逆変換）・
`clear_check_snapshot_for_save()`/`restore_clear_check_snapshot()`（Clear Check証明
の保存/復元）・`is_playable()`（Definition validationのライブ判定）を追加した。
既存の`battle_content_snapshot()`・`record_clear_check_success()`・
`has_ever_cleared()`・`is_clear_check_currently_valid()`（いずれもStep 5から）は
無改修のまま——保存/ロードを挟んでもこれらの比較ロジックがそのまま機能する。

`_next_skill_ordinal`は必ずそのまま保存する（既存skill_idの最大値から再計算しては
いけない）——さもないと「スキル削除→同内容再作成は別skill_id扱い」というStep 5の
確定仕様（README.md「Step 5」節参照）が、削除済みidの再利用によって壊れうる。

**JSON数値型正規化**：Godot 4.7の`JSON.parse_string()`（実機検証済み）はJSON上の
すべての数値を無条件でfloatとして返す（`1000`のような小数点のないリテラルでも
`1000.0`になる）。そのため`RBMCreatorDraft.restore_from_saved_dict()`/
`restore_clear_check_snapshot()`は、フィールドの意味的な型（hp/atk/spd/
`_next_skill_ordinal`/heal_fixed_amount/duration_turns/turn/order等は`int()`、
atk_multiplier/heal_percent/buff_multiplier/weight等は`float()`）へ明示的に
再キャストする。正規化しないと、GDScriptの`Dictionary ==`はint/floatの型不一致で
falseを返すため、`is_clear_check_currently_valid()`が正しくクリア済みのstageを
ロードしても常にfalseになってしまう（新しい丸め仕様は追加していない、
`int()`/`float()`という既存の標準キャストのみ）。

**未保存変更判定**：`RBMCreatorMain`が「最後に保存した、または新規Creator起動
直後の」`full_authoring_snapshot()`（`_reference_authoring_snapshot`）を保持し、
現在のdraftから都度生成した同じsnapshotと比較するだけのライブ判定
（`has_unsaved_changes()`）——dirty flagではないため、A→B→Aと完全に元へ戻せば
自動的に未保存変更なしへ戻る。Clear Check成功snapshot自体もこの比較対象に含む
（確定仕様）ため、著作内容を一切変更していなくてもClear Checkに成功しただけで
未保存変更ありと判定される。

**状態は保存しない**：`draft`/`playable`/`clear_checked`という3状態は、保存JSONへ
固定値として書き込まず、`RBMLocalStageRepository.list()`が毎回`draft.is_playable()`
/`draft.is_clear_check_currently_valid()`から都度算出する（キャッシュしない——
Step 5の`is_clear_check_currently_valid()`自体が既に採用している設計哲学と一貫
させるため）。

**新しいボスとして保存はSave As型**（確定仕様）：実行後、Creatorは新しく発行された
stage_idを現在編集中として扱うよう切り替わる（`RBMCreatorMain.current_stage_id`）。
元stageは一切変更されない。現在Draftに有効なClear Check証明があれば、stage_idが
変わってもそのまま引き継がれる（`battle_content_snapshot()`が`boss_id`/`stage_id`を
比較対象外としている既存の設計のおかげで、保存側で特別な処理は不要）。

**Creator入口・一覧・削除**：`RBMCreatorEntry`が「新しいボス戦を作る」/
「保存したボス戦を編集」の2系統と、後者から開くローカル保存stage一覧（下書きも
含めすべて表示、ボス名部分一致・stage_id完全一致検索、削除確認画面つき）を提供
する。`RBMCreatorMain`を1つだけ保持し続け（構築のたびに破棄・再構築しない）、
`start_new()`/`start_loaded()`は既存のdraftオブジェクトの**フィールドだけ**を
`restore_from_saved_dict()`経由で書き換える——draftの**参照自体**は差し替えない。
これはSTEP1-7の各ビューが`setup()`時に受け取ったdraft参照を自分で保持し続ける
既存設計（このファイル冒頭のコメント参照）と両立させるための構成で、参照を
差し替えると再度`setup()`を呼ばない限りビュー側が古い参照を見続けてしまう
（`setup()`を再度呼ぶとUI二重構築のリスクがある）ため、この設計にした。

**Creator退出の未保存確認**：`RBMCreatorMain`にSTEP1-7のナビゲーション文脈でのみ
表示される「Creator一覧へ戻る」ボタンと、未保存変更がある場合の確認パネル
（保存する/保存せず終了/キャンセル）を追加した。「保存する」は通常の保存フロー
（STEP7の保存ボタンと同じ画面）へ進むだけで、既存stageだからといって自動上書きは
しない——保存後にCreatorを自動的に退出する挙動にはしていない（保存操作自体が
強制的にCreator全体から追い出すのは不自然という判断、実装上の解釈として
記録）。TEST BATTLE/CLEAR CHECK/保存の各サブ画面からの退出はそれぞれ既存の
「Creatorに戻る」導線がSTEP7へ戻すのみで、これらのサブ画面からCreator全体を
退出する経路は今回scope外のまま。

まだ実装していないもの：ADVANCED Creator、CHALLENGE（挑戦者側はREWIND不可の別仕様、
Step 6で保存したstageのうちplayable以上のみを一覧表示する予定）、オンライン公開・
公開ID発行、条件分岐AI、演出/VFX、既存`main.gd`/`main.tscn` への接続、世代
バックアップ、`_index.json`による検索高速化。
