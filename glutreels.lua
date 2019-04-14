-- glut
--
-- granular sampler in progress
-- (currently requires a grid)
--
-- trigger voices
-- using grid rows 2-8
--
-- mute voices and record
-- patterns using grid row 1
--

engine.name = 'Glut'
local g = grid.connect()

local VOICES = 7

local positions = {}
local gates = {}
local voice_levels = {}

for i=1, VOICES do
  positions[i] = -1
  gates[i] = 0
  voice_levels[i] = 0
end

local gridbuf = require 'lib/gridbuf'
local grid_ctl = gridbuf.new(16, 8)
local grid_voc = gridbuf.new(16, 8)

local metro_grid_refresh
local metro_blink

--[[
recorder
]]

local pattern_banks = {}
local pattern_timers = {}
local pattern_leds = {} -- for displaying button presses
local pattern_positions = {} -- playback positions
local record_bank = -1
local record_prevtime = -1
local record_length = -1
local alt = false
local blink = 0
local metro_blink

---- reeels 

local sc = require "softcut"
local UI = require "ui"
local tab = require 'tabutil'
local fileselect = require "fileselect"
local textentry = require "textentry"

local playing = false
local recording = false
local filesel = false
local settings = false
local mounted = false
local warble_state = false
local tape_tension = 30
local plhead_lvl = 35 -- playhead height
local plhead_slvl = 0 -- playhead brightness
local speed = 0 -- default speed
local reel_pos_x = 28  -- default
local reel_pos_y = 21 -- default
local c_pos_x = 20
local c_pos_y = 58
local bind_vals = {20,48,80,108,0,0,0,0,0,0}
local clip_len_s = 60
local rec_vol = 1
local fade = 0.01
local TR = 4 -- temp
local SLEW_AMOUNT = 0.03
local WARBLE_AMOUNT = 10
local trk = 1
local blink_r = false
local r_reel = {{},{},{},{},{},{}}
local l_reel = {{},{},{},{},{},{}}
local speed_disp = {">",">>",">>>",">>>>","<","<<","<<<","<<<<"}
local reel = {}
local rec_time = 0
local rec_start
local play_time = {0,0,0,0}
local mutes = {true,true,true,true}


local function update_rate(i)
  local n = math.pow(2,reel.speed)
  reel.speed = math.abs(speed)
  if reel.rev == 1 then n = -n end
  sc.rate(i, n / reel.q[i])
end

local function warble(state)
  local n = {}
  if state == true then
    for i=1,TR do
      n[i] = (math.pow(2,reel.speed) / reel.q[i])
      sc.rate(i, n[i] + l_reel[i].position / WARBLE_AMOUNT)
      update_rate(i)
    end
  end
end

local function play_count()
  for i=1,TR do
    if reel.rev == 0 then
      play_time[i] = play_time[i] + (0.01 / (reel.q[i] - math.abs(speed / 2 )))
      if play_time[i] >= reel.loop_end[i] then
        play_time[i] = reel.loop_start[i]
      end
    elseif reel.rev == 1 then
      play_time[i] = play_time[i] - (0.01 / (reel.q[i] - math.abs(speed / 2)))
      if play_time[i] <= reel.loop_start[i] == 1 then -- fix wtf(?)
        play_time[i] = reel.loop_end[i]
      end
    end
  end
  if recording then
    rec_time = play_time[trk]
  end
  warble(warble_state)
end

local function update_params_list()
  settings_list.entries = {"Tr " .. trk .. (mutes[trk] == false and "  Vol " or " "), "Start", "End", "Quality","--","-", "--", "Load clip", "Save clip",  "--", "Clear clip", not mounted and "New reel" or "Clear all", "--", "Save reel", "Load reel", "Warble"}
  settings_amounts_list.entries = {mutes[trk] == false and util.round(reel.vol[trk]*100) or (reel.clip[trk] == 0 and "Load" or "muted") or "" .. util.round(reel.vol[trk]*100),util.round(reel.loop_start[trk],0.1),util.round(reel.loop_end[trk],0.1),reel.q[trk] ,"","-","","","","","","","","","", warble_state == true and "On" or "Off"}
end
-- REEL
local function set_loop(tr, st, en)
  st = reel.s[tr] + st
  en = reel.s[tr] + en
  sc.loop_start(tr,st)
  sc.loop_end(tr,en)
  if play_time[tr] > en or play_time[tr] < st then
    sc.position(tr,st)
    play_time[trk] = reel.loop_start[trk]
  end
