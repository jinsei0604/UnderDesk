# 外部資料の記録（EXTERNAL_REFERENCES）

Quality System に取り入れた外部の専門知識の出典と、何をどこへ反映したかの記録。
- 外部資料の長文はコピーしない。原則を自分たちの言葉で要約する。画像・動画は転載しない。
- 出典に書いていないことを推測で補わない。確認できなかった内容には **UNVERIFIED** と付ける。
- 「確認」は 2026-10-07 に公開ページを読んで行った。講演は**動画を見ておらず、GDC Vault の概要文だけ**を確認している（講演の中身の細部は UNVERIFIED）。
- 他の文書では、ここのID（例: `[R1]`）で出典を示す。

---

## 1. VFX

| ID | 資料 | 発行元・著者 | 確認状態 | 採用した内容（要約） | 反映先 |
|---|---|---|---|---|---|
| R1 | 「/dev: League's VFX Style Guide」（2017年10月、Riot の公式サイト Nexus の記事。現在は元のURLが転送されるため、Internet Archive の保存版で確認） | Riot Games（Riot Jino = Jin ho Yang、Principal VFX Artist） | 確認済み | VFXの4つの目的: ①ゲームプレイの明快さ ②visual clutter（見た目の雑音）を減らす ③キャラクターのテーマを強める ④Surprise and delight。目的を達成する5つの領域: gameplay・value・color・shape・timing。「見た目の大きさ・強さは、ゲームプレイ上の重要度を表すべき」 | COMBAT_PRESENTATION §5、ART_DIRECTION §6、REVIEW_CHECKLIST B、QUALITY_EVALS D |
| R2 | 上の記事からリンクされた VFX Style Guide 本体（PDF） | Riot Games | **UNVERIFIED**（ダウンロード形式のため開いていない） | 採用していない。下のR3の要約に出てくる個別の決まり（例: 最も明るい白は最重要の技に取っておく、主・副の形、彩度の使い方、短い持続時間）は原典で未確認 | — |
| R3 | 「10 Design Tips from the League of Legends VFX Style Guide」 | VFX Apprentice（二次資料） | 二次資料（原典との一致は **UNVERIFIED**） | 主・副の形を分けて雑音を減らす、値（明暗）・彩度・大きさを技の重要度に合わせる、効果を長く残さない、という考え方の存在を知る手がかりとしてだけ使う。規約の根拠にはR1と自分たちの実測を使う | COMBAT_PRESENTATION §5.4〜§5.7（「UNVERIFIED」と明記） |
| V1 | GDC 2017「Visual Effects Bootcamp: Artistic Principles of VFX」 | Hadidjah Chamberlain（Blizzard）、Jason Keyser（Riot） | 概要文のみ確認 | VFXの芸術的な基礎を、ゲームプレイ上の配慮と合わせて扱うという方針（概要文の範囲）。講演内の個別の原則は **UNVERIFIED** | COMBAT_PRESENTATION §5 |
| V2 | GDC 2018「Visual Effects Bootcamp: Zip! Thwack! Ping! Animation Principles of VFX」 | Michael Lyndon（SideFX） | 概要文のみ確認 | アニメーションの12原則はVFXにも当てはまる（予備動作・タイミング・余韻など）。細部は **UNVERIFIED** | COMBAT_PRESENTATION §5.7、ANIMATION_CRAFT §0 |
| V3 | GDC 2018「Visual Effects Bootcamp: The Thinking Process of Beautiful Design」 | Ryan Woodward（Riot） | 概要文のみ確認 | 2Dアニメーションの設計原則と、音楽のようなタイミングの考え方をVFXに使う（概要文の範囲）。細部は **UNVERIFIED** | ANIMATION_CRAFT §3（参考のみ） |

## 2. Animation

