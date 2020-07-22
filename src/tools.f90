!================================================================================
subroutine error(line)
!
  implicit none
  character :: line*(*)
  write(*,*) "######## ",line
  write(*,*) "######## EXITING"
  stop
!
end subroutine error
!================================================================================
subroutine update_prof_force
!
  use common_var
  !
  implicit none
  integer :: i
  !
  do i=1,ngrid-1
    prof_force(i)=(prof_F(i)-prof_F(i+1))/dxgrid
  enddo
  prof_force(ngrid)=prof_force(ngrid-1)
!
end subroutine update_prof_force
!================================================================================
subroutine print_profiles
!
  use common_var
  !
  implicit none
  integer :: i
  double precision :: x
  !
  write(*,*) ""
  write(*,*) "writing F,gamma,mass in PROFILES"
  write(*,*) ""
  open(77,file="PROFILES",status="unknown")
  write(77,'(A,E13.4)') "# x F F/kT gamma mass; taug=",taug
  do i=1,ngrid
    x=xmin+dble(i-1)*dxgrid
    write(77,'(5E15.6)') x,prof_F(i)-minval(prof_F(:)),(prof_F(i)-minval(prof_F(:)))/kT,&
     prof_g(i),prof_m(i)
  enddo
  close(77)
!
end subroutine print_profiles
!================================================================================
subroutine compute_error(error,type_err)
!
  use common_var
  !
  implicit none
  integer :: ix,iv,it,i,ig,nave,type_err, prop_order
  double precision :: error,eps,newnorm
  double precision :: dq,ddq,diff(ngrid),delta
  double precision :: a(ngrid),da(ngrid),dda(ngrid)       ! drift       and derivatives
  double precision :: D(ngrid),dD(ngrid),ddD(ngrid)       ! diff.coeff. and derivatives
  !double precision :: b(ngrid),db(ngrid),ddb(ngrid)       ! drift       and derivatives
  double precision :: b,db,ddb                            ! drift       and derivatives
  double precision :: phi(ngrid),dphi(ngrid),ddphi(ngrid) ! force/m     and derivatives
  double precision :: gam(ngrid),dgam(ngrid),ddgam(ngrid) ! gamma       and derivatives
  double precision :: q,v,v1,v2,q3,q2,q1,q0,f1,g1,sigma2,tau 
  double precision :: g,dg,dt2,dt3,tmp
  double precision :: Mq,Mqq,Mv,Mvv,Mqv,detM
  double precision, parameter :: pi=3.14159265359d0, pi2=pi*pi
  !
  if (type_err.eq.1) then
    !
    ! Kullback-Leibler divergence: err=sum(-Pref*log(Pmod/Pref))
    ! log likelihood: L = sum(Pref*log(Pmod))
    ! I use the latter, simpler, and shift a little bit to include empty regions ("smoothing"?)
    eps=(0.001D0)/dble(nx*nx*(nt+1))  ! altering total norm by 0.001 (arbitrary, but small)
    newnorm=1.D0+0.001D0
    ! TODO improve using Gaussian kernels...
    error = -sum( Pref(:,:,:)*log((Pmod(:,:,:)+eps)/newnorm) )
  elseif (type_err.eq.2) then
    !
    ! root mean square deviation
    if (use_velocity.eq.1) then
      error = dsqrt( sum((Pref(:,:,:)-Pmod(:,:,:))**2)/dble(nx*nx*(nt+1)) )
    else
      error = dsqrt( sum((Pref(:,1,:)-Pmod(:,1,:))**2)/dble(nx*(nt+1)) )
    endif
    !
  elseif (type_err.eq.3) then
    !
    if (type_Langevin.eq.0) then
      !
      ! log likelihood from short-time overdamped propagator
      prop_order = 2   ! order of the propagator: TODO choose in the input
      !
      if (prop_order.eq.1) then
        D(:)=kT/(prof_m(:)*prof_g(:))
        do ig=1,ngrid-1
          dD(ig)=( D(ig+1)-D(ig) )/dxgrid
        enddo
        dD(ngrid)=dD(ngrid-1)
        !diff(:)=4.d0*D(:)*dt
        a(:)=( D(:)*prof_force(:)/kT + dD(:) )
        error=0.d0
        nave=0
        do i=2,nttot
          if (colvar(i,1)-colvar(i-1,1)>0.d0) then ! (avoid time discontinuity)
            dq    = colvar(i,2)-colvar(i-1,2)
            ig = int((colvar(i-1,2)-xmin)/dxgrid)+1
            Mq    = a(ig)*dt ! we leave q out
            Mqq   = 2.d0*D(ig)*dt
            error = error + 0.5d0*log(2.d0*pi*Mqq) + (dq-Mq)**2 / (2.d0*Mqq)
            !error = error + 0.5d0*log(diff(ig)*pi) + (dq-a(ig)*dt)**2/(diff(ig))
            nave  = nave+1
          endif 
        enddo
        error = error/dble(nave)
      endif
      !
      if (prop_order.eq.2) then
        D(:)=kT/(prof_m(:)*prof_g(:))
        do ig=1,ngrid-1
          dD(ig)=( D(ig+1)-D(ig) )/dxgrid
        enddo
        dD(ngrid)=dD(ngrid-1)
        do ig=1,ngrid-1
          ddD(ig)=( dD(ig+1)-dD(ig) )/dxgrid
        enddo
        ddD(ngrid)=ddD(ngrid-1)
        a(:)=( D(:)*prof_force(:)/kT + dD(:) )
        do ig=1,ngrid-1
          da(ig)=( a(ig+1)-a(ig) )/dxgrid
        enddo
        da(ngrid)=da(ngrid-1)
        do ig=1,ngrid-1
          dda(ig)=( da(ig+1)-da(ig) )/dxgrid
        enddo
        dda(ngrid)=dda(ngrid-1)
        error=0.d0
        nave=0
        do i=2,nttot
          if (colvar(i,1)-colvar(i-1,1)>0.d0) then ! (avoid time discontinuity)
            dq    = colvar(i,2)-colvar(i-1,2)
            ig = int((colvar(i-1,2)-xmin)/dxgrid)+1 ! pre-point
            Mq    = a(ig)*dt+0.5d0*( a(ig)*da(ig)+dda(ig)*D(ig) )*dt*dt ! we leave q out
            Mqq   = 2.d0*D(ig)*dt+( a(ig)*dD(ig)+2.d0*da(ig)*D(ig)+D(ig)*ddD(ig) )*dt*dt
            error = error + 0.5d0*log(2.d0*pi*Mqq) + (dq-Mq)**2 / (2.d0*Mqq)
            nave  = nave+1
          endif 
        enddo
        error = error/dble(nave)
      endif
      !
    elseif (type_Langevin.eq.1) then
      !
      ! log likelihood from short-time standard (Kramers) propagator, third order:
      ! note that b=phi-gamma*v, phi=force/m, D=gamma/m*beta, db/dv=-gamma
      !
      D(:)=prof_g(:)*kT/prof_m(:)
      do ig=1,ngrid-1
        dD(ig)=( D(ig+1)-D(ig) )/dxgrid
      enddo
      dD(ngrid)=dD(ngrid-1)
      do ig=1,ngrid-1
        ddD(ig)=( dD(ig+1)-dD(ig) )/dxgrid
      enddo
      ddD(ngrid)=ddD(ngrid-1)
      !
      phi(:)=prof_force(:)/prof_m(:)
      do ig=1,ngrid-1
        dphi(ig)=( phi(ig+1)-phi(ig) )/dxgrid
      enddo
      dphi(ngrid)=dphi(ngrid-1)
      do ig=1,ngrid-1
        ddphi(ig)=( dphi(ig+1)-dphi(ig) )/dxgrid
      enddo
      ddphi(ngrid)=ddphi(ngrid-1)
      !
      gam(:)=prof_g(:)
      do ig=1,ngrid-1
        dgam(ig)=( gam(ig+1)-gam(ig) )/dxgrid
      enddo
      dgam(ngrid)=dgam(ngrid-1)
      do ig=1,ngrid-1
        ddgam(ig)=( dgam(ig+1)-dgam(ig) )/dxgrid
      enddo
      ddgam(ngrid)=ddgam(ngrid-1)
      dt2=dt*dt
      dt3=dt2*dt
      !
      error=0.d0
      nave=0
      do i=3,nttot
        if (colvar(i,1)-colvar(i-2,1)>0.d0) then ! (avoid time discontinuity)
          q      = colvar(i-2,2)
          q2     = colvar(i-1,2)
          q3     = colvar(i  ,2)
          v      = ( q2-q  )/dt
          v2     = ( q3-q2 )/dt
          ig     = int((q-xmin)/dxgrid)+1
          b      =   phi(ig)  -gam(ig)*v
          db     =  dphi(ig) -dgam(ig)*v
          ddb    = ddphi(ig)-ddgam(ig)*v
          g      = gam(ig)
          dg     = dgam(ig)
          !
          tmp = (db*v-b*g)
          Mq  = q + v*dt + b*dt2/2.d0 + tmp*dt3/6.d0
          Mqq = 2.d0*D(ig)*dt3/3.d0
          Mv  = v + b*dt + tmp*dt2/2.d0 &
              + ((ddb*v-db*g-2.d0*b*dg)*v+b*db+b*g*g-2.d0*D(ig)*dg)*dt3/6.d0
          Mvv = 2.d0*D(ig)*dt + (dD(ig)*v-2.d0*D(ig)*g)*dt2 &
              + ((ddD(ig)*v-2.d0*dD(ig)*g-4.d0*D(ig)*dg)*v+dD(ig)*b+2.d0*D(ig)*(db+2.d0*g*g))*dt3/3.d0
          Mqv = D(ig)*dt2 + (dD(ig)*v-3.d0*D(ig)*g)*dt3/3.d0
          detM = Mqq*Mvv-Mqv*Mqv 
          !
          error = error + 0.5d0*log(4.d0*pi2*detM) &
                + ( 0.5d0*Mvv*(q2-Mq)**2 + 0.5d0*Mqq*(v2-Mv)**2 - Mqv*(q2-Mq)*(v2-Mv) )/detM
          nave  = nave+1
        endif 
      enddo
