class_name RBMCreatorGuideCharacter
extends Control

## Creator「作成方法を選択」画面の案内役キャラクター。
##
## 正式Idle実装パス（2026-09-03、3回目）: ユーザー提供の正式A〜E差分
## 素材5枚（creator_guide_idle_a/b/c.png=通常/呼吸中間/呼吸最大、
## _d_posture.png=ごく稀な姿勢・重心調整、_e_hand.png=差し出した手の
## 微動、いずれもBODY_NATIVE_SIZEと同一キャンバス・同一座標、手も含めた
## 完全な1枚絵）を使用する。旧A/B/C（前回セッションの試作素材）は今回の
## 正式版で完全に置き換えた——ファイル名は同一（creator_guide_idle_a/b/
## c.png）のため上書きの形で置換し、「どちらが実際に使われているか
## わからない」状態が発生しない。
##
## 実装前の独立検証（最終報告参照、ユーザー提供のverification_report.txt
## の内容とも完全一致を確認済み）: ①5枚とも1067×1475・FORMAT_RGBA8で
## 完全一致②足元（最下端の不透明行）が5枚ともnative y=1359で完全一致
## ③境界の白フリンジ率が5枚とも0.0%（コード側での白色除去/erosion/
## alpha加工/色置換は一切行っていない、提供PNGをそのまま使用）④A基準の
## 差分範囲: B/C=胸元～肩(334,348)-(605,595)、D=腰～コート裾の内側
## (423,559)-(606,755)、E=手のひらの指先のみ(809,401)-(846,421)、いずれも
## 足・脚には一切かかっていない。素材側の問題は見つからなかった——コード
## 側での補正は不要。
##
## 実表示スケール増幅パス（2026-09-03、4回目）: 上記③の差分は素材上には
## 確かに存在するが、実ゲーム表示（rbm_creator_entry.gdのGUIDE_CHARACTER_
## SCALE=0.50倍固定）で見ると輪郭の実移動量がnative換算で1px未満（例:
## Cの肩ラインの平均移動量は実測native約1.3px=画面0.65px、境界を跨がない
## 内部色変化がdiff面積の大半を占めていた）で、nearest-neighbor縮小により
## 事実上消えてしまい「何が変わったか分からない」状態だった。これに対応し、
## tools/_ui_pass_shots/generate_amplified_idle_frames.gd（提供PNGへの
## 上書きではなく、その場で新しい絵を描き起こすのでもなく、各フレーム
## 自身の既存ピクセルだけを対象領域内でローカルに逆写像ワープ——new(x,y)=
## source(x-dx,y-dy)、nearest sample、補間なし、対象領域境界でraised-
## cosine窓関数により変位が厳密に0へ収束し外側と完全に継ぎ目なく一致する
## 設計）で、B/C=肩～胸帯域の垂直方向持ち上げ（B:native2.5px/C:native
## 5.5px）、D=同帯域の水平シフト＋わずかな肩の高さの左右せん断（native
## 3.5px＋tilt2.0px、腰から下・首から上は完全固定）、E=手首を支点とした
## 放射状変位（支点で0、指先へ向かうほど増加、native(3,-3.5)px）を適用した
## 試作B'/C'/D'/E'を生成し、実ゲーム表示サイズでの比較画像・実背景合成
## 画像・境界フリンジ再検証を経て本番採用した。実測した実画面上の移動量:
## B肩ライン平均0.65px（最大1.0px）／C肩ライン平均0.69px（最大5.0px）／
## D胴体左端平均1.08px（最大4.5px）／E指先到達点1.5px。いずれも仕様が
## 求めた「1〜2px、大きくても2〜3px」の範囲内。
##
## この増幅パス実施前、同じ全走査で提供素材そのものの欠陥も発見した:
## creator_guide_idle_b.pngのy=595と、creator_guide_idle_c.pngのy=594-595
## に、胴体の横幅ほぼ全体（440列中421列）が透明になる1〜2行の細い欠落
## （A/D/Eには存在しない、書き出し時のエクスポート由来と推測）があった。
## 新しい絵を描き足すのではなく直近の正常な行をそのまま複製する最も保守的
## な方法で埋めてから増幅ワープを適用した（generate_amplified_idle_
## frames.gd内の_repair_row()参照）。
##
## 全身の連動パス（2026-09-03、5回目）: 上記4回目のB/C/Eは胸・肩／手首
## だけを動かし、袖から下・コート裾・脚は完全静止のままだったため「上半身
## だけ動いて長いコートは静止画」という見え方だった。今回は「呼吸=胸・肩が
## 主動作、袖・コート上部・コート裾は振幅の小さいsecondary motionとして
## 追従する」設計へ拡張し、Dだけは「肩・胴体・骨盤・左右脚まで含めた全身の
## 重心移動（靴位置は完全固定）」として作り直した。手法は4回目と同じ
## backward warp＋raised-cosine窓関数だが、複数の帯域の変位を「単一の
## パスで加算」してから1回だけワープする設計に変更した——帯域ごとに別々の
## _apply_vbands呼び出しへ分けると、y範囲が重なる帯域どうしで後段の呼び
## 出しが前段の結果を上書きしてしまい、重なり領域（B/Cのy:550-640付近）で
## 変位が欠落する継ぎ目が生じるバグを実装中に発見・修正した（generate_
## amplified_idle_frames.gd、単一region・単一bands配列で全帯域を同時に
## 渡す設計に統一、E'の手首＋袖口も同様に_apply_hand_and_cuff()で単一パス
## 化した）。
##
## B/C: 主動作(胸・肩、y中心460・半値幅140)は4回目から変更なし。追従として
## 袖付け根〜コート上部(y中心760・半値幅220)とコート裾(y中心1020・半値幅
## 170)の2帯域を追加し、垂直方向のみ（風になびく横揺れは加えていない）
## 加算——C側の追従振幅をB側より大きくすることで「肩・胸が上がる→コート
## 上部が追従→コート裾がわずかに遅れて形を変える」という遅延の感覚を、
## 静止画の離散切り替えのままB→Cの振幅差だけで表現した。実測（実画面px）:
## コート裾の平均移動量はB=0.07px・C=0.33px（Cのみ、コート裾がBより明確に
## 大きく追従する設計どおり）。
##
## D: 肩(水平シフト+左右せん断、4回目と同帯域)・胴体/骨盤(水平シフト、y
## 中心750・半値幅220)・コート裾(水平シフト+左右せん断、y中心1020・半値幅
## 170)・左右脚（コート裾直下y:920-1140でのみ、支える側の脚はamplitude
## 0.6px・緩める側の脚はamplitude2.6pxという非対称な傾き。脚の変位は
## y>=1140で確実に0となり、足首・靴が並ぶy=1250以降は実測で完全に0——
## 「両足・靴の床上位置は完全固定」を数式レベルで保証）を単一の変位場と
## して合成。実測（実画面px、平均）: 肩1.15px／胴体・骨盤1.26px／コート裾
## 1.39px——肩から裾にかけて緩やかに増加する一貫したカスケードとして
## 全身がつながって見える。
##
## E: 手首を支点とした放射状変位（主動作、4回目から変更なし）に加え、
## 袖口（native y中心480・x中心660、手の変位と同じ向きにnative(1.2,-1.2)
## px）のローカルな追従を追加——支点付近の生地がほんの少しだけ動くことで
## 「手だけが独立して動く」印象を弱めた。
##
## 段階的増幅パス（2026-09-03、6回目）: 5回目時点の実画面px（B/Cコート裾
## 平均0.07px/0.33px等）はまだ実ゲーム動画では認識しづらかったため、
## 「現在版=100%として1.5倍・2倍の2候補を生成し、実ゲーム表示サイズで
## 比較して自然に認識できる最小の方を採用する」という段階的手法（tools/
## _ui_pass_shots/generate_amplified_idle_frames.gd、CANDIDATE_MULTS配列で
## 両方を同時出力）で再調整した。5回目の各局所帯域の変位振幅（chest/
## torso/hem/D各帯域/E手首・袖口）を一律に定数倍しつつ、D脚の左右非対称比
## だけは倍率以上に差を広げ（1.5x: 支える0.7px/緩める4.2px）、加えて
## B/Cのコート裾帯域に左右非対称の重み(x_var、"単純な上下移動は禁止、
## 左右で変化量を変え布の形が変化したように"という要求に対応——時間的な
## 往復要素が無い静止画のため風になびく動きにはならない)を新規追加した。
## 1.5倍・2倍とも実背景合成＋拡大比較画像で目視した結果、両方とも「はっきり
## 動いたと分かる」水準に達しており、より控えめな1.5倍を採用した。採用後の
## 実測（実画面px、平均）: Cチェスト0.99px（最大5.5px）／Cコート裾0.34px／
## D肩1.65px・胴体骨盤1.98px・コート裾2.15px／E手の到達点2.5px。足元
## （native y=1359、全frame一致）・顔髪帯域（diff 0px）・境界フリンジ
## （0.0%）は今回も無変化のまま確認済み。
##
## 横ズレ修正＋通常呼吸のみ再増幅パス（2026-09-03、7回目）: 実GPU動画で
## 「呼吸終端付近でコートの一部が横方向へ一瞬ズレて見える」という報告を
## 受け、A/B/Cの各部位（肩・胸・袖・コート外周・裾）のX方向差分を全走査で
## 調査した結果、原因は6回目で「重なり領域の上書きバグ」を直すために
## chest_band/torso_band/hem_bandを単一の共有region(x:150-820)へ統合した
## 際、主動作chest_bandの適用x範囲が意図せず旧来（x:240-720相当）より
## 広がり、差し出した腕の付け根（x~750-820、native y~460付近でシルエット
## が急激に細くなる境界）まで垂直方向の変位が及んでいたことだった——
## この領域はY方向にシルエット輪郭が急峻に変化するため、純粋な垂直
## シフトのはずが境界のX位置が副産物として大きくジャンプしていた
## （実測: y=460の右袖付け根でA基準からB/Cとも native-6px、呼吸振幅と
## 無関係にB/Cで同一値だったことから、輪郭形状が急変する場所特有の現象と
## 特定）。
##
## 修正の第一段（raised-cosine窓）はchest_bandへX方向の対称な減衰
## (x_center/x_half)を追加したが、腕の付け根を確実に避けようと半値幅を
## 絞るほど、本来動かしたい肩の外側（x~280-350/600-680）まで一緒に
## 減衰してしまい、C胸の平均変位がむしろ縮んでしまう逆効果が判明
## （実測でC胸の平均が前回の0.99画面pxから0.43画面pxへ低下）。左右対称の
## ベル型窓では「危険領域だけを遮断」と「肩全体は満額で動かす」を両立
## できないため、「指定範囲内は常に振幅100%(flat top)、その外側だけ
## taper幅でなめらかに0へ」という台形型の窓関数へ作り直した
## （x_flat_left/x_flat_right/x_taper、chest_bandは有効範囲x:220-680を
## 満額に保ちつつx:680-740でなめらかに0へ、腕の付け根x~750+には一切
## 届かない）。コート裾帯域は先細りのパネル先端（native y~1100-1150）
## 付近で幾何学的にX方向の見かけの変化が過大になっていたため（先端は
## 形状上、わずかな垂直変位でも見かけのX変化が増幅されやすい）、
## half_hを170→130へ縮小して先端部分では変位が0へ収束するよう調整した。
##
## 修正後、通常呼吸A/B/Cのみを対象に再増幅（"通常呼吸そのものがまだ弱い"
## という報告を受け、D/Eは今回一律増幅せず回帰確認のみ、production側の
## D/E資産ファイル自体は今回一切上書きしていない——6回目採用時点のまま、
## 真の意味でのゼロ差分による回帰保証）。前回(6回目)の1.5倍をさらに強め
## た2.0倍相当（6回目の"現在版=100%"基準）を1回で試し、実背景合成・
## 拡大比較・A→B→C→B→Aの復帰シーケンス撮影で確認した結果、「はっきり
## 呼吸が分かる」かつ「大げさではない」水準に達しており、中間候補
## （1.7〜2.0程度）を追加試作する必要はないと判断し、この2.0倍をそのまま
## 採用した。採用後の実測（実画面px、平均）: Cチェスト1.28px（旧0.99px、
## 台形型窓への作り直し後に本来の増幅どおり回復）／Cコート裾0.15px。
## X方向ジャンプの全走査再検証（native8px超を閾値、A→B/A→C）では、
## 台形型窓への変更で新たに肩の付け根付近（native y~546-579）にも同種の
## 大きな測定値が現れたが、これは腕の付け根の実バグ（B/Cで振幅と無関係に
## 同一値が出る）とは異なり、C側でのみ・かつ振幅に応じた値のみで、丸い
## 袖の輪郭が持つ局所的な凸形状（先細りのコート裾先端と同じ「輪郭の
## 尖った/丸まった部分は幾何学的にX方向の見かけの変化が過大になる」性質）
## と判明——拡大画像で直接目視した結果、袖・コート裾・袖口/手首境界の
## いずれも実際の見た目は「布・関節の形が自然に変化した」という範囲に
## 収まっており、破綻や継ぎ目は見られなかった。足元（native y=1359、
## 全frame一致）・顔髪帯域（diff 0px）・境界フリンジ（0.0%）は今回も
## 無変化のまま確認済み。
##
## 実GPU表示スケールでの散らばりノイズ修正＋中間フレーム追加パス
## （2026-09-03、8回目）: 実GPU（`--path . -s <script>`、headlessの
## dummyレンダラーはこの環境では`RenderingServer.frame_post_draw`が
## 永久に発火しない/`--write-movie`が"Parameter t is null"でクラッシュ
## するため、代わりにウィンドウ有りの通常exeで実OpenGL(Intel UHD
## Graphics)レンダリングを使用——`tools/_ui_pass_shots/`の各撮影
## ハーネスは`Godot_v4.7-stable_win64.exe`（`_console`ではない方）を
## 使うこと）でRBMCreatorEntry経由の実表示（GUIDE_CHARACTER_SCALE=0.50、
## 実背景合成）を直接撮影し、A→B・B→C等の遷移直前/直後を比較した結果、
## 前回（7回目）までのネイティブ解像度でのdiff確認（輪郭が連続的に動く
## ことを確認済み）では見えていなかった問題を発見した——実表示スケール
## （ネイティブ→画面が正確に2:1）では、B/Cの差分が輪郭だけでなく上着の
## 内部（縫い目・ハイライト等）にまで「散らばったノイズ」として現れて
## いた（`ab_review.png`等、diffをmagentaで可視化した実画像で確認）。
##
## 【原因】warp関数群（`_apply_vbands`等、tools/_ui_pass_shots/
## generate_amplified_idle_frames.gd）がdx_i/dy_iを「最も近い整数」へ
## 丸めていたため、Y方向へ連続的に変化するfalloff値が奇数/偶数どちらの
## 整数に丸まるかが行ごとに不規則に入れ替わっていた。GUIDE_CHARACTER_
## SCALE=0.50の最近傍縮小では、画面へ実際に出力されるのはネイティブの
## 偶数行/偶数列だけであり、ある画面画素の参照元ネイティブ行
## (2*y_screen-dy_i)はdy_iの偶奇でネイティブの偶数行/奇数行のどちらを
## 見るかが決まる——dy_iが行ごとに不規則に偶数/奇数を行き来すると、
## 隣接する画面画素が参照するネイティブ行の偶奇も不規則に入れ替わり、
## 実在する細かい線画差分（偶数行と奇数行で微妙に異なる縫い目等）を
## 拾ってしまい「合板全体がちらつくノイズ」に見えていた。
##
## 【修正】dx_i/dy_iを「最も近い整数」ではなく「最も近い偶数（=表示
## スケール0.50の逆数である2の倍数）」へ丸めるよう統一した
## （`_round_display_aligned`）。これにより画面画素の参照元は常に同じ
## 偶奇のネイティブ行/列に固定され、「奇数/偶数どちらを見るか運任せ」
## という散らばりノイズの発生源を構造的に排除した。B/C/D/Eの4枚を
## この丸め方式で再生成し、実GPU screenshotのbefore/after差分で
## 散らばりノイズが明確に減少したことを確認した（動き幅自体は7回目の
## 2.0倍のまま変更していない——§16「動き幅を戻さない」の方針を維持）。
## 効果の直接検証（使い捨てスクリプトで実施、確認後削除）: 同一ソース・
## 同一振幅(B、chest 2.5*2.0等)のまま丸め方式だけを「最も近い整数」→
## 「最も近い偶数」へ切り替え、A基準の差分を「ネイティブ2px毎に1点
## サンプル」（GUIDE_CHARACTER_SCALE=0.50のnearest-neighbor縮小と同じ
## 条件）で数えたところ、78649px→61191px（約22%減）——丸め方式の変更
## だけで実際に画面へ出力される差分ノイズが有意に減ることを直接確認した。
##
## 【中間フレーム追加（§10-12「3枚だけで足りるか再評価」への対応）】
## 呼吸A→B→C→B→Aを、各遷移1回の全振幅スワップ（4段階）から、
## A→AB→B→BC→C→BC→B→AB→A（8段階、実体テクスチャはA/AB/B/BC/Cの
## 5枚）へ拡張した。中間フレームAB/BCは新しい絵を描き起こすのではなく、
## 既存のwarpパイプラインを流用——AB'はB自身の素材(b_src、実際の
## 手描き原画)を「Bの最終振幅の半分」でwarp、BC'はC自身の素材(c_src)を
## 「B・C振幅の中間値」でwarpするだけで生成した（新規絵・クロス
## フェード/ブレンドは一切行わない、常に単一の既存ソース画像からの
## 離散warpのみ——ドット絵として破綻しないための既存方針を維持）。
## 8段階化により1回のtexture切り替えあたりの見た目の変化量が旧来の
## 約半分になり、散らばりノイズの絶対量も半減する（振幅が半分になれば
## 丸め誤差の総量も概ね半分になるため）。
##
## 【タイミング再設計（§7-9「動きが遅い」への対応）】合計周期を
## 4.0秒→約2.95秒へ短縮しつつ、単純な一律高速化はしていない——8段階化と
## セットで実施し、各段の保持時間は0.30〜0.70秒に収めた（最長のA=0.70秒
## でも「一呼吸の合間の一息」程度、最短の遷移段=0.30秒は「今まさに
## 動いている」ことが視認できる最小限の長さ、という両案（3枚のまま
## 高速化するだけの案／中間フレームを足す案）を実際に比較した結果、
## 8段階化の方が「散らばりノイズの絶対量も減る」という追加の利点を
## 持つため採用した）。
##
## Idle構成（1つのCharacterBody TextureRectのtextureを丸ごと差し替える
## だけ、scale/rotation/Tween補間/Shader変形は一切使わない）:
## ①通常呼吸: A→AB→B→BC→C→BC→B→AB→(ループ)を常時実行。
## ②姿勢調整D: 8〜14秒のランダム間隔で、呼吸サイクルがちょうどAへ戻った
##   自然なタイミングでのみ発生——B/C表示中に割り込むことはない。A(束の間
##   保持)→D(短時間保持)→A(束の間保持)→通常呼吸再開、という形。
## ③手の微動E: 10〜18秒のランダム間隔で、同じく呼吸がAへ戻った自然な
##   タイミングでのみ発生。
## ④D/Eは同時発生しない・互いに直接遷移しない——両方とも「一度Aへ戻る」
##   ことでしか始まらない共通ゲート（_special_active==0 かつ 呼吸段が
##   ちょうどAの、開始から最低0.3秒経過した時点）を通るため、構造的に
##   D→E/E→Dの直接遷移や同時発生が起こり得ない設計にした。
##
## まばたきとの独立性: まばたき（瞼オーバーレイ）は_next_blink_time
## （3-6秒のランダム間隔）で完全に独立して駆動されており、呼吸・D・Eの
## いずれとも同期しない（同じ_elapsedを参照するだけで、判定ロジック自体は
## 完全に分離）。「毎回呼吸3回目で瞬きして...」のような機械的パターンには
## ならない——4つ全てが独立したランダム/固定周期のタイマーで駆動される。
##
## §16（前回セッション、まだ有効な調査結果）: 体全体のscale/キャラ全体
## rotation/手のrotationは、ドット絵をnearest-neighborで小さな表示scale
## （実機で約0.50倍）のまま連続的に変形させる実装だった——静止したドット
## 絵の一部だけを差し替える方式ではなく、1枚絵全体をサブピクセル単位で
## 連続変形させていたため「AI生成映像のように滲む」症状になっていた。
## 今回のIdle実装は全て離散フレーム切り替えのみ（補間なし）のため、この
## 問題を再現しない。
##
## 白フリンジ／背景黒帯 修正パス（2026-09-03、1回目）: まばたきの瞼は、
## 単色ColorRectの矩形塗りつぶしから、キャラクター自身の既存ピクセルだけ
## を使った「閉じ目の実形状パッチ」テクスチャへ変更済み（無改修のまま
## 維持）。表示は「固定サイズのTextureRect」を「高さが0→フルへ育つ
## clip_contents付きControl」で覆う方式。
##
## RBMTitleEffects（このプロジェクト唯一の既存アニメーション実装）と
## 同じ設計方針を踏襲する:
## ①起動時に固定Node数だけ生成し、_process中のNode生成/破棄/Texture生成
## /画像加工は一切行わない——A〜E全てのテクスチャは_build()で一度だけ
## load()し、以降は_process()内で既存TextureRectの.texture参照を
## 差し替えるだけ。
## ②is_visible_in_tree()がfalseの間は_process自体を早期returnし、非表示中は
## 計算もドリフトも一切発生させない。
## ③randf_rangeによる緩やかな非同期化（まばたき/D/Eの各スケジュールに使用）。

