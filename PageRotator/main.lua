-- Xournal++ PageRotator plugin
-- Rotates the PDF background of the currently opened document using qpdf.
-- The original PDF is backed up before being overwritten.

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function isWindows()
    return package.config:sub(1, 1) == "\\"
end

-- Debug log so we can diagnose what happens in the GUI-spawned Xournal++
-- process where stdout is not visible.
local LOG_PATH = (function()
    if package.config:sub(1, 1) == "\\" then
        return (os.getenv("USERPROFILE") or "C:\\") .. "\\PageRotator.log"
    end
    return (os.getenv("HOME") or "/tmp") .. "/PageRotator.log"
end)()
local function log(msg)
    local f = io.open(LOG_PATH, "a")
    if f then
        f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(msg) .. "\n")
        f:close()
    end
end

-- Absolute paths for gzip/gunzip so they work under a minimal launchd PATH.
local function gzipBin()
    if isWindows() then return "gzip" end
    local f = io.open("/usr/bin/gzip", "rb")
    if f then f:close(); return "/usr/bin/gzip" end
    return "gzip"
end
local function gunzipBin()
    if isWindows() then return "gunzip" end
    local f = io.open("/usr/bin/gunzip", "rb")
    if f then f:close(); return "/usr/bin/gunzip" end
    return "gunzip"
end

local function fileExists(path)
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

-- Glob a directory pattern in Lua via the shell. Returns the first match
-- that exists, or nil.
local function firstGlob(patterns)
    if not patterns or #patterns == 0 then return nil end
    local cmd
    if isWindows() then
        -- Use PowerShell so we can resolve wildcards predictably
        local joined = ""
        for _, p in ipairs(patterns) do
            joined = joined .. "'" .. p:gsub("'", "''") .. "',"
        end
        cmd = "powershell -NoProfile -Command \"@(" .. joined ..
              ") | ForEach-Object { Get-ChildItem -Path $_ -ErrorAction SilentlyContinue } | " ..
              "Select-Object -First 1 -ExpandProperty FullName\""
    else
        cmd = "ls -1 " .. table.concat(patterns, " ") .. " 2>/dev/null | head -n1"
    end
    local h = io.popen(cmd, "r")
    if not h then return nil end
    local line = h:read("*l")
    h:close()
    if line and line ~= "" then return line end
    return nil
end

-- Resolve `qpdf` even when GUI-spawned apps have a minimal PATH (typical on
-- macOS: /opt/homebrew/bin is missing; on Windows: launchers don't inherit
-- the chocolatey PATH right after install).
local function resolveQpdf()
    local candidates
    if isWindows() then
        candidates = {
            "C:\\ProgramData\\chocolatey\\bin\\qpdf.exe", -- Choco shim
            "C:\\Program Files\\qpdf\\bin\\qpdf.exe",
            "C:\\Program Files (x86)\\qpdf\\bin\\qpdf.exe",
            "C:\\msys64\\usr\\bin\\qpdf.exe",
        }
    else
        candidates = {
            "/opt/homebrew/bin/qpdf",  -- macOS arm64 Homebrew
            "/usr/local/bin/qpdf",     -- macOS Intel Homebrew, common Linux
            "/usr/bin/qpdf",           -- system package managers
            "/opt/local/bin/qpdf",     -- MacPorts
        }
    end
    for _, path in ipairs(candidates) do
        if fileExists(path) then return path end
    end
    -- Fallback: try PATH lookup via shell
    local lookup
    if isWindows() then
        lookup = "where qpdf 2>NUL"
    else
        lookup = "command -v qpdf 2>/dev/null"
    end
    local handle = io.popen(lookup, "r")
    if handle then
        local found = handle:read("*l")
        handle:close()
        if found and found ~= "" and fileExists(found) then
            return found
        end
    end
    -- Windows: try chocolatey's versioned lib dir (e.g.
    --   C:\ProgramData\chocolatey\lib\qpdf\tools\qpdf-12.x.x\bin\qpdf.exe)
    if isWindows() then
        local globbed = firstGlob({
            "C:\\ProgramData\\chocolatey\\lib\\qpdf\\tools\\*\\bin\\qpdf.exe",
            "C:\\ProgramData\\chocolatey\\lib\\qpdf*\\tools\\bin\\qpdf.exe",
        })
        if globbed then return globbed end
        return "qpdf.exe"  -- final fallback, trust PATH at exec time
    end
    return nil
end

local function shellQuote(s)
    if isWindows() then
        -- Wrap in double quotes and escape inner double quotes
        return '"' .. s:gsub('"', '\\"') .. '"'
    end
    return "'" .. s:gsub("'", [['\'']]) .. "'"
end

-- ---------------------------------------------------------------------------
-- Gzip helpers (cross-platform). Windows has no gzip/gunzip out of the box,
-- so we fall back to a tiny PowerShell script using .NET GZipStream.
-- ---------------------------------------------------------------------------

