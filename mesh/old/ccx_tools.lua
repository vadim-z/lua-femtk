local function calc_boundary_disp(mesh, E, blist)
   -- calculate boundary displacements given strains at infinity
   -- E are strains in Voigt notation, shear strain doubled

   -- calculate set of required boundaries
   local bset = {}
   for _, b in ipairs(blist) do
      bset[b] = true
   end

   -- all boundary nodes
   local bnodes = {}
   for _, set in ipairs(mesh.surf_n) do
      if bset[set.id] then
         for node, _ in pairs(set) do
            if node ~= 'id' then
               bnodes[node] = true
            end
         end
      end
   end

   local bdisp = {}
   for kn = 1, #mesh.nodes do
      if bnodes[kn] then
         -- displacements
         local x, y, z = table.unpack(mesh.nodes[kn])
         local ux = E[1]*x + 0.5*(E[6]*y + E[5]*z)
         local uy = E[2]*y + 0.5*(E[4]*z + E[6]*x)
         local uz = E[3]*z + 0.5*(E[5]*x + E[4]*y)
         table.insert(bdisp, { kn, ux, uy, uz } )
      end
   end
   mesh.bdisp = bdisp
end


return {
   calc_boundary_disp = calc_boundary_disp,
}

