-- CombatIndicator: tells you the moment you drop out of combat, and for rogues
-- (and druids in cat form) whether Stealth / Prowl is ready to re-stealth.
--
-- Shown as one icon with a number on it and a small label under it:
--   In combat ............ swords icon, red "Combat" (optional, /ci combat)
--   In PvP combat ........ swords icon, orange countdown to the expected combat
--                          drop; glows in the last 2 s. Restarts on every
--                          hostile player action to or from you (combat log).
--   Left combat .......... sound + Stealth icon glowing green "Stealth!" (or
--                          grey with a cooldown swipe while it's on cooldown)
--   Stealthed / timeout .. hides

local ADDON = ...

local SHOW_AFTER_READY = 4   -- seconds the "STEALTH!" message stays up
local SHOW_NO_STEALTH  = 3   -- seconds "OUT OF COMBAT" stays for other classes
local DEFAULTS = { point = "CENTER", x = 0, y = 120, locked = false, scale = 1, sound = true, showCombat = false,
  pvpTimer = 6,   -- seconds without PvP actions before the game drops you from combat
  showAt = 4 }    -- the PvP countdown only appears once this few seconds are left

-- Stealth (rogue) and Prowl (druid), all ranks; the highest known rank is used.
local STEALTH_IDS = { 1787, 1786, 1785, 1784, 9913, 6783, 5215 }

local function Secret(v) return issecretvalue and issecretvalue(v) end

local Glow = LibStub("LibCustomGlow-1.0-foreverauras")

local ICON_SIZE = 44
local ICON_COMBAT  = "Interface\\Icons\\Ability_DualWield"
local ICON_STEALTH = "Interface\\Icons\\Ability_Stealth"
local ICON_SAFE    = "Interface\\RaidFrame\\ReadyCheck-Ready"

local db
-- Layout: one icon, a number on it (countdowns), a small label under it.
local frame = CreateFrame("Frame", "CombatIndicatorFrame", UIParent)
frame:SetSize(ICON_SIZE, ICON_SIZE)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")

local border = frame:CreateTexture(nil, "BACKGROUND")
border:SetPoint("TOPLEFT", -1, 1)
border:SetPoint("BOTTOMRIGHT", 1, -1)
border:SetColorTexture(0, 0, 0, 1)

local icon = frame:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()

-- Cooldown swipe for Stealth (its own numbers hidden; we draw ours).
local cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
cooldown:SetAllPoints()
cooldown:SetDrawEdge(false)
if cooldown.SetHideCountdownNumbers then cooldown:SetHideCountdownNumbers(true) end

local overlay = CreateFrame("Frame", nil, frame)
overlay:SetAllPoints()
overlay:SetFrameLevel(cooldown:GetFrameLevel() + 2)

local number = overlay:CreateFontString(nil, "OVERLAY")
number:SetFont(STANDARD_TEXT_FONT, 17, "OUTLINE")
number:SetPoint("CENTER")

local label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetPoint("TOP", frame, "BOTTOM", 0, -3)

local glowOn
local function SetGlow(color)
  if glowOn == color then return end
  if glowOn then Glow.ButtonGlow_Stop(frame) end
  glowOn = color
  if color then Glow.ButtonGlow_Start(frame, color, 0.25) end
end

-- state: "combat", "left" (just left combat), "idle"
local state, leftAt, readyAt = "idle", 0, nil
-- Last hostile action between you and an enemy player (nil = not PvP combat).
local lastPvP = nil
-- Hostile NPCs fighting you: GUID -> time of last action with it. While any
-- is in here, combat won't drop on a timer, so the countdown is hidden. An NPC
-- leaves when it dies, or after NPC_FORGET seconds with no action (it reset,
-- or you got away).
local NPC_FORGET = 10
local npcs = {}

local function NpcInvolved()
  local now = GetTime()
  for guid, t in pairs(npcs) do
    if now - t > NPC_FORGET then npcs[guid] = nil end
  end
  return next(npcs) ~= nil
end

local function KnownStealthSpell()
  for _, id in ipairs(STEALTH_IDS) do
    if IsPlayerSpell(id) then return id end
  end
end

-- Stealth cooldown: remaining seconds (0 = ready) plus start/duration for the
-- swipe; nil if you don't know Stealth/Prowl.
local function StealthCooldown()
  local id = KnownStealthSpell()
  if not id then return nil end
  local start, duration
  if C_Spell and C_Spell.GetSpellCooldown then
    local info = C_Spell.GetSpellCooldown(id)
    if info then start, duration = info.startTime, info.duration end
  else
    start, duration = GetSpellCooldown(id)
  end
  if not start or Secret(start) or Secret(duration) then return 0 end
  -- Ignore the global cooldown.
  if duration <= 1.5 or start == 0 then return 0 end
  return math.max(0, start + duration - GetTime()), start, duration
end

local function StealthIcon()
  local id = KnownStealthSpell()
  local tex = id and ((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
    or (GetSpellTexture and GetSpellTexture(id)))
  if tex and not Secret(tex) then return tex end
  return ICON_STEALTH
end

-- r, g, b, alpha (alpha is used by the glow)
local RED    = { 1, 0.25, 0.25, 1 }
local ORANGE = { 1, 0.55, 0.1, 1 }
local YELLOW = { 1, 0.82, 0, 1 }
local GREEN  = { 0.2, 1, 0.2, 1 }
local GREY   = { 0.7, 0.7, 0.7, 1 }

-- One call sets the whole display.
--   tex: icon texture   txt/color: small label   num: number on the icon
--   desat: grey icon     glow: glow color or nil
local function Show(tex, txt, color, num, desat, glow)
  icon:SetTexture(tex)
  if tex == ICON_SAFE then icon:SetTexCoord(0, 1, 0, 1) else icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  icon:SetDesaturated(desat and true or false)
  label:SetText(txt or "")
  label:SetTextColor(color[1], color[2], color[3])
  number:SetText(num or "")
  number:SetTextColor(color[1], color[2], color[3])
  SetGlow(glow)
  frame:Show()
end

local function HideAll()
  SetGlow(nil)
  cooldown:Clear()
  frame:Hide()
end

local function Unlocked() return db and not db.locked end

local function Refresh()
  if state ~= "left" then cooldown:Clear() end

  if state == "combat" then
    -- PvP only: count down to the expected combat drop.
    -- Hidden while you're still trading hits; it only shows up once nobody
    -- has hit anybody for a while (db.showAt seconds or less to go).
    local left = lastPvP and not NpcInvolved() and db.pvpTimer - (GetTime() - lastPvP)
    if left and left <= db.showAt then
      if left > 0 then
        -- Last 2 seconds: glow so you can get ready to stealth.
        Show(ICON_COMBAT, "Drop", ORANGE, ("%.1f"):format(left), false, left <= 2 and ORANGE or nil)
      else
        Show(ICON_COMBAT, "Dropping", YELLOW, "...", false, YELLOW)
      end
      return
    end
    if db.showCombat then
      Show(ICON_COMBAT, "Combat", RED)
    elseif Unlocked() then
      Show(StealthIcon(), "Drag me", GREY, nil, true)
    else
      HideAll()
    end
    return
  end

  if state == "left" then
    if IsStealthed() then state = "idle"; return Refresh() end
    local cd, start, duration = StealthCooldown()
    if cd == nil then
      -- No stealth spell (other class or druid out of cat form).
      Show(ICON_SAFE, "Out of combat", GREEN)
      if GetTime() - leftAt > SHOW_NO_STEALTH then state = "idle"; return Refresh() end
    elseif cd > 0 then
      if start then cooldown:SetCooldown(start, duration) end
      Show(StealthIcon(), "Stealth", YELLOW, ("%.1f"):format(cd), true)
    else
      cooldown:Clear()
      readyAt = readyAt or GetTime()
      Show(StealthIcon(), "Stealth!", GREEN, nil, false, GREEN)
      if GetTime() - readyAt > SHOW_AFTER_READY then state = "idle"; return Refresh() end
    end
    return
  end

  -- idle
  if Unlocked() then
    Show(StealthIcon(), "Drag me", GREY, nil, true)
  else
    HideAll()
  end
end

local function ApplyLock()
  frame:EnableMouse(not db.locked)
  Refresh()
end

local function ApplyLayout()
  frame:ClearAllPoints()
  frame:SetPoint(db.point, UIParent, db.point, db.x, db.y)
  frame:SetScale(db.scale)
end

frame:SetScript("OnDragStart", function(self) if Unlocked() then self:StartMoving() end end)
frame:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, _, x, y = self:GetPoint()
  db.point, db.x, db.y = point, x, y
end)

local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + dt
  if elapsed < 0.1 then return end
  elapsed = 0
  if state == "left" or (state == "combat" and lastPvP) then Refresh() end
end)

