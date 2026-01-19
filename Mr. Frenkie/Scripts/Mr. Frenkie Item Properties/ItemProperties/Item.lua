local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Core = require("Core")
local Utils = require("Utils")

local Item = {}

function Item.GetSelectedItems()
    local items = {}
    local count = r.CountSelectedMediaItems(0)
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        if item and r.ValidatePtr(item, "MediaItem*") then
            items[#items + 1] = item
        end
    end
    return items
end

function Item.GetTake(item)
    if not item then return nil end
    return r.GetActiveTake(item)
end

function Item.GetTakeType(take)
    if not take then return "Empty" end
    local source = r.GetMediaItemTake_Source(take)
    if not source then return "Empty" end
    local source_type = r.GetMediaSourceType(source, "")
    return source_type == "MIDI" and "MIDI" or "Audio"
end

function Item.GetTakeSourceReverse(take)
    if not take then return false end
    local src = r.GetMediaItemTake_Source(take)
    if not src then return false end
    local ok, offs, len, rev = r.PCM_Source_GetSectionInfo(src)
    if ok then return rev == true end
    return false
end

function Item.IsItemReversed(item)
    if not item or not r.ValidatePtr(item, "MediaItem*") then return false end
    local take = Item.GetTake(item)
    if not take then return false end
    if r.GetMediaItemTakeInfo_Value(take, "B_REVERSE") == 1 then return true end
    if Item.GetTakeSourceReverse(take) then return true end
    return false
end

function Item.ItemHasFX(item)
    if not item then return false end
    local take = Item.GetTake(item)
    if not take then return false end
    return r.TakeFX_GetCount(take) > 0
end

function Item.FormatRateValue(rate)
    if not rate then return "1.000" end
    return string.format("%.3f", rate)
end

function Item.GetItemProps(item)
    if not item then return nil end
    local take = Item.GetTake(item)
    local take_type = Item.GetTakeType(take)
    if not take_type then return nil end
    if take_type == "Empty" then
        return {
            take_type = "Empty",
            mute = r.GetMediaItemInfo_Value(item, "B_MUTE") == 1,
            loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1,
            lock = r.GetMediaItemInfo_Value(item, "C_LOCK") == 1
        }
    end
    local props = {
        take_type = take_type,
        mute = r.GetMediaItemInfo_Value(item, "B_MUTE") == 1,
        loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1,
        lock = r.GetMediaItemInfo_Value(item, "C_LOCK") == 1,
        pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
        playback_rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
        preserve_pitch = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") == 1,
        reverse = Item.IsItemReversed(item),
        mode = r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE"),
        name = r.GetTakeName(take)
    }
    local pitchmode_value = r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE")
    if pitchmode_value == -1 then
        props.mode = -1
    else
        props.mode = math.floor(pitchmode_value / 65536)
    end
    if take_type == "MIDI" then
        props.velocity_scale = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
    else
        props.volume = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
    end
    props.bpm = r.Master_GetTempo() / props.playback_rate
    return props
end

function Item.GetAggregatedProps(items)
    return Core.GetAggregatedProps(items)
end

function Item.SetItemProps(item, props)
    if not item or not props then return end
    if props.mute ~= nil then
        r.SetMediaItemInfo_Value(item, "B_MUTE", props.mute and 1 or 0)
    end
    if props.loop ~= nil then
        r.SetMediaItemInfo_Value(item, "B_LOOPSRC", props.loop and 1 or 0)
    end
    if props.lock ~= nil then
        r.SetMediaItemInfo_Value(item, "C_LOCK", props.lock and 1 or 0)
    end
    local take = Item.GetTake(item)
    if not take then return end
    if props.playback_rate ~= nil then
        r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", props.playback_rate)
    end
    if props.preserve_pitch ~= nil then
        r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", props.preserve_pitch and 1 or 0)
    end
    if props.pitch ~= nil then
        r.SetMediaItemTakeInfo_Value(take, "D_PITCH", props.pitch)
    end
    if props.mode ~= nil or props.mode_bits ~= nil then
        local current_pm = r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE")
        local alg = nil
        local bits = nil
        if props.mode ~= nil then
            alg = props.mode
        else
            if current_pm == -1 then
                alg = -1
            else
                alg = math.floor(current_pm / 65536)
            end
        end
        if props.mode_bits ~= nil then
            bits = props.mode_bits & 0xFFFF
        else
            if current_pm == -1 then
                bits = 0
            else
                bits = current_pm & 0xFFFF
            end
        end
        if alg == -1 then
            r.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", -1)
        else
            r.SetMediaItemTakeInfo_Value(take, "I_PITCHMODE", alg * 65536 + bits)
        end
    end
    if props.velocity_scale ~= nil then
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", props.velocity_scale)
    elseif props.volume ~= nil then
        r.SetMediaItemTakeInfo_Value(take, "D_VOL", props.volume)
    end
    if props.name ~= nil then
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", props.name, true)
    end
end

function Item.SetAllItemsProps(items, props)
    if not items or #items == 0 or not props then return end
    local state = Core.GetState()
    local base_values = state.base_values or {}
    if not base_values or #base_values == 0 then
        base_values = {}
        for i, item in ipairs(items) do
            base_values[i] = Item.GetItemProps(item)
        end
        state.base_values = base_values
        Core.SetState(state)
    end
    for i, item in ipairs(items) do
        local item_props = Item.GetItemProps(item)
        if not item_props then goto continue end
        local item_specific_props = {}
        if props.mute ~= nil then item_specific_props.mute = props.mute end
        if props.loop ~= nil then item_specific_props.loop = props.loop end
        if props.lock ~= nil then item_specific_props.lock = props.lock end
        if props.name ~= nil then item_specific_props.name = props.name end
        if props.preserve_pitch ~= nil then item_specific_props.preserve_pitch = props.preserve_pitch end
        if props.mode ~= nil then item_specific_props.mode = props.mode end
        if props.mode_bits ~= nil then item_specific_props.mode_bits = props.mode_bits end
        if props.playback_rate ~= nil then item_specific_props.playback_rate = props.playback_rate end
        if props.bpm ~= nil then item_specific_props.bpm = props.bpm end
        item_specific_props.take_type = item_props.take_type
        if props.pitch_delta ~= nil and base_values and base_values[i] then
            local current_pitch = item_props.pitch or 0
            item_specific_props.pitch = current_pitch + props.pitch_delta
            item_specific_props.pitch = math.max(-24, math.min(24, item_specific_props.pitch))
        elseif props.pitch ~= nil then
            item_specific_props.pitch = props.pitch
        end
        if props.volume_delta ~= nil and base_values and base_values[i] then
            local base_volume = base_values[i].volume or 1.0
            item_specific_props.volume = base_volume + props.volume_delta
            item_specific_props.volume = math.max(0.0, math.min(4.0, item_specific_props.volume))
        elseif props.velocity_delta ~= nil and base_values and base_values[i] then
            local base_velocity = base_values[i].velocity_scale or 1.0
            item_specific_props.velocity_scale = base_velocity + props.velocity_delta
            item_specific_props.velocity_scale = math.max(0.0, math.min(2.0, item_specific_props.velocity_scale))
        elseif base_values and base_values[i] then
            local base_val = base_values[i]
            if base_val.take_type ~= "MIDI" and base_val.volume and props.base_volume and props.volume ~= nil then
                local change_factor = props.volume / props.base_volume
                item_specific_props.volume = base_val.volume * change_factor
                item_specific_props.volume = math.max(0.0, math.min(4.0, item_specific_props.volume))
            elseif base_val.take_type == "MIDI" and base_val.velocity_scale and props.base_velocity and props.velocity_scale ~= nil then
                local change_factor = props.velocity_scale / props.base_velocity
                item_specific_props.velocity_scale = base_val.velocity_scale * change_factor
                item_specific_props.velocity_scale = math.max(0.0, math.min(2.0, item_specific_props.velocity_scale))
            end
        else
            if props.volume ~= nil then item_specific_props.volume = props.volume end
            if props.velocity_scale ~= nil then item_specific_props.velocity_scale = props.velocity_scale end
        end
        Item.SetItemProps(item, item_specific_props)
        ::continue::
    end
    r.UpdateArrange()
end

function Item.UpdatePreservePitch(items, preserve)
    Utils.with_undo("Toggle Preserve Pitch", function()
        Item.SetAllItemsProps(items, { preserve_pitch = preserve })
    end)
end

function Item.UpdateLoop(items, loop)
    Utils.with_undo("Toggle Loop", function()
        Item.SetAllItemsProps(items, { loop = loop })
    end)
end

function Item.UpdateMute(items, mute)
    Utils.with_undo("Toggle Mute", function()
        Item.SetAllItemsProps(items, { mute = mute })
    end)
end

function Item.UpdateLock(items, lock)
    Utils.with_undo("Toggle Lock", function()
        Item.SetAllItemsProps(items, { lock = lock })
    end)
end

function Item.UpdateReverse(items, reverse)
    Utils.with_undo("Toggle Reverse", function()
        r.PreventUIRefresh(1)
        local original = {}
        local sel_count = r.CountSelectedMediaItems(0)
        for i = 0, sel_count - 1 do
            original[#original + 1] = r.GetSelectedMediaItem(0, i)
        end
        for i = 0, sel_count - 1 do
            local it = r.GetSelectedMediaItem(0, i)
            if it then r.SetMediaItemSelected(it, false) end
        end
        for _, item in ipairs(items) do
            if item and r.ValidatePtr(item, "MediaItem*") then
                r.SetMediaItemSelected(item, true)
                local take = Item.GetTake(item)
                if take then
                    local cur_rev = Item.IsItemReversed(item)
                    if cur_rev ~= reverse then
                        r.Main_OnCommand(41051, 0)
                    end
                end
                r.SetMediaItemSelected(item, false)
            end
        end
        for _, it in ipairs(original) do
            if it and r.ValidatePtr(it, "MediaItem*") then
                r.SetMediaItemSelected(it, true)
            end
        end
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
    end)
end

function Item.RemoveAllFX(items)
    Utils.with_undo('Remove all item FX', function()
        for _, item in ipairs(items) do
            local take = Item.GetTake(item)
            if take then
                local fx_count = r.TakeFX_GetCount(take)
                for fx_idx = fx_count - 1, 0, -1 do
                    r.TakeFX_Delete(take, fx_idx)
                end
            end
        end
    end)
end

function Item.OpenFXChain(items)
    r.Main_OnCommand(40638, 0)
end

return Item
