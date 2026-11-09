# Gesture Commands

Tap, hold and long-hold gestures for anything on your gamepad crossbar in **World of Warcraft: Forever**.

A gesture attaches to something already on your crossbar: a spell, an item, or a macro that shows a spell.
When you press that button:

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
2. **New gesture**, then drag onto the three boxes:
   - **Tap (trigger)**: the spell or item that is on your crossbar (or a macro that shows a spell).
   - **Hold** and **Long hold**: whatever you want those to cast.
3. Tick **Enabled**, then **Test** to check your setup.

Shaman? The **Totems preset** sets up Call of the Elements / Totemic Recall / Totemic Call in one click.

### Custom tap actions

A macro whose first line shows a spell (`#showtooltip Lightning Bolt`) triggers that spell's gesture, and a
tap runs the macro. So for a dedicated gesture button, put a macro on your crossbar and make it the trigger.

## Commands

| Command | What it does |
|---|---|
| `/gestures` | Open the setup window |
| `/gestures on` / `off` | Turn it on or off. `off` returns your buttons to normal immediately |
| `/gestures test` | Check your gestures, where their triggers are, and the hold timing |
| `/gestures hold 4` / `hold2 9` | Hold / long-hold length in steps of about 0.2 s (defaults 3 and 7) |
| `/gestures preset totems` | Add the shaman Totems gesture |
| `/gestures debug` | Print where each crossbar press goes (for troubleshooting) |

## Good to know

- **Crossbar only**: it works with the gamepad crossbar (all bars and pages), not keyboard action bars.
- **One gesture per trigger**: the same spell on two slots shares the same gesture, and every rank of a
  spell counts as the same trigger.
- **Taps act on release**, so a tap has a tiny delay compared with a normal button.
- **Hold timing is approximate**: secure game code has no clock, so holds are counted in game updates of
  about 0.2 s and can arm slightly early in very busy combat.
- Gestures can only be edited out of combat; using them works in combat.
- If you use **Totem Commands**, turn it off (`/totemcommands off`): both work on the same buttons. The
  Totems preset here does the same job.

## How it works

Everything that casts runs in the game's secure environment: each crossbar button is wrapped with
Blizzard's `SecureHandlerWrapScript` and the press/release decision is made there. The addon never changes
Blizzard's settings or code, so it doesn't cause "action blocked" errors.

## License

[MIT](LICENSE)