end

local function rec(tr, state)
  if state == true then -- start rec
    --if rec_time ~= 0 then
      --rec_time = 0
    --end
    recording = true
    if not reel.name[tr]:find("*") then
      rec_start = play_time[tr]
      reel.name[tr] = "*" .. reel.name[tr]
      -- sync pos with graphics on initial recording
      sc.position(tr, reel.s[tr] + rec_start)
    end
    reel.rec[tr] = 1
    sc.rec(tr,1)
  elseif state == false then -- stop rec
    recording = false
    reel.rec[tr] = 0
    sc.rec_level(tr,0)
    if reel.clip[tr] == 0 then
      if reel.rev == 0 then
        reel.loop_start[tr] = rec_start - 0.1
        reel.loop_end[tr] = rec_time 
        set_loop(tr, reel.loop_start[tr], reel.loop_end[tr])
      elseif reel.rev == 1 then
        reel.loop_start[tr] = rec_time
        reel.loop_end[tr] = rec_start - 0.1 
        set_loop(tr, reel.loop_start[tr], reel.loop_end[tr])
      end
    end
    reel.clip[tr] = 1
    update_params_list()
  end
end

local function mute(tr,state)
  if state == true then
    sc.level(tr,0)
    mutes[tr] = true
  elseif state == false then
    mutes[tr] = false
    sc.level(tr,reel.vol[tr])
  end
end

local function play(state)
  if state == true then
    playing = true
    play_counter:start()
    for i=1,TR do
      sc.play(i,1)
      reel.play[i] = 1
    end
  elseif state == false then
    playing = false
    play_counter:stop()
    for i=1,TR do
    if reel.rec[i] == 1 then rec(i,false) end
      sc.play(i,0)
      reel.play[i] = 0
    end
  end
end

local function clear_track(tr)
  reel.clip[tr] = 1
  if reel.name[tr]:find("*") then
    reel.name[tr] = string.gsub(reel.name[tr], "*", "")
  end
  play_time[tr] = 0
  reel.q[tr] = 1
  reel.play[tr] = 0
  reel.loop_end[tr] = 60
  reel.length[tr] = 60
  reel.clip[tr] = 0
  set_loop(tr,reel.s[tr],reel.loop_end[tr])
  sc.buffer_clear_region(reel.s[tr], reel.length[tr])
  sc.position(tr,reel.s[tr])
  print("Clear buffer region " .. reel.s[tr], reel.length[tr])
end
-- PERSISTENCE
local function init_folders()
  if util.file_exists(_path.data .. "reels/") == false then
    util.make_dir(_path.data .. "reels/")
  end
  if util.file_exists(_path.audio .. "reels/") == false then
    util.make_dir(_path.audio .. "reels/")
  end
end

local function new_reel()
  sc.buffer_clear()
  reel.name = {"-","-","-","-"}
  settings_list.index = 1
  settings_amounts_list.index = 1
  rec_time = 0
  playing = false
  for i=1,TR do
    play_time[i] = 0
    table.insert(reel.q,1)
    table.insert(reel.play,0)
    reel.loop_end = {60, 60, 60, 60}
    table.insert(reel.loop_end,16)
    table.insert(reel.length,60)
    table.insert(reel.clip,0)
    set_loop(i,0,reel.loop_end[i])
    sc.position(i,reel.s[i])
  end
  mounted = true
  update_params_list()
end

local function load_clip(path)
  if path ~= "cancel" then
    if path:find(".aif") or path:find(".wav") then
      local ch, len = sound_file_inspect(path)
      reel.paths[trk] = path
      reel.clip[trk] = 1
      reel.name[trk] = path:match("[^/]*$")
      if len/48000 <= 60 then 
	      reel.length[trk] = len/48000
      else
	      reel.length[trk] = 59.9
      end
      reel.e[trk] = reel.s[trk] + reel.length[trk]
      if not path:find(reel.proj) then reel.loop_end[trk] = reel.length[trk] end
      print("read to " .. reel.s[trk], reel.e[trk])
      sc.buffer_read_mono(path, 0, reel.s[trk], reel.length[trk], 1, 1)
      if not playing then sc.play(trk,0) end
      play_time[trk] = 0
      sc.position(trk,reel.s[trk])
      sc.level(trk, reel.vol[trk])
      mute(trk,false)
      mounted = true
      update_rate(trk)
      update_params_list()
      -- default loop on
      set_loop(trk,0,reel.loop_end[trk])
    else
      print("not a sound file")
    end
  end
  settings = true
  filesel = false
