/// `partial_markdown_regression_test.dart` のフィクスチャ。
///
/// サンプル画面 (`example/lib/src/sample_reply.dart`) の `sampleReply` を
/// そのまま転記する。パッケージ側のテストは example に依存できないので、
/// 同じ文字列をここへ複製する (値そのものは変えない)。
library;

/// 作り物の返答。見出し・段落・太字・インラインコード・箇条書き・番号リスト・
/// 表・コードブロック・引用・リンクを含む。
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
