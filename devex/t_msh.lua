local R = require('mesh/read_msh2')
local U = require('mesh/utils')
local EX2 = require('netCDF/exo2s')

if #arg < 2 then
   error('Not enough arguments!')
end

local M = R.read_msh2(arg[1])
U.compress_mesh(M)

local f = EX2.Exo2File()
f:init(arg[2])
f:define_title('converted')
f:define_nodes(U.nodes_to_ex2(M.nodes))
f:define_els(M.elems)
f:define_nodesets(U.exo2_nsets(M, { surfn = 100, voln = 200 }),
                  { 'SURF', 'VOL' }, true )
f:close()
