-- Made by geodude#2619, улучшено и русифицировано по заказу

if game.PlaceId ~= 6839171747 or game.ReplicatedStorage.GameData.Floor.Value ~= "Rooms" then
    game.StarterGui:SetCore("SendNotification", { Title = "Ошибка"; Text = "Вы должны быть в игре Rooms для запуска скрипта!" })

    local Sound = Instance.new("Sound")
    Sound.Parent = game.SoundService
    Sound.SoundId = "rbxassetid://550209561"
    Sound.Volume = 5
    Sound.PlayOnRemove = true
    Sound:Destroy()

    return
elseif workspace:FindFirstChild("PathFindPartsFolder") then
    game.StarterGui:SetCore("SendNotification", { Title = "Внимание"; Text = "Если скрипт не работает — напишите мне! geodude#2619" })

    local Sound = Instance.new("Sound")
    Sound.Parent = game.SoundService
    Sound.SoundId = "rbxassetid://550209561"
    Sound.Volume = 5
    Sound.PlayOnRemove = true
    Sound:Destroy()

    return
end

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = game.Players.LocalPlayer
local LatestRoom = game.ReplicatedStorage.GameData.LatestRoom

local Cooldown = false

-- Папка для визуализации пути
local Folder = Instance.new("Folder")
Folder.Name = "PathFindPartsFolder"
Folder.Parent = workspace

-- Переменные управления авто ТП
local AutoTPEnabled = false

-- Создаем GUI
local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
ScreenGui.Name = "RoomsBotGUI"

local Background = Instance.new("Frame", ScreenGui)
Background.Size = UDim2.new(0, 360, 0, 200)
Background.Position = UDim2.new(0, 20, 0, 20)
Background.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
Background.BorderSizePixel = 0
Background.Active = true
Background.Draggable = true

local Title = Instance.new("TextLabel", Background)
Title.Text = "Бот для Rooms"
Title.Size = UDim2.new(1, 0, 0, 30)
Title.BackgroundTransparency = 1
Title.TextColor3 = Color3.new(1,1,1)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 20

-- Текст для отображения текущей комнаты, монстра и двери
local InfoText = Instance.new("TextLabel", Background)
InfoText.Position = UDim2.new(0, 10, 0, 40)
InfoText.Size = UDim2.new(1, -20, 0, 60)
InfoText.BackgroundTransparency = 1
InfoText.TextColor3 = Color3.new(1,1,1)
InfoText.Font = Enum.Font.SourceSans
InfoText.TextSize = 16
InfoText.TextWrapped = true
InfoText.Text = "Комната: 0\nМонстр: Нет\nДверь: Нет\nРасстояние: 0"

-- Счётчик пройденных комнат
local RoomsPassed = 0

local RoomsPassedLabel = Instance.new("TextLabel", Background)
RoomsPassedLabel.Position = UDim2.new(0, 10, 0, 100)
RoomsPassedLabel.Size = UDim2.new(1, -20, 0, 20)
RoomsPassedLabel.BackgroundTransparency = 1
RoomsPassedLabel.TextColor3 = Color3.new(1,1,1)
RoomsPassedLabel.Font = Enum.Font.SourceSans
RoomsPassedLabel.TextSize = 16
RoomsPassedLabel.Text = "Пройдено комнат: 0"

-- Чекбокс авто ТП на верхний блок
local AutoTPCheckbox = Instance.new("TextButton", Background)
AutoTPCheckbox.Position = UDim2.new(0, 10, 0, 130)
AutoTPCheckbox.Size = UDim2.new(0, 140, 0, 30)
AutoTPCheckbox.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
AutoTPCheckbox.TextColor3 = Color3.new(1,1,1)
AutoTPCheckbox.Font = Enum.Font.SourceSans
AutoTPCheckbox.TextSize = 16
AutoTPCheckbox.Text = "Авто ТП на верх: ВЫКЛ"

AutoTPCheckbox.MouseButton1Click:Connect(function()
    AutoTPEnabled = not AutoTPEnabled
    if AutoTPEnabled then
        AutoTPCheckbox.Text = "Авто ТП на верх: ВКЛ"
    else
        AutoTPCheckbox.Text = "Авто ТП на верх: ВЫКЛ"
    end
end)

-- Кнопка ручного ТП на верхний блок
local ManualTPButton = Instance.new("TextButton", Background)
ManualTPButton.Position = UDim2.new(0, 180, 0, 130)
ManualTPButton.Size = UDim2.new(0, 140, 0, 30)
ManualTPButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
ManualTPButton.TextColor3 = Color3.new(1,1,1)
ManualTPButton.Font = Enum.Font.SourceSans
ManualTPButton.TextSize = 16
ManualTPButton.Text = "Ручной ТП на верх"

ManualTPButton.MouseButton1Click:Connect(function()
    teleportUpAndSide()
end)

-- Кнопка ТП к двери (следующей)
local DoorTPButton = Instance.new("TextButton", Background)
DoorTPButton.Position = UDim2.new(0, 10, 0, 170)
DoorTPButton.Size = UDim2.new(1, -20, 0, 25)
DoorTPButton.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
DoorTPButton.TextColor3 = Color3.new(1,1,1)
DoorTPButton.Font = Enum.Font.SourceSans
DoorTPButton.TextSize = 16
DoorTPButton.Text = "ТП к двери"

