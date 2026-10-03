--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	H.test("vehicle plate application reuses one descendant snapshot", function()
		local runtime = Runtime.new()
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.VehiclePlateService)
		service:Init({
			Configuration = {
				VehicleIdentity = {
					PlatePartNames = {},
					PlateTextNames = { "Registration" },
					PlateGeneratorNames = { "PlateGenerator" },
				},
			},
		})

		local scans = 0
		local removed = false
		local attributes = {}
		local generator: any = {
			Name = "PlateGenerator",
			IsA = function(_self, className)
				return className == "BaseScript"
			end,
			Destroy = function()
				removed = true
			end,
		}
		local label: any = {
			Name = "Registration",
			Text = "OLD",
			Parent = nil,
			IsA = function(_self, className)
				return className == "TextLabel"
			end,
			GetAttribute = function()
				return nil
			end,
		}
		local descendants = { generator, label }
		local vehicle: any = {
			Name = "TestVehicle",
			GetDescendants = function()
				scans += 1
				return descendants
			end,
			SetAttribute = function(_self, name, value)
				attributes[name] = value
			end,
			FindFirstChild = function()
				return nil
			end,
		}

		local changed = service:Apply(vehicle, "AB12 CDE")
		H.expect(scans == 1, "plate application recursively enumerated the vehicle more than once")
		H.expect(removed, "legacy plate generator was not removed from the shared snapshot")
		H.expect(changed == 1 and label.Text == "AB12 CDE", "registration text update changed")
		H.expect(
			attributes.RoleplayOSRegistration == "AB12 CDE",
			"authoritative registration attribute was not written"
		)
	end)
end
