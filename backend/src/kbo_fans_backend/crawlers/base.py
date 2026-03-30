from requests import Session

from kbo_fans_backend.core.config import get_settings


class BaseCrawler:
    def __init__(self) -> None:
        settings = get_settings()
        self.base_url = settings.kbo_base_url
        self.timeout = settings.request_timeout_seconds
        self.session = Session()
        self.session.headers.update(
            {
                "User-Agent": (
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36"
                ),
                "Referer": f"{self.base_url}/",
            }
        )
