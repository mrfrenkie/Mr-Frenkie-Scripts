local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")

local original_props = {}
local base_values = {}
local current_selection = {}
local accumulated_pitch = 0

local last_mouse_state = false
local cached_items = {}
local cached_props = nil
local cached_tracks = {}
local _freeze_sel_key = nil
local _freeze_proj_cc = 0
local freeze_stats = nil
local _items_proj_cc = 0
local cache_time = 0
local cache_duration = 0.2
local last_update_time = 0
local update_interval = 1/30
local last_gc_time = 0
local gc_interval = 10
local prefer_track_context = false

local ItemPropsCore = {}

function ItemPropsCore.CheckExtensions()
    if not r.JS_ReaScriptAPI_Version then
        r.ShowMessageBox("js_ReaScriptAPI extension is required for this script.", "Missing Extension", 0)
        return false
    end
    if not r.ImGui_CreateContext then
        r.ShowMessageBox("ReaImGui extension is required for this script.", "Missing Extension", 0)
        return false
    end
    if not r.BR_GetMouseCursorContext then
        r.ShowMessageBox("SWS extension is required for this script.", "Missing Extension", 0)
        return false
    end
    return true
end

function ItemPropsCore.GetSelectedItems()
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

function ItemPropsCore.GetTake(item)
    if not item then return nil end
    return r.GetActiveTake(item)
end

function ItemPropsCore.GetTakeType(take)
    if not take then return "Empty" end
    local source = r.GetMediaItemTake_Source(take)
    if not source then return "Empty" end
    local source_type = r.GetMediaSourceType(source, "")
    return source_type == "MIDI" and "MIDI" or "Audio"
end

function ItemPropsCore.GetTakeSourceReverse(take)
    if not take then return false end
    local src = r.GetMediaItemTake_Source(take)
    if not src then return false end
    local ok, offs, len, rev = r.PCM_Source_GetSectionInfo(src)
    if ok then return rev == true end
    return false
end

function ItemPropsCore.IsItemReversed(item)
    if not item or not r.ValidatePtr(item, "MediaItem*") then return false end
    local take = ItemPropsCore.GetTake(item)
    if not take then return false end
    if r.GetMediaItemTakeInfo_Value(take, "B_REVERSE") == 1 then return true end
    if ItemPropsCore.GetTakeSourceReverse(take) then return true end
    return false
end

function ItemPropsCore.ItemHasFX(item)
    if not item then return false end
    local take = ItemPropsCore.GetTake(item)
    if not take then return false end
    return r.TakeFX_GetCount(take) > 0
end

function ItemPropsCore.GetMIDIVelocityScale(take)
    if not take then return 1.0 end
    return r.GetMediaItemTakeInfo_Value(take, "D_VOL")
end

function ItemPropsCore.FormatRateValue(rate)
    if not rate then return "1.000" end
    return string.format("%.3f", rate)
end

function ItemPropsCore.GetItemProps(item)
    if not item then return nil end
    local take = ItemPropsCore.GetTake(item)
    local take_type = ItemPropsCore.GetTakeType(take)
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
        reverse = ItemPropsCore.IsItemReversed(item),
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
        props.velocity_scale = ItemPropsCore.GetMIDIVelocityScale(take)
    else
        props.volume = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
    end
    props.bpm = r.Master_GetTempo() / props.playback_rate
    return props
end

