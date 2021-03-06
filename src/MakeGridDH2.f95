subroutine MakeGridDH(griddh, n, cilm, lmax, norm, sampling, csphase, &
                        lmax_calc)
!-------------------------------------------------------------------------------
!
!   Given the Spherical Harmonic coefficients CILM, this subroutine
!   will evalate the function on a grid with an equal number of samples N in 
!   both latitude and longitude (or N by 2N by specifying the optional parameter
!   SAMPLING = 2). This is the inverse of the routine SHExpandDH, both of which
!   are done quickly using FFTs for each degree of each latitude band. The 
!   number of samples is determined by the spherical harmonic bandwidth LMAX.
!   Nevertheless, the coefficients can be evaluated up to smaller spherical 
!   harmonic degree by specifying the optional parameter LMAX_CALC. Note that 
!   N is always EVEN for this routine. 
!   
!   The Legendre functions are computed on the fly using the scaling methodolgy 
!   presented in Holmes and Featherston (2002). When NORM = 1, 2 or 4, these are 
!   accurate to about degree 2800. When NORM = 3, the routine is only stable to 
!   about degree 15!
!
!   The output grid contains N samples in latitude from 90 to -90+interval, 
!   and in longitude from 0 to 360-2*interval (or N x 2N, see below), where 
!   interval is the sampling interval, and n=2*(LMAX+1). Note that the datum at 
!   90 degees latitude is ultimately downweighted to zero, so this point does 
!   not contribute to the spherical harmonic coefficients.
!
!   Calling Parameters
!
!       IN
!           cilm        Input spherical harmonic coefficients with 
!                       dimension (2, lmax+1, lmax+1).
!           lmax        Maximum spherical harmonic degree used in the expansion.
!                       This determines the spacing of the output grid.
!
!       OUT
!           griddh      Gridded data of the spherical harmonic
!                       coefficients CILM with dimensions (2*LMAX+2 , 2*LMAX+2). 
!           n           Number of samples in the grid, always even, which 
!                       is 2*(LMAX+2).
!       OPTIONAL (IN)
!           norm        Normalization to be used when calculating Legendre 
!                       functions
!                           (1) "geodesy" (default)
!                           (2) Schmidt
!                           (3) unnormalized
!                           (4) orthonormalized
!           sampling    (1) Grid is N latitudes by N longitudes (default).
!                       (2) Grid is N by 2N. The higher frequencies resulting
!                       from this oversampling in longitude are discarded, and 
!                       hence not aliased into lower frequencies.
!           csphase     1: Do not include the phase factor of (-1)^m
!                       -1: Apply the phase factor of (-1)^m.
!           lmax_calc   The maximum spherical harmonic degree to evaluate
!                       the coefficients up to.
!
!   Notes:
!       1.  If lmax is greater than the the maximum spherical harmonic
!           degree of the input file, then this file will be ZERO PADDED!
!           (i.e., those degrees after lmax are assumed to be zero).
!       2.  Latitude is geocentric latitude.
!
!   Dependencies:   FFTW3, CSPHASE_DEFAULT
!
!   Copyright (c) 2015, Mark A. Wieczorek
!   All rights reserved.
!
!-------------------------------------------------------------------------------
    use FFTW3
    use SHTOOLS, only: CSPHASE_DEFAULT
    
    implicit none
    
    real*8, intent(in) :: cilm(:,:,:)
    real*8, intent(out) :: griddh(:,:)
    integer, intent(in) :: lmax
    integer, intent(out) :: n
    integer, intent(in), optional :: norm, sampling, csphase, lmax_calc
    integer :: l, m, i, l1, m1, lmax_comp, i_eq, i_s, astat(4), lnorm, nlong
    real*8 :: grid(4*lmax+4), pi, theta, coef0, scalef, rescalem, u, p, pmm, &
              pm1, pm2, z, coef0s, tempr
    complex*16 :: coef(2*lmax+3), coefs(2*lmax+3), tempc
    integer*8 :: plan
    real*8, save, allocatable :: ff1(:,:), ff2(:,:), sqr(:)
    integer*1, save, allocatable :: fsymsign(:,:)
    integer, save :: lmax_old = 0, norm_old = 0
    integer*1 :: phase

