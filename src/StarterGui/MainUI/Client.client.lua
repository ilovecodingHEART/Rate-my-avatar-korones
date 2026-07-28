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

	-- Shop: cartoon layout, dark palette. The heavy outline is what gives the
	-- reference its look, so it stays near-black rather than grey.
	ShopOutline = Color3.fromRGB(0, 0, 0),
	CardBackground = Color3.fromRGB(22, 23, 27),
	TabActive = Color3.fromRGB(34, 36, 42),
	TabIdle = Color3.fromRGB(20, 21, 25),
	AdminBackground = Color3.fromRGB(46, 30, 58),
	AdminText = Color3.fromRGB(214, 170, 255),

	BuyBackground = Color3.fromRGB(28, 92, 44),
	BuyStroke = Color3.fromRGB(74, 190, 104),
	BuyText = Color3.fromRGB(190, 255, 205),

	Text = Color3.fromRGB(236, 238, 242),
	MutedText = Color3.fromRGB(150, 156, 166),
	Placeholder = Color3.fromRGB(110, 116, 126),

	Good = Color3.fromRGB(120, 235, 150),
	Bad = Color3.fromRGB(255, 130, 130),
}

local PANEL_CORNER = UDim.new(0, 14)
local CONTROL_CORNER = UDim.new(0, 8)
local SHOP_CORNER = UDim.new(0, 16)
local STATUS_TIME = 4
local PASS_WORD = "Gamepass"

-- GothamBold is the closest built-in to the chunky reference lettering and
-- exists on old clients; FontFace/custom fonts do not.
local TITLE_FONT = Enum.Font.GothamBold
local BODY_FONT = Enum.Font.Gotham

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
StyleButton(ShopButton, THEME.PanelBackground, THEME.ShopOutline, THEME.Text)
GetOrMakeCorner(ShopButton, SHOP_CORNER)
StyleBorder(ShopButton, THEME.ShopOutline, 4)
AddSheen(ShopButton)

-- Match the heavier shop outline on the booth toggle so the two HUD buttons
-- read as a pair.
StyleBorder(ToggleButton, THEME.ShopOutline, 4)
GetOrMakeCorner(ToggleButton, SHOP_CORNER)

-- Root window --------------------------------------------------------------

local ShopFrame = ScreenGui:FindFirstChild("ShopFrame")
if not ShopFrame then
	ShopFrame = Instance.new("Frame")
	ShopFrame.Name = "ShopFrame"
	ShopFrame.Parent = ScreenGui
end
ShopFrame.Visible = false
ShopFrame.Size = UDim2.new(0.56, 0, 0.50, 0)
ShopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
ShopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ShopFrame.BackgroundColor3 = THEME.PanelBackground
ShopFrame.BorderSizePixel = 0
ShopFrame.ClipsDescendants = false
GetOrMakeCorner(ShopFrame, SHOP_CORNER)
StyleBorder(ShopFrame, THEME.ShopOutline, 4)
AddSheen(ShopFrame)

for _, junk in ipairs(ShopFrame:GetChildren()) do
	if junk:IsA("UIAspectRatioConstraint") or junk:IsA("UIListLayout") then
		junk:Destroy()
	end
end

-- Big title sitting above the window, like the reference.
local ShopTitle = ShopFrame:FindFirstChild("ShopTitle")
if not ShopTitle then
	ShopTitle = Instance.new("TextLabel")
	ShopTitle.Name = "ShopTitle"
	ShopTitle.Parent = ShopFrame
end
ShopTitle.Size = UDim2.new(1, 0, 0.15, 0)
ShopTitle.Position = UDim2.new(0.5, 0, -0.015, 0)
ShopTitle.AnchorPoint = Vector2.new(0.5, 1)
ShopTitle.BackgroundTransparency = 1
ShopTitle.Text = "Shop!"
ShopTitle.TextScaled = true
ShopTitle.Font = TITLE_FONT
ShopTitle.TextColor3 = THEME.Text
ShopTitle.TextStrokeTransparency = 1
do
	local st = ShopTitle:FindFirstChildOfClass("UIStroke")
	if not st then
		st = Instance.new("UIStroke")
		st.Parent = ShopTitle
	end
	st.Color = THEME.ShopOutline
	st.Thickness = 4
	st.Transparency = 0
end

-- Close button, top right corner of the window.
local ShopClose = ShopFrame:FindFirstChild("ShopClose")
if not ShopClose then
	ShopClose = Instance.new("TextButton")
	ShopClose.Name = "ShopClose"
	ShopClose.Parent = ShopFrame
