# Contributing

Short version of how this addon is built, checked and shipped. The
[README](./README.md) explains how it works.

## Local setup

```powershell
git clone https://github.com/Moose-Ltd/AutoSpellRanks.git
cd AutoSpellRanks
.\install.ps1          # junction AutoSpellRanks/ into the beta AddOns folder (-Path for another install)
```

Edit, then `/reload` in game. Turn on Lua errors while developing:

```
/console scriptErrors 1
```

## Syntax check

The client runs Lua 5.1. Parse before committing:

```bash
npm i -g luaparse@0.3.1
node tools/check.js
```

[`ci.yml`](./.github/workflows/ci.yml) runs the same check on every push.

## Conventions

- One file, local functions only. The only globals are `AutoSpellRanksDB` and the slash handlers.
- Forever is the Retail 12.x client. Use `C_*` namespaces where they exist; guard every call for existence and pass values through `IsSecret` before comparing.
- Never call protected functions. Placing a spell with `PlaceAction` out of combat is allowed; if the client ever protects it, the addon must stand down, not retry.
- Chat text stays short and plain: no em dashes, no first-person plural, no filler.
- One feature or fix per commit, with a message that says what changed and why.

## Reporting a bug

Open an issue with the bug template and include:

- Client build (`/run print(GetBuildInfo())`) and class.
- The spell and rank on the button, and the rank you know.
- What `/asr scan` prints.
- Any red Lua error text (`/console scriptErrors 1`).

## Shipping

1. Bump `## Version` in `AutoSpellRanks/AutoSpellRanks.toc` (keep the `-forever` suffix).
2. Add the release to `CHANGELOG.md`.
3. Commit, then tag and push: `git tag v1.0.1-forever && git push origin main --tags`.
4. [`release.yml`](./.github/workflows/release.yml) checks the tag matches the TOC, builds `AutoSpellRanks-<version>.zip` and attaches it to a GitHub Release.
5. Upload that zip to CurseForge under the Forever flavour, game version 1.60.1.

`.\package.ps1` builds the same zip locally into `dist/`.
