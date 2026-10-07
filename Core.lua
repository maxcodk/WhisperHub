-- WhisperHub / Core.lua   (WoW 1.12.1, Lua 5.0: no '#', no select, no string.gmatch)
-- Design rule: the DATA MODEL is updated first and independently of any UI.
-- The UI is only a view of WH.convos, so a UI bug can never "lose" a whisper.

WH = {}
local WH = WH
local getn, tinsert, tremove = table.getn, table.insert, table.remove

WH.VERSION  = "0.2.4"
WH.MAXLINES = 200                       -- lines kept in memory per conversation
WH.convos   = {}                        -- key(lowercase name) -> conversation
WH.seq      = 0                         -- global line counter
WH.pending  = {}                        -- lines received before the DB was ready
WH.stats    = { recv = 0, stored = 0, failed = 0, dberr = 0 }
WH.captureOK = true                     -- set to false after an internal error -> chat frames get whispers again

local defaults = {
  suppress = 1,   -- hide whispers from normal chat frames (they live in WhisperHub)
  sound    = 1,
  autoopen = 1,   -- open the window on incoming whisper (not in combat)
  takeover = 1,   -- intercept /w, /r, "Whisper" buttons and open WhisperHub tabs
  button   = 1,   -- permanent free-floating button (minimap style, drag anywhere)
  icon     = 1,   -- on-screen message icon: 1 = only when unread, 2 = always, 0 = never
  history  = 100, -- lines loaded from DB when a conversation is opened
  keepdays = 0,   -- delete DB history older than N days at login (0 = keep forever)
  who      = 1,   -- background /who lookups for guild/zone/level of the active contact
  whodelay = 6,   -- seconds between background /who requests
  deferopen = 1,  -- whisper arrived in combat: open the window when combat ends
  hidecombat = 0, -- hide the window while in combat
}

function WH.Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ffcc[WhisperHub]|r " .. tostring(msg)) end
local Print = WH.Print

function WH.Get(k)
  local v = WhisperHubDB and WhisperHubDB.opt and WhisperHubDB.opt[k]
  if v == nil then return defaults[k] end
  return v
end
function WH.Set(k, v)
  WhisperHubDB = WhisperHubDB or {}
  WhisperHubDB.opt = WhisperHubDB.opt or {}
  WhisperHubDB.opt[k] = v
end

local function Key(name) return string.lower(name) end
local function Esc(s) local r = string.gsub(tostring(s), "'", "''"); return r end

---------------------------------------------------------------------------
-- conversations
---------------------------------------------------------------------------
function WH.GetConvo(name, create)
  local k = Key(name)
  local c = WH.convos[k]
  if not c and create then
    c = { name = name, key = k, lines = {}, unread = 0, last = 0, loaded = false, hidden = false }
    WH.convos[k] = c
  end
  return c
end

-- put already-persisted lines in front of the live ones
function WH.Prepend(c, list)
  local merged = {}
  for i = 1, getn(list) do tinsert(merged, list[i]) end
  for i = 1, getn(c.lines) do tinsert(merged, c.lines[i]) end
  while getn(merged) > WH.MAXLINES do tremove(merged, 1) end
  c.lines = merged
end

function WH.AddLine(name, out, text, kind)
  local c = WH.GetConvo(name, true)
  WH.seq = WH.seq + 1
  local line = { seq = WH.seq, ts = time(), out = out, text = text, kind = kind or "msg" }
  tinsert(c.lines, line)
  if getn(c.lines) > WH.MAXLINES then tremove(c.lines, 1) end
  c.last = line.ts
  c.hidden = false
  if line.kind == "msg" then WH.Persist(c, line) end
  return c, line
end

---------------------------------------------------------------------------
-- player info: class / level / race / guild / zone
-- sources: units around us (free) -> background /who (queued, throttled, results swallowed like WIM does)
---------------------------------------------------------------------------
-- localized class name -> token. English works via upper-casing; Russian is best effort; units teach more at runtime.
local classMap = {
  ["Воин"]="WARRIOR", ["Паладин"]="PALADIN", ["Охотник"]="HUNTER", ["Охотница"]="HUNTER", ["Разбойник"]="ROGUE",
  ["Разбойница"]="ROGUE", ["Жрец"]="PRIEST", ["Жрица"]="PRIEST", ["Шаман"]="SHAMAN", ["Шаманка"]="SHAMAN",
  ["Маг"]="MAGE", ["Чернокнижник"]="WARLOCK", ["Чернокнижница"]="WARLOCK", ["Друид"]="DRUID",
}
function WH.ClassToken(localized)
  if not localized or localized == "" then return nil end
  if classMap[localized] then return classMap[localized] end
  local up = string.upper(localized)
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[up] then return up end
  return nil
