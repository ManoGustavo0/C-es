-- Cães Retro | Interface API 2 Stable + coletor de bombons sem teleporte.
local function loadRetroBox()
	assert(type(loadstring)=="function","loadstring indisponível no executor.")
	local supported,getter=pcall(function() return game.HttpGet end)
	assert(supported and type(getter)=="function","game:HttpGet indisponível no executor.")
	local url="https://raw.githubusercontent.com/ManoGustavo0/RetroBox/main/dist/bootstrap/v2.lua"
	local source=game:HttpGet(url)
	assert(type(source)=="string" and #source>0,"O bootstrap retornou uma fonte vazia.")
	local chunk,err=loadstring(source); assert(chunk,err)
	local Library=chunk({Channel="stable"})
	assert(type(Library)=="table" and Library.APIVersion==2 and type(Library.CreateWindow)=="function","RetroBox API 2 incompatível.")
	return Library
end
local createCaesRetroUi=(function()
-- Factory incorporada ao caes.lua pelo build; não é dependência do executor.
return function(ctx)
    local Library, player, state = ctx.Library, ctx.player, ctx.state
    local RS = game:GetService("ReplicatedStorage")
    local CS = game:GetService("CollectionService")
    local window = Library:CreateWindow({
        Id = "CaesRetro-" .. game.GameId, Title = "Cães Retro",
        Subtitle = "Cães Retro · sobrevivência, combate e evento", Icon = "shield",
        Theme = "Retro98", Locale = "pt-BR", Settings = true, ShowProfile = true,
        Launcher = true, LauncherText = "UI", ToggleKey = Enum.KeyCode.RightShift,
        DestroyOnClose = false, PixelIcons = true, PixelDecorations = true,
        Tooltips = true, TooltipDelay = .2, SmoothDragging = false,
        Parent = player:WaitForChild("PlayerGui"), ConfigFolder = "RetroBox/Caes/" .. game.GameId, ConfigVersion = 1,
        CallbackExecutor = function(callback, args)
            if type(setthreadidentity) == "function" then setthreadidentity(8) end
            return callback(table.unpack(args, 1, args.n))
        end,
    })
    if typeof(window.Launcher) == "Instance" then window.Launcher.AutoLocalize = false end
    local debugState = ctx.debug()
    debugState.uiWindow = window
    window:OnDestroy(ctx.unload)
    for _, resource in pairs(ctx.resources or {}) do if resource then window:Manage(resource) end end
    local alive, controls = true, {}
    local function flag(control, key, transform)
        controls[key] = control
        window:Manage(window:GetFlagState("caes." .. key):Subscribe(function(value)
            ctx.set(key, transform and transform(value) or value)
        end, true), "Disconnect")
        return control
    end
    local function toggle(section, key, title, icon, tooltip)
        local unavailable = ctx.unavailable and ctx.unavailable[key]
        local c = section:AddToggle({Id = "caes." .. key, Title = title, Icon = icon,
            Default = state[key] == true and not unavailable, Disabled = unavailable == true,
            Tooltip = unavailable and "O módulo necessário não está disponível neste cliente." or tooltip})
        return flag(c, key)
    end
    local overview = window:CreateTab({Title = "Painel", Icon = "home", Columns = 1}):CreateSection({Title = "Rodada e personagem", Icon = "map"})
    local roundLabel = overview:AddLabel({Id = "caes.round", Title = "Rodada", Icon = "clock", Default = "Carregando..."})
    local numbers = {}
    for _, key in ipairs({"coins", "survivals", "dogs", "health", "bonbons", "collected", "gained", "attempts"}) do
        numbers[key] = window:CreateState(key == "health" and "—" or 0)
    end
    local r1 = overview:CreateRow({Gap = 10, StackAt = 440})
    r1:AddStatCard({Id = "caes.stat.coins", Title = "Moedas", Icon = "coins", State = numbers.coins, TwoWay = false, Format = "Compact"})
    r1:AddStatCard({Id = "caes.stat.survivals", Title = "Sobrevivências", Icon = "trophy", State = numbers.survivals, TwoWay = false, Format = "Raw"})
    local r2 = overview:CreateRow({Gap = 10, StackAt = 440})
    r2:AddStatCard({Id = "caes.stat.dogs", Title = "Cães vivos", Icon = "skull", State = numbers.dogs, TwoWay = false, Format = "Raw"})
    r2:AddStatCard({Id = "caes.stat.health", Title = "Saúde real", Icon = "shield", State = numbers.health, TwoWay = false, Format = "Raw"})
    local equipment = overview:AddLabel({Id = "caes.equipment", Title = "Equipamento", Icon = "backpack", Default = "Nenhum item equipado"})

    local eventTab = window:CreateTab({Title = "Evento", Icon = "gift", Columns = 1})
    local event = eventTab:CreateSection({Title = "Coletor de bombons", Icon = "gift"})
    local collection = {attempts = 0, confirmed = 0, gained = 0, available = 0, status = "Coletor desligado", errors = 0}
    debugState.bonbons = collection
    local collectorToggle = event:AddToggle({Id = "caes.autoBonbons", Title = "Auto coletar bombons", Icon = "magnet",
        Default = state.autoBonbons == true, Tooltip = "Coleta os bombons do mapa por contato informado. Não move o personagem, não altera sua velocidade e não usa teleporte.",
        Floating = {Text = "BOMBONS", MobileOnly = true, Position = Vector2.new(.04, .65)}})
    local eventStatus = event:AddLabel({Id = "caes.bonbons.status", Title = "Estado da coleta", Icon = "info", Default = collection.status})
    event:AddLabel({Id = "caes.bonbons.help", Title = "Funcionamento", Icon = "info",
        Default = "O coletor acompanha os bombons que aparecerem durante as rodadas.\nAs coletas são contadas pelo evento de confirmação do servidor.\nO script não compra nem converte moedas em bombons."})
    local b1 = event:CreateRow({Gap = 10, StackAt = 440})
    b1:AddStatCard({Id = "caes.stat.bonbons", Title = "Saldo de bombons", Icon = "wallet", State = numbers.bonbons, TwoWay = false, Format = "Raw"})
    b1:AddStatCard({Id = "caes.stat.collected", Title = "Coletas confirmadas", Icon = "success", State = numbers.collected, TwoWay = false,
        Format = "Raw", Subtitle = "Confirmações recebidas nesta execução"})
    local b2 = event:CreateRow({Gap = 10, StackAt = 440})
    b2:AddStatCard({Id = "caes.stat.gained", Title = "Bombons recebidos", Icon = "gift", State = numbers.gained, TwoWay = false, Format = "Raw"})
    b2:AddStatCard({Id = "caes.stat.attempts", Title = "Tentativas de coleta", Icon = "magnet", State = numbers.attempts, TwoWay = false,
        Format = "Raw", Subtitle = "Envio não equivale a coleta confirmada"})
    local candyModule = RS.Client:FindFirstChild("Bonbons")
    local candyConfig = candyModule and require(candyModule).Config or nil
    local tag = candyConfig and candyConfig.Tag or "Bonbon"
    local collectedAttribute = candyConfig and candyConfig.PickedAttribute or "Collected"
    local remoteFolder = RS:FindFirstChild("Remotes")
    local pickup = remoteFolder and remoteFolder:FindFirstChild("BonbonPickup")
    if pickup and pickup:IsA("RemoteEvent") then
        window:Manage(pickup.OnClientEvent:Connect(function(_, amount)
            if not alive then return end
            amount = tonumber(amount) or 1
            if amount ~= amount or amount <= 0 or amount == math.huge then return end
            collection.confirmed += 1; collection.gained += amount
        end))
    end
    local candidates, queue, retries = {}, {}, setmetatable({}, {__mode = "k"})
    local function available(part)
        return part:IsA("BasePart") and part.Parent ~= nil and part:IsDescendantOf(workspace)
            and part:GetAttribute(collectedAttribute) ~= true
    end
    local function add(part)
        if part:IsA("BasePart") and not candidates[part] then candidates[part] = true; queue[#queue + 1] = part end
    end
    for _, part in ipairs(CS:GetTagged(tag)) do add(part) end
    window:Manage(CS:GetInstanceAddedSignal(tag):Connect(add))
    window:Manage(CS:GetInstanceRemovedSignal(tag):Connect(function(part) candidates[part] = nil; retries[part] = nil end))
    local cursor = 0
    local collector = window:CreateTask({Id = "caes.bonbons.worker", Interval = .22, Start = false, OnError = "Stop", Callback = function(token)
        token:ThrowIfCancelled()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not humanoid or humanoid.Health <= 0 or not root then collection.status = "Aguardando personagem vivo"; return end
        assert(type(firetouchinterest) == "function", "O coletor requer firetouchinterest no executor.")
        local chosen
        for _ = 1, #queue do
            cursor = cursor % #queue + 1
            local part = queue[cursor]
            if candidates[part] and available(part) then
                local record = retries[part]
                if not record or os.clock() >= record.nextAt then chosen = part; break end
            end
        end
        if not chosen then collection.status = collection.available > 0 and "Aguardando novas confirmações" or "Aguardando bombons no mapa"; return end
        local record = retries[chosen] or {attempts = 0}
        record.attempts += 1
        record.nextAt = os.clock() + (record.attempts >= 3 and 12 or 2)
        retries[chosen] = record
        local touching = false
        token:Manage(function()
            if touching then pcall(firetouchinterest, root, chosen, 1); touching = false end
        end)
        token:ThrowIfCancelled()
        collection.status = "Coletando bombons · sem mover o personagem"
        collection.attempts += 1
        local sent, reason = pcall(firetouchinterest, root, chosen, 0)
        if not sent then
            collection.errors += 1; collection.status = "Tentativa adiada: " .. tostring(reason); return
        end
        touching = true
        task.wait(.04)
        token:ThrowIfCancelled()
        if touching then pcall(firetouchinterest, root, chosen, 1); touching = false end
    end})
    debugState.bonbonJob = collector
    collectorToggle:BindTask(collector)
    flag(collectorToggle, "autoBonbons")
    if type(firetouchinterest) ~= "function" or not pickup then
        collectorToggle:SetDisabled(true)
        collectorToggle:SetTooltip("Coletor indisponível: firetouchinterest ou o evento nativo BonbonPickup não foi encontrado.")
        collectorToggle:SetValue(false, true)
    end

    local fightTab = window:CreateTab({Title = "Combate", Icon = "target", Columns = 1})
    local fight = fightTab:CreateSection({Title = "Armas de fogo", Icon = "target"})
    toggle(fight, "silentAim", "Silent aim", "target", "Direciona os tiros para cães vivos dentro do FOV, usando o caminho de disparo já existente no script.")
    toggle(fight, "autoReload", "Auto recarga", "tools", "Pede a recarga nativa quando a arma equipada fica sem munição no pente e ainda tem reserva.")
    flag(fight:AddSlider({Id = "caes.fovDeg", Title = "Campo de visão do silent aim", Icon = "sliders",
        Min = 10, Max = 170, Step = 1, Default = state.fovDeg, Suffix = "°",
        Tooltip = "Abertura angular do cone de alvos. O círculo na tela acompanha o FOV da câmera."}), "fovDeg")
    local turret = fightTab:CreateSection({Title = "Torreta automática", Icon = "tools"})
    toggle(turret, "autoTurret", "Auto torreta", "target", "Mira e dispara quando você estiver montado numa torreta, respeitando o arco de giro do cano.")
    toggle(turret, "predict", "Mira preditiva da torreta", "clock", "Compensa movimento do cão e atraso de rede, preservando a correção de mira já usada pelo seu script.")
    local modes = {"Mais perto da torreta", "Menor vida", "Mais perto de você"}
    flag(turret:AddDropdown({Id = "caes.turretTarget", Title = "Prioridade do alvo", Icon = "target", Options = modes,
        Default = modes[state.turretTarget] or modes[1], Tooltip = "Define como a torreta escolhe entre cães que ela consegue alcançar."}),
        "turretTarget", function(value) return table.find(modes, value) or 1 end)
    flag(turret:AddSlider({Id = "caes.turretLeadMs", Title = "Antecipação adicional", Icon = "clock",
        Min = 0, Max = 250, Step = 5, Default = state.turretLeadMs, Suffix = " ms",
        Tooltip = "Tempo extra somado à compensação de ping da mira preditiva."}), "turretLeadMs")
    local turretStats = turret:AddLabel({Id = "caes.turret.stats", Title = "Estado da torreta", Icon = "info", Default = "Aguardando..."})

    local survival = window:CreateTab({Title = "Sobrevivência", Icon = "shield", Columns = 1})
    local protection = survival:CreateSection({Title = "Fuga e mobilidade", Icon = "shield"})
    toggle(protection, "infStamina", "Stamina infinita", "rocket", "Mantém a stamina do módulo de corrida do jogo, como na versão anterior.")
    toggle(protection, "autoMini", "Auto minigame de fuga", "keyboard", "Automatiza a luta para escapar quando um cão agarra seu personagem.")
    toggle(protection, "godMode", "Anti-arrasto e anti-ragdoll", "shield", "Ajuda a escapar e a levantar. Não é invulnerabilidade e não falsifica a vida recebida do servidor.")
    toggle(protection, "autoHopium", "Auto Hopium", "potion", "Ativa a cura quando o Hopium está equipado, tem carga e sua vida está baixa.")
    local protectionLabel = protection:AddLabel({Id = "caes.protection.stats", Title = "Proteção observada", Icon = "info", Default = "Carregando..."})
    local quality = survival:CreateSection({Title = "Qualidade de vida", Icon = "sliders"})
    toggle(quality, "skipIntro", "Pular introdução", "eye", "Aciona o próprio botão de pular a cinematográfica do jogo.")

    local fovGui = Instance.new("ScreenGui")
    fovGui.Name = "CaesRetro_Fov"; fovGui.ResetOnSpawn = false; fovGui.IgnoreGuiInset = true; fovGui.DisplayOrder = 20
    fovGui.Parent = player.PlayerGui; window:Manage(fovGui)
    local fovCircle = Instance.new("Frame")
    fovCircle.Name = "SilentAimFov"; fovCircle.AnchorPoint = Vector2.new(.5, .5); fovCircle.Position = UDim2.fromScale(.5, .5)
    fovCircle.Size = UDim2.fromOffset(130, 130); fovCircle.BackgroundTransparency = 1; fovCircle.Visible = state.silentAim; fovCircle.Parent = fovGui
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(1, 0); corner.Parent = fovCircle
    local outline = Instance.new("UIStroke"); outline.Color = Color3.fromRGB(100, 225, 245); outline.Transparency = .45; outline.Thickness = 1; outline.Parent = fovCircle
    local fovLabel = Instance.new("TextLabel")
    fovLabel.BackgroundTransparency = 1; fovLabel.Size = UDim2.fromOffset(150, 20); fovLabel.Position = UDim2.new(.5, -75, 0, -22)
    fovLabel.Text = "FOV: " .. state.fovDeg .. "°"; fovLabel.TextColor3 = outline.Color; fovLabel.TextStrokeTransparency = .2
    fovLabel.Font = Enum.Font.Code; fovLabel.TextSize = 12; fovLabel.AutoLocalize = false; fovLabel.Parent = fovCircle

    local function update()
        if not alive then return end
        local d = ctx.debug(); if not d then return end
        local round, shop, leaders = RS:FindFirstChild("Round"), player:FindFirstChild("Shop"), player:FindFirstChild("leaderstats")
        local rstats, character = player:FindFirstChild("RoundStats"), player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local status = round and round:GetAttribute("Status") or "Lobby"
        local ends = round and round:GetAttribute("EndsAt")
        local remaining = type(ends) == "number" and math.max(0, math.ceil(ends - workspace:GetServerTimeNow())) or 0
        roundLabel:SetText(string.format("%s · %s · %02d:%02d\nEspecial: %s",
            tostring(status), tostring(rstats and rstats:GetAttribute("Map") or "Lobby"), math.floor(remaining / 60), remaining % 60,
            tostring(round and round:GetAttribute("Special") or "Normal")))
        local dogs = 0; local folder = workspace:FindFirstChild("NPCs")
        if folder then for _, model in ipairs(folder:GetChildren()) do local h = model:FindFirstChildOfClass("Humanoid"); if h and h.Health > 0 then dogs += 1 end end end
        local aliveCandies, liveQueue = 0, {}
        for part in pairs(candidates) do
            if available(part) then aliveCandies += 1; liveQueue[#liveQueue + 1] = part else candidates[part] = nil; retries[part] = nil end
        end
        queue = liveQueue; cursor = 0; collection.available = aliveCandies
        local survivals = leaders and leaders:FindFirstChild("Survivals")
        Library:Batch(function()
            numbers.coins:Set(shop and shop:GetAttribute("Coins") or 0); numbers.bonbons:Set(shop and shop:GetAttribute("Bonbons") or 0)
            numbers.survivals:Set(survivals and survivals.Value or 0); numbers.dogs:Set(dogs)
            numbers.health:Set(humanoid and string.format("%.0f / %.0f", humanoid.Health, humanoid.MaxHealth) or "—")
            numbers.collected:Set(collection.confirmed); numbers.gained:Set(collection.gained); numbers.attempts:Set(collection.attempts)
        end)
        local job = collector:GetStatus()
        eventStatus:SetText(job.LastError and "Erro: " .. tostring(job.LastError)
            or (job.Requested and collection.status or "Coletor desligado") .. "\nBombons disponíveis: " .. aliveCandies)
        local tool = character and character:FindFirstChildOfClass("Tool")
        local weapon = tool and tool.Name or "Nenhum item equipado"
        if tool and type(tool:GetAttribute("Loaded")) == "number" then weapon ..= string.format(" · %.0f / %.0f munições", tool:GetAttribute("Loaded"), tool:GetAttribute("Reserve") or 0) end
        equipment:SetText(weapon .. "\nRetroBox " .. Library:GetVersion() .. " · Shift direito abre o menu")
        local t, g, s = d.turretStats or {}, d.godStats or {}, d.struggleStats or {}
        turretStats:SetText(string.format("%s · %.0f ms de ping\nMiras enviadas: %d · Eventos de tiro: %d",
            d.turret and d.turret._manning and "Montada" or "Aguardando montagem", d.ping and d.ping() * 2000 or 0, t.aimed or 0, t.shotEvents or 0))
        protectionLabel:SetText(string.format("Arrastos: %d · Apertos aceitos: %d\nQuedas reais de vida: %d · Ragdolls interrompidos: %d",
            g.grabs or 0, s.credit or 0, g.drops or 0, g.ragdollBlocks or 0))
        fovCircle.Visible = state.silentAim == true
    end
    window:CreateTask({Id = "caes.ui.telemetry", Interval = .25, Start = true, OnError = "Continue", Callback = function(token)
        token:ThrowIfCancelled(); update()
    end})
    window:Manage(function() alive = false; table.clear(candidates); table.clear(queue) end)
    local session = overview:CreateRow({Gap = 10, StackAt = 440})
    session:AddButton({Id = "caes.hide", Title = "Ocultar menu", Text = "OCULTAR", Icon = "eye",
        Tooltip = "Oculta o menu e mantém as funções ativas. Reabra com UI ou Shift direito.", Callback = function() window:Hide(); return true end})
    session:AddButton({Id = "caes.unload", Title = "Encerrar script", Text = "ENCERRAR", Icon = "close",
        Tooltip = "Desliga as tarefas, limpa a interface e restaura os hooks do script.", Callback = function() ctx.unload(); return true end})
    local api = {window = window, gui = fovGui, fovCircle = fovCircle, fovLabel = fovLabel, controls = controls, collector = collector, collection = collection}
    function api.set(key, value)
        local c = controls[key]
        if c then
            if key == "turretTarget" then value = modes[value] or modes[1] end
            c:SetValue(value)
        else ctx.set(key, value) end
    end
    function api.refresh() update() end
    function api.cleanup() if alive then alive = false; window:Destroy() end end
    function api.getSnapshot()
        return {balance = player:FindFirstChild("Shop") and player.Shop:GetAttribute("Bonbons"), collected = collection.confirmed,
            gained = collection.gained, attempts = collection.attempts, available = collection.available,
            enabled = collector:GetStatus().Requested, status = collection.status, diagnostics = window:GetDiagnostics()}
    end
    update()
    window:Notify({Title = "Cães Retro", Content = "Pronto. O coletor sem teleporte está na aba Evento.", Kind = "success", Icon = "gift", Duration = 6})
    return api
end

end)()
local function main()
	assert(game.GameId == 10765582175, "Este script é para cães/cachorros.")
	if type(setthreadidentity) == "function" then setthreadidentity(8) end
	local Library = loadRetroBox()
	local alive = true
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local LocalPlayer = Players.LocalPlayer
	local function getModule(name)
		local folder = ReplicatedStorage:FindFirstChild("Client")
		if not folder then return nil end
		local ok, mod = pcall(require, folder:FindFirstChild(name))
		if ok and type(mod) == "table" then return mod end
		return nil
	end
	local Sprint = getModule("Sprint")
	local Skill = getModule("SkillCheck")
	local GunClient = getModule("GunClient")
	-- Net (mesmo modulo que o GunClient usa) pra poder pedir reload no servidor
	local Net
	do
		local m = ReplicatedStorage:FindFirstChild("Modules")
		local ok, mod = pcall(require, m and m:FindFirstChild("Net"))
		if ok and type(mod) == "table" then Net = mod end
	end
	-- novo modulo: turret (hook da mira automatica)
	local Turret = getModule("Turret")
	local TurretRig
	do
		local m = ReplicatedStorage:FindFirstChild("Modules")
		local ok, mod = pcall(require, m and m:FindFirstChild("TurretRig"))
		if ok and type(mod) == "table" then TurretRig = mod end
	end
	-- migração da v1: desativa handlers órfãos (sem unload) e remove painel antigo
	local legacy = rawget(_G, "__CGM_DEBUG")
	local savedState, savedStats = {}, {}
	if legacy then
		for key,value in pairs(legacy.state or {}) do savedState[key]=value end
		for _,name in ipairs({"aimStats","reloadStats","turretStats","godStats","struggleStats","introStats"}) do
			savedStats[name]={}
			for key,value in pairs(legacy[name] or {}) do
				if type(value)=="number" and key~="lastHp" then savedStats[name][key]=value end
			end
		end
	end
	if legacy then
		if type(legacy.unload) == "function" then
			local needsLegacyWait = not (legacy.ui and legacy.ui.window)
			legacy.unload()
			if needsLegacyWait then task.wait(2.1) end
		elseif legacy.state then
			legacy.state.infStamina = false
			legacy.state.autoMini = false
		end
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local oldGui = pg and pg:FindFirstChild("CacMenu")
		if oldGui then oldGui:Destroy() end
	end
	_G.__CGM_LOADED = true
	-- turretTarget: 1 = mais perto da torreta, 2 = menor vida, 3 = mais perto de voce
	local state = { infStamina = true, autoMini = true, silentAim = false, autoReload = true, autoTurret = true, autoHopium = true, predict = true, godMode = true, skipIntro = true, turretTarget = 1, fovDeg = 90, turretLeadMs = 60, autoBonbons = true }
	for key,value in pairs(savedState) do
		if type(state[key]) == type(value) then state[key]=value end
	end
	state.fovDeg = math.clamp(tonumber(state.fovDeg) or 90,10,170)
	state.turretTarget = math.clamp(math.floor(tonumber(state.turretTarget) or 1),1,3)
	state.turretLeadMs = math.clamp(tonumber(state.turretLeadMs) or 60,0,250)
	-- ===== Silent aim: redireciona balas para cães dentro do circulo de FOV =====
	local oldNearest = GunClient and GunClient._nearestTarget
	local hookOk = type(oldNearest) == "function"
	local oldFire = GunClient and GunClient._fire
	local fireOk = type(oldFire) == "function"
	local aimStats = { calls = 0, hits = 0, lastTarget = nil }
	local aimParams = RaycastParams.new()
	aimParams.FilterType = Enum.RaycastFilterType.Include
	-- raio do FOV em px, convertendo graus -> viewport (mesma formula do aimbot_test)
	local function fovRadiusPx(cam)
		local vp = cam.ViewportSize
		return math.tan(math.rad(state.fovDeg) * 0.5)
			/ math.tan(math.rad(cam.FieldOfView) * 0.5) * (vp.Y * 0.5)
	end	-- melhor alvo: cao vivo em NPCs projetado dentro do circulo de FOV, com LOS da arma
	local function bestDogInFov(self)
		local cam = workspace.CurrentCamera
		local folder = workspace:FindFirstChild("NPCs")
		if not cam or not folder then return nil end
		local filter = { folder }
		for _, name in ipairs({ "CurrentMap", "Lobby" }) do
			local f = workspace:FindFirstChild(name)
			if f then table.insert(filter, f) end
		end
		aimParams.FilterDescendantsInstances = filter
		local muzzle
		if self and self._handle then
			local m = self._handle:FindFirstChild("Muzzle")
			if m then muzzle = m.WorldPosition end
		end
		muzzle = muzzle or cam.CFrame.Position
		local best, bestScore
		for _, model in ipairs(folder:GetChildren()) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			local part = model:FindFirstChild("Torso") or model:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and part and part:IsA("BasePart") then
				-- projecao manual (conica): -Z na frente; WorldToViewportPoint esta quebrado neste ambiente
				local rel = cam.CFrame:PointToObjectSpace(part.Position)
				local depth = -rel.Z
				if depth > 0.01 then
					local score = (rel.X * rel.X + rel.Y * rel.Y) / (depth * depth) -- tan^2 do angulo
					local tanHalf = math.tan(math.rad(state.fovDeg) * 0.5)
					if score <= tanHalf * tanHalf and (not bestScore or score < bestScore) then
						local hit = workspace:Raycast(muzzle, part.Position - muzzle, aimParams)
						if not hit or hit.Instance:IsDescendantOf(folder) then
							best, bestScore = part.Position, score
						end
					end
				end
			end
		end
		return best
	end
	if hookOk then
		GunClient._nearestTarget = function(self, ...)
			if not state.silentAim then
				return oldNearest(self, ...)
			end
			-- caminho mobile (BindAction): alvo no FOV vence; erro nunca quebra o disparo
			local ok, pos = pcall(bestDogInFov, self)
			if ok and pos then return pos end
			return oldNearest(self, ...)
		end
	end	-- PONTO PRINCIPAL: no PC, Tool.Activated chama _fire() SEM target (usa mouse.Hit).
	-- Interceptando aqui, todo tiro (clique ou auto) recebe o alvo no FOV.
	if fireOk then
		GunClient._fire = function(self, tool, target)
			if state.silentAim then
				aimStats.calls = aimStats.calls + 1
				local ok, pos = pcall(bestDogInFov, self)
				if ok and pos then
					target = pos
					aimStats.hits = aimStats.hits + 1
					aimStats.lastTarget = pos
				end
			end
			return oldFire(self, tool, target)
		end
	end
	-- ===== fim silent aim =====
	-- ===== auto Hopium (cura quando o item esta equipado) =====
	local hopiumState = { active = false, tool = nil, heals = 0 }
	local function findHopiumTool()
		local char = LocalPlayer.Character
		if not char then return nil end
		for _, c in ipairs(char:GetChildren()) do
			if c:IsA("Tool") and c.Name:lower():gsub("%s", "") == "hopium" then
				return c
			end
		end
		return nil
	end
	local function releaseHopium()
		if hopiumState.active and hopiumState.tool then
			pcall(function()
				hopiumState.tool:Deactivate()
			end)
		end
		hopiumState.active = false
		hopiumState.tool = nil
	end
	local function tryAutoHopium()
		if not state.autoHopium then
			releaseHopium()
			return
		end
		local char = LocalPlayer.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local tool = findHopiumTool()
		if not hum or not tool then
			releaseHopium()
			return
		end
		local charge = tool:GetAttribute("Charge") or 0
		local want = hum.Health > 0 and hum.Health < hum.MaxHealth * 0.8 and charge > 1
		if want and not hopiumState.active then
			hopiumState.active = true
			hopiumState.tool = tool
			hopiumState.heals = hopiumState.heals + 1
			pcall(function()
				tool:Activate()
			end)
		elseif (not want) and hopiumState.active then
			releaseHopium()
		end
	end
	-- ===== fim auto Hopium =====
	-- ===== auto turret (quando montado numa torreta) =====
	local turretOk = type(Turret) == "table" and type(TurretRig) == "table"
	local turretStats = { aimed = 0, fired = 0, seen = 0, blocked = 0, shots = 0, hits = 0, lastMiss = 0, avgMiss = 0, shotEvents = 0, calls = 0 }
	local turretFiring = false
	local turretLastAim = 0
	local turretLastTarget
	-- ===== predict: onde o cao ESTARA quando o server processar o tiro =====
	-- o aim so chega ao server com atraso (ping/2 + tique do server + nosso
	-- SendRate de 20/s): nesse intervalo um cao andando a ~18 studs/s desloca
	-- ~1,2 studs. O predict soma esse deslocamento na mira.
	-- ping real medido no client, atualizado a cada 2s (meio-ida em segundos)
	local pingSec = 0.035
	task.spawn(function()
		local okStats, stats = pcall(function() return game:GetService("Stats") end)
		if not okStats or not stats then return end
		while turretOk and alive do
			local ok, ms = pcall(function()
				return stats.Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
			if ok and type(ms) == "number" and ms > 0 and ms < 2000 then
				pingSec = (ms / 1000) * 0.5
			end
			task.wait(2)
		end
	end)
	-- velocidade media do cao: amostra a cada >=0.08s porque o server replica
	-- posicao em pulsos (dif de 1 frame ficaria ruidosa)
	local dogTrack = {}
	local function dogVelocity(model, part, now)
		local pos = part.Position
		local rec = dogTrack[model]
		if not rec then
			dogTrack[model] = { t = now, pos = pos, vel = Vector3.zero }
			return Vector3.zero
		end
		local dt = now - rec.t
		if dt >= 0.08 then
			local nv = (pos - rec.pos) / dt
			if nv.Magnitude > 40 then nv = nv.Unit * 40 end
			rec.vel = if rec.vel.Magnitude > 0 then rec.vel:Lerp(nv, 0.55) else nv
			rec.t = now
			rec.pos = pos
		end
		return rec.vel
	end
	-- aim = pivot * RotY(yaw) * RotX(pitch); cano = (-cos p sin yaw, sin p, -cos p cos yaw)
	local function turretYawPitch(rig, origin, worldPos)
		local dir = worldPos - origin
		if dir.Magnitude < 0.01 then return nil end
		local localDir = rig.pivot:VectorToObjectSpace(dir.Unit)
		local pitch = math.deg(math.asin(math.clamp(localDir.Y, -1, 1)))
		local yaw = math.deg(math.atan2(-localDir.X, -localDir.Z))
		return yaw, pitch
	end
	-- A bala sai da boca do cano (MuzzleAttachment), que fica ACIMA do pivot.
	-- Mirar a partir do pivot fazia o projetil passar por cima do cao, entao
	-- resolvemos yaw/pitch iterativamente a partir da boca real do cano.
	local function turretAimAt(rig, worldPos)
		local yaw, pitch = turretYawPitch(rig, rig.pivot.Position, worldPos)
		if not yaw then return nil end
		for _ = 1, 5 do
			local ok, muzzleCF = pcall(TurretRig.muzzle, rig, yaw, pitch)
			if not ok or not muzzleCF then break end
			local ny, np = turretYawPitch(rig, muzzleCF.Position, worldPos)
			if not ny then return nil end
			local converged = math.abs(ny - yaw) < 1e-2 and math.abs(np - pitch) < 1e-2
			yaw, pitch = ny, np
			if converged then break end
		end
		return yaw, pitch
	end
	-- a torreta tem limite de giro: alvo fora de YawLimit/PitchUp/PitchDown nao da pra mirar
	local function turretAimable(rig, yaw, pitch)
		local margin = 0.5
		if math.abs(yaw) > rig.yawLimit - margin then return false end
		if pitch < -rig.pitchDown + margin or pitch > rig.pitchUp - margin then return false end
		return true
	end
	-- distancia do cao ate VOCE (modo "perto de voce": o que vai te morder)
	local function turretDistToPlayer(part)
		local char = LocalPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then return math.huge end
		return (part.Position - root.Position).Magnitude
	end
	-- pontuacao do alvo: menor pontuacao ganha. Modo escolhido no menu.
	local function turretScore(mode, distTurret, hp, distPlayer)
		if mode == 2 then return hp end
		if mode == 3 then return distPlayer end
		return distTurret
	end
	local function bestTurretTarget(rig)
		local folder = workspace:FindFirstChild("NPCs")
		if not folder or not rig or not rig.pivot then return nil end
		local origin = rig.pivot.Position
		local now = os.clock()
		local lead = 0
		if state.predict then
			lead = (state.turretLeadMs / 1000) + pingSec
		end
		local best, bestD, bestYaw, bestPitch
		turretStats.calls = turretStats.calls + 1
		if turretStats.calls % 600 == 0 then
			-- poda o historico de caoes que sairam do mapa/round
			for m2 in pairs(dogTrack) do
				if not m2:IsDescendantOf(workspace) then
					dogTrack[m2] = nil
				end
			end
		end
		for _, m in ipairs(folder:GetChildren()) do
			local hum = m:FindFirstChildOfClass("Humanoid")
			local part = m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
			if hum and hum.Health > 0 and part and part:IsA("BasePart") then
				turretStats.seen = turretStats.seen + 1
				-- alvo previsto: corpo atual + velocidade * tempo de reacao do server
				local aimPos = part.Position
				if lead > 0 then
					local vel = dogVelocity(m, part, now)
					if vel.Magnitude > 0.5 then
						aimPos = aimPos + vel * lead
					end
				end
				local yaw, pitch = turretAimAt(rig, aimPos)
				if yaw and aimPos ~= part.Position and not turretAimable(rig, yaw, pitch) then
					-- previsto fora do arco de giro: volta a mirar no corpo atual
					yaw, pitch = turretAimAt(rig, part.Position)
				end
				if yaw and turretAimable(rig, yaw, pitch) then
					local d = (part.Position - origin).Magnitude
					-- bestD guarda a PONTUACAO do alvo (nao a distancia): assim a
					-- prioridade do menu decide quem a torreta mira
					local score = turretScore(state.turretTarget, d, hum.Health, turretDistToPlayer(part))
					if not bestD or score < bestD then
						best, bestD, bestYaw, bestPitch = part.Position, score, yaw, pitch
					end
				else
					turretStats.blocked = turretStats.blocked + 1
				end
			end
		end
		return best, bestYaw, bestPitch
	end
	local function stopTurretFire()
		if turretFiring then
			turretFiring = false
			pcall(function()
				Net:Fire("TurretFire", false)
			end)
		end
	end
	local function tryAutoTurret()
		if not turretOk then return end
		local rig = Turret._manning
		if not rig or not state.autoTurret then
			stopTurretFire()
			return
		end
		-- yaw/pitch ja vem do cano e dentro dos limites de giro da torreta
		local target, yaw, pitch = bestTurretTarget(rig)
		if not target or not yaw then
			turretLastTarget = nil
			stopTurretFire()
			return
		end
		yaw, pitch = TurretRig.clamp(rig, yaw, pitch)
		Turret._yaw, Turret._pitch = yaw, pitch
		local now = os.clock()
		if target ~= turretLastTarget then
			-- trocou de alvo: manda o aim na hora em vez de esperar o proximo tique
			turretLastTarget = target
			turretLastAim = 0
		end
		if now - turretLastAim >= 1 / 20 then
			turretLastAim = now
			turretStats.aimed = turretStats.aimed + 1
			pcall(function()
				Net:Fire("TurretAim", yaw, pitch)
			end)
		end
		if not turretFiring then
			turretFiring = true
			turretStats.fired = turretStats.fired + 1
			pcall(function()
				Net:Fire("TurretFire", true)
			end)
		end
	end
	-- telemetria do tiro: o server devolve (origem, ponto de impacto, rig) no
	-- TurretShot; da pra medir a distancia entre o impacto e o cao mais proximo
	-- (miss real) — é assim que comparamos predict ligado vs desligado.
	local shotConn, godCharConn
	do
		local ok, conn = pcall(function()
			return Net:Listen("TurretShot", function(origin, hitPos, rig)
				turretStats.shotEvents = turretStats.shotEvents + 1
				local manning = Turret._manning
				if not manning or typeof(hitPos) ~= "Vector3"
					or (rig ~= manning and rig ~= manning.model) then
					return
				end
				local folder = workspace:FindFirstChild("NPCs")
				if not folder then return end
				local near
				for _, m in ipairs(folder:GetChildren()) do
					local hum = m:FindFirstChildOfClass("Humanoid")
					local part = m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart")
					if hum and hum.Health > 0 and part and part:IsA("BasePart") then
						local d = (part.Position - hitPos).Magnitude
						if not near or d < near then near = d end
					end
				end
				if near then
					turretStats.shots = turretStats.shots + 1
					turretStats.lastMiss = near
					local n = math.min(turretStats.shots, 20)
					turretStats.avgMiss = turretStats.avgMiss + (near - turretStats.avgMiss) / n
					if near <= 1.5 then
						turretStats.hits = turretStats.hits + 1
					end
				end
			end)
		end)
		if ok then shotConn = conn end
	end
	-- ===== fim auto turret =====
	-- ===== god mode v7: sem vida; anti-arrasto = acabar com o arrasto =====
	-- Tudo decidido por medicao ao vivo, nao por achismo:
	--   * VIDA: nao mexer. A v5 travava Health = MaxHealth a cada frame; isso
	--     nunca impediu nada (o dano e do SERVIDOR — em ataque real contei 30
	--     quedas de vida com blocked=0, tudo por replicacao) e so mascarava a
	--     barra. Agora NENHUMA linha escreve em Health e os hooks
	--     __namecall/__newindex (que existiam so pra vida) sairam junto.
	--     "mord" no painel e leitura pura: com o escudo ligado a barra mostra
	--     a vida REAL do servidor (testado: 8/100 continuou 8/100).
	--   * ARRASTO — o que eu medi quando um cao me pega:
	--       - o Humanoid fica em PlatformStanding (PlatformStand=true) e a
	--         velocidade da raiz e ~0.1 studs/s: quem carrega e o SERVIDOR, por
	--         posicao;
	--       - NAO existe weld/constraint entre voce e o cao (no personagem so
	--         os Motor6D do proprio rig; no cao, os BallSocket dele): nao ha o
	--         que destruir;
	--       - Humanoid:Move medido = 0,00 studs em 0,5s (estado Running,
	--         WalkSpeed 16) -> neste cliente o Move e inerte;
	--       - o ambiente nao expoe keypress/keyrelease/VirtualInputManager,
	--         entao o script tambem nao consegue "andar" por input.
	--     Conclusao honesta: sem escrever posicao/velocidade (o teleporte que
	--     te deu kick, e que voce proibiu), o cliente NAO recusa o
	--     carregamento. O que ele pode:
	--       a) nao ficar ragdoll: PlatformStand=false + GettingUp so quando o
	--          estado esta em PlatformStanding, inclusive no arrasto; AutoRotate
	--          (a trava de frente do tiro, do GunClient) nunca e tocado;
	--       b) acabar com o arrasto de verdade — ganhando o minigame (agora
	--          OP: zona = barra inteira, ~8 apertos/s) em ~1s em vez de ~5s;
	--       c) deixar o atributo Dragged INTACTO, que e o que mantem o minigame
	--          do jogo vivo (era ele que a v4 apagava e quebrava a barra);
	--       d) quando o arrasto acaba, voce esta livre e anda normalmente.
	-- Nada aqui escreve CFrame, PivotTo, AssemblyLinearVelocity, Health ou
	-- atributo do jogo (conferido por contagem no arquivo).
	local godStats = { deaths = 0, drops = 0, ragdollBlocks = 0, scans = 0, grabs = 0,
		lastDrop = 0, lastDropHp = 0, lastDropDist = -1, lastErr = nil }
	local godDogs = {}
	local godDogsNext = 0
	local godConns = {}
	-- a raiz do personagem pode sumir por um instante (respawn/rebuild do rig)
	local function godRoot(char)
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		return (hum and hum.RootPart) or (char and char.PrimaryPart)
			or (char and char:FindFirstChild("HumanoidRootPart")) or (char and char:FindFirstChild("Torso"))
	end
	-- so leitura: lista os caes vivos (contexto da mordida / direcao do cao)
	local function godRefreshDogs(now, force)
		if not force and now < godDogsNext then return end
		godDogsNext = now + 0.2
		table.clear(godDogs)
		local folder = workspace:FindFirstChild("NPCs")
		if not folder then return end
		for _, m in ipairs(folder:GetChildren()) do
			local hum = m:FindFirstChildOfClass("Humanoid")
			local part = m:FindFirstChild("Torso") or m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
			if hum and hum.Health > 0 and part and part:IsA("BasePart") then
				godDogs[#godDogs + 1] = { model = m, part = part }
			end
		end
	end
	local function godNearest(from)
		local best, bestD
		for _, e in ipairs(godDogs) do
			local d = (e.part.Position - from).Magnitude
			if not bestD or d < bestD then
				best, bestD = e, d
			end
		end
		return best, bestD
	end
	-- anti-ragdoll: SO mexe em PlatformStand, que e o estado "caido/agarrado"
	-- do jogo (Client_RagdollController poe PlatformStand = true).
	-- NUNCA mexe em AutoRotate: o GunClient usa AutoRotate = false pra travar a

	-- (se quiser um painel de estado do movimento, insere aqui)	-- sua frente na direcao do tiro (_faceTowards) e devolve true quando voce
	-- para de atirar. A versao anterior tratava "AutoRotate = false" como
	-- caido e resetava a cada frame: MEDIDO, 27 conflitos por segundo com a
	-- trava do tiro, e cada reset chamava ChangeState(GettingUp) — era isso
	-- que jogava o personagem pra cima e pra baixo e cancelava o pulo.
	local function godUnfreeze(hum)
		hum.PlatformStand = false
		local st = hum:GetState()
		if hum.Health > 0 and (st == Enum.HumanoidStateType.PlatformStanding
			or st == Enum.HumanoidStateType.Physics) then
			pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
		end
	end
	-- leitura: toda queda de vida abaixo do maximo veio do servidor; serve de
	-- alarme ("mord") e de contexto (a que distancia o cao estava)
	local function godWatch(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if not alive or not hum or not hum:IsA("Humanoid") then return end
		godStats.lastHp = hum.Health
		table.insert(godConns, hum.HealthChanged:Connect(function(hp)
			if hp < godStats.lastHp then
				godStats.drops = godStats.drops + 1
				godStats.lastDrop = os.clock()
				godStats.lastDropHp = hp
				local root = godRoot(char)
				local _, d = root and godNearest(root.Position)
				godStats.lastDropDist = d or -1
			end
			godStats.lastHp = hp
		end))
		table.insert(godConns, hum.Died:Connect(function()
			godStats.deaths = godStats.deaths + 1
		end))
	end
	local function godAttach(char)
		if not char then return end
		task.spawn(godWatch, char)
	end
	if LocalPlayer.Character then godAttach(LocalPlayer.Character) end
	godCharConn = LocalPlayer.CharacterAdded:Connect(godAttach)
	local godWasDragged = false
	-- chamado a cada frame pelo RenderStepped
	local function godTick(now)
		local char = LocalPlayer.Character
		if not char or not char.Parent then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		if not state.godMode then return end
		godStats.scans = godStats.scans + 1
		local dragged = char:GetAttribute("Dragged") == true
		if dragged and not godWasDragged then
			godWasDragged = true
			godStats.grabs = godStats.grabs + 1
		elseif not dragged and godWasDragged then
			godWasDragged = false
		end
		-- anti-ragdoll: so quando o jogo realmente te poem em PlatformStand
		-- (durante o arrasto tambem) — AutoRotate e do jogo, nao se toca
		if hum.Health > 0 and hum.PlatformStand then
			godStats.ragdollBlocks = godStats.ragdollBlocks + 1
			godUnfreeze(hum)
		end
		-- telemetria do arrasto: guarda a distancia do cao no pior momento
		if dragged then
			local root = hum.RootPart
			if root then
				godRefreshDogs(now)
				local _, d = godNearest(root.Position)
				if d and d > 0 then
					godStats.lastGrabDist = d
				end
			end
		end
	end
	local function godCleanup()
		for _, c in ipairs(godConns) do
			pcall(function() c:Disconnect() end)
		end
		table.clear(godConns)
		if godCharConn then
			pcall(function() godCharConn:Disconnect() end)
			godCharConn = nil
		end
	end
	-- ===== fim god mode =====
	-- ===== Auto reload: recarrega somente quando o Loaded chegar a 0 =====
	-- Nao altera munição: so pede o RifleReload (o mesmo da tecla R) e o
	-- servidor entrega um pente novo vindo da reserva.
	local reloadOk = type(Net) == "table"
	local reloadStats = { reloads = 0 }
	local lastReloadReq = 0
	local function tryAutoReload()
		if not Net or not state.autoReload then return end
		local char = LocalPlayer.Character
		local tool = char and char:FindFirstChildOfClass("Tool")
		if not tool then return end
		if tool:GetAttribute("Reloading") == true then return end
		local loaded = tool:GetAttribute("Loaded")
		if type(loaded) ~= "number" or loaded > 0 then return end
		local reserve = tool:GetAttribute("Reserve")
		if type(reserve) == "number" and reserve <= 0 then return end
		local now = os.clock()
		if now - lastReloadReq < 1.5 then return end
		lastReloadReq = now
		reloadStats.reloads = reloadStats.reloads + 1
		pcall(function()
			Net:Fire("RifleReload")
		end)
	end
-- ===== fim auto reload =====
	local gui, fovCircle, fovLabel, lastFovText, godLabel, lastGodText, uiCleanup
	local renderConn, keyConn, dragConn, clampConn
	-- ===== skip intro: dispara o proprio botao "Skip" do jogo =====
	-- O intro do jogo cria um ScreenGui chamado "Intro" com um botao "Skip".
	-- O clique nesse botao faz t_7.skip = true, o que aborta a cinematografica
	-- (hold/shot checam skip a cada RenderStepped) e devolve a camera. Aqui eu
	-- disparo o MESMO sinal Activated com firesignal — mesmo caminho de quem
	-- clica; se firesignal nao existir, chamo o callback via getconnections.
	-- Nenhum remote inventado: quem avisa o servidor (Track:FireServer
	-- "IntroDone") continua sendo o proprio modulo do jogo.
	local introStats = { skips = 0, lastErr = nil }
	local introSkipFeito
	local function trySkipIntro()
		if not state.skipIntro then return end
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local intro = pg and pg:FindFirstChild("Intro")
		if not intro then
			introSkipFeito = nil
			return
		end
		local btn = intro:FindFirstChild("Skip", true)
		if not btn or btn == introSkipFeito then return end
		introSkipFeito = btn
		local ok, err = pcall(function()
			if type(firesignal) == "function" then
				firesignal(btn.Activated)
				return
			end
			if type(getconnections) == "function" then
				for _, c in ipairs(getconnections(btn.Activated)) do
					if c.Function then
						pcall(c.Function, c)
					end
				end
			end
		end)
		if ok then
			introStats.skips = introStats.skips + 1
		else
			introStats.lastErr = tostring(err)
		end
	end
	-- ===== fim skip intro =====
	-- ===== struggle OP: joga o minigame do jogo melhor que um humano =====
	-- Como o minigame funciona (lido do Client_SkillCheck do jogo):
	--   * o atributo Dragged liga a barra (_active/_gui);
	--   * o ponteiro varre 0..1 ida e volta (SweepTime 1.1s);
	--   * a zona verde e [zoneStart, zoneStart + ZoneWidth] e e sorteada no
	--     CLIENTE (_reroll usa math.random local) — o servidor NAO conhece a
	--     zona, ele so recebe o FireServer do _press e conta o DragProgress;
	--   * _press() so manda o remote quando o ponteiro esta dentro da zona.
	-- Entao o "OP" honesto e mexer no que o cliente manda:
	--   1) ZoneWidth = 1 e ZoneMargin = 0 -> a zona passa a ser a BARRA INTEIRA
	--      e qualquer aperto acerta (era 0.18 = 18% da barra);
	--   2) a barra vai pra cima do botao onde se aperta (o SPACE que o proprio
	--      jogo desenha no centro da tela), entao o "local do clique" fica
	--      sempre visivel em cima do botao (barra verde inteira);
	--   3) o aperto sai com cooldown 0.08-0.17s sorteado (6-8 apertos por
	--      segundo, o ritmo de um humano batendo no espaco rapido) — sem
	--      metronomo e sem flood de remote.
	-- Telemetria no painel: "hits" = apertos enviados; se o servidor recusar
	-- algum, o DragProgress nao sobe e o "credit" (debug) fica pra tras.
	local struggleStats = { hits = 0, credit = 0, lastPress = 0, lastErr = nil,
		cooldown = 0.1, aplicado = false, lastProgress = 0 }
	local miniOp = function()
		local sk = Skill
		if not sk then return false end
		local cfg = sk.Config
		if cfg then
			cfg.ZoneWidth = 1
			cfg.ZoneMargin = 0
		end
		local track = sk._track
		if track then
			pcall(function()
				track.AnchorPoint = Vector2.new(0.5, 0.5)
				track.Position = UDim2.fromScale(0.5, 0.42)
			end)
		end
		return true
	end
	local function tryStruggle()
		if not (state.autoMini or state.godMode) then return end
		local sk = Skill
		if not sk or not sk._active then
			struggleStats.aplicado = false
			return
		end
		if not struggleStats.aplicado then
			struggleStats.aplicado = miniOp()
		end
		-- leitura: DragProgress so sobe quando o servidor aceita o aperto
		local char = LocalPlayer.Character
		local prog = char and char:GetAttribute("DragProgress")
		if type(prog) == "number" then
			if prog > struggleStats.lastProgress then
				struggleStats.credit = struggleStats.credit + 1
			end
			struggleStats.lastProgress = prog
		end
		local agora = os.clock()
		if agora - struggleStats.lastPress < struggleStats.cooldown then return end
		struggleStats.lastPress = agora
		struggleStats.cooldown = 0.08 + math.random() * 0.09
		local ok, err = pcall(function() sk:_press() end)
		if ok then
			struggleStats.hits = struggleStats.hits + 1
		else
			struggleStats.lastErr = tostring(err)
		end
	end
	-- ===== fim struggle =====
	renderConn = RunService.RenderStepped:Connect(function()
		tryAutoReload()
		tryAutoHopium()
		tryAutoTurret()
		-- god mode: anti-arrasto + anti-ragdoll (nao escreve nada na vida)
		-- um erro aqui NAO pode derrubar o loop inteiro (era o que matava o
		-- auto minigame junto quando o god mode ligava): fica registrado
		local gok, gerr = pcall(godTick, os.clock())
		if not gok then godStats.lastErr = tostring(gerr) end
		if Sprint and state.infStamina then
			Sprint._stamina = Sprint.Config.Max
			Sprint._spent = false
		end
		tryStruggle()
		trySkipIntro()
		if fovLabel then
			local txt = "FOV: " .. state.fovDeg .. "°"
			if txt ~= lastFovText then
				fovLabel.Text = txt
				lastFovText = txt
			end
		end
		if godLabel then
			local txt = string.format("god: %d arr • %d hits • %d mord",
				godStats.grabs, struggleStats.hits, godStats.drops)
			if struggleStats.lastErr or godStats.lastErr then
				txt = txt .. " • ERRO"
			end
			if txt ~= lastGodText then
				godLabel.Text = txt
				lastGodText = txt
			end
		end
		if fovCircle and fovCircle.Visible then
			local cam = workspace.CurrentCamera
			if cam then
				local d = math.clamp(fovRadiusPx(cam) * 2, 4, math.max(cam.ViewportSize.X, cam.ViewportSize.Y) * 2)
				fovCircle.Size = UDim2.fromOffset(d, d)
			end
		end
	end)
	local unloading = false
	local function unload()
		if unloading then return end
		unloading=true; alive=false
		local owner = _G.__CGM_DEBUG
		if not uiCleanup and owner and owner.uiWindow then owner.uiWindow:Destroy() end
		if uiCleanup then uiCleanup(); uiCleanup=nil end
		if renderConn then renderConn:Disconnect() renderConn = nil end
		if keyConn then keyConn:Disconnect() keyConn = nil end
		if dragConn then dragConn:Disconnect() dragConn = nil end
		if clampConn then clampConn:Disconnect() clampConn = nil end
		if hookOk and GunClient and GunClient._nearestTarget ~= oldNearest then
			GunClient._nearestTarget = oldNearest
		end
		if fireOk and GunClient and GunClient._fire ~= oldFire then
			GunClient._fire = oldFire
		end
		stopTurretFire()
		releaseHopium()
		state.godMode = false
		godCleanup()
		if shotConn then pcall(function() shotConn:Disconnect() end) shotConn = nil end
		if godCharConn then pcall(function() godCharConn:Disconnect() end) godCharConn = nil end
		if gui then gui:Destroy() gui = nil end
		_G.__CGM_LOADED = false
		_G.__CGM_DEBUG = nil
	end
	-- modos de prioridade de alvo da torreta (o menu cicla entre eles e a
	-- telemetria do debug le daqui)
	local turretModes = { "mais perto", "menor vida", "perto de voce" }
	_G.__CGM_DEBUG = {
		state = state,
		set = function(key, value)
			state[key] = value
			if key == "silentAim" and fovCircle then
				fovCircle.Visible = value and true or false
			end
		end,
		sprint = Sprint,
		skill = Skill,
		gunClient = GunClient,
		reloadHooked = reloadOk,
		reloadStats = reloadStats,
		hooked = hookOk and fireOk,
		hookedNearest = hookOk,
		hookedFire = fireOk,
		aimStats = aimStats,
		turret = Turret,
		turretRig = TurretRig,
		turretAimAt = turretAimAt,
		turretStats = turretStats,
		turretFiring = function() return turretFiring end,
		ping = function() return pingSec end,
		godStats = godStats,
		godDogs = function()
			return #godDogs
		end,
		godNearest = function()
			local char = LocalPlayer.Character
			local root = char and godRoot(char)
			if not root then return -1 end
			godRefreshDogs(0, true)
			local _, d = godNearest(root.Position)
			return d or -1
		end,
		godDragged = function()
			local c = LocalPlayer.Character
			return c and c:GetAttribute("Dragged")
		end,
		godProgress = function()
			local c = LocalPlayer.Character
			return c and c:GetAttribute("DragProgress")
		end,
		godReset = function()
			for k, v in pairs(godStats) do
				if type(v) == "number" then godStats[k] = 0 end
			end
		end,
		godHooks = function()
			return "sem hooks (v6: vida intocada)"
		end,
		struggleStats = struggleStats,
		miniOp = miniOp,
		turretScore = turretScore,
		turretModes = turretModes,
		trySkipIntro = trySkipIntro,
		introStats = introStats,
		godVida = function()
			local c = LocalPlayer.Character
			local h = c and c:FindFirstChildOfClass("Humanoid")
			return h and h.Health or -1
		end,
		hopium = hopiumState,
		findHopiumTool = findHopiumTool,
		fovRadiusPx = fovRadiusPx,
		bestDogInFov = function()
			return bestDogInFov(GunClient)
		end,
		unload = unload,
	}

	for name,values in pairs(savedStats) do
		local target = _G.__CGM_DEBUG[name]
		if target then for key,value in pairs(values) do target[key]=value end end
	end
	-- CAES_RETROBOX_API2
	local backendSet = _G.__CGM_DEBUG.set
	local view = createCaesRetroUi({
		Library=Library, player=LocalPlayer, state=state,
		set=backendSet,
		debug=function() return _G.__CGM_DEBUG end,
		unload=unload,
		resources={render=renderConn,shots=shotConn,character=godCharConn},
		unavailable={
			infStamina=not Sprint, autoMini=not Skill,
			silentAim=not (hookOk and fireOk), autoReload=not reloadOk,
			autoTurret=not turretOk, predict=not turretOk,
		},
	})
	gui=view.gui; fovCircle=view.fovCircle; fovLabel=view.fovLabel
	lastFovText=fovLabel.Text
	uiCleanup=view.cleanup
	_G.__CGM_DEBUG.ui=view
	_G.__CGM_DEBUG.set=view.set
	print("[cgm] menu pronto — sprint:", Sprint ~= nil, "skill:", Skill ~= nil, "hooks:", "nearest=" .. tostring(hookOk), "fire=" .. tostring(fireOk), "reload=" .. tostring(reloadOk), "turret=" .. tostring(turretOk), "predict=" .. tostring(state.predict)) 
	if _G.__CGM_DEBUG then
		print("[cgm] reloadHooked=", _G.__CGM_DEBUG.reloadHooked, "reloads=", _G.__CGM_DEBUG.reloadStats.reloads)
	end
end
task.defer(function()
	local ok,err=xpcall(main,function(message) return debug.traceback(tostring(message),2) end)
	if not ok then
		local current=_G.__CGM_DEBUG
		if current and current.uiWindow and current.unload then pcall(current.unload) end
		warn("Cães Retro: "..tostring(err))
	end
end)
