/// 塊の印: 思考か返答か。
enum ChunkKind {
  /// 思考の塊。
  thinking,

  /// 返答の塊。
  reply,
}

/// 返答の Widget に届く 1 回分の塊。
///
/// 1 回に届く数文字の文字列 ([text]) と、その印 ([kind]) を持つ。文字数は
/// 届き方しだいで、1 文字のことも十数文字のこともある。
class Chunk {
  const Chunk(this.text, {this.kind = ChunkKind.reply});

  /// 塊の文字列。
  final String text;

  /// 塊の印: 思考か返答か。
  final ChunkKind kind;
}
