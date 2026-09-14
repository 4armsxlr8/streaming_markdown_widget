import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';
import 'package:streaming_markdown_widget_example/src/gemini_reply_source.dart';

/// 本物の供給 (Gemini の SSE 応答を塊の Stream に変換する) のテスト (AC-18)。
///
/// seam は利用例アプリの変換。要件「変換は example の純 Dart のコードとして
/// 書き、API の応答の作り物でテストできる」のとおり、[geminiReplyStream] は
/// Widget も画面も要らない関数としてここで主張する。ネットワークは
/// [MockClient] で差し替えるので本物の Gemini は呼ばない (本物は実機で確認
/// する)。
void main() {
  /// 差し替えた client に渡す鍵 (値そのものに意味はなく、そのままヘッダへ
  /// 載ることだけが効く)。
  const apiKey = 'test-api-key';

  /// 差し替えた client に渡すモデル名 (URL に載ることだけが効く)。
  const model = 'gemini-2.5-flash';

  /// 供給を頼む質問。
  const question = '本物の供給はどう動くのか';

  /// 2xx の応答のヘッダ。
  ///
  /// charset が無いと [http.Response] は本文を latin1 で符号化するので、
  /// 日本語の作り物が壊れる。実際の Gemini も
  /// `text/event-stream; charset=utf-8` を返す。
  const sseHeaders = {'content-type': 'text/event-stream; charset=utf-8'};

  /// 思考の印が付いた part。
  Map<String, Object?> thoughtPart(String text) => {
    'text': text,
    'thought': true,
  };

  /// 返答の part (思考の印は付かない)。
  Map<String, Object?> replyPart(String text) => {'text': text};

  /// SSE の 1 イベント (`data: <JSON>` + 空行) を組む。
  ///
  /// [parts] を渡さない候補は `content` を持たない (安全性でブロックされた
  /// ときの実際の形)。`usageMetadata` / `modelVersion` / `responseId` は変換
  /// では無視されるが、実際の Gemini の形に近づけるため付けておく。
  String event({List<Map<String, Object?>>? parts, String? finishReason}) {
    final candidate = <String, Object?>{
      if (parts != null) 'content': {'parts': parts, 'role': 'model'},
      'index': 0,
      'finishReason': ?finishReason,
    };
    final json = jsonEncode({
      'candidates': [candidate],
      'usageMetadata': {
        'promptTokenCount': 8,
        'candidatesTokenCount': 12,
        'totalTokenCount': 20,
      },
      'modelVersion': model,
      'responseId': 'test-response-id',
    });
    return 'data: $json\n\n';
  }

  /// [stream] を最後まで読み、届いた塊と (あれば) 終わり方のエラーを返す。
  ///
  /// エラーで終わる場合も、それまでに届いた塊を見たいので `toList` は使わない。
  Future<({List<Chunk> chunks, Object? error})> drain(
    Stream<Chunk> stream,
  ) async {
    final chunks = <Chunk>[];
    Object? error;
    try {
      await for (final chunk in stream) {
        chunks.add(chunk);
      }
    } catch (thrown) {
      error = thrown;
    }
    return (chunks: chunks, error: error);
  }

  test(
    'AC-18 思考の印が付いた parts 2 つと本文の parts 3 つの SSE は、思考の塊 2 つ → 返答の塊 3 つの順に変換され終端で閉じる',
    () async {
      // 2 つめのイベントは、1 つのイベントに思考と本文の parts が混ざる場合。
      final body =
          event(parts: [thoughtPart('質問の要点を整える。')]) +
          event(parts: [thoughtPart('答えの筋道を決める。'), replyPart('# 本物の供給\n\n')]) +
          event(parts: [replyPart('各 `data:` 行を JSON として読む。')]) +
          event(parts: [replyPart('そして終端で閉じる。')], finishReason: 'STOP');
      final client = MockClient(
        (request) async => http.Response(body, 200, headers: sseHeaders),
      );

      // toList が完了すること自体が「終端で閉じる」の主張。
      final chunks = await geminiReplyStream(
        question,
        apiKey: apiKey,
        model: model,
        client: client,
      ).toList();

      expect(chunks.map((chunk) => chunk.kind).toList(), [
        ChunkKind.thinking,
        ChunkKind.thinking,
        ChunkKind.reply,
        ChunkKind.reply,
        ChunkKind.reply,
      ]);
      expect(chunks.map((chunk) => chunk.text).toList(), [
        '質問の要点を整える。',
        '答えの筋道を決める。',
        '# 本物の供給\n\n',
        '各 `data:` 行を JSON として読む。',
        'そして終端で閉じる。',
      ]);
    },
  );

  test('AC-18 思考の印が付いた parts が無い SSE は、返答の塊だけに変換される (思考の塊は 0 個)', () async {
    final body =
        event(parts: [replyPart('思考の印が無い本文。')]) +
        event(parts: [replyPart('続きの本文。')], finishReason: 'STOP');
    final client = MockClient(
      (request) async => http.Response(body, 200, headers: sseHeaders),
    );

    final chunks = await geminiReplyStream(
      question,
      apiKey: apiKey,
      model: model,
      client: client,
    ).toList();

    expect(chunks.map((chunk) => chunk.kind).toList(), [
      ChunkKind.reply,
      ChunkKind.reply,
    ]);
    expect(chunks.map((chunk) => chunk.text).toList(), [
      '思考の印が無い本文。',
      '続きの本文。',
    ]);
  });

  test('AC-18 HTTP 401 が返ると塊は 1 つも流れず、status code を含むメッセージのエラーで終わる', () async {
    // 鍵が誤っているときに実際に返る本文。
    const errorBody =
        '{"error":{"code":401,'
        '"message":"API key not valid. Please pass a valid API key.",'
        '"status":"UNAUTHENTICATED"}}';
    final client = MockClient(
      (request) async => http.Response(
        errorBody,
        401,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final result = await drain(
      geminiReplyStream(question, apiKey: apiKey, model: model, client: client),
    );

    expect(result.chunks, isEmpty);
    expect(result.error, isNotNull);
    expect('${result.error}', contains('401'));
  });

  test('AC-18 finishReason が来ないまま本文が終わると、届いた塊が流れた後にエラーで終わる', () async {
    // どちらのイベントも形は正しく、finishReason だけが来ないまま途切れる。
    final body =
        event(parts: [replyPart('ここまでは届いた。')]) +
        event(parts: [replyPart('この続きは来ない。')]);
    final client = MockClient(
      (request) async => http.Response(body, 200, headers: sseHeaders),
    );

    final result = await drain(
      geminiReplyStream(question, apiKey: apiKey, model: model, client: client),
    );

    expect(result.chunks.map((chunk) => chunk.text).toList(), [
      'ここまでは届いた。',
      'この続きは来ない。',
    ]);
    expect(result.error, isNotNull);
  });

  test('AC-18 finishReason が SAFETY で本文が空だと、その理由を含むメッセージのエラーで終わる', () async {
    // 安全性でブロックされたときは content を持たない候補が 1 つだけ来る。
    final client = MockClient(
      (request) async => http.Response(
        event(finishReason: 'SAFETY'),
        200,
        headers: sseHeaders,
      ),
    );

    final result = await drain(
      geminiReplyStream(question, apiKey: apiKey, model: model, client: client),
    );

    expect(result.chunks, isEmpty);
    expect(result.error, isNotNull);
    expect('${result.error}', contains('SAFETY'));
  });

  test(
    'AC-18 供給を購読すると alt=sse の streamGenerateContent へ、鍵と includeThoughts と質問を付けて POST する',
    () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          event(parts: [replyPart('確認用の返答。')], finishReason: 'STOP'),
          200,
          headers: sseHeaders,
        );
      });

      await geminiReplyStream(
        question,
        apiKey: apiKey,
        model: model,
        client: client,
      ).toList();

      expect(captured.method, 'POST');
      expect(captured.url.scheme, 'https');
      expect(captured.url.host, 'generativelanguage.googleapis.com');
      // Uri の組み方しだいで `:` が %3A になるので、復号してから比べる。
      expect(
        Uri.decodeFull(captured.url.path),
        '/v1beta/models/$model:streamGenerateContent',
      );
      expect(captured.url.queryParameters['alt'], 'sse');
      expect(captured.headers['x-goog-api-key'], apiKey);
      expect(captured.headers['content-type'], contains('application/json'));

      final body =
          jsonDecode(utf8.decode(captured.bodyBytes)) as Map<String, Object?>;
      final contents = body['contents']! as List<Object?>;
      final content = contents.first! as Map<String, Object?>;
      final parts = content['parts']! as List<Object?>;
      expect((parts.first! as Map<String, Object?>)['text'], question);
      final generationConfig =
          body['generationConfig']! as Map<String, Object?>;
      final thinkingConfig =
          generationConfig['thinkingConfig']! as Map<String, Object?>;
      expect(thinkingConfig['includeThoughts'], isTrue);
    },
  );
}
