import threading
from concurrent.futures import ThreadPoolExecutor

from kbo_fans_backend.utils import ttl_cache as ttl_cache_module
from kbo_fans_backend.utils.ttl_cache import TtlCache


def test_expired_value_remains_available_for_stale_fallback(monkeypatch) -> None:
    now = [100.0]
    monkeypatch.setattr(ttl_cache_module.time, "monotonic", lambda: now[0])
    cache = TtlCache[str, dict](ttl_seconds=10)
    cache.set("historical", {"source": "crawler"})

    now[0] = 111.0

    assert cache.get("historical") is None
    assert cache.get_stale("historical") == {"source": "crawler"}


def test_cache_evicts_oldest_entry_at_capacity(monkeypatch) -> None:
    now = [100.0]
    monkeypatch.setattr(ttl_cache_module.time, "monotonic", lambda: now[0])
    cache = TtlCache[str, int](ttl_seconds=10, max_entries=2)
    cache.set("oldest", 1)
    now[0] = 101.0
    cache.set("middle", 2)
    now[0] = 102.0
    cache.set("newest", 3)

    assert cache.get_stale("oldest") is None
    assert cache.get_stale("middle") == 2
    assert cache.get_stale("newest") == 3


def test_concurrent_writes_keep_cache_within_capacity(monkeypatch) -> None:
    cache = TtlCache[str, int](ttl_seconds=10, max_entries=1)
    cache.set("seed", 0)
    workers_ready = threading.Barrier(2)

    def synchronized_monotonic() -> float:
        workers_ready.wait(timeout=2)
        return 100.0

    monkeypatch.setattr(ttl_cache_module.time, "monotonic", synchronized_monotonic)
    with ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(cache.set, "first", 1),
            executor.submit(cache.set, "second", 2),
        ]
        for future in futures:
            future.result(timeout=2)

    assert cache.get_stale("seed") is None
    assert sum(
        cache.get_stale(key) is not None for key in ("first", "second")
    ) == 1
