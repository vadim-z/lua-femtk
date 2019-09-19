local read_frd = require('FRD/read_frd')
local frd_exo_map = require('FRD/frd_exo_map')

local usage = [[

Usage: lua5.3 frd2exo.lua [options] frd_file exo_file

Options:
-1: use netCDF-1 format (default)
-2: use netCDF-2 format
-f: use float (real*4) type instead of default
-d: use double (real*8) type instead of default
-sets set_file : use set_file to read node sets
-surfn id : put surface node sets with ids starting from id
-voln id : put volume node sets with ids starting from id
]]

local ftype, fnames, sets, fmt = nil, {}, nil, nil

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
   elseif a == '-sets' then
      assert(karg < #arg, 'Too few arguments')
      karg = karg + 1
      sets = { filename = arg[karg] }
   elseif a == '-surfn' or a == '-voln' then
      assert(karg < #arg, 'Too few arguments')
      assert(sets, 'Sets file undefined')
      karg = karg + 1
      sets[a:sub(2)] = math.tointeger(arg[karg])
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
      sets = sets,
      fmt = fmt,
})
read_frd.read_frd(fnames[1], wr)
