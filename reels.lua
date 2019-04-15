--
-- reel to reel tape player 
-- @its_your_bedtime
--
-- hold btn 1 for settings
-- btn 2 play / pause
-- btn 3 rec on/off
--
-- enc 1 - switch track
-- enc 2 - change speed
-- enc 3 - overdub level

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
local TR = 4
local SLEW_AMOUNT = 0.03
local WARBLE_AMOUNT = 10
local trk = 1
local rec_blink = false
local r_reel = {{},{},{},{},{},{}}
local l_reel = {{},{},{},{},{},{}}
local speed_disp = {">",">>",">>>",">>>>","<","<<","<<<","<<<<"}
local reel = {}
local rec_time = 0
local rec_start
local play_time = {0,0,0,0}
local mutes = {true,true,true,true}
local loop_pos = {1, 1, 1, 1}
-- 
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
      if play_time[i] >= (reel.loop_end[i] or reel.length[i]) then 
        play_time[i] = reel.loop_start[i]
      end
    elseif reel.rev == 1 then
      play_time[i] = play_time[i] - (0.01 / (reel.q[i] - math.abs(speed / 2)))
      if play_time[i] <= (reel.loop_start[i] or 0) then
        play_time[i] = reel.loop_end[i]
      end
    end
  end
  if recording then
    rec_time = play_time[trk]
  end
  warble(warble_state)
end

local function menu_loop_pos(tr, pos)
  local init_string = "           "
  return ("%s%s%s"):format(init_string:sub(1,pos-1), "-", init_string:sub(pos+1))
end

local function update_params_list()
  settings_list.entries = {
    "TR " .. trk .. (mutes[trk] == false and "  Vol " or " "),
    "Quality",
    "<" .. menu_loop_pos(trk, loop_pos[trk]) .. ">",
    "Start", 
    "End", 
    "--", 
    "Load clip", 
    "Save clip",  
    "--", 
    "Clear clip", 
    not mounted and "New reel" or "Clear all", 
    "--", 
    "Save reel", 
    "Load reel",
    "--",
    "Warble"
  }
  settings_amounts_list.entries = {
    mutes[trk] == false and util.round(reel.vol[trk]*100) or (reel.clip[trk] == 0 and "Load" or "muted") or " " .. util.round(reel.vol[trk]*100),
    reel.q[trk],
    "",
    util.round(reel.loop_start[trk],0.1),
    util.round(reel.loop_end[trk],0.1),
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    "",
    warble_state == true and "On" or "Off"
  }
end

local function set_loop(tr, st, en)
  loop_pos[tr] = util.clamp(math.ceil((st)  / 100 * 18),1,11)
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
  if state == true then
    recording = true
    if not reel.name[tr]:find("*") then
      reel.name[tr] = "*" .. reel.name[tr]
    end
    -- sync pos with graphics
    rec_start = play_time[tr]
    sc.position(tr, reel.s[tr] + rec_start)
    reel.rec[tr] = 1
    sc.rec(tr,1)
  elseif state == false then
    recording = false
    reel.rec[tr] = 0
    sc.rec(tr,0)
     if reel.clip[tr] == 0 then
       if reel.rev == 0 then
         reel.loop_start[tr] = util.clamp(rec_start,0,60)
         reel.loop_end[tr] = util.clamp(rec_time,0,60)
         set_loop(tr, reel.loop_start[tr], reel.loop_end[tr])
       elseif reel.rev == 1 then
         reel.loop_start[tr] = util.clamp(rec_time,0,60)
         reel.loop_end[tr] = util.clamp(rec_start,0,60)
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
  reel.q[tr] = 1
  reel.loop_start[tr] = 0
  reel.loop_end[tr] = 60
  reel.length[tr] = 60
  reel.clip[tr] = 0
  set_loop(tr,0,reel.loop_end[tr])
  sc.buffer_clear_region(reel.s[tr], reel.length[tr])
  sc.position(tr,reel.s[tr])
  print("Clear buffer region " .. reel.s[tr], reel.length[tr])
end

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
    table.insert(reel.loop_start, 0)
    table.insert(reel.loop_end,60)
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

function init()
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
  blink_metro = metro.init{event = function(stage) rec_blink = not rec_blink end, time = 1 / 2}
  blink_metro:start()
  reel_redraw = metro.init{event = function(stage) redraw() animation() end, time = 1 / 60}
  reel_redraw:start()
  --
end

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
        elseif settings_list.index == 7 then
          filesel = true
          fileselect.enter(_path.audio, load_clip)
        elseif settings_list.index == 8 then
          filesel = true
          textentry.enter(save_clip, reel.name[trk] == "-*" and "reel-" .. (math.random(9000)+1000) or (reel.name[trk]:find("*") and reel.name[trk]:match("[^.]*")):sub(2,-1))
        elseif settings_list.index == 10 then
          clear_track(trk)
        elseif settings_list.index == 11 then
          new_reel()
        elseif settings_list.index == 13 then
          filesel = true
          textentry.enter(save_project, reel.proj)
        elseif settings_list.index == 14 then
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
  norns.encoders.set_accel(3,(settings and (settings_list.index == 3 or settings_list.index == 4 or settings_list.index == 5)) and true or false)
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
    elseif (settings and mounted) then
      if settings_list.index == 1 and mutes[trk] == false then
        reel.vol[trk] = util.clamp(reel.vol[trk] + d / 100, 0,1)
        sc.level(trk,reel.vol[trk])
        update_params_list()
      elseif settings_list.index == 2 then
        reel.q[trk] = util.clamp(reel.q[trk] + d,1,24)
        update_rate(trk)
      elseif settings_list.index == 3 then
        local loop_len = reel.loop_end[trk] - reel.loop_start[trk]
        reel.loop_start[trk] = util.clamp(reel.loop_start[trk] + d / 10,0,59)
        reel.loop_end[trk] = util.clamp(reel.loop_start[trk] + loop_len,reel.loop_start[trk],reel.length[trk])
        set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
      elseif settings_list.index == 4 then
        reel.loop_start[trk] = util.clamp(reel.loop_start[trk] + d / 10,0,reel.loop_end[trk])
        set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
      elseif settings_list.index == 5 then
        reel.loop_end[trk] = util.clamp(reel.loop_end[trk] + d / 10,reel.loop_start[trk],util.round(reel.length[trk],0.1))
        set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
      elseif settings_list.index == 16 then
        reel.loop_end[trk] = util.clamp(reel.loop_end[trk] + d / 10,reel.loop_start[trk],util.round(reel.length[trk],0.1))
        set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
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
      screen.level(rec_blink and 5 or 15)
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
