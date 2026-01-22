---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""
package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Theme = require("Theme")
local Utils = require("Utils")

local UIComponents = {}
local _hover_timers = {}
local _pending_tooltip_text = nil
local _italic_font = nil
local _agg_region = nil

local function _srgb_lin(c)
    local s = c / 255.0
    if s <= 0.03928 then return s / 12.92 end
    return ((s + 0.055) / 1.055) ^ 2.4
end

function UIComponents.ShouldUseBlackText(r_val, g_val, b_val)
    local L = 0.2126 * _srgb_lin(r_val) + 0.7152 * _srgb_lin(g_val) + 0.0722 * _srgb_lin(b_val)
    return L >= 0.179
end

function UIComponents.PushBlackText(ctx, flag)
    if flag then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black'))
        local ok, col = pcall(r.ImGui_Col_TextDisabled)
        if ok then r.ImGui_PushStyleColor(ctx, col, Theme.get('black')) end
    end
end

function UIComponents.PopBlackText(ctx, flag)
    if flag then
        local ok = pcall(r.ImGui_Col_TextDisabled)
        if ok then r.ImGui_PopStyleColor(ctx, 2) else r.ImGui_PopStyleColor(ctx, 1) end
    end
end

function UIComponents.GetBarColorAndUseBlack(items, tracks, props)
    local color = Theme.get('gray_64')
    local use_black = false
    if props.take_type == 'Track' then
        if #tracks == 1 and r.ValidatePtr(tracks[1], 'MediaTrack*') then
            local n = r.GetTrackColor(tracks[1]) or 0
            if n ~= 0 then
                local rr, gg, bb = r.ColorFromNative(n)
                color = Theme.rgba(rr, gg, bb, 255)
                use_black = UIComponents.ShouldUseBlackText(rr, gg, bb)
            end
        elseif #tracks > 1 then
            local first = nil
            local all_same = true
            for _, tr in ipairs(tracks) do
                if r.ValidatePtr(tr, 'MediaTrack*') then
                    local n = r.GetTrackColor(tr) or 0
                    if n == 0 then all_same = false break end
                    if not first then first = n elseif n ~= first then all_same = false break end
                end
            end
            if all_same and first then
                local rr, gg, bb = r.ColorFromNative(first)
                color = Theme.rgba(rr, gg, bb, 255)
                use_black = UIComponents.ShouldUseBlackText(rr, gg, bb)
            end
        end
    else
        if #items == 1 then
            if items[1] and r.ValidatePtr(items[1], 'MediaItem*') then
                local n = r.GetDisplayedMediaItemColor(items[1]) or 0
                if n ~= 0 then
                    local rr, gg, bb = r.ColorFromNative(n)
                    color = Theme.rgba(rr, gg, bb, 255)
                    use_black = UIComponents.ShouldUseBlackText(rr, gg, bb)
                end
            end
        elseif #items > 1 and props.common_color and not props.colors_differ then
            local rr, gg, bb = r.ColorFromNative(props.common_color)
            color = Theme.rgba(rr, gg, bb, 255)
            use_black = UIComponents.ShouldUseBlackText(rr, gg, bb)
        end
    end
    return color, use_black
end

function UIComponents.StyledButton(ctx, label, width, action)
    UIComponents.ColoredButton(ctx, label, width, Theme.get('transparent'), Theme.get('hover_white_32'), Theme.get('active_white_64'), action)
end

function UIComponents.StyledResetButton(ctx, label, width, is_modified, action, disabled, is_mixed)
    disabled = disabled or false
    local pop_label = UIComponents.PushLabelStateColor(ctx, disabled, is_mixed, is_modified)
    UIComponents.PushTransparentButtonStates(ctx, disabled)
    if disabled then r.ImGui_BeginDisabled(ctx, true) end
    if r.ImGui_Button(ctx, label, width) then
        if not disabled then
            action()
        end
    end
    if disabled then r.ImGui_EndDisabled(ctx) end
    r.ImGui_PopStyleColor(ctx, 3)
    if pop_label > 0 then r.ImGui_PopStyleColor(ctx, pop_label) end
end

function UIComponents.ShowTooltipDelayedIfHovered(ctx, key, text, delay)
    local hovered = r.ImGui_IsItemHovered(ctx)
    if hovered and text and text ~= '' then
        local now = r.time_precise()
        local t = _hover_timers[key]
        if not t then
            _hover_timers[key] = now
        elseif now - t >= (delay or 0.5) then
            _pending_tooltip_text = text
        end
    else
        _hover_timers[key] = nil
    end
