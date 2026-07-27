--[[
	Booth server script  (ServerScriptService)

	Original booth system by ywinfe and thugshaker.
	Image-ID integration.

	Written for Roblox/Luau 2021 and earlier:
	  * no task.*, no attributes, no string interpolation
	  * only wait(), tick(), pcall(), type()

	No HttpService is used. A claimed booth starts on the placeholder image and
	the owner sets their own picture with an image / decal ID.

	Requirements:
	  * ReplicatedStorage.RemoteEvent
	  * Workspace.Booths.<Booth>.Display.SurfaceGui.ImageLabel / .TextLabel
	    Workspace.Booths.<Booth>.Display.Attachment.ProximityPrompt
	    Workspace.Booths.<Booth>.Display.BoothOwner (ObjectValue)
	    Workspace.Booths.<Booth>.PartNamePlayer.SurfaceGui.TextLabel
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")

local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local Booths = Workspace:WaitForChild("Booths")

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

local DEFAULT_IMAGE = "rbxasset://textures/ui/GuiImagePlaceholder.png"

local FILTER_TEXT = true -- set false if FilterStringAsync is unavailable
local MAX_TEXT_LENGTH = 120
local ACTION_COOLDOWN = 1 -- seconds between remote actions per player

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local LastAction = {} -- [Player] = tick() of the last accepted remote call

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function IsBooth(Booth)
	if typeof(Booth) ~= "Instance" then
		return false
	end
	if Booth.Parent ~= Booths then
		return false
	end

	local Display = Booth:FindFirstChild("Display")
	if not Display then
		return false
	end

	local SurfaceGui = Display:FindFirstChild("SurfaceGui")
	local Attachment = Display:FindFirstChild("Attachment")
	local Owner = Display:FindFirstChild("BoothOwner")
	if not SurfaceGui or not Attachment or not Owner then
		return false
	end

	return SurfaceGui:FindFirstChild("ImageLabel") ~= nil
		and SurfaceGui:FindFirstChild("TextLabel") ~= nil
		and Attachment:FindFirstChild("ProximityPrompt") ~= nil
end

local function GetPrompt(Booth)
	return Booth.Display.Attachment.ProximityPrompt
end

local function GetNameLabel(Booth)
	local Part = Booth:FindFirstChild("PartNamePlayer")
	if not Part then
		return nil
	end
	local SurfaceGui = Part:FindFirstChild("SurfaceGui")
	if not SurfaceGui then
		return nil
	end
	return SurfaceGui:FindFirstChild("TextLabel")
end

local function SetNamePlate(Booth, Text)
	local Label = GetNameLabel(Booth)
	if Label then
		Label.Text = Text
	end
end

-------------------------------------------------------------------------------
-- Input validation
-------------------------------------------------------------------------------

-- Only accepts a numeric image/decal asset ID. Players cannot inject a URL.
local function MakeImageContent(ImageId)
	if type(ImageId) == "number" then
		ImageId = tostring(ImageId)
	end
	if type(ImageId) ~= "string" then
		return nil
	end
	if string.len(ImageId) > 64 then
		return nil
	end

	-- Accept a bare ID, "rbxassetid://123" or a link containing "?id=123".
	local Digits = string.match(ImageId, "^%s*(%d+)%s*$")
		or string.match(ImageId, "^%s*rbxassetid://(%d+)%s*$")
		or string.match(ImageId, "[?&]id=(%d+)")

	if not Digits or Digits == "0" or string.len(Digits) > 18 then
		return nil
	end

	return "rbxassetid://" .. Digits
end

local function CheckCooldown(Player)
	local Now = tick()
	local Last = LastAction[Player]
	if Last and (Now - Last) < ACTION_COOLDOWN then
		return false
	end
	LastAction[Player] = Now
	return true
end

-------------------------------------------------------------------------------
-- Booth claiming / resetting
-------------------------------------------------------------------------------

local function ResetBooth(Player, Booth)
	if not Booth or not IsBooth(Booth) then
		if Player then
			local Owned = Player:FindFirstChild("OwnedBooth")
			if Owned then
				Owned.Value = nil
			end
			RemoteEvent:FireClient(Player, "BoothUnclaimed")
		end
		return
	end

	Booth.Display.SurfaceGui.ImageLabel.Image = DEFAULT_IMAGE
	Booth.Display.SurfaceGui.TextLabel.Text = "Unclaimed Booth"
	Booth.Display.BoothOwner.Value = nil
	SetNamePlate(Booth, "None")

	local Prompt = GetPrompt(Booth)
	Prompt.Enabled = true
	Prompt.ObjectText = "Claim Booth"

	if Player then
		local Owned = Player:FindFirstChild("OwnedBooth")
		if Owned and Owned.Value == Booth then
			Owned.Value = nil
		end
		RemoteEvent:FireClient(Player, "BoothUnclaimed")
	end
end

local function ClaimBooth(Player, Booth)
	local OwnedBooth = Player:FindFirstChild("OwnedBooth")

	-- Server-side checks stop one player claiming multiple booths and stop
	-- two players claiming the same booth at nearly the same time.
	if not OwnedBooth or OwnedBooth.Value then
		return
	end
	if not IsBooth(Booth) or Booth.Display.BoothOwner.Value then
		return
	end

	local Prompt = GetPrompt(Booth)
	Prompt.Enabled = false
	Prompt.ObjectText = Player.Name .. "'s Booth"

	Booth.Display.BoothOwner.Value = Player
	Booth.Display.SurfaceGui.TextLabel.Text = Player.Name .. "'s Booth"
	Booth.Display.SurfaceGui.ImageLabel.Image = DEFAULT_IMAGE
	SetNamePlate(Booth, Player.Name)
	OwnedBooth.Value = Booth

	RemoteEvent:FireClient(Player, "DisablePrompts")
	RemoteEvent:FireClient(Player, "OpenGui")
end

local function SetupBooth(Booth)
	if not IsBooth(Booth) then
		return
	end

	GetPrompt(Booth).Triggered:Connect(function(Player)
		ClaimBooth(Player, Booth)
	end)

	-- Start every booth in a clean state.
	Booth.Display.BoothOwner.Value = nil
	Booth.Display.SurfaceGui.ImageLabel.Image = DEFAULT_IMAGE
	Booth.Display.SurfaceGui.TextLabel.Text = "Unclaimed Booth"
	SetNamePlate(Booth, "None")
	GetPrompt(Booth).Enabled = true
end

-------------------------------------------------------------------------------
-- Remote handling
-------------------------------------------------------------------------------

local function HandleChangeText(Player, Booth, Text)
	if type(Text) ~= "string" then
		return
	end

	Text = string.sub(Text, 1, MAX_TEXT_LENGTH)
	if string.match(Text, "^%s*$") then
		RemoteEvent:FireClient(Player, "TextError", "Type something first.")
		return
	end

	local FinalText = Text

	if FILTER_TEXT then
		local Filtered
		local Success, ErrorMessage = pcall(function()
			Filtered = TextService:FilterStringAsync(Text, Player.UserId):GetChatForUserAsync(Player.UserId)
		end)

		if Success and type(Filtered) == "string" then
			FinalText = Filtered
		else
			warn("Text filtering failed: " .. tostring(ErrorMessage))
			RemoteEvent:FireClient(Player, "TextError", "Text filter is unavailable, try again.")
			return
		end
	end

	-- The player may have unclaimed while the filter call was yielding.
	if not IsBooth(Booth) or Booth.Display.BoothOwner.Value ~= Player then
		return
	end

	Booth.Display.SurfaceGui.TextLabel.Text = FinalText
	RemoteEvent:FireClient(Player, "TextChanged")
end

local function HandleChangeImage(Player, Booth, ImageId)
	local ImageContent = MakeImageContent(ImageId)
	if not ImageContent then
		RemoteEvent:FireClient(Player, "ImageError", "Enter a valid numeric image asset ID.")
		return
	end

	Booth.Display.SurfaceGui.ImageLabel.Image = ImageContent
	RemoteEvent:FireClient(Player, "ImageChanged")
end

RemoteEvent.OnServerEvent:Connect(function(Player, Argument, Argument2)
	if type(Argument) ~= "string" then
		return
	end

	local OwnedBooth = Player:FindFirstChild("OwnedBooth")
	local Booth = nil
	if OwnedBooth then
		Booth = OwnedBooth.Value
	end

	-- Ignore edit requests from players who do not own a booth.
	if not Booth or not IsBooth(Booth) or Booth.Display.BoothOwner.Value ~= Player then
		return
	end

	if not CheckCooldown(Player) then
		return
	end

	if Argument == "ChangeText" then
		HandleChangeText(Player, Booth, Argument2)
	elseif Argument == "ChangeImage" then
		HandleChangeImage(Player, Booth, Argument2)
	elseif Argument == "UnclaimBooth" then
		ResetBooth(Player, Booth)
		RemoteEvent:FireClient(Player, "EnablePrompts")
	end
end)

-------------------------------------------------------------------------------
-- Players
-------------------------------------------------------------------------------

local function PlayerAdded(Player)
	local OwnedBooth = Player:FindFirstChild("OwnedBooth")
	if not OwnedBooth then
		OwnedBooth = Instance.new("ObjectValue")
		OwnedBooth.Name = "OwnedBooth"
		OwnedBooth.Value = nil
		OwnedBooth.Parent = Player
	end

	RemoteEvent:FireClient(Player, "Start")
end

local function PlayerRemoving(Player)
	local OwnedBooth = Player:FindFirstChild("OwnedBooth")
	if OwnedBooth and OwnedBooth.Value then
		ResetBooth(nil, OwnedBooth.Value)
	end

	-- Safety net: release any booth still pointing at this player.
	for _, Booth in pairs(Booths:GetChildren()) do
		if IsBooth(Booth) and Booth.Display.BoothOwner.Value == Player then
			ResetBooth(nil, Booth)
		end
	end

	LastAction[Player] = nil
end

for _, Booth in pairs(Booths:GetChildren()) do
	SetupBooth(Booth)
end
Booths.ChildAdded:Connect(function(Booth)
	wait() -- let the booth's children replicate before wiring it up
	SetupBooth(Booth)
end)

for _, Player in ipairs(Players:GetPlayers()) do
	PlayerAdded(Player)
end

Players.PlayerAdded:Connect(PlayerAdded)
Players.PlayerRemoving:Connect(PlayerRemoving)

-- Original booth system by ywinfe and thugshaker
