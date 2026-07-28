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
	local admin = H.addPlayer("qzc", 78857)
	H.drain()

	local label = tagOf(admin)
	ok(label ~= nil, "the admin has a tag")
	eq(label.Text, "Admin", "reading Admin")
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
