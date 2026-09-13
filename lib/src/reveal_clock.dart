import 'package:flutter/widgets.dart' show StringCharacters;

/// 出現中の 1 文字 (書記素) と、その不透明度。
///
/// [opacity] は 0 (透明) から 1 (不透明) の範囲。出現を始めたがまだ 1 に達して
/// いない文字だけがこの型で表れる ([RevealClock.revealingAt] を参照)。
class RevealingChar {
  const RevealingChar({required this.index, required this.char, required this.opacity});

  /// 受信した文字列の中での書記素の通し番号 (0 始まり)。
  final int index;

  /// この文字そのもの (書記素 1 つ)。
  final String char;

  /// 不透明度 (0〜1)。
  final double opacity;
}

/// 出現開始からの経過 [elapsed] とフェードにかかる時間 [fade] から、
/// 不透明度 (0〜1) を計算する。[RevealClock.revealingAt] と描画側
/// (`revealed_markdown.dart` の `_RevealCursor.consume`) の両方で使う共通の
/// 勾配。
double revealOpacity(Duration elapsed, Duration fade) =>
    (elapsed.inMicroseconds / fade.inMicroseconds).clamp(0, 1);

/// 1 文字ずつの出現の時計。
///
/// 受信した書記素の列を保持し、各文字が出現を始める時刻 (基準値) を割り当てる。
/// Flutter の Widget に依存しない純 Dart。時刻はすべて [Duration] (経過時間)
/// で表し、`Widget` や `Ticker` を知らない。
///
/// 基準の出現間隔は 40 文字/秒 = 25ms。未出現の残り ([pendingCountAt]) が
/// 追いつきの上限を超えた瞬間、または [fastForward] が呼ばれた瞬間に、
/// その時点の残りから速さを 1 度だけ決めて割り当て直す
/// (「切り替わった瞬間の残り」から決め、毎フレーム残りで割り直さない)。
///
/// 塊の境界でサロゲートペアが割れた場合は、書記素が閉じるまで文字数に数えない
/// ([receivedCount] / [text] に含めない)。
class RevealClock {
  RevealClock({this.normalInterval = const Duration(microseconds: 25000)});

  /// 1 文字の不透明度が 0 から 1 になるまでの基準の時間 (`fade` 引数の既定値。
  /// `ReplyTheme.fadeDuration` はこれを参照する — 出現の速さの正本はここ)。
  static const Duration defaultFade = Duration(milliseconds: 300);

  /// 基準の出現間隔 (40 文字/秒)。
  final Duration normalInterval;

  /// 受信した書記素 (サロゲートが閉じているもののみ)。
  final List<String> _chars = [];

  /// 各書記素の出現開始時刻。まだ割り当てていない文字は null。
  final List<Duration?> _startTimes = [];

  /// 塊の境界で割れた、まだ閉じていない上位サロゲート 1 文字分。
  String? _danglingHighSurrogate;

  /// 受信した文字数 (書記素。閉じていないサロゲートは数えない)。
  int get receivedCount => _chars.length;

  /// 受信した全文 (閉じていないサロゲートは含まない)。
  String get text => _chars.join();

  /// 塊の文字列を受信するだけで、出現の割り当ては行わない。
  ///
  /// 思考の畳みを待つ間など、出現を始めさせたくない塊を溜めておくのに使う。
  /// 割り当ては後で [scheduleFromArrival] や [fastForward] を呼んで行う。
  void appendOnly(String chunkText) {
    final combined = (_danglingHighSurrogate ?? '') + chunkText;
    _danglingHighSurrogate = null;

    var toProcess = combined;
    if (toProcess.isNotEmpty) {
      final lastUnit = toProcess.codeUnitAt(toProcess.length - 1);
      // 上位サロゲート (U+D800-U+DBFF) で終わっていれば、対になる下位サロゲート
      // が次の塊で届くまで保留する。
      if (lastUnit >= 0xD800 && lastUnit <= 0xDBFF) {
        _danglingHighSurrogate = toProcess.substring(toProcess.length - 1);
        toProcess = toProcess.substring(0, toProcess.length - 1);
      }
    }
    if (toProcess.isEmpty) return;

    // 直前に受信済みの書記素と新しい塊がくっついて 1 つの書記素になる場合
    // (ZWJ 連結絵文字・結合文字・肌色修飾・国旗など、塊の境界がその途中で
    // 割れた場合) に備え、「直前の書記素 + 新しい塊」をまとめて書記素に
    // 割り直す。先頭の書記素が直前の書記素を吸収していれば、直前の項目を
    // 置き換える (出現開始時刻 [_startTimes] はそのまま保つ)。
    var graphemes = toProcess.characters.toList(growable: false);
    if (_chars.isNotEmpty) {
      final merged = (_chars.last + toProcess).characters.toList(growable: false);
      if (merged.isNotEmpty && merged.first != _chars.last) {
        _chars[_chars.length - 1] = merged.first;
        graphemes = merged.skip(1).toList(growable: false);
      }
    }

    for (final grapheme in graphemes) {
      _chars.add(grapheme);
      _startTimes.add(null);
    }
  }