end

function WH.GetInfo(name)
  local t = WhisperHubDB and WhisperHubDB.info
  return t and t[Key(name)]
end

local function SetInfo(name, f)
  if not (WhisperHubDB and WhisperHubDB.info) then return end
  local k = Key(name)
  local i = WhisperHubDB.info[k]
  if not i then i = {}; WhisperHubDB.info[k] = i end
  if f.class and f.class ~= "" then i.class = f.class end
  if f.classLoc and f.classLoc ~= "" then i.classLoc = f.classLoc end
  if f.level and f.level ~= 0 then i.level = f.level end
  if f.race and f.race ~= "" then i.race = f.race end
  if f.guild ~= nil then i.guild = f.guild end          -- "" = no guild
  if f.zone and f.zone ~= "" then i.zone = f.zone; i.zt = time(); i.mt = nil end
  if f.miss then i.mt = time() end          -- /who found nobody (offline / hidden)
end

local scanUnits
function WH.ScanUnits(name)
  if not scanUnits then
    scanUnits = { "target", "mouseover", "party1", "party2", "party3", "party4" }
    for i = 1, 40 do tinsert(scanUnits, "raid" .. i) end
  end
  for i = 1, getn(scanUnits) do
    local u = scanUnits[i]
    if UnitExists(u) and UnitIsPlayer(u) and UnitName(u) == name then
      local loc, token = UnitClass(u)
      if loc and token then classMap[loc] = token end
      local guild = GetGuildInfo(u)
      SetInfo(name, { class = token, classLoc = loc, level = UnitLevel(u), race = UnitRace(u), guild = guild or "" })
      return true
    end
  end
  return false
end

-- called for incoming whispers and when a tab is selected
function WH.ScanClass(name)
  if not (WhisperHubDB and WhisperHubDB.info) then return end
  WH.ScanUnits(name)                -- free data (class/level/guild) from units we can see
  if WH.Get("who") ~= 1 then return end
  local i, now = WH.GetInfo(name), time()
  local zoneFresh = i and i.zt and now - i.zt <= 120
  local missFresh = i and i.mt and now - i.mt <= 120
  if not zoneFresh and not missFresh then WH.QueueWho(name) end   -- zone only comes from /who
end

function WH.ClassHex(name)
  local i = WH.GetInfo(name)
  local col = i and i.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[i.class]
  if col then
    return string.format("%02x%02x%02x", math.floor(col.r * 255 + .5), math.floor(col.g * 255 + .5), math.floor(col.b * 255 + .5))
  end
  return "ff80ff"
end

-- background /who ----------------------------------------------------------
local who = { queue = {}, busy = false, sent = 0, last = 0 }
WH.who = who

local whoFrame = CreateFrame("Frame", "WhisperHubWho")   -- OnUpdate runs ONLY while the queue is non-empty

local function WhoTick()
  local now = GetTime()
  if who.busy then
    if now - who.sent > 8 then who.busy = false; SetWhoToUI(0) end   -- no answer, give up
    return
  end
  if getn(who.queue) == 0 then whoFrame:SetScript("OnUpdate", nil); return end
  if now - who.last < WH.Get("whodelay") then return end
  local name = tremove(who.queue, 1)
  who.name, who.busy, who.sent, who.last = name, true, now, now
  SetWhoToUI(1)
  SendWho('n-"' .. name .. '"')
end

function WH.QueueWho(name, force)
  if not force and WH.Get("who") ~= 1 then return end
  local k = Key(name)
  if who.busy and who.name and Key(who.name) == k then return end
  for i = 1, getn(who.queue) do if Key(who.queue[i]) == k then return end end
  if getn(who.queue) >= 10 then return end
  tinsert(who.queue, name)
  whoFrame:SetScript("OnUpdate", WhoTick)
end

