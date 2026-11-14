-- Gesture Commands: controller navigation for our windows. Open a window's panel with ns.Nav.Open(panel,
-- isPopup) from OnShow and ns.Nav.Close(panel) from OnHide.
--
-- Two modes, each in its own file:
-- - "blizzard" (GamepadUI.lua, the default when the game is in controller mode): the windows join Blizzard's
--   gamepad UI like its own panels: LT / RT and the View button reach them, SmartNavigation moves its cursor
--   over their buttons, A clicks and B closes.
-- - "own" (OwnNavigation.lua, `/gestures padnav own`): our own D-pad, A, B and X bindings and highlight, over
--   the controls a panel lists in GetNavControls() (GetNavDefault() picks the first).
-- Both honour a control's OnSmartNavClick and a panel's SmartNavigationCloseHandler. A mode is
-- { Open(panel, isPopup), Close(panel), Refresh(panel) } in Nav.modes.
--
-- A panel can also list its controls in rows (panel:GetNavRows(): top to bottom, each left to right). Then,
-- in both modes, left / right move along the row and up / down go to the next row above / below with a
-- usable control, to the one nearest in X. Without rows, each mode moves to the nearest control in the
-- direction, which can leave a row for a nearer control below it.

local _, ns = ...;

local Nav = { modes = {} };
ns.Nav = Nav;

local panelModes = {}; -- open panel -> mode name

function Nav.UsesGamepadUI()
	return C_InputInterfaceStyle ~= nil and C_InputInterfaceStyle.GetCurrentStyle() == Enum.InputDeviceInterfaceType.Gamepad;
end

function Nav.UsesOwnNavigation()
	return ns.DB().ownNavigation == true;
end

function Nav.Open(panel, isPopup)
	local mode = Nav.UsesOwnNavigation() and "own" or (Nav.UsesGamepadUI() and "blizzard") or nil;
	panelModes[panel] = mode;
	if mode then
		Nav.modes[mode].Open(panel, isPopup);
	end
end

function Nav.Close(panel)
	local mode = panelModes[panel];
	panelModes[panel] = nil;
	if mode then
		Nav.modes[mode].Close(panel);
	end
end

-- After a panel shows, hides or disables some of its controls.
function Nav.Refresh(panel)
	local mode = Nav.modes[panelModes[panel] or "own"];
	mode.Refresh(panel);
end

-------------------------------------------------------------------------------
-- Rows
-------------------------------------------------------------------------------

Nav.DIRECTIONS = { "UP", "DOWN", "LEFT", "RIGHT" };
local STEPS = { UP = { -1, 0 }, DOWN = { 1, 0 }, LEFT = { 0, -1 }, RIGHT = { 0, 1 } }; -- rows, columns

function Nav.IsUsable(control)
	return control ~= nil and control:IsVisible() and (control.IsEnabled == nil or control:IsEnabled()) and true or false;
end

-- Where a direction ("UP", "DOWN", "LEFT", "RIGHT") goes from a control: the control, or nil to stay. The
-- second result is false if the control isn't in any row.
function Nav.FindInRows(rows, from, direction)
	local step = STEPS[direction];
	for rowIndex, row in ipairs(rows) do
		for columnIndex, control in ipairs(row) do
			if control == from then
				if step[2] ~= 0 then
					local last = step[2] > 0 and #row or 1;
					for index = columnIndex + step[2], last, step[2] do
						if Nav.IsUsable(row[index]) then
							return row[index], true;
						end
					end
					return nil, true;
				end
				local fromX = from:GetCenter();
				local last = step[1] > 0 and #rows or 1;
				for index = rowIndex + step[1], last, step[1] do
					local best, bestDistance;
					for _, candidate in ipairs(rows[index]) do
						if Nav.IsUsable(candidate) then
							local x = candidate:GetCenter();
							local distance = (fromX and x) and math.abs(x - fromX) or 0;
							if not bestDistance or distance < bestDistance then
								best, bestDistance = candidate, distance;
							end
						end
					end
					if best then
						return best, true;
					end
				end
				return nil, true;
			end
		end
	end
	return nil, false;
end
