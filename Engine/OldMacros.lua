-- Before 0.10 the addon made a character macro for every gesture ("/cast <Tap>" or "/use item:<id>").
-- Remove the ones that are still exactly that, after putting the Tap itself on any action slot that held
-- one so bound gestures keep working. A macro the player has edited is left alone. Once per session, out of
-- combat, after the action slots are known (on entering the world).

local _, ns = ...;
local Engine = ns.Engine;

local MAX_ACCOUNT_MACROS = MAX_ACCOUNT_MACROS or 120;

-- Returns false to be retried.
local function RemoveOldGestureMacros()
	if InCombatLockdown() then
		return false;
	end
	local removed = 0;
	for index, gesture in ipairs(ns.DB().gestures) do
		local name, trigger = gesture.macro, gesture.trigger;
		gesture.macro = nil;
		local macroIndex = name and GetMacroIndexByName(name);
		if macroIndex and macroIndex > MAX_ACCOUNT_MACROS and trigger and (trigger.kind == "spell" or trigger.kind == "item") then
			local _, _, body = GetMacroInfo(macroIndex);
			local madeBody = trigger.kind == "item" and ("/use item:" .. trigger.id)
				or ("/cast " .. (C_Spell.GetSpellName(trigger.id) or trigger.name or ""));
			if body and strtrim(body) == madeBody then
				for slot = 1, Engine.MAX_ACTION_SLOT do
					if GetActionInfo(slot) == "macro" and Engine.GetSlotActionText(slot) == name and ns.PickupGesture(index) then
						(C_ActionBar.PutActionInSlot or PlaceAction)(slot);
						ClearCursor();
					end
				end
				DeleteMacro(macroIndex);
				removed = removed + 1;
			end
		end
	end
	if removed > 0 then
		ns.Print(("removed %d macro%s that earlier versions made for your gestures; action slots that held them now hold the Tap itself."):format(
			removed, removed == 1 and "" or "s"));
	end
	return true;
end

local checked = false;
local function Check()
	if not checked then
		checked = RemoveOldGestureMacros();
	end
end
ns.On("PLAYER_ENTERING_WORLD", Check);
ns.On("PLAYER_REGEN_ENABLED", Check);
