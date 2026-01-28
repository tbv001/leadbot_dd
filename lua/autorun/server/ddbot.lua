if game.SinglePlayer() or engine.ActiveGamemode() ~= "darkestdays" then return end

AddCSLuaFile("ddbot/shared.lua")

DDBot = {}
include("ddbot/bot.lua")