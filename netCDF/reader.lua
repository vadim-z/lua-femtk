-- Native support of NetCDF in Lua
-- Reader module

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
local NCReaderClass = {}

-- shortcuts
local sunpack = string.unpack
local spacksize = string.packsize
--local tconcat = table.concat
--local tinsert = table.insert

-- padding and alignment
local function pad4len(len)
   return 3 - (len-1)%4
end

--local function pad4z(len)
--   return ('\0'):rep(pad4len(len))
--end

-- format strings for types
local type_fmt = {
   [ NC.BYTE ] = '>b',
   [ NC.CHAR ] = '>c1', -- ???
   [ NC.SHORT ] = '>i2',
   [ NC.INT ] = '>i4',
   [ NC.FLOAT ] = '>f',
   [ NC.DOUBLE ] = '>d',
}

local type_sz = {}
for t, s in pairs(type_fmt) do
   type_sz[t] = spacksize(s)
end

-- block for creating netCDF file and writing the header
do
   -- read 4-byte signed integer
   local function read_i4(f)
      return (sunpack('>i4', f:read(4)))
   end

   -- read 4-aligned variable length string
   local function read_vls(f)
      local len = read_i4(f)
      -- read padded string and extract substring
      return f:read(len + pad4len(len)):sub(1, len)
   end

   -- read value by format
   local function read_val(f, fmt, sz)
      return (sunpack(fmt,f:read(sz)))
   end

   -- read array of typed elements
   local function read_typevals(f, typ, n, pad)
      local len = type_sz[typ]*n
      if pad then
         len = len + pad4len(len)
      end
      local bin = f:read(len)
      local arr = {}
      local pos = 1
      for k = 1, n do
         arr[k], pos = sunpack(type_fmt[typ], bin, pos)
      end
      return arr
   end

   -- Elements of NetCDF-1/2 format
   -- FIXME: names of vars, dims and atts are not checked according to specification

   -- private functions
   -- read dim_list object
   local function read_dim_list(self)
      local f = self.f
      local dim_list = { map = {} }
      self.dim_list = dim_list

      local tag = read_i4(f)
      local ndims = read_i4(f)
      if tag == 0 then
         -- No dimensions
         return
      end
      assert(tag == NC.DIMENSION, 'Expected dimensions list')

      -- read and process the dimensions
      local fixed = true -- are all dimensions fixed?

      for kdim = 1, ndims do
         local dim_name = read_vls(f)
         local dim_size = read_i4(f)

         assert(dim_size >= 0, 'Invalid dimension ' .. dim_name)
         local rec = dim_size == 0
         assert(fixed or not rec,
                'More than one record dimension is not supported in classic NetCDF')
         fixed = fixed and not rec

         if rec then
            dim_list.rec_dim = kdim
         end
         local dim = { name = dim_name, size = dim_size }
         dim_list[kdim] = dim
         dim_list.map[dim_name] = dim
      end

      self.dim_list = dim_list
   end

   -- read (local) att_list object
   local function read_local_att_list(f)
      local att_list = { map = {} }

      local tag = read_i4(f)
      local natts = read_i4(f)
      if tag == 0 then
         -- No attributes
         return att_list
      end
      assert(tag == NC.ATTRIBUTE, 'Expected attributes list')

      -- read and process the attributes
      for katt = 1, natts do
         local att_name = read_vls(f)
         local att_type = read_i4(f)
         local att
         if att_type == NC.CHAR then
            -- read character attribute as string
            att = { string = read_vls(f) }
         else
            -- read as array
            local size = read_i4(f)
            att = read_typevals(f, att_type, size, true)
            att.name = att_name
         end

         att.name = att_name
         att.type = att_type
         att_list[katt] = att
         att_list.map[att_name] = att
      end

      return att_list
   end

   -- read att_list object
   local function read_att_list(self)
      self.att_list = read_local_att_list(self.f)
   end

   -- read var_list object
   local function read_var_list(self)
      local f = self.f
      local var_list = { map = {} }
      self.var_list = var_list

      local tag = read_i4(f)
      local nvars = read_i4(f)
      if tag == 0 then
         -- No variables
         return
      end
      assert(tag == NC.VARIABLE, 'Expected variables list')

      local n_rec_vars = 0 -- do we need to pack records? count record vars
      local rec_size = 0 -- total size of one record
      local packed_rec_size = 0

      for kvar = 1, nvars do
         -- read the variable
         local var_name = read_vls(f)
         local var_rank = read_i4(f)
         local var_dims = read_typevals(f, NC.INT, var_rank, false)
         local var_att_list = read_local_att_list(f)
         local var_type = read_i4(f)
         local var_vsize = read_i4(f)
         local var_begin = read_val(f, self.offset_fmt, self.offset_size)
         local var = {
            name = var_name,
            rank = var_rank,
            dims = var_dims,
            atts = var_att_list,
            type = var_type,
            vsize = var_vsize,
            begin = var_begin
         }

         -- process the variable
         local n_items = 1
         local n_items_s = 1
         for kdim = 1, var_rank do
            -- increment
            local dim_ix = var_dims[kdim] + 1
            var_dims[kdim] = dim_ix
            local locrec = dim_ix == self.dim_list.rec_dim
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
               n_items = n_items * self.dim_list[dim_ix].size
               if var_type == NC.CHAR and kdim < var_rank then
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
         var.real_vsize = n_items * type_sz[var_type]

         if var.rec then
            -- record
            n_rec_vars = n_rec_vars + 1
            rec_size = rec_size + var_vsize
            -- in case there's only one record var
            packed_rec_size = var.real_vsize
         end

         -- store var
         var_list[kvar] = var
         var_list.map[var_name] = var
      end

      -- pack records?
      if n_rec_vars == 1 then
         -- pack record variables
         rec_size = packed_rec_size
      end

      -- store results
      self.var_list = var_list
      self.rec_size = rec_size
   end

   -- read header; set important flags
   local function read_hdr(self)
      local f = self.f
      local sgn = f:read(4)

      if sgn == 'CDF\1' then
         self.offset_size = 4
         self.offset_fmt = '> i4'
      elseif sgn == 'CDF\2' then
         self.offset_size = 8
         self.offset_fmt = '> i8'
      else
         error('Unsupported netCDF format')
      end

      -- initialize number of records
      self.num_recs = read_i4(f)

      -- read dimensions, attributes, variables
      read_dim_list(self)
      read_att_list(self)
      read_var_list(self)
   end

   -- public method: open netCDF file, read the header
   function NCReaderClass:open(fname)
      self.f = assert(io.open(fname, 'rb'))
      read_hdr(self)
   end
