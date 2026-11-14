-- Gestures: a Tap ("trigger"), optional hold and long-hold actions, and an optional name and icon that label
-- it in the setup window and on the crossbar buttons that hold its Tap (Labels.lua).

local _, ns = ...;

local NAME_LENGTH = 16;
local QUESTION_MARK_ICON = 134400; -- "automatic": the Tap action's icon

local function TruncateUTF8(text, maxChars)
	local out, count = {}, 0;
	for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		count = count + 1;
		if count > maxChars then
			break;
		end
		table.insert(out, char);
	end
	return table.concat(out);
end

function ns.GetGestureName(gesture)
	if gesture.name and gesture.name ~= "" then
		return gesture.name;
	end
	local triggerName = ns.GetActionDisplay(gesture.trigger);
	return TruncateUTF8(triggerName or "Gesture", NAME_LENGTH);
end

function ns.GetGestureIcon(gesture)
	if gesture.icon then
		return gesture.icon;
	end
	local _, icon = ns.GetActionDisplay(gesture.trigger);
	return icon or QUESTION_MARK_ICON;
end

function ns.AddGesture(gesture)
	gesture = gesture or {};
	table.insert(ns.DB().gestures, gesture);
	ns.Publish();
	return #ns.DB().gestures;
end

function ns.RemoveGesture(index)
	table.remove(ns.DB().gestures, index);
	ns.Publish();
end

function ns.SetGestureAction(index, mode, action)
	local gesture = ns.DB().gestures[index];
	if not gesture then
		return;
	end
	gesture[mode] = action;
	ns.Publish();
end

-- An empty name or nil icon goes back to the Tap action's.
function ns.SetGestureNameIcon(index, name, icon)
	local gesture = ns.DB().gestures[index];
	if not gesture then
		return;
	end
	name = name and strtrim(name) or "";
	gesture.name = name ~= "" and TruncateUTF8(name, NAME_LENGTH) or nil;
	gesture.icon = (icon and icon ~= QUESTION_MARK_ICON) and icon or nil;
	ns.RefreshCrossbarLabels();
	if ns.OnPublished then
		ns.OnPublished();
	end
end
