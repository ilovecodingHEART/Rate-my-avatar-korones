--[[
===============================================================================
  BOOTH REPORT SYSTEM  -  extracted reference copy
===============================================================================

  This file is NOT the running code and is not loaded by the place. It is the
  report system pulled out of ServerScriptService.Server into one place so it
  can be read on its own, for whoever is adding the Discord webhook.

  The live code is src/Server.server.lua. If you change behaviour, change it
  there - this copy will drift otherwise.

-------------------------------------------------------------------------------
  WHERE TO ADD THE WEBHOOK
-------------------------------------------------------------------------------

  Search this file for "WEBHOOK HOOK POINT". There are two:

    1. a report is filed      -> in HandleReport, after the report is stored
    2. a report is closed     -> in the AdminResolveReport branch

  Almost certainly you only want the first one.

  In the live file those are at roughly:

    src/Server.server.lua : HandleReport            (the "SaveReports()" line)
    src/Server.server.lua : "AdminResolveReport"    (the remote branch)

-------------------------------------------------------------------------------
  THINGS THAT WILL BITE YOU
-------------------------------------------------------------------------------

  * Discord blocks Roblox server IPs outright. HttpService:PostAsync straight
    to discord.com/api/webhooks/... returns 403. You need a relay in between.
    This place already proxies its avatar lookups through
    https://koroneproxy.onrender.com for the same reason - talk to whoever runs
    that before standing up a second one.

  * HttpService:PostAsync YIELDS. Do not call it inline in HandleReport: a slow
    or dead webhook would hold up the player who pressed the button, and every
    other report behind it. Wrap it in spawn() so it happens off to the side.
    The example below does this.

  * Wrap it in pcall as well. An HTTP failure that propagates would take out
    the rest of HandleReport, and the report would be lost even though it was
    already stored.

  * Rate limits. Discord allows roughly 5 requests per second per webhook and
    will 429 beyond that. MAX_REPORTS is 60 and REPORT_COOLDOWN is 20 seconds
    per player, so a normal server will not get near that - but a busy one with
    many reporters could. Queue and batch if you see 429s.

  * Note is already filtered. HandleReport runs the free-text note through
    TextService and blanks it if filtering fails, so what reaches your webhook
    is safe to display. Reason is forced onto the fixed list. Do NOT bypass
    HandleReport and post raw player text.

  * Image is a rbxassetid:// string, not a URL. To show a thumbnail in Discord
    you need to turn it into one through the thumbnails API.

===============================================================================
]]

-------------------------------------------------------------------------------
-- 1. Services and remote  (already present in the live script)
-------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")

-------------------------------------------------------------------------------
-- 2. Configuration
-------------------------------------------------------------------------------

local REPORT_DATASTORE = "Reports_v1"

--[[
	Reasons are a FIXED list rather than free text, on purpose.

	Two reasons. Staff get something they can triage at a glance, and a report
	cannot itself be used to put abuse in front of a moderator. Anything not on
	this list is forced to the last entry ("Other") rather than being trusted.
--]]
local REPORT_REASONS = {
	"Inappropriate image",
	"Inappropriate text",
	"Advertising",
	"Impersonation",
	"Spam or booth hogging",
	"Other",
}

local MAX_REPORTS = 60
local REPORT_COOLDOWN = 20 -- seconds between reports from the same player

local FILTER_TEXT = true

-------------------------------------------------------------------------------
-- 3. State
-------------------------------------------------------------------------------

--[[
	A report row, as stored:

	    Id           number   unique, increments forever
	    BoothIndex   number   which booth, stable across the session
	    Against      number   UserId of the booth owner being reported
	    AgainstName  string   their name at the time
	    By           number   UserId of the reporter
	    ByName       string   their name at the time
	    Reason       string   one of REPORT_REASONS, never anything else
	    Note         string   optional, already filtered, may be ""
	    Time         number   os.time() when it was filed
	    Text         string   what the booth said AT THE TIME
	    Image        string   what the booth showed, "rbxassetid://..."

	Text and Image are snapshots deliberately, so staff can still see what was
	reported after the owner changes it or leaves.
--]]
local Reports = {}
local NextReportId = 1
local LastReport = {} -- [userId] = tick()

local ReportStore = nil
do
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore(REPORT_DATASTORE)
	end)
	if ok then
		ReportStore = res
	else
		warn("[Admin] Report DataStore unavailable, reports will only last this server.")
	end
end

