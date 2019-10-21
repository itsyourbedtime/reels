-- reel to reel tape player lib 
-- 2.0 @its_your_bedtime
--
-- How to:
-- Place 
--       reels.init() 
--       reels:enc(n,d),
--       reels:key(n,z)
--       reels:redraw() 
--
-- inside corresponding functions 
-- 
-- Activate via params page or 
-- manually with reels.active = true / false

local reels = {}
reels.mix = require 'core/mix'
local UI = require "ui"
local tab = require 'tabutil'
local fileselect = require "fileselect"
local textentry = require "textentry"
local mix = require 'core/mix'

local playing = false
local recording = false
local filesel = false
local settings = false
local mounted = false
local flutter_state = false
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
local input_vol = 1
local engine_vol = 0
local fade = 0.001
local TR = 4
local SLEW_AMOUNT = 1
local FLUTTER_AMOUNT = 60
local trk = 1
local rec_blink = false
local r_reel = {{},{},{},{},{},{}}
local l_reel = {{},{},{},{},{},{}}
local speed_disp = {">",">>",">>>",">>>>","<","<<","<<<","<<<<"}
local reel = {}
local rec_time = 0
local rec_start = 0
local play_time = {0,0,0,0}
local mutes = {true,true,true,true}
local loop_pos = {1, 1, 1, 1}
local threshold_val = 1
local arm = false
local active = false

mix.vu = function(in1,in2,out1,out2)
  mix.in1 = in1
  mix.in2 = in2
  mix.out1 = out1
  mix.out2 = out2
end

reels.threshold = function(val)
  if (mix.in1 >= val or mix.in2 >= val) then
    return true
  elseif (engine_vol > 0 and (mix.out1 >= val or mix.out2 >= val)) then -- engine level dumb hack
    return true
  else
    return false
  end
end

reels.update_rate = function(i)
  local n = math.pow(2,reel.speed)
  reel.speed = math.abs(speed)
  if reel.rev == 1 then n = -n end
  softcut.rate(i, n / reel.q[i])
end

reels.flutter = function(state)
  local n = {}
  if state == true then
    for i=1,TR do
      n[i] = (math.pow(2,reel.speed) / reel.q[i])
      softcut.rate(i, n[i] + l_reel[i].position / 10)
      reels.update_rate(i)
    end
  end
end

reels.play_count = function()
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
  reels.flutter(flutter_state)
end

reels.menu_loop_pos = function(tr, pos)
  local init_string = "           "
  return ("%s%s%s"):format(init_string:sub(1,pos-1), "-", init_string:sub(pos+1))
end

reels.update_params_list = function()
  if mounted then
    settings_list.entries = {
      "TR " .. trk .. ((mutes[trk] == false and reel.clip[trk] == 1) and "  Vol" or " "),
      "<" .. reels.menu_loop_pos(trk, loop_pos[trk]) .. ">",
      "Start", 
      "End", 
      "--",
      "Quality",
      "Flutter",
      "Threshold",
      "--", 
      "Clear track", 
      "Load clip", 
      "Save clip",  
      "-- ", 
      not mounted and "New reel" or "Clear all",
      "Load reel",
      "Save reel", 
    }
    settings_amounts_list.entries = {
      (mutes[trk] == false and reel.clip[trk] == 1) and util.round(reel.vol[trk]*100) or (reel.name[trk] == "-" and "Load" or "Muted") or " " .. util.round(reel.vol[trk]*100),
      "",
      util.round(reel.loop_start[trk],0.1),
      util.round(reel.loop_end[trk],0.1),
      "",
      reel.q[trk] == 1 and "1:1" or "1:" .. reel.q[trk],
      flutter_state == true and "on" or "off",
      threshold_val == 0 and "no" or threshold_val, 
      "","","","","","","","",
    }
  else 
    settings_list.entries = {"New reel", "Load reel"}
    settings_amounts_list.entries = {}
  end
end

reels.set_loop = function(tr, st, en)
  loop_pos[tr] = util.clamp(math.ceil((st)  / 100 * 18),1,11)
  st = reel.s[tr] + st
  en = reel.s[tr] + en
  softcut.loop_start(tr,st)
  softcut.loop_end(tr,en)
  if play_time[tr] > en or play_time[tr] < st then
    softcut.position(tr,st)
    play_time[trk] = reel.loop_start[trk]
  end
end

