local function fixed_reader(fmt)
   local parse_tbl = {}
   local pos = 1
   for t, len in string.gmatch(fmt, '([*IEA])(%d+)') do
      if t == '*' then
         pos = pos + len
      elseif t == 'A' then
         local begpos = pos
         local endpos = pos + len - 1
         table.insert(parse_tbl,
                      function (s)
                         return s:sub(begpos, endpos)
                      end )
         pos = pos + len
      elseif t == 'I' then
         local begpos = pos
         local endpos = pos + len - 1
         table.insert(parse_tbl,
                      function (s)
                         return math.tointeger(s:sub(begpos, endpos))
                      end )
         pos = pos + len
      elseif t == 'E' then
         local begpos = pos
         local endpos = pos + len - 1
         table.insert(parse_tbl,
                      function (s)
                         return tonumber(s:sub(begpos, endpos))
                      end )
         pos = pos + len
      end
   end

   return function (s)
      local res = {}
      local l = #parse_tbl
      for k = 1, l do
         res[k] = parse_tbl[k](s)
      end
      return table.unpack(res, 1, l)
   end
end

return {
   fixed_reader = fixed_reader,
}