-- Combat log: which hostile actions keep you in combat.
local band = bit.band
local CONTROL_PLAYER = COMBATLOG_OBJECT_CONTROL_PLAYER or 0x100   -- players and their pets
local REACTION_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local AFFILIATION_MINE = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1  -- you or your pet

local HOSTILE_EVENT = {
  SWING_DAMAGE = true, SWING_MISSED = true,
  RANGE_DAMAGE = true, RANGE_MISSED = true,
  SPELL_DAMAGE = true, SPELL_MISSED = true,
  SPELL_PERIODIC_DAMAGE = true, SPELL_PERIODIC_MISSED = true,
  SPELL_AURA_APPLIED = true, SPELL_AURA_REFRESH = true, -- debuffs only (checked below)
  SPELL_INTERRUPT = true, SPELL_DISPEL = true, SPELL_STOLEN = true,
}

local DEATH_EVENT = { UNIT_DIED = true, UNIT_DESTROYED = true, PARTY_KILL = true }

-- Debug / stats for the current fight (/ci debug).
local stats = { log = 0, logSecret = 0, logUsed = 0, fallback = 0 }
local lastDebug = {}
-- Lines are also kept in CombatIndicatorDB.log (last 400), written to
-- WTF\Account\<name>\SavedVariables\CombatIndicator.lua on /reload or logout.
local MAX_LOG = 400
local function Debug(msg)
  if not (db and db.debug) then return end
  local now = GetTime()
  if lastDebug[msg] and now - lastDebug[msg] < 0.5 then return end
  lastDebug[msg] = now
  print("|cff33ff99CI debug|r: " .. msg)
  local _, instanceType = IsInInstance()
  db.log = db.log or {}
  table.insert(db.log, ("%s %.1f [%s] %s"):format(date("%H:%M:%S"), now, instanceType or "?", msg))
  while #db.log > MAX_LOG do table.remove(db.log, 1) end
