-- UI/AddonOptions.lua
-- Registers WoW Roguelite under Interface Options > AddOns.

local ADDON_NAME, ns = ...
local Options = ns:NewModule("AddonOptions")

function Options:Init()
    if self.panel then return end

    local panel = CreateFrame("Frame", "WRL_InterfaceOptionsPanel")
    panel.name = "WoW Roguelite"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("WoW Roguelite")

    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    status:SetWidth(560)
    status:SetJustifyH("LEFT")
    status:SetText("WoW Roguelite is loaded. Use /wrl, the minimap button, or the buttons below to open the addon.")

    local openMain = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openMain:SetSize(150, 24)
    openMain:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -18)
    openMain:SetText("Open WRL")
    openMain:SetScript("OnClick", function()
        if ns.MainFrame then
            ns.MainFrame:Toggle()
        end
    end)

    local openSettings = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    openSettings:SetSize(150, 24)
    openSettings:SetPoint("LEFT", openMain, "RIGHT", 12, 0)
    openSettings:SetText("WRL Settings")
    openSettings:SetScript("OnClick", function()
        if ns.SettingsPopup then
            ns.SettingsPopup:Show()
        end
    end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    hint:SetPoint("TOPLEFT", openMain, "BOTTOMLEFT", 0, -16)
    hint:SetWidth(560)
    hint:SetJustifyH("LEFT")
    hint:SetText("Gameplay rules and general addon preferences live in the /wrl gear Settings popup.")

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    end

    self.panel = panel
end
