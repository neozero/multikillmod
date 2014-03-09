--[[
	MultiKill Mod 1.0.3
	Author: NeoZeroo
	E-mail: neozeroo+cobalt@gmail.com
	Thread: http://www.cobaltforum.net/topic/1884-


	* Changelog *
	1.0.3
	- Compatible with v115-Alpha
	- Fixed: since v113, sometimes the laugh button caused a crash

	1.0.2
	- Compatible with v107-Alpha
	- Removed a fix to a text rendering bug already in the game (they fixed it in 107-ALPHA)

	1.0.1
	- Fixed error with vibration when the first player is using a joystick
--]]

local function onInit_Multikill()

debugging = false
mouseVisible = false
print('MultiKill 1.0.3 Activated')

realScreenWidth, realScreenHeight = video.getScreenSize()
screenWidth, screenHeight = 1280, 800
screenFactor = screenWidth / realScreenWidth
clearp = daisy.clearPrint

streakdelay = 4
soundDir = 'controls/announcer/'
announcer = {
	multi = {
		[1] = { text = 'First Blood'	, audio = soundDir .. 'multi/0_firstblood.ogg'},
		[2] = { text = 'Double Kill'	, audio = soundDir .. 'multi/2_doublekill.ogg'},
		[3] = { text = 'Multi Kill'		, audio = soundDir .. 'multi/3_multikill.ogg'},
		[4] = { text = 'Mega Kill'		, audio = soundDir .. 'multi/4_megakill.ogg'},
		[5] = { text = 'Ultra Kill'		, audio = soundDir .. 'multi/5_ultrakill.ogg'},
		[6] = { text = 'Monster Kill'	, audio = soundDir .. 'multi/6_monsterkill.ogg'},
		[7] = { text = 'Ludicrous Kill'	, audio = soundDir .. 'multi/7_ludicrouskill.ogg'},
		[8] = { text = 'Holy Shit'		, audio = soundDir .. 'multi/8_holyshit.ogg'}
	},
	spree = {
		[5] =  { text = 'Killing Spree!', audio = soundDir .. 'spree/5_killingspree.ogg'},
		[10] = { text = 'Rampage!'		, audio = soundDir .. 'spree/10_rampage.ogg'},
		[15] = { text = 'Dominating!'	, audio = soundDir .. 'spree/15_dominating.ogg'},
		[20] = { text = 'Unstoppable!'	, audio = soundDir .. 'spree/20_unstoppable.ogg'},
		[25] = { text = 'God Like!'		, audio = soundDir .. 'spree/25_godlike.ogg'}
	}
}

spriteList = {
	blastGun  = video.createSpriteState('blastgun', '../char.dat'),
	signBreak = video.createSpriteState('signBreak', '../tiles.dat')
}

wins = {}
wins['Red wins!']    = true
wins['Green wins!']  = true
wins['Blue wins!']   = true
wins['Yellow wins!'] = true

streak = {}
preMultiQueue = {}
soundPlaying = { audio = '', time = 0, wait = 1 }
playerList = {}
pstats = {}
fragQueue = {}
fragList = {}
multiQueue = {}
shakeQueue = {}
randoms = { 0, 0 }
needRandom = true
scoresFile = 'MultiKill_scores.txt'


-- On frame rendering
local function frameRender()
	if(mouseVisible) then
		daisy.setMouseVisible(true)
	end

	if(currentGame) then
		updatePreMultiQueue()
	end
	updateFrags()
	updateShake()
	generateRandom()
end
hook.add("frameRender",frameRender)


-- When an actor is added to the current map
-- Set baseMap
OldPlayerActorAdded = Mode.onPlayerActorAdded
function Mode:onPlayerActorAdded(e)
	actor = e
	if(actor.sender) then
		baseMap = actor.map
	end
	return OldPlayerActorAdded(self,e)
end


