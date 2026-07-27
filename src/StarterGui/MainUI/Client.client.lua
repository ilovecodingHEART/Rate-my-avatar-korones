--[[
	Booth client script  (StarterGui.MainUI.Client)

	Original booth system by ywinfe and thugshaker.
	Pekora avatar + image-ID integration.

	This script drives the existing menu (TextBox / ChangeText / UnclaimBooth)
	AND builds the new image controls at run time by cloning the widgets that
	are already in MainUI, so nothing has to be added by hand in Studio and the
	new buttons keep the same corners, strokes and font as the old ones.

	Created at run time inside MainUI.Frame:
	    ImageBox      TextBox     "Enter Image / Decal ID.."
	    ChangeImage   TextButton  "Set Image"
	    ResetImage    TextButton  "Use My Pekora Avatar"
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
-- Configuration
-------------------------------------------------------------------------------

local STATUS_TIME = 4 -- seconds a status message stays on screen
local GOOD_COLOR = Color3.fromRGB(120, 255, 140)
local BAD_COLOR = Color3.fromRGB(255, 120, 120)
local IDLE_COLOR = Color3.fromRGB(235, 235, 235)

-- Row heights (scale of the Frame) so seven rows fit inside it.
local LAYOUT = {
	{Name = "TextLabel", Order = 1, Height = 0.14, Width = 1.00},
	{Name = "TextBox", Order = 2, Height = 0.16, Width = 0.888},
	{Name = "ChangeText", Order = 3, Height = 0.11, Width = 0.515},
	{Name = "ImageBox", Order = 4, Height = 0.16, Width = 0.888},
	{Name = "ChangeImage", Order = 5, Height = 0.11, Width = 0.515},
	{Name = "ResetImage", Order = 6, Height = 0.10, Width = 0.60},
	{Name = "Status", Order = 7, Height = 0.08, Width = 0.90},
	{Name = "UnclaimBooth", Order = 8, Height = 0.10, Width = 0.40},
}

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
	Label.TextColor3 = IDLE_COLOR
	Label.Visible = true
	Label.Parent = Frame
	return Label
end

local ImageBox = CloneTextBox("ImageBox", "Enter Image / Decal ID..")
local ChangeImage = CloneButton("ChangeImage", "Set Image")
local ResetImage = CloneButton("ResetImage", "Use My Pekora Avatar")
local Status = BuildStatus()

-- Apply the row sizes and the vertical order.
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
	ListLayout.Padding = UDim.new(0.02, 0)
	ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	ListLayout.VerticalAlignment = Enum.VerticalAlignment.Top
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
		Status.TextColor3 = IDLE_COLOR
	elseif IsError then
		Status.TextColor3 = BAD_COLOR
	else
		Status.TextColor3 = GOOD_COLOR
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
		SetStatus("Booth claimed. Loading your Pekora avatar..")

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

ResetImage.MouseButton1Click:Connect(function()
	ImageBox.Text = ""
	RemoteEvent:FireServer("ResetImage")
	SetStatus("Reloading your Pekora avatar..")
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
