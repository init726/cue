import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_calendar/device_calendar.dart' as calendar;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import 'cue_api.dart';
import 'cue_colors.dart';
import 'cue_event_identity.dart';
import 'cue_categories.dart';
import 'cue_location.dart';
import 'cue_logo.dart';
import 'cue_map_launcher.dart';
import 'cue_map_page.dart';
import 'cue_period.dart';
import 'cue_period_planner.dart';
import 'cue_place_search.dart';
import 'cue_route.dart';
import 'cue_schedule_fields.dart';
import 'cue_schedule_agent.dart';
import 'cue_splash.dart';
import 'cue_travel_estimator.dart';
import 'cue_upcoming.dart';
import 'saved_event_editor.dart';

final cueThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
// release 빌드에서 CUE_API_URL을 빠뜨려도 개발용 localhost가 아니라 배포 서버로 연결한다.
const cueApiUrl = String.fromEnvironment(
  'CUE_API_URL',
  defaultValue: bool.fromEnvironment('dart.vm.product')
      ? 'https://cue-api-vczh.onrender.com'
      : 'http://localhost:8787',
);

ThemeData cueTheme(Brightness brightness) {
  final c = CueColors.forBrightness(brightness);
  final background = c.background;
  final surface = c.surface;
  final foreground = c.ink;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    // 둥근 글꼴로 부드러운 인상을 준다. 굵기 500·600은 가까운 400·700으로 맞춰진다.
    fontFamily: 'NanumSquareRound',
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
      surface: surface,
    ).copyWith(
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.accent,
      onSecondary: c.onAccent,
      secondaryContainer: c.tint,
      onSecondaryContainer: c.accentText,
      onSurface: c.ink,
      onSurfaceVariant: c.muted,
      outline: c.border,
      outlineVariant: c.border,
      error: c.danger,
      surfaceContainerLowest: surface,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surface,
      surfaceContainerHighest: c.surfaceMuted,
    ),
    dividerColor: c.border,
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: surface,
      indicatorColor: c.tint,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
        color: states.contains(WidgetState.selected) ? c.accentText : c.muted,
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        size: 23,
        color: states.contains(WidgetState.selected) ? c.accentText : c.muted,
      )),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(0, 52),
      backgroundColor: c.primary,
      foregroundColor: c.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    )),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
      foregroundColor: c.ink,
      side: BorderSide(color: c.border),
    )),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.accentText)),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: c.tint,
      side: BorderSide(color: c.border),
      labelStyle: TextStyle(color: c.ink),
      secondaryLabelStyle: TextStyle(color: c.accentText, fontWeight: FontWeight.w700),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: c.accent),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      elevation: 12,
      backgroundColor: surface,
      contentTextStyle: TextStyle(color: foreground, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.border),
      ),
      actionTextColor: c.accentText,
    ),
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: foreground,
        height: 1.2,
      ),
      titleLarge: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        color: foreground,
      ),
      bodyMedium: TextStyle(fontSize: 15, color: foreground, height: 1.5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
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
      // 날짜·시간 휠과 기본 대화상자를 한국어(년·월·일 순서)로 보여준다.
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const CueHome(),
    ),
  );
}

enum ScanStage { idle, processing, notEvent, pastEvent, review, saved }

class _CalendarSchedule {
  const _CalendarSchedule(this.item, this.event, this.savedEvent);

  final CueScheduleItem item;
  final calendar.Event event;
  final Map<String, dynamic>? savedEvent;
}

class _ScheduleChoice {
  const _ScheduleChoice(this.action, [this.slot, this.savedEvent, this.sessionIndex]);

