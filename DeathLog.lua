-- Kraken Death Counter: the death log. What killed you, where, and the last few hits.
--
-- Forever (like Midnight) gives addons no combat log, so the killer comes from two
-- places:
--   * the game's own Death Recap (C_DeathRecap, or the older DeathRecap_GetEvents),
--     which lists the hits that killed you: who, with what, for how much. It can be
--     unreadable (secret) for a moment after death, so it is retried for a while;
--   * what was attacking you when you died: hostile units (your target, focus,
--     mouseover and nameplates) that had you targeted in the last few seconds of
--     taking damage. Used, and marked "probably", when the recap isn't available.
--
-- Deaths are saved account-wide in KrakenDeathCounter_DB.log, each with the
-- character's name, so the window can show one character or all of them.

local ADDON_NAME, ns = ...

local MAX_LOG = 1000          -- oldest entries dropped past this
local HITS_KEPT = 5           -- hits shown in a death's tooltip
local ATTACKER_WINDOW = 10    -- seconds an attacker counts as "attacking you"
local RETRIES = { 0.3, 1, 2, 4, 8, 15, 30, 60 }
local ANNOUNCE_BY = 2         -- seconds: chat line with the recap if ready, else the guess

local db, char

---------------------------------------------------------------- helpers
local function plain(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return plain(a), plain(b), plain(c) end
end

local function global(name) return rawget(_G, name) end

local function num(value)
    value = plain(value)
    return type(value) == "number" and value or tonumber(value)
end

local function str(value)
    value = plain(value)
    return (type(value) == "string" and value ~= "") and value or nil
end

local function Now() return call(global("GetServerTime")) or time() end

---------------------------------------------------------------- who is attacking you
-- [name] = { name, level, class, player, seen }
local attackers = {}

local function Consider(unit, now)
    if call(UnitExists, unit) ~= true then return end
    if call(UnitCanAttack, "player", unit) ~= true then return end
    if call(UnitIsUnit, unit .. "target", "player") ~= true then return end
    local name = str(call(UnitName, unit))
    if not name then return end
    local rec = attackers[name] or {}
    rec.name, rec.seen = name, now
    rec.level = num(call(UnitLevel, unit)) or rec.level
    rec.class = str(call(UnitClassification, unit)) or rec.class
    rec.player = call(UnitIsPlayer, unit) == true
    attackers[name] = rec
end

local function Snapshot()
    local now = GetTime()
    Consider("target", now); Consider("focus", now); Consider("mouseover", now)
    local plates = global("C_NamePlate") and call(C_NamePlate.GetNamePlates)
    if type(plates) == "table" then
        for i = 1, #plates do
            local plate = plates[i]
            local unit = type(plate) == "table" and (plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit))
            if type(unit) == "string" then Consider(unit, now) end
        end
    end
end

