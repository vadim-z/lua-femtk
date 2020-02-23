local R = require('mesh/read_msh2')
local W = require('mesh/old/write_ccx')
local T = require('mesh/old/ccx_tools')

if #arg < 3 then
   error('Not enough arguments!')
end

local M = R.read_msh2(arg[1])

local set_out = {
   vol_n = 'voln',
   surf_n = 'surfn',
   vol_el = 'volel',
   fmt = 'netCDF',
   filename = 'sets.nc',
}

local f = assert(io.open(arg[2], 'w'))
W.write_ccx_mesh(f, M)

-- boundary conditions
local b_ext = {1,2,3,4,5,6}
f:write('*NSET, NSET=NBOUEXT\n')
for k = 1, #b_ext do
   f:write(('NBOU%d,\n'):format(b_ext[k]))
end
f:write([[
*BOUNDARY
NBOUEXT,1,3
]])

local mode = math.tointeger(arg[3])

if mode == 123 then
   for ke = 1, 3 do
      local einf = { 0., 0., 0., 0., 0., 0. }
      einf[ke] = 1.0
      T.calc_boundary_disp(M, einf, b_ext)
      local amp = string.format('AE%u', ke)
      W.write_ccx_model_boundary(f, M, {ke}, amp)
   end
elseif mode >= 4 and mode <= 6 then
   local einf = { 0., 0., 0., 0., 0., 0. }
   einf[mode] = 1.0
   T.calc_boundary_disp(M, einf, {1,2,3,4,5,6})
   local amp = string.format('AE%u', mode)
   W.write_ccx_model_boundary(f, M, false, amp)
else
   error('Invalid mode')
end

W.write_ccx_tables(M, set_out)
f:close()
