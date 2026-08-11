from pathlib import Path
from types import SimpleNamespace

import kbo_fans_backend.core.config as config_module
import kbo_fans_backend.storage.snapshot_store as snapshot_store_module
from kbo_fans_backend.storage import JsonSnapshotStore


def test_default_snapshot_paths_separate_runtime_writes_from_packaged_seeds(
    monkeypatch,
) -> None:
    monkeypatch.delenv("SNAPSHOT_DIR", raising=False)
    monkeypatch.delenv("SNAPSHOT_SEED_DIR", raising=False)
    config_module.get_settings.cache_clear()
    try:
        settings = config_module.get_settings()
    finally:
        config_module.get_settings.cache_clear()

    backend_data_dir = Path(config_module.__file__).resolve().parents[3] / "data"
    assert Path(settings.snapshot_dir) == backend_data_dir / "runtime" / "snapshots"
    assert Path(settings.snapshot_seed_dir) == backend_data_dir / "snapshots"


def test_default_store_reads_seed_but_writes_only_runtime(tmp_path, monkeypatch) -> None:
    runtime_dir = tmp_path / "runtime"
    seed_dir = tmp_path / "seed"
    seed_store = JsonSnapshotStore(base_dir=str(seed_dir))
    seed_store.save("standings_latest", "2025", {"source": "seed"})
    seed_path = seed_dir / "standings_latest" / "2025.json"
    seed_before = seed_path.read_text(encoding="utf-8")
    monkeypatch.setattr(
        snapshot_store_module,
        "get_settings",
        lambda: SimpleNamespace(
            snapshot_dir=str(runtime_dir),
            snapshot_seed_dir=str(seed_dir),
        ),
    )

    store = JsonSnapshotStore()

    assert store.load_payload("standings_latest", "2025") == {"source": "seed"}
    assert not (runtime_dir / "standings_latest" / "2025.json").exists()

    store.save("standings_latest", "2025", {"source": "runtime"})

    assert store.load_payload("standings_latest", "2025") == {"source": "runtime"}
    assert seed_path.read_text(encoding="utf-8") == seed_before


def test_explicit_base_dir_does_not_fall_back_to_configured_seed(
    tmp_path,
    monkeypatch,
) -> None:
    explicit_dir = tmp_path / "explicit"
    seed_dir = tmp_path / "seed"
    JsonSnapshotStore(base_dir=str(seed_dir)).save(
        "standings_latest",
        "2025",
        {"source": "seed"},
    )
    monkeypatch.setattr(
        snapshot_store_module,
        "get_settings",
        lambda: SimpleNamespace(
            snapshot_dir=str(tmp_path / "runtime"),
            snapshot_seed_dir=str(seed_dir),
        ),
    )

    store = JsonSnapshotStore(base_dir=str(explicit_dir))

    assert store.load("standings_latest", "2025") is None
