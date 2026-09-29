-- HPSystemServer.lua
-- Сервер: хранит HP, создаёт UI/события, управляет избранными объектами

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HPFolderName = "HPObjects"

local hpObjects = {} -- [Model/Part] = {maxHp, currentHp, name, color, highlight}
local selectedTargets = {} -- [Player] = {object, ...} or just one if needed

-- Создаём папку с данными, если нет
local rootFolder = ReplicatedStorage:FindFirstChild(HPFolderName)
if not rootFolder then
    rootFolder = Instance.new("Folder")
    rootFolder.Name = HPFolderName
    rootFolder.Parent = ReplicatedStorage
end

-- Базовый RemoteEvent
local updateHpEvent = ReplicatedStorage:FindFirstChild("UpdateHPData")
if not updateHpEvent then
    updateHpEvent = Instance.new("RemoteEvent")
    updateHpEvent.Name = "UpdateHPData"
    updateHpEvent.Parent = ReplicatedStorage
end

local requestMenuEvent = ReplicatedStorage:FindFirstChild("RequestHPMenu")
if not requestMenuEvent then
    requestMenuEvent = Instance.new("RemoteEvent")
    requestMenuEvent.Name = "RequestHPMenu"
    requestMenuEvent.Parent = ReplicatedStorage
end

local selectObjectEvent = ReplicatedStorage:FindFirstChild("SelectHPObject")
if not selectObjectEvent then
    selectObjectEvent = Instance.new("RemoteEvent")
    selectObjectEvent.Name = "SelectHPObject"
    selectObjectEvent.Parent = ReplicatedStorage
end

local clearSelectionEvent = ReplicatedStorage:FindFirstChild("ClearHPSelection")
if not clearSelectionEvent then
    clearSelectionEvent = Instance.new("RemoteEvent")
    clearSelectionEvent.Name = "ClearHPSelection"
    clearSelectionEvent.Parent = ReplicatedStorage
end

local function getTopModel(instance)
    local model = instance
    if instance:IsA("Model") then
        return instance
    end
    while model and not model:IsA("Model") do
        model = model.Parent
    end
    return model
end

local function ensureHumanoid(target)
    if target:IsA("Humanoid") then
        return target
    end
    local model = getTopModel(target)
    if model then
        return model:FindFirstChildOfClass("Humanoid")
    end
    return nil
end

local function createBillboard(object, hpInfo)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "HPBillboard"
    billboard.Size = UDim2.new(0, 80, 0, 35)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    billboard.Parent = object

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundTransparency = 1
    frame.Parent = billboard

    local text = Instance.new("TextLabel")
    text.Size = UDim2.new(1, 0, 1, 0)
    text.BackgroundTransparency = 1
    text.TextColor3 = Color3.fromRGB(255, 255, 255)
    text.TextStrokeTransparency = 0
    text.Font = Enum.Font.GothamBold
    text.TextSize = 18
    text.TextScaled = false
    text.Text = string.format("%d/%d", hpInfo.currentHp, hpInfo.maxHp)
    text.Parent = frame

    return billboard
end

local function refreshBillboard(object, hpInfo)
    local billboard = object:FindFirstChild("HPBillboard")
    if billboard and billboard:FindFirstChild("Frame") then
        local textLabel = billboard.Frame:FindFirstChildOfClass("TextLabel")
        if textLabel then
            textLabel.Text = string.format("%d/%d", hpInfo.currentHp, hpInfo.maxHp)
            if hpInfo.currentHp <= 0 then
                textLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
            elseif hpInfo.currentHp / hpInfo.maxHp < 0.35 then
                textLabel.TextColor3 = Color3.fromRGB(255, 180, 60)
            else
                textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end
    end
end

local function attachHighlight(object, color)
    if object:FindFirstChild("HPHighlight") then
        object.HPHighlight.Enabled = true
        object.HPHighlight.FillColor = color
        return
    end

    local highlight = Instance.new("Highlight")
    highlight.Name = "HPHighlight"
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0.2
    highlight.Enabled = true
    highlight.Parent = object
end

local function removeHighlight(object)
    local highlight = object:FindFirstChild("HPHighlight")
    if highlight then
        highlight.Enabled = false
    end
end

local function getAllTrackedObjects()
    local list = {}
    for obj, data in pairs(hpObjects) do
        if obj and obj.Parent then
            table.insert(list, {
                name = data.name,
                maxHp = data.maxHp,
                currentHp = data.currentHp,
                object = obj,
                id = tostring(obj),
            })
        end
    end
    return list
end

local function notifyClients()
    local list = getAllTrackedObjects()
    updateHpEvent:FireAllClients(list)
end