end

local function load_reel_data(pth)
  saved = tab.load(pth)
  if saved ~= nil then
    print("reel data found")
    reel = saved
  else
    print("no reel data")
  end
end

local function load_mix(path)
  if path ~= "cancel" then
    if path:find(".reel") then
      load_reel_data(path)
      trk = 1
      for i=1,TR do
        if reel.name[i] ~= "-" then
          --print("reading file > " ..reel.paths[i])
          load_clip(reel.paths[i])
          trk = util.clamp(trk + 1,1,TR)
          mounted = true
          play_time[i] = reel.loop_start[i]
          sc.position(i,reel.s[i] + reel.loop_start[i])
          update_rate(i)
          sc.play(i,0)
        end
      end
    else
      print("not a reel file")
    end
  end
  trk = 1
  settings = true
  filesel = false
  update_params_list()
end

local function save_clip(txt)
  if txt then
    local c_start = reel.s[trk]
    local c_len = reel.e[trk]
    print("SAVE " .. _path.audio .. "reels/".. txt .. ".aif", c_start, c_len)
    sc.buffer_write_mono(_path.audio .. "reels/"..txt..".aif",c_start,c_len, 1)
    reel.name[trk] = txt
  else
    print("save cancel")
  end
  filesel = false
end

local function save_project(txt)
  if txt then
    reel.proj = txt
    for i=1,TR do
      if reel.name[i] ~= "-" then
        if reel.name[i]:find("*") then
          local name = reel.name[i] == "*-" and (txt .. "-rec-" .. i .. ".aif") or reel.name[i]:sub(2,-1) -- remove asterisk
          local save_path = _path.audio .."reels/" .. name
          reel.paths[i] = save_path
          print("saving "..i .. "clip at " .. save_path, reel.s[i],reel.e[i])
          sc.buffer_write_mono(_path.audio .."reels/" .. name, reel.s[i],reel.e[i], 1)
        end
      end
    end
    tab.save(reel, _path.data.."reels/".. txt ..".reel")
  else
    print("save cancel")
  end
  filesel = false
end
-- UI
local function update_reel()
  for i=1,6 do
    l_reel[i].velocity = util.linlin(0, 1, 0.01, (speed/1.9)/(reel.q[1]/2), 0.15)
    l_reel[i].position = (l_reel[i].position - l_reel[i].velocity) % (math.pi * 2)
    l_reel[i].x = 30 + l_reel[i].orbit * math.cos(l_reel[i].position)
    l_reel[i].y = 25 + l_reel[i].orbit * math.sin(l_reel[i].position)
    r_reel[i].velocity = util.linlin(0, 1, 0.01, (speed/1.5)/(reel.q[1]/2), 0.15)
    r_reel[i].position = (r_reel[i].position - r_reel[i].velocity) % (math.pi * 2)
    r_reel[i].x = 95 + r_reel[i].orbit * math.cos(r_reel[i].position)
    r_reel[i].y = 25 + r_reel[i].orbit * math.sin(r_reel[i].position)
  end
end

local function animation()
  if playing == true then
    update_reel()
    if plhead_lvl > 31 then
      plhead_lvl = plhead_lvl - 1
    elseif plhead_lvl < 32 and plhead_lvl > 25 then
      plhead_lvl = plhead_lvl - 1
    end
    if tape_tension > 20 and plhead_lvl < 32  then
      tape_tension = tape_tension - 1
      plhead_slvl = util.clamp(plhead_slvl + 1,0,2)
    end
  elseif playing == false then
    if plhead_lvl < 35 then
      plhead_lvl = plhead_lvl + 1
    elseif plhead_lvl > 25 then
      end
    if tape_tension < 30 then
      tape_tension = tape_tension + 1
      plhead_slvl = util.clamp(plhead_slvl - 1,0,5)
    end
  end
  if settings == true and reel_pos_x > -20 then
    reel_pos_x = reel_pos_x - 5
  elseif settings == false and reel_pos_x <= 30 then
    reel_pos_x = reel_pos_x + 5
  end
  -- cursor position
  if c_pos_x ~= bind_vals[trk] then
    if c_pos_x <= bind_vals[trk] then
      c_pos_x = util.clamp(c_pos_x + 3,bind_vals[trk]-20,bind_vals[trk])
    elseif c_pos_x >= bind_vals[trk] then
      c_pos_x = util.clamp(c_pos_x - 3,bind_vals[trk],bind_vals[trk]+20)
    end
  end
