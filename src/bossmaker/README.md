# RPG BOSS MAKER — 戦闘コア（分離境界）

このディレクトリ（`src/bossmaker/`）と `data_bossmaker/` は、RPG BOSS MAKER（仮称）専用の
戦闘コアです。既存UNDERDESKの `src/core/sim.gd` / `src/ui/main.gd` とは意図的に分離されて
おり、どちらの方向にも依存しません。

## なぜ分離しているか

既存 `UDSim` にはUNDERDESK進行・DEF・REWIND・REWINDⅡ・部位破壊・どうぐ・報酬・ステージ進行・
既存ボスAIが強く結合しており、これらを少しずつRPG BOSS MAKER仕様へ改造する方式は採用しない
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

## 現状（Step 2完了時点）

- UI非依存の戦闘コア（`RBMBattle`/`RBMUnit`/`RBMConstants`/`RBMDataLoader`）
- 固定5キャラクター・全20スキルのデータ定義（`data_bossmaker/allies/*.json`）
- テスト用ボス定義（`data_bossmaker/enemies/test_boss.json`）
- 自動テスト（`tests/bossmaker/`）

まだ実装していないもの（Step 2完了条件・実装しないものリスト参照）：SIMPLE/ADVANCED
Creator、Clear Check UI、CHALLENGE UI、既存 `main.gd`/`main.tscn` への接続、指定行動、演出/VFX、
セーブ、オンライン。
