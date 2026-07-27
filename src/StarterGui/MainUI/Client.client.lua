--[[
	Booth client script  (StarterGui.MainUI.Client)

	Original booth system by ywinfe and thugshaker.

	This script drives the existing menu (TextBox / ChangeText / UnclaimBooth),
	adds the image-ID controls, and applies a dark theme to every element in
	MainUI at run time, so nothing has to be recoloured by hand in Studio.

	Created at run time inside MainUI.Frame:
	    ImageBox      TextBox     "Enter Image / Decal ID.."
	    ChangeImage   TextButton  "Set Image"
	    Status        TextLabel   feedback line

	Written for Roblox/Luau 2021 and earlier.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local Player = Players.LocalPlayer

local ScreenGui = script.Parent
local Frame = ScreenGui:WaitForChild("Frame")
local ToggleButton = ScreenGui:WaitForChild("TextButton")

local TextBox = Frame:WaitForChild("TextBox")
local ChangeText = Frame:WaitForChild("ChangeText")
local UnclaimBooth = Frame:WaitForChild("UnclaimBooth")
local Title = Frame:FindFirstChild("TextLabel")

local Booths = workspace:WaitForChild("Booths")

-------------------------------------------------------------------------------
-- Dark theme palette
-------------------------------------------------------------------------------

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
	MutedText = Color3.fromRGB(150, 156, 166),
	Placeholder = Color3.fromRGB(110, 116, 126),

	Good = Color3.fromRGB(120, 235, 150),
	Bad = Color3.fromRGB(255, 130, 130),
}

local PANEL_CORNER = UDim.new(0, 14)
local CONTROL_CORNER = UDim.new(0, 8)

local STATUS_TIME = 4 -- seconds a status message stays on screen

-- Row heights (scale of the Frame) so all seven rows fit inside it.
-- Heights + padding + UIPadding must stay under 1.0, because the Frame has
-- ClipsDescendants on and would otherwise cut off the last row.
--   0.835 rows + 6 * 0.016 padding + 0.04 UIPadding = 0.971
local LAYOUT = {
	{Name = "TextLabel", Order = 1, Height = 0.130, Width = 1.00},
	{Name = "TextBox", Order = 2, Height = 0.150, Width = 0.888},
	{Name = "ChangeText", Order = 3, Height = 0.115, Width = 0.515},
	{Name = "ImageBox", Order = 4, Height = 0.150, Width = 0.888},
	{Name = "ChangeImage", Order = 5, Height = 0.115, Width = 0.515},
	{Name = "Status", Order = 6, Height = 0.075, Width = 0.90},
	{Name = "UnclaimBooth", Order = 7, Height = 0.100, Width = 0.44},
}

-------------------------------------------------------------------------------
-- Theme helpers
-------------------------------------------------------------------------------

local function GetOrMakeCorner(Element, Radius)
	local Corner = Element:FindFirstChildOfClass("UICorner")
	if not Corner then
		Corner = Instance.new("UICorner")
		Corner.Parent = Element
	end
	Corner.CornerRadius = Radius
	return Corner
end

-- UIStroke parented to a Frame / TextButton / TextBox draws the border.
local function StyleBorder(Element, Color, Thickness)
	local Stroke = Element:FindFirstChildOfClass("UIStroke")
	if not Stroke then
		Stroke = Instance.new("UIStroke")
		Stroke.Parent = Element
	end
	Stroke.Color = Color
	Stroke.Thickness = Thickness
	Stroke.Transparency = 0
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	return Stroke
end

-- UIStroke parented to a TextLabel outlines the glyphs; keep it dark and faint
-- so light text stays readable without a hard black halo.
local function StyleTextStroke(Label)
	local Stroke = Label:FindFirstChildOfClass("UIStroke")
	if Stroke then
		Stroke.Color = Color3.fromRGB(0, 0, 0)
		Stroke.Thickness = 1
		Stroke.Transparency = 0.55
	end
end

local function StyleCaption(Element, Color)
	Element.TextColor3 = Color
	Element.TextStrokeTransparency = 1

	local Label = Element:FindFirstChild("TextLabel")
	if Label and Label:IsA("TextLabel") then
		Label.BackgroundTransparency = 1
		Label.TextColor3 = Color
		Label.TextStrokeTransparency = 1
		StyleTextStroke(Label)
	end
end

local function StyleButton(Button, Background, StrokeColor, TextColor)
	Button.BackgroundColor3 = Background
	Button.BackgroundTransparency = 0
	Button.BorderSizePixel = 0
	Button.AutoButtonColor = true
	GetOrMakeCorner(Button, CONTROL_CORNER)
	StyleBorder(Button, StrokeColor, 2)
	StyleCaption(Button, TextColor)
end

local function StyleInput(Box)
	Box.BackgroundColor3 = THEME.InputBackground
	Box.BackgroundTransparency = 0
	Box.BorderSizePixel = 0
	Box.TextColor3 = THEME.Text
	Box.TextStrokeTransparency = 1
	Box.PlaceholderColor3 = THEME.Placeholder
	GetOrMakeCorner(Box, CONTROL_CORNER)
	StyleBorder(Box, THEME.InputStroke, 2)
end

-- Faint top-down sheen, like the reference panel.
local function AddSheen(Element)
	if Element:FindFirstChildOfClass("UIGradient") then
		return
	end

	local Gradient = Instance.new("UIGradient")
	Gradient.Rotation = 90
	Gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(205, 205, 210)),
	})
	Gradient.Parent = Element
