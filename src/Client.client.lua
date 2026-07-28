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

	-- Rank badges. Same weight as the rest of the palette so the panel still
	-- reads as one piece, just with the rank obvious at a glance.
	OwnerBadge = Color3.fromRGB(255, 196, 92),
	DevBadge = Color3.fromRGB(120, 235, 160),
	AdminBadge = Color3.fromRGB(214, 170, 255),
	ModBadge = Color3.fromRGB(130, 200, 255),
	PlayerBadge = Color3.fromRGB(150, 156, 166),

	ReportBackground = Color3.fromRGB(52, 34, 20),
	ReportText = Color3.fromRGB(255, 190, 130),

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

--[[
	Every input in the place is a clone of Frame.TextBox, and that box is set
	to TextScaled = true in the .rbxl. TextScaled grows the font until it fills
	the box, so a 42px tall field rendered ~38px glyphs where a UI font wants
	14-18. That is what made the boxes look shouty and cramped, and it was
	inherited by all seven clones because nothing here ever turned it off.

	So the text properties are pinned explicitly rather than left to whatever
	the source happened to carry:

	    TextScaled  off, or the size below is ignored
	    TextSize    a real, readable size
	    TextWrapped off, because these are one-line fields and wrapping a
	                placeholder mid-word inside a 42px box looks broken
	    TextXAlignment  left, so the caret starts where the eye does
	    UIPadding   a few pixels so the text is not flush against the border

	Anything that genuinely wants different values sets them after calling this.
--]]
local INPUT_TEXT_SIZE = 15

local function StyleInput(Box)
	Box.BackgroundColor3 = THEME.InputBackground
	Box.BackgroundTransparency = 0
	Box.BorderSizePixel = 0
	Box.TextColor3 = THEME.Text
	Box.TextStrokeTransparency = 1
	Box.PlaceholderColor3 = THEME.Placeholder

	Box.TextScaled = false
	Box.TextSize = INPUT_TEXT_SIZE
	Box.TextWrapped = false
	Box.TextTruncate = Enum.TextTruncate.AtEnd
	Box.TextXAlignment = Enum.TextXAlignment.Left
	Box.TextYAlignment = Enum.TextYAlignment.Center
	Box.Font = BODY_FONT
	Box.ClipsDescendants = true

	local pad = Box:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Parent = Box
	end
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)

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

--[[
	The HUD button stack, bottom left.

	These used to each pick their own offset from ToggleButton - 0.085, 0.17,
	0.255 - which meant the spacing was three numbers in three different parts
	of the file that all had to agree, and adding a fourth button meant
	guessing the next one. The stack is defined once here instead.

	A minimum pixel height is applied too. ToggleButton's size is pure scale,
	so on a small window the buttons shrank until the captions were unreadable,
	which is what they were doing in the screenshots.
--]]
local HUD = {
	MinWidth = 104,
	MinHeight = 34,
	--[[
		The gap between buttons, in pixels.

		Has to cover two things at once: the visual gap, and the amount the
		UISizeConstraint can lift a button above its scale height on a small
		window. 20 is the smallest value that never lets them touch between
		1080p and roughly 600x320, while still reading as one stack rather
		than four scattered buttons.
	--]]
	Pad = 20,
	-- button -> slot, so the stack can be relaid out and hidden as a group.
	Placed = {},
}

--[[
	A minimum size, done correctly.

	The previous attempt wrote

	    math.max(ToggleButton.Size.X.Offset, HUD.MinWidth)

	meaning "at least 104 wide". It is not. A UDim2 axis resolves as
	scale * parent + offset, so the two are ADDED: a 137px button became
	137 + 104 = 241px, and every button in the stack grew past the gap between
	them and past its own column. That is what made the HUD worse rather than
	better.

	A minimum in a system that adds has to be expressed as pure pixels with no
	scale at all, which is what UISizeConstraint is for. The button keeps its
	scale size and the constraint raises it only when the window is small
	enough to need it.
--]]
do
	local limit = ToggleButton:FindFirstChildOfClass("UISizeConstraint")
	if not limit then
		limit = Instance.new("UISizeConstraint")
		limit.Parent = ToggleButton
	end
	limit.MinSize = Vector2.new(HUD.MinWidth, HUD.MinHeight)
end

HUD.Size = ToggleButton.Size
HUD.Anchor = ToggleButton.Position

-- Slot 0. The place file already positions it, so it is registered by hand
-- rather than going through PlaceHudButton.
HUD.Placed[ToggleButton] = 0

--[[
	Stacked upwards from the toggle.

	The spacing used to be pure scale while the height had a pixel floor, so on
	a short window the gap shrank below the button and they piled on top of
	each other - visibly, in the bug report. The offset now carries the spacing
	in pixels, so the gap and the height are in the same units and cannot drift
	apart at any window size.
--]]
--[[
	Below roughly 1024px wide the panel is simply wider than the space beside
	it, so no amount of repositioning keeps the HUD clear: at 617px the panel
	starts at x=23 and the buttons already reach x=108. Shrinking the buttons
	would only trade the overlap for unreadable text.

	So the stack hides while a window is open, which costs nothing - the window
	it opened is already on screen, with its own close button. This is what the
	Roblox menus do as well.
--]]
--[[
	Some buttons have their own reason to be hidden - the booth toggle only
	appears once a booth is claimed, the admin button only for staff. Those
	rules are remembered here so that restoring the stack cannot turn a button
	back on that was never supposed to be showing.

	HUD.Allowed[button] == false means "never show this one". Anything not
	listed is always allowed.
--]]
HUD.Allowed = {}

-- Whether a window is currently covering the HUD. Kept so that a permission
-- change arriving while the panel is open cannot put a button back on screen
-- underneath it, which is exactly what AdminAccess used to do.
HUD.Hidden = false

function HUD.Show(visible)
	HUD.Hidden = not visible
	for button in pairs(HUD.Placed) do
		local allowed = HUD.Allowed[button]
		if allowed == nil then
			allowed = true
		end
		button.Visible = visible and allowed
	end
end

-- Re-applies the current rules. Called after anything changes a button's
-- permission, so the answer always goes through one place.
function HUD.Refresh()
	HUD.Show(not HUD.Hidden)
end

--[[
	Stacked upwards from the toggle.

	The spacing is carried in BOTH parts of the UDim2, matching how the button
	itself is sized:

	    scale  = the button's own scale height, so the gap grows with the
	             button on a tall window
	    offset = the pad, plus enough to clear the pixel floor on a short one

	Doing it in pixels alone was wrong. The step was worked out once from
	whatever ScreenGui.AbsoluteSize happened to be at build time and then baked
	into an offset, so at 1080p the buttons were 77px tall but still stacked
	50px apart and overlapped by 27. Scale spacing tracks scale sizing for
	free, at every window size, with nothing to recompute on resize.
--]]
local function PlaceHudButton(button, slot)
	HUD.Placed[button] = slot
	button.Size = HUD.Size

	-- Each clone needs its own constraint; they are not inherited by assigning
	-- Size from another button.
	local limit = button:FindFirstChildOfClass("UISizeConstraint")
	if not limit then
		limit = Instance.new("UISizeConstraint")
		limit.Parent = button
	end
	limit.MinSize = Vector2.new(HUD.MinWidth, HUD.MinHeight)

	--[[
		The gap has to clear whichever of the two is deciding the height, and
		which one that is changes with the window:

		    big window    the scale height wins
		    small window  the UISizeConstraint floor wins

		Both are covered by carrying the scale height in the scale part and a
		fixed pad in the offset, with the pad sized to absorb how far the
		constraint can lift a button on a small window.

		Deliberately no measurement of ScreenGui.AbsoluteSize here, because
		measuring the screen is what broke this twice: the step was computed
		once from whatever the size happened to be when the button was built,
		then baked into a fixed offset, so it was only ever right at that one
		size. This version cannot go stale, and needs no resize event to be
		correct.
	--]]
	local stepScale = HUD.Size.Y.Scale
	local stepOffset = HUD.Size.Y.Offset + HUD.Pad

	button.Position = UDim2.new(
		HUD.Anchor.X.Scale,
		HUD.Anchor.X.Offset,
		HUD.Anchor.Y.Scale - stepScale * slot,
		HUD.Anchor.Y.Offset - stepOffset * slot
	)
end

local ShopButton = ScreenGui:FindFirstChild("ShopButton")
if not ShopButton then
	ShopButton = ToggleButton:Clone()
	ShopButton.Name = "ShopButton"
	ShopButton.Parent = ScreenGui
end
ShopButton.Visible = true
PlaceHudButton(ShopButton, 1)
SetCaption(ShopButton, "Shop")
StyleButton(ShopButton, THEME.PanelBackground, THEME.ShopOutline, THEME.Text)
GetOrMakeCorner(ShopButton, SHOP_CORNER)
StyleBorder(ShopButton, THEME.ShopOutline, 4)
AddSheen(ShopButton)

-- Match the heavier shop outline on the booth toggle so the HUD buttons read
-- as one set. Its size was already settled above.
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
do
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

do
	local sideList = Sidebar:FindFirstChildOfClass("UIListLayout")
	if not sideList then
		sideList = Instance.new("UIListLayout")
		sideList.Parent = Sidebar
	end
	sideList.SortOrder = Enum.SortOrder.LayoutOrder
	sideList.Padding = UDim.new(0.035, 0)
	sideList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sideList.VerticalAlignment = Enum.VerticalAlignment.Top
end

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
gridLayout.CellPadding = UDim2.new(0.04, 0, 0.04, 0)
gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

-- FIX: UIAspectRatioConstraint only works when parented to a real GuiObject
-- (it needs AbsoluteSize), not a UIGridLayout. Parenting it there silently
-- does nothing, so CellSize's height stayed at "0, 0" forever and every
-- card rendered at 0px tall - invisible, even though it existed and passed
-- the category filter. Compute cell height directly from the grid's actual
-- pixel width instead, and keep it updated as the grid resizes.
local CARD_ASPECT = 1.30
local CARD_WIDTH_SCALE = 0.47

local function UpdateGridCellSize()
	local cellWidth = Grid.AbsoluteSize.X * CARD_WIDTH_SCALE
	local cellHeight = cellWidth / CARD_ASPECT
	gridLayout.CellSize = UDim2.new(CARD_WIDTH_SCALE, 0, 0, cellHeight)
end

Grid:GetPropertyChangedSignal("AbsoluteSize"):Connect(UpdateGridCellSize)
UpdateGridCellSize()

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
	Same look as the shop, scaled up: heavy black outline, dark cards, a
	sidebar of pages down the left.

	    Home      who you are, your headshot, the server at a glance
	    Players   everyone here, with the moderation buttons per row
	    Reports   the queue of reported booths
	    Staff     the whitelist, and the ban list
	    Shop      the gamepass editor that used to be the whole panel

	Which pages you get depends on your rank, and the server only ever sends
	the pages you are allowed to see. None of that is trusted though: the
	panel is a convenience, and every button ends up at the same server side
	check a chat command would hit.
--]]

local IsAdminClient = false
local MyRank = 0
local MyRankName = "Player"

--[[
	Must match the server's numbers exactly. They are compared with >= on both
	sides, so Developer slotting in at 3 gives it every Admin power without any
	other line needing to know it exists.
--]]
local RANK = {
	Mod = 1,
	Admin = 2,
	Dev = 3,
	Owner = 4,
}

local function RankColour(rank)
	if rank >= RANK.Owner then
		return THEME.OwnerBadge
	elseif rank >= RANK.Dev then
		return THEME.DevBadge
	elseif rank >= RANK.Admin then
		return THEME.AdminBadge
	elseif rank >= RANK.Mod then
		return THEME.ModBadge
	end
	return THEME.PlayerBadge
end

--[[
	Cloned from ToggleButton, not built from nothing.

	ShopButton is a clone, so it draws its caption through a child TextLabel
	that carries the place's own font, stroke and padding. This one was an
	Instance.new with the text set directly on the button, so the two rendered
	visibly differently sitting next to each other - different weight, and the
	caption sat off centre against its neighbour.

	Cloning gets the same child and the same look for free, and SetCaption
	writes to whichever of the two a button actually uses.
--]]
local AdminButton = ScreenGui:FindFirstChild("AdminButton")
if not AdminButton then
	AdminButton = ToggleButton:Clone()
	AdminButton.Name = "AdminButton"
	AdminButton.Parent = ScreenGui
end
PlaceHudButton(AdminButton, 2)
SetCaption(AdminButton, "Admin")
AdminButton.TextScaled = true
AdminButton.Font = TITLE_FONT
AdminButton.BackgroundColor3 = THEME.AdminBackground
StyleCaption(AdminButton, THEME.AdminText)
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
--[[
	Sized in scale, with a floor so it stays readable and a ceiling so it can
	never be bigger than the window it is drawn in.

	The floor on its own was a mistake, and a worse bug than the one it fixed:
	a 720x400 minimum on a 617x326 window put the panel over both edges, so the
	close button sat off screen. A minimum that ignores the window is not a
	minimum, it is an overflow.

	UISizeConstraint takes a MaxSize as well, so the two together say what was
	actually meant: be at least this readable, never wider than the screen.
	Roblox applies MaxSize after MinSize, so the cap wins on a small window,
	which is the behaviour we want.

	ScreenGui.AbsoluteSize is watched rather than assumed, because the window
	can be resized mid-session and a cap computed once at startup would be
	wrong the moment somebody drags the window.
--]]
AdminFrame.Size = UDim2.new(0.72, 0, 0.68, 0)
AdminFrame.Position = UDim2.new(0.5, 0, 0.5, 0)

