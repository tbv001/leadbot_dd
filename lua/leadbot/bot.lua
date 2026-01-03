LeadBot.TeamPlay = false -- don't hurt players on the bots team
LeadBot.LerpAim = true -- interpolate aim (smooth aim)

--[[ COMMANDS ]]--

concommand.Add("leadbot_add", function(ply, _, args) if IsValid(ply) and !ply:IsSuperAdmin() then return end local amount = 1 if tonumber(args[1]) then amount = tonumber(args[1]) end for i = 1, amount do timer.Simple(i * 0.1, function() LeadBot.AddBot() end) end end, nil, "Adds a LeadBot")
concommand.Add("leadbot_kick", function(ply, _, args) if !args[1] or IsValid(ply) and !ply:IsSuperAdmin() then return end if args[1] ~= "all" then for k, v in pairs(player.GetBots()) do if string.find(v:GetName(), args[1]) then v:Kick() return end end else for k, v in pairs(player.GetBots()) do v:Kick() end end end, nil, "Kicks LeadBots (all is avaliable!)")
CreateConVar("leadbot_strategy", "1", {FCVAR_ARCHIVE, FCVAR_NOTIFY}, "Enables the strategy system for newly created bots.")

--[[ FUNCTIONS ]]--

function LeadBot.AddBot()
    if !navmesh.IsLoaded() then
        ErrorNoHalt("There is no navmesh! Generate one using \"nav_generate\"!\n")
        return
    end

    if player.GetCount() == game.MaxPlayers() then
        MsgN("[LeadBot] Player limit reached!")
        return
    end

    local original_name
    local name = "Bot #" .. #player.GetBots() + 1
    local model = player_manager.TranslateToPlayerModelName(table.Random(player_manager.AllValidModels()))
    local botcolor = ColorRand()
    local botweaponcolor = ColorRand()
    local color = Vector(botcolor.r / 255, botcolor.g / 255, botcolor.b / 255)
    local weaponcolor = Vector(botweaponcolor.r / 255, botweaponcolor.g / 255, botweaponcolor.b / 255)
    local strategy = GetConVar("leadbot_strategy"):GetInt()
    local bot = player.CreateNextBot(name)

    if !IsValid(bot) then
        MsgN("[LeadBot] Unable to create bot!")
        return
    end

    bot.LeadBot_Config = {model, color, weaponcolor, strategy}

    -- for legacy purposes, will be removed soon when gamemodes are updated
    bot.BotStrategy = strategy
    bot.OriginalName = original_name
    bot.ControllerBot = ents.Create("leadbot_navigator")
    bot.ControllerBot:Spawn()
    bot.ControllerBot:SetOwner(bot)
    bot.LeadBot = true
    LeadBot.AddBotOverride(bot)
    LeadBot.AddBotControllerOverride(bot, bot.ControllerBot)
    MsgN("[LeadBot] Bot " .. name .. " with strategy " .. bot.BotStrategy .. " added!")
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

    -- gamemode spawns us asap for some reason, let's try to override this and "pick our loadout"
    bot:KillSilent()
    bot:SetDeaths(0)
    bot:SetTeamColor()
    bot.NextSpawnTime = CurTime() + GetConVar("dd_options_spawn_time"):GetInt()
end

function LeadBot.AddBotControllerOverride(bot, controller)
end

function LeadBot.PlayerSpawn(bot)
    if !bot:IsBot() then return end

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

    -- melee only person
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

local gametype
local door_enabled

cvars.AddChangeCallback("dd_gametype", function(_, _, game)
    if gametype then
        gametype = game
    end
end)

function LeadBot.Think()
    if !gametype then
        LeadBot.TeamPlay = GAMEMODE:GetGametype() ~= "ffa"
        gametype = GAMEMODE:GetGametype()

        if ents.FindByClass("prop_door_rotating")[1] then
            door_enabled = true
        end
    end

    for _, bot in player.Iterator() do
        if bot:IsLBot() then
            if bot.NextSpawnTime and !bot:Alive() and bot.NextSpawnTime < CurTime() then
                bot:Spawn()
                return
            end

            local wep = bot:GetActiveWeapon()
            if IsValid(wep) then
                local ammoty = wep:GetPrimaryAmmoType() or wep.Primary.Ammo
                bot:SetAmmo(wep.Primary.DefaultClip, ammoty)
            end
        end
    end
