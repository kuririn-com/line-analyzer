import 'package:flutter/foundation.dart';

/// iOS production IDs stay unchanged. Android debug/profile use Google samples.
abstract final class AdConfiguration {
  static const iosBannerId = 'ca-app-pub-9003840415284448/3327652245';
  static const androidTestBannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const androidBannerId = String.fromEnvironment(
    'ANDROID_ADMOB_BANNER_ID',
  );

  static String? bannerIdFor(TargetPlatform platform, {required bool release}) {
    if (platform == TargetPlatform.iOS) return iosBannerId;
    if (platform == TargetPlatform.android) {
      if (!release) return androidTestBannerId;
      return androidBannerId.isEmpty ? null : androidBannerId;
    }
    return null;
  }

  static String? get bannerId =>
      kIsWeb ? null : bannerIdFor(defaultTargetPlatform, release: kReleaseMode);
}