end

--[=[
-- block for writing values to netCDF files
do
   -- expecting invariant:
   -- f:seek() == f_offs

   local OFFSET_NUMRECS = 4

   -- private functions
   -- add string zero-padded up to length
   local function add_string(t, s, len, zterm)
      -- truncate a string if required
      if zterm then
         -- force zero-termination, decrease max length by 1
         s = s:sub(1, len-1)
      else
         s = s:sub(1, len)
      end
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
         if rank == 0 or var.rec and rank ==1 then
            -- write scalar
            -- by definition, character rank-1 records go there too
            tinsert(bintbl, spack(fmt, data))
         elseif (rank == 1 or var.rec and rank == 2)
         and var.type == NC.CHAR and type(data) == 'string' then
            -- write string as 'scalar':
            -- rank-1 fixed variable or rank-2 record
            -- length is the size of the last dimension

            -- force null-termination in string arrays,
            -- according to section 6.29 of
            -- The NetCDF Fortran 77 Interface Guide:
            -- Variable-length strings should follow the C convention
            -- of writing strings with a terminating zero byte so that
            -- the intended length of the string can be determined when
            -- it is later read by either C or FORTRAN programs.
            local zterm = var.rec
            add_string(bintbl, data,
                       self.dim_list[var.dimids[rank]].size, zterm)
         else
            error('Table expected')
         end
      else
         if var.type == NC.CHAR and not data.array then
            -- flat array of strings
            assert(#data == var.n_items_s, 'Incorrect data length')
            -- size of the last dimension
            local len = self.dim_list[var.dimids[rank]].size
            -- force null-termination in string arrays, see above
            -- string arrays are record variables or
            -- fixed variables with more than one string item
            local zterm = var.rec or #data > 1
            for _, d in ipairs(data) do
               add_string(bintbl, d, len, zterm)
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

   -- write fixed/record var by id
   local function write_var_by_id(self, varid, data, nrec)
      local var = self.var_list[varid]
      local offs = var.begin
      if var.rec then
         assert(nrec,
                'Number of record missing when writing record variable')
         -- add required number of records
         offs = offs + (nrec-1)*self.rec_size
      end

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
      local pad = not (var.rec and self.pack_recs)
      write_data(self, var, data, pad)
   end

   -- update numrecs
   local function write_numrecs(self, numrecs_new)
      if not self.stream and self.numrecs ~= numrecs_new then
         -- do nothing in streaming mode
         -- or if the number of records haven't changed
         local offs = self.f:seek('set', OFFSET_NUMRECS)
         self.f:write(spack('>i4', numrecs_new))
         -- return to prev offset
         self.f:seek('set', offs)
      end
      -- update field, just in case
      self.numrecs = numrecs_new
   end

   -- public method: write a fixed or variable to netCDF file
   -- update number of records if required
   -- nrec may be missing in case of fixed variable
   function NCReaderClass:write_var(name, data, nrec)
      local varid = self.var_list.xref[name]
      assert(varid, 'Unknown variable ' .. name)
      write_var_by_id(self, varid, data, nrec)
      if self.var_list[varid].rec then
         local numrecs_new = math.max(self.numrecs, nrec)
         write_numrecs(self, numrecs_new)
      end
   end

   -- public method: write every fixed variable to netCDF file
   function NCReaderClass:write_fixed_vars(vars_data)
      for varid, var in ipairs(self.var_list) do
         if not var.rec then
            local data = vars_data[var.name]
            assert(data, 'Missing variable ' .. var.name)
            write_var_by_id(self, varid, data)
         end
      end
   end

   -- public method: write every record variable to netCDF file
   -- nrec may be missing in case of the next record
   function NCReaderClass:write_record(vars_data, nrec)
      nrec = nrec or self.numrecs + 1
      for varid, var in ipairs(self.var_list) do
         if var.rec then
            local data = vars_data[var.name]
            assert(data, 'Missing variable ' .. var.name)
            write_var_by_id(self, varid, data, nrec)
         end
      end
      write_numrecs(self, nrec)
   end

end
]=]

-- public method: close netCDF file
function NCReaderClass:close()
   self.f:close()
end

-- constructor
local function NCReader()
   return setmetatable({}, { __index = NCReaderClass } )
end

return {
   NC = NC,
   NCReader = NCReader,
}
