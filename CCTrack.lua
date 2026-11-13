-- CCTrack 0.1 (WoW Forever)
-- Tracks YOUR OWN crowd control, silences/interrupts and DoTs/debuffs on multiple targets (WoW Forever, Lua 5.1)
-- No combat log on Forever: casts come from UNIT_SPELLCAST_* events and landing/fading from UNIT_AURA.
-- Values the client marks as secret are never compared or used in math (see R()).

CCTrack = CCTrack or {}
local CCT = CCTrack
CCT.version = "0.1"

local ADDON_NAME = ...
local MAX_BARS = 24
local BAR_SPACING = 2
local PENDING_GRACE = 3
local REFRESH_DELAY = 0.7
local MAX_NAMEPLATES = 40
local DEFAULT_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local OWN_FILTER = "HARMFUL|PLAYER"

local DEFAULTS = {
    width = 200,
    height = 18,
    growUp = false,
    locked = true,
    point = "CENTER",
    relPoint = "CENTER",
    x = -250,
    y = 120,
    ccOnly = false,
}

----------------------------------------------------------------------
-- Spell data
-- dur  = duration per rank in seconds (index = rank)
-- cast = cast time in seconds (only used for matching window)
-- aoe  = hits several targets at once
-- debuff = not a real CC (DoT, slow, root, silence, armor debuff, ...); hidden in "CC only" mode
-- pvp  = optional duration cap against players (not set by default)
-- aura = name of the debuff if it differs from the spell
--        name (e.g. Counterspell applies "Counterspell - Silenced")
-- breaks = any damage ends it; the bar goes away when you hit the mob with a damaging
--          spell or (if readable) its health drops. Forever hides enemy auras from addons,
--          so this is how a break is seen.
-- dmg  = the spell deals damage (breaks "breaks" CCs on its target); spells not in
--        this table count as damaging unless listed in NO_DAMAGE
-- Ranks beyond the end of dur use the last value.
----------------------------------------------------------------------
local SPELLS = {
    -- Mage
    ["Polymorph"]          = { breaks = true, dur = { 20, 30, 40, 50 }, cast = 1.5 },
    ["Frost Nova"]         = { dmg = true, dur = { 8, 8, 8, 8 }, aoe = true },
    ["Counterspell"]       = { debuff = true, dur = { 4 }, aura = "Counterspell - Silenced" },
    ["Fireball"]           = { dmg = true, debuff = true, dur = { 4, 6, 6, 8 }, cast = 3 },
    ["Pyroblast"]          = { dmg = true, debuff = true, dur = { 12 }, cast = 6 },
    ["Frostbolt"]          = { dmg = true, debuff = true, dur = { 12 }, cast = 2.5 },
    ["Cone of Cold"]       = { dmg = true, debuff = true, dur = { 8 }, aoe = true },
    -- Warlock
    ["Fear"]               = { dur = { 10, 15, 20 }, cast = 1.5 },
    ["Howl of Terror"]     = { dur = { 10, 15 }, cast = 2, aoe = true },
    ["Banish"]             = { dur = { 20, 30 }, cast = 1.5 },
    ["Death Coil"]         = { dmg = true, dur = { 3, 3, 3 } },
    ["Corruption"]         = { dmg = true, debuff = true, dur = { 12, 15, 18 }, cast = 2 },
    ["Immolate"]           = { dmg = true, debuff = true, dur = { 15 }, cast = 2 },
    ["Siphon Life"]        = { dmg = true, debuff = true, dur = { 30 } },
    ["Curse of Agony"]     = { dmg = true, debuff = true, dur = { 24 } },
    ["Curse of Weakness"]  = { debuff = true, dur = { 120 } },
    ["Curse of Recklessness"] = { debuff = true, dur = { 120 } },
    ["Curse of Tongues"]   = { debuff = true, dur = { 30 } },
    ["Curse of the Elements"] = { debuff = true, dur = { 300 } },
    ["Curse of Shadow"]    = { debuff = true, dur = { 300 } },
    ["Curse of Doom"]      = { dmg = true, debuff = true, dur = { 60 } },
    ["Curse of Exhaustion"] = { debuff = true, dur = { 12 } },
    -- Priest
    ["Shackle Undead"]     = { dur = { 30, 40, 50 }, cast = 1.5 },
    ["Psychic Scream"]     = { dur = { 8, 8, 8, 8 }, aoe = true },
    ["Silence"]            = { debuff = true, dur = { 5 } },
    ["Shadow Word: Pain"]  = { dmg = true, debuff = true, dur = { 18 } },
    ["Devouring Plague"]   = { dmg = true, debuff = true, dur = { 24 } },
    ["Holy Fire"]          = { dmg = true, debuff = true, dur = { 10 }, cast = 3 },
    -- Rogue
    ["Sap"]                = { breaks = true, dur = { 25, 35, 45 } },
    ["Gouge"]              = { dmg = true, breaks = true, dur = { 4, 4, 4, 4, 4 } },
    ["Blind"]              = { breaks = true, dur = { 10, 10 } },
    ["Cheap Shot"]         = { dur = { 4 } },
    ["Kick"]               = { dmg = true, debuff = true, dur = { 2 }, aura = "Kick - Silenced" },
    ["Garrote"]            = { dmg = true, debuff = true, dur = { 18 } },
    ["Expose Armor"]       = { debuff = true, dur = { 30 } },
    -- Druid
    ["Hibernate"]          = { breaks = true, dur = { 20, 30, 40 }, cast = 1.5 },
    ["Entangling Roots"]   = { dur = { 12, 15, 18, 21, 24, 27 }, cast = 1.5 },
    ["Bash"]               = { dmg = true, dur = { 2, 3, 4 } },
    ["Pounce"]             = { dmg = true, dur = { 2 } },
    ["Rake"]               = { dmg = true, debuff = true, dur = { 9 } },
    ["Rip"]                = { dmg = true, debuff = true, dur = { 12 } },
    ["Moonfire"]           = { dmg = true, debuff = true, dur = { 9, 12 } },
    ["Faerie Fire"]        = { debuff = true, dur = { 40 }, cast = 1 },
    ["Faerie Fire (Feral)"] = { debuff = true, dur = { 40 } },
    ["Demoralizing Roar"]  = { debuff = true, dur = { 30 }, aoe = true },
    -- Hunter
    ["Wyvern Sting"]       = { breaks = true, dur = { 12, 18, 24 } },
    ["Scare Beast"]        = { dur = { 10, 15, 20 }, cast = 1 },
    ["Scatter Shot"]       = { dmg = true, breaks = true, dur = { 4 } },
    ["Serpent Sting"]      = { dmg = true, debuff = true, dur = { 15 } },
    ["Viper Sting"]        = { debuff = true, dur = { 8 } },
    ["Scorpid Sting"]      = { debuff = true, dur = { 20 } },
    ["Hunter's Mark"]      = { debuff = true, dur = { 120 } },
    ["Concussive Shot"]    = { dmg = true, debuff = true, dur = { 4 } },
    ["Wing Clip"]          = { dmg = true, debuff = true, dur = { 10 } },
    -- Paladin
    ["Hammer of Justice"]  = { dur = { 3, 4, 5, 6 } },
    ["Repentance"]         = { breaks = true, dur = { 6 } },
    ["Turn Undead"]        = { dur = { 10, 15, 20 }, cast = 1.5 },
    -- Shaman
    ["Flame Shock"]        = { dmg = true, debuff = true, dur = { 12 } },
    ["Frost Shock"]        = { dmg = true, debuff = true, dur = { 8 } },
    -- Warrior
    ["Intimidating Shout"] = { dur = { 8 }, aoe = true },
    ["Concussion Blow"]    = { dmg = true, dur = { 5 } },
    ["Shield Bash"]        = { dmg = true, debuff = true, dur = { 3 }, aura = "Shield Bash - Silenced" },
    ["Rend"]               = { dmg = true, debuff = true, dur = { 9, 12, 15, 18, 21 } },
    ["Hamstring"]          = { dmg = true, debuff = true, dur = { 15 } },
    ["Sunder Armor"]       = { debuff = true, dur = { 30 } },
    ["Demoralizing Shout"] = { debuff = true, dur = { 30 }, aoe = true },
    ["Thunder Clap"]       = { dmg = true, debuff = true, dur = { 10, 14, 18, 22, 26, 30 }, aoe = true },
    ["Mortal Strike"]      = { dmg = true, debuff = true, dur = { 10 } },
    ["Piercing Howl"]      = { debuff = true, dur = { 6 }, aoe = true },
    ["Disarm"]             = { debuff = true, dur = { 10 } },
}
CCT.SPELLS = SPELLS