reels.rec = function(tr, state)
  if state == true then
    recording = true
    if not reel.name[tr]:find("*") then
      reel.name[tr] = "*" .. reel.name[tr]
      rec_start = play_time[tr] 
      reels.update_params_list()
    end
    -- sync pos with graphics
    softcut.position(tr, reel.s[tr] + play_time[tr]) -- fix offset?
    softcut.rec(tr,1)
  elseif state == false then
    if (reel.clip[tr] == 0 and recording) then
      -- l o o p i n g
      if reel.rev == 0 then
        reel.loop_start[tr] = util.clamp(rec_start, 0, 60)
        reel.loop_end[tr] = util.clamp(rec_time, 0, 60)
      elseif reel.rev == 1 then
        reel.loop_start[tr] = util.clamp(rec_time, 0, 60)
        reel.loop_end[tr] = util.clamp(rec_start, 0, 60)
      end
      if reel.loop_end[tr] < reel.loop_start[tr] then
        reel.loop_end[tr] = 60
      end
      reels.set_loop(tr, reel.loop_start[tr] + 0.01, reel.loop_end[tr] + 0.01)
      reel.clip[tr] =1
    end
    reel.clip[tr] = reel.clip[tr]
    recording = false
    reel.rec[tr] = 0
    softcut.rec(tr,0)
    reels.update_params_list()
  end
end

reels.rec_work = function(tr)
  if reel.rec[tr] == 1 then
    if ((reels.threshold(threshold_val) and arm) and playing) then
      arm = false 
      reels.rec(tr,true)
    end
  else
  end
end

reels.mute = function(tr,state)
  if state == true then
    softcut.level(tr,0)
    mutes[tr] = true
  elseif state == false then
    softcut.level(tr,reel.vol[tr])
    mutes[tr] = false
  end
end

reels.play = function(state)
  if state == true then
    playing = true
    reels.play_counter:start()
    for i=1,TR do
      softcut.play(i,1)
      reel.play[i] = 1
    end
  elseif state == false then
    playing = false
    reels.play_counter:stop()
    for i=1,TR do
    if reel.rec[i] == 1 then reels.rec(i,false) end
      softcut.play(i,0)
      reel.play[i] = 0
    end
  end
end

reels.init_folders = function()
  if util.file_exists(_path.data .. "reels/") == false then
    util.make_dir(_path.data .. "reels/")
  end
  if util.file_exists(_path.audio .. "reels/") == false then
    util.make_dir(_path.audio .. "reels/")
  end
end

reels.clear_track = function(tr)
  reel.name[tr] = "-"
  reel.clip[tr] = 0
  reel.q[tr] = 1
  reel.loop_start[tr] = 0
  reel.loop_end[tr] = 60
  reel.length[tr] = 60
  reel.clip[tr] = 0
  reels.set_loop(tr,0,reel.loop_end[tr])
  softcut.buffer_clear_region(reel.s[tr], reel.length[tr])
  softcut.position(tr,reel.s[tr])
end

reels.new_reel = function()
  softcut.buffer_clear()
  settings_list.index = 1
  settings_amounts_list.index = 1
  rec_time = 0
  playing = false
  for i=1,TR do
    reels.clear_track(i)
  end
  mounted = true
  reels.update_params_list()
end

reels.load_clip = function(path)
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
      softcut.buffer_read_mono(path, 0, reel.s[trk], reel.length[trk], 1, 1)
      if not playing then softcut.play(trk,0) end
      play_time[trk] = 0
      softcut.position(trk,reel.s[trk])
      softcut.level(trk, reel.vol[trk])
      reels.mute(trk,false)
      mounted = true
      reels.update_rate(trk)
      reels.update_params_list()
      reels.set_loop(trk,0,reel.loop_end[trk])
    else
      print("not a sound file")
    end
  end
  settings = true
  filesel = false
end

reels.load_reel_data = function(pth)
  saved = tab.load(pth)
  if saved ~= nil then
    print("reel data found")
    reel = saved
  else
    print("no reel data")
  end
end

reels.load_reel = function(path)
  if path ~= "cancel" then
    if path:find(".reel") then
      reels.load_reel_data(path)
      mounted = true
      trk = 1
      for i=1,TR do
        if reel.name[i] ~= "-" then
          reels.load_clip(reel.paths[i])
          trk = util.clamp(trk + 1,1,TR)
          play_time[i] = reel.loop_start[i]
          softcut.position(i,reel.s[i] + reel.loop_start[i])
          reels.update_rate(i)
          softcut.play(i,0)
        end
      end
    trk = 1
    settings = true
    else
      print("not a reel file")
    end
  else
    mounted = false 
  end
  filesel = false
  reels.update_params_list()
end

