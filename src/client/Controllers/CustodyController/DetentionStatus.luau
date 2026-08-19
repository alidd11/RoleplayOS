--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)
local Tokens = Utils.Tokens
local C, T = Utils.Colour, Utils.Text
local formatTime = Utils.formatTime
local text = Utils.text
local button = Utils.button
local outline = Utils.outline

return function(CustodyController)
	-- What is happening to the player it is happening to.
	--
	-- A detainee previously got nothing at all: the cuff event the server sends them
	-- was never handled here, so the whole experience of being arrested was a
	-- character that stopped answering the controls, with no statement anywhere on
	-- screen of who had done it, whether it would end, or what they could do. That
	-- is the single most likely moment for somebody to close the game, so it is the
	-- one screen in this file that is never optional.
	function CustodyController:_mountStatus()
		local gui = Instance.new("ScreenGui")
		gui.Name = "RoleplayOSCustodyStatus"
		gui:SetAttribute("RoleplayOSManagedUI", true)
		gui.ResetOnSpawn = false
		gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
		-- Anchored to a screen edge, so it must stay clear of notches, rounded
		-- corners and home indicators rather than being clipped by them.
		gui.ClipToDeviceSafeArea = true
		gui.DisplayOrder = 22
		gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
		self.statusGui = gui

		local banner = Instance.new("Frame")
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.Size = UDim2.fromOffset(468, 104)
		banner.BackgroundColor3 = C.surface
		banner.BorderSizePixel = 0
		banner.Visible = false
		banner.Parent = gui
		outline(banner)
		self.statusBanner = banner
		local bannerScale = Instance.new("UIScale")
		bannerScale.Parent = banner
		self.statusScale = bannerScale

		local rule = Instance.new("Frame")
		rule.Size = UDim2.new(1, 0, 0, 2)
		rule.BackgroundColor3 = C.accent
		rule.BorderSizePixel = 0
		rule.Parent = banner
		self.statusRule = rule

		local kind = text(banner, "IN HANDCUFFS", T.section, C.accent, true)
		kind.Position = UDim2.fromOffset(Tokens.Spacing.pad, 12)
		kind.Size = UDim2.new(1, -180, 0, 14)
		self.statusKind = kind

		local headline = text(banner, "", T.subtitle, C.text, true)
		headline.Position = UDim2.fromOffset(Tokens.Spacing.pad, 30)
		headline.Size = UDim2.new(1, -180, 0, 20)
		headline.TextTruncate = Enum.TextTruncate.AtEnd
		self.statusHeadline = headline

		local detail = text(banner, "", T.dense, C.muted)
		detail.Position = UDim2.fromOffset(Tokens.Spacing.pad, 52)
		detail.Size = UDim2.new(1, -180, 0, 40)
		detail.TextWrapped = true
		detail.TextYAlignment = Enum.TextYAlignment.Top
		self.statusDetail = detail

		local clock = text(banner, "00:00", 26, C.accent, true)
		clock.AnchorPoint = Vector2.new(1, 0)
		clock.Position = UDim2.new(1, -Tokens.Spacing.pad, 0, 14)
		clock.Size = UDim2.fromOffset(148, 32)
		clock.TextXAlignment = Enum.TextXAlignment.Right
		self.statusClock = clock

		local earlyRelease = button(banner, "EARLY RELEASE", C.accentFill)
		earlyRelease.AnchorPoint = Vector2.new(1, 0)
		earlyRelease.Position = UDim2.new(1, -Tokens.Spacing.pad, 0, 52)
		earlyRelease.Size = UDim2.fromOffset(148, 32)
		earlyRelease.TextSize = T.dense
		earlyRelease.Visible = false
		self.earlyRelease = earlyRelease

		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(0, 1)
		track.Position = UDim2.fromScale(0, 1)
		track.Size = UDim2.new(1, 0, 0, 3)
		track.BackgroundColor3 = C.raised
		track.BorderSizePixel = 0
		track.Visible = false
		track.Parent = banner
		self.statusTrack = track
		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = C.accent
		fill.BorderSizePixel = 0
		fill.Parent = track
		self.statusFill = fill

		table.insert(
			self.connections,
			earlyRelease.Activated:Connect(function()
				self:_useEarlyRelease()
			end)
		)
	end

	function CustodyController:_useEarlyRelease()
		local credits =
			math.max(0, math.floor(tonumber(self.policyMetadata.EarlyReleaseCredits) or 0))
		if credits > 0 then
			local response =
				self.context.Controllers.NetworkController:Request("UseEarlyReleaseCredit", {})
			if response.Data then
				self.policyMetadata = response.Data
			end
			if response.Success then
				self:_announceRelease(
					"Released early. Your criminal record still shows the booking.",
					"Released"
				)
			else
				self:_notify(
					self:Explain(response, "The release credit could not be used."),
					"Custody",
					"Danger"
				)
			end
			self:_updateStatus()
			return
		end
		local product = (self.policyMetadata.EarlyReleaseProducts or {})[1]
		local productId = tonumber(product and product.ProductId) or 0
		if productId > 0 then
			MarketplaceService:PromptProductPurchase(Players.LocalPlayer, productId)
		else
			self:_notify("Early release is not on sale on this server.", "Custody")
		end
	end

	function CustodyController:_refreshPolicyMetadata()
		local response = self.context.Controllers.NetworkController:Request("GetCustodyPolicy", {})
		if response.Success and response.Data then
			self.policy = response.Data.Offences or {}
			self.policyMetadata = response.Data
		end
	end

	-- Both halves of a release can reach the client, in either order: the sentence
	-- attribute drops to zero and, for a credit, a CustodyChanged event explains
	-- why. Whichever arrives first speaks and the other stays quiet, so a player is
	-- told once and told the more specific of the two things.
	function CustodyController:_announceRelease(message: string, title: string)
		local now = os.clock()
		if self.releaseAnnouncedAt and now - self.releaseAnnouncedAt < 3 then
			return
		end
		self.releaseAnnouncedAt = now
		self:_notify(message, title, "Success")
	end

	function CustodyController:_updateStatus()
		local player = Players.LocalPlayer
		local remaining = math.max(
			0,
			math.floor(tonumber(player:GetAttribute("RoleplayOSCustodyRemaining")) or 0)
		)
		local serving = remaining > 0
		local cuffed = player:GetAttribute("RoleplayOSCuffed") == true
		local escorted = player:GetAttribute("RoleplayOSEscorted") == true
		self.statusBanner.Visible = serving or cuffed
		if not self.statusBanner.Visible then
			self.peakRemaining = 0
			return
		end

		if serving then
			self.peakRemaining = math.max(self.peakRemaining or 0, remaining)
			self.statusKind.Text = "IN CUSTODY"
			self.statusKind.TextColor3 = C.accent
			self.statusRule.BackgroundColor3 = C.accent
			self.statusHeadline.Text = "You are in the cells"
			self.statusDetail.Text = "You are let out automatically when this reaches zero. "
				.. "Leaving the server does not shorten it."
			self.statusClock.Visible = true
			self.statusClock.Text = formatTime(remaining)
			self.statusTrack.Visible = true
			local peak = math.max(self.peakRemaining or remaining, 1)
			self.statusFill.Size = UDim2.fromScale(math.clamp(1 - remaining / peak, 0, 1), 1)
		else
			self.peakRemaining = 0
			self.statusKind.Text = "IN HANDCUFFS"
			self.statusKind.TextColor3 = C.warning
			self.statusRule.BackgroundColor3 = C.warning
			self.statusHeadline.Text = if self.detainedByName
				then "Detained by " .. self.detainedByName
				else "You have been detained"
			self.statusDetail.Text = if escorted
				then "An officer is walking you. You cannot move or get out of a vehicle "
					.. "until they let go, take the cuffs off, or book you in."
				else "You cannot run or jump. An officer has to take the cuffs off or book "
					.. "you into custody before you can move freely again."
			self.statusClock.Visible = false
			self.statusTrack.Visible = false
		end

		local credits =
			math.max(0, math.floor(tonumber(self.policyMetadata.EarlyReleaseCredits) or 0))
		local single = (self.policyMetadata.EarlyReleaseProducts or {})[1]
		self.earlyRelease.Visible = serving and self.policyMetadata.ServerKind == "Public"
		self.earlyRelease.Text = if credits > 0
			then string.format("USE CREDIT  ·  %d", credits)
			else string.format(
				"BUY RELEASE  ·  %d R$",
				tonumber(single and single.PriceRobux) or 19
			)

		local wide = if serving then -180 else -Tokens.Spacing.pad * 2
		self.statusKind.Size = UDim2.new(1, wide, 0, 14)
		self.statusHeadline.Size = UDim2.new(1, wide, 0, 20)
		self.statusDetail.Size = UDim2.new(1, wide, 0, 40)
	end

	-- Announces the transitions rather than only the state, because a banner
	-- appearing at the top of the screen is easy to miss at the exact moment the
	-- player is trying to work out why their character has stopped moving.
	function CustodyController:_watchDetention()
		local player = Players.LocalPlayer
		local function react()
			local remaining = math.max(
				0,
				math.floor(tonumber(player:GetAttribute("RoleplayOSCustodyRemaining")) or 0)
			)
			local cuffed = player:GetAttribute("RoleplayOSCuffed") == true
			local previousRemaining = self.lastRemaining
			local previousCuffed = self.lastCuffed
			self.lastRemaining = remaining
			self.lastCuffed = cuffed
			if cuffed then
				self.lastCuffedAt = os.clock()
			end
			-- A sentence that starts moments after this character was in handcuffs is
			-- a booking that just happened; one that starts without that is this
			-- character rejoining partway through time it was already serving. The
			-- two need opposite wording, and the cuffs coming off and the sentence
			-- appearing can replicate in either order, so the timestamp decides
			-- rather than the current value of the cuffed attribute.
			local justBooked = cuffed
				or (self.lastCuffedAt ~= nil and os.clock() - self.lastCuffedAt < 5)

			if cuffed and previousCuffed == false then
				self:_notify(
					if self.detainedByName
						then self.detainedByName
							.. " has put you in handcuffs. You cannot move away until an officer "
							.. "takes them off or books you into custody."
						else "You have been put in handcuffs. You cannot move away until an officer "
							.. "takes them off or books you into custody.",
					"Detained",
					"Danger"
				)
			elseif previousCuffed == true and not cuffed then
				-- Deferred by a frame: booking takes the cuffs off and starts a sentence
				-- in the same server call, and telling somebody they are free to go
				-- immediately before locking them in a cell is worse than saying nothing.
				task.defer(function()
					local serving = math.max(
						0,
						math.floor(tonumber(player:GetAttribute("RoleplayOSCustodyRemaining")) or 0)
					) > 0
					if not serving then
						self.detainedByName = nil
						self:_notify(
							"The handcuffs are off. You are free to go.",
							"Released",
							"Success"
						)
					end
				end)
			end

			if remaining > 0 and (previousRemaining == nil or previousRemaining == 0) then
				self.detainedByName = nil
				self:_notify(
					if justBooked
						then string.format(
							"You have been booked into custody and moved to a cell. %s to serve.",
							formatTime(remaining)
						)
						else string.format(
							"You are still serving custody time from earlier. %s left.",
							formatTime(remaining)
						),
					"In custody",
					"Danger"
				)
			elseif previousRemaining ~= nil and previousRemaining > 0 and remaining == 0 then
				-- Slightly behind the attribute, so a credit release gets to explain
				-- itself first. The two arrive on different channels and their order is
				-- not guaranteed.
				task.delay(0.35, function()
					self:_announceRelease(
						"You have served your time and been let out of the cells.",
						"Released"
					)
				end)
			end
			self:_updateStatus()
		end
		for _, attribute in
			{ "RoleplayOSCustodyRemaining", "RoleplayOSCuffed", "RoleplayOSEscorted" }
		do
			table.insert(
				self.connections,
				player:GetAttributeChangedSignal(attribute):Connect(react)
			)
		end
		react()
	end
end
