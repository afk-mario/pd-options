import 'CoreLibs/ui'
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"

local pd <const> = playdate
local gfx <const> = pd.graphics

class('Options').extends(gfx.sprite)

local timer <const> = pd.timer
local itemHeight <const> = 24
local w <const> = 200	--198
local h <const> = 240
local dividerWidth <const> = 1

local KEY_REPEAT = 50
local KEY_REPEAT_INITIAL = 250
local TOGGLE, SLIDER, RESET = 1, 2, 'RESET'
local TOGGLE_VALS = {false, true}

local optionDefinitions = {
    -- name (required string): option's display name in menu
    -- key (optional string): identifier for the option in the userOptions table json output (NEEDS TO BE UNIQUE)
        -- if key is not provided, lowercase name is used as the key
        -- set the key to "RESET" to make a "reset to defaults" button
    -- values (optional table): table of possible values. Only required for normal "List" style options.
    -- style (optional enum: TOGGLE, SLIDER, or none): defines a special type of option. If omitted, this will be a normal "list" option.
        -- For any of these special option types, the "values" field is not required as it is calculated automatically.
        -- TOGGLE: boolean toggle switch. Values: {false, true}
        -- SLIDER: used to select an integer in a range from min to max (useful for volume controls). Values: {min, ... , max}
    -- default (optional number): index of the value that should be set as default. If omitted, the first item in the values list will be the default.
        -- For a standard list option, make sure to use the index of the item you want in the list, not the item itself.
        -- For a toggle switch, set default to 1 for false, 2 for true.
        -- For a slider, the default is not an index but rather an actual integer value. So if your volume slider goes from 0 to 5, and you want to
        -- start on max volume, set the default to 5 (as opposed to 6).
    -- preview (optional boolean): hide the options menu while the option is changing to more easily preview the changes. B or scrolling off the option will end the preview mode.
    -- dirtyRead (optional boolean): if true, reads on this option will return `nil` if the value hasn't changed from the last read. This is useful for expensive operations based on an option value. dirtyRead options can also be "force" read to ignore the dirty state (see main.lua example app).
    -- tooltip (optional string): Show a tooltip box when the user is selecting an option for additional help
    -- ignoreOnLoad (optional boolean): Ignore the stored value for this option when loading the game. useful for settings that you want to be temporary.
    -- locks (optional table): A table detailing which option under which condition should be "locked" when this option is a certain value. Format:
        -- lockedOption: key of the option to lock
        -- lockedValue: index of the value to lock the above option to
        -- lockedWhen: when the value of the locking option is equal to this, the lockedOption becomes locked. Use indexes for every option style except TOGGLE, in which case use booleans.
    -- canFavorite (optional boolean): Sets whether or not an option value can be "favorited" by pressing A on the value.
        -- If favorite-able, an option value can be toggled as favorite with the A button
        -- If any values favorited, only those are selected from for Opts:randomize()
        -- It's up to you what else to do with the favorite values. You can access them with Opts:getFavorites(key). The resulting list is is a list of indexes for the option.values array.
    {
        header = 'Options Demo',
        options = {
            {name='B button', key='bFunction', values={'add circle', 'add square', 'clear all'}, dirtyRead=false, tooltip='Change the function of the B button. Not a dirtyRead option as the value is checked on demand when b is pressed.'},
            {name='Background', key='bg', values={'no bg', 'bayer', 'vertical'}, default=1, preview=true, dirtyRead=true, tooltip='This option hides the rest of the list when changed for a better look at the scene behind it', canFavorite=true},
            {name='Outlined', style=TOGGLE, default=1, dirtyRead=true, tooltip='Example for a toggle switch. Controls whether the added shapes are outlined or not. Will lock the background setting to "bayer"', locks={lockedOption='bg', lockedValue=2, lockedWhen=true}},
            {name='X offset', key='xOffset', min=-2, max=2, default=0, style=SLIDER, dirtyRead=true},
            {name='Y offset', key='yOffset', min=0, max=10, default=0, style=SLIDER, dirtyRead=true},
            {name='Reset to defaults', key='RESET'}
        }
    }
}

