-- Tests for the xopp-on-disk editor.
-- Verifies that page width/height attributes are swapped only for
-- the requested page numbers and the file remains valid gzip XML.

package.path = package.path .. ";./?.lua;./tests/?.lua"

local mock = require("tests.mock_app")
_G.app = mock.app

local chunk, err = loadfile("PageRotator/main.lua")
if not chunk then error("cannot load plugin: " .. tostring(err)) end
chunk()

local passed, failed = 0, 0
local function run(name, fn)
    local ok, e = pcall(fn)
    if ok then passed = passed + 1; io.write("  ok  " .. name .. "\n")
    else failed = failed + 1; io.write("  FAIL " .. name .. "\n      " .. tostring(e) .. "\n") end
end

local function readGzText(path)
    local h = io.popen("gunzip -c " .. ("'" .. path:gsub("'", "'\\''") .. "'"), "r")
    if not h then return nil end
    local s = h:read("*a"); h:close(); return s
end

local function writeGz(srcXml, dstGz)
    local cmd = "gzip -c '" .. srcXml:gsub("'", "'\\''") .. "' > '" .. dstGz:gsub("'", "'\\''") .. "'"
    return os.execute(cmd)
end

print("== xopp editor tests ==")

local SRC = "tests/fixtures/sample.xopp"
local WORK = "tests/fixtures/work.xopp"

run("editXoppPageDimensions swaps only the requested pages", function()
    -- Re-create a fresh working copy from the gzipped fixture
    os.execute("cp " .. SRC .. " " .. WORK)
    -- Swap pages 1 and 3
    local ok, e = _G.editXoppPageDimensions(WORK, {
        [1] = { 841.889764, 595.275591 },
        [3] = { 841.889764, 595.275591 },
    })
    if not ok then error("editor returned error: " .. tostring(e)) end

    local text = readGzText(WORK)
    if not text then error("could not gunzip work copy") end

    -- count <page width=... height=...> tags and inspect dims
    local widths = {}
    local heights = {}
    for w, h in text:gmatch('<page%s+width="([%d%.]+)"%s+height="([%d%.]+)"') do
        widths[#widths + 1] = tonumber(w)
        heights[#heights + 1] = tonumber(h)
    end
    if #widths ~= 3 then error("expected 3 pages, got " .. #widths) end

    -- page 1: swapped → width≈841, height≈595
    if math.abs(widths[1] - 841.889764) > 0.01 then error("p1 width not swapped: " .. widths[1]) end
    if math.abs(heights[1] - 595.275591) > 0.01 then error("p1 height not swapped: " .. heights[1]) end
    -- page 2: unchanged → 595 / 841
    if math.abs(widths[2] - 595.275591) > 0.01 then error("p2 width changed: " .. widths[2]) end
    if math.abs(heights[2] - 841.889764) > 0.01 then error("p2 height changed: " .. heights[2]) end
    -- page 3: swapped
    if math.abs(widths[3] - 841.889764) > 0.01 then error("p3 width not swapped: " .. widths[3]) end
end)

run("editXoppPageDimensions on all pages", function()
    os.execute("cp " .. SRC .. " " .. WORK)
    local ok = _G.editXoppPageDimensions(WORK, {
        [1] = { 841.889764, 595.275591 },
        [2] = { 841.889764, 595.275591 },
        [3] = { 841.889764, 595.275591 },
    })
    if not ok then error("editor returned error") end
    local text = readGzText(WORK)
    local count = 0
    for _ in text:gmatch('<page%s+width="841') do count = count + 1 end
    if count ~= 3 then error("expected 3 swapped pages, got " .. count) end
end)

run("output remains valid gzip XML (parseable, contains <xournal>)", function()
    os.execute("cp " .. SRC .. " " .. WORK)
    _G.editXoppPageDimensions(WORK, { [2] = { 100, 200 } })
    local text = readGzText(WORK)
    if not text or not text:find("<xournal") then
        error("missing <xournal> root after edit")
    end
    if not text:find('</xournal>') then
        error("missing closing </xournal>")
    end
end)

print(string.format("\n== %d passed, %d failed ==", passed, failed))
os.exit(failed == 0 and 0 or 1)
