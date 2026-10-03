--!strict

-- Use clothing template asset IDs, not catalogue page URLs. Empty values keep
-- the uniform disabled and deliberately fail the production release check.
return {
	Uniforms = {
		PoliceStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		AmbulanceStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		FireStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		TransportStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		HighwaysStandard = { ShirtTemplate = "", TrousersTemplate = "" },
		PrisonStandard = { ShirtTemplate = "", TrousersTemplate = "" },
	},
}
