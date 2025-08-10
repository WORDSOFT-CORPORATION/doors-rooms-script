-- Улучшенный AutoRooms для Delta (оптимизирован для телефона)
-- Основа: оригинальный код geodude#2619, переработан интерфейс и логика
-- WORDSOFT — адаптация и оптимизация

-- ====== Настройки (можешь менять) ======
local NOTIFY_SOUND_ID = "rbxassetid://550209561"
local FINISH_SOUND_ID = "rbxassetid://4590662766"
local WALK_SPEED = 21
local PATH_RECOMPUTE_DELAY = 1.0         -- сек между пересчётами пути
local STUCK_TIMEOUT = 2.0                -- сек, если не дошёл до точки — считаем застрял
local HEARTBEAT_INTERVAL = 0.06          -- оптимизация: как часто обновляем UI/ESP (примерно 16 FPS)
local MAX_WAYPOINTS_RENDER = 60          -- ограничение создаваемых визуалов пути
-- =========================================

if game.PlaceId ~= 6839171747 or game.ReplicatedStorage.GameData.Floor.Value ~= "Rooms" then
    game.StarterGui:SetCore("SendNotification", { Title = "Неверное место"; Text = "Похоже, это не режим Rooms. Запусти скрипт в Rooms!" })
    local s = Instance.new("Sound", game.SoundService)
    s.SoundId = NOTIFY_SOUND_ID
    s.Volume = 5
    s.PlayOnRemove = true
    s:Destroy()
    return
elseif workspace:FindFirstChild("PathFindPartsFolder") then
    game.StarterGui:SetCore("SendNotification", { Title = "Предупреждение"; Text = "Уже запущен бот. Если он сломался — перезапусти игру." })
    local s = Instance.new("Sound", game.SoundService)
    s.SoundId = NOTIFY_SOUND_ID
    s.Volume = 5
    s.PlayOnRemove = true
    s:Destroy()
    return
end

-- Сервисы и переменные
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local LatestRoom = game.ReplicatedStorage.GameData.LatestRoom
local workspaceRooms = workspace.CurrentRooms

-- Счётчики и состояния
local totalRoomsPassed = 0
local totalMonstersEncountered = 0
local startTime = tick()
local lastPathCompute = 0
local lastHeartbeat = 0
local espShowDoors = true
local espShowMonsters = true
local isHiding = false
local isActive = true

-- Создаём папку для визуалов
local Folder = Instance.new("Folder")
Folder.Parent = workspace
Folder.Name = "PathFindPartsFolder"

-- Отключаем "A90" модуль если есть
pcall(function()
    local mod = LocalPlayer.PlayerGui.MainUI.Initiator.Main_Game.RemoteListener.Modules:FindFirstChild("A90")
    if mod then mod.Name = "lol" end
end)

-- Функция поиска ближайшего пустого шкафа
local function getLocker()
    local closest
    local lpPos = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position
    if not lpPos then return nil end
    for _,v in pairs(workspaceRooms:GetDescendants()) do
        if v.Name == "Rooms_Locker" and v:FindFirstChild("Door") and v:FindFirstChild("HiddenPlayer") then
            if v.HiddenPlayer.Value == nil and v.Door.Position.Y > -3 then
                local dpos = v.Door.Position
                if not closest then
                    closest = v.Door
                else
                    if (lpPos - dpos).Magnitude < (lpPos - closest.Position).Magnitude then
                        closest = v.Door
                    end
                end
            end
        end
    end
    return closest
end

-- Функция получения текущей цели (дверь или шкаф если монстр)
local function getPathTarget()
    local entity = workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120")
    if entity and entity.Main and entity.Main.Position.Y > -4 then
        return getLocker()
    end
    -- Защита: проверка существования комнаты
    local roomIndex = LatestRoom.Value
    local room = workspaceRooms:FindFirstChild(tostring(roomIndex))
    if room and room:FindFirstChild("Door") and room.Door:FindFirstChild("Door") then
        return room.Door.Door
    end
    -- fallback: ближайшая дверь в CurrentRooms
    local closestDoor
    local lpPos = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position
    if not lpPos then return nil end
    for _,r in pairs(workspaceRooms:GetChildren()) do
        if r:FindFirstChild("Door") and r.Door:FindFirstChild("Door") then
            local dpart = r.Door.Door
            if dpart and (lpPos - dpart.Position).Magnitude < 120 then
                closestDoor = r.Door.Door
                break
            end
        end
    end
    return closestDoor
