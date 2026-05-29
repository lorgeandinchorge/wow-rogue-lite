local played = {}

local function resetHarness(selectedSound)
    played = {}
    WRL_DB = {
        settings = {
            deathSound = selectedSound or "dark_souls",
        },
    }

    _G.PlaySoundFile = function(path, channel)
        played[#played + 1] = { path = path, channel = channel }
    end
    _G.math.random = function(max)
        return max
    end

    local ns = {
        Settings = {},
        Debug = function() end,
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns.Settings:Get(key, default)
        local value = WRL_DB.settings[key]
        if value == nil then return default end
        return value
    end

    assert(loadfile("Core/Death.lua"))("WoWRoguelite", ns)
    return ns
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, message)
    if not value then error(message .. ": expected truthy value", 2) end
end

local function testDeathSoundOptionsExposeShippedSounds()
    local ns = resetHarness()
    local options = ns.Death:DeathSoundOptions()

    assertEqual(options[1].id, "off", "first sound option is off")
    assertEqual(options[2].id, "random", "second sound option is random")
    assertTrue(ns.Death:DeathSoundLabel("dark_souls"):find("Dark Souls", 1, true), "Dark Souls option is labeled")
    assertTrue(ns.Death:DeathSoundPath("dark_souls_alt"):find("%(1%)", 1) ~= nil, "duplicate Dark Souls sound is also exposed")
    assertTrue(ns.Death:DeathSoundPath("dark_souls"):find("sounds\\dark%-souls", 1) ~= nil, "Dark Souls option points at bundled sound")
end

local function testSelectedDeathSoundPlaysOnMasterChannel()
    local ns = resetHarness("dark_souls")

    ns.Death:PlayDeathSound()

    assertEqual(#played, 1, "selected sound plays once")
    assertTrue(played[1].path:find("dark%-souls", 1) ~= nil, "selected sound path is used")
    assertEqual(played[1].channel, "Master", "death sound uses Master channel")
end

local function testOffDeathSoundDoesNotPlay()
    local ns = resetHarness("off")

    ns.Death:PlayDeathSound()

    assertEqual(#played, 0, "off setting suppresses death sound")
end

local function testRandomDeathSoundChoosesPlayableOption()
    local ns = resetHarness("random")

    ns.Death:PlayDeathSound()

    assertEqual(#played, 1, "random setting plays one sound")
    assertTrue(played[1].path:find("super%-mario", 1) ~= nil, "random chooses from playable options")
end

testDeathSoundOptionsExposeShippedSounds()
testSelectedDeathSoundPlaysOnMasterChannel()
testOffDeathSoundDoesNotPlay()
testRandomDeathSoundChoosesPlayableOption()

print("DeathSound.test.lua: ok")
