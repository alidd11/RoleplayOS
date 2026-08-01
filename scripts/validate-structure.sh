#!/usr/bin/env bash
set -euo pipefail

required=(
  default.project.json src/client/init.client.luau src/server/Bootstrap.server.luau
  src/server/Services/DataService.luau src/server/Services/EconomyService.luau
  src/shared/Types/DomainTypes.luau src/shared/Config/Config.luau
  docs/ARCHITECTURE.md docs/SECURITY.md tests/run.luau
)

for path in "${required[@]}"; do
  test -e "$path" || { echo "Missing required path: $path" >&2; exit 1; }
done

echo "Repository structure is valid."
