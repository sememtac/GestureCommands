-- The gamepad crossbar's buttons.

local _, ns = ...;
local Engine = ns.Engine;

function Engine.GetPageUnit()
	return GamepadMainActionBarFrame and GamepadMainActionBarFrame.PageUnit;
end

-- The crossbar buttons that hold bindable actions: the top bar's left cluster (its right cluster is
-- Interact/Inspect/Back/Jump), all eight buttons of the left, right and bottom bars, and the stance and
-- possess bars that can take over one of those bars' slots. Returns { button, bar = key, index }.
local LAYOUT = { { "topBar", 4 }, { "leftBar", 8 }, { "rightBar", 8 }, { "bottomBar", 8 }, { "stanceBar", 8 }, { "possessBar", 8 } };

function ns.GetCrossbarButtons()
	local pageUnit = Engine.GetPageUnit();
	local bars = pageUnit and pageUnit.actionBars;
	if not bars then
		return {};
	end

	local buttons = {};
	for _, entry in ipairs(LAYOUT) do
		local barKey, count = entry[1], entry[2];
		local bar = bars[barKey];
		for index = 1, count do
			local button = bar and bar.GetActionButtonByIndex and bar:GetActionButtonByIndex(index);
			-- Only standard action buttons; the possess bar uses pet buttons.
			if button and button.GetAttribute and button:GetAttribute("type") == "action" then
				table.insert(buttons, { button = button, bar = barKey, index = index });
			end
		end
	end
	return buttons;
end

function Engine.GetButtonSlot(button)
	return button.action or button:GetID();
end
