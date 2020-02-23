local R = require('mesh/read_mesh_netgen')
local W = require('mesh/old/write_ccx')
local T = require('mesh/old/ccx_tools')

if #arg < 2 then
   error('Not enough arguments!')
end

local M = R.read_mesh_netgen_tets(arg[1])

T.calc_boundary_disp(M, {0.,0.,2.e-3,0.,0.,0.}, {1,2,3,4,5,6})


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
W.write_ccx_model_boundary(f, M)
W.write_ccx_tables(M, set_out)
f:close()
