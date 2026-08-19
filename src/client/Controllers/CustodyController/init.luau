--!strict

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local CustodyController = {
	connections = {},
	targetUserId = nil,
	selectedCodes = {},
	policy = {},
	policyMetadata = {},
	chips = {},
}

local BookingTerminal = require(script.BookingTerminal)
local DetentionStatus = require(script.DetentionStatus)

-- Each of these attaches a group of methods onto CustodyController directly
-- (they only need `self`, not a lexical upvalue) - the same split used for
-- NetworkService, DataService, VehicleSpawnerService and CustodyService this
-- session. Order does not matter: nothing here runs until a caller invokes a
-- method, well after every group is attached.
BookingTerminal(CustodyController)
DetentionStatus(CustodyController)

-- What a refused custody request means, in words the player can act on.
--
-- Every refusal below used to reach the player as "Custody action was refused"
-- or "The custody booking could not be completed", which names the outcome and
-- withholds the only part that matters: whether to walk closer, write more, or
-- stop trying. The server already sends the reason as a Code beside the
-- message, so nothing new has to be asked for to say which it is.
local REFUSALS = {
	NOT_AUTHORISED = "Your role cannot process custody.",
	TARGET_NOT_SEATED = "Sit the detainee in a custody chair before booking them.",
	CHAIR_NOT_FOUND = "That custody chair could not be found.",
	CHAIR_EMPTY = "Nobody is sitting in that chair.",
	TARGET_NOT_CUFFED = "The detainee has to be in handcuffs first.",
	TARGET_OUT_OF_RANGE = "Get closer to the detainee, with nothing between you.",
	TARGET_UNAVAILABLE = "That player cannot be dealt with right now.",
	GROUNDS_REQUIRED = "Write the grounds first — a few words is enough.",
	INVALID_GROUNDS = "Those grounds could not be read. Type them again.",
	TEXT_FILTER_UNAVAILABLE = "Roblox could not check that text. Try again in a moment.",
	CUSTODY_CELL_UNAVAILABLE = "This server has no custody cell, so nobody can be booked here.",
	CHARACTER_UNAVAILABLE = "The detainee has no character loaded to book.",
	PROFILE_UNAVAILABLE = "The detainee's save has not loaded yet.",
	NO_VALID_OFFENCES = "None of those offences were recognised.",
	HANDCUFFS_MUST_BE_EQUIPPED = "Hold your handcuffs before using them.",
	NOT_MANAGING_OFFICER = "Only the officer who put these cuffs on can take them off.",
	OFFICER_ALREADY_ESCORTING = "You already have hold of someone. Let go of them first.",
	ALREADY_ESCORTED = "Another officer already has hold of this detainee.",
	CUSTODY_SEAT_UNAVAILABLE = "No custody seat nearby. Bring a marked vehicle closer.",
	INVALID_SEARCH_POWER = "Choose a search power before recording the search.",
	INVALID_CUFF_MODE = "Those handcuffs were used in a way the server does not recognise.",
	INVALID_CUFF_POSITION = "The cuffs cannot go there.",
	INVALID_CUSTODY_ACTION = "That custody action no longer exists.",
	NO_ACTIVE_CUSTODY_SENTENCE = "You are not serving custody time.",
	NO_EARLY_RELEASE_CREDITS = "You have no early release credits left.",
	PUBLIC_SERVER_REQUIRED = "Early release is only offered on public servers.",
	NO_SESSION = "Your save has not loaded yet.",
	CIVILIAN_SPAWN_NOT_CONFIGURED = "This server has nowhere to release people to.",
	CIVILIAN_ROLE_ASSIGNMENT_FAILED = "You could not be put back on the street. Tell a moderator.",
	CIVILIAN_SPAWN_FAILED = "You could not be put back on the street. Tell a moderator.",
	CHARACTER_SPAWN_FAILED = "Your character could not be moved. Tell a moderator.",
}

-- Readable names for the search powers the server accepts. The detainee was
-- being told they had been searched under the raw wire value, which is not a
-- sentence anybody reads.
local SEARCH_POWERS = {
	PACE_S1 = "stop and search powers",
	CJPOA_S60 = "powers to search for offensive weapons",
	FIREARMS_S47 = "powers to search for firearms",
	PACE_S32_POST_ARREST = "post-arrest search powers",
	PACE_S54_CUSTODY = "custody search powers",
}

function CustodyController:Init(context: any)
	self.context = context
end

-- The one place that turns a refused custody response into something to do
-- about it. PublicSafetyController runs the restraint actions and this file runs
-- the booking, and the two must not be able to describe the same refusal
-- differently, so the table lives here and that controller asks for it.
function CustodyController:Explain(response: any, fallback: string): string
	if type(response) ~= "table" then
		return fallback
	end
	local explained = REFUSALS[tostring(response.Code)]
	if explained then
		return explained
	end
	return if type(response.Message) == "string" and response.Message ~= ""
		then response.Message
		else fallback
