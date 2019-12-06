--
-- reels 191116
-- @its_your_bedtime
-- llllllll.co/t/reels

local reels = {}

local ui_lib = require "ui"
local fileselect = require "fileselect"
local textentry = require "textentry"

local playing, recording, filesel, settings, mounted, blink = false, false, false, false, false, false
local speed, clip_length, rec_vol, input_vol, engine_vol, total_tracks, in_l, in_r = 0, 60, 1, 1, 0, 4, 0, 0

local ui = {
    speed = { ">", ">>", ">>>", ">>>>", "<", "<<", "<<<", "<<<<" },
    cursor = { 
        x = 20, 
        y = 58, 
        bind = { 20, 48, 80, 108, 0, 0, 0, 0, 0, 0 }
    },
    reel = {
        pos = { x = 28, y = 21 },  -- default
        left  = { {}, {}, {}, {}, {}, {} },
        right = { {}, {}, {}, {}, {}, {} },
    },
    tape = { 
        tension = 30,
        flutter = { on = false, amount = 60 }
    },
    playhead = {
        height = 35,
        brightness = 0,
    },
}

local reel = {
    proj = "untitled",
    s = {}, e = {}, paths = {},
    playback = { pos = 0, speed = 0, reverse = false },
    rec = { arm = false, time = 0, start = 0, level = 1, pre = 1, threshold = 1 },
    track = {
        selected = 1,
        name  = { "-", "-", "-", "-" },
        level = { 1, 1, 1, 1 },
        time  = { 0, 0, 0, 0 },
        quality = { 1, 1, 1, 1 },
        length  = { 60, 60, 60, 60 },
        clip  = { false, false, false, false },
        play = { false, false, false, false },
        rec  = { false, false, false, false },
        mute = { true, true, true, true },
    },
    loop = {
        pos = { 1, 1, 1, 1 },
        s = { 0, 0, 0, 0 },
        e = { 60, 60, 60, 60 },
    }
}

reels.threshold = function(val)
  if (in_l >= val / 1.5 or in_r >= val / 1.5) then
    return true
  elseif (engine_vol > 0 and (in_l >= val /1.5  or in_r >= val /1.5 )) then
    return true
  else
    return false
  end
end

reels.update_rate = function(i)
  local n = math.pow( 2, reel.playback.speed)
  reel.playback.speed = math.abs(speed)
  if reel.playback.reverse then n = -n end
  if playing then softcut.rate(i, n / reel.track.quality[i]) end
end

reels.flutter = function(state)
  local n = {}
  if state == true then
    for i=1, total_tracks do
      n[i] = (math.pow(2,reel.playback.speed) / reel.track.quality[i])
      softcut.rate(i, n[i] + ui.reel.left[i].position / 10)
      reels.update_rate(i)
    end
  end
end

reels.phase = function(t, x)
  if playing then 
    reel.track.time[t] = x 
    reels.flutter(ui.tape.flutter.on)
    if recording then reel.rec.time = reel.track.time[reel.track.selected] end
  end
end

reels.menu_loop_pos = function(tr, pos)
  local init_string = "           "
  return ("%s%s%s"):format(init_string:sub(1,pos-1), "-", init_string:sub(pos+1))
end

reels.update_params_list = function()
  local tr = reel.track
  local sel = tr.selected
  
  if mounted then
    settings_list.entries = {
      "TR " .. sel .. ((not tr.mute[sel] and tr.clip[sel]) and "  Vol" or " "),
      "<" .. reels.menu_loop_pos(sel, reel.loop.pos[sel]) .. ">",
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
      (tr.mute[sel] == false and tr.clip[sel]) and util.round(tr.level[sel]*100) or (tr.name[sel] == "-" and "Load" or "Muted") or " " .. util.round(tr.level[sel]*100),
      "",
      util.round(reel.loop.s[sel],0.1),
      util.round(reel.loop.e[sel],0.1),
      "",
      tr.quality[sel] == 1 and "1:1" or "1:" .. tr.quality[sel],
      ui.tape.flutter.on == true and "on" or "off",
      reel.rec.threshold == 0 and "no" or reel.rec.threshold, 
      "","","","","","","","",
    }
  else 
    settings_list.entries = {"New reel", "Load reel"}
    settings_amounts_list.entries = {}
  end
