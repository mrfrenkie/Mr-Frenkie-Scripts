---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local script_path_full = debug.getinfo(1, 'S').source:match('@(.*)')
local script_dir = script_path_full:match('(.*[\\/])') or ''
package.path = script_dir .. '?.lua;' .. script_dir .. '?/init.lua;' .. package.path
local core = require('Core')
local TimestrechWidget = require('TimestretchWidget')
local UI = require('UIComponents')
local Theme = require('Theme')
local pitch_module = require('Pitch')
local Fader = require('Fader')
local Utils = require('Utils')
local Track = require('Track')
local Item = require('Item')

 
local initial_state = core.GetState()
if not initial_state.cached_items then
    initial_state.cached_items = {}
    core.SetState(initial_state)
end

if not core.CheckExtensions() then
    return
end

local ctx = nil
local font = nil
local font_italic = nil
local font_bold = nil
local audio_icon = nil
local midi_icon = nil
local track_icon = nil
local loop_icon_looped = nil
local loop_icon_unlooped = nil
local loop_icon_mixed = nil
local reverse_icon_reversed = nil
local reverse_icon_unreversed = nil
local reverse_icon_mixed = nil
local mute_icon_muted = nil
local mute_icon_unmuted = nil
local mute_icon_mixed = nil
local lock_icon_locked = nil
local lock_icon_unlocked = nil
local lock_icon_mixed = nil
local first_auto_resize = true
local initial_item_width = 1100

local function CreateFont(file_path)
    return r.ImGui_CreateFont(file_path)
end

local function PushFont(ctx, font, size)
    r.ImGui_PushFont(ctx, font, size)
end

local function PushFontCompat(ctx, font, size)
    local ok = pcall(r.ImGui_PushFont, ctx, font)
    if not ok then
        r.ImGui_PushFont(ctx, font, size)
    end
end

local function LoadIcon(dir, name)
    local png = dir .. name .. '.png'
    local img = nil
    local f = io.open(png, 'rb')
    if f then
        f:close()
        img = r.ImGui_CreateImage(png)
    end
    if not img then
        local d = dir .. 'default-icon.png'
        local df = io.open(d, 'rb')
        if df then
            df:close()
            img = r.ImGui_CreateImage(d)
        end
    end
    return img
end

function EnsureImGuiContext()
    if not ctx then
        local script_path_full = debug.getinfo(1, 'S').source:match('@(.*)')
        local script_dir = script_path_full:match('(.*[\\/])') or ''

        ctx = r.ImGui_CreateContext('Frenkie Item Properties')
        font = CreateFont(script_dir .. 'fonts/Roboto-Regular.ttf')
        pcall(r.ImGui_Attach, ctx, font)
        local italic_path = script_dir .. 'fonts/Roboto-Italic.ttf'
        local f = io.open(italic_path, 'rb')
        if f then
            f:close()
            font_italic = CreateFont(italic_path)
            pcall(r.ImGui_Attach, ctx, font_italic)
            UI.SetItalicFont(font_italic)
        else
            UI.SetItalicFont(nil)
        end
        local bold_path = script_dir .. 'fonts/Roboto-Bold.ttf'
        local bf = io.open(bold_path, 'rb')
        if bf then
            bf:close()
            font_bold = CreateFont(bold_path)
            pcall(r.ImGui_Attach, ctx, font_bold)
        end

        local icon_path = script_dir .. 'icons/'
        audio_icon = r.ImGui_CreateImage(icon_path .. 'audio-item.png')
        midi_icon = r.ImGui_CreateImage(icon_path .. 'midi-item.png')
        track_icon = r.ImGui_CreateImage(icon_path .. 'track-icon.png')
        loop_icon_looped = LoadIcon(icon_path, 'looped')
        loop_icon_unlooped = LoadIcon(icon_path, 'unlooped')
        loop_icon_mixed = LoadIcon(icon_path, 'looped mixed')
        reverse_icon_reversed = LoadIcon(icon_path, 'reversed')
        reverse_icon_unreversed = LoadIcon(icon_path, 'unreversed')
        reverse_icon_mixed = LoadIcon(icon_path, 'reversed mixed')
        mute_icon_muted = LoadIcon(icon_path, 'muted')
        mute_icon_unmuted = LoadIcon(icon_path, 'unmuted')
        mute_icon_mixed = LoadIcon(icon_path, 'muted mixed')
        lock_icon_locked = LoadIcon(icon_path, 'locked')
        lock_icon_unlocked = LoadIcon(icon_path, 'unlocked')
        lock_icon_mixed = LoadIcon(icon_path, 'locked mixed')

        if audio_icon then r.ImGui_Attach(ctx, audio_icon) end
        if midi_icon then r.ImGui_Attach(ctx, midi_icon) end
        if track_icon then r.ImGui_Attach(ctx, track_icon) end
        if loop_icon_looped then r.ImGui_Attach(ctx, loop_icon_looped) end
        if loop_icon_unlooped then r.ImGui_Attach(ctx, loop_icon_unlooped) end
        if loop_icon_mixed then r.ImGui_Attach(ctx, loop_icon_mixed) end
        if reverse_icon_reversed then r.ImGui_Attach(ctx, reverse_icon_reversed) end
        if reverse_icon_unreversed then r.ImGui_Attach(ctx, reverse_icon_unreversed) end
        if reverse_icon_mixed then r.ImGui_Attach(ctx, reverse_icon_mixed) end
        if mute_icon_muted then r.ImGui_Attach(ctx, mute_icon_muted) end
        if mute_icon_unmuted then r.ImGui_Attach(ctx, mute_icon_unmuted) end
        if mute_icon_mixed then r.ImGui_Attach(ctx, mute_icon_mixed) end
        if lock_icon_locked then r.ImGui_Attach(ctx, lock_icon_locked) end
        if lock_icon_unlocked then r.ImGui_Attach(ctx, lock_icon_unlocked) end
        if lock_icon_mixed then r.ImGui_Attach(ctx, lock_icon_mixed) end
    end
