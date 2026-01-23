if game.SinglePlayer() or engine.ActiveGamemode() ~= "darkestdays" then return end

include("ddbot/shared.lua")

hook.Add("CalcMainActivity", "DDBot_CalcMainActivity", CalcMainActivityBots)