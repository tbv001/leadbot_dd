local include = include
local Vector = Vector
local Angle = Angle
local concommand = concommand
local IsValid = IsValid
local pairs = pairs
local player = player
local string = string
local GetConVar = GetConVar
local MsgN = MsgN
local navmesh = navmesh
local CreateConVar = CreateConVar
local cvars = cvars
local tonumber = tonumber
local tobool = tobool
local math = math
local ents = ents
local game = game
local player_manager = player_manager
local table = table
local tostring = tostring
local CurTime = CurTime
local util = util
local team = team
local Color = Color
local ipairs = ipairs
local timer = timer
local VectorRand = VectorRand
local FrameTime = FrameTime
local LerpAngle = LerpAngle
local coroutine = coroutine
local hook = hook

include("ddbot/shared.lua")

local isTeamPlay = false
local entityLoaded = false
local nextQuotaCheck = 0
local objective
local gameType
local doorEnabled
local cachedPrimaries, cachedSecondaries
local cachedSpells, cachedPerks, cachedBuilds
local cv_QuotaVal = 0
local cv_AimSpeedMultVal = 1
local cv_FOVVal = math.cos(math.rad(50))
local cv_SlideEnabled = true
local cv_DiveEnabled = true
local cv_CombatMovementEnabled = true
local cv_CanUseGrenadesEnabled = true
local cv_CanUseSpellsEnabled = true
local cv_AimPredictionEnabled = true
local groundCheckOffset = Vector(0, 0, 58)
local dirCheckHullMins = Vector(-13, -13, -13)
local dirCheckHullMaxs = Vector(13, 13, 13)
local supportQueue = {}
local tempVector = Vector(0, 0, 0)
local tempAngle = Angle(0, 0, 0)
local visTrace1 = { mask = MASK_VISIBLE }
local visTrace2 = { mask = MASK_VISIBLE }
local visTrace3 = { mask = MASK_VISIBLE }
local propTrace = { mask = MASK_SHOT }
local hullTrace = { mask = MASK_PLAYERSOLID_BRUSHONLY }
local groundTrace = { mask = MASK_PLAYERSOLID_BRUSHONLY }
local doorTrace = {}


--[[----------------------------
    Commands & ConVars
----------------------------]]--

concommand.Add("dd_bot_add", function(ply, _, args)
    if not IsValid(ply) then
        return
    end

    if not ply:IsSuperAdmin() then
        return
    end

    DDBot.AddBot(args[1])
end, nil, "Adds a bot, with a custom name if specified")

concommand.Add("dd_bot_kick", function(ply, _, args)
    if not IsValid(ply) then
        return
    end

    if not ply:IsSuperAdmin() then
        return
    end

    if args[1] and args[1] ~= "all" then
        for k, v in pairs(player.GetBots()) do
            if string.find(v:GetName(), args[1]) then
                v:Kick()
                return
            end
        end
    else
        for k, v in pairs(player.GetBots()) do
            v:Kick()
        end
    end
end, nil, "Kicks all bots, kicks a bot by name if specified")

concommand.Add("dd_bot_generatenavmesh", function(ply, _, args)
    if not IsValid(ply) then
        return
    end

    if not ply:IsSuperAdmin() then
        return
    end

    if not GetConVar("sv_cheats"):GetBool() then
        MsgN("[DDBot] sv_cheats must be enabled to generate a navmesh!")
        return
    end

    if navmesh.IsGenerating() then
        MsgN("[DDBot] Navmesh generation is already in progress!")
        return
    end

    ply:ConCommand("nav_slope_limit 0.55")
    ply:ConCommand("nav_max_view_distance 1")
    ply:ConCommand("nav_quicksave 2")

    if ply:Alive() then
        ply:ConCommand("nav_mark_walkable")
    end

    ply:ConCommand("nav_generate")
end, nil, "Generates a cheap navmesh, requires sv_cheats 1")

local cv_AimSpeedMult = CreateConVar("dd_bot_aim_speed_mult", "1", {FCVAR_ARCHIVE}, "Sets the bot aim speed multiplier")
local cv_Slide = CreateConVar("dd_bot_slide", "1", {FCVAR_ARCHIVE}, "Sets whether or not bots can slide")
local cv_Dive = CreateConVar("dd_bot_dive", "1", {FCVAR_ARCHIVE}, "Sets whether or not bots can dive")
local cv_CombatMovement = CreateConVar("dd_bot_combat_movement", "1", {FCVAR_ARCHIVE}, "Sets whether or not bots can use combat movement")
local cv_CanUseGrenades = CreateConVar("dd_bot_use_grenades", "1", {FCVAR_ARCHIVE}, "Sets whether or not bots can use grenades")
local cv_CanUseSpells = CreateConVar("dd_bot_use_spells", "1", {FCVAR_ARCHIVE}, "Sets whether or not bots can use spells")
local cv_Quota = CreateConVar("dd_bot_quota", "0", {FCVAR_ARCHIVE}, "Sets the bot quota")
local cv_AimPrediction = CreateConVar("dd_bot_aim_prediction", "1", {FCVAR_ARCHIVE}, "Sets whether or not bots can use aim prediction")
local cv_AimSpreadMult = CreateConVar("dd_bot_aim_spread_mult", "1.0", {FCVAR_ARCHIVE}, "Sets the bot aim spread multiplier")
local cv_FOV = CreateConVar("dd_bot_fov", "100", {FCVAR_ARCHIVE}, "Sets the bot field of view")


--[[----------------------------
    ConVar Change Callbacks
----------------------------]]--

cvars.AddChangeCallback("dd_bot_quota", function(convar_name, value_old, value_new)
    cv_QuotaVal = tonumber(value_new)
end)

cvars.AddChangeCallback("dd_bot_aim_speed_mult", function(convar_name, value_old, value_new)
    cv_AimSpeedMultVal = tonumber(value_new)
end)

cvars.AddChangeCallback("dd_bot_slide", function(convar_name, value_old, value_new)
    cv_SlideEnabled = tobool(value_new)
end)

cvars.AddChangeCallback("dd_bot_dive", function(convar_name, value_old, value_new)
    cv_DiveEnabled = tobool(value_new)
end)

cvars.AddChangeCallback("dd_bot_combat_movement", function(convar_name, value_old, value_new)
    cv_CombatMovementEnabled = tobool(value_new)
end)

cvars.AddChangeCallback("dd_bot_use_grenades", function(convar_name, value_old, value_new)
    cv_CanUseGrenadesEnabled = tobool(value_new)
end)

cvars.AddChangeCallback("dd_bot_use_spells", function(convar_name, value_old, value_new)
    cv_CanUseSpellsEnabled = tobool(value_new)
end)