end

local function GetTrackSelectionKey(tracks)
    local parts = {}
    for _, tr in ipairs(tracks or {}) do
        parts[#parts + 1] = r.GetTrackGUID(tr) or ''
    end
    return table.concat(parts, '|')
end

local function IsItemSelection(props)
    return props.take_type == 'Audio' or props.take_type == 'MIDI' or props.take_type == 'Mult' or props.take_type == 'Empty'
end

local function IsTrackSelection(props)
    return props.take_type == 'Track'
end

local function RoundUpPow2(n)
    if not n or n <= 0 then return 0 end
    local p = 1
    while p < n do p = p * 2 end
    return p
end


local function Main()
    local state = core.GetState()

    local ms_left = r.JS_Mouse_GetState(1)
    local ms_right = r.JS_Mouse_GetState(2)
    if (ms_left == 1 or ms_right == 2) and not state.last_mouse_state then
        state.last_mouse_button = (ms_right == 2) and 2 or 1
        local window, segment, details = r.BR_GetMouseCursorContext()
        if window ~= 'unknown' then
            local it = r.BR_GetMouseCursorContext_Item()
            if it and r.ValidatePtr(it, 'MediaItem*') then
                state.prefer_track_context = false
                state.force_track_context = false
            elseif window == 'tcp' or window == 'mcp' then
                state.prefer_track_context = true
                state.force_track_context = true
                local tr, pos = r.BR_TrackAtMouseCursor()
                if tr and r.ValidatePtr(tr, 'MediaTrack*') then
                    state.hovered_track = tr
                else
                    state.hovered_track = nil
                end
            else
                state.force_track_context = false
            end
        end
        local items_now = Item.GetSelectedItems()
        local tracks_now = Track.GetSelectedTracks()
        if not state.force_track_context then
            if #items_now > 0 then
                state.prefer_track_context = false
            elseif #tracks_now > 0 then
                state.prefer_track_context = true
            end
        end
        if state.force_track_context then
            state.cached_props = { take_type = 'Track', name = 'Selected Track' }
        elseif state.prefer_track_context and #tracks_now > 0 then
            state.cached_props = { take_type = 'Track', name = 'Selected Track' }
        elseif #items_now > 0 then
            state.cached_props = Item.GetAggregatedProps(items_now)
        elseif #tracks_now > 0 then
            state.cached_props = { take_type = 'Track', name = 'Selected Track' }
        else
            state.cached_props = {}
        end
        state.cached_items = items_now
        state.cached_tracks = tracks_now
        state.last_mouse_state = true
        core.SetState(state)
    elseif ms_left == 0 and ms_right == 0 and state.last_mouse_state then
        local items_now = Item.GetSelectedItems()
        local tracks_now = Track.GetSelectedTracks()
        if state.last_mouse_button == 2 then
            state.force_track_context = false
            if #items_now > 0 then
                state.prefer_track_context = false
                state.cached_props = Item.GetAggregatedProps(items_now)
            elseif #tracks_now > 0 then
                state.prefer_track_context = true
                state.cached_props = { take_type = 'Track', name = 'Selected Track' }
            else
                state.cached_props = {}
            end
        else
            if state.force_track_context then
                state.prefer_track_context = true
                state.cached_props = { take_type = 'Track', name = 'Selected Track' }
            else
                if #items_now > 0 then
                    state.prefer_track_context = false
                    state.cached_props = Item.GetAggregatedProps(items_now)
                elseif #tracks_now > 0 then
                    state.prefer_track_context = true
                    state.cached_props = { take_type = 'Track', name = 'Selected Track' }
                else
                    state.cached_props = {}
                end
            end
        end
        state.cached_items = items_now
        state.cached_tracks = tracks_now
        state.last_mouse_button = 0
        state.last_mouse_state = false
        core.SetState(state)
    end

    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        return
    end

    PushFont(ctx, font, 13)
    UI.ApplyWindowStyle(ctx)

    r.ImGui_SetNextWindowSize(ctx, initial_item_width or 1000, 600, r.ImGui_Cond_FirstUseEver())
    local flags = r.ImGui_WindowFlags_None()
    if first_auto_resize then flags = flags | r.ImGui_WindowFlags_AlwaysAutoResize() end
    local visible, open = r.ImGui_Begin(ctx, 'Item Properties', true, flags)
    if r.ImGui_IsWindowAppearing(ctx) then first_auto_resize = false end

    if visible then
        local state = core.GetState()
        local items = Item.GetSelectedItems()
        local selected_tracks = Track.GetSelectedTracks()
        local tracks = selected_tracks
        if state.force_track_context and state.hovered_track and r.ValidatePtr(state.hovered_track, 'MediaTrack*') then
            tracks = { state.hovered_track }
        end
        local old_items = state.cached_items or {}
        local old_tracks = state.cached_tracks or {}

        local items_changed = not Utils.shallow_equal(old_items, items)
        local tracks_changed = not Utils.shallow_equal(old_tracks, tracks)
        local should_update_cache = items_changed or tracks_changed
        if not state.force_track_context then
            if #items > 0 then
                state.prefer_track_context = false
            elseif #tracks > 0 then
                state.prefer_track_context = true
            end
        end
        if should_update_cache then
            if state.prefer_track_context and #tracks > 0 then
                state.cached_props = { take_type = 'Track', name = 'Selected Track' }
            elseif #items > 0 then
                state.cached_props = Item.GetAggregatedProps(items)
            elseif #tracks > 0 then
                state.cached_props = { take_type = 'Track', name = 'Selected Track' }
            else
                state.cached_props = {}
            end
            state.cached_items = items
            state.cached_tracks = tracks
        end

        local proj_cc = r.GetProjectStateChangeCount(0)
        local freeze_sel_key = GetTrackSelectionKey(tracks)
        if (state._freeze_sel_key ~= freeze_sel_key) or (state._freeze_proj_cc ~= proj_cc) or (state.freeze_stats == nil) then
            state.freeze_stats = Track.GetFreezeStats(tracks)
            state._freeze_sel_key = freeze_sel_key
            state._freeze_proj_cc = proj_cc
            core.SetState(state)
        end
        if #items > 0 and not items_changed and not state.prefer_track_context then
            if state._items_proj_cc ~= proj_cc then
                state.cached_props = Item.GetAggregatedProps(items)
                state._items_proj_cc = proj_cc
                state.cache_time = r.time_precise()
                core.SetState(state)
            end
        end

        if should_update_cache then
            if items_changed then
                Fader.ResetAccumulatedValues()
            end
            state.cache_time = r.time_precise()
            core.SetState(state)
        end

        items = state.cached_items or {}
        local props = state.cached_props
        local base_values = core.GetState().base_values or {}

        if #items > 1000 then
            props = { take_type = 'Warning', name = string.format('Too many items (%d). Performance may be affected.', #items) }
        end

        core.CleanupOriginalProps()
        core.SetState(state)

        if not props and #items == 0 and #tracks == 0 then
            pitch_module.ClearState()
            r.ImGui_Text(ctx, 'No items or tracks selected')
        elseif props then
            local color, use_black = UI.GetBarColorAndUseBlack(items, tracks, props)

            r.ImGui_BeginGroup(ctx)

            UI.IconDisplay(ctx, props.take_type == 'MIDI' and midi_icon or 
                              props.take_type == 'Audio' and audio_icon or 
                              props.take_type == 'Track' and track_icon or nil)

            local bar_color = color
            UI.PushBlackText(ctx, use_black)

            local changed, new_name
            if props.take_type == 'Track' then
                if #tracks > 1 then
                    local hint_text = 'Multiple Tracks (' .. #tracks .. '):'
                    changed, new_name = UI.MultiItemInput(ctx, '##MultipleTracks', hint_text, '', -1, bar_color)
                    if changed and new_name ~= '' then
                        for _, tr in ipairs(tracks) do
                            if tr and r.ValidatePtr(tr, 'MediaTrack*') then
                                r.GetSetMediaTrackInfo_String(tr, 'P_NAME', new_name, true)
                            end
                        end
                        props.name = new_name
                    end
                elseif #tracks == 1 and r.ValidatePtr(tracks[1], 'MediaTrack*') then
                    local _, tname = r.GetTrackName(tracks[1])
                    local current_name = (props.name and props.name ~= 'Selected Track') and props.name or (tname or '')
                    changed, new_name = UI.StyledInput(ctx, '##TrackName', current_name, -1, bar_color)
                    if changed and new_name ~= current_name then
                        r.GetSetMediaTrackInfo_String(tracks[1], 'P_NAME', new_name, true)
                        props.name = new_name
                    end
                else
                    r.ImGui_Text(ctx, 'No tracks selected')
                end
            else
                if props.take_type == 'Empty' then
                    UI.PureColorBar(ctx, nil, bar_color)
                elseif #items > 1 then
                    local hint_text = 'Multiple Items (' .. #items .. '):'
                    if props.name and not props.name:match('^Multiple Items') then
                        hint_text = 'Multiple Items (' .. #items .. '): ' .. props.name
                    end
                    changed, new_name = UI.MultiItemInput(ctx, '##MultipleItems', hint_text, '', -1, bar_color)
                    if changed and new_name ~= '' then
                        for _, item in ipairs(items) do
                            local take = r.GetActiveTake(item)
                            if take then
                                r.GetSetMediaItemTakeInfo_String(take, 'P_NAME', new_name, true)
                            end
                        end
                        props.name = new_name
                    end
                else
                    changed, new_name = UI.StyledInput(ctx, '##ObjectName', props.name or '', -1, bar_color)
                    if changed and new_name ~= (props.name or '') then
                        local take = r.GetActiveTake(items[1])
                        if take then
                            r.GetSetMediaItemTakeInfo_String(take, 'P_NAME', new_name, true)
                        end
                        props.name = new_name
                    end
                end
            end

            UI.PopBlackText(ctx, use_black)

            r.ImGui_EndGroup(ctx)

            if IsTrackSelection(props) then
                r.ImGui_BeginGroup(ctx)
                UI.RenderInfoButton(ctx, 41654)
                UI.Separator(ctx)
                local single_track = (#tracks >= 1 and r.ValidatePtr(tracks[1], 'MediaTrack*')) and tracks[1] or nil
                local current_val = 0
                local has_mt_fx = false
                if single_track then
                    local v = Track.GetMidiTransposeValue(single_track)
                    if v ~= nil then current_val = v end
                    has_mt_fx = (Track.FindMidiTransposeFX(single_track) ~= nil)
                end
                local mt_changed, mt_new, mt_deactivated = UI.VerticalPitchControl(ctx, 'MIDI Transpose', current_val, 50, 0.1, -48, 48, '%.0f st', function()
                    if single_track then
                        Track.RemoveMidiTransposeFX({ single_track })
                    end
                end, 110, nil, has_mt_fx, nil, nil, true, true)
                if mt_changed and single_track then
                    Track.UpdateMidiTransposeImmediate({ single_track }, mt_new)
                end
                if mt_deactivated and single_track then
                    Track.FinalizeMidiTranspose()
                end
                UI.Separator(ctx)
                local fs = state.freeze_stats or { total = 0, has = false, track_count = #tracks, mixed = false, all_frozen = false }
                local base, hover, active, push_black = UI.GetFreezeAccentColors(fs)
                local label = 'Unfreeze'
                local width = 80
                if fs.track_count == 1 and fs.has then
                    label = string.format('Unfreeze (%d)', fs.total)
                    width = 100
                end
                UI.StyledButton(ctx, 'Freeze', 70, function()
                    Track.FreezeTracks(tracks)
                end)
                r.ImGui_SameLine(ctx, 0, 2)
                if base then
                    if push_black then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black')) end
                    UI.ColoredButton(ctx, label, width, base, hover, active, function()
                        Track.UnfreezeTracks(tracks)
                    end)
                    if push_black then r.ImGui_PopStyleColor(ctx, 1) end
                else
                    UI.StyledButton(ctx, label, width, function()
                        Track.UnfreezeTracks(tracks)
                    end)
                end
                UI.Separator(ctx)
                local pdc_value = '-'
                if #tracks == 1 and r.ValidatePtr(tracks[1], 'MediaTrack*') then
                    local perf = Track.GetPerfInfo(tracks[1])
                    local pdc = perf and perf.pdc_spl or nil
                    if pdc then
                        local rounded = RoundUpPow2(math.floor(pdc))
                        local sr = r.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false) or 0
                        if sr and sr > 0 then
                            local ms = (rounded / sr) * 1000.0
                            pdc_value = string.format('%d spl (%.2f ms)', rounded, ms)
                        else
                            pdc_value = string.format('%d spl', rounded)
                        end
                    end
                elseif #tracks > 1 then
                    pdc_value = 'mixed'
                end
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_white_soft'))
                if font_bold then
                    PushFontCompat(ctx, font_bold, 0)
                end
                r.ImGui_Text(ctx, 'PDC:')
                if font_bold then
                    r.ImGui_PopFont(ctx)
                end
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_SameLine(ctx, 0, 6)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                r.ImGui_Text(ctx, pdc_value)
                r.ImGui_PopStyleColor(ctx, 1)
                r.ImGui_EndGroup(ctx)
            end

            if IsItemSelection(props) then
                r.ImGui_BeginGroup(ctx)
                UI.RenderInfoButton(ctx, 40009)
                UI.Separator(ctx)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black'))
                UI.ColoredButton(ctx, 'N', 20, Theme.get('beige_base'), Theme.get('beige_hover'), Theme.get('beige_active'), function()
                    r.Main_OnCommand(40850, 0)
                end)
                r.ImGui_PopStyleColor(ctx, 1)
                UI.Separator(ctx)
                if props.take_type == 'Empty' then
                    r.ImGui_EndGroup(ctx)
                else
                local base_red = Theme.get('red_base')
                local hover_red = Theme.get('red_hover')
                local active_red = Theme.get('red_active')
                local blue = Theme.get('blue_freeze')
                local yellow = Theme.get('yellow')
                local item_tracks = {}
                local seen = {}
                for _, it in ipairs(items) do
                    local tr = r.GetMediaItem_Track(it)
                    if tr and r.ValidatePtr(tr, 'MediaTrack*') then
                        local guid = r.GetTrackGUID(tr)
                        if guid and not seen[guid] then
                            seen[guid] = true
                            item_tracks[#item_tracks + 1] = tr
                        end
                    end
                end
                local fs_items = Track.GetFreezeStats(item_tracks)
                local btn_base, btn_hover, btn_active, push_black = UI.GetFreezeAccentColors(fs_items)
                if not btn_base then
                    btn_base = base_red
                    btn_hover = hover_red
                    btn_active = active_red
                end
                if push_black then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black')) end
                UI.ColoredButton(ctx, '↺', 24, btn_base, btn_hover, btn_active, function()
                    local cmd1 = r.NamedCommandLookup('_SWS_RESETRATE')
                    local cmd2 = r.NamedCommandLookup('_XENAKIOS_RESETITEMLENMEDOFFS')
                    local cmd3 = r.NamedCommandLookup('_XENAKIOS_RESETITEMPITCHANDRATE')
                    if cmd1 ~= 0 then r.Main_OnCommand(cmd1, 0) end
                    if cmd2 ~= 0 then r.Main_OnCommand(cmd2, 0) end
                    if cmd3 ~= 0 then r.Main_OnCommand(cmd3, 0) end
                end)
                if push_black then r.ImGui_PopStyleColor(ctx, 1) end
                UI.Separator(ctx)
                local is_rate_modified = (props.playback_rate or 1.0) ~= 1.0
                UI.StyledResetButton(ctx, 'Rate:', 40, is_rate_modified, function()
                    props.playback_rate = 1.0
                    props.bpm = r.Master_GetTempo()
                    Utils.with_undo('Reset Rate', function()
                        Item.SetAllItemsProps(items, props)
                    end)
                end)
                r.ImGui_SameLine(ctx, 0, 2)
                local formatted_rate = Item.FormatRateValue(props.playback_rate or 1.0)
                if UI.TextButton(ctx, formatted_rate .. '##RateDisplay', 70) then
                    r.ImGui_OpenPopup(ctx, 'RateEdit')
                end
                if r.ImGui_BeginPopup(ctx, 'RateEdit') then
                    local rate_changed, rate, rate_deactivated = UI.DragDoubleInput(ctx, '##RatePopup', props.playback_rate or 1.0, 100, 0.01, 0.01, 10, '%.6f')
                    if rate_changed then
                        props.playback_rate = rate
                        props.bpm = r.Master_GetTempo() / rate
                        Utils.with_undo('Change Rate', function()
                            Item.SetAllItemsProps(items, props)
                        end)
                    end
                    
                    if r.ImGui_Button(ctx, 'Close') then
                        r.ImGui_CloseCurrentPopup(ctx)
                        Utils.DeferClearCursorContext()
                    end
                    r.ImGui_EndPopup(ctx)
                end
                UI.Separator(ctx)
                UI.StyledButton(ctx, 'BPM:', 40, function()
                    props.bpm = r.Master_GetTempo()
                    props.playback_rate = 1.0
                    Utils.with_undo('Reset BPM', function()
                        local bpm_props = { bpm = props.bpm, playback_rate = props.playback_rate }
                        Item.SetAllItemsProps(items, bpm_props)
                    end)
                end)
                r.ImGui_SameLine(ctx, 0, 2)
                local bmp_changed, bpm, bpm_deactivated = UI.DragDoubleInput(ctx, '##BPM', props.bpm or r.Master_GetTempo(), 50, 0.1, 20, 999, '%.0f')
                if bmp_changed then
                    props.bpm = bpm
                    props.playback_rate = r.Master_GetTempo() / bpm
                    Utils.with_undo('Change BPM', function()
                        local bpm_props = { bpm = bpm, playback_rate = props.playback_rate }
                        Item.SetAllItemsProps(items, bpm_props)
                    end)
                end
                
                UI.Separator(ctx)
                local preserve_value = props.preserve_pitch
                local preserve_mixed = (#items > 1)
                local preserve_disabled = (props.take_type == 'MIDI')
                local preserve_changed, preserve = UI.StyledCheckbox(ctx, 'Preserve', preserve_value, preserve_mixed, preserve_disabled)
                if preserve_changed and not preserve_disabled then
                    props.preserve_pitch = preserve
                    Item.UpdatePreservePitch(items, preserve)
                end
                UI.Separator(ctx)
                TimestrechWidget.Render(ctx, props, items, Item, UI.StyledResetButton)
                UI.Separator(ctx)
                if props.take_type == 'Audio' or props.take_type == 'MIDI' or props.take_type == 'Mult' then
                    if #items > 1 then UI.ResetAggHoverRegion() end
                    pitch_module.CheckSelectionChange(items)
                    local current_pitch = pitch_module.GetAggregatedPitch(items)
                    local is_modified, is_mixed = pitch_module.GetPitchLabelFlags(items)
                local pitch_changed, new_pitch, pitch_deactivated = UI.VerticalPitchControl(ctx, 'Pitch:', current_pitch, 50, 0.1, -48, 48, '%.0f st', function()
                    pitch_module.HandlePitchReset(items, base_values)
                    props.pitch = 0
                end, nil, false, is_modified, is_mixed, #items, nil, false)
                if #items > 1 and r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                    pitch_module.RevertAggregatedPitchChanges(items, base_values)
                    props.pitch = 0
                    for i, item in ipairs(items) do
                        local take = r.GetActiveTake(item)
                        if take and base_values[i] then
                            base_values[i].pitch = pitch_module.GetPitch(take)
                        end
                    end
                end
                if pitch_changed then
                    local updated_pitch = pitch_module.HandlePitchChange(items, new_pitch, current_pitch, base_values)
                    props.pitch = updated_pitch
                    for i, item in ipairs(items) do
                        local take = r.GetActiveTake(item)
                            if take and base_values[i] then
                                base_values[i].pitch = pitch_module.GetPitch(take)
                            end
                        end
                    end
                    if pitch_deactivated then
                        pitch_module.FinalizePitchChange()
                    end
                    UI.Separator(ctx)
                end
                Fader.RenderFaders(ctx, items, props, base_values, bar_color, UI)
                
                if #items > 1 then
                    UI.ShowTooltipDelayedIfHoveredInAggRegion(ctx, 'agg_unified', 'Режим Агрегации:\n\nВ данном режиме все внесённые изменения\nс собственными значениями выделенных объектов', 0.5)
                end
                UI.Separator(ctx)
                local has_fx = false
                if #items == 1 then
                    has_fx = Item.ItemHasFX(items[1])
                else
                    for _, item in ipairs(items) do
                        if Item.ItemHasFX(item) then
                            has_fx = true
                            break
                        end
                    end
                end
                local function fx_action()
                    local mods = r.ImGui_GetKeyMods(ctx)
                    local alt_pressed = (mods & r.ImGui_Mod_Alt()) ~= 0
                    local cmd_pressed = (mods & r.ImGui_Mod_Super()) ~= 0
                    local ctrl_pressed = (mods & r.ImGui_Mod_Ctrl()) ~= 0
                    if alt_pressed then
                        Item.RemoveAllFX(items)
                    elseif (cmd_pressed or ctrl_pressed) and has_fx then
                        r.Main_OnCommand(40209, 0)
                    else
                        Item.OpenFXChain(items)
                    end
                end
                if has_fx then
                    local green = Theme.get('green_accent')
                    UI.ColoredButton(ctx, 'FX', 30, green, green, green, fx_action)
                else
                    UI.StyledButton(ctx, 'FX', 30, fx_action)
                end
                UI.Separator(ctx)
                local loop_value = props.loop
                local loop_mixed = (loop_value == nil)
                local loop_changed, loop = UI.IconToggleTri(ctx, '##LoopIcon', loop_icon_looped, loop_icon_unlooped, loop_icon_mixed, loop_value, loop_mixed, 20)
                if loop_changed then
                    props.loop = loop
                    Item.UpdateLoop(items, loop)
                end
                r.ImGui_SameLine(ctx, 0, 8)
                local reverse_value = props.reverse
                local reverse_mixed = (reverse_value == nil)
                local reverse_changed, reverse = UI.IconToggleTri(ctx, '##ReverseIcon', reverse_icon_reversed, reverse_icon_unreversed, reverse_icon_mixed, reverse_value, reverse_mixed, 20)
                if reverse_changed then
                    props.reverse = reverse
                    Item.UpdateReverse(items, reverse)
                    state.cached_props = Item.GetAggregatedProps(items)
                    core.SetState(state)
                end
                r.ImGui_SameLine(ctx, 0, 8)
                local mute_value = props.mute
                local mute_mixed = (mute_value == nil)
                local mute_changed, mute = UI.IconToggleTri(ctx, '##MuteIcon', mute_icon_muted, mute_icon_unmuted, mute_icon_mixed, mute_value, mute_mixed, 20)
                if mute_changed then
                    props.mute = mute
                    Item.UpdateMute(items, mute)
                end
                r.ImGui_SameLine(ctx, 0, 8)
                local lock_value = props.lock
                local lock_mixed = (lock_value == nil)
                local lock_changed, lock = UI.IconToggleTri(ctx, '##LockIcon', lock_icon_locked, lock_icon_unlocked, lock_icon_mixed, lock_value, lock_mixed, 20)
                if lock_changed then
                    props.lock = lock
                    Item.UpdateLock(items, lock)
                end
                UI.Separator(ctx)
                r.ImGui_EndGroup(ctx)
            end
            end
        end
        r.ImGui_End(ctx)
    end
    UI.PopWindowStyle(ctx)
    r.ImGui_PopFont(ctx)
    UI.RenderPendingTooltip(ctx)
    if open then
        r.defer(Main)
    end
end

local function loop()
    EnsureImGuiContext()
    Main()
end

loop()
