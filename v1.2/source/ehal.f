c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     #################################################################
c     ##                                                             ##
c     ##  subroutine ehal3  --  buffered 14-7 vdw energy & analysis  ##
c     ##                                                             ##
c     #################################################################
c
c
c     "ehal3" calculates the buffered 14-7 van der Waals energy
c     and partitions the energy among the atoms
c
c
      subroutine ehal
      use energi
      use potent
      use vdwpot
      implicit none
      real*8 elrc
c
c     choose the method for summing over pairwise interactions
c
      if (use_vdwshort) then
        call ehalshort0c
      else if (use_vdwlong) then
        call ehallong0c
      else
        call ehal0c
      end if
c
c     apply long range van der Waals correction if desired
c
      if (use_vcorr) then
         call evcorr (elrc)
         ev = ev + elrc
      end if
      return
      end
c
c
c     ##############################################################
c     ##                                                          ##
c     ##  subroutine ehal0c  --  buffered 14-7 analysis via list  ##
c     ##                                                          ##
c     ##############################################################
c
c
c     "ehal0c" calculates the buffered 14-7 van der Waals energy
c     and also partitions the energy among the atoms using a
c     pairwise neighbor list
c
c
      subroutine ehal0c
      use atmlst
      use atoms
      use bound
      use couple
      use domdec
      use energi
      use inter
      use molcul
      use mutant
      use neigh
      use shunt
      use usage
      use vdw
      use vdwpot
      implicit none
      integer i,j,iglob,kglob,kbis
      integer ii,iv,it,iivdw,inl
      integer kk,kv,kt
      integer, allocatable :: iv14(:)
      real*8 e,eps,rdn
      real*8 rv,rv7
      real*8 xi,yi,zi
      real*8 xr,yr,zr
      real*8 rho,tau,taper
      real*8 scal,t1,t2
      real*8 rik,rik2,rik3
      real*8 rik4,rik5,rik7
      real*8, allocatable :: xred(:)
      real*8, allocatable :: yred(:)
      real*8, allocatable :: zred(:)
      real*8, allocatable :: vscale(:)
      logical proceed,usei
      logical muti,mutk,mutik
      character*10 mode
c
c
c     zero out the van der Waals energy and partitioning terms
c
      ev = 0.0d0
c
c     perform dynamic allocation of some local arrays
c
      allocate (iv14(n))
      allocate (xred(nbloc))
      allocate (yred(nbloc))
      allocate (zred(nbloc))
      allocate (vscale(n))
c
c     set arrays needed to scale connected atom interactions
c
      vscale = 1.0d0
      iv14 = 0
c
c     set the coefficients for the switching function
c
      mode = 'VDW'
      call switch (mode)
