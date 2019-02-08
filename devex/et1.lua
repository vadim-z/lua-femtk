local EX2 = require('netCDF/exo2s')

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

local f = EX2.Exo2File()
f:init('t1.exo')
f:define_title('foobar')
f:add_qa{code='manual', ver='0.00', date = '02.08.2022', time = '9:50'}
f:define_nodes{
   -- X
   { 0.0, 1.0, 0.0, 0.0},
   -- Y
   { 0.0, 0.0, 1.0, 0.0},
   -- Z
   { 0.0, 0.0, 0.0, 1.0},
}

f:define_els(
   { { 1, 2, 3, 4, type = 'TETRA', id = 99 } },
   { [99] = 'steel' }
)

f:define_glob_vars{'goo', 'zoo'}
f:define_node_vars{'UX', 'UY', 'UZ'}

f:write_glob_vars(2, { zoo = 2, goo = 3} )
f:write_glob_vars(1, { goo = 100, zoo = 900 } )
f:write_time_step(1, 0.5)
f:write_time_step(2, 0.7)

f:write_node_var(1, 'UX', { 1.1, 1.2, 1.3, 1.4})
f:write_node_var(1, 'UZ', { -1.1, -1.2, -1.3, -1.4})
f:write_node_var(1, 'UY', { 0.01, 0.02, 0.03, 0.04})
f:write_node_var(2, 'UY', { 2.1, 2.2, 2.3, 2.4})
f:write_node_var(2, 'UZ', { -2.1, -2.2, -2.3, -2.4})
f:write_node_var(2, 'UX', { 0.01, 0.02, 0.03, 0.04})

f:close()

-- rPrint(f, 100000)

