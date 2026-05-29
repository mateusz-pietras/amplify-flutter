# PR Description: WebAssembly (WASM) Support

> **Suggested title**: `fix: Add WebAssembly (dart2wasm) support`

---

## Description

This PR adds WebAssembly (dart2wasm) support to the Amplify Flutter SDK, fixing a critical crash that occurs when Flutter web apps using `amplify_flutter` are compiled to WASM.

Since Flutter 3.22+, `flutter build web` produces both a dart2js and a dart2wasm build by default, with modern browsers (Chrome ≥119) automatically selecting WASM. This means **every Flutter web app using Amplify crashes on startup** on modern browsers unless explicitly built with `--no-wasm`.

## Problem

When compiled to WASM, the SDK crashes immediately with:
```
ParallelWaitError: Unsupported operation: Platform._operatingSystem
```

**Root cause**: The `zIsWeb` constant in `aws_common` used `identical(0, 0.0)` — a JavaScript-era trick that exploits JS's unified number type. In WebAssembly, integers and doubles are distinct types (`i32`/`f64`), so this returns `false`, causing all `!zIsWeb && Platform.isAndroid` guards to evaluate `Platform.*` — which always throws `UnsupportedError` in WASM.

## Solution

1. **`zIsWeb` fix** — Replace `identical(0, 0.0)` with `bool.fromEnvironment('dart.library.js_interop')`, matching Flutter's own `kIsWeb` implementation since v3.22

2. **Platform conditional import order** — Fix `amplify_core/lib/src/platform/platform.dart` to check `dart.library.js_interop` before `dart.library.io` (both are `true` in WASM; first-match-wins)

3. **Worker file naming** — Update `fallbackUrls` in generated worker files to match `build_web_compilers 4.x` output naming (`.dart2js.js` instead of `.dart.js`)

4. **Build configuration** — Add `dart2wasm_args` to `build.yaml` files and extend `worker_copy_builder` patterns for WASM outputs

5. **Full monorepo audit** — Identified and fixed all remaining files with `io`-before-`js_interop` conditional imports:
   - `auth/amplify_auth_cognito_dart` — `asf_device_info_collector.dart` (critical: signIn crash)
   - `api/amplify_api_dart` — `is_windows/is_windows.dart` (WebSocket blob policy)
   - `aws_common` — `aws_config_value.dart`, `aws_path_provider.dart`, `config_file/file_loader.dart`

## Related Issues

- **Fixes** #6350 — WebAssembly Support
- **Supersedes** #6356 — Original community PR by @tyllark (stalled since Sep 2025, merge conflicts)

## Acknowledgments

This work builds on the extensive research and initial implementation by **@tyllark** in PR #6356, who:
- Identified the root cause and wrote the one-line fix
- Filed and resolved two upstream blockers ([dart-lang/core #913](https://github.com/dart-lang/core/issues/913) for `crypto`, [dart-lang/build #4230](https://github.com/dart-lang/build/issues/4230) for `build_web_compilers`)
- Implemented worker build system changes across 7 commits

Both upstream blockers have been resolved and released (`crypto 3.0.7`, `build_web_compilers 4.6.0`).

## Packages Modified

| Package | Change |
|---------|--------|
| `aws_common` | Fix `zIsWeb` constant; fix `aws_config_value.dart`, `aws_path_provider.dart`, `config_file/file_loader.dart` import guards; add `dart2wasm_args` to `build.yaml`; add unit tests |
| `amplify_core` | Fix conditional export order in `platform.dart`, add `dart2wasm_args` to `build.yaml` |
| `amplify_auth_cognito_dart` | Fix `asf_device_info_collector.dart` import order; update worker fallback URLs; extend `build.yaml` for WASM outputs |
| `amplify_api_dart` | Fix `is_windows/is_windows.dart` export guard; add `dart2wasm_args` to `build.yaml` |
| `amplify_secure_storage_dart` | Update worker fallback URLs, extend `build.yaml` for WASM outputs |
| `aws_signature_v4` | Add `dart2wasm_args` to `build.yaml` |
| `amplify_analytics_pinpoint_dart` | Add `dart2wasm_args` to `build.yaml` |
| `amplify_auth_cognito_test` | Add `dart2wasm_args` to `build.yaml` |
| `amplify_secure_storage_test` | Add `dart2wasm_args` to `build.yaml` |
| `worker_bee/e2e` | Extend `build.yaml` for WASM outputs |
| `example_common` | Add `dart2wasm_args` to `build.yaml` |

## Testing

### Automated
- ✅ `dart analyze lib/` passes on `aws_common` (0 issues)
- ✅ `dart test` passes on `aws_common` (264 tests, 0 failures)
- ✅ `dart analyze lib/` passes on `amplify_core` (0 new issues)
- ✅ `dart test` passes on `amplify_core` (156 tests, 0 failures)
- ✅ `dart analyze lib/src/graphql/web_socket/blocs/is_windows/` passes on `amplify_api_dart` (0 issues)
- ✅ New `globals_test.dart` verifies `zIsWeb` behavior on VM

### Manual
- ✅ `flutter build web --wasm` completes without errors
- ✅ App starts without `Platform._operatingSystem` crash on Chrome (WASM)
- ✅ dart2js build (`flutter build web --no-wasm`) still works (no regression)

## Technical Details

### Why `identical(0, 0.0)` fails in WASM

| Runtime | `identical(0, 0.0)` | Correct `zIsWeb`? |
|---------|---------------------|-------------------|
| Dart VM | `false` | ✅ (not web) |
| dart2js | `true` | ✅ (is web) |
| dart2wasm | `false` | ❌ (should be web) |

### Why `dart.library.io` is `true` in WASM

In dart2js, `dart:io` is not available (`dart.library.io = false`), so conditional imports using `if (dart.library.io)` correctly fall through. In dart2wasm, `dart:io` exists as a stub that throws `UnsupportedError` at runtime (`dart.library.io = true`). This means any conditional import that checks `dart.library.io` before `dart.library.js_interop` will incorrectly select the IO implementation in WASM.

### `dart.library.js_interop` — the correct check

`dart.library.js_interop` is `true` in both dart2js and dart2wasm web builds, and `false` on native platforms. This is the same constant Flutter uses for `kIsWeb`:

```dart
// flutter/lib/src/foundation/constants.dart:
const bool kIsWeb = bool.fromEnvironment('dart.library.js_interop');
```

## Breaking Changes

**None.** This is a bug fix. The `zIsWeb` constant was always *intended* to detect web builds — it now correctly does so for WASM in addition to JavaScript.

## Checklist

- [x] Follows [Amplify Flutter Contributing Guidelines](https://github.com/aws-amplify/amplify-flutter/blob/main/CONTRIBUTING.md)
- [x] Tests added/updated
- [x] `dart analyze` passes
- [x] `dart test` passes
- [x] No breaking changes
- [x] Documentation updated (doc comments on `zIsWeb`)
