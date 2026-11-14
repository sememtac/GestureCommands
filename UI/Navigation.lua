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
