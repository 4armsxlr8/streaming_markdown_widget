# streaming_markdown_widget

AI チャットの返答欄のように、少しずつ届く Markdown を整形したまま 1 文字ずつ出現させる Widget を再現する Flutter サンプルです。

## 起動方法

```sh
flutter run -d "iPhone 16"
```

```sh
flutter run -d <起動中の Android エミュレータ>
```

確認デバイスは iOS シミュレータと Android で、macOS・Web は対象外です。

## 再現範囲

- 起動すると、作り物の返答が自動で流れ始めます。まず思考の枠が現れ、思考の文が流れ終わると返答の吹き出しに切り替わります。
- 届いた文字は 1 文字ずつ出現します。基準の速さは 40 文字/秒 (25ms 間隔) で、各文字の不透明度は出現を始めてから 300ms で 0 から 1 になります。
- 追いつき: まだ出現していない残りが遅れの上限 24 文字 (600ms 分) を超えると出現の速さを上げ、600ms 以内に残りを上限以下へ戻します。
- 早送り: 受信完了の時点でまだ出現していない残りは 400ms 以内に出し切ります。
- 書きかけの記法は閉じた形で描きます。途中の太字・斜体・インラインコードは閉じた形で、閉じていないコードフェンスは伸びていくコードブロックとして描かれます。書きかけのリンクはラベルだけの素の文字で描かれ、閉じ括弧が届くとリンクになります。表は区切り行が届くまで見出し行も出ず、届いた行から本体が増えます。
- 対応する記法は見出し・段落・太字・斜体・インラインコード・コードブロック・箇条書き・番号リスト・引用・リンク・表です。数式・画像・脚注・打ち消し線・タスクリストは整形されず、記号のままの文字として出ます。引用・リストの中の表とフェンス、CommonMark が強調と認めない形 (前後の空白や記号の並びが flanking の条件を満たさない `**` `*` `__` `_` など) も対象外です。
- 思考の枠: 思考が流れている間は見出し行に「考え中…」の文字の上を光が左から右へ流れます (1.6 秒周期)。本文は既定で 1 行の高さだけ見え、タップすると全部の高さに広がります。思考が終わると見出しが「n 秒考えました」に変わり、本文は 300ms で畳まれます。畳まれた見出し行もタップで開閉できます。
- 受信前 (何も届いていない間) は返答の吹き出しに待機の点 3 つが出ます。
- 「最初から流す」ボタンを押すと、受信中でも受信完了後でも返答を 0 から流し直します。
- 返答が画面の高さを越えて伸びると、読んでいる位置が末尾から 72px 以内なら自動で末尾へ追随します。72px より上へスクロールして離れると追随を止め、読んでいる位置を動かしません。
- 受信中の末尾に印は付きません。返答の文字は選択できません。リンクをタップしても何も起きません。
- 作り物の返答は塊にして届けます。1 塊は既定 4 文字、5 回に 1 回は 8 文字で、届く間隔は基準 125ms の 0.5〜2.0 倍のむらを持たせています (この供給の値はサンプル側の設定で、Widget の挙動ではありません)。供給の乱数に `Random` を渡すと (`ReplyPage(random:)`)、同じ seed なら塊の切れ方と間隔が毎回同じになります (動作確認・テスト用)。
- 見た目の基準値 (色・余白・角丸・文字サイズなど) は、認識合わせ用の HTML モックの CSS から転記しています。

## 仕組み

