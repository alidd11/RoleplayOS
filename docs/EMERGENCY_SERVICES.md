# Emergency services

Departments define ranks and roles. Duty profiles are separate from civilians. Starting duty validates profile, department, role, access and station before team assignment. Spawn, uniform and loadout responsibilities are isolated services. Loadouts clone only named ServerStorage tools; missing assets degrade with warnings rather than granting substitutes.

Unit registration carries callsign, department, division, station and status. Radio channels and complete MDT permission resolution are explicit integration points for v0.6. Suspension or blacklist always blocks access.

Emergency duty uses registered station spawn IDs rather than global part-name searches. See [Spawning](SPAWNING.md) for the validation and rollback contract.

The Careers view supplies applicant-safe duty-profile summaries and valid spawn options for each role. Frontline Policing displays its available reporting points and requires the player to choose one before the server begins duty. Production access remains application-gated; the development profile exists only under the explicit Studio mock setting.
