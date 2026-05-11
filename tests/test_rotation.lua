-- Unit tests for the Xournal++ PageRotator plugin.
-- Loads main.lua against a mocked `app` table and asserts on the
-- recorded API call trace.

package.path = package.path .. ";./?.lua;./tests/?.lua"

local mock = require("tests.mock_app")

local failures = 0
local passed = 0

-- Spy that captures calls to the plugin's editXoppPageDimensions so we can
-- assert the rotation logic without actually mutating files on disk.
local editorSpy = { calls = {} }
local function installEditorSpy()
    editorSpy.calls = {}
    _G.editXoppPageDimensions = function(path, dims)
        local copy = {}
        for k, v in pairs(dims) do copy[k] = { v[1], v[2] } end
        editorSpy.calls[#editorSpy.calls + 1] = { path = path, dims = copy }
        return true
    end
end

local function loadPlugin()
    -- Each test gets a fresh chunk so module-level state resets.
    mock.reset()
    _G.app = mock.app
    local chunk, err = loadfile("PageRotator/main.lua")
    if not chunk then error("Cannot load plugin: " .. tostring(err)) end
    -- The plugin file defines globals (initUi, rotate*, editXoppPageDimensions).
    chunk()
    installEditorSpy()
end

local function assertEq(actual, expected, msg)
    if actual ~= expected then
        error(string.format("%s\n  expected: %s\n  actual:   %s",
            msg or "assertion failed", tostring(expected), tostring(actual)), 2)
    end
end

local function findCall(name, after)
    after = after or 0
    for i = after + 1, #mock.calls do
        if mock.calls[i].name == name then return i, mock.calls[i] end
    end
    return nil
end

local function countCalls(name)
    local n = 0
    for _, c in ipairs(mock.calls) do
        if c.name == name then n = n + 1 end
    end
    return n
end

-- Isolated, throw-away copies of the fixtures. Re-created for every test
-- so the unit suite never mutates the master fixtures.
local UNIT_PDF = "tests/fixtures/_unit_pdf.pdf"
local UNIT_XOPP = "tests/fixtures/_unit_xopp.xopp"

local function freshFixtures()
    os.execute("cp tests/fixtures/portrait.pdf " .. UNIT_PDF .. " 2>/dev/null")
    os.execute("cp tests/fixtures/sample.xopp " .. UNIT_XOPP .. " 2>/dev/null")
end

local function makeDoc(pageDims, currentPage, withPdf)
    freshFixtures()
    local pages = {}
    for i, dim in ipairs(pageDims) do
        pages[i] = {
            pageWidth = dim[1],
            pageHeight = dim[2],
            pdfBackgroundPageNo = withPdf and i or 0,
        }
    end
    return {
        pages = pages,
        currentPage = currentPage or 1,
        pdfBackgroundFilename = withPdf and UNIT_PDF or "",
        xoppFilename = UNIT_XOPP,
    }
end

local function run(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        io.write(string.format("  ok  %s\n", name))
    else
        failures = failures + 1
        io.write(string.format("  FAIL %s\n      %s\n", name, tostring(err)))
    end
end

-- ---------------------------------------------------------------------------
-- Tests
-- ---------------------------------------------------------------------------

print("== PageRotator unit tests ==")

run("initUi registers six menu entries", function()
    loadPlugin()
    initUi()
    assertEq(#mock.registeredMenus, 6, "menu count")
    assertEq(mock.registeredMenus[1].callback, "rotateCurrentCW", "first cb")
    assertEq(mock.registeredMenus[1].accelerator, "<Control><Shift>r", "shortcut")
end)

run("rotate 90° current edits only the current page dimensions", function()
    loadPlugin()
    mock.docStructure = makeDoc({{595, 842}, {595, 842}}, 1, true)
    rotateCurrentCW()
    assertEq(#editorSpy.calls, 1, "edit was called once")
    local dims = editorSpy.calls[1].dims
    -- Only page 1 should be in dims, swapped
    local count = 0; for _ in pairs(dims) do count = count + 1 end
    assertEq(count, 1, "exactly one page entry")
    assertEq(dims[1][1], 842, "new width = old height")
    assertEq(dims[1][2], 595, "new height = old width")
end)

run("rotate 180° does NOT edit xopp dimensions", function()
    loadPlugin()
    mock.docStructure = makeDoc({{595, 842}}, 1, true)
    rotateCurrent180()
    assertEq(#editorSpy.calls, 0, "no xopp edit for 180°")
    -- but the document must still be reloaded so the rotated PDF shows up
    if not findCall("openFile") then error("openFile not called for 180°") end
end)

run("rotate 90° all swaps dimensions for every PDF-backed page", function()
    loadPlugin()
    mock.docStructure = makeDoc({{595, 842}, {595, 842}, {595, 842}}, 2, true)
    rotateAllCW()
    assertEq(#editorSpy.calls, 1, "edit called once")
    local dims = editorSpy.calls[1].dims
    for i = 1, 3 do
        if not dims[i] then error("missing dim entry for page " .. i) end
        assertEq(dims[i][1], 842, "page " .. i .. " width swapped")
        assertEq(dims[i][2], 595, "page " .. i .. " height swapped")
    end
end)

run("rotate fails gracefully when no PDF background", function()
    loadPlugin()
    mock.docStructure = makeDoc({{595, 842}}, 1, false)
    rotateCurrentCW()
    if not mock.lastDialog or not mock.lastDialog.isError then
        error("expected an error dialog")
    end
    assertEq(#editorSpy.calls, 0, "no xopp edit attempted")
end)

run("flow order is save → editXopp → openFile", function()
    loadPlugin()
    mock.docStructure = makeDoc({{595, 842}, {595, 842}}, 1, true)
    rotateCurrentCW()

    -- Find save call
    local saveIdx
    for i, c in ipairs(mock.calls) do
        if c.name == "activateAction" and c.args[1] == "save" then
            saveIdx = i; break
        end
    end
    if not saveIdx then error("missing save action") end

    -- Find openFile call
    local openIdx
    for i, c in ipairs(mock.calls) do
        if c.name == "openFile" then openIdx = i; break end
    end
    if not openIdx then error("missing openFile") end

    -- editorSpy doesn't go through mock.calls (it's a global spy),
    -- but we can verify it ran at least once and that openFile comes AFTER save.
    assertEq(#editorSpy.calls, 1, "editor was invoked")
    if openIdx <= saveIdx then error("openFile must come after save") end
end)

run("openFile reloads the same xopp path with oldDocument=true", function()
    loadPlugin()
    mock.docStructure = makeDoc({{595, 842}}, 1, true)
    rotateCurrentCW()
    local _, c = findCall("openFile")
    if not c then error("openFile not called") end
    assertEq(c.args[1], UNIT_XOPP, "reload same xopp path")
    assertEq(c.args[3], true, "oldDocument=true to skip save prompt")
end)

-- ---------------------------------------------------------------------------
print(string.format("\n== %d passed, %d failed ==", passed, failures))
os.exit(failures == 0 and 0 or 1)
