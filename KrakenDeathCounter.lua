-- Kraken Death Counter: a movable on-screen death counter for streaming.
--
-- The number comes from the server's own "Total deaths" statistic (the same value the
-- Statistics window shows). Forever's Statistics window reads rows with
-- GetStatistic(categoryID, index) -> quantity, skip, statID and names them with
-- GetAchievementInfo(statID); this addon finds the "Total deaths" row the same way.
-- If the statistic can't be read, it falls back to counting PLAYER_DEAD itself.

local ADDON_NAME = ...
local TITLE = "Kraken Death Counter"
local TOTAL_DEATHS_NAMES = { ["Total deaths"] = true }
local TOTAL_DEATHS_RETAIL_ID = 60   -- the long-standing statistic ID, checked by name before use

local DEFAULTS = {
    shown = true,
    locked = false,
    scale = 1.0,
    label = "Deaths",
    showSession = false,
    showIcon = true,
    background = true,
    point = { "TOP", "UIParent", "TOP", 0, -120 },
}

local db, char
local statCategory, statIndex, statID     -- where "Total deaths" lives once found
local sessionDeaths = 0
local lastShown

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff5555" .. TITLE .. "|r: " .. msg)
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

local function plain(value)
    if type(issecretvalue) == "function" and issecretvalue(value) then return nil end
    return value
end

---------------------------------------------------------------- statistic lookup
local function StatName(id)
    local _, name = safe(GetAchievementInfo, id)
    return plain(name)
end

local function FindTotalDeaths()
    local categories = safe(GetStatisticsCategoryList)
    if type(categories) ~= "table" then return false end
    for _, categoryID in ipairs(categories) do
        local count = tonumber(plain((safe(GetCategoryNumAchievements, categoryID)))) or 0
        for i = 1, count do
            local _, skip, id = safe(GetStatistic, categoryID, i)
            id = plain(id)
            if id and not plain(skip) then
                local name = StatName(id)
                if (name and TOTAL_DEATHS_NAMES[name]) or (id == TOTAL_DEATHS_RETAIL_ID and name) then
                    statCategory, statIndex, statID = categoryID, i, id
                    return true
                end
            end
        end
    end
    return false
end

-- nil when the statistic can't be read; otherwise a number (the window's "--" is 0)
local function ReadTotalDeaths()
    if not statCategory and not FindTotalDeaths() then return nil end
    local quantity, _, id = safe(GetStatistic, statCategory, statIndex)
    if plain(id) ~= statID then
        statCategory, statIndex, statID = nil, nil, nil       -- list changed; look again
        if not FindTotalDeaths() then return nil end
        quantity = safe(GetStatistic, statCategory, statIndex)
    end
    quantity = plain(quantity)
    if quantity == nil then return nil end
    local value = tonumber((tostring(quantity):gsub("[^%d]", "")))
    return value or 0
end

---------------------------------------------------------------- overlay
local frame = CreateFrame("Frame", "KrakenDeathCounterFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
frame:SetSize(180, 44)
frame:SetFrameStrata("MEDIUM")
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetSize(30, 30)
icon:SetPoint("LEFT", 8, 0)
icon:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")

local text = frame:CreateFontString(nil, "OVERLAY")
text:SetFont(STANDARD_TEXT_FONT, 24, "OUTLINE")
text:SetTextColor(1, 0.82, 0)
text:SetJustifyH("LEFT")

local sub = frame:CreateFontString(nil, "OVERLAY")
sub:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
sub:SetTextColor(0.85, 0.85, 0.85)
sub:SetJustifyH("LEFT")

local function ApplyBackground()
    if db.background and frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.6)
        frame:SetBackdropBorderColor(0.6, 0.1, 0.1, 0.9)
    elseif frame.SetBackdrop then
        frame:SetBackdrop(nil)
    end
end

local function Layout()
    text:ClearAllPoints()
    sub:ClearAllPoints()
    local left = 10
    if db.showIcon then icon:Show(); left = 44 else icon:Hide() end
    if db.showSession then
        text:SetPoint("TOPLEFT", left, -6)
        sub:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -1)
        sub:Show()
    else
        text:SetPoint("LEFT", left, 0)
        sub:Hide()
    end
    local width = left + math.max(text:GetStringWidth() or 0, db.showSession and (sub:GetStringWidth() or 0) or 0) + 14
    frame:SetSize(math.max(width, 90), db.showSession and 52 or 44)
end