end

local function draw_reel(x,y)
  local l = util.round(speed * 10)
  if l < 0 then
    l = math.abs(l) + 4
  elseif l >= 4 then
    l = 4
  elseif l == 0 then
    l = reel.rev == 1 and 5 or 1
  end
  screen.level(1)
  screen.line_width(1.9)
  local pos = {1,3,5}
  for i = 1, 3 do
    screen.move((x + r_reel[pos[i]].x) - 30, (y + r_reel[pos[i]].y) - 25)--, 0.5)
    screen.line((x + r_reel[pos[i]+1].x) - 30, (y + r_reel[pos[i]+1].y) - 25)
    screen.stroke()
    screen.move((x + l_reel[pos[i]].x) - 30, (y + l_reel[pos[i]].y) - 25)--, 0.5)
    screen.line((x + l_reel[pos[i]+1].x) - 30, (y + l_reel[pos[i]+1].y) - 25)
    screen.stroke()
  end
  screen.line_width(1)
  -- speed icons >>>>
  screen.move(x + 32, y + 2)-- - 19)
  screen.level(speed == 0 and 1 or 6)
  screen.text_center(speed_disp[util.clamp(l,1,8)])
  screen.stroke()
  --
  screen.level(1)
  screen.circle(x+5,y+28,2)
  screen.fill()
  screen.circle(x+55,y+28,2)
  screen.fill()
  screen.level(0)
  screen.circle(x+5,y+28,1)
  screen.circle(x+55,y+28,1)
  screen.fill()
  --right reel
  screen.level(1)
  screen.circle(x+65,y,1)
  screen.stroke()
  screen.circle(x+65,y,20)
  screen.stroke()
  screen.circle(x+65,y,3)
  screen.stroke()
  -- left
  screen.circle(x,y,20)
  screen.stroke()
  screen.circle(x,y,1)
  screen.stroke()
  screen.circle(x,y,3)
  screen.stroke()
  -- tape
  if mounted then
    screen.level(6)
    screen.move(x,y-17)
    screen.line(x+65,y-12)
    screen.stroke()
    screen.level(6)
    screen.circle(x,y,18)
    screen.stroke()
    screen.level(3)
    screen.circle(x,y,17)
    screen.stroke()
    screen.level(6)
    screen.circle(x+65,y,14)
    screen.stroke()
    screen.level(3)
    screen.circle(x+65,y,13)
    screen.stroke()
    screen.level(6)
    screen.move(x+75,y+10)
    screen.line(x+55,y+30)
    screen.stroke()
    screen.move(x-9,y+16)
    screen.line(x+5,y+30)
    screen.stroke()
    screen.move(x+5,y+30)
    screen.curve(x+40,y+tape_tension,x+25,y+tape_tension,x+56,y+30)
    screen.stroke()
  end
  -- playhead
  screen.level(plhead_slvl)
  screen.circle(x + 32,y + plhead_lvl + 1,3)
  screen.rect(x + 28,y + plhead_lvl,8,4)
  screen.fill()
end

local function draw_bars(x,y)
  for i=1,TR do
    screen.level(mutes[i] and 1 or reel.rec[i] == 1 and 9 or 3)
    screen.rect((x * i *2) - 24,y,26,3)
    screen.stroke()
    screen.level(mutes[i] and 1 or reel.rec[i] == 1 and 9 or 3)
    screen.rect((x * i *2) - 24,y,25,3)
    screen.fill()
    screen.stroke()
    screen.level(0)
    -- display loop start / end points
    screen.rect(((x * i *2) - 24) + (reel.loop_start[i] / reel.length[i] * 25), 61, (reel.loop_end[i] / reel.length[i] * 25) - (reel.loop_start[i] / reel.length[i] * 25), 2)
    screen.fill()
    screen.level(15)
    screen.move(((x * i *2) - 24) + (((play_time[i]) / (reel.length[i]) * 25)), 61)
    screen.line_rel(0,2)
    screen.stroke()
  end
end

local function draw_cursor(x,y)
  screen.level(9)
  screen.move(x-3,y-3)
  screen.line(x,y)
  screen.line_rel(3,-3)
  screen.stroke()
end