local function registerObject(object, maxHp, name)
    if hpObjects[object] then
        return
    end

    local hpInfo = {
        maxHp = maxHp,
        currentHp = maxHp,
        name = name or object.Name,
        color = Color3.fromRGB(255, 255, 255),
    }

    hpObjects[object] = hpInfo

    -- Если объект - Model, создаём BillboardGui на его PrimaryPart, иначе на сам объект
    local attachPart = object
    if object:IsA("Model") then
        attachPart = object.PrimaryPart or object:FindFirstChild("HumanoidRootPart") or object:FindFirstChildWhichIsA("BasePart")
    end

    if attachPart then
        createBillboard(attachPart, hpInfo)
    end

    notifyClients()
end

local function damageObject(object, amount)
    if not hpObjects[object] then
        return
    end

    local info = hpObjects[object]
    info.currentHp = math.max(0, info.currentHp - amount)

    local attachPart = object
    if object:IsA("Model") then
        attachPart = object.PrimaryPart or object:FindFirstChild("HumanoidRootPart") or object:FindFirstChildWhichIsA("BasePart")
    end

    if attachPart then
        refreshBillboard(attachPart, info)
    end

    if info.currentHp <= 0 then
        -- Можно убрать объект или просто пометить как мёртвый
        if object:IsA("Model") then
            if object:FindFirstChildOfClass("Humanoid") then
                object:FindFirstChildOfClass("Humanoid").Health = 0
            end
        end
    end

    notifyClients()
end

local function healObject(object, amount)
    if not hpObjects[object] then
        return
    end

    local info = hpObjects[object]
    info.currentHp = math.min(info.maxHp, info.currentHp + amount)

    local attachPart = object
    if object:IsA("Model") then
        attachPart = object.PrimaryPart or object:FindFirstChild("HumanoidRootPart") or object:FindFirstChildWhichIsA("BasePart")
    end

    if attachPart then
        refreshBillboard(attachPart, info)
    end

    notifyClients()
end

-- Пример: зарегистрировать всё, что имеет Humanoid и свойство Name.
local function scanWorkspace()
    for _, instance in ipairs(workspace:GetDescendants()) do
        if instance:IsA("Model") then
            local humanoid = instance:FindFirstChildOfClass("Humanoid")
            if humanoid then
                local name = instance.Name
                if not hpObjects[instance] then
                    registerObject(instance, math.ceil(humanoid.MaxHealth), name)
                end
            end
        elseif instance:IsA("Part") then
            -- Можно присваивать кастомный HP объект, например любой Part
            -- В этом примере не регистрируем по умолчанию
        end
    end
end

-- Обработка выбора
selectObjectEvent.OnServerEvent:Connect(function(player, objectId)
    if typeof(objectId) ~= "string" then
        return
    end

    local target = nil
    for obj, _ in pairs(hpObjects) do
        if tostring(obj) == objectId then
            target = obj
            break
        end
    end

    if not target then
        return
    end

    -- Сохраняем несколько целей для игрока
    if not selectedTargets[player] then
        selectedTargets[player] = {}
    end

    table.insert(selectedTargets[player], target)

    -- Отмечаем highlight
    local attachPart = target
    if target:IsA("Model") then
        attachPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart")
    end

    if attachPart then
        attachHighlight(attachPart, Color3.fromRGB(0, 255, 144))
    end

    -- Отправить подтверждение
    selectObjectEvent:FireClient(player, {
        name = hpObjects[target].name,
        hp = hpObjects[target].currentHp,
        maxHp = hpObjects[target].maxHp,
    })
end)

clearSelectionEvent.OnServerEvent:Connect(function(player)
    if selectedTargets[player] then
        for _, target in ipairs(selectedTargets[player]) do
            local attachPart = target
            if target:IsA("Model") then
                attachPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChildWhichIsA("BasePart")
            end
            if attachPart then
                removeHighlight(attachPart)
            end
        end
        selectedTargets[player] = {}
    end
end)

-- Клиент просит меню
requestMenuEvent.OnServerEvent:Connect(function(player)
    notifyClients()
end)

-- Тестовые команды:
-- 1) Выбранный объект получает урон:
-- local part = workspace.SomePart
-- damageObject(part, 10)
-- 2) Подобрать объект, сделать HP:
-- registerObject(workspace.SomeNPC, 200, "Boss")

-- Проверяем workspace сразу
scanWorkspace()

-- Пример автоматического обновления HP у humanoids
for _, model in ipairs(workspace:GetDescendants()) do
    if model:IsA("Model") then
        local humanoid = model:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid.Died:Connect(function()
                if hpObjects[model] then
                    hpObjects[model].currentHp = 0
                    notifyClients()
                end
            end)
        end
    end
end

print("HP system initialized")
