local mesh_utils = require('mesh/utils')

local function write_nodes(f, mesh)
   f:write('*NODE, NSET=Nall\n')
   for k = 1, #mesh.nodes do
      f:write(string.format('%10u,%12.5e,%12.5e,%12.5e\n', k,
                            table.unpack(mesh.nodes[k])))
   end
end

local function write_els(f, mesh)
   -- FIXME FIXME: determine order by the 1st element
   f:write(string.format('*ELEMENT, TYPE=C3D%d, ELSET=Eall\n',
                         #mesh.elems[1]))
   for ke = 1, #mesh.elems do
      local nodes = mesh.elems[ke]
      local ln = {}
      table.insert(ln, string.format('%10u', ke))
      for kn = 1, #nodes do
         table.insert(ln, string.format('%10u', nodes[kn]))
      end
      -- FIXME: other types of elements
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

-- ==== TEXT FORMAT ====
-- write one table corresponding to sets
local function write_sets_tbl_txt(fname, sets, nitems)
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

   -- prepare one table corresponding to sets
   local function mk_sets_netCDF(def, vardata, sets, nitems, varprefix, dimname)
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
      end
   end

   local def = {
      dims = {
         num_nodes = #mesh.nodes,
         num_elem = #mesh.elems,
      },
      vars = {},
      atts = {}
   }
   local vardata = {}

   if fnames_tbl.surf_n then
      mk_sets_netCDF(def, vardata, mesh.surf_n, #mesh.nodes,
                     fnames_tbl.surf_n, 'num_nodes')
      def.atts.n_surf_n = { #mesh.surf_n, type = NC.NC.INT }
   end

   if fnames_tbl.vol_n then
      mk_sets_netCDF(def, vardata, mesh.vol_n, #mesh.nodes,
                     fnames_tbl.vol_n, 'num_nodes')
      def.atts.n_vol_n = { #mesh.vol_n, type = NC.NC.INT }
   end

   if fnames_tbl.vol_el then
      mk_sets_netCDF(def, vardata, mesh.vol_el, #mesh.elems,
                     fnames_tbl.vol_el, 'num_elem')
      def.atts.n_vol_el = { #mesh.vol_el, type = NC.NC.INT }
   end

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

local function write_mesh_ccx(fname, mesh, fnames_tbl)
   -- compress if needed
   mesh_utils.compress_mesh(mesh)

   local f = assert(io.open(fname, 'w'))
   fnames_tbl = fnames_tbl or {}
   write_nodes(f, mesh)
   write_els(f, mesh)
   -- material sets
   write_sets(f, 'NSET', 'NMAT', mesh.vol_n, #mesh.nodes)
   write_sets(f, 'ELSET', 'EMAT', mesh.vol_el, #mesh.elems)
   -- boundary sets
   write_sets(f, 'NSET', 'NBOU', mesh.surf_n, #mesh.nodes)

   -- boundary conditions
   if mesh.bdisp then
      write_model_boundary(f, mesh)
   end

   -- write tables
   set_writers[fnames_tbl.fmt](mesh, fnames_tbl)

   f:close()
end

return {
   write_mesh_ccx = write_mesh_ccx,
}
