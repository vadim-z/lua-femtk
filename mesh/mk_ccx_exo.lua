local R = require('mesh/read_msh2')
local W = require('mesh/write_ccx')
local U = require('mesh/utils')

if #arg < 3 then
   error('Not enough arguments!')
end

local M = R.read_msh2(arg[1])

U.write_mesh_exo2(M, arg[3],
                  { title = 'cnv: ' .. arg[1],
                    ids = { nsets = 100, ssets = 500 },
                    fp_type = 'float' })

local f = assert(io.open(arg[2], 'w'))
W.write_ccx_mesh(f, M)

f:close()
