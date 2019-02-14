-- Module to write simplified EXODUS II files
local netCDF = require('netCDF/writer')

local Exo2Class = {}

-- initialize general EXODUS II entities
local function define_gen(self, fp_type)
   local wsize
   if fp_type == 'float' then
      self.numtype = netCDF.NC.FLOAT
      wsize = 4
   elseif fp_type == 'double' then
      self.numtype = netCDF.NC.DOUBLE
      wsize = 8
   else
      error('Invalid floating point type: ', fp_type)
   end

   self.dims = {}
   self.dims.time_step = 0
   self.dims.four = 4
   self.dims.len_string = 33
   self.dims.len_line = 81
   self.atts = {}
   self.atts.version = { 2.02, type = netCDF.NC.FLOAT }
   self.atts.api_version = { 2.02, type = netCDF.NC.FLOAT }
   self.atts.floating_point_word_size = { wsize, type = netCDF.NC.INT }
   -- Large model file
   self.atts.file_size = { 1, type = netCDF.NC.INT }
   self.vars = {}
   self.vars.time_whole = {
      type = self.numtype,
      dims = { 'time_step' }
   }
   self.vals_fixed = {}
end

-- initialization method
function Exo2Class:init(fname, fp_type)
   define_gen(self, fp_type or 'double')
   self.filename = fname
end

function Exo2Class:define_title(title)
   assert(not self.NCfile, 'Unexpected title definition')
   self.atts.title = title
end

-- add QA records
function Exo2Class:add_qa(qa)
   assert(not self.NCfile, 'Unexpected QA records definition')
   local nqa = self.dims.num_qa_rec
   if nqa then
      -- add to existing variable
      self.dims.num_qa_rec = nqa + 1
   else
      -- create qa variable
      self.dims.num_qa_rec = 1
      self.vars.qa_records = {
         type = netCDF.NC.CHAR,
         dims = { 'num_qa_rec', 'four', 'len_string' }
      }
      self.vals_fixed.qa_records = {}
   end

   table.insert(self.vals_fixed.qa_records, qa.code)
   table.insert(self.vals_fixed.qa_records, qa.ver)
   table.insert(self.vals_fixed.qa_records, qa.date)
   table.insert(self.vals_fixed.qa_records, qa.time)
end

-- add information record
function Exo2Class:add_info(info)
   assert(not self.NCfile, 'Unexpected information record definition')
   local n = self.dims.num_info or 0
   n = n + 1
   self.dims.num_info = n

   if n == 1 then
      -- create info_records variable
      self.vars.info_records = {
         type = netCDF.NC.CHAR,
         dims = { 'num_info', 'len_line' }
      }
      self.vals_fixed.info_records = {}
   end
   table.insert(self.vals_fixed.info_records, info)
end

