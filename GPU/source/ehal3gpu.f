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
#include "tinker_precision.h"
#include "tinker_types.h"

      module ehal3gpu_inl
        integer(1) one1,two1
        real(t_p)  half,one
        parameter( half=0.5, one=1.0
     &           , one1=1, two1=2 )
        contains
#include "convert.f.inc"
#include "image.f.inc"
#include "pair_ehal1.f.inc"
      end module

      subroutine ehal3gpu
      use analyz
      use atoms
      use domdec
      use energi
      use inform
      use iounit
      use interfaces ,only: ehal3c_p
     &               ,ehalshortlong3c_p
      use potent
      use tinheader ,only:ti_p,re_p
      use vdwpot
      use mpi

      implicit none
      integer i
      real(r_p) elrc,aelrc
c
c
c     choose the method for summing over pairwise interactions
c
      if (use_vdwshort) then
        call ehalshortlong3c_p
      else if (use_vdwlong) then
        call ehalshortlong3c_p
      else
        call ehal3c_p
      end if
c
c     apply long range van der Waals correction if desired
c
      if (use_vcorr) then
!$acc data create(elrc) async
         call evcorr (elrc)
!$acc serial async present(ev,elrc)
         ev = ev + elrc
!$acc end serial
c        aelrc = elrc / real(n,r_p)
c        do i = 1, nbloc
c           aev(i) = aev(i) + aelrc
c        end do
         if (rank.eq.0.and.verbose) then
!$acc update host(elrc) async
!$acc wait
            if (elrc.ne.0.0_ti_p.and.app_id.eq.analyze_a) then
               write (iout,10)  elrc
   10          format (/,' Long Range vdw Correction :',9x,f12.4)
            end if
         end if
!$acc end data
      end if
      end
c
c
c
c     #################################################################
c     ##                                                             ##
c     ##  subroutine ehal3cgpu  --  buffered 14-7 analysis via list  ##
c     ##                                                             ##
c     #################################################################
c
c     "ehal3cvec" calculates the buffered 14-7 van der Waals energy
c     and also partitions the energy among the atoms using a
c     pairwise neighbor list
c
c
      subroutine ehal3cgpu
      use action    ,only: nev,nev_
cold  use analyz    ,only: aev
      use atmlst    ,only: vdwglobnl,vdwglob
      use atoms     ,only: x,y,z,n
      use couple    ,only: i12,n12
      use domdec    ,only: loc,rank,nbloc
      use ehal3gpu_inl
      use energi    ,only: ev=>ev_r
      use inform    ,only: deb_Path
      use interfaces,only: ehal3c_correct_scaling
      use mutant    ,only: scexp,scalpha,vlambda,vcouple,mut=>mutInt
      use neigh     ,only: vlst,nvlst
      use tinheader ,only: ti_p,re_p
      use tinMemory ,only: prmem_request
      use sizes     ,only: maxvalue,tinkerdebug
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin,
     &                     epsilon,nvdwbloc,nvdwlocnl,
     &                     nvdwclass,skipvdw12
      use vdwpot    ,only: dhal,ghal
      use vdw_locArray
      use utilgpu   ,only: def_queue,dir_queue,rec_queue
#ifdef _OPENACC
     &                    ,dir_stream
     &                    ,rec_stream,rec_event,stream_wait_async
#endif
      use virial
      implicit none
      integer i,j,k,kk,ksave
      integer kt,kglob,kbis,kvloc,kv,ki
      integer iglob,iivdw
      integer ii,iv,it,ivloc
      integer nnvlst,nnvlst2
      integer nn12,nn13,nn14,ntot
      integer in12,ai12(maxvalue)
      real(t_p)  xi,yi,zi,redi,e,de
      real(t_p)  rdn,rdn1,redk
      real(t_p)  rik2,rinv
      real(t_p)  dedx,dedy,dedz
      real(r_p)  devx,devy,devz,devt
      real(t_p)  invrho,rv7orho
      real(t_p)  dtau,gtau,tau,tau7,rv7
      real(t_p)  rv2,eps2
      real(t_p)  xpos,ypos,zpos
      real(t_p)  dtaper,taper
      real(t_p)  vscale,vscale4
      integer(1) muti,mutik
      logical    do_scale4
      logical    ik12
      character*10 mode

c
      if(deb_Path) write (*,*) 'ehal3cgpu'

#ifdef _OPENACC
      if (dir_queue.ne.rec_queue) then
         call stream_wait_async(rec_stream,dir_stream,rec_event)
      end if
#endif
      call prmem_request(xred,nbloc,queue=def_queue)
      call prmem_request(yred,nbloc,queue=def_queue)
      call prmem_request(zred,nbloc,queue=def_queue)

!$acc data present(xred,yred,zred)
!$acc&     present(loc,ired,kred,x,y,z,vdwglobnl,ivdw,loc,jvdw,
!$acc&  vdwglob,vlst,nvlst,radmin,epsilon,mut,i12,n12)
!$acc&     present(ev,nev,nev_)

      ev  = 0
      nev_= 0.0