-- spells outside SPELLS that you may cast on an enemy without damaging it
local NO_DAMAGE = {
    ["Detect Magic"] = true, ["Tranquilizing Shot"] = true, ["Mind Vision"] = true,
    ["Mind Soothe"] = true, ["Distract"] = true, ["Pick Pocket"] = true, ["Soothe Animal"] = true,
    ["Tame Beast"] = true, ["Beast Lore"] = true, ["Purge"] = true, ["Dispel Magic"] = true,
}

-- aura name -> spell name (only differs for a few spells)
local AURA_TO_SPELL = {}
for name, data in pairs(SPELLS) do
    AURA_TO_SPELL[data.aura or name] = name
end

----------------------------------------------------------------------
-- State
----------------------------------------------------------------------
local S = {
    entries = {},
    pending = {},
    bars = {},
    known = {},
    unitList = { "target", "mouseover", "focus" },
    targetKey = {}, -- replaced on PLAYER_TARGET_CHANGED, even if the new GUID is secret
    dirty = false,
    debug = false,
    blind = false, -- set once the client refuses to show us any aura data
    auraEvents = 0,
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99CCTrack:|r " .. msg)
end

local LOG_MAX = 400

-- debug lines are also kept in CCTrackDB.log (written to disk on /reload or logout)
local function Debug(msg)
    if S.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff999999CCTrack debug:|r " .. msg)
        local log = CCTrackDB and CCTrackDB.log
        if log then
            log[#log + 1] = string.format("%.2f %s", GetTime(), msg)
            if #log > LOG_MAX then table.remove(log, 1) end
        end
    end
end

----------------------------------------------------------------------
-- Secret values
-- R(v) returns v, or nil if the client made it a secret value. All
-- logic works on R()'d values only; secrets are only handed to widgets.
----------------------------------------------------------------------
local CUA = C_UnitAuras or {}
local IsSecret = issecretvalue or function() return false end

local IsSecretTable = issecrettable or function() return false end

-- secret value or secret table: may not be compared, indexed or used in math
local function Opaque(v)
    return IsSecret(v) or (type(v) == "table" and IsSecretTable(v))
end

local function R(v)
    -- check first: even "v == nil" is not allowed on a secret
    if Opaque(v) then return nil end
    return v
end

-- printable description for /cctrack probe and debug output
local function Describe(v)
    if Opaque(v) then return "|cffff5555SECRET|r" end
    if v == nil then return "nil" end
    return tostring(v)
end

----------------------------------------------------------------------
-- Helpers
----------------------------------------------------------------------
local function RankNumber(rankStr)
    if not rankStr then return nil end
    local _, _, n = string.find(rankStr, "(%d+)")
    return tonumber(n)
end

local function StripStacks(name)
    -- stacking debuffs may show up as "Sunder Armor (2)"
    return (string.gsub(name, "%s*%(%d+%)$", ""))
end

local function SpellInfoById(id)
    if not id or not C_Spell then return nil end
    local name = C_Spell.GetSpellName and R(C_Spell.GetSpellName(id))
    local sub = C_Spell.GetSpellSubtext and R(C_Spell.GetSpellSubtext(id))
    local tex = C_Spell.GetSpellTexture and R(C_Spell.GetSpellTexture(id))
    local castMs
    if C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(id)
        info = R(info)
        castMs = info and R(info.castTime)
    end
    return name, RankNumber(sub), tex, castMs
end

local function GetIcon(unit)
    if GetRaidTargetIndex and UnitExists(unit) then
        return R(GetRaidTargetIndex(unit))
    end
    return nil
end

-- compound tokens like "party1target" can make UnitGUID/UnitName throw on Forever
local function SafeGUID(unit)
    local ok, guid = pcall(UnitGUID, unit)
    return ok and R(guid) or nil
end

local function SafeName(unit)
    local ok, name = pcall(UnitName, unit)
    return ok and R(name) or nil
end

-- readable identity of a unit: GUID (nil inside instances if secret), name
local function UnitIdent(unit)
    return SafeGUID(unit), SafeName(unit)
end

local function IsUnit(a, b)
    return R(UnitIsUnit(a, b)) and true or false
end

local function BuildUnitList()
    local list = { "target", "mouseover", "focus" }
    for i = 1, MAX_NAMEPLATES do
        table.insert(list, "nameplate" .. i)
    end
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do
            table.insert(list, "raid" .. i .. "target")
        end
    else
        for i = 1, n - 1 do
            table.insert(list, "party" .. i .. "target")
        end
    end
    S.unitList = list
end

-- units whose UNIT_AURA we care about (enemies we can see)
local function IsWatchedAuraUnit(unit)
    unit = R(unit)
    return unit and (unit == "target" or unit == "focus" or unit == "mouseover"
        or string.find(unit, "^nameplate%d+$") ~= nil)
end

local function ForEachBookSpellID(fn)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and Enum and Enum.SpellBookSpellBank then
        local bank = Enum.SpellBookSpellBank.Player
        for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
            if info and not info.shouldHide then
                for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if item and item.spellID and not item.isPassive then
                        fn(item.spellID)
                    end
                end
            end
        end
    elseif GetNumSpellTabs and GetSpellBookItemInfo then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
                if kind == "SPELL" and id then fn(id) end
            end
        end
    end
end

local function ScanSpellbook()
    S.known = {}
    ForEachBookSpellID(function(id)
        local name, rank, tex = SpellInfoById(id)
        if name and SPELLS[name] then
            local r = rank or 1
            local k = S.known[name]
            if not k then
                k = { maxRank = 0 }
                S.known[name] = k
            end
            if r >= k.maxRank then
                k.maxRank = r
                k.texture = tex
            end
        end
    end)
end

local function GetDuration(spell, rank, isPlayer)
    local data = SPELLS[spell]
    local n = #data.dur
    local k = S.known[spell]
    rank = rank or (k and k.maxRank) or n
    local d = data.dur[rank] or data.dur[n]
    if isPlayer and data.pvp and data.pvp < d then
        d = data.pvp
    end
    return d
end

----------------------------------------------------------------------
-- Bars
----------------------------------------------------------------------
local function CreateBar(i)
    local f = CreateFrame("Frame", "CCTrackBar" .. i, UIParent)
    f:SetFrameStrata("MEDIUM")
    f:EnableMouse(false)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetPoint("LEFT", f.icon, "RIGHT", 1, 0)
    f.bar:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.bar:SetStatusBarTexture(BAR_TEXTURE)

    f.bg = f.bar:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f.bar)
    f.bg:SetColorTexture(0, 0, 0, 0.6)

    f.marker = f.bar:CreateTexture(nil, "OVERLAY")
    f.marker:SetTexture(MARKER_TEXTURE)

    f.time = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.time:SetPoint("RIGHT", f.bar, "RIGHT", -3, 0)
    f.time:SetJustifyH("RIGHT")

    f.name = f.bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.name:SetJustifyH("LEFT")

    f:Hide()
    S.bars[i] = f
    return f
end

local function SetMarker(texture, index)
    local col = math.fmod(index - 1, 4)
    local row = math.floor((index - 1) / 4)
    texture:SetTexCoord(col * 0.25, (col + 1) * 0.25, row * 0.25, (row + 1) * 0.25)
end

local function ByExpire(a, b)
    return a.expire < b.expire
end

local function Layout()
    S.dirty = false
    table.sort(S.entries, ByExpire)
    local db = CCTrackDB
    local w, h = db.width, db.height
    for i = 1, MAX_BARS do
        local b = S.bars[i]
        local e = S.entries[i]
        if e then
            b = b or CreateBar(i)
            b:SetWidth(w)
            b:SetHeight(h)
            b.icon:SetWidth(h)
            b.icon:SetHeight(h)
            b.bar:SetHeight(h)
            b.marker:SetWidth(h - 4)
            b.marker:SetHeight(h - 4)

            b:ClearAllPoints()
            local off = (i - 1) * (h + BAR_SPACING)
            if db.growUp then
                b:SetPoint("BOTTOMLEFT", CCT.anchor, "TOPLEFT", 0, off)
            else
                b:SetPoint("TOPLEFT", CCT.anchor, "BOTTOMLEFT", 0, -off)
            end

            b.icon:SetTexture(e.texture or DEFAULT_ICON)
            b.bar:SetMinMaxValues(0, e.dur)
            b.name:ClearAllPoints()
            if e.icon then
                SetMarker(b.marker, e.icon)
                b.marker:ClearAllPoints()
                b.marker:SetPoint("LEFT", b.bar, "LEFT", 3, 0)
                b.marker:Show()
                b.name:SetPoint("LEFT", b.marker, "RIGHT", 3, 0)
            else
                b.marker:Hide()
                b.name:SetPoint("LEFT", b.bar, "LEFT", 4, 0)
            end
            b.name:SetPoint("RIGHT", b.time, "LEFT", -3, 0)
            -- mobText may be a secret name (inside instances); widgets accept those
            if not pcall(b.name.SetText, b.name, e.mobText or e.mob) then
                b.name:SetText(e.mob or "?")
            end
            b:Show()
        elseif b then
            b:Hide()
        end
    end
end

local function RemoveEntry(e)
    for i = 1, #S.entries do
        if S.entries[i] == e then
            table.remove(S.entries, i)
            break
        end
    end
    S.dirty = true
end

local function UnqualifiedName(name)
    return name and (string.match(name, "^[^-]+"))
end

-- t = { mob, mobText, guid, icon, auraID, unit, targetKey }
local function SameTarget(e, t, spell, now)
    if e.guid and t.guid then
        return e.guid == t.guid
    end
    if e.targetKey and t.targetKey then
        return e.targetKey == t.targetKey
    end
    if e.auraID and t.auraID then
        return e.auraID == t.auraID
    end
    -- one side has no readable GUID (secret in combat, readable out of it): fall back to name
    if not (e.mob and UnqualifiedName(e.mob) == UnqualifiedName(t.mob)) then
        return false
    end
    if e.icon or t.icon then
        return e.icon == t.icon
    end
    -- unmarked same-named mobs: an AoE hitting several of them must not
    -- replace the bars it just created
    return not SPELLS[spell].aoe or (now - e.start) > 0.5
end

local SafeHealth, UnitForGUID -- defined with the break-on-damage code below

local function AddEntry(spell, t, rank, isPlayer, texture, durOverride, isTest)
    local now = GetTime()
    local dur = durOverride or GetDuration(spell, rank, isPlayer)
    local expire = now + dur
    if t.auraDur and t.auraExpire and t.auraDur > 0 and t.auraExpire > now then
        -- the client knows the real duration (talents, PvP, diminishing returns)
        dur, expire = t.auraDur, t.auraExpire
    end
    local k = S.known[spell]
    local tex = texture or (k and k.texture) or DEFAULT_ICON

    -- refresh: replace the existing bar of this spell on this mob
    if not isTest then
        for i = #S.entries, 1, -1 do
            local e = S.entries[i]
            if e.spell == spell and not e.test and SameTarget(e, t, spell, now) then
                table.remove(S.entries, i)
            end
        end
    end

    table.insert(S.entries, {
        spell = spell,
        mob = t.mob,
        mobText = t.mobText,
        guid = t.guid,
        targetKey = t.targetKey,
        icon = t.icon,
        auraID = t.auraID,
        texture = tex,
        start = now,
        dur = dur,
        expire = expire,
        confirmed = t.auraID ~= nil,
        test = isTest,
    })
    local u = t.unit or UnitForGUID(t.guid)
    S.entries[#S.entries].hp = u and SafeHealth(u) or nil
    S.dirty = true
    Debug("tracking " .. spell .. " on " .. (t.mob or "?") .. " (" .. string.format("%.1f", dur) .. "s)")
end

----------------------------------------------------------------------
-- Own cast detection (UNIT_SPELLCAST_* for "player")
----------------------------------------------------------------------
local function IsTracked(name)
    local data = SPELLS[name]
    if not data then return false end
    return not (CCTrackDB and CCTrackDB.ccOnly and data.debuff)
end

local function FindPendingByGUID(castGUID)
    if not castGUID then return nil end
    for i = 1, #S.pending do
        if S.pending[i].castGUID == castGUID then return S.pending[i], i end
    end
    return nil
end

-- the unit the cast went to: SENT gives the target's name; check target/mouseover/focus
local function CastTargetUnit(targetName)
    targetName = UnqualifiedName(targetName)
    if not targetName then
        return UnitExists("target") and "target" or nil
    end
    for _, u in ipairs({ "target", "mouseover", "focus" }) do
        if UnitExists(u) and UnqualifiedName(SafeName(u)) == targetName then return u end
    end
    -- The sent name can be readable while UnitName("target") is secret.
    if UnitExists("target") and not SafeName("target") then return "target" end
    return nil
end

local function RecordCast(spellID, castGUID, targetName)
    local name, rank, tex, castMs = SpellInfoById(spellID)
    if not name or not IsTracked(name) then return nil end
    local data = SPELLS[name]
    local k = S.known[name]
    targetName = UnqualifiedName(targetName)
    local u = CastTargetUnit(targetName)
    local guid, uname
    if u then guid, uname = UnitIdent(u) end
    local cast = castMs and castMs / 1000 or data.cast or 0
    local p = {
        castGUID = castGUID,
        spell = name,
        rank = rank,
        tex = tex or (k and k.texture),
        target = targetName or uname,
        targetKey = u == "target" and S.targetKey or nil,
        guid = guid,
        icon = u and GetIcon(u) or nil,
        isPlayer = u and R(UnitIsPlayer(u)) and true or false,
        sentAt = GetTime(),
        castTime = cast,
        expire = GetTime() + cast + PENDING_GRACE,
    }
    table.insert(S.pending, p)
    if #S.pending > 8 then
        table.remove(S.pending, 1)
    end
    Debug("cast " .. name .. " target=" .. tostring(p.target))
    return p
end

----------------------------------------------------------------------
-- Aura handling (replaces the 1.12 combat log)
----------------------------------------------------------------------
local function PendingMatchesUnit(p, unit, guid, name)
    if SPELLS[p.spell].aoe then return true end
    if p.guid and guid then return p.guid == guid end
    if p.target and name then return p.target == UnqualifiedName(name) end
    if p.targetKey then
        return p.targetKey == S.targetKey and (unit == "target" or IsUnit(unit, "target"))
    end
    if p.target == nil and p.guid == nil then return true end
    return unit == "target" or IsUnit(unit, "target")
end

local function ClaimPending(spell, unit, guid, name)
    local now = GetTime()
    local found
    for i = #S.pending, 1, -1 do
        local p = S.pending[i]
        if now > p.expire then
            table.remove(S.pending, i)
        elseif not found and (spell == nil or p.spell == spell) and PendingMatchesUnit(p, unit, guid, name)
               and (spell ~= nil or (not SPELLS[p.spell].aoe
                   and (p.castDone or now >= p.sentAt + p.castTime - 0.2))) then
            -- spell == nil: aura contents are secret; only a (nearly) finished
            -- single-target cast on this very unit may claim it
            found = p
        end
    end
    if found and not SPELLS[found.spell].aoe then
        for i = #S.pending, 1, -1 do
            local p = S.pending[i]
            if p.spell == found.spell and p.target == found.target and p.guid == found.guid
                and p.targetKey == found.targetKey then
                table.remove(S.pending, i)
            end
        end
    end
    return found
end

-- returns the tracked spell, plus whether the aura could be identified at all
-- (false = contents are secret)
local function AuraSpell(aura)
    local name = R(aura.name)
    if not name then
        local sid = R(aura.spellId)
        name = sid and SpellInfoById(sid)
    end
    if not name then return nil, false end
    return AURA_TO_SPELL[StripStacks(name)], true
end

-- a new own debuff appeared on a visible unit
local function OnAuraCandidate(unit, aura)
    local id = R(aura.auraInstanceID)
    if S.debug then
        Debug("aura on " .. unit .. ": name=" .. Describe(aura.name) .. " spellId=" .. Describe(aura.spellId)
            .. " id=" .. Describe(aura.auraInstanceID) .. " pending=" .. #S.pending)
    end
    local spell, known = AuraSpell(aura)
    if known and not (spell and IsTracked(spell)) then return end

    local guid, name = UnitIdent(unit)
    -- The same unit can appear under several tokens with independent snapshots.
    -- An aura already tracked through one token is not a new cast through another.
    if id then
        for i = 1, #S.entries do
            local e = S.entries[i]
            if e.auraID == id and (not guid or not e.guid or e.guid == guid) then return end
        end
    end
    local p = ClaimPending(spell, unit, guid, name)
    if not p then return end
    spell = spell or p.spell

    AddEntry(spell, {
        mob = name,
        mobText = UnitName(unit), -- may be secret, display only
        guid = guid,
        unit = unit,
        targetKey = (unit == "target" or IsUnit(unit, "target")) and S.targetKey or nil,
        icon = GetIcon(unit),
        auraID = id,
        auraDur = R(aura.duration),
        auraExpire = R(aura.expirationTime),
    }, p.rank, R(UnitIsPlayer(unit)) and true or false, R(aura.icon) or p.tex)
end

-- stands in for an aura we may not look into (secret table); all its fields read as nil
local OPAQUE = {}

-- Calls fn(aura) for each aura matching filter (default: own debuffs); fn
-- returning true stops. Returns false if the client would not let us read
-- the unit's auras at all.
local function ScanUnitAuras(unit, fn, filter)
    -- once refused ("Auras cannot be accessed when secret"), don't ask again until combat ends
    if S.blind or not CUA.GetAuraDataByIndex then return false end
    for i = 1, 40 do
        local ok, aura = pcall(CUA.GetAuraDataByIndex, unit, i, filter or OWN_FILTER)
        if not ok then
            if not S.blind then Debug("aura access refused: " .. tostring(aura)) end
            S.blind = true
            return false
        end
        if Opaque(aura) then
            if fn(OPAQUE) then return true end
        elseif aura == nil then
            return true
        elseif fn(aura) then
            return true
        end
    end
    return true
end

-- UNIT_AURA's payload (isFullUpdate, addedAuras, ...) can be secret on Forever,
-- so it is never read. Instead every unit token keeps the own aura IDs of its
-- last scan, and each scan diffs against that. Scans run on UNIT_AURA and,
-- while a cast is pending, every 0.1s for all visible units.
local snapshots = {}

local function ScanSnapshot(unit)
    local snap = { guid = SafeGUID(unit), ids = {}, count = 0, list = {}, opaque = 0, noID = 0 }
    snap.readable = ScanUnitAuras(unit, function(aura)
        snap.count = snap.count + 1
        snap.list[snap.count] = aura
        if aura == OPAQUE then snap.opaque = snap.opaque + 1 end
        local id = R(aura.auraInstanceID)
        if id then snap.ids[id] = true else snap.noID = snap.noID + 1 end
    end)
    return snap
end

-- the unit token now points at a (possibly) different mob: start over
local function ResetSnapshot(unit)
    local snap = UnitExists(unit) and ScanSnapshot(unit)
    snapshots[unit] = snap and snap.readable and snap or nil
end

local function OnUnitAura(unit)
    if not IsWatchedAuraUnit(unit) then return end
    if not UnitExists(unit) then
        snapshots[unit] = nil
        return
    end
    local prev = snapshots[unit]
    local snap = ScanSnapshot(unit)
    -- a refused scan knows nothing: keep the old snapshot, remove nothing
    if not snap.readable then return end
    if prev and prev.guid ~= snap.guid then prev = nil end
    snapshots[unit] = snap

    if snap.guid and snap.noID == 0 then
        -- A readable scan can attest to absence only for this unit.
        for i = #S.entries, 1, -1 do
            local e = S.entries[i]
            if not e.test and e.auraID and not snap.ids[e.auraID]
                and (e.guid == snap.guid or (not e.guid and prev and prev.ids[e.auraID])) then
                Debug(e.spell .. " faded from " .. (e.mob or "?"))
                table.remove(S.entries, i)
                S.dirty = true
            end
        end
    end
    if #S.pending == 0 then return end
    if S.debug and (not prev or prev.count ~= snap.count or prev.opaque ~= snap.opaque) then
        Debug(unit .. " scan: own=" .. snap.count .. " opaque=" .. snap.opaque .. (prev and "" or " (first scan)"))
    end
    for i = 1, snap.count do
        local aura = snap.list[i]
        local id = R(aura.auraInstanceID)
        local isNew
        if not prev then
            isNew = true -- no earlier scan: every own aura is a candidate (still needs a pending cast)
        elseif id then
            isNew = not prev.ids[id]
        else
            isNew = snap.count > prev.count
        end
        if isNew then
            OnAuraCandidate(unit, aura)
        end
    end
end

local POLL_UNITS = { "target", "focus", "mouseover" }
for i = 1, MAX_NAMEPLATES do
    table.insert(POLL_UNITS, "nameplate" .. i)
end

local function PollUnits()
    for i = 1, #POLL_UNITS do
        if UnitExists(POLL_UNITS[i]) then OnUnitAura(POLL_UNITS[i]) end
    end
end

-- Re-casting on a mob that already has the debuff changes no aura IDs, so a
-- finished cast with an existing bar for the same spell and mob counts as a
-- refresh after REFRESH_DELAY (gives a new aura the chance to show up first).
local function FindEntryForPending(p, now)
    local target = { guid = p.guid, mob = p.target, icon = p.icon, targetKey = p.targetKey }
    for i = 1, #S.entries do
        local e = S.entries[i]
        if not e.test and e.spell == p.spell and SameTarget(e, target, p.spell, now) then
            return e
        end
    end
    return nil
end

local function AuraByInstance(u, id)
    if S.blind or not CUA.GetAuraDataByAuraInstanceID then return OPAQUE end
    local ok, aura = pcall(CUA.GetAuraDataByAuraInstanceID, u, id)
    if not ok or Opaque(aura) then return OPAQUE end
    return aura
end

-- Returns the matching aura, nil for a readable absence, or OPAQUE when
-- the client hides data needed to tell whether the aura is present.
local function FindEntryAura(unit, e)
    if e.auraID then return AuraByInstance(unit, e.auraID) end
    local found
    local readable = ScanUnitAuras(unit, function(aura)
        local spell, known = AuraSpell(aura)
        if spell == e.spell then
            found = aura
            return true
        end
        if not known then found = OPAQUE end
    end)
    if not readable then return OPAQUE end
    return found
end

local function UnitMatchesEntry(u, e)
    if not UnitExists(u) then return false end
    local guid = SafeGUID(u)
    if e.guid and guid then return guid == e.guid end
    if u == "target" and e.targetKey then return e.targetKey == S.targetKey end
    return e.icon ~= nil and SafeName(u) == e.mob and GetIcon(u) == e.icon
end

local function PollRefresh(now)
    for i = #S.pending, 1, -1 do
        local p = S.pending[i]
        if p.castDone and now <= p.expire and now - p.castDone >= REFRESH_DELAY then
            local e = not SPELLS[p.spell].aoe and FindEntryForPending(p, now)
            if e then
                local unit
                for j = 1, #S.unitList do
                    local candidate = S.unitList[j]
                    if UnitMatchesEntry(candidate, e) then
                        unit = candidate
                        break
                    end
                end
                local aura = unit and FindEntryAura(unit, e)
                local exp = aura and R(aura.expirationTime)
                if exp and exp > e.expire + 0.5 then
                    table.remove(S.pending, i)
                    local duration = R(aura.duration)
                    e.dur = (duration and duration > 0) and duration or GetDuration(p.spell, p.rank, p.isPlayer)
                    e.start = p.castDone
                    e.expire = exp
                    S.dirty = true
                    Debug(p.spell .. " refreshed on " .. (e.mob or "?"))
                elseif S.blind then
                    table.remove(S.pending, i)
                    e.guid = p.guid or e.guid
                    e.mob = p.target or e.mob
                    e.targetKey = p.targetKey or e.targetKey
                    e.icon = p.icon or e.icon
                    e.dur = GetDuration(p.spell, p.rank, p.isPlayer)
                    e.start = p.castDone
                    e.expire = p.castDone + e.dur
                    e.missing = nil
                    S.dirty = true
                    Debug(p.spell .. " refresh assumed (auras unreadable)")
                end
            elseif S.blind then
                -- the client hides aura data from us completely: trust the finished cast
                table.remove(S.pending, i)
                Debug(p.spell .. " assumed landed (auras unreadable) guid=" .. Describe(p.guid))
                AddEntry(p.spell, {
                    mob = p.target,
                    guid = p.guid,
                    icon = p.icon,
                    targetKey = p.targetKey,
                }, p.rank, p.isPlayer, p.tex)
            end
        end
    end
end

----------------------------------------------------------------------
-- Break on damage: auras are hidden, health is not (outside instances)
----------------------------------------------------------------------
function SafeHealth(unit)
    local ok, hp = pcall(UnitHealth, unit)
    return ok and R(hp) or nil
end

-- the unit token currently showing this mob (needs a readable GUID)
function UnitForGUID(guid)
    if not guid then return nil end
    for i = 1, #POLL_UNITS do
        local u = POLL_UNITS[i]
        if UnitExists(u) and SafeGUID(u) == guid then return u end
    end
    return nil
end

local function CheckBreaks(unit)
    local guid = SafeGUID(unit)
    if not guid then return end
    local hp
    for i = #S.entries, 1, -1 do
        local e = S.entries[i]
        if e.guid == guid and not e.test and SPELLS[e.spell].breaks then
            hp = hp or SafeHealth(unit)
            if not hp then return end
            if e.hp and hp < e.hp then
                Debug(e.spell .. " broke on " .. (e.mob or "?") .. " (damage)")
                table.remove(S.entries, i)
                S.dirty = true
            elseif not e.hp or hp > e.hp then
                e.hp = hp -- first look, or regenerating (sheep heal)
            end
        end
    end
end

-- Own casts: remember who each cast went to, so a damaging spell that lands on
-- a mob with a breakable CC of ours removes that bar (works without auras/health).
local castTargets, castTargetCount = {}, 0

local function RememberCastTarget(castGUID, targetName)
    if not castGUID then return end
    if not targetName or targetName == "" then return end -- self casts, ground AoE
    if castTargetCount >= 32 then castTargets, castTargetCount = {}, 0 end
    if not castTargets[castGUID] then castTargetCount = castTargetCount + 1 end
    local u = CastTargetUnit(targetName)
    castTargets[castGUID] = {
        name = UnqualifiedName(targetName),
        targetKey = u == "target" and S.targetKey or nil,
        guid = u and SafeGUID(u) or nil,
        icon = u and GetIcon(u) or nil,
    }
end

local function IsDamaging(name)
    if not name then return false end
    local data = SPELLS[name]
    if data then return data.dmg and true or false end
    return not NO_DAMAGE[name]
end

local function OnOwnCastLanded(castGUID, spellID)
    local t = castGUID and castTargets[castGUID]
    if not t then return end
    castTargets[castGUID] = nil
    castTargetCount = castTargetCount - 1
    local name = SpellInfoById(spellID)
    if not IsDamaging(name) then return end
    for i = #S.entries, 1, -1 do
        local e = S.entries[i]
        if not e.test and SPELLS[e.spell].breaks and e.spell ~= name then
            local same
            if t.guid and e.guid then
                same = t.guid == e.guid
            elseif t.targetKey and e.targetKey then
                same = t.targetKey == e.targetKey
            else
                same = UnqualifiedName(e.mob) == t.name and (not e.icon or not t.icon or e.icon == t.icon)
            end
            if same then
                Debug(e.spell .. " broken by your " .. name .. " on " .. (e.mob or "?"))
                table.remove(S.entries, i)
                S.dirty = true
            end
        end
    end
end

----------------------------------------------------------------------
-- Reconcile with units we can actually see (target, mouseover, focus,
-- nameplates, group targets). Needs a GUID or a raid icon to be unambiguous.
----------------------------------------------------------------------
local function Reconcile(now)
    for i = #S.entries, 1, -1 do
        local e = S.entries[i]
        if e and SPELLS[e.spell].breaks and not e.test then
            local u = UnitForGUID(e.guid)
            if u then CheckBreaks(u) end
        end
    end
    for i = #S.entries, 1, -1 do
        local e = S.entries[i]
        if e and (e.guid or e.icon) and not e.test then
            local absent, has, dead = false, false, false
            for j = 1, #S.unitList do
                local u = S.unitList[j]
                if UnitMatchesEntry(u, e) then
                    if R(UnitIsDead(u)) then
                        dead = true
                    else
                        local aura = FindEntryAura(u, e)
                        if aura and aura ~= OPAQUE then has = true end
                        if not aura then absent = true end
                    end
                end
            end
            if dead then
                Debug((e.mob or "?") .. " is dead - removing " .. e.spell)
                RemoveEntry(e)
            elseif has then
                e.confirmed = true
                e.missing = nil
            elseif absent and e.confirmed and (now - e.start) > 2 then
                if not e.missing then
                    e.missing = now
                elseif (now - e.missing) > 0.6 then
                    Debug(e.spell .. " no longer on " .. (e.mob or "?"))
                    RemoveEntry(e)
                end
            else
                e.missing = nil
            end
        end
    end
end

----------------------------------------------------------------------
-- Anchor + position
----------------------------------------------------------------------
local function SavePosition()
    local point, _, relPoint, x, y = CCT.anchor:GetPoint()
    local db = CCTrackDB
    db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

local function ApplyPosition()
    local db = CCTrackDB
    CCT.anchor:ClearAllPoints()
    CCT.anchor:SetPoint(db.point, UIParent, db.relPoint, db.x, db.y)
end

local function ApplyLock()
    local a = CCT.anchor
    if CCTrackDB.locked then
        a:EnableMouse(false)
        a:SetAlpha(0)
    else
        a:EnableMouse(true)
        a:SetAlpha(1)
    end
end

local function ApplySize()
    CCT.anchor:SetWidth(CCTrackDB.width)
    S.dirty = true
end

local function CreateAnchor()
    local a = CreateFrame("Frame", "CCTrackAnchor", UIParent, "BackdropTemplate")
    a:SetWidth(200)
    a:SetHeight(16)
    a:SetFrameStrata("MEDIUM")
    a:SetMovable(true)
    a:SetClampedToScreen(true)
    a:RegisterForDrag("LeftButton")
    a:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    a:SetBackdropColor(0, 0, 0.35, 0.85)
    a.text = a:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    a.text:SetPoint("CENTER", a, "CENTER", 0, 0)
    a.text:SetText("CCTrack - drag to move")
    a:SetScript("OnDragStart", function(self)
        if not CCTrackDB.locked then
            self:StartMoving()
        end
    end)
    a:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    CCT.anchor = a
end

----------------------------------------------------------------------
-- Test bars
----------------------------------------------------------------------
local function ToggleTestBars()
    local removed = false
    for i = #S.entries, 1, -1 do
        if S.entries[i].test then
            table.remove(S.entries, i)
            removed = true
        end
    end
    if removed then
        S.dirty = true
        return
    end
    AddEntry("Polymorph", { mob = "Test Target 1", icon = 8 }, nil, false, "Interface\\Icons\\Spell_Nature_Polymorph", 20, true)
    AddEntry("Frost Nova", { mob = "Test Target 2", icon = 4 }, nil, false, "Interface\\Icons\\Spell_Frost_FrostNova", 30, true)
    AddEntry("Sap", { mob = "Test Target 3" }, nil, false, "Interface\\Icons\\Ability_Sap", 45, true)
end

----------------------------------------------------------------------
-- Config UI
-- Built from basic widgets so it looks like the 1.12 Options* templates.
----------------------------------------------------------------------
local function ResetPosition()
    local db = CCTrackDB
    db.point, db.relPoint, db.x, db.y = DEFAULTS.point, DEFAULTS.relPoint, DEFAULTS.x, DEFAULTS.y
    ApplyPosition()
end

local function SetCCOnly(v)
    CCTrackDB.ccOnly = v and true or false
    if CCTrackDB.ccOnly then
        for i = #S.entries, 1, -1 do
            local e = S.entries[i]
            if not e.test and SPELLS[e.spell].debuff then
                table.remove(S.entries, i)
            end
        end
        for i = #S.pending, 1, -1 do
            if SPELLS[S.pending[i].spell].debuff then
                table.remove(S.pending, i)
            end
        end
    end
    S.dirty = true
    if CCT.ccCheck then CCT.ccCheck:SetChecked(CCTrackDB.ccOnly) end
end

local function CreateCheck(name, parent, y, label, checked, onClick)
    local c = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    c:SetWidth(26)
    c:SetHeight(26)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, y)
    local t = c.Text or c.text or _G[name .. "Text"] or c:CreateFontString(nil, "ARTWORK")
    t:SetFontObject("GameFontHighlight")
    t:ClearAllPoints()
    t:SetPoint("LEFT", c, "RIGHT", 0, 1)
    t:SetText(label)
    c:SetChecked(checked)
    c:SetScript("OnClick", onClick)
    return c
end

local function CreateSlider(name, parent, y, minV, maxV, step, value, label, onChange)
    local s = CreateFrame("Slider", name, parent, "BackdropTemplate")
    s:SetOrientation("HORIZONTAL")
    s:SetWidth(200)
    s:SetHeight(17)
    s:SetPoint("TOP", parent, "TOP", 0, y)
    s:SetHitRectInsets(0, 0, -10, -10)
    s:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
    })
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:EnableMouse(true)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end

    s.text = s:CreateFontString(name .. "Text", "ARTWORK", "GameFontHighlight")
    s.text:SetPoint("BOTTOM", s, "TOP", 0, 0)
    local low = s:CreateFontString(name .. "Low", "ARTWORK", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 2, 3)
    low:SetText(tostring(minV))
    local high = s:CreateFontString(name .. "High", "ARTWORK", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", -2, 3)
    high:SetText(tostring(maxV))

    s:SetValue(value)
    s.text:SetText(label .. value)
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor(v + 0.5)
        self.text:SetText(label .. v)
        onChange(v)
    end)
    return s
