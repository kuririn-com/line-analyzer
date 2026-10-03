import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    MobileAds.instance.initialize();
  }

  runApp(const LineTalkAnalyzerApp());
}

class LineTalkAnalyzerApp extends StatelessWidget {
  const LineTalkAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LINEトーク分析',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja', 'JP'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F8F7),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF06C755),
        ),
      ),
      home: const LineTalkAnalyzerPage(),
    );
  }
}

class LineTalkAnalyzerPage extends StatefulWidget {
  const LineTalkAnalyzerPage({super.key});

  @override
  State<LineTalkAnalyzerPage> createState() =>
      _LineTalkAnalyzerPageState();
}

class _LineTalkAnalyzerPageState
    extends State<LineTalkAnalyzerPage> {
  String _fileName = '';
  String _talkText = '';

  int _totalMessages = 0;

  final Set<String> _participants = {};

  final List<int> _weekdayCounts =
      List<int>.filled(7, 0);

  int _favoriteCount = 0;
  int _romanticFavoriteCount = 0;
  int _favoriteQuestionCount = 0;
  int _objectFavoriteCount = 0;
  int _unknownFavoriteCount = 0;

  int _romanticMorningCount = 0;
  int _romanticDaytimeCount = 0;
  int _romanticEveningCount = 0;
  int _romanticNightCount = 0;
  int _romanticLateNightCount = 0;

  final List<_FavoriteEntry> _favoriteEntries = [];

  int _thanksCount = 0;
  int _lateNightCount = 0;

  final TextEditingController _wordController =
      TextEditingController();

  String _checkedWord = '';
  int _wordCount = 0;

  final Map<String, int> _replyTimeTotals = {};
  final Map<String, int> _replyCounts = {};
  final Map<String, double> _averageReplyMinutes = {};

  int _compatibilityScore = 0;
  int _lastingScore = 0;

  bool _isLoading = false;
  String? _errorMessage;

  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  final RegExp _messagePattern =
      RegExp(r'^(\d{2}):(\d{2})');

  // 日付ヘッダー用。先頭だけでなく行内の形式も認識する。
  // メッセージ行は先に時刻判定するので、本文中の日付を誤認しない。
  final RegExp _datePattern = RegExp(
    r'(\d{4})\s*[./-]\s*(\d{1,2})\s*[./-]\s*(\d{1,2})',
  );

  final RegExp _japaneseDatePattern = RegExp(
    r'(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日',
  );

  static const List<String> _weekdays = [
    '月',
    '火',
    '水',
    '木',
    '金',
    '土',
    '日',
  ];

  final List<_TalkMessage> _messages = [];

  final Map<DateTime, int> _dailyMessageCounts = {};
  DateTime? _latestTalkDate;
  DateTime? _selectedSearchDate;

  @override
  void initState() {
    super.initState();

    if (!kIsWeb) {
      _loadBannerAd();
    }
  }

  void _loadBannerAd() {
    final BannerAd bannerAd = BannerAd(
      adUnitId:
          'ca-app-pub-9003840415284448/3327652245',
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }

          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerAdReady = true;
          });
        },
        onAdFailedToLoad: (
          Ad ad,
          LoadAdError error,
        ) {
          ad.dispose();

          if (!mounted) {
            return;
          }

          setState(() {
            _bannerAd = null;
            _isBannerAdReady = false;
          });
        },
      ),
    );

    _bannerAd = bannerAd;
    bannerAd.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final PlatformFile? file =
          await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (file == null) {
        if (!mounted) {
          return;
        }

        setState(() {
          _isLoading = false;
        });

        return;
      }

      final Uint8List bytes =
          await file.readAsBytes();

      final String text = utf8.decode(
        bytes,
        allowMalformed: true,
      );

      _analyzeTalk(text);

      if (!mounted) {
        return;
      }

      setState(() {
        _fileName = file.name;
        _talkText = text;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'ファイルの読み込みに失敗しました。\n$e';
      });
    }
  }

  DateTime? _parseDateHeader(String line) {
    Match? match = _datePattern.firstMatch(line);

    match ??= _japaneseDatePattern.firstMatch(line);

    if (match == null) {
      return null;
    }

    final int? year = int.tryParse(match.group(1)!);
    final int? month = int.tryParse(match.group(2)!);
    final int? day = int.tryParse(match.group(3)!);

    if (year == null || month == null || day == null) {
      return null;
    }

    final DateTime date = DateTime(year, month, day);

    if (date.year != year ||
        date.month != month ||
        date.day != day) {
      return null;
    }

    return DateTime(date.year, date.month, date.day);
  }

  void _analyzeTalk(String text) {
    _totalMessages = 0;

    _participants.clear();
    _messages.clear();
    _dailyMessageCounts.clear();
    _latestTalkDate = null;
    _selectedSearchDate = null;

    _replyTimeTotals.clear();
    _replyCounts.clear();
    _averageReplyMinutes.clear();

    for (int i = 0;
        i < _weekdayCounts.length;
        i++) {
      _weekdayCounts[i] = 0;
    }

    _favoriteCount = 0;
    _romanticFavoriteCount = 0;
    _favoriteQuestionCount = 0;
    _objectFavoriteCount = 0;
    _unknownFavoriteCount = 0;
    _romanticMorningCount = 0;
    _romanticDaytimeCount = 0;
    _romanticEveningCount = 0;
    _romanticNightCount = 0;
    _romanticLateNightCount = 0;
    _favoriteEntries.clear();

    _thanksCount = 0;
    _lateNightCount = 0;

    _checkedWord = '';
    _wordCount = 0;

    DateTime? currentDate;

    final List<String> lines =
        text.split(RegExp(r'\r?\n'));

    for (final String rawLine in lines) {
      final String line = rawLine
          .replaceFirst('\uFEFF', '')
          .trimRight();

      if (line.isEmpty) {
        continue;
      }

      // 先にメッセージ行を判定する。
      // これにより、本文中に「2025/01/01」などが書かれていても
      // 日付ヘッダーと誤認しない。
      final Match? messageMatch =
          _messagePattern.firstMatch(line);

      if (messageMatch == null) {
        final DateTime? parsedDate =
            _parseDateHeader(line);

        if (parsedDate != null) {
          currentDate = parsedDate;
        }

        continue;
      }

      final int hour =
          int.tryParse(messageMatch.group(1)!) ?? 0;

      final int minute =
          int.tryParse(messageMatch.group(2)!) ?? 0;

      if (hour < 0 ||
          hour > 23 ||
          minute < 0 ||
          minute > 59) {
        continue;
      }

      final List<String> elements = line
          .trim()
          .split(RegExp(r'\s+'));

      if (elements.length < 2) {
        continue;
      }

      final String participant =
          elements[1].trim();

      if (participant.isEmpty) {
        continue;
      }

      // LINEの「送信を取り消しました」は実際のトークとして集計しない。
      if (line.endsWith('送信を取り消しました')) {
        continue;
      }

      _participants.add(participant);

      _totalMessages++;

      final _TalkMessage message =
          _TalkMessage(
        participant: participant,
        hour: hour,
        minute: minute,
        date: currentDate,
        rawText: line,
      );

      _messages.add(message);

      _favoriteCount += _countWordVariants(
        line,
        _favoriteWords,
      );

      _thanksCount += _countWordVariants(
        line,
        _thanksWords,
      );

      if (hour >= 2 && hour <= 4) {
        _lateNightCount++;
      }

      if (currentDate != null) {
        final int weekdayIndex =
            currentDate.weekday - 1;

        if (weekdayIndex >= 0 &&
            weekdayIndex < 7) {
          _weekdayCounts[weekdayIndex]++;
        }

        final DateTime dateKey = DateTime(
          currentDate.year,
          currentDate.month,
          currentDate.day,
        );

        _dailyMessageCounts[dateKey] =
            (_dailyMessageCounts[dateKey] ?? 0) + 1;

        if (_latestTalkDate == null ||
            dateKey.isAfter(_latestTalkDate!)) {
          _latestTalkDate = dateKey;
        }
      }
    }

    _analyzeFavoriteExpressions();

    _calculateReplySpeed();

    if (_wordController.text.trim().isNotEmpty) {
      _calculateFreeWordInternal(
        _wordController.text.trim(),
      );
    }

    _calculateCompatibility();
  }

  static const List<String> _favoriteObjectWords = [
    'ミセス',
    'Mrs. GREEN APPLE',
    'Mrs.GREEN APPLE',
    'サザン',
    'YOASOBI',
    'Ado',
    'あいみょん',
    '米津玄師',
    'Official髭男dism',
    'ヒゲダン',
    'King Gnu',
    '藤井風',
    'Vaundy',
    'back number',
    'ONE OK ROCK',
    'RADWIMPS',
    'Saucy Dog',
    'sumika',
    'Snow Man',
    'BTS',
    'K-POP',
    'ディズニー',
    'ポケモン',
    'アニメ',
    '漫画',
    'マンガ',
    '映画',
    'ドラマ',
    '曲',
    '音楽',
    '歌',
    'ゲーム',
    '猫',
    'ネコ',
    '犬',
    '料理',
    'ラーメン',
    '寿司',
    'カフェ',
    '店',
    '洋服',
    '服',
    'ブランド',
    '食べ物',
    'スイーツ',
    'お菓子',
  ];

  String _messageBody(_TalkMessage message) {
    final List<String> elements = message.rawText
        .trim()
        .split(RegExp(r'\s+'));

    if (elements.length <= 2) {
      return '';
    }

    return elements.sublist(2).join(' ').trim();
  }

  bool _containsAny(String text, List<String> words) {
    for (final String word in words) {
      if (word.isNotEmpty && text.contains(word)) {
        return true;
      }
    }

    return false;
  }

  bool _containsDirectTarget(
    String body,
    String sender,
  ) {
    final RegExp directTargetPattern = RegExp(
      r'(私|僕|俺|うち|あなた|君|きみ|お前|自分|相手).*(大好き|好き)',
    );

    if (directTargetPattern.hasMatch(body)) {
      return true;
    }

    for (final String participant in _participants) {
      if (participant.isEmpty || participant == sender) {
        continue;
      }

      if (body.contains(participant) &&
          _containsAny(body, _favoriteWords)) {
        return true;
      }
    }

    return false;
  }

  bool _isFavoriteQuestion(String body) {
    if (!body.contains('好き')) {
      return false;
    }

    return body.contains('好き？') ||
        body.contains('好き?') ||
        body.contains('好きなの') ||
        body.contains('好きなん') ||
        body.contains('好きかな');
  }

  bool _looksLikeRomanticPhrase(String body) {
    final String normalized = body
        .replaceAll('！', '')
        .replaceAll('!', '')
        .replaceAll('。', '')
        .replaceAll('、', '')
        .replaceAll('♪', '')
        .trim();

    final RegExp pattern = RegExp(
      r'^(大好き|だいすき|ダイスキ|好き|すき|スキ)(だよ|だね|だな|なんだ|なんだよ|です|かも|すぎる|だよね|だった)?[\s💕❤️💗😊🥰☺️]*$',
    );

    return pattern.hasMatch(normalized);
  }

  _FavoriteCategory _classifyFavoriteMessage(
    _TalkMessage message,
  ) {
    final String body = _messageBody(message);

    if (body.isEmpty ||
        !_containsAny(body, _favoriteWords)) {
      return _FavoriteCategory.unknown;
    }

    if (_isFavoriteQuestion(body) &&
        _containsDirectTarget(body, message.participant)) {
      return _FavoriteCategory.question;
    }

    if (_containsAny(body, _favoriteObjectWords)) {
      return _FavoriteCategory.object;
    }

    if (_containsDirectTarget(body, message.participant) ||
        _looksLikeRomanticPhrase(body)) {
      return _FavoriteCategory.romantic;
    }

    return _FavoriteCategory.unknown;
  }

  void _analyzeFavoriteExpressions() {
    _romanticFavoriteCount = 0;
    _favoriteQuestionCount = 0;
    _objectFavoriteCount = 0;
    _unknownFavoriteCount = 0;

    _romanticMorningCount = 0;
    _romanticDaytimeCount = 0;
    _romanticEveningCount = 0;
    _romanticNightCount = 0;
    _romanticLateNightCount = 0;

    _favoriteEntries.clear();

    for (final _TalkMessage message in _messages) {
      final int count = _countWordVariants(
        _messageBody(message),
        _favoriteWords,
      );

      if (count == 0) {
        continue;
      }

      final _FavoriteCategory category =
          _classifyFavoriteMessage(message);

      if (category == _FavoriteCategory.romantic) {
        _romanticFavoriteCount += count;

        if (message.hour >= 5 && message.hour <= 10) {
          _romanticMorningCount += count;
        } else if (message.hour >= 11 && message.hour <= 16) {
          _romanticDaytimeCount += count;
        } else if (message.hour >= 17 && message.hour <= 20) {
          _romanticEveningCount += count;
        } else if (message.hour >= 21 && message.hour <= 23) {
          _romanticNightCount += count;
        } else {
          _romanticLateNightCount += count;
        }
      } else if (category == _FavoriteCategory.question) {
        _favoriteQuestionCount += count;
      } else if (category == _FavoriteCategory.object) {
        _objectFavoriteCount += count;
      } else {
        _unknownFavoriteCount += count;
      }

      _favoriteEntries.add(
        _FavoriteEntry(
          category: category,
          count: count,
          message: message,
        ),
      );
    }
  }

  void _calculateReplySpeed() {
    _replyTimeTotals.clear();
    _replyCounts.clear();
    _averageReplyMinutes.clear();

    if (_messages.length < 2) {
      return;
    }

    for (int i = 1;
        i < _messages.length;
        i++) {
      final _TalkMessage previous =
          _messages[i - 1];

      final _TalkMessage current =
          _messages[i];

      if (previous.participant ==
          current.participant) {
        continue;
      }

      if (previous.date != null &&
          current.date != null) {
        final bool sameDay =
            previous.date!.year ==
                    current.date!.year &&
                previous.date!.month ==
                    current.date!.month &&
                previous.date!.day ==
                    current.date!.day;

        if (!sameDay) {
          continue;
        }
      }

      final int previousMinutes =
          previous.hour * 60 +
              previous.minute;

      final int currentMinutes =
          current.hour * 60 +
              current.minute;

      final int difference =
          currentMinutes - previousMinutes;

      if (difference <= 0) {
        continue;
      }

      if (difference > 720) {
        continue;
      }

      _replyTimeTotals[current.participant] =
          (_replyTimeTotals[current.participant] ??
                  0) +
              difference;

      _replyCounts[current.participant] =
          (_replyCounts[current.participant] ??
                  0) +
              1;
    }

    for (final String participant
        in _participants) {
      final int total =
          _replyTimeTotals[participant] ?? 0;

      final int count =
          _replyCounts[participant] ?? 0;

      if (count > 0) {
        _averageReplyMinutes[participant] =
            total / count;
      }
    }
  }

  String _formatReplyTime(
    String participant,
  ) {
    final double? average =
        _averageReplyMinutes[participant];

    if (average == null) {
      return 'データ不足';
    }

    final int minutes =
        average.round();

    if (minutes < 60) {
      return '平均$minutes分';
    }

    final int hours = minutes ~/ 60;
    final int remainingMinutes =
        minutes % 60;

    if (remainingMinutes == 0) {
      return '平均${hours}時間';
    }

    return '平均${hours}時間${remainingMinutes}分';
  }

  double _getAverageReply(
    String participant,
  ) {
    return _averageReplyMinutes[participant] ??
        0;
  }

  void _calculateFreeWord() {
    final String word =
        _wordController.text.trim();

    if (word.isEmpty) {
      setState(() {
        _checkedWord = '';
        _wordCount = 0;
      });

      return;
    }

    _calculateFreeWordInternal(word);

    setState(() {});
  }

  void _calculateFreeWordInternal(
    String word,
  ) {
    _checkedWord = word;

    _wordCount =
        _countOccurrences(_talkText, word);
  }

  static const List<String> _favoriteWords = [
    '大好き',
    'だいすき',
    'ダイスキ',
    '好き',
    'すき',
    'スキ',
  ];

  static const List<String> _thanksWords = [
    'ありがとう',
    'ありがと',
    'せんきゅー',
    'センキュー',
    'せんきゅ',
    'センキュ',
    'サンクス',
  ];

  int _countWordVariants(
    String text,
    List<String> variants,
  ) {
    if (text.isEmpty || variants.isEmpty) {
      return 0;
    }

    final List<String> sortedVariants =
        List<String>.from(variants)
          ..sort(
            (String a, String b) =>
                b.length.compareTo(a.length),
          );

    final RegExp pattern = RegExp(
      sortedVariants.map(RegExp.escape).join('|'),
    );

    return pattern.allMatches(text).length;
  }

  int _countOccurrences(
    String text,
    String word,
  ) {
    if (word.isEmpty) {
      return 0;
    }

    int count = 0;
    int startIndex = 0;

    while (true) {
      final int index =
          text.indexOf(
        word,
        startIndex,
      );

      if (index == -1) {
        break;
      }

      count++;

      startIndex =
          index + word.length;

      if (startIndex >= text.length) {
        break;
      }
    }

    return count;
  }

  void _calculateCompatibility() {
    if (_totalMessages == 0) {
      _compatibilityScore = 0;
      _lastingScore = 0;
      return;
    }

    final List<String> people =
        _participants.toList();

    if (people.length < 2) {
      _compatibilityScore = 50;
      _lastingScore = 50;
      return;
    }

    final String personA = people[0];
    final String personB = people[1];

    double messageScore = 0;

    if (_totalMessages >= 5000) {
      messageScore = 20;
    } else if (_totalMessages >= 2000) {
      messageScore = 18;
    } else if (_totalMessages >= 1000) {
      messageScore = 16;
    } else if (_totalMessages >= 500) {
      messageScore = 13;
    } else if (_totalMessages >= 200) {
      messageScore = 10;
    } else if (_totalMessages >= 100) {
      messageScore = 7;
    } else if (_totalMessages >= 30) {
      messageScore = 4;
    } else {
      messageScore = 2;
    }

    final int positiveWords =
        _romanticFavoriteCount + _thanksCount;

    double positiveScore = 0;

    if (positiveWords >= 100) {
      positiveScore = 20;
    } else if (positiveWords >= 50) {
      positiveScore = 18;
    } else if (positiveWords >= 30) {
      positiveScore = 16;
    } else if (positiveWords >= 20) {
      positiveScore = 14;
    } else if (positiveWords >= 10) {
      positiveScore = 11;
    } else if (positiveWords >= 5) {
      positiveScore = 8;
    } else if (positiveWords >= 1) {
      positiveScore = 4;
    }

    final double lateNightRatio =
        _totalMessages == 0
            ? 0
            : _lateNightCount /
                _totalMessages;

    double lateNightScore = 0;

    if (lateNightRatio >= 0.01 &&
        lateNightRatio <= 0.15) {
      lateNightScore = 15;
    } else if (lateNightRatio > 0 &&
        lateNightRatio < 0.25) {
      lateNightScore = 11;
    } else if (lateNightRatio == 0) {
      lateNightScore = 5;
    } else {
      lateNightScore = 7;
    }

    final double replyA =
        _getAverageReply(personA);

    final double replyB =
        _getAverageReply(personB);

    double balanceScore = 0;

    if (replyA > 0 && replyB > 0) {
      final double faster =
          replyA < replyB ? replyA : replyB;

      final double slower =
          replyA > replyB ? replyA : replyB;

      final double ratio =
          slower == 0
              ? 1
              : faster / slower;

      if (ratio >= 0.85) {
        balanceScore = 15;
      } else if (ratio >= 0.65) {
        balanceScore = 12;
      } else if (ratio >= 0.45) {
        balanceScore = 9;
      } else {
        balanceScore = 5;
      }
    } else {
      balanceScore = 7;
    }

    double participantScore = 0;

    if (people.length == 2) {
      participantScore = 10;
    } else if (people.length == 3) {
      participantScore = 6;
    } else {
      participantScore = 3;
    }

    double continuityScore = 0;

    final int activeWeekdays =
        _weekdayCounts
            .where((int value) => value > 0)
            .length;

    if (activeWeekdays >= 7) {
      continuityScore = 20;
    } else if (activeWeekdays >= 5) {
      continuityScore = 17;
    } else if (activeWeekdays >= 3) {
      continuityScore = 13;
    } else if (activeWeekdays >= 2) {
      continuityScore = 9;
    } else {
      continuityScore = 5;
    }

    double rawScore =
        messageScore +
            positiveScore +
            lateNightScore +
            balanceScore +
            participantScore +
            continuityScore;

    rawScore =
        rawScore.clamp(0.0, 100.0);

    _compatibilityScore =
        rawScore.round();

    double lasting =
        (_compatibilityScore * 0.55) +
            (continuityScore * 1.2) +
            (balanceScore * 0.8);

    if (positiveWords > 0) {
      lasting += 5;
    }

    if (lateNightRatio > 0 &&
        lateNightRatio < 0.2) {
      lasting += 4;
    }

    lasting =
        lasting.clamp(0.0, 100.0);

    _lastingScore =
        lasting.round();
  }

  void _reset() {
    setState(() {
      _fileName = '';
      _talkText = '';

      _totalMessages = 0;

      _participants.clear();
      _messages.clear();
      _dailyMessageCounts.clear();
      _latestTalkDate = null;
      _selectedSearchDate = null;

      for (int i = 0;
          i < _weekdayCounts.length;
          i++) {
        _weekdayCounts[i] = 0;
      }

      _favoriteCount = 0;
      _romanticFavoriteCount = 0;
      _favoriteQuestionCount = 0;
      _objectFavoriteCount = 0;
      _unknownFavoriteCount = 0;
      _romanticMorningCount = 0;
      _romanticDaytimeCount = 0;
      _romanticEveningCount = 0;
      _romanticNightCount = 0;
      _romanticLateNightCount = 0;
      _favoriteEntries.clear();

      _thanksCount = 0;
      _lateNightCount = 0;

      _replyTimeTotals.clear();
      _replyCounts.clear();
      _averageReplyMinutes.clear();

      _compatibilityScore = 0;
      _lastingScore = 0;

      _checkedWord = '';
      _wordCount = 0;

      _wordController.clear();

      _errorMessage = null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF6F8F7),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _fileName.isEmpty
                  ? _buildHomeScreen()
                  : _buildAnalysisScreen(),
            ),
            _buildAdBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 66,
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 22,
      ),
      decoration:
          const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Color(0xFF06A94D),
            Color(0xFF06C755),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration:
                BoxDecoration(
              color:
                  Colors.white.withOpacity(0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    'LINEトーク分析',
                    maxLines: 1,
                    softWrap: false,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Icon(
            Icons.bar_chart_rounded,
            size: 31,
            color:
                Colors.white.withOpacity(0.22),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeScreen() {
    return SingleChildScrollView(
      padding:
          const EdgeInsets.fromLTRB(
        18,
        0,
        18,
        24,
      ),
      child: Column(
        children: [
          _buildIntroduction(),
          const SizedBox(height: 16),
          _buildCoupleConceptCard(),
          const SizedBox(height: 16),
          _buildFilePickerCard(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 14),
            _buildErrorCard(),
          ],
          if (_isLoading) ...[
            const SizedBox(height: 14),
            _buildLoadingCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisScreen() {
    return SingleChildScrollView(
      padding:
          const EdgeInsets.fromLTRB(
        18,
        0,
        18,
        24,
      ),
      child: Column(
        children: [
          _buildIntroduction(),
          const SizedBox(height: 16),
          _buildFileInfoCard(),
          const SizedBox(height: 16),
          _buildCompatibilityCard(),
          const SizedBox(height: 16),
          _buildBasicResultCard(),
          const SizedBox(height: 16),
          _buildParticipantsCard(),
          const SizedBox(height: 16),
          _buildReplySpeedCard(),
          const SizedBox(height: 16),
          _buildFreeWordCard(),
          const SizedBox(height: 16),
          _buildStandardWordCard(),
          const SizedBox(height: 16),
          _buildFavoriteAnalysisCard(),
          const SizedBox(height: 16),
          _buildLateNightCard(),
          const SizedBox(height: 16),
          _buildRecentSevenDaysCard(),
          const SizedBox(height: 18),
          _buildResetButton(),
        ],
      ),
    );
  }

  Widget _buildIntroduction() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        5,
        25,
        5,
        14,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '二人のトークを',
                      style: TextStyle(
                        fontSize: 26,
                        height: 1.2,
                        fontWeight:
                            FontWeight.w900,
                        color:
                            Color(0xFF26332E),
                      ),
                    ),
                    const SizedBox(height: 1),
                    RichText(
                      text: const TextSpan(
                        children: [
                          TextSpan(
                            text:
                                'ちょっと本気で',
                            style: TextStyle(
                              fontSize: 29,
                              height: 1.2,
                              fontWeight:
                                  FontWeight.w900,
                              color:
                                  Color(0xFF06B653),
                            ),
                          ),
                          TextSpan(
                            text: '分析。',
                            style: TextStyle(
                              fontSize: 29,
                              height: 1.2,
                              fontWeight:
                                  FontWeight.w900,
                              color:
                                  Color(0xFF26332E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 66,
                height: 66,
                decoration:
                    BoxDecoration(
                  gradient:
                      const LinearGradient(
                    begin:
                        Alignment.topLeft,
                    end:
                        Alignment.bottomRight,
                    colors: [
                      Color(0xFFE7F8EF),
                      Color(0xFFFFEEF3),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      color:
                          Color(0xFF06B653),
                      size: 31,
                    ),
                    Positioned(
                      right: 10,
                      top: 11,
                      child: Icon(
                        Icons.favorite_rounded,
                        color:
                            Color(0xFFE86A8D),
                        size: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'メッセージ数、返信スピード、定番ワード、深夜トークまで、ふたりの会話を楽しくチェック。',
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color:
                  Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoupleConceptCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        18,
      ),
      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0FAF5),
            Color(0xFFFFF1F5),
          ],
        ),
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              const Color(0xFFDCEFE5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 53,
            height: 53,
            decoration:
                BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF06B653,
                  ).withOpacity(0.10),
                  blurRadius: 10,
                  offset:
                      const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color:
                  Color(0xFFE05A82),
              size: 27,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'ふたりの会話をもっと楽しもう',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight:
                        FontWeight.w800,
                    color:
                        Color(0xFF315B47),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'トーク履歴から、ふたりだけの会話の特徴を発見。',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color:
                        Color(0xFF6D8278),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilePickerCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        22,
        28,
        22,
        25,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              const Color(0xFFDDE9E2),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF245C42)
                    .withOpacity(0.07),
            blurRadius: 20,
            offset:
                const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration:
                BoxDecoration(
              gradient:
                  const LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  Color(0xFFE4F8EC),
                  Color(0xFFFFEEF3),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.file_open_rounded,
              color:
                  Color(0xFF06B653),
              size: 38,
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'LINEトーク履歴を選択',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color:
                  Color(0xFF29322F),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'ふたりのトーク履歴 .txt ファイルに対応',
            style: TextStyle(
              fontSize: 12,
              color:
                  Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 21),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: FilledButton.icon(
              onPressed:
                  _isLoading
                      ? null
                      : _pickFile,
              icon: const Icon(
                Icons.upload_file_rounded,
                size: 19,
              ),
              label: const Text(
                'トーク履歴を読み込む',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    const Color(
                  0xFF06C755,
                ),
                foregroundColor:
                    Colors.white,
                disabledBackgroundColor:
                    const Color(
                  0xFF9EDDB8,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '※トーク内容は分析のため端末上で処理されます',
            style: TextStyle(
              fontSize: 9,
              color:
                  Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfoCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(14),
      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          colors: [
            Color(0xFFEAF8F0),
            Color(0xFFFFF2F5),
          ],
        ),
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color:
              const Color(0xFFD8EBE0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration:
                BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.description_rounded,
              color:
                  Color(0xFF06B653),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                const Text(
                  '解析中のトーク履歴',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        Color(0xFF6E887B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fileName,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    color:
                        Color(0xFF34443C),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color:
                Color(0xFF06B653),
          ),
        ],
      ),
    );
  }

  Widget _buildCompatibilityCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(21),
      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFE7EE),
            Color(0xFFFFF2F6),
            Color(0xFFF3FAF6),
          ],
        ),
        borderRadius:
            BorderRadius.circular(25),
        border: Border.all(
          color:
              const Color(0xFFF1CAD6),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFFB55B75)
                    .withOpacity(0.10),
            blurRadius: 22,
            offset:
                const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 7,
            ),
            decoration:
                BoxDecoration(
              color:
                  Colors.white.withOpacity(0.78),
              borderRadius:
                  BorderRadius.circular(30),
            ),
            child: const Text(
              '💗 ふたりのトーク診断 💗',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight:
                    FontWeight.w900,
                color:
                    Color(0xFF9C4660),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'トークデータから独自アルゴリズムで算出',
            style: TextStyle(
              fontSize: 11,
              color:
                  Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 19),
          Row(
            children: [
              Expanded(
                child: _buildScoreCircle(
                  title: '相性',
                  score:
                      _compatibilityScore,
                  suffix: '点',
                  color:
                      const Color(
                    0xFFE2537D,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: _buildScoreCircle(
                  title: '長続き度',
                  score:
                      _lastingScore,
                  suffix: '%',
                  color:
                      const Color(
                    0xFF4E9B76,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(13),
            decoration:
                BoxDecoration(
              color:
                  Colors.white.withOpacity(0.80),
              borderRadius:
                  BorderRadius.circular(15),
            ),
            child: Text(
              _getCompatibilityMessage(),
              textAlign:
                  TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight:
                    FontWeight.w600,
                color:
                    Color(0xFF5E4B52),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            '※この診断はトークデータを使ったエンタメ向けの簡易診断です。',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color:
                  Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreCircle({
    required String title,
    required int score,
    required String suffix,
    required Color color,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 16,
      ),
      decoration:
          BoxDecoration(
        color:
            Colors.white.withOpacity(0.88),
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight:
                  FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 92,
            height: 92,
            decoration:
                BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color,
                width: 5,
              ),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color:
                      color.withOpacity(0.10),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 30,
                    height: 1,
                    fontWeight:
                        FontWeight.w900,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suffix,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _getCompatibilityMessage() {
    if (_totalMessages == 0) {
      return '💬 まずはトークを読み込んで、二人の会話を見てみよう！';
    }

    final String baseMessage;

    final bool highCompatibility =
        _compatibilityScore >= 70;
    final bool mediumCompatibility =
        _compatibilityScore >= 40;
    final bool highLasting =
        _lastingScore >= 70;
    final bool mediumLasting =
        _lastingScore >= 40;

if (highCompatibility && highLasting) {
  baseMessage =
      '🎉 会話の相性も長続き度もいい感じ！\n'
      '二人のやり取りから、自然な盛り上がりと安定感が感じられます。';
} else if (highCompatibility && mediumLasting) {
  baseMessage =
      '💞 会話の相性がかなり良好！\n'
      '楽しく話せる土台ができているので、今のペースを大切にしていこう。';
} else if (highCompatibility && !mediumLasting) {
  baseMessage =
      '✨ トークの相性がいい二人！\n'
      '会話の楽しさはしっかり出ています。これからの積み重ねにも注目です。';
} else if (mediumCompatibility && highLasting) {
  baseMessage =
      '🌱 長続きにつながる安定感がいい感じ！\n'
      '会話量が増えていけば、二人らしい盛り上がりがさらに見えてきそうです。';
} else if (mediumCompatibility && mediumLasting) {
  baseMessage =
      '😊 バランスのいいトーク！\n'
      '今の会話を楽しみながら、少しずつ二人の時間を増やしていくと良さそうです。';
} else if (mediumCompatibility && !mediumLasting) {
  baseMessage =
      '🌷 ここから伸びていく余地がたっぷり！\n'
      'すでに会話の土台があるので、気軽なやり取りを重ねてみよう。';
} else if (!mediumCompatibility && highLasting) {
  baseMessage =
      '💚 ゆっくりでも続いているところがいいポイント！\n'
      '派手な会話量だけではなく、二人のペースで積み重ねている感じが出ています。';
} else if (!mediumCompatibility && mediumLasting) {
  baseMessage =
      '🌼 二人のペースで育っているトーク！\n'
      'これから会話が増えていくほど、相性の特徴ももっと見えてきそうです。';
} else {
  baseMessage =
      '💬 ここから二人のトークが育っていく段階！\n'
      '会話を重ねるほど、今回とは違った二人らしさも見えてきそうです。';
}

    final List<String> evaluations = [];

    final List<double> replyValues =
        _averageReplyMinutes.values
            .where((double value) => value > 0)
            .toList();

    if (replyValues.isNotEmpty) {
      final double averageReply =
          replyValues.reduce((double a, double b) => a + b) /
              replyValues.length;

      if (averageReply <= 10) {
        evaluations.add('⚡ 返信テンポがかなり速く、会話のキャッチボールが活発！');
      } else if (averageReply <= 30) {
        evaluations.add('💨 返信テンポがよく、スムーズなやり取りができています！');
      } else if (averageReply <= 120) {
        evaluations.add('💬 無理のないペースで、しっかり会話が続いています！');
      }
    }

    if (_romanticFavoriteCount >= 10) {
      evaluations.add('💖 相手への「好き」がたくさん見つかって、好意がしっかり伝わるトーク！');
    } else if (_romanticFavoriteCount >= 3) {
      evaluations.add('💕 相手への「好き」もしっかり登場。二人の好意が感じられます！');
    } else if (_romanticFavoriteCount >= 1) {
      evaluations.add('💗 相手への「好き」も見つかりました。小さなプラス要素です！');
    }

    if (_thanksCount >= 5) {
      evaluations.add('🙏 感謝の言葉も豊富で、思いやりのあるやり取りが見えます！');
    } else if (_thanksCount >= 1) {
      evaluations.add('🌿 感謝の言葉も見られ、丁寧なやり取りができています！');
    }

    if (evaluations.isEmpty) {
      evaluations.add('🌟 これからトークが増えるほど、二人らしいプラス評価も見つかってきます！');
    }

    return '$baseMessage\n\n${evaluations.take(2).join('\n')}';
  }

  Widget _buildBasicResultCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.chat_bubble_rounded,
            title: '基本集計',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildStatBox(
                  icon:
                      Icons.forum_rounded,
                  label: '総メッセージ数',
                  value:
                      '$_totalMessages',
                  unit: '件',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatBox(
                  icon:
                      Icons.people_alt_rounded,
                  label: '参加者',
                  value:
                      '${_participants.length}',
                  unit: '人',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required IconData icon,
    required String label,
    required String value,
    required String unit,
  }) {
    return Container(
      padding:
          const EdgeInsets.all(16),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFFF0F8F4),
        borderRadius:
            BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color:
                const Color(0xFF06B653),
            size: 22,
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color:
                  Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight:
                      FontWeight.w800,
                  color:
                      Color(0xFF19734A),
                ),
              ),
              const SizedBox(width: 3),
              Padding(
                padding:
                    const EdgeInsets.only(
                  bottom: 4,
                ),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsCard() {
    final List<String> participants =
        _participants.toList()..sort();

    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon:
                Icons.people_alt_rounded,
            title: '参加者一覧',
            trailing:
                '${participants.length}人',
          ),
          const SizedBox(height: 14),
          if (participants.isEmpty)
            Text(
              '参加者を検出できませんでした。',
              style: TextStyle(
                color:
                    Colors.grey.shade600,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  participants.map(
                (String name) {
                  return Container(
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 13,
                      vertical: 9,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFF0F8F4,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(30),
                      border: Border.all(
                        color:
                            const Color(
                          0xFFD2E9DD,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          size: 16,
                          color:
                              Color(
                            0xFF06B653,
                          ),
                        ),
                        const SizedBox(
                            width: 5),
                        Text(
                          name,
                          style:
                              const TextStyle(
                            fontWeight:
                                FontWeight.w600,
                            color:
                                Color(
                              0xFF37624D,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildReplySpeedCard() {
    final List<String> people =
        _participants.toList();

    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.speed_rounded,
            title: '返信スピード比較',
            trailing: '平均返信時間',
          ),
          const SizedBox(height: 8),
          Text(
            '前の人の発言から、次に別の人が返信するまでの時間を簡易計算しています。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color:
                  Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 17),
          if (people.length < 2)
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(16),
              decoration:
                  BoxDecoration(
                color:
                    const Color(0xFFF3F8F5),
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: const Text(
                '2人以上の参加者データが必要です。',
                textAlign:
                    TextAlign.center,
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child:
                      _buildReplyPersonCard(
                    people[0],
                    const Color(
                      0xFF06B653,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child:
                      _buildReplyPersonCard(
                    people[1],
                    const Color(
                      0xFFE06A8C,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            _buildReplyBalanceBar(
              people[0],
              people[1],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyPersonCard(
    String participant,
    Color color,
  ) {
    final int replyCount =
        _replyCounts[participant] ?? 0;

    return Container(
      padding:
          const EdgeInsets.all(15),
      decoration:
          BoxDecoration(
        color:
            color.withOpacity(0.08),
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color:
              color.withOpacity(0.25),
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor:
                color.withOpacity(0.15),
            child: Icon(
              Icons.person_rounded,
              color: color,
              size: 23,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            participant,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatReplyTime(
              participant,
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight:
                  FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            replyCount > 0
                ? '${replyCount}回を計測'
                : '計測データなし',
            style: TextStyle(
              fontSize: 10,
              color:
                  Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyBalanceBar(
    String personA,
    String personB,
  ) {
    final double a =
        _getAverageReply(personA);

    final double b =
        _getAverageReply(personB);

    if (a <= 0 || b <= 0) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.all(12),
        decoration:
            BoxDecoration(
          color:
              const Color(0xFFF4F8F6),
          borderRadius:
              BorderRadius.circular(12),
        ),
        child: const Text(
          '返信スピードの比較には、両者の返信データが必要です。',
          textAlign:
              TextAlign.center,
          style:
              TextStyle(fontSize: 12),
        ),
      );
    }

    final double maxValue =
        a > b ? a : b;

    final int aFlex = _safeFlex(
      a / maxValue,
    );

    final int bFlex = _safeFlex(
      b / maxValue,
    );

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Text(
          '返信時間のバランス',
          style: TextStyle(
            fontSize: 12,
            fontWeight:
                FontWeight.bold,
            color:
                Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius:
              BorderRadius.circular(20),
          child: Row(
            children: [
              Expanded(
                flex: aFlex,
                child: Container(
                  height: 13,
                  color:
                      const Color(0xFF06B653),
                ),
              ),
              Expanded(
                flex: bFlex,
                child: Container(
                  height: 13,
                  color:
                      const Color(0xFFE06A8C),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
          children: [
            Flexible(
              child: Text(
                '$personA：${a.round()}分',
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color:
                      Color(0xFF069E4D),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
            Flexible(
              child: Text(
                '$personB：${b.round()}分',
                textAlign:
                    TextAlign.right,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color:
                      Color(0xFFD45C7D),
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  int _safeFlex(double ratio) {
    final int value =
        (ratio * 100).round();

    if (value < 1) {
      return 1;
    }

    if (value > 100) {
      return 100;
    }

    return value;
  }

  Widget _buildFreeWordCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(20),
      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF0FAF5),
            Color(0xFFFFF4F7),
          ],
        ),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color:
              const Color(0xFFDCEBE2),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            '🔍 気になるワードをチェック',
            style: TextStyle(
              fontSize: 19,
              fontWeight:
                  FontWeight.w900,
              color:
                  Color(0xFF315C48),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '好きな言葉を入力して、トーク全体で何回登場したか調べます。',
            style: TextStyle(
              fontSize: 12,
              color:
                  Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller:
                      _wordController,
                  textInputAction:
                      TextInputAction.search,
                  onSubmitted: (_) {
                    _calculateFreeWord();
                  },
                  decoration:
                      InputDecoration(
                    hintText:
                        '例：会いたい、楽しい',
                    prefixIcon:
                        const Icon(
                      Icons.search_rounded,
                      color:
                          Color(0xFF06B653),
                    ),
                    filled: true,
                    fillColor:
                        Colors.white,
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                      borderSide:
                          BorderSide.none,
                    ),
                    focusedBorder:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                      borderSide:
                          const BorderSide(
                        color:
                            Color(0xFF06C755),
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed:
                      _talkText.isEmpty
                          ? null
                          : _calculateFreeWord,
                  style:
                      FilledButton.styleFrom(
                    backgroundColor:
                        const Color(
                      0xFF06C755,
                    ),
                    foregroundColor:
                        Colors.white,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                  child: const Text(
                    '集計',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_checkedWord.isNotEmpty) ...[
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(15),
              decoration:
                  BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons
                        .auto_awesome_rounded,
                    color:
                        Color(0xFFE05A82),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '「$_checkedWord」',
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '$_wordCount回',
                    style:
                        const TextStyle(
                      fontSize: 22,
                      fontWeight:
                          FontWeight.w800,
                      color:
                          Color(0xFF187A4F),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStandardWordCard() {
    final int total =
        _favoriteCount +
            _thanksCount;

    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon:
                Icons.favorite_rounded,
            title: 'ふたりの定番ワード',
            trailing: '合計 $total 回',
            accentPink: true,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildWordResult(
                  word: '好き',
                  count:
                      _favoriteCount,
                  icon:
                      Icons.favorite_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildWordResult(
                  word: '感謝',
                  count:
                      _thanksCount,
                  icon:
                      Icons
                          .volunteer_activism_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWordResult({
    required String word,
    required int count,
    required IconData icon,
  }) {
    return Container(
      padding:
          const EdgeInsets.all(15),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFFFFF1F5),
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              const Color(0xFFF5D6DF),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color:
                const Color(0xFFE2567F),
            size: 25,
          ),
          const SizedBox(height: 8),
          Text(
            word,
            style: const TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$count回',
            style: const TextStyle(
              fontSize: 22,
              fontWeight:
                  FontWeight.w800,
              color:
                  Color(0xFFA23B5E),
            ),
          ),
        ],
      ),
    );
  }

  String _favoriteCategoryLabel(
    _FavoriteCategory category,
  ) {
    switch (category) {
      case _FavoriteCategory.romantic:
        return '相手への好き';
      case _FavoriteCategory.question:
        return '好き？と質問';
      case _FavoriteCategory.object:
        return '対象への好き';
      case _FavoriteCategory.unknown:
        return '判定保留';
    }
  }

  Color _favoriteCategoryColor(
    _FavoriteCategory category,
  ) {
    switch (category) {
      case _FavoriteCategory.romantic:
        return const Color(0xFFE2567F);
      case _FavoriteCategory.question:
        return const Color(0xFF8A5CA8);
      case _FavoriteCategory.object:
        return const Color(0xFF368B67);
      case _FavoriteCategory.unknown:
        return const Color(0xFF8A8F8D);
    }
  }

  String _formatFavoriteDate(_TalkMessage message) {
    if (message.date == null) {
      return '${message.hour.toString().padLeft(2, '0')}:${message.minute.toString().padLeft(2, '0')}';
    }

    return '${message.date!.year}/${message.date!.month.toString().padLeft(2, '0')}/${message.date!.day.toString().padLeft(2, '0')} ${message.hour.toString().padLeft(2, '0')}:${message.minute.toString().padLeft(2, '0')}';
  }

  String _favoriteTimingText() {
    final List<_FavoriteTiming> timings = [
      _FavoriteTiming('朝', _romanticMorningCount),
      _FavoriteTiming('昼', _romanticDaytimeCount),
      _FavoriteTiming('夕方', _romanticEveningCount),
      _FavoriteTiming('夜', _romanticNightCount),
      _FavoriteTiming('深夜', _romanticLateNightCount),
    ];

    _FavoriteTiming top = timings.first;

    for (final _FavoriteTiming timing in timings) {
      if (timing.count > top.count) {
        top = timing;
      }
    }

    if (top.count == 0) {
      return '相手への「好き」と推定できる発言は、まだありません。';
    }

    return '相手への「好き」は主に${top.label}に伝えています。';
  }

  Widget _buildFavoriteTimingBar(
    String label,
    int count,
    int maxCount,
  ) {
    final double ratio = maxCount == 0
        ? 0
        : count / maxCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4A544F),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F1F1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE86A8D),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF4A544F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteMiniCount(
    String label,
    int count,
    IconData icon,
    Color iconColor,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFE8ECEA),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 19,
              color: iconColor,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF555E5A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$count回',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: Color(0xFF35433D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteAnalysisCard() {
    _FavoriteEntry? firstRomantic;
    _FavoriteEntry? latestRomantic;

    for (final _FavoriteEntry entry in _favoriteEntries) {
      if (entry.category != _FavoriteCategory.romantic) {
        continue;
      }

      if (firstRomantic == null ||
          _compareTalkMessageTime(
                entry.message,
                firstRomantic.message,
              ) <
              0) {
        firstRomantic = entry;
      }

      if (latestRomantic == null ||
          _compareTalkMessageTime(
                entry.message,
                latestRomantic.message,
              ) >
              0) {
        latestRomantic = entry;
      }
    }

    final int maxTimingCount = [
      _romanticMorningCount,
      _romanticDaytimeCount,
      _romanticEveningCount,
      _romanticNightCount,
      _romanticLateNightCount,
    ].reduce((int a, int b) => a > b ? a : b);

    final List<_FavoriteEntry> romanticEntries =
        _favoriteEntries
            .where(
              (_FavoriteEntry entry) =>
                  entry.category == _FavoriteCategory.romantic,
            )
            .toList();

    romanticEntries.sort(
      (_FavoriteEntry a, _FavoriteEntry b) =>
          _compareTalkMessageTime(b.message, a.message),
    );

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.favorite_rounded,
            title: '「好き」の意味までチェック',
            accentPink: true,
          ),
          const SizedBox(height: 7),
          Text(
            '「ミセス好きだよ」のような対象への「好き」と、相手への「好き」を分けて集計します。',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildFavoriteMiniCount(
                '相手への好き',
                _romanticFavoriteCount,
                Icons.favorite_rounded,
                const Color(0xFFE2567F),
              ),
              const SizedBox(width: 8),
              _buildFavoriteMiniCount(
                '好き？と質問',
                _favoriteQuestionCount,
                Icons.help_rounded,
                const Color(0xFF8A5CA8),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildFavoriteMiniCount(
                '対象への好き',
                _objectFavoriteCount,
                Icons.music_note_rounded,
                const Color(0xFF368B67),
              ),
              const SizedBox(width: 8),
              _buildFavoriteMiniCount(
                '判定保留',
                _unknownFavoriteCount,
                Icons.help_outline_rounded,
                const Color(0xFF8A8F8D),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F9),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: const Color(0xFFF6DCE4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💗 伝えるタイミング',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8E3657),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _favoriteTimingText(),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: Color(0xFF5A4A50),
                  ),
                ),
                const SizedBox(height: 12),
                _buildFavoriteTimingBar(
                  '朝',
                  _romanticMorningCount,
                  maxTimingCount,
                ),
                _buildFavoriteTimingBar(
                  '昼',
                  _romanticDaytimeCount,
                  maxTimingCount,
                ),
                _buildFavoriteTimingBar(
                  '夕方',
                  _romanticEveningCount,
                  maxTimingCount,
                ),
                _buildFavoriteTimingBar(
                  '夜',
                  _romanticNightCount,
                  maxTimingCount,
                ),
                _buildFavoriteTimingBar(
                  '深夜',
                  _romanticLateNightCount,
                  maxTimingCount,
                ),
              ],
            ),
          ),
          if (firstRomantic != null) ...[
            const SizedBox(height: 14),
            _buildFavoriteMomentCard(
              title: '最初に見つかった相手への「好き」',
              entry: firstRomantic,
            ),
          ],
          if (latestRomantic != null &&
              latestRomantic != firstRomantic) ...[
            const SizedBox(height: 9),
            _buildFavoriteMomentCard(
              title: '最近の相手への「好き」',
              entry: latestRomantic,
            ),
          ],
          if (romanticEntries.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              '最近の発言',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF394640),
              ),
            ),
            const SizedBox(height: 8),
            for (final _FavoriteEntry entry
                in romanticEntries.take(5)) ...[
              _buildFavoriteHistoryRow(entry),
              if (entry != romanticEntries.take(5).last)
                const SizedBox(height: 7),
            ],
          ],
          if (_unknownFavoriteCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              '※ 文脈だけでは意味を決めにくい「好き」は判定保留にしています。',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _compareTalkMessageTime(
    _TalkMessage a,
    _TalkMessage b,
  ) {
    if (a.date != null && b.date != null) {
      final int dateCompare = a.date!.compareTo(b.date!);
      if (dateCompare != 0) {
        return dateCompare;
      }
    }

    final int aMinutes = a.hour * 60 + a.minute;
    final int bMinutes = b.hour * 60 + b.minute;

    return aMinutes.compareTo(bMinutes);
  }

  Widget _buildFavoriteMomentCard({
    required String title,
    required _FavoriteEntry entry,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFEAEDEB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${_formatFavoriteDate(entry.message)}  ${entry.message.participant}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF44504A),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            _messageBody(entry.message),
            style: const TextStyle(
              fontSize: 13,
              height: 1.45,
              color: Color(0xFF28342F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteHistoryRow(
    _FavoriteEntry entry,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAF9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.favorite_rounded,
            size: 17,
            color: _favoriteCategoryColor(entry.category),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_formatFavoriteDate(entry.message)}  ${entry.message.participant}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _messageBody(entry.message),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Color(0xFF2F3935),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLateNightCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(20),
      decoration:
          const BoxDecoration(
        gradient:
            LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF263746),
            Color(0xFF425D72),
          ],
        ),
        borderRadius:
            BorderRadius.all(
          Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 55,
            height: 55,
            decoration:
                BoxDecoration(
              color:
                  Colors.white
                      .withOpacity(0.12),
              borderRadius:
                  BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.nights_stay_rounded,
              color: Colors.white,
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '深夜のふたり',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '2:00〜4:59に送信されたメッセージ',
                  style: TextStyle(
                    color:
                        Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$_lateNightCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            '件',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateLabel(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日（${_weekdays[date.weekday - 1]}）';
  }

  Future<void> _searchTalkDate() async {
    if (_dailyMessageCounts.isEmpty) {
      return;
    }

    final List<DateTime> dates =
        _dailyMessageCounts.keys.toList();

    DateTime earliestDate = dates.first;
    DateTime latestDate = dates.first;

    for (final DateTime date in dates) {
      if (date.isBefore(earliestDate)) {
        earliestDate = date;
      }

      if (date.isAfter(latestDate)) {
        latestDate = date;
      }
    }

    earliestDate = DateTime(
      earliestDate.year,
      earliestDate.month,
      earliestDate.day,
    );

    // 最新日も実際に分析できた日付キーから決める。
    latestDate = DateTime(
      latestDate.year,
      latestDate.month,
      latestDate.day,
    );

    DateTime initialDate =
        _selectedSearchDate ?? latestDate;

    if (initialDate.isBefore(earliestDate)) {
      initialDate = earliestDate;
    }

    if (initialDate.isAfter(latestDate)) {
      initialDate = latestDate;
    }

    final DateTime? pickedDate =
        await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliestDate,
      lastDate: latestDate,
      helpText: 'トークの日付を検索',
      cancelText: 'キャンセル',
      confirmText: '選択',
      locale: const Locale('ja', 'JP'),
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    final DateTime dateKey = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
    );

    setState(() {
      _selectedSearchDate = dateKey;
    });
  }

  Widget _buildRecentSevenDaysCard() {
    final DateTime? latestDate = _latestTalkDate;

    DateTime? earliestDate;
    if (_dailyMessageCounts.isNotEmpty) {
      final List<DateTime> dates =
          _dailyMessageCounts.keys.toList()..sort();
      earliestDate = DateTime(
        dates.first.year,
        dates.first.month,
        dates.first.day,
      );
    }

    if (latestDate == null || earliestDate == null) {
      return _buildCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.calendar_month_rounded,
              title: '直近7日間のトーク履歴',
            ),
            const SizedBox(height: 8),
            Text(
              '日付データを取得できませんでした。',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      );
    }

    final DateTime latestDay = DateTime(
      latestDate.year,
      latestDate.month,
      latestDate.day,
    );

    int maxCount = 0;

    for (int i = 0; i < 7; i++) {
      final DateTime dateKey =
          latestDay.subtract(Duration(days: i));
      final int count =
          _dailyMessageCounts[dateKey] ?? 0;

      if (count > maxCount) {
        maxCount = count;
      }
    }

    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Icons.calendar_month_rounded,
            title: '直近7日間のトーク履歴',
          ),
          const SizedBox(height: 7),
          Text(
            'トーク履歴の最新日から、直近7日分を表示しています。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          for (int i = 0; i < 7; i++) ...[
            Builder(
              builder: (BuildContext context) {
                final DateTime dateKey =
                    latestDay.subtract(Duration(days: i));
                final int count =
                    _dailyMessageCounts[dateKey] ?? 0;
                final double ratio = maxCount == 0
                    ? 0
                    : count / maxCount;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 146,
                        child: Text(
                          _formatDateLabel(dateKey),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF34443C),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 11,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F2EC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor:
                                ratio.clamp(0.0, 1.0),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF58D68D),
                                    Color(0xFF06B653),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '$count件',
                          textAlign: TextAlign.end,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF19734A),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Text(
            '検索可能期間：${_formatDateLabel(earliestDate)}〜${_formatDateLabel(latestDate)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _searchTalkDate,
              icon: const Icon(
                Icons.calendar_month_rounded,
                size: 19,
              ),
              label: const Text(
                'カレンダーから日付を検索',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF06A94D),
                side: const BorderSide(
                  color: Color(0xFF06A94D),
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          if (_selectedSearchDate != null) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (BuildContext context) {
                final DateTime selectedDate =
                    _selectedSearchDate!;
                final int count =
                    _dailyMessageCounts[selectedDate] ?? 0;

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F8F4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFD2E9DD),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF06B653),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '${_formatDateLabel(selectedDate)}  $count件',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF315B47),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResetButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: _reset,
        icon: const Icon(
          Icons.refresh_rounded,
        ),
        label: const Text(
          '別のトーク履歴を分析する',
          style: TextStyle(
            fontWeight:
                FontWeight.bold,
          ),
        ),
        style:
            OutlinedButton.styleFrom(
          foregroundColor:
              const Color(0xFF06A94D),
          side:
              const BorderSide(
            color:
                Color(0xFF06A94D),
            width: 1.3,
          ),
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(15),
          ),
        ),
      ),
    );
  }

  Widget _buildAdBanner() {
    if (_isBannerAdReady &&
        _bannerAd != null) {
      return Container(
        width: double.infinity,
        height: 52,
        color: const Color(0xFFEDEDED),
        alignment: Alignment.center,
        child: SizedBox(
          width: 320,
          height: 50,
          child: AdWidget(
            ad: _bannerAd!,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 52,
      color: const Color(0xFFEDEDED),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(15),
      decoration:
          BoxDecoration(
        color:
            const Color(0xFFFFEEEE),
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              const Color(0xFFFFCCCC),
        ),
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(
                color: Colors.red,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCard() {
    return _buildCard(
      child: const Column(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child:
                CircularProgressIndicator(
              color:
                  Color(0xFF06C755),
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'トーク履歴を解析しています…',
            style: TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(20),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color:
              const Color(0xFFDDE8E2),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF3D6854)
                    .withOpacity(0.045),
            blurRadius: 18,
            offset:
                const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    String? trailing,
    bool accentPink = false,
  }) {
    final Color accentColor =
        accentPink
            ? const Color(0xFFE1557D)
            : const Color(0xFF06B653);

    final Color lightColor =
        accentPink
            ? const Color(0xFFFFE8EF)
            : const Color(0xFFE6F8EE);

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration:
              BoxDecoration(
            color: lightColor,
            borderRadius:
                BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: accentColor,
            size: 21,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style:
                const TextStyle(
              fontSize: 17,
              fontWeight:
                  FontWeight.bold,
              color:
                  Color(0xFF35433C),
            ),
          ),
        ),
        if (trailing != null)
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 5,
            ),
            decoration:
                BoxDecoration(
              color:
                  accentPink
                      ? const Color(
                          0xFFFFEDF2,
                        )
                      : const Color(
                          0xFFEAF7F0,
                        ),
              borderRadius:
                  BorderRadius.circular(20),
            ),
            child: Text(
              trailing,
              style:
                  TextStyle(
                color:
                    accentPink
                        ? const Color(
                            0xFFBE4C70,
                          )
                        : const Color(
                            0xFF39815E,
                          ),
                fontSize: 12,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

enum _FavoriteCategory {
  romantic,
  question,
  object,
  unknown,
}

class _FavoriteEntry {
  final _FavoriteCategory category;
  final int count;
  final _TalkMessage message;

  const _FavoriteEntry({
    required this.category,
    required this.count,
    required this.message,
  });
}

class _FavoriteTiming {
  final String label;
  final int count;

  const _FavoriteTiming(
    this.label,
    this.count,
  );
}

class _TalkMessage {
  final String participant;
  final int hour;
  final int minute;
  final DateTime? date;
  final String rawText;

  const _TalkMessage({
    required this.participant,
    required this.hour,
    required this.minute,
    required this.date,
    required this.rawText,
  });
}