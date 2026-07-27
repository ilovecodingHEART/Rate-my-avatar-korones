-- Mock of just enough Roblox Studio to run the ReplaceBooths command-bar script.
local M = {}

-- Vector3 --------------------------------------------------------------------
local V3 = {}
V3.__index = V3
local function v3(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0}, V3) end
V3.__add = function(a,b) return v3(a.X+b.X, a.Y+b.Y, a.Z+b.Z) end
V3.__sub = function(a,b) return v3(a.X-b.X, a.Y-b.Y, a.Z-b.Z) end
V3.__mul = function(a,b)
  if type(b) == "number" then return v3(a.X*b, a.Y*b, a.Z*b) end
  if type(a) == "number" then return v3(b.X*a, b.Y*a, b.Z*a) end
  return v3(a.X*b.X, a.Y*b.Y, a.Z*b.Z)
end
V3.__unm = function(a) return v3(-a.X,-a.Y,-a.Z) end
V3.__eq = function(a,b) return a.X==b.X and a.Y==b.Y and a.Z==b.Z end
V3.__tostring = function(a) return string.format("(%.3f, %.3f, %.3f)", a.X,a.Y,a.Z) end
V3.__index = function(t,k)
  if k == "Magnitude" then return math.sqrt(t.X^2+t.Y^2+t.Z^2) end
  if k == "Unit" then
    local m = math.sqrt(t.X^2+t.Y^2+t.Z^2)
    return v3(t.X/m, t.Y/m, t.Z/m)
  end
  return rawget(V3, k)
end
M.v3 = v3

-- CFrame ---------------------------------------------------------------------
-- stored as position + 3x3 row-major rotation {r00..r22}
local CF = {}
local function cfnew(x,y,z, r)
  r = r or {1,0,0, 0,1,0, 0,0,1}
  return setmetatable({X=x,Y=y,Z=z,R=r}, CF)
end
local function cross(ax,ay,az,bx,by,bz)
  return ay*bz-az*by, az*bx-ax*bz, ax*by-ay*bx
end
local function norm(x,y,z)
  local m=math.sqrt(x*x+y*y+z*z); return x/m,y/m,z/m
end
-- CFrame.new(pos, lookAt)
local function cfLook(p, at)
  local fx,fy,fz = norm(at.X-p.X, at.Y-p.Y, at.Z-p.Z)   -- forward = look
  local ux,uy,uz = 0,1,0
  local rx,ry,rz = cross(fx,fy,fz, ux,uy,uz)            -- right = look x up
  rx,ry,rz = norm(rx,ry,rz)
  local nx,ny,nz = cross(rx,ry,rz, fx,fy,fz)            -- up = right x look
  -- Roblox: columns are right, up, -look
  local R = { rx, nx, -fx,
              ry, ny, -fy,
              rz, nz, -fz }
  return cfnew(p.X,p.Y,p.Z, R)
end
CF.__index = function(t,k)
  if k == "Position" then return v3(t.X,t.Y,t.Z) end
  if k == "LookVector" then return v3(-t.R[3], -t.R[6], -t.R[9]) end
  if k == "p" then return v3(t.X,t.Y,t.Z) end
  return rawget(CF, k)
end
function CF:components()
  return self.X,self.Y,self.Z, self.R[1],self.R[2],self.R[3],
         self.R[4],self.R[5],self.R[6], self.R[7],self.R[8],self.R[9]
end
function CF:Inverse()
  local R=self.R
  -- transpose
  local T = {R[1],R[4],R[7], R[2],R[5],R[8], R[3],R[6],R[9]}
  local x = -(T[1]*self.X + T[2]*self.Y + T[3]*self.Z)
  local y = -(T[4]*self.X + T[5]*self.Y + T[6]*self.Z)
  local z = -(T[7]*self.X + T[8]*self.Y + T[9]*self.Z)
  return cfnew(x,y,z,T)
end
CF.__mul = function(a,b)
  if getmetatable(b) == V3 then
    return v3(a.R[1]*b.X + a.R[2]*b.Y + a.R[3]*b.Z + a.X,
              a.R[4]*b.X + a.R[5]*b.Y + a.R[6]*b.Z + a.Y,
              a.R[7]*b.X + a.R[8]*b.Y + a.R[9]*b.Z + a.Z)
  end
  local A,B = a.R, b.R
  local R = {}
  for i=0,2 do for j=0,2 do
    R[i*3+j+1] = A[i*3+1]*B[j+1] + A[i*3+2]*B[3+j+1] + A[i*3+3]*B[6+j+1]
  end end
  local x = A[1]*b.X + A[2]*b.Y + A[3]*b.Z + a.X
  local y = A[4]*b.X + A[5]*b.Y + A[6]*b.Z + a.Y
  local z = A[7]*b.X + A[8]*b.Y + A[9]*b.Z + a.Z
  return cfnew(x,y,z,R)
end
M.cfnew = cfnew

