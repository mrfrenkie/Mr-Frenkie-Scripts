-- Frenkie Item Properties 2.7

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

local _, _, sectionID, cmdID = reaper.get_action_context()
if sectionID and cmdID ~= 0 then
    reaper.SetToggleCommandState(sectionID, cmdID, 1)
    reaper.RefreshToolbar2(sectionID, cmdID)
    reaper.atexit(function()
        reaper.SetToggleCommandState(sectionID, cmdID, 0)
        reaper.RefreshToolbar2(sectionID, cmdID)
    end)
end

dofile(script_dir .. "UI.lua")
