import '../../data/models/ticketing.dart';
import '../utils/kbo_time.dart';

class TicketingPolicy {
  static const Map<String, Map<String, String>> _vendorByTeam = {
    'LG': {
      'vendorKey': 'interpark',
      'vendorName': '인터파크 티켓',
      'vendorUrl': 'https://tickets.interpark.com',
    },
    'OB': {
      'vendorKey': 'interpark',
      'vendorName': '인터파크 티켓',
      'vendorUrl': 'https://tickets.interpark.com',
    },
    'SK': {
      'vendorKey': 'interpark',
      'vendorName': '인터파크 티켓',
      'vendorUrl': 'https://tickets.interpark.com',
    },
    'KT': {
      'vendorKey': 'interpark',
      'vendorName': '인터파크 티켓',
      'vendorUrl': 'https://tickets.interpark.com',
    },
    'HT': {
      'vendorKey': 'ticketlink',
      'vendorName': '티켓링크',
      'vendorUrl': 'https://www.ticketlink.co.kr',
    },
    'HH': {
      'vendorKey': 'ticketlink',
      'vendorName': '티켓링크',
      'vendorUrl': 'https://www.ticketlink.co.kr',
    },
    'NC': {
      'vendorKey': 'ticketlink',
      'vendorName': '티켓링크',
      'vendorUrl': 'https://www.ticketlink.co.kr',
    },
    'SS': {
      'vendorKey': 'ticketlink',
      'vendorName': '티켓링크',
      'vendorUrl': 'https://www.ticketlink.co.kr',
    },
    'LT': {
      'vendorKey': 'ticketlink',
      'vendorName': '티켓링크',
      'vendorUrl': 'https://www.ticketlink.co.kr',
    },
    'WO': {
      'vendorKey': 'ticketlink',
      'vendorName': '티켓링크',
      'vendorUrl': 'https://www.ticketlink.co.kr',
    },
  };

  static TicketInfo? inferredTicketInfo({
    required String homeTeamId,
    required String gameId,
    required String startTime,
  }) {
    final vendor = _vendorByTeam[homeTeamId];
    if (vendor == null) {
      return null;
    }

    final gameStart = _parseGameStart(gameId: gameId, startTime: startTime);
    final gameCivil = gameStart == null ? null : kboCivilDateTime(gameStart);
    final openDate = gameCivil == null
        ? null
        : DateTime.utc(
            gameCivil.year,
            gameCivil.month,
            gameCivil.day,
          ).subtract(const Duration(days: 7));
    final openAt = openDate == null
        ? null
        : kboInstantFromCivil(
            year: openDate.year,
            month: openDate.month,
            day: openDate.day,
            hour: 11,
          );

    return TicketInfo(
      vendorKey: vendor['vendorKey']!,
      vendorName: vendor['vendorName']!,
      vendorUrl: vendor['vendorUrl'],
      openAt: openAt,
      source: TicketSource.inferred,
      note: '홈팀 기본 예매 정책 기준 추정값',
    );
  }

  static DateTime? _parseGameStart({
    required String gameId,
    required String startTime,
  }) {
    if (gameId.length < 8) {
      return null;
    }

    final hourMinute = startTime.split(':');
    if (hourMinute.length != 2) {
      return null;
    }

    final year = int.tryParse(gameId.substring(0, 4));
    final month = int.tryParse(gameId.substring(4, 6));
    final day = int.tryParse(gameId.substring(6, 8));
    final hour = int.tryParse(hourMinute[0]);
    final minute = int.tryParse(hourMinute[1]);

    if ([year, month, day, hour, minute].contains(null)) {
      return null;
    }

    return kboInstantFromCivil(
      year: year!,
      month: month!,
      day: day!,
      hour: hour!,
      minute: minute!,
    );
  }
}
