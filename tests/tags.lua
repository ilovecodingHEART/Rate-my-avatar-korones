--[[
	Staff tags, the trolling commands, and the report-window message that sent
	the user looking for a bug that was not there.

	Loaded by tests/all.lua, which owns the runner.
--]]

return function(test, ok, eq)

-------------------------------------------------------------------------------
-- Staff tags
-------------------------------------------------------------------------------

local function tagOf(player)
	local char = player.Character
	if not char then
		return nil
	end
	local head = char:FindFirstChild("Head")
	if not head then
		return nil
	end
	local gui = head:FindFirstChild("StaffTag")
	if not gui then
		return nil
	end
	return gui:FindFirstChild("Label")
end

test("staff get a label above their head", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()

	local label = tagOf(owner)
	ok(label ~= nil, "the owner has a tag")
	eq(label.Text, "Owner", "and it says Owner")
end)

test("each rank gets its own label", function(H)
	local dev = H.addPlayer("qzc", 78857)
	H.drain()

	local label = tagOf(dev)
	ok(label ~= nil, "the developer has a tag")
	eq(label.Text, "Developer", "reading Developer")

	-- A promoted Admin gets their own wording, not the Developer one.
	H.asPlayer(dev, "AdminSetRank", {UserId = 1001, Rank = 2, Name = "alice"})
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	eq(tagOf(alice).Text, "Admin", "and an admin reads Admin")
end)

test("the four ranks all have different tag colours", function(H)
	-- A tag nobody can tell apart is not much of a tag.
	local owner = H.addPlayer("thugshaker", 49603)
	local dev = H.addPlayer("qzc", 78857)
	H.drain()

	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 2, Name = "alice"})
	H.asPlayer(owner, "AdminSetRank", {UserId = 1002, Rank = 1, Name = "bob"})
	local admin = H.addPlayer("alice", 1001)
	local mod = H.addPlayer("bob", 1002)
	H.drain()

	local seen = {}
	for _, p in ipairs({owner, dev, admin, mod}) do
		local c = tagOf(p).TextColor3
		local key = tostring(c.R) .. "," .. tostring(c.G) .. "," .. tostring(c.B)
		ok(seen[key] == nil, "colour for " .. tagOf(p).Text .. " is not a duplicate")
		seen[key] = true
	end
end)

test("ordinary players get no label", function(H)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	eq(tagOf(alice), nil, "no tag on a normal player")
end)

test("the label comes back after a respawn", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	ok(tagOf(owner) ~= nil, "tagged on join")

	owner:LoadCharacter()
	H.drain()

	local label = tagOf(owner)
	ok(label ~= nil, "still tagged after respawning")
	eq(label.Text, "Owner", "with the right rank")
end)

test("a promotion adds the label straight away", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	eq(tagOf(alice), nil, "alice starts with no tag")

	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})
	H.drain()

	local label = tagOf(alice)
	ok(label ~= nil, "she is tagged without rejoining")
	eq(label.Text, "Mod", "as a Mod")
end)

test("a demotion takes the label away again", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local alice = H.addPlayer("alice", 1001)
	H.drain()
	ok(tagOf(alice) ~= nil, "tagged while a mod")

	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 0, Name = "alice"})
	H.drain()

	eq(tagOf(alice), nil, "tag removed on demotion")
end)

test("the staff tag clears the AFK label", function(H)
	--[[
		The place has a separate AFK system that parents its own BillboardGui
		to the Head at 2.5 studs. Both survive because the names differ, but at
		the same height they render through each other. This pins the clearance
		so the two cannot be pushed back on top of one another.
	--]]
	local AFK_OFFSET = 2.5

	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()

	local gui = owner.Character.Head:FindFirstChild("StaffTag")
	ok(gui ~= nil, "the tag exists")
	ok(gui.StudsOffset.Y >= AFK_OFFSET + 0.5,
		"it sits clear of the AFK label at " .. tostring(AFK_OFFSET) .. " studs")
end)

test("the tag does not draw through walls", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()

	local head = owner.Character:FindFirstChild("Head")
	local gui = head:FindFirstChild("StaffTag")

	-- AlwaysOnTop would put every staff name through the whole map.
	eq(gui.AlwaysOnTop, false, "hidden behind geometry like a normal nameplate")
	ok(gui.MaxDistance <= 100, "and fades out at a sensible distance")
end)

