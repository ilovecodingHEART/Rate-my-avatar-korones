--[[
	A small stand-in for the Roblox API, enough to actually run the booth
	server and client scripts outside Studio.

	The point is not to emulate Roblox. It is to catch the mistakes that a
	syntax check cannot see: a nil field, a renamed function called from the
	other half, a remote argument that arrives in the wrong order, a rank check
	written backwards. Those all show up the moment the code really runs, and
	none of them show up in a parse.

	Instances are plain tables with a metatable that makes unknown property
	writes stick and unknown reads return nil, which is close enough to a
	Roblox instance for UI construction code. Anything the scripts genuinely
	depend on - FindFirstChild, GetChildren, signals, RemoteEvent both ways,
	DataStores, MarketplaceService - is real.
--]]

local M = {}

-------------------------------------------------------------------------------
-- Signals
-------------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({handlers = {}}, Signal)
end

function Signal:Connect(fn)
	table.insert(self.handlers, fn)
	local conn = {}
	function conn:Disconnect()
		for i, h in ipairs(self.owner.handlers) do
			if h == self.fn then
				table.remove(self.owner.handlers, i)
				break
			end
		end
	end
	conn.owner = self
	conn.fn = fn
	return conn
end

Signal.connect = Signal.Connect

function Signal:Fire(...)
	-- Copied first so a handler that disconnects mid-fire cannot skip another.
	local snapshot = {}
	for i, h in ipairs(self.handlers) do
		snapshot[i] = h
	end
	for _, h in ipairs(snapshot) do
		local ok, err = pcall(h, ...)
		if not ok then
			M.errors[#M.errors + 1] = tostring(err)
			if M.verbose then
				print("  [signal error] " .. tostring(err))
			end
		end
	end
end

M.Signal = Signal

-------------------------------------------------------------------------------
-- Instances
-------------------------------------------------------------------------------

local Instance_mt = {}

local function newInstance(className, name)
	local self = {
		ClassName = className,
		Name = name or className,
		_children = {},
		_parent = nil,
		Archivable = true,
	}

	self.ChildAdded = Signal.new()
	self.ChildRemoved = Signal.new()
	self.AncestryChanged = Signal.new()

	-- GuiObjects are measured by layout code, so these have to be real numbers
	-- rather than nil or the first arithmetic on them throws.
	self.AbsoluteSize = {X = 800, Y = 600}
	self.AbsolutePosition = {X = 0, Y = 0}
	self.Visible = true

	-- Buttons and boxes need these to exist whether or not anything listens.
	if className == "TextButton" or className == "ImageButton" then
		self.MouseButton1Click = Signal.new()
		self.MouseButton1Down = Signal.new()
		self.MouseEnter = Signal.new()
		self.MouseLeave = Signal.new()
		self.Activated = Signal.new()
	end
	if className == "TextBox" then
		self.FocusLost = Signal.new()
		self.Focused = Signal.new()
	end
	if className == "ProximityPrompt" then
		self.Triggered = Signal.new()
	end
	if className == "RemoteEvent" then
		self.OnServerEvent = Signal.new()
		self.OnClientEvent = Signal.new()
	end
	if className == "Humanoid" then
		self.Health = 100
		self.MaxHealth = 100
		self.WalkSpeed = 16
		self.JumpPower = 50
		self.Died = Signal.new()
	end

	return setmetatable(self, Instance_mt)
end

Instance_mt.__index = function(t, k)
	if k == "Parent" then
		return rawget(t, "_parent")
	end

	local v = rawget(t, k)
	if v ~= nil then
		return v
	end

	local methods = M.InstanceMethods
	if methods[k] then
		return methods[k]
	end

	-- Roblox finds children by name as a property. Real code leans on this,
	-- e.g. Booth.Display.SurfaceGui.TextLabel.
	for _, c in ipairs(rawget(t, "_children")) do
		if c.Name == k then
			return c
		end
	end

	return nil
end

Instance_mt.__newindex = function(t, k, v)
	if k == "Parent" then
		local old = rawget(t, "_parent")
		if old then
			for i, c in ipairs(rawget(old, "_children")) do
				if c == t then
					table.remove(rawget(old, "_children"), i)
					break
				end
			end
			old.ChildRemoved:Fire(t)
		end
		rawset(t, "_parent", v)
		if v then
			table.insert(rawget(v, "_children"), t)
			v.ChildAdded:Fire(t)
		end
		return
	end
	rawset(t, k, v)
end

Instance_mt.__tostring = function(t)
	return rawget(t, "Name") or "Instance"
end

local ISA = {
	TextButton = {"GuiObject", "GuiBase2d", "TextButton", "Instance"},
	TextLabel = {"GuiObject", "GuiBase2d", "TextLabel", "Instance"},
	TextBox = {"GuiObject", "GuiBase2d", "TextBox", "Instance"},
	ImageLabel = {"GuiObject", "GuiBase2d", "ImageLabel", "Instance"},
	Frame = {"GuiObject", "GuiBase2d", "Frame", "Instance"},
	ScrollingFrame = {"GuiObject", "GuiBase2d", "ScrollingFrame", "Frame", "Instance"},
	ScreenGui = {"ScreenGui", "LayerCollector", "Instance"},
	SurfaceGui = {"SurfaceGui", "LayerCollector", "Instance"},
	Part = {"BasePart", "Part", "Instance"},
	MeshPart = {"BasePart", "MeshPart", "Instance"},
	Model = {"Model", "Instance"},
	Folder = {"Folder", "Instance"},
	Tool = {"Tool", "Instance"},
	Player = {"Player", "Instance"},
	Humanoid = {"Humanoid", "Instance"},
	Decal = {"Decal", "Instance"},
	Sound = {"Sound", "Instance"},
	ObjectValue = {"ObjectValue", "ValueBase", "Instance"},
	StringValue = {"StringValue", "ValueBase", "Instance"},
	RemoteEvent = {"RemoteEvent", "Instance"},
	ProximityPrompt = {"ProximityPrompt", "Instance"},
	Backpack = {"Backpack", "Instance"},
}

M.InstanceMethods = {
	IsA = function(self, className)
		if self.ClassName == className then
			return true
		end
		local list = ISA[self.ClassName]
		if list then
			for _, c in ipairs(list) do
				if c == className then
					return true
				end
			end
		end
		return false
	end,

	FindFirstChild = function(self, name, recursive)
		for _, c in ipairs(rawget(self, "_children")) do
			if c.Name == name then
				return c
			end
		end
		if recursive then
			for _, c in ipairs(rawget(self, "_children")) do
				local hit = c:FindFirstChild(name, true)
				if hit then
					return hit
				end
			end
		end
		return nil
	end,

	WaitForChild = function(self, name)
		local hit = self:FindFirstChild(name)
		if not hit then
			error("WaitForChild would hang forever: " .. tostring(self.Name) .. "." .. tostring(name), 2)
		end
		return hit
	end,

	FindFirstChildOfClass = function(self, className)
		for _, c in ipairs(rawget(self, "_children")) do
			if c.ClassName == className then
				return c
			end
		end
		return nil
	end,

	FindFirstChildWhichIsA = function(self, className)
		for _, c in ipairs(rawget(self, "_children")) do
			if c:IsA(className) then
				return c
			end
		end
		return nil
	end,

	GetChildren = function(self)
		local out = {}
		for i, c in ipairs(rawget(self, "_children")) do
			out[i] = c
		end
		return out
	end,

	GetDescendants = function(self)
		local out = {}
		local function walk(node)
			for _, c in ipairs(rawget(node, "_children")) do
				out[#out + 1] = c
				walk(c)
			end
		end
		walk(self)
		return out
	end,

	IsDescendantOf = function(self, other)
		local cur = rawget(self, "_parent")
		while cur do
			if cur == other then
				return true
			end
			cur = rawget(cur, "_parent")
		end
		return false
	end,

	Destroy = function(self)
		self.Parent = nil
		rawset(self, "_destroyed", true)
	end,

	Clone = function(self)
		local copy = newInstance(self.ClassName, self.Name)
		for k, v in pairs(self) do
			if k ~= "_children" and k ~= "_parent" and type(v) ~= "function"
				and getmetatable(v) ~= Signal then
				rawset(copy, k, v)
			end
		end
		for _, c in ipairs(rawget(self, "_children")) do
			local cc = c:Clone()
			cc.Parent = copy
		end
		return copy
	end,

	GetPropertyChangedSignal = function(self, prop)
		local key = "_changed_" .. prop
		if not rawget(self, key) then
			rawset(self, key, Signal.new())
		end
		return rawget(self, key)
	end,

	SetAttribute = function(self, name, value)
		local a = rawget(self, "_attrs")
		if not a then
			a = {}
			rawset(self, "_attrs", a)
		end
		a[name] = value
	end,

	GetAttribute = function(self, name)
		local a = rawget(self, "_attrs")
		return a and a[name] or nil
	end,

	-- Player
	Kick = function(self, reason)
		M.kicks[#M.kicks + 1] = {Player = self, Reason = reason}
		rawset(self, "_kicked", reason or true)
	end,

	LoadCharacter = function(self)
		M.buildCharacter(self)
	end,

	FireClient = function(self, player, ...)
		local sig = rawget(self, "_clientSignals")
		if sig and sig[player] then
			sig[player]:Fire(...)
		end
		M.fired[#M.fired + 1] = {To = player, Args = {...}}
	end,

	FireServer = function(self, ...)
		self.OnServerEvent:Fire(M.localPlayer, ...)
	end,

	FireAllClients = function(self, ...)
		local sig = rawget(self, "_clientSignals")
		if sig then
			for _, s in pairs(sig) do
				s:Fire(...)
			end
		end
	end,
}

M.newInstance = newInstance

return M