!      do i=3,nt_interp
!        if (interp_colvar(i,1)-interp_colvar(i-2,1)>0.d0) then ! (avoid time discontinuity)
!          q2     = interp_colvar(i,2)
!          q1     = interp_colvar(i-1,2)
!          q0     = interp_colvar(i-2,2)
!          ddq    = ( q2-2.d0*q1+q0 )/tau
!          dq     = q1-q0 
!          ig  = int((q1-xmin)/dxgrid)+1
!          f1     = prof_force(ig)
!          m1     = prof_m(ig)
!          g1     = prof_g(ig)
!          delta  = ( ddq - tau*f1/m1 + g1*dq )
!          sigma2 = tau*2.d0*kT*g1/m1
!          delta  = delta*delta / sigma2
!          error  = error + 0.5d0*log(2.d0*pi*sigma2) + 0.5d0*delta ! missing the normalization here
!          nave   = nave+1
!        endif 
!      enddo
      error = error/dble(nave)
      !
    endif
    !
  endif
  ! TODO: add also Kolmogorov-Smirnov statistic on P(x,t) (discarding velocities...)
!
end subroutine compute_error
!======================================================================
subroutine compute_typical_min_error(minerr1,minerr2)
!
  use common_var
  !
  double precision :: minerr1,minerr2
  double precision :: Ptmp(nx,nx,0:nt)
  !
  ! store the correct Pref (from MD data)
  Ptmp=Pref
  ! compute 1st Pmod (a particular realization depending on random sequence)
  call compute_Pmod ! run ntraj_Langevin simulations and compute Pmod
  ! pretend Pref is Pmod
  Pref=Pmod
  ! compute 2nd Pmod (a particular realization depending on random sequence)
  call compute_Pmod ! run ntraj_Langevin simulations and compute Pmod
  ! compute errors between the two Pmod obtained from identical parameters
  call compute_error(minerr1,1)  
  call compute_error(minerr2,2)  
  write(*,'(A,2E11.4)') " typical min error (between two realizations of the same model) = ",&
   minerr1,minerr2
  ! store back the original Pref
  Pref=Ptmp
