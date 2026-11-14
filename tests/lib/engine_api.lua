-- The engine functions and data the UI may use (Engine/API.md). ui_test.lua's fake engine provides all of
-- them, engine_test.lua checks the real engine does, and static_test.lua checks the UI uses nothing else.
return {
	"DB", "MODES", "MODE_LABELS", "conflicts", "GetHoldTicks", "GetHold2Ticks",
	"GetActionDisplay", "ReadCursor", "MakeTrigger",
	"GetGestureName", "GetGestureIcon", "AddGesture", "RemoveGesture", "SetGestureAction", "SetGestureNameIcon",
	"SetEnabled", "Publish",
	"PickupGesture", "StartPlacing", "IsPlacing", "CancelPlacing",
	"IsTotemCommandsActive", "SwitchFromTotemCommands",
	"Print", "RunTest",
	-- Core
	"On", "AfterCombat", "Snippet",
}