reels.save_clip = function(txt)
  if txt then
    local c_start = reel.s[trk]
    local c_len = reel.e[trk]
    print("SAVE " .. _path.audio .. "reels/".. txt .. ".aif", c_start, c_len)
    softcut.buffer_write_mono(_path.audio .. "reels/"..txt..".aif",c_start,c_len, 1)
    reel.name[trk] = txt
  else
    print("save cancel")
  end
  filesel = false
end

reels.save_project = function(txt)
  if txt then
    reel.proj = txt
    for i=1,TR do
      if reel.name[i] ~= "-" then
        if reel.name[i]:find("*") then
          local name = reel.name[i] == "*-" and (txt .. "-rec-" .. i .. ".aif") or reel.name[i]:sub(2,-1) -- remove asterisk
          local save_path = _path.audio .."reels/" .. name
          reel.paths[i] = save_path
          print("saving "..i .. "clip at " .. save_path, reel.s[i],reel.e[i])
          softcut.buffer_write_mono(_path.audio .."reels/" .. name, reel.s[i],reel.e[i], 1)
        end
      end
    end
    tab.save(reel, _path.data.."reels/".. txt ..".reel")
  else
    print("save cancel")
  end
  filesel = false
end

reels.init = function()
  --softcut.reset()
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
  audio.level_eng_cut(0)
  mix:set_raw("monitor", rec_vol)
  -- param switch 
  params:add_option ("tape_switch", "Reels:", {"background", "active"}, 1)
  params:set_action("tape_switch", function(x) if x == 1 then reels.active = false else reels.active = true end end)
  params:add_separator()

  params:add_control("IN", "Input level", controlspec.new(0, 1, 'lin', 0, 1, ""))
  params:set_action("IN", function(x) input_vol = x  audio.level_adc_cut(input_vol) end)
  params:add_control("ENG", "Engine level", controlspec.new(0, 1, 'lin', 0, 0, ""))
  params:set_action("ENG", function(x) engine_vol = x audio.level_eng_cut(engine_vol) end)
  params:add_separator()


  for i=1,4 do
    softcut.level(i,1)
    softcut.level_input_cut(1, i, 1.0)
    softcut.level_input_cut(2, i, 1.0)
    softcut.pan(i, 0)
    softcut.play(i, 0)
    softcut.rate(i, 1)
    reel.s[i] = 2 + (i-1) * clip_len_s
    reel.e[i] = reel.s[i] + (clip_len_s - 2)
    softcut.loop_start(i, reel.s[i])
    softcut.loop_end(i, reel.e[i])
    
    softcut.loop(i, 1)
    softcut.rec(i, 0)
    
    softcut.fade_time(i,0.01)
    softcut.level_slew_time(i,0)
    softcut.rate_slew_time(i,SLEW_AMOUNT)

    softcut.rec_level(i, 1)
    softcut.pre_level(i, 1)
    softcut.position(i, reel.s[i])
    softcut.buffer(i,1)
    softcut.enable(i, 1)
    reels.update_rate(i)

    softcut.filter_dry(i, 1);
    softcut.filter_fc(i, 0);
    softcut.filter_lp(i, 0);
    softcut.filter_bp(i, 0);
    softcut.filter_rq(i, 0);
        
    params:add_control(i.."vol", i.." Volume", controlspec.new(0, 1, 'lin', 0, 1, ""))
    params:set_action(i.."vol", function(x) reel.vol[i]  = x softcut.level(i, reel.vol[i]) reels.update_params_list() end)

    params:add_control(i.."pan", i.." Pan", controlspec.new(-1, 1, 'lin', 0, 0, ""))
    params:set_action(i.."pan", function(x) softcut.pan(i,x) end)
    
    params:add_separator()
    
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
  reels.init_folders()
  reels.update_reel()
  -- settings
  settings_list = UI.ScrollingList.new(75, 12, 1, {"New reel", "Load reel"})
  settings_list.num_visible = 4
  settings_list.num_above_selected = 0
  settings_list.active = false
  settings_amounts_list = UI.ScrollingList.new(128, 12)
  settings_amounts_list.num_visible = 4
  settings_amounts_list.num_above_selected = 0
  settings_amounts_list.text_align = "right"
  settings_amounts_list.active = false
  --
  reels.play_counter = metro.init{event = function(stage) if playing == true then reels.play_count() end end,time = 0.01, count = -1}
  reels.blink_metro = metro.init{event = function(stage) rec_blink = not rec_blink end, time = 1 / 2}
  reels.blink_metro:start()
  reels.reel_redraw = metro.init{event = function(stage) if (not norns.menu.status() and reels.active) then reels:redraw() reels.animation() else end end, time = 1 / 60}
  reels.reel_redraw:start()
  reels.rec_worker = metro.init{event = function(stage) reels.rec_work(trk) end, time = 1 / 30}
  reels.rec_worker:start()
  --
  if reels.active then
    params:set("tape_switch", 2)
  else 
    params:set("tape_switch", 1)
  end
