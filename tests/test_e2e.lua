-- End-to-end test: run a real rotation through the plugin against real
-- fixture files (PDF + xopp). Verifies that the PDF actually gets a
-- rotation flag set and that the xopp on disk has its page dimensions
-- swapped after the rotation. The Xournal UI calls (setCurrentPage,
-- openFile, activateAction) are mocked, but qpdf and gzip run for real.

package.path = package.path .. ";./?.lua;./tests/?.lua"

local mock = require("tests.mock_app")
_G.app = mock.app

-- Load the plugin so its globals are defined
local chunk = assert(loadfile("PageRotator/main.lua"))
chunk()

local passed, failed = 0, 0
local function run(name, fn)
    local ok, e = pcall(fn)
    if ok then passed = passed + 1; io.write("  ok  " .. name .. "\n")
    else failed = failed + 1; io.write("  FAIL " .. name .. "\n      " .. tostring(e) .. "\n") end
end

local function shellQuote(s) return "'" .. s:gsub("'", [['\'']]) .. "'" end

local function readGz(path)
    local h = io.popen("gunzip -c " .. shellQuote(path), "r")
    local s = h:read("*a"); h:close(); return s
end

local function pageDimensionsOf(xoppPath)
    local text = readGz(xoppPath)
    local result = {}
    for w, h in text:gmatch('<page%s+width="([%d%.%-]+)"%s+height="([%d%.%-]+)"') do
        result[#result + 1] = { tonumber(w), tonumber(h) }
    end
    return result
end

local function pdfRotations(pdfPath)
    local h = io.popen("python3 -c '" ..
        "import pypdf, sys; r = pypdf.PdfReader(\"" .. pdfPath .. "\"); " ..
        "print(\",\".join(str(p.rotation) for p in r.pages))'", "r")
    local s = h:read("*a"); h:close()
    s = (s or ""):gsub("%s+$", "")
    local result = {}
    for n in s:gmatch("[^,]+") do result[#result + 1] = tonumber(n) end
    return result
end

-- ---------------------------------------------------------------------------
-- Fixture setup
-- ---------------------------------------------------------------------------

local FIX = "tests/fixtures"
local SRC_PDF = FIX .. "/portrait.pdf"
local SRC_XOPP = FIX .. "/sample.xopp"

local function prepareScenario(scenarioPdf, scenarioXopp)
    os.execute("cp " .. SRC_PDF .. " " .. scenarioPdf)
    os.execute("cp " .. SRC_XOPP .. " " .. scenarioXopp)
end

print("== End-to-end rotation tests ==")

run("rotate current page 90° CW: PDF has /Rotate=90 on page 1 only, xopp p1 swapped", function()
    local pdf = FIX .. "/e2e_current.pdf"
    local xopp = FIX .. "/e2e_current.xopp"
    prepareScenario(pdf, xopp)
    -- Patch the sample xopp to reference our scenario pdf path
    -- (the editor only touches <page> tags, so this is independent)

    mock.reset()
    mock.docStructure = {
        pages = {
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 1 },
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 2 },
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 3 },
        },
        currentPage = 1,
        pdfBackgroundFilename = pdf,
        xoppFilename = xopp,
    }
    rotateCurrentCW()

    -- PDF: page 1 should now have rotation=90, others 0
    local rots = pdfRotations(pdf)
    if rots[1] ~= 90 then error("page 1 not rotated: " .. tostring(rots[1])) end
    if rots[2] ~= 0 then error("page 2 unexpectedly rotated: " .. tostring(rots[2])) end
    if rots[3] ~= 0 then error("page 3 unexpectedly rotated: " .. tostring(rots[3])) end

    -- xopp: page 1 should have swapped dims, others unchanged
    local dims = pageDimensionsOf(xopp)
    if math.abs(dims[1][1] - 841.889764) > 0.01 then
        error("xopp p1 width not swapped: " .. tostring(dims[1][1]))
    end
    if math.abs(dims[1][2] - 595.275591) > 0.01 then
        error("xopp p1 height not swapped: " .. tostring(dims[1][2]))
    end
    if math.abs(dims[2][1] - 595.275591) > 0.01 then
        error("xopp p2 changed unexpectedly")
    end
end)

run("rotate all pages 90° CCW: every PDF page rotated, all xopp pages swapped", function()
    local pdf = FIX .. "/e2e_all.pdf"
    local xopp = FIX .. "/e2e_all.xopp"
    prepareScenario(pdf, xopp)

    mock.reset()
    mock.docStructure = {
        pages = {
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 1 },
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 2 },
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 3 },
        },
        currentPage = 2,
        pdfBackgroundFilename = pdf,
        xoppFilename = xopp,
    }
    rotateAllCCW()

    local rots = pdfRotations(pdf)
    for i, r in ipairs(rots) do
        if r ~= 270 then
            error("page " .. i .. " expected rotation 270, got " .. tostring(r))
        end
    end
    local dims = pageDimensionsOf(xopp)
    for i = 1, 3 do
        if math.abs(dims[i][1] - 841.889764) > 0.01 then
            error("xopp p" .. i .. " width not swapped")
        end
    end
end)

run("rotate 180°: PDF gets /Rotate=180 but xopp dimensions stay the same", function()
    local pdf = FIX .. "/e2e_180.pdf"
    local xopp = FIX .. "/e2e_180.xopp"
    prepareScenario(pdf, xopp)

    mock.reset()
    mock.docStructure = {
        pages = {
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 1 },
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 2 },
            { pageWidth = 595.275591, pageHeight = 841.889764, pdfBackgroundPageNo = 3 },
        },
        currentPage = 1,
        pdfBackgroundFilename = pdf,
        xoppFilename = xopp,
    }
    rotateCurrent180()

    local rots = pdfRotations(pdf)
    if rots[1] ~= 180 then error("page 1 rotation: " .. tostring(rots[1])) end

    local dims = pageDimensionsOf(xopp)
    -- dimensions must be UNCHANGED for 180°
    if math.abs(dims[1][1] - 595.275591) > 0.01 then
        error("xopp p1 width changed for 180°: " .. tostring(dims[1][1]))
    end
    if math.abs(dims[1][2] - 841.889764) > 0.01 then
        error("xopp p1 height changed for 180°: " .. tostring(dims[1][2]))
    end
end)

print(string.format("\n== %d passed, %d failed ==", passed, failed))
os.exit(failed == 0 and 0 or 1)
