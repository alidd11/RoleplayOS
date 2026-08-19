--!strict
local Utils = {}

function Utils.trimToMaximum(items: { any }, maximum: number)
	while #items > maximum do
		table.remove(items, 1)
	end
end

function Utils.root(player: Player): BasePart?
	local item = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	return if item and item:IsA("BasePart") then item else nil
end

function Utils.humanoid(player: Player): Humanoid?
	return if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
end

return Utils
