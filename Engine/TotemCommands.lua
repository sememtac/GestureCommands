-- Totem Commands, the shaman-only addon Gesture Commands grew out of, wraps the same buttons; both acting on
-- one press would cast twice, so Gesture Commands stays off while it is on.

local _, ns = ...;
local Engine = ns.Engine;

function ns.IsTotemCommandsActive()
	return TotemCommandsHeader ~= nil and TotemCommandsHeader:GetAttribute("enabled") == true;
end

-- Totem Commands is one fixed gesture. Switching moves it over: that gesture (unless there already is one
-- on Call of the Elements), its hold lengths, and Totem Commands turned off through its own command. Spells
-- by name for the rank the character knows, with the IDs for other languages.
local TOTEM_SPELLS = {
	trigger = { 66842, "Call of the Elements" },
	hold = { 36936, "Totemic Recall" },
	long = { 437009, "Totemic Call" },
};

local function GetTotemSpell(mode)
	local id, name = TOTEM_SPELLS[mode][1], TOTEM_SPELLS[mode][2];
	local info = C_Spell.GetSpellInfo(name);
	id = info and info.spellID or id;
	name = C_Spell.GetSpellName(id) or name;
	return { kind = "spell", id = id, name = name };
end

function ns.SwitchFromTotemCommands()
	if InCombatLockdown() then
		ns.Print("can't switch in combat.");
		return false;
	end
	local db = ns.DB();
	local trigger = GetTotemSpell("trigger");
	local index;
	for existing, gesture in ipairs(db.gestures) do
		local shown = Engine.ResolveShown(gesture.trigger);
		if shown and shown.kind == "spell" and C_Spell.GetSpellName(shown.id) == trigger.name then
			index = existing;
		end
	end
	if not index then
		table.insert(db.gestures, { trigger = trigger, hold = GetTotemSpell("hold"), long = GetTotemSpell("long"), slots = {} });
		index = #db.gestures;
	end
	-- Totem Commands acted on every slot holding Call of the Elements: so does the gesture.
	Engine.BindAllSlotsHolding(db.gestures[index]);
	local totemDB = TotemCommandsDB;
	if totemDB then
		db.holdTicks = db.holdTicks or totemDB.holdTicks;
		db.hold2Ticks = db.hold2Ticks or totemDB.hold2Ticks;
	end
	if SlashCmdList.TOTEMCOMMANDS then
		SlashCmdList.TOTEMCOMMANDS("off");
	end
	db.enabled = true;
	ns.Publish();
	ns.Print(ns.IsTotemCommandsActive() and "couldn't turn Totem Commands off - type /totemcommands off."
		or "switched: your totem gesture is set up here, and Totem Commands is off (you can remove it).");
	return index;
end
