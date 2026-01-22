---@diagnostic disable: undefined-global, undefined-field
local r = reaper
local Utils = {}

local script_path = debug.getinfo(1, "S").source:match("@(.*)")
local script_dir = script_path:match("(.*[\\/])") or ""

local MIDI_TRANSPOSE_UTILITY_JSFX = [[// Created automatically by Frenkie Items Properties Widget
desc:MIDI Transpose Utility
//tags: MIDI processing utility
//author: Mr. Frenkie

slider1:0<-48,48,1>Transpose (Semitones)
options:no_meter

@init
gfx_ext_retina == 0 ? gfx_ext_retina = 1;
gfx_ext_flags |= 0x100 | 0x200;
gate_count = 0;
gate_vel_max = 0;

@block
while (midirecv(offset, msg1, msg2, msg3)) (
  status = msg1 & 0xF0;
  
  (status == 0x90 && msg3 > 0) ? (
    gate_count += 1;
    gate_note_vel[msg2] = msg3;
    (msg3 > gate_vel_max) ? gate_vel_max = msg3;
  ) : (status == 0x80 || (status == 0x90 && msg3 == 0)) ? (
    gate_count -= 1;
    gate_count < 0 ? gate_count = 0;
    gate_note_vel[msg2] = 0;
    i = 0;
    gate_vel_max = 0;
    while (i < 128) (
      v = gate_note_vel[i];
      (v > gate_vel_max) ? gate_vel_max = v;
      i += 1;
    );
  );
  
  (status == 0x80 || status == 0x90 || status == 0xA0) ? (
    new_note = msg2 + slider1;
    new_note < 0 ? new_note = 0;
    new_note > 127 ? new_note = 127;
    midisend(offset, msg1, new_note, msg3);
  ) : (
    midisend(offset, msg1, msg2, msg3);
  );
);

@gfx 150 40

gfx_clear = 0x1a1a1a;

str = #;
slider1 > 0 ? sprintf(str, "+%d st", slider1) : sprintf(str, "%d st", slider1);

gfx_setfont(1, "Arial", 24, 'b');
gfx_a = 1;

slider1 < 0 ? (
  gfx_r = 1.0; gfx_g = 0.55; gfx_b = 0.0; // Dark Orange
) : slider1 > 0 ? (
  gfx_r = 0.25; gfx_g = 0.88; gfx_b = 0.82; // Turquoise
) : (
  gfx_r = 1; gfx_g = 1; gfx_b = 1; // White for 0
);

str_w = 0; str_h = 0;
gfx_measurestr(str, str_w, str_h);

gfx_x = (gfx_w - str_w) / 2;
gfx_y = (gfx_h - str_h) / 2;

sq_w = 16; sq_h = 16;
sq_x = gfx_x - 12 - sq_w;
sq_y = gfx_y + (str_h - sq_h) / 2;
text_r = gfx_r; text_g = gfx_g; text_b = gfx_b; text_a = gfx_a;
(gate_count > 0) ? (
  t = gate_vel_max / 127;
  t < 0 ? t = 0;
  t > 1 ? t = 1;
  gfx_a = 0.2 + 0.8 * t;
  gfx_r = 1; gfx_g = 1; gfx_b = 0;
  gfx_rect(sq_x, sq_y, sq_w, sq_h);
);
gfx_r = text_r; gfx_g = text_g; gfx_b = text_b; gfx_a = text_a;

gfx_drawstr(str)]]

function Utils.vol_to_db(vol)
    return vol <= 0 and -math.huge or 20 * math.log(vol, 10)
end

function Utils.db_to_vol(db)
    return 10^(db/20)
end

function Utils.with_undo(description, func)
    r.Undo_BeginBlock()
    func()
    r.Undo_EndBlock(description, -1)
end

function Utils.shallow_equal(t1, t2)
    if #t1 ~= #t2 then return false end
    for k, v in pairs(t1) do
        if v ~= t2[k] then return false end
    end
    return true
end

function Utils.DeferClearCursorContext()
    r.defer(function() r.SetCursorContext(0, nil) end)
end

