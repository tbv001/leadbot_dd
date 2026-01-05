AddCSLuaFile("leadbot/shared.lua")

if game.SinglePlayer() or engine.ActiveGamemode() ~= "darkestdays" then return end

LeadBot = {}

-- Core
include("leadbot/bot.lua")

-- Quota system
include("leadbot/quota.lua")