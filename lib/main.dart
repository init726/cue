import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_calendar/device_calendar.dart' as calendar;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'cue_api.dart';
import 'cue_categories.dart';
import 'cue_design.dart';
import 'cue_route.dart';
import 'cue_splash.dart';
import 'saved_event_editor.dart';

// 흰 바탕 위에 옅은 회색 카드를 올리고, 강조색은 한 화면에 한 곳에만 쓴다.
const ink = Color(0xFF191F28);
const muted = Color(0xFF6B7684);
const paper = Color(0xFFFFFFFF);
const accent = Color(0xFF169ED3);
const mint = Color(0xFFE6F5FB);
final cueThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
const cueApiUrl = String.fromEnvironment(
  'CUE_API_URL',
  defaultValue: 'http://localhost:8787',
);

ThemeData cueTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF17171C) : paper;
  final surface = dark ? const Color(0xFF232329) : const Color(0xFFF2F4F6);
  final foreground = dark ? const Color(0xFFECEEF0) : ink;
  final blue = dark ? const Color(0xFF55C7F3) : accent;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Pretendard',
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
      surface: surface,
    ),
    dividerColor: dark ? const Color(0xFF303438) : const Color(0xFFE8EBEE),
    // 물결 효과 대신 iOS처럼 눌린 동안만 옅게 표시한다.
    splashFactory: NoSplash.splashFactory,
    highlightColor: dark ? const Color(0x14FFFFFF) : const Color(0x0F000000),
    navigationBarTheme: NavigationBarThemeData(
      height: 58,
      elevation: 0,
      backgroundColor: background,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontFamily: 'Pretendard',
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? foreground : (dark ? const Color(0xFF8A9097) : muted),
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        size: 24,
        color: states.contains(WidgetState.selected) ? foreground : (dark ? const Color(0xFF8A9097) : muted),
      )),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      backgroundColor: blue,
      foregroundColor: dark ? const Color(0xFF101214) : Colors.white,
      minimumSize: const Size(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CueRadius.control)),
      textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w600),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CueRadius.control)),
      textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 16, fontWeight: FontWeight.w600),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(
      foregroundColor: blue,
      textStyle: const TextStyle(fontFamily: 'Pretendard', fontSize: 15, fontWeight: FontWeight.w600),
    )),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide.none,
      showCheckmark: false,
      backgroundColor: surface,
      selectedColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      labelStyle: TextStyle(fontFamily: 'Pretendard', fontSize: 14, fontWeight: FontWeight.w500, color: foreground),
      secondaryLabelStyle: TextStyle(fontFamily: 'Pretendard', fontSize: 14, fontWeight: FontWeight.w600, color: background),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: dark ? const Color(0xFF2A2E32) : const Color(0xFF23262A),
      contentTextStyle: const TextStyle(fontFamily: 'Pretendard', color: Colors.white, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CueRadius.control)),
      actionTextColor: blue,
    ),
    textTheme: TextTheme(
      headlineLarge: CueType.largeTitle.copyWith(color: foreground),
      titleLarge: CueType.title.copyWith(color: foreground),
      bodyMedium: TextStyle(fontSize: 15, color: foreground, height: 1.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // 입력칸은 회색 카드 위에 놓이므로 바탕색으로 채운다.
      fillColor: background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CueRadius.control),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (useSupabaseAuth) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }
  runApp(const CueApp());
}

class CueApp extends StatelessWidget {
  const CueApp({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: cueThemeMode,
    builder: (_, mode, _) => MaterialApp(
      title: 'Cue',
      debugShowCheckedModeBanner: false,
      theme: cueTheme(Brightness.light),
      darkTheme: cueTheme(Brightness.dark),
      themeMode: mode,
      home: const CueHome(),
    ),
  );
}

enum ScanStage { idle, processing, notEvent, pastEvent, review, saved }

class CueDocument {
  CueDocument(this.path, this.name);
  final String path;
  final String name;
  int? lengthSync() => File(path).lengthSync();
  Future<int?> length() async => File(path).length();
  Future<List<int>> readAsBytes() => File(path).readAsBytes();
}

class CueHome extends StatefulWidget {
  const CueHome({super.key});
  @override
  State<CueHome> createState() => _CueHomeState();
}

class _CueHomeState extends State<CueHome> with WidgetsBindingObserver {
  static const shareChannel = MethodChannel('cue/shared');
  bool readyForShares = false;
  bool takingSharedFile = false;
  bool get isDark => Theme.of(context).brightness == Brightness.dark;
  Color get ink => isDark ? Color(0xFFECEEF0) : Color(0xFF191F28);
  Color get muted => isDark ? Color(0xFF9EA6B0) : Color(0xFF6B7684);
  Color get paper => isDark ? Color(0xFF17171C) : Color(0xFFFFFFFF);
  Color get accent => isDark ? Color(0xFF55C7F3) : Color(0xFF169ED3);
  Color get mint => isDark ? Color(0xFF1F3540) : Color(0xFFE6F5FB);
  Color get surface => isDark ? Color(0xFF232329) : Color(0xFFF2F4F6);
  Color get borderColor => isDark ? Color(0xFF2F2F36) : Color(0xFFE5E8EB);
  Color get cameraCard => isDark ? Color(0xFF202326) : Color(0xFF169ED3);

  final api = CueApi(cueApiUrl);
  final picker = ImagePicker();
  final calendarPlugin = calendar.DeviceCalendarPlugin();
  final titleController = TextEditingController();
  final venueController = TextEditingController();
  final deadlineController = TextEditingController();
  final feeController = TextEditingController();
  bool showUnknownInputs = false;
  // 추천 탭에서 '일정에 추가'로 들어온 확인 화면이면 돌아갈 곳을 추천 탭으로 한다.
  bool fromRecommendation = false;
  int tab = 0;
  int tabDirection = 1;
  int reviewStep = 0;
  int reviewDirection = 1;
  ScanStage stage = ScanStage.idle;
  File? image;
  CueDocument? document;
  CueEvent? candidate;
  int? selectedSession;
  String? pastEventTitle;
  String? pastEventEndedAt;
  Set<String> interestedIds = {};
  int? recommendationSeed;
  DateTime? startsAt;
  DateTime? endsAt;
  int reminderMinutes = 60;
  int defaultReminderMinutes = 60;
  int defaultDurationMinutes = 120;
  String? preferredCalendarId;
  String preferredCalendarName = '기기 기본 캘린더';
  String selectedCategory = '기타';
  bool loading = true;
  bool onboardingCompleted = false;
  bool onboardingPreferencesDirty = false;
  bool saving = false;
  bool personalizationEnabled = true;
  bool recommendationEnabled = true;
  bool recommendationLoading = false;
  String? userId;
  bool cloudConnected = false;
  String? busyEventId;
  // 실험: 내 일정을 하루 노선으로 보여준다. 목록 보기와 비교할 수 있게 전환을 남겨 둔다.
  bool routeView = true;
  DateTime? routeFocusDate;
  bool showDeveloperInfo = false;
  String? settingsSection;
  String communitySchool = '';
  String communityRegion = '';
  String communityAgeBand = '';
  String recommendationSource = 'all';
  bool sharingEvent = false;
  int routeFocusRequest = 0;
  String? statusMessage;
  String? apiError;
  // 화면에는 apiError(쉬운 문장)를, '자세히'에서는 원문을 보여준다.
  String? apiErrorDetail;
  // 분석을 취소하면 번호가 바뀌어 늦게 도착한 결과를 버린다.
  int analysisRun = 0;
  List<Map<String, dynamic>> saved = [];
  List<Map<String, dynamic>> recommended = [];
  Timer? progressTimer;

  void _selectTab(int value) {
    if (value == tab) return;
    setState(() {
      tabDirection = value > tab ? 1 : -1;
      tab = value;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_takeSharedFile());
  }

  Future<void> _takeSharedFile() async {
    if (!Platform.isIOS || !readyForShares || takingSharedFile) return;
    takingSharedFile = true;
    try {
      final path = await shareChannel.invokeMethod<String>('takeSharedFile');
      if (path == null || !mounted) return;
      final shared = File(path);
      if (!await shared.exists()) return;
      final extension = path.toLowerCase();
      setState(() {
        tabDirection = -1;
        tab = 0;
        stage = ScanStage.idle;
        candidate = null;
        if (extension.endsWith('.pdf')) {
          document = CueDocument(path, '공유한 문서.pdf');
          image = null;
        } else {
          image = shared;
          document = null;
        }
      });
      await _analyze();
    } catch (error) { _error(error, fallback: '공유한 파일을 열지 못했어요.'); }
    finally { takingSharedFile = false; }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    progressTimer?.cancel();
    titleController.dispose();
    venueController.dispose();
    deadlineController.dispose();
    feeController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final minimum = Future<void>.delayed(Duration(milliseconds: 1100));
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    cueThemeMode.value = switch (prefs.getString('theme_mode')) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    defaultReminderMinutes = prefs.getInt('default_reminder_minutes') ?? 60;
    onboardingCompleted = prefs.getBool('cue_onboarding_completed') ?? false;
    interestedIds = (prefs.getStringList('interested_events') ?? []).toSet();
    reminderMinutes = defaultReminderMinutes;
    defaultDurationMinutes = prefs.getInt('default_duration_minutes') ?? 120;
    preferredCalendarId = prefs.getString('preferred_calendar_id');
    preferredCalendarName =
        prefs.getString('preferred_calendar_name') ?? '기기 기본 캘린더';
    await minimum;
    if (!mounted) return;
    setState(() => loading = false);
    unawaited(() async {
      await _refresh();
      readyForShares = true;
      await _takeSharedFile();
    }());
  }

  Future<void> _refresh({bool shuffle = false}) async {
    if (mounted) setState(() => recommendationLoading = true);
    // 새로고침(shuffle)이면 새 seed와 방금 본 행사를 보내 서버가 다른 조합을 고르게 한다.
    var recommendationRoute = '/v1/recommendations';
    if (shuffle) {
      recommendationSeed = DateTime.now().millisecondsSinceEpoch % 1000000000;
      final seen = recommended.map((event) => event['id']).whereType<String>().take(40).join(',');
      recommendationRoute += '?seed=$recommendationSeed&seen=$seen';
    } else if (recommendationSeed != null) {
      recommendationRoute += '?seed=$recommendationSeed';
    }
    try {
      await api.init();
      await _syncOnboarding();
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList('pending_event_deletions') ?? [];
      for (final id in pending) {
        try {
          await api.delete('/v1/events/$id');
        } on CueApiException catch (error) {
          if (error.status != 404) break;
        }
        await prefs.setStringList(
          'pending_event_deletions',
          (prefs.getStringList('pending_event_deletions') ?? [])..remove(id),
        );
      }
      final responses = await Future.wait([
        api.get('/v1/me'),
        api.get(recommendationRoute),
      ]);
      final me = responses[0];
      final recs = responses[1];
      if (!mounted) return;
      setState(() {
        final profile = me['profile'] as Map<String, dynamic>? ?? {};
        communitySchool = profile['school'] as String? ?? '';
        communityRegion = profile['region'] as String? ?? '';
        communityAgeBand = profile['ageBand'] as String? ?? '';
        userId = me['userId'] as String?;
        cloudConnected = me['cloudConnected'] as bool? ?? false;
        onboardingCompleted = onboardingCompleted ||
            (profile['onboardingCompleted'] as bool? ?? false);
        if (!onboardingPreferencesDirty) {
          personalizationEnabled =
              profile['personalizationEnabled'] as bool? ?? true;
          recommendationEnabled =
              profile['recommendationEnabled'] as bool? ?? true;
        }
        final pendingIds =
            (prefs.getStringList('pending_event_deletions') ?? []).toSet();
        saved = (me['saved'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .where((event) => !pendingIds.contains(event['id']))
            .toList();
        recommended = (recs['events'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        recommendationLoading = false;
        apiError = null;
        apiErrorDetail = null;
      });
      if (onboardingCompleted) {
        await prefs.setBool('cue_onboarding_completed', true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          recommendationLoading = false;
          apiError = _friendly(error);
          apiErrorDetail = error.toString();
        });
      }
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await picker.pickImage(
        source: source,
        imageQuality: 78,
        maxWidth: 1800,
      );
      if (picked == null || !mounted) return;
      setState(() {
        image = File(picked.path);
        document = null;
        stage = ScanStage.idle;
        statusMessage = null;
      });
      await _analyze();
    } catch (error) {
      _error(error, fallback: '사진을 열지 못했어요.');
    }
  }

  Future<void> _pickDocument() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'hwp', 'hwpx'],
      );
      if (files.isEmpty || !mounted) return;
      final picked = files.single;
      if (picked.path == null) throw CueApiException('문서 경로를 읽지 못했어요. 다시 선택해 주세요.');
      final length = picked.lengthSync() ?? await picked.length();
      if (length == null || length == 0 || length > 10 * 1024 * 1024) {
        throw CueApiException('10MB 이하의 PDF 또는 한글 파일을 선택해 주세요.');
      }
      if (!mounted) return;
      setState(() {
        document = CueDocument(picked.path!, picked.name);
        image = null;
        stage = ScanStage.idle;
        statusMessage = null;
      });
      await _analyze();
    } catch (error) {
      _error(error, fallback: '문서를 열지 못했어요.');
    }
  }

