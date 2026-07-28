--[[
	Booth server script  (ServerScriptService)

	Original booth system by ywinfe and thugshaker.

	Written for Roblox/Luau 2021 and earlier:
	  * no task.*, no attributes, no string interpolation
	  * only wait(), tick(), pcall(), type()

	Gamepasses (all Pekora catalog assets, bought with PromptPurchase):
	  UPLOAD      set the image on the booth you claimed
	  BOOMBOX     grants a working boombox tool
	  PERMANENT   your image STAYS on that booth after you leave

	Permanent images are saved per booth (by index) in a DataStore, so they
	survive unclaim, disconnect and server restarts. The next player to claim
	that booth inherits the image, and can only replace it if they own UPLOAD.

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
local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")

local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local Booths = Workspace:WaitForChild("Booths")

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

-- Shown on unclaimed booths and on any booth with no saved image.
local DEFAULT_IMAGE = "rbxassetid://821176"

local FILTER_TEXT = true -- set false if FilterStringAsync is unavailable
local MAX_TEXT_LENGTH = 120
local ACTION_COOLDOWN = 1 -- seconds between remote actions per player

local USE_DATASTORE = true -- false = permanent images last only this server
local DATASTORE_NAME = "BoothImages_v1"
local SAVE_RETRIES = 3

-------------------------------------------------------------------------------
-- Gamepasses
-------------------------------------------------------------------------------
--[[
	On Pekora, real game passes do not work, so passes are sold as catalog
	shirts. Every entry here is therefore an ASSET:

	    ownership -> MarketplaceService:PlayerOwnsAsset(Player, Id)
	    purchase  -> MarketplaceService:PromptPurchase(Player, Id)
	    finished  -> MarketplaceService.PromptPurchaseFinished

	IsGamePass is left in only in case Pekora ever fixes real passes; keep it
	false for /catalog/ links. Ids come straight from the URL:
	    https://www.pekora.zip/catalog/356360/Thugshaker-fan-shirt
	                                    ^^^^^^
--]]

local PASSES = {
	UPLOAD = {
		Id = 356360,
		IsGamePass = false,
		Title = "Image Upload Gamepass",
		Blurb = "Put your own image on the booth you claim.",
	},
	BOOMBOX = {
		Id = 353454,
		IsGamePass = false,
		Title = "Boombox Gamepass",
		Blurb = "Carry a boombox and play any audio ID.",
	},
	PERMANENT = {
		Id = 353447,
		IsGamePass = false,
		Title = "Permanent Image Gamepass",
		Blurb = "Your image stays on the booth after you leave.",
	},
}

-- Order the shop lists them in.
local SHOP_ORDER = {"UPLOAD", "PERMANENT", "BOOMBOX"}

-- Player-facing wording never names the shirts.
local PASS_WORD = "Gamepass"

local OWNERSHIP_CACHE_SECONDS = 30

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local LastAction = {} -- [Player]           = tick() of last accepted action
local LastCheck = {} -- [Player]           = tick() of last passive refresh
local Ownership = {} -- [Player][Key]      = {Owns = bool, Time = number}
local BoothIndex = {} -- [Booth]            = stable number
local BoothImage = {} -- [Booth]            = saved image string or nil
local BoothDirty = {} -- [Booth]            = true when it needs saving

local ImageStore = nil
if USE_DATASTORE then
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore(DATASTORE_NAME)
	end)
	if ok then
		ImageStore = res
	else
		warn("[Booth] DataStore unavailable, permanent images will not persist: " .. tostring(res))
	end
end

-------------------------------------------------------------------------------
-- Booth helpers
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

local function SetNamePlate(Booth, Text)
	local Part = Booth:FindFirstChild("PartNamePlayer")
	if not Part then
		return
	end
	local SurfaceGui = Part:FindFirstChild("SurfaceGui")
	if not SurfaceGui then
		return
	end
	local Label = SurfaceGui:FindFirstChild("TextLabel")
	if Label then
		Label.Text = Text
	end
end

-- Whatever this booth should be showing right now.
local function CurrentImage(Booth)
	return BoothImage[Booth] or DEFAULT_IMAGE
end

local function ApplyImage(Booth)
	Booth.Display.SurfaceGui.ImageLabel.Image = CurrentImage(Booth)
end

-------------------------------------------------------------------------------
-- Saving permanent images
-------------------------------------------------------------------------------

local function KeyFor(Booth)
	return "booth_" .. tostring(BoothIndex[Booth] or 0)
end

local function LoadBoothImage(Booth)
	if not ImageStore then
		return
	end

	local ok, res = pcall(function()
		return ImageStore:GetAsync(KeyFor(Booth))
	end)

	if ok and type(res) == "string" and res ~= "" then
		BoothImage[Booth] = res
	elseif not ok then
		warn("[Booth] Could not load image for " .. KeyFor(Booth) .. ": " .. tostring(res))
	end
end

local function SaveBoothImage(Booth)
	if not ImageStore then
		BoothDirty[Booth] = nil
		return
	end

	local key = KeyFor(Booth)
	local value = BoothImage[Booth]

	for attempt = 1, SAVE_RETRIES do
		local ok, err = pcall(function()
			ImageStore:SetAsync(key, value)
		end)
		if ok then
			BoothDirty[Booth] = nil
			return true
		end
		if attempt == SAVE_RETRIES then
			warn("[Booth] Could not save " .. key .. ": " .. tostring(err))
		else
			wait(2)
		end
	end
	return false
end

-------------------------------------------------------------------------------
-- Ownership
-------------------------------------------------------------------------------

local function DoOwnershipCheck(Player, Pass)
	local Owns = false

	local Success, Result = pcall(function()
		if Pass.IsGamePass then
			return MarketplaceService:UserOwnsGamePassAsync(Player.UserId, Pass.Id)
		end
		-- PlayerOwnsAsset takes the Player object, not the UserId.
		return MarketplaceService:PlayerOwnsAsset(Player, Pass.Id)
	end)

	if Success then
		Owns = (Result == true)
	else
		-- Fail closed: never hand out a perk because the API broke.
		warn("[Booth] Ownership check failed for " .. Player.Name .. ": " .. tostring(Result))
	end

	return Owns
end

local function PlayerOwns(Player, Key, UseCache)
	local Pass = PASSES[Key]
	if not Pass then
		return false
	end

	local byPlayer = Ownership[Player]
	if not byPlayer then
		byPlayer = {}
		Ownership[Player] = byPlayer
	end

	if UseCache ~= false then
		local Cached = byPlayer[Key]
		if Cached and (tick() - Cached.Time) < OWNERSHIP_CACHE_SECONDS then
			return Cached.Owns
		end
	end

	local Owns = DoOwnershipCheck(Player, Pass)

	if Player.Parent ~= nil then
		byPlayer[Key] = {Owns = Owns, Time = tick()}
	end
	return Owns
end

-- One payload the client uses for both the booth UI and the shop.
local function PushPassState(Player, UseCache)
	local state = {}
	for _, Key in ipairs(SHOP_ORDER) do
		local Pass = PASSES[Key]
		state[#state + 1] = {
			Key = Key,
			Id = Pass.Id,
			Title = Pass.Title,
			Blurb = Pass.Blurb,
			Owns = PlayerOwns(Player, Key, UseCache),
		}
	end

	if Player.Parent ~= nil then
		RemoteEvent:FireClient(Player, "PassState", state)
	end
	return state
end

-------------------------------------------------------------------------------
-- Boombox
-------------------------------------------------------------------------------

local function FindBoomboxTemplate()
	local direct = ServerStorage:FindFirstChild("Boombox")
	if direct and direct:IsA("Tool") then
		return direct
	end
	for _, d in ipairs(ServerStorage:GetDescendants()) do
		if d:IsA("Tool") and d.Name == "Boombox" then
			return d
		end
	end
	return nil
end

local function GiveBoombox(Player)
	if not PlayerOwns(Player, "BOOMBOX", true) then
		return false
	end

	local template = FindBoomboxTemplate()
	if not template then
		warn("[Booth] No Boombox tool found in ServerStorage.")
		return false
	end

	local backpack = Player:FindFirstChildOfClass("Backpack")
	if backpack and not backpack:FindFirstChild("Boombox") then
		template:Clone().Parent = backpack
	end

	local gear = Player:FindFirstChild("StarterGear")
	if gear and not gear:FindFirstChild("Boombox") then
		template:Clone().Parent = gear
	end

	return true
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
-- Claiming
-------------------------------------------------------------------------------

-- Unclaiming must NOT wipe the image: a permanent image belongs to the booth,
-- not to whoever happens to be standing in it.
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

	ApplyImage(Booth)
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
	SetNamePlate(Booth, Player.Name)
	OwnedBooth.Value = Booth

	-- Inherit whatever image is already on this booth.
	ApplyImage(Booth)

	RemoteEvent:FireClient(Player, "DisablePrompts")
	RemoteEvent:FireClient(Player, "OpenGui")
end

local function SetupBooth(Booth, index)
	if not IsBooth(Booth) then
		return
	end

	BoothIndex[Booth] = index

	GetPrompt(Booth).Triggered:Connect(function(Player)
		ClaimBooth(Player, Booth)
	end)

	Booth.Display.BoothOwner.Value = nil
	Booth.Display.SurfaceGui.TextLabel.Text = "Unclaimed Booth"
	SetNamePlate(Booth, "None")
	GetPrompt(Booth).Enabled = true
	GetPrompt(Booth).ObjectText = "Claim Booth"
	ApplyImage(Booth)
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
			warn("[Booth] Text filtering failed: " .. tostring(ErrorMessage))
			RemoteEvent:FireClient(Player, "TextError", "Text filter is unavailable, try again.")
			return
		end
	end

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

	-- Enforced on the server. Hiding the button client-side is only cosmetic.
	if not PlayerOwns(Player, "UPLOAD", true) then
		PushPassState(Player, true)
		RemoteEvent:FireClient(Player, "ImageError", "Custom images need the " .. PASS_WORD .. ".")
		return
	end

	if not IsBooth(Booth) or Booth.Display.BoothOwner.Value ~= Player then
		return
	end

	local Permanent = PlayerOwns(Player, "PERMANENT", true)

	if not IsBooth(Booth) or Booth.Display.BoothOwner.Value ~= Player then
		return
	end

	if Permanent then
		BoothImage[Booth] = ImageContent
		BoothDirty[Booth] = true
		Booth.Display.SurfaceGui.ImageLabel.Image = ImageContent
		SaveBoothImage(Booth)
		RemoteEvent:FireClient(Player, "ImageChanged", "Image set. It will stay on this booth.")
	else
		-- No PERMANENT pass: show it now, but do not overwrite the saved one.
		Booth.Display.SurfaceGui.ImageLabel.Image = ImageContent
		RemoteEvent:FireClient(Player, "ImageChanged", "Image set for now. Buy the "
			.. PASS_WORD .. " to make it stay.")
	end
end

RemoteEvent.OnServerEvent:Connect(function(Player, Argument, Argument2)
	if type(Argument) ~= "string" then
		return
	end

	if Argument == "PromptPurchase" then
		if not CheckCooldown(Player) then
			return
		end
		local Pass = PASSES[Argument2]
		if not Pass then
			return
		end
		if PlayerOwns(Player, Argument2, true) then
			PushPassState(Player, true)
			return
		end
		local ok, err = pcall(function()
			if Pass.IsGamePass then
				MarketplaceService:PromptGamePassPurchase(Player, Pass.Id)
			else
				MarketplaceService:PromptPurchase(Player, Pass.Id)
			end
		end)
		if not ok then
			warn("[Booth] Purchase prompt failed: " .. tostring(err))
			RemoteEvent:FireClient(Player, "ImageError", "Could not open the store page.")
		end
		return

	elseif Argument == "CheckPasses" then
		local Now = tick()
		local Last = LastCheck[Player]
		if not Last or (Now - Last) >= ACTION_COOLDOWN then
			LastCheck[Player] = Now
			PushPassState(Player, true)
		end
		return
	end

	local OwnedBooth = Player:FindFirstChild("OwnedBooth")
	local Booth = nil
	if OwnedBooth then
		Booth = OwnedBooth.Value
	end

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
	PushPassState(Player, false)

	GiveBoombox(Player)
	Player.CharacterAdded:Connect(function()
		wait(1)
		GiveBoombox(Player)
	end)
end

local function PlayerRemoving(Player)
	local OwnedBooth = Player:FindFirstChild("OwnedBooth")
	if OwnedBooth and OwnedBooth.Value then
		ResetBooth(nil, OwnedBooth.Value)
	end

	for _, Booth in pairs(Booths:GetChildren()) do
		if IsBooth(Booth) and Booth.Display.BoothOwner.Value == Player then
			ResetBooth(nil, Booth)
		end
	end

	LastAction[Player] = nil
	LastCheck[Player] = nil
	Ownership[Player] = nil
end

-------------------------------------------------------------------------------
-- Purchase completion
-------------------------------------------------------------------------------

local ById = {}
for Key, Pass in pairs(PASSES) do
	ById[Pass.Id] = Key
end

local function OnPurchaseFinished(Player, Id, WasPurchased)
	if not WasPurchased then
		return
	end
	if typeof(Player) ~= "Instance" or not Player:IsA("Player") then
		return
	end

	local Key = ById[tonumber(Id)]
	if not Key then
		return
	end

	-- Drop only that item's cached answer, then re-check it for real.
	local byPlayer = Ownership[Player]
	if byPlayer then
		byPlayer[Key] = nil
	end

	PushPassState(Player, false)

	if Key == "BOOMBOX" then
		GiveBoombox(Player)
	end
end

MarketplaceService.PromptPurchaseFinished:Connect(OnPurchaseFinished)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(OnPurchaseFinished)

-------------------------------------------------------------------------------
-- Start up
-------------------------------------------------------------------------------

local ordered = Booths:GetChildren()
table.sort(ordered, function(a, b)
	local ap, bp = a:FindFirstChild("Display"), b:FindFirstChild("Display")
	if ap and bp then
		if math.abs(ap.Position.X - bp.Position.X) > 0.01 then
			return ap.Position.X < bp.Position.X
		end
		return ap.Position.Z < bp.Position.Z
	end
	return a.Name < b.Name
end)

for index, Booth in ipairs(ordered) do
	if IsBooth(Booth) then
		BoothIndex[Booth] = index
		LoadBoothImage(Booth)
		SetupBooth(Booth, index)
	end
end

Booths.ChildAdded:Connect(function(Booth)
	wait()
	if IsBooth(Booth) then
		local n = #Booths:GetChildren()
		BoothIndex[Booth] = n
		LoadBoothImage(Booth)
		SetupBooth(Booth, n)
	end
end)

for _, Player in ipairs(Players:GetPlayers()) do
	PlayerAdded(Player)
end

Players.PlayerAdded:Connect(PlayerAdded)
Players.PlayerRemoving:Connect(PlayerRemoving)

game:BindToClose(function()
	for Booth, dirty in pairs(BoothDirty) do
		if dirty then
			SaveBoothImage(Booth)
		end
	end
end)

-- Original booth system by ywinfe and thugshaker
