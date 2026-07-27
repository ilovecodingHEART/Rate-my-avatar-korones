--[[============================================================================
  REPLACE MAP BOOTHS WITH boothgood
  Paste this whole thing into the Studio Command Bar and press Enter.

  What it does
    1. Finds every old map booth (the Model named "Booth" made of
       Pole / Banner / Tabletop / Carpet / Table).
    2. Drops a copy of the boothgood template in the same spot, facing the
       same way, sitting on the same ground.
    3. Deletes the old booth.
    4. Puts every new booth in Workspace.Booths, which is the folder the
       booth server script expects.

  Before running
    * Insert boothgood.rbxm into the place (anywhere: Workspace,
      ServerStorage, ReplicatedStorage...). The script hunts for it.
    * Have the map in Workspace.

  Read the output first: DRY_RUN is ON, so nothing is changed until you
  set it to false.
============================================================================]]

--==[ CONFIG ]================================================================

local DRY_RUN = true -- true = only print a report, change nothing

local TEMPLATE_NAME = nil -- nil = auto-detect. Or force it, e.g. "boothgood"
local FOLDER_NAME = "Booths" -- new booths are collected here
local DELETE_OLD = true -- false = keep old booths (moved to a backup folder)
local BACKUP_FOLDER = "OldBooths_Backup"

-- The old Banner shows its GUI on the Front face; boothgood's Display uses the
-- Back face. Those are opposite directions, so the copy has to be spun 180
-- degrees or every booth ends up facing backwards. If yours come out
-- back-to-front, flip this.
local FLIP_180 = true

-- Nudge every booth if it sits slightly high or low / too far forward.
local HEIGHT_OFFSET = 0
local FORWARD_OFFSET = 0

--==[ HELPERS ]===============================================================

local Workspace = game:GetService("Workspace")
local Selection = game:GetService("Selection")

local function isOldBooth(inst)
	if not inst:IsA("Model") then
		return false
	end
	-- Old booths have a Banner; the new ones have Display + BoothOwner.
	if not inst:FindFirstChild("Banner") then
		return false
	end
	if inst:FindFirstChild("Display") and inst.Display:FindFirstChild("BoothOwner") then
		return false
	end
	return true
end

local function isNewBooth(inst)
	if not inst:IsA("Model") then
		return false
	end
	local display = inst:FindFirstChild("Display")
	if not display then
		return false
	end
	return display:FindFirstChild("BoothOwner") ~= nil
		and display:FindFirstChild("SurfaceGui") ~= nil
end

-- Manual bounding box: works on every Studio version and does not need a
-- PrimaryPart (the map booths have none, so :SetPrimaryPartCFrame would error).
local function getBounds(model)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false

	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			found = true
			local cf, size = part.CFrame, part.Size
			local sx, sy, sz = size.X / 2, size.Y / 2, size.Z / 2
			local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:components()
			-- Half-extents of a rotated box projected onto the world axes.
			local ex = math.abs(r00) * sx + math.abs(r01) * sy + math.abs(r02) * sz
			local ey = math.abs(r10) * sx + math.abs(r11) * sy + math.abs(r12) * sz
			local ez = math.abs(r20) * sx + math.abs(r21) * sy + math.abs(r22) * sz
			if x - ex < minX then minX = x - ex end
			if y - ey < minY then minY = y - ey end
			if z - ez < minZ then minZ = z - ez end
			if x + ex > maxX then maxX = x + ex end
			if y + ey > maxY then maxY = y + ey end
			if z + ez > maxZ then maxZ = z + ez end
		end
	end

	if not found then
		return nil
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

-- Move a whole model by a transform, without needing a PrimaryPart.
local function transformModel(model, transform)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CFrame = transform * part.CFrame
		end
	end
end

local function horizontalLook(cf)
	local lv = cf.LookVector
	local flat = Vector3.new(lv.X, 0, lv.Z)
	if flat.Magnitude < 0.001 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

--==[ FIND THE TEMPLATE ]=====================================================

local function findTemplate()
	if TEMPLATE_NAME then
		for _, d in ipairs(game:GetDescendants()) do
			if d.Name == TEMPLATE_NAME and isNewBooth(d) then
				return d
			end
		end
		return nil, "No booth model named '" .. TEMPLATE_NAME .. "' found."
	end

	local candidates = {}
	for _, where in ipairs({
		game:GetService("ServerStorage"),
		game:GetService("ReplicatedStorage"),
		game:GetService("Lighting"),
		Workspace,
	}) do
		for _, d in ipairs(where:GetDescendants()) do
			if isNewBooth(d) then
				table.insert(candidates, d)
			end
		end
	end

	if #candidates == 0 then
		return nil, "Could not find the boothgood template. Insert boothgood.rbxm first."
	end
	return candidates[1]
