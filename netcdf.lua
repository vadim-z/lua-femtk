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

-- Elements of NetCDF-1/2 format
-- FIXME: names of vars, dims and atts are not checked according to specification
do
   -- File class
   local NCFileClass = {}

   -- shortcuts
   local spack = string.pack
   local spacksize = string.packsize
   local tconcat = table.concat
   local tinsert = table.insert

   -- constants
   local ABSENT = ('\0'):rep(8)

   -- format strings for types
   local type_fmt = {
      [ NC.BYTE ] = '>b',
      [ NC.CHAR ] = '>B', -- ???
      [ NC.SHORT ] = '>i2',
      [ NC.INT ] = '>i4',
      [ NC.FLOAT ] = '>f',
      [ NC.DOUBLE ] = '>d',
   }

   -- private functions for var_list object

   -- create dim_list object
   local function create_dim_list(self, dimlist)
      -- make cross reference, check for record dimension
      local ncdims = { xref = {} }
      local ndims = #dimlist
      local fixed = true -- are all dimensions fixed?
      for k = 1, ndims do
         local dim = dimlist[k]
         assert(dim.name and dim.size and dim.size >= 0, 'Invalid dimension ' .. k)
         local rec = dim.size == 0
         assert(fixed or not rec,
                'More than one record dimension is not supported in classic NetCDF')
         fixed = fixed and not rec
         if rec then
            ncdims.rec_dim = k
         end
         ncdims[k] = dim
         ncdims.xref[dim.name] = k
      end

      -- binary representation
      local bintbl = {}
      if ndims == 0 then
         -- dimensions are absent
         bintbl[1] = ABSENT
      else
         -- tag
         tinsert(bintbl, spack('> i4 i4', NC.DIMENSION, ndims))
         for k = 1, ndims do
            local dim = dimlist[k]
            -- write each dimension
            tinsert(bintbl, spack('>!4 s4 i4', dim.name, dim.size))
         end
      end
      ncdims.bin = tconcat(bintbl)

      self.dim_list = ncdims
   end

   local function pad4len(len)
      return 3 - (len-1)%4
   end

   local function pad4z(len)
      return ('\0'):rep(pad4len(len))
   end

   -- create att_list object
   local function new_att_list(attlist)
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
            tinsert(pad4z(attlen))
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
      local nvars = 0
      local ncvars = {}

      local vars_def_len =  2*szi4 -- size of variable definition;
      -- initial: tag and nvars
      local fixed_size = 0 -- total size of fixed variable data
      local rec_size = 0 -- total size of one record
      local n_rec_vars = 0 -- do we need to pack records? count record vars
      local packed_rec_size = 0

      for var_name, var_v in pairs(varlist) do
         nvars = nvars + 1
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
         var.rank = #var_v.dims
         local vsize = val_size
         for kdim, dim_name in ipairs(var_v.dims) do
            -- include size of dim  id
            vars_def_len = vars_def_len + szi4
            local dimid = self.dim_list.xref[dim_name]
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
            end
         end -- loop over dimensions

         -- Alignment; padding
         local real_vsize = vsize
         -- vsize is always rounded up to the multiple of 4
         var.vsize = vsize + pad4len(vsize)
         if var.rec then
            -- record
            n_rec_vars = n_rec_vars + 1
            rec_size = rec_size + vsize
            -- in case there's only one record var
            packed_rec_size = packed_rec_size + real_vsize
         else
            -- fixed var
            fixed_size = fixed_size + vsize
         end

         -- ========= Process attributes ============
         var.vatt_list = new_att_list(var_v.atts)
         -- add length of attribute list for this variable
         vars_def_len = vars_def_len + #var.vatt_list.bin

         -- add variable
         ncvars[nvars] = var
      end -- loop over variables

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
      -- header size according to binary representation
      local hdr_size_bin = #self.sgn + szi4 + #self.dim_list.bin + #self.att_list.bin +
         self.vars_def_len

      -- header size with user requirements
      local offs = math.max(hdr_size_bin, self.hdr_size_min or 0)

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


   -- create var_list object
   local function create_var_list(self, varlist)
      prepare_var_defs(self, varlist)
      var_list_binary(self)
   end
--[[
      -- FIXME: too long function
      local nvars = 0
      local ncvars = {}
      -- binary representation

      local szi4 = spacksize('>i4')
      local vars_def_len =  2*szi4 -- size of variable definition;
      -- initial: tag and nvars
      local var_def_len = 0 -- total length of variables DEFINITION
      local fixed_size = 0 -- total size of fixed variable data
      local rec_size = 0 -- total size of one record
      local n_rec_vars = 0 -- do we need to pack records? count record vars
      local packed_rec_size = 0

      -- Phase I: preprocess variables, determine header size
      for var_name, var_v in pairs(varlist) do
         nvars = nvars + 1
         local var = {
            name = var_name,
            dimids = {},
            val_fmt = type_fmt[var_v.type],
            type = var_v.type,
            rec = false, -- scalar variables are not records (by default)
            -- .....
         }

         -- ========= Process name and type ============
         -- include sizes of name, name length, type,
         -- ndims, vsize, offset
         vars_def_len = vars_def_len + 4*szi4 + #var_name + self.offset_size

         -- size of one element of the variable
         local val_size = spacksize(var.val_fmt)

         -- ========= Process dimensions ============
         var.rank = #var_v.dims
         local vsize = val_size
         for kdim, dim_name in ipairs(var_v.dims) do
            -- include size of dim  id
            vars_def_len = vars_def_len + szi4
            local dimid = self.dim_list.xref[dim_name]
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
            end
         end -- loop over dimensions

         -- Alignment; padding
         local real_vsize = vsize
         -- vsize is always rounded up to the multiple of 4
         var.vsize = vsize + 3 - (vsize-1)%4
         if var.rec then
            -- record
            n_rec_vars = n_rec_vars + 1
            rec_size = rec_size + vsize
            -- in case there's only one record var
            packed_rec_size = packed_rec_size + real_vsize
         else
            -- fixed var
            fixed_size = fixed_size + vsize
         end

         -- ========= Process attributes ============
         var.vatt_list = self:create_att_list(var_v.atts)
         -- add length of attribute list for this variable
         vars_def_len = vars_def_len + #var.vatt_list.binary

         -- add variable
         ncvars[nvars] = var
      end -- loop over variables

      if n_rec_vars == 1 then
         -- pack record variables
         rec_size = packed_rec_size
      end

--]]


--[[


      -- leave place for tag or absent
      bintbl[1] = false
      for att_name, att_v in pairs(attlist) do
         natts = natts + 1
         -- write each attribute
         if type(att_v) == 'string' then
            tinsert(bintbl, spack('>s4 i4 s4', att_name, NC.CHAR, att_v))
         else
            tinsert(bintbl, spack('>s4 i4 i4', att_name, att_v.type, #att_v))
            for k = 1, #att_v do
               tinsert(bintbl, spack(type_fmt[att_v.type], att_v[k]))
            end
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
]]--


--[[
      -- constructor
      local function NCFile()
         return setmetatable({}, { __index = NCFileClass } )
      end

]]--
end
