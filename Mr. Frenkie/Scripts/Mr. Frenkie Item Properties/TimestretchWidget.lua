---@diagnostic disable: undefined-global, undefined-field
local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

package.path = script_dir .. "?.lua;" .. script_dir .. "?/init.lua;" .. package.path
local Utils = require("Utils")
local UI = require("UIComponents")
local Theme = require("Theme")

local TimestrechWidget = {}
local open_settings_alg = nil

local modes = {
    [-1] = "Project Default",
    [9] = "Elastique 3 Pro",
    [10] = "Elastique 3 Efficient",
    [11] = "Elastique 3 Soloist",
    [12] = "Rubber Band Library",
    [14] = "Rrreeeaaa",
    [0] = "SoundTouch",
    [15] = "ReaReaRea",
    [2] = "Simple windowed",
}

local mode_names = {
    "Project Default",
    "Elastique 3 Pro",
    "Elastique 3 Efficient",
    "Elastique 3 Soloist",
    "Rubber Band Library",
    "Rrreeeaaa",
    "SoundTouch",
    "ReaReaRea",
    "Simple windowed",
}

local mode_indices = {
    -1, 9, 10, 11, 12, 14, 0, 15, 2
}

local mode_names_str = table.concat(mode_names, '\0') .. '\0'

function TimestrechWidget.GetModeIndex(mode_value)
    if mode_value == nil then return 0 end
    for i, v in ipairs(mode_indices) do
        if v == mode_value then
            return i - 1
        end
    end
    return 0
end

function TimestrechWidget.GetModeValue(index)
    return mode_indices[index + 1] or -1
end

function TimestrechWidget.IsModeModified(mode_value)
    return mode_value ~= nil and mode_value ~= -1
end

