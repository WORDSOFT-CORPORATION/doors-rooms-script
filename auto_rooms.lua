-- Created by WORDSOFT
-- Script version: 1.0.2
-- Оптимизированная русская версия AutoRooms (Rooms для DOORS)
-- Требует: запускать внутри режима Rooms (в игре DOORS)
-- Подходящая для Delta / мобильных executor'ов (оптимизировано)

-- ====== Настройки (при необходимости меняй) ======
local NOTIFY_SOUND_ID = "rbxassetid://550209561"
local FINISH_SOUND_ID = "rbxassetid://4590662766"
local WALK_SPEED = 21
local PATH_RECOMPUTE_DELAY = 0.9   -- сек между попытками построить путь
local STUCK_TIMEOUT = 2.0          -- сек — время ожидания достижения вэйпоинта
local HEARTBEAT_INTERVAL = 0.07    -- обновление UI/ESP (примерно 14 FPS)
local MAX_BILLBOARDS = 12          -- максимум ESP-целей (для оптимизации)
local TELEPORT_HEIGHT = 300        -- высота, куда телепортируем, если нет шкафа
local LOCKER_SEARCH_RADIUS = 80    -- как далеко искать шкаф (оптимизация)
-- ================================================

-- Проверка места
if game.PlaceId ~= 6839171747 or game.ReplicatedStorage.GameData.Floor.Value ~= "Rooms" then
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {
            Title = "Ошибка";
            Text = "Запускай скрипт только в режиме Rooms!"
        })
    end)
    local s = Instance.new("Sound", game.SoundService)
    s.SoundId = NOTIFY_SOUND_ID
    s.Volume = 4
    s.PlayOnRemove = true
    s:Destroy()
    return
end

-- Защита: не запускать второй экземпляр
if workspace:FindFirstChild("PathFindPartsFolder") then
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {
            Title = "Предупреждение";
            Text = "Скрипт уже запущен. Перезапусти игру если нужен новый запуск."
        })
    end)
    local s = Instance.new("Sound", game.SoundService)
    s.SoundId = NOTIFY_SOUND_ID
    s.Volume = 4
    s.PlayOnRemove = true
    s:Destroy()
    return
end

-- Сервисы
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local LatestRoom = game.ReplicatedStorage.GameData.LatestRoom
local workspaceRooms = workspace:WaitForChild("CurrentRooms")

-- Состояния
local isActive = true
local totalRoomsPassed = 0
local totalMonstersEncountered = 0
local startTime = tick()
local espDoors = true
local espMonsters = true
local useDrawingLine = false -- линия через Drawing (если доступно и хочешь)
local isHiding = false

-- Папка для визуалов (менее тяжёлая)
local Folder = Instance.new("Folder")
Folder.Name = "PathFindPartsFolder"
Folder.Parent = workspace

-- Отключим модуль A90 если он есть (оригинальная защита)
pcall(function()
    local mod = LocalPlayer.PlayerGui.MainUI.Initiator.Main_Game.RemoteListener.Modules:FindFirstChild("A90")
    if mod then mod.Name = "lol" end
end)

-- Отключаем AFK disconnect
do
    local GC = getconnections or get_signal_cons
    if GC and LocalPlayer and LocalPlayer.Idled then
        pcall(function()
            for _,v in pairs(GC(LocalPlayer.Idled)) do
                if v.Disable then pcall(function() v:Disable() end) end
                if v.Disconnect then pcall(function() v:Disconnect() end) end
            end
        end)
    end
end

-- Утилиты
local function notify(title, text, soundId)
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {Title = title; Text = text; Duration = 3})
    end)
    if soundId then
        local s = Instance.new("Sound", game.SoundService)
        s.SoundId = soundId
        s.Volume = 3
        s.PlayOnRemove = true
        s:Destroy()
    end
end

