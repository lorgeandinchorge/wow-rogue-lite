local currentGuid = "Player-1-OLD"

local function resetHarness()
    WRL_DB = {
        characters = {
            ["Runner-Realm"] = {
                key = "Runner-Realm",
                uid = "Runner-Realm#100",
                createdAt = 100,
                generation = 1,
                isArchived = false,
                class = "WARRIOR",
                race = "HUMAN",
                levelAtCreate = 12,
                levelCurrent = 12,
                status = "retired",
                deathLog = {},
            },
        },
    }

    currentGuid = "Player-1-NEW"

    _G.time = function() return 200 end
    _G.UnitLevel = function() return 1 end
    _G.UnitClass = function() return nil, "WARRIOR" end
    _G.UnitRace = function() return nil, "HUMAN" end
    _G.UnitGUID = function(unit)
        return unit == "player" and currentGuid or nil
    end

    local ns = {}
    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end
    function ns:Print() end
    function ns:Debug() end
    function ns:UnitKey() return "Runner-Realm" end

    assert(loadfile("Core/Database.lua"))("WoWRoguelite", ns)
    return ns.Database
end

local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function testGuidChangeArchivesSameNameSameClassRecord()
    local db = resetHarness()
    WRL_DB.characters["Runner-Realm"].playerGuid = "Player-1-OLD"

    local rec = db:EnsureCharacter("Runner-Realm")

    assertEqual(rec.uid, "Runner-Realm#200", "new same-name same-class character gets fresh uid")
    assertEqual(rec.playerGuid, "Player-1-NEW", "new character stores player guid")
    assertEqual(rec.generation, 2, "new character increments generation")
    assertEqual(WRL_DB.characters["Runner-Realm#100"].isArchived, true,
        "old same-name record is archived")
end

local function testMissingStoredGuidIsBackfilledWithoutArchiving()
    local db = resetHarness()

    local rec = db:EnsureCharacter("Runner-Realm")

    assertEqual(rec.uid, "Runner-Realm#100", "old record without guid is retained")
    assertEqual(rec.playerGuid, "Player-1-NEW", "old record stores guid for future detection")
    assertEqual(WRL_DB.characters["Runner-Realm#100"], nil,
        "old record without guid is not archived on first guid-aware login")
end

testGuidChangeArchivesSameNameSameClassRecord()
testMissingStoredGuidIsBackfilledWithoutArchiving()

print("CharacterIdentity.test.lua: ok")
