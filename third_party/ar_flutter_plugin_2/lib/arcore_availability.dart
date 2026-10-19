import 'package:flutter/services.dart';

/// Whether this device can run ARCore at all, without opening an AR view.
enum ArCoreAvailability {
  /// Supported; ARCore may still need installing/updating, which the AR view
  /// offers to do.
  supported,

  /// The device isn't ARCore-certified (or has no Google Play).
  unsupported,

  /// ARCore couldn't tell (e.g. offline on first run).
  unknown,
}

const _channel = MethodChannel('ar_flutter_plugin_2/arcore');

Future<ArCoreAvailability> checkArCoreAvailability() async {
  final String? name;
  try {
    name = await _channel.invokeMethod<String>('checkAvailability');
  } on PlatformException {
    return ArCoreAvailability.unknown;
  } on MissingPluginException {
    return ArCoreAvailability.unsupported; // not Android
  }
  if (name == null) return ArCoreAvailability.unknown;
  if (name.startsWith('SUPPORTED_')) return ArCoreAvailability.supported;
  if (name.startsWith('UNSUPPORTED_')) return ArCoreAvailability.unsupported;
  return ArCoreAvailability.unknown;
}
