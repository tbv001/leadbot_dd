include("leadbot/shared.lua")

--[[ CONFIGURATION ]]--

LeadBot.TeamPlay = false -- don't hurt players on the bots team
LeadBot.LerpAim = true -- interpolate aim (smooth aim)

local objective
local gametype
local door_enabled

--[[ COMMANDS ]]--

concommand.Add("leadbot_add", function(ply, _, args)
    if IsValid(ply) and not ply:IsSuperAdmin() then
        return
    end
    local amount = 1
    if tonumber(args[1]) then
        amount = tonumber(args[1])
    end
    for i = 1, amount do
        timer.Simple(i * 0.1, function()
            LeadBot.AddBot()
        end)
    end
end, nil, "Adds a LeadBot")

concommand.Add("leadbot_kick", function(ply, _, args)
    if not args[1] or IsValid(ply) and not ply:IsSuperAdmin() then
        return
    end
    if args[1] ~= "all" then
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
end, nil, "Kicks LeadBots (all is avaliable!)")


--[[ FUNCTIONS ]]--

function LeadBot.AddBot()
    if !navmesh.IsLoaded() then
        MsgN("There is no navmesh! Generate one using \"nav_generate\"!\n")
        return
    end

    if player.GetCount() == game.MaxPlayers() then
        MsgN("[LeadBot] Player limit reached!")
        return
    end

    local name = "Bot #" .. #player.GetBots() + 1
    local model = player_manager.TranslateToPlayerModelName(table.Random(player_manager.AllValidModels()))
    local botcolor = ColorRand()
    local botweaponcolor = ColorRand()
    local color = Vector(botcolor.r / 255, botcolor.g / 255, botcolor.b / 255)
    local weaponcolor = Vector(botweaponcolor.r / 255, botweaponcolor.g / 255, botweaponcolor.b / 255)
    local bot = player.CreateNextBot(name)

    if !IsValid(bot) then
        MsgN("[LeadBot] Unable to create bot!")
        return
    end

    bot.LeadBot_Config = {model, color, weaponcolor}

    bot.ControllerBot = ents.Create("leadbot_navigator")
    bot.ControllerBot:Spawn()
    bot.ControllerBot:SetOwner(bot)
    bot.LeadBot = true
    LeadBot.AddBotOverride(bot)
    MsgN("[LeadBot] Bot " .. name .. " added!")
end

function LeadBot.AddBotOverride(bot)
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
    bot.NextSpawnTime = CurTime() + GetConVar("dd_options_spawn_time"):GetInt()
end

function LeadBot.PlayerSpawn(bot)
    if !bot:IsBot() then return end
    if not (Spells and Perks and Builds and Weapons) then return end

    local primaries = {}
    local secondaries = {}
    local _, spell1 = table.Random(Spells)
    local _, spell2 = table.Random(Spells)
    local _, perk = table.Random(Perks)
    local build = table.Random(Builds)

    for class, wep in pairs(Weapons) do
        if wep.Melee then
            table.insert(secondaries, class)
        else
            table.insert(primaries, class)
        end
    end

    local primary, secondary = table.Random(primaries), table.Random(secondaries)

    -- Melee only build
    if math.random(5) == 1 then
        primary = "none"
        build = Builds[table.Random({"healthy", "agile"})]
        perk = "adrenaline"
    end

    bot.Loadout = {primary, secondary}
    bot.SpellsToGive = {spell1, spell2}

    if math.random(5) == 1 or perk == "adrenaline" then
        bot.PerksToGive = {perk}
    else
        bot.PerksToGive = {"none"}
    end

    build.OnSet(bot)

    timer.Simple(0, function()
        if IsValid(bot) then
            local model = string.lower(player_manager.TranslatePlayerModel(bot:LBGetModel()))
            if table.HasValue(GAMEMODE.ModelBlacklist, model) then
                model = "models/player/kleiner.mdl"
            end

            bot:SetModel(model)
            bot:SetDTString(0, model)
            bot:SetVoiceSet(VoiceSetTranslate[model] or "male")
        end
    end)
end

function LeadBot.Init()
    LeadBot.TeamPlay = GAMEMODE:GetGametype() ~= "ffa"
    gametype = GAMEMODE:GetGametype()

    if ents.FindByClass("prop_door_rotating")[1] then
        door_enabled = true
    end
end

