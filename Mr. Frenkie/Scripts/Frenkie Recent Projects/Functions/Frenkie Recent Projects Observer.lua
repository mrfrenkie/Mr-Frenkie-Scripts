---@diagnostic disable: undefined-global -- reaper is provided by REAPER at runtime

local SECTION = "FrenkieRecentProjectsHistory"
local KEY_REV = "rev_v1"
local KEY_HB = "hb_v1"
local KEY_OBSERVER_CMD = "observer_cmd_id_v1"
local KEY_OBSERVER_SECTION = "observer_section_id_v1"
local KEY_OBSERVER_RUNNING = "observer_running_v1"
local KEY_OPEN_LIST = "open_list_v1"
local KEY_OPEN_REV = "open_rev_v1"

local MAX_ITEMS = 1000
local POLL_INTERVAL_SEC = 0.5

local HISTORY_FILENAME = "My Resent Projects List.txt"
local LEGACY_HISTORY_FILENAME = "Frenkie Recent Projects History.txt"

local history_file_path = nil

local function get_history_file_path()
  if history_file_path then
    return history_file_path
  end
  local src = debug.getinfo(1, "S")
  local script_path = src and src.source and src.source:match("@(.+)") or ""
  local dir = script_path:match("(.+)[/\\][^/\\]+$") or ""
  local parent_dir = dir:match("(.+)[/\\][^/\\]+$") or dir
  if parent_dir ~= "" then
    local new_path = parent_dir .. "/" .. HISTORY_FILENAME
    local legacy_path = parent_dir .. "/" .. LEGACY_HISTORY_FILENAME
    local has_file_exists = reaper and reaper.file_exists
    if has_file_exists and reaper.file_exists(new_path) then
      history_file_path = new_path
    elseif has_file_exists and reaper.file_exists(legacy_path) then
      local ok = os.rename(legacy_path, new_path)
      if ok then
        history_file_path = new_path
      else
        history_file_path = legacy_path
      end
    else
      history_file_path = new_path
    end
  else
    local new_path = HISTORY_FILENAME
    local legacy_path = LEGACY_HISTORY_FILENAME
    local has_file_exists = reaper and reaper.file_exists
    if has_file_exists and reaper.file_exists(new_path) then
      history_file_path = new_path
    elseif has_file_exists and reaper.file_exists(legacy_path) then
      local ok = os.rename(legacy_path, new_path)
      if ok then
        history_file_path = new_path
      else
        history_file_path = legacy_path
      end
    else
      history_file_path = new_path
    end
  end
  return history_file_path
end

local function setToggleState(sectionID, cmdID, state)
  if not sectionID or not cmdID then return end
  if reaper.SetToggleCommandState and reaper.RefreshToolbar2 then
    reaper.SetToggleCommandState(sectionID, cmdID, state or 0)
    reaper.RefreshToolbar2(sectionID, cmdID)
  end
end

local function norm_path(p)
  return tostring(p or ""):gsub("\\", "/"):lower()
end

local function base_name(p)
  local s = tostring(p or "")
  local n = s:match("([^/\\]+)%.rpp$") or s:match("([^/\\]+)$") or s
  return n
end

local function esc(s)
  s = tostring(s or "")
  s = s:gsub("%%", "%%25")
  s = s:gsub("\r", "%%0D")
  s = s:gsub("\n", "%%0A")
  s = s:gsub("\t", "%%09")
  return s
end

local function unesc(s)
  s = tostring(s or "")
  s = s:gsub("%%0D", "\r")
  s = s:gsub("%%0A", "\n")
  s = s:gsub("%%09", "\t")
  s = s:gsub("%%25", "%%")
  return s
end

local function looks_like_project_path(p)
  local s = tostring(p or "")
  if s == "" then return false end
  local low = s:lower()
  if low:match("%.rpp$") then return true end
  if low:match("%.rpp%-bak$") then return true end
  return s:match("[/\\]") ~= nil and low:find(".rpp", 1, true) ~= nil
