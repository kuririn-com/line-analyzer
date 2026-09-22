import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const LineTalkAnalyzerApp());
}

class LineTalkAnalyzerApp extends StatelessWidget {
  const LineTalkAnalyzerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LINEトーク分析',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5FAF6),
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

  final Set<String> _participants = <String>{};

  final List<int> _weekdayCounts = <int>[
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];

  int _favoriteCount = 0;
  int _thanksCount = 0;
  int _lateNightCount = 0;

  final TextEditingController _wordController =
      TextEditingController();

  String _checkedWord = '';
  int _wordCount = 0;

  final Map<String, int> _replyTimeTotals =
      <String, int>{};

  final Map<String, int> _replyCounts =
      <String, int>{};

  final Map<String, double> _averageReplyMinutes =
      <String, double>{};

  int _compatibilityScore = 0;
  int _lastingScore = 0;

  bool _isLoading = false;

  String? _errorMessage;

  final List<_TalkMessage> _messages =
      <_TalkMessage>[];

  final RegExp _messagePattern =
      RegExp(r'^(\d{2}):(\d{2})');

  final RegExp _datePattern =
      RegExp(r'^(\d{4})/(\d{1,2})/(\d{1,2})');

  static const List<String> _weekdays = <String>[
    '月',
    '火',
    '水',
    '木',
    '金',
    '土',
    '日',
  ];

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<PlatformFile> result =
          await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['txt'],
      );

      if (result.isEmpty) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final Uint8List bytes =
          await result.first.readAsBytes();

      final String text = utf8.decode(bytes);

      _analyzeTalk(text);

      setState(() {
        _fileName = result.first.name;
        _talkText = text;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage =
            'ファイルの読み込みに失敗しました。\n$e';
      });
    }
  }

  void _analyzeTalk(String text) {
    _totalMessages = 0;

    _participants.clear();
    _messages.clear();

    _replyTimeTotals.clear();
    _replyCounts.clear();
    _averageReplyMinutes.clear();

    for (int i = 0; i < _weekdayCounts.length; i++) {
      _weekdayCounts[i] = 0;
    }

    _favoriteCount = 0;
    _thanksCount = 0;
    _lateNightCount = 0;

    DateTime? currentDate;

    final List<String> lines =
        text.split(RegExp(r'\r?\n'));

    for (final String rawLine in lines) {
      final String line = rawLine.trimRight();

      if (line.isEmpty) {
        continue;
      }

      final Match? dateMatch =
          _datePattern.firstMatch(line);

      if (dateMatch != null) {
        final int? year =
            int.tryParse(dateMatch.group(1)!);

        final int? month =
            int.tryParse(dateMatch.group(2)!);

        final int? day =
            int.tryParse(dateMatch.group(3)!);

        if (year != null &&
            month != null &&
            day != null) {
          try {
            currentDate = DateTime(
              year,
              month,
              day,
            );
          } catch (_) {
            currentDate = null;
          }
        }

        continue;
      }

      final Match? messageMatch =
          _messagePattern.firstMatch(line);

      if (messageMatch == null) {
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

      final List<String> elements =
          line.trim().split(RegExp(r'\s+'));

      if (elements.length < 2) {
        continue;
      }

      final String participant =
          elements[1].trim();

      if (participant.isEmpty) {
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

      _favoriteCount +=
          _countOccurrences(line, '好き');

      _thanksCount +=
          _countOccurrences(line, '感謝');

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
      }
    }

    _calculateReplySpeed();

    if (_wordController.text.trim().isNotEmpty) {
      _calculateFreeWordInternal(
        _wordController.text.trim(),
      );
    }

    _calculateCompatibility();
  }

  void _calculateReplySpeed() {
    _replyTimeTotals.clear();
    _replyCounts.clear();
    _averageReplyMinutes.clear();

    if (_messages.length < 2) {
      return;
    }

    for (int i = 1; i < _messages.length; i++) {
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
          (_replyTimeTotals[current.participant] ?? 0) +
              difference;

      _replyCounts[current.participant] =
          (_replyCounts[current.participant] ?? 0) + 1;
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

  String _formatReplyTime(String participant) {
    final double? average =
        _averageReplyMinutes[participant];

    if (average == null) {
      return 'データ不足';
    }

    final int minutes = average.round();

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

  double _getAverageReply(String participant) {
    return _averageReplyMinutes[participant] ?? 0.0;
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

  void _calculateFreeWordInternal(String word) {
    _checkedWord = word;
    _wordCount =
        _countOccurrences(_talkText, word);
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
          text.indexOf(word, startIndex);

      if (index == -1) {
        break;
      }

      count++;

      startIndex = index + word.length;
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

    double messageScore = 0.0;

    if (_totalMessages >= 5000) {
      messageScore = 20.0;
    } else if (_totalMessages >= 2000) {
      messageScore = 18.0;
    } else if (_totalMessages >= 1000) {
      messageScore = 16.0;
    } else if (_totalMessages >= 500) {
      messageScore = 13.0;
    } else if (_totalMessages >= 200) {
      messageScore = 10.0;
    } else if (_totalMessages >= 100) {
      messageScore = 7.0;
    } else if (_totalMessages >= 30) {
      messageScore = 4.0;
    } else {
      messageScore = 2.0;
    }

    final int positiveWords =
        _favoriteCount + _thanksCount;

    double positiveScore = 0.0;

    if (positiveWords >= 100) {
      positiveScore = 20.0;
    } else if (positiveWords >= 50) {
      positiveScore = 18.0;
    } else if (positiveWords >= 30) {
      positiveScore = 16.0;
    } else if (positiveWords >= 20) {
      positiveScore = 14.0;
    } else if (positiveWords >= 10) {
      positiveScore = 11.0;
    } else if (positiveWords >= 5) {
      positiveScore = 8.0;
    } else if (positiveWords >= 1) {
      positiveScore = 4.0;
    }

    final double lateNightRatio =
        _totalMessages == 0
            ? 0.0
            : _lateNightCount / _totalMessages;

    double lateNightScore = 0.0;

    if (lateNightRatio >= 0.01 &&
        lateNightRatio <= 0.15) {
      lateNightScore = 15.0;
    } else if (lateNightRatio > 0.0 &&
        lateNightRatio < 0.25) {
      lateNightScore = 11.0;
    } else if (lateNightRatio == 0.0) {
      lateNightScore = 5.0;
    } else {
      lateNightScore = 7.0;
    }

    final double replyA =
        _getAverageReply(personA);

    final double replyB =
        _getAverageReply(personB);

    double balanceScore = 0.0;

    if (replyA > 0.0 && replyB > 0.0) {
      final double faster =
          replyA < replyB ? replyA : replyB;

      final double slower =
          replyA > replyB ? replyA : replyB;

      final double ratio =
          slower == 0.0
              ? 1.0
              : faster / slower;

      if (ratio >= 0.85) {
        balanceScore = 15.0;
      } else if (ratio >= 0.65) {
        balanceScore = 12.0;
      } else if (ratio >= 0.45) {
        balanceScore = 9.0;
      } else {
        balanceScore = 5.0;
      }
    } else {
      balanceScore = 7.0;
    }

    double participantScore = 0.0;

    if (people.length == 2) {
      participantScore = 10.0;
    } else if (people.length == 3) {
      participantScore = 6.0;
    } else {
      participantScore = 3.0;
    }

    double continuityScore = 0.0;

    final int activeWeekdays =
        _weekdayCounts
            .where((int value) => value > 0)
            .length;

    if (activeWeekdays >= 7) {
      continuityScore = 20.0;
    } else if (activeWeekdays >= 5) {
      continuityScore = 17.0;
    } else if (activeWeekdays >= 3) {
      continuityScore = 13.0;
    } else if (activeWeekdays >= 2) {
      continuityScore = 9.0;
    } else {
      continuityScore = 5.0;
    }

    double rawScore =
        messageScore +
        positiveScore +
        lateNightScore +
        balanceScore +
        participantScore +
        continuityScore;

    rawScore = rawScore.clamp(0.0, 100.0);

    _compatibilityScore = rawScore.round();

    double lasting =
        (_compatibilityScore * 0.55) +
        (continuityScore * 1.2) +
        (balanceScore * 0.8);

    if (positiveWords > 0) {
      lasting += 5.0;
    }

    if (lateNightRatio > 0.0 &&
        lateNightRatio < 0.2) {
      lasting += 4.0;
    }

    lasting = lasting.clamp(0.0, 100.0);

    _lastingScore = lasting.round();
  }

  int get _maxWeekdayCount {
    if (_weekdayCounts.isEmpty) {
      return 1;
    }

    final int maxValue =
        _weekdayCounts.reduce(
      (int a, int b) => a > b ? a : b,
    );

    return maxValue == 0 ? 1 : maxValue;
  }

  void _reset() {
    setState(() {
      _fileName = '';
      _talkText = '';

      _totalMessages = 0;

      _participants.clear();
      _messages.clear();

      for (int i = 0;
          i < _weekdayCounts.length;
          i++) {
        _weekdayCounts[i] = 0;
      }

      _favoriteCount = 0;
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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFFE8F8EC),
              Color(0xFFF7FBF8),
              Color(0xFFF5FAF6),
            ],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                expandedHeight: 155,
                backgroundColor:
                    const Color(0xFF20A04B),
                foregroundColor: Colors.white,
                elevation: 0,
                flexibleSpace:
                    FlexibleSpaceBar(
                  titlePadding:
                      const EdgeInsets.only(
                    left: 20,
                    bottom: 16,
                  ),
                  title: const Text(
                    'LINEトーク分析',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  background: Container(
                    decoration:
                        const BoxDecoration(
                      gradient:
                          LinearGradient(
                        begin:
                            Alignment.topLeft,
                        end:
                            Alignment.bottomRight,
                        colors: <Color>[
                          Color(0xFF159447),
                          Color(0xFF65CF83),
                        ],
                      ),
                    ),
                    child: const Align(
                      alignment:
                          Alignment.topRight,
                      child: Padding(
                        padding:
                            EdgeInsets.only(
                          top: 25,
                          right: 25,
                        ),
                        child: Icon(
                          Icons
                              .analytics_rounded,
                          size: 78,
                          color:
                              Colors.white24,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding:
                    const EdgeInsets.fromLTRB(
                  16,
                  20,
                  16,
                  30,
                ),
                sliver: SliverList(
                  delegate:
                      SliverChildListDelegate(
                    <Widget>[
                      _buildIntroduction(),
                      const SizedBox(height: 16),
                      _buildFilePickerCard(),
                      if (_errorMessage != null) ...<Widget>[
                        const SizedBox(height: 14),
                        _buildErrorCard(),
                      ],
                      if (_isLoading) ...<Widget>[
                        const SizedBox(height: 14),
                        _buildLoadingCard(),
                      ],
                      if (_fileName.isNotEmpty &&
                          !_isLoading) ...<Widget>[
                        const SizedBox(height: 18),
                        _buildFileInfoCard(),
                        const SizedBox(height: 18),
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
                        _buildLateNightCard(),
                        const SizedBox(height: 16),
                        _buildWeekdayChartCard(),
                        const SizedBox(height: 20),
                        _buildResetButton(),
                      ],
                      const SizedBox(height: 28),
                      _buildAdBanner(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntroduction() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          '二人のトークを\nちょっと本気で分析。',
          style: TextStyle(
            fontSize: 28,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: Color(0xFF183C24),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'メッセージ数、返信スピード、'
          '定番ワード、深夜トークまでまとめてチェック。',
          style: TextStyle(
            fontSize: 14,
            height: 1.6,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildFilePickerCard() {
    return _buildCard(
      child: Column(
        children: <Widget>[
          Container(
            width: 68,
            height: 68,
            decoration:
                BoxDecoration(
              color:
                  const Color(0xFFE3F6E8),
              borderRadius:
                  BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.file_open_rounded,
              color: Colors.green,
              size: 34,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'LINEトーク履歴を選択',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '.txtファイルに対応しています',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed:
                  _isLoading ? null : _pickFile,
              icon: const Icon(
                Icons.folder_open_rounded,
              ),
              label: const Text(
                'ファイルを選択する',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style:
                  FilledButton.styleFrom(
                backgroundColor:
                    Colors.green,
                foregroundColor:
                    Colors.white,
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileInfoCard() {
    return Container(
      padding:
          const EdgeInsets.all(14),
      decoration:
          BoxDecoration(
        color: const Color(0xFFE7F8EB),
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFC8ECCE),
        ),
      ),
      child: Row(
        children: <Widget>[
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
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '解析中のファイル',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _fileName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow:
                      TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.check_circle_rounded,
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildCompatibilityCard() {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(22),
      decoration:
          BoxDecoration(
        gradient:
            const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFFFFE8F0),
            Color(0xFFFFF5F8),
            Color(0xFFEFFAF3),
          ],
        ),
        borderRadius:
            BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFFFC6D8),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.pink.withValues(
              alpha: 0.10,
            ),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: const <Widget>[
              Text(
                '💗',
                style:
                    TextStyle(fontSize: 25),
              ),
              SizedBox(width: 8),
              Text(
                'ふたりのトーク診断',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight:
                      FontWeight.w800,
                  color: Color(0xFF9C3155),
                ),
              ),
              SizedBox(width: 8),
              Text(
                '💗',
                style:
                    TextStyle(fontSize: 25),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'トークデータから独自アルゴリズムで算出',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildScoreCircle(
                  title: '相性',
                  score:
                      _compatibilityScore,
                  suffix: '点',
                  color:
                      const Color(0xFFE95480),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildScoreCircle(
                  title: '長続き度',
                  score: _lastingScore,
                  suffix: '%',
                  color:
                      const Color(0xFF49A968),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.72,
              ),
              borderRadius:
                  BorderRadius.circular(14),
            ),
            child: Text(
              _getCompatibilityMessage(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6F3449),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '※この診断はトークデータを使ったエンタメ向けの簡易診断です。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              color: Colors.grey.shade600,
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
        vertical: 17,
      ),
      decoration:
          BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.8,
        ),
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Column(
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 9),
          Container(
            width: 94,
            height: 94,
            decoration:
                BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color,
                width: 5,
              ),
              color: Colors.white,
            ),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: <Widget>[
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
    if (_compatibilityScore >= 90) {
      return '🎉 トークデータ上ではかなり盛り上がっている二人！';
    }

    if (_compatibilityScore >= 80) {
      return '💞 会話のバランスが良く、かなり仲の良さが感じられます！';
    }

    if (_compatibilityScore >= 70) {
      return '😊 いい感じの会話量。これからのトークにも注目です！';
    }

    if (_compatibilityScore >= 60) {
      return '🌱 まだまだ伸びしろあり。二人の会話を楽しもう！';
    }

    if (_compatibilityScore >= 40) {
      return '✨ これからデータが増えるほど診断も変化していきます。';
    }

    return '💬 まずはたくさん話して、トークデータを増やしてみよう！';
  }

  Widget _buildBasicResultCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            icon: Icons.chat_rounded,
            title: '基本集計',
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
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
        color: const Color(0xFFF3FAF4),
        borderRadius:
            BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon,
            color: Colors.green,
            size: 22,
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                value,
                style: const TextStyle(
                  fontSize: 27,
                  fontWeight:
                      FontWeight.w800,
                  color: Color(0xFF185C2E),
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
        children: <Widget>[
          _buildSectionHeader(
            icon: Icons.groups_rounded,
            title: '参加者一覧',
            trailing:
                '${participants.length}人',
          ),
          const SizedBox(height: 14),
          if (participants.isEmpty)
            Text(
              '参加者を検出できませんでした。',
              style: TextStyle(
                color: Colors.grey.shade600,
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
                        0xFFEAF7ED,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        30,
                      ),
                    ),
                    child: Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: <Widget>[
                        const Icon(
                          Icons
                              .person_rounded,
                          size: 17,
                          color:
                              Colors.green,
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
                              0xFF276C3A,
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
        children: <Widget>[
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
              color: Colors.grey.shade700,
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
                    const Color(0xFFF5F7F6),
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
              ),
              child: const Text(
                '2人以上の参加者データが必要です。',
                textAlign: TextAlign.center,
              ),
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child:
                      _buildReplyPersonCard(
                    people[0],
                    const Color(
                      0xFF4D9DE0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child:
                      _buildReplyPersonCard(
                    people[1],
                    const Color(
                      0xFFE86A92,
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
    final double average =
        _getAverageReply(participant);

    final int replyCount =
        _replyCounts[participant] ?? 0;

    return Container(
      padding:
          const EdgeInsets.all(15),
      decoration:
          BoxDecoration(
        color: color.withValues(
          alpha: 0.08,
        ),
        borderRadius:
            BorderRadius.circular(17),
        border: Border.all(
          color: color.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          CircleAvatar(
            radius: 24,
            backgroundColor:
                color.withValues(
              alpha: 0.15,
            ),
            child: Icon(
              Icons.person_rounded,
              color: color,
              size: 25,
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
            _formatReplyTime(participant),
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
              color: Colors.grey.shade600,
            ),
          ),
          if (average > 0) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              '${average.round()}分',
              style: TextStyle(
                fontSize: 9,
                color: color,
              ),
            ),
          ],
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

    if (a <= 0.0 || b <= 0.0) {
      return Container(
        width: double.infinity,
        padding:
            const EdgeInsets.all(12),
        decoration:
            BoxDecoration(
          color:
              const Color(0xFFF5F7F6),
          borderRadius:
              BorderRadius.circular(12),
        ),
        child: const Text(
          '返信スピードの比較には、両者の返信データが必要です。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12),
        ),
      );
    }

    final double maxValue =
        a > b ? a : b;

    final double aRatio =
        a / maxValue;

    final double bRatio =
        b / maxValue;

    final int aFlex =
        (aRatio * 100).round().clamp(1, 100);

    final int bFlex =
        (bRatio * 100).round().clamp(1, 100);

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '返信時間のバランス',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius:
              BorderRadius.circular(20),
          child: Row(
            children: <Widget>[
              Expanded(
                flex: aFlex,
                child: Container(
                  height: 13,
                  color:
                      const Color(0xFF4D9DE0),
                ),
              ),
              Expanded(
                flex: bFlex,
                child: Container(
                  height: 13,
                  color:
                      const Color(0xFFE86A92),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Row(
          mainAxisAlignment:
              MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Flexible(
              child: Text(
                '$personA：${a.round()}分',
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF4D9DE0),
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
                  color: Color(0xFFE86A92),
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

  Widget _buildFreeWordCard() {
    return Container(
      padding:
          const EdgeInsets.all(20),
      decoration:
          BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFD5E9FF),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.blue.withValues(
              alpha: 0.05,
            ),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(0xFFE6F2FF),
                  borderRadius:
                      BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color:
                      Color(0xFF3188D6),
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Text(
                  '自由ワードチェック',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight:
                        FontWeight.bold,
                    color:
                        Color(0xFF174D7A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '好きな言葉を入力して、トーク全体で何回登場したか調べます。',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: <Widget>[
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
                        '例：デート、名前',
                    prefixIcon:
                        const Icon(
                      Icons.edit_rounded,
                      color:
                          Color(0xFF3188D6),
                    ),
                    filled: true,
                    fillColor:
                        const Color(0xFFF4F8FC),
                    border:
                        OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                      borderSide:
                          BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 14,
                      vertical: 14,
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
                        const Color(0xFF3188D6),
                    foregroundColor:
                        Colors.white,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 17,
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
          if (_checkedWord.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(17),
              decoration:
                  const BoxDecoration(
                gradient:
                    LinearGradient(
                  colors: <Color>[
                    Color(0xFFE8F3FF),
                    Color(0xFFF3F8FF),
                  ],
                ),
                borderRadius:
                    BorderRadius.all(
                  Radius.circular(15),
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color:
                        Color(0xFF3188D6),
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
                          Color(0xFF246EAF),
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
        _favoriteCount + _thanksCount;

    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            icon: Icons.favorite_rounded,
            title: '定番ワード',
            trailing: '合計 $total 回',
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: _buildWordResult(
                  word: '好き',
                  count: _favoriteCount,
                  icon:
                      Icons.favorite_rounded,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildWordResult(
                  word: '感謝',
                  count: _thanksCount,
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
            const Color(0xFFF7FAF7),
        borderRadius:
            BorderRadius.circular(15),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            icon,
            color: Colors.green,
            size: 25,
          ),
          const SizedBox(height: 8),
          Text(
            word,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$count回',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF226B36),
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
          colors: <Color>[
            Color(0xFF173B28),
            Color(0xFF276443),
          ],
        ),
        borderRadius:
            BorderRadius.all(
          Radius.circular(20),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 55,
            height: 55,
            decoration:
                BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.12,
              ),
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
              children: <Widget>[
                Text(
                  '深夜トーク',
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
                    color: Colors.white70,
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

  Widget _buildWeekdayChartCard() {
    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            icon:
                Icons.bar_chart_rounded,
            title: '曜日別の発言頻度',
          ),
          const SizedBox(height: 7),
          Text(
            '曜日ごとのメッセージ数を表示しています。',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children:
                  List<Widget>.generate(
                7,
                (int index) {
                  final int count =
                      _weekdayCounts[index];

                  final double ratio =
                      count /
                          _maxWeekdayCount;

                  final double barHeight =
                      ratio == 0.0
                          ? 8.0
                          : 20.0 +
                              (150.0 * ratio);

                  return Expanded(
                    child: Padding(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 4,
                      ),
                      child: Column(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .end,
                        children: <Widget>[
                          Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  FontWeight.bold,
                              color:
                                  Colors.grey
                                      .shade700,
                            ),
                          ),
                          const SizedBox(
                              height: 5),
                          AnimatedContainer(
                            duration:
                                const Duration(
                              milliseconds: 500,
                            ),
                            curve:
                                Curves.easeOut,
                            height: barHeight,
                            width:
                                double.infinity,
                            decoration:
                                const BoxDecoration(
                              gradient:
                                  LinearGradient(
                                begin:
                                    Alignment
                                        .topCenter,
                                end:
                                    Alignment
                                        .bottomCenter,
                                colors: <Color>[
                                  Color(
                                      0xFF65CE82),
                                  Color(
                                      0xFF2DA653),
                                ],
                              ),
                              borderRadius:
                                  BorderRadius
                                      .vertical(
                                top:
                                    Radius.circular(
                                  9,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(
                              height: 8),
                          Text(
                            _weekdays[index],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  FontWeight.bold,
                              color:
                                  Colors.grey
                                      .shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdBanner() {
    return Container(
      width: double.infinity,
      height: 70,
      decoration:
          BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius:
            BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        'ここにGoogle AdMobの広告が表示されます',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
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
            fontWeight: FontWeight.bold,
          ),
        ),
        style:
            OutlinedButton.styleFrom(
          foregroundColor: Colors.green,
          side: const BorderSide(
            color: Colors.green,
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
        children: <Widget>[
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
        children: <Widget>[
          SizedBox(
            width: 30,
            height: 30,
            child:
                CircularProgressIndicator(
              color: Colors.green,
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'トーク履歴を解析しています…',
            style: TextStyle(
              fontWeight: FontWeight.bold,
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
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.045,
            ),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
  }) {
    return Row(
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration:
              BoxDecoration(
            color:
                const Color(0xFFE6F7EA),
            borderRadius:
                BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.green,
            size: 21,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: Color(0xFF183C24),
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
                  const Color(0xFFEAF7ED),
              borderRadius:
                  BorderRadius.circular(20),
            ),
            child: Text(
              trailing,
              style: const TextStyle(
                color: Color(0xFF24823D),
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