end

local function CreateConfig()
    local f = CreateFrame("Frame", "CCTrackConfig", UIParent, "BackdropTemplate")
    f:SetWidth(260)
    f:SetHeight(275)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", f, "TOP", 0, -16)
    title:SetText("CCTrack " .. CCT.version)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    CreateCheck("CCTrackUnlockCheck", f, -42, "Unlock (drag the blue anchor)", not CCTrackDB.locked, function(self)
        CCTrackDB.locked = not (self:GetChecked() and true or false)
        ApplyLock()
    end)

    CreateCheck("CCTrackGrowCheck", f, -68, "Grow bars upwards", CCTrackDB.growUp, function(self)
        CCTrackDB.growUp = self:GetChecked() and true or false
        S.dirty = true
    end)

    CCT.ccCheck = CreateCheck("CCTrackCCOnlyCheck", f, -94, "Only CC (hide DoTs/debuffs)", CCTrackDB.ccOnly, function(self)
        SetCCOnly(self:GetChecked())
    end)

    CreateSlider("CCTrackWidthSlider", f, -142, 100, 400, 5, CCTrackDB.width, "Bar width: ", function(v)
        CCTrackDB.width = v
        ApplySize()
    end)

    CreateSlider("CCTrackHeightSlider", f, -182, 10, 40, 1, CCTrackDB.height, "Bar height: ", function(v)
        CCTrackDB.height = v
        S.dirty = true
    end)

    -- Buttons
    local test = CreateFrame("Button", "CCTrackTestButton", f, "UIPanelButtonTemplate")
    test:SetWidth(100)
    test:SetHeight(22)
    test:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 22, 20)
    test:SetText("Test bars")
    test:SetScript("OnClick", function() ToggleTestBars() end)

    local reset = CreateFrame("Button", "CCTrackResetButton", f, "UIPanelButtonTemplate")
    reset:SetWidth(100)
    reset:SetHeight(22)
    reset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -22, 20)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function() ResetPosition() end)

    table.insert(UISpecialFrames, "CCTrackConfig")
    f:Hide()
    CCT.config = f