end

function UIComponents.ResetAggHoverRegion()
    _agg_region = nil
end

function UIComponents.ExtendAggHoverRegion(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    if not _agg_region then
        _agg_region = { x1 = x1, y1 = y1, x2 = x2, y2 = y2 }
    else
        if x1 < _agg_region.x1 then _agg_region.x1 = x1 end
        if y1 < _agg_region.y1 then _agg_region.y1 = y1 end
        if x2 > _agg_region.x2 then _agg_region.x2 = x2 end
        if y2 > _agg_region.y2 then _agg_region.y2 = y2 end
    end
end

function UIComponents.ShowTooltipDelayedIfHoveredInAggRegion(ctx, key, text, delay)
    if not _agg_region then return end
    local mx, my = r.ImGui_GetMousePos(ctx)
    local inside = (mx >= _agg_region.x1 and mx <= _agg_region.x2 and my >= _agg_region.y1 and my <= _agg_region.y2)
    if inside and text and text ~= '' then
        local now = r.time_precise()
        local t = _hover_timers[key]
        if not t then
            _hover_timers[key] = now
        elseif now - t >= (delay or 0.5) then
            _pending_tooltip_text = text
        end
    else
        _hover_timers[key] = nil
    end
end

function UIComponents.IsMouseInsideAggRegion(ctx)
    if not _agg_region then return false end
    local mx, my = r.ImGui_GetMousePos(ctx)
    return mx >= _agg_region.x1 and mx <= _agg_region.x2 and my >= _agg_region.y1 and my <= _agg_region.y2
end

function UIComponents.RenderPendingTooltip(ctx)
    if _pending_tooltip_text and _pending_tooltip_text ~= '' then
        local ok = pcall(r.ImGui_BeginTooltip, ctx)
        if ok then
            r.ImGui_Text(ctx, 'AGGREGATION MODE:')
            if _italic_font then
                local pushed = pcall(r.ImGui_PushFont, ctx, _italic_font)
                if not pushed then pcall(r.ImGui_PushFont, ctx, _italic_font, 13) end
            end
            r.ImGui_Text(ctx, 'В данном режиме все внесённые изменения')
            r.ImGui_Text(ctx, 'суммируются с собственными значениями выделенных объектов')
            if _italic_font then r.ImGui_PopFont(ctx) end
            r.ImGui_EndTooltip(ctx)
        else
            r.ImGui_SetTooltip(ctx, 'AGGREGATION MODE:\n\nВ данном режиме все внесённые изменения\nсуммируются с собственными значениями выделенных объектов')
        end
        _pending_tooltip_text = nil
    end
end

function UIComponents.SetItalicFont(font)
    _italic_font = font
end

function UIComponents.Separator(ctx, left, right)
    left = left or 8
    right = right or left
    r.ImGui_SameLine(ctx, 0, left)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('pipe_gray'))
    r.ImGui_Text(ctx, "|")
    r.ImGui_PopStyleColor(ctx, 1)
    r.ImGui_SameLine(ctx, 0, right)
end

function UIComponents.IconDisplay(ctx, icon, size)
    size = size or 19
    if icon then
        r.ImGui_Image(ctx, icon, size, size)
        r.ImGui_SameLine(ctx)
    end
end

function UIComponents.ColoredButton(ctx, label, width, color, hover_color, active_color, action)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color or Theme.get('gray_64'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover_color or Theme.get('gray_80'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), active_color or Theme.get('gray_96'))
    if r.ImGui_Button(ctx, label, width) then
        action()
    end
    r.ImGui_PopStyleColor(ctx, 3)
end

function UIComponents.TextButton(ctx, text, width)
    UIComponents.PushTransparentButtonStates(ctx, false)
    local clicked = r.ImGui_Button(ctx, text, width)
    r.ImGui_PopStyleColor(ctx, 3)
    return clicked
end

function UIComponents.AggregationBadge(ctx, tooltip)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('green_accent'))
    UIComponents.PushTransparentButtonStates(ctx, false)
    r.ImGui_Button(ctx, 'Δ', 18)
    r.ImGui_PopStyleColor(ctx, 4)
    if r.ImGui_IsItemHovered(ctx) and tooltip then
        r.ImGui_SetTooltip(ctx, tooltip)
    end
end

