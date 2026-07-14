import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

void main() {
  runApp(const JujenzaoApp());
}

class JujenzaoApp extends StatelessWidget {
  const JujenzaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '營建工程管理日報表',
      theme: buildAppTheme(),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
