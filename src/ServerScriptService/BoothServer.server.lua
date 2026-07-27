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
local MarketplaceService = game:GetService("MarketplaceService")

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
-- Paywall
-------------------------------------------------------------------------------
--[[
	Setting a custom booth image is locked behind an item the player has to own.

	PAYWALL_ID is taken from the item's URL:
	    https://www.pekora.zip/catalog/356360/Thugshaker-fan-shirt
	                                    ^^^^^^

	PAYWALL_IS_GAMEPASS decides which API is used, and the two are NOT
	interchangeable. Pekora's "/catalog/" pages are ordinary assets (shirts,
	t-shirts, gear), so this must stay false for the link above:

	    false -> MarketplaceService:PlayerOwnsAsset(Player, Id)
	             MarketplaceService:PromptPurchase(Player, Id)
	             MarketplaceService.PromptPurchaseFinished

	    true  -> MarketplaceService:UserOwnsGamePassAsync(Player.UserId, Id)
	             MarketplaceService:PromptGamePassPurchase(Player, Id)
	             MarketplaceService.PromptGamePassPurchaseFinished

	A real game pass lives on a "/game-pass/" URL. If you switch to one, put its
	pass ID here and set PAYWALL_IS_GAMEPASS to true.
--]]

local PAYWALL_ENABLED = true
local PAYWALL_ID = 356360
local PAYWALL_IS_GAMEPASS = false
local PAYWALL_NAME = "Thugshaker fan shirt"

-- Ownership answers are cached so a player spamming the button cannot spam the
-- web API. A successful purchase clears the entry immediately.
local OWNERSHIP_CACHE_SECONDS = 30

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local LastAction = {} -- [Player] = tick() of the last accepted remote call
local LastCheck = {} -- [Player] = tick() of the last paywall refresh request
local OwnsPaywall = {} -- [Player] = {Owns = boolean, Time = number}

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

-------------------------------------------------------------------------------
-- Paywall checks
-------------------------------------------------------------------------------

-- Yields. Returns true / false, and never errors: if the web call fails we
-- deny access rather than handing out the perk for free.
local function DoOwnershipCheck(Player)
	local Owns = false

	local Success, Result = pcall(function()
		if PAYWALL_IS_GAMEPASS then
			return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, PAYWALL_ID)
		end
		-- PlayerOwnsAsset takes the Player object, not the UserId.
		return MarketplaceService:PlayerOwnsAsset(Player, PAYWALL_ID)
	end)

	if Success then
		Owns = (Result == true)
	else
		warn("Booth paywall check failed for " .. Player.Name .. ": " .. tostring(Result))
	end

	return Owns
end

local function PlayerOwnsPaywall(Player, UseCache)
	if not PAYWALL_ENABLED then
		return true
	end

	if UseCache ~= false then
		local Cached = OwnsPaywall[Player]
		if Cached and (tick() - Cached.Time) < OWNERSHIP_CACHE_SECONDS then
			return Cached.Owns
		end
	end

	local Owns = DoOwnershipCheck(Player)

	-- The player may have left while the call was yielding.
	if Player.Parent == nil then
		return Owns
	end

	OwnsPaywall[Player] = {Owns = Owns, Time = tick()}
	return Owns
end

-- Tells the client whether to show "Set Image" or "Unlock Image Uploads".
local function PushPaywallState(Player, Owns)
	RemoteEvent:FireClient(Player, "PaywallState", {
		Enabled = PAYWALL_ENABLED,
		Owns = Owns,
		Name = PAYWALL_NAME,
		Id = PAYWALL_ID,
	})
end

local function RefreshPaywallState(Player, UseCache)
	local Owns = PlayerOwnsPaywall(Player, UseCache)
	if Player.Parent ~= nil then
		PushPaywallState(Player, Owns)
	end
	return Owns
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

	-- The paywall is enforced HERE, on the server. Hiding the button on the
	-- client is only cosmetic; an exploiter can always fire the remote.
	if not PlayerOwnsPaywall(Player, true) then
		PushPaywallState(Player, false)
		RemoteEvent:FireClient(Player, "ImageError",
			"Custom images need the " .. PAYWALL_NAME .. ".")
		return
	end

	-- Re-validate: the player may have unclaimed while the check was yielding.
	if not IsBooth(Booth) or Booth.Display.BoothOwner.Value ~= Player then
		return
	end

	Booth.Display.SurfaceGui.ImageLabel.Image = ImageContent
	RemoteEvent:FireClient(Player, "ImageChanged")
end

local function HandlePromptPurchase(Player)
	if not PAYWALL_ENABLED then
		return
	end

	-- Do not prompt someone who already owns it.
	if PlayerOwnsPaywall(Player, true) then
		PushPaywallState(Player, true)
		RemoteEvent:FireClient(Player, "ImageChanged")
		return
	end

	local Success, Result = pcall(function()
		if PAYWALL_IS_GAMEPASS then
			MarketplaceService:PromptGamePassPurchase(Player, PAYWALL_ID)
		else
			MarketplaceService:PromptPurchase(Player, PAYWALL_ID)
		end
	end)

	if not Success then
		warn("Could not open the purchase prompt: " .. tostring(Result))
		RemoteEvent:FireClient(Player, "ImageError", "Could not open the store page.")
	end
end

RemoteEvent.OnServerEvent:Connect(function(Player, Argument, Argument2)
	if type(Argument) ~= "string" then
		return
	end

	-- These two do not need a booth, so they are handled before the ownership
	-- test below (a player can buy the item before claiming anything).
	if Argument == "PromptPurchase" then
		if CheckCooldown(Player) then
			HandlePromptPurchase(Player)
		end
		return
	elseif Argument == "CheckPaywall" then
		-- Kept on its own throttle: this is a passive UI sync fired on join, so
		-- it must not eat the player's first real action from the cooldown.
		local Now = tick()
		local Last = LastCheck[Player]
		if not Last or (Now - Last) >= ACTION_COOLDOWN then
			LastCheck[Player] = Now
			RefreshPaywallState(Player, true)
		end
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

	-- Tell the client up front whether image uploads are unlocked.
	RefreshPaywallState(Player, false)
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
	LastCheck[Player] = nil
	OwnsPaywall[Player] = nil
end

-------------------------------------------------------------------------------
-- Purchase completion
-------------------------------------------------------------------------------

-- Assets and game passes fire two different events, so only connect the one
-- that matches PAYWALL_IS_GAMEPASS.
local function OnPurchaseFinished(Player, Id, WasPurchased)
	if not WasPurchased then
		return
	end
	if tonumber(Id) ~= PAYWALL_ID then
		return
	end
	if typeof(Player) ~= "Instance" or not Player:IsA("Player") then
		return
	end

	-- Drop the cached "does not own" answer, then re-check against the API.
	OwnsPaywall[Player] = nil
	RefreshPaywallState(Player, false)
end

if PAYWALL_ENABLED then
	if PAYWALL_IS_GAMEPASS then
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(OnPurchaseFinished)
	else
		MarketplaceService.PromptPurchaseFinished:Connect(OnPurchaseFinished)
	end
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