function UIComponents.StyledInputCommon(ctx, label, hint_text, value, width, bar_color, use_hint)
    bar_color = bar_color or Theme.get('gray_64')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 4)
    if width then
        r.ImGui_SetNextItemWidth(ctx, width)
    end
    local changed, new_value
    if use_hint then
        changed, new_value = r.ImGui_InputTextWithHint(ctx, label, hint_text or '', value, r.ImGui_InputTextFlags_None())
    else
        changed, new_value = r.ImGui_InputText(ctx, label, value, r.ImGui_InputTextFlags_AutoSelectAll())
    end
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 2)
    return changed, new_value, deactivated
end

function UIComponents.StyledInput(ctx, label, value, width, bar_color)
    return UIComponents.StyledInputCommon(ctx, label, nil, value, width, bar_color, false)
end

function UIComponents.MultiItemInput(ctx, label, hint_text, value, width, bar_color)
    return UIComponents.StyledInputCommon(ctx, label, hint_text, value, width, bar_color, true)
end

function UIComponents.PureColorBar(ctx, width, bar_color)
    local w_avail, _ = r.ImGui_GetContentRegionAvail(ctx)
    local w = width or w_avail
    local h = 23
    r.ImGui_Dummy(ctx, w, h)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bar_color, 6)
end

function UIComponents.StyledCombo(ctx, label, current_index, items_str, width, bar_color, items_count)
    bar_color = bar_color or Theme.get('gray_64')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), Theme.get('gray_30'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), Theme.get('gray_64'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), Theme.get('gray_74'))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 4)
    if width then
        r.ImGui_SetNextItemWidth(ctx, width)
    end
    local changed, new_index
    if items_count then
        changed, new_index = r.ImGui_Combo(ctx, label, current_index, items_str, items_count)
    else
        changed, new_index = r.ImGui_Combo(ctx, label, current_index, items_str)
    end
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 6)
    return changed, new_index
end

function UIComponents.StyledSlider(ctx, label, value, min_val, max_val, format, bar_color)
    bar_color = bar_color or Theme.get('green_accent')
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), bar_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), bar_color)
    local changed, new_value = r.ImGui_SliderDouble(ctx, label, value, min_val, max_val, format)
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    r.ImGui_PopStyleColor(ctx, 2)
    return changed, new_value, deactivated
end

function UIComponents.DragDoubleInput(ctx, id, value, width, speed, min_val, max_val, format)
    if width then
        r.ImGui_SetNextItemWidth(ctx, width)
    end
    local changed, new_value = r.ImGui_DragDouble(ctx, id, value, speed or 0.1, min_val or -999, max_val or 999, format or "%.0f")
    local deactivated = Utils.ClearCursorContextOnDeactivation(ctx)
    return changed, new_value, deactivated
end

function UIComponents.ApplyWindowStyle(ctx)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 12, 6)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), Theme.get('gray_30'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), Theme.get('gray_45'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), Theme.get('gray_61'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.get('gray_74'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_64'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_80'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_96'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), Theme.get('green_accent'))
end

function UIComponents.PopWindowStyle(ctx)
    r.ImGui_PopStyleColor(ctx, 10)
    r.ImGui_PopStyleVar(ctx, 3)
end

function UIComponents.StyledCheckbox(ctx, label, value, is_mixed, disabled)
    disabled = disabled or false
    local mixed = (value == nil and is_mixed)
    if disabled then
        UIComponents.PushLabelStateColor(ctx, true, false, false)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), Theme.get('pipe_gray'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.get('frame_disabled'))
        r.ImGui_BeginDisabled(ctx, true)
    elseif mixed then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), Theme.get('yellow'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.get('gray_64'))
    end
    local changed, new_value = r.ImGui_Checkbox(ctx, label, mixed or (value or false))
    if disabled then
        r.ImGui_EndDisabled(ctx)
        r.ImGui_PopStyleColor(ctx, 5)
        changed = false
    elseif mixed then
        r.ImGui_PopStyleColor(ctx, 2)
    end
    return changed, new_value
end