end

reels.set_loop = function(tr, st, en)
  reel.loop.pos[tr] = util.clamp(math.ceil((st)  / 100 * 18), 1, 11)
  st = reel.s[tr] + st
  en = reel.s[tr] + en
  softcut.loop_start(tr, st)
  softcut.loop_end(tr, en)
  if reel.track.time[tr] > en or reel.track.time[tr] < st then
    softcut.position(tr, st)
  end
end

reels.rec = function(tr, state)
  if state == true then
    recording = true
    if not reel.track.name[tr]:find("*") then
      reel.track.name[tr] = "*" .. reel.track.name[tr]
      reel.rec.start = reel.track.time[tr] 
      reels.update_params_list()
    end
    softcut.position(tr, reel.track.time[tr])
    softcut.rec(tr, 1)
  elseif state == false then
    local offset = 60 * (tr - 1)
    if (not reel.track.clip[tr] and recording) then
      reel.loop.s[tr] = reel.rec.start - offset 
      reel.loop.e[tr] = reel.rec.time - offset
      if reel.playback.reverse then
        reel.loop.s[tr] = reel.rec.time - offset 
        reel.loop.e[tr] = reel.rec.start - offset 
      end
      if reel.loop.e[tr] < reel.loop.s[tr] then
        reel.loop.e[tr] = 60 - offset
      end
      reels.set_loop(tr, reel.loop.s[tr], reel.loop.e[tr] )
      reel.track.clip[tr] = true
    end
    reel.track.clip[tr] = reel.track.clip[tr]
    recording = false
    reel.track.rec[tr] = false
    softcut.rec(tr, 0)
    reels.update_params_list()
  end
end

reels.rec_handler = function(tr)
  if reel.track.rec[tr] then
    if ((reels.threshold(reel.rec.threshold) and reel.rec.arm) and playing) then
      reel.rec.arm = false 
      reels.rec(tr, true)
    end
  else
  end
end

reels.mute = function(tr,state)
  if state == true then
    softcut.level(tr, 0)
    reel.track.mute[tr] = true
  elseif state == false then
    softcut.level(tr,reel.track.level[tr])
    reel.track.mute[tr] = false
  end
end

reels.play = function(state)
  if state == true then
    playing = true
    for i=1, total_tracks do
      softcut.play(i, 1)
      reel.track.play[i] = true
      softcut.poll_start_phase()
    end
  elseif state == false then
    playing = false
    for i=1, total_tracks do
    if reel.track.rec[i] then reels.rec(i, false) end
      softcut.play(i, 0)
      reel.track.play[i] = false
      softcut.poll_stop_phase()
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
  reel.track.name[tr] = "-"
  reel.track.clip[tr] = false
  reel.track.quality[tr] = 1
  reel.loop.s[tr] = 0
  reel.loop.e[tr] = 60
  reel.track.length[tr] = 60
  reels.set_loop(tr, 0, reel.loop.e[tr])
  softcut.buffer_clear_region(reel.s[tr], reel.track.length[tr])
  softcut.position(tr, reel.s[tr])
end

reels.new_reel = function()
  softcut.buffer_clear()
  settings_list.index = 1
  settings_amounts_list.index = 1
  reel.rec.time = 0
  playing = false
  for i=1, total_tracks do
    softcut.play(i, 0)
    reels.clear_track(i)
  end
  mounted = true
  reels.update_params_list()
end

