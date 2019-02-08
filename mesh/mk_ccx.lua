require('2de')
local R = require('read_mesh_netgen')
local W = require('write_ccx')
local T = require('ccx_tools')

if #arg < 2 then
   error('Not enough arguments!')
end

local M = R.read_mesh_netgen(arg[1])
R.make_sets(M)

T.calc_boundary_disp(M, {0.,0.,2.e-3,0.,0.,0.}, {1,2,3,4,5,6})

W.write_mesh_ccx_tets(arg[2], M,
                      { vol_n = 'voln',
                        surf_n = 'surfn',
                        vol_el = 'volel',
                      })