-- When a player joins a team
-- Add to playerList and reset streaks
oldPlayerWantsToJoinTeam = Mode.onPlayerWantsToJoinTeam
function Mode:onPlayerWantsToJoinTeam(e)
	local id, player
	if(e.ai) then
		player = e.ai.player

		local new = true
		for i,k in pairs(playerList) do
			if(k.name == player.name) then
				id = i
				new = false
			end
		end

		if(new) then
			aiCount = aiCount and aiCount+1 or 101
			id = aiCount
		end
	else
		player = e.sender.player
		id = e.sender.id
	end

	debugPrint('---onPlayerWantsToJoinTeam('..id..')')

	currentGame = e.game
	player.__id = id
	playerList[id] = player
	pstats[id] = { kill = 0, death = 0, tk = 0 }
	resetStreak(id, 0, 0)
	clearp()
	return oldPlayerWantsToJoinTeam(self, e)
end


-- When a player lefts a team
-- Exclude fom playerList
oldPlayerLeft = Mode.onPlayerLeft
function Mode:onPlayerLeft(e)
 	local id
	if(e.ai) then
		id = e.ai.player.__id
	elseif(e.sender and e.sender.player.__id) then
		id = e.sender.player.__id
	end
	if(id) then
		playerList[id] = nil
	end

	debugPrint(string.format('---onPlayerLeft(%s)', id or 'nil'))
	return oldPlayerLeft(self, e)
end


-- When a player status changes
-- Detect a kill/death
oldPlayerStatChanged = Mode.onPlayerStatChanged
function Mode:onPlayerStatChanged(e)
	if(e) then
		local player
		if(e.ai) then
			player = e.ai.player
		elseif(e.sender) then
			player = e.sender.player
		end

		if(player and player.stats and next(player.stats) and not forcedKillFlag) then
			debugPrint('---onPlayerStatChanged('..player.__id..') --> enqueueFrag('..player.__id..')')
			enqueueFrag(player.__id, player.stats, currentGame.time)
		end

		forcedKillFlag = false
	end
	return oldPlayerStatChanged(self, e)
end


-- Cancel frag count for forced kill at the game over screen
oldForcedKill = Actor.forcedKill
function Actor:forcedKill(e)
	forcedKillFlag = true
	return oldForcedKill(self, e)
end


-- When a new round is started
-- Reset some lists
-- Read global scores from the file
OldInitedMapBehaviours = Mode.onInitedMapBehaviours
function Mode:onInitedMapBehaviours(e)
	roundOver = false
	fragList = {}
	fragQueue = {}
	multiQueue = {}
	soundPlaying = { audio = '', time = 0, wait = 1 }
	resetStreak()
	if(globalScores == nil) then
		readScore()
	end
	return OldInitedMapBehaviours(self, e)
end


-- When player is hit
-- Shakes joystick
oldApplyAttackDamage = Actor.applyAttackDamage
function Actor:applyAttackDamage(...)
	local args = {...}
	if(args[2].target and args[2].target.player and args[2].target.player.__id) then
		setShake(args[2].target.player.__id, 0.12)
	end
	return oldApplyAttackDamage(self, ...)
end


-- When player with joystick presses Select, make actor laugh
oldJoyButtonPressed = Input.joyButtonPressed
function Input:joyButtonPressed(jid, button, ...)

	-- if button 8, laugh
	if(jid and self.joysticks[jid]
		and self.joysticks[jid].player
		and self.joysticks[jid].player.__id
		and button == 8) then
		setEmotion(self.joysticks[jid].player.__id, 'laugh')
	end
	oldJoyButtonPressed(self, jid, button, ...)
end


-- When rendering view
-- Set baseView
OldRenderGameModeViewHud = Mode.onRenderGameModeViewHud
function Mode:onRenderGameModeViewHud(e)
	baseView = e
	return OldRenderGameModeViewHud(self,e)
end


-- When rendering hud
-- Renders frag list and animated multikills
oldRenderGameModeHud = Mode.onRenderGameModeHud
function Mode:onRenderGameModeHud(...)
	renderFragList()
	renderMultiKills()
	return oldRenderGameModeHud(self, ...)
end


