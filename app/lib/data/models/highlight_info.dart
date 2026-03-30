import 'highlight_video.dart';

class HighlightInfo {
  final String? officialUrl;
  final List<HighlightVideo> youtubeVideos;

  const HighlightInfo({
    this.officialUrl,
    this.youtubeVideos = const [],
  });
}
