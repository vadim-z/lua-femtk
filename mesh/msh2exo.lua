local R = require('mesh/read_msh2')
local U = require('mesh/utils')

if #arg < 2 then
   error('Not enough arguments!')
end

local M = R.read_msh2(arg[1])
U.write_mesh_exo2(M, arg[2],
                  { title = 'converted',
                    ids = { nsets = 100, ssets = 500 },
                    fp_type = arg[3] })
