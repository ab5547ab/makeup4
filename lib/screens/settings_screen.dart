import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/wifi_connection_controller.dart';
import 'github_sync_settings_screen.dart';
import 'wifi_settings_screen.dart';

/// מסך הגדרות ראשי - "רכזת" שמפנה לשני מסכי הגדרות נפרדים ועצמאיים:
/// סנכרון ל-GitHub, וחיבור לרשת Wi-Fi. שני הנושאים מנוהלים בנפרד לגמרי,
/// כדי שאפשר יהיה להגדיר/לשנות כל אחד מהם בלי להשפיע על השני.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _wifiSubtitle(WifiConnectionController wifi) {
    switch (wifi.status) {
      case WifiConnectionStatus.notConfigured:
        return 'לא מוגדר';
      case WifiConnectionStatus.disconnected:
        return 'מוגדר, לא מחובר כרגע';
      case WifiConnectionStatus.connecting:
        return 'מתחבר...';
      case WifiConnectionStatus.connected:
        return 'מחובר (${wifi.ssid ?? ''})';
      case WifiConnectionStatus.error:
        return 'שגיאת חיבור';
    }
  }

  @override
  Widget build(BuildContext context) {
    final wifi = context.watch<WifiConnectionController>();

    return Scaffold(
      appBar: AppBar(title: const Text('הגדרות')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('סנכרון ל-GitHub'),
              subtitle: const Text('גיבוי ושחזור אוטומטי של קובץ התורים'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const GithubSyncSettingsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: Icon(
                wifi.isConnected ? Icons.wifi : Icons.wifi_outlined,
                color: wifi.isConnected ? Colors.green.shade700 : null,
              ),
              title: const Text('חיבור לרשת Wi-Fi'),
              subtitle: Text(_wifiSubtitle(wifi)),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const WifiSettingsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
