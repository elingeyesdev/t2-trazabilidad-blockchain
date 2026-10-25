import 'package:flutter/material.dart';

import 'screens/home/home_screen.dart';

class AgroFusionApp extends StatelessWidget {
  const AgroFusionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroFusion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10B981)),
      ),
      home: const HomeScreen(),
    );
  }
}
