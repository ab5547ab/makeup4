import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'screens/calendar_screen.dart';
import 'services/appointments_controller.dart';
import 'services/wifi_connection_controller.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MakeupCalendarApp());
}

class MakeupCalendarApp extends StatelessWidget {
  const MakeupCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppointmentsController()),
        // מנוהל ברמת האפליקציה כולה (ולא מסך ההגדרות) כדי שהחיבור
        // לרשת ה-Wi-Fi יישאר פעיל כל עוד האפליקציה פתוחה.
        ChangeNotifierProvider(create: (_) => WifiConnectionController()),
      ],
      child: MaterialApp(
        title: 'יומן עבודה וניהול תורים',
        debugShowCheckedModeBanner: false,
        theme: appTheme,
        locale: const Locale('he', 'IL'),
        supportedLocales: const [Locale('he', 'IL'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const CalendarScreen(),
      ),
    );
  }
}
