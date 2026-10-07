-- WhisperHub / UI.lua
-- ONE window, ONE message frame, ONE edit box. Switching a tab just re-renders <=200 lines.
-- No per-window OnUpdate handlers -> dragging stays cheap however many conversations exist.

local WH = WH
local getn, tinsert = table.getn, table.insert
WH.ui = { offset = 0, rows = {}, rail = {} }
local ui = WH.ui

local NUM_ROWS, ROW_H = 15, 22
local BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local ME_COLOR = "bdbdbd"      -- neutral grey: unique, not any class colour

local function DayStr(ts) return date("%d.%m.%Y", ts) end
local function Separator(ts) return "|cff666666-------- " .. DayStr(ts) .. " --------|r" end

function WH.InfoLine(name)
  local i = WH.GetInfo(name)
  if not i then return WH.Get("who") == 1 and "|cff888888looking up info...|r" or "" end
  local parts = {}
  local main = ""
  if i.level then main = "Lvl " .. i.level end
  if i.race then main = main .. " " .. i.race end
  if i.classLoc then main = main .. " " .. i.classLoc end
  if main ~= "" then tinsert(parts, "|cffcccccc" .. main .. "|r") end
  if i.guild and i.guild ~= "" then tinsert(parts, "|cff40ff40<" .. i.guild .. ">|r") end
  if i.zone then tinsert(parts, "|cffffd200" .. i.zone .. "|r") end
  if getn(parts) == 0 then return i.mt and "|cff888888offline / not found|r" or "|cff888888looking up info...|r" end
  return table.concat(parts, "   ")
end

local function FormatLine(c, l)
  local t = (DayStr(l.ts) == DayStr(time())) and date("%H:%M", l.ts) or date("%d.%m %H:%M", l.ts)
  if l.kind == "sys" then return "|cff888888[" .. t .. "]|r |cffffcc00" .. l.text .. "|r" end
  local who, col
  if l.out then who, col = WH.me, ME_COLOR else who, col = c.name, WH.ClassHex(c.name) end
  return "|cff888888[" .. t .. "]|r |cff" .. col .. who .. "|r: " .. l.text
end

function WH.SavePos(frame, slot)
  local p, _, rp, x, y = frame:GetPoint()
  WhisperHubDB[slot] = { p, rp, x, y }
end
local function RestorePos(frame, slot, dp, dx, dy)
  local s = WhisperHubDB[slot]
  frame:ClearAllPoints()
  if s then frame:SetPoint(s[1], UIParent, s[2], s[3], s[4]) else frame:SetPoint(dp, UIParent, dp, dx, dy) end
end

---------------------------------------------------------------------------
-- rendering
---------------------------------------------------------------------------
function WH.RefreshList()
  local arr = {}
  for k, c in pairs(WH.convos) do if not c.hidden then tinsert(arr, c) end end
  table.sort(arr, function(a, b)
    local pa, pb = WH.IsPinned(a.key), WH.IsPinned(b.key)
    if pa ~= pb then return pa end
    if a.last ~= b.last then return a.last > b.last end
    return a.key < b.key
  end)
  ui.sorted = arr
  local maxoff = math.max(0, getn(arr) - NUM_ROWS)
  if ui.offset > maxoff then ui.offset = maxoff end
  if ui.offset < 0 then ui.offset = 0 end
  for i = 1, NUM_ROWS do
    local b, c = ui.rows[i], arr[i + ui.offset]
    if c then
      b.key = c.key
      b.text:SetText((WH.IsPinned(c.key) and "|cffffd200*|r" or "") .. "|cff" .. WH.ClassHex(c.name) .. c.name .. "|r")
      b.badge:SetText(c.unread > 0 and ("|cffff3333" .. c.unread .. "|r") or "")
      if c.key == ui.cur then b.sel:Show() else b.sel:Hide() end
      b:Show()
    else
      b.key = nil
      b:Hide()
    end
  end
end

function WH.UpdateHeader(c)
  if not c then ui.title:SetText("|cff888888-|r"); ui.sub:SetText(""); return end
  ui.title:SetText("|cff" .. WH.ClassHex(c.name) .. c.name .. "|r")
  ui.sub:SetText(WH.InfoLine(c.name))
end

