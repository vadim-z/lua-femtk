local R = require('FRD/read_frd')
local M = require('FRD/frd_exo_map')

local wr1 = M.Exo2_writer({filename = 'es.exo'})
R.read_frd('xtra/unisphere_ES.frd', wr1)
local wr2 = M.Exo2_writer({filename = 'seg.exo'})
R.read_frd('xtra/segment.frd.ref', wr2)
local wr3 = M.Exo2_writer({filename = 'gap2.exo'})
R.read_frd('xtra/gap2.frd.ref', wr3)