-- processed INSIDE the FriendsFrame hook so the stock /who panel never pops up (same trick as WIM)
local function HandleWhoResult()
  local n = GetNumWhoResults()
  local found = false
  for i = 1, n do
    local name, guild, level, race, class, zone = GetWhoInfo(i)
    if name and who.name and Key(name) == Key(who.name) then
      found = true
      SetInfo(name, { class = WH.ClassToken(class), classLoc = class, level = level, race = race, guild = guild or "", zone = zone })
      if WH.uiOK then WH.UIInfoChanged(name) end
    end
  end
  if not found and who.name then
    SetInfo(who.name, { miss = true })
    if WH.uiOK then WH.UIInfoChanged(who.name) end
  end
  who.busy = false
  SetWhoToUI(0)
end

local origFriendsEvent = FriendsFrame_OnEvent
FriendsFrame_OnEvent = function(ev)
  if event == "WHO_LIST_UPDATE" and who.busy then
    pcall(HandleWhoResult)
    return
  end
  return origFriendsEvent(ev)
end

local origWhoListUpdate = WhoList_Update
WhoList_Update = function()
  if who.busy then return end
  return origWhoListUpdate()
end

---------------------------------------------------------------------------
-- storage: HearthDB (SQLite, async writes) with SavedVariables fallback
---------------------------------------------------------------------------
function WH.OnWrite(rows, err)
  if err then
    WH.stats.dberr = WH.stats.dberr + 1
    pcall(HDB_ClearPoison, WH.db)
    if WH.stats.dberr == 1 then Print("DB write failed: " .. tostring(err)) end
  else
    WH.stats.stored = WH.stats.stored + 1
  end
end

function WH.SVBucket(c, create)
  WhisperHubDB.sv = WhisperHubDB.sv or {}
  local rk = WH.realm .. "\t" .. WH.me
  local r = WhisperHubDB.sv[rk]
  if not r then r = {}; WhisperHubDB.sv[rk] = r end
  local b = r[c.key]
  if not b and create then b = { name = c.name, lines = {} }; r[c.key] = b end
  return b, r
end

function WH.DBInsert(c, line)
  if WH.backend == "hdb" then
    local sql = "INSERT INTO messages (realm, me, pkey, peer, dir, ts, text) VALUES ('"
      .. Esc(WH.realm) .. "','" .. Esc(WH.me) .. "','" .. Esc(c.key) .. "','" .. Esc(c.name) .. "',"
      .. (line.out and 1 or 0) .. "," .. line.ts .. ",'" .. Esc(line.text) .. "')"
    local ok, err = pcall(HDB_ExecuteAsync, WH.db, sql, WH.OnWrite)
    if not ok then WH.OnWrite(nil, err) end
  else
    local b = WH.SVBucket(c, true)
    tinsert(b.lines, { line.ts, line.out and 1 or 0, line.text })
    while getn(b.lines) > WH.MAXLINES do tremove(b.lines, 1) end
    WH.stats.stored = WH.stats.stored + 1
  end
end

function WH.Persist(c, line)
  if not WH.dbReady then
    tinsert(WH.pending, { c, line })
  else
    WH.DBInsert(c, line)
  end
end

function WH.LoadHistory(c)
  if c.loaded or c.loading then return end
  if WH.backend ~= "hdb" then c.loaded = true; return end
  c.loading = true
  local req = WH.seq
  local sql = "SELECT dir, ts, text FROM (SELECT id, dir, ts, text FROM messages WHERE realm='" .. Esc(WH.realm)
    .. "' AND me='" .. Esc(WH.me) .. "' AND pkey='" .. Esc(c.key) .. "' ORDER BY id DESC LIMIT "
    .. WH.Get("history") .. ") ORDER BY id ASC"
  local ok = pcall(HDB_QueryAsync, WH.db, sql, function(rows, err)
    c.loading = false
    c.loaded = true
    if err then pcall(HDB_ClearPoison, WH.db); return end
    local loaded = {}
    for i = 1, getn(rows) do
      local r = rows[i]
      tinsert(loaded, { seq = 0, ts = tonumber(r.ts) or 0, out = (r.dir == "1"), text = r.text or "", kind = "msg" })
    end
    -- lines with seq <= req were already written to the DB before this query -> they are in 'loaded'
    local live = {}
    for i = 1, getn(c.lines) do
      local l = c.lines[i]
      if l.kind == "sys" or l.seq > req then tinsert(live, l) end
    end
    c.lines = live
    WH.Prepend(c, loaded)
    if WH.uiOK then WH.UIRefreshConvo(c) end
  end)
  if not ok then c.loading = false; c.loaded = true end