## ソース画像のネイティブ解像度（等倍配置の基準）。実際の画面表示サイズは
## 呼び出し元（RBMCreatorEntry）がこのNode自身のscaleを設定して一括縮小
## する——子Node自身の座標は常にこのネイティブピクセル空間のまま持つ
## ことで、素材を画像編集ソフトで確認した座標をそのままコードへ転記できる。
const BODY_NATIVE_SIZE := Vector2(1067.0, 1475.0)

## 呼吸Idle差分5枚（A=通常、AB=A→B中間、B=吸気中、BC=B→C中間、
## C=吸気最大）。手も含めた完全な1枚絵——同一キャンバス・同一座標。
## AB/BCは新規に描き起こした絵ではなく、B/C自身の素材を「最終振幅の
## 半分」「B/Cの中間振幅」でwarpしただけの中間キーフレーム（8回目
## セッション、§10-12「中間フレーム追加」を実施——詳細は下記コメント参照）。
const IDLE_TEXTURE_A_PATH := "res://assets_bossmaker/art/creator_guide_idle_a.png"
const IDLE_TEXTURE_AB_PATH := "res://assets_bossmaker/art/creator_guide_idle_ab.png"
const IDLE_TEXTURE_B_PATH := "res://assets_bossmaker/art/creator_guide_idle_b.png"
const IDLE_TEXTURE_BC_PATH := "res://assets_bossmaker/art/creator_guide_idle_bc.png"
const IDLE_TEXTURE_C_PATH := "res://assets_bossmaker/art/creator_guide_idle_c.png"
## 姿勢調整D・手の微動E（いずれも通常の呼吸ループには含めない、単独の
## 特殊Idleイベント専用テクスチャ）。
const IDLE_TEXTURE_D_PATH := "res://assets_bossmaker/art/creator_guide_idle_d_posture.png"
const IDLE_TEXTURE_E_PATH := "res://assets_bossmaker/art/creator_guide_idle_e_hand.png"

