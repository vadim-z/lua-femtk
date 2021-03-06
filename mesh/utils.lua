-- various mesh utils
local exo2s = require('netCDF/exo2s')

-- convert boolean set to map and its inverse
local function bool_to_map(bset, nbset)
   local map, imap = {}, {}
   local kmap = 0
   for kb = 1, nbset do
      if bset[kb] then
         -- insert into map
         kmap = kmap + 1
         map[kmap] = kb
         imap[kb] = kmap
      end
   end

   return map, imap
end

-- compress sparse mesh var
local function compress_var(map, var)
   local var_comp = {}
   for k, km in ipairs(map) do
      var_comp[k] = var[km]
   end
   var_comp.id = var.id

   return var_comp
end

-- correct node numbers in elements
local function fix_elems(imap, elems, nelems)
   local elems_fix = {}
   for k = 1, nelems do
      local v = elems[k]
      if v then
         for kn, node in ipairs(v) do
            local node_map = imap[node]
            if node_map then
               v[kn] = node_map
            else
               error(string.format(
                        'Failed to map node %d in element %d',
                        node, k))
            end
         end
         elems_fix[k] = v
      end
   end

   return elems_fix
end

-- correct element numbers in sides
local function fix_sides(imap, sides)
   for ks = 1, #sides do
      local s = sides[ks]
      local el_map = imap[s.el]
      if el_map then
         s.el = el_map
      else
         error(string.format(
                  'Failed to map element %d in side with id %d',
                  s.el, s.side))
      end
   end
end

local function compress_mesh(mesh)
   if mesh.node_map then
      -- build node map
      local map, imap = bool_to_map(mesh.node_map, mesh.nnodes)
      -- compress nodes
      mesh.nodes = compress_var(map, mesh.nodes)
      -- compress node sets
      for ks = 1, #mesh.nsets do
         mesh.nsets[ks] = compress_var(map, mesh.nsets[ks])
      end
      -- fix elemens
      mesh.elems = fix_elems(imap, mesh.elems, mesh.nelems)
      -- fix count and map
      mesh.nnodes = #mesh.nodes
      mesh.node_map = false
   end

   if mesh.elem_map then
      -- build elem map
      local map, imap = bool_to_map(mesh.elem_map, mesh.nelems)
      -- compress elements
      mesh.elems = compress_var(map, mesh.elems)
      -- compress element sets
      for ks = 1, #mesh.elsets do
         mesh.elsets[ks] = compress_var(map, mesh.elsets[ks])
      end

      -- fix side definitions
      for ks = 1, #mesh.ssets do
         fix_sides(imap, mesh.ssets[ks])
      end

      -- fix count and map
      mesh.nelems = #mesh.elems
      mesh.elem_map = false
   end
end

-- convert nodes array to EXODUS-II large format three arrays
local function nodes_to_exo2(nodes)
   local nodes_exo2 = {{}, {}, {}}

   for kn, node in ipairs(nodes) do
      for kc, coord in ipairs(node) do
         nodes_exo2[kc][kn] = coord
      end
   end

   return nodes_exo2
end

-- convert boolean sets to raw node sets in EXODUS II format
local function exo2_nsets(mesh, ids)
   local sets = {}

   local function add_sets(n_sets, id)
      if id then
         for _, set in ipairs(n_sets) do
            local rset, _ = bool_to_map(set, mesh.nnodes)
            rset.id =  id + set.id
            table.insert(sets, rset)
         end
      end
   end

   -- add node sets
   add_sets(mesh.nsets, ids.nsets)

   return sets
end

local function exo2_ssets(mesh, ids)
   local sets = {}

   local id = ids.ssets

   if id then
      for kset = 1, #mesh.ssets do
         local set = mesh.ssets[kset]
         local rset = {}
         for ks = 1, #set do
            table.insert(rset, set[ks])
         end
         rset.id =  ids.ssets + set.id
         table.insert(sets, rset)
      end
   end

   return sets
end

-- create EXODUS II file and save mesh to it
local function save_mesh_exo2(mesh, fname, par)
   local f = exo2s.Exo2File()
   compress_mesh(mesh)
   f:init(fname, par)
   f:define_title(par.title)
   f:define_nodes(nodes_to_exo2(mesh.nodes))
   f:define_els(mesh.elems)
   f:define_nodesets(exo2_nsets(mesh, par.ids),
                     {}, true )
   f:define_sidesets(exo2_ssets(mesh, par.ids), {})
   return f
end

-- write mesh to EXODUS II file and close it afterwards
local function write_mesh_exo2(...)
   local f = save_mesh_exo2(...)
   f:close() -- commit changes
end

return {
   compress_mesh = compress_mesh,
   nodes_to_exo2 = nodes_to_exo2,
   exo2_nsets = exo2_nsets,
   save_mesh_exo2 = save_mesh_exo2,
   write_mesh_exo2 = write_mesh_exo2,
}