reels.load_clip = function(path)
  if path ~= "cancel" then
    if path:find(".aif") or path:find(".wav") then
      local ch, len = audio.file_info(path)
      reel.paths[reel.track.selected] = path
      reel.track.clip[reel.track.selected] = true
      reel.track.name[reel.track.selected] = path:match("[^/]*$")
      if len / 48000 <= 60 then 
	      reel.track.length[reel.track.selected] = len / 48000
      else
	      reel.track.length[reel.track.selected] = 60
      end
      reel.e[reel.track.selected] = reel.s[reel.track.selected] + reel.track.length[reel.track.selected]
      if not path:find(reel.proj) then 
        reel.loop.e[reel.track.selected] = reel.track.length[reel.track.selected] 
        reel.track.time[reel.track.selected] = reel.s[reel.track.selected]
        reels.set_loop(reel.track.selected, reel.s[reel.track.selected], reel.loop.e[reel.track.selected])
      end
      softcut.buffer_read_mono(path, 0, reel.s[reel.track.selected], reel.track.length[reel.track.selected], 1, 1)
      print("read to " .. reel.s[reel.track.selected], reel.e[reel.track.selected])
      if not playing then softcut.play(reel.track.selected, 0) end
      --softcut.level(reel.track.selected, reel.track.level[reel.track.selected])
      reels.mute(reel.track.selected, false)
      mounted = true
      reels.update_rate(reel.track.selected)
      reels.update_params_list()
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
  softcut.poll_stop_phase()
  if path ~= "cancel" then
    if path:find(".reel") then
      reels.load_reel_data(path)
      mounted = true
      reel.track.selected = 1
      for i=1, total_tracks do
        if reel.track.name[i] ~= "-" then
          reels.load_clip(reel.paths[i])
          reel.track.selected = util.clamp(reel.track.selected + 1, 1, total_tracks)
          reels.set_loop(i, reel.loop.s[i], reel.loop.e[i])
          softcut.position(i, reel.loop.s[i])
          softcut.level(reel.track.selected, reel.track.level[reel.track.selected])
          reels.update_rate(i)
          softcut.play(i, 0)
        end
      end
    reel.track.selected = 1
    settings = true
    else
      print("not a reel file")
    end
  else
    mounted = false 
  end
  filesel = false
  reels.update_params_list()
  settings_list.index = 1
  settings_amounts_list.index = 1
end

reels.save_clip = function(txt)
  if txt then
    local c_start = reel.s[reel.track.selected]
    local c_len = reel.e[reel.track.selected]
    print("SAVE " .. _path.audio .. "reels/".. txt .. ".aif", c_start, c_len)
    softcut.buffer_write_mono(_path.audio .. "reels/"..txt..".aif", c_start, c_len, 1)
    reel.track.name[reel.track.selected] = txt
  else
    print("save cancel")
  end
  filesel = false
end

