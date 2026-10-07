-- WhisperHub / Skin.lua : optional pfUI look. Every call is guarded: if the pfUI API differs
-- in your fork, WhisperHub simply keeps its default Blizzard-style look.
function WH.ApplySkin()
  if not (pfUI and pfUI.api) then return end
  local api, ui = pfUI.api, WH.ui
  local function try(fn, a, b, c, d) if fn then pcall(fn, a, b, c, d) end end

  if api.CreateBackdrop then
    ui.frame:SetBackdrop(nil)
    try(api.CreateBackdrop, ui.frame, nil, nil, .85)
    ui.edit:SetBackdrop(nil)
    try(api.CreateBackdrop, ui.edit, nil, nil, .75)
  end
  try(api.CreateBackdropShadow, ui.frame)
  for i = 1, table.getn(ui.rail) do try(api.SkinButton, ui.rail[i]) end
  try(api.SkinCloseButton, ui.close, ui.frame, -6, -6)

  if pfUI.font_default then
    pcall(function()
      ui.msg:SetFont(pfUI.font_default, 12, "OUTLINE")
      ui.edit:SetFont(pfUI.font_default, 12, "OUTLINE")
    end)
  end
end

-- the settings panel is created lazily, so it is skinned when it first appears
function WH.ApplySkin2()
  if not (pfUI and pfUI.api) then return end
  local api, o = pfUI.api, WH.ui.opts
  if not o then return end
  if api.CreateBackdrop then
    o:SetBackdrop(nil)
    pcall(api.CreateBackdrop, o, nil, nil, .9)
  end
  if api.SkinButton then
    pcall(api.SkinButton, o.keep)
    pcall(api.SkinButton, WhisperHubOptReset)
  end
  if api.SkinCheckbox then
    for i = 1, table.getn(o.checks) do pcall(api.SkinCheckbox, o.checks[i]) end
  end
end
