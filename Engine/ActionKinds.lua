-- Action kinds: everything that differs between spells, items, toys, mounts and macros, in one place.
-- An action is { kind = <kind name>, id = number, name = string } (a macro has only its name). Supporting a
-- new kind means registering it here, and adding a tab to UI/Picker.lua if it should be choosable there.
--
-- A kind has:
--   Display(action)       -> name, icon
--   CastSpec(action)      -> the SecureActionButton type, the attribute it reads, and the value; nil if it
--                            can't be cast
--   Pickup(action)        -> true, or false and a message; puts the action on the cursor
--   IsAvailable(action)   -> whether it still exists for this character (optional; default yes)
--   Shows(action)         -> the spell or item action it stands for, if any (optional)
--   canTap                -> it can be a gesture's Tap
-- and, to be a Tap, one way for the secure code to find the crossbar slots that hold it:
--   ContentKeys(action, scan, keys) adds "spell:<id>" / "item:<id>" keys: the secure code looks a pressed
--                            slot up by what it shows (GetActionInfo; a macro counts as what it shows).
--   SlotHolds(action, slot, context) -> whether a slot (an ActionSlots scan entry) holds it. These Taps are
--                            published by slot number, for kinds the secure code can't see: the game hides
--                            mount and toy IDs from it, and a macro shows only what it casts.
--                            SlotContext(action), if any, computes `context` once per scan.

local _, ns = ...;
local Engine = ns.Engine;

local KINDS = {};
Engine.ActionKinds = KINDS;

local function Register(name, kind)
	KINDS[name] = kind;
end
Engine.RegisterActionKind = Register;

Register("spell", {
	canTap = true,
	Display = function(action)
		return C_Spell.GetSpellName(action.id) or action.name, C_Spell.GetSpellTexture(action.id);
	end,
	CastSpec = function(action)
		-- By name, so a ranked spell always casts the highest rank the character knows.
		local name = C_Spell.GetSpellName(action.id) or action.name;
		return "spell", "spell", name or action.id;
	end,
	Pickup = function(action)
		-- The highest rank the character knows.
		local name = C_Spell.GetSpellName(action.id) or action.name;
		local best = name and C_Spell.GetSpellInfo(name);
		C_Spell.PickupSpell(best and best.spellID or action.id);
		return true;
	end,
	Shows = function(action)
		return action;
	end,
	-- Ranked spells have one ID per rank, so any action slot showing a spell with the Tap's name counts, as
	-- do the Tap's own ID and the highest known rank.
	ContentKeys = function(action, scan, keys)
		keys["spell:" .. action.id] = true;
		local name = C_Spell.GetSpellName(action.id) or action.name;
		if not name then
			return;
		end
		local info = C_Spell.GetSpellInfo(name);
		if info and info.spellID then
			keys["spell:" .. info.spellID] = true;
		end
		for _, slot in pairs(scan.slots) do
			if slot.shows == "spell" and slot.id and scan:SpellName(slot.id) == name then
				keys["spell:" .. slot.id] = true;
			end
		end
	end,
});

local function ItemDisplay(action)
	return C_Item.GetItemNameByID(action.id) or action.name, C_Item.GetItemIconByID(action.id);
end

Register("item", {
	canTap = true,
	Display = ItemDisplay,
	CastSpec = function(action)
		return "item", "item", "item:" .. action.id;
	end,
	Pickup = function(action)
		C_Item.PickupItem(action.id);
		return true;
	end,
	Shows = function(action)
		return action;
	end,
	ContentKeys = function(action, _, keys)
		keys["item:" .. action.id] = true;
	end,
});

Register("toy", {
	canTap = true,
	Display = ItemDisplay,
	CastSpec = function(action)
		return "toy", "toy", action.id;
	end,
	Pickup = function(action)
		C_ToyBox.PickupToyBoxItem(action.id);
		return true;
	end,
	IsAvailable = function(action)
		return not PlayerHasToy or PlayerHasToy(action.id);
	end,
	SlotHolds = function(action, slot)
		return (slot.kind == "item" or slot.kind == "toy") and slot.id == action.id;
	end,
});

Register("mount", {
	canTap = true,
	Display = function(action)
		local name, _, icon = C_MountJournal.GetMountInfoByID(action.id);
		return name or action.name, icon;
	end,
	CastSpec = function(action)
		local _, spellID = C_MountJournal.GetMountInfoByID(action.id);
		if spellID then
			return "spell", "spell", spellID;
		end
	end,
	Pickup = function(action)
		-- The mount journal picks up by list position; the mount's spell if it's filtered out of the list.
		for index = 1, C_MountJournal.GetNumDisplayedMounts and C_MountJournal.GetNumDisplayedMounts() or 0 do
			if C_MountJournal.GetDisplayedMountID(index) == action.id then
				C_MountJournal.Pickup(index);
				return true;
			end
		end
		local _, spellID = C_MountJournal.GetMountInfoByID(action.id);
		if spellID then
			C_Spell.PickupSpell(spellID);
		end
		return true;
	end,
	IsAvailable = function(action)
		return (C_MountJournal.GetMountInfoByID(action.id)) ~= nil;
	end,
	-- The mount's spell: a slot can hold the mount itself or its spell.
	SlotContext = function(action)
		return (select(2, C_MountJournal.GetMountInfoByID(action.id)));
	end,
	SlotHolds = function(action, slot, spellID)
		return (slot.kind == "summonmount" and slot.id == action.id) or (spellID ~= nil and slot.kind == "spell" and slot.id == spellID);
	end,
});