local function draw_rec_vol_slider(x,y)
  screen.level(1)
  screen.move(x - 30, y - 17)
  screen.line(x - 30, y + 29)
  screen.stroke()
  screen.level(6)
  screen.rect(x - 33, 48 - rec_vol / 3 * 132, 5, 2)
  screen.fill()
end




local function record_event(x, y, z)
  if record_bank > 0 then
    -- record first event tick
    local current_time = util.time()

    if record_prevtime < 0 then
      record_prevtime = current_time
    end

    local time_delta = current_time - record_prevtime
    table.insert(pattern_banks[record_bank], {time_delta, x, y, z})
    record_prevtime = current_time
  end
end

local function start_playback(n)
  pattern_timers[n]:start(0.001, 1) -- TODO: timer doesn't start immediately with zero
end

local function stop_playback(n)
  pattern_timers[n]:stop()
  pattern_positions[n] = 1
end

local function arm_recording(n)
  record_bank = n
end

local function stop_recording()
  local recorded_events = #pattern_banks[record_bank]

  if recorded_events > 0 then
    -- save last delta to first event
    local current_time = util.time()
    local final_delta = current_time - record_prevtime
    pattern_banks[record_bank][1][1] = final_delta

    start_playback(record_bank)
  end

  record_bank = -1
  record_prevtime = -1
end

local function pattern_next(n)
  local bank = pattern_banks[n]
  local pos = pattern_positions[n]

  local event = bank[pos]
  local delta, x, y, z = table.unpack(event)
  pattern_leds[n] = z
  grid_key(x, y, z, true)

  local next_pos = pos + 1
  if next_pos > #bank then
    next_pos = 1
  end

  local next_event = bank[next_pos]
  local next_delta = next_event[1]
  pattern_positions[n] = next_pos

  -- schedule next event
  pattern_timers[n]:start(next_delta, 1)
end

local function record_handler(n)
  if alt then
    -- clear pattern
    if n == record_bank then stop_recording() end
    if pattern_timers[n].is_running then stop_playback(n) end
    pattern_banks[n] = {}
    do return end
  end

  if n == record_bank then
    -- stop if pressed current recording
    stop_recording()
  else
    local pattern = pattern_banks[n]

    if #pattern > 0 then
      -- toggle playback if there's data
      if pattern_timers[n].is_running then stop_playback(n) else start_playback(n) end
    else
      -- stop recording if it's happening
      if record_bank > 0 then
        stop_recording()
      end
      -- arm new pattern for recording
      arm_recording(n)
    end
  end
end

--[[
internals
]]

local function display_voice(phase, width)
  local pos = phase * width

  local levels = {}
  for i = 1, width do levels[i] = 0 end

  local left = math.floor(pos)
  local index_left = left + 1
  local dist_left = math.abs(pos - left)

  local right = math.floor(pos + 1)
  local index_right = right + 1
  local dist_right = math.abs(pos - right)

  if index_left < 1 then index_left = width end
  if index_left > width then index_left = 1 end

  if index_right < 1 then index_right = width end
  if index_right > width then index_right = 1 end

  levels[index_left] = math.floor(math.abs(1 - dist_left) * 15)
  levels[index_right] = math.floor(math.abs(1 - dist_right) * 15)

  return levels
end

local function start_voice(voice, pos)
  engine.seek(voice, pos)
  engine.gate(voice, 1)
  gates[voice] = 1
end

local function stop_voice(voice)
  gates[voice] = 0
  engine.gate(voice, 0)
end

local function grid_refresh()
  if g == nil then
    return
  end

  grid_ctl:led_level_all(0)
  grid_voc:led_level_all(0)

  -- alt
  grid_ctl:led_level_set(16, 1, alt and 15 or 1)

  -- pattern banks
  for i=1, VOICES do
    local level = 2

    if #pattern_banks[i] > 0 then level = 5 end
    if pattern_timers[i].is_running then
      level = 10
      if pattern_leds[i] > 0 then
        level = 12
      end
    end

    grid_ctl:led_level_set(8 + i, 1, level)
  end

  -- blink armed pattern
  if record_bank > 0 then
      grid_ctl:led_level_set(8 + record_bank, 1, 15 * blink)
  end

  -- voices
  for i=1, VOICES do
    if voice_levels[i] > 0 then
      grid_ctl:led_level_set(i, 1, math.min(math.ceil(voice_levels[i] * 15), 15))
      grid_voc:led_level_row(1, i + 1, display_voice(positions[i], 16))
    end
  end

  local buf = grid_ctl | grid_voc
  buf:render(g)
  g:refresh()
