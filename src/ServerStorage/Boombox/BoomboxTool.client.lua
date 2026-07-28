--[[
	Boombox  (LocalScript inside the Boombox Tool)

	Granted by the server to owners of the Boombox Gamepass.
	Equip it, type an audio ID, press Play.

	The Sound lives on the Handle and is driven through the tool's
	RemoteEvent so every player hears it, not just the owner.

	Written for Roblox/Luau 2021 and earlier.
--]]

local Players = game:GetService("Players")

local tool = script.Parent
local remote = tool:WaitForChild("BoomboxRemote")
local player = Players.LocalPlayer

local THEME = {
	PanelBackground = Color3.fromRGB(12, 12, 14),
	PanelStroke = Color3.fromRGB(64, 69, 78),
	InputBackground = Color3.fromRGB(24, 25, 29),
	InputStroke = Color3.fromRGB(58, 63, 72),
	ButtonBackground = Color3.fromRGB(30, 32, 37),
	ButtonStroke = Color3.fromRGB(72, 78, 88),
	DangerBackground = Color3.fromRGB(34, 22, 24),
	DangerStroke = Color3.fromRGB(120, 62, 66),
	DangerText = Color3.fromRGB(255, 138, 138),
	Text = Color3.fromRGB(236, 238, 242),
	Placeholder = Color3.fromRGB(110, 116, 126),
}

local gui = Instance.new("ScreenGui")
gui.Name = "BoomboxUI"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0.26, 0, 0.12, 0)
panel.Position = UDim2.new(0.5, 0, 0.86, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = THEME.PanelBackground
panel.BorderSizePixel = 0
panel.Parent = gui

local pc = Instance.new("UICorner")
pc.CornerRadius = UDim.new(0, 14)
pc.Parent = panel

local ps = Instance.new("UIStroke")
ps.Color = THEME.PanelStroke
ps.Thickness = 3
ps.Parent = panel

local box = Instance.new("TextBox")
box.Size = UDim2.new(0.62, 0, 0.5, 0)
box.Position = UDim2.new(0.04, 0, 0.25, 0)
box.BackgroundColor3 = THEME.InputBackground
box.BorderSizePixel = 0
box.Text = ""
box.PlaceholderText = "Audio ID.."
box.PlaceholderColor3 = THEME.Placeholder
box.TextColor3 = THEME.Text
box.TextScaled = true
box.ClearTextOnFocus = false
box.Parent = panel

local bc = Instance.new("UICorner")
bc.CornerRadius = UDim.new(0, 8)
bc.Parent = box

local bs = Instance.new("UIStroke")
bs.Color = THEME.InputStroke
bs.Thickness = 2
bs.Parent = box

local function mkButton(text, x, w, bg, st, tc)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(w, 0, 0.5, 0)
	b.Position = UDim2.new(x, 0, 0.25, 0)
	b.BackgroundColor3 = bg
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = tc
	b.TextScaled = true
	b.Parent = panel
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = st
	s.Thickness = 2
	s.Parent = b
	return b
end

local play = mkButton("Play", 0.68, 0.14, THEME.ButtonBackground, THEME.ButtonStroke, THEME.Text)
local stop = mkButton("Stop", 0.84, 0.13, THEME.DangerBackground, THEME.DangerStroke, THEME.DangerText)

local function readId(s)
	return string.match(s, "^%s*(%d+)%s*$")
		or string.match(s, "^%s*rbxassetid://(%d+)%s*$")
		or string.match(s, "[?&]id=(%d+)")
end

play.MouseButton1Click:Connect(function()
	local id = readId(box.Text)
	if id then
		remote:FireServer("Play", id)
	else
		box.Text = ""
		box.PlaceholderText = "Numbers only.."
	end
end)

box.FocusLost:Connect(function(enter)
	if enter then
		local id = readId(box.Text)
		if id then
			remote:FireServer("Play", id)
		end
	end
end)

stop.MouseButton1Click:Connect(function()
	remote:FireServer("Stop")
end)

tool.Equipped:Connect(function()
	gui.Enabled = true
end)

tool.Unequipped:Connect(function()
	gui.Enabled = false
end)
