-- Publishing: the gestures -> secure header attributes (out of combat only).
--   "g:<key>" = gesture number, for every key the secure code finds the gesture's Tap by (ActionKinds.lua)
--   "g<n>-<mode>-type" / "-attr" / "-value" = how to cast gesture n's hold / long-hold action
--   enabled, holdTicks, hold2Ticks, debug

local _, ns = ...;
local Engine = ns.Engine;
local header = ns.header;

local publishedAttributes = {};
local keyOwners = {}; -- "slot:<n>" / "spell:<id>" / "item:<id>" -> gesture number, from the last Publish
ns.conflicts = {}; -- gesture number -> the gesture number it shares a Tap with

local function SetPublished(name, value)
	header:SetAttribute(name, value);
	publishedAttributes[name] = true;
end

-- The gesture a crossbar slot triggers, by the same lookup the secure code does (as of the last Publish).
function Engine.GetSlotGesture(slot)
	local index = keyOwners["slot:" .. slot];
	if not index then
		local kind, id, subType = GetActionInfo(slot);
		if kind == "macro" then
			kind = subType;
		end
		index = kind and id and keyOwners[kind .. ":" .. id];
	end
	return index and ns.DB().gestures[index];
end

-- Returns false if it has to wait for combat to end (it is retried then).
function ns.Publish()
	if InCombatLockdown() then
		return false;
	end

	for name in pairs(publishedAttributes) do
		header:SetAttribute(name, nil);
	end
	wipe(publishedAttributes);

	ns.conflicts = {};
	wipe(keyOwners);
	local db = ns.DB();
	local scan = Engine.ScanActionSlots();
	for index, gesture in ipairs(db.gestures) do
		if gesture.trigger then
			for key in pairs(Engine.GetTriggerKeys(gesture.trigger, scan)) do
				if keyOwners[key] and keyOwners[key] ~= index then
					ns.conflicts[index] = keyOwners[key];
				end
				keyOwners[key] = index;
				SetPublished("g:" .. key, index);
			end
			for _, mode in ipairs(ns.MODES) do
				local action = gesture[mode];
				local actionType, attribute, value;
				if action then
					actionType, attribute, value = Engine.GetCastSpec(action);
				end
				if actionType then
					local prefix = "g" .. index .. "-" .. mode .. "-";
					SetPublished(prefix .. "type", actionType);
					SetPublished(prefix .. "attr", attribute);
					SetPublished(prefix .. "value", value);
				end
			end
		end
	end

	-- On unless the player turned it off; buttons are only hooked once there is a gesture to act on.
	local enabled = db.enabled ~= false and not ns.IsTotemCommandsActive();
	if enabled and #db.gestures > 0 then
		Engine.WrapCrossbarButtons();
	end
	header:SetAttribute("holdTicks", ns.GetHoldTicks());
	header:SetAttribute("hold2Ticks", ns.GetHold2Ticks());
	header:SetAttribute("debug", db.debug == true);
	header:SetAttribute("enabled", enabled);
	ns.RefreshCrossbarLabels();
	if ns.OnPublished then
		ns.OnPublished();
	end
	return true;
end

function ns.SetEnabled(enabled)
	if InCombatLockdown() then
		ns.Print("can't change this in combat.");
		return false;
	end
	if enabled and ns.IsTotemCommandsActive() then
		ns.Print("Totem Commands is on and uses the same buttons. Type /totemcommands off first.");
		return false;
	end
	ns.DB().enabled = enabled;
	ns.Publish();
	return true;
end

-- Publish after login (a frame later, so Blizzard's gamepad bars finish their own setup first), and again
-- whenever spells, slots, forms or macros change or combat ends (debounced).
local loggedIn, publishQueued = false, false;

ns.On("PLAYER_LOGIN", function()
	loggedIn = true;
	C_Timer.After(0, ns.Publish);
end);

local function QueuePublish()
	if not loggedIn or publishQueued then
		return;
	end
	publishQueued = true;
	C_Timer.After(0.5, function()
		publishQueued = false;
		ns.Publish();
	end);
end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "SPELLS_CHANGED", "UPDATE_SHAPESHIFT_FORMS",
	"ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS" }) do
	ns.On(event, QueuePublish);
end
