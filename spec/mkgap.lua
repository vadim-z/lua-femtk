--local reader = require('mesh/read_msh2')
--local utils = require('mesh/utils')

-- find node/el sets by ids
-- return list corresponding to ids
local function sets_by_ids(sets, ids)
   local list = {}
   for _, id in ipairs(ids) do
      for kset, set in ipairs(sets) do
         if set.id == id then
            list[#list+1] = kset
         end
      end
   end

   return list
end

-- identify nodes belonging to both domains
-- add twin nodes to the list
local function add_twin_map(mesh, k_last, twin_map, vn1, vn2)
   for k = 1, mesh.nnodes do
      if mesh.vol_n[vn1][k] and mesh.vol_n[vn2][k] and not twin_map[k] then
         -- make new twin of this node
         k_last = k_last + 1
         twin_map[k] = k_last
      end
   end
   return k_last
end

local function update_vols(mesh, twin_map, vn2, ve2)
   for k, ktwin in pairs(twin_map) do
      -- copy node
      local node = {}
      mesh.nodes[ktwin] = node
      for kc, vc in ipairs(mesh.nodes[k]) do
         node[kc] = vc
      end

      -- change volume node set references
      if mesh.vol_n[vn2][k] then
         mesh.vol_n[vn2][k] = nil
         mesh.vol_n[vn2][ktwin] = true
      end
   end

   -- fix elements
   for k = 1, mesh.nelems do
      if mesh.vol_el[ve2][k] then
         local el = mesh.elems[k]
         -- replace all nodes in the twin list by twins
         for kn, node in ipairs(el) do
            local twin = twin_map[node]
            if twin then
               el[kn] = twin
            end
         end
      end
   end

--[[
   -- Phase III: add twins to a new surface if required
   -- FIXME: other surfaces
   for k, ktwin in pairs(twin_map) do
      if surf1 then
         mesh.surf_n[surf1][k] = true
      end
      if surf2 then
         mesh.surf_n[surf2][ktwin] = true
      end
   end
]]
end

-- dilate all nodes belonging to domain list in XY-plane by fac
local function dilate_nodes_xy(mesh, vlist, fac)
   local marked = {}

   for _, kvol in ipairs(vlist) do
      -- iterate over all nodes in volume node set
      for node, _ in pairs(mesh.vol_n[kvol]) do
         if node ~= 'id' and not marked[node] then
            -- do not dilate twice
            marked[node] = true

            mesh.nodes[node][1] = mesh.nodes[node][1]*fac
            mesh.nodes[node][2] = mesh.nodes[node][2]*fac
         end
      end
   end
end

local function twin_lists(twin_map, n)
   local tw1, tw2 = {}, {}
   for k = 1, n do
      local ktwin = twin_map[k]
      if ktwin then
         tw1[#tw1+1] = k
         tw2[#tw2+1] = ktwin
      end
   end
   return tw1, tw2
end

local function mkgap(mesh, id_list1, id_list2, fac)
--[[
   local surf1, surf2 = nil, nil

   if list1.surf_id then
      table.insert(mesh.surf_n, { id = list1.surf_id })
      -- surface node sets index
      surf1 = #mesh.surf_n
   end

   if list2.surf_id then
      table.insert(mesh.surf_n, { id = list2.surf_id })
      -- surface node sets index
      surf2 = #mesh.surf_n
   end
]]

   -- volume node sets
   local vn1 = sets_by_ids(mesh.vol_n, id_list1)
   local vn2 = sets_by_ids(mesh.vol_n, id_list2)
   -- volume element sets
   local ve1 = sets_by_ids(mesh.vol_el, id_list1)
   local ve2 = sets_by_ids(mesh.vol_el, id_list2)

   local k_last, twin_map = mesh.nnodes, {}

   for k = 1, #id_list1 do
      k_last = add_twin_map(mesh, k_last, twin_map, vn1[k], vn2[k])
   end

   -- FIXME: partition surfaces etc

   -- update number of nodes
   mesh.nnodes = k_last

   for k = 1, #id_list1 do
      update_vols(mesh, twin_map, vn2[k], ve2[k])
   end

   dilate_nodes_xy(mesh, vn2, fac)

   mesh.twin1, mesh.twin2 = twin_lists(twin_map, mesh.nnodes)
end

return {
   mkgap = mkgap,
}
