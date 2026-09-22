-- ============================================================
-- FS25_UniqueLicensePlates.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

UniqueLicensePlates = {}
local M = UniqueLicensePlates
M.shopPreviewVehicles = setmetatable({}, {__mode = "k"})
local unpackArgs = unpack or table.unpack

local function pack(...)
    return {n = select("#", ...), ...}
end

function M.copy(data)
    if data == nil then return nil end
    local result = {}
    for key, value in pairs(data) do result[key] = value end
    result.characters = {}
    for i, char in ipairs(data.characters or {}) do result.characters[i] = char end
    return result
end

function M.isValidData(data)
    return data ~= nil
        and data.variation ~= nil
        and type(data.characters) == "table"
        and data.colorIndex ~= nil
        and data.placementIndex ~= nil
end

function M.key(data)
    if data == nil or type(data.characters) ~= "table"
        or data.placementIndex == LicensePlateManager.PLACEMENT_OPTION.NONE then
        return nil
    end
    local value = table.concat(data.characters):upper():gsub("[%s_%-]", "")
    return value ~= "" and value or nil
end

function M.isRealVehicle(vehicle)
    return vehicle ~= nil and not vehicle.isDeleted
        and vehicle.propertyState ~= VehiclePropertyState.SHOP_CONFIG
        and vehicle.spec_licensePlates ~= nil
end

function M.vehicles()
    local mission = g_currentMission
    return mission and mission.vehicleSystem and mission.vehicleSystem.vehicles or {}
end

function M.used(except)
    local used = {}
    for _, vehicle in pairs(M.vehicles()) do
        if vehicle ~= except and M.isRealVehicle(vehicle) then
            local spec = vehicle.spec_licensePlates
            local key = M.key(spec and spec.licensePlateData)
            if key ~= nil then used[key] = true end
        end
    end
    for vehicle, _ in pairs(M.assigned or {}) do
        if vehicle ~= except and M.isRealVehicle(vehicle) then
            local spec = vehicle.spec_licensePlates
            local key = M.key(spec and spec.licensePlateData)
            if key ~= nil then used[key] = true end
        end
    end
    return used
end

function M.conflicts(data, except)
    local key = M.key(data)
    return key ~= nil and M.used(except)[key] == true
end

function M.getPlateDefinition(data, vehicle)
    local spec = vehicle and vehicle.spec_licensePlates
    local plates = spec and spec.licensePlates or nil
    if plates ~= nil then
        for _, entry in ipairs(plates) do
            local plate = entry and entry.data
            if plate ~= nil and plate.variations ~= nil and plate.variations[data.variation] ~= nil then
                return plate
            end
        end
    end

    local managerPlates = g_licensePlateManager and g_licensePlateManager.licensePlates
    if managerPlates ~= nil then
        for _, plate in ipairs(managerPlates) do
            if plate ~= nil and plate.variations ~= nil and plate.variations[data.variation] ~= nil then
                return plate
            end
        end
    end
    return nil
end

function M.template(data, vehicle)
    local plate = M.getPlateDefinition(data, vehicle)
    return plate and plate.variations and plate.variations[data.variation]
end

