local AddCSLuaFile = AddCSLuaFile
local Vector = Vector
local IsValid = IsValid
local Path = Path
local coroutine = coroutine

if SERVER then AddCSLuaFile() end

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"

function ENT:Initialize()
	if CLIENT then return end

	self:SetModel("models/player.mdl")
	self:SetNoDraw(true)
	self:SetSolid(SOLID_NONE)

	self.PosGen = nil
	self.NextJump = -1
	self.NextDuck = 0
	self.cur_segment = 2
	self.Target = nil
	self.LastSegmented = 0
	self.ForgetTarget = 0
	self.LastSeenTarget = 0
	self.NextCenter = 0
	self.LookAt = Vector(0, 0, 0)
	self.LookAtTime = 0
	self.ForcedLookAt = false
	self.goalPos = Vector(0, 0, 0)
	self.nextStuckJump = 0
	self.NextCombatMove = 0
	self.CombatStrafeDir = 0
	self.NextAttack = 0
	self.NextAttack2 = 0
	self.NextAttack2Delay = 0
	self.NextChangeSpell = 0
	self.NextDiveTime = 0
	self.ShootReactionTime = 0
	self.NextSlideTime = 0
	self.CurSlideTime = 0
	self.NextNadeThrowTime = 0
	self.ForceShoot = false
	self.ForceCast = false
	self.NextPropCheck = 0
	self.LastStuckPos = nil
	self.NextStuckPosUpdate = 0
	self.StuckTime = 0
	self.StuckStrafeDir = 1
	self.NextStuckStrafe = 0
	self.CurrentLadder = nil
	self.PendingTarget = nil
	self.PendingProp = nil
	self.PendingForceShootOff = false
end

local function pathGenerator(ent, area, fromArea, ladder, elevator, length)
	if (not IsValid(fromArea)) then
		return 0
	else
		if (not ent.loco:IsAreaTraversable(area)) then
			return -1
		end

		local dist = 0

		if (IsValid(ladder)) then
			dist = ladder:GetLength()
		elseif (length > 0) then
			dist = length
		else
			dist = (area:GetCenter() - fromArea:GetCenter()):GetLength()
		end

		local cost = dist + fromArea:GetCostSoFar()

		if not IsValid(ladder) then
			local deltaZ = fromArea:ComputeAdjacentConnectionHeightChange(area)
			if (deltaZ >= ent.loco:GetStepHeight()) then
				if (deltaZ >= ent.loco:GetMaxJumpHeight()) then
					return -1
				end

				cost = cost + 5 * dist
			elseif (deltaZ < -ent.loco:GetDeathDropHeight()) then
				return -1
			end
		end

		return cost
	end
end

function ENT:ChasePos()
	self.P = Path("Follow")
	self.P:SetMinLookAheadDistance(300)
	self.P:SetGoalTolerance(20)
	self.P:Compute(self, self.PosGen, function(area, fromArea, ladder, elevator, length) return pathGenerator(self, area, fromArea, ladder, elevator, length) end)

	if not IsValid(self.P) then return end

	while IsValid(self.P) do
		if self.PosGen then
			self.P:Compute(self, self.PosGen, function(area, fromArea, ladder, elevator, length) return pathGenerator(self, area, fromArea, ladder, elevator, length) end)
			self.cur_segment = 2
		end

		coroutine.wait(0.1)
		coroutine.yield()
	end
end

function ENT:OnInjured()
	return false
end

function ENT:OnKilled()
	return false
end

function ENT:IsNPC()
	return false
end

function ENT:Health()
	return 0
end

function ENT:RunBehaviour()
	while (true) do
		if self.PosGen then
			self:ChasePos()
		end

		coroutine.yield()
	end
end