end

-- Fallback for when the combat log is blocked. On Forever, addon restrictions
-- are active during a PvP match (battlegrounds, arenas), so the log gives us
-- nothing there. Unit events still fire, so we use those instead:
--   UNIT_COMBAT on you ............ you got hit (damage, miss, DoT tick)
--   UNIT_COMBAT on your target .... while you auto-attack an enemy player
--   harmful spell cast ............ on an enemy player target
-- It can't tell players from mobs, so in a battleground every hit counts as PvP.
local autoAttacking, logUsable = false, false
local function InPvPInstance()
  local _, instanceType = IsInInstance()
  return instanceType == "pvp" or instanceType == "arena"
end
local function UseFallback() return InPvPInstance() or not logUsable end
local function MarkFallback(why)
  lastPvP = GetTime()
  stats.fallback = stats.fallback + 1
  Debug("timer reset: " .. why)
end

local function OnCombatLog()
  stats.log = stats.log + 1
  local _, sub, _, srcGUID, _, srcFlags, _, dstGUID, _, dstFlags, _, _, _, _, auraType =
    CombatLogGetCurrentEventInfo()
  if Secret(sub) or Secret(srcFlags) or Secret(dstFlags) then
    stats.logSecret = stats.logSecret + 1
    return
  end
  if DEATH_EVENT[sub] then
    if dstGUID and not Secret(dstGUID) then npcs[dstGUID] = nil end
    return
  end
  if not HOSTILE_EVENT[sub] then return end
  if Secret(srcFlags) or Secret(dstFlags) or not srcFlags or not dstFlags then return end
  if (sub == "SPELL_AURA_APPLIED" or sub == "SPELL_AURA_REFRESH") and auraType ~= "DEBUFF" then return end

  local fromMe = band(srcFlags, AFFILIATION_MINE) > 0
  local toMe   = band(dstFlags, AFFILIATION_MINE) > 0
  if fromMe == toMe then return end           -- not involving you (or self-damage)
  logUsable = true

  -- Works both ways: your own attacks on an enemy player restart the timer too.
  local other = toMe and srcFlags or dstFlags
  if band(other, REACTION_HOSTILE) == 0 then return end
  stats.logUsed = stats.logUsed + 1
  if band(other, CONTROL_PLAYER) > 0 then
    lastPvP = GetTime()
    Debug("timer reset: combat log " .. sub)
  else
    -- A mob is in the fight: no timer until it dies or is forgotten.
    local guid = toMe and srcGUID or dstGUID
    if Secret(guid) or not guid then guid = "?" end
    npcs[guid] = GetTime()
  end
