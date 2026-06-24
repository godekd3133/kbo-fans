import '../constants/team_data.dart';

String kboShortTeamDisplayName({
  required String teamId,
  required String teamName,
  required String shortName,
}) {
  final id = teamId.trim();
  if (id.isNotEmpty) {
    final team = KboTeams.byId(id);
    if (team != null) {
      return team.shortName;
    }
  }

  final short = shortName.trim();
  if (short.isNotEmpty) {
    final team = KboTeams.byId(short);
    if (team != null) {
      return team.shortName;
    }
  }

  final resolved = KboTeams.resolve(
    id: teamId,
    name: teamName,
    shortName: shortName,
  );
  if (resolved != null) {
    return resolved.shortName;
  }

  final name = teamName.trim();
  if (short.isNotEmpty) {
    return short;
  }
  if (name.isNotEmpty) {
    return name;
  }
  return id;
}
