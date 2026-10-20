import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Android production requests wait for UMP. No conversation text is supplied.
abstract final class AndroidAdConsent {
  static Future<bool> prepare() async {
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((_) {
          if (!updated.isCompleted) updated.complete();
        });
      },
      (_) {
        if (!updated.isCompleted) updated.complete();
      },
    );
    await updated.future;
    return ConsentInformation.instance.canRequestAds();
  }

  static Future<bool> get privacyOptionsRequired async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  static Future<void> showPrivacyOptions() async {
    final closed = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((_) => closed.complete());
    await closed.future;
  }
}