  Future<void> _analyze() async {
    if (image == null && document == null) return;
    final run = ++analysisRun;
    if (apiError != null) {
      await _refresh();
      if (apiError != null) {
        _message(apiError!);
        return;
      }
    }
    if (run != analysisRun) return;
    setState(() {
      stage = ScanStage.processing;
      statusMessage = '행사 안내물인지 확인하는 중';
    });
    progressTimer?.cancel();
    progressTimer = Timer(Duration(seconds: 4), () {
      if (mounted && stage == ScanStage.processing) {
        setState(() => statusMessage = '행사라면 시간과 장소를 정리하는 중');
      }
    });
    try {
      final source = <String, dynamic>{};
      if (document != null) {
        final bytes = await document!.readAsBytes();
        if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
          throw CueApiException('10MB 이하의 PDF 또는 한글 파일을 선택해 주세요.');
        }
        source['file'] = {'name': document!.name, 'data': base64Encode(bytes)};
      } else {
        final bytes = await image!.readAsBytes();
        if (bytes.length > 5 * 1024 * 1024) {
          throw CueApiException('사진이 너무 커요. 5MB 이하 이미지를 선택해 주세요.');
        }
        final ext = image!.path.toLowerCase();
        final mime = ext.endsWith('.png')
            ? 'png'
            : ext.endsWith('.webp')
            ? 'webp'
            : 'jpeg';
        source['image'] = 'data:image/$mime;base64,${base64Encode(bytes)}';
      }
      final result = await api.post('/v1/analyze', {
        ...source,
        'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        'defaultDurationMinutes': defaultDurationMinutes,
      });
      if (!mounted || run != analysisRun) return;
      if (result['status'] == 'past_event') {
        setState(() {
          stage = ScanStage.pastEvent;
          candidate = null;
          pastEventTitle = result['title'] as String?;
          pastEventEndedAt = result['endedAt'] as String?;
        });
        return;
      }
      if (result['status'] != 'event') {
        setState(() {
          stage = ScanStage.notEvent;
          candidate = null;
        });
        return;
      }
      final event = CueEvent.fromJson(result['event'] as Map<String, dynamic>);
      setState(() {
        candidate = event;
        stage = ScanStage.review;
        reviewStep = 0;
        titleController.text = event.title;
        selectedCategory = event.category;
        deadlineController.text = event.applicationDeadline == null ? '' : event.applicationDeadline!.substring(0, 10);
        feeController.text = event.participationFee ?? '';
        showUnknownInputs = false;
        selectedSession = event.sessions.length == 1 ? 0 : null;
        _applySession(selectedSession);
      });
    } catch (error) {
      if (mounted && run == analysisRun) {
        setState(() => stage = ScanStage.idle);
        _error(error);
      }
    } finally {
      if (run == analysisRun) progressTimer?.cancel();
    }
  }

  void _applySession(int? index) {
    if (index == null || candidate == null) {
      startsAt = null;
      endsAt = null;
      venueController.text = '';
      return;
    }
    final value = candidate!.sessions[index];
    startsAt = value.startsAt;
    endsAt = value.endsAt;
    venueController.text = value.venue;
  }

