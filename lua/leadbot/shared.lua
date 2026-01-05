-- https://github.com/Necrossin/darkestdays/blob/master/gamemode/obj_player_extend.lua#L165
function RunningCheck(bot)
    local walkSpeed = bot:GetWalkSpeed()
    return bot:GetVelocity():LengthSqr() >= (math.pow(walkSpeed, 2) + 2500 - 100)
end

function CalcMainActivityBots(bot, vel)
    if bot:IsBot() then
        if RunningCheck(bot) then
            local activeWeapon = bot:GetActiveWeapon()
            local sequence = "run_all_charging"
            if IsValid(activeWeapon) then
                if activeWeapon.RunSequence then
                    sequence = activeWeapon:RunSequence()
                end
            end
            return ACT_MP_RUN, bot:LookupSequence(sequence)
        end
    end
end