-- The slash command: /gestures (or /gesturecommands).

local _, ns = ...;

local MIN_HOLD_TICKS, MAX_HOLD_TICKS, MAX_HOLD2_TICKS = 2, 6, 12;

local function SetHoldTicks(arg)
	local ticks = tonumber(arg);
	if ticks < MIN_HOLD_TICKS or ticks > MAX_HOLD_TICKS then
		ns.Print(("hold must be %d to %d ticks (about 0.2 s each)."):format(MIN_HOLD_TICKS, MAX_HOLD_TICKS));
		return false;
	end
	ns.DB().holdTicks = ticks;
	ns.Print(("hold: %d ticks."):format(ticks));
	return true;
end

local function SetHold2Ticks(arg)
	local ticks = tonumber(arg);
	if ticks < ns.GetHoldTicks() + 2 or ticks > MAX_HOLD2_TICKS then
		ns.Print(("hold2 must be %d to %d ticks."):format(ns.GetHoldTicks() + 2, MAX_HOLD2_TICKS));
		return false;
	end
	ns.DB().hold2Ticks = ticks;
	ns.Print(("long hold: %d ticks."):format(ticks));
	return true;
end

SLASH_GESTURECOMMANDS1 = "/gestures";
SLASH_GESTURECOMMANDS2 = "/gesturecommands";
SlashCmdList.GESTURECOMMANDS = function(msg)
	msg = strtrim(msg or ""):lower();
	local holdArg = msg:match("^hold%s+(%d+)$");
	local hold2Arg = msg:match("^hold2%s+(%d+)$");
	if msg == "" then
		if ns.ToggleConfig then
			ns.ToggleConfig();
		end
	elseif msg == "test" then
		ns.RunTest();
	elseif msg == "on" or msg == "off" then
		if ns.SetEnabled(msg == "on") then
			ns.Print(msg == "on" and "on." or "off - crossbar buttons behave normally.");
		end
	elseif msg == "minimap" then
		if ns.ToggleMinimapButton then
			ns.ToggleMinimapButton();
		end
	elseif msg == "padnav own" or msg == "padnav blizzard" then
		ns.DB().ownNavigation = msg == "padnav own" or nil;
		if ns.CloseConfig then
			ns.CloseConfig();
		end
		ns.Print(ns.DB().ownNavigation and "the window now uses its own controller navigation (D-pad, A, B, X; LT / RT don't reach it)."
			or "the window now uses the game's controller navigation (LT / RT, View, A, B).");
	elseif msg == "debug" or holdArg or hold2Arg then
		if InCombatLockdown() then
			ns.Print("can't change this in combat.");
			return;
		end
		if msg == "debug" then
			ns.DB().debug = not ns.DB().debug;
			ns.Print("debug output " .. (ns.DB().debug and "on." or "off."));
		elseif holdArg and not SetHoldTicks(holdArg) then
			return;
		elseif hold2Arg and not SetHold2Ticks(hold2Arg) then
			return;
		end
		ns.Publish();
	else
		ns.Print("/gestures opens the window. Also: on, off, test, debug, hold <n>, hold2 <n>, minimap, padnav own|blizzard.");
	end
end;