-------------------------------------------------------------------------------
-- 4. Persistence
-------------------------------------------------------------------------------

local function SaveReports()
	if not ReportStore then
		return false
	end

	local ok, err = pcall(function()
		ReportStore:SetAsync("open", {Next = NextReportId, List = Reports})
	end)
	if not ok then
		warn("[Admin] Could not save reports: " .. tostring(err))
	end
	return ok
end

local function LoadReports()
	Reports = {}
	if not ReportStore then
		return
	end

	local ok, res = pcall(function()
		return ReportStore:GetAsync("open")
	end)

	if ok and type(res) == "table" then
		NextReportId = tonumber(res.Next) or 1
		if type(res.List) == "table" then
			for _, row in pairs(res.List) do
				if type(row) == "table" and row.Id then
					Reports[#Reports + 1] = row
				end
			end
		end
	elseif not ok then
		warn("[Admin] Could not load reports: " .. tostring(res))
	end
end

LoadReports()

-------------------------------------------------------------------------------
-- 5. Queue helpers
-------------------------------------------------------------------------------

-- Newest first, so the queue reads like an inbox.
local function ReportList()
	local out = {}
	for i = #Reports, 1, -1 do
		local r = Reports[i]
		out[#out + 1] = {
			Id = r.Id,
			Booth = r.BoothIndex,
			Against = r.Against,
			AgainstName = r.AgainstName,
			ByName = r.ByName,
			Reason = r.Reason,
			Note = r.Note,
			Text = r.Text,
			Image = r.Image,
			Time = r.Time,
			Online = FindPlayerByUserId(r.Against) ~= nil,
		}
	end
	return out
end

local function RemoveReport(id)
	id = tonumber(id)
	for i, r in ipairs(Reports) do
		if r.Id == id then
			table.remove(Reports, i)
			return r
		end
	end
	return nil
end

-- Every staff member on shift sees the same queue.
local function PushReports(Player)
	if not IsAdmin(Player) then
		return
	end
	RemoteEvent:FireClient(Player, "AdminReports", ReportList(), REPORT_REASONS)
end

local function BroadcastReports()
	for _, p in ipairs(Players:GetPlayers()) do
		if IsAdmin(p) then
			PushReports(p)
		end
	end
end

-------------------------------------------------------------------------------
-- 6. THE WEBHOOK BIT
-------------------------------------------------------------------------------
--[[
	Everything in this section is the part to write. It is not wired into the
	live script - adding it there is the job.

	Set WEBHOOK_URL to a RELAY you control, not to discord.com directly.
	Roblox server IPs are blocked by Discord and will get a flat 403.
--]]

local WEBHOOK_URL = "" -- e.g. "https://your-relay.example/report"

local function ReportToPayload(report)
	--[[
		Shaped as a Discord embed. Adjust to whatever your relay expects; if
		the relay forwards verbatim then this is the Discord format.

		Note may be "" - either because the reporter left it blank or because
		filtering failed and it was deliberately blanked. Both are fine to
		show as "none".
	--]]
	local fields = {
		{name = "Booth", value = tostring(report.BoothIndex), inline = true},
		{name = "Reason", value = tostring(report.Reason), inline = true},
		{name = "Owner", value = string.format("%s (%d)",
			tostring(report.AgainstName), tonumber(report.Against) or 0), inline = false},
		{name = "Reported by", value = string.format("%s (%d)",
			tostring(report.ByName), tonumber(report.By) or 0), inline = false},
		{name = "Booth text", value = (report.Text ~= "" and report.Text) or "(blank)", inline = false},
		{name = "Note", value = (report.Note ~= "" and report.Note) or "(none)", inline = false},
	}

	return {
		username = "Booth Reports",
		embeds = {
			{
				title = "Report #" .. tostring(report.Id),
				color = 15158332, -- red
				fields = fields,
				footer = {text = "Image asset: " .. tostring(report.Image)},
				timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ", report.Time),
			},
		},
	}
end

--[[
	Fire and forget.

	spawn() because PostAsync yields and must not hold up the player who
	pressed the button. pcall() because an HTTP failure must not take out
	HandleReport, which has already stored the report by this point - the
	report surviving matters more than the notification.
--]]
local function SendReportWebhook(report)
	if WEBHOOK_URL == "" then
		return
	end

	spawn(function()
		local ok, err = pcall(function()
			HttpService:PostAsync(
				WEBHOOK_URL,
				HttpService:JSONEncode(ReportToPayload(report)),
				Enum.HttpContentType.ApplicationJson
			)
		end)

		if not ok then
			-- Worth a warn, not worth retrying: the report is already in the
			-- queue and staff will see it in the panel regardless.
			warn("[Report] Webhook failed: " .. tostring(err))
		end
	end)
end

-------------------------------------------------------------------------------
-- 7. Filing a report
-------------------------------------------------------------------------------
--[[
	This is the one admin-adjacent path an ordinary player can take, so it is
	the one that has to be hardest to abuse:

	  * rate limited per player
	  * the queue is capped, so it cannot be used to fill the DataStore
	  * you cannot report an unclaimed booth, your own booth, or the same booth
	    twice while the first report is still open
	  * the reason has to be one of the fixed list, the free text note is
	    filtered like any other player text

	Returns nil on success, or a string explaining the refusal.
--]]
local function HandleReport(Player, data)
	if type(data) ~= "table" then
		return "Bad report."
	end

	local now = tick()
	local last = LastReport[Player.UserId]
	if last and (now - last) < REPORT_COOLDOWN then
		return "You just sent one, give it a moment."
	end

	if #Reports >= MAX_REPORTS then
		return "The report queue is full, staff are on it."
	end

	local booth = BoothByIndex(data.Booth)
	if not booth then
		return "That booth is not there any more."
	end

	local owner = booth.Display.BoothOwner.Value
	if not owner then
		return "Nobody has claimed that booth."
	end
	if owner == Player then
		return "That is your own booth."
	end

	-- One open report per booth per reporter.
	for _, r in ipairs(Reports) do
		if r.BoothIndex == BoothIndex[booth] and r.By == Player.UserId then
			return "You have already reported that booth."
		end
	end

	-- Anything not on the fixed list becomes "Other" rather than being trusted.
	local reason = CleanText(data.Reason, 40)
	local knownReason = false
	for _, r in ipairs(REPORT_REASONS) do
		if r == reason then
			knownReason = true
			break
		end
	end
	if not knownReason then
		reason = REPORT_REASONS[#REPORT_REASONS]
	end

	local note = CleanText(data.Note, 120)
	if note ~= "" and FILTER_TEXT then
		local filtered
		local ok = pcall(function()
			filtered = TextService:FilterStringAsync(note, Player.UserId):GetChatForUserAsync(Player.UserId)
		end)
		if ok and type(filtered) == "string" then
			note = filtered
		else
			-- Never put unfiltered player text in front of staff.
			note = ""
		end
	end

	LastReport[Player.UserId] = now
	NextReportId = NextReportId + 1

	local report = {
		Id = NextReportId,
		BoothIndex = BoothIndex[booth],
		Against = owner.UserId,
		AgainstName = owner.Name,
		By = Player.UserId,
		ByName = Player.Name,
		Reason = reason,
		Note = note,
		Time = os.time(),
		Text = booth.Display.SurfaceGui.TextLabel.Text,
		Image = booth.Display.SurfaceGui.ImageLabel.Image,
	}

	Reports[#Reports + 1] = report

	SaveReports()
	BroadcastReports()

	-----------------------------------------------------------------------
	-- WEBHOOK HOOK POINT 1: a report was filed
	--
	-- Deliberately AFTER the report is stored and the panel has been told,
	-- so a dead webhook cannot cost anyone a report. Non-blocking.
	-----------------------------------------------------------------------
	SendReportWebhook(report)

	-- Anyone on shift gets a nudge, even with the panel shut.
	for _, p in ipairs(Players:GetPlayers()) do
		if IsAdmin(p) then
			RemoteEvent:FireClient(p, "AdminLog", "New report on booth "
				.. tostring(BoothIndex[booth]) .. " (" .. reason .. ")")
		end
	end

	return nil
end

-------------------------------------------------------------------------------
-- 8. What the report window offers a player
-------------------------------------------------------------------------------
--[[
	An empty list has two very different causes, and saying "no claimed booths"
	for both was actively misleading: testing the button on your own booth,
	alone in the server, reported that nothing was claimed when something
	obviously was.

	So the count of claimed booths goes out alongside the list, and the window
	can tell "nobody has set one up yet" apart from "the only one is yours".
--]]
local function PushReportTargets(Player)
	local list = {}
	local claimed = 0

	for _, booth in ipairs(Booths:GetChildren()) do
		if IsBooth(booth) then
			local owner = booth.Display.BoothOwner.Value
			if owner then
				claimed = claimed + 1
				if owner ~= Player then
					list[#list + 1] = {
						Booth = BoothIndex[booth],
						OwnerName = owner.Name,
						Text = booth.Display.SurfaceGui.TextLabel.Text,
					}
				end
			end
		end
	end

	table.sort(list, function(a, b)
		return (a.Booth or 0) < (b.Booth or 0)
	end)

	RemoteEvent:FireClient(Player, "ReportTargets", list, REPORT_REASONS, claimed)
end

-------------------------------------------------------------------------------
-- 9. Remote handling
-------------------------------------------------------------------------------
--[[
	These live inside the one big RemoteEvent.OnServerEvent handler in the real
	script, alongside every other branch. Shown here on their own.
--]]

RemoteEvent.OnServerEvent:Connect(function(Player, Argument, Argument2)

	-- Open to everyone: this is how a normal player finds a booth to report.
	--
	-- Deliberately NOT on the general action cooldown. Opening the window and
	-- then sending are two remotes a second apart at most, so sharing the one
	-- second budget meant the send was silently swallowed and the button looked
	-- broken. Filing is rate limited properly by REPORT_COOLDOWN inside
	-- HandleReport, which is the limit that actually matters.
	if Argument == "ReportOpen" then
		PushReportTargets(Player)
		return

	elseif Argument == "ReportBooth" then
		local err = HandleReport(Player, Argument2)
		if err then
			RemoteEvent:FireClient(Player, "ReportError", err)
		else
			RemoteEvent:FireClient(Player, "ReportOk", "Sent to the moderators. Thanks.")
		end
		return

	-- Staff only, from the Reports page of the admin panel.
	elseif Argument == "AdminResolveReport" then
		if not IsAdmin(Player) then
			return
		end
		if not CheckStaffCooldown(Player) then
			return
		end

		local removed = RemoveReport(Argument2)
		if not removed then
			Notify(Player, "That report is already gone.", true)
			return
		end

		SaveReports()
		BroadcastReports()

		-------------------------------------------------------------------
		-- WEBHOOK HOOK POINT 2: a report was closed
		--
		-- Optional. Only useful if you want the Discord side to show that
		-- something has been dealt with. `removed` is the full report row,
		-- and Player is the staff member who closed it.
		-------------------------------------------------------------------
		-- SendResolvedWebhook(removed, Player)

		LogAction(Player, "closed report #" .. tostring(removed.Id)
			.. " against " .. tostring(removed.AgainstName))
		Notify(Player, "Report closed.", false)
		return

	-- Walks the staff member to the booth a report is about.
	elseif Argument == "AdminGotoReport" then
		if not IsAdmin(Player) then
			return
		end

		local booth = BoothByIndex(Argument2)
		if not booth then
			Notify(Player, "That booth is gone.", true)
			return
		end

		local root = Player.Character and
			(Player.Character:FindFirstChild("HumanoidRootPart")
				or Player.Character:FindFirstChild("Torso"))
		if not root then
			Notify(Player, "You have no character right now.", true)
			return
		end

		root.CFrame = booth.Display.CFrame * CFrame.new(0, 0, 8)
		Notify(Player, "Moved to booth " .. tostring(Argument2) .. ".", false)
		return
	end
end)

--[[
===============================================================================
  DEPENDENCIES

  Referenced above but defined elsewhere in src/Server.server.lua:

    IsAdmin(Player)              Mod and up
    CheckStaffCooldown(Player)   short per-staff rate limit, answers when it
                                 refuses rather than going quiet
    Notify(Player, msg, bad)     status line in the admin panel
    LogAction(actor, msg)        tells the other staff what was done
    CleanText(raw, limit)        trims, flattens newlines, truncates
    FindPlayerByUserId(id)       nil if they have left
    BoothByIndex(index)          booth model from its stable index
    IsBooth(model)               shape check
    Booths                       Workspace.Booths folder
    BoothIndex[booth]            booth -> stable number

  CLIENT SIDE

  The player-facing window and the staff Reports page are in
  src/Client.client.lua. The messages between them:

    server -> client   ReportTargets    list, reasons, claimedCount
                       ReportOk         message
                       ReportError      message
                       AdminReports     queue, reasons
                       AdminLog         one-line nudge

    client -> server   ReportOpen
                       ReportBooth      {Booth, Reason, Note}
                       AdminResolveReport  reportId
                       AdminGotoReport     boothIndex

  A webhook needs none of this. Everything you want happens server side in
  HandleReport.
===============================================================================
]]