function UIComponents.IconToggle(ctx, id, icons, state, is_mixed, size)
    size = size or 20
    local mixed = (state == nil and is_mixed)
    local current = mixed and false or (state or false)
    local icon = nil
    if icons then
        icon = mixed and icons.mixed or (current and icons.on or icons.off)
    end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('hover_white_32'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('active_white_64'))
    if id then r.ImGui_PushID(ctx, id) end
    local clicked = false
    if icon then
        local ok, ret = pcall(r.ImGui_ImageButton, ctx, icon, size, size, 0, Theme.get('transparent'), Theme.get('transparent'))
        if ok then
            clicked = ret
            UIComponents.DrawHoverActiveOverlay(ctx)
        else
            r.ImGui_Image(ctx, icon, size, size)
            clicked = r.ImGui_IsItemClicked(ctx)
            UIComponents.DrawHoverActiveOverlay(ctx)
        end
    else
        clicked = r.ImGui_Button(ctx, current and 'On' or 'Off', size)
    end
    if id then r.ImGui_PopID(ctx) end
    r.ImGui_PopStyleColor(ctx, 3)
    if clicked then
        if mixed then
            return true, true
        else
            return true, not current
        end
    end
    return false, mixed and nil or current
end

function UIComponents.IconToggleDual(ctx, id, icon_on, icon_off, state, size)
    return UIComponents.IconToggle(ctx, id, { on = icon_on, off = icon_off }, state, false, size)
end

function UIComponents.IconToggleTri(ctx, id, icon_on, icon_off, icon_mixed, state, is_mixed, size)
    return UIComponents.IconToggle(ctx, id, { on = icon_on, off = icon_off, mixed = icon_mixed }, state, is_mixed, size)
end

function UIComponents.ParameterControl(ctx, label, value, width, speed, min_val, max_val, format, reset_action, label_width, has_different_values, is_modified)
    if is_modified == nil then
        is_modified = (value ~= 0)
    end
    UIComponents.StyledResetButton(ctx, label, label_width or 40, is_modified, reset_action)
    r.ImGui_SameLine(ctx, 0, 2)
    local changed, new_value, deactivated = UIComponents.DragDoubleInput(ctx, '##' .. label, value, width or 50, speed, min_val, max_val, format)
    return changed, new_value, deactivated
end

local _pitch_drag_state = {}

