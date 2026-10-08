---
name: mc-combat-presentation
description: Routes Makers & Challengers battle-presentation work to the project quality docs in docs/quality/. Use when creating, modifying, or reviewing boss attacks, awakening sequences, ally skills and finishers, hit reactions, VFX and shaders, camera shake, hit stop, flashes, or character motion and idle loops (戦闘演出・ボスの技・覚醒・味方の技・エフェクト・アニメーション). Do not use for menu or UI layout, audio-only changes, or performance-only profiling; use mc-ui-accessibility, mc-audio, or mc-godot-performance for those.
---

# mc-combat-presentation

戦闘演出の作業で、どの品質文書のどの章を読み、最後に何を確かめるかを決める案内。品質の正本は `docs/quality/`。規約の本文はここに書き足さない。

## 始める前
1. [PRO_QUALITY_BIBLE.md](../../../docs/quality/PRO_QUALITY_BIBLE.md) §1（判断基準・Release Gate・数値の扱い）と §6（してはいけないこと）を確認する。
2. `git status` で、他の未コミット変更と自分の変更を分ける。reset／checkout／stash／clean は使わない。
3. 直す対象が [QUALITY_AUDIT.md](../../../docs/quality/QUALITY_AUDIT.md) にあれば、その QA 項目を読む。

## 読むもの（作業に関係する章だけ）
| 作業 | 読む |
|---|---|
| ポーズ・タイミング・待機・移動 | [ANIMATION_CRAFT.md](../../../docs/quality/ANIMATION_CRAFT.md) の該当章、[COMBAT_PRESENTATION.md](../../../docs/quality/COMBAT_PRESENTATION.md) §3 |
| 技の構成・長さ・Impact | COMBAT_PRESENTATION.md §1・§2・§3.3 |
| VFX・Shader | COMBAT_PRESENTATION.md §5、[ART_DIRECTION.md](../../../docs/quality/ART_DIRECTION.md) §3.1・§6・§8 |
| 揺れ・Hit Stop・Flash | COMBAT_PRESENTATION.md §4、[ACCESSIBILITY.md](../../../docs/quality/ACCESSIBILITY.md) §4・§5 |
| ドット絵との統一 | COMBAT_PRESENTATION.md §6、ART_DIRECTION.md §2 |
| 覚醒・覚醒後 | COMBAT_PRESENTATION.md §7 |
| 実装の決まり（専用スクリプト・共通部品・中断） | COMBAT_PRESENTATION.md §9 |
| 重さ・停止 | [PERFORMANCE.md](../../../docs/quality/PERFORMANCE.md) §1〜§3（深く測る時は mc-godot-performance） |
| 音を付ける・直す | [AUDIO.md](../../../docs/quality/AUDIO.md) §2・§3（音が中心なら mc-audio） |

## 守ること
- 戦闘状態・乱数・保存データに触れない。演出は確定した戦闘イベントを読むだけ。
- 承認済みの演出を、規約の数値に合わせるためだけに作り直さない。新しい見た目の方向性を決めない（未決定はユーザーに判断を求める）。
- 技・キャラ・ボスごとに固有の演出にする。共通にするのは基礎部品だけ。
- 1回に1つの問題だけを扱う。

## 終わる前
- Test（実行範囲は PRO_QUALITY_BIBLE.md §5）→ Runtime（実GPU・実時間のフレーム時間、1280×720と1920×1080）→ Video（一覧画像・動画）の順で確かめる。
- [REVIEW_CHECKLIST.md](../../../docs/quality/REVIEW_CHECKLIST.md) のリスト A・B・C を埋める（音を触ったら F も）。
- 見た目の良し悪しは、映像をユーザーが見て決める。このSkillや規約を読んだことを品質の根拠にしない。