end

function grid_key(x, y, z, skip_record)
  if y > 1 or (y == 1 and x < 9) then
    if not skip_record then
      record_event(x, y, z)
    end
  end

  if z > 0 then
    -- set voice pos
    if y > 1 then
      local voice = y - 1
      start_voice(voice, (x - 1) / 16)
    else
      if x == 16 then
        -- alt
        alt = true
      elseif x > 8 then
        record_handler(x - 8)
      elseif x == 8 then
        -- reserved
      elseif x < 8 then
        -- stop
        local voice = x
        stop_voice(voice)
      end
    end
  else
    -- alt
    if x == 16 and y == 1 then alt = false end
  end
end

function init()
  g.key = function(x, y, z)
    grid_key(x, y, z)
  end

  -- polls
  for v = 1, VOICES do
    local phase_poll = poll.set('phase_' .. v, function(pos) positions[v] = pos end)
    phase_poll.time = 0.05
    phase_poll:start()

    local level_poll = poll.set('level_' .. v, function(lvl) voice_levels[v] = lvl end)
    level_poll.time = 0.05
    level_poll:start()
  end

  -- recorders
  for v = 1, VOICES do
    table.insert(pattern_timers, metro.init(function(tick) pattern_next(v) end))
    table.insert(pattern_banks, {})
    table.insert(pattern_leds, 0)
    table.insert(pattern_positions, 1)
  end

  -- grid refresh timer, 40 fps
  metro_grid_refresh = metro.init(function(stage) grid_refresh() end, 1 / 40)
  metro_grid_refresh:start()

  metro_blink = metro.init(function(stage) blink = blink ~ 1 end, 1 / 4)
  metro_blink:start()

  local sep = ": "

  params:add_taper("reverb_mix", "*"..sep.."mix", 0, 100, 50, 0, "%")
  params:set_action("reverb_mix", function(value) engine.reverb_mix(value / 100) end)

  params:add_taper("reverb_room", "*"..sep.."room", 0, 100, 50, 0, "%")
  params:set_action("reverb_room", function(value) engine.reverb_room(value / 100) end)

  params:add_taper("reverb_damp", "*"..sep.."damp", 0, 100, 50, 0, "%")
  params:set_action("reverb_damp", function(value) engine.reverb_damp(value / 100) end)

  for v = 1, VOICES do
    params:add_separator()

    params:add_file(v.."sample", v..sep.."sample")
    params:set_action(v.."sample", function(file) engine.read(v, file) end)

    params:add_taper(v.."volume", v..sep.."volume", -60, 20, 0, 0, "dB")
    params:set_action(v.."volume", function(value) engine.volume(v, math.pow(10, value / 20)) end)

    params:add_taper(v.."speed", v..sep.."speed", -200, 200, 100, 0, "%")
    params:set_action(v.."speed", function(value) engine.speed(v, value / 100) end)

    params:add_taper(v.."jitter", v..sep.."jitter", 0, 500, 0, 5, "ms")
    params:set_action(v.."jitter", function(value) engine.jitter(v, value / 1000) end)

    params:add_taper(v.."size", v..sep.."size", 1, 500, 100, 5, "ms")
    params:set_action(v.."size", function(value) engine.size(v, value / 1000) end)

    params:add_taper(v.."density", v..sep.."density", 0, 512, 20, 6, "hz")
    params:set_action(v.."density", function(value) engine.density(v, value) end)

    params:add_taper(v.."pitch", v..sep.."pitch", -24, 24, 0, 0, "st")
    params:set_action(v.."pitch", function(value) engine.pitch(v, math.pow(0.5, -value / 12)) end)

    params:add_taper(v.."spread", v..sep.."spread", 0, 100, 0, 0, "%")
    params:set_action(v.."spread", function(value) engine.spread(v, value / 100) end)

    params:add_taper(v.."fade", v..sep.."att / dec", 1, 9000, 1000, 3, "ms")
    params:set_action(v.."fade", function(value) engine.envscale(v, value / 1000) end)
  end

  params:bang()
  
  --- rreeellllsslzz
  
    reel.proj = "untitled"
  reel.s = {}
  reel.e = {}
  reel.paths = {}
  reel.name = {"-", "-", "-", "-"}
  reel.play = {0, 0, 0, 0}
  reel.rec = {0, 0, 0, 0}
  reel.rec_level = 1
  reel.pre_level = 1
  reel.loop_start = {0, 0, 0, 0}
  reel.loop_end = {60, 60, 60, 60}
  reel.vol = {1, 1, 1, 1}
  reel.clip = {0, 0, 0, 0}
  reel.pos = 0
  reel.speed = 0
  reel.rev = 0
  reel.length = {60, 60, 60, 60}
  reel.q = {1, 1, 1, 1}
  audio.level_cut(1)
  audio.level_adc_cut(1)
  for i=1,4 do
    sc.level(i,1)
    sc.level_slew_time(1,SLEW_AMOUNT)
    sc.level_input_cut(1, i, 1.0)
    sc.level_input_cut(2, i, 1.0)
    sc.pan(i, 0.5)
    sc.play(i, 0)
    sc.rate(i, 1)
    reel.s[i] = 2 + (i-1) * clip_len_s
    reel.e[i] = reel.s[i] + (clip_len_s - 2)
    sc.loop_start(i, reel.s[i])
    sc.loop_end(i, reel.e[i])
    
    sc.loop(i, 1)
    sc.fade_time(i, 0.1)
    sc.rec(i, 0)
    sc.rec_level(i, 1)
    sc.pre_level(i, 1)
    sc.position(i, reel.s[i])
    sc.buffer(i,1)
    sc.enable(i, 1)
    update_rate(i)

    sc.filter_dry(i, 1);
    sc.filter_fc(i, 0);
    sc.filter_lp(i, 0);
    sc.filter_bp(i, 0);
    sc.filter_rq(i, 0);
    
    params:add_control(i.."pan", i.." pan", controlspec.new(0, 1, 'lin', 0, 0.5, ""))
    params:set_action(i.."pan", function(x) softcut.pan(i,x) end)
  end
  -- reel graphics
  for i=1,6 do
    r_reel[i].orbit = math.fmod(i,2)~=0 and 6 or 15
    r_reel[i].position = i <= 2 and 0 or i <= 4 and 2 or 4
    r_reel[i].velocity = util.linlin(0, 1, 0.01, speed, 1)
    l_reel[i].orbit = math.fmod(i,2)~=0 and 6 or 15
    l_reel[i].position = i <= 2 and 3 or i <= 4 and 5 or 7.1
    l_reel[i].velocity = util.linlin(0, 1, 0.01, speed*3, 0.2)
  end
  init_folders()
  update_reel()
  -- settings
  settings_list = UI.ScrollingList.new(75, 12, 1, {"Load reel", "New reel"})
  settings_list.num_visible = 4
  settings_list.num_above_selected = 0
  settings_list.active = false
  settings_amounts_list = UI.ScrollingList.new(125, 12)
  settings_amounts_list.num_visible = 4
  settings_amounts_list.num_above_selected = 0
  settings_amounts_list.text_align = "right"
  settings_amounts_list.active = false
  --
  play_counter = metro.init{event = function(stage) if playing == true then play_count() end end,time = 0.01, count = -1}
  blink_metro = metro.init{event = function(stage) blink_r = not blink_r end, time = 1 / 2}
  blink_metro:start()
  reel_redraw = metro.init{event = function(stage) redraw() animation() end, time = 1 / 60}
  reel_redraw:start()
  --

