package com.techsgardenhouse.garden_house_app

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (an androidx ComponentActivity) rather than
// FlutterActivity: the AR view (SceneView) needs one to request the camera
// permission and to install/update Google Play Services for AR.
class MainActivity : FlutterFragmentActivity()
