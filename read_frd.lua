local R = require('readfix53')

local rdr = R.fixed_reader
local ck = R.check_val
local ckne = R.check_val_nonempty
local deblank = R.deblank

local function read_node_block(f, fmt, sz_blk, ncomps)
   local blk = {}
   -- allocate components array
   for k = 1, ncomps do
      blk[k] = {}
   end
   local recfmt1, recfmt2, codefmt
   codefmt = rdr('*1 I2')
   -- read nodal data block
   if fmt == 0 then
      recfmt1 = rdr('*1 I2 I5' .. string.rep('E12', 6))
      recfmt2 = rdr('*1 I2 *5' .. string.rep('E12', 6))
   elseif fmt == 1 then
      recfmt1 = rdr('*1 I2 I10' .. string.rep('E12', 6))
      recfmt2 = rdr('*1 I2 *10' .. string.rep('E12', 6))
   elseif fmt == 2 then
      error('Unsupported fmt')
   else
      error('Unknown fmt')
   end

   local code, nread = 0, 0

   local node, ndata

   while code ~= -3 do
      local l = f:read()

      if not l then
         error('Record expected')
      end
      code = ck(codefmt(l), 'code')
      if code == -1 then
         -- new data line
         local A = { recfmt1(l) }
         node = ck(A[2], 'node number')
         ndata = #A - 2
         for k = 1, ndata do
            blk[k][node] = ck(A[2+k], 'value')
         end
         nread = nread + 1
      elseif code == -2 then
         -- continuation line
         local A = { recfmt2(l) }
         -- expecting ndata and node to be defined
         local cont = #A - 1
         for k = 1, cont do
            blk[ndata+k][node] = ck(A[1+k], 'value')
         end
         ndata = ndata + cont
      elseif code ~= -3 then
         error(string.format('Unknown record code %d in block', code))
      end
   end

   -- check amount of lines we have read
   if sz_blk ~= nread then
      error(string.format('Expected %d lines, read %d', sz_blk, nread))
   end

   return blk
end

local function read_el_block(f, fmt, sz_blk)
   -- Read element definition block
   local blk = {}
   local recfmt1, recfmt2, codefmt
   codefmt = rdr('*1 I2')
   -- read nodal data block
   if fmt == 0 then
      recfmt1 = rdr('*1 I2 I5 I5 I5 I5')
      recfmt2 = rdr('*1 I2' .. string.rep('I5', 15))
   elseif fmt == 1 then
      recfmt1 = rdr('*1 I2 I10 I5 I5 I5')
      recfmt2 = rdr('*1 I2' .. string.rep('I10', 10))
   elseif fmt == 2 then
      error('Unsupported fmt')
   else
      error('Unknown fmt')
   end

   local code, nread = 0, 0

   local el, nnodes, el_def

   while code ~= -3 do
      local l = f:read()
      if not l then
         error('Record expected')
      end
      code = ck(codefmt(l), 'code')
      if code == -1 then
         -- new data line
         local A = { recfmt1(l) }
         el = ck(A[2], 'element number')
         el_def = {
            type = ck(A[3], 'value'),
            group = ck(A[4], 'value'),
            material = ck(A[5], 'value'),
            nodes = {},
         }
         blk[el] = el_def
         nnodes = 0
         nread = nread + 1
      elseif code == -2 then
         -- continuation line
         local A = { recfmt2(l) }
         -- expecting nnode, el and el_def be defined
         local cont = #A - 1
         for k = 1, cont do
            el_def.nodes[nnodes+k] = ck(A[1+k], 'node number')
         end
         nnodes = nnodes + cont
      elseif code ~= -3 then
         error(string.format('Unknown record code %d in block', code))
      end
   end

   -- check amount of lines we have read
   if sz_blk ~= nread then
      error(string.format('Expected %d lines, read %d', sz_blk, nread))
   end

   return blk
end