reels.save_project = function(txt)
  if txt then
    reel.proj = txt
    for i=1, total_tracks do
      if reel.track.name[i] ~= "-" then
        if reel.track.name[i]:find("*") then
          reel.track.name[i] = reel.track.name[i] == "*-" and (txt .. "-rec-" .. i .. ".aif") or reel.track.name[i]:sub(2,-1)
          local save_path = _path.audio .."reels/" .. reel.track.name[i]
          reel.paths[i] = save_path
          softcut.buffer_write_mono(_path.audio .."reels/" .. reel.track.name[i], reel.s[i], reel.e[i], 1)
          print("saving ".. i .. " clip at " .. save_path, reel.s[i],reel.e[i])
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
  audio.level_cut(1)
  audio.level_adc_cut(1)
  audio.level_eng_cut(0)
  mix:set_raw("monitor", rec_vol)
  params:add_option ( "tape_switch", "Reels:", { "background", "active" }, 1 )
  params:set_action( "tape_switch", function(x) if x == 1 then reels.active = false else reels.active = true end end )
  params:add_separator()
  params:add_control("IN", "Input level", controlspec.new(0, 1, 'lin', 0, 1, ""))
  params:set_action("IN", function(x) input_vol = x  audio.level_adc_cut(input_vol) end)
  params:add_control("ENG", "Engine level", controlspec.new(0, 1, 'lin', 0, 0, ""))
  params:set_action("ENG", function(x) engine_vol = x audio.level_eng_cut(engine_vol) end)
  params:add_separator()
  
  local vu_l, vu_r = poll.set("amp_in_l"), poll.set("amp_in_r")
  vu_l.time, vu_r.time = 1 / 30, 1 / 30
  vu_l.callback = function(val) in_l = val * 100 end
  vu_r.callback = function(val) in_r = val * 100 end
  vu_l:start()
  vu_r:start()

  
  softcut.event_phase(reels.phase)

  for i=1, 4 do
    softcut.level(i,1)
    softcut.level_input_cut(1, i, 1)
    softcut.level_input_cut(2, i, 1)
    softcut.pan(i, 0)
    softcut.play(i, 0)
    softcut.rate(i, 1)
    reel.s[i] = (i-1) * clip_length
    reel.e[i] = reel.s[i] + clip_length
    softcut.loop_start(i, reel.s[i])
    softcut.loop_end(i, reel.e[i])
    softcut.loop(i, 1)
    softcut.rec(i, 0)

    softcut.fade_time(i, 0.01)
    softcut.level_slew_time(i, 0)
    softcut.rate_slew_time(i, 0.5)

    softcut.rec_level(i, 1)
    softcut.pre_level(i, 1)
    softcut.position(i, reel.s[i])
    softcut.buffer(i,1)
    softcut.enable(i, 1)
    reels.update_rate(i)
    
   

    softcut.filter_br(i, 0)
    softcut.filter_dry(i, 1);
    softcut.filter_fc(i, 0);
    softcut.filter_lp(i, 0);
    softcut.filter_bp(i, 0);
    softcut.filter_rq(i, 0);
        
    softcut.phase_quant(i, 0.01)
    
    params:add_control(i.."vol", i.." Volume", controlspec.new(0, 1, 'lin', 0, 1, ""))
    params:set_action(i.."vol", function(x) reel.track.level[i]  = x softcut.level(i, reel.track.level[i]) reels.update_params_list() end)

    params:add_control(i.."pan", i.." Pan", controlspec.new(-1, 1, 'lin', 0, 0, ""))
    params:set_action(i.."pan", function(x) softcut.pan(i,x) end)
    
    params:add_separator()

  end
  

  -- reel graphics
  for i=1, 6 do
    ui.reel.right[i].orbit = math.fmod(i,2)~=0 and 6 or 15
    ui.reel.right[i].position = i <= 2 and 0 or i <= 4 and 2 or 4
    ui.reel.right[i].velocity = util.linlin(0, 1, 0.01, speed, 1)
    ui.reel.left[i].orbit = math.fmod(i,2)~=0 and 6 or 15
    ui.reel.left[i].position = i <= 2 and 3 or i <= 4 and 5 or 7.1
    ui.reel.left[i].velocity = util.linlin(0, 1, 0.01, speed * 3, 0.2)
  end
  reels.init_folders()
  reels.update_reel()
  -- settings
  settings_list = ui_lib.ScrollingList.new(75, 12, 1, {"New reel", "Load reel"})
  settings_list.num_visible = 4
  settings_list.num_above_selected = 0
  settings_list.active = false
  settings_amounts_list = ui_lib.ScrollingList.new(128, 12)
  settings_amounts_list.num_visible = 4
  settings_amounts_list.num_above_selected = 0
  settings_amounts_list.text_align = "right"
  settings_amounts_list.active = false
  --
  reels.blink_metro = metro.init{event = function(stage) blink = not blink end, time = 1 / 2}
  reels.blink_metro:start()
  reels.update = metro.init{event = function(stage) reels.rec_handler(reel.track.selected) if (not norns.menu.status() and reels.active) then reels:redraw() reels.animation() else end end, time = 1 / 60}
  reels.update:start()
  --
  if reels.active then params:set("tape_switch", 2) else params:set("tape_switch", 1) end
end

