class TeamStats {
  final String teamId;
  final int season;
  final Map<String, String> hitting;
  final Map<String, String> pitching;

  const TeamStats({
    required this.teamId,
    required this.season,
    required this.hitting,
    required this.pitching,
  });
}
