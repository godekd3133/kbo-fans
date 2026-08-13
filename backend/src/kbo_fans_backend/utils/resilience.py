from __future__ import annotations

import concurrent.futures
import threading
from typing import Any, Callable


class UpstreamBusyError(RuntimeError):
    """Raised when bounded upstream work cannot accept another waiter."""


class UpstreamDeadlineExceeded(TimeoutError):
    """Raised when an upstream aggregate exceeds its absolute time budget."""


class BoundedExecutor:
    """Thread pool with a bounded running + queued work budget."""

    def __init__(
        self,
        *,
        max_workers: int,
        max_pending: int,
        queue_timeout_seconds: float,
        thread_name_prefix: str,
    ) -> None:
        if max_workers <= 0:
            raise ValueError("max_workers must be positive")
        if max_pending < max_workers:
            raise ValueError("max_pending must be at least max_workers")
        self._executor = concurrent.futures.ThreadPoolExecutor(
            max_workers=max_workers,
            thread_name_prefix=thread_name_prefix,
        )
        self._capacity = threading.BoundedSemaphore(max_pending)
        self._queue_timeout_seconds = max(0.0, queue_timeout_seconds)

    def submit(self, fn: Callable[..., Any], *args: Any, **kwargs: Any):
        acquired = self._capacity.acquire(timeout=self._queue_timeout_seconds)
        if not acquired:
            raise UpstreamBusyError("upstream work queue is full")
        try:
            future = self._executor.submit(fn, *args, **kwargs)
        except BaseException:
            self._capacity.release()
            raise
        future.add_done_callback(lambda _: self._capacity.release())
        return future


def remaining_seconds(deadline: float, *, now: Callable[[], float]) -> float:
    return max(0.0, deadline - now())


def result_before_deadline(
    future: concurrent.futures.Future,
    *,
    deadline: float,
    now: Callable[[], float],
    operation: str,
) -> Any:
    remaining = remaining_seconds(deadline, now=now)
    if remaining <= 0:
        future.cancel()
        raise UpstreamDeadlineExceeded(f"{operation} deadline exceeded")
    try:
        return future.result(timeout=remaining)
    except concurrent.futures.TimeoutError as error:
        future.cancel()
        raise UpstreamDeadlineExceeded(f"{operation} deadline exceeded") from error
