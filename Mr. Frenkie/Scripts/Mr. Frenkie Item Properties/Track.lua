---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local Utils = require("Utils")

local Track = {}

function Track.GetSelectedTracks()
    local count = r.CountSelectedTracks(0)
    if count == 0 then
        return {}
    end
    local tracks = {}
    for i = 0, count - 1 do
        local track = r.GetSelectedTrack(0, i)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            tracks[#tracks + 1] = track
        end
    end
    return tracks
end

function Track.FreezeTracks(tracks)
    r.Main_OnCommand(41223, 0)
end

function Track.UnfreezeTracks(tracks)
    r.Main_OnCommand(41644, 0)
end

function Track.GetFreezeCountForTrack(track)
    if not track or not r.ValidatePtr(track, 'MediaTrack*') then return 0 end
    local val = r.GetMediaTrackInfo_Value(track, 'I_FREEZECOUNT') or 0
    return math.floor(val)
end

function Track.GetFreezeStats(tracks)
    local total = 0
    local track_count = 0
    local frozen_count = 0
    if tracks then
        for _, tr in ipairs(tracks) do
            local cnt = Track.GetFreezeCountForTrack(tr)
            total = total + cnt
            track_count = track_count + 1
            if cnt > 0 then frozen_count = frozen_count + 1 end
        end
    end
    local has = (frozen_count > 0)
    local all_frozen = (track_count > 0 and frozen_count == track_count)
    local none_frozen = (frozen_count == 0)
    local mixed = (frozen_count > 0 and frozen_count < track_count)
    return {
        total = total,
        has = has,
        track_count = track_count,
        frozen_count = frozen_count,
        all_frozen = all_frozen,
        none_frozen = none_frozen,
        mixed = mixed,
    }
end

function Track.GetTotalFXLatency(track)
    if not track or not r.ValidatePtr(track, 'MediaTrack*') then return nil end
    local total = 0
    local has_latency = (r.TrackFX_GetLatency ~= nil)
    local has_named = (r.TrackFX_GetNamedConfigParm ~= nil)
    local fx_count = r.TrackFX_GetCount(track) or 0
    for i = 0, fx_count - 1 do
        local enabled = r.TrackFX_GetEnabled(track, i)
        local offline = r.TrackFX_GetOffline(track, i)
        if enabled and not offline then
            local lat = 0
            if has_latency then
                lat = r.TrackFX_GetLatency(track, i) or 0
            elseif has_named then
                local ok, val = r.TrackFX_GetNamedConfigParm(track, i, 'pdc')
                if ok and val then
                    local tmp = tonumber(val)
                    if tmp ~= nil then lat = tmp end
                else
                    local ok2, val2 = r.TrackFX_GetNamedConfigParm(track, i, 'latency')
                    if ok2 and val2 then
                        local tmp2 = tonumber(val2)
                        if tmp2 ~= nil then lat = tmp2 end
                    end
                end
            end
            total = total + lat
        end
    end
    local rec_count = 0
    local ok = pcall(function() rec_count = r.TrackFX_GetRecCount(track) or 0 end)
    if ok and rec_count > 0 then
        for i = 0, rec_count - 1 do
            local idx = 0x1000000 + i
            local enabled = r.TrackFX_GetEnabled(track, idx)
            local offline = r.TrackFX_GetOffline(track, idx)
            if enabled and not offline then
                local lat = 0
                if has_latency then
                    lat = r.TrackFX_GetLatency(track, idx) or 0
                elseif has_named then
                    local ok3, val3 = r.TrackFX_GetNamedConfigParm(track, idx, 'pdc')
                    if ok3 and val3 then
                        local tmp3 = tonumber(val3)
                        if tmp3 ~= nil then lat = tmp3 end
                    else
                        local ok4, val4 = r.TrackFX_GetNamedConfigParm(track, idx, 'latency')
                        if ok4 and val4 then
                            local tmp4 = tonumber(val4)
                            if tmp4 ~= nil then lat = tmp4 end
                        end
                    end
                end
                total = total + lat
            end
        end
    end
    if total == 0 and not has_latency and not has_named then return nil end
    return total
end

function Track.GetPerfInfo(track)
    return {
        pdc_spl = Track.GetTotalFXLatency(track)
    }
end

local function ensure_mt_front(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    Utils.EnsureMIDITransposeUtilityInstalled()
    local just_added = false
    local fx_idx = nil
    local fx_cnt = r.TrackFX_GetCount(track) or 0
    for i = 0, fx_cnt - 1 do
        local ok, name = r.TrackFX_GetFXName(track, i, "")
        if ok and name and name:lower():find("midi transpose utility") then
            fx_idx = i
            break
        end
    end
    if fx_idx == nil then
        fx_idx = r.TrackFX_GetByName(track, "JS: Mr. Frenkie/MIDI Transpose Utility", false)
        if fx_idx == -1 then
            fx_idx = r.TrackFX_GetByName(track, "JS: MIDI Transpose Utility", false)
        end
        if fx_idx == -1 then
            fx_idx = r.TrackFX_AddByName(track, "JS: Mr. Frenkie/MIDI Transpose Utility", false, 1)
            if fx_idx == -1 then
                fx_idx = r.TrackFX_AddByName(track, "JS: MIDI Transpose Utility", false, 1)
            end
            if fx_idx == -1 then return nil end
            just_added = true
        end
    end
    if fx_idx ~= 0 then
        r.TrackFX_CopyToTrack(track, fx_idx, track, 0, true)
        fx_idx = 0
    end
    if just_added then
        Utils.ApplyMIDITransposePreset(track, fx_idx)
        Utils.EnableEmbeddedUIMCP(track, fx_idx)
    end
    pcall(r.TrackFX_SetOpen, track, fx_idx, false)
    return fx_idx
end

local function find_transpose_param(track, fx_idx)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    if fx_idx == nil or fx_idx < 0 then return nil end
    local param_count = r.TrackFX_GetNumParams(track, fx_idx) or 0
    for p = 0, param_count - 1 do
        local ok, name = r.TrackFX_GetParamName(track, fx_idx, p, "")
        if ok and name then
            local n = name:lower()
            if n:find("transpose") or n:find("semitone") or n:find("semitones") or n:find("shift") then
                return p
            end
        end
    end
    if param_count > 0 then return 0 end
    return nil
end

function Track.FindMidiTransposeFX(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    local fx_cnt = r.TrackFX_GetCount(track) or 0
    for i = 0, fx_cnt - 1 do
        local ok, name = r.TrackFX_GetFXName(track, i, "")
        if ok and name and name:lower():find("midi transpose utility") then
            return i
        end
    end
    -- Only our utility is considered
    return nil
end

function Track.GetMidiTransposeValue(track)
    local fx_idx = Track.FindMidiTransposeFX(track)
    if fx_idx == nil then return nil end
    local p_idx = find_transpose_param(track, fx_idx)
    if p_idx == nil then return nil end
    local val = r.TrackFX_GetParam(track, fx_idx, p_idx)
    return val
end


function Track.TransposeMidiFX(tracks, semitone_delta)
    if not tracks or #tracks == 0 then return end
    Utils.with_undo(semitone_delta > 0 and "Transpose MIDI +1 st" or "Transpose MIDI -1 st", function()
        for _, tr in ipairs(tracks) do
            if tr and r.ValidatePtr(tr, "MediaTrack*") then
                local fx_idx = ensure_mt_front(tr)
                if fx_idx ~= nil then
                    local p_idx = find_transpose_param(tr, fx_idx)
                    if p_idx ~= nil then
                        local val, minv, maxv = r.TrackFX_GetParam(tr, fx_idx, p_idx)
                        if val ~= nil and minv ~= nil and maxv ~= nil then
                            local new_val = val + semitone_delta
                            if new_val < minv then new_val = minv end
                            if new_val > maxv then new_val = maxv end
                            r.TrackFX_SetParam(tr, fx_idx, p_idx, new_val)
                            pcall(r.TrackFX_SetOpen, tr, fx_idx, false)
                        end
                    end
                end
            end
        end
    end)
end

function Track.SetMidiTransposeAbsolute(tracks, target)
    if not tracks or #tracks == 0 then return end
    Utils.with_undo("Set MIDI Transpose", function()
        for _, tr in ipairs(tracks) do
            if tr and r.ValidatePtr(tr, "MediaTrack*") then
                local fx_idx = ensure_mt_front(tr)
                if fx_idx ~= nil then
                    local p_idx = find_transpose_param(tr, fx_idx)
                    if p_idx ~= nil then
                        local _, minv, maxv = r.TrackFX_GetParam(tr, fx_idx, p_idx)
                        local new_val = target
                        if minv ~= nil and maxv ~= nil then
                            if new_val < minv then new_val = minv end
                            if new_val > maxv then new_val = maxv end
                        end
                        r.TrackFX_SetParam(tr, fx_idx, p_idx, new_val)
                        pcall(r.TrackFX_SetOpen, tr, fx_idx, false)
                    end
                end
            end
        end
    end)
end

function Track.UpdateMidiTransposeImmediate(tracks, target)
    if not tracks or #tracks == 0 then return end
    for _, tr in ipairs(tracks) do
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            local fx_idx = ensure_mt_front(tr)
            if fx_idx ~= nil then
                local p_idx = find_transpose_param(tr, fx_idx)
                if p_idx ~= nil then
                    local _, minv, maxv = r.TrackFX_GetParam(tr, fx_idx, p_idx)
                    local new_val = target
                    if minv ~= nil and maxv ~= nil then
                        if new_val < minv then new_val = minv end
                        if new_val > maxv then new_val = maxv end
                    end
                    r.TrackFX_SetParam(tr, fx_idx, p_idx, new_val)
                    pcall(r.TrackFX_SetOpen, tr, fx_idx, false)
                end
            end
        end
    end
end

function Track.FinalizeMidiTranspose()
    Utils.with_undo("Transpose MIDI", function() end)
end

function Track.ResetMidiTranspose(tracks)
    Track.RemoveMidiTransposeFX(tracks)
end

function Track.RemoveMidiTransposeFX(tracks)
    if not tracks or #tracks == 0 then return end
    Utils.with_undo("Remove MIDI Transpose", function()
        for _, tr in ipairs(tracks) do
            if tr and r.ValidatePtr(tr, "MediaTrack*") then
                local fx_idx = Track.FindMidiTransposeFX(tr)
                if fx_idx ~= nil then
                    pcall(r.TrackFX_Delete, tr, fx_idx)
                end
            end
        end
    end)
end

return Track
