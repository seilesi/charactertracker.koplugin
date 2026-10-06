-- Character Tracker for KOReader, tracks and adds notes for KOReader

local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Screen = require("device").screen
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local G_reader_settings = G_reader_settings or require("luasettings").reader
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local json = require("json")
local _ = require("gettext")
local T = require("ffi/util").template

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
    { key = "spouse",   label = _("Spouse"),   category = "family" },
    { key = "ally",     label = _("Ally"),     category = "social" },
    { key = "enemy",    label = _("Enemy"),    category = "social" },
    { key = "friend",   label = _("Friend"),   category = "social" },
    { key = "mentor",   label = _("Mentor"),   category = "social" },
    { key = "servant",  label = _("Servant"),  category = "social" },
    { key = "master",   label = _("Master"),   category = "social" },
    { key = "lover",    label = _("Lover"),    category = "social" },
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

function CharacterTracker:onReaderReady()
    if self._reader_ready_done then
        return
    end
    self._reader_ready_done = true

    self:_registerDictButton()

    self:loadData()
    self:loadPlaces()
    self:loadCompendium()
    self:loadFamilies()
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
    local marks = scanRuns(self.ui.document, { place.name }, self:getMatchCap())
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
    local marks = scanRuns(self.ui.document, { entry.name }, self:getMatchCap())
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
    if not force then
        local cache = self:_loadMarksCache()
        local cached_fp, cached_cap
        if cache then
            cached_fp, cached_cap = cache.fingerprint, tonumber(cache.cap)
            local legacy_cap, rest = (cached_fp or ""):match("^fmt=2|cap=(%d+)(.*)$")
            if legacy_cap then
                cached_fp = "fmt=2" .. rest
                cached_cap = cached_cap or tonumber(legacy_cap)
            end
        end
        local cap_now = self:getMatchCap()
        if cache and cached_fp == fingerprint and cached_cap and cached_cap >= cap_now then
            self.marks_by_charname = cache.characters or {}
            self.marks_by_placename = cache.places or {}
            self.marks_by_objname = cache.objects or {}
            if cached_cap > cap_now then
                trimBucketsToCap(self.marks_by_charname, cap_now)
                trimBucketsToCap(self.marks_by_placename, cap_now)
                trimBucketsToCap(self.marks_by_objname, cap_now)
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
        logger.info("CharacterTracker: mark cache miss - scanning the book")
    end

    local Trapper = require("ui/trapper")
    local info = InfoMessage:new{ text = _("Indexing names…") }
    UIManager:show(info)
    UIManager:forceRePaint()
    local cap = self:getMatchCap()
    local completed, results = Trapper:dismissableRunInSubprocess(function()
        local doc = self.ui.document
        local per_char, per_place, per_object = {}, {}, {}
        if self.mark_enabled then
            for _i, char in ipairs(self.characters) do
                local strings = { char.name }
                for _j, alias in ipairs(char.aliases or {}) do
                    table.insert(strings, alias)
                end
                per_char[char.name] = scanRuns(doc, strings, cap)
            end
        end
        if self.place_mark_enabled then
            for _i, place in ipairs(self.places) do
                if place.name and place.name ~= "" then
                    per_place[place.name] = scanRuns(doc, { place.name }, cap)
                end
            end
        end
        if self.object_mark_enabled then
            for _i, entry in ipairs(self.compendium) do
                if entry.name and entry.name ~= "" then
                    per_object[entry.name] = scanRuns(doc, { entry.name }, cap)
                end
            end
        end
        return { characters = per_char, places = per_place, objects = per_object }
    end, info)
    UIManager:close(info)
    if completed and results then
        self.marks_by_charname = results.characters or {}
        self.marks_by_placename = results.places or {}
        self.marks_by_objname = results.objects or {}
        hydrateMarks(self.marks_by_charname, "character")
        hydrateMarks(self.marks_by_placename, "place")
        hydrateMarks(self.marks_by_objname, "object")
        self._marks_complete = true
        self:_saveMarksCache(fingerprint)
        logger.info(string.format("CharacterTracker: scanned the book in %.2fs (wall clock may differ - the scan runs in a subprocess)", os.clock() - t0))
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
        for _j, member in ipairs(family.members) do
            if member.role == nil then member.role = "" end
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
    local plugin = self
    local FileChooser = require("ui/widget/filechooser")
    local chooser
    chooser = FileChooser:new{
        name = "charactertracker_import",
        path = self:getExportsDir(),
        show_parent = self.dialog,
        close_callback = function()
            UIManager:close(chooser)
        end,
        file_filter = function(filename)
            return filename:match("%.json$") ~= nil
        end,
    }
    function chooser:onFileSelect(item)
        UIManager:close(chooser)
        plugin:confirmImport(item.path)
    end
    UIManager:show(chooser)
