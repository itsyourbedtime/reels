-- reels.
--
-- @its_your_bedtime
-- llllllll.co/t/reels
--
--
-- hold btn 1 for settings
-- btn 2 play / pause
-- btn 3 rec on/off
--
-- enc 1 - switch track
-- enc 2 - change speed
-- enc 3 - overdub level

local reels = include('reels/lib/libreels')

function init()
  reels.active = true 
  reels.init()
end

function key(n,z)
  reels:key(n,z)
end

function enc(n,d)
  reels:enc(n,d)
end

function redraw()
  reels:redraw()
end