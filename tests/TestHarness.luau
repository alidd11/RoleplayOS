--!strict
local Harness = { passed = 0, failed = 0 }
function Harness.expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end
function Harness.test(name: string, callback: () -> ())
	local ok, problem = pcall(callback)
	if ok then
		Harness.passed += 1
		print("PASS " .. name)
	else
		Harness.failed += 1
		warn("FAIL " .. name .. ": " .. tostring(problem))
	end
end
function Harness.finish()
	assert(Harness.failed == 0, string.format("%d tests failed", Harness.failed))
	print(string.format("%d tests passed", Harness.passed))
end
return Harness
