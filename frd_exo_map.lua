local exo2s = require('exo2s')
local readfix = require('readfix53')

-- aux functions
local rdr = readfix.fixed_reader
local ck = readfix.check_val
local ckne = readfix.check_val_nonempty
local deblank = readfix.deblank

-- EXODUS II mapper/writer class
local Exo2_writer_class = {}

-- constructor
local function Exo2_writer(filename)
   return setmetatable({}, { __index = Exo2_writer_class } ):init(filename)
end

-- initialization
function Exo2_writer_class:init(filename)
   self.filename = filename
   return self
end

-- record processors
function Exo2_writer_class:rec1C(_)
   -- initial record
   self.f = exo2s.Exo2File()
   self.f:init(self.filename)

   -- initialize internal state variables
   self.title = ''
   self.title_expected = true
   self.qa= {}
   self.qa_nrecs = 0
   self.mats = {}
   self.nodes = false
   self.elts = false
   self.glob_vars = {}
   self.saved_glob_vals = nil
   self.saved_time = nil
   self.plist = {}
   self.node_vars = {}
   self.map_node_vars = {}
   self.saved_node_vals = {} -- FIXME FIXME
   self.nrec = 0
   self.stepmap = {}
end

do
   local qa_codes = {
      DATE = { key = 'date', rdr = rdr('*18 A20') },
      TIME = { key = 'time', rdr = rdr('*18 A8') },
      PGM = { key = 'code', rdr = rdr('*18 A48') },
      VERSION = { key = 'ver', rdr = rdr('*18 A40') },
   }

   local rdr_UMAT = rdr('*3 I5 A58')

   local xtra_u_records = {
      USER = true,
      HOST = true,
      COMPILETIME = true,
      DIR = true,
      DBN = true,
   }

   function Exo2_writer_class:rec1U(rec)
      local urec = false

      -- Try to parse QA or MAT records first
      -- only if at least one line of heading is read
      local uname = deblank(rec:sub(1, 18))
      local qa = qa_codes[uname]
      if qa then
         -- QA record
         if self.qa[qa.key] then
            -- redefining element of QA record
            io.stderr:write('Warning: Redefining QA record ', qa.key, '\n')
         else
            -- new element of QA record
            self.qa_nrecs = self.qa_nrecs + 1
         end
         local val = deblank(qa.rdr(rec))
         self.qa[qa.key] = val
         if self.qa_nrecs == 4 then
            -- send QA records to EXODUS II
            self.f:add_qa(self.qa)
            -- reset QA
            self.qa= {}
            self.qa_nrecs = 0
         end
         urec = true
      elseif rec:sub(1, 3) == 'MAT' then
         -- parse MAT record
         local id, mat = rdr_UMAT(rec)
         ck(id, 'Material id')
         mat = ckne(deblank(mat), 'Material')
         self.mats[id] = mat
         urec = true
      elseif xtra_u_records[uname] then
         -- known and ignored record, switch state nevertheless
         urec = true
      elseif self.title_expected then
         -- part of the title
         self.title = self.title .. deblank(rec)
      else
         -- no part of title and completely unknown record
         io.stderr:write('Ignoring unknown 1U record: ', rec, '\n')
         -- no effect on title, since title_expected is obviously false here
      end

      if self.title_expected and urec then
         -- switch from title to records mode
         self.title_expected = false
         -- send title
         self.f:define_title(self.title)
      end
   end
end

function Exo2_writer_class:rec2C(rec)
   if self.nodes then
      io.stderr:write('Multiple 2C node blocks; redefining nodes\n')
   else
      self.nodes = true
   end
   self.f:define_nodes(rec)
end

do
   -- FRD elements definitions in EXODUS II terms
   -- according to CGX and EXODUS II guides, the order of nodes is the same
   -- no mapping required
   local eldefs = {
      -- 8-nodes hex
      { nodes = 8, name = 'HEX' },
      -- 6-nodes wedge
      { nodes = 6, name = 'WEDGE' },
      -- 4-nodes tetra
      { nodes = 4, name = 'TETRA' },
      -- 20-nodes hex
      { nodes = 20, name = 'HEX' },
      -- 15-nodes wedge
      { nodes = 15, name = 'WEDGE' },
      -- 10-nodes tetra
      { nodes = 10, name = 'TETRA' },
      -- 3-nodes triangle
      { nodes = 3, name = 'TRIANGLE' },
      -- 6-nodes triangle
      { nodes = 6, name = 'TRIANGLE' },
      -- 4-nodes quad
      { nodes = 4, name = 'QUAD' },
      -- 8-nodes quad
      { nodes = 8, name = 'QUAD' },
      -- 2-node beam
      { nodes = 2, name = 'BEAM' },
      -- 3-node beam
      { nodes = 2, name = 'BEAM' },
   }

   function Exo2_writer_class:rec3C(rec)
      if self.elts then
         io.stderr:write('Multiple 3C element blocks; redefining elements\n')
      else
         self.elts = true
      end

      local elts = {}
      for k, elt in ipairs(rec) do
         -- some mapping of elements
         local def = assert(eldefs[elt.type], 'Unknown element type')
         assert(#elt.nodes == def.nodes,
                'Type of element inconsistent with the number of nodes')
         elts[k] = elt.nodes
         elts[k].type = def.name
         elts[k].id = elt.material
      end

      self.f:define_els(elts, self.mats)
   end
