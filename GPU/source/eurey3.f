c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     #############################################################
c     ##                                                         ##
c     ##  subroutine eurey3  --  Urey-Bradley energy & analysis  ##
c     ##                                                         ##
c     #############################################################
c
c
c     "eurey3" calculates the Urey-Bradley energy; also
c     partitions the energy among the atoms
c
c
#include "tinker_macro.h"
      subroutine eurey3
      use action
      use analyz
      use atmlst
      use atmtyp
      use atoms
      use bound
      use domdec
      use energi
      use group
      use inform
      use iounit
      use tinheader ,only:ti_p,re_p
      use urey
      use urypot
      use usage
      implicit none
      integer i,ia,ib,ic,iurey
      integer ibloc,icloc
      real(t_p) e,ideal,force
      real(t_p) dt,dt2
      real(t_p) xac,yac,zac,rac
      real(t_p) fgrp
      integer iga,igc
      logical proceed
      logical header,huge
c
c
c     zero out the Urey-Bradley energy and partitioning terms
c
      neub = 0
      eub = 0.0_ti_p
      aub = 0.0_ti_p
      header = .true.
c
c     calculate the Urey-Bradley 1-3 energy term
c
      do iurey = 1, nureyloc
         i = ureyglob(iurey)
         ia = iury(1,i)
         ib = iury(2,i)
         ibloc = loc(ib)
         ic = iury(3,i)
         icloc = loc(ic)
         ideal = ul(i)
         force = uk(i)
c
c     decide whether to compute the current interaction
c
         proceed = .true.
         if (proceed)  proceed = (use(ia) .or. use(ic))
c
c     compute the value of the 1-3 distance deviation
c
         if (proceed) then
            xac = x(ia) - x(ic)
            yac = y(ia) - y(ic)
            zac = z(ia) - z(ic)
            if (use_polymer)  call image (xac,yac,zac)
            rac = sqrt(xac*xac + yac*yac + zac*zac)
            dt = rac - ideal
            dt2 = dt * dt
c
c     calculate the Urey-Bradley energy for this interaction
c
            e = ureyunit * force * dt2 * (1.0_ti_p+cury*dt+qury*dt2)
            
            if(use_group) then
              iga=grplist(ia)
              igc=grplist(ic)
              fgrp = wgrp(iga+1,igc+1)
              e = e*fgrp
            endif
c
c     increment the total Urey-Bradley energy
c
            neub = neub + 1
            eub = eub + e
            aub(ibloc) = aub(ibloc) + 0.5_ti_p*e
            aub(icloc) = aub(icloc) + 0.5_ti_p*e
c
c     print a message if the energy of this interaction is large
c
            huge = (e .gt. 5.0_ti_p)
            if (debug .or. (verbose.and.huge)) then
               if (header) then
                  header = .false.
                  write (iout,10)
   10             format (/,' Individual Urey-Bradley Interactions :',
     &                    //,' Type',18x,'Atom Names',18x,'Ideal',
     &                       4x,'Actual',6x,'Energy',/)
               end if
               write (iout,20)  ia,name(ia),ib,name(ib),
     &                          ic,name(ic),ideal,rac,e
   20          format (' UreyBrad',2x,i7,'-',a3,i7,'-',a3,
     &                    i7,'-',a3,2x,2f10.4,f12.4)
            end if
         end if
      end do
      return
      end
