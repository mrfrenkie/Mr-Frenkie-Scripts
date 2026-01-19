local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")

local accumulated_pitch = 0
local current_selection = {}
local transpose_drag_active = false
local transpose_drag_start = 0
local transpose_drag_last = 0

local ItemPropsPitch = {}

function ItemPropsPitch.GetPitch(take)
    if not take then return 0 end
    return r.GetMediaItemTakeInfo_Value(take, "D_PITCH")
end

function ItemPropsPitch.SetPitch(take, pitch)
    if not take or pitch == nil then return end
    r.SetMediaItemTakeInfo_Value(take, "D_PITCH", pitch)
end

function ItemPropsPitch.UpdateAccumulatedPitch(pitch_delta)
    accumulated_pitch = accumulated_pitch + pitch_delta
end

function ItemPropsPitch.ResetAccumulatedPitch()
    accumulated_pitch = 0
end

function ItemPropsPitch.GetAccumulatedPitch()
    return accumulated_pitch
end

function ItemPropsPitch.CheckSelectionChange(items)
    local selection_changed = false
    if #current_selection > 0 then
        selection_changed = #items ~= #current_selection
        if not selection_changed then
            for i = 1, #items do
                if items[i] ~= current_selection[i] then
                    selection_changed = true
                    break
                end
            end
        end
    else
        selection_changed = #items > 0
    end
    if selection_changed then
        accumulated_pitch = 0
        current_selection = {}
        for i, item in ipairs(items) do
            current_selection[i] = item
        end
    end
    return selection_changed
end

function ItemPropsPitch.ResetPitch(items)
    Utils.with_undo("Reset Pitch", function()
        for _, item in ipairs(items) do
            if item and r.ValidatePtr(item, "MediaItem*") then
                local take = r.GetActiveTake(item)
                if take then
                    ItemPropsPitch.SetPitch(take, 0)
                end
            end
        end
    end)
    r.UpdateArrange()
end

function ItemPropsPitch.UpdatePitch(items, pitch_delta, base_values)
    if not items or #items == 0 then return end
    for i, item in ipairs(items) do
        if item and r.ValidatePtr(item, "MediaItem*") then
            local take = r.GetActiveTake(item)
            if take then
                local current_pitch = ItemPropsPitch.GetPitch(take)
                local new_pitch = current_pitch + pitch_delta
                new_pitch = math.max(-24, math.min(24, new_pitch))
                ItemPropsPitch.SetPitch(take, new_pitch)
            end
        end
    end
    r.UpdateArrange()
end

function ItemPropsPitch.SetAbsolutePitch(items, pitch)
    if not items or #items == 0 then return end
    for _, item in ipairs(items) do
        if item and r.ValidatePtr(item, "MediaItem*") then
            local take = r.GetActiveTake(item)
            if take then
                local clamped_pitch = math.max(-24, math.min(24, pitch))
                ItemPropsPitch.SetPitch(take, clamped_pitch)
            end
        end
    end
    r.UpdateArrange()
end

function ItemPropsPitch.HandlePitchChange(items, new_pitch, current_pitch, base_values)
    new_pitch = math.floor(new_pitch + 0.5)
    new_pitch = math.max(-48, math.min(48, new_pitch))
    local pitch_delta = new_pitch - (current_pitch or 0)
    if #items > 1 then
        ItemPropsPitch.UpdateAccumulatedPitch(pitch_delta)
    end
    ItemPropsPitch.UpdatePitch(items, pitch_delta, base_values)
    return new_pitch
end

function ItemPropsPitch.FinalizePitchChange()
    Utils.with_undo("Change Pitch", function() end)
end