| ID | 資料 | 発行元・著者 | 確認状態 | 採用した内容（要約） | 反映先 |
|---|---|---|---|---|---|
| A1 | GDC 2014 Animation Bootcamp「Fluid and Powerful Animation within Frame Restrictions」（Visual Arts） | Mariel Cartwright（Lab Zero Games、Skullgirls） | 概要文のみ確認 | 2Dゲームで「最も明快で滑らかな動き」と「応答の速いゲームプレイ」を両立させる。強いキーフレーム・予備動作・タイミングが要。パンチ1つを6コマで見せるような少ないコマ数でも原則を伝える | ANIMATION_CRAFT §1〜§3 |
| A2 | GDC China 2014「Powerful and Effective Animation for 2D/3D Games」（Production） | Mariel Cartwright（Lab Zero Games） | 概要文のみ確認 | 2Dゲームのアニメーションはまずゲームプレイに奉仕する。キーフレーム・予備動作・smear（動きのブレの絵）・タイミングを、制約の多い環境で効かせる | ANIMATION_CRAFT §1・§9 |
| A3 | アニメーションの12原則（Frank Thomas、Ollie Johnston『The Illusion of Life: Disney Animation』1981年） | 原典は未読。一覧と要約は Wikipedia「Twelve basic principles of animation」で確認 | 一覧は確認済み（原典の記述は **UNVERIFIED**） | Squash and stretch、Anticipation、Staging、Straight ahead / Pose to pose、Follow through / Overlapping action、Slow in / Slow out、Arc、Secondary action、Timing、Exaggeration、Solid drawing、Appeal。ゲームでは必要なものを選んで使う | ANIMATION_CRAFT 全体 |

## 3. Accessibility（Xbox Accessibility Guidelines、Microsoft Learn）

すべて確認済み（各ページの ms.date は 2022-05-09。XAG 102 のみ 2023-06-08）。

| ID | ページ | 採用した内容（要約） | 反映先 |
|---|---|---|---|
| X101 | XAG 101 Text display | 文字の最小の目安: PC/VRは1080pで18px以上（4Kで36px）。家庭用ゲーム機は1080pで26px。大きさは「本文の高さ」＝最も高いアセンダーから最も低いディセンダーまでの画素数で測る。最小サイズの200%まで拡大できること。対応言語の全文字を含むフォント。行の長さは英語80字・日中韓40字まで、行間1.5 | ACCESSIBILITY §1 |
| X102 | XAG 102 Contrast | 標準の文字・重要な要素は4.5:1以上。大きい文字（PCで1080p時36px以上）と大きな要素は3:1以上。無効状態の文字は3:1以上。高コントラストモードは7:1。背景が一様でない時は最もコントラストが低い部分で測る。ロゴ・純粋な装飾は対象外。色だけで情報を伝えない | ACCESSIBILITY §2 |
| X103 | XAG 103 Additional channels for visual and audio cues | 色だけで情報を表さない。ゲームに必要な情報は形・模様・アイコン・文字のいずれかを併用。押せない状態を灰色だけで示さない | ACCESSIBILITY §3 |
| X117 | XAG 117 Visual distractions and motion settings | 画面揺れ・揺れ動くカメラ・モーションブラーは避けるか、切る設定を用意する。ゲームに必要なもの以外の繰り返しの上下・左右の動きを避ける。文字のある画面の点滅・自動で動く内容は止める・隠す手段を用意する | ACCESSIBILITY §4 |
| X118 | XAG 118 Photosensitivity | 輝度の閃光（輝度10%以上の変化で、暗い側が0.8未満）、赤の閃光（彩度の高い赤 R/(R+G+B)≥0.8、(R−G−B)×320 の変化が20超）、縞模様（コントラスト差10%超）。失敗条件: 約3回/秒を超える、画面の約20%以上を占める、弱い閃光でも長く続く。警告画面より、危険な内容をなくすことを優先する。検査ツールの例: Harding FPA | ACCESSIBILITY §5、COMBAT_PRESENTATION §4.4 |

## 4. Godot 4（公式ドキュメント、表示は Godot Engine 4.7 版）

