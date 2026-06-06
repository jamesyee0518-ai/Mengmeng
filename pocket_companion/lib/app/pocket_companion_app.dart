import 'package:flutter/material.dart';

import '../features/face/face_page.dart';

class PocketCompanionApp extends StatelessWidget {
  const PocketCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF36D399),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF070A0D),
        useMaterial3: true,
      ),
      home: const FacePage(),
    );
  }
}
