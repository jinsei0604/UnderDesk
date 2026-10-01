# ボスごとの専用戦闘背景

このフォルダは、ボスごとの専用戦闘背景を置く場所です。フォルダ名は boss_id（`RBMVisualAssets.APPEARANCES` の値）です。

| フォルダ | ボス |
|---|---|
| `slime/` | スライム |
| `wolf/` | 狼 |
| `knight/` | 騎士 |
| `dragon/` | 竜 |
| `ghost/` | 幽霊 |
| `golem/` | ゴーレム |
| `musha/` | 朽ちた機械武者 |
| `astronaut/` | 宇宙飛行士 |

## 追加の手順（例: 朽ちた機械武者）

1. 画像を `musha/background.png` という名前で置きます。
2. Godot エディタを一度開いて、画像を取り込みます（`.import` ができます）。

これだけで、TEST BATTLE・クリアチェック・挑戦（ホーム画面のモニターを含む）のすべてで、そのボスの戦闘に自動で使われます。覚醒後も同じ背景です。コードを書き換える必要はありません。

新しいボスを足したときは、その boss_id の名前でフォルダを作り、同じように `background.png` を置きます。

## 特別なパスを使いたいとき（任意）

ファイル名を変えたい、別のフォルダの画像を使いたいなどの場合だけ、`src/bossmaker/visuals/rbm_battle_backgrounds.gd` の `BOSS_BACKGROUNDS` に書きます（例: `"musha": "musha/background_winter.png"`）。書いたものが `background.png` より優先されます。

## 背景の決まり方

1. `BOSS_BACKGROUNDS` の上書き（書いてあれば）
2. `<boss_id>/background.png`
3. Creator で選んだ昼/夜の標準背景（`assets_bossmaker/art/battle_courtyard_*.png`）

ファイルが無い・取り込まれていない・画像として読めない場合は、次の候補を使います。専用背景が無いのは正常な状態で、エラーにはなりません。

- 画像は 1280×720 の画面いっぱいに、縦横比を保ったまま拡大・縮小して表示されます（はみ出た分は切れます）。拡大はぼかさずに行います。標準背景の画像は 1672×941 です。
- 各フォルダの `.gitkeep` は、空のフォルダを Git に残すためだけのファイルです。
