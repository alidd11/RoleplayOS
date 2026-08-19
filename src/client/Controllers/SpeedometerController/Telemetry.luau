--!strict
local Players = game:GetService("Players")
local Utils = require(script.Parent.Utils)
local NEEDLE_TAU = Utils.NEEDLE_TAU
local TACHO_TAU = Utils.TACHO_TAU
local isTelemetry = Utils.isTelemetry

return function(SpeedometerController)
	-- The chassis's own values folder.
	--
	-- This used to take whatever FindFirstChild returned for the name, and that
	-- walks the tree in its own order and stops at the first hit. On the Honda it
	-- stopped at the lighting addon's folder every time: no Velocity, no RPM, no
	-- Gear, no PBrake. So the cluster fell back to reading the seat's own assembly
	-- velocity, the gear and rev counter had nothing to show, and the handbrake
	-- badge could never light because the value it watches was in a folder nobody
	-- was looking at. The two vehicles that did work only worked because they
	-- happen to carry one Values folder each.
	--
	-- Nearest wins where telemetry is present, so a seat-level folder still beats a
	-- deeper one, but a folder that cannot answer the question is never chosen over
	-- one that can.
	function SpeedometerController:_chassisValues(seat: BasePart): Folder?
		local settings = self.settings
		local name = settings.ValuesFolderName
		local nearby =
			{ seat:FindFirstChild(name), seat.Parent and seat.Parent:FindFirstChild(name) }
		for _, candidate in nearby do
			if candidate and candidate:IsA("Folder") and isTelemetry(candidate, settings) then
				return candidate
			end
		end
		local vehicle = seat:FindFirstAncestorOfClass("Model")
		if not vehicle then
			return nil
		end
		local fallback: Folder? = nil
		for _, descendant in vehicle:GetDescendants() do
			if descendant.Name == name and descendant:IsA("Folder") then
				if isTelemetry(descendant, settings) then
					return descendant
				end
				fallback = fallback or descendant
			end
		end
		-- Nothing published telemetry. The caller copes: speed falls back to the
		-- seat's assembly velocity and the rest of the cluster stays blank, which is
		-- the honest reading for a vehicle that reports nothing.
		return fallback
	end

	-- Moves the needle and the number one frame closer to the last sample.
	--
	-- Exponential easing rather than a fixed step per frame, so the needle covers a
	-- large gap quickly and a small one gently, which is how a real one behaves. The
	-- alpha is derived from dt through exp rather than used directly, because a
	-- constant fraction per frame would make the needle settle at a different speed
	-- on a 144Hz screen than on a 30Hz one.
	--
	-- The number is driven from the same eased value as the needle rather than from
	-- the raw sample. That is deliberate: a digital readout that jumps to 58 while
	-- the needle is still passing 40 reads as two instruments disagreeing.
	function SpeedometerController:_animate(dt: number)
		local target = self.targetMph
		-- Nothing sampled yet. Drawing a zero here would make the needle wind up from
		-- the end stop on the first frame after the cluster appears.
		if target == nil then
			return
		end
		local shown = self.shownMph
		if shown == nil then
			-- First sample since getting in. Start where the vehicle already is.
			shown = target
		end
		shown += (target - shown) * (1 - math.exp(-dt / NEEDLE_TAU))
		-- Snapped once it is within a twentieth of a mph, so the needle actually
		-- comes to rest instead of creeping toward the target forever and rewriting
		-- two properties every frame of a parked car.
		if math.abs(target - shown) < 0.05 then
			shown = target
		end
		self.shownMph = shown

		-- Capped at three digits for the label only. The needle clamps separately in
		-- _paintSweep, so a vehicle above the dial's range parks the needle at the end
		-- stop while the number keeps counting, exactly as a real cluster does.
		self:_setText(self.speed, tostring(math.min(math.floor(shown + 0.5), 999)))
		self:_paintSweep(shown / math.max(self.settings.TopSpeedMph, 1))

		-- The rev ring, on its own shorter time constant.
		local targetRpm = self.targetRpm
		if targetRpm == nil then
			self:_setTachoVisible(false)
		else
			self:_setTachoVisible(true)
			local shownRpm = self.shownRpm
			if shownRpm == nil then
				shownRpm = targetRpm
			end
			shownRpm += (targetRpm - shownRpm) * (1 - math.exp(-dt / TACHO_TAU))
			if math.abs(targetRpm - shownRpm) < 1 then
				shownRpm = targetRpm
			end
			self.shownRpm = shownRpm
			self:_paintTacho(shownRpm / math.max(self.settings.Redline, 1))
		end
	end

	-- Puts the needle where the vehicle already is, without sweeping to it.
	--
	-- Getting into a moving car should not show the needle winding up from zero: the
	-- car was doing forty before the cluster appeared, and animating that is the
	-- gauge lying about the first half second.
	function SpeedometerController:_snapToSeat()
		self.targetMph = nil
		self.shownMph = nil
		self.targetRpm = nil
		self.shownRpm = nil
		-- Forces the next _setTachoVisible through, since the new vehicle may not have
		-- a tachometer where the last one did.
		self.tachoVisible = nil
		self.tachoLit = nil
	end

	-- The chassis's own gauge, removed wherever it turns up.
	--
	-- The spawner already takes this frame out of the vehicle, and that ought to be
	-- the end of it. It is done again here because the kit hands its interface to the
	-- driver at seat time and the two are not reliably ordered: whichever copy the
	-- client ends up holding, this catches it. Destroyed rather than hidden -- hiding
	-- was the old workaround and it left the script behind it running, writing a
	-- needle and a speed into an invisible frame for the whole drive.
	local STOCK_GAUGE_FRAMES = { "AC6_Stock_Gauges", "AC6C_Style_Gauges", "FH5_Gauge" }

	function SpeedometerController:_stripStockGauges()
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return
		end
		for _, descendant in playerGui:GetDescendants() do
			if descendant:IsA("GuiObject") and table.find(STOCK_GAUGE_FRAMES, descendant.Name) then
				descendant:Destroy()
			end
		end
	end

	function SpeedometerController:_watch(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if not humanoid or not humanoid:IsA("Humanoid") then
			return
		end
		table.insert(
			self.connections,
			humanoid:GetPropertyChangedSignal("SeatPart"):Connect(function()
				self.seat = if humanoid.SeatPart and humanoid.SeatPart:IsA("VehicleSeat")
					then humanoid.SeatPart
					else nil
				self.frame.Visible = self.seat ~= nil
				-- Deferred, because the kit parents its interface after the seat change.
				if self.seat then
					self:_stripStockGauges()
					task.delay(0.4, function()
						self:_stripStockGauges()
					end)
					task.delay(1.5, function()
						self:_stripStockGauges()
					end)
				end
				-- Discards the previous vehicle's needle position, so the first sample
				-- in this one is adopted rather than swept to.
				self:_snapToSeat()
				-- The chassis's own gauge strip used to be hidden here on the way in and
				-- put back on the way out, because it parented a second speedometer into
				-- the driver's PlayerGui reading the same number in a different typeface.
				-- The spawner now removes that frame from the vehicle outright, so there
				-- is nothing left to hide and the script behind it is no longer running.
			end)
		)
	end
end