local function tmpDir()
    if isWindows() then
        return os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
    end
    return os.getenv("TMPDIR") or "/tmp"
end

local function pathSep()
    return isWindows() and "\\" or "/"
end

local function decompressGzipFile(srcPath)
    if isWindows() then
        local outFile = tmpDir() .. pathSep() .. "PageRotator_xml.txt"
        local scriptFile = tmpDir() .. pathSep() .. "PageRotator_decompress.ps1"
        local script = string.format(
            '$b=[IO.File]::ReadAllBytes(%q)\n' ..
            '$ms=New-Object IO.MemoryStream\n' ..
            '$ms.Write($b,0,$b.Length)\n' ..
            '$ms.Position=0\n' ..
            '$gz=New-Object IO.Compression.GZipStream($ms,[IO.Compression.CompressionMode]::Decompress)\n' ..
            '$sr=New-Object IO.StreamReader($gz,[Text.Encoding]::UTF8)\n' ..
            '[IO.File]::WriteAllText(%q,$sr.ReadToEnd(),[Text.Encoding]::UTF8)\n',
            srcPath, outFile
        )
        local f = io.open(scriptFile, "w")
        if not f then return nil, "cannot write ps1" end
        f:write(script); f:close()
        local cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' .. scriptFile .. '"'
        local rc = os.execute(cmd)
        os.remove(scriptFile)
        if rc ~= true and rc ~= 0 then return nil, "powershell decompress failed" end
        local r = io.open(outFile, "rb")
        if not r then return nil, "cannot read decompressed tmp" end
        local content = r:read("*a"); r:close()
        os.remove(outFile)
        if not content or content == "" then return nil, "decompressed empty" end
        return content
    end
    local h = io.popen(gunzipBin() .. " -c " .. shellQuote(srcPath), "r")
    if not h then return nil, "gunzip popen failed" end
    local content = h:read("*a")
    h:close()
    if not content or content == "" then return nil, "decompressed empty" end
    return content
end

local function compressGzipFile(content, dstPath)
    if isWindows() then
        local inFile = tmpDir() .. pathSep() .. "PageRotator_in.xml"
        local scriptFile = tmpDir() .. pathSep() .. "PageRotator_compress.ps1"
        local fi = io.open(inFile, "wb")
        if not fi then return false, "cannot write tmp in" end
        fi:write(content); fi:close()
        local script = string.format(
            '$bytes=[IO.File]::ReadAllBytes(%q)\n' ..
            '$fs=[IO.File]::Create(%q)\n' ..
            '$gz=New-Object IO.Compression.GZipStream($fs,[IO.Compression.CompressionMode]::Compress)\n' ..
            '$gz.Write($bytes,0,$bytes.Length)\n' ..
            '$gz.Close()\n' ..
            '$fs.Close()\n',
            inFile, dstPath
        )
        local f = io.open(scriptFile, "w")
        if not f then return false, "cannot write ps1" end
        f:write(script); f:close()
        local cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' .. scriptFile .. '"'
        local rc = os.execute(cmd)
        os.remove(scriptFile)
        os.remove(inFile)
        if rc ~= true and rc ~= 0 then return false, "powershell compress failed" end
        return true
    end
    local tmpGz = dstPath .. ".pagerotator.tmp.gz"
    local hw = io.popen(gzipBin() .. " -c > " .. shellQuote(tmpGz), "w")
    if not hw then return false, "gzip popen failed" end
    hw:write(content)
    if not hw:close() then os.remove(tmpGz); return false, "gzip write failed" end
    if not os.rename(tmpGz, dstPath) then
        local fi = io.open(tmpGz, "rb")
        if not fi then return false, "rename failed and tmp unreadable" end
        local data = fi:read("*a"); fi:close()
        local fo = io.open(dstPath, "wb")
        if not fo then os.remove(tmpGz); return false, "cannot write final" end
        fo:write(data); fo:close()
        os.remove(tmpGz)
    end
    return true
end