function reels.update_reel()
  for i=1, 6 do
    ui.reel.left[i].velocity = util.linlin(0, 1, 0.01, (speed / 1.9) / (reel.track.quality[1] / 2), 0.15)
    ui.reel.left[i].position = (ui.reel.left[i].position - ui.reel.left[i].velocity) % (math.pi * 2)
    ui.reel.left[i].x = 30 + ui.reel.left[i].orbit * math.cos(ui.reel.left[i].position)
    ui.reel.left[i].y = 25 + ui.reel.left[i].orbit * math.sin(ui.reel.left[i].position)
    ui.reel.right[i].velocity = util.linlin(0, 1, 0.01, (speed / 1.5) / (reel.track.quality[1] / 2), 0.15)
    ui.reel.right[i].position = (ui.reel.right[i].position - ui.reel.right[i].velocity) % (math.pi * 2)
    ui.reel.right[i].x = 95 + ui.reel.right[i].orbit * math.cos(ui.reel.right[i].position)
    ui.reel.right[i].y = 25 + ui.reel.right[i].orbit * math.sin(ui.reel.right[i].position)
  end
end

reels.animation = function()
  if playing then
    reels.update_reel()
    if ui.playhead.height > 31 then
      ui.playhead.height = ui.playhead.height - 1
    elseif ui.playhead.height < 32 and ui.playhead.height > 25 then
      ui.playhead.height = ui.playhead.height - 1
    end
    if ui.tape.tension > 20 and ui.playhead.height < 32  then
      ui.tape.tension = ui.tape.tension - 1
      ui.playhead.brightness = util.clamp(ui.playhead.brightness + 1, 0, 2)
    end
  elseif not playing then
    if ui.playhead.height < 35 then
      ui.playhead.height = ui.playhead.height + 1
    elseif ui.playhead.height > 25 then
      end
    if ui.tape.tension < 30 then
      ui.tape.tension = ui.tape.tension + 1
      ui.playhead.brightness = util.clamp(ui.playhead.brightness - 1, 0, 5)
    end
  end
  if settings then
    ui.reel.pos.x = util.clamp(ui.reel.pos.x - 5, -27, 35)
  elseif not setting then
    ui.reel.pos.x = util.clamp(ui.reel.pos.x + 5, -27, 35)
    
  end
  local sel = reel.track.selected
  -- cursor position
  if ui.cursor.x ~= ui.cursor.bind[sel] then
    if ui.cursor.x <= ui.cursor.bind[sel] then
      ui.cursor.x = util.clamp(ui.cursor.x + 3, ui.cursor.bind[sel] - 20, ui.cursor.bind[sel])
    elseif ui.cursor.x >= ui.cursor.bind[sel] then
      ui.cursor.x = util.clamp(ui.cursor.x - 3, ui.cursor.bind[sel], ui.cursor.bind[sel] + 20)
    end
  end
end