local function IsIgnored(name)
  for i = 1, GetNumIgnores() do
    local n = GetIgnoreName(i)
    if n and string.lower(n) == string.lower(name) then return true end
  end
  return false
end

function WH.UpdateRail()
  local c = ui.cur and WH.convos[ui.cur]
  for i = 1, getn(ui.rail) do
    local b = ui.rail[i]
    if c then b:Enable() else b:Disable() end
  end
  if not c then return end
  ui.rail.ignore:SetText(IsIgnored(c.name) and "Unignore" or "Ignore")
  ui.rail.pin:SetText(WH.IsPinned(c.key) and "Unpin" or "Pin")
  if IsInGuild and not IsInGuild() then ui.rail.ginvite:Disable() end
end

function WH.RenderConvo(c)
  ui.msg:Clear()
  WH.UpdateHeader(c)
  WH.UpdateRail()
  if not c then return end
  local prev
  for i = 1, getn(c.lines) do
    local l = c.lines[i]
    local d = DayStr(l.ts)
    if d ~= prev then ui.msg:AddMessage(Separator(l.ts)); prev = d end
    ui.msg:AddMessage(FormatLine(c, l), 1, .5, 1)
  end
end

-- background /who delivered new info
function WH.UIInfoChanged(name)
  local c = ui.cur and WH.convos[ui.cur]
  if c and string.lower(c.name) == string.lower(name) then WH.UpdateHeader(c) end
  WH.RefreshList()
end

function WH.UnreadTotal()
  local n = 0
  for k, c in pairs(WH.convos) do n = n + c.unread end
  return n
end

-- re-render the active conversation after async history arrived
function WH.UIRefreshConvo(c)
  if WhisperHubFrame:IsVisible() and ui.cur == c.key then WH.RenderConvo(c) end
  WH.RefreshList()
end

function WH.UIRefresh()
  WH.RefreshList()
  WH.UpdateIcon()
end

-- a line was added to conversation c
function WH.UIUpdate(c)
  if WhisperHubFrame:IsVisible() and ui.cur == c.key then
    local n = getn(c.lines)
    local l = c.lines[n]
    if l then
      local pl = c.lines[n - 1]
      if not pl or DayStr(pl.ts) ~= DayStr(l.ts) then ui.msg:AddMessage(Separator(l.ts)) end
      ui.msg:AddMessage(FormatLine(c, l), 1, .5, 1)
    end
  end
  WH.UIRefresh()
end

---------------------------------------------------------------------------
-- selection / open / close
---------------------------------------------------------------------------
function WH.Select(key)
  local c = WH.convos[key]
  if not c then return end
  ui.cur = key
  c.unread = 0
  WH.LoadHistory(c)
  WH.ScanClass(c.name)          -- units first, queued /who if info is missing or stale
  WH.RenderConvo(c)
  WH.UIRefresh()
end

function WH.ShowFrame()
  WhisperHubFrame:Show()
  if not (ui.cur and WH.convos[ui.cur] and not WH.convos[ui.cur].hidden) then
    WH.RefreshList()
    local first = ui.sorted[1]
    if first then WH.Select(first.key) else ui.cur = nil; WH.RenderConvo(nil) end
  else
    WH.Select(ui.cur)
  end
end

function WH.Open(name)
  if not WH.uiOK then return end
  local c = WH.GetConvo(name, true)
  c.hidden = false
  if c.last == 0 then c.last = time() end
  WH.ScanClass(c.name)
  WH.ShowFrame()
  WH.Select(c.key)
  ui.edit:SetFocus()
end

function WH.CloseTab(key)
  local c = WH.convos[key]
  if not c then return end
  c.hidden = true
  if ui.cur == key then
    ui.cur = nil
    WH.RefreshList()
    local nxt = ui.sorted[1]
    if nxt then WH.Select(nxt.key) else WH.RenderConvo(nil) end
  end
  WH.UIRefresh()
end

function WH.NextUnread()
  local arr = ui.sorted or {}
  local n = getn(arr)
  if n == 0 then return end
  local idx = 0
  for i = 1, n do if arr[i].key == ui.cur then idx = i end end
  for step = 1, n do
    local c = arr[math.mod(idx + step - 1, n) + 1]
    if c.unread > 0 then WH.Select(c.key); return end
  end
  WH.Select(arr[math.mod(idx, n) + 1].key)
end

