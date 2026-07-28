--[[
	Runs the booth server and client for real and checks what they do.

	Each test gets a fresh place, so nothing leaks between them. The point is
	to cover the things that were actually changed - ranks, the whitelist, the
	commands, the reports, the avatar fetch - plus enough of the original booth
	behaviour to prove none of it was broken on the way past.
--]]

local passed, failed = 0, 0
local failures = {}
local currentTest = ""

local function ok(cond, label)
	if cond then
		passed = passed + 1
	else
		failed = failed + 1
		failures[#failures + 1] = currentTest .. ": " .. label
		print("    FAIL  " .. label)
	end
end

local function eq(a, b, label)
	if a == b then
		passed = passed + 1
	else
		failed = failed + 1
		local msg = label .. "  (got " .. tostring(a) .. ", wanted " .. tostring(b) .. ")"
		failures[#failures + 1] = currentTest .. ": " .. msg
		print("    FAIL  " .. msg)
	end
end

-- A fresh place, server running, with `booths` booths already in it.
local function freshServer(booths)
	package.loaded = {}
	for _, k in ipairs({"game", "workspace", "Workspace", "script", "Instance", "Enum"}) do
		_G[k] = nil
	end

	local H = dofile(TOOLS .. "/harness.lua")
	H.installGlobals()
	H.buildPlace()

	for i = 1, (booths or 3) do
		H.addBooth(i)
	end

	H.runServer()
	return H
end

local tests = {}

local function test(name, fn)
	tests[#tests + 1] = {Name = name, Fn = fn}
end

-------------------------------------------------------------------------------
-- Booth basics, to prove the original behaviour still works
-------------------------------------------------------------------------------

test("booths are set up and claimable", function(H)
	local booth = H.booths:GetChildren()[1]
	ok(booth ~= nil, "a booth exists")
	eq(booth.Display.SurfaceGui.TextLabel.Text, "Unclaimed Booth", "starts unclaimed")
	eq(booth.Display.Attachment.ProximityPrompt.Enabled, true, "prompt is on")

	local p = H.addPlayer("alice", 1001)
	H.drain()

	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(p)

	eq(booth.Display.BoothOwner.Value, p, "alice owns the booth")
	eq(booth.Display.SurfaceGui.TextLabel.Text, "alice's Booth", "label updated")
	eq(booth.Display.Attachment.ProximityPrompt.Enabled, false, "prompt is off once claimed")
	eq(booth.PartNamePlayer.SurfaceGui.TextLabel.Text, "alice", "nameplate updated")
end)

test("leaving frees the booth", function(H)
	local booth = H.booths:GetChildren()[1]
	local p = H.addPlayer("alice", 1001)
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(p)
	eq(booth.Display.BoothOwner.Value, p, "claimed")

	H.removePlayer(p)
	eq(booth.Display.BoothOwner.Value, nil, "freed on leave")
	eq(booth.Display.SurfaceGui.TextLabel.Text, "Unclaimed Booth", "label reset")
end)

test("booth text is filtered", function(H)
	local booth = H.booths:GetChildren()[1]
	local p = H.addPlayer("alice", 1001)
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(p)

	H.asPlayer(p, "ChangeText", "hello badword there")
	eq(booth.Display.SurfaceGui.TextLabel.Text, "hello ####### there", "text went through the filter")
end)

test("image upload needs the pass", function(H)
	local booth = H.booths:GetChildren()[1]
	local p = H.addPlayer("alice", 1001)
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(p)

	H.asPlayer(p, "ChangeImage", "12345")
	local err = H.lastSent(p, "ImageError")
	ok(err ~= nil, "refused without the pass")

	-- Grant UPLOAD and try again. The "does not own" answer is cached for
	-- half a minute, so the clock has to move past that first.
	H.Marketplace._owned[p] = {[356360] = true}
	H.advance(60)
	H.asPlayer(p, "ChangeImage", "12345")
	eq(booth.Display.SurfaceGui.ImageLabel.Image, "rbxassetid://12345", "image applied with the pass")
end)

-------------------------------------------------------------------------------
-- Ranks
-------------------------------------------------------------------------------

test("thugshaker is a hard coded owner", function(H)
	local p = H.addPlayer("thugshaker", 49603)
	H.drain()

	local access = H.lastSent(p, "AdminAccess")
	ok(access ~= nil, "got an access message")
	eq(access[2], true, "allowed in")
	eq(access[3], 3, "rank 3")
	eq(access[4], "Owner", "named Owner")
end)

test("the seeded IDs come in as admins", function(H)
	local q = H.addPlayer("qzc", 78857)
	local y = H.addPlayer("ywinfe", 181869)
	H.drain()

	local qa = H.lastSent(q, "AdminAccess")
	eq(qa[3], 2, "qzc is rank 2")
	eq(qa[4], "Admin", "qzc is Admin")

	local ya = H.lastSent(y, "AdminAccess")
	eq(ya[3], 2, "ywinfe is rank 2")
	eq(ya[4], "Admin", "ywinfe is Admin")
end)

test("a rank is by UserId, not by name", function(H)
	-- Someone calling themselves thugshaker with a different ID gets nothing.
	local imposter = H.addPlayer("thugshaker", 999999)
	H.drain()

	local access = H.lastSent(imposter, "AdminAccess")
	eq(access[2], false, "name alone does not grant a rank")
	eq(access[3], 0, "rank 0")
end)

test("an ordinary player gets no panel", function(H)
	local p = H.addPlayer("alice", 1001)
	H.drain()

	local access = H.lastSent(p, "AdminAccess")
	eq(access[2], false, "not allowed")

	-- And firing the admin remotes by hand does nothing.
	H.clearSent()
	H.asPlayer(p, "AdminOpen")
	eq(H.lastSent(p, "AdminPlayers"), nil, "AdminOpen ignored")

	H.asPlayer(p, "AdminCommand", {Name = "kick", Target = 1002, Value = "x"})
	eq(#H.mock.kicks, 0, "kick by a non admin did nothing")
end)

-------------------------------------------------------------------------------
-- Commands
-------------------------------------------------------------------------------

test("a mod can kick, an ordinary player cannot", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "kick", Target = victim.UserId, Value = "spamming"})

	eq(#H.mock.kicks, 1, "one kick happened")
	eq(H.mock.kicks[1].Player, victim, "the right person")
	ok(string.find(H.mock.kicks[1].Reason, "spamming") ~= nil, "reason carried through")
end)

test("staff cannot act on someone who outranks them", function(H)
	local admin = H.addPlayer("qzc", 78857)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(admin, "AdminCommand", {Name = "kick", Target = owner.UserId, Value = "nope"})

	eq(#H.mock.kicks, 0, "the owner was not kicked")
	local err = H.lastSent(admin, "AdminError")
	ok(err ~= nil, "the admin was told no")
	ok(string.find(tostring(err[2]), "outrank") ~= nil, "told why")
end)

test("staff cannot act on themselves", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {Name = "kick", Target = owner.UserId, Value = "oops"})
	eq(#H.mock.kicks, 0, "no self kick")
end)

test("freeze holds someone still and survives a respawn", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "freeze", Target = victim.UserId})

	local hum = victim.Character:FindFirstChild("Humanoid")
	eq(hum.WalkSpeed, 0, "cannot walk")
	eq(victim.Character.HumanoidRootPart.Anchored, true, "anchored in place")

	-- Respawning must not be an escape.
	victim:LoadCharacter()
	H.drain()
	local hum2 = victim.Character:FindFirstChild("Humanoid")
	eq(hum2.WalkSpeed, 0, "still frozen after a respawn")

	H.asPlayer(owner, "AdminCommand", {Name = "unfreeze", Target = victim.UserId})
	eq(victim.Character:FindFirstChild("Humanoid").WalkSpeed, 16, "unfrozen")
end)

test("mute stops chat commands and is reported to the client", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "mute", Target = victim.UserId})
	local told = H.lastSent(victim, "Muted")
	ok(told ~= nil and told[2] == true, "the muted player was told")

	H.asPlayer(owner, "AdminCommand", {Name = "unmute", Target = victim.UserId})
	local told2 = H.lastSent(victim, "Muted")
	eq(told2[2], false, "and told when it was lifted")
end)

