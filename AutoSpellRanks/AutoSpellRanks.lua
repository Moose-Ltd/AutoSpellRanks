-------------------------------------------------------------------------------
-- Auto Spell Ranks
--
-- Keeps action bar spell buttons on the highest rank you know. Forever has
-- Vanilla-style spell ranks on the Retail client: learning Demon Armor rank 3
-- does not change the button that still holds rank 2. This addon swaps such
-- buttons for the new rank, out of combat.
--
-- Name-based macros ("/cast Demon Armor") already cast the top rank; this
-- covers plain spell buttons dragged from the spellbook.
--
-- Settings (AutoSpellRanksDB, account-wide):
--   enabled   swap buttons when a new rank is learned (default on)
--   report    print a line for each spell moved to a higher rank (default on)
--
-- Commands: /asr, /autospellranks
--   (none)          status
--   on | off        enable or disable
--   report on|off   chat lines for each swap
--   scan            scan and upgrade now, with a summary
--   debug           list what each button on screen holds (AutoSpellRanksDB.debug)
--   help            list commands
-------------------------------------------------------------------------------

local ADDON = ...

local PREFIX        = "|cffb04cffAuto Spell Ranks|r: "
local DEBOUNCE      = 1.0    -- seconds after SPELLS_CHANGED before scanning
local LOGIN_DELAY   = 3.0    -- seconds after PLAYER_LOGIN before the first scan
local CURSOR_RETRY  = 2.0    -- seconds to wait when the cursor is busy

local DEFAULTS = { enabled = true, report = true }

local db                     -- AutoSpellRanksDB once ADDON_LOADED has fired
local pendingCombat = false  -- scan requested during combat
local pendingForce  = false
local scanTimer                -- debounce / retry timer
local placeBroken   = false  -- PlaceAction threw once; never try again this session

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local function Print(msg)
    (DEFAULT_CHAT_FRAME or ChatFrame1):AddMessage(PREFIX .. tostring(msg))
end

-- Secret values (Midnight/Forever restriction) throw on comparison.
local function IsSecret(v)
    return issecretvalue and issecretvalue(v) or false
end

-- Event names differ between client lines; register whichever exist.
local function SafeRegister(frame, event)
    return pcall(frame.RegisterEvent, frame, event)
end

local function OnOff(b) return b and "|cff00ff00on|r" or "|cffff0000off|r" end

-------------------------------------------------------------------------------
-- Spell lookups
-------------------------------------------------------------------------------

-- The normal action bars use slots 1-180. The Gamepad UI (Alpha) keeps its
-- own layout in the slots above: 181-208 on its main page, more for the
-- LT / RT pages and form pages. Scan well past that; an empty or invalid
-- slot costs next to nothing.
local MAX_ACTION_SLOT = 1200

local function NumActionSlots()
    return MAX_ACTION_SLOT
end

local function SpellName(spellID)
    if not spellID then return nil end
    if C_Spell.GetSpellName then
        local name = C_Spell.GetSpellName(spellID)
        if name and not IsSecret(name) then return name end
    end
    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name
    if IsSecret(name) then return nil end
    return name
end

local function RankNumber(spellID)
    if not spellID then return 0 end
    if C_Spell.GetSpellSkillLineAbilityRank then
        local ok, rank = pcall(C_Spell.GetSpellSkillLineAbilityRank, spellID)
        if ok and type(rank) == "number" and not IsSecret(rank) and rank > 0 then
            return rank
        end
    end
    local sub = C_Spell.GetSpellSubtext and C_Spell.GetSpellSubtext(spellID)
    if sub and not IsSecret(sub) then
        local n = tonumber(sub:match("(%d+)"))
        if n then return n end
    end
    return 0
end

local function IsKnown(spellID)
    if not spellID then return false end
    local known
    if IsSpellKnownOrOverridesKnown then
        known = IsSpellKnownOrOverridesKnown(spellID)
    elseif IsPlayerSpell then
        known = IsPlayerSpell(spellID)
    elseif IsSpellKnown then
        known = IsSpellKnown(spellID)
    end
    if IsSecret(known) then return false end
    return known and true or false
end

-- Scans the player spellbook for every entry named `name` and returns the
-- spellID with the highest rank. Used when the by-name lookup is inconclusive.
local function HighestRankFromSpellbook(name)
    if not C_SpellBook or not C_SpellBook.GetNumSpellBookSkillLines then return nil end
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell or 1

    local bestID, bestRank = nil, -1
    local lines = C_SpellBook.GetNumSpellBookSkillLines() or 0
    for line = 1, lines do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
        if info and info.numSpellBookItems and info.itemIndexOffset then
            for i = 1, info.numSpellBookItems do
                local index = info.itemIndexOffset + i
                local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
                if item and item.itemType == spellType and item.spellID and item.name == name
                   and not item.isOffSpec then
                    local lowRank = false
                    if C_SpellBook.IsSpellBookItemLowRank then
                        local ok, low = pcall(C_SpellBook.IsSpellBookItemLowRank, index, bank)
                        lowRank = ok and low and not IsSecret(low) or false
                    end
                    local rank = RankNumber(item.spellID)
                    if not lowRank and rank >= bestRank then
                        bestID, bestRank = item.spellID, rank
                    elseif bestID == nil then
                        bestID, bestRank = item.spellID, rank
                    end
                end
            end
        end
    end
    return bestID
