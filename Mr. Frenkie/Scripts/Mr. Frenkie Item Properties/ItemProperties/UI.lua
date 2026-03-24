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
local JSFX = require('jsfx')

local function ensure_jsfx_installed()
    if not (r.APIExists and r.APIExists("FIP_EnsureJSFXFileStr")) then return end
    r.FIP_EnsureJSFXFileStr("MIDI Transpose and Monitor.jsfx", JSFX.MIDI_TRANSPOSE_UTILITY_JSFX, 0)
    r.FIP_EnsureJSFXFileStr("Low Cut 24 dB oct.jsfx", JSFX.LOW_CUT_24DB_JSFX, 0)
    r.FIP_EnsureJSFXFileStr("High Cut 24 dB oct.jsfx", JSFX.HIGH_CUT_24DB_JSFX, 0)
    if r.APIExists("FIP_EnsureJSFXPresetStr") then
        r.FIP_EnsureJSFXPresetStr("js-Mr_ Frenkie_Low Cut 24 dB oct_jsfx.ini", JSFX.PRESET_LOW_CUT_24_EMBEDDED, 0)
        r.FIP_EnsureJSFXPresetStr("js-Mr_ Frenkie_High Cut 24 dB oct_jsfx.ini", JSFX.PRESET_HIGH_CUT_24_EMBEDDED, 0)
    end
    if r.APIExists("FIP_SetMidiTransposePresetStr") then
        r.FIP_SetMidiTransposePresetStr(JSFX.MIDI_TRANSPOSE_UTILITY_PRESET_INI, 0)
    end
end

ensure_jsfx_installed()

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
local playback_offset_last_guid = nil
local playback_offset_last_ms = 0.0
local playback_offset_last_unit = 'ms'
local playback_offset_last_valid = false
local playback_offset_edit_focus = false

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


local function ApplyContextFromReaperCursor(state)
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
    local items_cnt = (r.APIExists and r.APIExists("FIP_CountSelectedItems"))
        and math.floor(tonumber((r.FIP_CountSelectedItems("", 0))) or 0)
        or r.CountSelectedMediaItems(0)

    local items_sig = (r.APIExists and r.APIExists("FIP_GetSelectedItemsSignatureStr"))
        and (r.FIP_GetSelectedItemsSignatureStr("", 0) or "")
        or ""

    local items_now = {}
    if items_cnt == 1 then
        local it = r.GetSelectedMediaItem(0, 0)
        if it then items_now[1] = it end
    end

    local tracks_now = Track.GetSelectedTracks()
    if not state.force_track_context then
        if items_cnt > 0 then
            state.prefer_track_context = false
        elseif #tracks_now > 0 then
            state.prefer_track_context = true
        end
    end
    if state.force_track_context then
        state.cached_props = { take_type = 'Track', name = 'Selected Track' }
    elseif state.prefer_track_context and #tracks_now > 0 then
        state.cached_props = { take_type = 'Track', name = 'Selected Track' }
    elseif items_cnt > 0 then
        state.cached_props = Item.GetAggregatedProps(items_now)
    elseif #tracks_now > 0 then
        state.cached_props = { take_type = 'Track', name = 'Selected Track' }
    else
        state.cached_props = {}
    end
    state.cached_items = items_now
    state.cached_items_sig = items_sig
    state.cached_items_count = items_cnt
    state.cached_tracks = tracks_now
end

