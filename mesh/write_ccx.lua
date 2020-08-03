local mesh_utils = require('mesh/utils')

local function write_nodes(f, mesh)
   f:write('*NODE, NSET=Nall\n')
   for k = 1, #mesh.nodes do
      f:write(string.format('%10u,%12.5e,%12.5e,%12.5e\n', k,
                            table.unpack(mesh.nodes[k])))
   end
end

local elemtable = {
   -- 1st order
   TETRA4 = { map = false }, -- C3D4
   HEX8 = { map = false }, -- C3D8
   WEDGE6 = { map = false }, -- C3D6
   -- 2nd order
   TETRA10 = { map = false }, -- C3D10
   HEX20 = { map = {
                1, 2, 3, 4, 5, 6, 7, 8,
                9, 10, 11, 12, 17, 18, 19, 20, 13, 14, 15, 16, }
           }, -- C3D20
   WEDGE15 = { map = {
                  1, 2, 3, 4, 5, 6,
                  7, 8, 9, 13, 14, 15, 10, 11, 12, }
             }, -- C3D15
}

local function write_els(f, mesh)
   -- mask to write elements grouping them by their types
   local elmask = {}
   for k = 1, #mesh.elems do
      elmask[k] = true
   end

   repeat
      -- find the first element not written yet
      local pos = 1
      while pos <= #mesh.elems and not elmask[pos] do
         pos = pos + 1
      end
      local found = pos <= #mesh.elems
      if found then
         -- element found, write header now
         -- elements from operators with repeating elset parameter
         -- are combined into the set
         f:write(string.format('*ELEMENT, TYPE=C3D%d, ELSET=Eall\n',
                               #mesh.elems[pos]))
         local eltype_name = mesh.elems[pos].type
         local elty = assert(elemtable[eltype_name],
                             'Failed to map eltype to CCX: ' .. eltype_name)
         -- process elements of the same type
         while pos <= #mesh.elems do
            if elmask[pos] and eltype_name == mesh.elems[pos].type then
               -- remove element from mask
               elmask[pos] = false

               local nodes = mesh.elems[pos]
               local ln = {}
               table.insert(ln, string.format('%10u', pos))
               for kn = 1, #nodes do
                  local ix
                  if not elty.map then
                     ix = kn
                  else
                     -- map node index
                     ix = elty.map[kn]
                  end
                  table.insert(ln, string.format('%10u', nodes[ix]))
               end

               -- write lines with continuations
               local ofs, len = 0, 1+#nodes
               while len > 0 do
                  local linelen = math.min(len, 7)
                  f:write(table.concat(ln, ',', ofs+1, ofs+linelen))
                  len = len - linelen
                  ofs = ofs + linelen
                  if len > 0 then
                     f:write(',\n') -- a continuation line will follow
                  else
                     f:write('\n')
                  end
               end

               -- element written
            end
            pos = pos + 1
         end
      end
      -- traverse elements again if any
   until not found
end

local function write_sets(f, kind, prefix, sets, nitems)
   for _, set in ipairs(sets) do
      f:write(string.format('*%s, %s=%s%d\n', kind, kind, prefix, set.id))
      for ki = 1, nitems do
         if set[ki] then
            f:write(string.format('%10u,\n', ki))
         end
      end
   end
end

local function write_ccx_mesh(f, mesh)
   -- compress if needed
   mesh_utils.compress_mesh(mesh)

   write_nodes(f, mesh)
   write_els(f, mesh)
   -- node sets
   write_sets(f, 'NSET', 'NSET', mesh.nsets, #mesh.nodes)
   write_sets(f, 'ELSET', 'EMAT', mesh.elsets, #mesh.elems)
end

return {
   write_ccx_mesh = write_ccx_mesh,
}