--[[
	The floating windows FitWindowsToScreen has to keep on screen.

	Holds the frames themselves rather than a flag, because the report window
	is created hundreds of lines below this point and naming it directly here
	would read as a nil global until then.
--]]
local SizeLimits = {}

-- Keeps both windows inside whatever the screen currently is.
--[[
	Keeps both windows on screen AND readable, which are two different jobs.

	Capping the size stops the panel hanging off the edge, but on its own it
	just squashes the contents instead: at 617x326 the rank label came out
	14px tall and the status line 13px, which is unreadable however neatly it
	fits. Scale factors do not care that text has a minimum useful size.

	So the panel keeps its full DESIGN size and a UIScale shrinks the whole
	thing as one piece when the window cannot fit it. Every proportion inside
	is preserved and the text shrinks evenly with everything else, instead of
	rows collapsing at different rates and landing on top of each other.

	Below MIN_SCALE it stops shrinking and simply clips, because past that
	point it is too small to use and hiding that helps nobody.
--]]
--[[
	The design size the panel is laid out at before scaling.

	Deliberately modest. A bigger canvas looks roomier on a large monitor but
	has to scale down further on a small one, and everything inside scales with
	it - so an ambitious design size is what turns a 28px row into 17px of
	unreadable text on a 617x326 window. 736x400 is the largest that still
	keeps the thinnest rows legible at the smallest window worth supporting.
--]]
local WINDOW = {
	AdminW = 736, AdminH = 400,
	ReportW = 560, ReportH = 340,
	MinScale = 0.5,
	-- Height the input dock reserves at the top: its own height plus the gap
	-- above it, plus a little breathing room below.
	DockStrip = 62,
}

local function ScaleFor(frame, wantW, wantH, screen)
	local scale = frame:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = frame
	end

	-- Whichever axis is tighter decides, so it never overflows the other.
	local fit = math.min((screen.X - 16) / wantW, (screen.Y - 16) / wantH, 1)
	scale.Scale = math.max(fit, WINDOW.MinScale)
	return scale
end

local function FitWindowsToScreen()
	local screen = ScreenGui.AbsoluteSize
	if screen.X <= 0 or screen.Y <= 0 then
		return
	end

	--[[
		Fixed pixel sizes, then scaled. Laying out at a known size is what
		makes the proportions predictable at every window.

		The height available is the screen MINUS the strip the input dock
		occupies at the top. Without that the panel centres on the whole screen
		and, on a small window where it fills the height, the dock lands on top
		of its title. Reserving the strip and nudging the panel down by half of
		it keeps the two apart at every size.
	--]]
	local reserved = WINDOW.DockStrip
	local usable = Vector2.new(screen.X, math.max(screen.Y - reserved, 120))

	AdminFrame.Size = UDim2.new(0, WINDOW.AdminW, 0, WINDOW.AdminH)
	ScaleFor(AdminFrame, WINDOW.AdminW, WINDOW.AdminH, usable)
	AdminFrame.Position = UDim2.new(0.5, 0, 0.5, math.floor(reserved / 2))

	-- The report window is built much further down the file, so it is fetched
	-- from the table rather than named directly: a bare `ReportFrame` here
	-- reads as a nil global until that local exists, which is a crash the
	-- moment the window is resized before the report UI is built.
	if SizeLimits.Report then
		SizeLimits.Report.Size = UDim2.new(0, WINDOW.ReportW, 0, WINDOW.ReportH)
		ScaleFor(SizeLimits.Report, WINDOW.ReportW, WINDOW.ReportH, screen)
	end
end

AdminFrame.AnchorPoint = Vector2.new(0.5, 0.5)
AdminFrame.BackgroundColor3 = THEME.PanelBackground
AdminFrame.BorderSizePixel = 0
AdminFrame.ZIndex = 2
GetOrMakeCorner(AdminFrame, SHOP_CORNER)
StyleBorder(AdminFrame, THEME.ShopOutline, 4)
AddSheen(AdminFrame)

local AdminTitle = AdminFrame:FindFirstChild("AdminTitle")
if not AdminTitle then
	AdminTitle = Instance.new("TextLabel")
	AdminTitle.Name = "AdminTitle"
	AdminTitle.Parent = AdminFrame
end
AdminTitle.Size = UDim2.new(1, 0, 0.12, 0)
AdminTitle.Position = UDim2.new(0.5, 0, -0.015, 0)
AdminTitle.AnchorPoint = Vector2.new(0.5, 1)
AdminTitle.BackgroundTransparency = 1
AdminTitle.Text = "Admin"
AdminTitle.TextScaled = true
AdminTitle.Font = TITLE_FONT
AdminTitle.TextColor3 = THEME.Text
AdminTitle.ZIndex = 3
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
AdminClose.Size = UDim2.new(0.048, 0, 0.082, 0)
AdminClose.Position = UDim2.new(1, 0, 0, 0)
AdminClose.AnchorPoint = Vector2.new(0.5, 0.5)
AdminClose.Text = "X"
AdminClose.TextScaled = true
AdminClose.Font = TITLE_FONT
AdminClose.BackgroundColor3 = THEME.DangerBackground
AdminClose.TextColor3 = THEME.DangerText
AdminClose.BorderSizePixel = 0
AdminClose.ZIndex = 6
GetOrMakeCorner(AdminClose, UDim.new(1, 0))
StyleBorder(AdminClose, THEME.ShopOutline, 3)

-------------------------------------------------------------------------------
-- Greeting
-------------------------------------------------------------------------------
--[[
	"Hello, <name>." with the admin's own headshot next to it, and their rank
	underneath. The picture comes from the server, which fetches it through
	the proxy. If that never arrives the client asks Roblox itself, and if
	that fails too the circle just shows the first letter of the name, so the
	header always looks finished.
--]]

--[[
	Where the greeting's text column starts, as a fraction of the card width.

	Worked out rather than typed. The headshot is a circle sized off the card
	HEIGHT but positioned as a fraction of the card WIDTH, so how far across it
	reaches depends on the card's aspect ratio - which means a hand-picked
	number silently goes wrong the moment the card is resized. That has now
	happened twice.

	    reach = inset + height * headScale / cardWidth

	so deriving it from the same three numbers the widgets use keeps the text
	clear of the picture whatever the card becomes.
--]]
local GREET = {
	W = 0.245, H = 0.225,
	HeadScale = 0.72,
	HeadInset = 0.05,
}

GREET.TextX = GREET.HeadInset
	+ (GREET.H * GREET.HeadScale) / (GREET.W * (16 / 9))
	+ 0.06

local Greet = AdminFrame:FindFirstChild("Greet")
if not Greet then
	Greet = Instance.new("Frame")
	Greet.Name = "Greet"
	Greet.Parent = AdminFrame
end
Greet.Size = UDim2.new(GREET.W, 0, GREET.H, 0)
Greet.Position = UDim2.new(0.022, 0, 0.035, 0)
Greet.BackgroundColor3 = THEME.CardBackground
Greet.BorderSizePixel = 0
Greet.ZIndex = 3
GetOrMakeCorner(Greet, CONTROL_CORNER)
StyleBorder(Greet, THEME.ShopOutline, 3)

local GreetImage = Greet:FindFirstChild("Head")
if not GreetImage then
	GreetImage = Instance.new("ImageLabel")
	GreetImage.Name = "Head"
	GreetImage.Parent = Greet
end
--[[
	The headshot is square, so its width comes from the card's HEIGHT while its
	position is a fraction of the card's WIDTH. Those are different numbers, so
	the picture's right edge has to be worked out rather than guessed: at 0.76
	of a 98px card it is 74px wide starting 14px in, which ran under text that
	began at 82px.

	GREET.TextX is derived from the same figures below, so the text column
	always starts clear of the picture no matter how the card is resized.
--]]
GreetImage.Size = UDim2.new(0, 0, GREET.HeadScale, 0)
GreetImage.Position = UDim2.new(GREET.HeadInset, 0, 0.5, 0)
GreetImage.AnchorPoint = Vector2.new(0, 0.5)
GreetImage.BackgroundColor3 = THEME.InputBackground
GreetImage.BorderSizePixel = 0
GreetImage.ScaleType = Enum.ScaleType.Fit
GreetImage.Image = ""
GreetImage.ZIndex = 4
GetOrMakeCorner(GreetImage, UDim.new(1, 0))
StyleBorder(GreetImage, THEME.ShopOutline, 2)
do
	-- Keeps the headshot a circle at any window size.
	local ar = GreetImage:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not ar then
		ar = Instance.new("UIAspectRatioConstraint")
		ar.Parent = GreetImage
	end
	ar.AspectRatio = 1
end

-- Shown behind the picture, so there is never an empty hole while it loads.
do
	local init = GreetImage:FindFirstChild("Initial")
	if not init then
		init = Instance.new("TextLabel")
		init.Name = "Initial"
		init.Parent = GreetImage
	end
end
GreetImage.Initial.Size = UDim2.new(1, 0, 1, 0)
GreetImage.Initial.BackgroundTransparency = 1
GreetImage.Initial.Text = string.upper(string.sub(Player.Name, 1, 1))
GreetImage.Initial.TextScaled = true
GreetImage.Initial.Font = TITLE_FONT
GreetImage.Initial.TextColor3 = THEME.MutedText
GreetImage.Initial.ZIndex = 4

local GreetHello = Greet:FindFirstChild("Hello")
if not GreetHello then
	GreetHello = Instance.new("TextLabel")
	GreetHello.Name = "Hello"
	GreetHello.Parent = Greet
end
GreetHello.Size = UDim2.new(1 - GREET.TextX - 0.04, 0, 0.36, 0)
GreetHello.Position = UDim2.new(GREET.TextX, 0, 0.16, 0)
GreetHello.BackgroundTransparency = 1
GreetHello.Text = "Hello, " .. Player.Name .. "."
GreetHello.TextScaled = true
GreetHello.Font = TITLE_FONT
GreetHello.TextColor3 = THEME.Text
GreetHello.TextXAlignment = Enum.TextXAlignment.Left
GreetHello.ZIndex = 4

local GreetRank = Greet:FindFirstChild("Rank")
if not GreetRank then
	GreetRank = Instance.new("TextLabel")
	GreetRank.Name = "Rank"
	GreetRank.Parent = Greet
end
GreetRank.Size = UDim2.new(1 - GREET.TextX - 0.04, 0, 0.34, 0)
GreetRank.Position = UDim2.new(GREET.TextX, 0, 0.52, 0)
GreetRank.BackgroundTransparency = 1
GreetRank.Text = "Player"
GreetRank.TextScaled = true
GreetRank.Font = BODY_FONT
GreetRank.TextColor3 = THEME.MutedText
GreetRank.TextXAlignment = Enum.TextXAlignment.Left
GreetRank.ZIndex = 4

-- Every headshot the panel has been told about, so the player rows and the
-- greeting can share one lookup instead of each fetching their own.
local Headshots = {}

local function SetGreeting(name, rankName, rank)
	GreetHello.Text = "Hello, " .. name .. "."
	GreetRank.Text = rankName
	GreetRank.TextColor3 = RankColour(rank or 0)
	GreetImage.Initial.Text = string.upper(string.sub(name, 1, 1))
end

-- Last resort if the proxy never answers: ask the client's own Roblox session.
local function LocalHeadshot(userId, apply)
	spawn(function()
		local ok, content = pcall(function()
			return Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size420x420
			)
		end)
		if ok and content and content ~= "" then
			Headshots[userId] = content
			apply(content)
		end
	end)
end

local function ApplyGreetHeadshot(url)
	GreetImage.Image = url or ""
	GreetImage.Initial.Visible = (url == nil or url == "")
end

-------------------------------------------------------------------------------
-- Pages
-------------------------------------------------------------------------------
--[[
	The sidebar and the page bodies are built from one table, so adding a page
	later is one entry rather than five edits. MinRank hides a page from
	anyone below it, which is why a Mod never sees the Staff or Shop tabs.
--]]

local PAGES = {
	{Name = "Home", MinRank = RANK.Mod},
	{Name = "Players", MinRank = RANK.Mod},
	{Name = "Reports", MinRank = RANK.Mod},
	{Name = "Staff", MinRank = RANK.Admin},
	{Name = "Shop", MinRank = RANK.Admin},
	{Name = "Trolling", MinRank = RANK.Admin},
}

local PageNav = AdminFrame:FindFirstChild("PageNav")
if not PageNav then
	PageNav = Instance.new("Frame")
	PageNav.Name = "PageNav"
	PageNav.Parent = AdminFrame
end
PageNav.Size = UDim2.new(0.245, 0, 0.58, 0)
PageNav.Position = UDim2.new(0.022, 0, 0.295, 0)
PageNav.BackgroundTransparency = 1
PageNav.ZIndex = 3

