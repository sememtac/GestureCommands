# Engine API

What `UI/` may use. Everything else in the engine is internal and goes through `ns.Engine`.
`tests/ui_test.lua` fakes exactly this list, and `tests/engine_test.lua` checks that the real engine
provides all of it. Keep the three in step.

## Data

| Name | |
|---|---|
| `ns.DB()` | Saved data for this character (layout in `Core/DB.lua`). |
| `ns.MODES` | The hold stages, in order: `{ "hold", "long" }`. |
| `ns.MODE_LABELS` | What the window calls each action: `trigger` "Tap", `hold`, `long`. |
| `ns.conflicts` | Gesture number → the gesture number it shares a Tap with (from the last publish). |
| `ns.GetHoldTicks()`, `ns.GetHold2Ticks()` | Hold and long-hold lengths, in secure ticks (about 0.2 s each). |

## Actions

An action is `{ kind = "spell"|"item"|"toy"|"mount"|"macro", id = number, name = string }`. A macro
has only its name.

| Name | |
|---|---|
| `ns.GetActionDisplay(action)` | Name and icon. |
| `ns.ReadCursor()` | The action on the cursor, or nil and the cursor type. |
| `ns.MakeTrigger(action)` | The action if it can be a Tap, else nil. |

## Gestures

A gesture is `{ trigger = action, hold = action, long = action, name = string, icon = fileID }`.
Gestures are numbered by their position in `ns.DB().gestures`.

| Name | |
|---|---|
| `ns.GetGestureName(gesture)`, `ns.GetGestureIcon(gesture)` | The chosen name and icon, or the Tap's. |
| `ns.AddGesture(gesture)` | Adds it and returns its number. |
| `ns.RemoveGesture(index)` | |
| `ns.SetGestureAction(index, mode, action)` | `mode` is `"trigger"`, `"hold"` or `"long"`; nil clears it. |
| `ns.SetGestureNameIcon(index, name, icon)` | An empty name or nil icon goes back to the Tap's. |
| `ns.SetEnabled(enabled)` | Returns false if it can't change now (combat, Totem Commands on). |
| `ns.Publish()` | Applies the configuration to the secure engine. Returns false in combat (retried after). |

## Putting a gesture on the crossbar

| Name | |
|---|---|
| `ns.PickupGesture(index)` | Puts the gesture's Tap on the cursor (mouse); the slot it's dropped on is bound to the gesture. |
| `ns.StartPlacing(index)` | Place mode (controller): the next crossbar press picks the slot. |
| `ns.IsPlacing()`, `ns.CancelPlacing(quiet)` | |

## Totem Commands

| Name | |
|---|---|
| `ns.IsTotemCommandsActive()` | |
| `ns.SwitchFromTotemCommands()` | Moves its gesture over and turns it off. |

## Other

| Name | |
|---|---|
| `ns.Print(text)` | Chat message with the addon's prefix. |
| `ns.RunTest()` | `/gestures test`. |

## Callbacks the UI sets

| Name | |
|---|---|
| `ns.OnPublished()` | After every publish, and after a name or icon change. |
| `ns.OnPlacingChanged(gesture, endsAt)` | Place mode started (`endsAt` is a `GetTime()` deadline) or ended (nil). |
| `ns.ToggleConfig()`, `ns.CloseConfig()`, `ns.ToggleMinimapButton()` | Used by the slash command. |
