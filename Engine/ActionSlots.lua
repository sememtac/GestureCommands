-- Action slots: what each one holds, scanned once per Publish rather than once per gesture.

local _, ns = ...;
local Engine = ns.Engine;

local MAX_ACTION_SLOT = 400; -- Covers the keyboard bars and the gamepad action storage (181+).
Engine.MAX_ACTION_SLOT = MAX_ACTION_SLOT;

function Engine.GetSlotActionText(slot)
	return (C_ActionBar.GetActionText or GetActionText)(slot);
end

local Scan = {};
Scan.__index = Scan;

-- C_Spell.GetSpellName, remembered for the scan.
function Scan:SpellName(id)
	local name = self.spellNames[id];
	if name == nil then
		name = C_Spell.GetSpellName(id) or false;
		self.spellNames[id] = name;
	end
	return name or nil;
end

-- Returns a scan: scan.slots[slot] = { kind, id, subType (GetActionInfo), shows, text } for every slot that
-- holds something. `shows` is what the secure code sees the slot as: a macro counts as the spell or item it
-- shows (its subType). `text` is the macro's name, for macros only.
function Engine.ScanActionSlots()
	local scan = setmetatable({ slots = {}, spellNames = {} }, Scan);
	for slot = 1, MAX_ACTION_SLOT do
		local kind, id, subType = GetActionInfo(slot);
		if kind then
			scan.slots[slot] = {
				kind = kind, id = id, subType = subType,
				shows = (kind == "macro") and subType or kind,
				text = (kind == "macro") and Engine.GetSlotActionText(slot) or nil,
			};
		end
	end
	return scan;
end
