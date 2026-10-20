import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_analyzer/ad_configuration.dart';

void main() {
  test('Android debug uses the Android sample, never the iOS banner', () {
    expect(
      AdConfiguration.bannerIdFor(TargetPlatform.android, release: false),
      AdConfiguration.androidTestBannerId,
    );
    expect(
      AdConfiguration.androidTestBannerId,
      isNot(AdConfiguration.iosBannerId),
    );
  });

  test('Android release without configuration does not fall back to iOS', () {
    expect(
      AdConfiguration.bannerIdFor(TargetPlatform.android, release: true),
      isNull,
    );
  });

  test('iOS production banner remains unchanged in both modes', () {
    for (final release in [false, true]) {
      expect(
        AdConfiguration.bannerIdFor(TargetPlatform.iOS, release: release),
        'ca-app-pub-9003840415284448/3327652245',
      );
    }
  });

  test('desktop platforms never request mobile ads', () {
    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.macOS,
    ]) {
      expect(AdConfiguration.bannerIdFor(platform, release: true), isNull);
    }
  });
}
