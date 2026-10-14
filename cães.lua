local function main()
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
	if legacy then
		if type(legacy.unload) == "function" then
			legacy.unload()
		elseif legacy.state then
			legacy.state.infStamina = false
			legacy.state.autoMini = false
		end
		local pg = LocalPlayer:FindFirstChild("PlayerGui")
		local oldGui = pg and pg:FindFirstChild("CacMenu")
		if oldGui then oldGui:Destroy() end
	end
	-- turretTarget: 1 = mais perto da torreta, 2 = menor vida, 3 = mais perto de voce
	local state = { infStamina = true, autoMini = true, silentAim = false, autoReload = true, autoTurret = true, autoHopium = true, predict = true, godMode = true, skipIntro = true, turretTarget = 1, fovDeg = 90, turretLeadMs = 60 }
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
		while turretOk and _G.__CGM_LOADED do
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
		if not hum or not hum:IsA("Humanoid") then return end
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
	local function unload()
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
	-- CAES_UI_REFRESH_V1
	local createCaesUi = (function()
-- CAES UI refresh. Embedded into caes.lua by install_caes_ui.lua.
return function(ctx)
    local Players=game:GetService('Players')
    local UIS=game:GetService('UserInputService')
    local RunService=game:GetService('RunService')
    local TweenService=game:GetService('TweenService')
    local player=ctx.player
    local state=ctx.state
    local alive=true
    local connections={}
    local tweens={}
    local refreshers={}
    local theme='Ciano'
    local accents={Ciano=Color3.fromRGB(71,211,233),Violeta=Color3.fromRGB(163,133,255),Verde=Color3.fromRGB(78,218,160)}
    local C={bg=Color3.fromRGB(13,17,26),side=Color3.fromRGB(17,22,33),card=Color3.fromRGB(21,28,41),hover=Color3.fromRGB(27,36,51),line=Color3.fromRGB(43,54,73),text=Color3.fromRGB(237,242,250),muted=Color3.fromRGB(143,157,181),dim=Color3.fromRGB(93,108,131),red=Color3.fromRGB(246,110,128)}
    local function accent() return accents[theme] end
    local function tint(color,amount) return C.card:Lerp(color,amount) end
    local function make(class,props,parent)
        local object=Instance.new(class)
        for key,value in pairs(props) do object[key]=value end
        object.Parent=parent
        return object
    end
    local function connect(signal,callback)
        local connection=signal:Connect(callback)
        table.insert(connections,connection)
        return connection
    end
    local function rounded(parent,radius) return make('UICorner',{CornerRadius=UDim.new(0,radius or 10)},parent) end
    local function stroke(parent,color,transparency)
        return make('UIStroke',{Color=color or C.line,Thickness=1,Transparency=transparency or 0,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},parent)
    end
    local function text(parent,name,value,x,y,w,h,size,color,bold)
        return make('TextLabel',{Name=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,Text=value,Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham,TextSize=size or 13,TextColor3=color or C.text,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center,TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=parent.ZIndex+2},parent)
    end
    local function animate(object,props,time)
        if not alive or not object.Parent then return end
        if tweens[object] then tweens[object]:Cancel() end
        local tween=TweenService:Create(object,TweenInfo.new(time or .16,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props)
        tweens[object]=tween
        tween:Play()
    end
    local function icon(parent,kind,color,x,y)
        local frame=make('Frame',{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(24,24),BackgroundTransparency=1,ZIndex=parent.ZIndex+2},parent)
        local pieces={}
        local function piece(px,py,w,h,r)
            local p=make('Frame',{Position=UDim2.fromOffset(px,py),Size=UDim2.fromOffset(w,h),BackgroundColor3=color,BorderSizePixel=0,ZIndex=frame.ZIndex},frame)
            if r then rounded(p,r) end
            table.insert(pieces,p)
            return p
        end
        if kind=='grid' then for _,p in ipairs({{3,3},{14,3},{3,14},{14,14}}) do piece(p[1],p[2],7,7,2) end
        elseif kind=='aim' then
            local ring=make('Frame',{Position=UDim2.fromOffset(4,4),Size=UDim2.fromOffset(16,16),BackgroundTransparency=1,ZIndex=frame.ZIndex},frame)
            rounded(ring,16); table.insert(pieces,stroke(ring,color,0))
            piece(11,0,2,6,1); piece(11,18,2,6,1); piece(0,11,6,2,1); piece(18,11,6,2,1)
        elseif kind=='health' then piece(9,3,6,18,2); piece(3,9,18,6,2)
        elseif kind=='gear' then
            for i=0,3 do local p=piece(10,1,4,22,2); p.Rotation=i*45 end
            local core=piece(5,5,14,14,7); core.BackgroundColor3=C.side
            table.insert(pieces,stroke(core,color,0))
        elseif kind=='paw' then
            piece(1,3,5,7,3); piece(7,0,5,7,3); piece(14,0,5,7,3); piece(20,3,5,7,3)
            piece(6,12,14,11,6)
        end
        return function(newColor)
            for _,p in ipairs(pieces) do
                if p:IsA('UIStroke') then p.Color=newColor
                elseif not (kind=='gear' and p.Size.X.Offset==14) then p.BackgroundColor3=newColor end
            end
        end
    end
    local gui=make('ScreenGui',{Name='CacMenu',ResetOnSpawn=false,IgnoreGuiInset=true,DisplayOrder=60,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},player:WaitForChild('PlayerGui'))
    local root=make('CanvasGroup',{Name='Panel',Size=UDim2.fromOffset(690,600),Position=UDim2.fromOffset(48,130),BackgroundColor3=C.bg,BorderSizePixel=0,Active=true,ZIndex=100,GroupTransparency=0},gui)
    rounded(root,16)
    local rootStroke=stroke(root,C.line,.1)
    local scale=make('UIScale',{Scale=1},root)
    local shadow=make('ImageLabel',{Name='Shadow',AnchorPoint=Vector2.new(0,0),Position=UDim2.fromOffset(24,106),Size=UDim2.fromOffset(738,648),BackgroundTransparency=1,Image='rbxassetid://1316045217',ImageColor3=Color3.new(0,0,0),ImageTransparency=.3,ScaleType=Enum.ScaleType.Slice,SliceCenter=Rect.new(10,10,118,118),ZIndex=99,Active=false},gui)
    local side=make('Frame',{Name='Sidebar',Position=UDim2.fromOffset(0,70),Size=UDim2.fromOffset(160,530),BackgroundColor3=C.side,BorderSizePixel=0,ZIndex=101},root)
    make('Frame',{Position=UDim2.fromOffset(160,70),Size=UDim2.fromOffset(1,530),BackgroundColor3=C.line,BackgroundTransparency=.3,BorderSizePixel=0,ZIndex=102},root)
    make('Frame',{Position=UDim2.fromOffset(0,69),Size=UDim2.fromOffset(690,1),BackgroundColor3=C.line,BackgroundTransparency=.3,BorderSizePixel=0,ZIndex=103},root)
    local header=make('Frame',{Name='Header',Size=UDim2.fromOffset(690,69),BackgroundTransparency=1,Active=true,ZIndex=104},root)
    local logo=make('Frame',{Position=UDim2.fromOffset(19,16),Size=UDim2.fromOffset(38,38),BackgroundColor3=tint(accent(),.2),BorderSizePixel=0,ZIndex=105},header)
    rounded(logo,11)
    local logoColor=icon(logo,'paw',accent(),6,6)
    text(header,'Brand','CAES',69,14,185,23,21,C.text,true)
    text(header,'BrandCaption','SURVIVAL CONTROL',70,37,195,16,9,C.muted,true)
    local badge=make('Frame',{Name='ConnectionBadge',Position=UDim2.fromOffset(475,23),Size=UDim2.fromOffset(103,25),BackgroundColor3=tint(accent(),.13),BorderSizePixel=0,ZIndex=105},header)
    rounded(badge,8)
    local badgeDot=make('Frame',{Position=UDim2.fromOffset(10,9),Size=UDim2.fromOffset(7,7),BackgroundColor3=accent(),BorderSizePixel=0,ZIndex=106},badge)
    rounded(badgeDot,5)
    local badgeText=text(badge,'Text','ONLINE',25,0,72,25,10,accent(),true)
    local function smallButton(name,label,x)
        local b=make('TextButton',{Name=name,Position=UDim2.fromOffset(x,20),Size=UDim2.fromOffset(30,30),BackgroundColor3=C.card,BorderSizePixel=0,Text=label,TextColor3=C.muted,TextSize=20,Font=Enum.Font.Gotham,AutoButtonColor=false,ZIndex=106},header)
        rounded(b,8)
        connect(b.MouseEnter,function() animate(b,{BackgroundColor3=C.hover,TextColor3=C.text}) end)
        connect(b.MouseLeave,function() animate(b,{BackgroundColor3=C.card,TextColor3=C.muted}) end)
        return b
    end
    local minimize=smallButton('Minimize','−',604)
    local close=smallButton('Close','×',644)
    local userBox=make('Frame',{Position=UDim2.fromOffset(12,456),Size=UDim2.fromOffset(136,58),BackgroundColor3=C.card,BorderSizePixel=0,ZIndex=103},side)
    rounded(userBox,10)
    local avatar=make('TextLabel',{Position=UDim2.fromOffset(10,12),Size=UDim2.fromOffset(30,30),BackgroundColor3=tint(accent(),.13),Text=player.DisplayName:sub(1,1):upper(),TextColor3=accent(),TextSize=15,Font=Enum.Font.GothamBold,BorderSizePixel=0,ZIndex=104},userBox)
    rounded(avatar,9)
    text(userBox,'Player',player.DisplayName,48,10,80,20,11,C.text,true)
    text(userBox,'Client','CLIENTE LOCAL',48,30,81,15,8,C.dim,true)
    local pageTitle=text(root,'PageTitle','Visão geral',181,90,452,28,23,C.text,true)
    local pageSubtitle=text(root,'PageSubtitle','Sua rodada em um só lugar.',183,120,480,20,12,C.muted,false)
    local viewport=make('Frame',{Name='Content',Position=UDim2.fromOffset(181,153),Size=UDim2.fromOffset(489,395),BackgroundTransparency=1,ZIndex=102},root)
    local footer=text(root,'Footer','INSERT   abrir / ocultar',181,565,271,20,10,C.dim,false)
    local activeLabel=text(root,'ActiveFeatures','',482,565,189,20,10,C.muted,false)
    activeLabel.TextXAlignment=Enum.TextXAlignment.Right
    local pages,nav={},{}
    local currentTab='Painel'
    local tabs={
        {key='Painel',title='Visão geral',subtitle='Sua rodada em um só lugar.',icon='grid'},
        {key='Combate',title='Combate',subtitle='Mira, recarga e controle da torreta.',icon='aim'},
        {key='Sobrevivência',title='Sobrevivência',subtitle='Mobilidade, recuperação e fuga.',icon='health'},
        {key='Ajustes',title='Ajustes',subtitle='Personalize o visual e os controles.',icon='gear'},
    }
    local function page(key)
        local p=make('ScrollingFrame',{Name=key,Size=UDim2.fromScale(1,1),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,ScrollBarImageColor3=C.line,CanvasSize=UDim2.fromOffset(0,0),ScrollingDirection=Enum.ScrollingDirection.Y,Visible=key=='Painel',ZIndex=103},viewport)
        pages[key]=p
        return p
    end
    local function navRefresh()
        for key,item in pairs(nav) do
            local active=key==currentTab
            item.button.BackgroundColor3=active and tint(accent(),.13) or C.side
            item.label.TextColor3=active and C.text or C.muted
            item.mark.Visible=active; item.mark.BackgroundColor3=accent()
            item.icon(active and accent() or C.dim)
        end
    end
    local function selectTab(key)
        assert(pages[key],'Aba inválida')
        currentTab=key
        for name,p in pairs(pages) do p.Visible=name==key end
        for _,tab in ipairs(tabs) do
            if tab.key==key then pageTitle.Text=tab.title; pageSubtitle.Text=tab.subtitle end
        end
        navRefresh()
    end
    for i,tab in ipairs(tabs) do
        local p=page(tab.key)
        local b=make('TextButton',{Name='Tab_'..tab.key,Position=UDim2.fromOffset(12,22+(i-1)*47),Size=UDim2.fromOffset(136,40),BackgroundColor3=C.side,BorderSizePixel=0,Text='',AutoButtonColor=false,ZIndex=104},side)
        rounded(b,9)
        local label=text(b,'Label',tab.key,41,0,90,40,12,C.muted,true)
        local recolor=icon(b,tab.icon,C.dim,10,8)
        local mark=make('Frame',{Position=UDim2.fromOffset(0,11),Size=UDim2.fromOffset(3,18),BackgroundColor3=accent(),BorderSizePixel=0,Visible=false,ZIndex=105},b)
        rounded(mark,2)
        nav[tab.key]={button=b,label=label,icon=recolor,mark=mark}
        connect(b.Activated,function() selectTab(tab.key) end)
        connect(b.MouseEnter,function() if currentTab~=tab.key then animate(b,{BackgroundColor3=C.card}) end end)
        connect(b.MouseLeave,function() if currentTab~=tab.key then animate(b,{BackgroundColor3=C.side}) end end)
    end
    local function card(parent,name,x,y,w,h)
        local c=make('Frame',{Name=name,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),BackgroundColor3=C.card,BorderSizePixel=0,ZIndex=105},parent)
        rounded(c,11); stroke(c,C.line,.45)
        return c
    end
    local widgets={}
    local featureKeys={'silentAim','autoReload','autoTurret','predict','infStamina','autoMini','autoHopium','godMode','skipIntro'}
    local function set(key,value)
        ctx.set(key,value)
        if widgets[key] then widgets[key].refresh(true) end
    end
    local function toggleCard(parent,key,label,description,x,y)
        local unavailable=ctx.unavailable and ctx.unavailable[key]
        local b=make('TextButton',{Name=key,Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(237,88),BackgroundColor3=C.card,BorderSizePixel=0,Text='',AutoButtonColor=false,ZIndex=105},parent)
        rounded(b,11)
        local border=stroke(b,C.line,.45)
        text(b,'Label',label,13,12,163,22,13,unavailable and C.dim or C.text,true)
        local desc=text(b,'Description',unavailable and 'Indisponível neste cliente.' or description,13,39,210,35,10,C.muted,false)
        desc.TextWrapped=true; desc.TextTruncate=Enum.TextTruncate.None; desc.TextYAlignment=Enum.TextYAlignment.Top
        local track=make('Frame',{Name='Switch',Position=UDim2.fromOffset(186,15),Size=UDim2.fromOffset(37,20),BackgroundColor3=C.line,BorderSizePixel=0,ZIndex=106},b)
        rounded(track,10)
        local knob=make('Frame',{Name='Knob',Position=UDim2.fromOffset(3,3),Size=UDim2.fromOffset(14,14),BackgroundColor3=C.muted,BorderSizePixel=0,ZIndex=107},track)
        rounded(knob,10)
        local last
        local function refresh(transition)
            local on=state[key]==true and not unavailable
            if on==last and not transition then return end
            last=on
            local trackColor=on and accent() or C.line
            local knobColor=on and C.bg or C.muted
            if transition then
                animate(track,{BackgroundColor3=trackColor}); animate(knob,{Position=UDim2.fromOffset(on and 20 or 3,3),BackgroundColor3=knobColor})
            else track.BackgroundColor3=trackColor; knob.Position=UDim2.fromOffset(on and 20 or 3,3); knob.BackgroundColor3=knobColor end
            border.Color=on and accent() or C.line; border.Transparency=on and .72 or .45
        end
        connect(b.Activated,function() if not unavailable then set(key,not state[key]) end end)
        connect(b.MouseEnter,function() animate(b,{BackgroundColor3=C.hover}) end)
        connect(b.MouseLeave,function() animate(b,{BackgroundColor3=C.card}) end)
        widgets[key]={button=b,refresh=refresh}; refresh(false)
    end
    toggleCard(pages.Combate,'silentAim','Silent aim','Direciona os tiros para cães no FOV.',0,0)
    toggleCard(pages.Combate,'autoReload','Auto reload','Recarrega quando o pente esvazia.',249,0)
    toggleCard(pages.Combate,'autoTurret','Auto torreta','Mira e dispara quando estiver montado.',0,100)
    toggleCard(pages.Combate,'predict','Mira preditiva','Compensa movimento e atraso da torreta.',249,100)
    local modes={'Mais perto da torreta','Menor vida','Mais perto de você'}
    local priorityCard=card(pages.Combate,'TurretPriority',0,212,486,77)
    text(priorityCard,'Label','Prioridade da torreta',13,10,306,20,12,C.text,true)
    local priorityButtons={}
    for i,label in ipairs({'Torreta','Menor vida','Você'}) do
        local b=make('TextButton',{Name='TurretMode'..i,Position=UDim2.fromOffset(13+(i-1)*154,38),Size=UDim2.fromOffset(145,27),BackgroundColor3=C.bg,Text=label,TextSize=11,TextColor3=C.muted,Font=Enum.Font.GothamMedium,BorderSizePixel=0,AutoButtonColor=false,ZIndex=107},priorityCard)
        rounded(b,7); priorityButtons[i]=b
        connect(b.Activated,function() set('turretTarget',i) end)
    end
    local modeHint=text(priorityCard,'Selected','',302,10,172,20,9,C.muted,false)
    modeHint.TextXAlignment=Enum.TextXAlignment.Right
    local function refreshPriority()
        local index=math.clamp(tonumber(state.turretTarget) or 1,1,3)
        for i,b in ipairs(priorityButtons) do b.BackgroundColor3=i==index and tint(accent(),.24) or C.bg; b.TextColor3=i==index and accent() or C.muted end
        modeHint.Text=modes[index]
    end
    table.insert(refreshers,refreshPriority)
    local fovCard=card(pages.Combate,'FovControl',0,301,486,91)
    text(fovCard,'Title','Campo de visão',13,9,238,22,13,C.text,true)
    local fovLabel=text(fovCard,'FovLabel','',325,9,147,22,12,accent(),true)
    fovLabel.TextXAlignment=Enum.TextXAlignment.Right
    local minus=make('TextButton',{Name='FovMinus',Position=UDim2.fromOffset(13,43),Size=UDim2.fromOffset(27,25),BackgroundColor3=C.bg,BorderSizePixel=0,Text='−',TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=16,AutoButtonColor=false,ZIndex=108},fovCard)
    local plus=make('TextButton',{Name='FovPlus',Position=UDim2.fromOffset(446,43),Size=UDim2.fromOffset(27,25),BackgroundColor3=C.bg,BorderSizePixel=0,Text='+',TextColor3=C.text,Font=Enum.Font.GothamBold,TextSize=16,AutoButtonColor=false,ZIndex=108},fovCard)
    rounded(minus,6); rounded(plus,6)
    local track=make('Frame',{Name='Track',Position=UDim2.fromOffset(53,54),Size=UDim2.fromOffset(380,4),BackgroundColor3=C.line,BorderSizePixel=0,Active=true,ZIndex=107},fovCard)
    rounded(track,4)
    local fill=make('Frame',{Name='Fill',Size=UDim2.fromScale(.5,1),BackgroundColor3=accent(),BorderSizePixel=0,ZIndex=108},track)
    rounded(fill,4)
    local knob=make('Frame',{Name='Knob',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(13,13),BackgroundColor3=accent(),BorderSizePixel=0,ZIndex=109},track)
    rounded(knob,8)
    local hitbox=make('TextButton',{Name='Slider',Position=UDim2.fromOffset(47,42),Size=UDim2.fromOffset(392,29),BackgroundTransparency=1,Text='',AutoButtonColor=false,ZIndex=110},fovCard)
    text(fovCard,'Hint','10°',53,72,100,14,9,C.dim,false)
    local maxHint=text(fovCard,'Max','170°',359,72,74,14,9,C.dim,false); maxHint.TextXAlignment=Enum.TextXAlignment.Right
    pages.Combate.CanvasSize=UDim2.fromOffset(0,405)
    local sliderDrag,sliderInput
    local function refreshFov()
        local value=math.clamp(tonumber(state.fovDeg) or 90,10,170)
        local ratio=(value-10)/160
        fill.Size=UDim2.fromScale(ratio,1); knob.Position=UDim2.fromScale(ratio,.5)
        fill.BackgroundColor3=accent(); knob.BackgroundColor3=accent(); fovLabel.TextColor3=accent()
        fovLabel.Text='FOV: '..math.floor(value)..'°'
    end
    local function pointerFov(x)
        local ratio=math.clamp((x-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)
        set('fovDeg',math.floor(10+ratio*160+.5)); refreshFov()
    end
    connect(minus.Activated,function() set('fovDeg',math.clamp(state.fovDeg-5,10,170)); refreshFov() end)
    connect(plus.Activated,function() set('fovDeg',math.clamp(state.fovDeg+5,10,170)); refreshFov() end)
    connect(hitbox.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then sliderDrag=true; sliderInput=input; pointerFov(input.Position.X) end
    end)
    table.insert(refreshers,refreshFov)
    toggleCard(pages['Sobrevivência'],'infStamina','Stamina infinita','Mantém a energia para correr.',0,0)
    toggleCard(pages['Sobrevivência'],'autoMini','Auto minigame','Automatiza o minigame de fuga.',249,0)
    toggleCard(pages['Sobrevivência'],'autoHopium','Auto Hopium','Usa a cura quando o item está equipado.',0,100)
    toggleCard(pages['Sobrevivência'],'godMode','Anti-arrasto','Facilita a fuga e reduz o ragdoll.',249,100)
    local protection=card(pages['Sobrevivência'],'ProtectionStats',0,212,486,117)
    text(protection,'Title','TELEMETRIA DA PROTEÇÃO',14,12,445,18,10,C.muted,true)
    local protectionValue=text(protection,'Value','Aguardando dados...',14,39,445,28,16,C.text,true)
    local protectionDetail=text(protection,'Detail','',14,77,445,23,11,C.muted,false)
    toggleCard(pages.Ajustes,'skipIntro','Pular introdução','Usa o botão de pular a cinematográfica.',0,0)
    local shortcut=card(pages.Ajustes,'Shortcut',249,0,237,88)
    text(shortcut,'Title','Atalho do painel',13,12,200,22,13,C.text,true)
    text(shortcut,'Hint','Insert para abrir ou ocultar.',13,44,210,23,11,C.muted,false)
    local themeCard=card(pages.Ajustes,'Theme',0,100,486,87)
    text(themeCard,'Title','Cor de destaque',13,9,445,20,13,C.text,true)
    local themeButtons={}
    for i,name in ipairs({'Ciano','Violeta','Verde'}) do
        local b=make('TextButton',{Name='Theme_'..name,Position=UDim2.fromOffset(13+(i-1)*154,40),Size=UDim2.fromOffset(145,30),BackgroundColor3=C.bg,BorderSizePixel=0,Text=name,TextColor3=accents[name],Font=Enum.Font.GothamMedium,TextSize=12,AutoButtonColor=false,ZIndex=108},themeCard)
        rounded(b,7); themeButtons[name]=b
    end
    local actionCard=card(pages.Ajustes,'Actions',0,199,486,118)
    text(actionCard,'Title','Interface e sessão',13,10,445,23,13,C.text,true)
    text(actionCard,'Description','Ocultar deixa os recursos ativos. Encerrar descarrega o script.',13,39,452,29,10,C.muted,false).TextWrapped=true
    local hideAction=make('TextButton',{Name='HideMenu',Position=UDim2.fromOffset(13,78),Size=UDim2.fromOffset(225,28),BackgroundColor3=C.hover,BorderSizePixel=0,Text='Ocultar painel',TextColor3=C.text,Font=Enum.Font.GothamMedium,TextSize=11,AutoButtonColor=false,ZIndex=107},actionCard)
    local unloadAction=make('TextButton',{Name='Unload',Position=UDim2.fromOffset(249,78),Size=UDim2.fromOffset(225,28),BackgroundColor3=tint(C.red,.16),BorderSizePixel=0,Text='Encerrar script',TextColor3=C.red,Font=Enum.Font.GothamMedium,TextSize=11,AutoButtonColor=false,ZIndex=107},actionCard)
    rounded(hideAction,7); rounded(unloadAction,7)
    local hero=card(pages.Painel,'RoundCard',0,0,486,67)
    local heroAccent=make('Frame',{Position=UDim2.fromOffset(0,13),Size=UDim2.fromOffset(3,41),BackgroundColor3=accent(),BorderSizePixel=0,ZIndex=107},hero); rounded(heroAccent,2)
    local roundTitle=text(hero,'RoundTitle','Aguardando rodada',15,9,333,23,15,C.text,true)
    local roundSubtitle=text(hero,'RoundSubtitle','',15,33,351,22,11,C.muted,false)
    local clock=text(hero,'Clock','--:--',380,12,91,38,19,accent(),true); clock.TextXAlignment=Enum.TextXAlignment.Right
    local statValues={}
    for i,item in ipairs({{'Dogs','CÃES VIVOS'},{'Coins','MOEDAS'},{'Survivals','SOBREVIVÊNCIAS'},{'Health','SAÚDE'}}) do
        local x=((i-1)%2)*249; local y=79+math.floor((i-1)/2)*83
        local c=card(pages.Painel,item[1],x,y,237,71)
        text(c,'Label',item[2],13,9,211,18,9,C.muted,true)
        statValues[item[1]]=text(c,'Value','—',13,28,211,32,23,C.text,true)
    end
    local healthBar=make('Frame',{Name='HealthBar',Position=UDim2.fromOffset(13,63),Size=UDim2.fromOffset(211,3),BackgroundColor3=C.line,BorderSizePixel=0,ZIndex=107},pages.Painel.Health)
    rounded(healthBar,3)
    local healthFill=make('Frame',{Size=UDim2.fromScale(1,1),BackgroundColor3=accent(),BorderSizePixel=0,ZIndex=108},healthBar); rounded(healthFill,3)
    local equipment=card(pages.Painel,'Equipment',0,245,486,87)
    text(equipment,'Title','EQUIPAMENTO & CONEXÃO',13,10,451,17,9,C.muted,true)
    local equipmentValue=text(equipment,'Value','',13,35,450,24,13,C.text,true)
    local equipmentNote=text(equipment,'Note','',13,61,452,16,10,C.muted,false)
    local fovCircle=make('Frame',{Name='SilentAimFov',AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),Size=UDim2.fromOffset(130,130),BackgroundTransparency=1,BorderSizePixel=0,Visible=state.silentAim,Active=false,ZIndex=80},gui)
    make('UICorner',{CornerRadius=UDim.new(1,0)},fovCircle)
    local fovStroke=stroke(fovCircle,accent(),.5)
    local pill=make('TextButton',{Name='TogglePill',Position=UDim2.new(0,24,1,-64),Size=UDim2.fromOffset(147,40),BackgroundColor3=C.side,BorderSizePixel=0,Text='',AutoButtonColor=false,Visible=false,ZIndex=100},gui)
    rounded(pill,12); stroke(pill,C.line,.1)
    local pillIcon=icon(pill,'paw',accent(),10,8)
    text(pill,'Title','CAES',44,0,55,40,13,C.text,true)
    text(pill,'Key','Insert',103,0,40,40,9,C.muted,false)
    local visibilityId=0
    local function setVisible(value)
        visibilityId+=1
        local id=visibilityId
        if value then
            root.Visible=true; shadow.Visible=true; pill.Visible=false
            animate(root,{GroupTransparency=0},.14)
        else
            pill.Visible=true
            animate(root,{GroupTransparency=1},.12)
            task.delay(.13,function() if alive and visibilityId==id then root.Visible=false; shadow.Visible=false end end)
        end
    end
    local function togglePanel() setVisible(not root.Visible or root.GroupTransparency>.5) end
    connect(minimize.Activated,function() setVisible(false) end)
    connect(close.Activated,function() setVisible(false) end)
    connect(hideAction.Activated,function() setVisible(false) end)
    connect(pill.Activated,function() setVisible(true) end)
    connect(unloadAction.Activated,function() ctx.unload() end)
    connect(UIS.InputBegan,function(input,processed)
        if not processed and input.KeyCode==Enum.KeyCode.Insert then togglePanel() end
    end)
    local function setTheme(value)
        assert(accents[value],'Tema inválido')
        theme=value
        logo.BackgroundColor3=tint(accent(),.2); logoColor(accent())
        badge.BackgroundColor3=tint(accent(),.13); badgeDot.BackgroundColor3=accent(); badgeText.TextColor3=accent()
        avatar.BackgroundColor3=tint(accent(),.13); avatar.TextColor3=accent(); heroAccent.BackgroundColor3=accent()
        clock.TextColor3=accent(); fovStroke.Color=accent(); pillIcon(accent())
        navRefresh(); refreshPriority(); refreshFov()
        for _,widget in pairs(widgets) do widget.refresh(true) end
        for name,b in pairs(themeButtons) do b.BackgroundColor3=name==theme and tint(accents[name],.2) or C.bg end
    end
    for name,b in pairs(themeButtons) do connect(b.Activated,function() setTheme(name) end) end
    local dragging,dragInput,dragStart,startPosition
    local function over(object,position)
        local p,s=object.AbsolutePosition,object.AbsoluteSize
        return position.X>=p.X and position.X<=p.X+s.X and position.Y>=p.Y and position.Y<=p.Y+s.Y
    end
    connect(header.InputBegan,function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            if over(close,input.Position) or over(minimize,input.Position) then return end
            dragging=true; dragInput=input; dragStart=input.Position; startPosition=root.Position
        end
    end)
    connect(UIS.InputEnded,function(input)
        if input==dragInput then dragging=false end
        if input==sliderInput then sliderDrag=false end
    end)
    local function viewportSize()
        local camera=workspace.CurrentCamera
        return camera and camera.ViewportSize or Vector2.new(1280,720)
    end
    local function clampWindow()
        local vp=viewportSize()
        scale.Scale=math.clamp(math.min(1,(vp.X-32)/690,(vp.Y-32)/600),.35,1)
        local size=Vector2.new(690,600)*scale.Scale
        local x=math.clamp(root.Position.X.Offset,8,math.max(8,vp.X-size.X-8))
        local y=math.clamp(root.Position.Y.Offset,8,math.max(8,vp.Y-size.Y-8))
        root.Position=UDim2.fromOffset(x,y)
        shadow.Position=UDim2.fromOffset(x-24*scale.Scale,y-24*scale.Scale)
        shadow.Size=UDim2.fromOffset(size.X+48*scale.Scale,size.Y+48*scale.Scale)
    end
    connect(UIS.InputChanged,function(input)
        if sliderDrag and (input.UserInputType==Enum.UserInputType.MouseMovement or input==sliderInput) then pointerFov(input.Position.X) end
        if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input==dragInput) then
            local d=input.Position-dragStart
            root.Position=UDim2.fromOffset(startPosition.X.Offset+d.X,startPosition.Y.Offset+d.Y)
            clampWindow()
        end
    end)
    local function shortNumber(value)
        value=tonumber(value) or 0
        if value>=1000000 then return (string.format('%.1fM',value/1000000):gsub('%.',',')) end
        if value>=10000 then return (string.format('%.1fk',value/1000):gsub('%.',',')) end
        return tostring(math.floor(value))
    end
    local function updateStats()
        local debug=ctx.debug()
        local round=game.ReplicatedStorage:FindFirstChild('Round')
        local stats=player:FindFirstChild('RoundStats')
        local shop=player:FindFirstChild('Shop')
        local leaders=player:FindFirstChild('leaderstats')
        local char=player.Character
        local hum=char and char:FindFirstChildOfClass('Humanoid')
        local status=round and round:GetAttribute('Status') or 'Lobby'
        local special=round and round:GetAttribute('Special') or ''
        local map=stats and stats:GetAttribute('Map') or ''
        roundTitle.Text=status=='Round' and 'Rodada em andamento' or (status=='Intermission' and 'Intervalo entre rodadas' or 'Preparando a próxima rodada')
        roundSubtitle.Text=(map~='' and tostring(map):gsub('_',' ') or 'Lobby')..'  /  '..(special~='' and tostring(special) or 'Normal')
        local ends=round and round:GetAttribute('EndsAt')
        local remaining=type(ends)=='number' and math.max(0,math.ceil(ends-workspace:GetServerTimeNow())) or 0
        clock.Text=string.format('%02d:%02d',math.floor(remaining/60),remaining%60)
        local dogs=0
        local folder=workspace:FindFirstChild('NPCs')
        if folder then for _,model in ipairs(folder:GetChildren()) do local h=model:FindFirstChildOfClass('Humanoid'); if h and h.Health>0 then dogs+=1 end end end
        statValues.Dogs.Text=tostring(dogs)
        statValues.Coins.Text=shortNumber(shop and shop:GetAttribute('Coins'))
        local survivals=leaders and leaders:FindFirstChild('Survivals')
        statValues.Survivals.Text=survivals and tostring(survivals.Value) or '—'
        local hp,maxHp=hum and hum.Health or 0,hum and hum.MaxHealth or 100
        statValues.Health.Text=string.format('%.0f / %.0f',hp,maxHp)
        healthFill.Size=UDim2.fromScale(math.clamp(hp/math.max(1,maxHp),0,1),1)
        healthFill.BackgroundColor3=hp<=maxHp*.25 and C.red or accent()
        local tool=char and char:FindFirstChildOfClass('Tool')
        local loaded,reserve=tool and tool:GetAttribute('Loaded'),tool and tool:GetAttribute('Reserve')
        equipmentValue.Text=tool and tool.Name or 'Nenhum item equipado'
        if type(loaded)=='number' then equipmentValue.Text..=string.format('  •  %.0f / %.0f munições',loaded,tonumber(reserve) or 0) end
        local turret=debug and debug.turret
        local ping=debug and debug.ping and math.floor(debug.ping()*2000) or 0
        equipmentNote.Text=(turret and turret._manning and 'Torreta montada' or 'Torreta em espera')..'  •  Ping '..ping..' ms  •  Insert: painel'
        local god=debug and debug.godStats or {}
        local struggle=debug and debug.struggleStats or {}
        protectionValue.Text=string.format('%d arrastos  /  %d apertos aceitos',god.grabs or 0,struggle.credit or 0)
        protectionDetail.Text=string.format('%d quedas de vida registradas  •  %d bloqueios de ragdoll',god.drops or 0,god.ragdollBlocks or 0)
        if god.lastErr or struggle.lastErr then protectionDetail.Text='Uma ação encontrou erro. Consulte o console.'; protectionDetail.TextColor3=C.red else protectionDetail.TextColor3=C.muted end
        local active=0
        for _,key in ipairs(featureKeys) do if state[key] and not (ctx.unavailable and ctx.unavailable[key]) then active+=1 end end
        activeLabel.Text=active..' recursos ativos'
    end
    local function refresh()
        for _,widget in pairs(widgets) do widget.refresh(false) end
        for _,callback in ipairs(refreshers) do callback() end
        fovCircle.Visible=state.silentAim==true
        updateStats()
    end
    local accumulator=0
    connect(RunService.Heartbeat,function(dt)
        accumulator+=dt
        if accumulator>=.2 then accumulator=0; if alive then clampWindow(); refresh() end end
    end)
    local api={gui=gui,root=root,fovCircle=fovCircle,fovLabel=fovLabel,pages=pages,widgets=widgets,selectTab=selectTab,set=set,setTheme=setTheme,setVisible=setVisible,refresh=refresh,pointerFov=pointerFov,priorityButtons=priorityButtons}
    function api.getTheme() return theme end
    function api.getTab() return currentTab end
    function api.cleanup()
        if not alive then return end
        alive=false
        for _,connection in ipairs(connections) do connection:Disconnect() end
        for _,tween in pairs(tweens) do pcall(function() tween:Cancel() end) end
        gui:Destroy()
    end
    clampWindow(); setTheme(theme); selectTab('Painel'); refresh()
    return api
end
	end)()
	local view = createCaesUi({
		player=LocalPlayer, state=state,
		set=function(key,value) _G.__CGM_DEBUG.set(key,value) end,
		debug=function() return _G.__CGM_DEBUG end,
		unload=unload,
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
	print("[cgm] menu pronto — sprint:", Sprint ~= nil, "skill:", Skill ~= nil, "hooks:", "nearest=" .. tostring(hookOk), "fire=" .. tostring(fireOk), "reload=" .. tostring(reloadOk), "turret=" .. tostring(turretOk), "predict=" .. tostring(state.predict)) 
	if _G.__CGM_DEBUG then
		print("[cgm] reloadHooked=", _G.__CGM_DEBUG.reloadHooked, "reloads=", _G.__CGM_DEBUG.reloadStats.reloads)
	end
end
if _G.__CGM_LOADED then
	print("[cgm] ja ativo, ignorando re-execucao")
else
	_G.__CGM_LOADED = true
	main()
end
