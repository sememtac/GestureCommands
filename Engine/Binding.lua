-- Putting a gesture on the crossbar: its Tap action goes on a crossbar slot, and that slot is then bound to
-- the gesture (GestureSlots.lua). With a mouse the Tap is put on the cursor (PickupGesture). With a
-- controller there is no way to drop a cursor action on the crossbar, so in place mode the next crossbar
-- press (caught and swallowed by the secure hook) picks the slot and the Tap is put there out of combat. Place mode times out if no crossbar
-- button is pressed; the setup window shows a banner meanwhile (ns.OnPlacingChanged).

local _, ns = ...;
local Engine = ns.Engine;
local header = ns.header;

-- Puts the gesture's Tap action on the cursor so it can be dropped on a crossbar slot.
function ns.PickupGesture(index)
	if InCombatLockdown() then
		ns.Print("can't place actions in combat.");
		return false;
	end
	local gesture = ns.DB().gestures[index];
	local trigger = gesture and gesture.trigger;
	if not trigger then
		ns.Print("choose this gesture's Tap first.");
		return false;
	end
	local ok, message = Engine.PickupAction(trigger);
	if ok then
		Engine.ExpectDrop(gesture);
	elseif message then
		ns.Print(message);
	end
	return ok;
end

local PLACE_TIMEOUT = 60;
local placing = nil; -- { index = gesture index, token = unique id, endsAt = GetTime() deadline }

function ns.IsPlacing()
	return placing ~= nil;
end

local function NotifyPlacing()
	if ns.OnPlacingChanged then
		ns.OnPlacingChanged(placing and ns.DB().gestures[placing.index], placing and placing.endsAt);
	end
end

function ns.CancelPlacing(quiet)
	if not placing then
		return;
	end
	if InCombatLockdown() then
		-- Can't change the secure state in combat: cancel when it ends. No press binds in combat anyway,
		-- so the banner goes now.
		if ns.OnPlacingChanged then
			ns.OnPlacingChanged(nil);
		end
		local token = placing.token;
		ns.AfterCombat(function()
			if placing and placing.token == token then
				ns.CancelPlacing(quiet);
			end
		end);
		return;
	end
	placing = nil;
	header:SetAttribute("placing", false);
	header:SetAttribute("placeSlot", nil);
	NotifyPlacing();
	if not quiet then
		ns.Print("bind cancelled (no crossbar button pressed).");
	end
end

function ns.StartPlacing(index)
	if InCombatLockdown() then
		ns.Print("can't place actions in combat.");
		return false;
	end
	local gesture = ns.DB().gestures[index];
	if not (gesture and gesture.trigger) then
		ns.Print("choose this gesture's Tap first.");
		return false;
	end
	if not Engine.IsAvailable(gesture.trigger) then
		ns.Print(("this gesture's Tap (%s) isn't available any more - choose it again."):format(tostring(ns.GetActionDisplay(gesture.trigger))));
		return false;
	end
	Engine.WrapCrossbarButtons();
	local token = {};
	placing = { index = index, token = token, endsAt = GetTime() + PLACE_TIMEOUT };
	header:SetAttribute("placeSlot", nil);
	header:SetAttribute("placing", true);
	UIErrorsFrame:AddMessage(("Press the crossbar button for %s"):format(ns.GetGestureName(gesture)), 0.2, 1, 0.6);
	NotifyPlacing();
	C_Timer.After(PLACE_TIMEOUT, function()
		if placing and placing.token == token then
			ns.CancelPlacing();
		end
	end);
	return true;
end

-- Called by the feedback poll (Feedback.lua) when the secure hook has reported a slot.
function ns.FinishPlacing(slot)
	local index = placing and placing.index;
	local gesture = index and ns.DB().gestures[index];
	placing = nil;
	header:SetAttribute("placeSlot", nil);
	NotifyPlacing();
	if not (gesture and ns.PickupGesture(index)) then
		return;
	end
	(C_ActionBar.PutActionInSlot or PlaceAction)(slot);
	ClearCursor();
	if Engine.SlotHoldsTrigger(slot, gesture.trigger) then
		Engine.BindGestureSlot(gesture, slot);
		ns.Publish();
		UIErrorsFrame:AddMessage(("%s placed"):format(ns.GetGestureName(gesture)), 0.2, 1, 0.6);
		Engine.Rumble();
	else
		ns.Print("couldn't place the gesture on that slot.");
	end
end
