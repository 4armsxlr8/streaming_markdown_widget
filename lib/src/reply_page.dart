import 'dart:math';

import 'package:flutter/material.dart';

import 'fake_reply_source.dart';
import 'keys.dart';
import 'reply_theme.dart';
import 'sample_reply.dart';
import 'streaming_reply.dart';
import 'streaming_reply_controller.dart';

/// サンプルの画面: 薄い灰色の背景に、返答の吹き出し 1 つと
/// 「最初から流す」ボタン。
///
/// 入力欄・履歴・利用者の吹き出しは持たない。起動すると同時に作り物の供給
/// ([FakeReplySource]) が自動で流れ始める。「最初から流す」を押すと、受信中
/// でも受信完了後でも、古い供給と [StreamingReplyController] を破棄してから
/// 新しい 2 つを作り直し、返答を 0 から流し直す。縦に長い返答も見られるよう
/// 画面全体を縦スクロールでき、返答が伸びて読んでいる位置が末尾付近にあれば
/// 自動で追随する。
class ReplyPage extends StatefulWidget {
  const ReplyPage({
    super.key,
    this.thinking = sampleThinking,
    this.reply = sampleReply,
    this.random,
  });

  /// 供給する思考の文。
  final String thinking;

  /// 供給する返答。
  final String reply;

  /// 供給の乱数 (省略時は [FakeReplySource] の既定に任せる)。動作確認・
  /// テストで供給の塊の切れ方・間隔を固定したいときに渡す。
  final Random? random;

  @override
  State<ReplyPage> createState() => _ReplyPageState();
}

class _ReplyPageState extends State<ReplyPage> {
  /// 「最初から流す」のたびに増やす世代。[_ReplyFlow] の Key にする ―
  /// Key が変わると Flutter は古い Element を丸ごと破棄してから新しく作る
  /// ([_ReplyFlowState.dispose] → [_ReplyFlowState.initState] の順)。
  /// Controller を差し替えるだけだと、その frame の animate phase (Ticker の
  /// 発火) が build phase より先に走るため、供給と Controller を手で
  /// dispose() する経路では間に合わず、古い Ticker が dispose 済み
  /// Controller に触れて例外になる。Key で丸ごと作り直せば、その隙の tick は
  /// まだ生きている古い Controller に届くだけ (無害) で、直後の build phase
  /// で古い供給・Controller ごと安全に破棄できる。
  int _generation = 0;

  /// 画面全体の縦スクロールの位置。自動追随 (末尾へ jumpTo) に使う。
  final ScrollController _scrollController = ScrollController();

  /// 末尾へ追随中かどうかの状態 ([Q3])。true になるのは末尾から
  /// [ReplyTheme.autoFollowDistance] 以内に (スクロール中でなく) 居るとき。
  /// true の間は 1 フレームでどれだけ伸びても (`gap` が
  /// [ReplyTheme.autoFollowDistance] を超えても) 末尾へ追随し続ける —
  /// 伸びた「量」ではなく「追随していたかどうか」で判定しないと、散文中の
  /// `|` を含む行がまとめて現れる・大きい文字サイズで表が現れるなど、1
  /// フレームで 72px を超えて伸びる普通の届き方で追随が永久に止まってしまう。
  /// false になるのは、利用者が指でスクロールして末尾から離れたときだけ
  /// ([_handleScrollUpdate] が `ScrollUpdateNotification.dragDetails` で
  /// 判定する — [ScrollMetricsNotification] は `scheduleMicrotask` で遅延
  /// 配送されるため、配送される頃には `isScrollingNotifier` がドラッグ終了で
  /// 既に false に戻っており、ここでは利用者のドラッグ中かどうかを判定できない)。
  bool _following = true;

  void _replay() => setState(() => _generation++);