end
ShopClose.Size = UDim2.new(0.062, 0, 0.092, 0)
ShopClose.Position = UDim2.new(1, 0, 0, 0)
ShopClose.AnchorPoint = Vector2.new(0.5, 0.5)
ShopClose.Text = "X"
ShopClose.TextScaled = true
ShopClose.Font = TITLE_FONT
ShopClose.BackgroundColor3 = THEME.DangerBackground
ShopClose.TextColor3 = THEME.DangerText
ShopClose.BorderSizePixel = 0
ShopClose.ZIndex = 5
GetOrMakeCorner(ShopClose, UDim.new(1, 0))
StyleBorder(ShopClose, THEME.ShopOutline, 3)

-- Sidebar --------------------------------------------------------------------

local Sidebar = ShopFrame:FindFirstChild("Sidebar")
if not Sidebar then
	Sidebar = Instance.new("Frame")
	Sidebar.Name = "Sidebar"
	Sidebar.Parent = ShopFrame
end
Sidebar.Size = UDim2.new(0.235, 0, 0.9, 0)
Sidebar.Position = UDim2.new(0.028, 0, 0.05, 0)
Sidebar.BackgroundTransparency = 1

local sideList = Sidebar:FindFirstChildOfClass("UIListLayout")
if not sideList then
	sideList = Instance.new("UIListLayout")
	sideList.Parent = Sidebar
end
sideList.SortOrder = Enum.SortOrder.LayoutOrder
sideList.Padding = UDim.new(0.035, 0)
sideList.HorizontalAlignment = Enum.HorizontalAlignment.Center
sideList.VerticalAlignment = Enum.VerticalAlignment.Top

-- Item grid ------------------------------------------------------------------

local Grid = ShopFrame:FindFirstChild("Grid")
if not Grid then
	Grid = Instance.new("ScrollingFrame")
	Grid.Name = "Grid"
	Grid.Parent = ShopFrame
end
Grid.Size = UDim2.new(0.69, 0, 0.9, 0)
Grid.Position = UDim2.new(0.285, 0, 0.05, 0)
Grid.BackgroundTransparency = 1
Grid.BorderSizePixel = 0
Grid.ScrollBarThickness = 8
Grid.ScrollBarImageColor3 = THEME.PanelStroke
Grid.CanvasSize = UDim2.new(0, 0, 0, 0)
Grid.AutomaticCanvasSize = Enum.AutomaticSize.Y

local gridLayout = Grid:FindFirstChildOfClass("UIGridLayout")
if not gridLayout then
	gridLayout = Instance.new("UIGridLayout")
	gridLayout.Parent = Grid
end
gridLayout.CellSize = UDim2.new(0.47, 0, 0, 0)
gridLayout.CellPadding = UDim2.new(0.04, 0, 0.04, 0)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local gridRatio = gridLayout:FindFirstChildOfClass("UIAspectRatioConstraint")
if not gridRatio then
	gridRatio = Instance.new("UIAspectRatioConstraint")
	gridRatio.Parent = gridLayout
end
gridRatio.AspectRatio = 1.30

local Empty = Grid:FindFirstChild("EmptyNote")
if not Empty then
	Empty = Instance.new("TextLabel")
	Empty.Name = "EmptyNote"
	Empty.Parent = ShopFrame
end
Empty.Size = UDim2.new(0.66, 0, 0.2, 0)
Empty.Position = UDim2.new(0.63, 0, 0.5, 0)
Empty.AnchorPoint = Vector2.new(0.5, 0.5)
Empty.BackgroundTransparency = 1
Empty.Text = "Nothing here yet."
Empty.TextScaled = true
Empty.Font = BODY_FONT
Empty.TextColor3 = THEME.MutedText
Empty.Visible = false

-- Building -------------------------------------------------------------------

local ShopRows = {}
local ShopCards = {}
local TabButtons = {}
local CurrentTab = nil
local ShopEntries = {}

local function RefreshGrid()
	local shown = 0
	for key, card in pairs(ShopCards) do
		local entry = ShopEntries[key]
		local vis = (entry ~= nil) and (entry.Category == CurrentTab)
		card.Visible = vis
		if vis then
			shown = shown + 1
		end
	end
	Empty.Visible = (shown == 0)
	Grid.Visible = (shown > 0)
end