c
c     apply any reduction factor to the atomic coordinates
c
      do ii = 1, nvdwbloc
         iivdw = vdwglob(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         iv = ired(iglob)
         rdn = kred(iglob)
         xr = x(iglob) - x(iv)
         yr = y(iglob) - y(iv)
         zr = z(iglob) - z(iv)
         if (use_polymer) call image(xr,yr,zr)
         xred(i) = rdn*xr + x(iv)
         yred(i) = rdn*yr + y(iv)
         zred(i) = rdn*zr + z(iv)
      end do
c
c
c     find the van der Waals energy via neighbor list search
c
      do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         iv = ired(iglob)
         it = jvdw(iglob)
         xi = xred(i)
         yi = yred(i)
         zi = zred(i)
         usei = (use(iglob) .or. use(iv))
         muti = mut(iglob)
c
c     set interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = v2scale
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = v3scale
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = v4scale
            iv14(i14(j,iglob)) = iglob
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = v5scale
         end do
c
c     decide whether to compute the current interaction
c
         do kk = 1, nvlst(ii)
            kglob = vlst(kk,ii)
            kbis = loc(kglob)
            kv = ired(kglob)
            mutk = mut(kglob)
            proceed = .true.
            if (proceed)  proceed = (usei .or. use(kglob) .or. use(kv))
c
c     compute the energy contribution for this interaction
c
            if (proceed) then
               kt = jvdw(kglob)
               xr = xi - xred(kbis)
               yr = yi - yred(kbis)
               zr = zi - zred(kbis)
               if (use_bounds) call image (xr,yr,zr)
               rik2 = xr*xr + yr*yr + zr*zr
c
c     check for an interaction distance less than the cutoff
c
               if (rik2 .le. off2) then
                  rik = sqrt(rik2)
                  rv  = radmin(kt,it)
                  eps = epsilon(kt,it)
                  if (iv14(kglob) .eq. iglob) then
                     rv = radmin4(kt,it)
                     eps = epsilon4(kt,it)
                  end if
                  eps = eps * vscale(kglob)
c
c     set use of lambda scaling for decoupling or annihilation
c
                  mutik = .false.
                  if (muti .or. mutk) then
                     if (vcouple .eq. 1) then
                        mutik = .true.
                     else if (.not.muti .or. .not.mutk) then
                        mutik = .true.
                     end if
                  end if
c
c     get the interaction energy, via soft core if necessary
c
                  if (mutik) then
                     rho = rik / rv
                     eps = eps * vlambda**scexp
                     scal = scalpha * (1.0d0-vlambda)**2
                     t1 = (1.0d0+dhal)**7 / (scal+(rho+dhal)**7)
                     t2 = (1.0d0+ghal) / (scal+rho**7+ghal)
                     e = eps * t1 * (t2-2.0d0)
                  else
                     rv7 = rv**7
                     rik7 = rik**7
                     rho = rik7 + ghal*rv7
                     tau = (dhal+1.0d0) / (rik + dhal*rv)
                     e = eps * rv7 * tau**7
     &                      * ((ghal+1.0d0)*rv7/rho-2.0d0)
                  end if
c
c     use energy switching if near the cutoff distance
c
                  if (rik2 .gt. cut2) then
                     rik3 = rik2 * rik
                     rik4 = rik2 * rik2
                     rik5 = rik2 * rik3
                     taper = c5*rik5 + c4*rik4 + c3*rik3
     &                          + c2*rik2 + c1*rik + c0
                     e = e * taper
                  end if
c
c     increment the overall van der Waals energy components
c
                  if (e .ne. 0.0d0) then
                     ev = ev + e
                  end if
c
c     increment the total intermolecular energy
c
                  if (molcule(iglob) .ne. molcule(kglob)) then
                     einter = einter + e
                  end if
c
               end if
            end if
         end do
c
c     reset interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = 1.0d0
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = 1.0d0
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = 1.0d0
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = 1.0d0
         end do
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (iv14)
      deallocate (xred)
      deallocate (yred)
      deallocate (zred)
      deallocate (vscale)
      return
      end
c
c     ###############################################################################
c     ##                                                                           ##
c     ##  subroutine ehalshort0c  --  short range buffered 14-7 analysis via list  ##
c     ##                                                                           ##
c     ###############################################################################
c
c
c     "ehalshort0c" calculates the short range buffered 14-7 van der Waals energy
c     and also partitions the energy among the atoms using a
c     pairwise neighbor list
c
c
      subroutine ehalshort0c
      use atmlst
      use atoms
      use bound
      use couple
      use cutoff
      use domdec
      use energi
      use inter
      use molcul
      use mutant
      use neigh
      use shunt
      use usage
      use vdw
      use vdwpot
      implicit none
      integer i,j,iglob,kglob,kbis
      integer ii,iv,it,iivdw,inl
      integer kk,kv,kt
      integer, allocatable :: iv14(:)
      real*8 e,eps,rdn
      real*8 rv,rv7
      real*8 xi,yi,zi
      real*8 xr,yr,zr
      real*8 rho,tau,taper
      real*8 scal,t1,t2
      real*8 rik,rik2,rik3
      real*8 rik4,rik5,rik7
      real*8 s,ds
      real*8, allocatable :: xred(:)
      real*8, allocatable :: yred(:)
      real*8, allocatable :: zred(:)
      real*8, allocatable :: vscale(:)
      logical proceed,usei
      logical muti,mutk,mutik
      character*10 mode
c
c
c     zero out the van der Waals energy and partitioning terms
c
      ev = 0.0d0
c
c     perform dynamic allocation of some local arrays
c
      allocate (iv14(n))
      allocate (xred(nbloc))
      allocate (yred(nbloc))
      allocate (zred(nbloc))
      allocate (vscale(n))
c
c     set arrays needed to scale connected atom interactions
c
      vscale = 1.0d0
      iv14 = 0
c
c     set the coefficients for the switching function
c
      mode = 'SHORTVDW'
      call switch (mode)
c
c     apply any reduction factor to the atomic coordinates
c
      do ii = 1, nvdwbloc
         iivdw = vdwglob(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         iv = ired(iglob)
         rdn = kred(iglob)
         xr = x(iglob) - x(iv)
         yr = y(iglob) - y(iv)
         zr = z(iglob) - z(iv)
         if (use_polymer) call image(xr,yr,zr)
         xred(i) = rdn*xr + x(iv)
         yred(i) = rdn*yr + y(iv)
         zred(i) = rdn*zr + z(iv)
      end do
c
c
c     find the van der Waals energy via neighbor list search
c
      do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         iv = ired(iglob)
         it = jvdw(iglob)
         xi = xred(i)
         yi = yred(i)
         zi = zred(i)
         usei = (use(iglob) .or. use(iv))
         muti = mut(iglob)
c
c     set interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = v2scale
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = v3scale
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = v4scale
            iv14(i14(j,iglob)) = iglob
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = v5scale
         end do
c
c     decide whether to compute the current interaction
c
         do kk = 1, nshortvlst(ii)
            kglob = shortvlst(kk,ii)
            kbis = loc(kglob)
            kv = ired(kglob)
            mutk = mut(kglob)
            proceed = .true.
            if (proceed)  proceed = (usei .or. use(kglob) .or. use(kv))
c
c     compute the energy contribution for this interaction
c
            if (proceed) then
               kt = jvdw(kglob)
               xr = xi - xred(kbis)
               yr = yi - yred(kbis)
               zr = zi - zred(kbis)
               if (use_bounds) call image (xr,yr,zr)
               rik2 = xr*xr + yr*yr + zr*zr
c
c     check for an interaction distance less than the cutoff
c
               if (rik2 .le. off2) then
                  rik = sqrt(rik2)
                  rv  = radmin(kt,it)
                  eps = epsilon(kt,it)
                  if (iv14(kglob) .eq. iglob) then
                     rv = radmin4(kt,it)
                     eps = epsilon4(kt,it)
                  end if
                  eps = eps * vscale(kglob)
c
c     set use of lambda scaling for decoupling or annihilation
c
                  mutik = .false.
                  if (muti .or. mutk) then
                     if (vcouple .eq. 1) then
                        mutik = .true.
                     else if (.not.muti .or. .not.mutk) then
                        mutik = .true.
                     end if
                  end if
c
c     get the interaction energy, via soft core if necessary
c
                  if (mutik) then
                     rho = rik / rv
                     eps = eps * vlambda**scexp
                     scal = scalpha * (1.0d0-vlambda)**2
                     t1 = (1.0d0+dhal)**7 / (scal+(rho+dhal)**7)
                     t2 = (1.0d0+ghal) / (scal+rho**7+ghal)
                     e = eps * t1 * (t2-2.0d0)
                  else
                     rv7 = rv**7
                     rik7 = rik**7
                     rho = rik7 + ghal*rv7
                     tau = (dhal+1.0d0) / (rik + dhal*rv)
                     e = eps * rv7 * tau**7
     &                      * ((ghal+1.0d0)*rv7/rho-2.0d0)
                  end if
c
c     use energy switching if near the cutoff distance
c
                  if (rik2 .gt. (off-shortheal)*(off-shortheal)) then
                     call switch_respa(rik,off,shortheal,s,ds)
                     e = e * s
                  end if
c
c     increment the overall van der Waals energy components
c
                  if (e .ne. 0.0d0) then
                     ev = ev + e
                  end if
c
c     increment the total intermolecular energy
c
                  if (molcule(iglob) .ne. molcule(kglob)) then
                     einter = einter + e
                  end if
c
               end if
            end if
         end do
c
c     reset interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = 1.0d0
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = 1.0d0
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = 1.0d0
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = 1.0d0
         end do
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (iv14)
      deallocate (xred)
      deallocate (yred)
      deallocate (zred)
      deallocate (vscale)
      return
      end
c
c     ###############################################################################
c     ##                                                                           ##
c     ##  subroutine ehallong0c  --  long range buffered 14-7 analysis via list    ##
c     ##                                                                           ##
c     ###############################################################################
c
c
c     "ehallong0c" calculates the long range buffered 14-7 van der Waals energy
c     and also partitions the energy among the atoms using a
c     pairwise neighbor list
c
c
      subroutine ehallong0c
      use atmlst
      use atoms
      use bound
      use couple
      use cutoff
      use domdec
      use energi
      use inter
      use molcul
      use mutant
      use neigh
      use shunt
      use usage
      use vdw
      use vdwpot
      implicit none
      integer i,j,iglob,kglob,kbis
      integer ii,iv,it,iivdw,inl
      integer kk,kv,kt
      integer, allocatable :: iv14(:)
      real*8 e,eps,rdn
      real*8 rv,rv7
      real*8 xi,yi,zi
      real*8 xr,yr,zr
      real*8 rho,tau,taper
      real*8 scal,t1,t2
      real*8 rik,rik2,rik3
      real*8 rik4,rik5,rik7
      real*8 s,ds,vdwshortcut2
      real*8, allocatable :: xred(:)
      real*8, allocatable :: yred(:)
      real*8, allocatable :: zred(:)
      real*8, allocatable :: vscale(:)
      logical proceed,usei
      logical muti,mutk,mutik
      character*10 mode
c
c
c     zero out the van der Waals energy and partitioning terms
c
      ev = 0.0d0
c
c     perform dynamic allocation of some local arrays
c
      allocate (iv14(n))
      allocate (xred(nbloc))
      allocate (yred(nbloc))
      allocate (zred(nbloc))
      allocate (vscale(n))
c
c     set arrays needed to scale connected atom interactions
c
      vscale = 1.0d0
      iv14 = 0
c
c     set the coefficients for the switching function
c
      mode = 'VDW'
      call switch (mode)
      vdwshortcut2 = (vdwshortcut-shortheal)**2
c
c     apply any reduction factor to the atomic coordinates
c
      do ii = 1, nvdwbloc
         iivdw = vdwglob(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         iv = ired(iglob)
         rdn = kred(iglob)
         xr = x(iglob) - x(iv)
         yr = y(iglob) - y(iv)
         zr = z(iglob) - z(iv)
         if (use_polymer) call image(xr,yr,zr)
         xred(i) = rdn*xr + x(iv)
         yred(i) = rdn*yr + y(iv)
         zred(i) = rdn*zr + z(iv)
      end do
c
c
c     find the van der Waals energy via neighbor list search
c
      do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i = loc(iglob)
         iv = ired(iglob)
         it = jvdw(iglob)
         xi = xred(i)
         yi = yred(i)
         zi = zred(i)
         usei = (use(iglob) .or. use(iv))
         muti = mut(iglob)
c
c     set interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = v2scale
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = v3scale
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = v4scale
            iv14(i14(j,iglob)) = iglob
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = v5scale
         end do
c
c     decide whether to compute the current interaction
c
         do kk = 1, nvlst(ii)
            kglob = vlst(kk,ii)
            kbis = loc(kglob)
            kv = ired(kglob)
            mutk = mut(kglob)
            proceed = .true.
            if (proceed)  proceed = (usei .or. use(kglob) .or. use(kv))
c
c     compute the energy contribution for this interaction
c
            if (proceed) then
               kt = jvdw(kglob)
               xr = xi - xred(kbis)
               yr = yi - yred(kbis)
               zr = zi - zred(kbis)
               if (use_bounds) call image (xr,yr,zr)
               rik2 = xr*xr + yr*yr + zr*zr
c
c     check for an interaction distance less than the cutoff
c
               if ((rik2 .le. off2).and.(rik2.ge.vdwshortcut2)) then
                  rik = sqrt(rik2)
                  rv  = radmin(kt,it)
                  eps = epsilon(kt,it)
                  if (iv14(kglob) .eq. iglob) then
                     rv = radmin4(kt,it)
                     eps = epsilon4(kt,it)
                  end if
                  eps = eps * vscale(kglob)
c
c     set use of lambda scaling for decoupling or annihilation
c
                  mutik = .false.
                  if (muti .or. mutk) then
                     if (vcouple .eq. 1) then
                        mutik = .true.
                     else if (.not.muti .or. .not.mutk) then
                        mutik = .true.
                     end if
                  end if
c
c     get the interaction energy, via soft core if necessary
c
                  if (mutik) then
                     rho = rik / rv
                     eps = eps * vlambda**scexp
                     scal = scalpha * (1.0d0-vlambda)**2
                     t1 = (1.0d0+dhal)**7 / (scal+(rho+dhal)**7)
                     t2 = (1.0d0+ghal) / (scal+rho**7+ghal)
                     e = eps * t1 * (t2-2.0d0)
                  else
                     rv7 = rv**7
                     rik7 = rik**7
                     rho = rik7 + ghal*rv7
                     tau = (dhal+1.0d0) / (rik + dhal*rv)
                     e = eps * rv7 * tau**7
     &                      * ((ghal+1.0d0)*rv7/rho-2.0d0)
                  end if
c
c     use energy switching if close the cutoff distance (at short range)
c
                  call switch_respa(rik,vdwshortcut,shortheal,s,ds)
                  e = (1-s)*e
c
c     use energy switching if near the cutoff distance
c
                  if (rik2 .gt. (off-shortheal)*(off-shortheal)) then
                     call switch_respa(rik,off,shortheal,s,ds)
                     e = e * s
                  end if
c
c     increment the overall van der Waals energy components
c
                  if (e .ne. 0.0d0) then
                     ev = ev + e
                  end if
c
c     increment the total intermolecular energy
c
                  if (molcule(iglob) .ne. molcule(kglob)) then
                     einter = einter + e
                  end if
c
               end if
            end if
         end do
c
c     reset interaction scaling coefficients for connected atoms
c
         do j = 1, n12(iglob)
            vscale(i12(j,iglob)) = 1.0d0
         end do
         do j = 1, n13(iglob)
            vscale(i13(j,iglob)) = 1.0d0
         end do
         do j = 1, n14(iglob)
            vscale(i14(j,iglob)) = 1.0d0
         end do
         do j = 1, n15(iglob)
            vscale(i15(j,iglob)) = 1.0d0
         end do
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (iv14)
      deallocate (xred)
      deallocate (yred)
      deallocate (zred)
      deallocate (vscale)
      return
      end