end

function CharacterTracker:confirmImport(path)
    local name = path:match("([^/]+)%.json$") or path
    UIManager:show(ConfirmBox:new{
        text = T(_("Import characters from '%1'?\nCharacters with the same name will be merged."), name),
        ok_text = _("Import"),
        ok_callback = function()
            local src = self:loadCharactersFromFile(path)
            if #src == 0 then
                UIManager:show(InfoMessage:new{
                    text = _("No characters found in that file."),
                })
                return
            end
            local merged = self:mergeCharacters(src)
            self:saveData()
            self:rebuildAllMarks()
            UIManager:show(InfoMessage:new{
                text = T(_("Imported %1 characters (%2 new)."), #src, merged),
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
            table.insert(names, place.name or "")
        end
        table.sort(names)
        table.insert(parts, "P[" .. table.concat(names, "\3") .. "]")
    end
    if self.object_mark_enabled then
        local names = {}
        for _i, entry in ipairs(self.compendium) do
            table.insert(names, entry.name or "")
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

    local lines = {}
    for _i, k in ipairs(order) do
        local b = by_target[k]
        local type_parts = merge_tokens(b.out_types, b.in_types, getRelationshipLabel)
        local sent_parts = merge_tokens(b.out_sent, b.in_sent, getSentimentLabel)
        local line = b.name .. ": "
        if #type_parts > 0 then
            line = line .. table.concat(type_parts, ", ")
        else
            line = line .. _("(linked)")
        end
        if #sent_parts > 0 then
            line = line .. "  —  " .. table.concat(sent_parts, ", ")
        end
        table.insert(lines, line)
    end
    return lines
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

                        local families_touched = false
                        for _i, family in ipairs(self.families or {}) do
                            for _j, member in ipairs(family.members or {}) do
                                if member.name and member.name:lower() == old_name_lower then
                                    member.name = new_name
                                    families_touched = true
                                end
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
        and G_reader_settings:isTrue("character_tracker_hide_type")
end

function CharacterTracker:isAgeHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_hide_age")
end

function CharacterTracker:isAbilityHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_hide_ability")
end

function CharacterTracker:isBelongingsHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_hide_belongings")
end

function CharacterTracker:isLastSeenHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_hide_last_seen")
end

function CharacterTracker:isSelectionOptionHidden(kind)
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_hide_selection_" .. kind)
end

function CharacterTracker:isIndexLimitWarningHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_hide_index_limit_warning")
end

function CharacterTracker:isFamilyHidden()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_hide_family")
end

function CharacterTracker:isTapOpensReadOnly()
    return G_reader_settings ~= nil
        and G_reader_settings:isTrue("character_tracker_tap_opens_readonly")
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
                    self:saveData()
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
                            self:saveData()
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
        short = shorten(short, 44)
        table.insert(buttons, {
            {
                text = "“" .. short .. "”",
                callback = function()
                    UIManager:close(self._highlights_dialog)
                    self._highlights_dialog = nil
                    self:showHighlightDialog(character, i)
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
                                character.highlights[index] = text
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

function CharacterTracker:getCharacterFamilyLines(character)
    local lines = {}
    local cname = character.name:lower()
    for _i, family in ipairs(self.families or {}) do
        for _j, member in ipairs(family.members or {}) do
            if member.name and member.name:lower() == cname then
                local line = family.name or _("(unnamed)")
                if member.role and member.role ~= "" then
                    line = line .. "  —  " .. member.role
                end
                table.insert(lines, line)
            end
        end
    end
    return lines
end

function CharacterTracker:buildCharacterDetailText(character)
    local text_parts = {}
    local sep = "────────────────"
    local function section(title)
        table.insert(text_parts, "\n" .. sep .. "\n  " .. title .. "\n" .. sep .. "\n")
    end

    table.insert(text_parts, "━━━ " .. character.name .. " ━━━\n\n")

    if character.aliases and #character.aliases > 0 then
        table.insert(text_parts, "  " .. _("Aliases") .. ": " ..
            table.concat(character.aliases, ", ") .. "\n")
    end

    if character.occupation and character.occupation ~= "" then
        table.insert(text_parts, "  " .. _("Occupation") .. ": " .. character.occupation .. "\n")
    else
        table.insert(text_parts, "  " .. _("Occupation") .. ": " .. _("(not set)") .. "\n")
    end

    local status_line = "  " .. _("Status") .. ": " ..
        (character.status and character.status ~= "" and getStatusLabel(character.status) or _("(not set)"))
    if character.status == "dead" and character.cause_of_death and character.cause_of_death ~= "" then
        status_line = status_line .. " — " .. _("cause") .. ": " .. character.cause_of_death
    end
    table.insert(text_parts, status_line .. "\n")

    if not self:isTypeHidden() then
        local ct = character.char_type or ""
        table.insert(text_parts, "  " .. _("Character type") .. ": " ..
            (ct ~= "" and getCharacterTypeLabel(ct) or _("(not set)")) .. "\n")
    end

    if character.appearance and character.appearance ~= "" then
        table.insert(text_parts, "  " .. _("Appearance") .. ": " .. character.appearance .. "\n")
    end

    local res_lines = self:getCharacterResidenceLines(character)
    if #res_lines > 0 then
        table.insert(text_parts, "  " .. _("Residence") .. ":\n")
        for _i, line in ipairs(res_lines) do
            table.insert(text_parts, "      • " .. line .. "\n")
        end
    end

    if not self:isAgeHidden() and character.age and character.age ~= "" then
        table.insert(text_parts, "  " .. _("Age") .. ": " .. character.age .. "\n")
    end

    if not self:isAbilityHidden() and character.ability and character.ability ~= "" then
        table.insert(text_parts, "  " .. _("Ability") .. ": " .. character.ability .. "\n")
    end

    if not self:isBelongingsHidden() then
        local belonging_names = self:getCharacterBelongingNames(character)
        if #belonging_names > 0 then
            table.insert(text_parts, "  " .. _("Belongings") .. ": " ..
                table.concat(belonging_names, ", ") .. "\n")
        end
    end

    if not self:isFamilyHidden() then
        local family_lines = self:getCharacterFamilyLines(character)
        if #family_lines > 0 then
            table.insert(text_parts, "  " .. _("Family") .. ":\n")
            for _i, line in ipairs(family_lines) do
                table.insert(text_parts, "      • " .. line .. "\n")
            end
        end
    end

    local rel_lines = self:buildRelationshipSummary(character)
    if #rel_lines > 0 then
        section(_("Relationships"))
        for _i, line in ipairs(rel_lines) do
            table.insert(text_parts, "  " .. line .. "\n")
        end
    end

    if character.factions and #character.factions > 0 then
        table.insert(text_parts, "\n  " .. _("Factions") .. ": " ..
            table.concat(character.factions, ", ") .. "\n")
    end

    if character.tags and #character.tags > 0 then
        table.insert(text_parts, "  " .. _("Tags") .. ": " ..
            table.concat(character.tags, ", ") .. "\n")
    end

    if character.traits and #character.traits > 0 then
        section(T(_("Personality traits (%1)"), #character.traits))
        for _i, entry in ipairs(character.traits) do
            local line = "  ◇ " .. (entry.trait or "")
            if entry.reason and entry.reason ~= "" then
                line = line .. " — " .. entry.reason
            end
            table.insert(text_parts, line .. "\n")
        end
    end

    local has_manual_last = not self:isLastSeenHidden()
        and character.last_occurrence and character.last_occurrence ~= ""
    if self.mark_enabled or has_manual_last then
        section(_("Occurrences"))
        if self.mark_enabled then
            local app = self:getCharacterAppearance(character)
            table.insert(text_parts, "  " .. _("Occurrences") .. ": " .. app.count .. "\n")
            if not self:isIndexLimitWarningHidden() and self:_indexLimitReached(character) then
                table.insert(text_parts, "  " .. T(_("(index limit of %1 reached - later mentions aren't underlined; raise it under \"Max matches per name\")"),
                    self:getMatchCap()) .. "\n")
            end
            if app.first_page then
                if app.first_chapter and app.first_chapter ~= _("Unknown chapter") then
                    table.insert(text_parts, "  " .. T(_("First seen: %1 (p. %2)"), app.first_chapter, app.first_page) .. "\n")
                else
                    table.insert(text_parts, "  " .. T(_("First seen: p. %1"), app.first_page) .. "\n")
                end
            end
        end
        if has_manual_last then
            table.insert(text_parts, "  " .. _("Last seen (manual)") .. ": " .. character.last_occurrence .. "\n")
        end
    end

    if character.highlights and #character.highlights > 0 then
        section(T(_("Highlights (%1)"), #character.highlights))
        for _i, quote in ipairs(character.highlights) do
            table.insert(text_parts, "  “" .. getNoteText(quote) .. "”\n\n")
        end
    end

    if character.secrets and #character.secrets > 0 then
        section(T(_("Secrets (%1)"), #character.secrets))
        for _i, secret in ipairs(character.secrets) do
            table.insert(text_parts, "  ▲ " .. secret .. "\n")
        end
    end

    if (character.skills and #character.skills > 0)
       or (character.weaknesses and #character.weaknesses > 0) then
        section(_("Skills & weaknesses"))
        if character.skills and #character.skills > 0 then
            table.insert(text_parts, "  " .. _("Skills / abilities") .. ":\n")
            for _i, skill in ipairs(character.skills) do
                table.insert(text_parts, "      + " .. skill .. "\n")
            end
        end
        if character.weaknesses and #character.weaknesses > 0 then
            if character.skills and #character.skills > 0 then
                table.insert(text_parts, "\n")
            end
            table.insert(text_parts, "  " .. _("Weaknesses") .. ":\n")
            for _i, weak in ipairs(character.weaknesses) do
                table.insert(text_parts, "      − " .. weak .. "\n")
            end
        end
    end

    if character.notes and #character.notes > 0 then
        section(T(_("Notes (%1)"), #character.notes))
        for _i, note in ipairs(character.notes) do
            table.insert(text_parts, "  ◆ " .. getNoteText(note) .. "\n\n")
        end
    else
        section(_("Notes"))
        table.insert(text_parts, "  " .. _("No notes yet.") .. "\n")
    end

    if character.quote and character.quote ~= "" then
        section(_("Quote"))
        table.insert(text_parts, "  “" .. character.quote .. "”\n")
    end

    return table.concat(text_parts)
end

function CharacterTracker:showCharacterDetail(character)
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
                self:showAliasManager(character)
            end,
        },
        {
            text = _("Occupation"),
            callback = function()
                UIManager:close(viewer)
                self:showOccupationDialog(character, reopen)
            end,
        },
        {
            text = _("Status"),
            callback = function()
                UIManager:close(viewer)
                self:showStatusDialog(character, reopen)
            end,
        },
        {
            text = _("Type"),
            callback = function()
                UIManager:close(viewer)
                self:showCharacterTypeDialog(character, reopen)
            end,
        },
    })
    do
        local row2 = {
            {
                text = _("Appearance"),
                callback = function()
                    UIManager:close(viewer)
                    self:showAppearanceDialog(character, reopen)
                end,
            },
            {
                text = _("Residence"),
                callback = function()
                    UIManager:close(viewer)
                    self:showResidenceManager(character)
                end,
            },
        }
        if not self:isLastSeenHidden() then
            table.insert(row2, {
                text = _("Last seen"),
                callback = function()
                    UIManager:close(viewer)
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
                    self:showAgeDialog(character, reopen)
                end,
            })
        end
        if not self:isAbilityHidden() then
            table.insert(row3, {
                text = _("Ability"),
                callback = function()
                    UIManager:close(viewer)
                    self:showAbilityDialog(character, reopen)
                end,
            })
        end
        if not self:isBelongingsHidden() then
            table.insert(row3, {
                text = _("Belongings"),
                callback = function()
                    UIManager:close(viewer)
                    self:showBelongingsManager(character)
                end,
            })
        end
        if #row3 > 0 then table.insert(rows, row3) end
    end
    table.insert(rows, {
        {
            text = _("Relations"),
            callback = function()
                UIManager:close(viewer)
                self:showRelationshipManager(character)
            end,
        },
        {
            text = _("Factions"),
            callback = function()
                UIManager:close(viewer)
                self:showFactionsManager(character)
            end,
        },
        {
            text = _("Tags"),
            callback = function()
                UIManager:close(viewer)
                self:showTagsManager(character)
            end,
        },
    })
    table.insert(rows, {
        {
            text = _("Traits"),
            callback = function()
                UIManager:close(viewer)
                self:showTraitsManager(character)
            end,
        },
        {
            text = _("Highlights"),
            callback = function()
                UIManager:close(viewer)
                self:showHighlightsManager(character)
            end,
        },
        {
            text = _("Secrets"),
            callback = function()
                UIManager:close(viewer)
                self:showSecretsManager(character)
            end,
        },
    })
    table.insert(rows, {
        {
            text = _("Skills/Weak."),
            callback = function()
                UIManager:close(viewer)
                self:showSkillsWeaknessesMenu(character)
            end,
        },
        {
            text = _("Notes"),
            callback = function()
                UIManager:close(viewer)
                self:showNotesManager(character)
            end,
        },
        {
            text = _("Quote"),
            callback = function()
                UIManager:close(viewer)
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
                self:showAddNoteDialog(character)
            end,
        },
        {
            text = _("Rename"),
            callback = function()
                UIManager:close(viewer)
                self:showRenameDialog(character, reopen)
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

    viewer = TextViewer:new{
        title = character.name,
        text = full_text,
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = rows,
    }
    UIManager:show(viewer)
end

function CharacterTracker:showCharacterDetailReadOnly(character)
    local full_text = self:buildCharacterDetailText(character)
    local viewer
    viewer = TextViewer:new{
        title = character.name,
        text = full_text,
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = {
            {
                {
                    text = _("Edit"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showCharacterDetail(character)
                    end,
                },
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

    local item_table = {}
    for _i, char in ipairs(chars) do
        local badges = {}
        if char.occupation and char.occupation ~= "" then
            table.insert(badges, char.occupation)
        end
        local ct = char.char_type or ""
        if ct ~= "" and not self:isTypeHidden() then
            table.insert(badges, getCharacterTypeLabel(ct))
        end
        if char.factions and #char.factions > 0 then
            table.insert(badges, table.concat(char.factions, "/"))
        end
        if char.aliases and #char.aliases > 0 then
            table.insert(badges, T(_("%1 aliases"), #char.aliases))
        end
        local incoming = incoming_map[char.name:lower()] or {}
        local rel_count = (char.relationships and #char.relationships or 0) + #incoming
        if rel_count > 0 then
            table.insert(badges, T(_("%1 relations"), rel_count))
        end
        if char.notes and #char.notes > 0 then
            table.insert(badges, T(_("%1 notes"), #char.notes))
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

    if not self:isSelectionOptionHidden("character") then
        table.insert(buttons, {
            { text = _("New character from selection"), callback = choose(function()
                local first_word = trimmed:match("^(%S+)") or ""
                self:showAddCharacterDialog(first_word)
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

function CharacterTracker:showPlaceList()
    local item_table = {}
    table.insert(item_table, {
        text = _("+ Add place"),
        callback = function()
            self:showAddPlaceDialog(nil)
        end,
    })
    local function walk(parent_id, depth)
        for _i, place in ipairs(self:getChildPlaces(parent_id)) do
            local indent = ("    "):rep(depth)
            local type_label = getPlaceTypeLabel(place.type)
            local kids = self:getChildPlaces(place.id)
            local suffix = "  ·  " .. type_label
            if #kids > 0 then
                suffix = suffix .. T(_("  ·  %1 sub-places"), #kids)
            end
            if place.residents and #place.residents > 0 then
                suffix = suffix .. T(_("  ·  %1 residents"), #place.residents)
            end
            table.insert(item_table, {
                text = indent .. (place.name or _("(unnamed)")) .. suffix,
                callback = function()
                    self:showPlaceDetail(place)
                end,
            })
            walk(place.id, depth + 1)
        end
    end
    walk(nil, 0)

    local menu_container
    local menu
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

function CharacterTracker:showPlaceDetail(place)
    local parts = {}
    table.insert(parts, "━━━ " .. (place.name or _("(unnamed)")) .. " ━━━\n\n")
    table.insert(parts, "  " .. _("Type") .. ": " .. getPlaceTypeLabel(place.type) .. "\n")

    local path = self:getPlacePath(place)
    if path and path ~= (place.name or "") then
        table.insert(parts, "  " .. _("Location") .. ": " .. path .. "\n")
    end

    if place.description and place.description ~= "" then
        table.insert(parts, "\n" .. place.description .. "\n")
    end

    local kids = self:getChildPlaces(place.id)
    if #kids > 0 then
        table.insert(parts, "\n────────────────\n  " .. _("Sub-places") .. "\n────────────────\n")
        for _i, kid in ipairs(kids) do
            table.insert(parts, "  • " .. (kid.name or _("(unnamed)"))
                .. "  (" .. getPlaceTypeLabel(kid.type) .. ")\n")
        end
    end

    if place.residents and #place.residents > 0 then
        table.insert(parts, "\n────────────────\n  " .. _("Residents") .. "\n────────────────\n")
        for _i, r in ipairs(place.residents) do
            local kind
            if r.kind == "works" then
                kind = r.past and _("worked here") or _("works here")
            else
                kind = r.past and _("lived here") or _("lives here")
            end
            table.insert(parts, "  • " .. (r.name or "?") .. "  (" .. kind .. ")\n")
        end
    end

    local viewer
    local function reopen() self:showPlaceDetail(place) end
    viewer = TextViewer:new{
        title = place.name or _("Place"),
        text = table.concat(parts),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = {
            {
                {
                    text = _("Rename"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showRenamePlaceDialog(place, reopen)
                    end,
                },
                {
                    text = _("Type"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showPlaceTypePicker(place, reopen)
                    end,
                },
                {
                    text = _("Description"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showPlaceDescriptionDialog(place, reopen)
                    end,
                },
            },
            {
                {
                    text = _("＋ Sub-place"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showAddPlaceDialog(place.id, reopen)
                    end,
                },
                {
                    text = _("Residents"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showPlaceResidentsManager(place)
                    end,
                },
                {
                    text = _("Move"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showPlaceParentPicker(place, reopen)
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(viewer)
                        self:deletePlace(place)
                    end,
                },
                {
                    text = _("Open list"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showPlaceList()
                    end,
                },
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

function CharacterTracker:showCompendiumList()
    local item_table = {}
    table.insert(item_table, {
        text = _("+ Add compendium entry"),
        callback = function()
            self:showAddCompendiumDialog()
        end,
    })
    for _i, entry in ipairs(self.compendium) do
        local owners = self:getCompendiumCurrentOwners(entry)
        local suffix = "  ·  " .. getCompendiumTypeLabel(entry.type)
        if #owners > 0 then
            local names = {}
            for _j, rec in ipairs(owners) do table.insert(names, rec.owner) end
            suffix = suffix .. T(_("  ·  owned by %1"), table.concat(names, " & "))
        end
        table.insert(item_table, {
            text = (entry.name or _("(unnamed)")) .. suffix,
            callback = function()
                self:showCompendiumDetail(entry)
            end,
        })
    end

    local menu_container
    local menu
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

function CharacterTracker:showCompendiumDetail(entry)
    local parts = {}
    table.insert(parts, "━━━ " .. (entry.name or _("(unnamed)")) .. " ━━━\n\n")
    table.insert(parts, "  " .. _("Type") .. ": " .. getCompendiumTypeLabel(entry.type) .. "\n")

    if entry.age and entry.age ~= "" then
        table.insert(parts, "  " .. _("Age") .. ": " .. entry.age .. "\n")
    end
    if entry.ability and entry.ability ~= "" then
        table.insert(parts, "  " .. _("Ability") .. ": " .. entry.ability .. "\n")
    end

    if entry.hide_from_belongings then
        table.insert(parts, "  " .. _("(hidden from character belongings)") .. "\n")
    end

    if entry.description and entry.description ~= "" then
        table.insert(parts, "\n" .. entry.description .. "\n")
    end

    if entry.ownership and #entry.ownership > 0 then
        table.insert(parts, "\n────────────────\n  " .. _("Ownership") .. "\n────────────────\n")
        for _i, rec in ipairs(entry.ownership) do
            local line = "  • " .. (rec.owner or "?")
            if rec.current then
                line = line .. "  (" .. _("current") .. ")"
            end
            table.insert(parts, line .. "\n")
            if rec.acquired and rec.acquired ~= "" then
                table.insert(parts, "      " .. _("acquired") .. ": " .. rec.acquired .. "\n")
            end
            if not rec.current and rec.lost and rec.lost ~= "" then
                table.insert(parts, "      " .. _("lost") .. ": " .. rec.lost .. "\n")
            end
        end
    end

    local viewer
    local function reopen() self:showCompendiumDetail(entry) end
    viewer = TextViewer:new{
        title = entry.name or _("Compendium entry"),
        text = table.concat(parts),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = {
            {
                {
                    text = _("Rename"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showRenameCompendiumDialog(entry, reopen)
                    end,
                },
                {
                    text = _("Type"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showCompendiumTypePicker(entry, reopen)
                    end,
                },
                {
                    text = _("Description"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showCompendiumDescriptionDialog(entry, reopen)
                    end,
                },
            },
            {
                {
                    text = _("Age"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showCompendiumAgeDialog(entry, reopen)
                    end,
                },
                {
                    text = _("Ability"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showCompendiumAbilityDialog(entry, reopen)
                    end,
                },
                {
                    text = _("Ownership"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showCompendiumOwnershipManager(entry)
                    end,
                },
            },
            {
                {
                    text = entry.hide_from_belongings and _("Show in belongings") or _("Hide from belongings"),
                    callback = function()
                        UIManager:close(viewer)
                        entry.hide_from_belongings = not entry.hide_from_belongings
                        self:saveCompendium()
                        reopen()
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(viewer)
                        self:deleteCompendiumEntry(entry)
                    end,
                },
                {
                    text = _("Open list"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showCompendiumList()
                    end,
                },
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
                            hide_from_belongings = false,
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
            self:saveCompendium()
            self:removeMarksForObjectName(entry.name)
            UIManager:show(InfoMessage:new{
                text = T(_("Deleted '%1'."), entry.name),
                timeout = 2,
            })
        end,
    })
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
    local item_table = {}
    table.insert(item_table, {
        text = _("+ Add family"),
        callback = function()
            self:showAddFamilyDialog()
        end,
    })
    for _i, family in ipairs(self.families) do
        local suffix = ""
        if family.members and #family.members > 0 then
            suffix = T(_("  ·  %1 member(s)"), #family.members)
        end
        table.insert(item_table, {
            text = (family.name or _("(unnamed)")) .. suffix,
            callback = function()
                self:showFamilyDetail(family)
            end,
        })
    end

    local menu_container
    local menu
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

function CharacterTracker:showFamilyDetail(family)
    local parts = {}
    table.insert(parts, "━━━ " .. (family.name or _("(unnamed)")) .. " ━━━\n\n")

    if family.description and family.description ~= "" then
        table.insert(parts, family.description .. "\n\n")
    end

    if family.members and #family.members > 0 then
        table.insert(parts, "────────────────\n  " .. _("Members") .. "\n────────────────\n")
        for _i, member in ipairs(family.members) do
            local line = "  • " .. (member.name or "?")
            if member.role and member.role ~= "" then
                line = line .. "  —  " .. member.role
            end
            table.insert(parts, line .. "\n")
        end
    else
        table.insert(parts, "\n  " .. _("No members added yet.") .. "\n")
    end

    local viewer
    local function reopen() self:showFamilyDetail(family) end
    viewer = TextViewer:new{
        title = family.name or _("Family"),
        text = table.concat(parts),
        width = math.floor(Device.screen:getWidth() * 0.9),
        height = math.floor(Device.screen:getHeight() * 0.85),
        buttons_table = {
            {
                {
                    text = _("Rename"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showRenameFamilyDialog(family, reopen)
                    end,
                },
                {
                    text = _("Description"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showFamilyDescriptionDialog(family, reopen)
                    end,
                },
                {
                    text = _("Members"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showFamilyMembersManager(family)
                    end,
                },
            },
            {
                {
                    text = _("Delete"),
                    callback = function()
                        UIManager:close(viewer)
                        self:deleteFamily(family)
                    end,
                },
                {
                    text = _("Open list"),
                    callback = function()
                        UIManager:close(viewer)
                        self:showFamilyList()
                    end,
                },
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
                        local family = {
                            id = genId(),
                            name = name,
                            description = "",
                            members = {},
                            created = os.date("%Y-%m-%d %H:%M"),
                        }
                        table.insert(self.families, family)
                        self:saveFamilies()
                        self:showFamilyDetail(family)
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
                            family.name = name
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
                    table.remove(family.members, i)
                    self:saveFamilies()
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
    self._family_member_act_dialog = ButtonDialog:new{
        title = T(_("%1 — %2"), family.name, member.name or "?"),
        buttons = {
            {
                { text = _("Edit role"), callback = function()
                    UIManager:close(self._family_member_act_dialog); self._family_member_act_dialog = nil
                    self:showFamilyMemberRoleDialog(family, index)
                end },
            },
            {
                { text = _("Open character"), callback = function()
                    UIManager:close(self._family_member_act_dialog); self._family_member_act_dialog = nil
                    local char = self:getCharacterByName(member.name)
                    if char then
                        self:showCharacterDetail(char)
                    else
                        UIManager:show(InfoMessage:new{
                            text = T(_("'%1' isn't a tracked character."), member.name or "?"),
                        })
                        self:showFamilyMembersManager(family)
                    end
                end },
            },
            {
                { text = _("Remove from family"), callback = function()
                    UIManager:close(self._family_member_act_dialog); self._family_member_act_dialog = nil
                    table.remove(family.members, index)
                    self:saveFamilies()
                    self:showFamilyMembersManager(family)
                end },
            },
            {
                { text = _("Cancel"), id = "close", callback = function()
                    UIManager:close(self._family_member_act_dialog); self._family_member_act_dialog = nil
                    self:showFamilyMembersManager(family)
                end },
            },
        },
    }
    UIManager:show(self._family_member_act_dialog)
end

function CharacterTracker:showFamilyMemberRoleDialog(family, index)
    local member = family.members[index]
    if not member then return end
    local dialog
    dialog = InputDialog:new{
        title = T(_("Role in '%1' for '%2'"), family.name, member.name or "?"),
        input = member.role or "",
        input_hint = _("e.g. head of house, heir, matriarch, disowned"),
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
    local dialog
    dialog = InputDialog:new{
        title = T(_("Role of '%1' in '%2'? (optional)"), member_name, family.name),
        input_hint = _("e.g. head of house, heir, matriarch, disowned"),
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

    self:_flushSaveData()

    self:setSeriesName(series_name)
    self:loadData()
    self:loadPlaces()
    self:loadCompendium()
    self:loadFamilies()

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
           and not entry:match("%.families%.json$") then
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
                viewer = TextViewer:new{
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
                text = _("Tapping a name opens the read-only view"),
                checked_func = function()
                    return self:isTapOpensReadOnly()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    G_reader_settings:saveSetting("character_tracker_tap_opens_readonly",
                        not self:isTapOpensReadOnly())
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
                    G_reader_settings:saveSetting("character_tracker_hide_type",
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
                    G_reader_settings:saveSetting("character_tracker_hide_age",
                        not self:isAgeHidden())
                end,
            },
            {
                text = _("Hide ability"),
                checked_func = function()
                    return self:isAbilityHidden()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    G_reader_settings:saveSetting("character_tracker_hide_ability",
                        not self:isAbilityHidden())
                end,
            },
            {
                text = _("Hide character belongings"),
                checked_func = function()
                    return self:isBelongingsHidden()
                end,
                callback = function()
                    if not G_reader_settings then return end
                    G_reader_settings:saveSetting("character_tracker_hide_belongings",
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
                    G_reader_settings:saveSetting("character_tracker_hide_last_seen",
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
                    G_reader_settings:saveSetting("character_tracker_hide_family",
                        not self:isFamilyHidden())
                end,
            },
        },
    }

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

    local selection_toggles = {
        { kind = "character",  label = _("Hide new character (when selecting text)") },
        { kind = "highlight",  label = _("Hide add highlight to character (when selecting text)") },
        { kind = "place",      label = _("Hide new place (when selecting text)") },
        { kind = "compendium", label = _("Hide new compendium entry (when selecting text)") },
        { kind = "family",     label = _("Hide new family (when selecting text)") },
    }
    for _i, t in ipairs(selection_toggles) do
        table.insert(menu_items.character_tracker.sub_item_table, {
            text = t.label,
            checked_func = function()
                return self:isSelectionOptionHidden(t.kind)
            end,
            callback = function()
                if not G_reader_settings then return end
                G_reader_settings:saveSetting("character_tracker_hide_selection_" .. t.kind,
                    not self:isSelectionOptionHidden(t.kind))
            end,
        })
    end
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
            local current = self:getSeriesName()
            if current == s.name then
                self:setSeriesName(nil)
                self:loadData()
                self:loadPlaces()
                self:loadCompendium()
                self:loadFamilies()
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