function WH.Send(name, text)
  if not name or text == "" then return end
  SendChatMessage(text, "WHISPER", GetDefaultLanguage("player"), name)
end

StaticPopupDialogs["WHISPERHUB_DELETE"] = {
  text = "Delete ALL saved history with %s?",
  button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function()
    local c = WH.convos[WH.deleteKey or ""]
    if c then
      WH.DeleteHistory(c)
      if ui.cur == c.key then ui.cur = nil; WH.RenderConvo(nil) end
      WH.UIRefresh()
    end
  end,
}

---------------------------------------------------------------------------
-- on-screen message icon (appears on new whisper, shows unread count, click = open)
---------------------------------------------------------------------------
function WH.UpdateIcon()
  local n = WH.UnreadTotal()
  local btn = WhisperHubButton
  if btn then
    if WH.Get("button") == 1 then btn:Show() else btn:Hide() end
    btn.count:SetText(n > 0 and n or "")
  end
  local b = WhisperHubIcon
  if not b then return end
  local mode = WH.Get("icon")
  if n > 0 then b.count:SetText(n) else b.count:SetText("") end
  if mode == 0 then
    b:Hide()
  elseif n > 0 or mode == 2 then
    b:Show()
  else
    b:Hide()
    b:SetScript("OnUpdate", nil)
  end
  if n == 0 then b:SetScript("OnUpdate", nil); b.tex:SetAlpha(1) end
end

-- short pulse so the icon is noticed; OnUpdate exists only while pulsing, then it is removed
function WH.IconAlert()
  local b = WhisperHubIcon
  if not b or WH.Get("icon") == 0 or WH.UnreadTotal() == 0 then return end
  b:Show()
  b.t0 = GetTime()
  b:SetScript("OnUpdate", function()
    local t = GetTime() - this.t0
    if t > 4 then this:SetScript("OnUpdate", nil); this.tex:SetAlpha(1); return end
    this.tex:SetAlpha(0.55 + 0.45 * math.abs(math.sin(t * 6)))
  end)
end

local function CreateIcon()
  local b = CreateFrame("Button", "WhisperHubIcon", UIParent)
  b:SetWidth(36); b:SetHeight(36)
  b:SetFrameStrata("FULLSCREEN_DIALOG")
  b:SetMovable(true); b:SetClampedToScreen(true)
  b:RegisterForDrag("LeftButton")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b.tex = b:CreateTexture(nil, "ARTWORK")
  b.tex:SetAllPoints(b)
  b.tex:SetTexture("Interface\\Icons\\INV_Letter_15")
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 2, -2)
  b.count:SetTextColor(1, .2, .2)
  RestorePos(b, "iconpos", "TOP", 0, -140)
  b:SetScript("OnDragStart", function() this.dragging = true; this:StartMoving() end)
  b:SetScript("OnDragStop", function() this:StopMovingOrSizing(); this.dragging = false; this.dragTime = GetTime(); WH.SavePos(this, "iconpos") end)
  b:SetScript("OnClick", function()
    if this.dragging or (this.dragTime and GetTime() - this.dragTime < 0.25) then return end
    if arg1 == "RightButton" then WH.Set("icon", 0); this:Hide(); return end
    if WhisperHubFrame:IsVisible() then
      WhisperHubFrame:Hide()
    else
      WH.ShowFrame()
      -- jump to the most recent conversation with unread messages
      local k = WH.lastUnread
      if k and WH.convos[k] and WH.convos[k].unread > 0 then WH.Select(k) end
    end
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("WhisperHub")
    GameTooltip:AddLine("Unread: " .. WH.UnreadTotal(), 1, 1, 1)
    GameTooltip:AddLine("Click: open  |  Drag: move  |  Right-click: hide icon", .6, .6, .6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:Hide()
end

---------------------------------------------------------------------------
-- permanent button: looks like a minimap button but is NOT attached to the minimap - drag it anywhere
---------------------------------------------------------------------------
local function CreateButton()
  local b = CreateFrame("Button", "WhisperHubButton", UIParent)
  b:SetWidth(32); b:SetHeight(32)
  b:SetFrameStrata("FULLSCREEN_DIALOG")   -- above pfUI minimap and other HUD frames
  b:SetFrameLevel(50)
  b:SetMovable(true); b:SetClampedToScreen(true)
  b:RegisterForDrag("LeftButton")
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  local icon = b:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\INV_Letter_15")
  icon:SetWidth(20); icon:SetHeight(20)
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -5)
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetWidth(52); border:SetHeight(52)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 3, -2)
  b.count:SetTextColor(1, .2, .2)
  RestorePos(b, "btnpos", "CENTER", 0, 120)
  b:SetScript("OnDragStart", function() this.dragging = true; this:StartMoving() end)
  b:SetScript("OnDragStop", function() this:StopMovingOrSizing(); this.dragging = false; this.dragTime = GetTime(); WH.SavePos(this, "btnpos") end)
  b:SetScript("OnClick", function()
    if this.dragging or (this.dragTime and GetTime() - this.dragTime < 0.25) then return end
    if arg1 == "RightButton" then WH.ToggleOptions(); return end
    if WhisperHubFrame:IsVisible() then
      WhisperHubFrame:Hide()
    else
      WH.ShowFrame()
      local k = WH.lastUnread
      if k and WH.convos[k] and WH.convos[k].unread > 0 then WH.Select(k) end
    end
  end)
  b:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_LEFT")
    GameTooltip:AddLine("WhisperHub")
    GameTooltip:AddLine("Unread: " .. WH.UnreadTotal(), 1, 1, 1)
    GameTooltip:AddLine("Click: open/close  |  Right-click: settings  |  Drag: move", .6, .6, .6)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

