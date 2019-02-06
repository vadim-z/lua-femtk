local R = require('read_frd')

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

local uni = R.read_frd('xtra/unisphere_ES.frd')
-- rPrint(uni, 1000000)
local cnt = R.read_frd('xtra/contact10.frd.ref')
-- rPrint(cnt, 1000000)
local gap = R.read_frd('xtra/gap2.frd.ref')
-- rPrint(gap, 1000000)
local seg = R.read_frd('xtra/segment.frd.ref')
--rPrint(seg, 1000000)
-- uni0 = R.read_frd('unisphere.frd')
--rPrint(uni0, 1000000)
local unit = R.read_frd('devex/unitest.frd')
rPrint(unit, 1000000)
