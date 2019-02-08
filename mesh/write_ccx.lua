local function write_nodes(f, mesh)
   f:write('*NODE, NSET=Nall\n')
   for k = 1, #mesh.nodes do
      f:write(string.format('%10u,%12.5e,%12.5e,%12.5e\n', k,
                            unpack(mesh.nodes[k])))
   end
end

-- INVERT tets?
local invert = true
local map_c3d10, map_c3d4
if invert then
   -- map netgen nodes (lexicographical ordering) to CCX order
   map_c3d10 = {
      1, 2, 4, 3, 5, 9, 7, 6, 8, 10,
   }
   map_c3d4 = { 1, 2, 4, 3 }
else
   -- map netgen nodes (lexicographical ordering) to CCX order
   map_c3d10 = {
      1, 2, 3, 4, 5, 8, 6, 7, 9, 10,
   }
   map_c3d4 = { 1, 2, 3, 4 }
end

local function write_els(f, mesh)
   -- FIXME FIXME: determine order by the 1st element
   f:write(string.format('*ELEMENT, TYPE=C3D%d, ELSET=Eall\n',
                         #mesh.elems[1].nodes))
   for ke = 1, #mesh.elems do
      local nodes = mesh.elems[ke].nodes
      local map
      if #nodes == 10 then
         map = map_c3d10
      elseif #nodes == 4 then
         map = map_c3d4
      else
         error('Sorry, only 4/10-nodes tets are supported')
      end
      local ln = {}
      table.insert(ln, string.format('%10u', ke))
      for kn = 1, #nodes do
         table.insert(ln, string.format('%10u', nodes[map[kn]]))
      end
      if #nodes == 10 then
         -- write 1st line
         f:write(table.concat(ln, ',', 1, 7), ',\n')
         -- write cont line
         f:write(table.concat(ln, ',', 8, 11), '\n')
      elseif #nodes == 4 then
         f:write(table.concat(ln, ',', 1, 5), ',\n')
      end
   end
end

local function write_sets(f, kind, prefix, sets, nitems)
   for ks = 1, #sets do
      f:write(string.format('*%s, %s=%s%d\n', kind, kind, prefix, ks))
      for ki = 1, nitems do
         if sets[ks][ki] then
            f:write(string.format('%10u,\n', ki))
         end
      end
   end
end

local function write_sets_tbl(fname, sets, nitems)
   local f = assert(io.open(fname, 'w'))
   for ki = 1, nitems do
      local ln = {}
      for ks = 1, #sets do
         local v = sets[ks][ki] and 1 or 0
         table.insert(ln, string.format('%1d', v))
      end
      f:write(table.concat(ln, ' '), '\n')
   end
   f:close()
end

local function write_model_boundary(f, mesh)
   -- write boundary conditions defined as a part of model
   f:write('*BOUNDARY\n')
   for _, bdisp in ipairs(mesh.bdisp) do
      for kd = 1, 3 do
         f:write(string.format('%10u,%d,%d,%12.5e\n',
                               bdisp[1], kd, kd, bdisp[1+kd]))
      end
   end
end

local function write_mesh_ccx_tets(fname, mesh, fnames_tbl)
   local f = assert(io.open(fname, 'w'))
   fnames_tbl = fnames_tbl or {}
   write_nodes(f, mesh)
   write_els(f, mesh)
   -- material sets
   write_sets(f, 'NSET', 'NMAT', mesh.vol_n, #mesh.nodes)
   if fnames_tbl.vol_n then
      write_sets_tbl(fnames_tbl.vol_n, mesh.vol_n, #mesh.nodes)
   end
   write_sets(f, 'ELSET', 'EMAT', mesh.vol_el, #mesh.elems)
   if fnames_tbl.vol_el then
      write_sets_tbl(fnames_tbl.vol_el, mesh.vol_el, #mesh.elems)
   end
   -- boundary sets
   write_sets(f, 'NSET', 'NBOU', mesh.surf_n, #mesh.nodes)
   if fnames_tbl.surf_n then
      write_sets_tbl(fnames_tbl.surf_n, mesh.surf_n, #mesh.nodes)
   end

   -- boundary conditions
   if mesh.bdisp then
      write_model_boundary(f, mesh)
   end

   f:close()
end

return {
   write_mesh_ccx_tets = write_mesh_ccx_tets,
}