end

-- Returns the spellID the client would cast for "/cast <name>", i.e. the
-- highest known rank, or nil if it cannot be determined.
local function HighestRank(name, currentID)
    local best
    local info = C_Spell.GetSpellInfo(name)
    if info and info.spellID and not IsSecret(info.spellID) then
        best = info.spellID
    end
    -- The by-name lookup may hand back the same rank the button already holds
    -- (or nothing). Cross-check with the spellbook before trusting it.
    if not best or best == currentID or RankNumber(best) < RankNumber(currentID) then
        local fromBook = HighestRankFromSpellbook(name)
        if fromBook and RankNumber(fromBook) > RankNumber(best or currentID) then
            best = fromBook
        end
    end
    if best and best ~= currentID and SpellName(best) == name and IsKnown(best)
       and RankNumber(best) > RankNumber(currentID) then
        return best
    end
    return nil
end

-------------------------------------------------------------------------------
-- Swapping
-------------------------------------------------------------------------------

-- Places `spellID` into action `slot`. Returns true on success.
local function PlaceSpell(slot, spellID)
    ClearCursor()
    local okPick = pcall(C_Spell.PickupSpell, spellID)
    if not okPick then
        pcall(PickupSpell, spellID)
    end
    local kind = GetCursorInfo()
    if kind ~= "spell" then
        ClearCursor()
        return false
    end
    local ok, err = pcall(PlaceAction, slot)
    ClearCursor()
    if not ok then
        placeBroken = true
        Print("the client refused to place a spell on the bar (" .. tostring(err) .. "). Stopping for this session.")
        return false
    end
    return true
end

