local r = reaper

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
                if ok and val and tonumber(val) then
                    lat = tonumber(val)
                else
                    local ok2, val2 = r.TrackFX_GetNamedConfigParm(track, i, 'latency')
                    if ok2 and val2 and tonumber(val2) then
                        lat = tonumber(val2)
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
                    if ok3 and val3 and tonumber(val3) then
                        lat = tonumber(val3)
                    else
                        local ok4, val4 = r.TrackFX_GetNamedConfigParm(track, idx, 'latency')
                        if ok4 and val4 and tonumber(val4) then
                            lat = tonumber(val4)
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

return Track
