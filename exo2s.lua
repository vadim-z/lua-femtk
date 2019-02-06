-- Module to write simplified EXODUS II files
local netCDF = require('netCDF')

local Exo2Class = {}

-- initialize general EXODUS II entities
local function define_gen(self)
   self.dims = {}
   self.dims.time_step = 0
   self.dims.four = 4
   self.dims.len_string = 33
   self.dims.len_line = 81
   self.atts = {}
   self.atts.version = { 2.02, type = netCDF.NC.FLOAT }
   self.atts.api_version = { 2.02, type = netCDF.NC.FLOAT }
   self.atts.floating_point_word_size = { 8, type = netCDF.NC.INT }
   self.atts.file_size = { 1, type = netCDF.NC.INT }
   --.......
end

-- define nodes and related variables
local function define_nodes(self, nodes)
   local ndim = #nodes
   if ndim > 0 then
      self.dims.num_dim = ndim
      self.dims.num_nodes = #nodes[1]
      local co = { 'x', 'y', 'z' }
      self.vars.coor_names = {
         type = netCDF.NC.CHAR,
         dims = { 'num_dim', 'len_string' }
      }
      self.vals_fixed.coor_names = {}
      for kd, dname in ipairs(co) do
         local coname = 'coord' .. dname
         self.vars[coname] = {
            type = self.numtype,
            dims = { 'num_nodes' }
         }
         self.vals_fixed[coname] = nodes[kd]
         self.vals_fixed.coor_names[kd] = dname:upper()
      end
   end
end

-- define element blocks and related variables
local function define_els(self, els)
   -- table of connect ... variables definition
   local conn_def = {}
   -- table of connect... variables content
   local conn_blocks = {}
   local nblocks = 0
   -- map of type*id -> nblocks
   local blocks = {}
   -- local maps of external element numbers in each block
   local blk_elem_maps = {}
   -- ids of the blocks
   local ids = {}

   for k, el in ipairs(els) do
      local id = el.id
      blocks[id] = blocks[id] or {}
      local bkey = string:format('%s%d', el.type, #el)
      -- try to find block by its id and type
      local bl_num = blocks[id][bkey]
      local block, el_map

      if not bl_num then
         -- element block does not exist yet. create it.
         nblocks = nblocks + 1
         blocks[id][bkey] = nblocks
         bl_num = nblocks
         block = {}
         conn_blocks[bl_num] = block
         el_map = {}
         blk_elem_maps[bl_num] = el_map
         -- add attribute (element type), dimensions to var definition
         conn_def[bl_num] = {
            type = self.numtype,
            dims = {
               string.format('num_el_in_blk%d', bl_num),
               string.format('num_nod_per_el%d', bl_num),
            },
            atts = { elem_type = el.type }
         }
         -- add id (property #1)
         ids[bl_num] = id
      else
         -- element block already exists. fetch it
         block = conn_blocks[bl_num]
         el_map = blk_elem_maps[bl_num]
      end

      -- add the element to the block
      -- register external number
      table.insert(el_map, k)
      -- add connectivity
      for _, node in ipairs(el) do
         table.insert(block, node)
      end

   end -- loop over elements

   -- build element map for EXODUS II: mapping of our element numbers to
   -- EXODUS one, which must be consecutive and contiguous in the
   -- element blocks
   local elem_map = {}
   for _, map in ipairs(blk_elem_maps) do
      for _, k in ipairs(map) do
         table.insert(elem_map, k)
      end
   end

   assert(#elem_map == #els,
          'Internal error: mismatching elements numbers')
   assert(#conn_blocks == nblocks,
          'Internal error: mismatching element blocks numbers')

   if nblocks == 0 then
      -- nothing to add
      return
   end
   -- add netCDF entities related to elements
   -- dimensions
   self.dims.num_elem = #els
   self.dims.num_el_blk = nblocks

   -- process blocks
   local status = {}
   for kblock, def in ipairs(conn_def) do
      -- elements in block
      self.dims[def.dims[1]] = #blk_elem_maps[kblock]
      -- nodes per element
      self.dims[def.dims[2]] = #els[blk_elem_maps[kblock][1]]
      -- add also connectivity variables and their values
      local name = string.format('connect%d', kblock)
      self.vars[name] = def
      self.vals_fixed[name] = conn_blocks[kblock]
      -- status
      status[kblock] = 1
   end

   -- variables (other) and their values
   -- add elem_map variable
   self.vars.elem_map = {
      type = netCDF.NC.INT,
      dims = { 'num_elem' },
   }
   self.vals_fixed.elem_map = elem_map
   -- add eb_prop1 variable
   self.vars.eb_prop1 = {
      type = netCDF.NC.INT,
      dims = { 'num_el_blk' },
      atts = { name = 'ID' }
   }
   self.vals_fixed.eb_prop1 = ids
   -- eb_status
   self.vars.eb_status = {
      type = netCDF.NC.INT,
      dims = { 'num_el_blk' },
   }
   self.vals_fixed.eb_status = status
end