-- define nodes and related variables
function Exo2Class:define_nodes(nodes)
   assert(not self.NCfile, 'Unexpected nodes definition')
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
function Exo2Class:define_els(els, mats)
   assert(not self.NCfile, 'Unexpected elements definition')
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
   -- inverse map
   self.inv_elem_map_blk = {}
   self.inv_elem_map_loc = {}

   for k, el in ipairs(els) do
      local id = el.id
      blocks[id] = blocks[id] or {}
      local bkey = string.format('%s%d', el.type, #el)
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
   for kblk, map in ipairs(blk_elem_maps) do
      for kint, kext in ipairs(map) do
         table.insert(elem_map, kext)
         -- inverse map entry
         self.inv_elem_map_blk[kext] = kblk
         self.inv_elem_map_loc[kext] = kint
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

   -- add 'material' properties
   if mats then
      local kprop = 1
      for kmat, mat in pairs(mats) do
         kprop = kprop + 1 -- skip 1st property ID
         local name = string.format('eb_prop%d', kprop)
         self.vars[name] = {
            type = netCDF.NC.INT,
            dims = { 'num_el_blk' },
            atts = { name = mat }
         }

         -- truth table
         local ptbl = {}
         for kbl, id in ipairs(ids) do
            ptbl[kbl] = (id == kmat) and 1 or 0
         end
         self.vals_fixed[name] = ptbl
      end
   end

   -- eb_status
   self.vars.eb_status = {
      type = netCDF.NC.INT,
      dims = { 'num_el_blk' },
   }
   self.vals_fixed.eb_status = status
end

-- define node sets and related variables
function Exo2Class:define_nodesets(nsets, props)
   assert(not self.NCfile, 'Unexpected node sets definition')
   if #nsets == 0 then
      -- nothing to add
      return
   end
   -- add netCDF entities related to nsets
   -- dimensions
   self.dims.num_node_sets = #nsets

   -- create node lists and node sets properties
   local status = {}
   local prop_vals = {}
   local ids = {}
   for kprop = 1, #props do
      prop_vals[kprop] = {}
   end

   -- iterate over node sets
   for kset, nset in ipairs(nsets) do
      local list = {}
      -- process all nodes
      for kn = 1, self.dims.num_nodes do
         if nset[kn] and nset[kn] ~= 0 then
            table.insert(list, kn)
         end
      end
      -- create node sets dimensions and variables
      local dimname = string.format('num_nod_ns%d', kset)
      local varname = string.format('node_ns%d', kset)
      -- nodes in set
      self.dims[dimname] = #list

      self.vars[varname] = {
         type = netCDF.NC.INT,
         dims = { dimname },
      }
      self.vals_fixed[varname] = list

      -- node sets properties
      status[kset] = 1
      ids[kset] = assert(nset.id, 'Absent node set ID')
      for kprop, name_prop in ipairs(props) do
         prop_vals[kprop][kset] = assert(nset[name_prop],
                                     'Absent node set property ' .. name_prop)
      end
   end

   -- create extra variables
   -- add ns_prop1 variable
   self.vars.ns_prop1 = {
      type = netCDF.NC.INT,
      dims = { 'num_node_sets' },
      atts = { name = 'ID' }
   }
   self.vals_fixed.ns_prop1 = ids

   -- add other properties
   for kprop, name_prop in ipairs(props) do
      local name = string.format('ns_prop%d', kprop+1)
      self.vars[name] = {
         type = netCDF.NC.INT,
         dims = { 'num_node_sets' },
         atts = { name = name_prop }
      }
      self.vals_fixed[name] = prop_vals[kprop]
   end

   -- ns_status
   self.vars.ns_status = {
      type = netCDF.NC.INT,
      dims = { 'num_node_sets' },
   }
   self.vals_fixed.ns_status = status
end

-- add global variables
-- NB: given that
--     1) current netCDF Lua interface supports writing a variable or a record
--     blob _as a whole only_
--     2) EXODUS II model aggregates global variables in one blob
-- there is no point defining and writing global variables separately
function Exo2Class:define_glob_vars(varnames)
   assert(not self.NCfile, 'Unexpected global variables definition')

   if #varnames > 0 then
      -- create global variables
      self.dims.num_glo_var = #varnames
      self.vars.name_glo_var = {
         type = netCDF.NC.CHAR,
         dims = { 'num_glo_var', 'len_string' }
      }
      self.vars.vals_glo_var = {
         type = self.numtype,
         dims = { 'time_step', 'num_glo_var' }
      }
      self.vals_fixed.name_glo_var = {}

      for k, name in ipairs(varnames) do
         self.vals_fixed.name_glo_var[k] = name
      end
   end
end

-- add node variable
function Exo2Class:define_node_var(varname)
   assert(not self.NCfile, 'Unexpected node variable definition')
   local n = self.dims.num_nod_var or 0
   n = n + 1
   self.dims.num_nod_var = n
   local vals_name = string.format('vals_nod_var%d', n)

   if n == 1 then
      -- create names of node variables
      self.vars.name_nod_var = {
         type = netCDF.NC.CHAR,
         dims = { 'num_nod_var', 'len_string' }
      }
      self.vals_fixed.name_nod_var = {}
      self.map_node_var = {}
   end
   table.insert(self.vals_fixed.name_nod_var, varname)

   self.map_node_var[varname] = n

   -- create node variable
   self.vars[vals_name] = {
      type = self.numtype,
      dims = { 'time_step', 'num_nodes' }
   }

end

-- add ordered block of node variables
function Exo2Class:define_node_vars(varlist)
   for _, var in ipairs(varlist) do
      self:define_node_var(var)
   end
end

local function create_file(self)
   assert(not self.NCfile, 'File already created')
   self.NCfile = netCDF.NCWriter()
   self.NCfile:create(self.filename, self)

   -- write fixed variables
   for name, var in pairs(self.vals_fixed) do
      self.NCfile:write_var(name, var)
   end
end

function Exo2Class:write_time_step(kstep, val)
   if not self.NCfile then
      create_file(self)
   end
   self.NCfile:write_var('time_whole', val, kstep)
end

-- writing values of all global variables at once, see the note above
function Exo2Class:write_glob_vars(kstep, vars)
   if not self.NCfile then
      create_file(self)
   end

   local names = self.vals_fixed.name_glo_var
   if names then
      local vals = {}
      for k, name in ipairs(names) do
         vals[k] = assert(vars[name],
                          'Global variable ' .. name .. ' not found')
      end

      self.NCfile:write_var('vals_glo_var', vals, kstep)
   end
end

-- writing values of nodal variable
function Exo2Class:write_node_var(kstep, varname, vals)
   if not self.NCfile then
      create_file(self)
   end

   local k = assert(self.map_node_var[varname],
                    'Node variable ' .. varname .. ' not found')

   local vals_name = string.format('vals_nod_var%d', k)

   self.NCfile:write_var(vals_name, vals, kstep)
end

function Exo2Class:close()
   if not self.NCfile then
      create_file(self)
   end

   self.NCfile:close()
   self.NCfile = nil
end

-- constructor
local function Exo2File()
   return setmetatable({}, { __index = Exo2Class } )
end

return {
   Exo2File = Exo2File,
}
