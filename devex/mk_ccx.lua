-- MinGW: notice https://gist.github.com/vadim-z/c6a232c5654793017e538bd723de1168
-- require('2de')
local R = require('mesh/read_mesh_netgen')
local W = require('mesh/write_ccx')
local T = require('mesh/ccx_tools')

if #arg < 2 then
   error('Not enough arguments!')
end

local M = R.read_mesh_netgen(arg[1])
R.make_sets(M)

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

W.write_mesh_ccx_tets(arg[2], M, set_out)