local function StyleTab(button, active)
	if active then
		button.BackgroundColor3 = THEME.TabActive
		StyleBorder(button, THEME.ShopOutline, 4)
		button.TextColor3 = THEME.Text
	else
		button.BackgroundColor3 = THEME.TabIdle
		StyleBorder(button, THEME.ShopOutline, 3)
		button.TextColor3 = THEME.MutedText
	end
end

local function SelectTab(name)
	CurrentTab = name
	for tabName, button in pairs(TabButtons) do
		StyleTab(button, tabName == name)
	end
	RefreshGrid()
end

local function BuildTab(name, order)
	local button = TabButtons[name]
	if not button then
		button = Instance.new("TextButton")
		button.Name = "Tab_" .. name
		button.Parent = Sidebar
		button.MouseButton1Click:Connect(function()
			SelectTab(name)
		end)
		TabButtons[name] = button
	end
	button.LayoutOrder = order
	button.Size = UDim2.new(0.9, 0, 0.235, 0)
	button.Text = name
	button.TextScaled = true
	button.Font = TITLE_FONT
	button.BorderSizePixel = 0
	button.AutoButtonColor = true
	GetOrMakeCorner(button, SHOP_CORNER)
	StyleTab(button, name == CurrentTab)
	return button
end

-- One item card: icon, name, price, buy button.
local function BuildShopRow(entry, order)
	local card = ShopCards[entry.Key]
	if not card then
		card = Instance.new("Frame")
		card.Name = "Card_" .. entry.Key
		card.Parent = Grid
		ShopCards[entry.Key] = card
	end
	card.LayoutOrder = order
	card.BackgroundColor3 = THEME.CardBackground
	card.BorderSizePixel = 0
	GetOrMakeCorner(card, SHOP_CORNER)
	StyleBorder(card, THEME.ShopOutline, 4)

	local title = card:FindFirstChild("Title")
	if not title then
		title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Parent = card
	end
	title.Size = UDim2.new(0.94, 0, 0.19, 0)
	title.Position = UDim2.new(0.5, 0, 0.03, 0)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.BackgroundTransparency = 1
	title.Text = entry.Title
	title.TextScaled = true
	title.Font = TITLE_FONT
	title.TextColor3 = THEME.Text
	title.TextStrokeTransparency = 1

	-- Icon. Blank until an asset id is filled in on the server.
	local icon = card:FindFirstChild("Icon")
	if not icon then
		icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Parent = card
	end
	icon.Size = UDim2.new(0.34, 0, 0.44, 0)
	icon.Position = UDim2.new(0.06, 0, 0.26, 0)
	icon.BackgroundColor3 = THEME.InputBackground
	icon.BorderSizePixel = 0
	icon.ScaleType = Enum.ScaleType.Fit
	if entry.Icon and entry.Icon ~= "" then
		icon.Image = entry.Icon
		icon.BackgroundTransparency = 1
	else
		icon.Image = ""
		icon.BackgroundTransparency = 0
	end
	GetOrMakeCorner(icon, CONTROL_CORNER)

	local price = card:FindFirstChild("Price")
	if not price then
		price = Instance.new("TextLabel")
		price.Name = "Price"
		price.Parent = card
	end
	price.Size = UDim2.new(0.5, 0, 0.18, 0)
	price.Position = UDim2.new(0.44, 0, 0.26, 0)
	price.BackgroundTransparency = 1
	price.Text = entry.Price or "Gamepass"
	price.TextScaled = true
	price.Font = TITLE_FONT
	price.TextColor3 = THEME.Text
	price.TextXAlignment = Enum.TextXAlignment.Left

	local blurb = card:FindFirstChild("Blurb")
	if not blurb then
		blurb = Instance.new("TextLabel")
		blurb.Name = "Blurb"
		blurb.Parent = card
	end
	blurb.Size = UDim2.new(0.5, 0, 0.24, 0)
	blurb.Position = UDim2.new(0.44, 0, 0.46, 0)
	blurb.BackgroundTransparency = 1
	blurb.Text = entry.Blurb or ""
	blurb.TextScaled = false
	blurb.TextWrapped = true
	blurb.TextSize = 13
	blurb.Font = BODY_FONT
	blurb.TextColor3 = THEME.MutedText
	blurb.TextXAlignment = Enum.TextXAlignment.Left

	local buy = card:FindFirstChild("Buy")
	if not buy then
		buy = Instance.new("TextButton")
		buy.Name = "Buy"
		buy.Parent = card
		buy.MouseButton1Click:Connect(function()
			RemoteEvent:FireServer("PromptPurchase", entry.Key)
		end)
	end
	buy.Size = UDim2.new(0.86, 0, 0.22, 0)
	buy.Position = UDim2.new(0.5, 0, 0.96, 0)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.TextScaled = true
	buy.Font = TITLE_FONT
	buy.BorderSizePixel = 0
	GetOrMakeCorner(buy, CONTROL_CORNER)

	ShopRows[entry.Key] = buy
	ShopEntries[entry.Key] = entry
	return card
