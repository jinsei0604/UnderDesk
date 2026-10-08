---
name: mc-art-direction
description: Routes Makers & Challengers art-direction questions to the project quality docs in docs/quality/. Use when deciding or reviewing the look of something new or changed - pixel-art consistency, character and boss silhouettes, palettes and saturation, backgrounds and lighting, boss themes and shape language, the visual balance between UI and battle, or title-room visuals (ドット絵・見た目の方向性・背景・配色・ボスのテーマ). Records undecided items as USER DECISION REQUIRED instead of inventing a new style. Do not use for battle timing details, UI behavior, audio, or performance work.
---

# mc-art-direction

見た目の方向性を扱う作業で、どの品質文書を読み、何を決めてはいけないかを示す案内。品質の正本は `docs/quality/`。規約の本文はここに書き足さない。

## 始める前
1. [ART_DIRECTION.md](../../../docs/quality/ART_DIRECTION.md) の記号（【固定】【現状】【未決定 / USER DECISION REQUIRED】【判断の問い】）と §10 の未決定の一覧を確認する。
2. [PRO_QUALITY_BIBLE.md](../../../docs/quality/PRO_QUALITY_BIBLE.md) §1 と §6 を確認する。
3. `git status` で、他の未コミット変更と自分の変更を分ける。

## 読むもの（作業に関係する章だけ）
| 作業 | 読む |
|---|---|
| 新しいボス・キャラの見た目・テーマ | ART_DIRECTION.md §1・§3・§9 |
| ドット絵の格子・解像度・拡大 | ART_DIRECTION.md §2、[COMBAT_PRESENTATION.md](../../../docs/quality/COMBAT_PRESENTATION.md) §6、[UI_UX.md](../../../docs/quality/UI_UX.md) §10.1 |
| 背景・照明・奥行き | ART_DIRECTION.md §4・§5 |
| VFX の形・色・明暗 | ART_DIRECTION.md §6・§8、COMBAT_PRESENTATION.md §5.4〜§5.7 |
| UI と戦闘の見た目の関係・配色 | ART_DIRECTION.md §7、UI_UX.md §11 |
| タイトルの部屋（Codex担当） | UI_UX.md §7、ART_DIRECTION.md §1 |
| 承認・却下の例 | [examples/README.md](../../../docs/quality/examples/README.md) |

## 守ること
- ART_DIRECTION.md に書かれていない方向性を決めない。必要なら「未決定 / USER DECISION REQUIRED」として、選択肢と比較画像をユーザーに示す。
- 【固定】の事項を変えない。【現状】を変える時もユーザーに確かめる。
- ドット絵の格子は基本だが絶対ではない。外れる表現はユーザーが動画で承認した場合だけ使う。既存を格子違反だけで作り直さない。
- 他の作品の画像・デザインをコピーしない。承認済みの例も、原理だけを学び、そのまま流用しない。
- タイトル画面・ボスの部屋の見た目は Codex の担当。

## 終わる前
- [REVIEW_CHECKLIST.md](../../../docs/quality/REVIEW_CHECKLIST.md) のリスト A（見た目の項目を含む）と、対象に合わせて B・D・E を埋める。
- 比較画像・動画をユーザーに見せて判断を求める。AIの自己評価だけで「良い見た目」と確定しない。
