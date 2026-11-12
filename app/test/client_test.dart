import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pravdomer/api/client.dart';
import 'package:pravdomer/api/models.dart';

import 'fixtures.dart';

PravdomerClient clientWith(http.Client c) => PravdomerClient(
  baseUrl: Uri.parse('http://api.test'),
  deviceId: 'device-1',
  httpClient: c,
  reconnectDelay: Duration.zero,
);

http.StreamedResponse sse(String body, {int status = 200}) =>
    http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
      headers: {'content-type': 'text/event-stream'},
    );

void main() {
  test('createAnalysis sends device id and body', () async {
    late http.Request seen;
    final c = clientWith(
      MockClient((req) async {
        seen = req;
        return http.Response(startJson, 202);
      }),
    );
    final r = await c.createAnalysis(url: 'https://example.com/a');
    expect(r.id, '01JCABC');
    expect(seen.method, 'POST');
    expect(seen.url.path, '/v1/analyses');
    expect(seen.headers['X-Device-Id'], 'device-1');
    expect(jsonDecode(seen.body), {'url': 'https://example.com/a'});
  });

  test('429 carries Retry-After', () async {
    final c = clientWith(
      MockClient(
        (_) async =>
            http.Response(errorJson, 429, headers: {'retry-after': '42'}),
      ),
    );
    await expectLater(
      c.createAnalysis(text: 'x'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'rate_limited')
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 42),
            ),
      ),
    );
  });

  test('error without JSON body falls back to status code', () async {
    final c = clientWith(MockClient((_) async => http.Response('nope', 413)));
    await expectLater(
      c.createAnalysis(text: 'x'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'too_large')),
    );
  });

  test('events reconnect after a dropped stream and end with done', () async {
    var calls = 0;
    final c = clientWith(
      MockClient.streaming((req, _) async {
        calls++;
        expect(req.url.path, '/v1/analyses/01JCABC/events');
        expect(req.headers['X-Device-Id'], 'device-1');
        if (calls == 1) {
          // Drops before done.
          return sse('event: status\ndata: {"status":"fetching"}\n\n');
        }
        if (calls == 2) throw http.ClientException('reset');
        return sse(
          'event: status\ndata: {"status":"fetching"}\n\n'
          'event: summary\ndata: {"score": 12}\n\n'
          'event: done\ndata: {}\n\n',
        );
      }),
    );
    final events = await c.events('01JCABC').toList();
    expect(calls, 3);
    expect(events.last, isA<DoneEvent>());
    expect(events.whereType<SummaryEvent>().single.summary.score, 12);
  });

  test('events give up with connection_lost', () async {
    final c = PravdomerClient(
      baseUrl: Uri.parse('http://api.test'),
      deviceId: 'd',
      reconnectDelay: Duration.zero,
      maxConsecutiveFailures: 2,
      httpClient: MockClient.streaming(
        (_, _) async => throw http.ClientException('down'),
      ),
    );
    final events = await c.events('x').toList();
    expect(
      events.single,
      isA<ErrorEvent>().having((e) => e.code, 'code', 'connection_lost'),
    );
  });

  test('server error event ends the stream', () async {
    final c = clientWith(
      MockClient.streaming(
        (_, _) async => sse(
          'event: error\ndata: {"code":"fetch_failed","message":"x"}\n\n',
        ),
      ),
    );
    final events = await c.events('x').toList();
    expect(
      events.single,
      isA<ErrorEvent>().having((e) => e.code, 'code', 'fetch_failed'),
    );
  });
}