c
c     apply any reduction factor to the atomic coordinates
c
!$acc parallel loop async(def_queue)
      do k = 1,nvdwbloc
         iglob   = ivdw (vdwglob (k))
         i       = loc  (iglob)
         iv      = ired (iglob)
         rdn     = kred (iglob)
         rdn1    = 1.0_ti_p - rdn
         xred(i) = rdn * x(iglob) + rdn1 * x(iv)
         yred(i) = rdn * y(iglob) + rdn1 * y(iv)
         zred(i) = rdn * z(iglob) + rdn1 * z(iv)
      enddo
c
c     set the coefficients for the switching function
c
      mode = 'VDW'
      call switch (mode)
      rinv = 1.0/(cut-off)
c
c     find van der Waals energy and derivatives via neighbor list
c
!$acc parallel loop gang vector_length(32)
!$acc&         private(ai12) reduction(+:nev_,ev)
!$acc&         async(def_queue)
      MAINLOOP:
     &do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i     = loc(iglob)

         nnvlst = nvlst(ii)
         if(nnvlst.eq.0) cycle MAINLOOP
         iv    = ired(iglob)
         ivloc = loc(iv)
         it    = jvdw(iglob)
         muti  = mut(iglob)
         xi    = xred(i)
         yi    = yred(i)
         zi    = zred(i)

         if (skipvdw12) then
            in12 = n12(iglob)
!$acc loop vector
            do j = 1,in12
               ai12(j) = i12(j,iglob)
            end do
         end if

!$acc loop vector reduction(+:nev_,ev) 
         do k = 1, nnvlst
            kglob  = vlst(k,ii)
            kbis   = loc (kglob)
            kvloc  = loc (ired(kglob))
            kt     = jvdw (kglob)
            mutik  = muti + mut(kglob)

            if (skipvdw12) then
               ik12 = .false.
!$acc loop seq
               do j = 1, in12
                  if (ai12(j).eq.kglob) ik12=.true.
               end do
               if (ik12) cycle
            end if
c
c     compute the energy contribution for this interaction
c
            xpos   = xi - xred(kbis)
            ypos   = yi - yred(kbis)
            zpos   = zi - zred(kbis)
            call image_inl(xpos,ypos,zpos)
c
c     decide whether to compute the current interaction
c     and check for an interaction distance less than the cutoff
c
            rik2   = xpos**2 + ypos**2 + zpos**2
            if (rik2>off2) cycle

            ! Annihilate
            if (vcouple.eq.1.and.mutik.eq.two1) mutik=one1

            rv2  =  radmin (kt,it)
            eps2 = epsilon (kt,it)

            call ehal1_couple(xpos,ypos,zpos,rik2,rv2,eps2,1.0_ti_p
     &                       ,cut2,rinv,off,ghal,dhal
     &                       ,scexp,vlambda,scalpha,mutik
     &                       ,e,dedx,dedy,dedz)

            ev        =  ev + tp2enr(e)
            nev_      = nev_+ 1
            !aev(i)    = aev(i)    + 0.5_ti_p*e
            !aev(kbis) = aev(kbis) + 0.5_ti_p*e

         end do
      end do MAINLOOP

      call ehal3c_correct_scaling(xred,yred,zred)

!$acc serial async(def_queue)
      nev = nev + int(nev_)
!$acc end serial

!$acc end data

      end subroutine

      subroutine ehalshortlong3cgpu
      use action    ,only: nev,nev_
cold  use analyz    ,only: aev
      use atmlst    ,only: vdwglobnl,vdwglob
      use atoms     ,only: x,y,z,n
      use couple    ,only: i12,n12
      use cutoff    ,only: vdwshortcut,shortheal
      use domdec    ,only: loc,rank,nbloc
      use ehal3gpu_inl
      use energi    ,only: ev=>ev_r
      use inform    ,only: deb_Path
      use interfaces,only: ehalshortlong3c_correct_scaling
      use mutant    ,only: scexp,scalpha,vlambda,vcouple,mut=>mutInt
      use neigh     ,only: shortvlst,nshortvlst,nvlst,vlst
      use tinheader ,only: ti_p,re_p
      use sizes     ,only: maxvalue,tinkerdebug
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use potent    ,only: use_vdwshort,use_vdwlong
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin,
     &                     epsilon,nvdwbloc,nvdwlocnl,
     &                     nvdwclass,skipvdw12
      use vdwpot    ,only: dhal,ghal
      use utilgpu   ,only: def_queue,dir_queue,rec_queue
#ifdef _OPENACC
     &                    ,dir_stream
     &                    ,rec_stream,rec_event,stream_wait_async
