import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('KBO Fans', style: Theme.of(context).textTheme.headlineMedium),
                  Row(
                    children: [
                      Text('3.28 토', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sports_baseball, size: 64, color: AppColors.divider),
                      const SizedBox(height: 16),
                      Text('스코어보드 구현 예정', style: TextStyle(fontSize: 16, color: AppColors.textDisabled)),
                      const SizedBox(height: 8),
                      Text('백엔드 API 연동 후 실시간 경기 데이터 표시', style: TextStyle(fontSize: 12, color: AppColors.textDisabled)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