function M.isGermanPlate(data, vehicle)
    local markers = {}
    if data and data.xmlFilename then markers[#markers + 1] = tostring(data.xmlFilename) end

    local plate = M.getPlateDefinition(data, vehicle)
    if plate and plate.filename then markers[#markers + 1] = tostring(plate.filename) end

    for _, marker in ipairs(markers) do
        local name = marker:lower():gsub("\\", "/")
        if name:find("licenseplatesde", 1, true)
            or name:find("licenseplate_de", 1, true)
            or name:find("licenseplate-de", 1, true)
            or name:find("germany", 1, true)
            or name:find("deutsch", 1, true) then
            return true
        end
    end
    return false
end

function M.label(data, vehicle)
    local variation = M.template(data, vehicle)
    if variation == nil then return table.concat(data.characters or {}) end
    local result = ""
    local position = 1
    for _, value in ipairs(variation.values) do
        local char = data.characters[position] or ""
        if not value.isStatic and char ~= "_" then
            result = result .. (value.nextSection and " " or "") .. char
        end
        if not value.isStatic then position = position + 1 end
    end
    return result:match("^%s*(.-)%s*$")
end

local function appendPool(target, seen, source)
    if source == nil then return end
    for _, item in ipairs(source) do
        local value = item and item.value
        if value ~= nil and value ~= "" and not seen[value] then
            seen[value] = true
            target[#target + 1] = value
        end
    end
end

function M.getCharacterPool(value, plate)
    local font = plate and plate.font or (g_licensePlateManager and g_licensePlateManager:getFont())
    if font == nil then return {} end

    local pool, seen = {}, {}
    local types = MaterialManager and MaterialManager.FONT_CHARACTER_TYPE
    if value.alphabetical and types then
        appendPool(pool, seen, font.charactersByType and font.charactersByType[types.ALPHABETICAL])
    end
    if value.numerical and types then
        appendPool(pool, seen, font.charactersByType and font.charactersByType[types.NUMERICAL])
    end
    if value.special and types then
        appendPool(pool, seen, font.charactersByType and font.charactersByType[types.SPECIAL])
    end
    if #pool == 0 then appendPool(pool, seen, font.characters) end
    return pool
end

function M.getEditableSlots(data, vehicle)
    local variation = M.template(data, vehicle)
    local plate = M.getPlateDefinition(data, vehicle)
    if variation == nil then return {}, plate end

    local german = M.isGermanPlate(data, vehicle)
    local slots = {}
    local position = 1
    for _, value in ipairs(variation.values) do
        if not value.isStatic then
            local editable = not value.locked and data.characters[position] ~= nil
            if editable then
                if german then
                    editable = value.numerical and not value.alphabetical and not value.special
                else
                    editable = value.alphabetical or value.numerical or value.special
                end
            end
            if editable then
                slots[#slots + 1] = {position = position, value = value}
            end
            position = position + 1
        end
    end
    return slots, plate
end

local function randomFromPool(pool, oldChar, forceDifferent, avoidZero)
    local choices = {}
    for _, char in ipairs(pool) do
        if (not forceDifferent or char ~= oldChar) and (not avoidZero or char ~= "0") then
            choices[#choices + 1] = char
        end
    end
    if #choices == 0 then
        for _, char in ipairs(pool) do
            if not avoidZero or char ~= "0" then choices[#choices + 1] = char end
        end
    end
    if #choices == 0 then return oldChar end
    return choices[math.random(1, #choices)]
end

function M.generateInternationalCandidate(data, vehicle)
    local slots, plate = M.getEditableSlots(data, vehicle)
    if #slots == 0 then return nil end

    local candidate = M.copy(data)
    local firstPureNumeric = true
    for _, slot in ipairs(slots) do
        local value = slot.value
        local oldChar = candidate.characters[slot.position]
        local pool = M.getCharacterPool(value, plate)
        if #pool == 0 then return nil end

        local pureNumeric = value.numerical and not value.alphabetical and not value.special
        local avoidZero = pureNumeric and firstPureNumeric
        candidate.characters[slot.position] = randomFromPool(pool, oldChar, true, avoidZero)
        if pureNumeric then firstPureNumeric = false end
    end
    return candidate
end

function M.generateGermanCandidate(data, vehicle)
    local slots = M.getEditableSlots(data, vehicle)
    if #slots == 0 or #slots > 4 then return nil end

    local minimum = 10 ^ (#slots - 1)
    local maximum = 10 ^ #slots - 1
    local number = math.random(minimum, maximum)
    local digits = tostring(number)
    digits = string.rep("0", #slots - #digits) .. digits

    local candidate = M.copy(data)
    for i, slot in ipairs(slots) do
        candidate.characters[slot.position] = digits:sub(i, i)
    end
    return candidate
end

function M.generateCandidate(data, vehicle)
    if M.isGermanPlate(data, vehicle) then
        return M.generateGermanCandidate(data, vehicle)
    end
    return M.generateInternationalCandidate(data, vehicle)
end

function M.suggestions(data, vehicle, count)
    if M.key(data) == nil or M.template(data, vehicle) == nil then return {} end

    local wanted = count or 10
    local occupied = M.used(vehicle)
    local originalKey = M.key(data)
    if originalKey ~= nil then occupied[originalKey] = true end

    local result = {}
    local attempts = 0
    local maxAttempts = M.isGermanPlate(data, vehicle) and 2500 or 1500

    while #result < wanted and attempts < maxAttempts do
        attempts = attempts + 1
        local candidate = M.generateCandidate(data, vehicle)
        if candidate == nil then break end
        local key = M.key(candidate)
        if key ~= nil and not occupied[key] then
            occupied[key] = true
            result[#result + 1] = candidate
        end
    end
    return result
end

function M.findFreeCandidate(data, vehicle)
    local occupied = M.used(vehicle)
    if M.isGermanPlate(data, vehicle) then
        local slots = M.getEditableSlots(data, vehicle)
        if #slots == 0 or #slots > 4 then return nil end
        local minimum = 10 ^ (#slots - 1)
        local maximum = 10 ^ #slots - 1
        local start = math.random(minimum, maximum)
        local capacity = maximum - minimum + 1
        for offset = 0, capacity - 1 do
            local number = minimum + ((start - minimum + offset) % capacity)
            local digits = tostring(number)
            digits = string.rep("0", #slots - #digits) .. digits
            local candidate = M.copy(data)
            for i, slot in ipairs(slots) do candidate.characters[slot.position] = digits:sub(i, i) end
            local key = M.key(candidate)
            if key ~= nil and not occupied[key] then return candidate end
        end
        return nil
    end

    for _ = 1, 5000 do
        local candidate = M.generateInternationalCandidate(data, vehicle)
        if candidate == nil then return nil end
        local key = M.key(candidate)
        if key ~= nil and not occupied[key] then return candidate end
    end
    return nil
end

function M.choose(data, vehicle, accept, cancel, screen)
    local suggestions = M.suggestions(data, vehicle, 10)
    if #suggestions == 0 then
        InfoDialog.show("Kennzeichen schon vergeben\nKeine freie automatische Kombination gefunden.", cancel)
        return
    end

    local labels = {}
    for i, candidate in ipairs(suggestions) do labels[i] = M.label(candidate, vehicle) end

    local description
    if M.isGermanPlate(data, vehicle) then
        description = "Freies Kennzeichen auswählen – die Buchstaben bleiben erhalten:"
    else
        description = "Freies Kennzeichen auswählen – das komplette Kennzeichen wird neu erzeugt:"
    end

    OptionDialog.show(function(index)
        M.stopChoicePreview(true)
        local candidate = suggestions[tonumber(index)]
        if candidate == nil then
            if cancel then cancel() end
        elseif M.conflicts(candidate, vehicle) then
            M.choose(candidate, vehicle, accept, cancel, screen)
        else
            accept(M.copy(candidate))
        end
    end, "Kennzeichen schon vergeben", description, labels)
    M.startChoicePreview(screen, suggestions, labels)
end

function M.stopChoicePreview(restore)
    local choice = M.choicePreview
    M.choicePreview = nil
    if choice ~= nil and restore then
        M.applyShopPreviewPlate(choice.screen, choice.original, true)
    end
end

function M.startChoicePreview(screen, suggestions, labels)
    if screen == nil or not M.isValidData(screen.licensePlateData) then return end
    local gui = g_gui and g_gui.guis and g_gui.guis.OptionDialog
    local dialog = gui and gui.target
    if dialog == nil then return end

    local seen = {}
    local function findSelector(element)
        if type(element) ~= "table" or seen[element] then return nil end
        seen[element] = true
        if type(element.getState) == "function" and type(element.texts) == "table"
            and #element.texts == #labels then
            local matches = true
            for i, label in ipairs(labels) do
                if element.texts[i] ~= label then matches = false; break end
            end
            if matches then return element end
        end
        for _, child in pairs(element.elements or {}) do
            local selector = findSelector(child)
            if selector ~= nil then return selector end
        end
        return nil
    end
    local selector = findSelector(dialog)
    if selector == nil then
        for _, value in pairs(dialog) do
            selector = findSelector(value)
            if selector ~= nil then break end
        end
    end
    if selector == nil then
        Logging.warning("[UniqueLicensePlates] Auswahlfeld fuer Live-Vorschau nicht gefunden")
        return
    end
    M.pendingShopPreview = nil
    M.choicePreview = {screen=screen, dialog=dialog, selector=selector,
        suggestions=suggestions, original=M.copy(screen.licensePlateData)}
    M.updateChoicePreview()
end

function M.updateChoicePreview()
    local choice = M.choicePreview
    if choice == nil then return end
    if choice.dialog.isOpen == false then
        M.stopChoicePreview(true)
        return
    end
    local index = choice.selector:getState()
    local candidate = choice.suggestions[index]
    if candidate ~= nil then
        M.applyShopPreviewPlate(choice.screen, candidate, true)
    end
end

function M.notify(text)
    if g_currentMission and g_currentMission.addIngameNotification then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO, text)
    end
end

ULPRequestLicensePlateEvent = {}
local ULPRequestLicensePlateEvent_mt = Class(ULPRequestLicensePlateEvent, Event)
InitEventClass(ULPRequestLicensePlateEvent, "ULPRequestLicensePlateEvent")

function ULPRequestLicensePlateEvent.emptyNew()
    return Event.new(ULPRequestLicensePlateEvent_mt)
end

function ULPRequestLicensePlateEvent.new(vehicle, data)
    local self = ULPRequestLicensePlateEvent.emptyNew()
    self.vehicle = vehicle
    self.data = M.copy(data)
    return self
end

function ULPRequestLicensePlateEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.data = LicensePlateManager.readLicensePlateData(streamId, connection)
    self:run(connection)
end

function ULPRequestLicensePlateEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    LicensePlateManager.writeLicensePlateData(streamId, connection, self.data)
end

function ULPRequestLicensePlateEvent:run(connection)
    if connection:getIsServer() or g_server == nil then return end
    if self.vehicle == nil or not M.isRealVehicle(self.vehicle) or not M.isValidData(self.data) then return end
    local current = self.vehicle.spec_licensePlates and self.vehicle.spec_licensePlates.licensePlateData
    if current and current.xmlFilename then self.data.xmlFilename = current.xmlFilename end
    self.vehicle:setLicensePlatesData(M.copy(self.data))
end

function ULPRequestLicensePlateEvent.sendEvent(vehicle, data)
    if g_client == nil then return end
    local connection = g_client:getServerConnection()
    if connection ~= nil then
        connection:sendEvent(ULPRequestLicensePlateEvent.new(vehicle, data))
    end
end

ULPApplyLicensePlateEvent = {}
local ULPApplyLicensePlateEvent_mt = Class(ULPApplyLicensePlateEvent, Event)
InitEventClass(ULPApplyLicensePlateEvent, "ULPApplyLicensePlateEvent")

function ULPApplyLicensePlateEvent.emptyNew()
    return Event.new(ULPApplyLicensePlateEvent_mt)
end

function ULPApplyLicensePlateEvent.new(vehicle, data)
    local self = ULPApplyLicensePlateEvent.emptyNew()
    self.vehicle = vehicle
    self.data = M.copy(data)
    return self
end

function ULPApplyLicensePlateEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.data = LicensePlateManager.readLicensePlateData(streamId, connection)
    self:run(connection)
end

function ULPApplyLicensePlateEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    LicensePlateManager.writeLicensePlateData(streamId, connection, self.data)
end

function ULPApplyLicensePlateEvent:run(connection)
    if not connection:getIsServer() or self.vehicle == nil or not M.isValidData(self.data) then return end
    local current = self.vehicle.spec_licensePlates and self.vehicle.spec_licensePlates.licensePlateData
    if current and current.xmlFilename then self.data.xmlFilename = current.xmlFilename end

    M.networkApply = true
    self.vehicle:setLicensePlatesData(M.copy(self.data))
    M.networkApply = false

    if M.assigned and M.isRealVehicle(self.vehicle) then M.assigned[self.vehicle] = true end
end

function M.shopVehicle(screen)
    local vehicle = screen and screen.vehicle
    return M.isRealVehicle(vehicle) and vehicle or nil
end

function M.installDialog()
    local gui = g_gui and g_gui.guis and g_gui.guis.LicensePlateDialog
    local dialog = gui and gui.target
    if dialog == nil or dialog.ulpInstalled or type(dialog.setCallback) ~= "function" then return end

    dialog.ulpInstalled = true
    local original = dialog.setCallback

    dialog.setCallback = function(self, callback, target, ...)
        local extra = pack(...)
        if callback == nil then return original(self, callback, target, unpackArgs(extra, 1, extra.n)) end

        local vehicle = M.shopVehicle(target)
        if M.isRealVehicle(target) then vehicle = target end

        local function checked(...)
            local args = pack(...)
            local dataIndex
            for i = 1, args.n do
                if type(args[i]) == "table" and type(args[i].characters) == "table" and args[i].variation ~= nil then
                    dataIndex = i
                    break
                end
            end

            local data = dataIndex and args[dataIndex]
            if data == nil or not M.conflicts(data, vehicle) then
                return callback(unpackArgs(args, 1, args.n))
            end

            M.pending = function()
                M.choose(data, vehicle, function(candidate)
                    args[dataIndex] = candidate
                    local result = pack(callback(unpackArgs(args, 1, args.n)))

                    if target ~= nil and target.licensePlateData ~= nil then
                        M.queueShopPreviewPlate(target, candidate)
                    end

                    return unpackArgs(result, 1, result.n)
                end, function()
                    self:setLicensePlateData(M.copy(data))
                    g_gui:showDialog("LicensePlateDialog")
                    self:updateLicensePlateGraphics()
                end, target ~= nil and target.licensePlateData ~= nil and target or nil)
            end
        end

        return original(self, checked, target, unpackArgs(extra, 1, extra.n))
    end
end

function M.updateShopPlateThumbnail(screen, data)
    local changed = false
    local found = false
    local seen = {}
    local characters = table.concat(data.characters)
    local function updatePlate(plate)
        if type(plate) ~= "table" or seen[plate] then return end
        seen[plate] = true
        if type(plate.updateData) ~= "function"
            or type(plate.setColorIndex) ~= "function"
            or type(plate.variations) ~= "table" then return end
        found = true
        if plate.characters ~= characters or plate.variationIndex ~= data.variation
            or plate.ulpPreviewColor ~= data.colorIndex then
            plate:updateData(data.variation, plate.position, characters, true)
            plate:setColorIndex(data.colorIndex)
            plate.ulpPreviewColor = data.colorIndex
            changed = true
        end
    end
    for name, value in pairs(screen) do
        updatePlate(value)
        if type(name) == "string" and name:lower():find("licenseplate", 1, true)
            and type(value) == "table" then
            for _, child in pairs(value) do updatePlate(child) end
        end
    end
    if changed then
        local visited = {}
        local function invalidate(element)
            if type(element) ~= "table" or visited[element] then return end
            visited[element] = true
            if type(element.setRenderDirty) == "function" then
                element:setRenderDirty()
            end
            for _, child in pairs(element.elements or {}) do invalidate(child) end
        end
        invalidate(screen)
        for _, value in pairs(screen) do invalidate(value) end
    end
    return found
end

function M.applyShopPreviewPlate(screen, data, previewOnly)
    if screen == nil or not M.isValidData(data) then
        return 0
    end

    if not previewOnly then screen.licensePlateData = M.copy(data) end
    local thumbnailFound = M.updateShopPlateThumbnail(screen, data)
    if not thumbnailFound and not previewOnly then
        Logging.warning("[UniqueLicensePlates] Kennzeichenobjekt der kleinen Shop-Vorschau nicht gefunden")
    end

    local applied = 0
    local seen = {}

    local function applyToVehicle(vehicle)
        if vehicle == nil
            or seen[vehicle]
            or type(vehicle) ~= "table"
            or vehicle.isDeleted
            or vehicle.propertyState ~= VehiclePropertyState.SHOP_CONFIG
            or vehicle.spec_licensePlates == nil
            or type(vehicle.setLicensePlatesData) ~= "function" then
            return
        end

        seen[vehicle] = true

        if type(vehicle.getLicensePlatesDataIsEqual) == "function"
            and vehicle:getLicensePlatesDataIsEqual(data) then
            applied = applied + 1
            return
        end

        local plateData = M.copy(data)
        local current = vehicle.spec_licensePlates.licensePlateData
        if current ~= nil and current.xmlFilename ~= nil then
            plateData.xmlFilename = current.xmlFilename
        end

        vehicle:setLicensePlatesData(plateData)
        applied = applied + 1
    end

    applyToVehicle(screen.vehicle)

    for _, value in pairs(screen) do
        applyToVehicle(value)
    end

    for vehicle in pairs(M.shopPreviewVehicles) do
        local filename = screen.storeItem and screen.storeItem.xmlFilename
        if filename == nil or vehicle.configFileName == filename then
            applyToVehicle(vehicle)
        end
    end

    if previewOnly then return applied end
    if applied == 0 then
        Logging.warning(
            "[UniqueLicensePlates] Shop-Preview konnte nicht aktualisiert werden: kein Vorschaumodell gefunden"
        )
    end

    return applied
end


function M.queueShopPreviewPlate(screen, data)
    if screen == nil or not M.isValidData(data) then
        return
    end

    M.applyShopPreviewPlate(screen, data)

    M.pendingShopPreview = {
        screen = screen,
        data = M.copy(data),
        frames = 2
    }
end

function M.installShop(screen)
    if screen == nil then return end
    for _, name in ipairs({"buyButton", "leaseButton"}) do
        local button = screen[name]
        if button and not button.ulpInstalled and type(button.onClickCallback) == "function" then
            button.ulpInstalled = true
            local original = button.onClickCallback
            button.onClickCallback = function(target, ...)
                local data = screen.licensePlateData
                local vehicle = M.shopVehicle(screen)
                local hasPlates = screen.storeItem and screen.storeItem.hasLicensePlates
                if hasPlates and M.conflicts(data, vehicle) then
                    M.choose(data, vehicle, function(candidate)
                        M.queueShopPreviewPlate(screen, candidate)
                    end, nil, screen)
                    return
                end
                return original(target, ...)
            end
        end
    end
end

function M:loadMap()
    self.assigned = setmetatable({}, {__mode = "k"})
    self.networkApply = false
    self.active = true
    self:installDialog()
    M.installShop(g_gui and g_gui.screenControllers and g_gui.screenControllers[ShopConfigScreen])
end

function M:update(dt)
    if not self.active then return end
    M.installDialog()
    M.installShop(g_gui and g_gui.screenControllers and g_gui.screenControllers[ShopConfigScreen])
    local pending = self.pending
    self.pending = nil
    if pending then pending() end
    M.updateChoicePreview()

    local preview = self.pendingShopPreview
    if preview ~= nil then
        preview.frames = (preview.frames or 1) - 1

        if preview.frames <= 0 then
            self.pendingShopPreview = nil
            M.applyShopPreviewPlate(preview.screen, preview.data)
        end
    end
end

function M:deleteMap()
    self.active = false
    self.pending = nil
    self.pendingShopPreview = nil
    self.choicePreview = nil
    self.shopPreviewVehicles = setmetatable({}, {__mode = "k"})
    self.assigned = nil
    self.networkApply = false
end

LicensePlates.setLicensePlatesData = Utils.overwrittenFunction(
    LicensePlates.setLicensePlatesData,
    function(vehicle, superFunc, data, ...)
        if vehicle.propertyState == VehiclePropertyState.SHOP_CONFIG then
            M.shopPreviewVehicles[vehicle] = true
        end
        if not M.active or M.networkApply or not M.isRealVehicle(vehicle) or not M.isValidData(data) then
            return superFunc(vehicle, data, ...)
        end

        if g_server ~= nil then
            local finalData = M.copy(data)
            local adjusted = false

            if M.conflicts(finalData, vehicle) then
                local freeData = M.findFreeCandidate(finalData, vehicle)
                if freeData == nil then
                    M.notify("Kennzeichen schon vergeben – keine freie Kombination gefunden")
                    return
                end
                finalData = freeData
                adjusted = true
            end

            local result = superFunc(vehicle, finalData, ...)
            if M.assigned then M.assigned[vehicle] = true end

            local synchronized = true
            if vehicle.getIsSynchronized ~= nil then synchronized = vehicle:getIsSynchronized() end
            if synchronized then
                g_server:broadcastEvent(ULPApplyLicensePlateEvent.new(vehicle, finalData), nil, nil, vehicle)
            end

            if adjusted then
                local mode = M.isGermanPlate(finalData, vehicle) and "Zahlenblock" or "komplettes Kennzeichen"
                M.notify("Kennzeichen schon vergeben – " .. mode .. " automatisch geändert: " .. M.label(finalData, vehicle))
            end
            return result
        end

        local synchronized = true
        if vehicle.getIsSynchronized ~= nil then synchronized = vehicle:getIsSynchronized() end
        if not synchronized then return superFunc(vehicle, data, ...) end

        ULPRequestLicensePlateEvent.sendEvent(vehicle, data)
        return
    end
)

addModEventListener(M)
