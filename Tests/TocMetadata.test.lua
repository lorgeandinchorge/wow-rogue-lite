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

print("TocMetadata.test.lua: ok")
