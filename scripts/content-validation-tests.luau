--!strict
local Runtime = require("./test-runtime")

return function(H: any)
	local function fixture(certifiedAssets: any?): (any, any, any)
		local runtime = Runtime.new()
		runtime.services.ServerStorage = runtime.globals.Instance.new("Folder")
		runtime.services.CollectionService = {}
		local root = runtime.services.ServerScriptService.RoleplayOS.Services
		local service = runtime.require(root.ContentValidationService)
		local context = {
			Configuration = {
				ContentQuality = {
					RequireCertification = false,
					CertifiedAssets = certifiedAssets or {},
					MaximumToolParts = 10,
					MaximumToolDescendants = 10,
				},
			},
		}
		service:Init(context)

		local scans = 0
		local descendants = {}
		local tool: any = {
			Name = "TestTool",
			RequiresHandle = nil,
			IsA = function(_self, className)
				return className == "Tool"
			end,
			GetAttribute = function()
				return nil
			end,
			GetDescendants = function()
				scans += 1
				return descendants
			end,
			GetFullName = function()
				return "ServerStorage.RoleplayOSAssets.Tools.TestTool"
			end,
			FindFirstChild = function()
				return nil
			end,
		}
		local toolsFolder: any = {
			FindFirstChild = function(_self, name)
				return if name == "TestTool" then tool else nil
			end,
		}
		local assets: any = {
			FindFirstChild = function(_self, name)
				return if name == "Tools" then toolsFolder else nil
			end,
		}
		return service, {
			Assets = assets,
			Tool = tool,
			Descendants = descendants,
			Scans = function()
				return scans
			end,
		}, runtime
	end

	H.test("content validation snapshots one asset tree for all checks", function()
		local service, f = fixture()
		local part: any = {
			Name = "Handle",
			ClassName = "Part",
			Parent = f.Tool,
			IsA = function(_self, className)
				return className == "BasePart" or className == "Part"
			end,
		}
		table.insert(f.Descendants, part)

		service:_check(
			f.Assets,
			"Tool",
			"TestTool",
			{ AssetPath = { "Tools", "TestTool" } },
			"Tool"
		)

		H.expect(f.Scans() == 1, "one tool validation recursively enumerated its tree more than once")
		H.expect(
			#service.report.Invalid == 0 and table.find(service.report.Ready, "Tool:TestTool"),
			"valid tool changed validation outcome while reusing the descendant snapshot"
		)
	end)

	H.test("content validation still inspects certified script source from the snapshot", function()
		local service, f = fixture({
			TestTool = {
				AllowedUnsafeDescendants = {
					Reviewed = { ClassName = "Script", Path = { "Reviewed" } },
				},
			},
		})
		local part: any = {
			Name = "Handle",
			ClassName = "Part",
			Parent = f.Tool,
			IsA = function(_self, className)
				return className == "BasePart" or className == "Part"
			end,
		}
		local scriptInstance: any = {
			Name = "Reviewed",
			ClassName = "Script",
			Parent = f.Tool,
			Source = "local HttpService = game:GetService(\"HttpService\")",
			IsA = function(_self, className)
				return className == "LuaSourceContainer" or className == "Script"
			end,
		}
		table.insert(f.Descendants, part)
		table.insert(f.Descendants, scriptInstance)

		service:_check(
			f.Assets,
			"Tool",
			"TestTool",
			{ AssetPath = { "Tools", "TestTool" } },
			"Tool"
		)

		H.expect(f.Scans() == 1, "script source validation performed another recursive asset scan")
		H.expect(
			table.find(service.report.Invalid, "Tool:TestTool:UNSAFE_SOURCE_HTTP_SERVICE") ~= nil,
			"certified unsafe descendant bypassed forbidden source validation"
		)
	end)
end
