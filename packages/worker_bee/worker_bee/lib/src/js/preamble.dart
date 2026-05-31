// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import 'dart:async';
import 'dart:js_interop';

// ignore: implementation_imports
import 'package:aws_common/src/js/common.dart';
import 'package:built_value/serializer.dart';
import 'package:web/web.dart';
import 'package:worker_bee/src/js/message_port_channel.dart';
import 'package:worker_bee/src/preamble.dart';
import 'package:worker_bee/src/serializers/serializers.dart';
import 'package:worker_bee/worker_bee.dart';

/// {@macro worker_bee.is_web_worker}
bool get isWebWorker => zIsWebWorker;

/// {@macro worker_bee.current_uri}
Uri get currentUri {
  return Uri.tryParse(self.location.href) ?? Uri();
}

/// {@macro worker_bee.get_worker_assignment}
Future<WorkerAssignment> getWorkerAssignment() async {
  // Errors in the preamble should be reported to the parent thread.
  void onError(Object e, StackTrace st) {
    self.postMessage(
      workerBeeSerializers
          .serialize(e, specifiedType: FullType.unspecified)
          .jsify(),
    );
  }

  return runTraced(() async {
    final assignmentCompleter = Completer<WorkerAssignment>.sync();
    late final JSExportedDartFunction jsOnMessageCallback;

    void onMessage(MessageEvent event) {
      final eventData = event.data;

      if (eventData.isA<JSString>()) {
        eventData as JSString;
        final state = eventData.toDart;

        self.removeEventListener('message', jsOnMessageCallback);

        final messagePort = event.ports.toDart.firstOrNull;
        final StreamChannel<LogEntry> logsChannel;
        if (messagePort is MessagePort) {
          logsChannel = MessagePortChannel<LogEntry>(messagePort);
        } else {
          // When MessagePort transfer is not available (e.g. dart2wasm main
          // thread), fall back to a no-op logs channel. Auth operations still
          // work; only log forwarding to the main thread is skipped.
          logsChannel = StreamChannel<LogEntry>(
            const Stream.empty(),
            NullStreamSink(),
          );
        }
        assignmentCompleter.complete(WorkerAssignment(state, logsChannel));
      } else {
        assignmentCompleter.completeError(
          StateError(
            'Invalid worker assignment: '
            '${workerBeeSerializers.serialize(eventData)}',
          ),
        );
      }
    }

    final onMessageCallback = Zone.current
        .bindUnaryCallback<void, MessageEvent>(onMessage);
    jsOnMessageCallback = onMessageCallback.toJS;

    self.addEventListener('message', jsOnMessageCallback);
    return assignmentCompleter.future;
  }, onError: onError);
}
