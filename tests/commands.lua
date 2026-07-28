--[[
	Covers the commands the main suite does not, plus the edge cases that only
	show up once a command is actually run: a target with no character, a
	value that is not a number, a rate limit that really does bite.

	Loaded by tests/all.lua, which owns the runner. This file only adds tests.
--]]

return function(test, ok, eq)

-- Movement --------------------------------------------------------------------

test("bring pulls someone to you", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	alice.Character.HumanoidRootPart.CFrame = CFrame.new(500, 0, 500)
	owner.Character.HumanoidRootPart.CFrame = CFrame.new(0, 0, 0)

	H.asPlayer(owner, "AdminCommand", {Name = "bring", Target = alice.UserId})

	local moved = alice.Character.HumanoidRootPart.CFrame
	ok(moved.X < 100, "alice was moved next to the owner")
end)

test("goto walks you to them", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	alice.Character.HumanoidRootPart.CFrame = CFrame.new(500, 0, 500)
	owner.Character.HumanoidRootPart.CFrame = CFrame.new(0, 0, 0)

	H.asPlayer(owner, "AdminCommand", {Name = "goto", Target = alice.UserId})

	local moved = owner.Character.HumanoidRootPart.CFrame
	ok(moved.X > 100, "the owner was moved out to alice")
end)

test("a command against someone with no character says so", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local ghost = H.addPlayer("alice", 1001, false)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {Name = "speed", Target = ghost.UserId, Value = "50"})

	local err = H.lastSent(owner, "AdminError")
	ok(err ~= nil, "refused rather than erroring")
	ok(string.find(tostring(err[2]), "character") ~= nil, "and explains why")
end)

test("respawn loads a fresh character", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	local before = alice.Character
	H.asPlayer(owner, "AdminCommand", {Name = "respawn", Target = alice.UserId})

	ok(alice.Character ~= before, "she got a new character")
end)

-- Character --------------------------------------------------------------------

test("heal puts health back to full", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	alice.Character.Humanoid.Health = 12
	H.asPlayer(owner, "AdminCommand", {Name = "heal", Target = alice.UserId})

	eq(alice.Character.Humanoid.Health, 100, "back to full")
end)

test("jump power is clamped like speed", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "jump", Target = alice.UserId, Value = "99999"})
	eq(alice.Character.Humanoid.JumpPower, 500, "clamped to the ceiling")
end)

test("a value that is not a number is refused", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {Name = "speed", Target = alice.UserId, Value = "fast"})

	local err = H.lastSent(owner, "AdminError")
	ok(err ~= nil, "refused")
	eq(alice.Character.Humanoid.WalkSpeed, 16, "and the speed was left alone")
end)

test("god and ungod are admin only", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local mod = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	H.drain()
	H.clearSent()

	H.asPlayer(mod, "AdminCommand", {Name = "god", Target = bob.UserId})

	local err = H.lastSent(mod, "AdminError")
	ok(err ~= nil, "a mod is refused")
	ok(string.find(tostring(err[2]), "Admin") ~= nil, "and told the rank needed")

	-- The owner can, though.
	H.asPlayer(owner, "AdminCommand", {Name = "god", Target = bob.UserId})
	ok(bob.Character.Humanoid.MaxHealth > 1000, "god mode applied")

	H.asPlayer(owner, "AdminCommand", {Name = "ungod", Target = bob.UserId})
	eq(bob.Character.Humanoid.MaxHealth, 100, "and taken off again")
end)

test("god survives a respawn", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "god", Target = alice.UserId})
	alice:LoadCharacter()
	H.drain()

	ok(alice.Character.Humanoid.MaxHealth > 1000, "still godded")
end)

test("invisible hides every part", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "invisible", Target = alice.UserId})
	eq(alice.Character.Head.Transparency, 1, "the head is hidden")

	H.asPlayer(owner, "AdminCommand", {Name = "visible", Target = alice.UserId})
	eq(alice.Character.Head.Transparency, 0, "and shown again")
