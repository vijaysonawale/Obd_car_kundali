// lib/main.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:upgrader/upgrader.dart';
import 'services/ad_manager.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdManager.instance.initialize(); // ← init AdMob before runApp
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    const home = HomeScreen();

    return MaterialApp(
      title: 'Car Kundali',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Platform.isAndroid
          ? UpgradeAlert(
              barrierDismissible: false,
              showIgnore: false,
              showLater: false,
              shouldPopScope: () => false,
              upgrader: Upgrader(durationUntilAlertAgain: Duration.zero),
              child: home,
            )
          : home,
    );
  }
}
