local R = require('mesh/old/read_msh2')
local U = require('mesh/old/utils')
local gap = require('spec/mkgap')

local M

M = R.read_msh2('xtra/fclad_all.msh')
U.compress_mesh(M)
gap.mkgap(M, {1,3, surf_id = 98}, {2,4, surf_id = 99}, 1.1)
U.write_mesh_exo2(M, 'o.exo', {
                     title = 'converted',
                     ids = { surfn = 100, voln = 300 }})

local f = io.open('tw.txt', 'w')
for k, v in ipairs(M.twin1) do
   f:write(string.format('%d %d %d\n', k, v, M.twin2[k]))
end
f:close()

M = R.read_msh2('xtra/fclad_phys.msh')
U.compress_mesh(M)
gap.mkgap(M, {1, surf_id = 5}, {2, surf_id = 11}, 1.1)
U.write_mesh_exo2(M, 'ophys.exo', {
                     title = 'converted',
                     ids = { surfn = 100, voln = 300 }})

f = io.open('twphys.txt', 'w')
for k, v in ipairs(M.twin1) do
   f:write(string.format('%d %d %d\n', k, v, M.twin2[k]))
end
f:close()
