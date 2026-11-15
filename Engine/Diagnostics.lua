-- Diagnostics: /gestures test, debug output for crossbar presses, and reports of actions Blizzard blocked.

local _, ns = ...;
local Engine = ns.Engine;
local header = ns.header;

local function GetBarName(bar)
	local pageUnit = Engine.GetPageUnit();
	for key, candidate in pairs(pageUnit and pageUnit.actionBars or {}) do
		if candidate == bar then
			return key;
		end
	end
	return tostring(bar);
end

local function OnPressActionButton(_, index, _, down)
	if not (down and ns.DB() and ns.DB().debug) then
		return;
	end
	local pageUnit = Engine.GetPageUnit();
	local bar = pageUnit and pageUnit:GetActiveBar();
	local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(index);
	local slot = button and button:GetID();
	local kind, id, subType = GetActionInfo(slot or 0);
	ns.Print(("press: button %d on %s, hooked=%s, slot=%s, action=%s %s %s"):format(index, GetBarName(bar),
		tostring(button and ns.wrapped[button] == true), tostring(slot), tostring(kind), tostring(id), tostring(subType or "")));
end

ns.On("PLAYER_LOGIN", function()
	if GamepadMainActionBarFrame and GamepadMainActionBarFrame.PressActionButton then
		hooksecurefunc(GamepadMainActionBarFrame, "PressActionButton", OnPressActionButton);
	end
end);

function ns.RunTest()
	local db = ns.DB();
	ns.Print(("%d gesture(s); %s; hold %d ticks, long hold %d ticks (about 0.2 s each)."):format(#db.gestures,
		header:GetAttribute("enabled") and "on" or "off", ns.GetHoldTicks(), ns.GetHold2Ticks()));
	for _, message in ipairs(ns.snippetErrors) do
		ns.Print("|cffff4040" .. message .. "|r");
	end
	if ns.IsTotemCommandsActive() then
		ns.Print("Totem Commands is on - turn it off (/totemcommands off) to use Gesture Commands.");
	end
	for index, gesture in ipairs(db.gestures) do
		local parts = {};
		for _, mode in ipairs({ "trigger", "hold", "long" }) do
			table.insert(parts, ns.MODE_LABELS[mode] .. ": " .. tostring((ns.GetActionDisplay(gesture[mode])) or "-"));
		end
		local slots = 0;
		for _, info in ipairs(ns.GetCrossbarButtons()) do
			if Engine.GetSlotGesture(info.button:GetID()) == gesture then
				slots = slots + 1;
			end
		end
		ns.Print(("%d. %s  (on %d crossbar slot%s of this page)%s"):format(index, table.concat(parts, ", "), slots,
			slots == 1 and "" or "s", ns.conflicts and ns.conflicts[index] and " - same Tap as another gesture!" or ""));
	end
	local start = header:GetAttribute("tickcount") or 0;
	C_Timer.After(2, function()
		local ticks = (header:GetAttribute("tickcount") or 0) - start;
		ns.Print(("secure ticks: %d in 2 s (%s)"):format(ticks, ticks >= 4 and "working" or "NOT working - please report"));
	end);
end

-- The "blocked from an action" dialog doesn't say which function; report it so problems can be traced.
local function OnActionBlocked(event, addonName, functionName)
	if addonName == ns.ADDON_NAME then
		ns.Print(("Blizzard blocked %s (%s) - please report this."):format(tostring(functionName),
			event == "ADDON_ACTION_FORBIDDEN" and "forbidden" or "blocked in combat"));
	end
end
ns.On("ADDON_ACTION_FORBIDDEN", OnActionBlocked);
ns.On("ADDON_ACTION_BLOCKED", OnActionBlocked);
