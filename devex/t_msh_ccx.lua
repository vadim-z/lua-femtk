local R = require('mesh/old/read_msh2')
local W = require('mesh/old/write_ccx')

if #arg < 2 then
   error('Not enough arguments!')
end

local M = R.read_msh2(arg[1])

local fmt = 'netCDF'

local set_out
if fmt == 'txt' then
   set_out = {
      vol_n = 'voln',
      surf_n = 'surfn',
      vol_el = 'volel',
      fmt = 'txt',
   }
elseif fmt == 'netCDF' then
   set_out = {
      vol_n = 'voln',
      surf_n = 'surfn',
      vol_el = 'volel',
      fmt = 'netCDF',
      filename = 'sets.nc',
   }
end

local f = assert(io.open(arg[2], 'w'))
W.write_ccx_mesh(f, M)
W.write_ccx_tables(M, set_out)
f:close()