end

-------------------------------------------------------------------------------
-- Admin panel
-------------------------------------------------------------------------------
--[[
	Same look as the shop: heavy black outline, dark cards, sidebar-free.
	Left column lists every pass, right column edits the selected one.

	Hidden entirely unless the server says this player is an admin, and every
	action is re-checked server side anyway.
--]]

local IsAdminClient = false

local AdminButton = ScreenGui:FindFirstChild("AdminButton")
if not AdminButton then
	AdminButton = Instance.new("TextButton")
	AdminButton.Name = "AdminButton"
	AdminButton.Parent = ScreenGui
end
AdminButton.Size = ToggleButton.Size
AdminButton.Position = UDim2.new(
	ToggleButton.Position.X.Scale,
	ToggleButton.Position.X.Offset,
	ToggleButton.Position.Y.Scale - 0.17,
	ToggleButton.Position.Y.Offset
)
AdminButton.Text = "Admin"
AdminButton.TextScaled = true
AdminButton.Font = TITLE_FONT
AdminButton.BackgroundColor3 = THEME.AdminBackground
AdminButton.TextColor3 = THEME.AdminText
AdminButton.BorderSizePixel = 0
AdminButton.Visible = false
GetOrMakeCorner(AdminButton, SHOP_CORNER)
StyleBorder(AdminButton, THEME.ShopOutline, 4)
AddSheen(AdminButton)

local AdminFrame = ScreenGui:FindFirstChild("AdminFrame")
if not AdminFrame then
	AdminFrame = Instance.new("Frame")
	AdminFrame.Name = "AdminFrame"
	AdminFrame.Parent = ScreenGui
end
AdminFrame.Visible = false
AdminFrame.Size = UDim2.new(0.62, 0, 0.60, 0)
AdminFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
AdminFrame.AnchorPoint = Vector2.new(0.5, 0.5)
AdminFrame.BackgroundColor3 = THEME.PanelBackground
AdminFrame.BorderSizePixel = 0
GetOrMakeCorner(AdminFrame, SHOP_CORNER)
StyleBorder(AdminFrame, THEME.ShopOutline, 4)
AddSheen(AdminFrame)

local AdminTitle = AdminFrame:FindFirstChild("AdminTitle")
if not AdminTitle then
	AdminTitle = Instance.new("TextLabel")
	AdminTitle.Name = "AdminTitle"
	AdminTitle.Parent = AdminFrame
end
AdminTitle.Size = UDim2.new(1, 0, 0.13, 0)
AdminTitle.Position = UDim2.new(0.5, 0, -0.015, 0)
AdminTitle.AnchorPoint = Vector2.new(0.5, 1)
AdminTitle.BackgroundTransparency = 1
AdminTitle.Text = "Admin"
AdminTitle.TextScaled = true
AdminTitle.Font = TITLE_FONT
AdminTitle.TextColor3 = THEME.Text
do
	local st = AdminTitle:FindFirstChildOfClass("UIStroke")
	if not st then
		st = Instance.new("UIStroke")
		st.Parent = AdminTitle
	end
	st.Color = THEME.ShopOutline
	st.Thickness = 4
end

local AdminClose = AdminFrame:FindFirstChild("AdminClose")
if not AdminClose then
	AdminClose = Instance.new("TextButton")
	AdminClose.Name = "AdminClose"
	AdminClose.Parent = AdminFrame
end
AdminClose.Size = UDim2.new(0.056, 0, 0.093, 0)
AdminClose.Position = UDim2.new(1, 0, 0, 0)
AdminClose.AnchorPoint = Vector2.new(0.5, 0.5)
AdminClose.Text = "X"
AdminClose.TextScaled = true
AdminClose.Font = TITLE_FONT
AdminClose.BackgroundColor3 = THEME.DangerBackground
AdminClose.TextColor3 = THEME.DangerText
AdminClose.BorderSizePixel = 0
AdminClose.ZIndex = 5
GetOrMakeCorner(AdminClose, UDim.new(1, 0))
StyleBorder(AdminClose, THEME.ShopOutline, 3)

