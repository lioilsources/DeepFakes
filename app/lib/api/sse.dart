import 'dart:async';
import 'dart:convert';

/// A single Server-Sent Event.
class SseEvent {
  const SseEvent({required this.event, required this.data, this.id});

  /// Event type; `message` when the server did not send an `event:` field.
  final String event;
  final String data;
  final String? id;

  @override
  String toString() => 'SseEvent($event, $data)';
}

/// Parses a `text/event-stream` byte stream into [SseEvent]s.
///
/// Follows the WHATWG event-stream rules that matter here: `\n`, `\r\n` and
/// `\r` line endings, `:` comments, multi-line `data:` joined by `\n`, one
/// optional space after the colon, dispatch on an empty line. An incomplete
/// event at end of stream is discarded, as the spec requires.
Stream<SseEvent> parseSse(Stream<List<int>> bytes) {
  return bytes
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .transform(const SseLineDecoder());
}

/// Turns already split lines into events. Exposed for testing.
class SseLineDecoder extends StreamTransformerBase<String, SseEvent> {
  const SseLineDecoder();

  @override
  Stream<SseEvent> bind(Stream<String> lines) async* {
    String? eventType;
    String? lastId;
    final data = <String>[];
    var hasData = false;

    await for (final line in lines) {
      if (line.isEmpty) {
        if (hasData) {
          yield SseEvent(
            event: (eventType == null || eventType.isEmpty)
                ? 'message'
                : eventType,
            data: data.join('\n'),
            id: lastId,
          );
        }
        eventType = null;
        data.clear();
        hasData = false;
        continue;
      }
      if (line.startsWith(':')) continue;

      final colon = line.indexOf(':');
      final String field;
      var value = '';
      if (colon < 0) {
        field = line;
      } else {
        field = line.substring(0, colon);
        value = line.substring(colon + 1);
        if (value.startsWith(' ')) value = value.substring(1);
      }
      switch (field) {
        case 'event':
          eventType = value;
        case 'data':
          data.add(value);
          hasData = true;
        case 'id':
          if (!value.contains('\u0000')) lastId = value;
        default:
          // `retry` and unknown fields are ignored; reconnect policy lives in
          // the client.
          break;
      }
    }
  }
}
