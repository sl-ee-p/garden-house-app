import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_house_app/asset_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => HttpOverrides.global = null);

  test('survives a client that disconnects early', () async {
    final server = await AssetServer.instance;
    final uri = Uri.parse(server.url('assets/missing.png'));
    final errors = <Object>[];
    await runZonedGuardedAsync(errors, () async {
      final socket = await Socket.connect(uri.host, uri.port);
      socket.write('GET ${uri.path} HTTP/1.1\r\nHost: ${uri.host}\r\n\r\n');
      socket.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    expect(errors, isEmpty);
    // Still serving afterwards.
    final client = HttpClient();
    final res = await (await client.getUrl(uri)).close();
    expect(res.statusCode, HttpStatus.notFound);
    client.close();
  });
}

Future<void> runZonedGuardedAsync(
  List<Object> errors,
  Future<void> Function() body,
) async {
  await runZonedGuarded(body, (e, _) => errors.add(e));
}
