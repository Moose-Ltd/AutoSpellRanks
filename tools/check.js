#!/usr/bin/env node
// check.js -- parses every Lua file in AutoSpellRanks/ as Lua 5.1 (what the
// client runs). Needs luaparse: `npm i -g luaparse@0.3.1`, or a local
// node_modules; the script looks in both places.
"use strict";
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

function loadLuaparse() {
    try { return require("luaparse"); } catch (_) { /* fall through */ }
    const globalRoot = execSync("npm root -g").toString().trim();
    return require(path.join(globalRoot, "luaparse"));
}

const luaparse = loadLuaparse();
const root = path.resolve(__dirname, "..", "AutoSpellRanks");
const files = [];
(function walk(d) {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
        const p = path.join(d, e.name);
        if (e.isDirectory()) walk(p); else if (p.endsWith(".lua")) files.push(p);
    }
})(root);

let failed = 0;
for (const f of files) {
    try {
        luaparse.parse(fs.readFileSync(f, "utf8"), { luaVersion: "5.1" });
        console.log("ok  ", path.relative(root, f));
    } catch (e) {
        failed++;
        console.log("FAIL", path.relative(root, f), "-", e.message);
    }
}
if (!files.length) { console.log("no Lua files found"); process.exit(1); }
process.exit(failed ? 1 : 0);
