# Local patches

Vendored from `ar_flutter_plugin_2` 0.0.3 on pub.dev (MIT, see LICENSE), with
the example app, docs and tests removed.

- `ArView.kt`: plane finding is applied through the session configuration
  instead of only to the session that exists when `init` is called. If ARCore
  creates the session later (e.g. after installing/updating Google Play
  Services for AR), planes were never detected and the view stayed stuck on
  "point your camera".
- `ArView.kt`: never calls `session.update()` itself. ARSceneView already
  updates the session once per frame; the plugin's extra `update()` calls (in
  `onFrame`, on tap and in `getCameraPose`) produced frames where
  `getUpdatedTrackables()` was empty, so `onPlaneDetected` never fired. The
  per-frame logic now runs in `onSessionUpdated` and taps hit-test
  `sceneView.frame`.
- `ArView.kt`: passes the activity to ARSceneView as `sharedActivity`. SceneView
  can't find it from the platform view's context, and without it skips the
  camera-permission and ARCore install/update flow, so with a missing or
  outdated ARCore the session silently failed (black camera). Requires the
  app's MainActivity to be a `FlutterFragmentActivity`.
- `ArView.kt`: session failures (`onSessionFailed`) are sent to Dart via
  `onError` as the exception class name, and re-sent on `init` because they
  can happen before Dart listens.
- `ArView.kt`: depth mode stays disabled (unused, expensive per frame).
- `ArView.kt`: no longer loads `environments/evening_meadow_2k.hdr`; SceneView's
  default neutral environment is used. The 6.7 MB HDR is deleted.
- `assets/models/Chicken_01.gltf` sample deleted.
- New `ar_flutter_plugin_2/arcore` channel (`ArFlutterPlugin.kt`) and
  `lib/arcore_availability.dart`: `checkArCoreAvailability()` asks
  `ArCoreApk.checkAvailability` whether the device supports ARCore.
- `ar_session_manager.dart`: forwards the native `onTrackingFailure` event
  through `ARSessionManager.onTrackingFailure`.
