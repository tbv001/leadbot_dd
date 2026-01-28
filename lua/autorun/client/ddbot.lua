if game.SinglePlayer() or engine.ActiveGamemode() ~= "darkestdays" then return end

DDBot = {}
include("ddbot/shared.lua")

hook.Add("CalcMainActivity", "DDBot_CalcMainActivity", DDBot.BotAnimations)