---------------------------------------------------------------------------
-- shift-click links into our edit box (same proxy idea as WIM; do not run both addons)
---------------------------------------------------------------------------
local function InstallLinkProxy()
  local box = ChatFrameEditBox
  local oVis, oShown, oInsert, oShow = box.IsVisible, box.IsShown, box.Insert, box.Show
  local lastIns = -1
  box.IsVisible = function(self) if ui.focus and IsShiftKeyDown() then return 1 end return oVis(self) end
  box.IsShown   = function(self) if ui.focus and IsShiftKeyDown() then return 1 end return oShown(self) end
  box.Show      = function(self) if ui.focus and IsShiftKeyDown() then return end return oShow(self) end
  box.Insert = function(self, text)
    if ui.focus then
      local t = GetTime()
      if t - lastIns > 0.02 then lastIns = t; ui.focus:Insert(text) end
      return
    end
    oInsert(self, text)
  end
end

---------------------------------------------------------------------------
-- quick settings panel + position reset
---------------------------------------------------------------------------
local OPTIONS = {
  { "suppress",   "Hide whispers from normal chat" },
  { "sound",      "Sound on incoming whisper" },
  { "autoopen",   "Open window on incoming whisper" },
  { "deferopen",  "In combat: open window after combat" },
  { "hidecombat", "Hide window during combat" },
  { "takeover",   "Intercept /w, /r and Whisper buttons" },
  { "who",        "Look up guild/zone (background /who)" },
  { "button",     "Show floating button" },
  { "icon",       "Popup icon on new whisper" },
}
local KEEP = { 0, 30, 90, 365 }

local function KeepText()
  local v = WH.Get("keepdays")
  if not v or v == 0 then return "History: keep forever" end
  return "History: keep " .. v .. " days"
end

function WH.ResetPositions()
  WhisperHubDB.pos, WhisperHubDB.iconpos, WhisperHubDB.btnpos = nil, nil, nil
  RestorePos(WhisperHubFrame, "pos", "CENTER", 0, 0)
  if WhisperHubIcon then RestorePos(WhisperHubIcon, "iconpos", "TOP", 0, -140) end
  if WhisperHubButton then RestorePos(WhisperHubButton, "btnpos", "CENTER", 0, 120) end
  WH.Print("window, popup icon and button moved back to the screen centre area")
end

