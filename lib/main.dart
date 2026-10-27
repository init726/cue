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
import 'cue_route.dart';
import 'cue_splash.dart';
import 'saved_event_editor.dart';

const ink = Color(0xFF181A1D);
const muted = Color(0xFF697078);
const paper = Color(0xFFF7F8FA);
const accent = Color(0xFF169ED3);
const mint = Color(0xFFE8F7FD);
final cueThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);
const cueApiUrl = String.fromEnvironment(
  'CUE_API_URL',
  defaultValue: 'http://localhost:8787',
);

ThemeData cueTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? const Color(0xFF101214) : paper;
  final surface = dark ? const Color(0xFF1A1D20) : Colors.white;
  final foreground = dark ? const Color(0xFFF4F5F6) : ink;
  final blue = dark ? const Color(0xFF55C7F3) : accent;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: blue,
      brightness: brightness,
      surface: surface,
    ),
    dividerColor: dark ? const Color(0xFF303438) : const Color(0xFFE8EBEE),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: surface,
      indicatorColor: dark ? const Color(0xFF29343A) : mint,
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
        fontSize: 11,
        fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
        color: states.contains(WidgetState.selected) ? blue : (dark ? const Color(0xFFA9AFB5) : muted),
      )),
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        size: 23,
        color: states.contains(WidgetState.selected) ? blue : (dark ? const Color(0xFFA9AFB5) : muted),
      )),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
      minimumSize: const Size(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontWeight: FontWeight.w800),
    )),
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
  Color get ink => isDark ? Color(0xFFF4F5F6) : Color(0xFF181A1D);
  Color get muted => isDark ? Color(0xFFA9AFB5) : Color(0xFF697078);
  Color get paper => isDark ? Color(0xFF101214) : Color(0xFFF7F8FA);
  Color get accent => isDark ? Color(0xFF55C7F3) : Color(0xFF169ED3);
  Color get mint => isDark ? Color(0xFF25343A) : Color(0xFFE8F7FD);
  Color get surface => isDark ? Color(0xFF1A1D20) : Colors.white;
  Color get borderColor => isDark ? Color(0xFF303438) : Color(0xFFE7EAED);
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
        titleController.text = event.title;
        selectedCategory = event.category;
        deadlineController.text = event.applicationDeadline == null ? '' : event.applicationDeadline!.substring(0, 10);
        feeController.text = event.participationFee ?? '';
        showUnknownInputs = false;
        selectedSession = event.sessions.length == 1 ? 0 : null;
        _applySession(selectedSession);
      });
      // 시간·장소가 여러 개면 별도 선택창으로 바로 고르게 한다.
      if (event.sessions.length > 1) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _chooseSession());
      } else if (event.sessions.isEmpty) {
        // 날짜나 장소가 분명하지 않으면 입력 후 바로 직접 고르는 시트를 띄운다.
        WidgetsBinding.instance.addPostFrameCallback((_) => _requireSchedule());
      }
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
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  margin: EdgeInsets.only(bottom: 9),
                  decoration: BoxDecoration(
                    border: Border.all(color: borderColor),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(children: [
                    Icon(icon, color: accent, size: 22),
                    SizedBox(width: 12),
                    Expanded(child: Text(label, style: TextStyle(color: muted))),
                    Text(value, style: TextStyle(color: ink, fontWeight: FontWeight.w800, fontSize: 16)),
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

  // 날짜가 불분명하면 창을 강제로 띄워 선택을 받는다. 취소하면 이 안내물 분석을 접는다.
  Future<void> _requireSchedule() async {
    final done = await _editSchedule(ambiguous: true, forced: true);
    if (!done && mounted) _reset();
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
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
            Expanded(
              child: IndexedStack(
                index: tab,
                children: [
                  _scroll(_home()),
                  _scroll(_saved(), onRefresh: _refresh),
                  _scroll(_discover(), onRefresh: () => _refresh(shuffle: true)),
                  _scroll(_settings()),
                ],
              ),
            ),
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
            onDestinationSelected: (value) => setState(() => tab = value),
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
      physics: onRefresh == null ? null : AlwaysScrollableScrollPhysics(),
      child: Padding(padding: EdgeInsets.fromLTRB(20, 20, 20, 32), child: child),
    );
    return onRefresh == null
        ? view
        : RefreshIndicator(color: accent, onRefresh: onRefresh, child: view);
  }
  Widget _header() => Padding(
    padding: EdgeInsets.fromLTRB(22, 14, 22, 8),
    child: Row(
      children: [
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            color: accent,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.camera_alt_rounded,
              color: isDark ? Color(0xFF101214) : Colors.white, size: 19),
        ),
        SizedBox(width: 11),
        Text(
          'cue',
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.w900,
            color: ink,
            letterSpacing: -1.5,
          ),
        ),
      ],
    ),
  );

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
      SizedBox(height: 22),
    ],
  );

  Widget _captureCard() => Container(
    padding: EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [Color(0xFF202326), Color(0xFF181A1D)]
            : [Color(0xFF20A9DD), Color(0xFF118CC3)],
      ),
      borderRadius: BorderRadius.circular(26),
      border: isDark ? Border.all(color: Color(0xFF34383C)) : null,
      boxShadow: isDark ? null : [BoxShadow(
        color: accent.withValues(alpha: 0.2), blurRadius: 28, offset: Offset(0, 12))],
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
          style: TextStyle(color: isDark ? Color(0xFFB7BCC1) : Color(0xFFE8F8FF)),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: mint,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: accent),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  fromRecommendation
                      ? '추천 행사를 일정에 추가해요. 확인하고 저장해 주세요.'
                      : '읽어낸 일정이에요. 저장 전에 확인해 주세요.',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 18),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow('01  행사 정보'),
              SizedBox(height: 14),
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: '행사 이름',
                  prefixIcon: Icon(Icons.celebration_outlined),
                ),
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('${event.title}-$selectedCategory'),
                initialValue: selectedCategory,
                decoration: InputDecoration(
                  labelText: '행사 종류',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: cueCategories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedCategory = value);
                },
              ),
              if (event.description.isNotEmpty) ...[
                SizedBox(height: 12),
                Text(event.description, maxLines: 3, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted)),
              ],
            ],
          ),
        ),
        SizedBox(height: 14),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow('02  시간과 장소'),
              SizedBox(height: 8),
              if (event.sessions.length > 1) ...[
                Text('한 가지를 선택해야 계속할 수 있어요. 아래에서 바꿀 수도 있어요.', style: TextStyle(color: muted)),
                SizedBox(height: 13),
                for (var i = 0; i < event.sessions.length; i++)
                  _sessionChoice(i, event.sessions[i]),
              ] else if (event.sessions.isEmpty) ...[
                Text(
                  '시간 또는 장소가 불명확해요. 아래에서 직접 골라 주세요.',
                  style: TextStyle(color: muted),
                ),
                SizedBox(height: 12),
              ],
              TextField(
                controller: venueController,
                decoration: InputDecoration(
                  labelText: '장소',
                  prefixIcon: Icon(Icons.place_outlined),
                ),
              ),
              SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _editSchedule(ambiguous: event.sessions.isEmpty && startsAt == null),
                icon: Icon(Icons.schedule),
                label: Text(startsAt == null ? '날짜와 시간 선택' : _date(startsAt!)),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size.fromHeight(52),
                  foregroundColor: accent,
                ),
              ),
              if (startsAt != null) ...[
                SizedBox(height: 7),
                Text(
                  '종료: ${_date(endsAt!)} · 필요하면 캘린더에서 수정할 수 있어요.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 14),
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _eyebrow('03  알림'),
              SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final option in [15, 60, 1440, -1])
                    ChoiceChip(
                      label: Text(_reminderLabel(option)),
                      selected: reminderMinutes == option,
                      onSelected: (_) =>
                          setState(() => reminderMinutes = option),
                    ),
                ],
              ),
              Divider(color: borderColor, height: 28),
              // 신청 마감일·참가비는 안내문에 없는 경우가 많아 기본으로 접어 둔다.
              InkWell(
                onTap: () => setState(() => showUnknownInputs = !showUnknownInputs),
                child: Row(
                  children: [
                    Icon(Icons.post_add_outlined, size: 20, color: muted),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if (deadlineController.text.trim().isNotEmpty) '마감 ${deadlineController.text.trim()}',
                          if (feeController.text.trim().isNotEmpty) feeController.text.trim(),
                        ].join(' · ').ifEmpty('신청 마감일·참가비 추가 (선택)'),
                        style: TextStyle(color: muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Icon(showUnknownInputs ? Icons.expand_less : Icons.expand_more, color: muted),
                  ],
                ),
              ),
              if (showUnknownInputs) ...[
                SizedBox(height: 12),
                TextField(
                  controller: deadlineController,
                  decoration: InputDecoration(labelText: '신청 마감일 (YYYY-MM-DD)'),
                  keyboardType: TextInputType.datetime,
                  onChanged: (_) => setState(() {}),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: feeController,
                  decoration: InputDecoration(labelText: '참가비 (예: 무료, 10,000원)'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ],
          ),
        ),
        SizedBox(height: 18),
        _button(
          saving ? '캘린더에 저장하는 중...' : '확인하고 캘린더에 저장',
          Icons.event_available_outlined,
          saving ? null : _save,
        ),
        SizedBox(height: 10),
        Center(
          child: fromRecommendation
              ? TextButton(
                  onPressed: () {
                    _reset();
                    setState(() => tab = 2);
                  },
                  child: Text('추천으로 돌아가기'),
                )
              : TextButton(onPressed: _reset, child: Text('다시 스캔하기')),
        ),
      ],
    );
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
                color: warn ? (isDark ? Color(0xFF3A2A17) : Color(0xFFFFF1E2)) : mint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${dayLabel(day.date)} · 일정 ${day.stops.length}곳',
                      style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
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
                if (backToRecommendations) setState(() => tab = 2);
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
    ],
  );

  Widget _discover() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageTitle('추천 행사', '관심 분야와 가까운 행사'),
      SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: recommendationLoading ? null : () => _refresh(shuffle: true),
          icon: Icon(Icons.shuffle, size: 18),
          label: Text('다른 행사 보기'),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ),
      SizedBox(height: 6),
      if (recommendationLoading && recommended.isEmpty)
        _empty(Icons.search, '관련 행사 확인 중', '행사 정보를 확인하고 있어요.'),
      if (!recommendationLoading && recommended.isEmpty)
        _empty(
          Icons.explore_outlined,
          '아직 추천할 행사가 없어요',
          '행사 포스터를 저장하면 관심 분야에 맞는 행사를 찾아드려요. 아래로 당겨서 새로고침할 수도 있어요.',
        ),
      for (final event in recommended) ...[
        _eventTile(event, recommended: true),
        SizedBox(height: 11),
      ],
    ],
  );

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _pageTitle('설정', '캘린더와 추천 설정'),
      SizedBox(height: 20),
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
      SizedBox(height: 12),
      Center(
        child: TextButton.icon(
          onPressed: _refresh,
          icon: Icon(Icons.refresh),
          label: Text('일정 및 추천 새로고침'),
        ),
      ),
      SizedBox(height: 18),
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
                foregroundColor: Color(0xFFE5484D),
                side: BorderSide(color: Color(0xFFE5484D)),
                minimumSize: Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
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
    ],
  );

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
          _tag(event['category'] as String? ?? '기타'),
          SizedBox(height: 11),
          Text(
            event['title'] as String? ?? '',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          SizedBox(height: 10),
          if (date != null) _detail(Icons.schedule, _date(date)),
          _detail(Icons.place_outlined, event['venue'] as String? ?? ''),
          if (recommended && event['reason'] is String) ...[
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, size: 15, color: accent),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    event['reason'] as String,
                    style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600),
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
                      backgroundColor: accent,
                      foregroundColor: isDark ? Color(0xFF101214) : Colors.white,
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
      fromRecommendation = true;
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
      color: isDark ? Color(0xFF20282C) : Color(0xFFEAF8FD),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: isDark ? Color(0xFF304047) : Color(0xFFD6EEF8)),
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
              side: BorderSide(color: Color(0xFFD8EEFC)),
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
              backgroundColor: light ? Color(0xFFF3FBFF) : accent,
              foregroundColor: light
                  ? Color(0xFF126E93)
                  : (isDark ? Color(0xFF101214) : Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              textStyle: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
  );
  String _date(DateTime value) => '${_dateOnly(value)} ${_timeOnly(value)}';
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