local musicOpt = optionDefinitions[1].options[1]
local bgOpt =  optionDefinitions[1].options[1]
local tilesetOpt = optionDefinitions[1].options[1]

local lockRelations = {} -- store for options that lock other options
local lockedOptions = {} -- hash set of option keys that are currently locked from being altered
local optionDefsByKey = {} -- transformation of the optionDefinitions object to be indexed by key. values point back to the option definition

function Options:init()
    Options.super.init(self)

    self.frame = 1
    self.menu = pd.ui.gridview.new(0, itemHeight)

    -- list of available options based on option screen (indexed by section/row for easy selection)
    self.currentOptions = {}
    -- current values for each option. (indexed by key for easy reads)
    self.userOptions = {}
    self.dirty = false
    self.previewMode = false

    -- sprite init
    self:setZIndex(9999)
    self:setIgnoresDrawOffset(true)
    self:setCenter(0,0)
    self:moveTo(0,0)
    self:setVisible(false)
    local img = gfx.image.new(400,240)
    self:setImage(img)
    self.menuImg = gfx.image.new(w, h)

    self:add()

    self:menuInit()
    self:userOptionsInit()

    function self.menu.drawCell(menuSelf, section, row, column, selected, x, y, width, height)
        local textPadding = 5
        local val, isFavorited = self:getValue(section, row)
        local label, style, numValues, minVal = self:getOptionDefInfo(section, row)
        if self.previewMode and not selected then return end

        gfx.pushContext()
        if selected then
            gfx.setColor(gfx.kColorBlack)
            gfx.fillRoundRect(x, y, width, height+2, 4)
            gfx.setImageDrawMode(gfx.kDrawModeFillWhite)
        else
            gfx.setImageDrawMode(gfx.kDrawModeCopy)
        end
        -- draw option
        -- gfx.setFont(font)
        local labelWidth, _ = gfx.getTextSize(label)
        labelWidth = math.min(width, labelWidth)
        gfx.drawTextInRect(label, x+textPadding, y+textPadding, labelWidth, height, nil, '...', kTextAlignment.left)

        -- draw switch as glyph
        if val ~= 'n/a' and val ~= nil then
            if style == TOGGLE then
                Options.drawSwitch(y+textPadding-2, val, selected)
            elseif style == SLIDER then
                Options.drawSlider(y+textPadding-2, val, selected, numValues, minVal)
            elseif style ~= RESET then
                -- draw value as text
                local optionWidth = 192 - (labelWidth+textPadding)
                if isFavorited then val = '❤️*' .. val else val = '*' .. val end
                gfx.drawTextInRect(val, labelWidth+textPadding, y+textPadding, optionWidth, height, nil, '...', kTextAlignment.right)
            end
        end

        gfx.popContext()
    end

    function self.menu.drawSectionHeader(menuSelf, section, x, y, width, height)
        if self.previewMode then return end

        local textPadding = 4
        local text = '*'..self.currentOptions[section].header:upper()..'*'
        gfx.pushContext()
            -- gfx.setImageDrawMode(gfx.kDrawModeCopy)
            gfx.drawText(text, x+4, y+textPadding)
            gfx.setColor(gfx.kColorBlack)
            gfx.setLineWidth(2)
            gfx.drawLine(x, y+height, x+width, y+height)

        gfx.popContext()
    end

    self.keyTimer = {}
    self.controls = {
        -- move
        leftButtonDown = function() self:toggleCurrentOption(-1) end,
        rightButtonDown = function() self:toggleCurrentOption(1) end,
        upButtonDown = function()
            self.keyTimer['U'] = timer.keyRepeatTimerWithDelay(KEY_REPEAT_INITIAL, KEY_REPEAT, function() self:selectPreviousRow() end)
        end,
        upButtonUp = function() if self.keyTimer['U'] then self.keyTimer['U']:remove() end end,
        downButtonDown = function()
            self.keyTimer['D'] = timer.keyRepeatTimerWithDelay(KEY_REPEAT_INITIAL, KEY_REPEAT, function() self:selectNextRow() end)
        end,
        downButtonUp = function() if self.keyTimer['D'] then self.keyTimer['D']:remove() end end,

        -- action
        AButtonDown = function()
            self:handleAPress()
        end,
        BButtonDown = function()
            if self.previewMode then
                self.previewMode = false
                self:updateImage()
            elseif not self.slideAnim then
                self:hide()
            end
        end,
        BButtonUp = function () end,
        -- turn with crank
        cranked = function(change, acceleratedChange)
            if pd.getCrankTicks(8) ~= 0 then
                if change < 0 then
                    self:selectPreviousRow()
                else
                    self:selectNextRow()
                end
            end
        end,
    }
