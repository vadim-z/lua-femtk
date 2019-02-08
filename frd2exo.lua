local read_frd = require('read_frd')
local frd_exo_map = require('frd_exo_map')

if #arg < 2 then
   io.stderr:write('Usage: lua5.3 frd2exo.lua frd_file exo_file\n')
   os.exit(1)
end

local wr = frd_exo_map.Exo2_writer(arg[2])
read_frd.read_frd(arg[1], wr)
