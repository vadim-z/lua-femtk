local EX2 = require('exo2s')

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

f:define_glob_var('goo')
f:define_glob_var('zoo')
f:define_node_var('UX')
f:define_node_var('UY')
f:define_node_var('UZ')

EX2.create_exo2_file(f)

f:close()

-- rPrint(f, 100000)

