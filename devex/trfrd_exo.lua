local R = require('read_frd')
local M = require('frd_exo_map')

local wr = M.Exo2_writer('es.exo')
R.read_frd('xtra/unisphere_ES.frd', wr)
local wr = M.Exo2_writer('seg.exo')
R.read_frd('xtra/segment.frd.ref', wr)
