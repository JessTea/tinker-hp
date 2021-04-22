c
c     Sorbonne University
c     Washington University in Saint Louis
c     University of Texas at Austin
c
c     ####################################################################
c     ##                                                                ##
c     ##  module atoms  --  number, position and type of current atoms  ##
c     ##                                                                ##
c     ####################################################################
c
c
c     x       current x-coordinate for each atom in the system
c     y       current y-coordinate for each atom in the system
c     z       current z-coordinate for each atom in the system
c     xold    last x-coordinate for each atom in the system
c     yold    last y-coordinate for each atom in the system
c     zold    last z-coordinate for each atom in the system
c     xold_nl save x-coordinate when last rebuild neighbor list
c     yold_nl save x-coordinate when last rebuild neighbor list
c     zold_nl save x-coordinate when last rebuild neighbor list
c     n       total number of atoms in the current system
c     n       total number of atoms per process element in the current system
c             (nvshmem feature)
c     nloop   First multiple of 16 after n
c     type    atom type number for each atom in the system
c     wintype window object corresponding to type
c
c
#include "tinker_precision.h"
      module atoms
      implicit none
      integer n,nloop,n_pe
      integer :: wintype
      integer  , pointer :: type(:)
      real(t_p),allocatable ,target :: x(:),y(:),z(:)
      real(t_p),allocatable ,target :: xold(:),yold(:),zold(:)
      real(t_p),allocatable :: xold_nl(:),yold_nl(:),zold_nl(:)
!$acc declare create(n)
      end

      module atomsMirror
      implicit none
      integer           :: n
      real(r_p),pointer :: x(:),y(:),z(:)
      real(t_p),pointer :: xold(:),yold(:),zold(:)

      interface
        module subroutine atomsmirror_init
        end subroutine

        module subroutine reCast_position
        end subroutine

        module subroutine download_position(queue)
        integer,optional::queue
        end subroutine

        module subroutine download_mirror_position(queue)
        integer,optional::queue
        end subroutine
      end interface

      contains

      subroutine save_atoms_pos
      implicit none
      integer i
!$acc parallel loop async default(present)
      do i = 1,n
         xold(i) = x(i)
         yold(i) = y(i)
         zold(i) = z(i)
      end do
      end subroutine

      end module