do
	local navLayout = PageNav:FindFirstChildOfClass("UIListLayout")
	if not navLayout then
		navLayout = Instance.new("UIListLayout")
		navLayout.Parent = PageNav
	end
	navLayout.SortOrder = Enum.SortOrder.LayoutOrder
	navLayout.Padding = UDim.new(0.025, 0)
	navLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
end

-- Where every page's contents live. One is visible at a time.
local PageHost = AdminFrame:FindFirstChild("PageHost")
if not PageHost then
	PageHost = Instance.new("Frame")
	PageHost.Name = "PageHost"
	PageHost.Parent = AdminFrame
end
PageHost.Size = UDim2.new(0.685, 0, 0.845, 0)
PageHost.Position = UDim2.new(0.295, 0, 0.035, 0)
PageHost.BackgroundTransparency = 1
PageHost.ZIndex = 3

local PageButtons = {}
local PageBodies = {}
local CurrentPage = nil

-- Assigned with the input dock further down, which cannot be built until
-- StyleInput and the theme exist. SelectPage runs before that, so it is
-- declared here and called only once it has a value.
local RefreshDock

-- Status line along the bottom, shared by every page.
local AdminStatus = AdminFrame:FindFirstChild("AdminStatus")
if not AdminStatus then
	AdminStatus = Instance.new("TextLabel")
	AdminStatus.Name = "AdminStatus"
	AdminStatus.Parent = AdminFrame
end
AdminStatus.Size = UDim2.new(0.95, 0, 0.075, 0)
AdminStatus.Position = UDim2.new(0.5, 0, 0.952, 0)
AdminStatus.AnchorPoint = Vector2.new(0.5, 0.5)
AdminStatus.BackgroundTransparency = 1
AdminStatus.Text = ""
AdminStatus.TextScaled = true
AdminStatus.Font = BODY_FONT
AdminStatus.TextColor3 = THEME.MutedText
AdminStatus.ZIndex = 4

local AdminStatusToken = 0

local function SetAdminStatus(msg, bad)
	AdminStatusToken = AdminStatusToken + 1
	local mine = AdminStatusToken

	AdminStatus.Text = msg or ""
	if bad then
		AdminStatus.TextColor3 = THEME.Bad
	else
		AdminStatus.TextColor3 = THEME.Good
	end

	if msg and msg ~= "" then
		delay(6, function()
			if AdminStatusToken == mine then
				AdminStatus.Text = ""
			end
		end)
	end
end

local function MakePageBody(name)
	local body = PageHost:FindFirstChild("P_" .. name)
	if not body then
		body = Instance.new("Frame")
		body.Name = "P_" .. name
		body.Parent = PageHost
	end
	body.Size = UDim2.new(1, 0, 1, 0)
	body.BackgroundTransparency = 1
	body.Visible = false
	body.ZIndex = 3
	PageBodies[name] = body
	return body
end

local function SelectPage(name)
	if not PageBodies[name] then
		return
	end

	CurrentPage = name

	for pageName, body in pairs(PageBodies) do
		body.Visible = (pageName == name)
	end

	for pageName, button in pairs(PageButtons) do
		local active = (pageName == name)
		if active then
			button.BackgroundColor3 = THEME.TabActive
			button.TextColor3 = THEME.Text
			StyleBorder(button, THEME.ShopOutline, 4)
		else
			button.BackgroundColor3 = THEME.TabIdle
			button.TextColor3 = THEME.MutedText
			StyleBorder(button, THEME.ShopOutline, 3)
		end
	end

	AdminTitle.Text = "Admin  -  " .. name

	-- Not every page takes a value, so the dock follows the page.
	if RefreshDock then
		RefreshDock()
	end

	-- Ask for just this page's data, so tabbing around stays current without
	-- resending everything every time.
	RemoteEvent:FireServer("AdminRefresh", name)
end

local function BuildNav()
	for i, page in ipairs(PAGES) do
		local allowed = MyRank >= page.MinRank

		local button = PageButtons[page.Name]
		if not button then
			button = Instance.new("TextButton")
			button.Name = "Nav_" .. page.Name
			button.Parent = PageNav
			button.MouseButton1Click:Connect(function()
				SelectPage(page.Name)
			end)
			PageButtons[page.Name] = button
		end

		button.LayoutOrder = i
		button.Size = UDim2.new(0.94, 0, 0.14, 0)
		button.Text = page.Name
		button.TextScaled = true
		button.Font = TITLE_FONT
		button.BorderSizePixel = 0
		button.AutoButtonColor = true
		button.ZIndex = 4
		button.Visible = allowed
		GetOrMakeCorner(button, CONTROL_CORNER)
		StyleBorder(button, THEME.ShopOutline, 3)

		if PageBodies[page.Name] then
			-- A demotion while the panel is open must not leave you looking at
			-- a page you can no longer use.
			if not allowed and CurrentPage == page.Name then
				SelectPage("Home")
			end
		end
	end
end

-- Reusable bits ---------------------------------------------------------------

local function MakeScroller(parent, name, size, position)
	local sf = parent:FindFirstChild(name)
	if not sf then
		sf = Instance.new("ScrollingFrame")
		sf.Name = name
		sf.Parent = parent
	end
	sf.Size = size
	sf.Position = position
	sf.BackgroundColor3 = THEME.CardBackground
	sf.BackgroundTransparency = 0
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 6
	sf.ScrollBarImageColor3 = THEME.PanelStroke
	sf.CanvasSize = UDim2.new(0, 0, 0, 0)
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.ZIndex = 3
	GetOrMakeCorner(sf, CONTROL_CORNER)
	StyleBorder(sf, THEME.ShopOutline, 3)

	local layout = sf:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = Instance.new("UIListLayout")
		layout.Parent = sf
	end
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 5)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local pad = sf:FindFirstChildOfClass("UIPadding")
	if not pad then
		pad = Instance.new("UIPadding")
		pad.Parent = sf
	end
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)

	return sf
end

--[[
	Rows and cards are rebuilt in place as data changes, so a button that
	already exists must not be connected a second time or one click would fire
	the remote twice. Attributes would be the tidy way to mark that, but this
	place targets old Roblox where they do not exist, so the buttons already
	wired are simply remembered here.
--]]
local Wired = {}

-- The two grids that command buttons get parented into, one per page.
local Grids = {}

local function MakeSmallButton(parent, name, caption, background, textColour)
	local b = parent:FindFirstChild(name)
	if not b then
		b = Instance.new("TextButton")
		b.Name = name
		b.Parent = parent
	end
	b.Text = caption
	b.TextScaled = true
	b.Font = TITLE_FONT
	b.BackgroundColor3 = background
	b.TextColor3 = textColour
	b.BorderSizePixel = 0
	b.AutoButtonColor = true
	b.ZIndex = 5
	GetOrMakeCorner(b, CONTROL_CORNER)
	StyleBorder(b, THEME.ShopOutline, 2)
	return b
end

-- A round headshot that fills itself in as pictures arrive.
local function MakeHeadshot(parent, name, userId, displayName)
	local img = parent:FindFirstChild(name)
	if not img then
		img = Instance.new("ImageLabel")
		img.Name = name
		img.Parent = parent
	end
	img.BackgroundColor3 = THEME.InputBackground
	img.BorderSizePixel = 0
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 4
	GetOrMakeCorner(img, UDim.new(1, 0))

	local initial = img:FindFirstChild("Initial")
	if not initial then
		initial = Instance.new("TextLabel")
		initial.Name = "Initial"
		initial.Parent = img
	end
	initial.Size = UDim2.new(1, 0, 1, 0)
	initial.BackgroundTransparency = 1
	initial.Text = string.upper(string.sub(tostring(displayName or "?"), 1, 1))
	initial.TextScaled = true
	initial.Font = TITLE_FONT
	initial.TextColor3 = THEME.MutedText
	initial.ZIndex = 4

	local url = Headshots[userId]
	img.Image = url or ""
	initial.Visible = (url == nil)

	if not url and userId then
		-- Nothing cached: fall back to the client's own copy rather than
		-- leaving a blank circle.
		LocalHeadshot(userId, function(content)
			if img.Parent then
				img.Image = content
				initial.Visible = false
			end
		end)
	end

	return img
end

-------------------------------------------------------------------------------
-- The input dock
-------------------------------------------------------------------------------
--[[
	One text field for the whole panel, floating above it rather than living
	inside it.

	The panel is laid out in scale and shrunk by a UIScale to fit the window,
	which is right for rows of buttons but wrong for a text field: the field
	shrinks with everything else and the text inside it has a minimum size
	below which it simply stops being readable. On a small window the boxes
	ended up shorter than their own text.

	So the field is pulled out and pinned to the top of the screen in FIXED
	PIXELS. It never scales, so it is the same comfortable size at 1920x1080
	and at 617x326, and it sits at a higher ZIndex than the panel so it works
	even when the panel is filling the whole screen.

	It also replaces two separate boxes - the Home page's message field and the
	Players page's argument field - with one, because they always meant the
	same thing: "the value for whatever I press next".
--]]

local DOCK = {Height = 40, Top = 10}

local InputDock = ScreenGui:FindFirstChild("InputDock")
if not InputDock then
	InputDock = Instance.new("Frame")
	InputDock.Name = "InputDock"
	InputDock.Parent = ScreenGui
end
--[[
	Fixed width, but never wider than the window. 520 fits comfortably from
	1080p down to about 550px across; below that the offset alone would hang
	off both edges, so the scale part takes over and it simply spans the screen
	with a small inset.
--]]
InputDock.Size = UDim2.new(0, 520, 0, DOCK.Height)
InputDock.SizeConstraint = Enum.SizeConstraint.RelativeXY

do
	local limit = InputDock:FindFirstChildOfClass("UISizeConstraint")
	if not limit then
		limit = Instance.new("UISizeConstraint")
		limit.Parent = InputDock
	end
	DOCK.Limit = limit
end
InputDock.Position = UDim2.new(0.5, 0, 0, DOCK.Top)
InputDock.AnchorPoint = Vector2.new(0.5, 0)
InputDock.BackgroundColor3 = THEME.PanelBackground
InputDock.BorderSizePixel = 0
InputDock.Visible = false
-- Above the panel (2) but below the toast banner (10).
InputDock.ZIndex = 9
GetOrMakeCorner(InputDock, SHOP_CORNER)
StyleBorder(InputDock, THEME.ShopOutline, 4)
AddSheen(InputDock)

-- Says what the field is for right now, so one box serving several commands is
-- never ambiguous.
DOCK.Label = InputDock:FindFirstChild("Caption")
if not DOCK.Label then
	DOCK.Label = Instance.new("TextLabel")
	DOCK.Label.Name = "Caption"
	DOCK.Label.Parent = InputDock
end
DOCK.Label.Size = UDim2.new(0, 92, 1, 0)
DOCK.Label.Position = UDim2.new(0, 12, 0, 0)
DOCK.Label.BackgroundTransparency = 1
DOCK.Label.Text = "Value"
DOCK.Label.TextScaled = false
DOCK.Label.TextSize = 14
DOCK.Label.Font = TITLE_FONT
DOCK.Label.TextColor3 = THEME.MutedText
DOCK.Label.TextXAlignment = Enum.TextXAlignment.Left
DOCK.Label.ZIndex = 10

DOCK.Input = InputDock:FindFirstChild("Box")
if not DOCK.Input then
	DOCK.Input = Instance.new("TextBox")
	DOCK.Input.Name = "Box"
	DOCK.Input.Parent = InputDock
end
DOCK.Input.Size = UDim2.new(1, -116, 0, 28)
DOCK.Input.Position = UDim2.new(0, 104, 0.5, 0)
DOCK.Input.AnchorPoint = Vector2.new(0, 0.5)
DOCK.Input.Text = ""
DOCK.Input.PlaceholderText = "Reason, message, or a number.."
DOCK.Input.ClearTextOnFocus = false
DOCK.Input.Visible = true
DOCK.Input.ZIndex = 10
StyleInput(DOCK.Input)

--[[
	The dock only makes sense while the panel is open, and only on the pages
	that actually take a value. Showing it on the Reports page, which has no
	command that reads it, would just be a box that does nothing.
--]]
DOCK.Pages = {
	Home = "Message / hour",
	Players = "Reason / value",
	Trolling = "Value",
}

function RefreshDock()
	local caption = DOCK.Pages[CurrentPage or ""]
	local wanted = AdminFrame.Visible and caption ~= nil

	InputDock.Visible = wanted
	if wanted then
		DOCK.Label.Text = caption
	end
end

-- Home -------------------------------------------------------------------------
--[[
	A landing page rather than a control panel: what your rank lets you do, a
	count of what is waiting, and the handful of server wide actions that are
	not about one particular player.
--]]

local HomeBody = MakePageBody("Home")

--[[
	The Home page is a plain vertical stack, and the bands are written out here
	rather than scattered across the widgets so the gaps are checkable at a
	glance and cannot silently close up.

	Each entry is {top, height} as a fraction of the page. They are in order and
	must not touch: the input sitting on top of the stat cards was exactly this
	going wrong, with the row heights edited in one place and the offsets in
	another.
--]]
--[[
	The Input band is gone: that field is the input dock now, pinned outside
	the panel. Actions moves up into the space and keeps the same gaps.
--]]
local HOME_BANDS = {
	Blurb = {0.015, 0.150},
	Stats = {0.185, 0.230},
	Actions = {0.450, 0.190},
}