local function CreateOptions()
  local o = CreateFrame("Frame", "WhisperHubOptions", UIParent)
  ui.opts = o
  o:SetWidth(330); o:SetHeight(46 + getn(OPTIONS) * 26 + 84)
  o:SetFrameStrata("FULLSCREEN_DIALOG")
  o:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  o:SetMovable(true); o:EnableMouse(true); o:SetClampedToScreen(true)
  o:SetBackdrop(BACKDROP); o:SetBackdropColor(0, 0, 0, .92)
  o:RegisterForDrag("LeftButton")
  o:SetScript("OnDragStart", function() this:StartMoving() end)
  o:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  tinsert(UISpecialFrames, "WhisperHubOptions")
  o:Hide()

  local t = o:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  t:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -14)
  t:SetText("WhisperHub - quick settings")
  local x = CreateFrame("Button", nil, o, "UIPanelCloseButton")
  x:SetPoint("TOPRIGHT", o, "TOPRIGHT", -3, -3)
  x:SetScript("OnClick", function() WhisperHubOptions:Hide() end)

  o.checks = {}
  for i = 1, getn(OPTIONS) do
    local name = "WhisperHubOpt" .. i
    local cb = CreateFrame("CheckButton", name, o, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", o, "TOPLEFT", 14, -36 - (i - 1) * 26)
    getglobal(name .. "Text"):SetText(OPTIONS[i][2])
    cb.key = OPTIONS[i][1]
    cb:SetScript("OnClick", function()
      WH.Set(this.key, this:GetChecked() and 1 or 0)
      WH.UpdateIcon()
    end)
    o.checks[i] = cb
  end

  local y = 46 + getn(OPTIONS) * 26
  local keep = CreateFrame("Button", "WhisperHubOptKeep", o, "UIPanelButtonTemplate")
  keep:SetWidth(180); keep:SetHeight(22)
  keep:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -y)
  keep:SetScript("OnClick", function()
    local cur, idx = WH.Get("keepdays") or 0, 1
    for i = 1, getn(KEEP) do if KEEP[i] == cur then idx = i end end
    WH.Set("keepdays", KEEP[math.mod(idx, getn(KEEP)) + 1])
    this:SetText(KeepText())
  end)
  keep:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Click to cycle: forever / 30 / 90 / 365 days")
    GameTooltip:AddLine("Older messages are deleted at login.", .7, .7, .7)
    GameTooltip:Show()
  end)
  keep:SetScript("OnLeave", function() GameTooltip:Hide() end)
  o.keep = keep

  local reset = CreateFrame("Button", "WhisperHubOptReset", o, "UIPanelButtonTemplate")
  reset:SetWidth(180); reset:SetHeight(22)
  reset:SetPoint("TOPLEFT", o, "TOPLEFT", 16, -(y + 28))
  reset:SetText("Reset window/button positions")
  reset:SetScript("OnClick", function() WH.ResetPositions() end)

  o:SetScript("OnShow", function()
    for i = 1, getn(this.checks) do
      local cb = this.checks[i]
      local v = WH.Get(cb.key)
      cb:SetChecked(v ~= 0 and v ~= nil and 1 or nil)
    end
    this.keep:SetText(KeepText())
  end)
  if WH.ApplySkin2 then pcall(WH.ApplySkin2) end
end

function WH.ToggleOptions()
  if not ui.opts then
    local ok, err = pcall(CreateOptions)
    if not ok then WH.Print("settings panel error: " .. tostring(err)); return end
  end
  if ui.opts:IsVisible() then ui.opts:Hide() else ui.opts:Show() end
end

