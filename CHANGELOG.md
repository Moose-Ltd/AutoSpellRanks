# Changelog

## Unreleased

- Click Casting: spells bound to mouse clicks (Click Casting window) now upgrade too. The scan only looked at action bar slots, and click bindings live in their own profile. Skipped while the Click Casting window is open; if the client refuses the update, the addon says so once and leaves click bindings alone for the session.
- Seal of Righteousness now upgrades from Rank 1. The game data holds two Rank 1 versions of it linked as if one outranked the other, which made the addon read Rank 1 as already equal to Rank 2. Ranks are now read from the rank text on the spell first.

## 1.1.0-forever

- Gamepad UI: spells on the Gamepad UI (Alpha) bars now upgrade too. Those bars use action slots above 180, which the scan never reached.
- New `/asr debug`: lists what each button on screen holds and which rank, saved to disk on `/reload`. For bug reports.
- Releases publish to CurseForge automatically once the project id is set in the TOC.

## 1.0.0-forever

First release for World of Warcraft: Forever (interface 16001). A standalone version of the Spell Ranks module from [MooseMode](https://github.com/Moose-Ltd/MooseMode).

- Scans every action bar slot a few seconds after login and again whenever a spell is learned.
- A button holding a lower rank of a spell you know is swapped for the highest rank, in place.
- Never runs in combat (it waits for combat to end), never touches macros, items or empty slots, and waits if you are dragging something.
- Rank lookup asks the client by name first, then cross-checks the spellbook so a button is only ever upgraded, never downgraded.
- If the client refuses to place a spell on a bar, the addon says so once and stands down for the session.
- `/asr` shows status; `on`, `off`, `report on|off`, `scan`, `help`.