end
local function parse_history_raw(raw)
  local out = {}
  raw = tostring(raw or "")
  if raw == "" then return out end

  for line in (raw .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      local ts_s, cnt_s, name_s, path_s = line:match("^(%d+)\t(%d+)\t(.-)\t(.*)$")
      local path = nil
      local name = nil
      local last_opened = 0
      local open_count = 0

      if ts_s and cnt_s and path_s then
        path = unesc(path_s)
        name = unesc(name_s or "")
        last_opened = tonumber(ts_s) or 0
        open_count = tonumber(cnt_s) or 0
      else
        local ts3_s, name3_s, path3_s = line:match("^(%d+)\t(.-)\t(.*)$")
        if ts3_s and path3_s then
          path = unesc(path3_s)
          name = unesc(name3_s or "")
          last_opened = tonumber(ts3_s) or 0
          open_count = 0
        else
          local ts2_s, path2_s = line:match("^(%d+)\t(.*)$")
          if ts2_s and path2_s then
            path = unesc(path2_s)
            name = ""
            last_opened = tonumber(ts2_s) or 0
            open_count = 0
          else
            path = unesc(line)
            name = ""
            last_opened = 0
            open_count = 0
          end
        end
      end

      path = tostring(path or "")
      if looks_like_project_path(path) then
        name = tostring(name or "")
        if name == "" then
          name = base_name(path)
        end
        out[#out + 1] = {
          path = path,
          norm = norm_path(path),
          name = name,
          last_opened = last_opened,
          open_count = open_count
        }
      end
    end
  end
  return out
end

local write_history_file

local function read_history_file()
  local path = get_history_file_path()
  local f = io.open(path, "r")
  if not f then
    write_history_file({})
    return {}
  end
  local raw = f:read("*a") or ""
  f:close()
  return parse_history_raw(raw)
end

function write_history_file(history)
  local path = get_history_file_path()
  local tmp_path = path .. ".tmp"
  local f = io.open(tmp_path, "w")
  if not f then
    return false
  end
  for i = 1, math.min(#history, MAX_ITEMS) do
    local it = history[i]
    f:write(string.format(
      "%d\t%d\t%s\t%s\n",
      tonumber(it.last_opened) or 0,
      tonumber(it.open_count) or 0,
      esc(it.name or ""),
      esc(it.path or "")
    ))
  end
  f:close()
  local ok, err = os.rename(tmp_path, path)
  if not ok then
    os.remove(tmp_path)
    return false
  end
  return true
end

local function load_history()
  local items = read_history_file()
  return items
end

local function save_history(history)
  write_history_file(history)
  reaper.SetExtState(SECTION, KEY_REV, tostring(math.floor(reaper.time_precise() * 1000)), true)
end

local function find_index(history, norm)
  for i = 1, #history do
    if history[i] and history[i].norm == norm then
      return i
    end
  end
  return nil
end

local history = load_history()
reaper.SetExtState(SECTION, KEY_REV, tostring(math.floor(reaper.time_precise() * 1000)), true)

local seen_open = {}
do
  for i = 1, #history do
    local it = history[i]
    if it and it.norm and it.norm ~= "" then
      seen_open[it.norm] = true
    end
  end
end

local last_current_norm = ""
local next_poll_t = 0.0
local last_open_sig = ""

local function build_open_signature()
  if not reaper.EnumProjects then
    return ""
  end
  local paths = {}
  local i = 0
  while true do
    local proj, p = reaper.EnumProjects(i, "")
    if not proj then break end
    p = tostring(p or "")
    local n = norm_path(p)
    if n ~= "" then
      paths[#paths + 1] = n
    end
    i = i + 1
    if i >= 256 then break end
  end
  table.sort(paths)
  return table.concat(paths, "\n")
end

local function record_open(path, now)
  path = tostring(path or "")
  if path == "" then return false end

  local norm = norm_path(path)
  if norm == "" then return false end

  local idx = find_index(history, norm)
  if idx then
    local it = history[idx]
    it.last_opened = now
    it.open_count = (tonumber(it.open_count) or 0) + 1
    it.name = it.name ~= "" and it.name or base_name(path)
    if idx ~= 1 then
      table.remove(history, idx)
      table.insert(history, 1, it)
    end
  else
    table.insert(history, 1, {
      path = path,
      norm = norm,
      name = base_name(path),
      last_opened = now,
      open_count = 1
    })
    if #history > MAX_ITEMS then
      history[MAX_ITEMS + 1] = nil
    end
  end
  return true
end

local function poll_once()
  local now = reaper.time_precise()
  local now_epoch = math.floor(now)

  local changed = false

  if reaper.EnumProjects then
    local _, cur_path = reaper.EnumProjects(-1, "")
    cur_path = tostring(cur_path or "")
    local cur_norm = norm_path(cur_path)
    if cur_norm ~= "" and cur_norm ~= last_current_norm then
      last_current_norm = cur_norm
      changed = record_open(cur_path, now_epoch) or changed
    end

    local i = 0
    while true do
      local proj, p = reaper.EnumProjects(i, "")
      if not proj then break end
      p = tostring(p or "")
      local n = norm_path(p)
      if n ~= "" and not seen_open[n] then
        seen_open[n] = true
        changed = record_open(p, now_epoch) or changed
      end
      i = i + 1
      if i >= 256 then break end
    end
  end

  if reaper.SetExtState then
    local sig = build_open_signature()
    if sig ~= last_open_sig then
      last_open_sig = sig
      reaper.SetExtState(SECTION, KEY_OPEN_LIST, sig, true)
      reaper.SetExtState(SECTION, KEY_OPEN_REV, tostring(math.floor(now * 1000)), true)
    end
  end

  if changed then
    save_history(history)
  end
end

local Observer = {}
Observer.SECTION = SECTION
Observer.KEY_LIST = KEY_LIST
Observer.KEY_REV = KEY_REV
Observer.KEY_HB = KEY_HB

function Observer.update()
  local now = reaper.time_precise()
  reaper.SetExtState(SECTION, KEY_HB, tostring(math.floor(now * 1000)), true)
  if now >= next_poll_t then
    next_poll_t = now + POLL_INTERVAL_SEC
    poll_once()
  end
end

local embedded = rawget(_G, "FrenkieRecentProjects_EmbedObserver") == true
if embedded then
  return Observer
end

local _, _, sectionID, cmdID = reaper.get_action_context()
sectionID = tonumber(sectionID)
cmdID = tonumber(cmdID)

if reaper.SetExtState then
  reaper.SetExtState(SECTION, KEY_OBSERVER_SECTION, tostring(sectionID or ""), true)
  reaper.SetExtState(SECTION, KEY_OBSERVER_CMD, tostring(cmdID or ""), true)
  reaper.SetExtState(SECTION, KEY_OBSERVER_RUNNING, "1", true)
end

setToggleState(sectionID, cmdID, 1)
reaper.atexit(function()
  setToggleState(sectionID, cmdID, 0)
  if reaper.SetExtState then
    reaper.SetExtState(SECTION, KEY_OBSERVER_RUNNING, "0", true)
  end
end)

local function standalone_loop()
  Observer.update()
  reaper.defer(standalone_loop)
end

standalone_loop()