| ID | ページ | 採用した内容（要約） | 反映先 |
|---|---|---|---|
| GD1 | Multiple resolutions | Stretch Mode（disabled／canvas_items／viewport）。canvas_items では画像の画素と画面の画素が1対1でなくなり、拡大のむらが出うる。Stretch Aspect の keep は黒帯を付ける。Stretch Scale Mode（Godot 4.2以降）: fractional は任意の倍率、integer は倍率を整数へ切り捨て、残りは黒帯になり、画素の不均一な拡大を防ぐ。ドット絵向けの推奨例は基準解像度640×360・viewport・integer。全画面は Fullscreen より Exclusive Fullscreen を推奨（Windowsでは Fullscreen は下端に1pxの線が残る） | UI_UX §10.1 |
| GD2 | Window クラス（Mode） | Windowed／Maximized／Fullscreen（複数ウィンドウ対応、表示モードは変えない）／Exclusive Fullscreen（1画面1ウィンドウ、負荷が少ない）。Windowsでは全画面の切り替えで一瞬暗くなることがある、Exclusive Fullscreen は録画ソフトで撮れない場合がある | UI_UX §10.1 |
| GD3 | Audio buses | 0dBがデジタル音声の最大。マスターバスの出力が0dBを超えないようにミックスを組むことでクリップ（音割れ）を避ける | AUDIO §8 |

## 5. Agent Skills

| ID | 資料 | 採用した内容（要約） | 反映先 |
|---|---|---|---|
| S1 | Anthropic「Agent Skills」概要（platform.claude.com） | SKILL.md の frontmatter は `name`（64字まで、英小文字・数字・ハイフン、"anthropic"・"claude" を含めない）と `description`（1024字まで、何をするかと「いつ使うか」の両方）。段階的な読み込み: 起動時は name と description だけ（約100トークン）、使う時に本文（5kトークン未満が目安）、参照ファイルは必要な時だけ | `.claude/skills/`・`.agents/skills/`、PRO_QUALITY_BIBLE §8 |
| S2 | Anthropic「Skills」（Claude Code のドキュメント） | プロジェクトのSkillは `.claude/skills/<skill-name>/SKILL.md`。一覧では description（＋when_to_use）が1,536字で切られるので、主な用途を先頭に書く。SKILL.md は500行未満に保ち、詳しい資料は別ファイルへ | 同上 |
| S3 | OpenAI「Agent Skills」（Codex。developers.openai.com/codex/skills から learn.chatgpt.com/docs/build-skills へ転送） | Codex は `$CWD/.agents/skills`、`$CWD/../.agents/skills`、`$REPO_ROOT/.agents/skills`、`$HOME/.agents/skills`、`/etc/codex/skills`、同梱の順に探す。name と description が必須。description には「使う時と使わない時」を書き、主な用途と手がかりの語を先頭に置く。一覧に使う量は文脈の2%（不明な時は8,000字）まで。シンボリックリンクのSkillフォルダにも対応 | 同上 |
| S4 | Agent Skills specification（agentskills.io） | name は1〜64字、英小文字・数字・ハイフン、先頭・末尾・連続ハイフン不可、親フォルダ名と一致。description は1〜1024字。本文は500行未満・5,000トークン未満が目安。参照は浅く保つ | 同上 |

---

## 6. 外部資料ではなく、このプロジェクトの判断として書いたもの

次は外部資料の規則ではなく、このゲームの実測・承認済みの演出・ユーザーの決定に基づく。外部資料の権威で裏付けられたものとして扱わない。
- 演出の長さ・揺れのpx・Hit Stopの秒数・UIアニメーションの秒数（COMBAT_PRESENTATION §2・§4、UI_UX §3）: 現在のゲームと1280×720を基準にした目安。
- 性能の予算（PERFORMANCE §1）: 参照機での実測に基づく基準。
- 音のミックスの優先順・マスキング・ヘッドルーム・ダッキング・バリエーション（AUDIO §3・§4・§6〜§8）: ユーザーの指定と一般的なミックスの考え方による。GD3 以外の外部資料では確認していない（**UNVERIFIED**）。
- ART_DIRECTION の【固定】【現状】: ユーザーの決定と、ゲームの調査結果。