cvars.AddChangeCallback("dd_bot_aim_prediction", function(convar_name, value_old, value_new)
    cv_AimPredictionEnabled = tobool(value_new)
end)

cvars.AddChangeCallback("dd_bot_aim_spread_mult", function(convar_name, value_old, value_new)
    cv_AimSpreadMult = tonumber(value_new)
end)

cvars.AddChangeCallback("dd_bot_fov", function(convar_name, value_old, value_new)
    cv_FOVVal = math.cos(math.rad(tonumber(value_new) * 0.5))
end)


--[[----------------------------
    Functions
----------------------------]]--

function DDBot.Init()
    isTeamPlay = GAMEMODE:GetGametype() ~= "ffa"
    gameType = GAMEMODE:GetGametype()
    
    cv_QuotaVal = cv_Quota:GetInt()
    cv_AimSpeedMultVal = cv_AimSpeedMult:GetFloat()
    cv_SlideEnabled = cv_Slide:GetBool()
    cv_DiveEnabled = cv_Dive:GetBool()
    cv_CombatMovementEnabled = cv_CombatMovement:GetBool()
    cv_CanUseGrenadesEnabled = cv_CanUseGrenades:GetBool()
    cv_CanUseSpellsEnabled = cv_CanUseSpells:GetBool()
    cv_AimPredictionEnabled = cv_AimPrediction:GetBool()
    cv_AimSpreadMult = cv_AimSpreadMult:GetFloat()
    cv_FOVVal = math.cos(math.rad(cv_FOV:GetInt() * 0.5))

    if ents.FindByClass("prop_door_rotating")[1] then
        doorEnabled = true
    end
end

function DDBot.AddBot(customName)
    if not entityLoaded then
        return
    end

    if not navmesh.IsLoaded() then
        MsgN("[DDBot] There is no navmesh! Generate one using \"dd_bot_generatenavmesh\"!")
        return
    end

    if player.GetCount() == game.MaxPlayers() then
        MsgN("[DDBot] Player limit reached!")
        return
    end

    local name = customName or "Bot #" .. #player.GetBots() + 1
    local model = player_manager.TranslateToPlayerModelName(table.Random(player_manager.AllValidModels()))
    local bot = player.CreateNextBot(name)

    if not IsValid(bot) then
        MsgN("[DDBot] Unable to create bot!")
        return
    end

    bot.ChosenPM = model
    bot.ControllerBot = ents.Create("ddbot_entity")
    bot.ControllerBot:Spawn()
    bot.ControllerBot:SetOwner(bot)
    DDBot.AddBotOverride(bot)
    MsgN("[DDBot] Bot '" .. name .. "' added!")
end

function DDBot.AddBotOverride(bot)
    if GAMEMODE:GetGametype() == "ffa" then
        bot:SetTeam(TEAM_FFA)
    elseif GAMEMODE:GetGametype() == "ts" then
        if GAMEMODE.DeadPeople[tostring(bot:SteamID())] or IsValid(GetHillEntity()) and GetHillEntity():GetTimer() <= TS_TIME * (1 - TS_DEADLINE) then
            bot:SetTeam(TEAM_THUG)
        else
            bot:SetTeam(TEAM_BLUE)
        end
    else
        if bot:CanJoinTeam(TEAM_RED) then
            bot:SetTeam(TEAM_RED)
        else
            bot:SetTeam(TEAM_BLUE)
        end
    end

    bot:KillSilent()
    bot:SetDeaths(0)
    bot:SetTeamColor()
    bot.NextSpawnTime = CurTime() + math.random(2, 6)
end

function DDBot.IsPosWithinFOV(bot, pos)
    local bPos = bot:GetPos()
    local diffX = pos.x - bPos.x
    local diffY = pos.y - bPos.y
    local diffZ = pos.z - bPos.z
    local distSqr = diffX * diffX + diffY * diffY + diffZ * diffZ
    
    if distSqr == 0 then return true end

    local aimVec = bot:GetAimVector()
    local dot = aimVec.x * diffX + aimVec.y * diffY + aimVec.z * diffZ
    local cosVal = cv_FOVVal

    return dot >= 0 and dot * dot >= cosVal * cosVal * distSqr
end

function DDBot.IsTargetVisible(bot, target, ignore)
    if not IsValid(target) or not IsValid(bot) then return nil end

    local targetCenter = target:WorldSpaceCenter()
    local botEyePos = bot:EyePos()

    if botEyePos:DistToSqr(targetCenter) > 2500 then 
        -- Field of view check
        if not DDBot.IsPosWithinFOV(bot, targetCenter) then
            return nil
        end
    end

    if target.IsGhosting and target:IsGhosting() then
        return nil
    end

    -- For props
    if not target:IsPlayer() then
        propTrace.start = botEyePos
        propTrace.endpos = targetCenter
        propTrace.filter = ignore
        local tr = util.TraceLine(propTrace)

        return tr.Entity == target and targetCenter or nil
    end

    local targetEyePos = target:EyePos()
    visTrace1.start = botEyePos
    visTrace1.endpos = targetEyePos
    visTrace1.filter = ignore
    local tr = util.TraceLine(visTrace1)

    if not tr.Hit then
        return targetEyePos
    end

    visTrace2.start = botEyePos
    visTrace2.endpos = targetCenter
    visTrace2.filter = ignore
    local tr2 = util.TraceLine(visTrace2)

    if not tr2.Hit then
        return targetCenter
    end

    local targetPos = target:GetPos()
    visTrace3.start = botEyePos
    visTrace3.endpos = targetPos
    visTrace3.filter = ignore
    local tr3 = util.TraceLine(visTrace3)

    if not tr3.Hit then
        return targetPos
    end

    return nil
end