test("speed is clamped rather than trusted", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "speed", Target = victim.UserId, Value = "99999"})
	eq(victim.Character:FindFirstChild("Humanoid").WalkSpeed, 200, "clamped to the ceiling")

	H.asPlayer(owner, "AdminCommand", {Name = "speed", Target = victim.UserId, Value = "-50"})
	eq(victim.Character:FindFirstChild("Humanoid").WalkSpeed, 0, "clamped to the floor")
end)

test("ban kicks now and blocks the rejoin", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "ban", Target = victim.UserId, Value = "cheating"})
	eq(#H.mock.kicks, 1, "kicked on the spot")

	H.removePlayer(victim)

	-- Coming back with the same UserId is refused.
	local again = H.addPlayer("alice", 1001)
	H.drain()
	ok(rawget(again, "_kicked") ~= nil, "the rejoin was refused")
end)

test("a ban survives a server restart", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()
	H.asPlayer(owner, "AdminCommand", {Name = "ban", Target = victim.UserId, Value = "cheating"})

	-- The DataStore is what carries state across a restart, so reuse it.
	local saved = H.DataStores._stores
	local H2 = freshServer(2)
	H2.DataStores._stores = saved
	H2.runServer()

	local rejoin = H2.addPlayer("alice", 1001)
	H2.drain()
	ok(rawget(rejoin, "_kicked") ~= nil, "still banned after the restart")
end)

