import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_house_app/house_viewer.dart';

void main() {
  const short = Duration(milliseconds: 50);

  test('times out with null', () async {
    final s = ViewerSnapshots((_) async {}, timeout: short);
    expect(await s.request(), isNull);
  });

  test('a throwing runner gives null', () async {
    final s = ViewerSnapshots((_) async => throw Exception('boom'));
    expect(await s.request(), isNull);
  });

  test('a page error gives null', () async {
    final s = ViewerSnapshots((_) async {});
    final f = s.request();
    s.onMessage({'type': 'snapshot', 'error': 'nope'});
    expect(await f, isNull);
  });

  test('a data URL gives the bytes', () async {
    final s = ViewerSnapshots((_) async {});
    final f = s.request();
    s.onMessage({
      'type': 'snapshot',
      'data': 'data:image/png;base64,${base64Encode([1, 2, 3])}',
    });
    expect(await f, Uint8List.fromList([1, 2, 3]));
  });

  test('concurrent requests share one future', () async {
    var calls = 0;
    final s = ViewerSnapshots((_) async => calls++);
    final a = s.request();
    final b = s.request();
    s.onMessage({
      'type': 'snapshot',
      'data': 'data:image/png;base64,${base64Encode([9])}',
    });
    expect(await a, await b);
    expect(calls, 1);
  });

  test('cancel completes with null', () async {
    final s = ViewerSnapshots((_) async {});
    final f = s.request();
    s.cancel();
    expect(await f, isNull);
  });
}
