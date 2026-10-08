---
name: mc-audio
description: Routes Makers & Challengers sound work to the project quality docs in docs/quality/. Use when adding or changing sound effects, BGM, ducking, mix balance, volume levels, buses, or the timing of attack and UI sounds (効果音・BGM・音量・ミックス). Do not use for visual-only changes.
---

# mc-audio

音の作業で、どの品質文書を読み、最後に何を確かめるかを決める案内。品質の正本は `docs/quality/`。規約の本文はここに書き足さない。

## 始める前
1. [PRO_QUALITY_BIBLE.md](../../../docs/quality/PRO_QUALITY_BIBLE.md) §1 と §6 を確認する。
2. `git status` で、他の未コミット変更と自分の変更を分ける。
3. [AUDIO.md](../../../docs/quality/AUDIO.md) §1 で、今の音の仕組み（`RBMAudio`、同時8音、専用の演出トラック）を確認する。

## 読むもの（作業に関係する章だけ）
| 作業 | 読む |
|---|---|
| 命中と音を合わせる | AUDIO.md §2 |
| 攻撃の大きさと音の差・変化の付け方 | AUDIO.md §3 |
| BGM・バス・ダッキング | AUDIO.md §4 |
| その瞬間に何を聞かせるか | AUDIO.md §6 |
| 大事な音が埋もれる・音割れ | AUDIO.md §7・§8 |
| してはいけないこと | AUDIO.md §5 |

## 守ること
- SE は演出の時間（`age`）の命中時刻に合わせて鳴らす。固定のタイマーで別に鳴らさない。
- 承認済みの専用の演出トラックをランダム化しない。
- ゲーム内の音量を録画用に変えない。
- 曲の方向性はユーザーが決める。

## 終わる前
- 実際のゲームの音量で、映像と一緒に聞いて確かめる。音が一番重なる場面で、マスターが0dBを超えないか測る。
- [REVIEW_CHECKLIST.md](../../../docs/quality/REVIEW_CHECKLIST.md) のリスト A・F を埋める。
- 音の良し悪しはユーザーが聞いて決める。