local function formatTime(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then
        return string.format("%02d:%02d:%02d", h, m, s)
    else
        return string.format("%02d:%02d", m, s)
    end
end

-- Поиск ближайшего пустого шкафа (оптимизирован)
local function getLocker()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return nil end
    local lpPos = LocalPlayer.Character.HumanoidRootPart.Position
    local closest = nil
    local closestDist = LOCKER_SEARCH_RADIUS + 1
    for _,v in pairs(workspaceRooms:GetDescendants()) do
        if v.Name == "Rooms_Locker" and v:FindFirstChild("Door") and v:FindFirstChild("HiddenPlayer") then
            if v.HiddenPlayer.Value == nil and v.Door.Position.Y > -3 then
                local dpos = v.Door.Position
                local dist = (lpPos - dpos).Magnitude
                if dist < closestDist then
                    closestDist = dist
                    closest = v.Door
                end
            end
        end
    end
    return closest
end

-- Получение целевой двери (или шкаф если монстр)
local function getPathTarget()
    local entity = workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120")
    if entity and entity:FindFirstChild("Main") and entity.Main.Position.Y > -4 then
        return getLocker()
    end
    local roomIndex = LatestRoom.Value
    local room = workspaceRooms:FindFirstChild(tostring(roomIndex))
    if room and room:FindFirstChild("Door") and room.Door:FindFirstChild("Door") then
        return room.Door.Door
    end
    -- fallback: ближайшая дверь
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return nil end
    local lpPos = LocalPlayer.Character.HumanoidRootPart.Position
    local nearest = nil
    local nDist = 99999
    for _,r in pairs(workspaceRooms:GetChildren()) do
        if r:FindFirstChild("Door") and r.Door:FindFirstChild("Door") then
            local dpart = r.Door.Door
            local dist = (lpPos - dpart.Position).Magnitude
            if dist < nDist then
                nDist = dist
                nearest = dpart
            end
        end
    end
    return nearest
end

-- Телепорт наверх (если нет шкафа)
local function teleportUp()
    pcall(function()
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
        local hrp = LocalPlayer.Character.HumanoidRootPart
        hrp.CFrame = CFrame.new(hrp.Position.X, TELEPORT_HEIGHT, hrp.Position.Z)
        wait(0.05)
    end)
end

-- Улучшенная логика следования пути (Pathfinding) с проверкой застреваний и попытками
local function followPathTo(targetPart)
    if not targetPart or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return false end
    local startPos = LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(0,3,0)
    local okAttempt = false

    local path = PathfindingService:CreatePath({WaypointSpacing = 1, AgentRadius = 0.1, AgentCanJump = false})
    path:ComputeAsync(startPos, targetPart.Position)
    if path.Status == Enum.PathStatus.NoPath then
        return false
    end

    local waypoints = path:GetWaypoints()
    -- сокращаем количество точек для мобильных
    if #waypoints > 80 then
        local step = math.ceil(#waypoints / 80)
        local new = {}
        for i=1,#waypoints,step do table.insert(new, waypoints[i]) end
        waypoints = new
    end

    for i,wp in ipairs(waypoints) do
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return false end
        -- двигаемся
        local humanoid = LocalPlayer.Character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(wp.Position)
            local startWait = tick()
            local reached = false
            while tick() - startWait < STUCK_TIMEOUT do
                if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
                local dist = (LocalPlayer.Character.HumanoidRootPart.Position - wp.Position).Magnitude
                if dist <= 2.5 then
                    reached = true
                    break
                end
                wait(0.06)
            end
            if not reached then
                -- не дошёл до вэйпоинта — считаем застрял, прекращаем и вернём false, чтобы внешний цикл пересчитал путь
                return false
            end
        else
            return false
        end
    end

    return true
end

-- ESP (Billboard fallback, лёгкий и мало нагружает телефон)
local EspCache = {} -- {instance = billboard, target = part}
local function clearEsp()
    for _,v in pairs(EspCache) do
        pcall(function() v.instance:Destroy() end)
    end
    EspCache = {}
end

local function createBillboard(target, label)
    if not target or not target.Parent then return nil end
    local bg = Instance.new("BillboardGui")
    bg.Adornee = target
    bg.Size = UDim2.new(0,120,0,30)
    bg.AlwaysOnTop = true
    bg.StudsOffset = Vector3.new(0, -1.4, 0)
    local txt = Instance.new("TextLabel", bg)
    txt.Size = UDim2.new(1,0,1,0)
    txt.BackgroundTransparency = 1
    txt.TextColor3 = Color3.new(1,1,1)
    txt.Font = Enum.Font.Gotham
    txt.TextSize = 14
    txt.Text = label
    txt.TextStrokeTransparency = 0.7
    bg.Parent = workspace
    return bg
end

-- Отслеживание появления монстров, уведомление и авто-прятка
local function handleEntitySpawned(ent)
    if not ent or not ent.Name then return end
    local name = ent.Name
    if name == "A60" or name == "A120" or name == "A90" then
        totalMonstersEncountered = totalMonstersEncountered + 1
        notify("Внимание!", "Появился монстр: "..name, NOTIFY_SOUND_ID)

        -- стартуем прятку в отдельном потоке, чтобы основной цикл не блокировался
        spawn(function()
            if not isActive then return end
            -- сначала ищем шкаф
            local locker = getLocker()
            if locker then
                -- пробуем добежать до шкафа
                isHiding = true
                local ok = followPathTo(locker)
                if ok then
                    -- активируем HidePrompt
                    pcall(function()
                        if locker.Parent and locker.Parent:FindFirstChild("HidePrompt") then
                            fireproximityprompt(locker.Parent.HidePrompt)
                        end
                    end)
                    -- ждём пока монстр уходит (максимум 12 секунд)
                    local startWait = tick()
                    while (workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120")) and tick() - startWait < 12 do
                        wait(0.6)
                    end
                else
                    -- не дошли — если нет шкафа поблизости, телепортируем наверх
                    teleportUp()
                    wait(1.2)
                end
                isHiding = false
            else
                -- если вовсе нет шкафа — телепорт наверх
                teleportUp()
                wait(1.2)
            end
        end)
    end
end

-- Подписки на появление сущностей
workspace.ChildAdded:Connect(function(child)
    pcall(function() handleEntitySpawned(child) end)
end)
-- проверим уже существующие
for _,c in pairs(workspace:GetChildren()) do
    pcall(function() handleEntitySpawned(c) end)
end

-- UI (упрощённый и лёгкий)
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "WordsoftAutoRoomsUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = game.CoreGui

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Size = UDim2.new(0,250,0,140)
MainFrame.Position = UDim2.new(1, -260, 0, 20)
MainFrame.BackgroundColor3 = Color3.fromRGB(18,18,18)
MainFrame.BackgroundTransparency = 0.08
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Active = true
MainFrame.Draggable = true

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, -8, 0, 26)
Title.Position = UDim2.new(0,4,0,4)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(255,255,255)
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Text = "WORDSOFT — AutoRooms 1.0.2"

local roomLabel = Instance.new("TextLabel", MainFrame)
roomLabel.Size = UDim2.new(1, -8, 0, 20)
roomLabel.Position = UDim2.new(0,4,0,34)
roomLabel.BackgroundTransparency = 1
roomLabel.Font = Enum.Font.Gotham
roomLabel.TextSize = 13
roomLabel.TextColor3 = Color3.fromRGB(200,200,200)
roomLabel.Text = "Текущая комната: 0"
roomLabel.TextXAlignment = Enum.TextXAlignment.Left

local totalRoomsLabel = Instance.new("TextLabel", MainFrame)
totalRoomsLabel.Size = UDim2.new(1, -8, 0, 18)
totalRoomsLabel.Position = UDim2.new(0,4,0,54)
totalRoomsLabel.BackgroundTransparency = 1
totalRoomsLabel.Font = Enum.Font.Gotham
totalRoomsLabel.TextSize = 12
totalRoomsLabel.TextColor3 = Color3.fromRGB(200,200,200)
totalRoomsLabel.Text = "Всего пройдено дверей: 0"
totalRoomsLabel.TextXAlignment = Enum.TextXAlignment.Left

local timeLabel = Instance.new("TextLabel", MainFrame)
timeLabel.Size = UDim2.new(1, -8, 0, 18)
timeLabel.Position = UDim2.new(0,4,0,74)
timeLabel.BackgroundTransparency = 1
timeLabel.Font = Enum.Font.Gotham
timeLabel.TextSize = 12
timeLabel.TextColor3 = Color3.fromRGB(200,200,200)
timeLabel.Text = "Время: 00:00"
timeLabel.TextXAlignment = Enum.TextXAlignment.Left

local monstersLabel = Instance.new("TextLabel", MainFrame)
monstersLabel.Size = UDim2.new(1, -8, 0, 18)
monstersLabel.Position = UDim2.new(0,4,0,94)
monstersLabel.BackgroundTransparency = 1
monstersLabel.Font = Enum.Font.Gotham
monstersLabel.TextSize = 12
monstersLabel.TextColor3 = Color3.fromRGB(200,200,200)
monstersLabel.Text = "Монстров встречено: 0"
monstersLabel.TextXAlignment = Enum.TextXAlignment.Left

-- переключатели ESP
local espDoorBtn = Instance.new("TextButton", MainFrame)
espDoorBtn.Size = UDim2.new(0,56,0,18)
espDoorBtn.Position = UDim2.new(0,6,0,116)
espDoorBtn.Font = Enum.Font.Gotham
espDoorBtn.TextSize = 12
espDoorBtn.Text = (espDoors and "ESP: Двери ✓") or "ESP: Двери ✗"
espDoorBtn.BackgroundColor3 = espDoors and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
espDoorBtn.TextColor3 = Color3.fromRGB(255,255,255)
espDoorBtn.BorderSizePixel = 0

local espMonBtn = Instance.new("TextButton", MainFrame)
espMonBtn.Size = UDim2.new(0,80,0,18)
espMonBtn.Position = UDim2.new(0,70,0,116)
espMonBtn.Font = Enum.Font.Gotham
espMonBtn.TextSize = 12
espMonBtn.Text = (espMonsters and "ESP: Монстры ✓") or "ESP: Монстры ✗"
espMonBtn.BackgroundColor3 = espMonsters and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
espMonBtn.TextColor3 = Color3.fromRGB(255,255,255)
espMonBtn.BorderSizePixel = 0

local stopBtn = Instance.new("TextButton", MainFrame)
stopBtn.Size = UDim2.new(0,56,0,18)
stopBtn.Position = UDim2.new(0,160,0,116)
stopBtn.Font = Enum.Font.Gotham
stopBtn.TextSize = 12
stopBtn.Text = "Откл"
stopBtn.BackgroundColor3 = Color3.fromRGB(150,30,30)
stopBtn.TextColor3 = Color3.fromRGB(255,255,255)
stopBtn.BorderSizePixel = 0

espDoorBtn.MouseButton1Click:Connect(function()
    espDoors = not espDoors
    espDoorBtn.Text = (espDoors and "ESP: Двери ✓") or "ESP: Двери ✗"
    espDoorBtn.BackgroundColor3 = espDoors and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
end)
espMonBtn.MouseButton1Click:Connect(function()
    espMonsters = not espMonsters
    espMonBtn.Text = (espMonsters and "ESP: Монстры ✓") or "ESP: Монстры ✗"
    espMonBtn.BackgroundColor3 = espMonsters and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
end)
stopBtn.MouseButton1Click:Connect(function()
    notify("AutoRooms", "Скрипт остановлен вручную.", NOTIFY_SOUND_ID)
    isActive = false
    -- чистим
    pcall(function() ScreenGui:Destroy() end)
    pcall(function() Folder:ClearAllChildren() end)
    pcall(function() Folder:Destroy() end)
end)

-- Мини-лейбл посередине (текущая комната, большой и удобный)
local midLabel = Instance.new("TextLabel", ScreenGui)
midLabel.Size = UDim2.new(0,160,0,40)
midLabel.Position = UDim2.new(0.5, -80, 0, 8)
midLabel.BackgroundColor3 = Color3.fromRGB(12,12,12)
midLabel.BackgroundTransparency = 0.35
midLabel.BorderSizePixel = 0
midLabel.Font = Enum.Font.GothamBold
midLabel.TextSize = 18
midLabel.TextColor3 = Color3.fromRGB(255,255,255)
midLabel.Text = "Комната: 0"

-- Основной цикл автопрохождения (в отдельном потоке)
spawn(function()
    while isActive do
        pcall(function()
            if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then wait(0.5); return end

            -- обновляем UI
            local curRoom = math.clamp(LatestRoom.Value, 0, 10000)
            midLabel.Text = "Комната: "..tostring(curRoom)
            roomLabel.Text = "Текущая комната: "..tostring(curRoom)
            if curRoom > totalRoomsPassed then
                totalRoomsPassed = curRoom
            end
            totalRoomsLabel.Text = "Всего пройдено дверей: "..tostring(totalRoomsPassed)
            timeLabel.Text = "Время: "..formatTime(tick() - startTime)
            monstersLabel.Text = "Монстров встречено: "..tostring(totalMonstersEncountered)

            -- управление движением
            if curRoom ~= 1000 then
                LocalPlayer.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
            else
                LocalPlayer.DevComputerMovementMode = Enum.DevComputerMovementMode.KeyboardMouse
                -- финал
                notify("AutoRooms", "Достигнута конечная комната. Скрипт завершил работу.", FINISH_SOUND_ID)
                isActive = false
                return
            end

            -- если есть монстр поблизости — getPathTarget вернёт шкаф
            local target = getPathTarget()
            if not target then
                wait(0.6)
                return
            end

            -- Если цель — шкаф (значит монстр) — прячемся
            local parentName = target.Parent and target.Parent.Name or ""
            if parentName == "Rooms_Locker" then
                -- скрытие: используем followPathTo, если не получилось — телепорт
                local ok = followPathTo(target)
                if ok then
                    pcall(function()
                        if target.Parent and target.Parent:FindFirstChild("HidePrompt") then
                            fireproximityprompt(target.Parent.HidePrompt)
                        end
                    end)
                    -- ждём пока монстр не исчезнет
                    local timeout = tick()
                    while (workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120")) and tick() - timeout < 12 do
                        wait(0.6)
                    end
                else
                    -- не удалось добраться — телепорт наверх
                    teleportUp()
                    wait(1)
                end
            else
                -- обычно двигаемся к двери
                local ok = followPathTo(target)
                if not ok then
                    -- если путь сломался — попробуем пересчитать через небольшую паузу
                    wait(0.2)
                end
            end

            wait(PATH_RECOMPUTE_DELAY)
        end)
    end
end)

-- ESP обновление (упрощённый Billboard режим для телефона)
local lastEspUpdate = 0
RunService.Heartbeat:Connect(function(dt)
    if tick() - lastEspUpdate < HEARTBEAT_INTERVAL then return end
    lastEspUpdate = tick()

    -- очищаем старые билборды
    clearEsp()

    -- двери
    if espDoors then
        local count = 0
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            local lpPos = LocalPlayer.Character.HumanoidRootPart.Position
            for _,r in pairs(workspaceRooms:GetChildren()) do
                if count >= MAX_BILLBOARDS then break end
                if r:FindFirstChild("Door") and r.Door:FindFirstChild("Door") then
                    local part = r.Door.Door
                    if (lpPos - part.Position).Magnitude < 140 then
                        local bb = createBillboard(part, "Дверь — "..tostring(math.floor((lpPos - part.Position).Magnitude)).."м")
                        if bb then
                            table.insert(EspCache, {instance = bb, target = part})
                            count = count + 1
                        end
                    end
                end
            end
        end
    end

    -- монстры
    if espMonsters then
        for _,name in pairs({"A60","A120","A90"}) do
            local ent = workspace:FindFirstChild(name)
            if ent and ent:FindFirstChild("Main") then
                local bb = createBillboard(ent.Main, name)
                if bb then
                    table.insert(EspCache, {instance = bb, target = ent.Main})
                end
            end
        end
    end
end)

-- Обновление таймера и мелких вещей (нечасто, чтобы экономить ресурс)
spawn(function()
    while isActive do
        pcall(function()
            if LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
                LocalPlayer.Character.Humanoid.WalkSpeed = WALK_SPEED
            end
        end)
        wait(0.8)
    end
end)

-- Отслеживание изменения номера комнаты (для счётчика)
LatestRoom:GetPropertyChangedSignal("Value"):Connect(function()
    local v = LatestRoom.Value
    pcall(function()
        if v > totalRoomsPassed then
            totalRoomsPassed = v
        end
    end)
end)

-- Очистка при выходе
local function cleanup()
    isActive = false
    pcall(function() ScreenGui:Destroy() end)
    pcall(function() clearEsp() end)
    pcall(function() Folder:ClearAllChildren() end)
    pcall(function() Folder:Destroy() end)
end

Players.LocalPlayer.CharacterRemoving:Connect(function() cleanup() end)
game:BindToClose(function() cleanup() end)

-- Запуск-уведомление
notify("WORDSOFT AutoRooms", "Скрипт запущен. Удачной игры.", NOTIFY_SOUND_ID)
