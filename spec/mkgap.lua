--local reader = require('mesh/read_msh2')
--local utils = require('mesh/utils')

-- identify nodes belonging to both domains
-- make twins of them
local function make_twins(mesh, twin_map, v1, v2, surf1, surf2)

   -- Phase I: build twin map, add twin nodes, replace volume node set refs
   local kend = mesh.nnodes
   for k = 1, mesh.nnodes do
      if mesh.vol_n[v1][k] and mesh.vol_n[v2][k] then
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
         mesh.vol_n[v2][k] = nil
         mesh.vol_n[v2][knew] = true
      end
   end
   -- update number of nodes
   mesh.nnodes = kend

   -- Phase II: fix elements
   for k = 1, mesh.nelems do
      if mesh.vol_el[v2][k] then
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

local function mkgap(mesh, list1, list2, fac)
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

   local twin_map = {}

   for k = 1, #list1 do
      make_twins(mesh, twin_map, list1[k], list2[k], surf1, surf2)
   end

   dilate_nodes_xy(mesh, list2, fac)

   mesh.twin1, mesh.twin2 = twin_lists(twin_map, mesh.nnodes)
end

return {
   mkgap = mkgap,
}