local function TransposeMIDI_Take(take, interval)
    if not take or interval == 0 then return end
    if not r.TakeIsMIDI(take) then return end
    local ok, midi_string = r.MIDI_GetAllEvts(take, "")
    if not ok then return end
    local len = #midi_string
    local pos = 1
    local events = {}
    while pos < len - 12 do
        local offset, flags, msg
        offset, flags, msg, pos = string.unpack("i4Bs4", midi_string, pos)
        if #msg == 3 then
            local status = (msg:byte(1) >> 4)
            if status == 9 or status == 8 then
                local p = msg:byte(2) + interval
                if p >= 0 and p <= 127 then
                    msg = msg:sub(1,1) .. string.char(p) .. msg:sub(3,3)
                end
            end
        end
        events[#events+1] = string.pack("i4Bs4", offset, flags, msg)
    end
    r.MIDI_SetAllEvts(take, table.concat(events) .. midi_string:sub(-12))
    r.MIDI_Sort(take)
end

local function TransposeMIDIItems(items, interval)
    if not items or #items == 0 or interval == 0 then return end
    for _, item in ipairs(items) do
        if item and r.ValidatePtr(item, "MediaItem*") then
            local take = r.GetActiveTake(item)
            TransposeMIDI_Take(take, interval)
        end
    end
    r.UpdateArrange()
end

function ItemPropsPitch.MIDITransposeDragUpdate(items, new_pitch, current_pitch)
    new_pitch = math.floor(new_pitch + 0.5)
    current_pitch = math.floor((current_pitch or 0) + 0.5)
    if not transpose_drag_active then
        transpose_drag_active = true
        transpose_drag_start = current_pitch
        transpose_drag_last = new_pitch
        return
    end
    transpose_drag_last = new_pitch
end

function ItemPropsPitch.FinalizeMIDITranspose(items)
    if not transpose_drag_active then return end
    local delta = math.floor(transpose_drag_last + 0.5) - math.floor(transpose_drag_start + 0.5)
    transpose_drag_active = false
    transpose_drag_start = 0
    transpose_drag_last = 0
    if delta == 0 then return end
    Utils.with_undo("Transpose MIDI", function()
        TransposeMIDIItems(items, delta)
    end)
end

function ItemPropsPitch.HandlePitchReset(items, base_values)
    ItemPropsPitch.ResetAccumulatedPitch()
    Utils.with_undo("Reset Pitch", function()
        ItemPropsPitch.SetAbsolutePitch(items, 0)
    end)
    if base_values then
        for i, item in ipairs(items) do
            local take = r.GetActiveTake(item)
            if take and base_values[i] then
                base_values[i].pitch = ItemPropsPitch.GetPitch(take)
            end
        end
    end
end

function ItemPropsPitch.RevertAggregatedPitchChanges(items, base_values)
    local delta = -ItemPropsPitch.GetAccumulatedPitch()
    if math.abs(delta) < 0.001 then
        ItemPropsPitch.ResetAccumulatedPitch()
        return
    end
    Utils.with_undo("Reset Pitch", function()
        ItemPropsPitch.UpdatePitch(items, delta, base_values)
    end)
    ItemPropsPitch.ResetAccumulatedPitch()
    if base_values then
        for i, item in ipairs(items) do
            local take = r.GetActiveTake(item)
            if take and base_values[i] then
                base_values[i].pitch = ItemPropsPitch.GetPitch(take)
            end
        end
    end
end

function ItemPropsPitch.GetAggregatedPitch(items)
    if not items or #items == 0 then
        return 0
    end
    if #items == 1 then
        if items[1] and r.ValidatePtr(items[1], "MediaItem*") then
            local take = r.GetActiveTake(items[1])
            return take and ItemPropsPitch.GetPitch(take) or 0
        end
        return 0
    end
    return accumulated_pitch
end

function ItemPropsPitch.GetPitchLabelFlags(items)
    if not items or #items == 0 then
        return false, false
    end
    if #items == 1 then
        local item = items[1]
        if item and r.ValidatePtr(item, "MediaItem*") then
            local take = r.GetActiveTake(item)
            local p = take and ItemPropsPitch.GetPitch(take) or 0
            local is_modified = math.abs(p) > 0.001
            return is_modified, false
        end
        return false, false
    end
    local first_pitch = nil
    local all_equal = true
    local all_zero = true
    for _, item in ipairs(items) do
        if item and r.ValidatePtr(item, "MediaItem*") then
            local take = r.GetActiveTake(item)
            local p = take and ItemPropsPitch.GetPitch(take) or 0
            if first_pitch == nil then
                first_pitch = p
            elseif math.abs(p - first_pitch) > 0.001 then
                all_equal = false
            end
            if math.abs(p) > 0.001 then
                all_zero = false
            end
        end
    end
    if all_zero then
        return false, false
    end
    if all_equal and (math.abs(first_pitch or 0) > 0.001) then
        return true, false
    end
    return false, true
end

function ItemPropsPitch.ClearState()
    accumulated_pitch = 0
    current_selection = {}
    r.UpdateArrange()
end

function ItemPropsPitch.HasModifiedPitchValues(items)
    if not items or #items == 0 then
        return false
    end
    for _, item in ipairs(items) do
        if item and r.ValidatePtr(item, "MediaItem*") then
            local take = r.GetActiveTake(item)
            if take then
                local pitch = ItemPropsPitch.GetPitch(take)
                if math.abs(pitch) > 0.001 then
                    return true
                end
            end
        end
    end
    return false
end

return ItemPropsPitch