-- Directly rewrite the width/height attributes of selected <page> elements
-- inside a (gzipped) .xopp file. The Xournal++ Lua API does not expose a
-- synchronous "save the changed page size" path, so editing the file on
-- disk before triggering a reload is the most reliable approach.
-- `dims` is a table keyed by 1-based Xournal page index, with values
-- `{ newWidth, newHeight }`. Pages not present in the table keep their
-- original dimensions.
-- This is intentionally global so unit tests can drive it directly.
function editXoppPageDimensions(xoppPath, dims)
    if not xoppPath or xoppPath == "" then
        return false, "no xopp path"
    end

    log("editXopp: start " .. xoppPath)
    local dimsCount = 0
    for k, v in pairs(dims) do
        dimsCount = dimsCount + 1
        log(string.format("  dims[%s] = %sx%s", tostring(k), tostring(v[1]), tostring(v[2])))
    end
    log("  dims count: " .. dimsCount)

    -- 1. Decompress
    local content, err = decompressGzipFile(xoppPath)
    if not content then
        log("  decompress failed: " .. tostring(err))
        return false, err
    end
    log("  decompressed length: " .. #content)

    -- 2. Replace width/height in the n-th <page> element when present in dims
    local idx = 0
    local swappedPages = 0
    content = content:gsub('<page%s+width="([%d%.%-]+)"%s+height="([%d%.%-]+)"',
        function(pw, ph)
            idx = idx + 1
            local d = dims[idx]
            if d then
                swappedPages = swappedPages + 1
                return string.format('<page width="%s" height="%s"',
                    tostring(d[1]), tostring(d[2]))
            end
            return string.format('<page width="%s" height="%s"', pw, ph)
        end)
    log(string.format("  pages found: %d, pages swapped: %d", idx, swappedPages))

    -- 3. Re-compress, overwriting the original
    local okC, errC = compressGzipFile(content, xoppPath)
    if not okC then
        log("  compress failed: " .. tostring(errC))
        return false, errC
    end

    log("  editXopp: done")
    return true
end

local function copyFile(src, dst)
    local fIn = io.open(src, "rb")
    if not fIn then return false, "cannot open source" end
    local fOut = io.open(dst, "wb")
    if not fOut then fIn:close(); return false, "cannot open destination" end
    while true do
        local chunk = fIn:read(64 * 1024)
        if not chunk then break end
        fOut:write(chunk)
    end
    fIn:close()
    fOut:close()
    return true
end

local function errorDialog(msg)
    app.openDialog(msg, {"OK"}, "", true)
end

local function infoDialog(msg)
    app.openDialog(msg, {"OK"}, "")
end

-- ---------------------------------------------------------------------------
-- Core rotation logic
-- ---------------------------------------------------------------------------

local function rotatePages(angle, scope)
    -- angle: 90, -90 or 180  (qpdf accepts +90/-90/+180/+270 etc.)
    -- scope: "current" or "all"

    log(string.format("rotatePages: angle=%d scope=%s", angle, scope))

    local doc = app.getDocumentStructure()
    local pdfPath = doc.pdfBackgroundFilename
    local xoppPath = doc.xoppFilename
    local currentPage = doc.currentPage
    log("  pdfPath=" .. tostring(pdfPath))
    log("  xoppPath=" .. tostring(xoppPath))
    log("  currentPage=" .. tostring(currentPage))
    if doc.pages and doc.pages[currentPage] then
        local p = doc.pages[currentPage]
        log(string.format("  page[cur]: w=%s h=%s pdfPageNo=%s",
            tostring(p.pageWidth), tostring(p.pageHeight),
            tostring(p.pdfBackgroundPageNo)))
    end

    if not pdfPath or pdfPath == "" then
        errorDialog("This document has no PDF background.\n" ..
            "Page rotation only works for PDF-backed documents.\n\n" ..
            "Use 'File > Annotate PDF' to open a PDF first.")
        return
    end

    if not fileExists(pdfPath) then
        errorDialog("The background PDF could not be found at:\n" .. pdfPath)
        return
    end

    local qpdfBin = resolveQpdf()
    if not qpdfBin then
        errorDialog("qpdf is required but could not be located.\n\n" ..
            "Install it with:\n" ..
            "  Debian/Ubuntu: sudo apt install qpdf\n" ..
            "  Fedora:        sudo dnf install qpdf\n" ..
            "  Arch:          sudo pacman -S qpdf\n" ..
            "  macOS:         brew install qpdf\n" ..
            "  Windows:       choco install qpdf\n\n" ..
            "Searched locations include /opt/homebrew/bin, /usr/local/bin and PATH.")
        return
    end

    -- qpdf needs a signed angle prefix
    local angleStr
    if angle > 0 then angleStr = "+" .. angle
    elseif angle < 0 then angleStr = tostring(angle)
    else angleStr = "+0" end

    local range
    if scope == "all" then
        range = "1-z"
    else
        local pageInfo = doc.pages[currentPage]
        local pdfPageNr = pageInfo and pageInfo.pdfBackgroundPageNo or 0
        if not pdfPageNr or pdfPageNr < 1 then
            errorDialog("The current Xournal page is not backed by a PDF page,\n" ..
                "so it cannot be rotated.")
            return
        end
        range = tostring(pdfPageNr)
    end

    -- Backup the original PDF
    local timestamp = os.date("%Y%m%d-%H%M%S")
    local backupPath = pdfPath .. ".bak-" .. timestamp
    local ok, err = copyFile(pdfPath, backupPath)
    if not ok then
        errorDialog("Failed to create backup of the PDF:\n" .. tostring(err))
        return
    end

    -- Run qpdf with --replace-input so the original path is preserved
    local cmd = string.format(
        "%s --rotate=%s:%s %s --replace-input",
        shellQuote(qpdfBin), angleStr, range, shellQuote(pdfPath)
    )
    if not isWindows() then
        cmd = cmd .. " 2>&1"
    end

    log("  qpdf cmd: " .. cmd)
    local handle = io.popen(cmd, "r")
    local output = ""
    if handle then
        output = handle:read("*a") or ""
        handle:close()
    end
    log("  qpdf output: " .. output)

    if not fileExists(pdfPath) then
        errorDialog("qpdf failed (output file is missing):\n" .. output ..
            "\n\nRestoring backup …")
        copyFile(backupPath, pdfPath)
        return
    end

    -- For 90°/270° we need to swap the Xournal page width/height so the
    -- visible page matches the rotated PDF. The Xournal API has no
    -- reliable synchronous "save with new page size" path, so we edit
    -- the .xopp file directly on disk and then reload it.
    local absAngle = math.abs(angle) % 360
    local needsSwap = (absAngle == 90 or absAngle == 270)

    if not xoppPath or xoppPath == "" or not fileExists(xoppPath) then
        app.refreshPage()
        infoDialog("PDF rotated, but the Xournal document has not been saved\n" ..
            "yet. Please save it (Cmd+S) and reopen to see the new geometry.\n\n" ..
            "PDF backup: " .. backupPath)
        return
    end

    if needsSwap then
        -- Flush any pending Xournal in-memory changes to disk first,
        -- otherwise our direct edits would be overwritten on the next save.
        app.activateAction("save")

        local dims = {}
        if scope == "current" then
            local p = doc.pages[currentPage]
            if p and p.pageWidth and p.pageHeight then
                dims[currentPage] = { p.pageHeight, p.pageWidth }
            end
        else
            for i, page in ipairs(doc.pages) do
                if page.pdfBackgroundPageNo and page.pdfBackgroundPageNo > 0
                    and page.pageWidth and page.pageHeight then
                    dims[i] = { page.pageHeight, page.pageWidth }
                end
            end
        end

        -- Back up the xopp before rewriting it
        copyFile(xoppPath, xoppPath .. ".bak-" .. timestamp)

        local okEdit, errEdit = editXoppPageDimensions(xoppPath, dims)
        if not okEdit then
            errorDialog("Failed to update .xopp dimensions: " ..
                tostring(errEdit) .. "\n\nReverting PDF rotation …")
            copyFile(backupPath, pdfPath)
            return
        end
    end

    -- Force a real reload: open a fresh empty document first, then re-open
    -- the (now edited) xopp. Without this Xournal++ sometimes keeps the
    -- in-memory page geometry instead of reading the on-disk xopp.
    log("  activating new-file to flush in-memory state")
    app.activateAction("new-file")
    log("  openFile " .. tostring(xoppPath))
    app.openFile(xoppPath, currentPage, true)
    log("rotatePages: done")

    infoDialog(string.format(
        "Rotated %s by %d° (qpdf range: %s).\n\nBackup saved at:\n%s\n\nLog: %s",
        scope == "all" and "all PDF pages" or "current page",
        angle, range, backupPath, LOG_PATH
    ))
end

-- ---------------------------------------------------------------------------
-- Callback wrappers (Xournal++ calls named globals)
-- ---------------------------------------------------------------------------

function rotateCurrentCW()  rotatePages(90,  "current") end
function rotateCurrentCCW() rotatePages(-90, "current") end
function rotateCurrent180() rotatePages(180, "current") end
function rotateAllCW()      rotatePages(90,  "all") end
function rotateAllCCW()     rotatePages(-90, "all") end
function rotateAll180()     rotatePages(180, "all") end

-- ---------------------------------------------------------------------------
-- UI registration
-- ---------------------------------------------------------------------------

function initUi()
    app.registerUi({
        menu        = "Rotate current PDF page 90° clockwise",
        callback    = "rotateCurrentCW",
        accelerator = "<Control><Shift>r",
    })
    app.registerUi({
        menu     = "Rotate current PDF page 90° counter-clockwise",
        callback = "rotateCurrentCCW",
    })
    app.registerUi({
        menu     = "Rotate current PDF page 180°",
        callback = "rotateCurrent180",
    })
    app.registerUi({
        menu     = "Rotate ALL PDF pages 90° clockwise",
        callback = "rotateAllCW",
    })
    app.registerUi({
        menu     = "Rotate ALL PDF pages 90° counter-clockwise",
        callback = "rotateAllCCW",
    })
    app.registerUi({
        menu     = "Rotate ALL PDF pages 180°",
        callback = "rotateAll180",
    })
end