test("announce reaches everyone", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local a = H.addPlayer("alice", 1001)
	local b = H.addPlayer("bob", 1002)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminCommand", {Name = "announce", Value = "show starts now"})

	local toA = H.lastSent(a, "Announce")
	local toB = H.lastSent(b, "Announce")
	ok(toA ~= nil, "alice heard it")
	ok(toB ~= nil, "bob heard it")
	eq(toA[3], "show starts now", "the message came through")
end)

test("locking the server turns away non staff", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "lock"})

	local stranger = H.addPlayer("alice", 1001)
	H.drain()
	ok(rawget(stranger, "_kicked") ~= nil, "a stranger is turned away")

	local mod = H.addPlayer("qzc", 78857)
	H.drain()
	eq(rawget(mod, "_kicked"), nil, "staff still get in")

	H.asPlayer(owner, "AdminCommand", {Name = "unlock"})
	local later = H.addPlayer("bob", 1002)
	H.drain()
	eq(rawget(later, "_kicked"), nil, "and everyone once unlocked")
end)

test("force unclaim frees someone else's booth", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)
	eq(booth.Display.BoothOwner.Value, alice, "alice claimed it")

	H.asPlayer(owner, "AdminCommand", {Name = "unclaim", Target = alice.UserId})
	eq(booth.Display.BoothOwner.Value, nil, "the booth was freed")
end)

-------------------------------------------------------------------------------
-- Chat commands
-------------------------------------------------------------------------------

