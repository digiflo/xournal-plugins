-- luacheck config for the Xournal++ PageRotator plugin
std = "lua54"

-- Xournal++ exposes a global `app` table to plugins and calls
-- the named globals `initUi` and the registered callbacks.
read_globals = { "app" }
globals = {
    "initUi",
    "rotateCurrentCW",
    "rotateCurrentCCW",
    "rotateCurrent180",
    "rotateAllCW",
    "rotateAllCCW",
    "rotateAll180",
    "editXoppPageDimensions",
}

-- Allow longer lines for readability
max_line_length = 120
