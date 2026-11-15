-- Where gestures are on the crossbar: a gesture is on the action slots it was bound to (gesture.slots),
-- while they still hold its Tap. The same spell put on another slot some other way (the spellbook, the
-- game's bind screen) is just that spell: its own icon, cast on press.
--
-- A slot is recorded when Bind's crossbar press puts the Tap there (Binding.lua), when the gesture dragged
-- out of the window is dropped there, when a bound action is moved there with the cursor (the crossbar's
-- edit mode does that), when Totem Commands is switched over, and once for gestures from before 1.1.0. It
-- stops being the gesture's when the player puts something else there, or binds another gesture there.
-- Players change slots through the cursor (dragging, the spellbook, bags, the game's bind screen and edit
-- mode all pick up and place); bars that change by themselves (another talent spec's bars) leave the
-- gesture on its slot, inactive until its Tap is back.

local _, ns = ...;
local Engine = ns.Engine;

local DROP_TIMEOUT = 60; -- seconds a gesture picked up from the window may wait on the cursor
local worldEntered = false; -- before that, the action slots may read empty
local expected = nil; -- { gesture = gesture whose Tap is on the cursor, untilTime = GetTime() deadline }
local cursorChangedAt = nil; -- GetTime() of the last cursor change (the same in one frame)

function Engine.BindGestureSlot(gesture, slot)
	for _, other in ipairs(ns.DB().gestures) do
		if other ~= gesture and other.slots then
			other.slots[slot] = nil;
		end
	end
	gesture.slots = gesture.slots or {};
	gesture.slots[slot] = true;
end

-- Binds the gesture to every slot that holds its Tap now. `scan` is Engine.ScanActionSlots(), if read.
function Engine.BindAllSlotsHolding(gesture, scan)
	gesture.slots = gesture.slots or {};
	local trigger = gesture.trigger;
	local kind = trigger and Engine.ActionKinds[trigger.kind];
	if not kind then
		return;
	end
	local context = kind.SlotContext and kind.SlotContext(trigger);
	for slot, info in pairs(scan or Engine.ScanActionSlots()) do
		if Engine.SlotHolds(trigger, info, context) then
			Engine.BindGestureSlot(gesture, slot);
		end
	end
end

-- The gesture's Tap is on the cursor (ns.PickupGesture): the slot it's dropped on becomes the gesture's.
function Engine.ExpectDrop(gesture)
	expected = { gesture = gesture, untilTime = GetTime() + DROP_TIMEOUT };
end

-- The gesture expected to be dropped: not after the timeout, nor once it's deleted.
local function ExpectedGesture()
	if expected and GetTime() > expected.untilTime then
		expected = nil;
	end
	if expected then
		for _, gesture in ipairs(ns.DB().gestures) do
			if gesture == expected.gesture then
				return gesture;
			end
		end
		expected = nil;
	end
	return nil;
end

-- Before 1.1.0 a gesture was on every slot holding its Tap (a macro showing it too). Those gestures have
-- no slots yet: record them once, when the action slots can be read. Returns false to be retried.
function Engine.MigrateGestureSlots()
	local legacy = {};
	for _, gesture in ipairs(ns.DB().gestures) do
		if gesture.slots == nil then
			table.insert(legacy, gesture);
		end
	end
	if #legacy == 0 then
		return true;
	end
	local scan = Engine.ScanActionSlots();
	if next(scan) == nil then
		return false; -- the bars haven't loaded
	end
	for _, gesture in ipairs(legacy) do
		Engine.BindAllSlotsHolding(gesture, scan);
	end
	return true;
end

local migrated = false;
local function Migrate()
	if not migrated then
		migrated = Engine.MigrateGestureSlots();
	end
end

ns.On("PLAYER_ENTERING_WORLD", function()
	worldEntered = true;
	Migrate();
end);
ns.On("PLAYER_REGEN_ENABLED", Migrate);

ns.On("ACTIONBAR_SLOT_CHANGED", function(_, slot)
	if not worldEntered or not slot or slot == 0 then
		return;
	end
	Migrate();
	-- The gesture on the cursor dropped here.
	local dropped = ExpectedGesture();
	if dropped and dropped.trigger and Engine.SlotHoldsTrigger(slot, dropped.trigger) then
		Engine.BindGestureSlot(dropped, slot);
		expected = nil;
	end
	-- A bound slot the player put something else on isn't the gesture's. If the Tap is now on the cursor,
	-- it's being moved: the slot it's dropped on is. (The cursor is busy, or just changed, when the player
	-- changes a slot; a change without it leaves the record.)
	if GetCursorInfo() == nil and cursorChangedAt ~= GetTime() then
		return;
	end
	for _, gesture in ipairs(ns.DB().gestures) do
		if gesture.slots and gesture.slots[slot] and not (gesture.trigger and Engine.SlotHoldsTrigger(slot, gesture.trigger)) then
			gesture.slots[slot] = nil;
			if gesture.trigger and Engine.CursorHoldsTrigger(gesture.trigger) then
				Engine.ExpectDrop(gesture);
			end
		end
	end
end);

-- The drag ended elsewhere (dropped on nothing, or something else picked up): forget it. A frame later, so
-- a drop's slot change is seen first.
ns.On("CURSOR_CHANGED", function()
	cursorChangedAt = GetTime();
	if expected then
		C_Timer.After(0, function()
			local gesture = ExpectedGesture();
			if gesture and not Engine.CursorHoldsTrigger(gesture.trigger) then
				expected = nil;
			end
		end);
	end
end);
