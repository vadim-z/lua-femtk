-- Reading Netgen mesh file (neutral format)

local function getline(f)
   local s
   repeat
      s = f:read()
      assert(s, 'Unexpected EoF')
      s = s:gsub('#.*', '')
   until not(s:match('^%s*$'))
   return s
end

local function tokenize(s)
   local t = {}
   for w in s:gmatch('%S+') do
      table.insert(t, (assert(tonumber(w), 'Lexical error: '..w)))
   end
   return table.unpack(t)
end

local function gettoks(f)
   return tokenize(getline(f))
end

local function read_nodes(f)
   local nnodes = gettoks(f)
   local nodes = {}
   for _ = 1, nnodes do
      table.insert(nodes, {gettoks(f)})
   end
   return nodes
end

local function marked_nset(nsets, mark)
   -- exists?
   local n_set = nsets.imap[mark]
   if not n_set then
      table.insert(nsets, { id = mark } )
      n_set = #nsets
      nsets.imap[mark] = n_set
   end
   return nsets[n_set]
end

-- INVERT tets?
local invert = true
local map_t10, map_t4
if invert then
   -- map netgen nodes (lexicographical ordering) to CCX order
   map_t10 = {
      1, 2, 4, 3, 5, 9, 7, 6, 8, 10,
   }
   map_t4 = { 1, 2, 4, 3 }
else
   -- map netgen nodes (lexicographical ordering) to CCX order
   map_t10 = {
      1, 2, 3, 4, 5, 8, 6, 7, 9, 10,
   }
   map_t4 = { 1, 2, 3, 4 }
end

local function read_vol_elems(mesh, f)
   local nelems = gettoks(f)
   local elems = {}
   local vol_el = { imap = {} }
   local vol_n = { imap = {} }

   for ke = 1, nelems do
      local el_ng = {gettoks(f)}
      local mark = el_ng[1]
      local el = {}
      local map
      el.id = mark

      -- mark volume element set
      local nset = marked_nset(vol_el, mark)
      nset[ke] = true

      -- mark nodes in volume node set
      nset = marked_nset(vol_n, mark)

      if #el_ng == 11 then
         -- 2nd order tet
         el.type = 'TETRA10'
         map = map_t10
      elseif #el_ng == 5 then
         el.type = 'TETRA4'
         map = map_t4
      else
         error('Sorry, only 4/10-nodes tets are supported')
      end
      -- fill mapped nodes
      for kn, n_map in ipairs(map) do
         local node = el_ng[1+n_map]
         el[kn] = node
         nset[node] = true
      end

      table.insert(elems, el)
   end

   mesh.elems = elems
   mesh.vol_n = vol_n
   mesh.vol_el = vol_el
end

local function read_surf_elems(mesh, f)
   local nelems = gettoks(f)
   local surf_n = { imap = {} }

   for _ = 1, nelems do
      local el_ng = {gettoks(f)}
      local mark = el_ng[1]

      -- mark nodes in surface node set
      local nset = marked_nset(surf_n, mark)

      for kn = 1, #el_ng - 1 do
         local node = el_ng[1+kn]
         nset[node] = true
      end
   end

   mesh.surf_n = surf_n
end

local function read_mesh_netgen_tets(fname)
   local f = assert(io.open(fname, 'r'))
   local mesh = {}
   mesh.nodes = read_nodes(f)
   mesh.nnodes = #mesh.nodes
   mesh.node_map = false
   read_vol_elems(mesh, f)
   mesh.nelems = #mesh.elems
   mesh.elem_map = false
   read_surf_elems(mesh, f)
   -- FIXME: generate side definitions
   mesh.surf_ss = { imap = {} }
   f:close()
   return mesh
end

return {
   read_mesh_netgen_tets = read_mesh_netgen_tets,
}
