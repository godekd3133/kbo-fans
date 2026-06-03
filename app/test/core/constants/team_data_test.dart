import 'package:flutter_test/flutter_test.dart';
import 'package:kbo_fans/core/constants/team_data.dart';

void main() {
  test('team logo URLs use transparent fixed emblem assets', () {
    for (final team in KboTeams.teams) {
      expect(
        team.logoUrl,
        'https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/emblem/regular/fixed/emblem_${team.id}.png',
      );
      expect(team.logoUrl, isNot(contains('_L.png')));
    }
  });
}