end

local function PlayAlert()
  if not db.sound then return end
  local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
  PlaySound(kit, "Master")
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entered combat
events:RegisterEvent("PLAYER_REGEN_ENABLED")   -- left combat
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_STEALTH")
events:RegisterEvent("PLAYER_ENTER_COMBAT")   -- auto-attack on
events:RegisterEvent("PLAYER_LEAVE_COMBAT")   -- auto-attack off
events:RegisterUnitEvent("UNIT_COMBAT", "player", "target")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_HEALTH", "player")

local function IsHarmful(spellID)
  local ok, harmful
  if C_Spell and C_Spell.IsSpellHarmful then
    ok, harmful = pcall(C_Spell.IsSpellHarmful, spellID)
  elseif IsHarmfulSpell and GetSpellInfo then
    ok, harmful = pcall(IsHarmfulSpell, GetSpellInfo(spellID))
  end
  return ok and not Secret(harmful) and harmful and true or false
end

local function EnemyPlayerTarget()
  return UnitExists("target") and UnitCanAttack("player", "target") and UnitIsPlayer("target")
end

-- Your health, to tell a hit from a heal when the hit type is hidden.
-- nil when the client hides your health too.
local function ReadHealth()
  local ok, h = pcall(UnitHealth, "player")
  if ok and h and not Secret(h) then return h end
end
local lastHealth = ReadHealth()
local reportedSecrets = false

local function OnUnitEvent(event, unit, arg2, arg3)
  if event == "UNIT_HEALTH" then
    -- Health went down = you got hit (works even when UNIT_COMBAT hides its type).
    local h = ReadHealth()
    if h and lastHealth and h < lastHealth and UseFallback() then
      MarkFallback("you lost health")
    end
    lastHealth = h
    return
  end
  if not UseFallback() then return end
  if event == "UNIT_COMBAT" then
    -- arg2 = action: WOUND, DODGE, PARRY, MISS, BLOCK, HEAL, ENERGIZE, ...
    local actionHidden = Secret(arg2) or arg2 == nil
    if not reportedSecrets and unit == "player" then
      reportedSecrets = true
      Debug(("hit type hidden: %s, health hidden: %s"):format(tostring(actionHidden), tostring(ReadHealth() == nil)))
    end
    if not actionHidden and (arg2 == "HEAL" or arg2 == "ENERGIZE") then return end
    if unit == "player" then
      if not actionHidden then
        MarkFallback("you were hit (" .. arg2 .. ")")
      elseif not ReadHealth() then
        -- Type and health both hidden: can't tell hits from heals, count it.
        MarkFallback("you were hit or healed (can't tell)")
      end
      -- else: type hidden but health visible -> UNIT_HEALTH decides.
    elseif unit == "target" and autoAttacking and EnemyPlayerTarget() then
      MarkFallback("your auto-attack")
    end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    -- arg3 = spellID. Only harmful spells: Sprint/Evasion/Vanish don't count.
    if arg3 and not Secret(arg3) and IsHarmful(arg3) and EnemyPlayerTarget() then
      MarkFallback("your spell")
    end
  end
end
-- Guarded: if this client ever blocks the combat log for addons, the rest still works.
local hasCombatLog = CombatLogGetCurrentEventInfo
  and pcall(events.RegisterEvent, events, "COMBAT_LOG_EVENT_UNFILTERED")
