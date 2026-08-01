# Development

Install tools with `aftman install`, serve with `rojo serve`, and connect an empty baseplate through the Rojo Studio plugin. Configure Teams, SpawnLocations and ServerStorage models by name. IDs set to `0`, empty uniform templates and missing models are intentional development values and grant no premium entitlement.

Before a change: read `AGENTS.md`, identify the owning service and update configuration/types first. After a change run:

```sh
stylua src tests
selene src tests
bash scripts/validate-structure.sh
rojo build default.project.json --output build/RoleplayOS.rbxlx
```

Never add direct DataStore or balance calls outside their owning services. Add a migration for persistent shape changes, a pure test for validation logic, and documentation for contract changes.