DoorTPButton.MouseButton1Click:Connect(function()
    local door = workspace.CurrentRooms[LatestRoom.Value].Door.Door
    if door and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        LocalPlayer.Character.HumanoidRootPart.CFrame = door.CFrame + Vector3.new(0,3,0)
    end
end)

-- Функция телепорта вверх и вбок
function teleportUpAndSide()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local offset = Vector3.new(3, 5, 0) -- Смещение: 3 вправо, 5 вверх
        hrp.CFrame = hrp.CFrame + offset
    end
end

-- Функция поиска ближайшего шкафа
function getLocker()
    local closest = nil

    for _,v in pairs(workspace.CurrentRooms:GetDescendants()) do
        if v.Name == "Rooms_Locker" then
            if v:FindFirstChild("Door") and v:FindFirstChild("HiddenPlayer") then
                if v.HiddenPlayer.Value == nil then
                    if v.Door.Position.Y > -3 then -- Не брать шкафы под мостом
                        if closest == nil then
                            closest = v.Door
                        else
                            if (LocalPlayer.Character.HumanoidRootPart.Position - v.Door.Position).Magnitude < (closest.Position - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude then
                                closest = v.Door
                            end
                        end
                    end
                end
            end
        end
    end

    return closest
end

-- Функция получения пути (к шкафу или к двери)
function getPath()
    local part

    local entity = workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120")
    if entity and entity.Main.Position.Y > -4 then
        part = getLocker()
    else
        part = workspace.CurrentRooms[LatestRoom.Value].Door.Door
    end

    return part
end

-- Обновляем информацию о текущей комнате и счётчик
LatestRoom:GetPropertyChangedSignal("Value"):Connect(function()
    InfoText.Text = string.format("Комната: %d\nМонстр: Нет\nДверь: %s\nРасстояние: 0", math.clamp(LatestRoom.Value,1,1000), "Неизвестна")
    RoomsPassed = LatestRoom.Value
    RoomsPassedLabel.Text = "Пройдено комнат: "..RoomsPassed

    if LatestRoom.Value == 1000 then
        LocalPlayer.DevComputerMovementMode = Enum.DevComputerMovementMode.KeyboardMouse

        Folder:ClearAllChildren()

        local Sound = Instance.new("Sound")
        Sound.Parent = game.SoundService
        Sound.SoundId = "rbxassetid://4590662766"
        Sound.Volume = 3
        Sound.PlayOnRemove = true
        Sound:Destroy()

        game.StarterGui:SetCore("SendNotification", { Title = "geodude#2619"; Text = "Спасибо за использование скрипта!" })
        return
    else
        LocalPlayer.DevComputerMovementMode = Enum.DevComputerMovementMode.Scriptable
    end
end)

-- Основной цикл, обновление каждый кадр
RunService.RenderStepped:Connect(function()
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end

    LocalPlayer.Character.HumanoidRootPart.CanCollide = false
    if LocalPlayer.Character:FindFirstChild("Collision") then
        LocalPlayer.Character.Collision.CanCollide = false
        LocalPlayer.Character.Collision.Size = Vector3.new(8, LocalPlayer.Character.Collision.Size.Y, 8)
    end

    LocalPlayer.Character.Humanoid.WalkSpeed = 21

    local pathPart = getPath()
    if not pathPart then return end

    local entity = workspace:FindFirstChild("A60") or workspace:FindFirstChild("A120")
    local distToPath = (LocalPlayer.Character.HumanoidRootPart.Position - pathPart.Position).Magnitude
    local monsterName = entity and entity.Name or "Нет"
    local doorName = pathPart and pathPart.Name or "Неизвестна"

    InfoText.Text = string.format("Комната: %d\nМонстр: %s\nДверь: %s\nРасстояние: %.1f", LatestRoom.Value, monsterName, doorName, distToPath)

    -- Если монстр появился
    if entity then
        if AutoTPEnabled then
            teleportUpAndSide()
        end
    end
end)

-- Бесконечный цикл для передвижения по пути
spawn(function()
    while true do
        if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then wait(0.1) continue end

        local Destination = getPath()
        if not Destination then wait(0.1) continue end

        local path = PathfindingService:CreatePath({ WaypointSpacing = 1, AgentRadius = 0.1, AgentCanJump = false })
        path:ComputeAsync(LocalPlayer.Character.HumanoidRootPart.Position - Vector3.new(0,3,0), Destination.Position)
        local Waypoints = path:GetWaypoints()

        if path.Status ~= Enum.PathStatus.NoPath then

            Folder:ClearAllChildren()

            for _, Waypoint in pairs(Waypoints) do
                local part = Instance.new("Part")
                part.Size = Vector3.new(1,1,1)
                part.Position = Waypoint.Position
                part.Shape = Enum.PartType.Cylinder
                part.Rotation = Vector3.new(0,0,90)
                part.Material = Enum.Material.SmoothPlastic
                part.Anchored = true
                part.CanCollide = false
                part.Parent = Folder
            end

            for _, Waypoint in pairs(Waypoints) do
                if LocalPlayer.Character.HumanoidRootPart.Anchored == false then
                    LocalPlayer.Character.Humanoid:MoveTo(Waypoint.Position)
                    LocalPlayer.Character.Humanoid.MoveToFinished:Wait()
                end
            end

        end

        wait(0.1)
    end
end)
