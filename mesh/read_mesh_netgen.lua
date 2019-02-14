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

local function read_elems(f)
   local nelems = gettoks(f)
   local elems = {}
   for _ = 1, nelems do
      local el = {gettoks(f)}
      local mark = el[1]
      table.remove(el, 1)
      table.insert(elems, { mark = mark, nodes = el } )
   end
   return elems
end

local function read_mesh_netgen(fname)
   -- local t = TT.tic('Reading Netgen mesh file (neutral format)')
   local f = assert(io.open(fname, 'r'))
   local nodes = read_nodes(f)
   local elems = read_elems(f)
   local selems = read_elems(f)
   f:close()
   -- TT.toc(t)
   return { nodes = nodes, elems = elems, selems = selems }
end

local function make_sets(mesh)
   -- Generate element and node sets corresponding to
   -- material and boundary markers
   local vol_el, vol_n, surf_n = {}, {}, {}

   -- enumerate volume elements
   for ke = 1, #mesh.elems do
      local m = mesh.elems[ke].mark
      vol_el[m] = vol_el[m] or {}
      vol_el[m][ke] = true
      vol_n[m] = vol_n[m] or {}
      local nodes = mesh.elems[ke].nodes
      for kn = 1, #nodes do
         vol_n[m][nodes[kn]] = true
      end
   end

   -- enumerate surface elements
   for ke = 1, #mesh.selems do
      local m = mesh.selems[ke].mark
      surf_n[m] = surf_n[m] or {}
      local nodes = mesh.selems[ke].nodes
      for kn = 1, #nodes do
         surf_n[m][nodes[kn]] = true
      end
   end
   mesh.vol_el = vol_el
   mesh.vol_n = vol_n
   mesh.surf_n = surf_n
end

return {
   read_mesh_netgen = read_mesh_netgen,
   make_sets = make_sets,
}
