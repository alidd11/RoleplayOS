--!strict

--[[
	ROLEPLAYOS EDITABLE DATA

	These numbered modules are the safe place for routine game configuration. They
	are loaded over the framework defaults in Config, so services do not need edits.

	01_Deployment  - production/studio switches, branding and integrations
	02_Groups      - Roblox community IDs and minimum ranks
	03_Gamepasses  - pass IDs created for the production experience
	04_Uniforms    - Roblox shirt and trouser template IDs
	05_Balancing   - starting money, character slots and common timings
	06_Vehicles    - vehicle prices, models, folders and spawner behaviour

	Use numbers without quotes for Roblox IDs. Leave an unknown clothing ID empty,
	never use a catalogue URL. Run the production validator before publishing.

	Vehicles and Tools are Models/Tools under ServerStorage > RoleplayOSAssets.
	Their exact folder layout is documented by the README at that root and by
	docs/CONTENT_AUTHORING.md in the repository.
]]

return "Read this module before changing the numbered RoleplayOS configuration files."
