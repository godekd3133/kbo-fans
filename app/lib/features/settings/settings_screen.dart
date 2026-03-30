import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text('설정 화면 구현 예정', style: TextStyle(color: AppColors.textDisabled)),
        ),
      ),
    );
  }
}