-- Attackers seen in the last few seconds, most recent first; the target wins ties.
local function RecentAttackers()
    local list, now = {}, GetTime()
    local target = str(call(UnitName, "target"))
    for name, rec in pairs(attackers) do
        if now - rec.seen <= ATTACKER_WINDOW then list[#list + 1] = rec else attackers[name] = nil end
    end
    table.sort(list, function(a, b)
        if a.seen ~= b.seen then return a.seen > b.seen end
        return a.name == target
    end)
    return list
end

-- The last few hits as the client reported them (no source: UNIT_COMBAT doesn't say).
local recentHits = {}
local function NoteHit(action, indicator, amount, school)
    if plain(action) ~= "WOUND" then return end
    amount = num(amount)
    if not amount or amount <= 0 then return end
    table.insert(recentHits, 1, { at = GetTime(), amount = amount, crit = plain(indicator) == "CRITICAL", school = num(school) })
    while #recentHits > HITS_KEPT do table.remove(recentHits) end
end

---------------------------------------------------------------- the game's death recap
local ENV_NAMES = { FALLING = "Falling", DROWNING = "Drowning", FATIGUE = "Fatigue", FIRE = "Fire",
                    LAVA = "Lava", SLIME = "Slime" }
local PLAYER_FLAG = 0x400   -- COMBATLOG_OBJECT_TYPE_PLAYER

-- The newest "|Hdeath:ID|h" recap link in the main chat frame, if the game posted one.
local function RecapIDFromChat()
    local chat = global("ChatFrame1")
    if type(chat) ~= "table" or type(chat.GetNumMessages) ~= "function" then return nil end
    local count = num(call(chat.GetNumMessages, chat)) or 0
    for i = count, math.max(1, count - 30), -1 do
        local text = str(call(chat.GetMessageInfo, chat, i))
        local id = text and text:match("|Hdeath:(%d+)|h")
        if id then return tonumber(id) end
    end
end

local function RecapEvents(id)
    local api = global("C_DeathRecap")
    local events, maxHP
    if type(api) == "table" then
        if call(api.HasRecapEvents, id) == false then return nil end
        events = call(api.GetRecapEvents, id)
        maxHP = call(api.GetRecapMaxHealth, id)
    end
    if type(events) ~= "table" then events = call(global("DeathRecap_GetEvents"), id) end
    if type(events) ~= "table" or #events == 0 then return nil end
    return events, num(maxHP)
end

local function Describe(ev)
    if type(ev) ~= "table" then return nil end
    local kind = str(ev.event)
    local env = str(ev.environmentalType)
    local hit = {
        who = str(ev.sourceName), what = str(ev.spellName),
        amount = num(ev.amount), overkill = num(ev.overkill), at = num(ev.timestamp),
        hp = num(ev.currentHP), crit = plain(ev.critical) == true,
    }
    if hit.overkill and hit.overkill <= 0 then hit.overkill = nil end
    if env or kind == "ENVIRONMENTAL_DAMAGE" then
        hit.who, hit.env = nil, true
        hit.what = env and (ENV_NAMES[env:upper()] or env) or "The environment"
    elseif not hit.what and (kind == "SWING_DAMAGE" or kind == nil) then
        hit.what = "Melee"
    end
    local flags = num(ev.sourceFlags)
    local band = global("bit") and bit.band
    if flags and band then hit.player = band(flags, PLAYER_FLAG) ~= 0 end
    if not hit.who and not hit.env and not hit.amount then return nil end   -- all secret
    return hit
end

-- The recap of your latest death as { killer = hit, hits = {...}, maxHP, key }, or nil.
local function ReadRecap()
    local id = RecapIDFromChat()
    local events, maxHP = RecapEvents(id)
    if not events and id then events, maxHP = RecapEvents(nil) end
    if not events then return nil end
    local hits = {}
    for i = 1, #events do
        local hit = Describe(events[i])
        if hit then hit.index = i; hits[#hits + 1] = hit end
    end
    if #hits == 0 then return nil end
    -- Newest first. Timestamps decide; otherwise the game's own order (killing blow first).
    table.sort(hits, function(a, b)
        if a.at and b.at and a.at ~= b.at then return a.at > b.at end
        return a.index < b.index
    end)
    local killer = hits[1]
    if not killer.who and not killer.env then return nil end
    local key = table.concat({ tostring(id or ""), tostring(killer.at or ""), killer.who or "", killer.what or "",
                               tostring(killer.amount or "") }, "|")
    while #hits > HITS_KEPT do table.remove(hits) end
    return { killer = killer, hits = hits, maxHP = maxHP, key = key }
end

---------------------------------------------------------------- recording a death
local pending   -- the latest entry, still waiting for the recap
local announced

local function KillerText(e, colour)
    local name = e.killer or "Unknown"
    if colour then name = (e.pvp and "|cffff7fff" or "|cffff5555") .. name .. "|r" end
    local extra = {}
    if e.killerLevel then extra[#extra + 1] = e.killerLevel == -1 and "??" or tostring(e.killerLevel) end
    if e.killerClass and e.killerClass ~= "normal" and e.killerClass ~= "minus" then
        extra[#extra + 1] = (e.killerClass == "worldboss" and "boss") or (e.killerClass == "rareelite" and "rare elite") or e.killerClass
    end
    if e.pvp then extra[#extra + 1] = "player" end
    if #extra > 0 then name = name .. " (" .. table.concat(extra, " ") .. ")" end
    return name
end

local function Amounts(e)
    local s = e.amount and tostring(e.amount) or ""
    if e.overkill then s = s .. " (" .. e.overkill .. " overkill)" end
    return s
end

-- "Hogger (11 elite) with Melee 45 (12 overkill)", "Falling 230", "probably Murloc
-- Raider (11), last hit 33", "an unknown attacker".
function ns.DeathLine(e, colour)
    local amounts = Amounts(e)
    if e.env then
        return (e.killer or "The environment") .. (amounts ~= "" and (" " .. amounts) or "")
    end
    if not e.killer then
        return "an unknown attacker" .. (e.amount and (", last hit " .. e.amount) or "")
    end
    local line = KillerText(e, colour)
    if e.ability then
        line = line .. " with " .. e.ability .. (amounts ~= "" and (" " .. amounts) or "")
    elseif e.amount then
        line = line .. ", last hit " .. amounts
    end
    if e.from == "guess" and (e.killer or e.env) then line = "probably " .. line end
    return line
end

local function Announce(e, update)
    if not db.announce then return end
    local where = e.sub and e.sub ~= e.zone and (e.sub .. ", " .. (e.zone or "")) or e.zone
    local line = ns.DeathLine(e, true)
    local lead = "Killed by "
    if line:sub(1, 9) == "probably " then lead, line = "Probably killed by ", line:sub(10) end
    ns.say((update and "Death recap: " or "") .. lead .. line
        .. (where and where ~= "" and (" in " .. where) or "") .. ". |cff888888/kdc log|r")
end

local function ApplyRecap(e, recap)
    local k = recap.killer
    e.from = "recap"
    e.env = k.env or nil
    e.killer = k.env and k.what or k.who
    e.ability = (not k.env) and k.what or nil
    e.amount, e.overkill = k.amount, k.overkill
    e.pvp = k.player or nil
    e.maxHP = recap.maxHP
    e.hits = {}
    for i, h in ipairs(recap.hits) do
        e.hits[i] = { who = h.who, what = h.what, amount = h.amount, crit = h.crit or nil, hp = h.hp,
                      ago = (k.at and h.at) and (k.at - h.at) or nil }
    end
    -- Level and rank, when the killer was also seen attacking you.
    e.killerLevel, e.killerClass = nil, nil
    for _, a in ipairs(e.attackers or {}) do
        if a.name == e.killer then e.killerLevel, e.killerClass = a.level, a.class end
    end
    char.lastRecapKey = recap.key
end

local function TryRecap(final)
    local e = pending
    if not e then return end
    local recap = ReadRecap()
    if recap and recap.key ~= char.lastRecapKey then
        ApplyRecap(e, recap)
        pending = nil
        Announce(e, announced)
        announced = true
        ns.RefreshLog()
        return
    end
    if final and not announced then Announce(e); announced = true end
end

function ns.OnDeath()
    if not db then return end
    Snapshot()
    local seen = RecentAttackers()
    local e = {
        t = Now(), who = str(call(UnitName, "player")) or "?",
        zone = str(call(GetRealZoneText)) or str(call(GetZoneText)),
        sub = str(call(GetSubZoneText)),
        level = num(call(UnitLevel, "player")),
        from = "guess", attackers = {},
    }
    for i, a in ipairs(seen) do
        if i > 4 then break end
        e.attackers[i] = { name = a.name, level = a.level, class = a.class, player = a.player or nil }
    end
    local top = e.attackers[1]
    if top then
        e.killer, e.killerLevel, e.killerClass, e.pvp = top.name, top.level, top.class, top.player
    end
    if recentHits[1] and GetTime() - recentHits[1].at <= ATTACKER_WINDOW then
        e.amount = recentHits[1].amount
        e.hits = {}
        for i, h in ipairs(recentHits) do
            e.hits[i] = { amount = h.amount, crit = h.crit or nil, ago = recentHits[1].at - h.at }
        end
    end
    wipe(recentHits)
    local log = db.log
    log[#log + 1] = e
    while #log > MAX_LOG do table.remove(log, 1) end
    pending, announced = e, false
    for _, delay in ipairs(RETRIES) do
        C_Timer.After(delay, function() if pending == e then TryRecap(delay >= ANNOUNCE_BY) end end)
    end
    ns.RefreshLog()
end

---------------------------------------------------------------- the log window
local win, rows, showAll
local ROW_H = 18

local function Entries()
    local list, me = {}, str(call(UnitName, "player"))
    for i = #db.log, 1, -1 do
        local e = db.log[i]
        if showAll or e.who == me then list[#list + 1] = e end
    end
    return list
end

local function TopKillers(list)
    local tally, order = {}, {}
    for _, e in ipairs(list) do
        if e.killer then
            local k = e.killer
            if not tally[k] then tally[k] = 0; order[#order + 1] = k end
            tally[k] = tally[k] + 1
        end
    end
    table.sort(order, function(a, b) return tally[a] > tally[b] end)
    local out = {}
    for i = 1, math.min(3, #order) do out[i] = order[i] .. " x" .. tally[order[i]] end
    return table.concat(out, ", ")
end

local function When(t) return type(date) == "function" and date("%b %d %H:%M", t) or tostring(t) end

local function RowTooltip(row)
    local e = row.entry
    if not e then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.DeathLine(e, true), 1, 1, 1, true)
    GameTooltip:AddLine(When(e.t) .. (showAll and ("  " .. (e.who or "?")) or ""), 0.7, 0.7, 0.7)
    local where = e.zone or "Unknown"
    if e.sub and e.sub ~= "" and e.sub ~= e.zone then where = e.sub .. ", " .. where end
    if e.coords then where = where .. " (" .. e.coords .. ")" end
    GameTooltip:AddLine(where .. (e.level and ("  (you were level " .. e.level .. ")") or ""), 0.7, 0.7, 0.7)
    if e.hits and #e.hits > 0 then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Last hits, newest first:", 1, 0.82, 0)
        for _, h in ipairs(e.hits) do
            local s = (h.ago and h.ago > 0) and (("-%.1fs  "):format(h.ago)) or "            "
            if h.who then s = s .. h.who .. ": " end
            s = s .. (h.what or "hit") .. (h.amount and (" " .. h.amount) or "") .. (h.crit and " (crit)" or "")
            if h.hp and e.maxHP and e.maxHP > 0 then s = s .. ("  |cff888888%d%% health left|r"):format(math.floor(h.hp / e.maxHP * 100 + 0.5)) end
            GameTooltip:AddLine(s, 1, 1, 1)
        end
    end
    if e.fight and #e.fight > 0 then
        GameTooltip:AddLine("In the fight: " .. table.concat(e.fight, ", "), 0.8, 0.8, 0.8, true)
    end
    if e.imported then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("From Kraken Log's record of the fight, before the death log existed: the last enemy you targeted or attacked before you died.", 0.6, 0.6, 0.6, true)
    elseif e.from == "guess" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("The game's death recap wasn't available, so this is what was attacking you when you died.", 0.6, 0.6, 0.6, true)
        if e.attackers and #e.attackers > 1 then
            local names = {}
            for i, a in ipairs(e.attackers) do names[i] = a.name end
            GameTooltip:AddLine("Attacking you: " .. table.concat(names, ", "), 0.6, 0.6, 0.6, true)
        end
    end
    GameTooltip:Show()
end

local function BuildWindow()
    win = CreateFrame("Frame", "KrakenDeathLogFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    win:SetSize(560, 400)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.SetBackdrop then
        win:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        win:SetBackdropColor(0, 0, 0, 0.9)
        win:SetBackdropBorderColor(0.6, 0.1, 0.1, 0.9)
    end
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "KrakenDeathLogFrame") end

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", 12, -10)
    win.title:SetText("What killed me")

    win.summary = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.summary:SetPoint("TOPLEFT", 12, -32)
    win.summary:SetPoint("RIGHT", -12, 0)
    win.summary:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    win.toggle = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.toggle:SetSize(130, 20)
    win.toggle:SetPoint("TOPRIGHT", -30, -8)
    win.toggle:SetScript("OnClick", function() showAll = not showAll; ns.RefreshLog() end)

    win.scroll = CreateFrame("ScrollFrame", "KrakenDeathLogScroll", win, "UIPanelScrollFrameTemplate")
    win.scroll:SetPoint("TOPLEFT", 10, -52)
    win.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
    win.content = CreateFrame("Frame", nil, win.scroll)
    win.content:SetSize(510, 10)
    win.scroll:SetScrollChild(win.content)

    win.empty = win.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    win.empty:SetPoint("TOPLEFT", 4, -4)
    win.empty:SetText("No deaths logged yet. Deaths are recorded from now on.")

    rows = {}
    win:Hide()
end

local function Row(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, win.content)
    row:SetSize(510, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    row.when = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.when:SetPoint("LEFT", 4, 0)
    row.when:SetWidth(84)
    row.when:SetJustifyH("LEFT")
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 90, 0)
    row.text:SetPoint("RIGHT", -4, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row:SetScript("OnEnter", RowTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    rows[i] = row
    return row
end

function ns.RefreshLog()
    if not win or not win:IsShown() then return end
    local list = Entries()
    local me = str(call(UnitName, "player")) or "this character"
    win.toggle:SetText(showAll and "All characters" or me)
    local top = TopKillers(list)
    win.summary:SetText(("%d death%s logged%s."):format(#list, #list == 1 and "" or "s",
        top ~= "" and (". Most often: " .. top) or ""))
    win.empty:SetShown(#list == 0)
    for i, e in ipairs(list) do
        local row = Row(i)
        row.entry = e
        row.when:SetText(When(e.t))
        local where = e.sub and e.sub ~= "" and e.sub or e.zone or ""
        local text = ns.DeathLine(e, true)
        if showAll then text = "|cffaaaaaa" .. (e.who or "?") .. ":|r " .. text end
        if e.level then text = text .. "  |cff888888lvl " .. e.level .. "|r" end
        if where ~= "" then text = text .. "  |cff888888" .. where .. "|r" end
        row.text:SetText(text)
        row:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide(); rows[i].entry = nil end
    win.content:SetHeight(math.max(10, #list * ROW_H))
end

function ns.ToggleLog()
    if not win then BuildWindow() end
    if win:IsShown() then win:Hide() else win:Show(); ns.RefreshLog() end
end

function ns.LastDeath()
    local me = str(call(UnitName, "player"))
    for i = #db.log, 1, -1 do
        if db.log[i].who == me then return db.log[i] end
    end
end

function ns.ClearLog()
    local me, kept, removed = str(call(UnitName, "player")), {}, 0
    for _, e in ipairs(db.log) do
        if e.who == me then removed = removed + 1 else kept[#kept + 1] = e end
    end
    db.log = kept
    ns.RefreshLog()
    return removed
end

---------------------------------------------------------------- earlier deaths, from Kraken Log
-- Kraken Log (if installed) writes lines like
--   "2026-11-08 14:28:05 | Elwynn Forest 76.4,87.0 | DIED | "
--   "2026-11-08 14:28:05 | Elwynn Forest 76.4,87.0 | CAST | 355 Taunt on Murloc Forager, id 46, lvl 10, hostile"
-- Deaths it recorded that the death log doesn't have yet are added, with the last
-- enemy you targeted or attacked in the half minute before (not one that had died).
local FIGHT_WINDOW = 30

local function ParseLine(line)
    if type(line) ~= "string" then return nil end
    local Y, M, D, h, m, s, where, kind, text = line:match("^(%d+)%-(%d+)%-(%d+) (%d+):(%d+):(%d+) | (.-) | ([%u_]+) | ?(.*)$")
    if not Y then return nil end
    local t = time({ year = tonumber(Y), month = tonumber(M), day = tonumber(D), hour = tonumber(h), min = tonumber(m), sec = tonumber(s) })
    return t, where, kind, text
end

-- "Murloc Forager, id 46, lvl 10, hostile" -> name, level (enemies only)
local function Enemy(unitText)
    if type(unitText) ~= "string" then return nil end
    if not (unitText:find(", hostile$") or unitText:find(", neutral$")) then return nil end
    local name = unitText:match("^(.-),")
    if not name or name == "" or name == "?" then return nil end
    return name, tonumber(unitText:match("lvl (%-?%d+)"))
end

local function SplitWhere(where)
    local place, x, y = where:match("^(.-) (%d+%.%d),(%d+%.%d)$")
    place = place or where
    local zone, sub = place:match("^(.-)/(.+)$")
    zone = zone or place
    if zone == "?" then zone = nil end
    return zone, sub, x and (x .. ", " .. y) or nil
end

function ns.ImportKrakenLog()
    local klog = global("KrakenLog_DB")
    local me = str(call(UnitName, "player"))
    if type(klog) ~= "table" or not me then return 0 end
    local lines = klog[(str(call(GetRealmName)) or "?") .. " - " .. me]
    if type(lines) ~= "table" then return 0 end

    local have = {}
    for _, e in ipairs(db.log) do if e.who == me and e.t then have[#have + 1] = e.t end end
    local function Known(t)
        for _, t2 in ipairs(have) do if math.abs(t2 - t) <= 60 then return true end end
    end

    local recent, level, lastDied, found = {}, nil, nil, 0
    for _, line in ipairs(lines) do
        local t, where, kind, text = ParseLine(line)
        if t then
            if kind == "LOGIN" then
                level = tonumber(text:match("level (%d+)")) or level
            elseif kind == "LEVEL_UP" then
                level = tonumber(text:match("(%d+)")) or level
            elseif kind == "TARGET" or kind == "CAST" then
                local name, lvl = Enemy(kind == "CAST" and text:match(" on (.+)$") or text)
                if name then recent[#recent + 1] = { t = t, name = name, level = lvl } end
            elseif kind == "XP" then
                local dead = text:match("^(.-) dies")
                if dead then recent[#recent + 1] = { t = t, name = dead, died = true } end
            elseif kind == "DIED" and not (lastDied and t - lastDied <= 5) then
                lastDied = t
                if not Known(t) then
                    local zone, sub, coords = SplitWhere(where)
                    local e = { t = t, who = me, zone = zone, sub = sub, coords = coords, level = level,
                                from = "guess", imported = true, attackers = {}, fight = {} }
                    local killed, seen = {}, {}
                    for i = #recent, 1, -1 do
                        local r = recent[i]
                        if t - r.t > FIGHT_WINDOW then break end
                        if r.died then
                            killed[r.name] = true
                        elseif not seen[r.name] then
                            seen[r.name] = true
                            -- An enemy that died before you didn't kill you.
                            if not killed[r.name] and #e.attackers < 4 then
                                e.attackers[#e.attackers + 1] = { name = r.name, level = r.level }
                            end
                            e.fight[#e.fight + 1] = r.name .. (killed[r.name] and " (you killed it)" or "")
                        end
                    end
                    for name in pairs(killed) do
                        if not seen[name] then e.fight[#e.fight + 1] = name .. " (you killed it)" end
                    end
                    local top = e.attackers[1]
                    if top then e.killer, e.killerLevel = top.name, top.level end
                    db.log[#db.log + 1] = e
                    have[#have + 1] = t
                    found = found + 1
                end
            end
            -- keep only the last half minute of fight lines
            while recent[1] and t - recent[1].t > FIGHT_WINDOW do table.remove(recent, 1) end
        end
    end
    if found > 0 then
        table.sort(db.log, function(a, b) return (a.t or 0) < (b.t or 0) end)
        while #db.log > MAX_LOG do table.remove(db.log, 1) end
        ns.RefreshLog()
    end
    return found
end

---------------------------------------------------------------- setup
function ns.InitLog(accountDB, charDB)
    db, char = accountDB, charDB
    if type(db.log) ~= "table" then db.log = {} end
    if db.announce == nil then db.announce = true end
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_COMBAT")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_ALIVE")
    f:RegisterEvent("PLAYER_UNGHOST")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(_, event, unit, action, indicator, amount, school)
        if event == "PLAYER_LOGIN" then
            -- Kraken Log's saved data is loaded by now. Once per character, so a
            -- /kdc clearlog stays cleared; /kdc import runs it again.
            if not char.klogImported then
                local n = ns.ImportKrakenLog()
                if global("KrakenLog_DB") then char.klogImported = true end
                if n > 0 then
                    ns.say(("Added %d earlier death%s from Kraken Log's records. |cff888888/kdc log|r"):format(n, n == 1 and "" or "s"))
                end
            end
        elseif event == "UNIT_COMBAT" then
            if unit == "player" then NoteHit(action, indicator, amount, school); Snapshot() end
        elseif pending then
            TryRecap(false)
        end
    end)
end
