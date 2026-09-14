/// A chunk's kind: thinking or reply.
enum ChunkKind {
  /// A thinking chunk.
  thinking,

  /// A reply chunk.
  reply,
}

/// One chunk delivered to the reply widget.
///
/// Holds the string received in one delivery ([text]) and its kind ([kind]).
/// The character count varies with how it arrives — sometimes a single
/// character, sometimes a dozen or more.
class Chunk {
  const Chunk(this.text, {this.kind = ChunkKind.reply});

  /// The chunk's text.
  final String text;

  /// The chunk's kind: thinking or reply.
  final ChunkKind kind;
}