-- Instances ------------------------------------------------------------------
local Inst = {}
Inst.__newindex = function(t,k,v)
  if k == "Parent" then
    local old = rawget(t,"Parent")
    if old then
      local kk = rawget(old,"_kids")
      for i,c in ipairs(kk) do if c==t then table.remove(kk,i) break end end
    end
    rawset(t,"Parent",v)
    if v then table.insert(rawget(v,"_kids"), t) end
    return
  end
  rawset(t,k,v)
end
Inst.__index = function(t,k)
  if k == "Position" then
    local cf = rawget(t,"CFrame")
    if cf then return v3(cf.X, cf.Y, cf.Z) end
    return nil
  end
  for _,c in ipairs(rawget(t,"_kids") or {}) do
    if rawget(c,"Name")==k then return c end
  end
  return rawget(Inst,k)
end
function Inst.FindFirstChild(self,n)
  for _,c in ipairs(rawget(self,"_kids") or {}) do
    if rawget(c,"Name")==n then return c end
  end
end
function Inst.IsA(self,c)
  local cls = rawget(self,"ClassName")
  if cls==c then return true end
  if c=="BasePart" then return cls=="Part" or cls=="UnionOperation" or cls=="MeshPart" or cls=="SpawnLocation" end
  return false
end
function Inst.GetChildren(self)
  local o={}
  for i,c in ipairs(rawget(self,"_kids") or {}) do o[i]=c end
  return o
end
function Inst.GetDescendants(self)
  local out={}
  local function rec(x)
    for _,c in ipairs(rawget(x,"_kids") or {}) do out[#out+1]=c; rec(c) end
  end
  rec(self); return out
end
function Inst.GetFullName(self)
  local parts={}
  local cur=self
  while cur do table.insert(parts,1,rawget(cur,"Name")); cur=rawget(cur,"Parent") end
  return table.concat(parts,".")
end
function Inst.Destroy(self)
  M.destroyed = M.destroyed + 1
  local p = rawget(self,"Parent")
  if p then
    local kk=rawget(p,"_kids")
    for i,c in ipairs(kk) do if c==self then table.remove(kk,i) break end end
  end
  rawset(self,"Parent",nil)
  rawset(self,"_destroyed",true)
end
function Inst.Clone(self)
  local c = M.new(rawget(self,"ClassName"), rawget(self,"Name"), nil)
  for k,v in pairs(self) do
    if k~="_kids" and k~="Parent" then
      if getmetatable(v)==CF then rawset(c,k,cfnew(v.X,v.Y,v.Z,{table.unpack(v.R)}))
      elseif getmetatable(v)==V3 then rawset(c,k,v3(v.X,v.Y,v.Z))
      else rawset(c,k,v) end
    end
  end
  for _,kid in ipairs(rawget(self,"_kids") or {}) do
    local kc = Inst.Clone(kid); kc.Parent = c
  end
  return c
end

function M.new(class, name, parent)
  local o = setmetatable({ClassName=class, Name=name, _kids={}}, Inst)
  rawset(o,"Parent",nil)
  if parent then o.Parent = parent end
  return o
end

function M.install(env)
  M.destroyed = 0
  M.warnings = {}
  M.prints = {}

  env.Vector3 = {new=function(x,y,z) return v3(x,y,z) end}
  env.CFrame  = {new=function(a,b,c)
    if getmetatable(a)==V3 and getmetatable(b)==V3 then return cfLook(a,b) end
    if getmetatable(a)==V3 then return cfnew(a.X,a.Y,a.Z) end
    return cfnew(a,b,c)
  end}
  env.Instance = {new=function(c) return M.new(c,c,nil) end}
  env.warn = function(...)
    local p={}
    for i=1,select('#',...) do p[#p+1]=tostring((select(i,...))) end
    table.insert(M.warnings, table.concat(p," "))
  end
  local realprint = print
  env.print = function(...)
    local p={}
    for i=1,select('#',...) do p[#p+1]=tostring((select(i,...))) end
    table.insert(M.prints, table.concat(p," "))
  end

  local workspace = M.new("Workspace","Workspace",nil)
  local ServerStorage = M.new("ServerStorage","ServerStorage",nil)
  local ReplicatedStorage = M.new("ReplicatedStorage","ReplicatedStorage",nil)
  local Lighting = M.new("Lighting","Lighting",nil)
  M.Workspace = workspace
  M.ServerStorage = ServerStorage

  local Selection = {Set=function(_, t) M.selected = t end}
  local services = {Workspace=workspace, ServerStorage=ServerStorage,
    ReplicatedStorage=ReplicatedStorage, Lighting=Lighting, Selection=Selection}

  local gameRoot = M.new("DataModel","game",nil)
  ServerStorage.Parent = gameRoot
  ReplicatedStorage.Parent = gameRoot
  Lighting.Parent = gameRoot
  workspace.Parent = gameRoot
  rawset(gameRoot, "GetService", function(_, n) return services[n] end)
  rawset(gameRoot, "GetDescendants", function(self) return Inst.GetDescendants(self) end)
  env.game = gameRoot
  env.workspace = workspace
  return M
end

return M
