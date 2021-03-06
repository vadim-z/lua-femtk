local read_frd = require('FRD/read_frd')
local frd_exo_map = require('FRD/frd_exo_map')

local usage = [[

Usage: lua5.3 frd2exo.lua [options] frd_file exo_file

Options:
-1: use netCDF-1 format (default)
-2: use netCDF-2 format
-f: use float (real*4) type instead of default
-d: use double (real*8) type instead of default
-x exo2_file : merge node and side sets from exo2_file
]]

local ftype, fnames, exo2_sets_filename, fmt = nil, {}, nil, nil, nil

local karg = 1
while karg <= #arg do
   local a = arg[karg]
   if a == '-1' then
      fmt = 1
   elseif a == '-2' then
      fmt = 2
   elseif a == '-f' then
      ftype = 'float'
   elseif a == '-d' then
      ftype = 'double'
   elseif a == '-x' then
      assert(karg < #arg, 'Too few arguments')
      karg = karg + 1
      exo2_sets_filename = arg[karg]
   else
      table.insert(fnames, a)
   end
   karg = karg + 1
end

if #fnames < 2 then
   io.stderr:write(usage)
   os.exit(1)
end

local wr = frd_exo_map.Exo2_writer({
      filename = fnames[2],
      fp_type = ftype,
      exo2_sets_filename = exo2_sets_filename,
      fmt = fmt,
})
read_frd.read_frd(fnames[1], wr)
