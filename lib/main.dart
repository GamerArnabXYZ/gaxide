import 'package:flutter/material.dart';
import 'screens/file_manager_screen.dart';
import 'utils/app_theme.dart';

void main() {
  runApp(const GaxIdeApp());
}

class GaxIdeApp extends StatelessWidget {
  const GaxIdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAX IDE',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const FileManagerScreen(),
    );
  }
}