end

function LeadBot.PostPlayerDeath(bot)
end

function LeadBot.PlayerHurt(ply, bot, hp, dmg)
    local controller = ply:GetController()

    controller.LookAtTime = CurTime() + 2
    controller.LookAt = ((bot:GetPos() + VectorRand() * 128) - ply:GetPos()):Angle()
end

function LeadBot.FindClosest(controller)
    local players = team.GetPlayers(TEAM_BLUE)
    local distance = 9999
    local playing = players[1]
    local distanceplayer = 9999999
    for k, v in ipairs(players) do
        if v:Alive() then
            distanceplayer = v:GetPos():DistToSqr(controller:GetPos())
            if distance > distanceplayer and v ~= controller then
                distance = distanceplayer
                playing = v
            end
        end
    end

    controller.Target = playing
end

function LeadBot.StartCommand(bot, cmd)
    local buttons = 0
    local botWeapon = bot:GetActiveWeapon()
    local controller = bot.ControllerBot
    local target = controller.Target

    if !IsValid(controller) then return end

    if not IsValid(target) then
        buttons = buttons + IN_SPEED
    end

    if IsValid(botWeapon) then
        if (botWeapon:Clip1() == 0 or !IsValid(target) and botWeapon:Clip1() <= botWeapon:GetMaxClip1() / 2) then
            buttons = buttons + IN_RELOAD
        end

        if IsValid(target) and (math.random(2) == 1 or botWeapon:GetClass() == "dd_striker") then
            bot:SwitchSpell()
            buttons = buttons + IN_ATTACK + ((!bot:IsThug() and IN_ATTACK2) or 0)
            if math.random((botWeapon.Base == "dd_meleebase" and 6) or 16) == 1 then
                buttons = buttons + IN_USE
            end
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
        controller.NextJump = -1
        buttons = buttons + IN_FORWARD
    end

    if controller.NextDuck > CurTime() then
        buttons = buttons + IN_DUCK
    elseif controller.NextJump == 0 then
        controller.NextJump = CurTime() + 1
        buttons = buttons + IN_JUMP
    end

    --[[if controller.MovingBack and math.random(6) == 1 then
        buttons = buttons + IN_USE
    end]]

    if !bot:IsOnGround() and controller.NextJump > CurTime() then
        buttons = buttons + IN_DUCK
    end

    -- bot:SelectWeapon((IsValid(controller.Target) and controller.Target:GetPos():DistToSqr(controller:GetPos()) < 129000 and "weapon_shotgun") or "weapon_smg1")
    cmd:ClearButtons()
    cmd:ClearMovement()
    cmd:SetButtons(buttons)
end

local objective

function LeadBot.CanSee(bot, target)
    if not IsValid(bot) or not IsValid(target) then return false end

    local botPos = bot:WorldSpaceCenter()
    local targetPos = target:WorldSpaceCenter()

    local tr = util.TraceLine({
        start = botPos,
        endpos = targetPos,
        filter = {bot, bot.ControllerBot}
    })

    return tr.Entity == target
end