-------------------------------------------------------------------------------
-- Trolling
-------------------------------------------------------------------------------

test("trolling is admin and up, not mods", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local mod = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	H.drain()
	H.clearSent()

	H.asPlayer(mod, "AdminCommand", {Name = "fling", Target = bob.UserId})
	local err = H.lastSent(mod, "AdminError")
	ok(err ~= nil, "a mod is refused")

	-- And the buttons are never even offered to them.
	H.clearSent()
	H.asPlayer(mod, "AdminOpen")
	local list = H.lastSent(mod, "AdminCommands")[2]
	local sawTroll = false
	for _, def in ipairs(list) do
		if def.Troll then
			sawTroll = true
		end
	end
	ok(not sawTroll, "and sees no troll commands at all")
end)

test("an admin does get the troll commands", function(H)
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.clearSent()

	H.asPlayer(admin, "AdminOpen")
	local list = H.lastSent(admin, "AdminCommands")[2]

	local names = {}
	for _, def in ipairs(list) do
		if def.Troll then
			names[def.Name] = true
		end
	end

	ok(names.fling, "fling is offered")
	ok(names.spin, "spin is offered")
	ok(names.cleanup, "and so is cleanup")
end)

test("fling throws them upwards", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "fling", Target = alice.UserId})

	local v = alice.Character.HumanoidRootPart.Velocity
	ok(v ~= nil and v.Y > 0, "she went up rather than nowhere")
end)

test("spin attaches something that cleanup removes", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "spin", Target = alice.UserId})
	local root = alice.Character.HumanoidRootPart
	ok(root:FindFirstChild("TrollSpin") ~= nil, "spinning")

	H.asPlayer(owner, "AdminCommand", {Name = "cleanup", Target = alice.UserId})
	eq(root:FindFirstChild("TrollSpin"), nil, "and cleanup stopped it")
end)

test("fire and sparkles land on the character and come off again", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "fire", Target = alice.UserId})
	H.asPlayer(owner, "AdminCommand", {Name = "sparkle", Target = alice.UserId})

	local torso = alice.Character:FindFirstChild("HumanoidRootPart")
	ok(torso:FindFirstChild("TrollFire") ~= nil, "on fire")
	ok(torso:FindFirstChild("TrollSparkles") ~= nil, "and sparkling")

	H.asPlayer(owner, "AdminCommand", {Name = "cleanup", Target = alice.UserId})
	eq(torso:FindFirstChild("TrollFire"), nil, "fire gone")
	eq(torso:FindFirstChild("TrollSparkles"), nil, "sparkles gone")
end)

test("the explosion cannot actually hurt anyone", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "explode", Target = alice.UserId})

	local boom = nil
	for _, thing in ipairs(H.Workspace:GetChildren()) do
		if thing.ClassName == "Explosion" then
			boom = thing
		end
	end

	ok(boom ~= nil, "there was an explosion")
	eq(boom.BlastPressure, 0, "with no pressure, so it does no damage")
	eq(boom.DestroyJointRadiusPercent, 0, "and cannot dismember anyone")
	eq(alice.Character.Humanoid.Health, 100, "she is unhurt")
end)

test("ghost makes them see-through, cleanup puts them back", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "ghost", Target = alice.UserId})
	ok(alice.Character.Head.Transparency > 0, "see-through")

	H.asPlayer(owner, "AdminCommand", {Name = "cleanup", Target = alice.UserId})
	eq(alice.Character.Head.Transparency, 0, "solid again")
end)

test("cleanup leaves a moderation invisibility alone", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	-- Invisible is a moderation state, not a prank, so a troll cleanup must
	-- not quietly undo it and put a hidden mod back on screen.
	H.asPlayer(owner, "AdminCommand", {Name = "invisible", Target = alice.UserId})
	H.asPlayer(owner, "AdminCommand", {Name = "cleanup", Target = alice.UserId})

	eq(alice.Character.Head.Transparency, 1, "still invisible")
end)

test("jail builds a cage and cleanup removes it", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "jail", Target = alice.UserId})

	local cage = H.Workspace:FindFirstChild("TrollJail")
	ok(cage ~= nil, "a cage appeared")
	ok(#cage:GetChildren() >= 5, "with walls and a lid")

	H.asPlayer(owner, "AdminCommand", {Name = "cleanup", Target = alice.UserId})
	eq(H.Workspace:FindFirstChild("TrollJail"), nil, "and it is gone")
end)

