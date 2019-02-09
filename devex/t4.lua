local NC = require('netCDF/writer')

local def = {
   fmt = 2,
   hdr_size_min = 1024,
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
      ts1 = {
         type = NC.NC.CHAR,
         dims = { 'time_step', 'three' },
      },
   },
}

local NCf = NC.NCWriter()
NCf:create('zzz2.nc', def)
NCf:write_fixed_vars({
      kkk = 43,
      tx = 'zxcvb',
      tx_3 = {'A', 'C', 'Q', array = true },
      ids = {1,2,3,4,5,6,7,8,9},
      idsx = {-1,-2,-3,-4,-5,-6,-7,-8,-9},
})
NCf:write_record({
      ts3 = {11,12,13,14,15,16,17,18,19},
      ts1 = 'foo',
})
NCf:write_record({
      ts3 = {111,112,113,114,115,116,117,118,119},
      ts1 = 'bar',
})
NCf:close()