  /// 受信完了を伝える。保留中の (対になる下位サロゲートが来なかった) 上位
  /// サロゲートがあれば、U+FFFD (置換文字) に変えて 1 文字として受信済みに
  /// 入れる (受信完了後に永久に消える経路を無くすため)。出現の割り当ては
  /// 行わない (呼び出し元が [scheduleFromArrival] や [fastForward] で行う)。
  ///
  /// 戻り値: 保留中の上位サロゲートを確定させた (= この呼び出しで初めて
  /// 1 文字以上受信した) なら true。呼び出し元 ([StreamingReplyController])
  /// はこれを見て、通常の到着解決 (思考の開始判定・返答の門開放) を通す。
  bool complete() {
    if (_danglingHighSurrogate == null) return false;
    _danglingHighSurrogate = null;
    _chars.add('�');
    _startTimes.add(null);
    return true;
  }

  /// 未割り当ての文字 (と、まだ出現していない割り当て済みの文字) に、
  /// 基準または追いつきの規則で出現開始時刻を割り当てる。
  ///
  /// [catchUpThreshold] を超える残りがあれば、[eventTime] の時点の残りから
  /// 追いつきの速さを 1 度だけ決めて [catchUpBudget] 以内に上限まで戻す。
  /// 超えなければ、割り当て済みでまだ出現していない文字の列に続けて基準の
  /// 間隔で割り当てる (無ければ [eventTime] から)。
  void scheduleFromArrival(
    Duration eventTime, {
    int catchUpThreshold = 24,
    Duration catchUpBudget = const Duration(milliseconds: 600),
  }) {
    final unassigned = <int>[];
    final outstanding = <int>[];
    for (var i = 0; i < _startTimes.length; i++) {
      final startTime = _startTimes[i];
      if (startTime == null) {
        unassigned.add(i);
      } else if (startTime >= eventTime) {
        // 同じ到着時刻の文字も、まだ時間が進んで出現を観測されていなければ
        // 列を継ぐ (等号を含めないと、tick を挟まず同時刻に届いた複数の塊が
        // すべて到着時刻ちょうどに重なって出現してしまう)。
        outstanding.add(i);
      }
    }
    if (unassigned.isEmpty) return;

    final pendingAfter = outstanding.length + unassigned.length;
    if (pendingAfter > catchUpThreshold) {
      _scheduleCatchUpTail(
        [...outstanding, ...unassigned],
        eventTime,
        budget: catchUpBudget,
        keepThreshold: catchUpThreshold,
      );
      return;
    }

    var next = outstanding.isNotEmpty
        ? _startTimes[outstanding.last]! + normalInterval
        : eventTime;
    for (final index in unassigned) {
      _startTimes[index] = next;
      next += normalInterval;
    }
  }

