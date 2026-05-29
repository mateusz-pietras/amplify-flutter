# WASM Support Fix — Decision Log & Change Summary

**Branch**: `fix/wasm-support`  
**Date**: 2026-05-29  
**Base**: `main` @ `5d896cacb` (post-v2.11.0)  
**Issue**: [aws-amplify/amplify-flutter #6350](https://github.com/aws-amplify/amplify-flutter/issues/6350)  
**Related PR**: [aws-amplify/amplify-flutter #6356](https://github.com/aws-amplify/amplify-flutter/pull/6356) (stalled community fix by @tyllark)

---

## 1. Summary

This branch fixes the `amplify_flutter` SDK to work correctly when compiled to WebAssembly (`dart2wasm`). Previously, the SDK crashed immediately on startup with:

```
ParallelWaitError: Unsupported operation: Platform._operatingSystem
```

The fix consists of:
1. **Root cause**: Correcting the `zIsWeb` constant from a JavaScript-specific heuristic to a compile-time environment check
2. **Secondary issue**: Fixing conditional import order in `amplify_core` platform detection
3. **Worker compatibility**: Updating worker file naming for `build_web_compilers 4.x`
4. **Build system**: Adding `dart2wasm` build configuration to all `build.yaml` files

---

## 2. Decision Log

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Created fresh branch from `main` instead of rebasing PR #6356 | PR #6356 is 9 months old with merge conflicts against a repo that's had 7+ releases. Cherry-picking the logic is cleaner and avoids conflict resolution in build tooling |
| 2 | Used `bool.fromEnvironment('dart.library.js_interop')` for `zIsWeb` | This is the same approach Flutter uses for `kIsWeb` since v3.22. It's `true` in both `dart2js` and `dart2wasm`, `false` on VM. Confirmed correct by Dart team |
| 3 | Fixed `amplify_core/platform.dart` import order (not in original PR #6356) | Both `dart.library.io` and `dart.library.js_interop` are `true` in WASM. Dart's conditional export uses first-match-wins. Without this fix, `platform_io.dart` loads in WASM and calls `Platform.operatingSystem` (throws) |
| 4 | Updated worker `fallbackUrls` to `.dart2js.js` naming | `build_web_compilers 4.x` in multi-compiler mode outputs `.dart2js.js` instead of `.dart.js`. The `jsEntrypoint` getter already uses `workers.min.js` which is correct (it's the copy builder output) |
| 5 | Added `dart2wasm_args` to simple `build.yaml` files (followed existing pattern from `amplify_foundation_dart`) | Conservative approach — matches existing repo pattern, ensures `--define=dart.vm.product=true` is passed to dart2wasm compiler in release builds |
| 6 | Extended `worker_copy_builder` `generate_for` patterns to include `.dart2js.js`, `.wasm`, `.mjs` | The `WorkerCopyBuilder` already has `buildExtensions` for these patterns (it was updated previously). We just needed to tell it which files to process |
| 7 | Did NOT restructure worker `debug`/`release` targets to remove `compiler: dart2js` | Workers run as Web Workers (separate JS execution context). Even in a WASM app, workers can be JS. Full WASM worker compilation is a separate enhancement |
| 8 | Did NOT modify `dart:io` imports anywhere | They're legal in WASM (the library exists but is stubbed). The `zIsWeb` guard properly prevents `Platform.*` calls from being reached |
| 9 | Added unit tests for `zIsWeb` on VM only | WASM verification requires actual `flutter build web --wasm` which is a manual step. VM tests confirm the constant works correctly on the non-web side |

---

## 3. Changes Made

### Commit 1: `fix(aws_common): use dart.library.js_interop for zIsWeb WASM support`
**File**: `packages/aws_common/lib/src/util/globals.dart`

Changed:
```dart
const bool zIsWeb = identical(0, 0.0);
```
To:
```dart
const bool zIsWeb = bool.fromEnvironment('dart.library.js_interop');
```

This single line is the root cause of the WASM crash. The `identical(0, 0.0)` trick exploits JavaScript's unified number type but fails in WASM where `int` (i32) and `double` (f64) are distinct.

### Commit 2: `fix(amplify_core): check dart.library.js_interop before dart.library.io in platform export`
**File**: `packages/amplify_core/lib/src/platform/platform.dart`

Swapped conditional export order:
```dart
// Before (broken in WASM):
export 'platform_stub.dart'
    if (dart.library.io) 'platform_io.dart'
    if (dart.library.js_interop) 'platform_html.dart';

// After (correct):
export 'platform_stub.dart'
    if (dart.library.js_interop) 'platform_html.dart'
    if (dart.library.io) 'platform_io.dart';
```

### Commit 3: `fix(auth,secure_storage): update worker fallback URLs for build_web_compilers 4.x`
**Files** (6 total):
- `packages/auth/amplify_auth_cognito_dart/lib/src/asf/asf_worker.worker.js.dart`
- `packages/auth/amplify_auth_cognito_dart/lib/src/flows/device/confirm_device_worker.worker.js.dart`
- `packages/auth/amplify_auth_cognito_dart/lib/src/flows/srp/srp_device_password_verifier_worker.worker.js.dart`
- `packages/auth/amplify_auth_cognito_dart/lib/src/flows/srp/srp_init_worker.worker.js.dart`
- `packages/auth/amplify_auth_cognito_dart/lib/src/flows/srp/srp_password_verifier_worker.worker.js.dart`
- `packages/secure_storage/amplify_secure_storage_dart/lib/src/worker/secure_storage_worker.worker.js.dart`

Changed `workers.debug.dart.js` → `workers.debug.dart2js.js` and `workers.release.dart.js` → `workers.release.dart2js.js` in `fallbackUrls`.

### Commit 4: `chore: add dart2wasm build configuration to build.yaml files`
**Files** (14 total):
- Added `dart2wasm_args:` to release_options in 11 simple `build.yaml` files
- Extended `generate_for` patterns in 3 worker `build.yaml` files to include `.dart2js.js`, `.wasm`, and `.mjs` output patterns

### Commit 5: `test(aws_common): add unit tests for global constants including zIsWeb`
**File**: `packages/aws_common/test/util/globals_test.dart`

6 tests verifying global constants on VM runtime.

---

## 4. Issues Tackled

### Issue 1: `zIsWeb` returns `false` in WASM (THE ROOT CAUSE)

| Aspect | Detail |
|--------|--------|
| **Symptom** | `ParallelWaitError: Unsupported operation: Platform._operatingSystem` on WASM startup |
| **Root cause** | `identical(0, 0.0)` returns `true` only in JavaScript (where all numbers are doubles). In WASM, `int` and `double` are distinct types, so it returns `false` |
| **Impact** | Every `!zIsWeb && Platform.isX` guard evaluates `Platform.*` in WASM → throws `UnsupportedError` |
| **Fix** | `bool.fromEnvironment('dart.library.js_interop')` — the official Dart way to detect web builds |

### Issue 2: `amplify_core` platform conditional import order

| Aspect | Detail |
|--------|--------|
| **Symptom** | Even after fixing `zIsWeb`, code using `amplify_core`'s platform detection could still access `Platform.operatingSystem` |
| **Root cause** | `if (dart.library.io)` is checked before `if (dart.library.js_interop)`. In WASM both are `true`, first match wins → loads `platform_io.dart` |
| **Impact** | `platform_io.dart` calls `Platform.operatingSystem` which throws in WASM |
| **Fix** | Swap order so `js_interop` (web) is checked first |

### Issue 3: Worker file naming mismatch

| Aspect | Detail |
|--------|--------|
| **Symptom** | After startup fix, Auth `signIn` fails because workers can't be loaded (404/MIME errors) |
| **Root cause** | `build_web_compilers 4.x` outputs `.dart2js.js` (not `.dart.js`) when archive extractor is involved |
| **Impact** | `fallbackUrls` references non-existent files |
| **Fix** | Update references to match `build_web_compilers 4.x` output naming |

### Issue 4: Missing `dart2wasm` build configuration

| Aspect | Detail |
|--------|--------|
| **Symptom** | `--define=dart.vm.product=true` not passed to dart2wasm compiler in release builds |
| **Root cause** | `build.yaml` files only had `dart2js_args:` |
| **Impact** | WASM release builds might not enable product mode optimizations |
| **Fix** | Add `dart2wasm_args:` mirroring `dart2js_args:` (pattern from `amplify_foundation_dart`) |

---

## 5. Testing Strategy

### Automated (VM)
- ✅ `dart analyze lib/` — 0 issues in `aws_common`
- ✅ `dart analyze lib/` — 0 new issues in `amplify_core` (2 pre-existing warnings)
- ✅ `dart test` — 264 tests pass in `aws_common` (0 failures, 1 pre-existing skip)
- ✅ `dart test` — 156 tests pass in `amplify_core` (0 failures)
- ✅ New `globals_test.dart` — 6 tests pass

### Manual Verification (WASM — user must perform)
1. Build app with `fvm flutter build web --wasm`
2. Open in Chrome ≥119 (WASM auto-selected)
3. Verify no `Platform._operatingSystem` crash on startup
4. Verify Auth `signIn` succeeds (workers load correctly)

---

## 6. Remaining Work for Upstream Merge

| # | Item | Status | Notes |
|---|------|--------|-------|
| 1 | WASM runtime verification | ⏳ Manual | User verifies app builds and runs on WASM |
| 2 | Auth `signIn` E2E on WASM | ⏳ Manual | Requires Cognito test user |
| 3 | Rebase onto latest `main` at PR time | ⏳ | Our branch is based on current `main` |
| 4 | CI WASM build step | 📋 Nice-to-have | Add `flutter build web --wasm` to GitHub Actions |
| 5 | CHANGELOG updates per package | 📋 Required | Per AWS Amplify contribution guidelines |
| 6 | Version bumps | 📋 Required | Patch version bump for `aws_common` and `amplify_core` |
| 7 | AWS team review | 📋 Required | Request from @harsh62 or @ekjotmultani |
| 8 | `entrypoint loader exception` investigation | ⚠️ Unknown | Mentioned by @tyllark (Oct 2025), unclear if still relevant |

---

## 7. How to Verify Locally

```bash
# In your Flutter app that uses amplify_flutter:
# 1. Add dependency override pointing to local fork
# pubspec.yaml:
dependency_overrides:
  aws_common:
    path: ../packages/amplify-flutter/packages/aws_common
  amplify_core:
    path: ../packages/amplify-flutter/packages/amplify_core

# 2. Build with WASM
fvm flutter build web --wasm

# 3. Serve and test
cd build/web && python3 -m http.server 8080
# Open http://localhost:8080 in Chrome ≥119
# Verify: no console errors, app initializes, auth works
```
