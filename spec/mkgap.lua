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
-- make twins of them
local function make_twins(mesh, twin_map, vn1, vn2, ve2)

   -- Phase I: build twin map, add twin nodes, replace volume node set refs
   local kend = mesh.nnodes
   for k = 1, mesh.nnodes do
      if mesh.vol_n[vn1][k] and mesh.vol_n[vn2][k] then
         local knew = twin_map[k]
         if not knew then
            -- make new twin of this node
            kend = kend + 1
            knew = kend
            twin_map[k] = knew

            -- copy node
            local node = {}
            mesh.nodes[knew] = node
            for kc, vc in ipairs(mesh.nodes[k]) do
               node[kc] = vc
            end

         end

         -- change volume node set references
         mesh.vol_n[vn2][k] = nil
         mesh.vol_n[vn2][knew] = true
      end
   end
   -- update number of nodes
   mesh.nnodes = kend

   -- Phase II: fix elements
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
   return twin_map

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

   local twin_map = {}

   for k = 1, #id_list1 do
      make_twins(mesh, twin_map, vn1[k], vn2[k], ve2[k])
   end

   dilate_nodes_xy(mesh, vn2, fac)

   mesh.twin1, mesh.twin2 = twin_lists(twin_map, mesh.nnodes)
end

return {
   mkgap = mkgap,
}
