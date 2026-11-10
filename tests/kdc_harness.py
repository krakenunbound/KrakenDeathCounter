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
time = os.time
date = os.date
function GetServerTime() return 1800000000 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
bit = { band = function(a, b) return a & b end }
SECRET = setmetatable({}, {__name = "secret"})
function issecretvalue(v) return v == SECRET end
ME = "Selene"
function GetRealZoneText() return "Elwynn Forest" end
function GetSubZoneText() return "Fargodeep Mine" end
UNITS = {}   -- [token] = {name, level, class, hostile, targetingMe, player}
function UnitName(u) if u == "player" then return ME end local x = UNITS[u]; return x and x.name end
function UnitLevel(u) if u == "player" then return 12 end local x = UNITS[u]; return x and x.level end
function UnitExists(u) return u == "player" or UNITS[u] ~= nil end
function UnitCanAttack(a, u) local x = UNITS[u]; return x ~= nil and x.hostile == true end
function UnitIsUnit(a, b)
  local base = a:match("^(.-)target$")
  if base and base ~= "" and b == "player" then local x = UNITS[base]; return x ~= nil and x.targetingMe == true end
  return a == b
end
function UnitClassification(u) local x = UNITS[u]; return x and x.class or "normal" end
function UnitIsPlayer(u) local x = UNITS[u]; return x ~= nil and x.player == true end
-- the death recap: RECAP = events, newest first; nil = unavailable
RECAP = nil
C_DeathRecap = {
  HasRecapEvents = function() return RECAP ~= nil end,
  GetRecapEvents = function() return RECAP end,
  GetRecapMaxHealth = function() return 500 end,
}
function ChatText() return table.concat(CHAT, "\n") end
function AllTexts()
  local out = {}
  for _, f in ipairs(FRAMES) do
    if f.shown then for _, r in ipairs(f.regions) do if r.shown then out[#out+1] = r.text end end end
  end
  return table.concat(out, "\n")
end
'''

def boot(saved_db=None, saved_char=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    if saved_db: lua.execute(saved_db)
    if saved_char: lua.execute(saved_char)
    ns = lua.eval("{}")
    for fn in ("KrakenDeathCounter.lua", "DeathLog.lua"):
        src = open(os.path.join(ADDON, fn), encoding="utf-8").read()
        lua.eval("function(s, n) return assert(load(s, '@' .. n)) end")(src, fn)("KrakenDeathCounter", ns)
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

# ---------------------------------------------------------------- what killed me
log_n = lambda l: l.eval("#KrakenDeathCounter_DB.log")
last = lambda l, k: l.eval("KrakenDeathCounter_DB.log[#KrakenDeathCounter_DB.log]." + k)
chat = lambda l: l.eval("ChatText()")

lua = boot()
lua.execute("""
RECAP = {
  { event="SWING_DAMAGE", sourceName="Hogger", amount=45, overkill=12, timestamp=100.5, currentHP=0, sourceFlags=0xa48 },
  { event="SPELL_DAMAGE", sourceName="Hogger", spellName="Vicious Slice", amount=80, overkill=-1, timestamp=99.0, currentHP=45, critical=true },
}
NOW = 100; Fire("PLAYER_DEAD"); Advance(103)
""")
check("Recap death is logged", log_n(lua) == 1)
check("Killer comes from the recap", last(lua, "killer") == "Hogger" and last(lua, "from") == "recap")
check("Killing blow: Melee 45, 12 overkill", last(lua, "ability") == "Melee" and last(lua, "amount") == 45 and last(lua, "overkill") == 12)
check("Overkill -1 on an earlier hit is dropped", lua.eval("KrakenDeathCounter_DB.log[1].hits[2].overkill") is None)
check("Earlier hit timed relative to the killing blow", abs(lua.eval("KrakenDeathCounter_DB.log[1].hits[2].ago") - 1.5) < 1e-6)
check("Zone, subzone, character and level recorded",
      last(lua, "zone") == "Elwynn Forest" and last(lua, "sub") == "Fargodeep Mine" and last(lua, "who") == "Selene" and last(lua, "level") == 12)
check("Chat line names killer and blow", "Killed by" in chat(lua) and "Hogger" in chat(lua) and "Melee 45" in chat(lua))
check("NPC killer not flagged as a player", last(lua, "pvp") is None)

lua.execute('CHAT = {}; NOW = 200; Fire("PLAYER_DEAD"); Advance(300)')
check("Previous death's recap is not reused", log_n(lua) == 2 and last(lua, "from") == "guess")
check("A death with no recap is still announced", "Killed by" in chat(lua))

lua.execute("""CHAT = {}; RECAP = { { event="ENVIRONMENTAL_DAMAGE", environmentalType="FALLING", amount=230, overkill=50, timestamp=400 } }
NOW = 400; Fire("PLAYER_DEAD"); Advance(410)""")
check("Falling death is named Falling", last(lua, "killer") == "Falling" and last(lua, "env") is True and last(lua, "ability") is None)
check("Falling chat line", "Killed by Falling 230" in chat(lua))

lua.execute("""CHAT = {}; RECAP = { { event="SPELL_DAMAGE", sourceName="Grim Reaper", spellName="Shadow Bolt", amount=300, timestamp=500, sourceFlags=0x548 } }
NOW = 500; Fire("PLAYER_DEAD"); Advance(510)""")
check("Player killer flagged as PvP", last(lua, "pvp") is True)

lua.execute("""CHAT = {}; RECAP = { { event="SPELL_DAMAGE", sourceName=SECRET, spellName=SECRET, amount=SECRET, timestamp=SECRET } }
UNITS.target = { name="Defias Thug", level=14, class="elite", hostile=true, targetingMe=true }
NOW = 600; Fire("UNIT_COMBAT", "player", "WOUND", "", 70, 1); Fire("PLAYER_DEAD"); Advance(603)""")
check("Secret recap: the attacker is used first", last(lua, "from") == "guess" and last(lua, "killer") == "Defias Thug")
check("The guess is announced as 'Probably killed by'", "Probably killed by" in chat(lua))
lua.execute("""RECAP = { { event="SPELL_DAMAGE", sourceName="Defias Thug", spellName="Backstab", amount=88, overkill=-1, timestamp=601 },
  { event="SPELL_DAMAGE", sourceName=SECRET, spellName=SECRET, amount=SECRET, timestamp=SECRET } }
Advance(620)""")
check("Recap applied once it becomes readable", last(lua, "from") == "recap" and last(lua, "ability") == "Backstab")
check("Follow-up line says 'Death recap:'", "Death recap: Killed by" in chat(lua))
check("Killer level and rank kept from the attacker", last(lua, "killerLevel") == 14 and last(lua, "killerClass") == "elite")
check("No overkill (-1) shows no overkill", last(lua, "overkill") is None and "overkill" not in chat(lua))
check("An all-secret earlier hit is left out", lua.eval("#KrakenDeathCounter_DB.log[#KrakenDeathCounter_DB.log].hits") == 1)

lua.execute("""CHAT = {}; RECAP = { { event="SPELL_DAMAGE", sourceName=SECRET, timestamp=SECRET } }
UNITS.target = { name="Defias Thug", level=14, class="elite", hostile=true, targetingMe=true }
NOW = 640; Fire("UNIT_COMBAT", "player", "WOUND", "", 70, 1); Fire("PLAYER_DEAD"); Advance(642)
RECAP = { { event="SPELL_DAMAGE", sourceName="Defias Pathstalker", spellName="Sinister Strike", amount=40, timestamp=641 } }
Advance(680)""")
check("Recap naming someone else drops the guessed mob's level", last(lua, "killer") == "Defias Pathstalker" and last(lua, "killerLevel") is None and last(lua, "killerClass") is None)
lua.execute("UNITS = {}")

lua.execute("""CHAT = {}; RECAP = nil
UNITS.focus = { name="Murloc Raider", level=11, hostile=true, targetingMe=true }
UNITS.mouseover = { name="Stormwind Guard", level=30, hostile=false, targetingMe=true }
NOW = 700; Fire("UNIT_COMBAT", "player", "WOUND", "CRITICAL", 33, 1); UNITS = {}
NOW = 703; Fire("PLAYER_DEAD"); Advance(800)""")
check("No recap: blames the attacker seen while you took damage", last(lua, "killer") == "Murloc Raider" and last(lua, "from") == "guess")
check("Non-hostile units are not blamed", lua.eval("#KrakenDeathCounter_DB.log[#KrakenDeathCounter_DB.log].attackers") == 1)
check("Last hit amount kept", last(lua, "amount") == 33)
check("Chat line: 'Probably killed by Murloc Raider (11), last hit 33'", "Probably killed by |cffff5555Murloc Raider|r (11), last hit 33" in chat(lua))

lua.execute("""CHAT = {}; NOW = 900; UNITS.target = { name="Old Mob", hostile=true, targetingMe=true }
Fire("UNIT_COMBAT", "player", "WOUND", "", 10, 1); UNITS = {}; NOW = 950; Fire("PLAYER_DEAD"); Advance(1100)""")
check("Attackers from over 10s ago aren't blamed", last(lua, "killer") is None)
check("Unknown killer is still logged and announced", log_n(lua) == 8 and "Killed by an unknown attacker in " in chat(lua))

lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("announce"); CHAT = {}; NOW = 1200; Fire("PLAYER_DEAD"); Advance(1300)')
check("/kdc announce turns the chat line off", "Killed by" not in chat(lua) and lua.eval("KrakenDeathCounter_DB.announce") is False)
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("announce")')

lua.execute('CHAT = {}; SlashCmdList.KRAKENDEATHCOUNTER("last")')
check("/kdc last prints the last death", "Last death:" in chat(lua))

lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("log")')
texts = lua.eval("AllTexts()")
check("/kdc log opens the window", lua.eval("KrakenDeathLogFrame.shown") is True)
check("Window lists Hogger and Falling", "Hogger" in texts and "Falling" in texts)
check("Summary counts the deaths", ("%d deaths logged" % log_n(lua)) in texts)
check("Summary names the top killers", "Most often: Hogger x1" in texts or "Most often:" in texts)
lua.execute('KrakenDeathCounterFrame.scripts.OnMouseUp(KrakenDeathCounterFrame, "RightButton")')
check("Right-click on the counter toggles the window", lua.eval("KrakenDeathLogFrame.shown") is False)
lua.execute('KrakenDeathCounterFrame.scripts.OnMouseUp(KrakenDeathCounterFrame, "LeftButton")')
check("Left-click doesn't open it", lua.eval("KrakenDeathLogFrame.shown") is False)

lua.execute('table.insert(KrakenDeathCounter_DB.log, 1, { t = 1, who = "Prime Arnold", killer = "Grizzled Bear", from = "recap" })')
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("log")')
check("Other characters' deaths hidden by default", "Grizzled Bear" not in lua.eval("AllTexts()"))
lua.execute('KrakenDeathLogFrame.toggle.scripts.OnClick()')
check("All-characters button shows them", "Grizzled Bear" in lua.eval("AllTexts()") and "Prime Arnold" in lua.eval("AllTexts()"))
mine = log_n(lua) - 1
lua.execute('CHAT = {}; SlashCmdList.KRAKENDEATHCOUNTER("clearlog")')
check("/kdc clearlog erases only this character", log_n(lua) == 1 and lua.eval("KrakenDeathCounter_DB.log[1].who") == "Prime Arnold")
check("/kdc clearlog reports how many", ("Erased %d deaths" % mine) in chat(lua))
lua.execute('CHAT = {}; SlashCmdList.KRAKENDEATHCOUNTER("last")')
check("/kdc last with nothing logged", "No deaths logged" in chat(lua))

lua = boot('KrakenDeathCounter_DB = { log = {} }; for i = 1, 1000 do KrakenDeathCounter_DB.log[i] = { t = i, who = "Selene", killer = "Old" .. i } end')
lua.execute('NOW = 50; DEATHS = 1; Fire("PLAYER_DEAD"); Advance(200)')
check("Log capped at 1000, oldest dropped", log_n(lua) == 1000 and lua.eval("KrakenDeathCounter_DB.log[1].killer") == "Old2")
check("Counter still updates alongside the log", shown(lua) == "Deaths: 1")

# Earlier deaths from Kraken Log's records
KLOG = r"""
function GetRealmName() return "Test Realm" end
KrakenLog_DB = { ["Test Realm - Luna"] = {
  "2026-11-08 14:00:00 | ? 45.3,72.1 | LOGIN | Luna, level 14 High Order Skyborne Warrior, build x, realm y",
  "2026-11-08 14:27:32 | Elwynn Forest 76.6,86.5 | CAST | 284 Heroic Strike on Croaky, id 248278, lvl 11, hostile",
  "2026-11-08 14:27:50 | Elwynn Forest 76.6,86.5 | XP | Croaky dies, you gain 125 experience.",
  "2026-11-08 14:27:51 | Elwynn Forest 76.6,86.7 | TARGET | Murloc Forager, id 46, lvl 10, hostile",
  "2026-11-08 14:27:58 | Elwynn Forest 76.6,86.5 | TARGET | Charity, lvl 11, player Priest",
  "2026-11-08 14:28:05 | Elwynn Forest 76.4,87.0 | CAST | 355 Taunt on Murloc Forager, id 46, lvl 10, hostile",
  "2026-11-08 14:28:05 | Elwynn Forest 76.4,87.0 | DIED | ",
  "2026-11-08 14:28:05 | Elwynn Forest 76.4,87.0 | DIED | ",
  "2026-11-08 14:31:29 | Elwynn Forest 74.0,72.3 | LEVEL_UP | 15",
  "2026-11-08 15:00:00 | Elwynn Forest/Goldshire 42.1,67.1 | TARGET | Prowler, id 118, lvl 9, hostile",
  "2026-11-08 15:05:00 | Elwynn Forest/Goldshire 42.1,67.1 | DIED | ",
  "2026-11-08 16:00:00 | Westfall 40.0,40.0 | TARGET | Kobold Miner, id 40, lvl 12, hostile",
  "2026-11-08 16:00:10 | Westfall 40.0,40.0 | CAST | 6343 Thunder Clap on Prowler Wolf, id 118, lvl 11, hostile",
  "2026-11-08 16:00:12 | Westfall 40.0,40.0 | XP | Prowler Wolf dies, you gain 50 experience.",
  "2026-11-08 16:00:15 | Westfall 40.0,40.0 | DIED | ",
} }
"""
lua = boot()
lua.execute(KLOG)
lua.execute('ME = "Luna"; CHAT = {}; Fire("PLAYER_LOGIN"); Advance(NOW + 1)')
log = lambda: [lua.eval(f"KrakenDeathCounter_DB.log[{i}]") for i in range(1, lua.eval("#KrakenDeathCounter_DB.log") + 1)]
L = log()
check("Import: Kraken Log deaths are added at login (double DIED line counted once)", len(L) == 3)
check("Import: the last mob targeted had died, so the one still alive is the killer", L[2]["killer"] == "Kobold Miner")
e = L[0]
check("Import: killer is the last enemy fought, not one that had already died",
      e["killer"] == "Murloc Forager" and e["killerLevel"] == 10)
check("Import: zone, coordinates and your level at the time", e["zone"] == "Elwynn Forest" and e["coords"] == "76.4, 87.0" and e["level"] == 14)
check("Import: the fight lists the mob you killed", "Croaky (you killed it)" in list(e["fight"].values()))
check("Import: players aren't counted as enemies", "Charity" not in str(list(e["fight"].values())))
check("Import: a death with no enemy in the last 30 seconds has no killer", L[1]["killer"] is None and L[1]["sub"] == "Goldshire")
check("Import: says so in chat", "3 earlier deaths from Kraken Log" in lua.eval("ChatText()"))
lua.execute('CHAT = {}; SAVED_W = table.remove(KrakenDeathCounter_DB.log); SlashCmdList.KRAKENDEATHCOUNTER("last")')
check("Import: no killer reads 'Unknown', not 'probably Unknown'",
      "unknown attacker" in lua.eval("ChatText()") and "probably" not in lua.eval("ChatText()"))
lua.execute('CHAT = {}; SAVED_E = table.remove(KrakenDeathCounter_DB.log); SlashCmdList.KRAKENDEATHCOUNTER("last")')
check("Import: a guessed killer reads 'probably'", "probably" in lua.eval("ChatText()") and "Murloc Forager" in lua.eval("ChatText()"))
lua.execute('table.insert(KrakenDeathCounter_DB.log, SAVED_E); table.insert(KrakenDeathCounter_DB.log, SAVED_W)')
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("import")')
check("Import: running it again adds nothing", len(log()) == 3 and "aren't already in the log" in lua.eval("ChatText()"))
lua.execute('SlashCmdList.KRAKENDEATHCOUNTER("clearlog"); Fire("PLAYER_LOGIN")')
check("Import: once per character, so clearlog stays cleared at the next login", len(log()) == 0)

print(f"\n{sum(results)}/{len(results)} passed")
sys.exit(0 if all(results) else 1)