!
end subroutine compute_typical_min_error
!======================================================================
function lcg(s)
  ! This simple PRNG might not be good enough for real work, but is
  ! sufficient for seeding a better PRNG.
  use iso_fortran_env, only: int64
  integer :: lcg
  integer(int64) :: s
  if (s == 0) then
     s = 104729
  else
     s = mod(s, 4294967296_int64)
  end if
  s = mod(s * 279470273_int64, 4294967291_int64)
  lcg = int(mod(s, int(huge(0), int64)), kind(0))
end function lcg
!======================================================================
subroutine init_random_seed()
  use iso_fortran_env, only: int64
  implicit none
  integer, allocatable :: seed(:)
  integer :: i, n, un, istat, dt(8), pid, lcg
  integer(int64) :: t
  double precision :: G

  ! this code is taken from https://gcc.gnu.org/onlinedocs/gfortran/RANDOM_005fSEED.html
  write(*,*) ""
  write(*,*) "initializing random number generator" 
  call random_seed(size = n)
  allocate(seed(n))
  ! First try if the OS provides a random number generator
  open(newunit=un, file="/dev/urandom", access="stream", &
       form="unformatted", action="read", status="old", iostat=istat)
  if (istat == 0) then
     read(un) seed
     close(un)
  else
     ! Fallback to XOR:ing the current time and pid. The PID is
     ! useful in case one launches multiple instances of the same
     ! program in parallel.
     call system_clock(t)
     if (t == 0) then
        call date_and_time(values=dt)
        t = (dt(1) - 1970) * 365_int64 * 24 * 60 * 60 * 1000 &
             + dt(2) * 31_int64 * 24 * 60 * 60 * 1000 &
             + dt(3) * 24_int64 * 60 * 60 * 1000 &
             + dt(5) * 60 * 60 * 1000 &
             + dt(6) * 60 * 1000 + dt(7) * 1000 &
             + dt(8)
     end if
     pid = getpid()
     t = ieor(t, int(pid, kind(t)))
     do i = 1, n
        seed(i) = lcg(t)
     end do
  end if
  call random_seed(put=seed)
  !
  !!!!!!!!!!!!! test Gaussian random numbers:
  do i=1,10000
    call noise(G)
    write(222,'(F12.6)') G
  enddo
  !
end subroutine init_random_seed
!======================================================================