function LeadBot.Think()
    if !gametype then
        LeadBot.Init()
    end

    for _, bot in player.Iterator() do
        if bot:IsLBot() then
            if bot.NextSpawnTime and !bot:Alive() and bot.NextSpawnTime < CurTime() then
                bot:Spawn()
                return
            end

            local wep = bot:GetActiveWeapon()
            if IsValid(wep) and wep.Primary then
                local ammoty = wep:GetPrimaryAmmoType() or wep.Primary.Ammo
                bot:SetAmmo(wep.Primary.DefaultClip, ammoty)
            end
        end
    end
end

function LeadBot.PlayerHurt(ply, att, hp, dmg)
    if not IsValid(ply) or not IsValid(att) then
        return
    end

    local controller = ply:GetController()

    if not IsValid(controller.Target) and (LeadBot.TeamPlay and (ply:Team() ~= att:Team()) or not LeadBot.TeamPlay) then
        controller.Target = att
        controller.ForgetTarget = CurTime() + 2
        controller.LookAt = (att:GetPos() - controller:GetPos()):Angle()
        controller.LookAtTime = CurTime() + 1
    elseif controller.Target == att then
        controller.LookAt = (att:GetPos() - controller:GetPos()):Angle()
        controller.LookAtTime = CurTime() + 1
    end
end

function LeadBot.GetVisibleHitbox(bot, target, ignore)
    if not IsValid(target) or not IsValid(bot) then return nil end

    -- Field of view check
    local botAimVec = bot:GetAimVector()
    local toTargetDir = (target:GetPos() - bot:GetPos()):GetNormalized()
    if botAimVec:Dot(toTargetDir) < 0.5 then
        return nil
    end

    local count = target:GetHitBoxCount(0)
    if not count then return nil end

    -- Iterate through hitboxes/bones
    for i = 0, count - 1 do
        local bone = target:GetHitBoxBone(i, 0)
        if bone then
            local pos = target:GetBonePosition(bone)
            if pos then
                local tr = util.TraceLine({
                    start = bot:EyePos(),
                    endpos = pos,
                    filter = ignore,
                    mask = MASK_SHOT
                })

                if tr.Entity == target then
                    return pos
                end
            end
        end
    end

    return nil
end

function LeadBot.StartCommand(bot, cmd)
    local buttons = 0
    local botWeapon = bot:GetActiveWeapon()
    local melee = IsValid(botWeapon) and botWeapon.Base == "dd_meleebase"
    local controller = bot.ControllerBot
    local target = controller.Target

    if !IsValid(controller) then return end

    if controller.NextAttack2 < CurTime() then
        buttons = buttons + IN_SPEED
    end

    if ((controller.NextSlideTime < CurTime() and math.random(5) == 1) or controller.CurSlideTime > CurTime()) and RunningCheck(bot) then
        if controller.CurSlideTime < CurTime() then
            controller.CurSlideTime = CurTime() + 1
        end
        buttons = buttons + IN_DUCK
        controller.NextSlideTime = CurTime() + math.random(4, 10)
    end

    if IsValid(botWeapon) then
        if not melee and botWeapon:GetMaxClip1() > 0 and (botWeapon:Clip1() == 0 or !IsValid(target) and botWeapon:Clip1() <= botWeapon:GetMaxClip1() / 2) then
            buttons = buttons + IN_RELOAD
        end

        if controller.NextChangeSpell < CurTime() and math.random(3) == 1 and not bot:IsThug() and botWeapon:GetClass() ~= "dd_striker" then
            bot:SwitchSpell()
            controller.NextChangeSpell = CurTime() + 5
        end

        if IsValid(target) then
            local aimVec = bot:GetAimVector()
            local targetPos = target:WorldSpaceCenter()
            local targetDir = (targetPos - bot:WorldSpaceCenter()):GetNormalized()

            if controller.NextAttack2Delay < CurTime() and math.random(3) == 1 and botWeapon:GetClass() ~= "dd_striker" and not bot:IsThug() then
                controller.NextAttack2 = CurTime() + 2
                controller.NextAttack2Delay = CurTime() + 5
            end

            if aimVec:Dot(targetDir) > 0.9 and controller.NextAttack < CurTime() and controller.ShootReactionTime < CurTime() then
                if melee and bot:GetPos():DistToSqr(target:GetPos()) < 10000 or not melee then
                    buttons = buttons + IN_ATTACK + (not bot:IsThug() and botWeapon:GetClass() ~= "dd_striker" and controller.NextAttack2 > CurTime() and IN_ATTACK2 or 0)

                    if botWeapon:GetClass() ~= "dd_striker" then
                        controller.NextAttack = CurTime() + 0.05
                    end
                end

                if controller.NextDiveTime < CurTime() and math.random(5) == 1 then
                    controller.NextDiveTime = CurTime() + math.random(4, 10)
                    bot:Dive()
                end
            end
        else
            controller.ShootReactionTime = CurTime() + math.random(0.25, 0.45)
        end
    end

    if bot:GetMoveType() == MOVETYPE_LADDER then
        local pos = controller.goalPos
        local ang = ((pos + bot:GetCurrentViewOffset()) - bot:GetShootPos()):Angle()

        if pos.z > controller:GetPos().z then
            controller.LookAt = Angle(-30, ang.y, 0)
        else
            controller.LookAt = Angle(30, ang.y, 0)
        end

        controller.LookAtTime = CurTime() + 0.1
        if controller.NextLadderJump < CurTime() then
            controller.NextJump = 0
        end
        buttons = buttons + IN_FORWARD
    else
        controller.NextLadderJump = CurTime() + 2
    end

    if controller.NextDuck > CurTime() then
        buttons = buttons + IN_DUCK
    elseif controller.NextJump == 0 then
        controller.NextJump = CurTime() + 1
        buttons = buttons + IN_JUMP
    end

    if !bot:IsOnGround() and controller.NextJump > CurTime() then
        buttons = buttons + IN_DUCK
    end

    cmd:ClearButtons()
    cmd:ClearMovement()
    cmd:SetButtons(buttons)