end

--[[
exports
]]

function key(n,z)
  if z == 1 then
    if n == 1 then
      if not settings then
        settings = true
        settings_list.active = true
        settings_amounts_list.active = true
      else
        settings = false
      end
    elseif n == 2 then
      if  reel.play[trk] ==  0 then
          play(true)
      elseif reel.play[trk] == 1 then
        if reel.rec[trk] == 1 then
          rec(trk,false)
        else
          play(false)
        end
      elseif filesel then
        filesel = false
      end
    elseif n == 3 then
      if settings == false and mounted then
        if reel.rec[trk] == 0 then
          rec(trk,true)
          mute(trk, false)
        elseif reel.rec[trk] == 1 then
          rec(trk,false)
        end
      elseif settings == true then
        if settings_list.index == 1 then
          if mounted then
            if reel.clip[trk] == 0  then
              filesel = true
              fileselect.enter(_path.audio, load_clip)
            elseif reel.clip[trk] == 1 then
              mute(trk, not mutes[trk])
            end
          else
            filesel = true
            fileselect.enter(_path.data .."reels/", load_mix)
          end
        elseif settings_list.index == 2 then
          if not mounted then new_reel() end
        elseif settings_list.index == 8 then
          filesel = true
          fileselect.enter(_path.audio, load_clip)
        elseif settings_list.index == 9 then
          filesel = true
          textentry.enter(save_clip, reel.name[trk] == "-*" and "reel-" .. (math.random(9000)+1000) or (reel.name[trk]:find("*") and reel.name[trk]:match("[^.]*")):sub(2,-1))
        elseif settings_list.index == 11 then
          clear_track(trk)
        elseif settings_list.index == 12 then
          new_reel()
        elseif settings_list.index == 14 then
          filesel = true
          textentry.enter(save_project, reel.proj)
        elseif settings_list.index == 15 then
          filesel = true
            fileselect.enter(_path.data.."reels/", load_mix)
        elseif settings_list.index == 16 then
          warble_state = not warble_state
        end
        update_params_list()
      end
    end
  end