## A→D中間フレーム「AD」（9回目セッション、緊急修正②「謎の横移動」
## 対応）。Dの絵自体（肩・胴体骨盤・コート裾が同方向へ一貫して滑らかに
## 増加するカスケード、足元は完全固定）は正当な体重移動として確認済み
## だったが、AとDの間に中間フレームが1枚も無く単一のtexture差し替え
## （1描画フレームで即座に全身が数px動く）で表示されていたため、実際の
## 変位量は小さい（実画面px平均で肩1.65px/胴体骨盤1.98px/コート裾
## 2.15px）にもかかわらず「自然な体重移動」ではなく「スプライトが
## 瞬間移動した」ように見える原因になっていたと判断した。新しい絵は
## 描き起こさず、既存のwarpパイプライン（D生成と同一の_apply_full_
## body_warp・同一の帯域定義）をD自身のソース画像へ適用し、D本番の
## 50%の変位量でwarpしたAD1枚だけを追加した
## （tools/_ui_pass_shots/generate_ad_intermediate_frame.gd）。
## A→AD→D→AD→Aという4段階遷移にすることで、瞬間移動に見えていた
## 一回のジャンプを2回の半分幅ジャンプへ分割する——Dの絵自体・
## D_HOLD_SEC・D_MIN/MAX_INTERVAL_SEC・呼吸サイクル側は一切変更しない。
const IDLE_TEXTURE_AD_PATH := "res://assets_bossmaker/art/creator_guide_idle_ad.png"