  /// まだ出現していない文字 (割り当て済み・未割り当ての両方) を、
  /// [eventTime] の時点の残りから決めた 1 つの速さで [budget] 以内に出し切る。
  ///
  /// 受信完了時の早送りと、返答の最初の塊が届いた時点の思考の早送りの
  /// どちらにも使う。
  ///
  /// 同じ文字が 2 回目の [fastForward] の対象になっても (受信完了までに思考の
  /// 早送りが 2 度走る場合など)、新しく計算した時刻が既存の割り当てより
  /// 遅ければ既存を保つ ([min] を取る) — 遅い方を採用すると、1 回目の
  /// 早送りで [budget] 以内に収まるよう割り当てた文字が、2 回目の (より遅い
  /// `eventTime` を起点にした) 割り当てで押し流されて期限を超えてしまう。
  void fastForward(Duration eventTime, {Duration budget = const Duration(milliseconds: 400)}) {
    final tail = <int>[];
    for (var i = 0; i < _startTimes.length; i++) {
      final startTime = _startTimes[i];
      // scheduleFromArrival と同じ理由で等号を含める: eventTime ちょうどに
      // 出現を始める (始めた) 文字を素通りさせると、そのすぐ後ろの文字が
      // 同じ eventTime に割り当てられ、2 文字が同時に出現してしまう。
      if (startTime == null || startTime >= eventTime) tail.add(i);
    }
    if (tail.isEmpty) return;

    final normalUs = normalInterval.inMicroseconds.toDouble();
    final budgetUs = budget.inMicroseconds.toDouble();
    final intervalUs = (budgetUs / tail.length) < normalUs ? budgetUs / tail.length : normalUs;
    for (var j = 0; j < tail.length; j++) {
      final index = tail[j];
      final candidate = eventTime + Duration(microseconds: (j * intervalUs).round());
      final existing = _startTimes[index];
      _startTimes[index] = existing == null || candidate < existing ? candidate : existing;
    }
  }

  /// [indexes] (昇順、outstanding の後に unassigned) を追いつきの規則で割り当てる。
  ///
  /// 先頭の `indexes.length - keepThreshold` 文字は追いつきの速さ、
  /// 残り [keepThreshold] 文字は基準の速さで、追いつきの最後の文字に続けて
  /// 割り当てる。
  void _scheduleCatchUpTail(
    List<int> indexes,
    Duration eventTime, {
    required Duration budget,
    required int keepThreshold,
  }) {
    final total = indexes.length;
    final catchUpCount = total - keepThreshold;
    final catchUpIntervalUs = budget.inMicroseconds / total;

    for (var j = 0; j < catchUpCount; j++) {
      _startTimes[indexes[j]] = eventTime + Duration(microseconds: (j * catchUpIntervalUs).round());
    }

    var next = _startTimes[indexes[catchUpCount - 1]]! + normalInterval;
    for (var k = 0; k < keepThreshold; k++) {
      _startTimes[indexes[catchUpCount + k]] = next;
      next += normalInterval;
    }
  }

  /// [now] 時点で出現を始めている文字数。
  int startedCountAt(Duration now) {
    var count = 0;
    for (final startTime in _startTimes) {
      if (startTime != null && startTime <= now) count++;
    }
    return count;
  }

  /// [now] 時点でまだ出現していない残り。
  int pendingCountAt(Duration now) => receivedCount - startedCountAt(now);

  /// [now] 時点で出現を始めたがまだ不透明度 1 に達していない文字。index 昇順。
  List<RevealingChar> revealingAt(Duration now, {Duration fade = defaultFade}) {
    final result = <RevealingChar>[];
    for (var i = 0; i < _chars.length; i++) {
      final startTime = _startTimes[i];
      if (startTime == null || startTime > now) continue;
      final elapsed = now - startTime;
      if (elapsed >= fade) continue;
      result.add(RevealingChar(index: i, char: _chars[i], opacity: revealOpacity(elapsed, fade)));
    }
    return result;
  }

  /// [now] 時点で不透明度が 1 に達した (表示済みの) 文字数。
  int displayedCountAt(Duration now, {Duration fade = defaultFade}) {
    var count = 0;
    for (final startTime in _startTimes) {
      if (startTime != null && now - startTime >= fade) count++;
    }
    return count;
  }

  /// [now] 時点で出現を始めた分までの文字列 (書記素の境界で切る)。
  String revealedTextAt(Duration now) {
    final buffer = StringBuffer();
    for (var i = 0; i < _chars.length; i++) {
      final startTime = _startTimes[i];
      if (startTime == null || startTime > now) break;
      buffer.write(_chars[i]);
    }
    return buffer.toString();
  }
}
