from __future__ import annotations

import json

from kbo_fans_backend.services.push_diagnostics import PushConfigurationDiagnostics


def main() -> None:
    print(json.dumps(PushConfigurationDiagnostics().status(), ensure_ascii=False, sort_keys=True))


if __name__ == "__main__":
    main()