end

function CustodyController:_notify(message: string, title: string, level: string?)
	self.context.Controllers.NotificationController:Show(message, title, level)
end

function CustodyController:_selectedCodeList(): { string }
	local result = {}
	for code, selected in self.selectedCodes do
		if selected then
			table.insert(result, code)
		end
	end
	table.sort(result)
	return result
end

function CustodyController:_selectedSeconds(): number
	local total = 0
	for _, offence in self.policy do
		if self.selectedCodes[offence.Code] then
			total += math.max(0, tonumber(offence.Seconds) or 0)
		end
	end
	return total
end

function CustodyController:Start()
	self.bookingGeneration = 0
	self.peakRemaining = 0
	self:_mountStatus()
	self:_mountBooking()
	-- Deferred: the serial client Start sequence must not block on an endpoint
	-- the server may not have registered yet.
	task.spawn(function()
		self:_refreshPolicyMetadata()
		self:_refreshPolicy()
		self:_updateStatus()
		self:_refreshSummary()
	end)

	self:_watchDetention()
	self:_refreshAccess(nil)
	table.insert(
		self.connections,
		self.context.Events.DutyChanged.Event:Connect(function(duty)
			self:_refreshAccess(duty)
		end)
	)
	-- Booking describes a person standing in front of this character. Losing the
	-- character ends that, and leaving the screen up over a respawn left an
	-- officer looking at a form whose every button the server would refuse.
	table.insert(
		self.connections,
		Players.LocalPlayer.CharacterRemoving:Connect(function()
			self:_closeBooking()
		end)
	)
	table.insert(
		self.connections,
		self.context.Events.StartMenuChanged.Event:Connect(function()
			self:_closeBooking()
		end)
	)
	-- Credits bought from the banner arrive through Roblox rather than through
	-- our own reply, so the button relabels itself from a fresh policy read
	-- instead of staying on the price of something already paid for.
	table.insert(
		self.connections,
		MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, _, purchased)
			if purchased and userId == Players.LocalPlayer.UserId then
				task.spawn(function()
					self:_refreshPolicyMetadata()
					self:_updateStatus()
				end)
			end
		end)
	)

	local remote = self.context.Controllers.NetworkController:ResolveEvent("CustodyChanged")
	if remote then
		table.insert(
			self.connections,
			remote.OnClientEvent:Connect(function(payload)
				if type(payload) ~= "table" then
					return
				end
				if payload.Kind == "State" then
					-- The only message that names the officer. It arrives with the cuffs,
					-- and going unhandled was why the arrest had no author.
					local officer = if payload.State
						then Players:GetPlayerByUserId(tonumber(payload.State.OfficerUserId) or 0)
						else nil
					self.detainedByName = if officer then officer.DisplayName else nil
					self:_updateStatus()
				elseif payload.Kind == "Caution" then
					self.context.Controllers.NotificationController:Show(
						payload.Text .. "\n\n" .. payload.SimulationNotice,
						"Arrest caution"
					)
				elseif payload.Kind == "SearchNotice" then
					local power = SEARCH_POWERS[tostring(payload.Power)]
					self.context.Controllers.NotificationController:Show(
						if power
							then "An officer has searched you under " .. power .. "."
							else "An officer has recorded a search of you.",
						"Searched"
					)
				elseif payload.Kind == "EarlyRelease" then
					self.policyMetadata.EarlyReleaseCredits = payload.Credits or 0
					self:_announceRelease(
						"Released early. Your criminal record still shows the booking.",
						"Released"
					)
					self:_updateStatus()
				end
			end)
		)
	end

	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Custody", function(layout)
		self.statusScale.Scale = math.min(
			layout.HudScale,
			self.context.Controllers.UIOrchestrator:FitScale(layout, Vector2.new(468, 104), 20)
		)
		-- This interface is mounted with CoreUISafeInsets, so its own origin is
		-- already below the native top bar. Adding NativeTop again pushed the
		-- banner a whole top bar further down the screen.
		self.statusBanner.Position = UDim2.new(0.5, 0, 0, 10)
	end)
end

function CustodyController:Destroy()
	self.bookingGeneration = (self.bookingGeneration or 0) + 1
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	table.clear(self.chips)
	if self.unbindLayout then
		self.unbindLayout()
	end
	if self.bookingGui then
		self.bookingGui:Destroy()
		self.bookingGui = nil
	end
	if self.statusGui then
		self.statusGui:Destroy()
		self.statusGui = nil
	end
end

return CustodyController
