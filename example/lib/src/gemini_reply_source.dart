import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:streaming_markdown_widget/streaming_markdown_widget.dart';

/// Timeout waiting for the initial HTTP response (connect + headers).
const _connectTimeout = Duration(seconds: 30);

/// Idle timeout once the SSE body is streaming: if no line arrives within
/// this long, the stream ends with a [TimeoutException].
const _idleTimeout = Duration(seconds: 60);

/// Real supply: converts a Gemini `streamGenerateContent` SSE response into
/// a [Stream] of [Chunk] (AC-18).
///
/// Posts [question] to
/// `v1beta/models/{model}:streamGenerateContent?alt=sse` with
/// `thinkingConfig.includeThoughts: true` (redirects are not followed — the
/// API key header must not be forwarded to another host), reads each `data:`
/// line as JSON, and turns every part of `candidates[0].content.parts` into a
/// [Chunk] (`thought == true` becomes [ChunkKind.thinking], otherwise
/// [ChunkKind.reply] — a single SSE event can carry both). The stream closes
/// once `finishReason` arrives as `STOP`.
///
/// [apiKey] and [model] are supplied by the caller (this function does not
/// read the environment). When [client] is omitted, a [http.Client] is
/// created and closed when the stream ends, errors, or is canceled; a
/// caller-supplied [client] is left open in every case. Canceling the
/// returned [Stream]'s subscription aborts the request in flight (closing an
/// owned client mid-request makes it error out) instead of leaving it running
/// unobserved.
///
/// The stream ends with an error when: the HTTP status is not 2xx, sending
/// the request or waiting for the response takes longer than
/// [_connectTimeout], no SSE line arrives for [_idleTimeout], a line's JSON
/// is malformed (a fixed message — never a fragment of the response body),
/// `finishReason` arrives as anything other than `STOP` (safety block,
/// `MAX_TOKENS`, …), or the body ends without ever sending a `finishReason`
/// (dropped connection).
Stream<Chunk> geminiReplyStream(
  String question, {
  required String apiKey,
  required String model,
  http.Client? client,
}) {
  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  StreamSubscription<String>? lineSubscription;
  var cancelled = false;
  final controller = StreamController<Chunk>();

  void closeOwnedClient() {
    if (ownsClient) httpClient.close();
  }

  void finish() {
    lineSubscription?.cancel();
    closeOwnedClient();
    controller.close();
  }

  // The single termination-with-error path: report [error] (unless the
  // controller is already closed — nothing left to report to) and finish
  // either way. Used by the SSE line's malformed-JSON case, the lines
  // Stream's own onError, and the outer catch below (which can run before
  // [lineSubscription] is ever assigned — finish()'s
  // `lineSubscription?.cancel()` stays null-safe for that).
  void fail(Object error, [StackTrace? stackTrace]) {
    if (!controller.isClosed) controller.addError(error, stackTrace);
    finish();
  }

  controller.onListen = () async {
    try {
      final uri = Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/$model:streamGenerateContent',
        {'alt': 'sse'},
      );
      final request = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['x-goog-api-key'] = apiKey
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': question},
              ],
            },
          ],
          'generationConfig': {
            'thinkingConfig': {'includeThoughts': true},
          },
        });

      final response = await httpClient.send(request).timeout(_connectTimeout);
      if (cancelled) return;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Gemini streamGenerateContent failed with status '
          '${response.statusCode}',
        );
      }

      var sawFinishReason = false;

      void handleLine(String line) {
        if (controller.isClosed) return;
        if (!line.startsWith('data: ')) return;
        final Object? event;
        try {
          event = jsonDecode(line.substring(6));
        } on FormatException {
          // Never include a fragment of the response body in the error — it
          // could contain anything the API sent.
          fail(
            const FormatException(
              'Gemini streamGenerateContent sent a malformed SSE line',
            ),
          );
          return;
        }
        if (event is! Map<String, Object?>) return;
        final candidates = event['candidates'];
        if (candidates is! List || candidates.isEmpty) return;
        final candidate = candidates.first;
        if (candidate is! Map<String, Object?>) return;

        final content = candidate['content'];
        final parts = content is Map<String, Object?> ? content['parts'] : null;
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map<String, Object?>) continue;
            final text = part['text'];
            if (text is! String) continue;
            controller.add(
              Chunk(
                text,
                kind: part['thought'] == true
                    ? ChunkKind.thinking
                    : ChunkKind.reply,
              ),
            );
          }
        }

        final finishReason = candidate['finishReason'];
        if (finishReason is String) {
          sawFinishReason = true;
          if (finishReason != 'STOP') {
            fail(
              Exception(
                'Gemini streamGenerateContent finished with reason '
                '$finishReason',
              ),
            );
          } else {
            finish();
          }
        }
      }

      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(_idleTimeout);

      lineSubscription = lines.listen(
        handleLine,
        onError: fail,
        onDone: () {
          if (!sawFinishReason) {
            controller.addError(
              Exception(
                'Gemini streamGenerateContent ended without a finishReason',
              ),
            );
          }
          finish();
        },
      );
    } catch (error, stackTrace) {
      fail(error, stackTrace);
    }
  };

  // Aborts a request that is still in flight (no line subscription yet) by
  // closing the owned client out from under it, and stops one that is
  // already streaming — either way, no further event reaches the (by then
  // unlistened) controller.
  controller.onCancel = () {
    cancelled = true;
    lineSubscription?.cancel();
    closeOwnedClient();
  };

  return controller.stream;
}
