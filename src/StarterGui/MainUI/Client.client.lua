--[[
	Booth client script  (StarterGui.MainUI.Client)

	Original booth system by ywinfe and thugshaker.

	Builds the booth menu, the shop, and applies the dark theme at run time by
	cloning the widgets already in MainUI, so nothing has to be styled by hand.

	Created at run time inside MainUI:
	    Frame.ImageBox      TextBox     image / decal ID
	    Frame.ChangeImage   TextButton  "Set Image" / "Unlock Image Uploads"
	    Frame.Status        TextLabel   feedback line
	    ShopButton          TextButton  opens the shop
	    ShopFrame           Frame       one row per gamepass, shows "Owned"

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

	LockedBackground = Color3.fromRGB(42, 34, 16),
	LockedStroke = Color3.fromRGB(150, 118, 44),
	LockedText = Color3.fromRGB(255, 214, 122),

	OwnedBackground = Color3.fromRGB(18, 34, 22),
	OwnedStroke = Color3.fromRGB(62, 122, 74),
	OwnedText = Color3.fromRGB(130, 235, 155),

	Text = Color3.fromRGB(236, 238, 242),
	MutedText = Color3.fromRGB(150, 156, 166),
	Placeholder = Color3.fromRGB(110, 116, 126),

	Good = Color3.fromRGB(120, 235, 150),
	Bad = Color3.fromRGB(255, 130, 130),
}

local PANEL_CORNER = UDim.new(0, 14)
local CONTROL_CORNER = UDim.new(0, 8)
local STATUS_TIME = 4
local PASS_WORD = "Gamepass"

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

local function StyleTextStroke(Label)
	local Stroke = Label:FindFirstChildOfClass("UIStroke")
	if Stroke then
		Stroke.Color = Color3.fromRGB(0, 0, 0)
		Stroke.Thickness = 1
		Stroke.Transparency = 0.55
	end
end

local function SetCaption(Element, Caption)
	local Label = Element:FindFirstChild("TextLabel")
	if Label and Label:IsA("TextLabel") then
		Label.Text = Caption
	else
		Element.Text = Caption
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
-- Booth menu widgets
-------------------------------------------------------------------------------

local function CloneButton(Name, Caption, parent)
	parent = parent or Frame
	local Existing = parent:FindFirstChild(Name)
	if Existing then
		return Existing
	end
	local Button = ChangeText:Clone()
	Button.Name = Name
	Button.Visible = true
	SetCaption(Button, Caption)
	Button.Parent = parent
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

local function CloneLabel(Name, parent)
	local Existing = parent:FindFirstChild(Name)
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
	Label.Name = Name
	Label.Text = ""
	Label.BackgroundTransparency = 1
	Label.Visible = true
	Label.Parent = parent
	return Label
end

local ImageBox = CloneTextBox("ImageBox", "Enter Image / Decal ID..")
local ChangeImage = CloneButton("ChangeImage", "Set Image")
local Status = CloneLabel("Status", Frame)

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
StyleButton(ToggleButton, THEME.PanelBackground, THEME.PanelStroke, THEME.Text)
GetOrMakeCorner(ToggleButton, CONTROL_CORNER)
AddSheen(ToggleButton)

Status.TextColor3 = THEME.MutedText
Status.TextStrokeTransparency = 1
StyleTextStroke(Status)

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
-- Shop
-------------------------------------------------------------------------------

local ShopButton = ScreenGui:FindFirstChild("ShopButton")
if not ShopButton then
	ShopButton = ToggleButton:Clone()
	ShopButton.Name = "ShopButton"
	ShopButton.Parent = ScreenGui
end
ShopButton.Visible = true
ShopButton.Size = ToggleButton.Size
ShopButton.Position = UDim2.new(
	ToggleButton.Position.X.Scale,
	ToggleButton.Position.X.Offset,
	ToggleButton.Position.Y.Scale - 0.085,
	ToggleButton.Position.Y.Offset
)
SetCaption(ShopButton, "Shop")
StyleButton(ShopButton, THEME.PanelBackground, THEME.PanelStroke, THEME.Text)
GetOrMakeCorner(ShopButton, CONTROL_CORNER)
AddSheen(ShopButton)

local ShopFrame = ScreenGui:FindFirstChild("ShopFrame")
if not ShopFrame then
	ShopFrame = Frame:Clone()
	ShopFrame.Name = "ShopFrame"
	-- Start clean: the booth widgets are not wanted in here.
	for _, c in ipairs(ShopFrame:GetChildren()) do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	ShopFrame.Parent = ScreenGui
end

ShopFrame.Visible = false
ShopFrame.Size = UDim2.new(0.42, 0, 0.46, 0)
ShopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
ShopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ShopFrame.BackgroundColor3 = THEME.PanelBackground
ShopFrame.BackgroundTransparency = 0
ShopFrame.BorderSizePixel = 0
GetOrMakeCorner(ShopFrame, PANEL_CORNER)
StyleBorder(ShopFrame, THEME.PanelStroke, 3)
AddSheen(ShopFrame)

local shopRatio = ShopFrame:FindFirstChildOfClass("UIAspectRatioConstraint")
if shopRatio then
	shopRatio:Destroy()
end

local shopList = ShopFrame:FindFirstChildOfClass("UIListLayout")
if not shopList then
	shopList = Instance.new("UIListLayout")
	shopList.Parent = ShopFrame
end
shopList.SortOrder = Enum.SortOrder.LayoutOrder
shopList.Padding = UDim.new(0.02, 0)
shopList.HorizontalAlignment = Enum.HorizontalAlignment.Center
shopList.VerticalAlignment = Enum.VerticalAlignment.Top

local shopPad = ShopFrame:FindFirstChildOfClass("UIPadding")
if not shopPad then
	shopPad = Instance.new("UIPadding")
	shopPad.Parent = ShopFrame
end
shopPad.PaddingTop = UDim.new(0.03, 0)
shopPad.PaddingBottom = UDim.new(0.03, 0)

local ShopTitle = CloneLabel("ShopTitle", ShopFrame)
ShopTitle.Text = "Shop"
ShopTitle.LayoutOrder = 0
ShopTitle.Size = UDim2.new(1, 0, 0.14, 0)
ShopTitle.TextColor3 = THEME.Text
StyleTextStroke(ShopTitle)

local ShopClose = CloneButton("ShopClose", "Close", ShopFrame)
ShopClose.LayoutOrder = 999
ShopClose.Size = UDim2.new(0.34, 0, 0.11, 0)
StyleButton(ShopClose, THEME.ButtonBackground, THEME.ButtonStroke, THEME.Text)

-- Key -> its buy button, so state updates are cheap.
local ShopRows = {}

local function BuildShopRow(entry, order)
	local rowName = "Row_" .. entry.Key
	local row = ShopFrame:FindFirstChild(rowName)
	if not row then
		row = Instance.new("Frame")
		row.Name = rowName
		row.BackgroundTransparency = 1
		row.Parent = ShopFrame
	end
	row.LayoutOrder = order
	row.Size = UDim2.new(0.94, 0, 0.20, 0)

	local rl = row:FindFirstChildOfClass("UIListLayout")
	if not rl then
		rl = Instance.new("UIListLayout")
		rl.Parent = row
	end
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Padding = UDim.new(0.02, 0)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rl.VerticalAlignment = Enum.VerticalAlignment.Top

	local name = CloneLabel("Name", row)
	name.LayoutOrder = 1
	name.Size = UDim2.new(1, 0, 0.36, 0)
	name.Text = entry.Title
	name.TextColor3 = THEME.Text
	StyleTextStroke(name)

	local blurb = CloneLabel("Blurb", row)
	blurb.LayoutOrder = 2
	blurb.Size = UDim2.new(1, 0, 0.26, 0)
	blurb.Text = entry.Blurb or ""
	blurb.TextColor3 = THEME.MutedText
	StyleTextStroke(blurb)

	local buy = row:FindFirstChild("Buy")
	if not buy then
		buy = ChangeText:Clone()
		buy.Name = "Buy"
		buy.Parent = row
		buy.MouseButton1Click:Connect(function()
			RemoteEvent:FireServer("PromptPurchase", entry.Key)
		end)
	end
	buy.LayoutOrder = 3
	buy.Size = UDim2.new(0.55, 0, 0.34, 0)
	buy.Visible = true

	ShopRows[entry.Key] = buy
	return row
end

-------------------------------------------------------------------------------
-- Pass state
-------------------------------------------------------------------------------

local Passes = {}

local function ApplyPassState()
	local ownsUpload = Passes.UPLOAD == true

	if ownsUpload then
		SetCaption(ChangeImage, "Set Image")
		StyleButton(ChangeImage, THEME.ButtonBackground, THEME.ButtonStroke, THEME.Text)
		ImageBox.PlaceholderText = "Enter Image / Decal ID.."
		ImageBox.TextEditable = true
	else
		SetCaption(ChangeImage, "Unlock Image Uploads")
		StyleButton(ChangeImage, THEME.LockedBackground, THEME.LockedStroke, THEME.LockedText)
		ImageBox.PlaceholderText = "Requires " .. PASS_WORD .. ".."
		ImageBox.TextEditable = false
	end

	for key, buy in pairs(ShopRows) do
		if Passes[key] then
			SetCaption(buy, "Owned")
			StyleButton(buy, THEME.OwnedBackground, THEME.OwnedStroke, THEME.OwnedText)
			buy.AutoButtonColor = false
		else
			SetCaption(buy, "Buy")
			StyleButton(buy, THEME.ButtonBackground, THEME.ButtonStroke, THEME.Text)
			buy.AutoButtonColor = true
		end
	end
end

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
	local Caption
	if Frame.Visible then
		Caption = "Close Booth Menu"
	else
		Caption = "Open Booth Menu"
	end
	SetCaption(ToggleButton, Caption)
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

	elseif Argument == "PassState" then
		if type(Argument2) == "table" then
			for i, entry in ipairs(Argument2) do
				Passes[entry.Key] = entry.Owns
				BuildShopRow(entry, i)
			end
			ApplyPassState()
		end

	elseif Argument == "ImageChanged" then
		SetStatus(Argument2 or "Image updated.", false)

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

ShopButton.MouseButton1Click:Connect(function()
	ShopFrame.Visible = not ShopFrame.Visible
	if ShopFrame.Visible then
		RemoteEvent:FireServer("CheckPasses")
	end
end)

ShopClose.MouseButton1Click:Connect(function()
	ShopFrame.Visible = false
end)

ChangeText.MouseButton1Click:Connect(function()
	if string.match(TextBox.Text, "^%s*$") then
		SetStatus("Type some booth text first.", true)
		return
	end
	RemoteEvent:FireServer("ChangeText", TextBox.Text)
	SetStatus("Sending text..")
end)

local function ReadImageId(Input)
	return string.match(Input, "^%s*(%d+)%s*$")
		or string.match(Input, "^%s*rbxassetid://(%d+)%s*$")
		or string.match(Input, "[?&]id=(%d+)")
end

local function SubmitImage()
	if not Passes.UPLOAD then
		ShopFrame.Visible = true
		RemoteEvent:FireServer("CheckPasses")
		SetStatus("Image uploads need the " .. PASS_WORD .. ".", true)
		return
	end

	local Id = ReadImageId(ImageBox.Text)
	if not Id then
		SetStatus("Enter a numeric image / decal ID.", true)
		return
	end

	RemoteEvent:FireServer("ChangeImage", Id)
	SetStatus("Sending image..")
end

ChangeImage.MouseButton1Click:Connect(SubmitImage)

ImageBox.FocusLost:Connect(function(EnterPressed)
	if EnterPressed then
		SubmitImage()
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
ShopFrame.Visible = false
ToggleButton.Visible = false
SetStatus("")
UpdateButtonText()
ApplyPassState()

RemoteEvent:FireServer("CheckPasses")

local OwnedBooth = Player:FindFirstChild("OwnedBooth")
if OwnedBooth and OwnedBooth.Value then
	ToggleButton.Visible = true
end

-- Original booth system by ywinfe and thugshaker
