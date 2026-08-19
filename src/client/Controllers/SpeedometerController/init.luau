--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.RoleplayOS.Config.Config)

local Utils = require(script.Utils)
local FUEL_ENABLED = Utils.FUEL_ENABLED
local CLUSTER_SIZE = Utils.CLUSTER_SIZE
local SAMPLE_INTERVAL = Utils.SAMPLE_INTERVAL
local C = Utils.C
local readValue = Utils.readValue
local readFirstValue = Utils.readFirstValue
local ancestorAttribute = Utils.ancestorAttribute
local readPath = Utils.readPath
local readsOn = Utils.readsOn
local speedMph = Utils.speedMph

local SpeedometerController = { connections = {}, seat = nil, accumulator = 0 }

local Telemetry = require(script.Telemetry)
local PanelUI = require(script.PanelUI)

-- Each of these attaches a group of methods onto SpeedometerController
-- directly (they only need `self`, not a lexical upvalue) - the same split
-- used across this session. Order does not matter: nothing here runs until a
-- caller invokes a method, well after every group is attached.
Telemetry(SpeedometerController)
PanelUI(SpeedometerController)

function SpeedometerController:Init(context: any)
	self.context = context
	self.settings = Config.Chassis
end

function SpeedometerController:Start()
	self:_mount()
	self.unbindLayout = self.context.Controllers.UIOrchestrator:Bind("Speedometer", function(layout)
		local touch = layout.InputMode == "Touch"
		local compactTouch = touch and layout.Compact
		self.frameScale.Scale = if compactTouch
			then math.min(layout.HudScale, 0.62)
			else layout.HudScale
		self.frame.AnchorPoint = Vector2.new(0.5, 1)
		-- Sits directly above the equipped tools.
		--
		-- This used to measure from HotbarBottom, which a vehicle inflates to 112 to
		-- clear the driving pedals. The pedals are touch-only, so on a desktop that
		-- reserve protects nothing: the cluster hung about fifty pixels above the
		-- tools with a band of empty screen beneath it. ToolbarBottom is the tools
		-- bar on its own, so the gap below the dial is now the ten pixels intended
		-- rather than ten plus a reserve for controls that were never drawn.
		--
		-- Touch still measures from HotbarBottom and adds the pedal height, because
		-- there the controls genuinely are on screen. Every touch device, not just
		-- the compact ones -- a tablet has pedals too, and the old test sent it down
		-- the desktop path and put the cluster underneath them.
		--
		-- UIScale pivots about the AnchorPoint, not the authored origin, so the
		-- anchored bottom edge stays put at any scale and needs no compensation.
		-- The previous code compensated anyway, which pushed compact screens too
		-- high by however much the scale differed from one.
		local bottomGap = if touch
			then layout.HotbarBottom + Config.DrivingControls.PedalSize + 24
			else layout.ToolbarBottom + 10
		self.frame.Position = UDim2.new(0.5, 0, 1, -bottomGap)
		-- One authored size, scaled by the interface factor, rather than a second
		-- set of measurements for compact screens that has to be kept in step.
		self.frame.Size = UDim2.fromOffset(CLUSTER_SIZE.X, CLUSTER_SIZE.Y)
	end)
	local player = Players.LocalPlayer
	if player.Character then
		self:_watch(player.Character)
	end
	table.insert(
		self.connections,
		player.CharacterAdded:Connect(function(character)
			self.seat = nil
			self.frame.Visible = false
			self:_watch(character)
		end)
	)
	table.insert(
		self.connections,
		RunService.RenderStepped:Connect(function(dt)
			local seat = self.seat
			if not seat then
				return
			end
			-- Every frame, regardless of whether the chassis was read this one. The
			-- needle's smoothness is the whole point of the split.
			self:_animate(dt)

			self.accumulator += dt
			if self.accumulator < SAMPLE_INTERVAL then
				return
			end
			-- Subtracted rather than zeroed, so a long frame does not throw away the
			-- overshoot and slowly drift the sample rate.
			self.accumulator -= SAMPLE_INTERVAL
			local values = self:_chassisValues(seat)
			-- Unrounded, and only a target. The animation step below owns what is
			-- actually drawn; rounding here would quantise the needle to whole mph
			-- and put back a coarser version of the stepping this replaced.
			self.targetMph = speedMph(seat, values)
			-- nil rather than zero where the chassis reports nothing, so the ring can
			-- tell "no tachometer fitted" apart from "engine idling".
			local rpm = readValue(values, self.settings.RpmValueName)
			self.targetRpm = if type(rpm) == "number" then math.max(rpm, 0) else nil

			-- The chassis knows its own gear, including reverse and each ratio,
			-- which throttle direction alone cannot tell apart. Fall back to
			-- throttle only where no chassis is present.
			local gear = readValue(values, self.settings.GearValueName)
			self:_setText(
				self.gear,
				if type(gear) == "number"
					then (if gear < 0 then "R" elseif gear == 0 then "N" else tostring(gear))
					elseif type(gear) == "string" and gear ~= "" then gear
					else (if seat.ThrottleFloat < -0.05
						then "R"
						elseif math.abs(seat.ThrottleFloat) > 0.05 then "D"
						else "N")
			)

			-- An unregistered vehicle shows nothing rather than a placeholder.
			-- "NO PLATE" reads as a fault the driver ought to do something about,
			-- when it only means this car was not spawned through the framework.
			local registration = seat:GetAttribute("RoleplayOSRegistration")
			-- Walked all the way up, like the fuel reading beneath. The odometer is
			-- written on the vehicle model and a seat is often two or three levels
			-- inside it, so checking only the seat and its immediate parent found
			-- nothing on exactly the vehicles that keep their seat in a subassembly.
			local mileage = ancestorAttribute(seat, "RoleplayOSMileage")
			local plated = type(registration) == "string" and registration ~= ""
			self.plate.Visible = plated
			if plated then
				self:_setText(
					self.plate,
					if type(mileage) == "number"
						then string.format("%s  ·  %.1f MI", registration, mileage)
						else registration :: string
				)
			end

			-- RoleplayOS fuel is authoritative. Existing authoring vehicles can
			-- still expose a chassis value for display; if neither exists the gauge
			-- reads unknown rather than silently disappearing.
			--
			-- Skipped entirely where the game has no fuel system, because then the
			-- strip was never built and there is nothing to write to.
			if FUEL_ENABLED then
				local fuel = ancestorAttribute(seat, "RoleplayOSFuel")
				if type(fuel) ~= "number" then
					for _, name in self.settings.FuelValueNames or {} do
						fuel = ancestorAttribute(seat, name)
						if type(fuel) == "number" then
							break
						end
					end
				end
				if type(fuel) ~= "number" then
					fuel = readFirstValue(values, self.settings.FuelValueNames)
				end
				self.fuelTrack.Visible = true
				self.fuelMark.Visible = true
				if type(fuel) == "number" then
					local level = fuel :: number
					if level >= 0 and level <= 1 then
						level *= 100
					end
					self:_setText(
						self.fuelMark,
						string.format("FUEL %d%%", math.floor(level + 0.5))
					)
					self.fuelFill.Size = UDim2.fromScale(math.clamp(level / 100, 0, 1), 1)
					self.fuelFill.BackgroundColor3 = if level <= 10
						then C.Danger
						elseif level <= 25 then C.Warn
						else C.Fuel
				else
					self:_setText(self.fuelMark, "FUEL --")
					self.fuelFill.Size = UDim2.fromScale(0, 1)
					self.fuelFill.BackgroundColor3 = C.Muted
				end
			end

			local handbrakeState = ancestorAttribute(seat, "RoleplayOSHandbrake")
			if handbrakeState == nil then
				for _, name in self.settings.HandbrakeValueNames or {} do
					handbrakeState = ancestorAttribute(seat, name)
					if handbrakeState ~= nil then
						break
					end
				end
			end
			if handbrakeState == nil then
				handbrakeState = readFirstValue(values, self.settings.HandbrakeValueNames)
			end
			local handbrakeOn = readsOn(handbrakeState)
			local handbrakeColour = if handbrakeOn then C.Danger else C.Muted
			self.handbrake.TextColor3 = handbrakeColour
			self.handbrakeStroke.Color = handbrakeColour

			-- Fitted, and intervening. Read straight from the chassis, so a vehicle
			-- that publishes neither leaves both lamps dark rather than pretending.
			-- Takes only the glyph now. The badge frame it used to fill is a bare
			-- container with nothing to paint.
			local function telltaleState(
				mark: TextLabel,
				fittedNames: { string },
				activeNames: { string }
			)
				local fitted = readsOn(readFirstValue(values, fittedNames))
				local active = readsOn(readFirstValue(values, activeNames))
				-- Only the glyph changes. Filling the box behind it was what made an
				-- intervening system look like a pressed button.
				mark.TextColor3 = if active then C.Warn elseif fitted then C.Muted else C.Track
				mark.TextTransparency = if active then 0 elseif fitted then 0.15 else 0.55
			end
			telltaleState(self.abs, self.settings.AbsValueNames, self.settings.AbsActiveValueNames)
			telltaleState(self.tcs, self.settings.TcsValueNames, self.settings.TcsActiveValueNames)

			-- The lighting addon's lamps.
			--
			-- Read straight off the BoolValues its own handler writes, so the cluster
			-- follows the indicators the driver is actually using rather than a second
			-- set of state that could disagree with the lamps on the car.
			local vehicle = seat:FindFirstAncestorOfClass("Model")
			local paths = self.settings.LightStatePaths
			local function lamp(mark: TextLabel, state: boolean?, lit: Color3)
				-- nil means this vehicle has no such lamp. Dark and fully faded, which
				-- is different from fitted-but-off: a van with a different lighting kit
				-- should not show a headlight tell-tale it cannot drive.
				if state == nil then
					mark.TextColor3 = C.Track
					mark.TextTransparency = 0.72
					return
				end
				mark.TextColor3 = if state then lit else C.Muted
				mark.TextTransparency = if state then 0 else 0.5
			end

			-- Hazards drive both arrows, because that is what pressing them does.
			local hazards = readPath(vehicle, paths.Hazards) == true
			lamp(
				self.indicatorLeft,
				if hazards then true else readPath(vehicle, paths.IndicatorLeft),
				C.Indicator
			)
			lamp(
				self.indicatorRight,
				if hazards then true else readPath(vehicle, paths.IndicatorRight),
				C.Indicator
			)
			lamp(self.headlight, readPath(vehicle, paths.Headlight), C.Indicator)
			lamp(self.mainBeam, readPath(vehicle, paths.MainBeam), C.Beam)
		end)
	)
end

function SpeedometerController:Destroy()
	for _, c in self.connections do
		c:Disconnect()
	end
	if self.gui then
		self.gui:Destroy()
	end
	if self.unbindLayout then
		self.unbindLayout()
	end
end

return SpeedometerController