reels.draw_reel = function(x, y)
  local flutter = ui.tape.flutter
  local right = ui.reel.right
  local left = ui.reel.left
  
  local l = util.round(speed * 10)
  if l < 0 then
    l = math.abs(l) + 4
  elseif l >= 4 then
    l = 4
  elseif l == 0 then
    l = reel.playback.reverse and 5 or 1
  end
  screen.level(2)
  screen.line_width(1.9)
  local pos = { 1, 3, 5}
  for i = 1, 3 do
    screen.move((x + right[pos[i]].x) - 30, (y + right[pos[i]].y) - 25)
    screen.line((x + right[pos[i] + 1].x) - 30, (y + right[pos[i] + 1].y) - 25)
    screen.stroke()
    screen.move((x + left[pos[i]].x) - 30, (y + left[pos[i]].y) - 25)
    screen.line((x + left[pos[i] + 1].x) - 30, (y + left[pos[i] + 1].y) - 25)
    screen.stroke()
  end
  screen.line_width(1)
  -- speed icons >>>>
  screen.move(x + 32, y + 2)
  screen.level(speed == 0 and 1 or 6)
  screen.text_center(ui.speed[util.clamp(l, 1, 8)])
  screen.stroke()
  --
  screen.level(1)
  screen.circle(x + 5, y + 28, 2)
  screen.fill()
  screen.circle(x + 55, y + 28, 2)
  screen.fill()
  screen.level(0)
  screen.circle(x + 5, y + 28, 1)
  screen.circle(x + 55, y + 28, 1)
  screen.fill()
  --right reel
  screen.level(1)
  screen.circle(x + 65, y, 1)
  screen.stroke()
  screen.circle(x + 65, y, 20)
  screen.stroke()
  screen.circle(x + 65, y, 3)
  screen.stroke()
  -- left
  screen.circle(x, y, 20)
  screen.stroke()
  screen.circle(x, y, 1)
  screen.stroke()
  screen.circle(x, y, 3)
  screen.stroke()
  -- tape
  if mounted then
    local x1, x2, x3
    screen.level(6)
    if not flutter.on or (flutter.on and not playing) then
      x1 = x + 65
      x2 = x + 65
      x3 = x + 70
    elseif (flutter.on and playing) then
      x1 =  x + 65 - math.random(0, 5)
      x2 =  x + 65 - math.random(0, 10)
      x3 =  x + 70 - math.random(0, 5)
    end
    screen.move(x, y - 17)
    screen.curve(x1, y - 12, x2, y - 12, x3, y - 12)
    screen.stroke()
    screen.level(6)
    screen.circle(x, y, 18)
    screen.stroke()
    screen.level(3)
    screen.circle(x, y, 17)
    screen.stroke()
    screen.level(6)
    screen.circle(x + 65, y, 14)
    screen.stroke()
    screen.level(3)
    screen.circle(x + 65, y, 13)
    screen.stroke()
    screen.level(6)
--[[    if not flutter.on or (flutter.on and not playing) then
      x1 = x + 75
      x2 = x + 65
      x3 = x + 55
    elseif (flutter.on and playing) then
      x1 =  x + 75 + math.random(0, 1)-- (flutter.amount * math.random(5) / 40)
      x2 =  x + 65 +  math.random(0, 1)
      x3 =  x + 55 + math.random(0, 1) -- (flutter.amount * math.random(5) / 40)
    end

    screen.curve(x1, y + 10, x2, y + 20, x3, y + 30)]]
    screen.move(x + 75, y + 10)
    screen.line(x + 55, y + 30)
    screen.stroke()
    screen.move(x - 9, y + 16)
    screen.line(x + 5, y + 30)
    screen.curve(x + 5, y + 30, x + 5, y + 30, x + 5, y + 30)
    screen.stroke()
    screen.move(x + 5, y + 30)
    screen.curve(x + 40, y + ui.tape.tension, x + 25, y + ui.tape.tension, x + 56, y + 30)
    screen.stroke()
  end
  -- playhead
  screen.level(ui.playhead.brightness)
  screen.circle(x + 32, y + ui.playhead.height + 1, 3)
  screen.rect(x + 28, y + ui.playhead.height, 8, 4)
  screen.fill()
end

reels.draw_bars = function(x, y)
  local tr = reel.track
  for i=1, total_tracks do
    screen.level(tr.mute[i] and 1 or tr.rec[i] and 9 or 3)
    screen.rect((x * i *2) - 24, y, 26, 3)
    screen.stroke()
    screen.rect((x * i *2) - 24, y, 25, 3)
    screen.fill()
    screen.level(0)
    local s = (reel.loop.s[i] - 1) / tr.length[i] * 25
    screen.rect(((x * i *2) - 24) + s, 61, ((reel.loop.e[i] + 1) / tr.length[i] * 25) - s, 2)
    screen.fill()
    screen.level(15)
    pos = tr.time[i] == 0 and 1 or tr.time[i] - (60 * i) + 60
    screen.move(((x * i * 2) - 24) + ((pos / (tr.length[i]) * 25)), 61)
    screen.line_rel(0, 2)
    screen.stroke()
  end
