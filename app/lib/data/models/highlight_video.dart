class HighlightVideo {
  final String videoId;
  final String title;
  final String thumbnailUrl;
  final String videoUrl;
  final String source;

  const HighlightVideo({
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
    required this.videoUrl,
    this.source = 'youtube_search',
  });
}
