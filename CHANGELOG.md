# Gesture Commands

## Unreleased

First release.

- Tap, hold and long-hold gestures for anything on the gamepad crossbar: a gesture attaches to a spell or
  item on a crossbar slot (or a macro that shows one); a tap does what the slot normally does, a hold and
  a longer hold cast what you assign.
- Hold actions can be spells, items, toys, mounts or macros.
- Gestures are macros for your gamepad: each has a name and icon (chosen like a macro's) and is stored as a
  character macro you can place on the crossbar.
- Setup window (`/gestures`, or Options > AddOns): choose actions from your spells, items, mounts and
  macros (or drag them in), Place on bar / drag gestures out, hold timing.
- Full controller support in the setup window, through the game's controller navigation like Blizzard's
  own windows (LT / RT, View, A, B), using only the calls Blizzard provides for addons, so it doesn't
  taint the crossbar. `/gestures padnav own` switches to the window's own D-pad navigation instead.
- `/gestures on|off|test|debug|hold <n>|hold2 <n>|padnav own|blizzard`.
