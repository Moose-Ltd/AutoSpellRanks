# Changelog

## Unreleased

- Releases publish to CurseForge automatically once the project id is set in the TOC.

## 1.0.0-forever

First release for World of Warcraft: Forever (interface 16001). A standalone version of the Spell Ranks module from [MooseMode](https://github.com/Moose-Ltd/MooseMode).

- Scans every action bar slot a few seconds after login and again whenever a spell is learned.
- A button holding a lower rank of a spell you know is swapped for the highest rank, in place.
- Never runs in combat (it waits for combat to end), never touches macros, items or empty slots, and waits if you are dragging something.
- Rank lookup asks the client by name first, then cross-checks the spellbook so a button is only ever upgraded, never downgraded.
- If the client refuses to place a spell on a bar, the addon says so once and stands down for the session.
- `/asr` shows status; `on`, `off`, `report on|off`, `scan`, `help`.
