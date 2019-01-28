local NC = require('netCDF')

local def = {
   fmt = 1,
   dims = {
      { name = 'time_step', size = 0 },
      { name = 'num_nodes', size = 9},
   },
   atts = {
      atr1 = {2, type = NC.NC.SHORT},
      attr2 = 'bzx',
      a3 = {1.5, type = NC.NC.FLOAT},
   }
}

local NCf = NC.NCFile()
NCf:create('zzz.nc', def)
NCf:close()
