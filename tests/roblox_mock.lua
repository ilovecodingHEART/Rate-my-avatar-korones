-- Minimal Roblox mock so the booth server script can actually be executed.
local M = {}
local signals = {}

local function newSignal()
  local s = {handlers = {}}
  function s:Connect(fn) table.insert(s.handlers, fn); return {Disconnect=function() end} end
  s.Fire = function(...)
    -- tolerate both s:Fire(a,b) and s.Fire(a,b)
    local args = {...}
    local start = 1
    if args[1] == s then start = 2 end
    local pass = {}
    for i = start, select('#', ...) do pass[#pass+1] = args[i] end
    for _, fn in ipairs(s.handlers) do fn(table.unpack(pass)) end
  end
  return s
end
M.newSignal = newSignal

-- Instance -------------------------------------------------------------------
local Instance_mt = {}
Instance_mt.__newindex = function(t, k, v)
  if k == "Parent" then
    local old = rawget(t, "Parent")
    if old then
      local ok = rawget(old, "_kids")
      for i, c in ipairs(ok) do if c == t then table.remove(ok, i) break end end
    end
    rawset(t, "Parent", v)
    if v then table.insert(rawget(v, "_kids"), t) end
    return
  end
  rawset(t, k, v)
end
Instance_mt.__index = function(t, k)
  local kids = rawget(t, "_kids")
  if kids then for _, c in ipairs(kids) do if rawget(c,"Name") == k then return c end end end
  return rawget(Instance_mt, k)
end
function Instance_mt.FindFirstChild(self, n)
  for _, c in ipairs(rawget(self,"_kids") or {}) do if rawget(c,"Name") == n then return c end end
  return nil
end
function Instance_mt.IsA(self, c) return rawget(self,"ClassName") == c end
function Instance_mt.GetChildren(self)
  local out = {}
  for i, c in ipairs(rawget(self,"_kids") or {}) do out[i] = c end
  return out
end
function Instance_mt.WaitForChild(self, n) return Instance_mt.FindFirstChild(self, n) end

local function new(class, name, parent)
  local o = setmetatable({ClassName=class, Name=name, _kids={}, Value=nil}, Instance_mt)
  rawset(o, "Parent", parent)
  if parent then table.insert(rawget(parent,"_kids"), o) end
  return o
end
M.new = new

-- Globals --------------------------------------------------------------------
function M.install(env, opts)
  env.typeof = function(v)
    if type(v) == "table" and getmetatable(v) == Instance_mt then return "Instance" end
    return type(v)
  end
  env.warn = function(...)
    local p = {}
    for i=1,select('#',...) do p[#p+1] = tostring((select(i,...))) end
    table.insert(M.warnings, table.concat(p," "))
  end
  env.wait = function() end
  env.tick = function() M.clock = M.clock + (M.step or 0); return M.clock end
  env.delay = function(_, f) table.insert(M.delayed, f) end

  local Instance = {}
  function Instance.new(c) return new(c, c, nil) end
  env.Instance = Instance

  -- services
  local ReplicatedStorage = new("ReplicatedStorage","ReplicatedStorage")
  local remote = new("RemoteEvent","RemoteEvent",ReplicatedStorage)
  remote.OnServerEvent = newSignal()
  M.toClient = {}
  remote.FireClient = function(a1, a2, a3, a4)
    local plr, a, b
    if a1 == remote then plr, a, b = a2, a3, a4 else plr, a, b = a1, a2, a3 end
    table.insert(M.toClient, {plr=plr, a=a, b=b})
  end
  M.remote = remote

  local Workspace = new("Workspace","Workspace")
  local booths = new("Folder","Booths",Workspace)
  booths.ChildAdded = newSignal()
  M.booths = booths

  local Players = new("Players","Players")
  Players.PlayerAdded = newSignal()
  Players.PlayerRemoving = newSignal()
  Players.GetPlayers = function() return {} end
  M.Players = Players

  local TextService = {}
  TextService.FilterStringAsync = function(a1, a2, a3)
    local txt; if a1 == TextService then txt = a2 else txt = a1 end
    return {GetChatForUserAsync=function() return txt end}
  end

  local MPS = {}
  M.mps = {owns=false, calls={}, prompts={}, err=false}
  MPS.PlayerOwnsAsset = function(a1, a2, a3)
    local plr, id
    if a1 == MPS then plr, id = a2, a3 else plr, id = a1, a2 end
    table.insert(M.mps.calls, {api="PlayerOwnsAsset", id=id, user=rawget(plr,"Name")})
    if M.mps.err then error("http 500") end
    return M.mps.owns
  end
  MPS.UserOwnsGamePassAsync = function(a1, a2, a3)
    local uid, id
    if a1 == MPS then uid, id = a2, a3 else uid, id = a1, a2 end
    table.insert(M.mps.calls, {api="UserOwnsGamePassAsync", id=id, user=uid})
    if M.mps.err then error("http 500") end
    return M.mps.owns
  end
  MPS.PromptPurchase = function(a1, a2, a3)
    local id; if a1 == MPS then id = a3 else id = a2 end
    table.insert(M.mps.prompts, {api="PromptPurchase", id=id})
  end
  MPS.PromptGamePassPurchase = function(a1, a2, a3)
    local id; if a1 == MPS then id = a3 else id = a2 end
    table.insert(M.mps.prompts, {api="PromptGamePassPurchase", id=id})
  end
  MPS.PromptPurchaseFinished = newSignal()
  MPS.PromptGamePassPurchaseFinished = newSignal()
  M.MPS = MPS

  local map = {
    ReplicatedStorage=ReplicatedStorage, Workspace=Workspace, Players=Players,
    TextService=TextService, MarketplaceService=MPS,
  }
  env.game = {GetService=function(a1, a2)
    local n; if type(a1)=="string" then n=a1 else n=a2 end
    return map[n]
  end}
  env.workspace = Workspace
  return M
end

M.warnings = {}
M.delayed = {}
M.clock = 0
return M
