package com.uhg0.ar_flutter_plugin_2

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import com.google.ar.core.ArCoreApk

class ArFlutterPlugin: FlutterPlugin, ActivityAware {
    private var activity: Activity? = null
    private var lifecycle: Lifecycle? = null
    private var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding? = null
    private var arCoreChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        flutterPluginBinding = binding
        arCoreChannel = MethodChannel(binding.binaryMessenger, "ar_flutter_plugin_2/arcore").apply {
            setMethodCallHandler { call, result ->
                if (call.method == "checkAvailability") {
                    checkAvailability(binding.applicationContext) { result.success(it) }
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        arCoreChannel?.setMethodCallHandler(null)
        arCoreChannel = null
        flutterPluginBinding = null
    }

    /** Reports ArCoreApk.Availability's name, waiting out the transient states. */
    private fun checkAvailability(context: Context, attempt: Int = 0, done: (String) -> Unit) {
        val availability = try {
            ArCoreApk.getInstance().checkAvailability(context)
        } catch (e: Exception) {
            done(ArCoreApk.Availability.UNKNOWN_ERROR.name)
            return
        }
        if (availability.isTransient && attempt < 25) {
            Handler(Looper.getMainLooper()).postDelayed(
                { checkAvailability(context, attempt + 1, done) },
                200,
            )
        } else {
            done(availability.name)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        lifecycle = (activity as LifecycleOwner).lifecycle
        
        // Enregistrer la factory une fois que nous avons l'activité et le lifecycle
        flutterPluginBinding?.let { flutterBinding ->
            flutterBinding.platformViewRegistry.registerViewFactory(
                "ar_flutter_plugin_2",
                ArViewFactory(
                    messenger = flutterBinding.binaryMessenger,
                    activity = activity!!,
                    lifecycle = lifecycle!!
                )
            )
        }
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
        lifecycle = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        lifecycle = (activity as LifecycleOwner).lifecycle
        
        // Réenregistrer la factory après les changements de configuration
        flutterPluginBinding?.let { flutterBinding ->
            flutterBinding.platformViewRegistry.registerViewFactory(
                "ar_flutter_plugin_2",
                ArViewFactory(
                    messenger = flutterBinding.binaryMessenger,
                    activity = activity!!,
                    lifecycle = lifecycle!!
                )
            )
        }
    }

    override fun onDetachedFromActivity() {
        activity = null
        lifecycle = null
    }
}
