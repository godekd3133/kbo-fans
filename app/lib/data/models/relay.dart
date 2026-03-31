class RelayItem {
  final int seqNo;
  final int inning;
  final String half; // "top" or "bottom"
  final String event; // HIT, HOMERUN, OUT, WALK, etc.
  final bool isScoring;
  final String text;
  final String? pitchSequence;

  const RelayItem({
    required this.seqNo,
    required this.inning,
    required this.half,
    required this.event,
    this.isScoring = false,
    required this.text,
    this.pitchSequence,
  });
}

class CurrentAtBat {
  final String batterName;
  final int batterNumber;
  final String batterHand;
  final String batterRecent;
  final String pitcherName;
  final int pitcherNumber;
  final String pitcherHand;
  final int pitchCount;
  final String inningText;
  final String baseState;
  final int balls;
  final int strikes;
  final int outs;

  const CurrentAtBat({
    required this.batterName,
    required this.batterNumber,
    required this.batterHand,
    this.batterRecent = '',
    required this.pitcherName,
    required this.pitcherNumber,
    required this.pitcherHand,
    required this.pitchCount,
    this.inningText = '',
    this.baseState = '',
    required this.balls,
    required this.strikes,
    required this.outs,
  });
}

class RelayData {
  final CurrentAtBat? currentAtBat;
  final List<RelayItem> relayItems;

  const RelayData({required this.currentAtBat, required this.relayItems});
}