function LeadBot.PlayerMove(bot, cmd, mv)
    local controller = bot.ControllerBot

    if !IsValid(controller) then
        bot.ControllerBot = ents.Create("leadbot_navigator")
        bot.ControllerBot:Spawn()
        bot.ControllerBot:SetOwner(bot)
        controller = bot.ControllerBot
    end

    local wep = bot:GetActiveWeapon()

    --[[local min, max = controller:GetModelBounds()
    debugoverlay.Box(controller:GetPos(), min, max, 0.1, Color(255, 0, 0, 0), true)]]

    -- force a recompute
    if controller.PosGen and controller.P and controller.TPos ~= controller.PosGen then
        controller.TPos = controller.PosGen
        controller.P:Compute(controller, controller.PosGen)
    end

    if controller:GetPos() ~= bot:GetPos() then
        controller:SetPos(bot:GetPos())
    end

    if controller:GetAngles() ~= bot:EyeAngles() then
        controller:SetAngles(bot:EyeAngles())
    end

    mv:SetForwardSpeed(1200)

    local zombies = gametype == "ts"
    local melee = IsValid(wep) and wep.Base == "dd_meleebase"

    if ((bot.NextSpawnTime and bot.NextSpawnTime + 1 > CurTime()) or !IsValid(controller.Target) or controller.ForgetTarget < CurTime() or !controller.Target:Alive()) then
        controller.Target = nil
    end

    if !IsValid(controller.Target) then
        if zombies and bot:Team() == TEAM_THUG then
            LeadBot.FindClosest(controller)
        else
            for _, ply in player.Iterator() do
                if ply ~= bot and ((ply:IsPlayer() and (!LeadBot.TeamPlay or (LeadBot.TeamPlay and (ply:Team() ~= bot:Team())))) or ply:IsNPC()) and ply:GetPos():DistToSqr(bot:GetPos()) < 2250000 then
                    --[[local targetpos = ply:EyePos() - Vector(0, 0, 10)
                    local trace = util.TraceLine({
                        start = bot:GetShootPos(),
                        endpos = targetpos,
                        filter = function(ent) return ent == ply end
                    })]]

                    if ply:Alive() and LeadBot.CanSee(bot, ply) then
                        controller.Target = ply
                        controller.ForgetTarget = CurTime() + 2
                    end
                end
            end
        end
    elseif controller.ForgetTarget < CurTime() and LeadBot.CanSee(bot, controller.Target) then
        controller.ForgetTarget = CurTime() + 2
    end

    if door_enabled then
        local dt = util.QuickTrace(bot:EyePos(), bot:GetForward() * 45, bot)

        if IsValid(dt.Entity) and dt.Entity:GetClass() == "prop_door_rotating" then
            dt.Entity:Fire("OpenAwayFrom", bot, 0)
        end
    end

    -- controller.MovingBack = false

    if !IsValid(controller.Target) and (!controller.PosGen or (gametype ~= "htf" and gametype ~= "koth" and bot:GetPos():DistToSqr(controller.PosGen) < 1000) or controller.LastSegmented < CurTime()) then
        if gametype == "htf" then
            if bot:IsCarryingFlag() then
                controller.PosGen = controller:FindSpot("random", {radius = 12500})
                controller.LastSegmented = CurTime() + 8
            else
                if !IsValid(objective) then
                    objective = ents.FindByClass("htf_flag")[1]
                end

                local flag = objective
                local rand = 64

                if !IsValid(flag:GetCarrier()) then
                    rand = 32
                end

                rand = VectorRand() * rand
                controller.PosGen = flag:GetPos() + Vector(rand.x, rand.y, 0)
                controller.LastSegmented = CurTime() + math.random(2, 3)
            end
        elseif gametype == "koth" then
            if !IsValid(objective) then
                objective = ents.FindByClass("koth_point")[1]
            end

            local point = objective
            local point_pos = point:GetPos()
            local rand = (point:GetRadius() - 12)

            if IsValid(controller.Target) then
                rand = rand * 1.25
            end

            rand = VectorRand() * rand
            controller.PosGen = point_pos + Vector(rand.x, rand.y, 0)
            controller.LastSegmented = CurTime() + math.random(3, 6)
        else
            -- find a random spot on the map, and in 10 seconds do it again!
            controller.PosGen = controller:FindSpot("random", {radius = 12500})
            controller.LastSegmented = CurTime() + 10
        end
    elseif IsValid(controller.Target) and ((gametype == "htf" and !bot:IsCarryingFlag()) or (gametype ~= "koth" and (bot:LBGetStrategy() ~= 1 or !melee)) or true) then
        -- move to our target
        local distance = controller.Target:GetPos():DistToSqr(bot:GetPos())
        if controller.LastSegmented < CurTime() then
            controller.PosGen = controller.Target:GetPos()
            controller.LastSegmented = CurTime() + ((melee and math.Rand(0.7, 0.9)) or math.Rand(1.1, 1.3))
        end

        -- back up if the target is really close
        -- TODO: find a random spot rather than trying to back up into what could just be a wall
        -- something like controller.PosGen = controller:FindSpot("random", {pos = bot:GetPos() - bot:GetForward() * 350, radius = 1000})?
        if !melee and distance <= 90000 then
            -- controller.MovingBack = true
            mv:SetForwardSpeed(-1200)
        end
    end

    -- movement also has a similar issue, but it's more severe...
    if !controller.P then
        return
    end

    local segments = controller.P:GetAllSegments()

    if !segments then return end

    local cur_segment = controller.cur_segment
    local curgoal = segments[cur_segment]

    -- got nowhere to go, why keep moving?
    if !curgoal then
        mv:SetForwardSpeed(0)
        return
    end

    -- think every step of the way!
    if segments[cur_segment + 1] and Vector(bot:GetPos().x, bot:GetPos().y, 0):DistToSqr(Vector(curgoal.pos.x, curgoal.pos.y)) < 100 then
        controller.cur_segment = controller.cur_segment + 1
        curgoal = segments[controller.cur_segment]
    end

    local goalpos = curgoal.pos

    local inobjective = false

    if gametype == "koth" then
        if IsValid(objective) then
            objective.radius2d = objective.radius2d or (objective:GetRadius() - 4) * (objective:GetRadius() - 4)
        end

        inobjective = IsValid(objective) and objective:GetPos():DistToSqr(controller:GetPos()) <= objective.radius2d
    end

    if bot:GetVelocity():Length2DSqr() <= 225 and (gametype ~= "koth" or !inobjective) then
        if controller.NextCenter < CurTime() then
            controller.strafeAngle = ((controller.strafeAngle == 1 and 2) or 1)
            -- curgoal.pos = curgoal.area:GetCenter()
            -- goalpos = segments[controller.cur_segment - 1].area:GetCenter()

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
            mv:SetSideSpeed(1500)
        elseif controller.strafeAngle == 2 then
            mv:SetSideSpeed(-1500)
        else
            mv:SetForwardSpeed(-1500)
        end
    end

    -- jump
    if controller.NextJump ~= 0 and curgoal.type > 1 and controller.NextJump < CurTime() then
        controller.NextJump = 0
    end

    -- duck
    if curgoal.area:GetAttributes() == NAV_MESH_CROUCH then
        controller.NextDuck = CurTime() + 0.1
    end

    controller.goalPos = goalpos

    if GetConVar("developer"):GetBool() then
        controller.P:Draw()
    end

    -- eyesight
    local lerp = FrameTime() * math.random(8, 10)
    local lerpc = FrameTime() * 8

    if !LeadBot.LerpAim then
        lerp = 1
        lerpc = 1
    end

    local mva = ((goalpos + bot:GetCurrentViewOffset()) - bot:GetShootPos()):Angle()

    mv:SetMoveAngles(mva)

    if IsValid(controller.Target) then
        local targetpos = controller.Target:EyePos()
        -- targetpos.z = math.random(controller.Target:GetPos().z, targetpos.z)
        -- targetpos = targetpos + VectorRand() * 64

        bot:SetEyeAngles(LerpAngle(lerp, bot:EyeAngles(), (targetpos - bot:GetShootPos()):Angle()))
        return
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

