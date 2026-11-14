-- Navigation tests: direction finding of our own controller navigation, on a synthetic layout.
-- Run: tests/run.ps1 (or luajit tests/nav_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
dofile(lib .. "world.lua").new()
local check = H.check

local ns = { Print = function() end, DB = function() return { ownNavigation = true } end }
H.loadAddon(ns, function(file) return file == "Navigation.lua" or file == "UI/Navigation.lua" end)
assert(ns.Nav, "Navigation.lua didn't load")

-- A control: only what navigation may read.
local function control(name, x, y, opts)
	opts = opts or {}
	local c = { name = name, x = x, y = y, visible = opts.visible ~= false, enabled = opts.enabled ~= false }
	function c:GetCenter() return self.x, self.y end
	function c:IsVisible() return self.visible end
	function c:IsEnabled() return self.enabled end
	function c:IsObjectType() return false end
	function c:GetScript() return nil end
	function c:LockHighlight() self.locked = true end
	function c:UnlockHighlight() self.locked = false end
	function c:Click() self.clicked = (self.clicked or 0) + 1 end
	return c
end

-- 3x3 grid, 40 apart (y grows upward), plus a wide button under the middle column.
local grid = {}
for row = 1, 3 do for col = 1, 3 do grid[#grid + 1] = control(("r%dc%d"):format(row, col), col * 40, -row * 40) end end
local wide = control("wide", 80, -170)
local controls = {}; for _, c in ipairs(grid) do controls[#controls + 1] = c end; controls[#controls + 1] = wide
local panel = { GetNavControls = function() return controls end, Hide = function(self) self.hidden = true end }

local function at() for _, c in ipairs(controls) do if c.locked then return c.name end end end
ns.Nav.Open(panel)
check(at() == "r1c1", "starts on the first control")
ns.Nav.OnInput("RIGHT"); check(at() == "r1c2", "right")
ns.Nav.OnInput("DOWN"); check(at() == "r2c2", "down")
ns.Nav.OnInput("LEFT"); check(at() == "r2c1", "left")
ns.Nav.OnInput("LEFT"); check(at() == "r2c1", "left edge: stays")
ns.Nav.OnInput("UP"); check(at() == "r1c1", "up")
ns.Nav.OnInput("UP"); check(at() == "r1c1", "top edge: stays")
grid[2].enabled = false
ns.Nav.OnInput("RIGHT"); check(at() == "r1c3", "skips a disabled control")
grid[6].visible = false
ns.Nav.OnInput("DOWN"); check(at() == "r3c3", "skips a hidden control")
ns.Nav.OnInput("DOWN"); check(at() == "wide", "down to the wide button below")
ns.Nav.OnInput("UP"); check(at() == "r3c2", "up from the wide button lands on the nearest column")
ns.Nav.OnInput("A"); check(grid[8].clicked == 1, "A clicks")
ns.Nav.OnInput("B"); check(panel.hidden, "B hides a panel without OnNavBack")

H.finish()
