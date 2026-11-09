# Gesture Commands

## Unreleased

First release.

- Tap, hold and long-hold gestures for anything on the gamepad crossbar: a gesture attaches to a spell or
  item on a crossbar slot (or a macro that shows one); a tap does what the slot normally does, a hold and
  a longer hold cast what you assign.
- Hold actions can be spells, items, toys, mounts or macros.
- The Tap can be a spell, an item, or one of your macros that shows one; the gesture is whatever crossbar
  slot holds it. Gesture Commands creates no macros (and removes the ones versions before 0.10 made).
  Optional name and icon, shown on the crossbar buttons that hold the gesture's Tap.
- Setup window (minimap button, the minimap's addons menu, `/gestures`, or Options > AddOns): choose actions from your spells, items, mounts and
  macros (or drag them in), hold timing; **Bind** puts a gesture on the next crossbar button you press
  (or drag it onto the crossbar).
- Full controller support in the setup window, through the game's controller navigation like Blizzard's
  own windows (LT / RT, View, A, B), using only the calls Blizzard provides for addons, so it doesn't
  taint the crossbar, with the game's LT / RT / View jump hints, focus glow and button prompts.
  `/gestures padnav own` switches to the window's own D-pad navigation instead.
- `/gestures on|off|test|debug|hold <n>|hold2 <n>|minimap|padnav own|blizzard`.
- Addon icon; a key binding to open the setup window.