  final String action;
  final CueTimeSlot? slot;
  final Map<String, dynamic>? savedEvent;
  final int? sessionIndex;
}

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
  // 색은 cue_colors.dart에서만 정한다. accent는 글자에도 쓰이므로 대비가 충분한 accentText를 쓴다.
  CueColors get colors => CueColors.of(context);
  Color get ink => colors.ink;
  Color get muted => colors.muted;
  Color get paper => colors.background;
  Color get accent => colors.accentText;
  Color get mint => colors.tint;
  Color get surface => colors.surface;
  Color get borderColor => colors.border;
  Color get cameraCard => colors.hero;

  final api = CueApi(cueApiUrl);
  final picker = ImagePicker();
  final calendarPlugin = calendar.DeviceCalendarPlugin();
  final travelEstimator = CueTravelEstimator();
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
  String? routePlanNote;
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
  bool locationBackfillRunning = false;
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
  String? recommendationError;
  List<String> interestLabels = [];
  // 직접 고른 관심 분야. 기록이 없어도 첫날부터 맞춤 추천에 쓴다.
  Set<String> favoriteTopics = {};
  bool sharingEvent = false;
  bool preventDuplicateEvents = true;
  bool checkScheduleConflicts = true;
  bool confirmLocalVenues = true;
  bool venueConfirmed = false;
  // 지도 검색으로 고른 장소. 장소 칸의 글자가 이 이름과 같을 때만 저장에 쓴다.
  CuePlace? selectedPlace;
  double? regionLatitude;
  double? regionLongitude;
  // 켜 두면 활동 지역을 기기의 현재 동네로 맞추고 앱을 열 때 가끔 갱신한다.
  bool useDeviceLocation = false;
  // 지도를 열 앱. 비어 있으면 처음 열 때 묻는다.
  String? mapAppPreference;
  bool locating = false;
  final locator = const CueLocator();
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
    preventDuplicateEvents = prefs.getBool('prevent_duplicate_events') ?? true;
    checkScheduleConflicts = prefs.getBool('check_schedule_conflicts') ?? true;
    confirmLocalVenues = prefs.getBool('confirm_local_venues') ?? true;
    useDeviceLocation = prefs.getBool('cue_use_device_location') ?? false;
    mapAppPreference = prefs.getString('cue_map_app');
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
    _weatherRequests.clear();
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
      // 추천은 새 행사를 찾느라 오래 걸릴 수 있어 내 일정과 따로 불러온다.
      final me = await api.get('/v1/me');
      if (!mounted) return;
      setState(() {
        final profile = me['profile'] as Map<String, dynamic>? ?? {};
        communitySchool = profile['school'] as String? ?? '';
        communityRegion = profile['region'] as String? ?? '';
        regionLatitude = (profile['regionLatitude'] as num?)?.toDouble();
        if (profile['favoriteTopics'] is List) {
          favoriteTopics = (profile['favoriteTopics'] as List).whereType<String>().toSet();
        }
        regionLongitude = (profile['regionLongitude'] as num?)?.toDouble();
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
        final interestRows = (me['interests'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .where((row) => (row['interestKey'] as String? ?? '').startsWith('domain:') &&
                ((row['score'] as num?) ?? 0) > 0 && row['interestKey'] != 'domain:기타')
            .toList()
          ..sort((a, b) => ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0));
        interestLabels = interestRows
            .map((row) => (row['interestKey'] as String).substring(7))
            .take(3)
            .toList();
        apiError = null;
        apiErrorDetail = null;
      });
      if (onboardingCompleted) {
        await prefs.setBool('cue_onboarding_completed', true);
      }
      if (cloudConnected) unawaited(_backfillSavedLocations());
      if (useDeviceLocation && !locating) {
        final last = DateTime.tryParse(prefs.getString('cue_device_location_at') ?? '');
        if (last == null || DateTime.now().difference(last) > const Duration(hours: 6)) {
          await _useCurrentLocation(silent: true);
        }
      }
      await _loadRecommendations(recommendationRoute);
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

  // 앞으로 7일의 바쁜 시간(제목 없이 시작/끝만). 캘린더 권한이 이미 있을 때만 읽고 권한을 묻지 않는다.
  Future<String?> _busyQuery() async {
    try {
      if ((await calendarPlugin.hasPermissions()).data != true) return null;
      final list = await calendarPlugin.retrieveCalendars();
      final calendars = list.data?.where((item) => item.id != null).toList() ?? [];
      final now = DateTime.now();
      final rows = await _readSchedules(calendars, now, now.add(Duration(days: 7)));
      return rows.take(80).map((row) =>
          '${row.item.start.toUtc().toIso8601String()}/${row.item.end.toUtc().toIso8601String()}').join(',');
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadRecommendations(String route) async {
    try {
      final busy = await _busyQuery();
      if (busy != null) route += '${route.contains('?') ? '&' : '?'}busy=${Uri.encodeQueryComponent(busy)}';
      final recs = await api.get(route);
      if (!mounted) return;
      setState(() {
        recommended = (recs['events'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        recommendationError = null;
        recommendationLoading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          recommendationLoading = false;
          recommendationError = _friendly(error);
        });
      }
    }
  }

  Future<void> _backfillSavedLocations() async {
    if (locationBackfillRunning || userId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'cue_location_backfill_v1_$userId';
    if (prefs.getBool(key) == true) return;
    locationBackfillRunning = true;
    try {
      for (final event in saved.where((row) => row['locationLatitude'] == null).take(20)) {
        final venue = event['venue'] as String? ?? '';
        final point = await travelEstimator.geocode(venue);
        if (point == null) continue;
        final id = event['id'] as String?;
        if (id == null) continue;
        await api.patch('/v1/events/$id', {
          'title': event['title'],
          'venue': venue,
          'startsAt': event['startsAt'],
          'endsAt': event['endsAt'],
          'category': event['category'] ?? '기타',
          'description': event['description'] ?? '',
          'tags': event['tags'] ?? [],
          'format': event['format'] ?? '기타',
          'domains': event['domains'] ?? [],
          'applicationDeadline': event['applicationDeadline'],
          'participationFee': event['participationFee'],
          'locationAddress': event['locationAddress'],
          'locationLatitude': point.latitude,
          'locationLongitude': point.longitude,
          'sourceUrl': event['sourceUrl'],
          'calendarId': event['calendarId'],
          'calendarEventId': event['calendarEventId'],
          'reminderMinutes': event['reminderMinutes'],
        });
        if (event['shared'] == true) {
          await api.post('/v1/events/$id/share', {'confirmPublic': true});
        }
      }
      await prefs.setBool(key, true);
    } catch (_) {
      // 다음 실행 때 안전하게 다시 시도한다.
    } finally {
      locationBackfillRunning = false;
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
        venueConfirmed = false;
        _applySession(selectedSession);
        if (event.period != null) venueController.text = event.period!.venue;
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
    venueConfirmed = false;
  }

  static const _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];
  String _dateOnly(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')} (${_weekdayNames[value.weekday - 1]})';
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
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink),
                    ),
                    SizedBox(height: 6),
                    Text(
                      ambiguous
                          ? '안내문에서 날짜나 시간, 장소가 분명하지 않았어요. 아래에서 직접 골라 주세요.'
                          : '캘린더에 저장할 날짜, 시간, 장소를 골라 주세요.',
                      style: TextStyle(color: muted, height: 1.5),
                    ),
                    SizedBox(height: 16),
                    CueScheduleFields(
                      start: start,
                      length: end.difference(start),
                      onChanged: (nextStart, nextEnd) => setSheet(() {
                        start = nextStart;
                        end = nextEnd;
                        problem = null;
                      }),
                    ),
                    SizedBox(height: 14),
                    TextField(
                      controller: venueField,
                      decoration: InputDecoration(
                        labelText: '장소',
                        prefixIcon: Icon(Icons.place_outlined),
                      ),
                    ),
                    if (problem != null) ...[
                      SizedBox(height: 8),
                      Text(problem!, style: TextStyle(color: colors.danger, fontSize: 13)),
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
      venueConfirmed = false;
    });
    return true;
  }

  Future<bool> _confirmVenueContext() async {
    if (!confirmLocalVenues || venueConfirmed || !cueVenueNeedsContext(venueController.text)) {
      return true;
    }
    final field = TextEditingController(text: venueController.text);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
        child: SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('이 장소를 찾을 수 있게 적어주세요',
                style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 7),
            Text('Cue는 ‘본관’이나 ‘교내 강당’만으로는 어느 학교인지 알 수 없어요. '
                '학교 또는 캠퍼스 이름과 건물·층·호실을 함께 적어주세요.',
                style: TextStyle(color: muted, height: 1.5)),
            SizedBox(height: 16),
            TextField(
              controller: field,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '정확한 장소',
                hintText: '예: 한국고등학교 본관 2층 시청각실',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final value = field.text.trim();
                if (value.isNotEmpty) Navigator.pop(sheetContext, value);
              },
              style: FilledButton.styleFrom(minimumSize: Size.fromHeight(52)),
              child: Text('이 장소로 확인'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, venueController.text.trim()),
              style: TextButton.styleFrom(minimumSize: Size.fromHeight(46)),
              child: Text('장소를 알고 있어요 · 이대로 계속'),
            ),
          ]),
        ),
      ),
    );
    field.dispose();
    if (result == null || !mounted) return false;
    setState(() {
      venueController.text = result;
      venueConfirmed = true;
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

  CueScheduleItem? _savedSchedule(Map<String, dynamic> event) {
    final start = DateTime.tryParse(event['startsAt'] as String? ?? '')?.toLocal();
    final end = DateTime.tryParse(event['endsAt'] as String? ?? '')?.toLocal();
    if (start == null || end == null || !end.isAfter(start)) return null;
    return CueScheduleItem(
      id: event['id'] as String? ?? '',
      title: event['title'] as String? ?? '',
      venue: event['venue'] as String? ?? '',
      start: start,
      end: end,
    );
  }

  String _slotLabel(CueTimeSlot slot) =>
      '${_dateOnly(slot.start)}  ${_timeOnly(slot.start)}–${_timeOnly(slot.end)}';

  Future<List<_CalendarSchedule>> _readDaySchedules(
    List<calendar.Calendar> calendars,
    DateTime date,
  ) {
    final dayStart = DateTime(date.year, date.month, date.day);
    return _readSchedules(calendars, dayStart, dayStart.add(Duration(days: 1)));
  }

  Future<List<_CalendarSchedule>> _readSchedules(
    List<calendar.Calendar> calendars,
    DateTime dayStart,
    DateTime dayEnd,
  ) async {
    final rows = <_CalendarSchedule>[];
    for (final source in calendars) {
      if (source.id == null) continue;
      final result = await calendarPlugin.retrieveEvents(
        source.id,
        calendar.RetrieveEventsParams(startDate: dayStart, endDate: dayEnd),
      );
      if (result.isSuccess != true) continue;
      for (final event in result.data ?? const <calendar.Event>[]) {
        if (event.allDay == true) continue;
        final start = event.start?.toLocal();
        final end = event.end?.toLocal();
        if (start == null || end == null || !end.isAfter(start)) continue;
        final linked = saved.where((item) =>
            item['calendarId'] == event.calendarId &&
            item['calendarEventId'] == event.eventId).firstOrNull;
        rows.add(_CalendarSchedule(
          CueScheduleItem(
            id: event.eventId ?? '${event.calendarId}:${event.title}:$start',
            title: event.title?.trim().isNotEmpty == true ? event.title!.trim() : '이름 없는 일정',
            venue: event.location?.trim() ?? '',
            start: start,
            end: end,
          ),
          event,
          linked,
        ));
      }
    }
    return rows;
  }

  Future<bool> _confirmCalendarDuplicate(_CalendarSchedule duplicate) async {
    final linked = duplicate.savedEvent;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.content_copy_outlined, color: accent, size: 30),
            SizedBox(height: 12),
            Text('이미 캘린더에 있는 행사예요',
                style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 7),
            Text('${duplicate.item.title}\n${_slotLabel(CueTimeSlot(duplicate.item.start, duplicate.item.end))}'
                '${duplicate.item.venue.isEmpty ? '' : '\n${duplicate.item.venue}'}',
                style: TextStyle(color: muted, height: 1.5)),
            SizedBox(height: 16),
            if (linked != null)
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, 'existing'),
                style: FilledButton.styleFrom(minimumSize: Size.fromHeight(50)),
                child: Text('기존 일정 보기'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, 'again'),
              style: TextButton.styleFrom(minimumSize: Size.fromHeight(48)),
              child: Text('그래도 하나 더 저장'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, 'cancel'),
              style: TextButton.styleFrom(minimumSize: Size.fromHeight(44)),
              child: Text('취소'),
            ),
          ]),
        ),
      ),
    );
    if (action == 'existing' && mounted) {
      setState(() {
        tabDirection = 1;
        tab = 1;
        routeFocusDate = duplicate.item.start;
        routeFocusRequest += 1;
      });
      _message('이미 저장한 일정으로 이동했어요.');
      return false;
    }
    return action == 'again';
  }

  Future<_ScheduleChoice?> _chooseConflictRoute(
    List<_CalendarSchedule> all,
    List<_CalendarSchedule> conflicts,
    DateTime newStart,
    DateTime newEnd,
  ) async {
    final period = candidate?.period;
    final busy = all.map((row) => row.item).toList();
    final periodSlot = period == null ? null : cueBestVisitOn(period, newStart, busy,
        now: DateTime.now(), visit: newEnd.difference(newStart));
    final newSlots = period != null
        ? [?periodSlot]
        : candidate?.timeMode == 'flexible'
            ? cueNearestFreeSlots(newStart, newEnd, busy)
            : const <CueTimeSlot>[];
    final alternateSessions = <MapEntry<int, CueSession>>[
      for (final entry in (candidate?.sessions ?? const <CueSession>[]).asMap().entries)
        if (entry.key != selectedSession &&
            !all.any((row) => cueSchedulesOverlap(
                entry.value.startsAt, entry.value.endsAt, row.item)))
          entry,
    ];
    final movable = conflicts.length == 1 ? conflicts.single.savedEvent : null;
    final existing = movable == null ? null : _savedSchedule(movable);
    // 과거 저장 데이터에는 고정/자유 방문 여부가 없으므로 기존 행사를 임의로 옮기지 않는다.
    final existingSlots = const <CueTimeSlot>[];
    if (!mounted) return null;
    return showModalBottomSheet<_ScheduleChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.84),
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(20, 0, 20, 22),
            children: [
              Icon(Icons.alt_route_rounded, color: accent, size: 31),
              SizedBox(height: 11),
              Text('이 시간에는 다른 일정이 있어요',
                  style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
              SizedBox(height: 7),
              Text('행사 시간을 임의로 바꾸지 않아요. 시간을 조정할 수 있는 행사인 경우에만 빈 시간을 골라 주세요.',
                  style: TextStyle(color: muted, height: 1.5)),
              SizedBox(height: 14),
              for (final conflict in conflicts)
                Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(13),
                  decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: borderColor)),
                  child: Row(children: [
                    Icon(Icons.event_busy_outlined, color: colors.warn),
                    SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(conflict.item.title, style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
                      Text('${_timeOnly(conflict.item.start)}–${_timeOnly(conflict.item.end)}',
                          style: TextStyle(color: muted, fontSize: 13)),
                    ])),
                  ]),
                ),
              if (alternateSessions.isNotEmpty) ...[
                SizedBox(height: 12),
                Text('안내문에 있는 다른 회차',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('실제 행사 안내에 적힌 선택지라 시간을 임의로 바꾸지 않아요.',
                    style: TextStyle(color: muted, fontSize: 12)),
                for (final entry in alternateSessions)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event_available_outlined, color: accent),
                    title: Text(_slotLabel(CueTimeSlot(entry.value.startsAt, entry.value.endsAt))),
                    subtitle: Text(entry.value.venue),
                    trailing: Icon(Icons.chevron_right, color: muted),
                    onTap: () => Navigator.pop(sheetContext,
                        _ScheduleChoice('alternate', null, null, entry.key)),
                  ),
              ],
              if (newSlots.isNotEmpty) ...[
                SizedBox(height: 12),
                Text('방금 찍은 행사를 옮기기',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('자유 방문·체험처럼 시간을 바꿔도 될 때만 선택하세요.',
                    style: TextStyle(color: muted, fontSize: 12)),
                for (final slot in newSlots)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.schedule_outlined, color: accent),
                    title: Text(_slotLabel(slot)),
                    trailing: Icon(Icons.chevron_right, color: muted),
                    onTap: () => Navigator.pop(sheetContext, _ScheduleChoice('move_new', slot)),
                  ),
              ],
              if (existing != null && existingSlots.isNotEmpty) ...[
                Divider(color: borderColor, height: 28),
                Text('기존 Cue 일정을 옮기기',
                    style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
                SizedBox(height: 5),
                Text('${existing.title}의 시간을 바꿔도 되는지 확인해 주세요.',
                    style: TextStyle(color: muted, fontSize: 12)),
                for (final slot in existingSlots.take(2))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.event_repeat_outlined, color: accent),
                    title: Text(_slotLabel(slot)),
                    trailing: Icon(Icons.chevron_right, color: muted),
                    onTap: () => Navigator.pop(sheetContext, _ScheduleChoice('move_existing', slot, movable)),
                  ),
              ],
              Divider(color: borderColor, height: 24),
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext, _ScheduleChoice('keep')),
                style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                child: Text('겹친 채로 저장'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                style: TextButton.styleFrom(minimumSize: Size.fromHeight(46)),
                child: Text('돌아가서 다시 확인'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmMovable(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('시간을 바꿔도 되나요?'),
          content: Text('$title이(가) 고정 시간 행사면 옮기지 마세요. '
              '자유 방문 행사나 조정 가능한 일정일 때만 계속해 주세요.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('아니요')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('옮겨도 돼요')),
          ],
        ),
      ) ?? false;

  Future<void> _moveSavedSchedule(Map<String, dynamic> savedEvent, CueTimeSlot slot) async {
    final id = savedEvent['id'] as String;
    final deviceEvent = await _resolveSavedEvent(savedEvent);
    final previousStart = deviceEvent.start;
    final previousEnd = deviceEvent.end;
    deviceEvent.start = tz.TZDateTime.from(slot.start, tz.UTC);
    deviceEvent.end = tz.TZDateTime.from(slot.end, tz.UTC);
    final result = await calendarPlugin.createOrUpdateEvent(deviceEvent);
    if (result?.isSuccess != true) throw CueApiException('기존 캘린더 일정을 옮기지 못했어요.');
    try {
      await api.patch('/v1/events/$id', {
        'title': savedEvent['title'],
        'venue': savedEvent['venue'],
        'startsAt': slot.start.toUtc().toIso8601String(),
        'endsAt': slot.end.toUtc().toIso8601String(),
        'category': savedEvent['category'] ?? '기타',
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
        'reminderMinutes': savedEvent['reminderMinutes'],
      });
    } catch (_) {
      deviceEvent.start = previousStart;
      deviceEvent.end = previousEnd;
      await calendarPlugin.createOrUpdateEvent(deviceEvent);
      throw CueApiException('서버에 반영하지 못해 기존 일정 시간을 되돌렸어요.');
    }
    await _refresh();
  }

  Future<bool> _reviewCalendarPlacement(
    List<calendar.Calendar> calendars,
    String title,
    String venue,
  ) async {
    final start = startsAt!;
    final end = endsAt!;
    final rows = await _readDaySchedules(calendars, start);
    final duplicate = rows.where((row) => cueLooksLikeDuplicate(
        title, venue, start, end, row.item)).firstOrNull;
    if (preventDuplicateEvents && duplicate != null) {
      return _confirmCalendarDuplicate(duplicate);
    }
    if (!checkScheduleConflicts) return true;
    final conflicts = rows.where((row) => cueSchedulesOverlap(start, end, row.item)).toList();
    if (conflicts.isEmpty) return _reviewTravelFeasibility(rows, title, venue, start, end);
    final choice = await _chooseConflictRoute(rows, conflicts, start, end);
    if (choice == null) return false;
    if (choice.action == 'keep') return true;
    if (choice.action == 'alternate' && choice.sessionIndex != null) {
      if (!mounted) return false;
      setState(() {
        selectedSession = choice.sessionIndex;
        _applySession(choice.sessionIndex);
      });
      return true;
    }
    if (choice.action == 'move_new' && choice.slot != null) {
      // 기간형 행사는 운영 시간 안에서만 옮기므로 따로 묻지 않는다.
      if (candidate?.period == null && !await _confirmMovable(title)) return false;
      if (!mounted) return false;
      setState(() {
        startsAt = choice.slot!.start;
        endsAt = choice.slot!.end;
        selectedSession = null;
      });
      return true;
    }
    if (choice.action == 'move_existing' && choice.slot != null && choice.savedEvent != null) {
      if (!await _confirmMovable(choice.savedEvent!['title'] as String? ?? '기존 일정')) return false;
      await _moveSavedSchedule(choice.savedEvent!, choice.slot!);
      return true;
    }
    return false;
  }

  Future<bool> _reviewTravelFeasibility(
    List<_CalendarSchedule> rows, String title, String venue, DateTime start, DateTime end,
  ) async {
    final before = rows.where((row) => !row.item.end.isAfter(start)).toList()
      ..sort((a, b) => b.item.end.compareTo(a.item.end));
    final after = rows.where((row) => !row.item.start.isBefore(end)).toList()
      ..sort((a, b) => a.item.start.compareTo(b.item.start));
    final previous = before.firstOrNull?.item;
    final next = after.firstOrNull?.item;
    final fromPrevious = previous == null ? null : await travelEstimator.estimate(
      from: previous.venue, to: venue, departureAt: previous.end,
    );
    final toNext = next == null ? null : await travelEstimator.estimate(
      from: venue, to: next.venue, departureAt: end,
    );
    final arrivalBuffer = candidate?.recommendedArrivalMinutes ?? 15;
    final assessment = cueAssessPlacement(
      start: start, end: end,
      previous: fromPrevious == null ? null : previous,
      next: toNext == null ? null : next,
      travelFromPreviousMinutes: fromPrevious?.minutes ?? 0,
      travelToNextMinutes: toNext?.minutes ?? 0,
      arrivalBufferMinutes: arrivalBuffer,
    );
    final pieces = <String>[];
    if (previous != null && fromPrevious != null) {
      final depart = start.subtract(Duration(minutes: fromPrevious.minutes + arrivalBuffer));
      pieces.add('${previous.title}에서 약 ${fromPrevious.minutes}분 · ${_timeOnly(depart)}까지 출발');
    } else if (arrivalBuffer > 0) {
      pieces.add('행사 $arrivalBuffer분 전 도착 권장');
    }
    if (next != null && toNext != null) pieces.add('${next.title}까지 약 ${toNext.minutes}분');
    routePlanNote = pieces.join('\n');
    if (assessment.isFeasible) return true;
    if (!mounted) return false;
    final reason = !assessment.canArrive
        ? '앞 일정이 끝난 뒤 이동하면 $arrivalBuffer분 전 도착하기 어려워요.'
        : '행사가 끝난 뒤 다음 일정 장소까지 제시간에 가기 어려워요.';
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.route_outlined, color: accent, size: 32),
            SizedBox(height: 12),
            Text('이동까지 포함하면 일정이 빠듯해요', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
            SizedBox(height: 7),
            Text(reason, style: TextStyle(color: muted, height: 1.5)),
            if (routePlanNote?.isNotEmpty == true) ...[
              SizedBox(height: 12),
              Text(routePlanNote!, style: TextStyle(color: ink, fontWeight: FontWeight.w700, height: 1.5)),
            ],
            SizedBox(height: 18),
            if (candidate!.sessions.length > 1)
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, 'session'),
                style: FilledButton.styleFrom(minimumSize: Size.fromHeight(50)),
                child: Text('다른 회차 선택'),
              ),
            if (candidate!.movable)
              OutlinedButton(
                onPressed: () => Navigator.pop(sheetContext, 'edit'),
                style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(48)),
                child: Text('방문 시간 다시 정하기'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext, 'keep'),
              style: TextButton.styleFrom(minimumSize: Size.fromHeight(46)),
              child: Text('그래도 이 시간으로 저장'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              style: TextButton.styleFrom(minimumSize: Size.fromHeight(44)),
              child: Text('돌아가기'),
            ),
          ]),
        ),
      ),
    );
    if (action == 'keep') return true;
    if (action == 'session') unawaited(_chooseSession());
    if (action == 'edit') {
      unawaited(candidate?.period != null ? _planPeriodVisit() : _editSchedule(forced: true));
    }
    return false;
  }

  Future<void> _save() async {
    if (candidate == null) return;
    if (candidate!.sessions.length > 1 && selectedSession == null && startsAt == null) {
      _message('시간과 장소 중 하나를 선택해 주세요.');
      unawaited(_chooseSession());
      return;
    }
    if (candidate!.period != null && startsAt == null) {
      _message('방문할 날짜와 시간을 정해 주세요.');
      unawaited(_planPeriodVisit());
      return;
    }
    final title = titleController.text.trim();
    var venue = venueController.text.trim();
    if (title.isEmpty || venue.isEmpty || startsAt == null || endsAt == null) {
      _message('행사 이름, 장소, 시간을 확인해 주세요.');
      return;
    }
    if (!endsAt!.isAfter(startsAt!)) {
      _message('종료 시간이 시작 시간보다 빨라요.');
      return;
    }
    final selected = selectedSession == null || selectedSession! >= candidate!.sessions.length
        ? null : candidate!.sessions[selectedSession!];
    final printedMidnight = selected?.timeText.contains('00:00') == true ||
        selected?.timeText.contains('0시') == true || selected?.timeText.contains('자정') == true;
    if (startsAt!.hour == 0 && startsAt!.minute == 0 && !printedMidnight) {
      _message('00:00은 확인된 자정 시간이 아니에요. 실제 시작 시간을 선택해 주세요.');
      unawaited(_editSchedule(ambiguous: true, forced: true));
      return;
    }
    if (deadlineController.text.trim().isNotEmpty &&
        (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(deadlineController.text.trim()) ||
         DateTime.tryParse(deadlineController.text.trim()) == null)) {
      _message('신청 마감일은 YYYY-MM-DD 형식으로 입력해 주세요.');
      return;
    }
    if (!await _confirmVenueContext()) return;
    venue = venueController.text.trim();
    setState(() => saving = true);
    try {
      final permission = await calendarPlugin.requestPermissions();
      if (permission.data != true) {
        throw CueApiException('캘린더 권한이 필요해요. 기기 설정에서 허용해 주세요.');
      }
      final list = await calendarPlugin.retrieveCalendars();
      final allCalendars =
          list.data?.where((item) => item.id != null).toList() ?? [];
      final calendars =
          allCalendars.where((item) => item.isReadOnly != true).toList();
      if (calendars.isEmpty) throw CueApiException('저장할 수 있는 캘린더가 없어요.');
      final target =
          calendars
              .where((item) => item.id == preferredCalendarId)
              .firstOrNull ??
          calendars.where((item) => item.isDefault == true).firstOrNull ??
          calendars.first;
      if (!await _reviewCalendarPlacement(allCalendars, title, venue)) return;
      if (!await _confirmVenueContext()) return;
      venue = venueController.text.trim();
      final period = candidate!.period;
      final description = period == null ? candidate!.description
          : [candidate!.description, cuePeriodNote(period, CueTimeSlot(startsAt!, endsAt!))]
              .where((part) => part.isNotEmpty).join('\n\n');
      final event = calendar.Event(
        target.id,
        title: title,
        location: venue,
        description: description,
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
        final place = _pickedPlace;
        final eventPoint = place == null ? await travelEstimator.geocode(venue) : null;
        await api.post('/v1/events', {
          'title': title,
          'venue': venue,
          'startsAt': startsAt!.toUtc().toIso8601String(),
          'endsAt': endsAt!.toUtc().toIso8601String(),
          'category': selectedCategory,
          'description': description,
          'tags': candidate!.tags,
          'format': candidate!.format,
          'domains': candidate!.domains,
          'applicationDeadline': deadlineController.text.trim().isEmpty
              ? null : DateTime.tryParse('${deadlineController.text.trim()}T23:59:00')?.toUtc().toIso8601String(),
          'participationFee': feeController.text.trim().isEmpty ? null : feeController.text.trim(),
          if (eventPoint != null) 'locationLatitude': eventPoint.latitude,
          if (eventPoint != null) 'locationLongitude': eventPoint.longitude,
          ...?place?.toSaveFields(),
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
      final venueChanged = draft.venue != savedEvent['venue'];
      final newPoint = venueChanged ? await travelEstimator.geocode(draft.venue) : null;
      try {
        await api.patch('/v1/events/$id', {
          'title': draft.title,
          'venue': draft.venue,
          if (!venueChanged) 'locationLatitude': savedEvent['locationLatitude'],
          if (!venueChanged) 'locationLongitude': savedEvent['locationLongitude'],
          if (venueChanged) ...{
            'placeId': null,
            'locationLatitude': newPoint?.latitude,
            'locationLongitude': newPoint?.longitude,
          },
          'startsAt': draft.startsAt.toUtc().toIso8601String(),
          'endsAt': draft.endsAt.toUtc().toIso8601String(),
          'category': draft.category,
          'format': savedEvent['format'] ?? '기타',
          'domains': savedEvent['domains'] ?? [],
          'description': savedEvent['description'] ?? '',
          'tags': savedEvent['tags'] ?? [],
          'applicationDeadline': savedEvent['applicationDeadline'],
          'participationFee': savedEvent['participationFee'],
          'locationAddress': venueChanged ? null : savedEvent['locationAddress'],
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
          decoration: BoxDecoration(color: colors.dangerTint, shape: BoxShape.circle),
          child: Icon(Icons.error_outline_rounded, size: 19, color: colors.danger),
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
      routePlanNote = null;
      stage = ScanStage.idle;
      reviewStep = 0;
      selectedSession = null;
      venueConfirmed = false;
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
            _header(),
            if (apiError != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _notice(apiError!, onTap: _refresh, detail: apiErrorDetail),
              ),
            Expanded(child: _scroll(_onboarding())),
          ]),
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            if (apiError != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _notice(apiError!, onTap: _refresh, detail: apiErrorDetail),
              ),
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
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor),
            boxShadow: isDark ? null : [BoxShadow(
              color: Colors.black.withValues(alpha: 0.07), blurRadius: 24, offset: Offset(0, 8))],
          ),
          clipBehavior: Clip.antiAlias,
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: _selectTab,
            destinations: [
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: '스캔',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '내 일정',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
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
      ),
    );
  }

  Widget _scroll(Widget child, {Future<void> Function()? onRefresh}) {
    final view = SingleChildScrollView(
      // 내용이 짧아도 당길 수 있고, iOS처럼 끝에서 튕긴다.
      physics: onRefresh == null ? null : AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      child: Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 32), child: child),
    );
    return onRefresh == null
        ? view
        : RefreshIndicator(
            color: accent,
            backgroundColor: colors.surface,
            strokeWidth: 2.6,
            displacement: 56,
            elevation: 3,
            onRefresh: () async {
              HapticFeedback.mediumImpact();
              await onRefresh();
            },
            child: view,
          );
  }
  Widget _header() => Padding(
    padding: EdgeInsets.fromLTRB(22, 14, 22, 8),
    child: Row(children: [CueLogo(size: 28)]),
  );

  // 시작은 서버 연결 없이 바로 한다. 온보딩에서 고른 추천 설정은 서버에 연결될 때 반영한다.
  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cue_onboarding_completed', true);
    await prefs.setBool('cue_onboarding_recommendations', personalizationEnabled && recommendationEnabled);
    await prefs.setString('cue_onboarding_region', communityRegion);
    await prefs.setString('cue_onboarding_age_band', communityAgeBand);
    await prefs.setStringList('cue_onboarding_topics', favoriteTopics.toList());
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
    final region = prefs.getString('cue_onboarding_region') ?? '';
    final ageBand = prefs.getString('cue_onboarding_age_band') ?? '';
    final topics = prefs.getStringList('cue_onboarding_topics') ?? const <String>[];
    final point = await travelEstimator.geocode(region);
    await api.patch('/v1/profile', {
      'onboardingCompleted': true,
      'personalizationEnabled': enabled,
      'recommendationEnabled': enabled,
      'region': region,
      'ageBand': ageBand,
      if (topics.isNotEmpty) 'favoriteTopics': topics,
      if (point != null) 'regionLatitude': point.latitude,
      if (point != null) 'regionLongitude': point.longitude,
    });
    await prefs.setBool('cue_onboarding_synced', true);
    onboardingPreferencesDirty = false;
  }

  Widget _topicChips(Set<String> selected, ValueChanged<Set<String>> onChanged) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final topic in cueTopics)
        FilterChip(
          label: Text(topic),
          selected: selected.contains(topic),
          showCheckmark: false,
          onSelected: (on) {
            final next = {...selected};
            if (on && next.length < 10) next.add(topic);
            if (!on) next.remove(topic);
            onChanged(next);
          },
        ),
    ],
  );

  // 추천 탭·설정에서 관심 분야를 고친다. 저장하면 바로 추천을 다시 불러온다.
  Future<void> _editTopics() async {
    var draft = {...favoriteTopics};
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(builder: (context, setSheet) => SafeArea(child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('관심 있는 분야', style: TextStyle(color: ink, fontSize: 20, fontWeight: FontWeight.w800)),
          SizedBox(height: 4),
          Text('최대 10개까지 고를 수 있어요. 저장한 행사에서 배운 관심사와 함께 써요.', style: TextStyle(color: muted, fontSize: 13)),
          SizedBox(height: 14),
          _topicChips(draft, (topics) => setSheet(() => draft = topics)),
          SizedBox(height: 18),
          _button('저장', Icons.check, () => Navigator.pop(sheetContext, draft)),
        ]),
      ))),
    );
    if (result == null || !mounted) return;
    setState(() => favoriteTopics = result);
    await _updateProfile({'favoriteTopics': result.toList()});
  }

  Widget _onboardingStep(String number, String title, String detail) =>
      Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(number, style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
                  Text(detail, style: TextStyle(color: muted, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _onboarding() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: 10),
      Text('Cue 시작하기', style: TextStyle(color: ink, fontSize: 30, fontWeight: FontWeight.w800)),
      SizedBox(height: 8),
      Text('포스터 한 장이면 캘린더 일정이 돼요.',
        style: TextStyle(color: muted, height: 1.5)),
      SizedBox(height: 24),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _eyebrow('사용 방법'),
        SizedBox(height: 10),
        _onboardingStep('1', '포스터나 공지문을 골라요', '촬영하거나 사진첩, PDF·한글 파일에서 고를 수 있어요.'),
        _onboardingStep('2', '일정 정보를 자동으로 읽어요', '시간과 장소를 확인하고 필요한 내용은 고쳐 주세요.'),
        _onboardingStep('3', '캘린더에 저장해요', '저장 버튼을 누른 일정만 캘린더에 추가돼요.'),
      ])),
      SizedBox(height: 14),
      _card(SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text('관심사 기반 행사 추천'),
        subtitle: Text('저장한 일정과 선택 기록으로 맞는 행사를 찾아드려요.'),
        value: personalizationEnabled && recommendationEnabled,
        onChanged: (value) => setState(() {
          onboardingPreferencesDirty = true;
          personalizationEnabled = value;
          recommendationEnabled = value;
        }),
      )),
      SizedBox(height: 14),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _eyebrow('관심 있는 분야'),
        SizedBox(height: 4),
        Text('3개 이상 고르면 첫날부터 맞는 행사를 추천해요.', style: TextStyle(color: muted, fontSize: 13)),
        SizedBox(height: 12),
        _topicChips(favoriteTopics, (topics) => setState(() => favoriteTopics = topics)),
      ])),
      SizedBox(height: 14),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _eyebrow('선택 · 추천 환경'),
        SizedBox(height: 10),
        TextField(
          decoration: InputDecoration(labelText: '주로 활동하는 지역', hintText: '예: 서울 성북구'),
          onChanged: (value) => communityRegion = value.trim(),
        ),
        SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: communityAgeBand,
          decoration: InputDecoration(labelText: '연령대'),
          items: ['', 'under20', '20s', '30s', '40plus'].map((value) => DropdownMenuItem(
            value: value,
            child: Text(value.isEmpty ? '선택 안 함' : _ageBandLabel(value)),
          )).toList(),
          onChanged: (value) => setState(() => communityAgeBand = value ?? ''),
        ),
        SizedBox(height: 8),
        Text(
          '정확한 생년월일이나 현재 위치는 저장하지 않아요. 지역의 대략적인 중심점과 연령대만 추천에 사용해요.',
          style: TextStyle(color: muted, fontSize: 12, height: 1.45),
        ),
      ])),
      SizedBox(height: 14),
      Text(
        '로그인 없이 바로 시작해요. 사진과 문서는 행사 정보를 읽기 위해 서버를 거쳐 OpenAI로 전송돼요. '
        '앱을 지우면 Cue 기록은 되찾을 수 없지만 캘린더에 저장한 일정은 남아요. '
        '테마, 알림, 저장할 캘린더는 설정에서 바꿀 수 있어요.',
        style: TextStyle(color: muted, fontSize: 13, height: 1.5),
      ),
      SizedBox(height: 20),
      _button('시작하기', Icons.arrow_forward, _finishOnboarding),
    ],
  );

  Widget _home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(height: 8),
      _tag('사진 한 장 → 일정 하나'),
      SizedBox(height: 16),
      Text(
        '행사 안내를\n캘린더에 저장하세요',
        style: TextStyle(
          fontSize: 34,
          height: 1.15,
          fontWeight: FontWeight.w900,
          color: ink,
          letterSpacing: -1,
        ),
      ),
      SizedBox(height: 13),
      Text(
        '확인한 일정만 캘린더에 저장돼요.',
        style: TextStyle(fontSize: 15, height: 1.55, color: muted),
      ),
      SizedBox(height: 24),
      if (stage == ScanStage.idle) _captureCard(),
      if (stage == ScanStage.processing) _progressCard(),
      if (stage == ScanStage.notEvent) _notEventCard(),
      if (stage == ScanStage.pastEvent) _pastEventCard(),
      if (stage == ScanStage.review) _reviewCard(),
      if (stage == ScanStage.saved) _savedCard(),
      if (stage == ScanStage.idle) ...[
        SizedBox(height: 18),
        _upcomingSection(),
      ],
      SizedBox(height: 22),
    ],
  );

  // 같은 위치·시각의 날씨는 화면을 다시 그려도 한 번만 묻는다.
  final _weatherRequests = <String, Future<CueWeather?>>{};

  Future<CueWeather?> _weather(double latitude, double longitude, [DateTime? at]) {
    final hour = at == null ? null : DateTime.utc(at.toUtc().year, at.toUtc().month, at.toUtc().day, at.toUtc().hour);
    final key = '${latitude.toStringAsFixed(2)},${longitude.toStringAsFixed(2)},${hour?.toIso8601String() ?? 'now'}';
    return _weatherRequests.putIfAbsent(key, () async {
      try {
        final when = hour == null ? '' : '&at=${Uri.encodeQueryComponent(at!.toUtc().toIso8601String())}';
        return CueWeather.fromJson(await api.get('/v1/weather?lat=$latitude&lng=$longitude$when'));
      } catch (_) {
        _weatherRequests.remove(key);
        return null;
      }
    });
  }

  // 스캔 탭 아래: 다음 일정의 지도·날씨·길찾기. 일정이 없으면 활동 지역의 오늘 날씨.
  Widget _upcomingSection() {
    final now = DateTime.now();
    final upcoming = saved.where((event) {
      final end = DateTime.tryParse(event['endsAt'] as String? ?? '');
      return end != null && end.toLocal().isAfter(now);
    }).toList()
      ..sort((a, b) => (a['startsAt'] as String).compareTo(b['startsAt'] as String));
    if (upcoming.isEmpty) {
      return CueTodayCard(
        region: communityRegion.isEmpty ? '내 지역' : communityRegion,
        weather: regionLatitude == null || regionLongitude == null ? null : _weather(regionLatitude!, regionLongitude!),
        onUseLocation: locating ? null : () => _useCurrentLocation(),
      );
    }
    final next = upcoming.first;
    final latitude = (next['locationLatitude'] as num?)?.toDouble();
    final longitude = (next['locationLongitude'] as num?)?.toDouble();
    final start = DateTime.parse(next['startsAt'] as String).toLocal();
    return CueUpcomingCard(
      event: next,
      now: now,
      moreCount: upcoming.length - 1,
      weather: latitude == null || longitude == null ? null : _weather(latitude, longitude, start),
      onOpenMap: () => _showOnMap([next], title: next['title'] as String? ?? '다가오는 일정'),
      onDirections: latitude == null || longitude == null ? null
          : () => _showOnMap([next], title: next['title'] as String? ?? '다가오는 일정', directions: true),
      onOpenSchedule: () => _selectTab(1),
    );
  }

  Widget _captureCard() => Container(
    padding: EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: colors.heroGradient,
      borderRadius: BorderRadius.circular(26),
      boxShadow: isDark ? null : [BoxShadow(
        color: colors.hero.withValues(alpha: 0.28), blurRadius: 30, offset: Offset(0, 14))],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.file(
              image!,
              height: 145,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          SizedBox(height: 12),
          _button('이 사진 다시 분석', Icons.refresh, _analyze, light: true),
          SizedBox(height: 18),
        ],
        if (document != null) ...[
          Row(
            children: [
              Icon(Icons.description_outlined, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  document!.name,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          _button('이 문서 다시 분석', Icons.refresh, _analyze, light: true),
          SizedBox(height: 18),
        ],
        Text(
          '무엇을 일정으로 바꿀까요?',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 7),
        Text(
          '포스터를 찍거나 가지고 있는 문서를 선택하세요.',
          style: TextStyle(color: colors.heroMuted),
        ),
        SizedBox(height: 23),
        _button(
          '포스터 촬영하기',
          Icons.camera_alt_outlined,
          () => _pick(ImageSource.camera),
          light: true,
        ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _button(
                '사진첩',
                Icons.photo_library_outlined,
                () => _pick(ImageSource.gallery),
                outlined: true,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _button(
                'PDF·한글',
                Icons.upload_file_outlined,
                _pickDocument,
                outlined: true,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _progressCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (image != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(17),
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
                  fontWeight: FontWeight.w800,
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
            fontWeight: FontWeight.w800,
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
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: ink),
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
        Row(children: [
          Text('${reviewStep + 1} / 4', style: TextStyle(color: accent, fontWeight: FontWeight.w900)),
          SizedBox(width: 12),
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: (reviewStep + 1) / 4,
              minHeight: 7,
              backgroundColor: mint,
              color: accent,
            ),
          )),
        ]),
        SizedBox(height: 14),
        Text(labels[reviewStep], style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: ink)),
        SizedBox(height: 5),
        Text('AI가 읽은 내용을 한 단계씩 확인해 주세요.', style: TextStyle(color: muted)),
        SizedBox(height: 20),
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
            Expanded(child: OutlinedButton.icon(
              onPressed: () => _setReviewStep(reviewStep - 1),
              icon: Icon(Icons.arrow_back_rounded),
              label: Text('이전'),
              style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(54)),
            )),
            SizedBox(width: 10),
          ],
          Expanded(
            flex: reviewStep > 0 ? 2 : 1,
            child: FilledButton.icon(
              onPressed: saving ? null : reviewStep == 3 ? _save : _nextReviewStep,
              icon: Icon(reviewStep == 3 ? Icons.event_available_rounded : Icons.arrow_forward_rounded),
              label: Text(reviewStep == 3
                  ? (saving ? '저장하는 중...' : '캘린더에 저장')
                  : '다음'),
              style: FilledButton.styleFrom(minimumSize: Size.fromHeight(54)),
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
      Container(
        width: 54, height: 54,
        decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(18)),
        child: Icon(Icons.celebration_rounded, color: accent),
      ),
      SizedBox(height: 18),
      TextField(
        controller: titleController,
        maxLength: 120,
        autofocus: false,
        decoration: InputDecoration(labelText: '행사 이름', hintText: '포스터에 적힌 행사 이름'),
      ),
      if (event.description.isNotEmpty) ...[
        SizedBox(height: 8),
        Text(event.description, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: muted, height: 1.5)),
      ],
    ],
  ));

  Widget _reviewCategoryPage() => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('가장 가까운 종류를 선택하세요',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)),
      SizedBox(height: 4),
      Text('선택한 종류는 추천 정확도에 반영돼요.', style: TextStyle(color: muted, fontSize: 13)),
      SizedBox(height: 18),
      for (final group in cueCategoryGroups.entries) ...[
        Text(group.key, style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w800)),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final value in group.value) ChoiceChip(
            label: Text(value),
            selected: selectedCategory == value,
            showCheckmark: false,
            avatar: selectedCategory == value ? Icon(Icons.check_rounded, size: 16, color: accent) : null,
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
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)),
        SizedBox(height: 12),
        for (var i = 0; i < event.sessions.length; i++) _sessionChoice(i, event.sessions[i]),
        SizedBox(height: 8),
      ],
      if (event.period != null) ...[
        _periodSummary(event.period!),
        SizedBox(height: 12),
      ],
      TextField(
        controller: venueController,
        onChanged: (_) => setState(() => venueConfirmed = false),
        decoration: InputDecoration(
          labelText: '장소',
          hintText: '예: 한국대학교 서울캠퍼스 본관 3층 시청각실',
          prefixIcon: Icon(Icons.place_outlined),
          suffixIcon: IconButton(
            onPressed: _findPlace,
            icon: Icon(Icons.map_outlined, color: accent),
            tooltip: '지도에서 찾기',
          ),
        ),
      ),
      if (_pickedPlace case final place?) ...[
        SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.verified_outlined, size: 17, color: accent),
          SizedBox(width: 7),
          Expanded(child: Text(
            [if (place.address.isNotEmpty) place.address, if (place.category.isNotEmpty) place.category].join(' · '),
            style: TextStyle(color: muted, fontSize: 13, height: 1.4))),
        ]),
      ] else if (venueController.text.trim().isNotEmpty) ...[
        SizedBox(height: 6),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: _findPlace,
          icon: Icon(Icons.map_outlined, size: 17),
          label: Text('지도에서 정확한 장소 고르기'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
        )),
      ],
      if (_pickedPlace == null && confirmLocalVenues && !venueConfirmed && cueVenueNeedsContext(venueController.text)) ...[
        SizedBox(height: 9),
        Container(
          padding: EdgeInsets.all(13),
          decoration: BoxDecoration(color: colors.warnTint,
              borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.location_searching_outlined, size: 19, color: colors.warn),
            SizedBox(width: 9),
            Expanded(child: Text('교내 장소로 보여요. 학교·캠퍼스·건물명까지 적으면 나중에 찾기 쉬워요.',
                style: TextStyle(color: colors.warn, fontSize: 13, height: 1.45))),
          ]),
        ),
      ],
      SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: event.period != null ? _planPeriodVisit
            : () => _editSchedule(ambiguous: event.sessions.isEmpty && startsAt == null),
        icon: Icon(Icons.schedule_rounded),
        label: Text(startsAt == null
            ? (event.period != null ? '방문 날짜·시간 정하기' : '날짜와 시간 선택')
            : _date(startsAt!)),
        style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(54), foregroundColor: accent),
      ),

    ],
  ));

  Widget _reviewReminderPage() => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('언제 알려드릴까요?',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: ink)),
      SizedBox(height: 14),
      for (final option in [15, 60, 1440, -1]) Padding(
        padding: EdgeInsets.only(bottom: 9),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => reminderMinutes = option),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            decoration: BoxDecoration(
              color: reminderMinutes == option ? mint : paper,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: reminderMinutes == option ? accent : borderColor),
            ),
            child: Row(children: [
              Icon(reminderMinutes == option ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: reminderMinutes == option ? accent : muted),
              SizedBox(width: 11),
              Text(_reminderLabel(option), style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
      Divider(color: borderColor, height: 28),
      InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => showUnknownInputs = !showUnknownInputs),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.tune_rounded, color: accent),
            SizedBox(width: 10),
            Expanded(child: Text('신청 마감일·참가비', style: TextStyle(color: ink, fontWeight: FontWeight.w700))),
            Icon(showUnknownInputs ? Icons.expand_less : Icons.expand_more, color: muted),
          ]),
        ),
      ),
      if (showUnknownInputs) ...[
        SizedBox(height: 12),
        TextField(controller: deadlineController,
            decoration: InputDecoration(labelText: '신청 마감일 (YYYY-MM-DD)'), keyboardType: TextInputType.datetime),
        SizedBox(height: 9),
        TextField(controller: feeController, decoration: InputDecoration(labelText: '참가비')),
      ],
    ],
  ));

  void _setReviewStep(int value) => setState(() {
    reviewDirection = value > reviewStep ? 1 : -1;
    reviewStep = value.clamp(0, 3);
  });

  Future<void> _nextReviewStep() async {
    if (reviewStep == 0 && titleController.text.trim().isEmpty) {
      _message('행사 이름을 확인해 주세요.');
      return;
    }
    if (reviewStep == 2) {
      if (candidate!.period != null && startsAt == null) {
        _message('방문할 날짜와 시간을 정해 주세요.');
        unawaited(_planPeriodVisit());
        return;
      }
      if (candidate!.sessions.length > 1 && selectedSession == null) {
        _message('참석할 시간과 장소를 선택해 주세요.');
        return;
      }
      if (venueController.text.trim().isEmpty || startsAt == null || endsAt == null) {
        _message('장소와 시간을 확인해 주세요.');
        return;
      }
      if (!await _confirmVenueContext()) return;
    }
    _setReviewStep(reviewStep + 1);
  }

  CuePlace? get _pickedPlace =>
      selectedPlace != null && selectedPlace!.name == venueController.text.trim() ? selectedPlace : null;

  Future<({bool enabled, List<CuePlace> places})> _searchPlaces(String query) async {
    final near = regionLatitude == null || regionLongitude == null ? '' : '&lat=$regionLatitude&lng=$regionLongitude';
    final result = await api.get('/v1/places?q=${Uri.encodeQueryComponent(query)}$near');
    return (
      enabled: result['enabled'] as bool? ?? false,
      places: (result['places'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(CuePlace.fromJson)
          .whereType<CuePlace>()
          .toList(),
    );
  }

  Future<void> _findPlace() async {
    final picked = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SafeArea(child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: CuePlaceSearchSheet(initialQuery: venueController.text.trim(), search: _searchPlaces),
          ),
        )),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (picked is CuePlace) {
        selectedPlace = picked;
        venueController.text = picked.name;
        // 지도에서 확인한 장소는 교내 장소 확인을 다시 묻지 않는다.
        venueConfirmed = true;
      } else if (picked is String) {
        selectedPlace = null;
        venueController.text = picked;
        venueConfirmed = false;
      }
    });
  }

  Widget _periodSummary(CuePeriod period) {
    final hours = cueHoursSummary(period);
    Widget line(IconData icon, String text) => Padding(
      padding: EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: accent),
        SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: ink, height: 1.4))),
      ]),
    );
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('기간 안에 자유롭게 방문하는 행사예요',
            style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
        line(Icons.date_range_outlined, '${cuePeriodRange(period)} · ${period.lengthDays}일간'),
        line(Icons.schedule_outlined, hours.isEmpty ? '운영 시간은 안내문에 없어요' : hours),
        if (period.closedWeekdays.isNotEmpty)
          line(Icons.block_outlined, '휴관 ${cueWeekdayRange(period.closedWeekdays)}요일'),
        line(Icons.timelapse_outlined, '보통 ${period.visitMinutes}분 정도 머물러요'),
      ]),
    );
  }

  // 기간형 행사는 운영 시간 전체가 아니라 실제로 머물 방문 시간만 캘린더에 넣는다.
  // 기간 동안의 내 일정을 한 번에 읽어 빈 날과 겹치는 시간을 함께 보여준다.
  Future<void> _planPeriodVisit() async {
    final period = candidate?.period;
    if (period == null || !mounted) return;
    final now = DateTime.now();
    final from = period.startDate.isAfter(now) ? period.startDate : DateTime(now.year, now.month, now.day);
    final limit = from.add(Duration(days: 180));
    final until = (period.endDate.isBefore(limit) ? period.endDate : limit).add(Duration(days: 1));
    var busy = <CueScheduleItem>[];
    try {
      final permission = await calendarPlugin.requestPermissions();
      if (permission.data == true) {
        final list = await calendarPlugin.retrieveCalendars();
        final calendars = list.data?.where((item) => item.id != null).toList() ?? [];
        busy = (await _readSchedules(calendars, from, until)).map((row) => row.item).toList();
      }
    } catch (_) {
      // 캘린더를 읽지 못해도 날짜와 시간은 고를 수 있다.
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<CueTimeSlot>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: CuePeriodPlanner(
              period: period,
              busy: busy,
              now: now,
              initial: startsAt == null || endsAt == null ? null : CueTimeSlot(startsAt!, endsAt!),
              onConfirm: (slot) => Navigator.pop(sheetContext, slot),
            ),
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      startsAt = picked.start;
      endsAt = picked.end;
      selectedSession = null;
    });
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
                        fontWeight: FontWeight.w800,
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
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selectedSession == index ? mint : paper,
          border: Border.all(
            color: selectedSession == index ? accent : borderColor,
            width: selectedSession == index ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(15),
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
                    style: TextStyle(fontWeight: FontWeight.w800, color: ink),
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
              fontWeight: FontWeight.w800,
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
                color: warn ? colors.warnTint : mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${dayLabel(day.date)} · 일정 ${day.stops.length}곳',
                      style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
                  SizedBox(height: 4),
                  Text(note, style: TextStyle(
                    color: warn ? colors.warn : muted,
                    fontSize: 13,
                  )),
                ],
              ),
            ),
          ],
          if (routePlanNote?.isNotEmpty == true) ...[
            SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.route_outlined, color: accent),
                SizedBox(width: 10),
                Expanded(child: Text(routePlanNote!, style: TextStyle(color: ink, height: 1.5))),
              ]),
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
            child: _pageTitle('내 일정', routeView ? '하루 동선으로 보는 일정' : '확인하고 저장한 행사'),
          ),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, icon: Icon(Icons.route_outlined), tooltip: '노선'),
              ButtonSegment(value: false, icon: Icon(Icons.view_agenda_outlined), tooltip: '목록'),
            ],
            selected: {routeView},
            onSelectionChanged: (value) => setState(() => routeView = value.first),
          ),
        ],
      ),
      SizedBox(height: 22),
      if (saved.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: sharingEvent ? null : _manageShares,
            icon: Icon(Icons.people_outline),
            label: Text('행사 공유 관리 (실험)'),
          ),
        ),
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
          onShowMap: (events, day) => _showOnMap(events, title: '${day.month}월 ${day.day}일 동선', route: true),
        )
      else
        for (final event in _byDate(saved)) ...[
          _eventTile(event),
          SizedBox(height: 11),
        ],
    ],
  );

  // 추천 탭은 서버가 붙인 묶음(section) 순서로 보여준다. 예전 서버는 묶음이 없으므로 맞춤 추천으로 본다.
  static const _recommendationSections = [
    ('fits', '이번 주 비어 있는 시간에', '내 캘린더가 비어 있는 시간에 열리는 행사예요.'),
    ('sameDay', '저장한 일정 근처', '같은 날 가까운 곳에서 열려 함께 들르기 좋아요.'),
    ('peers', '비슷한 사람들이 저장한 행사', '나와 학교·연령대·지역·관심 분야가 비슷한 사람들이 일정에 넣었어요.'),
    ('local', '내 지역 행사·축제', '활동 지역 가까이에서 열려요. 축제를 먼저 보여드려요.'),
    ('nearby', '내 주변에서 공유된 행사', '가까운 곳·같은 연령대 사람들이 직접 찾아 공유했어요.'),
    ('interest', '관심 분야 행사·축제', '가까운 곳이 아니어도 관심 분야에 맞는 전국 행사예요.'),
    ('explore', '이런 행사는 어때요?', '관심 분야 밖이지만 가깝고 곧 열리는 행사예요.'),
  ];

  // 추천 기준 위치를 한 줄로 보여준다. 위치를 쓰지 않으면 현재 위치를 쓰자고 권한다.
  Widget _locationBar() {
    final hasRegion = regionLatitude != null && communityRegion.isNotEmpty;
    final ageHint = communityAgeBand.isEmpty ? ' · 연령대를 정하면 또래가 공유한 행사가 먼저 나와요' : ' · ${_ageBandLabel(communityAgeBand)}';
    return Container(
      padding: EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        Icon(useDeviceLocation ? Icons.my_location : Icons.near_me_outlined, color: accent, size: 20),
        SizedBox(width: 10),
        Expanded(child: Text(
          hasRegion ? '$communityRegion 기준$ageHint' : '현재 위치를 쓰면 내 주변에서 공유된 행사를 먼저 보여드려요.',
          style: TextStyle(color: ink, fontSize: 13, height: 1.4))),
        if (locating)
          Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
        else
          TextButton(
            onPressed: () => _useCurrentLocation(),
            child: Text(useDeviceLocation ? '새로고침' : '현재 위치 사용'),
          ),
      ]),
    );
  }

  Widget _discover() {
    final sections = <String, List<Map<String, dynamic>>>{};
    for (final event in recommended) {
      sections.putIfAbsent(event['section'] as String? ?? 'interest', () => []).add(event);
    }
    final noCommunity = communitySchool.isEmpty && communityRegion.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 새 추천은 화면을 아래로 당겨 받는다(_scroll의 RefreshIndicator).
        GestureDetector(
          onTap: _editTopics,
          // 직접 고른 분야를 먼저, 저장 기록에서 배운 분야를 뒤에 보여준다.
          child: _pageTitle('추천 행사', interestLabels.isEmpty && favoriteTopics.isEmpty
              ? '저장한 행사로 취향을 배워요 · 당기면 새로 찾아요'
              : '${{...favoriteTopics, ...interestLabels}.take(3).join('·')}에 관심이 많아요'),
        ),
        SizedBox(height: 12),
        _locationBar(),
        if (favoriteTopics.isEmpty && interestLabels.isEmpty) ...[
          SizedBox(height: 10),
          _card(Row(children: [
            Icon(Icons.interests_outlined, color: accent),
            SizedBox(width: 12),
            Expanded(child: Text('관심 분야를 고르면 바로 맞춤 추천을 받을 수 있어요.',
                style: TextStyle(color: ink, height: 1.45))),
            TextButton(onPressed: _editTopics, child: Text('고르기')),
          ])),
        ],
        SizedBox(height: 16),
        if (recommendationLoading && recommended.isEmpty)
          _empty(Icons.search, '행사를 찾고 있어요', '새 행사를 찾을 때는 1분 정도 걸릴 수 있어요.')
        else if (recommendationError != null && recommended.isEmpty)
          _card(Column(children: [
            Icon(Icons.cloud_off_outlined, color: muted, size: 30),
            SizedBox(height: 10),
            Text('추천을 불러오지 못했어요', style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 16)),
            SizedBox(height: 5),
            Text(recommendationError!, textAlign: TextAlign.center, style: TextStyle(color: muted, height: 1.45)),
            SizedBox(height: 12),
            OutlinedButton(onPressed: () => _refresh(), child: Text('다시 시도')),
          ]))
        else if (recommended.isEmpty)
          _empty(Icons.explore_outlined, '아직 보여드릴 행사가 없어요',
              '포스터를 하나 저장하면 비슷한 행사를 찾아드려요. 화면을 아래로 당기면 다시 찾아요.'),
        for (final (key, title, defaultSubtitle) in _recommendationSections)
          if (sections[key]?.isNotEmpty == true) ...[
            Padding(
              padding: EdgeInsets.only(top: 6, bottom: 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text(key == 'explore' && interestLabels.isEmpty
                    ? '가깝고 곧 열리는 행사부터 보여드려요. 저장할수록 취향에 맞춰져요.'
                    : defaultSubtitle, style: TextStyle(color: muted, fontSize: 13)),
              ]),
            ),
            for (final event in sections[key]!) ...[
              _eventTile(event, recommended: true),
              SizedBox(height: 11),
            ],
            SizedBox(height: 12),
          ],
        TextButton.icon(
          onPressed: _editCommunity,
          icon: Icon(Icons.tune),
          label: Text(noCommunity ? '학교·지역·연령대 설정' : '학교·지역·연령대 바꾸기'),
        ),
      ],
    );
  }

  Widget _settings() {
    final section = settingsSection;
    final page = section != null
      ? PopScope<Object?>(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) setState(() => settingsSection = null);
        },
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => settingsSection = null),
              icon: Icon(Icons.arrow_back),
              label: Text('설정으로'),
            ),
          ),
          _pageTitle(section, switch (section) {
            '캘린더와 알림' => '새 일정을 저장할 때 적용할 기본값',
            '일정 에이전트' => '중복·충돌·불분명한 장소를 저장 전에 확인',
            '화면 테마' => '편안하게 볼 수 있는 화면',
            '지도 앱' => '장소와 길찾기를 열 앱',
            '추천' => '관심사 기록과 행사 추천 관리',
            _ => '데이터 처리와 익명 계정 안내',
          }),
          SizedBox(height: 20),
          ..._settingsContent(section),
        ],
        ),
      )
      : Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageTitle('설정', '내 Cue를 편하게 맞춰보세요'),
        SizedBox(height: 18),
        InkWell(
          onTap: () => setState(() => settingsSection = '내 데이터'),
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: EdgeInsets.all(17),
            decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(18)),
                child: Icon(Icons.check_rounded, color: Colors.white, size: 28),
              ),
              SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('내 Cue', style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 3),
                Text(cloudConnected ? '클라우드에 연결됨' : '연결 상태 확인 필요',
                    style: TextStyle(color: cloudConnected ? colors.success : muted, fontSize: 13)),
              ])),
              Icon(Icons.chevron_right, color: muted),
            ]),
          ),
        ),
        SizedBox(height: 24),
        _settingsGroup('일정', [
          _settingsEntry(Icons.calendar_month_outlined, '캘린더와 알림',
              '$preferredCalendarName · ${_reminderLabel(defaultReminderMinutes)}'),
          _settingsEntry(Icons.auto_fix_high_outlined, '일정 에이전트',
              '중복·충돌·교내 장소 확인'),
        ]),
        SizedBox(height: 22),
        _settingsGroup('개인화', [
          _settingsEntry(Icons.auto_awesome_outlined, '추천',
              personalizationEnabled && recommendationEnabled ? '관심사 기반 추천 사용 중' : '추천 꺼짐'),
        ]),
        SizedBox(height: 22),
        _settingsGroup('앱', [
          _settingsEntry(Icons.palette_outlined, '화면 테마',
              switch (cueThemeMode.value) {
                ThemeMode.system => '시스템 설정 따르기',
                ThemeMode.light => '라이트',
                ThemeMode.dark => '다크',
              }),
          _settingsEntry(Icons.map_outlined, '지도 앱',
              CueMapAppLabel.parse(mapAppPreference)?.label ?? '처음 열 때 고르기'),
          _settingsEntry(Icons.shield_outlined, '내 데이터', '사진 처리 안내 · 계정과 기록'),
        ]),
      ],
    );
    return AnimatedSwitcher(
      duration: Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(begin: Offset(section == null ? -0.04 : 0.04, 0), end: Offset.zero)
              .animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(section ?? 'settings-home'), child: page),
    );
  }

  Widget _settingsGroup(String label, List<Widget> entries) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: EdgeInsets.only(left: 4, bottom: 9),
        child: Text(label, style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w700)),
      ),
      Container(
        decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (var index = 0; index < entries.length; index++) ...[
            entries[index],
            if (index + 1 < entries.length)
              Divider(color: borderColor, height: 1, indent: 66),
          ],
        ]),
      ),
    ],
  );

  Widget _settingsEntry(IconData icon, String title, String summary) => ListTile(
    contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 7),
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: mint, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: accent, size: 20),
    ),
    title: Text(title),
    subtitle: Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
    trailing: Icon(Icons.chevron_right, color: muted),
    onTap: () => setState(() => settingsSection = title),
  );

  Future<void> _setAgentPreference(String key, bool value) async {
    setState(() {
      if (key == 'prevent_duplicate_events') preventDuplicateEvents = value;
      if (key == 'check_schedule_conflicts') checkScheduleConflicts = value;
      if (key == 'confirm_local_venues') confirmLocalVenues = value;
    });
    await (await SharedPreferences.getInstance()).setBool(key, value);
  }

  List<Widget> _settingsContent(String section) => switch (section) {
    '지도 앱' => [
      _card(FutureBuilder<List<CueMapApp>>(
        future: cueInstalledMapApps(),
        builder: (context, snapshot) {
          final apps = snapshot.data ?? const <CueMapApp>[];
          final current = CueMapAppLabel.parse(mapAppPreference);
          Widget option(CueMapApp? app, String label, String? note) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(current == app ? Icons.radio_button_checked : Icons.radio_button_off,
                color: current == app ? accent : muted),
            title: Text(label),
            subtitle: note == null ? null : Text(note),
            onTap: () => _setMapApp(app),
          );
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            option(null, '처음 열 때 고르기', '설치된 지도 앱 중에서 물어봐요.'),
            for (final app in apps)
              option(app, app.label, app == CueMapApp.web ? '앱 없이 카카오맵 웹으로 열어요.' : null),
            if (snapshot.connectionState == ConnectionState.done && !apps.contains(CueMapApp.kakao))
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('카카오맵·네이버 지도 앱을 설치하면 여기에 나타나요.', style: TextStyle(color: muted, fontSize: 13)),
              ),
          ]);
        },
      )),
    ],
    '캘린더와 알림' => [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _eyebrow('캘린더와 알림'),
            SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.calendar_month_outlined, color: accent),
              title: Text('저장할 캘린더'),
              subtitle: Text(preferredCalendarName),
              trailing: Icon(Icons.chevron_right, color: muted),
              onTap: _chooseCalendar,
            ),
            Divider(color: borderColor),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.notifications_outlined, color: accent),
              title: Text('기본 알림'),
              subtitle: Text('새 행사에 먼저 적용돼요'),
              trailing: DropdownButton<int>(
                value: defaultReminderMinutes,
                underline: SizedBox.shrink(),
                items: [15, 60, 1440, -1]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(_reminderLabel(value)),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() {
                    defaultReminderMinutes = value;
                    reminderMinutes = value;
                  });
                  await (await SharedPreferences.getInstance()).setInt(
                    'default_reminder_minutes',
                    value,
                  );
                },
              ),
            ),
            Divider(color: borderColor),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.timelapse_outlined, color: accent),
              title: Text('기본 일정 길이'),
              subtitle: Text('종료 시간이 없는 행사에 적용돼요'),
              trailing: DropdownButton<int>(
                value: defaultDurationMinutes,
                underline: SizedBox.shrink(),
                items: [60, 120, 180]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('${value ~/ 60}시간'),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() => defaultDurationMinutes = value);
                  await (await SharedPreferences.getInstance()).setInt(
                    'default_duration_minutes',
                    value,
                  );
                },
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 14),
    ],
    '일정 에이전트' => [
      _card(Column(children: [
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.content_copy_outlined, color: accent),
          title: Text('중복 행사 확인'),
          subtitle: Text('같은 행사·시간·장소를 다시 찍으면 저장 전에 알려줘요.'),
          value: preventDuplicateEvents,
          onChanged: (value) => _setAgentPreference('prevent_duplicate_events', value),
        ),
        Divider(color: borderColor),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.alt_route_rounded, color: accent),
          title: Text('시간 충돌 확인'),
          subtitle: Text('기기 캘린더와 겹치면 빈 시간 후보를 보여줘요.'),
          value: checkScheduleConflicts,
          onChanged: (value) => _setAgentPreference('check_schedule_conflicts', value),
        ),
        Divider(color: borderColor),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          secondary: Icon(Icons.location_searching_outlined, color: accent),
          title: Text('교내 장소 확인'),
          subtitle: Text('학교·캠퍼스·건물 정보가 부족하면 직접 확인해요.'),
          value: confirmLocalVenues,
          onChanged: (value) => _setAgentPreference('confirm_local_venues', value),
        ),
      ])),
      SizedBox(height: 12),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: Text('행사 시간은 고정일 수 있어 자동으로 바꾸지 않아요. '
            '빈 시간을 제안한 뒤 항상 확인을 받아요.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.5)),
      ),
      SizedBox(height: 14),
    ],
    '화면 테마' => [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _eyebrow('화면 테마'),
            SizedBox(height: 14),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text('시스템')),
                ButtonSegment(value: ThemeMode.light, label: Text('라이트')),
                ButtonSegment(value: ThemeMode.dark, label: Text('다크')),
              ],
              selected: {cueThemeMode.value},
              onSelectionChanged: (value) async {
                cueThemeMode.value = value.first;
                await (await SharedPreferences.getInstance()).setString(
                  'theme_mode',
                  value.first.name,
                );
              },
            ),
          ],
        ),
      ),
      SizedBox(height: 14),
    ],
    '추천' => [
      _card(ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.interests_outlined, color: accent),
        title: Text('관심 있는 분야'),
        subtitle: Text(favoriteTopics.isEmpty ? '고르지 않음 · 저장한 행사로만 배워요' : favoriteTopics.join(' · ')),
        trailing: Icon(Icons.chevron_right, color: muted),
        onTap: _editTopics,
      )),
      SizedBox(height: 14),
      _card(ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(Icons.people_outline, color: accent),
        title: Text('내 추천 환경 (실험)'),
        subtitle: Text([communitySchool, communityRegion, _ageBandLabel(communityAgeBand)]
            .where((value) => value.isNotEmpty).join(' · ').isEmpty
                ? '학교·활동 지역·연령대 선택'
                : [communitySchool, communityRegion, _ageBandLabel(communityAgeBand)]
                    .where((value) => value.isNotEmpty).join(' · ')),
        trailing: Icon(Icons.chevron_right, color: muted),
        onTap: _editCommunity,
      )),
      SizedBox(height: 14),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _eyebrow('개인화와 추천'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('관심사 기반 추천'),
              subtitle: Text('끄면 추천을 위한 선택 기록을 사용하지 않아요.'),
              value: personalizationEnabled,
              onChanged: (value) =>
                  _updateProfile({'personalizationEnabled': value}),
            ),
            Divider(color: borderColor),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text('행사 추천 표시'),
              subtitle: Text('추천 행사 화면에 표시할지 정해요.'),
              value: recommendationEnabled,
              onChanged: personalizationEnabled
                  ? (value) => _updateProfile({'recommendationEnabled': value})
                  : null,
            ),
          ],
        ),
      ),
      SizedBox(height: 14),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _eyebrow('관심사 기록'),
            SizedBox(height: 8),
            Text(
              '관심 표시와 추천 기록, Cue가 파악한 관심사를 모두 지워요. 저장한 일정은 그대로 남아요.',
              style: TextStyle(color: muted, height: 1.5),
            ),
            SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _resetInterests,
              icon: Icon(Icons.delete_sweep_outlined),
              label: Text('내 관심사 기록 초기화'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
                side: BorderSide(color: colors.danger),
                minimumSize: Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 14),
    ],
    '내 데이터' => [
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '사진과 일정 데이터',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '사진과 문서는 행사 정보를 읽기 위해 서버를 거쳐 OpenAI로 전송돼요. 행사 안내물이 아니면 더 분석하지 않아요.',
              style: TextStyle(color: muted, height: 1.5),
            ),
          ],
        ),
      ),
      SizedBox(height: 14),
      _card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _eyebrow('내 기록'),
            SizedBox(height: 8),
            Text(
              userId == null
                  ? '아직 서버에 연결되지 않았어요. 연결되면 일정과 관심사가 기록돼요.'
                  : '로그인 없이 쓰는 익명 계정에 일정과 관심사가 기록되고 있어요.',
              style: TextStyle(color: ink, height: 1.5),
            ),
            SizedBox(height: 6),
            Text(
              '앱을 지우거나 기기를 바꾸면 Cue 기록은 되찾을 수 없어요. 기기 캘린더에 저장한 일정은 그대로 남아요.',
              style: TextStyle(color: muted, fontSize: 13, height: 1.5),
            ),
            SizedBox(height: 6),
            InkWell(
              onTap: () => setState(() => showDeveloperInfo = !showDeveloperInfo),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Text('개발자 정보', style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w700)),
                  Icon(showDeveloperInfo ? Icons.expand_less : Icons.expand_more, size: 18, color: muted),
                ]),
              ),
            ),
            if (showDeveloperInfo)
              SelectableText(
                [
                  '서버  $cueApiUrl',
                  '클라우드 저장소  ${cloudConnected ? '연결됨' : '연결 안 됨'}',
                  if (userId != null) '사용자 ID  $userId',
                  if (apiErrorDetail != null) '마지막 오류  $apiErrorDetail',
                ].join('\n'),
                style: TextStyle(color: muted, fontSize: 12, height: 1.5),
              ),
          ],
        ),
      ),
      SizedBox(height: 14),
      TextButton.icon(onPressed: _refresh, icon: Icon(Icons.refresh), label: Text('연결 다시 확인')),
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
            style: FilledButton.styleFrom(backgroundColor: colors.danger, foregroundColor: Colors.white),
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

  CueMapTarget _mapTarget(Map<String, dynamic> event) {
    final place = event['place'] as Map<String, dynamic>?;
    return CueMapTarget(
      name: event['venue'] as String? ?? '',
      latitude: (event['locationLatitude'] as num?)?.toDouble(),
      longitude: (event['locationLongitude'] as num?)?.toDouble(),
      kakaoPlaceId: place?['provider'] == 'kakao' ? (place?['id'] as String?) : null,
    );
  }

  Future<void> _openMap(Map<String, dynamic> event, {bool directions = false}) {
    _noteOpened(event, directions ? 'directions' : 'map');
    return _openInMap(_mapTarget(event), directions: directions);
  }

  // 추천받은 행사의 지도·길찾기·원 안내를 열면 약한 관심으로 기록한다. 실패해도 조용히 넘어간다.
  void _noteOpened(Map<String, dynamic> event, String kind) {
    final id = event['id'];
    if (id == null || !recommended.any((item) => item['id'] == id)) return;
    unawaited(api.post('/v1/interactions', {'eventId': id, 'action': 'recommendation_opened', 'kind': kind})
        .then((_) {}, onError: (_) {}));
  }

  // 위치를 아는 일정은 앱 안 지도(iOS)로 보여준다. 지도를 띄울 수 없으면 지도 앱으로 연다.
  Future<void> _showOnMap(List<Map<String, dynamic>> events,
      {required String title, bool route = false, int initial = 0, bool directions = false}) async {
    if (events.isNotEmpty) _noteOpened(events[initial.clamp(0, events.length - 1)], directions ? 'directions' : 'map');
    final stops = events.map(CueMapStop.from).whereType<CueMapStop>().toList();
    if (!CueMapView.supported || stops.isEmpty) {
      if (events.isNotEmpty) await _openMap(events[initial.clamp(0, events.length - 1)], directions: directions);
      return;
    }
    final start = events[initial.clamp(0, events.length - 1)];
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CueMapPage(
      title: title,
      stops: stops,
      route: route,
      startWithDirections: directions,
      initial: stops.indexWhere((stop) => identical(stop.event, start)).clamp(0, stops.length - 1),
      onDirections: (stop) => _openMap(stop.event, directions: true),
      onOpenExternal: (stop) => _openMap(stop.event),
      weatherFor: (stop) => stop.start == null
          ? Future.value(null)
          : _weather(stop.latitude, stop.longitude, stop.start),
    )));
  }

  // 설치된 지도 앱으로 바로 연다. 처음 한 번만 앱을 고르고, 고른 앱은 설정에서 바꿀 수 있다.
  Future<void> _openInMap(CueMapTarget target, {bool directions = false}) async {
    final installed = await cueInstalledMapApps();
    var app = CueMapAppLabel.parse(mapAppPreference);
    if (app == null || !installed.contains(app)) {
      final apps = installed.where((item) => item != CueMapApp.web).toList();
      if (apps.isEmpty) {
        app = CueMapApp.web;
      } else {
        if (!mounted) return;
        app = await showModalBottomSheet<CueMapApp>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(child: Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('어떤 지도로 열까요?', style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('고른 앱으로 계속 열어요. 설정 → 지도 앱에서 바꿀 수 있어요.', style: TextStyle(color: muted, fontSize: 13)),
              SizedBox(height: 10),
              for (final item in apps)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.map_outlined, color: accent),
                  title: Text(item.label),
                  trailing: Icon(Icons.chevron_right, color: muted),
                  onTap: () => Navigator.pop(sheetContext, item),
                ),
            ]),
          )),
        );
        if (app == null) return;
        await _setMapApp(app);
      }
    }
    if (!await cueLaunchMap(app, target, directions: directions)) _message('지도를 열지 못했어요.');
  }

  Future<void> _setMapApp(CueMapApp? app) async {
    final prefs = await SharedPreferences.getInstance();
    if (app == null) {
      await prefs.remove('cue_map_app');
    } else {
      await prefs.setString('cue_map_app', app.name);
    }
    if (mounted) setState(() => mapAppPreference = app?.name);
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
          CueEventIdentity(
            title: event['title'] as String? ?? '',
            venue: event['venue'] as String? ?? '',
            category: event['category'] as String? ?? '기타',
            startsAt: date,
            sourceKind: recommended ? event['originKind'] as String? ?? 'catalog' : null,
            participationFee: event['participationFee'] as String?,
            tags: (event['tags'] as List<dynamic>? ?? []).whereType<String>().toList(),
            placeDetail: event['place'] is Map<String, dynamic>
                ? [
                    (event['place'] as Map<String, dynamic>)['address'] as String? ?? '',
                    (event['place'] as Map<String, dynamic>)['category'] as String? ?? '',
                  ].where((part) => part.isNotEmpty).join(' · ')
                : null,
            onOpenMap: (event['venue'] as String? ?? '').trim().isEmpty ? null
                : () => _showOnMap([event], title: event['venue'] as String? ?? '장소'),
          ),
          // 둘러보기 묶음은 머리말이 이유를 설명하므로 카드마다 같은 문장을 반복하지 않는다.
          if (recommended && event['section'] != 'explore' &&
              event['reason'] is String && (event['reason'] as String).trim().isNotEmpty) ...[
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(event['originKind'] == 'shared' ? Icons.people_outline : Icons.auto_awesome,
                    size: 15, color: muted),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event['reason'] as String,
                    style: TextStyle(color: muted, fontSize: 12, height: 1.5),
                  ),
                ),
              ],
            ),
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
                    icon: Icon(Icons.event_available_outlined),
                    label: Text('일정에 추가'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary,
                      minimumSize: Size.fromHeight(48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: TextStyle(fontWeight: FontWeight.w800),
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
                  tooltip: '행사 더보기',
                  icon: Icon(Icons.more_horiz, color: muted),
                  onPressed: () async {
                    final value = await _recommendationActions(event, hasSource: sourceUrl != null);
                    if (value == 'dismiss') {
                      await _dismissRecommendation(event);
                    } else if (value == 'source' && sourceUrl != null) {
                      _noteOpened(event, 'source');
                      final url = Uri.tryParse(sourceUrl);
                      if (url == null || !await launchUrl(url, mode: LaunchMode.externalApplication)) {
                        _message('원 안내 페이지를 열 수 없어요.');
                      }
                    }
                  },
                ),
              ],
            ),
        ],
      ),
    );
  }

  // 추천 카드의 더보기. 아래에서 올라오는 시트에 항목이 차례로 떠오른다. 고른 항목의 값을 돌려준다.
  Future<String?> _recommendationActions(Map<String, dynamic> event, {required bool hasSource}) {
    final actions = [
      ('dismiss', Icons.visibility_off_outlined, '관심 없음', '이런 행사는 덜 보여드릴게요'),
      if (hasSource) ('source', Icons.open_in_new_rounded, '원 안내 보기', '주최 측 안내 페이지를 열어요'),
    ];
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      sheetAnimationStyle: AnimationStyle(
        duration: Duration(milliseconds: 380),
        reverseDuration: Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 14),
              child: Text(event['title'] as String? ?? '행사',
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontSize: 17, fontWeight: FontWeight.w800, height: 1.35)),
            ),
            for (final (index, (value, icon, title, subtitle)) in actions.indexed)
              _staggered(index, Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Material(
                  color: colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.pop(sheetContext, value),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: colors.tint, shape: BoxShape.circle),
                          child: Icon(icon, size: 19, color: colors.accentText),
                        ),
                        SizedBox(width: 13),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(title, style: TextStyle(color: ink, fontSize: 15.5, fontWeight: FontWeight.w800)),
                          SizedBox(height: 3),
                          Text(subtitle, style: TextStyle(color: muted, fontSize: 13)),
                        ])),
                        Icon(Icons.chevron_right_rounded, color: muted),
                      ]),
                    ),
                  ),
                ),
              )),
            _staggered(actions.length, TextButton(
              onPressed: () => Navigator.pop(sheetContext),
              style: TextButton.styleFrom(minimumSize: Size.fromHeight(46), foregroundColor: muted),
              child: Text('닫기', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      ),
    );
  }

  // 시트 안의 항목이 순서대로 살짝 올라오며 나타나게 한다.
  Widget _staggered(int index, Widget child) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 360 + index * 70),
    curve: Interval(index * 70 / (360 + index * 70), 1, curve: Curves.easeOutCubic),
    builder: (_, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: child),
    ),
    child: child,
  );

  String _ageBandLabel(String value) => switch (value) {
    'under20' => '20세 미만', '20s' => '20대', '30s' => '30대', '40plus' => '40세 이상', _ => '',
  };

  // 현재 위치를 동네 이름과 약 1km 단위 좌표로 바꿔 활동 지역에 저장한다.
  // silent면 권한을 묻지 않고, 실패해도 알리지 않으며 추천을 다시 불러오지 않는다(새로고침 중에 호출).
  Future<void> _useCurrentLocation({bool silent = false}) async {
    if (locating) return;
    setState(() => locating = true);
    try {
      final point = await locator.current(ask: !silent);
      if (point == null) {
        if (silent || !mounted) return;
        final deniedForever = await locator.deniedForever();
        if (!mounted) return;
        if (deniedForever) {
          final open = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
            title: Text('위치 권한이 꺼져 있어요'),
            content: Text('설정에서 Cue의 위치 접근을 "앱을 사용하는 동안"으로 바꾸면 내 주변 행사를 볼 수 있어요.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('나중에')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('설정 열기')),
            ],
          ));
          if (open == true) await locator.openSettings();
        } else {
          _message('현재 위치를 확인하지 못했어요. 위치 서비스를 켜고 다시 시도해 주세요.');
        }
        return;
      }
      String? region;
      try {
        final result = await api.get('/v1/places/region?lat=${point.latitude}&lng=${point.longitude}');
        region = result['region'] as String?;
      } catch (_) {
        // 지역 이름을 못 찾아도 좌표만으로 거리 추천은 된다.
      }
      double coarse(double value) => (value * 100).round() / 100;
      await api.patch('/v1/profile', {
        'region': region ?? '현재 위치 주변',
        'regionLatitude': coarse(point.latitude),
        'regionLongitude': coarse(point.longitude),
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cue_use_device_location', true);
      await prefs.setString('cue_device_location_at', DateTime.now().toIso8601String());
      if (!mounted) return;
      setState(() {
        useDeviceLocation = true;
        communityRegion = region ?? '현재 위치 주변';
        regionLatitude = coarse(point.latitude);
        regionLongitude = coarse(point.longitude);
      });
      if (!silent) {
        _message('${region ?? '현재 위치'} 주변 행사로 추천할게요.');
        await _refresh();
      }
    } catch (error) {
      if (!silent) _error(error);
    } finally {
      if (mounted) setState(() => locating = false);
    }
  }

  Future<void> _stopDeviceLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cue_use_device_location', false);
    if (mounted) setState(() => useDeviceLocation = false);
    _message('현재 위치 갱신을 껐어요. 활동 지역은 직접 바꿀 수 있어요.');
  }

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
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: () => Navigator.pop(context, <String, dynamic>{'useLocation': true,
              'school': school, 'ageBand': ageBand}),
            icon: Icon(Icons.my_location, size: 18),
            label: Text('현재 위치로 설정'),
          )),
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
    if (result != null && result['useLocation'] == true && mounted) {
      try {
        await api.patch('/v1/profile', {'school': result['school'], 'ageBand': result['ageBand']});
      } catch (_) {
        // 학교·연령대 저장이 실패해도 위치 설정은 계속한다.
      }
      await _useCurrentLocation();
      return;
    }
    if (result != null && mounted) {
      // 지역을 직접 적었으면 기기 위치로 덮어쓰지 않는다.
      if (useDeviceLocation && result['region'] != communityRegion) await _stopDeviceLocation();
      final point = await travelEstimator.geocode(result['region'] as String? ?? '');
      if (point != null) {
        result['regionLatitude'] = point.latitude;
        result['regionLongitude'] = point.longitude;
      }
      await _updateProfile(result);
    }
  }

  Future<void> _manageShares() async {
    final event = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.65,
        child: Column(children: [
          Padding(padding: EdgeInsets.all(20), child: Text('내가 발견한 행사 공유',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
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
            '${event['place'] is Map ? '장소: 지도에서 확인한 장소라 이름과 주소를 함께 공개해요.\n\n' : '장소: 지도에서 확인하지 않은 장소라 이름만 공개하고 위치는 약 1km 범위로만 써요.\n\n'}'
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
        for (final choice in ['관심 없는 분야', '시간 안 맞음', '장소가 멂', '비쌈', '참가 조건 안 맞음', '이미 알고 있는 행사'])
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

  Widget _pageTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: ink),
      ),
      SizedBox(height: 5),
      Text(subtitle, style: TextStyle(color: muted)),
    ],
  );
  Widget _empty(IconData icon, String title, String text) => _card(
    Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            Icon(icon, size: 44, color: accent),
            SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
            SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: muted),
            ),
          ],
        ),
      ),
    ),
  );
  Widget _notice(String text, {VoidCallback? onTap, String? detail}) => Container(
    padding: EdgeInsets.fromLTRB(13, 10, 8, 10),
    decoration: BoxDecoration(
      color: colors.tint,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: colors.accent.withValues(alpha: 0.18)),
    ),
    child: Row(
      children: [
        Icon(Icons.info_outline, size: 20, color: accent),
        SizedBox(width: 7),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: ink)),
        ),
        if (detail != null && detail != text)
          TextButton(onPressed: () => _showDetail(detail), child: Text('자세히')),
        if (onTap != null)
          IconButton(
            onPressed: onTap,
            icon: Icon(Icons.refresh),
            tooltip: '다시 연결',
          ),
      ],
    ),
  );
  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(19),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: borderColor),
      boxShadow: isDark ? null : [BoxShadow(
        color: Colors.black.withValues(alpha: 0.035), blurRadius: 18, offset: Offset(0, 5))],
    ),
    child: child,
  );
  Widget _eyebrow(String value) => Text(
    value,
    style: TextStyle(
      fontSize: 12,
      letterSpacing: 0.7,
      color: accent,
      fontWeight: FontWeight.w900,
    ),
  );
  Widget _tag(String value) => Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: mint,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      value,
      style: TextStyle(
        color: accent,
        fontSize: 12,
        fontWeight: FontWeight.w700,
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
    height: 54,
    child: outlined
        ? OutlinedButton.icon(
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          )
        : FilledButton.icon(
            onPressed: onTap,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: light ? colors.heroAction : colors.primary,
              foregroundColor: light ? colors.onHeroAction : colors.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
  );
  String _date(DateTime value) => '${_dateOnly(value)} ${_timeOnly(value)}';
}
