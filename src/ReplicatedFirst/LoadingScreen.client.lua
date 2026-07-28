--[[
	Fake loading screen  (ReplicatedFirst.LoadingScreen, a LocalScript)

	Counts to ~10,000 assets in ~5 seconds, then fades out.

	The count is driven by ELAPSED TIME, not one wait() per asset: 10,000
	waits would take several minutes. This way it always finishes in
	LOAD_SECONDS no matter what the framerate is.

	Purely cosmetic. Matches the booth dark theme.

	Written for Roblox/Luau 2021 and earlier.
--]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TOTAL_ASSETS = 10000
local LOAD_SECONDS = 5
local FADE_SECONDS = 0.6
local TITLE = "RATE MY AVATAR"

local THEME = {
	PanelBackground = Color3.fromRGB(12, 12, 14),
	PanelStroke = Color3.fromRGB(64, 69, 78),
	BarBackground = Color3.fromRGB(24, 25, 29),
	BarFill = Color3.fromRGB(120, 235, 150),
	Text = Color3.fromRGB(236, 238, 242),
	MutedText = Color3.fromRGB(150, 156, 166),
}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

-------------------------------------------------------------------------------
-- Build
-------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ResetOnSpawn = false
gui.Parent = playerGui

local back = Instance.new("Frame")
back.Name = "Back"
back.Size = UDim2.new(1, 0, 1, 0)
back.BackgroundColor3 = THEME.PanelBackground
back.BorderSizePixel = 0
back.Parent = gui

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(0.7, 0, 0.12, 0)
title.Position = UDim2.new(0.5, 0, 0.36, 0)
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.BackgroundTransparency = 1
title.Text = TITLE
title.TextColor3 = THEME.Text
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.Parent = back

local barBack = Instance.new("Frame")
barBack.Name = "BarBack"
barBack.Size = UDim2.new(0.46, 0, 0.022, 0)
barBack.Position = UDim2.new(0.5, 0, 0.52, 0)
barBack.AnchorPoint = Vector2.new(0.5, 0.5)
barBack.BackgroundColor3 = THEME.BarBackground
barBack.BorderSizePixel = 0
barBack.Parent = back

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(1, 0)
barCorner.Parent = barBack

local barStroke = Instance.new("UIStroke")
barStroke.Color = THEME.PanelStroke
barStroke.Thickness = 2
barStroke.Parent = barBack

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.new(0, 0, 1, 0)
fill.BackgroundColor3 = THEME.BarFill
fill.BorderSizePixel = 0
fill.Parent = barBack

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

local counter = Instance.new("TextLabel")
counter.Name = "Counter"
counter.Size = UDim2.new(0.6, 0, 0.05, 0)
counter.Position = UDim2.new(0.5, 0, 0.58, 0)
counter.AnchorPoint = Vector2.new(0.5, 0.5)
counter.BackgroundTransparency = 1
counter.Text = "Loading assets.. 0 / " .. TOTAL_ASSETS
counter.TextColor3 = THEME.MutedText
counter.TextScaled = true
counter.Font = Enum.Font.Gotham
counter.Parent = back

-------------------------------------------------------------------------------
-- Count
-------------------------------------------------------------------------------

local startedAt = tick()
local connection

connection = RunService.RenderStepped:Connect(function()
	local elapsed = tick() - startedAt
	local alpha = elapsed / LOAD_SECONDS
	if alpha > 1 then
		alpha = 1
	end

	-- Ease out slightly so it sprints then settles, like a real loader.
	local eased = 1 - (1 - alpha) * (1 - alpha)
	local shown = math.floor(eased * TOTAL_ASSETS)

	counter.Text = "Loading assets.. " .. shown .. " / " .. TOTAL_ASSETS
	fill.Size = UDim2.new(eased, 0, 1, 0)

	if alpha >= 1 then
		if connection then
			connection:Disconnect()
			connection = nil
		end

		counter.Text = "Loaded " .. TOTAL_ASSETS .. " assets"

		local info = TweenInfo.new(FADE_SECONDS)
		TweenService:Create(back, info, {BackgroundTransparency = 1}):Play()
		TweenService:Create(title, info, {TextTransparency = 1}):Play()
		TweenService:Create(counter, info, {TextTransparency = 1}):Play()
		TweenService:Create(barBack, info, {BackgroundTransparency = 1}):Play()
		TweenService:Create(fill, info, {BackgroundTransparency = 1}):Play()
		TweenService:Create(barStroke, info, {Transparency = 1}):Play()

		delay(FADE_SECONDS + 0.1, function()
			gui:Destroy()
		end)
	end
end)