local function Main()
    local state = core.GetState()

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

    local ms_left = r.JS_Mouse_GetState(1)
    local ms_right = r.JS_Mouse_GetState(2)
    local window_hovered = visible and r.ImGui_IsWindowHovered(ctx)

    if (ms_left == 1 or ms_right == 2) and not state.last_mouse_state then
        state.last_mouse_button = (ms_right == 2) and 2 or 1
        if ms_right == 2 then
            if window_hovered then
                state.manual_context_override = true
                local show_track_now = (state.manual_context_override and state.manual_context_prefer_track)
                    or (not state.manual_context_override and state.prefer_track_context)
                state.manual_context_prefer_track = not show_track_now
                state.prefer_track_context = state.manual_context_prefer_track
                state.force_track_context = state.manual_context_prefer_track
                if not state.manual_context_prefer_track then
                    state.hovered_track = nil
                end
                local items_cnt = (r.APIExists and r.APIExists("FIP_CountSelectedItems"))
                    and math.floor(tonumber((r.FIP_CountSelectedItems("", 0))) or 0)
                    or r.CountSelectedMediaItems(0)

                local items_sig = (r.APIExists and r.APIExists("FIP_GetSelectedItemsSignatureStr"))
                    and (r.FIP_GetSelectedItemsSignatureStr("", 0) or "")
                    or ""

                local items_now = {}
                if items_cnt == 1 then
                    local it = r.GetSelectedMediaItem(0, 0)
                    if it then items_now[1] = it end
                end

                local tracks_now = Track.GetSelectedTracks()
                if state.manual_context_prefer_track and #tracks_now > 0 then
                    state.cached_props = { take_type = 'Track', name = 'Selected Track' }
                    state.cached_items = {}
                    state.cached_items_sig = items_sig
                    state.cached_items_count = items_cnt
                    state.cached_tracks = tracks_now
                elseif not state.manual_context_prefer_track and items_cnt > 0 then
                    state.cached_props = Item.GetAggregatedProps(items_now)
                    state.cached_items = items_now
                    state.cached_items_sig = items_sig
                    state.cached_items_count = items_cnt
                    state.cached_tracks = tracks_now
                elseif #tracks_now > 0 then
                    state.cached_props = { take_type = 'Track', name = 'Selected Track' }
                    state.cached_items = items_now
                    state.cached_items_sig = items_sig
                    state.cached_items_count = items_cnt
                    state.cached_tracks = tracks_now
                else
                    state.cached_props = {}
                    state.cached_items = items_now
                    state.cached_items_sig = items_sig
                    state.cached_items_count = items_cnt
                    state.cached_tracks = tracks_now
                end
            else
                state.manual_context_override = false
                ApplyContextFromReaperCursor(state)
            end
        else
            if window_hovered then
                -- Left-click inside widget: don't change context (cache updated in visible block)
            else
                state.manual_context_override = false
                ApplyContextFromReaperCursor(state)
            end
        end
        state.last_mouse_state = true
        core.SetState(state)
    elseif ms_left == 0 and ms_right == 0 and state.last_mouse_state then
        state.last_mouse_button = 0
        state.last_mouse_state = false
        core.SetState(state)
    end

    if visible then
        local state = core.GetState()

        local items_count = (r.APIExists and r.APIExists("FIP_CountSelectedItems"))
            and math.floor(tonumber((r.FIP_CountSelectedItems("", 0))) or 0)
            or r.CountSelectedMediaItems(0)

        local items_sig = (r.APIExists and r.APIExists("FIP_GetSelectedItemsSignatureStr"))
            and (r.FIP_GetSelectedItemsSignatureStr("", 0) or "")
            or ""

        local items = {}
        if items_count == 1 then
            local it = r.GetSelectedMediaItem(0, 0)
            if it then items[1] = it end
        end

        local selected_tracks = Track.GetSelectedTracks()
        local tracks = selected_tracks
        if not state.manual_context_override and state.force_track_context and state.hovered_track and r.ValidatePtr(state.hovered_track, 'MediaTrack*') then
            tracks = { state.hovered_track }
        end

        local old_items_sig = state.cached_items_sig or ""
        local old_tracks = state.cached_tracks or {}

        local items_changed = (old_items_sig ~= items_sig)
        local tracks_changed = not Utils.shallow_equal(old_tracks, tracks)
        local should_update_cache = items_changed or tracks_changed

        if not state.manual_context_override then
            if not state.force_track_context then
                if items_count > 0 then
                    state.prefer_track_context = false
                elseif #tracks > 0 then
                    state.prefer_track_context = true
                end
            end
        end

        if should_update_cache then
            if state.manual_context_override then
                state.cached_items = items
                state.cached_items_sig = items_sig
                state.cached_items_count = items_count
                state.cached_tracks = tracks
                if state.manual_context_prefer_track and #tracks > 0 then
                    state.cached_props = { take_type = 'Track', name = 'Selected Track' }
                elseif not state.manual_context_prefer_track and items_count > 0 then
                    state.cached_props = Item.GetAggregatedProps(items)
                elseif state.manual_context_prefer_track and #tracks > 0 then
                    state.cached_props = { take_type = 'Track', name = 'Selected Track' }
                else
                    state.cached_props = {}
                end
            else
                if state.prefer_track_context and #tracks > 0 then
                    state.cached_props = { take_type = 'Track', name = 'Selected Track' }
                elseif items_count > 0 then
                    state.cached_props = Item.GetAggregatedProps(items)
                elseif #tracks > 0 then
                    state.cached_props = { take_type = 'Track', name = 'Selected Track' }
                else
                    state.cached_props = {}
                end
                state.cached_items = items
                state.cached_items_sig = items_sig
                state.cached_items_count = items_count
                state.cached_tracks = tracks
            end
        end

        local proj_cc = r.GetProjectStateChangeCount(0)
        local freeze_sel_key = GetTrackSelectionKey(tracks)
        if (state._freeze_sel_key ~= freeze_sel_key) or (state._freeze_proj_cc ~= proj_cc) or (state.freeze_stats == nil) then
            state.freeze_stats = Track.GetFreezeStats(tracks)
            state._freeze_sel_key = freeze_sel_key
            state._freeze_proj_cc = proj_cc
            core.SetState(state)
        end
        if items_count > 0 and not items_changed and not state.prefer_track_context then
            if state._items_proj_cc ~= proj_cc then
                state.cached_props = Item.GetAggregatedProps(items)
                state._items_proj_cc = proj_cc
                state.cache_time = r.time_precise()
                core.SetState(state)
                core.DebugAggregated(items, state.cached_props)
            end
        end
        if items_count > 0 and not state.prefer_track_context then
            local now = r.time_precise()
            local interval = state.update_interval or (1/30)
            if (now - (state.last_update_time or 0)) >= interval then
                state.cached_props = Item.GetAggregatedProps(items)
                state.last_update_time = now
                state.cache_time = now
                core.SetState(state)
                core.DebugAggregated(items, state.cached_props)
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
        local item_count = state.cached_items_count or #items

        if item_count > 1000 then
            props = { take_type = 'Warning', name = string.format('Too many items (%d). Performance may be affected.', item_count) }
        end

        core.CleanupOriginalProps()
        core.SetState(state)

        if not props and item_count == 0 and #tracks == 0 then
            pitch_module.ClearState()
            r.ImGui_Text(ctx, 'No items or tracks selected')
        elseif props then
            props.sel_item_count = item_count
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
                elseif item_count > 1 then
                    local hint_text = 'Multiple Items (' .. item_count .. '):'
                    if props.name and not props.name:match('^Multiple Items') then
                        hint_text = 'Multiple Items (' .. item_count .. '): ' .. props.name
                    end
                    changed, new_name = UI.MultiItemInput(ctx, '##MultipleItems', hint_text, '', -1, bar_color)
                    if changed and new_name ~= '' then
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsName") then
                            r.FIP_SetSelectedItemsName(new_name, 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsName not available\n")
                        end
                        props.name = new_name
                    end
                else
                    changed, new_name = UI.StyledInput(ctx, '##ObjectName', props.name or '', -1, bar_color)
                    if changed and new_name ~= (props.name or '') then
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsName") then
                            r.FIP_SetSelectedItemsName(new_name, 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsName not available\n")
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
                local has_track_note = false
                if single_track then
                    local _, note_text = r.GetSetMediaTrackInfo_String(single_track, 'P_NOTES', '', false)
                    if note_text and note_text ~= '' then
                        has_track_note = true
                    end
                end
                if has_track_note then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('black'))
                    UI.ColoredButton(ctx, 'N', 20, Theme.get('beige_base'), Theme.get('beige_hover'), Theme.get('beige_active'), function()
                        r.Main_OnCommand(43704, 0)
                    end)
                    r.ImGui_PopStyleColor(ctx, 1)
                else
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_gray'))
                    UI.ColoredButton(ctx, 'N', 20, Theme.get('gray_42'), Theme.get('gray_58'), Theme.get('gray_74'), function()
                        r.Main_OnCommand(43704, 0)
                    end)
                    r.ImGui_PopStyleColor(ctx, 1)
                end
                UI.Separator(ctx)
                local current_val = 0
                local has_mt_fx = false
                if single_track then
                    local v = Track.GetMidiTransposeValue(single_track)
                    if v ~= nil then current_val = v end
                    has_mt_fx = (Track.FindMidiTransposeFX(single_track) ~= nil)
                end
                local mt_label = 'MIDI Input:'
                local mt_label_w = select(1, r.ImGui_CalcTextSize(ctx, mt_label))
                local mt_changed, mt_new, mt_deactivated = UI.VerticalPitchControl(ctx, mt_label, current_val, 50, 0.1, -48, 48, '%.0f st', function()
                    if single_track then
                        local fx_idx = Track.FindMidiTransposeFX(single_track)
                        if fx_idx ~= nil then
                            Track.RemoveMidiTransposeFX({ single_track })
                        else
                            Track.SetMidiTransposeAbsolute({ single_track }, 0)
                        end
                    end
                end, mt_label_w + 8, nil, has_mt_fx, nil, nil, true, true)
                if mt_changed and single_track then
                    Track.UpdateMidiTransposeImmediate({ single_track }, mt_new)
                end
                if mt_deactivated and single_track then
                    Track.FinalizeMidiTranspose()
                end
                UI.Separator(ctx)
                -- HP/LP filters: one row, thin font, compact; width = content only (no extra space after LP)
                local freq_box_w = select(1, r.ImGui_CalcTextSize(ctx, "999 Hz")) + 16
                local FILTER_BLOCK_W = 32 + 2 + 4 + freq_box_w + 8 + 32 + 2 + 4 + freq_box_w + 8  -- HP btn + : + FreqBox + gap + LP btn + : + FreqBox + pad
                local FILTER_BLOCK_H = 22
                local hp_idx = single_track and Track.FindHPFilterFX(single_track) or nil
                local lp_idx = single_track and Track.FindLPFilterFX(single_track) or nil
                r.ImGui_PushID(ctx, "TrackFilters")
                PushFont(ctx, font, 12)
                r.ImGui_BeginChild(ctx, "##FilterBlock", FILTER_BLOCK_W, FILTER_BLOCK_H, r.ImGui_ChildFlags_None())
                if single_track then
                    local sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 44100
                    local fmax = math.min(sr * 0.499, 20000)
                    local hp_norm = 0
                    local lp_norm = 1
                    local hp_24 = true
                    local lp_24 = true
                    if hp_idx ~= nil then
                        hp_norm = Track.GetFilterFreqNorm(single_track, hp_idx) or 0
                        hp_24 = Track.GetFilterSlope24(single_track, hp_idx)
                    end
                    if lp_idx ~= nil then
                        lp_norm = Track.GetFilterFreqNorm(single_track, lp_idx) or 1
                        lp_24 = Track.GetFilterSlope24(single_track, lp_idx)
                    end
                    local hp_freq = Track.NormToFreq(hp_norm)
                    local lp_freq = Track.NormToFreq(lp_norm)
                    local hp_label = hp_24 and "HP4" or "HP2"
                    local lp_label = lp_24 and "LP4" or "LP2"
                    -- Hue from norm like JSFX: hue = norm * 0.78, L=0.75, S=1 -> RGB
                    local function freq_norm_to_color(norm)
                        norm = math.max(0, math.min(1, norm or 0))
                        local h = norm * 0.78
                        local L, S = 0.75, 1
                        local q = L < 0.5 and (L * (1 + S)) or (L + S - L * S)
                        local p = 2 * L - q
                        local function hue2rgb(t)
                            if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
                            if t < 0.166667 then return p + (q - p) * 6 * t end
                            if t < 0.5 then return q end
                            if t < 0.666667 then return p + (q - p) * (0.666667 - t) * 6 end
                            return p
                        end
                        local rv = hue2rgb(h + 0.333333)
                        local gv = hue2rgb(h)
                        local bv = hue2rgb(h - 0.333333)
                        return Theme.rgba(rv * 255, gv * 255, bv * 255, 255)
                    end
                    -- Display in box: "20k", "1k", "999 Hz"
                    local function format_freq_display(f)
                        if f >= 10000 then return string.format("%.0fk", f / 1000) end
                        if f >= 1000 then return string.format("%.1fk", f / 1000) end
                        return string.format("%.0f Hz", f)
                    end
                    local function hp_display_fn(norm) return format_freq_display(Track.NormToFreq(norm)) end
                    local function lp_display_fn(norm) return format_freq_display(Track.NormToFreq(norm)) end
                    -- HP: label (slope) + numeric box "20k"/"1k"/"999 Hz", left-mouse drag
                    r.ImGui_PushID(ctx, "HP")
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_white_soft'))
                    UI.StyledButton(ctx, hp_label .. "##HP", 32, function()
                        if hp_idx == nil then
                            Track.EnsureHPFilterOnly(single_track, hp_norm, not hp_24)
                            hp_idx = Track.FindHPFilterFX(single_track)
                        end
                        if hp_idx ~= nil then
                            Track.SetFilterSlope24(single_track, hp_idx, not hp_24, hp_norm)
                        end
                    end)
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_SameLine(ctx, 0, 2)
                    r.ImGui_Text(ctx, ":")
                    r.ImGui_SameLine(ctx, 0, 4)
                    local hp_changed, hp_new_norm, hp_activated = UI.FreqBox(ctx, "##HPFreq", hp_norm, freq_box_w, freq_norm_to_color(hp_norm), false, hp_display_fn, 0)
                    if hp_activated and hp_idx == nil then
                        Track.EnsureHPFilterOnly(single_track, hp_norm, hp_24)
                        hp_idx = Track.FindHPFilterFX(single_track)
                    end
                    if hp_changed then
                        local hp_new_freq = Track.NormToFreq(hp_new_norm)
                        hp_new_freq = math.max(20, math.min(fmax, hp_new_freq))
                        if hp_new_freq <= 20 and hp_idx ~= nil then
                            Track.RemoveHPFilterFX(single_track)
                            hp_idx = nil
                        elseif hp_idx == nil and hp_new_freq > 20 then
                            Track.EnsureHPFilterOnly(single_track, hp_new_norm, hp_24)
                            hp_idx = Track.FindHPFilterFX(single_track)
                        elseif hp_idx ~= nil then
                            Track.SetFilterFreqNorm(single_track, hp_idx, hp_new_norm)
                        end
                    end
                    r.ImGui_PopID(ctx)
                    -- LP: same numeric box, inverted drag (left = lower cutoff)
                    r.ImGui_SameLine(ctx, 0, 8)
                    r.ImGui_PushID(ctx, "LP")
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.get('text_white_soft'))
                    UI.StyledButton(ctx, lp_label .. "##LP", 32, function()
                        if lp_idx == nil then
                            Track.EnsureLPFilterOnly(single_track, lp_norm, not lp_24)
                            lp_idx = Track.FindLPFilterFX(single_track)
                        end
                        if lp_idx ~= nil then
                            Track.SetFilterSlope24(single_track, lp_idx, not lp_24, lp_norm)
                        end
                    end)
                    r.ImGui_PopStyleColor(ctx, 1)
                    r.ImGui_SameLine(ctx, 0, 2)
                    r.ImGui_Text(ctx, ":")
                    r.ImGui_SameLine(ctx, 0, 4)
                    local lp_changed, lp_new_norm, lp_activated = UI.FreqBox(ctx, "##LPFreq", lp_norm, freq_box_w, freq_norm_to_color(lp_norm), true, lp_display_fn, 1)
                    if lp_activated and lp_idx == nil then
                        Track.EnsureLPFilterOnly(single_track, lp_norm, lp_24)
                        lp_idx = Track.FindLPFilterFX(single_track)
                    end
                    if lp_changed then
                        local lp_new_freq = Track.NormToFreq(lp_new_norm)
                        lp_new_freq = math.max(20, math.min(fmax, lp_new_freq))
                        if lp_new_freq >= fmax and lp_idx ~= nil then
                            Track.RemoveLPFilterFX(single_track)
                            lp_idx = nil
                        elseif lp_idx == nil and lp_new_freq < fmax then
                            Track.EnsureLPFilterOnly(single_track, lp_new_norm, lp_24)
                            lp_idx = Track.FindLPFilterFX(single_track)
                        elseif lp_idx ~= nil then
                            Track.SetFilterFreqNorm(single_track, lp_idx, lp_new_norm)
                        end
                    end
                    r.ImGui_PopID(ctx)
                else
                    r.ImGui_Text(ctx, "HP / LP")
                end
                r.ImGui_EndChild(ctx)
                r.ImGui_PopFont(ctx)
                r.ImGui_PopID(ctx)
                UI.Separator(ctx)
                local has_track_pitch_api = (r.APIExists and r.APIExists("FIP_GetSelectedTracksItemsPitchStatsStr"))
                    and (r.APIExists and r.APIExists("FIP_AddSelectedTracksItemsPitchVal"))
                    and (r.APIExists and r.APIExists("FIP_ResetSelectedTracksItemsPitchVal"))
                local track_item_count, items_pitch, items_modified, items_mixed = 0, 0, false, false
                if has_track_pitch_api and #tracks > 0 then
                    track_item_count, items_pitch, items_modified, items_mixed = pitch_module.GetSelectedTracksItemsPitchInfo()
                end
                local has_track_items = has_track_pitch_api and (track_item_count > 0)
                if not has_track_items then
                    r.ImGui_BeginDisabled(ctx, true)
                end
                local it_label = 'Track Items Transpose'
                local it_label_w = select(1, r.ImGui_CalcTextSize(ctx, it_label))
                local it_changed, it_new, it_deactivated = UI.VerticalPitchControl(ctx, it_label, items_pitch, 50, 0.1, -96, 96, '%.0f st', function()
                    if has_track_items then
                        pitch_module.HandleSelectedTracksItemsPitchReset()
                    end
                end, it_label_w + 8, nil, items_modified, items_mixed, has_track_items and track_item_count or 0, nil, false)
                if not has_track_items then
                    r.ImGui_EndDisabled(ctx)
                    it_changed = false
                    it_deactivated = false
                end
                if has_track_items then
                    if it_changed then
                        local updated_pitch = pitch_module.HandleSelectedTracksItemsPitchChange(it_new, items_pitch)
                        items_pitch = updated_pitch
                    end
                    if it_deactivated then
                        pitch_module.ResetSelectedTracksItemsPitchDelta()
                        pitch_module.FinalizePitchChange()
                    end
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

                local playback_offset_enabled = false
                local playback_offset_ms = playback_offset_last_ms or 0.0
                local playback_offset_unit = playback_offset_last_unit or 'ms'
                local sr = r.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false) or 0

                if single_track then
                    local flag = r.GetMediaTrackInfo_Value(single_track, 'I_PLAY_OFFSET_FLAG') or 0
                    local raw = r.GetMediaTrackInfo_Value(single_track, 'D_PLAY_OFFSET') or 0.0
                    local flag_int = math.floor(flag + 0.5)
                    local disabled = (flag_int & 1) ~= 0
                    local unit_samples = (flag_int & 2) ~= 0
                    local track_guid = r.GetTrackGUID(single_track)
                    playback_offset_enabled = not disabled

                    if playback_offset_enabled or not playback_offset_last_valid or playback_offset_last_guid ~= track_guid then
                        if unit_samples and sr > 0 then
                            playback_offset_unit = 'samples'
                            playback_offset_ms = (raw / sr) * 1000.0
                        else
                            playback_offset_unit = 'ms'
                            playback_offset_ms = raw * 1000.0
                        end
                        playback_offset_last_ms = playback_offset_ms
                        playback_offset_last_unit = playback_offset_unit
                        playback_offset_last_guid = track_guid
                        playback_offset_last_valid = true
                    else
                        playback_offset_ms = playback_offset_last_ms or playback_offset_ms
                        playback_offset_unit = playback_offset_last_unit or playback_offset_unit
                    end
                else
                    playback_offset_last_valid = false
                    playback_offset_last_guid = nil
                end

                local delay_disabled = not single_track
                local delay_checked = playback_offset_enabled
                local delay_changed, delay_value = UI.StyledCheckbox(ctx, 'Delay', delay_checked, false, delay_disabled)
                if delay_changed and single_track then
                    Utils.with_undo('Toggle Play Offset', function()
                        r.Main_OnCommand(42232, 0)
                    end)
                end

                r.ImGui_SameLine(ctx, 0, 8)

                local knob_disabled = not single_track
                if knob_disabled then r.ImGui_BeginDisabled(ctx, true) end

                local knob_value
                local min_val
                local max_val
                if playback_offset_unit == 'samples' and sr > 0 then
                    local range_samples = sr
                    min_val = -range_samples
                    max_val = range_samples
                    knob_value = (playback_offset_ms / 1000.0) * sr
                else
                    local range_ms = 1000.0
                    min_val = -range_ms
                    max_val = range_ms
                    knob_value = playback_offset_ms
                end

                local knob_changed, knob_new, knob_deactivated, knob_reset = UI.Knob(ctx, 'TrackDelayKnob', knob_value, min_val, max_val, 0.0, nil, playback_offset_enabled)

                if (knob_changed or knob_reset) and single_track then
                    if knob_reset then
                        playback_offset_ms = 0.0
                    else
                        local new_ms
                        if playback_offset_unit == 'samples' and sr > 0 then
                            new_ms = (knob_new / sr) * 1000.0
                        else
                            new_ms = knob_new
                        end
                        playback_offset_ms = new_ms
                    end

                    local track_guid = r.GetTrackGUID(single_track)
                    if track_guid then
                        playback_offset_last_guid = track_guid
                        playback_offset_last_ms = playback_offset_ms
                        playback_offset_last_unit = playback_offset_unit
                        playback_offset_last_valid = true
                    end

                    local raw
                    if playback_offset_unit == 'samples' and sr > 0 then
                        raw = (playback_offset_ms / 1000.0) * sr
                    else
                        raw = playback_offset_ms / 1000.0
                    end

                    local unit_bit = (playback_offset_unit == 'samples' and sr > 0) and 2 or 0
                    local disabled_bit = playback_offset_enabled and 0 or 1
                    local flag = unit_bit | disabled_bit
                    r.SetMediaTrackInfo_Value(single_track, 'I_PLAY_OFFSET_FLAG', flag)
                    r.SetMediaTrackInfo_Value(single_track, 'D_PLAY_OFFSET', raw)
                    r.TrackList_AdjustWindows(0)
                    r.UpdateArrange()
                end

                if knob_deactivated and single_track then
                    Utils.with_undo('Change Play Offset', function() end)
                end

                if knob_disabled then r.ImGui_EndDisabled(ctx) end

                r.ImGui_SameLine(ctx, 0, 6)

                if single_track and playback_offset_enabled then
                    local display_value
                    local display_label
                    if playback_offset_unit == 'samples' and sr > 0 then
                        local samples = (playback_offset_ms / 1000.0) * sr
                        display_value = samples
                        display_label = string.format('%+d', math.floor(samples + 0.5))
                    else
                        display_value = playback_offset_ms
                        display_label = string.format('%+.1f', playback_offset_ms)
                    end
                    if UI.TextButton(ctx, display_label .. '##PlayOffsetValue', 70) then
                        playback_offset_edit_focus = true
                        r.ImGui_OpenPopup(ctx, 'PlayOffsetEdit')
                    end
                    if r.ImGui_BeginPopup(ctx, 'PlayOffsetEdit') then
                        if playback_offset_edit_focus then
                            r.ImGui_SetKeyboardFocusHere(ctx)
                            playback_offset_edit_focus = false
                        end
                        local edit_value = display_value
                        if playback_offset_unit == 'samples' and sr > 0 then
                            local changed, new_value, deactivated = UI.DragDoubleInput(ctx, '##PlayOffsetEditSamples', edit_value, 80, 1.0, -sr, sr, '%.0f')
                            if changed then
                                edit_value = new_value
                                playback_offset_ms = (edit_value / sr) * 1000.0
                            end
                            if deactivated then
                                if playback_offset_enabled then
                                    Utils.with_undo('Set Play Offset', function()
                                        local samples = math.floor(edit_value + 0.5)
                                        local raw = samples
                                        local unit_bit = 2
                                        local disabled_bit = 0
                                        local flag = unit_bit | disabled_bit
                                        r.SetMediaTrackInfo_Value(single_track, 'I_PLAY_OFFSET_FLAG', flag)
                                        r.SetMediaTrackInfo_Value(single_track, 'D_PLAY_OFFSET', raw)
                                        r.TrackList_AdjustWindows(0)
                                        r.UpdateArrange()
                                    end)
                                end
                                r.ImGui_CloseCurrentPopup(ctx)
                                Utils.DeferClearCursorContext()
                            end
                        else
                            local changed, new_value, deactivated = UI.DragDoubleInput(ctx, '##PlayOffsetEditMs', edit_value, 80, 0.1, -1000.0, 1000.0, '%.1f')
                            if changed then
                                edit_value = new_value
                                playback_offset_ms = edit_value
                            end
                            if deactivated then
                                if playback_offset_enabled then
                                    Utils.with_undo('Set Play Offset', function()
                                        local raw = playback_offset_ms / 1000.0
                                        local unit_bit = 0
                                        local disabled_bit = 0
                                        local flag = unit_bit | disabled_bit
                                        r.SetMediaTrackInfo_Value(single_track, 'I_PLAY_OFFSET_FLAG', flag)
                                        r.SetMediaTrackInfo_Value(single_track, 'D_PLAY_OFFSET', raw)
                                        r.TrackList_AdjustWindows(0)
                                        r.UpdateArrange()
                                    end)
                                end
                                r.ImGui_CloseCurrentPopup(ctx)
                                Utils.DeferClearCursorContext()
                            end
                        end
                        if r.ImGui_Button(ctx, 'Close') then
                            r.ImGui_CloseCurrentPopup(ctx)
                            Utils.DeferClearCursorContext()
                        end
                        r.ImGui_EndPopup(ctx)
                    end
                end

                r.ImGui_SameLine(ctx, 0, 6)

                local unit_label = ''
                if playback_offset_enabled then
                    unit_label = (playback_offset_unit == 'samples') and 'samples' or 'ms'
                end
                local units_disabled = (not single_track) or (not playback_offset_enabled)
                if units_disabled then r.ImGui_BeginDisabled(ctx, true) end
                if UI.TextButton(ctx, unit_label .. '##PlayOffsetUnits', 60) then
                    r.ImGui_OpenPopup(ctx, 'PlayOffsetUnits')
                end
                if r.ImGui_BeginPopup(ctx, 'PlayOffsetUnits') then
                    if r.ImGui_MenuItem(ctx, 'Milliseconds', nil, playback_offset_unit == 'ms') and single_track then
                        if playback_offset_unit ~= 'ms' then
                            Utils.with_undo('Change Play Offset Units', function()
                                playback_offset_unit = 'ms'
                                local unit_bit = 0
                                local disabled_bit = playback_offset_enabled and 0 or 1
                                local flag = unit_bit | disabled_bit
                                r.SetMediaTrackInfo_Value(single_track, 'I_PLAY_OFFSET_FLAG', flag)
                                local raw = playback_offset_ms / 1000.0
                                r.SetMediaTrackInfo_Value(single_track, 'D_PLAY_OFFSET', raw)
                                r.TrackList_AdjustWindows(0)
                                r.UpdateArrange()
                            end)
                        end
                    end
                    if r.ImGui_MenuItem(ctx, 'Samples', nil, playback_offset_unit == 'samples') and single_track and sr > 0 then
                        if playback_offset_unit ~= 'samples' then
                            Utils.with_undo('Change Play Offset Units', function()
                                playback_offset_unit = 'samples'
                                local unit_bit = 2
                                local disabled_bit = playback_offset_enabled and 0 or 1
                                local flag = unit_bit | disabled_bit
                                r.SetMediaTrackInfo_Value(single_track, 'I_PLAY_OFFSET_FLAG', flag)
                                local samples = (playback_offset_ms / 1000.0) * sr
                                r.SetMediaTrackInfo_Value(single_track, 'D_PLAY_OFFSET', samples)
                                r.TrackList_AdjustWindows(0)
                                r.UpdateArrange()
                            end)
                        end
                    end
                    r.ImGui_EndPopup(ctx)
                end
                if units_disabled then r.ImGui_EndDisabled(ctx) end

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
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                            r.FIP_SetSelectedItemsPlaybackRate("1.0", 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                        end
                    end)
                    local state2 = core.GetState()
                    state2.cached_props = Item.GetAggregatedProps(items)
                    core.SetState(state2)
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
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                            r.FIP_SetSelectedItemsPlaybackRate(tostring(rate), 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                        end
                    end
                    if r.ImGui_Button(ctx, 'Close') then
                        r.ImGui_CloseCurrentPopup(ctx)
                        Utils.DeferClearCursorContext()
                    end
                    r.ImGui_EndPopup(ctx)
                end
                UI.Separator(ctx)
                local project_tempo = r.Master_GetTempo()
                local current_bpm = props.bpm or project_tempo
                local bpm_modified = math.abs(current_bpm - project_tempo) > 0.0001
                local bmp_changed, bpm, bpm_deactivated = UI.VerticalPitchControl(ctx, 'BPM:', current_bpm, 50, 1.0, 20, 999, '%.0f', function()
                    props.bpm = project_tempo
                    props.playback_rate = 1.0
                    Utils.with_undo('Reset BPM', function()
                        if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                            r.FIP_SetSelectedItemsPlaybackRate("1.0", 0)
                        else
                            r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                        end
                    end)
                end, 40, nil, bpm_modified, false, item_count, nil, false)
                if bmp_changed then
                    props.bpm = bpm
                    props.playback_rate = project_tempo / bpm
                    if r.APIExists and r.APIExists("FIP_SetSelectedItemsPlaybackRate") then
                        r.FIP_SetSelectedItemsPlaybackRate(tostring(props.playback_rate), 0)
                    else
                        r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPlaybackRate not available\n")
                    end
                end
                if bmp_deactivated then
                    Utils.with_undo('Change BPM', function() end)
                end
                UI.Separator(ctx)
                local preserve_value = props.preserve_pitch
                local preserve_mixed = (preserve_value == nil)
                local preserve_disabled = (props.take_type == 'MIDI')
                local preserve_changed, preserve = UI.StyledCheckbox(ctx, 'Preserve', preserve_value, preserve_mixed, preserve_disabled)
                if preserve_changed and not preserve_disabled then
                    props.preserve_pitch = preserve
                    Item.UpdatePreservePitch(items, preserve)
                    local state2 = core.GetState()
                    state2.cached_props = Item.GetAggregatedProps(items)
                    core.SetState(state2)
                end
                UI.Separator(ctx)
                TimestrechWidget.Render(ctx, props, items, Item, UI.StyledResetButton)
                UI.Separator(ctx)
                if props.take_type == 'Audio' or props.take_type == 'MIDI' or props.take_type == 'Mult' then
                    if item_count > 1 then UI.ResetAggHoverRegion() end
                    local is_multi = (item_count > 1)
                    local transpose_midi_mode = (r.GetExtState("Frenkie_Inspector", "TransposeMIDI") == "1")
                    -- Use Delta/Accumulator mode for Multi-selection OR when Transpose MIDI is active (since we need relative edits for MIDI)
                    local use_delta_mode = is_multi or (transpose_midi_mode and (props.take_type == 'MIDI' or props.take_type == 'Mult'))
                    
                    local base_pitch = 0
                    local is_mixed = false
                    local is_modified = false
                    
                    if use_delta_mode then
                        local pitch_state = (r.APIExists and r.APIExists("FIP_GetSelectedItemsPitchStateVal"))
                            and (r.FIP_GetSelectedItemsPitchStateVal("", 0) or 0)
                            or 0
                        is_mixed = (pitch_state < 0)
                        is_modified = (pitch_state > 0)
                        base_pitch = (r.APIExists and r.APIExists("FIP_GetSelectedItemsPitchDeltaVal"))
                            and (r.FIP_GetSelectedItemsPitchDeltaVal("", 0) or 0)
                            or 0
                    else
                        local pitch_str = (r.APIExists and r.APIExists("FIP_GetAggregatedPitch")) and r.FIP_GetAggregatedPitch("", 0) or "0"
                        is_mixed = (pitch_str == "MIXED")
                        base_pitch = is_mixed and 0 or tonumber(pitch_str or "0") or 0
                        is_modified = (not is_mixed) and math.abs(base_pitch) > 0.001
                    end
                    local pitch_changed, new_pitch, pitch_deactivated = UI.VerticalPitchControl(ctx, 'Pitch:', base_pitch, 50, 0.1, -96, 96, '%.0f st', function()
                        local transpose_midi_mode_cb = (r.GetExtState("Frenkie_Inspector", "TransposeMIDI") == "1")
                        if props.take_type == 'MIDI' and transpose_midi_mode_cb then
                            if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                r.FIP_SetSelectedItemsPitch("0", 0)
                            end
                            props.pitch = 0
                        else
                            if use_delta_mode then
                                if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                    r.FIP_SetSelectedItemsPitch("0", 0)
                                else
                                    r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
                                end
                                if r.APIExists and r.APIExists("FIP_ResetSelectedItemsPitchDeltaVal") then
                                    r.FIP_ResetSelectedItemsPitchDeltaVal("", 0)
                                end
                                props.pitch = 0
                            else
                                if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                    r.FIP_SetSelectedItemsPitch("0", 0)
                                else
                                    r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
                                end
                                props.pitch = 0
                            end
                        end
                    end, nil, false, is_modified, is_mixed, item_count, nil, false)
                    if pitch_changed then
                        if use_delta_mode then
                            local delta = new_pitch - base_pitch
                            if math.abs(delta) > 0.0001 then
                                if r.APIExists and r.APIExists("FIP_ApplyAddSelectedItemsPitchDeltaVal") then
                                    r.FIP_ApplyAddSelectedItemsPitchDeltaVal(tostring(delta), 0)
                                else
                                    r.ShowConsoleMsg("ERROR: FIP_ApplyAddSelectedItemsPitchDeltaVal not available\n")
                                end
                            end
                            props.pitch = new_pitch
                        else
                            if r.APIExists and r.APIExists("FIP_SetSelectedItemsPitch") then
                                r.FIP_SetSelectedItemsPitch(tostring(new_pitch), 0)
                            else
                                r.ShowConsoleMsg("ERROR: FIP_SetSelectedItemsPitch not available\n")
                            end
                            props.pitch = new_pitch
                            state.cached_props = Item.GetAggregatedProps(items)
                            core.SetState(state)
                        end
                    end
                    if pitch_deactivated then
                        if use_delta_mode then
                            pitch_module.FinalizeMIDITranspose(items)
                            -- Force refresh properties to ensure UI snaps back to 0 (since Item Pitch didn't change)
                            state.cached_props = Item.GetAggregatedProps(items)
                            core.SetState(state)
                        else
                            Utils.with_undo("Change Pitch", function() end)
                        end
                    end
                    UI.Separator(ctx)
                end
                Fader.RenderFaders(ctx, items, props, bar_color, UI)
                
                if item_count > 1 then
                    UI.ShowTooltipDelayedIfHoveredInAggRegion(ctx, 'agg_unified', 'Режим Агрегации:\n\nВ данном режиме все внесённые изменения\nс собственными значениями выделенных объектов', 0.5)
                end
                UI.Separator(ctx)
                local has_fx = (item_count == 1) and Item.ItemHasFX(items[1]) or false
                local function fx_action()
                    local mods = r.ImGui_GetKeyMods(ctx)
                    local alt_pressed = (mods & r.ImGui_Mod_Alt()) ~= 0
                    local cmd_pressed = (mods & r.ImGui_Mod_Super()) ~= 0
                    local ctrl_pressed = (mods & r.ImGui_Mod_Ctrl()) ~= 0
                    local selected_items = items
                    if item_count > 1 then
                        selected_items = Item.GetSelectedItems()
                    end
                    if alt_pressed then
                        Item.RemoveAllFX(selected_items)
                    elseif (cmd_pressed or ctrl_pressed) then
                        local any_fx = false
                        if item_count == 1 then
                            any_fx = has_fx
                        else
                            for _, item in ipairs(selected_items) do
                                if Item.ItemHasFX(item) then
                                    any_fx = true
                                    break
                                end
                            end
                        end
                        if any_fx then
                            r.Main_OnCommand(40209, 0)
                        else
                            Item.OpenFXChain(selected_items)
                        end
                    else
                        Item.OpenFXChain(selected_items)
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
                    state.cached_props = Item.GetAggregatedProps(items)
                    core.SetState(state)
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
                    state.cached_props = Item.GetAggregatedProps(items)
                    core.SetState(state)
                end
                r.ImGui_SameLine(ctx, 0, 8)
                local lock_value = props.lock
                local lock_mixed = (lock_value == nil)
                local lock_changed, lock = UI.IconToggleTri(ctx, '##LockIcon', lock_icon_locked, lock_icon_unlocked, lock_icon_mixed, lock_value, lock_mixed, 20)
                if lock_changed then
                    props.lock = lock
                    Item.UpdateLock(items, lock)
                    state.cached_props = Item.GetAggregatedProps(items)
                    core.SetState(state)
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
