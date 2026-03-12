import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthSproutApp());
}

class HealthSproutApp extends StatelessWidget {
  const HealthSproutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:          'Health Sprout',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor:   const Color(0xFF2E7D32),
          brightness:  Brightness.light,
        ),
        useMaterial3: true,
        fontFamily:   'Roboto',
        cardTheme:    const CardThemeData(
          elevation: 2,
          margin:    EdgeInsets.zero,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