end

-- UI: лёгкое окно справа сверху
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = game.CoreGui
ScreenGui.ResetOnSpawn = false

local MainFrame = Instance.new("Frame", ScreenGui)
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 260, 0, 140)
MainFrame.Position = UDim2.new(1, -270, 0, 20)
MainFrame.BackgroundTransparency = 0.12
MainFrame.BackgroundColor3 = Color3.fromRGB(20,20,20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ClipsDescendants = true

local Title = Instance.new("TextLabel", MainFrame)
Title.Size = UDim2.new(1, -8, 0, 28)
Title.Position = UDim2.new(0,4,0,4)
Title.Text = "AutoRooms — WORDSOFT"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextColor3 = Color3.fromRGB(255,255,255)
Title.BackgroundTransparency = 1
Title.TextXAlignment = Enum.TextXAlignment.Left

local roomLabel = Instance.new("TextLabel", MainFrame)
roomLabel.Size = UDim2.new(0.5, -6, 0, 22)
roomLabel.Position = UDim2.new(0,4,0,36)
roomLabel.Text = "Комната: 0"
roomLabel.Font = Enum.Font.Gotham
roomLabel.TextSize = 13
roomLabel.TextColor3 = Color3.fromRGB(200,200,200)
roomLabel.BackgroundTransparency = 1
roomLabel.TextXAlignment = Enum.TextXAlignment.Left

local totalRoomsLabel = Instance.new("TextLabel", MainFrame)
totalRoomsLabel.Size = UDim2.new(0.5, -6, 0, 22)
totalRoomsLabel.Position = UDim2.new(0.5, 2, 0,36)
totalRoomsLabel.Text = "Всего дверей: 0"
totalRoomsLabel.Font = Enum.Font.Gotham
totalRoomsLabel.TextSize = 13
totalRoomsLabel.TextColor3 = Color3.fromRGB(200,200,200)
totalRoomsLabel.BackgroundTransparency = 1
totalRoomsLabel.TextXAlignment = Enum.TextXAlignment.Left

local timeLabel = Instance.new("TextLabel", MainFrame)
timeLabel.Size = UDim2.new(1, -8, 0, 20)
timeLabel.Position = UDim2.new(0,4,0,60)
timeLabel.Text = "Время: 00:00"
timeLabel.Font = Enum.Font.Gotham
timeLabel.TextSize = 13
timeLabel.TextColor3 = Color3.fromRGB(200,200,200)
timeLabel.BackgroundTransparency = 1
timeLabel.TextXAlignment = Enum.TextXAlignment.Left

local monstersLabel = Instance.new("TextLabel", MainFrame)
monstersLabel.Size = UDim2.new(1, -8, 0, 20)
monstersLabel.Position = UDim2.new(0,4,0,82)
monstersLabel.Text = "Монстров встречено: 0"
monstersLabel.Font = Enum.Font.Gotham
monstersLabel.TextSize = 13
monstersLabel.TextColor3 = Color3.fromRGB(200,200,200)
monstersLabel.BackgroundTransparency = 1
monstersLabel.TextXAlignment = Enum.TextXAlignment.Left

-- ESP переключатели
local espDoorsLabel = Instance.new("TextLabel", MainFrame)
espDoorsLabel.Size = UDim2.new(0.5, -6, 0, 20)
espDoorsLabel.Position = UDim2.new(0,4,0,104)
espDoorsLabel.Text = "ESP двери"
espDoorsLabel.Font = Enum.Font.Gotham
espDoorsLabel.TextSize = 13
espDoorsLabel.TextColor3 = Color3.fromRGB(200,200,200)
espDoorsLabel.BackgroundTransparency = 1
espDoorsLabel.TextXAlignment = Enum.TextXAlignment.Left

local espDoorsBtn = Instance.new("TextButton", MainFrame)
espDoorsBtn.Size = UDim2.new(0,34,0,18)
espDoorsBtn.Position = UDim2.new(0.5, 2, 0,104)
espDoorsBtn.Text = espShowDoors and "Вкл" or "Выкл"
espDoorsBtn.Font = Enum.Font.Gotham
espDoorsBtn.TextSize = 12
espDoorsBtn.BackgroundColor3 = espShowDoors and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
espDoorsBtn.TextColor3 = Color3.fromRGB(255,255,255)
espDoorsBtn.BorderSizePixel = 0

local espMonLabel = Instance.new("TextLabel", MainFrame)
espMonLabel.Size = UDim2.new(0.5, -6, 0, 20)
espMonLabel.Position = UDim2.new(0,4,0,124)
espMonLabel.Text = "ESP монстры"
espMonLabel.Font = Enum.Font.Gotham
espMonLabel.TextSize = 13
espMonLabel.TextColor3 = Color3.fromRGB(200,200,200)
espMonLabel.BackgroundTransparency = 1
espMonLabel.TextXAlignment = Enum.TextXAlignment.Left

local espMonBtn = Instance.new("TextButton", MainFrame)
espMonBtn.Size = UDim2.new(0,34,0,18)
espMonBtn.Position = UDim2.new(0.5, 2, 0,124)
espMonBtn.Text = espShowMonsters and "Вкл" or "Выкл"
espMonBtn.Font = Enum.Font.Gotham
espMonBtn.TextSize = 12
espMonBtn.BackgroundColor3 = espShowMonsters and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
espMonBtn.TextColor3 = Color3.fromRGB(255,255,255)
espMonBtn.BorderSizePixel = 0

-- Кнопки
espDoorsBtn.MouseButton1Click:Connect(function()
    espShowDoors = not espShowDoors
    espDoorsBtn.Text = espShowDoors and "Вкл" or "Выкл"
    espDoorsBtn.BackgroundColor3 = espShowDoors and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
end)
espMonBtn.MouseButton1Click:Connect(function()
    espShowMonsters = not espShowMonsters
    espMonBtn.Text = espShowMonsters and "Вкл" or "Выкл"
    espMonBtn.BackgroundColor3 = espShowMonsters and Color3.fromRGB(30,120,30) or Color3.fromRGB(120,30,30)
end)

-- Текстовый маленький лейбл посередине экрана (номер текущей комнаты, минимал)
local MidLabel = Instance.new("TextLabel", ScreenGui)
MidLabel.Size = UDim2.new(0,140,0,36)
MidLabel.Position = UDim2.new(0.5, -70, 0, 8)
MidLabel.BackgroundTransparency = 0.4
MidLabel.BackgroundColor3 = Color3.fromRGB(10,10,10)
MidLabel.BorderSizePixel = 0
MidLabel.TextColor3 = Color3.fromRGB(255,255,255)
MidLabel.Font = Enum.Font.GothamBold
MidLabel.TextSize = 18
MidLabel.Text = "Комната: 0"
MidLabel.TextStrokeTransparency = 0.8

-- Функция уведомления + звук
local function notify(title, text, soundId)
    pcall(function()
        game.StarterGui:SetCore("SendNotification", { Title = title; Text = text; Duration = 3 })
    end)
    if soundId then
        local s = Instance.new("Sound", game.SoundService)
        s.SoundId = soundId
        s.Volume = 3
        s.PlayOnRemove = true
        s:Destroy()
    end
end

-- ESP: используем Drawing API если есть (эффективнее), иначе BillboardGui fallback
local DrawingAvailable = (typeof(drawing) == "table" or typeof(Drawing) == "table")
local EspObjects = {} -- таблица для линий/текстов

local function createEspForTarget(target, label)
    if not target then return nil end
    if DrawingAvailable and drawing then
        local line = drawing.new("Line")
        local txt = drawing.new("Text")
        line.Thickness = 2
        line.Transparency = 1
        txt.Center = true
        txt.Size = 14
        txt.Outline = true
        txt.Color = Color3.new(1,1,1)
        return {target=target, line=line, txt=txt, label=label}
    else
        -- fallback simple BillboardGui (lightweight)
        local ad = Instance.new("BillboardGui")
        ad.Size = UDim2.new(0,150,0,30)
        ad.AlwaysOnTop = true
        ad.StudsOffset = Vector3.new(0, -1.5, 0)
        local txt = Instance.new("TextLabel", ad)
        txt.Size = UDim2.new(1,1,1,1)
        txt.BackgroundTransparency = 1
        txt.TextColor3 = Color3.fromRGB(255,255,255)
        txt.Font = Enum.Font.Gotham
        txt.TextSize = 14
        txt.Text = label
        ad.Parent = target.Parent or workspace
        return {target=target, billboard=ad, label=label}
    end
end

local function removeEsp(obj)
    if not obj then return end
    if obj.line then
        pcall(function() obj.line:Remove() end)
        pcall(function() obj.txt:Remove() end)
    elseif obj.billboard then
        pcall(function() obj.billboard:Destroy() end)
    end
end

-- Отслеживание спавна монстров
local function onEntitySpawned(ent)
    if not ent or not ent.Name then return end
    local name = ent.Name
    if name == "A60" or name == "A120" or name == "A90" then
        totalMonstersEncountered = totalMonstersEncountered + 1
        notify("Внимание!", "Появился монстр: "..name, NOTIFY_SOUND_ID)
        -- Запускаем прятку: идём к шкафу если есть
        spawn(function()
            if not isActive then return end
            local locker = getLocker()
            if locker then
                -- инициируем моментальную прятку
                pcall(function()
                    -- перепрокладываем путь к шкафу используя Pathfinding
                    local path = PathfindingService:CreatePath({WaypointSpacing=1, AgentRadius=0.1, AgentCanJump=false})
                    local fromPos = LocalPlayer.Character and LocalPlayer.Character.HumanoidRootPart and LocalPlayer.Character.HumanoidRootPart.Position or nil
                    if fromPos then
                        path:ComputeAsync(fromPos - Vector3.new(0,3,0), locker.Position)
                        if path.Status ~= Enum.PathStatus.NoPath then
                            isHiding = true
                            for i,wp in pairs(path:GetWaypoints()) do
                                if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
                                LocalPlayer.Character.Humanoid:MoveTo(wp.Position)
                                local ok = LocalPlayer.Character.Humanoid.MoveToFinished:Wait()
                                if not ok then
                                    -- застрял, попробуем следующий путь
                                    break
                                end
                            end
                            -- если возле шкафа — активировать прятку
                            if locker.Parent and locker.Parent:FindFirstChild("HidePrompt") then
                                pcall(function() fireproximityprompt(locker.Parent.HidePrompt) end)
                            end
                            wait(0.2)
                            isHiding = false
                        end
                    end
                end)
            end
        end)
    end
end

-- Подписываемся на spawn
workspace.ChildAdded:Connect(function(child)
    pcall(function() onEntitySpawned(child) end)
end)
-- Проверяем если уже есть
for _,child in pairs(workspace:GetChildren()) do
    pcall(function() onEntitySpawned(child) end)
end

-- Защита от AFK (отключаем отключения)
local GC = getconnections or get_signal_cons
if GC and LocalPlayer and LocalPlayer.Idled then
    for i,v in pairs(GC(LocalPlayer.Idled)) do
        if v["Disable"] then
            pcall(function() v["Disable"](v) end)
        elseif v["Disconnect"] then
            pcall(function() v["Disconnect"](v) end)
        end
    end
end

-- Улучшенная логика движения: путь с проверкой застревания
local function followPathTo(targetPart)
    if not targetPart or not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return false end
    local fromPos = LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(0,3,0)
    local success = false
    local path = PathfindingService:CreatePath({WaypointSpacing = 1, AgentRadius = 0.1, AgentCanJump = false})
    path:ComputeAsync(fromPos, targetPart.Position)
    if path.Status == Enum.PathStatus.NoPath then return false end

    local waypoints = path:GetWaypoints()
    -- ограничиваем количество визуальных точек для оптимизации телефона
    local wpCount = #waypoints
    if wpCount > MAX_WAYPOINTS_RENDER then
        -- укоротим — берем лишь каждую n-ю точку
        local step = math.ceil(wpCount / MAX_WAYPOINTS_RENDER)
        local new = {}
        for i=1,wpCount,step do
            table.insert(new, waypoints[i])
        end
        waypoints = new
    end

    local lastPos = LocalPlayer.Character.HumanoidRootPart.Position
    for _,wp in pairs(waypoints) do
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Humanoid") then break end
        LocalPlayer.Character.Humanoid:MoveTo(wp.Position)
        local startWait = tick()
        local reached = false
        while tick() - startWait < STUCK_TIMEOUT do
            if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then break end
            local dist = (LocalPlayer.Character.HumanoidRootPart.Position - wp.Position).Magnitude
            if dist < 2.5 then
                reached = true
                break
            end
            wait(0.08)
        end
        if not reached then
            -- застрял — перестроим путь
            return false
        end
    end
    return true
end

-- Основной цикл автопрохождения (в отдельном потоке)
spawn(function()
    while isActive do
        pcall(function()
            if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then wait(0.5); return end

            -- Обновляем HUD
            local curRoom = math.clamp(LatestRoom.Value, 0, 10000)
            roomLabel.Text = "Комната: "..tostring(curRoom)
            MidLabel.Text = "Комната: "..tostring(curRoom)
            -- считаем пройденные двери (при увеличении LatestRoom)
            if curRoom > totalRoomsPassed then
                totalRoomsPassed = math.max(totalRoomsPassed, curRoom)
            end
            totalRoomsLabel.Text = "Всего дверей: "..tostring(totalRoomsPassed)
            monstersLabel.Text = "Монстров встречено: "..tostring(totalMonstersEncountered)

            -- Двигаем персонажа (включаем скриптовое управление)
            if curRoom ~= 1000 then
                LocalPlayer.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
            else
                LocalPlayer.DevComputerMovementMode = Enum.DevComputerMovementMode.KeyboardMouse
                Folder:ClearAllChildren()
                notify("AutoRooms", "Достигнута финальная комната. Скрипт завершил работу.", FINISH_SOUND_ID)
                isActive = false
                return
            end

            -- Получаем цель
            local target = getPathTarget()
            if not target then
                wait(0.5)
                return
            end

            -- Если появился монстр — приоритет прятки (getPathTarget вернёт шкаф)
            local entity = workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120")
            if entity and entity.Main and entity.Main.Position.Y > -4 then
                -- если есть шкаф рядом — прячемся (followPathTo сделает путь до шкафа)
                local locker = getLocker()
                if locker then
                    local ok = followPathTo(locker)
                    if ok then
                        if locker.Parent and locker.Parent:FindFirstChild("HidePrompt") then
                            pcall(function() fireproximityprompt(locker.Parent.HidePrompt) end)
                        end
                        -- ждем пока монстр уйдёт
                        local waitStart = tick()
                        while workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120") do
                            if tick() - waitStart > 12 then break end
                            wait(0.5)
                        end
                    else
                        -- не удалось добраться — пробуем перепрокладку позже
                        wait(0.6)
                    end
                else
                    -- нет шкафа — просто отойдём в сторону (просто стоим и ждем)
                    wait(0.5)
                end
            else
                -- обычное прохождение к двери
                local ok = followPathTo(target)
                if not ok then
                    -- перепробуем через небольшую паузу
                    wait(0.2)
                end
            end
            wait(PATH_RECOMPUTE_DELAY)
        end)
    end
end)

-- HEARTBEAT: обновление ESP (оптимизировано)
local lastTick = tick()
RunService.Heartbeat:Connect(function(delta)
    if tick() - lastHeartbeat < HEARTBEAT_INTERVAL then return end
    lastHeartbeat = tick()

    -- Очистка предыдущих ESP (удаляем старые Drawing / Billboard)
    for i,v in pairs(EspObjects) do
        removeEsp(v)
    end
    EspObjects = {}

    -- Собираем цели
    if espShowDoors then
        -- дверные цели: ближайшие N дверей (чтобы не рендерить все)
        local cnt = 0
        local lpRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if lpRoot then
            local lpPos = lpRoot.Position
            for _,r in pairs(workspaceRooms:GetChildren()) do
                if r:FindFirstChild("Door") and r.Door:FindFirstChild("Door") then
                    local dpart = r.Door.Door
                    if dpart and (lpPos - dpart.Position).Magnitude < 120 then
                        cnt = cnt + 1
                        table.insert(EspObjects, createEspForTarget(dpart, "Дверь"))
                        if cnt >= 12 then break end
                    end
                end
            end
        end
    end

    if espShowMonsters then
        for _,name in pairs({"A60","A120","A90"}) do
            local ent = workspace:FindFirstChild(name)
            if ent and ent:FindFirstChild("Main") then
                table.insert(EspObjects, createEspForTarget(ent.Main, name))
            end
        end
    end

    -- Рисуем линии и подписи (если Drawing доступен)
    if DrawingAvailable and drawing then
        local camera = workspace.CurrentCamera
        for _,obj in pairs(EspObjects) do
            if obj and obj.target and obj.line then
                pcall(function()
                    local pos3 = obj.target.Position
                    local screenPos, onscreen = camera:WorldToViewportPoint(pos3)
                    if onscreen then
                        local centerX = camera.ViewportSize.X/2
                        local centerY = camera.ViewportSize.Y/2
                        obj.line.From = Vector2.new(centerX, centerY)
                        obj.line.To = Vector2.new(screenPos.X, screenPos.Y)
                        obj.line.Color = Color3.new(1,1,1)
                        obj.txt.Position = Vector2.new((obj.line.To.X + obj.line.From.X)/2, (obj.line.To.Y + obj.line.From.Y)/2 + 12)
                        local dist = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and math.floor((LocalPlayer.Character.HumanoidRootPart.Position - pos3).Magnitude) or 0
                        obj.txt.Text = obj.label.." "..tostring(dist).."м"
                    else
                        obj.line.Visible = false
                        obj.txt.Visible = false
                    end
                end)
            elseif obj and obj.billboard then
                -- Billboard fallback: обновим текст и позицию offset
                pcall(function()
                    local txt = obj.billboard:FindFirstChildOfClass("TextLabel")
                    if txt and obj.target and obj.target.Parent then
                        txt.Text = obj.label.." "..tostring(math.floor((LocalPlayer.Character.HumanoidRootPart.Position - obj.target.Position).Magnitude)).."м"
                        obj.billboard.Adornee = obj.target
                    end
                end)
            end
        end
    else
        -- fallback Billboard already created
    end
end)

-- Функция чистки при выходе
local function cleanup()
    isActive = false
    pcall(function() ScreenGui:Destroy() end)
    pcall(function() Folder:ClearAllChildren() end)
    pcall(function() Folder:Destroy() end)
end

-- Подписка на изменение номера комнаты, чтобы считать прошедшие двери
LatestRoom:GetPropertyChangedSignal("Value"):Connect(function()
    local v = LatestRoom.Value
    pcall(function()
        MidLabel.Text = "Комната: "..tostring(v)
        roomLabel.Text = "Комната: "..tostring(v)
        if v > totalRoomsPassed then
            totalRoomsPassed = v
            totalRoomsLabel.Text = "Всего дверей: "..tostring(totalRoomsPassed)
        end
    end)
end)

-- Защита: при выходе персонажа или рестарте чистим
Players.LocalPlayer.CharacterRemoving:Connect(function() cleanup() end)
game:BindToClose(function() cleanup() end)

-- Финальное уведомление
notify("AutoRooms", "Скрипт запущен. Удачной игры.", NOTIFY_SOUND_ID)
