local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local IsServer = RunService:IsServer()
local IsClient = RunService:IsClient()

local Signal

if IsServer then
	Signal = Instance.new("RemoteEvent")
	Signal.Name = "Signal"
	Signal.Parent = script
elseif IsClient then
	Signal = script:WaitForChild("Signal")
end

local function getObjectFromContainer(container)
	if typeof(container) == "Instance" then
		return container
	elseif typeof(container) == "Vector3" then
		local object = Instance.new("Attachment")
		object.WorldPosition = container
		object.Parent = workspace.Terrain
		
		return object, true
	elseif typeof(container) == "CFrame" then
		local object = Instance.new("Attachment")
		object.WorldPosition = container.Position
		object.Parent = workspace.Terrain
		
		return object, true
	end
	
	warn("Invalid object type passed: ", container, typeof(container))
	
	return nil
end

local AudioService = {}
AudioService.AudioRegistry = {}
AudioService.ActiveAudios = {}
AudioService.SoundSetting = 1

AudioService._LoadedClients = {}

local function internalDestroyAudio(audio, parentObject, parentWasCreated)
	local index = table.find(AudioService.ActiveAudios, audio)
	if index then
		table.remove(AudioService.ActiveAudios, index)
	end
	
	audio:Destroy()

	if parentWasCreated then
		parentObject:Destroy()
	end
end

-- Creates a new audio object
--[[
params:
	reference:			[number] | string]
	container:			[vector3 | cframe | instance] (where the audio gets stored)
	audioProperties?:	[table] (audio property mapping)
	effectProperties?:	[table]	(effect objects and their property mapping)
	
return~ [instance], [instance]
]]
function AudioService.Create(reference, container, audioProperties, effectProperties)
	audioProperties = audioProperties or {}
	effectProperties = effectProperties or {}

	local audio = nil
	local typeOfReference = typeof(reference)
	if typeOfReference == "Instance" then
		assert(reference:IsA("Sound"), tostring(reference).." is not a Sound Instance")
		audio = reference:Clone()
	elseif typeOfReference == "string" or typeOfReference == "number" then
		audio = AudioService.GetRegisteredAudioObject(reference)

		-- Attempt to use the reference as a direct sound ID
		if not audio then
			audio = Instance.new("Sound")
			audio.SoundId = "rbxassetid://"..reference:match("%d+")
		end
	end

	for property, value in audioProperties do
		audio[property] = value
	end

	for effect, propertyTable in effectProperties do
		local effectObject = Instance.new(effect)
		for property, value in propertyTable do
			effectObject[property] = value
		end

		effectObject.Parent = audio
	end

	audio:SetAttribute("OriginalVolume", audioProperties.Volume or audio.Volume)
	audio.Volume *= AudioService.SoundSetting

	local parentObject = getObjectFromContainer(container)
	audio.Parent = parentObject
	
	table.insert(AudioService.ActiveAudios, audio)

	return audio, container
end

-- Creates a new audio object and immediately plays it once loaded
--[[
params:
	reference:		[number] | string]
	container:		[vector3 | cframe | instance] (where the audio gets stored)
	properties?: 	[table]
		audio?:		[table]	(audio property mapping)
		effect?:	[table]	(effect objects and their property mapping)
		play?:		[table] (custom properties for play behavior)
	serverOverride?:[boolean] (plays the sound on the server, not recommended as there is no volume control for each client)
	
return~ [instance], [instance]
]]
function AudioService.Play(reference, container, properties, serverOverride)
	if IsServer and not serverOverride then
		Signal:FireAllClients("Play", reference, container, properties)
		return
	end
	
	properties = properties or {}
	
	local audioProperties = properties.audio or {}
	local effectProperties = properties.effects or {}
	local playProperties = properties.play or {}
	
	local audio, parentObject = AudioService.Create(reference, container, audioProperties, effectProperties)
	local parentWasCreated = (container ~= parentObject)

	if audio.TimeLength == 0 then
		print'wait for load'
		audio:GetPropertyChangedSignal("TimeLength"):Wait()
		print'loaded'
	end

	if playProperties.Duration then
		audio.PlaybackSpeed = audio.TimeLength / playProperties.Duration
	end
	
	if playProperties.LoopCount then
		assert(audioProperties.Looped, "Audio must have looped property to use 'LoopCount'")
		
		local loopCount = 0
		
		local loopConnection
		loopConnection = audio.Looped:Connect(function()
			loopCount += 1
			
			if playProperties.LoopCount == loopCount then
				loopConnection:Disconnect()
				
				audio:Stop()
				internalDestroyAudio(audio, parentObject, parentWasCreated)
			end
		end)
	end
	
	if not audioProperties.Looped then
		audio.Ended:Once(function()
			internalDestroyAudio(audio, parentObject, parentWasCreated)
		end)
	end

	audio:Play()
	
	return audio, parentObject
end

-- Adjusts the sound volume of all currently active sounds and future sounds
--[[
params:
	settingMultiplier	[number]
]]
function AudioService.AdjustSoundSetting(settingMultiplier)
	AudioService.SoundSetting = settingMultiplier
	
	for _,audio in AudioService.ActiveAudios do
		audio.Volume = audio:GetAttribute("OriginalVolume") * AudioService.SoundSetting
	end
end

-- Get stored reference from AudioRegistry
--[[
params:
	reference	[number | string]
	
return~ [instance]
]]
function AudioService.GetRegisteredAudioObject(reference)
	reference = tostring(reference)
	
	local referencedSound = AudioService.AudioRegistry[reference]
	if referencedSound then
		local id = nil
		
		if typeof(referencedSound) == "Instance" then
			return referencedSound
		else
			id = tostring(referencedSound):match("%d+")
			
			local audio = Instance.new("Sound")
			audio.SoundId = "rbxassetid://"..id

			return audio
		end
	end
		
	return nil
end

-- Store a reference to an audio id or instance, clones itself automatically to client if run on server
--[[
params:
	reference	[number | string]
	audio		[number | string | instance]	
]]
function AudioService.RegisterAudio(reference, audio)
	if IsServer then
		Signal:FireAllClients("RegisterAudio", reference, audio)
	end
	
	reference = tostring(reference)
	
	if not AudioService.AudioRegistry[reference] then
		AudioService.AudioRegistry[reference] = audio
	else
		warn(reference, audio, " was already registered in AudioService")
	end
end

if IsClient then
	-- Convert server functions to client functions
	Signal.OnClientEvent:Connect(function(func, ...)
		if AudioService[func] then
			AudioService[func](...)
		end
	end)
	
	-- Tell server client has loaded
	Signal:FireServer("Loaded")
elseif IsServer then
	-- Flag when client is loaded
	Signal.OnServerEvent:Connect(function(player, action)
		if action == "Loaded" then
			AudioService._LoadedClients[player] = true
		end
	end)
	
	-- Any server registered audios should be replicated to new client
	Players.PlayerAdded:Connect(function(player)
		repeat task.wait() until AudioService._LoadedClients[player]
		
		for reference, audio in AudioService.AudioRegistry do
			Signal:FireClient(player, "RegisterAudio", reference, audio)
		end
	end)
	
	-- Clean up player table memory
	Players.PlayerRemoving:Connect(function(player)
		AudioService._LoadedClients[player] = nil
	end)
end

return AudioService
