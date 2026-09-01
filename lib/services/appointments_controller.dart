import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/appointment.dart';
import 'github_sync_service.dart';
import 'storage_service.dart';

/// מצב הסנכרון מול קובץ ה-JSON ב-GitHub, לצורך הצגה בממשק.
enum SyncStatus {
  /// לא הוגדרו פרטי סנכרון (עדיין לא הוזנו טוקן/ריפו בהגדרות)
  notConfigured,

  /// מוגדר, אין פעולה פעילה כרגע
  idle,

  /// העלאה/הורדה מתבצעת כרגע ברקע
  syncing,

  /// הפעולה האחרונה הצליחה
  success,

  /// הפעולה האחרונה נכשלה (למשל אין אינטרנט)
  error,
}

/// המוח של האפליקציה: מחזיק את רשימת התורים בזיכרון, שומר לאחסון המקומי
/// בכל שינוי, ומודיע למסכים לרענן את עצמם. כאשר מוגדר סנכרון ל-GitHub,
/// כל הוספה/עריכה/מחיקה של תור מעלה אוטומטית ברקע עותק מעודכן של קובץ
/// ה-JSON, כדי שהגיבוי בענן תמיד יהיה תואם למה שרואים במכשיר.
class AppointmentsController extends ChangeNotifier {
  final StorageService _storage = StorageService();
  List<Appointment> _appointments = [];
  bool _isLoading = true;

  GitHubSyncService? _syncService;
  SyncStatus _syncStatus = SyncStatus.notConfigured;
  String? _syncError;
  DateTime? _lastSyncedAt;

  List<Appointment> get appointments => List.unmodifiable(_appointments);
  bool get isLoading => _isLoading;

  SyncStatus get syncStatus => _syncStatus;
  String? get syncError => _syncError;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  bool get isSyncConfigured => _syncService != null;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    _appointments = await _storage.loadAppointments();
    _appointments.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await _loadSyncSettings();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadSyncSettings() async {
    final settings = await _storage.loadSyncSettings();
    _buildSyncService(settings);
  }

  void _buildSyncService(Map<String, String> settings) {
    final token = settings['token'] ?? '';
    final owner = settings['owner'] ?? '';
    final repo = settings['repo'] ?? '';
    final path = settings['path'] ?? '';
    if (token.isEmpty || owner.isEmpty || repo.isEmpty || path.isEmpty) {
      _syncService = null;
      _syncStatus = SyncStatus.notConfigured;
    } else {
      _syncService = GitHubSyncService(
        token: token,
        owner: owner,
        repo: repo,
        path: path,
      );
      _syncStatus = SyncStatus.idle;
    }
    _syncError = null;
  }

  /// נקרא ממסך ההגדרות מיד לאחר שמירת פרטי הסנכרון, כדי שהסנכרון
  /// האוטומטי יתחיל לפעול בלי צורך להפעיל מחדש את האפליקציה.
  void applySyncSettings({
    required String token,
    required String owner,
    required String repo,
    required String path,
  }) {
    _buildSyncService({
      'token': token,
      'owner': owner,
      'repo': repo,
      'path': path,
    });
    notifyListeners();
  }

  List<Appointment> forDay(DateTime day) {
    return _appointments
        .where((a) =>
            a.dateTime.year == day.year &&
            a.dateTime.month == day.month &&
            a.dateTime.day == day.day)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  /// מפת ימים עם תורים - משמש להצגת נקודות על הלוח שנה
  Set<DateTime> get daysWithAppointments => _appointments
      .map((a) => DateTime(a.dateTime.year, a.dateTime.month, a.dateTime.day))
      .toSet();

  double totalForMonth(DateTime month) {
    return _appointments
        .where((a) =>
            a.dateTime.year == month.year &&
            a.dateTime.month == month.month &&
            a.status != AppointmentStatus.cancelled)
        .fold(0.0, (sum, a) => sum + a.price);
  }

  int countForMonth(DateTime month) {
    return _appointments
        .where((a) =>
            a.dateTime.year == month.year && a.dateTime.month == month.month)
        .length;
  }

  Future<void> add(Appointment appointment) async {
    _appointments.add(appointment);
    _appointments.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
    await _storage.saveAppointments(_appointments);
    unawaited(_syncUpload());
  }

  Future<void> update(Appointment appointment) async {
    final index = _appointments.indexWhere((a) => a.id == appointment.id);
    if (index == -1) return;
    _appointments[index] = appointment;
    _appointments.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
    await _storage.saveAppointments(_appointments);
    unawaited(_syncUpload());
  }

  Future<void> delete(String id) async {
    _appointments.removeWhere((a) => a.id == id);
    notifyListeners();
    await _storage.saveAppointments(_appointments);
    unawaited(_syncUpload());
  }

  /// מיזוג רשימת תורים שהתקבלה מסנכרון (GitHub) - לפי מזהה, האחרון מנצח
  Future<void> mergeFromRemote(List<Appointment> remote) async {
    final map = {for (final a in _appointments) a.id: a};
    for (final r in remote) {
      map[r.id] = r;
    }
    _appointments = map.values.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
    await _storage.saveAppointments(_appointments);
  }

  /// מעלה את המצב הנוכחי ל-GitHub ברקע, ללא חסימת המשתמש. נקרא אוטומטית
  /// לאחר כל הוספה/עריכה/מחיקה, בתנאי שהוגדר סנכרון בהגדרות.
  Future<void> _syncUpload() async {
    final service = _syncService;
    if (service == null) return;
    _syncStatus = SyncStatus.syncing;
    _syncError = null;
    notifyListeners();
    try {
      await service.uploadAppointments(_appointments);
      _syncStatus = SyncStatus.success;
      _lastSyncedAt = DateTime.now();
    } catch (e) {
      _syncStatus = SyncStatus.error;
      _syncError = e.toString();
    }
    notifyListeners();
  }

  /// רענון ידני (כפתור הרענון במסך הראשי): מוריד את הגרסה העדכנית
  /// מ-GitHub וממזג אותה עם הנתונים המקומיים. אם לא הוגדר סנכרון,
  /// טוען מחדש רק מהאחסון המקומי של המכשיר.
  Future<void> refresh() async {
    final service = _syncService;
    if (service == null) {
      await load();
      return;
    }
    _syncStatus = SyncStatus.syncing;
    _syncError = null;
    notifyListeners();
    try {
      final remote = await service.downloadAppointments();
      await mergeFromRemote(remote);
      _syncStatus = SyncStatus.success;
      _lastSyncedAt = DateTime.now();
    } catch (e) {
      _syncStatus = SyncStatus.error;
      _syncError = e.toString();
    }
    notifyListeners();
  }
}