end

-------------------------------------------------------------------------------
-- Building the new widgets
-------------------------------------------------------------------------------

-- A cloned TextButton keeps its UICorner / UIStroke / UIListLayout / TextLabel.
local function CloneButton(Name, Caption)
	local Existing = Frame:FindFirstChild(Name)
	if Existing then
		return Existing
	end

	local Button = ChangeText:Clone()
	Button.Name = Name
	Button.Visible = true

	local Label = Button:FindFirstChild("TextLabel")
	if Label then
		Label.Text = Caption
	else
		Button.Text = Caption
	end

	Button.Parent = Frame
	return Button
end

local function CloneTextBox(Name, Placeholder)
	local Existing = Frame:FindFirstChild(Name)
	if Existing then
		return Existing
	end

	local Box = TextBox:Clone()
	Box.Name = Name
	Box.Text = ""
	Box.PlaceholderText = Placeholder
	Box.ClearTextOnFocus = false
	Box.Visible = true
	Box.Parent = Frame
	return Box
end

local function BuildStatus()
	local Existing = Frame:FindFirstChild("Status")
	if Existing then
		return Existing
	end

	local Label
	if Title then
		Label = Title:Clone()
	else
		Label = Instance.new("TextLabel")
		Label.TextScaled = true
	end

	Label.Name = "Status"
	Label.Text = ""
	Label.BackgroundTransparency = 1
	Label.Visible = true
	Label.Parent = Frame
	return Label
end

local ImageBox = CloneTextBox("ImageBox", "Enter Image / Decal ID..")
local ChangeImage = CloneButton("ChangeImage", "Set Image")
local Status = BuildStatus()

-------------------------------------------------------------------------------
-- Apply the dark theme
-------------------------------------------------------------------------------

-- Main panel: near-black, rounded, thin grey outline.
Frame.BackgroundColor3 = THEME.PanelBackground
Frame.BackgroundTransparency = 0
Frame.BorderSizePixel = 0
GetOrMakeCorner(Frame, PANEL_CORNER)
StyleBorder(Frame, THEME.PanelStroke, 3)
AddSheen(Frame)

if Title then
	Title.BackgroundTransparency = 1
	Title.TextColor3 = THEME.Text
	Title.TextStrokeTransparency = 1
	StyleTextStroke(Title)
end

StyleInput(TextBox)
StyleInput(ImageBox)

StyleButton(ChangeText, THEME.ButtonBackground, THEME.ButtonStroke, THEME.Text)
StyleButton(ChangeImage, THEME.ButtonBackground, THEME.ButtonStroke, THEME.Text)
StyleButton(UnclaimBooth, THEME.DangerBackground, THEME.DangerStroke, THEME.DangerText)

-- Floating open/close button, same panel styling.
StyleButton(ToggleButton, THEME.PanelBackground, THEME.PanelStroke, THEME.Text)
GetOrMakeCorner(ToggleButton, CONTROL_CORNER)
AddSheen(ToggleButton)

Status.TextColor3 = THEME.MutedText
Status.TextStrokeTransparency = 1
StyleTextStroke(Status)

-- Row sizes and vertical order.
for _, Row in ipairs(LAYOUT) do
	local Element = Frame:FindFirstChild(Row.Name)
	if Element then
		Element.LayoutOrder = Row.Order
		Element.Size = UDim2.new(Row.Width, 0, Row.Height, 0)
	end
end

local ListLayout = Frame:FindFirstChildOfClass("UIListLayout")
if ListLayout then
	ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ListLayout.Padding = UDim.new(0.016, 0)
	ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
end

local Padding = Frame:FindFirstChildOfClass("UIPadding")
if not Padding then
	Padding = Instance.new("UIPadding")
	Padding.Parent = Frame
end
Padding.PaddingTop = UDim.new(0.02, 0)
Padding.PaddingBottom = UDim.new(0.02, 0)

-------------------------------------------------------------------------------
-- Status helper
-------------------------------------------------------------------------------

local StatusToken = 0

local function SetStatus(Message, IsError)
	StatusToken = StatusToken + 1
	local MyToken = StatusToken

	Status.Text = Message or ""
	if IsError == nil then
		Status.TextColor3 = THEME.MutedText
	elseif IsError then
		Status.TextColor3 = THEME.Bad
	else
		Status.TextColor3 = THEME.Good
	end

	if Message and Message ~= "" then
		delay(STATUS_TIME, function()
			if StatusToken == MyToken then
				Status.Text = ""
			end
		end)
	end
