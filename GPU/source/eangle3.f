c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ###############################################################
c     ##                                                           ##
c     ##  subroutine eangle3  --  angle bending energy & analysis  ##
c     ##                                                           ##
c     ###############################################################
c
c
c     "eangle3" calculates the angle bending potential energy, also
c     partitions the energy among the atoms; projected in-plane
c     angles at trigonal centers, spceial linear or Fourier angle
c     bending terms are optionally used
c
c
#include "tinker_macro.h"
      subroutine eangle3
      use action
      use analyz
      use angle
      use angpot
      use atmlst
      use atmtyp
      use atoms
      use bound
      use domdec
      use energi
      use group
      use inform
      use iounit
      use math
      use tinheader
      use usage
      implicit none
      integer i,ia,ib,ic,id,iangle
      integer ibloc
      real(t_p) e,ideal,force
      real(t_p) fold,factor
      real(t_p) dot,cosine
      real(t_p) angle1
      real(t_p) dt,dt2,dt3,dt4
      real(t_p) xia,yia,zia
      real(t_p) xib,yib,zib
      real(t_p) xic,yic,zic
      real(t_p) xid,yid,zid
      real(t_p) xab,yab,zab
      real(t_p) xcb,ycb,zcb
      real(t_p) xad,yad,zad
      real(t_p) xbd,ybd,zbd
      real(t_p) xcd,ycd,zcd
      real(t_p) xip,yip,zip
      real(t_p) xap,yap,zap
      real(t_p) xcp,ycp,zcp
      real(t_p) rab2,rcb2
      real(t_p) rap2,rcp2
      real(t_p) xt,yt,zt
      real(t_p) rt2,delta
      real(t_p) fgrp
      logical proceed
      logical header,huge
      character*9 label
c
c
c     zero out the angle bending energy and partitioning terms
c
      nea = 0
      ea = 0.0_ti_p
      aea = 0.0_ti_p
      header = .true.
c
c     calculate the bond angle bending energy term
c
      do iangle = 1, nangleloc
         i =  angleglob(iangle)
         ia = iang(1,i)
         ib = iang(2,i)
         ibloc = loc(ib)
         ic = iang(3,i)
         id = iang(4,i)
         ideal = anat(i)
         force = ak(i)
c
c     decide whether to compute the current interaction
c
         if (angtyp(i) .eq. 'IN-PLANE') then
            if (use_group)  call groups (fgrp,ia,ib,ic,id,0,0)
            proceed = (use(ia) .or. use(ib) .or.
     &                                 use(ic) .or. use(id))
         else
            if (use_group)  call groups (fgrp,ia,ib,ic,0,0,0)
            proceed = (use(ia) .or. use(ib) .or. use(ic))
         end if
c
c     get the coordinates of the atoms in the angle
c
         if (proceed) then
            xia = x(ia)
            yia = y(ia)
            zia = z(ia)
            xib = x(ib)
            yib = y(ib)
            zib = z(ib)
            xic = x(ic)
            yic = y(ic)
            zic = z(ic)
c
c     compute the bond angle bending energy
c
            if (angtyp(i) .ne. 'IN-PLANE') then
               xab = xia - xib
               yab = yia - yib
               zab = zia - zib
               xcb = xic - xib
               ycb = yic - yib
               zcb = zic - zib
               if (use_polymer) then
                  call image (xab,yab,zab)
                  call image (xcb,ycb,zcb)
               end if
               rab2 = xab*xab + yab*yab + zab*zab
               rcb2 = xcb*xcb + ycb*ycb + zcb*zcb
               if (rab2.ne.0.0_ti_p .and. rcb2.ne.0.0_ti_p) then
                  dot = xab*xcb + yab*ycb + zab*zcb
                  cosine = dot / sqrt(rab2*rcb2)
                  cosine = min(1.0_ti_p,max(-1.0_ti_p,cosine))
                  angle1 = radian * acos(cosine)
                  if (angtyp(i) .eq. 'HARMONIC') then
                     dt = angle1 - ideal
                     dt2 = dt * dt
                     dt3 = dt2 * dt
                     dt4 = dt2 * dt2
                     e = angunit * force * dt2
     &                  * (1.0_ti_p+cang*dt+qang*dt2+pang*dt3+sang*dt4)
                  else if (angtyp(i) .eq. 'LINEAR') then
                     factor = 2.0_ti_p * angunit * radian**2
                     e = factor * force * (1.0_ti_p+cosine)
                  else if (angtyp(i) .eq. 'FOURIER') then
                     fold = afld(i)
                     factor = 2.0_ti_p * angunit * (radian/fold)**2
                     cosine = cos((fold*angle1-ideal)/radian)
                     e = factor * force * (1.0_ti_p+cosine)
                  end if