-- https://github.com/Necrossin/darkestdays/blob/master/entities/entities/effect_grenade/shared.lua#L96
function DDBot.ThrowNade(bot)
    if not entityLoaded then return end
    if not bot:Alive() then return end

    local curTime = CurTime()
    local wep = bot:GetActiveWeapon()
	
	if bot.IsCrow and bot:IsCrow() then return end
	
	if IsValid(wep) then
		if bot:IsSprinting() then return end
		if wep.IsCasting and wep:IsCasting() then return end
		if wep.IsReloading and wep:IsReloading() then return end
		if wep.GetNextReload and wep:GetNextReload() > curTime then return end
		if wep.IsAttacking and wep:IsAttacking() then return end
		if wep.IsBlocking and wep:IsBlocking() then return end
		
		if wep.SetSpellEnd then
			wep:SetSpellEnd(curTime + 0.65)
		end
	end

	local ent = ents.Create("npc_grenade_frag")
	if IsValid(ent) then
		local v = bot:GetShootPos()
		v = v + bot:GetForward() * 5
		v = v + bot:GetRight() * -8
		v = v + bot:GetUp() * -4
		ent:SetPos(v)
		local ang = bot:GetAngles()
		ent:SetAngles(ang)
		ent:SetOwner(bot)
		ent:Activate()
		ent:Spawn()
		ent:SetSaveValue("m_hThrower", bot )
		local col = team.GetColor(bot:Team()) or Color(255, 255, 255)
		col.a = 255
		
		ent:SetMaterial("models/shiny")
		ent:SetColor(col)
		
		ent:SetSaveValue("m_flDamage", 115 )
		ent:SetSaveValue("m_DmgRadius", 280 )

		ent:Fire("SetTimer",1.8,0)
		ent:SetModelScale( 1.5, 0 )

		local phys = ent:GetPhysicsObject()
		if IsValid(phys) then
			phys:Wake()
			phys:SetVelocity(bot:GetVelocity()+bot:GetAimVector() * 900)
			phys:AddAngleVelocity(Vector(600,math.random(-1200,1200),0))
		end

		bot:PlayGesture(ACT_GMOD_GESTURE_ITEM_DROP)
		ent:EmitSound( "weapons/slam/throw.wav" )
	end
end

