if game.SinglePlayer() or engine.ActiveGamemode() ~= "darkestdays" then return end

AddCSLuaFile("ddbot/shared.lua")

include("ddbot/bot.lua")