## A→AB→B→BC→C→BC→B→AB→(ループでA)の順を、_idle_textures配列
## （[A,AB,B,BC,C]）への添字で表す。AB/BCはそれぞれ上り/下りの両方で
## 同じtextureを再利用する（不要な二重ロードを避ける、旧・Bの2回参照と
## 同じ考え方）。8段階に分けたことで、1回のtexture切り替えあたりの
## 見た目の変化量が旧・4段階（A→B→C→B）のときの約半分になり、
## 「大きな一回の全振幅スワップ」に伴うちらつきが緩和される
## （8回目セッション§10-12参照）。
const IDLE_SEQUENCE_INDICES: Array[int] = [0, 1, 2, 3, 4, 3, 2, 1]

## _idle_textures配列内でのD/E/ADの添字（A=0,AB=1,B=2,BC=3,C=4に続けて格納）。
const IDLE_TEXTURE_D_INDEX := 5
const IDLE_TEXTURE_E_INDEX := 6
const IDLE_TEXTURE_AD_INDEX := 7

## 各段の保持時間（秒）。合計約2.95秒——8回目セッションで4.0秒から短縮
## した（§7-9「動きが遅い」への対応）。単純な一律高速化ではなく、
## 8段階化とセットで実施——Aと吸気ピークC周辺だけをわずかに長く保持し
## （「止まる」感を完全には無くさない）、それ以外の遷移段（AB/B/BC）は
## いずれも0.30秒前後の短い保持にとどめることで、「長時間静止してから
## 一気に切り替わる」印象を解消しつつ「常時せわしなく動き続ける」ことも
## 避けた。
const IDLE_FRAME_DURATIONS: Array[float] = [0.70, 0.30, 0.30, 0.30, 0.45, 0.30, 0.30, 0.30]

