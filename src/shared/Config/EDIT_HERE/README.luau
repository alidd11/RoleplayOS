--!strict

--[[
	ROLEPLAYOS EDITABLE DATA

	These modules are the safe place for ordinary game configuration. They are
	loaded over the framework defaults in Config, so services do not need editing.

	01_Deployment  - production/studio switches and game branding
	02_Groups      - Roblox community IDs and minimum ranks
	03_Gamepasses  - pass IDs created for this experience
	04_Uniforms    - Roblox shirt and trouser template IDs
	05_Balancing   - starting cash, character slots and common timings

	Use numbers without quotes for Roblox IDs. Leave an unknown asset ID as an
	empty string, never as a catalogue URL. Publish only after the production
	validator passes.

	Vehicles and tools are inserted as Models/Tools under ServerStorage >
	RoleplayOSAssets. Their folder layout is documented by the README stored at
	the root of RoleplayOSAssets.
]]

return "Open the numbered modules beside this one to edit RoleplayOS data."