  /// [Keys.replyScroll] の extent (中身の高さ) が変わるたびに呼ばれる
  /// (新しい文字が届いて中身が伸びたときなど。利用者の指のドラッグでは
  /// 発生しない位置だけの変化はここに来ない)。[_following] の間は末尾へ
  /// 追随し、そうでなければ何もしない (読んでいる位置を動かさない)。
  ///
  /// コードブロック・表は自前の横スクロールを持ち、その通知もここまで
  /// 泡上がりしてくるので、縦スクロール (この画面の [_scrollController])
  /// のものだけを見る。
  bool _handleScrollMetrics(ScrollMetricsNotification notification) {
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    final gap = metrics.maxScrollExtent - metrics.pixels;
    if (gap <= ReplyTheme.autoFollowDistance) _following = true;
    // gap <= 0 は iOS の bounce で `pixels` が `maxScrollExtent` を超えている
    // 間 (追随は gap が 0〜autoFollowDistance の間だけ)。jumpTo するまでも
    // ないので何もしない (following の状態は変えない)。
    if (!_following || gap <= 0) return false;
    // 指がドラッグ中なら jumpTo しない (goIdle() でドラッグ操作を破棄して
    // しまうため)。
    if (_scrollController.position.isScrollingNotifier.value) return false;
    _scrollController.jumpTo(metrics.maxScrollExtent);
    return false;
  }

  /// 利用者の指のドラッグによるスクロール位置の変化のたびに呼ばれる
  /// (`dragDetails != null` で判定。中身が伸びて自動追随した分はここに
  /// 来ない)。末尾から [ReplyTheme.autoFollowDistance] を超えて離れたら
  /// [_following] を false にする。
  bool _handleScrollUpdate(ScrollUpdateNotification notification) {
    if (notification.dragDetails == null) return false;
    final metrics = notification.metrics;
    if (metrics.axis != Axis.vertical) return false;
    final gap = metrics.maxScrollExtent - metrics.pixels;
    if (gap > ReplyTheme.autoFollowDistance) _following = false;
    return false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReplyTheme.pageBackground,
      // SafeArea で包み、ステータスバーやノッチの下に吹き出し・「考え中…」が
      // 潜らないようにする (AppBar が無い Scaffold なので上の余白が自動では
      // 空かない)。背景色は Scaffold 自身が塗るので SafeArea の外まで届く。
      body: SafeArea(
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: _handleScrollMetrics,
          child: NotificationListener<ScrollUpdateNotification>(
            onNotification: _handleScrollUpdate,
            child: SingleChildScrollView(
              key: Keys.replyScroll,
              controller: _scrollController,
              padding: ReplyTheme.pagePadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ReplyFlow(
                    key: ValueKey(_generation),
                    thinking: widget.thinking,
                    reply: widget.reply,
                    random: widget.random,
                  ),
                  const SizedBox(height: ReplyTheme.actionsSpacingTop),
                  _ReplayButton(onTap: _replay),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 供給 ([FakeReplySource]) と [StreamingReplyController] を 1 組だけ持つ。
/// 生まれたら供給が始まり、破棄されると供給・Controller の順に破棄する。
class _ReplyFlow extends StatefulWidget {
  const _ReplyFlow({
    super.key,
    required this.thinking,
    required this.reply,
    this.random,
  });

  /// 供給する思考の文。
  final String thinking;

  /// 供給する返答。
  final String reply;

  /// 供給の乱数 ([ReplyPage.random] をそのまま渡す)。
  final Random? random;

  @override
  State<_ReplyFlow> createState() => _ReplyFlowState();
}

class _ReplyFlowState extends State<_ReplyFlow> {
  late final StreamingReplyController _controller;
  late final FakeReplySource _source;

  @override
  void initState() {
    super.initState();
    _controller = StreamingReplyController();
    _source = FakeReplySource(
      controller: _controller,
      thinking: widget.thinking,
      reply: widget.reply,
      random: widget.random,
    );
    _source.start();
  }

  @override
  void dispose() {
    _source.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamingReply(controller: _controller);
}

/// 「最初から流す」ボタン。
class _ReplayButton extends StatelessWidget {
  const _ReplayButton({required this.onTap});

  final VoidCallback onTap;

  /// ボタンの文言。
  static const _label = '最初から流す';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: Keys.replayButton,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: ReplyTheme.replayButtonPadding,
        decoration: BoxDecoration(
          color: ReplyTheme.replayButtonBackground,
          border: Border.all(
            color: ReplyTheme.replayButtonBorderColor,
            width: ReplyTheme.replayButtonBorderWidth,
          ),
          borderRadius: BorderRadius.circular(
            ReplyTheme.replayButtonBorderRadius,
          ),
        ),
        child: const Text(_label, style: ReplyTheme.replayButtonTextStyle),
      ),
    );
  }
}
