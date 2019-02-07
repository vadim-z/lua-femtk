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
--[[
   self.plist = {}
   self.stepmap = {}
   self.nrecstep = 0
]]
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
      local rname = deblank(rec:sub(1, 18))
      local qa = qa_codes[rname]
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
      elseif xtra_u_records[rname] then
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

function Exo2_writer_class:rec1P(rec)
--   table.insert(self.plist, rec)
end

function Exo2_writer_class:rec100C(blk)
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

function Exo2_writer_class.rec9999(self)
   io.stderr:write('FRD file processed.\n')
   self.f:close()
end

return {
   Exo2_writer = Exo2_writer,
}