local function Count()
    local total = ReadTotalDeaths()
    if total then
        char.lastStat = total
        char.trackedSinceStat = 0
        return total, true
    end
    -- Statistic unreadable: last known server value plus deaths seen since.
    return (char.lastStat or 0) + (char.trackedSinceStat or 0), false
end

local function Refresh()
    if not db then return end
    local total = Count()
    text:SetText(db.label .. ": " .. total)
    sub:SetText("This session: " .. sessionDeaths)
    if lastShown and total > lastShown then
        -- A brief red pulse so viewers notice the number change.
        text:SetTextColor(1, 0.2, 0.2)
        C_Timer.After(2, function() text:SetTextColor(1, 0.82, 0) end)
    end
    lastShown = total
    Layout()
end

local function SavePosition()
    local point, _, relPoint, x, y = frame:GetPoint(1)
    db.point = { point, "UIParent", relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
end

local function ApplySettings()
    frame:ClearAllPoints()
    local p = db.point
    frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    frame:SetScale(db.scale)
    frame:EnableMouse(not db.locked)
    ApplyBackground()
    if db.shown then frame:Show() else frame:Hide() end
    Refresh()
end

frame:SetScript("OnDragStart", function(self) if not db.locked then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); SavePosition() end)
frame:SetScript("OnEnter", function(self)
    if db.locked then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine(TITLE)
    GameTooltip:AddLine("Drag to move. /kdc lock to lock it in place.", 1, 1, 1, true)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------- events
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_DEAD")
events:RegisterEvent("CRITERIA_UPDATE")
events:RegisterEvent("RECEIVED_ACHIEVEMENT_LIST")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        KrakenDeathCounter_DB = KrakenDeathCounter_DB or {}
        KrakenDeathCounter_Char = KrakenDeathCounter_Char or {}
        db, char = KrakenDeathCounter_DB, KrakenDeathCounter_Char
        for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
        ApplySettings()
    elseif event == "PLAYER_DEAD" then
        sessionDeaths = sessionDeaths + 1
        char.trackedSinceStat = (char.trackedSinceStat or 0) + 1
        Refresh()
        -- The server statistic updates a moment after the death.
        C_Timer.After(1, Refresh)
        C_Timer.After(5, Refresh)
    elseif db then
        Refresh()
        if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(3, Refresh) end
    end
end)

---------------------------------------------------------------- /kdc
local HELP = {
    "/kdc show | hide - show or hide the counter",
    "/kdc lock | unlock - lock it in place (unlocked: drag to move)",
    "/kdc scale 1.5 - size (0.5 to 4)",
    "/kdc label Deaths - change the word before the number",
    "/kdc session - toggle the 'This session' line",
    "/kdc icon - toggle the skull icon",
    "/kdc bg - toggle the background box",
    "/kdc reset - move it back to the top of the screen",
    "/kdc status - show where the number comes from",
}

SLASH_KRAKENDEATHCOUNTER1 = "/kdc"
SLASH_KRAKENDEATHCOUNTER2 = "/deaths"
SlashCmdList.KRAKENDEATHCOUNTER = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "show" then db.shown = true
    elseif cmd == "hide" then db.shown = false
    elseif cmd == "lock" then db.locked = true; say("Locked.")
    elseif cmd == "unlock" then db.locked = false; say("Unlocked - drag it where you want it.")
    elseif cmd == "scale" then
        local s = tonumber(rest)
        if not s or s < 0.5 or s > 4 then say("Scale must be between 0.5 and 4."); return end
        db.scale = s
    elseif cmd == "label" then
        db.label = rest ~= "" and rest or DEFAULTS.label
    elseif cmd == "session" then db.showSession = not db.showSession
    elseif cmd == "icon" then db.showIcon = not db.showIcon
    elseif cmd == "bg" then db.background = not db.background
    elseif cmd == "reset" then db.point = { unpack(DEFAULTS.point) }
    elseif cmd == "status" then
        local total, fromServer = Count()
        if fromServer then
            say(("%d deaths, from the server's \"%s\" statistic (ID %s)."):format(total, StatName(statID) or "Total deaths", tostring(statID)))
        else
            say(("%d deaths, counted by the addon (the \"Total deaths\" statistic isn't readable right now)."):format(total))
        end
        say(("This session: %d. Locked: %s. Scale: %s."):format(sessionDeaths, tostring(db.locked), tostring(db.scale)))
        return
    else
        for _, line in ipairs(HELP) do say(line) end
        return
    end
    ApplySettings()
end
