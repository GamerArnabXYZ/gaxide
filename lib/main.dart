import 'package:flutter/material.dart';
import 'screens/file_manager_screen.dart';
import 'services/theme_controller.dart';
import 'utils/app_theme.dart';

void main() {
  runApp(const GaxIdeApp());
}

class GaxIdeApp extends StatefulWidget {
  const GaxIdeApp({super.key});

  @override
  State<GaxIdeApp> createState() => _GaxIdeAppState();
}

class _GaxIdeAppState extends State<GaxIdeApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds the whole app the instant a theme/font is changed in
    // Settings — no restart needed.
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'GAX IDE',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.themeFor(ThemeController.instance.themeOption, ThemeController.instance.uiFont),
          home: const FileManagerScreen(),
        );
      },
    );
  }
}