-- Left: the list of passes.
local AdminList = AdminFrame:FindFirstChild("AdminList")
if not AdminList then
	AdminList = Instance.new("ScrollingFrame")
	AdminList.Name = "AdminList"
	AdminList.Parent = AdminFrame
end
AdminList.Size = UDim2.new(0.32, 0, 0.78, 0)
AdminList.Position = UDim2.new(0.03, 0, 0.05, 0)
AdminList.BackgroundColor3 = THEME.CardBackground
AdminList.BorderSizePixel = 0
AdminList.ScrollBarThickness = 6
AdminList.ScrollBarImageColor3 = THEME.PanelStroke
AdminList.CanvasSize = UDim2.new(0, 0, 0, 0)
AdminList.AutomaticCanvasSize = Enum.AutomaticSize.Y
GetOrMakeCorner(AdminList, CONTROL_CORNER)
StyleBorder(AdminList, THEME.ShopOutline, 3)

local listLayout = AdminList:FindFirstChildOfClass("UIListLayout")
if not listLayout then
	listLayout = Instance.new("UIListLayout")
	listLayout.Parent = AdminList
end
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 4)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

local listPad = AdminList:FindFirstChildOfClass("UIPadding")
if not listPad then
	listPad = Instance.new("UIPadding")
	listPad.Parent = AdminList
end
listPad.PaddingTop = UDim.new(0, 6)

local NewButton = AdminFrame:FindFirstChild("NewPass")
if not NewButton then
	NewButton = Instance.new("TextButton")
	NewButton.Name = "NewPass"
	NewButton.Parent = AdminFrame
end
NewButton.Size = UDim2.new(0.32, 0, 0.10, 0)
NewButton.Position = UDim2.new(0.03, 0, 0.85, 0)
NewButton.Text = "+ New Gamepass"
NewButton.TextScaled = true
NewButton.Font = TITLE_FONT
NewButton.BackgroundColor3 = THEME.BuyBackground
NewButton.TextColor3 = THEME.BuyText
NewButton.BorderSizePixel = 0
GetOrMakeCorner(NewButton, CONTROL_CORNER)
StyleBorder(NewButton, THEME.ShopOutline, 3)

-- Right: the editor.
local Editor = AdminFrame:FindFirstChild("Editor")
if not Editor then
	Editor = Instance.new("Frame")
	Editor.Name = "Editor"
	Editor.Parent = AdminFrame
end
Editor.Size = UDim2.new(0.60, 0, 0.90, 0)
Editor.Position = UDim2.new(0.37, 0, 0.05, 0)
Editor.BackgroundTransparency = 1

local AdminFields = {}
local AdminSelected = nil
local AdminEntries = {}

-- One labelled text box in the editor column.
local function MakeField(name, label, order, placeholder)
	local holder = Editor:FindFirstChild("F_" .. name)
	if not holder then
		holder = Instance.new("Frame")
		holder.Name = "F_" .. name
		holder.BackgroundTransparency = 1
		holder.Parent = Editor
	end
	holder.LayoutOrder = order
	holder.Size = UDim2.new(1, 0, 0.115, 0)

	local cap = holder:FindFirstChild("Cap")
	if not cap then
		cap = Instance.new("TextLabel")
		cap.Name = "Cap"
		cap.Parent = holder
	end
	cap.Size = UDim2.new(0.26, 0, 1, 0)
	cap.BackgroundTransparency = 1
	cap.Text = label
	cap.TextScaled = true
	cap.Font = BODY_FONT
	cap.TextColor3 = THEME.MutedText
	cap.TextXAlignment = Enum.TextXAlignment.Left

	local box = holder:FindFirstChild("Box")
	if not box then
		box = Instance.new("TextBox")
		box.Name = "Box"
		box.Parent = holder
	end
	box.Size = UDim2.new(0.72, 0, 0.82, 0)
	box.Position = UDim2.new(0.28, 0, 0.09, 0)
	box.BackgroundColor3 = THEME.InputBackground
	box.BorderSizePixel = 0
	box.Text = ""
	box.PlaceholderText = placeholder or ""
	box.PlaceholderColor3 = THEME.Placeholder
	box.TextColor3 = THEME.Text
	box.TextScaled = true
	box.ClearTextOnFocus = false
	GetOrMakeCorner(box, CONTROL_CORNER)
	StyleBorder(box, THEME.InputStroke, 2)

	AdminFields[name] = box
	return box
end

local editorLayout = Editor:FindFirstChildOfClass("UIListLayout")
if not editorLayout then
	editorLayout = Instance.new("UIListLayout")
	editorLayout.Parent = Editor