end)

-- Warnings ----------------------------------------------------------------------

test("a warning reaches only the person warned", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {
		Name = "warn", Target = alice.UserId, Value = "last chance",
	})

	local toAlice = H.lastSent(alice, "AdminWarn")
	ok(toAlice ~= nil, "alice was warned")
	eq(toAlice[3], "last chance", "with the message")
	eq(H.lastSent(bob, "AdminWarn"), nil, "bob heard nothing")
end)

test("an empty warning is refused", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {Name = "warn", Target = alice.UserId, Value = "   "})

	ok(H.lastSent(owner, "AdminError") ~= nil, "refused")
	eq(H.lastSent(alice, "AdminWarn"), nil, "and nothing was sent")
end)

-- Booths ------------------------------------------------------------------------

test("clearbooth wipes the image but leaves the claim", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.Marketplace._owned[alice] = {[356360] = true, [353447] = true}
	H.advance(60)
	H.asPlayer(alice, "ChangeImage", "999")
	eq(booth.Display.SurfaceGui.ImageLabel.Image, "rbxassetid://999", "image set")

	H.asPlayer(owner, "AdminCommand", {Name = "clearbooth", Target = alice.UserId})

	ok(booth.Display.SurfaceGui.ImageLabel.Image ~= "rbxassetid://999", "image wiped")
	eq(booth.Display.BoothOwner.Value, alice, "but she still owns it")
end)

test("resetbooths frees everything at once", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	H.drain()

	local all = H.booths:GetChildren()
	all[1].Display.Attachment.ProximityPrompt.Triggered:Fire(alice)
	all[2].Display.Attachment.ProximityPrompt.Triggered:Fire(bob)

	H.asPlayer(owner, "AdminCommand", {Name = "resetbooths"})

	eq(all[1].Display.BoothOwner.Value, nil, "the first is free")
	eq(all[2].Display.BoothOwner.Value, nil, "and so is the second")
end)

test("resetbooths is admin only", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local mod = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(bob)

	H.clearSent()
	H.asPlayer(mod, "AdminCommand", {Name = "resetbooths"})

	ok(H.lastSent(mod, "AdminError") ~= nil, "a mod is refused")
	eq(booth.Display.BoothOwner.Value, bob, "and the booth was left alone")
end)

-- Time and unban -----------------------------------------------------------------

test("time is clamped to a real hour", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "time", Value = "18"})
	eq(H.Lighting.ClockTime, 18, "set to 18")

	H.asPlayer(owner, "AdminCommand", {Name = "time", Value = "99"})
	eq(H.Lighting.ClockTime, 24, "clamped at 24")
end)

test("unban works on someone who is not here", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "ban", Target = alice.UserId, Value = "x"})
	H.removePlayer(alice)

	-- By UserId, since she is gone.
	H.asPlayer(owner, "AdminCommand", {Name = "unban", Value = "1001"})

	local back = H.addPlayer("alice", 1001)
	H.drain()
	eq(rawget(back, "_kicked"), nil, "she can rejoin")
end)

test("unban by remembered name also works", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "ban", Target = alice.UserId, Value = "x"})
	H.removePlayer(alice)

	H.asPlayer(owner, "AdminCommand", {Name = "unban", Value = "alice"})

	local back = H.addPlayer("alice", 1001)
	H.drain()
	eq(rawget(back, "_kicked"), nil, "she can rejoin")
end)

test("unbanning someone who is not banned says so", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {Name = "unban", Value = "nobody"})
	ok(H.lastSent(owner, "AdminError") ~= nil, "told there is no such ban")
end)

-- Rate limiting --------------------------------------------------------------------

test("the staff rate limit answers rather than going quiet", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	-- Two commands with no time between them at all.
	local frozen = H.clock
	H.asPlayer(owner, "AdminCommand", {Name = "heal", Target = alice.UserId})
	H.clock = frozen
	H.asPlayer(owner, "AdminCommand", {Name = "heal", Target = alice.UserId})

	local err = H.lastSent(owner, "AdminError")
	ok(err ~= nil, "the second one got an answer")
	ok(string.find(tostring(err[2]), "Slow down") ~= nil, "saying to slow down")
end)