# --- 姿勢調整D（§4、通常呼吸には含まれない単独の特殊Idle） ---
const D_MIN_INTERVAL_SEC := 8.0
const D_MAX_INTERVAL_SEC := 14.0
const D_HOLD_SEC := 1.3

## AD中間フレームの保持時間（9回目セッション、緊急修正②）。A/D本体の
## 保持時間（0.70秒/1.3秒）よりずっと短く、「今まさに動いている」ことが
## 見える最小限の長さ——8回目セッションでAB/BCの遷移段に採用した
## 0.30秒前後という考え方をAD/DAにもそのまま踏襲した。
const AD_TRANSITION_HOLD_SEC := 0.16

# --- 手の微動E（§5、通常呼吸には含まれない単独の特殊Idle） ---
const E_MIN_INTERVAL_SEC := 10.0
const E_MAX_INTERVAL_SEC := 18.0
const E_HOLD_SEC := 1.3

## D/Eが発火してよいのは、呼吸サイクルがちょうどA（段0）に戻り、かつその
## Aへ切り替わってから最低この秒数が経過した後だけ——特殊Idle終了直後に
## 即座に次の特殊Idleへ飛び、Aが実質0秒しか見えない事態を防ぐ（§6の
## 「D発生中にE...へ直接遷移させない、必ず一度Aへ戻る」を、Aが実際に
## 目に見える形で保証する）。
const MIN_A_HOLD_BEFORE_SPECIAL_SEC := 0.3

