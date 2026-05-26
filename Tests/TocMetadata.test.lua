local function readFile(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

local toc = readFile("WoWRoguelite.toc")
local interface = toc:match("##%s*Interface:%s*([^\r\n]+)")
if interface ~= "20505" then
    error(("expected WoWRoguelite.toc Interface 20505, got %s"):format(tostring(interface)), 2)
end

local tocVersion = toc:match("##%s*Version:%s*([^\r\n]+)")
if tocVersion ~= "0.4.0" then
    error(("expected WoWRoguelite.toc Version 0.4.0, got %s"):format(tostring(tocVersion)), 2)
end

local lua = readFile("WoWRoguelite.lua")
local luaVersion = lua:match('ns%.version%s*=%s*"([^"]+)"')
if luaVersion ~= tocVersion then
    error(("expected WoWRoguelite.lua ns.version to match toc Version %s, got %s"):format(tostring(tocVersion), tostring(luaVersion)), 2)
end

local loansPos = toc:find("Core/Loans.lua", 1, true)
local contributionsPos = toc:find("Core/Contributions.lua", 1, true)
if not loansPos then
    error("expected WoWRoguelite.toc to load Core/Loans.lua", 2)
end
if not contributionsPos or loansPos > contributionsPos then
    error("expected Core/Loans.lua to load before Core/Contributions.lua", 2)
end

print("TocMetadata.test.lua: ok")
