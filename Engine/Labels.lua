-- Gesture icons and names on the crossbar. A gesture with its own icon or name shows it on every crossbar
-- button that holds its Tap: the icon in the button's icon, the name in the text line macros use. Whenever
-- Blizzard sets either we set ours over it, in hooksecurefunc post-hooks so Blizzard's code stays untainted;
-- the icon's mask, cooldown and usable / range colouring stay Blizzard's. Out-of-combat changes to gestures
-- are applied with RefreshCrossbarLabels.

local _, ns = ...;
local Engine = ns.Engine;

local regionButtons = {}; -- crossbar button icon texture / name font string -> its button
local shownIcons, shownNames = {}, {}; -- crossbar button -> the gesture icon / name we put on it
local settingRegion = false;

local function SetRegion(region, method, value)
	settingRegion = true;
	region[method](region, value);
	settingRegion = false;
end

local function OnIconSet(texture)
	if settingRegion then
		return;
	end
	local button = regionButtons[texture];
	local gesture = Engine.GetSlotGesture(Engine.GetButtonSlot(button));
	shownIcons[button] = gesture and gesture.icon;
	if shownIcons[button] then
		SetRegion(texture, "SetTexture", shownIcons[button]);
	end
end

local function OnNameSet(fontString)
	if settingRegion then
		return;
	end
	local button = regionButtons[fontString];
	local gesture = Engine.GetSlotGesture(Engine.GetButtonSlot(button));
	shownNames[button] = gesture and gesture.name;
	if shownNames[button] then
		SetRegion(fontString, "SetText", shownNames[button]);
	end
end

function ns.RefreshCrossbarLabels()
	local any = false;
	for _, gesture in ipairs(ns.DB().gestures) do
		any = any or gesture.icon ~= nil or gesture.name ~= nil;
	end
	if any then
		for _, info in ipairs(ns.GetCrossbarButtons()) do
			local button = info.button;
			if button.icon and not regionButtons[button.icon] then
				regionButtons[button.icon] = button;
				hooksecurefunc(button.icon, "SetTexture", OnIconSet);
			end
			if button.Name and not regionButtons[button.Name] then
				regionButtons[button.Name] = button;
				hooksecurefunc(button.Name, "SetText", OnNameSet);
			end
		end
	end
	for region, button in pairs(regionButtons) do
		local slot = Engine.GetButtonSlot(button);
		local gesture = Engine.GetSlotGesture(slot);
		if region == button.icon then
			local icon = gesture and gesture.icon;
			if icon then
				SetRegion(region, "SetTexture", icon);
			elseif shownIcons[button] then
				-- No longer a gesture with an icon: back to the action's own.
				SetRegion(region, "SetTexture", C_ActionBar.GetActionTexture(slot));
			end
			shownIcons[button] = icon;
		else
			local name = gesture and gesture.name;
			if name then
				SetRegion(region, "SetText", name);
			elseif shownNames[button] then
				SetRegion(region, "SetText", C_ActionBar.UsesActionText(slot) and C_ActionBar.GetActionText(slot) or "");
			end
			shownNames[button] = name;
		end
	end
end
