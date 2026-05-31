// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

import 'package:aws_common/aws_common.dart';
import 'package:test/test.dart';

/// Tests for the global constants in `aws_common`.
///
/// Note: `zIsWeb` uses `bool.fromEnvironment('dart.library.js_interop')` which
/// is `true` in both dart2js and dart2wasm web builds, and `false` on the Dart
/// VM. Since `dart test` runs on the VM, `zIsWeb` is expected to be `false`
/// here.
///
/// To verify WASM correctness, build with `flutter build web --wasm` and
/// confirm the app starts without `Platform._operatingSystem` errors.
/// See: https://github.com/aws-amplify/amplify-flutter/issues/6350
void main() {
  group('globals', () {
    group('zIsWeb', () {
      test('is false on Dart VM (test runtime)', () {
        // dart test runs on the VM where dart.library.js_interop is not defined
        expect(zIsWeb, isFalse);
      });

      test('is a compile-time constant', () {
        // Verify it can be used in const contexts
        const web = zIsWeb;
        expect(web, isFalse);
      });
    });

    group('zDebugMode', () {
      test('is accessible', () {
        // In test mode, debug mode should be true (no --define=dart.vm.product)
        expect(zDebugMode, isTrue);
      });
    });

    group('zReleaseMode', () {
      test('is false in test mode', () {
        expect(zReleaseMode, isFalse);
      });
    });

    group('zProfileMode', () {
      test('is false in test mode', () {
        expect(zProfileMode, isFalse);
      });
    });

    group('zIsFlutter', () {
      test('is false in pure Dart test', () {
        // dart test does not define dart.library.ui
        expect(zIsFlutter, isFalse);
      });
    });

    group('zIsWasm', () {
      test('is false on Dart VM (test runtime)', () {
        expect(zIsWasm, isFalse);
      });

      test('is a compile-time constant', () {
        const wasm = zIsWasm;
        expect(wasm, isFalse);
      });
    });
  });
}
