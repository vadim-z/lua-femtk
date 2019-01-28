local NC = require('netCDF')

local def = {
   fmt = 1,
   -- stream = true, -- HIGHLY EXPRERIMENTAL
   dims = {
      time_step = 0,
      num_nodes = 9,
      len = 20,
      three = 3,
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
      tx = {
         type = NC.NC.CHAR,
         dims = { 'len' },
      },
      tx_3 = {
         type = NC.NC.CHAR,
         dims = { 'three' },
      },
   },
}

local NCf = NC.NCFile()
NCf:create('zzz2.nc', def)
NCf:write_vars({
      kkk = 43,
      tx = 'zxcvb',
      tx_3 = {'A', 'C', 'Q', array = true },
      ids = {1,2,3,4,5,6,7,8,9},
      idsx = {-1,-2,-3,-4,-5,-6,-7,-8,-9},
})
NCf:close()
