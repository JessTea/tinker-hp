c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ############################################################
c     ##                                                        ##
c     ##  subroutine epolar1  --  polarization energy & derivs  ##
c     ##                                                        ##
c     ############################################################
c
c
c     "epolar1" calculates the induced dipole polarization energy
c     and derivatives with respect to Cartesian coordinates
c
c
#include "tinker_precision.h"
      subroutine epolar1
      use polpot
      use potent
      use mpi
      implicit none
c
c     choose the method for summing over polarization interactions
c
      if (use_lambdadyn) then
        call elambdapolar1c
      else
        if (use_polarshortreal) then
          if (polalgshort.eq.3) then
            !call epolar1tcg !FIXME
          else
            call epolar1c
          end if
        else
          if (polalg.eq.3) then
            !call epolar1tcg
          else
            call epolar1c
          end if
        end if
      end if
      return
      end
c
c     ###################################################################
c     ##                                                               ##
c     ##  subroutine epolar1c  --  Ewald polarization derivs via list  ##
c     ##                                                               ##
c     ###################################################################
c
c
c     "epolar1c" calculates the dipole polarization energy and
c     derivatives with respect to Cartesian coordinates using
c     particle mesh Ewald summation and a neighbor list
c
c
      subroutine epolar1c
      use atmlst
      use atoms
      use boxes
      use chgpot
      use deriv
      use domdec
      use energi
      use ewald
      use iounit
      use math
      use mpole
      use polar
      use polpot
      use potent
      use tinheader ,only:ti_p,re_p
      use virial
      use mpi
      implicit none
      integer i,ii,iglob,iipole,ierr
      real(t_p) e,f,term,fterm
      real(t_p) dix,diy,diz
      real(t_p) uix,uiy,uiz,uii
      real(t_p) xd,yd,zd
      real(t_p) xq,yq,zq
      real(t_p) xu,yu,zu
      real(t_p) xup,yup,zup
      real(t_p) xv,yv,zv,vterm
      real(t_p) xufield,yufield
      real(t_p) zufield
      real(t_p) fix(3),fiy(3),fiz(3)
      real(t_p) trq(3)
c
c
c     zero out the polarization energy and derivatives
c
      ep = 0.0_re_p
      dep = 0_re_p
c
      if (npole .eq. 0)  return
c
c     set the energy unit conversion factor
c
      f = electric / dielec
c
c     compute the induced dipoles at each polarizable atom
c
      if (use_polarshortreal) then
        if (polalg.eq.5) then
          call dcinduce_shortreal
        else
          call newinduce_shortreal
        end if
      else if (use_pmecore) then
        if (polalg.eq.5) then
          call dcinduce_pme
        else
          call newinduce_pme
c         call newinduce_pmevec
        end if
      else
        if (polalg.eq.5) then
          call dcinduce_pme2
        else
          call newinduce_pme2
c         call newinduce_pme2vec
        end if
      end if
c
c     compute the reciprocal space part of the Ewald summation
c
      if ((.not.(use_pmecore)).or.(use_pmecore).and.(rank.gt.ndir-1))
     $   then
        if (use_prec) then
          call eprecip1
        end if
      end if
c
c     compute the real space part of the Ewald summation
c
      if ((.not.(use_pmecore)).or.(use_pmecore).and.(rank.le.ndir-1))
     $   then
        if (use_preal) then
           call epreal1c
        end if

        if (use_pself) then
c
c     compute the Ewald self-energy term over all the atoms
c
          term = 2.0_ti_p * aewald * aewald
          fterm = -f * aewald / sqrtpi
          do ii = 1, npoleloc
             iipole = poleglob(ii)
             dix = rpole(2,iipole)
             diy = rpole(3,iipole)
             diz = rpole(4,iipole)
             uix = uind(1,iipole)
             uiy = uind(2,iipole)
             uiz = uind(3,iipole)
             uii = dix*uix + diy*uiy + diz*uiz
             e = fterm * term * uii / 3.0_ti_p
             ep = ep + e
          end do
c
c     compute the self-energy torque term due to induced dipole
c
          term = (4.0_ti_p/3.0_ti_p) * f * aewald**3 / sqrtpi
          do ii = 1, npoleloc
             iipole = poleglob(ii)
             dix = rpole(2,iipole)
             diy = rpole(3,iipole)
             diz = rpole(4,iipole)
             uix = 0.5_ti_p * (uind(1,iipole)+uinp(1,iipole))
             uiy = 0.5_ti_p * (uind(2,iipole)+uinp(2,iipole))
             uiz = 0.5_ti_p * (uind(3,iipole)+uinp(3,iipole))
             trq(1) = term * (diy*uiz-diz*uiy)
             trq(2) = term * (diz*uix-dix*uiz)
             trq(3) = term * (dix*uiy-diy*uix)
             call torque (iipole,trq,fix,fiy,fiz,dep)
          end do