local function HomeBand(element, name)
	local band = HOME_BANDS[name]
	element.Position = UDim2.new(0, 0, band[1], 0)
	element.Size = UDim2.new(1, 0, band[2], 0)
end

local HomeBlurb = HomeBody:FindFirstChild("Blurb")
if not HomeBlurb then
	HomeBlurb = Instance.new("TextLabel")
	HomeBlurb.Name = "Blurb"
	HomeBlurb.Parent = HomeBody
end
HomeBand(HomeBlurb, "Blurb")
HomeBlurb.BackgroundTransparency = 1
HomeBlurb.Text = ""
HomeBlurb.TextScaled = false
HomeBlurb.TextSize = 15
HomeBlurb.TextWrapped = true
HomeBlurb.Font = BODY_FONT
HomeBlurb.TextColor3 = THEME.MutedText
HomeBlurb.TextXAlignment = Enum.TextXAlignment.Left
HomeBlurb.TextYAlignment = Enum.TextYAlignment.Top
HomeBlurb.ZIndex = 4

-- Three counters across the top.
local HomeStats = HomeBody:FindFirstChild("Stats")
if not HomeStats then
	HomeStats = Instance.new("Frame")
	HomeStats.Name = "Stats"
	HomeStats.Parent = HomeBody
end
HomeBand(HomeStats, "Stats")
HomeStats.BackgroundTransparency = 1
HomeStats.ZIndex = 4

do
	local statLayout = HomeStats:FindFirstChildOfClass("UIListLayout")
	if not statLayout then
		statLayout = Instance.new("UIListLayout")
		statLayout.Parent = HomeStats
	end
	statLayout.FillDirection = Enum.FillDirection.Horizontal
	statLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statLayout.Padding = UDim.new(0.025, 0)
end

local StatValues = {}

local function MakeStat(name, caption, order)
	local card = HomeStats:FindFirstChild("S_" .. name)
	if not card then
		card = Instance.new("Frame")
		card.Name = "S_" .. name
		card.Parent = HomeStats
	end
	card.LayoutOrder = order
	card.Size = UDim2.new(0.31, 0, 1, 0)
	card.BackgroundColor3 = THEME.CardBackground
	card.BorderSizePixel = 0
	card.ZIndex = 4
	GetOrMakeCorner(card, CONTROL_CORNER)
	StyleBorder(card, THEME.ShopOutline, 3)

	local value = card:FindFirstChild("Value")
	if not value then
		value = Instance.new("TextLabel")
		value.Name = "Value"
		value.Parent = card
	end
	value.Size = UDim2.new(1, 0, 0.58, 0)
	value.Position = UDim2.new(0, 0, 0.06, 0)
	value.BackgroundTransparency = 1
	value.Text = "0"
	value.TextScaled = true
	value.Font = TITLE_FONT
	value.TextColor3 = THEME.Text
	value.ZIndex = 5

	local label = card:FindFirstChild("Caption")
	if not label then
		label = Instance.new("TextLabel")
		label.Name = "Caption"
		label.Parent = card
	end
	label.Size = UDim2.new(1, 0, 0.28, 0)
	label.Position = UDim2.new(0, 0, 0.64, 0)
	label.BackgroundTransparency = 1
	label.Text = caption
	label.TextScaled = true
	label.Font = BODY_FONT
	label.TextColor3 = THEME.MutedText
	label.ZIndex = 5

	StatValues[name] = value
	return card
end

MakeStat("Players", "In server", 1)
MakeStat("Reports", "Open reports", 2)
MakeStat("Booths", "Booths claimed", 3)

-- Server wide actions, the ones that are not aimed at one person.
local HomeActions = HomeBody:FindFirstChild("Actions")
if not HomeActions then
	HomeActions = Instance.new("Frame")
	HomeActions.Name = "Actions"
	HomeActions.Parent = HomeBody
end
HomeBand(HomeActions, "Actions")
HomeActions.BackgroundTransparency = 1
HomeActions.ZIndex = 4

do
	local actLayout = HomeActions:FindFirstChildOfClass("UIGridLayout")
	if not actLayout then
		actLayout = Instance.new("UIGridLayout")
		actLayout.Parent = HomeActions
	end
	--[[
		Five buttons across one row.

		Four cells of 0.235 plus three gaps of 0.02 comes to exactly 1.000 of
		the width, which is the boundary case a grid wraps on, so the last
		button dropped to a second line and the labels squashed. Sizing for
		five across with the gaps subtracted first leaves the row a little
		short of full and keeps every caption on one line.
	--]]
	local acrossCount = 5
	local acrossPad = 0.015
	local acrossCell = (1 - acrossPad * (acrossCount + 1)) / acrossCount

	actLayout.CellSize = UDim2.new(acrossCell, 0, 0.86, 0)
	actLayout.CellPadding = UDim2.new(acrossPad, 0, 0.08, 0)
	actLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
end

-- The free text box the announce / time buttons read from.
--[[
	No text field here any more. It lived in the panel, scaled with it, and
	became unreadable on a small window; it is now the input dock pinned to the
	top of the screen at a fixed pixel size. The band it used to occupy is
	given back to the action buttons.
--]]

-- Players ----------------------------------------------------------------------
--[[
	The list on the left is everyone in the server; picking someone fills the
	panel on the right with every command that takes a target, drawn straight
	from what the server said this rank is allowed to run.

	Nothing here is hard coded to a command name. The server sends the command
	list, the page draws a button per command, and pressing one sends the
	command's own name back. So a command added on the server shows up here on
	its own, with no matching client edit.
--]]

local PlayersBody = MakePageBody("Players")

local PlayerList = MakeScroller(
	PlayersBody, "PlayerList",
	UDim2.new(0.40, 0, 0.96, 0), UDim2.new(0, 0, 0.02, 0)
)

local PlayerActions = PlayersBody:FindFirstChild("Actions")
if not PlayerActions then
	PlayerActions = Instance.new("Frame")
	PlayerActions.Name = "Actions"
	PlayerActions.Parent = PlayersBody
end
PlayerActions.Size = UDim2.new(0.575, 0, 0.96, 0)
PlayerActions.Position = UDim2.new(0.425, 0, 0.02, 0)
PlayerActions.BackgroundTransparency = 1
PlayerActions.ZIndex = 4

-- Who is selected, shown above the buttons.
local SelectedLabel = PlayerActions:FindFirstChild("Selected")
if not SelectedLabel then
	SelectedLabel = Instance.new("TextLabel")
	SelectedLabel.Name = "Selected"
	SelectedLabel.Parent = PlayerActions
end
SelectedLabel.Size = UDim2.new(1, 0, 0.1, 0)
SelectedLabel.BackgroundTransparency = 1
SelectedLabel.Text = "Pick someone from the list."
SelectedLabel.TextScaled = true
SelectedLabel.Font = TITLE_FONT
SelectedLabel.TextColor3 = THEME.MutedText
SelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
SelectedLabel.ZIndex = 5

-- Shared argument box: reasons, messages, speeds all come from here.
-- The argument field is the input dock now, so the button grid starts higher.