end

--==[ RUN ]===================================================================

local template, err = findTemplate()
if not template then
	warn("[Booths] " .. err)
	return
end

-- Collect the old booths BEFORE touching anything.
local oldBooths = {}
for _, d in ipairs(Workspace:GetDescendants()) do
	if isOldBooth(d) then
		table.insert(oldBooths, d)
	end
end

print("========================================")
print("[Booths] template : " .. template:GetFullName())
print("[Booths] old booths found : " .. #oldBooths)
print("[Booths] DRY_RUN : " .. tostring(DRY_RUN))
print("========================================")

if #oldBooths == 0 then
	warn("[Booths] Nothing to replace. Is the map in Workspace?")
	return
end

-- Template measurements, taken once.
local tDisplay = template:FindFirstChild("Display")
if not tDisplay then
	warn("[Booths] The template has no Display part.")
	return
end

local tMin = select(1, getBounds(template))
if not tMin then
	warn("[Booths] The template has no parts.")
	return
end
local templateDisplayRise = tDisplay.Position.Y - tMin.Y

local folder = Workspace:FindFirstChild(FOLDER_NAME)
local backup = DELETE_OLD and nil or Workspace:FindFirstChild(BACKUP_FOLDER)

if not DRY_RUN then
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = Workspace
	end
	if not DELETE_OLD and not backup then
		backup = Instance.new("Folder")
		backup.Name = BACKUP_FOLDER
		backup.Parent = Workspace
	end
end

local made = {}
local skipped = 0

for index, old in ipairs(oldBooths) do
	local banner = old:FindFirstChild("Banner")
	local oldMin = select(1, getBounds(old))

	if not banner or not oldMin then
		warn(string.format("[Booths] #%d skipped: no Banner or no parts.", index))
		skipped = skipped + 1
	else
		-- Where the old booth displayed, and which way it looked.
		local outward = horizontalLook(banner.CFrame)
		local facing = FLIP_180 and -outward or outward

		local targetPos = Vector3.new(
			banner.Position.X,
			oldMin.Y + templateDisplayRise + HEIGHT_OFFSET,
			banner.Position.Z
		) + outward * FORWARD_OFFSET

		local wantDisplayCF = CFrame.new(targetPos, targetPos + facing)

		print(string.format(
			"[Booths] #%2d  %s  ->  pos(%.1f, %.1f, %.1f)  facing(%.2f, %.2f)",
			index, old:GetFullName(),
			targetPos.X, targetPos.Y, targetPos.Z, outward.X, outward.Z))

		if not DRY_RUN then
			local copy = template:Clone()
			copy.Name = "Booth"

			-- Align the copy's Display onto the target, then move every part
			-- by that same transform. No PrimaryPart needed.
			local copyDisplay = copy:FindFirstChild("Display")
			local transform = wantDisplayCF * copyDisplay.CFrame:Inverse()
			transformModel(copy, transform)

			copy.Parent = folder
			table.insert(made, copy)

			if DELETE_OLD then
				old:Destroy()
			else
				old.Parent = backup
			end
		end
	end
end

print("========================================")
if DRY_RUN then
	print(string.format("[Booths] DRY RUN: would replace %d booth(s), skip %d.",
		#oldBooths - skipped, skipped))
	print("[Booths] Set DRY_RUN = false at the top, then run it again.")
else
	print(string.format("[Booths] Replaced %d booth(s), skipped %d.", #made, skipped))
	print("[Booths] New booths live in Workspace." .. FOLDER_NAME)
	if not DELETE_OLD then
		print("[Booths] Old booths kept in Workspace." .. BACKUP_FOLDER)
	end
	print("[Booths] Check them, then Ctrl+Z undoes the whole run if it looks wrong.")
	pcall(function()
		Selection:Set(made)
	end)
end

-- The template itself must not be left inside the Booths folder, or the server
-- script would treat it as a real booth.
if not DRY_RUN and template.Parent == folder then
	warn("[Booths] The template was inside " .. FOLDER_NAME .. "; move it out.")
end
print("========================================")