test("chat and the GUI take the same route", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	owner.Chatted:Fire("/kick alice being rude")

	eq(#H.mock.kicks, 1, "the chat command kicked")
	eq(H.mock.kicks[1].Player, victim, "the right person")
	ok(string.find(H.mock.kicks[1].Reason, "being rude") ~= nil, "the reason came through")
end)

test("chat commands from a non admin are ignored", function(H)
	local a = H.addPlayer("alice", 1001)
	local b = H.addPlayer("bob", 1002)
	H.drain()

	a.Chatted:Fire("/kick bob")
	eq(#H.mock.kicks, 0, "nothing happened")
end)

test("a partial name that matches two people is refused", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.addPlayer("bobby", 1001)
	H.addPlayer("bobbi", 1002)
	H.drain()
	H.clearSent()

	owner.Chatted:Fire("/kick bob")

	eq(#H.mock.kicks, 0, "nobody was kicked on a guess")
	local err = H.lastSent(owner, "AdminError")
	ok(err ~= nil and string.find(tostring(err[2]), "matches") ~= nil, "told it was ambiguous")
end)

test("a target can be given as a UserId", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	owner.Chatted:Fire("/kick 1001 by id")
	eq(#H.mock.kicks, 1, "the UserId resolved")
	eq(H.mock.kicks[1].Player, victim, "to the right player")
end)

-------------------------------------------------------------------------------
-- The whitelist
-------------------------------------------------------------------------------

test("an owner can promote someone to admin", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 2, Name = "alice"})
	H.drain()

	local access = H.lastSent(alice, "AdminAccess")
	eq(access[2], true, "alice can now open the panel")
	eq(access[4], "Admin", "as an Admin")
end)

test("an admin can make a mod but not another admin", function(H)
	local admin = H.addPlayer("qzc", 78857)
	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(admin, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})
	H.drain()
	local access = H.lastSent(alice, "AdminAccess")
	eq(access[4], "Mod", "a mod was made")

	-- Same admin trying to hand out their own rank is refused.
	H.clearSent()
	H.asPlayer(admin, "AdminSetRank", {UserId = 1002, Rank = 2, Name = "bob"})
	local err = H.lastSent(admin, "AdminError")
	ok(err ~= nil, "refused")
	ok(string.find(tostring(err[2]), "above your own") ~= nil, "told why")
end)

test("owner cannot be handed out in game", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 3, Name = "alice"})
	local err = H.lastSent(owner, "AdminError")
	ok(err ~= nil and string.find(tostring(err[2]), "Owner") ~= nil, "refused, and says so")
end)

test("a hard coded owner cannot be demoted", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local other = H.addPlayer("qzc", 78857)
	H.drain()
	H.clearSent()

	-- Even another owner-level actor cannot strip the script's owner.
	H.asPlayer(owner, "AdminSetRank", {UserId = 49603, Rank = 0})
	local err = H.lastSent(owner, "AdminError")
	ok(err ~= nil, "refused")
end)

test("the whitelist survives a restart", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local saved = H.DataStores._stores
	local H2 = freshServer(2)
	H2.DataStores._stores = saved
	H2.runServer()

	local alice = H2.addPlayer("alice", 1001)
	H2.drain()
	local access = H2.lastSent(alice, "AdminAccess")
	eq(access[4], "Mod", "alice is still a mod")
end)

test("a demotion mid session closes the panel", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 0, Name = "alice"})
	H.drain()

	local closed = H.lastSent(alice, "AdminClose")
	ok(closed ~= nil, "alice's panel was closed")
end)

-------------------------------------------------------------------------------
-- Reports
-------------------------------------------------------------------------------

test("a player can report someone else's booth", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	local mod = H.addPlayer("qzc", 78857)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.clearSent()
	H.asPlayer(bob, "ReportBooth", {
		Booth = 1,
		Reason = "Inappropriate image",
		Note = "look at it",
	})

	local okMsg = H.lastSent(bob, "ReportOk")
	ok(okMsg ~= nil, "the report was accepted")

	local queue = H.lastSent(mod, "AdminReports")
	ok(queue ~= nil, "staff got the queue")
	eq(#queue[2], 1, "with one report in it")
	eq(queue[2][1].AgainstName, "alice", "against the booth owner")
	eq(queue[2][1].Reason, "Inappropriate image", "with the reason")
end)

test("you cannot report your own booth", function(H)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.clearSent()
	H.asPlayer(alice, "ReportBooth", {Booth = 1, Reason = "Spam or booth hogging"})

	local err = H.lastSent(alice, "ReportError")
	ok(err ~= nil, "refused")
	ok(string.find(tostring(err[2]), "own booth") ~= nil, "says why")
end)

test("you cannot report an unclaimed booth", function(H)
	local bob = H.addPlayer("bob", 1002)
	H.drain()
	H.clearSent()

	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "Advertising"})
	local err = H.lastSent(bob, "ReportError")
	ok(err ~= nil, "refused")
