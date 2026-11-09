# Gesture Commands

Tap, hold and long-hold gestures for anything on your gamepad crossbar in **World of Warcraft: Forever**.

A gesture is like a macro for your gamepad: it has a **name and icon** (edited just like a macro's), a **Tap**
action, and **Hold** / **Long hold** actions. Place it on your crossbar, and when you press that button:

| You do | You feel / see | On release |
|---|---|---|
| **Tap** | nothing | the slot does what it normally does |
| **Hold** (~0.5 s) | a rumble, "Release for …" | casts your **Hold** action |
| **Keep holding** (~1.4 s) | a double rumble, "Release for …" | casts your **Long hold** action |

Hold actions can be **spells, items, toys, mounts or macros**. Nothing is cast until you let go, so you can
hold past a stage you don't want, and a stage you leave empty is simply skipped. The slot keeps its own
icon and cooldown, and every other button works exactly as before.

## Setup

1. Type `/gestures` (or Options > AddOns > Gesture Commands).
2. **New gesture**, then fill the three boxes - click a box to choose from your spells, items, mounts and
   macros, or drag something onto it:
   - **Tap**: a spell or item (or a macro that shows a spell). A tap casts it.
   - **Hold** and **Long hold**: whatever you want those to cast.
3. **Name & icon** (or click the gesture's icon): pick a name and an icon, just like for a macro.
4. **Bind**: with a controller, the window closes - press the crossbar button you want the gesture on (L1 / R1
   for the other bars, both shoulders + D-pad left / right for another page; nothing is cast by that press).
   A banner shows what you're binding and the time left (60 s); open `/gestures` to cancel. In combat your
   buttons work normally and the bind waits for a press after the fight. With a mouse, Bind (or dragging the gesture from the
   list) puts it on your cursor to drop on a crossbar slot.
5. Press **Test** to check your setup. Gesture Commands is on by default; untick **Enabled** to switch it off.

Each gesture is stored as one of your **character macros** (with your name and icon, casting the Tap
action), so it shows up in the Macros window too. Deleting the gesture deletes its macro. A slot that
holds the Tap spell or item directly also works as the gesture.

### With a controller

The window works with the game's controller navigation like Blizzard's own windows: **LT / RT** switch
between it and other open windows (bags, spellbook...), the **View** button switches between the game and
the windows, the D-pad moves between buttons, **A** selects and **B** goes back / closes; like the game's
panels, the window shows the LT / RT / View glyphs and a focus glow, and button prompts at the bottom.
Selecting a box opens a list of your spells, items, mounts and macros, so no mouse is needed; **Clear** in
that list empties the box. **Bind** closes the window and takes the next crossbar button you press (if
another window is still open, press View first). Naming a gesture needs a keyboard (the game has no on-screen keyboard); it starts with the Tap
spell's name, so you only need to type if you want a different one.

The window closes when you enter combat (editing is locked in combat anyway).

The game's own bind screen can't be opened by an addon for a gesture (only its spellbook, bags and Macros
windows can open it). Each gesture is a character macro, though, so Esc > Macros > Character tab > X (Bind)
works too.

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
- Each gesture uses one character macro slot (30 per character).
- If you use **Totem Commands**, turn it off (`/totemcommands off`): both work on the same buttons.

## How it works

Everything that casts runs in the game's secure environment: each crossbar button is wrapped with
Blizzard's `SecureHandlerWrapScript` and the press/release decision is made there. The addon never changes
Blizzard's settings or code, so it doesn't cause "action blocked" errors.

## License

[MIT](LICENSE)
