import 'dart:async';

import 'package:test/test.dart';

/// Documents the subscribe-before-send requirement for inline [WorkerBee] dispatch
/// on WASM (sync broadcast response streams).
void main() {
  group('inline worker dispatch stream order', () {
    test('sync add before listen loses event on broadcast stream', () async {
      final controller = StreamController<int>.broadcast(sync: true);
      controller.add(1);
      await expectLater(
        controller.stream.first.timeout(const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
      await controller.close();
    });

    test('listen before sync add delivers event', () async {
      final controller = StreamController<int>.broadcast(sync: true);
      final responseFuture = controller.stream.first;
      controller.add(42);
      await expectLater(responseFuture, completion(42));
      await controller.close();
    });
  });
}
