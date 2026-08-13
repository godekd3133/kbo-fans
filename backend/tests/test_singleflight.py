import threading
from concurrent.futures import ThreadPoolExecutor

import pytest

from kbo_fans_backend.utils.resilience import UpstreamBusyError
from kbo_fans_backend.utils.singleflight import SingleFlight


def test_singleflight_follower_has_bounded_wait_and_recovers() -> None:
    singleflight = SingleFlight[str]()
    started = threading.Event()
    release = threading.Event()

    def blocking_leader() -> str:
        started.set()
        assert release.wait(timeout=2)
        return "leader-result"

    with ThreadPoolExecutor(max_workers=1) as executor:
        leader = executor.submit(singleflight.call, "same-key", blocking_leader)
        assert started.wait(timeout=1)
        try:
            with pytest.raises(UpstreamBusyError, match="same-key"):
                singleflight.call(
                    "same-key",
                    lambda: "must-not-run",
                    wait_timeout_seconds=0.03,
                )
        finally:
            release.set()
        assert leader.result(timeout=1) == "leader-result"

    assert singleflight.call("same-key", lambda: "next-result") == "next-result"