test("troll effects are cleared when the target leaves", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "jail", Target = alice.UserId})
	ok(H.Workspace:FindFirstChild("TrollJail") ~= nil, "jailed")

	H.removePlayer(alice)
	eq(H.Workspace:FindFirstChild("TrollJail"), nil, "cage removed when she left")
end)

test("the disco stops on its own", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "disco"})
	H.clearSent()

	-- Starting it twice should be refused while it is already running.
	H.asPlayer(owner, "AdminCommand", {Name = "disco"})
	ok(H.lastSent(owner, "AdminError") ~= nil, "cannot start a second one")

	-- Draining the scheduled work runs the loop to completion.
	H.drain(400)
	H.clearSent()
	H.asPlayer(owner, "AdminCommand", {Name = "disco"})
	ok(H.lastSent(owner, "AdminError") == nil, "and it can be started again after")
end)

test("troll commands are logged like everything else", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local other = H.addPlayer("qzc", 78857)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {Name = "fling", Target = alice.UserId})

	local logged = H.lastSent(other, "AdminLog")
	ok(logged ~= nil, "the other staff member was told")
	ok(string.find(tostring(logged[2]), "fling") ~= nil, "and it names the command")
end)

test("nobody can troll someone who outranks them", function(H)
	local admin = H.addPlayer("qzc", 78857)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(admin, "AdminCommand", {Name = "fling", Target = owner.UserId})

	local err = H.lastSent(admin, "AdminError")
	ok(err ~= nil, "refused")
	local v = owner.Character.HumanoidRootPart.Velocity
	ok(v == nil or v.Y == 0, "and the owner did not move")
end)

-------------------------------------------------------------------------------
-- The report window's empty message
-------------------------------------------------------------------------------

