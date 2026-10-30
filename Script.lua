--!strict
-- Skrypt Mage: DeathCount, ShopClock, Startup Webhook + Wykrywanie 0 HP, Shift, NPC, Łóżko & Kawa

-- 1. KONFIGURACJA WEBHOOKA
local DISCORD_WEBHOOK_URL = webhooka_discord

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local localPlayer = Players.LocalPlayer or Players:GetPlayers()[1]

-- Uniwersalna funkcja wysyłająca surowy JSON na Discord Webhook
local function sendRawDiscordWebhook(payloadTable: table)
	if DISCORD_WEBHOOK_URL == "Webhooka Discord" or DISCORD_WEBHOOK_URL == "" then
		warn("[MAGE LOG] Brak skonfigurowanego adresu URL Webhooka Discord!")
		return
	end

	local payload = HttpService:JSONEncode(payloadTable)

	local reqFunc = (syn and syn.request) or (http and http.request) or request or (http_request)
	
	if reqFunc then
		reqFunc({
			Url = DISCORD_WEBHOOK_URL,
			Method = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body = payload
		})
		print("[F9 PUSH] Powiadomienie wysłane na Discord!")
	else
		pcall(function()
			HttpService:PostAsync(DISCORD_WEBHOOK_URL, payload, Enum.HttpContentType.ApplicationJson)
		end)
		print("[F9 PUSH] Powiadomienie wysłane przez HttpService!")
	end
end

-- 2. WYKRYWANIE ZMIANY ATRYBUTU DeathCount NA PLAYERS
local function setupDeathCountListener()
	print("[MAGE SYSTEM] Nasłuchiwanie atrybutu DeathCount aktywne.")

	local function checkDeathCount()
		local deathCountVal = Players:GetAttribute("DeathCount")
		if deathCountVal ~= nil then
			warn(string.format("[F9 LOG] Zmiana DeathCount: %s", tostring(deathCountVal)))

			local deathCountPayload = {
				content = nil,
				embeds = {
					{
						description = string.format("Max Death Normal Patient\n%s/3", tostring(deathCountVal)),
						color = nil
					}
				},
				attachments = {}
			}

			sendRawDiscordWebhook(deathCountPayload)
		end
	end

	-- Nasłuchuj zmian atrybutu DeathCount na serwisie Players
	Players:GetAttributeChangedSignal("DeathCount"):Connect(checkDeathCount)
end

-- 3. WYKRYWANIE SKLEPU OGRANICZONEGO CZASOWO (ShopClock & ShopItemModels)
local function setupShopClockListener()
	local misc = Workspace:WaitForChild("Misc", 5)
	if not misc then return end

	local shopClock = misc:WaitForChild("ShopClock", 5)
	if not shopClock then return end

	local screen = shopClock:WaitForChild("Screen", 5)
	if not screen then return end

	local ui = screen:WaitForChild("UI", 5)
	if not ui then return end

	local label = ui:WaitForChild("Label", 5) :: TextLabel?
	if not label or (not label:IsA("TextLabel") and not label:IsA("TextBox")) then return end

	local previousText = label.Text

	local function checkShopClock()
		local currentText = label.Text

		if (previousText == "" or previousText == nil) and currentText ~= "" then
			local itemNames = {}
			local shopItemModelsFolder = misc:FindFirstChild("ShopItemModels")

			if shopItemModelsFolder then
				for _, child in ipairs(shopItemModelsFolder:GetChildren()) do
					if child:IsA("Model") then
						table.insert(itemNames, child.Name)
					end
				end
			end

			local itemListFormatted = #itemNames > 0 and table.concat(itemNames, ", ") or "Brak modeli"

			local shopPayload = {
				content = nil,
				embeds = {
					{
						description = string.format("List of items in the Limited-Time Shop: %s", itemListFormatted),
						color = nil
					}
				},
				attachments = {}
			}

			sendRawDiscordWebhook(shopPayload)
		end

		previousText = currentText
	end

	checkShopClock()
	label:GetPropertyChangedSignal("Text"):Connect(checkShopClock)
end