-- When rendering 'Team Wins!' screen
-- Renders global score
oldrenderEndScore = ScoreHud.renderEndScore
function ScoreHud:renderEndScore(...)
	if(Settings.GlobalScores == false) then
		return oldrenderEndScore(self, ...)
	end

	local alpha = currentGame.mode.matchRestartAnim * 255
	local totalAlpha = alpha <= 70 and alpha or 70
	local winner = currentGame.mode.winningTeam.name
	local globalWinners = {}
	local teams = self.sorted
	local mode = currentGame.mode.objective.stat

	local spacing = screenWidth / (1.295 + 1.234 * #teams)
	local left = screenWidth/2 - (#teams - 1)/2 * spacing
	local y = 190

	if(roundOver == false) then
		writeScore(mode, winner)
		globalScores[mode][winner] = globalScores[mode][winner] + 1
		roundOver = true
	end

	globalWinners = getGlobalWinners(mode)
	for i,k in pairs(teams) do
		local name = k.ref.name
		local score = globalScores[mode][name]
		local x = (i-1)*spacing
		local white = ((math.cos(currentGame.mode.matchOverTimer * 18) + 1) / 2) * 215
		local colors = {}
		for m, n in pairs(k.ref.colors.hud) do
			colors[m] = n
			for o,p in pairs(globalWinners) do
				if(name == p) then
					colors[m] = math.min(255, n + white)
				end
			end
		end
		video.renderTextSprites('('..score..')', left+x, y, 1, 'big', alpha, colors.r, colors.g, colors.b)
		video.renderTextSprites('Global:', left-150, y, 1, 'big', totalAlpha, 255,255,255)
	end
	return oldrenderEndScore(self, ...)
end


-- Update frag list
function updateFrags()
	if(#fragQueue > 0 and currentGame.time - fragQueue[#fragQueue].time >= 0.01) then
		processFrag()
	end
end


-- Prepare frag list to be rendered, manage streaks
function processFrag()
	debugPrint('---preocessFrag()')
	local killers = {}
	local deads = {}
	local tk
	local killerCount = 0
	for i,k in pairs(fragQueue) do
		if(k.kill  > 0) then
			killers[k.id] = 1
			killerCount = killerCount + 1
		end
		if(k.death > 0) then table.insert(deads,   k.id) end
		tk = k.tk > 0 and k.id or tk
	end

	fragQueue = {}

	for i,k in pairs(deads) do
		resetStreak(k, 0, 0, 0)
		setShake(k, 0.6)
		local hasKiller
		if(killerCount > 0) then
			for m,n in pairs(killers) do
				if(m ~= k) then
					addToFragList(m, k)
					manageStreak(m, 1, k)
					manageStreak(k, -1)
					hasKiller = true
				end
			end
		end
		if(not hasKiller) then
			if(tk ~= nil) then
				addToFragList(nil, k, true)
				manageStreak(k, -1)
			else
				addToFragList(nil, k)
				manageStreak(k, -1)
			end
		end
		firstBloodSet = true
	end
end


-- Add killer and victim to frag list
function addToFragList(idKiller, idDead, tk)
	local killer, dead

	for i,k in ipairs({idDead, idKiller}) do
		if(k) then
			local name = nameFromId(k)
			local r,g,b = colorsFromId(k)
			if(i==1) then
				dead = {name = name, r = r, g = g, b = b}
			else
				killer = {name = name, r = r, g = g, b = b}
			end
		end
	end

	if(#fragList >= 5) then
		table.remove(fragList)
	end
	table.insert(fragList, 1, { killer = killer, dead = dead, tk = tk})
end


-- Render frag list
function renderFragList()
	if(Settings.KillFeed == false) then
		return
	end
	local x = screenWidth - 130
	local y = 110
	local vSpacing = 25

	for i=1,#fragList do
		local dead = fragList[i].dead.name
		local dr = fragList[i].dead.r
		local dg = fragList[i].dead.g
		local db = fragList[i].dead.b

		if(fragList[i].killer) then
			local killer = fragList[i].killer.name
			local kr = fragList[i].killer.r
			local kg = fragList[i].killer.g
			local kb = fragList[i].killer.b

			video.renderShadowedTextSprites(killer, x,    y - (i-1)*vSpacing, 2, 'small', 255, kr, kg, kb)
			video.renderShadowedTextSprites(dead,   x+40, y - (i-1)*vSpacing, 0, 'small', 255, dr, dg, db)
			if(spriteList.blastGun ~= -1) then
				video.renderSpriteState(spriteList.blastGun, x+15, y + 10 - (i-1)*vSpacing)
			end
		elseif(fragList[i].tk) then
			video.renderShadowedTextSprites("(-1)",  x-60, y - (i-1)*vSpacing, 1, 'small', 255, dr, dg, db)
			video.renderSpriteState(spriteList.signBreak, x-27, y + 7 - (i-1)*vSpacing, 0.47, 1)
			video.renderShadowedTextSprites(dead,  x-10, y - (i-1)*vSpacing, 0, 'small', 255, dr, dg, db)
		else
			video.renderSpriteState(spriteList.signBreak, x-27, y + 7 - (i-1)*vSpacing, 0.47, 1)
			video.renderShadowedTextSprites(dead,  x-10, y - (i-1)*vSpacing, 0, 'small', 255, dr, dg, db)
		end
	end
end


-- Add kill/death to frag list
function enqueueFrag(id, stats, time)
	debugPrint('---enqueueFrag('..tostring(id)..', '..tostring(stats)..', '..tostring(time))
	local kill = stats.kills ~= nil and stats.kills.value or 0
	local death = stats.deaths ~= nil and stats.deaths.value or 0
	local tk = stats.teamkills ~= nil and stats.teamkills.value or 0

	local difKill = kill - pstats[id].kill
	local difDeath = death - pstats[id].death
	local difTk = tk - pstats[id].tk

	pstats[id].kill = kill
	pstats[id].death = death
	pstats[id].tk = tk

	table.insert(fragQueue, { id  = id,
							kill = difKill,
							death = difDeath,
							tk = difTk,
							time  = time })
	--print(string.format('id: %s - kills: %s - deaths: %s - tk: %s - time: %s', id, difKill, difDeath, difTk, time))
end


-- Set/reset streak stats based on kills/deaths
function manageStreak(id, score, idDead)
	debugPrint('---manageStreak('..id..','..score..')')

	local lastTime = streak[id].time or 0
	local lastCount = streak[id].count or 0
	local lastSpree = streak[id].spree or 0
	local time = currentGame.time

	if(score < 0) then
		resetStreak(id, 0, 0, 0)
	elseif(score > 0) then
		if(time - streak[id].time > streakdelay) then
			resetStreak(id, time, 1)
			streak[id].spree = lastSpree + 1
		else
			streak[id].time = time
			streak[id].count = lastCount + 1
			streak[id].spree = lastSpree + 1
		end
	end

	enqueueKill(id, streak[id].count, streak[id].spree, idDead)
end


-- Prepare kill to be added to multikills list
function enqueueKill(id, count, spree, idDead)
	debugPrint('---enqueueKill('..id..', '..count..', '..spree..')')
	if(count < 1) then
		return
	elseif(count > 8) then
		count = 8
	end
	if(spree > 25) then
		spree = 25
	end

	if(announcer.multi[count] ~= nil and (count > 1 or firstBloodSet == false)) then
		enqueuePreMulti(id, idDead, 'multi', count)
	end
	if(announcer.spree[spree] ~= nil) then
		enqueuePreMulti(id, idDead, 'spree', spree)
	end
	--print(string.format('id: %s, count: %s, spree: %s', id, count, spree))
end

-- Add kill and its properties to multikills list
function enqueuePreMulti(id, idDead, annType, annId)
	if(idDead == nil or playerList[idDead] == nil or playerList[idDead].actor == nil) then
		return
	end
	local x = playerList[idDead].actor.lastX
	local y = playerList[idDead].actor.lastY
	local annAudio = announcer[annType][annId].audio
	local color = {}
	color.r, color.g, color.b = colorsFromId(id)
	table.insert(preMultiQueue, {annType = annType, annId = annId, annAudio = annAudio, x = x, y = y, color = color})
end

-- Manage multikills list, add to multikill rendering list, and play sound
function updatePreMultiQueue()
	local time = currentGame.time
	if (time - soundPlaying.time > soundPlaying.wait) then
		local multi = preMultiQueue[1]
		if(multi ~= nil) then
			if(Settings.MultiKillsAnimation) then
				enqueueMulti(multi.annType, multi.annId, time, multi.x, multi.y, multi.color)
			end
			soundPlaying.audio = multi.annAudio
			soundPlaying.time = time
			table.remove(preMultiQueue, 1)
			if(Settings.MultiKillsAnnouncer) then
				audio.stopMusic(soundPlaying.audio)
				audio.playMusic(soundPlaying.audio)
			end
		end
	end
end

-- Add multikill to final list
function enqueueMulti(annType, annId, time, x, y, color)
	local delay = 0.1
	local count = annType == 'multi' and annId-1 or 5
	local color = color or {r = 255, g = 255, b = 255}

	for i=0,count do
		table.insert(multiQueue, {annType = annType, annId = annId, time = time, count = i, x = x, y = y, color = color})
	end
end

-- Render animated multikills from final list
function renderMultiKills()
	local distance = 100
	local delay = 0.25
	local lifeSpan = 0.7

	for i,k in pairs(multiQueue) do
		local lifeSpan = lifeSpan + k.count*delay
		if(k.annType == 'spree') then
			lifeSpan = lifeSpan + k.annId/20
		end
		local life = currentGame.time - k.time
		local text = announcer[k.annType][k.annId].text
		local variationIn = math.min(1, math.max(0, tweenIn(life, 0, 1, lifeSpan)))
		local variationOut = math.min(1, math.max(0, tweenOut(life, 0, 1, lifeSpan)))
		local x, y = baseMap:positionToView(k.x, k.y-70, baseView)
		x, y = x*screenFactor, y*screenFactor

		if(k.annType == 'multi') then
			y = y - variationIn * distance
		else
			x = x + randoms[1]
			y = y + randoms[2]
			needRandom = true
		end
		local alpha = (255 - variationOut * 255) * math.min(1, life*30)

		for j=1,7 do
			video.renderTextSprites(text, x, y, 1, 'big', alpha, k.color.r, k.color.g, k.color.b)
		end

		if(life > lifeSpan) then
			multiQueue[i] = nil
		end
	end
end


-- Reset streaks for player
function resetStreak(id, time, count, spree)
	debugPrint(string.format('---resetStreak(%s, %s, %s, %s)', id or 'nil', time or 'nil', count or 'nil', spree or 'nil'))
	if(id == nil) then
		for i,k in pairs(playerList) do
			resetStreak(i, 0, 0)
		end
		firstBloodSet = false
		return
	end

	if(streak[id] == nil) then
		streak[id] = { time = 0, count = 0, spree = 0 }
	end

	streak[id].time = time or streak[id].time
	streak[id].count = count or streak[id].count
	streak[id].spree = spree or streak[id].spree
end


-- Get player name from id
function nameFromId(id)
	if(playerList[id] == nil) then
		return nil
	end

	local playerName
	if(playerList[id].name) then
		playerName = playerList[id].name
	else
		playerName = playerList[id].team.name:gsub("^%l", string.upper)
		playerName = countTeammates(id) > 1 and playerName..'-'..id or playerName
	end
	return playerName
end


-- Get team colors from player id
function colorsFromId(id)
	if(playerList[id] and playerList[id].team and playerList[id].team.colors) then
		local r = playerList[id].team.colors.text.r
		local g = playerList[id].team.colors.text.g
		local b = playerList[id].team.colors.text.b

		if(playerList[id].team.name == 'blue') then
			r = r+50
			g = g+50
		end

		return r, g, b
	else
		return 255, 255, 255
	end
end


-- Get number of players on the same team as player
function countTeammates(id)
	local count = 0
	local team = playerList[id].team.name
	for i,k in pairs(playerList) do
		if(k.team.name == team) then
			count = count + 1
		end
	end
	return count
end


-- In Cubic Easing
function tweenIn(t, b, c, d, s)
  local t = t / d
  return c * math.pow(t, 3) + b
end


-- Out Cubic Easing
function tweenOut(t, b, c, d, s)
  local t = t / d - 1
  return c * (math.pow(t, 3) + 1) + b
end


-- Vibrate player joystick (add to queue)
function setShake(id, duration)
	if(Settings.Vibration) then
		table.insert(shakeQueue, {id = id, duration = duration, time = daisy.getSeconds()})
	end
end

-- Vibrate player joystick (from queue)
function updateShake()
	local rotor = 0    -- 1: right/weaker rotor; 0: left/stronger rotor
	local force = 1000 -- probably ranges from 0 to 10
	local time = daisy.getSeconds()
	for i,k in pairs(shakeQueue) do
		if(playerList[k.id]
			and playerList[k.id].sender
			and playerList[k.id].ai == nil
			and playerList[k.id].sender.device == 'joystick'
			and time - k.time < k.duration) then
			Controller.shake(playerList[k.id].sender, rotor, force)
		else
			shakeQueue[i] = nil
		end
	end

	-- hack to fix infinity joystick vibration when a
	-- player is inactive for 60 seconds and gets a hit
	for i,k in pairs(playerList) do
		if(k.sender and k.sender.timeout and k.sender.timeout > 30 and k.sender.device == 'joystick') then
			k.sender.timeout = 1
		end
	end
end


-- Get id from player using the keyboard
function getKeyboardId()
	for i,k in pairs(playerList) do
		if(k.sender and k.sender.model == 'keyboard') then
			return i
		end
	end
end

-- Set actor emotion (duration automatically managed by the game)
function setEmotion(id, ...)
	--happy, sad, angry, surprised, confused, laugh, impressed, diggit, tappin, steppin, groovin
	local args = {...}

	if (Settings.LaughButton == false or id == nil or playerList[id] == nil or playerList[id].actor == nil or playerList[id].actor.emotions == nil) then
		return false
	end

	for i,k in pairs(args) do
		playerList[id].actor.emotionsActive[k] = true
	end

	if(playerList[id].actor.emotionAmount == nil) then
		playerList[id].actor.emotionAmount = 1
	end

	playerList[id].actor.emotionDuration = 1.5
	playerList[id].actor.emotionDelay = 0
	playerList[id].actor.expressingEmotion = true

	return true
end


-- Generate random numbers needed inside rendering functions
function generateRandom()
	if (needRandom) then
		randoms[1] = math.random(-10,10)
		randoms[2] = math.random(-10,10)
		needRandom = false
	end
end


-- Get list of teams currently winning in the global score
function getGlobalWinners(mode)
	local globalWinners = {}
	local maxScore = 0
	for i,k in pairs(globalScores[mode]) do
		maxScore = k > maxScore and k or maxScore
	end
	for i,k in pairs(globalScores[mode]) do
		if(k == maxScore) then
			table.insert(globalWinners, i)
		end
	end
	return globalWinners
end


-- Parse saved global scores from default file
function readScore()
	if(Settings.GlobalScores == false) then
		return
	end

	local pastHours = 12*60*60 --12 hours
	local now = os.time()
	local teams = {'red', 'green', 'blue', 'yellow'}
	local modes = {'kills', 'plugsCaptured', 'collectedEnergy'}
	globalScores = {}
	for _,i in pairs(modes) do
		globalScores[i] = {}
		for _,k in pairs(teams) do
			globalScores[i][k] = 0
		end
	end

	local file = io.open('daisyMoon/controls/'..scoresFile, 'r')
	if(file) then
		local content = file:read('*all')
		local lines = stringSplit(content, '\n')
		for i,k in pairs(lines) do
			local line = stringSplit(k, '\t')
			if(line[1] == 'score' and now - line[5] <= pastHours) then
				globalScores[line[2]][line[3]] = globalScores[line[2]][line[3]] + 1
			end
		end
		file:close()
		return true
	else
		file = io.open('daisyMoon/controls/'..scoresFile, 'w')
		if(file) then
			file:close()
		else
			print('Couldn\'t read global scores from "'..scoresFile..'"!')
		end
	end

	return false
end


-- Add new score to global score file
function writeScore(mode, team)
	if(Settings.GlobalScores == false) then
		return
	end

	local date = os.time()
	local dateString = os.date('%Y/%m/%d %H:%M:%S', date)

	local file = io.open('daisyMoon/controls/'..scoresFile, 'a')
	if(file) then
		file:write(string.format('score\t%s\t%s\t%s\t%s\n', mode, team, dateString, date))
		file:close()
	else
		print('Couldn\'t write score to "'..scoresFile..'"!')
	end
end


-- load settings from "MultiKill.cfg"
function loadSettings()
	Settings = {}
	Settings.MultiKillsAnimation = ''
	Settings.MultiKillsAnnouncer = ''
	Settings.KillFeed = ''
	Settings.GlobalScores = ''
	Settings.Vibration = ''
	Settings.LaughButton = ''

	local file = io.open('daisyMoon/controls/MultiKill.cfg', 'r')
	if(file) then
		local content = file:read('*all')
		content = string.gsub(content, ' ','')
		local lines = stringSplit(content, '\n')
		for i,k in pairs(lines) do
			local line = stringSplit(k, '=')
			if(Settings[line[1]]) then
				if(line[2] == 'true') then
					Settings[line[1]] = true
				elseif(line[2] == 'false') then
					Settings[line[1]] = false
				end
			end
		end
		file:close()
	end

	local doWrite = false
	for i,k in pairs(Settings) do
		if(k == '') then
			Settings[i] = true
			doWrite = true
		end
	end

	if(doWrite) then
		local file = io.open('daisyMoon/controls/MultiKill.cfg', 'w')
		if(file) then
			for i,k in pairs(Settings) do
				file:write(i .. ' = ' .. tostring(k) .. '\n')
			end
			file:close()
			print('Some missing or invalid settings were set to "true" in "MultiKill.cfg".')
		else
			print('Couldn\'t access "MultiKill.cfg" file!')
			print('All missing settings enabled.')
		end
	end
end


-- Split string using separator
function stringSplit(str, sep)
	sep = sep or '%s'

	t={}
	i=1
	for str in string.gmatch(str, "([^"..sep.."]+)") do
		t[i] = str
		i = i + 1
	end
	return t
end


-- Print if debugging
function debugPrint(var, list)
	if(debugging) then
		if(list) then
			printList(var)
		else
			print(var)
		end
	end
end


-- If table, print its contents
function printList(var, limit, search, start)
	local count = 0
	local limit = limit or 999
	local start = start or 999
	local side = ''
	if(var == nil) then
		print('null')
	elseif(type(var) ~= 'table') then
		print(tostring(var)	)
	elseif(limit == 'side') then
		for i,k in pairs(var) do
			for l,m in pairs(k) do
				side = side .. getValue(m) .. ' - '
			end
			print(side)
			side = ''
		end
	else
		local keyList = {}
		for i,k in pairs(var) do
			table.insert(keyList, i)
		end
		table.sort(keyList)
		for i,k in ipairs(keyList) do
			local result
			if(search) then result = string.find(tostring(string.lower(k)), search) end
			if(search == nil or (result and result <= start)) then
				print(k .. ' - ' .. getValue(var[k]))
				count = count + 1
			end
			if(count >= limit) then
				break
			end
		end
	end
end

-- Return tostrung(var) or table[n]
function getValue(var)
	if(type(var) ~= 'table') then
		return tostring(var)
	end
	if(var == nil) then
		return ''
	end

	local count = 0
	for _ in pairs(var) do count = count + 1 end
	return 'table[' .. count .. ']'
end

function restart_hooks()
	hook.remove("frameRender",frameRender)
	hook.remove("keyPress", onKeyPress)
	hook.remove("gameInit", onInit_Multikill)
end

-- Press tab to laugh
function onKeyPress(key)
	if(key == 9) then
		setEmotion(getKeyboardId(), 'laugh')
	end
end
hook.add("keyPress", onKeyPress)

loadSettings()
readScore()

end -- end of file
hook.add("gameInit", onInit_Multikill)


function restart_multikill()
  	restart_hooks()
	Mode.onPlayerActorAdded = OldPlayerActorAdded
	Mode.onRenderGameModeViewHud = OldRenderGameModeViewHud
	Mode.onInitedMapBehaviours = OldInitedMapBehaviours
	Mode.onPlayerWantsToJoinTeam = oldPlayerWantsToJoinTeam
	Mode.onPlayerLeft = oldPlayerLeft
	Mode.onPlayerStatChanged = oldPlayerStatChanged
	Mode.onRenderGameModeHud = oldRenderGameModeHud
	Actor.applyAttackDamage = oldApplyAttackDamage
	Actor.forcedKill = oldForcedKill
	Input.joyButtonPressed = oldJoyButtonPressed
	ScoreHud.renderEndScore = oldrenderEndScore

	-- store before restart
	local tempPlayerList = playerList
	local tempPstats = pstats
	local tempFragList = fragList
	local tempStreak = streak

	clearp()
	dofile('MultiKill.lua')
	onInit_Multikill()

	-- reload after restart
	playerList = tempPlayerList
	pstats = tempPstats
	fragList = tempFragList
	streak = tempStreak
end