#endif
      use virial
      implicit none
      integer i,j,k,kk,ksave
      integer kt,kglob,kbis,kvloc,kv,ki
      integer iglob,iivdw
      integer ii,iv,it,ivloc
      integer nnvlst,nnvlst2
      integer nn12,nn13,nn14,ntot
      integer in12,ai12(maxvalue)
      integer,pointer::lst(:,:),nlst(:)
      real(t_p)  vdwshortcut2
      real(t_p)  xi,yi,zi,redi,e,de
      real(t_p)  rdn,rdn1,redk
      real(t_p)  rik2,rinv
      real(t_p)  dedx,dedy,dedz
      real(r_p)  devx,devy,devz,devt
      real(t_p)  invrho,rv7orho
      real(t_p)  dtau,gtau,tau,tau7,rv7
      real(t_p)  rv2,eps2
      real(t_p)  xpos,ypos,zpos
      real(t_p)  dtaper,taper
      real(t_p)  vscale,vscale4
      logical    do_scale4,ik12
      integer(1) muti,mutik
      character*10 mode

      real(t_p)  xred(nbloc)
      real(t_p)  yred(nbloc)
      real(t_p)  zred(nbloc)
c
      if(deb_Path) write (*,*) 'ehalshortlong3cgpu'

#ifdef _OPENACC
      if (dir_queue.ne.rec_queue) then
         call stream_wait_async(rec_stream,dir_stream,rec_event)
      end if
#endif

!$acc data create(xred,yred,zred)
!$acc&     present(loc,ired,kred,x,y,z,vdwglobnl,ivdw,loc,jvdw,
!$acc&  vdwglob,radmin,epsilon)
!$acc&     present(ev,nev,nev_)
!$acc&     async(def_queue)

      ev  = 0
      nev_= 0.0

c
c     apply any reduction factor to the atomic coordinates
c
!$acc parallel loop default(present)
!$acc&         async(def_queue)
      do k = 1,nvdwbloc
         iglob   = ivdw (vdwglob (k))
         i       = loc  (iglob)
         iv      = ired (iglob)
         rdn     = kred (iglob)
         rdn1    = 1.0_ti_p - rdn
         xred(i) = rdn * x(iglob) + rdn1 * x(iv)
         yred(i) = rdn * y(iglob) + rdn1 * y(iv)
         zred(i) = rdn * z(iglob) + rdn1 * z(iv)
      enddo
c
c     set the coefficients for the switching function
c
      if (use_vdwshort) then
         mode  = 'SHORTVDW'
         call switch (mode)
         vdwshortcut2 = 0
          lst =>  shortvlst
         nlst => nshortvlst
      else if (use_vdwlong) then
         mode  = 'VDW'
         call switch (mode)
         vdwshortcut2 = (vdwshortcut-shortheal)**2
          lst =>  vlst
         nlst => nvlst
      else
         write(*,*) "Unknown mode for ehal3c_shortlongcgpu",mode
         call fatal
      end if
!$acc enter data attach(nlst,lst) async(def_queue)
c
c     find van der Waals energy and derivatives via neighbor list
c
!$acc parallel loop gang vector_length(32)
!$acc&         private(ai12)
!$acc&         present(lst,nlst) async(def_queue)
      MAINLOOP:
     &do ii = 1, nvdwlocnl
         iivdw = vdwglobnl(ii)
         iglob = ivdw(iivdw)
         i     = loc(iglob)

         nnvlst = nlst(ii)
         if(nnvlst.eq.0) cycle MAINLOOP
         iv    = ired(iglob)
         ivloc = loc(iv)
         it    = jvdw(iglob)
         xi    = xred(i)
         yi    = yred(i)
         zi    = zred(i)
         muti  = mut(iglob)

         if (skipvdw12) then
            in12 = n12(iglob)
!$acc loop vector
            do j = 1,in12
               ai12(j) = i12(j,iglob)
            end do
         end if

!$acc loop vector 
         do k = 1, nnvlst
            kglob  = lst(k,ii)
            kbis   = loc (kglob)
            kvloc  = loc (ired(kglob))
            kt     = jvdw (kglob)
            mutik  = muti + mut(kglob)
            !vscale  = 1.0_ti_p

            if (skipvdw12) then
               ik12 = .false.
!$acc loop seq
               do j = 1, in12
                  if (ai12(j).eq.kglob) ik12=.true.
               end do
               if (ik12) cycle
            end if
c
c     compute the energy contribution for this interaction
c
            xpos   = xi - xred(kbis)
            ypos   = yi - yred(kbis)
            zpos   = zi - zred(kbis)
            call image_inl(xpos,ypos,zpos)
