local function assertEqual(actual, expected, message)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)), 2)
    end
end

local function makeFrame()
    local f = {
        scripts = {},
        hidden = true,
    }

    function f:SetFrameStrata() end
    function f:SetAllPoints() end
    function f:EnableMouse() end
    function f:Hide() self.hidden = true end
    function f:Show() self.hidden = false end
    function f:IsShown() return not self.hidden end
    function f:SetColorTexture() end
    function f:SetHeight() end
    function f:SetPoint() end
    function f:SetSize() end
    function f:SetWidth() end
    function f:SetJustifyH() end
    function f:SetTextColor() end
    function f:SetText() end
    function f:SetFont() end
    function f:SetFormattedText(fmt, ...)
        self.text = string.format(fmt, ...)
    end
    function f:CreateTexture() return makeFrame() end
    function f:CreateFontString() return makeFrame() end
    function f:EnableKeyboard() end
    function f:SetScript(name, cb) self.scripts[name] = cb end
    function f:GetScript(name) return self.scripts[name] end

    -- Intentionally no SetPropagateKeyboardInput: older Classic clients may not
    -- expose it, and the death screen must still open.
    return f
end

local function resetHarness()
    local ns = {
        Tiers = {},
    }

    function ns:NewModule(name)
        local module = {}
        self[name] = module
        return module
    end

    function ns:Debug() end

    function ns.Tiers:FormatMoney(copper)
        return tostring(copper) .. "c"
    end

    _G.RAID_CLASS_COLORS = {
        WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    }
    _G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    _G.UIParent = makeFrame()
    _G.CreateFrame = function()
        return makeFrame()
    end

    assert(loadfile("UI/DeathScreen.lua"))("WoWRoguelite", ns)
    return ns
end

local function testDeathScreenShowsWithoutKeyboardPropagationApi()
    local ns = resetHarness()
    local continued = false

    ns.DeathScreen:Show(
        {
            uid = "Runner-Realm#100",
            characterKey = "Runner-Realm",
            class = "WARRIOR",
            race = "HUMAN",
            level = 12,
            zone = "Westfall",
            livesUsed = 1,
        },
        { totalLiquid = 12345 },
        { class = "WARRIOR", race = "HUMAN", levelCurrent = 12 },
        function() continued = true end
    )

    assertEqual(ns.DeathScreen:IsShown(), true,
        "death screen opens without SetPropagateKeyboardInput")

    ns.DeathScreen.frame._btn:GetScript("OnClick")(ns.DeathScreen.frame._btn)
    assertEqual(continued, true, "continue callback fires")
    assertEqual(ns.DeathScreen:IsShown(), false, "death screen hides after continue")
end

local function testDeathScreenToleratesPartialMemorialData()
    local ns = resetHarness()

    ns.DeathScreen:Show(
        {
            uid = "Runner-Realm#100",
            characterKey = "Runner-Realm",
        },
        {},
        {},
        function() end
    )

    assertEqual(ns.DeathScreen:IsShown(), true,
        "death screen opens with partial memorial data")
end

testDeathScreenShowsWithoutKeyboardPropagationApi()
testDeathScreenToleratesPartialMemorialData()

print("DeathScreen.test.lua: ok")
