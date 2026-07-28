--[[
	Boombox server half  (Script inside the Boombox Tool)

	Plays the audio on the Handle so everyone nearby hears it.
	The client half only sends the ID; all validation happens here.

	Written for Roblox/Luau 2021 and earlier.
--]]

local tool = script.Parent
local remote = tool:WaitForChild("BoomboxRemote")
local handle = tool:WaitForChild("Handle")

local MAX_VOLUME = 1
local ROLLOFF = 90
local COOLDOWN = 1

local sound = handle:FindFirstChild("BoomboxSound")
if not sound then
	sound = Instance.new("Sound")
	sound.Name = "BoomboxSound"
	sound.Volume = MAX_VOLUME
	sound.Looped = true
	sound.RollOffMaxDistance = ROLLOFF
	sound.Parent = handle
end

local lastUse = 0

local function ownerOf()
	local parent = tool.Parent
	if not parent then
		return nil
	end
	local Players = game:GetService("Players")
	local p = Players:GetPlayerFromCharacter(parent)
	if p then
		return p
	end
	if parent:IsA("Backpack") then
		return parent.Parent
	end
	return nil
end

remote.OnServerEvent:Connect(function(player, action, value)
	-- Only the person holding it may drive it.
	if player ~= ownerOf() then
		return
	end

	local now = tick()
	if (now - lastUse) < COOLDOWN then
		return
	end
	lastUse = now

	if action == "Play" then
		if type(value) ~= "string" and type(value) ~= "number" then
			return
		end
		local digits = string.match(tostring(value), "^%s*(%d+)%s*$")
		if not digits or string.len(digits) > 18 then
			return
		end

		sound:Stop()
		sound.SoundId = "rbxassetid://" .. digits
		local ok, err = pcall(function()
			sound:Play()
		end)
		if not ok then
			warn("[Boombox] Could not play " .. digits .. ": " .. tostring(err))
		end

	elseif action == "Stop" then
		sound:Stop()
	end
end)

tool.Unequipped:Connect(function()
	sound:Stop()
end)