test("the report list says how many booths are claimed", function(H)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	-- Alone, with her own booth claimed: nothing to report, but something IS
	-- claimed. Saying "no claimed booths" here is what looked like a bug.
	H.booths:GetChildren()[1].Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.clearSent()
	H.asPlayer(alice, "ReportOpen")
	local msg = H.lastSent(alice, "ReportTargets")

	eq(#msg[2], 0, "nothing she may report")
	eq(msg[4], 1, "but the count says one booth is claimed")
end)

test("the count is zero when nothing is claimed at all", function(H)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(alice, "ReportOpen")
	local msg = H.lastSent(alice, "ReportTargets")

	eq(#msg[2], 0, "nothing to report")
	eq(msg[4], 0, "and nothing is claimed")
end)

test("someone else's booth is offered normally", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	H.drain()

	local all = H.booths:GetChildren()
	all[1].Display.Attachment.ProximityPrompt.Triggered:Fire(alice)
	all[2].Display.Attachment.ProximityPrompt.Triggered:Fire(bob)

	H.clearSent()
	H.asPlayer(alice, "ReportOpen")
	local msg = H.lastSent(alice, "ReportTargets")

	eq(#msg[2], 1, "bob's booth is offered")
	eq(msg[2][1].OwnerName, "bob", "and it is his")
	eq(msg[4], 2, "with both counted as claimed")
end)

test("the client explains an empty list correctly", function(H)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.booths:GetChildren()[1].Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.runClient(alice)
	local gui = H.clientGui

	H.findIn(gui, "ReportButton").MouseButton1Click:Fire()
	H.drain()

	-- Scoped to the report window: the booth menu has a "Status" too.
	local status = H.findIn(H.findIn(gui, "ReportFrame"), "Status")
	ok(string.find(status.Text, "yours") ~= nil,
		"it says the only booth is hers, not that none are claimed")
end)

test("the client says something different when nothing is claimed", function(H)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.runClient(alice)

	local gui = H.clientGui
	H.findIn(gui, "ReportButton").MouseButton1Click:Fire()
	H.drain()

	local status = H.findIn(H.findIn(gui, "ReportFrame"), "Status")
	ok(string.find(status.Text, "Nobody has claimed") ~= nil,
		"it says nobody has claimed one")
end)

-------------------------------------------------------------------------------
-- The HUD stack
-------------------------------------------------------------------------------

test("the HUD buttons never overlap each other", function(H)
	--[[
		The buttons are sized by scale with a UISizeConstraint floor, and
		stacked by the drawn height. An earlier attempt used math.max on the
		UDim2 offset, which ADDS rather than flooring, so each button grew past
		the gap between them. This checks the real spacing.
	--]]
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local gui = H.clientGui
	local names = {"TextButton", "ShopButton", "AdminButton", "ReportButton"}
	local seen = {}

	for _, name in ipairs(names) do
		local b = H.findIn(gui, name)
		ok(b ~= nil, name .. " exists")
		if b then
			seen[#seen + 1] = {Name = name, Y = b.Position.Y.Offset, H = b.Size.Y.Offset}
		end
	end

	-- Offsets are negative going up the screen, so sort and compare gaps.
	table.sort(seen, function(a, b)
		return a.Y > b.Y
	end)

	for i = 1, #seen - 1 do
		local gap = seen[i].Y - seen[i + 1].Y
		ok(gap > 0, seen[i + 1].Name .. " sits above " .. seen[i].Name)
	end
end)

-------------------------------------------------------------------------------
-- Text inputs
-------------------------------------------------------------------------------

test("no input inherits TextScaled from the place file", function(H)
	--[[
		Frame.TextBox in the .rbxl has TextScaled = true, and every input in
		the UI is a clone of it. TextScaled grows the font until it fills the
		box, so a 42px field rendered ~38px glyphs where a UI font wants 14-18.
		All seven clones inherited it and nothing turned it off.

		This walks every TextBox that actually exists rather than a hard coded
		list, so a new input added later is covered without anyone remembering
		to add it here.
	--]]
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local function walk(node, found)
		for _, c in ipairs(node:GetChildren()) do
			if c.ClassName == "TextBox" then
				found[#found + 1] = c
			end
			walk(c, found)
		end
		return found
	end

	local boxes = walk(H.clientGui, {})
	ok(#boxes >= 6, "found the inputs (" .. #boxes .. ")")

	for _, box in ipairs(boxes) do
		eq(box.TextScaled, false, box.Name .. " does not scale its text")
		ok(box.TextSize and box.TextSize >= 12 and box.TextSize <= 20,
			box.Name .. " has a readable TextSize (" .. tostring(box.TextSize) .. ")")
		ok(box:FindFirstChildOfClass("UIPadding") ~= nil,
			box.Name .. " has padding so the text is not flush to the border")
	end
end)

test("single line inputs do not wrap, the report note does", function(H)
	--[[
		Wrapping a placeholder mid-word inside a 42px tall field looks broken.
		The report note is the one genuine exception: it is a free-text note,
		so it wraps and sits top aligned.
	--]]
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.runClient(alice)

	local gui = H.clientGui

	local note = H.findIn(gui, "ReportFrame"):FindFirstChild("Note")
	ok(note ~= nil, "the report note exists")
	eq(note.TextWrapped, true, "it wraps")
	eq(note.MultiLine, true, "and takes more than one line")

	-- The single line fields must not.
	for _, name in ipairs({"TextBox", "ImageBox"}) do
		local b = H.findIn(gui, name)
		if b then
			eq(b.TextWrapped, false, name .. " stays on one line")
		end
	end
end)

-------------------------------------------------------------------------------
-- The input dock
-------------------------------------------------------------------------------

test("the input field lives outside the panel at a fixed size", function(H)
	--[[
		The panel is laid out in scale and shrunk by a UIScale, which is right
		for rows of buttons and wrong for a text field: the field shrank with
		everything else until the text stopped being readable.

		So the field is pinned to the top of the screen in fixed pixels and
		never scales. This checks it is genuinely outside the panel, since a
		field nested inside would inherit the UIScale again and undo the point.
	--]]
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local gui = H.clientGui
	local dock = H.findIn(gui, "InputDock")
	ok(dock ~= nil, "the dock exists")

	eq(dock.Parent, gui, "it is a sibling of the panel, not inside it")

	-- Fixed pixels: no scale component at all.
	eq(dock.Size.Y.Scale, 0, "its height is pure pixels")
	ok(dock.Size.Y.Offset >= 32, "and big enough to hold a readable field")

	-- It has to draw over the panel, which fills the screen on a small window.
	local panel = H.findIn(gui, "AdminFrame")
	ok(dock.ZIndex > panel.ZIndex, "it draws above the panel")

	local box = dock:FindFirstChild("Box")
	ok(box ~= nil, "the field is in there")
	eq(box.TextScaled, false, "and does not scale its text")
end)

test("the dock only shows on pages that take a value", function(H)
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local gui = H.clientGui
	local dock = H.findIn(gui, "InputDock")

	eq(dock.Visible, false, "hidden while the panel is shut")

	H.remote.OnClientEvent:Fire("AdminAccess", true, 3, "Developer")
	H.findIn(gui, "AdminButton").MouseButton1Click:Fire()
	H.drain()
	eq(dock.Visible, true, "shown on Home, which takes a message")

	-- Reports has no command that reads a value, so a box there would do
	-- nothing but confuse.
	H.findIn(gui, "Nav_Reports").MouseButton1Click:Fire()
	H.drain()
	eq(dock.Visible, false, "hidden on Reports")

	H.findIn(gui, "Nav_Players").MouseButton1Click:Fire()
	H.drain()
	eq(dock.Visible, true, "shown again on Players")

	H.findIn(gui, "AdminClose").MouseButton1Click:Fire()
	eq(dock.Visible, false, "and gone with the panel")
end)

test("one field feeds every page", function(H)
	--[[
		Home and Players used to have separate boxes that always meant the same
		thing. Typing on one page and pressing a button on another now works,
		because there is only one field.
	--]]
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.runClient(owner)

	H.asPlayer(owner, "AdminOpen")
	H.drain()

	local gui = H.clientGui
	H.findIn(gui, "InputDock").Box.Text = "typed on one page"

	-- Announce is a Home command; kick is a Players one. Both read the dock.
	H.findIn(gui, "H_announce").MouseButton1Click:Fire()
	local said = H.lastSent(alice, "Announce")
	ok(said ~= nil, "announce went out")
	eq(said[3], "typed on one page", "with what was typed")

	H.findIn(gui, "P_1001").MouseButton1Click:Fire()
	H.findIn(gui, "C_kick").MouseButton1Click:Fire()
	eq(#H.mock.kicks, 1, "and the kick used the same field")
	ok(string.find(H.mock.kicks[1].Reason, "typed on one page") ~= nil,
		"as its reason")
end)

test("every HUD button is built the same way", function(H)
	--[[
		ShopButton was a clone of ToggleButton, so it drew its caption through
		a child TextLabel carrying the place's own font and stroke. Admin and
		Report were Instance.new with the text set straight on the button, so
		the two rendered differently sitting next to each other.
	--]]
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local gui = H.clientGui
	for _, name in ipairs({"TextButton", "ShopButton", "AdminButton", "ReportButton"}) do
		local b = H.findIn(gui, name)
		ok(b ~= nil, name .. " exists")

		local label = b:FindFirstChild("TextLabel")
		ok(label ~= nil, name .. " draws its caption through a TextLabel")
		eq(b.Text, "", name .. " does not also set text on the button itself")
	end

	-- And the captions actually landed on those labels.
	eq(H.findIn(gui, "AdminButton").TextLabel.Text, "Admin", "admin caption")
	eq(H.findIn(gui, "ReportButton").TextLabel.Text, "Report", "report caption")
	eq(H.findIn(gui, "ShopButton").TextLabel.Text, "Shop", "shop caption")
end)

test("the HUD stack never overlaps at any window size", function(H)
	--[[
		The step used to be baked into a pixel offset from one measurement of
		the screen, so at 1080p the buttons were 77px tall but still stacked
		50px apart. The spacing is carried in scale and offset now, matching
		how the button is sized, so it holds at every size rather than the one
		the player happened to join at.
	--]]
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local gui = H.clientGui
	local names = {"TextButton", "ShopButton", "AdminButton", "ReportButton"}

	for _, screen in ipairs({{1920, 1080}, {1280, 720}, {1024, 576}, {617, 326}}) do
		local w, h = screen[1], screen[2]

		local drawn = {}
		for _, name in ipairs(names) do
			local b = H.findIn(gui, name)
			drawn[#drawn + 1] = {
				Name = name,
				Y = b.Position.Y.Scale * h + b.Position.Y.Offset,
				H = math.max(b.Size.Y.Scale * h + b.Size.Y.Offset, 34),
			}
		end

		table.sort(drawn, function(a, b)
			return a.Y < b.Y
		end)

		for i = 1, #drawn - 1 do
			local gap = drawn[i + 1].Y - drawn[i].Y
			ok(gap >= drawn[i].H,
				string.format("%dx%d: %s clears %s (gap %.0f, height %.0f)",
					w, h, drawn[i + 1].Name, drawn[i].Name, gap, drawn[i].H))
		end
	end
end)

test("opening a window hides the HUD, closing brings it back", function(H)
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local gui = H.clientGui
	H.remote.OnClientEvent:Fire("AdminAccess", true, 3, "Developer")

	local adminButton = H.findIn(gui, "AdminButton")
	local reportButton = H.findIn(gui, "ReportButton")
	eq(adminButton.Visible, true, "the admin button starts visible")

	-- Opening the panel takes the stack off screen, because below about
	-- 1024px wide there is simply no room beside the panel for it.
	adminButton.MouseButton1Click:Fire()
	H.drain()
	eq(H.findIn(gui, "AdminFrame").Visible, true, "the panel opened")
	eq(adminButton.Visible, false, "and the HUD went away")
	eq(reportButton.Visible, false, "all of it, not just the one pressed")

	H.findIn(gui, "AdminClose").MouseButton1Click:Fire()
	eq(H.findIn(gui, "AdminFrame").Visible, false, "the panel closed")
	eq(adminButton.Visible, true, "and the HUD came back")
	eq(reportButton.Visible, true, "all of it")
end)

test("the report window hides the HUD too", function(H)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.runClient(alice)

	local gui = H.clientGui
	local reportButton = H.findIn(gui, "ReportButton")

	reportButton.MouseButton1Click:Fire()
	H.drain()
	eq(reportButton.Visible, false, "hidden while the window is up")

	H.findIn(H.findIn(gui, "ReportFrame"), "Close").MouseButton1Click:Fire()
	eq(reportButton.Visible, true, "back once it is closed")
end)

test("hiding the HUD does not resurrect the booth toggle", function(H)
	--[[
		The booth toggle is only meant to show once a booth is claimed, so
		restoring the stack must respect that rather than turning everything
		back on blindly.
	--]]
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.runClient(alice)

	local gui = H.clientGui
	local toggle = H.findIn(gui, "TextButton")
	eq(toggle.Visible, false, "no booth, so no toggle")

	H.findIn(gui, "ReportButton").MouseButton1Click:Fire()
	H.drain()
	H.findIn(H.findIn(gui, "ReportFrame"), "Close").MouseButton1Click:Fire()

	eq(toggle.Visible, false, "still hidden after the HUD came back")

	-- Claim a booth, and it should appear.
	H.remote.OnClientEvent:Fire("OpenGui")
	eq(toggle.Visible, true, "shown once a booth is claimed")
end)

test("the trolling page exists for an admin", function(H)
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	local gui = H.clientGui
	ok(H.findIn(gui, "Nav_Trolling") ~= nil, "there is a Trolling tab")
	ok(H.findIn(gui, "P_Trolling") ~= nil, "and a Trolling page")
end)

test("troll buttons land on the trolling page, not the players page", function(H)
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(admin)

	H.remote.OnClientEvent:Fire("AdminAccess", true, 2, "Admin")
	H.remote.OnClientEvent:Fire("AdminCommands", {
		{Name = "kick", Label = "Kick", Args = {"player", "text"}, Rank = 1},
		{Name = "fling", Label = "Fling", Args = {"player"}, Rank = 2, Troll = true},
	})

	eq(#H.mock.errors, 0, "no errors building them")

	local kick = H.findIn(H.clientGui, "C_kick")
	local fling = H.findIn(H.clientGui, "C_fling")
	ok(kick ~= nil, "the kick button exists")
	ok(fling ~= nil, "and so does fling")

	-- Walk up from each button to find which page it ended up on.
	local function pageOf(button)
		local node = button.Parent
		while node do
			if string.sub(tostring(node.Name), 1, 2) == "P_" then
				return node.Name
			end
			node = node.Parent
		end
		return "?"
	end

	eq(pageOf(kick), "P_Players", "kick is on the Players page")
	eq(pageOf(fling), "P_Trolling", "fling is on the Trolling page")
end)

end
