import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:line_analyzer/android_ad_consent.dart';

class FakeConsentInformation extends ConsentInformation {
  bool updateFails = false;
  bool mayRequestAds = false;
  final events = <String>[];

  @override
  void requestConsentInfoUpdate(
    ConsentRequestParameters params,
    OnConsentInfoUpdateSuccessListener successListener,
    OnConsentInfoUpdateFailureListener failureListener,
  ) {
    events.add('update');
    if (updateFails) {
      failureListener(FormError(errorCode: 2, message: 'Offline'));
    } else {
      successListener();
    }
  }

  @override
  Future<bool> canRequestAds() async {
    events.add('canRequestAds');
    return mayRequestAds;
  }

  @override
  Future<PrivacyOptionsRequirementStatus>
  getPrivacyOptionsRequirementStatus() async =>
      PrivacyOptionsRequirementStatus.required;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final original = ConsentInformation.instance;
  const channel = MethodChannel('plugins.flutter.io/google_mobile_ads/ump');
  late FakeConsentInformation consent;

  setUp(() {
    consent = FakeConsentInformation();
    ConsentInformation.instance = consent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          consent.events.add(call.method);
          return null;
        });
  });

  tearDown(() {
    ConsentInformation.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('waits for consent form before deciding whether ads may load', () async {
    consent.mayRequestAds = true;
    expect(await AndroidAdConsent.prepare(), isTrue);
    expect(consent.events, [
      'update',
      'UserMessagingPlatform#loadAndShowConsentFormIfRequired',
      'canRequestAds',
    ]);
  });

  test('no consent means no production ad request', () async {
    expect(await AndroidAdConsent.prepare(), isFalse);
  });

  test('offline update respects cached SDK consent', () async {
    consent.updateFails = true;
    expect(await AndroidAdConsent.prepare(), isFalse);
    consent.mayRequestAds = true;
    expect(await AndroidAdConsent.prepare(), isTrue);
  });

  test('required privacy options are available to reopen', () async {
    expect(await AndroidAdConsent.privacyOptionsRequired, isTrue);
    await AndroidAdConsent.showPrivacyOptions();
    expect(consent.events, ['UserMessagingPlatform#showPrivacyOptionsForm']);
  });
}
