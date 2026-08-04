--!strict

-- Pays people for working.
--
-- The economy was spend-only: vehicles, food, furniture and property all took
-- money and nothing but reselling a vehicle ever returned any, so a balance
-- could only fall. Wages were defined on jobs but never actually paid.
--
-- Pay accrues while a shift is worked and is settled on an interval rather than
-- granted in a lump on clocking off, so leaving on a crash or a disconnect
-- costs at most one period. Every payment goes through the economy service, so
-- it is validated, recorded in the character's transaction history and audited
-- like any other movement of money.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local PayrollService = {}

function PayrollService:Init(context: any)
	self.context = context
	self.settings = context.Configuration.Payroll
	self.running = false
	-- Where each player was standing at the last payment, used to tell working
	-- from standing still.
	self.marks = {}
end

-- What an hour of this player's current work is worth, or nil when they are not
-- working. Emergency duty pays by department and rank; civilian employment pays
-- the job's own wage.
function PayrollService:_hourlyRate(player: Player): (number?, string?)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local duty = self.context.Services:Get("DutyService"):Get(player)
	if duty then
		local rate = self.settings.DepartmentHourlyRates[duty.DepartmentId]
			or self.settings.DefaultDepartmentHourlyRate
		-- Rank lives on the duty profile, not on the shift record, so reading it
		-- from the shift silently gave everyone the lowest rank's pay.
		local profile = session
			and session.Profile.DutyProfiles
			and session.Profile.DutyProfiles[duty.DutyProfileId]
		local rank = math.max(0, (tonumber(profile and profile.Rank) or 1) - 1)
		return rate + rank * self.settings.RankHourlyBonus, duty.DepartmentId
	end
	local character = session
		and session.ActiveCharacterId
		and session.Profile.Characters[session.ActiveCharacterId]
	-- Employment is a list of records rather than a single one, since a character
	-- keeps its history. The current job is the most recently started, so the
	-- list is read from the end.
	local records = if character and type(character.Employment) == "table"
		then character.Employment
		else {}
	local job = nil
	for index = #records, 1, -1 do
		local candidate = records[index]
		local jobId = candidate and candidate.JobId
		if type(jobId) == "string" and self.context.Configuration.Jobs[jobId] then
			job = self.context.Configuration.Jobs[jobId]
			break
		end
	end
	if job then
		-- BaseWage is what a completed task is worth, not an hourly rate, so it
		-- is not used as one. A job may declare an HourlyRate of its own.
		local hourly = tonumber(job.HourlyRate) or self.settings.CivilianHourlyRate
		return hourly, job.Id
	end
	return nil, nil
end

-- Paid work means being present, not being logged in. Without this a character
-- left standing in a locker room earns the same as one answering calls, which
-- is the quickest way to make every other price in the game meaningless.
function PayrollService:_hasWorked(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	local previous = self.marks[player.UserId]
	self.marks[player.UserId] = root.Position
	if not previous then
		-- First period after clocking on: nothing to compare against, so it is
		-- treated as worked rather than withheld.
		return true
	end
	return (root.Position - previous).Magnitude >= self.settings.MinimumMovementStuds
end

function PayrollService:_pay(player: Player)
	local session = self.context.Services:Get("DataService"):GetSession(player)
	local characterId = session and session.ActiveCharacterId
	if not characterId then
		return
	end
	local rate, source = self:_hourlyRate(player)
	if not rate or rate <= 0 then
		self.marks[player.UserId] = nil
		return
	end
	if not self:_hasWorked(player) then
		return
	end
	local amount = math.floor(rate * (self.settings.IntervalSeconds / 3600) + 0.5)
	if amount <= 0 then
		return
	end
	self.context.Services:Get("EconomyService"):Apply(player, {
		TransactionId = HttpService:GenerateGUID(false),
		CharacterId = characterId,
		Direction = "Credit",
		Amount = amount,
		Reason = "Wages",
		Metadata = { Source = source, Seconds = self.settings.IntervalSeconds },
	})
end

function PayrollService:Start()
	if not self.settings.Enabled then
		return
	end
	self.running = true
	self.connection = Players.PlayerRemoving:Connect(function(player)
		self.marks[player.UserId] = nil
	end)
	task.spawn(function()
		while self.running do
			task.wait(self.settings.IntervalSeconds)
			for _, player in Players:GetPlayers() do
				-- One player's payment failing must not stop the rest being paid.
				task.spawn(function()
					local ok, problem = pcall(function()
						self:_pay(player)
					end)
					if not ok then
						self.context.Logger:Warning(
							"Wage payment failed",
							{ UserId = player.UserId, Error = tostring(problem) }
						)
					end
				end)
			end
		end
	end)
end

function PayrollService:Destroy()
	self.running = false
	if self.connection then
		self.connection:Disconnect()
	end
	table.clear(self.marks)
end

return PayrollService
