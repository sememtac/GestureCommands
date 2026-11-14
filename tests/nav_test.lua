-- Navigation tests: direction finding of our own controller navigation, on a synthetic layout.
-- Run: tests/run.ps1 (or luajit tests/nav_test.lua from the repo root).
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]*$", "") .. "lib/"
local H = dofile(lib .. "harness.lua")
dofile(lib .. "world.lua").new()
local check = H.check

local ns = {}
H.loadAddon(ns, function(file) return file == "Core/Core.lua" end)
ns.Print, ns.DB = function() end, function() return { ownNavigation = true } end
H.loadAddon(ns, function(file) return file == "UI/Navigation.lua" or file == "UI/OwnNavigation.lua" end)
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
ns.Nav.modes.own.Close(panel)

-- ---- rows: tabs 80 apart over a grid of cells 40 apart, the first grid row just under the tabs ----------
-- By position alone, right from a tab finds the cell down-right (nearer than the next tab).
local tabs, cells = {}, {}
for i = 1, 4 do tabs[i] = control("tab" .. i, 40 + (i - 1) * 80, 0) end
for row = 1, 3 do
	cells[row] = {}
	for col = 1, 8 do cells[row][col] = control(("cell%d.%d"):format(row, col), 20 + (col - 1) * 40, -20 - (row - 1) * 40) end
end
local pager = { control("first", 20, -160), control("last", 300, -160) }
local rows = { tabs, cells[1], cells[2], cells[3], pager }
local Find = ns.Nav.FindInRows
check(Find(rows, tabs[2], "RIGHT") == tabs[3], "rows: right moves along the row (not to the nearer cell below)")
check(Find(rows, tabs[2], "LEFT") == tabs[1] and Find(rows, tabs[1], "LEFT") == nil, "rows: left along the row; stays at its start")
check(Find(rows, tabs[4], "RIGHT") == nil, "rows: stays at the row's end")
check(Find(rows, tabs[4], "DOWN") == cells[1][7], "rows: down goes to the next row, to the control nearest in X")
check(Find(rows, cells[1][1], "UP") == tabs[1] and Find(rows, cells[1][8], "UP") == tabs[4], "rows: up likewise")
check(Find(rows, cells[3][5], "DOWN") == pager[2] and Find(rows, cells[3][4], "DOWN") == pager[1], "rows: down from the middle still reaches the next part")
tabs[2].enabled = false
check(Find(rows, tabs[1], "RIGHT") == tabs[3], "rows: skips a disabled control")
tabs[2].enabled = true
for col = 1, 8 do cells[2][col].visible = false end
check(Find(rows, cells[1][3], "DOWN") == cells[3][3], "rows: skips a row with nothing usable")
local inRows = select(2, Find(rows, control("elsewhere", 0, 0), "UP"))
check(inRows == false, "rows: a control not in any row is reported as such")
for col = 1, 8 do cells[2][col].visible = true end

-- Our own navigation follows a panel's rows.
local rowPanel = { GetNavRows = function() return rows end, Hide = function() end }
function rowPanel:GetNavControls()
	local list = {}
	for _, row in ipairs(rows) do for _, c in ipairs(row) do list[#list + 1] = c end end
	return list
end
rowPanel.GetNavDefault = function() return tabs[2] end
ns.Nav.Open(rowPanel)
check(at() == nil and tabs[2].locked, "rows panel: starts on its default")
ns.Nav.OnInput("RIGHT"); check(tabs[3].locked, "own navigation: right goes to the next tab, not the cell below")
ns.Nav.OnInput("DOWN"); check(cells[1][5].locked, "own navigation: down goes to the grid")
ns.Nav.OnInput("RIGHT"); check(cells[1][6].locked, "own navigation: right along the grid row")
ns.Nav.OnInput("UP"); check(tabs[3].locked, "own navigation: up back to the tabs")

H.finish()