c
c         compute the cell dipole boundary correction term
c
          if (boundary .eq. 'VACUUM') then
             xd = 0.0_ti_p
             yd = 0.0_ti_p
             zd = 0.0_ti_p
             xu = 0.0_ti_p
             yu = 0.0_ti_p
             zu = 0.0_ti_p
             xup = 0.0_ti_p
             yup = 0.0_ti_p
             zup = 0.0_ti_p
             do i = 1, npoleloc
                iipole = poleglob(i)
                iglob = ipole(iipole)
                xd = xd + rpole(2,iipole) + rpole(1,iipole)*x(iglob)
                yd = yd + rpole(3,iipole) + rpole(1,iipole)*y(iglob)
                zd = zd + rpole(4,iipole) + rpole(1,iipole)*z(iglob)
                xu = xu + uind(1,iipole)
                yu = yu + uind(2,iipole)
                zu = zu + uind(3,iipole)
                xup = xup + uinp(1,iipole)
                yup = yup + uinp(2,iipole)
                zup = zup + uinp(3,iipole)
             end do
             call MPI_ALLREDUCE(MPI_IN_PLACE,xd,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,yd,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,zd,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,xu,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,yu,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,zu,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,xup,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,yup,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,zup,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             term = (2.0_ti_p/3.0_ti_p) * f * (pi/volbox)
             if (rank.eq.0) then
               ep = ep + term*(xd*xu+yd*yu+zd*zu)
             end if
             do ii = 1, npoleloc
                iipole = poleglob(ii)
                iglob = ipole(iipole)
                i = loc(iglob)
                dep(1,i) = dep(1,i) + term*rpole(1,iipole)*(xu+xup)
                dep(2,i) = dep(2,i) + term*rpole(1,iipole)*(yu+yup)
                dep(3,i) = dep(3,i) + term*rpole(1,iipole)*(zu+zup)
             end do
             xufield = -term * (xu+xup)
             yufield = -term * (yu+yup)
             zufield = -term * (zu+zup)
             do i = 1, npoleloc
                iipole = poleglob(i)
              trq(1) = rpole(3,iipole)*zufield - rpole(4,iipole)*yufield
              trq(2) = rpole(4,iipole)*xufield - rpole(2,iipole)*zufield
              trq(3) = rpole(2,iipole)*yufield - rpole(3,iipole)*xufield
                call torque (iipole,trq,fix,fiy,fiz,dep)
             end do
c
c       boundary correction to virial due to overall cell dipole
c
             xd = 0.0_ti_p
             yd = 0.0_ti_p
             zd = 0.0_ti_p
             xq = 0.0_ti_p
             yq = 0.0_ti_p
             zq = 0.0_ti_p
             do i = 1, npoleloc
                iipole = poleglob(i)
                iglob = ipole(iipole)
                xd = xd + rpole(2,iipole)
                yd = yd + rpole(3,iipole)
                zd = zd + rpole(4,iipole)
                xq = xq + rpole(1,iipole)*x(iglob)
                yq = yq + rpole(1,iipole)*y(iglob)
                zq = zq + rpole(1,iipole)*z(iglob)
             end do
             call MPI_ALLREDUCE(MPI_IN_PLACE,xd,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,yd,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,zd,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,xq,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,yq,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             call MPI_ALLREDUCE(MPI_IN_PLACE,zq,1,MPI_TPREC,MPI_SUM,
     $          COMM_TINKER,ierr)
             if (rank.eq.0) then
               xv = xq * (xu+xup)
               yv = yq * (yu+yup)
               zv = zq * (zu+zup)
               vterm = xv + yv + zv + xu*xup + yu*yup + zu*zup
     &                    + xd*(xu+xup) + yd*(yu+yup) + zd*(zu+zup)
               vterm = term * vterm
               vir(1,1) = vir(1,1) + term*xv + vterm
               vir(2,1) = vir(2,1) + term*xv
               vir(3,1) = vir(3,1) + term*xv
               vir(1,2) = vir(1,2) + term*yv
               vir(2,2) = vir(2,2) + term*yv + vterm
               vir(3,2) = vir(3,2) + term*yv
               vir(1,3) = vir(1,3) + term*zv
               vir(2,3) = vir(2,3) + term*zv
               vir(3,3) = vir(3,3) + term*zv + vterm
             end if
           end if
        end if
      end if
      return
      end
c
c
c
      subroutine elambdapolar1c
      use atmlst
      use atoms
      use boxes
      use chgpot
      use deriv
      use domdec
      use energi
      use ewald
      use iounit
      use math
      use mpole
      use mutant
      use polar
      use polpot
      use potent
      use uprior
      use virial
      use mpi
      implicit none
      integer i,iipole,j,k,ierr
      real*8 elambdatemp,plambda
      real*8, allocatable :: delambdap0(:,:),delambdap1(:,:)
      real*8, allocatable :: delambdaprec0(:,:),delambdaprec1(:,:)
      real*8 :: elambdap0,elambdap1
      real*8 dplambdadelambdae,d2plambdad2elambdae
c
      allocate (delambdaprec0(3,nlocrec2))
      allocate (delambdaprec1(3,nlocrec2))
      allocate (delambdap0(3,nbloc))
      allocate (delambdap1(3,nbloc))
      elambdatemp = elambda  
c
c     zero out the polarization energy and derivatives
c
      ep = 0.0d0
      dep = 0d0
      deprec = 0d0
c
      if (npole .eq. 0)  return
      if (.not.(use_mpole)) then
        delambdae = 0d0
      end if

c
c     polarization is interpolated between elambda=1 and elambda=0, for lambda.gt.plambda,
c     otherwise the value taken is for elambda=0
c
      elambdap1 = 0d0
      delambdap1 = 0d0
      delambdaprec1 = 0d0
      if (elambda.gt.bplambda) then
        elambda = 1d0
        call MPI_BARRIER(hostcomm,ierr)
        if (hostrank.eq.0) call altelec
        call MPI_BARRIER(hostcomm,ierr)
        call rotpole
        ep = 0d0
        dep = 0d0
        deprec = 0d0
        call epolar1c
        elambdap1  = ep
        delambdap1 = dep
        delambdaprec1 = deprec
      end if

      elambda = 0d0
      call MPI_BARRIER(hostcomm,ierr)
      if (hostrank.eq.0) call altelec
      call MPI_BARRIER(hostcomm,ierr)
      call rotpole
      ep = 0d0
      dep = 0d0
      deprec = 0d0
      call epolar1c
      elambdap0  = ep
      delambdap0 = dep
      delambdaprec0 = deprec
c
c     also store the dipoles to build ASPC guess
c
      nualt = min(nualt+1,maxualt)
      do i = 1, npolebloc
        iipole = poleglob(i)
         do j = 1, 3
            do k = nualt, 2, -1
               udalt(k,j,iipole) = udalt(k-1,j,iipole)
               upalt(k,j,iipole) = upalt(k-1,j,iipole)
            end do
            udalt(1,j,iipole) = uind(j,iipole)
            upalt(1,j,iipole) = uinp(j,iipole)
          end do
      end do
 
      elambda = elambdatemp 
c
c     interpolation of "plambda" between bplambda and 1 as a function of
c     elambda: 
c       plambda = 0 for elambda.le.bplambda
c       u = (elambda-bplambda)/(1-bplambda)
c       plambda = u**3 for elambda.gt.plambda
c       ep = (1-plambda)*ep0 +  plambda*ep1
c
      if (elambda.le.bplambda) then
        plambda = 0d0
        dplambdadelambdae = 0d0
        d2plambdad2elambdae = 0d0
      else
        plambda = ((elambda-bplambda)/(1-bplambda))**3
        dplambdadelambdae = 3d0*((elambda-bplambda)/(1-bplambda))**2
        d2plambdad2elambdae = 6d0*((elambda-bplambda)/(1-bplambda))
      end if
      ep = plambda*elambdap1 + (1-plambda)*elambdap0
      deprec = (1-plambda)*delambdaprec0+plambda*delambdaprec1
      dep = (1-plambda)*delambdap0 + plambda*delambdap1
      delambdae = delambdae + (elambdap1-elambdap0)*dplambdadelambdae
c
c     reset lambda to initial value
c
      call MPI_BARRIER(hostcomm,ierr)
      if (hostrank.eq.0) call altelec
      call MPI_BARRIER(hostcomm,ierr)
      call rotpole
      return
      end
c
c
c     ###################################################################
c     ##                                                               ##
c     ##  subroutine eprecip1  --  PME recip polarize energy & derivs  ##
c     ##                                                               ##
c     ###################################################################
c
c
c     "eprecip1" evaluates the reciprocal space portion of the particle
c     mesh Ewald summation energy and gradient due to dipole polarization
c
c     literature reference:
c
c     C. Sagui, L. G. Pedersen and T. A. Darden, "Towards an Accurate
c     Representation of Electrostatics in Classical Force Fields:
c     Efficient Implementation of Multipolar Interactions in
c     Biomolecular Simulations", Journal of Chemical Physics, 120,
c     73-87 (2004)
c
c     modifications for nonperiodic systems suggested by Tom Darden
c     during May 2007
c
c
      subroutine eprecip1
      use atmlst
      use atoms
      use bound
      use boxes
      use chgpot
      use deriv
      use domdec
      use energi
      use ewald
      use fft
      use inform
      use math
      use mpole
      use pme
      use polar
      use polpot
      use potent
      use timestat
      use tinheader ,only:ti_p,re_p
      use virial
      use mpi
      implicit none
      integer status(MPI_STATUS_SIZE),tag,ierr
      integer i,j,k,ii,iipole,iglob
      integer j1,j2,j3
      integer k1,k2,k3
      integer m1,m2,m3
      integer ntot,nff
      integer nf1,nf2,nf3
      integer deriv1(10)
      integer deriv2(10)
      integer deriv3(10)
      real(t_p) e,eterm,f
      real(t_p) r1,r2,r3
      real(t_p) h1,h2,h3
      real(t_p) f1,f2,f3
      real(t_p) vxx,vyy,vzz
      real(t_p) vxy,vxz,vyz
      real(t_p) volterm,denom
      real(t_p) hsq,expterm
      real(t_p) term,pterm
      real(t_p) vterm,struc2
      real(t_p) trq(3),fix(3)
      real(t_p) fiy(3),fiz(3)
      real(t_p) cphim(4),cphid(4)
      real(t_p) cphip(4)
      real(t_p) a(3,3),ftc(10,10)
      real(t_p), allocatable :: cmp(:,:),fmp(:,:)
      real(t_p), allocatable :: fuind(:,:)
      real(t_p), allocatable :: fuinp(:,:)
      real(t_p), allocatable :: fphid(:,:)
      real(t_p), allocatable :: fphip(:,:)
      real(t_p), allocatable :: fphidp(:,:)
      real(t_p), allocatable :: qgrip(:,:,:,:)
      real(t_p), allocatable :: qgridmpi(:,:,:,:,:)
      integer, allocatable :: reqsend(:),reqrec(:)
      integer, allocatable :: req2send(:),req2rec(:)
      integer nprocloc,commloc,rankloc,proc
      real(t_p) time0,time1

      parameter(  !indices into the electrostatic field array
     &  deriv1=(/ 2, 5,  8,  9, 11, 16, 18, 14, 15, 20 /),
     &  deriv2=(/ 3, 8,  6, 10, 14, 12, 19, 16, 20, 17 /),
     &  deriv3=(/ 4, 9, 10,  7, 15, 17, 13, 20, 18, 19 /))
c
      if (deb_Path) write(*,'(2x,a)') 'eprecip1'
      call timer_enter( timer_eprecip )
      if (use_pmecore) then
        nprocloc = nrec
        commloc  = comm_rec
        rankloc  = rank_bis
      else
        nprocloc = nproc
        commloc  = COMM_TINKER
        rankloc  = rank
      end if
c
c
c     return if the Ewald coefficient is zero
c
      if (aewald .lt. 1.0d-6)  return
      f = electric / dielec
c
c     perform dynamic allocation of some global arrays
c
      allocate (fuind(3,npolerecloc))
      allocate (fuinp(3,npolerecloc))
      allocate (cmp(10,npolerecloc))
      allocate (fmp(10,npolerecloc))
      allocate (fphid(10,npolerecloc))
      allocate (fphip(10,npolerecloc))
      allocate (fphidp(20,npolerecloc))
      allocate (qgridmpi(2,n1mpimax,n2mpimax,n3mpimax,nrec_recep))
      allocate (reqsend(nproc))
      allocate (reqrec(nproc))
      allocate (req2send(nproc))
      allocate (req2rec(nproc))
c
c     zero out the temporary virial accumulation variables
c
      vxx = 0.0_ti_p
      vxy = 0.0_ti_p
      vxz = 0.0_ti_p
      vyy = 0.0_ti_p
      vyz = 0.0_ti_p
      vzz = 0.0_ti_p
c
c     get the fractional to Cartesian transformation matrix
c
      call frac_to_cart (ftc)
c
c     initialize variables required for the scalar summation
c
      ntot = nfft1 * nfft2 * nfft3
      pterm = (pi/aewald)**2
      volterm = pi * volbox
      nff = nfft1 * nfft2
      nf1 = (nfft1+1) / 2
      nf2 = (nfft2+1) / 2
      nf3 = (nfft3+1) / 2
c
c     remove scalar sum virial from prior multipole 3-D FFT
c
c      if (use_mpole) then
         vxx = -vmxx
         vxy = -vmxy
         vxz = -vmxz
         vyy = -vmyy
         vyz = -vmyz
         vzz = -vmzz
cc
cc     compute the arrays of B-spline coefficients
cc
c      else
c         call bspline_fill
c         call table_fill
cc
cc     assign only the permanent multipoles to the PME grid
cc     and perform the 3-D FFT forward transformation
cc
         do i = 1, npolerecloc
            iipole = polerecglob(i)
            cmp(1,i) = rpole(1,iipole)
            cmp(2,i) = rpole(2,iipole)
            cmp(3,i) = rpole(3,iipole)
            cmp(4,i) = rpole(4,iipole)
            cmp(5,i) = rpole(5,iipole)
            cmp(6,i) = rpole(9,iipole)
            cmp(7,i) = rpole(13,iipole)
            cmp(8,i) = 2.0_ti_p * rpole(6,iipole)
            cmp(9,i) = 2.0_ti_p * rpole(7,iipole)
            cmp(10,i) = 2.0_ti_p * rpole(10,iipole)
           call cmp_to_fmp_site(cmp(1,i),fmp(1,i))
         end do
c         call cmp_to_fmp (cmp,fmp)
c         call grid_mpole (fmp)
c         call fftfront
cc
cc     make the scalar summation over reciprocal lattice
cc
c         do i = 1, ntot-1
c            k3 = i/nff + 1
c            j = i - (k3-1)*nff
c            k2 = j/nfft1 + 1
c            k1 = j - (k2-1)*nfft1 + 1
c            m1 = k1 - 1
c            m2 = k2 - 1
c            m3 = k3 - 1
c            if (k1 .gt. nf1)  m1 = m1 - nfft1
c            if (k2 .gt. nf2)  m2 = m2 - nfft2
c            if (k3 .gt. nf3)  m3 = m3 - nfft3
c            r1 = real(m1,t_p)
c            r2 = real(m2,t_p)
c            r3 = real(m3,t_p)
c            h1 = recip(1,1)*r1 + recip(1,2)*r2 + recip(1,3)*r3
c            h2 = recip(2,1)*r1 + recip(2,2)*r2 + recip(2,3)*r3
c            h3 = recip(3,1)*r1 + recip(3,2)*r2 + recip(3,3)*r3
c            hsq = h1*h1 + h2*h2 + h3*h3
c            term = -pterm * hsq
c            expterm = 0.0_ti_p
c            if (term .gt. -50.0_ti_p) then
c               denom = volterm*hsq*bsmod1(k1)*bsmod2(k2)*bsmod3(k3)
c               expterm = exp(term) / denom
c               if (.not. use_bounds) then
c                  expterm = expterm * (1.0_ti_p-cos(pi*xbox*sqrt(hsq)))
c               else if (octahedron) then
c                  if (mod(m1+m2+m3,2) .ne. 0)  expterm = 0.0_ti_p
c               end if
c               struc2 = qgrid(1,k1,k2,k3)**2 + qgrid(2,k1,k2,k3)**2
c               eterm = 0.5_ti_p * f * expterm * struc2
c               vterm = (2.0_ti_p/hsq) * (1.0_ti_p-term) * eterm
c               vxx = vxx - h1*h1*vterm + eterm
c               vxy = vxy - h1*h2*vterm
c               vxz = vxz - h1*h3*vterm
c               vyy = vyy - h2*h2*vterm + eterm
c               vyz = vyz - h2*h3*vterm
c               vzz = vzz - h3*h3*vterm + eterm
c            end if
c         end do
cc
cc     account for zeroth grid point for nonperiodic system
cc
c         qfac(1,1,1) = 0.0_ti_p
c         if (.not. use_bounds) then
c            expterm = 0.5_ti_p * pi / xbox
c            struc2 = qgrid(1,1,1,1)**2 + qgrid(2,1,1,1)**2
c            e = f * expterm * struc2
c            qfac(1,1,1) = expterm
c         end if
cc
cc     complete the transformation of the PME grid
cc
c         do k = 1, nfft3
c            do j = 1, nfft2
c               do i = 1, nfft1
c                  term = qfac(i,j,k)
c                  qgrid(1,i,j,k) = term * qgrid(1,i,j,k)
c                  qgrid(2,i,j,k) = term * qgrid(2,i,j,k)
c               end do
c            end do
c         end do
cc
cc     perform 3-D FFT backward transform and get potential
cc
c         call fftback
c         call fphi_mpole (fphi)
c         do i = 1, npole
c            do j = 1, 20
c               fphi(j,i) = f * fphi(j,i)
c            end do
c         end do
c         call fphi_to_cphi (fphi,cphi)
c      end if
c
c     zero out the PME grid
c
      qgrid2in_2d = 0_ti_p
c
c     convert Cartesian induced dipoles to fractional coordinates
c
      do i = 1, 3
         a(1,i) = real(nfft1,t_p) * recip(i,1)
         a(2,i) = real(nfft2,t_p) * recip(i,2)
         a(3,i) = real(nfft3,t_p) * recip(i,3)
      end do
      time0 = mpi_wtime()
      do ii = 1, npolerecloc
         iipole = polerecglob(ii)
         iglob = ipole(iipole)
         do j = 1, 3
            fuind(j,ii) = a(j,1)*uind(1,iipole) + a(j,2)*uind(2,iipole)
     &                      + a(j,3)*uind(3,iipole)
            fuinp(j,ii) = a(j,1)*uinp(1,iipole) + a(j,2)*uinp(2,iipole)
     &                      + a(j,3)*uinp(3,iipole)
         end do
         call grid_uind_site(iglob,ii,fuind(1,ii),fuinp(1,ii),
     $    qgrid2in_2d)
      end do
      time1 = mpi_wtime()
      timegrid1 = timegrid1 + time1 - time0
c
c     MPI : begin reception
c
      do i = 1, nrec_recep
        tag = nprocloc*rankloc + prec_recep(i) + 1
        call MPI_IRECV(qgridmpi(1,1,1,1,i),2*n1mpimax*n2mpimax*
     $   n3mpimax,MPI_TPREC,prec_recep(i),tag,
     $   commloc,reqrec(i),ierr)
      end do
c
c     MPI : begin sending
c
      time0 = mpi_wtime()
      do i = 1, nrec_send
        tag = nprocloc*prec_send(i) + rankloc + 1
        call MPI_ISEND(qgrid2in_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_TPREC,
     $   prec_send(i),tag,commloc,reqsend(i),ierr)
      end do
c
      do i = 1, nrec_recep
        call MPI_WAIT(reqrec(i),status,ierr)
      end do
      do i = 1, nrec_send
        call MPI_WAIT(reqsend(i),status,ierr)
      end do
c
c     do the reduction 'by hand'
c
      do i = 1, nrec_recep
        qgrid2in_2d(:,:,:,:,1) = qgrid2in_2d(:,:,:,:,1)+
     $   qgridmpi(:,:,:,:,i)
      end do
      time1 = mpi_wtime()
      timerecreccomm = timerecreccomm + time1 - time0
c
      time0 = mpi_wtime()
      call fft2d_frontmpi(qgrid2in_2d,qgrid2out_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
      time1 = mpi_wtime()
      timeffts = timeffts + time1 - time0
c
c     account for zeroth grid point for nonperiodic system
c
      if (.not. use_bounds) then
         expterm = 0.5_ti_p * pi / xbox
         struc2 = qgrid2in_2d(1,1,1,1,1)**2 + qgrid2in_2d(2,1,1,1,1)**2
         e = f * expterm * struc2
         ep = ep + e
      end if
      if ((istart2(rankloc+1).eq.1).and.(jstart2(rankloc+1).eq.1)
     $   .and.(kstart2(rankloc+1).eq.1)) then
        if (.not. use_bounds) then
           expterm = 0.5_ti_p * pi / xbox
           struc2 = qgrid2in_2d(1,1,1,1,1)**2 +
     $       qgrid2in_2d(2,1,1,1,1)**2
           e = f * expterm * struc2
           ep = ep + e
        end if
      end if
c
c     complete the transformation of the PME grid
c
      time0 = mpi_wtime()
      do k = 1, ksize2(rankloc+1)
         do j = 1, jsize2(rankloc+1)
           do i = 1, isize2(rankloc+1)
             term = qfac_2d(i,j,k)
             qgrid2out_2d(1,i,j,k) = term*qgrid2out_2d(1,i,j,k)
             qgrid2out_2d(2,i,j,k) = term*qgrid2out_2d(2,i,j,k)
           end do
         end do
      end do
      time1 = mpi_wtime()
      timescalar = timescalar + time1 - time0
c
c     perform 3-D FFT backward transform and get potential
c
      time0 = mpi_wtime()
      call fft2d_backmpi(qgrid2in_2d,qgrid2out_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
      time1 = mpi_wtime()
      timeffts = timeffts + time1 - time0
c
c     MPI : Begin reception
c
      time0 = mpi_wtime()
      do i = 1, nrec_send
        tag = nprocloc*rankloc + prec_send(i) + 1
        call MPI_IRECV(qgrid2in_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_TPREC,
     $   prec_recep(i),tag,commloc,req2rec(i),ierr)
      end do
c
c     MPI : begin sending
c
      do i = 1, nrec_recep
        tag = nprocloc*prec_recep(i) + rankloc + 1
        call MPI_ISEND(qgrid2in_2d(1,1,1,1,1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_TPREC,
     $   prec_send(i),tag,commloc,req2send(i),ierr)
      end do
c
      time0 = mpi_wtime()
      do i = 1, nrec_send
        call MPI_WAIT(req2rec(i),status,ierr)
      end do
      do i = 1, nrec_recep
        call MPI_WAIT(req2send(i),status,ierr)
      end do
      time1 = mpi_wtime()
      timerecreccomm = timerecreccomm + time1 - time0
       time0 = mpi_wtime()
       do ii = 1, npolerecloc
         iipole = polerecglob(ii)
         iglob = ipole(iipole)
         call fphi_uind_site(iglob,ii,fphid(1,ii),fphip(1,ii),
     $        fphidp(1,ii))
         do j = 1, 10
            fphid(j,ii) = electric * fphid(j,ii)
            fphip(j,ii) = electric * fphip(j,ii)
         end do
         do j = 1, 20
            fphidp(j,ii) = electric * fphidp(j,ii)
         end do
         do j = 1, 20
            fphirec(j,ii) = electric * fphirec(j,ii)
         end do
       end do
c
c     increment the induced dipole energy and gradient
c
      e = 0.0_ti_p
      do i = 1, npolerecloc
         f1 = 0.0_ti_p
         f2 = 0.0_ti_p
         f3 = 0.0_ti_p
         do k = 1, 3
            j1 = deriv1(k+1)
            j2 = deriv2(k+1)
            j3 = deriv3(k+1)
            e = e + fuind(k,i)*fphirec(k+1,i)
            f1 = f1 + (fuind(k,i)+fuinp(k,i))*fphirec(j1,i)
     &              + fuind(k,i)*fphip(j1,i)
     &              + fuinp(k,i)*fphid(j1,i)
            f2 = f2 + (fuind(k,i)+fuinp(k,i))*fphirec(j2,i)
     &              + fuind(k,i)*fphip(j2,i)
     &              + fuinp(k,i)*fphid(j2,i)
            f3 = f3 + (fuind(k,i)+fuinp(k,i))*fphirec(j3,i)
     &              + fuind(k,i)*fphip(j3,i)
     &              + fuinp(k,i)*fphid(j3,i)
         end do
         do k = 1, 10
            f1 = f1 + fmp(k,i)*fphidp(deriv1(k),i)
            f2 = f2 + fmp(k,i)*fphidp(deriv2(k),i)
            f3 = f3 + fmp(k,i)*fphidp(deriv3(k),i)
         end do
         f1 = 0.5_ti_p * real(nfft1,t_p) * f1
         f2 = 0.5_ti_p * real(nfft2,t_p) * f2
         f3 = 0.5_ti_p * real(nfft3,t_p) * f3
         h1 = recip(1,1)*f1 + recip(1,2)*f2 + recip(1,3)*f3
         h2 = recip(2,1)*f1 + recip(2,2)*f2 + recip(2,3)*f3
         h3 = recip(3,1)*f1 + recip(3,2)*f2 + recip(3,3)*f3
         iipole = polerecglob(i)
         iglob = ipole(iipole)
         ii = locrec(iglob)
         deprec(1,ii) = deprec(1,ii) + h1
         deprec(2,ii) = deprec(2,ii) + h2
         deprec(3,ii) = deprec(3,ii) + h3
      end do
      e = 0.5_ti_p * e
      ep = ep + e
c
c     set the potential to be the induced dipole average
c
      do i = 1, npolerecloc
         do k = 1, 10
            fphidp(k,i) = 0.5_ti_p  * fphidp(k,i)
         end do
         call fphi_to_cphi_site(fphidp(1,i),cphirec(1,i))
      end do
c
c     distribute torques into the induced dipole gradient
c
      do i = 1, npolerecloc
         iipole = polerecglob(i)
         trq(1) = cmp(4,i)*cphirec(3,i) - cmp(3,i)*cphirec(4,i)
     &               + 2.0_ti_p*(cmp(7,i)-cmp(6,i))*cphirec(10,i)
     &               + cmp(9,i)*cphirec(8,i) + cmp(10,i)*cphirec(6,i)
     &               - cmp(8,i)*cphirec(9,i) - cmp(10,i)*cphirec(7,i)
         trq(2) = cmp(2,i)*cphirec(4,i) - cmp(4,i)*cphirec(2,i)
     &               + 2.0_ti_p*(cmp(5,i)-cmp(7,i))*cphirec(9,i)
     &               + cmp(8,i)*cphirec(10,i) + cmp(9,i)*cphirec(7,i)
     &               - cmp(9,i)*cphirec(5,i) - cmp(10,i)*cphirec(8,i)
         trq(3) = cmp(3,i)*cphirec(2,i) - cmp(2,i)*cphirec(3,i)
     &               + 2.0_ti_p*(cmp(6,i)-cmp(5,i))*cphirec(8,i)
     &               + cmp(8,i)*cphirec(5,i) + cmp(10,i)*cphirec(9,i)
     &               - cmp(8,i)*cphirec(6,i) - cmp(9,i)*cphirec(10,i)
         call torque_rec (iipole,trq,fix,fiy,fiz,deprec)
      end do
c
c     induced dipole contribution to the internal virial
c
      do i = 1, npolerecloc
         iipole = polerecglob(i)
         do j = 2, 4
            cphim(j) = 0.0_ti_p
            cphid(j) = 0.0_ti_p
            cphip(j) = 0.0_ti_p
            do k = 2, 4
               cphim(j) = cphim(j) + ftc(j,k)*fphirec(k,i)
               cphid(j) = cphid(j) + ftc(j,k)*fphid(k,i)
               cphip(j) = cphip(j) + ftc(j,k)*fphip(k,i)
            end do
         end do
         vxx = vxx - cphirec(2,i)*cmp(2,i)
     &         - 0.5_ti_p*(cphim(2)*(uind(1,iipole)+uinp(1,iipole))
     &         +cphid(2)*uinp(1,iipole)+cphip(2)*uind(1,iipole))
         vxy = vxy - 0.5_ti_p*(cphirec(2,i)*cmp(3,i)+cphirec(3,i)*
     $         cmp(2,i))
     &         - 0.25_ti_p*(cphim(2)*(uind(2,iipole)+uinp(2,iipole))
     &         +cphim(3)*(uind(1,iipole)+uinp(1,iipole))
     &         +cphid(2)*uinp(2,iipole)+cphip(2)*uind(2,iipole)
     &         +cphid(3)*uinp(1,iipole)+cphip(3)*uind(1,iipole))
         vxz = vxz - 0.5_ti_p*(cphirec(2,i)*cmp(4,i)+cphirec(4,i)*
     $         cmp(2,i))
     &         - 0.25_ti_p*(cphim(2)*(uind(3,iipole)+uinp(3,iipole))
     &         +cphim(4)*(uind(1,iipole)+uinp(1,iipole))
     &         +cphid(2)*uinp(3,iipole)+cphip(2)*uind(3,iipole)
     &         +cphid(4)*uinp(1,iipole)+cphip(4)*uind(1,iipole))
         vyy = vyy - cphirec(3,i)*cmp(3,i)
     &         - 0.5_ti_p*(cphim(3)*(uind(2,iipole)+uinp(2,iipole))
     &         +cphid(3)*uinp(2,iipole)+cphip(3)*uind(2,iipole))
         vyz = vyz - 0.5_ti_p*(cphirec(3,i)*cmp(4,i)+cphirec(4,i)*
     $         cmp(3,i))
     &         - 0.25_ti_p*(cphim(3)*(uind(3,iipole)+uinp(3,iipole))
     &         +cphim(4)*(uind(2,iipole)+uinp(2,iipole))
     &         +cphid(3)*uinp(3,iipole)+cphip(3)*uind(3,iipole)
     &         +cphid(4)*uinp(2,iipole)+cphip(4)*uind(2,iipole))
         vzz = vzz - cphirec(4,i)*cmp(4,i)
     &         - 0.5_ti_p*(cphim(4)*(uind(3,iipole)+uinp(3,iipole))
     &         +cphid(4)*uinp(3,iipole)+cphip(4)*uind(3,iipole))
         vxx = vxx - 2.0_ti_p*cmp(5,i)*cphirec(5,i) - cmp(8,i)*
     $         cphirec(8,i)
     &         - cmp(9,i)*cphirec(9,i)
         vxy = vxy - (cmp(5,i)+cmp(6,i))*cphirec(8,i)
     &         - 0.5_ti_p*(cmp(8,i)*(cphirec(6,i)+cphirec(5,i))
     &         +cmp(9,i)*cphirec(10,i)+cmp(10,i)*cphirec(9,i))
         vxz = vxz - (cmp(5,i)+cmp(7,i))*cphirec(9,i)
     &         - 0.5_ti_p*(cmp(9,i)*(cphirec(5,i)+cphirec(7,i))
     &          +cmp(8,i)*cphirec(10,i)+cmp(10,i)*cphirec(8,i))
         vyy = vyy - 2.0_ti_p*cmp(6,i)*cphirec(6,i) - cmp(8,i)*
     $         cphirec(8,i)
     &         - cmp(10,i)*cphirec(10,i)
         vyz = vyz - (cmp(6,i)+cmp(7,i))*cphirec(10,i)
     &         - 0.5_ti_p*(cmp(10,i)*(cphirec(6,i)+cphirec(7,i))
     &         +cmp(8,i)*cphirec(9,i)+cmp(9,i)*cphirec(8,i))
         vzz = vzz - 2.0_ti_p*cmp(7,i)*cphirec(7,i) -
     $             cmp(9,i)*cphirec(9,i)
     &             - cmp(10,i)*cphirec(10,i) 
      end do
c
c     perform deallocation of some local arrays
c
      deallocate (fuind)
      deallocate (fuinp)
      deallocate (fphid)
      deallocate (fphip)
      deallocate (fphidp)
c
c     perform dynamic allocation of some local arrays
c
      allocate (qgrip(2,isize2(rankloc+1),jsize2(rankloc+1),
     $ ksize2(rankloc+1)))
c
c     assign permanent and induced multipoles to the PME grid
c     and perform the 3-D FFT forward transformation
c
c
c    zero out the grid
c
      qgridin_2d = 0_ti_p
c
      do i = 1, npolerecloc
         iipole = polerecglob(i)
         iglob = ipole(iipole)
         do j = 2, 4
            cmp(j,i) = cmp(j,i) + uinp(j-1,iipole)
         end do
        call cmp_to_fmp_site (cmp(1,i),fmp(1,i))
        call grid_mpole_site(iglob,i,fmp(1,i))
      end do
c
c     MPI : Begin reception
c
      do i = 1, nrec_recep
        tag = nprocloc*rankloc + prec_recep(i) + 1
        call MPI_IRECV(qgridmpi(1,1,1,1,i),2*n1mpimax*n2mpimax*
     $   n3mpimax,MPI_TPREC,prec_recep(i),tag,
     $   commloc,reqrec(i),ierr)
      end do
c
c     MPI : begin sending
c
      time0 = mpi_wtime()
      do i = 1, nrec_send
        tag = nprocloc*prec_send(i) + rankloc + 1
        call MPI_ISEND(qgridin_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_TPREC,
     $   prec_send(i),tag,commloc,reqsend(i),ierr)
      end do
c
      do i = 1, nrec_recep
        call MPI_WAIT(reqrec(i),status,ierr)
      end do
      do i = 1, nrec_send
        call MPI_WAIT(reqsend(i),status,ierr)
      end do
c
c     do the reduction 'by hand'
c
      do i = 1, nrec_recep
        qgridin_2d(:,:,:,:,1) = qgridin_2d(:,:,:,:,1)+
     $   qgridmpi(:,:,:,:,i)
      end do
      time1 = mpi_wtime()
      timerecreccomm = timerecreccomm + time1 - time0
c
      time0 = mpi_wtime()
      call fft2d_frontmpi(qgridin_2d,qgridout_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
      do k = 1, ksize2(rankloc+1)
         do j = 1, jsize2(rankloc+1)
            do i = 1, isize2(rankloc+1)
               qgrip(1,i,j,k) = qgridout_2d(1,i,j,k)
               qgrip(2,i,j,k) = qgridout_2d(2,i,j,k)
            end do
         end do
      end do
c
c     zero out the PME grid
c
      qgridin_2d = 0_ti_p
      do i = 1, npolerecloc
         iipole = polerecglob(i)
         iglob = ipole(iipole)
         do j = 2, 4
            cmp(j,i) = cmp(j,i) + uind(j-1,iipole) - uinp(j-1,iipole)
         end do
         call cmp_to_fmp_site(cmp(1,i),fmp(1,i))
         call grid_mpole_site(iglob,i,fmp(1,i))
      end do
      time1 = mpi_wtime()
      timegrid1 = timegrid1 + time1 - time0
c
c     MPI : Begin reception
c
      do i = 1, nrec_recep
        tag = nprocloc*rankloc + prec_recep(i) + 1
        call MPI_IRECV(qgridmpi(1,1,1,1,i),2*n1mpimax*n2mpimax*
     $   n3mpimax,MPI_TPREC,prec_recep(i),tag,
     $   commloc,reqrec(i),ierr)
      end do
c
c     MPI : begin sending
c
      time0 = mpi_wtime()
      do i = 1, nrec_send
        tag = nprocloc*prec_send(i) + rankloc + 1
        call MPI_ISEND(qgridin_2d(1,1,1,1,i+1),
     $   2*n1mpimax*n2mpimax*n3mpimax,MPI_TPREC,
     $   prec_send(i),tag,commloc,reqsend(i),ierr)
      end do
c
      do i = 1, nrec_recep
        call MPI_WAIT(reqrec(i),status,ierr)
      end do
      do i = 1, nrec_send
        call MPI_WAIT(reqsend(i),status,ierr)
      end do
c
c     do the reduction 'by hand'
c
      do i = 1, nrec_recep
        qgridin_2d(:,:,:,:,1) = qgridin_2d(:,:,:,:,1)+
     $   qgridmpi(:,:,:,:,i)
      end do
      time1 = mpi_wtime()
      timerecreccomm = timerecreccomm + time1 - time0
c
      time0 = mpi_wtime()
      call fft2d_frontmpi(qgridin_2d,qgridout_2d,n1mpimax,n2mpimax,
     $ n3mpimax)
      time1 = mpi_wtime()
      timeffts = timeffts + time1 - time0
c
c     make the scalar summation over reciprocal lattice
c
      if ((istart2(rankloc+1).eq.1).and.(jstart2(rankloc+1).eq.1).and.
     $   (kstart2(rankloc+1).eq.1)) then
           qfac_2d(1,1,1) = 0.0_ti_p
      end if
      do k3 = kstart2(rankloc+1),kend2(rankloc+1)
        do k2 = jstart2(rankloc+1),jend2(rankloc+1)
          do k1 = istart2(rankloc+1),iend2(rankloc+1)
           m1 = k1 - 1
           m2 = k2 - 1
           m3 = k3 - 1
           if (k1 .gt. nf1)  m1 = m1 - nfft1
           if (k2 .gt. nf2)  m2 = m2 - nfft2
           if (k3 .gt. nf3)  m3 = m3 - nfft3
           if ((m1.eq.0).and.(m2.eq.0).and.(m3.eq.0)) goto 20
           r1 = real(m1,t_p)
           r2 = real(m2,t_p)
           r3 = real(m3,t_p)
           h1 = recip(1,1)*r1 + recip(1,2)*r2 + recip(1,3)*r3
           h2 = recip(2,1)*r1 + recip(2,2)*r2 + recip(2,3)*r3
           h3 = recip(3,1)*r1 + recip(3,2)*r2 + recip(3,3)*r3
           hsq = h1*h1 + h2*h2 + h3*h3
           term = -pterm * hsq
           expterm = 0.0_ti_p
           if (term .gt. -50.0_ti_p) then
              denom = volterm*hsq*bsmod1(k1)*bsmod2(k2)*bsmod3(k3)
              expterm = exp(term) / denom
              if (.not. use_bounds) then
                 expterm = expterm * (1.0_ti_p-cos(pi*xbox*sqrt(hsq)))
              else if (octahedron) then
                 if (mod(m1+m2+m3,2) .ne. 0)  expterm = 0.0_ti_p
              end if
              struc2 = qgridout_2d(1,k1-istart2(rankloc+1)+1,
     $         k2-jstart2(rankloc+1)+1,k3-kstart2(rankloc+1)+1)*
     $         qgrip(1,k1-istart2(rankloc+1)+1,
     $         k2-jstart2(rankloc+1)+1,
     $         k3-kstart2(rankloc+1)+1)
     &         + qgridout_2d(2,k1-istart2(rankloc+1)+1,k2-
     $         jstart2(rankloc+1)+1,k3-kstart2(rankloc+1)+1)*
     $         qgrip(2,k1-istart2(rankloc+1)+1,
     $         k2-jstart2(rankloc+1)+1,
     $         k3-kstart2(rankloc+1)+1)
              eterm = 0.5_ti_p * f * expterm * struc2
              vterm = (2.0_ti_p/hsq) * (1.0_ti_p-term) * eterm
              vxx = vxx + h1*h1*vterm - eterm
              vxy = vxy + h1*h2*vterm
              vxz = vxz + h1*h3*vterm
              vyy = vyy + h2*h2*vterm - eterm
              vyz = vyz + h2*h3*vterm
              vzz = vzz + h3*h3*vterm - eterm
           end if
           qfac_2d(k1-istart2(rankloc+1)+1,k2-jstart2(rankloc+1)+1,k3-
     $       kstart2(rankloc+1)+1) = expterm
 20         continue
         end do
       end do
      end do
c
c     increment the internal virial tensor components
c
      vir(1,1) = vir(1,1) + vxx
      vir(2,1) = vir(2,1) + vxy
      vir(3,1) = vir(3,1) + vxz
      vir(1,2) = vir(1,2) + vxy
      vir(2,2) = vir(2,2) + vyy
      vir(3,2) = vir(3,2) + vyz
      vir(1,3) = vir(1,3) + vxz
      vir(2,3) = vir(2,3) + vyz
      vir(3,3) = vir(3,3) + vzz
c
c     perform deallocation of some local arrays
c
      deallocate (qgrip)
c      deallocate (fuind)
c      deallocate (fuinp)
      deallocate (cmp)
      deallocate (fmp)
c      deallocate (fphid)
c      deallocate (fphip)
c      deallocate (fphidp)
      deallocate (qgridmpi)
      deallocate (reqsend)
      deallocate (reqrec)
      deallocate (req2send)
      deallocate (req2rec)
      
      call timer_exit( timer_eprecip )
      end
c
c
c     #################################################################
c     ##                                                             ##
c     ##  subroutine epreal1c  --  Ewald real space derivs via list  ##
c     ##                                                             ##
c     #################################################################
c
c
c     "epreal1d" evaluates the real space portion of the Ewald
c     summation energy and gradient due to dipole polarization
c     via a neighbor list
c
c
      subroutine epreal1c
      use atmlst
      use atoms
      use bound
      use chgpot
      use couple
      use deriv     ,only:dep
      use domdec
      use energi
      use ewald
      use inter
      use iounit
      use inform
      use math
      use molcul
      use mpole
      use neigh
      use polar
      use polgrp
      use polpot
      use potent
      use shunt
      use virial
      use mpi
      use timestat
      use tinheader ,only:ti_p,re_p
      implicit none
      integer i,j,k,iglob,kglob,kbis
      integer ii,kkk,iipole,kkpole
      integer iax,iay,iaz
      integer,pointer:: lst(:,:),nlst(:)
      real(t_p) e,efull,f
      real(t_p) erfc,bfac
      real(t_p) alsq2,alsq2n
      real(t_p) exp2a,ralpha
      real(t_p) damp,expdamp
      real(t_p) pdi,pti,pgamma
      real(t_p) temp3,temp5,temp7
      real(t_p) sc3,sc5,sc7
      real(t_p) psc3,psc5,psc7
      real(t_p) dsc3,dsc5,dsc7
      real(t_p) usc3,usc5
      real(t_p) psr3,psr5,psr7
      real(t_p) dsr3,dsr5,dsr7
      real(t_p) usr3,usr5
      real(t_p) xi,yi,zi
      real(t_p) xr,yr,zr
      real(t_p) r,r2,rr1,rr3
      real(t_p) rr5,rr7,rr9
      real(t_p) ci,dix,diy,diz
      real(t_p) qixx,qixy,qixz
      real(t_p) qiyy,qiyz,qizz
      real(t_p) uix,uiy,uiz
      real(t_p) uixp,uiyp,uizp
      real(t_p) ck,dkx,dky,dkz
      real(t_p) qkxx,qkxy,qkxz
      real(t_p) qkyy,qkyz,qkzz
      real(t_p) ukx,uky,ukz
      real(t_p) ukxp,ukyp,ukzp
      real(t_p) dri,drk
      real(t_p) qrix,qriy,qriz
      real(t_p) qrkx,qrky,qrkz
      real(t_p) qrri,qrrk
      real(t_p) duik,quik
      real(t_p) txxi,tyyi,tzzi
      real(t_p) txyi,txzi,tyzi
      real(t_p) txxk,tyyk,tzzk
      real(t_p) txyk,txzk,tyzk
      real(t_p) uri,urip,turi
      real(t_p) urk,urkp,turk

      real(t_p) txi3,tyi3,tzi3
      real(t_p) txi5,tyi5,tzi5
      real(t_p) txk3,tyk3,tzk3
      real(t_p) txk5,tyk5,tzk5
      real(t_p) term1,term2,term3
      real(t_p) term4,term5
      real(t_p) term6,term7
      real(t_p) depx,depy,depz
      real(t_p) frcx,frcy,frcz
      real(t_p) xix,yix,zix
      real(t_p) xiy,yiy,ziy
      real(t_p) xiz,yiz,ziz
      real(t_p) vxx,vyy,vzz
      real(t_p) vxy,vxz,vyz
      real(t_p) rc3(3),rc5(3),rc7(3)
      real(t_p) prc3(3),prc5(3),prc7(3)
      real(t_p) drc3(3),drc5(3),drc7(3)
      real(t_p) urc3(3),urc5(3)
      real(t_p) trq(3),fix(3)
      real(t_p) fiy(3),fiz(3)
      real(t_p) bn(0:4)
      real(t_p), allocatable :: pscale(:)
      real(t_p), allocatable :: dscale(:)
      real(t_p), allocatable :: uscale(:)
      real(t_p), allocatable :: ufld(:,:)
      real(t_p), allocatable :: dufld(:,:)
      character*10 mode
 1000 format(' Warning, system moved too much since last neighbor list',
     $   ' update, try lowering nlupdate')
c
      if (deb_Path) write(*,'(2x,a)') 'epreal1c'
      call timer_enter( timer_epreal )
c
c     perform dynamic allocation of some local arrays
c
      allocate (pscale(n))
      allocate (dscale(n))
      allocate (uscale(n))
      allocate (ufld(3,nbloc))
      allocate (dufld(6,nbloc))
c
c     set exclusion coefficients and arrays to store fields
c
      pscale = 1.0_ti_p
      dscale = 1.0_ti_p
      uscale = 1.0_ti_p
      ufld = 0.0_ti_p
      dufld = 0.0_ti_p
      if(rank.eq.0.and.tinkerdebug) write (*,*) 'epreal1c'

c
c     set conversion factor, cutoff and switching coefficients
c
      f = 0.5_ti_p * electric / dielec
      if (use_polarshortreal) then 
         mode  = 'SHORTEWALD'
          lst  =>  shortelst
         nlst  => nshortelst
      else
         mode  = 'EWALD'
          lst  =>  elst
         nlst  => nelst
      endif
      call switch (mode)
c
c     OpenMP directives for the major loop structure
c
c     compute the dipole polarization gradient components
c
      do ii = 1, npolelocnl
         iipole = poleglobnl(ii)
         iglob = ipole(iipole)
         i = loc(iglob)
         if ((i.eq.0).or.(i.gt.nbloc)) then
           write(iout,1000)
           cycle
         end if
         pdi = pdamp(iipole)
         pti = thole(iipole)
         xi = x(iglob)
         yi = y(iglob)
         zi = z(iglob)
         ci = rpole(1,iipole)
         dix = rpole(2,iipole)
         diy = rpole(3,iipole)
         diz = rpole(4,iipole)
         qixx = rpole(5,iipole)
         qixy = rpole(6,iipole)
         qixz = rpole(7,iipole)
         qiyy = rpole(9,iipole)
         qiyz = rpole(10,iipole)
         qizz = rpole(13,iipole)
         uix = uind(1,iipole)
         uiy = uind(2,iipole)
         uiz = uind(3,iipole)
         uixp = uinp(1,iipole)
         uiyp = uinp(2,iipole)
         uizp = uinp(3,iipole)
         do j = 1, n12(iglob)
            pscale(i12(j,iglob)) = p2scale
         end do
         do j = 1, n13(iglob)
            pscale(i13(j,iglob)) = p3scale
         end do
         do j = 1, n14(iglob)
            pscale(i14(j,iglob)) = p4scale
            do k = 1, np11(iglob)
                if (i14(j,iglob) .eq. ip11(k,iglob))
     &            pscale(i14(j,iglob)) = p4scale * p41scale
            end do
         end do
         do j = 1, n15(iglob)
            pscale(i15(j,iglob)) = p5scale
         end do
         do j = 1, np11(iglob)
            dscale(ip11(j,iglob)) = d1scale
            uscale(ip11(j,iglob)) = u1scale
         end do
         do j = 1, np12(iglob)
            dscale(ip12(j,iglob)) = d2scale
            uscale(ip12(j,iglob)) = u2scale
         end do
         do j = 1, np13(iglob)
            dscale(ip13(j,iglob)) = d3scale
            uscale(ip13(j,iglob)) = u3scale
         end do
         do j = 1, np14(iglob)
            dscale(ip14(j,iglob)) = d4scale
            uscale(ip14(j,iglob)) = u4scale
         end do
c
c     evaluate all sites within the cutoff distance
c
         do kkk = 1, nlst(ii)
            kkpole = lst(kkk,ii)
            kglob = ipole(kkpole)
            kbis = loc(kglob)
            if (kbis.eq.0) then
              write(iout,1000)
              cycle
            end if
            xr = x(kglob) - xi
            yr = y(kglob) - yi
            zr = z(kglob) - zi
            if (use_bounds)  call image (xr,yr,zr)
            r2 = xr*xr + yr*yr + zr*zr
            if (r2 .le. off2) then
               r = sqrt(r2)
               ck = rpole(1,kkpole)
               dkx = rpole(2,kkpole)
               dky = rpole(3,kkpole)
               dkz = rpole(4,kkpole)
               qkxx = rpole(5,kkpole)
               qkxy = rpole(6,kkpole)
               qkxz = rpole(7,kkpole)
               qkyy = rpole(9,kkpole)
               qkyz = rpole(10,kkpole)
               qkzz = rpole(13,kkpole)
               ukx = uind(1,kkpole)
               uky = uind(2,kkpole)
               ukz = uind(3,kkpole)
               ukxp = uinp(1,kkpole)
               ukyp = uinp(2,kkpole)
               ukzp = uinp(3,kkpole)
c
c     get reciprocal distance terms for this interaction
c
               rr1 = f / r
               rr3 = rr1 / r2
               rr5 = 3.0_ti_p * rr3 / r2
               rr7 = 5.0_ti_p * rr5 / r2
               rr9 = 7.0_ti_p * rr7 / r2
c
c     calculate the real space Ewald error function terms
c
               ralpha = aewald * r
               bn(0) = erfc(ralpha) / r
               alsq2 = 2.0_ti_p * aewald**2
               alsq2n = 0.0_ti_p
               if (aewald .gt. 0.0_ti_p)
     &            alsq2n = 1.0_ti_p / (sqrtpi*aewald)
               exp2a = exp(-ralpha**2)
               do j = 1, 4
                  bfac = real(j+j-1,t_p)
                  alsq2n = alsq2 * alsq2n
                  bn(j) = (bfac*bn(j-1)+alsq2n*exp2a) / r2
               end do
               do j = 0, 4
                  bn(j) = f * bn(j)
               end do
c
c     apply Thole polarization damping to scale factors
c
               sc3 = 1.0_ti_p
               sc5 = 1.0_ti_p
               sc7 = 1.0_ti_p
               do j = 1, 3
                  rc3(j) = 0.0_ti_p
                  rc5(j) = 0.0_ti_p
                  rc7(j) = 0.0_ti_p
               end do
               damp = pdi * pdamp(kkpole)
               if (damp .ne. 0.0_ti_p) then
                  pgamma = min(pti,thole(kkpole))
                  damp = -pgamma * (r/damp)**3
                  if (damp .gt. -50.0_ti_p) then
                     expdamp = exp(damp)
                     sc3 = 1.0_ti_p - expdamp
                     sc5 = 1.0_ti_p - (1.0_ti_p-damp)*expdamp
                     sc7 = 1.0_ti_p - (1.0_ti_p-damp+0.6_ti_p*damp**2)
     &                                    *expdamp
                     temp3 = -3.0_ti_p * damp * expdamp / r2
                     temp5 = -damp
                     temp7 = -0.2_ti_p - 0.6_ti_p*damp
                     rc3(1) = xr * temp3
                     rc3(2) = yr * temp3
                     rc3(3) = zr * temp3
                     rc5(1) = rc3(1) * temp5
                     rc5(2) = rc3(2) * temp5
                     rc5(3) = rc3(3) * temp5
                     rc7(1) = rc5(1) * temp7
                     rc7(2) = rc5(2) * temp7
                     rc7(3) = rc5(3) * temp7
                  end if
               end if
c
c     intermediates involving moments and distance separation
c
               dri = dix*xr + diy*yr + diz*zr
               drk = dkx*xr + dky*yr + dkz*zr
               qrix = qixx*xr + qixy*yr + qixz*zr
               qriy = qixy*xr + qiyy*yr + qiyz*zr
               qriz = qixz*xr + qiyz*yr + qizz*zr
               qrkx = qkxx*xr + qkxy*yr + qkxz*zr
               qrky = qkxy*xr + qkyy*yr + qkyz*zr
               qrkz = qkxz*xr + qkyz*yr + qkzz*zr
               qrri = qrix*xr + qriy*yr + qriz*zr
               qrrk = qrkx*xr + qrky*yr + qrkz*zr
               uri = uix*xr + uiy*yr + uiz*zr
               urk = ukx*xr + uky*yr + ukz*zr
               urip = uixp*xr + uiyp*yr + uizp*zr
               urkp = ukxp*xr + ukyp*yr + ukzp*zr
               duik = dix*ukx + diy*uky + diz*ukz
     &                   + dkx*uix + dky*uiy + dkz*uiz
               quik = qrix*ukx + qriy*uky + qriz*ukz
     &                   - qrkx*uix - qrky*uiy - qrkz*uiz
c
c     calculate intermediate terms for polarization interaction
c
               term1 = ck*uri - ci*urk + duik
               term2 = 2.0_ti_p*quik - uri*drk - dri*urk
               term3 = uri*qrrk - urk*qrri
c
c     intermediates involving Thole damping and scale factors
c
               psr3 = rr3 * sc3 * pscale(kglob)
               psr5 = rr5 * sc5 * pscale(kglob)
               psr7 = rr7 * sc7 * pscale(kglob)
c
c     compute the full undamped energy for this interaction
c
               efull = term1*psr3 + term2*psr5 + term3*psr7
               if (molcule(iglob) .ne. molcule(kglob))
     &            einter = einter + efull
c
c     intermediates involving Thole damping and scale factors
c
               psc3 = 1.0_ti_p - sc3*pscale(kglob)
               psc5 = 1.0_ti_p - sc5*pscale(kglob)
               psc7 = 1.0_ti_p - sc7*pscale(kglob)
               dsc3 = 1.0_ti_p - sc3*dscale(kglob)
               dsc5 = 1.0_ti_p - sc5*dscale(kglob)
               dsc7 = 1.0_ti_p - sc7*dscale(kglob)
               usc3 = 1.0_ti_p - sc3*uscale(kglob)
               usc5 = 1.0_ti_p - sc5*uscale(kglob)
               psr3 = bn(1) - psc3*rr3
               psr5 = bn(2) - psc5*rr5
               psr7 = bn(3) - psc7*rr7
               dsr3 = bn(1) - dsc3*rr3
               dsr5 = bn(2) - dsc5*rr5
               dsr7 = bn(3) - dsc7*rr7
               usr3 = bn(1) - usc3*rr3
               usr5 = bn(2) - usc5*rr5
               do j = 1, 3
                  prc3(j) = rc3(j) * pscale(kglob)
                  prc5(j) = rc5(j) * pscale(kglob)
                  prc7(j) = rc7(j) * pscale(kglob)
                  drc3(j) = rc3(j) * dscale(kglob)
                  drc5(j) = rc5(j) * dscale(kglob)
                  drc7(j) = rc7(j) * dscale(kglob)
                  urc3(j) = rc3(j) * uscale(kglob)
                  urc5(j) = rc5(j) * uscale(kglob)
               end do
c
c     compute the energy contribution for this interaction
c
               e = term1*psr3 + term2*psr5 + term3*psr7
               ep = ep + e
c
c     get the dEd/dR terms used for direct polarization force
c
               term1 = bn(2) - dsc3*rr5
               term2 = bn(3) - dsc5*rr7
               term3 = -dsr3 + term1*xr*xr - rr3*xr*drc3(1)
               term4 = rr3*drc3(1) - term1*xr - dsr5*xr
               term5 = term2*xr*xr - dsr5 - rr5*xr*drc5(1)
               term6 = (bn(4)-dsc7*rr9)*xr*xr - bn(3) - rr7*xr*drc7(1)
               term7 = rr5*drc5(1) - 2.0_ti_p*bn(3)*xr
     &                    + (dsc5+1.5_ti_p*dsc7)*rr7*xr
               txxi = ci*term3 + dix*term4 + dri*term5
     &                 + 2.0_ti_p*dsr5*qixx + (qriy*yr+qriz*zr)*dsc7*rr7
     &                 + 2.0_ti_p*qrix*term7 + qrri*term6
               txxk = ck*term3 - dkx*term4 - drk*term5
     &                 + 2.0_ti_p*dsr5*qkxx + (qrky*yr+qrkz*zr)*dsc7*rr7
     &                 + 2.0_ti_p*qrkx*term7 + qrrk*term6
               term3 = -dsr3 + term1*yr*yr - rr3*yr*drc3(2)
               term4 = rr3*drc3(2) - term1*yr - dsr5*yr
               term5 = term2*yr*yr - dsr5 - rr5*yr*drc5(2)
               term6 = (bn(4)-dsc7*rr9)*yr*yr - bn(3) - rr7*yr*drc7(2)
               term7 = rr5*drc5(2) - 2.0_ti_p*bn(3)*yr
     &                    + (dsc5+1.5_ti_p*dsc7)*rr7*yr
               tyyi = ci*term3 + diy*term4 + dri*term5
     &                 + 2.0_ti_p*dsr5*qiyy + (qrix*xr+qriz*zr)*dsc7*rr7
     &                 + 2.0_ti_p*qriy*term7 + qrri*term6
               tyyk = ck*term3 - dky*term4 - drk*term5
     &                 + 2.0_ti_p*dsr5*qkyy + (qrkx*xr+qrkz*zr)*dsc7*rr7
     &                 + 2.0_ti_p*qrky*term7 + qrrk*term6
               term3 = -dsr3 + term1*zr*zr - rr3*zr*drc3(3)
               term4 = rr3*drc3(3) - term1*zr - dsr5*zr
               term5 = term2*zr*zr - dsr5 - rr5*zr*drc5(3)
               term6 = (bn(4)-dsc7*rr9)*zr*zr - bn(3) - rr7*zr*drc7(3)
               term7 = rr5*drc5(3) - 2.0_ti_p*bn(3)*zr
     &                    + (dsc5+1.5_ti_p*dsc7)*rr7*zr
               tzzi = ci*term3 + diz*term4 + dri*term5
     &                 + 2.0_ti_p*dsr5*qizz + (qrix*xr+qriy*yr)*dsc7*rr7
     &                 + 2.0_ti_p*qriz*term7 + qrri*term6
               tzzk = ck*term3 - dkz*term4 - drk*term5
     &                 + 2.0_ti_p*dsr5*qkzz + (qrkx*xr+qrky*yr)*dsc7*rr7
     &                 + 2.0_ti_p*qrkz*term7 + qrrk*term6
               term3 = term1*xr*yr - rr3*yr*drc3(1)
               term4 = rr3*drc3(1) - term1*xr
               term5 = term2*xr*yr - rr5*yr*drc5(1)
               term6 = (bn(4)-dsc7*rr9)*xr*yr - rr7*yr*drc7(1)
               term7 = rr5*drc5(1) - term2*xr
               txyi = ci*term3 - dsr5*dix*yr + diy*term4 + dri*term5
     &                   + 2.0_ti_p*dsr5*qixy - 2.0_ti_p*dsr7*yr*qrix
     &                   + 2.0_ti_p*qriy*term7 + qrri*term6
               txyk = ck*term3 + dsr5*dkx*yr - dky*term4 - drk*term5
     &                   + 2.0_ti_p*dsr5*qkxy - 2.0_ti_p*dsr7*yr*qrkx
     &                   + 2.0_ti_p*qrky*term7 + qrrk*term6
               term3 = term1*xr*zr - rr3*zr*drc3(1)
               term5 = term2*xr*zr - rr5*zr*drc5(1)
               term6 = (bn(4)-dsc7*rr9)*xr*zr - rr7*zr*drc7(1)
               txzi = ci*term3 - dsr5*dix*zr + diz*term4 + dri*term5
     &                   + 2.0_ti_p*dsr5*qixz - 2.0_ti_p*dsr7*zr*qrix
     &                   + 2.0_ti_p*qriz*term7 + qrri*term6
               txzk = ck*term3 + dsr5*dkx*zr - dkz*term4 - drk*term5
     &                   + 2.0_ti_p*dsr5*qkxz - 2.0_ti_p*dsr7*zr*qrkx
     &                   + 2.0_ti_p*qrkz*term7 + qrrk*term6
               term3 = term1*yr*zr - rr3*zr*drc3(2)
               term4 = rr3*drc3(2) - term1*yr
               term5 = term2*yr*zr - rr5*zr*drc5(2)
               term6 = (bn(4)-dsc7*rr9)*yr*zr - rr7*zr*drc7(2)
               term7 = rr5*drc5(2) - term2*yr
               tyzi = ci*term3 - dsr5*diy*zr + diz*term4 + dri*term5
     &                   + 2.0_ti_p*dsr5*qiyz - 2.0_ti_p*dsr7*zr*qriy
     &                   + 2.0_ti_p*qriz*term7 + qrri*term6
               tyzk = ck*term3 + dsr5*dky*zr - dkz*term4 - drk*term5
     &                   + 2.0_ti_p*dsr5*qkyz - 2.0_ti_p*dsr7*zr*qrky
     &                   + 2.0_ti_p*qrkz*term7 + qrrk*term6
               depx = txxi*ukxp + txyi*ukyp + txzi*ukzp
     &                   - txxk*uixp - txyk*uiyp - txzk*uizp
               depy = txyi*ukxp + tyyi*ukyp + tyzi*ukzp
     &                   - txyk*uixp - tyyk*uiyp - tyzk*uizp
               depz = txzi*ukxp + tyzi*ukyp + tzzi*ukzp
     &                   - txzk*uixp - tyzk*uiyp - tzzk*uizp
               frcx = depx
               frcy = depy
               frcz = depz
c
c     get the dEp/dR terms used for direct polarization force
c
               term1 = bn(2) - psc3*rr5
               term2 = bn(3) - psc5*rr7
               term3 = -psr3 + term1*xr*xr - rr3*xr*prc3(1)
               term4 = rr3*prc3(1) - term1*xr - psr5*xr
               term5 = term2*xr*xr - psr5 - rr5*xr*prc5(1)
               term6 = (bn(4)-psc7*rr9)*xr*xr - bn(3) - rr7*xr*prc7(1)
               term7 = rr5*prc5(1) - 2.0_ti_p*bn(3)*xr
     &                    + (psc5+1.5_ti_p*psc7)*rr7*xr
               txxi = ci*term3 + dix*term4 + dri*term5
     &                 + 2.0_ti_p*psr5*qixx + (qriy*yr+qriz*zr)*psc7*rr7
     &                 + 2.0_ti_p*qrix*term7 + qrri*term6
               txxk = ck*term3 - dkx*term4 - drk*term5
     &                 + 2.0_ti_p*psr5*qkxx + (qrky*yr+qrkz*zr)*psc7*rr7
     &                 + 2.0_ti_p*qrkx*term7 + qrrk*term6
               term3 = -psr3 + term1*yr*yr - rr3*yr*prc3(2)
               term4 = rr3*prc3(2) - term1*yr - psr5*yr
               term5 = term2*yr*yr - psr5 - rr5*yr*prc5(2)
               term6 = (bn(4)-psc7*rr9)*yr*yr - bn(3) - rr7*yr*prc7(2)
               term7 = rr5*prc5(2) - 2.0_ti_p*bn(3)*yr
     &                    + (psc5+1.5_ti_p*psc7)*rr7*yr
               tyyi = ci*term3 + diy*term4 + dri*term5
     &                 + 2.0_ti_p*psr5*qiyy + (qrix*xr+qriz*zr)*psc7*rr7
     &                 + 2.0_ti_p*qriy*term7 + qrri*term6
               tyyk = ck*term3 - dky*term4 - drk*term5
     &                 + 2.0_ti_p*psr5*qkyy + (qrkx*xr+qrkz*zr)*psc7*rr7
     &                 + 2.0_ti_p*qrky*term7 + qrrk*term6
               term3 = -psr3 + term1*zr*zr - rr3*zr*prc3(3)
               term4 = rr3*prc3(3) - term1*zr - psr5*zr
               term5 = term2*zr*zr - psr5 - rr5*zr*prc5(3)
               term6 = (bn(4)-psc7*rr9)*zr*zr - bn(3) - rr7*zr*prc7(3)
               term7 = rr5*prc5(3) - 2.0_ti_p*bn(3)*zr
     &                    + (psc5+1.5_ti_p*psc7)*rr7*zr
               tzzi = ci*term3 + diz*term4 + dri*term5
     &                 + 2.0_ti_p*psr5*qizz + (qrix*xr+qriy*yr)*psc7*rr7
     &                 + 2.0_ti_p*qriz*term7 + qrri*term6
               tzzk = ck*term3 - dkz*term4 - drk*term5
     &                 + 2.0_ti_p*psr5*qkzz + (qrkx*xr+qrky*yr)*psc7*rr7
     &                 + 2.0_ti_p*qrkz*term7 + qrrk*term6
               term3 = term1*xr*yr - rr3*yr*prc3(1)
               term4 = rr3*prc3(1) - term1*xr
               term5 = term2*xr*yr - rr5*yr*prc5(1)
               term6 = (bn(4)-psc7*rr9)*xr*yr - rr7*yr*prc7(1)
               term7 = rr5*prc5(1) - term2*xr
               txyi = ci*term3 - psr5*dix*yr + diy*term4 + dri*term5
     &                   + 2.0_ti_p*psr5*qixy - 2.0_ti_p*psr7*yr*qrix
     &                   + 2.0_ti_p*qriy*term7 + qrri*term6
               txyk = ck*term3 + psr5*dkx*yr - dky*term4 - drk*term5
     &                   + 2.0_ti_p*psr5*qkxy - 2.0_ti_p*psr7*yr*qrkx
     &                   + 2.0_ti_p*qrky*term7 + qrrk*term6
               term3 = term1*xr*zr - rr3*zr*prc3(1)
               term5 = term2*xr*zr - rr5*zr*prc5(1)
               term6 = (bn(4)-psc7*rr9)*xr*zr - rr7*zr*prc7(1)
               txzi = ci*term3 - psr5*dix*zr + diz*term4 + dri*term5
     &                   + 2.0_ti_p*psr5*qixz - 2.0_ti_p*psr7*zr*qrix
     &                   + 2.0_ti_p*qriz*term7 + qrri*term6
               txzk = ck*term3 + psr5*dkx*zr - dkz*term4 - drk*term5
     &                   + 2.0_ti_p*psr5*qkxz - 2.0_ti_p*psr7*zr*qrkx
     &                   + 2.0_ti_p*qrkz*term7 + qrrk*term6
               term3 = term1*yr*zr - rr3*zr*prc3(2)
               term4 = rr3*prc3(2) - term1*yr
               term5 = term2*yr*zr - rr5*zr*prc5(2)
               term6 = (bn(4)-psc7*rr9)*yr*zr - rr7*zr*prc7(2)
               term7 = rr5*prc5(2) - term2*yr
               tyzi = ci*term3 - psr5*diy*zr + diz*term4 + dri*term5
     &                   + 2.0_ti_p*psr5*qiyz - 2.0_ti_p*psr7*zr*qriy
     &                   + 2.0_ti_p*qriz*term7 + qrri*term6
               tyzk = ck*term3 + psr5*dky*zr - dkz*term4 - drk*term5
     &                   + 2.0_ti_p*psr5*qkyz - 2.0_ti_p*psr7*zr*qrky
     &                   + 2.0_ti_p*qrkz*term7 + qrrk*term6
               depx = txxi*ukx + txyi*uky + txzi*ukz
     &                   - txxk*uix - txyk*uiy - txzk*uiz
               depy = txyi*ukx + tyyi*uky + tyzi*ukz
     &                   - txyk*uix - tyyk*uiy - tyzk*uiz
               depz = txzi*ukx + tyzi*uky + tzzi*ukz
     &                   - txzk*uix - tyzk*uiy - tzzk*uiz
               frcx = frcx + depx
               frcy = frcy + depy
               frcz = frcz + depz
c
c     get the dtau/dr terms used for mutual polarization force
c
               term1 = bn(2) - usc3*rr5
               term2 = bn(3) - usc5*rr7
               term3 = usr5 + term1
               term4 = rr3 * uscale(kglob)
               term5 = -xr*term3 + rc3(1)*term4
               term6 = -usr5 + xr*xr*term2 - rr5*xr*urc5(1)
               txxi = uix*term5 + uri*term6
               txxk = ukx*term5 + urk*term6
               term5 = -yr*term3 + rc3(2)*term4
               term6 = -usr5 + yr*yr*term2 - rr5*yr*urc5(2)
               tyyi = uiy*term5 + uri*term6
               tyyk = uky*term5 + urk*term6
               term5 = -zr*term3 + rc3(3)*term4
               term6 = -usr5 + zr*zr*term2 - rr5*zr*urc5(3)
               tzzi = uiz*term5 + uri*term6
               tzzk = ukz*term5 + urk*term6
               term4 = -usr5 * yr
               term5 = -xr*term1 + rr3*urc3(1)
               term6 = xr*yr*term2 - rr5*yr*urc5(1)
               txyi = uix*term4 + uiy*term5 + uri*term6
               txyk = ukx*term4 + uky*term5 + urk*term6
               term4 = -usr5 * zr
               term6 = xr*zr*term2 - rr5*zr*urc5(1)
               txzi = uix*term4 + uiz*term5 + uri*term6
               txzk = ukx*term4 + ukz*term5 + urk*term6
               term5 = -yr*term1 + rr3*urc3(2)
               term6 = yr*zr*term2 - rr5*zr*urc5(2)
               tyzi = uiy*term4 + uiz*term5 + uri*term6
               tyzk = uky*term4 + ukz*term5 + urk*term6
               depx = txxi*ukxp + txyi*ukyp + txzi*ukzp
     &                   + txxk*uixp + txyk*uiyp + txzk*uizp
               depy = txyi*ukxp + tyyi*ukyp + tyzi*ukzp
     &                   + txyk*uixp + tyyk*uiyp + tyzk*uizp
               depz = txzi*ukxp + tyzi*ukyp + tzzi*ukzp
     &                   + txzk*uixp + tyzk*uiyp + tzzk*uizp
               frcx = frcx + depx
               frcy = frcy + depy
               frcz = frcz + depz
c
c     increment gradient and virial due to Cartesian forces
c
               dep(1,i) = dep(1,i) - frcx
               dep(2,i) = dep(2,i) - frcy
               dep(3,i) = dep(3,i) - frcz
               dep(1,kbis) = dep(1,kbis) + frcx
               dep(2,kbis) = dep(2,kbis) + frcy
               dep(3,kbis) = dep(3,kbis) + frcz
               vxx = xr * frcx
               vxy = yr * frcx
               vxz = zr * frcx
               vyy = yr * frcy
               vyz = zr * frcy
               vzz = zr * frcz
               vir(1,1) = vir(1,1) + vxx
               vir(2,1) = vir(2,1) + vxy
               vir(3,1) = vir(3,1) + vxz
               vir(1,2) = vir(1,2) + vxy
               vir(2,2) = vir(2,2) + vyy
               vir(3,2) = vir(3,2) + vyz
               vir(1,3) = vir(1,3) + vxz
               vir(2,3) = vir(2,3) + vyz
               vir(3,3) = vir(3,3) + vzz
c
c     get the induced dipole field used for dipole torques
c
               txi3 = psr3*ukx + dsr3*ukxp
               tyi3 = psr3*uky + dsr3*ukyp
               tzi3 = psr3*ukz + dsr3*ukzp
               txk3 = psr3*uix + dsr3*uixp
               tyk3 = psr3*uiy + dsr3*uiyp
               tzk3 = psr3*uiz + dsr3*uizp
               turi = -psr5*urk - dsr5*urkp
               turk = -psr5*uri - dsr5*urip
               ufld(1,i) = ufld(1,i) + txi3 + xr*turi
               ufld(2,i) = ufld(2,i) + tyi3 + yr*turi
               ufld(3,i) = ufld(3,i) + tzi3 + zr*turi
               ufld(1,kbis) = ufld(1,kbis) + txk3 + xr*turk
               ufld(2,kbis) = ufld(2,kbis) + tyk3 + yr*turk
               ufld(3,kbis) = ufld(3,kbis) + tzk3 + zr*turk
c
c     get induced dipole field gradient used for quadrupole torques
c
               txi5 = 2.0_ti_p * (psr5*ukx+dsr5*ukxp)
               tyi5 = 2.0_ti_p * (psr5*uky+dsr5*ukyp)
               tzi5 = 2.0_ti_p * (psr5*ukz+dsr5*ukzp)
               txk5 = 2.0_ti_p * (psr5*uix+dsr5*uixp)
               tyk5 = 2.0_ti_p * (psr5*uiy+dsr5*uiyp)
               tzk5 = 2.0_ti_p * (psr5*uiz+dsr5*uizp)
               turi = -psr7*urk - dsr7*urkp
               turk = -psr7*uri - dsr7*urip
               dufld(1,i) = dufld(1,i) + xr*txi5 + xr*xr*turi
               dufld(2,i) = dufld(2,i) + xr*tyi5 + yr*txi5
     &                         + 2.0_ti_p*xr*yr*turi
               dufld(3,i) = dufld(3,i) + yr*tyi5 + yr*yr*turi
               dufld(4,i) = dufld(4,i) + xr*tzi5 + zr*txi5
     &                         + 2.0_ti_p*xr*zr*turi
               dufld(5,i) = dufld(5,i) + yr*tzi5 + zr*tyi5
     &                         + 2.0_ti_p*yr*zr*turi
               dufld(6,i) = dufld(6,i) + zr*tzi5 + zr*zr*turi
               dufld(1,kbis) = dufld(1,kbis) - xr*txk5 - xr*xr*turk
               dufld(2,kbis) = dufld(2,kbis) - xr*tyk5 - yr*txk5
     &                         - 2.0_ti_p*xr*yr*turk
               dufld(3,kbis) = dufld(3,kbis) - yr*tyk5 - yr*yr*turk
               dufld(4,kbis) = dufld(4,kbis) - xr*tzk5 - zr*txk5
     &                         - 2.0_ti_p*xr*zr*turk
               dufld(5,kbis) = dufld(5,kbis) - yr*tzk5 - zr*tyk5
     &                         - 2.0_ti_p*yr*zr*turk
               dufld(6,kbis) = dufld(6,kbis) - zr*tzk5 - zr*zr*turk
            end if
         end do
c
c     reset exclusion coefficients for connected atoms
c
         do j = 1, n12(iglob)
            pscale(i12(j,iglob)) = 1.0_ti_p
         end do
         do j = 1, n13(iglob)
            pscale(i13(j,iglob)) = 1.0_ti_p
         end do
         do j = 1, n14(iglob)
            pscale(i14(j,iglob)) = 1.0_ti_p
         end do
         do j = 1, n15(iglob)
            pscale(i15(j,iglob)) = 1.0_ti_p
         end do
         do j = 1, np11(iglob)
            dscale(ip11(j,iglob)) = 1.0_ti_p
            uscale(ip11(j,iglob)) = 1.0_ti_p
         end do
         do j = 1, np12(iglob)
            dscale(ip12(j,iglob)) = 1.0_ti_p
            uscale(ip12(j,iglob)) = 1.0_ti_p
         end do
         do j = 1, np13(iglob)
            dscale(ip13(j,iglob)) = 1.0_ti_p
            uscale(ip13(j,iglob)) = 1.0_ti_p
         end do
         do j = 1, np14(iglob)
            dscale(ip14(j,iglob)) = 1.0_ti_p
            uscale(ip14(j,iglob)) = 1.0_ti_p
         end do
      end do
c
c     OpenMP directives for the major loop structure
c
c
c     torque is induced field and gradient cross permanent moments
c
      do ii = 1, npolelocnl
         iipole = poleglobnl(ii)
         iglob = ipole(iipole)
         i = loc(iglob)
         dix = rpole(2,iipole)
         diy = rpole(3,iipole)
         diz = rpole(4,iipole)
         qixx = rpole(5,iipole)
         qixy = rpole(6,iipole)
         qixz = rpole(7,iipole)
         qiyy = rpole(9,iipole)
         qiyz = rpole(10,iipole)
         qizz = rpole(13,iipole)
         trq(1) = diz*ufld(2,i) - diy*ufld(3,i)
     &               + qixz*dufld(2,i) - qixy*dufld(4,i)
     &               + 2.0_ti_p*qiyz*(dufld(3,i)-dufld(6,i))
     &               + (qizz-qiyy)*dufld(5,i)
         trq(2) = dix*ufld(3,i) - diz*ufld(1,i)
     &               - qiyz*dufld(2,i) + qixy*dufld(5,i)
     &               + 2.0_ti_p*qixz*(dufld(6,i)-dufld(1,i))
     &               + (qixx-qizz)*dufld(4,i)
         trq(3) = diy*ufld(1,i) - dix*ufld(2,i)
     &               + qiyz*dufld(4,i) - qixz*dufld(5,i)
     &               + 2.0_ti_p*qixy*(dufld(1,i)-dufld(3,i))
     &               + (qiyy-qixx)*dufld(2,i)
         call torque (iipole,trq,fix,fiy,fiz,dep)
         iaz = zaxis(iipole)
         iax = xaxis(iipole)
         iay = yaxis(iipole)
         if (iaz .le. 0)  iaz = iglob
         if (iax .le. 0)  iax = iglob
         if (iay .le. 0)  iay = iglob
         xiz = x(iaz) - x(iglob)
         yiz = y(iaz) - y(iglob)
         ziz = z(iaz) - z(iglob)
         xix = x(iax) - x(iglob)
         yix = y(iax) - y(iglob)
         zix = z(iax) - z(iglob)
         xiy = x(iay) - x(iglob)
         yiy = y(iay) - y(iglob)
         ziy = z(iay) - z(iglob)
         vxx = xix*fix(1) + xiy*fiy(1) + xiz*fiz(1)
         vxy = yix*fix(1) + yiy*fiy(1) + yiz*fiz(1)
         vxz = zix*fix(1) + ziy*fiy(1) + ziz*fiz(1)
         vyy = yix*fix(2) + yiy*fiy(2) + yiz*fiz(2)
         vyz = zix*fix(2) + ziy*fiy(2) + ziz*fiz(2)
         vzz = zix*fix(3) + ziy*fiy(3) + ziz*fiz(3)
         vir(1,1) = vir(1,1) + vxx
         vir(2,1) = vir(2,1) + vxy
         vir(3,1) = vir(3,1) + vxz
         vir(1,2) = vir(1,2) + vxy
         vir(2,2) = vir(2,2) + vyy
         vir(3,2) = vir(3,2) + vyz
         vir(1,3) = vir(1,3) + vxz
         vir(2,3) = vir(2,3) + vyz
         vir(3,3) = vir(3,3) + vzz
      end do
c
c     OpenMP directives for the major loop structure
c
c
c     perform deallocation of some local arrays
c
      deallocate (pscale)
      deallocate (dscale)
      deallocate (uscale)
      deallocate (ufld)
      deallocate (dufld)
      
      call timer_exit( timer_epreal )
      end