---------------------------------------------------------------------------
-- construction
---------------------------------------------------------------------------
function WH.CreateUI()
  WhisperHubDB = WhisperHubDB or {}
  local f = CreateFrame("Frame", "WhisperHubFrame", UIParent)
  ui.frame = f
  f:SetWidth(680); f:SetHeight(380)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:EnableMouse(true); f:SetClampedToScreen(true)
  f:SetBackdrop(BACKDROP); f:SetBackdropColor(0, 0, 0, .85)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function() this:StartMoving() end)
  f:SetScript("OnDragStop", function() this:StopMovingOrSizing(); WH.SavePos(this, "pos") end)
  RestorePos(f, "pos", "CENTER", 0, 0)
  tinsert(UISpecialFrames, "WhisperHubFrame")
  f:Hide()

  ui.close = CreateFrame("Button", "WhisperHubClose", f, "UIPanelCloseButton")
  ui.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -3, -3)
  ui.close:SetScript("OnClick", function() WhisperHubFrame:Hide() end)

  ui.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  ui.title:SetPoint("TOPLEFT", f, "TOPLEFT", 172, -12)
  ui.title:SetJustifyH("LEFT")
  ui.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ui.sub:SetPoint("TOPLEFT", f, "TOPLEFT", 172, -29)
  ui.sub:SetWidth(400)
  ui.sub:SetJustifyH("LEFT")

  -- settings: small gear, far away from the character info text
  ui.optBtn = CreateFrame("Button", "WhisperHubSettings", f)
  ui.optBtn:SetWidth(18); ui.optBtn:SetHeight(18)
  ui.optBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -10)
  ui.optBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Gear_01")
  ui.optBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  ui.optBtn:SetScript("OnClick", function() WH.ToggleOptions() end)
  ui.optBtn:SetScript("OnEnter", function() GameTooltip:SetOwner(this, "ANCHOR_LEFT"); GameTooltip:AddLine("Settings"); GameTooltip:Show() end)
  ui.optBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- thin separators instead of heavy borders
  local sep1 = f:CreateTexture(nil, "ARTWORK")
  sep1:SetTexture(1, 1, 1, .12)
  sep1:SetWidth(1)
  sep1:SetPoint("TOPLEFT", f, "TOPLEFT", 160, -12)
  sep1:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 160, 12)
  local sep2 = f:CreateTexture(nil, "ARTWORK")
  sep2:SetTexture(1, 1, 1, .12)
  sep2:SetHeight(1)
  sep2:SetPoint("TOPLEFT", f, "TOPLEFT", 172, -46)
  sep2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -46)

  -- contact list (left)
  for i = 1, NUM_ROWS do
    local b = CreateFrame("Button", "WhisperHubRow" .. i, f)
    b:SetWidth(142); b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -14 - (i - 1) * ROW_H)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:EnableMouseWheel(true)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 4, 0); b.text:SetWidth(108); b.text:SetJustifyH("LEFT")
    b.badge = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.badge:SetPoint("RIGHT", b, "RIGHT", -4, 0)
    b.sel = b:CreateTexture(nil, "BACKGROUND")
    b.sel:SetAllPoints(b); b.sel:SetTexture(1, 1, 1, .15); b.sel:Hide()
    b:SetScript("OnClick", function()
      if not this.key then return end
      if arg1 == "RightButton" then WH.CloseTab(this.key) else WH.Select(this.key) end
    end)
    b:SetScript("OnMouseWheel", function() ui.offset = ui.offset - arg1; WH.RefreshList() end)
    b:SetScript("OnEnter", function()
      local c = this.key and WH.convos[this.key]
      if not c then return end
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine(c.name, 1, 1, 1)
      local info = WH.InfoLine(c.name)
      if info ~= "" then GameTooltip:AddLine(info) end
      if c.last > 0 then GameTooltip:AddLine("Last message: " .. date("%d.%m.%Y %H:%M", c.last), .6, .6, .6) end
      GameTooltip:AddLine("Right-click: close tab", .5, .5, .5)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ui.rows[i] = b
  end

  -- action rail (right side), like WIM's shortcut bar
  -- every button action runs protected: a missing API on this client prints a readable error instead of failing silently
  local function Act(fn)
    return function()
      local c = ui.cur and WH.convos[ui.cur]
      if not c then return end
      local ok, err = pcall(fn, c.name, c)
      if not ok then WH.Print("action failed: " .. tostring(err)) end
    end
  end
  -- 1.12 clients use GuildInviteByName(name); GuildInvite(name) does not exist here (that was the nil call)
  local function GuildInviteName(n)
    if GuildInviteByName then GuildInviteByName(n)
    elseif GuildInvite then GuildInvite(n)
    elseif SlashCmdList and SlashCmdList["GUILD_INVITE"] then SlashCmdList["GUILD_INVITE"](n)
    else error("no guild invite function found on this client") end
  end
  local actions = {
    { "invite",  "Invite",  "Invite to group",              Act(function(n) InviteByName(n) end) },
    { "target",  "Target",  "Target (must be nearby)",      Act(function(n)
        TargetByName(n, true)
        if string.lower(UnitName("target") or "") ~= string.lower(n) then WH.Print(n .. " is not nearby") end
      end) },
    { "friend",  "Friend",  "Add to friends list",          Act(function(n) AddFriend(n) end) },
    { "ignore",  "Ignore",  "Toggle ignore",                Act(function(n) AddOrDelIgnore(n) end) },
    { "ginvite", "Guild",   "Invite to guild",              Act(function(n)
        if IsInGuild and not IsInGuild() then WH.Print("You are not in a guild"); return end
        GuildInviteName(n)
      end) },
    { "who",     "Refresh", "Look up guild/zone/level now", Act(function(n) WH.QueueWho(n, true) end) },
    { "pin",     "Pin",     "Keep this tab on top",         Act(function(n, c) WH.TogglePin(c); WH.RefreshList(); WH.UpdateRail() end) },
    { "close",   "Close",   "Close tab (history is kept)",  Act(function(n, c) WH.CloseTab(c.key) end) },
    { "delete",  "Delete",  "Delete saved history",         Act(function(n, c) WH.deleteKey = c.key; StaticPopup_Show("WHISPERHUB_DELETE", c.name) end) },
  }
  for i = 1, getn(actions) do
    local a = actions[i]
    local b = CreateFrame("Button", "WhisperHubRail" .. i, f, "UIPanelButtonTemplate")
    b:SetWidth(84); b:SetHeight(20)
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -52 - (i - 1) * 23 - (i > 7 and 12 or 0))
    b:SetText(a[2])
    b.tip = a[3]
    b:SetScript("OnClick", a[4])
    b:SetScript("OnEnter", function() GameTooltip:SetOwner(this, "ANCHOR_LEFT"); GameTooltip:AddLine(this.tip); GameTooltip:Show() end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tinsert(ui.rail, b)
    ui.rail[a[1]] = b
  end
  pcall(function() ui.rail.delete:GetFontString():SetTextColor(1, .45, .45) end)
  f:RegisterEvent("IGNORELIST_UPDATE")
  f:RegisterEvent("FRIENDLIST_UPDATE")
  f:SetScript("OnEvent", function() if this:IsVisible() then WH.UpdateRail() end end)

  -- message view
  local m = CreateFrame("ScrollingMessageFrame", "WhisperHubMessages", f)
  ui.msg = m
  m:SetPoint("TOPLEFT", f, "TOPLEFT", 172, -52)
  m:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -108, 44)
  m:SetFontObject(ChatFontNormal)
  m:SetJustifyH("LEFT")
  m:SetFading(false)
  m:SetMaxLines(WH.MAXLINES + 50)
  m:EnableMouse(true)
  m:EnableMouseWheel(true)
  m:SetScript("OnMouseWheel", function()
    if arg1 > 0 then
      if IsShiftKeyDown() then this:ScrollToTop() else this:ScrollUp() end
    else
      if IsShiftKeyDown() then this:ScrollToBottom() else this:ScrollDown() end
    end
  end)
  m:SetScript("OnHyperlinkClick", function() SetItemRef(arg1, arg2, arg3) end)

  -- edit box
  local e = CreateFrame("EditBox", "WhisperHubEdit", f)
  ui.edit = e
  e:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 172, 12)
  e:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -108, 12)
  e:SetHeight(24)
  e:SetFontObject(ChatFontNormal)
  e:SetAutoFocus(false)
  e:SetMaxLetters(255)
  e:SetTextInsets(6, 6, 0, 0)
  e:SetBackdrop(BACKDROP); e:SetBackdropColor(0, 0, 0, .6)
  e:SetScript("OnEnterPressed", function()
    local text = this:GetText()
    if text ~= "" and ui.cur and WH.convos[ui.cur] then
      WH.Send(WH.convos[ui.cur].name, text)
      this:SetText("")
    end
  end)
  e:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  e:SetScript("OnTabPressed", function() WH.NextUnread() end)
  e:SetScript("OnEditFocusGained", function() ui.focus = this end)
  e:SetScript("OnEditFocusLost", function() ui.focus = nil end)

  f:SetScript("OnShow", function() WH.UpdateIcon() end)
  f:SetScript("OnHide", function() ui.edit:ClearFocus() end)

  -- optional parts: a failure here must never take the main window down
  local ok, err = pcall(InstallLinkProxy)
  if not ok then WH.Print("link proxy disabled: " .. tostring(err)) end
  ok, err = pcall(CreateIcon)
  if not ok then WH.Print("icon error: " .. tostring(err)) end
  ok, err = pcall(CreateButton)
  if not ok then WH.Print("button error: " .. tostring(err)) end
  if WH.ApplySkin then pcall(WH.ApplySkin) end
end