  static const _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
  String _dateOnly(DateTime value) =>
      '${value.year == DateTime.now().year ? '' : '${value.year}년 '}${value.month}월 ${value.day}일 (${_weekdayNames[value.weekday - 1]})';
  String _timeOnly(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  // 날짜가 불분명하거나 직접 고르고 싶을 때 쓰는 일정 입력 시트. 날짜·시작/종료 시간·장소를 한 곳에서 정한다.
  // forced면 바깥을 눌러도, 아래로 밀어도, 뒤로가기로도 닫히지 않고 선택을 마치거나 분석을 취소해야만 나갈 수 있다.
  Future<bool> _editSchedule({bool ambiguous = false, bool forced = false}) async {
    if (!mounted) return false;
    final now = DateTime.now();
    var start = startsAt ?? DateTime(now.year, now.month, now.day + 1, 14);
    var end = endsAt ?? start.add(Duration(minutes: defaultDurationMinutes));
    final venueField = TextEditingController(text: venueController.text);
    String? problem;
    final result = await showModalBottomSheet<(DateTime, DateTime, String)>(
      context: context,
      isScrollControlled: true,
      isDismissible: !forced,
      enableDrag: !forced,
      showDragHandle: !forced,
      builder: (sheetContext) => PopScope(
        canPop: !forced,
        child: StatefulBuilder(
        builder: (context, setSheet) {
          Future<void> pickDate() async {
            final picked = await showDatePicker(
              context: context,
              initialDate: start.isBefore(now) ? now : start,
              firstDate: DateTime(now.year - 1),
              lastDate: DateTime(now.year + 5),
            );
            if (picked == null) return;
            setSheet(() {
              start = DateTime(picked.year, picked.month, picked.day, start.hour, start.minute);
              end = DateTime(picked.year, picked.month, picked.day, end.hour, end.minute);
              problem = null;
            });
          }

          Future<void> pickTime(bool beginning) async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(beginning ? start : end),
            );
            if (picked == null) return;
            setSheet(() {
              if (beginning) {
                final length = end.difference(start);
                start = DateTime(start.year, start.month, start.day, picked.hour, picked.minute);
                end = start.add(length.isNegative || length == Duration.zero
                    ? Duration(minutes: defaultDurationMinutes)
                    : length);
              } else {
                end = DateTime(start.year, start.month, start.day, picked.hour, picked.minute);
              }
              problem = null;
            });
          }

          Widget row(IconData icon, String label, String value, VoidCallback onTap) =>
              InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(CueRadius.control),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  margin: EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(CueRadius.control),
                  ),
                  child: Row(children: [
                    Icon(icon, color: accent, size: 22),
                    SizedBox(width: 12),
                    Expanded(child: Text(label, style: TextStyle(color: muted))),
                    Text(value, style: TextStyle(color: ink, fontWeight: FontWeight.w600, fontSize: 16)),
                    SizedBox(width: 4),
                    Icon(Icons.chevron_right, color: muted),
                  ]),
                ),
              );

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 2, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ambiguous ? '날짜와 시간을 정해 주세요' : '일정을 직접 입력해요',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink),
                    ),
                    SizedBox(height: 6),
                    Text(
                      ambiguous
                          ? '안내문에서 날짜나 시간, 장소가 분명하지 않았어요. 아래에서 직접 골라 주세요.'
                          : '캘린더에 저장할 날짜, 시간, 장소를 골라 주세요.',
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                    SizedBox(height: 16),
                    row(Icons.event_outlined, '날짜', _dateOnly(start), pickDate),
                    row(Icons.schedule, '시작', _timeOnly(start), () => pickTime(true)),
                    row(Icons.timelapse_outlined, '종료', _timeOnly(end), () => pickTime(false)),
                    SizedBox(height: 3),
                    TextField(
                      controller: venueField,
                      decoration: InputDecoration(
                        labelText: '장소',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                    ),
                    if (problem != null) ...[
                      SizedBox(height: 8),
                      Text(problem!, style: TextStyle(color: Color(0xFFE5484D), fontSize: 13)),
                    ],
                    SizedBox(height: 16),
                    _button('이 일정으로 정하기', Icons.check, () {
                      if (venueField.text.trim().isEmpty) {
                        setSheet(() => problem = '장소를 입력해 주세요.');
                      } else if (!end.isAfter(start)) {
                        setSheet(() => problem = '종료 시간이 시작 시간보다 늦어야 해요.');
                      } else {
                        Navigator.pop(sheetContext, (start, end, venueField.text.trim()));
                      }
                    }),
                    if (forced)
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(sheetContext),
                          child: Text('취소하고 다른 안내물 선택'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      ),
    );
    venueField.dispose();
    if (result == null || !mounted) return false;
    setState(() {
      startsAt = result.$1;
      endsAt = result.$2;
      venueController.text = result.$3;
      selectedSession = null;
    });
    return true;
  }

  Future<void> _chooseCalendar() async {
    try {
      final permission = await calendarPlugin.requestPermissions();
      if (permission.data != true) throw CueApiException('캘린더 권한이 필요해요.');
      final result = await calendarPlugin.retrieveCalendars();
      final calendars =
          result.data
              ?.where((item) => item.isReadOnly != true && item.id != null)
              .toList() ??
          [];
      if (!mounted) return;
      final chosen = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: Icon(Icons.phone_iphone, color: accent),
                title: Text('기기 기본 캘린더'),
                onTap: () => Navigator.pop(sheetContext, ''),
              ),
              for (final item in calendars)
                ListTile(
                  leading: Icon(Icons.calendar_month_outlined, color: accent),
                  title: Text(item.name ?? '이름 없는 캘린더'),
                  subtitle: item.isDefault == true ? Text('기기 기본값') : null,
                  onTap: () => Navigator.pop(sheetContext, item.id),
                ),
            ],
          ),
        ),
      );
      if (!mounted || chosen == null) return;
      final selected = calendars.where((item) => item.id == chosen).firstOrNull;
      setState(() {
        preferredCalendarId = chosen.isEmpty ? null : chosen;
        preferredCalendarName = selected?.name ?? '기기 기본 캘린더';
      });
      final prefs = await SharedPreferences.getInstance();
      if (preferredCalendarId == null) {
        await prefs.remove('preferred_calendar_id');
      } else {
        await prefs.setString('preferred_calendar_id', preferredCalendarId!);
      }
      await prefs.setString('preferred_calendar_name', preferredCalendarName);
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _save() async {
    if (candidate == null) return;
    if (candidate!.sessions.length > 1 && selectedSession == null && startsAt == null) {
      _message('시간과 장소 중 하나를 선택해 주세요.');
      unawaited(_chooseSession());
      return;
    }
    final title = titleController.text.trim();
    final venue = venueController.text.trim();
    if (title.isEmpty || venue.isEmpty || startsAt == null || endsAt == null) {
      _message('행사 이름, 장소, 시간을 확인해 주세요.');
      return;
    }
    if (!endsAt!.isAfter(startsAt!)) {
      _message('종료 시간이 시작 시간보다 빨라요.');
      return;
    }
    if (deadlineController.text.trim().isNotEmpty &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(deadlineController.text.trim()) ||
         DateTime.tryParse(deadlineController.text.trim()) == null)) {
      _message('신청 마감일은 YYYY-MM-DD 형식으로 입력해 주세요.');
      return;
    }
    setState(() => saving = true);
    try {
      final permission = await calendarPlugin.requestPermissions();
      if (permission.data != true) {
        throw CueApiException('캘린더 권한이 필요해요. 기기 설정에서 허용해 주세요.');
      }
      final list = await calendarPlugin.retrieveCalendars();
      final calendars =
          list.data
              ?.where((item) => item.isReadOnly != true && item.id != null)
              .toList() ??
          [];
      if (calendars.isEmpty) throw CueApiException('저장할 수 있는 캘린더가 없어요.');
      final target =
          calendars
              .where((item) => item.id == preferredCalendarId)
              .firstOrNull ??
          calendars.where((item) => item.isDefault == true).firstOrNull ??
          calendars.first;
      final event = calendar.Event(
        target.id,
        title: title,
        location: venue,
        description: candidate!.description,
        start: tz.TZDateTime.from(startsAt!, tz.UTC),
        end: tz.TZDateTime.from(endsAt!, tz.UTC),
        reminders: reminderMinutes == -1
            ? []
            : [calendar.Reminder(minutes: reminderMinutes)],
      );
      final result = await calendarPlugin.createOrUpdateEvent(event);
      if (result?.isSuccess != true || result?.data == null) {
        throw CueApiException('캘린더에 저장하지 못했어요.');
      }
      if (!mounted) return;
      setState(() => stage = ScanStage.saved);
      try {
        await api.post('/v1/events', {
          'title': title,
          'venue': venue,
          'startsAt': startsAt!.toUtc().toIso8601String(),
          'endsAt': endsAt!.toUtc().toIso8601String(),
          'category': selectedCategory,
          'description': candidate!.description,
          'tags': candidate!.tags,
          'format': candidate!.format,
          'domains': candidate!.domains,
          'applicationDeadline': deadlineController.text.trim().isEmpty
              ? null : DateTime.tryParse('${deadlineController.text.trim()}T23:59:00')?.toUtc().toIso8601String(),
          'participationFee': feeController.text.trim().isEmpty ? null : feeController.text.trim(),
          'calendarId': target.id,
          'calendarEventId': result!.data,
          'reminderMinutes': reminderMinutes,
        });
        await _refresh();
      } catch (_) {
        _message('캘린더에는 저장됐지만 Cue 기록에는 아직 반영되지 않았어요.');
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<calendar.Event> _resolveSavedEvent(
    Map<String, dynamic> savedEvent,
  ) async {
    final permission = await calendarPlugin.requestPermissions();
    if (permission.data != true) {
      throw CueApiException('캘린더 권한이 필요해요. 기기 설정에서 허용해 주세요.');
    }
    final calendarId = savedEvent['calendarId'] as String?;
    final eventId = savedEvent['calendarEventId'] as String?;
    if (calendarId != null && eventId != null) {
      final result = await calendarPlugin.retrieveEvents(
        calendarId,
        calendar.RetrieveEventsParams(eventIds: [eventId]),
      );
      final matches =
          result.data?.where((item) => item.eventId == eventId).toList() ?? [];
      if (result.isSuccess != true || matches.length != 1) {
        throw CueApiException('연결된 캘린더 일정을 찾지 못했어요. 캘린더에서 직접 확인해 주세요.');
      }
      return matches.single;
    }
    // Records saved before calendar IDs were stored can be linked only by a unique exact match.
    final calendars = await calendarPlugin.retrieveCalendars();
    if (calendars.isSuccess != true) throw CueApiException('캘린더 목록을 읽지 못했어요.');
    final start = DateTime.parse(savedEvent['startsAt'] as String);
    final end = DateTime.parse(savedEvent['endsAt'] as String);
    final matches = <calendar.Event>[];
    for (final item in calendars.data ?? []) {
      if (item.id == null || item.isReadOnly == true) continue;
      final result = await calendarPlugin.retrieveEvents(
        item.id,
        calendar.RetrieveEventsParams(
          startDate: start.subtract(Duration(days: 1)),
          endDate: end.add(Duration(days: 1)),
        ),
      );
      if (result.isSuccess != true) continue;
      matches.addAll(
        result.data?.where(
              (event) =>
                  event.eventId != null &&
                  event.title?.trim() == savedEvent['title'] &&
                  event.location?.trim() == savedEvent['venue'] &&
                  event.start != null &&
                  event.end != null &&
                  event.start!.toUtc().difference(start).inSeconds.abs() < 60 &&
                  event.end!.toUtc().difference(end).inSeconds.abs() < 60,
            ) ??
            <calendar.Event>[],
      );
    }
    if (matches.length != 1) {
      throw CueApiException(
        matches.isEmpty
            ? '기존 기록과 일치하는 캘린더 일정을 찾지 못했어요.'
            : '같은 일정이 여러 개라 안전하게 고를 수 없어요. 캘린더에서 직접 수정해 주세요.',
      );
    }
    return matches.single;
  }

  Future<void> _editSaved(Map<String, dynamic> savedEvent) async {
    final id = savedEvent['id'] as String;
    setState(() => busyEventId = id);
    try {
      final deviceEvent = await _resolveSavedEvent(savedEvent);
      if (!mounted) return;
      setState(() => busyEventId = null);
      final draft = await Navigator.push<SavedEventDraft>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SavedEventEditor(saved: savedEvent, calendarEvent: deviceEvent),
        ),
      );
      if (draft == null || !mounted) return;
      setState(() => busyEventId = id);
      final previous = calendar.Event(
        deviceEvent.calendarId,
        eventId: deviceEvent.eventId,
        title: deviceEvent.title,
        location: deviceEvent.location,
        description: deviceEvent.description,
        start: deviceEvent.start,
        end: deviceEvent.end,
        reminders: deviceEvent.reminders,
        attendees: deviceEvent.attendees,
        recurrenceRule: deviceEvent.recurrenceRule,
        availability: deviceEvent.availability,
        allDay: deviceEvent.allDay,
        status: deviceEvent.status,
        url: deviceEvent.url,
      );
      deviceEvent.title = draft.title;
      deviceEvent.location = draft.venue;
      deviceEvent.start = tz.TZDateTime.from(draft.startsAt, tz.UTC);
      deviceEvent.end = tz.TZDateTime.from(draft.endsAt, tz.UTC);
      deviceEvent.reminders = draft.reminderMinutes == -1
          ? []
          : [calendar.Reminder(minutes: draft.reminderMinutes)];
      final result = await calendarPlugin.createOrUpdateEvent(deviceEvent);
      if (result?.isSuccess != true) {
        throw CueApiException('캘린더 일정을 수정하지 못했어요.');
      }
      try {
        await api.patch('/v1/events/$id', {
          'title': draft.title,
          'venue': draft.venue,
          'startsAt': draft.startsAt.toUtc().toIso8601String(),
          'endsAt': draft.endsAt.toUtc().toIso8601String(),
          'category': draft.category,
          'format': savedEvent['format'] ?? '기타',
          'domains': savedEvent['domains'] ?? [],
          'description': savedEvent['description'] ?? '',
          'tags': savedEvent['tags'] ?? [],
          'applicationDeadline': savedEvent['applicationDeadline'],
          'participationFee': savedEvent['participationFee'],
          'locationAddress': savedEvent['locationAddress'],
          'sourceUrl': savedEvent['sourceUrl'],
          'calendarId': deviceEvent.calendarId,
          'calendarEventId': result?.data ?? deviceEvent.eventId,
          'reminderMinutes': draft.reminderMinutes,
        });
      } catch (_) {
        final restored = await calendarPlugin.createOrUpdateEvent(previous);
        throw CueApiException(
          restored?.isSuccess == true
              ? '서버에 반영하지 못해 캘린더 변경을 되돌렸어요. 다시 시도해 주세요.'
              : '서버 반영과 변경 되돌리기에 모두 실패했어요. 캘린더 일정을 직접 확인해 주세요.',
        );
      }
      await _refresh();
      _message('캘린더 일정과 알림을 수정했어요.');
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => busyEventId = null);
    }
  }

  // 목록 보기는 다가오는 일정을 가까운 순서로, 지난 일정은 그 뒤에 최근 순서로 둔다.
  List<Map<String, dynamic>> _byDate(List<Map<String, dynamic>> events) {
    final now = DateTime.now();
    DateTime start(Map<String, dynamic> event) =>
        DateTime.tryParse(event['startsAt'] as String? ?? '') ?? DateTime(1970);
    DateTime end(Map<String, dynamic> event) =>
        DateTime.tryParse(event['endsAt'] as String? ?? '') ?? DateTime(1970);
    final upcoming = events.where((event) => end(event).isAfter(now)).toList()
      ..sort((a, b) => start(a).compareTo(start(b)));
    final past = events.where((event) => !end(event).isAfter(now)).toList()
      ..sort((a, b) => start(b).compareTo(start(a)));
    return [...upcoming, ...past];
  }

  // 겹치는 일정 중 하나를 고르면 나머지를 한 번에 확인받고 취소한다.
  Future<void> _keepOnly(Map<String, dynamic> keep, List<Map<String, dynamic>> drop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${keep['title']}만 남길까요?'),
        content: Text([
          '아래 일정은 기기 캘린더의 일정·알림과 함께 취소돼요.',
          for (final event in drop) '• ${event['title']}',
        ].join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('돌아가기')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('나머지 취소')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    for (final event in drop) {
      if (!await _deleteSaved(event, quiet: true)) return;
    }
    await _refresh();
    _message('${keep['title']}만 남겼어요.');
  }

  Future<void> _cancelSaved(Map<String, dynamic> savedEvent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('일정을 취소할까요?'),
        content: Text('기기 캘린더의 일정과 알림이 삭제되고 Cue의 추천 기록에서도 빠져요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('돌아가기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('일정 취소'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _deleteSaved(savedEvent);
  }

  // 기기 캘린더와 Cue 기록에서 일정을 지운다. quiet면 성공 안내와 새로고침을 호출한 쪽에 맡긴다.
  Future<bool> _deleteSaved(Map<String, dynamic> savedEvent, {bool quiet = false}) async {
    final id = savedEvent['id'] as String;
    setState(() => busyEventId = id);
    try {
      final deviceEvent = await _resolveSavedEvent(savedEvent);
      final result = await calendarPlugin.deleteEvent(
        deviceEvent.calendarId,
        deviceEvent.eventId,
      );
      if (result.isSuccess != true || result.data != true) {
        throw CueApiException('캘린더에서 일정을 삭제하지 못했어요.');
      }
      var synced = true;
      try {
        await api.delete('/v1/events/$id');
      } catch (_) {
        synced = false;
        final prefs = await SharedPreferences.getInstance();
        final pending = prefs.getStringList('pending_event_deletions') ?? [];
        if (!pending.contains(id)) {
          await prefs.setStringList('pending_event_deletions', [
            ...pending,
            id,
          ]);
        }
        _message('캘린더 일정과 알림을 삭제했어요. Cue 기록은 연결되면 정리할게요.');
      }
      if (!quiet) {
        await _refresh();
        if (synced) _message('일정을 취소했어요.');
      }
      return true;
    } catch (error) {
      _error(error);
      return false;
    } finally {
      if (mounted) setState(() => busyEventId = null);
    }
  }

  void _message(String text) {
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        margin: EdgeInsets.fromLTRB(16, 0, 16, 14),
        content: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: mint, shape: BoxShape.circle),
            child: Icon(Icons.check_rounded, size: 19, color: accent),
          ),
          SizedBox(width: 11),
          Expanded(child: Text(text)),
        ]),
      ));
    }
  }

  // 오류 원문 대신 사용자가 이해할 문장을 보여준다. CueApiException은 이미 사용자용 문장이다.
  String _friendly(Object error, {String? fallback}) {
    if (error is CueApiException) return error.message;
    final text = error.toString();
    if (error is SocketException || error is TimeoutException ||
        RegExp('SocketException|ClientException|Failed host lookup|AuthRetryableFetchException').hasMatch(text)) {
      return '서버에 연결할 수 없어요. 인터넷 연결을 확인하고 잠시 후 다시 시도해 주세요.';
    }
    return fallback ?? '문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
  }

  void _error(Object error, {String? fallback}) {
    if (!mounted) return;
    final text = _friendly(error, fallback: fallback);
    final detail = error.toString();
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 14),
      content: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(color: Color(0xFFFFEDEC), shape: BoxShape.circle),
          child: Icon(Icons.error_outline_rounded, size: 19, color: Color(0xFFD94A45)),
        ),
        SizedBox(width: 11),
        Expanded(child: Text(text)),
      ]),
      action: detail == text
          ? null
          : SnackBarAction(label: '자세히', onPressed: () => _showDetail(detail)),
    ));
  }

  void _showDetail(String detail) => showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('오류 내용'),
      content: SingleChildScrollView(child: SelectableText(detail, style: TextStyle(fontSize: 13))),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: detail));
            Navigator.pop(dialogContext);
            _message('오류 내용을 복사했어요.');
          },
          child: Text('복사'),
        ),
        FilledButton(onPressed: () => Navigator.pop(dialogContext), child: Text('닫기')),
      ],
    ),
  );

  void _reset() {
    analysisRun += 1;
    progressTimer?.cancel();
    setState(() {
      deadlineController.clear();
      feeController.clear();
      showUnknownInputs = false;
      fromRecommendation = false;
      image = null;
      document = null;
      candidate = null;
      stage = ScanStage.idle;
      reviewStep = 0;
      selectedSession = null;
      startsAt = null;
      endsAt = null;
      selectedCategory = '기타';
      reminderMinutes = defaultReminderMinutes;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return CueSplash();
    if (!onboardingCompleted) {
      return Scaffold(
        body: SafeArea(
          child: Column(children: [
            if (apiError != null) _notice(apiError!, onTap: _refresh, detail: apiErrorDetail),
            Expanded(child: _scroll(_onboarding())),
            // 주 버튼은 스크롤과 상관없이 화면 아래에 고정한다.
            Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: _button('시작하기', Icons.arrow_forward, _finishOnboarding),
            ),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (apiError != null) _notice(apiError!, onTap: _refresh, detail: apiErrorDetail),
            Expanded(child: AnimatedSwitcher(
              duration: Duration(milliseconds: 320),
              reverseDuration: Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(0.08 * tabDirection, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(tab),
                child: switch (tab) {
                  1 => _scroll(_saved(), onRefresh: _refresh),
                  2 => _scroll(_discover(), onRefresh: () => _refresh(shuffle: true)),
                  3 => KeyedSubtree(key: ValueKey(settingsSection), child: _scroll(_settings())),
                  _ => _scroll(_home()),
                },
              ),
            )),
          ],
        ),
      ),
      // 떠 있는 상자 대신 화면 아래에 붙은 탭 바. 위쪽 구분선 하나로만 나눈다.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: borderColor, width: 0.5))),
        child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: _selectTab,
            destinations: [
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt_rounded),
            label: '스캔',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '내 일정',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: '추천',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: '설정',
          ),
            ],
          ),
      ),
    );
  }

  Widget _scroll(Widget child, {Future<void> Function()? onRefresh}) {
    final view = SingleChildScrollView(
      physics: onRefresh == null ? null : AlwaysScrollableScrollPhysics(),
      child: Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 32), child: child),
    );
    return onRefresh == null
        ? view
        : RefreshIndicator(color: accent, onRefresh: onRefresh, child: view);
  }
  // 시작은 서버 연결 없이 바로 한다. 온보딩에서 고른 추천 설정은 서버에 연결될 때 반영한다.
  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cue_onboarding_completed', true);
    await prefs.setBool('cue_onboarding_recommendations', personalizationEnabled && recommendationEnabled);
    await prefs.setBool('cue_onboarding_synced', false);
    if (!mounted) return;
    setState(() => onboardingCompleted = true);
    unawaited(_refresh());
  }

  Future<void> _syncOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    // 키가 없으면 예전 버전에서 이미 서버에 저장한 사용자다.
    if (prefs.getBool('cue_onboarding_synced') != false) return;
    final enabled = prefs.getBool('cue_onboarding_recommendations') ?? true;
    await api.patch('/v1/profile', {
      'onboardingCompleted': true,
      'personalizationEnabled': enabled,
      'recommendationEnabled': enabled,
    });
    await prefs.setBool('cue_onboarding_synced', true);
    onboardingPreferencesDirty = false;
  }

  Widget _onboardingStep(String emoji, String title, String detail) => Padding(
    padding: EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: surface, shape: BoxShape.circle),
          child: Text(emoji, style: TextStyle(fontSize: 24)),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: CueType.headline.copyWith(color: ink)),
              SizedBox(height: 2),
              Text(detail, style: CueType.caption.copyWith(color: muted, fontSize: 14)),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _onboarding() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: 28),
      Text('행사 포스터를\n일정으로 바꿔 드릴게요', style: CueType.largeTitle.copyWith(color: ink)),
      SizedBox(height: 8),
      Text('Cue 시작하기', style: CueType.body.copyWith(color: muted, fontSize: 15)),
      SizedBox(height: 32),
      _onboardingStep('📸', '포스터나 공지문을 찍어요', '사진첩, PDF·한글 파일도 읽을 수 있어요'),
      _onboardingStep('👀', '읽어낸 내용을 확인해요', '날짜·시간·장소는 저장 전에 고칠 수 있어요'),
      _onboardingStep('🗓️', '캘린더에 저장해요', '저장을 누른 일정만 캘린더에 추가돼요'),
      SizedBox(height: 28),
      _group([
        _row('관심사 기반 행사 추천',
            subtitle: '저장한 일정으로 맞는 행사를 찾아드려요',
            trailing: Switch.adaptive(
              value: personalizationEnabled && recommendationEnabled,
              onChanged: (value) => setState(() {
                onboardingPreferencesDirty = true;
                personalizationEnabled = value;
                recommendationEnabled = value;
              }),
            )),
      ], footer: '로그인 없이 바로 시작해요. 사진과 문서는 행사 정보를 읽기 위해 서버를 거쳐 OpenAI로 전송돼요. '
          '앱을 지우면 Cue 기록은 되찾을 수 없지만 캘린더에 저장한 일정은 남아요.'),
    ],
  );

  Widget _home() {
    final idle = stage == ScanStage.idle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (idle) ..._homeGreeting()
        else if (stage != ScanStage.review && stage != ScanStage.saved) _pageTitle('스캔'),
        SizedBox(height: idle ? 24 : 16),
        if (idle) _captureCard(),
        if (stage == ScanStage.processing) _progressCard(),
        if (stage == ScanStage.notEvent) _notEventCard(),
        if (stage == ScanStage.pastEvent) _pastEventCard(),
        if (stage == ScanStage.review) _reviewCard(),
        if (stage == ScanStage.saved) _savedCard(),
        SizedBox(height: 22),
      ],
    );
  }

  // 첫 화면은 오늘 날짜와 다음 일정으로 시작한다. 사용자와 관련된 정보가 먼저 보여야 한다.
  List<Widget> _homeGreeting() {
    final now = DateTime.now();
    final next = nextCue(buildRoute(saved), now);
    return [
      Text(dayLabel(now), style: CueType.body.copyWith(color: muted, fontSize: 15)),
      SizedBox(height: 6),
      Text('포스터 한 장이면\n일정이 돼요', style: CueType.largeTitle.copyWith(color: ink)),
      if (next != null) ...[
        SizedBox(height: 20),
        Material(
          color: surface,
          borderRadius: BorderRadius.circular(CueRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _selectTab(1),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(children: [
                Text('🗓️', style: TextStyle(fontSize: 22)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(next.inProgress ? '지금 진행 중' : '다음 일정 · ${countdown(next.stop.start, now)}',
                        style: CueType.label.copyWith(color: accent)),
                    SizedBox(height: 2),
                    Text(next.stop.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: CueType.headline.copyWith(color: ink)),
                  ]),
                ),
                Icon(Icons.chevron_right, size: 20, color: muted),
              ]),
            ),
          ),
        ),
      ],
    ];
  }

  // 촬영 타일 하나만 강조하고, 사진첩과 문서는 아래 목록으로 둔다.
  Widget _captureCard() {
    final picked = image != null || document != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: surface,
          borderRadius: BorderRadius.circular(CueRadius.card),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: picked ? null : () => _pick(ImageSource.camera),
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (image != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(CueRadius.control),
                      child: Image.file(image!, height: 200, width: double.infinity, fit: BoxFit.cover),
                    )
                  else if (document != null)
                    Row(children: [
                      Text('📄', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(document!.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: CueType.headline.copyWith(color: ink)),
                      ),
                    ])
                  else
                    SizedBox(
                      height: 160,
                      width: double.infinity,
                      child: CustomPaint(painter: _PosterArt(
                        front: isDark ? Color(0xFF3A3A43) : Colors.white,
                        back: isDark ? Color(0xFF2D2D35) : Color(0xFFE3E7EB),
                        line: isDark ? Color(0xFF55555F) : Color(0xFFDDE1E5),
                        accent: accent,
                        shadow: !isDark,
                      )),
                    ),
                  SizedBox(height: 20),
                  Text(picked ? '다시 읽어 볼까요?' : '포스터 찍기', style: CueType.title.copyWith(color: ink)),
                  SizedBox(height: 4),
                  Text('찍으면 날짜·시간·장소를 읽어 드려요',
                      style: CueType.caption.copyWith(color: muted, fontSize: 14)),
                  SizedBox(height: 18),
                  picked
                      ? _button(image != null ? '이 사진 다시 분석' : '이 문서 다시 분석', Icons.refresh, _analyze)
                      : _button('포스터 촬영하기', Icons.camera_alt_outlined, () => _pick(ImageSource.camera)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(height: 12),
        _group([
          _row('앨범에서 고르기', leading: '🖼️', onTap: () => _pick(ImageSource.gallery)),
          _row('PDF·한글 공지문 열기', leading: '📄', onTap: _pickDocument),
        ], footer: '읽어낸 내용을 확인한 뒤에만 캘린더에 저장돼요.'),
      ],
    );
  }

  Widget _progressCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(CueRadius.control),
            child: Image.file(
              image!,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        if (document != null)
          Row(
            children: [
              Icon(Icons.description_outlined, color: accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  document!.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        SizedBox(height: 23),
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3, color: accent),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                statusMessage ?? '분석하는 중',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        Text('서버가 쉬고 있었다면 처음에는 30초 넘게 걸릴 수 있어요.',
            style: TextStyle(color: muted, fontSize: 13)),
        SizedBox(height: 6),
        TextButton.icon(
          onPressed: _reset,
          icon: Icon(Icons.close),
          label: Text('분석 취소'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ],
    ),
  );

  Widget _notEventCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, color: accent, size: 35),
        SizedBox(height: 15),
        Text(
          '행사 안내물을 찾지 못했어요',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '행사 정보가 확인되지 않아 분석을 중단했어요. 다른 포스터나 공지문을 선택해 주세요.',
          style: TextStyle(color: muted, height: 1.5),
        ),
        SizedBox(height: 20),
        _button('다른 안내물 선택', Icons.refresh, () {
          _reset();
        }),
      ],
    ),
  );

  Widget _pastEventCard() {
    final ended = DateTime.tryParse(pastEventEndedAt ?? '')?.toLocal();
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.event_busy_outlined, color: accent, size: 35),
          SizedBox(height: 15),
          Text(
            '이미 지난 행사예요',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: ink),
          ),
          SizedBox(height: 8),
          Text(
            [
              if ((pastEventTitle ?? '').isNotEmpty) pastEventTitle!,
              if (ended != null) '${_date(ended)}에 끝난 행사라 일정 저장을 취소했어요.'
              else '일정이 이미 지나 저장을 취소했어요.',
            ].join('\n'),
            style: TextStyle(color: muted, height: 1.5),
          ),
          SizedBox(height: 20),
          _button('다른 안내물 선택', Icons.refresh, _reset),
        ],
      ),
    );
  }

  Widget _reviewCard() {
    final event = candidate!;
    const labels = ['행사 이름', '행사 종류', '시간과 장소', '알림'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 네 칸짜리 진행 막대. 지난 단계와 현재 단계만 강조색으로 채운다.
        Row(children: [
          for (var i = 0; i < 4; i += 1) ...[
            if (i > 0) SizedBox(width: 4),
            Expanded(child: AnimatedContainer(
              duration: Duration(milliseconds: 240),
              height: 4,
              decoration: BoxDecoration(
                color: i <= reviewStep ? accent : surface,
                borderRadius: BorderRadius.circular(2),
              ),
            )),
          ],
        ]),
        SizedBox(height: 20),
        Text('${reviewStep + 1}/4', style: CueType.label.copyWith(color: muted)),
        SizedBox(height: 4),
        Text(labels[reviewStep], style: CueType.largeTitle.copyWith(color: ink)),
        SizedBox(height: 4),
        Text(fromRecommendation ? '일정에 담기 전에 내용을 확인해 주세요.' : '포스터에서 읽은 내용이에요. 맞는지 확인해 주세요.',
            style: CueType.body.copyWith(color: muted, fontSize: 15)),
        SizedBox(height: 24),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 280),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: Offset(0.06 * reviewDirection, 0), end: Offset.zero).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(reviewStep),
            child: switch (reviewStep) {
              1 => _reviewCategoryPage(),
              2 => _reviewSchedulePage(event),
              3 => _reviewReminderPage(),
              _ => _reviewTitlePage(event),
            },
          ),
        ),
        SizedBox(height: 18),
        Row(children: [
          if (reviewStep > 0) ...[
            Expanded(child: FilledButton(
              onPressed: () => _setReviewStep(reviewStep - 1),
              style: FilledButton.styleFrom(
                backgroundColor: surface,
                foregroundColor: ink,
                minimumSize: Size.fromHeight(52),
              ),
              child: Text('이전'),
            )),
            SizedBox(width: 10),
          ],
          Expanded(
            flex: reviewStep > 0 ? 2 : 1,
            child: FilledButton(
              onPressed: saving ? null : reviewStep == 3 ? _save : _nextReviewStep,
              style: FilledButton.styleFrom(minimumSize: Size.fromHeight(52)),
              child: Text(reviewStep == 3
                  ? (saving ? '저장하는 중...' : '캘린더에 저장')
                  : '다음'),
            ),
          ),
        ]),
        SizedBox(height: 8),
        Center(child: TextButton(
          onPressed: () {
            final back = fromRecommendation;
            _reset();
            if (back) _selectTab(2);
          },
          child: Text(fromRecommendation ? '추천으로 돌아가기' : '분석 취소'),
        )),
      ],
    );
  }

  Widget _reviewTitlePage(CueEvent event) => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: titleController,
        maxLength: 120,
        autofocus: false,
        style: CueType.headline.copyWith(color: ink),
        decoration: InputDecoration(labelText: '행사 이름', hintText: '포스터에 적힌 행사 이름', counterText: ''),
      ),
      if (event.description.isNotEmpty) ...[
        SizedBox(height: 8),
        Text(event.description, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, height: 1.5)),
      ],
    ],
  ));

  // 칩은 회색 바탕이라 카드 없이 화면 바탕에 바로 놓는다.
  Widget _reviewCategoryPage() => Padding(padding: EdgeInsets.zero, child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('가장 가까운 종류를 골라 주세요', style: CueType.headline.copyWith(color: ink)),
      SizedBox(height: 2),
      Text('고른 종류는 추천에 반영돼요.', style: CueType.caption.copyWith(color: muted)),
      SizedBox(height: 18),
      for (final group in cueCategoryGroups.entries) ...[
        _eyebrow(group.key),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final value in group.value) ChoiceChip(
            label: Text(value),
            selected: selectedCategory == value,
            onSelected: (_) => setState(() => selectedCategory = value),
          )],
        ),
        SizedBox(height: 15),
      ],
    ],
  ));

  Widget _reviewSchedulePage(CueEvent event) => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (event.sessions.length > 1) ...[
        Text('참석할 일정 하나를 선택하세요',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ink)),
        SizedBox(height: 12),
        for (var i = 0; i < event.sessions.length; i++) _sessionChoice(i, event.sessions[i]),
        SizedBox(height: 8),
      ],
      TextField(
        controller: venueController,
        decoration: InputDecoration(labelText: '장소', prefixIcon: Icon(Icons.place_outlined)),
      ),
      SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => _editSchedule(ambiguous: event.sessions.isEmpty && startsAt == null),
        icon: Icon(Icons.schedule_rounded),
        label: Text(startsAt == null ? '날짜와 시간 선택' : _date(startsAt!)),
        style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(54), foregroundColor: accent),
      ),
      if (startsAt != null) ...[
        SizedBox(height: 8),
        Text('종료 ${_date(endsAt!)}', style: TextStyle(color: muted, fontSize: 13)),
      ],
    ],
  ));

  Widget _reviewReminderPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _group([
        for (final option in [15, 60, 1440, -1])
          _row(_reminderLabel(option),
              trailing: reminderMinutes == option ? Icon(Icons.check, size: 20, color: accent) : SizedBox(width: 20),
              onTap: () => setState(() => reminderMinutes = option)),
      ], label: '언제 알려드릴까요?'),
      _group([
        _row('신청 마감일·참가비',
            value: [
              if (deadlineController.text.trim().isNotEmpty) deadlineController.text.trim(),
              if (feeController.text.trim().isNotEmpty) feeController.text.trim(),
            ].join(' · ').ifEmpty('선택 사항'),
            trailing: Icon(showUnknownInputs ? Icons.expand_less : Icons.expand_more, size: 20, color: muted),
            onTap: () => setState(() => showUnknownInputs = !showUnknownInputs)),
        if (showUnknownInputs)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(children: [
              TextField(controller: deadlineController, onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: '신청 마감일 (YYYY-MM-DD)'), keyboardType: TextInputType.datetime),
              SizedBox(height: 9),
              TextField(controller: feeController, onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: '참가비')),
            ]),
          ),
      ], label: '추가 정보'),
    ],
  );

  void _setReviewStep(int value) => setState(() {
    reviewDirection = value > reviewStep ? 1 : -1;
    reviewStep = value.clamp(0, 3);
  });

  void _nextReviewStep() {
    if (reviewStep == 0 && titleController.text.trim().isEmpty) {
      _message('행사 이름을 확인해 주세요.');
      return;
    }
    if (reviewStep == 2) {
      if (candidate!.sessions.length > 1 && selectedSession == null) {
        _message('참석할 시간과 장소를 선택해 주세요.');
        return;
      }
      if (venueController.text.trim().isEmpty || startsAt == null || endsAt == null) {
        _message('장소와 시간을 확인해 주세요.');
        return;
      }
    }
    _setReviewStep(reviewStep + 1);
  }

  Future<void> _chooseSession() async {
    final event = candidate;
    if (event == null || event.sessions.length < 2 || !mounted) return;
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) => PopScope(
        canPop: false,
        child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(22, 2, 22, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '참석할 일정을 선택해 주세요',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      '이 행사는 시간과 장소가 ${event.sessions.length}가지예요. 캘린더에 저장할 하나를 골라 주세요.',
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: [
                    for (var i = 0; i < event.sessions.length; i++)
                      _sessionChoice(
                        i,
                        event.sessions[i],
                        onTap: () => Navigator.pop(sheetContext, i),
                      ),
                    TextButton.icon(
                      onPressed: () => Navigator.pop(sheetContext, -1),
                      icon: Icon(Icons.edit_calendar_outlined),
                      label: Text('여기에 없는 일정이에요 · 직접 입력'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, -2),
                      child: Text('취소하고 다른 안내물 선택'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
    if (picked == -2) {
      if (mounted) _reset();
    } else if (picked == -1) {
      // 직접 입력을 마치지 않고 나오면 다시 선택창으로 돌아온다.
      if (!await _editSchedule(forced: true) && mounted) await _chooseSession();
    } else if (picked != null && mounted) {
      setState(() {
        selectedSession = picked;
        _applySession(picked);
      });
    }
  }

  Widget _sessionChoice(int index, CueSession session, {VoidCallback? onTap}) => Padding(
    padding: EdgeInsets.only(bottom: 9),
    child: InkWell(
      onTap: onTap ?? () => setState(() {
        selectedSession = index;
        _applySession(index);
      }),
      borderRadius: BorderRadius.circular(CueRadius.control),
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selectedSession == index ? mint : paper,
          border: Border.all(
            color: selectedSession == index ? accent : borderColor,
            width: selectedSession == index ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(CueRadius.control),
        ),
        child: Row(
          children: [
            Icon(
              selectedSession == index
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: accent,
            ),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.label.isEmpty
                        ? _date(session.startsAt)
                        : session.label,
                    style: TextStyle(fontWeight: FontWeight.w600, color: ink),
                  ),
                  Text(
                    '${_date(session.startsAt)} · ${session.venue}',
                    style: TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // 방금 저장한 일정이 있는 날의 노선. 서버 목록에 아직 없으면 방금 저장한 일정을 더해 계산한다.
  RouteDay? _savedDay() {
    final start = startsAt;
    final end = endsAt;
    if (start == null || end == null) return null;
    final title = titleController.text.trim();
    final listed = saved.any((event) =>
        event['title'] == title &&
        (DateTime.tryParse(event['startsAt'] as String? ?? '')?.isAtSameMomentAs(start) ?? false));
    final events = [
      ...saved,
      if (!listed)
        {
          'id': 'just-saved',
          'title': title,
          'venue': venueController.text.trim(),
          'category': selectedCategory,
          'startsAt': start.toUtc().toIso8601String(),
          'endsAt': end.toUtc().toIso8601String(),
        },
    ];
    final date = DateTime(start.year, start.month, start.day);
    return buildRoute(events).where((day) => day.date == date).firstOrNull;
  }

  Widget _savedCard() {
    final day = _savedDay();
    final (note, warn) = day == null
        ? ('', false)
        : day.hasFork
        ? ('시간이 겹치는 일정이 있어요. 동선에서 하나를 골라 주세요.', true)
        : day.hasTight
        ? ('앞뒤 일정과 간격이 짧아요. 이동 시간을 확인해 주세요.', true)
        : day.stops.length > 1
        ? ('이날 다른 일정과 겹치지 않아요.', false)
        : ('이날 일정은 이것 하나예요.', false);
    final backToRecommendations = fromRecommendation;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: accent, size: 46),
          SizedBox(height: 15),
          Text(
            '저장 완료',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          SizedBox(height: 6),
          Text('캘린더에 일정과 알림이 추가됐어요.', style: TextStyle(color: muted)),
          if (day != null) ...[
            SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: warn ? (isDark ? Color(0xFF3A2A17) : Color(0xFFFFF1E2)) : mint,
                borderRadius: BorderRadius.circular(CueRadius.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${dayLabel(day.date)} · 일정 ${day.stops.length}곳',
                      style: TextStyle(color: ink, fontWeight: FontWeight.w600)),
                  SizedBox(height: 4),
                  Text(note, style: TextStyle(
                    color: warn ? (isDark ? Color(0xFFFFB86B) : Color(0xFFC96A12)) : muted,
                    fontSize: 13,
                  )),
                ],
              ),
            ),
          ],
          SizedBox(height: 20),
          if (day != null) ...[
            _button('이날 동선 보기', Icons.route_outlined, () {
              _reset();
              setState(() {
                tabDirection = 1;
                tab = 1;
                routeView = true;
                routeFocusDate = day.date;
                routeFocusRequest += 1;
              });
            }),
            SizedBox(height: 8),
          ],
          Center(
            child: TextButton(
              onPressed: () {
                _reset();
                if (backToRecommendations) _selectTab(2);
              },
              child: Text(backToRecommendations ? '추천 더 보기' : '다른 행사 스캔하기'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _saved() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _pageTitle('내 일정'),
          ),
          // 동선과 목록 보기를 아이콘 하나로 오간다. 아이콘은 바꿀 보기를 가리킨다.
          IconButton(
            tooltip: routeView ? '목록으로 보기' : '동선으로 보기',
            onPressed: () => setState(() => routeView = !routeView),
            icon: Icon(routeView ? Icons.view_agenda_outlined : Icons.route_outlined, color: ink),
          ),
        ],
      ),
      SizedBox(height: 16),
      if (saved.isEmpty)
        _empty(Icons.event_note_outlined, '아직 저장한 행사가 없어요', '포스터나 공지문을 선택해 보세요.')
      else if (routeView)
        RouteView(
          events: saved,
          busyEventId: busyEventId,
          onEdit: _editSaved,
          onCancel: _cancelSaved,
          onKeep: _keepOnly,
          focusDate: routeFocusDate,
          focusRequest: routeFocusRequest,
        )
      else
        for (final event in _byDate(saved)) ...[
          _eventTile(event),
          SizedBox(height: 11),
        ],
      // 공유는 실험 기능이라 일정 아래 묶음 목록으로 둔다.
      if (saved.isNotEmpty) ...[
        SizedBox(height: 12),
        _group([
          _row('행사 공유 관리', leading: '🤝', onTap: sharingEvent ? null : _manageShares),
        ], label: '실험', footer: '저장한 행사를 다른 사용자에게 공개할 수 있어요.'),
      ],
    ],
  );

  Widget _discover() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: _pageTitle('추천')),
          IconButton(
            tooltip: '다른 행사 보기',
            onPressed: recommendationLoading ? null : () => _refresh(shuffle: true),
            icon: Icon(Icons.refresh, color: ink),
          ),
        ],
      ),
      SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final source in (const {'all': '전체', 'web': '웹에서 찾은 행사', 'shared': '사용자 공유'}).entries)
            ChoiceChip(
              label: Text(source.value),
              selected: recommendationSource == source.key,
              onSelected: (_) => setState(() => recommendationSource = source.key),
            ),
        ],
      ),
      TextButton(
        onPressed: _editCommunity,
        style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        child: Text('학교·활동 지역으로 추천받기'),
      ),
      SizedBox(height: 8),
      if (recommendationLoading && recommended.isEmpty)
        _empty(Icons.search, '관련 행사 확인 중', '행사 정보를 확인하고 있어요.'),
      if (!recommendationLoading && recommended.isEmpty)
        _empty(
          Icons.explore_outlined,
          '아직 추천할 행사가 없어요',
          '행사 포스터를 저장하면 관심 분야에 맞는 행사를 찾아드려요. 아래로 당겨서 새로고침할 수도 있어요.',
        ),
      for (final event in recommended) ...[
        if (recommendationSource == 'all' || event['originKind'] == recommendationSource) ...[
          _eventTile(event, recommended: true),
          SizedBox(height: 11),
        ],
      ],
      if (recommended.isNotEmpty && recommendationSource != 'all' &&
          !recommended.any((event) => event['originKind'] == recommendationSource))
        _empty(Icons.event_note_outlined, '이 출처의 추천이 아직 없어요', '다른 출처를 선택하거나 나중에 다시 확인해 주세요.'),
    ],
  );

  Widget _settings() {
    final section = settingsSection;
    if (section != null) {
      return PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() => settingsSection = null);
        },
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: () => setState(() => settingsSection = null),
            icon: Icon(Icons.chevron_left, size: 22),
            label: Text('설정으로'),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          ),
          SizedBox(height: 4),
          _pageTitle(section),
          SizedBox(height: 20),
          ..._settingsContent(section),
        ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitle('설정'),
        SizedBox(height: 20),
        _group([
          _settingsEntry('🗓️', '캘린더와 알림', _reminderLabel(defaultReminderMinutes)),
          _settingsEntry('🌗', '화면 테마', switch (cueThemeMode.value) {
            ThemeMode.system => '시스템',
            ThemeMode.light => '라이트',
            ThemeMode.dark => '다크',
          }),
          _settingsEntry('💡', '추천', personalizationEnabled && recommendationEnabled ? '켜짐' : '꺼짐'),
          _settingsEntry('🔒', '내 데이터', ''),
        ]),
      ],
    );
  }

  Widget _settingsEntry(String emoji, String title, String summary) => _row(
    title,
    leading: emoji,
    value: summary.isEmpty ? null : summary,
    onTap: () => setState(() => settingsSection = title),
  );

  List<Widget> _settingsContent(String section) => switch (section) {
    '캘린더와 알림' => [
      _group([
        _row('저장할 캘린더', value: preferredCalendarName, onTap: _chooseCalendar),
        _row('기본 알림', trailing: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: defaultReminderMinutes,
              style: CueType.body.copyWith(color: muted),
              items: [15, 60, 1440, -1]
                  .map((value) => DropdownMenuItem(value: value, child: Text(_reminderLabel(value))))
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                setState(() {
                  defaultReminderMinutes = value;
                  reminderMinutes = value;
                });
                await (await SharedPreferences.getInstance()).setInt('default_reminder_minutes', value);
              },
            ),
          )),
        _row('기본 일정 길이', subtitle: '종료 시간이 없는 행사에 적용돼요',
            trailing: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: defaultDurationMinutes,
              style: CueType.body.copyWith(color: muted),
              items: [60, 120, 180]
                  .map((value) => DropdownMenuItem(value: value, child: Text('${{value ~/ 60}}시간')))
                  .toList(),
              onChanged: (value) async {
                if (value == null) return;
                setState(() {
                  defaultDurationMinutes = value;
                });
                await (await SharedPreferences.getInstance()).setInt('default_duration_minutes', value);
              },
            ),
          )),
      ], footer: '새 일정을 저장할 때 먼저 적용되는 값이에요.'),
    ],
    '화면 테마' => [
      _group([
        for (final (mode, label) in [(ThemeMode.system, '시스템'), (ThemeMode.light, '라이트'), (ThemeMode.dark, '다크')])
          _row(label,
              trailing: cueThemeMode.value == mode ? Icon(Icons.check, size: 20, color: accent) : SizedBox(width: 20),
              onTap: () async {
                cueThemeMode.value = mode;
                setState(() {});
                await (await SharedPreferences.getInstance()).setString('theme_mode', mode.name);
              }),
      ], footer: '시스템을 고르면 기기의 라이트·다크 설정을 따라가요.'),
    ],
    '추천' => [
      _group([
        _row('관심사 기반 추천',
            trailing: Switch.adaptive(
              value: personalizationEnabled,
              onChanged: (value) => _updateProfile({'personalizationEnabled': value}),
            )),
        _row('행사 추천 표시',
            trailing: Switch.adaptive(
              value: recommendationEnabled,
              onChanged: personalizationEnabled
                  ? (value) => _updateProfile({'recommendationEnabled': value})
                  : null,
            )),
      ], footer: '끄면 추천을 위한 선택 기록을 사용하지 않아요.'),
      _group([
        _row('학교·활동 지역·연령대',
            value: [communitySchool, communityRegion, _ageBandLabel(communityAgeBand)]
                .where((value) => value.isNotEmpty).join(' · ').ifEmpty('선택 안 함'),
            onTap: _editCommunity),
      ], label: '내 추천 환경 (실험)', footer: '비슷한 환경의 사용자가 공유한 행사를 먼저 보여드려요.'),
      _group([
        _row('내 관심사 기록 초기화', color: Color(0xFFE5484D), onTap: _resetInterests),
      ], footer: '관심 표시와 추천 기록, Cue가 파악한 관심사를 모두 지워요. 저장한 일정은 그대로 남아요.'),
    ],
    '내 데이터' => [
      _group([
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '사진과 문서는 행사 정보를 읽기 위해 서버를 거쳐 OpenAI로 전송돼요. 행사 안내물이 아니면 더 분석하지 않아요.',
            style: CueType.body.copyWith(color: ink, fontSize: 15),
          ),
        ),
      ], label: '사진과 문서'),
      _group([
        _row(userId == null ? '서버에 연결되지 않음' : '익명 계정에 기록 중',
            subtitle: '앱을 지우거나 기기를 바꾸면 Cue 기록은 되찾을 수 없어요. 기기 캘린더의 일정은 그대로 남아요.'),
        _row('연결 다시 확인', color: accent, onTap: _refresh),
        _row('개발자 정보',
            trailing: Icon(showDeveloperInfo ? Icons.expand_less : Icons.expand_more, size: 20, color: muted),
            onTap: () => setState(() => showDeveloperInfo = !showDeveloperInfo)),
        if (showDeveloperInfo)
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: SelectableText(
              [
                '서버  $cueApiUrl',
                '클라우드 저장소  ${cloudConnected ? '연결됨' : '연결 안 됨'}',
                if (userId != null) '사용자 ID  $userId',
                if (apiErrorDetail != null) '마지막 오류  $apiErrorDetail',
              ].join('\n'),
              style: CueType.caption.copyWith(color: muted, fontSize: 12),
            ),
          ),
      ], label: '내 기록'),
    ],
    _ => const <Widget>[],
  };

  Future<void> _resetInterests() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('관심사 기록을 초기화할까요?'),
        content: Text(
          '관심 표시, 추천 기록, Cue가 파악한 관심사가 모두 삭제돼요. 저장한 일정은 지워지지 않고, 삭제한 기록은 되돌릴 수 없어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Color(0xFFE5484D)),
            child: Text('초기화'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.delete('/v1/interests');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('interested_events');
      if (!mounted) return;
      setState(() {
        interestedIds = {};
        recommendationSeed = null;
      });
      _message('관심사 기록을 초기화했어요.');
      await _refresh();
    } catch (error) {
      _message('초기화하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Widget _eventTile(Map<String, dynamic> event, {bool recommended = false}) {
    DateTime? date;
    try {
      date = DateTime.parse(event['startsAt'] as String).toLocal();
    } catch (_) {}
    final description = event['description'] as String? ?? '';
    final sourceUrl = event['sourceUrl'] as String?;
    final interested = interestedIds.contains(event['id']);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              event['category'] as String? ?? '기타',
              if (recommended) switch (event['originKind']) {
                'shared' => '사용자 공유',
                'web' => '웹에서 찾음',
                'demo' => '시연용 예시',
                _ => '등록된 행사',
              },
            ].join(' · '),
            style: CueType.label.copyWith(color: muted),
          ),
          SizedBox(height: 6),
          Text(event['title'] as String? ?? '', style: CueType.title.copyWith(color: ink, fontSize: 19)),
          SizedBox(height: 8),
          if (date != null) _detail(Icons.schedule, _date(date)),
          _detail(Icons.place_outlined, event['venue'] as String? ?? ''),
          if (recommended && event['reason'] is String) ...[
            SizedBox(height: 10),
            Text(event['reason'] as String, style: CueType.caption.copyWith(color: muted)),
          ],
          if (recommended && description.isNotEmpty) ...[
            SizedBox(height: 8),
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: muted, fontSize: 13, height: 1.45),
            ),
          ],
          SizedBox(height: 14),
          if (!recommended && busyEventId == event['id'])
            Center(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 9),
                    Text('캘린더와 알림을 확인하는 중'),
                  ],
                ),
              ),
            )
          else if (!recommended)
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () => _editSaved(event),
                  icon: Icon(Icons.edit_outlined),
                  label: Text('수정'),
                ),
                SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _cancelSaved(event),
                  icon: Icon(Icons.event_busy_outlined),
                  label: Text('일정 취소'),
                ),
              ],
            )
          else
            // 주 행동은 '일정에 추가' 하나만 크게 두고, 나머지는 아이콘으로 줄인다.
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _planRecommendation(event),
                    icon: Icon(Icons.add, size: 20),
                    label: Text('일정에 추가'),
                    // 카드마다 있는 버튼이라 옅은 바탕으로 둔다. 진한 강조색은 화면의 주 버튼에만 쓴다.
                    style: FilledButton.styleFrom(
                      backgroundColor: isDark ? Color(0xFF17171C) : Colors.white,
                      foregroundColor: accent,
                      minimumSize: Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(CueRadius.control)),
                      textStyle: TextStyle(fontFamily: 'Pretendard', fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(width: 6),
                IconButton(
                  tooltip: interested ? '관심 표시함' : '관심 있음',
                  onPressed: interested
                      ? () => _message('이미 관심 표시한 행사예요.')
                      : () => _feedback(event, 'interested'),
                  icon: Icon(interested ? Icons.favorite : Icons.favorite_border, color: accent),
                ),
                IconButton(
                  tooltip: '관심 없음',
                  onPressed: () => _dismissRecommendation(event),
                  icon: Icon(Icons.not_interested_outlined, color: muted),
                ),
                if (sourceUrl != null)
                  IconButton(
                    tooltip: '공식 안내',
                    onPressed: () async {
                      final url = Uri.tryParse(sourceUrl);
                      if (url == null || !await launchUrl(url, mode: LaunchMode.externalApplication)) {
                        _message('공식 안내 페이지를 열 수 없어요.');
                      }
                    },
                    icon: Icon(Icons.open_in_new, color: muted),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _ageBandLabel(String value) => switch (value) {
    'under20' => '20세 미만', '20s' => '20대', '30s' => '30대', '40plus' => '40세 이상', _ => '',
  };

  Future<void> _editCommunity() async {
    var school = communitySchool;
    var region = communityRegion;
    var ageBand = communityAgeBand;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text('내 추천 환경'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('모두 선택사항이에요. 같은 학교·지역·연령대에서 공유된 행사를 추천하는 데 사용해요. 학교나 연령은 인증되지 않으며 참가 자격을 보장하지 않아요.'),
          SizedBox(height: 16),
          TextFormField(initialValue: school, maxLength: 80,
            decoration: InputDecoration(labelText: '학교·캠퍼스', hintText: '예: 한국대학교 서울캠퍼스'),
            onChanged: (value) => school = value.trim()),
          TextFormField(initialValue: region, maxLength: 80,
            decoration: InputDecoration(labelText: '활동 지역', hintText: '예: 서울 성북구'),
            onChanged: (value) => region = value.trim()),
          DropdownButtonFormField<String>(
            initialValue: ageBand,
            decoration: InputDecoration(labelText: '연령대'),
            items: ['', 'under20', '20s', '30s', '40plus'].map((value) => DropdownMenuItem(
              value: value, child: Text(value.isEmpty ? '선택 안 함' : _ageBandLabel(value)))).toList(),
            onChanged: (value) => update(() => ageBand = value ?? ''),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, <String, dynamic>{
            'school': school, 'region': region, 'ageBand': ageBand,
          }), child: Text('저장')),
        ],
      )),
    );
    if (result != null && mounted) await _updateProfile(result);
  }

  Future<void> _manageShares() async {
    final event = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(children: [
          Padding(padding: EdgeInsets.all(20), child: Text('내가 발견한 행사 공유',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
          Expanded(child: ListView(children: [
            for (final event in saved)
              ListTile(
                title: Text(event['title'] as String? ?? ''),
                subtitle: Text(event['shared'] == true ? '공유 중 · 선택해서 공유 취소' : '나만 저장 · 선택해서 공개 내용 확인'),
                trailing: Icon(event['shared'] == true ? Icons.public : Icons.share_outlined),
                onTap: () => Navigator.pop(context, event),
              ),
          ])),
        ]),
      )),
    );
    if (event != null && mounted) await _shareEvent(event);
  }

  Future<void> _shareEvent(Map<String, dynamic> event) async {
    if (sharingEvent) return;
    final shared = event['shared'] == true;
    final start = DateTime.tryParse(event['startsAt'] as String? ?? '')?.toLocal();
    final end = DateTime.tryParse(event['endsAt'] as String? ?? '')?.toLocal();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(shared ? '행사 공유를 취소할까요?' : '이 행사 정보를 공개할까요?'),
        content: SingleChildScrollView(child: Text(shared
          ? '공유한 행사와 추천 노출을 중단해요. 다른 사람이 이미 자기 캘린더에 저장한 일정은 남아요.'
          : '${event['title']}\n${event['venue']}\n'
            '${start == null ? '' : _date(start)} ~ ${end == null ? '' : _date(end)}\n\n'
            '${event['description'] ?? ''}\n\n'
            '분야: ${event['category'] ?? ''}\n'
            '태그: ${(event['tags'] as List<dynamic>? ?? []).join(', ')}\n'
            '참가비: ${event['participationFee'] ?? '정보 없음'}\n'
            '신청 마감: ${event['applicationDeadline'] ?? '정보 없음'}\n'
            '출처: ${event['sourceUrl'] ?? '없음'}\n\n'
            '행사명·장소·시간·설명·분야·태그·참가비·마감일과 출처 링크를 다른 사용자에게 공개해요. '
            '사진 원본과 캘린더 연결·알림 정보는 공유하지 않아요. '
            '설정한 학교·활동 지역·연령대도 추천 기준으로 함께 저장돼요. '
            '개인 메모나 비공개 행사 정보가 포함되어 있다면 먼저 수정해 주세요. '
            '공유된 정보는 검증되지 않았으므로 참가 조건은 직접 확인해야 해요.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('닫기')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: Text(shared ? '공유 취소' : '공개하고 공유')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => sharingEvent = true);
    try {
      final route = '/v1/events/${event['id']}/share';
      if (shared) {
        await api.delete(route);
      } else {
        await api.post(route, {'confirmPublic': true});
      }
      _message(shared ? '공유를 취소했어요.' : '행사 정보를 공유했어요.');
      await _refresh();
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => sharingEvent = false);
    }
  }

  Future<void> _updateProfile(Map<String, dynamic> changes) async {
    try {
      await api.patch('/v1/profile', changes);
      await _refresh();
    } catch (error) {
      _error(error);
    }
  }

  Future<void> _feedback(Map<String, dynamic> event, String action) async {
    final id = event['id'] as String?;
    final interested = action == 'interested' && id != null;
    if (interested) setState(() => interestedIds = {...interestedIds, id});
    try {
      await api.post('/v1/interactions', {
        'eventId': event['id'],
        'action': action,
      });
      if (interested) {
        await (await SharedPreferences.getInstance())
            .setStringList('interested_events', interestedIds.toList());
      }
      _message(action == 'interested' ? '관심 표시했어요.' : '추천에 반영했어요.');
    } catch (error) {
      if (interested && mounted) {
        setState(() => interestedIds = {...interestedIds}..remove(id));
      }
      _message('저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    }
  }

  Future<void> _dismissRecommendation(Map<String, dynamic> event) async {
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('관심 없는 이유 (선택사항)')),
        for (final choice in ['관심 없는 분야', '시간 안 맞음', '장소가 멂', '참가 조건 안 맞음', '이미 알고 있는 행사'])
          ListTile(title: Text(choice), onTap: () => Navigator.pop(context, choice)),
        TextButton(onPressed: () => Navigator.pop(context, ''), child: Text('이유 없이 관심 없음')),
      ])),
    );
    if (reason == null) return;
    try {
      await api.post('/v1/interactions', {
        'eventId': event['id'], 'action': 'not_interested',
        if (reason.isNotEmpty) 'reason': reason,
      });
      if (mounted) {
        setState(() => recommended = recommended.where((item) => item['id'] != event['id']).toList());
      }
      _message('추천에서 제외했어요.');
    } catch (error) { _message('저장하지 못했어요. 잠시 후 다시 시도해 주세요.'); }
  }

  Future<void> _planRecommendation(Map<String, dynamic> event) async {
    try {
      await api.post('/v1/interactions', {
        'eventId': event['id'],
        'action': 'recommendation_opened',
      });
      await api.post('/v1/goals', {'eventId': event['id']});
      _openRecommendation(event);
    } catch (error) {
      _error(error);
    }
  }

  void _openRecommendation(Map<String, dynamic> event) {
    final session = CueSession(
      label: '',
      startsAt: DateTime.parse(event['startsAt'] as String).toLocal(),
      endsAt: DateTime.parse(event['endsAt'] as String).toLocal(),
      venue: event['venue'] as String,
    );
    setState(() {
      candidate = CueEvent(
        title: event['title'] as String,
        category: event['category'] as String,
        description: event['description'] as String? ?? '',
        tags: (event['tags'] as List<dynamic>? ?? [])
            .whereType<String>()
            .toList(),
        format: event['format'] as String? ?? '기타',
        domains: (event['domains'] as List<dynamic>? ?? []).whereType<String>().toList(),
        applicationDeadline: event['applicationDeadline'] as String?,
        participationFee: event['participationFee'] as String?,
        sessions: [session],
      );
      titleController.text = candidate!.title;
      deadlineController.text = candidate!.applicationDeadline == null
          ? '' : candidate!.applicationDeadline!.substring(0, 10);
      feeController.text = candidate!.participationFee ?? '';
      showUnknownInputs = false;
      selectedCategory = candidate!.category;
      selectedSession = 0;
      _applySession(0);
      stage = ScanStage.review;
      reviewStep = 0;
      fromRecommendation = true;
      tabDirection = -1;
      tab = 0;
    });
  }

  Widget _detail(IconData icon, String text) => Padding(
    padding: EdgeInsets.only(top: 5),
    child: Row(
      children: [
        Icon(icon, size: 16, color: muted),
        SizedBox(width: 7),
        Expanded(
          child: Text(text, style: TextStyle(color: muted, fontSize: 13)),
        ),
      ],
    ),
  );
  Widget _pageTitle(String title, [String subtitle = '']) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: CueType.largeTitle.copyWith(color: ink)),
      if (subtitle.isNotEmpty) ...[
        SizedBox(height: 4),
        Text(subtitle, style: CueType.body.copyWith(color: muted, fontSize: 15)),
      ],
    ],
  );
  // 빈 화면은 상자에 넣지 않는다. 짧은 제목과 설명만 둔다.
  Widget _empty(IconData icon, String title, String text) => Padding(
    padding: EdgeInsets.symmetric(vertical: 28, horizontal: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 24, color: muted),
        SizedBox(height: 12),
        Text(title, style: CueType.headline.copyWith(color: ink)),
        SizedBox(height: 4),
        Text(text, style: CueType.caption.copyWith(color: muted, fontSize: 14)),
      ],
    ),
  );
  // 연결 문제는 화면 맨 위 한 줄로만 알린다.
  Widget _notice(String text, {VoidCallback? onTap, String? detail}) => Container(
    padding: EdgeInsets.fromLTRB(20, 6, 8, 6),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: borderColor, width: 0.5))),
    child: Row(
      children: [
        Icon(Icons.cloud_off_outlined, size: 16, color: muted),
        SizedBox(width: 8),
        Expanded(
          child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: CueType.caption.copyWith(color: muted)),
        ),
        if (detail != null && detail != text)
          TextButton(onPressed: () => _showDetail(detail), child: Text('자세히')),
        if (onTap != null) TextButton(onPressed: onTap, child: Text('다시 시도')),
      ],
    ),
  );
  // 행사·일정처럼 실제 대상을 담는 상자. 테두리와 그림자 없이 바탕색 차이로만 구분한다.
  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(CueRadius.card),
    ),
    child: child,
  );
  Widget _eyebrow(String value) => Text(value, style: CueType.label.copyWith(color: muted));
  // 설정 화면처럼 줄로 나눈 묶음 목록. 상자는 묶음 하나에만 쓰고 줄마다 나누지 않는다.
  Widget _group(List<Widget> rows, {String? label, String? footer}) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (label != null)
        Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 8), child: _eyebrow(label)),
      Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(CueRadius.card)),
        child: Column(children: [
          for (var i = 0; i < rows.length; i += 1) ...[
            if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: 16, color: borderColor),
            rows[i],
          ],
        ]),
      ),
      if (footer != null)
        Padding(
          padding: EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(footer, style: CueType.caption.copyWith(color: muted)),
        ),
      SizedBox(height: 24),
    ],
  );
  Widget _row(String title, {String? leading, String? value, String? subtitle, Widget? trailing, VoidCallback? onTap, Color? color}) => InkWell(
    onTap: onTap,
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: 50),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            if (leading != null) ...[
              Text(leading, style: TextStyle(fontSize: 20)),
              SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: CueType.body.copyWith(color: color ?? ink)),
                  if (subtitle != null) ...[
                    SizedBox(height: 2),
                    Text(subtitle, style: CueType.caption.copyWith(color: muted)),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              SizedBox(width: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 170),
                child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end, style: CueType.body.copyWith(color: muted)),
              ),
            ],
            if (trailing != null) ...[SizedBox(width: 8), trailing]
            else if (onTap != null) ...[SizedBox(width: 4), Icon(Icons.chevron_right, size: 20, color: muted)],
          ],
        ),
      ),
    ),
  );
  String _reminderLabel(int value) => switch (value) {
    15 => '15분 전',
    60 => '1시간 전',
    1440 => '1일 전',
    _ => '알림 없음',
  };
  Widget _button(
    String label,
    IconData icon,
    VoidCallback? onTap, {
    bool light = false,
    bool outlined = false,
  }) => SizedBox(
    width: double.infinity,
    height: 50,
    child: outlined
        ? OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: ink,
              side: BorderSide(color: borderColor),
            ),
          )
        : FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 20),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: light ? (isDark ? Color(0xFF26292D) : Color(0xFFEEF0F2)) : accent,
              foregroundColor: light ? ink : (isDark ? Color(0xFF101214) : Colors.white),
            ),
          ),
  );
  String _date(DateTime value) => '${_dateOnly(value)} ${_timeOnly(value)}';
}

