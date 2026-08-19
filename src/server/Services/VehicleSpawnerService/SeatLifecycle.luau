--!strict

local RigMechanics = require(script.Parent.RigMechanics)

return function(VehicleSpawnerService)
	-- Removes the player's vehicle, whatever the reason.
	function VehicleSpawnerService:Remove(userId: number)
		local vehicle = self.active[userId]
		-- Banked before the entry is cleared, and cleared before the destroy.
		--
		-- These two lines were the other way round, and it cost every driver their
		-- last stretch of mileage. The Destroying handler installed at spawn is
		-- guarded on `self.active[userId] == vehicle`, so clearing the entry first
		-- made that test false before the handler ran: the final flush that exists
		-- precisely for this never happened, and self.telemetry kept the destroyed
		-- model and its VehicleId for the life of the server, one entry per person who
		-- had ever driven.
		--
		-- This is the path taken when a player dies and when they leave, so the loss
		-- was up to fifteen seconds of driving every time, which is most of the reason
		-- an odometer would ever look wrong. The replacement path in Spawn already had
		-- the order right.
		self:_persistTelemetry(userId, true)
		self.telemetry[userId] = nil
		self.active[userId] = nil
		if vehicle and vehicle.Parent then
			RigMechanics.ejectOccupants(vehicle)
			vehicle:Destroy()
		end
	end

	-- Watches one player's seat, and cleans up after whatever they were riding.
	function VehicleSpawnerService:_watchSeat(player: Player)
		local previous = self.seatConnections[player.UserId]
		if previous then
			previous:Disconnect()
			self.seatConnections[player.UserId] = nil
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local lastVehicle: Instance? = nil
		self.seatConnections[player.UserId] = humanoid
			:GetPropertyChangedSignal("SeatPart")
			:Connect(function()
				local seat = humanoid.SeatPart
				if seat then
					local mounted = RigMechanics.vehicleOf(seat)
					lastVehicle = mounted
					-- After the kit has had its go, so this picks up only what its broken
					-- R15 path left behind rather than racing it.
					task.delay(0.4, function()
						local body = player.Character
						if not body or humanoid.SeatPart ~= seat or not mounted.Parent then
							return
						end
						local moved = RigMechanics.anchorAccessoriesToProxy(body, mounted)
						if moved > 0 then
							self.context.Logger:Info(
								"Accessories hung on the vehicle's proxy head",
								{
									UserId = player.UserId,
									Vehicle = mounted.Name,
									AccessoriesMoved = moved,
								}
							)
						end
					end)
					return
				end
				-- Just got off. Deferred by a frame so Roblox has finished removing
				-- its own seat weld before we look at what is left.
				local vehicle = lastVehicle
				lastVehicle = nil
				if not vehicle or not vehicle.Parent then
					return
				end
				task.defer(function()
					local body = player.Character
					if not body or not vehicle.Parent then
						return
					end
					-- Accessories first, then the rest of the joints.
					--
					-- Order matters: RigMechanics.detachRider destroys every joint spanning the rider
					-- and the vehicle, and an accessory the kit left welded to its dummy
					-- head is one of those. Cutting first would leave the hat attached to
					-- nothing, which is a different way of losing it.
					local restored = RigMechanics.reattachAccessories(body, vehicle)
					local removed = RigMechanics.detachRider(body, vehicle)
					-- Last, because it is the only one that puts joints back rather than
					-- taking them away, and it must not have its work cut by the two
					-- above.
					local repaired = RigMechanics.restoreRig(body)
					if removed > 0 or restored > 0 or repaired > 0 then
						self.context.Logger:Info("Rider released from a vehicle that kept hold", {
							UserId = player.UserId,
							Vehicle = vehicle.Name,
							JointsRemoved = removed,
							AccessoriesRestored = restored,
							RigJointsRepaired = repaired,
						})
					end
				end)
			end)
	end
end
