"""Mock-client test for KrakenDeathCounter (lupa). Usage: python -I kdc_harness.py <addon_dir>"""
import sys, os
from lupa import LuaRuntime

ADDON = sys.argv[1]
MOCK = r'''
NOW = 0
function GetTime() return NOW end
local stub
stub = setmetatable({}, {__call=function() return stub end, __index=function() return stub end})
KrakenDeathCounter_DB, KrakenDeathCounter_Char = false, false  -- no SavedVariables yet
setmetatable(_G, {__index=function(t,k) return stub end})
CHAT = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) CHAT[#CHAT+1] = m end }
TIMERS = {}
C_Timer = { After = function(d, fn) TIMERS[#TIMERS+1] = {at=NOW+d, fn=fn} end }
function Advance(to)
  while true do
    table.sort(TIMERS, function(a,b) return a.at < b.at end)
    local n = TIMERS[1]; if not n or n.at > to then break end
    table.remove(TIMERS, 1); NOW = n.at; n.fn()
  end
  NOW = to
end
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
BackdropTemplateMixin = {}
UIParent = {}
FRAMES = {}
local function region()
  local r = { shown = true, text = "" }
  function r:SetText(t) self.text = t end
  function r:GetStringWidth() return #self.text * 10 end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:IsShown() return self.shown end
  function r:SetTextColor(r_, g, b) self.color = {r_, g, b} end
  setmetatable(r, {__index = function() return function() end end})
  return r
end
function CreateFrame(kind, name)
  local f = region()
  f.events, f.scripts, f.regions = {}, {}, {}
  function f:RegisterEvent(e) self.events[e] = true end
  function f:SetScript(n, fn) self.scripts[n] = fn end
  function f:CreateFontString() local fs = region(); self.regions[#self.regions+1] = fs; return fs end
  function f:CreateTexture() return region() end
  function f:SetPoint(...) self.point = {...} end
  function f:GetPoint() local p = self.point or {"TOP", UIParent, "TOP", 0, -120}; return p[1], p[2], p[3], p[4], p[5] end
  function f:SetScale(s) self.scale = s end
  function f:EnableMouse(v) self.mouse = v end
  FRAMES[#FRAMES+1] = f
  if name then _G[name] = f end
  return f
end
function Fire(e, ...) for _, f in ipairs(FRAMES) do if f.events[e] and f.scripts.OnEvent then f.scripts.OnEvent(f, e, ...) end end end
SlashCmdList = {}
-- statistics: category 130 = Character (unrelated), 122 = Deaths with Total deaths (60) at index 1
DEATHS = 0
STAT_READABLE = true
STATS = { [130] = { {id=328, name="Total gold acquired"} }, [122] = { {id=60, name="Total deaths"}, {id=1501, name="Deaths in Alterac Valley"} } }
function GetStatisticsCategoryList() if not STAT_READABLE then return nil end return {130, 122} end
function GetCategoryNumAchievements(c) return #(STATS[c] or {}) end
function GetStatistic(c, i)
  local s = STATS[c] and STATS[c][i]; if not s then return nil end
  local q = (s.id == 60) and (DEATHS > 0 and tostring(DEATHS) or "--") or "--"
  return q, false, s.id
end
function GetAchievementInfo(id)
  for _, list in pairs(STATS) do for _, s in ipairs(list) do if s.id == id then return id, s.name end end end
end
'''

def boot(saved_db=None, saved_char=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    if saved_db: lua.execute(saved_db)
    if saved_char: lua.execute(saved_char)
    src = open(os.path.join(ADDON, "KrakenDeathCounter.lua"), encoding="utf-8").read()
    lua.eval("function(s) return assert(load(s, '@KrakenDeathCounter.lua')) end")(src)("KrakenDeathCounter", lua.eval("{}"))
    lua.execute('Fire("ADDON_LOADED", "KrakenDeathCounter"); Fire("PLAYER_ENTERING_WORLD"); Advance(5)')
    return lua

results = []
def check(name, cond):
    results.append(bool(cond)); print(("PASS " if cond else "FAIL ") + name)

shown = lambda l: l.eval("KrakenDeathCounterFrame.regions[1].text")

lua = boot()
check("Fresh character shows Deaths: 0 (statistic '--')", shown(lua) == "Deaths: 0")
lua.execute('NOW=10; DEATHS = 1; Fire("PLAYER_DEAD"); Advance(11)')
check("After a death the server statistic shows 1", shown(lua) == "Deaths: 1")
check("Number pulses red on change", tuple(lua.eval("KrakenDeathCounterFrame.regions[1].color").values())[1] < 0.5)
lua.execute('Advance(20)')
check("Pulse returns to gold", tuple(lua.eval("KrakenDeathCounterFrame.regions[1].color").values())[1] > 0.8)
lua.execute('DEATHS = 7; Fire("CRITERIA_UPDATE")')
check("Existing server count (7) is shown, not just this session", shown(lua) == "Deaths: 7")
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("session")')
check("Session line shows this session's deaths", lua.eval("KrakenDeathCounterFrame.regions[2].text") == "This session: 1")
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("label Times I died")')
check("Custom label", shown(lua) == "Times I died: 7")
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("scale 2"); SlashCmdList.KRAKENDEATHCOUNTER("lock")')
check("Scale and lock applied", lua.eval("KrakenDeathCounterFrame.scale") == 2 and lua.eval("KrakenDeathCounterFrame.mouse") is False)
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("scale 9")')
check("Out-of-range scale rejected", lua.eval("KrakenDeathCounterFrame.scale") == 2)
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("status")')
check("/kdc status names the server statistic", any("statistic" in m and "ID 60" in m for m in lua.eval("CHAT").values()))
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("hide")')
check("/kdc hide hides it", lua.eval("KrakenDeathCounterFrame.shown") is False)

# Fallback: statistic unreadable -> last known server value + deaths counted since
lua = boot('KrakenDeathCounter_DB = {}; STAT_READABLE = false', 'KrakenDeathCounter_Char = { lastStat = 4, trackedSinceStat = 0 }')
lua.execute('Fire("CRITERIA_UPDATE")')
check("Unreadable statistic falls back to last known value", shown(lua) == "Deaths: 4")
lua.execute('NOW=50; Fire("PLAYER_DEAD"); Advance(60)')
check("Fallback counts deaths itself", shown(lua) == "Deaths: 5")
lua.execute('STAT_READABLE = true; DEATHS = 5; Fire("CRITERIA_UPDATE")')
check("Server value takes over again without double counting", shown(lua) == "Deaths: 5")

print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