end
editorLayout.SortOrder = Enum.SortOrder.LayoutOrder
editorLayout.Padding = UDim.new(0, 6)

MakeField("Key", "Key", 1, "SPEED_PASS")
MakeField("Title", "Name", 2, "Speed Boost")
MakeField("Id", "Asset ID", 3, "356360")
MakeField("Price", "Price", 4, "Gamepass")
MakeField("Icon", "Icon ID", 5, "rbxassetid:// or blank")
MakeField("Blurb", "Blurb", 6, "What it does")
MakeField("Category", "Category", 7, "Passes")

local AdminStatus = Editor:FindFirstChild("AdminStatus")
if not AdminStatus then
	AdminStatus = Instance.new("TextLabel")
	AdminStatus.Name = "AdminStatus"
	AdminStatus.Parent = Editor
end
AdminStatus.LayoutOrder = 8
AdminStatus.Size = UDim2.new(1, 0, 0.08, 0)
AdminStatus.BackgroundTransparency = 1
AdminStatus.Text = ""
AdminStatus.TextScaled = true
AdminStatus.Font = BODY_FONT
AdminStatus.TextColor3 = THEME.MutedText

local Buttons = Editor:FindFirstChild("Buttons")
if not Buttons then
	Buttons = Instance.new("Frame")
	Buttons.Name = "Buttons"
	Buttons.BackgroundTransparency = 1
	Buttons.Parent = Editor
end
Buttons.LayoutOrder = 9
Buttons.Size = UDim2.new(1, 0, 0.12, 0)

local SaveButton = Buttons:FindFirstChild("Save")
if not SaveButton then
	SaveButton = Instance.new("TextButton")
	SaveButton.Name = "Save"
	SaveButton.Parent = Buttons
end
SaveButton.Size = UDim2.new(0.48, 0, 1, 0)
SaveButton.Text = "Save"
SaveButton.TextScaled = true
SaveButton.Font = TITLE_FONT
SaveButton.BackgroundColor3 = THEME.BuyBackground
SaveButton.TextColor3 = THEME.BuyText
SaveButton.BorderSizePixel = 0
GetOrMakeCorner(SaveButton, CONTROL_CORNER)
StyleBorder(SaveButton, THEME.ShopOutline, 3)

local DeleteButton = Buttons:FindFirstChild("Delete")
if not DeleteButton then
	DeleteButton = Instance.new("TextButton")
	DeleteButton.Name = "Delete"
	DeleteButton.Parent = Buttons
end
DeleteButton.Size = UDim2.new(0.48, 0, 1, 0)
DeleteButton.Position = UDim2.new(0.52, 0, 0, 0)
DeleteButton.Text = "Delete"
DeleteButton.TextScaled = true
DeleteButton.Font = TITLE_FONT
DeleteButton.BackgroundColor3 = THEME.DangerBackground
DeleteButton.TextColor3 = THEME.DangerText
DeleteButton.BorderSizePixel = 0
GetOrMakeCorner(DeleteButton, CONTROL_CORNER)
StyleBorder(DeleteButton, THEME.ShopOutline, 3)

local function SetAdminStatus(msg, bad)
	AdminStatus.Text = msg or ""
	if bad then
		AdminStatus.TextColor3 = THEME.Bad
	else
		AdminStatus.TextColor3 = THEME.Good
	end
end

local function LoadIntoEditor(entry)
	AdminSelected = entry and entry.Key or nil

	if not entry then
		AdminFields.Key.Text = ""
		AdminFields.Title.Text = ""
		AdminFields.Id.Text = ""
		AdminFields.Price.Text = "Gamepass"
		AdminFields.Icon.Text = ""
		AdminFields.Blurb.Text = ""
		AdminFields.Category.Text = "Passes"
		AdminFields.Key.TextEditable = true
		AdminFields.Id.TextEditable = true
		DeleteButton.Visible = false
		SetAdminStatus("New gamepass", false)
		return
	end

	AdminFields.Key.Text = entry.Key
	AdminFields.Title.Text = entry.Title or ""
	AdminFields.Id.Text = tostring(entry.Id or "")
	AdminFields.Price.Text = entry.Price or ""
	AdminFields.Icon.Text = entry.Icon or ""
	AdminFields.Blurb.Text = entry.Blurb or ""
	AdminFields.Category.Text = entry.Category or "Passes"

	-- Built ins are wired into the booth logic, so their key and id are locked.
	AdminFields.Key.TextEditable = not entry.Builtin
	AdminFields.Id.TextEditable = not entry.Builtin
	DeleteButton.Visible = not entry.Builtin

	if entry.Builtin then
		SetAdminStatus("Built in: key and ID locked", false)
	else
		SetAdminStatus("", false)
	end
