---
name: mc-godot-performance
description: Routes Makers & Challengers performance work to the project quality docs in docs/quality/. Use when measuring or fixing frame drops, hitches, first-use stalls, slow screen or title-room creation, heavy shaders or SubViewports, draw-call spikes, or large texture loading in the Godot 4 game (処理落ち・カクつき・停止・重い). Requires real-time GPU measurement and keeping the visuals identical. Do not use to judge visual quality or to cut visuals for speed.
---

# mc-godot-performance

処理落ち・停止の計測と改善で、どの品質文書を読み、どう測るかを決める案内。品質の正本は `docs/quality/`。規約の本文はここに書き足さない。

## 始める前
1. [PERFORMANCE.md](../../../docs/quality/PERFORMANCE.md) §1（予算と位置づけ）・§1.2（改善と呼べるもの）を確認する。
2. [PRO_QUALITY_BIBLE.md](../../../docs/quality/PRO_QUALITY_BIBLE.md) §5.1（録画モードは処理落ちを隠す、検証ツールの読み出しが止める）を確認する。
3. `git status` で、他の未コミット変更と自分の変更を分ける。
4. 直す対象が [QUALITY_AUDIT.md](../../../docs/quality/QUALITY_AUDIT.md) にあれば、その QA 項目の実測を読む。

## 読むもの
| 作業 | 読む |
|---|---|
| 予算・目標 | PERFORMANCE.md §1 |
| 原因の候補と対策 | PERFORMANCE.md §2 |
| 測り方 | PERFORMANCE.md §3 |
| 構造の決まり | PERFORMANCE.md §4、[COMBAT_PRESENTATION.md](../../../docs/quality/COMBAT_PRESENTATION.md) §5.3・§9 |
| テストと実GPUの確認 | PERFORMANCE.md §5 |

## 進め方
1. 実時間で測る（フレームごとの経過時間、平均・最悪・20ms超・33ms超、Performance の objects／draw calls／primitives）。再生中に画面の読み出し・保存・print をしない。
2. 同じ演出を同じ起動の中で2回測り、初回だけの停止か、毎回の重さかを分ける。1280×720と1920×1080の両方で測る。
3. 原因を1つに絞ってから直す（CPU側の処理か、GPU側の描画か）。
4. 直した後、同じ方法で測り直し、見た目が同じことを画素の比較か一覧画像で確かめる。

## 守ること
- 見た目を削っただけで速くして「改善」と呼ばない。見た目を変える必要があるなら、前後の映像をユーザーに見せて判断を求める。
- 録画モード（`--write-movie`／`--fixed-fps`）の滑らかさで性能を判断しない。
- 戦闘状態・乱数・保存データに触れない。

## 終わる前
- 修正前後の数値（平均fps・最悪・20ms超・33ms超）を並べて報告する。
- [REVIEW_CHECKLIST.md](../../../docs/quality/REVIEW_CHECKLIST.md) のリスト A・C を埋める（演出を触ったら B も）。
