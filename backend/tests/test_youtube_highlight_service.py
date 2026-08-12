import threading

from kbo_fans_backend.services.youtube_highlight import YoutubeHighlightService


def test_relevant_title_accepts_short_team_aliases() -> None:
    service = YoutubeHighlightService()

    assert service._is_relevant_title(
        title="6/30 KT vs LG 하이라이트",
        away_name="KT 위즈",
        home_name="LG 트윈스",
        game_id="20260630KTLG0",
    )


def test_highlight_oembed_titles_are_fetched_with_bounded_parallelism(monkeypatch) -> None:
    service = YoutubeHighlightService()
    video_ids = ["aaaaaaaaaaa", "bbbbbbbbbbb", "ccccccccccc"]
    barrier = threading.Barrier(len(video_ids))
    thread_ids = set()

    monkeypatch.setattr(service, "_search_video_ids", lambda query, limit: video_ids)

    def fetch_title(video_url: str) -> str:
        del video_url
        thread_ids.add(threading.get_ident())
        barrier.wait(timeout=2)
        return "6/30 KT vs LG 하이라이트"

    monkeypatch.setattr(service, "_fetch_title", fetch_title)

    videos = service.fetch_highlights(
        game_id="20260630KTLG0",
        away_name="KT 위즈",
        home_name="LG 트윈스",
    )

    assert len(videos) == len(video_ids)
    assert len(thread_ids) > 1
