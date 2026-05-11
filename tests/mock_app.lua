-- Mock of the Xournal++ Lua plugin API for tests.
-- It records every call so tests can assert on them.

local M = {}
M.calls = {}
M.registeredMenus = {}
M.lastDialog = nil

-- State that the plugin reads
M.docStructure = nil
M.currentPage = 1

local function record(name, ...)
    local args = {...}
    table.insert(M.calls, { name = name, args = args })
end

function M.reset()
    M.calls = {}
    M.registeredMenus = {}
    M.lastDialog = nil
end

-- The `app` table that the plugin uses
local app = {}

function app.registerUi(opts)
    table.insert(M.registeredMenus, opts)
    return { menuId = #M.registeredMenus }
end

function app.getDocumentStructure()
    record("getDocumentStructure")
    return M.docStructure
end

function app.setCurrentPage(pageNr)
    record("setCurrentPage", pageNr)
    M.currentPage = pageNr
    if M.docStructure then M.docStructure.currentPage = pageNr end
end

function app.setPageSize(w, h, relative)
    record("setPageSize", w, h, relative)
    if M.docStructure and M.docStructure.pages[M.currentPage] then
        local p = M.docStructure.pages[M.currentPage]
        if relative then
            p.pageWidth = (p.pageWidth or 0) + w
            p.pageHeight = (p.pageHeight or 0) + h
        else
            p.pageWidth = w
            p.pageHeight = h
        end
    end
end

function app.activateAction(action, state)
    record("activateAction", action, state)
end

function app.refreshPage()
    record("refreshPage")
end

function app.openFile(path, pageNr, oldDocument)
    record("openFile", path, pageNr, oldDocument)
    return true
end

function app.openDialog(message, options, callback, isError)
    record("openDialog", message, options, callback, isError)
    M.lastDialog = {
        message = message,
        options = options,
        callback = callback,
        isError = isError,
    }
end

M.app = app

return M