test("reports are rate limited per player", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	local carol = H.addPlayer("carol", 1003)
	H.drain()

	local all = H.booths:GetChildren()
	all[1].Display.Attachment.ProximityPrompt.Triggered:Fire(alice)
	all[2].Display.Attachment.ProximityPrompt.Triggered:Fire(carol)

	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "Advertising"})
	H.clearSent()

	-- A different booth, so only the cooldown can stop it.
	H.asPlayer(bob, "ReportBooth", {Booth = 2, Reason = "Advertising"})
	local err = H.lastSent(bob, "ReportError")
	ok(err ~= nil, "the second report was refused")

	-- Once the cooldown passes it goes through.
	H.advance(60)
	H.clearSent()
	H.asPlayer(bob, "ReportBooth", {Booth = 2, Reason = "Advertising"})
	ok(H.lastSent(bob, "ReportOk") ~= nil, "and is accepted later")
end)

-- Shop, still admin only ------------------------------------------------------------

test("a mod cannot edit the shop", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local mod = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(mod, "AdminSavePass", {
		Key = "SNEAKY", Title = "Sneaky", Id = 1234, Category = "Passes",
	})

	H.asPlayer(owner, "AdminRefresh", "Shop")
	local shop = H.lastSent(owner, "AdminState")[2]
	for _, entry in ipairs(shop) do
		ok(entry.Key ~= "SNEAKY", "the mod's pass was not added")
	end
end)

test("an admin can add a pass and it reaches the shop", function(H)
	local admin = H.addPlayer("qzc", 78857)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(admin, "AdminSavePass", {
		Key = "SPEED", Title = "Speed Boost", Id = 4242,
		Category = "Passes", Blurb = "go fast", Price = "Gamepass",
	})

	local state = H.lastSent(alice, "PassState")
	ok(state ~= nil, "the shop was pushed to everyone")

	local found = false
	for _, entry in ipairs(state[2]) do
		if entry.Key == "SPEED" then
			found = true
			eq(entry.Title, "Speed Boost", "with the title")
		end
	end
	ok(found, "the new pass is in the shop")
end)

test("built in passes cannot be deleted", function(H)
	local admin = H.addPlayer("qzc", 78857)
	H.drain()
	H.clearSent()

	H.asPlayer(admin, "AdminDeletePass", "UPLOAD")

	local err = H.lastSent(admin, "AdminError")
	ok(err ~= nil, "refused")

	H.asPlayer(admin, "AdminRefresh", "Shop")
	local shop = H.lastSent(admin, "AdminState")[2]
	local stillThere = false
	for _, entry in ipairs(shop) do
		if entry.Key == "UPLOAD" then
			stillThere = true
		end
	end
	ok(stillThere, "UPLOAD is still there")
end)

-- Staff page data ---------------------------------------------------------------------

test("the staff list marks hard coded owners as locked", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminRefresh", "Staff")
	local staff = H.lastSent(owner, "AdminStaff")[2]

	local found = nil
	for _, row in ipairs(staff) do
		if row.UserId == 49603 then
			found = row
		end
	end

	ok(found ~= nil, "the owner is listed")
	eq(found.Locked, true, "and marked as locked")
	eq(found.RankName, "Owner", "with the right rank")
end)

test("the ban list is sent alongside the staff list", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "ban", Target = alice.UserId, Value = "griefing"})

	H.clearSent()
	H.asPlayer(owner, "AdminRefresh", "Staff")
	local msg = H.lastSent(owner, "AdminStaff")

	ok(msg[3] ~= nil, "a ban list came through")
	eq(#msg[3], 1, "with one ban in it")
	eq(msg[3][1].Reason, "griefing", "and the reason")
end)

end
