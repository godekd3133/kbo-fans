import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Explanations describe the statistic, never an inferred player grade.
class BaseballMetricGuide {
  final String key;
  final String title;
  final String definition;
  final String formula;
  final String readingTip;
  final String? sourcePath;

  const BaseballMetricGuide({
    required this.key,
    required this.title,
    required this.definition,
    required this.formula,
    required this.readingTip,
    this.sourcePath,
  });
}

const baseballMetricGuides = [
  BaseballMetricGuide(
    key: 'AVG',
    title: '타율 · AVG',
    definition: '타수 중 안타의 비율입니다. 볼넷은 포함하지 않습니다.',
    formula: '안타 ÷ 타수',
    readingTip: '높을수록 안타 비율이 높아요. 타수와 OPS도 함께 보세요.',
    sourcePath: 'batting-average',
  ),
  BaseballMetricGuide(
    key: 'OPS',
    title: '출루·장타 · OPS',
    definition: '출루율과 장타율을 더해 공격 기록을 함께 보는 값입니다.',
    formula: '출루율 + 장타율',
    readingTip: '높을수록 좋아요. 수비·주루를 포함한 종합 실력 점수는 아닙니다.',
    sourcePath: 'on-base-plus-slugging',
  ),
  BaseballMetricGuide(
    key: 'ERA',
    title: '평균자책 · ERA',
    definition: '9이닝당 자책점을 나타냅니다.',
    formula: '자책점 × 9 ÷ 투구 이닝',
    readingTip: '낮을수록 자책점이 적어요. 투구 이닝과 WHIP를 함께 보세요.',
    sourcePath: 'earned-run-average',
  ),
  BaseballMetricGuide(
    key: 'WHIP',
    title: '이닝당 출루 허용 · WHIP',
    definition: '한 이닝에 볼넷과 안타를 얼마나 허용했는지 보여줍니다.',
    formula: '(볼넷 + 피안타) ÷ 투구 이닝',
    readingTip: '낮을수록 허용이 적어요. 몸에 맞는 공은 이 계산에 포함하지 않습니다.',
    sourcePath: 'walks-and-hits-per-inning-pitched',
  ),
  BaseballMetricGuide(
    key: 'HR',
    title: '홈런 · HR',
    definition: '시즌 동안 기록한 홈런의 개수입니다.',
    formula: '시즌 누적 기록',
    readingTip: '출전 기회가 다르면 누적값도 달라져요. 경기 수와 타수를 함께 보세요.',
    sourcePath: 'home-run',
  ),
  BaseballMetricGuide(
    key: 'W',
    title: '승리 · W',
    definition: '공식 기록에서 승리 투수로 인정된 횟수입니다.',
    formula: '시즌 누적 기록',
    readingTip: '팀 득점과 불펜의 영향도 있어요. ERA와 투구 이닝을 함께 보세요.',
    sourcePath: 'win',
  ),
  BaseballMetricGuide(
    key: 'SV',
    title: '세이브 · SV',
    definition: '세이브 요건을 충족하며 리드를 지킨 횟수입니다.',
    formula: '시즌 누적 기록',
    readingTip: '보직과 등판 기회가 달라질 수 있어요. ERA와 이닝도 함께 보세요.',
    sourcePath: 'save',
  ),
  BaseballMetricGuide(
    key: 'SO',
    title: '탈삼진 · SO',
    definition: '타자를 삼진으로 잡은 횟수입니다.',
    formula: '시즌 누적 기록',
    readingTip: '많이 던진 투수는 기회도 많아요. 투구 이닝을 함께 보세요.',
    sourcePath: 'strikeout',
  ),
  BaseballMetricGuide(
    key: 'OPSPLUS',
    title: 'OPS 상대지수',
    definition: '이 화면에 포함된 OPS 선수 평균을 100으로 놓은 앱 계산값입니다.',
    formula: '선수 OPS ÷ 포함된 선수의 OPS 평균 × 100',
    readingTip: '리그 전체·구장 보정 지표가 아닙니다. 공식 OPS+나 wRC+와 구분해 주세요.',
  ),
];

BaseballMetricGuide? baseballMetricGuideFor(String value) {
  final normalized = value.trim().toUpperCase();
  final key =
      const {
        '타율': 'AVG',
        '홈런': 'HR',
        '평균자책': 'ERA',
        '평균자책점': 'ERA',
        '다승': 'W',
        'WINS': 'W',
        '승': 'W',
        '승-패': 'W',
        '세이브': 'SV',
        'SAVES': 'SV',
        '탈삼진': 'SO',
        'STRIKEOUTS': 'SO',
        'OPS 상대지수': 'OPSPLUS',
      }[normalized] ??
      normalized;
  for (final guide in baseballMetricGuides) {
    if (guide.key == key) return guide;
  }
  return null;
}

Future<void> showBaseballMetricGuide(BuildContext context, {String? metric}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (context) => _MetricGuideSheet(initialMetric: metric),
  );
}

class BaseballMetricGuideButton extends StatelessWidget {
  final String? metric;
  final String label;
  const BaseballMetricGuideButton({
    super.key,
    this.metric,
    this.label = '기록 읽는 법',
  });

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => showBaseballMetricGuide(context, metric: metric),
    icon: const Icon(Icons.help_outline_rounded, size: 18),
    label: Text(label),
    style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
  );
}

class _MetricGuideSheet extends StatefulWidget {
  final String? initialMetric;
  const _MetricGuideSheet({this.initialMetric});
  @override
  State<_MetricGuideSheet> createState() => _MetricGuideSheetState();
}

class _MetricGuideSheetState extends State<_MetricGuideSheet> {
  late BaseballMetricGuide _selected;
  @override
  void initState() {
    super.initState();
    _selected =
        baseballMetricGuideFor(widget.initialMetric ?? '') ??
        baseballMetricGuides.first;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.78,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '기록 읽는 법',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: '기록 설명 닫기',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final guide in baseballMetricGuides)
                ChoiceChip(
                  label: Text(guide.key == 'OPSPLUS' ? 'OPS 상대지수' : guide.key),
                  selected: _selected == guide,
                  onSelected: (_) => setState(() => _selected = guide),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            _selected.title,
            key: const ValueKey('metric-guide-title'),
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            _selected.definition,
            style: const TextStyle(fontSize: 16, height: 1.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardSub,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _selected.formula,
              style: const TextStyle(
                fontSize: 16,
                height: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '함께 읽기',
            style: TextStyle(color: colors.accent, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            _selected.readingTip,
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          if (_selected.sourcePath != null) ...[
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://www.mlb.com/glossary/standard-stats/${_selected.sourcePath}',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('MLB 야구 용어집'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