end

function LeadBot.PlayerMove(bot, cmd, mv)
    local controller = bot.ControllerBot
    local maxSpeed = 9999 --mv:GetMaxSpeed() or 1500
    local inobjective = false
    local visibleTargetPos

    if !IsValid(controller) then
        bot.ControllerBot = ents.Create("leadbot_navigator")
        bot.ControllerBot:Spawn()
        bot.ControllerBot:SetOwner(bot)
        controller = bot.ControllerBot
    end

    local wep = bot:GetActiveWeapon()

    if controller:GetPos() ~= bot:GetPos() then
        controller:SetPos(bot:GetPos())
    end

    if controller:GetAngles() ~= bot:EyeAngles() then
        controller:SetAngles(bot:EyeAngles())
    end

    mv:SetForwardSpeed(maxSpeed)

    local zombies = gametype == "ts"
    local melee = IsValid(wep) and wep.Base == "dd_meleebase"

    if ((bot.NextSpawnTime and bot.NextSpawnTime + 1 > CurTime()) or !IsValid(controller.Target) or controller.ForgetTarget < CurTime() or !controller.Target:Alive()) then
        controller.Target = nil
    end

    if not IsValid(controller.Target) then
        local targets = {}
        local botPos = bot:GetPos()

        for _, ply in player.Iterator() do
            if ply ~= bot and ((ply:IsPlayer() and (!LeadBot.TeamPlay or (LeadBot.TeamPlay and (ply:Team() ~= bot:Team())))) or ply:IsNPC()) and ply:GetPos():DistToSqr(botPos) < 2250000 then
                if ply:Alive() then
                    table.insert(targets, ply)
                end
            end
        end

        table.sort(targets, function(a, b)
            return a:GetPos():DistToSqr(botPos) < b:GetPos():DistToSqr(botPos)
        end)

        for _, ply in ipairs(targets) do
            visibleTargetPos = LeadBot.GetVisibleHitbox(bot, ply, {bot, controller})
            if visibleTargetPos then
                controller.Target = ply
                controller.ForgetTarget = CurTime() + 2
                break
            end
        end
    elseif controller.ForgetTarget > CurTime() then
        visibleTargetPos = LeadBot.GetVisibleHitbox(bot, controller.Target, {bot, controller})
        if visibleTargetPos then
            controller.ForgetTarget = CurTime() + 2
        end
    end

    if door_enabled then
        local dt = util.QuickTrace(bot:EyePos(), bot:GetForward() * 45, bot)

        if IsValid(dt.Entity) and dt.Entity:GetClass() == "prop_door_rotating" then
            dt.Entity:Fire("OpenAwayFrom", bot, 0)
        end
    end

    if gametype == "koth" then
        if objective and IsValid(objective) then
            objective.radius2d = objective.radius2d or (objective:GetRadius() - 12) * (objective:GetRadius() - 12)
        end

        inobjective = objective and IsValid(objective) and objective:GetPos():DistToSqr(controller:GetPos()) <= objective.radius2d
    end

    if not IsValid(controller.Target) and (not controller.PosGen or (gametype ~= "htf" and gametype ~= "koth" and bot:GetPos():DistToSqr(controller.PosGen) < 1000) or controller.LastSegmented < CurTime()) then
        if gametype == "htf" then
            if bot:IsCarryingFlag() then
                controller.PosGen = controller:FindSpot("random", {radius = 12500})
                controller.LastSegmented = CurTime() + 8
            else
                if !IsValid(objective) then
                    objective = ents.FindByClass("htf_flag")[1]
                end

                local flag = objective
                if IsValid(flag) then
                    local rand = 64

                    if !IsValid(flag:GetCarrier()) then
                        rand = 32
                    end

                    rand = VectorRand() * rand
                    controller.PosGen = flag:GetPos() + Vector(rand.x, rand.y, 0)
                    controller.LastSegmented = CurTime() + 2
                end
            end
        elseif gametype == "koth" then
            if !IsValid(objective) then
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
                controller.PosGen = point_pos + Vector(rand.x, rand.y, 0)
                controller.LastSegmented = CurTime() + 2
            end
        else
            -- Find a random spot on the map, and in 10 seconds do it again!
            controller.PosGen = controller:FindSpot("random", {radius = 12500})
            controller.LastSegmented = CurTime() + 10
        end
    elseif IsValid(controller.Target) then
        local distance = controller.Target:GetPos():DistToSqr(bot:GetPos())

        -- Move to our target
        if !bot:IsCarryingFlag() and (not melee and not inobjective or melee) then
            controller.PosGen = controller.Target:GetPos()
            controller.LastSegmented = CurTime() + ((melee and math.Rand(0.7, 0.9)) or math.Rand(1.1, 1.3))
        end

        if not visibleTargetPos then
            visibleTargetPos = LeadBot.GetVisibleHitbox(bot, controller.Target, {bot, controller})
        end

        if !melee and visibleTargetPos then
            -- Back up if the target is really close
            if distance <= 40000 then
                mv:SetForwardSpeed(-maxSpeed)
            end

            -- Combat movement (strafing, jumping)
            if controller.NextCombatMove < CurTime() then
                controller.NextCombatMove = CurTime() + math.Rand(0.5, 1.5)

                -- Random strafe
                local r = math.random(3)
                if r == 1 then controller.CombatStrafeDir = 1
                elseif r == 2 then controller.CombatStrafeDir = -1
                else controller.CombatStrafeDir = 0 end

                -- Random jump
                if math.random(5) == 1 then
                    controller.NextJump = 0
                end
            end

            if controller.CombatStrafeDir ~= 0 then
                mv:SetSideSpeed(controller.CombatStrafeDir * maxSpeed)
            end
        end
    end

    if !controller.P then
        return
    end

    local segments = controller.P:GetAllSegments()

    if !segments then return end

    local cur_segment = controller.cur_segment
    local curgoal = segments[cur_segment]

    -- Got nowhere to go, why keep moving?
    if !curgoal then
        mv:SetForwardSpeed(0)
        return
    end

    -- Think every step of the way!
    if segments[cur_segment + 1] and Vector(bot:GetPos().x, bot:GetPos().y, 0):DistToSqr(Vector(curgoal.pos.x, curgoal.pos.y)) < 100 then
        controller.cur_segment = controller.cur_segment + 1
        curgoal = segments[controller.cur_segment]
    end

    local goalpos = curgoal.pos

    -- Stuck logic
    if bot:GetVelocity():Length2DSqr() <= 225 and (gametype ~= "koth" or !inobjective) then
        if controller.NextCenter < CurTime() then
            controller.strafeAngle = ((controller.strafeAngle == 1 and 2) or 1)
            controller.NextCenter = CurTime() + math.Rand(0.3, 0.65)
        elseif controller.nextStuckJump < CurTime() then
            if !bot:Crouching() then
                controller.NextJump = 0
            end
            controller.nextStuckJump = CurTime() + math.Rand(1, 2)
        end
    end

    if controller.NextCenter > CurTime() then
        if controller.strafeAngle == 1 then
            mv:SetSideSpeed(maxSpeed)
        elseif controller.strafeAngle == 2 then
            mv:SetSideSpeed(-maxSpeed)
        else
            mv:SetForwardSpeed(-maxSpeed)
        end
    end

    -- Jump
    if controller.NextJump ~= 0 and curgoal.type > 1 and controller.NextJump < CurTime() then
        controller.NextJump = 0
    end

    -- Duck
    if curgoal.area:GetAttributes() == NAV_MESH_CROUCH then
        controller.NextDuck = CurTime() + 0.1
    end

    controller.goalPos = goalpos

    if GetConVar("developer"):GetBool() then
        controller.P:Draw()
    end

    -- Eyesight
    local lerp = FrameTime() * 16
    local lerpc = FrameTime() * 8

    if !LeadBot.LerpAim then
        lerp = 1
        lerpc = 1
    end

    local mva = ((goalpos + bot:GetCurrentViewOffset()) - bot:GetShootPos()):Angle()

    mv:SetMoveAngles(mva)

    if not visibleTargetPos and IsValid(controller.Target) then
        visibleTargetPos = LeadBot.GetVisibleHitbox(bot, controller.Target, {bot, controller})
    end

    if IsValid(controller.Target) and visibleTargetPos then
        if gametype == "koth" and inobjective and not melee then
            mv:SetForwardSpeed(0)
        end

        bot:SetEyeAngles(LerpAngle(lerp, bot:EyeAngles(), (visibleTargetPos - bot:GetShootPos()):Angle()))
    else
        if gametype == "koth" and inobjective then
            mv:SetForwardSpeed(0)

            if controller.LookAtTime < CurTime() then
                controller.LookAt = Angle(math.random(-40, 40), math.random(-180, 180), 0)
                controller.LookAtTime = CurTime() + math.Rand(0.9, 1.3)
            end
        end

        if controller.LookAtTime > CurTime() then
            local ang = LerpAngle(lerpc, bot:EyeAngles(), controller.LookAt)
            bot:SetEyeAngles(Angle(ang.p, ang.y, 0))
        else
            local ang = LerpAngle(lerpc, bot:EyeAngles(), mva)
            bot:SetEyeAngles(Angle(ang.p, ang.y, 0))
        end
    end
