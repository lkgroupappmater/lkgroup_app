import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Uses Flutter's existing platform bridge so installed clients receive this
/// behavior through their normal code update. Device sound/haptic settings apply.
class NotificationAlert {
  static Future<void> play() async {
    try {
      await SystemSound.play(defaultTargetPlatform == TargetPlatform.iOS
          ? SystemSoundType.alert : SystemSoundType.click);
      await HapticFeedback.vibrate();
    } on PlatformException {
      // Device audio policy must not block the visible alert.
    } on MissingPluginException {
      // Tests and unsupported desktop hosts still show the visible alert.
    }
  }
}