end



reels.draw_cursor = function(x, y)
  screen.level(9)
  screen.move(x - 3, y - 3)
  screen.line(x,y)
  screen.line_rel(3, -3)
  screen.stroke()
end


reels.draw_rec_vol_slider = function(x, y)
  
  screen.level(1)
  screen.move(x - 30, y - 17)
  screen.line(x - 30, y + 29)
  screen.stroke()
  screen.level(3)
  local l = util.clamp((in_l or 0), 0, rec_vol * 44)
  screen.rect(x - 31.5 ,y + 29,3,-l)
  screen.line_rel(3, 0)
  screen.fill()
  screen.level(4)
  local r = util.clamp((in_r or 0), 0, rec_vol * 44)
  screen.rect(x - 31.5, y + 29, 3, -r)
  screen.line_rel(3, 0)
  screen.fill()
  screen.level(6)
  screen.rect(x - 33, 48 - rec_vol / 3 * 132, 5, 2)
  screen.fill()
  screen.level(5)
  screen.rect(x - 32, 49 - reel.rec.threshold / 15 * 10, 3, 1)
  screen.fill()
end

function reels:key(n, z)
  local sel = reel.track.selected
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
        if not reel.track.play[sel] then
            reels.play(true)
        elseif reel.track.play[sel] then
          if reel.track.rec[sel] then
            reel.track.rec[sel] = false
            reel.rec.arm = false
            reels.rec(sel, false)
          else
            reels.play(false)
          end
        elseif filesel then
          filesel = false
        end
      elseif n == 3 then
        if settings == false and mounted then
          if not reel.track.rec[sel] then
            reel.track.rec[sel] = true -- rec work flag
            reel.rec.arm = true
            reels.mute(sel, false)
          elseif reel.track.rec[sel] then
            reel.track.rec[sel] = false
            reel.rec.arm = false
            reels.rec(sel,false)
          end
        elseif settings then
          if settings_list.index == 1 then
            if mounted then
              if reel.track.name[sel] == "-" then
                filesel = true
                fileselect.enter(_path.audio, reels.load_clip)
              elseif reel.track.clip[sel] then
                reels.mute(sel, not reel.track.mute[sel])
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
            reels.clear_track(sel)
          elseif settings_list.index == 11 then -- load clip
            filesel = true
            fileselect.enter(_path.audio, reels.load_clip)
          elseif settings_list.index == 12 then -- save
            filesel = true
            textentry.enter(reels.save_clip, reel.track.name[sel] == "-*" and "reel-" .. (math.random(9000)+1000) or (reel.track.name[sel]:find("*") and reel.track.name[sel]:match("[^.]*")):sub(2,-1))
          elseif settings_list.index == 14 then -- clear reel
            reels.new_reel()
          elseif settings_list.index == 15 then -- load 
            filesel = true
              fileselect.enter(_path.data.."reels/", reels.load_reel)
          elseif settings_list.index == 16 then -- save 
            filesel = true
            textentry.enter(reels.save_project, reel.proj)
          elseif (settings_list.index <= 9 or settings_list.index >= 2) then
            if not reel.track.rec[sel] then
              reel.track.rec[sel] = true -- rec work flag
              reel.rec.arm = true
              reels.mute(sel, false)
            elseif reel.track.rec[sel] then
              reel.track.rec[sel] = false
              reel.rec.arm = false
              reels.rec(sel,false)
            end
          end
          reels.update_params_list()
        end
      end
    end
  else
  end
end