local function Scan(force)
    if not db then return end
    if not force and not db.enabled then return end
    if placeBroken then
        if force then Print("disabled for this session after a placement error.") end
        return
    end
    if InCombatLockdown() then
        pendingCombat = true
        pendingForce = pendingForce or force
        if force then Print("will scan after combat.") end
        return
    end
    if GetCursorInfo() then
        -- The player is dragging something; try again shortly.
        if scanTimer then scanTimer:Cancel() end
        scanTimer = C_Timer.NewTimer(CURSOR_RETRY, function() scanTimer = nil; Scan(force) end)
        return
    end

    local report = force or db.report
    local swaps = {}        -- name -> { rank = n, count = c }
    local order = {}
    local swapped, scanned = 0, 0

    for slot = 1, NumActionSlots() do
        local okInfo, actionType, id = pcall(GetActionInfo, slot)
        if okInfo and actionType == "spell" and id and not IsSecret(id) then
            scanned = scanned + 1
            local name = SpellName(id)
            if name then
                local newID = HighestRank(name, id)
                if newID then
                    if PlaceSpell(slot, newID) then
                        swapped = swapped + 1
                        local entry = swaps[name]
                        if not entry then
                            entry = { rank = RankNumber(newID), count = 0 }
                            swaps[name] = entry
                            order[#order + 1] = name
                        end
                        entry.count = entry.count + 1
                    elseif placeBroken then
                        break
                    end
                end
            end
        end
    end

    if report then
        for _, name in ipairs(order) do
            local e = swaps[name]
            local rankText = e.rank > 0 and ("Rank %d"):format(e.rank) or "highest rank"
            Print(("%s -> %s (%d button%s)"):format(name, rankText, e.count, e.count == 1 and "" or "s"))
        end
    end
    if force then
        if swapped == 0 then
            Print(("%d spell button%s checked, all on the highest rank."):format(scanned, scanned == 1 and "" or "s"))
        else
            Print(("%d button%s upgraded."):format(swapped, swapped == 1 and "" or "s"))
        end
    end
end

local function ScheduleScan(delay, force)
    if scanTimer then scanTimer:Cancel() end
    scanTimer = C_Timer.NewTimer(delay, function()
        scanTimer = nil
        Scan(force)
    end)
end

-------------------------------------------------------------------------------
-- Debug: what every button on screen holds
--
-- For finding out where a UI (the Gamepad UI, another bar addon) keeps its
-- buttons: each shown frame that carries an action slot or a spell, with
-- the spell's rank and the highest rank you know. The full list goes to
-- AutoSpellRanksDB.debug (written to disk on /reload); chat gets a summary.
-------------------------------------------------------------------------------

local function Field(f, key)
    local ok, v = pcall(function() return f[key] end)
    if ok and v ~= nil and not IsSecret(v) then return v end
end

local function Attr(f, key)
    if type(f.GetAttribute) ~= "function" then return nil end
    local ok, v = pcall(f.GetAttribute, f, key)
    if ok and v ~= nil and not IsSecret(v) then return v end
end

local function FrameName(f)
    for _, method in ipairs({ "GetDebugName", "GetName" }) do
        if type(f[method]) == "function" then
            local ok, n = pcall(f[method], f)
            if ok and type(n) == "string" and not IsSecret(n) and n ~= "" then return n end
        end
    end
    return tostring(f)
end

local function SpellText(spellID)
    local name = SpellName(spellID)
    if not name then return "spell " .. tostring(spellID) end
    local text = ("%s r%d (id %d)"):format(name, RankNumber(spellID), spellID)
    local better = HighestRank(name, spellID)
    if better then text = text .. (" OLD, r%d known"):format(RankNumber(better)) end
    return text
end

-- One line for a shown frame that carries an action slot or a spell, else nil.
local function Describe(f)
    local visible = f:IsVisible()
    if not visible or IsSecret(visible) then return nil end
    local slot = Field(f, "action") or Attr(f, "action") or Field(f, "actionID")
    if type(slot) ~= "number" then slot = nil end
    local kind = Attr(f, "type")
    local spell = (kind == "spell" and Attr(f, "spell")) or Field(f, "spellID")
    local what
    if slot then
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id and not IsSecret(id) then
            what = ("slot %d: %s"):format(slot, SpellText(id))
        else
            what = ("slot %d: %s"):format(slot, tostring(actionType or "empty"))
        end
    elseif spell then
        local id = tonumber(spell) or (C_Spell.GetSpellInfo(spell) or {}).spellID
        what = ("no slot, %s: %s"):format(kind == "spell" and "spell attribute" or "spellID field",
            id and SpellText(id) or tostring(spell))
    end
    return what and (FrameName(f) .. "  " .. what)
end

local function DebugButtons()
    local lines, old = {}, 0
    local f = EnumerateFrames()
    while f do
        local ok, line = pcall(Describe, f)
        if ok and line then
            lines[#lines + 1] = line
            if line:find(" OLD,") then old = old + 1 end
        end
        f = EnumerateFrames(f)
    end
    table.sort(lines)
    db.debug = { when = date("%Y-%m-%d %H:%M:%S"), lines = lines }
    Print(("%d buttons on screen hold an action or spell, %d of them on an old rank."):format(#lines, old))
    Print("Full list saved to AutoSpellRanksDB.debug: /reload to write it to disk.")
end

-------------------------------------------------------------------------------
-- Events
-------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
SafeRegister(frame, "ADDON_LOADED")
SafeRegister(frame, "PLAYER_LOGIN")
-- LEARNED_SPELL_IN_TAB was renamed LEARNED_SPELL_IN_SKILL_LINE in the Retail
-- line that Forever runs. Register whichever exist; SPELLS_CHANGED alone is
-- enough to catch new ranks.
SafeRegister(frame, "LEARNED_SPELL_IN_SKILL_LINE")
SafeRegister(frame, "LEARNED_SPELL_IN_TAB")
SafeRegister(frame, "SPELLS_CHANGED")
SafeRegister(frame, "PLAYER_REGEN_ENABLED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        self:UnregisterEvent("ADDON_LOADED")
        AutoSpellRanksDB = AutoSpellRanksDB or {}
        db = AutoSpellRanksDB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        return
    end
    if not db then return end
    if event == "PLAYER_LOGIN" then
        ScheduleScan(LOGIN_DELAY, false)
    elseif event == "LEARNED_SPELL_IN_SKILL_LINE" or event == "LEARNED_SPELL_IN_TAB" or event == "SPELLS_CHANGED" then
        if db.enabled then ScheduleScan(DEBOUNCE, false) end
    elseif event == "PLAYER_REGEN_ENABLED" and pendingCombat then
        pendingCombat = false
        local force = pendingForce
        pendingForce = false
        ScheduleScan(0.5, force)
    end
end)

-------------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------------

local function ShowStatus()
    Print(("upgrades %s, report swaps %s. Type /asr help for commands."):format(OnOff(db.enabled), OnOff(db.report)))
end

local function ShowHelp()
    Print("/asr on | off       enable or disable rank upgrades")
    Print("/asr report on|off  print a line for each swap")
    Print("/asr scan           scan the bars and upgrade now")
    Print("/asr debug          list what the buttons on screen hold (saved on /reload)")
end

SLASH_AUTOSPELLRANKS1 = "/asr"
SLASH_AUTOSPELLRANKS2 = "/autospellranks"
SlashCmdList.AUTOSPELLRANKS = function(msg)
    if not db then return end
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.-)$")
    cmd = (cmd or ""):lower()
    rest = (rest or ""):lower()

    if cmd == "" or cmd == "status" then
        ShowStatus()
    elseif cmd == "on" then
        db.enabled = true
        Print("upgrades " .. OnOff(true))
        ScheduleScan(0.2, false)
    elseif cmd == "off" then
        db.enabled = false
        Print("upgrades " .. OnOff(false))
    elseif cmd == "report" then
        if rest == "on" then db.report = true
        elseif rest == "off" then db.report = false
        else db.report = not db.report end
        Print("report swaps " .. OnOff(db.report))
    elseif cmd == "scan" or cmd == "ranks" then
        Scan(true)
    elseif cmd == "debug" then
        DebugButtons()
    elseif cmd == "help" then
        ShowHelp()
    else
        ShowStatus()
        ShowHelp()
    end
end
