--[[
	Builds a fake place, runs Server.server.lua in it, then runs
	Client.client.lua against the same RemoteEvent, and hands the test file a
	small API for driving both sides.

	Two players exist by default:
	    thugshaker  49603   hard coded Owner
	    ywinfe     181869   Admin from the seeded whitelist
	and tests add ordinary players as they need them.
--]]

local mock = dofile(TOOLS .. "/mock_roblox.lua")

local Instance_new = mock.newInstance
local Signal = mock.Signal

mock.errors = {}
mock.kicks = {}
mock.fired = {}
mock.verbose = false

local H = {mock = mock}

--[[
	Every body ever passed to spawn().

	The mock has no threads, so a loop that polls for something and wait()s
	between attempts runs once and gives up, which made those loops look
	permanently broken. H.rerunSpawned() runs them again after a test has set
	the world up - the honest substitute for Roblox resuming the thread.
--]]
H.spawned = {}

function H.rerunSpawned()
	for _, fn in ipairs(H.spawned) do
		pcall(fn)
	end
end

-------------------------------------------------------------------------------
-- Roblox globals
-------------------------------------------------------------------------------

local scheduled = {}


function H.installGlobals()
	_G.Instance = {
		new = function(className, parent)
			local inst = Instance_new(className)
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
	}

	-- Enums are only ever assigned and compared, never inspected, so a table
	-- that invents members on demand is indistinguishable from the real thing.
	local enumCache = {}
	_G.Enum = setmetatable({}, {
		__index = function(_, group)
			if not enumCache[group] then
				enumCache[group] = setmetatable({}, {
					__index = function(t, name)
						local v = {Name = name, Group = group}
						rawset(t, name, v)
						return v
					end,
				})
			end
			return enumCache[group]
		end,
	})

	local function vec2(x, y)
		return {X = x or 0, Y = y or 0}
	end
	_G.Vector2 = {new = vec2}

	local Vector3_mt = {}
	Vector3_mt.__index = Vector3_mt
	local function vec3(x, y, z)
		return setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, Vector3_mt)
	end
	-- Real Vector3s add, and code that positions things relative to a player
	-- leans on it, so the mock has to as well.
	Vector3_mt.__add = function(a, b)
		return vec3((a.X or 0) + (b.X or 0), (a.Y or 0) + (b.Y or 0), (a.Z or 0) + (b.Z or 0))
	end
	Vector3_mt.__sub = function(a, b)
		return vec3((a.X or 0) - (b.X or 0), (a.Y or 0) - (b.Y or 0), (a.Z or 0) - (b.Z or 0))
	end
	_G.Vector3 = {new = vec3}

	local CFrame_mt = {}
	CFrame_mt.__index = CFrame_mt
	CFrame_mt.__mul = function(a, b)
		return setmetatable({
			X = a.X + (b.X or 0), Y = a.Y + (b.Y or 0), Z = a.Z + (b.Z or 0),
			Position = vec3(a.X, a.Y, a.Z),
		}, CFrame_mt)
	end
	_G.CFrame = {
		new = function(x, y, z)
			local c = setmetatable({X = x or 0, Y = y or 0, Z = z or 0}, CFrame_mt)
			c.Position = vec3(x, y, z)
			return c
		end,
	}

	_G.UDim = {new = function(s, o) return {Scale = s, Offset = o} end}
	_G.UDim2 = {
		new = function(xs, xo, ys, yo)
			return {X = {Scale = xs, Offset = xo}, Y = {Scale = ys, Offset = yo}}
		end,
	}
	_G.Color3 = {
		fromRGB = function(r, g, b) return {R = r, G = g, B = b} end,
		new = function(r, g, b) return {R = r, G = g, B = b} end,
	}
	_G.BrickColor = {new = function(n) return {Name = n} end}
	_G.ColorSequence = {new = function(v) return {Keypoints = v} end}
	_G.ColorSequenceKeypoint = {new = function(t, c) return {Time = t, Value = c} end}
	_G.NumberSequence = {new = function(v) return {Value = v} end}
	_G.TweenInfo = {new = function(...) return {...} end}

	--[[
		require() on a ModuleScript returns whatever the module returned. The
		mock stores that on the instance as _module, so code that requires a
		module and reads its API can be exercised.
	--]]
	_G.require = function(target)
		if type(target) == "table" then
			local mod = rawget(target, "_module")
			if mod ~= nil then
				return mod
			end
		end
		error("require: nothing to return", 0)
	end

	_G.typeof = function(v)
		if type(v) == "table" and rawget(v, "ClassName") then
			return "Instance"
		end
		return type(v)
	end

	--[[
		A clock the tests control.

		Real time barely moves between two statements, so anything rate limited
		would refuse the second call and the test would be measuring the
		cooldown rather than the behaviour. Every tick() nudges the clock on a
		little, which is enough for consecutive actions to be treated as
		separate, and H.advance() jumps it when a test wants to prove a cooldown
		really does bite.
	--]]
	H.clock = 1000
	_G.tick = function()
		H.clock = H.clock + 0.2
		return H.clock
	end

	_G.wait = function(n) return n or 0 end
	_G.time = _G.tick
	_G.warn = function(...)
		if mock.verbose then
			local bits = {}
			for i = 1, select("#", ...) do
				bits[i] = tostring(select(i, ...))
			end
			print("  [warn] " .. table.concat(bits, " "))
		end
	end

	-- spawn and delay run the body immediately rather than later, so a test
	-- sees the result without needing a scheduler. Anything that must not run
	-- inline is scheduled instead and drained by H.drain().
	_G.spawn = function(fn)
		scheduled[#scheduled + 1] = fn
		H.spawned[#H.spawned + 1] = fn
	end
	_G.delay = function(_t, fn)
		scheduled[#scheduled + 1] = fn
	end

	if not math.clamp then
		math.clamp = function(v, lo, hi)
			if v < lo then return lo end
			if v > hi then return hi end
			return v
		end
	end
	if not table.find then
		table.find = function(t, needle)
			for i, v in ipairs(t) do
				if v == needle then return i end
			end
			return nil
		end
	end
end

-- Jump the clock, for tests that want a cooldown to have expired.
function H.advance(seconds)
	H.clock = H.clock + (seconds or 60)
end

function H.drain(limit)
	local n = 0
	while #scheduled > 0 and n < (limit or 200) do
		local fn = table.remove(scheduled, 1)
		local ok, err = pcall(fn)
		if not ok then
			mock.errors[#mock.errors + 1] = tostring(err)
			if mock.verbose then
				print("  [spawn error] " .. tostring(err))
			end
		end
		n = n + 1
	end
	return n
end

-------------------------------------------------------------------------------
-- The place
-------------------------------------------------------------------------------

function H.buildPlace()
	local services = {}

	local function service(className, name)
		local s = Instance_new(className, name or className)
		services[name or className] = s
		return s
	end

	local Workspace = service("Workspace", "Workspace")
	local ReplicatedStorage = service("ReplicatedStorage", "ReplicatedStorage")
	local ServerStorage = service("ServerStorage", "ServerStorage")
	local ServerScriptService = service("ServerScriptService", "ServerScriptService")
	local StarterGui = service("StarterGui", "StarterGui")
	local Lighting = service("Lighting", "Lighting")
	local PlayersService = service("Players", "Players")

	PlayersService._list = {}
	PlayersService.PlayerAdded = Signal.new()
	PlayersService.PlayerRemoving = Signal.new()
	PlayersService.GetPlayers = function(self)
		local out = {}
		for i, p in ipairs(self._list) do
			out[i] = p
		end
		return out
	end
	PlayersService.GetUserThumbnailAsync = function(_self, userId)
		return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId), true
	end

	-- HttpService. Tests swap _handler to decide what the proxy "returns",
	-- which is how the avatar path gets exercised both working and broken.
	local Http = service("HttpService", "HttpService")
	Http._handler = nil
	Http._calls = {}
	Http._posts = {}
	Http.PostAsync = function(self, url, body, contentType)
		self._posts[#self._posts + 1] = {Url = url, Body = body}
		if self._postFail then
			error("HTTP 500", 0)
		end
		return ""
	end
	Http.GetAsync = function(self, url)
		self._calls[#self._calls + 1] = url
		if not self._handler then
			error("HTTP 403 (Trust check failed)", 0)
		end
		return self._handler(url)
	end
	Http.JSONDecode = function(_self, text)
		return H.jsonDecode(text)
	end
	Http.JSONEncode = function(_self, value)
		return H.jsonEncode(value)
	end

	-- DataStores, in memory, with the same async-ish surface.
	local DSS = service("DataStoreService", "DataStoreService")
	DSS._stores = {}
	DSS._fail = false
	DSS.GetDataStore = function(self, name)
		if self._fail then
			error("DataStore unavailable", 0)
		end
		if not self._stores[name] then
			local data = {}
			self._stores[name] = {
				_data = data,
				GetAsync = function(_s, key)
					return data[key]
				end,
				SetAsync = function(_s, key, value)
					data[key] = value
					return value
				end,
				UpdateAsync = function(_s, key, fn)
					data[key] = fn(data[key])
					return data[key]
				end,
				RemoveAsync = function(_s, key)
					local old = data[key]
					data[key] = nil
					return old
				end,
			}
		end
		return self._stores[name]
	end

	local MPS = service("MarketplaceService", "MarketplaceService")
	MPS._owned = {}
	MPS.PromptPurchaseFinished = Signal.new()
	MPS.PromptGamePassPurchaseFinished = Signal.new()
	MPS.PlayerOwnsAsset = function(self, player, id)
		local byPlayer = self._owned[player]
		return byPlayer ~= nil and byPlayer[id] == true
	end
	MPS.UserOwnsGamePassAsync = function(self, userId, id)
		for p, owned in pairs(self._owned) do
			if p.UserId == userId then
				return owned[id] == true
			end
		end
		return false
	end
	MPS.PromptPurchase = function(self, player, id)
		self._lastPrompt = {Player = player, Id = id}
	end
	MPS.PromptGamePassPurchase = MPS.PromptPurchase

	local TS = service("TextService", "TextService")
	TS._fail = false
	TS.FilterStringAsync = function(self, text)
		if self._fail then
			error("filter unavailable", 0)
		end
		return {
			GetChatForUserAsync = function()
				-- Stand-in for real filtering: enough to prove the code path
				-- routes text through it rather than around it.
				return (text:gsub("badword", "#######"))
			end,
		}
	end

	local game = Instance_new("DataModel", "game")
	game.CreatorType = _G.Enum.CreatorType.User
	game.CreatorId = 1
	game.GetService = function(_self, name)
		local s = services[name]
		if not s then
			s = service(name, name)
		end
		return s
	end
	game.BindToClose = function(_self, fn)
		H._bindToClose = fn
	end
	game.PlaceId = 1

	_G.game = game
	_G.workspace = Workspace
	_G.Workspace = Workspace

	H.services = services
	H.game = game
	H.Workspace = Workspace
	H.ReplicatedStorage = ReplicatedStorage
	H.ServerStorage = ServerStorage
	H.StarterGui = StarterGui
	H.Players = PlayersService
	H.Http = Http
	H.DataStores = DSS
	H.Marketplace = MPS
	H.TextService = TS
	H.Lighting = Lighting

	-- The remote both halves talk over.
	local remote = Instance_new("RemoteEvent", "RemoteEvent")
	remote.Parent = ReplicatedStorage
	rawset(remote, "_clientSignals", {})
	H.remote = remote

	-- Booths folder, filled by H.addBooth.
	local booths = Instance_new("Folder", "Booths")
	booths.Parent = Workspace
	H.booths = booths

	return H
end

-- One booth with every part the server insists on.
function H.addBooth(index)
	local booth = Instance_new("Model", "Booth")

	local display = Instance_new("Part", "Display")
	display.Position = _G.Vector3.new(index * 10, 0, 0)
	display.CFrame = _G.CFrame.new(index * 10, 0, 0)
	display.Parent = booth

	local sg = Instance_new("SurfaceGui", "SurfaceGui")
	sg.Parent = display
	local img = Instance_new("ImageLabel", "ImageLabel")
	img.Image = ""
	img.Parent = sg
	local txt = Instance_new("TextLabel", "TextLabel")
	txt.Text = ""
	txt.Parent = sg

	local att = Instance_new("Attachment", "Attachment")
	att.Parent = display
	local prompt = Instance_new("ProximityPrompt", "ProximityPrompt")
	prompt.Enabled = true
	prompt.Parent = att

	local owner = Instance_new("ObjectValue", "BoothOwner")
	owner.Value = nil
	owner.Parent = display

	local plate = Instance_new("Part", "PartNamePlayer")
	plate.Parent = booth
	local psg = Instance_new("SurfaceGui", "SurfaceGui")
	psg.Parent = plate
	local plabel = Instance_new("TextLabel", "TextLabel")
	plabel.Text = ""
	plabel.Parent = psg

	booth.Parent = H.booths
	return booth
end

function H.buildCharacter(player)
	local char = Instance_new("Model", player.Name)
	local hum = Instance_new("Humanoid", "Humanoid")
	hum.Parent = char
	local root = Instance_new("Part", "HumanoidRootPart")
	root.CFrame = _G.CFrame.new(0, 0, 0)
	root.Position = _G.Vector3.new(0, 0, 0)
	root.Anchored = false
	root.Parent = char
	local head = Instance_new("Part", "Head")
	head.Parent = char

	char.Parent = H.Workspace
	player.Character = char
	if player.CharacterAdded then
		player.CharacterAdded:Fire(char)
	end
	return char
end
mock.buildCharacter = H.buildCharacter

function H.addPlayer(name, userId, withCharacter)
	local p = Instance_new("Player", name)
	p.UserId = userId
	p.Chatted = Signal.new()
	p.CharacterAdded = Signal.new()
	p.Character = nil

	local backpack = Instance_new("Backpack", "Backpack")
	backpack.Parent = p
	local gear = Instance_new("StarterGear", "StarterGear")
	gear.Parent = p

	-- Real players sit under the Players service, and the scripts check
	-- Player.Parent to tell "still here" from "already left".
	p.Parent = H.Players

	table.insert(H.Players._list, p)

	-- Each player gets their own client-side signal on the remote.
	rawget(H.remote, "_clientSignals")[p] = Signal.new()

	if withCharacter ~= false then
		H.buildCharacter(p)
	end

	H.Players.PlayerAdded:Fire(p)
	return p
end

function H.removePlayer(p)
	for i, q in ipairs(H.Players._list) do
		if q == p then
			table.remove(H.Players._list, i)
			break
		end
	end
	H.Players.PlayerRemoving:Fire(p)
	p.Parent = nil
end

-- Everything the server sent this player, newest last.
function H.sentTo(player)
	local out = {}
	for _, row in ipairs(mock.fired) do
		if row.To == player then
			out[#out + 1] = row.Args
		end
	end
	return out
end

function H.lastSent(player, kind)
	local hit = nil
	for _, row in ipairs(mock.fired) do
		if row.To == player and row.Args[1] == kind then
			hit = row.Args
		end
	end
	return hit
end

function H.clearSent()
	mock.fired = {}
end

-- Pretend to be `player` pressing something: fires the remote server-side.
function H.asPlayer(player, ...)
	H.remote.OnServerEvent:Fire(player, ...)
end

-------------------------------------------------------------------------------
-- Minimal JSON, for the proxy replies
-------------------------------------------------------------------------------

function H.jsonDecode(text)
	local pos = 1

	local function skip()
		while pos <= #text and text:sub(pos, pos):match("[%s]") do
			pos = pos + 1
		end
	end

	local parseValue

	local function parseString()
		pos = pos + 1
		local out = {}
		while pos <= #text do
			local c = text:sub(pos, pos)
			if c == '"' then
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				pos = pos + 1
				out[#out + 1] = text:sub(pos, pos)
				pos = pos + 1
			else
				out[#out + 1] = c
				pos = pos + 1
			end
		end
		error("unterminated string in JSON")
	end

	local function parseNumber()
		local s = pos
		while pos <= #text and text:sub(pos, pos):match("[%d%.%-%+eE]") do
			pos = pos + 1
		end
		return tonumber(text:sub(s, pos - 1))
	end

	parseValue = function()
		skip()
		local c = text:sub(pos, pos)
		if c == "{" then
			pos = pos + 1
			local obj = {}
			skip()
			if text:sub(pos, pos) == "}" then
				pos = pos + 1
				return obj
			end
			while true do
				skip()
				local k = parseString()
				skip()
				pos = pos + 1 -- colon
				obj[k] = parseValue()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "}" then
					return obj
				end
			end
		elseif c == "[" then
			pos = pos + 1
			local arr = {}
			skip()
			if text:sub(pos, pos) == "]" then
				pos = pos + 1
				return arr
			end
			while true do
				arr[#arr + 1] = parseValue()
				skip()
				local d = text:sub(pos, pos)
				pos = pos + 1
				if d == "]" then
					return arr
				end
			end
		elseif c == '"' then
			return parseString()
		elseif text:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif text:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif text:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		else
			return parseNumber()
		end
	end

	return parseValue()
end

function H.jsonEncode(v)
	local t = type(v)
	if t == "string" then
		return '"' .. v:gsub('"', '\\"') .. '"'
	elseif t == "number" or t == "boolean" then
		return tostring(v)
	elseif t == "table" then
		local isArray = (#v > 0)
		local bits = {}
		if isArray then
			for _, item in ipairs(v) do
				bits[#bits + 1] = H.jsonEncode(item)
			end
			return "[" .. table.concat(bits, ",") .. "]"
		end
		for k, item in pairs(v) do
			bits[#bits + 1] = '"' .. tostring(k) .. '":' .. H.jsonEncode(item)
		end
		return "{" .. table.concat(bits, ",") .. "}"
	end
	return "null"
end

-------------------------------------------------------------------------------
-- Running the scripts
-------------------------------------------------------------------------------

function H.runServer()
	local src = io.open(SRC .. "/Server.server.lua"):read("*a")
	local chunk, err = loadstring(src, "@Server.server.lua")
	if not chunk then
		error("server would not load: " .. tostring(err))
	end

	-- `script` is what a Roblox Script sees as itself.
	local scriptObj = Instance_new("Script", "Server")
	scriptObj.Parent = H.services.ServerScriptService
	_G.script = scriptObj

	chunk()
	H.drain()
end

-- The client needs a StarterGui.MainUI shaped like the real one, because it
-- clones the existing widgets rather than building them from nothing.
function H.buildMainUI()
	local gui = Instance_new("ScreenGui", "MainUI")
	gui.Parent = H.StarterGui

	local frame = Instance_new("Frame", "Frame")
	frame.Visible = false
	frame.Parent = gui

	--[[
		The real geometry out of the place file, not invented numbers.

		These used to be {0.5, 0.1} at {0.9, 0.9}, which is nothing like the
		actual ToggleButton. Every HUD calculation the client makes is derived
		from this button, so testing against made-up dimensions meant the tests
		could not see sizing bugs at all - and one shipped twice.

		    Frame        Size {0.400, 0.400}  Pos {0.500, 0.500}
		    TextButton   Size {0.107, 0.071}  Pos {0.007, 0.550}
		    ChangeText   Size {0.515, 0.125}  Pos {0.500, 0.734}
	--]]
	local function styledButton(name, parent, size, pos)
		local b = Instance_new("TextButton", name)
		b.Text = ""
		b.Size = size or _G.UDim2.new(0.515, 0, 0.125, 0)
		b.Position = pos or _G.UDim2.new(0.5, 0, 0.734, 0)
		local label = Instance_new("TextLabel", "TextLabel")
		label.Text = ""
		label.Parent = b
		Instance_new("UICorner", "UICorner").Parent = b
		Instance_new("UIStroke", "UIStroke").Parent = b
		b.Parent = parent
		return b
	end

	styledButton("ChangeText", frame)
	styledButton("UnclaimBooth", frame)

	local box = Instance_new("TextBox", "TextBox")
	box.Text = ""
	box.Parent = frame

	local title = Instance_new("TextLabel", "TextLabel")
	title.Text = "Booth"
	title.Parent = frame

	Instance_new("UIListLayout", "UIListLayout").Parent = frame
	Instance_new("UICorner", "UICorner").Parent = frame
	Instance_new("UIStroke", "UIStroke").Parent = frame

	local toggle = styledButton(
		"TextButton", gui,
		_G.UDim2.new(0.107, 0, 0.071, 0),
		_G.UDim2.new(0.007, 0, 0.550, 0)
	)

	H.gui = gui
	return gui
end

function H.runClient(player)
	local src = io.open(SRC .. "/Client.client.lua"):read("*a")
	local chunk, err = loadstring(src, "@Client.client.lua")
	if not chunk then
		error("client would not load: " .. tostring(err))
	end

	local gui = H.buildMainUI()

	local scriptObj = Instance_new("LocalScript", "Client")
	scriptObj.Parent = gui
	_G.script = scriptObj

	-- The client reads Players.LocalPlayer and fires the remote as itself.
	H.Players.LocalPlayer = player
	mock.localPlayer = player

	-- OnClientEvent has to be this player's own signal.
	rawset(H.remote, "OnClientEvent", rawget(H.remote, "_clientSignals")[player])

	chunk()
	H.drain()

	H.clientGui = gui
	return gui
end

-- Find a descendant by name, for asserting on what the UI actually built.
function H.findIn(root, name)
	if root.Name == name then
		return root
	end
	for _, c in ipairs(root:GetChildren()) do
		local hit = H.findIn(c, name)
		if hit then
			return hit
		end
	end
	return nil
end

return H