hook.Add("PostPlayerDeath", "LeadBot_Death", function(bot)
    if bot:IsLBot() then
        LeadBot.PostPlayerDeath(bot)
    end
end)

hook.Add("EntityTakeDamage", "LeadBot_Hurt", function(ply, dmgi)
    local bot = dmgi:GetAttacker()
    local hp = ply:Health()
    local dmg = dmgi:GetDamage()

    if IsValid(ply) and ply:IsPlayer() and ply:IsLBot() then
        LeadBot.PlayerHurt(ply, bot, hp, dmg)
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

--[[ META ]]--

local player_meta = FindMetaTable("Player")
local oldInfo = player_meta.GetInfo

function player_meta.IsLBot(self, realbotsonly)
    if realbotsonly == true then
        return self.LeadBot and self:IsBot() or false
    end

    return self.LeadBot or false
end

function player_meta.LBGetStrategy(self)
    if self.LeadBot_Config then
        return self.LeadBot_Config[4]
    else
        return 0
    end
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
            return self:LBGetModel() --self.LeadBot_Config[1]
        elseif convar == "cl_playercolor" then
            return self:LBGetColor() --self.LeadBot_Config[2]
        elseif convar == "cl_weaponcolor" then
            return self:LBGetColor(true) --self.LeadBot_Config[3]
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