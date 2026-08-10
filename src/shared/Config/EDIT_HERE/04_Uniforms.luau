--!strict

-- Use clothing template asset IDs, not catalogue page URLs. Empty values keep
-- the uniform disabled and deliberately fail the production release check.
return {
	Uniforms = {
		-- Extracted from the supplied "Police Community Support Officer" kit.
		PoliceCommunitySupportOfficer = {
			ShirtTemplate = "2301512590",
			TrousersTemplate = "700637070",
			KitAssetPath = { "Uniforms", "Police", "PoliceCommunitySupportOfficer" },
			RemovePersonalAccessories = true,
		},
		PoliceStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		AmbulanceStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		FireStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		TransportStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		HighwaysStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		PrisonStandard = { ShirtTemplate = "", TrousersTemplate = "" },
	},
}