end

do
   -- significant 1P records
   local p_records = {
      STEP = { false, 'LOAD_INCR', 'LOAD_STEP',
               rdr = rdr('*18 I12 I12 I12') },
      GK = { 'GK', rdr = rdr('*18 E12') },
      HID = { 'HID', rdr = rdr('*18 I12') },
      AX = { 'AX1', 'AX2', 'AX3', 'AX4', 'AX5', 'AX6',
             rdr = rdr('*18 E12 E12 E12 E12 E12 E12') },
      GM = { rdr = rdr('*18 E12') },
      SUBC = { rdr = rdr('*18 I12') },
      MODE = { 'MODE', rdr = rdr('*18 I12') },
   }

   function Exo2_writer_class:rec1P(rec)
      local pname = deblank(rec:sub(1, 18))
      local pdef = p_records[pname]
      if pdef then
         local vals = { pdef.rdr(rec) }
         for k, name in ipairs(pdef) do
            if name then
               -- determine names of global vars before 1st 100C block
               if self.nrec == 0 then
                  table.insert(self.glob_vars, name)
               end
               self.plist[name] = vals[k]
            end
         end
      else
         io.stderr:write('Ignoring unknown 1P record: ', rec, '\n')
      end
   end

end

local function commit_saved(self)
   -- write saved values
   assert(self.saved_glob_vals and
             self.saved_node_vals and
             self.saved_time and
             self.nrec == 1,
          'Internal error: unexpected commit')

   -- time
   self.f:write_time_step(self.nrec, self.saved_time)

   -- global variables
   self.f:write_glob_vars(self.nrec, self.saved_glob_vals)

   -- node variables
   for k, var in ipairs(self.node_vars) do
      self.f:write_node_var(self.nrec, var, self.saved_node_vals[k])
   end

   -- cleanup
   self.saved_time = nil
   self.saved_glob_vals = nil
   self.saved_node_vals = nil
end

do