function reels:enc(n, d)
  local sel = reel.track.selected
  if reels.active then
    norns.encoders.set_sens(1,7)
    norns.encoders.set_sens(2, (settings and 6 or 1))
    norns.encoders.set_sens(3, (settings and (settings_list.index == (1 or 2 or 7 or 8))) and 1 or (not settings and (speed < -0.01 or speed > 0.01)) and 1 or 3)
    norns.encoders.set_accel(1, false)
    norns.encoders.set_accel(2, false)
    norns.encoders.set_accel(3,(settings and settings_list.index < 5) and true or false)
    if n == 1 then
      if (not recording and not reel.track.rec[sel]) then 
        reel.track.selected = util.clamp(sel + d, 1, total_tracks) 
      end
      if mounted then
        reels.update_params_list()
      end
      if ui.cursor.x ~= ui.cursor.bind[sel] then
        ui.cursor.x = (ui.cursor.x + d)
      end
    elseif n == 2 then
      if not settings then
        rec_vol = util.clamp(rec_vol + d / 100, 0, 1)
        mix:set_raw("monitor", rec_vol)
        audio.level_adc_cut(rec_vol)
        softcut.rec_level(sel, rec_vol)
      elseif settings then
        settings_list:set_index_delta(util.clamp(d, -1, 1), false)
        settings_amounts_list:set_index(settings_list.index)
      end
    elseif n == 3 then
      if not settings then
        speed = util.clamp( util.round(( speed + d /  100 ), 0.001 ), -0.8, 0.8 )
        if speed < 0 then
          reel.playback.reverse = true
        elseif speed >= 0 then
          reel.playback.reverse = false
        end
        for i=1, total_tracks do
          reels.update_rate(i)
        end
      elseif (settings and mounted) then
        if settings_list.index == 1 and reel.track.mute[sel] == false then
          reel.track.level[sel] = util.clamp(reel.track.level[sel] + d / 100, 0, 1)
          softcut.level(sel, reel.track.level[sel])
          reels.update_params_list()
        elseif settings_list.index == 2 then
          local loop_len = reel.loop.e[sel] - reel.loop.s[sel]
          reel.loop.s[sel] = util.clamp(reel.loop.s[sel] + d / 10, 0, 59)
          reel.loop.e[sel] = util.clamp(reel.loop.s[sel] + loop_len, reel.loop.s[sel], reel.track.length[sel])
          reels.set_loop(sel, reel.loop.s[sel], reel.loop.e[sel])
        elseif settings_list.index == 3 then
          reel.loop.s[sel] = util.clamp(reel.loop.s[sel] + d / 10, 0, reel.loop.e[sel])
          reels.set_loop(sel, reel.loop.s[sel],reel.loop.e[sel])
        elseif settings_list.index == 4 then
          reel.loop.e[sel] = util.clamp(reel.loop.e[sel] + d / 10, reel.loop.s[sel], util.round(reel.track.length[sel],0.1))
          reels.set_loop(sel, reel.loop.s[sel],reel.loop.e[sel])
        elseif settings_list.index == 6 then
          reel.track.quality[sel] = util.clamp(reel.track.quality[sel] + d, 1, 24)
          reels.update_rate(sel)
        elseif settings_list.index == 7 then
          ui.tape.flutter.on  = not ui.tape.flutter.on
        elseif settings_list.index == 8 then
          reel.rec.threshold = util.clamp(reel.rec.threshold + d, 0, 60)
          reels.update_rate(sel)
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
      reels.draw_reel(ui.reel.pos.x, ui.reel.pos.y)
      reels.draw_cursor(ui.cursor.x, ui.cursor.y)
      reels.draw_bars(15, 61)
      if recording then
        screen.level(blink and 5 or 15)
        screen.circle(ui.reel.pos.x + 80, ui.reel.pos.y + 30, 4)
        screen.fill()
        screen.stroke()
      end
      if not settings then
        reels.draw_rec_vol_slider(ui.reel.pos.x, ui.reel.pos.y)
      end
      if settings and ui.reel.pos.x < -15 then
        if mounted then
          screen.level(6)
          screen.move(128, 5)
          screen.text_right(reel.track.name[reel.track.selected]:match("[^.]*"))
          screen.stroke()
          settings_list:redraw()
          settings_amounts_list:redraw()
        else
          screen.level(6)
          settings_list:redraw()
        end
      end
    end
  end
  screen.update()
end

return reels 
