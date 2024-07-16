c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     #####################################################
c     ##                                                 ##
c     ##  module cavity  --  variables for the cavity MD ##
c     ##                                                 ##
c     #####################################################
c
c
c
c
      module cavity
      implicit none
      real*8 :: cav_x=0.0d0, cav_y=0.0d0
      real*8 :: cav_freq= 660.7  !ps-1  3550cm-1
      real*8 :: cav_mass=1.0d0, cav_alpha
      logical :: use_cavity=.FALSE., include_multipoles = .FALSE.   
      logical :: include_multipoles_induced = .FALSE.    
      real*8 :: cav_E, cav_Fx=0.0d0,cav_Fy=0.0d0
      real*8 :: cav_vx=0.0d0, cav_vy=0.0d0 
      integer :: Ncell=1
      save 
      end