end


--[[ HOOKS ]]--

hook.Add("PlayerDisconnected", "LeadBot_Disconnect", function(bot)
    if IsValid(bot.ControllerBot) then
        bot.ControllerBot:Remove()
    end
end)

hook.Add("SetupMove", "LeadBot_Control", function(bot, mv, cmd)
    if bot:IsLBot() then
        LeadBot.PlayerMove(bot, cmd, mv)
    end
end)

hook.Add("StartCommand", "LeadBot_Control", function(bot, cmd)
    if bot:IsLBot() then
        LeadBot.StartCommand(bot, cmd)
    end
end)

hook.Add("EntityTakeDamage", "LeadBot_Hurt", function(ply, dmgi)
    local att = dmgi:GetAttacker()
    local hp = ply:Health()
    local dmg = dmgi:GetDamage()

    if IsValid(ply) and ply:IsPlayer() and ply:IsLBot() then
        LeadBot.PlayerHurt(ply, att, hp, dmg)
    end
end)

hook.Add("Think", "LeadBot_Think", function()
    LeadBot.Think()
end)

hook.Add("PlayerSpawn", "LeadBot_Spawn", function(bot)
    if bot:IsLBot() then
        LeadBot.PlayerSpawn(bot)
    end
end)

hook.Add("InitPostEntity", "LeadBot_PostEnt_Init", function()
    LeadBot.Init()
end)