local function read_var_block(f)
   -- read variable definition block
   local blk = {}
   local codefmt = rdr('*1 I2')
   local recfmt4 = rdr('*1 I2 *2 A8 I5 I5')
   local recfmt5 = rdr('*1 I2 *2 A8 I5 I5 I5 I5 I5 A8')

   local ncomps, code

   local l = f:read()
   if not l then
      error('Record expected')
   end
   code = ck(codefmt(l), 'code')
   -- Read header
   if code == -4 then
      local _, nm, nc, irtype = recfmt4(l)
      blk.name = ckne(deblank(nm))
      ncomps = ck(nc, 'number of components')
      if (ck(irtype) ~= 1) then
         error('Unsupported nodal data type')
      end
   else
      error(string.format('Unexpected record code %d in block', code))
   end

   -- Read components
   local ncomps_provided = 0
   for k = 1, ncomps do
      l = f:read()
      if not l then
         error('Record expected')
      end
      code = ck(codefmt(l), 'code')
      if code == -5 then
         local _, nm, _, typ, i1, i2, exist, cname = recfmt5(l)
         local cblk = {
            name = ckne(deblank(nm)),
            type = ck(typ),
            ind1 = i1,
            ind2 = i2,
            exist = exist or 0,
            cname = deblank(cname),
         }

         -- make cross-references
         blk[k] = cblk
         blk[cblk.name] = cblk

         -- count provided components
         if cblk.exist ~= 1 then
            ncomps_provided = ncomps_provided + 1
         end
      else
         error(string.format('Unexpected record code %d in block', code))
      end
   end -- loop over components
   blk.ncomps = ncomps_provided

   return blk
end

local function read_frd(fname, writer)
   -- Read FRD data file produced by CalculiX

   local keycodefmt = rdr('*1 I4 A1')
   local recfmt1C = rdr('*1 *4 *1 A6')
   local recfmt1UP = rdr('*1 *4 *1 A66')
   local recfmt23C = rdr('*1 *4 *1 *18 I12 *37 I1')
   local recfmt100C = rdr('*1 *4 *1 A6 E12 I12 A20 I2 I5 A10 I2')

   local key = 0

   local f = assert(io.open(fname, 'r'), 'file not found')

   while key ~= 9999 do
      local l = assert(f:read(), 'Record expected')
      local A = { keycodefmt(l) }
      key = assert(A[1], 'Invalid record format')
      local code = A[2]

      if key == 1 and code == 'C' then
         -- 1C record, model name
         writer:rec1C(recfmt1C(l))
      elseif key == 1 and code == 'U' then
         -- 1U record, user metadata
         writer:rec1U(recfmt1UP(l))
      elseif key == 2 and code == 'C' then
         -- 2C record, node coordinates
         local nnodes, fmt = recfmt23C(l)
         ck(nnodes, 'number of nodes')
         ck(fmt, 'format')
         writer:rec2C(read_node_block(f, fmt, nnodes, 3))
      elseif key == 3 and code == 'C' then
         -- 3C record, element definitions
         local nelts, fmt = recfmt23C(l)
         ck(nelts, 'number of elements')
         ck(fmt, 'format')
         writer:rec3C(read_el_block(f, fmt, nelts))
      elseif key == 1 and code == 'P' then
         -- 1P record, results metadata
         writer:rec1P(recfmt1UP(l))
      elseif key == 100 and code == 'C' then
         -- 100C record, nodal result block
         local sname, val, nnodes, text, typ, nstp, analys, fmt =
            recfmt100C(l)

         --  read variable definitions
         local var = read_var_block(f)

         ck(nnodes, 'number of nodes')
         ck(fmt, 'format')

         -- read data
         local blk = read_node_block(f, fmt, nnodes, var.ncomps)

         -- add variable definition
         blk.var = var
         -- add intrinsic metadata
         blk.setname = sname
         blk.val = ck(val, 'step value')
         blk.text = text
         blk.type = ck(typ)
         blk.nstep = ck(nstp)
         blk.analysis = deblank(analys)

         writer:rec100C(blk)
      elseif key == 9999 then
         -- last record
         f:close()
         writer:rec9999()
      else
         error(string.format('Unknown record %d%c\n', key, code))
      end
   end
   return writer
end

-- simple table writer
local table_writer_class = {}

-- constructor
local function table_writer()
   return setmetatable({}, { __index = table_writer_class } )
end

-- record processors
function table_writer_class:rec1C(rec)
   -- initial record
   self.frd = {}
   self.frd.model_name = rec
   self.frd.user = {}
   self.plist = {}
   self.stepmap = {}
   self.nrecstep = 0
end

function table_writer_class:rec1U(rec)
   table.insert(self.frd.user, rec)
end

function table_writer_class:rec2C(rec)
   if self.frd.nodes then
      error('Multiple 2C node blocks are not supported')
   else
      self.frd.nodes = rec
   end
end

function table_writer_class:rec3C(rec)
   if self.frd.elts then
      error('Multiple 3C element blocks are not supported')
   else
      self.frd.elts = rec
   end
end

function table_writer_class:rec1P(rec)
   table.insert(self.plist, rec)
end

function table_writer_class:rec100C(blk)
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
   io.stderr:write(string.format(
                      'Read block %s step %d\n',
                      blk.var.name, blk.nstep))
end

function table_writer_class.rec9999(_)
   io.stderr:write('FRD file processed.\n')
end

return {
   read_frd = read_frd,
   table_writer = table_writer,
}
