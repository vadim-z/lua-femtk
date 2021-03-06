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
   -- FIXME FIXME: determine order by the 1st element
   f:write(string.format('*ELEMENT, TYPE=C3D%d, ELSET=Eall\n',
                         #mesh.elems[1]))
   for ke, elem in ipairs(mesh.elems) do
      local elty = assert(elemtable[elem.type],
                          'Failed to map eltype to CCX: ' .. elem.type)
      local nodes = mesh.elems[ke]
      local ln = {}
      table.insert(ln, string.format('%10u', ke))
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
   end
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

local function write_ccx_model_boundary(f, mesh, dof, amp)
   -- write boundary conditions defined as a part of model
   f:write('*BOUNDARY')
   if amp then
      f:write(', AMPLITUDE=', amp)
   end
   f:write('\n')
   dof = dof or { 1, 2, 3}
   for _, bdisp in ipairs(mesh.bdisp) do
      for kdi = 1, #dof do
         kd = dof[kdi]
         f:write(string.format('%10u,%d,%d,%12.5e\n',
                               bdisp[1], kd, kd, bdisp[1+kd]))
      end
   end
end

-- ==== TEXT FORMAT ====
-- write one table corresponding to sets
local function write_sets_tbl_txt(fname, sets, nitems)
   local f = assert(io.open(fname, 'w'))
   -- banner
   local ln = { '%' }
   for _,  set in ipairs(sets) do
      table.insert(ln, string.format('%d', set.id))
   end
   f:write(table.concat(ln, ' '), '\n')

   for ki = 1, nitems do
      ln = {}
      for _, set in ipairs(sets) do
         local v = set[ki] and 1 or 0
         table.insert(ln, string.format('%1d', v))
      end
      f:write(table.concat(ln, ' '), '\n')
   end
   f:close()
end

-- write all tables
local function write_sets_tbls_txt(mesh, fnames_tbl)
   if fnames_tbl.vol_n then
      write_sets_tbl_txt(fnames_tbl.vol_n, mesh.vol_n, #mesh.nodes)
   end
   if fnames_tbl.vol_el then
      write_sets_tbl_txt(fnames_tbl.vol_el, mesh.vol_el, #mesh.elems)
   end
   -- boundary sets
   if fnames_tbl.surf_n then
      write_sets_tbl_txt(fnames_tbl.surf_n, mesh.surf_n, #mesh.nodes)
   end
end

-- ==== netCDF FORMAT ====
local function write_sets_netCDF(mesh, fnames_tbl)
   local NC = require('netCDF/writer')

   local def = {
      dims = {
         num_nodes = #mesh.nodes,
         num_elem = #mesh.elems,
      },
      vars = {},
      atts = {}
   }
   local vardata = {}

   -- prepare one table corresponding to sets
   local function mk_sets_netCDF(sets, nitems, varprefix, dimname)
      if varprefix and #sets > 0 then
         local ids = {}
         -- the map
         for ks, set in ipairs(sets) do
            local varname = string.format('%s_%d', varprefix, ks)
            local list = {}
            for ki = 1, nitems do
               table.insert(list, set[ki] and 1 or 0)
            end
            def.vars[varname] = {
               type = NC.NC.BYTE,
               dims = { dimname }
            }
            vardata[varname] = list
            ids[ks] = set.id
         end
         -- dimension and ids
         local sets_dim_name = 'num_' .. varprefix
         def.dims[sets_dim_name] = #sets
         local ids_var_name = 'id_' .. varprefix
         def.vars[ids_var_name] = {
            type = NC.NC.INT,
            dims = { sets_dim_name },
         }
         vardata[ids_var_name] = ids
      end
   end

   mk_sets_netCDF(mesh.surf_n, #mesh.nodes, fnames_tbl.surf_n, 'num_nodes')
   mk_sets_netCDF(mesh.vol_n, #mesh.nodes, fnames_tbl.vol_n, 'num_nodes')
   mk_sets_netCDF(mesh.vol_el, #mesh.elems, fnames_tbl.vol_el, 'num_elem')

   local f = NC.NCWriter()
   f:create(fnames_tbl.filename, def)
   for name, _ in pairs(def.vars) do
      f:write_var(name, vardata[name])
   end

   f:close()
end

local set_writers = {
   txt = write_sets_tbls_txt,
   netCDF = write_sets_netCDF,
}

local function write_ccx_mesh(f, mesh)
   -- compress if needed
   mesh_utils.compress_mesh(mesh)

   write_nodes(f, mesh)
   write_els(f, mesh)
   -- material sets
   write_sets(f, 'NSET', 'NMAT', mesh.vol_n, #mesh.nodes)
   write_sets(f, 'ELSET', 'EMAT', mesh.vol_el, #mesh.elems)
   -- boundary sets
   write_sets(f, 'NSET', 'NBOU', mesh.surf_n, #mesh.nodes)
end

local function write_ccx_tables(mesh, fnames_tbl)
   set_writers[fnames_tbl.fmt](mesh, fnames_tbl)
end

return {
   write_ccx_mesh = write_ccx_mesh,
   write_ccx_model_boundary = write_ccx_model_boundary,
   write_ccx_tables = write_ccx_tables,
}
