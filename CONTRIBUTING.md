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

## Changelog rule

Every user-visible change adds a line under `## Unreleased` in `CHANGELOG.md`,
in the same commit as the change. CI fails a pull request that touches the
addon folder without touching the changelog. Small changes get small lines;
that is fine.

## Shipping

A release is a tag. Everything after the push is automatic.

1. Rename `## Unreleased` in `CHANGELOG.md` to the new version, for example `## 1.0.1-forever`.
2. Bump `## Version` in `AutoSpellRanks/AutoSpellRanks.toc` to the same string (keep the `-forever` suffix).
3. Commit as `Version 1.0.1-forever`.
4. Tag and push: `git tag v1.0.1-forever && git push origin main --tags`.

[`release.yml`](./.github/workflows/release.yml) then checks the tag matches
the TOC, builds `AutoSpellRanks-<version>.zip`, publishes a GitHub Release with
the zip attached, and uploads the same zip to CurseForge with that changelog
section as the file notes.

Patch releases are encouraged: a one-line fix deserves its own tag rather than
waiting for a batch.

CurseForge upload needs three things, set once:

- `## X-Curse-Project-ID` in the TOC: the project id from the CurseForge project page.
- Repository secret `CF_API_KEY`: a CurseForge API token. Never commit it.
- Optional repository variables: `CF_GAME_VERSION` (for example `1.60.1`; defaults to the newest Forever version) and `CF_RELEASE_TYPE` (`alpha`, `beta` or `release`; defaults to `beta`).

Without the id or the token the workflow skips the upload and says so in the
run summary. `.\package.ps1` builds the same zip locally into `dist/`.