local function RenderDisabledModeLabel(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.get('transparent'))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.get('transparent'))
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_Button(ctx, 'Mode:', 40)
    r.ImGui_EndDisabled(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
end

function TimestrechWidget.Render(ctx, props, items, core, StyledResetButton)
    if props.take_type == "MIDI" then
        RenderDisabledModeLabel(ctx)
        r.ImGui_SameLine(ctx, 0, 5)
        r.ImGui_SetNextItemWidth(ctx, 120)
        r.ImGui_BeginDisabled(ctx, true)
        r.ImGui_Combo(ctx, '##Mode', 0, "Audio Only\0\0")
        r.ImGui_EndDisabled(ctx)
    elseif props.take_type == "Mult" then
        RenderDisabledModeLabel(ctx)
        r.ImGui_SameLine(ctx, 0, 5)
        r.ImGui_BeginDisabled(ctx, true)
        r.ImGui_SetNextItemWidth(ctx, 120)
        r.ImGui_InputText(ctx, "##ModeAudioOnly", "Audio Only", r.ImGui_InputTextFlags_ReadOnly())
        r.ImGui_EndDisabled(ctx)
    else
        local mode_index = TimestrechWidget.GetModeIndex(props.mode)
        local is_mode_modified = TimestrechWidget.IsModeModified(props.mode)
        local is_mode_mixed = (props.mode == nil)
        StyledResetButton(ctx, 'Mode:', 40, is_mode_modified, function()
            props.mode = -1
            Utils.with_undo("Reset Mode to Project Default", function()
                local mode_props = { mode = -1, mode_bits = 0 }
                core.SetAllItemsProps(items, mode_props)
            end)
        end, nil, is_mode_mixed)
        r.ImGui_SameLine(ctx, 0, 5)
        local current_name = TimestrechWidget.GetModeName(props.mode)
        if is_mode_mixed then current_name = "Multiple" end
        if UI.TextButton(ctx, (current_name or "Project Default") .. '##PitchModeMenu', 120) then
            r.ImGui_OpenPopup(ctx, 'PitchModeMenu')
        end
        if r.ImGui_BeginPopup(ctx, 'PitchModeMenu') then
            local function get_current_bits()
                local bits = 0
                if #items >= 1 then
                    local it = items[1]
                    if it and r.ValidatePtr(it, 'MediaItem*') then
                        local tk = r.GetActiveTake(it)
                        if tk then
                            local pm = r.GetMediaItemTakeInfo_Value(tk, "I_PITCHMODE")
                            if pm ~= -1 then
                                bits = pm & 0xFFFF
                            end
                        end
                    end
                end
                return bits
            end
            local function SectionHeader(ctx2, label, with_separator, accent_color)
                if with_separator then
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Separator(), accent_color or Theme.get('pipe_gray'))
                    r.ImGui_Separator(ctx2)
                    r.ImGui_PopStyleColor(ctx2, 1)
                end
                r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Text(), accent_color or Theme.get('text_gray'))
                r.ImGui_Text(ctx2, label)
                r.ImGui_PopStyleColor(ctx2, 1)
            end
            local function apply_mode(alg, bits)
                props.mode = alg
                Utils.with_undo("Change Mode", function()
                    core.SetAllItemsProps(items, { mode = alg, mode_bits = bits or 0 })
                end)
                Utils.DeferClearCursorContext()
            end
            local function apply_opt_settings(alg, formant, opt_mode)
                local b = ((opt_mode or 0) << 8) | (formant or 0)
                apply_mode(alg, b)
            end
            local function DrawSettings(ctx2, alg, bits_now, accent_color)
                if alg == 9 or alg == 10 or alg == 11 then
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderHovered(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderActive(), accent_color)
                    local opt_idx = (bits_now >> 8) & 0x03
                    local frm_idx = bits_now & 0x03
                    SectionHeader(ctx2, "Optimization", false, accent_color)
                    if r.ImGui_Selectable(ctx2, "Standard", (opt_idx == 0)) then
                        apply_opt_settings(alg, frm_idx, 0)
                    end
                    if r.ImGui_Selectable(ctx2, "Tonal optimized", (opt_idx == 1)) then
                        apply_opt_settings(alg, frm_idx, 1)
                    end
                    if r.ImGui_Selectable(ctx2, "Transient optimized", (opt_idx == 2)) then
                        apply_opt_settings(alg, frm_idx, 2)
                    end
                    SectionHeader(ctx2, "Formants", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Off", (frm_idx == 0)) then
                        apply_opt_settings(alg, 0, opt_idx)
                    end
                    if r.ImGui_Selectable(ctx2, "Light", (frm_idx == 1)) then
                        apply_opt_settings(alg, 1, opt_idx)
                    end
                    if r.ImGui_Selectable(ctx2, "Most pitches", (frm_idx == 2)) then
                        apply_opt_settings(alg, 2, opt_idx)
                    end
                    if r.ImGui_Selectable(ctx2, "Strong", (frm_idx == 3)) then
                        apply_opt_settings(alg, 3, opt_idx)
                    end
                    r.ImGui_PopStyleColor(ctx2, 3)
                    return
                end
                if alg == 12 then
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderHovered(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderActive(), accent_color)
                    local rb_trans   =  bits_now        & 0x03
                    local rb_det     = (bits_now >> 2)  & 0x03
                    local rb_window  = (bits_now >> 4)  & 0x03
                    local rb_pitch   = (bits_now >> 6)  & 0x03
                    local rb_engine  = (bits_now >> 8)  & 0x01
                    local function rb_pack(t, d, w, p, e)
                        return (t & 0x03) | ((d & 0x03) << 2) | ((w & 0x03) << 4) | ((p & 0x03) << 6) | ((e & 0x01) << 8)
                    end
                    SectionHeader(ctx2, "Transients", false, accent_color)
                    if r.ImGui_Selectable(ctx2, "Crisp", (rb_trans == 0)) then
                        apply_mode(alg, rb_pack(0, rb_det, rb_window, rb_pitch, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "Mixed", (rb_trans == 1)) then
                        apply_mode(alg, rb_pack(1, rb_det, rb_window, rb_pitch, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "Smooth", (rb_trans == 2)) then
                        apply_mode(alg, rb_pack(2, rb_det, rb_window, rb_pitch, rb_engine))
                    end
                    SectionHeader(ctx2, "Detector", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Compound", (rb_det == 0)) then
                        apply_mode(alg, rb_pack(rb_trans, 0, rb_window, rb_pitch, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "Percussive", (rb_det == 1)) then
                        apply_mode(alg, rb_pack(rb_trans, 1, rb_window, rb_pitch, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "Soft", (rb_det == 2)) then
                        apply_mode(alg, rb_pack(rb_trans, 2, rb_window, rb_pitch, rb_engine))
                    end
                    SectionHeader(ctx2, "Window", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Standard", (rb_window == 0)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, 0, rb_pitch, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "Short", (rb_window == 1)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, 1, rb_pitch, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "Long", (rb_window == 2)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, 2, rb_pitch, rb_engine))
                    end
                    SectionHeader(ctx2, "Pitch mode", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "High speed", (rb_pitch == 0)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, rb_window, 0, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "High quality", (rb_pitch == 1)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, rb_window, 1, rb_engine))
                    end
                    if r.ImGui_Selectable(ctx2, "High consistency", (rb_pitch == 2)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, rb_window, 2, rb_engine))
                    end
                    SectionHeader(ctx2, "Engine", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Faster (R2)", (rb_engine == 0)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, rb_window, rb_pitch, 0))
                    end
                    if r.ImGui_Selectable(ctx2, "Finer (R3)", (rb_engine == 1)) then
                        apply_mode(alg, rb_pack(rb_trans, rb_det, rb_window, rb_pitch, 1))
                    end
                    r.ImGui_PopStyleColor(ctx2, 3)
                    return
                end
                if alg == 14 then
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderHovered(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderActive(), accent_color)
                    local rr_fft    =  bits_now        & 0x03
                    local rr_offset = (bits_now >> 2)  & 0x03
                    local rr_awin   = (bits_now >> 4)  & 0x03
                    local rr_synth  = (bits_now >> 6)  & 0x07
                    local rr_swin   = (bits_now >> 9)  & 0x03
                    local function rr_pack(f, o, aw, so, sw)
                        return (f & 0x03) | ((o & 0x03) << 2) | ((aw & 0x03) << 4) | ((so & 0x07) << 6) | ((sw & 0x03) << 9)
                    end
                    SectionHeader(ctx2, "FFT", false, accent_color)
                    if r.ImGui_Selectable(ctx2, "32768 [default]", (rr_fft == 0)) then
                        apply_mode(alg, rr_pack(0, rr_offset, rr_awin, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "16384", (rr_fft == 1)) then
                        apply_mode(alg, rr_pack(1, rr_offset, rr_awin, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "8192", (rr_fft == 2)) then
                        apply_mode(alg, rr_pack(2, rr_offset, rr_awin, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "4096", (rr_fft == 3)) then
                        apply_mode(alg, rr_pack(3, rr_offset, rr_awin, rr_synth, rr_swin))
                    end
                    SectionHeader(ctx2, "analysis offset", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "1/2 [default]", (rr_offset == 0)) then
                        apply_mode(alg, rr_pack(rr_fft, 0, rr_awin, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "1/4", (rr_offset == 1)) then
                        apply_mode(alg, rr_pack(rr_fft, 1, rr_awin, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "1/6", (rr_offset == 2)) then
                        apply_mode(alg, rr_pack(rr_fft, 2, rr_awin, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "1/8", (rr_offset == 3)) then
                        apply_mode(alg, rr_pack(rr_fft, 3, rr_awin, rr_synth, rr_swin))
                    end
                    SectionHeader(ctx2, "analysis window", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "blackman–harris [default]##rr_awin_bh", (rr_awin == 0)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, 0, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "hamming##rr_awin_hm", (rr_awin == 1)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, 1, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "blackman##rr_awin_bm", (rr_awin == 2)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, 2, rr_synth, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "rectangular##rr_awin_rc", (rr_awin == 3)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, 3, rr_synth, rr_swin))
                    end
                    SectionHeader(ctx2, "synthesis", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "3x [a bit pulsing]", (rr_synth == 0)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 0, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "4x [default]", (rr_synth == 1)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 1, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "5x", (rr_synth == 2)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 2, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "6x", (rr_synth == 3)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 3, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "7x", (rr_synth == 4)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 4, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "8x", (rr_synth == 5)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 5, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "9x", (rr_synth == 6)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 6, rr_swin))
                    end
                    if r.ImGui_Selectable(ctx2, "10x", (rr_synth == 7)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, 7, rr_swin))
                    end
                    SectionHeader(ctx2, "synthesis window", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "blackman–harris [default]##rr_swin_bh", (rr_swin == 0)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, rr_synth, 0))
                    end
                    if r.ImGui_Selectable(ctx2, "hamming##rr_swin_hm", (rr_swin == 1)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, rr_synth, 1))
                    end
                    if r.ImGui_Selectable(ctx2, "blackman##rr_swin_bm", (rr_swin == 2)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, rr_synth, 2))
                    end
                    if r.ImGui_Selectable(ctx2, "triangular##rr_swin_tr", (rr_swin == 3)) then
                        apply_mode(alg, rr_pack(rr_fft, rr_offset, rr_awin, rr_synth, 3))
                    end
                    r.ImGui_PopStyleColor(ctx2, 3)
                    return
                end
                if alg == 0 then
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderHovered(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderActive(), accent_color)
                    local st_seq    =  bits_now        & 0x03
                    local st_seek   = (bits_now >> 2)  & 0x03
                    local st_over   = (bits_now >> 4)  & 0x03
                    local function st_pack(sq, sk, ov)
                        return (sq & 0x03) | ((sk & 0x03) << 2) | ((ov & 0x03) << 4)
                    end
                    SectionHeader(ctx2, "Sequence length", false, accent_color)
                    if r.ImGui_Selectable(ctx2, "Default##st_seq_def", (st_seq == 0)) then
                        apply_mode(alg, st_pack(0, st_seek, st_over))
                    end
                    if r.ImGui_Selectable(ctx2, "Short##st_seq_short", (st_seq == 1)) then
                        apply_mode(alg, st_pack(1, st_seek, st_over))
                    end
                    if r.ImGui_Selectable(ctx2, "Medium##st_seq_med", (st_seq == 2)) then
                        apply_mode(alg, st_pack(2, st_seek, st_over))
                    end
                    if r.ImGui_Selectable(ctx2, "Long##st_seq_long", (st_seq == 3)) then
                        apply_mode(alg, st_pack(3, st_seek, st_over))
                    end
                    SectionHeader(ctx2, "Search window", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Default##st_seek_def", (st_seek == 0)) then
                        apply_mode(alg, st_pack(st_seq, 0, st_over))
                    end
                    if r.ImGui_Selectable(ctx2, "Short##st_seek_short", (st_seek == 1)) then
                        apply_mode(alg, st_pack(st_seq, 1, st_over))
                    end
                    if r.ImGui_Selectable(ctx2, "Medium##st_seek_med", (st_seek == 2)) then
                        apply_mode(alg, st_pack(st_seq, 2, st_over))
                    end
                    if r.ImGui_Selectable(ctx2, "Long##st_seek_long", (st_seek == 3)) then
                        apply_mode(alg, st_pack(st_seq, 3, st_over))
                    end
                    SectionHeader(ctx2, "Overlap", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Default##st_ov_def", (st_over == 0)) then
                        apply_mode(alg, st_pack(st_seq, st_seek, 0))
                    end
                    if r.ImGui_Selectable(ctx2, "Low##st_ov_low", (st_over == 1)) then
                        apply_mode(alg, st_pack(st_seq, st_seek, 1))
                    end
                    if r.ImGui_Selectable(ctx2, "Medium##st_ov_med", (st_over == 2)) then
                        apply_mode(alg, st_pack(st_seq, st_seek, 2))
                    end
                    if r.ImGui_Selectable(ctx2, "High##st_ov_high", (st_over == 3)) then
                        apply_mode(alg, st_pack(st_seq, st_seek, 3))
                    end
                    r.ImGui_PopStyleColor(ctx2, 3)
                    return
                end
                if alg == 2 then
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderHovered(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderActive(), accent_color)
                    local sw_fft   =  bits_now        & 0x03
                    local sw_win   = (bits_now >> 2)  & 0x03
                    local sw_ov    = (bits_now >> 4)  & 0x03
                    local function sw_pack(ff, wn, ov)
                        return (ff & 0x03) | ((wn & 0x03) << 2) | ((ov & 0x03) << 4)
                    end
                    SectionHeader(ctx2, "Window size", false, accent_color)
                    if r.ImGui_Selectable(ctx2, "512##sw_fft_512", (sw_fft == 0)) then
                        apply_mode(alg, sw_pack(0, sw_win, sw_ov))
                    end
                    if r.ImGui_Selectable(ctx2, "1024##sw_fft_1024", (sw_fft == 1)) then
                        apply_mode(alg, sw_pack(1, sw_win, sw_ov))
                    end
                    if r.ImGui_Selectable(ctx2, "2048##sw_fft_2048", (sw_fft == 2)) then
                        apply_mode(alg, sw_pack(2, sw_win, sw_ov))
                    end
                    if r.ImGui_Selectable(ctx2, "4096##sw_fft_4096", (sw_fft == 3)) then
                        apply_mode(alg, sw_pack(3, sw_win, sw_ov))
                    end
                    SectionHeader(ctx2, "Window type", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "hanning##sw_win_hn", (sw_win == 0)) then
                        apply_mode(alg, sw_pack(sw_fft, 0, sw_ov))
                    end
                    if r.ImGui_Selectable(ctx2, "hamming##sw_win_hm", (sw_win == 1)) then
                        apply_mode(alg, sw_pack(sw_fft, 1, sw_ov))
                    end
                    if r.ImGui_Selectable(ctx2, "blackman##sw_win_bm", (sw_win == 2)) then
                        apply_mode(alg, sw_pack(sw_fft, 2, sw_ov))
                    end
                    if r.ImGui_Selectable(ctx2, "rectangular##sw_win_rc", (sw_win == 3)) then
                        apply_mode(alg, sw_pack(sw_fft, 3, sw_ov))
                    end
                    SectionHeader(ctx2, "Overlap", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "2x##sw_ov_2x", (sw_ov == 0)) then
                        apply_mode(alg, sw_pack(sw_fft, sw_win, 0))
                    end
                    if r.ImGui_Selectable(ctx2, "4x##sw_ov_4x", (sw_ov == 1)) then
                        apply_mode(alg, sw_pack(sw_fft, sw_win, 1))
                    end
                    if r.ImGui_Selectable(ctx2, "8x##sw_ov_8x", (sw_ov == 2)) then
                        apply_mode(alg, sw_pack(sw_fft, sw_win, 2))
                    end
                    if r.ImGui_Selectable(ctx2, "16x##sw_ov_16x", (sw_ov == 3)) then
                        apply_mode(alg, sw_pack(sw_fft, sw_win, 3))
                    end
                    r.ImGui_PopStyleColor(ctx2, 3)
                    return
                end
                if alg == 15 then
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_Header(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderHovered(), accent_color)
                    r.ImGui_PushStyleColor(ctx2, r.ImGui_Col_HeaderActive(), accent_color)
                    local rrr_eng   =  bits_now        & 0x03
                    local rrr_ws    = (bits_now >> 2)  & 0x03
                    local rrr_tr    = (bits_now >> 4)  & 0x01
                    local function rrr_pack(en, ws, tr)
                        return (en & 0x03) | ((ws & 0x03) << 2) | ((tr & 0x01) << 4)
                    end
                    SectionHeader(ctx2, "Engine", false, accent_color)
                    if r.ImGui_Selectable(ctx2, "Classic##rrr_eng_cl", (rrr_eng == 0)) then
                        apply_mode(alg, rrr_pack(0, rrr_ws, rrr_tr))
                    end
                    if r.ImGui_Selectable(ctx2, "Smooth##rrr_eng_sm", (rrr_eng == 1)) then
                        apply_mode(alg, rrr_pack(1, rrr_ws, rrr_tr))
                    end
                    if r.ImGui_Selectable(ctx2, "Experimental##rrr_eng_ex", (rrr_eng == 2)) then
                        apply_mode(alg, rrr_pack(2, rrr_ws, rrr_tr))
                    end
                    if r.ImGui_Selectable(ctx2, "Fast##rrr_eng_fs", (rrr_eng == 3)) then
                        apply_mode(alg, rrr_pack(3, rrr_ws, rrr_tr))
                    end
                    SectionHeader(ctx2, "Window size", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Short##rrr_ws_sh", (rrr_ws == 0)) then
                        apply_mode(alg, rrr_pack(rrr_eng, 0, rrr_tr))
                    end
                    if r.ImGui_Selectable(ctx2, "Medium##rrr_ws_md", (rrr_ws == 1)) then
                        apply_mode(alg, rrr_pack(rrr_eng, 1, rrr_tr))
                    end
                    if r.ImGui_Selectable(ctx2, "Long##rrr_ws_lg", (rrr_ws == 2)) then
                        apply_mode(alg, rrr_pack(rrr_eng, 2, rrr_tr))
                    end
                    if r.ImGui_Selectable(ctx2, "Very long##rrr_ws_vl", (rrr_ws == 3)) then
                        apply_mode(alg, rrr_pack(rrr_eng, 3, rrr_tr))
                    end
                    SectionHeader(ctx2, "Preserve transients", true, accent_color)
                    if r.ImGui_Selectable(ctx2, "Off##rrr_tr_off", (rrr_tr == 0)) then
                        apply_mode(alg, rrr_pack(rrr_eng, rrr_ws, 0))
                    end
                    if r.ImGui_Selectable(ctx2, "On##rrr_tr_on", (rrr_tr == 1)) then
                        apply_mode(alg, rrr_pack(rrr_eng, rrr_ws, 1))
                    end
                    r.ImGui_PopStyleColor(ctx2, 3)
                    return
                end
                SectionHeader(ctx2, "No settings", false, accent_color)
            end
            local bits_now = get_current_bits()
            local accent_color = Theme.get('green_accent')
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), accent_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), accent_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), accent_color)
            for i, alg in ipairs(mode_indices) do
                local name = mode_names[i]
                local selected = (props.mode == alg)
                if r.ImGui_Selectable(ctx, name, selected) then
                    if alg == -1 then
                        apply_mode(-1, 0)
                    elseif alg == 14 then
                        apply_mode(alg, 0x40)
                    else
                        apply_mode(alg, 0)
                    end
                    open_settings_alg = alg
                    bits_now = get_current_bits()
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                local toggle_label = (open_settings_alg == alg) and "Hide settings" or "Settings"
                if r.ImGui_SmallButton(ctx, toggle_label .. "##" .. tostring(alg)) then
                    if open_settings_alg == alg then
                        open_settings_alg = nil
                    else
                        open_settings_alg = alg
                    end
                end
                if open_settings_alg == alg then
                    r.ImGui_Spacing(ctx)
                    r.ImGui_Indent(ctx)
                    DrawSettings(ctx, alg, bits_now, accent_color)
                    r.ImGui_Unindent(ctx)
                end
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_Separator(ctx)
            if r.ImGui_Button(ctx, 'Close') then
                r.ImGui_CloseCurrentPopup(ctx)
                Utils.DeferClearCursorContext()
            end
            r.ImGui_EndPopup(ctx)
        end
    end
end

function TimestrechWidget.GetModeName(mode_value)
    return modes[mode_value] or "Unknown"
end

TimestrechWidget.mode_names = mode_names
TimestrechWidget.mode_indices = mode_indices
TimestrechWidget.mode_names_str = mode_names_str
TimestrechWidget.modes = modes

return TimestrechWidget