Grids.Action = MakeScroller(
	PlayerActions, "Grid",
	UDim2.new(1, 0, 0.84, 0), UDim2.new(0, 0, 0.14, 0)
)
Grids.Action.BackgroundTransparency = 1
do
	local st = Grids.Action:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 1
	end
	local old = Grids.Action:FindFirstChildOfClass("UIListLayout")
	if old then
		old:Destroy()
	end
	local grid = Grids.Action:FindFirstChildOfClass("UIGridLayout")
	if not grid then
		grid = Instance.new("UIGridLayout")
		grid.Parent = Grids.Action
	end
	grid.CellSize = UDim2.new(0.31, 0, 0, 34)
	grid.CellPadding = UDim2.new(0.025, 0, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
end

local PlayerRows = {}
local PlayerEntries = {}
local SelectedUserId = nil
local CommandDefs = {}
local CommandButtons = {}

local function SelectedEntry()
	if not SelectedUserId then
		return nil
	end
	return PlayerEntries[SelectedUserId]
end

-- Greys out any command whose target the viewer is not allowed to touch, and
-- any command that needs a target when none is picked.
local function RefreshActionButtons()
	local entry = SelectedEntry()

	if entry then
		SelectedLabel.Text = entry.Name .. "  (" .. entry.RankName .. ")"
		SelectedLabel.TextColor3 = RankColour(entry.Rank)
	else
		SelectedLabel.Text = "Pick someone from the list."
		SelectedLabel.TextColor3 = THEME.MutedText
	end

	for name, button in pairs(CommandButtons) do
		local def = CommandDefs[name]
		local usable = true

		if def and def.WantsPlayer then
			usable = (entry ~= nil) and (entry.CanAct == true)
		end

		button.AutoButtonColor = usable
		if usable then
			button.TextTransparency = 0
			button.BackgroundTransparency = 0
		else
			button.TextTransparency = 0.55
			button.BackgroundTransparency = 0.55
		end
	end
end

--[[
	The Players page and the Trolling page show the same people and share one
	selection, so both lists have to highlight together. TrollRows is filled in
	further down; until then it is simply empty and the loop does nothing.
--]]
local TrollRows = {}

local function SelectPlayer(userId)
	SelectedUserId = userId

	for id, row in pairs(PlayerRows) do
		if id == userId then
			row.BackgroundColor3 = THEME.TabActive
		else
			row.BackgroundColor3 = THEME.TabIdle
		end
	end

	for id, row in pairs(TrollRows) do
		if id == userId then
			row.BackgroundColor3 = THEME.TabActive
		else
			row.BackgroundColor3 = THEME.TabIdle
		end
	end

	RefreshActionButtons()
end

local function BuildPlayerRow(entry, order)
	local row = PlayerRows[entry.UserId]
	if not row then
		row = Instance.new("TextButton")
		row.Name = "P_" .. tostring(entry.UserId)
		row.Parent = PlayerList
		row.Text = ""
		row.MouseButton1Click:Connect(function()
			SelectPlayer(entry.UserId)
		end)
		PlayerRows[entry.UserId] = row
	end

	row.LayoutOrder = order
	row.Size = UDim2.new(0.94, 0, 0, 46)
	row.BackgroundColor3 = (SelectedUserId == entry.UserId) and THEME.TabActive or THEME.TabIdle
	row.BorderSizePixel = 0
	row.AutoButtonColor = true
	row.ZIndex = 4
	GetOrMakeCorner(row, CONTROL_CORNER)
	StyleBorder(row, THEME.ShopOutline, 2)

	local head = MakeHeadshot(row, "Head", entry.UserId, entry.Name)
	head.Size = UDim2.new(0, 34, 0, 34)
	head.Position = UDim2.new(0, 6, 0.5, 0)
	head.AnchorPoint = Vector2.new(0, 0.5)

	local nameLabel = row:FindFirstChild("PName")
	if not nameLabel then
		nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "PName"
		nameLabel.Parent = row
	end
	nameLabel.Size = UDim2.new(0.62, 0, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 46, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.Name
	nameLabel.TextScaled = true
	nameLabel.Font = TITLE_FONT
	nameLabel.TextColor3 = THEME.Text
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 5

	-- Second line: rank, booth, and whatever moderation is on them, so the
	-- state of a player is readable without clicking into them.
	local bits = {entry.RankName}
	if entry.Booth then
		bits[#bits + 1] = "Booth " .. tostring(entry.Booth)
	end
	if entry.Muted then
		bits[#bits + 1] = "Muted"
	end
	if entry.Frozen then
		bits[#bits + 1] = "Frozen"
	end
	if entry.God then
		bits[#bits + 1] = "God"
	end
	if entry.Invisible then
		bits[#bits + 1] = "Invisible"
	end

	local sub = row:FindFirstChild("Sub")
	if not sub then
		sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.Parent = row
	end
	sub.Size = UDim2.new(0.72, 0, 0.36, 0)
	sub.Position = UDim2.new(0, 46, 0.55, 0)
	sub.BackgroundTransparency = 1
	sub.Text = table.concat(bits, "  -  ")
	sub.TextScaled = false
	sub.TextSize = 12
	sub.Font = BODY_FONT
	sub.TextColor3 = RankColour(entry.Rank)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 5

	return row
end

-- Reports ----------------------------------------------------------------------
--[[
	The moderation inbox. Each card is one reported booth: who owns it, who
	reported it, why, and what the booth actually said at the time.

	The two buttons are the whole point of the page. "Go To" walks you to the
	booth so you can see it yourself, and "Close" drops the report once it is
	dealt with. Anything harsher happens on the Players page, against the
	owner, so the punishment always goes through the same rank checks.
--]]

local ReportsBody = MakePageBody("Reports")

local ReportList = MakeScroller(
	ReportsBody, "List",
	UDim2.new(1, 0, 0.96, 0), UDim2.new(0, 0, 0.02, 0)
)

local ReportEmpty = ReportsBody:FindFirstChild("Empty")
if not ReportEmpty then
	ReportEmpty = Instance.new("TextLabel")
	ReportEmpty.Name = "Empty"
	ReportEmpty.Parent = ReportsBody
end
ReportEmpty.Size = UDim2.new(0.8, 0, 0.2, 0)
ReportEmpty.Position = UDim2.new(0.5, 0, 0.42, 0)
ReportEmpty.AnchorPoint = Vector2.new(0.5, 0.5)
ReportEmpty.BackgroundTransparency = 1
ReportEmpty.Text = "No open reports. Nice."
ReportEmpty.TextScaled = true
ReportEmpty.Font = BODY_FONT
ReportEmpty.TextColor3 = THEME.MutedText
ReportEmpty.ZIndex = 5

local ReportCards = {}

local function BuildReportCard(entry, order)
	local card = ReportCards[entry.Id]
	if not card then
		card = Instance.new("Frame")
		card.Name = "R_" .. tostring(entry.Id)
		card.Parent = ReportList
		ReportCards[entry.Id] = card
	end

	card.LayoutOrder = order
	card.Size = UDim2.new(0.96, 0, 0, 92)
	card.BackgroundColor3 = THEME.TabIdle
	card.BorderSizePixel = 0
	card.ZIndex = 4
	GetOrMakeCorner(card, CONTROL_CORNER)
	StyleBorder(card, THEME.ShopOutline, 2)

	-- A thumbnail of the reported image, so staff can triage the obvious ones
	-- without walking over to the booth at all.
	local shot = card:FindFirstChild("Shot")
	if not shot then
		shot = Instance.new("ImageLabel")
		shot.Name = "Shot"
		shot.Parent = card
	end
	shot.Size = UDim2.new(0, 74, 0, 74)
	shot.Position = UDim2.new(0, 8, 0.5, 0)
	shot.AnchorPoint = Vector2.new(0, 0.5)
	shot.BackgroundColor3 = THEME.InputBackground
	shot.BorderSizePixel = 0
	shot.ScaleType = Enum.ScaleType.Fit
	shot.Image = entry.Image or ""
	shot.ZIndex = 5
	GetOrMakeCorner(shot, CONTROL_CORNER)
	StyleBorder(shot, THEME.ShopOutline, 2)

	local heading = card:FindFirstChild("Heading")
	if not heading then
		heading = Instance.new("TextLabel")
		heading.Name = "Heading"
		heading.Parent = card
	end
	heading.Size = UDim2.new(0.52, 0, 0, 20)
	heading.Position = UDim2.new(0, 92, 0, 8)
	heading.BackgroundTransparency = 1
	heading.Text = "Booth " .. tostring(entry.Booth) .. "  -  " .. tostring(entry.AgainstName)
	heading.TextScaled = true
	heading.Font = TITLE_FONT
	heading.TextColor3 = THEME.Text
	heading.TextXAlignment = Enum.TextXAlignment.Left
	heading.ZIndex = 5

	local reason = card:FindFirstChild("Reason")
	if not reason then
		reason = Instance.new("TextLabel")
		reason.Name = "Reason"
		reason.Parent = card
	end
	reason.Size = UDim2.new(0.52, 0, 0, 16)
	reason.Position = UDim2.new(0, 92, 0, 30)
	reason.BackgroundTransparency = 1
	reason.Text = tostring(entry.Reason)
	reason.TextScaled = false
	reason.TextSize = 14
	reason.Font = TITLE_FONT
	reason.TextColor3 = THEME.ReportText
	reason.TextXAlignment = Enum.TextXAlignment.Left
	reason.ZIndex = 5

	-- Everything else on one wrapped line: the reporter, their note, and the
	-- booth's own caption as it was when the report went in.
	local detail = card:FindFirstChild("Detail")
	if not detail then
		detail = Instance.new("TextLabel")
		detail.Name = "Detail"
		detail.Parent = card
	end
	detail.Size = UDim2.new(0.53, 0, 0, 38)
	detail.Position = UDim2.new(0, 92, 0, 48)
	detail.BackgroundTransparency = 1

	local pieces = {"by " .. tostring(entry.ByName)}
	if not entry.Online then
		pieces[#pieces + 1] = "owner has left"
	end
	if entry.Note and entry.Note ~= "" then
		pieces[#pieces + 1] = "\"" .. entry.Note .. "\""
	end
	if entry.Text and entry.Text ~= "" then
		pieces[#pieces + 1] = "booth says: " .. entry.Text
	end

	detail.Text = table.concat(pieces, "  -  ")
	detail.TextScaled = false
	detail.TextSize = 12
	detail.TextWrapped = true
	detail.Font = BODY_FONT
	detail.TextColor3 = THEME.MutedText
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextYAlignment = Enum.TextYAlignment.Top
	detail.ZIndex = 5

	local goTo = MakeSmallButton(card, "Goto", "Go To", THEME.ButtonBackground, THEME.Text)
	goTo.Size = UDim2.new(0, 78, 0, 28)
	goTo.Position = UDim2.new(1, -8, 0, 12)
	goTo.AnchorPoint = Vector2.new(1, 0)
	if not Wired[goTo] then
		Wired[goTo] = true
		goTo.MouseButton1Click:Connect(function()
			RemoteEvent:FireServer("AdminGotoReport", entry.Booth)
		end)
	end

	local close = MakeSmallButton(card, "Close", "Close", THEME.BuyBackground, THEME.BuyText)
	close.Size = UDim2.new(0, 78, 0, 28)
	close.Position = UDim2.new(1, -8, 0, 50)
	close.AnchorPoint = Vector2.new(1, 0)
	if not Wired[close] then
		Wired[close] = true
		close.MouseButton1Click:Connect(function()
			RemoteEvent:FireServer("AdminResolveReport", entry.Id)
		end)
	end

	return card
end

-- Staff ------------------------------------------------------------------------
--[[
	The whitelist. Admin and up only.

	Promoting someone already in the server is done from the Players page, so
	this page is aimed at the other case: whitelisting by UserId, for someone
	who is not online. The ID is the number out of a profile URL, which is why
	the box says so.

	Owners are drawn greyed out with a padlock note, because they come from the
	script and no button here can change them.
--]]

local StaffBody = MakePageBody("Staff")

local StaffList = MakeScroller(
	StaffBody, "List",
	UDim2.new(0.52, 0, 0.96, 0), UDim2.new(0, 0, 0.02, 0)
)

local StaffSide = StaffBody:FindFirstChild("Side")
if not StaffSide then
	StaffSide = Instance.new("Frame")
	StaffSide.Name = "Side"
	StaffSide.Parent = StaffBody
end
StaffSide.Size = UDim2.new(0.45, 0, 0.96, 0)
StaffSide.Position = UDim2.new(0.55, 0, 0.02, 0)
StaffSide.BackgroundTransparency = 1
StaffSide.ZIndex = 4

do
	local AddTitle = StaffSide:FindFirstChild("AddTitle")
	if not AddTitle then
		AddTitle = Instance.new("TextLabel")
		AddTitle.Name = "AddTitle"
		AddTitle.Parent = StaffSide
	end
	AddTitle.Size = UDim2.new(1, 0, 0.09, 0)
	AddTitle.BackgroundTransparency = 1
	AddTitle.Text = "Whitelist by UserId"
	AddTitle.TextScaled = true
	AddTitle.Font = TITLE_FONT
	AddTitle.TextColor3 = THEME.Text
	AddTitle.TextXAlignment = Enum.TextXAlignment.Left
	AddTitle.ZIndex = 5
end

do
	local AddHint = StaffSide:FindFirstChild("AddHint")
	if not AddHint then
		AddHint = Instance.new("TextLabel")
		AddHint.Name = "AddHint"
		AddHint.Parent = StaffSide
	end
	AddHint.Size = UDim2.new(1, 0, 0.12, 0)
	AddHint.Position = UDim2.new(0, 0, 0.10, 0)
	AddHint.BackgroundTransparency = 1
	AddHint.Text = "The number in their profile URL. Works whether or not they are in the server."
	AddHint.TextScaled = false
	AddHint.TextSize = 12
	AddHint.TextWrapped = true
	AddHint.Font = BODY_FONT
	AddHint.TextColor3 = THEME.MutedText
	AddHint.TextXAlignment = Enum.TextXAlignment.Left
	AddHint.TextYAlignment = Enum.TextYAlignment.Top
	AddHint.ZIndex = 5
end

local StaffIdBox = StaffSide:FindFirstChild("IdBox")
if not StaffIdBox then
	StaffIdBox = TextBox:Clone()
	StaffIdBox.Name = "IdBox"
	StaffIdBox.Parent = StaffSide
end
StaffIdBox.Size = UDim2.new(1, 0, 0.11, 0)
StaffIdBox.Position = UDim2.new(0, 0, 0.24, 0)
StaffIdBox.Text = ""
StaffIdBox.PlaceholderText = "UserId, e.g. 49603"
StaffIdBox.ClearTextOnFocus = false
StaffIdBox.Visible = true
StaffIdBox.ZIndex = 5
StyleInput(StaffIdBox)

local StaffNameBox = StaffSide:FindFirstChild("NameBox")
if not StaffNameBox then
	StaffNameBox = TextBox:Clone()
	StaffNameBox.Name = "NameBox"
	StaffNameBox.Parent = StaffSide
end
StaffNameBox.Size = UDim2.new(1, 0, 0.11, 0)
StaffNameBox.Position = UDim2.new(0, 0, 0.37, 0)
StaffNameBox.Text = ""
StaffNameBox.PlaceholderText = "Name, for the list only"
StaffNameBox.ClearTextOnFocus = false
StaffNameBox.Visible = true
StaffNameBox.ZIndex = 5
StyleInput(StaffNameBox)

--[[
	The three whitelist buttons. Built and wired in one pass, partly to keep
	them together and partly because this file sits close to Lua's 200 local
	ceiling and three more names at the top level is three it cannot spare.
	SubmitRank is declared below and captured by the handlers.
--]]
local StaffRankButtons = {
	{"MakeMod", "Add as Mod", THEME.ButtonBackground, THEME.ModBadge,
		UDim2.new(0.48, 0, 0.11, 0), UDim2.new(0, 0, 0.50, 0), RANK.Mod},
	{"MakeAdmin", "Add as Admin", THEME.ButtonBackground, THEME.AdminBadge,
		UDim2.new(0.48, 0, 0.11, 0), UDim2.new(0.52, 0, 0.50, 0), RANK.Admin},
	{"RemoveStaff", "Remove from staff", THEME.DangerBackground, THEME.DangerText,
		UDim2.new(1, 0, 0.11, 0), UDim2.new(0, 0, 0.63, 0), 0},
}

do
	local BanTitle = StaffSide:FindFirstChild("BanTitle")
	if not BanTitle then
		BanTitle = Instance.new("TextLabel")
		BanTitle.Name = "BanTitle"
		BanTitle.Parent = StaffSide
	end
	BanTitle.Size = UDim2.new(1, 0, 0.10, 0)
	BanTitle.Position = UDim2.new(0, 0, 0.755, 0)
	BanTitle.BackgroundTransparency = 1
	BanTitle.Text = "Bans"
	BanTitle.TextScaled = true
	BanTitle.Font = TITLE_FONT
	BanTitle.TextColor3 = THEME.Text
	BanTitle.TextXAlignment = Enum.TextXAlignment.Left
	BanTitle.ZIndex = 5
end

local BanList = MakeScroller(
	StaffSide, "BanList",
	UDim2.new(1, 0, 0.14, 0), UDim2.new(0, 0, 0.86, 0)
)

local StaffRows = {}
local BanRows = {}

local function BuildStaffRow(entry, order)
	local row = StaffRows[entry.UserId]
	if not row then
		row = Instance.new("Frame")
		row.Name = "S_" .. tostring(entry.UserId)
		row.Parent = StaffList
		StaffRows[entry.UserId] = row
	end

	row.LayoutOrder = order
	row.Size = UDim2.new(0.94, 0, 0, 44)
	row.BackgroundColor3 = THEME.TabIdle
	row.BorderSizePixel = 0
	row.ZIndex = 4
	GetOrMakeCorner(row, CONTROL_CORNER)
	StyleBorder(row, THEME.ShopOutline, 2)

	local head = MakeHeadshot(row, "Head", entry.UserId, entry.Name)
	head.Size = UDim2.new(0, 32, 0, 32)
	head.Position = UDim2.new(0, 6, 0.5, 0)
	head.AnchorPoint = Vector2.new(0, 0.5)

	local nameLabel = row:FindFirstChild("SName")
	if not nameLabel then
		nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "SName"
		nameLabel.Parent = row
	end
	nameLabel.Size = UDim2.new(0.5, 0, 0.5, 0)
	nameLabel.Position = UDim2.new(0, 44, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(entry.Name)
	nameLabel.TextScaled = true
	nameLabel.Font = TITLE_FONT
	nameLabel.TextColor3 = THEME.Text
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 5

	local sub = row:FindFirstChild("Sub")
	if not sub then
		sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.Parent = row
	end
	sub.Size = UDim2.new(0.62, 0, 0.36, 0)
	sub.Position = UDim2.new(0, 44, 0.55, 0)
	sub.BackgroundTransparency = 1

	local note = entry.RankName .. "  -  " .. tostring(entry.UserId)
	if entry.Locked then
		note = note .. "  -  set in script"
	elseif entry.By then
		note = note .. "  -  by " .. tostring(entry.By)
	end

	sub.Text = note
	sub.TextScaled = false
	sub.TextSize = 12
	sub.Font = BODY_FONT
	sub.TextColor3 = RankColour(entry.Rank)
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 5

	-- One-tap demote, only for rows this viewer could actually change.
	local drop = row:FindFirstChild("Drop")
	local canDrop = (not entry.Locked) and (entry.Rank < MyRank or MyRank >= RANK.Owner)

	if canDrop then
		drop = MakeSmallButton(row, "Drop", "Remove", THEME.DangerBackground, THEME.DangerText)
		drop.Size = UDim2.new(0, 72, 0, 26)
		drop.Position = UDim2.new(1, -8, 0.5, 0)
		drop.AnchorPoint = Vector2.new(1, 0.5)
		if not Wired[drop] then
			Wired[drop] = true
			drop.MouseButton1Click:Connect(function()
				RemoteEvent:FireServer("AdminSetRank", {
					UserId = entry.UserId,
					Rank = 0,
					Name = entry.Name,
				})
			end)
		end
	elseif drop then
		drop.Visible = false
	end

	return row
end

local function BuildBanRow(entry, order)
	local row = BanRows[entry.UserId]
	if not row then
		row = Instance.new("TextButton")
		row.Name = "B_" .. tostring(entry.UserId)
		row.Parent = BanList
		BanRows[entry.UserId] = row
		row.MouseButton1Click:Connect(function()
			-- Fills the box so the unban is one more tap.
			StaffIdBox.Text = tostring(entry.UserId)
			StaffNameBox.Text = tostring(entry.Name)
			SetAdminStatus("Loaded " .. tostring(entry.Name) .. ". Use Unban on the Players page.", false)
		end)
	end

	row.LayoutOrder = order
	row.Size = UDim2.new(0.94, 0, 0, 22)
	row.Text = tostring(entry.Name) .. "  -  " .. tostring(entry.Reason)
	row.TextScaled = false
	row.TextSize = 12
	row.Font = BODY_FONT
	row.BackgroundColor3 = THEME.TabIdle
	row.TextColor3 = THEME.DangerText
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.BorderSizePixel = 0
	row.ZIndex = 5
	GetOrMakeCorner(row, CONTROL_CORNER)

	return row
end

-- Reads the two boxes and asks the server for a rank change.
local function SubmitRank(rank)
	local id = tonumber(string.match(StaffIdBox.Text, "%d+") or "")
	if not id then
		SetAdminStatus("Put a UserId in first.", true)
		return
	end
	RemoteEvent:FireServer("AdminSetRank", {
		UserId = id,
		Rank = rank,
		Name = StaffNameBox.Text,
	})
end

for _, spec in ipairs(StaffRankButtons) do
	local button = MakeSmallButton(StaffSide, spec[1], spec[2], spec[3], spec[4])
	button.Size = spec[5]
	button.Position = spec[6]
	button.MouseButton1Click:Connect(function()
		SubmitRank(spec[7])
	end)
end

-- Trolling ---------------------------------------------------------------------
--[[
	The same shape as the Players page, on purpose: pick somebody on the left,
	press a thing on the right.

	It shares the Players page's selection rather than keeping its own, so
	whoever you had highlighted is still highlighted when you tab over, and
	there is only ever one "who is selected" to reason about.

	Every button here is reversible and none of them can end somebody's
	session. Cleanup puts a person fully back to normal, and the disco stops on
	its own so it cannot be left running by someone who logs off.
--]]

local TrollBody = MakePageBody("Trolling")

local TrollList = MakeScroller(
	TrollBody, "TrollList",
	UDim2.new(0.40, 0, 0.96, 0), UDim2.new(0, 0, 0.02, 0)
)

local TrollSide = TrollBody:FindFirstChild("Side")
if not TrollSide then
	TrollSide = Instance.new("Frame")
	TrollSide.Name = "Side"
	TrollSide.Parent = TrollBody
end
TrollSide.Size = UDim2.new(0.575, 0, 0.96, 0)
TrollSide.Position = UDim2.new(0.425, 0, 0.02, 0)
TrollSide.BackgroundTransparency = 1
TrollSide.ZIndex = 4

do
	local TrollNote = TrollSide:FindFirstChild("Note")
	if not TrollNote then
		TrollNote = Instance.new("TextLabel")
		TrollNote.Name = "Note"
		TrollNote.Parent = TrollSide
	end
	TrollNote.Size = UDim2.new(1, 0, 0.11, 0)
	TrollNote.BackgroundTransparency = 1
	TrollNote.Text = "Pick someone on the left. Cleanup undoes all of it."
	TrollNote.TextScaled = false
	TrollNote.TextSize = 13
	TrollNote.TextWrapped = true
	TrollNote.Font = BODY_FONT
	TrollNote.TextColor3 = THEME.MutedText
	TrollNote.TextXAlignment = Enum.TextXAlignment.Left
	TrollNote.ZIndex = 5
end

Grids.Troll = MakeScroller(
	TrollSide, "Grid",
	UDim2.new(1, 0, 0.87, 0), UDim2.new(0, 0, 0.13, 0)
)
Grids.Troll.BackgroundTransparency = 1
do
	local st = Grids.Troll:FindFirstChildOfClass("UIStroke")
	if st then
		st.Transparency = 1
	end
	local old = Grids.Troll:FindFirstChildOfClass("UIListLayout")
	if old then
		old:Destroy()
	end
	local grid = Grids.Troll:FindFirstChildOfClass("UIGridLayout")
	if not grid then
		grid = Instance.new("UIGridLayout")
		grid.Parent = Grids.Troll
	end
	grid.CellSize = UDim2.new(0.31, 0, 0, 34)
	grid.CellPadding = UDim2.new(0.025, 0, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
end

-- Rows here mirror the Players page. TrollRows itself is declared up with
-- SelectPlayer, which needs it to highlight both lists at once.
local function BuildTrollRow(entry, order)
	local row = TrollRows[entry.UserId]
	if not row then
		row = Instance.new("TextButton")
		row.Name = "T_" .. tostring(entry.UserId)
		row.Parent = TrollList
		row.Text = ""
		row.MouseButton1Click:Connect(function()
			SelectPlayer(entry.UserId)
		end)
		TrollRows[entry.UserId] = row
	end

	row.LayoutOrder = order
	row.Size = UDim2.new(0.94, 0, 0, 40)
	row.BackgroundColor3 = (SelectedUserId == entry.UserId) and THEME.TabActive or THEME.TabIdle
	row.BorderSizePixel = 0
	row.AutoButtonColor = true
	row.ZIndex = 4
	GetOrMakeCorner(row, CONTROL_CORNER)
	StyleBorder(row, THEME.ShopOutline, 2)

	local head = MakeHeadshot(row, "Head", entry.UserId, entry.Name)
	head.Size = UDim2.new(0, 30, 0, 30)
	head.Position = UDim2.new(0, 6, 0.5, 0)
	head.AnchorPoint = Vector2.new(0, 0.5)

	local nameLabel = row:FindFirstChild("TName")
	if not nameLabel then
		nameLabel = Instance.new("TextLabel")
		nameLabel.Name = "TName"
		nameLabel.Parent = row
	end
	nameLabel.Size = UDim2.new(0.7, 0, 0.7, 0)
	nameLabel.Position = UDim2.new(0, 42, 0.15, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = entry.Name
	nameLabel.TextScaled = true
	nameLabel.Font = TITLE_FONT
	nameLabel.TextColor3 = RankColour(entry.Rank)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 5

	return row
end

-- Shop -------------------------------------------------------------------------
--[[
	The gamepass editor. This is what the whole panel used to be, moved onto a
	page of its own and otherwise left alone, so anyone who already knew it
	still knows it.

	Left column lists every pass, right column edits the selected one. Built in
	passes keep their key and asset ID locked, because UPLOAD, PERMANENT and
	BOOMBOX are wired into the booth logic by name.
--]]

local ShopBody = MakePageBody("Shop")

local AdminList = MakeScroller(
	ShopBody, "AdminList",
	UDim2.new(0.36, 0, 0.85, 0), UDim2.new(0, 0, 0.02, 0)
)

local NewButton = MakeSmallButton(ShopBody, "NewPass", "+ New Gamepass",
	THEME.BuyBackground, THEME.BuyText)
NewButton.Size = UDim2.new(0.36, 0, 0.1, 0)
NewButton.Position = UDim2.new(0, 0, 0.89, 0)

local Editor = ShopBody:FindFirstChild("Editor")
if not Editor then
	Editor = Instance.new("Frame")
	Editor.Name = "Editor"
	Editor.Parent = ShopBody
end
Editor.Size = UDim2.new(0.60, 0, 0.97, 0)
Editor.Position = UDim2.new(0.40, 0, 0.02, 0)
Editor.BackgroundTransparency = 1
Editor.ZIndex = 4

do
	local editorLayout = Editor:FindFirstChildOfClass("UIListLayout")
	if not editorLayout then
		editorLayout = Instance.new("UIListLayout")
		editorLayout.Parent = Editor
	end
	editorLayout.SortOrder = Enum.SortOrder.LayoutOrder
	editorLayout.Padding = UDim.new(0, 5)
end

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
	holder.Size = UDim2.new(1, 0, 0.105, 0)
	holder.ZIndex = 4

	local cap = holder:FindFirstChild("Cap")
	if not cap then
		cap = Instance.new("TextLabel")
		cap.Name = "Cap"
		cap.Parent = holder
	end
	cap.Size = UDim2.new(0.26, 0, 1, 0)
	cap.BackgroundTransparency = 1
	cap.Text = label
	-- Fixed size for the same reason as the box beside it: TextScaled on a
	-- short row makes the caption taller than the field it labels.
	cap.TextScaled = false
	cap.TextSize = INPUT_TEXT_SIZE
	cap.Font = BODY_FONT
	cap.TextColor3 = THEME.MutedText
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.ZIndex = 5

	local box = holder:FindFirstChild("Box")
	if not box then
		box = Instance.new("TextBox")
		box.Name = "Box"
		box.Parent = holder
	end
	box.Size = UDim2.new(0.72, 0, 0.82, 0)
	box.Position = UDim2.new(0.28, 0, 0.09, 0)
	box.Text = ""
	box.PlaceholderText = placeholder or ""
	box.ClearTextOnFocus = false
	box.ZIndex = 5

	-- Through StyleInput rather than styled by hand, so these fields match
	-- every other input. Doing it by hand here is how they ended up as the
	-- only boxes still carrying TextScaled.
	StyleInput(box)

	AdminFields[name] = box
	return box
end

MakeField("Key", "Key", 1, "SPEED_PASS")
MakeField("Title", "Name", 2, "Speed Boost")
MakeField("Id", "Asset ID", 3, "356360")
MakeField("Price", "Price", 4, "Gamepass")
MakeField("Icon", "Icon ID", 5, "rbxassetid:// or blank")
MakeField("Blurb", "Blurb", 6, "What it does")
MakeField("Category", "Category", 7, "Passes")

local Buttons = Editor:FindFirstChild("Buttons")
if not Buttons then
	Buttons = Instance.new("Frame")
	Buttons.Name = "Buttons"
	Buttons.BackgroundTransparency = 1
	Buttons.Parent = Editor
end
Buttons.LayoutOrder = 9
Buttons.Size = UDim2.new(1, 0, 0.12, 0)
Buttons.ZIndex = 4

local SaveButton = MakeSmallButton(Buttons, "Save", "Save",
	THEME.BuyBackground, THEME.BuyText)
SaveButton.Size = UDim2.new(0.48, 0, 1, 0)

local DeleteButton = MakeSmallButton(Buttons, "Delete", "Delete",
	THEME.DangerBackground, THEME.DangerText)
DeleteButton.Size = UDim2.new(0.48, 0, 1, 0)
DeleteButton.Position = UDim2.new(0.52, 0, 0, 0)

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
	row.ZIndex = 5
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

-------------------------------------------------------------------------------
-- Command buttons
-------------------------------------------------------------------------------
--[[
	Built from whatever the server said this rank can run, so the page is
	always exactly the command set the player actually has. A command that
	takes no target sits on the same grid as the rest and simply ignores the
	selection.
--]]

local function BuildCommandButtons(list)
	CommandDefs = {}
	CommandButtons = CommandButtons or {}

	local seen = {}

	for i, def in ipairs(list) do
		local wantsPlayer = false
		local wantsValue = false
		if type(def.Args) == "table" then
			for _, a in pairs(def.Args) do
				if a == "player" then
					wantsPlayer = true
				elseif a == "text" or a == "number" then
					wantsValue = true
				end
			end
		end

		def.WantsPlayer = wantsPlayer and not def.Raw
		def.WantsValue = wantsValue
		CommandDefs[def.Name] = def
		seen[def.Name] = true

		-- Troll commands live on their own page, so a mis-click on the
		-- moderation page cannot set somebody on fire instead of warning them.
		local host = def.Troll and Grids.Troll or Grids.Action

		local button = CommandButtons[def.Name]
		if not button then
			button = Instance.new("TextButton")
			button.Name = "C_" .. def.Name
			button.Parent = host
			CommandButtons[def.Name] = button

			button.MouseButton1Click:Connect(function()
				local d = CommandDefs[def.Name]
				if not d then
					return
				end

				local target = nil
				if d.WantsPlayer then
					local entry = SelectedEntry()
					if not entry then
						SetAdminStatus("Pick someone from the list first.", true)
						return
					end
					if not entry.CanAct then
						SetAdminStatus("You cannot use that on " .. entry.Name .. ".", true)
						return
					end
					target = entry.UserId
				end

				-- Raw commands read the free text box even with nobody picked,
				-- which is what makes /announce and /time work from the GUI.
				-- One field for every page now, so no choosing between two.
				local value = DOCK.Input.Text
				if value == "" and d.Default then
					value = d.Default
				end

				RemoteEvent:FireServer("AdminCommand", {
					Name = d.Name,
					Target = target,
					Value = value,
				})
				SetAdminStatus("Sending /" .. d.Name .. "..", false)
			end)
		end

		button.LayoutOrder = i
		button.Text = def.Label or def.Name
		button.TextScaled = true
		button.Font = TITLE_FONT
		button.BorderSizePixel = 0
		button.ZIndex = 5
		button.Visible = true
		GetOrMakeCorner(button, CONTROL_CORNER)

		if def.Danger then
			button.BackgroundColor3 = THEME.DangerBackground
			button.TextColor3 = THEME.DangerText
		elseif def.Troll then
			button.BackgroundColor3 = THEME.AdminBackground
			button.TextColor3 = THEME.AdminText
		else
			button.BackgroundColor3 = THEME.ButtonBackground
			button.TextColor3 = THEME.Text
		end
		StyleBorder(button, THEME.ShopOutline, 2)
	end

	-- A demotion can take commands away, so anything no longer sent is hidden.
	for name, button in pairs(CommandButtons) do
		if not seen[name] then
			button.Visible = false
		end
	end

	RefreshActionButtons()
end

-- The Home page's server wide buttons are the same commands, just laid out
-- separately so they are not buried under the per player ones.
local HomeButtons = {}

local function BuildHomeButtons()
	local wanted = {"announce", "time", "lock", "unlock", "resetbooths"}

	for i, name in ipairs(wanted) do
		local def = CommandDefs[name]
		local button = HomeButtons[name]

		if def then
			if not button then
				button = Instance.new("TextButton")
				button.Name = "H_" .. name
				button.Parent = HomeActions
				HomeButtons[name] = button

				button.MouseButton1Click:Connect(function()
					local d = CommandDefs[name]
					if not d then
						return
					end
					local value = DOCK.Input.Text
					if value == "" and d.Default then
						value = d.Default
					end
					RemoteEvent:FireServer("AdminCommand", {
						Name = name,
						Target = nil,
						Value = value,
					})
					SetAdminStatus("Sending /" .. name .. "..", false)
				end)
			end

			button.LayoutOrder = i
			button.Text = def.Label or name
			button.TextScaled = true
			button.Font = TITLE_FONT
			button.BorderSizePixel = 0
			button.ZIndex = 5
			button.Visible = true
			GetOrMakeCorner(button, CONTROL_CORNER)

			if def.Danger then
				button.BackgroundColor3 = THEME.DangerBackground
				button.TextColor3 = THEME.DangerText
			else
				button.BackgroundColor3 = THEME.ButtonBackground
				button.TextColor3 = THEME.Text
			end
			StyleBorder(button, THEME.ShopOutline, 2)

		elseif button then
			button.Visible = false
		end
	end
end


-------------------------------------------------------------------------------
-- Opening and closing
-------------------------------------------------------------------------------

local function SetPanelOpen(open)
	if open and not IsAdminClient then
		return
	end

	AdminFrame.Visible = open
	HUD.Show(not open)
	RefreshDock()

	if open then
		-- Everything is refetched on open, so a panel left shut for an hour
		-- never shows a stale queue.
		RemoteEvent:FireServer("AdminOpen")
		SelectPage(CurrentPage or "Home")
	end
end

AdminButton.MouseButton1Click:Connect(function()
	SetPanelOpen(not AdminFrame.Visible)
end)

AdminClose.MouseButton1Click:Connect(function()
	SetPanelOpen(false)
end)

-------------------------------------------------------------------------------
-- Reporting a booth
-------------------------------------------------------------------------------
--[[
	The player side of the report system, and the only part of it everyone
	sees. Same look as the shop, deliberately: pick a booth, pick a reason,
	add a note if you want, send.

	Reasons are a fixed list rather than free text so staff get something they
	can triage at a glance, and so a report cannot itself be used to put abuse
	in front of a moderator. The optional note is filtered on the server like
	any other player text.
--]]

-- Cloned for the same reason as AdminButton: it inherits the TextLabel that
-- makes every button in the stack render alike.
local ReportButton = ScreenGui:FindFirstChild("ReportButton")
if not ReportButton then
	ReportButton = ToggleButton:Clone()
	ReportButton.Name = "ReportButton"
	ReportButton.Parent = ScreenGui
end
PlaceHudButton(ReportButton, 3)

-- No resize handler needed for the stack: the positions are expressed in the
-- same scale-plus-offset terms as the sizes, so they follow the window on
-- their own. HUD.Placed is still kept, for hiding the stack as a group.
SetCaption(ReportButton, "Report")
ReportButton.TextScaled = true
ReportButton.Font = TITLE_FONT
ReportButton.BackgroundColor3 = THEME.ReportBackground
StyleCaption(ReportButton, THEME.ReportText)
ReportButton.BorderSizePixel = 0
ReportButton.Visible = true
GetOrMakeCorner(ReportButton, SHOP_CORNER)
StyleBorder(ReportButton, THEME.ShopOutline, 4)
AddSheen(ReportButton)

local ReportFrame = ScreenGui:FindFirstChild("ReportFrame")
if not ReportFrame then
	ReportFrame = Instance.new("Frame")
	ReportFrame.Name = "ReportFrame"
	ReportFrame.Parent = ScreenGui
end
ReportFrame.Visible = false
ReportFrame.Size = UDim2.new(0.50, 0, 0.52, 0)
ReportFrame.Position = UDim2.new(0.5, 0, 0.5, 0)

-- Same floor-and-ceiling as the admin panel; FitWindowsToScreen sets both.
-- Registering the frame itself is what switches the resize handler on for it.
SizeLimits.Report = ReportFrame

-- Both windows are known about now, so apply the caps and keep following the
-- window: it can be resized mid-session and a cap worked out once at startup
-- would be wrong the moment somebody drags the edge.
FitWindowsToScreen()
ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(FitWindowsToScreen)
ReportFrame.AnchorPoint = Vector2.new(0.5, 0.5)
ReportFrame.BackgroundColor3 = THEME.PanelBackground
ReportFrame.BorderSizePixel = 0
ReportFrame.ZIndex = 2
GetOrMakeCorner(ReportFrame, SHOP_CORNER)
StyleBorder(ReportFrame, THEME.ShopOutline, 4)
AddSheen(ReportFrame)

do
	local ReportTitle = ReportFrame:FindFirstChild("Title")
	if not ReportTitle then
		ReportTitle = Instance.new("TextLabel")
		ReportTitle.Name = "Title"
		ReportTitle.Parent = ReportFrame
	end
	ReportTitle.Size = UDim2.new(1, 0, 0.15, 0)
	ReportTitle.Position = UDim2.new(0.5, 0, -0.015, 0)
	ReportTitle.AnchorPoint = Vector2.new(0.5, 1)
	ReportTitle.BackgroundTransparency = 1
	ReportTitle.Text = "Report a Booth"
	ReportTitle.TextScaled = true
	ReportTitle.Font = TITLE_FONT
	ReportTitle.TextColor3 = THEME.Text
	ReportTitle.ZIndex = 3

	local st = ReportTitle:FindFirstChildOfClass("UIStroke")
	if not st then
		st = Instance.new("UIStroke")
		st.Parent = ReportTitle
	end
	st.Color = THEME.ShopOutline
	st.Thickness = 4
end

local ReportClose = ReportFrame:FindFirstChild("Close")
if not ReportClose then
	ReportClose = Instance.new("TextButton")
	ReportClose.Name = "Close"
	ReportClose.Parent = ReportFrame
end
ReportClose.Size = UDim2.new(0.065, 0, 0.095, 0)
ReportClose.Position = UDim2.new(1, 0, 0, 0)
ReportClose.AnchorPoint = Vector2.new(0.5, 0.5)
ReportClose.Text = "X"
ReportClose.TextScaled = true
ReportClose.Font = TITLE_FONT
ReportClose.BackgroundColor3 = THEME.DangerBackground
ReportClose.TextColor3 = THEME.DangerText
ReportClose.BorderSizePixel = 0
ReportClose.ZIndex = 6
GetOrMakeCorner(ReportClose, UDim.new(1, 0))
StyleBorder(ReportClose, THEME.ShopOutline, 3)

-- Which booth ---------------------------------------------------------------

local BoothPick = MakeScroller(
	ReportFrame, "BoothPick",
	UDim2.new(0.44, 0, 0.62, 0), UDim2.new(0.035, 0, 0.06, 0)
)

do
	local BoothPickTitle = ReportFrame:FindFirstChild("PickTitle")
	if not BoothPickTitle then
		BoothPickTitle = Instance.new("TextLabel")
		BoothPickTitle.Name = "PickTitle"
		BoothPickTitle.Parent = ReportFrame
	end
	BoothPickTitle.Size = UDim2.new(0.44, 0, 0.08, 0)
	BoothPickTitle.Position = UDim2.new(0.035, 0, 0.70, 0)
	BoothPickTitle.BackgroundTransparency = 1
	BoothPickTitle.Text = "Pick a booth"
	BoothPickTitle.TextScaled = true
	BoothPickTitle.Font = BODY_FONT
	BoothPickTitle.TextColor3 = THEME.MutedText
	BoothPickTitle.ZIndex = 3
end

-- Why -----------------------------------------------------------------------

local ReasonPick = MakeScroller(
	ReportFrame, "ReasonPick",
	UDim2.new(0.46, 0, 0.44, 0), UDim2.new(0.505, 0, 0.06, 0)
)

local ReportNote = ReportFrame:FindFirstChild("Note")
if not ReportNote then
	ReportNote = TextBox:Clone()
	ReportNote.Name = "Note"
	ReportNote.Parent = ReportFrame
end
ReportNote.Size = UDim2.new(0.46, 0, 0.11, 0)
ReportNote.Position = UDim2.new(0.505, 0, 0.53, 0)
ReportNote.Text = ""
ReportNote.PlaceholderText = "Anything to add? (optional)"
ReportNote.ClearTextOnFocus = false
ReportNote.Visible = true
ReportNote.ZIndex = 3
StyleInput(ReportNote)

-- The one input that is a free-text note rather than a single-line field, so
-- it wraps and sits top-aligned instead of truncating.
ReportNote.TextWrapped = true
ReportNote.TextTruncate = Enum.TextTruncate.None
ReportNote.TextYAlignment = Enum.TextYAlignment.Top
ReportNote.MultiLine = true

local SendReport = MakeSmallButton(ReportFrame, "Send", "Send Report",
	THEME.ReportBackground, THEME.ReportText)
SendReport.Size = UDim2.new(0.46, 0, 0.12, 0)
SendReport.Position = UDim2.new(0.505, 0, 0.66, 0)
StyleBorder(SendReport, THEME.ShopOutline, 3)

local ReportStatus = ReportFrame:FindFirstChild("Status")
if not ReportStatus then
	ReportStatus = Instance.new("TextLabel")
	ReportStatus.Name = "Status"
	ReportStatus.Parent = ReportFrame
end
ReportStatus.Size = UDim2.new(0.93, 0, 0.09, 0)
ReportStatus.Position = UDim2.new(0.5, 0, 0.87, 0)
ReportStatus.AnchorPoint = Vector2.new(0.5, 0.5)
ReportStatus.BackgroundTransparency = 1
ReportStatus.Text = ""
ReportStatus.TextScaled = true
ReportStatus.Font = BODY_FONT
ReportStatus.TextColor3 = THEME.MutedText
ReportStatus.ZIndex = 3

--[[
	The report window's own state, kept in one table.

	Grouped rather than four separate locals because this file runs close to
	Lua's 200 local ceiling, and these are always read and written together
	anyway, so a single name is no harder to follow.
--]]
local Picker = {
	BoothRows = {},
	ReasonRows = {},
	Booth = nil,
	Reason = nil,
}

local function SetReportStatus(msg, bad)
	ReportStatus.Text = msg or ""
	if bad then
		ReportStatus.TextColor3 = THEME.Bad
	else
		ReportStatus.TextColor3 = THEME.Good
	end
end

local function RefreshPicks()
	for booth, row in pairs(Picker.BoothRows) do
		row.BackgroundColor3 = (booth == Picker.Booth) and THEME.TabActive or THEME.TabIdle
	end
	for reason, row in pairs(Picker.ReasonRows) do
		row.BackgroundColor3 = (reason == Picker.Reason) and THEME.TabActive or THEME.TabIdle
	end
end

local function BuildBoothRow(entry, order)
	local row = Picker.BoothRows[entry.Booth]
	if not row then
		row = Instance.new("TextButton")
		row.Name = "RB_" .. tostring(entry.Booth)
		row.Parent = BoothPick
		Picker.BoothRows[entry.Booth] = row
		row.MouseButton1Click:Connect(function()
			Picker.Booth = entry.Booth
			RefreshPicks()
		end)
	end

	row.LayoutOrder = order
	row.Size = UDim2.new(0.92, 0, 0, 34)
	row.Text = tostring(entry.OwnerName) .. "  (booth " .. tostring(entry.Booth) .. ")"
	row.TextScaled = false
	row.TextSize = 13
	row.Font = BODY_FONT
	row.BackgroundColor3 = THEME.TabIdle
	row.TextColor3 = THEME.Text
	row.BorderSizePixel = 0
	row.ZIndex = 4
	GetOrMakeCorner(row, CONTROL_CORNER)
	StyleBorder(row, THEME.ShopOutline, 2)
	return row
end

local function BuildReasonRow(reason, order)
	local row = Picker.ReasonRows[reason]
	if not row then
		row = Instance.new("TextButton")
		row.Name = "RR_" .. tostring(order)
		row.Parent = ReasonPick
		Picker.ReasonRows[reason] = row
		row.MouseButton1Click:Connect(function()
			Picker.Reason = reason
			RefreshPicks()
		end)
	end

	row.LayoutOrder = order
	row.Size = UDim2.new(0.92, 0, 0, 28)
	row.Text = reason
	row.TextScaled = false
	row.TextSize = 13
	row.Font = BODY_FONT
	row.BackgroundColor3 = THEME.TabIdle
	row.TextColor3 = THEME.Text
	row.BorderSizePixel = 0
	row.ZIndex = 4
	GetOrMakeCorner(row, CONTROL_CORNER)
	StyleBorder(row, THEME.ShopOutline, 2)
	return row
end

ReportButton.MouseButton1Click:Connect(function()
	ReportFrame.Visible = not ReportFrame.Visible
	HUD.Show(not ReportFrame.Visible)
	if ReportFrame.Visible then
		SetReportStatus("")
		RemoteEvent:FireServer("ReportOpen")
	end
end)

ReportClose.MouseButton1Click:Connect(function()
	ReportFrame.Visible = false
	HUD.Show(true)
end)

SendReport.MouseButton1Click:Connect(function()
	if not Picker.Booth then
		SetReportStatus("Pick which booth first.", true)
		return
	end
	if not Picker.Reason then
		SetReportStatus("Pick a reason.", true)
		return
	end

	RemoteEvent:FireServer("ReportBooth", {
		Booth = Picker.Booth,
		Reason = Picker.Reason,
		Note = ReportNote.Text,
	})
	SetReportStatus("Sending..", false)
end)

-------------------------------------------------------------------------------
-- Toasts
-------------------------------------------------------------------------------
--[[
	One banner across the top, shared by announcements, warnings, and the
	nudge staff get when a report comes in. Each one replaces the last rather
	than stacking, so a spammed announce cannot bury the screen.
--]]

local Toast = ScreenGui:FindFirstChild("Toast")
if not Toast then
	Toast = Instance.new("TextLabel")
	Toast.Name = "Toast"
	Toast.Parent = ScreenGui
end
Toast.Size = UDim2.new(0.58, 0, 0.075, 0)
Toast.Position = UDim2.new(0.5, 0, 0.08, 0)
Toast.AnchorPoint = Vector2.new(0.5, 0.5)
Toast.BackgroundColor3 = THEME.PanelBackground
Toast.BorderSizePixel = 0
Toast.Text = ""
Toast.TextScaled = true
Toast.Font = TITLE_FONT
Toast.TextColor3 = THEME.Text
Toast.Visible = false
Toast.ZIndex = 10
GetOrMakeCorner(Toast, SHOP_CORNER)
StyleBorder(Toast, THEME.ShopOutline, 4)
AddSheen(Toast)

local ToastToken = 0

local function ShowToast(message, colour, seconds)
	ToastToken = ToastToken + 1
	local mine = ToastToken

	Toast.Text = message
	Toast.TextColor3 = colour or THEME.Text
	Toast.Visible = true

	delay(seconds or 7, function()
		if ToastToken == mine then
			Toast.Visible = false
		end
	end)
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

RemoteEvent.OnClientEvent:Connect(function(Argument, Argument2, Argument3, Argument4)
	if not Argument then
		return
	end

	if Argument == "Start" then
		HUD.Allowed[ToggleButton] = false
		HUD.Refresh()
		Frame.Visible = false
		UpdateButtonText()

	elseif Argument == "OpenGui" then
		HUD.Allowed[ToggleButton] = true
		HUD.Refresh()
		Frame.Visible = true
		UpdateButtonText()
		SetStatus("Booth claimed.", false)

	elseif Argument == "BoothUnclaimed" then
		HUD.Allowed[ToggleButton] = false
		HUD.Refresh()
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
				-- FIX: normalize the category directly on the entry, not just
				-- in a local variable used for the tab list. Without this,
				-- entries sent without a Category field stay nil, so
				-- RefreshGrid's "entry.Category == CurrentTab" check never
				-- matches and every gamepass card stays hidden.
				entry.Category = entry.Category or "Passes"

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
		-- Argument2 = allowed, Argument3 = rank number, Argument4 = rank name.
		IsAdminClient = (Argument2 == true)
		MyRank = tonumber(Argument3) or 0
		MyRankName = Argument4 or "Player"

		HUD.Allowed[AdminButton] = IsAdminClient
		HUD.Refresh()
		SetGreeting(Player.Name, MyRankName, MyRank)
		BuildNav()

		if not IsAdminClient then
			AdminFrame.Visible = false
		end

	elseif Argument == "AdminClose" then
		HUD.Show(true)
		InputDock.Visible = false
		-- Sent when someone is demoted while they have the panel open.
		IsAdminClient = false
		MyRank = 0
		HUD.Allowed[AdminButton] = false
		AdminButton.Visible = false
		AdminFrame.Visible = false

	elseif Argument == "AdminHeadshot" then
		-- Argument2 = userId, Argument3 = url. Arrives whenever the proxy
		-- answers, which may be well after the row was drawn.
		local userId = tonumber(Argument2)
		if userId and type(Argument3) == "string" and Argument3 ~= "" then
			Headshots[userId] = Argument3

			if userId == Player.UserId then
				ApplyGreetHeadshot(Argument3)
			end

			-- Patch any row already on screen for that user.
			local row = PlayerRows[userId]
			if row then
				local img = row:FindFirstChild("Head")
				if img then
					img.Image = Argument3
					local initial = img:FindFirstChild("Initial")
					if initial then
						initial.Visible = false
					end
				end
			end

			local srow = StaffRows[userId]
			if srow then
				local img = srow:FindFirstChild("Head")
				if img then
					img.Image = Argument3
					local initial = img:FindFirstChild("Initial")
					if initial then
						initial.Visible = false
					end
				end
			end
		end

	elseif Argument == "AdminCommands" then
		if type(Argument2) == "table" then
			BuildCommandButtons(Argument2)
			BuildHomeButtons()
		end

	elseif Argument == "AdminPlayers" then
		if type(Argument2) == "table" then
			local seen = {}
			local claimed = 0

			for i, entry in ipairs(Argument2) do
				if entry.Headshot then
					Headshots[entry.UserId] = entry.Headshot
				end
				PlayerEntries[entry.UserId] = entry
				BuildPlayerRow(entry, i)
				BuildTrollRow(entry, i)
				seen[entry.UserId] = true
				if entry.Booth then
					claimed = claimed + 1
				end
			end

			-- Drop rows for anyone who has left.
			for userId, row in pairs(PlayerRows) do
				if not seen[userId] then
					row:Destroy()
					PlayerRows[userId] = nil
					PlayerEntries[userId] = nil
					if SelectedUserId == userId then
						SelectedUserId = nil
					end
				end
			end

			for userId, row in pairs(TrollRows) do
				if not seen[userId] then
					row:Destroy()
					TrollRows[userId] = nil
				end
			end

			StatValues.Players.Text = tostring(#Argument2)
			StatValues.Booths.Text = tostring(claimed)

			if Argument3 == true then
				HomeBlurb.Text = "You are " .. MyRankName
					.. ". The server is LOCKED to staff. Type /help in chat, or use the pages on the left."
			else
				HomeBlurb.Text = "You are " .. MyRankName
					.. ". Every button here has a chat command with the same name, so /kick and the Kick button do the same thing."
			end

			RefreshActionButtons()
		end

	elseif Argument == "AdminReports" then
		if type(Argument2) == "table" then
			local seen = {}
			for i, entry in ipairs(Argument2) do
				BuildReportCard(entry, i)
				seen[entry.Id] = true
			end

			for id, card in pairs(ReportCards) do
				if not seen[id] then
					card:Destroy()
					ReportCards[id] = nil
				end
			end

			ReportEmpty.Visible = (#Argument2 == 0)
			StatValues.Reports.Text = tostring(#Argument2)
		end

	elseif Argument == "AdminStaff" then
		if type(Argument2) == "table" then
			local seen = {}
			for i, entry in ipairs(Argument2) do
				BuildStaffRow(entry, i)
				seen[entry.UserId] = true
			end
			for userId, row in pairs(StaffRows) do
				if not seen[userId] then
					row:Destroy()
					StaffRows[userId] = nil
				end
			end
		end

		if type(Argument3) == "table" then
			local seenBan = {}
			for i, entry in ipairs(Argument3) do
				BuildBanRow(entry, i)
				seenBan[entry.UserId] = true
			end
			for userId, row in pairs(BanRows) do
				if not seenBan[userId] then
					row:Destroy()
					BanRows[userId] = nil
				end
			end
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

	elseif Argument == "AdminLog" then
		-- Another staff member did something. Only worth a line in the panel.
		SetAdminStatus(Argument2 or "", false)

	elseif Argument == "Announce" then
		ShowToast(tostring(Argument2) .. ": " .. tostring(Argument3), THEME.Text, 8)

	elseif Argument == "AdminWarn" then
		ShowToast("Warning from " .. tostring(Argument2) .. ": " .. tostring(Argument3),
			THEME.Bad, 10)

	elseif Argument == "Muted" then
		if Argument2 == true then
			ShowToast("You have been muted by a moderator.", THEME.Bad, 8)
		else
			ShowToast("You can talk again.", THEME.Good, 5)
		end

	elseif Argument == "ReportTargets" then
		if type(Argument2) == "table" then
			local seen = {}
			for i, entry in ipairs(Argument2) do
				BuildBoothRow(entry, i)
				seen[entry.Booth] = true
			end
			for booth, row in pairs(Picker.BoothRows) do
				if not seen[booth] then
					row:Destroy()
					Picker.BoothRows[booth] = nil
					if Picker.Booth == booth then
						Picker.Booth = nil
					end
				end
			end

			if #Argument2 == 0 then
				-- Argument4 is how many booths are claimed in total, including
				-- this player's own. Without it "nothing to report" reads as
				-- "nothing is claimed", which is wrong and confusing when the
				-- one claimed booth is yours.
				if (tonumber(Argument4) or 0) > 0 then
					SetReportStatus("The only claimed booth is yours. You cannot report yourself.", false)
				else
					SetReportStatus("Nobody has claimed a booth yet, so there is nothing to report.", false)
				end
			else
				SetReportStatus("")
			end
		end

		if type(Argument3) == "table" then
			for i, reason in ipairs(Argument3) do
				BuildReasonRow(reason, i)
			end
		end

		RefreshPicks()

	elseif Argument == "ReportOk" then
		SetReportStatus(Argument2 or "Sent.", false)
		Picker.Booth = nil
		Picker.Reason = nil
		ReportNote.Text = ""
		RefreshPicks()

	elseif Argument == "ReportError" then
		SetReportStatus(Argument2 or "That did not work.", true)
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
	HUD.Show(not ShopFrame.Visible)
	if ShopFrame.Visible then
		RemoteEvent:FireServer("CheckPasses")
	end
end)

ShopClose.MouseButton1Click:Connect(function()
	ShopFrame.Visible = false
	HUD.Show(true)
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
ReportFrame.Visible = false
Toast.Visible = false
BoomPanel.Visible = false
LoadIntoEditor(nil)
HUD.Allowed[ToggleButton] = false
ToggleButton.Visible = false
SetStatus("")
UpdateButtonText()
ApplyPassState()

-- The panel is built for everyone but only ever shown to staff, so the very
-- first thing it needs is a rank. Until the server answers AdminAccess the
-- button stays hidden and every page stays empty.
SetGreeting(Player.Name, "Player", 0)
BuildNav()
SelectPage("Home")
AdminFrame.Visible = false

-- The client's own headshot is a good enough placeholder while the proxy is
-- waking up, and covers the case where HTTP is off entirely.
LocalHeadshot(Player.UserId, function(content)
	if GreetImage.Image == "" then
		ApplyGreetHeadshot(content)
	end
end)

RemoteEvent:FireServer("CheckPasses")

local OwnedBooth = Player:FindFirstChild("OwnedBooth")
if OwnedBooth and OwnedBooth.Value then
	HUD.Allowed[ToggleButton] = true
	ToggleButton.Visible = true
end

-- Original booth system by ywinfe and thugshaker