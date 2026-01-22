---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Core = require("Core")
local Utils = require("Utils")
local Theme = require("Theme")

local Take = {}

function Take.Render(ctx, items, props, UI, bar_color)
    UI.Separator(ctx)
    local label_text = 'Take'
    local active_display = nil
    local total_takes = nil
    if #items == 1 and r.ValidatePtr(items[1], 'MediaItem*') then
        local item = items[1]
        total_takes = r.GetMediaItemNumTakes(item)
        local active_take = r.GetActiveTake(item)
        local active_index = 0
        if active_take then
            active_index = math.floor(r.GetMediaItemTakeInfo_Value(active_take, 'IP_TAKENUMBER'))
        end
        active_display = (active_index + 1)
        if total_takes and total_takes > 0 then
            label_text = string.format('Take %d/%d', active_display, total_takes)
        end
    end
    local _, use_black = UI.GetBarColorAndUseBlack(items, {}, props)
    if not label_text:match(":$") then
        label_text = label_text .. ":"
    end
    local is_on = (r.GetToggleCommandStateEx and r.GetToggleCommandStateEx(0, 40435) == 1) or (r.GetToggleCommandState and r.GetToggleCommandState(40435) == 1)
    if not is_on then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray')) end
    UI.StyledResetButton(ctx, label_text, 70, false, function()
        local mods = r.ImGui_GetKeyMods(ctx)
        local has_cmd = (mods & r.ImGui_Mod_Super()) ~= 0
        local has_ctrl = (mods & r.ImGui_Mod_Ctrl()) ~= 0
        local has_shift = (mods & r.ImGui_Mod_Shift()) ~= 0
        local has_alt = (mods & r.ImGui_Mod_Alt()) ~= 0
        if has_alt then
            r.Main_OnCommand(40643, 0)
        elseif (has_cmd or has_ctrl) and has_shift then
            r.Main_OnCommand(42635, 0)
        elseif has_cmd or has_ctrl then
            r.Main_OnCommand(40131, 0)
        else
            r.Main_OnCommand(40435, 0)
        end
    end, false)
    if not is_on then r.ImGui_PopStyleColor(ctx, 1) end
    r.ImGui_SameLine(ctx, 0, 5)
    if #items == 1 then
        local item = items[1]
        if item and r.ValidatePtr(item, 'MediaItem*') then
            local take_count = r.GetMediaItemNumTakes(item)
            local active_index = 0
            local active_take = r.GetActiveTake(item)
            if active_take then
                active_index = math.floor(r.GetMediaItemTakeInfo_Value(active_take, 'IP_TAKENUMBER'))
            end
            local names = {}
            for i = 0, take_count - 1 do
                local tk = r.GetMediaItemTake(item, i)
                local nm = r.GetTakeName(tk)
                names[#names + 1] = nm or ''
            end
            local items_str = table.concat(names, '\0') .. '\0'
            r.ImGui_SetNextItemWidth(ctx, 120)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), bar_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), bar_color)
            local preview = names[active_index + 1] or ''
            UI.PushBlackText(ctx, use_black)
            local opened
            do
                local ok_flag, no_arrow = pcall(r.ImGui_ComboFlags_NoArrowButton)
                if ok_flag and no_arrow then
                    opened = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview, no_arrow)
                else
                    opened = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview)
                end
            end
            UI.PopBlackText(ctx, use_black)
            UI.DrawHoverActiveOverlay(ctx)
            r.ImGui_PopStyleColor(ctx, 4)
            if opened then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), Theme.get('gray_30'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), Theme.get('gray_58'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), Theme.get('gray_64'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), Theme.get('gray_74'))
                for i = 0, take_count - 1 do
                    local sel = (i == active_index)
                    if r.ImGui_Selectable(ctx, names[i + 1], sel) then
                        local new_take = r.GetMediaItemTake(item, i)
                        if new_take then
                            Utils.with_undo('Select Take', function()
                                r.SetActiveTake(new_take)
                            end)
                            local state = Core.GetState()
                            state.cached_props = Core.GetAggregatedProps(items)
                            Core.SetState(state)
                            r.UpdateArrange()
                        end
                    end
                end
                r.ImGui_PopStyleColor(ctx, 4)
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_SameLine(ctx, 0, 4)
            UI.PushTransparentButtonStates(ctx, false)
            local prev_disabled = (active_index <= 0)
            local prev_clicked
            if prev_disabled then
                r.ImGui_BeginDisabled(ctx, true)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                local ok_dir, dir_left = pcall(r.ImGui_Dir_Left)
                if ok_dir and dir_left then
                    prev_clicked = r.ImGui_ArrowButton(ctx, '##TakePrev', dir_left)
                else
                    prev_clicked = r.ImGui_Button(ctx, '<', 20)
                end
                r.ImGui_EndDisabled(ctx)
                r.ImGui_PopStyleColor(ctx, 4)
            else
                local ok_dir, dir_left = pcall(r.ImGui_Dir_Left)
                if ok_dir and dir_left then
                    prev_clicked = r.ImGui_ArrowButton(ctx, '##TakePrev', dir_left)
                else
                    prev_clicked = r.ImGui_Button(ctx, '<', 20)
                end
            end
            UI.DrawHoverActiveOverlay(ctx)
            r.ImGui_SameLine(ctx, 0, 2)
            local next_disabled = (active_index >= take_count - 1)
            local next_clicked
            if next_disabled then
                r.ImGui_BeginDisabled(ctx, true)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('frame_disabled'))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                local ok_dir2, dir_right = pcall(r.ImGui_Dir_Right)
                if ok_dir2 and dir_right then
                    next_clicked = r.ImGui_ArrowButton(ctx, '##TakeNext', dir_right)
                else
                    next_clicked = r.ImGui_Button(ctx, '>', 20)
                end
                r.ImGui_EndDisabled(ctx)
                r.ImGui_PopStyleColor(ctx, 4)
            else
                local ok_dir2, dir_right = pcall(r.ImGui_Dir_Right)
                if ok_dir2 and dir_right then
                    next_clicked = r.ImGui_ArrowButton(ctx, '##TakeNext', dir_right)
                else
                    next_clicked = r.ImGui_Button(ctx, '>', 20)
                end
            end
            UI.DrawHoverActiveOverlay(ctx)
            r.ImGui_PopStyleColor(ctx, 3)
            if (prev_clicked and not prev_disabled) or (next_clicked and not next_disabled) then
                local delta = prev_clicked and -1 or 1
                local target_index = active_index + delta
                if target_index < 0 then target_index = 0 end
                if target_index >= take_count then target_index = take_count - 1 end
                local new_take = r.GetMediaItemTake(item, target_index)
                if new_take then
                    Utils.with_undo('Select Take', function()
                        r.SetActiveTake(new_take)
                    end)
                    local state = Core.GetState()
                    state.cached_props = Core.GetAggregatedProps(items)
                    Core.SetState(state)
                    r.UpdateArrange()
                end
            end
        end
    else
        r.ImGui_SetNextItemWidth(ctx, 120)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), bar_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), bar_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), bar_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), bar_color)
        r.ImGui_BeginDisabled(ctx, true)
        local preview_multi = 'Только для одного объекта'
        UI.PushBlackText(ctx, use_black)
        local opened_multi
        do
            local ok_flag2, no_arrow2 = pcall(r.ImGui_ComboFlags_NoArrowButton)
            if ok_flag2 and no_arrow2 then
                opened_multi = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview_multi, no_arrow2)
            else
                opened_multi = r.ImGui_BeginCombo(ctx, '##TakeSelectInline', preview_multi)
            end
        end
        UI.PopBlackText(ctx, use_black)
        if opened_multi then r.ImGui_EndCombo(ctx) end
        r.ImGui_EndDisabled(ctx)
        r.ImGui_PopStyleColor(ctx, 4)
        r.ImGui_SameLine(ctx, 0, 4)
        r.ImGui_BeginDisabled(ctx, true)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('frame_disabled'))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
        local _ = r.ImGui_Button(ctx, '<', 20)
        r.ImGui_SameLine(ctx, 0, 2)
        local __ = r.ImGui_Button(ctx, '>', 20)
        r.ImGui_EndDisabled(ctx)
        r.ImGui_PopStyleColor(ctx, 4)
    end
end

return Take