end

function WH.DeleteHistory(c)
  if WH.backend == "hdb" then
    pcall(HDB_ExecuteAsync, WH.db, "DELETE FROM messages WHERE realm='" .. Esc(WH.realm) .. "' AND me='" .. Esc(WH.me)
      .. "' AND pkey='" .. Esc(c.key) .. "'", WH.OnWrite)
  else
    local b, r = WH.SVBucket(c, false)
    if b then r[c.key] = nil end
  end
  WH.convos[c.key] = nil
end

function WH.Init()
  if WH.inited then return end
  WH.inited = true
  WhisperHubDB = WhisperHubDB or {}
  WhisperHubDB.opt = WhisperHubDB.opt or {}
  WhisperHubDB.info = WhisperHubDB.info or {}
  WhisperHubDB.pins = WhisperHubDB.pins or {}
  WH.realm = GetRealmName()
  WH.me = UnitName("player")
  WH.pinKey = WH.realm .. "\t" .. WH.me
  WhisperHubDB.pins[WH.pinKey] = WhisperHubDB.pins[WH.pinKey] or {}

  if HDB_Open then
    local ok, h = pcall(HDB_Open, "WhisperHub.db")
    if ok then
      local ok2, err = pcall(HDB_Execute, h, [[
        CREATE TABLE IF NOT EXISTS messages (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          realm TEXT NOT NULL, me TEXT NOT NULL, pkey TEXT NOT NULL, peer TEXT NOT NULL,
          dir INTEGER NOT NULL, ts INTEGER NOT NULL, text TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS idx_conv ON messages(realm, me, pkey, id);
      ]])
      if ok2 then WH.db = h; WH.backend = "hdb" else Print("HearthDB schema error: " .. tostring(err)) end
    else
      Print("HDB_Open failed: " .. tostring(h))
    end
  end

  if WH.backend ~= "hdb" then
    WH.backend = "sv"
    Print("HearthDB not found - history is kept in SavedVariables (saved on logout/reload only).")
    local _, r = WH.SVBucket({ key = "" }, false)
    for k, b in pairs(r) do
      local c = WH.GetConvo(b.name, true)
      c.loaded = true
      local list = {}
      for i = 1, getn(b.lines) do
        local l = b.lines[i]
        tinsert(list, { seq = 0, ts = l[1], out = (l[2] == 1), text = l[3], kind = "msg" })
        if l[1] > c.last then c.last = l[1] end
      end
      WH.Prepend(c, list)
    end
  end

  -- retention: /wh keep <days>
  local keep = tonumber(WH.Get("keepdays")) or 0
  if keep > 0 then
    local cutoff = time() - keep * 86400
    if WH.backend == "hdb" then
      pcall(HDB_ExecuteAsync, WH.db, "DELETE FROM messages WHERE ts < " .. cutoff, WH.OnWrite)
    else
      local _, r = WH.SVBucket({ key = "" }, false)
      for k, b in pairs(r) do
        while getn(b.lines) > 0 and b.lines[1][1] < cutoff do tremove(b.lines, 1) end
      end
    end
  end

  -- pinned conversations are always in the list
  for k, nm in pairs(WhisperHubDB.pins[WH.pinKey]) do
    WH.GetConvo(nm, true)
  end

  WH.dbReady = true
  for i = 1, getn(WH.pending) do WH.DBInsert(WH.pending[i][1], WH.pending[i][2]) end
  WH.pending = {}

  if WH.backend == "hdb" then
    pcall(HDB_QueryAsync, WH.db, "SELECT peer, MAX(ts) AS lastts FROM messages WHERE realm='" .. Esc(WH.realm)
      .. "' AND me='" .. Esc(WH.me) .. "' GROUP BY pkey ORDER BY lastts DESC LIMIT 100", function(rows, err)
      if err then pcall(HDB_ClearPoison, WH.db); return end
      for i = 1, getn(rows) do
        local c = WH.GetConvo(rows[i].peer, true)
        local t = tonumber(rows[i].lastts) or 0
        if t > c.last then c.last = t end
      end
      if WH.uiOK then WH.UIRefresh() end
    end)
  end

  local ok, err = pcall(WH.CreateUI)
  if ok then WH.uiOK = true; WH.uiError = nil; WH.UIRefresh() else WH.uiError = tostring(err); Print("UI error: " .. WH.uiError) end
end

---------------------------------------------------------------------------
-- pins, search
---------------------------------------------------------------------------
function WH.IsPinned(key) return WhisperHubDB.pins and WhisperHubDB.pins[WH.pinKey] and WhisperHubDB.pins[WH.pinKey][key] and true or false end
function WH.TogglePin(c)
  local p = WhisperHubDB.pins[WH.pinKey]
  if p[c.key] then p[c.key] = nil else p[c.key] = c.name end
end

local function Out(ts, dir, peer, text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff888888" .. date("%d.%m.%y %H:%M", ts) .. "|r |cffff80ff" .. (dir and ("-> " .. peer) or ("<- " .. peer)) .. "|r: " .. text)
end

function WH.Find(text)
  if text == "" then Print("/wh find <text>"); return end
  if WH.backend == "hdb" then
    local pat = string.gsub(string.gsub(string.gsub(text, "\\", "\\\\"), "%%", "\\%%"), "_", "\\_")
    local sql = "SELECT peer, dir, ts, text FROM messages WHERE realm='" .. Esc(WH.realm) .. "' AND me='" .. Esc(WH.me)
      .. "' AND text LIKE '%" .. Esc(pat) .. "%' ESCAPE '\\' ORDER BY id DESC LIMIT 15"
    pcall(HDB_QueryAsync, WH.db, sql, function(rows, err)
      if err then pcall(HDB_ClearPoison, WH.db); Print("search error: " .. tostring(err)); return end
      Print(getn(rows) .. " match(es), newest first:")
      for i = 1, getn(rows) do local r = rows[i]; Out(tonumber(r.ts) or 0, r.dir == "1", r.peer, r.text) end
    end)
  else
    local n, low = 0, string.lower(text)
    local _, r = WH.SVBucket({ key = "" }, false)
    for k, b in pairs(r) do
      for i = getn(b.lines), 1, -1 do
        local l = b.lines[i]
        if n < 15 and string.find(string.lower(l[3]), low, 1, true) then Out(l[1], l[2] == 1, b.name, l[3]); n = n + 1 end
      end
    end
    Print(n .. " match(es)")
  end
end

---------------------------------------------------------------------------
-- chat capture
---------------------------------------------------------------------------
local function GlobalToPattern(s)
  s = string.gsub(s, "([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
  s = string.gsub(s, "%%s", "(.+)")
  return s
end
WH.notFound = ERR_CHAT_PLAYER_NOT_FOUND_S and GlobalToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S) or nil

function WH.HandleChat(ev, text, who)
  if ev == "CHAT_MSG_WHISPER" then
    local c = WH.AddLine(who, false, text)
    WH.ScanClass(who)
    -- the default handler normally records this for /r; we may suppress it, so do it ourselves
    pcall(ChatEdit_SetLastTellTarget, DEFAULT_CHAT_FRAME.editBox, who)
    WH.OnIncoming(c)
  elseif ev == "CHAT_MSG_WHISPER_INFORM" then
    local c = WH.AddLine(who, true, text)
    if ChatEdit_SetLastToldTarget then pcall(ChatEdit_SetLastToldTarget, DEFAULT_CHAT_FRAME.editBox, who) end
    if WH.uiOK then WH.UIUpdate(c) end
  elseif ev == "CHAT_MSG_AFK" or ev == "CHAT_MSG_DND" then
    local c = WH.GetConvo(who)
    if c then
      WH.AddLine(who, false, "<" .. (ev == "CHAT_MSG_AFK" and "AFK" or "DND") .. "> " .. text, "sys")
      if WH.uiOK then WH.UIUpdate(c) end
    end
  elseif ev == "CHAT_MSG_SYSTEM" and WH.notFound then
    local _, _, n = string.find(text, WH.notFound)
    local c = n and WH.GetConvo(n)
    if c then
      WH.AddLine(c.name, false, text, "sys")
      if WH.uiOK then WH.UIUpdate(c) end
    end
  end
end

function WH.OnIncoming(c)
  local visible = WH.uiOK and WhisperHubFrame:IsVisible()
  if not (visible and WH.ui.cur == c.key) then c.unread = c.unread + 1 end
  WH.lastUnread = c.key
  if WH.Get("sound") == 1 then PlaySound("TellMessage") end
  if not WH.uiOK then return end
  if not visible and WH.Get("autoopen") == 1 then
    if UnitAffectingCombat("player") then
      if WH.Get("deferopen") == 1 then WH.openAfter = c.key end
      WH.UIUpdate(c)
    else
      WH.ShowFrame()
      WH.Select(c.key)
    end
  else
    WH.UIUpdate(c)
  end
  WH.IconAlert()
end

local ef = CreateFrame("Frame", "WhisperHubEvents")
ef:RegisterEvent("VARIABLES_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("CHAT_MSG_WHISPER")
ef:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
ef:RegisterEvent("CHAT_MSG_AFK")
ef:RegisterEvent("CHAT_MSG_DND")
ef:RegisterEvent("CHAT_MSG_SYSTEM")
ef:RegisterEvent("PLAYER_REGEN_DISABLED")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    WhisperHubDB = WhisperHubDB or {}
    WhisperHubDB.opt = WhisperHubDB.opt or {}
    WhisperHubDB.info = WhisperHubDB.info or {}
  elseif event == "PLAYER_ENTERING_WORLD" then
    WH.Init()
  elseif event == "PLAYER_REGEN_DISABLED" then
    if WH.uiOK and WH.Get("hidecombat") == 1 and WhisperHubFrame:IsVisible() then
      WH.hiddenByCombat = true
      WhisperHubFrame:Hide()
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if WH.uiOK then
      if WH.hiddenByCombat then WH.hiddenByCombat = false; WH.ShowFrame() end
      if WH.openAfter and WH.convos[WH.openAfter] then
        local k = WH.openAfter
        WH.openAfter = nil
        if not WhisperHubFrame:IsVisible() then WH.ShowFrame() end
        WH.Select(k)
      end
      WH.openAfter = nil
    end
  else
    if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then WH.stats.recv = WH.stats.recv + 1 end
    local ok, err = pcall(WH.HandleChat, event, arg1, arg2)
    if not ok then
      WH.stats.failed = WH.stats.failed + 1
      WH.captureOK = false                       -- give whispers back to the normal chat frames
      if event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_WHISPER_INFORM" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff80ff[" .. (event == "CHAT_MSG_WHISPER" and "From " or "To ") .. tostring(arg2) .. "]: " .. tostring(arg1) .. "|r")
      end
      if WH.stats.failed == 1 then Print("capture error (whispers go to chat again): " .. tostring(err)) end
    end
  end
end)

---------------------------------------------------------------------------
-- hooks (installed at load; every hook falls back to the original behaviour until the UI is ready)
---------------------------------------------------------------------------
function WH.ShouldSuppress()
  return WH.uiOK and WH.captureOK and WH.Get("suppress") == 1
end

local origOnEvent = ChatFrame_OnEvent
ChatFrame_OnEvent = function(ev)
  if (ev == "CHAT_MSG_WHISPER" or ev == "CHAT_MSG_WHISPER_INFORM") and WH.ShouldSuppress() then return end
  return origOnEvent(ev)
end

local function TakeOver() return WH.uiOK and WH.Get("takeover") == 1 end

local origSendTell = ChatFrame_SendTell
ChatFrame_SendTell = function(name, chatFrame)
  if TakeOver() and name and name ~= "" then WH.Open(name) else return origSendTell(name, chatFrame) end
end

local origReply = ChatFrame_ReplyTell
ChatFrame_ReplyTell = function(chatFrame)
  if TakeOver() then
    chatFrame = chatFrame or DEFAULT_CHAT_FRAME
    local t = ChatEdit_GetLastTellTarget(chatFrame.editBox)
    if t and t ~= "" then WH.Open(t); return end
  end
  return origReply(chatFrame)
end

local origFriendsSend = FriendsFrame_SendMessage
FriendsFrame_SendMessage = function()
  if TakeOver() then
    local name = GetFriendInfo(FriendsFrame.selectedFriend)
    if name then WH.Open(name); return end
  end
  return origFriendsSend()
end

-- "/w Name" or "/r" typed WITHOUT text -> open the tab. With text: normal send, the INFORM event fills the tab.
local origParse = ChatEdit_ParseText
ChatEdit_ParseText = function(editBox, send)
  if TakeOver() and send and send ~= 0 then
    local _, _, command, rest = string.find(editBox:GetText(), "^(/%S+)%s*(.*)")
    if command then
      command = string.upper(command)
      local target
      local i = 1
      while true do
        local w, r = getglobal("SLASH_WHISPER" .. i), getglobal("SLASH_REPLY" .. i)
        if not w and not r then break end
        if w and command == string.upper(w) then
          local _, _, np, tp = string.find(rest, "^(%S+)%s*(.*)")
          if np and tp == "" then target = string.gsub(string.lower(np), "^%l", string.upper) end
          break
        elseif r and command == string.upper(r) and rest == "" then
          local t = ChatEdit_GetLastTellTarget(editBox)
          if t and t ~= "" then target = t end
          break
        end
        i = i + 1
      end
      if target then
        WH.Open(target)
        editBox:SetText("")
        editBox:Hide()
        return
      end
    end
  end
  return origParse(editBox, send)
end

---------------------------------------------------------------------------
-- slash command
---------------------------------------------------------------------------
SLASH_WHISPERHUB1 = "/wh"
SLASH_WHISPERHUB2 = "/whisperhub"
SlashCmdList["WHISPERHUB"] = function(msg)
  msg = string.lower(msg or "")
  local _, _, cmd, arg = string.find(msg, "^(%S*)%s*(%S*)")
  local function flag(name, label)
    local v = (arg == "on" or arg == "1") and 1 or 0
    WH.Set(name, v)
    Print(label .. ": " .. (v == 1 and "on" or "off"))
  end
  if cmd == "" then
    if not WH.uiOK then Print("UI not ready" .. (WH.uiError and (": " .. WH.uiError) or " yet (not logged in to the world?)")); return end
    if WhisperHubFrame:IsVisible() then WhisperHubFrame:Hide() else WH.ShowFrame() end
  elseif cmd == "suppress" then flag("suppress", "hide whispers from chat frames")
  elseif cmd == "sound" then flag("sound", "sound")
  elseif cmd == "autoopen" then flag("autoopen", "auto-open on incoming whisper")
  elseif cmd == "takeover" then flag("takeover", "intercept /w, /r, whisper buttons")
  elseif cmd == "options" or cmd == "config" or cmd == "settings" then
    if WH.uiOK then WH.ToggleOptions() end
  elseif cmd == "resetpos" then
    if WH.uiOK then WH.ResetPositions() end
  elseif cmd == "button" then
    flag("button", "floating button")
    if WH.uiOK then WH.UpdateIcon() end
  elseif cmd == "who" then flag("who", "background /who lookups (guild/zone)")
  elseif cmd == "deferopen" then flag("deferopen", "open window after combat")
  elseif cmd == "hidecombat" then flag("hidecombat", "hide window in combat")
  elseif cmd == "whodelay" then
    local n = tonumber(arg)
    if n and n >= 2 then WH.Set("whodelay", n); Print("/who delay: " .. n .. "s") else Print("usage: /wh whodelay <seconds >= 2>") end
  elseif cmd == "keep" then
    local n = tonumber(arg)
    if n and n >= 0 then WH.Set("keepdays", n); Print("history older than " .. n .. " days is deleted at login (0 = keep forever)") else Print("usage: /wh keep <days>") end
  elseif cmd == "find" then
    local _, _, rest = string.find(msg, "^find%s+(.+)$")
    WH.Find(rest or "")
  elseif cmd == "icon" then
    local v = (arg == "always") and 2 or ((arg == "off") and 0 or 1)
    WH.Set("icon", v)
    Print("message icon: " .. ((v == 2 and "always") or (v == 0 and "off") or "only when unread"))
    if WH.uiOK then WH.UpdateIcon() end
  elseif cmd == "debug" then
    Print("v" .. WH.VERSION .. " backend=" .. tostring(WH.backend) .. " HDB=" .. tostring(HDB_GetVersion and "yes" or "no")
      .. " ui=" .. tostring(WH.uiOK) .. " captureOK=" .. tostring(WH.captureOK))
    Print("whisper events=" .. WH.stats.recv .. " db-writes-ok=" .. WH.stats.stored .. " capture-failed=" .. WH.stats.failed .. " db-errors=" .. WH.stats.dberr)
  else
    Print("/wh - toggle | options | resetpos | button on|off | icon on|off|always | suppress | sound | autoopen | takeover | who | deferopen | hidecombat (on|off) | whodelay N | keep DAYS | find TEXT | debug")
  end
end
