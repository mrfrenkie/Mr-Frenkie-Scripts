-- @description Item Properties
-- @version 4.0b
-- @author Mr. Frenkie
-- @changelog
--   Added:
--   - Track Snapshots
-- @metapackage
-- @provides
--   [darwin-arm64 main] .
--   [win64 main] .
--   [darwin-arm64 nomain] ItemProperties/*
--   [win64 nomain] ItemProperties/*
--   [darwin-arm64 nomain] ItemProperties/icons/*
--   [win64 nomain] ItemProperties/icons/*
--   [darwin-arm64 nomain] ItemProperties/fonts/*
--   [win64 nomain] ItemProperties/fonts/*
--   [darwin-arm64 extension] ../../../../UserPlugins/reaper_frenkie_core.dylib > reaper_frenkie_core.dylib
--   [win64 extension] ../../../../UserPlugins/reaper_frenkie_core.dll > reaper_frenkie_core.dll
-- @link Forum https://forum.cockos.com/
-- @link Repository https://github.com/mrfrenkie/Mr-Frenkie-Scripts
---@diagnostic disable: undefined-global, undefined-field
-- Frenkie Item Properties 4.0b
-- Основной скрипт просто запускает UI модуль

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""
local sep = package.config:sub(1, 1)

local r = reaper
local _, _, sectionID, cmdID = r.get_action_context()
if sectionID and cmdID ~= 0 then
    r.SetToggleCommandState(sectionID, cmdID, 1)
    r.RefreshToolbar2(sectionID, cmdID)
    r.atexit(function()
        r.SetToggleCommandState(sectionID, cmdID, 0)
        r.RefreshToolbar2(sectionID, cmdID)
    end)
end

dofile(script_dir .. "ItemProperties" .. sep .. "UI.lua")
