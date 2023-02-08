c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ###################################################################
c     ##                                                               ##
c     ##  module urey  --  Urey-Bradley interactions in the structure  ##
c     ##                                                               ##
c     ###################################################################
c
c
c     uk      Urey-Bradley force constants (kcal/mole/Ang**2)
c     winuk    window object corresponding to uk
c     ul      ideal 1-3 distance values in Angstroms
c     winul    window object corresponding to ul
c     nurey   total number of Urey-Bradley terms in the system
c     nureyloc   local number of Urey-Bradley terms in the system
c     iury    numbers of the atoms in each Urey-Bradley interaction
c     winiury    window object corresponding to iury
c     nburey    numbers of Urey-Bradley interactions before each atom
c     winnburey    window object corresponding to nburey
c
c
#include "tinker_macro.h"
      module urey
      implicit none
      integer nurey,nureyloc
      integer, pointer :: iury(:,:),nburey(:)
      real(t_p), pointer ::  uk(:),ul(:)
      integer :: winiury,winnburey,winuk,winul
      end