function ItemPropsCore.GetAggregatedProps(items)
    if not items or #items == 0 then 
        accumulated_pitch = 0
        current_selection = {}
        return nil 
    end
    local MAX_ITEMS = 500
    if #items > MAX_ITEMS then
        return {
            take_type = "Warning",
            name = string.format("Too many items selected (%d). Limit: %d", #items, MAX_ITEMS),
            mute = nil,
            loop = nil,
            pitch = nil,
            playback_rate = nil,
            preserve_pitch = nil,
            reverse = nil,
            mode = nil,
            volume = nil,
            velocity_scale = nil,
            bpm = nil
        }
    end
    if #items == 1 then 
        if #current_selection > 0 then
            current_selection = {}
            accumulated_pitch = 0
        end
        return ItemPropsCore.GetItemProps(items[1]) 
    end
    local first_props = ItemPropsCore.GetItemProps(items[1])
    if not first_props then return nil end
    local aggregated = {}
    for k, v in pairs(first_props) do
        aggregated[k] = v
    end
    local has_midi = first_props.take_type == "MIDI"
    local has_audio = first_props.take_type == "Audio"
    local common_color = r.GetDisplayedMediaItemColor(items[1])
    local colors_differ = false
    for i = 2, #items do
        local item = items[i]
        if not item or not r.ValidatePtr(item, "MediaItem*") then
            goto continue
        end
        local props = ItemPropsCore.GetItemProps(item)
        if props then
            if props.take_type == "MIDI" then
                has_midi = true
            else
                has_audio = true
            end
            local item_color = r.GetDisplayedMediaItemColor(item)
            if item_color ~= common_color then
                colors_differ = true
            end
            if aggregated.mute ~= props.mute then aggregated.mute = nil end
            if aggregated.loop ~= props.loop then aggregated.loop = nil end
            if aggregated.lock ~= props.lock then aggregated.lock = nil end
            if math.abs((aggregated.playback_rate or 1) - (props.playback_rate or 1)) > 0.001 then aggregated.playback_rate = nil end
            if aggregated.preserve_pitch ~= props.preserve_pitch then aggregated.preserve_pitch = nil end
            if aggregated.reverse ~= props.reverse then aggregated.reverse = nil end
            if aggregated.mode ~= props.mode then aggregated.mode = nil end
            if math.abs((aggregated.bpm or 120) - (props.bpm or 120)) > 0.1 then aggregated.bpm = nil end
            if aggregated.name ~= props.name then aggregated.name = "Multiple Items (" .. #items .. ")" end
            if props.take_type == "MIDI" then
                if aggregated.velocity_scale and props.velocity_scale then
                    if math.abs(aggregated.velocity_scale - props.velocity_scale) > 0.01 then
                        aggregated.velocity_scale = nil
                    end
                else
                    aggregated.velocity_scale = nil
                end
            else
                if aggregated.volume and props.volume then
                    if math.abs(aggregated.volume - props.volume) > 0.01 then
                        aggregated.volume = nil
                    end
                else
                    aggregated.volume = nil
                end
            end
        end
        ::continue::
    end
    if #items > 1 then
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
            current_selection = {}
            for i, item in ipairs(items) do
                current_selection[i] = item
            end
            selection_changed = false
        end
        if selection_changed then
            accumulated_pitch = 0
            current_selection = {}
            for i, item in ipairs(items) do
                current_selection[i] = item
            end
        end
        if has_audio and aggregated.volume == nil then
            aggregated.volume = 1.0
        end
        if has_midi and aggregated.velocity_scale == nil then
            aggregated.velocity_scale = 1.0
        end
    else
        if #current_selection > 0 then
            current_selection = {}
            accumulated_pitch = 0
        end
    end
    if has_midi and has_audio then
        aggregated.take_type = "Mult"
    end
    aggregated.common_color = common_color
    aggregated.colors_differ = colors_differ
    return aggregated
end

function ItemPropsCore.OpenItemFXChain(item)
    if not item then return end
    r.SetMediaItemSelected(item, true)
    r.Main_OnCommand(40638, 0)
end

function ItemPropsCore.ClearOriginalPropsForSelection()
    local items = ItemPropsCore.GetSelectedItems()
    for _, item in ipairs(items) do
        local item_ptr = r.GetMediaItemGUID(item)
        if original_props[item_ptr] then
            original_props[item_ptr] = nil
        end
    end
end

function ItemPropsCore.CleanupOriginalProps()
    if not original_props then return end
    local items = ItemPropsCore.GetSelectedItems()
    if #items == 0 then
        original_props = {}
        base_values = {}
        cached_items = {}
        cached_props = nil
        collectgarbage("collect")
        return
    end
    local valid_props = {}
    for item_ptr, props in pairs(original_props) do
        local item = r.BR_GetMediaItemByGUID(0, item_ptr)
        if item and r.ValidatePtr(item, "MediaItem*") then
            valid_props[item_ptr] = props
        end
    end
    original_props = valid_props
    if #base_values > 50 then
        local new_base_values = {}
        local start_idx = #base_values - 25 + 1
        for i = start_idx, #base_values do
            new_base_values[#new_base_values + 1] = base_values[i]
        end
        base_values = new_base_values
    end
end

function ItemPropsCore.SetItemProps(item, props)
    if not item or not props then return end
    local take = ItemPropsCore.GetTake(item)
    if not take then return end
    if props.mute ~= nil then
        r.SetMediaItemInfo_Value(item, "B_MUTE", props.mute and 1 or 0)
    end
    if props.loop ~= nil then
        r.SetMediaItemInfo_Value(item, "B_LOOPSRC", props.loop and 1 or 0)
    end
    if props.lock ~= nil then
        r.SetMediaItemInfo_Value(item, "C_LOCK", props.lock and 1 or 0)
    end
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

function ItemPropsCore.SetAllItemsProps(items, props)
    if not items or #items == 0 or not props then return end
    if not base_values or #base_values == 0 then
        base_values = {}
        for i, item in ipairs(items) do
            base_values[i] = ItemPropsCore.GetItemProps(item)
        end
    end
    for i, item in ipairs(items) do
        local item_props = ItemPropsCore.GetItemProps(item)
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
        if props.pitch_delta ~= nil and props.base_values and props.base_values[i] then
            local current_pitch = item_props.pitch or 0
            item_specific_props.pitch = current_pitch + props.pitch_delta
            item_specific_props.pitch = math.max(-24, math.min(24, item_specific_props.pitch))
        elseif props.pitch ~= nil then
            item_specific_props.pitch = props.pitch
        end
        if props.volume_delta ~= nil and props.base_values and props.base_values[i] then
            local base_volume = props.base_values[i].volume or 1.0
            item_specific_props.volume = base_volume + props.volume_delta
            item_specific_props.volume = math.max(0.0, math.min(4.0, item_specific_props.volume))
        elseif props.velocity_delta ~= nil and props.base_values and props.base_values[i] then
            local base_velocity = props.base_values[i].velocity_scale or 1.0
            item_specific_props.velocity_scale = base_velocity + props.velocity_delta
            item_specific_props.velocity_scale = math.max(0.0, math.min(2.0, item_specific_props.velocity_scale))
        elseif props.base_values and props.base_values[i] then
            local base_val = props.base_values[i]
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
        ItemPropsCore.SetItemProps(item, item_specific_props)
        ::continue::
    end
    r.UpdateArrange()
end

function ItemPropsCore.GetState()
    return {
        original_props = original_props,
        base_values = base_values,
        current_selection = current_selection,
        last_mouse_state = last_mouse_state,
        prefer_track_context = prefer_track_context,
        cached_items = cached_items,
        cached_tracks = cached_tracks,
        cached_props = cached_props,
        cache_time = cache_time,
        cache_duration = cache_duration,
        last_update_time = last_update_time,
        update_interval = update_interval,
        last_gc_time = last_gc_time,
        gc_interval = gc_interval,
        _freeze_sel_key = _freeze_sel_key,
        _freeze_proj_cc = _freeze_proj_cc,
        freeze_stats = freeze_stats,
        _items_proj_cc = _items_proj_cc
    }
end

function ItemPropsCore.SetState(state)
    original_props = state.original_props or {}
    base_values = state.base_values or {}
    current_selection = state.current_selection or {}
    last_mouse_state = state.last_mouse_state or false
    prefer_track_context = state.prefer_track_context or false
    cached_items = state.cached_items or {}
    cached_tracks = state.cached_tracks or {}
    cached_props = state.cached_props
    cache_time = state.cache_time or 0
    cache_duration = state.cache_duration or 0.2
    last_update_time = state.last_update_time or 0
    update_interval = state.update_interval or (1/30)
    last_gc_time = state.last_gc_time or 0
    gc_interval = state.gc_interval or 10
    _freeze_sel_key = state._freeze_sel_key
    _freeze_proj_cc = state._freeze_proj_cc
    freeze_stats = state.freeze_stats
    _items_proj_cc = state._items_proj_cc
end

function ItemPropsCore.UpdatePreservePitch(items, preserve)
    Utils.with_undo("Toggle Preserve Pitch", function()
        ItemPropsCore.SetAllItemsProps(items, { preserve_pitch = preserve })
    end)
end

function ItemPropsCore.UpdateLoop(items, loop)
    Utils.with_undo("Toggle Loop", function()
        ItemPropsCore.SetAllItemsProps(items, { loop = loop })
    end)
end

function ItemPropsCore.UpdateMute(items, mute)
    Utils.with_undo("Toggle Mute", function()
        ItemPropsCore.SetAllItemsProps(items, { mute = mute })
    end)
end

function ItemPropsCore.UpdateLock(items, lock)
    Utils.with_undo("Toggle Lock", function()
        ItemPropsCore.SetAllItemsProps(items, { lock = lock })
    end)
end

function ItemPropsCore.UpdateReverse(items, reverse)
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
                local take = ItemPropsCore.GetTake(item)
                if take then
                    local cur_rev = ItemPropsCore.IsItemReversed(item)
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

function ItemPropsCore.RemoveAllFX(items)
    Utils.with_undo('Remove all item FX', function()
        for _, item in ipairs(items) do
            local take = ItemPropsCore.GetTake(item)
            if take then
                local fx_count = r.TakeFX_GetCount(take)
                for fx_idx = fx_count - 1, 0, -1 do
                    r.TakeFX_Delete(take, fx_idx)
                end
            end
        end
    end)
end

function ItemPropsCore.OpenFXChain(items)
    r.Main_OnCommand(40638, 0)
end

return ItemPropsCore