-- 4. WIADOMOŚĆ STARTOWA (STARTUP WEBHOOK)
local function sendStartupWebhook()
	local shiftText = "Unknown"
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if playerGui then
		local shiftGui = playerGui:FindFirstChild("Shift")
		local frame = shiftGui and shiftGui:FindFirstChild("Frame")
		local header = frame and frame:FindFirstChild("header")
		local textObj = header and header:FindFirstChild("text") :: TextLabel?
		if textObj and (textObj:IsA("TextLabel") or textObj:IsA("TextBox")) then
			shiftText = textObj.Text ~= "" and textObj.Text or "Unknown"
		end
	end

	local coffeeReadyText = "no"
	local misc = Workspace:FindFirstChild("Misc")
	local coffeeMachine = misc and misc:FindFirstChild("CoffeeMachine")
	local attachment = coffeeMachine and coffeeMachine:FindFirstChild("Attachment")
	local ui = attachment and attachment:FindFirstChild("UI")
	local statusLabel = ui and ui:FindFirstChild("status") :: TextLabel?
	if statusLabel and statusLabel:IsA("TextLabel") then
		if string.find(string.lower(statusLabel.Text), "ready") then
			coffeeReadyText = "yes"
		end
	end

	local normalList = {}
	local anomalyList = {}

	local npcsFolder = Workspace:FindFirstChild("NPCs")
	if npcsFolder then
		for _, child in ipairs(npcsFolder:GetChildren()) do
			if child:IsA("Model") and child.Name ~= "Doctor" and child.Name ~= "Barney" then
				if child:GetAttribute("Skinwalker") ~= nil then
					table.insert(anomalyList, child.Name)
				else
					table.insert(normalList, child.Name)
				end
			end
		end
	end

	local normalsFormatted = #normalList > 0 and table.concat(normalList, ", ") or "0"
	local anomaliesFormatted = #anomalyList > 0 and table.concat(anomalyList, ", ") or "0"

	local descriptionText = string.format(
		"Now Shift is ``%s`` 🗓️\n\nThe coffee is ready. = ``%s``\n\nlist of NPCs:\nNormals: ``%s`` ✅\nAnomalies: ``%s`` ⚠️",
		shiftText,
		coffeeReadyText,
		normalsFormatted,
		anomaliesFormatted
	)

	sendRawDiscordWebhook({
		content = nil,
		embeds = {
			{
				description = descriptionText,
				color = nil
			}
		},
		attachments = {}
	})
end