- `app.dart`: サンプルのルート Widget。`MaterialApp` で `ReplyPage` を表示するだけ。
- `reply_page.dart`: 画面の持ち主。「最初から流す」のたびに世代 (`_generation`) を増やし、その値を `_ReplyFlow` の `Key` にする。Key を変えて古い Element を丸ごと破棄してから作り直すのは、供給と Controller を手で `dispose()` する経路だと、その frame の Ticker の発火が build phase より先に走り、dispose 済み Controller に古い Ticker が触れて例外になるため。供給 (`FakeReplySource`) と `StreamingReplyController` は `_ReplyFlow` が 1 組だけ持ち、生成と同時に供給を始め、破棄時に供給 → Controller の順で破棄する。
- `fake_reply_source.dart`: TDD 対象外の作り物の供給。`Timer` で思考 → 返答の順に塊を `StreamingReplyController.addChunk` へ届ける。1 塊の文字数・むらの間隔は `ReplyTheme` の供給用の定数 (mock.html の供給ループと同じ値) を使う。
- `chunk.dart`: 塊 1 つの型。文字列と印 (`ChunkKind.thinking` / `reply`) だけを持つ、Widget から独立した値。
- `sample_reply.dart`: 起動時に流す既定の思考の文・返答の定数。mock.html の `THINK` / `TEXT` をそのまま転記。
- `streaming_reply_controller.dart`: 返答の Widget の入り口 (`ChangeNotifier`)。思考・返答それぞれに `RevealClock` を 1 つずつ持ち、`addChunk` で塊を受け取り `tick` で時計を進める。塊の到着時刻は、`framesPaused` が true か繰り延べの列 `_deferredArrivals` が空でない (`_mustDefer`) ときだけ `_deferredArrivals` に積んで次の `tick` の `now` を待ち、そうでなければ直近の `tick` の `now` を使う — 止まっている間の `_lastTickNow` は古くなりうるため、それをそのまま到着時刻にすると次のフレームで出現中の残りがまとめて表示済みへ飛んでしまう。返答の最初の塊が届くと思考の残りを早送りし、300ms かけて本文を畳んで (`collapseDuration`) から返答の時計 (`_replyGateOpen`) を開く。
- `reveal_clock.dart`: 1 文字ずつの出現の時計。Widget を知らない純 Dart で、各書記素の出現開始時刻を保持する。追いつき・早送りに切り替わった瞬間の残りから速さを 1 度だけ決めて `_startTimes` に書き込み、以降の tick はそれを観測するだけにするのは、毎 tick の残り (出現するにつれて減っていく) で速さを割り直すと文字ごとの間隔が tick のたびに変わり、加減速して見えてしまうため。1 度で決め切ることで、追いつき中も早送り中も一定の速さに見える。
- `reveal_ticker.dart`: `StreamingReplyController.needsTicks` が true の間だけ `Ticker` を回し、フレームごとに `controller.tick` を呼ぶ薄い Widget。出現中・未出現の文字が無くなれば Ticker を止め、無駄な再描画をしない。`tick` には `SchedulerBinding.currentFrameTimeStamp` (フレームの時刻そのもの) をそのまま渡す — Controller は tick 間の差分 (経過) しか使わないので、Widget 側で 0 始まりの原点を管理する必要が無い。`controller.framesPaused` は、フレームが実際に流れているかどうかの事実を `Ticker` 自身 (`!_ticker.isTicking`) に聞いて立て、`TickerMode` が無効な間・Ticker 自体が止まっている間に届いた塊・受信完了の到着処理を Controller 側で繰り延べさせる。開始・停止のガードは共有関数 `syncTicker` (`revealed_markdown.dart` の Ticker とも共有) が担う。
- `streaming_reply.dart`: 思考の枠と返答の吹き出しを縦に並べる合成 Widget。受信前は待機の点、思考の塊が届けば思考の枠、返答の最初の塊が届けば吹き出しを出す条件をここで判定する。
- `revealed_markdown.dart`: Controller の 1 区分 (思考 or 返答) の `revealedText` を Markdown として (または素の文字として) 描く。前フレームの可視文字列との共通接頭辞より後ろを「今描かれた文字」として出現開始時刻を割り当てる方式で、書きかけの記法のために描かれていなかった文字が描かれた瞬間に一斉に出現を始める挙動もこの仕組みだけで説明できる。出現中の文字だけ 1 文字 (書記素) 1 `TextSpan` にして色のアルファで不透明度を出し、表示済みの区間は 1 つの span にまとめる。画像記法は前処理 (`partial_markdown.dart`) が既に記号のままの素の文字にエスケープ済みなので、ここに画像だけの特別扱いは無い。受信完了 (`complete`) が false → true に切り替わる最初のフレームだけ、今フレームの全可視文字を表示済みとして確定し、書きかけの記法を閉じていた形から受信完了後の生の記号込みの形へ可視文字列の形が変わっても出現し直させない。
- `partial_markdown.dart`: 前処理はパーサーそのものを判定器にする: 素の parse で最後のブロックの種類を特定し、表・フェンスの書きかけだけ行単位で保留する。最後のブロックが表かコードブロックなら記号は一切閉じない。それ以外では残った `**` `*` `__` `_` `` ` `` と書きかけのリンクを候補にし、実際に閉じてから再 parse して strong / em / code / リンクとして消費されたものだけ採用する。画像 `![alt](url)` は `![` を `\!\[` にエスケープし、パーサーに画像にもリンクにもさせず記号のままの文字にする (受信完了後 (`complete: true`) も含め、この前処理だけが唯一常に行われる例外)。それ以外の書きかけの記法は受信完了後は何も落とさず何も閉じない。最後のブロックの行範囲の絞り込みは、末尾からの再 parse 探索ではなく行の形から候補を 1 つ推定し、その 1 候補だけを parse して確かめる (推定が外れた稀なケースは末尾 8 行までの総当たりで探し、それでも見つからなければそのフレームは閉じない)。
- `markdown_heading.dart`: 見出し (`#`〜`######`) を描く。mock の見た目が 2 段階しか無いため、`##` までは h2 相当、`###` 以降は h3 相当のスタイルにする。
- `markdown_paragraph.dart`: 段落を描く。引用の中の段落は呼び出し元が style を差し替えて使う。
- `markdown_list.dart`: 箇条書き・番号リストを描く。行頭の「•」や「1.」は受信した文字ではなくこの Widget 自身が描き、出現の対象にしない。
- `markdown_blockquote.dart`: 引用を描く。中身は段落などのブロック Widget をそのまま包むだけ。
- `markdown_code_block.dart`: コードフェンスを描く。等幅・暗色背景で、シンタックスハイライトとコピーボタンは持たない。
- `markdown_table.dart`: 表を描く。列幅は `IntrinsicColumnWidth` で届いた内容から決まり、表そのものと本体行を揃えるのは前処理 (`partial_markdown.dart`) の役目で、この Widget は渡された行をそのまま並べる。
- `thinking_frame.dart`: 思考の枠。見出し行 (光る「考え中…」または「n 秒考えました」) と本文を持つ。本文の高さは `AnimatedSize` (300ms) で 1 行/全部/0 の間を変え、1 行のときに最新の行 (末尾) を見せるのに `OverflowBox` を `bottomLeft` 揃えで使う — 中身 (`RevealedMarkdown`) には常に自然な複数行の高さで測らせ、外側の `ConstrainedBox` の高さだけを切り詰めることで、出現の状態を持つ `RevealedMarkdown` 自体は 1 行/全部/畳みの間で形を変えずに済む。
- `thinking_shimmer.dart`: 見出し行「考え中…」の光。`ShaderMask` でグラデーションを 1.6 秒周期で左から右へ流す。
- `waiting_dots.dart`: 受信前の待機の点 3 つ。`AnimationController` 1 本を、3 つの点で位相 (0.2 秒ずつ) をずらして使い回す。
- `reply_theme.dart`: 見た目・出現・供給の基準値をまとめて持つ定数の集まり。値は mock.html の確定案の CSS と `cz-mock-script` の供給ループから転記し、直書きの散在を避ける。
- `keys.dart`: テストや動作確認から辿るための `Key`。

テストは `test/` の 9 ファイル + `test/helpers/` の 4 ファイルで構成します。`partial_markdown_test.dart`・`partial_markdown_regression_test.dart` (書きかけの記法の回帰テスト) は前処理と parse の結果を HTML にして比べる純 Dart テスト、`streaming_reply_controller_test.dart`・`reveal_catch_up_test.dart` (追いつきの再発動) は `StreamingReplyController.tick` に `Duration` を直接渡して時計の進み方を検証する純 Dart テストです。`revealed_markdown_test.dart`・`revealed_markdown_plain_test.dart` (AST から Widget への描画と不透明度)・`streaming_reply_test.dart` (思考の枠と返答の吹き出しの合成)・`reply_page_test.dart`・`reply_page_supply_test.dart` (供給の再現性と自動追随。画面全体) は `RevealTicker` 越しにしか時間が進まないため `pumpAndSettle` を使わず、`test/helpers/reveal.dart` の `pumpFrames` で実機の 1 フレーム相当 (16ms) 刻みに進めます。`test/helpers/app.dart` はビュー寸法を固定してサンプルまたは `ReplyPage` を pump し、`test/helpers/page.dart` は供給の乱数を固定した画面と縦スクロール位置の取得を提供し (`reply_page_supply_test.dart` 用)、`test/helpers/reveal.dart` はそれに加えて `RevealedMarkdown` を `RevealTicker` で包んで pump する補助と、描かれた span の不透明度・可視文字列を集める関数を、`test/helpers/markdown_html.dart` は前処理 + parse の結果を HTML にして比べ、生の記号が残っていないか・可視文字列が先頭部分になっているかを機械的に検査する補助 (`partial_markdown_regression_test.dart` 用) を提供します。