c
c     decide whether to compute the current interaction
c     and check for an interaction distance less than the cutoff
c
            rik2   = xpos**2 + ypos**2 + zpos**2
            if (rik2<vdwshortcut2.or.rik2>off2) cycle

            ! Annihilate
            if (vcouple.eq.1.and.mutik.eq.two1) mutik=one1

            rv2  =  radmin (kt,it)
            eps2 = epsilon (kt,it)

            if (use_vdwshort) then
               call ehal1_couple_short(xpos,ypos,zpos,rik2,rv2,eps2
     &                    ,1.0_ti_p,cut2,off
     &                    ,scexp,vlambda,scalpha,mutik
     &                    ,shortheal,ghal,dhal,e,dedx,dedy,dedz)
            else
               call ehal1_couple_long(xpos,ypos,zpos,rik2,rv2,eps2
     &                    ,1.0_ti_p,cut2,cut,off,vdwshortcut
     &                    ,scexp,vlambda,scalpha,mutik
     &                    ,shortheal,ghal,dhal,e,dedx,dedy,dedz)
            end if

            ev   =   ev  + tp2enr(e)
            nev_ =  nev_ + 1

         end do
      end do MAINLOOP
!$acc exit data detach(lst,nlst) async(def_queue)

      call ehalshortlong3c_correct_scaling(xred,yred,zred,mode)

!$acc serial present(nev,nev_) async(def_queue)
      nev = int(nev_)
!$acc end serial

!$acc end data

      end subroutine