function DDBot.GetLeader(bot)
    if not IsValid(bot) then return nil end

    local potentialLeaders = {}

    for _, ply in player.Iterator() do
        if ply:Alive() and ply:Team() == bot:Team() then
            potentialLeaders[#potentialLeaders + 1] = ply
        end
    end

    local count = #potentialLeaders
    if count == 0 then return nil end
    if count == 1 then return potentialLeaders[1] end

    table.sort(potentialLeaders, function(a, b)
        if a:IsBot() ~= b:IsBot() then
            return not a:IsBot()
        end
        return a:EntIndex() < b:EntIndex()
    end)

    return potentialLeaders[1]
end

function DDBot.GetClosestPlayer(bot, teammate)
    if not IsValid(bot) then return nil end

    local closestPlayer = nil
    local closestDist = math.huge
    local botPos = bot:GetPos()
    local botTeam = bot:Team()

    for _, ply in player.Iterator() do
        if ply == bot then continue end

        if ply:Alive() and (not teammate and ply:Team() ~= botTeam or teammate and ply:Team() == botTeam) then
            local dist = botPos:DistToSqr(ply:GetPos())
            if dist < closestDist then
                closestDist = dist
                closestPlayer = ply
            end
        end
    end

    return closestPlayer
end

function DDBot.CalculateAimPrediction(projectileSpeed, shootPos, target, targetAimPos)
    if not IsValid(target) then return nil end
    
    local targetPos = targetAimPos or target:WorldSpaceCenter()
    local targetVel = target:GetVelocity()
    local dist = shootPos:Distance(targetPos)
    local timeToHit = dist / projectileSpeed
    
    return targetPos + (targetVel * timeToHit)
end

function DDBot.FindRandomSpot(bot)
    if not IsValid(bot) then return end

    local randomPosList = navmesh.Find(bot:GetPos(), 12500, 18, 128)
    if not randomPosList or #randomPosList == 0 then
        return bot:GetPos()
    end
    
    local randomNav = randomPosList[math.random(1, #randomPosList)]
    local pos = randomNav and randomNav:GetRandomPoint()

    return pos or bot:GetPos()
end

function DDBot.GiveSupport(ply, target)
    if not IsValid(ply) or not IsValid(target) then return end
    supportQueue[#supportQueue + 1] = {ply = ply, target = target}
end

function DDBot.IsDirClear(bot, dir)
    if not IsValid(bot) then
        return 0
    end

    local controller = bot.ControllerBot
    if not IsValid(controller) then
        return 0
    end

    local dirRange = 75
    local center = bot:WorldSpaceCenter()
    local endPos = center + dir * dirRange
    local filter = {bot, controller}
    
    hullTrace.start = center
    hullTrace.endpos = endPos
    hullTrace.mins = dirCheckHullMins
    hullTrace.maxs = dirCheckHullMaxs
    hullTrace.filter = filter
    local tr = util.TraceHull(hullTrace)

    local clearDist = dirRange * tr.Fraction

    if clearDist < 20 then
        return 0
    end

    local botPos = bot:GetPos()
    local checkPos = botPos + dir * clearDist
    
    groundTrace.start = checkPos
    groundTrace.endpos = checkPos - groundCheckOffset
    groundTrace.filter = filter
    local gTrace = util.TraceLine(groundTrace)

    if not gTrace.StartSolid and not gTrace.Hit then
        return 0
    end

    return clearDist
end


--[[----------------------------
    Hook Functions
----------------------------]]--

function DDBot.PlayerSpawn(bot)
    if not (Spells and Perks and Builds and Weapons) then return end

    local zombies = gameType == "ts"

    if not cachedPrimaries then
        cachedPrimaries = {}
        cachedSecondaries = {}
        for class, wep in pairs(Weapons) do
            if class == "empty" or class == "dd_sparkler" then continue end

            if wep.Melee then
                cachedSecondaries[#cachedSecondaries + 1] = class
            else
                cachedPrimaries[#cachedPrimaries + 1] = class
            end
        end
    end
    
    if not cachedSpells then
        local tempSpells = table.GetKeys(Spells)
        cachedSpells = {}
        for _, spell in ipairs(tempSpells) do
            if spell ~= "barrier" then
                cachedSpells[#cachedSpells + 1] = spell
            end
        end

        local tempPerks = table.GetKeys(Perks)
        cachedPerks = {}
        for _, perk in ipairs(tempPerks) do
            if perk ~= "thug" and perk ~= "crow" and perk ~= "blank" then
                cachedPerks[#cachedPerks + 1] = perk
            end
        end

        cachedBuilds = table.GetKeys(Builds)
    end
    
    local loadoutType = math.random(1, 4)
    local spell1 = cachedSpells[math.random(#cachedSpells)]
    local spell2 = cachedSpells[math.random(#cachedSpells)]
    while spell2 == spell1 and #cachedSpells > 1 do
        spell2 = cachedSpells[math.random(#cachedSpells)]
    end
    local perk = cachedPerks[math.random(#cachedPerks)]
    local primary = cachedPrimaries[math.random(#cachedPrimaries)]
    local secondary = cachedSecondaries[math.random(#cachedSecondaries)]
    local build = Builds[cachedBuilds[math.random(#cachedBuilds)]]
    bot.Skills["strength"] = 0
    bot.Skills["magic"] = 5
    bot.Skills["agility"] = 15

    if loadoutType == 3 then
        primary = "dd_sparkler"
        secondary = "dd_wand"
        build = Builds["arcane"]
        bot.Skills["strength"] = 0
        bot.Skills["magic"] = 15
        bot.Skills["agility"] = 5
    elseif loadoutType == 4 and not zombies then
        local thugOrNot = math.random(5) == 1 and "thug" or "adrenaline"
        primary = "none"

        local bList = {"agile", "healthy"}
        build = Builds[bList[math.random(#bList)]]
        perk = thugOrNot

        if secondary == "dd_fists" then
            perk = "martialarts"
        end

        bot.Skills["strength"] = 15
        bot.Skills["magic"] = 5
        bot.Skills["agility"] = 0
    end

    bot.Loadout = {primary, secondary}
    bot.SpellsToGive = {spell1, spell2}
    if math.random(5) == 1 and loadoutType ~= 4 then
        bot.PerksToGive = {"blank"}
    else
        bot.PerksToGive = {perk}
    end

    timer.Simple(0, function()
        if IsValid(bot) then
            local model = string.lower(player_manager.TranslatePlayerModel(bot.ChosenPM))
            if table.HasValue(GAMEMODE.ModelBlacklist, model) then
                model = "models/player/kleiner.mdl"
            end

            bot:SetModel(model)
            bot:SetDTString(0, model)
            bot:SetVoiceSet(VoiceSetTranslate[model] or "male")

            build.OnSet(bot)
        end
    end)
end

function DDBot.Think()
    local curTime = CurTime()

    if not gameType then
        DDBot.Init()
    end

    for _, bot in player.Iterator() do
        if bot:IsBot() then
            if bot.NextSpawnTime and not bot:Alive() and bot.NextSpawnTime < curTime then
                bot:Spawn()
            end

            if bot:Alive() then
                local wep = bot:GetActiveWeapon()
                if IsValid(wep) and wep.Primary then
                    local ammoty = wep:GetPrimaryAmmoType() or wep.Primary.Ammo
                    bot:SetAmmo(wep.Primary.DefaultClip, ammoty)
                end
            end
        end
    end

    if nextQuotaCheck < curTime and entityLoaded then
        nextQuotaCheck = curTime + 1

        local bots = player.GetBots()
        local numBots = #bots
        local quota = cv_QuotaVal
        local humans = #player.GetHumans()
        local target = quota - humans
        if target < 0 then target = 0 end

        if humans > 0 then
            if numBots < target then
                for i = 1, target - numBots do
                    DDBot.AddBot()
                end
            elseif numBots > target then
                for i = numBots, numBots - (numBots - target) + 1, -1 do
                    bots[i]:Kick()
                end
            end
        elseif numBots > 0 then
            for i = 1, numBots do
                bots[i]:Kick()
            end
        end
    end
end

function DDBot.PlayerHurt(ply, att, hp, dmg)
    if not IsValid(ply) or not IsValid(att) then
        return
    end

    if isTeamPlay and ply.Team and att.Team and ply:Team() == att:Team() then
        return
    end

    if ply == att or not ply:Alive() or not att:Alive() then
        return
    end

    local controller = ply.ControllerBot

    if controller and IsValid(controller) and ply:IsBot() then
        local curTime = CurTime()
        local attCenter = att:WorldSpaceCenter()
        local plyShootPos = ply:GetShootPos()
        local target = controller.Target
        local controllerPos = controller:GetPos()
        
        if not IsValid(target) then
            controller.Target = att
            controller.ForgetTarget = curTime + 2
            controller.LookAt = attCenter
            controller.LookAtTime = curTime + 1
        else
            if target == att then
                controller.LookAt = attCenter
                controller.LookAtTime = curTime + 1
            elseif controllerPos:DistToSqr(target:GetPos()) > controllerPos:DistToSqr(att:GetPos()) then
                controller.Target = att
                controller.ForgetTarget = curTime + 2
                controller.LookAt = attCenter
                controller.LookAtTime = curTime + 1
            end
        end
    end

    if isTeamPlay then
        DDBot.GiveSupport(ply, att)
        DDBot.GiveSupport(att, ply)
    end
end

function DDBot.PlayerDeath(bot, inflictor, attacker)
    if bot.ControllerBot then
        bot.ControllerBot.Target = nil
    end
end

function DDBot.StartCommand(bot, cmd)
    local controller = bot.ControllerBot
    if not IsValid(controller) then return end

    local buttons = 0
    local curTime = CurTime()
    local zombies = gameType == "ts"
    local botPos = bot:GetPos()
    local botWeapon = bot:GetActiveWeapon()
    local botWeaponValid = IsValid(botWeapon)
    local melee = botWeaponValid and botWeapon.Base == "dd_meleebase"
    local isUsingMinigun = botWeaponValid and botWeapon:GetClass() == "dd_striker"
    local target = controller.Target
    local isTargetValid = IsValid(target)
    local isTargetVisible = isTargetValid and DDBot.IsTargetVisible(bot, target, {bot, controller})
    local isThug = bot:IsThug()
    local aboutToThrowNade = cv_CanUseGrenadesEnabled and bot.Skills.agility == 15 and isTargetVisible and controller.NextNadeThrowTime < curTime and math.random(5) == 1 and not melee and not isThug
    local curSpell = bot.GetCurrentSpell and bot:GetCurrentSpell()
    local isAlreadyAttacking = false
    local isAlreadyCasting = false
    local isSliding = false
    local isOnLadder = bot:GetMoveType() == MOVETYPE_LADDER

    -- Sprint when not casting spells and not about to throw nade
    if (not cv_CanUseSpellsEnabled or controller.NextAttack2 < curTime) and not aboutToThrowNade and not isOnLadder then
        buttons = IN_SPEED
    end

    -- Slide
    if cv_SlideEnabled and ((controller.NextSlideTime < curTime and math.random(5) == 1) or controller.CurSlideTime > curTime) and DDBot.RunningCheck(bot) and not isThug then
        if controller.CurSlideTime < curTime then
            controller.CurSlideTime = curTime + math.random(1, 2)
        end
        buttons = buttons + IN_DUCK
        controller.NextSlideTime = curTime + math.random(4, 10)
        isSliding = true
    end

    if botWeaponValid then
        -- Only reload if we're out of ammo or we're safe to reload (no target and low ammo)
        if not melee then
            local maxClip = botWeapon:GetMaxClip1()
            if maxClip > 0 then
                local clip = botWeapon:Clip1()
                if clip == 0 or (not isTargetValid and not controller.ForceShoot and clip < maxClip) then
                    buttons = buttons + IN_RELOAD
                end
            end
        end

        -- Change spell
        if controller.NextChangeSpell < curTime and math.random(3) == 1 and not isThug and not isUsingMinigun then
            controller.NextChangeSpell = curTime + math.random(5, 30)
            bot:SwitchSpell()
        end

        if isTargetValid then
            if cv_CanUseSpellsEnabled and controller.NextAttack2Delay < curTime and (curSpell and bot.CanCast and bot:CanCast(curSpell)) and math.random(3) == 1 and not isUsingMinigun and not isThug then
                local nextAttack2Time = melee and 1 or 2
                controller.NextAttack2 = curTime + nextAttack2Time
                controller.NextAttack2Delay = curTime + math.random(5, 10)

                if curSpell:GetClass() == "spell_cure" then
                    if isTeamPlay then
                        local closestTeammate = DDBot.GetClosestPlayer(bot, true)
                        if IsValid(closestTeammate) and bot:VisibleVec(closestTeammate:GetPos()) then
                            controller.LookAt = closestTeammate:GetPos()
                        else
                            controller.LookAt = botPos
                        end
                    else
                        controller.LookAt = botPos
                    end
                    controller.LookAtTime = curTime + 0.1
                    controller.NextAttack2 = curTime + 0.1
                    controller.ForcedLookAt = true
                    controller.ForceCast = true
                end
            end

            local targetCenter = target:WorldSpaceCenter()
            if (isUsingMinigun or DDBot.IsPosWithinFOV(bot, targetCenter)) and controller.NextAttack < curTime and controller.ShootReactionTime < curTime and (isUsingMinigun or isTargetVisible) then
                local inMeleeRange = not melee or botPos:DistToSqr(target:GetPos()) < 10000
                if inMeleeRange then
                    local attack2 = (not isThug and not aboutToThrowNade and controller.NextAttack2 > curTime) and IN_ATTACK2 or 0
                    buttons = buttons + IN_ATTACK + attack2
                    isAlreadyCasting = attack2 > 0
                    isAlreadyAttacking = true

                    if not isUsingMinigun then
                        controller.NextAttack = curTime + 0.05
                    end
                end

                -- Dive
                if cv_DiveEnabled and controller.NextDiveTime < curTime and math.random(10) == 1 and not melee and not zombies then
                    controller.NextDiveTime = curTime + math.random(4, 10)
                    buttons = buttons + IN_WALK
                end

                -- Throw nade
                if aboutToThrowNade and entityLoaded then
                    controller.NextNadeThrowTime = curTime + math.random(12, 20)
                    DDBot.ThrowNade(bot)
                end
            end
        else
            controller.ShootReactionTime = curTime + math.Rand(0.25, 0.5)
        end

        if not isAlreadyAttacking and controller.NextAttack < curTime and controller.ForceShoot then
            buttons = buttons + IN_ATTACK

            if not isUsingMinigun then
                controller.NextAttack = curTime + 0.05
            end
        end

        if not isAlreadyCasting and controller.NextAttack2 > curTime and controller.ForceCast then
            buttons = buttons + IN_ATTACK2
        else
            controller.ForceCast = false
        end
    end

    if isOnLadder then
        buttons = buttons + IN_FORWARD
    end

    if not isSliding and not isOnLadder then
        if controller.NextDuck > curTime then
            buttons = buttons + IN_DUCK
        elseif controller.NextJump == 0 then
            controller.NextJump = curTime + 1
            buttons = buttons + IN_JUMP
        end

        if not bot:IsOnGround() and controller.NextJump > curTime then
            buttons = buttons + IN_DUCK
        end
    end

    cmd:ClearButtons()
    cmd:ClearMovement()
    cmd:SetButtons(buttons)
end

function DDBot.PlayerMove(bot, cmd, mv)
    local controller = bot.ControllerBot
    local maxSpeed = 999999
    local resultingForwardSpeed = 0
    local resultingSideSpeed = 0
    local resultingEyeAngle
    local resultingMoveAngle
    local inobjective = false
    local reachedDest = false
    local backingUp = false
    local combatMovement = false
    local useAimSpeedMult = false
    local isOnLadder = bot:GetMoveType() == MOVETYPE_LADDER
    local backClearDist = DDBot.IsDirClear(bot, -bot:GetForward())
    local rightClearDist = DDBot.IsDirClear(bot, bot:GetRight())
    local leftClearDist = DDBot.IsDirClear(bot, -bot:GetRight())
    local backIsClear = backClearDist >= 100
    local rightIsClear = rightClearDist >= 100
    local leftIsClear = leftClearDist >= 100
    local visibleTargetPos

    if not IsValid(controller) then
        bot.ControllerBot = ents.Create("ddbot_entity")
        bot.ControllerBot:Spawn()
        bot.ControllerBot:SetOwner(bot)
        controller = bot.ControllerBot
    end

    local wep = bot:GetActiveWeapon()
    local botPos = bot:GetPos()
    local curTime = CurTime()

    local controllerPos = controller:GetPos()
    if controllerPos ~= botPos then
        controller:SetPos(botPos)
    end

    local botEyeAngles = bot:EyeAngles()
    local controllerAngles = controller:GetAngles()
    if controllerAngles ~= botEyeAngles then
        controller:SetAngles(botEyeAngles)
    end

    resultingForwardSpeed = maxSpeed

    local zombies = gameType == "ts"
    local melee = IsValid(wep) and wep.Base == "dd_meleebase"
    local isUsingMinigun = IsValid(wep) and wep:GetClass() == "dd_striker"

    if (bot.NextSpawnTime and bot.NextSpawnTime + 1 > curTime) or controller.ForgetTarget < curTime or not IsValid(controller.Target) or not controller.Target:Alive() or (controller.Target.IsGhosting and controller.Target:IsGhosting()) then
        controller.Target = nil
    end

    -- Target acquisition
    if controller.PendingTarget then
        local forgetTargetTime = isUsingMinigun and 1 or 10

        controller.Target = controller.PendingTarget
        controller.ForgetTarget = curTime + forgetTargetTime
        controller.ForceShoot = false
        controller.PendingTarget = nil
    end

    -- Prop checking
    if controller.PendingProp then
        controller.LookAt = controller.PendingProp:WorldSpaceCenter()
        controller.LookAtTime = curTime + 0.1
        controller.ForceShoot = true
        controller.PendingProp = nil
    elseif controller.PendingForceShootOff then
        controller.ForceShoot = false
        controller.PendingForceShootOff = nil
    end

    if doorEnabled then
        local dt = util.QuickTrace(bot:EyePos(), bot:GetForward() * 45, {bot, controller})

        if IsValid(dt.Entity) and dt.Entity:GetClass() == "prop_door_rotating" then
            dt.Entity:Fire("OpenAwayFrom", bot, 0)
        end
    end

    local objectivePos
    local isKothMode = gameType == "koth"
    if isKothMode then
        if objective and IsValid(objective) then
            objective.radius2d = objective.radius2d or ((objective:GetRadius() - 12) * (objective:GetRadius() - 12) / 1.5)
            objectivePos = objective:GetPos()
        end

        inobjective = objectivePos and objectivePos:DistToSqr(botPos) <= objective.radius2d
    end

    local isHtfMode = gameType == "htf"
    if not IsValid(controller.Target) and (not controller.PosGen or (not isHtfMode and not isKothMode and botPos:DistToSqr(controller.PosGen) < 1000) or controller.LastSegmented < curTime) then
        if isHtfMode then
            if bot:IsCarryingFlag() then
                controller.PosGen = DDBot.FindRandomSpot(bot)
                controller.LastSegmented = curTime + 8
            else
                if not IsValid(objective) then
                    objective = ents.FindByClass("htf_flag")[1]
                end

                local flag = objective
                if IsValid(flag) then
                    local rand = 64

                    if not IsValid(flag:GetCarrier()) then
                        rand = 32
                    end

                    rand = VectorRand() * rand
                    tempVector.x, tempVector.y, tempVector.z = rand.x, rand.y, 0
                    controller.PosGen = flag:GetPos() + tempVector
                    controller.LastSegmented = curTime + 2
                end
            end
        elseif isKothMode then
            if not IsValid(objective) then
                objective = ents.FindByClass("koth_point")[1]
            end

            local point = objective
            if IsValid(point) then
                local point_pos = point:GetPos()
                local rand = (point:GetRadius() - 12)

                if IsValid(controller.Target) then
                    rand = rand * 1.25
                end

                rand = VectorRand() * rand
                tempVector.x, tempVector.y, tempVector.z = rand.x, rand.y, 0
                controller.PosGen = point_pos + tempVector
                controller.LastSegmented = curTime + 2
            end
        elseif zombies then
            if bot:IsThug() then
                local closestEnemy = DDBot.GetClosestPlayer(bot, false)
                if IsValid(closestEnemy) then
                    controller.PosGen = closestEnemy:GetPos()
                    controller.LastSegmented = curTime + 2
                else
                    controller.PosGen = DDBot.FindRandomSpot(bot)
                    controller.LastSegmented = curTime + 10
                end
            else
                local leader = DDBot.GetLeader(bot)
                if IsValid(leader) and leader ~= bot then
                    local rand = VectorRand()
                    tempVector.x, tempVector.y, tempVector.z = rand.x * 200, rand.y * 200, 0
                    controller.PosGen = leader:GetPos() + tempVector
                    controller.LastSegmented = curTime + 2
                else
                    controller.PosGen = DDBot.FindRandomSpot(bot)
                    controller.LastSegmented = curTime + 10
                end
            end
        else
            -- Find a random spot on the map, and in 10 seconds do it again!
            controller.PosGen = DDBot.FindRandomSpot(bot)
            controller.LastSegmented = curTime + 10
        end
    elseif IsValid(controller.Target) then
        local targetPos = controller.Target:GetPos()
        local distance = targetPos:DistToSqr(botPos)

        -- Move to our target
        if not bot:IsCarryingFlag() and (not zombies or bot:IsThug()) and (not melee and not inobjective and (not objectivePos or botPos:DistToSqr(objectivePos) > 250000) or melee) then
            controller.PosGen = targetPos
            controller.LastSegmented = curTime + (melee and math.Rand(0.7, 0.9) or math.Rand(1.1, 1.3))
        end

        if not visibleTargetPos then
            visibleTargetPos = DDBot.IsTargetVisible(bot, controller.Target, {bot, controller})
        end

        if visibleTargetPos then
            -- Back up if the target is really close
            local backupDist = not zombies and 40000 or 160000

            if distance <= backupDist and not melee then
                if not backIsClear then
                    if leftIsClear then
                        resultingSideSpeed = -maxSpeed
                    elseif rightIsClear then
                        resultingSideSpeed = maxSpeed
                    elseif leftClearDist > 0 or rightClearDist > 0 then
                        resultingSideSpeed = leftClearDist >= rightClearDist and -maxSpeed or maxSpeed
                    else
                        resultingSideSpeed = 0
                    end
                end

                backingUp = true
                resultingForwardSpeed = -maxSpeed
            end

            local botSideSpeed = mv:GetSideSpeed()

            -- Combat movement (strafing, jumping)
            if cv_CombatMovementEnabled and (controller.NextCombatMove < curTime or (botSideSpeed > 0 and not rightIsClear or botSideSpeed < 0 and not leftIsClear)) then
                controller.NextCombatMove = curTime + math.Rand(0.5, 1.5)

                -- Random strafe
                local strafeDir = 0

                if leftIsClear and rightIsClear then
                    strafeDir = math.random(2) == 1 and 1 or -1
                elseif leftIsClear then
                    strafeDir = -1
                elseif rightIsClear then
                    strafeDir = 1
                elseif leftClearDist > 0 or rightClearDist > 0 then
                    strafeDir = leftClearDist >= rightClearDist and -1 or 1
                else
                    strafeDir = 0
                end

                controller.CombatStrafeDir = strafeDir

                -- Random jump
                if math.random(5) == 1 then
                    controller.NextJump = 0
                end
            end

            if controller.CombatStrafeDir ~= 0 and not melee and not backingUp then
                combatMovement = true
                resultingSideSpeed = controller.CombatStrafeDir * maxSpeed
            end
        end
    end

    if not controller.P then
        return
    end

    local segments = controller.P:GetAllSegments()

    if not segments then return end

    local cur_segment = controller.cur_segment
    local curgoal = segments[cur_segment]

    -- Got nowhere to go, why keep moving?
    if not curgoal then
        mv:SetForwardSpeed(0)
        return
    end

    if not visibleTargetPos and IsValid(controller.Target) then
        visibleTargetPos = DDBot.IsTargetVisible(bot, controller.Target, {bot, controller})
    end

    if botPos:DistToSqr(controller.PosGen) < 900 or (visibleTargetPos and not melee and not backingUp) then
        resultingForwardSpeed = 0
        reachedDest = true
    end

    -- Think every step of the way!
    local cPos = curgoal.pos
    local distSqr = botPos:DistToSqr(cPos)

    if segments[cur_segment + 1] and distSqr < 400 then
        controller.cur_segment = controller.cur_segment + 1
        curgoal = segments[controller.cur_segment]
    end

    local goalpos = curgoal.pos

    -- Stuck logic
    if not inobjective and not reachedDest and not combatMovement then
        if controller.NextStuckPosUpdate < curTime then
            local lastStuckPos = controller.LastStuckPos or botPos
            local movedDistSqr = botPos:DistToSqr(lastStuckPos)

            controller.LastStuckPos = botPos
            controller.NextStuckPosUpdate = curTime + 0.5

            if movedDistSqr < 400 then
                controller.StuckTime = (controller.StuckTime or 0) + 0.5
            else
                controller.StuckTime = 0
            end
        end

        if controller.StuckTime >= 0.5 then
            if controller.NextStuckStrafe < curTime then
                controller.StuckStrafeDir = controller.StuckStrafeDir == 1 and -1 or 1
                controller.NextStuckStrafe = curTime + math.Rand(0.3, 0.65)
            end

            if controller.nextStuckJump < curTime then
                if not bot:Crouching() then
                    controller.NextJump = 0
                end
                controller.nextStuckJump = curTime + math.Rand(1, 2)
            end

            resultingSideSpeed = controller.StuckStrafeDir * maxSpeed
        end
    end

    -- Jump
    if controller.NextJump ~= 0 and curgoal.type > 0 and controller.NextJump < curTime then
        controller.NextJump = 0
    end

    -- Duck
    if curgoal.area:GetAttributes() == NAV_MESH_CROUCH then
        controller.NextDuck = curTime + 0.1
    end

    controller.goalPos = goalpos

    -- Eyesight
    local ft = FrameTime()
    local lerp = ft * 8 * cv_AimSpeedMultVal
    local lerpc = ft * 8

    local mva = ((goalpos + bot:GetCurrentViewOffset()) - bot:GetShootPos()):Angle()

    if not visibleTargetPos and IsValid(controller.Target) then
        visibleTargetPos = DDBot.IsTargetVisible(bot, controller.Target, {bot, controller})
    end

    if controller.ForcedLookAt and controller.LookAtTime < curTime then
        controller.ForcedLookAt = false
    end

    local botShootPos = bot:GetShootPos()
    local traversingLadder = IsValid(curgoal.ladder)

    if traversingLadder then
        controller.CurrentLadder = curgoal.ladder
        local targetAng = (goalpos - botShootPos):Angle()
        resultingEyeAngle = targetAng
        useAimSpeedMult = false
    elseif IsValid(controller.Target) and (isUsingMinigun or visibleTargetPos or controller.LastSeenTarget < curTime) then
        if inobjective and not melee then
            resultingForwardSpeed = 0
        end

        if visibleTargetPos then
            controller.LastSeenTarget = curTime + 1
        end

        local aimAtPos = visibleTargetPos or controller.Target:WorldSpaceCenter()

        local wepValid = IsValid(wep)
        if wepValid and cv_AimPredictionEnabled then
            local class = wep:GetClass()
            
            if class == "dd_xbow" then
                local predictedPos = DDBot.CalculateAimPrediction(3000, botShootPos, controller.Target, aimAtPos)
                if predictedPos then
                    aimAtPos = predictedPos
                end
            elseif class == "dd_launcher" then
                local targetPos = controller.Target:GetPos()
                local launcherAimPos = bot:VisibleVec(targetPos) and targetPos or aimAtPos
                local predictedPos = DDBot.CalculateAimPrediction(1000, botShootPos, controller.Target, launcherAimPos)
                if predictedPos then
                    aimAtPos = predictedPos
                end
            end
        end

        local targetAng = (aimAtPos - botShootPos):Angle()

        if cv_AimSpreadMult > 0 then
            tempAngle.p, tempAngle.y, tempAngle.r = math.Rand(-5, 5), math.Rand(-5, 5), 0
            targetAng = targetAng + tempAngle * cv_AimSpreadMult
        end

        if controller.ForcedLookAt and controller.LookAtTime > curTime then
            targetAng = (controller.LookAt - botShootPos):Angle()
            lerp = 1
        end

        resultingEyeAngle = targetAng
        useAimSpeedMult = true
    else
        if inobjective and not backingUp then
            resultingForwardSpeed = 0

            if controller.LookAtTime < curTime then
                local rand = VectorRand()
                tempVector.x, tempVector.y, tempVector.z = rand.x * 100, rand.y * 100, 0
                controller.LookAt = bot:EyePos() + tempVector
                controller.LookAtTime = curTime + math.Rand(0.9, 1.3)
            end
        end

        local lookAtAngle

        if controller.LookAtTime > curTime then
            lookAtAngle = (controller.LookAt - botShootPos):Angle()
        end

        if lookAtAngle then
            resultingEyeAngle = lookAtAngle
        else
            resultingEyeAngle = mva
        end
    end

    if isOnLadder and IsValid(controller.CurrentLadder) and controller.StuckTime < 1.0 then
        resultingForwardSpeed = maxSpeed
        resultingSideSpeed = 0

        local ladder = controller.CurrentLadder
        local ladderTop = ladder:GetTop()
        local ladderBottom = ladder:GetBottom()
        local distToTop = cPos:DistToSqr(ladderTop)
        local distToBottom = cPos:DistToSqr(ladderBottom)
        local centerLadderAngle = ((ladderTop + ladderBottom) * 0.5 - botShootPos):Angle()
        local whichSide = distToTop < distToBottom and -1 or 1
        local yAxis = whichSide * 30
        local zAxis = centerLadderAngle.y + (whichSide == 1 and 180 or 0)
        tempAngle.p, tempAngle.y, tempAngle.r = yAxis, zAxis, 0
        
        resultingMoveAngle = tempAngle
        resultingEyeAngle = tempAngle
        useAimSpeedMult = false
    elseif isOnLadder then
        bot:ExitLadder()
    end

    local lerpResult = useAimSpeedMult and lerp or lerpc
    resultingMoveAngle = resultingMoveAngle or mva
    bot:SetEyeAngles(LerpAngle(lerpResult, botEyeAngles, resultingEyeAngle))
    mv:SetMoveAngles(resultingMoveAngle)
    mv:SetForwardSpeed(resultingForwardSpeed)
    mv:SetSideSpeed(resultingSideSpeed)
end


--[[----------------------------
    Coroutines
----------------------------]]--

local processingLimit = 100
local curProcessing = 0
local updateCoroutine = nil

function DDBot.UpdateBots()
    local curTime = CurTime()

    local function shouldYield()
        curProcessing = curProcessing + 1
        if curProcessing >= processingLimit then
            curProcessing = 0
            coroutine.yield()
        end
    end

    for _, bot in player.Iterator() do
        if not bot:IsBot() or not bot:Alive() then continue end

        local controller = bot.ControllerBot
        if not IsValid(controller) then continue end

        local botPos = bot:GetPos()
        local botTeam = bot:Team()
        local targets = {}
        local targetDistances = {}

        -- Check for targets
        for _, ply in player.Iterator() do
            if ply ~= bot and ply:Alive() then
                local isEnemy = not isTeamPlay or ply:Team() ~= botTeam

                if isEnemy then
                    local distSqr = ply:GetPos():DistToSqr(botPos)
                    if distSqr < 2250000 then
                        local idx = #targets + 1
                        targets[idx] = ply
                        targetDistances[ply] = distSqr
                    end
                end
            end
            shouldYield()
        end

        local targetCount = #targets
        if targetCount > 1 then
            table.sort(targets, function(a, b)
                return targetDistances[a] < targetDistances[b]
            end)
        end

        local currentTargetDistSqr = IsValid(controller.Target) and botPos:DistToSqr(controller.Target:GetPos()) or math.huge
        for i = 1, targetCount do
            local ply = targets[i]
            local isTargetVisible = DDBot.IsTargetVisible(bot, ply, {bot, controller})
            if isTargetVisible and (not IsValid(controller.Target) or controller.Target == ply or currentTargetDistSqr > targetDistances[ply]) then
                controller.PendingTarget = ply
                break
            end
            shouldYield()
        end

        -- Prop and breakable checking
        if not IsValid(controller.Target) and controller.NextPropCheck < curTime then
            controller.NextPropCheck = curTime + 0.1
            local wep = bot:GetActiveWeapon()
            local melee = IsValid(wep) and wep.Base == "dd_meleebase"
            local radiusCheck = melee and 50 or 100
            local propsInRadius = ents.FindInSphere(botPos, radiusCheck)
            local closestDist = math.huge
            local closestProp

            for _, prop in ipairs(propsInRadius) do
                local propClass = prop:GetClass()
                if (string.StartsWith(propClass, "prop_") or propClass == "func_breakable") and prop:Health() > 0 then
                    local explodeDamage = prop:GetKeyValues()["ExplodeDamage"]
                    if explodeDamage and tonumber(explodeDamage) > 0 then
                        continue
                    end

                    local dist = botPos:DistToSqr(prop:GetPos())
                    if dist < closestDist then
                        closestDist = dist
                        closestProp = prop
                    end
                end
                shouldYield()
            end

            if closestProp and DDBot.IsTargetVisible(bot, closestProp, {bot, controller}) then
                controller.PendingProp = closestProp
            else
                controller.PendingForceShootOff = true
            end
        end

        shouldYield()
    end

    -- Process support queue
    local canSetPos = gameType ~= "koth" and gameType ~= "htf"
    while #supportQueue > 0 do
        local request = table.remove(supportQueue, 1)
        local ply = request.ply
        local target = request.target

        if not IsValid(ply) or not IsValid(target) then continue end

        local plyPos = ply:GetPos()
        local plyTeam = ply.Team and ply:Team()
        local targetPos = target:GetPos()
        local targetCenter = target:WorldSpaceCenter()

        for _, bot in ipairs(player.GetBots()) do
            if bot == ply or not IsValid(bot) then continue end

            local controller = bot.ControllerBot
            if not IsValid(controller) then continue end

            if plyTeam and bot.Team and bot:Team() ~= plyTeam then continue end

            local isVisible = bot:VisibleVec(ply:EyePos())
            if plyPos:DistToSqr(bot:GetPos()) > 250000 and not isVisible then continue end

            if not IsValid(controller.Target) then
                if canSetPos then
                    controller.PosGen = targetPos
                    controller.LastSegmented = curTime + 5
                end

                if isVisible then
                    controller.LookAt = targetCenter
                    controller.LookAtTime = curTime + 1
                end
            end

            shouldYield()
        end

        shouldYield()
    end

    coroutine.yield()
end


--[[----------------------------
    Hooks
----------------------------]]--

hook.Add("PlayerDisconnected", "DDBot_PlayerDisconnected", function(bot)
    if IsValid(bot.ControllerBot) then
        bot.ControllerBot:Remove()
    end
end)

hook.Add("SetupMove", "DDBot_PlayerMove", function(bot, mv, cmd)
    if bot:IsBot() and bot:Alive() then
        DDBot.PlayerMove(bot, cmd, mv)
    end
end)

hook.Add("StartCommand", "DDBot_StartCommand", function(bot, cmd)
    if bot:IsBot() and bot:Alive() then
        DDBot.StartCommand(bot, cmd)
    end
end)

hook.Add("EntityTakeDamage", "DDBot_EntityTakeDamage", function(ply, dmgi)
    local att = dmgi:GetAttacker()
    local hp = ply:Health()
    local dmg = dmgi:GetDamage()

    if IsValid(ply) and ply:IsPlayer() and ply ~= att then
        DDBot.PlayerHurt(ply, att, hp, dmg)
    end
end)

hook.Add("PlayerDeath", "DDBot_PlayerDeath", function(bot, inflictor, attacker)
    if IsValid(bot) and bot:IsBot() then
        DDBot.PlayerDeath(bot, inflictor, attacker)
    end
end)

hook.Add("Think", "DDBot_Think", function()
    -- Coroutine
    if not updateCoroutine or coroutine.status(updateCoroutine) == "dead" then
        updateCoroutine = coroutine.create(DDBot.UpdateBots)
    end
    if coroutine.status(updateCoroutine) == "suspended" then
        coroutine.resume(updateCoroutine)
    end

    DDBot.Think()
end)

hook.Add("PlayerSpawn", "DDBot_PlayerSpawn", function(bot)
    if bot:IsBot() then
        DDBot.PlayerSpawn(bot)
    end
end)

hook.Add("Initialize", "DDBot_Initialize", function()
    entityLoaded = false
end)

hook.Add("PreCleanupMap", "DDBot_PreCleanupMap", function()
    entityLoaded = false
end)

hook.Add("InitPostEntity", "DDBot_InitPostEntity", function()
    entityLoaded = true
    DDBot.Init()
end)

hook.Add("PostCleanupMap", "DDBot_PostCleanupMap", function()
    entityLoaded = true
    DDBot.Init()
end)

hook.Add("CalcMainActivity", "DDBot_CalcMainActivity", DDBot.BotAnimations)