end

local AdminRows = {}

local function BuildAdminRow(entry, order)
	local row = AdminRows[entry.Key]
	if not row then
		row = Instance.new("TextButton")
		row.Name = "L_" .. entry.Key
		row.Parent = AdminList
		row.MouseButton1Click:Connect(function()
			LoadIntoEditor(AdminEntries[entry.Key])
		end)
		AdminRows[entry.Key] = row
	end
	row.LayoutOrder = order
	row.Size = UDim2.new(0.92, 0, 0, 30)
	row.Text = entry.Title or entry.Key
	row.TextScaled = true
	row.Font = BODY_FONT
	row.BackgroundColor3 = THEME.TabIdle
	row.TextColor3 = THEME.Text
	row.BorderSizePixel = 0
	GetOrMakeCorner(row, CONTROL_CORNER)
	StyleBorder(row, THEME.ShopOutline, 2)
	return row
end

NewButton.MouseButton1Click:Connect(function()
	LoadIntoEditor(nil)
end)

SaveButton.MouseButton1Click:Connect(function()
	RemoteEvent:FireServer("AdminSavePass", {
		Key = AdminFields.Key.Text,
		Title = AdminFields.Title.Text,
		Id = tonumber(AdminFields.Id.Text),
		Price = AdminFields.Price.Text,
		Icon = AdminFields.Icon.Text,
		Blurb = AdminFields.Blurb.Text,
		Category = AdminFields.Category.Text,
	})
	SetAdminStatus("Saving..", false)
end)

DeleteButton.MouseButton1Click:Connect(function()
	if AdminSelected then
		RemoteEvent:FireServer("AdminDeletePass", AdminSelected)
	end
end)

AdminClose.MouseButton1Click:Connect(function()
	AdminFrame.Visible = false
end)

AdminButton.MouseButton1Click:Connect(function()
	AdminFrame.Visible = not AdminFrame.Visible
	if AdminFrame.Visible then
		RemoteEvent:FireServer("AdminOpen")
	end
end)

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
			buy.Text = "Owned"
			buy.BackgroundColor3 = THEME.OwnedBackground
			buy.TextColor3 = THEME.OwnedText
			StyleBorder(buy, THEME.ShopOutline, 3)
			buy.AutoButtonColor = false
		else
			buy.Text = "Buy"
			buy.BackgroundColor3 = THEME.BuyBackground
			buy.TextColor3 = THEME.BuyText
			StyleBorder(buy, THEME.ShopOutline, 3)
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

