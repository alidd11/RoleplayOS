# Release readiness

This is the short production handoff for **Emergency Response: Portsmouth**. It
separates repository checks that can run automatically from decisions and evidence
that must come from the authorised Roblox place.

## Automated gate

Run from the repository root:

```sh
stylua --check src tests
selene src tests
bash scripts/validate-structure.sh
python3 scripts/validate-deployment.py --production
python3 scripts/audit-gamepasses.py
rojo build real-baseplate.project.json --output build/RoleplayOS-Production.rbxlx
```

The production command is intentionally expected to fail until every item below is
resolved. Do not bypass or weaken it to obtain a green build.

## Configuration blockers requiring an owner decision

- Change `Framework.Environment` to `Production` only for the release candidate.
- Set both Studio mock-access switches to `false` in the release candidate.
- Replace the temporary Control group mapping with the final Roblox group ID.
- Add the final Roblox shirt and trouser template IDs for every configured uniform.
- Confirm every gamepass ID belongs to the production experience, not the development
  baseplate.
- Confirm every production pass is on sale at its approved positive Robux price. The
  live read-only audit reports disabled and unpriced passes before release.
- Enable the speeding-fine integration only after the Creator Hub secret exists and
  HTTP requests are enabled. Never store a Discord webhook URL in this repository.

## Content blockers

- Migrate the approved vehicles and tools into `ServerStorage/RoleplayOSAssets`.
- Certify the required CCTV, ANPR, speed-camera, custody, dealership and dispatch
  models in `WORLD_ASSET_CERTIFICATION.md`.
- Keep all imported templates free of scripts, remotes, bindables, prompts and click
  detectors. `ContentValidationService` is critical and stops an unsafe server from
  starting.
- Record provenance and redistribution rights for every third-party model or decal.

## Place-only acceptance

Complete every applicable row in `STAGING_ACCEPTANCE.md` against the exact published
staging version that will be promoted. At minimum this requires two players and two
live JobIds, because persistence, session locking, dispatch isolation and reset/rejoin
behaviour cannot be proven by a source build.

No production publish is approved until the automated gate and applicable live rows
both pass.