function Utils.ClearCursorContextOnDeactivation(ctx)
    local deactivated = r.ImGui_IsItemDeactivated(ctx)
    if deactivated then
        local hovered = r.ImGui_IsWindowHovered(ctx)
        if not hovered then
            Utils.DeferClearCursorContext()
        end
    end
    return deactivated
end

local MIDI_TRANSPOSE_UTILITY_PRESET_INI = [[[General]
NbPresets=1

[Preset0]
Data=30202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D202D20225472616E73706F757365205574696C69747920666F72204974656D2050726F706572746965732232
Len=168
Name=Transpouse Utility for Item Properties
]]

function Utils.GetScriptDir()
    return script_dir
end

function Utils.EnsureMIDITransposeUtilityInstalled()
    local res_path = r.GetResourcePath()
    if not res_path or res_path == "" then return end
    local sep = package.config:sub(1, 1)
    local effects_dir = res_path .. sep .. "Effects" .. sep .. "Mr. Frenkie"
    pcall(function() r.RecursiveCreateDirectory(effects_dir, 0) end)
    local dest = effects_dir .. sep .. "MIDI Transpose Utility.jsfx"
    local need_write = true
    local d0 = io.open(dest, "rb")
    if d0 then
        local old = d0:read("*a")
        d0:close()
        if old == MIDI_TRANSPOSE_UTILITY_JSFX then need_write = false end
    end
    if need_write then
        local d = io.open(dest, "wb")
        if d then
            d:write(MIDI_TRANSPOSE_UTILITY_JSFX)
            d:close()
        end
    end
    pcall(function() r.EnumInstalledFX(-1) end)
    return "JS: MIDI Transpose Utility"
end

function Utils.WritePresetForFX(track, fx_idx)
    if not track or fx_idx == nil or fx_idx < 0 then return nil end
    local ok, preset_path = pcall(function() return r.TrackFX_GetUserPresetFilename(track, fx_idx, "") end)
    if not ok or not preset_path or preset_path == "" then return nil end
    local need_write = true
    local d0 = io.open(preset_path, "rb")
    if d0 then
        local old = d0:read("*a")
        d0:close()
        if old == MIDI_TRANSPOSE_UTILITY_PRESET_INI then need_write = false end
    end
    if need_write then
        local d = io.open(preset_path, "wb")
        if d then
            d:write(MIDI_TRANSPOSE_UTILITY_PRESET_INI)
            d:close()
        end
    end
    return preset_path, need_write
end

function Utils.ApplyMIDITransposePreset(track, fx_idx)
    if not track or fx_idx == nil or fx_idx < 0 then return end
    local _, wrote = Utils.WritePresetForFX(track, fx_idx)
    if wrote then
        pcall(function() r.EnumInstalledFX(-1) end)
    end
    r.TrackFX_SetPreset(track, fx_idx, "Transpouse Utility for Item Properties")
end

function Utils.EnableEmbeddedUIMCP(track, fx_idx)
    if not track or fx_idx == nil or fx_idx < 0 then return end
    local ok, chunk = r.GetTrackStateChunk(track, "", false)
    if not ok or not chunk or chunk == "" then return end
    local lines = {}
    for line in chunk:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end
    local fx_count = r.TrackFX_GetCount(track) or 0
    local fx_wak_indices = {}
    local collect = false
    local brackets = 0
    local idx = 0
    for i = 1, #lines do
        local ln = lines[i]
        if ln:match("<FXCHAIN") then collect = true end
        if collect then
            local openb = select(2, ln:gsub("<", ""))
            local closeb = select(2, ln:gsub(">", ""))
            brackets = brackets + openb - closeb
            if ln:match("^WAK%s") then
                idx = idx + 1
                fx_wak_indices[idx] = i
            end
            if brackets == 0 then break end
        end
    end
    local wak_line_idx = fx_wak_indices[fx_idx + 1]
    if wak_line_idx then
        local src = lines[wak_line_idx]
        local f1, f2 = src:match("WAK%s+([%d%-]+)%s+([%d%-]+)")
        f1 = tonumber(f1) or 0
        f2 = 2
        lines[wak_line_idx] = ("WAK %d %d"):format(f1, f2)
        local newchunk = table.concat(lines, "\n")
        r.SetTrackStateChunk(track, newchunk, false)
    end
end

return Utils
