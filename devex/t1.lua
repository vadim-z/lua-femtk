local NC = require('netCDF')

local def = {
   fmt = 1,
   dims = {
      time_step = 0,
      num_nodes = 9,
   },
   atts = {
      atr1 = {2, type = NC.NC.SHORT},
      attr2 = 'bzx',
      a3 = {1.5, type = NC.NC.FLOAT},
   },
   vars = {
      kkk = { 
         type = NC.NC.BYTE,
         atts = {
            id = { 'a', 'q', 'u', type = NC.NC.CHAR },
         },
      },
      ids = {
         type = NC.NC.FLOAT,
         atts = {
            x = 'qwe',
            y = { 1, 2, type = NC.NC.BYTE}
         },
         dims = { 'num_nodes' },
      },
      idsx = {
         type = NC.NC.SHORT,
         dims = { 'num_nodes' },
      },
      ts3 = {
         type = NC.NC.BYTE,
         dims = { 'time_step','num_nodes' },
         atts = {},
      },
   },
}

local NCf = NC.NCFile()
NCf:create('zzz.nc', def)
NCf:close()