end)

test("the same booth cannot be reported twice by one person", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "Advertising"})
	H.clearSent()

	-- Second attempt: the cooldown or the duplicate check must stop it.
	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "Advertising"})
	local err = H.lastSent(bob, "ReportError")
	ok(err ~= nil, "the second one was refused")
end)

test("an unknown reason is not taken at face value", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	local mod = H.addPlayer("qzc", 78857)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.clearSent()
	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "<script>whatever</script>"})

	local queue = H.lastSent(mod, "AdminReports")
	eq(queue[2][1].Reason, "Other", "forced back onto the fixed list")
end)

test("a mod can close a report", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	local mod = H.addPlayer("qzc", 78857)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)
	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "Advertising"})

	local queue = H.lastSent(mod, "AdminReports")
	local id = queue[2][1].Id

	H.clearSent()
	H.asPlayer(mod, "AdminResolveReport", id)

	local after = H.lastSent(mod, "AdminReports")
	eq(#after[2], 0, "the queue is empty again")
end)

test("an ordinary player cannot close a report", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	local mod = H.addPlayer("qzc", 78857)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)
	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "Advertising"})

	local queue = H.lastSent(mod, "AdminReports")
	local id = queue[2][1].Id

	H.asPlayer(bob, "AdminResolveReport", id)

	H.clearSent()
	H.asPlayer(mod, "AdminRefresh", "Reports")
	local after = H.lastSent(mod, "AdminReports")
	eq(#after[2], 1, "the report is still there")
end)

test("the report note is filtered", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	local mod = H.addPlayer("qzc", 78857)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.clearSent()
	H.asPlayer(bob, "ReportBooth", {Booth = 1, Reason = "Other", Note = "this is badword"})

	local queue = H.lastSent(mod, "AdminReports")
	eq(queue[2][1].Note, "this is #######", "the note went through the filter")
end)

-------------------------------------------------------------------------------
-- Avatars through the proxy
-------------------------------------------------------------------------------

test("a headshot is fetched through the proxy", function(H)
	H.Http._handler = function(url)
		if string.find(url, "avatar%-headshot") then
			return '{"data":[{"targetId":49603,"state":"Completed",'
				.. '"imageUrl":"https://example.invalid/head.png"}]}'
		end
		return '{"data":[]}'
	end

	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()

	-- The first call kicks off the fetch; the second finds it cached.
	H.clearSent()
	H.asPlayer(owner, "AdminOpen")
	H.drain()

	local shot = H.lastSent(owner, "AdminHeadshot")
	ok(shot ~= nil, "a headshot was sent")
	eq(shot[3], "https://example.invalid/head.png", "the proxy URL came through")

	local usedProxy = false
	for _, url in ipairs(H.Http._calls) do
		if string.find(url, "koroneproxy.onrender.com") then
			usedProxy = true
		end
	end
	ok(usedProxy, "it went via the proxy, not the site")
end)

test("the avatar endpoint is used when the headshot one is empty", function(H)
	H.Http._handler = function(url)
		if string.find(url, "avatar%-headshot") then
			return '{"data":[]}'
		end
		if string.find(url, "thumbnails/v1/users/avatar") then
			return '{"data":[{"targetId":49603,"imageUrl":"https://example.invalid/body.png"}]}'
		end
		return "{}"
	end

	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()
	H.asPlayer(owner, "AdminOpen")
	H.drain()

	local shot = H.lastSent(owner, "AdminHeadshot")
	ok(shot ~= nil, "still got a picture")
	eq(shot[3], "https://example.invalid/body.png", "from the fallback endpoint")
end)

