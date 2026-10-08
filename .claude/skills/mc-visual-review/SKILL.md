---
name: mc-visual-review
description: Reviews Makers & Challengers videos, frame sheets, and screenshots against the project quality docs in docs/quality/. Use when asked to look at footage or images of battle presentations, awakenings, ally skills, UI screens, or title rooms and judge quality, find problems, or compare before and after (動画・一覧画像・スクリーンショットのレビュー). Reports findings with frame or time positions and allows "no change needed"; the final verdict stays with the user. Do not use to implement fixes; hand those to the matching skill.
---

# mc-visual-review

動画・一覧画像・スクリーンショットのレビューで、何を基準に見て、どう報告するかを決める案内。品質の正本は `docs/quality/`。規約の本文はここに書き足さない。

## 始める前
1. [PRO_QUALITY_BIBLE.md](../../../docs/quality/PRO_QUALITY_BIBLE.md) §1（判断基準）と §3（Review A〜L）を確認する。
2. 撮影の条件を確かめる: 実時間か `--fixed-fps` か、解像度、どの画面か。録画モードの滑らかさで性能を判断しない（§5.1）。

## 読むもの（見る対象に関係する章だけ）
| 見る対象 | 読む |
|---|---|
| 動き（ポーズ・タイミング・Spacing・弧・ループ） | [ANIMATION_CRAFT.md](../../../docs/quality/ANIMATION_CRAFT.md) §2〜§15 |
| VFX（形・明暗・雑音・テーマ） | [COMBAT_PRESENTATION.md](../../../docs/quality/COMBAT_PRESENTATION.md) §5、[ART_DIRECTION.md](../../../docs/quality/ART_DIRECTION.md) §6 |
| 画面の注目の順・同じゲームに見えるか | ART_DIRECTION.md §1〜§8 |
| UI・文字 | [UI_UX.md](../../../docs/quality/UI_UX.md)、[ACCESSIBILITY.md](../../../docs/quality/ACCESSIBILITY.md) §1〜§3 |
| 閃光・揺れ | ACCESSIBILITY.md §4・§5 |
| 確認項目の一覧 | [REVIEW_CHECKLIST.md](../../../docs/quality/REVIEW_CHECKLIST.md) の該当リスト |
| 承認・却下の例 | [examples/README.md](../../../docs/quality/examples/README.md) |

## 見方
1. コマ送りで見る。1コマ止めてポーズ・構図が成り立つか（Review H）、一番見てほしい場所が明確か（Review I）。
2. シルエット・明暗の順・形・色・タイミングを確かめる。
3. 実時間の映像で、速さ・重さ・テンポ・音との一致を確かめる。

## 報告の形
見つけたことごとに:
- どこで（時刻・コマ番号・画面の位置）
- プレイヤーに何が見えるか
- どの原則に関係するか（文書と章）
- 優先度（P0〜P3）、または「直さない」
- 案（承認済みの演出なら、選択肢としてユーザーの判断に回す）

## 守ること
- 規約との差があるだけで、作り直しを勧めない。「直さない」も正しい結論になりうる。
- 承認済みの演出を変える提案は、ユーザーの判断事項として示す。
- AIのレビューだけで「プロ品質」「合格」と確定しない。最終判断はユーザー。