!$OMP   threadprivate(ff1, ff2, sqr, fsymsign, lmax_old, norm_old)
    
    n = 2 * lmax + 2
    
    if (present(sampling)) then
        if (sampling /= 1 .and. sampling /=2) then
            print*, "Error --- MakeGridDH"
            print*, "Optional parameter SAMPLING must be 1 (N by N) " // &
                    "or 2 (N by 2N)."
            print*, "Input value is ", sampling
            stop
        end if
    end if
    
    if (size(cilm(:,1,1)) < 2) then
        print*, "Error --- MakeGridDH"
        print*, "CILM must be dimensioned as (2, *, *)."
        print*, "Input dimension is ", size(cilm(:,1,1)), size(cilm(1,:,1)), &
                size(cilm(1,1,:))
        stop
    end if 
    
    if (present(sampling)) then
        if (sampling == 1) then
            if (size(griddh(:,1)) < n .or. size(griddh(1,:)) < n) then
                print*, "Error --- MakeGridDH"
                print*, "GRIDDH must be dimensioned as (N, N) where N is ", n
                print*, "Input dimension is ", size(griddh(:,1)), &
                        size(griddh(1,:))
                stop
            end if
            
        else if (sampling ==2) then
            if (size(griddh(:,1)) < n .or. size(griddh(1,:)) < 2*n) then
                print*, "Error --- MakeGriddDH"
                print*, "GRIDDH must be dimensioned as (N, 2*N) where N is ", n
                print*, "Input dimension is ", size(griddh(:,1)), &
                        size(griddh(1,:))
                stop
            end if
        end if
        
    else
        if (size(griddh(:,1)) < n .or. size(griddh(1,:)) < n) then
            print*, "Error --- MakeGridDH"
            print*, "GRIDDH must be dimensioned as (N, N) where N is ", n
            print*, "Input dimension is ", size(griddh(:,1)), size(griddh(1,:))
            stop
        end if

    end if
        
    if (present(norm)) then
        if (norm > 4 .or. norm < 1) then
            print*, "Error --- MakeGridDH"
            print*, "Parameter NORM must be 1 (geodesy), 2 (Schmidt), " // &
                    "3 (unnormalized), or 4 (orthonormalized)."
            print*, "Input value is ", norm
            stop
        end if
        
        lnorm = norm
        
    else
        lnorm = 1
        
    end if
    
    if (present(csphase)) then
            if (csphase /= -1 .and. csphase /= 1) then
                print*, "Error --- MakeGridDH"
                print*, "CSPHASE must be 1 (exclude) or -1 (include)"
                print*, "Input valuse is ", csphase
                stop
                
            else
                phase = csphase
                
            endif
        else
            phase = CSPHASE_DEFAULT
            
        endif

    pi = acos(-1.0d0)
    
    scalef = 1.0d-280
    
    if (present(lmax_calc)) then
        if (lmax_calc > lmax) then
            print*, "Error --- MakeGridDH"
            print*, "LMAX_CALC must be less than or equal to LMAX."
            print*, "LMAX = ", lmax
            print*, "LMAX_CALC = ", lmax_calc
            stop
            
        else
            lmax_comp = min(lmax, size(cilm(1,1,:))-1, size(cilm(1,:,1))-1, &
                            lmax_calc)
                            
        end if
    else
        lmax_comp = min(lmax, size(cilm(1,1,:))-1, size(cilm(1,:,1))-1)
        
    end if
    
    if (present(sampling)) then
        if (sampling == 1) then
            nlong = n
            
        else
            nlong = 2 * n
            
        end if
        
    else
        nlong = n
        
    end if
    
    !---------------------------------------------------------------------------
    !
    !   Calculate recursion constants used in computing the Legendre polynomials
    !
    !---------------------------------------------------------------------------
    
    if (lmax_comp /= lmax_old .or. lnorm /= norm_old) then
        
        if (allocated (sqr)) deallocate (sqr)
        if (allocated (ff1)) deallocate (ff1)
        if (allocated (ff2)) deallocate (ff2)
        if (allocated (fsymsign)) deallocate (fsymsign)
        
        allocate (sqr(2 * lmax_comp +1 ), stat=astat(1))
        allocate (ff1(lmax_comp+1,lmax_comp+1), stat=astat(2))
        allocate (ff2(lmax_comp+1,lmax_comp+1), stat=astat(3))
        allocate (fsymsign(lmax_comp+1,lmax_comp+1), stat=astat(4))
        
        if (sum(astat(1:4)) /= 0) then
            print*, "MakeGridDH --- Error"
            print*, "Problem allocating arrays SQR, FF1, FF2, or FSYMSIGN", &
                    astat(1), astat(2), astat(3), astat(4)
            stop
        end if
        
        !-----------------------------------------------------------------------
        !
        !   Calculate signs used for symmetry of Legendre functions about 
        !   equator
        !
        !-----------------------------------------------------------------------
        do l = 0, lmax_comp, 1
            do m = 0, l, 1
                if (mod(l-m,2) == 0) then
                    fsymsign(l+1,m+1) = 1
                    
                else
                    fsymsign(l+1,m+1) = -1
                    
                end if
                
            end do
            
        end do
            
        !-----------------------------------------------------------------------
        !
        !   Precompute square roots of integers that are used several times.
        !
        !-----------------------------------------------------------------------
        do l = 1, 2 * lmax_comp + 1
            sqr(l) = sqrt(dble(l))
        end do

        !-----------------------------------------------------------------------
        !
        !   Precompute multiplicative factors used in recursion relationships
        !       P(l,m) = x*f1(l,m)*P(l-1,m) - P(l-2,m)*f2(l,m)
        !       k = l*(l+1)/2 + m + 1
        !   Note that prefactors are not used for the case when m=l as a 
        !   different recursion is used. Furthermore, for m=l-1, Plmbar(l-2,m) 
        !   is assumed to be zero.
        !
        !-----------------------------------------------------------------------
        select case (lnorm)
        
            case (1,4)
    
                if (lmax_comp /= 0) then
                    ff1(2,1) = sqr(3)
                    ff2(2,1) = 0.0d0
                end if
                
                do l = 2, lmax_comp, 1
                    ff1(l+1,1) = sqr(2*l-1) * sqr(2*l+1) / dble(l)
                    ff2(l+1,1) = dble(l-1) * sqr(2*l+1) / sqr(2*l-3) / dble(l)
                    
                    do m = 1, l-2, 1
                        ff1(l+1,m+1) = sqr(2*l+1) * sqr(2*l-1) / sqr(l+m) &
                                        / sqr(l-m)
                        ff2(l+1,m+1) = sqr(2*l+1) * sqr(l-m-1) * sqr(l+m-1) &
                                        / sqr(2*l-3) / sqr(l+m) / sqr(l-m) 
                    end do
                    
                    ff1(l+1,l) = sqr(2*l+1) * sqr(2*l-1) / sqr(l+m) / sqr(l-m)
                    ff2(l+1,l) = 0.0d0
                    
                end do
            
            case (2)
            
                if (lmax_comp /= 0) then
                    ff1(2,1) = 1.0d0
                    ff2(2,1) = 0.0d0
                end if
                
                do l = 2, lmax_comp, 1
                    ff1(l+1,1) = dble(2*l-1) / dble(l)
                    ff2(l+1,1) = dble(l-1) / dble(l)
                    
                    do m = 1, l-2, 1
                        ff1(l+1,m+1) = dble(2*l-1) / sqr(l+m) / sqr(l-m)
                        ff2(l+1,m+1) = sqr(l-m-1) * sqr(l+m-1) / sqr(l+m) &
                                        / sqr(l-m)
                    end do
                    
                    ff1(l+1,l)= dble(2*l-1) / sqr(l+m) / sqr(l-m)
                    ff2(l+1,l) = 0.0d0
                    
                end do
            
            case (3)
        
                do l = 1, lmax_comp, 1
                    ff1(l+1,1) = dble(2*l-1) / dble(l)
                    ff2(l+1,1) = dble(l-1) / dble(l)
                    
                    do m = 1, l-1, 1
                        ff1(l+1,m+1) = dble(2*l-1) / dble(l-m)
                        ff2(l+1,m+1) = dble(l+m-1) / dble(l-m)
                    end do
                    
                end do

        end select
    
        lmax_old = lmax_comp
        norm_old = lnorm
    
    end if
    
    !---------------------------------------------------------------------------
    !
    !   Do special case of lmax_comp = 0
    !
    !--------------------------------------------------------------------------- 
    if (lmax_comp == 0) then
    
        select case (lnorm)
            case (1,2,3); pm2 = 1.0d0
            case (4); pm2 = 1.0d0 / sqrt(4.0d0 * pi)
        end select
        
        if (present(sampling)) then
            if (sampling == 1) then
                griddh(1:n, 1:n) = cilm(1,1,1) * pm2
            else
                griddh(1:n, 1:2*n) = cilm(1,1,1) * pm2
            end if
            
        else
            griddh(1:n, 1:n) = cilm(1,1,1) * pm2
        
        end if
    
        return
    
    end if
    
    !---------------------------------------------------------------------------
    !
    !   Determine Clms one l at a time by intergrating over latitude.
    !   
    !---------------------------------------------------------------------------
    
    call dfftw_plan_dft_c2r_1d_(plan, nlong, coef(1:nlong/2+1), grid(1:nlong), &
                                FFTW_MEASURE)

    i_eq = n/2 + 1  ! Index correspondong to zero latitude

    do i = 1, i_eq - 1, 1
    
        i_s = 2*i_eq -i
    
        theta = pi * dble(i-1) / dble(n)
        z = cos(theta)
        u = sqrt( (1.0d0-z) * (1.0d0+z) )

        coef(1:lmax+1) = dcmplx(0.0d0,0.0d0)
        coef0 = 0.0d0
        coefs(1:lmax+1) = dcmplx(0.0d0,0.0d0)
        coef0s = 0.0d0
        
        select case (lnorm)
            case (1,2,3); pm2 = 1.0d0
            case (4); pm2 = 1.0d0 / sqrt(4.0d0 * pi)
        end select

        tempr =  cilm(1,1,1) * pm2
        coef0 = coef0 + tempr
        coef0s = coef0s + tempr     ! fsymsign is always 1 for l=m=0
                
        pm1 =  ff1(2,1) * z * pm2
        tempr = cilm(1,2,1) * pm1
        coef0 = coef0 + tempr
        coef0s = coef0s - tempr     ! fsymsign = -1
                
        do l = 2, lmax_comp, 1
            l1 = l+1
            p = ff1(l1,1) * z * pm1 - ff2(l1,1) * pm2
            tempr = cilm(1,l1,1) * p
            coef0 = coef0 + tempr
            coef0s = coef0s + tempr * fsymsign(l1,1)
            pm2 = pm1
            pm1 = p
        end do
                
        select case (lnorm)
            case (1,2);  pmm = sqr(2) * scalef
            case (3);    pmm = scalef
            case (4);    pmm = sqr(2) * scalef / sqrt(4.0d0 * pi)
        end select
                
        rescalem = 1.0d0/scalef
            
        do m = 1, lmax_comp-1, 1
            m1 = m+1
            rescalem = rescalem * u
                    
            select case (lnorm)
                case (1,4)
                    pmm = phase * pmm * sqr(2*m+1) / sqr(2*m)
                    pm2 = pmm
                case (2)
                    pmm = phase * pmm * sqr(2*m+1) / sqr(2*m)
                    pm2 = pmm / sqr(2*m+1)
                case (3)
                    pmm = phase * pmm * dble(2*m-1)
                    pm2 = pmm
            end select
            
            tempc = dcmplx(cilm(1,m1,m1), - cilm(2,m1,m1)) * pm2
            coef(m1) = coef(m1) + tempc
            coefs(m1) = coefs(m1) + tempc
            ! fsymsign = 1
                                        
            pm1 = z * ff1(m1+1,m1) * pm2
                    
            tempc = dcmplx(cilm(1,m1+1,m1), - cilm(2,m1+1,m1)) * pm1
            coef(m1) = coef(m1) + tempc 
            coefs(m1) = coefs(m1) - tempc
            ! fsymsign = -1
                    
            do l = m + 2, lmax_comp, 1
                l1 = l+1
                p = z * ff1(l1,m1) * pm1 - ff2(l1,m1) * pm2
                pm2 = pm1
                pm1 = p
                tempc = dcmplx(cilm(1,l1,m1), - cilm(2,l1,m1)) * p
                coef(m1) = coef(m1) + tempc
                coefs(m1) = coefs(m1) + tempc * fsymsign(l1,m1)
            end do
                    
            coef(m1) = coef(m1) * rescalem
            coefs(m1) = coefs(m1) * rescalem
                    
        end do           
                                
        rescalem = rescalem * u
                
        select case(lnorm)
            case(1,4)
                pmm = phase * pmm * sqr(2*lmax_comp+1) / sqr(2*lmax_comp) &
                        * rescalem
            case(2)
                pmm = phase * pmm / sqr(2*lmax_comp) * rescalem
            case(3)
                pmm = phase * pmm * dble(2*lmax_comp-1) * rescalem
        end select
                    
        tempc = dcmplx(cilm(1,lmax_comp+1,lmax_comp+1), &
                        - cilm(2,lmax_comp+1,lmax_comp+1)) * pmm
        coef(lmax_comp+1) = coef(lmax_comp+1) + tempc
        coefs(lmax_comp+1) = coefs(lmax_comp+1) + tempc
        ! fsymsign = 1
        
        coef(1) = dcmplx(coef0,0.0d0)
        coef(2:lmax+1) = coef(2:lmax+1)/2.0d0
        
        if (present(sampling)) then
            if (sampling == 2) then
                coef(lmax+2:2*lmax+3) = dcmplx(0.0d0,0.0d0) 
            end if
        end if
                        
        call dfftw_execute_(plan)    ! take fourier transform
        griddh(i,1:nlong) = grid(1:nlong)
                
        if (i /= 1) then    ! don't compute value for south pole.
            coef(1) = dcmplx(coef0s,0.0d0)
            coef(2:lmax+1) = coefs(2:lmax+1)/2.0d0
        
            if (present(sampling)) then
                if (sampling == 2) then
                    coef(lmax+2:2*lmax+3) = dcmplx(0.0d0,0.0d0) 
                end if
            end if
                
            call dfftw_execute_(plan)    ! take fourier transform
            griddh(i_s,1:nlong) = grid(1:nlong)
            
        end if
            
    end do
    
    ! Finally, do equator
    
    z = 0.0d0
    u = 1.0d0

    coef(1:lmax+1) = dcmplx(0.0d0,0.0d0)
    coef0 = 0.0d0
    
    select case(lnorm)
        case (1,2,3); pm2 = 1.0d0
        case (4); pm2 = 1.0d0 / sqrt(4.0d0 * pi)
    end select
    
    coef0 = coef0 + cilm(1,1,1) * pm2
                
    do l = 2, lmax_comp, 2
        l1 = l+1
        p = - ff2(l1,1) * pm2
        pm2 = p
        coef0 = coef0 + cilm(1,l1,1) * p
    end do
                
    select case (lnorm)
        case (1,2);  pmm = sqr(2) * scalef
        case (3);    pmm = scalef
        case (4);    pmm = sqr(2) * scalef / sqrt(4.0d0 * pi)
    end select
                
    rescalem = 1.0d0/scalef
            
    do m = 1, lmax_comp-1, 1   
        m1 = m + 1
                    
        select case (lnorm)
            case (1,4)
                pmm = phase * pmm * sqr(2*m+1) / sqr(2*m)
                pm2 = pmm
            case (2)
                pmm = phase * pmm * sqr(2*m+1) / sqr(2*m)
                pm2 = pmm / sqr(2*m+1)
            case (3)
                pmm = phase * pmm * dble(2*m-1)
                pm2 = pmm
        end select
                    
        coef(m1) = coef(m1) + dcmplx(cilm(1,m1,m1), &
                    - cilm(2,m1,m1)) * pm2
                    
        do l = m + 2, lmax_comp, 2
            l1 = l+1
            p = - ff2(l1,m1) * pm2
            coef(m1) = coef(m1) + dcmplx(cilm(1,l1,m1), &
                    - cilm(2,l1,m1)) * p
            pm2 = p
        end do
                    
    end do           
                
    select case (lnorm)
        case (1,4)
            pmm = phase * pmm * sqr(2*lmax_comp+1) / sqr(2*lmax_comp)
        case (2)
            pmm = phase * pmm / sqr(2*lmax_comp)
        case (3)
            pmm = phase * pmm * dble(2*lmax_comp-1)
    end select
                    
    coef(lmax_comp+1) = coef(lmax_comp+1) + &
                        dcmplx(cilm(1,lmax_comp+1,lmax_comp+1), &
                        - cilm(2,lmax_comp+1,lmax_comp+1)) * pmm
        
    coef(1) = dcmplx(coef0,0.0d0)
    coef(2:lmax+1) = coef(2:lmax+1) * rescalem / 2.0d0
    
    if (present(sampling)) then
        if (sampling == 2) then
            coef(lmax+2:2*lmax+3) = dcmplx(0.0d0,0.0d0) 
        end if
    end if
    
    call dfftw_execute_(plan)    ! take fourier transform
                
    griddh(i_eq,1:nlong) = grid(1:nlong)

    call dfftw_destroy_plan_(plan)
                
end subroutine MakeGridDH
