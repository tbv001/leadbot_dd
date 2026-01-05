if SERVER then AddCSLuaFile() end

ENT.Base = "base_nextbot"
ENT.Type = "nextbot"

function ENT:Initialize()
	if CLIENT then return end

	self:SetModel("models/player.mdl")
	self:SetNoDraw(!GetConVar("developer"):GetBool())
	self:SetSolid(SOLID_NONE)

	self.PosGen = nil
	self.NextJump = -1
	self.NextDuck = 0
	self.cur_segment = 2
	self.Target = nil
	self.CurTargetPos = nil
	self.LastSegmented = 0
	self.ForgetTarget = 0
	self.NextCenter = 0
	self.LookAt = Angle(0, 0, 0)
	self.LookAtTime = 0
	self.goalPos = Vector(0, 0, 0)
	self.strafeAngle = 0
	self.nextStuckJump = 0
	self.NextCombatMove = 0
	self.CombatStrafeDir = 0
	self.NextAttack = 0
	self.NextAttack2 = 0
	self.NextAttack2Delay = 0
	self.NextChangeSpell = 0
	self.NextLadderJump = 0
	self.NextDiveTime = 0
	self.ShootReactionTime = 0
	self.NextSlideTime = 0
	self.CurSlideTime = 0

	if LeadBot.AddControllerOverride then
		LeadBot.AddControllerOverride(self)
	end
end

function ENT:ChasePos()
	self.P = Path("Follow")
	self.P:SetMinLookAheadDistance(300)
	self.P:SetGoalTolerance(20)
	self.P:Compute(self, self.PosGen)

	if !self.P:IsValid() then return end

	while self.P:IsValid() do
		if self.PosGen then
			self.P:Compute(self, self.PosGen)
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
			self:ChasePos({})
		end

		coroutine.yield()
	end
end