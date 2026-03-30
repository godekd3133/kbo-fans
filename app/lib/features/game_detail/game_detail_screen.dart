import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class GameDetailScreen extends StatelessWidget {
  final String gameId;
  const GameDetailScreen({super.key, required this.gameId});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('경기 상세'),
          bottom: const TabBar(
            indicatorColor: AppColors.textPrimary,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textDisabled,
            tabs: [
              Tab(text: '스코어'),
              Tab(text: '문자중계'),
              Tab(text: '박스스코어'),
              Tab(text: '라인업'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            Center(child: Text('스코어 탭 구현 예정', style: TextStyle(color: AppColors.textDisabled))),
            Center(child: Text('문자중계 탭 구현 예정', style: TextStyle(color: AppColors.textDisabled))),
            Center(child: Text('박스스코어 탭 구현 예정', style: TextStyle(color: AppColors.textDisabled))),
            Center(child: Text('라인업 탭 구현 예정', style: TextStyle(color: AppColors.textDisabled))),
          ],
        ),
      ),
    );
  }
}
