local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Item = require("Item")
local Utils = require("Utils")
local Theme = require("Theme")
local Take = require("Take")

local Fader = {}

local accumulated_volume = 0
local accumulated_velocity = 0

local function UpdateAccumulatedVolume(volume_delta)
    accumulated_volume = accumulated_volume + volume_delta
end

local function ResetAccumulatedVolume()
    accumulated_volume = 0
end

local function GetAccumulatedVolume()
    return accumulated_volume
end

local function UpdateAccumulatedVelocity(velocity_delta)
    accumulated_velocity = accumulated_velocity + velocity_delta
end

local function ResetAccumulatedVelocity()
    accumulated_velocity = 0
end

local function GetAccumulatedVelocity()
    return accumulated_velocity
end

function Fader.ResetAccumulatedValues()
    accumulated_volume = 0
    accumulated_velocity = 0
end


function Fader.VolumeControl(ctx, items, props, base_values, bar_color, UI)
    local is_vol_modified = false
    local is_vol_mixed = false
    if #items == 1 then
        is_vol_modified = math.abs((props.volume or 1.0) - 1.0) > 0.001
    else
        local first_val = nil
        local all_equal = true
        for _, item in ipairs(items) do
            if item and r.ValidatePtr(item, "MediaItem*") then
                local take = r.GetActiveTake(item)
                if take then
                    local volume = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
                    if first_val == nil then
                        first_val = volume
                    else
                        if math.abs(volume - first_val) > 0.001 then
                            all_equal = false
                        end
                    end
                    if math.abs(volume - 1.0) > 0.001 then
                        is_vol_modified = true
                    end
                end
            end
        end
        is_vol_mixed = not all_equal
    end
    UI.StyledResetButton(ctx, 'Vol:', 35, is_vol_modified, function()
        props.volume = 1.0
        Utils.with_undo("Reset Volume", function()
            local reset_props = { volume = 1.0 }
            Item.SetAllItemsProps(items, reset_props)
        end)
        ResetAccumulatedVolume()
    end, false, is_vol_mixed)
    if #items > 1 then
        UI.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_SameLine(ctx, 0, 2)
    r.ImGui_SetNextItemWidth(ctx, 120)
    local display_volume
    if #items > 1 then
        display_volume = 1.0 + GetAccumulatedVolume()
    else
        display_volume = props.volume or 1.0
    end
    local vol_db = Utils.vol_to_db(display_volume)
    local vol_changed, new_vol_db = UI.StyledSlider(ctx, '##Volume', vol_db, -60.0, 12.0, "%.1f dB", bar_color)
    if #items > 1 then
        UI.DrawAggregationOutline(ctx, nil, 4, 0)
        UI.ExtendAggHoverRegion(ctx)
    end
    
    if vol_changed then
        local new_volume = Utils.db_to_vol(new_vol_db)
        if #items > 1 then
            local current_accumulated_db = Utils.vol_to_db(1.0 + GetAccumulatedVolume())
            local volume_delta_db = new_vol_db - current_accumulated_db
            local volume_delta = Utils.db_to_vol(current_accumulated_db + volume_delta_db) - Utils.db_to_vol(current_accumulated_db)
            if math.abs(volume_delta) > 0.001 then
                UpdateAccumulatedVolume(volume_delta)
                for _, item in ipairs(items) do
                    if item and r.ValidatePtr(item, "MediaItem*") then
                        local take = r.GetActiveTake(item)
                        if take then
                            local current_volume = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
                            local current_db = Utils.vol_to_db(current_volume)
                            local new_item_volume = Utils.db_to_vol(current_db + volume_delta_db)
                            new_item_volume = math.max(0.0, math.min(4.0, new_item_volume))
                            r.SetMediaItemTakeInfo_Value(take, "D_VOL", new_item_volume)
                        end
                    end
                end
                r.UpdateArrange()
            end
        else
            props.volume = new_volume
            local vol_props = { volume = props.volume }
            Item.SetItemProps(items[1], vol_props)
            r.UpdateArrange()
        end
    end
    local vol_deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    if vol_deactivated then
        Utils.with_undo("Change Volume", function() end)
    end
    Take.Render(ctx, items, props, UI, bar_color)
