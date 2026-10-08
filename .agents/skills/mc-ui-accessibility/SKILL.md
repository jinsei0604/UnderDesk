---
name: mc-ui-accessibility
description: Routes Makers & Challengers UI and accessibility work to the project quality docs in docs/quality/. Use when creating, changing, or reviewing screens, menus, HUD, dialogs, transitions, loading/empty/error states, text size, fonts, contrast, color-only cues, focus and keyboard or gamepad navigation, photosensitivity or motion settings, or window/fullscreen scaling (UI・画面・文字の大きさ・コントラスト・全画面). Do not use for battle VFX timing, audio mixing, or performance profiling.
---

# mc-ui-accessibility

画面・UI・遊びやすさの作業で、どの品質文書を読み、最後に何を確かめるかを決める案内。品質の正本は `docs/quality/`。規約の本文はここに書き足さない。

## 始める前
1. [PRO_QUALITY_BIBLE.md](../../../docs/quality/PRO_QUALITY_BIBLE.md) §1（Release Gate の「読めないUIなし」「重大なAccessibility問題なし」を含む）と §6 を確認する。
2. `git status` で、他の未コミット変更と自分の変更を分ける。
3. 直す対象が [QUALITY_AUDIT.md](../../../docs/quality/QUALITY_AUDIT.md) にあれば、その QA 項目を読む。

## 読むもの（作業に関係する章だけ）
| 作業 | 読む |
|---|---|
| 画面の作り・主な行動・状態の表示 | [UI_UX.md](../../../docs/quality/UI_UX.md) §1・§12・§13 |
| 文字の大きさ・コントラスト・色以外の手がかり | [ACCESSIBILITY.md](../../../docs/quality/ACCESSIBILITY.md) §1〜§3、UI_UX.md §2・§16 |
| ボタンの手応え・フォーカス・キーボード／パッド | UI_UX.md §3・§14、ACCESSIBILITY.md §6 |
| 画面遷移・UIの動き | UI_UX.md §4・§15、ACCESSIBILITY.md §4 |
| 戦闘HUD | UI_UX.md §5 |
| ボス作成（Creator） | UI_UX.md §6 |
| オンライン・Loading・エラー | UI_UX.md §8・§13 |
| 翻訳 | UI_UX.md §9 |
| 設定・全画面・拡大方式 | UI_UX.md §10・§10.1 |
| 配色・画風 | [ART_DIRECTION.md](../../../docs/quality/ART_DIRECTION.md) §7、UI_UX.md §11 |
| 光過敏 | ACCESSIBILITY.md §5 |

## 守ること
- デザインの方向性（配色・画風・レイアウトの大きな変更）は、ユーザーが採用を決めてから実装する。
- 論理14pxを機械的に18pxへ変えない。実際の画面で測ってから判断する。
- Accessibility を理由に既存のデザインを勝手に変えない。測定結果と案を示す。
- `project.godot` の表示設定・入力設定（ゲームパッド）は、ユーザーの判断なしに変えない。
- タイトル画面・ボスの部屋の見た目は Codex の担当。

## 終わる前
- 日本語・英語の両方、1280×720以外のウィンドウでも実際の画面を確かめる。
- [REVIEW_CHECKLIST.md](../../../docs/quality/REVIEW_CHECKLIST.md) のリスト A・D・G を埋める（タイトルなら E も）。