local function MacroIndex(name)
	local index = GetMacroIndexByName(name);
	return (index and index > 0) and index or nil;
end

Register("macro", {
	canTap = true,
	Display = function(action)
		local name, icon = GetMacroInfo(action.name);
		return name or action.name, icon;
	end,
	CastSpec = function(action)
		return "macro", "macro", action.name;
	end,
	Pickup = function(action)
		local index = MacroIndex(action.name);
		if not index then
			return false, ("the macro %s doesn't exist any more - choose this gesture's Tap again."):format(tostring(action.name));
		end
		PickupMacro(index);
		return true;
	end,
	IsAvailable = function(action)
		return MacroIndex(action.name) ~= nil;
	end,
	-- What the macro shows right now (#showtooltip / its first /cast), or nil.
	Shows = function(action)
		local index = MacroIndex(action.name);
		if not index then
			return nil;
		end
		local spellID = GetMacroSpell(index);
		if spellID then
			return { kind = "spell", id = spellID, name = C_Spell.GetSpellName(spellID) };
		end
		local _, itemLink = GetMacroItem(index);
		local itemID = itemLink and C_Item.GetItemInfoInstant(itemLink);
		if itemID then
			return { kind = "item", id = itemID, name = C_Item.GetItemNameByID(itemID) };
		end
		return nil;
	end,
	SlotHolds = function(action, slot)
		return slot.kind == "macro" and slot.text == action.name;
	end,
});

-------------------------------------------------------------------------------
-- By kind
-------------------------------------------------------------------------------

function ns.GetActionDisplay(action)
	if not action then
		return nil, nil;
	end
	local kind = KINDS[action.kind];
	if kind then
		return kind.Display(action);
	end
	return action.name, nil;
end

function Engine.GetCastSpec(action)
	local kind = KINDS[action.kind];
	if kind and kind.CastSpec then
		return kind.CastSpec(action);
	end
	return nil;
end

function Engine.IsAvailable(action)
	local kind = KINDS[action.kind];
	return not (kind and kind.IsAvailable) or kind.IsAvailable(action);
end

-- Returns true, or false and a message.
function Engine.PickupAction(action)
	local kind = KINDS[action.kind];
	if not kind then
		return false;
	end
	return kind.Pickup(action);
end

-- The spell or item an action stands for (a macro: what it shows right now), or nil.
function Engine.ResolveShown(action)
	local kind = action and KINDS[action.kind];
	return kind and kind.Shows and kind.Shows(action) or nil;
end

-- A dropped action as a Tap, or nil if it can't be one. Binding the gesture puts that action itself on the
-- crossbar, and a tap does what it does.
function ns.MakeTrigger(action)
	local kind = action and KINDS[action.kind];
	return kind and kind.canTap and action or nil;
end

-- Every key the secure code finds this Tap by, from an ActionSlots scan: "slot:<n>" for each slot holding a
-- slot-keyed Tap (if it still exists), else "spell:<id>" / "item:<id>" for what slots holding it show.
function Engine.GetTriggerKeys(trigger, scan)
	local keys = {};
	local kind = KINDS[trigger.kind];
	if not kind then
		return keys;
	end
	if kind.SlotHolds then
		if not Engine.IsAvailable(trigger) then
			return keys;
		end
		local context = kind.SlotContext and kind.SlotContext(trigger);
		for slot, info in pairs(scan.slots) do
			if kind.SlotHolds(trigger, info, context) then
				keys["slot:" .. slot] = true;
			end
		end
	else
		kind.ContentKeys(trigger, scan, keys);
	end
	return keys;
end

-- Whether an action slot holds this Tap now, as the secure code would find it there.
function Engine.SlotHoldsTrigger(slot, trigger)
	local scan = Engine.ScanActionSlots(slot);
	local info = scan.slots[slot];
	if not info then
		return false;
	end
	local keys = Engine.GetTriggerKeys(trigger, scan);
	return keys["slot:" .. slot] or (info.shows ~= nil and info.id ~= nil and keys[info.shows .. ":" .. info.id]) or false;
end

-- Reads the cursor into an action (nil and the cursor type if it holds something else).
function ns.ReadCursor()
	local cursorType, info1, _, info3 = GetCursorInfo();
	if cursorType == "spell" and info3 then
		return { kind = "spell", id = info3, name = C_Spell.GetSpellName(info3) };
	elseif cursorType == "item" and info1 then
		local isToy = (PlayerHasToy and PlayerHasToy(info1)) or false;
		return { kind = isToy and "toy" or "item", id = info1, name = C_Item.GetItemNameByID(info1) };
	elseif cursorType == "mount" and info1 then
		return { kind = "mount", id = info1, name = (C_MountJournal.GetMountInfoByID(info1)) };
	elseif cursorType == "macro" and info1 then
		return { kind = "macro", name = (GetMacroInfo(info1)) };
	end
	return nil, cursorType;
end
