-- Character Tracker for KOReader, tracks and adds notes for KOReader

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Screen = require("device").screen
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local G_reader_settings = G_reader_settings or require("luasettings").reader
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local json = require("json")
local _ = require("gettext")
local T = require("ffi/util").template

local LAYOUT_SCOPE_KEY = "character_tracker_layout_scope"
local LayoutSettings = { doc = nil }

function LayoutSettings:isPerBook()
    return self.doc ~= nil and G_reader_settings:readSetting(LAYOUT_SCOPE_KEY) == "book"
end

function LayoutSettings:readSetting(key, default)
    if self:isPerBook() then
        local v = self.doc:readSetting(key)
        if v ~= nil then return v end
    end
    local v = G_reader_settings:readSetting(key)
    if v == nil then return default end
    return v
end

function LayoutSettings:isTrue(key)
    return self:readSetting(key) == true
end

function LayoutSettings:saveSetting(key, value)
    if self:isPerBook() then
        self.doc:saveSetting(key, value)
    else
        G_reader_settings:saveSetting(key, value)
    end
    return self
end

function LayoutSettings:delSetting(key)
    if self:isPerBook() then
        self.doc:delSetting(key)
    else
        G_reader_settings:delSetting(key)
    end
    return self
end



local SAVE_DEBOUNCE_SECONDS = 2
local UNLIMITED_MATCHES = 1000000
local MAX_MATCHES_PER_NAME = 800
local RECOMMENDED_MAX_MATCHES = 1600

local CharacterTracker = WidgetContainer:extend{
    name = "charactertracker",
    is_doc_only = true,
    characters = nil,
    data_file = nil,
    char_marks = nil,
    mark_enabled = false,
    visible_boxes = nil,
}

local RELATIONSHIP_TYPES = {
    { key = "father",   label = _("Father"),   category = "family" },
    { key = "mother",   label = _("Mother"),   category = "family" },
    { key = "son",      label = _("Son"),      category = "family" },
    { key = "daughter", label = _("Daughter"), category = "family" },
    { key = "brother",  label = _("Brother"),  category = "family" },
    { key = "sister",   label = _("Sister"),   category = "family" },
    { key = "sibling",  label = _("Sibling"),  category = "family" },
    { key = "parent",   label = _("Parent"),   category = "family" },
    { key = "child",    label = _("Child"),    category = "family" },
    { key = "adoptive_parent", label = _("Adoptive parent"), category = "family" },
    { key = "adopted_child",   label = _("Adopted child"),   category = "family" },
    { key = "guardian", label = _("Guardian"), category = "family" },
    { key = "ward",     label = _("Ward"),     category = "family" },
    { key = "step_parent",   label = _("Step-parent"),   category = "family" },
    { key = "step_child",    label = _("Step-child"),    category = "family" },
    { key = "foster_parent", label = _("Foster parent"), category = "family" },
    { key = "foster_child",  label = _("Foster child"),  category = "family" },
    { key = "partner",  label = _("Partner"),  category = "family" },
    { key = "ex",       label = _("Ex-partner"), category = "family" },
    { key = "cousin",   label = _("Cousin"),   category = "family" },
    { key = "spouse",   label = _("Spouse"),   category = "family" },
    { key = "ally",     label = _("Ally"),     category = "social" },
    { key = "rival",    label = _("Rival"),    category = "social" },
    { key = "enemy",    label = _("Enemy"),    category = "social" },
    { key = "friend",   label = _("Friend"),   category = "social" },
    { key = "mentor",   label = _("Mentor"),   category = "social" },
    { key = "servant",  label = _("Servant"),  category = "social" },
    { key = "master",   label = _("Master"),   category = "social" },
    { key = "lover",    label = _("Lover"),    category = "social" },
    { key = "platonic", label = _("Platonic friend"), category = "social" },
    { key = "acquaintance", label = _("Acquaintance"), category = "social" },
    { key = "professional", label = _("Professional"), category = "social" },
    { key = "family_bond", label = _("Family bond"), category = "social" },
    { key = "caregiving", label = _("Co-parent / caregiver"), category = "social" },
    { key = "codependent", label = _("Codependent"), category = "social" },
    { key = "toxic", label = _("Toxic"), category = "social" },
    { key = "parasocial", label = _("Parasocial"), category = "social" },
    { key = "dating", label = _("Dating"), category = "social" },
    { key = "monogamous", label = _("Monogamous partner"), category = "social" },
    { key = "open", label = _("Open relationship"), category = "social" },
    { key = "polyamorous", label = _("Polyamorous partner"), category = "social" },
    { key = "ldr", label = _("Long-distance partner"), category = "social" },
    { key = "asexual", label = _("Asexual relationship"), category = "social" },
    { key = "queerplatonic", label = _("Queerplatonic partner"), category = "social" },
    { key = "fwb", label = _("Friend with benefits"), category = "social" },
    { key = "situationship", label = _("Situationship"), category = "social" },
    { key = "custom",   label = _("Custom…"),  category = "other" },
}

local function getRelationshipLabel(type_key)
    for _i, rt in ipairs(RELATIONSHIP_TYPES) do
        if rt.key == type_key then
            return rt.label
        end
    end
    return type_key or _("Unknown")
end

local TIE_KINDS = {
    { key = "friend", label = _("Friends"), visual = "solid", rel = "friend", pull = true,
      desc = _("People who like and trust each other.") },
    { key = "platonic", label = _("Platonic friendship"), visual = "solid", pull = true,
      desc = _("A close, non-romantic and non-sexual friendship.") },
    { key = "acquaintance", label = _("Acquaintances"), visual = "thin",
      desc = _("A casual connection without deep emotional ties, such as classmates or neighbours.") },
    { key = "ally", label = _("Allies"), visual = "double", rel = "ally", pull = true,
      desc = _("People on the same side, working toward a shared goal.") },
    { key = "enemy", label = _("Enemies"), visual = "dashed", rel = "enemy",
      desc = _("People who oppose or want to harm each other.") },
    { key = "rival", label = _("Rivals"), visual = "dotted", rel = "rival",
      desc = _("People competing for the same goal, person or position.") },
    { key = "professional", label = _("Professional"), visual = "thin",
      desc = _("A connection built on work or duty, such as coworkers or boss and employee.") },
    { key = "family_bond", label = _("Family bond"), visual = "thick", pull = true,
      desc = _("A chosen or biological family connection with strong loyalty and obligation.") },
    { key = "caregiving", label = _("Co-parenting / caregiving"), visual = "thick", pull = true,
      desc = _("People who share responsibility for raising a child or looking after someone.") },
    { key = "codependent", label = _("Codependent"), visual = "dashdot",
      desc = _("An unbalanced bond where one or both rely on the other for their sense of worth.") },
    { key = "toxic", label = _("Toxic"), visual = "dashdot",
      desc = _("A harmful pattern of manipulation, control, jealousy or emotional damage.") },
    { key = "parasocial", label = _("Parasocial"), visual = "dotted",
      desc = _("A one-sided attachment, such as a fan to a celebrity or character.") },
    { key = "dating", label = _("Dating / casual romance"), visual = "wavy", pull = true, romance = true,
      desc = _("Seeing each other romantically without a long-term commitment.") },
    { key = "monogamous", label = _("Monogamous"), visual = "wavy", pull = true, romance = true,
      desc = _("A romantic relationship with exactly one partner.") },
    { key = "open", label = _("Open / non-monogamous"), visual = "wavy", pull = true, romance = true,
      desc = _("A partnership where seeing or sleeping with others is allowed.") },
    { key = "polyamorous", label = _("Polyamorous"), visual = "wavy", pull = true, romance = true,
      desc = _("Several romantic relationships at once, with everyone's knowledge.") },
    { key = "ldr", label = _("Long-distance"), visual = "wavy", pull = true, romance = true,
      desc = _("A couple living far apart, keeping the bond through calls and visits.") },
    { key = "asexual", label = _("Asexual relationship"), visual = "wavy", pull = true, romance = true,
      desc = _("A relationship where little or no sexual attraction is involved.") },
    { key = "queerplatonic", label = _("Queerplatonic / alterous"), visual = "wavy", pull = true, romance = true,
      desc = _("A deep bond that does not fit the line between friendship and romance.") },
    { key = "married", label = _("Engaged / married"), visual = "double", rel = "spouse", pull = true, romance = true,
      desc = _("A formal commitment, engaged or wed.") },
    { key = "fwb", label = _("Friends with benefits"), visual = "dashdot", pull = true, romance = true,
      desc = _("Friends who also share a physical relationship without romance.") },
    { key = "situationship", label = _("Situationship"), visual = "dashdot", pull = true, romance = true,
      desc = _("Something more than friends but undefined, with no clear commitment.") },
    { key = "complicated", label = _("It's complicated"), visual = "dashed", rel = "lover", pull = true, romance = true,
      desc = _("A romantic tangle: secret, unresolved or on and off.") },
    { key = "ex", label = _("Exes"), visual = "dotted", rel = "ex", romance = true,
      desc = _("A former couple.") },
}

local TIE_KIND_BY_KEY = {}
for _i, kind in ipairs(TIE_KINDS) do
    kind.rel = kind.rel or kind.key
    kind.group_label = kind.romance and _("Relationship tree · romance") or _("Relationship tree · friendship & bonds")
    TIE_KIND_BY_KEY[kind.key] = kind
end

local LEGACY_TIE_KINDS = {
    friendship = { solid = "friend", double = "ally", dashed = "enemy", dotted = "rival" },
    dating = { solid = "dating", double = "married", dashed = "complicated", dotted = "ex" },
}

local function migrateTieKind(tie, family_mode)
    if tie.kind == "custom" and type(tie.custom) == "table" and tie.custom.name then return end
    if tie.kind and TIE_KIND_BY_KEY[tie.kind] then return end
    local map = LEGACY_TIE_KINDS[(tie.mode or family_mode) == "dating" and "dating" or "friendship"]
    tie.kind = map[tie.style or "solid"] or "friend"
end

local SENTIMENT_TYPES = {
    { key = "likes",     label = _("Likes") },
    { key = "dislikes",  label = _("Dislikes") },
    { key = "loves",     label = _("Loves") },
    { key = "hates",     label = _("Hates") },
    { key = "fears",     label = _("Fears") },
    { key = "admires",   label = _("Admires") },
    { key = "respects",  label = _("Respects") },
    { key = "distrusts", label = _("Distrusts") },
    { key = "envies",    label = _("Envies") },
    { key = "pities",    label = _("Pities") },
    { key = "loyal",     label = _("Loyal to") },
    { key = "custom",    label = _("Custom…") },
}

local function getSentimentLabel(key)
    if not key or key == "" then return nil end
    for _i, st in ipairs(SENTIMENT_TYPES) do
        if st.key == key then
            return st.label
        end
    end
    return key
end

local CHARACTER_TYPES = {
    { key = "",           label = _("Not set") },
    { key = "main",       label = _("Main") },
    { key = "secondary",  label = _("Secondary") },
    { key = "tertiary",   label = _("Tertiary") },
    { key = "mentioned",  label = _("Mentioned") },
    { key = "antagonist", label = _("Antagonist") },
    { key = "narrator",   label = _("Narrator") },
}

local function getCharacterTypeLabel(type_key)
    if not type_key or type_key == "" then return _("Not set") end
    for _i, r in ipairs(CHARACTER_TYPES) do
        if r.key == type_key then
            return r.label
        end
    end
    return type_key
end

local STATUS_TYPES = {
    { key = "alive",   label = _("Alive") },
    { key = "dead",    label = _("Dead") },
    { key = "missing", label = _("Missing") },
    { key = "unknown", label = _("Unknown") },
    { key = "custom",  label = _("Custom…") },
}

local function getStatusLabel(status_key)
    if not status_key or status_key == "" then return _("Not set") end
    for _i, s in ipairs(STATUS_TYPES) do
        if s.key == status_key then
            return s.label
        end
    end
    return status_key
end

local PLACE_TYPES = {
    { key = "kingdom",       label = _("Kingdom") },
    { key = "empire",        label = _("Empire") },
    { key = "dukedom",       label = _("Dukedom") },
    { key = "principality",  label = _("Principality") },
    { key = "county",        label = _("County") },
    { key = "republic",      label = _("Republic") },
    { key = "federation",    label = _("Federation") },
    { key = "dictatorship",  label = _("Dictatorship") },
    { key = "theocracy",     label = _("Theocracy") },
    { key = "city_state",    label = _("City-state") },
    { key = "province",      label = _("Province") },
    { key = "region",        label = _("Region") },
    { key = "city",          label = _("City") },
    { key = "town",          label = _("Town") },
    { key = "village",        label = _("Village") },
    { key = "district",      label = _("District") },
    { key = "fortress",      label = _("Fortress / castle") },
    { key = "building",      label = _("Building") },
    { key = "landmark",      label = _("Landmark") },
    { key = "custom",        label = _("Custom…") },
}

local function getPlaceTypeLabel(type_key)
    if not type_key or type_key == "" then return _("Unspecified") end
    for _i, p in ipairs(PLACE_TYPES) do
        if p.key == type_key then
            return p.label
        end
    end
    return type_key
end

local HIGHLIGHT_TOPICS = {
    { key = "status",        label = _("Status") },
    { key = "occupation",    label = _("Occupation") },
    { key = "appearance",    label = _("Appearance") },
    { key = "ability",       label = _("Ability") },
    { key = "belongings",    label = _("Belongings") },
    { key = "relationships", label = _("Relationships") },
    { key = "factions",      label = _("Factions") },
    { key = "traits",        label = _("Traits") },
    { key = "skills",        label = _("Skills") },
    { key = "weaknesses",    label = _("Weaknesses") },
    { key = "secrets",       label = _("Secrets") },
}

local function getTopicLabel(key)
    for _i, topic in ipairs(HIGHLIGHT_TOPICS) do
        if topic.key == key then return topic.label end
    end
    return key
end

local PAGE_SECTIONS = {
    { key = "appearance",        label = _("Appearance") },
    { key = "ability",           label = _("Ability") },
    { key = "relationships",     label = _("Relationships") },
    { key = "tree_ties",         label = _("Family & relationship trees") },
    { key = "factions_tags",     label = _("Factions & tags") },
    { key = "traits",            label = _("Personality traits") },
    { key = "occurrences",       label = _("Occurrences") },
    { key = "timeline",          label = _("Timeline events") },
    { key = "highlights",        label = _("Highlights") },
    { key = "topic_highlights",  label = _("Highlights by topic") },
    { key = "secrets",           label = _("Secrets") },
    { key = "skills_weaknesses", label = _("Skills & weaknesses") },
    { key = "notes",             label = _("Notes") },
    { key = "quote",             label = _("Quote") },
}

local COMPENDIUM_TYPES = {
    { key = "object",      label = _("Object") },
    { key = "artifact",    label = _("Artifact") },
    { key = "weapon",      label = _("Weapon") },
    { key = "document",    label = _("Document / book") },
    { key = "concept",     label = _("Concept / abstract idea") },
    { key = "magic_system", label = _("Magic system") },
    { key = "custom",      label = _("Custom…") },
}

local function getCompendiumTypeLabel(type_key)
    if not type_key or type_key == "" then return _("Unspecified") end
    for _i, c in ipairs(COMPENDIUM_TYPES) do
        if c.key == type_key then
            return c.label
        end
    end
    return type_key
end

local function shorten(s, max)
    if #s <= max then return s end
    local cut = max - 3
    while cut > 0 do
        local b = s:byte(cut + 1)
        if b and b >= 0x80 and b < 0xC0 then
            cut = cut - 1
        else
            break
        end
    end
    return s:sub(1, cut) .. "..."
end

local function trim(s)
    if not s then return "" end
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function pageBlock(title, body)
    if LayoutSettings and LayoutSettings:isTrue("character_tracker_hide_counts") then
        title = title:gsub("%s*%(%d+%)$", "")
    end
    return "\n── " .. title .. " ──\n" .. body
end

local function pageBullets(items, marker)
    local out = {}
    for _i, item in ipairs(items) do
        table.insert(out, marker .. item .. "\n")
    end
    return table.concat(out)
end

local function formatHighlight(text, notes)
    local out = "“" .. text .. "”\n"
    for _i, note in ipairs(notes or {}) do
        out = out .. "  • " .. note .. "\n"
    end
    return out
end

local function getNoteText(note)
    if type(note) == "table" then return note.text or "" end
    return tostring(note)
end

local _id_seq = 0
local function genId()
    _id_seq = _id_seq + 1
    return string.format("p%s_%s_%s", os.time(), _id_seq, math.random(100000))
end

function CharacterTracker:init()
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
    self.characters = {}
    self.places = {}
    self.places_file = nil
    self.compendium = {}
    self.compendium_file = nil
    self.families = {}
    self.timelines = {}
    self.families_file = nil
    self._name_index = {}
    self._no_underline_names = {}
    self.marks_by_charname = {}
    self.marks_by_placename = {}
    self.marks_by_objname = {}
    self.marks_by_page = {}
    self.mark_enabled = false
    self.place_mark_enabled = false
    self.object_mark_enabled = false
    self.underline_invisible = false
    self._data_dirty = false
    self._places_dirty = false
    self._compendium_dirty = false
    self._families_dirty = false
    self._timeline_dirty = false
    self._save_scheduled = false
    self._trash = {}
    self._reader_ready_done = false
    self._dict_button_registered = false
    self:_ensureVirtualKeyboard()
    self:_registerDictButton()
end

function CharacterTracker:_ensureVirtualKeyboard()
    if not G_reader_settings then return end
    if G_reader_settings:readSetting("virtual_keyboard_enabled") ~= nil then
        return
    end
    G_reader_settings:saveSetting("virtual_keyboard_enabled", true)
    if G_reader_settings.flush then
        pcall(function() G_reader_settings:flush() end)
    end
end

function CharacterTracker:onDispatcherRegisterActions()
    Dispatcher:registerAction("character_tracker_show", {
        category = "none",
        event = "ShowCharacterList",
        title = _("Character Tracker: character list"),
        reader = true,
    })
    Dispatcher:registerAction("character_tracker_show_edit", {
        category = "none",
        event = "ShowEditCharacterList",
        title = _("Character Tracker: edit character list"),
        reader = true,
    })
    Dispatcher:registerAction("character_tracker_show_places", {
        category = "none",
        event = "ShowPlaceList",
        title = _("Character Tracker: places"),
        reader = true,
    })
    Dispatcher:registerAction("character_tracker_show_compendium", {
        category = "none",
        event = "ShowCompendiumList",
        title = _("Character Tracker: compendium"),
        reader = true,
    })
    Dispatcher:registerAction("character_tracker_show_families", {
        category = "none",
        event = "ShowFamilyList",
        title = _("Character Tracker: families"),
        reader = true,
    })
    Dispatcher:registerAction("character_tracker_show_family_tree", {
        category = "none",
        event = "ShowFamilyTreePicker",
        title = _("Character Tracker: family tree"),
        reader = true,
    })
    Dispatcher:registerAction("character_tracker_show_timeline", {
        category = "none",
        event = "ShowTimelineList",
        title = _("Character Tracker: timeline"),
        reader = true,
    })
    Dispatcher:registerAction("character_tracker_show_family_tree_edit", {
        category = "none",
        event = "ShowFamilyTreeEditPicker",
        title = _("Character Tracker: edit family tree"),
        reader = true,
    })
end

function CharacterTracker:onShowPlaceList()
    self:showPlaceList()
end

function CharacterTracker:onShowCompendiumList()
    self:showCompendiumList()
end

function CharacterTracker:onShowFamilyList()
    self:showFamilyList()
end

function CharacterTracker:onShowFamilyTreePicker()
    self:showFamilyTreePicker(true)
end

function CharacterTracker:onShowFamilyTreeEditPicker()
    self:showFamilyTreePicker(false)
end

function CharacterTracker:onReaderReady()
    if self._reader_ready_done then
        return
    end
    self._reader_ready_done = true

    LayoutSettings.doc = self.ui.doc_settings

    self:_registerDictButton()

    self:loadData()
    self:loadPlaces()
    self:loadCompendium()
    self:loadFamilies()
    self:loadTimelines()
    local saved = self.ui.doc_settings:readSetting("character_tracker_underline")
    if saved ~= nil then
        self.mark_enabled = saved
    end
    local saved_places = self.ui.doc_settings:readSetting("character_tracker_underline_places")
    if saved_places ~= nil then
        self.place_mark_enabled = saved_places
    end
    local saved_objects = self.ui.doc_settings:readSetting("character_tracker_underline_objects")
    if saved_objects ~= nil then
        self.object_mark_enabled = saved_objects
    end
    local saved_invisible = self.ui.doc_settings:readSetting("character_tracker_underline_invisible")
    if saved_invisible ~= nil then
        self.underline_invisible = saved_invisible
    end
    self.view = self.ui.view
    self.ui.view:registerViewModule("charactertracker", self)
    self.ui:registerTouchZones({
        {
            id = "charactertracker_tap",
            ges = "tap",
            screen_zone = {
                ratio_x = 0, ratio_y = 0,
                ratio_w = 1, ratio_h = 1,
            },
            overrides = {
                "readerhighlight_tap",
            },
            handler = function(ges)
                return self:onTapUnderline(ges)
            end,
        },
    })
    self.marks_by_charname = {}
    self.marks_by_placename = {}
    self.marks_by_objname = {}
    self.marks_by_page = {}
    self.char_marks = {}
    self.mark_runs = {}
    self.visible_boxes = {}
    if self.mark_enabled or self.place_mark_enabled or self.object_mark_enabled then
        self._deferred_index_fn = function()
            self._deferred_index_fn = nil
            if self._closed then return end
            self:rebuildAllMarks()
        end
        UIManager:scheduleIn(0.3, self._deferred_index_fn)
    end
    if self.ui.highlight then
        self.ui.highlight:addToHighlightDialog("charactertracker_assign", function(this)
            return {
                text = _("Character"),
                callback = function()
                    local selected = this.selected_text
                    this:onClose()
                    self:onAssignHighlightToCharacter(selected)
                end,
            }
        end)
    end
end

function CharacterTracker:onCloseDocument()
    self:_disarmDetailReturn()
    LayoutSettings.doc = nil
    self._closed = true
    if self._deferred_index_fn then
        UIManager:unschedule(self._deferred_index_fn)
        self._deferred_index_fn = nil
    end
    self:_flushSaveData()
    if self._save_scheduled then
        UIManager:unschedule(self._flushSaveDataBound)
        self._save_scheduled = false
    end
    local ok1, err1 = pcall(function()
        self.ui:unRegisterTouchZones({ { id = "charactertracker_tap" } })
    end)
    if not ok1 then
        logger.dbg("CharacterTracker: unRegisterTouchZones not available:", err1)
    end
    local ok2, err2 = pcall(function()
        self.ui.view:unregisterViewModule("charactertracker")
    end)
    if not ok2 then
        logger.dbg("CharacterTracker: unregisterViewModule not available:", err2)
    end
end

function CharacterTracker:onFlushSettings()
    self:_flushSaveData()
end

function CharacterTracker:onSuspend()
    self:_flushSaveData()
end

function CharacterTracker:onPageUpdate()
    self.visible_boxes = {}
    self._paint_cache_key = nil
end

local function scanRuns(document, strings, cap)
    local marks = {}
    for r, text in ipairs(strings) do
        if text and text ~= "" then
            local res = document:findAllText(text, true, 0, cap, false)
            if res then
                for _i, item in ipairs(res) do
                    marks[#marks + 1] = {
                        start = item.start,
                        ["end"] = item["end"],
                        boxes = item.boxes,
                        r = r,
                    }
                end
            end
        end
    end
    return marks
end

local function hydrateMarks(buckets, entity_type)
    for name, marks in pairs(buckets) do
        for _i, m in ipairs(marks) do
            m.char_name = name
            m.entity_type = entity_type
        end
    end
end

local function trimBucketsToCap(buckets, cap)
    for name, marks in pairs(buckets) do
        local counts, kept = {}, {}
        for _i, m in ipairs(marks) do
            local r = m.r or 0
            local n = (counts[r] or 0) + 1
            counts[r] = n
            if n <= cap then kept[#kept + 1] = m end
        end
        if #kept ~= #marks then buckets[name] = kept end
    end
end

local function characterStrings(char)
    local strings = { char.name }
    for _i, alias in ipairs(char.aliases or {}) do
        strings[#strings + 1] = alias
    end
    return strings
end

local function nameStrings(entity)
    return characterStrings(entity)
end

local function entityMeta(buckets, entities, strings_of, cap)
    local out = {}
    for _i, entity in ipairs(entities) do
        local name = entity.name
        local marks = name and buckets[name]
        if marks then
            local counts, capped = {}, false
            for _j, m in ipairs(marks) do
                local r = m.r or 0
                local n = (counts[r] or 0) + 1
                counts[r] = n
                if n >= cap then capped = true end
            end
            out[name] = {
                sig = table.concat(strings_of(entity), "\1"),
                cap = cap,
                complete = not capped,
            }
        end
    end
    return out
end

local function slimBuckets(buckets)
    local out = {}
    for name, marks in pairs(buckets) do
        local list = {}
        for i, m in ipairs(marks) do
            list[i] = { start = m.start, ["end"] = m["end"], boxes = m.boxes, r = m.r }
        end
        out[name] = list
    end
    return out
end

function CharacterTracker:paintTo(bb, x, y)
    self.visible_boxes = {}
    if not (self.mark_enabled or self.place_mark_enabled or self.object_mark_enabled) then
        return
    end
    if not self.char_marks or #self.char_marks == 0 then
        return
    end
    local ok, err = pcall(function()
        if self.ui.rolling then
            self:_paintToRolling(bb, x, y)
        elseif self.ui.paging then
            self:_paintToPaging(bb, x, y)
        end
    end)
    if not ok then
        logger.warn("CharacterTracker: paintTo error:", err)
        self.char_marks = {}
        self.visible_boxes = {}
    end
end

function CharacterTracker:_paintToRolling(bb, x, y)
    local cur_view_top = self.ui.document:getCurrentPos()
    local cur_view_bottom
    if self.view.view_mode == "page" and self.ui.document:getVisiblePageCount() > 1 then
        cur_view_bottom = cur_view_top + 2 * self.ui.dimen.h
    else
        cur_view_bottom = cur_view_top + self.ui.dimen.h
    end

    local cache_key = cur_view_top .. ":" .. cur_view_bottom .. ":" .. tostring(self.underline_invisible)
    if self._paint_cache_key == cache_key and self._paint_cache_boxes then
        for _i, cached in ipairs(self._paint_cache_boxes) do
            if not self._no_underline_names[cached.char_name:lower()] then
                if not self.underline_invisible then
                    self.view:drawHighlightRect(bb, x, y, cached.rect, "underscore")
                end
                table.insert(self.visible_boxes, cached)
            end
        end
        return
    end

    local doc = self.ui.document
    local computed = {}
    for _r, run in ipairs(self.mark_runs or {}) do
        local n = #run
        local lo, hi = 1, n + 1
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            local m = run[mid]
            local end_pos = m["end"] and doc:getPosFromXPointer(m["end"])
            if end_pos and end_pos < cur_view_top then
                lo = mid + 1
            else
                hi = mid
            end
        end
        for i = lo, n do
            local mark = run[i]
            if mark.start and mark["end"] then
                local start_pos = doc:getPosFromXPointer(mark.start)
                if start_pos then
                    if start_pos > cur_view_bottom then
                        break
                    end
                    local boxes = doc:getScreenBoxesFromPositions(mark.start, mark["end"], true)
                    if boxes then
                        local char_name_lower = mark.char_name:lower()
                        for _j, box in ipairs(boxes) do
                            if box.h ~= 0 and not self._no_underline_names[char_name_lower] then
                                if not self.underline_invisible then
                                    self.view:drawHighlightRect(bb, x, y, box, "underscore")
                                end
                                local entry = { rect = box, char_name = mark.char_name, entity_type = mark.entity_type }
                                table.insert(self.visible_boxes, entry)
                                table.insert(computed, entry)
                            end
                        end
                    end
                end
            end
        end
    end
    self._paint_cache_key = cache_key
    self._paint_cache_boxes = computed
end

function CharacterTracker:_paintToPaging(bb, x, y)
    local cur_page = self:getCurrentPage()
    local page_marks = self.marks_by_page[cur_page]
    if not page_marks then return end
    for _i, mark in ipairs(page_marks) do
        if mark.boxes and not self._no_underline_names[mark.char_name:lower()] then
            for _j, box in ipairs(mark.boxes) do
                local native_box = self.ui.document:nativeToPageRectTransform(cur_page, box)
                if native_box then
                    local screen_rect = self.view:pageToScreenTransform(cur_page, native_box)
                    if screen_rect then
                        if not self.underline_invisible then
                            self.view:drawHighlightRect(bb, x, y, screen_rect, "underscore")
                        end
                        table.insert(self.visible_boxes, {
                            rect = native_box,
                            char_name = mark.char_name,
                            entity_type = mark.entity_type,
                        })
                    end
                end
            end
        end
    end
end

function CharacterTracker:_indexMarks()
    local flat = {}
    local by_page = {}
    local runs = {}
    local want_runs = self.ui.rolling ~= nil and self.ui.rolling ~= false
    local function fold(marks_by_name)
        for _name, marks in pairs(marks_by_name) do
            local run, last_r
            for _i, mark in ipairs(marks) do
                if want_runs then
                    if not run or mark.r ~= last_r then
                        run = {}
                        runs[#runs + 1] = run
                        last_r = mark.r
                    end
                    run[#run + 1] = mark
                end
                table.insert(flat, mark)
                if self.ui.paging and mark.start and by_page[mark.start] == nil then
                    by_page[mark.start] = {}
                end
                if self.ui.paging and mark.start then
                    table.insert(by_page[mark.start], mark)
                end
            end
        end
    end
    fold(self.marks_by_charname)
    fold(self.marks_by_placename)
    fold(self.marks_by_objname)
    self.char_marks = flat
    self.mark_runs = runs
    self.marks_by_page = by_page
end

function CharacterTracker:_indexLimitReached(character)
    local cap = self:getMatchCap()
    if cap >= UNLIMITED_MATCHES then return false end
    local counts = {}
    for _i, m in ipairs(self.marks_by_charname[character.name] or {}) do
        local r = m.r or 0
        counts[r] = (counts[r] or 0) + 1
    end
    for _r, n in pairs(counts) do
        if n >= cap then return true end
    end
    return false
end

function CharacterTracker:getMatchCap()
    local cap = G_reader_settings:readSetting("character_tracker_max_matches_per_name", MAX_MATCHES_PER_NAME)
    if type(cap) ~= "number" or cap < 1 then
        return MAX_MATCHES_PER_NAME
    end
    return cap
end

function CharacterTracker:rebuildMarksForCharacter(char)
    if not self.ui.document then return end
    if not self.mark_enabled then return end
    local strings = { char.name }
    for _j, alias in ipairs(char.aliases or {}) do
        table.insert(strings, alias)
    end
    local marks = scanRuns(self.ui.document, strings, self:getMatchCap())
    hydrateMarks({ [char.name] = marks }, "character")
    self.marks_by_charname[char.name] = marks
    self:_indexMarks()
    self:_saveMarksCache()
    UIManager:setDirty(self.dialog, "ui")
end

function CharacterTracker:removeMarksForCharacterName(char_name)
    self.marks_by_charname[char_name] = nil
    self:_indexMarks()
    self:_saveMarksCache()
    UIManager:setDirty(self.dialog, "ui")
end

function CharacterTracker:rebuildMarksForPlace(place)
    if not self.ui.document then return end
    if not self.place_mark_enabled then return end
    if not place.name or place.name == "" then return end
    local marks = scanRuns(self.ui.document, nameStrings(place), self:getMatchCap())
    hydrateMarks({ [place.name] = marks }, "place")
    self.marks_by_placename[place.name] = marks
    self:_indexMarks()
    self:_saveMarksCache()
    UIManager:setDirty(self.dialog, "ui")
end

function CharacterTracker:removeMarksForPlaceName(name)
    self.marks_by_placename[name] = nil
    self:_indexMarks()
    self:_saveMarksCache()
    UIManager:setDirty(self.dialog, "ui")
end

function CharacterTracker:rebuildMarksForObject(entry)
    if not self.ui.document then return end
    if not self.object_mark_enabled then return end
    if not entry.name or entry.name == "" then return end
    local marks = scanRuns(self.ui.document, nameStrings(entry), self:getMatchCap())
    hydrateMarks({ [entry.name] = marks }, "object")
    self.marks_by_objname[entry.name] = marks
    self:_indexMarks()
    self:_saveMarksCache()
    UIManager:setDirty(self.dialog, "ui")
end

function CharacterTracker:removeMarksForObjectName(name)
    self.marks_by_objname[name] = nil
    self:_indexMarks()
    self:_saveMarksCache()
    UIManager:setDirty(self.dialog, "ui")
end

function CharacterTracker:rebuildAllMarks(force)
    if not self.ui.document then return end
    if not (self.mark_enabled or self.place_mark_enabled or self.object_mark_enabled) then
        self.marks_by_charname = {}
        self.marks_by_placename = {}
        self.marks_by_objname = {}
        self.marks_by_page = {}
        self.char_marks = {}
        self.mark_runs = {}
        self.visible_boxes = {}
        return
    end
    self.marks_by_charname = {}
    self.marks_by_placename = {}
    self.marks_by_objname = {}
    self._marks_complete = false

    local have_chars = self.mark_enabled and #self.characters > 0
    local have_places = self.place_mark_enabled and #self.places > 0
    local have_objects = self.object_mark_enabled and #self.compendium > 0
    if not (have_chars or have_places or have_objects) then
        self._marks_complete = true
        self:_indexMarks()
        return
    end

    local t0 = os.clock()
    local fingerprint = self:_computeMarksFingerprint()
    local cap = self:getMatchCap()
    local cache, cached_fp, cached_cap
    if not force then
        cache = self:_loadMarksCache()
        if cache then
            cached_fp, cached_cap = cache.fingerprint, tonumber(cache.cap)
            local legacy_cap, rest = (cached_fp or ""):match("^fmt=2|cap=(%d+)(.*)$")
            if legacy_cap then
                cached_fp = "fmt=2" .. rest
                cached_cap = cached_cap or tonumber(legacy_cap)
            end
        end
        if cache and cached_fp == fingerprint and cached_cap and cached_cap >= cap then
            self.marks_by_charname = cache.characters or {}
            self.marks_by_placename = cache.places or {}
            self.marks_by_objname = cache.objects or {}
            if cached_cap > cap then
                trimBucketsToCap(self.marks_by_charname, cap)
                trimBucketsToCap(self.marks_by_placename, cap)
                trimBucketsToCap(self.marks_by_objname, cap)
            end
            hydrateMarks(self.marks_by_charname, "character")
            hydrateMarks(self.marks_by_placename, "place")
            hydrateMarks(self.marks_by_objname, "object")
            self._marks_complete = true
            self:_indexMarks()
            logger.info(string.format("CharacterTracker: mark cache HIT, loaded in %.2fs", os.clock() - t0))
            UIManager:setDirty(self.dialog, "ui")
            return
        end
    end

    local meta = {}
    if cache and type(cache.meta) == "table" and (cached_fp or ""):sub(1, 5) == "fmt=2" then
        meta = cache.meta
    end

    local kept = { characters = {}, places = {}, objects = {} }
    local pending = { characters = {}, places = {}, objects = {} }

    local function plan(kind, enabled, entities, strings_of, cached_marks)
        if not enabled then return end
        local cached_meta = meta[kind] or {}
        for _i, entity in ipairs(entities) do
            local name = entity.name
            if name and name ~= "" then
                local strings = strings_of(entity)
                local m = cached_meta[name]
                local marks = cached_marks and cached_marks[name]
                local reusable = m and marks and m.sig == table.concat(strings, "\1")
                    and (m.complete or (tonumber(m.cap) or 0) >= cap)
                if reusable then
                    kept[kind][name] = marks
                else
                    pending[kind][#pending[kind] + 1] = { name = name, strings = strings }
                end
            end
        end
    end
    plan("characters", self.mark_enabled, self.characters, characterStrings, cache and cache.characters)
    plan("places", self.place_mark_enabled, self.places, nameStrings, cache and cache.places)
    plan("objects", self.object_mark_enabled, self.compendium, nameStrings, cache and cache.objects)

    trimBucketsToCap(kept.characters, cap)
    trimBucketsToCap(kept.places, cap)
    trimBucketsToCap(kept.objects, cap)

    local to_scan = #pending.characters + #pending.places + #pending.objects
    local completed, results = true, nil
    if to_scan > 0 then
        logger.info(string.format("CharacterTracker: indexing %d name(s) not covered by the saved index", to_scan))
        local Trapper = require("ui/trapper")
        local info = InfoMessage:new{ text = _("Indexing names…") }
        UIManager:show(info)
        UIManager:forceRePaint()
        completed, results = Trapper:dismissableRunInSubprocess(function()
            local doc = self.ui.document
            local out = { characters = {}, places = {}, objects = {} }
            for kind, list in pairs(pending) do
                for _i, item in ipairs(list) do
                    out[kind][item.name] = scanRuns(doc, item.strings, cap)
                end
            end
            return out
        end, info)
        UIManager:close(info)
    end

    if completed then
        for kind, buckets in pairs(results or {}) do
            for name, marks in pairs(buckets) do
                kept[kind][name] = marks
            end
        end
    end

    self.marks_by_charname = kept.characters
    self.marks_by_placename = kept.places
    self.marks_by_objname = kept.objects
    hydrateMarks(self.marks_by_charname, "character")
    hydrateMarks(self.marks_by_placename, "place")
    hydrateMarks(self.marks_by_objname, "object")

    if completed then
        self._marks_complete = true
        self:_saveMarksCache(fingerprint)
        logger.info(string.format("CharacterTracker: index updated in %.2fs (the scan itself runs in a subprocess, so wall clock may differ)", os.clock() - t0))
    end
    self:_indexMarks()
    UIManager:setDirty(self.dialog, "ui")
end

function CharacterTracker:onTapUnderline(ges)
    if not self.visible_boxes or #self.visible_boxes == 0 then
        return false
    end
    local ok, result = pcall(function()
        local pos = self.view:screenToPageTransform(ges.pos)
        if not pos then return false end
        for _i, vbox in ipairs(self.visible_boxes) do
            local r = vbox.rect
            if pos.x >= r.x and pos.y >= r.y
               and pos.x <= r.x + r.w and pos.y <= r.y + r.h then
                if vbox.entity_type == "place" then
                    local place = self:getPlaceByName(vbox.char_name)
                    if place then
                        self:showPlaceDetail(place)
                        return true
                    end
                elseif vbox.entity_type == "object" then
                    local entry = self:getCompendiumEntryByName(vbox.char_name)
                    if entry then
                        self:showCompendiumDetail(entry)
                        return true
                    end
                else
                    local char = self:getCharacterByName(vbox.char_name)
                    if char then
                        if self:isTapOpensReadOnly() then
                            self:showCharacterDetailReadOnly(char)
                        else
                            self:showCharacterDetail(char)
                        end
                        return true
                    end
                end
            end
        end
        return false
    end)
    if not ok then
        logger.warn("CharacterTracker: tap error:", result)
        self.visible_boxes = {}
        return false
    end
    return result
end

function CharacterTracker:getSeriesDir()
    local dir = DataStorage:getDataDir() .. "/character_tracker"
    lfs.mkdir(dir)
    return dir
end

function CharacterTracker:getSeriesName()
    if not self.ui.doc_settings then return nil end
    return self.ui.doc_settings:readSetting("character_tracker_series")
end

function CharacterTracker:setSeriesName(name)
    if not self.ui.doc_settings then return end
    self.ui.doc_settings:saveSetting("character_tracker_series", name)
    self.data_file = nil
    self.places_file = nil
    self.compendium_file = nil
    self.families_file = nil
end

function CharacterTracker:_seriesFileBase(series)
    local base = series:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
    if base == "" then
        local hex = series:gsub(".", function(c) return string.format("%02x", c:byte()) end)
        base = "series_" .. hex:sub(1, 80)
    end
    return base
end

function CharacterTracker:getDataFilePath()
    if self.data_file then return self.data_file end
    local series = self:getSeriesName()
    if series and series ~= "" then
        local safe_name = self:_seriesFileBase(series)
        self.data_file = self:getSeriesDir() .. "/" .. safe_name .. ".json"
    else
        local doc_path = self.ui.document.file
        self.data_file = doc_path .. ".characters.json"
    end
    return self.data_file
end

function CharacterTracker:getPlacesFilePath()
    if self.places_file then return self.places_file end
    local series = self:getSeriesName()
    if series and series ~= "" then
        local safe_name = self:_seriesFileBase(series)
        self.places_file = self:getSeriesDir() .. "/" .. safe_name .. ".places.json"
    else
        local doc_path = self.ui.document.file
        self.places_file = doc_path .. ".places.json"
    end
    return self.places_file
end

function CharacterTracker:loadPlaces()
    self.places = {}
    local path = self:getPlacesFilePath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then
                self.places = data
            else
                logger.warn("CharacterTracker: failed to parse", path)
            end
        end
    end
    for _i, place in ipairs(self.places) do
        if not place.id then place.id = genId() end
        if place.type == nil then place.type = "" end
        if place.description == nil then place.description = "" end
        if place.residents == nil then place.residents = {} end
        if type(place.aliases) ~= "table" then place.aliases = {} end
        if place.status == nil then place.status = "" end
        for _f, field in ipairs({ "facts", "rulers", "features", "connections", "history", "secrets", "notes", "section_order" }) do
            if type(place[field]) ~= "table" then place[field] = {} end
        end
        for _j, c in ipairs(place.connections) do
            if c.travel == nil then c.travel = "" end
            if type(c.notes) ~= "table" then c.notes = {} end
            if type(c.secrets) ~= "table" then c.secrets = {} end
        end
    end
end

function CharacterTracker:savePlaces()
    self._places_dirty = true
    self:_scheduleFlush()
end

function CharacterTracker:getCompendiumFilePath()
    if self.compendium_file then return self.compendium_file end
    local series = self:getSeriesName()
    if series and series ~= "" then
        local safe_name = self:_seriesFileBase(series)
        self.compendium_file = self:getSeriesDir() .. "/" .. safe_name .. ".compendium.json"
    else
        local doc_path = self.ui.document.file
        self.compendium_file = doc_path .. ".compendium.json"
    end
    return self.compendium_file
end

function CharacterTracker:loadCompendium()
    self.compendium = {}
    local path = self:getCompendiumFilePath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then
                self.compendium = data
            else
                logger.warn("CharacterTracker: failed to parse", path)
            end
        end
    end
    for _i, entry in ipairs(self.compendium) do
        if not entry.id then entry.id = genId() end
        if entry.type == nil then entry.type = "" end
        if entry.description == nil then entry.description = "" end
        if entry.age == nil then entry.age = "" end
        if entry.ability == nil then entry.ability = "" end
        if entry.ownership == nil then entry.ownership = {} end
        if entry.hide_from_belongings == nil then entry.hide_from_belongings = false end
        if type(entry.aliases) ~= "table" then entry.aliases = {} end
        if entry.status == nil then entry.status = "" end
        if entry.location_text == nil then entry.location_text = "" end
        for _f, field in ipairs({ "facts", "properties", "limitations", "connections", "history", "secrets", "notes", "section_order" }) do
            if type(entry[field]) ~= "table" then entry[field] = {} end
        end
        for _j, c in ipairs(entry.connections) do
            if type(c.notes) ~= "table" then c.notes = {} end
            if type(c.secrets) ~= "table" then c.secrets = {} end
        end
        local any_explicit_current = false
        for _j, rec in ipairs(entry.ownership) do
            if rec.current ~= nil then any_explicit_current = true end
        end
        for j, rec in ipairs(entry.ownership) do
            if rec.acquired == nil then rec.acquired = rec.how or "" end
            rec.how = nil
            if rec.lost == nil then rec.lost = "" end
            if rec.current == nil then
                rec.current = (not any_explicit_current) and (j == #entry.ownership)
            end
        end
    end
end

function CharacterTracker:saveCompendium()
    self._compendium_dirty = true
    self:_scheduleFlush()
end

function CharacterTracker:getFamiliesFilePath()
    if self.families_file then return self.families_file end
    local series = self:getSeriesName()
    if series and series ~= "" then
        local safe_name = self:_seriesFileBase(series)
        self.families_file = self:getSeriesDir() .. "/" .. safe_name .. ".families.json"
    else
        local doc_path = self.ui.document.file
        self.families_file = doc_path .. ".families.json"
    end
    return self.families_file
end

function CharacterTracker:loadFamilies()
    self.families = {}
    local path = self:getFamiliesFilePath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then
                self.families = data
            else
                logger.warn("CharacterTracker: failed to parse", path)
            end
        end
    end
    for _i, family in ipairs(self.families) do
        if not family.id then family.id = genId() end
        if family.description == nil then family.description = "" end
        if family.members == nil then family.members = {} end
        if family.motto == nil then family.motto = "" end
        if family.seat == nil then family.seat = "" end
        if type(family.notes) ~= "table" then family.notes = {} end
        if type(family.relations) ~= "table" then family.relations = {} end
        if type(family.houses) ~= "table" then family.houses = {} end
        if family.sigil == nil then family.sigil = "" end
        if family.inheritance == nil then family.inheritance = "" end
        if type(family.succession) ~= "table" then family.succession = {} end
        if type(family.traits) ~= "table" then family.traits = {} end
        if type(family.holdings) ~= "table" then family.holdings = {} end
        if type(family.history) ~= "table" then family.history = {} end
        if type(family.secrets) ~= "table" then family.secrets = {} end
        if type(family.section_order) ~= "table" then family.section_order = {} end
        for _j, member in ipairs(family.members) do
            if member.role == nil then member.role = "" end
            if member.tie == nil then member.tie = "" end
            if type(member.parents) ~= "table" then member.parents = {} end
        end
        for _j, rel in ipairs(family.relations) do
            if rel.type == nil then rel.type = "" end
            if rel.sentiment == nil then rel.sentiment = "" end
            if type(rel.notes) ~= "table" then rel.notes = {} end
            if type(rel.secrets) ~= "table" then rel.secrets = {} end
        end
        for _j, house in ipairs(family.houses) do
            if house.kind == nil then house.kind = "" end
            if house.sentiment == nil then house.sentiment = "" end
            if type(house.notes) ~= "table" then house.notes = {} end
            if type(house.secrets) ~= "table" then house.secrets = {} end
        end
        if type(family.placeholders) ~= "table" then family.placeholders = {} end
        if type(family.couple_styles) ~= "table" then family.couple_styles = {} end
        if family.tree_kind ~= "social" then family.tree_kind = "family" end
        if type(family.social_ties) ~= "table" then family.social_ties = {} end
        if type(family.social_groups) ~= "table" then family.social_groups = {} end
        if type(family.social_positions) ~= "table" then family.social_positions = {} end
        if type(family.rel_order) ~= "table" then family.rel_order = {} end
        if type(family.dynamics) ~= "table" then family.dynamics = {} end
        for _j, tie in ipairs(family.social_ties) do
            migrateTieKind(tie, family.social_mode)
            tie.style, tie.mode = nil, nil
            if type(tie.notes) ~= "table" then tie.notes = {} end
            if type(tie.secrets) ~= "table" then tie.secrets = {} end
            if type(tie.note) == "string" and tie.note ~= "" then table.insert(tie.notes, tie.note) end
            tie.note = nil
        end
        family.social_mode = nil
        for _j, group in ipairs(family.social_groups) do
            if type(group.members) ~= "table" then group.members = {} end
        end
        if family.rel_format ~= 2 then
            local migrated = {}
            for _j, rel in ipairs(family.relations) do
                if rel.type ~= "" then
                    table.insert(migrated, {
                        from = rel.to, to = rel.from, type = rel.type, sentiment = "",
                        notes = rel.notes, secrets = rel.secrets,
                    })
                    if rel.sentiment ~= "" then
                        table.insert(migrated, {
                            from = rel.from, to = rel.to, type = "", sentiment = rel.sentiment,
                            notes = {}, secrets = {},
                        })
                    end
                else
                    table.insert(migrated, rel)
                end
            end
            family.relations = migrated
            family.rel_format = 2
        end
    end
end

function CharacterTracker:saveFamilies()
    self._families_dirty = true
    self:_scheduleFlush()
end

function CharacterTracker:getExportsDir()
    local dir = DataStorage:getDataDir() .. "/character_tracker/exports"
    lfs.mkdir(dir)
    return dir
end

function CharacterTracker:showExportDialog()
    local default_name = self:getSeriesName()
    if not default_name and self.ui.document and self.ui.document.file then
        default_name = self.ui.document.file:match("([^/]+)%.%w+$") or "characters"
    end
    default_name = default_name or "characters"

    local dialog
    dialog = InputDialog:new{
        title = _("Export characters"),
        input = default_name,
        input_hint = _("Filename (saved under character_tracker/exports)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Export"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name == "" then return end
                        local safe = name:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
                        local path = self:getExportsDir() .. "/" .. safe .. ".json"
                        local ok, content = pcall(json.encode, self.characters)
                        if ok then
                            local f = io.open(path, "w")
                            if f then
                                f:write(content)
                                f:close()
                                UIManager:show(InfoMessage:new{
                                    text = T(_("Exported %1 characters to:\n%2"), #self.characters, path),
                                    timeout = 3,
                                })
                            else
                                UIManager:show(InfoMessage:new{
                                    text = _("Export failed: cannot write file."),
                                })
                            end
                        else
                            UIManager:show(InfoMessage:new{
                                text = _("Export failed: could not encode data."),
                            })
                        end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showImportDialog()
    local dir = self:getExportsDir()
    local files = {}
    pcall(function()
        for entry in lfs.dir(dir) do
            if entry:match("%.json$") then table.insert(files, entry) end
        end
    end)
    table.sort(files, function(a, b) return a:lower() < b:lower() end)

    local menu_container
    local menu
    local function close_menu()
        UIManager:close(menu_container)
    end
    local item_table = {
        {
            text = _("Other file…"),
            callback = function()
                close_menu()
                self:showImportPathDialog()
            end,
        },
    }
    for _i, file in ipairs(files) do
        table.insert(item_table, {
            text = file,
            callback = function()
                close_menu()
                self:confirmImport(dir .. "/" .. file)
            end,
        })
    end
    menu = Menu:new{
        title = T(_("Import characters (%1)"), dir),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = close_menu,
    }
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

function CharacterTracker:showImportPathDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Import characters"),
        input_hint = _("Full path of the .json file"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Import"),
                    is_enter_default = true,
                    callback = function()
                        local path = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if path ~= "" then self:confirmImport(path) end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:confirmImport(path)
    local name = path:match("([^/]+)%.json$") or path
    UIManager:show(ConfirmBox:new{
        text = T(_("Import characters from '%1'?\nCharacters with the same name will be merged."), name),
        ok_text = _("Import"),
        ok_callback = function()
            local ok, imported, merged = pcall(function()
                local src = self:loadCharactersFromFile(path)
                if type(src) ~= "table" or #src == 0 then return 0, 0 end
                local added = self:mergeCharacters(src)
                self:saveData()
                return #src, added
            end)
            if not ok then
                logger.warn("CharacterTracker: import failed", imported)
                UIManager:show(InfoMessage:new{
                    text = _("Import failed. The file could not be read."),
                })
                return
            end
            if imported == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("No characters found in that file."),
                })
                return
            end
            pcall(function() self:rebuildAllMarks() end)
            UIManager:show(InfoMessage:new{
                text = T(_("Imported %1 characters (%2 new)."), imported, merged),
                timeout = 2,
            })
        end,
    })
end

function CharacterTracker:_normalizeCharacter(char)
    if char.underline == nil then char.underline = true end
    if char.pinned == nil then char.pinned = false end
    if char.char_type == nil then
        char.char_type = char.role or ""
    end
    char.role = nil
    if type(char.aliases) ~= "table" then char.aliases = {} end
    if type(char.notes) ~= "table" then char.notes = {} end
    if type(char.relationships) ~= "table" then char.relationships = {} end
    if char.occupation == nil then char.occupation = "" end
    if char.factions == nil then char.factions = {} end
    if char.tags == nil then char.tags = {} end
    if char.traits == nil then char.traits = {} end
    if char.highlights == nil then char.highlights = {} end
    if type(char.topic_highlights) ~= "table" then char.topic_highlights = {} end
    for _i, entry in ipairs(char.topic_highlights) do
        if type(entry.notes) ~= "table" then entry.notes = {} end
        if type(entry.note) == "string" and entry.note ~= "" then
            table.insert(entry.notes, entry.note)
        end
        entry.note = nil
    end
    if char.residences == nil then char.residences = {} end
    if char.status == nil then char.status = "" end
    if char.appearance == nil then char.appearance = "" end
    if char.age == nil then char.age = "" end
    if char.ability == nil then char.ability = char.power or "" end
    char.power = nil
    if char.secrets == nil then char.secrets = {} end
    if char.skills == nil then char.skills = {} end
    if char.weaknesses == nil then char.weaknesses = {} end
    if char.belongings == nil then char.belongings = {} end
    if char.cause_of_death == nil then char.cause_of_death = "" end
    if char.quote == nil then char.quote = "" end
    if char.last_occurrence == nil then char.last_occurrence = "" end
    char.rating = nil
    for _j, rel in ipairs(char.relationships) do
        if rel.sentiment == nil then rel.sentiment = "" end
        if rel.type == nil then rel.type = "" end
    end
end

function CharacterTracker:loadData()
    self.characters = {}
    local path = self:getDataFilePath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then
                local cleaned = {}
                for _i, char in ipairs(data) do
                    if type(char) == "table" and type(char.name) == "string" and char.name ~= "" then
                        self:_normalizeCharacter(char)
                        table.insert(cleaned, char)
                    end
                end
                self.characters = cleaned
            else
                logger.warn("CharacterTracker: failed to parse", path)
                pcall(os.rename, path, path .. ".corrupt")
            end
        end
    end
    self:_rebuildNameIndex()
end

function CharacterTracker:saveData()
    self._data_dirty = true
    self:_scheduleFlush()
end

function CharacterTracker:_scheduleFlush()
    if self._save_scheduled then return end
    self._save_scheduled = true
    self._flushSaveDataBound = function()
        self._save_scheduled = false
        self:_flushSaveData()
    end
    UIManager:scheduleIn(SAVE_DEBOUNCE_SECONDS, self._flushSaveDataBound)
end

local function _writeJsonFile(path, tbl)
    local ok, content = pcall(json.encode, tbl)
    if not ok then
        logger.warn("CharacterTracker: failed to encode data for", path)
        return false
    end
    local f = io.open(path, "w")
    if f then
        f:write(content)
        f:close()
        return true
    end
    return false
end

function CharacterTracker:getMarksCacheFilePath()
    if self.marks_cache_file then return self.marks_cache_file end
    if not (self.ui and self.ui.document and self.ui.document.file) then return nil end
    self.marks_cache_file = self.ui.document.file .. ".markscache.json"
    return self.marks_cache_file
end

function CharacterTracker:_computeMarksFingerprint()
    local parts = { "fmt=2" }
    if self.mark_enabled then
        local names = {}
        for _i, char in ipairs(self.characters) do
            local a = {}
            for _j, alias in ipairs(char.aliases or {}) do table.insert(a, alias) end
            table.insert(names, (char.name or "") .. "\1" .. table.concat(a, "\2"))
        end
        table.sort(names)
        table.insert(parts, "C[" .. table.concat(names, "\3") .. "]")
    end
    if self.place_mark_enabled then
        local names = {}
        for _i, place in ipairs(self.places) do
            local aliases = place.aliases or {}
            table.insert(names, (place.name or "") .. (#aliases > 0 and ("\1" .. table.concat(aliases, "\2")) or ""))
        end
        table.sort(names)
        table.insert(parts, "P[" .. table.concat(names, "\3") .. "]")
    end
    if self.object_mark_enabled then
        local names = {}
        for _i, entry in ipairs(self.compendium) do
            local aliases = entry.aliases or {}
            table.insert(names, (entry.name or "") .. (#aliases > 0 and ("\1" .. table.concat(aliases, "\2")) or ""))
        end
        table.sort(names)
        table.insert(parts, "O[" .. table.concat(names, "\3") .. "]")
    end
    return table.concat(parts, "|")
end

function CharacterTracker:_loadMarksCache()
    local path = self:getMarksCacheFilePath()
    if not path then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    if not content or content == "" then return nil end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

function CharacterTracker:_saveMarksCache(fingerprint)
    local path = self:getMarksCacheFilePath()
    if not path then return end
    if not self._marks_complete then return end
    _writeJsonFile(path, {
        fingerprint = fingerprint or self:_computeMarksFingerprint(),
        cap = self:getMatchCap(),
        meta = {
            characters = entityMeta(self.marks_by_charname, self.characters, characterStrings, self:getMatchCap()),
            places = entityMeta(self.marks_by_placename, self.places, nameStrings, self:getMatchCap()),
            objects = entityMeta(self.marks_by_objname, self.compendium, nameStrings, self:getMatchCap()),
        },
        characters = slimBuckets(self.marks_by_charname),
        places = slimBuckets(self.marks_by_placename),
        objects = slimBuckets(self.marks_by_objname),
    })
end

function CharacterTracker:_flushSaveData()
    if self._data_dirty then
        if _writeJsonFile(self:getDataFilePath(), self.characters) then
            self._data_dirty = false
        end
    end
    if self._places_dirty then
        if _writeJsonFile(self:getPlacesFilePath(), self.places) then
            self._places_dirty = false
        end
    end
    if self._compendium_dirty then
        if _writeJsonFile(self:getCompendiumFilePath(), self.compendium) then
            self._compendium_dirty = false
        end
    end
    if self._families_dirty then
        if _writeJsonFile(self:getFamiliesFilePath(), self.families) then
            self._families_dirty = false
        end
    end
    if self._timeline_dirty then
        if _writeJsonFile(self:getTimelineFilePath(), self.timelines) then
            self._timeline_dirty = false
        end
    end
end

function CharacterTracker:loadCharactersFromFile(path)
    local f = io.open(path, "r")
    if not f then return {} end
    local content = f:read("*all")
    f:close()
    if not content or content == "" then return {} end
    local ok, data = pcall(json.decode, content)
    if ok and data then return data end
    return {}
end

function CharacterTracker:mergeCharacters(source_chars)
    local merged_count = 0
    for _i, src in ipairs(source_chars) do
      if type(src) == "table" and type(src.name) == "string" and src.name ~= "" then
        self:_normalizeCharacter(src)
        local existing = self:getCharacterByName(src.name)
        if existing then
            if src.aliases then
                if not existing.aliases then existing.aliases = {} end
                for _j, alias in ipairs(src.aliases) do
                    local found = false
                    for _k, ea in ipairs(existing.aliases) do
                        if ea:lower() == alias:lower() then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(existing.aliases, alias)
                    end
                end
            end
            if src.notes then
                if not existing.notes then existing.notes = {} end
                for _j, note in ipairs(src.notes) do
                    local note_text = getNoteText(note)
                    local found = false
                    for _k, en in ipairs(existing.notes) do
                        if getNoteText(en) == note_text then
                            found = true
                            break
                        end
                    end
                    if not found then
                        table.insert(existing.notes, note)
                    end
                end
            end
            local function merge_string_list(field)
                if not src[field] then return end
                if not existing[field] then existing[field] = {} end
                for _j, v in ipairs(src[field]) do
                    local vs = getNoteText(v)
                    local found = false
                    for _k, ev in ipairs(existing[field]) do
                        if getNoteText(ev):lower() == vs:lower() then found = true break end
                    end
                    if not found then table.insert(existing[field], v) end
                end
            end
            merge_string_list("factions")
            merge_string_list("tags")
            merge_string_list("highlights")
            merge_string_list("secrets")
            merge_string_list("skills")
            merge_string_list("weaknesses")
            merge_string_list("belongings")
            for _j, th in ipairs(src.topic_highlights or {}) do
                local found = false
                for _k, eh in ipairs(existing.topic_highlights) do
                    if eh.topic == th.topic and eh.text == th.text then found = true break end
                end
                if not found then table.insert(existing.topic_highlights, th) end
            end
            if src.traits then
                if not existing.traits then existing.traits = {} end
                for _j, t in ipairs(src.traits) do
                    local found = false
                    for _k, et in ipairs(existing.traits) do
                        if (et.trait or ""):lower() == (t.trait or ""):lower() then found = true break end
                    end
                    if not found then table.insert(existing.traits, t) end
                end
            end
            local function fill_if_empty(field)
                if (not existing[field] or existing[field] == "") and src[field] and src[field] ~= "" then
                    existing[field] = src[field]
                end
            end
            fill_if_empty("occupation")
            fill_if_empty("status")
            fill_if_empty("cause_of_death")
            fill_if_empty("appearance")
            fill_if_empty("age")
            fill_if_empty("ability")
            fill_if_empty("quote")
            fill_if_empty("last_occurrence")
            if (not existing.char_type or existing.char_type == "") then
                existing.char_type = src.char_type or src.role or existing.char_type or ""
            end
            if src.relationships then
                if not existing.relationships then existing.relationships = {} end
                for _j, rel in ipairs(src.relationships) do
                    local found = false
                    for _k, er in ipairs(existing.relationships) do
                        if er.target:lower() == rel.target:lower()
                           and (er.type or "") == (rel.type or "") then
                            found = true
                            if (not er.sentiment or er.sentiment == "") and rel.sentiment then
                                er.sentiment = rel.sentiment
                            end
                            break
                        end
                    end
                    if not found then table.insert(existing.relationships, rel) end
                end
            end
        else
            table.insert(self.characters, src)
            merged_count = merged_count + 1
            self:_rebuildNameIndex()
        end
      end
    end
    self:_rebuildNameIndex()
    return merged_count
end

function CharacterTracker:_showInputDialog(dialog)
    UIManager:show(dialog)
    UIManager:nextTick(function()
        if dialog.onShowKeyboard then
            dialog:onShowKeyboard()
        end
    end)
end

function CharacterTracker:getCurrentPage()
    return self.ui:getCurrentPage()
end

function CharacterTracker:getCurrentChapter()
    local page
    if self.ui.rolling then
        page = self.ui.document:getXPointer()
    else
        page = self:getCurrentPage()
    end
    local toc_title = self.ui.toc:getTocTitleByPage(page)
    return toc_title or _("Unknown chapter")
end

function CharacterTracker:getCharacterAppearance(character)
    local marks = self.marks_by_charname[character.name]
    if not marks or #marks == 0 then
        return { count = 0 }
    end
    local count = #marks
    local first_page
    if self.ui.paging then
        for _i, mark in ipairs(marks) do
            if mark.start and (not first_page or mark.start < first_page) then
                first_page = mark.start
            end
        end
    elseif self.ui.rolling and self.ui.document.getPageFromXPointer then
        local ok1, f = pcall(function()
            return self.ui.document:getPageFromXPointer(marks[1].start)
        end)
        if ok1 and f then first_page = f end
    end
    return {
        count = count,
        first_page = first_page,
        first_chapter = first_page and self.ui.toc:getTocTitleByPage(first_page) or nil,
    }
end

function CharacterTracker:_rebuildNameIndex()
    local index = {}
    local no_underline = {}
    for _i, char in ipairs(self.characters) do
        if char.underline == false then
            no_underline[char.name:lower()] = true
        end
        index[char.name:lower()] = char
        if char.aliases then
            for _j, alias in ipairs(char.aliases) do
                if char.underline == false then
                    no_underline[alias:lower()] = true
                end
                index[alias:lower()] = char
            end
        end
    end
    self._name_index = index
    self._no_underline_names = no_underline
end

function CharacterTracker:getCharacterByName(name)
    if not name then return nil end
    return self._name_index[name:lower()]
end

function CharacterTracker:getCharacterIndex(character)
    for i, char in ipairs(self.characters) do
        if char.name == character.name then
            return i
        end
    end
    return nil
end

function CharacterTracker:addCharacter(name, note, callback, occupation)
    if self:getCharacterByName(name) then
        UIManager:show(InfoMessage:new{
            text = T(_("Character '%1' already exists."), name),
        })
        return
    end

    local character = {
        name = name,
        aliases = {},
        notes = {},
        relationships = {},
        occupation = "",
        char_type = "",
        status = "",
        appearance = "",
        age = "",
        ability = "",
        factions = {},
        tags = {},
        traits = {},
        highlights = {},
        topic_highlights = {},
        residences = {},
        secrets = {},
        skills = {},
        weaknesses = {},
        belongings = {},
        cause_of_death = "",
        quote = "",
        last_occurrence = "",
        underline = true,
        created = os.date("%Y-%m-%d %H:%M"),
    }

    if occupation and occupation ~= "" then
        character.occupation = occupation
    end

    if note and note ~= "" then
        table.insert(character.notes, note)
    end

    table.insert(self.characters, character)
    self:_rebuildNameIndex()
    self:saveData()
    self:rebuildMarksForCharacter(character)

    UIManager:show(InfoMessage:new{
        text = T(_("Character '%1' added."), name),
        timeout = 2,
    })

    if callback then callback(character) end
end

function CharacterTracker:showAddCharacterDialog(preselected_name, callback)
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Add new character"),
        fields = {
            {
                text = preselected_name or "",
                hint = _("Character name"),
            },
            {
                text = "",
                hint = _("Occupation (optional) - e.g. blacksmith, queen"),
            },
            {
                text = "",
                hint = _("Note (optional) - e.g. description"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local name = fields[1]:match("^%s*(.-)%s*$")
                        local occupation = fields[2]:match("^%s*(.-)%s*$")
                        local note = fields[3]:match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Name cannot be empty."),
                            })
                            return
                        end
                        self:addCharacter(name, note, callback, occupation)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showNotesManager(character)
    local buttons = {}

    for i, note in ipairs(character.notes or {}) do
        local note_text = getNoteText(note)
        local short = note_text
        short = shorten(short, 40)

        table.insert(buttons, {
            {
                text = short,
                callback = function()
                    UIManager:close(self._notes_dialog)
                    self._notes_dialog = nil
                    self:showEditNoteDialog(character, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._notes_dialog)
                    self._notes_dialog = nil
                    self:confirmDeleteNote(character, i)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("+ Add note"),
            callback = function()
                UIManager:close(self._notes_dialog)
                self._notes_dialog = nil
                self:showAddNoteDialog(character)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._notes_dialog)
                self._notes_dialog = nil
            end,
        },
    })

    self._notes_dialog = ButtonDialog:new{
        title = T(_("Notes - %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._notes_dialog)
end

function CharacterTracker:showAddNoteDialog(character)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Add note to '%1'"), character.name),
        input_hint = _("Write your note here..."),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if text == "" then return end

                        table.insert(character.notes, text)
                        self:saveData()
                        UIManager:show(InfoMessage:new{
                            text = _("Note added."),
                            timeout = 1,
                        })
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showEditNoteDialog(character, note_index)
    local old_text = getNoteText(character.notes[note_index])

    local dialog
    dialog = InputDialog:new{
        title = _("Edit note"),
        input = old_text,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if text == "" then return end

                        character.notes[note_index] = text
                        self:saveData()
                        UIManager:show(InfoMessage:new{
                            text = _("Note updated."),
                            timeout = 1,
                        })
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:confirmDeleteNote(character, note_index)
    local note_text = getNoteText(character.notes[note_index])
    local short = note_text
    short = shorten(short, 50)

    UIManager:show(ConfirmBox:new{
        text = T(_("Delete note?\n\n\"%1\""), short),
        ok_text = _("Delete"),
        ok_callback = function()
            table.remove(character.notes, note_index)
            self:saveData()
            UIManager:show(InfoMessage:new{
                text = _("Note deleted."),
                timeout = 1,
            })
        end,
    })
end

function CharacterTracker:showAliasManager(character)
    if not character.aliases then
        character.aliases = {}
    end

    local buttons = {}

    for i, alias in ipairs(character.aliases) do
        local short = alias
        short = shorten(short, 35)

        table.insert(buttons, {
            {
                text = short,
                callback = function()
                    UIManager:close(self._alias_dialog)
                    self._alias_dialog = nil
                    self:showEditAliasDialog(character, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._alias_dialog)
                    self._alias_dialog = nil
                    self:confirmDeleteAlias(character, i)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("+ Add alias"),
            callback = function()
                UIManager:close(self._alias_dialog)
                self._alias_dialog = nil
                self:showAddAliasDialog(character)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._alias_dialog)
                self._alias_dialog = nil
            end,
        },
    })

    self._alias_dialog = ButtonDialog:new{
        title = T(_("Aliases - %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._alias_dialog)
end

function CharacterTracker:isAliasOrNameTaken(text, exclude_character)
    local match = self._name_index[text:lower()]
    if match and match ~= exclude_character then
        return match.name
    end
    return nil
end

function CharacterTracker:showAddAliasDialog(character)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Add alias for '%1'"), character.name),
        input_hint = _("Alias (nickname, title, etc.)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local alias = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if alias == "" then return end

                        local taken_by = self:isAliasOrNameTaken(alias, character)
                        if taken_by then
                            UIManager:show(InfoMessage:new{
                                text = T(_("'%1' is already used by '%2'."), alias, taken_by),
                            })
                            return
                        end

                        if character.aliases then
                            for _i, existing in ipairs(character.aliases) do
                                if existing:lower() == alias:lower() then
                                    UIManager:show(InfoMessage:new{
                                        text = T(_("Alias '%1' already exists."), alias),
                                    })
                                    return
                                end
                            end
                        end

                        if not character.aliases then
                            character.aliases = {}
                        end
                        table.insert(character.aliases, alias)
                        self:_rebuildNameIndex()
                        self:saveData()
                        self:rebuildMarksForCharacter(character)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Alias '%1' added."), alias),
                            timeout = 1,
                        })
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showEditAliasDialog(character, alias_index)
    local old_alias = character.aliases[alias_index]
    local dialog
    dialog = InputDialog:new{
        title = _("Edit alias"),
        input = old_alias,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local alias = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if alias == "" then return end

                        if alias:lower() ~= old_alias:lower() then
                            local taken_by = self:isAliasOrNameTaken(alias, character)
                            if taken_by then
                                UIManager:show(InfoMessage:new{
                                    text = T(_("'%1' is already used by '%2'."), alias, taken_by),
                                })
                                return
                            end
                            for i, existing in ipairs(character.aliases) do
                                if i ~= alias_index and existing:lower() == alias:lower() then
                                    UIManager:show(InfoMessage:new{
                                        text = T(_("Alias '%1' already exists."), alias),
                                    })
                                    return
                                end
                            end
                        end

                        character.aliases[alias_index] = alias
                        self:_rebuildNameIndex()
                        self:saveData()
                        self:rebuildMarksForCharacter(character)
                        UIManager:show(InfoMessage:new{
                            text = T(_("Alias updated to '%1'."), alias),
                            timeout = 1,
                        })
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:confirmDeleteAlias(character, alias_index)
    local alias = character.aliases[alias_index]
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete alias '%1'?"), alias),
        ok_text = _("Delete"),
        ok_callback = function()
            table.remove(character.aliases, alias_index)
            self:_rebuildNameIndex()
            self:saveData()
            self:rebuildMarksForCharacter(character)
            UIManager:show(InfoMessage:new{
                text = T(_("Alias '%1' deleted."), alias),
                timeout = 1,
            })
        end,
    })
end

function CharacterTracker:showRelationshipManager(character)
    if not character.relationships then
        character.relationships = {}
    end

    local buttons = {}

    for i, rel in ipairs(character.relationships) do
        local label = getRelationshipLabel(rel.type)
        if not rel.type or rel.type == "" then
            label = _("(sentiment only)")
        end
        local sent_label = getSentimentLabel(rel.sentiment)
        local display = rel.target .. " — " .. label
        if sent_label then
            display = display .. " · " .. sent_label
        end
        display = shorten(display, 42)

        table.insert(buttons, {
            {
                text = display,
                callback = function()
                    UIManager:close(self._rel_dialog)
                    self._rel_dialog = nil
                    self:showRelationshipEntryActions(character, i)
                end,
                hold_callback = function()
                    local target_char = self:getCharacterByName(rel.target)
                    if target_char then
                        UIManager:close(self._rel_dialog)
                        self._rel_dialog = nil
                        self:showCharacterDetail(target_char)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("Character '%1' not found."), rel.target),
                        })
                    end
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._rel_dialog)
                    self._rel_dialog = nil
                    self:confirmDeleteRelationship(character, i)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("+ Add relationship"),
            callback = function()
                UIManager:close(self._rel_dialog)
                self._rel_dialog = nil
                self:showAddRelationshipPicker(character)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._rel_dialog)
                self._rel_dialog = nil
            end,
        },
    })

    self._rel_dialog = ButtonDialog:new{
        title = T(_("Relationships - %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._rel_dialog)
end

function CharacterTracker:showAddRelationshipPicker(character)
    local buttons = {}
    local row = {}

    for _i, char in ipairs(self.characters) do
        if char.name ~= character.name then
            table.insert(row, {
                text = char.name,
                callback = function()
                    UIManager:close(self._rel_picker)
                    self._rel_picker = nil
                    self:showRelationshipTypePicker(character, char.name)
                end,
            })
            if #row >= 2 then
                table.insert(buttons, row)
                row = {}
            end
        end
    end
    if #row > 0 then
        table.insert(buttons, row)
    end

    if #buttons == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No other characters to link. Add more characters first."),
        })
        return
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._rel_picker)
                self._rel_picker = nil
            end,
        },
    })

    self._rel_picker = ButtonDialog:new{
        title = T(_("Add relationship from '%1' to…"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._rel_picker)
end

function CharacterTracker:showRelationshipTypePicker(character, target_name)
    local buttons = {}
    local row = {}

    for _i, rt in ipairs(RELATIONSHIP_TYPES) do
        if rt.key == "custom" then
        else
            table.insert(row, {
                text = rt.label,
                callback = function()
                    UIManager:close(self._rel_type_picker)
                    self._rel_type_picker = nil
                    self:showRelationshipSentimentPicker(character, target_name, rt.key)
                end,
            })
            if #row >= 3 then
                table.insert(buttons, row)
                row = {}
            end
        end
    end
    if #row > 0 then
        table.insert(buttons, row)
    end

    table.insert(buttons, {
        {
            text = _("Custom…"),
            callback = function()
                UIManager:close(self._rel_type_picker)
                self._rel_type_picker = nil
                self:showCustomRelationshipDialog(character, target_name)
            end,
        },
    })

    table.insert(buttons, {
        {
            text = _("— none (sentiment only) —"),
            callback = function()
                UIManager:close(self._rel_type_picker)
                self._rel_type_picker = nil
                self:showRelationshipSentimentPicker(character, target_name, "")
            end,
        },
    })

    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._rel_type_picker)
                self._rel_type_picker = nil
            end,
        },
    })

    self._rel_type_picker = ButtonDialog:new{
        title = T(_("'%1' is ___ of '%2'"), target_name, character.name),
        buttons = buttons,
    }
    UIManager:show(self._rel_type_picker)
end

function CharacterTracker:showCustomRelationshipDialog(character, target_name)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Custom relationship: '%1' → '%2'"), character.name, target_name),
        input_hint = _("Relationship (e.g. squire, rival, betrothed)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local rel_type = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if rel_type == "" then return end
                        self:showRelationshipSentimentPicker(character, target_name, rel_type)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showRelationshipSentimentPicker(character, target_name, rel_type, rel_index)
    local buttons = {}
    local row = {}
    for _i, st in ipairs(SENTIMENT_TYPES) do
        if st.key ~= "custom" then
            table.insert(row, {
                text = st.label,
                callback = function()
                    UIManager:close(self._rel_sent_picker)
                    self._rel_sent_picker = nil
                    self:_commitRelationship(character, target_name, rel_type, st.key, rel_index)
                end,
            })
            if #row >= 3 then
                table.insert(buttons, row)
                row = {}
            end
        end
    end
    if #row > 0 then
        table.insert(buttons, row)
    end

    table.insert(buttons, {
        {
            text = _("Custom sentiment…"),
            callback = function()
                UIManager:close(self._rel_sent_picker)
                self._rel_sent_picker = nil
                self:showCustomSentimentDialog(character, target_name, rel_type, rel_index)
            end,
        },
    })
    table.insert(buttons, {
        {
            text = rel_index and _("Clear sentiment") or _("Skip (no sentiment)"),
            callback = function()
                UIManager:close(self._rel_sent_picker)
                self._rel_sent_picker = nil
                self:_commitRelationship(character, target_name, rel_type, "", rel_index)
            end,
        },
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._rel_sent_picker)
                self._rel_sent_picker = nil
            end,
        },
    })

    self._rel_sent_picker = ButtonDialog:new{
        title = T(_("How does '%1' feel about '%2'?"), character.name, target_name),
        buttons = buttons,
    }
    UIManager:show(self._rel_sent_picker)
end

function CharacterTracker:showCustomSentimentDialog(character, target_name, rel_type, rel_index)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Custom sentiment: '%1' → '%2'"), character.name, target_name),
        input_hint = _("e.g. jealous of, indebted to, wary of"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local sentiment = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if sentiment == "" then return end
                        self:_commitRelationship(character, target_name, rel_type, sentiment, rel_index)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:_commitRelationship(character, target_name, rel_type, sentiment, rel_index)
    if not character.relationships then
        character.relationships = {}
    end

    if rel_index then
        local rel = character.relationships[rel_index]
        if rel then
            if rel_type ~= nil then rel.type = rel_type end
            rel.sentiment = sentiment or ""
        end
        self:saveData()
        UIManager:show(InfoMessage:new{ text = _("Relationship updated."), timeout = 1 })
        return
    end

    for _i, rel in ipairs(character.relationships) do
        if rel.target:lower() == target_name:lower() and (rel.type or "") == (rel_type or "") then
            if sentiment and sentiment ~= "" then
                rel.sentiment = sentiment
            end
            self:saveData()
            UIManager:show(InfoMessage:new{
                text = _("Updated existing relationship."),
                timeout = 1,
            })
            return
        end
    end

    table.insert(character.relationships, {
        target = target_name,
        type = rel_type or "",
        sentiment = sentiment or "",
    })
    self:saveData()

    local label = (rel_type and rel_type ~= "") and getRelationshipLabel(rel_type) or _("(sentiment only)")
    UIManager:show(InfoMessage:new{
        text = T(_("Linked '%1' → '%2' (%3)."), character.name, target_name, label),
        timeout = 2,
    })
end

function CharacterTracker:showRelationshipEntryActions(character, rel_index)
    local rel = character.relationships[rel_index]
    if not rel then return end
    local buttons = {
        {
            {
                text = T(_("Open '%1'"), rel.target),
                callback = function()
                    UIManager:close(self._rel_entry_dialog)
                    self._rel_entry_dialog = nil
                    local target_char = self:getCharacterByName(rel.target)
                    if target_char then
                        self:showCharacterDetail(target_char)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("Character '%1' not found."), rel.target),
                        })
                    end
                end,
            },
        },
        {
            {
                text = _("Change relationship type"),
                callback = function()
                    UIManager:close(self._rel_entry_dialog)
                    self._rel_entry_dialog = nil
                    self:showChangeRelationshipTypePicker(character, rel_index)
                end,
            },
        },
        {
            {
                text = getSentimentLabel(rel.sentiment) and _("Change sentiment") or _("Add sentiment"),
                callback = function()
                    UIManager:close(self._rel_entry_dialog)
                    self._rel_entry_dialog = nil
                    self:showRelationshipSentimentPicker(character, rel.target, rel.type, rel_index)
                end,
            },
        },
        {
            {
                text = _("Delete"),
                callback = function()
                    UIManager:close(self._rel_entry_dialog)
                    self._rel_entry_dialog = nil
                    self:confirmDeleteRelationship(character, rel_index)
                end,
            },
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(self._rel_entry_dialog)
                    self._rel_entry_dialog = nil
                end,
            },
        },
    }
    self._rel_entry_dialog = ButtonDialog:new{
        title = T(_("%1 → %2"), character.name, rel.target),
        buttons = buttons,
    }
    UIManager:show(self._rel_entry_dialog)
end

function CharacterTracker:showChangeRelationshipTypePicker(character, rel_index)
    local rel = character.relationships[rel_index]
    if not rel then return end
    local buttons = {}
    local row = {}
    for _i, rt in ipairs(RELATIONSHIP_TYPES) do
        if rt.key ~= "custom" then
            table.insert(row, {
                text = rt.label,
                callback = function()
                    UIManager:close(self._rel_change_picker)
                    self._rel_change_picker = nil
                    self:_commitRelationship(character, rel.target, rt.key, rel.sentiment, rel_index)
                end,
            })
            if #row >= 3 then
                table.insert(buttons, row)
                row = {}
            end
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Custom…"),
            callback = function()
                UIManager:close(self._rel_change_picker)
                self._rel_change_picker = nil
                local dialog
                dialog = InputDialog:new{
                    title = _("Custom relationship type"),
                    input = (rel.type ~= "" and getRelationshipLabel(rel.type)) or "",
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                        { text = _("Save"), is_enter_default = true, callback = function()
                            local t = dialog:getInputText():match("^%s*(.-)%s*$")
                            UIManager:close(dialog)
                            if t == "" then return end
                            self:_commitRelationship(character, rel.target, t, rel.sentiment, rel_index)
                        end },
                    }},
                }
                self:_showInputDialog(dialog)
            end,
        },
        {
            text = _("— none (sentiment only) —"),
            callback = function()
                UIManager:close(self._rel_change_picker)
                self._rel_change_picker = nil
                self:_commitRelationship(character, rel.target, "", rel.sentiment, rel_index)
            end,
        },
    })
    self._rel_change_picker = ButtonDialog:new{
        title = T(_("'%1' is ___ of '%2'"), rel.target, character.name),
        buttons = buttons,
    }
    UIManager:show(self._rel_change_picker)
end

function CharacterTracker:confirmDeleteRelationship(character, rel_index)
    local rel = character.relationships[rel_index]
    local label = (rel.type and rel.type ~= "") and getRelationshipLabel(rel.type) or _("(sentiment only)")

    UIManager:show(ConfirmBox:new{
        text = T(_("Delete link?\n\n%1 → %2 (%3)"), character.name, rel.target, label),
        ok_text = _("Delete"),
        ok_callback = function()
            table.remove(character.relationships, rel_index)
            self:saveData()
            UIManager:show(InfoMessage:new{
                text = _("Relationship deleted."),
                timeout = 1,
            })
        end,
    })
end

function CharacterTracker:buildRelationshipSummary(character)
    local by_target = {}
    local order = {}
    local function bucket(name)
        local k = name:lower()
        if not by_target[k] then
            by_target[k] = { name = name, out_types = {}, in_types = {},
                             out_sent = {}, in_sent = {} }
            table.insert(order, k)
        end
        return by_target[k]
    end

    for _i, rel in ipairs(character.relationships or {}) do
        local b = bucket(rel.target)
        if rel.type and rel.type ~= "" then b.out_types[rel.type] = true end
        if rel.sentiment and rel.sentiment ~= "" then b.out_sent[rel.sentiment] = true end
    end

    local self_lower = character.name:lower()
    for _i, char in ipairs(self.characters) do
        if char.name:lower() ~= self_lower and char.relationships then
            for _j, rel in ipairs(char.relationships) do
                if rel.target:lower() == self_lower then
                    local b = bucket(char.name)
                    if rel.type and rel.type ~= "" then b.in_types[rel.type] = true end
                    if rel.sentiment and rel.sentiment ~= "" then b.in_sent[rel.sentiment] = true end
                end
            end
        end
    end

    return self:_formatRelationBuckets(order, by_target)
end

function CharacterTracker:_formatRelationBuckets(order, by_target)
    local function merge_tokens(outset, inset, labelfn)
        local keys = {}
        for kk in pairs(outset) do keys[kk] = true end
        for kk in pairs(inset) do keys[kk] = true end
        local sorted = {}
        for kk in pairs(keys) do table.insert(sorted, kk) end
        table.sort(sorted, function(a, b)
            return (labelfn(a) or a):lower() < (labelfn(b) or b):lower()
        end)
        local parts = {}
        for _x, kk in ipairs(sorted) do
            local dir
            if outset[kk] and inset[kk] then dir = " ↔"
            elseif outset[kk] then dir = " →"
            else dir = " ←" end
            table.insert(parts, (labelfn(kk) or kk) .. dir)
        end
        return parts
    end

    local sentence = self:getRelationshipStyle() == "sentence"

    local function sorted_union(outset, inset)
        local keys = {}
        for kk in pairs(outset) do keys[kk] = true end
        for kk in pairs(inset) do keys[kk] = true end
        local sorted = {}
        for kk in pairs(keys) do table.insert(sorted, kk) end
        table.sort(sorted, function(a, b)
            return (getRelationshipLabel(a) or a):lower() < (getRelationshipLabel(b) or b):lower()
        end)
        return sorted
    end

    local lines = {}
    for _i, k in ipairs(order) do
        local b = by_target[k]
        local sent_parts = merge_tokens(b.out_sent, b.in_sent, getSentimentLabel)
        local line
        if sentence then
            local out_list, in_list = {}, {}
            for _x, kk in ipairs(sorted_union(b.out_types, b.in_types)) do
                local label = (getRelationshipLabel(kk) or kk):lower()
                if b.out_types[kk] then
                    table.insert(out_list, label)
                else
                    table.insert(in_list, label .. " " .. _("of") .. " " .. b.name)
                end
            end
            local clauses = {}
            if #out_list > 0 then
                table.insert(clauses, b.name .. " " .. _("is their") .. " " .. table.concat(out_list, ", "))
            end
            if #in_list > 0 then
                table.insert(clauses, table.concat(in_list, ", "))
            end
            if #clauses > 0 then
                line = table.concat(clauses, "; ")
            else
                line = b.name .. ": " .. _("(linked)")
            end
        else
            local type_parts = merge_tokens(b.out_types, b.in_types, getRelationshipLabel)
            line = b.name .. ": "
            if #type_parts > 0 then
                line = line .. table.concat(type_parts, ", ")
            else
                line = line .. _("(linked)")
            end
        end
        if #sent_parts > 0 then
            line = line .. "  —  " .. table.concat(sent_parts, ", ")
        end
        table.insert(lines, line)
    end
    return lines
end

function CharacterTracker:getRelationshipStyle()
    if G_reader_settings ~= nil
       and G_reader_settings:readSetting("character_tracker_relationship_style") == "sentence" then
        return "sentence"
    end
    return "compact"
end

function CharacterTracker:showRelationshipStyleDialog()
    local current = self:getRelationshipStyle()
    local options = {
        { key = "compact", label = _("Compact (e.g. Fred: son →)") },
        { key = "sentence", label = _("Sentence (e.g. Fred is their son / son of Ted)") },
    }
    local buttons = {}
    for _i, opt in ipairs(options) do
        table.insert(buttons, {
            {
                text = (current == opt.key and "✓ " or "") .. opt.label,
                callback = function()
                    UIManager:close(self._rel_style_dialog)
                    self._rel_style_dialog = nil
                    if G_reader_settings then
                        G_reader_settings:saveSetting("character_tracker_relationship_style", opt.key)
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._rel_style_dialog)
                self._rel_style_dialog = nil
            end,
        },
    })
    self._rel_style_dialog = ButtonDialog:new{
        title = _("How relationships are written"),
        buttons = buttons,
    }
    UIManager:show(self._rel_style_dialog)
end

function CharacterTracker:_relatedCharacters(character)
    local related, seen = {}, {}
    local function add(char)
        if char and char ~= character and not seen[char] then
            seen[char] = true
            table.insert(related, char)
        end
    end
    for _i, rel in ipairs(character.relationships or {}) do
        add(self:getCharacterByName(rel.target))
    end
    local self_lower = character.name:lower()
    for _i, char in ipairs(self.characters) do
        for _j, rel in ipairs(char.relationships or {}) do
            if rel.target and rel.target:lower() == self_lower then
                add(char)
                break
            end
        end
    end
    return related
end

function CharacterTracker:_onRelationshipHold(character, viewer, readonly, text)
    local selected = ((text or ""):gsub("^[%s%p]+", ""):gsub("[%s%p]+$", ""))
    local needle = selected:lower()

    local function open(char)
        if viewer then UIManager:close(viewer) end
        if readonly then
            self:showCharacterDetailReadOnly(char)
        else
            self:showCharacterDetail(char)
        end
    end

    local exact
    local candidates = {}
    if needle ~= "" then
        for _i, char in ipairs(self:_relatedCharacters(character)) do
            local names = { char.name }
            for _j, alias in ipairs(char.aliases or {}) do
                table.insert(names, alias)
            end
            local matched = false
            for _j, name in ipairs(names) do
                local lowered = name:lower()
                if lowered == needle then
                    exact = char
                    matched = true
                    break
                end
                for word in lowered:gmatch("%S+") do
                    if (word:gsub("^%p+", ""):gsub("%p+$", "")) == needle then
                        matched = true
                    end
                end
            end
            if matched then table.insert(candidates, char) end
        end
    end

    if exact then
        open(exact)
    elseif #candidates == 1 then
        open(candidates[1])
    elseif #candidates > 1 then
        local buttons = {}
        for _i, char in ipairs(candidates) do
            table.insert(buttons, {
                {
                    text = char.name,
                    callback = function()
                        UIManager:close(self._rel_hold_dialog)
                        self._rel_hold_dialog = nil
                        open(char)
                    end,
                },
            })
        end
        table.insert(buttons, {
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(self._rel_hold_dialog)
                    self._rel_hold_dialog = nil
                end,
            },
        })
        self._rel_hold_dialog = ButtonDialog:new{
            title = _("Open which character?"),
            buttons = buttons,
        }
        UIManager:show(self._rel_hold_dialog)
    elseif text and text ~= "" then
        pcall(function() Device.input.setClipboardText(text) end)
        UIManager:show(InfoMessage:new{
            text = _("Copied to clipboard."),
            timeout = 1,
        })
    end
end

function CharacterTracker:getIncomingRelationships(character)
    local incoming = {}
    local name_lower = character.name:lower()
    for _i, char in ipairs(self.characters) do
        if char.name ~= character.name and char.relationships then
            for _j, rel in ipairs(char.relationships) do
                if rel.target:lower() == name_lower then
                    table.insert(incoming, {
                        source = char.name,
                        type = rel.type,
                    })
                end
            end
        end
    end
    return incoming
end

function CharacterTracker:_buildIncomingRelationshipsMap()
    local map = {}
    for _i, char in ipairs(self.characters) do
        if char.relationships then
            for _j, rel in ipairs(char.relationships) do
                local key = rel.target:lower()
                if not map[key] then map[key] = {} end
                table.insert(map[key], { source = char.name, type = rel.type })
            end
        end
    end
    return map
end

function CharacterTracker:deleteCharacter(character)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete character '%1' and all associated data?"), character.name),
        ok_text = _("Delete"),
        ok_callback = function()
            local idx = self:getCharacterIndex(character)
            if idx then
                local snapshot = {
                    character = character,
                    incoming = {},
                    residents = {},
                }
                local char_name_lower = character.name:lower()
                for _i, char in ipairs(self.characters) do
                    if char.relationships then
                        for j = #char.relationships, 1, -1 do
                            if char.relationships[j].target:lower() == char_name_lower then
                                table.insert(snapshot.incoming, {
                                    char = char,
                                    rel = char.relationships[j],
                                })
                                table.remove(char.relationships, j)
                            end
                        end
                    end
                end
                local places_touched = false
                for _i, place in ipairs(self.places or {}) do
                    if place.residents then
                        for j = #place.residents, 1, -1 do
                            if (place.residents[j].name or ""):lower() == char_name_lower then
                                table.insert(snapshot.residents, {
                                    place = place,
                                    resident = place.residents[j],
                                })
                                table.remove(place.residents, j)
                                places_touched = true
                            end
                        end
                    end
                end
                if places_touched then self:savePlaces() end
                table.remove(self.characters, idx)
                table.insert(self._trash, snapshot)
                while #self._trash > 5 do
                    table.remove(self._trash, 1)
                end
                self:_rebuildNameIndex()
                self:saveData()
                self:removeMarksForCharacterName(character.name)
                UIManager:show(InfoMessage:new{
                    text = T(_("Character '%1' deleted.\nUse 'Undo last delete' to restore."), character.name),
                    timeout = 3,
                })
            end
        end,
    })
end

function CharacterTracker:restoreLastDeleted()
    local snapshot = table.remove(self._trash)
    if not snapshot then
        UIManager:show(InfoMessage:new{
            text = _("Nothing to restore."),
        })
        return
    end
    local clash = self:getCharacterByName(snapshot.character.name)
    if clash then
        table.insert(self._trash, snapshot)
        UIManager:show(InfoMessage:new{
            text = T(_("Can't restore '%1': that name is now used by '%2'. Rename or delete that one first."),
                snapshot.character.name, clash.name),
        })
        return
    end
    table.insert(self.characters, snapshot.character)
    for _i, entry in ipairs(snapshot.incoming) do
        if entry.char.relationships then
            table.insert(entry.char.relationships, entry.rel)
        end
    end
    if snapshot.residents then
        for _i, entry in ipairs(snapshot.residents) do
            if entry.place.residents then
                table.insert(entry.place.residents, entry.resident)
            end
        end
        if #snapshot.residents > 0 then self:savePlaces() end
    end
    self:_rebuildNameIndex()
    self:saveData()
    if self.mark_enabled then
        self:rebuildMarksForCharacter(snapshot.character)
    end
    UIManager:show(InfoMessage:new{
        text = T(_("Restored character '%1'."), snapshot.character.name),
        timeout = 2,
    })
end

function CharacterTracker:showRenameDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Rename '%1'"), character.name),
        input = character.name,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local new_name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if new_name == "" or new_name == character.name then return end

                        local taken_by = self:isAliasOrNameTaken(new_name, character)
                        if taken_by then
                            UIManager:show(InfoMessage:new{
                                text = T(_("'%1' is already used by '%2'."), new_name, taken_by),
                            })
                            return
                        end

                        local old_name = character.name
                        local old_name_lower = old_name:lower()

                        for _i, char in ipairs(self.characters) do
                            if char.relationships then
                                for _j, rel in ipairs(char.relationships) do
                                    if rel.target:lower() == old_name_lower then
                                        rel.target = new_name
                                    end
                                end
                            end
                        end

                        local places_touched = false
                        for _i, place in ipairs(self.places or {}) do
                            for _j, resident in ipairs(place.residents or {}) do
                                if resident.name and resident.name:lower() == old_name_lower then
                                    resident.name = new_name
                                    places_touched = true
                                end
                            end
                        end
                        if places_touched then self:savePlaces() end

                        local compendium_touched = false
                        for _i, entry in ipairs(self.compendium or {}) do
                            for _j, rec in ipairs(entry.ownership or {}) do
                                if rec.owner and rec.owner:lower() == old_name_lower then
                                    rec.owner = new_name
                                    compendium_touched = true
                                end
                            end
                        end
                        if compendium_touched then self:saveCompendium() end

                        local timeline_touched = false
                        for _i, tl in ipairs(self.timelines or {}) do
                            for _j, event in ipairs(tl.events or {}) do
                                for k, name in ipairs(event.characters or {}) do
                                    if name:lower() == old_name_lower then
                                        event.characters[k] = new_name
                                        timeline_touched = true
                                    end
                                end
                            end
                        end
                        if timeline_touched then self:saveTimeline() end

                        local families_touched = false
                        for _i, family in ipairs(self.families or {}) do
                            for _j, member in ipairs(family.members or {}) do
                                if member.name and member.name:lower() == old_name_lower then
                                    member.name = new_name
                                    families_touched = true
                                end
                            end
                            for _j, rel in ipairs(family.relations or {}) do
                                if rel.from and rel.from:lower() == old_name_lower then
                                    rel.from = new_name
                                    families_touched = true
                                end
                                if rel.to and rel.to:lower() == old_name_lower then
                                    rel.to = new_name
                                    families_touched = true
                                end
                            end
                            for _j, member in ipairs(family.members or {}) do
                                for k, parent in ipairs(member.parents or {}) do
                                    if parent:lower() == old_name_lower then
                                        self:_renameParentKind(member, parent, new_name)
                                        member.parents[k] = new_name
                                        families_touched = true
                                    end
                                end
                            end
                            for _j, entry in ipairs(family.succession or {}) do
                                if entry.name and entry.name:lower() == old_name_lower then
                                    entry.name = new_name
                                    families_touched = true
                                end
                            end
                            for k, name in ipairs(family.section_order or {}) do
                                if name:lower() == old_name_lower then
                                    family.section_order[k] = new_name
                                    families_touched = true
                                end
                            end
                            self:_renameCoupleStyleKeys(family, old_name_lower, new_name)
                            for _j, tie in ipairs(family.social_ties or {}) do
                                if tie.from and tie.from:lower() == old_name_lower then tie.from = new_name families_touched = true end
                                if tie.to and tie.to:lower() == old_name_lower then tie.to = new_name families_touched = true end
                            end
                        end
                        if families_touched then self:saveFamilies() end

                        character.name = new_name
                        self:_rebuildNameIndex()
                        self:saveData()
                        self:removeMarksForCharacterName(old_name)
                        self:rebuildMarksForCharacter(character)

                        UIManager:show(InfoMessage:new{
                            text = T(_("Renamed '%1' → '%2'."), old_name, new_name),
                            timeout = 2,
                        })

                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showOccupationDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Occupation of '%1'"), character.name),
        input = character.occupation or "",
        input_hint = _("e.g. blacksmith, court physician, king"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        character.occupation = ""
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        character.occupation = text
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCharacterTypeDialog(character, on_done)
    local buttons = {}
    for _i, type_def in ipairs(CHARACTER_TYPES) do
        table.insert(buttons, {
            {
                text = type_def.label,
                callback = function()
                    UIManager:close(self._char_type_dialog)
                    self._char_type_dialog = nil
                    character.char_type = type_def.key
                    self:saveData()
                    if on_done then on_done() end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Custom…"),
            callback = function()
                UIManager:close(self._char_type_dialog)
                self._char_type_dialog = nil
                local dialog
                dialog = InputDialog:new{
                    title = T(_("Custom character type for '%1'"), character.name),
                    input = character.char_type or "",
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                        { text = _("Save"), is_enter_default = true, callback = function()
                            local t = dialog:getInputText():match("^%s*(.-)%s*$")
                            UIManager:close(dialog)
                            character.char_type = t
                            self:saveData()
                            if on_done then on_done() end
                        end },
                    }},
                }
                self:_showInputDialog(dialog)
            end,
        },
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._char_type_dialog)
                self._char_type_dialog = nil
            end,
        },
    })
    self._char_type_dialog = ButtonDialog:new{
        title = T(_("Character type of '%1'"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._char_type_dialog)
end

function CharacterTracker:isTypeHidden()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_type")
end

function CharacterTracker:isAgeHidden()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_age")
end

function CharacterTracker:isAbilityHidden()
    if LayoutSettings ~= nil and LayoutSettings:isTrue("character_tracker_hide_ability") then
        LayoutSettings:saveSetting("character_tracker_hide_ability", false)
        self:setCharacterSectionHidden("ability", true)
    end
    return self:isCharacterSectionHidden("ability")
end

function CharacterTracker:isAppearanceHidden()
    return self:isCharacterSectionHidden("appearance")
end

function CharacterTracker:isBelongingsHidden()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_belongings")
end

function CharacterTracker:isLastSeenHidden()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_last_seen")
end

function CharacterTracker:isSelectionOptionHidden(kind)
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_selection_" .. kind)
end

function CharacterTracker:isIndexLimitWarningHidden()
    if G_reader_settings == nil then return true end
    local value = G_reader_settings:readSetting("character_tracker_hide_index_limit_warning")
    return value == nil or value == true
end

function CharacterTracker:isFamilyHidden()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_family")
end

function CharacterTracker:isShortTreeLabel()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_short_tree_label")
end

function CharacterTracker:isReadOnlyTreeButtonHidden()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_readonly_tree_button")
end

function CharacterTracker:isReadOnlyEditButtonHidden()
    return G_reader_settings ~= nil
        and LayoutSettings:isTrue("character_tracker_hide_readonly_edit_button")
end

function CharacterTracker:isTapOpensEdit()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tap_opens_edit")
end

function CharacterTracker:isTapOpensReadOnly()
    return not self:isTapOpensEdit()
end

function CharacterTracker:showStatusDialog(character, on_done)
    local buttons = {}
    for _i, status_def in ipairs(STATUS_TYPES) do
        table.insert(buttons, {
            {
                text = status_def.label,
                callback = function()
                    UIManager:close(self._status_dialog)
                    self._status_dialog = nil
                    if status_def.key == "custom" then
                        local dialog
                        dialog = InputDialog:new{
                            title = T(_("Custom status for '%1'"), character.name),
                            input = character.status or "",
                            input_hint = _("e.g. presumed dead, cursed, exiled"),
                            buttons = {{
                                { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                                { text = _("Save"), is_enter_default = true, callback = function()
                                    local t = dialog:getInputText():match("^%s*(.-)%s*$")
                                    UIManager:close(dialog)
                                    if t ~= "" then
                                        character.status = t
                                        self:saveData()
                                    end
                                    if on_done then on_done() end
                                end },
                            }},
                        }
                        self:_showInputDialog(dialog)
                    elseif status_def.key == "dead" then
                        character.status = "dead"
                        self:saveData()
                        self:showCauseOfDeathDialog(character, on_done)
                    else
                        character.status = status_def.key
                        self:saveData()
                        if on_done then on_done() end
                    end
                end,
            },
        })
    end
    if character.status == "dead" then
        table.insert(buttons, {
            {
                text = character.cause_of_death and character.cause_of_death ~= ""
                    and _("Edit cause of death") or _("Add cause of death"),
                callback = function()
                    UIManager:close(self._status_dialog)
                    self._status_dialog = nil
                    self:showCauseOfDeathDialog(character, on_done)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Clear status"),
            callback = function()
                UIManager:close(self._status_dialog)
                self._status_dialog = nil
                character.status = ""
                self:saveData()
                if on_done then on_done() end
            end,
        },
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._status_dialog)
                self._status_dialog = nil
            end,
        },
    })
    self._status_dialog = ButtonDialog:new{
        title = T(_("Status of '%1'"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._status_dialog)
end

function CharacterTracker:showCauseOfDeathDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Cause of death — %1 (optional)"), character.name),
        input = character.cause_of_death or "",
        input_hint = _("e.g. stabbed in the throne room, fever, unknown"),
        buttons = {
            {
                {
                    text = _("Skip"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        character.cause_of_death = ""
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        character.cause_of_death = text
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showAppearanceDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Physical appearance — %1"), character.name),
        input = character.appearance or "",
        input_hint = _("e.g. tall, silver hair, a scar above one eyebrow"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        character.appearance = ""
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        character.appearance = text
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showQuoteDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Character quote — %1"), character.name),
        input = character.quote or "",
        input_hint = _("A memorable line this character says"),
        text_height = math.floor(Device.screen:getHeight() * 0.25),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        character.quote = ""
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        character.quote = text
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showLastOccurrenceDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Last seen (manual) — %1"), character.name),
        input = character.last_occurrence or "",
        input_hint = _("e.g. p. 350, Chapter 42, just before the finale"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        character.last_occurrence = ""
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        character.last_occurrence = text
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showAgeDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Age of '%1'"), character.name),
        input = character.age or "",
        input_hint = _("e.g. 27, unknown, ancient"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        character.age = ""
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        character.age = text
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showAbilityDialog(character, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Ability/abilities — %1"), character.name),
        input = character.ability or "",
        input_hint = _("e.g. can control fire, sees the future"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        character.ability = ""
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        character.ability = text
                        self:saveData()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:_stringListChanged(opts)
    if opts.on_change then
        opts.on_change()
    else
        self:saveData()
    end
end

function CharacterTracker:showStringListManager(character, field, opts)
    if not character[field] then character[field] = {} end
    local list = character[field]
    local buttons = {}

    for i, value in ipairs(list) do
        local short = value
        short = shorten(short, 34)
        table.insert(buttons, {
            {
                text = short,
                callback = function()
                    UIManager:close(self._strlist_dialog)
                    self._strlist_dialog = nil
                    self:showStringListEntryDialog(character, field, opts, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._strlist_dialog)
                    self._strlist_dialog = nil
                    table.remove(list, i)
                    self:_stringListChanged(opts)
                    self:showStringListManager(character, field, opts)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = opts.add_label,
            callback = function()
                UIManager:close(self._strlist_dialog)
                self._strlist_dialog = nil
                self:showStringListEntryDialog(character, field, opts, nil)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._strlist_dialog)
                self._strlist_dialog = nil
                if opts.on_close then opts.on_close() end
            end,
        },
    })

    self._strlist_dialog = ButtonDialog:new{
        title = T("%1 — %2", opts.title, character.name),
        buttons = buttons,
    }
    UIManager:show(self._strlist_dialog)
end

function CharacterTracker:showStringListEntryDialog(character, field, opts, index)
    if not character[field] then character[field] = {} end
    local list = character[field]
    local dialog
    dialog = InputDialog:new{
        title = index and opts.edit_title or opts.add_title,
        input = index and list[index] or "",
        input_hint = opts.hint,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showStringListManager(character, field, opts)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if text ~= "" then
                            if index then
                                list[index] = text
                            else
                                local dup = false
                                for _i, v in ipairs(list) do
                                    if v:lower() == text:lower() then dup = true break end
                                end
                                if not dup then table.insert(list, text) end
                            end
                            self:_stringListChanged(opts)
                        end
                        self:showStringListManager(character, field, opts)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showFactionsManager(character)
    self:showStringListManager(character, "factions", {
        title = _("Factions / groups"),
        add_label = _("+ Add faction / group"),
        add_title = _("Add faction / group"),
        edit_title = _("Edit faction / group"),
        hint = _("e.g. House Stark, Night's Watch, The Rebellion"),
    })
end

function CharacterTracker:showTagsManager(character)
    self:showStringListManager(character, "tags", {
        title = _("Tags"),
        add_label = _("+ Add tag"),
        add_title = _("Add tag"),
        edit_title = _("Edit tag"),
        hint = _("freeform, e.g. pov-character, dead, comic-relief"),
    })
end

function CharacterTracker:showSecretsManager(character)
    self:showStringListManager(character, "secrets", {
        title = _("Secrets"),
        add_label = _("+ Add secret"),
        add_title = _("Add secret"),
        edit_title = _("Edit secret"),
        hint = _("something this character is hiding"),
    })
end

function CharacterTracker:showSkillsManager(character)
    self:showStringListManager(character, "skills", {
        title = _("Skills / abilities"),
        add_label = _("+ Add skill"),
        add_title = _("Add skill / ability"),
        edit_title = _("Edit skill / ability"),
        hint = _("e.g. swordsmanship, lock-picking, healing"),
    })
end

function CharacterTracker:showWeaknessesManager(character)
    self:showStringListManager(character, "weaknesses", {
        title = _("Weaknesses"),
        add_label = _("+ Add weakness"),
        add_title = _("Add weakness"),
        edit_title = _("Edit weakness"),
        hint = _("e.g. afraid of heights, silver, pride"),
    })
end

function CharacterTracker:showBelongingsManager(character)
    self:showStringListManager(character, "belongings", {
        title = _("Belongings"),
        add_label = _("+ Add belonging"),
        add_title = _("Add belonging"),
        edit_title = _("Edit belonging"),
        hint = _("e.g. a family sword, a locket, a stolen map"),
    })
end

function CharacterTracker:showSkillsWeaknessesMenu(character)
    self._skills_weak_dialog = ButtonDialog:new{
        title = T(_("Skills & weaknesses — %1"), character.name),
        buttons = {
            {
                { text = _("Skills / abilities"), callback = function()
                    UIManager:close(self._skills_weak_dialog); self._skills_weak_dialog = nil
                    self:showSkillsManager(character)
                end },
            },
            {
                { text = _("Weaknesses"), callback = function()
                    UIManager:close(self._skills_weak_dialog); self._skills_weak_dialog = nil
                    self:showWeaknessesManager(character)
                end },
            },
            {
                { text = _("Close"), id = "close", callback = function()
                    UIManager:close(self._skills_weak_dialog); self._skills_weak_dialog = nil
                end },
            },
        },
    }
    UIManager:show(self._skills_weak_dialog)
end

function CharacterTracker:showTraitsManager(character)
    if not character.traits then character.traits = {} end
    local buttons = {}

    for i, entry in ipairs(character.traits) do
        local label = entry.trait or ""
        if entry.reason and entry.reason ~= "" then
            label = label .. "  —  " .. entry.reason
        end
        label = shorten(label, 44)
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._traits_dialog)
                    self._traits_dialog = nil
                    self:showTraitDialog(character, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._traits_dialog)
                    self._traits_dialog = nil
                    table.remove(character.traits, i)
                    self:saveData()
                    self:showTraitsManager(character)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("+ Add trait"),
            callback = function()
                UIManager:close(self._traits_dialog)
                self._traits_dialog = nil
                self:showTraitDialog(character, nil)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._traits_dialog)
                self._traits_dialog = nil
            end,
        },
    })

    self._traits_dialog = ButtonDialog:new{
        title = T(_("Personality traits — %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._traits_dialog)
end

function CharacterTracker:showTraitDialog(character, index)
    if not character.traits then character.traits = {} end
    local entry = index and character.traits[index] or nil
    local dialog
    dialog = MultiInputDialog:new{
        title = index and _("Edit personality trait") or _("Add personality trait"),
        fields = {
            {
                text = entry and entry.trait or "",
                hint = _("Trait — e.g. brave, deceitful, loyal"),
            },
            {
                text = entry and entry.reason or "",
                hint = _("Why you think so (optional)"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showTraitsManager(character)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local trait = fields[1]:match("^%s*(.-)%s*$")
                        local reason = fields[2]:match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if trait ~= "" then
                            if index then
                                character.traits[index] = { trait = trait, reason = reason }
                            else
                                table.insert(character.traits, { trait = trait, reason = reason })
                            end
                            self:saveData()
                        end
                        self:showTraitsManager(character)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showHighlightsManager(character)
    if not character.highlights then character.highlights = {} end
    local buttons = {}

    for i, quote in ipairs(character.highlights) do
        local text = getNoteText(quote)
        local short = text
        short = shorten(short, 40)
        local note_count = (type(quote) == "table" and type(quote.notes) == "table") and #quote.notes or 0
        table.insert(buttons, {
            {
                text = "“" .. short .. "”" .. (note_count > 0 and (" ✎" .. note_count) or ""),
                callback = function()
                    UIManager:close(self._highlights_dialog)
                    self._highlights_dialog = nil
                    self:showHighlightActions(character, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._highlights_dialog)
                    self._highlights_dialog = nil
                    table.remove(character.highlights, i)
                    self:saveData()
                    self:showHighlightsManager(character)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("+ Add highlight"),
            callback = function()
                UIManager:close(self._highlights_dialog)
                self._highlights_dialog = nil
                self:showHighlightDialog(character, nil)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._highlights_dialog)
                self._highlights_dialog = nil
            end,
        },
    })

    self._highlights_dialog = ButtonDialog:new{
        title = T(_("Highlights — %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._highlights_dialog)
end

function CharacterTracker:showHighlightDialog(character, index)
    if not character.highlights then character.highlights = {} end
    local dialog
    dialog = InputDialog:new{
        title = index and _("Edit highlight") or _("Add highlight"),
        input = index and getNoteText(character.highlights[index]) or "",
        input_hint = _("Paste or type a passage / quote"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showHighlightsManager(character)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if text ~= "" then
                            if index then
                                local current = character.highlights[index]
                                if type(current) == "table" then
                                    current.text = text
                                else
                                    character.highlights[index] = text
                                end
                            else
                                table.insert(character.highlights, text)
                            end
                            self:saveData()
                        end
                        self:showHighlightsManager(character)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showResidenceManager(character)
    if not character.residences then character.residences = {} end
    local buttons = {}

    for i, res in ipairs(character.residences) do
        local kind = res.kind == "works" and _("works") or _("lives")
        local label = res.place .. "  (" .. kind
        if res.past then label = label .. ", " .. _("past") end
        label = label .. ")"
        label = shorten(label, 42)
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._residence_dialog)
                    self._residence_dialog = nil
                    self:showResidenceDialog(character, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._residence_dialog)
                    self._residence_dialog = nil
                    table.remove(character.residences, i)
                    self:saveData()
                    self:showResidenceManager(character)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("+ Add residence"),
            callback = function()
                UIManager:close(self._residence_dialog)
                self._residence_dialog = nil
                self:showResidenceDialog(character, nil)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._residence_dialog)
                self._residence_dialog = nil
            end,
        },
    })

    self._residence_dialog = ButtonDialog:new{
        title = T(_("Residences (manual) — %1\nPlaces module residences show automatically"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._residence_dialog)
end

function CharacterTracker:showResidenceDialog(character, index)
    if not character.residences then character.residences = {} end
    local entry = index and character.residences[index] or nil
    local dialog
    dialog = InputDialog:new{
        title = index and _("Edit residence") or _("Add residence"),
        input = entry and entry.place or "",
        input_hint = _("Place name"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showResidenceManager(character)
                    end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local place = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if place == "" then
                            self:showResidenceManager(character)
                            return
                        end
                        self:showResidenceKindPicker(character, index, place, entry)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showResidenceKindPicker(character, index, place, entry)
    local function commit(kind, past)
        local rec = { place = place, kind = kind, past = past }
        if index then
            character.residences[index] = rec
        else
            table.insert(character.residences, rec)
        end
        self:saveData()
        self:showResidenceManager(character)
    end
    self._residence_kind_dialog = ButtonDialog:new{
        title = T(_("'%1' at '%2'"), character.name, place),
        buttons = {
            {
                { text = _("Lives here (current)"), callback = function()
                    UIManager:close(self._residence_kind_dialog); self._residence_kind_dialog = nil
                    commit("lives", false)
                end },
            },
            {
                { text = _("Lived here (past)"), callback = function()
                    UIManager:close(self._residence_kind_dialog); self._residence_kind_dialog = nil
                    commit("lives", true)
                end },
            },
            {
                { text = _("Works here (current)"), callback = function()
                    UIManager:close(self._residence_kind_dialog); self._residence_kind_dialog = nil
                    commit("works", false)
                end },
            },
            {
                { text = _("Worked here (past)"), callback = function()
                    UIManager:close(self._residence_kind_dialog); self._residence_kind_dialog = nil
                    commit("works", true)
                end },
            },
            {
                { text = _("Cancel"), id = "close", callback = function()
                    UIManager:close(self._residence_kind_dialog); self._residence_kind_dialog = nil
                    self:showResidenceManager(character)
                end },
            },
        },
    }
    UIManager:show(self._residence_kind_dialog)
end

function CharacterTracker:getCharacterResidenceLines(character)
    local lines = {}
    local seen = {}

    local function add(place_label, kind, past)
        local key = (place_label .. "|" .. kind .. "|" .. tostring(past)):lower()
        if seen[key] then return end
        seen[key] = true
        local verb
        if kind == "works" then
            verb = past and _("worked") or _("works")
        else
            verb = past and _("lived") or _("lives")
        end
        local line = place_label .. "  (" .. verb
        if past then line = line .. ", " .. _("past") end
        line = line .. ")"
        table.insert(lines, line)
    end

    for _i, res in ipairs(character.residences or {}) do
        add(res.place, res.kind or "lives", res.past == true)
    end

    local cname = character.name:lower()
    for _i, place in ipairs(self.places or {}) do
        for _j, resident in ipairs(place.residents or {}) do
            if resident.name and resident.name:lower() == cname then
                add(self:getPlacePath(place), resident.kind or "lives", resident.past == true)
            end
        end
    end

    return lines
end

function CharacterTracker:getCharacterResidencePlaceNames(character)
    local names = {}
    local seen = {}
    local function add(name)
        if not name or name == "" then return end
        local key = name:lower()
        if seen[key] then return end
        seen[key] = true
        table.insert(names, name)
    end
    for _i, res in ipairs(character.residences or {}) do
        add(res.place)
    end
    local cname = character.name:lower()
    for _i, place in ipairs(self.places or {}) do
        for _j, resident in ipairs(place.residents or {}) do
            if resident.name and resident.name:lower() == cname then
                add(place.name)
            end
        end
    end
    return names
end

function CharacterTracker:getCharacterBelongingNames(character)
    local names = {}
    local seen = {}
    local function add(name)
        if not name or name == "" then return end
        local key = name:lower()
        if seen[key] then return end
        seen[key] = true
        table.insert(names, name)
    end
    for _i, b in ipairs(character.belongings or {}) do
        add(b)
    end
    local cname = character.name:lower()
    for _i, entry in ipairs(self.compendium or {}) do
        if not entry.hide_from_belongings then
            for _j, rec in ipairs(self:getCompendiumCurrentOwners(entry)) do
                if rec.owner and rec.owner:lower() == cname then
                    add(entry.name)
                    break
                end
            end
        end
    end
    return names
end

local FAMILY_ROMANTIC_RANK = { spouse = 4, partner = 3, lover = 2, ex = 1 }
local FAMILY_BLOOD_TYPES = {
    father = true, mother = true, parent = true, son = true, daughter = true, child = true,
    brother = true, sister = true, sibling = true, cousin = true,
    adoptive_parent = true, adopted_child = true, guardian = true, ward = true,
    step_parent = true, step_child = true, foster_parent = true, foster_child = true,
}

function CharacterTracker:_familyOrigin(family, member)
    local tie = member.tie or ""
    if tie ~= "" and tie ~= _("By blood") then return "linked", tie:lower() end
    local name = (member.name or ""):lower()
    local others = {}
    for _i, other in ipairs(family.members or {}) do
        local key = (other.name or ""):lower()
        if key ~= name then others[key] = true end
    end
    local has_blood, best_rank, best_type = false, 0, nil
    if member.parents and #member.parents > 0 then has_blood = true end
    for _i, other in ipairs(family.members or {}) do
        for _j, p in ipairs(other.parents or {}) do
            if (p or ""):lower() == name then has_blood = true end
        end
    end
    local function consider(rel_type)
        if FAMILY_BLOOD_TYPES[rel_type] then has_blood = true end
        local rank = FAMILY_ROMANTIC_RANK[rel_type]
        if rank and rank > best_rank then best_rank, best_type = rank, rel_type end
    end
    for _i, fam in ipairs(self.families or {}) do
        for _j, rel in ipairs(fam.relations or {}) do
            local from, to = (rel.from or ""):lower(), (rel.to or ""):lower()
            if (from == name and others[to]) or (to == name and others[from]) then
                consider(rel.type)
            end
        end
    end
    for _i, char in ipairs(self.characters or {}) do
        local cname = (char.name or ""):lower()
        for _j, rel in ipairs(char.relationships or {}) do
            local target = (rel.target or ""):lower()
            if (cname == name and others[target]) or (target == name and others[cname]) then
                consider(rel.type)
            end
        end
    end
    if best_type and not has_blood then
        if best_type == "spouse" then return "linked", _("by marriage") end
        if best_type == "ex" then return "linked", _("former romantic relationship") end
        return "linked", _("romantic relationship")
    end
    return "from", nil
end

function CharacterTracker:_familyTieSuffix(family, member, total)
    local kind, detail = self:_familyOrigin(family, member)
    if kind == "from" then
        if total >= 2 then return "  ·  " .. _("from") end
        return ""
    end
    return "  ·  " .. _("linked") .. " (" .. detail .. ")"
end

function CharacterTracker:getCharacterFamilyLines(character)
    local entries = {}
    local cname = character.name:lower()
    for _i, family in ipairs(self.families or {}) do
        for _j, member in ipairs(family.members or {}) do
            if member.name and member.name:lower() == cname then
                table.insert(entries, { family = family, member = member })
            end
        end
    end
    local lines = {}
    for _i, entry in ipairs(entries) do
        local line = entry.family.name or _("(unnamed)")
        if entry.member.role and entry.member.role ~= "" then
            line = line .. "  —  " .. entry.member.role
        end
        line = line .. self:_familyTieSuffix(entry.family, entry.member, #entries)
        table.insert(lines, line)
    end
    return lines
end

function CharacterTracker:getSectionOrder()
    local valid = {}
    for _i, def in ipairs(PAGE_SECTIONS) do
        valid[def.key] = true
    end
    local saved = LayoutSettings and LayoutSettings:readSetting("character_tracker_section_order")
    local order, seen = {}, {}
    if type(saved) == "table" then
        for _i, key in ipairs(saved) do
            if valid[key] and not seen[key] then
                seen[key] = true
                table.insert(order, key)
            end
        end
    end
    for _i, def in ipairs(PAGE_SECTIONS) do
        if not seen[def.key] then
            table.insert(order, def.key)
        end
    end
    return order
end

function CharacterTracker:saveSectionOrder(order)
    if not G_reader_settings then return end
    LayoutSettings:saveSetting("character_tracker_section_order", order)
end

function CharacterTracker:isCharacterSectionHidden(key)
    local hidden = LayoutSettings and LayoutSettings:readSetting("character_tracker_hidden_character_sections")
    return type(hidden) == "table" and hidden[key] == true
end

function CharacterTracker:setCharacterSectionHidden(key, value)
    if not G_reader_settings then return end
    local hidden = LayoutSettings:readSetting("character_tracker_hidden_character_sections")
    local updated = {}
    if type(hidden) == "table" then
        for k, v in pairs(hidden) do updated[k] = v end
    end
    updated[key] = value or nil
    LayoutSettings:saveSetting("character_tracker_hidden_character_sections", updated)
end

function CharacterTracker:showSectionOrderDialog(on_done)
    local labels = {}
    for _i, def in ipairs(PAGE_SECTIONS) do
        labels[def.key] = def.label
    end
    local order = self:getSectionOrder()
    local function reshow()
        UIManager:close(self._section_order_dialog)
        self._section_order_dialog = nil
        self:showSectionOrderDialog(on_done)
    end
    local buttons = {}
    for i, key in ipairs(order) do
        table.insert(buttons, {
            {
                text = "▲",
                callback = function()
                    if i > 1 then
                        order[i], order[i - 1] = order[i - 1], order[i]
                        self:saveSectionOrder(order)
                    end
                    reshow()
                end,
            },
            {
                text = (labels[key] or key) .. (self:isCharacterSectionHidden(key) and (" (" .. _("hidden") .. ")") or ""),
                callback = function() end,
            },
            {
                text = "▼",
                callback = function()
                    if i < #order then
                        order[i], order[i + 1] = order[i + 1], order[i]
                        self:saveSectionOrder(order)
                    end
                    reshow()
                end,
            },
            {
                text = self:isCharacterSectionHidden(key) and _("Show") or _("Hide"),
                callback = function()
                    self:setCharacterSectionHidden(key, not self:isCharacterSectionHidden(key))
                    reshow()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Layout templates…"),
            callback = function()
                UIManager:close(self._section_order_dialog)
                self._section_order_dialog = nil
                self:showLayoutTemplatesDialog(function()
                    self:showSectionOrderDialog(on_done)
                end)
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Reset to default"),
            callback = function()
                local defaults = {}
                for _i, def in ipairs(PAGE_SECTIONS) do
                    table.insert(defaults, def.key)
                end
                self:saveSectionOrder(defaults)
                reshow()
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._section_order_dialog)
                self._section_order_dialog = nil
                if on_done then on_done() end
            end,
        },
    })
    self._section_order_dialog = ButtonDialog:new{
        title = _("Character page sections (▲ / ▼ to move)\nHide applies to every character · the fields at the top stay where they are"),
        buttons = buttons,
    }
    UIManager:show(self._section_order_dialog)
end

function CharacterTracker:buildCharacterDetailText(character)
    local head = {}
    local function add(label, value)
        table.insert(head, label .. ": " .. value .. "\n")
    end
    local block = pageBlock
    local bullets = pageBullets

    if character.aliases and #character.aliases > 0 then
        add(_("Aliases"), table.concat(character.aliases, ", "))
    end

    add(_("Occupation"), (character.occupation and character.occupation ~= "") and character.occupation or _("(not set)"))

    local status_text = (character.status and character.status ~= "" and getStatusLabel(character.status)) or _("(not set)")
    if character.status == "dead" and character.cause_of_death and character.cause_of_death ~= "" then
        status_text = status_text .. " — " .. _("cause") .. ": " .. character.cause_of_death
    end
    add(_("Status"), status_text)

    if not self:isTypeHidden() then
        local ct = character.char_type or ""
        add(_("Character type"), ct ~= "" and getCharacterTypeLabel(ct) or _("(not set)"))
    end

    local res_lines = self:getCharacterResidenceLines(character)
    if #res_lines > 0 then
        table.insert(head, _("Residence") .. ":\n")
        table.insert(head, bullets(res_lines, "  • "))
    end

    if not self:isAgeHidden() and character.age and character.age ~= "" then
        add(_("Age"), character.age)
    end

    if not self:isBelongingsHidden() then
        local belonging_names = self:getCharacterBelongingNames(character)
        if #belonging_names > 0 then
            add(_("Belongings"), table.concat(belonging_names, ", "))
        end
    end

    if not self:isFamilyHidden() then
        local family_lines = self:getCharacterFamilyLines(character)
        if #family_lines > 0 then
            table.insert(head, _("Family") .. ":\n")
            table.insert(head, bullets(family_lines, "  • "))
        end
    end

    local builders = {}

    builders.appearance = function()
        if not character.appearance or character.appearance == "" then return nil end
        return block(_("Appearance"), character.appearance .. "\n")
    end

    builders.ability = function()
        if not character.ability or character.ability == "" then return nil end
        return block(_("Ability"), character.ability .. "\n")
    end

    builders.relationships = function()
        local rel_lines = self:buildRelationshipSummary(character)
        if #rel_lines == 0 then return nil end
        return block(T(_("Relationships (%1)"), #rel_lines), bullets(rel_lines, "• "))
    end

    builders.tree_ties = function()
        local sections = self:buildCharacterTreeSections(character)
        if #sections == 0 then return nil end
        local out = {}
        for _i, section in ipairs(sections) do
            table.insert(out, block(section.title, section.body))
        end
        return table.concat(out)
    end

    builders.factions_tags = function()
        local lines = {}
        if character.factions and #character.factions > 0 then
            table.insert(lines, _("Factions") .. ": " .. table.concat(character.factions, ", ") .. "\n")
        end
        if character.tags and #character.tags > 0 then
            table.insert(lines, _("Tags") .. ": " .. table.concat(character.tags, ", ") .. "\n")
        end
        if #lines == 0 then return nil end
        return "\n" .. table.concat(lines)
    end

    builders.traits = function()
        if not (character.traits and #character.traits > 0) then return nil end
        local lines = {}
        for _i, entry in ipairs(character.traits) do
            local text = entry.trait or ""
            if entry.reason and entry.reason ~= "" then
                text = text .. " — " .. entry.reason
            end
            table.insert(lines, text)
        end
        return block(T(_("Personality traits (%1)"), #character.traits), bullets(lines, "• "))
    end

    builders.timeline = function()
        local lines = {}
        local cname = character.name:lower()
        for _i, tl in ipairs(self.timelines or {}) do
            for _j, event in ipairs(tl.events or {}) do
                for _k, name in ipairs(event.characters or {}) do
                    if name:lower() == cname then
                        local line = event.title ~= "" and event.title or _("(untitled event)")
                        if event.page ~= "" then line = line .. " (" .. T(_("p. %1"), event.page) .. ")" end
                        if tl.name ~= "" then line = line .. " — " .. tl.name end
                        table.insert(lines, line)
                        break
                    end
                end
            end
        end
        if #lines == 0 then return nil end
        return block(T(_("Timeline events (%1)"), #lines), bullets(lines, "• "))
    end

    builders.occurrences = function()
        local has_manual_last = not self:isLastSeenHidden()
            and character.last_occurrence and character.last_occurrence ~= ""
        if not (self.mark_enabled or has_manual_last) then return nil end
        local body = {}
        if self.mark_enabled then
            local app = self:getCharacterAppearance(character)
            if not self:isIndexLimitWarningHidden() and self:_indexLimitReached(character) then
                table.insert(body, T(_("(index limit of %1 reached - later mentions aren't underlined; raise it under \"Max matches per name\")"),
                    self:getMatchCap()) .. "\n")
            end
            if app.first_page then
                if app.first_chapter and app.first_chapter ~= _("Unknown chapter") then
                    table.insert(body, T(_("First seen: %1 (p. %2)"), app.first_chapter, app.first_page) .. "\n")
                else
                    table.insert(body, T(_("First seen: p. %1"), app.first_page) .. "\n")
                end
            end
        end
        if has_manual_last then
            table.insert(body, _("Last seen (manual)") .. ": " .. character.last_occurrence .. "\n")
        end
        return block(_("Occurrences"), table.concat(body))
    end

    builders.highlights = function()
        if not (character.highlights and #character.highlights > 0) then return nil end
        local quotes = {}
        for _i, quote in ipairs(character.highlights) do
            table.insert(quotes, formatHighlight(getNoteText(quote), type(quote) == "table" and quote.notes or nil))
        end
        return block(T(_("Highlights (%1)"), #character.highlights), table.concat(quotes, "\n"))
    end

    builders.topic_highlights = function()
        local blocks = {}
        for _i, topic in ipairs(self:_availableTopics()) do
            local lines = {}
            for _j, entry in ipairs(character.topic_highlights or {}) do
                if entry.topic == topic.key then
                    table.insert(lines, formatHighlight(getNoteText(entry.text), entry.notes))
                end
            end
            if #lines > 0 then
                table.insert(blocks, block(topic.label, table.concat(lines, "\n")))
            end
        end
        if #blocks == 0 then return nil end
        return table.concat(blocks)
    end

    builders.secrets = function()
        if not (character.secrets and #character.secrets > 0) then return nil end
        return block(T(_("Secrets (%1)"), #character.secrets), bullets(character.secrets, "• "))
    end

    builders.skills_weaknesses = function()
        local has_skills = character.skills and #character.skills > 0
        local has_weak = character.weaknesses and #character.weaknesses > 0
        if not (has_skills or has_weak) then return nil end
        local body = {}
        if has_skills then
            table.insert(body, _("Skills / abilities") .. ":\n" .. bullets(character.skills, "+ "))
        end
        if has_weak then
            table.insert(body, _("Weaknesses") .. ":\n" .. bullets(character.weaknesses, "− "))
        end
        return block(_("Skills & weaknesses"), table.concat(body, "\n"))
    end

    builders.notes = function()
        if character.notes and #character.notes > 0 then
            local lines = {}
            for _i, note in ipairs(character.notes) do
                table.insert(lines, getNoteText(note))
            end
            return block(T(_("Notes (%1)"), #character.notes), bullets(lines, "• "))
        end
        return block(_("Notes"), _("No notes yet.") .. "\n")
    end

    builders.quote = function()
        if not (character.quote and character.quote ~= "") then return nil end
        return block(_("Quote"), "“" .. character.quote .. "”\n")
    end

    local parts = { table.concat(head) }
    for _i, key in ipairs(self:getSectionOrder()) do
        if not self:isCharacterSectionHidden(key) then
            local build = builders[key]
            local text = build and build()
            if text then table.insert(parts, text) end
        end
    end
    return table.concat(parts)
end

function CharacterTracker:showCharacterDetail(character)
    self:_disarmDetailReturn()
    local full_text = self:buildCharacterDetailText(character)

    local function reopen()
        self:showCharacterDetail(character)
    end

    local viewer

    local rows = {}
    table.insert(rows, {
        {
            text = _("Aliases"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showAliasManager(character)
            end,
        },
        {
            text = _("Occupation"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showOccupationDialog(character, reopen)
            end,
        },
        {
            text = _("Status"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showStatusDialog(character, reopen)
            end,
        },
        {
            text = _("Type"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showCharacterTypeDialog(character, reopen)
            end,
        },
    })
    do
        local row2 = {
            {
                section = "appearance",
                text = _("Appearance"),
                callback = function()
                    UIManager:close(viewer)
                    self:_armDetailReturn(character, reopen)
                    self:showAppearanceDialog(character, reopen)
                end,
            },
            {
                text = _("Residence"),
                callback = function()
                    UIManager:close(viewer)
                    self:_armDetailReturn(character, reopen)
                    self:showResidenceManager(character)
                end,
            },
        }
        if not self:isLastSeenHidden() then
            table.insert(row2, {
                text = _("Last seen"),
                callback = function()
                    UIManager:close(viewer)
                    self:_armDetailReturn(character, reopen)
                    self:showLastOccurrenceDialog(character, reopen)
                end,
            })
        end
        table.insert(rows, row2)
    end
    do
        local row3 = {}
        if not self:isAgeHidden() then
            table.insert(row3, {
                text = _("Age"),
                callback = function()
                    UIManager:close(viewer)
                    self:_armDetailReturn(character, reopen)
                    self:showAgeDialog(character, reopen)
                end,
            })
        end
        if not self:isAbilityHidden() then
            table.insert(row3, {
                text = _("Ability"),
                callback = function()
                    UIManager:close(viewer)
                    self:_armDetailReturn(character, reopen)
                    self:showAbilityDialog(character, reopen)
                end,
            })
        end
        if not self:isBelongingsHidden() then
            table.insert(row3, {
                text = _("Belongings"),
                callback = function()
                    UIManager:close(viewer)
                    self:_armDetailReturn(character, reopen)
                    self:showBelongingsManager(character)
                end,
            })
        end
        if #row3 > 0 then table.insert(rows, row3) end
    end
    table.insert(rows, {
        {
            section = "relationships",
            text = _("Relations"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showRelationshipManager(character)
            end,
        },
        {
            section = "factions_tags",
            text = _("Factions"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showFactionsManager(character)
            end,
        },
        {
            section = "factions_tags",
            text = _("Tags"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showTagsManager(character)
            end,
        },
    })
    if not self:isFamilyHidden() then
        table.insert(rows[#rows], {
            text = _("Families"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showCharacterFamiliesManager(character)
            end,
        })
    end
    table.insert(rows, {
        {
            section = "traits",
            text = _("Traits"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showTraitsManager(character)
            end,
        },
        {
            section = "highlights",
            text = _("Highlights"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showHighlightsManager(character)
            end,
        },
        {
            section = "topic_highlights",
            text = _("Topics"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showTopicHighlightsManager(character)
            end,
        },
        {
            section = "secrets",
            text = _("Secrets"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showSecretsManager(character)
            end,
        },
    })
    table.insert(rows, {
        {
            section = "skills_weaknesses",
            text = _("Skills/Weak."),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showSkillsWeaknessesMenu(character)
            end,
        },
        {
            section = "notes",
            text = _("Notes"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showNotesManager(character)
            end,
        },
        {
            section = "quote",
            text = _("Quote"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showQuoteDialog(character, reopen)
            end,
        },
    })
    table.insert(rows, {
        {
            text = _("Underline"),
            callback = function()
                UIManager:close(viewer)
                character.underline = not character.underline
                self:_rebuildNameIndex()
                self._paint_cache_key = nil
                self:saveData()
                reopen()
            end,
        },
        {
            text = character.pinned == true and _("Unpin") or _("Pin"),
            callback = function()
                UIManager:close(viewer)
                character.pinned = not (character.pinned == true)
                self:saveData()
                reopen()
            end,
        },
        {
            text = _("＋ Note"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showAddNoteDialog(character)
            end,
        },
        {
            text = _("Rename"),
            callback = function()
                UIManager:close(viewer)
                self:_armDetailReturn(character, reopen)
                self:showRenameDialog(character, reopen)
            end,
        },
    })
    local visible_rows = {}
    for _i, row in ipairs(rows) do
        local kept = {}
        for _j, button in ipairs(row) do
            if not button.section or not self:isCharacterSectionHidden(button.section) then
                table.insert(kept, button)
            end
        end
        if #kept > 0 then table.insert(visible_rows, kept) end
    end
    rows = visible_rows
    table.insert(rows, {
        {
            text = _("Arrange sections"),
            callback = function()
                UIManager:close(viewer)
                self:showSectionOrderDialog(reopen)
            end,
        },
    })
    table.insert(rows, {
        {
            text = _("Delete"),
            callback = function()
                UIManager:close(viewer)
                self:deleteCharacter(character)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(viewer)
            end,
        },
    })

    viewer = self:newTextViewer("character_edit"){
        title = character.name,
        text = full_text,
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = rows,
        text_selection_callback = function(text)
            self:_onRelationshipHold(character, viewer, false, text)
        end,
    }
    UIManager:show(viewer)
end

function CharacterTracker:showCharacterDetailReadOnly(character)
    local full_text = self:buildCharacterDetailText(character)
    local viewer
    local button_row = {}
    if not self:isReadOnlyTreeButtonHidden() then
        table.insert(button_row, {
            text = self:isShortTreeLabel() and _("Tree") or _("Family tree"),
            callback = function()
                self:showCharacterFamilyTrees(character)
            end,
        })
    end
    if not self:isReadOnlyEditButtonHidden() then
        table.insert(button_row, {
            text = _("Edit"),
            callback = function()
                UIManager:close(viewer)
                self:showCharacterDetail(character)
            end,
        })
    end
    table.insert(button_row, {
        text = _("Close"),
        id = "close",
        callback = function()
            UIManager:close(viewer)
        end,
    })
    viewer = self:newTextViewer("character_read"){
        title = character.name,
        text = full_text,
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        text_selection_callback = function(text)
            self:_onRelationshipHold(character, viewer, true, text)
        end,
        buttons_table = { button_row },
    }
    UIManager:show(viewer)
end

function CharacterTracker:showCharacterFamilyTrees(character)
    local key = (character.name or ""):lower()
    local found = {}
    for _i, family in ipairs(self.families or {}) do
        for _j, member in ipairs(family.members or {}) do
            if (member.name or ""):lower() == key then
                table.insert(found, { family = family, member = member })
                break
            end
        end
    end
    if #found == 0 then
        UIManager:show(InfoMessage:new{
            text = T(_("%1 is currently not in a family tree."), character.name),
        })
        return
    end
    if #found == 1 then
        self:showFamilyTree(found[1].family, true)
        return
    end
    local dialog
    local buttons = {}
    for _i, entry in ipairs(found) do
        local kind = self:_familyOrigin(entry.family, entry.member)
        local prefix = kind == "from" and (_("From") .. ": ") or (_("Linked") .. ": ")
        table.insert(buttons, {
            {
                text = shorten(prefix .. (entry.family.name or _("(unnamed)")), 40),
                callback = function()
                    UIManager:close(dialog)
                    self:showFamilyTree(entry.family, true)
                end,
            },
        })
    end
    table.insert(buttons, {
        { text = _("Close"), id = "close", callback = function() UIManager:close(dialog) end },
    })
    dialog = ButtonDialog:new{
        title = T(_("Family trees of %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function CharacterTracker:onShowCharacterList()
    self:showCharacterList(nil, nil, true)
end

function CharacterTracker:onShowEditCharacterList()
    self:showCharacterList()
end

function CharacterTracker:showCharacterList(filter, sort_mode, readonly)
    if not self.characters or #self.characters == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No characters tracked yet.\n\nTo add a character:\n1. Select text in the book\n2. Tap 'Character' in the highlight menu\n3. Or use the Tools menu → Character Tracker → Add character"),
        })
        return
    end

    filter = filter and filter ~= "" and filter:lower() or nil
    local struct_filter = self._struct_filter

    local chars = {}
    for _i, char in ipairs(self.characters) do
        local ok = true
        if filter and not self:characterMatchesQuery(char, filter) then
            ok = false
        end
        if ok and struct_filter and not self:characterMatchesStructFilter(char, struct_filter) then
            ok = false
        end
        if ok then
            table.insert(chars, char)
        end
    end
    if #chars == 0 then
        local msg
        if filter and struct_filter then
            msg = T(_("No characters match '%1' and the current filter."), filter)
        elseif filter then
            msg = T(_("No characters match '%1'."), filter)
        else
            msg = _("No characters match the current filter.")
        end
        UIManager:show(InfoMessage:new{ text = msg })
        return
    end

    sort_mode = sort_mode or self._sort_mode or "default"
    local sort_fns = {
        name = function(a, b) return a.name:lower() < b.name:lower() end,
        char_type = function(a, b)
            local ra, rb = getCharacterTypeLabel(a.char_type or ""), getCharacterTypeLabel(b.char_type or "")
            if ra ~= rb then return ra < rb end
            return a.name:lower() < b.name:lower()
        end,
        occupation = function(a, b)
            local ra, rb = (a.occupation or ""):lower(), (b.occupation or ""):lower()
            if ra ~= rb then return ra < rb end
            return a.name:lower() < b.name:lower()
        end,
        created = function(a, b)
            local ca, cb = a.created or "", b.created or ""
            if ca ~= cb then return ca < cb end
            return a.name:lower() < b.name:lower()
        end,
    }
    local cmp = sort_fns[sort_mode]
    if cmp then
        table.sort(chars, function(a, b)
            local pa, pb = a.pinned == true, b.pinned == true
            if pa ~= pb then return pa end
            return cmp(a, b)
        end)
    elseif sort_mode ~= "manual" then
        local pinned, rest = {}, {}
        for _i, char in ipairs(chars) do
            table.insert(char.pinned == true and pinned or rest, char)
        end
        for _i, char in ipairs(rest) do table.insert(pinned, char) end
        chars = pinned
    end

    local incoming_map = self:_buildIncomingRelationshipsMap()
    local badge_order, badge_hidden = self:getListBadgeLayout()

    local item_table = {}
    for _i, char in ipairs(chars) do
        local pieces = {}
        if char.occupation and char.occupation ~= "" then
            pieces.occupation = char.occupation
        end
        local ct = char.char_type or ""
        if ct ~= "" and not self:isTypeHidden() then
            pieces.type = getCharacterTypeLabel(ct)
        end
        if char.factions and #char.factions > 0 then
            pieces.factions = table.concat(char.factions, "/")
        end
        if char.aliases and #char.aliases > 0 then
            pieces.aliases = T(_("%1 aliases"), #char.aliases)
        end
        local incoming = incoming_map[char.name:lower()] or {}
        local rel_count = (char.relationships and #char.relationships or 0) + #incoming
        if rel_count > 0 then
            pieces.relations = T(_("%1 relations"), rel_count)
        end
        if char.notes and #char.notes > 0 then
            pieces.notes = T(_("%1 notes"), #char.notes)
        end
        local badges = {}
        for _j, badge_key in ipairs(badge_order) do
            if pieces[badge_key] and not badge_hidden[badge_key] then
                table.insert(badges, pieces[badge_key])
            end
        end
        local info = ""
        if #badges > 0 then
            info = " · " .. table.concat(badges, " · ")
        end

        local display_name = char.name

        table.insert(item_table, {
            text = display_name .. info,
            character = char,
            callback = function()
                if readonly then
                    self:showCharacterDetailReadOnly(char)
                else
                    self:showCharacterDetail(char)
                end
            end,
        })
    end

    local list_title
    if filter then
        list_title = T(_("Characters matching '%1' (%2)"), filter, #chars)
    elseif struct_filter then
        list_title = T(_("Characters: %1 = %2 (%3)"), struct_filter.kind, struct_filter.value, #chars)
    else
        list_title = readonly and _("Character list") or _("Edit character list")
    end

    local menu_container
    local menu
    menu = Menu:new{
        title = list_title,
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = function()
            UIManager:close(menu_container)
        end,
    }
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

local function dictPopupSelectedText(popup)
    if not popup then return nil end
    local from_highlight = popup.highlight and popup.highlight.selected_text
        and popup.highlight.selected_text.text
    if type(from_highlight) == "string" and trim(from_highlight) ~= "" then
        return trim(from_highlight)
    end
    local looked_up = popup.lookupword or popup.word or popup.displayword
    if type(looked_up) == "string" and trim(looked_up) ~= "" then
        return trim(looked_up)
    end
    return nil
end

function CharacterTracker:_onDictButtonTap(popup)
    local selected = dictPopupSelectedText(popup)
    if popup then
        if popup.onClose then
            popup:onClose()
        else
            UIManager:close(popup)
        end
    end
    self:onAssignHighlightToCharacter(selected and { text = selected } or nil)
end

function CharacterTracker:_registerDictButton()
    if self._dict_button_registered then return end
    local dictionary = self.ui and self.ui.dictionary
    if not dictionary or type(dictionary.addToDictButtons) ~= "function" then
        return
    end
    dictionary:addToDictButtons({
        id = "charactertracker_assign",
        menu_text = _("Character"),
        text = _("Character"),
        callback = function(popup)
            self:_onDictButtonTap(popup)
        end,
        hold_callback = function()
            self:showCharacterList(nil, nil, true)
        end,
    })
    self._dict_button_registered = true
    self:_addDictButtonToUserLayout("charactertracker_assign")
end

function CharacterTracker:_addDictButtonToUserLayout(button_id)
    if not G_reader_settings then return end
    local config = G_reader_settings:readSetting("dict_button_config")
    if not (config and config.layout) then
        return
    end
    local flag = "character_tracker_dict_button_added_" .. button_id
    if G_reader_settings:isTrue(flag) then return end
    G_reader_settings:saveSetting(flag, true)

    for _i, row in ipairs(config.layout) do
        for _j, id in ipairs(row) do
            if id == button_id then return end
        end
    end

    local last_idx = #config.layout
    local row = config.layout[last_idx]
    local max_in_row = (config.row_count and config.row_count[last_idx]) or 3
    if not row or #row >= max_in_row then
        row = {}
        table.insert(config.layout, row)
        if config.row_count then
            config.row_count[#config.layout] = 3
        end
    end
    table.insert(row, button_id)

    if config.order then
        local present = false
        for _i, id in ipairs(config.order) do
            if id == button_id then present = true break end
        end
        if not present then table.insert(config.order, button_id) end
    end
    G_reader_settings:saveSetting("dict_button_config", config)
end

function CharacterTracker:onDictButtonsReady(dict_popup, dict_buttons)
    if not dict_popup or not dict_buttons then return end
    if self._dict_button_registered then return end
    for _i, row in ipairs(dict_buttons) do
        for _j, button in ipairs(row) do
            if button.id == "charactertracker_assign" then return end
        end
    end
    local button_row = {
        {
            id = "charactertracker_assign",
            text = _("Character"),
            callback = function()
                self:_onDictButtonTap(dict_popup)
            end,
            hold_callback = function()
                self:showCharacterList(nil, nil, true)
            end,
        },
    }
    local insert_index = #dict_buttons
    if insert_index < 1 then
        table.insert(dict_buttons, button_row)
    else
        table.insert(dict_buttons, insert_index, button_row)
    end
end

function CharacterTracker:onAssignHighlightToCharacter(selected)
    if not selected then
        UIManager:show(InfoMessage:new{
            text = _("No text selected."),
        })
        return
    end

    local selected_text = selected.text or ""
    local trimmed = selected_text:match("^%s*(.-)%s*$")
    local existing = self:getCharacterByName(trimmed)

    local selection_name = (trimmed:gsub("%s+", " "))

    local buttons = {}
    local function choose(fn)
        return function()
            UIManager:close(self._assign_dialog)
            self._assign_dialog = nil
            fn()
        end
    end

    if existing then
        table.insert(buttons, {
            { text = T(_("Open '%1'"), existing.name), callback = choose(function()
                self:showCharacterDetail(existing)
            end) },
        })
    end
    local existing_place = self:getPlaceByName(selection_name)
    if existing_place then
        table.insert(buttons, {
            { text = T(_("Open place '%1'"), existing_place.name), callback = choose(function()
                self:showPlaceDetail(existing_place)
            end) },
        })
    end
    local existing_entry = self:getCompendiumEntryByName(selection_name)
    if existing_entry then
        table.insert(buttons, {
            { text = T(_("Open compendium '%1'"), existing_entry.name), callback = choose(function()
                self:showCompendiumDetail(existing_entry)
            end) },
        })
    end
    local existing_family = self:getFamilyByName(selection_name)
    if existing_family then
        table.insert(buttons, {
            { text = T(_("Open family '%1'"), existing_family.name), callback = choose(function()
                self:showFamilyDetail(existing_family)
            end) },
        })
    end

    if #self.characters > 0 and not self:isSelectionOptionHidden("highlight") then
        table.insert(buttons, {
            { text = _("Add selection as highlight to…"), callback = choose(function()
                self:showAssignHighlightPicker(trimmed)
            end) },
        })
    end

    if #self.characters > 0 and not self:isSelectionOptionHidden("topic") then
        table.insert(buttons, {
            { text = _("Add selection as topic highlight to…"), callback = choose(function()
                self:showAssignTopicHighlightPicker(trimmed)
            end) },
        })
    end

    if #self.families > 0 and not self:isSelectionOptionHidden("family_excerpt") then
        table.insert(buttons, {
            { text = _("Add selection to a family or relationship…"), callback = choose(function()
                self:showAssignFamilyExcerpt(trimmed, self:_selectionPage(selected))
            end) },
        })
    end

    if not self:isSelectionOptionHidden("timeline") then
        table.insert(buttons, {
            { text = _("Add selection to a timeline event…"), callback = choose(function()
                self:showAssignTimelineExcerpt(trimmed, self:_selectionPage(selected))
            end) },
        })
    end

    if #self.characters > 0 and not self:isSelectionOptionHidden("appearance") and not self:isAppearanceHidden() then
        table.insert(buttons, {
            { text = _("Add selection to appearance of…"), callback = choose(function()
                self:showAssignAppearancePicker(trimmed)
            end) },
        })
    end

    if not self:isSelectionOptionHidden("character") then
        table.insert(buttons, {
            { text = _("New character from selection"), callback = choose(function()
                self:showAddCharacterDialog(selection_name)
            end) },
        })
    end

    if not self:isSelectionOptionHidden("place") then
        table.insert(buttons, {
            { text = _("New place from selection"), callback = choose(function()
                self:showAddPlaceDialog(nil, nil, selection_name)
            end) },
        })
    end

    if not self:isSelectionOptionHidden("compendium") then
        table.insert(buttons, {
            { text = _("New compendium entry from selection"), callback = choose(function()
                self:showAddCompendiumDialog(selection_name)
            end) },
        })
    end

    if not self:isSelectionOptionHidden("family") then
        table.insert(buttons, {
            { text = _("New family from selection"), callback = choose(function()
                self:showAddFamilyDialog(selection_name)
            end) },
        })
    end

    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._assign_dialog)
                self._assign_dialog = nil
            end,
        },
    })

    local preview = trimmed
    preview = shorten(preview, 60)
    self._assign_dialog = ButtonDialog:new{
        title = T(_("Selection: “%1”"), preview),
        buttons = buttons,
    }
    UIManager:show(self._assign_dialog)
end

function CharacterTracker:showAssignHighlightPicker(quote)
    local buttons = {}
    local row = {}
    for _i, char in ipairs(self.characters) do
        table.insert(row, {
            text = char.name,
            callback = function()
                UIManager:close(self._assign_hl_picker)
                self._assign_hl_picker = nil
                if not char.highlights then char.highlights = {} end
                table.insert(char.highlights, quote)
                self:saveData()
                UIManager:show(InfoMessage:new{
                    text = T(_("Highlight added to '%1'."), char.name),
                    timeout = 2,
                })
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._assign_hl_picker)
                self._assign_hl_picker = nil
            end,
        },
    })
    self._assign_hl_picker = ButtonDialog:new{
        title = _("Attach highlight to which character?"),
        buttons = buttons,
    }
    UIManager:show(self._assign_hl_picker)
end

function CharacterTracker:showAssignAppearancePicker(text)
    local buttons = {}
    local row = {}
    for _i, char in ipairs(self.characters) do
        table.insert(row, {
            text = char.name,
            callback = function()
                UIManager:close(self._assign_appearance_picker)
                self._assign_appearance_picker = nil
                local current = trim(char.appearance or "")
                char.appearance = current ~= "" and (current .. "\n" .. text) or text
                self:saveData()
                UIManager:show(InfoMessage:new{
                    text = T(_("Added to the appearance of '%1'."), char.name),
                    timeout = 2,
                })
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._assign_appearance_picker)
                self._assign_appearance_picker = nil
            end,
        },
    })
    self._assign_appearance_picker = ButtonDialog:new{
        title = _("Add to the appearance of which character?"),
        buttons = buttons,
    }
    UIManager:show(self._assign_appearance_picker)
end

function CharacterTracker:_availableTopics()
    local out = {}
    for _i, topic in ipairs(HIGHLIGHT_TOPICS) do
        local hidden = (topic.key == "ability" and self:isAbilityHidden())
            or (topic.key == "appearance" and self:isAppearanceHidden())
            or (topic.key == "belongings" and self:isBelongingsHidden())
        if not hidden then table.insert(out, topic) end
    end
    return out
end

function CharacterTracker:showTopicPicker(title, on_pick)
    local buttons = {}
    local row = {}
    for _i, topic in ipairs(self:_availableTopics()) do
        table.insert(row, {
            text = topic.label,
            callback = function()
                UIManager:close(self._topic_picker)
                self._topic_picker = nil
                on_pick(topic.key)
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._topic_picker)
                self._topic_picker = nil
            end,
        },
    })
    self._topic_picker = ButtonDialog:new{
        title = title,
        buttons = buttons,
    }
    UIManager:show(self._topic_picker)
end

function CharacterTracker:addTopicHighlight(character, topic, text)
    if type(character.topic_highlights) ~= "table" then character.topic_highlights = {} end
    table.insert(character.topic_highlights, { topic = topic, text = text })
    self:saveData()
    UIManager:show(InfoMessage:new{
        text = T(_("Added to %1 for '%2'."), getTopicLabel(topic), character.name),
        timeout = 2,
    })
end

function CharacterTracker:showAssignTopicHighlightPicker(quote)
    local buttons = {}
    local row = {}
    for _i, char in ipairs(self.characters) do
        table.insert(row, {
            text = char.name,
            callback = function()
                UIManager:close(self._assign_topic_picker)
                self._assign_topic_picker = nil
                self:showTopicPicker(T(_("What is this about for '%1'?"), char.name), function(topic)
                    self:addTopicHighlight(char, topic, quote)
                end)
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._assign_topic_picker)
                self._assign_topic_picker = nil
            end,
        },
    })
    self._assign_topic_picker = ButtonDialog:new{
        title = _("Attach topic highlight to which character?"),
        buttons = buttons,
    }
    UIManager:show(self._assign_topic_picker)
end

function CharacterTracker:_topicHighlightOrder(character)
    local order, used = {}, {}
    for _i, topic in ipairs(HIGHLIGHT_TOPICS) do
        for j, entry in ipairs(character.topic_highlights) do
            if entry.topic == topic.key then
                table.insert(order, j)
                used[j] = true
            end
        end
    end
    for j, _entry in ipairs(character.topic_highlights) do
        if not used[j] then table.insert(order, j) end
    end
    return order
end

function CharacterTracker:_topicCount(character, key)
    local n = 0
    for _i, entry in ipairs(character.topic_highlights or {}) do
        if entry.topic == key then n = n + 1 end
    end
    return n
end

function CharacterTracker:showTopicHighlightsManager(character)
    if type(character.topic_highlights) ~= "table" then character.topic_highlights = {} end
    local buttons = {}
    local row = {}
    for _i, topic in ipairs(HIGHLIGHT_TOPICS) do
        local count = self:_topicCount(character, topic.key)
        local hidden = (topic.key == "ability" and self:isAbilityHidden())
            or (topic.key == "appearance" and self:isAppearanceHidden())
            or (topic.key == "belongings" and self:isBelongingsHidden())
        if not hidden or count > 0 then
            table.insert(row, {
                text = topic.label .. (count > 0 and (" (" .. count .. ")") or ""),
                callback = function()
                    UIManager:close(self._topic_hl_dialog)
                    self._topic_hl_dialog = nil
                    self:showTopicHighlightList(character, topic.key)
                end,
            })
            if #row >= 2 then
                table.insert(buttons, row)
                row = {}
            end
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._topic_hl_dialog)
                self._topic_hl_dialog = nil
            end,
        },
    })
    self._topic_hl_dialog = ButtonDialog:new{
        title = T(_("Topics — %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._topic_hl_dialog)
end

function CharacterTracker:showTopicHighlightList(character, topic_key)
    if type(character.topic_highlights) ~= "table" then character.topic_highlights = {} end
    local buttons = {}
    for i, entry in ipairs(character.topic_highlights) do
        if entry.topic == topic_key then
            local note_count = type(entry.notes) == "table" and #entry.notes or 0
            table.insert(buttons, {
                {
                    text = shorten(getNoteText(entry.text), 40)
                        .. (note_count > 0 and (" ✎" .. note_count) or ""),
                    callback = function()
                        UIManager:close(self._topic_list_dialog)
                        self._topic_list_dialog = nil
                        self:showTopicHighlightActions(character, i)
                    end,
                },
                {
                    text = "✕",
                    callback = function()
                        UIManager:close(self._topic_list_dialog)
                        self._topic_list_dialog = nil
                        table.remove(character.topic_highlights, i)
                        self:saveData()
                        self:showTopicHighlightList(character, topic_key)
                    end,
                },
            })
        end
    end
    table.insert(buttons, {
        {
            text = _("+ Add highlight"),
            callback = function()
                UIManager:close(self._topic_list_dialog)
                self._topic_list_dialog = nil
                self:showTopicHighlightTextDialog(character, nil, topic_key)
            end,
        },
        {
            text = _("Back"),
            id = "close",
            callback = function()
                UIManager:close(self._topic_list_dialog)
                self._topic_list_dialog = nil
                self:showTopicHighlightsManager(character)
            end,
        },
    })
    if self:_topicCount(character, topic_key) >= 2 then
        table.insert(buttons, #buttons, {
            {
                text = _("Arrange highlights"),
                callback = function()
                    UIManager:close(self._topic_list_dialog)
                    self._topic_list_dialog = nil
                    self:showTopicHighlightArrange(character, topic_key)
                end,
            },
        })
    end
    self._topic_list_dialog = ButtonDialog:new{
        title = T(_("%1 — %2"), getTopicLabel(topic_key), character.name),
        buttons = buttons,
    }
    UIManager:show(self._topic_list_dialog)
end

function CharacterTracker:showTopicHighlightArrange(character, topic_key)
    local list = character.topic_highlights
    local slots = {}
    for i, entry in ipairs(list) do
        if entry.topic == topic_key then slots[#slots + 1] = i end
    end
    local function reshow()
        UIManager:close(self._topic_arrange_dialog)
        self._topic_arrange_dialog = nil
        self:showTopicHighlightArrange(character, topic_key)
    end
    local function swap(a, b)
        if b < 1 or b > #slots then return end
        list[slots[a]], list[slots[b]] = list[slots[b]], list[slots[a]]
        self:saveData()
    end
    local buttons = {}
    for n, slot in ipairs(slots) do
        local entry = list[slot]
        table.insert(buttons, {
            { text = "▲", callback = function() swap(n, n - 1) reshow() end },
            { text = shorten(getNoteText(entry.text), 34), callback = function() end },
            { text = "▼", callback = function() swap(n, n + 1) reshow() end },
        })
    end
    table.insert(buttons, {
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._topic_arrange_dialog)
            self._topic_arrange_dialog = nil
            self:showTopicHighlightList(character, topic_key)
        end },
    })
    self._topic_arrange_dialog = ButtonDialog:new{
        title = T(_("Arrange %1 highlights\n(▲ / ▼ to move)"), getTopicLabel(topic_key)),
        buttons = buttons,
    }
    UIManager:show(self._topic_arrange_dialog)
end

function CharacterTracker:showHighlightNotesArrange(character, list, index, back)
    local entry = list[index]
    if type(entry) ~= "table" or type(entry.notes) ~= "table" then
        back()
        return
    end
    local function reshow()
        UIManager:close(self._hl_arrange_dialog)
        self._hl_arrange_dialog = nil
        self:showHighlightNotesArrange(character, list, index, back)
    end
    local function swap(a, b)
        if b < 1 or b > #entry.notes then return end
        entry.notes[a], entry.notes[b] = entry.notes[b], entry.notes[a]
        self:_saveFor(character)
    end
    local buttons = {}
    for n, note in ipairs(entry.notes) do
        table.insert(buttons, {
            { text = "▲", callback = function() swap(n, n - 1) reshow() end },
            { text = shorten(note, 34), callback = function() end },
            { text = "▼", callback = function() swap(n, n + 1) reshow() end },
        })
    end
    table.insert(buttons, {
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._hl_arrange_dialog)
            self._hl_arrange_dialog = nil
            self:showHighlightNotesManager(character, list, index, back)
        end },
    })
    self._hl_arrange_dialog = ButtonDialog:new{
        title = T(_("Arrange notes on “%1”\n(▲ / ▼ to move)"), shorten(getNoteText(entry.text), 30)),
        buttons = buttons,
    }
    UIManager:show(self._hl_arrange_dialog)
end

function CharacterTracker:showTopicHighlightActions(character, index)
    local list = character.topic_highlights
    local entry = list[index]
    if not entry then return end
    local topic_key = entry.topic
    local function close_and(fn)
        return function()
            UIManager:close(self._topic_hl_act_dialog)
            self._topic_hl_act_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = index + step
        while j >= 1 and j <= #list do
            if list[j].topic == topic_key then
                list[index], list[j] = list[j], list[index]
                self:saveData()
                break
            end
            j = j + step
        end
        self:showTopicHighlightList(character, topic_key)
    end
    local note_count = type(entry.notes) == "table" and #entry.notes or 0
    self._topic_hl_act_dialog = ButtonDialog:new{
        title = shorten("[" .. getTopicLabel(topic_key) .. "] " .. getNoteText(entry.text), 60),
        buttons = {
            {
                { text = _("Edit highlight"), callback = close_and(function()
                    self:showTopicHighlightTextDialog(character, index)
                end) },
                { text = note_count > 0 and T(_("Notes (%1)"), note_count) or _("Notes"), callback = close_and(function()
                    self:showHighlightNotesManager(character, list, index, function()
                        self:showTopicHighlightList(character, topic_key)
                    end)
                end) },
            },
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function()
                    move(-1)
                end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function()
                    move(1)
                end) },
            },
            {
                { text = _("Delete"), callback = close_and(function()
                    table.remove(list, index)
                    self:saveData()
                    self:showTopicHighlightList(character, topic_key)
                end) },
                { text = _("Back"), id = "close", callback = close_and(function()
                    self:showTopicHighlightList(character, topic_key)
                end) },
            },
        },
    }
    UIManager:show(self._topic_hl_act_dialog)
end

function CharacterTracker:showHighlightActions(character, index)
    local list = character.highlights
    local entry = list[index]
    if entry == nil then return end
    local function close_and(fn)
        return function()
            UIManager:close(self._highlight_act_dialog)
            self._highlight_act_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = index + step
        if j >= 1 and j <= #list then
            list[index], list[j] = list[j], list[index]
            self:saveData()
        end
        self:showHighlightsManager(character)
    end
    local note_count = (type(entry) == "table" and type(entry.notes) == "table") and #entry.notes or 0
    self._highlight_act_dialog = ButtonDialog:new{
        title = shorten("“" .. getNoteText(entry) .. "”", 60),
        buttons = {
            {
                { text = _("Edit highlight"), callback = close_and(function()
                    self:showHighlightDialog(character, index)
                end) },
                { text = note_count > 0 and T(_("Notes (%1)"), note_count) or _("Notes"), callback = close_and(function()
                    self:showHighlightNotesManager(character, list, index, function()
                        self:showHighlightsManager(character)
                    end)
                end) },
            },
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function()
                    move(-1)
                end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function()
                    move(1)
                end) },
            },
            {
                { text = _("Delete"), callback = close_and(function()
                    table.remove(list, index)
                    self:saveData()
                    self:showHighlightsManager(character)
                end) },
                { text = _("Back"), id = "close", callback = close_and(function()
                    self:showHighlightsManager(character)
                end) },
            },
        },
    }
    UIManager:show(self._highlight_act_dialog)
end

function CharacterTracker:showHighlightNotesManager(character, list, index, back)
    local entry = list[index]
    if entry == nil then
        back()
        return
    end
    if type(entry) ~= "table" then
        entry = { text = entry }
        list[index] = entry
    end
    if type(entry.notes) ~= "table" then entry.notes = {} end
    local buttons = {}
    for i, note in ipairs(entry.notes) do
        table.insert(buttons, {
            {
                text = shorten(note, 40),
                callback = function()
                    UIManager:close(self._hl_notes_dialog)
                    self._hl_notes_dialog = nil
                    self:showHighlightNoteActions(character, list, index, i, back)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._hl_notes_dialog)
                    self._hl_notes_dialog = nil
                    table.remove(entry.notes, i)
                    self:_saveFor(character)
                    self:showHighlightNotesManager(character, list, index, back)
                end,
            },
        })
    end
    if #entry.notes >= 2 then
        table.insert(buttons, {
            {
                text = _("Arrange notes"),
                callback = function()
                    UIManager:close(self._hl_notes_dialog)
                    self._hl_notes_dialog = nil
                    self:showHighlightNotesArrange(character, list, index, back)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add note"),
            callback = function()
                UIManager:close(self._hl_notes_dialog)
                self._hl_notes_dialog = nil
                self:showHighlightNoteDialog(character, list, index, nil, back)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._hl_notes_dialog)
                self._hl_notes_dialog = nil
                back()
            end,
        },
    })
    self._hl_notes_dialog = ButtonDialog:new{
        title = T(_("Notes on “%1”"), shorten(getNoteText(entry.text), 40)),
        buttons = buttons,
    }
    UIManager:show(self._hl_notes_dialog)
end

function CharacterTracker:showHighlightNoteActions(character, list, index, note_index, back)
    local entry = list[index]
    if type(entry) ~= "table" or type(entry.notes) ~= "table" or not entry.notes[note_index] then
        self:showHighlightNotesManager(character, list, index, back)
        return
    end
    local function close_and(fn)
        return function()
            UIManager:close(self._hl_note_act_dialog)
            self._hl_note_act_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = note_index + step
        if j >= 1 and j <= #entry.notes then
            entry.notes[note_index], entry.notes[j] = entry.notes[j], entry.notes[note_index]
            self:_saveFor(character)
        end
        self:showHighlightNotesManager(character, list, index, back)
    end
    self._hl_note_act_dialog = ButtonDialog:new{
        title = shorten(entry.notes[note_index], 60),
        buttons = {
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function()
                    move(-1)
                end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function()
                    move(1)
                end) },
            },
            {
                { text = _("Edit note"), callback = close_and(function()
                    self:showHighlightNoteDialog(character, list, index, note_index, back)
                end) },
                { text = _("Delete"), callback = close_and(function()
                    table.remove(entry.notes, note_index)
                    self:_saveFor(character)
                    self:showHighlightNotesManager(character, list, index, back)
                end) },
            },
            {
                { text = _("Back"), id = "close", callback = close_and(function()
                    self:showHighlightNotesManager(character, list, index, back)
                end) },
            },
        },
    }
    UIManager:show(self._hl_note_act_dialog)
end

function CharacterTracker:showHighlightNoteDialog(character, list, index, note_index, back)
    local entry = list[index]
    if type(entry) ~= "table" then
        back()
        return
    end
    local dialog
    dialog = InputDialog:new{
        title = note_index and _("Edit note") or _("Add note"),
        input = note_index and entry.notes[note_index] or "",
        input_hint = _("Write your note about this highlight"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showHighlightNotesManager(character, list, index, back)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if text ~= "" then
                            if note_index then
                                entry.notes[note_index] = text
                            else
                                table.insert(entry.notes, text)
                            end
                            self:_saveFor(character)
                        end
                        self:showHighlightNotesManager(character, list, index, back)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showTopicHighlightTextDialog(character, index, topic)
    local entry = index and character.topic_highlights[index] or nil
    local dialog
    dialog = InputDialog:new{
        title = entry and T(_("Edit %1 highlight"), getTopicLabel(entry.topic))
            or T(_("Add %1 highlight"), getTopicLabel(topic)),
        input = entry and getNoteText(entry.text) or "",
        input_hint = _("Paste or type a passage / quote"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showTopicHighlightList(character, entry and entry.topic or topic)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if text ~= "" then
                            if entry then
                                entry.text = text
                            else
                                table.insert(character.topic_highlights, { topic = topic, text = text })
                            end
                            self:saveData()
                        end
                        self:showTopicHighlightList(character, entry and entry.topic or topic)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:getPlaceById(id)
    if not id then return nil end
    for _i, place in ipairs(self.places) do
        if place.id == id then return place end
    end
    return nil
end

function CharacterTracker:getPlaceByName(name)
    if not name then return nil end
    local nl = name:lower()
    for _i, place in ipairs(self.places) do
        if place.name and place.name:lower() == nl then return place end
        for _j, alias in ipairs(place.aliases or {}) do
            if alias:lower() == nl then return place end
        end
    end
    return nil
end

function CharacterTracker:getChildPlaces(parent_id)
    local out = {}
    for _i, place in ipairs(self.places) do
        if (place.parent_id or nil) == (parent_id or nil) then
            table.insert(out, place)
        end
    end
    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

function CharacterTracker:getPlacePath(place)
    local names = {}
    local seen = {}
    local cur = place
    local depth = 0
    while cur and depth < 20 do
        if seen[cur.id] then break end
        seen[cur.id] = true
        table.insert(names, 1, cur.name or _("(unnamed)"))
        cur = self:getPlaceById(cur.parent_id)
        depth = depth + 1
    end
    return table.concat(names, " › ")
end

function CharacterTracker:_placeWouldCycle(place, new_parent_id)
    local cur = self:getPlaceById(new_parent_id)
    local depth = 0
    while cur and depth < 50 do
        if cur.id == place.id then return true end
        cur = self:getPlaceById(cur.parent_id)
        depth = depth + 1
    end
    return false
end

local PLACE_STATUSES = {
    { key = "standing",  label = _("Standing") },
    { key = "thriving",  label = _("Thriving") },
    { key = "declining", label = _("Declining") },
    { key = "ruined",    label = _("Ruined") },
    { key = "destroyed", label = _("Destroyed") },
    { key = "abandoned", label = _("Abandoned") },
    { key = "hidden",    label = _("Hidden") },
    { key = "disputed",  label = _("Disputed") },
}

local function getPlaceStatusLabel(key)
    if not key or key == "" then return nil end
    for _i, st in ipairs(PLACE_STATUSES) do
        if st.key == key then return st.label end
    end
    return key
end

local PLACE_CONNECTION_KINDS = {
    { key = "borders",  label = _("Borders"),       inverse = "borders" },
    { key = "road",     label = _("Road to"),       inverse = "road" },
    { key = "sea",      label = _("Sea route to"),  inverse = "sea" },
    { key = "river",    label = _("River to"),      inverse = "river" },
    { key = "allied",   label = _("Allied with"),   inverse = "allied" },
    { key = "war",      label = _("At war with"),   inverse = "war" },
    { key = "trade",    label = _("Trades with"),   inverse = "trade" },
    { key = "rival",    label = _("Rival of"),      inverse = "rival" },
    { key = "vassal",   label = _("Vassal of"),     inverse = "overlord" },
    { key = "overlord", label = _("Overlord of"),   inverse = "vassal" },
    { key = "near",     label = _("Near"),          inverse = "near" },
}

local function getPlaceConnectionLabel(kind, incoming)
    for _i, k in ipairs(PLACE_CONNECTION_KINDS) do
        if k.key == kind then
            if not incoming then return k.label end
            for _j, other in ipairs(PLACE_CONNECTION_KINDS) do
                if other.key == k.inverse then return other.label end
            end
            return k.label
        end
    end
    local forward, reverse = (kind or ""):match("^(.-)%s*/%s*(.-)$")
    if forward and forward ~= "" then
        if incoming then return reverse ~= "" and reverse or forward end
        return forward
    end
    return kind or ""
end

local PLACE_SECTIONS = {
    { key = "facts",       label = _("Facts") },
    { key = "rulers",      label = _("Rulers") },
    { key = "features",    label = _("Notable features") },
    { key = "subplaces",   label = _("Sub-places") },
    { key = "residents",   label = _("Residents") },
    { key = "connections", label = _("Connections") },
    { key = "history",     label = _("History") },
    { key = "secrets",     label = _("Secrets") },
    { key = "notes",       label = _("Notes") },
    { key = "timeline",    label = _("Timeline events") },
}

local PLACE_FACT_PRESETS = {
    _("Population"), _("Government"), _("Climate"), _("Terrain"), _("Founded"),
    _("Language"), _("Religion"), _("Currency"), _("Exports"), _("Defenses"),
}

function CharacterTracker:getPlaceSectionOrder(place)
    local order, seen = {}, {}
    for _i, key in ipairs(place.section_order or {}) do
        for _j, section in ipairs(PLACE_SECTIONS) do
            if section.key == key and not seen[key] then
                seen[key] = true
                order[#order + 1] = key
            end
        end
    end
    for _i, section in ipairs(PLACE_SECTIONS) do
        if not seen[section.key] then order[#order + 1] = section.key end
    end
    return order
end

function CharacterTracker:_countDescendantPlaces(place_id, seen)
    seen = seen or {}
    local total = 0
    for _i, kid in ipairs(self:getChildPlaces(place_id)) do
        if not seen[kid.id] then
            seen[kid.id] = true
            total = total + 1 + self:_countDescendantPlaces(kid.id, seen)
        end
    end
    return total
end

function CharacterTracker:showPlaceList()
    self._place_collapsed = self._place_collapsed or {}
    local item_table = {}
    table.insert(item_table, {
        text = _("+ Add place"),
        callback = function()
            self:showAddPlaceDialog(nil)
        end,
    })
    local menu_container
    local menu
    local seen = {}
    local function walk(parent_id, depth)
        for _i, place in ipairs(self:getChildPlaces(parent_id)) do
            if not seen[place.id] then
                seen[place.id] = true
                local indent = ("    "):rep(depth)
                local kids = self:getChildPlaces(place.id)
                local collapsed = self._place_collapsed[place.id]
                local marker = #kids > 0 and (collapsed and "▸ " or "▾ ") or "   "
                local suffix = "  ·  " .. getPlaceTypeLabel(place.type)
                local status = getPlaceStatusLabel(place.status)
                if status then suffix = suffix .. "  ·  " .. status end
                if #kids > 0 then
                    suffix = suffix .. T(_("  ·  %1 sub-places"), #kids)
                end
                if place.residents and #place.residents > 0 then
                    suffix = suffix .. T(_("  ·  %1 residents"), #place.residents)
                end
                table.insert(item_table, {
                    text = indent .. marker .. (place.name or _("(unnamed)")) .. suffix,
                    callback = function()
                        self:showPlaceDetail(place)
                    end,
                    hold_callback = function()
                        if #kids > 0 then
                            self._place_collapsed[place.id] = not collapsed or nil
                            UIManager:close(menu_container)
                            self:showPlaceList()
                        end
                    end,
                })
                if not collapsed then walk(place.id, depth + 1) end
            end
        end
    end
    walk(nil, 0)

    menu = Menu:new{
        title = T(_("Places (%1)"), #self.places),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        onMenuHold = function(_self, item)
            if item.hold_callback then item.hold_callback() end
            return true
        end,
        close_callback = function()
            UIManager:close(menu_container)
        end,
    }
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

function CharacterTracker:buildPlaceText(place)
    local parts = {}
    if place.aliases and #place.aliases > 0 then
        table.insert(parts, _("Aliases") .. ": " .. table.concat(place.aliases, ", ") .. "\n")
    end
    local head = _("Type") .. ": " .. getPlaceTypeLabel(place.type)
    local status = getPlaceStatusLabel(place.status)
    if status then head = head .. "  ·  " .. _("Status") .. ": " .. status end
    table.insert(parts, head .. "\n")

    local path = self:getPlacePath(place)
    if path and path ~= (place.name or "") then
        table.insert(parts, _("Location") .. ": " .. path .. "\n")
    end

    local current = {}
    for _i, r in ipairs(place.rulers or {}) do
        if not r.past then table.insert(current, r.name or "?") end
    end
    if #current > 0 then
        table.insert(parts, _("Ruled by") .. ": " .. table.concat(current, ", ") .. "\n")
    end

    if place.description and place.description ~= "" then
        table.insert(parts, "\n" .. place.description .. "\n")
    end

    local builders = {}

    builders.facts = function()
        if not place.facts or #place.facts == 0 then return nil end
        local lines = {}
        for _i, fact in ipairs(place.facts) do
            table.insert(lines, (fact.label or "?") .. ": " .. (fact.value or ""))
        end
        return pageBlock(T(_("Facts (%1)"), #lines), pageBullets(lines, "• "))
    end

    builders.rulers = function()
        if not place.rulers or #place.rulers == 0 then return nil end
        local lines = {}
        for _i, r in ipairs(place.rulers) do
            local line = r.name or "?"
            if r.note and r.note ~= "" then line = line .. " — " .. r.note end
            if r.past then line = line .. " (" .. _("former") .. ")" end
            table.insert(lines, line)
        end
        return pageBlock(T(_("Rulers (%1)"), #lines), pageBullets(lines, "• "))
    end

    builders.features = function()
        if not place.features or #place.features == 0 then return nil end
        return pageBlock(T(_("Notable features (%1)"), #place.features), pageBullets(place.features, "• "))
    end

    builders.subplaces = function()
        local total = self:_countDescendantPlaces(place.id)
        if total == 0 then return nil end
        local out, seen = {}, { [place.id] = true }
        local function tree(parent_id, prefix)
            local kids = self:getChildPlaces(parent_id)
            for i, kid in ipairs(kids) do
                if not seen[kid.id] then
                    seen[kid.id] = true
                    local last = i == #kids
                    local line = prefix .. (last and "└─ " or "├─ ") .. (kid.name or _("(unnamed)"))
                        .. " · " .. getPlaceTypeLabel(kid.type)
                    local kid_status = getPlaceStatusLabel(kid.status)
                    if kid_status then line = line .. " · " .. kid_status end
                    table.insert(out, line)
                    tree(kid.id, prefix .. (last and "   " or "│  "))
                end
            end
        end
        tree(place.id, "")
        return pageBlock(T(_("Sub-places (%1)"), total), table.concat(out, "\n") .. "\n")
    end

    builders.residents = function()
        if not place.residents or #place.residents == 0 then return nil end
        local lines = {}
        for _i, r in ipairs(place.residents) do
            local kind
            if r.kind == "works" then
                kind = r.past and _("worked here") or _("works here")
            else
                kind = r.past and _("lived here") or _("lives here")
            end
            local line = r.name or "?"
            if r.role and r.role ~= "" then line = line .. " — " .. r.role end
            table.insert(lines, line .. " · " .. kind)
        end
        return pageBlock(T(_("Residents (%1)"), #lines), pageBullets(lines, "• "))
    end

    builders.connections = function()
        local lines = {}
        local function add(text, c)
            local entry = "• " .. text .. "\n"
            for _i, note in ipairs(c.notes or {}) do
                entry = entry .. "  • " .. note .. "\n"
            end
            for _i, secret in ipairs(c.secrets or {}) do
                entry = entry .. "  • " .. _("Secret") .. ": " .. secret .. "\n"
            end
            table.insert(lines, entry)
        end
        local function travel(c)
            if c.travel and c.travel ~= "" then return " · " .. c.travel end
            return ""
        end
        for _i, c in ipairs(place.connections or {}) do
            local other = self:getPlaceById(c.to)
            if other then
                add(getPlaceConnectionLabel(c.kind, false) .. " " .. (other.name or "?") .. travel(c), c)
            end
        end
        for _i, other in ipairs(self.places) do
            if other.id ~= place.id then
                for _j, c in ipairs(other.connections or {}) do
                    if c.to == place.id then
                        add(getPlaceConnectionLabel(c.kind, true) .. " " .. (other.name or "?") .. travel(c), c)
                    end
                end
            end
        end
        if #lines == 0 then return nil end
        return pageBlock(T(_("Connections (%1)"), #lines), table.concat(lines))
    end

    builders.history = function()
        if not place.history or #place.history == 0 then return nil end
        return pageBlock(T(_("History (%1)"), #place.history), pageBullets(place.history, "• "))
    end

    builders.secrets = function()
        if not place.secrets or #place.secrets == 0 then return nil end
        return pageBlock(T(_("Secrets (%1)"), #place.secrets), pageBullets(place.secrets, "• "))
    end

    builders.timeline = function()
        local lines = self:_timelineEventLines("places", place.name)
        if #lines == 0 then return nil end
        return pageBlock(T(_("Timeline events (%1)"), #lines), pageBullets(lines, "• "))
    end

    builders.notes = function()
        if not place.notes or #place.notes == 0 then return nil end
        return pageBlock(T(_("Notes (%1)"), #place.notes), pageBullets(place.notes, "• "))
    end

    for _i, key in ipairs(self:getPlaceSectionOrder(place)) do
        if not self:isPlaceSectionHidden(key) then
            local text = builders[key]()
            if text then table.insert(parts, text) end
        end
    end
    return (table.concat(parts):gsub("^\n+", ""))
end

function CharacterTracker:isPlaceSectionHidden(key)
    local hidden = LayoutSettings and LayoutSettings:readSetting("character_tracker_hidden_place_sections")
    return type(hidden) == "table" and hidden[key] == true
end

function CharacterTracker:setPlaceSectionHidden(key, value)
    if not G_reader_settings then return end
    local hidden = LayoutSettings:readSetting("character_tracker_hidden_place_sections")
    local updated = {}
    if type(hidden) == "table" then
        for k, v in pairs(hidden) do updated[k] = v end
    end
    updated[key] = value or nil
    LayoutSettings:saveSetting("character_tracker_hidden_place_sections", updated)
end

function CharacterTracker:showPlaceDetail(place)
    local viewer
    local function reopen() self:showPlaceDetail(place) end
    local function list(field, title, add_label, add_title, edit_title, hint)
        self:showStringListManager(place, field, {
            title = title,
            add_label = add_label,
            add_title = add_title,
            edit_title = edit_title,
            hint = hint,
            on_change = function() self:savePlaces() end,
            on_close = reopen,
        })
    end
    local function go(fn)
        return function()
            UIManager:close(viewer)
            fn()
        end
    end
    local defs = {
        { text = _("Rename"), callback = go(function() self:showRenamePlaceDialog(place, reopen) end) },
        { text = _("Type"), callback = go(function() self:showPlaceTypePicker(place, reopen) end) },
        { text = _("Status"), callback = go(function() self:showPlaceStatusPicker(place, reopen) end) },
        { text = _("Description"), callback = go(function() self:showPlaceDescriptionDialog(place, reopen) end) },
        { text = _("Aliases"), callback = go(function() self:showPlaceAliasManager(place, reopen) end) },
        { text = _("＋ Sub-place"), callback = go(function() self:showAddPlaceDialog(place.id, reopen) end) },
        { section = "facts", text = _("Facts"), callback = go(function() self:showPlaceFactsManager(place) end) },
        { section = "rulers", text = _("Rulers"), callback = go(function() self:showPlaceRulersManager(place) end) },
        { section = "features", text = _("Features"), callback = go(function()
            list("features", _("Notable features"), _("+ Add feature"), _("Add feature"), _("Edit feature"), _("a landmark, a famous inn, a hidden cave"))
        end) },
        { section = "residents", text = _("Residents"), callback = go(function() self:showPlaceResidentsManager(place) end) },
        { section = "connections", text = _("Connections"), callback = go(function() self:showPlaceConnectionsManager(place) end) },
        { section = "history", text = _("History"), callback = go(function()
            list("history", _("History"), _("+ Add event"), _("Add event"), _("Edit event"), _("a founding, a siege, a disaster"))
        end) },
        { section = "secrets", text = _("Secrets"), callback = go(function()
            list("secrets", _("Secrets"), _("+ Add secret"), _("Add secret"), _("Edit secret"), _("something hidden about this place"))
        end) },
        { section = "notes", text = _("Notes"), callback = go(function()
            list("notes", _("Notes"), _("+ Add note"), _("Add note"), _("Edit note"), _("anything worth remembering"))
        end) },
        { text = _("More"), callback = go(function() self:showPlaceMoreMenu(place) end) },
    }
    local rows, row = {}, {}
    for _i, def in ipairs(defs) do
        if not def.section or not self:isPlaceSectionHidden(def.section) then
            table.insert(row, { text = def.text, callback = def.callback })
            if #row >= 4 then
                table.insert(rows, row)
                row = {}
            end
        end
    end
    if #row > 0 then table.insert(rows, row) end
    table.insert(rows, {
        { text = _("Delete"), callback = go(function() self:deletePlace(place) end) },
        { text = _("Open list"), callback = go(function() self:showPlaceList() end) },
        { text = _("Close"), id = "close", callback = go(function() end) },
    })
    viewer = self:newTextViewer("place"){
        title = place.name or _("Place"),
        text = self:buildPlaceText(place),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = rows,
    }
    UIManager:show(viewer)
end

function CharacterTracker:showPlaceMoreMenu(place)
    local function reopen() self:showPlaceDetail(place) end
    local function close_and(fn)
        return function()
            UIManager:close(self._place_more_dialog)
            self._place_more_dialog = nil
            fn()
        end
    end
    local rows = {
        {
            { text = _("Move to another parent"), callback = close_and(function()
                self:showPlaceParentPicker(place, reopen)
            end) },
            { text = _("Arrange sections"), callback = close_and(function()
                self:showPlaceSectionOrderDialog(place)
            end) },
        },
    }
    local parent = self:getPlaceById(place.parent_id)
    if parent then
        table.insert(rows, {
            { text = T(_("Open '%1'"), shorten(parent.name or "?", 30)), callback = close_and(function()
                self:showPlaceDetail(parent)
            end) },
        })
    end
    table.insert(rows, {
        { text = _("Back"), id = "close", callback = close_and(reopen) },
    })
    self._place_more_dialog = self:newButtonDialog("place_more"){
        title = T(_("More — %1"), place.name or "?"),
        buttons = rows,
    }
    UIManager:show(self._place_more_dialog)
end

function CharacterTracker:showPlaceSectionOrderDialog(place)
    local order = self:getPlaceSectionOrder(place)
    local labels = {}
    for _i, section in ipairs(PLACE_SECTIONS) do labels[section.key] = section.label end
    local function reshow()
        UIManager:close(self._place_order_dialog)
        self._place_order_dialog = nil
        self:showPlaceSectionOrderDialog(place)
    end
    local buttons = {}
    for i, key in ipairs(order) do
        table.insert(buttons, {
            { text = "▲", callback = function()
                if i > 1 then
                    order[i], order[i - 1] = order[i - 1], order[i]
                    place.section_order = order
                    self:savePlaces()
                end
                reshow()
            end },
            { text = (labels[key] or key) .. (self:isPlaceSectionHidden(key) and (" (" .. _("hidden") .. ")") or ""),
              callback = function() end },
            { text = "▼", callback = function()
                if i < #order then
                    order[i], order[i + 1] = order[i + 1], order[i]
                    place.section_order = order
                    self:savePlaces()
                end
                reshow()
            end },
            { text = self:isPlaceSectionHidden(key) and _("Show") or _("Hide"), callback = function()
                self:setPlaceSectionHidden(key, not self:isPlaceSectionHidden(key))
                reshow()
            end },
        })
    end
    table.insert(buttons, {
        { text = _("Reset order"), callback = function()
            place.section_order = {}
            self:savePlaces()
            reshow()
        end },
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._place_order_dialog)
            self._place_order_dialog = nil
            self:showPlaceDetail(place)
        end },
    })
    self._place_order_dialog = ButtonDialog:new{
        title = T(_("Page sections — %1\n(▲ / ▼ to move · Hide applies to every place)"), place.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._place_order_dialog)
end

function CharacterTracker:showPlaceStatusPicker(place, on_done)
    local choices = {}
    for _i, st in ipairs(PLACE_STATUSES) do
        table.insert(choices, { label = (place.status == st.key and "✓ " or "") .. st.label, value = st.key })
    end
    table.insert(choices, { label = _("— none —"), value = "" })
    self:_showChoice(T(_("Status of '%1'"), place.name or "?"), choices, function(value)
        place.status = value
        self:savePlaces()
        if on_done then on_done() end
    end, { hint = _("e.g. besieged, cursed, occupied") })
end

function CharacterTracker:_showListEntryActions(title, list, index, opts)
    local function close_and(fn)
        return function()
            UIManager:close(self._list_entry_dialog)
            self._list_entry_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = index + step
        if j >= 1 and j <= #list then
            list[index], list[j] = list[j], list[index]
            opts.on_change()
        end
        opts.back()
    end
    local rows = {}
    if opts.on_edit then
        table.insert(rows, {
            { text = _("Edit"), callback = close_and(function() opts.on_edit(index) end) },
        })
    end
    if opts.extra then
        for _i, row in ipairs(opts.extra(close_and)) do table.insert(rows, row) end
    end
    table.insert(rows, {
        { text = "▲ " .. _("Move up"), callback = close_and(function() move(-1) end) },
        { text = "▼ " .. _("Move down"), callback = close_and(function() move(1) end) },
    })
    table.insert(rows, {
        { text = _("Delete"), callback = close_and(function()
            table.remove(list, index)
            opts.on_change()
            opts.back()
        end) },
        { text = _("Back"), id = "close", callback = close_and(opts.back) },
    })
    self._list_entry_dialog = ButtonDialog:new{
        title = shorten(title, 60),
        buttons = rows,
    }
    UIManager:show(self._list_entry_dialog)
end

function CharacterTracker:showPlaceFactsManager(place)
    if type(place.facts) ~= "table" then place.facts = {} end
    local function back() self:showPlaceFactsManager(place) end
    local buttons = {}
    for i, fact in ipairs(place.facts) do
        table.insert(buttons, {
            {
                text = shorten((fact.label or "?") .. ": " .. (fact.value or ""), 42),
                callback = function()
                    UIManager:close(self._place_facts_dialog)
                    self._place_facts_dialog = nil
                    self:_showListEntryActions((fact.label or "?") .. ": " .. (fact.value or ""), place.facts, i, {
                        on_edit = function(index) self:showPlaceFactDialog(place, index) end,
                        on_change = function() self:savePlaces() end,
                        back = back,
                    })
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._place_facts_dialog)
                    self._place_facts_dialog = nil
                    table.remove(place.facts, i)
                    self:savePlaces()
                    back()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add fact"),
            callback = function()
                UIManager:close(self._place_facts_dialog)
                self._place_facts_dialog = nil
                local choices = {}
                for _i, preset in ipairs(PLACE_FACT_PRESETS) do
                    table.insert(choices, { label = preset, value = preset })
                end
                self:_showChoice(T(_("Add a fact to '%1'"), place.name or "?"), choices, function(label)
                    self:showPlaceFactDialog(place, nil, label)
                end, { hint = _("What is this fact about?") })
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._place_facts_dialog)
                self._place_facts_dialog = nil
                self:showPlaceDetail(place)
            end,
        },
    })
    self._place_facts_dialog = ButtonDialog:new{
        title = T(_("Facts — %1"), place.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._place_facts_dialog)
end

function CharacterTracker:showPlaceFactDialog(place, index, preset)
    local fact = index and place.facts[index] or nil
    local dialog
    dialog = MultiInputDialog:new{
        title = fact and _("Edit fact") or _("Add fact"),
        fields = {
            { text = fact and fact.label or preset or "", hint = _("Label — e.g. Population") },
            { text = fact and fact.value or "", hint = _("Value — e.g. about 12,000") },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showPlaceFactsManager(place)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local label, value = trim(fields[1]), trim(fields[2])
                        UIManager:close(dialog)
                        if label ~= "" then
                            if fact then
                                fact.label, fact.value = label, value
                            else
                                table.insert(place.facts, { label = label, value = value })
                            end
                            self:savePlaces()
                        end
                        self:showPlaceFactsManager(place)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showPlaceRulersManager(place)
    if type(place.rulers) ~= "table" then place.rulers = {} end
    local function back() self:showPlaceRulersManager(place) end
    local function describe(r)
        local text = r.name or "?"
        if r.note and r.note ~= "" then text = text .. " — " .. r.note end
        if r.past then text = text .. " (" .. _("former") .. ")" end
        return text
    end
    local buttons = {}
    for i, r in ipairs(place.rulers) do
        table.insert(buttons, {
            {
                text = shorten(describe(r), 42),
                callback = function()
                    UIManager:close(self._place_rulers_dialog)
                    self._place_rulers_dialog = nil
                    self:_showListEntryActions(describe(r), place.rulers, i, {
                        on_edit = function(index)
                            local dialog
                            dialog = InputDialog:new{
                                title = T(_("Note on %1"), r.name or "?"),
                                input = r.note or "",
                                input_hint = _("e.g. king, regent, usurper, elected"),
                                buttons = {
                                    {
                                        {
                                            text = _("Cancel"),
                                            id = "close",
                                            callback = function()
                                                UIManager:close(dialog)
                                                back()
                                            end,
                                        },
                                        {
                                            text = _("Save"),
                                            is_enter_default = true,
                                            callback = function()
                                                r.note = trim(dialog:getInputText())
                                                UIManager:close(dialog)
                                                self:savePlaces()
                                                back()
                                            end,
                                        },
                                    },
                                },
                            }
                            self:_showInputDialog(dialog)
                        end,
                        extra = function(close_and)
                            return {
                                {
                                    { text = r.past and _("Mark as current") or _("Mark as former"), callback = close_and(function()
                                        r.past = not r.past or nil
                                        self:savePlaces()
                                        back()
                                    end) },
                                    { text = _("Open character"), callback = close_and(function()
                                        local char = self:getCharacterByName(r.name)
                                        if char then
                                            self:showCharacterDetail(char)
                                        else
                                            UIManager:show(InfoMessage:new{
                                                text = T(_("Character '%1' not found."), r.name or "?"),
                                            })
                                            back()
                                        end
                                    end) },
                                },
                            }
                        end,
                        on_change = function() self:savePlaces() end,
                        back = back,
                    })
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._place_rulers_dialog)
                    self._place_rulers_dialog = nil
                    table.remove(place.rulers, i)
                    self:savePlaces()
                    back()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add ruler"),
            callback = function()
                UIManager:close(self._place_rulers_dialog)
                self._place_rulers_dialog = nil
                local choices = {}
                for _i, char in ipairs(self.characters or {}) do
                    table.insert(choices, { label = char.name, value = char.name })
                end
                self:_showChoice(T(_("Who rules '%1'?"), place.name or "?"), choices, function(name)
                    table.insert(place.rulers, { name = name, note = "", past = nil })
                    self:savePlaces()
                    back()
                end, { hint = _("Name of the ruler") })
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._place_rulers_dialog)
                self._place_rulers_dialog = nil
                self:showPlaceDetail(place)
            end,
        },
    })
    self._place_rulers_dialog = ButtonDialog:new{
        title = T(_("Rulers — %1\n(first = current ruler)"), place.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._place_rulers_dialog)
end

function CharacterTracker:showPlaceConnectionsManager(place)
    if type(place.connections) ~= "table" then place.connections = {} end
    local function back() self:showPlaceConnectionsManager(place) end
    local function describe(c)
        local other = self:getPlaceById(c.to)
        return getPlaceConnectionLabel(c.kind, false) .. " " .. (other and other.name or "?")
    end
    local buttons = {}
    for i, c in ipairs(place.connections) do
        local extras = (c.notes and #c.notes or 0) + (c.secrets and #c.secrets or 0)
        table.insert(buttons, {
            {
                text = shorten(describe(c), 40) .. (extras > 0 and (" ✎" .. extras) or ""),
                callback = function()
                    UIManager:close(self._place_conn_dialog)
                    self._place_conn_dialog = nil
                    self:_showListEntryActions(describe(c), place.connections, i, {
                        extra = function(close_and)
                            return {
                                {
                                    { text = _("Change kind"), callback = close_and(function()
                                        self:showPlaceConnectionKindPicker(place, function(kind)
                                            c.kind = kind
                                            self:savePlaces()
                                            back()
                                        end)
                                    end) },
                                    { text = _("Travel / distance"), callback = close_and(function()
                                        self:showPlaceConnectionTravelDialog(c, function()
                                            self:savePlaces()
                                            back()
                                        end)
                                    end) },
                                },
                                {
                                    { text = _("Notes & secrets"), callback = close_and(function()
                                        self:showEntryNotesSecrets(place, c, describe(c), back, function() self:savePlaces() end)
                                    end) },
                                    { text = _("Open place"), callback = close_and(function()
                                        local other = self:getPlaceById(c.to)
                                        if other then self:showPlaceDetail(other) else back() end
                                    end) },
                                },
                            }
                        end,
                        on_change = function() self:savePlaces() end,
                        back = back,
                    })
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._place_conn_dialog)
                    self._place_conn_dialog = nil
                    table.remove(place.connections, i)
                    self:savePlaces()
                    back()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add connection"),
            callback = function()
                UIManager:close(self._place_conn_dialog)
                self._place_conn_dialog = nil
                local choices = {}
                for _i, other in ipairs(self.places) do
                    if other.id ~= place.id then
                        table.insert(choices, { label = shorten(self:getPlacePath(other), 34), value = other.id })
                    end
                end
                if #choices == 0 then
                    UIManager:show(InfoMessage:new{ text = _("Add another place first.") })
                    back()
                    return
                end
                self:_showChoice(T(_("Connect '%1' to…"), place.name or "?"), choices, function(other_id)
                    self:showPlaceConnectionKindPicker(place, function(kind)
                        local entry = { to = other_id, kind = kind, travel = "", notes = {}, secrets = {} }
                        self:showPlaceConnectionTravelDialog(entry, function()
                            table.insert(place.connections, entry)
                            self:savePlaces()
                            back()
                        end)
                    end)
                end)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._place_conn_dialog)
                self._place_conn_dialog = nil
                self:showPlaceDetail(place)
            end,
        },
    })
    self._place_conn_dialog = ButtonDialog:new{
        title = T(_("Connections — %1"), place.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._place_conn_dialog)
end

function CharacterTracker:showPlaceConnectionKindPicker(place, on_pick)
    local choices = {}
    for _i, k in ipairs(PLACE_CONNECTION_KINDS) do
        table.insert(choices, { label = k.label, value = k.key })
    end
    self:_showChoice(T(_("How is '%1' connected?"), place.name or "?"), choices, on_pick,
        { hint = _("A custom kind, e.g. smuggling route — or \"Overlooks / Overlooked by\" for both directions") })
end

function CharacterTracker:showPlaceConnectionTravelDialog(entry, on_done)
    local dialog
    dialog = InputDialog:new{
        title = _("Travel time / distance"),
        input = entry.travel or "",
        input_hint = _("e.g. 3 days by road (optional)"),
        buttons = {
            {
                {
                    text = _("Skip"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        on_done()
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        entry.travel = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        on_done()
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showPlaceAliasManager(place, on_done)
    self:showStringListManager(place, "aliases", {
        title = _("Aliases"),
        add_label = _("+ Add alias"),
        add_title = _("Add alias"),
        edit_title = _("Edit alias"),
        hint = _("another name for this place"),
        on_change = function()
            self:savePlaces()
            self:rebuildMarksForPlace(place)
        end,
        on_close = on_done,
    })
end

function CharacterTracker:showCompendiumAliasManager(entry, on_done)
    self:showStringListManager(entry, "aliases", {
        title = _("Aliases"),
        add_label = _("+ Add alias"),
        add_title = _("Add alias"),
        edit_title = _("Edit alias"),
        hint = _("another name for this entry"),
        on_change = function()
            self:saveCompendium()
            self:rebuildMarksForObject(entry)
        end,
        on_close = on_done,
    })
end

function CharacterTracker:showAddPlaceDialog(parent_id, on_done, preselected_name)
    local dialog
    local parent = self:getPlaceById(parent_id)
    dialog = InputDialog:new{
        input = preselected_name or "",
        title = parent and T(_("Add sub-place inside '%1'"), parent.name) or _("Add place"),
        input_hint = _("Place name (e.g. Winterfell, Free City of Braavos)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name == "" then return end
                        local place = {
                            id = genId(),
                            name = name,
                            type = "",
                            description = "",
                            parent_id = parent_id,
                            residents = {},
                            aliases = {},
                            status = "",
                            facts = {},
                            rulers = {},
                            features = {},
                            connections = {},
                            history = {},
                            secrets = {},
                            notes = {},
                            section_order = {},
                            created = os.date("%Y-%m-%d %H:%M"),
                        }
                        table.insert(self.places, place)
                        self:savePlaces()
                        self:rebuildMarksForPlace(place)
                        self:showPlaceTypePicker(place, function()
                            if on_done then on_done() else self:showPlaceDetail(place) end
                        end)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showPlaceTypePicker(place, on_done)
    local buttons = {}
    local row = {}
    for _i, pt in ipairs(PLACE_TYPES) do
        if pt.key ~= "custom" then
            table.insert(row, {
                text = pt.label,
                callback = function()
                    UIManager:close(self._place_type_dialog)
                    self._place_type_dialog = nil
                    place.type = pt.key
                    self:savePlaces()
                    if on_done then on_done() end
                end,
            })
            if #row >= 3 then
                table.insert(buttons, row)
                row = {}
            end
        end
    end
    if #row > 0 then table.insert(buttons, row) end

    table.insert(buttons, {
        {
            text = _("Custom…"),
            callback = function()
                UIManager:close(self._place_type_dialog)
                self._place_type_dialog = nil
                local dialog
                dialog = InputDialog:new{
                    title = _("Custom place type"),
                    input = (place.type ~= "" and getPlaceTypeLabel(place.type)) or "",
                    input_hint = _("e.g. sultanate, march, protectorate"),
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                        { text = _("Save"), is_enter_default = true, callback = function()
                            local t = dialog:getInputText():match("^%s*(.-)%s*$")
                            UIManager:close(dialog)
                            if t ~= "" then
                                place.type = t
                                self:savePlaces()
                            end
                            if on_done then on_done() end
                        end },
                    }},
                }
                self:_showInputDialog(dialog)
            end,
        },
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._place_type_dialog)
                self._place_type_dialog = nil
            end,
        },
    })

    self._place_type_dialog = ButtonDialog:new{
        title = T(_("Type of '%1'"), place.name),
        buttons = buttons,
    }
    UIManager:show(self._place_type_dialog)
end

function CharacterTracker:showPlaceDescriptionDialog(place, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Description — %1"), place.name),
        input = place.description or "",
        input_hint = _("Describe this place…"),
        text_height = math.floor(Device.screen:getHeight() * 0.35),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        place.description = text
                        self:savePlaces()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showRenamePlaceDialog(place, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Rename '%1'"), place.name),
        input = place.name or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name ~= "" and name ~= place.name then
                            local old_name = place.name
                            place.name = name
                            self:savePlaces()
                            self:removeMarksForPlaceName(old_name)
                            self:_renameInTimelines("places", old_name, name)
                            self:rebuildMarksForPlace(place)
                        end
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showPlaceParentPicker(place, on_done)
    local buttons = {}
    table.insert(buttons, {
        {
            text = _("— top level (no parent) —"),
            callback = function()
                UIManager:close(self._place_parent_dialog)
                self._place_parent_dialog = nil
                place.parent_id = nil
                self:savePlaces()
                if on_done then on_done() end
            end,
        },
    })
    for _i, cand in ipairs(self.places) do
        if cand.id ~= place.id and not self:_placeWouldCycle(place, cand.id) then
            table.insert(buttons, {
                {
                    text = self:getPlacePath(cand),
                    callback = function()
                        UIManager:close(self._place_parent_dialog)
                        self._place_parent_dialog = nil
                        place.parent_id = cand.id
                        self:savePlaces()
                        if on_done then on_done() end
                    end,
                },
            })
        end
    end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._place_parent_dialog)
                self._place_parent_dialog = nil
                if on_done then on_done() end
            end,
        },
    })
    self._place_parent_dialog = ButtonDialog:new{
        title = T(_("Move '%1' under…"), place.name),
        buttons = buttons,
    }
    UIManager:show(self._place_parent_dialog)
end

function CharacterTracker:deletePlace(place)
    local kids = self:getChildPlaces(place.id)
    local msg
    if #kids > 0 then
        msg = T(_("Delete place '%1'?\n\nIts %2 sub-place(s) will be moved up to the parent level."),
            place.name, #kids)
    else
        msg = T(_("Delete place '%1'?"), place.name)
    end
    UIManager:show(ConfirmBox:new{
        text = msg,
        ok_text = _("Delete"),
        ok_callback = function()
            for _i, kid in ipairs(kids) do
                kid.parent_id = place.parent_id
            end
            for i = #self.places, 1, -1 do
                if self.places[i].id == place.id then
                    table.remove(self.places, i)
                    break
                end
            end
            for _i, other in ipairs(self.places) do
                for j = #(other.connections or {}), 1, -1 do
                    if other.connections[j].to == place.id then
                        table.remove(other.connections, j)
                    end
                end
            end
            self:savePlaces()
            self:removeMarksForPlaceName(place.name)
            UIManager:show(InfoMessage:new{
                text = T(_("Place '%1' deleted."), place.name),
                timeout = 2,
            })
        end,
    })
end

function CharacterTracker:showPlaceResidentsManager(place)
    if not place.residents then place.residents = {} end
    local buttons = {}

    for i, r in ipairs(place.residents) do
        local kind
        if r.kind == "works" then
            kind = r.past and _("worked") or _("works")
        else
            kind = r.past and _("lived") or _("lives")
        end
        local label = (r.name or "?") .. "  (" .. kind
        if r.past then label = label .. ", " .. _("past") end
        label = label .. ")"
        if r.role and r.role ~= "" then label = label .. " — " .. r.role end
        label = shorten(label, 42)
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._place_res_dialog)
                    self._place_res_dialog = nil
                    self:showPlaceResidentActions(place, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._place_res_dialog)
                    self._place_res_dialog = nil
                    table.remove(place.residents, i)
                    self:savePlaces()
                    self:showPlaceResidentsManager(place)
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = _("+ Add resident"),
            callback = function()
                UIManager:close(self._place_res_dialog)
                self._place_res_dialog = nil
                self:showAddResidentPicker(place)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._place_res_dialog)
                self._place_res_dialog = nil
            end,
        },
    })

    self._place_res_dialog = ButtonDialog:new{
        title = T(_("Residents — %1"), place.name),
        buttons = buttons,
    }
    UIManager:show(self._place_res_dialog)
end

function CharacterTracker:showPlaceResidentActions(place, res_index)
    local r = place.residents[res_index]
    if not r then return end
    self._place_res_act_dialog = ButtonDialog:new{
        title = T(_("%1 @ %2"), r.name or "?", place.name),
        buttons = {
            {
                { text = r.past and _("Mark as current") or _("Mark as past"), callback = function()
                    UIManager:close(self._place_res_act_dialog); self._place_res_act_dialog = nil
                    r.past = not r.past
                    self:savePlaces()
                    self:showPlaceResidentsManager(place)
                end },
            },
            {
                { text = (r.kind == "works") and _("Change to: lives here") or _("Change to: works here"), callback = function()
                    UIManager:close(self._place_res_act_dialog); self._place_res_act_dialog = nil
                    r.kind = (r.kind == "works") and "lives" or "works"
                    self:savePlaces()
                    self:showPlaceResidentsManager(place)
                end },
            },
            {
                { text = _("Set role"), callback = function()
                    UIManager:close(self._place_res_act_dialog); self._place_res_act_dialog = nil
                    local dialog
                    dialog = InputDialog:new{
                        title = T(_("Role of %1 here"), r.name or "?"),
                        input = r.role or "",
                        input_hint = _("e.g. lord, innkeeper, prisoner, guard captain"),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                        self:showPlaceResidentsManager(place)
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        r.role = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        self:savePlaces()
                                        self:showPlaceResidentsManager(place)
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end },
                { text = _("Open character"), callback = function()
                    UIManager:close(self._place_res_act_dialog); self._place_res_act_dialog = nil
                    local char = self:getCharacterByName(r.name)
                    if char then
                        self:showCharacterDetail(char)
                    else
                        UIManager:show(InfoMessage:new{ text = T(_("Character '%1' not found."), r.name or "?") })
                        self:showPlaceResidentsManager(place)
                    end
                end },
            },
            {
                { text = "▲ " .. _("Move up"), callback = function()
                    UIManager:close(self._place_res_act_dialog); self._place_res_act_dialog = nil
                    if res_index > 1 then
                        place.residents[res_index], place.residents[res_index - 1] = place.residents[res_index - 1], place.residents[res_index]
                        self:savePlaces()
                    end
                    self:showPlaceResidentsManager(place)
                end },
                { text = "▼ " .. _("Move down"), callback = function()
                    UIManager:close(self._place_res_act_dialog); self._place_res_act_dialog = nil
                    if res_index < #place.residents then
                        place.residents[res_index], place.residents[res_index + 1] = place.residents[res_index + 1], place.residents[res_index]
                        self:savePlaces()
                    end
                    self:showPlaceResidentsManager(place)
                end },
            },
            {
                { text = _("Cancel"), id = "close", callback = function()
                    UIManager:close(self._place_res_act_dialog); self._place_res_act_dialog = nil
                    self:showPlaceResidentsManager(place)
                end },
            },
        },
    }
    UIManager:show(self._place_res_act_dialog)
end

function CharacterTracker:showAddResidentPicker(place)
    if not self.characters or #self.characters == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No characters to add. Create characters first."),
        })
        self:showPlaceResidentsManager(place)
        return
    end
    local buttons = {}
    local row = {}
    for _i, char in ipairs(self.characters) do
        table.insert(row, {
            text = char.name,
            callback = function()
                UIManager:close(self._add_resident_dialog)
                self._add_resident_dialog = nil
                self:showResidentKindPicker(place, char.name)
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._add_resident_dialog)
                self._add_resident_dialog = nil
                self:showPlaceResidentsManager(place)
            end,
        },
    })
    self._add_resident_dialog = ButtonDialog:new{
        title = T(_("Add resident to '%1'"), place.name),
        buttons = buttons,
    }
    UIManager:show(self._add_resident_dialog)
end

function CharacterTracker:showResidentKindPicker(place, char_name)
    if not place.residents then place.residents = {} end
    local function commit(kind, past)
        for _i, r in ipairs(place.residents) do
            if (r.name or ""):lower() == char_name:lower()
               and (r.kind or "lives") == kind and (r.past == true) == past then
                self:showPlaceResidentsManager(place)
                return
            end
        end
        table.insert(place.residents, { name = char_name, kind = kind, past = past })
        self:savePlaces()
        self:showPlaceResidentsManager(place)
    end
    self._resident_kind_dialog = ButtonDialog:new{
        title = T(_("'%1' at '%2'"), char_name, place.name),
        buttons = {
            { { text = _("Lives here (current)"), callback = function()
                UIManager:close(self._resident_kind_dialog); self._resident_kind_dialog = nil
                commit("lives", false) end } },
            { { text = _("Lived here (past)"), callback = function()
                UIManager:close(self._resident_kind_dialog); self._resident_kind_dialog = nil
                commit("lives", true) end } },
            { { text = _("Works here (current)"), callback = function()
                UIManager:close(self._resident_kind_dialog); self._resident_kind_dialog = nil
                commit("works", false) end } },
            { { text = _("Worked here (past)"), callback = function()
                UIManager:close(self._resident_kind_dialog); self._resident_kind_dialog = nil
                commit("works", true) end } },
            { { text = _("Cancel"), id = "close", callback = function()
                UIManager:close(self._resident_kind_dialog); self._resident_kind_dialog = nil
                self:showPlaceResidentsManager(place) end } },
        },
    }
    UIManager:show(self._resident_kind_dialog)
end

function CharacterTracker:getCompendiumEntryByName(name)
    if not name then return nil end
    local nl = name:lower()
    for _i, entry in ipairs(self.compendium) do
        if entry.name and entry.name:lower() == nl then return entry end
        for _j, alias in ipairs(entry.aliases or {}) do
            if alias:lower() == nl then return entry end
        end
    end
    return nil
end

function CharacterTracker:getCompendiumCurrentOwners(entry)
    local out = {}
    for _i, rec in ipairs(entry.ownership or {}) do
        if rec.current then table.insert(out, rec) end
    end
    return out
end

local COMPENDIUM_STATUSES = {
    { key = "intact",    label = _("Intact") },
    { key = "damaged",   label = _("Damaged") },
    { key = "broken",    label = _("Broken") },
    { key = "lost",      label = _("Lost") },
    { key = "stolen",    label = _("Stolen") },
    { key = "hidden",    label = _("Hidden") },
    { key = "sealed",    label = _("Sealed") },
    { key = "cursed",    label = _("Cursed") },
    { key = "destroyed", label = _("Destroyed") },
    { key = "unknown",   label = _("Unknown") },
}

local function getCompendiumStatusLabel(key)
    if not key or key == "" then return nil end
    for _i, st in ipairs(COMPENDIUM_STATUSES) do
        if st.key == key then return st.label end
    end
    return key
end

local COMPENDIUM_CONNECTION_KINDS = {
    { key = "part_of",     label = _("Part of"),        inverse = "contains" },
    { key = "contains",    label = _("Contains"),       inverse = "part_of" },
    { key = "requires",    label = _("Requires"),       inverse = "needed_by" },
    { key = "needed_by",   label = _("Needed by"),      inverse = "requires" },
    { key = "powers",      label = _("Powers"),         inverse = "powered_by" },
    { key = "powered_by",  label = _("Powered by"),     inverse = "powers" },
    { key = "counters",    label = _("Counters"),       inverse = "countered_by" },
    { key = "countered_by", label = _("Countered by"),  inverse = "counters" },
    { key = "derived",     label = _("Derived from"),   inverse = "source" },
    { key = "source",      label = _("Source of"),      inverse = "derived" },
    { key = "counterpart", label = _("Counterpart of"), inverse = "counterpart" },
    { key = "similar",     label = _("Similar to"),     inverse = "similar" },
}

local function getCompendiumConnectionLabel(kind, incoming)
    for _i, k in ipairs(COMPENDIUM_CONNECTION_KINDS) do
        if k.key == kind then
            if not incoming then return k.label end
            for _j, other in ipairs(COMPENDIUM_CONNECTION_KINDS) do
                if other.key == k.inverse then return other.label end
            end
            return k.label
        end
    end
    local forward, reverse = (kind or ""):match("^(.-)%s*/%s*(.-)$")
    if forward and forward ~= "" then
        if incoming then return reverse ~= "" and reverse or forward end
        return forward
    end
    return kind or ""
end

local COMPENDIUM_SECTIONS = {
    { key = "facts",       label = _("Facts") },
    { key = "properties",  label = _("Properties") },
    { key = "limitations", label = _("Limitations") },
    { key = "ownership",   label = _("Ownership") },
    { key = "connections", label = _("Connections") },
    { key = "history",     label = _("History") },
    { key = "secrets",     label = _("Secrets") },
    { key = "notes",       label = _("Notes") },
    { key = "timeline",    label = _("Timeline events") },
}

local COMPENDIUM_FACT_PRESETS = {
    _("Material"), _("Creator"), _("Origin"), _("Value"), _("Rarity"),
    _("Size"), _("Weight"), _("Author"), _("Language"), _("Era"),
}

function CharacterTracker:isCompendiumSectionHidden(key)
    local hidden = LayoutSettings and LayoutSettings:readSetting("character_tracker_hidden_compendium_sections")
    return type(hidden) == "table" and hidden[key] == true
end

function CharacterTracker:setCompendiumSectionHidden(key, value)
    if not G_reader_settings then return end
    local hidden = LayoutSettings:readSetting("character_tracker_hidden_compendium_sections")
    local updated = {}
    if type(hidden) == "table" then
        for k, v in pairs(hidden) do updated[k] = v end
    end
    updated[key] = value or nil
    LayoutSettings:saveSetting("character_tracker_hidden_compendium_sections", updated)
end

function CharacterTracker:getCompendiumSectionOrder(entry)
    local order, seen = {}, {}
    for _i, key in ipairs(entry.section_order or {}) do
        for _j, section in ipairs(COMPENDIUM_SECTIONS) do
            if section.key == key and not seen[key] then
                seen[key] = true
                order[#order + 1] = key
            end
        end
    end
    for _i, section in ipairs(COMPENDIUM_SECTIONS) do
        if not seen[section.key] then order[#order + 1] = section.key end
    end
    return order
end

function CharacterTracker:getCompendiumLocationText(entry)
    if entry.location_place then
        local place = self:getPlaceById(entry.location_place)
        if place then return self:getPlacePath(place) end
    end
    if entry.location_text and entry.location_text ~= "" then return entry.location_text end
    return nil
end

function CharacterTracker:showCompendiumList()
    self._compendium_collapsed = self._compendium_collapsed or {}
    local item_table = {}
    table.insert(item_table, {
        text = _("+ Add compendium entry"),
        callback = function()
            self:showAddCompendiumDialog()
        end,
    })
    local groups, group_order = {}, {}
    for _i, entry in ipairs(self.compendium) do
        local label = getCompendiumTypeLabel(entry.type)
        if not groups[label] then
            groups[label] = {}
            group_order[#group_order + 1] = label
        end
        table.insert(groups[label], entry)
    end
    local unspecified = getCompendiumTypeLabel("")
    table.sort(group_order, function(a, b)
        if a == unspecified then return false end
        if b == unspecified then return true end
        return a:lower() < b:lower()
    end)
    local menu_container
    local menu
    for _i, label in ipairs(group_order) do
        local list = groups[label]
        table.sort(list, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
        local collapsed = self._compendium_collapsed[label]
        table.insert(item_table, {
            text = (collapsed and "▸ " or "▾ ") .. label .. " (" .. #list .. ")",
            callback = function()
                self._compendium_collapsed[label] = not collapsed or nil
                UIManager:close(menu_container)
                self:showCompendiumList()
            end,
        })
        if not collapsed then
            for _j, entry in ipairs(list) do
                local owners = self:getCompendiumCurrentOwners(entry)
                local suffix = ""
                local status = getCompendiumStatusLabel(entry.status)
                if status then suffix = suffix .. "  ·  " .. status end
                if #owners > 0 then
                    local names = {}
                    for _k, rec in ipairs(owners) do table.insert(names, rec.owner) end
                    suffix = suffix .. T(_("  ·  owned by %1"), table.concat(names, " & "))
                end
                table.insert(item_table, {
                    text = "      " .. (entry.name or _("(unnamed)")) .. suffix,
                    callback = function()
                        self:showCompendiumDetail(entry)
                    end,
                })
            end
        end
    end

    menu = Menu:new{
        title = T(_("Compendium (%1)"), #self.compendium),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = function()
            UIManager:close(menu_container)
        end,
    }
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

function CharacterTracker:buildCompendiumText(entry)
    local parts = {}
    if entry.aliases and #entry.aliases > 0 then
        table.insert(parts, _("Aliases") .. ": " .. table.concat(entry.aliases, ", ") .. "\n")
    end
    local head = _("Type") .. ": " .. getCompendiumTypeLabel(entry.type)
    local status = getCompendiumStatusLabel(entry.status)
    if status then head = head .. "  ·  " .. _("Status") .. ": " .. status end
    table.insert(parts, head .. "\n")

    local owners = self:getCompendiumCurrentOwners(entry)
    if #owners > 0 then
        local names = {}
        for _i, rec in ipairs(owners) do table.insert(names, rec.owner or "?") end
        table.insert(parts, _("Held by") .. ": " .. table.concat(names, ", ") .. "\n")
    end
    local location = self:getCompendiumLocationText(entry)
    if location then
        table.insert(parts, _("Located at") .. ": " .. location .. "\n")
    end
    if entry.age and entry.age ~= "" then
        table.insert(parts, _("Age") .. ": " .. entry.age .. "\n")
    end
    if entry.ability and entry.ability ~= "" then
        table.insert(parts, _("Ability") .. ": " .. entry.ability .. "\n")
    end
    if entry.hide_from_belongings then
        table.insert(parts, _("(hidden from character belongings)") .. "\n")
    end
    if entry.description and entry.description ~= "" then
        table.insert(parts, "\n" .. entry.description .. "\n")
    end

    local builders = {}

    builders.facts = function()
        if not entry.facts or #entry.facts == 0 then return nil end
        local lines = {}
        for _i, fact in ipairs(entry.facts) do
            table.insert(lines, (fact.label or "?") .. ": " .. (fact.value or ""))
        end
        return pageBlock(T(_("Facts (%1)"), #lines), pageBullets(lines, "• "))
    end

    builders.properties = function()
        if not entry.properties or #entry.properties == 0 then return nil end
        return pageBlock(T(_("Properties (%1)"), #entry.properties), pageBullets(entry.properties, "• "))
    end

    builders.limitations = function()
        if not entry.limitations or #entry.limitations == 0 then return nil end
        return pageBlock(T(_("Limitations (%1)"), #entry.limitations), pageBullets(entry.limitations, "• "))
    end

    builders.ownership = function()
        if not entry.ownership or #entry.ownership == 0 then return nil end
        local lines = {}
        for _i, rec in ipairs(entry.ownership) do
            local line = "• " .. (rec.owner or "?")
            if rec.current then
                line = line .. " · " .. _("current")
            end
            line = line .. "\n"
            if rec.acquired and rec.acquired ~= "" then
                line = line .. "  " .. _("acquired") .. ": " .. rec.acquired .. "\n"
            end
            if not rec.current and rec.lost and rec.lost ~= "" then
                line = line .. "  " .. _("lost") .. ": " .. rec.lost .. "\n"
            end
            table.insert(lines, line)
        end
        return pageBlock(T(_("Ownership (%1)"), #entry.ownership), table.concat(lines, "\n"))
    end

    builders.connections = function()
        local lines = {}
        local function add(text, c)
            local item = "• " .. text .. "\n"
            for _i, note in ipairs(c.notes or {}) do
                item = item .. "  • " .. note .. "\n"
            end
            for _i, secret in ipairs(c.secrets or {}) do
                item = item .. "  • " .. _("Secret") .. ": " .. secret .. "\n"
            end
            table.insert(lines, item)
        end
        for _i, c in ipairs(entry.connections or {}) do
            local other = self:getCompendiumEntryById(c.to)
            if other then
                add(getCompendiumConnectionLabel(c.kind, false) .. " " .. (other.name or "?"), c)
            end
        end
        for _i, other in ipairs(self.compendium) do
            if other.id ~= entry.id then
                for _j, c in ipairs(other.connections or {}) do
                    if c.to == entry.id then
                        add(getCompendiumConnectionLabel(c.kind, true) .. " " .. (other.name or "?"), c)
                    end
                end
            end
        end
        if #lines == 0 then return nil end
        return pageBlock(T(_("Connections (%1)"), #lines), table.concat(lines))
    end

    builders.history = function()
        if not entry.history or #entry.history == 0 then return nil end
        return pageBlock(T(_("History (%1)"), #entry.history), pageBullets(entry.history, "• "))
    end

    builders.secrets = function()
        if not entry.secrets or #entry.secrets == 0 then return nil end
        return pageBlock(T(_("Secrets (%1)"), #entry.secrets), pageBullets(entry.secrets, "• "))
    end

    builders.timeline = function()
        local lines = self:_timelineEventLines("objects", entry.name)
        if #lines == 0 then return nil end
        return pageBlock(T(_("Timeline events (%1)"), #lines), pageBullets(lines, "• "))
    end

    builders.notes = function()
        if not entry.notes or #entry.notes == 0 then return nil end
        return pageBlock(T(_("Notes (%1)"), #entry.notes), pageBullets(entry.notes, "• "))
    end

    for _i, key in ipairs(self:getCompendiumSectionOrder(entry)) do
        if not self:isCompendiumSectionHidden(key) then
            local text = builders[key]()
            if text then table.insert(parts, text) end
        end
    end
    return (table.concat(parts):gsub("^\n+", ""))
end

function CharacterTracker:getCompendiumEntryById(id)
    if not id then return nil end
    for _i, entry in ipairs(self.compendium) do
        if entry.id == id then return entry end
    end
    return nil
end

function CharacterTracker:showCompendiumDetail(entry)
    local viewer
    local function reopen() self:showCompendiumDetail(entry) end
    local function list(field, title, add_label, add_title, edit_title, hint)
        self:showStringListManager(entry, field, {
            title = title,
            add_label = add_label,
            add_title = add_title,
            edit_title = edit_title,
            hint = hint,
            on_change = function() self:saveCompendium() end,
            on_close = reopen,
        })
    end
    local function go(fn)
        return function()
            UIManager:close(viewer)
            fn()
        end
    end
    local defs = {
        { text = _("Rename"), callback = go(function() self:showRenameCompendiumDialog(entry, reopen) end) },
        { text = _("Type"), callback = go(function() self:showCompendiumTypePicker(entry, reopen) end) },
        { text = _("Status"), callback = go(function() self:showCompendiumStatusPicker(entry, reopen) end) },
        { text = _("Description"), callback = go(function() self:showCompendiumDescriptionDialog(entry, reopen) end) },
        { text = _("Aliases"), callback = go(function() self:showCompendiumAliasManager(entry, reopen) end) },
        { text = _("Age"), callback = go(function() self:showCompendiumAgeDialog(entry, reopen) end) },
        { text = _("Ability"), callback = go(function() self:showCompendiumAbilityDialog(entry, reopen) end) },
        { text = _("Location"), callback = go(function() self:showCompendiumLocationPicker(entry, reopen) end) },
        { section = "facts", text = _("Facts"), callback = go(function() self:showCompendiumFactsManager(entry) end) },
        { section = "properties", text = _("Properties"), callback = go(function()
            list("properties", _("Properties"), _("+ Add property"), _("Add property"), _("Edit property"), _("an effect, a power, a quality"))
        end) },
        { section = "limitations", text = _("Limits"), callback = go(function()
            list("limitations", _("Limitations"), _("+ Add limitation"), _("Add limitation"), _("Edit limitation"), _("a cost, a weakness, a rule"))
        end) },
        { section = "ownership", text = _("Ownership"), callback = go(function() self:showCompendiumOwnershipManager(entry) end) },
        { section = "connections", text = _("Connections"), callback = go(function() self:showCompendiumConnectionsManager(entry) end) },
        { section = "history", text = _("History"), callback = go(function()
            list("history", _("History"), _("+ Add event"), _("Add event"), _("Edit event"), _("forged, lost, rediscovered"))
        end) },
        { section = "secrets", text = _("Secrets"), callback = go(function()
            list("secrets", _("Secrets"), _("+ Add secret"), _("Add secret"), _("Edit secret"), _("something hidden about this"))
        end) },
        { section = "notes", text = _("Notes"), callback = go(function()
            list("notes", _("Notes"), _("+ Add note"), _("Add note"), _("Edit note"), _("anything worth remembering"))
        end) },
        { text = _("More"), callback = go(function() self:showCompendiumMoreMenu(entry) end) },
    }
    local rows, row = {}, {}
    for _i, def in ipairs(defs) do
        if not def.section or not self:isCompendiumSectionHidden(def.section) then
            table.insert(row, { text = def.text, callback = def.callback })
            if #row >= 4 then
                table.insert(rows, row)
                row = {}
            end
        end
    end
    if #row > 0 then table.insert(rows, row) end
    table.insert(rows, {
        { text = _("Delete"), callback = go(function() self:deleteCompendiumEntry(entry) end) },
        { text = _("Open list"), callback = go(function() self:showCompendiumList() end) },
        { text = _("Close"), id = "close", callback = go(function() end) },
    })
    viewer = self:newTextViewer("compendium"){
        title = entry.name or _("Compendium entry"),
        text = self:buildCompendiumText(entry),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = rows,
    }
    UIManager:show(viewer)
end

function CharacterTracker:showCompendiumMoreMenu(entry)
    local function reopen() self:showCompendiumDetail(entry) end
    local function close_and(fn)
        return function()
            UIManager:close(self._compendium_more_dialog)
            self._compendium_more_dialog = nil
            fn()
        end
    end
    self._compendium_more_dialog = self:newButtonDialog("compendium_more"){
        title = T(_("More — %1"), entry.name or "?"),
        buttons = {
            {
                { text = entry.hide_from_belongings and _("Show in belongings") or _("Hide from belongings"),
                  callback = close_and(function()
                    entry.hide_from_belongings = not entry.hide_from_belongings
                    self:saveCompendium()
                    reopen()
                end) },
            },
            {
                { text = _("Arrange sections"), callback = close_and(function()
                    self:showCompendiumSectionOrderDialog(entry)
                end) },
            },
            {
                { text = _("Back"), id = "close", callback = close_and(reopen) },
            },
        },
    }
    UIManager:show(self._compendium_more_dialog)
end

function CharacterTracker:showCompendiumSectionOrderDialog(entry)
    local order = self:getCompendiumSectionOrder(entry)
    local labels = {}
    for _i, section in ipairs(COMPENDIUM_SECTIONS) do labels[section.key] = section.label end
    local function reshow()
        UIManager:close(self._compendium_order_dialog)
        self._compendium_order_dialog = nil
        self:showCompendiumSectionOrderDialog(entry)
    end
    local buttons = {}
    for i, key in ipairs(order) do
        table.insert(buttons, {
            { text = "▲", callback = function()
                if i > 1 then
                    order[i], order[i - 1] = order[i - 1], order[i]
                    entry.section_order = order
                    self:saveCompendium()
                end
                reshow()
            end },
            { text = (labels[key] or key) .. (self:isCompendiumSectionHidden(key) and (" (" .. _("hidden") .. ")") or ""),
              callback = function() end },
            { text = "▼", callback = function()
                if i < #order then
                    order[i], order[i + 1] = order[i + 1], order[i]
                    entry.section_order = order
                    self:saveCompendium()
                end
                reshow()
            end },
            { text = self:isCompendiumSectionHidden(key) and _("Show") or _("Hide"), callback = function()
                self:setCompendiumSectionHidden(key, not self:isCompendiumSectionHidden(key))
                reshow()
            end },
        })
    end
    table.insert(buttons, {
        { text = _("Reset order"), callback = function()
            entry.section_order = {}
            self:saveCompendium()
            reshow()
        end },
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._compendium_order_dialog)
            self._compendium_order_dialog = nil
            self:showCompendiumDetail(entry)
        end },
    })
    self._compendium_order_dialog = ButtonDialog:new{
        title = T(_("Page sections — %1\n(▲ / ▼ to move · Hide applies to every entry)"), entry.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._compendium_order_dialog)
end

function CharacterTracker:showCompendiumStatusPicker(entry, on_done)
    local choices = {}
    for _i, st in ipairs(COMPENDIUM_STATUSES) do
        table.insert(choices, { label = (entry.status == st.key and "✓ " or "") .. st.label, value = st.key })
    end
    table.insert(choices, { label = _("— none —"), value = "" })
    self:_showChoice(T(_("Condition of '%1'"), entry.name or "?"), choices, function(value)
        entry.status = value
        self:saveCompendium()
        if on_done then on_done() end
    end, { hint = _("e.g. dormant, awakened, corrupted") })
end

function CharacterTracker:showCompendiumLocationPicker(entry, on_done)
    local choices = {}
    for _i, place in ipairs(self.places or {}) do
        table.insert(choices, { label = shorten(self:getPlacePath(place), 34), value = place.id })
    end
    table.insert(choices, { label = _("— unknown —"), value = "" })
    self:_showChoice(T(_("Where is '%1'?"), entry.name or "?"), choices, function(value)
        if value == "" then
            entry.location_place = nil
            entry.location_text = ""
        elseif self:getPlaceById(value) then
            entry.location_place = value
            entry.location_text = ""
        else
            entry.location_place = nil
            entry.location_text = value
        end
        self:saveCompendium()
        if on_done then on_done() end
    end, { hint = _("e.g. buried beneath the old oak, carried by the thief") })
end

function CharacterTracker:showCompendiumFactsManager(entry)
    if type(entry.facts) ~= "table" then entry.facts = {} end
    local function back() self:showCompendiumFactsManager(entry) end
    local buttons = {}
    for i, fact in ipairs(entry.facts) do
        table.insert(buttons, {
            {
                text = shorten((fact.label or "?") .. ": " .. (fact.value or ""), 42),
                callback = function()
                    UIManager:close(self._comp_facts_dialog)
                    self._comp_facts_dialog = nil
                    self:_showListEntryActions((fact.label or "?") .. ": " .. (fact.value or ""), entry.facts, i, {
                        on_edit = function(index) self:showCompendiumFactDialog(entry, index) end,
                        on_change = function() self:saveCompendium() end,
                        back = back,
                    })
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._comp_facts_dialog)
                    self._comp_facts_dialog = nil
                    table.remove(entry.facts, i)
                    self:saveCompendium()
                    back()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add fact"),
            callback = function()
                UIManager:close(self._comp_facts_dialog)
                self._comp_facts_dialog = nil
                local choices = {}
                for _i, preset in ipairs(COMPENDIUM_FACT_PRESETS) do
                    table.insert(choices, { label = preset, value = preset })
                end
                self:_showChoice(T(_("Add a fact to '%1'"), entry.name or "?"), choices, function(label)
                    self:showCompendiumFactDialog(entry, nil, label)
                end, { hint = _("What is this fact about?") })
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._comp_facts_dialog)
                self._comp_facts_dialog = nil
                self:showCompendiumDetail(entry)
            end,
        },
    })
    self._comp_facts_dialog = ButtonDialog:new{
        title = T(_("Facts — %1"), entry.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._comp_facts_dialog)
end

function CharacterTracker:showCompendiumFactDialog(entry, index, preset)
    local fact = index and entry.facts[index] or nil
    local dialog
    dialog = MultiInputDialog:new{
        title = fact and _("Edit fact") or _("Add fact"),
        fields = {
            { text = fact and fact.label or preset or "", hint = _("Label — e.g. Material") },
            { text = fact and fact.value or "", hint = _("Value — e.g. Valyrian steel") },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showCompendiumFactsManager(entry)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local label, value = trim(fields[1]), trim(fields[2])
                        UIManager:close(dialog)
                        if label ~= "" then
                            if fact then
                                fact.label, fact.value = label, value
                            else
                                table.insert(entry.facts, { label = label, value = value })
                            end
                            self:saveCompendium()
                        end
                        self:showCompendiumFactsManager(entry)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCompendiumConnectionsManager(entry)
    if type(entry.connections) ~= "table" then entry.connections = {} end
    local function back() self:showCompendiumConnectionsManager(entry) end
    local function describe(c)
        local other = self:getCompendiumEntryById(c.to)
        return getCompendiumConnectionLabel(c.kind, false) .. " " .. (other and other.name or "?")
    end
    local function pickKind(on_pick)
        local choices = {}
        for _i, k in ipairs(COMPENDIUM_CONNECTION_KINDS) do
            table.insert(choices, { label = k.label, value = k.key })
        end
        self:_showChoice(T(_("How is '%1' connected?"), entry.name or "?"), choices, on_pick,
            { hint = _("A custom kind, e.g. guards — or \"Guards / Guarded by\" for both directions") })
    end
    local buttons = {}
    for i, c in ipairs(entry.connections) do
        local extras = (c.notes and #c.notes or 0) + (c.secrets and #c.secrets or 0)
        table.insert(buttons, {
            {
                text = shorten(describe(c), 40) .. (extras > 0 and (" ✎" .. extras) or ""),
                callback = function()
                    UIManager:close(self._comp_conn_dialog)
                    self._comp_conn_dialog = nil
                    self:_showListEntryActions(describe(c), entry.connections, i, {
                        extra = function(close_and)
                            return {
                                {
                                    { text = _("Change kind"), callback = close_and(function()
                                        pickKind(function(kind)
                                            c.kind = kind
                                            self:saveCompendium()
                                            back()
                                        end)
                                    end) },
                                    { text = _("Notes & secrets"), callback = close_and(function()
                                        self:showEntryNotesSecrets(entry, c, describe(c), back, function() self:saveCompendium() end)
                                    end) },
                                },
                                {
                                    { text = _("Open entry"), callback = close_and(function()
                                        local other = self:getCompendiumEntryById(c.to)
                                        if other then self:showCompendiumDetail(other) else back() end
                                    end) },
                                },
                            }
                        end,
                        on_change = function() self:saveCompendium() end,
                        back = back,
                    })
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._comp_conn_dialog)
                    self._comp_conn_dialog = nil
                    table.remove(entry.connections, i)
                    self:saveCompendium()
                    back()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add connection"),
            callback = function()
                UIManager:close(self._comp_conn_dialog)
                self._comp_conn_dialog = nil
                local choices = {}
                for _i, other in ipairs(self.compendium) do
                    if other.id ~= entry.id then
                        table.insert(choices, { label = shorten(other.name or "?", 34), value = other.id })
                    end
                end
                if #choices == 0 then
                    UIManager:show(InfoMessage:new{ text = _("Add another compendium entry first.") })
                    back()
                    return
                end
                self:_showChoice(T(_("Connect '%1' to…"), entry.name or "?"), choices, function(other_id)
                    pickKind(function(kind)
                        table.insert(entry.connections, { to = other_id, kind = kind, notes = {}, secrets = {} })
                        self:saveCompendium()
                        back()
                    end)
                end)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._comp_conn_dialog)
                self._comp_conn_dialog = nil
                self:showCompendiumDetail(entry)
            end,
        },
    })
    self._comp_conn_dialog = ButtonDialog:new{
        title = T(_("Connections — %1"), entry.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._comp_conn_dialog)
end

function CharacterTracker:showAddCompendiumDialog(preselected_name)
    local dialog
    dialog = InputDialog:new{
        input = preselected_name or "",
        title = _("Add compendium entry"),
        input_hint = _("Name (e.g. The Sunsword, The Weave)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name == "" then return end
                        local entry = {
                            id = genId(),
                            name = name,
                            type = "",
                            description = "",
                            age = "",
                            ability = "",
                            ownership = {},
                            aliases = {},
                            hide_from_belongings = false,
                            status = "",
                            location_text = "",
                            facts = {},
                            properties = {},
                            limitations = {},
                            connections = {},
                            history = {},
                            secrets = {},
                            notes = {},
                            section_order = {},
                            created = os.date("%Y-%m-%d %H:%M"),
                        }
                        table.insert(self.compendium, entry)
                        self:saveCompendium()
                        self:rebuildMarksForObject(entry)
                        self:showCompendiumTypePicker(entry, function()
                            self:showCompendiumDetail(entry)
                        end)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCompendiumTypePicker(entry, on_done)
    local buttons = {}
    local row = {}
    for _i, ct in ipairs(COMPENDIUM_TYPES) do
        if ct.key ~= "custom" then
            table.insert(row, {
                text = ct.label,
                callback = function()
                    UIManager:close(self._compendium_type_dialog)
                    self._compendium_type_dialog = nil
                    entry.type = ct.key
                    self:saveCompendium()
                    if on_done then on_done() end
                end,
            })
            if #row >= 3 then
                table.insert(buttons, row)
                row = {}
            end
        end
    end
    if #row > 0 then table.insert(buttons, row) end

    table.insert(buttons, {
        {
            text = _("Custom…"),
            callback = function()
                UIManager:close(self._compendium_type_dialog)
                self._compendium_type_dialog = nil
                local dialog
                dialog = InputDialog:new{
                    title = _("Custom compendium type"),
                    input = (entry.type ~= "" and getCompendiumTypeLabel(entry.type)) or "",
                    input_hint = _("e.g. relic, prophecy, ritual"),
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                        { text = _("Save"), is_enter_default = true, callback = function()
                            local t = dialog:getInputText():match("^%s*(.-)%s*$")
                            UIManager:close(dialog)
                            if t ~= "" then
                                entry.type = t
                                self:saveCompendium()
                            end
                            if on_done then on_done() end
                        end },
                    }},
                }
                self:_showInputDialog(dialog)
            end,
        },
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._compendium_type_dialog)
                self._compendium_type_dialog = nil
            end,
        },
    })

    self._compendium_type_dialog = ButtonDialog:new{
        title = T(_("Type of '%1'"), entry.name),
        buttons = buttons,
    }
    UIManager:show(self._compendium_type_dialog)
end

function CharacterTracker:showRenameCompendiumDialog(entry, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Rename '%1'"), entry.name),
        input = entry.name or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name ~= "" and name ~= entry.name then
                            local old_name = entry.name
                            entry.name = name
                            self:saveCompendium()
                            self:removeMarksForObjectName(old_name)
                            self:_renameInTimelines("objects", old_name, name)
                            self:rebuildMarksForObject(entry)
                        end
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCompendiumDescriptionDialog(entry, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Description — %1"), entry.name),
        input = entry.description or "",
        input_hint = _("What is it? What does it do?"),
        text_height = math.floor(Device.screen:getHeight() * 0.35),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        entry.description = text
                        self:saveCompendium()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCompendiumAgeDialog(entry, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Age — %1"), entry.name),
        input = entry.age or "",
        input_hint = _("e.g. 300 years old, ancient, newly forged"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        entry.age = ""
                        self:saveCompendium()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        entry.age = text
                        self:saveCompendium()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCompendiumAbilityDialog(entry, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Ability / what it does — %1"), entry.name),
        input = entry.ability or "",
        input_hint = _("e.g. grants invisibility, cuts through any armor"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        entry.ability = ""
                        self:saveCompendium()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        entry.ability = text
                        self:saveCompendium()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCompendiumOwnershipManager(entry)
    if not entry.ownership then entry.ownership = {} end
    local buttons = {}
    for i, rec in ipairs(entry.ownership) do
        local label = (rec.owner or "?") .. (rec.current and ("  (" .. _("current") .. ")") or "")
        if rec.acquired and rec.acquired ~= "" then
            label = label .. " — " .. rec.acquired
        end
        label = shorten(label, 46)
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._ownership_dialog)
                    self._ownership_dialog = nil
                    self:showOwnershipRecordActions(entry, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._ownership_dialog)
                    self._ownership_dialog = nil
                    table.remove(entry.ownership, i)
                    self:saveCompendium()
                    self:showCompendiumOwnershipManager(entry)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add ownership record"),
            callback = function()
                UIManager:close(self._ownership_dialog)
                self._ownership_dialog = nil
                self:showAddOwnershipPicker(entry)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._ownership_dialog)
                self._ownership_dialog = nil
                self:showCompendiumDetail(entry)
            end,
        },
    })
    self._ownership_dialog = ButtonDialog:new{
        title = T(_("Ownership — %1\n(tap a record for more options)"), entry.name),
        buttons = buttons,
    }
    UIManager:show(self._ownership_dialog)
end

function CharacterTracker:showOwnershipRecordActions(entry, index)
    local rec = entry.ownership[index]
    if not rec then return end
    local function close_and(fn)
        return function()
            UIManager:close(self._ownership_act_dialog)
            self._ownership_act_dialog = nil
            fn()
        end
    end
    local buttons = {
        {
            { text = "▲ " .. _("Move up"), callback = close_and(function()
                if index > 1 then
                    entry.ownership[index], entry.ownership[index - 1] =
                        entry.ownership[index - 1], entry.ownership[index]
                    self:saveCompendium()
                end
                self:showCompendiumOwnershipManager(entry)
            end) },
            { text = "▼ " .. _("Move down"), callback = close_and(function()
                if index < #entry.ownership then
                    entry.ownership[index], entry.ownership[index + 1] =
                        entry.ownership[index + 1], entry.ownership[index]
                    self:saveCompendium()
                end
                self:showCompendiumOwnershipManager(entry)
            end) },
        },
        {
            { text = rec.current and _("Mark as past owner") or _("Mark as current owner"), callback = close_and(function()
                rec.current = not rec.current
                self:saveCompendium()
                self:showCompendiumOwnershipManager(entry)
            end) },
        },
        {
            { text = _("Edit how acquired"), callback = close_and(function()
                self:showOwnershipFieldDialog(entry, index, "acquired")
            end) },
            { text = _("Edit how lost"), callback = close_and(function()
                self:showOwnershipFieldDialog(entry, index, "lost")
            end) },
        },
        {
            { text = _("Open character"), callback = close_and(function()
                local char = self:getCharacterByName(rec.owner)
                if char then
                    self:showCharacterDetail(char)
                else
                    UIManager:show(InfoMessage:new{
                        text = T(_("'%1' isn't a tracked character."), rec.owner or "?"),
                    })
                    self:showCompendiumOwnershipManager(entry)
                end
            end) },
        },
        {
            { text = _("Delete"), callback = close_and(function()
                table.remove(entry.ownership, index)
                self:saveCompendium()
                self:showCompendiumOwnershipManager(entry)
            end) },
            { text = _("Cancel"), id = "close", callback = close_and(function()
                self:showCompendiumOwnershipManager(entry)
            end) },
        },
    }
    self._ownership_act_dialog = ButtonDialog:new{
        title = T(_("%1 — %2"), entry.name, rec.owner or "?"),
        buttons = buttons,
    }
    UIManager:show(self._ownership_act_dialog)
end

function CharacterTracker:showOwnershipFieldDialog(entry, index, field)
    local rec = entry.ownership[index]
    if not rec then return end
    local dialog
    dialog = InputDialog:new{
        title = field == "acquired" and T(_("How '%1' got '%2'"), rec.owner or "?", entry.name)
            or T(_("How '%1' lost '%2'"), rec.owner or "?", entry.name),
        input = rec[field] or "",
        input_hint = field == "acquired"
            and _("e.g. inherited from their father, stole it during the raid, found it")
            or _("e.g. traded it away, it was stolen, gave it up willingly"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showCompendiumOwnershipManager(entry)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        rec[field] = ""
                        self:saveCompendium()
                        self:showCompendiumOwnershipManager(entry)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        rec[field] = text
                        self:saveCompendium()
                        self:showCompendiumOwnershipManager(entry)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showAddOwnershipPicker(entry)
    local buttons = {}
    local row = {}
    for _i, char in ipairs(self.characters) do
        table.insert(row, {
            text = char.name,
            callback = function()
                UIManager:close(self._add_owner_dialog)
                self._add_owner_dialog = nil
                self:showOwnershipAcquiredDialog(entry, char.name)
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Other / custom name…"),
            callback = function()
                UIManager:close(self._add_owner_dialog)
                self._add_owner_dialog = nil
                local dialog
                dialog = InputDialog:new{
                    title = _("Owner name"),
                    input_hint = _("e.g. the crown, unknown, a nameless thief"),
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                        { text = _("Next"), is_enter_default = true, callback = function()
                            local name = dialog:getInputText():match("^%s*(.-)%s*$")
                            UIManager:close(dialog)
                            if name == "" then return end
                            self:showOwnershipAcquiredDialog(entry, name)
                        end },
                    }},
                }
                self:_showInputDialog(dialog)
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._add_owner_dialog)
                self._add_owner_dialog = nil
            end,
        },
    })
    self._add_owner_dialog = ButtonDialog:new{
        title = T(_("Who owns/took '%1'?"), entry.name),
        buttons = buttons,
    }
    UIManager:show(self._add_owner_dialog)
end

function CharacterTracker:showOwnershipAcquiredDialog(entry, owner_name)
    local dialog
    dialog = InputDialog:new{
        title = T(_("How did '%1' get '%2'? (optional)"), owner_name, entry.name),
        input_hint = _("e.g. inherited from their father, stole it during the raid, found it"),
        buttons = {
            {
                {
                    text = _("Skip"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showOwnershipCurrentPicker(entry, owner_name, "")
                    end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local acquired = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        self:showOwnershipCurrentPicker(entry, owner_name, acquired)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showOwnershipCurrentPicker(entry, owner_name, acquired)
    self._ownership_current_dialog = ButtonDialog:new{
        title = T(_("Is '%1' a current owner of '%2'?"), owner_name, entry.name),
        buttons = {
            {
                { text = _("Yes - current owner"), callback = function()
                    UIManager:close(self._ownership_current_dialog)
                    self._ownership_current_dialog = nil
                    table.insert(entry.ownership, { owner = owner_name, acquired = acquired, lost = "", current = true })
                    self:saveCompendium()
                    self:showCompendiumOwnershipManager(entry)
                end },
            },
            {
                { text = _("No - past owner only"), callback = function()
                    UIManager:close(self._ownership_current_dialog)
                    self._ownership_current_dialog = nil
                    self:showOwnershipLostDialog(entry, owner_name, acquired)
                end },
            },
        },
    }
    UIManager:show(self._ownership_current_dialog)
end

function CharacterTracker:showOwnershipLostDialog(entry, owner_name, acquired)
    local dialog
    dialog = InputDialog:new{
        title = T(_("How did '%1' lose '%2'? (optional)"), owner_name, entry.name),
        input_hint = _("e.g. traded it away, it was stolen, gave it up willingly"),
        buttons = {
            {
                {
                    text = _("Skip"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        table.insert(entry.ownership, { owner = owner_name, acquired = acquired, lost = "", current = false })
                        self:saveCompendium()
                        self:showCompendiumOwnershipManager(entry)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local lost = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        table.insert(entry.ownership, { owner = owner_name, acquired = acquired, lost = lost, current = false })
                        self:saveCompendium()
                        self:showCompendiumOwnershipManager(entry)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:deleteCompendiumEntry(entry)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete compendium entry '%1'?"), entry.name),
        ok_text = _("Delete"),
        ok_callback = function()
            for i = #self.compendium, 1, -1 do
                if self.compendium[i].id == entry.id then
                    table.remove(self.compendium, i)
                    break
                end
            end
            for _i, other in ipairs(self.compendium) do
                for j = #(other.connections or {}), 1, -1 do
                    if other.connections[j].to == entry.id then
                        table.remove(other.connections, j)
                    end
                end
            end
            self:saveCompendium()
            self:removeMarksForObjectName(entry.name)
            UIManager:show(InfoMessage:new{
                text = T(_("Deleted '%1'."), entry.name),
                timeout = 2,
            })
        end,
    })
end

function CharacterTracker:getTimelineFilePath()
    if self.timeline_file then return self.timeline_file end
    local series = self:getSeriesName()
    if series and series ~= "" then
        local safe_name = self:_seriesFileBase(series)
        self.timeline_file = self:getSeriesDir() .. "/" .. safe_name .. ".timeline.json"
    else
        local doc_path = self.ui.document.file
        self.timeline_file = doc_path .. ".timeline.json"
    end
    return self.timeline_file
end

function CharacterTracker:loadTimelines()
    self.timelines = {}
    self.timeline_file = nil
    local path = self:getTimelineFilePath()
    local f = io.open(path, "r")
    if f then
        local content = f:read("*all")
        f:close()
        if content and content ~= "" then
            local ok, data = pcall(json.decode, content)
            if ok and type(data) == "table" then
                self.timelines = data
            else
                logger.warn("CharacterTracker: failed to parse", path)
            end
        end
    end
    for _i, tl in ipairs(self.timelines) do
        if not tl.id then tl.id = genId() end
        if tl.name == nil then tl.name = "" end
        if tl.description == nil then tl.description = "" end
        if tl.sort ~= "page" then tl.sort = "manual" end
        if type(tl.events) ~= "table" then tl.events = {} end
        for _j, event in ipairs(tl.events) do
            if not event.id then event.id = genId() end
            if event.title == nil then event.title = "" end
            if event.page == nil then event.page = "" end
            if event.when == nil then event.when = "" end
            if type(event.characters) ~= "table" then event.characters = {} end
            if type(event.places) ~= "table" then event.places = {} end
            if type(event.objects) ~= "table" then event.objects = {} end
            if event.text == nil then event.text = "" end
            if type(event.excerpts) ~= "table" then event.excerpts = {} end
            if type(event.notes) ~= "table" then event.notes = {} end
            for _k, excerpt in ipairs(event.excerpts) do
                if excerpt.page == nil then excerpt.page = "" end
                if type(excerpt.notes) ~= "table" then excerpt.notes = {} end
            end
        end
    end
end

function CharacterTracker:saveTimeline()
    self._timeline_dirty = true
    self:_scheduleFlush()
end

function CharacterTracker:_saveFor(owner)
    if owner and owner.save_fn then
        owner.save_fn()
    else
        self:saveData()
    end
end

function CharacterTracker:_timelineSaver()
    return { save_fn = function() self:saveTimeline() end }
end

function CharacterTracker:_currentPageText()
    local ok, page = pcall(function() return self:getCurrentPage() end)
    if ok and page then return tostring(page) end
    return ""
end

function CharacterTracker:_selectionPage(selected)
    local page
    pcall(function()
        if self.ui.paging and selected and selected.pos0 and selected.pos0.page then
            page = selected.pos0.page
        elseif self.ui.rolling and selected and selected.pos0 and self.ui.document.getPageFromXPointer then
            page = self.ui.document:getPageFromXPointer(selected.pos0)
        end
    end)
    if page then return tostring(page) end
    return self:_currentPageText()
end

local function timelinePageNumber(page)
    return tonumber((page or ""):match("%d+"))
end

function CharacterTracker:_timelineEventLines(field, name)
    local lines = {}
    local key = (name or ""):lower()
    for _i, tl in ipairs(self.timelines or {}) do
        for _j, event in ipairs(tl.events or {}) do
            for _k, linked in ipairs(event[field] or {}) do
                if linked:lower() == key then
                    local line = event.title ~= "" and event.title or _("(untitled event)")
                    if event.page ~= "" then line = line .. " (" .. T(_("p. %1"), event.page) .. ")" end
                    if tl.name ~= "" then line = line .. " — " .. tl.name end
                    table.insert(lines, line)
                    break
                end
            end
        end
    end
    return lines
end

function CharacterTracker:_renameInTimelines(field, old_name, new_name)
    local touched = false
    local old = (old_name or ""):lower()
    for _i, tl in ipairs(self.timelines or {}) do
        for _j, event in ipairs(tl.events or {}) do
            for k, linked in ipairs(event[field] or {}) do
                if linked:lower() == old then
                    event[field][k] = new_name
                    touched = true
                end
            end
        end
    end
    if touched then self:saveTimeline() end
end

function CharacterTracker:getTimelineById(id)
    for _i, tl in ipairs(self.timelines or {}) do
        if tl.id == id then return tl end
    end
    return nil
end

function CharacterTracker:_timelineOrderedEvents(tl)
    local list = {}
    for i, event in ipairs(tl.events) do
        list[#list + 1] = { event = event, index = i }
    end
    if tl.sort == "page" then
        local slots, paged = {}, {}
        for i, item in ipairs(list) do
            if timelinePageNumber(item.event.page) then
                slots[#slots + 1] = i
                paged[#paged + 1] = item
            end
        end
        table.sort(paged, function(a, b)
            local pa, pb = timelinePageNumber(a.event.page), timelinePageNumber(b.event.page)
            if pa ~= pb then return pa < pb end
            return a.index < b.index
        end)
        local result = {}
        for i, item in ipairs(list) do result[i] = item end
        for k, slot in ipairs(slots) do result[slot] = paged[k] end
        list = result
    end
    if tl.reverse then
        local flipped = {}
        for i = #list, 1, -1 do flipped[#flipped + 1] = list[i] end
        list = flipped
    end
    return list
end

function CharacterTracker:buildTimelineEventBlock(event, number)
    local lines = {}
    local heading = event.title ~= "" and event.title or _("(untitled event)")
    if number then heading = number .. " · " .. heading end
    table.insert(lines, "\n── " .. heading .. " ──\n")
    local meta = {}
    if event.page ~= "" then table.insert(meta, T(_("Page %1"), event.page)) end
    if event.when ~= "" then table.insert(meta, event.when) end
    if event.earlier then table.insert(meta, _("earlier event")) end
    if #meta > 0 then table.insert(lines, table.concat(meta, " · ") .. "\n") end
    if event.characters and #event.characters > 0 then
        table.insert(lines, _("Characters") .. ": " .. table.concat(event.characters, ", ") .. "\n")
    end
    if event.places and #event.places > 0 then
        table.insert(lines, _("Places") .. ": " .. table.concat(event.places, ", ") .. "\n")
    end
    if event.objects and #event.objects > 0 then
        table.insert(lines, _("Compendium") .. ": " .. table.concat(event.objects, ", ") .. "\n")
    end
    if event.text ~= "" then table.insert(lines, event.text .. "\n") end
    for _i, excerpt in ipairs(event.excerpts) do
        local line = "“" .. getNoteText(excerpt.text) .. "”"
        if excerpt.page ~= "" then line = line .. " (" .. T(_("p. %1"), excerpt.page) .. ")" end
        table.insert(lines, "\n" .. line .. "\n")
        for _j, note in ipairs(excerpt.notes) do
            table.insert(lines, "  • " .. note .. "\n")
        end
    end
    if #event.notes > 0 then
        table.insert(lines, "\n" .. _("Notes") .. "\n")
        table.insert(lines, pageBullets(event.notes, "• "))
    end
    return table.concat(lines)
end

function CharacterTracker:showTimelineList()
    local item_table = {}
    local menu_container
    table.insert(item_table, {
        text = _("+ New timeline"),
        callback = function()
            self:showAddTimelineDialog()
        end,
    })
    for _i, tl in ipairs(self.timelines) do
        table.insert(item_table, {
            text = (tl.name ~= "" and tl.name or _("(unnamed)")) .. T(_("  ·  %1 event(s)"), #tl.events),
            callback = function()
                UIManager:close(menu_container)
                self:showTimelineView(tl)
            end,
        })
    end

    local menu
    menu = Menu:new{
        title = T(_("Timelines (%1)"), #self.timelines),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = function()
            UIManager:close(menu_container)
        end,
    }
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

function CharacterTracker:showAddTimelineDialog(on_done)
    local dialog
    dialog = InputDialog:new{
        title = _("New timeline"),
        input_hint = _("Name (e.g. Main plot, Backstory, The war)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local name = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if name == "" then return end
                        local tl = {
                            id = genId(),
                            name = name,
                            description = "",
                            sort = "manual",
                            events = {},
                            created = os.date("%Y-%m-%d %H:%M"),
                        }
                        table.insert(self.timelines, tl)
                        self:saveTimeline()
                        if on_done then on_done(tl) else self:showTimelineView(tl) end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

local function timelineMarginMode(tl)
    if tl.margin == "date" or tl.margin == "both" then return tl.margin end
    return "page"
end

local function tlpx(value)
    local factor = math.min(2, math.max(0.5, Screen:getWidth() / 1236))
    return math.max(1, math.floor(value * factor + 0.5))
end

local function timelineGeometry(canvas_w)
    local gutter_w = tlpx(100)
    local spine_x = gutter_w + tlpx(32)
    local card_x = spine_x + tlpx(24)
    return {
        gutter_w = gutter_w,
        spine_x = spine_x,
        card_x = card_x,
        card_w = canvas_w - card_x - tlpx(18),
        label_x = tlpx(14),
    }
end

local function timelineEntryParts(event, card_w, gray, hide_when)
    local parts = {}
    local y = 0
    local function add(widget, gap, kind)
        parts[#parts + 1] = { w = widget, y = y, kind = kind }
        y = y + widget:getSize().h + (gap or tlpx(4))
    end
    local title = event.title ~= "" and event.title or _("(untitled event)")
    add(TextBoxWidget:new{ text = title, face = Font:getFace("tfont", tlpx(21)), width = card_w }, tlpx(3))
    local meta = {}
    if event.when ~= "" and not hide_when then meta[#meta + 1] = event.when end
    if event.earlier then meta[#meta + 1] = _("earlier event") end
    if #meta > 0 then
        add(TextBoxWidget:new{
            text = table.concat(meta, " · "), face = Font:getFace("cfont", tlpx(15)), width = card_w, fgcolor = gray,
        }, tlpx(5))
    end
    local linked = {}
    for _i, field in ipairs({ "characters", "places", "objects" }) do
        if event[field] and #event[field] > 0 then
            table.insert(linked, table.concat(event[field], ", "))
        end
    end
    if #linked > 0 then
        add(TextBoxWidget:new{
            text = shorten(table.concat(linked, "  ·  "), 110), face = Font:getFace("cfont", tlpx(15)),
            width = card_w, fgcolor = gray,
        }, tlpx(5))
    end
    if event.text ~= "" then
        add(TextBoxWidget:new{
            text = shorten(event.text, 220), face = Font:getFace("cfont", tlpx(17)), width = card_w,
        }, tlpx(7))
    end
    if #event.excerpts > 0 then
        local excerpt = event.excerpts[1]
        local line = "“" .. shorten(getNoteText(excerpt.text), 110) .. "”"
        if excerpt.page ~= "" then line = line .. "  p." .. excerpt.page end
        if #event.excerpts > 1 then line = line .. "  +" .. (#event.excerpts - 1) end
        add(TextBoxWidget:new{
            text = line, face = Font:getFace("cfont", tlpx(15)), width = card_w - tlpx(14), fgcolor = gray,
        }, tlpx(5), "excerpt")
    end
    local note_total = #event.notes
    for _i, excerpt in ipairs(event.excerpts) do note_total = note_total + #excerpt.notes end
    if note_total > 0 then
        add(TextBoxWidget:new{
            text = "✎ " .. note_total, face = Font:getFace("cfont", tlpx(14)), width = card_w, fgcolor = gray,
        }, tlpx(2))
    end
    return parts, y
end

local function freeTimelineParts(parts)
    for _i, part in ipairs(parts) do part.w:free() end
end

local function layoutTimelinePages(ordered, card_w, avail_h, gray, hide_when)
    local pages = {}
    local current = { items = {}, used = 0 }
    for _i, item in ipairs(ordered) do
        local parts, content_h = timelineEntryParts(item.event, card_w, gray, hide_when)
        freeTimelineParts(parts)
        local height = content_h + tlpx(28)
        if current.used + height > avail_h and #current.items > 0 then
            pages[#pages + 1] = current
            current = { items = {}, used = 0 }
        end
        current.items[#current.items + 1] = { event = item.event, y = current.used, h = height }
        current.used = current.used + height
    end
    if #current.items > 0 or #pages == 0 then pages[#pages + 1] = current end
    return pages
end

local function timelineHeaderWidgets(tl, canvas_w, order_label, gray)
    local title = TextBoxWidget:new{
        text = tl.name ~= "" and tl.name or _("Timeline"),
        face = Font:getFace("tfont", tlpx(24)),
        width = canvas_w - tlpx(120),
    }
    local sub = TextBoxWidget:new{
        text = T(_("%1 event(s) · %2"), #tl.events, order_label),
        face = Font:getFace("cfont", tlpx(16)),
        fgcolor = gray,
        width = canvas_w - tlpx(36),
    }
    return title, sub
end

local function timelineHeaderHeight(tl, canvas_w, order_label, gray)
    local title, sub = timelineHeaderWidgets(tl, canvas_w, order_label, gray)
    local height = tlpx(28) + title:getSize().h + tlpx(2) + sub:getSize().h + tlpx(16)
    title:free()
    sub:free()
    return height
end

local function renderTimelinePage(tl, pages, page_index, canvas_w, canvas_h, header_h, gray, order_label)
    local bb_type = Screen.bb and Screen.bb:getType() or Blitbuffer.TYPE_BB8
    local bb = Blitbuffer.new(canvas_w, canvas_h, bb_type)
    bb:fill(Blitbuffer.COLOR_WHITE)
    local black = Blitbuffer.COLOR_BLACK
    local geo = timelineGeometry(canvas_w)
    local spine_x, card_x, card_w = geo.spine_x, geo.card_x, geo.card_w

    local function rect(x, y, w, h, color)
        bb:paintRect(math.floor(x), math.floor(y), math.max(1, math.floor(w)), math.max(1, math.floor(h)), color or black)
    end
    local function disc(cx, cy, r, color)
        for dy = -r, r do
            local dx = math.floor(math.sqrt(r * r - dy * dy))
            rect(cx - dx, cy + dy, 2 * dx + 1, 1, color)
        end
    end

    local title, sub = timelineHeaderWidgets(tl, canvas_w, order_label, gray)
    local title_h = title:getSize().h
    title:paintTo(bb, tlpx(18), tlpx(28))
    title:free()
    sub:paintTo(bb, tlpx(18), tlpx(28) + title_h + tlpx(2))
    sub:free()
    local counter = TextWidget:new{
        text = page_index .. " / " .. #pages,
        face = Font:getFace("cfont", tlpx(17)),
        fgcolor = gray,
    }
    counter:paintTo(bb, canvas_w - counter:getSize().w - tlpx(18), tlpx(32))
    counter:free()
    rect(0, header_h - tlpx(6), canvas_w, tlpx(2), gray)

    local page = pages[page_index]
    local top = header_h
    local bar_w = tlpx(3)
    rect(spine_x - math.floor(bar_w / 2), top, bar_w, canvas_h - top, gray)

    local hits = {}
    if page then
        for _i, item in ipairs(page.items) do
            local event = item.event
            local y0 = top + item.y + tlpx(8)
            local parts = timelineEntryParts(event, card_w, gray, timelineMarginMode(tl) ~= "page")
            for _j, part in ipairs(parts) do
                if part.kind == "excerpt" then
                    rect(card_x - 1, y0 + part.y, bar_w, part.w:getSize().h, gray)
                    part.w:paintTo(bb, card_x + tlpx(12), y0 + part.y)
                else
                    part.w:paintTo(bb, card_x, y0 + part.y)
                end
            end
            freeTimelineParts(parts)
            local dot_y = y0 + tlpx(14)
            disc(spine_x, dot_y, tlpx(11), black)
            if event.earlier then disc(spine_x, dot_y, tlpx(7), Blitbuffer.COLOR_WHITE) end
            local mode = timelineMarginMode(tl)
            local label_parts = {}
            if mode ~= "page" and event.when ~= "" then
                label_parts[#label_parts + 1] = shorten(event.when, 40)
            end
            if mode ~= "date" and event.page ~= "" then
                label_parts[#label_parts + 1] = "p. " .. event.page
            end
            if #label_parts == 0 and event.earlier then
                label_parts[1] = _("earlier")
            end
            local label = table.concat(label_parts, "\n")
            if label ~= "" then
                local tw = TextBoxWidget:new{
                    text = label, face = Font:getFace("cfont", tlpx(16)), fgcolor = gray,
                    width = geo.gutter_w - tlpx(6), alignment = "right",
                }
                tw:paintTo(bb, geo.label_x, dot_y - tw:getSize().h / 2)
                tw:free()
            end
            hits[#hits + 1] = { y1 = top + item.y, y2 = top + item.y + item.h, event = event }
        end
    end
    return bb, hits
end

local TimelineCanvas = InputContainer:extend{
    width = 0,
    height = 0,
}

function TimelineCanvas:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = {
        TimelineTap = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
        TimelineSwipe = {
            GestureRange:new{ ges = "swipe", range = function() return self.dimen end },
        },
    }
end

function TimelineCanvas:getSize()
    return self.dimen
end

function TimelineCanvas:freeBuffer()
    if self.bb then
        self.bb:free()
        self.bb = nil
    end
end

function TimelineCanvas:setBuffer(bb, hits)
    self:freeBuffer()
    self.bb = bb
    self.hits = hits or {}
end

function TimelineCanvas:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self.bb then
        bb:blitFrom(self.bb, x, y, 0, 0, self.dimen.w, self.dimen.h)
    end
end

function TimelineCanvas:onTimelineTap(_arg, ges)
    if self.passthrough and self.passthrough() then return false end
    local ly = ges.pos.y - self.dimen.y
    for _i, hit in ipairs(self.hits or {}) do
        if ly >= hit.y1 and ly <= hit.y2 then
            if self.on_entry then self.on_entry(hit.event) end
            return true
        end
    end
    return true
end

function TimelineCanvas:onTimelineSwipe(_arg, ges)
    if self.passthrough and self.passthrough() then return false end
    local dir = ges.direction or ""
    if dir == "west" then
        if self.on_page then self.on_page(1) end
        return true
    elseif dir == "east" then
        if self.on_page then self.on_page(-1) end
        return true
    end
    return false
end

local TimelineView = InputContainer:extend{
    covers_fullscreen = true,
    tracker = nil,
    timeline = nil,
}

function TimelineView:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.gray = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            NextPage = { { Device.input.group.PgFwd } },
            PrevPage = { { Device.input.group.PgBack } },
        }
    end
    local tl = self.timeline
    self.gesture_mode = false
    local button_row = {
        { text = "◀", callback = function() self:turn(-1) end },
        { text = "▶", callback = function() self:turn(1) end },
        { text = _("＋ Event"), callback = function()
            self.tracker:showTimelineEventDialog(tl, nil, function(event)
                self.tracker:showTimelineEventDetail(tl, event)
            end)
        end },
    }
    if not self.tracker:isTimelineShotHidden() then
        table.insert(button_row, { text = _("Shot"), callback = function() self:showShotMenu() end })
    end
    table.insert(button_row, { text = _("More"), callback = function() self.tracker:showTimelineMoreMenu(tl, self) end })
    table.insert(button_row, { text = _("Close"), callback = function() self:onClose() end })
    self.button_table = ButtonTable:new{
        width = sw - 20,
        show_parent = self,
        buttons = { button_row },
    }
    local canvas_h = sh - self.button_table:getSize().h - 4
    self.canvas = TimelineCanvas:new{
        width = sw,
        height = canvas_h,
        show_parent = self,
        on_entry = function(event)
            self.tracker._timeline_last = self.tracker._timeline_last or {}
            self.tracker._timeline_last[tl.id] = event.id
            self.tracker:showTimelineEventDetail(tl, event)
        end,
        on_page = function(delta) self:turn(delta) end,
        passthrough = function() return self.gesture_mode end,
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        VerticalGroup:new{
            align = "center",
            self.canvas,
            self.button_table,
        },
    }
    self.page_index = 1
    self:rebuild(true)
end

function TimelineView:rebuild(restore)
    local tl = self.timeline
    local order_label = (tl.sort == "page" and _("by page") or _("manual order"))
        .. " · " .. (tl.reverse and _("newest first") or _("oldest first"))
    local header_h = timelineHeaderHeight(tl, self.canvas.dimen.w, order_label, self.gray)
    local ordered = self.tracker:_timelineOrderedEvents(tl)
    local card_w = timelineGeometry(self.canvas.dimen.w).card_w
    self.pages = layoutTimelinePages(ordered, card_w, self.canvas.dimen.h - header_h, self.gray, timelineMarginMode(tl) ~= "page")
    if restore then
        local last = self.tracker._timeline_last and self.tracker._timeline_last[tl.id]
        if last then
            for p, page in ipairs(self.pages) do
                for _i, item in ipairs(page.items) do
                    if item.event.id == last then self.page_index = p end
                end
            end
        end
    end
    if self.page_index > #self.pages then self.page_index = #self.pages end
    if self.page_index < 1 then self.page_index = 1 end
    local bb, hits = renderTimelinePage(tl, self.pages, self.page_index,
        self.canvas.dimen.w, self.canvas.dimen.h, header_h, self.gray, order_label)
    self.header_h = header_h
    self.order_label = order_label
    self.canvas:setBuffer(bb, hits)
    UIManager:setDirty(self, "ui")
end

function TimelineView:saveImage(whole)
    local tl = self.timeline
    if not self.canvas.bb then return end
    local dir = (G_reader_settings and G_reader_settings:readSetting("screenshot_dir"))
        or (DataStorage:getFullDataDir() .. "/screenshots")
    lfs.mkdir(dir)
    local safe = (tl.name ~= "" and tl.name or "timeline"):gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
    local base = dir .. "/Timeline_" .. safe .. os.date("_%Y-%m-%d_%H-%M-%S")
    local w, h = self.canvas.dimen.w, self.canvas.dimen.h
    local saved
    local ok = pcall(function()
        if not whole then
            saved = base .. ".png"
            self.canvas.bb:writePNG(saved)
            return
        end
        local count = #self.pages
        local total_h = h + (count - 1) * (h - self.header_h)
        local function page_bb(p)
            return (renderTimelinePage(tl, self.pages, p, w, h, self.header_h, self.gray, self.order_label))
        end
        if w * total_h <= 9000000 then
            local bb_type = Screen.bb and Screen.bb:getType() or Blitbuffer.TYPE_BB8
            local big = Blitbuffer.new(w, total_h, bb_type)
            big:fill(Blitbuffer.COLOR_WHITE)
            for p = 1, count do
                local pbb = page_bb(p)
                if p == 1 then
                    big:blitFrom(pbb, 0, 0, 0, 0, w, h)
                else
                    big:blitFrom(pbb, 0, h + (p - 2) * (h - self.header_h), 0, self.header_h, w, h - self.header_h)
                end
                pbb:free()
            end
            saved = base .. ".png"
            big:writePNG(saved)
            big:free()
        else
            for p = 1, count do
                local pbb = page_bb(p)
                saved = base .. "_p" .. p .. ".png"
                pbb:writePNG(saved)
                pbb:free()
            end
            saved = base .. "_p*.png"
        end
    end)
    UIManager:show(InfoMessage:new{
        text = ok and T(_("Saved to:\n%1"), saved or dir) or _("Could not save the image."),
        timeout = 4,
    })
end

function TimelineView:showShotMenu()
    local dialog
    local function pick(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    local buttons = {}
    if self.gesture_mode then
        table.insert(buttons, {
            { text = _("Turn off gesture mode"), callback = pick(function()
                self.gesture_mode = false
            end) },
        })
    else
        table.insert(buttons, {
            { text = _("Gesture / screenshot mode"), callback = pick(function()
                self.gesture_mode = true
                UIManager:show(InfoMessage:new{
                    text = _("Gesture mode is on: the timeline ignores touches so your own gestures, like the screenshot gesture, work. Tap Shot to turn it off."),
                    timeout = 4,
                })
            end) },
        })
    end
    table.insert(buttons, {
        { text = _("Save this page as image"), callback = pick(function() self:saveImage(false) end) },
    })
    table.insert(buttons, {
        { text = _("Save whole timeline as image"), callback = pick(function() self:saveImage(true) end) },
    })
    table.insert(buttons, {
        { text = _("Cancel"), id = "close", callback = pick(function() end) },
    })
    dialog = ButtonDialog:new{
        title = self.gesture_mode and _("Screenshots (gesture mode is on)") or _("Screenshots"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function TimelineView:turn(delta)
    local target = self.page_index + delta
    if target < 1 or target > #self.pages then return end
    self.page_index = target
    self:rebuild()
end

function TimelineView:onNextPage()
    self:turn(1)
    return true
end

function TimelineView:onPrevPage()
    self:turn(-1)
    return true
end

function TimelineView:onClose()
    UIManager:close(self, "flashui")
    return true
end

function TimelineView:onCloseWidget()
    if self.canvas then self.canvas:freeBuffer() end
    if self.tracker._timeline_view == self then self.tracker._timeline_view = nil end
end

function CharacterTracker:showTimelineView(tl)
    if self._timeline_view then
        UIManager:close(self._timeline_view)
        self._timeline_view = nil
    end
    if tl.view == "list" then
        self:showTimelineListView(tl)
        return
    end
    local view = TimelineView:new{ tracker = self, timeline = tl }
    self._timeline_view = view
    UIManager:show(view)
end

function CharacterTracker:showTimelineListView(tl)
    local item_table = {}
    table.insert(item_table, {
        text = _("+ Add event"),
        callback = function()
            self:showTimelineEventDialog(tl, nil, function(event)
                self:showTimelineEventDetail(tl, event)
            end)
        end,
    })
    table.insert(item_table, {
        text = _("⚙ Timeline options"),
        callback = function()
            self:showTimelineMoreMenu(tl, nil)
        end,
    })
    local last = self._timeline_last and self._timeline_last[tl.id]
    local last_index
    local mode = timelineMarginMode(tl)
    for _n, item in ipairs(self:_timelineOrderedEvents(tl)) do
        local event = item.event
        local label_parts = {}
        if mode ~= "page" and event.when ~= "" then label_parts[#label_parts + 1] = shorten(event.when, 28) end
        if mode ~= "date" and event.page ~= "" then label_parts[#label_parts + 1] = "p. " .. event.page end
        if #label_parts == 0 and event.earlier then label_parts[1] = _("earlier") end
        local text = event.title ~= "" and event.title or _("(untitled event)")
        if #label_parts > 0 then text = table.concat(label_parts, " · ") .. "   " .. text end
        if mode == "page" and event.when ~= "" then text = text .. "   ·   " .. shorten(event.when, 28) end
        if event.earlier and #label_parts > 0 and label_parts[1] ~= _("earlier") then
            text = text .. "  (" .. _("earlier") .. ")"
        end
        local note_total = #event.notes
        for _i, excerpt in ipairs(event.excerpts) do note_total = note_total + #excerpt.notes end
        if note_total > 0 then text = text .. "  ✎" .. note_total end
        table.insert(item_table, {
            text = text,
            callback = function()
                self._timeline_last = self._timeline_last or {}
                self._timeline_last[tl.id] = event.id
                self:showTimelineEventDetail(tl, event)
            end,
        })
        if last and event.id == last then last_index = #item_table end
    end

    local container
    local menu
    menu = Menu:new{
        title = (tl.name ~= "" and tl.name or _("Timeline")) .. T(_("  ·  %1 event(s)"), #tl.events),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = function()
            UIManager:close(container)
            if self._timeline_view == container then self._timeline_view = nil end
        end,
    }
    if last_index then
        pcall(function() menu:switchItemTable(nil, item_table, last_index) end)
    end
    container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = container
    self._timeline_view = container
    UIManager:show(container)
end

function CharacterTracker:showTimelineMoreMenu(tl, view)
    local function close_and(fn)
        return function()
            UIManager:close(self._timeline_more_dialog)
            self._timeline_more_dialog = nil
            fn()
        end
    end
    local function reopen() self:showTimelineView(tl) end
    self._timeline_more_dialog = self:newButtonDialog("timeline_more"){
        title = tl.name ~= "" and tl.name or _("Timeline"),
        buttons = {
            {
                { text = tl.view == "list" and _("View: list") or _("View: timeline"), callback = close_and(function()
                    tl.view = tl.view == "list" and "timeline" or "list"
                    self:saveTimeline()
                    reopen()
                end) },
                { text = tl.reverse and _("Newest first") or _("Oldest first"), callback = close_and(function()
                    tl.reverse = not tl.reverse or nil
                    self:saveTimeline()
                    reopen()
                end) },
            },
            {
                { text = _("All events"), callback = close_and(function() self:showTimelineEventsManager(tl) end) },
            },
            {
                { text = _("Rename"), callback = close_and(function() self:showRenameTimelineDialog(tl, reopen) end) },
                { text = _("Description"), callback = close_and(function() self:showTimelineDescriptionDialog(tl, reopen) end) },
            },
            {
                { text = tl.sort == "page" and _("Order: by page") or _("Order: manual"), callback = close_and(function()
                    tl.sort = tl.sort == "page" and "manual" or "page"
                    self:saveTimeline()
                    reopen()
                end) },
            },
            {
                { text = T(_("Left margin: %1"),
                    timelineMarginMode(tl) == "date" and _("date")
                        or (timelineMarginMode(tl) == "both" and _("date & page") or _("page"))),
                  callback = close_and(function()
                    local mode = timelineMarginMode(tl)
                    tl.margin = mode == "page" and "date" or (mode == "date" and "both" or "page")
                    self:saveTimeline()
                    reopen()
                end) },
            },
            {
                { text = _("Delete timeline"), callback = close_and(function() self:deleteTimeline(tl) end) },
                { text = _("Open list"), callback = close_and(function()
                    local current = view or self._timeline_view
                    if current then UIManager:close(current) end
                    self._timeline_view = nil
                    self:showTimelineList()
                end) },
            },
            {
                { text = _("Cancel"), id = "close", callback = function()
                    UIManager:close(self._timeline_more_dialog)
                    self._timeline_more_dialog = nil
                end },
            },
        },
    }
    UIManager:show(self._timeline_more_dialog)
end

function CharacterTracker:showRenameTimelineDialog(tl, on_done)
    local dialog
    dialog = InputDialog:new{
        title = _("Rename timeline"),
        input = tl.name or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local name = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if name ~= "" then
                            tl.name = name
                            self:saveTimeline()
                        end
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showTimelineDescriptionDialog(tl, on_done)
    local dialog
    dialog = InputDialog:new{
        title = _("Timeline description"),
        input = tl.description or "",
        input_hint = _("What does this timeline cover?"),
        text_height = math.floor(Device.screen:getHeight() * 0.35),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        tl.description = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        self:saveTimeline()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:deleteTimeline(tl)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete timeline '%1' and its %2 event(s)?"), tl.name, #tl.events),
        ok_text = _("Delete"),
        ok_callback = function()
            for i = #self.timelines, 1, -1 do
                if self.timelines[i] == tl then
                    table.remove(self.timelines, i)
                    break
                end
            end
            if self._timeline_view then
                UIManager:close(self._timeline_view)
                self._timeline_view = nil
            end
            self:saveTimeline()
            UIManager:show(InfoMessage:new{
                text = T(_("Deleted '%1'."), tl.name),
                timeout = 2,
            })
        end,
    })
end

function CharacterTracker:showTimelineEventsManager(tl)
    local buttons = {}
    for n, item in ipairs(self:_timelineOrderedEvents(tl)) do
        local event = item.event
        local label = n .. ". "
        if event.page ~= "" then label = label .. "p." .. event.page .. " · " end
        label = label .. (event.title ~= "" and event.title or _("(untitled event)"))
        table.insert(buttons, {
            {
                text = shorten(label, 42),
                callback = function()
                    UIManager:close(self._timeline_events_dialog)
                    self._timeline_events_dialog = nil
                    self:showTimelineEventDetail(tl, event)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._timeline_events_dialog)
                    self._timeline_events_dialog = nil
                    table.remove(tl.events, item.index)
                    self:saveTimeline()
                    self:showTimelineEventsManager(tl)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add event"),
            callback = function()
                UIManager:close(self._timeline_events_dialog)
                self._timeline_events_dialog = nil
                self:showTimelineEventDialog(tl, nil, function(event)
                    self:showTimelineEventDetail(tl, event)
                end)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._timeline_events_dialog)
                self._timeline_events_dialog = nil
                self:showTimelineView(tl)
            end,
        },
    })
    self._timeline_events_dialog = ButtonDialog:new{
        title = T(_("Events — %1"), tl.name),
        buttons = buttons,
    }
    UIManager:show(self._timeline_events_dialog)
end

function CharacterTracker:showTimelineEventDialog(tl, event, on_done, preset)
    local dialog
    dialog = MultiInputDialog:new{
        title = event and _("Edit event") or _("New event"),
        fields = {
            { text = event and event.title or (preset and preset.title) or "", hint = _("What happened? (title)") },
            { text = event and event.page or (preset and preset.page) or "",
              hint = self:_currentPageText() ~= "" and T(_("Page (optional) — you're on page %1"), self:_currentPageText())
                  or _("Page (optional)") },
            { text = event and event.when or "", hint = _("Date / when it happened (optional) — e.g. Day 3, spring of 1203") },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if event and on_done then on_done(event) end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        local title, page, when = trim(fields[1]), trim(fields[2]), trim(fields[3])
                        UIManager:close(dialog)
                        if title == "" and not event then return end
                        if event then
                            event.title, event.page, event.when = title, page, when
                        else
                            event = {
                                id = genId(), title = title, page = page, when = when,
                                text = "", excerpts = {}, notes = {}, characters = {}, places = {}, objects = {},
                                created = os.date("%Y-%m-%d %H:%M"),
                            }
                            table.insert(tl.events, event)
                        end
                        self:saveTimeline()
                        if on_done then on_done(event) end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showTimelineEventDetail(tl, event)
    self._timeline_last = self._timeline_last or {}
    self._timeline_last[tl.id] = event.id
    local viewer
    local function reopen() self:showTimelineEventDetail(tl, event) end
    local function go(fn)
        return function()
            UIManager:close(viewer)
            fn()
        end
    end
    local function move(step)
        local index
        for i, e in ipairs(tl.events) do
            if e == event then index = i end
        end
        local j = index and index + step
        if index and j >= 1 and j <= #tl.events then
            tl.events[index], tl.events[j] = tl.events[j], tl.events[index]
            self:saveTimeline()
        end
        reopen()
    end
    viewer = self:newTextViewer("timeline_event"){
        title = event.title ~= "" and event.title or _("Event"),
        text = (self:buildTimelineEventBlock(event):gsub("^\n+", "")),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = {
            {
                { text = _("Details"), callback = go(function()
                    self:showTimelineEventDialog(tl, event, reopen)
                end) },
                { text = _("Links"), callback = go(function()
                    self:showTimelineEventLinksMenu(tl, event)
                end) },
                { text = _("Write"), callback = go(function()
                    self:showTimelineEventTextDialog(tl, event, reopen)
                end) },
                { text = _("Notes"), callback = go(function()
                    self:showStringListManager({ name = event.title, notes = event.notes }, "notes", {
                        title = _("Notes"),
                        add_label = _("+ Add note"),
                        add_title = _("Add note"),
                        edit_title = _("Edit note"),
                        hint = _("anything worth remembering about this event"),
                        on_change = function() self:saveTimeline() end,
                        on_close = reopen,
                    })
                end) },
            },
            {
                { text = _("＋ Excerpt"), callback = go(function()
                    self:showTimelineExcerptDialog(tl, event, nil, reopen)
                end) },
                { text = _("Excerpts"), callback = go(function()
                    self:showTimelineExcerptsManager(tl, event)
                end) },
                { text = "▲", callback = go(function() move(-1) end) },
                { text = "▼", callback = go(function() move(1) end) },
            },
            {
                { text = event.earlier and _("Earlier: on") or _("Earlier: off"), callback = go(function()
                    event.earlier = not event.earlier or nil
                    self:saveTimeline()
                    reopen()
                end) },
                { text = _("Delete"), callback = go(function()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete the event '%1'?"), event.title),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            for i = #tl.events, 1, -1 do
                                if tl.events[i] == event then table.remove(tl.events, i) end
                            end
                            self:saveTimeline()
                            self:showTimelineView(tl)
                        end,
                        cancel_callback = reopen,
                    })
                end) },
                { text = _("Back to timeline"), callback = go(function() self:showTimelineView(tl) end) },
            },
        },
        close_callback = function()
            self:showTimelineView(tl)
        end,
    }
    UIManager:show(viewer)
end

local TIMELINE_LINK_KINDS = {
    characters = { label = _("Characters"), ask = _("Who was involved in '%1'?"), hint = _("Name of someone not in your character list") },
    places = { label = _("Places"), ask = _("Where did '%1' happen?"), hint = _("Name of a place that isn't tracked") },
    objects = { label = _("Compendium"), ask = _("Which compendium entry is part of '%1'?"), hint = _("Name of an entry that isn't tracked") },
}

function CharacterTracker:_timelineLinkSource(kind)
    if kind == "places" then return self.places or {} end
    if kind == "objects" then return self.compendium or {} end
    return self.characters or {}
end

function CharacterTracker:showTimelineEventLinksMenu(tl, event)
    local dialog
    local function pick(kind)
        return function()
            UIManager:close(dialog)
            self:showTimelineEventLinks(tl, event, kind)
        end
    end
    local function count(kind) return #(event[kind] or {}) end
    dialog = ButtonDialog:new{
        title = T(_("Link to '%1'"), event.title),
        buttons = {
            {
                { text = T(_("Characters (%1)"), count("characters")), callback = pick("characters") },
                { text = T(_("Places (%1)"), count("places")), callback = pick("places") },
            },
            {
                { text = T(_("Compendium (%1)"), count("objects")), callback = pick("objects") },
            },
            {
                { text = _("Back"), id = "close", callback = function()
                    UIManager:close(dialog)
                    self:showTimelineEventDetail(tl, event)
                end },
            },
        },
    }
    UIManager:show(dialog)
end

function CharacterTracker:showTimelineEventCharacters(tl, event)
    self:showTimelineEventLinks(tl, event, "characters")
end

function CharacterTracker:showTimelineEventLinks(tl, event, kind)
    local info = TIMELINE_LINK_KINDS[kind]
    if type(event[kind]) ~= "table" then event[kind] = {} end
    local list = event[kind]
    local function back() self:showTimelineEventLinks(tl, event, kind) end
    local function open(name)
        if kind == "characters" then
            local char = self:getCharacterByName(name)
            if char then self:showCharacterDetailReadOnly(char) end
        elseif kind == "places" then
            local place = self:getPlaceByName(name)
            if place then self:showPlaceDetail(place) end
        else
            local entry = self:getCompendiumEntryByName(name)
            if entry then self:showCompendiumDetail(entry) end
        end
    end
    local buttons = {}
    for i, name in ipairs(list) do
        table.insert(buttons, {
            {
                text = name,
                callback = function()
                    UIManager:close(self._timeline_links_dialog)
                    self._timeline_links_dialog = nil
                    open(name)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._timeline_links_dialog)
                    self._timeline_links_dialog = nil
                    table.remove(list, i)
                    self:saveTimeline()
                    back()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add"),
            callback = function()
                UIManager:close(self._timeline_links_dialog)
                self._timeline_links_dialog = nil
                local present = {}
                for _i, name in ipairs(list) do present[name:lower()] = true end
                local choices = {}
                for _i, item in ipairs(self:_timelineLinkSource(kind)) do
                    if item.name and not present[item.name:lower()] then
                        table.insert(choices, { label = item.name, value = item.name })
                    end
                end
                self:_showChoice(T(info.ask, event.title), choices, function(name)
                    if not present[name:lower()] then
                        table.insert(list, name)
                        self:saveTimeline()
                    end
                    back()
                end, { hint = info.hint })
            end,
        },
        {
            text = _("Done"),
            id = "close",
            callback = function()
                UIManager:close(self._timeline_links_dialog)
                self._timeline_links_dialog = nil
                self:showTimelineEventLinksMenu(tl, event)
            end,
        },
    })
    self._timeline_links_dialog = ButtonDialog:new{
        title = T(_("%1 in '%2'"), info.label, event.title),
        buttons = buttons,
    }
    UIManager:show(self._timeline_links_dialog)
end

function CharacterTracker:showTimelineEventTextDialog(tl, event, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("What happened — %1"), event.title),
        input = event.text or "",
        input_hint = _("Write what happened in your own words…"),
        text_height = math.floor(Device.screen:getHeight() * 0.4),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        event.text = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        self:saveTimeline()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showTimelineExcerptDialog(tl, event, index, on_done, preset_text, preset_page)
    local excerpt = index and event.excerpts[index] or nil
    local dialog
    dialog = InputDialog:new{
        title = excerpt and _("Edit excerpt") or _("Add excerpt"),
        input = excerpt and getNoteText(excerpt.text) or preset_text or "",
        input_hint = _("Paste or type a passage / quote"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Next"),
                    is_enter_default = true,
                    callback = function()
                        local text = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if text == "" then
                            if on_done then on_done() end
                            return
                        end
                        local page_dialog
                        page_dialog = InputDialog:new{
                            title = _("Page of this excerpt"),
                            input = excerpt and excerpt.page or preset_page or "",
                            input_hint = self:_currentPageText() ~= ""
                                and T(_("Page (optional) — you're on page %1"), self:_currentPageText())
                                or _("Page (optional)"),
                            buttons = {
                                {
                                    {
                                        text = _("Skip"),
                                        id = "close",
                                        callback = function()
                                            UIManager:close(page_dialog)
                                            if excerpt then
                                                excerpt.text = text
                                            else
                                                table.insert(event.excerpts, { text = text, page = "", notes = {} })
                                            end
                                            self:saveTimeline()
                                            if on_done then on_done() end
                                        end,
                                    },
                                    {
                                        text = _("Save"),
                                        is_enter_default = true,
                                        callback = function()
                                            local page = trim(page_dialog:getInputText())
                                            UIManager:close(page_dialog)
                                            if excerpt then
                                                excerpt.text, excerpt.page = text, page
                                            else
                                                table.insert(event.excerpts, { text = text, page = page, notes = {} })
                                            end
                                            self:saveTimeline()
                                            if on_done then on_done() end
                                        end,
                                    },
                                },
                            },
                        }
                        self:_showInputDialog(page_dialog)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showTimelineExcerptsManager(tl, event)
    local function back() self:showTimelineExcerptsManager(tl, event) end
    local buttons = {}
    for i, excerpt in ipairs(event.excerpts) do
        local note_count = #excerpt.notes
        local label = "“" .. shorten(getNoteText(excerpt.text), 28) .. "”"
        if excerpt.page ~= "" then label = label .. " p." .. excerpt.page end
        if note_count > 0 then label = label .. " ✎" .. note_count end
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._timeline_excerpts_dialog)
                    self._timeline_excerpts_dialog = nil
                    self:showTimelineExcerptActions(tl, event, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._timeline_excerpts_dialog)
                    self._timeline_excerpts_dialog = nil
                    self:confirmDeleteTimelineExcerpt(event, i, back)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add excerpt"),
            callback = function()
                UIManager:close(self._timeline_excerpts_dialog)
                self._timeline_excerpts_dialog = nil
                self:showTimelineExcerptDialog(tl, event, nil, back)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._timeline_excerpts_dialog)
                self._timeline_excerpts_dialog = nil
                self:showTimelineEventDetail(tl, event)
            end,
        },
    })
    self._timeline_excerpts_dialog = ButtonDialog:new{
        title = T(_("Excerpts — %1"), event.title),
        buttons = buttons,
    }
    UIManager:show(self._timeline_excerpts_dialog)
end

function CharacterTracker:confirmDeleteTimelineExcerpt(event, index, back)
    local excerpt = event.excerpts[index]
    if not excerpt then
        back()
        return
    end
    UIManager:show(ConfirmBox:new{
        text = T(_("Are you sure you want to delete this excerpt?\n\n“%1”"), shorten(getNoteText(excerpt.text), 90)),
        ok_text = _("Delete"),
        ok_callback = function()
            table.remove(event.excerpts, index)
            self:saveTimeline()
            back()
        end,
        cancel_callback = back,
    })
end

function CharacterTracker:showTimelineExcerptActions(tl, event, index)
    local excerpt = event.excerpts[index]
    if not excerpt then return end
    local function back() self:showTimelineExcerptsManager(tl, event) end
    local function close_and(fn)
        return function()
            UIManager:close(self._timeline_excerpt_act_dialog)
            self._timeline_excerpt_act_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = index + step
        if j >= 1 and j <= #event.excerpts then
            event.excerpts[index], event.excerpts[j] = event.excerpts[j], event.excerpts[index]
            self:saveTimeline()
        end
        back()
    end
    local note_count = #excerpt.notes
    self._timeline_excerpt_act_dialog = ButtonDialog:new{
        title = shorten("“" .. getNoteText(excerpt.text) .. "”", 60),
        buttons = {
            {
                { text = _("Edit excerpt"), callback = close_and(function()
                    self:showTimelineExcerptDialog(tl, event, index, back)
                end) },
                { text = note_count > 0 and T(_("Notes (%1)"), note_count) or _("Notes"), callback = close_and(function()
                    self:showHighlightNotesManager(self:_timelineSaver(), event.excerpts, index, back)
                end) },
            },
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function() move(-1) end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function() move(1) end) },
            },
            {
                { text = _("Delete"), callback = close_and(function()
                    self:confirmDeleteTimelineExcerpt(event, index, back)
                end) },
                { text = _("Back"), id = "close", callback = close_and(back) },
            },
        },
    }
    UIManager:show(self._timeline_excerpt_act_dialog)
end

function CharacterTracker:showTimelineQuickAdd()
    local function with_timeline(tl)
        self:showTimelineEventDialog(tl, nil, function(event)
            self:showTimelineEventDetail(tl, event)
        end)
    end
    if #self.timelines == 0 then
        self:showAddTimelineDialog(with_timeline)
        return
    end
    local choices = {}
    for _i, tl in ipairs(self.timelines) do
        table.insert(choices, { label = tl.name ~= "" and tl.name or _("(unnamed)"), value = tl.id })
    end
    table.insert(choices, { label = _("+ New timeline"), value = "__new" })
    self:_showChoice(_("Log an event on which timeline?"), choices, function(id)
        if id == "__new" then
            self:showAddTimelineDialog(with_timeline)
        else
            local tl = self:getTimelineById(id)
            if tl then with_timeline(tl) end
        end
    end)
end

function CharacterTracker:showAssignTimelineExcerpt(text, page)
    local function with_timeline(tl)
        local choices = {}
        for _i, event in ipairs(tl.events) do
            local label = event.title ~= "" and event.title or _("(untitled event)")
            if event.page ~= "" then label = "p." .. event.page .. " · " .. label end
            table.insert(choices, { label = shorten(label, 36), value = event.id })
        end
        table.insert(choices, { label = _("＋ New event"), value = "__new" })
        self:_showChoice(T(_("Add the excerpt to which event of '%1'?"), tl.name), choices, function(id)
            if id == "__new" then
                self:showTimelineEventDialog(tl, nil, function(event)
                    table.insert(event.excerpts, { text = text, page = page, notes = {} })
                    self:saveTimeline()
                    self:showTimelineEventDetail(tl, event)
                end, { title = shorten(text, 50), page = page })
                return
            end
            for _i, event in ipairs(tl.events) do
                if event.id == id then
                    table.insert(event.excerpts, { text = text, page = page, notes = {} })
                    self:saveTimeline()
                    UIManager:show(InfoMessage:new{
                        text = T(_("Excerpt added to '%1'."), event.title),
                        timeout = 2,
                    })
                    return
                end
            end
        end)
    end
    if #self.timelines == 0 then
        self:showAddTimelineDialog(with_timeline)
        return
    end
    if #self.timelines == 1 then
        with_timeline(self.timelines[1])
        return
    end
    local choices = {}
    for _i, tl in ipairs(self.timelines) do
        table.insert(choices, { label = tl.name ~= "" and tl.name or _("(unnamed)"), value = tl.id })
    end
    self:_showChoice(_("Which timeline?"), choices, function(id)
        local tl = self:getTimelineById(id)
        if tl then with_timeline(tl) end
    end)
end

function CharacterTracker:onShowTimelineList()
    self:showTimelineList()
end

function CharacterTracker:getFamilyByName(name)
    if not name then return nil end
    local nl = name:lower()
    for _i, family in ipairs(self.families) do
        if family.name and family.name:lower() == nl then return family end
    end
    return nil
end

function CharacterTracker:getFamilyById(id)
    if not id then return nil end
    for _i, family in ipairs(self.families) do
        if family.id == id then return family end
    end
    return nil
end

function CharacterTracker:showFamilyList()
    self._family_collapsed = self._family_collapsed or {}
    local item_table = {}
    table.insert(item_table, {
        text = _("+ Add family"),
        callback = function()
            self:showAddFamilyDialog()
        end,
    })
    local sections = {
        { key = "family", label = _("Families"), list = {} },
        { key = "social", label = _("Relationships"), list = {} },
    }
    for _i, family in ipairs(self.families) do
        local section = family.tree_kind == "social" and sections[2] or sections[1]
        table.insert(section.list, family)
    end
    local menu_container
    local menu
    for _i, section in ipairs(sections) do
        if #section.list > 0 then
            local collapsed = self._family_collapsed[section.key]
            table.insert(item_table, {
                text = (collapsed and "▸ " or "▾ ") .. section.label .. " (" .. #section.list .. ")",
                callback = function()
                    self._family_collapsed[section.key] = not collapsed or nil
                    UIManager:close(menu_container)
                    self:showFamilyList()
                end,
            })
            if not collapsed then
                for _j, family in ipairs(section.list) do
                    local suffix = ""
                    if family.members and #family.members > 0 then
                        suffix = T(_("  ·  %1 member(s)"), #family.members)
                    end
                    table.insert(item_table, {
                        text = "      " .. (family.name or _("(unnamed)")) .. suffix,
                        callback = function()
                            self:showFamilyDetail(family)
                        end,
                    })
                end
            end
        end
    end

    menu = Menu:new{
        title = T(_("Families (%1)"), #self.families),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = function()
            UIManager:close(menu_container)
        end,
    }
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

function CharacterTracker:showFamilyTreePicker(read_only)
    if not self.families or #self.families == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No families yet. Add a family first."),
        })
        return
    end
    local item_table = {}
    for _i, social in ipairs({ false, true }) do
        local list = {}
        for _j, family in ipairs(self.families) do
            if (family.tree_kind == "social") == social then table.insert(list, family) end
        end
        if #list > 0 then
            table.insert(item_table, {
                text = "▾ " .. (social and _("Relationships") or _("Families")) .. " (" .. #list .. ")",
            })
            for _j, family in ipairs(list) do
                local suffix = ""
                if family.members and #family.members > 0 then
                    suffix = T(_("  ·  %1 member(s)"), #family.members)
                end
                table.insert(item_table, {
                    text = "      " .. (family.name or _("(unnamed)")) .. suffix,
                    callback = function()
                        self:showFamilyTree(family, read_only)
                    end,
                })
            end
        end
    end

    local menu_container
    local menu
    menu = Menu:new{
        title = read_only and _("Family tree — choose a family") or _("Edit family tree — choose a family"),
        item_table = item_table,
        is_borderless = true,
        is_popout = false,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = function()
            UIManager:close(menu_container)
        end,
    }
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

local function lowerOrEmpty(s)
    return (s or ""):lower()
end

local function memberByName(family, name)
    local key = lowerOrEmpty(name)
    for _i, member in ipairs(family.members or {}) do
        if lowerOrEmpty(member.name) == key then return member end
    end
    return nil
end

local function tieChoices()
    return {
        { label = _("By blood"), value = _("By blood") },
        { label = _("By marriage"), value = _("By marriage") },
        { label = _("Adopted"), value = _("Adopted") },
        { label = _("Fostered"), value = _("Fostered") },
        { label = _("Sworn"), value = _("Sworn") },
        { label = _("— none —"), value = "" },
    }
end

local function relationChoices()
    local out = {}
    for _i, rt in ipairs(RELATIONSHIP_TYPES) do
        if rt.key ~= "custom" then
            table.insert(out, { label = rt.label, value = rt.key })
        end
    end
    table.insert(out, { label = _("— none (sentiment only) —"), value = "" })
    return out
end

local function sentimentChoices()
    local out = {}
    for _i, st in ipairs(SENTIMENT_TYPES) do
        if st.key ~= "custom" then
            table.insert(out, { label = st.label, value = st.key })
        end
    end
    table.insert(out, { label = _("— none —"), value = "" })
    return out
end

local function houseKindChoices()
    return {
        { label = _("Allied"), value = _("Allied") },
        { label = _("Rival"), value = _("Rival") },
        { label = _("Enemy"), value = _("Enemy") },
        { label = _("Vassal of"), value = _("Vassal of") },
        { label = _("Lord of"), value = _("Lord of") },
        { label = _("Marriage ties"), value = _("Marriage ties") },
        { label = _("Neutral"), value = _("Neutral") },
    }
end

local function traitKindChoices()
    return {
        { label = _("Ability"), value = _("Ability") },
        { label = _("Power"), value = _("Power") },
        { label = _("Curse"), value = _("Curse") },
        { label = _("Blessing"), value = _("Blessing") },
        { label = _("Trait"), value = _("Trait") },
        { label = _("Tradition"), value = _("Tradition") },
    }
end

local function memberChoices(family, exclude)
    local out = {}
    local skip = lowerOrEmpty(exclude)
    for _i, member in ipairs(family.members or {}) do
        if member.name and lowerOrEmpty(member.name) ~= skip then
            table.insert(out, { label = member.name, value = member.name })
        end
    end
    return out
end

local function describeInnerRelation(rel)
    local label = (rel.type and rel.type ~= "") and getRelationshipLabel(rel.type) or _("(sentiment only)")
    local display = (rel.from or "?") .. " → " .. (rel.to or "?") .. " — " .. label
    local sentiment = getSentimentLabel(rel.sentiment)
    if sentiment then
        display = display .. " · " .. sentiment
    end
    return display
end

local function describeHouse(house)
    local bits = {}
    if house.kind and house.kind ~= "" then
        table.insert(bits, house.kind)
    end
    local sentiment = getSentimentLabel(house.sentiment)
    if sentiment then
        table.insert(bits, sentiment)
    end
    local head = house.family or "?"
    if #bits == 0 then return head end
    return head .. ": " .. table.concat(bits, " · ")
end

local function placeholderByName(family, name)
    local key = lowerOrEmpty(name)
    for _i, ph in ipairs(family.placeholders or {}) do
        if lowerOrEmpty(ph.name) == key then return ph end
    end
    return nil
end

local COUPLE_STYLES = {
    { key = "married",  visual = "double", visual_label = _("double line") },
    { key = "partners", visual = "solid",  visual_label = _("solid line") },
    { key = "casual",   visual = "dashed", visual_label = _("dashed line") },
    { key = "former",   visual = "dotted", visual_label = _("dotted line") },
    { key = "none",     visual = "none",   visual_label = "" },
}

local LINE_MEANING_DEFAULTS = {
    married = _("Married"), partners = _("Together"), casual = _("Not a couple"), former = _("Former"),
    child_dashed = _("Adopted / foster parent"), child_dotted = _("Guardian / step-parent"),
}

for _i, kind in ipairs(TIE_KINDS) do
    LINE_MEANING_DEFAULTS["tie_" .. kind.key] = kind.label
end

local LINE_MEANING_KEYS = {
    { key = "married", visual = "double", group = _("Couples") },
    { key = "partners", visual = "solid", group = _("Couples") },
    { key = "casual", visual = "dashed", group = _("Couples") },
    { key = "former", visual = "dotted", group = _("Couples") },
    { key = "child_dashed", visual = "dashed", group = _("Parents and children") },
    { key = "child_dotted", visual = "dotted", group = _("Parents and children") },
}

for _i, kind in ipairs(TIE_KINDS) do
    table.insert(LINE_MEANING_KEYS, { key = "tie_" .. kind.key, visual = kind.visual, group = kind.group_label })
end

local LEGACY_TIE_MEANINGS = {
    tie_friend = "social_solid", tie_ally = "social_double", tie_enemy = "social_dashed", tie_rival = "social_dotted",
    tie_dating = "dating_solid", tie_married = "dating_double", tie_complicated = "dating_dashed", tie_ex = "dating_dotted",
}

local function lineMeaning(key)
    local saved = G_reader_settings and G_reader_settings:readSetting("character_tracker_line_meanings")
    local custom = type(saved) == "table" and saved[key]
    if (not custom or custom == "") and type(saved) == "table" and LEGACY_TIE_MEANINGS[key] then
        custom = saved[LEGACY_TIE_MEANINGS[key]]
    end
    if custom and custom ~= "" then return custom end
    return LINE_MEANING_DEFAULTS[key] or key
end

local function tieKind(key)
    return TIE_KIND_BY_KEY[key] or TIE_KIND_BY_KEY.friend
end

local function tieKindMeaning(key)
    return lineMeaning("tie_" .. tieKind(key).key)
end

local TIE_VISUALS = { "solid", "thin", "thick", "double", "dashed", "dotted", "dashdot", "wavy" }

local TIE_VISUAL_LABELS = {
    solid = _("Solid line"), thin = _("Thin line"), thick = _("Thick line"), double = _("Double line"),
    dashed = _("Dashed line"), dotted = _("Dotted line"), dashdot = _("Dash-dot line"), wavy = _("Wavy line"),
}

local function tieLink(tie)
    return tie.oneway and " → " or " ↔ "
end

local function tieInfo(tie)
    if tie.kind == "custom" and type(tie.custom) == "table" then
        local visual = TIE_VISUAL_LABELS[tie.custom.visual] and tie.custom.visual or "solid"
        return { key = "custom", custom = true, visual = visual, label = tie.custom.name or "?", desc = "" }
    end
    local kind = tieKind(tie.kind)
    return { key = kind.key, visual = kind.visual, label = tieKindMeaning(kind.key), desc = kind.desc, pull = kind.pull }
end

local TREE_SCALES = { 0.5, 0.65, 0.8, 1.0, 1.25, 1.5, 1.8 }
local TREE_MAX_PIXELS = 9000000
local TREE_FONT_DEFAULTS = { first = 23, last = 17, info = 15 }

local function parseCustomCouple(style)
    if type(style) ~= "string" then return nil end
    local base, name = style:match("^custom|(%a+)|(.+)$")
    if base then return base, name end
    return nil
end

local function coupleBaseStyle(style)
    return parseCustomCouple(style) or style
end

local function coupleStyleLabel(key)
    if key == "none" then return _("No line") end
    local custom_base, custom_name = parseCustomCouple(key)
    if custom_base then
        for _i, st in ipairs(COUPLE_STYLES) do
            if st.key == custom_base then return custom_name .. " — " .. st.visual_label end
        end
        return custom_name
    end
    for _i, st in ipairs(COUPLE_STYLES) do
        if st.key == key then return lineMeaning(key) .. " — " .. st.visual_label end
    end
    return key
end

local function coupleStyleShort(key)
    return (coupleStyleLabel(key):gsub("%s*—.*$", ""))
end

local function coupleKey(a, b)
    a, b = lowerOrEmpty(a), lowerOrEmpty(b)
    if a > b then a, b = b, a end
    return a .. "|" .. b
end

local PARENT_LINK_TYPES = {
    father = { parent = "to" },
    mother = { parent = "to" },
    parent = { parent = "to" },
    son = { parent = "from" },
    daughter = { parent = "from" },
    child = { parent = "from" },
    adoptive_parent = { parent = "to", kind = "adopted" },
    adopted_child = { parent = "from", kind = "adopted" },
    guardian = { parent = "to", kind = "guardian" },
    ward = { parent = "from", kind = "guardian" },
    step_parent = { parent = "to", kind = "step" },
    step_child = { parent = "from", kind = "step" },
    foster_parent = { parent = "to", kind = "foster" },
    foster_child = { parent = "from", kind = "foster" },
}

local PARTNER_TYPES = {
    spouse = { style = "married", rank = 4 },
    partner = { style = "partners", rank = 3 },
    lover = { style = "casual", rank = 2 },
    ex = { style = "former", rank = 1 },
}

local function buildFamilyGraph(family)
    local members = family.members or {}
    if #members == 0 then return nil end
    local canon, order, plain, gender = {}, {}, {}, {}
    for _i, m in ipairs(members) do
        local key = lowerOrEmpty(m.name)
        if key ~= "" and not canon[key] then
            canon[key] = m.name
            plain[key] = m.name
            order[#order + 1] = key
            if m.gender == "male" or m.gender == "female" then gender[key] = m.gender end
        end
    end
    for _i, ph in ipairs(family.placeholders or {}) do
        local key = lowerOrEmpty(ph.name)
        if key ~= "" and not canon[key] then
            canon[key] = "[" .. ph.name .. "]"
            order[#order + 1] = key
        end
    end
    local parents, siblings, cousins = {}, {}, {}
    local partners, explicit, explicit_rank = {}, {}, {}
    local edge_kind = {}
    local function addPartner(a, b)
        if a == b or not canon[a] or not canon[b] then return end
        partners[a] = partners[a] or {}
        partners[b] = partners[b] or {}
        for _i, existing in ipairs(partners[a]) do
            if existing == b then return end
        end
        table.insert(partners[a], b)
        table.insert(partners[b], a)
    end
    local function link(parent_key, child_key, kind)
        if parent_key == child_key or not canon[parent_key] or not canon[child_key] then return end
        parents[child_key] = parents[child_key] or {}
        local present = false
        for _i, existing in ipairs(parents[child_key]) do
            if existing == parent_key then present = true end
        end
        if not present then table.insert(parents[child_key], parent_key) end
        if kind then
            edge_kind[child_key] = edge_kind[child_key] or {}
            edge_kind[child_key][parent_key] = kind
        end
    end
    for _i, m in ipairs(members) do
        local child_key = lowerOrEmpty(m.name)
        local kinds = m.parent_kinds or {}
        for _j, p in ipairs(m.parents or {}) do
            local pk = lowerOrEmpty(p)
            local kind = kinds[pk]
            if kind == "" then kind = nil end
            link(pk, child_key, kind)
        end
        for _j, p in ipairs((family.extra_parents or {})[child_key] or {}) do
            link(lowerOrEmpty(p), child_key)
        end
    end
    for _i, rel in ipairs(family.relations or {}) do
        local owner, target = lowerOrEmpty(rel.from), lowerOrEmpty(rel.to)
        local ty = rel.type
        local plink = PARENT_LINK_TYPES[ty]
        local ptype = PARTNER_TYPES[ty]
        if plink then
            if plink.parent == "to" then
                link(target, owner, plink.kind)
            else
                link(owner, target, plink.kind)
            end
        elseif ptype and plain[owner] and plain[target] then
            local pair = coupleKey(owner, target)
            if (explicit_rank[pair] or 0) < ptype.rank then
                explicit[pair] = ptype.style
                explicit_rank[pair] = ptype.rank
            end
            addPartner(owner, target)
        elseif (ty == "brother" or ty == "sister" or ty == "sibling") and plain[owner] and plain[target] then
            siblings[#siblings + 1] = { owner, target }
        elseif ty == "cousin" and plain[owner] and plain[target] then
            cousins[owner] = cousins[owner] or {}
            cousins[target] = cousins[target] or {}
            table.insert(cousins[owner], target)
            table.insert(cousins[target], owner)
        end
    end
    local group_of = {}
    local function find(k)
        while group_of[k] and group_of[k] ~= k do k = group_of[k] end
        return k
    end
    for _i, pair in ipairs(siblings) do
        group_of[pair[1]] = group_of[pair[1]] or pair[1]
        group_of[pair[2]] = group_of[pair[2]] or pair[2]
        local a, b = find(pair[1]), find(pair[2])
        if a ~= b then group_of[b] = a end
    end
    local groups, group_order = {}, {}
    for _i, key in ipairs(order) do
        if group_of[key] then
            local root = find(key)
            if not groups[root] then
                groups[root] = {}
                group_order[#group_order + 1] = root
            end
            table.insert(groups[root], key)
        end
    end
    local virtual_count = 0
    for _i, root in ipairs(group_order) do
        local group = groups[root]
        local donor
        for _j, key in ipairs(group) do
            if parents[key] and #parents[key] > 0 then
                donor = key
                break
            end
        end
        if donor then
            for _j, key in ipairs(group) do
                if not (parents[key] and #parents[key] > 0) then
                    for _k, p in ipairs(parents[donor]) do
                        link(p, key, edge_kind[donor] and edge_kind[donor][p] or nil)
                    end
                end
            end
        elseif #group >= 2 then
            virtual_count = virtual_count + 1
            local vkey = "\0sibling" .. virtual_count
            canon[vkey] = "[" .. _("Parents unknown") .. "]"
            order[#order + 1] = vkey
            for _j, key in ipairs(group) do link(vkey, key) end
        end
    end
    for _i, key in ipairs(order) do
        local by_kind, kind_order = {}, {}
        for _j, p in ipairs(parents[key] or {}) do
            local kind = edge_kind[key] and edge_kind[key][p] or "bio"
            if not by_kind[kind] then
                by_kind[kind] = {}
                kind_order[#kind_order + 1] = kind
            end
            table.insert(by_kind[kind], p)
        end
        for _j, kind in ipairs(kind_order) do
            local ps = by_kind[kind]
            if #ps >= 2 then addPartner(ps[1], ps[2]) end
        end
    end
    local children = {}
    for _i, key in ipairs(order) do
        for _j, p in ipairs(parents[key] or {}) do
            children[p] = children[p] or {}
            table.insert(children[p], key)
        end
    end
    return {
        canon = canon, plain = plain, order = order, parents = parents,
        children = children, cousins = cousins, partners = partners, explicit = explicit,
        edge_kind = edge_kind, gender = gender,
    }
end

local function filterFamilyGraph(g, allowed)
    local out = {
        canon = g.canon, plain = g.plain, explicit = g.explicit, order = {},
        parents = {}, children = {}, partners = {}, cousins = {}, edge_kind = {},
        focus = g.focus, hidden_counts = g.hidden_counts, relation_labels = g.relation_labels,
        gender = g.gender,
    }
    for _i, key in ipairs(g.order) do
        if allowed[key] then table.insert(out.order, key) end
    end
    local function copyList(source, key)
        local list = {}
        for _i, other in ipairs(source[key] or {}) do
            if allowed[other] then table.insert(list, other) end
        end
        if #list > 0 then return list end
        return nil
    end
    for _i, key in ipairs(out.order) do
        out.parents[key] = copyList(g.parents, key)
        out.children[key] = copyList(g.children, key)
        out.partners[key] = copyList(g.partners, key)
        out.cousins[key] = copyList(g.cousins, key)
        if g.edge_kind[key] then
            for parent, kind in pairs(g.edge_kind[key]) do
                if allowed[parent] then
                    out.edge_kind[key] = out.edge_kind[key] or {}
                    out.edge_kind[key][parent] = kind
                end
            end
        end
    end
    return out
end

local function focusFamilyGraph(g, focus, depth)
    if not g.canon[focus] then return g end
    local allowed = { [focus] = true }
    local frontier = { focus }
    for _step = 1, depth do
        local nextf = {}
        for _i, key in ipairs(frontier) do
            for _j, list in ipairs({ g.parents[key] or {}, g.children[key] or {}, g.partners[key] or {} }) do
                for _k, other in ipairs(list) do
                    if not allowed[other] then
                        allowed[other] = true
                        nextf[#nextf + 1] = other
                    end
                end
            end
        end
        frontier = nextf
        if #frontier == 0 then break end
    end
    local out = filterFamilyGraph(g, allowed)
    out.focus = focus
    return out
end

local function treeDescendants(g, roots, extra)
    local set = {}
    local function inSource(p)
        if set[p] or roots[p] or (extra and extra[p]) then return true end
        if g.parents[p] and #g.parents[p] > 0 then return false end
        for _i, r in ipairs(g.partners[p] or {}) do
            if set[r] or roots[r] then return true end
        end
        return false
    end
    local changed = true
    while changed do
        changed = false
        for _i, c in ipairs(g.order) do
            if not set[c] and not roots[c] then
                local ps = g.parents[c]
                if ps and #ps > 0 then
                    local all = true
                    for _j, p in ipairs(ps) do
                        if not inSource(p) then
                            all = false
                            break
                        end
                    end
                    if all then
                        set[c] = true
                        changed = true
                    end
                end
            end
        end
    end
    return set
end

local function treePartnerSet(g, key)
    local out = {}
    for _i, q in ipairs(g.partners[key] or {}) do out[q] = true end
    return out
end

local function treeMarriedIn(g, set, protected)
    local extra = {}
    for key in pairs(set) do
        for _i, q in ipairs(g.partners[key] or {}) do
            if not set[q] and not protected[q] and not extra[q] and not (g.parents[q] and #g.parents[q] > 0) then
                local ok = true
                for _j, r in ipairs(g.partners[q] or {}) do
                    if not set[r] and r ~= q then ok = false end
                end
                for _j, c in ipairs(g.children[q] or {}) do
                    if not set[c] then ok = false end
                end
                if ok then extra[q] = true end
            end
        end
    end
    for key in pairs(extra) do set[key] = true end
    return set
end

local function collapseFamilyGraph(g, hidden_down, hidden_up)
    local hidden, counts = {}, {}
    local function count(set)
        local n = 0
        for _k in pairs(set) do n = n + 1 end
        return n
    end
    for key in pairs(hidden_down) do
        if g.canon[key] then
            local roots = { [key] = true }
            local protected = { [key] = true }
            for _i, q in ipairs(g.partners[key] or {}) do protected[q] = true end
            local set = treeMarriedIn(g, treeDescendants(g, roots, treePartnerSet(g, key)), protected)
            counts[key] = counts[key] or { down = 0, up = 0 }
            counts[key].down = count(set)
            for k in pairs(set) do hidden[k] = true end
        end
    end
    for key in pairs(hidden_up) do
        if g.canon[key] then
            local ancestors, frontier = {}, { key }
            while #frontier > 0 do
                local nextf = {}
                for _i, k in ipairs(frontier) do
                    for _j, p in ipairs(g.parents[k] or {}) do
                        if not ancestors[p] and p ~= key then
                            ancestors[p] = true
                            nextf[#nextf + 1] = p
                        end
                    end
                end
                frontier = nextf
            end
            local protected = { [key] = true }
            local own = treeDescendants(g, { [key] = true }, treePartnerSet(g, key))
            for k in pairs(own) do protected[k] = true end
            for _i, q in ipairs(g.partners[key] or {}) do protected[q] = true end
            for k in pairs(own) do
                for _i, q in ipairs(g.partners[k] or {}) do protected[q] = true end
            end
            local set = {}
            for k in pairs(ancestors) do set[k] = true end
            for k in pairs(treeDescendants(g, ancestors)) do set[k] = true end
            for k in pairs(protected) do set[k] = nil end
            set = treeMarriedIn(g, set, protected)
            counts[key] = counts[key] or { down = 0, up = 0 }
            counts[key].up = count(set)
            for k in pairs(set) do hidden[k] = true end
        end
    end
    if next(hidden) == nil then
        g.hidden_counts = nil
        return g
    end
    local allowed = {}
    for _i, key in ipairs(g.order) do
        if not hidden[key] then allowed[key] = true end
    end
    local visible_counts = {}
    for key, c in pairs(counts) do
        if allowed[key] and (c.down > 0 or c.up > 0) then visible_counts[key] = c end
    end
    g.hidden_counts = visible_counts
    return filterFamilyGraph(g, allowed)
end

local function treeGreats(count, base)
    if count <= 0 then return base end
    if count <= 2 then return _("Great-") .. string.rep(_("great-"), count - 1) .. base:lower() end
    return T(_("%1× great-%2"), count, base:lower())
end

local TREE_INVERSE_LABELS = {
    father = _("Child"), mother = _("Child"), parent = _("Child"),
    son = _("Parent"), daughter = _("Parent"), child = _("Parent"),
    brother = _("Sibling"), sister = _("Sibling"), sibling = _("Sibling"),
    spouse = _("Spouse"), partner = _("Partner"), lover = _("Lover"), ex = _("Ex-partner"),
    cousin = _("Cousin"),
    adoptive_parent = _("Adopted child"), adopted_child = _("Adoptive parent"),
    guardian = _("Ward"), ward = _("Guardian"),
    step_parent = _("Step-child"), step_child = _("Step-parent"),
    foster_parent = _("Foster child"), foster_child = _("Foster parent"),
}

local TREE_PATH_PARTNER = {
    married = _("Spouse"), partners = _("Partner"), casual = _("Partner"), former = _("Ex-partner"),
}

local function treeSharesParent(g, p, q)
    for _i, a in ipairs(g.parents[p] or {}) do
        for _j, b in ipairs(g.parents[q] or {}) do
            if a == b then return true end
        end
    end
    return false
end

local function treeIsDoubleCousin(g, focus, key)
    local mine, theirs = g.parents[focus] or {}, g.parents[key] or {}
    if #mine < 2 or #theirs < 2 then return false end
    local used_mine, used_theirs, matches = {}, {}, 0
    for _i, p in ipairs(mine) do
        for _j, q in ipairs(theirs) do
            if not used_mine[p] and not used_theirs[q] and treeSharesParent(g, p, q) then
                used_mine[p] = true
                used_theirs[q] = true
                matches = matches + 1
            end
        end
    end
    return matches >= 2
end

local function treePathLabel(g, focus, key, path)
    local n = #path
    if path:match("^U+$") then
        if n == 1 then
            local kind = g.edge_kind[focus] and g.edge_kind[focus][key]
            if kind == "adopted" then return _("Adoptive parent") end
            if kind == "guardian" then return _("Guardian") end
            if kind == "step" then return _("Step-parent") end
            if kind == "foster" then return _("Foster parent") end
            return _("Parent")
        end
        return treeGreats(n - 2, _("Grandparent"))
    end
    if path:match("^D+$") then
        if n == 1 then
            local kind = g.edge_kind[key] and g.edge_kind[key][focus]
            if kind == "adopted" then return _("Adopted child") end
            if kind == "guardian" then return _("Ward") end
            if kind == "step" then return _("Step-child") end
            if kind == "foster" then return _("Foster child") end
            return _("Child")
        end
        return treeGreats(n - 2, _("Grandchild"))
    end
    local ups, downs = path:match("^(U+)(D+)$")
    if ups then
        local a, b = #ups, #downs
        if a == 1 and b == 1 then
            local mine, theirs = g.parents[focus] or {}, g.parents[key] or {}
            local shared_any, shared_bio = false, false
            for _i, p in ipairs(mine) do
                for _j, q in ipairs(theirs) do
                    if p == q then
                        shared_any = true
                        local step = (g.edge_kind[focus] and g.edge_kind[focus][p] == "step")
                            or (g.edge_kind[key] and g.edge_kind[key][p] == "step")
                        if not step then shared_bio = true end
                    end
                end
            end
            if shared_any and not shared_bio then return _("Step-sibling") end
            if #mine >= 2 and #theirs >= 2 then
                local shared = 0
                for _i, p in ipairs(mine) do
                    for _j, q in ipairs(theirs) do
                        if p == q then shared = shared + 1 end
                    end
                end
                if shared < #mine or shared < #theirs then return _("Half-sibling") end
            end
            return _("Sibling")
        end
        if b == 1 then return treeGreats(a - 2, _("Aunt/uncle")) end
        if a == 1 then
            if b == 2 then return _("Niece/nephew") end
            if b == 3 then return _("Grand-niece/nephew") end
            return T(_("%1× grand-niece/nephew"), b - 2)
        end
        if a == 2 and b == 2 and treeIsDoubleCousin(g, focus, key) then
            return _("Double cousin")
        end
        local degree = math.min(a, b) - 1
        local removed = math.abs(a - b)
        local label
        if degree == 1 then
            label = _("Cousin")
        elseif degree == 2 then
            label = _("Second cousin")
        elseif degree == 3 then
            label = _("Third cousin")
        else
            label = T(_("%1th cousin"), degree)
        end
        if removed == 1 then
            label = label .. _(", once removed")
        elseif removed == 2 then
            label = label .. _(", twice removed")
        elseif removed > 2 then
            label = label .. T(_(", %1 times removed"), removed)
        end
        return label
    end
    if path == "PU" then return _("Parent-in-law") end
    if path == "DP" then return _("Child-in-law") end
    if path == "UP" then return _("Step-parent") end
    if path == "PD" then return _("Step-child") end
    if path == "PUD" or path == "UDP" then return _("Sibling-in-law") end
    if path == "UPD" then return _("Step-sibling") end
    if path == "UUDP" then return _("Aunt/uncle by marriage") end
    if path == "PUU" then return _("Grandparent-in-law") end
    return nil
end

local TREE_GENDER_EXACT = {}
local TREE_GENDER_WORDS = {
    { "grandparent", "grandfather", "grandmother" },
    { "grandchild", "grandson", "granddaughter" },
    { "aunt/uncle", "uncle", "aunt" },
    { "niece/nephew", "nephew", "niece" },
}
for _i, row in ipairs({
    { _("Parent"), _("Father"), _("Mother") },
    { _("Child"), _("Son"), _("Daughter") },
    { _("Sibling"), _("Brother"), _("Sister") },
    { _("Spouse"), _("Husband"), _("Wife") },
    { _("Adoptive parent"), _("Adoptive father"), _("Adoptive mother") },
    { _("Adopted child"), _("Adopted son"), _("Adopted daughter") },
    { _("Step-parent"), _("Stepfather"), _("Stepmother") },
    { _("Step-child"), _("Stepson"), _("Stepdaughter") },
    { _("Foster parent"), _("Foster father"), _("Foster mother") },
    { _("Foster child"), _("Foster son"), _("Foster daughter") },
    { _("Grandparent"), _("Grandfather"), _("Grandmother") },
    { _("Grandchild"), _("Grandson"), _("Granddaughter") },
    { _("Half-sibling"), _("Half-brother"), _("Half-sister") },
    { _("Aunt/uncle"), _("Uncle"), _("Aunt") },
    { _("Niece/nephew"), _("Nephew"), _("Niece") },
    { _("Grand-niece/nephew"), _("Grand-nephew"), _("Grand-niece") },
    { _("Parent-in-law"), _("Father-in-law"), _("Mother-in-law") },
    { _("Child-in-law"), _("Son-in-law"), _("Daughter-in-law") },
    { _("Sibling-in-law"), _("Brother-in-law"), _("Sister-in-law") },
    { _("Step-sibling"), _("Stepbrother"), _("Stepsister") },
    { _("Aunt/uncle by marriage"), _("Uncle by marriage"), _("Aunt by marriage") },
    { _("Grandparent-in-law"), _("Grandfather-in-law"), _("Grandmother-in-law") },
}) do
    TREE_GENDER_EXACT[row[1]] = { male = row[2], female = row[3] }
end

local function treeGenderize(label, gender)
    if not label or (gender ~= "male" and gender ~= "female") then return label end
    local exact = TREE_GENDER_EXACT[label]
    if exact then return exact[gender] end
    for _i, word in ipairs(TREE_GENDER_WORDS) do
        local start, finish = label:find(word[1], 1, true)
        if start then
            return label:sub(1, start - 1) .. (gender == "male" and word[2] or word[3]) .. label:sub(finish + 1)
        end
    end
    return label
end

local function treeRelationLabels(g, vf, focus)
    local path = { [focus] = "" }
    local queue, head = { focus }, 1
    while head <= #queue do
        local cur = queue[head]
        head = head + 1
        local p = path[cur]
        if #p < 8 then
            for _i, step in ipairs({ { g.parents, "U" }, { g.children, "D" }, { g.partners, "P" } }) do
                for _j, other in ipairs(step[1][cur] or {}) do
                    if path[other] == nil then
                        path[other] = p .. step[2]
                        queue[#queue + 1] = other
                    end
                end
            end
        end
    end
    local direct, other_direct = {}, {}
    local known_types = {}
    for _i, rt in ipairs(RELATIONSHIP_TYPES) do known_types[rt.key] = true end
    for _i, rel in ipairs(vf.relations or {}) do
        local from, to = lowerOrEmpty(rel.from), lowerOrEmpty(rel.to)
        if rel.type and rel.type ~= "" then
            local custom = not known_types[rel.type]
            local target = direct
            if not custom and not TREE_INVERSE_LABELS[rel.type] then target = other_direct end
            local forward, reverse = getRelationshipLabel(rel.type), TREE_INVERSE_LABELS[rel.type] or getRelationshipLabel(rel.type)
            if custom then
                local a, b = rel.type:match("^(.-)%s*/%s*(.-)$")
                if a and a ~= "" then
                    forward = a
                    reverse = b ~= "" and b or a
                end
            end
            if from == focus then
                target[to] = target[to] or forward
            elseif to == focus then
                target[from] = target[from] or reverse
            end
        end
    end
    local labels = {}
    for key, p in pairs(path) do
        if key ~= focus then
            local label = direct[key]
            if not label and p == "P" then
                label = TREE_PATH_PARTNER[g.explicit[coupleKey(focus, key)] or ""] or _("Partner")
            end
            labels[key] = label or treePathLabel(g, focus, key, p) or other_direct[key]
        end
    end
    for _i, source in ipairs({ direct, other_direct }) do
        for key, label in pairs(source) do
            if key ~= focus and not labels[key] and g.canon[key] then labels[key] = label end
        end
    end
    for key, label in pairs(labels) do
        labels[key] = treeGenderize(label, g.gender and g.gender[key])
    end
    return labels
end

local function treeNameParts(member)
    local first = trim(member.first_name or "")
    local last = trim(member.last_name or "")
    if first == "" and last == "" then
        local name = trim(member.name or "")
        local head, tail = name:match("^(.*)%s+(%S+)$")
        if head then return head, tail end
        return name, ""
    end
    return first, last
end

local function freeTreeLayout(L)
    for _i, node in ipairs(L.nodes) do
        for _j, line in ipairs(node.name_lines) do line.tw:free() end
        for _j, tw in ipairs(node.infos) do tw:free() end
    end
end

local function layoutFamilyTree(family, g, scale)
    local function px(v)
        return math.max(1, math.floor(v * scale + 0.5))
    end
    local gray = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK
    local sizes = family.tree_sizes or TREE_FONT_DEFAULTS
    local name_face = Font:getFace("cfont", px(sizes.first))
    local last_face = Font:getFace("cfont", px(sizes.last))
    local info_face = Font:getFace("cfont", px(sizes.info))
    local pad = px(10)
    local couple_gap = px(80)
    local sibling_gap = px(36)
    local root_gap = px(70)
    local v_gap = px(96)
    local margin = px(40)
    local underline_t = px(2)

    local nodes, by_key = {}, {}
    local order_index = {}
    local max_h = 0
    local name_block_h = 0
    for i, key in ipairs(g.order) do
        order_index[key] = i
        local member = g.plain[key] and memberByName(family, g.canon[key]) or nil
        local node = { key = key, infos = {}, name_lines = {}, placeholder = not g.plain[key] }
        local first, last = g.canon[key], ""
        if member then first, last = treeNameParts(member) end
        local name_color = node.placeholder and gray or Blitbuffer.COLOR_BLACK
        if first ~= "" then
            table.insert(node.name_lines, {
                tw = TextWidget:new{ text = first, face = name_face, fgcolor = name_color },
            })
        end
        if last ~= "" then
            table.insert(node.name_lines, {
                tw = TextWidget:new{ text = last, face = last_face, fgcolor = name_color },
            })
        end
        local texts = {}
        if g.relation_labels and g.relation_labels[key] then
            texts[#texts + 1] = g.relation_labels[key]
        end
        if member and member.title and member.title ~= "" then
            texts[#texts + 1] = member.title
        end
        if member and member.role and member.role ~= "" then
            texts[#texts + 1] = member.role
        end
        if family.guest_of and family.guest_of[key] then
            texts[#texts + 1] = family.guest_of[key]
        end
        if g.cousins[key] then
            local names, seen = {}, {}
            for _j, c in ipairs(g.cousins[key]) do
                if not seen[c] then
                    seen[c] = true
                    names[#names + 1] = g.canon[c]
                end
            end
            texts[#texts + 1] = "~ " .. _("cousin of") .. " " .. table.concat(names, ", ")
        end
        local hidden = g.hidden_counts and g.hidden_counts[key]
        if hidden then
            texts[#texts + 1] = T(_("(+%1 hidden)"), hidden.down + hidden.up)
        end
        local widest, name_h = 0, 0
        for _j, line in ipairs(node.name_lines) do
            local size = line.tw:getSize()
            line.h = size.h
            if size.w > widest then widest = size.w end
            name_h = name_h + size.h
        end
        node.name_w = widest
        node.name_h = name_h
        if name_h > name_block_h then name_block_h = name_h end
        local info_h = 0
        for _j, text in ipairs(texts) do
            local tw = TextWidget:new{ text = text, face = info_face, fgcolor = gray }
            local size = tw:getSize()
            if size.w > widest then widest = size.w end
            info_h = info_h + size.h + px(2)
            table.insert(node.infos, tw)
        end
        node.info_h = info_h
        node.w = widest + 2 * pad
        nodes[#nodes + 1] = node
        by_key[key] = node
    end
    for _i, node in ipairs(nodes) do
        node.h = pad + name_block_h + px(2) + underline_t + px(5) + node.info_h + pad
        if node.h > max_h then max_h = node.h end
    end

    local function has_parents(k)
        return g.parents[k] and #g.parents[k] > 0
    end
    local adj = {}
    for _i, a in ipairs(g.order) do
        for _j, b in ipairs(g.partners[a] or {}) do
            if order_index[a] < order_index[b] and (not has_parents(a) or not has_parents(b)) then
                adj[a] = adj[a] or {}
                adj[b] = adj[b] or {}
                table.insert(adj[a], b)
                table.insert(adj[b], a)
            end
        end
    end

    local chains, chain_of = {}, {}
    local function newChain(members)
        local chain = { members = members, pos = {}, first = math.huge, level = 0 }
        for i, k in ipairs(members) do
            chain.pos[k] = i
            chain_of[k] = chain
            if order_index[k] < chain.first then chain.first = order_index[k] end
        end
        table.insert(chains, chain)
    end
    local seen_comp = {}
    for _i, key in ipairs(g.order) do
        if not seen_comp[key] then
            local comp, stack = {}, { key }
            seen_comp[key] = true
            while #stack > 0 do
                local cur = table.remove(stack)
                comp[#comp + 1] = cur
                for _j, nb in ipairs(adj[cur] or {}) do
                    if not seen_comp[nb] then
                        seen_comp[nb] = true
                        stack[#stack + 1] = nb
                    end
                end
            end
            table.sort(comp, function(x, y) return order_index[x] < order_index[y] end)
            local start = comp[1]
            for _j, k in ipairs(comp) do
                if #(adj[k] or {}) < #(adj[start] or {}) then start = k end
            end
            local used = { [start] = true }
            local path = { start }
            local cur = start
            while true do
                local nxt
                for _j, nb in ipairs(adj[cur] or {}) do
                    if not used[nb] then
                        nxt = nb
                        break
                    end
                end
                if not nxt then break end
                used[nxt] = true
                path[#path + 1] = nxt
                cur = nxt
            end
            newChain(path)
            for _j, k in ipairs(comp) do
                if not used[k] then newChain({ k }) end
            end
        end
    end
    table.sort(chains, function(x, y) return x.first < y.first end)

    local level = {}
    for _i, k in ipairs(g.order) do level[k] = 0 end
    local cap = #g.order
    for _pass = 1, cap + 2 do
        local changed = false
        for _i, c in ipairs(g.order) do
            for _j, p in ipairs(g.parents[c] or {}) do
                if level[c] < level[p] + 1 and level[p] < cap then
                    level[c] = level[p] + 1
                    changed = true
                end
            end
        end
        for _i, chain in ipairs(chains) do
            local lv = 0
            for _j, k in ipairs(chain.members) do
                if level[k] > lv then lv = level[k] end
            end
            for _j, k in ipairs(chain.members) do
                if level[k] ~= lv then
                    level[k] = lv
                    changed = true
                end
            end
            chain.level = lv
        end
        if not changed then break end
    end

    local kids = {}
    for _i, B in ipairs(chains) do
        for _j, m in ipairs(B.members) do
            if not B.parent_chain then
                for _k, p in ipairs(g.parents[m] or {}) do
                    local pc = chain_of[p]
                    if pc and pc ~= B and pc.level < B.level then
                        B.parent_chain = pc
                        break
                    end
                end
            end
        end
        if B.parent_chain then
            kids[B.parent_chain] = kids[B.parent_chain] or {}
            table.insert(kids[B.parent_chain], B)
        end
        local w = 0
        for j, k in ipairs(B.members) do
            w = w + by_key[k].w + (j > 1 and couple_gap or 0)
        end
        B.w = w
    end

    local sub_w = {}
    local function measure(B)
        local total = 0
        for i, C in ipairs(kids[B] or {}) do
            measure(C)
            total = total + sub_w[C] + (i > 1 and sibling_gap or 0)
        end
        B.children_total = total
        sub_w[B] = math.max(B.w, total)
    end
    local function place(B, left)
        local x = left + (sub_w[B] - B.w) / 2
        for _i, k in ipairs(B.members) do
            by_key[k].x = x
            x = x + by_key[k].w + couple_gap
        end
        local cx = left + (sub_w[B] - B.children_total) / 2
        for _i, C in ipairs(kids[B] or {}) do
            place(C, cx)
            cx = cx + sub_w[C] + sibling_gap
        end
    end

    local label_w = (family.tree_flags and family.tree_flags.generations) and px(78) or 0
    local cursor = margin + label_w
    local first_root = true
    for _i, B in ipairs(chains) do
        if not B.parent_chain then
            measure(B)
            if not first_root then cursor = cursor + root_gap end
            first_root = false
            place(B, cursor)
            cursor = cursor + sub_w[B]
        end
    end

    local content_h = 0
    for _i, node in ipairs(nodes) do
        node.h = max_h
        node.y = margin + level[node.key] * (max_h + v_gap)
        node.x = node.x or margin
        if node.y + max_h + margin > content_h then content_h = node.y + max_h + margin end
    end

    return {
        g = g, nodes = nodes, by_key = by_key, chains = chains, chain_of = chain_of,
        px = px, pad = pad, name_block_h = name_block_h, couple_gap = couple_gap, v_gap = v_gap, gray = gray,
        underline_t = underline_t, content_w = cursor + margin, content_h = content_h,
        scale = scale, level = level, info_face = info_face, margin = margin,
        show_generations = label_w > 0, max_h = max_h,
    }
end

local function treeKindStyle(kind)
    if kind == "adopted" or kind == "foster" then return "casual" end
    if kind == "guardian" or kind == "step" then return "former" end
    return nil
end

local function drawFamilyTree(L, style_of, canvas_w, canvas_h, hide_underline)
    local g = L.g
    local bb_w = math.max(L.content_w, canvas_w)
    local bb_h = math.max(L.content_h, canvas_h)
    local bb_type = Screen.bb and Screen.bb:getType() or Blitbuffer.TYPE_BB8
    local bb = Blitbuffer.new(bb_w, bb_h, bb_type)
    bb:fill(Blitbuffer.COLOR_WHITE)
    local ox = math.floor((bb_w - L.content_w) / 2)
    local oy = math.floor((bb_h - L.content_h) / 2)
    local t = L.px(2)
    local black = Blitbuffer.COLOR_BLACK

    local function rect(x, y, w, h, color)
        bb:paintRect(math.floor(x + ox), math.floor(y + oy), math.max(1, math.floor(w)), math.max(1, math.floor(h)), color or black)
    end

    local persons, lines = {}, {}
    local function addLine(x1, y1, x2, y2, info)
        if x1 > x2 then x1, x2 = x2, x1 end
        if y1 > y2 then y1, y2 = y2, y1 end
        lines[#lines + 1] = { x1 = x1 + ox, y1 = y1 + oy, x2 = x2 + ox, y2 = y2 + oy, info = info }
    end
    local function dashed(x1, x2, y, dash, gap, color)
        local x = x1
        while x < x2 do
            rect(x, y - t / 2, math.min(dash, x2 - x), t, color)
            x = x + dash + gap
        end
    end
    local function vdashed(x, y1, y2, dash, gap)
        local y = y1
        while y < y2 do
            rect(x - t / 2, y, t, math.min(dash, y2 - y))
            y = y + dash + gap
        end
    end
    local function hline(x1, x2, y, style)
        style = coupleBaseStyle(style)
        if style == "none" then return end
        if style == "married" then
            rect(x1, y - t * 1.5, x2 - x1, t)
            rect(x1, y + t * 0.5, x2 - x1, t)
        elseif style == "casual" then
            dashed(x1, x2, y, L.px(11), L.px(8))
        elseif style == "former" then
            dashed(x1, x2, y, t, L.px(6))
        else
            rect(x1, y - t / 2, x2 - x1, t)
        end
    end
    local function vline(x, y1, y2, info, style)
        if y1 > y2 then y1, y2 = y2, y1 end
        if style == "casual" then
            vdashed(x, y1, y2, L.px(10), L.px(7))
        elseif style == "former" then
            vdashed(x, y1, y2, t, L.px(6))
        else
            rect(x - t / 2, y1, t, y2 - y1 + t)
        end
        addLine(x, y1, x, y2, info)
    end
    local function y_link(node)
        return node.y + L.pad + L.name_block_h / 2
    end

    local sym_face = Font:getFace("cfont", L.px(20))
    local function marriage_symbol(style, cx, y, centered)
        style = coupleBaseStyle(style)
        if style ~= "married" and style ~= "partners" then return end
        local tw = TextWidget:new{ text = "⚭", face = sym_face }
        local size = tw:getSize()
        local sy = centered and (y - size.h / 2) or (y - size.h - t * 2)
        if centered then
            rect(cx - size.w / 2 - 3, sy, size.w + 6, size.h, Blitbuffer.COLOR_WHITE)
        end
        tw:paintTo(bb, math.floor(cx - size.w / 2 + ox), math.floor(sy + oy))
        tw:free()
    end

    local focus_node = g.focus and L.by_key[g.focus]

    for _i, node in ipairs(L.nodes) do
        local ny = node.y + L.pad + (L.name_block_h - node.name_h)
        for _j, line in ipairs(node.name_lines) do
            local size = line.tw:getSize()
            line.tw:paintTo(bb, math.floor(node.x + (node.w - size.w) / 2 + ox), math.floor(ny + oy))
            ny = ny + line.h
        end
        local uy = node.y + L.pad + L.name_block_h + L.px(2)
        local uw = node.name_w + L.px(14)
        local ux = node.x + (node.w - uw) / 2
        if hide_underline then
        elseif node.placeholder then
            dashed(ux, ux + uw, uy + t / 2, L.px(7), L.px(5), L.gray)
        else
            rect(ux, uy, uw, t)
        end
        local iy = uy + t + L.px(5)
        for _j, tw in ipairs(node.infos) do
            local size = tw:getSize()
            tw:paintTo(bb, math.floor(node.x + (node.w - size.w) / 2 + ox), math.floor(iy + oy))
            iy = iy + size.h + L.px(2)
        end
        persons[#persons + 1] = { x = node.x + ox, y = node.y + oy, w = node.w, h = node.h, key = node.key }
    end

    if focus_node then
        local m = L.px(3)
        rect(focus_node.x - m, focus_node.y - m, focus_node.w + 2 * m, t, L.gray)
        rect(focus_node.x - m, focus_node.y + focus_node.h + m - t, focus_node.w + 2 * m, t, L.gray)
        rect(focus_node.x - m, focus_node.y - m, t, focus_node.h + 2 * m, L.gray)
        rect(focus_node.x + focus_node.w + m - t, focus_node.y - m, t, focus_node.h + 2 * m, L.gray)
    end

    if L.show_generations then
        local seen, ranks = {}, {}
        for _i, node in ipairs(L.nodes) do
            local lv = L.level[node.key]
            if not seen[lv] then
                seen[lv] = true
                ranks[#ranks + 1] = lv
            end
        end
        table.sort(ranks)
        for index, lv in ipairs(ranks) do
            local tw = TextWidget:new{ text = T(_("Gen %1"), index), face = L.info_face, fgcolor = L.gray }
            local size = tw:getSize()
            local row_y = L.margin + lv * (L.max_h + L.v_gap) + L.pad + L.name_block_h / 2
            tw:paintTo(bb, math.floor(L.margin / 2 + ox), math.floor(row_y - size.h / 2 + oy))
            tw:free()
        end
    end

    local drawn_pair = {}
    local used = {}
    for _i, chain in ipairs(L.chains) do
        for j = 1, #chain.members - 1 do
            local a, b = L.by_key[chain.members[j]], L.by_key[chain.members[j + 1]]
            local y = y_link(a)
            local link_style = style_of(a.key, b.key)
            if link_style ~= "none" then used[link_style] = true end
            hline(a.x + a.w, b.x, y, link_style)
            marriage_symbol(link_style, (a.x + a.w + b.x) / 2, y, false)
            addLine(a.x + a.w, y, b.x, y, { kind = "couple", a = a.key, b = b.key })
            drawn_pair[coupleKey(a.key, b.key)] = true
        end
    end

    local group_map, groups = {}, {}
    for _i, c in ipairs(g.order) do
        local ps = g.parents[c]
        if ps and #ps > 0 then
            local by_kind, kind_order = {}, {}
            for _j, p in ipairs(ps) do
                local kind = g.edge_kind[c] and g.edge_kind[c][p] or "bio"
                if not by_kind[kind] then
                    by_kind[kind] = {}
                    kind_order[#kind_order + 1] = kind
                end
                table.insert(by_kind[kind], p)
            end
            for _j, kind in ipairs(kind_order) do
                local ids = by_kind[kind]
                table.sort(ids)
                local gk = kind .. "\2" .. table.concat(ids, "\1")
                if not group_map[gk] then
                    group_map[gk] = { parents = ids, children = {}, kind = kind ~= "bio" and kind or nil }
                    groups[#groups + 1] = group_map[gk]
                end
                table.insert(group_map[gk].children, c)
            end
        end
    end

    for _i, grp in ipairs(groups) do
        local pn = {}
        local p_bottom = 0
        for _j, p in ipairs(grp.parents) do
            local n = L.by_key[p]
            pn[#pn + 1] = n
            if n.y + n.h > p_bottom then p_bottom = n.y + n.h end
        end
        local c_top = math.huge
        for _j, c in ipairs(grp.children) do
            local n = L.by_key[c]
            if n.y < c_top then c_top = n.y end
        end
        local bus_y
        if c_top > p_bottom then
            bus_y = math.floor((p_bottom + c_top) / 2)
            if grp.kind and c_top - p_bottom > L.px(40) then
                bus_y = math.min(bus_y + L.px(12), math.floor(c_top - L.px(10)))
            end
        else
            bus_y = math.floor(p_bottom + L.v_gap / 2)
        end
        local vs = treeKindStyle(grp.kind)
        if vs == "casual" then used.child_dashed = true elseif vs == "former" then used.child_dotted = true end
        local info = { kind = "group", parents = grp.parents, children = grp.children, rel_kind = grp.kind }
        local xs = {}
        local anchored = false
        if #pn == 2 then
            local a, b = pn[1], pn[2]
            if a.x > b.x then a, b = b, a end
            local chain = L.chain_of[a.key]
            if chain == L.chain_of[b.key] and style_of(a.key, b.key) ~= "none"
               and math.abs(chain.pos[a.key] - chain.pos[b.key]) == 1 then
                anchored = true
                local gx = a.x + a.w + L.couple_gap / 2
                vline(gx, y_link(a), bus_y, info, vs)
                xs[#xs + 1] = gx
            end
        end
        local joined = false
        if not anchored and #pn == 2 then
            local a, b = pn[1], pn[2]
            if a.x > b.x then a, b = b, a end
            local style = style_of(a.key, b.key)
            if style ~= "none" then
                used[style] = true
                joined = true
                local ax, bx = a.x + a.w / 2, b.x + b.w / 2
                local join_y = math.floor(p_bottom + (bus_y - p_bottom) * 0.45)
                local pair_info = { kind = "couple", a = a.key, b = b.key }
                vline(ax, a.y + a.h, join_y, pair_info, vs)
                vline(bx, b.y + b.h, join_y, pair_info, vs)
                hline(ax, bx, join_y, style)
                marriage_symbol(style, (ax + bx) / 2, join_y, false)
                addLine(ax, join_y, bx, join_y, pair_info)
                drawn_pair[coupleKey(a.key, b.key)] = true
                local mx = (ax + bx) / 2
                vline(mx, join_y, bus_y, info, vs)
                xs[#xs + 1] = mx
            end
        end
        if not anchored and not joined then
            for _j, n in ipairs(pn) do
                local cxp = n.x + n.w / 2
                vline(cxp, n.y + n.h, bus_y, info, vs)
                xs[#xs + 1] = cxp
            end
        end
        for _j, c in ipairs(grp.children) do
            local n = L.by_key[c]
            local cxc = n.x + n.w / 2
            vline(cxc, bus_y, n.y, { kind = "child", parents = grp.parents, child = c, rel_kind = grp.kind }, vs)
            xs[#xs + 1] = cxc
        end
        local lo, hi = math.huge, -math.huge
        for _j, x in ipairs(xs) do
            if x < lo then lo = x end
            if x > hi then hi = x end
        end
        if hi > lo then
            if vs then
                hline(lo - t / 2, hi + t / 2, bus_y, vs)
            else
                rect(lo - t / 2, bus_y - t / 2, hi - lo + t, t)
            end
            addLine(lo, bus_y, hi, bus_y, info)
        end
    end

    local bracket_count = {}
    for _i, a in ipairs(g.order) do
        for _j, b in ipairs(g.partners[a] or {}) do
            local pair = coupleKey(a, b)
            if a < b and not drawn_pair[pair] and L.by_key[a] and L.by_key[b] then
                drawn_pair[pair] = true
                local style = style_of(a, b)
                if style ~= "none" then
                    used[style] = true
                    local na, nb = L.by_key[a], L.by_key[b]
                    if na.x > nb.x then na, nb = nb, na end
                    local row = math.floor(math.max(na.y + na.h, nb.y + nb.h))
                    bracket_count[row] = (bracket_count[row] or 0) + 1
                    local by = row + L.px(8) * bracket_count[row] + L.px(4)
                    local ax, bx = na.x + na.w / 2, nb.x + nb.w / 2
                    local pair_info = { kind = "couple", a = a, b = b }
                    vline(ax, na.y + na.h, by, pair_info)
                    vline(bx, nb.y + nb.h, by, pair_info)
                    hline(ax, bx, by, style)
                    marriage_symbol(style, (ax + bx) / 2, by, false)
                    addLine(ax, by, bx, by, pair_info)
                end
            end
        end
    end

    freeTreeLayout(L)
    for key, _flag in pairs(used) do
        local base, name = parseCustomCouple(key)
        if base then
            local visual = "solid"
            for _i, st in ipairs(COUPLE_STYLES) do
                if st.key == base then visual = st.visual end
            end
            used[key] = { visual = visual, meaning = name }
        end
    end
    return { bb = bb, w = bb_w, h = bb_h, persons = persons, lines = lines, scale = L.scale, legend = used }
end

local function renderFamilyTree(family, g, request_scale, canvas_w, canvas_h, style_of, hide_underline)
    local scale = request_scale
    local L
    if not scale then
        L = layoutFamilyTree(family, g, 1)
        if L.content_w > canvas_w then
            scale = math.max(0.45, math.floor(canvas_w / L.content_w * 20) / 20)
            freeTreeLayout(L)
            L = nil
        else
            scale = 1
        end
    end
    for _attempt = 1, 6 do
        L = L or layoutFamilyTree(family, g, scale)
        if L.content_w * L.content_h <= TREE_MAX_PIXELS or scale <= 0.45 then break end
        freeTreeLayout(L)
        L = nil
        scale = math.max(0.45, scale * 0.8)
    end
    L = L or layoutFamilyTree(family, g, scale)
    local result = drawFamilyTree(L, style_of, canvas_w, canvas_h, hide_underline)
    result.scale = scale
    return result
end

local function socialEdgePoint(node, tx, ty)
    local cx, cy = node.x + node.w / 2, node.y + node.h / 2
    local dx, dy = tx - cx, ty - cy
    if dx == 0 and dy == 0 then return cx, cy end
    local hw, hh = node.w / 2 + 6, node.h / 2 + 6
    local sx = dx ~= 0 and hw / math.abs(dx) or math.huge
    local sy = dy ~= 0 and hh / math.abs(dy) or math.huge
    local s = math.min(sx, sy)
    return cx + dx * s, cy + dy * s
end

local function drawTreeSegment(bb, x1, y1, x2, y2, style, thick, color, unit)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then return end
    local ux, uy = dx / len, dy / len
    local px, py = -uy, ux
    local dash_dot = unit * 14 + unit * 8 + thick + unit * 8
    local function run(offset)
        local pattern_on, pattern_off
        if style == "dashed" then
            pattern_on, pattern_off = unit * 14, unit * 10
        elseif style == "dotted" then
            pattern_on, pattern_off = thick, unit * 9
        end
        local line_thick = style == "thick" and thick * 2 or thick
        if style == "thin" then line_thick = math.max(1, math.floor(thick / 2)) end
        local d = 0
        local step = math.max(1, math.floor(line_thick / 2))
        while d <= len do
            local draw = true
            if pattern_on then
                draw = (d % (pattern_on + pattern_off)) < pattern_on
            elseif style == "dashdot" then
                local m = d % dash_dot
                draw = m < unit * 14 or (m >= unit * 22 and m < unit * 22 + thick)
            end
            if draw then
                local o = offset
                if style == "wavy" then o = offset + math.sin(d / (unit * 4)) * thick * 1.6 end
                local x, y = x1 + ux * d + px * o, y1 + uy * d + py * o
                bb:paintRect(math.floor(x - line_thick / 2), math.floor(y - line_thick / 2), line_thick, line_thick, color)
            end
            d = d + step
        end
    end
    if style == "double" then
        run(-thick)
        run(thick)
    else
        run(0)
    end
end

local SOCIAL_GRID_X, SOCIAL_GRID_Y = 190, 110

local function drawArrowHead(bb, tx, ty, ux, uy, size, color)
    local nx, ny = -uy, ux
    local base_x, base_y = tx - ux * size, ty - uy * size
    local half = size * 0.45
    local steps = math.max(2, math.floor(half))
    for i = -steps, steps do
        local f = i / steps
        drawTreeSegment(bb, tx, ty, base_x + nx * half * f, base_y + ny * half * f, "solid", 2, color, 1)
    end
end

local function renderSocialTree(vf, ties, g, request_scale, canvas_w, canvas_h, hide_underline, family_graph, member_groups, show_labels, positions, grid)
    local scale = request_scale
    local L
    local function place(sc)
        local layout = layoutFamilyTree(vf, g, sc)
        local nodes = layout.nodes
        local count = #nodes
        local parent_of = {}
        local function find(k)
            while parent_of[k] and parent_of[k] ~= k do k = parent_of[k] end
            return k
        end
        for _i, node in ipairs(nodes) do parent_of[node.key] = node.key end
        for _i, tie in ipairs(ties) do
            if tie.pull and parent_of[tie.a] and parent_of[tie.b] then
                local ra, rb = find(tie.a), find(tie.b)
                if ra ~= rb then parent_of[rb] = ra end
            end
        end
        for _i, set in ipairs(member_groups or {}) do
            for k = 2, #set do
                if parent_of[set[1]] and parent_of[set[k]] then
                    local ra, rb = find(set[1]), find(set[k])
                    if ra ~= rb then parent_of[rb] = ra end
                end
            end
        end
        local groups, group_order = {}, {}
        for _i, node in ipairs(nodes) do
            local root = find(node.key)
            if not groups[root] then
                groups[root] = {}
                group_order[#group_order + 1] = root
            end
            table.insert(groups[root], node)
        end
        table.sort(group_order, function(a, b)
            if #groups[a] ~= #groups[b] then return #groups[a] > #groups[b] end
            return a < b
        end)
        local ordered = {}
        for _i, root in ipairs(group_order) do
            for _j, node in ipairs(groups[root]) do ordered[#ordered + 1] = node end
        end
        local margin = layout.margin
        local max_w, max_h, perimeter = 0, 0, 0
        for _i, node in ipairs(nodes) do
            if node.w > max_w then max_w = node.w end
            if node.h > max_h then max_h = node.h end
            perimeter = perimeter + math.max(node.w, node.h) + layout.px(34)
        end
        local radius = count > 1 and math.max(layout.px(140), perimeter / (2 * math.pi)) or 0
        local cx = margin + radius + max_w / 2
        local cy = margin + radius + max_h / 2
        for i, node in ipairs(ordered) do
            if count == 1 then
                node.x, node.y = cx - node.w / 2, cy - node.h / 2
            else
                local angle = 2 * math.pi * (i - 1) / count - math.pi / 2
                node.x = cx + radius * math.cos(angle) - node.w / 2
                node.y = cy + radius * math.sin(angle) - node.h / 2
            end
        end
        local pinned = {}
        for _i, node in ipairs(nodes) do
            local spot = positions and positions[node.key]
            if type(spot) == "table" and tonumber(spot.x) and tonumber(spot.y) then
                node.x = cx + spot.x * sc - node.w / 2
                node.y = cy + spot.y * sc - node.h / 2
                pinned[node.key] = true
            end
        end
        local function pairId(ka, kb)
            if ka < kb then return ka .. "|" .. kb end
            return kb .. "|" .. ka
        end
        local tie_need = {}
        local label_face = Font:getFace("cfont", math.max(11, math.floor(14 * sc)))
        for _i, tie in ipairs(ties) do
            if not tie.hidden and parent_of[tie.a] and parent_of[tie.b] then
                local id = pairId(tie.a, tie.b)
                local entry = tie_need[id]
                if not entry then
                    entry = { labels = {} }
                    tie_need[id] = entry
                end
                if show_labels and tie.label then
                    local tw = TextWidget:new{ text = tie.label, face = label_face }
                    local size = tw:getSize()
                    table.insert(entry.labels, { w = size.w + 6, h = size.h + 2 })
                    tw:free()
                else
                    table.insert(entry.labels, { w = 0, h = 0, none = true })
                end
            end
        end
        local base_x, base_y = layout.px(70), layout.px(44)
        local line_spacing = layout.px(48)
        for _iter = 1, 160 do
            local moved = false
            for i = 1, count do
                for j = i + 1, count do
                    local a, b = nodes[i], nodes[j]
                    local wa = pinned[a.key] and 0 or 1
                    local wb = pinned[b.key] and 0 or 1
                    if wa + wb > 0 then
                        local dx = (b.x + b.w / 2) - (a.x + a.w / 2)
                        local dy = (b.y + b.h / 2) - (a.y + a.h / 2)
                        local need = tie_need[pairId(a.key, b.key)]
                        if need then
                            local dist = math.sqrt(dx * dx + dy * dy)
                            local ux, uy
                            if dist < 1 then
                                ux, uy, dist = 1, 0, 0
                            else
                                ux, uy = dx / dist, dy / dist
                            end
                            local function exit_len(node)
                                local hw, hh = node.w / 2 + 6, node.h / 2 + 6
                                local sx = ux ~= 0 and hw / math.abs(ux) or math.huge
                                local sy = uy ~= 0 and hh / math.abs(uy) or math.huge
                                return math.min(sx, sy)
                            end
                            local line_len = dist - exit_len(a) - exit_len(b)
                            local along_max, along_sum, perp_max, labelled = 0, 0, 0, false
                            for _k, label in ipairs(need.labels) do
                                if not label.none then
                                    labelled = true
                                    local along = math.abs(ux) * label.w + math.abs(uy) * label.h
                                    local perp = math.abs(uy) * label.w + math.abs(ux) * label.h
                                    along_max = math.max(along_max, along)
                                    along_sum = along_sum + along
                                    perp_max = math.max(perp_max, perp)
                                end
                            end
                            local need_len = layout.px(40)
                            if labelled then
                                need_len = layout.px(110) + ((perp_max + 4 <= line_spacing) and along_max or along_sum)
                            end
                            if line_len < need_len then
                                local deficit = need_len - line_len
                                local share_a, share_b = wa / (wa + wb), wb / (wa + wb)
                                a.x = a.x - ux * (deficit * share_a + wa)
                                a.y = a.y - uy * (deficit * share_a + wa)
                                b.x = b.x + ux * (deficit * share_b + wb)
                                b.y = b.y + uy * (deficit * share_b + wb)
                                moved = true
                            end
                        else
                            local need_x = (a.w + b.w) / 2 + base_x
                            local need_y = (a.h + b.h) / 2 + base_y
                            if math.abs(dx) < need_x and math.abs(dy) < need_y then
                                local pen_x = need_x - math.abs(dx)
                                local pen_y = need_y - math.abs(dy)
                                local share_a, share_b = wa / (wa + wb), wb / (wa + wb)
                                if pen_x / need_x < pen_y / need_y then
                                    local sign = dx >= 0 and 1 or -1
                                    a.x = a.x - sign * (pen_x * share_a + wa)
                                    b.x = b.x + sign * (pen_x * share_b + wb)
                                else
                                    local sign = dy >= 0 and 1 or -1
                                    a.y = a.y - sign * (pen_y * share_a + wa)
                                    b.y = b.y + sign * (pen_y * share_b + wb)
                                end
                                moved = true
                            end
                        end
                    end
                end
            end
            if not moved then break end
        end
        local min_x, min_y, max_x, max_y = math.huge, math.huge, -math.huge, -math.huge
        for _i, node in ipairs(nodes) do
            min_x = math.min(min_x, node.x)
            min_y = math.min(min_y, node.y)
            max_x = math.max(max_x, node.x + node.w)
            max_y = math.max(max_y, node.y + node.h)
        end
        for _i, node in ipairs(nodes) do
            node.x = node.x - min_x + margin
            node.y = node.y - min_y + margin
        end
        layout.origin_x = cx - min_x + margin
        layout.origin_y = cy - min_y + margin
        layout.content_w = (max_x - min_x) + 2 * margin
        layout.content_h = (max_y - min_y) + 2 * margin
        return layout
    end
    if not scale then
        L = place(1)
        if L.content_w > canvas_w then
            scale = math.max(0.45, math.floor(canvas_w / L.content_w * 20) / 20)
            freeTreeLayout(L)
            L = nil
        else
            scale = 1
        end
    end
    for _attempt = 1, 6 do
        L = L or place(scale)
        if L.content_w * L.content_h <= TREE_MAX_PIXELS or scale <= 0.45 then break end
        freeTreeLayout(L)
        L = nil
        scale = math.max(0.45, scale * 0.8)
    end
    L = L or place(scale)
    local by_key = L.by_key
    local px = L.px
    local content_w, content_h = L.content_w, L.content_h
    local result = drawFamilyTree(L, function() return "none" end, canvas_w, canvas_h, hide_underline)
    result.scale = scale
    local bb = result.bb
    local ox = math.floor((result.w - content_w) / 2)
    local oy = math.floor((result.h - content_h) / 2)
    local gray = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK
    local used = {}
    local lines = result.lines
    local thick = math.max(2, px(2))
    local function edge(a_key, b_key, style, color, thin, info)
        local na, nb = by_key[a_key], by_key[b_key]
        if not na or not nb then return end
        local ax, ay = socialEdgePoint(na, nb.x + nb.w / 2, nb.y + nb.h / 2)
        local bx, by = socialEdgePoint(nb, na.x + na.w / 2, na.y + na.h / 2)
        drawTreeSegment(bb, ax + ox, ay + oy, bx + ox, by + oy, style, thin and math.max(1, math.floor(thick / 2)) or thick, color, px(1))
        if info then
            lines[#lines + 1] = {
                x1 = math.min(ax, bx) + ox, y1 = math.min(ay, by) + oy,
                x2 = math.max(ax, bx) + ox, y2 = math.max(ay, by) + oy,
                seg = { ax + ox, ay + oy, bx + ox, by + oy },
                info = info,
            }
        end
    end
    if family_graph then
        for _i, child in ipairs(family_graph.order) do
            for _j, parent in ipairs(family_graph.parents[child] or {}) do
                if by_key[child] and by_key[parent] then
                    edge(parent, child, "solid", gray, true, nil)
                    used.family_ties = true
                end
            end
            for _j, partner in ipairs(family_graph.partners[child] or {}) do
                if child < partner and by_key[child] and by_key[partner] then
                    edge(child, partner, "solid", gray, true, nil)
                    used.family_ties = true
                end
            end
        end
    end
    if grid then
        local dot_color = Blitbuffer.COLOR_BLACK
        local step_x, step_y = grid.x * scale / 2, grid.y * scale / 2
        local origin_x, origin_y = L.origin_x + ox, L.origin_y + oy
        local first_i = math.ceil(-origin_x / step_x)
        local last_i = math.floor((result.w - origin_x) / step_x)
        local first_j = math.ceil(-origin_y / step_y)
        local last_j = math.floor((result.h - origin_y) / step_y)
        for gi = first_i, last_i do
            for gj = first_j, last_j do
                local dot_x = math.floor(origin_x + gi * step_x)
                local dot_y = math.floor(origin_y + gj * step_y)
                local free = true
                for _i, node in ipairs(L.nodes) do
                    if dot_x > node.x + ox - 8 and dot_x < node.x + ox + node.w + 8
                       and dot_y > node.y + oy - 8 and dot_y < node.y + oy + node.h + 8 then
                        free = false
                        break
                    end
                end
                if free then
                    if gi % 2 == 0 and gj % 2 == 0 then
                        bb:paintRect(dot_x - 1, dot_y - 4, 3, 9, dot_color)
                        bb:paintRect(dot_x - 2, dot_y - 3, 5, 7, dot_color)
                        bb:paintRect(dot_x - 3, dot_y - 2, 7, 5, dot_color)
                        bb:paintRect(dot_x - 4, dot_y - 1, 9, 3, dot_color)
                    else
                        bb:paintRect(dot_x - 1, dot_y - 1, 3, 3, dot_color)
                    end
                end
            end
        end
    end
    local function pairId(tie)
        if tie.a < tie.b then return tie.a .. "|" .. tie.b end
        return tie.b .. "|" .. tie.a
    end
    local pair_total, pair_seen = {}, {}
    for _i, tie in ipairs(ties) do
        if by_key[tie.a] and by_key[tie.b] and not tie.hidden then
            local id = pairId(tie)
            pair_total[id] = (pair_total[id] or 0) + 1
        end
    end
    local spacing = show_labels and px(48) or px(24)
    local black = Blitbuffer.COLOR_BLACK
    local label_face = Font:getFace("cfont", math.max(11, math.floor(14 * scale)))
    local label_jobs = {}
    local segs = {}
    for index, tie in ipairs(ties) do
        local na, nb = by_key[tie.a], by_key[tie.b]
        if na and nb and not tie.hidden then
            local id = pairId(tie)
            pair_seen[id] = (pair_seen[id] or 0) + 1
            local offset = (pair_seen[id] - (pair_total[id] + 1) / 2) * spacing
            local ca, cb = na, nb
            if tie.a > tie.b then ca, cb = nb, na end
            local cdx = (cb.x + cb.w / 2) - (ca.x + ca.w / 2)
            local cdy = (cb.y + cb.h / 2) - (ca.y + ca.h / 2)
            local clen = math.max(1, math.sqrt(cdx * cdx + cdy * cdy))
            local sx, sy = -cdy / clen * offset, cdx / clen * offset
            local ax, ay = socialEdgePoint(na, nb.x + nb.w / 2, nb.y + nb.h / 2)
            local bx, by = socialEdgePoint(nb, na.x + na.w / 2, na.y + na.h / 2)
            ax, ay, bx, by = ax + sx, ay + sy, bx + sx, by + sy
            drawTreeSegment(bb, ax + ox, ay + oy, bx + ox, by + oy, tie.visual, thick, black, px(1))
            do
                local dx, dy = bx - ax, by - ay
                local len = math.sqrt(dx * dx + dy * dy)
                if len >= 1 then
                    drawArrowHead(bb, bx + ox, by + oy, dx / len, dy / len, px(20), black)
                    if not tie.oneway then
                        drawArrowHead(bb, ax + ox, ay + oy, -dx / len, -dy / len, px(20), black)
                    end
                end
            end
            lines[#lines + 1] = {
                x1 = math.min(ax, bx) + ox, y1 = math.min(ay, by) + oy,
                x2 = math.max(ax, bx) + ox, y2 = math.max(ay, by) + oy,
                seg = { ax + ox, ay + oy, bx + ox, by + oy },
                info = { kind = "tie", a = tie.a, b = tie.b, index = tie.index or index },
            }
            segs[#segs + 1] = { idx = index, ax = ax + ox, ay = ay + oy, bx = bx + ox, by = by + oy }
            used[tie.meaning_key] = tie.custom and { visual = tie.visual, meaning = tie.label } or true
            if show_labels and tie.label then
                label_jobs[#label_jobs + 1] = {
                    idx = index, t = tie.label_t,
                    text = tie.label,
                    ax = ax + ox, ay = ay + oy, bx = bx + ox, by = by + oy,
                }
            end
        end
    end
    local placed = {}
    local function overlaps(r1, r2)
        return r1.x < r2.x + r2.w and r2.x < r1.x + r1.w and r1.y < r2.y + r2.h and r2.y < r1.y + r1.h
    end
    local node_rects = {}
    for _i, node in ipairs(L.nodes) do
        node_rects[#node_rects + 1] = { x = node.x + ox, y = node.y + oy, w = node.w, h = node.h }
    end
    local fractions = { 0.5, 0.42, 0.58, 0.34, 0.66, 0.27, 0.73, 0.22, 0.78 }
    local function segment_hits(seg, rect)
        local sdx, sdy = seg.bx - seg.ax, seg.by - seg.ay
        local steps = math.max(1, math.floor(math.sqrt(sdx * sdx + sdy * sdy) / 6))
        for step = 0, steps do
            local f = step / steps
            local sx, sy = seg.ax + sdx * f, seg.ay + sdy * f
            if sx >= rect.x and sx <= rect.x + rect.w and sy >= rect.y and sy <= rect.y + rect.h then
                return true
            end
        end
        return false
    end
    for _i, job in ipairs(label_jobs) do
        local tw = TextWidget:new{ text = job.text, face = label_face }
        local size = tw:getSize()
        local rect_w, rect_h = size.w + 6, size.h + 2
        local best, best_score
        local candidates = job.t and { math.max(0.1, math.min(0.9, job.t)) } or fractions
        for _j, t in ipairs(candidates) do
            local mx = job.ax + (job.bx - job.ax) * t
            local my = job.ay + (job.by - job.ay) * t
            local rect = { x = math.floor(mx - rect_w / 2), y = math.floor(my - rect_h / 2), w = rect_w, h = rect_h }
            local score = 0
            for _k, other in ipairs(placed) do
                if overlaps(rect, other) then score = score + 10 end
            end
            for _k, nr in ipairs(node_rects) do
                if overlaps(rect, nr) then score = score + 1 end
            end
            for _k, seg in ipairs(segs) do
                if seg.idx ~= job.idx and segment_hits(seg, rect) then score = score + 3 end
            end
            if not best_score or score < best_score then
                best, best_score = rect, score
            end
            if score == 0 then break end
        end
        bb:paintRect(best.x, best.y, best.w, best.h, Blitbuffer.COLOR_WHITE)
        tw:paintTo(bb, best.x + 3, best.y + 1)
        tw:free()
        placed[#placed + 1] = best
    end
    result.legend = used
    result.origin = { x = L.origin_x + ox, y = L.origin_y + oy }
    return result
end

local function treeLegendEntries(used)
    local entries = {}
    if not used then return entries end
    for _i, def in ipairs(LINE_MEANING_KEYS) do
        if used[def.key] then
            table.insert(entries, { visual = def.visual, meaning = lineMeaning(def.key) })
        end
    end
    local customs = {}
    for _key, value in pairs(used) do
        if type(value) == "table" then table.insert(customs, value) end
    end
    table.sort(customs, function(a, b) return a.meaning:lower() < b.meaning:lower() end)
    for _i, value in ipairs(customs) do
        table.insert(entries, { visual = value.visual, meaning = value.meaning })
    end
    if used.family_ties then
        table.insert(entries, { visual = "gray", meaning = _("Family ties") })
    end
    return entries
end

local function paintTreeLegend(bb, x, y, w, h, entries)
    local gray = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK
    local black = Blitbuffer.COLOR_BLACK
    local face = Font:getFace("cfont", 15)
    local widgets, max_w, row_h = {}, 0, 0
    for _i, entry in ipairs(entries) do
        local tw = TextWidget:new{ text = entry.meaning, face = face }
        local size = tw:getSize()
        if size.w > max_w then max_w = size.w end
        if size.h > row_h then row_h = size.h end
        widgets[#widgets + 1] = tw
    end
    local pad, sample = 10, 54
    row_h = row_h + 8
    local box_w = pad * 2 + sample + 10 + max_w
    local box_h = pad * 2 + #entries * row_h
    local bx, by = x + 10, y + h - box_h - 10
    bb:paintRect(bx, by, box_w, box_h, Blitbuffer.COLOR_WHITE)
    bb:paintRect(bx, by, box_w, 2, black)
    bb:paintRect(bx, by + box_h - 2, box_w, 2, black)
    bb:paintRect(bx, by, 2, box_h, black)
    bb:paintRect(bx + box_w - 2, by, 2, box_h, black)
    for i, entry in ipairs(entries) do
        local row_top = by + pad + (i - 1) * row_h
        local ry = row_top + math.floor(row_h / 2)
        local lx = bx + pad
        if entry.visual == "double" then
            bb:paintRect(lx, ry - 3, sample, 2, black)
            bb:paintRect(lx, ry + 1, sample, 2, black)
        elseif entry.visual == "dashed" then
            local px = lx
            while px < lx + sample do
                bb:paintRect(px, ry - 1, math.min(12, lx + sample - px), 3, black)
                px = px + 18
            end
        elseif entry.visual == "dotted" then
            local px = lx
            while px < lx + sample do
                bb:paintRect(px, ry - 1, 3, 3, black)
                px = px + 9
            end
        elseif entry.visual == "thin" then
            bb:paintRect(lx, ry, sample, 1, black)
        elseif entry.visual == "thick" then
            bb:paintRect(lx, ry - 3, sample, 6, black)
        elseif entry.visual == "dashdot" then
            local px = lx
            while px < lx + sample do
                bb:paintRect(px, ry - 1, math.min(12, lx + sample - px), 3, black)
                px = px + 12
                if px < lx + sample then bb:paintRect(px + 3, ry - 1, 3, 3, black) end
                px = px + 11
            end
        elseif entry.visual == "wavy" then
            for wx = 0, sample - 1, 2 do
                local wy = math.floor(math.sin(wx / 4) * 4 + 0.5)
                bb:paintRect(lx + wx, ry + wy - 1, 2, 3, black)
            end
        elseif entry.visual == "gray" then
            bb:paintRect(lx, ry, sample, 2, gray)
        else
            bb:paintRect(lx, ry - 1, sample, 3, black)
        end
        widgets[i]:paintTo(bb, lx + sample + 10, row_top + 4)
        widgets[i]:free()
    end
end

local FamilyTreeCanvas = InputContainer:extend{
    width = 0,
    height = 0,
}

function FamilyTreeCanvas:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.off_x = 0
    self.off_y = 0
    self.ges_events = {
        TreeTap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
        TreeSwipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            },
        },
        TreeHold = {
            GestureRange:new{
                ges = "hold",
                range = function() return self.dimen end,
            },
        },
    }
end

function FamilyTreeCanvas:onTreeHold(_arg, ges)
    if self.passthrough and self.passthrough() then return false end
    if self.result and self.on_hold then
        self.on_hold(ges.pos.x - self.dimen.x + self.off_x, ges.pos.y - self.dimen.y + self.off_y)
    end
    return true
end

function FamilyTreeCanvas:getSize()
    return self.dimen
end

function FamilyTreeCanvas:freeResult()
    if self.result and self.result.bb then
        self.result.bb:free()
    end
    self.result = nil
end

function FamilyTreeCanvas:setResult(result)
    self:freeResult()
    self.result = result
    self.off_x = math.max(0, math.floor((result.w - self.dimen.w) / 2))
    self.off_y = 0
end

function FamilyTreeCanvas:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_WHITE)
    if self.result then
        local src_x, src_y = math.max(0, self.off_x), math.max(0, self.off_y)
        local dst_x, dst_y = math.max(0, -self.off_x), math.max(0, -self.off_y)
        local blit_w = math.min(self.dimen.w - dst_x, self.result.w - src_x)
        local blit_h = math.min(self.dimen.h - dst_y, self.result.h - src_y)
        if blit_w > 0 and blit_h > 0 then
            bb:blitFrom(self.result.bb, x + dst_x, y + dst_y, src_x, src_y, blit_w, blit_h)
        end
        if self.show_legend and self.show_legend() then
            local entries = treeLegendEntries(self.result.legend)
            if #entries > 0 then paintTreeLegend(bb, x, y, self.dimen.w, self.dimen.h, entries) end
        end
    end
end

function FamilyTreeCanvas:onTreeTap(_arg, ges)
    if self.passthrough and self.passthrough() then return false end
    if self.result and self.on_tap then
        self.on_tap(ges.pos.x - self.dimen.x + self.off_x, ges.pos.y - self.dimen.y + self.off_y)
    end
    return true
end

function FamilyTreeCanvas:onTreeSwipe(_arg, ges)
    if self.passthrough and self.passthrough() then return false end
    if not self.result then return true end
    local dist = ges.distance or 200
    if self.pan_boost and self.pan_boost() then dist = dist * 1.6 end
    local dir = ges.direction or ""
    local diagonal = (dir:find("north") or dir:find("south")) and (dir:find("east") or dir:find("west"))
    if diagonal then dist = dist * 0.7 end
    local dx, dy = 0, 0
    if dir:find("east") then dx = dist elseif dir:find("west") then dx = -dist end
    if dir:find("north") then dy = -dist elseif dir:find("south") then dy = dist end
    local slack_x = math.floor(self.dimen.w * 0.45)
    local slack_y = math.floor(self.dimen.h * 0.45)
    local max_x = math.max(0, self.result.w - self.dimen.w) + slack_x
    local max_y = math.max(0, self.result.h - self.dimen.h) + slack_y
    self.off_x = math.min(max_x, math.max(-slack_x, self.off_x - dx))
    self.off_y = math.min(max_y, math.max(-slack_y, self.off_y - dy))
    UIManager:setDirty(self.show_parent or self, function()
        return "ui", self.dimen
    end)
    return true
end

local FamilyTreeView = InputContainer:extend{
    covers_fullscreen = true,
    tracker = nil,
    family = nil,
    scale = nil,
}

function FamilyTreeView:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.hidden_down = {}
    self.hidden_up = {}
    self.focus = nil
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    local gray = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_BLACK
    local title_frame = HorizontalGroup:new{
        align = "center",
        FrameContainer:new{
            bordersize = 0,
            padding = 10,
            padding_bottom = 2,
            TextWidget:new{
                text = T(_("Family tree — %1"), self.family.name or ""),
                face = Font:getFace("tfont", 22),
                bold = true,
                max_width = sw - 130,
            },
        },
        Button:new{
            text = "✕",
            bordersize = 0,
            margin = 0,
            padding = 12,
            show_parent = self,
            callback = function() self:onClose() end,
        },
    }
    self.base_hint = self.family.tree_kind == "social"
        and _("Tap a name to see their relationships · tap a line for the details")
        or _("Tap a name for details · hold a name to focus on them · tap a line for the relationship")
    self.hint_widget = TextWidget:new{
        text = self.base_hint,
        face = Font:getFace("cfont", 16),
        fgcolor = gray,
        max_width = sw - 40,
    }
    local hint_frame = FrameContainer:new{
        bordersize = 0,
        padding = 4,
        padding_left = 10,
        self.hint_widget,
    }
    self.editing = not self.read_only
    local button_row
    if self.read_only then
        button_row = {
            { text = "-", callback = function() self:zoom(-1) end },
            { text = "+", callback = function() self:zoom(1) end },
            { text = _("Pan"), callback = function() self:togglePan() end },
            { text = _("Shot"), callback = function() self:showShotMenu() end },
            { text = _("Edit"), callback = function()
                UIManager:close(self)
                self.tracker:showFamilyTree(self.family, false)
            end },
            { text = _("Close"), callback = function() self:onClose() end },
        }
    else
        button_row = {
            { text = "-", callback = function() self:zoom(-1) end },
            { text = "+", callback = function() self:zoom(1) end },
            { text = self.family.tree_kind == "social" and _("Ties") or _("Lines"), callback = function()
                if self.family.tree_kind == "social" then
                    self.tracker:showFamilySocialTiesManager(self.family, self)
                else
                    self.tracker:showFamilyLinesDialog(self.family, self)
                end
            end },
            { text = _("View"), callback = function()
                self.tracker:showFamilyTreeViewDialog(self.family, self)
            end },
            { text = _("Read"), callback = function()
                UIManager:close(self)
                self.tracker:showFamilyTree(self.family, true)
            end },
            { text = _("Shot"), callback = function() self:showShotMenu() end },
            { text = _("Close"), callback = function() self:onClose() end },
        }
        if self.family.tree_kind == "social" then
            table.insert(button_row, 4, { text = _("Mode"), callback = function()
                self:showModeDialog()
            end })
        else
            table.insert(button_row, 3, { text = _("Pan"), callback = function() self:togglePan() end })
        end
    end
    if self.tracker:isTreeShotHidden() then
        for i = #button_row, 1, -1 do
            if button_row[i].text == _("Shot") then table.remove(button_row, i) end
        end
        self.gesture_mode = false
    end
    self.button_table = ButtonTable:new{
        width = sw - 20,
        show_parent = self,
        buttons = { button_row },
    }
    local canvas_h = sh - title_frame:getSize().h - hint_frame:getSize().h - self.button_table:getSize().h - 4
    self.canvas = FamilyTreeCanvas:new{
        width = sw,
        height = canvas_h,
        show_parent = self,
        on_tap = function(x, y) self:onCanvasTap(x, y) end,
        on_hold = function(x, y) self:onCanvasHold(x, y) end,
        passthrough = function() return self.gesture_mode end,
        show_legend = function() return self.tracker:isTreeLegendOn() end,
        pan_boost = function() return self.mode == "pan" end,
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        VerticalGroup:new{
            align = "center",
            title_frame,
            hint_frame,
            self.canvas,
            self.button_table,
        },
    }
    self:rebuild(self.scale)
end

function FamilyTreeView:rebuild(scale)
    self.tracker:_syncGenders()
    if self.family.tree_kind == "social" then
        self.vf = self.tracker:buildSocialStub(self.family)
        self.full_graph = buildFamilyGraph(self.vf)
        if not self.full_graph then
            self.graph = nil
            self.canvas:freeResult()
            return
        end
        self.base_graph = self.full_graph
        self.graph = self.full_graph
        local ties = {}
        for index, tie in ipairs(self.family.social_ties or {}) do
            local info = tieInfo(tie)
            table.insert(ties, {
                a = lowerOrEmpty(tie.from), b = lowerOrEmpty(tie.to), visual = info.visual, pull = info.pull, index = index,
                meaning_key = info.custom and ("custom|" .. info.visual .. "|" .. info.label) or ("tie_" .. info.key),
                label = info.label, custom = info.custom, oneway = tie.oneway, hidden = tie.hide_line, label_t = tie.label_t,
            })
        end
        local family_graph
        if self.tracker:isSocialShowFamily() then family_graph = buildFamilyGraph(self.family) end
        local member_groups = {}
        for _i, group in ipairs(self.family.social_groups or {}) do
            local set = {}
            for _j, name in ipairs(group.members or {}) do set[#set + 1] = lowerOrEmpty(name) end
            if #set >= 2 then member_groups[#member_groups + 1] = set end
        end
        local result = renderSocialTree(self.vf, ties, self.graph, scale, self.canvas.dimen.w, self.canvas.dimen.h,
            self.tracker:isTreeUnderlineHidden(), family_graph, member_groups, self.tracker:isSocialLabelsOn(),
            self.family.social_positions,
            (self.mode == "move" and self.family.social_grid) and { x = SOCIAL_GRID_X, y = SOCIAL_GRID_Y } or nil)
        self.scale = result.scale
        self.canvas:setResult(result)
        UIManager:setDirty(self, "ui")
        return
    end
    self.vf = self.tracker:buildCombinedFamily(self.family)
    self.full_graph = buildFamilyGraph(self.vf)
    if not self.full_graph then
        self.graph = nil
        self.canvas:freeResult()
        return
    end
    local base = self.full_graph
    if self.focus and base.canon[self.focus] then
        base.relation_labels = treeRelationLabels(base, self.vf, self.focus)
        if self.tracker:isTreeFocusLabelOnly() then
            base.focus = self.focus
        else
            base = focusFamilyGraph(base, self.focus, self.tracker:getTreeFocusDepth())
        end
    else
        self.focus = nil
    end
    self.base_graph = base
    self.graph = collapseFamilyGraph(base, self.hidden_down, self.hidden_up)
    local result = renderFamilyTree(self.vf, self.graph, scale, self.canvas.dimen.w, self.canvas.dimen.h, function(a, b)
        return self.tracker:getCoupleStyle(self.vf, self.graph, a, b)
    end, self.tracker:isTreeUnderlineHidden())
    self.scale = result.scale
    self.canvas:setResult(result)
    UIManager:setDirty(self, "ui")
end

function FamilyTreeView:zoom(direction)
    local current = self.scale or 1
    local target
    if direction > 0 then
        for _i, s in ipairs(TREE_SCALES) do
            if s > current + 0.01 then
                target = s
                break
            end
        end
    else
        for i = #TREE_SCALES, 1, -1 do
            if TREE_SCALES[i] < current - 0.01 then
                target = TREE_SCALES[i]
                break
            end
        end
    end
    if target then self:rebuild(target) end
end

function FamilyTreeView:personAt(x, y)
    local result = self.canvas.result
    if not result then return nil end
    for _i, p in ipairs(result.persons) do
        if x >= p.x and x <= p.x + p.w and y >= p.y and y <= p.y + p.h then
            return p.key
        end
    end
    return nil
end

function FamilyTreeView:branchCount(key, direction)
    local base = self.base_graph
    collapseFamilyGraph(base, direction == "down" and { [key] = true } or {}, direction == "up" and { [key] = true } or {})
    local counts = base.hidden_counts and base.hidden_counts[key]
    base.hidden_counts = nil
    return counts and counts[direction] or 0
end

function FamilyTreeView:toggleBranch(key, direction)
    local state = direction == "down" and self.hidden_down or self.hidden_up
    if state[key] then
        state[key] = nil
    else
        state[key] = true
    end
    self:rebuild(self.scale)
end

function FamilyTreeView:setFocus(key)
    self.focus = key
    self:rebuild(self.scale)
end

function FamilyTreeView:clearBranches()
    self.hidden_down = {}
    self.hidden_up = {}
    self:rebuild(self.scale)
end

function FamilyTreeView:branchAction(key)
    if self.hidden_up[key] then
        self:toggleBranch(key, "up")
    elseif self.hidden_down[key] then
        self:toggleBranch(key, "down")
    elseif self.base_graph.partners[key] and self:branchCount(key, "up") > 0 then
        self:toggleBranch(key, "up")
    elseif self:branchCount(key, "down") > 0 then
        self:toggleBranch(key, "down")
    elseif self:branchCount(key, "up") > 0 then
        self:toggleBranch(key, "up")
    else
        UIManager:show(InfoMessage:new{
            text = T(_("%1 has no branch to hide."), self.graph.canon[key] or "?"),
            timeout = 2,
        })
    end
end

function FamilyTreeView:updateHint()
    local name = self.pending and self.graph and self.graph.canon[self.pending]
    local text
    if self.mode == "move" then
        text = name and T(_("Moving %1 — tap where to put them · hold a name to let it arrange itself"), name)
            or _("Move mode — tap a name, then tap where it should go")
    elseif self.mode == "draw" then
        text = name and T(_("Line from %1 — now tap the person the arrow points to"), name)
            or _("Draw mode — tap the first name, then the second; the arrow points to the second")
    elseif self.mode == "pan" then
        text = _("Pan mode — swipe to move around the tree · tap Pan again to go back")
    else
        text = self.base_hint
    end
    self.hint_widget:setText(text)
    UIManager:setDirty(self, "ui")
end

function FamilyTreeView:setMode(mode)
    self.mode = mode
    self.pending = nil
    if self.family.social_grid then self:rebuild(self.scale) end
    self:updateHint()
end

function FamilyTreeView:togglePan()
    self:setMode(self.mode ~= "pan" and "pan" or nil)
end

function FamilyTreeView:snapAllToGrid()
    local result = self.canvas.result
    if not result or not result.origin then return end
    local sc = self.scale or 1
    if type(self.family.social_positions) ~= "table" then self.family.social_positions = {} end
    for _i, person in ipairs(result.persons) do
        local x = (person.x + person.w / 2 - result.origin.x) / sc
        local y = (person.y + person.h / 2 - result.origin.y) / sc
        self.family.social_positions[person.key] = {
            x = math.floor(x / SOCIAL_GRID_X + 0.5) * SOCIAL_GRID_X,
            y = math.floor(y / SOCIAL_GRID_Y + 0.5) * SOCIAL_GRID_Y,
        }
    end
    self.tracker:saveFamilies()
    self:rebuild(self.scale)
end

function FamilyTreeView:showModeDialog()
    local dialog
    local function pick(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    local mode = self.mode or "browse"
    local function mark(key)
        return mode == key and "✓ " or ""
    end
    dialog = ButtonDialog:new{
        title = _("Tree mode"),
        buttons = {
            {
                { text = mark("browse") .. _("Browse (tap names and lines)"), callback = pick(function()
                    self:setMode(nil)
                end) },
            },
            {
                { text = mark("pan") .. _("Pan (swipe to look around the tree)"), callback = pick(function()
                    self:setMode("pan")
                end) },
            },
            {
                { text = mark("move") .. _("Move people around"), callback = pick(function()
                    self:setMode("move")
                end) },
            },
            {
                { text = mark("draw") .. _("Draw a line between two people"), callback = pick(function()
                    self:setMode("draw")
                end) },
            },
            {
                { text = (self.family.social_grid and "✓ " or "") .. _("Grid mode (names snap to a grid)"), callback = pick(function()
                    self.family.social_grid = (not self.family.social_grid) or nil
                    self.tracker:saveFamilies()
                    self:rebuild(self.scale)
                    UIManager:show(InfoMessage:new{
                        text = self.family.social_grid
                            and _("Grid mode is on. In Move mode, names now snap to the dots.")
                            or _("Grid mode is off. Names go exactly where you tap."),
                        timeout = 3,
                    })
                end) },
            },
            {
                { text = _("Snap everyone to the grid"), callback = pick(function()
                    self:snapAllToGrid()
                end) },
            },
            {
                { text = _("Reset layout (let the tree arrange itself)"), callback = pick(function()
                    self.family.social_positions = {}
                    self.tracker:saveFamilies()
                    self:rebuild(self.scale)
                end) },
            },
            {
                { text = _("Cancel"), id = "close", callback = pick(function() end) },
            },
        },
    }
    UIManager:show(dialog)
end

function FamilyTreeView:onModeTap(x, y)
    if self.mode == "pan" then return end
    local key = self:personAt(x, y)
    if self.mode == "move" then
        if key then
            self.pending = key
            self:updateHint()
            return
        end
        local origin = self.canvas.result and self.canvas.result.origin
        if not self.pending or not origin then return end
        local sc = self.scale or 1
        if type(self.family.social_positions) ~= "table" then self.family.social_positions = {} end
        local world_x, world_y = (x - origin.x) / sc, (y - origin.y) / sc
        if self.family.social_grid then
            local half_x, half_y = SOCIAL_GRID_X / 2, SOCIAL_GRID_Y / 2
            world_x = math.floor(world_x / half_x + 0.5) * half_x
            world_y = math.floor(world_y / half_y + 0.5) * half_y
        end
        self.family.social_positions[self.pending] = { x = world_x, y = world_y }
        self.pending = nil
        self.tracker:saveFamilies()
        self:rebuild(self.scale)
        self:updateHint()
    elseif self.mode == "draw" then
        if not key then return end
        if not self.pending then
            self.pending = key
            self:updateHint()
            return
        end
        if key == self.pending then
            self.pending = nil
            self:updateHint()
            return
        end
        local from, to = self.graph.canon[self.pending], self.graph.canon[key]
        self.pending = nil
        self:updateHint()
        self.tracker:_createSocialTie(self.family, self, from, to)
    end
end

function FamilyTreeView:onCanvasHold(x, y)
    if self.mode == "pan" then return end
    local key = self:personAt(x, y)
    if not key then return end
    if self.mode == "move" then
        if type(self.family.social_positions) == "table" then self.family.social_positions[key] = nil end
        self.pending = nil
        self.tracker:saveFamilies()
        self:rebuild(self.scale)
        self:updateHint()
        return
    end
    if self.family.tree_kind == "social" then
        self.tracker:showFamilyTreePersonInfo(self.family, self, key)
        return
    end
    if self.tracker:getTreeHoldAction() == "focus" then
        self:setFocus(self.focus ~= key and key or nil)
    else
        self:branchAction(key)
    end
end

function FamilyTreeView:onCanvasTap(x, y)
    local result = self.canvas.result
    if not result then return end
    if self.mode then
        self:onModeTap(x, y)
        return
    end
    local key = self:personAt(x, y)
    if key then
        self.tracker:showFamilyTreePersonInfo(self.family, self, key)
        return
    end
    local tolerance = math.max(14, math.floor(18 * (self.scale or 1)))
    local best, best_d
    for _i, l in ipairs(result.lines) do
        local dx, dy = 0, 0
        if l.seg then
            local sx1, sy1, sx2, sy2 = l.seg[1], l.seg[2], l.seg[3], l.seg[4]
            local vx, vy = sx2 - sx1, sy2 - sy1
            local len2 = vx * vx + vy * vy
            local t = len2 > 0 and ((x - sx1) * vx + (y - sy1) * vy) / len2 or 0
            t = math.max(0, math.min(1, t))
            dx, dy = x - (sx1 + t * vx), y - (sy1 + t * vy)
        else
            if x < l.x1 then dx = l.x1 - x elseif x > l.x2 then dx = x - l.x2 end
            if y < l.y1 then dy = l.y1 - y elseif y > l.y2 then dy = y - l.y2 end
        end
        local d = math.sqrt(dx * dx + dy * dy) + (l.info.kind == "group" and 0.5 or 0)
        if d <= tolerance and (not best_d or d < best_d) then
            best, best_d = l, d
        end
    end
    if best then
        self.tracker:showFamilyTreeLineInfo(self.family, self, best.info)
    end
end

function FamilyTreeView:saveImage()
    local result = self.canvas.result
    if not result or not result.bb then return end
    local dir = (G_reader_settings and G_reader_settings:readSetting("screenshot_dir"))
        or (DataStorage:getFullDataDir() .. "/screenshots")
    lfs.mkdir(dir)
    local safe = (self.family.name or "family"):gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
    local path = dir .. "/FamilyTree_" .. safe .. os.date("_%Y-%m-%d_%H-%M-%S") .. ".png"
    local ok = pcall(function() result.bb:writePNG(path) end)
    UIManager:show(InfoMessage:new{
        text = ok and T(_("Saved the whole tree to:\n%1"), path) or _("Could not save the image."),
        timeout = 4,
    })
end

function FamilyTreeView:showShotMenu()
    local dialog
    local function pick(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    local buttons = {}
    if self.gesture_mode then
        table.insert(buttons, {
            { text = _("Turn off gesture mode"), callback = pick(function()
                self.gesture_mode = false
            end) },
        })
    else
        table.insert(buttons, {
            { text = _("Gesture / screenshot mode"), callback = pick(function()
                self.gesture_mode = true
                UIManager:show(InfoMessage:new{
                    text = _("Gesture mode is on: the tree ignores touches so your own gestures, like the screenshot gesture, work. Tap Shot to turn it off."),
                    timeout = 4,
                })
            end) },
        })
    end
    table.insert(buttons, {
        { text = _("Save whole tree as image"), callback = pick(function() self:saveImage() end) },
    })
    table.insert(buttons, {
        { text = _("Cancel"), id = "close", callback = pick(function() end) },
    })
    dialog = ButtonDialog:new{
        title = self.gesture_mode and _("Screenshots (gesture mode is on)") or _("Screenshots"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function FamilyTreeView:onClose()
    UIManager:close(self, "flashui")
    return true
end

function FamilyTreeView:onCloseWidget()
    if self.canvas then self.canvas:freeResult() end
end

function CharacterTracker:_showChoice(title, choices, on_pick, custom)
    local buttons = {}
    local row = {}
    for _i, choice in ipairs(choices) do
        table.insert(row, {
            text = choice.label,
            callback = function()
                UIManager:close(self._choice_dialog)
                self._choice_dialog = nil
                on_pick(choice.value)
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    if custom then
        table.insert(buttons, {
            {
                text = _("Custom…"),
                callback = function()
                    UIManager:close(self._choice_dialog)
                    self._choice_dialog = nil
                    local dialog
                    dialog = InputDialog:new{
                        title = custom.title or title,
                        input_hint = custom.hint,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        local text = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        if text ~= "" then on_pick(text) end
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._choice_dialog)
                self._choice_dialog = nil
            end,
        },
    })
    self._choice_dialog = ButtonDialog:new{
        title = title,
        buttons = buttons,
    }
    UIManager:show(self._choice_dialog)
end

function CharacterTracker:_removeFamilyMember(family, index)
    local member = family.members[index]
    if not member then return end
    local name = lowerOrEmpty(member.name)
    table.remove(family.members, index)
    for i = #(family.relations or {}), 1, -1 do
        local rel = family.relations[i]
        if lowerOrEmpty(rel.from) == name or lowerOrEmpty(rel.to) == name then
            table.remove(family.relations, i)
        end
    end
    for i = #(family.social_ties or {}), 1, -1 do
        local tie = family.social_ties[i]
        if lowerOrEmpty(tie.from) == name or lowerOrEmpty(tie.to) == name then
            self:_unmirrorSocialTie(tie)
            table.remove(family.social_ties, i)
        end
    end
    for i = #(family.succession or {}), 1, -1 do
        if lowerOrEmpty(family.succession[i].name) == name then
            table.remove(family.succession, i)
        end
    end
    for i = #(family.section_order or {}), 1, -1 do
        if lowerOrEmpty(family.section_order[i]) == name then
            table.remove(family.section_order, i)
        end
    end
    for _i, other in ipairs(family.members) do
        for j = #(other.parents or {}), 1, -1 do
            if lowerOrEmpty(other.parents[j]) == name then
                table.remove(other.parents, j)
            end
        end
    end
    self:saveFamilies()
end

function CharacterTracker:getFamilySectionOrder(family)
    local order, seen = {}, {}
    for _i, name in ipairs(family.section_order or {}) do
        local member = memberByName(family, name)
        if member and not seen[lowerOrEmpty(member.name)] then
            seen[lowerOrEmpty(member.name)] = true
            order[#order + 1] = member.name
        end
    end
    for _i, member in ipairs(family.members or {}) do
        local key = lowerOrEmpty(member.name)
        if not seen[key] then
            seen[key] = true
            order[#order + 1] = member.name
        end
    end
    return order
end

function CharacterTracker:buildSocialText(family)
    local parts = {}
    if family.description and family.description ~= "" then
        table.insert(parts, "\n" .. family.description .. "\n")
    end

    if family.members and #family.members > 0 then
        local lines = {}
        for _i, member in ipairs(family.members) do
            local line = member.name or "?"
            if member.role and member.role ~= "" then line = line .. " — " .. member.role end
            table.insert(lines, line)
        end
        table.insert(parts, pageBlock(T(_("Members (%1)"), #lines), pageBullets(lines, "• ")))
    else
        table.insert(parts, "\n" .. _("No members added yet.") .. "\n")
    end

    if family.social_groups and #family.social_groups > 0 then
        local lines = {}
        for _i, group in ipairs(family.social_groups) do
            local line = group.name or "?"
            if #group.members > 0 then line = line .. " — " .. table.concat(group.members, ", ") end
            table.insert(lines, line)
        end
        table.insert(parts, pageBlock(T(_("Groups (%1)"), #lines), pageBullets(lines, "• ")))
    end

    for _i, kind in ipairs(TIE_KINDS) do
        local lines = {}
        for _j, tie in ipairs(family.social_ties or {}) do
            if tie.kind == kind.key then
                local line = (tie.from or "?") .. tieLink(tie) .. (tie.to or "?")
                if tie.notes and #tie.notes > 0 then line = line .. " — " .. table.concat(tie.notes, "; ") end
                table.insert(lines, line)
            end
        end
        if #lines > 0 then
            table.insert(parts, pageBlock(
                tieKindMeaning(kind.key) .. " (" .. #lines .. ")", pageBullets(lines, "• ")))
        end
    end

    local custom_names, custom_order = {}, {}
    for _i, tie in ipairs(family.social_ties or {}) do
        if tie.kind == "custom" and type(tie.custom) == "table" then
            local name = tie.custom.name or "?"
            if not custom_names[name] then
                custom_names[name] = {}
                custom_order[#custom_order + 1] = name
            end
            local line = (tie.from or "?") .. tieLink(tie) .. (tie.to or "?")
            if tie.notes and #tie.notes > 0 then line = line .. " — " .. table.concat(tie.notes, "; ") end
            table.insert(custom_names[name], line)
        end
    end
    for _i, name in ipairs(custom_order) do
        table.insert(parts, pageBlock(name .. " (" .. #custom_names[name] .. ")", pageBullets(custom_names[name], "• ")))
    end

    local lists = {
        { "dynamics", _("Dynamics") },
        { "history", _("History") },
        { "secrets", _("Secrets") },
        { "notes", _("Notes") },
    }
    for _i, spec in ipairs(lists) do
        local list = family[spec[1]]
        if list and #list > 0 then
            table.insert(parts, pageBlock(spec[2] .. " (" .. #list .. ")", pageBullets(list, "• ")))
        end
    end

    return (table.concat(parts):gsub("^\n+", ""))
end

function CharacterTracker:showSocialGroupsManager(family)
    if type(family.social_groups) ~= "table" then family.social_groups = {} end
    local function back() self:showSocialGroupsManager(family) end
    local buttons = {}
    for i, group in ipairs(family.social_groups) do
        table.insert(buttons, {
            {
                text = shorten((group.name or "?") .. " · " .. #group.members, 42),
                callback = function()
                    UIManager:close(self._social_groups_dialog)
                    self._social_groups_dialog = nil
                    self:showSocialGroupActions(family, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._social_groups_dialog)
                    self._social_groups_dialog = nil
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete the group '%1'?"), group.name or "?"),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            table.remove(family.social_groups, i)
                            self:saveFamilies()
                            back()
                        end,
                        cancel_callback = back,
                    })
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add group"),
            callback = function()
                UIManager:close(self._social_groups_dialog)
                self._social_groups_dialog = nil
                local dialog
                dialog = InputDialog:new{
                    title = _("New group"),
                    input_hint = _("e.g. The Wolf Pack, the book club"),
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(dialog)
                                    back()
                                end,
                            },
                            {
                                text = _("Create"),
                                is_enter_default = true,
                                callback = function()
                                    local name = trim(dialog:getInputText())
                                    UIManager:close(dialog)
                                    if name ~= "" then
                                        table.insert(family.social_groups, { name = name, members = {} })
                                        self:saveFamilies()
                                        self:showSocialGroupActions(family, #family.social_groups)
                                    else
                                        back()
                                    end
                                end,
                            },
                        },
                    },
                }
                self:_showInputDialog(dialog)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._social_groups_dialog)
                self._social_groups_dialog = nil
                self:showFamilyDetail(family)
            end,
        },
    })
    self._social_groups_dialog = ButtonDialog:new{
        title = T(_("Groups — %1\n(members of a group sit together in the tree)"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._social_groups_dialog)
end

function CharacterTracker:showSocialGroupActions(family, index)
    local group = family.social_groups[index]
    if not group then return end
    local function back() self:showSocialGroupsManager(family) end
    local function close_and(fn)
        return function()
            UIManager:close(self._social_group_act_dialog)
            self._social_group_act_dialog = nil
            fn()
        end
    end
    self._social_group_act_dialog = ButtonDialog:new{
        title = T(_("%1 (%2 members)"), group.name or "?", #group.members),
        buttons = {
            {
                { text = _("Members"), callback = close_and(function()
                    self:showSocialGroupMembers(family, index)
                end) },
                { text = _("Rename"), callback = close_and(function()
                    local dialog
                    dialog = InputDialog:new{
                        title = _("Rename group"),
                        input = group.name or "",
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                        back()
                                    end,
                                },
                                {
                                    text = _("Rename"),
                                    is_enter_default = true,
                                    callback = function()
                                        local name = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        if name ~= "" then
                                            group.name = name
                                            self:saveFamilies()
                                        end
                                        back()
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end) },
            },
            {
                { text = _("Delete"), callback = close_and(function()
                    table.remove(family.social_groups, index)
                    self:saveFamilies()
                    back()
                end) },
                { text = _("Back"), id = "close", callback = close_and(back) },
            },
        },
    }
    UIManager:show(self._social_group_act_dialog)
end

function CharacterTracker:showSocialGroupMembers(family, index)
    local group = family.social_groups[index]
    if not group then return end
    local function back() self:showSocialGroupMembers(family, index) end
    local buttons = {}
    for i, name in ipairs(group.members) do
        table.insert(buttons, {
            { text = name, callback = function() end },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._social_group_members_dialog)
                    self._social_group_members_dialog = nil
                    table.remove(group.members, i)
                    self:saveFamilies()
                    back()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add member"),
            callback = function()
                UIManager:close(self._social_group_members_dialog)
                self._social_group_members_dialog = nil
                local present = {}
                for _i, name in ipairs(group.members) do present[name:lower()] = true end
                local choices = {}
                for _i, member in ipairs(family.members or {}) do
                    if member.name and not present[member.name:lower()] then
                        table.insert(choices, { label = member.name, value = member.name })
                    end
                end
                if #choices == 0 then
                    UIManager:show(InfoMessage:new{ text = _("Everyone is already in this group.") })
                    back()
                    return
                end
                self:_showChoice(T(_("Add to '%1'"), group.name or "?"), choices, function(name)
                    table.insert(group.members, name)
                    self:saveFamilies()
                    back()
                end)
            end,
        },
        {
            text = _("Done"),
            id = "close",
            callback = function()
                UIManager:close(self._social_group_members_dialog)
                self._social_group_members_dialog = nil
                self:showSocialGroupActions(family, index)
            end,
        },
    })
    self._social_group_members_dialog = ButtonDialog:new{
        title = T(_("Members of %1"), group.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._social_group_members_dialog)
end

function CharacterTracker:buildFamilyText(family)
    if family.tree_kind == "social" then return self:buildSocialText(family) end
    local parts = {}

    if family.motto and family.motto ~= "" then
        table.insert(parts, _("Motto") .. ": " .. family.motto .. "\n")
    end
    if family.seat and family.seat ~= "" then
        table.insert(parts, _("Seat") .. ": " .. family.seat .. "\n")
    end
    if family.sigil and family.sigil ~= "" then
        table.insert(parts, _("Sigil & colors") .. ": " .. family.sigil .. "\n")
    end
    if family.inheritance and family.inheritance ~= "" then
        table.insert(parts, _("Inheritance") .. ": " .. family.inheritance .. "\n")
    end

    if family.description and family.description ~= "" then
        table.insert(parts, "\n" .. family.description .. "\n")
    end

    if family.members and #family.members > 0 then
        local lines = {}
        for _i, member in ipairs(family.members) do
            local line = member.name or "?"
            if member.role and member.role ~= "" then
                line = line .. " — " .. member.role
            end
            if member.tie and member.tie ~= "" then
                line = line .. " · " .. member.tie
            end
            table.insert(lines, line)
        end
        table.insert(parts, pageBlock(T(_("Members (%1)"), #family.members), pageBullets(lines, "• ")))
    else
        table.insert(parts, "\n" .. _("No members added yet.") .. "\n")
    end

    if family.succession and #family.succession > 0 then
        local lines = {}
        for i, entry in ipairs(family.succession) do
            local line = i .. ". " .. (entry.name or "?")
            if entry.note and entry.note ~= "" then
                line = line .. " — " .. entry.note
            end
            table.insert(lines, line)
        end
        table.insert(parts, pageBlock(_("Line of succession"), pageBullets(lines, "")))
    end

    if family.traits and #family.traits > 0 then
        local lines = {}
        for _i, trait in ipairs(family.traits) do
            table.insert(lines, (trait.kind or _("Trait")) .. ": " .. (trait.text or ""))
        end
        table.insert(parts, pageBlock(T(_("Family traits (%1)"), #family.traits), pageBullets(lines, "• ")))
    end

    if family.houses and #family.houses > 0 then
        local lines = {}
        for _i, house in ipairs(family.houses) do
            local line = "• " .. describeHouse(house) .. "\n"
            for _j, note in ipairs(house.notes or {}) do
                line = line .. "  • " .. note .. "\n"
            end
            for _j, secret in ipairs(house.secrets or {}) do
                line = line .. "  • " .. _("Secret") .. ": " .. secret .. "\n"
            end
            table.insert(lines, line)
        end
        table.insert(parts, pageBlock(T(_("Alliances & houses (%1)"), #family.houses), table.concat(lines)))
    end

    if family.tree_kind == "social" and family.social_ties and #family.social_ties > 0 then
        local tie_lines = {}
        for _i, tie in ipairs(family.social_ties) do
            local line = self:_socialTieLabel(family, tie)
            if tie.notes and #tie.notes > 0 then line = line .. " — " .. table.concat(tie.notes, "; ") end
            table.insert(tie_lines, line)
        end
        table.insert(parts, pageBlock(T(_("Relationship ties (%1)"), #tie_lines), pageBullets(tie_lines, "• ")))
    end

    local linked = self:getLinkedFamilies(family)
    if #linked > 0 then
        local mine = {}
        for _i, m in ipairs(family.members or {}) do
            mine[lowerOrEmpty(m.name)] = true
        end
        local lines = {}
        for _i, other in ipairs(linked) do
            local shared = {}
            for _j, m in ipairs(other.members or {}) do
                if mine[lowerOrEmpty(m.name)] then table.insert(shared, m.name) end
            end
            table.insert(lines, (other.name or "?") .. " — " .. table.concat(shared, ", "))
        end
        table.insert(parts, pageBlock(T(_("Linked families (%1)"), #linked), pageBullets(lines, "• ")))
    end

    if family.holdings and #family.holdings > 0 then
        table.insert(parts, pageBlock(T(_("Holdings & titles (%1)"), #family.holdings), pageBullets(family.holdings, "• ")))
    end

    if family.history and #family.history > 0 then
        table.insert(parts, pageBlock(T(_("History (%1)"), #family.history), pageBullets(family.history, "• ")))
    end

    local succession_position = {}
    for i, entry in ipairs(family.succession or {}) do
        succession_position[lowerOrEmpty(entry.name)] = i
    end
    for _i, name in ipairs(self:getFamilySectionOrder(family)) do
        local member = memberByName(family, name)
        if member then
            local lines = {}
            local meta = {}
            if member.role and member.role ~= "" then table.insert(meta, member.role) end
            if member.tie and member.tie ~= "" then table.insert(meta, member.tie) end
            if #meta > 0 then
                table.insert(lines, table.concat(meta, " · ") .. "\n")
            end
            local position = succession_position[lowerOrEmpty(member.name)]
            if position then
                table.insert(lines, T(_("In line of succession: #%1"), position) .. "\n")
            end
            if member.parents and #member.parents > 0 then
                table.insert(lines, _("Parents") .. ": " .. table.concat(member.parents, ", ") .. "\n")
            end
            for _j, relation_entry in ipairs(self:_familyRelationEntries(family, member.name)) do
                local entry = "• " .. relation_entry.line .. "\n"
                for _k, rel in ipairs(relation_entry.rels) do
                    for _k, note in ipairs(rel.notes or {}) do
                        entry = entry .. "  • " .. note .. "\n"
                    end
                    for _k, secret in ipairs(rel.secrets or {}) do
                        entry = entry .. "  • " .. _("Secret") .. ": " .. secret .. "\n"
                    end
                end
                table.insert(lines, entry)
            end
            if #lines > 0 then
                table.insert(parts, pageBlock(member.name, table.concat(lines)))
            end
        end
    end

    if family.secrets and #family.secrets > 0 then
        table.insert(parts, pageBlock(T(_("Family secrets (%1)"), #family.secrets), pageBullets(family.secrets, "• ")))
    end

    if family.notes and #family.notes > 0 then
        table.insert(parts, pageBlock(T(_("Notes (%1)"), #family.notes), pageBullets(family.notes, "• ")))
    end

    return (table.concat(parts):gsub("^\n+", ""))
end

function CharacterTracker:getDefaultCoupleStyle()
    local value = G_reader_settings and G_reader_settings:readSetting("character_tracker_parent_line_default")
    for _i, st in ipairs(COUPLE_STYLES) do
        if st.key == value then return value end
    end
    return "partners"
end

function CharacterTracker:getCoupleStyle(family, g, a, b)
    local key = coupleKey(a, b)
    local own = family.couple_styles and family.couple_styles[key]
    if own and own ~= "" then return own end
    if g and g.explicit[key] then return g.explicit[key] end
    return self:getDefaultCoupleStyle()
end

function CharacterTracker:getTreeFontSize(kind)
    local value = G_reader_settings and tonumber(G_reader_settings:readSetting("character_tracker_tree_size_" .. kind))
    if not value then return TREE_FONT_DEFAULTS[kind] end
    return math.max(8, math.min(40, math.floor(value)))
end

function CharacterTracker:isTreeGenerationsHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tree_hide_generations")
end

function CharacterTracker:getTreeHoldAction()
    if G_reader_settings ~= nil
       and G_reader_settings:isTrue("character_tracker_tree_hold_branch") then
        return "branch"
    end
    return "focus"
end

function CharacterTracker:isTreeFocusLabelOnly()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tree_focus_label_only")
end

function CharacterTracker:getTreeFocusDepth()
    local value = G_reader_settings and tonumber(G_reader_settings:readSetting("character_tracker_tree_focus_depth"))
    if not value then return 2 end
    return math.max(1, math.min(8, math.floor(value)))
end

function CharacterTracker:isTimelineShotHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_timeline_hide_shot")
end

function CharacterTracker:showLineMeaningsDialog(on_done, view)
    local visual_names = {
        double = _("double"), solid = _("solid"), dashed = _("dashed"), dotted = _("dotted"),
        thin = _("thin"), thick = _("thick"), dashdot = _("dash-dot"), wavy = _("wavy"),
    }
    local function reshow()
        UIManager:close(self._line_meanings_dialog)
        self._line_meanings_dialog = nil
        if view then view:rebuild(view.scale) end
        self:showLineMeaningsDialog(on_done, view)
    end
    local function store(updated)
        if G_reader_settings then
            G_reader_settings:saveSetting("character_tracker_line_meanings", updated)
        end
    end
    local function current_table()
        local saved = G_reader_settings and G_reader_settings:readSetting("character_tracker_line_meanings")
        local copy = {}
        if type(saved) == "table" then
            for k, v in pairs(saved) do copy[k] = v end
        end
        return copy
    end
    local buttons = {}
    for _i, def in ipairs(LINE_MEANING_KEYS) do
        table.insert(buttons, {
            {
                text = shorten(def.group .. " · " .. visual_names[def.visual] .. ": " .. lineMeaning(def.key), 46),
                callback = function()
                    UIManager:close(self._line_meanings_dialog)
                    self._line_meanings_dialog = nil
                    local dialog
                    dialog = InputDialog:new{
                        title = T(_("What does the %1 line mean? (%2)"), visual_names[def.visual], def.group),
                        input = lineMeaning(def.key),
                        input_hint = LINE_MEANING_DEFAULTS[def.key],
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                        reshow()
                                    end,
                                },
                                {
                                    text = _("Reset"),
                                    callback = function()
                                        UIManager:close(dialog)
                                        local updated = current_table()
                                        updated[def.key] = nil
                                        store(updated)
                                        reshow()
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        local text = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        local updated = current_table()
                                        updated[def.key] = text ~= "" and text or nil
                                        store(updated)
                                        reshow()
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end,
            },
        })
    end
    table.insert(buttons, {
        { text = _("Reset all"), callback = function()
            store({})
            reshow()
        end },
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._line_meanings_dialog)
            self._line_meanings_dialog = nil
            if on_done then on_done() end
        end },
    })
    self._line_meanings_dialog = ButtonDialog:new{
        title = _("What each kind of line means\n(tap one to rename it)"),
        buttons = buttons,
    }
    UIManager:show(self._line_meanings_dialog)
end

function CharacterTracker:isSocialSyncOn()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_social_sync")
end

local BUTTON_AREAS = {
    { key = "character_edit", label = _("Character page (edit)") },
    { key = "character_read", label = _("Character page (read-only)") },
    { key = "search_result", label = _("Character from search") },
    { key = "place", label = _("Place page") },
    { key = "place_more", label = _("Place — More menu") },
    { key = "compendium", label = _("Compendium page") },
    { key = "compendium_more", label = _("Compendium — More menu") },
    { key = "family", label = _("Family / relationship page") },
    { key = "family_more", label = _("Family / relationship — More menu") },
    { key = "timeline_event", label = _("Timeline event page") },
    { key = "timeline_more", label = _("Timeline — More menu") },
    { key = "tree_person", label = _("Tapping a character in a tree") },
    { key = "tree_line", label = _("Tapping a line in a family tree") },
    { key = "tie_info", label = _("Tapping a line in a relationship tree") },
}

function CharacterTracker:getButtonLayout(area, default_mode, default_count)
    local saved = LayoutSettings and LayoutSettings:readSetting("character_tracker_button_layouts")
    local entry = type(saved) == "table" and saved[area] or nil
    if type(entry) == "table" then
        if entry.mode == "default" then return default_mode, default_count end
        if entry.mode == "per_row" or entry.mode == "rows" then
            return entry.mode, math.max(1, math.min(8, math.floor(tonumber(entry.count) or 2)))
        end
    end
    return default_mode, default_count
end

function CharacterTracker:layoutButtons(area, rows, default_mode, default_count)
    local mode, count = self:getButtonLayout(area, default_mode, default_count)
    if not mode or type(rows) ~= "table" then return rows end
    local flat, closers = {}, {}
    for _i, row in ipairs(rows) do
        for _j, button in ipairs(row) do
            if button.id == "close" then
                table.insert(closers, button)
            else
                table.insert(flat, button)
            end
        end
    end
    local total = #flat
    local row_count
    if mode == "rows" then
        row_count = math.min(math.max(1, count), math.max(1, total))
    else
        row_count = math.ceil(total / math.max(1, count))
    end
    local base = total > 0 and math.floor(total / row_count) or 0
    local extra = total > 0 and total % row_count or 0
    local packed, position = {}, 1
    for r = 1, row_count do
        local size = base + (r <= extra and 1 or 0)
        local pack_row = {}
        for _i = 1, size do
            table.insert(pack_row, flat[position])
            position = position + 1
        end
        if #pack_row > 0 then table.insert(packed, pack_row) end
    end
    if #closers > 0 then table.insert(packed, closers) end
    return packed
end

function CharacterTracker:newTextViewer(area, default_mode, default_count)
    return function(opts)
        opts.buttons_table = self:layoutButtons(area, opts.buttons_table, default_mode, default_count)
        return TextViewer:new(opts)
    end
end

function CharacterTracker:newButtonDialog(area, default_mode, default_count)
    return function(opts)
        opts.buttons = self:layoutButtons(area, opts.buttons, default_mode, default_count)
        return ButtonDialog:new(opts)
    end
end

function CharacterTracker:showButtonLayoutDialog(area, label, on_done)
    local default_mode, default_count
    if area == "tree_person" then default_mode, default_count = "per_row", 2 end
    local mode, count = self:getButtonLayout(area, default_mode, default_count)
    local saved = LayoutSettings and LayoutSettings:readSetting("character_tracker_button_layouts")
    local explicit = type(saved) == "table" and type(saved[area]) == "table" and saved[area].mode ~= "default"
    local function save(new_mode, new_count)
        if not G_reader_settings then return end
        local updated = {}
        if type(saved) == "table" then
            for k, v in pairs(saved) do updated[k] = v end
        end
        updated[area] = { mode = new_mode, count = new_count }
        LayoutSettings:saveSetting("character_tracker_button_layouts", updated)
    end
    local function pick_number(new_mode, title, numbers)
        local choices = {}
        for _i, number in ipairs(numbers) do
            table.insert(choices, {
                label = ((mode == new_mode and count == number) and "✓ " or "") .. tostring(number),
                value = number,
            })
        end
        self:_showChoice(title, choices, function(number)
            save(new_mode, number)
            if on_done then on_done() end
        end)
    end
    self:_showChoice(label, {
        { label = ((not explicit) and "✓ " or "") .. _("Default"), value = "default" },
        { label = (explicit and mode == "per_row" and count == 1 and "✓ " or "") .. _("One button per row"), value = "single" },
        { label = (explicit and mode == "per_row" and count > 1 and "✓ " or "") .. _("Choose buttons per row (rows are evened out)"), value = "per_row" },
        { label = (explicit and mode == "rows" and "✓ " or "") .. _("Choose number of rows"), value = "rows" },
    }, function(choice)
        if choice == "default" then
            save("default", 0)
            if on_done then on_done() end
        elseif choice == "single" then
            save("per_row", 1)
            if on_done then on_done() end
        elseif choice == "per_row" then
            pick_number("per_row", _("How many buttons in each row?"), { 2, 3, 4, 5, 6 })
        else
            pick_number("rows", _("How many rows of buttons?"), { 1, 2, 3, 4, 5, 6 })
        end
    end)
end

local LIST_BADGES = {
    { key = "occupation", label = _("Occupation") },
    { key = "type", label = _("Character type") },
    { key = "factions", label = _("Factions") },
    { key = "aliases", label = _("Aliases") },
    { key = "relations", label = _("Relations count") },
    { key = "notes", label = _("Notes count") },
}

function CharacterTracker:getListBadgeLayout()
    local saved = LayoutSettings and LayoutSettings:readSetting("character_tracker_list_badges")
    local valid = {}
    for _i, badge in ipairs(LIST_BADGES) do valid[badge.key] = true end
    local order, seen, hidden = {}, {}, {}
    if type(saved) == "table" then
        for _i, key in ipairs(saved.order or {}) do
            if valid[key] and not seen[key] then
                seen[key] = true
                order[#order + 1] = key
            end
        end
        for key, value in pairs(saved.hidden or {}) do
            if valid[key] and value then hidden[key] = true end
        end
    end
    for _i, badge in ipairs(LIST_BADGES) do
        if not seen[badge.key] then order[#order + 1] = badge.key end
    end
    return order, hidden
end

function CharacterTracker:showListBadgesDialog()
    local labels = {}
    for _i, badge in ipairs(LIST_BADGES) do labels[badge.key] = badge.label end
    local order, hidden = self:getListBadgeLayout()
    local function save()
        if G_reader_settings then
            LayoutSettings:saveSetting("character_tracker_list_badges", { order = order, hidden = hidden })
        end
    end
    local function reshow()
        UIManager:close(self._list_badges_dialog)
        self._list_badges_dialog = nil
        self:showListBadgesDialog()
    end
    local buttons = {}
    for i, key in ipairs(order) do
        table.insert(buttons, {
            { text = "▲", callback = function()
                if i > 1 then
                    order[i], order[i - 1] = order[i - 1], order[i]
                    save()
                end
                reshow()
            end },
            { text = labels[key] .. (hidden[key] and (" (" .. _("hidden") .. ")") or ""), callback = function() end },
            { text = "▼", callback = function()
                if i < #order then
                    order[i], order[i + 1] = order[i + 1], order[i]
                    save()
                end
                reshow()
            end },
            { text = hidden[key] and _("Show") or _("Hide"), callback = function()
                hidden[key] = (not hidden[key]) or nil
                save()
                reshow()
            end },
        })
    end
    table.insert(buttons, {
        { text = _("Reset to default"), callback = function()
            if LayoutSettings then LayoutSettings:delSetting("character_tracker_list_badges") end
            reshow()
        end },
        { text = _("Close"), id = "close", callback = function()
            UIManager:close(self._list_badges_dialog)
            self._list_badges_dialog = nil
        end },
    })
    self._list_badges_dialog = ButtonDialog:new{
        title = _("Details next to each name in the character list\n▲ / ▼ to move · Hide or Show each one"),
        buttons = buttons,
    }
    UIManager:show(self._list_badges_dialog)
end

function CharacterTracker:isSocialLabelsOn()
    return G_reader_settings == nil
        or G_reader_settings:readSetting("character_tracker_social_labels") ~= false
end

function CharacterTracker:isSocialShowFamily()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_social_show_family")
end

local function socialTieType(tie)
    if tie.kind == "custom" then return nil end
    return tieKind(tie.kind).rel
end

function CharacterTracker:_mirrorSocialTie(tie, skip_save)
    if not self:isSocialSyncOn() or not tie then return false end
    local rel_type = socialTieType(tie)
    if not rel_type then return false end
    local owner = self:getCharacterByName(tie.from)
    local target = self:getCharacterByName(tie.to)
    if not owner or not target or owner == target then return false end
    if type(owner.relationships) ~= "table" then owner.relationships = {} end
    for _i, existing in ipairs(owner.relationships) do
        if (existing.target or ""):lower() == target.name:lower() and (existing.type or "") == rel_type then
            return false
        end
    end
    table.insert(owner.relationships, { target = target.name, type = rel_type, sentiment = "" })
    if not skip_save then self:saveData() end
    return true
end

function CharacterTracker:_unmirrorSocialTie(tie)
    if not self:isSocialSyncOn() or not tie then return end
    local owner = self:getCharacterByName(tie.from)
    if not owner or type(owner.relationships) ~= "table" then return end
    local rel_type = socialTieType(tie)
    if not rel_type then return end
    for i = #owner.relationships, 1, -1 do
        local existing = owner.relationships[i]
        if (existing.target or ""):lower() == (tie.to or ""):lower() and (existing.type or "") == rel_type then
            table.remove(owner.relationships, i)
            self:saveData()
            return
        end
    end
end

function CharacterTracker:toggleSocialSync()
    if not G_reader_settings then return end
    local enable = not self:isSocialSyncOn()
    G_reader_settings:saveSetting("character_tracker_social_sync", enable)
    if enable then
        local added = 0
        for _i, family in ipairs(self.families or {}) do
            for _j, tie in ipairs(family.social_ties or {}) do
                if self:_mirrorSocialTie(tie, true) then added = added + 1 end
            end
        end
        if added > 0 then self:saveData() end
        UIManager:show(InfoMessage:new{
            text = T(_("Relationship tree ties will also appear in the character list. %1 added."), added),
            timeout = 2,
        })
    end
end

function CharacterTracker:buildSocialStub(family)
    local stub = {
        name = family.name, real = family, members = {}, relations = {}, placeholders = {},
        couple_styles = {}, guest_of = {}, extra_parents = {},
        tree_flags = { generations = false },
        tree_sizes = {
            first = self:getTreeFontSize("first"),
            last = self:getTreeFontSize("last"),
            info = self:getTreeFontSize("info"),
        },
    }
    for _i, m in ipairs(family.members or {}) do
        table.insert(stub.members, {
            name = m.name, role = m.role, title = m.title, first_name = m.first_name,
            last_name = m.last_name, gender = m.gender, tie = m.tie, parents = {},
        })
    end
    return stub
end

function CharacterTracker:_socialTieLabel(family, tie)
    local joint = tie.oneway and " → " or " — "
    return (tie.from or "?") .. joint .. tieInfo(tie).label .. joint .. (tie.to or "?")
end

function CharacterTracker:_chooseTieReceiver(tie, on_pick)
    self:_showChoice(T(_("Who receives the feeling in the relationship between '%1' and '%2'?"), tie.from or "?", tie.to or "?"), {
        { label = T(_("%1 receives it"), tie.to or "?"), value = false },
        { label = T(_("%1 receives it"), tie.from or "?"), value = true },
    }, on_pick)
end

function CharacterTracker:_chooseTieDirection(from, to, on_pick)
    self:_showChoice(T(_("Which way does the feeling go between '%1' and '%2'?"), from, to), {
        { label = _("Both ways (mutual)"), value = "both" },
        { label = T(_("%1 → %2 only"), shorten(from, 14), shorten(to, 14)), value = "forward" },
        { label = T(_("%1 → %2 only"), shorten(to, 14), shorten(from, 14)), value = "backward" },
    }, on_pick)
end

function CharacterTracker:importSocialTiesFromCharacters(family)
    if type(family.social_ties) ~= "table" then family.social_ties = {} end
    local rel_to_kind = { partner = "dating" }
    for _i, kind in ipairs(TIE_KINDS) do
        if not rel_to_kind[kind.rel] then rel_to_kind[kind.rel] = kind.key end
    end
    local type_category = {}
    for _i, rt in ipairs(RELATIONSHIP_TYPES) do type_category[rt.key] = rt.category end
    local member_name = {}
    for _i, member in ipairs(family.members or {}) do
        if member.name then member_name[member.name:lower()] = member.name end
    end
    local function exists(from, to, kind, custom_name)
        for _i, tie in ipairs(family.social_ties) do
            local same = tie.kind == kind and (kind ~= "custom" or (tie.custom and tie.custom.name == custom_name))
            if same then
                local f, t = lowerOrEmpty(tie.from), lowerOrEmpty(tie.to)
                if f == from:lower() and t == to:lower() then return true end
                if not tie.oneway and f == to:lower() and t == from:lower() then return true end
            end
        end
        return false
    end
    local function reciprocal(owner_name, target_name, rel_type)
        local other = self:getCharacterByName(target_name)
        for _i, rel in ipairs(other and other.relationships or {}) do
            if lowerOrEmpty(rel.target) == owner_name:lower() and rel.type == rel_type then return true end
        end
        return false
    end
    local added = 0
    for _i, member in ipairs(family.members or {}) do
        local owner = self:getCharacterByName(member.name)
        for _j, rel in ipairs(owner and owner.relationships or {}) do
            local target = member_name[lowerOrEmpty(rel.target)]
            local rel_type = rel.type or ""
            local usable = type_category[rel_type] == "social" or rel_type == "partner" or rel_type == "spouse" or rel_type == "ex"
            if target and usable and target:lower() ~= member.name:lower() then
                local kind = rel_to_kind[rel_type] or "custom"
                local custom
                if kind == "custom" then custom = { name = getRelationshipLabel(rel_type), visual = "solid" } end
                if not exists(member.name, target, kind, custom and custom.name) then
                    local mutual = reciprocal(member.name, target, rel_type)
                    if not (mutual and member.name:lower() > target:lower()) then
                        table.insert(family.social_ties, {
                            from = member.name, to = target, kind = kind, custom = custom,
                            oneway = (not mutual) or nil,
                        })
                        added = added + 1
                    end
                end
            end
        end
    end
    self:saveFamilies()
    return added
end

function CharacterTracker:_chooseCustomTie(title, family, on_pick)
    local seen, choices = {}, {}
    for _i, tie in ipairs(family and family.social_ties or {}) do
        if tie.kind == "custom" and type(tie.custom) == "table" and tie.custom.name then
            local id = tie.custom.name:lower() .. "|" .. (tie.custom.visual or "solid")
            if not seen[id] then
                seen[id] = true
                table.insert(choices, {
                    label = shorten(tie.custom.name .. " (" .. (TIE_VISUAL_LABELS[tie.custom.visual] or "") .. ")", 30),
                    value = tie.custom,
                })
            end
        end
    end
    table.insert(choices, { label = _("+ New custom type"), value = false })
    self:_showChoice(title, choices, function(existing)
        if existing then
            on_pick("custom", { name = existing.name, visual = existing.visual })
            return
        end
        local dialog
        dialog = InputDialog:new{
            title = _("Name of this relationship type"),
            input_hint = _("e.g. blood brothers, old flame, business partners"),
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function()
                            UIManager:close(dialog)
                        end,
                    },
                    {
                        text = _("Next"),
                        is_enter_default = true,
                        callback = function()
                            local name = trim(dialog:getInputText())
                            UIManager:close(dialog)
                            if name == "" then return end
                            local visuals = {}
                            for _i, visual in ipairs(TIE_VISUALS) do
                                table.insert(visuals, { label = TIE_VISUAL_LABELS[visual], value = visual })
                            end
                            self:_showChoice(T(_("Which line for '%1'?"), name), visuals, function(visual)
                                on_pick("custom", { name = name, visual = visual })
                            end)
                        end,
                    },
                },
            },
        }
        self:_showInputDialog(dialog)
    end)
end

function CharacterTracker:_chooseTieKind(title, current, on_pick, family)
    local function kinds_of(romance)
        local choices = {}
        for _i, kind in ipairs(TIE_KINDS) do
            if (kind.romance == true) == romance then
                table.insert(choices, {
                    label = (current == kind.key and "✓ " or "") .. shorten(tieKindMeaning(kind.key), 28),
                    value = kind.key,
                })
            end
        end
        return choices
    end
    self:_showChoice(title, {
        { label = _("Friendship & bonds"), value = "bonds" },
        { label = _("Romance"), value = "romance" },
        { label = (current == "custom" and "✓ " or "") .. _("Custom"), value = "custom" },
    }, function(group)
        if group == "custom" then
            self:_chooseCustomTie(title, family, on_pick)
            return
        end
        self:_showChoice(title, kinds_of(group == "romance"), function(kind)
            on_pick(kind, nil)
        end)
    end)
end

function CharacterTracker:showTieKindGuide()
    local visual_names = {
        solid = _("solid line"), thin = _("thin line"), thick = _("thick line"), double = _("double line"),
        dashed = _("dashed line"), dotted = _("dotted line"), dashdot = _("dash-dot line"), wavy = _("wavy line"),
    }
    local parts = {}
    for _i, romance in ipairs({ false, true }) do
        table.insert(parts, (romance and _("Romance") or _("Friendship & bonds")) .. "\n")
        for _j, kind in ipairs(TIE_KINDS) do
            if (kind.romance == true) == romance then
                table.insert(parts, "• " .. tieKindMeaning(kind.key) .. " (" .. visual_names[kind.visual] .. ")\n  " .. kind.desc .. "\n")
            end
        end
        table.insert(parts, "\n")
    end
    UIManager:show(TextViewer:new{
        title = _("Relationship types"),
        text = table.concat(parts),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
    })
end

function CharacterTracker:showFamilySocialTiesManager(family, view)
    if type(family.social_ties) ~= "table" then family.social_ties = {} end
    local function refresh()
        if view then view:rebuild(view.scale) end
    end
    local function back() self:showFamilySocialTiesManager(family, view) end
    local buttons = {}
    for i, tie in ipairs(family.social_ties) do
        local extras = #(tie.notes or {}) + #(tie.secrets or {})
        table.insert(buttons, {
            {
                text = shorten(self:_socialTieLabel(family, tie), 42) .. (extras > 0 and (" ✎" .. extras) or ""),
                callback = function()
                    UIManager:close(self._social_ties_dialog)
                    self._social_ties_dialog = nil
                    self:showSocialTieActions(family, i, view)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._social_ties_dialog)
                    self._social_ties_dialog = nil
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete this tie?\n\n%1"), self:_socialTieLabel(family, tie)),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            self:_unmirrorSocialTie(tie)
                            table.remove(family.social_ties, i)
                            self:saveFamilies()
                            refresh()
                            back()
                        end,
                        cancel_callback = back,
                    })
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add tie"),
            callback = function()
                UIManager:close(self._social_ties_dialog)
                self._social_ties_dialog = nil
                if not family.members or #family.members < 2 then
                    UIManager:show(InfoMessage:new{ text = _("Add at least two members to the family first.") })
                    back()
                    return
                end
                self:_showChoice(_("Tie from…"), memberChoices(family, nil), function(from)
                    self:_showChoice(T(_("Tie from '%1' to…"), from), memberChoices(family, from), function(to)
                        self:_chooseTieKind(T(_("How are '%1' and '%2' connected?"), from, to), nil, function(kind, custom)
                            self:_chooseTieDirection(from, to, function(direction)
                                local tie = { from = from, to = to, kind = kind, custom = custom }
                                if direction == "forward" then
                                    tie.oneway = true
                                elseif direction == "backward" then
                                    tie.from, tie.to, tie.oneway = to, from, true
                                end
                                table.insert(family.social_ties, tie)
                                self:_mirrorSocialTie(tie)
                                self:saveFamilies()
                                refresh()
                                back()
                            end)
                        end, family)
                    end)
                end)
            end,
        },
        {
            text = _("Line meanings"),
            callback = function()
                UIManager:close(self._social_ties_dialog)
                self._social_ties_dialog = nil
                self:showLineMeaningsDialog(function()
                    refresh()
                    back()
                end, view)
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Import from character list"),
            callback = function()
                local added = self:importSocialTiesFromCharacters(family)
                UIManager:close(self._social_ties_dialog)
                self._social_ties_dialog = nil
                UIManager:show(InfoMessage:new{
                    text = added > 0 and T(_("%1 tie(s) added from the character list."), added)
                        or _("Nothing new to import. Add friends, rivals and so on on a character's page first."),
                    timeout = 3,
                })
                refresh()
                back()
            end,
        },
        {
            text = _("Relationship types guide"),
            callback = function()
                self:showTieKindGuide()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._social_ties_dialog)
                self._social_ties_dialog = nil
                if not view then self:showFamilyDetail(family) end
            end,
        },
    })
    self._social_ties_dialog = ButtonDialog:new{
        title = T(_("Relationship ties — %1"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._social_ties_dialog)
end

function CharacterTracker:_createSocialTie(family, view, from, to)
    if type(family.social_ties) ~= "table" then family.social_ties = {} end
    self:_chooseTieKind(T(_("How are '%1' and '%2' connected?"), from, to), nil, function(kind, custom)
        self:_chooseTieDirection(from, to, function(direction)
            local tie = { from = from, to = to, kind = kind, custom = custom }
            if direction == "forward" then
                tie.oneway = true
            elseif direction == "backward" then
                tie.from, tie.to, tie.oneway = to, from, true
            end
            table.insert(family.social_ties, tie)
            self:_mirrorSocialTie(tie)
            self:saveFamilies()
            view:rebuild(view.scale)
        end)
    end, family)
end

function CharacterTracker:_addSocialTieFrom(family, view, from)
    if type(family.social_ties) ~= "table" then family.social_ties = {} end
    local vf = view.vf or family
    if not vf.members or #vf.members < 2 then
        UIManager:show(InfoMessage:new{ text = _("Add at least two members to the family first.") })
        return
    end
    self:_showChoice(T(_("Tie from '%1' to…"), from), memberChoices(vf, from), function(to)
        self:_createSocialTie(family, view, from, to)
    end)
end

function CharacterTracker:_addFamilyRelationFrom(family, view, from)
    local vf = view.vf or family
    if not vf.members or #vf.members < 2 then
        UIManager:show(InfoMessage:new{ text = _("Add at least two members to the family first.") })
        return
    end
    self:_showChoice(T(_("Add relationship from '%1' to…"), from), memberChoices(vf, from), function(to)
        self:_showChoice(T(_("'%1' is ___ of '%2'"), to, from), relationChoices(), function(rel_type)
            self:_commitFamilyRelation(family, from, to, rel_type, "")
            view:rebuild(view.scale)
        end, { hint = _("A custom tag, e.g. rival — or \"Mentor / Student\" to name both directions") })
    end)
end

function CharacterTracker:showSocialTieActions(family, index, view)
    local tie = family.social_ties[index]
    if not tie then return end
    local function refresh()
        if view then view:rebuild(view.scale) end
    end
    local function back() self:showFamilySocialTiesManager(family, view) end
    local function close_and(fn)
        return function()
            UIManager:close(self._social_tie_act_dialog)
            self._social_tie_act_dialog = nil
            fn()
        end
    end
    self._social_tie_act_dialog = ButtonDialog:new{
        title = shorten(self:_socialTieLabel(family, tie), 60),
        buttons = {
            {
                { text = _("Change type"), callback = close_and(function()
                    self:_chooseTieKind(T(_("How are '%1' and '%2' connected?"), tie.from or "?", tie.to or "?"), tie.kind, function(kind, custom)
                        self:_unmirrorSocialTie(tie)
                        tie.kind = kind
                        tie.custom = custom
                        self:_mirrorSocialTie(tie)
                        self:saveFamilies()
                        refresh()
                        back()
                    end, family)
                end) },
                { text = T(_("Notes & secrets (%1)"), #(tie.notes or {}) + #(tie.secrets or {})), callback = close_and(function()
                    self:showEntryNotesSecrets(family, tie, self:_socialTieLabel(family, tie), function()
                        refresh()
                        back()
                    end)
                end) },
            },
            {
                { text = _("Direction"), callback = close_and(function()
                    self:_chooseTieDirection(tie.from or "?", tie.to or "?", function(direction)
                        self:_unmirrorSocialTie(tie)
                        if direction == "both" then
                            tie.oneway = nil
                        else
                            if direction == "backward" then tie.from, tie.to = tie.to, tie.from end
                            tie.oneway = true
                        end
                        self:_mirrorSocialTie(tie)
                        self:saveFamilies()
                        refresh()
                        back()
                    end)
                end) },
                { text = _("Swap direction"), callback = close_and(function()
                    self:_unmirrorSocialTie(tie)
                    tie.from, tie.to = tie.to, tie.from
                    self:_mirrorSocialTie(tie)
                    self:saveFamilies()
                    refresh()
                    back()
                end) },
            },
            {
                { text = tie.hide_line and _("Show line") or _("Hide line"), callback = close_and(function()
                    tie.hide_line = (not tie.hide_line) or nil
                    self:saveFamilies()
                    refresh()
                    back()
                end) },
                { text = _("Label position"), callback = close_and(function()
                    local from_name, to_name = shorten(tie.from or "?", 14), shorten(tie.to or "?", 14)
                    local function mark(value)
                        return tie.label_t == value and "✓ " or ""
                    end
                    self:_showChoice(_("Where on the line should the label sit?"), {
                        { label = (tie.label_t == nil and "✓ " or "") .. _("Centre (automatic)"), value = "auto" },
                        { label = mark(0.2) .. T(_("Near %1"), from_name), value = 0.2 },
                        { label = mark(0.35) .. T(_("Closer to %1"), from_name), value = 0.35 },
                        { label = mark(0.65) .. T(_("Closer to %1"), to_name), value = 0.65 },
                        { label = mark(0.8) .. T(_("Near %1"), to_name), value = 0.8 },
                    }, function(value)
                        tie.label_t = value ~= "auto" and value or nil
                        self:saveFamilies()
                        refresh()
                        back()
                    end)
                end) },
            },
            {
                { text = _("Delete"), callback = close_and(function()
                    self:_unmirrorSocialTie(tie)
                    table.remove(family.social_ties, index)
                    self:saveFamilies()
                    refresh()
                    back()
                end) },
                { text = _("Back"), id = "close", callback = close_and(back) },
            },
        },
    }
    UIManager:show(self._social_tie_act_dialog)
end

function CharacterTracker:showSocialTieInfo(family, view, info)
    local tie = family.social_ties and family.social_ties[info.index]
    if not tie then return end
    local lines = {
        (tie.from or "?") .. tieLink(tie) .. (tie.to or "?"),
        "",
        tieInfo(tie).label,
        tieInfo(tie).desc,
    }
    if tie.notes and #tie.notes > 0 then
        table.insert(lines, "")
        table.insert(lines, _("Notes"))
        for _i, note in ipairs(tie.notes) do table.insert(lines, "• " .. note) end
    end
    if tie.secrets and #tie.secrets > 0 then
        table.insert(lines, "")
        table.insert(lines, _("Secrets"))
        for _i, secret in ipairs(tie.secrets) do table.insert(lines, "• " .. secret) end
    end
    local viewer
    local function close_and(fn)
        return function()
            UIManager:close(viewer)
            fn()
        end
    end
    local buttons = {}
    local row = {
        { text = _("Notes & secrets"), callback = close_and(function()
            self:showEntryNotesSecrets(family, tie, self:_socialTieLabel(family, tie), function()
                self:showSocialTieInfo(family, view, info)
            end)
        end) },
    }
    if view.editing then
        table.insert(row, { text = _("Edit this tie"), callback = close_and(function()
            self:showSocialTieActions(family, info.index, view)
        end) })
        table.insert(buttons, row)
        table.insert(buttons, {
            { text = _("Reverse arrow"), callback = close_and(function()
                self:_unmirrorSocialTie(tie)
                tie.from, tie.to = tie.to, tie.from
                tie.oneway = true
                self:_mirrorSocialTie(tie)
                self:saveFamilies()
                view:rebuild(view.scale)
            end) },
            { text = tie.oneway and _("Make two-way") or _("Make one-way"), callback = close_and(function()
                if tie.oneway then
                    self:_unmirrorSocialTie(tie)
                    tie.oneway = nil
                    self:_mirrorSocialTie(tie)
                    self:saveFamilies()
                    view:rebuild(view.scale)
                    return
                end
                self:_chooseTieReceiver(tie, function(swap)
                    self:_unmirrorSocialTie(tie)
                    if swap then tie.from, tie.to = tie.to, tie.from end
                    tie.oneway = true
                    self:_mirrorSocialTie(tie)
                    self:saveFamilies()
                    view:rebuild(view.scale)
                end)
            end) },
        })
    else
        table.insert(buttons, row)
    end
    table.insert(buttons, {
        { text = _("Close"), id = "close", callback = close_and(function() end) },
    })
    viewer = self:newTextViewer("tie_info"){
        title = _("Relationship tie"),
        text = table.concat(lines, "\n"),
        width = math.floor(Device.screen:getWidth() * 0.85),
        height = math.floor(Device.screen:getHeight() * 0.45),
        buttons_table = buttons,
    }
    UIManager:show(viewer)
end

function CharacterTracker:_orderItems(family, person_key, items)
    local saved = type(family.rel_order) == "table" and family.rel_order[person_key] or nil
    local rank = {}
    for i, key in ipairs(saved or {}) do rank[key] = i end
    local indexed = {}
    for i, item in ipairs(items) do indexed[i] = { item = item, fallback = 1000 + i } end
    table.sort(indexed, function(a, b)
        return (rank[a.item.key] or a.fallback) < (rank[b.item.key] or b.fallback)
    end)
    local ordered = {}
    for i, entry in ipairs(indexed) do ordered[i] = entry.item end
    return ordered
end

function CharacterTracker:showRelOrderDialog(family, person_key, items, on_done)
    local function reshow()
        UIManager:close(self._rel_order_dialog)
        self._rel_order_dialog = nil
        self:showRelOrderDialog(family, person_key, items, on_done)
    end
    local ordered = self:_orderItems(family, person_key, items)
    local function save()
        if type(family.rel_order) ~= "table" then family.rel_order = {} end
        local keys = {}
        for i, item in ipairs(ordered) do keys[i] = item.key end
        family.rel_order[person_key] = keys
        self:saveFamilies()
    end
    local buttons = {}
    for i, item in ipairs(ordered) do
        table.insert(buttons, {
            { text = "▲", callback = function()
                if i > 1 then
                    ordered[i], ordered[i - 1] = ordered[i - 1], ordered[i]
                    save()
                end
                reshow()
            end },
            { text = shorten(item.label, 30), callback = function() end },
            { text = "▼", callback = function()
                if i < #ordered then
                    ordered[i], ordered[i + 1] = ordered[i + 1], ordered[i]
                    save()
                end
                reshow()
            end },
        })
    end
    table.insert(buttons, {
        { text = _("Reset order"), callback = function()
            if type(family.rel_order) == "table" then family.rel_order[person_key] = nil end
            self:saveFamilies()
            reshow()
        end },
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._rel_order_dialog)
            self._rel_order_dialog = nil
            if on_done then on_done() end
        end },
    })
    self._rel_order_dialog = ButtonDialog:new{
        title = _("Order of relationships (▲ / ▼ to move)"),
        buttons = buttons,
    }
    UIManager:show(self._rel_order_dialog)
end

function CharacterTracker:_socialPersonItems(family, name)
    local key = lowerOrEmpty(name)
    local others, order, total = {}, {}, 0
    for _i, tie in ipairs(family.social_ties or {}) do
        local from_key, to_key = lowerOrEmpty(tie.from), lowerOrEmpty(tie.to)
        if from_key == key or to_key == key then
            local other = from_key == key and tie.to or tie.from
            local other_key = lowerOrEmpty(other)
            if not others[other_key] then
                others[other_key] = { name = other or "?", ties = {} }
                order[#order + 1] = other_key
            end
            table.insert(others[other_key].ties, tie)
            total = total + 1
        end
    end
    local items = {}
    for _i, other_key in ipairs(order) do
        local entry = others[other_key]
        local lines = { "", T(_("With %1"), entry.name) }
        for _j, tie in ipairs(entry.ties) do
            local arrow
            if not tie.oneway then
                arrow = name .. " ↔ " .. entry.name
            elseif lowerOrEmpty(tie.from) == key then
                arrow = name .. " → " .. entry.name
            else
                arrow = entry.name .. " → " .. name
            end
            table.insert(lines, "• " .. tieInfo(tie).label .. " (" .. arrow .. ")")
            for _k, note in ipairs(tie.notes or {}) do table.insert(lines, "      – " .. note) end
            for _k, secret in ipairs(tie.secrets or {}) do
                table.insert(lines, "      – " .. _("(secret)") .. " " .. secret)
            end
        end
        table.insert(items, { key = "with:" .. other_key, label = T(_("With %1"), entry.name), lines = lines })
    end
    return items, total
end

function CharacterTracker:buildSocialPersonLines(family, name)
    local key = lowerOrEmpty(name)
    local items, total = self:_socialPersonItems(family, name)
    local lines = { "" }
    if total == 0 then
        table.insert(lines, _("No relationships yet."))
    else
        table.insert(lines, T(_("Relationships (%1)"), total))
        for _i, item in ipairs(self:_orderItems(family, key, items)) do
            for _j, line in ipairs(item.lines) do table.insert(lines, line) end
        end
    end
    local mentioned = {}
    for _i, dynamic in ipairs(family.dynamics or {}) do
        if dynamic:lower():find(key, 1, true) then table.insert(mentioned, dynamic) end
    end
    if #mentioned > 0 then
        table.insert(lines, "")
        table.insert(lines, T(_("Dynamics (%1)"), #mentioned))
        for _i, dynamic in ipairs(mentioned) do table.insert(lines, "• " .. dynamic) end
    end
    return lines
end

function CharacterTracker:buildCharacterTreeSections(character)
    local sections = {}
    for _i, family in ipairs(self.families or {}) do
        local member = memberByName(family, character.name)
        if member then
            if family.tree_kind == "social" then
                local lines = self:buildSocialPersonLines(family, member.name)
                if #lines > 2 or lines[2] ~= _("No relationships yet.") then
                    table.remove(lines, 1)
                    table.insert(sections, {
                        title = (family.name or "?") .. " (" .. _("relationship tree") .. ")",
                        body = table.concat(lines, "\n") .. "\n",
                    })
                end
            else
                local body = {}
                for _j, entry in ipairs(self:_familyRelationEntries(family, member.name)) do
                    local text
                    for _k, rel in ipairs(entry.rels) do
                        for _l, note in ipairs(rel.notes or {}) do
                            text = (text or ("• " .. entry.line .. "\n")) .. "      – " .. note .. "\n"
                        end
                        for _l, secret in ipairs(rel.secrets or {}) do
                            text = (text or ("• " .. entry.line .. "\n")) .. "      – " .. _("(secret)") .. " " .. secret .. "\n"
                        end
                    end
                    if text then table.insert(body, text) end
                end
                if #body > 0 then
                    table.insert(sections, { title = family.name or "?", body = table.concat(body) })
                end
            end
        end
    end
    return sections
end

function CharacterTracker:showAssignFamilyExcerpt(text, page)
    if not self.families or #self.families == 0 then
        UIManager:show(InfoMessage:new{ text = _("There are no families or relationships yet.") })
        return
    end
    local entry_text = "“" .. text .. "”"
    if page and page ~= "" then entry_text = entry_text .. " (p. " .. page .. ")" end
    local function done(label)
        self:saveFamilies()
        UIManager:show(InfoMessage:new{ text = T(_("Added to %1."), label), timeout = 2 })
    end
    local function append(list_owner, field, label)
        if type(list_owner[field]) ~= "table" then list_owner[field] = {} end
        table.insert(list_owner[field], entry_text)
        done(label)
    end
    local function pick_target(family)
        local choices = {}
        if family.tree_kind == "social" then
            for i, tie in ipairs(family.social_ties or {}) do
                table.insert(choices, {
                    label = shorten(self:_socialTieLabel(family, tie), 38),
                    value = { kind = "tie", index = i },
                })
            end
            table.insert(choices, { label = _("Dynamics (whole group)"), value = { kind = "list", field = "dynamics" } })
        else
            for i, rel in ipairs(family.relations or {}) do
                table.insert(choices, {
                    label = shorten(describeInnerRelation(rel), 38),
                    value = { kind = "relation", index = i },
                })
            end
            table.insert(choices, { label = _("History"), value = { kind = "list", field = "history" } })
        end
        table.insert(choices, { label = _("Notes"), value = { kind = "list", field = "notes" } })
        self:_showChoice(T(_("Add the selection to which part of '%1'?"), family.name or "?"), choices, function(target)
            if target.kind == "tie" then
                local tie = family.social_ties[target.index]
                if tie then append(tie, "notes", self:_socialTieLabel(family, tie)) end
            elseif target.kind == "relation" then
                local rel = family.relations[target.index]
                if rel then append(rel, "notes", describeInnerRelation(rel)) end
            else
                append(family, target.field, family.name or "?")
            end
        end)
    end
    local choices = {}
    for _i, family in ipairs(self.families) do
        table.insert(choices, {
            label = shorten((family.name or _("(unnamed)")) .. (family.tree_kind == "social" and (" · " .. _("relationship")) or ""), 38),
            value = family.id,
        })
    end
    if #choices == 1 then
        pick_target(self.families[1])
        return
    end
    self:_showChoice(_("Add the selection to which family or relationship?"), choices, function(id)
        local family = self:getFamilyById(id)
        if family then pick_target(family) end
    end)
end

function CharacterTracker:isTreeLegendOn()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tree_legend")
end

function CharacterTracker:isTreeShotHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tree_hide_shot")
end

function CharacterTracker:isTreeUnderlineHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tree_hide_underline")
end

function CharacterTracker:isTreeCombinedHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tree_hide_combined")
end

function CharacterTracker:getLinkedFamilies(family)
    local mine = {}
    for _i, m in ipairs(family.members or {}) do
        mine[lowerOrEmpty(m.name)] = true
    end
    local out = {}
    for _i, other in ipairs(self.families or {}) do
        if other ~= family then
            for _j, m in ipairs(other.members or {}) do
                if mine[lowerOrEmpty(m.name)] then
                    table.insert(out, other)
                    break
                end
            end
        end
    end
    return out
end

function CharacterTracker:buildCombinedFamily(family)
    local vf = {
        name = family.name, real = family,
        members = {}, relations = {}, placeholders = {}, couple_styles = {},
        guest_of = {}, extra_parents = {},
        tree_flags = { generations = not self:isTreeGenerationsHidden() },
        tree_sizes = {
            first = self:getTreeFontSize("first"),
            last = self:getTreeFontSize("last"),
            info = self:getTreeFontSize("info"),
        },
    }
    local seen_member, seen_placeholder = {}, {}
    local function addFrom(source, guest)
        for _i, m in ipairs(source.members or {}) do
            local key = lowerOrEmpty(m.name)
            if key ~= "" then
                if not seen_member[key] then
                    seen_member[key] = true
                    table.insert(vf.members, m)
                    if guest then vf.guest_of[key] = source.name end
                elseif guest then
                    for _j, p in ipairs(m.parents or {}) do
                        vf.extra_parents[key] = vf.extra_parents[key] or {}
                        table.insert(vf.extra_parents[key], p)
                    end
                end
            end
        end
        for _i, rel in ipairs(source.relations or {}) do
            table.insert(vf.relations, rel)
        end
        for _i, ph in ipairs(source.placeholders or {}) do
            local key = lowerOrEmpty(ph.name)
            if not seen_placeholder[key] then
                seen_placeholder[key] = true
                table.insert(vf.placeholders, ph)
            end
        end
        for key, style in pairs(source.couple_styles or {}) do
            if vf.couple_styles[key] == nil then vf.couple_styles[key] = style end
        end
    end
    addFrom(family, false)
    if not self:isTreeCombinedHidden() then
        local excluded = family.tree_excluded or {}
        for _i, other in ipairs(self:getLinkedFamilies(family)) do
            if not excluded[other.id] then addFrom(other, true) end
        end
    end
    if self:isRelationSyncOn() then
        local present = {}
        for _i, rel in ipairs(vf.relations) do
            present[lowerOrEmpty(rel.from) .. "|" .. lowerOrEmpty(rel.to) .. "|" .. (rel.type or "")] = true
        end
        for _i, m in ipairs(vf.members) do
            local char = self:getCharacterByName(m.name)
            for _j, r in ipairs(char and char.relationships or {}) do
                if r.target and r.type and r.type ~= "" and seen_member[lowerOrEmpty(r.target)] then
                    local id = lowerOrEmpty(char.name) .. "|" .. lowerOrEmpty(r.target) .. "|" .. r.type
                    if not present[id] then
                        present[id] = true
                        table.insert(vf.relations, {
                            from = char.name, to = r.target, type = r.type, sentiment = r.sentiment or "",
                            notes = {}, secrets = {},
                        })
                    end
                end
            end
        end
    end
    return vf
end

function CharacterTracker:_renameParentKind(member, old_name, new_name)
    local kinds = member.parent_kinds
    if type(kinds) ~= "table" then return end
    local old = lowerOrEmpty(old_name)
    if kinds[old] then
        kinds[lowerOrEmpty(new_name)] = kinds[old]
        kinds[old] = nil
    end
end

function CharacterTracker:_findMemberOwner(member)
    for _i, fam in ipairs(self.families or {}) do
        for j, m in ipairs(fam.members or {}) do
            if m == member then return fam, j end
        end
    end
    return nil, nil
end

function CharacterTracker:_findPlaceholderOwner(name)
    for _i, fam in ipairs(self.families or {}) do
        local ph = placeholderByName(fam, name)
        if ph then return fam, ph end
    end
    return nil, nil
end

function CharacterTracker:_renameCoupleStyleKeys(family, old_name, new_name)
    if type(family.couple_styles) ~= "table" then return end
    local old, new = lowerOrEmpty(old_name), lowerOrEmpty(new_name)
    local moves = {}
    for key, style in pairs(family.couple_styles) do
        local a, b = key:match("^(.*)|(.*)$")
        if a == old or b == old then
            if a == old then a = new end
            if b == old then b = new end
            table.insert(moves, { old_key = key, new_key = coupleKey(a, b), style = style })
        end
    end
    for _i, move in ipairs(moves) do
        family.couple_styles[move.old_key] = nil
    end
    for _i, move in ipairs(moves) do
        family.couple_styles[move.new_key] = move.style
    end
end

function CharacterTracker:_familyRelationEntries(family, member_name, only_other)
    local key = lowerOrEmpty(member_name)
    local only = only_other and lowerOrEmpty(only_other) or nil
    local by_target, bucket_order = {}, {}
    local function bucket(other)
        local k = other:lower()
        if not by_target[k] then
            by_target[k] = { name = other, out_types = {}, in_types = {},
                             out_sent = {}, in_sent = {}, rels = {} }
            table.insert(bucket_order, k)
        end
        return by_target[k]
    end
    for _i, rel in ipairs(family.relations or {}) do
        local b
        local outgoing = lowerOrEmpty(rel.from) == key
        if outgoing then
            if not only or lowerOrEmpty(rel.to) == only then b = bucket(rel.to or "?") end
        elseif lowerOrEmpty(rel.to) == key then
            if not only or lowerOrEmpty(rel.from) == only then b = bucket(rel.from or "?") end
        end
        if b then
            local types = outgoing and b.out_types or b.in_types
            local sents = outgoing and b.out_sent or b.in_sent
            if rel.type and rel.type ~= "" then types[rel.type] = true end
            if rel.sentiment and rel.sentiment ~= "" then sents[rel.sentiment] = true end
            table.insert(b.rels, rel)
        end
    end
    local formatted = self:_formatRelationBuckets(bucket_order, by_target)
    local entries = {}
    for n, k in ipairs(bucket_order) do
        table.insert(entries, { line = formatted[n], rels = by_target[k].rels })
    end
    return entries
end

function CharacterTracker:showFamilyTreeNameDialog(family, member, on_done)
    local first, last = treeNameParts(member)
    local char = self:getCharacterByName(member.name)
    local dialog
    dialog = MultiInputDialog:new{
        title = T(_("Tree name — %1"), member.name or "?"),
        fields = {
            {
                text = first,
                hint = _("First name"),
            },
            {
                text = last,
                hint = _("Last name (shown smaller, under the first name)"),
            },
            {
                text = member.title or "",
                hint = (char and char.occupation and char.occupation ~= "") and char.occupation
                    or _("Occupation title (shown small, under the person)"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        UIManager:close(dialog)
                        member.first_name = trim(fields[1])
                        member.last_name = trim(fields[2])
                        member.title = trim(fields[3])
                        self:saveFamilies()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showFamilyTree(family, read_only)
    if not buildFamilyGraph(family) then
        UIManager:show(InfoMessage:new{
            text = _("Add members first - the tree is built from each member's parents, plus any father / mother / son / daughter / sibling / spouse relationships."),
        })
        return
    end
    UIManager:show(FamilyTreeView:new{ tracker = self, family = family, read_only = read_only })
end

function CharacterTracker:_familyPairText(family, g, ka, kb)
    local lines = {}
    if not (g.plain[ka] and g.plain[kb]) then return lines end
    for _i, entry in ipairs(self:_familyRelationEntries(family, g.canon[ka], g.canon[kb])) do
        table.insert(lines, "• " .. entry.line)
        for _j, rel in ipairs(entry.rels) do
            for _k, note in ipairs(rel.notes or {}) do
                table.insert(lines, "    – " .. note)
            end
            for _k, secret in ipairs(rel.secrets or {}) do
                table.insert(lines, "    – " .. _("Secret") .. ": " .. secret)
            end
        end
    end
    return lines
end

function CharacterTracker:showFamilyTreeLineInfo(family, view, info)
    if info.kind == "tie" then
        self:showSocialTieInfo(family, view, info)
        return
    end
    local g = view.graph
    local vf = view.vf or family
    local function name(k) return g.canon[k] or "?" end
    local lines = {}
    local title
    local buttons = {}
    local viewer
    local function close_and(fn)
        return function()
            UIManager:close(viewer)
            fn()
        end
    end
    local function style_row(ka, kb)
        if not view.editing then return end
        table.insert(buttons, {
            { text = _("Change line type"), callback = close_and(function()
                self:showFamilyCoupleStyleDialog(vf, g, ka, kb, function()
                    view:rebuild(view.scale)
                end)
            end) },
        })
    end
    local function rel_row(ka, kb, label, category)
        if not view.editing then return end
        table.insert(buttons, {
            { text = label or _("Change relationship"), callback = close_and(function()
                self:showFamilyPairRelationshipDialog(view, ka, kb, category)
            end) },
        })
    end
    local function common_children(ka, kb)
        local out = {}
        for _i, c in ipairs(g.children[ka] or {}) do
            for _j, p in ipairs(g.parents[c] or {}) do
                if p == kb then table.insert(out, name(c)) end
            end
        end
        return out
    end
    if info.kind == "couple" then
        title = name(info.a) .. " + " .. name(info.b)
        table.insert(lines, _("Line") .. ": " .. coupleStyleLabel(self:getCoupleStyle(vf, g, info.a, info.b)))
        local pair = self:_familyPairText(vf, g, info.a, info.b)
        table.insert(lines, "")
        if #pair > 0 then
            for _i, l in ipairs(pair) do table.insert(lines, l) end
        else
            table.insert(lines, _("No relationship recorded between them yet."))
        end
        local kids = common_children(info.a, info.b)
        if #kids > 0 then
            table.insert(lines, "")
            table.insert(lines, _("Children together") .. ": " .. table.concat(kids, ", "))
        end
        style_row(info.a, info.b)
        rel_row(info.a, info.b, nil, "couple")
    elseif info.kind == "child" then
        local parent_names = {}
        for _i, p in ipairs(info.parents) do table.insert(parent_names, name(p)) end
        title = table.concat(parent_names, " & ") .. " → " .. name(info.child)
        local kind_text = {
            adopted = _("adoptive parent"), guardian = _("guardian"),
            step = _("step-parent"), foster = _("foster parent"),
        }
        for _i, p in ipairs(info.parents) do
            if info.rel_kind and kind_text[info.rel_kind] then
                table.insert(lines, T(_("%1 is the %2 of %3."), name(p), kind_text[info.rel_kind], name(info.child)))
            else
                table.insert(lines, T(_("%1 is a parent of %2."), name(p), name(info.child)))
            end
            for _j, l in ipairs(self:_familyPairText(vf, g, p, info.child)) do
                table.insert(lines, l)
            end
            table.insert(lines, "")
        end
        for _i, p in ipairs(info.parents) do
            rel_row(p, info.child, #info.parents > 1 and T(_("Change relationship with %1"), name(p)) or nil, "parent")
        end
    else
        local parent_names, child_names = {}, {}
        for _i, p in ipairs(info.parents) do table.insert(parent_names, name(p)) end
        for _i, c in ipairs(info.children) do table.insert(child_names, name(c)) end
        title = table.concat(parent_names, " & ")
        table.insert(lines, _("Parents") .. ": " .. table.concat(parent_names, ", "))
        table.insert(lines, _("Children") .. ": " .. table.concat(child_names, ", "))
        if #info.parents == 2 then
            table.insert(lines, "")
            table.insert(lines, _("Line") .. ": " .. coupleStyleLabel(self:getCoupleStyle(vf, g, info.parents[1], info.parents[2])))
            for _i, l in ipairs(self:_familyPairText(vf, g, info.parents[1], info.parents[2])) do
                table.insert(lines, l)
            end
            style_row(info.parents[1], info.parents[2])
            rel_row(info.parents[1], info.parents[2], nil, "couple")
        end
    end
    local closing = {}
    table.insert(closing, { text = _("Close"), id = "close", callback = close_and(function() end) })
    table.insert(buttons, closing)
    viewer = self:newTextViewer("tree_line"){
        title = title,
        text = table.concat(lines, "\n"),
        width = math.floor(Device.screen:getWidth() * 0.85),
        height = math.floor(Device.screen:getHeight() * 0.6),
        buttons_table = buttons,
    }
    UIManager:show(viewer)
end

function CharacterTracker:showFamilyPairRelationshipDialog(view, ka, kb, category)
    local g = view.graph
    local family = view.family
    if not (g.plain[ka] and g.plain[kb]) then
        UIManager:show(InfoMessage:new{
            text = _("Placeholders can't have relationships. Replace the placeholder with a character first."),
        })
        return
    end
    local a, b = g.canon[ka], g.canon[kb]
    local function refresh()
        view:rebuild(view.scale)
    end
    local function again()
        refresh()
        self:showFamilyPairRelationshipDialog(view, ka, kb, category)
    end
    local function matches(rel_type)
        if category == "couple" then return PARTNER_TYPES[rel_type] ~= nil end
        if category == "parent" then return PARENT_LINK_TYPES[rel_type] ~= nil end
        return true
    end
    local records, parent_links, char_links = {}, {}, {}
    for _i, fam in ipairs(self.families or {}) do
        for index, rel in ipairs(fam.relations or {}) do
            local from, to = lowerOrEmpty(rel.from), lowerOrEmpty(rel.to)
            if ((from == ka and to == kb) or (from == kb and to == ka)) and matches(rel.type) then
                table.insert(records, { family = fam, index = index, rel = rel })
            end
        end
        if category ~= "couple" then
            for _j, m in ipairs(fam.members or {}) do
                local mk = lowerOrEmpty(m.name)
                local wanted = category == "parent" and mk == kb or (category ~= "parent" and (mk == ka or mk == kb))
                if wanted then
                    local other = mk == ka and kb or ka
                    if category == "parent" then other = ka end
                    for pi, p in ipairs(m.parents or {}) do
                        if lowerOrEmpty(p) == other then
                            table.insert(parent_links, { family = fam, member = m, index = pi, parent = p })
                        end
                    end
                end
            end
        end
    end
    if self:isRelationSyncOn() then
        for _i, char in ipairs(self.characters or {}) do
            local ck = lowerOrEmpty(char.name)
            if ck == ka or ck == kb then
                local other = ck == ka and kb or ka
                for ri, rel in ipairs(char.relationships or {}) do
                    if lowerOrEmpty(rel.target) == other and rel.type and rel.type ~= "" and matches(rel.type) then
                        table.insert(char_links, { char = char, index = ri, rel = rel })
                    end
                end
            end
        end
    end
    local dialog
    local function close_and(fn)
        return function()
            UIManager:close(dialog)
            fn()
        end
    end
    local custom_hint = { hint = _("A custom tag, e.g. rival — or \"Mentor / Student\" to name both directions") }
    local function addNew()
        local choices = {}
        for _i, choice in ipairs(relationChoices()) do
            if category == nil or matches(choice.value) then
                table.insert(choices, choice)
            end
        end
        self:_showChoice(T(_("'%1' is ___ of '%2'"), b, a), choices, function(rel_type)
            self:_commitFamilyRelation(family, a, b, rel_type, "")
            again()
        end, category == nil and custom_hint or nil)
    end
    local function removeParentLink(link)
        table.remove(link.member.parents, link.index)
        if link.member.parent_kinds then
            link.member.parent_kinds[lowerOrEmpty(link.parent)] = nil
        end
    end
    local function removeEverything()
        for i = #records, 1, -1 do
            local record = records[i]
            self:_unsyncRelationFromCharacter(record.rel)
            table.remove(record.family.relations, record.index)
        end
        for i = #parent_links, 1, -1 do removeParentLink(parent_links[i]) end
        for i = #char_links, 1, -1 do
            table.remove(char_links[i].char.relationships, char_links[i].index)
        end
        self:saveFamilies()
        self:saveData()
        self:_cleanupLinkedMembers()
    end
    if #records == 0 and #parent_links == 0 and #char_links == 0 then
        UIManager:show(InfoMessage:new{
            text = T(_("No relationship is recorded between %1 and %2 yet. Choose one."), a, b),
            timeout = 2,
        })
        addNew()
        return
    end
    local buttons = {}
    for _i, record in ipairs(records) do
        table.insert(buttons, {
            {
                text = shorten(describeInnerRelation(record.rel), 40),
                callback = close_and(function()
                    self:_showChoice(T(_("'%1' is ___ of '%2'"), record.rel.to or "?", record.rel.from or "?"),
                        relationChoices(), function(value)
                            self:_commitFamilyRelation(record.family, record.rel.from, record.rel.to,
                                value, record.rel.sentiment, record.index)
                            again()
                        end, custom_hint)
                end),
            },
            {
                text = "✕",
                callback = close_and(function()
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete this relationship?\n\n%1"), describeInnerRelation(record.rel)),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            self:_unsyncRelationFromCharacter(record.rel)
                            table.remove(record.family.relations, record.index)
                            self:saveFamilies()
                            self:_cleanupLinkedMembers()
                            again()
                        end,
                        cancel_callback = again,
                    })
                end),
            },
        })
    end
    for _i, link in ipairs(parent_links) do
        table.insert(buttons, {
            {
                text = shorten(T(_("Parents list: %1 is a parent of %2"), link.parent, link.member.name), 40),
                callback = function() end,
            },
            {
                text = "✕",
                callback = close_and(function()
                    removeParentLink(link)
                    self:saveFamilies()
                    self:_cleanupLinkedMembers()
                    again()
                end),
            },
        })
    end
    for _i, link in ipairs(char_links) do
        table.insert(buttons, {
            {
                text = shorten(T(_("Character list: %1 → %2 (%3)"), link.char.name, link.rel.target,
                    getRelationshipLabel(link.rel.type)), 40),
                callback = function() end,
            },
            {
                text = "✕",
                callback = close_and(function()
                    table.remove(link.char.relationships, link.index)
                    self:saveData()
                    again()
                end),
            },
        })
    end
    table.insert(buttons, {
        { text = _("+ Add another relationship"), callback = close_and(addNew) },
        { text = _("Remove all"), callback = close_and(function()
            UIManager:show(ConfirmBox:new{
                text = T(_("Remove every relationship between %1 and %2?"), a, b),
                ok_text = _("Remove"),
                ok_callback = function()
                    removeEverything()
                    again()
                end,
                cancel_callback = again,
            })
        end) },
    })
    table.insert(buttons, {
        { text = _("Done"), id = "close", callback = close_and(refresh) },
    })
    dialog = ButtonDialog:new{
        title = T(category == "parent" and _("Parent link — %1 and %2\n(tap to change it, ✕ to remove it)")
            or (category == "couple" and _("Couple link — %1 and %2\n(tap to change it, ✕ to remove it)")
            or _("Relationship — %1 and %2\n(tap one to change it, ✕ to remove it)")), a, b),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function CharacterTracker:showFamilyTreePersonInfo(family, view, key)
    local g = view.graph
    local vf = view.vf or family
    local name = g.canon[key]
    local member = g.plain[key] and memberByName(vf, name) or nil
    local lines = {}
    if member then
        local meta = {}
        if member.title and member.title ~= "" then table.insert(meta, member.title) end
        if member.role and member.role ~= "" then table.insert(meta, member.role) end
        if member.tie and member.tie ~= "" then table.insert(meta, member.tie) end
        if #meta > 0 then table.insert(lines, table.concat(meta, " · ")) end
    else
        table.insert(lines, _("Placeholder - not introduced yet."))
    end
    local function names_of(keys)
        local out = {}
        for _i, k in ipairs(keys) do table.insert(out, g.canon[k]) end
        return out
    end
    local rel_items = {}
    if family.tree_kind == "social" then
        rel_items = (self:_socialPersonItems(family, name))
        for _i, line in ipairs(self:buildSocialPersonLines(family, name)) do table.insert(lines, line) end
    else
        local function add(item_key, label, text)
            table.insert(rel_items, { key = item_key, label = label, lines = { text } })
        end
        if g.parents[key] and #g.parents[key] > 0 then
            add("parents", _("Parents"), _("Parents") .. ": " .. table.concat(names_of(g.parents[key]), ", "))
        end
        if g.partners[key] and #g.partners[key] > 0 then
            add("partners", _("Partners"), _("Partners") .. ": " .. table.concat(names_of(g.partners[key]), ", "))
        end
        if g.children[key] and #g.children[key] > 0 then
            add("children", _("Children"), _("Children") .. ": " .. table.concat(names_of(g.children[key]), ", "))
        end
        local full = view.full_graph
        if full and full.canon[key] then
            local labels = treeRelationLabels(full, vf, key)
            local by_label, label_order = {}, {}
            for _i, other in ipairs(full.order) do
                local label = labels[other]
                if label then
                    if not by_label[label] then
                        by_label[label] = {}
                        label_order[#label_order + 1] = label
                    end
                    table.insert(by_label[label], full.canon[other])
                end
            end
            table.sort(label_order, function(a, b) return a:lower() < b:lower() end)
            for _i, label in ipairs(label_order) do
                add("rel:" .. label, label, label .. ": " .. table.concat(by_label[label], ", "))
            end
        end
        for _i, item in ipairs(self:_orderItems(family, key, rel_items)) do
            for _j, line in ipairs(item.lines) do table.insert(lines, line) end
        end
    end
    local viewer
    local function close_and(fn)
        return function()
            UIManager:close(viewer)
            fn()
        end
    end
    local buttons = {}
    if #rel_items > 1 and view.editing then
        table.insert(buttons, {
            { text = _("Arrange order"), callback = close_and(function()
                self:showRelOrderDialog(family, key, rel_items, function()
                    self:showFamilyTreePersonInfo(family, view, key)
                end)
            end) },
        })
    end
    if member then
        local owner, index = self:_findMemberOwner(member)
        local row = {}
        if self:getCharacterByName(member.name) then
            table.insert(row, { text = _("Open character"), callback = close_and(function()
                self:showCharacterDetailReadOnly(self:getCharacterByName(member.name))
            end) })
        end
        if owner and view.editing then
            table.insert(row, { text = _("Parents"), callback = close_and(function()
                self._tree_return_view = view
                self:showFamilyMemberParents(owner, index)
            end) })
        end
        if #row > 0 then table.insert(buttons, row) end
        if view.editing then
            table.insert(buttons, {
                { text = family.tree_kind == "social" and _("Add tie") or _("Add relationship"), callback = close_and(function()
                    if family.tree_kind == "social" then
                        self:_addSocialTieFrom(family, view, name)
                    else
                        self:_addFamilyRelationFrom(family, view, name)
                    end
                end) },
            })
            table.insert(buttons, {
                { text = _("Set gender"), callback = close_and(function()
                    self:showFamilyGenderDialog(member, function()
                        view:rebuild(view.scale)
                    end)
                end) },
            })
            if memberByName(family, member.name) then
                table.insert(buttons, {
                    { text = _("Unlink family"), callback = close_and(function()
                        self:showFamilyUnlinkDialog(family, function()
                            view:rebuild(view.scale)
                        end, member.name)
                    end) },
                })
            end
            table.insert(buttons, {
                { text = _("Names & title"), callback = close_and(function()
                    self:showFamilyTreeNameDialog(owner or family, member, function()
                        view:rebuild(view.scale)
                    end)
                end) },
            })
        end
    elseif view.editing then
        local owner, ph = self:_findPlaceholderOwner(g.canon[key]:match("^%[(.*)%]$") or "")
        if ph then
            table.insert(buttons, {
                { text = _("Replace"), callback = close_and(function()
                    self:showFamilyPlaceholderActions(owner, ph, function()
                        view:rebuild(view.scale)
                    end)
                end) },
            })
        end
    end
    if family.tree_kind ~= "social" then
        table.insert(buttons, {
            { text = view.focus == key and _("Clear focus") or _("Focus"), callback = close_and(function()
                view:setFocus(view.focus ~= key and key or nil)
            end) },
        })
        table.insert(buttons, {
            { text = view.hidden_down[key] and _("Show below") or _("Hide below"), callback = close_and(function()
                view:toggleBranch(key, "down")
            end) },
            { text = view.hidden_up[key] and _("Show above") or _("Hide above"), callback = close_and(function()
                view:toggleBranch(key, "up")
            end) },
        })
    end
    table.insert(buttons, {
        { text = _("Close"), id = "close", callback = close_and(function() end) },
    })
    viewer = self:newTextViewer("tree_person", "per_row", 2){
        title = name,
        text = table.concat(lines, "\n"),
        width = math.floor(Device.screen:getWidth() * 0.85),
        height = math.floor(Device.screen:getHeight() * 0.6),
        buttons_table = buttons,
    }
    UIManager:show(viewer)
end

function CharacterTracker:showFamilyCoupleStyleDialog(family, g, ka, kb, on_done)
    local current = self:getCoupleStyle(family, g, ka, kb)
    local choices = {}
    for _i, st in ipairs(COUPLE_STYLES) do
        table.insert(choices, { label = (st.key == current and "✓ " or "") .. coupleStyleLabel(st.key), value = st.key })
    end
    local seen_custom = {}
    for _i, source in ipairs({ family.real or family, family }) do
        for _pair, style in pairs(source.couple_styles or {}) do
            if parseCustomCouple(style) and not seen_custom[style] then
                seen_custom[style] = true
                table.insert(choices, { label = (style == current and "✓ " or "") .. shorten(coupleStyleLabel(style), 34), value = style })
            end
        end
    end
    table.insert(choices, { label = _("+ Custom line…"), value = "__custom" })
    table.insert(choices, { label = _("Use the default"), value = "" })
    self:_showChoice(T(_("Line between %1 and %2"), g.canon[ka], g.canon[kb]), choices, function(value)
        if value == "__custom" then
            local dialog
            dialog = InputDialog:new{
                title = T(_("Name of the tie between %1 and %2"), g.canon[ka], g.canon[kb]),
                input_hint = _("e.g. betrothed, secret affair, blood oath"),
                buttons = {
                    {
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function()
                                UIManager:close(dialog)
                                if on_done then on_done() end
                            end,
                        },
                        {
                            text = _("Next"),
                            is_enter_default = true,
                            callback = function()
                                local name = trim(dialog:getInputText()):gsub("|", "/")
                                UIManager:close(dialog)
                                if name == "" then
                                    if on_done then on_done() end
                                    return
                                end
                                local bases = {}
                                for _i, st in ipairs(COUPLE_STYLES) do
                                    if st.key ~= "none" then
                                        table.insert(bases, { label = st.visual_label:gsub("^%l", string.upper), value = st.key })
                                    end
                                end
                                self:_showChoice(T(_("Which line for '%1'?"), name), bases, function(base)
                                    self:_applyCoupleStyle(family, ka, kb, "custom|" .. base .. "|" .. name, on_done)
                                end)
                            end,
                        },
                    },
                },
            }
            self:_showInputDialog(dialog)
            return
        end
        self:_applyCoupleStyle(family, ka, kb, value, on_done)
    end)
end

function CharacterTracker:_applyCoupleStyle(family, ka, kb, value, on_done)
    local real = family.real or family
    if type(real.couple_styles) ~= "table" then real.couple_styles = {} end
    real.couple_styles[coupleKey(ka, kb)] = value ~= "" and value or nil
    if real ~= family then family.couple_styles[coupleKey(ka, kb)] = value ~= "" and value or nil end
    self:saveFamilies()
    if on_done then on_done() end
end

function CharacterTracker:showFamilyCoupleList(family, view)
    local g = view.graph
    local vf = view.vf or family
    local buttons = {}
    local seen = {}
    for _i, a in ipairs(g.order) do
        for _j, b in ipairs(g.partners[a] or {}) do
            local key = coupleKey(a, b)
            if not seen[key] then
                seen[key] = true
                table.insert(buttons, {
                    {
                        text = shorten(g.canon[a] .. " + " .. g.canon[b], 30) .. " · " .. coupleStyleShort(self:getCoupleStyle(vf, g, a, b)),
                        callback = function()
                            UIManager:close(self._family_couples_dialog)
                            self._family_couples_dialog = nil
                            self:showFamilyCoupleStyleDialog(vf, g, a, b, function()
                                view:rebuild(view.scale)
                                self:showFamilyCoupleList(family, view)
                            end)
                        end,
                    },
                })
            end
        end
    end
    if #buttons == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No parent pairs yet - give a member two parents, or add a spouse relationship."),
        })
        return
    end
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._family_couples_dialog)
                self._family_couples_dialog = nil
            end,
        },
    })
    self._family_couples_dialog = ButtonDialog:new{
        title = _("Line between each pair of parents"),
        buttons = buttons,
    }
    UIManager:show(self._family_couples_dialog)
end

function CharacterTracker:showFamilyTreeTextSizeDialog(family, view)
    local kinds = {
        { key = "first", label = _("First name") },
        { key = "last", label = _("Last name") },
        { key = "info", label = _("Occupation & small text") },
    }
    local function change(key, delta)
        local value = math.max(8, math.min(40, self:getTreeFontSize(key) + delta))
        if G_reader_settings then
            G_reader_settings:saveSetting("character_tracker_tree_size_" .. key, value)
        end
        UIManager:close(self._family_size_dialog)
        self._family_size_dialog = nil
        view:rebuild(view.scale)
        self:showFamilyTreeTextSizeDialog(family, view)
    end
    local buttons = {}
    for _i, kind in ipairs(kinds) do
        table.insert(buttons, {
            { text = kind.label .. ": " .. self:getTreeFontSize(kind.key), callback = function() end },
            { text = "-", callback = function() change(kind.key, -1) end },
            { text = "+", callback = function() change(kind.key, 1) end },
        })
    end
    table.insert(buttons, {
        { text = _("Reset sizes"), callback = function()
            if G_reader_settings then
                for _j, kind in ipairs(kinds) do
                    G_reader_settings:delSetting("character_tracker_tree_size_" .. kind.key)
                end
            end
            UIManager:close(self._family_size_dialog)
            self._family_size_dialog = nil
            view:rebuild(view.scale)
            self:showFamilyTreeTextSizeDialog(family, view)
        end },
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._family_size_dialog)
            self._family_size_dialog = nil
            self:showFamilyTreeViewDialog(family, view)
        end },
    })
    self._family_size_dialog = ButtonDialog:new{
        title = _("Tree text sizes (independent of zoom)"),
        buttons = buttons,
    }
    UIManager:show(self._family_size_dialog)
end

function CharacterTracker:showFamilyTreeFocusPicker(family, view)
    local g = view.full_graph
    if not g then return end
    local choices = {}
    for _i, key in ipairs(g.order) do
        if g.plain[key] then
            table.insert(choices, { label = g.canon[key], value = key })
        end
    end
    self:_showChoice(_("Focus on which person?"), choices, function(key)
        view:setFocus(key)
        self:showFamilyTreeViewDialog(family, view)
    end)
end

function CharacterTracker:_applyFamilyLink(family, other, a_name, b_name, rel_type)
    local tie = _("Linked")
    if rel_type == "spouse" then
        tie = _("By marriage")
    elseif rel_type == "adoptive_parent" or rel_type == "adopted_child" then
        tie = _("Adopted")
    elseif rel_type == "foster_parent" or rel_type == "foster_child" then
        tie = _("Fostered")
    end
    local function ensure(fam, name)
        if not memberByName(fam, name) then
            table.insert(fam.members, { name = name, role = "", tie = tie, parents = {}, linked_in = true })
        end
    end
    ensure(family, b_name)
    ensure(other, a_name)
    for _i, rel in ipairs(family.relations) do
        if lowerOrEmpty(rel.from) == lowerOrEmpty(a_name) and lowerOrEmpty(rel.to) == lowerOrEmpty(b_name)
           and rel.type == rel_type then
            self:saveFamilies()
            return
        end
    end
    table.insert(family.relations, {
        from = a_name, to = b_name, type = rel_type, sentiment = "",
        notes = {}, secrets = {},
    })
    self:_syncRelationToCharacter(family.relations[#family.relations])
    self:saveFamilies()
end

function CharacterTracker:showFamilyLinkDialog(family, on_done)
    local others = {}
    for _i, other in ipairs(self.families) do
        if other ~= family and other.members and #other.members > 0 then
            table.insert(others, { label = other.name or "?", value = other.id })
        end
    end
    if not family.members or #family.members == 0 or #others == 0 then
        UIManager:show(InfoMessage:new{
            text = _("You need members in this family and at least one other family with members to link them."),
        })
        if on_done then on_done() end
        return
    end
    local allowed = {
        spouse = true, partner = true, lover = true, ex = true,
        father = true, mother = true, parent = true, son = true, daughter = true, child = true,
        adoptive_parent = true, adopted_child = true, guardian = true, ward = true,
        step_parent = true, step_child = true, foster_parent = true, foster_child = true,
        brother = true, sister = true, sibling = true, cousin = true,
    }
    local type_choices = {}
    for _i, rt in ipairs(RELATIONSHIP_TYPES) do
        if allowed[rt.key] then
            table.insert(type_choices, { label = rt.label, value = rt.key })
        end
    end
    self:_showChoice(T(_("Which member of '%1'?"), family.name), memberChoices(family, nil), function(a_name)
        self:_showChoice(T(_("Link '%1' to which family?"), a_name), others, function(other_id)
            local other = self:getFamilyById(other_id)
            if not other then
                if on_done then on_done() end
                return
            end
            self:_showChoice(T(_("Which member of '%1'?"), other.name), memberChoices(other, a_name), function(b_name)
                self:_showChoice(T(_("'%1' is ___ of '%2'"), b_name, a_name), type_choices, function(rel_type)
                    self:_applyFamilyLink(family, other, a_name, b_name, rel_type)
                    UIManager:show(InfoMessage:new{
                        text = T(_("Linked '%1' and '%2'. Both now appear in both families."), a_name, b_name),
                        timeout = 2,
                    })
                    if on_done then on_done() end
                end, { hint = _("A custom tag, e.g. rival — or \"Mentor / Student\" to name both directions") })
            end)
        end)
    end)
end

function CharacterTracker:isRelationSyncOn()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_sync_tree_relationships")
end

function CharacterTracker:_syncRelationToCharacter(rel, skip_save)
    if not self:isRelationSyncOn() or not rel then return false end
    local owner = self:getCharacterByName(rel.from)
    local target = self:getCharacterByName(rel.to)
    if not owner or not target or owner == target then return false end
    if type(owner.relationships) ~= "table" then owner.relationships = {} end
    local rel_type = rel.type or ""
    for _i, existing in ipairs(owner.relationships) do
        if lowerOrEmpty(existing.target) == lowerOrEmpty(target.name) and (existing.type or "") == rel_type then
            if (not existing.sentiment or existing.sentiment == "") and rel.sentiment and rel.sentiment ~= "" then
                existing.sentiment = rel.sentiment
                if not skip_save then self:saveData() end
                return true
            end
            return false
        end
    end
    table.insert(owner.relationships, {
        target = target.name, type = rel_type, sentiment = rel.sentiment or "",
    })
    if not skip_save then self:saveData() end
    return true
end

function CharacterTracker:_memberHasFamilyTies(family, member)
    local name = (member.name or ""):lower()
    if member.parents and #member.parents > 0 then return true end
    local others = {}
    for _i, other in ipairs(family.members or {}) do
        local key = (other.name or ""):lower()
        if key ~= name then
            others[key] = true
            for _j, p in ipairs(other.parents or {}) do
                if (p or ""):lower() == name then return true end
            end
        end
    end
    for _i, fam in ipairs(self.families or {}) do
        for _j, rel in ipairs(fam.relations or {}) do
            local from, to = (rel.from or ""):lower(), (rel.to or ""):lower()
            if (from == name and others[to]) or (to == name and others[from]) then return true end
        end
    end
    return false
end

function CharacterTracker:_cleanupLinkedMembers()
    local removed = 0
    for _i, fam in ipairs(self.families or {}) do
        for j = #(fam.members or {}), 1, -1 do
            local member = fam.members[j]
            local added_by_link = member.linked_in or (member.linked_in == nil and member.tie == _("Linked"))
            if added_by_link and not self:_memberHasFamilyTies(fam, member) then
                self:_removeFamilyMember(fam, j)
                removed = removed + 1
            end
        end
    end
    return removed
end

function CharacterTracker:_unsyncRelationFromCharacter(rel)
    if not self:isRelationSyncOn() or not rel then return end
    local owner = self:getCharacterByName(rel.from)
    if not owner or type(owner.relationships) ~= "table" then return end
    for i = #owner.relationships, 1, -1 do
        local existing = owner.relationships[i]
        if lowerOrEmpty(existing.target) == lowerOrEmpty(rel.to) and (existing.type or "") == (rel.type or "") then
            table.remove(owner.relationships, i)
            self:saveData()
            return
        end
    end
end

function CharacterTracker:_syncAllFamilyRelations()
    local added = 0
    for _i, family in ipairs(self.families or {}) do
        for _j, rel in ipairs(family.relations or {}) do
            if self:_syncRelationToCharacter(rel, true) then added = added + 1 end
        end
    end
    if added > 0 then self:saveData() end
    return added
end

function CharacterTracker:toggleRelationSync()
    if not G_reader_settings then return end
    local enable = not self:isRelationSyncOn()
    G_reader_settings:saveSetting("character_tracker_sync_tree_relationships", enable)
    if enable then
        local added = self:_syncAllFamilyRelations()
        UIManager:show(InfoMessage:new{
            text = T(_("Syncing on. %1 family relationship(s) added to the character list."), added),
            timeout = 2,
        })
    end
end

function CharacterTracker:showCharacterFamiliesManager(character)
    local cname = character.name:lower()
    local function back() self:showCharacterFamiliesManager(character) end
    local function finish() self:showCharacterDetail(character) end
    local entries = {}
    for _i, family in ipairs(self.families or {}) do
        for j, member in ipairs(family.members or {}) do
            if member.name and member.name:lower() == cname then
                table.insert(entries, { family = family, member = member, index = j })
            end
        end
    end
    local buttons = {}
    for _i, entry in ipairs(entries) do
        local label = entry.family.name or _("(unnamed)")
        if entry.member.role and entry.member.role ~= "" then label = label .. " — " .. entry.member.role end
        label = label .. self:_familyTieSuffix(entry.family, entry.member, #entries)
        table.insert(buttons, {
            {
                text = shorten(label, 44),
                callback = function()
                    UIManager:close(self._char_families_dialog)
                    self._char_families_dialog = nil
                    self:showCharacterFamilyEntryActions(character, entry.family, entry.index, back)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._char_families_dialog)
                    self._char_families_dialog = nil
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Remove %1 from %2?"), character.name, entry.family.name or "?"),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            self:_removeFamilyMember(entry.family, entry.index)
                            back()
                        end,
                        cancel_callback = back,
                    })
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add to a family"),
            callback = function()
                UIManager:close(self._char_families_dialog)
                self._char_families_dialog = nil
                local present = {}
                for _i, entry in ipairs(entries) do present[entry.family] = true end
                local choices = {}
                for _i, family in ipairs(self.families or {}) do
                    if not present[family] then
                        table.insert(choices, { label = family.name or _("(unnamed)"), value = family.id })
                    end
                end
                if #choices == 0 then
                    UIManager:show(InfoMessage:new{
                        text = #(self.families or {}) == 0
                            and _("There are no families yet. Add one from Tools → Character Tracker → Add family.")
                            or T(_("%1 is already in every family."), character.name),
                    })
                    back()
                    return
                end
                self:_showChoice(T(_("Add %1 to which family?"), character.name), choices, function(id)
                    local family = self:getFamilyById(id)
                    if not family then back() return end
                    if family.tree_kind == "social" then
                        table.insert(family.members, {
                            name = character.name, role = "", tie = "", parents = {},
                        })
                        self:saveFamilies()
                        back()
                        return
                    end
                    local dialog
                    dialog = InputDialog:new{
                        title = T(_("Role of %1 in %2 (optional)"), character.name, family.name or "?"),
                        input_hint = self:_familyRoleHint(family),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                        back()
                                    end,
                                },
                                {
                                    text = _("Add"),
                                    is_enter_default = true,
                                    callback = function()
                                        local role = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        table.insert(family.members, {
                                            name = character.name, role = role, tie = "", parents = {},
                                        })
                                        self:saveFamilies()
                                        back()
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end)
            end,
        },
        {
            text = _("Done"),
            id = "close",
            callback = function()
                UIManager:close(self._char_families_dialog)
                self._char_families_dialog = nil
                finish()
            end,
        },
    })
    self._char_families_dialog = ButtonDialog:new{
        title = T(_("Families of %1"), character.name),
        buttons = buttons,
    }
    UIManager:show(self._char_families_dialog)
end

function CharacterTracker:showCharacterFamilyEntryActions(character, family, index, back)
    local member = family.members[index]
    if not member then back() return end
    local function close_and(fn)
        return function()
            UIManager:close(self._char_family_act_dialog)
            self._char_family_act_dialog = nil
            fn()
        end
    end
    self._char_family_act_dialog = ButtonDialog:new{
        title = T(_("%1 in %2"), character.name, family.name or "?"),
        buttons = {
            {
                { text = _("Edit role"), callback = close_and(function()
                    local dialog
                    dialog = InputDialog:new{
                        title = T(_("Role in %1"), family.name or "?"),
                        input = member.role or "",
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                        back()
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        member.role = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        self:saveFamilies()
                                        back()
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end) },
                { text = _("Set tie"), callback = close_and(function()
                    self:_showChoice(T(_("How is %1 tied to %2?"), character.name, family.name or "?"), tieChoices(), function(value)
                        member.tie = value
                        self:saveFamilies()
                        back()
                    end, { hint = _("e.g. cousin by marriage, sworn shield") })
                end) },
            },
            {
                { text = _("Open family"), callback = close_and(function()
                    self:showFamilyDetail(family)
                end) },
                { text = _("Back"), id = "close", callback = close_and(back) },
            },
        },
    }
    UIManager:show(self._char_family_act_dialog)
end

function CharacterTracker:showFamilyGenderDialog(member, on_done)
    local current = member.gender
    local choices = {
        { label = (current == "male" and "✓ " or "") .. _("Male"), value = "male" },
        { label = (current == "female" and "✓ " or "") .. _("Female"), value = "female" },
        { label = (current ~= "male" and current ~= "female" and "✓ " or "") .. _("Not set"), value = "" },
    }
    self:_showChoice(T(_("Gender of %1"), member.name or "?"), choices, function(value)
        self:setGenderByName(member.name, value ~= "" and value or nil)
        member.gender = value ~= "" and value or nil
        if on_done then on_done() end
    end)
end

function CharacterTracker:setGenderByName(name, gender)
    local key = lowerOrEmpty(name)
    for _i, family in ipairs(self.families or {}) do
        for _j, member in ipairs(family.members or {}) do
            if lowerOrEmpty(member.name) == key then member.gender = gender end
        end
    end
    self:saveFamilies()
end

function CharacterTracker:_syncGenders()
    local known = {}
    for _i, family in ipairs(self.families or {}) do
        for _j, member in ipairs(family.members or {}) do
            if member.gender == "male" or member.gender == "female" then
                local key = lowerOrEmpty(member.name)
                if not known[key] then known[key] = member.gender end
            end
        end
    end
    local changed = false
    for _i, family in ipairs(self.families or {}) do
        for _j, member in ipairs(family.members or {}) do
            local key = lowerOrEmpty(member.name)
            if known[key] and member.gender ~= known[key] then
                member.gender = known[key]
                changed = true
            end
        end
    end
    if changed then self:saveFamilies() end
end

function CharacterTracker:showFamilyUnlinkDialog(family, on_done, only_name)
    local entries, choices = {}, {}
    for _i, other in ipairs(self:getLinkedFamilies(family)) do
        for _j, m in ipairs(other.members or {}) do
            local mine = memberByName(family, m.name)
            if mine and (not only_name or lowerOrEmpty(m.name) == lowerOrEmpty(only_name)) then
                entries[#entries + 1] = { member = mine.name, other = other }
                choices[#choices + 1] = {
                    label = shorten(mine.name .. " ↔ " .. (other.name or "?"), 40),
                    value = #entries,
                }
            end
        end
    end
    if #entries == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Nobody in this family is shared with another family."),
        })
        if on_done then on_done() end
        return
    end
    local function pick(index)
        local entry = entries[index]
        local other = entry.other
        local options = {
            { label = T(_("Remove from %1"), other.name or "?"), value = "other" },
            { label = T(_("Remove from %1"), family.name or "?"), value = "this" },
        }
        self:_showChoice(T(_("Unlink '%1'"), entry.member), options, function(value)
            local fam = value == "other" and other or family
            UIManager:show(ConfirmBox:new{
                text = T(_("Remove '%1' from '%2'?"), entry.member, fam.name or "?"),
                ok_text = _("Remove"),
                ok_callback = function()
                    for i, m in ipairs(fam.members) do
                        if lowerOrEmpty(m.name) == lowerOrEmpty(entry.member) then
                            self:_removeFamilyMember(fam, i)
                            break
                        end
                    end
                    if on_done then on_done() end
                end,
                cancel_callback = function()
                    if on_done then on_done() end
                end,
            })
        end)
    end
    if #entries == 1 then
        pick(1)
    else
        self:_showChoice(_("Unlink which member?"), choices, pick)
    end
end

function CharacterTracker:showFamilyTreeViewDialog(family, view)
    local function close_and(fn)
        return function()
            UIManager:close(self._family_view_dialog)
            self._family_view_dialog = nil
            fn()
        end
    end
    local function refresh()
        view:rebuild(view.scale)
        self:showFamilyTreeViewDialog(family, view)
    end
    local function toggle(setting, current)
        return close_and(function()
            if G_reader_settings then
                G_reader_settings:saveSetting(setting, not current)
            end
            refresh()
        end)
    end
    local buttons = {
        {
            { text = (self:isTreeUnderlineHidden() and "" or "✓ ") .. _("Line under names"),
              callback = toggle("character_tracker_tree_hide_underline", self:isTreeUnderlineHidden()) },
            { text = (self:isTreeGenerationsHidden() and "" or "✓ ") .. _("Generation labels"),
              callback = toggle("character_tracker_tree_hide_generations", self:isTreeGenerationsHidden()) },
        },
        {
            { text = (self:isTreeCombinedHidden() and "" or "✓ ") .. _("Show combined families"),
              callback = toggle("character_tracker_tree_hide_combined", self:isTreeCombinedHidden()) },
        },
        {
            { text = (self:isRelationSyncOn() and "✓ " or "") .. _("Sync with character list"),
              callback = close_and(function()
                self:toggleRelationSync()
                refresh()
            end) },
        },
        {
            { text = _("Text sizes"), callback = close_and(function()
                self:showFamilyTreeTextSizeDialog(family, view)
            end) },
            { text = self:getTreeHoldAction() == "focus" and _("Hold a name: focus") or _("Hold a name: hide / show branch"),
              callback = close_and(function()
                if G_reader_settings then
                    G_reader_settings:saveSetting("character_tracker_tree_hold_branch",
                        self:getTreeHoldAction() == "focus")
                end
                self:showFamilyTreeViewDialog(family, view)
            end) },
        },
    }
    table.insert(buttons, {
        { text = (self:isTreeLegendOn() and "✓ " or "") .. _("Line legend"),
          callback = toggle("character_tracker_tree_legend", self:isTreeLegendOn()) },
        { text = _("Line meanings"), callback = close_and(function()
            self:showLineMeaningsDialog(function() self:showFamilyTreeViewDialog(family, view) end, view)
        end) },
    })
    local label_only = self:isTreeFocusLabelOnly()
    local function style_button()
        return { text = label_only and _("Focus style: label everyone") or _("Focus style: show only relatives"),
                 callback = toggle("character_tracker_tree_focus_label_only", label_only) }
    end
    if view.focus and view.full_graph then
        table.insert(buttons, {
            { text = T(_("Focus: %1"), shorten(view.full_graph.canon[view.focus] or "?", 24)), callback = close_and(function()
                self:showFamilyTreeFocusPicker(family, view)
            end) },
            { text = _("Show everyone"), callback = close_and(function()
                view:setFocus(nil)
                self:showFamilyTreeViewDialog(family, view)
            end) },
        })
        table.insert(buttons, { style_button() })
        if not label_only then
            local function change_depth(delta)
                return close_and(function()
                    local value = math.max(1, math.min(8, self:getTreeFocusDepth() + delta))
                    if G_reader_settings then
                        G_reader_settings:saveSetting("character_tracker_tree_focus_depth", value)
                    end
                    refresh()
                end)
            end
            table.insert(buttons, {
                { text = T(_("Focus reach: %1"), self:getTreeFocusDepth()), callback = function() end },
                { text = "-", callback = change_depth(-1) },
                { text = "+", callback = change_depth(1) },
            })
        end
    else
        table.insert(buttons, {
            { text = _("Focus on a person…"), callback = close_and(function()
                self:showFamilyTreeFocusPicker(family, view)
            end) },
        })
        table.insert(buttons, { style_button() })
    end
    if next(view.hidden_down) or next(view.hidden_up) then
        table.insert(buttons, {
            { text = _("Show all branches"), callback = close_and(function()
                view:clearBranches()
                self:showFamilyTreeViewDialog(family, view)
            end) },
        })
    end
    table.insert(buttons, {
        { text = _("Link another family"), callback = close_and(function()
            self:showFamilyLinkDialog(family, function()
                view:rebuild(view.scale)
                self:showFamilyTreeViewDialog(family, view)
            end)
        end) },
        { text = _("Unlink a member"), callback = close_and(function()
            self:showFamilyUnlinkDialog(family, function()
                view:rebuild(view.scale)
                self:showFamilyTreeViewDialog(family, view)
            end)
        end) },
    })
    if not self:isTreeCombinedHidden() then
        local linked = self:getLinkedFamilies(family)
        if #linked == 0 then
            table.insert(buttons, {
                { text = _("No other family shares a member with this one"), callback = function() end },
            })
        end
        local excluded = family.tree_excluded or {}
        for _i, other in ipairs(linked) do
            table.insert(buttons, {
                { text = (excluded[other.id] and "" or "✓ ") .. shorten(other.name or "?", 36), callback = close_and(function()
                    if type(family.tree_excluded) ~= "table" then family.tree_excluded = {} end
                    family.tree_excluded[other.id] = (not family.tree_excluded[other.id]) or nil
                    self:saveFamilies()
                    refresh()
                end) },
            })
        end
    end
    table.insert(buttons, {
        { text = _("Close"), id = "close", callback = close_and(function() end) },
    })
    self._family_view_dialog = ButtonDialog:new{
        title = _("What to show in the tree"),
        buttons = buttons,
    }
    UIManager:show(self._family_view_dialog)
end

function CharacterTracker:showFamilyLinesDialog(family, view)
    local function close_and(fn)
        return function()
            UIManager:close(self._family_lines_dialog)
            self._family_lines_dialog = nil
            fn()
        end
    end
    self._family_lines_dialog = ButtonDialog:new{
        title = _("Lines between parents"),
        buttons = {
            {
                { text = T(_("Default: %1"), coupleStyleShort(self:getDefaultCoupleStyle())), callback = close_and(function()
                    local current = self:getDefaultCoupleStyle()
                    local choices = {}
                    for _i, st in ipairs(COUPLE_STYLES) do
                        table.insert(choices, { label = (st.key == current and "✓ " or "") .. coupleStyleLabel(st.key), value = st.key })
                    end
                    self:_showChoice(_("Default line between parents who aren't married"), choices, function(value)
                        if G_reader_settings then
                            G_reader_settings:saveSetting("character_tracker_parent_line_default", value)
                        end
                        view:rebuild(view.scale)
                    end)
                end) },
            },
            {
                { text = _("Change a pair's line"), callback = close_and(function()
                    self:showFamilyCoupleList(family, view)
                end) },
            },
            {
                { text = _("Line meanings"), callback = close_and(function()
                    self:showLineMeaningsDialog(function()
                        self:showFamilyLinesDialog(family, view)
                    end, view)
                end) },
                { text = (self:isTreeLegendOn() and "✓ " or "") .. _("Legend"), callback = close_and(function()
                    if G_reader_settings then
                        G_reader_settings:saveSetting("character_tracker_tree_legend", not self:isTreeLegendOn())
                    end
                    view:rebuild(view.scale)
                    self:showFamilyLinesDialog(family, view)
                end) },
            },
            {
                { text = _("Close"), id = "close", callback = close_and(function() end) },
            },
        },
    }
    UIManager:show(self._family_lines_dialog)
end

function CharacterTracker:_familyActions(family, reopen)
    local function list(field, title, add_label, add_title, edit_title, hint)
        return function()
            self:showStringListManager(family, field, {
                title = title,
                add_label = add_label,
                add_title = add_title,
                edit_title = edit_title,
                hint = hint,
                on_change = function() self:saveFamilies() end,
                on_close = reopen,
            })
        end
    end
    return {
        { key = "rename", label = _("Rename"), default = "main", run = function()
            self:showRenameFamilyDialog(family, reopen)
        end },
        { key = "description", label = _("Description"), default = "main", run = function()
            self:showFamilyDescriptionDialog(family, reopen)
        end },
        { key = "motto", label = _("Motto"), default = "main", run = function()
            self:showFamilyTextFieldDialog(family, "motto", _("Motto"), _("House words"), reopen)
        end },
        { key = "seat", label = _("Seat"), default = "main", run = function()
            self:showFamilyTextFieldDialog(family, "seat", _("Seat"), _("Where the family is based"), reopen)
        end },
        { key = "members", label = _("Members"), default = "main", run = function()
            self:showFamilyMembersManager(family)
        end },
        { key = "relations", label = family.tree_kind == "social" and _("Ties") or _("Relations"),
          default = "main", run = function()
            if family.tree_kind == "social" then
                self:showFamilySocialTiesManager(family)
            else
                self:showFamilyRelationsManager(family)
            end
        end },
        { key = "tree_kind", label = _("Tree type"), default = "more", run = function()
            local choices = {
                { label = (family.tree_kind ~= "social" and "✓ " or "") .. _("Family tree (blood & marriage ties)"), value = "family" },
                { label = (family.tree_kind == "social" and "✓ " or "") .. _("Relationship tree (friends, enemies, allies…)"), value = "social" },
            }
            self:_showChoice(T(_("What kind of tree is '%1'?"), family.name or "?"), choices, function(kind)
                family.tree_kind = kind
                if type(family.social_ties) ~= "table" then family.social_ties = {} end
                self:saveFamilies()
                reopen()
            end)
        end },
        { key = "alliances", label = _("Alliances"), default = "main", run = function()
            self:showFamilyHousesManager(family)
        end },
        { key = "notes", label = _("Notes"), default = "main", run = function()
            self:showFamilyNotesManager(family)
        end },
        { key = "edit_role", label = _("Edit role"), default = "more", run = function()
            if not family.members or #family.members == 0 then
                UIManager:show(InfoMessage:new{ text = _("Add members to the family first.") })
                reopen()
                return
            end
            self:_showChoice(T(_("Whose role in '%1'?"), family.name or "?"), memberChoices(family, nil), function(name)
                local member = memberByName(family, name)
                if not member then reopen() return end
                local dialog
                dialog = InputDialog:new{
                    title = T(_("Role of %1"), member.name),
                    input = member.role or "",
                    input_hint = self:_familyRoleHint(family),
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(dialog)
                                    reopen()
                                end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    member.role = trim(dialog:getInputText())
                                    UIManager:close(dialog)
                                    self:saveFamilies()
                                    reopen()
                                end,
                            },
                        },
                    },
                }
                self:_showInputDialog(dialog)
            end)
        end },
        { key = "set_tie", label = _("Set tie"), default = "more", run = function()
            if not family.members or #family.members == 0 then
                UIManager:show(InfoMessage:new{ text = _("Add members to the family first.") })
                reopen()
                return
            end
            self:_showChoice(T(_("Whose tie to '%1'?"), family.name or "?"), memberChoices(family, nil), function(name)
                local member = memberByName(family, name)
                if not member then reopen() return end
                self:_showChoice(T(_("How is '%1' tied to '%2'?"), member.name, family.name or "?"), tieChoices(), function(value)
                    member.tie = value
                    self:saveFamilies()
                    reopen()
                end, { hint = _("e.g. cousin by marriage, sworn shield") })
            end)
        end },
        { key = "tree", label = _("Tree"), default = "main", run = function()
            self:showFamilyTree(family)
        end },
        { key = "succession", label = _("Succession"), default = "main", run = function()
            self:showFamilySuccessionManager(family)
        end },
        { key = "traits", label = _("Traits"), default = "main", run = function()
            self:showFamilyTraitsManager(family)
        end },
        { key = "sigil", label = _("Sigil & colors"), default = "more", run = function()
            self:showFamilyTextFieldDialog(family, "sigil", _("Sigil & colors"), _("Heraldry, banner, colors"), reopen)
        end },
        { key = "inheritance", label = _("Inheritance rule"), default = "more", run = function()
            self:showFamilyTextFieldDialog(family, "inheritance", _("Inheritance"), _("e.g. eldest son first, elected by the council"), reopen)
        end },
        { key = "holdings", label = _("Holdings & titles"), default = "more",
          run = list("holdings", _("Holdings & titles"), _("+ Add holding / title"), _("Add holding / title"), _("Edit holding / title"), _("lands, titles, wealth, heirlooms")) },
        { key = "history", label = _("History"), default = "more",
          run = list("history", _("History"), _("+ Add event"), _("Add event"), _("Edit event"), _("a founding, a war, a scandal")) },
        { key = "secrets", label = _("Family secrets"), default = "more",
          run = list("secrets", _("Family secrets"), _("+ Add secret"), _("Add secret"), _("Edit secret"), _("something the family hides")) },
        { key = "arrange_sections", label = _("Arrange member sections"), default = "more", run = function()
            self:showFamilySectionOrderDialog(family)
        end },
        { key = "placeholders", label = _("Placeholder parents"), default = "more", run = function()
            self:showFamilyPlaceholdersManager(family)
        end },
        { key = "link", label = _("Link to another family"), default = "more", run = function()
            self:showFamilyLinkDialog(family, reopen)
        end },
        { key = "unlink", label = _("Unlink from another family"), default = "more", run = function()
            self:showFamilyUnlinkDialog(family, reopen)
        end },
        { key = "groups", label = _("Groups"), default = "main", run = function()
            self:showSocialGroupsManager(family)
        end },
        { key = "dynamics", label = _("Dynamics"), default = "main",
          run = list("dynamics", _("Dynamics"), _("+ Add dynamic"), _("Add dynamic"), _("Edit dynamic"), _("a shared secret, an inside joke, a rivalry")) },
    }
end

local FAMILY_ONLY_ACTIONS = {
    motto = true, seat = true, alliances = true, succession = true, traits = true, sigil = true,
    inheritance = true, holdings = true, arrange_sections = true, placeholders = true,
    link = true, unlink = true, set_tie = true,
}
local SOCIAL_ONLY_ACTIONS = { groups = true, dynamics = true }

local function familyActionApplies(key, family)
    if SOCIAL_ONLY_ACTIONS[key] then return family.tree_kind == "social" end
    if FAMILY_ONLY_ACTIONS[key] then return family.tree_kind ~= "social" end
    return true
end

function CharacterTracker:getFamilyButtonLayout()
    local defs = self:_familyActions({}, function() end)
    local default_place, valid = {}, {}
    for _i, def in ipairs(defs) do
        default_place[def.key] = def.default
        valid[def.key] = true
    end
    local saved = G_reader_settings and G_reader_settings:readSetting("character_tracker_family_layout")
    local order, seen, placement = {}, {}, {}
    if type(saved) == "table" then
        for _i, key in ipairs(saved.order or {}) do
            if valid[key] and not seen[key] then
                seen[key] = true
                order[#order + 1] = key
            end
        end
    end
    for _i, def in ipairs(defs) do
        if not seen[def.key] then order[#order + 1] = def.key end
    end
    for _i, key in ipairs(order) do
        local place = type(saved) == "table" and saved.placement and saved.placement[key]
        if place ~= "main" and place ~= "more" and place ~= "hidden" then place = default_place[key] end
        placement[key] = place
    end
    return order, placement
end

function CharacterTracker:saveFamilyButtonLayout(order, placement)
    if not G_reader_settings then return end
    G_reader_settings:saveSetting("character_tracker_family_layout", { order = order, placement = placement })
end

function CharacterTracker:showFamilyDetail(family)
    self._tree_return_view = nil
    local viewer
    local function reopen() self:showFamilyDetail(family) end
    local actions = {}
    for _i, def in ipairs(self:_familyActions(family, reopen)) do actions[def.key] = def end
    local order, placement = self:getFamilyButtonLayout()
    local rows, row = {}, {}
    local function add(button)
        table.insert(row, button)
        if #row >= 4 then
            table.insert(rows, row)
            row = {}
        end
    end
    for _i, key in ipairs(order) do
        if placement[key] == "main" and actions[key] and familyActionApplies(key, family) then
            add({ text = actions[key].label, callback = function()
                UIManager:close(viewer)
                actions[key].run()
            end })
        end
    end
    add({ text = _("More"), callback = function()
        UIManager:close(viewer)
        self:showFamilyMoreMenu(family)
    end })
    if #row > 0 then table.insert(rows, row) end
    table.insert(rows, {
        { text = _("Delete"), callback = function()
            UIManager:close(viewer)
            self:deleteFamily(family)
        end },
        { text = _("Open list"), callback = function()
            UIManager:close(viewer)
            self:showFamilyList()
        end },
        { text = _("Close"), id = "close", callback = function()
            UIManager:close(viewer)
        end },
    })
    viewer = self:newTextViewer("family"){
        title = family.name or _("Family"),
        text = self:buildFamilyText(family),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = rows,
    }
    UIManager:show(viewer)
end

function CharacterTracker:showFamilyMoreMenu(family)
    local function reopen() self:showFamilyDetail(family) end
    local function close_and(fn)
        return function()
            UIManager:close(self._family_more_dialog)
            self._family_more_dialog = nil
            fn()
        end
    end
    local actions = {}
    for _i, def in ipairs(self:_familyActions(family, reopen)) do actions[def.key] = def end
    local order, placement = self:getFamilyButtonLayout()
    local rows, row = {}, {}
    for _i, key in ipairs(order) do
        if placement[key] == "more" and actions[key] and familyActionApplies(key, family) then
            table.insert(row, { text = actions[key].label, callback = close_and(function()
                actions[key].run()
            end) })
            if #row >= 2 then
                table.insert(rows, row)
                row = {}
            end
        end
    end
    if #row > 0 then table.insert(rows, row) end
    table.insert(rows, {
        { text = _("Customize buttons"), callback = close_and(function()
            self:showFamilyButtonCustomizer(family)
        end) },
    })
    table.insert(rows, {
        { text = _("Back"), id = "close", callback = close_and(reopen) },
    })
    self._family_more_dialog = self:newButtonDialog("family_more"){
        title = T(_("More — %1"), family.name),
        buttons = rows,
    }
    UIManager:show(self._family_more_dialog)
end

function CharacterTracker:showFamilyButtonCustomizer(family)
    local labels = {}
    for _i, def in ipairs(self:_familyActions({}, function() end)) do labels[def.key] = def.label end
    local order, placement = self:getFamilyButtonLayout()
    local group_names = { main = _("Main"), more = _("More"), hidden = _("Hidden") }
    local next_place = { main = "more", more = "hidden", hidden = "main" }
    local next_label = { main = _("→ More"), more = _("→ Hide"), hidden = _("→ Main") }
    local function reshow()
        UIManager:close(self._family_custom_dialog)
        self._family_custom_dialog = nil
        self:showFamilyButtonCustomizer(family)
    end
    local function neighbor(key, step)
        local index
        for i, k in ipairs(order) do
            if k == key then index = i end
        end
        local j = index + step
        while j >= 1 and j <= #order do
            if placement[order[j]] == placement[key] then return index, j end
            j = j + step
        end
        return index, nil
    end
    local buttons = {}
    for _i, group in ipairs({ "main", "more", "hidden" }) do
        for _j, key in ipairs(order) do
            if placement[key] == group and familyActionApplies(key, family) then
                table.insert(buttons, {
                    { text = "▲", callback = function()
                        local a, b = neighbor(key, -1)
                        if b then
                            order[a], order[b] = order[b], order[a]
                            self:saveFamilyButtonLayout(order, placement)
                        end
                        reshow()
                    end },
                    { text = "[" .. group_names[group] .. "] " .. labels[key], callback = function() end },
                    { text = "▼", callback = function()
                        local a, b = neighbor(key, 1)
                        if b then
                            order[a], order[b] = order[b], order[a]
                            self:saveFamilyButtonLayout(order, placement)
                        end
                        reshow()
                    end },
                    { text = next_label[group], callback = function()
                        placement[key] = next_place[group]
                        self:saveFamilyButtonLayout(order, placement)
                        reshow()
                    end },
                })
            end
        end
    end
    table.insert(buttons, {
        { text = _("Reset to default"), callback = function()
            if G_reader_settings then
                G_reader_settings:delSetting("character_tracker_family_layout")
            end
            reshow()
        end },
        { text = _("Done"), id = "close", callback = function()
            UIManager:close(self._family_custom_dialog)
            self._family_custom_dialog = nil
            self:showFamilyDetail(family)
        end },
    })
    self._family_custom_dialog = ButtonDialog:new{
        title = _("Family page buttons\n▲ / ▼ to move · the last button moves it between Main, More and Hidden"),
        buttons = buttons,
    }
    UIManager:show(self._family_custom_dialog)
end

function CharacterTracker:showFamilySectionOrderDialog(family)
    local order = self:getFamilySectionOrder(family)
    local buttons = {}
    for i, name in ipairs(order) do
        table.insert(buttons, {
            {
                text = "▲",
                callback = function()
                    UIManager:close(self._family_order_dialog)
                    self._family_order_dialog = nil
                    if i > 1 then
                        order[i], order[i - 1] = order[i - 1], order[i]
                        family.section_order = order
                        self:saveFamilies()
                    end
                    self:showFamilySectionOrderDialog(family)
                end,
            },
            {
                text = shorten(name, 30),
                callback = function() end,
            },
            {
                text = "▼",
                callback = function()
                    UIManager:close(self._family_order_dialog)
                    self._family_order_dialog = nil
                    if i < #order then
                        order[i], order[i + 1] = order[i + 1], order[i]
                        family.section_order = order
                        self:saveFamilies()
                    end
                    self:showFamilySectionOrderDialog(family)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Reset to member order"),
            callback = function()
                UIManager:close(self._family_order_dialog)
                self._family_order_dialog = nil
                family.section_order = {}
                self:saveFamilies()
                self:showFamilySectionOrderDialog(family)
            end,
        },
        {
            text = _("Done"),
            id = "close",
            callback = function()
                UIManager:close(self._family_order_dialog)
                self._family_order_dialog = nil
                self:showFamilyDetail(family)
            end,
        },
    })
    self._family_order_dialog = ButtonDialog:new{
        title = T(_("Member sections — %1\n(▲ / ▼ to move)"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._family_order_dialog)
end

function CharacterTracker:showFamilyTextFieldDialog(family, field, title, hint, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T("%1 — %2", title, family.name),
        input = family[field] or "",
        input_hint = hint,
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        family[field] = ""
                        self:saveFamilies()
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        family[field] = text
                        self:saveFamilies()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showFamilyNotesManager(family)
    self:showStringListManager(family, "notes", {
        title = _("Family notes"),
        add_label = _("+ Add note"),
        add_title = _("Add note"),
        edit_title = _("Edit note"),
        hint = _("history, scandals, anything worth remembering"),
        on_change = function()
            self:saveFamilies()
        end,
        on_close = function()
            self:showFamilyDetail(family)
        end,
    })
end

function CharacterTracker:showEntryNotesSecrets(family, entry, label, on_close, save)
    if type(entry.notes) ~= "table" then entry.notes = {} end
    if type(entry.secrets) ~= "table" then entry.secrets = {} end
    local function reopen()
        self:showEntryNotesSecrets(family, entry, label, on_close, save)
    end
    local function manage(field, title, add_label, add_title, edit_title, hint)
        self:showStringListManager({ name = label, [field] = entry[field] }, field, {
            title = title,
            add_label = add_label,
            add_title = add_title,
            edit_title = edit_title,
            hint = hint,
            on_change = function()
                if save then save() else self:saveFamilies() end
            end,
            on_close = reopen,
        })
    end
    local function close_and(fn)
        return function()
            UIManager:close(self._entry_lists_dialog)
            self._entry_lists_dialog = nil
            fn()
        end
    end
    self._entry_lists_dialog = ButtonDialog:new{
        title = shorten(label, 60),
        buttons = {
            {
                { text = T(_("Notes (%1)"), #entry.notes), callback = close_and(function()
                    manage("notes", _("Notes"), _("+ Add note"), _("Add note"), _("Edit note"), _("anything worth remembering about this"))
                end) },
                { text = T(_("Secrets (%1)"), #entry.secrets), callback = close_and(function()
                    manage("secrets", _("Secrets"), _("+ Add secret"), _("Add secret"), _("Edit secret"), _("something hidden about this"))
                end) },
            },
            {
                { text = _("Done"), id = "close", callback = close_and(on_close) },
            },
        },
    }
    UIManager:show(self._entry_lists_dialog)
end

function CharacterTracker:showFamilyRelationsManager(family, view)
    if view then self._tree_return_view = view end
    if type(family.relations) ~= "table" then family.relations = {} end
    local buttons = {}
    for i, rel in ipairs(family.relations) do
        local extras = ((rel.notes and #rel.notes or 0) + (rel.secrets and #rel.secrets or 0))
        table.insert(buttons, {
            {
                text = shorten(describeInnerRelation(rel), 40) .. (extras > 0 and (" ✎" .. extras) or ""),
                callback = function()
                    UIManager:close(self._family_rel_dialog)
                    self._family_rel_dialog = nil
                    self:showFamilyRelationActions(family, i)
                end,
                hold_callback = function()
                    local target_char = self:getCharacterByName(rel.to)
                    if target_char then
                        UIManager:close(self._family_rel_dialog)
                        self._family_rel_dialog = nil
                        self:showCharacterDetail(target_char)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("Character '%1' not found."), rel.to or "?"),
                        })
                    end
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._family_rel_dialog)
                    self._family_rel_dialog = nil
                    UIManager:show(ConfirmBox:new{
                        text = T(_("Delete link?\n\n%1"), describeInnerRelation(rel)),
                        ok_text = _("Delete"),
                        ok_callback = function()
                            self:_unsyncRelationFromCharacter(family.relations[i])
                            table.remove(family.relations, i)
                            self:saveFamilies()
                            self:_cleanupLinkedMembers()
                            self:showFamilyRelationsManager(family)
                        end,
                        cancel_callback = function()
                            self:showFamilyRelationsManager(family)
                        end,
                    })
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add relationship"),
            callback = function()
                UIManager:close(self._family_rel_dialog)
                self._family_rel_dialog = nil
                self:showAddFamilyRelation(family)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._family_rel_dialog)
                self._family_rel_dialog = nil
                local back_view = self._tree_return_view
                self._tree_return_view = nil
                if back_view then back_view:rebuild(back_view.scale) else self:showFamilyDetail(family) end
            end,
        },
    })
    self._family_rel_dialog = ButtonDialog:new{
        title = T(_("Inner relationships — %1"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._family_rel_dialog)
end

function CharacterTracker:_commitFamilyRelation(family, from, to, rel_type, sentiment, index)
    if index then
        local rel = family.relations[index]
        if rel then
            self:_unsyncRelationFromCharacter(rel)
            if rel_type ~= nil then rel.type = rel_type end
            rel.sentiment = sentiment or ""
            self:_syncRelationToCharacter(rel)
        end
        self:saveFamilies()
        UIManager:show(InfoMessage:new{ text = _("Relationship updated."), timeout = 1 })
        return
    end
    for _i, rel in ipairs(family.relations) do
        if lowerOrEmpty(rel.from) == lowerOrEmpty(from) and lowerOrEmpty(rel.to) == lowerOrEmpty(to)
           and (rel.type or "") == (rel_type or "") then
            if sentiment and sentiment ~= "" then
                rel.sentiment = sentiment
            end
            self:saveFamilies()
            UIManager:show(InfoMessage:new{
                text = _("Updated existing relationship."),
                timeout = 1,
            })
            return
        end
    end
    table.insert(family.relations, {
        from = from, to = to, type = rel_type or "", sentiment = sentiment or "",
        notes = {}, secrets = {},
    })
    self:_syncRelationToCharacter(family.relations[#family.relations])
    self:saveFamilies()
    local label = (rel_type and rel_type ~= "") and getRelationshipLabel(rel_type) or _("(sentiment only)")
    UIManager:show(InfoMessage:new{
        text = T(_("Linked '%1' → '%2' (%3)."), from, to, label),
        timeout = 2,
    })
end

function CharacterTracker:showAddFamilyRelation(family)
    if not family.members or #family.members < 2 then
        UIManager:show(InfoMessage:new{
            text = _("Add at least two members to the family first."),
        })
        self:showFamilyRelationsManager(family)
        return
    end
    self:_showChoice(_("Add relationship from…"), memberChoices(family, nil), function(from)
        self:_showChoice(T(_("Add relationship from '%1' to…"), from), memberChoices(family, from), function(to)
            self:_showChoice(T(_("'%1' is ___ of '%2'"), to, from), relationChoices(), function(rel_type)
                self:_showChoice(T(_("How does '%1' feel about '%2'?"), from, to), sentimentChoices(), function(sentiment)
                    self:_commitFamilyRelation(family, from, to, rel_type, sentiment)
                    self:showFamilyRelationsManager(family)
                end, { hint = _("e.g. jealous of, indebted to, wary of") })
            end, { hint = _("A custom tag, e.g. squire — or \"Mentor / Student\" to name both directions") })
        end)
    end)
end

function CharacterTracker:showFamilyRelationActions(family, index)
    local rel = family.relations[index]
    if not rel then return end
    local function close_and(fn)
        return function()
            UIManager:close(self._family_rel_act_dialog)
            self._family_rel_act_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = index + step
        if j >= 1 and j <= #family.relations then
            family.relations[index], family.relations[j] = family.relations[j], family.relations[index]
            self:saveFamilies()
        end
        self:showFamilyRelationsManager(family)
    end
    self._family_rel_act_dialog = ButtonDialog:new{
        title = shorten(describeInnerRelation(rel), 60),
        buttons = {
            {
                { text = T(_("Open '%1'"), rel.to or "?"), callback = close_and(function()
                    local target_char = self:getCharacterByName(rel.to)
                    if target_char then
                        self:showCharacterDetail(target_char)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("Character '%1' not found."), rel.to or "?"),
                        })
                        self:showFamilyRelationsManager(family)
                    end
                end) },
                { text = _("Notes & secrets"), callback = close_and(function()
                    self:showEntryNotesSecrets(family, rel, describeInnerRelation(rel), function()
                        self:showFamilyRelationsManager(family)
                    end)
                end) },
            },
            {
                { text = _("Change relationship type"), callback = close_and(function()
                    self:_showChoice(T(_("'%1' is ___ of '%2'"), rel.to or "?", rel.from or "?"), relationChoices(), function(value)
                        self:_commitFamilyRelation(family, rel.from, rel.to, value, rel.sentiment, index)
                        self:showFamilyRelationsManager(family)
                    end, { hint = _("A custom tag, e.g. squire — or \"Mentor / Student\" to name both directions") })
                end) },
            },
            {
                { text = getSentimentLabel(rel.sentiment) and _("Change sentiment") or _("Add sentiment"), callback = close_and(function()
                    self:_showChoice(T(_("How does '%1' feel about '%2'?"), rel.from or "?", rel.to or "?"), sentimentChoices(), function(value)
                        self:_commitFamilyRelation(family, rel.from, rel.to, nil, value, index)
                        self:showFamilyRelationsManager(family)
                    end, { hint = _("e.g. jealous of, indebted to, wary of") })
                end) },
            },
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function()
                    move(-1)
                end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function()
                    move(1)
                end) },
            },
            {
                { text = _("Delete"), callback = close_and(function()
                    self:_unsyncRelationFromCharacter(family.relations[index])
                    table.remove(family.relations, index)
                    self:saveFamilies()
                    self:_cleanupLinkedMembers()
                    self:showFamilyRelationsManager(family)
                end) },
                { text = _("Back"), id = "close", callback = close_and(function()
                    self:showFamilyRelationsManager(family)
                end) },
            },
        },
    }
    UIManager:show(self._family_rel_act_dialog)
end

function CharacterTracker:showFamilySuccessionManager(family)
    if type(family.succession) ~= "table" then family.succession = {} end
    local buttons = {}
    for i, entry in ipairs(family.succession) do
        local label = i .. ". " .. (entry.name or "?")
        if entry.note and entry.note ~= "" then
            label = label .. " — " .. entry.note
        end
        table.insert(buttons, {
            {
                text = shorten(label, 44),
                callback = function()
                    UIManager:close(self._family_succ_dialog)
                    self._family_succ_dialog = nil
                    self:showFamilySuccessionActions(family, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._family_succ_dialog)
                    self._family_succ_dialog = nil
                    table.remove(family.succession, i)
                    self:saveFamilies()
                    self:showFamilySuccessionManager(family)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add to line"),
            callback = function()
                UIManager:close(self._family_succ_dialog)
                self._family_succ_dialog = nil
                local taken = {}
                for _i, entry in ipairs(family.succession) do
                    taken[lowerOrEmpty(entry.name)] = true
                end
                local choices = {}
                for _i, choice in ipairs(memberChoices(family, nil)) do
                    if not taken[lowerOrEmpty(choice.value)] then
                        table.insert(choices, choice)
                    end
                end
                if #choices == 0 then
                    UIManager:show(InfoMessage:new{
                        text = _("Every member is already in the line of succession."),
                    })
                    self:showFamilySuccessionManager(family)
                    return
                end
                self:_showChoice(_("Next in line"), choices, function(name)
                    table.insert(family.succession, { name = name, note = "" })
                    self:saveFamilies()
                    self:showFamilySuccessionManager(family)
                end)
            end,
        },
        {
            text = _("Inheritance rule"),
            callback = function()
                UIManager:close(self._family_succ_dialog)
                self._family_succ_dialog = nil
                self:showFamilyTextFieldDialog(family, "inheritance", _("Inheritance"), _("e.g. eldest son first, elected by the council"), function()
                    self:showFamilySuccessionManager(family)
                end)
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._family_succ_dialog)
                self._family_succ_dialog = nil
                self:showFamilyDetail(family)
            end,
        },
    })
    self._family_succ_dialog = ButtonDialog:new{
        title = T(_("Line of succession — %1\n(first = next in line)"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._family_succ_dialog)
end

function CharacterTracker:showFamilySuccessionActions(family, index)
    local entry = family.succession[index]
    if not entry then return end
    local function close_and(fn)
        return function()
            UIManager:close(self._family_succ_act_dialog)
            self._family_succ_act_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = index + step
        if j >= 1 and j <= #family.succession then
            family.succession[index], family.succession[j] = family.succession[j], family.succession[index]
            self:saveFamilies()
        end
        self:showFamilySuccessionManager(family)
    end
    self._family_succ_act_dialog = ButtonDialog:new{
        title = entry.name or "?",
        buttons = {
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function()
                    move(-1)
                end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function()
                    move(1)
                end) },
            },
            {
                { text = _("Set note"), callback = close_and(function()
                    local dialog
                    dialog = InputDialog:new{
                        title = T(_("Note on %1's claim"), entry.name or "?"),
                        input = entry.note or "",
                        input_hint = _("e.g. heir apparent, disputed, contested by a cousin"),
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                        self:showFamilySuccessionManager(family)
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        entry.note = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        self:saveFamilies()
                                        self:showFamilySuccessionManager(family)
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end) },
                { text = _("Remove"), callback = close_and(function()
                    table.remove(family.succession, index)
                    self:saveFamilies()
                    self:showFamilySuccessionManager(family)
                end) },
            },
            {
                { text = _("Back"), id = "close", callback = close_and(function()
                    self:showFamilySuccessionManager(family)
                end) },
            },
        },
    }
    UIManager:show(self._family_succ_act_dialog)
end

function CharacterTracker:showFamilyTraitsManager(family)
    if type(family.traits) ~= "table" then family.traits = {} end
    local buttons = {}
    for i, trait in ipairs(family.traits) do
        table.insert(buttons, {
            {
                text = shorten((trait.kind or _("Trait")) .. ": " .. (trait.text or ""), 44),
                callback = function()
                    UIManager:close(self._family_trait_dialog)
                    self._family_trait_dialog = nil
                    self:showFamilyTraitActions(family, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._family_trait_dialog)
                    self._family_trait_dialog = nil
                    table.remove(family.traits, i)
                    self:saveFamilies()
                    self:showFamilyTraitsManager(family)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add family trait"),
            callback = function()
                UIManager:close(self._family_trait_dialog)
                self._family_trait_dialog = nil
                self:_showChoice(T(_("What kind of trait is shared by '%1'?"), family.name), traitKindChoices(), function(kind)
                    self:showFamilyTraitTextDialog(family, nil, kind)
                end, { hint = _("e.g. oath, gift, taboo") })
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._family_trait_dialog)
                self._family_trait_dialog = nil
                self:showFamilyDetail(family)
            end,
        },
    })
    self._family_trait_dialog = ButtonDialog:new{
        title = T(_("Family traits — %1\n(shared abilities, powers, curses…)"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._family_trait_dialog)
end

function CharacterTracker:showFamilyTraitActions(family, index)
    local trait = family.traits[index]
    if not trait then return end
    local function close_and(fn)
        return function()
            UIManager:close(self._family_trait_act_dialog)
            self._family_trait_act_dialog = nil
            fn()
        end
    end
    local function move(step)
        local j = index + step
        if j >= 1 and j <= #family.traits then
            family.traits[index], family.traits[j] = family.traits[j], family.traits[index]
            self:saveFamilies()
        end
        self:showFamilyTraitsManager(family)
    end
    self._family_trait_act_dialog = ButtonDialog:new{
        title = shorten((trait.kind or _("Trait")) .. ": " .. (trait.text or ""), 60),
        buttons = {
            {
                { text = _("Edit text"), callback = close_and(function()
                    self:showFamilyTraitTextDialog(family, index)
                end) },
                { text = _("Change kind"), callback = close_and(function()
                    self:_showChoice(_("Kind of trait"), traitKindChoices(), function(kind)
                        trait.kind = kind
                        self:saveFamilies()
                        self:showFamilyTraitsManager(family)
                    end, { hint = _("e.g. oath, gift, taboo") })
                end) },
            },
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function()
                    move(-1)
                end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function()
                    move(1)
                end) },
            },
            {
                { text = _("Delete"), callback = close_and(function()
                    table.remove(family.traits, index)
                    self:saveFamilies()
                    self:showFamilyTraitsManager(family)
                end) },
                { text = _("Back"), id = "close", callback = close_and(function()
                    self:showFamilyTraitsManager(family)
                end) },
            },
        },
    }
    UIManager:show(self._family_trait_act_dialog)
end

function CharacterTracker:showFamilyTraitTextDialog(family, index, kind)
    local trait = index and family.traits[index] or nil
    local dialog
    dialog = InputDialog:new{
        title = T(_("%1 shared by '%2'"), (trait and trait.kind) or kind or _("Trait"), family.name),
        input = trait and trait.text or "",
        input_hint = _("Describe it"),
        text_height = math.floor(Device.screen:getHeight() * 0.3),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showFamilyTraitsManager(family)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if text ~= "" then
                            if trait then
                                trait.text = text
                            else
                                table.insert(family.traits, { kind = kind, text = text })
                            end
                            self:saveFamilies()
                        end
                        self:showFamilyTraitsManager(family)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showFamilyHousesManager(family)
    if type(family.houses) ~= "table" then family.houses = {} end
    local buttons = {}
    for i, house in ipairs(family.houses) do
        local extras = ((house.notes and #house.notes or 0) + (house.secrets and #house.secrets or 0))
        table.insert(buttons, {
            {
                text = shorten(describeHouse(house), 40) .. (extras > 0 and (" ✎" .. extras) or ""),
                callback = function()
                    UIManager:close(self._family_house_dialog)
                    self._family_house_dialog = nil
                    self:showFamilyHouseActions(family, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._family_house_dialog)
                    self._family_house_dialog = nil
                    table.remove(family.houses, i)
                    self:saveFamilies()
                    self:showFamilyHousesManager(family)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add alliance / house"),
            callback = function()
                UIManager:close(self._family_house_dialog)
                self._family_house_dialog = nil
                self:showAddFamilyHouse(family)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._family_house_dialog)
                self._family_house_dialog = nil
                self:showFamilyDetail(family)
            end,
        },
    })
    self._family_house_dialog = ButtonDialog:new{
        title = T(_("Alliances & houses — %1"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._family_house_dialog)
end

function CharacterTracker:showAddFamilyHouse(family)
    local choices = {}
    for _i, other in ipairs(self.families) do
        if other ~= family and other.name then
            table.insert(choices, { label = other.name, value = other.name })
        end
    end
    self:_showChoice(T(_("Which house relates to '%1'?"), family.name), choices, function(other_name)
        self:_showChoice(T(_("'%1' and '%2' are…"), family.name, other_name), houseKindChoices(), function(kind)
            self:_showChoice(T(_("How does '%1' feel about '%2'?"), family.name, other_name), sentimentChoices(), function(sentiment)
                table.insert(family.houses, {
                    family = other_name, kind = kind, sentiment = sentiment,
                    notes = {}, secrets = {},
                })
                self:saveFamilies()
                self:showFamilyHousesManager(family)
            end, { hint = _("e.g. wary of, indebted to") })
        end, { hint = _("e.g. sworn to, at war with") })
    end, { hint = _("Name of the other house") })
end

function CharacterTracker:showFamilyHouseActions(family, index)
    local house = family.houses[index]
    if not house then return end
    local function close_and(fn)
        return function()
            UIManager:close(self._family_house_act_dialog)
            self._family_house_act_dialog = nil
            fn()
        end
    end
    self._family_house_act_dialog = ButtonDialog:new{
        title = shorten(describeHouse(house), 60),
        buttons = {
            {
                { text = _("Notes & secrets"), callback = close_and(function()
                    self:showEntryNotesSecrets(family, house, describeHouse(house), function()
                        self:showFamilyHousesManager(family)
                    end)
                end) },
            },
            {
                { text = _("Change relationship"), callback = close_and(function()
                    self:_showChoice(T(_("'%1' and '%2' are…"), family.name, house.family or "?"), houseKindChoices(), function(value)
                        house.kind = value
                        self:saveFamilies()
                        self:showFamilyHousesManager(family)
                    end, { hint = _("e.g. sworn to, at war with") })
                end) },
                { text = _("Change sentiment"), callback = close_and(function()
                    self:_showChoice(T(_("How does '%1' feel about '%2'?"), family.name, house.family or "?"), sentimentChoices(), function(value)
                        house.sentiment = value
                        self:saveFamilies()
                        self:showFamilyHousesManager(family)
                    end, { hint = _("e.g. wary of, indebted to") })
                end) },
            },
            {
                { text = _("Open house"), callback = close_and(function()
                    local other = self:getFamilyByName(house.family)
                    if other then
                        self:showFamilyDetail(other)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("'%1' isn't a tracked family."), house.family or "?"),
                        })
                        self:showFamilyHousesManager(family)
                    end
                end) },
                { text = _("Delete"), callback = close_and(function()
                    table.remove(family.houses, index)
                    self:saveFamilies()
                    self:showFamilyHousesManager(family)
                end) },
            },
            {
                { text = _("Back"), id = "close", callback = close_and(function()
                    self:showFamilyHousesManager(family)
                end) },
            },
        },
    }
    UIManager:show(self._family_house_act_dialog)
end

function CharacterTracker:showAddFamilyDialog(preselected_name)
    local dialog
    dialog = InputDialog:new{
        input = preselected_name or "",
        title = _("Add family"),
        input_hint = _("Family name (e.g. House Stark, the Baggins family)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name == "" then return end
                        local function create(kind)
                            local family = {
                                id = genId(),
                                name = name,
                                description = "",
                                members = {},
                                motto = "",
                                seat = "",
                                notes = {},
                                relations = {},
                                houses = {},
                                sigil = "",
                                inheritance = "",
                                succession = {},
                                traits = {},
                                holdings = {},
                                history = {},
                                secrets = {},
                                section_order = {},
                                placeholders = {},
                                couple_styles = {},
                                tree_kind = kind,
                                social_ties = {},
                                social_groups = {},
                                dynamics = {},
                                rel_format = 2,
                                created = os.date("%Y-%m-%d %H:%M"),
                            }
                            table.insert(self.families, family)
                            self:saveFamilies()
                            self:showFamilyDetail(family)
                        end
                        self:_showChoice(T(_("What kind of tree is '%1'?"), name), {
                            { label = _("Family tree (blood & marriage ties)"), value = "family" },
                            { label = _("Relationship tree (friends, dating, rivals…)"), value = "social" },
                        }, function(kind)
                            create(kind)
                        end)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showRenameFamilyDialog(family, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Rename '%1'"), family.name),
        input = family.name or "",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local name = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if name ~= "" then
                            local old_lower = (family.name or ""):lower()
                            family.name = name
                            for _i, other in ipairs(self.families) do
                                for _j, house in ipairs(other.houses or {}) do
                                    if (house.family or ""):lower() == old_lower then
                                        house.family = name
                                    end
                                end
                            end
                            self:saveFamilies()
                        end
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showFamilyDescriptionDialog(family, on_done)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Description — %1"), family.name),
        input = family.description or "",
        input_hint = _("House words, history, standing… anything you like"),
        text_height = math.floor(Device.screen:getHeight() * 0.35),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        family.description = text
                        self:saveFamilies()
                        if on_done then on_done() end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showFamilyMembersManager(family)
    if not family.members then family.members = {} end
    local buttons = {}
    for i, member in ipairs(family.members) do
        local label = member.name or "?"
        if member.role and member.role ~= "" then
            label = label .. "  —  " .. member.role
        end
        label = shorten(label, 46)
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._family_members_dialog)
                    self._family_members_dialog = nil
                    self:showFamilyMemberActions(family, i)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._family_members_dialog)
                    self._family_members_dialog = nil
                    self:_removeFamilyMember(family, i)
                    self:showFamilyMembersManager(family)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add member"),
            callback = function()
                UIManager:close(self._family_members_dialog)
                self._family_members_dialog = nil
                self:showAddFamilyMemberPicker(family)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._family_members_dialog)
                self._family_members_dialog = nil
            end,
        },
    })
    self._family_members_dialog = ButtonDialog:new{
        title = T(_("Members — %1"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._family_members_dialog)
end

function CharacterTracker:showFamilyMemberActions(family, index)
    local member = family.members[index]
    if not member then return end
    local function close_and(fn)
        return function()
            UIManager:close(self._family_member_act_dialog)
            self._family_member_act_dialog = nil
            fn()
        end
    end
    local function swap(a, b)
        if b >= 1 and b <= #family.members then
            family.members[a], family.members[b] = family.members[b], family.members[a]
            self:saveFamilies()
        end
        self:showFamilyMembersManager(family)
    end
    self._family_member_act_dialog = ButtonDialog:new{
        title = T(_("%1 — %2"), family.name, member.name or "?"),
        buttons = {
            {
                { text = "▲ " .. _("Move up"), callback = close_and(function()
                    swap(index, index - 1)
                end) },
                { text = "▼ " .. _("Move down"), callback = close_and(function()
                    swap(index, index + 1)
                end) },
            },
            {
                { text = _("Edit role"), callback = close_and(function()
                    self:showFamilyMemberRoleDialog(family, index)
                end) },
                { text = _("Set tie"), callback = close_and(function()
                    self:_showChoice(T(_("How is '%1' tied to '%2'?"), member.name or "?", family.name), tieChoices(), function(value)
                        member.tie = value
                        self:saveFamilies()
                        self:showFamilyMembersManager(family)
                    end, { hint = _("e.g. cousin by marriage, sworn shield") })
                end) },
            },
            {
                { text = _("Parents"), callback = close_and(function()
                    self:showFamilyMemberParents(family, index)
                end) },
                { text = _("Tree name & title"), callback = close_and(function()
                    self:showFamilyTreeNameDialog(family, member, function()
                        self:showFamilyMembersManager(family)
                    end)
                end) },
            },
            {
                { text = _("Set gender"), callback = close_and(function()
                    self:showFamilyGenderDialog(member, function()
                        self:showFamilyMembersManager(family)
                    end)
                end) },
            },
            {
                { text = _("Open character"), callback = close_and(function()
                    local char = self:getCharacterByName(member.name)
                    if char then
                        self:showCharacterDetail(char)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("'%1' isn't a tracked character."), member.name or "?"),
                        })
                        self:showFamilyMembersManager(family)
                    end
                end) },
            },
            {
                { text = _("Remove from family"), callback = close_and(function()
                    self:_removeFamilyMember(family, index)
                    self:showFamilyMembersManager(family)
                end) },
                { text = _("Cancel"), id = "close", callback = close_and(function()
                    self:showFamilyMembersManager(family)
                end) },
            },
        },
    }
    UIManager:show(self._family_member_act_dialog)
end

function CharacterTracker:_uniqueFamilyName(family, base)
    local name = base
    local n = 1
    while memberByName(family, name) or placeholderByName(family, name) do
        n = n + 1
        name = base .. " " .. n
    end
    return name
end

function CharacterTracker:showFamilyMemberParents(family, index)
    local member = family.members[index]
    if not member then return end
    if type(member.parents) ~= "table" then member.parents = {} end
    if type(family.placeholders) ~= "table" then family.placeholders = {} end
    local function reopen()
        self:showFamilyMemberParents(family, index)
    end
    local buttons = {}
    for i, parent in ipairs(member.parents) do
        local placeholder = placeholderByName(family, parent)
        local kind = member.parent_kinds and member.parent_kinds[lowerOrEmpty(parent)] or nil
        local kind_labels = {
            adopted = _("adopted"), guardian = _("guardian"), step = _("step"), foster = _("foster"),
        }
        table.insert(buttons, {
            {
                text = (placeholder and ("[" .. parent .. "]") or parent)
                    .. (kind and kind_labels[kind] and (" (" .. kind_labels[kind] .. ")") or ""),
                callback = function()
                    UIManager:close(self._family_parents_dialog)
                    self._family_parents_dialog = nil
                    local choices = {
                        { label = _("Biological"), value = "" },
                        { label = _("Adopted"), value = "adopted" },
                        { label = _("Guardian"), value = "guardian" },
                        { label = _("Step-parent"), value = "step" },
                        { label = _("Foster parent"), value = "foster" },
                    }
                    if placeholder then
                        table.insert(choices, { label = _("Replace or rename…"), value = "__placeholder" })
                    end
                    self:_showChoice(T(_("How is '%1' linked to '%2'?"), parent, member.name or "?"), choices, function(value)
                        if value == "__placeholder" then
                            self:showFamilyPlaceholderActions(family, placeholder, reopen)
                            return
                        end
                        if type(member.parent_kinds) ~= "table" then member.parent_kinds = {} end
                        member.parent_kinds[lowerOrEmpty(parent)] = value ~= "" and value or nil
                        self:saveFamilies()
                        reopen()
                    end)
                end,
            },
            {
                text = "✕",
                callback = function()
                    UIManager:close(self._family_parents_dialog)
                    self._family_parents_dialog = nil
                    table.remove(member.parents, i)
                    self:saveFamilies()
                    reopen()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Add parent"),
            callback = function()
                UIManager:close(self._family_parents_dialog)
                self._family_parents_dialog = nil
                local taken = { [(member.name or ""):lower()] = true }
                for _i, parent in ipairs(member.parents) do
                    taken[parent:lower()] = true
                end
                local child_key = (member.name or ""):lower()
                local choices = {}
                for _i, other in ipairs(family.members) do
                    if other.name and not taken[other.name:lower()] then
                        table.insert(choices, { label = other.name, value = other.name })
                    end
                end
                for _i, ph in ipairs(family.placeholders) do
                    if not taken[ph.name:lower()] then
                        table.insert(choices, { label = "[" .. ph.name .. "]", value = ph.name })
                    end
                end
                if #choices == 0 then
                    UIManager:show(InfoMessage:new{
                        text = _("No other members available to add as a parent."),
                    })
                    reopen()
                    return
                end
                self:_showChoice(T(_("Parent of '%1'"), member.name or "?"), choices, function(name)
                    if name:lower() ~= child_key then
                        table.insert(member.parents, name)
                        self:saveFamilies()
                    end
                    reopen()
                end)
            end,
        },
        {
            text = _("+ Placeholder parent"),
            callback = function()
                UIManager:close(self._family_parents_dialog)
                self._family_parents_dialog = nil
                local kinds = {
                    { label = _("Father"), value = _("father") },
                    { label = _("Mother"), value = _("mother") },
                    { label = _("Parent"), value = _("parent") },
                }
                self:_showChoice(T(_("Unknown parent of '%1'"), member.name or "?"), kinds, function(kind)
                    local name = self:_uniqueFamilyName(family, T(_("%1's %2"), member.name or "?", kind))
                    table.insert(family.placeholders, { name = name })
                    table.insert(member.parents, name)
                    self:saveFamilies()
                    reopen()
                end, { hint = _("e.g. guardian, grandfather") })
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Done"),
            id = "close",
            callback = function()
                UIManager:close(self._family_parents_dialog)
                self._family_parents_dialog = nil
                local back_view = self._tree_return_view
                self._tree_return_view = nil
                if back_view then back_view:rebuild(back_view.scale) else self:showFamilyMembersManager(family) end
            end,
        },
    })
    self._family_parents_dialog = ButtonDialog:new{
        title = T(_("Parents of %1\n(used to build the family tree)\n[brackets] = placeholder, tap to replace"), member.name or "?"),
        buttons = buttons,
    }
    UIManager:show(self._family_parents_dialog)
end

function CharacterTracker:_placeholderChildren(family, ph)
    local key = lowerOrEmpty(ph.name)
    local out = {}
    for _i, member in ipairs(family.members) do
        for _j, parent in ipairs(member.parents or {}) do
            if lowerOrEmpty(parent) == key then
                table.insert(out, member)
                break
            end
        end
    end
    return out
end

function CharacterTracker:_removePlaceholder(family, ph)
    local key = lowerOrEmpty(ph.name)
    for _i, member in ipairs(family.members) do
        for j = #(member.parents or {}), 1, -1 do
            if lowerOrEmpty(member.parents[j]) == key then
                table.remove(member.parents, j)
            end
        end
    end
    for i = #family.placeholders, 1, -1 do
        if family.placeholders[i] == ph then
            table.remove(family.placeholders, i)
        end
    end
end

function CharacterTracker:_replacePlaceholder(family, ph, new_name)
    local key = lowerOrEmpty(ph.name)
    local target = memberByName(family, new_name)
    if not target then
        local char = self:getCharacterByName(new_name)
        table.insert(family.members, {
            name = char and char.name or new_name,
            role = "",
            tie = "",
            parents = {},
        })
        new_name = family.members[#family.members].name
    else
        new_name = target.name
    end
    local new_key = lowerOrEmpty(new_name)
    self:_renameCoupleStyleKeys(family, ph.name, new_name)
    for _i, member in ipairs(family.members) do
        local list = member.parents or {}
        local has_new = false
        for _j, parent in ipairs(list) do
            if lowerOrEmpty(parent) == new_key then has_new = true end
        end
        for j = #list, 1, -1 do
            if lowerOrEmpty(list[j]) == key then
                if has_new or lowerOrEmpty(member.name) == new_key then
                    table.remove(list, j)
                else
                    self:_renameParentKind(member, list[j], new_name)
                    list[j] = new_name
                    has_new = true
                end
            end
        end
    end
    for i = #family.placeholders, 1, -1 do
        if family.placeholders[i] == ph then
            table.remove(family.placeholders, i)
        end
    end
    self:saveFamilies()
end

function CharacterTracker:showFamilyPlaceholderActions(family, ph, back)
    local function close_and(fn)
        return function()
            UIManager:close(self._family_ph_dialog)
            self._family_ph_dialog = nil
            fn()
        end
    end
    local children = self:_placeholderChildren(family, ph)
    local names = {}
    for _i, child in ipairs(children) do table.insert(names, child.name) end
    self._family_ph_dialog = ButtonDialog:new{
        title = T(_("Placeholder: %1\nParent of: %2"), ph.name, #names > 0 and table.concat(names, ", ") or "—"),
        buttons = {
            {
                { text = _("Replace with a character"), callback = close_and(function()
                    local child_set = {}
                    for _i, child in ipairs(children) do child_set[lowerOrEmpty(child.name)] = true end
                    local choices, listed = {}, {}
                    for _i, member in ipairs(family.members) do
                        local key = lowerOrEmpty(member.name)
                        if member.name and not child_set[key] then
                            listed[key] = true
                            table.insert(choices, { label = member.name, value = member.name })
                        end
                    end
                    for _i, char in ipairs(self.characters or {}) do
                        local key = lowerOrEmpty(char.name)
                        if char.name and not listed[key] and not child_set[key] then
                            listed[key] = true
                            table.insert(choices, { label = char.name .. " +", value = char.name })
                        end
                    end
                    if #choices == 0 then
                        UIManager:show(InfoMessage:new{
                            text = _("No characters available to use."),
                        })
                        back()
                        return
                    end
                    self:_showChoice(T(_("Who is '%1'?\n(+ = not yet in this family)"), ph.name), choices, function(name)
                        self:_replacePlaceholder(family, ph, name)
                        UIManager:show(InfoMessage:new{
                            text = T(_("'%1' replaced."), ph.name),
                            timeout = 1,
                        })
                        back()
                    end)
                end) },
                { text = _("Rename"), callback = close_and(function()
                    local dialog
                    dialog = InputDialog:new{
                        title = T(_("Rename '%1'"), ph.name),
                        input = ph.name,
                        buttons = {
                            {
                                {
                                    text = _("Cancel"),
                                    id = "close",
                                    callback = function()
                                        UIManager:close(dialog)
                                        back()
                                    end,
                                },
                                {
                                    text = _("Save"),
                                    is_enter_default = true,
                                    callback = function()
                                        local text = trim(dialog:getInputText())
                                        UIManager:close(dialog)
                                        local clash = memberByName(family, text) or placeholderByName(family, text)
                                        if text ~= "" and (not clash or clash == ph) then
                                            local old_key = lowerOrEmpty(ph.name)
                                            self:_renameCoupleStyleKeys(family, ph.name, text)
                                            for _i, member in ipairs(family.members) do
                                                for k, parent in ipairs(member.parents or {}) do
                                                    if lowerOrEmpty(parent) == old_key then
                                                        self:_renameParentKind(member, parent, text)
                                                        member.parents[k] = text
                                                    end
                                                end
                                            end
                                            ph.name = text
                                            self:saveFamilies()
                                        elseif text ~= "" then
                                            UIManager:show(InfoMessage:new{
                                                text = _("That name is already used in this family."),
                                            })
                                        end
                                        back()
                                    end,
                                },
                            },
                        },
                    }
                    self:_showInputDialog(dialog)
                end) },
            },
            {
                { text = _("Remove placeholder"), callback = close_and(function()
                    self:_removePlaceholder(family, ph)
                    self:saveFamilies()
                    back()
                end) },
                { text = _("Back"), id = "close", callback = close_and(back) },
            },
        },
    }
    UIManager:show(self._family_ph_dialog)
end

function CharacterTracker:showFamilyPlaceholdersManager(family)
    if type(family.placeholders) ~= "table" then family.placeholders = {} end
    local buttons = {}
    for _i, ph in ipairs(family.placeholders) do
        local count = #self:_placeholderChildren(family, ph)
        table.insert(buttons, {
            {
                text = shorten("[" .. ph.name .. "]", 36) .. (count > 0 and (" · " .. count) or ""),
                callback = function()
                    UIManager:close(self._family_ph_list_dialog)
                    self._family_ph_list_dialog = nil
                    self:showFamilyPlaceholderActions(family, ph, function()
                        self:showFamilyPlaceholdersManager(family)
                    end)
                end,
            },
        })
    end
    if #buttons == 0 then
        table.insert(buttons, {
            {
                text = _("No placeholders yet — add one from a member's Parents"),
                callback = function() end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._family_ph_list_dialog)
                self._family_ph_list_dialog = nil
                self:showFamilyDetail(family)
            end,
        },
    })
    self._family_ph_list_dialog = ButtonDialog:new{
        title = T(_("Placeholder parents — %1\n(tap one to replace it with a character)"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._family_ph_list_dialog)
end

function CharacterTracker:_familyRoleHint(family)
    if family and family.tree_kind == "social" then
        return _("e.g. the leader, the peacemaker, the joker")
    end
    return _("e.g. head of house, heir, matriarch, disowned")
end

function CharacterTracker:showFamilyMemberRoleDialog(family, index)
    local member = family.members[index]
    if not member then return end
    local dialog
    dialog = InputDialog:new{
        title = T(_("Role in '%1' for '%2'"), family.name, member.name or "?"),
        input = member.role or "",
        input_hint = self:_familyRoleHint(family),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        self:showFamilyMembersManager(family)
                    end,
                },
                {
                    text = _("Clear"),
                    callback = function()
                        UIManager:close(dialog)
                        member.role = ""
                        self:saveFamilies()
                        self:showFamilyMembersManager(family)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local text = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        member.role = text
                        self:saveFamilies()
                        self:showFamilyMembersManager(family)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showAddFamilyMemberPicker(family)
    local buttons = {}
    local row = {}
    for _i, char in ipairs(self.characters) do
        table.insert(row, {
            text = char.name,
            callback = function()
                UIManager:close(self._add_family_member_dialog)
                self._add_family_member_dialog = nil
                self:showAddFamilyMemberRoleDialog(family, char.name)
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Other / custom name…"),
            callback = function()
                UIManager:close(self._add_family_member_dialog)
                self._add_family_member_dialog = nil
                local dialog
                dialog = InputDialog:new{
                    title = _("Member name"),
                    input_hint = _("Name of the family member"),
                    buttons = {{
                        { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
                        { text = _("Next"), is_enter_default = true, callback = function()
                            local name = dialog:getInputText():match("^%s*(.-)%s*$")
                            UIManager:close(dialog)
                            if name == "" then return end
                            self:showAddFamilyMemberRoleDialog(family, name)
                        end },
                    }},
                }
                self:_showInputDialog(dialog)
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._add_family_member_dialog)
                self._add_family_member_dialog = nil
            end,
        },
    })
    self._add_family_member_dialog = ButtonDialog:new{
        title = T(_("Add member to '%1'"), family.name),
        buttons = buttons,
    }
    UIManager:show(self._add_family_member_dialog)
end

function CharacterTracker:showAddFamilyMemberRoleDialog(family, member_name)
    if family.tree_kind == "social" then
        table.insert(family.members, { name = member_name, role = "" })
        self:saveFamilies()
        self:showFamilyMembersManager(family)
        return
    end
    local dialog
    dialog = InputDialog:new{
        title = T(_("Role of '%1' in '%2'? (optional)"), member_name, family.name),
        input_hint = self:_familyRoleHint(family),
        buttons = {
            {
                {
                    text = _("Skip"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        table.insert(family.members, { name = member_name, role = "" })
                        self:saveFamilies()
                        self:showFamilyMembersManager(family)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local role = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        table.insert(family.members, { name = member_name, role = role })
                        self:saveFamilies()
                        self:showFamilyMembersManager(family)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:deleteFamily(family)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete family '%1'?"), family.name),
        ok_text = _("Delete"),
        ok_callback = function()
            for i = #self.families, 1, -1 do
                if self.families[i].id == family.id then
                    table.remove(self.families, i)
                    break
                end
            end
            self:saveFamilies()
            UIManager:show(InfoMessage:new{
                text = T(_("Deleted family '%1'."), family.name),
                timeout = 2,
            })
        end,
    })
end

function CharacterTracker:showLinkSeriesDialog()
    local available = self:getAvailableSeries()

    if #available > 0 then
        local buttons = {}
        for _i, s in ipairs(available) do
            table.insert(buttons, {
                {
                    text = s.name .. " (" .. s.count .. " chars)",
                    callback = function()
                        UIManager:close(self._series_picker)
                        self._series_picker = nil
                        self:linkToSeries(s.name)
                    end,
                },
                {
                    text = _("X"),
                    callback = function()
                        UIManager:close(self._series_picker)
                        self._series_picker = nil
                        self:confirmDeleteSeries(s)
                    end,
                },
            })
        end
        table.insert(buttons, {
            {
                text = _("＋ New series"),
                callback = function()
                    UIManager:close(self._series_picker)
                    self._series_picker = nil
                    self:showNewSeriesDialog()
                end,
            },
        })
        table.insert(buttons, {
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(self._series_picker)
                    self._series_picker = nil
                end,
            },
        })
        self._series_picker = ButtonDialog:new{
            title = _("Link book to series"),
            buttons = buttons,
        }
        UIManager:show(self._series_picker)
    else
        self:showNewSeriesDialog()
    end
end

function CharacterTracker:showNewSeriesDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("New series"),
        input_hint = _("Series name (e.g. A Song of Ice and Fire)"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Create & link"),
                    is_enter_default = true,
                    callback = function()
                        local series = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if series == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Series name cannot be empty."),
                            })
                            return
                        end
                        self:linkToSeries(series)
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:linkToSeries(series_name)
    local old_characters = self.characters
    local had_characters = #old_characters > 0
    local old_places = self.places or {}
    local old_compendium = self.compendium or {}
    local old_families = self.families or {}
    local old_timelines = self.timelines or {}

    self:_flushSaveData()

    self:setSeriesName(series_name)
    self:loadData()
    self:loadPlaces()
    self:loadCompendium()
    self:loadFamilies()
    self:loadTimelines()

    if #self.places == 0 and #old_places > 0 then
        self.places = old_places
        self:savePlaces()
    end
    if #self.compendium == 0 and #old_compendium > 0 then
        self.compendium = old_compendium
        self:saveCompendium()
    end
    if #self.families == 0 and #old_families > 0 then
        self.families = old_families
        self:saveFamilies()
    end
    if #self.timelines == 0 and #old_timelines > 0 then
        self.timelines = old_timelines
        self:saveTimeline()
    end

    local series_had_characters = #self.characters > 0

    if had_characters then
        local merged = self:mergeCharacters(old_characters)
        self:saveData()
        self:rebuildAllMarks()

        local msg
        if series_had_characters then
            msg = T(_("Linked to series '%1'.\nMerged characters: %2 new added, %3 already in series."),
                series_name, merged, #old_characters - merged)
        else
            msg = T(_("Linked to series '%1'.\n%2 characters moved to shared series."),
                series_name, #self.characters)
        end
        UIManager:show(InfoMessage:new{ text = msg })
    else
        if series_had_characters then
            self:rebuildAllMarks()
            UIManager:show(InfoMessage:new{
                text = T(_("Linked to series '%1'.\nLoaded %2 shared characters."),
                    series_name, #self.characters),
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Linked to series '%1'.\nNo characters yet — they will be shared across all books in this series."),
                    series_name),
            })
        end
    end
end

function CharacterTracker:unlinkFromSeries()
    local series = self:getSeriesName()
    if not series or series == "" then return end

    UIManager:show(ConfirmBox:new{
        text = T(_("Unlink this book from series '%1'?\n\nThe shared series characters will remain in the series. This book will start with an empty character list."), series),
        ok_text = _("Unlink"),
        ok_callback = function()
            self:_flushSaveData()
            self:setSeriesName(nil)
            self.characters = {}
            self:_rebuildNameIndex()
            self:saveData()
            self:loadPlaces()
            self:loadCompendium()
            self:loadFamilies()
            self:loadTimelines()
            self:rebuildAllMarks()
            UIManager:show(InfoMessage:new{
                text = T(_("Unlinked from series '%1'."), series),
                timeout = 2,
            })
        end,
    })
end

function CharacterTracker:getAvailableSeries()
    local series = {}
    local dir = self:getSeriesDir()
    for entry in lfs.dir(dir) do
        if entry:match("%.json$")
           and not entry:match("%.places%.json$")
           and not entry:match("%.compendium%.json$")
           and not entry:match("%.families%.json$")
           and not entry:match("%.timeline%.json$") then
            local name = entry:gsub("%.json$", ""):gsub("_", " ")
            local path = dir .. "/" .. entry
            local chars = self:loadCharactersFromFile(path)
            table.insert(series, {
                name = name,
                path = path,
                count = #chars,
            })
        end
    end
    return series
end

function CharacterTracker:characterMatchesQuery(char, q)
    if not q or q == "" then return false end
    if char.name:lower():find(q, 1, true) then return true end
    if char.aliases then
        for _i, alias in ipairs(char.aliases) do
            if alias:lower():find(q, 1, true) then return true end
        end
    end
    return false
end

function CharacterTracker:characterMatchesStructFilter(char, f)
    if not f or not f.value then return true end
    local value_lower = f.value:lower()
    if f.kind == "status" then
        if not char.status or char.status == "" then return false end
        return getStatusLabel(char.status):lower() == value_lower
    elseif f.kind == "faction" then
        for _i, fac in ipairs(char.factions or {}) do
            if fac:lower() == value_lower then return true end
        end
        return false
    elseif f.kind == "place" then
        for _i, name in ipairs(self:getCharacterResidencePlaceNames(char)) do
            if name:lower() == value_lower then return true end
        end
        return false
    end
    return true
end

function CharacterTracker:_collectFilterValues(kind)
    local seen = {}
    local values = {}
    local function add(v)
        if not v or v == "" then return end
        local key = v:lower()
        if not seen[key] then
            seen[key] = true
            table.insert(values, v)
        end
    end
    if kind == "status" then
        for _i, char in ipairs(self.characters) do
            if char.status and char.status ~= "" then
                add(getStatusLabel(char.status))
            end
        end
    elseif kind == "faction" then
        for _i, char in ipairs(self.characters) do
            for _j, f in ipairs(char.factions or {}) do add(f) end
        end
    elseif kind == "place" then
        for _i, char in ipairs(self.characters) do
            for _j, name in ipairs(self:getCharacterResidencePlaceNames(char)) do add(name) end
        end
    end
    table.sort(values, function(a, b) return a:lower() < b:lower() end)
    return values
end

function CharacterTracker:showCharacterFilterDialog()
    local buttons = {
        {
            {
                text = _("By status"),
                callback = function()
                    UIManager:close(self._filter_kind_dialog)
                    self._filter_kind_dialog = nil
                    self:showFilterValuePicker("status")
                end,
            },
        },
        {
            {
                text = _("By faction"),
                callback = function()
                    UIManager:close(self._filter_kind_dialog)
                    self._filter_kind_dialog = nil
                    self:showFilterValuePicker("faction")
                end,
            },
        },
        {
            {
                text = _("By place"),
                callback = function()
                    UIManager:close(self._filter_kind_dialog)
                    self._filter_kind_dialog = nil
                    self:showFilterValuePicker("place")
                end,
            },
        },
    }
    if self._struct_filter then
        table.insert(buttons, {
            {
                text = T(_("Clear filter (%1 = %2)"), self._struct_filter.kind, self._struct_filter.value),
                callback = function()
                    UIManager:close(self._filter_kind_dialog)
                    self._filter_kind_dialog = nil
                    self._struct_filter = nil
                    self:showCharacterList()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._filter_kind_dialog)
                self._filter_kind_dialog = nil
            end,
        },
    })
    self._filter_kind_dialog = ButtonDialog:new{
        title = _("Filter characters by…"),
        buttons = buttons,
    }
    UIManager:show(self._filter_kind_dialog)
end

function CharacterTracker:showFilterValuePicker(kind)
    local values = self:_collectFilterValues(kind)
    if #values == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Nothing to filter by yet - no characters have that set."),
        })
        return
    end
    local buttons = {}
    local row = {}
    for _i, v in ipairs(values) do
        table.insert(row, {
            text = v,
            callback = function()
                UIManager:close(self._filter_value_dialog)
                self._filter_value_dialog = nil
                self._struct_filter = { kind = kind, value = v }
                self:showCharacterList()
            end,
        })
        if #row >= 2 then
            table.insert(buttons, row)
            row = {}
        end
    end
    if #row > 0 then table.insert(buttons, row) end
    table.insert(buttons, {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                UIManager:close(self._filter_value_dialog)
                self._filter_value_dialog = nil
            end,
        },
    })
    self._filter_value_dialog = ButtonDialog:new{
        title = _("Filter value"),
        buttons = buttons,
    }
    UIManager:show(self._filter_value_dialog)
end

function CharacterTracker:showSeriesCharacterSearch()
    local dialog
    dialog = InputDialog:new{
        title = _("Search series characters"),
        input_hint = _("Name or alias to search for"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local q = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if q == "" then return end
                        self:showSeriesSearchResults(q:lower())
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showSeriesSearchResults(q)
    local results = {}
    if not self:getSeriesName() then
        for _i, char in ipairs(self.characters) do
            if self:characterMatchesQuery(char, q) then
                table.insert(results, { char = char, source = _("This book") })
            end
        end
    end
    for _i, s in ipairs(self:getAvailableSeries()) do
        local chars = self:loadCharactersFromFile(s.path)
        for _j, char in ipairs(chars) do
            if self:characterMatchesQuery(char, q) then
                table.insert(results, { char = char, source = s.name })
            end
        end
    end

    if #results == 0 then
        UIManager:show(InfoMessage:new{
            text = T(_("No characters match '%1'."), q),
        })
        return
    end

    local item_table = {}
    for _i, r in ipairs(results) do
        local aliases = ""
        if r.char.aliases and #r.char.aliases > 0 then
            aliases = "\n    aka: " .. table.concat(r.char.aliases, ", ")
        end
        table.insert(item_table, {
            text = r.char.name .. "  ·  " .. r.source .. aliases,
            callback = function()
                UIManager:close(self._search_menu)
                self._search_menu = nil
                local viewer
                viewer = self:newTextViewer("search_result"){
                    title = r.char.name .. " (" .. r.source .. ")",
                    text = T(_("Occupation: %1\nCharacter type: %2\nNotes: %3"),
                        (r.char.occupation and r.char.occupation ~= "") and r.char.occupation or _("(not set)"),
                        getCharacterTypeLabel(r.char.char_type or r.char.role or ""),
                        (r.char.notes and #r.char.notes > 0) and tostring(#r.char.notes) or _("none")),
                    width = math.floor(Device.screen:getWidth() * 0.9),
                    height = math.floor(Device.screen:getHeight() * 0.85),
                    buttons_table = {
                        {
                            {
                                text = _("Close"),
                                id = "close",
                                callback = function()
                                    UIManager:close(viewer)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(viewer)
            end,
        })
    end

    local menu_container
    local menu
    menu = Menu:new{
        title = T(_("Search results: '%1' (%2)"), q, #results),
        item_table = item_table,
        is_borderless = true,
        covers_fullscreen_widget = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        onMenuSelect = function(_self, item)
            if item.callback then item.callback() end
        end,
        close_callback = function()
            UIManager:close(menu_container)
        end,
    }
    self._search_menu = menu
    menu_container = CenterContainer:new{
        dimen = Screen:getSize(),
        menu,
    }
    menu.show_parent = menu_container
    UIManager:show(menu_container)
end

function CharacterTracker:showCharacterSearch()
    local dialog
    dialog = InputDialog:new{
        title = _("Search characters"),
        input_hint = _("Name or alias"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Search"),
                    is_enter_default = true,
                    callback = function()
                        local q = dialog:getInputText():match("^%s*(.-)%s*$")
                        UIManager:close(dialog)
                        if q == "" then
                            self:showCharacterList()
                        else
                            self:showCharacterList(q)
                        end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showCharacterSortDialog()
    local current = self._sort_mode or "default"
    local modes = {
        { key = "default", label = _("Default (added order)") },
        { key = "name", label = _("Name (A-Z)") },
        { key = "char_type", label = _("Character type") },
        { key = "occupation", label = _("Occupation") },
        { key = "created", label = _("Date added") },
        { key = "manual", label = _("Manual (your own order)") },
    }
    local buttons = {}
    for _i, m in ipairs(modes) do
        local label = m.label
        if current == m.key then
            label = "✓ " .. label
        end
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._sort_dialog)
                    self._sort_dialog = nil
                    self._sort_mode = m.key == "default" and nil or m.key
                    if m.key == "manual" then
                        self:showReorderCharactersDialog()
                    else
                        self:showCharacterList()
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Reorder characters…"),
            callback = function()
                UIManager:close(self._sort_dialog)
                self._sort_dialog = nil
                self._sort_mode = "manual"
                self:showReorderCharactersDialog()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._sort_dialog)
                self._sort_dialog = nil
            end,
        },
    })
    self._sort_dialog = ButtonDialog:new{
        title = _("Sort characters"),
        buttons = buttons,
    }
    UIManager:show(self._sort_dialog)
end

function CharacterTracker:moveCharacter(index, delta)
    local new_index = index + delta
    if new_index < 1 or new_index > #self.characters then return end
    self.characters[index], self.characters[new_index] =
        self.characters[new_index], self.characters[index]
    self:saveData()
end

function CharacterTracker:showReorderCharactersDialog()
    if not self.characters or #self.characters == 0 then
        UIManager:show(InfoMessage:new{ text = _("No characters to reorder.") })
        return
    end
    local buttons = {}
    for i, char in ipairs(self.characters) do
        local short = char.name
        short = shorten(short, 28)
        table.insert(buttons, {
            {
                text = "▲",
                callback = function()
                    UIManager:close(self._reorder_dialog)
                    self._reorder_dialog = nil
                    self:moveCharacter(i, -1)
                    self:showReorderCharactersDialog()
                end,
            },
            {
                text = short,
                callback = function()
                    UIManager:close(self._reorder_dialog)
                    self._reorder_dialog = nil
                    self:showCharacterDetailReadOnly(char)
                end,
            },
            {
                text = "▼",
                callback = function()
                    UIManager:close(self._reorder_dialog)
                    self._reorder_dialog = nil
                    self:moveCharacter(i, 1)
                    self:showReorderCharactersDialog()
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._reorder_dialog)
                self._reorder_dialog = nil
            end,
        },
    })
    self._reorder_dialog = ButtonDialog:new{
        title = _("Reorder characters (▲ / ▼ to move)"),
        buttons = buttons,
    }
    UIManager:show(self._reorder_dialog)
end

function CharacterTracker:_applyMatchCap(cap)
    G_reader_settings:saveSetting("character_tracker_max_matches_per_name", cap)
    if self.mark_enabled or self.place_mark_enabled or self.object_mark_enabled then
        self:rebuildAllMarks()
    end
    UIManager:show(InfoMessage:new{
        text = T(_("Max matches per name set to %1."),
            cap >= UNLIMITED_MATCHES and _("unlimited") or cap),
        timeout = 2,
    })
end

function CharacterTracker:showCustomMatchCapDialog()
    local current = self:getMatchCap()
    local dialog
    dialog = InputDialog:new{
        title = T(_("Custom max mentions per name\n(not recommended above %1)"), RECOMMENDED_MAX_MATCHES),
        input = current < UNLIMITED_MATCHES and tostring(current) or "",
        input_type = "number",
        input_hint = _("A whole number, e.g. 1200"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local n = tonumber(dialog:getInputText():match("^%s*(%d+)%s*$"))
                        UIManager:close(dialog)
                        if not n or n < 1 then
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a whole number of at least 1."),
                            })
                            return
                        end
                        n = math.min(n, UNLIMITED_MATCHES)
                        if n > RECOMMENDED_MAX_MATCHES and n < UNLIMITED_MATCHES then
                            UIManager:show(ConfirmBox:new{
                                text = T(_("%1 is above the recommended %2: indexing will take longer and the saved index will be larger, which may cause lag or delays.\n\nUse it anyway?"),
                                    n, RECOMMENDED_MAX_MATCHES),
                                ok_text = _("Use it"),
                                ok_callback = function()
                                    self:_applyMatchCap(n)
                                end,
                            })
                        else
                            self:_applyMatchCap(n)
                        end
                    end,
                },
            },
        },
    }
    self:_showInputDialog(dialog)
end

function CharacterTracker:showMatchCapDialog()
    local current = self:getMatchCap()
    local buttons = {}
    local presets = { 400, 800, 1200, 1600, UNLIMITED_MATCHES }
    local is_preset = false
    for _i, cap in ipairs(presets) do
        local label = tostring(cap)
        if cap == UNLIMITED_MATCHES then
            label = _("Unlimited (may cause lag / delay)")
        elseif cap == MAX_MATCHES_PER_NAME then
            label = label .. " " .. _("(default)")
        end
        if cap == current then
            label = "✓ " .. label
            is_preset = true
        end
        table.insert(buttons, {
            {
                text = label,
                callback = function()
                    UIManager:close(self._match_cap_dialog)
                    self._match_cap_dialog = nil
                    if cap == UNLIMITED_MATCHES and current ~= UNLIMITED_MATCHES then
                        UIManager:show(ConfirmBox:new{
                            text = _("Unlimited indexes every mention of every name. On a long book the first index can take much longer and the saved index gets much bigger, which may cause lag or delays.\n\nUse unlimited anyway?"),
                            ok_text = _("Use unlimited"),
                            ok_callback = function()
                                self:_applyMatchCap(cap)
                            end,
                        })
                    else
                        self:_applyMatchCap(cap)
                    end
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = (is_preset and "" or "✓ ") .. T(_("Custom… (not recommended above %1)"), RECOMMENDED_MAX_MATCHES),
            callback = function()
                UIManager:close(self._match_cap_dialog)
                self._match_cap_dialog = nil
                self:showCustomMatchCapDialog()
            end,
        },
    })
    table.insert(buttons, {
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._match_cap_dialog)
                self._match_cap_dialog = nil
            end,
        },
    })
    self._match_cap_dialog = ButtonDialog:new{
        title = _("Max mentions indexed per name\nMentions past this number (counting from the start of the book) aren't underlined. Higher = slower first index, bigger cache."),
        buttons = buttons,
    }
    UIManager:show(self._match_cap_dialog)
end

local DETAIL_RETURN_POLL = 0.3

function CharacterTracker:_disarmDetailReturn()
    self._detail_return = nil
end

function CharacterTracker:_armDetailReturn(character, reopen)
    local stack = UIManager._window_stack
    if not stack or not reopen then return end
    local state = { character = character, reopen = reopen, baseline = #stack, idle = 0 }
    self._detail_return = state
    local function poll()
        if self._detail_return ~= state or self._closed then return end
        if #UIManager._window_stack <= state.baseline then
            state.idle = state.idle + 1
        else
            state.idle = 0
        end
        if state.idle >= 2 then
            self._detail_return = nil
            if self:getCharacterIndex(character) then reopen() end
            return
        end
        UIManager:scheduleIn(DETAIL_RETURN_POLL, poll)
    end
    UIManager:scheduleIn(DETAIL_RETURN_POLL, poll)
end

local LAYOUT_TEMPLATES_KEY = "character_tracker_layout_templates"
local LAYOUT_ACTIVE_KEY = "character_tracker_layout_template_active"
local LAYOUT_BOOL_KEYS = {
    "character_tracker_hide_type", "character_tracker_hide_age",
    "character_tracker_hide_belongings", "character_tracker_hide_last_seen",
    "character_tracker_hide_family", "character_tracker_hide_readonly_tree_button",
    "character_tracker_short_tree_label", "character_tracker_hide_readonly_edit_button",
    "character_tracker_hide_counts",
}
for _i, kind in ipairs({ "character", "highlight", "topic", "place", "compendium",
        "family", "appearance", "timeline", "family_excerpt" }) do
    table.insert(LAYOUT_BOOL_KEYS, "character_tracker_hide_selection_" .. kind)
end
local LAYOUT_HIDDEN_KEYS = {
    "character_tracker_hidden_character_sections",
    "character_tracker_hidden_place_sections",
    "character_tracker_hidden_compendium_sections",
}

local function layoutDeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = layoutDeepCopy(x) end
    return out
end

local function layoutDeepEqual(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do
        if not layoutDeepEqual(v, b[k]) then return false end
    end
    for k in pairs(b) do
        if a[k] == nil then return false end
    end
    return true
end

function CharacterTracker:snapshotLayout()
    local snap = { bools = {}, hidden = {}, order = self:getSectionOrder(), buttons = {}, badges = {} }
    for _i, key in ipairs(LAYOUT_BOOL_KEYS) do
        snap.bools[key] = LayoutSettings:isTrue(key)
    end
    for _i, key in ipairs(LAYOUT_HIDDEN_KEYS) do
        local out = {}
        local saved = LayoutSettings:readSetting(key)
        if type(saved) == "table" then
            for k, v in pairs(saved) do
                if v == true then out[k] = true end
            end
        end
        snap.hidden[key] = out
    end
    local layouts = LayoutSettings:readSetting("character_tracker_button_layouts")
    if type(layouts) == "table" then
        for area, entry in pairs(layouts) do
            if type(entry) == "table" and entry.mode ~= "default" then
                snap.buttons[area] = { mode = entry.mode, count = entry.count }
            end
        end
    end
    local order, hidden = self:getListBadgeLayout()
    snap.badges = { order = order, hidden = hidden }
    return snap
end

function CharacterTracker:applyLayoutSnapshot(snap)
    for key, value in pairs(snap.bools or {}) do
        LayoutSettings:saveSetting(key, value == true)
    end
    for key, value in pairs(snap.hidden or {}) do
        LayoutSettings:saveSetting(key, layoutDeepCopy(value))
    end
    LayoutSettings:saveSetting("character_tracker_section_order", layoutDeepCopy(snap.order or {}))
    LayoutSettings:saveSetting("character_tracker_button_layouts", layoutDeepCopy(snap.buttons or {}))
    LayoutSettings:saveSetting("character_tracker_list_badges", layoutDeepCopy(snap.badges or {}))
end

function CharacterTracker:getLayoutTemplates()
    local saved = G_reader_settings:readSetting(LAYOUT_TEMPLATES_KEY)
    return type(saved) == "table" and saved or {}
end

function CharacterTracker:saveLayoutTemplate(name, snap)
    local all = layoutDeepCopy(self:getLayoutTemplates())
    all[name] = snap
    G_reader_settings:saveSetting(LAYOUT_TEMPLATES_KEY, all)
end

function CharacterTracker:deleteLayoutTemplate(name)
    local all = layoutDeepCopy(self:getLayoutTemplates())
    all[name] = nil
    G_reader_settings:saveSetting(LAYOUT_TEMPLATES_KEY, all)
    if LayoutSettings:readSetting(LAYOUT_ACTIVE_KEY) == name then
        LayoutSettings:delSetting(LAYOUT_ACTIVE_KEY)
    end
end

function CharacterTracker:getActiveLayoutTemplate()
    local name = LayoutSettings:readSetting(LAYOUT_ACTIVE_KEY)
    local template = name and self:getLayoutTemplates()[name]
    if not template then return nil, false end
    return name, not layoutDeepEqual(template, self:snapshotLayout())
end

function CharacterTracker:showLayoutScopeDialog(on_done)
    local per_book = LayoutSettings:isPerBook()
    local choices = {
        { label = (per_book and "" or "✓ ") .. _("All books share one layout"), value = "global" },
        { label = (per_book and "✓ " or "") .. _("Each book keeps its own layout"), value = "book" },
    }
    if per_book then
        table.insert(choices, { label = _("Use this book's layout for all books"), value = "promote" })
        table.insert(choices, { label = _("Reset this book to the shared layout"), value = "reset" })
    end
    self:_showChoice(_("Where do page layout settings apply?\n(hidden sections, order, buttons per row)"), choices, function(value)
        if value == "global" or value == "book" then
            if value == "book" and not LayoutSettings.doc then return end
            G_reader_settings:saveSetting(LAYOUT_SCOPE_KEY, value)
        elseif value == "promote" then
            local snap = self:snapshotLayout()
            G_reader_settings:saveSetting(LAYOUT_SCOPE_KEY, "global")
            self:applyLayoutSnapshot(snap)
            G_reader_settings:saveSetting(LAYOUT_SCOPE_KEY, "book")
        elseif value == "reset" then
            local doc = LayoutSettings.doc
            if doc then
                for _i, key in ipairs(LAYOUT_BOOL_KEYS) do doc:delSetting(key) end
                for _i, key in ipairs(LAYOUT_HIDDEN_KEYS) do doc:delSetting(key) end
                for _i, key in ipairs({ "character_tracker_section_order", "character_tracker_button_layouts",
                        "character_tracker_list_badges", LAYOUT_ACTIVE_KEY }) do
                    doc:delSetting(key)
                end
            end
        end
        if on_done then on_done() end
    end)
end

function CharacterTracker:showSaveLayoutTemplateDialog(on_done, existing_name)
    local dialog
    dialog = InputDialog:new{
        title = _("Name this layout template"),
        input = existing_name or "",
        input_hint = _("e.g. Fantasy, Nonfiction"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                        if on_done then on_done() end
                    end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local name = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if name == "" then
                            if on_done then on_done() end
                            return
                        end
                        local function store()
                            self:saveLayoutTemplate(name, self:snapshotLayout())
                            LayoutSettings:saveSetting(LAYOUT_ACTIVE_KEY, name)
                            UIManager:show(InfoMessage:new{
                                text = T(_("Saved layout template '%1'."), name), timeout = 2,
                            })
                            if on_done then on_done() end
                        end
                        if self:getLayoutTemplates()[name] and name ~= existing_name then
                            UIManager:show(ConfirmBox:new{
                                text = T(_("A template named '%1' already exists. Replace it?"), name),
                                ok_text = _("Replace"),
                                ok_callback = store,
                                cancel_callback = function() if on_done then on_done() end end,
                            })
                        else
                            store()
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CharacterTracker:showLayoutTemplateActions(name, on_done)
    self:_showChoice(T(_("Template '%1'"), name), {
        { label = _("Apply"), value = "apply" },
        { label = _("Update with current layout"), value = "update" },
        { label = _("Rename"), value = "rename" },
        { label = _("Delete"), value = "delete" },
    }, function(value)
        local template = self:getLayoutTemplates()[name]
        if not template then
            if on_done then on_done() end
            return
        end
        if value == "apply" then
            self:applyLayoutSnapshot(template)
            LayoutSettings:saveSetting(LAYOUT_ACTIVE_KEY, name)
            UIManager:show(InfoMessage:new{ text = T(_("Applied '%1'."), name), timeout = 2 })
            if on_done then on_done() end
        elseif value == "update" then
            self:saveLayoutTemplate(name, self:snapshotLayout())
            LayoutSettings:saveSetting(LAYOUT_ACTIVE_KEY, name)
            UIManager:show(InfoMessage:new{ text = T(_("Updated '%1'."), name), timeout = 2 })
            if on_done then on_done() end
        elseif value == "rename" then
            local dialog
            dialog = InputDialog:new{
                title = T(_("Rename '%1'"), name),
                input = name,
                buttons = {
                    {
                        { text = _("Cancel"), id = "close", callback = function()
                            UIManager:close(dialog)
                            if on_done then on_done() end
                        end },
                        { text = _("Rename"), is_enter_default = true, callback = function()
                            local new_name = trim(dialog:getInputText())
                            UIManager:close(dialog)
                            if new_name ~= "" and new_name ~= name and not self:getLayoutTemplates()[new_name] then
                                self:saveLayoutTemplate(new_name, template)
                                local was_active = LayoutSettings:readSetting(LAYOUT_ACTIVE_KEY) == name
                                self:deleteLayoutTemplate(name)
                                if was_active then LayoutSettings:saveSetting(LAYOUT_ACTIVE_KEY, new_name) end
                            end
                            if on_done then on_done() end
                        end },
                    },
                },
            }
            UIManager:show(dialog)
            dialog:onShowKeyboard()
        else
            UIManager:show(ConfirmBox:new{
                text = T(_("Delete layout template '%1'?"), name),
                ok_text = _("Delete"),
                ok_callback = function()
                    self:deleteLayoutTemplate(name)
                    if on_done then on_done() end
                end,
                cancel_callback = function() if on_done then on_done() end end,
            })
        end
    end)
end

function CharacterTracker:showLayoutTemplatesDialog(on_done)
    local active, customized = self:getActiveLayoutTemplate()
    local scope = LayoutSettings:isPerBook() and _("this book only") or _("all books")
    local status = active
        and T(_("Current: %1%2"), active, customized and (" (" .. _("customized") .. ")") or "")
        or _("Current: no template")
    local function reshow()
        UIManager:close(self._layout_templates_dialog)
        self._layout_templates_dialog = nil
        self:showLayoutTemplatesDialog(on_done)
    end
    local names = {}
    for name in pairs(self:getLayoutTemplates()) do table.insert(names, name) end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    local buttons = {}
    for _i, name in ipairs(names) do
        table.insert(buttons, {
            {
                text = (name == active and "✓ " or "") .. name,
                callback = function()
                    UIManager:close(self._layout_templates_dialog)
                    self._layout_templates_dialog = nil
                    self:showLayoutTemplateActions(name, reshow)
                end,
            },
        })
    end
    table.insert(buttons, {
        {
            text = _("+ Save current layout as template"),
            callback = function()
                UIManager:close(self._layout_templates_dialog)
                self._layout_templates_dialog = nil
                self:showSaveLayoutTemplateDialog(reshow)
            end,
        },
    })
    table.insert(buttons, {
        {
            text = T(_("Applies to: %1"), scope),
            callback = function()
                UIManager:close(self._layout_templates_dialog)
                self._layout_templates_dialog = nil
                self:showLayoutScopeDialog(reshow)
            end,
        },
        {
            text = _("Close"),
            id = "close",
            callback = function()
                UIManager:close(self._layout_templates_dialog)
                self._layout_templates_dialog = nil
                if on_done then on_done() end
            end,
        },
    })
    self._layout_templates_dialog = ButtonDialog:new{
        title = _("Layout templates") .. "\n" .. status
            .. "\n" .. _("A template stores hidden sections, order, and buttons per row."),
        buttons = buttons,
    }
    UIManager:show(self._layout_templates_dialog)
end

function CharacterTracker:addToMainMenu(menu_items)
    menu_items.character_tracker = {
        text = _("Character Tracker"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Character list"),
                keep_menu_open = false,
                callback = function()
                    self:showCharacterList(nil, nil, true)
                end,
            },
            {
                text = _("Edit character list"),
                keep_menu_open = false,
                callback = function()
                    self:showCharacterList()
                end,
            },
            {
                text = _("Search characters"),
                keep_menu_open = false,
                callback = function()
                    self:showCharacterSearch()
                end,
            },
            {
                text = _("Sort characters"),
                keep_menu_open = false,
                callback = function()
                    self:showCharacterSortDialog()
                end,
            },
            {
                text = _("Filter characters"),
                keep_menu_open = false,
                callback = function()
                    self:showCharacterFilterDialog()
                end,
            },
            {
                text = _("Add character"),
                keep_menu_open = false,
                callback = function()
                    self:showAddCharacterDialog()
                end,
            },
            {
                text = _("Places"),
                keep_menu_open = false,
                callback = function()
                    self:showPlaceList()
                end,
            },
            {
                text = _("Add place"),
                keep_menu_open = false,
                callback = function()
                    self:showAddPlaceDialog(nil)
                end,
            },
            {
                text = _("Compendium"),
                keep_menu_open = false,
                callback = function()
                    self:showCompendiumList()
                end,
            },
            {
                text = _("Add compendium entry"),
                keep_menu_open = false,
                callback = function()
                    self:showAddCompendiumDialog()
                end,
            },
            {
                text = _("Families"),
                keep_menu_open = false,
                callback = function()
                    self:showFamilyList()
                end,
            },
            {
                text = _("Add family"),
                keep_menu_open = false,
                callback = function()
                    self:showAddFamilyDialog()
                end,
            },
            {
                text = _("Family tree"),
                keep_menu_open = false,
                callback = function()
                    self:showFamilyTreePicker(true)
                end,
            },
            {
                text = _("Edit family tree"),
                keep_menu_open = false,
                callback = function()
                    self:showFamilyTreePicker(false)
                end,
            },
            {
                text = _("Timeline"),
                keep_menu_open = false,
                callback = function()
                    self:showTimelineList()
                end,
            },
            {
                text = _("Add timeline event"),
                keep_menu_open = false,
                callback = function()
                    self:showTimelineQuickAdd()
                end,
            },
            {
                text = _("Underline names in text"),
                checked_func = function()
                    return self.mark_enabled
                end,
                callback = function()
                    self.mark_enabled = not self.mark_enabled
                    self.ui.doc_settings:saveSetting("character_tracker_underline", self.mark_enabled)
                    self._paint_cache_key = nil
                    if self.mark_enabled then
                        if not next(self.marks_by_charname) then
                            self:rebuildAllMarks()
                        end
                    else
                        self.marks_by_charname = {}
                        self:_indexMarks()
                        self.visible_boxes = {}
                    end
                    UIManager:setDirty(self.dialog, "ui")
                end,
            },
            {
                text = _("Underline places in text"),
                checked_func = function()
                    return self.place_mark_enabled
                end,
                callback = function()
                    self.place_mark_enabled = not self.place_mark_enabled
                    self.ui.doc_settings:saveSetting("character_tracker_underline_places", self.place_mark_enabled)
                    self._paint_cache_key = nil
                    if self.place_mark_enabled then
                        if not next(self.marks_by_placename) then
                            self:rebuildAllMarks()
                        end
                    else
                        self.marks_by_placename = {}
                        self:_indexMarks()
                        self.visible_boxes = {}
                    end
                    UIManager:setDirty(self.dialog, "ui")
                end,
            },
            {
                text = _("Underline objects in text"),
                checked_func = function()
                    return self.object_mark_enabled
                end,
                callback = function()
                    self.object_mark_enabled = not self.object_mark_enabled
                    self.ui.doc_settings:saveSetting("character_tracker_underline_objects", self.object_mark_enabled)
                    self._paint_cache_key = nil
                    if self.object_mark_enabled then
                        if not next(self.marks_by_objname) then
                            self:rebuildAllMarks()
                        end
                    else
                        self.marks_by_objname = {}
                        self:_indexMarks()
                        self.visible_boxes = {}
                    end
                    UIManager:setDirty(self.dialog, "ui")
                end,
            },
            {
                text = _("Invisible underline"),
                checked_func = function()
                    return self.underline_invisible
                end,
                callback = function()
                    self.underline_invisible = not self.underline_invisible
                    self.ui.doc_settings:saveSetting("character_tracker_underline_invisible", self.underline_invisible)
                    self._paint_cache_key = nil
                    UIManager:setDirty(self.dialog, "ui")
                end,
            },
            {
                text = _("Tapping a name opens the edit view"),
                checked_func = function()
                    return self:isTapOpensEdit()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    G_reader_settings:saveSetting("character_tracker_tap_opens_edit",
                        not self:isTapOpensEdit())
                end,
            },
            {
                text = _("Relationship wording"),
                keep_menu_open = false,
                callback = function()
                    self:showRelationshipStyleDialog()
                end,
            },
            {
                text = _("Arrange character page sections"),
                keep_menu_open = false,
                callback = function()
                    self:showSectionOrderDialog()
                end,
            },
            {
                text = _("Layout templates & scope"),
                keep_menu_open = false,
                callback = function()
                    self:showLayoutTemplatesDialog()
                end,
            },
            {
                text = _("Max matches per name"),
                keep_menu_open = false,
                callback = function()
                    self:showMatchCapDialog()
                end,
            },
            {
                text = _("Re-index now"),
                keep_menu_open = false,
                callback = function()
                    if not (self.mark_enabled or self.place_mark_enabled or self.object_mark_enabled) then
                        UIManager:show(InfoMessage:new{
                            text = _("Nothing to index - turn on an \"Underline ... in text\" option first."),
                            timeout = 3,
                        })
                        return
                    end
                    self:rebuildAllMarks(true)
                end,
            },
            {
                text = _("Search series characters"),
                keep_menu_open = false,
                callback = function()
                    self:showSeriesCharacterSearch()
                end,
            },
            {
                text = _("Export characters"),
                keep_menu_open = false,
                callback = function()
                    self:showExportDialog()
                end,
            },
            {
                text = _("Import characters"),
                keep_menu_open = false,
                callback = function()
                    self:showImportDialog()
                end,
            },
            {
                text = _("Undo last delete"),
                keep_menu_open = false,
                callback = function()
                    self:restoreLastDeleted()
                end,
            },
            {
                text = _("Link to series"),
                keep_menu_open = false,
                callback = function()
                    local series = self:getSeriesName()
                    if series and series ~= "" then
                        self:showSeriesOptions()
                    else
                        self:showLinkSeriesDialog()
                    end
                end,
            },
            {
                text = _("Hide character type"),
                checked_func = function()
                    return self:isTypeHidden()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    LayoutSettings:saveSetting("character_tracker_hide_type",
                        not self:isTypeHidden())
                end,
            },
            {
                text = _("Hide age"),
                checked_func = function()
                    return self:isAgeHidden()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    LayoutSettings:saveSetting("character_tracker_hide_age",
                        not self:isAgeHidden())
                end,
            },
            {
                text = _("Hide character belongings"),
                checked_func = function()
                    return self:isBelongingsHidden()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    LayoutSettings:saveSetting("character_tracker_hide_belongings",
                        not self:isBelongingsHidden())
                end,
            },
            {
                text = _("Hide last seen"),
                checked_func = function()
                    return self:isLastSeenHidden()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    LayoutSettings:saveSetting("character_tracker_hide_last_seen",
                        not self:isLastSeenHidden())
                end,
            },
            {
                text = _("Hide family roles"),
                checked_func = function()
                    return self:isFamilyHidden()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    LayoutSettings:saveSetting("character_tracker_hide_family",
                        not self:isFamilyHidden())
                end,
            },
        },
    }

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Character list details (order & hide)"),
        keep_menu_open = true,
        callback = function()
            self:showListBadgesDialog()
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide family tree button (read-only character page)"),
        checked_func = function()
            return self:isReadOnlyTreeButtonHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            LayoutSettings:saveSetting("character_tracker_hide_readonly_tree_button",
                not self:isReadOnlyTreeButtonHidden())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Call the family tree button \"Tree\" (read-only character page)"),
        checked_func = function()
            return self:isShortTreeLabel()
        end,
        callback = function()
            if not G_reader_settings then return end
            LayoutSettings:saveSetting("character_tracker_short_tree_label",
                not self:isShortTreeLabel())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide edit button (read-only character page)"),
        checked_func = function()
            return self:isReadOnlyEditButtonHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            LayoutSettings:saveSetting("character_tracker_hide_readonly_edit_button",
                not self:isReadOnlyEditButtonHidden())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide counts in page headings"),
        checked_func = function()
            return G_reader_settings ~= nil
                and LayoutSettings:isTrue("character_tracker_hide_counts")
        end,
        callback = function()
            if not G_reader_settings then return end
            LayoutSettings:saveSetting("character_tracker_hide_counts",
                not LayoutSettings:isTrue("character_tracker_hide_counts"))
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide index limit warning"),
        checked_func = function()
            return self:isIndexLimitWarningHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_hide_index_limit_warning",
                not self:isIndexLimitWarningHidden())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide underline in family tree"),
        checked_func = function()
            return self:isTreeUnderlineHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_tree_hide_underline",
                not self:isTreeUnderlineHidden())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Sync family tree relationships with character list"),
        checked_func = function()
            return self:isRelationSyncOn()
        end,
        callback = function()
            self:toggleRelationSync()
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide shot button in timeline"),
        checked_func = function()
            return self:isTimelineShotHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_timeline_hide_shot",
                not self:isTimelineShotHidden())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide shot button in family tree"),
        checked_func = function()
            return self:isTreeShotHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_tree_hide_shot",
                not self:isTreeShotHidden())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide generation labels in family tree"),
        checked_func = function()
            return self:isTreeGenerationsHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_tree_hide_generations",
                not self:isTreeGenerationsHidden())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Show line legend in family tree"),
        checked_func = function()
            return self:isTreeLegendOn()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_tree_legend", not self:isTreeLegendOn())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Sync relationship tree ties with character list"),
        checked_func = function()
            return self:isSocialSyncOn()
        end,
        callback = function()
            self:toggleSocialSync()
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Show family ties in relationship trees"),
        checked_func = function()
            return self:isSocialShowFamily()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_social_show_family", not self:isSocialShowFamily())
        end,
    })

    local button_layout_texts = {}
    for _i, area in ipairs(BUTTON_AREAS) do
        local text = _("Buttons") .. " · " .. area.label
        table.insert(button_layout_texts, text)
        table.insert(menu_items.character_tracker.sub_item_table, {
            text = text,
            keep_menu_open = true,
            callback = function()
                self:showButtonLayoutDialog(area.key, area.label)
            end,
        })
    end

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Label ties in relationship trees"),
        checked_func = function()
            return self:isSocialLabelsOn()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_social_labels", not self:isSocialLabelsOn())
        end,
    })

    table.insert(menu_items.character_tracker.sub_item_table, {
        text = _("Hide combined families in family tree"),
        checked_func = function()
            return self:isTreeCombinedHidden()
        end,
        callback = function()
            if not G_reader_settings then return end
            G_reader_settings:saveSetting("character_tracker_tree_hide_combined",
                not self:isTreeCombinedHidden())
        end,
    })

    local selection_toggles = {
        { kind = "character",  label = _("Hide new character (when selecting text)") },
        { kind = "highlight",  label = _("Hide add highlight to character (when selecting text)") },
        { kind = "topic",      label = _("Hide add topic highlight (when selecting text)") },
        { kind = "place",      label = _("Hide new place (when selecting text)") },
        { kind = "compendium", label = _("Hide new compendium entry (when selecting text)") },
        { kind = "family",     label = _("Hide new family (when selecting text)") },
        { kind = "appearance", label = _("Hide add to appearance (when selecting text)") },
        { kind = "timeline", label = _("Hide add to timeline (when selecting text)") },
        { kind = "family_excerpt", label = _("Hide add to family or relationship (when selecting text)") },
    }
    for _i, t in ipairs(selection_toggles) do
        table.insert(menu_items.character_tracker.sub_item_table, {
            text = t.label,
            checked_func = function()
                return self:isSelectionOptionHidden(t.kind)
            end,
            callback = function()
                if not G_reader_settings then return end
                LayoutSettings:saveSetting("character_tracker_hide_selection_" .. t.kind,
                    not self:isSelectionOptionHidden(t.kind))
            end,
        })
    end

    local selection_texts = {}
    for _i, t in ipairs(selection_toggles) do table.insert(selection_texts, t.label) end
    local sections = {
        {
            title = _("Character list & pages"),
            texts = {
                _("Hide character type"), _("Hide age"), _("Hide character belongings"),
                _("Hide last seen"), _("Hide family roles"), _("Hide counts in page headings"),
                _("Character list details (order & hide)"),
                _("Hide family tree button (read-only character page)"),
                _("Hide edit button (read-only character page)"),
                _("Call the family tree button \"Tree\" (read-only character page)"),
            },
        },
        {
            title = _("Underlining"),
            texts = {
                _("Underline names in text"), _("Underline places in text"), _("Underline objects in text"),
                _("Invisible underline"), _("Tapping a name opens the edit view"),
                _("Hide index limit warning"),
            },
        },
        { title = _("Selecting text"), texts = selection_texts },
        {
            title = _("Family tree"),
            texts = {
                _("Hide underline in family tree"), _("Hide shot button in family tree"),
                _("Hide generation labels in family tree"), _("Hide combined families in family tree"),
                _("Show line legend in family tree"),
                _("Sync family tree relationships with character list"),
            },
        },
        {
            title = _("Relationship tree"),
            texts = {
                _("Sync relationship tree ties with character list"),
                _("Show family ties in relationship trees"), _("Label ties in relationship trees"),
            },
        },
        { title = _("Timeline"), texts = { _("Hide shot button in timeline") } },
        { title = _("Button layouts (rows and columns)"), texts = button_layout_texts },
    }
    local section_of = {}
    local buckets = {}
    for i, section in ipairs(sections) do
        buckets[i] = {}
        for _j, text in ipairs(section.texts) do section_of[text] = i end
    end
    local remaining = {}
    for _i, item in ipairs(menu_items.character_tracker.sub_item_table) do
        local index = section_of[item.text]
        if index then
            item.keep_menu_open = true
            table.insert(buckets[index], item)
        else
            table.insert(remaining, item)
        end
    end
    local grouped = {}
    for i, section in ipairs(sections) do
        if #buckets[i] > 0 then
            table.insert(grouped, { text = section.title, sub_item_table = buckets[i] })
        end
    end
    table.insert(remaining, { text = _("Hide & display settings"), sub_item_table = grouped })
    menu_items.character_tracker.sub_item_table = remaining
end

function CharacterTracker:confirmDeleteSeries(s)
    UIManager:show(ConfirmBox:new{
        text = T(_("Delete series '%1'?\n\nThis will permanently remove the shared character file (%2 characters). Books currently linked to this series will lose access to its characters."), s.name, s.count),
        ok_text = _("Delete"),
        ok_callback = function()
            os.remove(s.path)
            os.remove((s.path:gsub("%.json$", ".places.json")))
            os.remove((s.path:gsub("%.json$", ".compendium.json")))
            os.remove((s.path:gsub("%.json$", ".families.json")))
            os.remove((s.path:gsub("%.json$", ".timeline.json")))
            local current = self:getSeriesName()
            if current == s.name then
                self:setSeriesName(nil)
                self:loadData()
                self:loadPlaces()
                self:loadCompendium()
                self:loadFamilies()
                self:loadTimelines()
            end
            UIManager:show(InfoMessage:new{
                text = T(_("Deleted series '%1'."), s.name),
                timeout = 2,
            })
        end,
    })
end

function CharacterTracker:showSeriesOptions()
    local series = self:getSeriesName()
    local buttons = {
        {
            {
                text = _("Change series name"),
                callback = function()
                    UIManager:close(self._series_dialog)
                    self._series_dialog = nil
                    self:showLinkSeriesDialog()
                end,
            },
        },
        {
            {
                text = _("Unlink from series"),
                callback = function()
                    UIManager:close(self._series_dialog)
                    self._series_dialog = nil
                    self:unlinkFromSeries()
                end,
            },
        },
        {
            {
                text = _("Close"),
                id = "close",
                callback = function()
                    UIManager:close(self._series_dialog)
                    self._series_dialog = nil
                end,
            },
        },
    }
    self._series_dialog = ButtonDialog:new{
        title = T(_("Series: %1\n%2 shared characters"), series, #self.characters),
        buttons = buttons,
    }
    UIManager:show(self._series_dialog)
end

return CharacterTracker