// 포스터 두 장과 캘린더 표시. 포스터가 일정이 된다는 것을 그림 하나로 보여 준다.
class _PosterArt extends CustomPainter {
  _PosterArt({required this.front, required this.back, required this.line, required this.accent, required this.shadow});

  final Color front;
  final Color back;
  final Color line;
  final Color accent;
  final bool shadow;

  void _poster(Canvas canvas, Offset center, double w, double h, double angle, Color fill, Color header) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final body = RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2, -h / 2, w, h), const Radius.circular(8));
    if (shadow) canvas.drawShadow(Path()..addRRect(body), const Color(0x33000000), 4, false);
    canvas.drawRRect(body, Paint()..color = fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2 + 8, -h / 2 + 8, w - 16, h * 0.42), const Radius.circular(5)),
      Paint()..color = header,
    );
    var y = -h / 2 + 8 + h * 0.42 + 10;
    for (final ratio in [0.85, 0.55, 0.7]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-w / 2 + 8, y, (w - 16) * ratio, 6), const Radius.circular(3)),
        Paint()..color = line,
      );
      y += 12;
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    _poster(canvas, Offset(cx + 30, cy - 4), 88, 118, 0.14, back, line);
    _poster(canvas, Offset(cx - 22, cy + 2), 96, 128, -0.1, front, accent.withValues(alpha: 0.85));

    // 오른쪽 아래의 캘린더 표시.
    canvas.save();
    canvas.translate(cx + 50, cy + 36);
    canvas.rotate(0.05);
    final chip = RRect.fromRectAndRadius(const Rect.fromLTWH(-32, -28, 64, 56), const Radius.circular(10));
    if (shadow) canvas.drawShadow(Path()..addRRect(chip), const Color(0x40000000), 5, false);
    canvas.drawRRect(chip, Paint()..color = front);
    canvas.save();
    canvas.clipRRect(chip);
    canvas.drawRect(const Rect.fromLTWH(-32, -28, 64, 15), Paint()..color = accent);
    canvas.restore();
    canvas.drawPath(
      Path()
        ..moveTo(-11, 6)
        ..lineTo(-3, 14)
        ..lineTo(12, -2),
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PosterArt old) =>
      old.front != front || old.back != back || old.line != line || old.accent != accent || old.shadow != shadow;
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
