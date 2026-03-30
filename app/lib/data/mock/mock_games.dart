import '../../core/constants/ticketing_policy.dart';
import '../models/game.dart';
import '../models/highlight_info.dart';
import '../models/highlight_video.dart';

final mockGames = <Game>[
  Game(
    gameId: '20260328KTLG0',
    status: GameStatus.live,
    inning: '4회초',
    away: TeamScore(
      teamId: 'KT', teamName: 'KT 위즈', shortName: 'KT', score: 6,
      innings: [6, 0, 0, 0, null, null, null, null, null],
      hits: 9, errors: 0, walks: 4,
    ),
    home: TeamScore(
      teamId: 'LG', teamName: 'LG 트윈스', shortName: 'LG', score: 2,
      innings: [0, 0, 2, null, null, null, null, null, null],
      hits: 3, errors: 0, walks: 4,
    ),
    stadium: '잠실',
    startTime: '14:00',
    crowd: 23750,
    ticketInfo: TicketingPolicy.inferredTicketInfo(
      homeTeamId: 'LG',
      gameId: '20260328KTLG0',
      startTime: '14:00',
    ),
    highlightInfo: const HighlightInfo(
      officialUrl: 'https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx?gameDate=20260328&gameId=20260328KTLG0&section=HIGHLIGHT',
      youtubeVideos: [
        HighlightVideo(
          videoId: 'tyo0j_fyPMU',
          title: 'KT vs LG 하이라이트 1',
          thumbnailUrl: 'https://i.ytimg.com/vi/tyo0j_fyPMU/hqdefault.jpg',
          videoUrl: 'https://www.youtube.com/watch?v=tyo0j_fyPMU',
        ),
        HighlightVideo(
          videoId: '-um_JO9NGOo',
          title: 'KT vs LG 하이라이트 2',
          thumbnailUrl: 'https://i.ytimg.com/vi/-um_JO9NGOo/hqdefault.jpg',
          videoUrl: 'https://www.youtube.com/watch?v=-um_JO9NGOo',
        ),
      ],
    ),
  ),
  Game(
    gameId: '20260328HTSK0',
    status: GameStatus.live,
    inning: '5회초',
    away: TeamScore(
      teamId: 'HT', teamName: 'KIA 타이거즈', shortName: 'KIA', score: 3,
      innings: [0, 1, 0, 2, null, null, null, null, null],
      hits: 6, errors: 0, walks: 2,
    ),
    home: TeamScore(
      teamId: 'SK', teamName: 'SSG 랜더스', shortName: 'SSG', score: 0,
      innings: [0, 0, 0, 0, null, null, null, null, null],
      hits: 2, errors: 1, walks: 3,
    ),
    stadium: '문학',
    startTime: '14:00',
    crowd: 18200,
    ticketInfo: TicketingPolicy.inferredTicketInfo(
      homeTeamId: 'SK',
      gameId: '20260328HTSK0',
      startTime: '14:00',
    ),
  ),
  Game(
    gameId: '20260328LTSS0',
    status: GameStatus.live,
    inning: '5회초',
    away: TeamScore(
      teamId: 'LT', teamName: '롯데 자이언츠', shortName: '롯데', score: 3,
      innings: [1, 0, 2, 0, null, null, null, null, null],
      hits: 7, errors: 0, walks: 1,
    ),
    home: TeamScore(
      teamId: 'SS', teamName: '삼성 라이온즈', shortName: '삼성', score: 0,
      innings: [0, 0, 0, 0, null, null, null, null, null],
      hits: 1, errors: 0, walks: 2,
    ),
    stadium: '대구',
    startTime: '14:00',
    crowd: 15600,
    ticketInfo: TicketingPolicy.inferredTicketInfo(
      homeTeamId: 'SS',
      gameId: '20260328LTSS0',
      startTime: '14:00',
    ),
  ),
  Game(
    gameId: '20260328OBNC0',
    status: GameStatus.live,
    inning: '4회말',
    away: TeamScore(
      teamId: 'OB', teamName: '두산 베어스', shortName: '두산', score: 0,
      innings: [0, 0, 0, null, null, null, null, null, null],
      hits: 2, errors: 0, walks: 1,
    ),
    home: TeamScore(
      teamId: 'NC', teamName: 'NC 다이노스', shortName: 'NC', score: 3,
      innings: [1, 0, 2, null, null, null, null, null, null],
      hits: 5, errors: 0, walks: 2,
    ),
    stadium: '창원',
    startTime: '14:00',
    crowd: 12400,
    ticketInfo: TicketingPolicy.inferredTicketInfo(
      homeTeamId: 'NC',
      gameId: '20260328OBNC0',
      startTime: '14:00',
    ),
  ),
  Game(
    gameId: '20260328WOHH0',
    status: GameStatus.live,
    inning: '5회초',
    away: TeamScore(
      teamId: 'WO', teamName: '키움 히어로즈', shortName: '키움', score: 0,
      innings: [0, 0, 0, 0, null, null, null, null, null],
      hits: 3, errors: 1, walks: 2,
    ),
    home: TeamScore(
      teamId: 'HH', teamName: '한화 이글스', shortName: '한화', score: 3,
      innings: [0, 2, 0, 1, null, null, null, null, null],
      hits: 6, errors: 0, walks: 1,
    ),
    stadium: '대전',
    startTime: '14:00',
    crowd: 11800,
    ticketInfo: TicketingPolicy.inferredTicketInfo(
      homeTeamId: 'HH',
      gameId: '20260328WOHH0',
      startTime: '14:00',
    ),
  ),
];