end

function reels.update_reel()
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

reels.animation = function()
  if playing == true then
    reels.update_reel()
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

reels.draw_reel = function(x,y)
  local l = util.round(speed * 10)
  if l < 0 then
    l = math.abs(l) + 4
  elseif l >= 4 then
    l = 4
  elseif l == 0 then
    l = reel.rev == 1 and 5 or 1
  end
  screen.level(2)
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
    local x1, x2, x3
    screen.level(6)
    if not flutter_state or (flutter_state and not playing) then
      x1 = x + 65
      x2 = x + 65
      x3 = x + 70
    elseif (flutter_state and playing) then
      x1 =  x + 65 - (FLUTTER_AMOUNT * math.random(5)/40)
      x2 =  x + 65 - (FLUTTER_AMOUNT * math.random(10)/20)
      x3 =  x + 70 - (FLUTTER_AMOUNT * math.random(5)/40)
    end
    screen.move(x,y-17)
    screen.curve(x1, y-12, x2, y-12, x3, y-12)
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
    screen.curve(x+5,y+30,x+5,y+30,x+5,y+30)
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

reels.draw_bars = function(x,y)
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
    screen.rect(((x * i *2) - 24) + ((reel.loop_start[i] - 1) / reel.length[i] * 25), 61, ((reel.loop_end[i] + 1) / reel.length[i] * 25) - ((reel.loop_start[i] - 1) / reel.length[i] * 25), 2)
    screen.fill()
    screen.level(15)
    screen.move(((x * i *2) - 24) + (((play_time[i]) / (reel.length[i]) * 25)), 61)
    screen.line_rel(0,2)
    screen.stroke()
  end
end



reels.draw_cursor = function(x,y)
  screen.level(9)
  screen.move(x-3,y-3)
  screen.line(x,y)
  screen.line_rel(3,-3)
  screen.stroke()
end


reels.draw_rec_vol_slider = function(x,y)
  
  norns.vu = mix.vu
  screen.level(1)
  screen.move(x - 30, y - 17)
  screen.line(x - 30, y + 29)
  screen.stroke()
  screen.level(3)
  local n = util.clamp((mix.in1 or 0)/64*48,0,rec_vol * 44)
  screen.rect(x - 31.5,y + 30,2,-n)
  screen.line_rel(3,0)
  screen.stroke()
  screen.level(4)
  local n = util.clamp((mix.in2 or 0)/64*48,0,rec_vol * 44)
  screen.rect(x - 31.5,y + 30,3,-n)
  screen.line_rel(3,0)
  screen.fill()
  screen.level(6)
  screen.rect(x - 33, 48 - rec_vol / 3 * 132, 5, 2)
  screen.fill()
  screen.level(5)
  screen.rect(x - 32, 50 - threshold_val / 15 * 10, 3, 1)
  screen.fill()
end

function reels:key(n,z)
  if reels.active then
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
            reels.play(true)
        elseif reel.play[trk] == 1 then
          if reel.rec[trk] == 1 then
            reel.rec[trk] = 0
            arm = false
            reels.rec(trk,false)
          else
            reels.play(false)
          end
        elseif filesel then
          filesel = false
        end
      elseif n == 3 then
        if settings == false and mounted then
          if reel.rec[trk] == 0 then
            reel.rec[trk] = 1 -- rec work flag
            arm = true
            reels.mute(trk, false)
          elseif reel.rec[trk] == 1 then
            reel.rec[trk] = 0
            arm = false
            reels.rec(trk,false)
          end
        elseif settings == true then
          if settings_list.index == 1 then
            if mounted then
              if reel.name[trk] == "-" then
                filesel = true
                fileselect.enter(_path.audio, reels.load_clip)
              elseif reel.clip[trk] == 1 then
                reels.mute(trk, not mutes[trk])
              end
            else
              if not mounted then 
                reels.new_reel() 
              end
            end
          elseif (settings_list.index == 2 and not mounted) then
            filesel = true
            fileselect.enter(_path.data .."reels/", reels.load_reel)
          elseif settings_list.index == 10 then -- clear tr
            reels.clear_track(trk)
          elseif settings_list.index == 11 then -- load clip
            filesel = true
            fileselect.enter(_path.audio, reels.load_clip)
          elseif settings_list.index == 12 then -- save
            filesel = true
            textentry.enter(reels.save_clip, reel.name[trk] == "-*" and "reel-" .. (math.random(9000)+1000) or (reel.name[trk]:find("*") and reel.name[trk]:match("[^.]*")):sub(2,-1))
          elseif settings_list.index == 14 then -- clear reel
            reels.new_reel()
          elseif settings_list.index == 15 then -- load 
            filesel = true
              fileselect.enter(_path.data.."reels/", reels.load_reel)
          elseif settings_list.index == 16 then -- save 
            filesel = true
            textentry.enter(reels.save_project, reel.proj)
          elseif (settings_list.index <= 9 or settings_list.index >= 2) then
            if reel.rec[trk] == 0 then
              reel.rec[trk] = 1 -- rec work flag
              arm = true
              reels.mute(trk, false)
            elseif reel.rec[trk] == 1 then
              reel.rec[trk] = 0
              arm = false
              reels.rec(trk,false)
            end
          end
          reels.update_params_list()
        end
      end
    end
  else
  end