## 目のバウンディングボックス（BODY_NATIVE_SIZE座標系、実測値）。呼吸/D/
## Eいずれの差分も目の周辺ピクセルは不変（各フレームの差分bboxが目の
## 座標と重ならないことを実装前確認で検証済み）のため、この座標は全段
## 共通のまま使い回せる。
const EYE_L_RECT := Rect2(445.0, 255.0, 42.0, 35.0)
const EYE_R_RECT := Rect2(522.0, 255.0, 40.0, 32.0)

## 頭・首の連動パス（2026-09-03、11回目）で追加した頭部帯域により、
## 目自体のピクセルも各フレームごとにわずかに動くようになったため、瞼
## パッチ（固定位置のオーバーレイ）を目の実位置へ追従させるオフセット。
## _idle_textures配列と同じ添字（A=0,AB=1,B=2,BC=3,C=4,D=5,E=6,AD=7）で
## 引く。値は実ピクセルのクロスコリレーション（a.pngを基準に、各frameの
## 目bbox領域が最も一致する平行移動量を総当たりで探索）で直接測定した
## ものをそのまま使用——falloff計算からの理論値ではなく実測値（誤差0、
## いずれも完全一致するシフト量が見つかった）。左右の目で同じ値になる
## ことも確認済み（頭は左右一体で動くため）。
## A/AB/AD/E=(0,0)（頭がまだ動いていない、またはEは頭を一切動かさない
## 設計のため）、B/BC/C=(0,-2)（呼吸で頭がnative2px上へ）、D=(2,0)
## （骨盤→肩の重心移動が頭まで延長され、native2px右へ）。
const EYE_OFFSET_BY_TEXTURE_INDEX: Array[Vector2] = [
	Vector2(0.0, 0.0),   # 0: A
	Vector2(0.0, 0.0),   # 1: AB
	Vector2(0.0, -2.0),  # 2: B
	Vector2(0.0, -2.0),  # 3: BC
	Vector2(0.0, -2.0),  # 4: C
	Vector2(2.0, 0.0),   # 5: D
	Vector2(0.0, 0.0),   # 6: E
	Vector2(0.0, 0.0),   # 7: AD
]

## 閉じ目パッチ（generate_eyelid_textures.gdで生成、新規イラストなし
## ——キャラクター自身の既存ピクセルのみを使用）。
const EYELID_TEXTURE_LEFT_PATH := "res://assets_bossmaker/art/creator_guide_character_eyelid_left.png"
const EYELID_TEXTURE_RIGHT_PATH := "res://assets_bossmaker/art/creator_guide_character_eyelid_right.png"

# --- まばたき ---
const BLINK_MIN_INTERVAL_SEC := 3.0
const BLINK_MAX_INTERVAL_SEC := 6.0
const BLINK_DURATION_SEC := 0.18

## 特殊Idleの種別。NONE=通常呼吸中、POSTURE=D表示中、HAND=E表示中。
enum SpecialIdle { NONE, POSTURE, HAND }

var _body: TextureRect
var _idle_textures: Array[Texture2D] = []
var _idle_stage_index := -1  # 未初期化を表す番兵。_process初回で必ず設定される。

