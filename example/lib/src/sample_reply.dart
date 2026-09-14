/// The default values for the fake reply (the body text [ReplyPage] runs at
/// launch).
///
/// Transcribed verbatim from `THINK` / `TEXT` in the `cz-mock-script` of
/// mock.html (`#variant=F`).
library;

/// The fake thinking text. Two paragraphs, using no markup.
const String sampleThinking = '''
ユーザーは ListView のカクつきを直したい。原因として多いのは、行の高さがばらばらで毎フレーム計測が走ること、画像の読み込みが重いこと、build が無駄に走ることの 3 つ。

まず builder への置き換えと高さの固定を手順として示し、方法の比較を表にまとめ、最後に DevTools での確認方法を添える。''';

/// The fake reply. Contains headings, paragraphs, bold text, inline code,
/// bullet lists, numbered lists, a table, a code block, a blockquote, and a
/// link.
const String sampleReply = '''
## リストを滑らかにスクロールさせるには

Flutter で長いリストを扱うときは、**画面に見えている行だけを組み立てる** のが基本です。`ListView.builder` を使うと、行は必要になった時点で作られます。

ポイントは次の 3 つです。

- 行の高さをできるだけ揃える
- 画像は `cacheWidth` で縮小して読み込む
- `const` にできる Widget は `const` にする

手順は以下のとおりです。

1. `ListView` を `ListView.builder` に置き換える
2. `itemExtent` か `prototypeItem` で高さを固定する
3. DevTools の Performance で再描画を確認する

高さを固定する方法は次のとおりです。

| 方法 | 効果 | 手間 |
|---|---|---|
| `itemExtent` | 高さの計算が不要になる | 小 |
| `prototypeItem` | 高さを 1 つの Widget から決める | 小 |
| `cacheExtent` の調整 | 先読みの量を変える | 中 |

```dart
ListView.builder(
  itemCount: items.length,
  itemExtent: 72,
  itemBuilder: (context, index) {
    return ItemTile(item: items[index]);
  },
)
```

> 行の高さが揃っていると、スクロール位置の計算が軽くなります。

詳しくは [公式ドキュメント](https://docs.flutter.dev/perf/best-practices) を参照してください。''';
