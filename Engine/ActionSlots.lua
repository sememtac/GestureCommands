-- Action slots: what each one holds.

local _, ns = ...;
local Engine = ns.Engine;

local MAX_ACTION_SLOT = 400; -- Covers the keyboard bars and the gamepad action storage (181+).
Engine.MAX_ACTION_SLOT = MAX_ACTION_SLOT;

function Engine.GetSlotActionText(slot)
	return (C_ActionBar.GetActionText or GetActionText)(slot);
end

-- What a slot holds: { kind, id, subType (GetActionInfo), shows, text }, or nil if it's empty. `shows` is
-- what the slot shows: a macro counts as the spell or item it shows (its subType). `text` is the macro's
-- name, for macros only.
function Engine.ReadSlot(slot)
	local kind, id, subType = GetActionInfo(slot);
	if not kind then
		return nil;
	end
	return {
		kind = kind, id = id, subType = subType,
		shows = (kind == "macro") and subType or kind,
		text = (kind == "macro") and Engine.GetSlotActionText(slot) or nil,
	};
end

-- Every slot that holds something: slot -> ReadSlot(slot).
function Engine.ScanActionSlots()
	local slots = {};
	for slot = 1, MAX_ACTION_SLOT do
		slots[slot] = Engine.ReadSlot(slot);
	end
	return slots;
end