## 通常呼吸サイクルの起点（_elapsedからのオフセット）。特殊Idleから
## 復帰するたびにここを更新し、必ずAから呼吸が再開するようにする。
var _breath_cycle_start := 0.0

var _special_active := SpecialIdle.NONE
var _special_end_time := 0.0
var _next_d_time := 0.0
var _next_e_time := 0.0

## 特殊Idleの多段階シーケンス（9回目セッション、緊急修正②）。POSTURE(D)
## はA→AD→D→AD→Aの4段階、HAND(E)は従来通りA→E→Aの単一段階のまま
## （E↔AはE自身の変位量が小さく局所的なため、本セッションの実測比較
## （torso_A_vs_E.png、胴体以下は無変化）で瞬間移動には見えないと判断し、
## 中間フレームを追加していない）。各要素は{texture_index:int,
## hold_sec:float}。
var _special_steps: Array = []
var _special_step_index := 0

var _eye_l: Control
var _eye_r: Control

## 現在_body.textureへ設定されている_idle_textures添字。瞼パッチの
## 位置を、目の実位置（頭・首の連動で各frameごとに動く）へ追従させる
## ため、_set_body_texture()経由でのみ更新する（直接_body.texture=…を
## 書かない、11回目セッションで新規導入）。
var _current_texture_index := 0

var _elapsed := 0.0
var _next_blink_time := 0.0

func _ready() -> void:
	_build()
	_next_blink_time = randf_range(BLINK_MIN_INTERVAL_SEC, BLINK_MAX_INTERVAL_SEC)
	_next_d_time = randf_range(D_MIN_INTERVAL_SEC, D_MAX_INTERVAL_SEC)
	_next_e_time = randf_range(E_MIN_INTERVAL_SEC, E_MAX_INTERVAL_SEC)
	set_process(true)

func _build() -> void:
	name = "GuideCharacter"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = BODY_NATIVE_SIZE

	_idle_textures = [
		load(IDLE_TEXTURE_A_PATH),
		load(IDLE_TEXTURE_AB_PATH),
		load(IDLE_TEXTURE_B_PATH),
		load(IDLE_TEXTURE_BC_PATH),
		load(IDLE_TEXTURE_C_PATH),
		load(IDLE_TEXTURE_D_PATH),
		load(IDLE_TEXTURE_E_PATH),
		load(IDLE_TEXTURE_AD_PATH),
	]

	_body = TextureRect.new()
	_body.name = "CharacterBody"
	_body.texture = _idle_textures[0]
	_current_texture_index = 0  # A。EYE_OFFSET_BY_TEXTURE_INDEX[0]=(0,0)
	# なので、_build_eyelid()が設定する既定位置のままで一致している
	# （_eye_l/_eye_rはまだ生成前のため、ここでは_set_body_texture()を
	# 呼ばずcurrent_texture_indexの初期値合わせのみ行う）。
	_body.position = Vector2.ZERO
	_body.size = BODY_NATIVE_SIZE
	_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_body.stretch_mode = TextureRect.STRETCH_SCALE
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)

	_eye_l = _build_eyelid(EYE_L_RECT, EYELID_TEXTURE_LEFT_PATH, "EyelidLeft")
	_eye_r = _build_eyelid(EYE_R_RECT, EYELID_TEXTURE_RIGHT_PATH, "EyelidRight")

## 目の実形状に沿った閉じ目パッチテクスチャを「上から徐々に露出させる」
## 方式。テクスチャ自体（子のTextureRect）は常に等倍・固定位置のまま
## ——伸縮させると滲むため、代わりに親（返り値のControl、clip_contents=
## true）の高さを0→rect.size.yへ動かしてクリップ量を変える。返り値は
## 「高さ0=開眼、rect.size.yまで伸ばすと完全に閉じる」という契約を持つ
## Control。
func _build_eyelid(rect: Rect2, texture_path: String, node_name: String) -> Control:
	var clip := Control.new()
	clip.name = node_name
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.clip_contents = true
	clip.position = rect.position
	clip.size = Vector2(rect.size.x, 0.0)
	add_child(clip)

	var patch := TextureRect.new()
	patch.name = "Patch"
	patch.texture = load(texture_path)
	patch.position = Vector2.ZERO
	patch.size = rect.size
	patch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	patch.stretch_mode = TextureRect.STRETCH_SCALE
	patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(patch)
	return clip

## _body.textureとEYE_OFFSET_BY_TEXTURE_INDEXに基づく瞼位置を、必ず
## 同じタイミングで一緒に更新する唯一の入口（11回目セッション、頭・首の
## 連動パスで新規導入）。呼吸/D/Eいずれの遷移も直接_body.texture=…を
## 書かずこの関数を経由することで、「頭の位置は変わったが瞼パッチだけ
## 古い位置に取り残される」事故を構造的に防ぐ。
func _set_body_texture(index: int) -> void:
	_current_texture_index = index
	_body.texture = _idle_textures[index]
	var offset: Vector2 = EYE_OFFSET_BY_TEXTURE_INDEX[index]
	_eye_l.position = EYE_L_RECT.position + offset
	_eye_r.position = EYE_R_RECT.position + offset

