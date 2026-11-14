-- Gesture Commands
-- Tap / hold / long-hold gestures for anything on the gamepad crossbar. A gesture attaches to a Tap action
-- on a crossbar slot: a tap does what the slot normally does, a hold casts the gesture's hold action, a
-- longer hold casts its long-hold action.
--
-- Layout (loaded in this order by the TOC):
--   Core/     the namespace, events, combat queue, secure snippet check, saved variables
--   Engine/   the secure gesture engine and everything that configures it (no windows)
--   UI/       the setup window, action picker, controller navigation, minimap button, menu dial entry
-- The UI only uses the engine through the flat ns.* functions listed in Engine/API.md; engine modules share
-- their internals through ns.Engine.

local ADDON_NAME, ns = ...;

ns.ADDON_NAME = ADDON_NAME;
ns.Engine = {};

-- The hold stages after a tap, in order, and what the window calls each action of a gesture.
ns.MODES = { "hold", "long" };
ns.MODE_LABELS = { trigger = "Tap", hold = "Hold", long = "Long hold" };

function ns.Print(text)
	print("|cff33ff99Gesture Commands|r: " .. text);
end

-------------------------------------------------------------------------------
-- Events: one frame; handlers run in the order they were added (that is, TOC order).
-------------------------------------------------------------------------------

local handlers = {}; -- event -> { handler, ... }
local eventFrame = CreateFrame("Frame");
eventFrame:SetScript("OnEvent", function(_, event, ...)
	for _, handler in ipairs(handlers[event]) do
		handler(event, ...);
	end
end);

function ns.On(event, handler)
	if not handlers[event] then
		handlers[event] = {};
		eventFrame:RegisterEvent(event);
	end
	table.insert(handlers[event], handler);
end

-------------------------------------------------------------------------------
-- Combat: secure state and protected calls can't change in combat. AfterCombat runs a function now, or
-- once combat ends (before any other end-of-combat handler).
-------------------------------------------------------------------------------

local afterCombat = {};

function ns.AfterCombat(fn)
	if InCombatLockdown() then
		table.insert(afterCombat, fn);
	else
		fn();
	end
end

ns.On("PLAYER_REGEN_ENABLED", function()
	local queued = afterCombat;
	afterCombat = {};
	for _, fn in ipairs(queued) do
		fn();
	end
end);

-------------------------------------------------------------------------------
-- Secure snippets. Blizzard compiles them with BuildRestrictedClosure, which refuses a body that contains the
-- word "function" or a brace anywhere, even in a comment, and code that fails there fails silently in game
-- (an early 1.0.1 build couldn't bind because of it). Every snippet goes through ns.Snippet, named after the
-- attribute or script it is for, so a bad one is reported as soon as the addon loads, and tests can check
-- them all.
-------------------------------------------------------------------------------

ns.snippets = {}; -- { name = ..., body = ... } in load order
ns.snippetErrors = {};

function ns.Snippet(name, body)
	local problem = (body:find("function", 1, true) and 'the word "function"') or (body:find("[{}]") and "a brace") or nil;
	table.insert(ns.snippets, { name = name, body = body });
	if problem then
		local message = ("secure code %s contains %s, which the game refuses - gestures won't work. Please report this."):format(name, problem);
		table.insert(ns.snippetErrors, message);
		ns.Print("|cffff4040" .. message .. "|r");
	end
	return body;
end