-- 5. WYKRYWANIE ŚMIERCI GRACZA (0 HP)
local function setupPlayerDeathListener()
	local hasSentDeathSignal = false

	local function onCharacterAdded(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
		if not humanoid then return end

		hasSentDeathSignal = false

		humanoid.HealthChanged:Connect(function(health: number)
			if health <= 0 and not hasSentDeathSignal then
				hasSentDeathSignal = true
				sendRawDiscordWebhook({
					content = nil,
					embeds = {
						{
							description = "You died ☠️",
							color = nil
						}
					},
					attachments = {}
				})
			end
		end)
	end

	if localPlayer.Character then
		task.spawn(function()
			onCharacterAdded(localPlayer.Character)
		end)
	end

	localPlayer.CharacterAdded:Connect(onCharacterAdded)
end

-- 6. WYKRYWANIE ZMIANY TEKSTU W SHIFT
local function setupShiftTextListener()
	local playerGui = localPlayer:WaitForChild("PlayerGui", 5) :: PlayerGui?
	if not playerGui then return end

	local shiftGui = playerGui:WaitForChild("Shift", 5)
	if not shiftGui then return end

	local frame = shiftGui:WaitForChild("Frame", 5)
	if not frame then return end

	local header = frame:WaitForChild("header", 5)
	if not header then return end

	local textObj = header:WaitForChild("text", 5) :: TextLabel?
	if not textObj or (not textObj:IsA("TextLabel") and not textObj:IsA("TextBox")) then return end

	local lastShiftText = textObj.Text

	local function checkShiftText()
		local currentText = textObj.Text
		if currentText ~= lastShiftText and currentText ~= "" then
			lastShiftText = currentText
			sendRawDiscordWebhook({
				content = nil,
				embeds = {
					{
						description = string.format("A new shift ``%s``  🗓️", currentText),
						color = nil
					}
				},
				attachments = {}
			})
		end
	end

	textObj:GetPropertyChangedSignal("Text"):Connect(checkShiftText)
end

-- 7. WYKRYWANIE STATUSU EKSPRESU DO KAWY
local function setupCoffeeMachineListener()
	local misc = Workspace:WaitForChild("Misc", 5)
	if not misc then return end
	
	local coffeeMachine = misc:WaitForChild("CoffeeMachine", 5)
	if not coffeeMachine then return end

	local attachment = coffeeMachine:WaitForChild("Attachment", 5)
	if not attachment then return end

	local ui = attachment:WaitForChild("UI", 5)
	if not ui then return end

	local statusLabel = ui:WaitForChild("status", 5) :: TextLabel?
	if not statusLabel or not statusLabel:IsA("TextLabel") then return end

	local hasSentCoffeeSignal = false

	local function checkCoffeeStatus()
		local text = statusLabel.Text
		if string.find(string.lower(text), "ready") then
			if not hasSentCoffeeSignal then
				hasSentCoffeeSignal = true
				sendRawDiscordWebhook({
					content = nil,
					embeds = {
						{
							description = "Coffee now is ``Ready``! ☕",
							color = nil
						}
					},
					attachments = {}
				})
			end
		else
			hasSentCoffeeSignal = false
		end
	end

	checkCoffeeStatus()
	statusLabel:GetPropertyChangedSignal("Text"):Connect(checkCoffeeStatus)
end

-- 8. PEŁNY SYSTEM MONITOROWANIA NPC
local function setupNpcAnomalyListener()
	local npcsFolder = Workspace:WaitForChild("NPCs", 5) :: Folder?
	if not npcsFolder then return end

	local function checkInBedStatus(model: Model)
		local inBedAttr = model:GetAttribute("InBed")
		if inBedAttr == true then
			local modelName = model.Name
			local roomName = tostring(model:GetAttribute("DesignatedRoom") or "Unknown Room")
			sendRawDiscordWebhook({
				content = nil,
				embeds = {
					{
						description = string.format("%s now is on ``bed`` in %s", modelName, roomName),
						color = nil
					}
				},
				attachments = {}
			})
		end
	end

	local function processNpcModel(child: Instance)
		if not child:IsA("Model") then return end
		local model = child :: Model
		local modelName = model.Name

		if model:GetAttribute("StoryForced") ~= nil then
			sendRawDiscordWebhook({
				content = nil,
				embeds = {
					{
						description = string.format("%s is here because he's a ``forced plot device``.  📜", modelName),
						color = nil
					}
				},
				attachments = {}
			})
		end

		if modelName == "Barney" then
			sendRawDiscordWebhook({
				content = nil,
				embeds = {
					{
						description = "``Barney`` came over for ``coffee``. ☕",
						color = nil
					}
				},
				attachments = {}
			})
			return
		end

		if modelName == "Doctor" then
			sendRawDiscordWebhook({
				content = nil,
				embeds = {
					{
						description = "Doctor/``End Shift``",
						color = nil
					}
				},
				attachments = {}
			})
			return
		end

		local hasSkinwalkerAttr = model:GetAttribute("Skinwalker") ~= nil

		if hasSkinwalkerAttr then
			sendRawDiscordWebhook({
				content = nil,
				embeds = {
					{
						description = string.format("``Patient`` %s is ``Anomaly``  ⚠️", modelName),
						color = nil
					}
				},
				attachments = {}
			})
		else
			sendRawDiscordWebhook({
				content = nil,
				embeds = {
					{
						description = string.format("``Patient`` %s is ``Normal``  ✅", modelName),
						color = nil
					}
				},
				attachments = {}
			})
		end

		checkInBedStatus(model)
		model:GetAttributeChangedSignal("InBed"):Connect(function()
			checkInBedStatus(model)
		end)
	end

	for _, child in ipairs(npcsFolder:GetChildren()) do
		processNpcModel(child)
	end

	npcsFolder.ChildAdded:Connect(processNpcModel)
end

-- === URUCHOMIENIE SKRYPTU ===
task.spawn(sendStartupWebhook)
task.spawn(setupDeathCountListener)
task.spawn(setupShopClockListener)
task.spawn(setupPlayerDeathListener)
task.spawn(setupShiftTextListener)
task.spawn(setupCoffeeMachineListener)
task.spawn(setupNpcAnomalyListener)
