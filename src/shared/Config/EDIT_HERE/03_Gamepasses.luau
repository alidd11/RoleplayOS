--!strict

-- Pass IDs belong to the publishable Portsmouth experience. A zero disables
-- purchasing and entitlement for that entry without breaking the menu.
--
-- PriceInRobux is also shown in the in-game catalogue. Set the matching price
-- on the same pass in Creator Hub; this file cannot publish Roblox catalogue
-- changes by itself.
return {
	Gamepasses = {
		PremiumVehicles = { GamepassId = 1936590544, PriceInRobux = 199 },
		ExtraCharacterSlot = { GamepassId = 1934044063, PriceInRobux = 99 },
		CustomRegistration = { GamepassId = 1937140343, PriceInRobux = 49 },
		CivilianKnife = { GamepassId = 1937446295, PriceInRobux = 75 },
		CivilianHandgun = { GamepassId = 1937822271, PriceInRobux = 125 },
		CivilianShotgun = { GamepassId = 1934518052, PriceInRobux = 175 },
		CivilianRifle = { GamepassId = 1934955986, PriceInRobux = 225 },
		PublicPoliceTeam = { GamepassId = 1937222319, PriceInRobux = 99 },
		PublicArmedResponse = { GamepassId = 1933270297, PriceInRobux = 249 },
		PublicRoadsPolicing = { GamepassId = 1933156365, PriceInRobux = 149 },
		PublicAmbulanceTeam = { GamepassId = 1936100607, PriceInRobux = 99 },
		PublicFireTeam = { GamepassId = 1936292594, PriceInRobux = 99 },
		PublicControlTeam = { GamepassId = 1935724637, PriceInRobux = 79 },
		PublicTransportTeam = { GamepassId = 1934302085, PriceInRobux = 59 },
		PublicHighwaysTeam = { GamepassId = 1934122097, PriceInRobux = 79 },
		PublicPrisonTeam = { GamepassId = 1937368306, PriceInRobux = 79 },
		GangSystemAccess = { GamepassId = 1941013627, PriceInRobux = 499 },
	},
}