end

function reels:enc(n,d)
  if reels.active then
    norns.encoders.set_sens(1,7)
    norns.encoders.set_sens(2,(settings and 6 or 1))
    norns.encoders.set_sens(3,(settings and (settings_list.index == (1 or 2 or 7 or 8))) and 1 or (not settings and (speed < -0.01 or speed > 0.01)) and 1 or 3)
    norns.encoders.set_accel(1,false)
    norns.encoders.set_accel(2,false)
    norns.encoders.set_accel(3,(settings and settings_list.index < 5) and true or false)
    if n == 1 then
      if (not recording and reel.rec[trk] ~= 1) then 
        trk = util.clamp(trk + d,1,TR) 
      end
      if mounted then
        reels.update_params_list()
      end
      if c_pos_x ~= bind_vals[trk] then
        c_pos_x = (c_pos_x + d)
      end
    elseif n == 2 then
      if not settings then
        rec_vol = util.clamp(rec_vol + d / 100, 0,1)
        mix:set_raw("monitor",rec_vol)
        softcut.rec_level(trk,rec_vol)
      elseif settings then
        settings_list:set_index_delta(util.clamp(d, -1, 1), false)
        settings_amounts_list:set_index(settings_list.index)
      end
    elseif n == 3 then
      if not settings then
        speed = util.clamp(util.round((speed + d /  100 ),0.001),-0.8,0.8)
        if speed < 0 then
          reel.rev = 1
        elseif speed >= 0 then
          reel.rev = 0
        end
        for i=1,TR do
          reels.update_rate(i)
        end
      elseif (settings and mounted) then
        if settings_list.index == 1 and mutes[trk] == false then
          reel.vol[trk] = util.clamp(reel.vol[trk] + d / 100, 0,1)
          softcut.level(trk,reel.vol[trk])
          reels.update_params_list()
        elseif settings_list.index == 2 then
          local loop_len = reel.loop_end[trk] - reel.loop_start[trk]
          reel.loop_start[trk] = util.clamp(reel.loop_start[trk] + d / 10,0,59)
          reel.loop_end[trk] = util.clamp(reel.loop_start[trk] + loop_len,reel.loop_start[trk],reel.length[trk])
          reels.set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
        elseif settings_list.index == 3 then
          reel.loop_start[trk] = util.clamp(reel.loop_start[trk] + d / 10,0,reel.loop_end[trk])
          reels.set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
        elseif settings_list.index == 4 then
          reel.loop_end[trk] = util.clamp(reel.loop_end[trk] + d / 10,reel.loop_start[trk],util.round(reel.length[trk],0.1))
          reels.set_loop(trk,reel.loop_start[trk],reel.loop_end[trk])
        elseif settings_list.index == 6 then
          reel.q[trk] = util.clamp(reel.q[trk] + d,1,24)
          reels.update_rate(trk)
        elseif settings_list.index == 7 then
          flutter_state  = not flutter_state
        elseif settings_list.index == 8 then
          threshold_val = util.clamp(threshold_val + d, 0, 60)
          reels.update_rate(trk)
        end
        reels.update_params_list()
      end
    end
  else
  end
end

function reels:redraw()
  if reels.active then
    screen.aa(0)
    screen.font_size(8)
    if not filesel then
      screen.clear()
      reels.draw_reel(reel_pos_x,reel_pos_y)
      reels.draw_cursor(c_pos_x,c_pos_y)
      reels.draw_bars(15,61)
      if recording then
        screen.level(rec_blink and 5 or 15)
        screen.circle(reel_pos_x + 80,reel_pos_y + 30,4)
        screen.fill()
        screen.stroke()
      end
      if not settings then
        reels.draw_rec_vol_slider(reel_pos_x,reel_pos_y)
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
  else
  end
  screen.update()
end



return reels 