RemoteEvent.OnClientEvent:Connect(function(Argument, Argument2, Argument3)
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

			-- Argument3 is the category list. Fall back to whatever the items
			-- themselves declare if an older server does not send it.
			local cats = Argument3
			if type(cats) ~= "table" then
				cats = {}
				local seen = {}
				for _, entry in ipairs(Argument2) do
					local c = entry.Category or "Passes"
					if not seen[c] then
						seen[c] = true
						cats[#cats + 1] = c
					end
				end
			end

			for i, name in ipairs(cats) do
				BuildTab(name, i)
			end
			if not CurrentTab and cats[1] then
				SelectTab(cats[1])
			else
				SelectTab(CurrentTab or cats[1])
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

	elseif Argument == "AdminAccess" then
		IsAdminClient = (Argument2 == true)
		AdminButton.Visible = IsAdminClient
		if not IsAdminClient then
			AdminFrame.Visible = false
		end

	elseif Argument == "AdminState" then
		if type(Argument2) == "table" then
			local seen = {}
			for i, entry in ipairs(Argument2) do
				AdminEntries[entry.Key] = entry
				BuildAdminRow(entry, i)
				seen[entry.Key] = true
			end
			-- Drop rows for passes that no longer exist.
			for key, row in pairs(AdminRows) do
				if not seen[key] then
					row:Destroy()
					AdminRows[key] = nil
					AdminEntries[key] = nil
					if AdminSelected == key then
						LoadIntoEditor(nil)
					end
				end
			end
			if AdminSelected and AdminEntries[AdminSelected] then
				LoadIntoEditor(AdminEntries[AdminSelected])
			end
		end

	elseif Argument == "AdminOk" then
		SetAdminStatus(Argument2 or "Done.", false)

	elseif Argument == "AdminError" then
		SetAdminStatus(Argument2 or "That did not work.", true)
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
-- Boombox
-------------------------------------------------------------------------------
--[[
	The Boombox tool is generated by the server and contains no scripts of its
	own (Script.Source cannot be written at run time). So the panel lives here
	and appears whenever the tool is equipped.
--]]

local BoomboxRemote = ReplicatedStorage:WaitForChild("BoomboxRemote")

local BoomPanel = ScreenGui:FindFirstChild("BoomboxPanel")
if not BoomPanel then
	BoomPanel = Instance.new("Frame")
	BoomPanel.Name = "BoomboxPanel"
	BoomPanel.Parent = ScreenGui
end
BoomPanel.Size = UDim2.new(0.26, 0, 0.09, 0)
BoomPanel.Position = UDim2.new(0.5, 0, 0.9, 0)
BoomPanel.AnchorPoint = Vector2.new(0.5, 0.5)
BoomPanel.BackgroundColor3 = THEME.PanelBackground
BoomPanel.BorderSizePixel = 0
BoomPanel.Visible = false
GetOrMakeCorner(BoomPanel, PANEL_CORNER)
StyleBorder(BoomPanel, THEME.PanelStroke, 3)
AddSheen(BoomPanel)

local BoomBox = BoomPanel:FindFirstChild("AudioBox")
if not BoomBox then
	BoomBox = TextBox:Clone()
	BoomBox.Name = "AudioBox"
	BoomBox.Parent = BoomPanel
end
BoomBox.Size = UDim2.new(0.58, 0, 0.56, 0)
BoomBox.Position = UDim2.new(0.04, 0, 0.22, 0)
BoomBox.Text = ""
BoomBox.PlaceholderText = "Audio ID.."
BoomBox.ClearTextOnFocus = false
BoomBox.Visible = true
StyleInput(BoomBox)

local BoomPlay = BoomPanel:FindFirstChild("Play")
if not BoomPlay then
	BoomPlay = ChangeText:Clone()
	BoomPlay.Name = "Play"
	BoomPlay.Parent = BoomPanel
end
BoomPlay.Size = UDim2.new(0.16, 0, 0.56, 0)
BoomPlay.Position = UDim2.new(0.64, 0, 0.22, 0)
BoomPlay.Visible = true
SetCaption(BoomPlay, "Play")
StyleButton(BoomPlay, THEME.ButtonBackground, THEME.ButtonStroke, THEME.Text)

local BoomStop = BoomPanel:FindFirstChild("Stop")
if not BoomStop then
	BoomStop = ChangeText:Clone()
	BoomStop.Name = "Stop"
	BoomStop.Parent = BoomPanel
end
BoomStop.Size = UDim2.new(0.16, 0, 0.56, 0)
BoomStop.Position = UDim2.new(0.82, 0, 0.22, 0)
BoomStop.Visible = true
SetCaption(BoomStop, "Stop")
StyleButton(BoomStop, THEME.DangerBackground, THEME.DangerStroke, THEME.DangerText)

local function SendAudio()
	local id = ReadImageId(BoomBox.Text)
	if id then
		BoomboxRemote:FireServer("Play", id)
	else
		BoomBox.Text = ""
		BoomBox.PlaceholderText = "Numbers only.."
	end
end

BoomPlay.MouseButton1Click:Connect(SendAudio)

BoomBox.FocusLost:Connect(function(EnterPressed)
	if EnterPressed then
		SendAudio()
	end
end)

BoomStop.MouseButton1Click:Connect(function()
	BoomboxRemote:FireServer("Stop")
end)

-- Show the panel only while the tool is actually equipped.
local function WatchCharacter(character)
	character.ChildAdded:Connect(function(child)
		if child.Name == "Boombox" and child:IsA("Tool") then
			BoomPanel.Visible = true
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child.Name == "Boombox" and child:IsA("Tool") then
			BoomPanel.Visible = false
		end
	end)
	BoomPanel.Visible = character:FindFirstChild("Boombox") ~= nil
end

if Player.Character then
	WatchCharacter(Player.Character)
end
Player.CharacterAdded:Connect(function(character)
	BoomPanel.Visible = false
	WatchCharacter(character)
end)

-------------------------------------------------------------------------------
-- Initial state
-------------------------------------------------------------------------------

Frame.Visible = false
ShopFrame.Visible = false
AdminFrame.Visible = false
AdminButton.Visible = false
BoomPanel.Visible = false
LoadIntoEditor(nil)
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
