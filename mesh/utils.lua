-- various mesh utils

-- FIXME (here and in readers):
-- determine and use maximal values of volume and surface markers

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

local function compress_mesh(mesh)
   if mesh.node_map then
      -- build node map
      local map, imap = bool_to_map(mesh.node_map, mesh.nnodes)
      -- compress nodes
      mesh.nodes = compress_var(map, mesh.nodes)
      -- compress node sets
      for ks = 1, #mesh.surf_n do
         mesh.surf_n[ks] = compress_var(map, mesh.surf_n[ks])
      end
      for ks = 1, #mesh.vol_n do
         mesh.vol_n[ks] = compress_var(map, mesh.vol_n[ks])
      end
      -- fix elemens
      mesh.elems = fix_elems(imap, mesh.elems, mesh.nelems)
      -- fix count and map
      mesh.nnodes = #mesh.nodes
      mesh.node_map = false
   end

   if mesh.elem_map then
      -- build elem map
      local map, _ = bool_to_map(mesh.elem_map, mesh.nelems)
      -- compress elements
      mesh.elems = compress_var(map, mesh.elems)
      -- compress element sets
      for ks = 1, #mesh.vol_el do
         mesh.vol_el[ks] = compress_var(map, mesh.vol_el[ks])
      end
      -- fix count and map
      mesh.nelems = #mesh.elems
      mesh.elem_map = false
   end
end

-- convert nodes array to EXODUS-II large format three arrays
local function nodes_to_ex2(nodes)
   local nodes_ex2 = {{}, {}, {}}

   for kn, node in ipairs(nodes) do
      for kc, coord in ipairs(node) do
         nodes_ex2[kc][kn] = coord
      end
   end

   return nodes_ex2
end

-- convert boolean sets to raw node sets in EXODUS II format
local function exo2_nsets(mesh, ids)
   local sets = {}

   local function add_sets(n_sets, id, code)
      for ks, set in ipairs(n_sets) do
         local rset, _ = bool_to_map(set, mesh.nnodes)
         rset.id =  id + ks
         rset.SURF = code
         rset.VOL = 1 - code
         table.insert(sets, rset)
      end
   end

   -- first, add surface sets
   add_sets(mesh.surf_n, ids.surfn, 1)
   -- then, add volume sets
   -- first, add surface sets
   add_sets(mesh.vol_n, ids.voln, 0)

   return sets
end

return {
   compress_mesh = compress_mesh,
   nodes_to_ex2 = nodes_to_ex2,
   exo2_nsets = exo2_nsets,
}