--[[
      assert(self.


   if not self.vars_defined@ then
      -- define global and nodal variables
      for _, var in ipairs(self.node_vars) do
         self.f:define_node_var(var)
      end
      self.vars_defined@ = true
      -- save accumulated values of node variables
      for k, var in ipairs(self.node_vars) do
         self.f:write_node_var(self.nrec, var, self.saved_node_vals[k])
      end
   end
   -- save accumulated values of global variables
   self.f:write_glob_vars(self.nrec, self.saved_glob_vals)
end
]]--
   local function first_step(self, blk)
      -- actions at the 1st step

      -- the 1st 100C block
      -- global variables are ready to be defined
      self.f:define_glob_vars(self.glob_vars)
      -- plist contains values to write later, save them
      self.saved_glob_vals = self.plist
      -- save time
      self.saved_time = blk.val
      -- add attributes related to analysis
      local info = string.format('Analysis type: %s %d',
                                 blk.analysis, blk.type)
      self.f:add_info(info)
   end

   local tensor_ord = {
      { 1, 4, 5 },
      { 4, 2, 6 },
      { 5, 6, 3 } }

   local vec_suf = { 'X', 'Y', 'Z' }
   local t2_suf = { 'XX', 'YY', 'ZZ', 'XY', 'XZ', 'YZ' }

   local function map_subcomp(comp)
      -- find suffix and index of a subcomponent
      local typ = comp.type
      local name = comp.name
      local ix, suf
      if typ == 1 then
         -- scalar
         ix = 1
         suf = ''
      elseif typ == 2 then
         -- vector
         ix = comp.ind1
         suf = '_' .. name:sub(1, -2) .. vec_suf[ix]
      elseif typ == 4 then
         -- (symmetric?) 2-tensor
         ix = tensor_ord[comp.ind1][comp.ind2]
         suf = '_' .. name:sub(1, -3) .. t2_suf[ix]
      elseif typ == 12 then
         -- amp/phase vector
         ix = comp.ind1
         local kc = 1 + (ix-1)%3
         suf = '_' .. name:sub(1, -2) .. vec_suf[kc]
      elseif typ == 14 then
         -- amp/phase 2-symtensor
         ix = tensor_ord[comp.ind1][comp.ind2]
         if comp.name:sub(1, 3) == 'MAG' then
            ix = ix + 0
         elseif comp.name:sub(1, 3) == 'PHA' then
            ix = ix + 6
         else
            error('Bad component name for variable type 14: ', comp.name)
         end
         local kc = 1 + (ix-1)%6
         suf = '_' .. name:sub(1, -3) .. t2_suf[kc]
      else
         error('Unknown variable type: ', typ)
      end
      return ix, suf
   end

--[[

   local function assign_block(self, varblk)
      -- assign FRD variable block to EXODUS II model
      -- define names and map of node variables

      -- create components map
      local map = self.map_node_vars
      local base = #map
      for k = 1, varblk.ncomps do
         local comp = varblk[k]
         local typ = comp.type
         if typ == 1 then
            -- scalar
            map[base+1] = k
         elseif typ == 2 or typ == 12 then
            -- vector or amp/phase vector
            map[base+comp.ind1] = k
         elseif typ == 4 then
            -- (symmetric?) 2-tensor
            local eord = tensor_ord[comp.ind1][comp.ind2]
            map[base+eord] = k
         elseif typ == 14 then
            -- amp/phase 2-symtensor
            local eord = tensor_ord[comp.ind1][comp.ind2]
            if comp.name:sub(1, 3) == 'MAG' then
               eord = eord + 0
            elseif comp.name:sub(1, 3) == 'PHA' then
               eord = eord + 6
            else
               error('Bad component name for variable type 14: ', comp.name)
            end
            map[base+eord] = k
         else
            error('Unknown variable type: ', typ)
         end
      end

      -- iterate over mapped components, collect names
      for k, kcomp in ipairs(map) do
         -- construct name
         local typ = varblk[kcomp].typ
         local name = varblk[kcomp].name
         local suf
         if typ == 1 then
            suf = ''
         elseif typ == 2 then
            suf = '_' .. name:sub(1, -2) .. vec_suf[k]
         elseif typ == 4 then
            suf = '_' .. name:sub(1, -3) .. t2_suf[k]
         elseif typ == 12 then
            local kc = 1 + (k-1)%3
            suf = '_' .. name:sub(1, -2) .. vec_suf[kc]
         elseif typ == 14 then
            local kc = 1 + (k-1)%6
            suf = '_' .. name:sub(1, -3) .. t2_suf[kc]
         end

         table.insert(self.node_vars, varblk.name .. suf)
      end

   end
]]
   function Exo2_writer_class:rec100C(blk)
      local nstp = blk.nstep
      local blk_nrec = self.stepmap[nstp]
      -- register step if required
      if not blk_nrec then
         -- new step
         if self.nrec == 0 then
            first_step(self, blk)
         elseif self.nrec == 1 then
            -- commit saved data
            commit_saved(self)
         end

         self.nrec = self.nrec + 1
         blk_nrec = self.nrec
         self.stepmap[nstp] = blk_nrec

         -- write global variables each new step
         if self.nrec > 1 then
            self.f:write_time_step(self.nrec, blk.val)
            self.f:write_glob_vars(self.nrec, self.plist)
         end

      end

      self.plist = {}
      if self.nrec == 1 then
         -- definition phase
--         assign_block(self, blk.var)

      end

--[[
   -- add 1P records reference
   blk.P = self.plist
   self.plist = {}

   local nstp = blk.nstep
   local istp = self.stepmap[nstp]
   -- register step if required
   if not istp then
      self.nrecstep = self.nrecstep + 1
      istp = self.nrecstep
      self.stepmap[nstp] = istp
   end
   -- istp points to number of output step
   -- where the block is stored
   self.frd[istp] = self.frd[istp] or {}
   table.insert(self.frd[istp], blk)
]]
      io.stderr:write(string.format(
                         'Read block %s step %d\n',
                         blk.var.name, blk.nstep))
   end
end

function Exo2_writer_class.rec9999(self)
   if self.nrec == 1 then
      commit_saved(self)
   end
   io.stderr:write('FRD file processed.\n')
   self.f:close()
end

return {
   Exo2_writer = Exo2_writer,
}