#ifdef _CUDA
      subroutine ehal3c_cu
      use action    ,only: nev
      use atmlst    ,only: vdwglobnl,vdwglob
      use atoms     ,only: x,y,z,n
      use domdec    ,only: loc,rank,nbloc,nproc
     &              ,xbegproc,xendproc,ybegproc,yendproc,zbegproc
     &              ,zendproc,glob
      use ehal1cu
      use energi    ,only: ev=>ev_r
      use inform    ,only: deb_Path
      use interfaces,only: ehal3c_correct_scaling
      use mutant    ,only: scexp,scalpha,vlambda,mut=>mutInt
      use neigh     ,only: cellv_glob,cellv_loc,cellv_jvdw
     &              ,vblst,ivblst
      use tinheader ,only: ti_p
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use utilcu    ,only: check_launch_kernel
      use utilgpu   ,only: def_queue,dir_queue,rec_queue,dir_stream
     &              ,start_dir_stream_cover,def_stream
     &              ,warp_size,inf
     &              ,ered_buff=>ered_buf1,nred_buff,reduce_energy_action
     &              ,zero_en_red_buffer,prmem_request
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin_c
     &              ,epsilon_c,nvdwbloc,nvdwlocnl
     &              ,nvdwlocnlb,nvdwclass
     &              ,nvdwlocnlb_pair,nvdwlocnlb2_pair
      use vdwpot    ,only: dhal,ghal,v2scale
      use vdw_locArray
      implicit none
      integer i,k
      integer iglob,iivdw,iv,grid
      integer ierrSync,lst_start
      real(t_p)  xbeg,xend,ybeg,yend,zbeg,zend
      real(t_p)  rdn,rdn1
      real(t_p)  rinv
      character*10 mode

      call prmem_request(xred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(yred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(zred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(xredc   ,nbloc     ,queue=def_queue)
      call prmem_request(yredc   ,nbloc     ,queue=def_queue)
      call prmem_request(zredc   ,nbloc     ,queue=def_queue)
      call prmem_request(loc_ired,nvdwlocnlb,queue=def_queue)
      call prmem_request(loc_kred,nvdwlocnlb,queue=def_queue)

c
      if(deb_Path) write (*,*) 'ehal3c_cu'
      def_queue = dir_queue
      def_stream = dir_stream
      xbeg = xbegproc(rank+1)
      xend = xendproc(rank+1)
      ybeg = ybegproc(rank+1)
      yend = yendproc(rank+1)
      zbeg = zbegproc(rank+1)
      zend = zendproc(rank+1)
      lst_start = 2*nvdwlocnlb_pair+1

#ifdef _OPENACC
      if (dir_queue.ne.rec_queue)
     &   call start_dir_stream_cover
#endif

c
c     apply any reduction factor to the atomic coordinates
c
!$acc parallel loop default(present) async(def_queue)
      do k = 1,nvdwlocnlb
         if (k.le.nvdwlocnl) then
            iglob    = cellv_glob(k)
            iv       = ired (iglob)
            rdn      = kred (iglob)
            rdn1     = 1.0_ti_p - rdn
            cellv_loc(k) = loc(iglob)
            loc_ired(k)  = loc(iv)
            if (iglob.eq.iv) then
               loc_kred(k) = rdn
            else
               loc_kred(k) = 1.0_ti_p
            end if
            xred(k)  = rdn * x(iglob) + rdn1 * x(iv)
            yred(k)  = rdn * y(iglob) + rdn1 * y(iv)
            zred(k)  = rdn * z(iglob) + rdn1 * z(iv)
         else
            ! Exclusion buffer to prevent interaction compute
            cellv_loc(k) = nbloc
            loc_ired(k)  = nbloc
            xred(k) = inf
            yred(k) = inf
            zred(k) = inf
         end if
      end do

!$acc parallel loop default(present) async(def_queue)
      do k = 1,nvdwbloc
         iglob    = ivdw(vdwglob(k))
         i        = loc  (iglob)
         iv       = ired (iglob)
         rdn      = kred (iglob)
         rdn1     = 1.0_ti_p - rdn
         xredc(i)  = rdn * x(iglob) + rdn1 * x(iv)
         yredc(i)  = rdn * y(iglob) + rdn1 * y(iv)
         zredc(i)  = rdn * z(iglob) + rdn1 * z(iv)
      end do

      call zero_en_red_buffer(def_queue)
c
c     set the coefficients for the switching function
c
      !print*, nvdwlocnlb_pair
      mode = 'VDW'
      call switch (mode)
      rinv = 1.0/(cut-off)
c
c     Call Vdw kernel in CUDA using C2 nblist
c
!$acc host_data use_device(xred,yred,zred,cellv_glob,cellv_loc
!$acc&    ,loc_ired,ivblst,vblst,cellv_jvdw,epsilon_c,mut
!$acc&    ,radmin_c,ired,kred,ered_buff,nred_buff
!$acc&    )

      call ehal3_cu2<<<*,VDW_BLOCK_DIM,0,def_stream>>>
     &             (xred,yred,zred,cellv_glob,cellv_loc,loc_ired
     &             ,ivblst,vblst(lst_start),cellv_jvdw
     &             ,epsilon_c,radmin_c,ired,kred
     &             ,ered_buff,nred_buff
     &             ,nvdwlocnlb2_pair,n,nbloc,nvdwlocnl,nvdwlocnlb
     &             ,nvdwclass
     &             ,c0,c1,c2,c3,c4,c5,cut2,rinv,off2,off,ghal,dhal
     &             ,scexp,vlambda,scalpha,mut
     &             ,xbeg,xend,ybeg,yend,zbeg,zend
     &             )
      call check_launch_kernel(" ehal3_cu2 ")

!$acc end host_data

      call reduce_energy_action(ev,nev,ered_buff,def_queue)

      call ehal3c_correct_scaling(xredc,yredc,zredc)

c!$acc end data
      end subroutine

      subroutine ehalshortlong3c_cu
      use action    ,only: nev
      use atmlst    ,only: vdwglobnl,vdwglob
      use atoms     ,only: x,y,z,n
      use cutoff    ,only: vdwshortcut,shortheal
      use domdec    ,only: loc,rank,nbloc,nproc
     &              ,xbegproc,xendproc,ybegproc,yendproc,zbegproc
     &              ,zendproc,glob
      use ehal1cu
      use energi    ,only: ev=>ev_r
      use inform    ,only: deb_Path
      use interfaces,only: ehalshortlong3c_correct_scaling
      use mutant    ,only: scexp,scalpha,vlambda,mut=>mutInt
      use neigh     ,only: cellv_glob,cellv_loc,cellv_jvdw
     &              ,vblst,ivblst,shortvblst,ishortvblst
      use potent    ,only: use_vdwshort,use_vdwlong
      use tinheader ,only: ti_p
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use utilcu    ,only: check_launch_kernel
      use utilgpu   ,only: def_queue,dir_queue,rec_queue,dir_stream
     &              ,rec_stream,rec_event,stream_wait_async
     &              ,warp_size,def_stream,inf
     &              ,ered_buff=>ered_buf1,nred_buff,reduce_energy_action
     &              ,zero_en_red_buffer,prmem_request
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin_c
     &              ,epsilon_c,nvdwbloc,nvdwlocnl
     &              ,nvdwlocnlb,nvdwclass
     &              ,nvdwlocnlb_pair,nvdwlocnlb2_pair
     &              ,nshortvdwlocnlb2_pair
      use vdwpot    ,only: dhal,ghal
      use vdw_locArray
      implicit none
      integer i,k
      integer iglob,iivdw,iv,grid
      integer ierrSync,lst_start
#ifdef TINKER_DEBUG
#endif
      real(t_p)  vdwshortcut2
      real(t_p)  xbeg,xend,ybeg,yend,zbeg,zend
      real(t_p)  rdn,rdn1
      character*10 mode

      call prmem_request(xred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(yred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(zred    ,nvdwlocnlb,queue=def_queue)
      call prmem_request(xredc   ,nbloc     ,queue=def_queue)
      call prmem_request(yredc   ,nbloc     ,queue=def_queue)
      call prmem_request(zredc   ,nbloc     ,queue=def_queue)
      call prmem_request(loc_ired,nvdwlocnlb,queue=def_queue)
      call prmem_request(loc_kred,nvdwlocnlb,queue=def_queue)
c
      if(deb_Path) write (*,*) 'ehalshortlong3c_cu'
      def_queue = dir_queue
      def_stream = dir_stream
      xbeg = xbegproc(rank+1)
      xend = xendproc(rank+1)
      ybeg = ybegproc(rank+1)
      yend = yendproc(rank+1)
      zbeg = zbegproc(rank+1)
      zend = zendproc(rank+1)
      lst_start = 2*nvdwlocnlb_pair+1

#ifdef _OPENACC
      if (dir_queue.ne.rec_queue)
     &   call stream_wait_async(rec_stream,dir_stream,rec_event)
#endif


#ifdef TINKER_DEBUG
#endif

c
c     apply any reduction factor to the atomic coordinates
c
!$acc parallel loop default(present) async(def_queue)
      do k = 1,nvdwlocnlb
         if (k.le.nvdwlocnl) then
            iglob    = cellv_glob(k)
            iv       = ired (iglob)
            rdn      = kred (iglob)
            rdn1     = 1.0_ti_p - rdn
            cellv_loc(k) = loc(iglob)
            loc_ired(k)  = loc(iv)
            if (iglob.eq.iv) then
               loc_kred(k) = rdn
            else
               loc_kred(k) = 1.0_ti_p
            end if
            xred(k)  = rdn * x(iglob) + rdn1 * x(iv)
            yred(k)  = rdn * y(iglob) + rdn1 * y(iv)
            zred(k)  = rdn * z(iglob) + rdn1 * z(iv)
         else
            ! Exclusion buffer to prevent interaction compute
            cellv_loc(k) = nbloc
            loc_ired(k)  = nbloc
            xred(k) = inf
            yred(k) = inf
            zred(k) = inf
         end if
      end do

!$acc parallel loop default(present) async(def_queue)
      do k = 1,nvdwbloc
         iglob    = ivdw(vdwglob(k))
         i        = loc  (iglob)
         iv       = ired (iglob)
         rdn      = kred (iglob)
         rdn1     = 1.0_ti_p - rdn
         xredc(i)  = rdn * x(iglob) + rdn1 * x(iv)
         yredc(i)  = rdn * y(iglob) + rdn1 * y(iv)
         zredc(i)  = rdn * z(iglob) + rdn1 * z(iv)
      end do

      call zero_en_red_buffer(def_queue)
c
c     set the coefficients for the switching function
c
      if (use_vdwshort) then
         mode = 'SHORTVDW'
         call switch (mode)
      else if (use_vdwlong) then
         mode = 'VDW'
         call switch(mode)
      end if

      vdwshortcut2 = (vdwshortcut-shortheal)**2
      grid = nvdwlocnlb_pair/50
c
c     Call Vdw kernel in CUDA using C2 nblist
c
!$acc host_data use_device(xred,yred,zred,cellv_glob,cellv_loc
!$acc&    ,loc_ired,ivblst,vblst,shortvblst,ishortvblst,cellv_jvdw
!$acc&    ,epsilon_c,radmin_c,ired,kred,ered_buff,nred_buff,mut
#ifdef TINKER_DEBUG
#endif
!$acc&    )

      if (use_vdwshort) then
      call ehalshortlong3_cu <<<*,VDW_BLOCK_DIM,0,def_stream>>>
     &           (xred,yred,zred,cellv_glob,cellv_loc,loc_ired
     &           ,ishortvblst,shortvblst(lst_start),cellv_jvdw
     &           ,epsilon_c,radmin_c
     &           ,ired,kred,ered_buff,nred_buff
     &           ,nshortvdwlocnlb2_pair,n,nbloc,nvdwlocnl,nvdwlocnlb
     &           ,nvdwclass
     &           ,c0,c1,c2,c3,c4,c5,cut2,cut,off2,0.0_ti_p,off
     &           ,scexp,vlambda,scalpha,mut
     &           ,vdwshortcut,shortheal,ghal,dhal,use_vdwshort
     &           ,xbeg,xend,ybeg,yend,zbeg,zend
#ifdef TINKER_DEBUG
#endif
     &           )

      else if (use_vdwlong) then
      call ehalshortlong3_cu <<<*,VDW_BLOCK_DIM,0,def_stream>>>
     &           (xred,yred,zred,cellv_glob,cellv_loc,loc_ired
     &           ,ivblst,vblst(lst_start),cellv_jvdw,epsilon_c,radmin_c
     &           ,ired,kred,ered_buff,nred_buff
     &           ,nvdwlocnlb2_pair,n,nbloc,nvdwlocnl,nvdwlocnlb
     &           ,nvdwclass
     &           ,c0,c1,c2,c3,c4,c5,cut2,cut,off2,vdwshortcut2,off
     &           ,scexp,vlambda,scalpha,mut
     &           ,vdwshortcut,shortheal,ghal,dhal,use_vdwshort
     &           ,xbeg,xend,ybeg,yend,zbeg,zend
#ifdef TINKER_DEBUG
#endif
     &           )
      end if
      call check_launch_kernel(" ehalshortlong3_cu2 ")

!$acc end host_data

      call reduce_energy_action(ev,nev,ered_buff,def_queue)

#ifdef TINKER_DEBUG
 34   format(2I10,3F12.4)
 36   format(A30,2I10)
 35   format(A30,I16,3x,F16.6,I16)
!$acc wait
!$acc exit data copyout(inter)
!$acc update host(dev,ev)
      write(*,36)'nvdw pair block ',nvdwlocnlb_pair,nvdwlocnlb2_pair
      write(*,35)'nev & ev & rank ',sum(inter),enr2en(ev),rank
#endif

      call ehalshortlong3c_correct_scaling(xredc,yredc,zredc,mode)

      end subroutine
#endif


      subroutine ehal3c_correct_scaling(xred,yred,zred)

      use action    ,only: nev,nev_
      use atmlst    ,only: vdwglobnl
      use domdec    ,only: loc,rank
      use ehal3gpu_inl
      use energi    ,only: ev=>ev_r
      use inform    ,only: deb_Path
      use mutant    ,only: scexp,scalpha,vlambda,vcouple,mut=>mutInt
      use tinheader ,only: ti_p
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin,radmin4,
     &                     epsilon,epsilon4
      use vdwpot    ,only: vcorrect_ik,vcorrect_scale,n_vscale,dhal,ghal
      use utilgpu   ,only: def_queue
      implicit none
      integer i,j,k,kk,ksave
      integer kt,kglob,kbis,kvloc,kv,ki
      integer iglob,iivdw
      integer ii,iv,it,ivloc
      integer nnvlst,nnvlst2
      integer nn12,nn13,nn14,ntot
      integer interac
      real(t_p)  xi,yi,zi,redi,e,de
      real(t_p)  rdn,rdn1,redk
      real(t_p)  rik2,rinv
      real(t_p)  dedx,dedy,dedz
      real(r_p)  devx,devy,devz,devt
      real(t_p)  invrho,rv7orho
      real(t_p)  dtau,gtau,tau,tau7,rv7
      real(t_p)  rv2,eps2
      real(t_p)  xpos,ypos,zpos
      real(t_p)  dtaper,taper
      real(t_p)  vscale,vscale4
      logical    do_scale4
      integer(1) muti,mutik
      character*10 mode

      real(t_p),intent(in):: xred(:)
      real(t_p),intent(in):: yred(:)
      real(t_p),intent(in):: zred(:)

      ! Scaling factor correction loop
      if (deb_Path)
     &   write(*,'(2x,a)') "ehal0c_correct_scaling"

      rinv = 1.0/(cut-off)

!$acc parallel loop async(def_queue)
!$acc&     gang vector
!$acc&     present(xred,yred,zred)
!$acc&     present(loc,ired,kred,ivdw,loc,jvdw,radmin,
!$acc&  radmin4,epsilon,epsilon4,vcorrect_ik,vcorrect_scale)
!$acc&     present(ev,nev)
      do ii = 1,n_vscale
         iglob  = vcorrect_ik(ii,1)
         kglob  = vcorrect_ik(ii,2)
         vscale = vcorrect_scale(ii)
         i      = loc(iglob)
         kbis   = loc(kglob)

         ivloc  = loc (ired(iglob))
         kvloc  = loc (ired(kglob))
         it     = jvdw(iglob)
         kt     = jvdw(kglob)

         muti   = mut(iglob)
         mutik  = muti + mut(kglob)

         do_scale4 = .false.
         vscale4   = 0

         if (vscale.lt.0) then 
            vscale4 = -vscale
            vscale = 1
         end if
c
c     compute the energy contribution for this interaction
c
         xpos   = xred(i) - xred(kbis)
         ypos   = yred(i) - yred(kbis)
         zpos   = zred(i) - zred(kbis)
         call image_inl(xpos,ypos,zpos)
c
c     decide whether to compute the current interaction
c     and check for an interaction distance less than the cutoff
c
         rik2   = xpos**2 + ypos**2 + zpos**2
         if (rik2>off2) cycle

         ! Annihilate
         if (vcouple.eq.1.and.mutik.eq.two1) mutik=one1

         ! Replace 1-4 interactions
 20      continue
         if (do_scale4) then
            rv2  = radmin4 (kt,it)
            eps2 = epsilon4(kt,it)
         else
            rv2  =  radmin (kt,it)
            eps2 = epsilon (kt,it)
         end if

         call ehal1_couple(xpos,ypos,zpos,rik2,rv2,eps2,vscale
     &                    ,cut2,rinv,off,ghal,dhal
     &                    ,scexp,vlambda,scalpha,mutik
     &                    ,e,dedx,dedy,dedz)

         if (.not.do_scale4) then
         e    = -e
         if (vscale.eq.1) nev=nev-1
         end if

         ev           =   ev + tp2enr(e)

         ! deal with 1-4 Interactions
         if (vscale4.gt.0) then
            vscale    =  vscale4
            do_scale4 = .true.
            vscale4   = 0
            goto 20
         end if
      end do
      end

      subroutine ehalshortlong3c_correct_scaling(xred,yred,zred,mode)
      use action    ,only: nev
      use atmlst    ,only: vdwglobnl
      use cutoff    ,only: shortheal,vdwshortcut
      use domdec    ,only: loc,rank
      use ehal3gpu_inl
      use energi    ,only: ev=>ev_r
      use inform    ,only: deb_Path
      use mutant    ,only: scexp,scalpha,vlambda,vcouple,mut=>mutInt
      use tinheader ,only: ti_p
      use shunt     ,only: c0,c1,c2,c3,c4,c5,off2,off,cut2,cut
      use vdw       ,only: ired,kred,jvdw,ivdw,radmin,radmin4,
     &                     epsilon,epsilon4
      use vdwpot    ,only: vcorrect_ik,vcorrect_scale,n_vscale,dhal,ghal
      use utilgpu   ,only: def_queue
      implicit none
      integer i,j,k,kk,ksave
      integer kt,kglob,kbis,kvloc,kv,ki
      integer iglob,iivdw
      integer ii,iv,it,ivloc
      integer nnvlst,nnvlst2
      integer nn12,nn13,nn14,ntot
      integer interac
      real(t_p)  xi,yi,zi,redi,e,de
      real(t_p)  rdn,rdn1,redk
      real(t_p)  invrik,rik,rik2,rik3,rik4,rik5,rik6,rik7
      real(t_p)  dedx,dedy,dedz
      real(r_p)  devx,devy,devz,devt
      real(t_p)  invrho,rv7orho
      real(t_p)  dtau,gtau,tau,tau7,rv7
      real(t_p)  rv2,eps2,vdwshortcut2
      real(t_p)  xpos,ypos,zpos
      real(t_p)  dtaper,taper
      real(t_p)  vscale,vscale4
      logical    do_scale4,short
      integer(1) muti,mutik

      real(t_p),intent(in):: xred(:)
      real(t_p),intent(in):: yred(:)
      real(t_p),intent(in):: zred(:)
      character*10,intent(in):: mode

      ! Scaling factor correction loop

      if (deb_Path)
     &   write(*,'(2x,a)') "ehal0c_correct_scaling_shortlong"

      if      (mode(1:8).eq.'SHORTVDW') then
         vdwshortcut2 = 0.0_ti_p
         short = .true.
      else if (mode(1:3).eq.'VDW') then
         vdwshortcut2 = (vdwshortcut-shortheal)**2
         short = .false.
      else
         print*,'mode ',mode, ' is unrecognized for',
     &          'ehalshortlong3c_correct_scaling'
         call fatal
      end if

!$acc parallel loop async(def_queue)
!$acc&     gang vector
!$acc&     present(xred,yred,zred)
!$acc&     present(loc,ired,kred,ivdw,loc,jvdw,radmin,mut,
!$acc&  radmin4,epsilon,epsilon4,vcorrect_ik,vcorrect_scale)
!$acc&     present(ev)
      do ii = 1,n_vscale
         iglob  = vcorrect_ik(ii,1)
         kglob  = vcorrect_ik(ii,2)
         vscale = vcorrect_scale(ii)
         i      = loc(iglob)
         kbis   = loc(kglob)

         ivloc  = loc (ired(iglob))
         kvloc  = loc (ired(kglob))
         it     = jvdw(iglob)
         kt     = jvdw(kglob)

         mutik  = mut(iglob) + mut(kglob)

         do_scale4 = .false.
         vscale4   = 0

         if (vscale.lt.0) then 
            vscale4 = -vscale
            vscale = 1
         end if
c
c     compute the energy contribution for this interaction
c
         xpos   = xred(i) - xred(kbis)
         ypos   = yred(i) - yred(kbis)
         zpos   = zred(i) - zred(kbis)
         call image_inl(xpos,ypos,zpos)
c
c     decide whether to compute the current interaction
c     and check for an interaction distance less than the cutoff
c
         rik2   = xpos**2 + ypos**2 + zpos**2
         if (rik2<vdwshortcut2.or.rik2>off2) cycle

         ! Annihilate
         if (vcouple.eq.1.and.mutik.eq.two1) mutik=one1
 
         !replace 1-4 interactions
 20      continue
         if (do_scale4) then
            rv2  = radmin4 (kt,it)
            eps2 = epsilon4(kt,it)
         else
            rv2  =  radmin (kt,it)
            eps2 = epsilon (kt,it)
         end if

         if (short) then
            call ehal1_couple_short(xpos,ypos,zpos,rik2,rv2,eps2,vscale
     &                       ,cut2,off
     &                       ,scexp,vlambda,scalpha,mutik
     &                       ,shortheal,ghal,dhal,e,dedx,dedy,dedz)
         else
            call ehal1_couple_long(xpos,ypos,zpos,rik2,rv2,eps2,vscale
     &                       ,cut2,cut,off,vdwshortcut
     &                       ,scexp,vlambda,scalpha,mutik
     &                       ,shortheal,ghal,dhal,e,dedx,dedy,dedz)
         end if

         if (.not.do_scale4) then
         e    = -e
         end if

         ev           =   ev + tp2enr(e)

         ! deal with 1-4 Interactions
         if (vscale4.gt.0) then
            vscale    =  vscale4
            do_scale4 = .true.
            vscale4   = 0
            goto 20
         end if
      end do
      end