test("everything still works with HTTP switched off", function(H)
	-- _handler stays nil, so every GetAsync throws, exactly like a place with
	-- HTTP requests disabled.
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminOpen")
	H.drain()

	local players = H.lastSent(owner, "AdminPlayers")
	ok(players ~= nil, "the panel still filled in")
	ok(#players[2] >= 2, "with the player list")

	H.asPlayer(owner, "AdminCommand", {Name = "kick", Target = victim.UserId, Value = "x"})
	eq(#H.mock.kicks, 1, "and commands still run")
end)

test("a broken proxy reply does not take the panel down", function(H)
	H.Http._handler = function()
		return "this is not json at all"
	end

	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminOpen")
	H.drain()

	local players = H.lastSent(owner, "AdminPlayers")
	ok(players ~= nil, "the panel still filled in")
end)

-------------------------------------------------------------------------------
-- The panel's own data
-------------------------------------------------------------------------------

test("opening the panel sends every page", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(owner, "AdminOpen")
	H.drain()

	ok(H.lastSent(owner, "AdminAccess") ~= nil, "who am I")
	ok(H.lastSent(owner, "AdminPlayers") ~= nil, "the player list")
	ok(H.lastSent(owner, "AdminReports") ~= nil, "the report queue")
	ok(H.lastSent(owner, "AdminStaff") ~= nil, "the staff list")
	ok(H.lastSent(owner, "AdminState") ~= nil, "the shop")
	ok(H.lastSent(owner, "AdminCommands") ~= nil, "the command list")
end)

test("a mod is not sent the admin only pages", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()

	H.asPlayer(alice, "AdminOpen")
	H.drain()

	ok(H.lastSent(alice, "AdminPlayers") ~= nil, "mods get the player list")
	ok(H.lastSent(alice, "AdminReports") ~= nil, "and the reports")
	eq(H.lastSent(alice, "AdminStaff"), nil, "but not the staff list")
end)

test("the command list is trimmed to the viewer's rank", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.asPlayer(owner, "AdminSetRank", {UserId = 1001, Rank = 1, Name = "alice"})

	local alice = H.addPlayer("alice", 1001)
	H.drain()
	H.clearSent()
	H.asPlayer(alice, "AdminOpen")

	local list = H.lastSent(alice, "AdminCommands")[2]
	local names = {}
	for _, def in ipairs(list) do
		names[def.Name] = true
	end

	ok(names.kick, "a mod is offered kick")
	ok(names.freeze, "and freeze")
	ok(not names.ban, "but not ban")
	ok(not names.admin, "and definitely not admin")
end)

test("the player list carries rank and moderation state", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local alice = H.addPlayer("alice", 1001)
	H.drain()

	H.asPlayer(owner, "AdminCommand", {Name = "mute", Target = alice.UserId})
	H.asPlayer(owner, "AdminCommand", {Name = "freeze", Target = alice.UserId})

	H.clearSent()
	H.asPlayer(owner, "AdminRefresh", "Players")
	local list = H.lastSent(owner, "AdminPlayers")[2]

	local found = nil
	for _, row in ipairs(list) do
		if row.UserId == 1001 then
			found = row
		end
	end

	ok(found ~= nil, "alice is in the list")
	eq(found.Muted, true, "shown as muted")
	eq(found.Frozen, true, "shown as frozen")
	eq(found.RankName, "Player", "with her rank")
	eq(found.CanAct, true, "and the owner may act on her")
end)

test("CanAct is false for someone who outranks you", function(H)
	local admin = H.addPlayer("qzc", 78857)
	H.addPlayer("thugshaker", 49603)
	H.drain()
	H.clearSent()

	H.asPlayer(admin, "AdminRefresh", "Players")
	local list = H.lastSent(admin, "AdminPlayers")[2]

	for _, row in ipairs(list) do
		if row.UserId == 49603 then
			eq(row.CanAct, false, "the admin cannot act on the owner")
		end
		if row.UserId == 78857 then
			eq(row.CanAct, false, "nor on themselves")
		end
	end
end)

-------------------------------------------------------------------------------
-- The client
-------------------------------------------------------------------------------

test("the client builds without erroring", function(H)
	local p = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.runClient(p)

	eq(#H.mock.errors, 0, "no errors while building the UI")

	local gui = H.clientGui
	ok(H.findIn(gui, "AdminButton") ~= nil, "the admin button exists")
	ok(H.findIn(gui, "AdminFrame") ~= nil, "the panel exists")
	ok(H.findIn(gui, "ReportButton") ~= nil, "the report button exists")
	ok(H.findIn(gui, "ReportFrame") ~= nil, "the report window exists")
end)

test("the panel has all five pages and the greeting", function(H)
	local p = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.runClient(p)

	local gui = H.clientGui
	for _, name in ipairs({"Home", "Players", "Reports", "Staff", "Shop"}) do
		ok(H.findIn(gui, "Nav_" .. name) ~= nil, "the " .. name .. " tab exists")
		ok(H.findIn(gui, "P_" .. name) ~= nil, "the " .. name .. " page exists")
	end

	local hello = H.findIn(gui, "Hello")
	ok(hello ~= nil, "the greeting exists")
	eq(hello.Text, "Hello, thugshaker.", "and greets by name")
end)

test("the greeting shows the rank the server sent", function(H)
	local p = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.runClient(p)

	-- Replay what the server says on join.
	H.remote.OnClientEvent:Fire("AdminAccess", true, 3, "Owner")

	local rank = H.findIn(H.clientGui, "Rank")
	eq(rank.Text, "Owner", "the rank badge reads Owner")
	eq(H.findIn(H.clientGui, "AdminButton").Visible, true, "and the button is shown")
end)

test("the admin button stays hidden for an ordinary player", function(H)
	local p = H.addPlayer("alice", 1001)
	H.drain()
	H.runClient(p)

	H.remote.OnClientEvent:Fire("AdminAccess", false, 0, "Player")

	eq(H.findIn(H.clientGui, "AdminButton").Visible, false, "no admin button")
	eq(H.findIn(H.clientGui, "AdminFrame").Visible, false, "and no panel")
end)

test("the client draws the player list it is sent", function(H)
	local p = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.runClient(p)

	H.remote.OnClientEvent:Fire("AdminAccess", true, 3, "Owner")
	H.remote.OnClientEvent:Fire("AdminPlayers", {
		{UserId = 1001, Name = "alice", Rank = 0, RankName = "Player", CanAct = true, Muted = true},
		{UserId = 49603, Name = "thugshaker", Rank = 3, RankName = "Owner", CanAct = false},
	}, false)

	eq(#H.mock.errors, 0, "no errors drawing the list")
	ok(H.findIn(H.clientGui, "P_1001") ~= nil, "alice has a row")
	ok(H.findIn(H.clientGui, "P_49603") ~= nil, "and so does the owner")
end)

test("the client draws the report queue it is sent", function(H)
	local p = H.addPlayer("qzc", 78857)
	H.drain()
	H.runClient(p)

	H.remote.OnClientEvent:Fire("AdminAccess", true, 2, "Admin")
	H.remote.OnClientEvent:Fire("AdminReports", {
		{
			Id = 7, Booth = 2, Against = 1001, AgainstName = "alice",
			ByName = "bob", Reason = "Advertising", Note = "spamming a link",
			Text = "buy my thing", Image = "rbxassetid://1", Online = true,
		},
	}, {"Advertising"})

	eq(#H.mock.errors, 0, "no errors drawing the queue")
	local card = H.findIn(H.clientGui, "R_7")
	ok(card ~= nil, "the report card exists")
	ok(string.find(card.Heading.Text, "alice") ~= nil, "and names the owner")
end)

test("the client builds a button per command it is offered", function(H)
	local p = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.runClient(p)

	H.remote.OnClientEvent:Fire("AdminAccess", true, 3, "Owner")
	H.remote.OnClientEvent:Fire("AdminCommands", {
		{Name = "kick", Label = "Kick", Args = {"player", "text"}, Rank = 1},
		{Name = "announce", Label = "Announce", Args = {"text"}, Rank = 1, Raw = true},
	})

	eq(#H.mock.errors, 0, "no errors building the buttons")
	ok(H.findIn(H.clientGui, "C_kick") ~= nil, "a kick button appeared")
	ok(H.findIn(H.clientGui, "C_announce") ~= nil, "and an announce button")
end)

test("a command button with nobody picked is refused client side", function(H)
	local p = H.addPlayer("thugshaker", 49603)
	H.drain()
	H.runClient(p)

	H.remote.OnClientEvent:Fire("AdminAccess", true, 3, "Owner")
	H.remote.OnClientEvent:Fire("AdminCommands", {
		{Name = "kick", Label = "Kick", Args = {"player", "text"}, Rank = 1},
	})

	H.clearSent()
	H.findIn(H.clientGui, "C_kick").MouseButton1Click:Fire()

	-- Nothing should have reached the server, and the status line should say so.
	local status = H.findIn(H.clientGui, "AdminStatus")
	ok(string.find(status.Text, "Pick someone") ~= nil, "told to pick someone first")
end)

test("the whole round trip works: client button to server action", function(H)
	local owner = H.addPlayer("thugshaker", 49603)
	local victim = H.addPlayer("alice", 1001)
	H.drain()
	H.runClient(owner)

	-- Let the server tell the client who it is, exactly as it would on join.
	H.asPlayer(owner, "AdminOpen")
	H.drain()

	local gui = H.clientGui
	ok(H.findIn(gui, "C_kick") ~= nil, "the kick button was built from the server's list")

	-- Pick alice in the list, then press Kick.
	H.findIn(gui, "P_1001").MouseButton1Click:Fire()
	H.findIn(gui, "Input").Text = "round trip"
	H.findIn(gui, "C_kick").MouseButton1Click:Fire()

	eq(#H.mock.kicks, 1, "the server kicked her")
	eq(H.mock.kicks[1].Player, victim, "the right person")
end)

test("the report window round trips too", function(H)
	local alice = H.addPlayer("alice", 1001)
	local bob = H.addPlayer("bob", 1002)
	local mod = H.addPlayer("qzc", 78857)
	H.drain()

	local booth = H.booths:GetChildren()[1]
	booth.Display.Attachment.ProximityPrompt.Triggered:Fire(alice)

	H.runClient(bob)
	local gui = H.clientGui

	-- Open the window, which asks the server what can be reported.
	H.findIn(gui, "ReportButton").MouseButton1Click:Fire()
	H.drain()

	local row = H.findIn(gui, "RB_1")
	ok(row ~= nil, "alice's booth is offered")

	row.MouseButton1Click:Fire()
	H.findIn(gui, "RR_1").MouseButton1Click:Fire()
	H.findIn(gui, "Send").MouseButton1Click:Fire()

	local queue = H.lastSent(mod, "AdminReports")
	ok(queue ~= nil and #queue[2] == 1, "the moderator got the report")
	eq(queue[2][1].AgainstName, "alice", "against the right person")
end)

-------------------------------------------------------------------------------
-- Extra suites
-------------------------------------------------------------------------------

-- Kept in their own file so this one stays readable; they share the runner and
-- the assertion helpers.
dofile(TESTS .. "/commands.lua")(test, ok, eq)
dofile(TESTS .. "/tags.lua")(test, ok, eq)

-------------------------------------------------------------------------------
-- Runner
-------------------------------------------------------------------------------

print("")
print("Running " .. #tests .. " tests")
print("")

for _, t in ipairs(tests) do
	currentTest = t.Name
	local H = freshServer(3)
	H.mock.errors = {}
	H.mock.kicks = {}
	H.clearSent()

	local before = failed
	local okRun, err = pcall(t.Fn, H)

	if not okRun then
		failed = failed + 1
		failures[#failures + 1] = t.Name .. ": crashed - " .. tostring(err)
		print("  CRASH " .. t.Name)
		print("        " .. tostring(err))
	elseif failed > before then
		print("  fail  " .. t.Name)
	else
		print("  ok    " .. t.Name)
	end
end

print("")
print(string.rep("-", 60))
print(passed .. " passed, " .. failed .. " failed")

if failed > 0 then
	print("")
	for _, f in ipairs(failures) do
		print("  " .. f)
	end
end
print("")

return failed == 0
