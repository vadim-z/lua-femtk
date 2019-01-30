local NC = require('netCDF')

local def = {
   fmt = 1,
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
      {
         ordered = true,
         {
            name = 'kkk',
            type = NC.NC.BYTE,
            atts = {
               id = { 'a', 'q', 'u', type = NC.NC.CHAR },
            },
         },
         {
            name = 'ids',
            type = NC.NC.FLOAT,
            atts = {
               x = 'qwe',
               y = { 1, 2, type = NC.NC.BYTE}
            },
            dims = { 'num_nodes' },
         },
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
      ts1 = {
         type = NC.NC.CHAR,
         dims = { 'time_step', 'three' },
      },
   },
}

local NCf = NC.NCFile()
NCf:create('zzz.nc', def)
NCf:write_var('kkk', {41})
NCf:write_var('kkk', 43)
NCf:write_var('tx', {'_@'})
NCf:write_var('tx', 'zxcvb')
NCf:write_var('tx_3', {'A', 'C', 'Q', array = true })
NCf:write_var('ids', {1,2,3,4,5,6,7,8,9})
NCf:write_var('idsx', {-1,-2,-3,-4,-5,-6,-7,-8,-9})
NCf:write_var('ts3', {11,12,13,14,15,16,17,18,19}, 2)
NCf:write_var('ts1', 'jkl', 1)
NCf:close()