function UIComponents.VerticalPitchControl(ctx, label, value, width, speed, min_val, max_val, format, reset_action, label_width, has_different_values, is_modified, is_mixed, agg_count, color_by_sign, octave_drag_default)
    if is_modified == nil then
        is_modified = (value ~= 0)
    end
    local id = label
    local disp_val = (_pitch_drag_state[id] and _pitch_drag_state[id].last) or value
    local disp_int = math.floor(disp_val + 0.5)
    local pushed_custom = false
    if color_by_sign and not is_mixed then
        local col = (disp_int > 0) and Theme.get('turquoise') or ((disp_int < 0) and Theme.get('orange_dark') or Theme.get('text_white_soft'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
        pushed_custom = true
        UIComponents.StyledResetButton(ctx, label, label_width or 40, false, reset_action, nil, false)
        r.ImGui_PopStyleColor(ctx, 1)
    else
        UIComponents.StyledResetButton(ctx, label, label_width or 40, is_modified, reset_action, nil, is_mixed)
    end
    if agg_count and agg_count > 1 then UIComponents.ExtendAggHoverRegion(ctx) end
    r.ImGui_SameLine(ctx, 0, 2)
    local w = width or 50
    local fmt = format or "%.0f"
    local text = string.format(fmt, disp_int)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('gray_42'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('gray_58'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('gray_74'))
    local clicked = r.ImGui_Button(ctx, ' ' .. text .. '##' .. label, w)
    if agg_count and agg_count > 1 then
        UIComponents.DrawAggregationOutline(ctx, nil, 4, 0)
        UIComponents.ExtendAggHoverRegion(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    local item_deactivated = r.ImGui_IsItemDeactivated(ctx)
    local activated = r.ImGui_IsItemActivated(ctx)
    local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
    if activated then
        _pitch_drag_state[id] = { start = value, last = value }
    end
    local changed = false
    local new_value = value
    if _pitch_drag_state[id] and mouse_down then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
        local s = speed or 0.1
        local shift = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
        local octave_mode = (octave_drag_default ~= false)
        local s2
        if octave_mode then
            s2 = shift and s or (s * 5)
        else
            s2 = shift and (s * 5) or s
        end
        local raw = _pitch_drag_state[id].start + (-dy) * s2
        if octave_mode then
            if shift then
                new_value = math.floor(raw + 0.5)
            else
                local diff = raw - _pitch_drag_state[id].start
                local steps = math.floor(diff / 12 + 0.5)
                new_value = _pitch_drag_state[id].start + steps * 12
            end
        else
            if shift then
                local diff = raw - _pitch_drag_state[id].start
                local steps = math.floor(diff / 12 + 0.5)
                new_value = _pitch_drag_state[id].start + steps * 12
            else
                new_value = math.floor(raw + 0.5)
            end
        end
        local mn = min_val or -999
        local mx = max_val or 999
        if new_value < mn then new_value = mn end
        if new_value > mx then new_value = mx end
        if new_value ~= _pitch_drag_state[id].last then
            changed = true
            _pitch_drag_state[id].last = new_value
        end
    end
    local hovered = r.ImGui_IsItemHovered(ctx)
    local dbl = hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    if dbl and not (agg_count and agg_count > 1) then
        changed = true
        new_value = 0
    end
    local deactivated = false
    if not mouse_down and _pitch_drag_state[id] then
        _pitch_drag_state[id] = nil
        local ok = pcall(r.ImGui_ResetMouseDragDelta, ctx, 0)
        local hovered = r.ImGui_IsWindowHovered(ctx)
        if not hovered then
            Utils.DeferClearCursorContext()
        end
        deactivated = true
    elseif item_deactivated and not mouse_down then
        deactivated = true
    end
    return changed, new_value, deactivated
end


function UIComponents.RenderInfoButton(ctx, command_id)
    UIComponents.StyledButton(ctx, 'i', 18, function()
        local mods = r.ImGui_GetKeyMods(ctx)
        local cmd_pressed = (mods & r.ImGui_Mod_Super()) ~= 0
        local ctrl_pressed = (mods & r.ImGui_Mod_Ctrl()) ~= 0
        local shift_pressed = (mods & r.ImGui_Mod_Shift()) ~= 0
        if (cmd_pressed or ctrl_pressed) and shift_pressed then
            local count = r.CountSelectedMediaItems(0)
            local path = nil
            for i = 0, count - 1 do
                local item = r.GetSelectedMediaItem(0, i)
                if item and r.ValidatePtr(item, 'MediaItem*') then
                    local take = r.GetActiveTake(item)
                    if take then
                        local src = r.GetMediaItemTake_Source(take)
                        if src then
                            local stype = r.GetMediaSourceType(src, '')
                            if stype ~= 'MIDI' then
                                local p = r.GetMediaSourceFileName(src, '')
                                if p and p ~= '' then
                                    path = p
                                    break
                                end
                            end
                        end
                    end
                end
            end
            if path then
                local os_str = r.GetOS()
                if os_str:match('Win') then
                    local cmd = string.format('explorer /select,%q', path)
                    os.execute(cmd)
                else
                    local cmd = string.format('open -R %q', path)
                    os.execute(cmd)
                end
            end
        elseif cmd_pressed or ctrl_pressed then
            r.Main_OnCommand(40011, 0)
        else
            r.Main_OnCommand(command_id, 0)
        end
    end)
end

function UIComponents.PushLabelStateColor(ctx, disabled, is_mixed, is_modified)
    if disabled then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
        return 1
    elseif is_mixed then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('yellow'))
        return 1
    elseif is_modified then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('green_accent'))
        return 1
    end
    return 0
end

function UIComponents.PushTransparentButtonStates(ctx, disabled)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), disabled and Theme.get('transparent') or Theme.get('hover_white_32'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), disabled and Theme.get('transparent') or Theme.get('active_white_64'))
end

function UIComponents.GetFreezeAccentColors(stats)
    if not stats then return nil, nil, nil, false end
    local blue = Theme.get('blue_freeze')
    local yellow = Theme.get('yellow')
    if (stats.track_count == 1 and stats.has) or stats.all_frozen then
        return blue, blue, blue, false
    elseif stats.mixed then
        return yellow, yellow, yellow, true
    end
    return nil, nil, nil, false
end

function UIComponents.DrawHoverActiveOverlay(ctx)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    if hovered or active then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        local col = active and Theme.get('active_white_64') or Theme.get('hover_white_32')
        r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col)
    end
end

function UIComponents.DrawAggregationOutline(ctx, color, rounding, inset)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local col = color or Theme.get('red_hover')
    local rads = rounding or 4
    local pad = inset or 0
    local thickness = 1.0
    r.ImGui_DrawList_AddRect(dl, x1 + pad, y1 + pad, x2 - pad, y2 - pad, col, rads, 0, thickness)
end

return UIComponents
