--[[
	Loading screen  (ReplicatedFirst.LoadingScreen, a LocalScript)

	Styled after the stock Roblox loader: flat dark grey, thin light type,
	and a spinning cube in the bottom right corner.

	Counts to ~10,000 assets in ~5 seconds, then fades out. The count is driven
	by ELAPSED TIME, not one wait() per asset, so it always finishes in
	LOAD_SECONDS no matter what the framerate is.

	Written for Roblox/Luau 2021 and earlier.
--]]

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-------------------------------------------------------------------------------
-- Configuration
-------------------------------------------------------------------------------

local TOTAL_ASSETS = 10000
local LOAD_SECONDS = 5
local FADE_SECONDS = 0.6

local TITLE = "Rate My Avatar"
local SUBTITLE = "By Korone"

--[[
	Optional logo shown above the title. Fill this in when you have one:

	    local LOGO_IMAGE = "rbxassetid://123456789"

	Leave it as "" and the text title is used on its own.
--]]
local LOGO_IMAGE = ""
local LOGO_HEIGHT = 0.20 -- fraction of screen height

--[[
	The spinning cube. Leave CUBE_IMAGE as "" to draw a plain white square,
	which already reads as the classic corner cube. Point it at a picture of
	the logo/cube if you would rather use art:

	    local CUBE_IMAGE = "rbxassetid://123456789"
--]]
local CUBE_IMAGE = ""
local CUBE_SPIN_SECONDS = 1.6 -- one full turn

local SHOW_BAR = true -- set false for a pure Roblox-style screen

local THEME = {
	Background = Color3.fromRGB(45, 45, 45),
	Title = Color3.fromRGB(242, 242, 242),
	Subtitle = Color3.fromRGB(178, 178, 178),
	Counter = Color3.fromRGB(150, 150, 150),
	Cube = Color3.fromRGB(255, 255, 255),
	BarBackground = Color3.fromRGB(64, 64, 64),
	BarFill = Color3.fromRGB(226, 226, 226),
}

-- SourceSans / SourceSansLight are the thin faces the real Roblox loader uses.
-- Gotham looks too heavy and modern here.
local TITLE_FONT = Enum.Font.SourceSans
local BODY_FONT = Enum.Font.SourceSansLight

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

pcall(function()
	ReplicatedFirst:RemoveDefaultLoadingScreen()
end)

local gui = Instance.new("ScreenGui")
gui.Name = "LoadingScreen"
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000
gui.ResetOnSpawn = false
gui.Parent = playerGui

local back = Instance.new("Frame")
back.Name = "Back"
back.Size = UDim2.new(1, 0, 1, 0)
back.BackgroundColor3 = THEME.Background
back.BorderSizePixel = 0
back.Parent = gui

-- Everything centred sits in here so the block can be nudged as one piece.
local centre = Instance.new("Frame")
centre.Name = "Centre"
centre.Size = UDim2.new(1, 0, 0.4, 0)
centre.Position = UDim2.new(0.5, 0, 0.5, 0)
centre.AnchorPoint = Vector2.new(0.5, 0.5)
centre.BackgroundTransparency = 1
centre.Parent = back

local logo = nil
if LOGO_IMAGE ~= "" then
	logo = Instance.new("ImageLabel")
	logo.Name = "Logo"
	logo.Size = UDim2.new(1, 0, LOGO_HEIGHT * 2.5, 0)
	logo.Position = UDim2.new(0.5, 0, 0.16, 0)
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.BackgroundTransparency = 1
	logo.Image = LOGO_IMAGE
	logo.ScaleType = Enum.ScaleType.Fit
	logo.Parent = centre
end

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(0.8, 0, 0.16, 0)
title.Position = UDim2.new(0.5, 0, 0.5, 0)
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.BackgroundTransparency = 1
title.Text = TITLE
title.TextColor3 = THEME.Title
title.TextScaled = true
title.Font = TITLE_FONT
title.Visible = (LOGO_IMAGE == "")
title.Parent = centre

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(0.8, 0, 0.075, 0)
subtitle.Position = UDim2.new(0.5, 0, 0.645, 0)
subtitle.AnchorPoint = Vector2.new(0.5, 0.5)
subtitle.BackgroundTransparency = 1
subtitle.Text = SUBTITLE
subtitle.TextColor3 = THEME.Subtitle
subtitle.TextScaled = true
subtitle.Font = BODY_FONT
subtitle.Parent = centre

-- Progress bar. Thin and grey so it does not fight the Roblox look.
local barBack, fill
if SHOW_BAR then
	barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Size = UDim2.new(0.3, 0, 0.006, 0)
	barBack.Position = UDim2.new(0.5, 0, 0.78, 0)
	barBack.AnchorPoint = Vector2.new(0.5, 0.5)
	barBack.BackgroundColor3 = THEME.BarBackground
	barBack.BorderSizePixel = 0
	barBack.Parent = centre

	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(1, 0)
	bc.Parent = barBack

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = THEME.BarFill
	fill.BorderSizePixel = 0
	fill.Parent = barBack

	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(1, 0)
	fc.Parent = fill
end

