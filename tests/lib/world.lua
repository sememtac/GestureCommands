-- A small game world for tests: combat, timers, chat, the cursor, action slots, the gamepad crossbar,
-- override bindings and the tooltip, wired to the strict widgets (widgets.lua) and the secure runtime
-- (secure.lua). Suites add their own spells, items, macros and so on.
local lib = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("world%.lua$", "")

local M = {}

function M.new()
	local W = dofile(lib .. "widgets.lua")
	local S = dofile(lib .. "secure.lua")
	local world = {
		W = W, S = S,
		combat = false, time = 1000, actions = {}, cursor = nil, casts = {}, useKeyDownCVar = true,
		printed = {}, messages = {}, timers = {}, rumbles = 0, keysDown = {},
		overrides = {}, bindingLog = {},
	}

	local R = S.new({
		GetActionInfo = function(slot) return GetActionInfo(slot) end,
		inCombat = function() return world.combat end,
		enterSecure = function() local was = W.inSecure; W.inSecure = true; return was end,
		leaveSecure = function(was) W.inSecure = was end,
		ClearOverrideBindings = function(owner) world.overrides[owner] = nil end,
	})
	world.R = R
	W.install({
		inCombat = function() return world.combat end,
		onSetAttribute = function(frame, k, v) R.setAttribute(frame, k, v) end,
	})

	-- Core API
	function InCombatLockdown() return world.combat end
	function GetTime() return world.time end
	C_Timer = { After = function(_, fn) world.timers[#world.timers + 1] = fn end }
	function print(s) world.printed[#world.printed + 1] = s end
	UIErrorsFrame = { AddMessage = function(_, m) world.messages[#world.messages + 1] = m end }
	function strtrim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
	function wipe(t) for k in pairs(t) do t[k] = nil end return t end
	function tinsert(t, v) table.insert(t, v) end
	-- The game's error handler shows the error; here it stops the test with it.
	function geterrorhandler() return function(e) error(e, 0) end end
	SlashCmdList = {}
	UISpecialFrames = {}
	function hooksecurefunc(t, k, fn)
		if type(t) == "string" then t, k, fn = _G, t, k end
		local orig = t[k]
		assert(type(orig) == "function", "hooksecurefunc: no function " .. tostring(k))
		t[k] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
	end
	UIParent = W.CreateFrame("Frame", "UIParent")

	-- Tooltip (strict: only what the addon uses)
	GameTooltip = {
		SetOwner = function(self, owner) self.owner = owner end,
		SetText = function(self, t) self.text = t end,
		AddLine = function(self, t) self.lines = self.lines or {}; self.lines[#self.lines + 1] = t end,
		SetSpellByID = function(self, id) self.spell = id end,
		SetItemByID = function(self, id) self.item = id end,
		Show = function(self) self.shown = true end,
		Hide = function(self) self.shown = false end,
	}
	function GameTooltip_Hide() GameTooltip:Hide() end

	-- Cursor and action slots
	function GetCursorInfo() if world.cursor then return unpack(world.cursor) end end
	function ClearCursor()
		local had = world.cursor ~= nil
		world.cursor = nil
		if had then W.fireEvent("CURSOR_CHANGED") end -- synchronous in the game
	end
	function GetActionInfo(slot) local a = world.actions[slot]; if a then return a[1], a[2], a[3] end end

	-- Secure templates and drivers
	SecureHandlerWrapScript = R.wrapScript
	RegisterStateDriver = R.registerStateDriver
	SecureHandlerSetFrameRef = R.setFrameRef

	-- Override bindings
	function SetOverrideBindingClick(owner, priority, key, name, button)
		assert(priority == true, "priority overrides")
		assert(not world.combat or W.inSecure, "SetOverrideBindingClick in combat")
		world.overrides[owner] = world.overrides[owner] or {}
		world.overrides[owner][key] = ("CLICK %s:%s"):format(name, button)
		world.bindingLog[#world.bindingLog + 1] = "set"
	end
	function SetOverrideBinding(owner, priority, key, action)
		assert(priority == true, "priority overrides")
		assert(not world.combat or W.inSecure, "SetOverrideBinding in combat")
		world.overrides[owner] = world.overrides[owner] or {}
		world.overrides[owner][key] = action
		world.bindingLog[#world.bindingLog + 1] = "set"
	end
	function ClearOverrideBindings(owner)
		assert(not world.combat or W.inSecure, "ClearOverrideBindings in combat")
		world.overrides[owner] = nil
		world.bindingLog[#world.bindingLog + 1] = "clear"
	end
	world.blizzardBindings = {} -- key -> action that Blizzard's own overrides would give
	function GetBindingAction(key)
		if world.blizzardBindings[key] then return world.blizzardBindings[key] end
		for _, keys in pairs(world.overrides) do if keys[key] then return keys[key] end end
		return ""
	end
	function IsKeyDown(key) return world.keysDown[key] == true end
	C_GamePad = { SetVibration = function() world.rumbles = world.rumbles + 1 end, StopVibration = function() end }

	-- Constants the addon reads
	GAMEPAD_FACE_BOTTOM, GAMEPAD_FACE_RIGHT, GAMEPAD_FACE_LEFT = "PAD1", "PAD2", "PAD3"
	GAMEPAD_SHOULDER_LEFT, GAMEPAD_SHOULDER_RIGHT = "PADLSHOULDER", "PADRSHOULDER"
	GAMEPAD_DPAD_LEFT, GAMEPAD_DPAD_RIGHT = "PADDLEFT", "PADDRIGHT"
	NORMAL_FONT_COLOR = { GetRGB = function() return 1, 0.82, 0 end }
	DISABLED_FONT_COLOR = { GetRGB = function() return 0.5, 0.5, 0.5 end }

	-- Helpers for suites
	function world.runTimers()
		for _ = 1, 3 do
			local t = world.timers
			world.timers = {}
			for _, fn in ipairs(t) do fn() end
		end
	end
	world.fire = W.fireEvent
	function world.poll() W.update(0.016) end
	-- One secure tick: state drivers whose value differs fire (the gesture engine's "tock" driver).
	function world.tick() R.tick() end
	function world.lastPrint() return world.printed[#world.printed] or "" end

	-- The gamepad crossbar: bars of Blizzard's secure action buttons with storage-slot IDs from 185.
	function world.buildCrossbar()
		local bars, nextID = {}, 185
		for _, key in ipairs({ "topBar", "leftBar", "rightBar", "bottomBar", "stanceBar", "possessBar" }) do
			local bar = { buttons = {} }
			for i = 1, 8 do
				-- Named like Blizzard's (<bar>ActionButton1..8); paging changes their IDs, not the frames.
				local b = W.CreateFrame("CheckButton", key .. "ActionButton" .. i, nil)
				b.blizzard, b.protected, b.id = true, true, nextID
				nextID = nextID + 1
				b.icon = b:CreateTexture()
				b.Name = b:CreateFontString()
				if key ~= "possessBar" then b.attrs.type = "action"; b.attrs.useOnKeyDown = true end
				bar.buttons[i] = b
			end
			function bar:GetActionButtonByIndex(i) return self.buttons[i] end
			bars[key] = bar
		end
		world.bars = bars
		world.activeBar = bars.topBar
		GamepadMainActionBarFrame = { PageUnit = { actionBars = bars, GetActiveBar = function() return world.activeBar end } }
		function GamepadMainActionBarFrame:PressActionButton() end
		return bars
	end

	-- A simplified SecureActionButton_OnClick: casts the "*type" virtual button, else the slot's action. A
	-- mouse click acts on release, whatever useOnKeyDown says (isSecureMousePress there).
	function world.blizzardOnClick(btn, button, down, isMouse)
		local useOnKeyDown = btn.attrs.useOnKeyDown
		if useOnKeyDown == nil then useOnKeyDown = world.useKeyDownCVar end
		if isMouse then useOnKeyDown = false end
		if not ((down and useOnKeyDown) or (not down and not useOnKeyDown)) then return end
		local suffix = (button == "LeftButton") and "1" or ("-" .. button)
		local t = btn.attrs["*type" .. suffix]
		if t then
			world.casts[#world.casts + 1] = t .. ":" .. tostring(btn.attrs["*" .. t .. suffix])
		else
			local a = world.actions[btn.id]
			if a then world.casts[#world.casts + 1] = "slot:" .. a[1] .. ":" .. tostring(a[2]) end
		end
	end
	function world.click(btn, button, down, isMouse)
		R.click(btn, button, down, function(b, mouseButton, d) world.blizzardOnClick(b, mouseButton, d, isMouse) end)
	end
	-- A mouse click: press and release, with the feedback poll after each.
	function world.mouseClick(btn)
		world.click(btn, "LeftButton", true, true); world.poll()
		world.click(btn, "LeftButton", false, true); world.poll()
	end
	-- Press, hold for some secure ticks, release (with the feedback poll each frame).
	function world.press(btn, ticksHeld)
		world.click(btn, "LeftButton", true)
		for _ = 1, ticksHeld do world.tick(); world.poll() end
		world.click(btn, "LeftButton", false)
		world.poll()
	end
	function world.lastCast() return world.casts[#world.casts] end

	return world
end

return M
