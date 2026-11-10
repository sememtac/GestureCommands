# Gesture Commands

Tap, hold and long-hold gestures for anything on your gamepad crossbar in **World of Warcraft: Forever**.

A gesture gives one crossbar button three actions: a **Tap**, a **Hold** and a **Long hold**. Bind it to a
crossbar button, and when you press that button:

| You do | You feel / see | On release |
|---|---|---|
| **Tap** | nothing | the slot does what it normally does |
| **Hold** (~0.6 s) | a rumble, "Release for …" | casts your **Hold** action |
| **Keep holding** (~1.4 s) | a double rumble, "Release for …" | casts your **Long hold** action |

Hold actions can be **spells, items, toys, mounts or macros**. Nothing is cast until you let go, so you can
hold past a stage you don't want, and a stage you leave empty is simply skipped. The slot keeps its own
icon and cooldown, and every other button works exactly as before.

## Setup

1. Open the window: with a controller, from the game's main menu dial (menu button, RB to its last page,
   point the right stick at **Gesture Commands** and let go - again to close it, like Bags). Or click the
   Gesture Commands button on the minimap (or pick it in the minimap's addons menu), type `/gestures`, use
   Options > AddOns > Gesture Commands, or set a key for it in Options > Keybindings > AddOns.
2. **New gesture**, then fill the three boxes - click a box to choose from your spells, items, mounts and
   macros, or drag something onto it:
   - **Tap**: a spell, an item, or one of your macros that shows a spell or item (`#showtooltip`). A tap casts
     or runs it, and it's what goes on the crossbar.
   - **Hold** and **Long hold**: whatever you want those to cast.
3. Optional: **Name & icon** (or click the gesture's icon). Both show on the crossbar buttons that hold the
   gesture's Tap - the name as the button's text line, like a macro's (cooldowns and range / mana colouring
   stay as usual).
4. **Bind**: with a controller, the window closes - press the crossbar button you want the gesture on (L1 / R1
   for the other bars, both shoulders + D-pad left / right for another page; nothing is cast by that press).
   A banner shows what you're binding and the time left (60 s); open `/gestures` to cancel. In combat your
   buttons work normally and the bind waits for a press after the fight. With a mouse, Bind (or dragging the
   gesture from the list) puts its Tap on your cursor to drop on a crossbar slot.
5. Press **Test** to check your setup. Gesture Commands is on by default; untick **Enabled** to switch it off.

Gesture Commands doesn't create macros. Any crossbar slot that holds the gesture's Tap - the spell or item,
or your macro - is the gesture, however it got there, and shows the gesture's name and icon if you chose
them.

### With a controller

The window works with the game's controller navigation like Blizzard's own windows: **LT / RT** switch
between it and other open windows (bags, spellbook...), the **View** button switches between the game and
the windows, the D-pad moves between buttons, **A** selects and **B** goes back / closes; like the game's
panels, the window shows the LT / RT / View glyphs and a focus glow, and button prompts at the bottom.
Selecting a box opens a list of your spells, items, mounts and macros, so no mouse is needed; **Clear** in
that list empties the box. **Bind** closes the window and takes the next crossbar button you press (if
another window is still open, press View first). Naming a gesture needs a keyboard (the game has no
on-screen keyboard); it starts with the Tap action's name, so you only need to type for a different one.

The window closes when you enter combat (editing is locked in combat anyway).

The game's own bind screen works too: bind the Tap spell from the spellbook, the item from your bags, or
your macro from the Macros window (X).

If the game ever shows "Gesture Commands: Blizzard blocked ..." while you use the window, type
`/gestures padnav own`: the window then uses its own navigation instead (the D-pad moves a yellow
highlight, A selects, X clears a box, B closes; LT / RT don't reach it) - and please report the message.
`/gestures padnav blizzard` switches back.


## Commands

| Command | What it does |
|---|---|
| `/gestures` | Open the setup window |
| `/gestures on` / `off` | Turn it on (the default) or off. `off` returns your buttons to normal immediately |
| `/gestures test` | Check your gestures, where their Tap actions are on the crossbar, and the hold timing |
| `/gestures hold 4` / `hold2 9` | Hold / long-hold length in steps of about 0.2 s (defaults 3 and 7) |
| `/gestures minimap` | Hide or show the minimap button (drag it to move it around the minimap) |
| `/gestures padnav own` / `blizzard` | Controller navigation of the window: its own, or the game's (the default) |
| `/gestures debug` | Print where each crossbar press goes (for troubleshooting) |

## Good to know

- **Crossbar only**: it works with the gamepad crossbar (all bars and pages), not keyboard action bars.
- **One gesture per Tap**: the same spell on two slots shares the same gesture, and every rank of a
  spell counts as the same Tap.
- **Taps act on release**, so a tap has a tiny delay compared with a normal button.
- **Hold timing is approximate**: secure game code has no clock, so holds are counted in game updates of
  about 0.2 s and can arm slightly early in very busy combat.
- Gestures can only be edited out of combat; using them works in combat.
- **Coming from Totem Commands?** Open the window and press **Switch from Totem Commands**: it sets up the
  same totem gesture (Tap Call of the Elements, Hold Totemic Recall, Long hold Totemic Call) with your hold
  lengths and turns Totem Commands off. The two can't run together - they use the same buttons.

## How it works

Everything that casts runs in the game's secure environment: each crossbar button is wrapped with
Blizzard's `SecureHandlerWrapScript` and the press/release decision is made there. The addon never changes
Blizzard's settings or code, so it doesn't cause "action blocked" errors.

## License

[MIT](LICENSE)
