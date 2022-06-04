c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ####################################################################
c     ##                                                                ##
c     ##  module mpole  --  multipole components for current structure  ##
c     ##                                                                ##
c     ####################################################################
c
c
c     maxpole   max components (monopole=1,dipole=4,quadrupole=13)
c
c     pole      multipole values for each site in the local frame
c     winpole    window object corresponding to pole
c     pole_orig  original multipole values for each site in the local frame (lambdadyn)
c     winpole_orig    window object corresponding to pole_orig
c     rpole     multipoles rotated to the global coordinate system
c     mono0     original atomic monopole values for charge flux
c     winmono0    window object corresponding to mono0
c
c     npole     total number of multipole sites in the system
c     npoleloc  local number of multipole sites in the system
c     npolebloc  local+neighbor number of multipole sites in the system
c     npolelocnl  localnl number of multipole sites in the system
c     npolerecloc  local number of reciprocal multipole sites in the system
c
c     poleloc   global-local correspondance for multipoles
c     polelocnl global-localnl correspondace for multipoles
c     polerecloc   global-local correspondance for reciprocal multipoles
c     nbpole    number of multipoles before each atom
c
c     ipole     number of the atom for each multipole site
c     winipole    window object corresponding to ipole
c     polsiz    number of multipole components at each atom
c     winpolsiz    window object corresponding to polsiz
c     pollist   multipole site for each atom (0=no multipole)
c     winpollist    window object corresponding to pollist
c     zaxis     number of the z-axis defining atom for each site
c     xaxis     number of the x-axis defining atom for each site
c     yaxis     number of the y-axis defining atom for each site
c     polaxe    local axis type for each multipole site
c     winpolaxe    window object corresponding to polaxe
c
c     alphapen  alpha parameters for sibfa like charge penetration
c     winalphapen    window object corresponding to alphapen
c     betapen   beta parameters for sibfa like charge penetration
c     winbetapen    window object corresponding to betapen
c     gammapen  gamma parameters for sibfa like charge penetration
c     wingammapen    window object corresponding to gammapen
c
c
      module mpole
      implicit none
      integer maxpole
      parameter (maxpole=13)
      integer npole,npoleloc,npolebloc,npolerecloc,npolelocnl
      integer, pointer :: ipole(:), polsiz(:), pollist(:)
      integer :: winipole,winpolsiz,winpollist
      integer, allocatable :: poleloc(:),polelocnl(:),polerecloc(:)
      integer, pointer :: nbpole(:)
      integer, allocatable :: zaxis(:),xaxis(:),yaxis(:)
      integer :: winnbpole
      real*8, allocatable :: rpole(:,:)
      real*8, pointer :: mono0(:)
      integer :: winmono0
      real*8, pointer :: pole(:,:),pole_orig(:,:)
      real*8, pointer :: alphapen(:),betapen(:),gammapen(:)
      integer :: winpole,winpole_orig,winalphapen,winbetapen,wingammapen
      real*8 vmxx,vmyy,vmzz
      real*8 vmxy,vmxz,vmyz
      character*8, pointer ::  polaxe(:)
      integer :: winpolaxe
      save
      end
