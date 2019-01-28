-- Native support of NetCDF in Lua

-- NetCDF constant namespace
local NC = {
   BYTE = 1,
   CHAR = 2,
   SHORT = 3,
   INT = 4,
   FLOAT = 5,
   DOUBLE = 6,

   DIMENSION = 10,
   VARIABLE = 11,
   ATTRIBUTE = 12,
}

-- File class
local NCFileClass = {}

-- shortcuts
local spack = string.pack
local spacksize = string.packsize
local tconcat = table.concat
local tinsert = table.insert

-- padding and alignment
local function pad4len(len)
   return 3 - (len-1)%4
end

local function pad4z(len)
   return ('\0'):rep(pad4len(len))
end

-- format strings for types
local type_fmt = {
   [ NC.BYTE ] = '>b',
   [ NC.CHAR ] = '>c1', -- ???
   [ NC.SHORT ] = '>i2',
   [ NC.INT ] = '>i4',
   [ NC.FLOAT ] = '>f',
   [ NC.DOUBLE ] = '>d',
}


-- block for creating netCDF file and writing the header
do
   -- constants
   local ABSENT = ('\0'):rep(8)

   -- Elements of NetCDF-1/2 format
   -- FIXME: names of vars, dims and atts are not checked according to specification

   -- private functions
   -- create dim_list object
   local function create_dim_list(self, dimlist)
      dimlist = dimlist or {}
      -- make cross reference
      local ncdims = { xref = {} }
      local kdim = 0
      local fixed = true -- are all dimensions fixed?

      for dim_name, dim_size in pairs(dimlist) do
         assert(dim_size >= 0, 'Invalid dimension ' .. dim_name)
         local rec = dim_size == 0
         assert(fixed or not rec,
                'More than one record dimension is not supported in classic NetCDF')
         fixed = fixed and not rec

         kdim = kdim + 1
         if rec then
            ncdims.rec_dim = kdim
         end
         ncdims[kdim] = { name = dim_name, size = dim_size }
         ncdims.xref[dim_name] = kdim
      end

      -- binary representation
      local bintbl = {}
      if kdim == 0 then
         -- dimensions are absent
         bintbl[1] = ABSENT
      else
         -- tag
         tinsert(bintbl, spack('> i4 i4', NC.DIMENSION, kdim))
         for _, dim in ipairs(ncdims) do
            -- write each dimension
            tinsert(bintbl, spack('>!4 s4 i4', dim.name, dim.size))
         end
      end
      ncdims.bin = tconcat(bintbl)

      self.dim_list = ncdims
   end

   -- create att_list object
   local function new_att_list(attlist)
      attlist = attlist or {}
      local natts = 0
      -- binary representation
      local bintbl = {}

      -- leave place for tag or absent
      bintbl[1] = false
      for att_name, att_v in pairs(attlist) do
         natts = natts + 1
         -- write each attribute
         if type(att_v) == 'string' then
            tinsert(bintbl, spack('>!4 s4 i4 s4 Xi4', att_name, NC.CHAR, att_v))
         else
            tinsert(bintbl, spack('>!4 s4 i4 i4', att_name, att_v.type, #att_v))
            local attlen = 0
            for k = 1, #att_v do
               local s = spack(type_fmt[att_v.type], att_v[k])
               tinsert(bintbl, s)
               attlen = attlen + #s
            end
            -- padding
            tinsert(bintbl, pad4z(attlen))
         end
      end

      if natts == 0 then
         -- attributes are absent
         bintbl[1] = ABSENT
      else
         -- place tag
         bintbl[1] = spack('> i4 i4', NC.ATTRIBUTE, natts)
      end

      attlist.bin = tconcat(bintbl)

      return attlist
   end

   local function create_att_list(self, attlist)
      self.att_list = new_att_list(attlist)
   end

   -- private functions for var_list object

   local szi4 = spacksize('>i4')

   -- Phase I: preprocess variables, determine header size
   local function prepare_var_defs(self, varlist)
      varlist = varlist or {}
      local kvar = 0
      local ncvars = { xref = {} }

      local vars_def_len =  2*szi4 -- size of variable definition;
      -- initial: tag and nvars
      local fixed_size = 0 -- total size of fixed variable data
      local rec_size = 0 -- total size of one record
      local n_rec_vars = 0 -- do we need to pack records? count record vars
      local packed_rec_size = 0

      for var_name, var_v in pairs(varlist) do
         local var = {
            name = var_name,
            dimids = {},
            val_fmt = type_fmt[var_v.type],
            type = var_v.type,
            rec = false, -- scalar variables are not records (by default)
            -- .....
         }

         -- ========= Process name and type ============
         -- include sizes of name, padded name length, type,
         -- ndims, vsize, offset
         vars_def_len = vars_def_len + 4*szi4 + self.offset_size +
            #var_name + pad4len(#var_name)

         -- size of one element of the variable
         local val_size = spacksize(var.val_fmt)

         -- ========= Process dimensions ============
         local dims = var_v.dims or {}
         var.rank = #dims
         local vsize = val_size
         local n_items = 1
         local n_items_s = 1
         for kdim, dim_name in ipairs(dims) do
            -- include size of dim  id
            vars_def_len = vars_def_len + szi4
            local dimid = self.dim_list.xref[dim_name]
            assert(dimid, 'Unknown dimension')
            var.dimids[kdim] = dimid
            local locrec = dimid == self.dim_list.rec_dim
            if kdim == 1 then
               -- is the variable record ?
               -- determine from the 1st dimension
               var.rec = locrec
            else
               assert(not locrec,
                      'Only the first dimension can be unlimited for variable '
                         .. var_name)
            end

            -- take the dimension into account
            if kdim > 1 or not locrec then
               vsize = vsize * self.dim_list[dimid].size
               n_items = n_items * self.dim_list[dimid].size
               if var.type == NC.CHAR and kdim < var.rank then
                  -- item is a number, or a string
                  -- string is written as one item
                  -- so we may exclude the last dimension for
                  -- character variables specified as
                  -- (an array of) strings
                  n_items_s = n_items
               end
            end
         end -- loop over dimensions

         var.n_items = n_items
         var.n_items_s = n_items_s

         -- Alignment; padding
         local real_vsize = vsize
         -- vsize is always rounded up to the multiple of 4
         var.vsize = vsize + pad4len(vsize)
         if var.rec then
            -- record
            n_rec_vars = n_rec_vars + 1
            rec_size = rec_size + vsize
            -- in case there's only one record var
            packed_rec_size = real_vsize
         else
            -- fixed var
            fixed_size = fixed_size + vsize
         end

         -- ========= Process attributes ============
         var.vatt_list = new_att_list(var_v.atts)
         -- add length of attribute list for this variable
         vars_def_len = vars_def_len + #var.vatt_list.bin

         -- add variable
         kvar = kvar + 1
         ncvars[kvar] = var
         ncvars.xref[var_name] = kvar

      end -- loop over variables

      -- pad records?
      self.pad_recs = n_rec_vars == 1

      if n_rec_vars == 1 then
         -- pack record variables
         rec_size = packed_rec_size
      end

      -- store results
      self.var_list = ncvars
      self.rec_size = rec_size
      self.fixed_size = fixed_size
      self.vars_def_len = vars_def_len
   end

   -- Phase II: calculate offsets, write binary representation
   local function var_list_binary(self)
      -- offset to header size
      local offs = self.hdr_size

      -- iterate over fixed variables
      for _, var in ipairs(self.var_list) do
         if not var.rec then
            var.begin = offs
            offs = offs + var.vsize
         end
      end

      -- offset points after all fixed variables

      -- iterate over record variables
      for _, var in ipairs(self.var_list) do
         if var.rec then
            var.begin = offs
            offs = offs + var.vsize
         end
      end

      -- note: if we have only one record variable, vsize may be greater than
      -- the real record length, so offs is incorrect after the loop above
      -- but we don't care

      -- now form binary representation
      local bintbl = {}
      local nvars = #self.var_list
      if nvars == 0 then
         -- variables are absent
         bintbl[1] = ABSENT
      else
         -- tag
         tinsert(bintbl, spack('> i4 i4', NC.VARIABLE, nvars))
         for _, var in ipairs(self.var_list) do
            -- write name and rank
            tinsert(bintbl, spack('>!4 s4 i4', var.name, var.rank))
            -- write dimension ids
            for _, dimid in ipairs(var.dimids) do
               tinsert(bintbl, spack('>i4', dimid-1))
            end
            -- write attributes
            tinsert(bintbl, var.vatt_list.bin)
            -- write type and size
            tinsert(bintbl, spack('> i4 i4', var.type, var.vsize))
            -- write offset
            tinsert(bintbl, spack(self.offset_fmt, var.begin))
         end
      end

      self.var_list.bin = tconcat(bintbl)
      assert(#self.var_list.bin == self.vars_def_len,
             'Internal error: variables definition length mismatch')
   end

   -- create header; set important flags
   local function create_hdr(self, ncdef)
      local sgn
      -- choose format
      if ncdef.fmt == 1 then
         self.offset_size = 4
         self.offset_fmt = '> i4'
         sgn = 'CDF\1'
      elseif ncdef.fmt == 2 then
         self.offset_size = 8
         self.offset_fmt = '> i8'
         sgn = 'CDF\2'
      else
         error('Unsupported netCDF format ' .. ncdef.fmt)
      end

      -- initialize number of records
      self.stream = ncdef.stream
      if ncdef.stream then
         self.numrecs = -1 -- special value
      else
         self.numrecs = 0
      end
      local numrecs_bin = spack('>i4', self.numrecs)

      -- process dimensions, attributes, variables
      create_dim_list(self, ncdef.dims)
      create_att_list(self, ncdef.atts)
      prepare_var_defs(self, ncdef.vars)

      -- calculate header size according to binary representation
      local hdr_size_real = #sgn + #numrecs_bin + #self.dim_list.bin + #self.att_list.bin +
         self.vars_def_len

      -- header size with user requirements
      self.hdr_size = math.max(hdr_size_real, ncdef.hdr_size_min or 0)

      -- finalize variable definitions, calculate offsets
      var_list_binary(self)

      -- header padding
      local hdr_pad = ('\0'):rep(self.hdr_size - hdr_size_real)

      -- create header
      self.hdr = sgn .. numrecs_bin .. self.dim_list.bin .. self.att_list.bin ..
         self.var_list.bin .. hdr_pad
   end

   -- public method: create netCDF file, write the header
   function NCFileClass:create(fname, ncdef)
      create_hdr(self, ncdef)
      self.f = assert(io.open(fname, 'wb'))
      assert(self.f:write(self.hdr))
      self.f_offs = #self.hdr
   end
end

-- block for writing values to netCDF files
do
   -- expecting invariant:
   -- f:seek() == f_offs

   local OFFSET_NUMRECS = 4

   -- private functions
   -- add string zero-padded up to length
   local function add_string(t, s, len)
      tinsert(t, s)
      tinsert(t, ('\0'):rep(len - #s))
   end

   -- write block of data to the current position
   local function write_data(self, var, data, pad)
      local bintbl = {}
      local fmt = var.val_fmt
      local rank = var.rank

      -- type/rank correspondence:
      -- */0 <--> scalar data
      -- char/1 <--> string
      -- */>0 <--> flat table

      if type(data) ~= 'table' then
         -- scalar cases
         if var.rank == 0 then
            -- write scalar
            tinsert(bintbl, spack(fmt, data))
         elseif (rank == 1 or var.rec and rank == 2)
         and var.type == NC.CHAR and type(data) == 'string' then
            -- write string as 'scalar':
            -- rank-1 fixed variable or rank-2 record
            -- length is the size of the last dimension
            add_string(bintbl, data,
                       self.dim_list[var.dimids[rank]].size)
         else
            error('Table expected')
         end
      else
         if var.type == NC.CHAR and not data.array then
            -- flat array of strings
            assert(#data == var.n_items_s, 'Incorrect data length')
            -- size of the last dimension
            local len = self.dim_list[var.dimids[rank]].size
            for _, d in ipairs(data) do
               add_string(bintbl, d, len)
            end
         else
            -- flat array of scalars
            assert(#data == var.n_items, 'Incorrect data length')
            for _, d in ipairs(data) do
               tinsert(bintbl, spack(fmt, d))
            end
         end
      end

      -- write it
      local bin = tconcat(bintbl)
      local padstr = ''
      if pad then
         padstr = pad4z(#bin)
      end
      self.f:write(bin, padstr)
      self.f_offs = self.f_offs + #bin + #padstr
   end

   -- write fixed var by id
   local function write_var_by_id(self, varid, data)
      local var = self.var_list[varid]
      assert(not var.rec,
             'Only fixed vars are written with write_var_...')
      local offs = var.begin
      if self.stream then
         -- streaming mode, no seek
         assert(self.f_offs == offs,
                'Invalid order of writes in the streaming mode')
      else
         -- seek
         self.f:seek('set', offs)
         self.f_offs = offs
      end
      -- pad fixed vars
      write_data(self, var, data, true)
   end

   -- public method: write a fixed variable to netCDF file
   function NCFileClass:write_var(name, data)
      local varid = self.var_list.xref[name]
      assert(varid, 'Unknown variable')
      write_var_by_id(self, varid, data)
   end

   -- public method: write every fixed variable to netCDF file
   function NCFileClass:write_vars(vars_data)
      for varid, var in ipairs(self.var_list) do
         if not var.rec then
            local data = vars_data[var.name]
            assert(data, 'Variable missing')
            write_var_by_id(self, varid, data)
         end
      end
   end

   -- update numrecs
   local function write_numrecs(self)
      if not self.stream then
         -- do nothing in streaming mode
         local offs = self.f:seek('set', OFFSET_NUMRECS)
         self.f:write(spack('>i4', self.numrecs))
         -- return to prev offset
         self.f:seek('set', offs)
      end
   end

end

-- public method: close netCDF file
function NCFileClass:close()
   self.f:close()
end

-- constructor
local function NCFile()
   return setmetatable({}, { __index = NCFileClass } )
end

return {
   NC = NC,
   NCFile = NCFile,
}