hook.Add("PostCleanupMap", "LeadBot_PostClean_Init", function()
    LeadBot.Init()
end)

hook.Add("CalcMainActivity", "LeadBot_ActivityServer", CalcMainActivityBots)


--[[ META ]]--

local player_meta = FindMetaTable("Player")
local oldInfo = player_meta.GetInfo

function player_meta.IsLBot(self, realbotsonly)
    if realbotsonly == true then
        return self.LeadBot and self:IsBot() or false
    end

    return self.LeadBot or false
end

function player_meta.LBGetModel(self)
    if self.LeadBot_Config then
        return self.LeadBot_Config[1]
    else
        return "kleiner"
    end
end

function player_meta.LBGetColor(self, weapon)
    if self.LeadBot_Config then
        if weapon == true then
            return self.LeadBot_Config[3]
        else
            return self.LeadBot_Config[2]
        end
    else
        return Vector(0, 0, 0)
    end
end

function player_meta.GetInfo(self, convar)
    if self:IsBot() and self:IsLBot() then
        if convar == "cl_playermodel" then
            return self:LBGetModel()
        elseif convar == "cl_playercolor" then
            return self:LBGetColor()
        elseif convar == "cl_weaponcolor" then
            return self:LBGetColor(true)
        else
            return ""
        end
    else
        return oldInfo(self, convar)
    end
end

function player_meta.GetController(self)
    if self:IsLBot() then
        return self.ControllerBot
    end
end