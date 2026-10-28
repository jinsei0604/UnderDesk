# 覚醒SEの由来

外部サービスからの素材追加はない。元プロジェクトの `assets_bossmaker/audio/` にある既存SEを読み込み、合成した低音・ノイズ・ベル音、短い反射音と混ぜた新規WAV。元のWAVは変更していない。

| キャラ | 再利用した元SE（.wav） | 加工の方向 |
|---|---|---|
| 勇者 | fire_cast, fire_burst, fire_move, fire_impact_heavy | 上昇する集炎音、炎の破裂、低い胴鳴り |
| 老執事 | ice_cast, ice_burst | 氷晶の高い倍音、静寂から短く割れる音 |
| 少女ヒーラー | lightning_cast, lightning_burst | 段階的なベル音、雷の立ち上がりと和音の余韻 |
| 侍 | wind_cast, samurai_iai_draw, wind_move, wind_burst | 風の吸い込み、鋭い抜刀音、短い残響 |
| ハンマー使い | boss_move_heavy, hammer_burst, guard_set, boss_impact_mass | 段階的な軋み、重い打撃、低音の余韻 |

48kHz / stereo / PCM16。各人に charge と release の2本。生成時のピークはそれぞれ約−6.2dBFS / −1.31dBFS。表示部品の標準再生ゲインは−9dB。既存Masterバス設定は変更していない。

時間は演出部品が管理する。集中音を静寂の開始時に停止し、解放SE・解放通知・閃光・揺れを同じタイムラインの境界で開始する。ランダムな音の差し替えは行わない。

配布ルート `authoring/make_audio.py` で再生成可能。実行時に `--project <独立プロジェクトのパス>` を渡す。NumPyが必要。生成先はその独立プロジェクト内の `ally_awakening/audio/`。
