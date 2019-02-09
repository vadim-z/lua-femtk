local reader = require('netCDF/reader')
local writer = require('netCDF/writer')

-- https://gist.github.com/stuby/5445834
local function rPrint(s, l, i) -- recursive Print (structure, limit, indent)
	l = (l) or 100; i = i or "";	-- default item limit, indent string
	if (l<1) then print "ERROR: Item limit reached."; return l-1 end;
	local ts = type(s);
	if (ts ~= "table") then print (i,ts,s); return l-1 end
	print (i,ts);           -- print "table"
	for k,v in pairs(s) do  -- print "[KEY] VALUE"
		l = rPrint(v, l, i.."\t["..tostring(k).."]");
		if (l < 0) then break end
	end
	return l
end

-- ============= WRITE =================
local WNC = writer.NC
local wr = writer.NCWriter()

local def = {
   fmt = 2,
   hdr_size_min = 1024,
   dims = {
      time_step = 0,
      num_nodes = 9,
      len = 20,
      three = 3,
   },
   atts = {
      atr1 = {2, type = WNC.SHORT},
      attr2 = 'bzx',
      a3 = {1.5, type = WNC.FLOAT},
   },
   vars = {
      kkk = {
         type = WNC.BYTE,
         atts = {
            id = { 'a', 'q', 'u', type = WNC.CHAR },
         },
      },
      ids = {
         type = WNC.FLOAT,
         atts = {
            x = 'qwe',
            y = { 1, 2, type = WNC.BYTE}
         },
         dims = { 'num_nodes' },
      },
      idsx = {
         type = WNC.SHORT,
         dims = { 'num_nodes' },
      },
      ts3 = {
         type = WNC.BYTE,
         dims = { 'time_step','num_nodes' },
         atts = {},
      },
      tx = {
         type = WNC.CHAR,
         dims = { 'len' },
      },
      tx_3 = {
         type = WNC.CHAR,
         dims = { 'three' },
      },
      ts1 = {
         type = WNC.CHAR,
         dims = { 'time_step', 'three' },
      },
      r2sh = {
         type = WNC.SHORT,
         dims = { 'three', 'num_nodes' }
      },
      r2str = {
         type = WNC.CHAR,
         dims = { 'three', 'len' }
      }
   },
}

wr:create('zzz2.nc', def)
wr:write_fixed_vars({
      kkk = 43,
      tx = 'zxcvb',
      tx_3 = {'A', 'C', 'Q', array = true },
      ids = {1,2,3,4,5,6,7,8,9},
      idsx = {-1,-2,-3,-4,-5,-6,-7,-8,-9},
      r2sh = { 11,12,13,14,15,16,17,18,19,
               21,22,23,24,25,26,27,28,29,
               31,32,33,34,35,36,37,38,39 },
      r2str = {
         'quuz', 'toor', 'muh'
      }
})
wr:write_record({
      ts3 = {11,12,13,14,15,16,17,18,19},
      ts1 = 'foo',
})
wr:write_record({
      ts3 = {111,112,113,114,115,116,117,118,119},
      ts1 = 'bar',
})
wr:close()

local def2 = {
-- fmt = 1,
   dims = {
      time_step = 0,
      num_nodes = 9,
      len = 20,
      three = 3,
      xdim = 2,
   },
   atts = {
      atr1 = {2, type = WNC.SHORT},
      attr2 = 'bzx',
      a3 = {1.5, type = WNC.FLOAT},
   },
   vars = {
      kkk = {
         type = WNC.BYTE,
         atts = {
            id = { 'a', 'q', 'u', type = WNC.CHAR },
         },
      },
      ids = {
         type = WNC.FLOAT,
         atts = {
            x = 'qwe',
            y = { 1, 2, type = WNC.BYTE}
         },
         dims = { 'num_nodes' },
      },
      idsx = {
         type = WNC.SHORT,
         dims = { 'num_nodes' },
      },
      ts3 = {
         type = WNC.BYTE,
         dims = { 'time_step','num_nodes' },
         atts = {},
      },
      tx = {
         type = WNC.CHAR,
         dims = { 'len' },
      },
      tx_3 = {
         type = WNC.CHAR,
         dims = { 'three' },
      },
      ts1 = {
         type = WNC.CHAR,
         dims = { 'time_step', 'three' },
      },
      tx4 = {
         type = WNC.CHAR,
         dims = { 'xdim', 'num_nodes' },
      },
      ss = {
         type = WNC.CHAR,
         dims = { 'time_step' }
      },
   },
}

wr:create('zzz.nc', def2)
wr:write_var('kkk', {41})
wr:write_var('kkk', 43)
wr:write_var('tx', {'_@'})
wr:write_var('tx', 'zxcvb')
wr:write_var('tx_3', {'A', 'C', 'Q', array = true })
wr:write_var('tx_3', {'ABCD'})
wr:write_var('ids', {1,2,3,4,5,6,7,8,9})
wr:write_var('idsx', {-1,-2,-3,-4,-5,-6,-7,-8,-9})
wr:write_var('ts3', {11,12,13,14,15,16,17,18,19}, 2)
wr:write_var('ts1', {'jkl'}, 1)
wr:write_var('tx4', { '1234567890abcdefghijkl', 'Q' } )
wr:write_var('ss', '$', 1)
wr:close()

-- ============= READ =================
local rd =reader.NCReader()
print('zzz.nc:')
rd:open('zzz.nc')
rPrint(rd, 1000000)
print('Reading fixed: ')
rPrint(rd:read_vars(false), 1000000)
for k = 1, rd.num_recs do
   print('Reading: ', k)
   rPrint(rd:read_vars(k), 1000000)
end
rd:close()

print('zzz2.nc:')
rd:open('zzz2.nc')
rPrint(rd, 1000000)
print('Reading fixed: ')
rPrint(rd:read_vars(false), 1000000)
for k = 1, rd.num_recs do
   print('Reading: ', k)
   rPrint(rd:read_vars(k), 1000000)
end

-- special read
rPrint(rd:read_var('ts1', 2, true), 1000)
rPrint(rd:read_var('r2str', false, true), 1000)

rd:close()