c
c     scale the interaction based on its group membership
c
                  if (use_group)  e = e * fgrp
c
c     increment the total bond angle bending energy
c
                  nea = nea + 1
                  ea = ea + e
                  aea(ibloc) = aea(ibloc) + e
c
c     print a message if the energy of this interaction is large
c
                  huge = (e .gt. 5.0_ti_p)
                  if (debug .or. (verbose.and.huge)) then
                     if (header) then
                        header = .false.
                        write (iout,10)
   10                   format (/,' Individual Angle Bending',
     &                             ' Interactions :',
     &                          //,' Type',18x,'Atom Names',18x,
     &                             'Ideal',4x,'Actual',6x,'Energy',/)
                     end if
                     label = 'Angle    '
                     if (angtyp(i) .eq. 'LINEAR') then
                        label = 'Angle-Lin'
                     else if (angtyp(i) .eq. 'FOURIER') then
                        label = 'Angle-Cos'
                        ideal = (ideal+180.0_ti_p) / fold
                        if (angle1-ideal .gt. 180.0_ti_p/fold)
     &                     ideal = ideal + 360.0_ti_p/fold
                     end if
                     write (iout,20)  label,ia,name(ia),ib,name(ib),
     &                                ic,name(ic),ideal,angle1,e
   20                format (1x,a9,1x,i7,'-',a3,i7,'-',a3,i7,
     &                          '-',a3,2x,2f10.4,f12.4)
                  end if
               end if
c
c     compute the projected in-plane angle bend energy
c
            else
               xid = x(id)
               yid = y(id)
               zid = z(id)
               xad = xia - xid
               yad = yia - yid
               zad = zia - zid
               xbd = xib - xid
               ybd = yib - yid
               zbd = zib - zid
               xcd = xic - xid
               ycd = yic - yid
               zcd = zic - zid
               if (use_polymer) then
                  call image (xad,yad,zad)
                  call image (xbd,ybd,zbd)
                  call image (xcd,ycd,zcd)
               end if
               xt = yad*zcd - zad*ycd
               yt = zad*xcd - xad*zcd
               zt = xad*ycd - yad*xcd
               rt2 = xt*xt + yt*yt + zt*zt
               delta = -(xt*xbd + yt*ybd + zt*zbd) / rt2
               xip = xib + xt*delta
               yip = yib + yt*delta
               zip = zib + zt*delta
               xap = xia - xip
               yap = yia - yip
               zap = zia - zip
               xcp = xic - xip
               ycp = yic - yip
               zcp = zic - zip
               if (use_polymer) then
                  call image (xap,yap,zap)
                  call image (xcp,ycp,zcp)
               end if
               rap2 = xap*xap + yap*yap + zap*zap
               rcp2 = xcp*xcp + ycp*ycp + zcp*zcp
               if (rap2.ne.0.0_ti_p .and. rcp2.ne.0.0_ti_p) then
                  dot = xap*xcp + yap*ycp + zap*zcp
                  cosine = dot / sqrt(rap2*rcp2)
                  cosine = min(1.0_ti_p,max(-1.0_ti_p,cosine))
                  angle1 = radian * acos(cosine)
                  dt = angle1 - ideal
                  dt2 = dt * dt
                  dt3 = dt2 * dt
                  dt4 = dt2 * dt2
                  e = angunit * force * dt2
     &                   * (1.0_ti_p+cang*dt+qang*dt2+pang*dt3+sang*dt4)
c
c     scale the interaction based on its group membership
c
                  if (use_group)  e = e * fgrp
c
c     increment the total bond angle bending energy
c
                  nea = nea + 1
                  ea = ea + e
                  aea(ibloc) = aea(ibloc) + e
c
c     print a message if the energy of this interaction is large
c
                  huge = (e .gt. 5.0_ti_p)
                  if (debug .or. (verbose.and.huge)) then
                     if (header) then
                        header = .false.
                        write (iout,30)
   30                   format (/,' Individual Angle Bending',
     &                             ' Interactions :',
     &                          //,' Type',18x,'Atom Names',18x,
     &                             'Ideal',4x,'Actual',6x,'Energy',/)
                     end if
                     write (iout,40)  ia,name(ia),ib,name(ib),ic,
     &                                name(ic),ideal,angle1,e
   40                format (' Angle-IP',2x,i7,'-',a3,i7,'-',a3,i7,
     &                          '-',a3,2x,2f10.4,f12.4)
                  end if
               end if
            end if
         end if
      end do
      return
      end
