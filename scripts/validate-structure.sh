#!/usr/bin/env bash
set -euo pipefail

required=(
  default.project.json src/client/init.client.luau src/server/Bootstrap.server.luau
  src/server/Services/DataService/init.luau src/server/Services/EconomyService.luau
  src/shared/Types/DomainTypes.luau src/shared/Config/Config.luau
  docs/ARCHITECTURE.md docs/SECURITY.md tests/run.luau
  real-baseplate.project.json docs/REAL_BASEPLATE_DEPLOYMENT.md
  scripts/validate-deployment.py
  scripts/validate-network-limits.py
)

for path in "${required[@]}"; do
  test -e "$path" || { echo "Missing required path: $path" >&2; exit 1; }
done

python3 scripts/validate-network-limits.py
# Arguments are forwarded, so --production reaches the gate it belongs to.
#
# This called the validator bare and accepted no arguments of its own, while the
# validator's own closing line tells you to "run again with --production before
# publishing". Passing that flag to this script did nothing at all: it was
# swallowed, the same permissive run happened again, and the same reassuring
# "Repository structure is valid" came back. The publish gate has therefore never
# once been runnable the way the tooling says to run it.
python3 scripts/validate-deployment.py "$@"
grep -q "Critical = true" src/server/Services/ContentValidationService.luau || {
  echo "ContentValidationService must remain critical; unsafe imported assets cannot be ignored." >&2
  exit 1
}
echo "Repository structure is valid."
