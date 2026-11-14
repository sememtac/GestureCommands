# Gesture Commands

## 1.0.1

- The Tap can be any spell, item, toy, mount or macro. Before, it had to be a spell, an item, or a macro
  that shows one.
- Fixed: pressing another crossbar button while holding a gesture cancelled the gesture.
- Fixed: with `/gestures padnav own`, the D-pad and A / B / X stayed with the window in combat.
- Fixed: the window's and the picker's close buttons didn't work in combat.
- Fixed: Bind with a mouse click also cast the slot's action; a bind that didn't take said "placed";
  cancelling a bind in combat did nothing.
- Fixed: after a reload in combat, holds didn't work until the next reload.
- Fixed: OK in Name & icon kept the Tap's name even after the Tap changed.
- Fixed: the picker could save to another gesture if you selected or deleted one while it was open.
- New gesture is off at 10 gestures, the most the list shows.
- Secure code the game would refuse is reported at load and by `/gestures test`.

## 1.0.0

Initial release.

- Tap, hold and long-hold gestures for gamepad crossbar buttons. Actions fire on release, with rumble and
  an on-screen prompt at each stage.
- Tap takes a spell, item or macro. Hold and Long hold also take toys and mounts.
- Setup window with full controller support through the game's controller navigation.
- One-step binding to any crossbar button, on any bar and page.
- Custom gesture name and icon, shown on the crossbar button.
- Open from the main menu dial, minimap button, addon compartment, key binding, Options > AddOns, or
  `/gestures`.
- Switch from Totem Commands: recreates its totem gesture and disables it.
- Commands: `/gestures on`, `off`, `test`, `hold`, `hold2`, `minimap`, `debug`, `padnav`.
