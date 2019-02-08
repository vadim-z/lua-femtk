local read_frd = require('FRD/read_frd')
local frd_exo_map = require('FRD/frd_exo_map')

local usage = [[

Usage: lua5.3 [-f|-d] frd2exo.lua frd_file exo_file

-f: use float (real*4) type instead of default
-d: use double (real*8) type instead of default

]]

local ftype, fnames = nil, {}

for _, a in ipairs(arg) do
   if a == '-f' then
      ftype = 'float'
   elseif a == '-d' then
      ftype = 'double'
   else
      table.insert(fnames, a)
   end
end

if #fnames < 2 then
   io.stderr:write(usage)
   os.exit(1)
end

local wr = frd_exo_map.Exo2_writer(fnames[2], ftype)
read_frd.read_frd(fnames[1], wr)
