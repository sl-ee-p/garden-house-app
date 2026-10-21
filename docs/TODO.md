# Open items

Leftovers from the October 2026 quality pass, in priority order. Each entry
says what is wrong, where, and the suggested fix.

## 1. Tests for viewer snapshots

- **Problem:** `ViewerSnapshots` (`lib/house_viewer.dart`) now completes every
  snapshot request with null on a script error, a page-reported error, a bad
  answer, a timeout or disposal, but no test covers it yet.
- **Fix:** add `test/viewer_snapshots_test.dart`. Build it with a fake
  `runJavaScript` and a short `timeout`, then check the following: the timeout
  returns null; a throwing runner returns null; `{type: 'snapshot', error: ...}`
  returns null; a valid data URL returns the bytes; concurrent requests share
  one future; `cancel()` completes with null.

## 2. Asset server: unhandled error when the client disconnects

- **Problem:** in `AssetServer._handle` (`lib/asset_server.dart`), an error
  from `await response.close()` (for example, the WebView dropped the
  connection) is outside the `try` and escapes as an unhandled async error.
- **Fix:** wrap `response.close()` in its own `try`/`catch` and log the error
  with `debugPrint`. Wrap the `statusCode` assignment in the `catch` branch
  too, because it throws `StateError` once headers have been sent. Add a test
  that binds the server, opens a request and closes the socket early.

## 3. `lib/main.dart` error handling and lifecycle

- **`_openAr`:** `model.exportGlb()` (file I/O) can throw. The `finally`
  resets the button, but the error is unhandled and the user sees nothing.
  Fix: catch it and show a SnackBar such as "Impossibile preparare la
  casetta per la realtà aumentata, riprova".
- **`_withRender`:** errors from `shareConfig`, `requestQuote` or
  `_renderFile` are unhandled. Fix: catch them and show a SnackBar such as
  "Condivisione non riuscita, riprova".
- **`requestQuote`** (`lib/share_config.dart`): it uses `context` for
  `showModalBottomSheet` after awaiting the snapshot (done in `_withRender`),
  without checking that the context is still mounted. Fix: add
  `if (!context.mounted) return;` before the sheet, or pass the check in
  from `_withRender`.
- **Saving when the app goes to the background:** `HouseModel.flush()`
  exists, but nothing calls it when the app pauses or is detached, so a
  change made in the last 500 ms is lost if the OS kills the app. Fix: in
  `_ConfiguratorScreenState`, create an `AppLifecycleListener(onPause: ...,
  onDetach: ...)` that calls `flush()` on the loaded model, and dispose the
  listener in `dispose()`.
- **Load error screen:** `build()` shows the raw `${snap.error}`. Fix: show
  a friendly Italian message ("Impossibile caricare la casetta") and a
  "Riprova" button. The button should reassign the model future, which means
  making `_model` non-final and calling `setState(() => _model =
  HouseModel.load())`.

## 4. `lib/photo_screen.dart`

- **Missing `mounted` checks:** `_choosePhoto` calls `setState` after
  `pickImage` and uses the context after the permission await, without a
  `mounted` check. Fix: add `if (!mounted) return;` after each await.
- **Unhandled `pickImage` errors:** a `PlatformException` (for example, the
  camera is unavailable or access was denied on iOS) goes unhandled. Fix:
  catch it and call `_showMessage(...)`.
- **Unhandled errors in `_share`:** errors from `_compose`, the file write or
  `SharePlus` go unhandled. Fix: add a `catch` that shows a message.
- **iOS camera permission:** `Permission.camera.request()` runs on every
  platform. On iOS, permission_handler reports camera as denied unless the
  Podfile defines `PERMISSION_CAMERA=1`, and this repo has no Podfile, so
  "Scatta una foto" probably always fails there. The code comment confirms
  the check exists only for Android, where the app declares CAMERA. Fix:
  guard the check with `Platform.isAndroid`. On iOS, image_picker asks for
  the permission itself, using `NSCameraUsageDescription` (see item 6).

## 5. `lib/ar_screen.dart`

- **Unhandled AR errors:** in `_onTap`, a `PlatformException` from
  `addAnchor`/`addNode` goes unhandled, and the anchor may be leaked. Fix:
  add `catch (e)` that removes the anchor if it was added and calls
  `_showError(...)`.
- **No alternative when camera access is denied:** the denied state only
  offers "Apri impostazioni". Fix: add a second button, "Usa una foto", that
  calls the existing `_usePhoto`.

## 6. `ios/Runner/Info.plist`

- **Problem:** `NSCameraUsageDescription` and
  `NSPhotoLibraryUsageDescription` are missing. iOS kills the app as soon as
  image_picker opens the camera, and ARKit would need the camera key too.
- **Fix:** add both keys in Italian. Suggested texts: "La fotocamera serve
  per fotografare il giardino e vedere la casetta al suo posto." and "Serve
  per scegliere una foto del giardino dove posizionare la casetta."

  Note: on iOS, `checkArCoreAvailability()` returns `unsupported` because the
  `arcore` channel is Android-only. The app therefore always opens the photo
  screen there, so iOS needs nothing else for AR today.

## 7. Accessibility of the colour swatches

- **Problem:** `_Dot` (`lib/color_picker.dart`) is a 40x40 `GestureDetector`.
  That is smaller than the 48 dp minimum tap target, and screen readers get no
  button role or selected state; the tooltip is the only label.
- **Fix:** wrap the dot in a 48x48 hit area (for example `SizedBox.square(
  dimension: 48)` plus `Center`, with the gesture on the outer box and the
  `Wrap` spacing reduced to keep the layout). Add `Semantics(button: true,
  selected: selected, label: tooltip)`. Add a widget test that uses
  `meetsGuideline(androidTapTargetGuideline)`.

## 8. README and pubspec

- **Problem:** `README.md` is the Flutter template, and `pubspec.yaml` still
  has the template description ("A new Flutter project.") and its
  boilerplate comments.
- **Fix:** write a README that covers the following:
  - what the app is: an Italian 3D configurator for Techs garden houses;
  - features: 3D preview, structure and panel colours, 16 brochure panel
    finishes, undo, favourites, sharing, quote request, AR on ARCore
    devices, and a photo placement fallback;
  - a `lib/` architecture overview;
  - how to run it;
  - the vendored AR plugin patches (`third_party/ar_flutter_plugin_2/PATCHES.md`);
  - the asset pipeline: `tools/optimize_glb.py`, `tools/make_textures.py`
    and `PANEL_TEXTURES.md`;
  - testing.

  In `pubspec.yaml`, set a real description and remove the template comments.
  Do not change the dependencies or the SDK constraint.

## 9. Continuous integration

- **Problem:** there is no CI.
- **Fix:** add `.github/workflows/ci.yml` with these settings:
  - triggers: `push` and `pull_request`;
  - `permissions: contents: read`;
  - runner: `ubuntu-latest`;
  - `subosito/flutter-action` on the stable channel, pinned to a Flutter
    release whose Dart is at least 3.13.5 (the SDK constraint is
    `^3.13.5`; the local tooling suggested 3.47.7).

  The job runs `flutter pub get`, `dart format --output=none
  --set-exit-if-changed lib test`, `flutter analyze` and `flutter test`.

## Note for local development

Flutter 3.47.2 (Dart 3.13.2) can't resolve `sdk: ^3.13.5`. To work with it,
relax the constraint to `^3.13.0` locally, and restore `pubspec.yaml` and
`pubspec.lock` before committing.