events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
  if event == "COMBAT_LOG_EVENT_UNFILTERED" then
    -- pcall: if reading the log is blocked it may error; count it and move on.
    if db and not pcall(OnCombatLog) then
      stats.logSecret = stats.logSecret + 1
      Debug("combat log read failed (blocked)")
    end
    return
  end
  if event == "UNIT_COMBAT" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_HEALTH" then
    -- pcall: hidden (secret) values must never turn into an error flood.
    if db then
      local ok, err = pcall(OnUnitEvent, event, arg1, arg2, arg3)
      if not ok then Debug("error: " .. tostring(err)) end
    end
    return
  end
  if event == "PLAYER_ENTER_COMBAT" then autoAttacking = true; return end
  if event == "PLAYER_LEAVE_COMBAT" then autoAttacking = false; return end
  if event == "ADDON_LOADED" then
    if arg1 ~= ADDON then return end
    CombatIndicatorDB = CombatIndicatorDB or {}
    db = CombatIndicatorDB
    for k, v in pairs(DEFAULTS) do if db[k] == nil then db[k] = v end end
    -- v2: the plain "Combat" icon is now off by default.
    if (db.version or 1) < 2 then db.showCombat = false; db.version = 2 end
    ApplyLayout()
    self:UnregisterEvent("ADDON_LOADED")
    ApplyLock()
    return
  end
  if not db then return end

  if event == "PLAYER_REGEN_DISABLED" then
    state = "combat"
    -- Keep a PvP hit that arrived in the same moment; forget older fights.
    if lastPvP and GetTime() - lastPvP > 1 then lastPvP = nil end
    Debug(("combat start - pvp instance: %s, combat log usable: %s"):format(
      tostring(InPvPInstance()), tostring(logUsable)))
  elseif event == "PLAYER_REGEN_ENABLED" then
    Debug(("combat end - log events %d (secret %d, used %d), fallback resets %d, timer %.1f, last pvp action %s s ago"):format(
      stats.log, stats.logSecret, stats.logUsed, stats.fallback, db.pvpTimer,
      lastPvP and ("%.1f"):format(GetTime() - lastPvP) or "never"))
    stats.log, stats.logSecret, stats.logUsed, stats.fallback = 0, 0, 0, 0
    logUsable = false
    reportedSecrets = false
    -- Learn the real drop time from the last fight (clamped to sane values).
    if lastPvP and not NpcInvolved() then
      local measured = GetTime() - lastPvP
      if measured > 3 and measured < 10 then db.pvpTimer = measured end
    end
    lastPvP = nil
    wipe(npcs)
    state, leftAt, readyAt = "left", GetTime(), nil
    if not IsStealthed() then PlayAlert() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    state = UnitAffectingCombat("player") and "combat" or "idle"
  end
  Refresh()
end)

local function Print(msg) print("|cff33ff99CombatIndicator|r: " .. msg) end

SLASH_COMBATINDICATOR1 = "/ci"
SLASH_COMBATINDICATOR2 = "/combatindicator"
SlashCmdList.COMBATINDICATOR = function(msg)
  local cmd, arg = (msg or ""):lower():match("^(%S*)%s*(.-)$")
  if cmd == "lock" then
    db.locked = true; ApplyLock(); Print("locked.")
  elseif cmd == "unlock" then
    db.locked = false; ApplyLock(); Print("unlocked - drag to move.")
  elseif cmd == "scale" and tonumber(arg) then
    db.scale = math.min(3, math.max(0.5, tonumber(arg))); ApplyLayout(); Print("scale " .. db.scale)
  elseif cmd == "sound" then
    db.sound = not db.sound; Print("sound " .. (db.sound and "on" or "off"))
  elseif cmd == "combat" then
    db.showCombat = not db.showCombat; Refresh()
    Print("\"IN COMBAT\" text " .. (db.showCombat and "on" or "off"))
  elseif cmd == "timer" then
    if tonumber(arg) then db.pvpTimer = math.min(10, math.max(3, tonumber(arg))) end
    Print(("PvP combat drop timer: %.1f s (learned automatically after each PvP fight)"):format(db.pvpTimer))
    if not hasCombatLog then Print("|cffff4040combat log not available - PvP countdown disabled.|r") end
  elseif cmd == "debug" then
    if arg == "clear" then
      db.log = {}; Print("debug log cleared.")
    else
      db.debug = not db.debug
      Print("debug " .. (db.debug and "on - logging timer resets and a summary after each fight (saved on /reload)" or "off"))
    end
  elseif cmd == "showat" then
    if tonumber(arg) then db.showAt = math.min(10, math.max(1, tonumber(arg))) end
    Print(("PvP countdown appears with %.1f s or less left."):format(db.showAt))
  elseif cmd == "testpvp" then
    state, lastPvP = "combat", GetTime()
    wipe(npcs)
    Refresh()
  elseif cmd == "test" then
    state, leftAt, readyAt = "left", GetTime(), nil
    PlayAlert(); Refresh()
  elseif cmd == "reset" then
    for k, v in pairs(DEFAULTS) do db[k] = v end
    ApplyLayout(); ApplyLock(); Print("reset.")
  else
    Print("commands: /ci lock | unlock | scale <0.5-3> | sound | combat | timer [sec] | showat [sec] | debug | test | testpvp | reset")
  end
end
