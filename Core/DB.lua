-- Saved data: per character, since gestures depend on the character's spells.
--
-- GestureCommandsCharDB = {
--     version = 1,                 -- schema version (MIGRATIONS below)
--     gestures = { gesture, ... }, -- gesture = { trigger = action, hold = action, long = action, name = string, icon = fileID,
--                                  --             slots = { [action slot] = true } } (the slots it's bound to;
--                                  --             nil on gestures from before 1.1.0 until GestureSlots.lua records them)
--                                  -- action = { kind = "spell"|"item"|"toy"|"mount"|"macro", id = number, name = string }
--     enabled = false,             -- only when turned off (on by default)
--     holdTicks, hold2Ticks,       -- only when changed from the defaults
--     debug, ownNavigation, minimapAngle, minimapHidden,
-- }

local _, ns = ...;

local DEFAULT_HOLD_TICKS, DEFAULT_HOLD2_TICKS = 3, 7;
ns.DEFAULT_HOLD_TICKS, ns.DEFAULT_HOLD2_TICKS = DEFAULT_HOLD_TICKS, DEFAULT_HOLD2_TICKS;

-- Each entry brings the saved data from the previous version to its own. Add new ones at the end; never
-- change one that has shipped.
local MIGRATIONS = {
	-- 1: the gesture list.
	function(db)
		db.gestures = db.gestures or {};
	end,
};

local function DB()
	return GestureCommandsCharDB;
end
ns.DB = DB;

ns.On("ADDON_LOADED", function(_, addonName)
	if addonName ~= ns.ADDON_NAME then
		return;
	end
	GestureCommandsCharDB = GestureCommandsCharDB or {};
	local db = GestureCommandsCharDB;
	for version = (db.version or 0) + 1, #MIGRATIONS do
		MIGRATIONS[version](db);
		db.version = version;
	end
end);

function ns.GetHoldTicks()
	return DB().holdTicks or DEFAULT_HOLD_TICKS;
end

function ns.GetHold2Ticks()
	return math.max(DB().hold2Ticks or DEFAULT_HOLD2_TICKS, ns.GetHoldTicks() + 2);
end
