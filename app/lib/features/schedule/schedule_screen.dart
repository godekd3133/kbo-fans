import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text('일정 화면 구현 예정', style: TextStyle(color: AppColors.textDisabled)),
        ),
      ),
    );
  }
}
