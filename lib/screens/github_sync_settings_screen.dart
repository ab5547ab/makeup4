import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/appointments_controller.dart';
import '../services/github_sync_service.dart';
import '../services/storage_service.dart';
import '../widgets/section_card.dart';

/// מסך הגדרות סנכרון ל-GitHub בלבד (גיבוי/שחזור קובץ JSON).
/// מנותק לחלוטין מהגדרות חיבור ה-Wi-Fi, שנמצאות במסך נפרד.
class GithubSyncSettingsScreen extends StatefulWidget {
  const GithubSyncSettingsScreen({super.key});

  @override
  State<GithubSyncSettingsScreen> createState() =>
      _GithubSyncSettingsScreenState();
}

class _GithubSyncSettingsScreenState extends State<GithubSyncSettingsScreen> {
  final _storage = StorageService();

  final _tokenCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _pathCtrl = TextEditingController(text: 'appointments_backup.json');

  bool _isUploading = false;
  bool _isDownloading = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _storage.loadSyncSettings();
    if (!mounted) return;
    setState(() {
      _tokenCtrl.text = settings['token'] ?? '';
      _ownerCtrl.text = settings['owner'] ?? '';
      _repoCtrl.text = settings['repo'] ?? '';
      _pathCtrl.text = settings['path'] ?? 'appointments_backup.json';
    });
  }

  Future<void> _persistSettings() async {
    await _storage.saveSyncSettings(
      token: _tokenCtrl.text.trim(),
      owner: _ownerCtrl.text.trim(),
      repo: _repoCtrl.text.trim(),
      path: _pathCtrl.text.trim(),
    );
    if (!mounted) return;
    context.read<AppointmentsController>().applySyncSettings(
          token: _tokenCtrl.text.trim(),
          owner: _ownerCtrl.text.trim(),
          repo: _repoCtrl.text.trim(),
          path: _pathCtrl.text.trim(),
        );
  }

  GitHubSyncService? _buildService() {
    if (_tokenCtrl.text.trim().isEmpty ||
        _ownerCtrl.text.trim().isEmpty ||
        _repoCtrl.text.trim().isEmpty ||
        _pathCtrl.text.trim().isEmpty) {
      _showSnack('נא למלא את כל שדות הסנכרון (טוקן, בעלים, ריפו, נתיב)');
      return null;
    }
    return GitHubSyncService(
      token: _tokenCtrl.text.trim(),
      owner: _ownerCtrl.text.trim(),
      repo: _repoCtrl.text.trim(),
      path: _pathCtrl.text.trim(),
    );
  }

  Future<void> _upload() async {
    final service = _buildService();
    if (service == null) return;
    await _persistSettings();

    setState(() => _isUploading = true);
    try {
      final appointments = context.read<AppointmentsController>().appointments;
      await service.uploadAppointments(appointments);
      _showSnack('הגיבוי הועלה בהצלחה ל-GitHub ✓');
    } catch (e) {
      _showSnack('שגיאה בגיבוי: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _download() async {
    final service = _buildService();
    if (service == null) return;
    await _persistSettings();

    setState(() => _isDownloading = true);
    try {
      final remote = await service.downloadAppointments();
      if (!mounted) return;
      await context.read<AppointmentsController>().mergeFromRemote(remote);
      _showSnack('שוחזרו ${remote.length} תורים מ-GitHub ✓');
    } catch (e) {
      _showSnack('שגיאה בשחזור: $e');
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _ownerCtrl.dispose();
    _repoCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // שמירה אוטומטית של ההגדרות ביציאה מהמסך, כדי שהסנכרון האוטומטי
        // יפעל גם אם המשתמש לא לחץ במפורש על גיבוי/שחזור.
        if (_tokenCtrl.text.trim().isNotEmpty &&
            _ownerCtrl.text.trim().isNotEmpty &&
            _repoCtrl.text.trim().isNotEmpty &&
            _pathCtrl.text.trim().isNotEmpty) {
          await _persistSettings();
        }
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('סנכרון ל-GitHub')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'גיבוי ושחזור ב-GitHub',
              icon: Icons.cloud_sync_outlined,
              children: [
                const Text(
                  'שומר עותק של כל התורים בקובץ JSON בריפו פרטי משלכם. '
                  'מומלץ להשתמש בריפו Private ובטוקן עם הרשאת repo בלבד. '
                  'בכל הוספה, עריכה או מחיקה של תור, קובץ ה-JSON מתעדכן '
                  'אוטומטית ברקע.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenCtrl,
                  obscureText: _obscureToken,
                  decoration: InputDecoration(
                    labelText: 'Personal Access Token',
                    suffixIcon: IconButton(
                      icon: Icon(_obscureToken
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _ownerCtrl,
                  decoration:
                      const InputDecoration(labelText: 'בעל הריפו (Username)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _repoCtrl,
                  decoration: const InputDecoration(labelText: 'שם הריפו'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pathCtrl,
                  decoration:
                      const InputDecoration(labelText: 'נתיב קובץ הגיבוי'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isDownloading ? null : _download,
                        icon: _isDownloading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.cloud_download_outlined),
                        label: const Text('שחזור'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isUploading ? null : _upload,
                        icon: _isUploading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.cloud_upload_outlined),
                        label: const Text('גיבוי כעת'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