end

function enc(n,d)
  norns.encoders.set_sens(1,4)
  norns.encoders.set_sens(2,3)
  norns.encoders.set_sens(3,1)
  norns.encoders.set_accel(1,false)
  norns.encoders.set_accel(2,settings and false or true)
  norns.encoders.set_accel(3,(settings and (settings_list.index == 2 or settings_list.index == 3)) and true or false)
  if n == 1 then
    if not recording then 
      trk = util.clamp(trk + d,1,TR) 
    end
    if mounted then
      update_params_list()
    end
    if c_pos_x ~= bind_vals[trk] then
      c_pos_x = (c_pos_x + d)
    end
  elseif n == 2 then
    if not settings then
      speed = util.clamp(util.round((speed + d /  100 ),0.001),-0.8,0.8)
      if speed < 0 then
        reel.rev = 1
      elseif speed >= 0 then
        reel.rev = 0
      end
      for i=1,TR do
        update_rate(i)
      end
    elseif settings then
      settings_list:set_index_delta(util.clamp(d, -1, 1), false)
      settings_amounts_list:set_index(settings_list.index)
    end
  elseif n == 3 then
    if not settings then
      rec_vol = util.clamp(rec_vol + d / 100, 0,1)
      sc.rec_level(trk,rec_vol)
    elseif settings then
      if settings_list.index == 1 and mutes[trk] == false then
        reel.vol[trk] = util.clamp(reel.vol[trk] + d / 100, 0,1)
        sc.level(trk,reel.vol[trk])
        update_params_list()
      elseif settings_list.index == 2 then
        reel.loop_start[trk] = util.clamp(reel.loop_start[trk] + d / 10,0,reel.length[trk])
        if reel.loop_start[trk] <= reel.loop_end[trk] then
          reel.loop_end[trk] = util.clamp(reel.loop_end[trk] + d / 10,0,util.round(reel.length[trk],0.1))
        end
        set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
      elseif settings_list.index == 3 then
        reel.loop_end[trk] = util.clamp(reel.loop_end[trk] + d / 10,0,util.round(reel.length[trk],0.1))
        if reel.loop_end[trk] <= reel.loop_start[trk] then
          reel.loop_start[trk] = util.clamp(reel.loop_start[trk] + d / 10,0,reel.length[trk])
        end
        set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
      elseif settings_list.index == 4 then
        reel.q[trk] = util.clamp(reel.q[trk] + d,1,24)
        update_rate(trk) -- ?
      end
      update_params_list()
    end
  end
end

function redraw()
  screen.aa(0)
  if not filesel then
    screen.clear()
    draw_reel(reel_pos_x,reel_pos_y)
    draw_cursor(c_pos_x,c_pos_y)
    draw_bars(15,61)
    if recording then
      screen.level(blink_r and 5 or 15)
      screen.circle(reel_pos_x + 80,reel_pos_y + 30,4)
      screen.fill()
      screen.stroke()
    end
    if not settings then
      draw_rec_vol_slider(reel_pos_x,reel_pos_y)
    end
    if settings and reel_pos_x < -15 then
      if mounted then
        screen.level(6)
        screen.move(128,5)
        screen.text_right(reel.name[trk]:match("[^.]*"))
        screen.stroke()
        settings_list:redraw()
        settings_amounts_list:redraw()
      else
        screen.level(6)
        settings_list:redraw()
      end
    end
  end
  screen.update()
end

function cleanup()
  sc.buffer_clear()
end