local counter = Instance.new("TextLabel")
counter.Name = "Counter"
counter.Size = UDim2.new(0.6, 0, 0.06, 0)
counter.Position = UDim2.new(0.5, 0, 0.88, 0)
counter.AnchorPoint = Vector2.new(0.5, 0.5)
counter.BackgroundTransparency = 1
counter.Text = "Loading assets.. 0 / " .. TOTAL_ASSETS
counter.TextColor3 = THEME.Counter
counter.TextScaled = true
counter.Font = BODY_FONT
counter.Parent = centre

-------------------------------------------------------------------------------
-- Spinning cube
-------------------------------------------------------------------------------
--[[
	The stock loader spins a little cube in the bottom right. A real 3D cube
	needs a ViewportFrame, which does not exist on every old client, so this
	rotates a square instead: same read, works everywhere.
--]]

local cubeHolder = Instance.new("Frame")
cubeHolder.Name = "CubeHolder"
cubeHolder.Size = UDim2.new(0.055, 0, 0.055, 0)
cubeHolder.Position = UDim2.new(0.92, 0, 0.84, 0)
cubeHolder.AnchorPoint = Vector2.new(0.5, 0.5)
cubeHolder.BackgroundTransparency = 1
cubeHolder.Parent = back

-- Keeps it square on any screen shape.
local cubeRatio = Instance.new("UIAspectRatioConstraint")
cubeRatio.AspectRatio = 1
cubeRatio.Parent = cubeHolder

local cube
if CUBE_IMAGE ~= "" then
	cube = Instance.new("ImageLabel")
	cube.Image = CUBE_IMAGE
	cube.BackgroundTransparency = 1
	cube.ScaleType = Enum.ScaleType.Fit
else
	cube = Instance.new("Frame")
	cube.BackgroundColor3 = THEME.Cube
	cube.BorderSizePixel = 0

	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0.16, 0)
	cc.Parent = cube

	-- The little dark notch in the middle, like the Roblox mark.
	local hole = Instance.new("Frame")
	hole.Name = "Hole"
	hole.Size = UDim2.new(0.34, 0, 0.34, 0)
	hole.Position = UDim2.new(0.5, 0, 0.5, 0)
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.BackgroundColor3 = THEME.Background
	hole.BorderSizePixel = 0
	hole.Parent = cube

	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0.12, 0)
	hc.Parent = hole
end

cube.Name = "Cube"
cube.Size = UDim2.new(0.74, 0, 0.74, 0)
cube.Position = UDim2.new(0.5, 0, 0.5, 0)
cube.AnchorPoint = Vector2.new(0.5, 0.5)
cube.Rotation = 20
cube.Parent = cubeHolder

-------------------------------------------------------------------------------
-- Run
-------------------------------------------------------------------------------

local startedAt = tick()
local connection
local finished = false

local function fadeOut()
	local info = TweenInfo.new(FADE_SECONDS)

	TweenService:Create(back, info, {BackgroundTransparency = 1}):Play()
	TweenService:Create(title, info, {TextTransparency = 1}):Play()
	TweenService:Create(subtitle, info, {TextTransparency = 1}):Play()
	TweenService:Create(counter, info, {TextTransparency = 1}):Play()

	if logo then
		TweenService:Create(logo, info, {ImageTransparency = 1}):Play()
	end
	if barBack then
		TweenService:Create(barBack, info, {BackgroundTransparency = 1}):Play()
		TweenService:Create(fill, info, {BackgroundTransparency = 1}):Play()
	end

	if CUBE_IMAGE ~= "" then
		TweenService:Create(cube, info, {ImageTransparency = 1}):Play()
	else
		TweenService:Create(cube, info, {BackgroundTransparency = 1}):Play()
		local hole = cube:FindFirstChild("Hole")
		if hole then
			TweenService:Create(hole, info, {BackgroundTransparency = 1}):Play()
		end
	end

	delay(FADE_SECONDS + 0.1, function()
		gui:Destroy()
	end)
end

connection = RunService.RenderStepped:Connect(function(step)
	-- Spin continuously, independent of the loading progress.
	cube.Rotation = cube.Rotation + (360 / CUBE_SPIN_SECONDS) * (step or 0.016)
	if cube.Rotation >= 360 then
		cube.Rotation = cube.Rotation - 360
	end

	if finished then
		return
	end

	local alpha = (tick() - startedAt) / LOAD_SECONDS
	if alpha > 1 then
		alpha = 1
	end

	-- Ease out so it sprints then settles, like a real loader.
	local eased = 1 - (1 - alpha) * (1 - alpha)

	counter.Text = "Loading assets.. " .. math.floor(eased * TOTAL_ASSETS)
		.. " / " .. TOTAL_ASSETS
	if fill then
		fill.Size = UDim2.new(eased, 0, 1, 0)
	end

	if alpha >= 1 then
		finished = true
		counter.Text = "Loaded " .. TOTAL_ASSETS .. " assets"

		-- Let the cube keep spinning through the fade, then stop everything.
		delay(FADE_SECONDS + 0.2, function()
			if connection then
				connection:Disconnect()
				connection = nil
			end
		end)

		fadeOut()
	end
end)
