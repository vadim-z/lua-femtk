-- module to read mesh in native gmsh MSH2 format

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

local function end_section(f, name)
   assert(getline(f) == '$End' .. name,
          'End of section ' .. name .. ' expected')
end

local function read_fmt(f)
   assert(getline(f) == '$MeshFormat', 'MeshFormat section expected')
   local fmt, ftype, dsize = gettoks(f)
   assert(fmt == 2.2 and ftype == 0 and dsize == 8, 'Invalid mesh format')
   end_section(f, 'MeshFormat')
end

local function read_nodes(M, f)
   local nnodes = gettoks(f)
   local nodes = {}
   local node_map = {}
   for _ = 1, nnodes do
      local i, x, y, z = gettoks(f)
      nodes[i] = {x, y, z}
   end
   end_section(f, 'Nodes')
   M.node_map = node_map
   M.nodes = nodes
   M.nnodes = nnodes
end

-- FIXME: unmapped 1D/2D elts
local elemtable = {
   -- 1st order
   {1, 2, 1}, -- 2n line
   {2, 3, 2}, -- 3n tri
   {3, 4, 2}, -- 4n quad
   {4, 4, 3,
    type = 'TETRA4', map = false }, -- 4n tet
   {5, 8, 3,
    type = 'HEX8', map = false }, -- 8n hex
   {6, 6, 3,
    type = 'WEDGE6', map = false }, -- 6n prism
   {7, 5, 3,
    type = 'PYRAMID5', map = false }, -- 5n pyr (unsupported in CCX/CGX)
   -- 2nd order
   {8, 3, 1}, -- 3n line
   {9, 6, 2}, -- 6n tri
   {10, 9, 2}, -- 9n quad
   {11, 10, 3,
    type = 'TETRA10',
    map = {1, 2, 3, 4, 5, 6, 7, 8, 10, 9},
   }, -- 10n tet
   {12, 27, 3}, -- 27n hex (unsupported in EXODUS II model)
   {13, 18, 3}, -- 18n prism (unsupported in EXODUS II model)
   {14, 14, 3}, -- 14n pyr (unsupported in EXODUS II model)
   -- misc
   {15, 1, 0}, -- point
   -- 2nd serendipity
   {16, 8, 2}, -- 8n quad
   {17, 20, 3,
    type = 'HEX20',
    map = {1, 2, 3, 4, 5, 6, 7, 8, 9, 12, 14, 10, 11, 13, 15, 16,
           17, 19, 20, 18},
   }, -- 20n hex (NB: this is EXODUS II order, CCX/CGX has another one!)
   {18, 15, 3,
    type = 'WEDGE15',
    map = {1, 2, 3, 4, 5, 6, 7, 10, 8, 9, 11, 12, 13, 15, 14},
   }, -- 15n prism (NB: this is EXODUS II order, CCX/CGX has another one!)
   {19, 13, 3,
    type = 'PYRAMID13',
    map = {1, 2, 3, 4, 5, 6, 9, 11, 7, 8, 10, 12, 13},
   }, -- 13n pyr (unsupported in CCX/CGX)
}

local function read_elems(M, f)
   local nelems = gettoks(f)
   local elems = {}
   local elem_map = {}
   local vol_el, vol_n = {}, {}
   local surf_n = {}

   for _ = 1, nelems do
      local ls = {gettoks(f)}
      -- parse element description
      local i = ls[1]
      local t = ls[2]
      local ntags = ls[3]
      assert(ntags >= 2, 'Invalid number of tags for element ' .. i)
      local phy = ls[4]
      local geom = ls[5]
      local nix = 3 + ntags

      -- parse nodes
      local elty = elemtable[t]
      assert(elty, 'Unknown element type ' .. t)

      -- FIXME: use geometric ID for unphysical elements (?)
      if phy == 0 then
         phy = geom
      end

      if elty[3] == 3 then
         -- 3D element, register, add element to set, add nodes to set
         local el = {}
         elems[i] = el
         elem_map[i] = true

         el.id = phy
         el.type = assert(elty.type,
                          'Element type unsupported in the model ' .. t)

         -- mark volume element set
         vol_el[phy] = vol_el[phy] or {}
         vol_el[phy][i] = true

         -- mark nodes in volume node set
         vol_n[phy] = vol_n[phy] or {}

         -- proceed with nodes
         local nnodes = elty[2]

         for kn = 1, nnodes do
            local node
            if not elty.map then
               -- map node index
               node = ls[nix+kn]
            else
               node = ls[nix + elty.map[kn] ]
            end
            el[kn] = node
            vol_n[phy][node] = true
            M.node_map[node] = true
         end
      elseif elty[3] == 2 then
         -- 2D element, add nodes to set

         -- mark nodes in surface node set
         surf_n[phy] = surf_n[phy] or {}

         -- proceed with nodes
         local nnodes = elty[2]

         for kn = 1, nnodes do
            local node = ls[nix+kn]
            surf_n[phy][node] = true
            M.node_map[node] = true
         end
      end
      -- ignore 1D, 0D elements
   end

   end_section(f, 'Elements')

   M.elems = elems
   M.nelems = nelems
   M.elem_map = elem_map
   M.vol_n = vol_n
   M.vol_el = vol_el
   M.surf_n = surf_n
end

local function skip_section(f, name)
   local ename = '$End' .. string.sub(name, 2)
   local l = name
   while l ~= ename do
      l = getline(f)
   end
end

local function read_msh2(fname)
   local f = assert(io.open(fname, 'r'))
   read_fmt(f)
   local mesh = {}
   local stage = 0

   while stage ~= 2 do
      local l = getline(f)
      if l == '$Nodes' and stage == 0 then
         read_nodes(mesh, f)
         stage = stage + 1
      elseif l == '$Elements' and stage == 1 then
         read_elems(mesh, f)
         stage = stage + 1
      else
         skip_section(f, l)
      end
   end
   f:close()

   return mesh
end

return {
   read_msh2 = read_msh2,
}