func _process(delta: float) -> void:
	# 非表示中（他STEPやTOP画面にいる間）は計算自体を止める——RBMTitle
	# Effects._process()と全く同じガード。
	if not is_visible_in_tree():
		return
	_elapsed += delta

	if _special_active == SpecialIdle.NONE:
		_process_normal_breathing()
	else:
		_process_special_idle()

	# まばたき: 三角波で開→半目→閉→半目→開。既定（ブロック外）は
	# 完全開放(height=0)。目周辺の矩形だけを差し替えるため、顔・髪・鼻・
	# 口・頭の形は一切変化しない。呼吸/D/Eいずれのタイマーとも完全に別の
	# 変数（_next_blink_time、3-6秒のランダム間隔）で駆動されており、
	# 同期しない。
	_eye_l.size.y = _eyelid_height(EYE_L_RECT.size.y)
	_eye_r.size.y = _eyelid_height(EYE_R_RECT.size.y)
	if _elapsed >= _next_blink_time + BLINK_DURATION_SEC:
		_next_blink_time = _elapsed + randf_range(BLINK_MIN_INTERVAL_SEC, BLINK_MAX_INTERVAL_SEC)

## 通常呼吸中の処理。A→B→C→Bのどの段にいるかを更新しつつ、ちょうどA
## （段0）に戻っていて、かつそのAへ切り替わってから最低MIN_A_HOLD_
## BEFORE_SPECIAL_SEC秒が経過している場合のみ、D/Eの発火可否を判定する。
func _process_normal_breathing() -> void:
	var t := _elapsed - _breath_cycle_start
	var stage_index := _current_idle_stage_index(t)

	if stage_index == 0 and t >= MIN_A_HOLD_BEFORE_SPECIAL_SEC:
		if _elapsed >= _next_d_time:
			# A→AD→D→AD→A（9回目セッション、緊急修正②）。Dの絵自体・
			# D_HOLD_SECは変更せず、瞬間切り替えに見えていたA↔Dの間に
			# 半分振幅の中間フレームを挟むだけ。
			_start_special_sequence(SpecialIdle.POSTURE, [
				{"texture_index": IDLE_TEXTURE_AD_INDEX, "hold_sec": AD_TRANSITION_HOLD_SEC},
				{"texture_index": IDLE_TEXTURE_D_INDEX, "hold_sec": D_HOLD_SEC},
				{"texture_index": IDLE_TEXTURE_AD_INDEX, "hold_sec": AD_TRANSITION_HOLD_SEC},
			])
			_next_d_time = _elapsed + randf_range(D_MIN_INTERVAL_SEC, D_MAX_INTERVAL_SEC)
			return
		elif _elapsed >= _next_e_time:
			# E↔Aは本セッションの実測比較（torso_A_vs_E.png、胴体以下は
			# 無変化）で瞬間移動には見えないと判断し、単一段階のまま。
			_start_special_sequence(SpecialIdle.HAND, [
				{"texture_index": IDLE_TEXTURE_E_INDEX, "hold_sec": E_HOLD_SEC},
			])
			_next_e_time = _elapsed + randf_range(E_MIN_INTERVAL_SEC, E_MAX_INTERVAL_SEC)
			return

	if stage_index != _idle_stage_index:
		_idle_stage_index = stage_index
		_set_body_texture(IDLE_SEQUENCE_INDICES[stage_index])

func _start_special_sequence(kind: SpecialIdle, steps: Array) -> void:
	_special_active = kind
	_special_steps = steps
	_special_step_index = 0
	_special_end_time = _elapsed + float(steps[0]["hold_sec"])
	_set_body_texture(int(steps[0]["texture_index"]))

## 特殊Idle（D/E）表示中の処理。現在の段の保持時間が終わったら、次の段が
## あればそれへ進み（例: AD→D、D→AD）、無ければ通常呼吸へ戻り、呼吸
## サイクルを必ずAから再開させる（_breath_cycle_startを今この瞬間へ
## リセットするため、次の_process呼び出しで段0=Aが即座に選ばれる）。
func _process_special_idle() -> void:
	if _elapsed < _special_end_time:
		return
	_special_step_index += 1
	if _special_step_index >= _special_steps.size():
		_special_active = SpecialIdle.NONE
		_special_steps = []
		_breath_cycle_start = _elapsed
		_idle_stage_index = 0
		_set_body_texture(0)
		return
	var step: Dictionary = _special_steps[_special_step_index]
	_special_end_time = _elapsed + float(step["hold_sec"])
	_set_body_texture(int(step["texture_index"]))

## _elapsedをIDLE_FRAME_DURATIONSの合計（1呼吸の周期）で割った余りから、
## 現在どの段（IDLE_SEQUENCE_INDICESの添字）にいるかを求める。
func _current_idle_stage_index(t_in: float) -> int:
	var total := 0.0
	for d in IDLE_FRAME_DURATIONS:
		total += d
	var t := fmod(t_in, total)
	var acc := 0.0
	for i in range(IDLE_FRAME_DURATIONS.size()):
		acc += IDLE_FRAME_DURATIONS[i]
		if t < acc:
			return i
	return IDLE_FRAME_DURATIONS.size() - 1

func _eyelid_height(full_height: float) -> float:
	if _elapsed < _next_blink_time or _elapsed >= _next_blink_time + BLINK_DURATION_SEC:
		return 0.0
	var t := (_elapsed - _next_blink_time) / BLINK_DURATION_SEC
	var coverage := 1.0 - absf(t * 2.0 - 1.0)  # 三角波 0→1→0（開→閉→開）
	return full_height * coverage