end

function Options:menuInit()
    self.currentOptions = optionDefinitions

    local sectionRows = {}
    local startRow = 0
    for i, section in ipairs(self.currentOptions) do
        if section.header then
            table.insert(sectionRows, #section.options)
        end
    end

    self.menu:setCellPadding(0,0,2,2)
    self.menu:setContentInset(4, 4, 0, 0)
    self.menu:setSectionHeaderHeight(itemHeight)
    self.menu:setSectionHeaderPadding(0, 0, 2, 0)

    self.menu:setNumberOfRows(table.unpack(sectionRows))
    self.menu:setSelectedRow(1)
end

function Options:userOptionsInit(ignoreUserOptions)
    local existingOptions = nil
    if not ignoreUserOptions then
        existingOptions = self:loadUserOptions()
    end
    self.userOptions = {}

    -- Go through each defined option and see if an existing value was loaded
    for j, section in ipairs(optionDefinitions) do
        for i, option in ipairs(section.options) do
            local key = option.key or option.name:lower()
            optionDefsByKey[key] = option
            if not option.style and not option.values then
                option.style = TOGGLE
            end
            if option.style == TOGGLE then
                option.values = TOGGLE_VALS
            end
            if option.key == RESET then
                option.values = {1}
                option.style = RESET
            end
            if option.style == SLIDER then
                option.values = {}
                for i=option.min, option.max, 1 do
                    table.insert(option.values, i)
                end

                if option.default == nil then option.default = 1 end
                -- when first loading this option, adjust the default to be an index rather than actual value
                if not option.defaultAdjusted then
                    option.default = table.indexOfElement(option.values, option.default)
                    option.defaultAdjusted = true
                end
            end
            if option.locks then
                lockRelations[key] = option.locks
            end
            local default = option.default or 1

            -- this option exists in the loaded json and needs to be imported
            if existingOptions and existingOptions[key] ~= nil and not option.ignoreOnLoad then
                local val = existingOptions[key]

                -- if the existing option is a dirtyRead option, mark it as dirty
                if #val == 2 then val[2] = true end

                -- if the value index exceeds the number of values available, reset to default
                if type(val[1]) == 'number' and val[1] > #option.values then
                    val[1] = default
                end

                -- set the loaded option
                self.userOptions[key] = val
                if val[1] == true then
                    option.current = 2
                elseif val[1] == false then
                    option.current = 1
                else
                    option.current = val[1]
                end

            -- this option does not exist and should be set to the default value
            else
                local val = {default}
                if option.style == TOGGLE then
                    val = {option.values[default]}
                end
                if option.dirtyRead then
                    val[2] = true
                end

                self.userOptions[key] = val
                option.current = default
            end

            -- if this option has favorites, load them
            local favKey = key .. 'Favorites'
            if option.canFavorite then
                option.favKey = favKey
                if existingOptions and existingOptions[favKey] then
                    local filteredFavs = {}
                    -- filter out favorites that are beyond the available number of assets
                    for i, idx in ipairs(existingOptions[favKey]) do
                        if idx <= #option.values then
                            table.insert(filteredFavs, idx)
                        end
                    end
                    self.userOptions[favKey] = filteredFavs
                else
                    self.userOptions[favKey] = {}
                end
            end

            option.key = key
        end
    end

    -- Iterate once more through all userOptions (now that they were imported or set to default)
    -- and set relevant options based on the 'locks' setting
    for key, val in pairs(self.userOptions) do
        self:handleOptionLocks(key, val[1])

    end
end

function Options:saveUserOptions()
    self.userOptions._build = pd.metadata.buildNumber
    pd.datastore.write(self.userOptions, 'settings', false)
end

function Options:loadUserOptions()
    return pd.datastore.read('settings')
end

function Options:resetKeyTimers()
    for k, v in pairs(self.keyTimer) do
        v:remove()
    end
end
function Options:show()
    self:playOpenSFX()
    self:setVisible(true)
    self.previewMode = false
    self:updateMenuImage()
    pd.inputHandlers.push(self.controls, true)

    self:updateImage()
end

function Options:hide()
    self:playCloseSFX()
    self:saveUserOptions()
    self:resetKeyTimers()
    pd.inputHandlers.pop()
    self:setVisible(false)
end

-- given an option key and a value, check if that setting should lock any other options from changing
function Options:handleOptionLocks(key, val)
    -- if this option locks something else
    if lockRelations[key] then
        -- get the other option
        local otherKey, otherVal = lockRelations[key].lockedOption, lockRelations[key].lockedValue

        -- value matches so lock this other option
        if lockRelations[key].lockedWhen == val then
            -- set the user option add to the locked options set to prevent it from being changed later
            self:setOptionIdx(otherKey, otherVal, optionDefsByKey[otherKey])
            lockedOptions[otherKey] = true
        -- unlock the option instead
        else
            lockedOptions[otherKey] = nil
        end

        -- mark other option as dirty if necessary
        if #self.userOptions[otherKey] == 2 then
            self.userOptions[otherKey][2] = true
        end
    end
end

-- Returns the option at the given section and row, or the currently selected option if no args
function Options:getSelectedOption(section, row)
    local selectedSection, selectedRow, selectedCol = self.menu:getSelection()
    section = section or selectedSection
    row = row or selectedRow
    return self.currentOptions[section].options[row]
end

function Options:getOptionDefInfo(section, row)
    local active <const> = self:getValue(section, row) == nil
    local bold <const> = active and '' or ''
    gfx.setFontTracking(0)
    local optDef = self:getSelectedOption(section, row)
    return bold..optDef.name, optDef.style, #optDef.values, optDef.min
end

function Options:getValue(section, row)
    local option = self:getSelectedOption(section, row)
    local isFavorited = false
    if option.favKey and table.indexOfElement(self.userOptions[option.favKey], option.current) ~= nil then
        isFavorited = true
    end
    return option.values[option.current], isFavorited
end

-- Returns the index of the option's value if it is marked as dirty, otherwise return nil
-- Pass ignoreDirty=true to always read the value of the option
-- Pass retrunValue=true to return the actual value instead of the index
function Options:read(key, ignoreDirty, returnValue)
    local opt = self.userOptions[key]
    if opt == nil then return opt end

    local values = nil
    if returnValue then
        values = optionDefsByKey[key].values
    end

    -- opt[1] is the value, opt[2] is a boolean indicating if the option is dirty.
    -- not all options are defined with dirty reads, and in that case they are only length 1
    if #opt == 2 and not ignoreDirty then
        if opt[2] then
            opt[2] = false
            return returnValue and values[opt[1]] or opt[1]
        end
    else
        if opt[2] then
            opt[2] = false
        end
        return returnValue and values[opt[1]] or opt[1]
    end
end

function Options:write(key, newIdx, keepClean)
    self:setOptionIdx(key, newIdx, optionDefsByKey[key], keepClean)
    self:updateImage()
end

-- Sets the given option to the new index, handling the boolean and dirty read case
function Options:setOptionIdx(key, newIdx, optionDef, keepClean)
    -- non-boolean options are stored as indices into values rather than values to make backwards-compatibility easier
    self.userOptions[key] = { newIdx }
    if optionDef.style == TOGGLE then
        self.userOptions[key] = { optionDef.values[newIdx] }
    end

    -- add dirty flag for this option
    if optionDef.dirtyRead then
        if not keepClean then
            self.userOptions[key][2] = newIdx ~= currentIdx
        else
            self.userOptions[key][2] = false
        end
    end

    -- keep track of the current index in the option definition as well
    optionDef.current = newIdx
end

function Options:isOptsDirty()
    return self.dirty
end

function Options:markOptsDirty()
    self.dirty = true
end

function Options:markClean()
    self.dirty = false
end

-- Given a table of option keys, randomize the value of those options and write the result.
-- If favorite values are set, randomizer only pulls from favorites.
function Options:randomize(keyList)
    local randomizableOpts = {}
    for i, key in ipairs(keyList) do
        if optionDefsByKey[key] ~= nil then
            table.insert(randomizableOpts, optionDefsByKey[key])
        end
    end
    if #randomizableOpts == 0 then return end

    for i, opt in ipairs(randomizableOpts) do
        local vals = opt.values
        local currentIdx = opt.current or opt.default
        local newIdx = 1

        if opt.favKey and #self.userOptions[opt.favKey] > 0 then
            local favList = self.userOptions[opt.favKey]
            newIdx = favList[math.random(1, #favList)]
        else
            newIdx = math.random(1, #vals)
        end

        self.userOptions[opt.key] = {newIdx}
        if opt.dirtyRead then
            self.userOptions[opt.key][2] = (newIdx ~= currentIdx)
        end

        opt.current = newIdx
    end
    self:markOptsDirty()
    self:updateImage()
end

function Options:getFavorites(key)
    local opt = optionDefsByKey[key]
    if opt.favKey then
        local favs = self.userOptions[opt.favKey]
        return favs
    end
    return {}
end

function Options:handleAPress()
    local option = self:getSelectedOption()
    -- toggle the option if can't be favorited
    if option.key == RESET then
        return self:resetToDefaults()
    end
    if not option.favKey then
        return self:toggleCurrentOption(1, true)
    end

    local favList = self.userOptions[option.favKey]
    local loc = table.indexOfElement(favList, option.current)
    if loc ~= nil then -- remove favorite by recreating the list without
        local newFavs = {}
        for i, fav in ipairs(favList) do
            if fav ~= option.current then table.insert(newFavs, fav) end
        end
        self.userOptions[option.favKey] = newFavs
    else -- add favorite
        table.insert(favList, option.current)
    end
    self:updateImage()
end

function Options:resetToDefaults()
    self:playResetSFX()
    self:userOptionsInit(true)
    self:updateImage()
end

function Options:toggleCurrentOption(incr, forceWrap)
    incr = incr or 1
    self:resetKeyTimers()
    self:playSelectionSFX(incr == 1)

    local option = self:getSelectedOption()
    local key =  option.key
    local values = option.values
    local currentIdx = option.current  or option.default

    if lockedOptions[key] then
        print('option is locked')
        return
    end

    local newIdx = currentIdx+incr
    if option.style == SLIDER then -- sliders dont wrap
        local minVal = 1
        local maxVal = #values
        newIdx = newIdx < minVal and minVal or newIdx > maxVal and maxVal or newIdx
    else -- pick new index by wrapping around all the values
        newIdx = 1 + (newIdx-1) % #values
    end
    -- boolean toggles should not wrap unless the A button is being used to toggle
    if option.style == TOGGLE and not forceWrap then
        newIdx = incr == -1 and 1 or 2
    end

    self:setOptionIdx(key, newIdx, option)

    -- mark entire object dirty
    if newIdx ~= currentIdx then
        self:markOptsDirty()
        if option.preview then
            self.previewMode = true
        end
    end

    self:handleOptionLocks(key, self.userOptions[key][1])
    self:updateImage()
end

function Options:onCurrentOption()
    local row <const> = self:getCurrentRow()

    if self:getValue(row) == false then
        self:toggleCurrentOption()
    end
end

function Options:offCurrentOption()
    local row <const> = self:getCurrentRow()

    if self:getValue(row) == true then
        self:toggleCurrentOption()
    end
end

function Options:update()
    if self.slideAnim then
        self:updateImage()
    end
end

function Options:updateImage()

    local img = self:getImage()
    img:clear(gfx.kColorClear)
    gfx.pushContext(img)
    -- gfx.setFont(ST_DIN, 'normal')
    -- gfx.setFont(ST_DIN_BOLD, 'bold')
    if self.slideAnim then
        local value = self.slideAnim.currentStage.value
        self:drawSideBar(value)
        self:drawMenu(value)
    elseif not self.previewMode then

        self:updateMenuImage()
        self:drawSideBar(w)
        self:drawMenu(w)

        local tooltip = self:getSelectedOption().tooltip
        if tooltip then
            self:drawTooltipBox(tooltip)
        end
    else
        self:updateMenuImage()
        self:drawMenu(w)
    end

    gfx.popContext()
    self:markDirty()
end

function Options:updateMenuImage()
    self.menuImg:clear(gfx.kColorClear)
    gfx.pushContext(self.menuImg)
        self.menu:drawInRect(0, 0, w, h)
    gfx.popContext()
end

function Options:drawSideBar(width)
    gfx.setColor(gfx.kColorWhite)
    gfx.fillRect(0, 0, width, 240)
    gfx.setColor(gfx.kColorBlack)
    gfx.setLineWidth(2)
    gfx.drawLine(width,0,width,240)
end

function Options:drawMenu(width)
    local menuXOffset = -w + width
    self.menuImg:draw(menuXOffset, 0)
end

function Options:drawTooltipBox(tooltip)
    local textPadding = 10
    local x, y = w + dividerWidth + 18, 30
    local maxWidth = 160
    local maxHeight = 180

    local tw, th = gfx.getTextSizeForMaxWidth(tooltip, maxWidth - 2*textPadding)
    local textRect = pd.geometry.rect.new(textPadding, textPadding, maxWidth - 2*textPadding, th)

    self.tooltipImg = gfx.image.new(200, th+40)
    gfx.pushContext(self.tooltipImg)

        Options.drawBox(1, 1, textRect.width + 2*textPadding, textRect.height + 2*textPadding, false)
        gfx.drawTextInRect(tooltip, textRect, nil, '...', kTextAlignment.left)

    gfx.popContext()

    self.tooltipImg:draw(x, y + (maxHeight-th)/2)
end

function Options:selectPreviousRow()
    self.previewMode = false
    self.menu:selectPreviousRow(true, false, false)
    local sect, row, col = self.menu:getSelection()
    self.menu:scrollCellToCenter(sect, row, col, false)
    self:playSelectionSFX(false)
    self:updateImage()
end

function Options:selectNextRow()
    self.previewMode = false
    self.menu:selectNextRow(true, false, false)
    local sect, row, col = self.menu:getSelection()
    self.menu:scrollCellToCenter(sect, row, col, false)
    self:playSelectionSFX(true)
    self:updateImage()
end

------------------------------------------
--------- STATIC DRAWING METHODS ---------
------------------------------------------

function Options.drawSwitch(y, val, selected)
    local x <const> = 158
    local y <const> = y+8

    local r <const> = 6
    local rx <const> = x+9
    local ry <const> = y-5
    local rw <const> = 24
    local rh <const> = r*2+2

    local cxoff <const> = x+16
    local cxon <const> = x+rw+2
    local cy <const> = y+2

    gfx.pushContext()
    gfx.setLineWidth(2)

    gfx.setColor(selected and gfx.kColorWhite or gfx.kColorBlack)

    if val then
        gfx.setDitherPattern(0.5)
        gfx.fillRoundRect(rx,ry,rw,rh, r)

        gfx.setColor(selected and gfx.kColorWhite or gfx.kColorBlack)
        gfx.drawRoundRect(rx,ry,rw,rh, r)
        gfx.fillCircleAtPoint(cxon,cy,r+2)
        -- gfx.drawRect(cxon,cy-3,1,6)
    else
        gfx.drawRoundRect(rx,ry,rw,rh, r)
        gfx.drawCircleAtPoint(cxoff,cy,r+1)
        gfx.setColor(selected and gfx.kColorBlack or gfx.kColorWhite)
        gfx.fillCircleAtPoint(cxoff,cy,r)
    end

    gfx.popContext()
end

function Options.drawSlider(y, rawVal, selected, numValues, minVal)
    -- rawVal: integer between min and max in the definition (inclusive)
    -- numValues: how many possible values (max - min + 1)
    -- minVal: minimum end of the range

    local rightEdge <const> = 190
    local y <const> = y+8

    local r <const> = 6
    local rw <const> = numValues * 5 + 12
    local rx <const> = rightEdge - rw
    local ry <const> = y-5
    local rh <const> = r*2+2

    -- adjust val to be between 1 and numValues
    val = rawVal + (1 - minVal)
    gfx.drawText(rawVal .. ','.. val, rx - 30, ry)
    local cx <const> = rx
    local cxv <const> = cx+(val*5)-1
    local cy <const> = y-6

    gfx.pushContext()
    gfx.setLineWidth(2)

    gfx.setColor(selected and gfx.kColorWhite or gfx.kColorBlack)

    if val then
        gfx.setColor(selected and gfx.kColorWhite or gfx.kColorBlack)

        -- body
        gfx.drawRoundRect(rx,ry,rw,rh, r)

        -- notches
        for dot=1,numValues do
            gfx.fillRect(cx+3+(dot*5),cy+7,2,2)
        end

        -- handle
        gfx.drawRoundRect(cxv+2,cy,6,rh+2,r)

        -- handle pattern
        gfx.setDitherPattern(0.5)
        gfx.fillRoundRect(cxv+2,cy,6,rh+2,r+2)
    end

    gfx.popContext()
end

function Options.drawBox(x, y, width, height, drawShadow)

    local rect = pd.geometry.rect.new(x, y, width, height)
    local shadow = pd.geometry.rect.new(rect.x, rect.y, rect.width+ 5, rect.height + 5)

    if drawShadow then
        -- shadow
        gfx.setColor(gfx.kColorBlack)
        gfx.setDitherPattern(0.5, gfx.image.kDitherTypeBayer2x2)
        gfx.fillRect(shadow)
    end

     -- background
     gfx.setColor(gfx.kColorWhite)
     gfx.fillRect(rect)

     -- border
     gfx.setColor(gfx.kColorBlack)
     gfx.setLineWidth(2)
     gfx.drawRect(rect)

    return drawShadow and shadow or rect
end

------------------------------------------
-------- SOUND EFFECT PLACEHOLDERS -------
------------------------------------------

-- open the menu
function Options:playOpenSFX() end

-- close the menu
function Options:playCloseSFX() end

-- reset to defaults
function Options:playResetSFX() end

-- select item
-- pass boolean true for forward selection, boolean false for reverse selection
function Options:playSelectionSFX(isForward) end