end

function Fader.VelocityControl(ctx, items, props, base_values, bar_color, UI)
    local is_vel_modified = false
    local is_vel_mixed = false
    if #items == 1 then
        is_vel_modified = math.abs((props.velocity_scale or 1.0) - 1.0) > 0.001
    else
        local first_val = nil
        local all_equal = true
        for _, item in ipairs(items) do
            if item and r.ValidatePtr(item, "MediaItem*") then
                local take = r.GetActiveTake(item)
                if take then
                    local velocity = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
                    if first_val == nil then
                        first_val = velocity
                    else
                        if math.abs(velocity - first_val) > 0.001 then
                            all_equal = false
                        end
                    end
                    if math.abs(velocity - 1.0) > 0.001 then
                        is_vel_modified = true
                    end
                end
            end
        end
        is_vel_mixed = not all_equal
    end
    UI.StyledResetButton(ctx, 'Vel:', 35, is_vel_modified, function()
        props.velocity_scale = 1.0
        Utils.with_undo("Reset Velocity", function()
            local reset_props = { velocity_scale = 1.0 }
            Item.SetAllItemsProps(items, reset_props)
        end)
        ResetAccumulatedVelocity()
    end, false, is_vel_mixed)
    if #items > 1 then
        UI.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_SameLine(ctx, 0, 2)
    r.ImGui_SetNextItemWidth(ctx, 120)
    local display_velocity
    if #items > 1 then
        display_velocity = 1.0 + GetAccumulatedVelocity()
    else
        display_velocity = props.velocity_scale or 1.0
    end
    local vel_changed, vel = UI.StyledSlider(ctx, '##Velocity', display_velocity, 0.0, 2.0, "x%.2f", bar_color)
    if #items > 1 then
        UI.DrawAggregationOutline(ctx, nil, 4, 0)
        UI.ExtendAggHoverRegion(ctx)
    end
    
    if vel_changed then
        if #items > 1 then
            local current_accumulated = GetAccumulatedVelocity()
            local velocity_delta = (vel - 1.0) - current_accumulated
            if math.abs(velocity_delta) > 0.001 then
                UpdateAccumulatedVelocity(velocity_delta)
                for _, item in ipairs(items) do
                    if item and r.ValidatePtr(item, "MediaItem*") then
                        local take = r.GetActiveTake(item)
                        if take then
                            local current_velocity = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
                            local new_item_velocity = current_velocity + velocity_delta
                            new_item_velocity = math.max(0.0, math.min(2.0, new_item_velocity))
                            r.SetMediaItemTakeInfo_Value(take, "D_VOL", new_item_velocity)
                        end
                    end
                end
                r.UpdateArrange()
            end
        else
            props.velocity_scale = vel
            local vel_props = { velocity_scale = vel }
            Item.SetItemProps(items[1], vel_props)
            r.UpdateArrange()
        end
    end
    local vel_deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    if vel_deactivated then
        Utils.with_undo("Change Velocity", function() end)
    end
    Take.Render(ctx, items, props, UI, bar_color)
end

function Fader.MixedVolumeControl(ctx, items, props, bar_color, UI)
    UI.StyledResetButton(ctx, 'Vol:', 35, false, function()
    end, true)
    UI.ExtendAggHoverRegion(ctx)
    r.ImGui_SameLine(ctx, 0, 2)
    r.ImGui_SetNextItemWidth(ctx, 120)
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_SliderDouble(ctx, '##VolumeMixed', 1.0, 0.0, 2.0, "Mixed")
    r.ImGui_EndDisabled(ctx)
    UI.ExtendAggHoverRegion(ctx)
    Take.Render(ctx, items, props, UI, bar_color)
end

function Fader.RenderFaders(ctx, items, props, base_values, bar_color, UI)
    if props.take_type == "Audio" then
        Fader.VolumeControl(ctx, items, props, base_values, bar_color, UI)
    elseif props.take_type == "MIDI" then
        Fader.VelocityControl(ctx, items, props, base_values, bar_color, UI)
    elseif props.take_type == "Mult" then
        Fader.MixedVolumeControl(ctx, items, props, bar_color, UI)
    end
end

return Fader
