import 'dart:convert';
import 'dart:typed_data';

class LineTalkStats {
  const LineTalkStats({
    required this.fileName,
    required this.messageCount,
    required this.participants,
  });

  final String fileName;
  final int messageCount;
  final List<String> participants;
}

final _messageLine = RegExp(
  r'^(\d{1,2}:\d{2}(?::\d{2})?)\t([^\t]+)\t(.*)$',
);

final _systemLine = RegExp(
  r'^(\d{1,2}:\d{2}(?::\d{2})?)\t([^\t]+)$',
);

final _dateLine = RegExp(
  r'^('
  r'\d{4}[./年]\d{1,2}[./月]\d{1,2}'
  r'|[A-Za-z]{3},?\s+\d{1,2}/\d{1,2}/\d{4}'
  r')',
);

String decodeTalkBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i + 1] | (bytes[i] << 8));
    }
    return String.fromCharCodes(units);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return utf8.decode(bytes, allowMalformed: true);
  }
}

LineTalkStats parseLineTalk(String text, {String fileName = ''}) {
  final participants = <String>[];
  final seen = <String>{};
  var messageCount = 0;

  for (final rawLine in text.split(RegExp(r'\r\n|\n|\r'))) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('[LINE]')) continue;
    if (line.startsWith('保存日時') || line.startsWith('Saved on')) continue;
    if (_dateLine.hasMatch(line)) continue;
    if (_systemLine.hasMatch(line) && !_messageLine.hasMatch(line)) continue;

    final match = _messageLine.firstMatch(line);
    if (match == null) continue;

    final name = match.group(2)!.trim();
    if (name.isEmpty) continue;

    messageCount += 1;
    if (seen.add(name)) {
      participants.add(name);
    }
  }

  return LineTalkStats(
    fileName: fileName,
    messageCount: messageCount,
    participants: participants,
  );
}
