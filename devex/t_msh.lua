local R = require('mesh/read_msh2')
local U = require('mesh/utils')

if #arg < 2 then
   error('Not enough arguments!')
end

local M = R.read_msh2(arg[1])
U.write_mesh_exo2(M, arg[2], 'converted',
                  { surfn = 100, voln = 300 })