end

-------------------------------------------------------------------------------
-- Menu visibility
-------------------------------------------------------------------------------

local function UpdateButtonText()
	local Label = ToggleButton:FindFirstChild("TextLabel")
	local Caption
	if Frame.Visible then
		Caption = "Close Booth Menu"
	else
		Caption = "Open Booth Menu"
	end

	if Label then
		Label.Text = Caption
	else
		ToggleButton.Text = Caption
	end
end

local function SetPromptsEnabled(Enabled)
	for _, Booth in ipairs(Booths:GetChildren()) do
		local Display = Booth:FindFirstChild("Display")
		if Display then
			local Attachment = Display:FindFirstChild("Attachment")
			local Owner = Display:FindFirstChild("BoothOwner")
			if Attachment then
				local Prompt = Attachment:FindFirstChild("ProximityPrompt")
				if Prompt then
					if Enabled then
						-- Only re-enable prompts on booths nobody owns.
						Prompt.Enabled = (Owner == nil) or (Owner.Value == nil)
					else
						Prompt.Enabled = false
					end
				end
			end
		end
	end
end

-------------------------------------------------------------------------------
-- Server messages
-------------------------------------------------------------------------------

RemoteEvent.OnClientEvent:Connect(function(Argument, Argument2)
	if not Argument then
		return
	end

	if Argument == "Start" then
		ToggleButton.Visible = false
		Frame.Visible = false
		UpdateButtonText()

	elseif Argument == "OpenGui" then
		ToggleButton.Visible = true
		Frame.Visible = true
		UpdateButtonText()
		SetStatus("Booth claimed.", false)

	elseif Argument == "BoothUnclaimed" then
		ToggleButton.Visible = false
		Frame.Visible = false
		TextBox.Text = ""
		ImageBox.Text = ""
		SetStatus("")
		UpdateButtonText()

	elseif Argument == "DisablePrompts" then
		SetPromptsEnabled(false)

	elseif Argument == "EnablePrompts" then
		SetPromptsEnabled(true)

	elseif Argument == "ImageChanged" then
		SetStatus("Image updated.", false)

	elseif Argument == "ImageError" then
		SetStatus(Argument2 or "That image ID did not work.", true)

	elseif Argument == "TextChanged" then
		SetStatus("Booth text updated.", false)

	elseif Argument == "TextError" then
		SetStatus(Argument2 or "That text could not be used.", true)
	end
end)

-------------------------------------------------------------------------------
-- Buttons
-------------------------------------------------------------------------------

ToggleButton.MouseButton1Click:Connect(function()
	Frame.Visible = not Frame.Visible
	UpdateButtonText()
end)

ChangeText.MouseButton1Click:Connect(function()
	local Text = TextBox.Text
	if string.match(Text, "^%s*$") then
		SetStatus("Type some booth text first.", true)
		return
	end

	RemoteEvent:FireServer("ChangeText", Text)
	SetStatus("Sending text..")
end)

-- Accepts a bare ID, an rbxassetid:// string, or a link containing "?id=".
local function ReadImageId(Input)
	return string.match(Input, "^%s*(%d+)%s*$")
		or string.match(Input, "^%s*rbxassetid://(%d+)%s*$")
		or string.match(Input, "[?&]id=(%d+)")
end

ChangeImage.MouseButton1Click:Connect(function()
	local Id = ReadImageId(ImageBox.Text)
	if not Id then
		SetStatus("Enter a numeric image / decal ID.", true)
		return
	end

	RemoteEvent:FireServer("ChangeImage", Id)
	SetStatus("Sending image..")
end)

ImageBox.FocusLost:Connect(function(EnterPressed)
	if EnterPressed then
		local Id = ReadImageId(ImageBox.Text)
		if Id then
			RemoteEvent:FireServer("ChangeImage", Id)
			SetStatus("Sending image..")
		else
			SetStatus("Enter a numeric image / decal ID.", true)
		end
	end
end)

TextBox.FocusLost:Connect(function(EnterPressed)
	if EnterPressed and not string.match(TextBox.Text, "^%s*$") then
		RemoteEvent:FireServer("ChangeText", TextBox.Text)
		SetStatus("Sending text..")
	end
end)

UnclaimBooth.MouseButton1Click:Connect(function()
	RemoteEvent:FireServer("UnclaimBooth")
	SetStatus("")
end)

-------------------------------------------------------------------------------
-- Initial state
-------------------------------------------------------------------------------

Frame.Visible = false
ToggleButton.Visible = false
SetStatus("")
UpdateButtonText()

-- Booths this client already owns (rejoin / respawn with ResetOnSpawn on).
local OwnedBooth = Player:FindFirstChild("OwnedBooth")
if OwnedBooth and OwnedBooth.Value then
	ToggleButton.Visible = true
end

-- Original booth system by ywinfe and thugshaker
