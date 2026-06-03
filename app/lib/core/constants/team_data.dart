import 'package:flutter/material.dart';

class KboTeam {
  final String id;
  final String name;
  final String shortName;
  final Color primaryColor;
  final Color secondaryColor;

  const KboTeam({
    required this.id,
    required this.name,
    required this.shortName,
    required this.primaryColor,
    required this.secondaryColor,
  });

  String get logoUrl =>
      'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/emblem/regular/fixed/emblem_$id.png';
}

class KboTeams {
  static const teams = <KboTeam>[
    KboTeam(
      id: 'LG',
      name: 'LG 트윈스',
      shortName: 'LG',
      primaryColor: Color(0xFFC60C30),
      secondaryColor: Color(0xFF000000),
    ),
    KboTeam(
      id: 'KT',
      name: 'KT 위즈',
      shortName: 'KT',
      primaryColor: Color(0xFF000000),
      secondaryColor: Color(0xFFEB1C24),
    ),
    KboTeam(
      id: 'SK',
      name: 'SSG 랜더스',
      shortName: 'SSG',
      primaryColor: Color(0xFFCE0E2D),
      secondaryColor: Color(0xFF1D1D1B),
    ),
    KboTeam(
      id: 'SS',
      name: '삼성 라이온즈',
      shortName: '삼성',
      primaryColor: Color(0xFF074CA1),
      secondaryColor: Color(0xFFFFFFFF),
    ),
    KboTeam(
      id: 'NC',
      name: 'NC 다이노스',
      shortName: 'NC',
      primaryColor: Color(0xFF315288),
      secondaryColor: Color(0xFFC5A55A),
    ),
    KboTeam(
      id: 'HH',
      name: '한화 이글스',
      shortName: '한화',
      primaryColor: Color(0xFFFF6600),
      secondaryColor: Color(0xFF000000),
    ),
    KboTeam(
      id: 'LT',
      name: '롯데 자이언츠',
      shortName: '롯데',
      primaryColor: Color(0xFF041E42),
      secondaryColor: Color(0xFFD00F31),
    ),
    KboTeam(
      id: 'HT',
      name: 'KIA 타이거즈',
      shortName: 'KIA',
      primaryColor: Color(0xFFEA0029),
      secondaryColor: Color(0xFF000000),
    ),
    KboTeam(
      id: 'OB',
      name: '두산 베어스',
      shortName: '두산',
      primaryColor: Color(0xFF131230),
      secondaryColor: Color(0xFFFFFFFF),
    ),
    KboTeam(
      id: 'WO',
      name: '키움 히어로즈',
      shortName: '키움',
      primaryColor: Color(0xFF820024),
      secondaryColor: Color(0xFF000000),
    ),
  ];

  static KboTeam? byId(String id) {
    try {
      return teams.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  static KboTeam? resolve({String? id, String? name, String? shortName}) {
    final normalizedId = (id ?? '').trim();
    if (normalizedId.isNotEmpty) {
      final team = byId(normalizedId);
      if (team != null) {
        return team;
      }
    }

    final candidates = [
      (name ?? '').trim(),
      (shortName ?? '').trim(),
    ].where((value) => value.isNotEmpty).toList();

    for (final candidate in candidates) {
      try {
        return teams.firstWhere(
          (team) =>
              team.name == candidate ||
              team.shortName == candidate ||
              team.name.replaceAll(' ', '') == candidate.replaceAll(' ', ''),
        );
      } catch (_) {
        continue;
      }
    }

    return null;
  }
}
