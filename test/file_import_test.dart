import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:line_analyzer/main.dart';

final class FixtureFile extends PlatformFile {
  @override
  String get name => 'android-talk.txt';

  @override
  Future<Uint8List> readAsBytes() async =>
      File('test/fixtures/android-talk.txt').readAsBytesSync();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FixturePicker extends FilePickerPlatform {
  bool cancel = false;
  bool fail = false;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    expect(type, FileType.custom);
    expect(allowedExtensions, ['txt']);
    if (fail) throw const FileSystemException('Read failed');
    return cancel ? null : FixtureFile();
  }
}

void main() {
  final original = FilePickerPlatform.instance;
  late FixturePicker picker;

  setUp(() {
    picker = FixturePicker();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() => FilePickerPlatform.instance = original);

  Future<void> openPicker(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const LineTalkAnalyzerApp());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('トーク履歴を読み込む'));
    await tester.tap(find.text('トーク履歴を読み込む'));
    await tester.pumpAndSettle();
  }

  testWidgets('Japanese LINE txt opens the existing analysis screen', (
    tester,
  ) async {
    await openPicker(tester);
    expect(find.text('android-talk.txt'), findsOneWidget);
    expect(find.text('解析中のトーク履歴'), findsOneWidget);
    expect(find.text('総メッセージ数'), findsOneWidget);
    expect(find.text('8'), findsWidgets);
    expect(find.textContaining('テスト太郎'), findsWidgets);
    expect(find.textContaining('テスト花子'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel leaves the import button usable', (tester) async {
    picker.cancel = true;
    await openPicker(tester);
    expect(find.text('解析中のトーク履歴'), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(button.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read errors are shown and the user can try again', (
    tester,
  ) async {
    picker.fail = true;
    await openPicker(tester);
    expect(find.textContaining('ファイルの読み込みに失敗しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
