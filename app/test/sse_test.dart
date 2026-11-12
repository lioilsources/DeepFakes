import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pravdomer/api/sse.dart';

Stream<List<int>> chunks(List<String> parts) =>
    Stream.fromIterable(parts.map(utf8.encode));

void main() {
  test('parses events with type, data and id', () async {
    final events = await parseSse(
      chunks([
        'event: status\ndata: {"status":"fetching"}\nid: 1\n\n',
        'event: done\ndata: {}\n\n',
      ]),
    ).toList();
    expect(events, hasLength(2));
    expect(events[0].event, 'status');
    expect(events[0].data, '{"status":"fetching"}');
    expect(events[0].id, '1');
    expect(events[1].event, 'done');
  });

  test('handles chunks split mid-line, CRLF and multi-byte UTF-8', () async {
    final bytes = utf8.encode(
      'event: paragraph\r\ndata: {"t":"příliš žluťoučký 🐴"}\r\n\r\n',
    );
    // Split into 3-byte pieces so UTF-8 sequences and CRLF are cut apart.
    final parts = <List<int>>[
      for (var i = 0; i < bytes.length; i += 3)
        bytes.sublist(i, (i + 3).clamp(0, bytes.length)),
    ];
    final events = await parseSse(Stream.fromIterable(parts)).toList();
    expect(events.single.event, 'paragraph');
    expect(events.single.data, '{"t":"příliš žluťoučký 🐴"}');
  });

  test('joins multi-line data, ignores comments and unknown fields', () async {
    final events = await parseSse(
      chunks([
        ': keep-alive\n\n',
        'retry: 3000\nfoo: bar\ndata: line1\ndata:line2\n\n',
      ]),
    ).toList();
    expect(events.single.event, 'message');
    expect(events.single.data, 'line1\nline2');
  });

  test(
    'blank line without data does not dispatch; trailing partial dropped',
    () async {
      final events = await parseSse(
        chunks([
          'event: status\n\n',
          'event: done\ndata: {}\n\n',
          'event: summary\ndata: {"score": 1}',
        ]),
      ).toList();
      expect(events.map((e) => e.event), ['done']);
    },
  );

  test('only one leading space is stripped', () async {
    final events = await parseSse(chunks(['data:  two spaces\n\n'])).toList();
    expect(events.single.data, ' two spaces');
  });
}