end

local function ToggleConfig()
    if not CCT.config then CreateConfig() end
    if CCT.config:IsShown() then
        CCT.config:Hide()
    else
        CCT.config:Show()
    end
end

----------------------------------------------------------------------
-- Probe: what does this client let addons read? (/cctrack probe)
----------------------------------------------------------------------
local function Probe()
    local function Has(path, v) Print(path .. ": " .. (v and "yes" or "|cffff5555missing|r")) end
    Print("--- probe v" .. CCT.version .. " ---")
    local inInstance, itype = IsInInstance()
    Print("in combat: " .. tostring(InCombatLockdown()) .. ", instance: " .. tostring(inInstance) .. " (" .. tostring(itype) .. ")"
        .. ", interface: " .. tostring(select(4, GetBuildInfo())))
    Has("issecretvalue", issecretvalue)
    Has("C_UnitAuras.GetAuraDataByIndex", CUA.GetAuraDataByIndex)
    Has("C_UnitAuras.GetAuraDataByAuraInstanceID", CUA.GetAuraDataByAuraInstanceID)
    Has("C_UnitAuras.IsAuraFilteredOutByInstanceID", CUA.IsAuraFilteredOutByInstanceID)
    Has("C_Spell.GetSpellName", C_Spell and C_Spell.GetSpellName)
    Has("C_Spell.GetSpellSubtext", C_Spell and C_Spell.GetSpellSubtext)
    Has("C_SpellBook.GetSpellBookItemInfo", C_SpellBook and C_SpellBook.GetSpellBookItemInfo)
    Has("GetRaidTargetIndex", GetRaidTargetIndex)
    local nKnown = 0
    for _ in pairs(S.known) do nKnown = nKnown + 1 end
    Print("spellbook: " .. nKnown .. " tracked spells found")
    if S.lastCast then
        Print("last own cast: spellID=" .. Describe(S.lastCast.spellID) .. " target=" .. Describe(S.lastCast.target)
            .. " castGUID=" .. Describe(S.lastCast.castGUID))
    else
        Print("last own cast: none yet (cast something, then probe again)")
    end
    if not UnitExists("target") then
        Print("no target - target a mob with your debuff on it and probe again")
        return
    end
    Print("target: name=" .. Describe(select(2, pcall(UnitName, "target"))) .. " guid=" .. Describe(select(2, pcall(UnitGUID, "target")))
        .. " raidIcon=" .. Describe(GetRaidTargetIndex and GetRaidTargetIndex("target"))
        .. " dead=" .. Describe(UnitIsDead("target")) .. " player=" .. Describe(UnitIsPlayer("target"))
        .. " health=" .. Describe(select(2, pcall(UnitHealth, "target"))))
    local n = 0
    ScanUnitAuras("target", function(a)
        n = n + 1
        Print("  own aura " .. n .. ": name=" .. Describe(a.name) .. " spellId=" .. Describe(a.spellId)
            .. " id=" .. Describe(a.auraInstanceID) .. " icon=" .. Describe(a.icon)
            .. " dur=" .. Describe(a.duration) .. " exp=" .. Describe(a.expirationTime)
            .. " src=" .. Describe(a.sourceUnit))
    end)
    if n == 0 then Print("  no own (HARMFUL|PLAYER) auras on target") end
    local function CountScan(filter)
        local cnt, opq = 0, 0
        local ok = ScanUnitAuras("target", function(a)
            cnt = cnt + 1
            if a == OPAQUE then opq = opq + 1 end
        end, filter)
        return cnt .. " (secret " .. opq .. (ok and "" or ", UNREADABLE") .. ")"
    end
    Print("  GetAuraDataByIndex: HARMFUL|PLAYER=" .. CountScan(OWN_FILTER) .. " HARMFUL=" .. CountScan("HARMFUL"))
    if CUA.GetUnitAuras then
        local ok, list = pcall(CUA.GetUnitAuras, "target", "HARMFUL")
        Print("  GetUnitAuras HARMFUL: " .. (not ok and "error" or Opaque(list) and "SECRET" or list and #list or "nil"))
    end
    if C_Secrets and C_Secrets.ShouldUnitIdentityBeSecret then
        Print("  identity secret: " .. Describe(C_Secrets.ShouldUnitIdentityBeSecret("target")))
    end
    Print("UNIT_AURA events seen: " .. S.auraEvents .. ", auras readable: " .. (S.blind and "NO" or "yes"))
    local np = 0
    for i = 1, MAX_NAMEPLATES do
        if UnitExists("nameplate" .. i) then np = np + 1 end
    end
    Print("visible nameplates: " .. np)
end

----------------------------------------------------------------------
-- Events / update loop
----------------------------------------------------------------------
local ef = CreateFrame("Frame", "CCTrackEventFrame", UIParent)
ef:RegisterEvent("ADDON_LOADED")
ef:RegisterEvent("PLAYER_ENTERING_WORLD")
ef:RegisterEvent("SPELLS_CHANGED")
ef:RegisterEvent("GROUP_ROSTER_UPDATE")
ef:RegisterEvent("UNIT_AURA")
ef:RegisterEvent("PLAYER_TARGET_CHANGED")
ef:RegisterEvent("PLAYER_FOCUS_CHANGED")
ef:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
ef:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ef:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
ef:RegisterEvent("UNIT_HEALTH")
ef:RegisterEvent("PLAYER_REGEN_ENABLED")
ef:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
ef:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
ef:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
ef:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")

ef:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_AURA" then
        S.auraEvents = S.auraEvents + 1
        OnUnitAura((...))
    elseif event == "PLAYER_TARGET_CHANGED" then
        S.targetKey = {}
        ResetSnapshot("target")
    elseif event == "PLAYER_FOCUS_CHANGED" then
        ResetSnapshot("focus")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        ResetSnapshot("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        ResetSnapshot((...))
    elseif event == "UNIT_SPELLCAST_SENT" then
        local _, target, castGUID, spellID = ...
        S.lastCast = { spellID = spellID, target = target, castGUID = castGUID }
        castGUID, spellID = R(castGUID), R(spellID)
        if spellID and not FindPendingByGUID(castGUID) then
            RecordCast(spellID, castGUID, R(target))
        end
        RememberCastTarget(castGUID, R(target))
    elseif event == "UNIT_SPELLCAST_START" then
        -- refine the matching window with the real cast time
        local _, castGUID = ...
        local p = FindPendingByGUID(R(castGUID))
        if p then
            local _, _, _, castMs = SpellInfoById(R(select(3, ...)))
            if castMs then p.expire = GetTime() + castMs / 1000 + PENDING_GRACE end
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local _, castGUID, spellID = ...
        castGUID, spellID = R(castGUID), R(spellID)
        local p = FindPendingByGUID(castGUID)
        Debug("cast succeeded spellID=" .. Describe(spellID) .. " pending=" .. (p and "yes" or "no")
            .. " UNIT_AURA events so far=" .. S.auraEvents)
        if not p and spellID then
            -- no SENT seen (e.g. cast without a target): record it now
            p = RecordCast(spellID, castGUID, nil)
        end
        if p then
            p.castDone = GetTime()
            p.expire = p.castDone + PENDING_GRACE
        end
        OnOwnCastLanded(castGUID, spellID)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local _, castGUID = ...
        castGUID = R(castGUID)
        local p, i = FindPendingByGUID(castGUID)
        if p and not p.castDone then
            table.remove(S.pending, i)
        end
        if castGUID and castTargets[castGUID] then
            castTargets[castGUID] = nil
            castTargetCount = castTargetCount - 1
        end
    elseif event == "ADDON_LOADED" then
        if ... ~= ADDON_NAME then return end
        if type(CCTrackDB) ~= "table" then CCTrackDB = {} end
        for k, v in pairs(DEFAULTS) do
            if CCTrackDB[k] == nil then CCTrackDB[k] = v end
        end
        CreateAnchor()
        ApplyPosition()
        ApplySize()
        ApplyLock()
        Print("v" .. CCT.version .. " loaded. Type /cctrack for options.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        S.entries = {}
        S.pending = {}
        snapshots = {}
        S.targetKey = {}
        castTargets, castTargetCount = {}, 0
        S.blind = false
        S.dirty = true
        ScanSpellbook()
        BuildUnitList()
        local names = {}
        for name in pairs(S.known) do table.insert(names, name) end
        if #names > 0 then
            Print("tracking: " .. table.concat(names, ", "))
        else
            Print("no tracked CC spells found in your spellbook.")
        end
    elseif event == "SPELLS_CHANGED" then
        ScanSpellbook()
    elseif event == "GROUP_ROSTER_UPDATE" then
        BuildUnitList()
    elseif event == "UNIT_HEALTH" then
        local unit = ...
        if #S.entries > 0 and IsWatchedAuraUnit(unit) then CheckBreaks(unit) end
    elseif event == "PLAYER_REGEN_ENABLED" then
        S.blind = false -- out of combat auras may be readable again
    end
end)

local tick, recTick = 0, 0
ef:SetScript("OnUpdate", function(self, elapsed)
    if not CCTrackDB or not CCT.anchor then return end
    local now = GetTime()

    for i = 1, MAX_BARS do
        local e = S.entries[i]
        local b = S.bars[i]
        if e and b and b:IsShown() then
            local rem = e.expire - now
            if rem < 0 then rem = 0 end
            b.bar:SetValue(rem)
            local r = rem / e.dur
            b.bar:SetStatusBarColor(1 - r, 0.3 + 0.7 * r, 0.1)
            b.time:SetText(string.format("%.1f", rem))
        end
    end

    tick = tick + elapsed
    if tick >= 0.1 then
        tick = 0
        if #S.pending > 0 then
            PollUnits()
            PollRefresh(now)
        end
        for i = #S.pending, 1, -1 do
            if now > S.pending[i].expire then
                table.remove(S.pending, i)
            end
        end
        for i = #S.entries, 1, -1 do
            if now >= S.entries[i].expire then
                table.remove(S.entries, i)
                S.dirty = true
            end
        end
    end

    recTick = recTick + elapsed
    if recTick >= 0.3 then
        recTick = 0
        if #S.entries > 0 then
            Reconcile(now)
        end
    end

    if S.dirty then Layout() end
end)

local function PrintStatus()
    local names = {}
    for name, k in pairs(S.known) do
        table.insert(names, name .. " (rank " .. k.maxRank .. ")")
    end
    Print("v" .. CCT.version .. " - recognized spells in your spellbook: " ..
        (#names > 0 and table.concat(names, ", ") or "NONE"))
    Print("active bars: " .. #S.entries .. ", pending casts: " .. #S.pending ..
        ", units watched: " .. #S.unitList .. ", mode: " .. (CCTrackDB.ccOnly and "CC only" or "all debuffs") .. ", debug: " .. (S.debug and "on" or "off")
        .. ", auras readable: " .. (S.blind and "NO (bars from casts)" or "yes"))
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_CCTRACK1 = "/cctrack"
SLASH_CCTRACK2 = "/cct"
SlashCmdList["CCTRACK"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "test" then
        ToggleTestBars()
    elseif msg == "reset" then
        ResetPosition()
    elseif msg == "unlock" then
        CCTrackDB.locked = false
        ApplyLock()
        Print("Unlocked - drag the blue anchor, then /cctrack lock.")
    elseif msg == "lock" then
        CCTrackDB.locked = true
        ApplyLock()
        Print("Locked.")
    elseif msg == "cc" then
        SetCCOnly(true)
        Print("Tracking CC only.")
    elseif msg == "all" then
        SetCCOnly(false)
        Print("Tracking CC and all debuffs.")
    elseif msg == "status" then
        PrintStatus()
    elseif msg == "probe" then
        Probe()
    elseif msg == "debug" then
        S.debug = not S.debug
        if S.debug then CCTrackDB.log = {} end
        Print("Debug " .. (S.debug and "on (also saved to the log in CCTrackDB, written on /reload)" or "off"))
    else
        ToggleConfig()
    end
end
