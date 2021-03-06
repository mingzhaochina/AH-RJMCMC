MODULE IL_RJMCMC
!
!  This program defines the Integrated Likelihood RJMCMC method.

!  The model is the set of all change points and intensity values (both at the internal change points and the end points)
! 
!  Marginalisation is performed on the fly by binning using a total of NBINS bins.
!  The outputs are returned in the structure RETURN_INFO
!
!  Phil Livermore, April 2016
! 
!
! For checking purposes, the subroutine runs in two modes:
! RUNNING_MODE = 1   This is the usual mode of operation
! RUNNING_MODE <> 1  This sets the likelihood to be unity, so that the prior distributions are sampled - these can be checked against the assumed distributions.

USE SORT

TYPE RETURN_INFO_STRUCTURE
REAL( KIND = 8), ALLOCATABLE, DIMENSION(:) :: AV, BEST, SUP, INF, MEDIAN, MODE, CHANGE_POINTS, CONVERGENCE
REAL( KIND = 8), ALLOCATABLE :: MARGINAL_DENSITY_INTENSITY(:,:)
INTEGER :: MAX_NUMBER_CHANGE_POINTS_HISTORY
INTEGER, ALLOCATABLE :: n_changepoint_hist(:)
END TYPE RETURN_INFO_STRUCTURE

REAL( KIND = 8), PARAMETER :: PI = 3.14159265358979_8
INTEGER :: RUNNING_MODE

CONTAINS
SUBROUTINE RJMCMC(burn_in, NUM_DATA, MIDPOINT_AGE, DELTA_AGE, INTENSITY, I_SD, NSAMPLE, I_MIN, I_MAX, X_MIN, X_MAX, K_MIN, K_MAX, SIGMA_MOVE, sigma_change_value, sigma_birth, discretise_size, SHOW, THIN, NBINS, RETURN_INFO, CALC_CREDIBLE,credible, FREQ_WRITE_MODELS, WRITE_MODEL_FILE_NAME, LIKELIHOOD_CHOICE, Outputs_directory)


IMPLICIT NONE
TYPE (RETURN_INFO_STRUCTURE) :: RETURN_INFO

INTEGER :: I, K, BURN_IN, NSAMPLE, K_INIT, K_MAX, K_MIN, K_MAX_ARRAYBOUND, discretise_size, show, thin, num, J, &
           NUM_DATA, K_MAX_ARRAY_BOUND, s, birth, death, move, ind, k_prop, accept, k_best, out, &
           NBINS, BIN_INDEX, IS_DIFF, CHANGE_value, i_age, FREQ_WRITE_MODELS, IOS, LIKELIHOOD_CHOICE
REAL( KIND = 8) :: D_MIN, D_MAX, I_MAX, I_MIN, sigma_move, sigma_change_value, sigma_birth, like_prop, prob, INT_J, pt_death(2), X_MIN, X_MAX, U, RAND(2), alpha
CHARACTER(300) :: WRITE_MODEL_FILE_NAME, format_descriptor

INTEGER, ALLOCATABLE :: ORDER(:)
REAL( KIND = 8) :: ENDPT_BEST(2)
CHARACTER(*) :: Outputs_directory

INTEGER :: b, bb, AB, AD, PD, PB, ACV, PCV, AP, PP, num_age_changes
REAL( KIND = 8) :: MIDPOINT_AGE(:), DELTA_AGE(:), Intensity(:), I_sd(:), ENDPT(2), ENDPT_PROP(2), like, like_best, like_init, credible
REAL( KIND = 8), ALLOCATABLE :: VAL_MIN(:), VAL_MAX(:),   MINI(:,:), MAXI(:,:), PT(:,:), PT_PROP(:,:), interpolated_signal(:), X(:), PT_NEW(:), PT_BEST(:,:), age(:), age_prop(:)
INTEGER, ALLOCATABLE, DIMENSION(:) :: IND_MIN, IND_MAX
INTEGER, ALLOCATABLE :: discrete_history(:,:)
LOGICAL :: CALC_CREDIBLE

!needed to write to files in row format:
WRITE(format_descriptor,'(A,i3,A)') '(',discretise_size,'F14.4)'

! Other parameters are fixed here

k_max_array_bound = k_max + 1;


!Uniform prior on vertex positions
D_min = X_min
D_max = X_max


NUM=ceiling((nsample-burn_in)*(100.0_8-credible)/200.0_8/thin)  ! number of collected samples for credible intervals

ALLOCATE( X(1: discretise_size) )
    DO I=1, discretise_size
    X(I) = X_MIN + REAL(I-1, KIND = 8)/REAL(discretise_size-1, KIND = 8) * (X_MAX - X_MIN)
    ENDDO

ALLOCATE( val_min(1: discretise_size), val_max(1: discretise_size), ind_min(1: discretise_size), ind_max(1: discretise_size),  &
MINI(1: discretise_size, 1:NUM), MAXI(1: discretise_size, 1:NUM), age(1: num_data), age_prop(1:num_data), discrete_history(1:discretise_size,1:NBINS) )

ALLOCATE( pt(1:k_max_array_bound,2), pt_prop(1:k_max_array_bound,2) , pt_best(1:k_max_array_bound,2) )

IF( FREQ_WRITE_MODELS > 0) then
OPEN(15, FILE = TRIM(Outputs_directory)//'/'//TRIM(WRITE_MODEL_FILE_NAME), STATUS = 'REPLACE', FORM = 'FORMATTED', IOSTAT = IOS)
IF( IOS .NE. 0) THEN
PRINT*, 'CANNOT OPEN FILE FOR MODEL WRITING ', TRIM(Outputs_directory)//'/'//TRIM(WRITE_MODEL_FILE_NAME)
STOP
ENDIF
WRITE(15,*) discretise_size, floor(REAL(nsample-burn_in, KIND = 8)/thin/FREQ_WRITE_MODELS)
WRITE(15,format_descriptor) X(1:discretise_size)
ENDIF



val_min(:) = 0.
val_max(:) = 0.
ind_min(:) = 0
ind_max(:) = 0
MINI(:,:) = 0.
MAXI(:,:) = 0.
pt(:,:) = 0.
b = 0 
bb = 0
AB=0
AD=0
PB=0
PD=0
ACV=0
PCV=0
AP=0
PP=0
RETURN_INFO%best(:) = 0.0_8
RETURN_INFO%AV(:) = 0.0_8
RETURN_INFO%change_points(:) = 0.0_8
RETURN_INFO%convergence(:) = 0.0_8
RETURN_INFO%sup(:) = 0.0_8
RETURN_INFO%inf(:) = 0.0_8
RETURN_INFO%n_changepoint_hist(:) = 0
discrete_history(:,:) = 0

IF(MINVAL( I_SD(1:NUM_DATA)) .eq. 0.0_8) THEN
PRINT*,'MIN INTENSITY ERROR IS 0, INCOMPATITBLE WITH ASSUMPTIONS BUILT INTO CODE'
STOP
ENDIF

IF(MINVAL( DELTA_AGE(1:NUM_DATA)) .eq. 0.0_8) THEN
PRINT*,'MIN AGE ERROR IS 0, INCOMPATITBLE WITH ASSUMPTIONS BUILT INTO CODE'
STOP
ENDIF

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
! Initialize - Define randomly the first model of the chain
CALL RANDOM_NUMBER( RAND(1))
k_init = floor(RAND(1) * (K_max - K_min+1)) + k_min

k = k_init

!randomly set the data ages
DO i=1, NUM_DATA
CALL RANDOM_NUMBER( RAND(1))
AGE(i) = MIDPOINT_AGE(i) + 2.0_8 * (rand(1)-0.5_8) * DELTA_AGE(i)
enddo

DO i=1,k_init
CALL RANDOM_NUMBER( RAND(1:2))
!PRINT*, RAND(1:2), D_MIN, D_MAX, I_MIN, I_MAX
    pt(i,1)=D_min+rand(1) * (D_max-D_min)  ! position of internal vertex
    pt(i,2)=I_min+rand(2) * (I_max-I_min)  ! magnitude of vertices
enddo

CALL RANDOM_NUMBER (RAND(1:2))
endpt(1) = I_min+RAND(1) * (I_max-I_min)
endpt(2) = I_min+RAND(2) * (I_max-I_min)

! make sure the positions are sorted in ascending order.
ALLOCATE( ORDER(1:k_init), pt_new(1:k_init) )
CALL quick_sort(pt(1:k_init,1), order)

do i = 1, k_init
pt_new(i) = pt( order(i), 2)
enddo
pt(1:k_init,2) = pt_new(:)

DEALLOCATE (ORDER, pt_new)

! COMPUTE INITIAL MISFIT
ALLOCATE( interpolated_signal(1:max(NUM_DATA,discretise_size)) ) !generic output space for interpolation.


IF( RUNNING_MODE .eq. 1) THEN
like=Integrated_likelihood( k, x_min, x_max, pt, endpt, NUM_DATA, MIDPOINT_AGE, DELTA_AGE, INTENSITY, I_SD, LIKELIHOOD_CHOICE )

else
like = 1.0_8
endif

like_best=like
like_init=like


!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!%%%%%%%%%%%%%%%%% START RJ-MCMC SAMPLING %%%%%%%%%%%%%%%%%
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

WRITE(6,*) 'BEGINNING RJ-MCMC SAMPLING....'
do s=1,nsample

! Print statistics of the chain.
    
    if (mod(s,show)==0 .AND. s>burn_in) then
!        write(6,'(A,i8,A,i3,5(A,F6.1))' ) 'Samples: ',s, ' Vertices: ',k, ' Acceptance rates: birth ', 100.0*AB/PB,' death ',100.0*AD/PD, ' change ', 100.0*ACV/PCV, ' pos ', 100.0*AP/PP, ' likelihood ', like
      write(6,'(A,i8,A,i3,6(A,F6.1))' ) 'Samples: ',s, ' Vertices: ',k, ' Acceptance: change F ', 100.0*ACV/PCV, ' change age ', 100.0*AP/PP,  ' birth ', 100.0*AB/PB,' death ',100.0*AD/PD  , ' likelihood ', like

    endif
     
    
    birth=0
    move=0
    death=0
    change_value = 0

    age_prop = age
    pt_prop=pt
    endpt_prop = endpt
    like_prop = like
    k_prop = k
    prob = 1.0
    out = 1
    !----------------------------------------------------------------------
    ! Every 2nd iteration, propose a new value
    if (mod(s,2)==0) then ! Change Value
        if (s>burn_in)  PCV=PCV+1
        change_value = 1
        k_prop = k
        CALL RANDOM_NUMBER( RAND(1))
        ind=ceiling(RAND(1)*(k+2))
! Check bounds to see if outside prior

        
        if(ind == k+1)  then! change left end point
            endpt_prop(1) = endpt(1) + randn()*sigma_change_value
            if( endpt_prop(1) < I_min .or. endpt_prop(1) > I_max ) out = 0

            
        elseif( ind == k+2) then ! change right end point
            endpt_prop(2) = endpt(2) + randn()*sigma_change_value
            if( endpt_prop(2) < I_min .or. endpt_prop(2) > I_max )out = 0

            
        else ! change interior point
            pt_prop(ind,2) = pt(ind,2) + randn()*sigma_change_value
            if( pt_prop(ind,2)>I_max .or. pt_prop(ind,2)<I_min) out = 0

        endif


    !-----------------------------------------------------------------------
        ! Every 2nd iteration iteration change the vertex positions
    elseif (mod(s,2)==1) then ! Change position
        CALL RANDOM_NUMBER( RAND(1))
        u=RAND(1) !Chose randomly between 3 different types of moves
        if (u<0.333) then ! BIRTH ++++++++++++++++++++++++++++++++++++++
            birth=1
            if (s>burn_in) PB=PB+1

            k_prop = k+1
            CALL RANDOM_NUMBER( RAND(1))
            pt_prop(k+1,1)=D_min+RAND(1)*(D_max-D_min)

! check that all the time-points are different:
DO WHILE ( CHECK_DIFFERENT( pt_prop(1:k+1,1)) .EQ. 1)
WRITE(101,*) 'Birth has resulted in two vertices of exactly the same age', pt_prop(1:k+1,1)
WRITE(101, *) 'Randomly generating a new age'
CALL RANDOM_NUMBER( RAND(1))
pt_prop(k+1,1)=D_min+RAND(1)*(D_max-D_min)
END DO

!interpolate to find magnitude as inferred by current state
CALL Find_linear_interpolated_values(k, x_min, x_max, pt, endpt, 1, pt_prop(k+1:k+1,1), interpolated_signal)

            
            pt_prop(k+1,2)=interpolated_signal(1)+randn()*sigma_birth
            
!GET prob
            prob=(1.0_8/(sigma_birth*sqrt(2.0_8*pi)))*exp(-(interpolated_signal(1)-pt_prop(k+1,2))**2/(2.0_8*sigma_birth**2))
            
            !Check BOUNDS to see if outside prior
            out=1
            if ((pt_prop(k+1,2)>I_max) .OR. (pt_prop(k+1,2)<I_min))  out=0

            if ((pt_prop(k+1,1)>D_max) .OR. (pt_prop(k+1,1)<D_min))  out=0

            if (k_prop>k_max) out=0


! make sure the positions are sorted in ascending order.
ALLOCATE( ORDER(1:k_prop), pt_new(1:k_prop) )
CALL quick_sort(pt_prop(1:k_prop,1), order)

do i = 1, k_prop
pt_new(i) = pt_prop( order(i), 2)
ENDDO
pt_prop(1:k_prop,2) = pt_new(:)

DEALLOCATE (ORDER, pt_new)

            
        elseif (u<0.666) then !  DEATH +++++++++++++++++++++++++++++++++++++++++
            death=1
            if (s>burn_in) PD=PD+1
            out = 1
            k_prop = k-1

            if (k_prop<k_min) out=0

            if (out == 1) then
                CALL RANDOM_NUMBER( RAND(1))
                ind=ceiling(RAND(1)*k)
                pt_death(1:2) = pt(ind,1:2)
! remove point to be deleted, shifting everything to the left.
                if(ind > 1) pt_prop(1:ind-1,1:2)=pt(1:ind-1,1:2)
                pt_prop(ind:k-1,1:2) = pt(ind+1:k,1:2)
                
                !GET prob
!interpolate to find magnitude of current state as needed by birth

CALL Find_linear_interpolated_values(k_prop, x_min, x_max, pt_prop, endpt_prop, 1, pt_death(1:1), interpolated_signal)


prob=1.0_8/(sigma_birth*sqrt(2.0_8*pi))  *  exp(-(interpolated_signal(1)-pt_death(2))**2/(2.0_8*sigma_birth**2))
                
            endif !if (out==1)

        else ! MOVE +++++++++++++++++++++++++++++++++++++++++++++++++++++++
            if (s>burn_in) PP=PP+1
            move=1
            out=1
            k_prop = k
            CALL RANDOM_NUMBER( RAND(1:2))
            IF( k > 0) THEN  !only consider if at least one point to move. If k=0, then ind is zero and there are no points to move.
            ind=ceiling(RAND(1)*k)
            pt_prop(ind,1) = pt(ind,1)+randn()*sigma_move         !Normal distribution of move destination
            !pt_prop(ind,1) = D_MIN + RAND(2) * (D_MAX - D_MIN)  !Uniform distribution of move destination
            !Check BOUNDS
            else
            pt_prop = pt
            ENDIF
            if ((pt_prop(ind,1)>D_max) .OR. (pt_prop(ind,1)<D_min))  out=0

!! check that all the time-points are different:
DO WHILE ( CHECK_DIFFERENT( pt_prop(1:k,1)) .EQ. 1)
WRITE(101,*) 'MOVE position has resulted in two vertices of exactly the same age', pt_prop(1:k+1,1)
WRITE(101, *) 'Randomly generating a new age'
pt_prop(ind,1) = pt(ind,1)+randn()*sigma_move
END DO



! make sure the positions are sorted in ascending order.
ALLOCATE( ORDER(1:k_prop), pt_new(1:k_prop) )
CALL quick_sort(pt_prop(1:k_prop,1), order)

do i = 1, k_prop
pt_new(i) = pt_prop( order(i), 2)
ENDDO
pt_prop(1:k_prop,2) = pt_new(:)

DEALLOCATE (ORDER, pt_new)


endif


ENDIF ! decide on what proposal to make
!----------------------------------------------------------------------
    

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    ! COMPUTE MISFIT OF THE PROPOSED MODEL
    ! If the proposed model is not outside the bounds of the uniform prior,
    ! compute its misfit : "like_prop"
    if (out==1)  then
    IF( RUNNING_MODE .eq. 1) THEN
    like_prop=Integrated_likelihood( k_prop, x_min, x_max, pt_prop, endpt_prop, NUM_DATA, MIDPOINT_AGE, DELTA_AGE, INTENSITY, I_SD, LIKELIHOOD_CHOICE )
! print*, k_prop
    else
    like_prop = 1.0_8
    endif

    endif !if (out==1)


!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
! %% SEE WHETHER MODEL IS ACCEPTED
    
    accept=0
    alpha = 0
    ! The acceptance term takes different
    ! values according the the proposal that has been made.
    
    if (birth==1) then
        if(out ==1) alpha = ((1.0_8/((I_max-I_min)*prob))*exp(-like_prop+like))
        CALL RANDOM_NUMBER( RAND(1))
        if (RAND(1) <alpha) THEN
            accept=1
if (s>burn_in) AB=AB+1!; PRINT*,like_prop,like
        endif
    elseif (death==1) then
        if(out == 1) alpha = ((I_max-I_min)*prob)*exp(-like_prop+like)
        CALL RANDOM_NUMBER( RAND(1))
        if (RAND(1)<alpha) then
            accept=1
            if (s>burn_in) AD=AD+1
        endif
        
    else ! NO JUMP, i.e no change in dimension
        if(out ==1) alpha = exp(-like_prop+like)
        CALL RANDOM_NUMBER( RAND(1))
        if (RAND(1)<alpha) then
            accept=1
            if (s>burn_in) then
                if (change_value .eq. 1) then
                    ACV=ACV+1
                elseif( move .eq. 1) then
                    AP=AP+1
                else
                PRINT*, 'FATAL ERROR 1'; stop
                endif
            endif !if (s>burn_in)

        endif
    endif

! If accept, update the values
    if (accept==1) then
        k=k_prop
        pt=pt_prop
        like=like_prop
        endpt = endpt_prop
        age = age_prop
    endif

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    ! Collect samples for the ensemble solution

    if (s>burn_in .AND. mod(s-burn_in,thin)==0) THEN
            b=b+1

    CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, discretise_size, x(1:discretise_size), interpolated_signal)
  
IF( FREQ_WRITE_MODELS > 0) then
if( s>burn_in .AND. mod(s-burn_in,thin * FREQ_WRITE_MODELS) == 0) WRITE(15,'(F10.3)') (interpolated_signal(i),i=1, discretise_size)
ENDIF

! CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, discretise_size, x(1:discretise_size), interpolated_signal)

! DO THE AVERAGE
RETURN_INFO%AV(:)=RETURN_INFO%AV(:)+interpolated_signal(1:discretise_size)


! build marginal intensity density
DO i=1,discretise_size
BIN_INDEX = FLOOR( (interpolated_signal(i)-I_MIN)/REAL(I_MAX-I_MIN, KIND = 8) * NBINS ) + 1
discrete_history(i,BIN_INDEX) = discrete_history(i,BIN_INDEX) + 1
enddo



IF ( CALC_CREDIBLE ) THEN
! Credible interval
 do i=1,discretise_size

! Do the (e.g.) 95% credible interval by keeping the lowest and greatest 2.5% of
! all models at each sample point. We could either keep ALL the data and at
! the end determine these regions, or (better) keep a running list of the
! num data points we need. At the end of the algorithm, simply take the
! maximum of the smallest points, and the min of the largest, to get the
! bounds on the credible intervals.
! Method:
! num is the number of data points corresponding to 2.5% of the total number
! of samples (after thinning).
! Collect num datapoints from the first num samples.
! For each subsequent sample, see if the value should actually be inside
! the 2.5% tail. If it is, replace an existing value by the current value.
! Repeat.

! Interestingly, this is by far the speed-bottleneck in the algorithm. As the algorithm progresses, the credible intervals converge and the
! tails need not be changed very much. This leads to an increase in speed of the algorithm as the iteration count increases.

                if (b<=num) then
                    MINI(i,b)=interpolated_signal(i)
                    MAXI(i,b)=interpolated_signal(i)
                    if (b==num) then
val_min(i) = MINVAL(MAXI(i,:) ); ind_min(i:i) = MINLOC( MAXI(i,:) )
val_max(i) = MAXVAL(MINI(i,:) ); ind_max(i:i) = MAXLOC( MINI(i,:) )

                    endif
                    
                else
                    if (interpolated_signal(i)>val_min(i)) then
                        MAXI(i,ind_min(i))=interpolated_signal(i);
                     val_min(i) = MINVAL(MAXI(i,:) ); ind_min(i:i) = MINLOC( MAXI(i,:) )
                    endif
                    if (interpolated_signal(i)<val_max(i)) then
                        MINI(i,ind_max(i))=interpolated_signal(i)
val_max(i) = MAXVAL(MINI(i,:) ); ind_max(i:i) = MAXLOC( MINI(i,:) )
                    endif
                endif
                
 enddo !i
 ENDIF !CALC_CREDIBLE


! Build histogram of number of changepoints: k
            RETURN_INFO%n_changepoint_hist(k)=RETURN_INFO%n_changepoint_hist(k) + 1


!Do the histogram on change points
            do i = 1,k
                bb=bb+1
                RETURN_INFO%change_points(bb)=pt(i,1)
            enddo

    endif !if burn-in
    
    RETURN_INFO%convergence(s)=like  ! Convergence of the misfit
    
    ! Get the best model
    if (like<like_best) then
        pt_best = pt
        k_best = k
        endpt_best = endpt
        like_best = like
    endif
    
enddo ! the Sampling of the mcmc


! Compute the average
RETURN_INFO%AV(:)=RETURN_INFO%AV(:)/b


do i=1, discretise_size
! Compute the credible intervals
RETURN_INFO%sup(i) = MINVAL(MAXI(i,:) )
RETURN_INFO%inf(i) = MAXVAL(MINI(i,:) )

! Compute the mode
RETURN_INFO%MODE(i) = (0.5_8 + REAL(MAXLOC( discrete_history(i,:),DIM = 1)-1, KIND = 8))/NBINS * (I_MAX-I_MIN) + I_MIN

! Compute the median. Get the first instance of the count from the left being greater than half the total:
do j=1, NBINS
if( sum( discrete_history(i,1:j)) .GE. sum( discrete_history(i,1:NBINS))/2) then
RETURN_INFO%median(i) = (REAL(j-1, KIND = 8)+0.5_8)/NBINS * (I_MAX-I_MIN) + I_MIN
exit
endif
enddo

! compute a discretised average  - this was just a check to make sure that it agrees with the average above - and it does.
!RETURN_INFO%AV2(i) = 0.0_8
!do j=1, NBINS
!RETURN_INFO%AV2(i) = RETURN_INFO%AV2(i) + discrete_history(i,i) * ((REAL(j-1, KIND = 8)+0.5_8)/NBINS * (I_MAX-I_MIN) + I_MIN)
!enddo
!RETURN_INFO%AV2(i) = RETURN_INFO%AV2(i) / sum( discrete_history(i,1:NBINS) )
!RETURN_INFO%MODE(i) = 1.0_8 * MAXLOC( discrete_history(i,:), DIM = 1 )
enddo

! Calculate the "best" solution
CALL Find_linear_interpolated_values(k_best, x_min, x_max, pt_best, endpt_best, discretise_size, x, RETURN_INFO%best(1:discretise_size) )

! normalise marginal distributions
RETURN_INFO%MARGINAL_DENSITY_INTENSITY(:,:) = REAL(discrete_history(:,:), KIND = 8)/ sum( discrete_history(1,:) )

RETURN_INFO%MAX_NUMBER_CHANGE_POINTS_HISTORY = bb

IF( FREQ_WRITE_MODELS > 0) CLOSE(15)

RETURN
END SUBROUTINE RJMCMC

FUNCTION Integrated_likelihood( k, x_min, x_max, pt, endpt, NUM, AGE, DELTA_AGE, intensity, delta_intensity, LIKELIHOOD_CHOICE)
IMPLICIT NONE
REAL( KIND = 8) :: Integrated_likelihood, val(1:1)
REAL( KIND = 8) :: x_max, x_min, pt(:,:), endpt(:), age(:), DELTA_age(:), delta_intensity(:), intensity(:)
INTEGER :: K, NUM, i,j, LIKELIHOOD_CHOICE, NUMBER_SEGMENTS,q

REAL( KIND = 8) :: interpolated_signal(NUM), START_POSITION(1:2,MAX(1,k+1)), END_POSITION(1:2,MAX(1,k+1)), LINE_LENGTHS(MAX(1,k+1))
REAL( KIND = 8) :: THETA_BAR, SIGMA_THETA, A, B, T2, T1, like
LOGICAL :: SKIP_OUT

!delta_age(:) = 0.01_8

IF( LIKELIHOOD_CHOICE .eq. 0) THEN ! assume midpoint ages are exact, use standard normal likelihood

CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, NUM, age, interpolated_signal)
Integrated_likelihood = 0.0_8
DO i=1, NUM
Integrated_likelihood=Integrated_likelihood+(Intensity(i) - interpolated_signal(i))**2/(2.0_8 * delta_intensity(i)**2)
ENDDO

ELSE ! compute integrated likelihood
Integrated_likelihood = 0.0_8

! test
!IF(k .eq. 1) then
!endpt(1) = 50.0_8
!endpt(2) = 70.0_8
!
!pt(1,2) = 0.5*(endpt(2)+endpt(1))
!pt(1,1) = 0.5 * (x_max + x_min)
!delta_age(:) = 0.1
!endif
!if( k .eq. 0) then
!endpt(1) = 50.0_8
!endpt(2) = 70.0_8
!delta_age(:) = 0.1
!endif
!

!PRINT*, endpt
DO I = 1, NUM !loop over data

! These are the choices:
! a) k is 0. Then there are no internal vertices, and we can use the age bounds themselves
! b) k is > 0, and  age(i) + delta(i) is not greater than all age vertices. Then there is at least one age vertex older than age(i) + delta(i)

START_POSITION(:,:) = 0.0_8
END_POSITION(:,:) = 0.0_8
! Find the start and end points of each segment that falls within the uniform age interval
NUMBER_SEGMENTS = 1
! The start position of the first segment will be at the very start of the uniform age interval
START_POSITION(1,1) = age(I) - delta_age(i)
CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, 1, age(i:i) - delta_age(i:i), val(1:1))
START_POSITION(2,1) = val(1)


IF( k .eq. 0) THEN
END_POSITION(1,NUMBER_SEGMENTS) = age(i) + delta_age(i)
CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, 1, age(i:i) + delta_age(i:i), val(1:1))
END_POSITION(2,NUMBER_SEGMENTS) = val(1)

ELSE
SKIP_OUT = .FALSE.
! Find the first internal vertex that is greater than the lower age bound
DO j = 1, K
 IF( pt(j,1) > START_POSITION(1,NUMBER_SEGMENTS) .AND. pt(j,1) < age(i) + delta_age(i) ) THEN  !the vertex pt(j,1) is contained inside the interval
    END_POSITION(1,NUMBER_SEGMENTS) = pt(j,1)
!CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, 1, pt(j:j,1), val(1:1))
    END_POSITION(2,NUMBER_SEGMENTS) = pt(j,2)
    NUMBER_SEGMENTS = NUMBER_SEGMENTS + 1
    START_POSITION(1,NUMBER_SEGMENTS) = END_POSITION(1,NUMBER_SEGMENTS-1)
    START_POSITION(2,NUMBER_SEGMENTS) = END_POSITION(2,NUMBER_SEGMENTS-1)
 ELSE IF( pt(j,1) > START_POSITION(1,NUMBER_SEGMENTS) .AND. pt(j,1) .GE. age(i) + delta_age(i) ) THEN  !we simply end the vertex and stop
    END_POSITION(1,NUMBER_SEGMENTS) = age(i) + delta_age(i)
CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, 1, age(i:i) + delta_age(i:i), val(1:1))
END_POSITION(2,NUMBER_SEGMENTS) = val(1)
SKIP_OUT = .TRUE.
   EXIT
  ENDIF

ENDDO !J

! If it gets here, and SKIP_OUT is not TRUE then its run out of points to check. This means that there are no internal vertices with an age greater than age + delta_age
! End the segment
IF(SKIP_OUT .eqv. .FALSE.) THEN
END_POSITION(1,NUMBER_SEGMENTS) = age(i) + delta_age(i)
CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, 1, age(i:i) + delta_age(i:i), val(1:1))
END_POSITION(2,NUMBER_SEGMENTS) = val(1)
ENDIF

ENDIF !is k zero?



DO J = 1, NUMBER_SEGMENTS
LINE_LENGTHS(J) = SQRT( (END_POSITION(1,J) - START_POSITION(1,J))**2 + (END_POSITION(2,J) - START_POSITION(2,J))**2 )
ENDDO
LINE_LENGTHS(1:NUMBER_SEGMENTS) = LINE_LENGTHS(1:NUMBER_SEGMENTS) / SUM( LINE_LENGTHS(1:NUMBER_SEGMENTS) )


like = 0.0_8
DO J = 1, NUMBER_SEGMENTS
IF( LINE_LENGTHS(J) .eq. 0) THEN
PRINT*, 'FATAL ERROR: SAMPLE ', I, ' SEGMENT ', J, ' HAS LINE LENGTH ZERO'
PRINT*, ' AGE : ', AGE(I) - delta_age(I), AGE(I) + delta_age(I)
DO q = 1, J
PRINT*, 'X positions :', START_POSITION(1,q), END_POSITION(1,q)
PRINT*, 'Y positions :', START_POSITION(2,q), END_POSITION(2,q)
ENDDO
STOP
ENDIF

A = INTENSITY(I) - START_POSITION(2,J)
B = END_POSITION(2,J) - START_POSITION(2,J)
IF( ABS(B) .LT. 1e-10) THEN
PRINT*, 'FATAL ERROR: SAMPLE ', I, ' SEGMENT ', J, ' HAS B VALUE LESS THAN 1E-10 OF ', B
STOP
ENDIF
THETA_BAR = A/B
SIGMA_THETA = delta_intensity(I) / b
T2 = (1.0_8 - THETA_BAR)/sqrt(2.0_8)/SIGMA_THETA
T1 = -THETA_BAR/sqrt(2.0_8)/SIGMA_THETA
like = like + LINE_LENGTHS(J) / B * (erf(T2) - erf(T1))
!PRINT*, like

!IF( like .eq. 0) PRINT*, LINE_LENGTHS(J), A, B, THETA_BAR, SIGMA_THETA, T2, T1, erf(T2), erf(T1)
IF(like .eq. 0. .and. 1 .eq. 0) THEN
!PRINT*, I, J, LINE_LENGTHS(J), intensity(I), age(I),x_min, A, B, THETA_BAR, SIGMA_THETA, T2, T1, erf(T2), erf(T1)
DO q = 1, NUMBER_SEGMENTS
PRINT*, 'X positions :', START_POSITION(1,q), END_POSITION(1,q)
PRINT*, 'Y positions :', START_POSITION(2,q), END_POSITION(2,q)
ENDDO
ENDIF
!PRINT*, A,B, SIGMA_THETA,THETA_BAR, T1, T2, erf(T2) - erf(T1)
!PRINT*, ''
!PRINT*, erf(T1), erf(T2), erfc(T1), erfc(T2)
ENDDO !J

like = like / 2.0_8 / (2.0_8 * delta_age(i))

! If T1 and T2 are large, then erf(T2) - erf(T1) is computationally zero. In this event (which only happens if the model is nowhere close to
! representing the data) then we replace like by a small value:
IF( like .eq. 0.0_8) like = 1.0e-50_8


Integrated_likelihood = Integrated_likelihood - log(like)

!compare likelihoods:
!CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, NUM, age, interpolated_signal)
!WRITE(6,'(i,4(ES13.4,X))') i, like, exp( -(Intensity(i) - interpolated_signal(i))**2/(2.0_8 * delta_intensity(i)**2)) / sqrt(2*3.141_8) / delta_intensity(i) / (2.0_8 * delta_age(i)),  START_POSITION(2,1), END_POSITION(2,1)

! Large T2, T1 may require large argument approximations for erf.

ENDDO !I
!PRINT*, Integrated_likelihood


!PRINT*,' NOT SETUP YET'
!STOP
ENDIF

RETURN
END FUNCTION Integrated_likelihood





SUBROUTINE Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, nd, grid, interpolated_signal)
IMPLICIT none
INTEGER :: K, nd
REAL( KIND = 8) ::linear_description_time(1:k+2),linear_description_intensity(1:k+2),interpolated_signal(1:nd)
REAL( KIND = 8) :: x_max, x_min, pt(:,:), endpt(:), grid(:)
INTENT(OUT) :: interpolated_signal

linear_description_time(1) = x_min
if(k > 0) linear_description_time(2:k+1) = pt(1:k,1)
linear_description_time(k+2) = x_max

linear_description_intensity(1) = endpt(1)
if( k>0) linear_description_intensity(2:k+1) = pt(1:k,2)
linear_description_intensity(k+2) = endpt(2)




call interp_linear( 1, k+2, linear_description_time, linear_description_intensity, nd, &
grid(1:nd), interpolated_signal )

return
END SUBROUTINE Find_linear_interpolated_values

REAL( KIND = 8) FUNCTION randn()
IMPLICIT none
REAL( KIND = 8):: RANDOM_NUMBERS(2)

CALL RANDOM_NUMBER( RANDOM_NUMBERS(1:2) )
! Use Box_Muller transform
RANDN = SQRT( -2.0_8 * LOG( RANDOM_NUMBERS(1) ) ) * COS( 2.0_8 * Pi * RANDOM_NUMBERS(2) )
!  ANOTHER IS = SQRT( -2.0_LONG_REAL * LOG( RANDOM_NUMBERS(1) )) * SIN( 2.0_LONG_REAL * Pi * RANDOM_NUMBERS(2) )
RETURN
END FUNCTION

subroutine interp_linear ( m, data_num, t_data, p_data, interp_num, &
t_interp, p_interp )

!*****************************************************************************80
!
!! INTERP_LINEAR: piecewise linear interpolation to a curve in M dimensions.
!
!  Discussion:
!
!    From a space of M dimensions, we are given a sequence of
!    DATA_NUM points, which are presumed to be successive samples
!    from a curve of points P.
!
!    We are also given a parameterization of this data, that is,
!    an associated sequence of DATA_NUM values of a variable T.
!    The values of T are assumed to be strictly increasing.
!
!    Thus, we have a sequence of values P(T), where T is a scalar,
!    and each value of P is of dimension M.
!
!    We are then given INTERP_NUM values of T, for which values P
!    are to be produced, by linear interpolation of the data we are given.
!
!    Note that the user may request extrapolation.  This occurs whenever
!    a T_INTERP value is less than the minimum T_DATA or greater than the
!    maximum T_DATA.  In that case, linear extrapolation is used.
!
!  Licensing:
!
!    This code is distributed under the GNU LGPL license.
!
!  Modified:
!
!    03 December 2007
!
!  Author:
!
!    John Burkardt
!
!  Parameters:
!
!    Input, integer ( kind = 4 ) M, the spatial dimension.
!
!    Input, integer ( kind = 4 ) DATA_NUM, the number of data points.
!
!    Input, real ( kind = 8 ) T_DATA(DATA_NUM), the value of the
!    independent variable at the sample points.  The values of T_DATA
!    must be strictly increasing.
!
!    Input, real ( kind = 8 ) P_DATA(M,DATA_NUM), the value of the
!    dependent variables at the sample points.
!
!    Input, integer ( kind = 4 ) INTERP_NUM, the number of points
!    at which interpolation is to be done.
!
!    Input, real ( kind = 8 ) T_INTERP(INTERP_NUM), the value of the
!    independent variable at the interpolation points.
!
!    Output, real ( kind = 8 ) P_INTERP(M,DATA_NUM), the interpolated
!    values of the dependent variables at the interpolation points.
!
implicit none

integer ( kind = 4 ) data_num
integer ( kind = 4 ) m
integer ( kind = 4 ) interp_num

integer ( kind = 4 ) interp
integer ( kind = 4 ) left
real ( kind = 8 ) p_data(m,data_num)
real ( kind = 8 ) p_interp(m,interp_num)
integer ( kind = 4 ) right
real ( kind = 8 ) t
real ( kind = 8 ) t_data(data_num)
real ( kind = 8 ) t_interp(interp_num)

if ( .not. r8vec_ascends_strictly ( data_num, t_data ) ) then
write ( *, '(a)' ) ' '
write ( *, '(a)' ) 'INTERP_LINEAR - Fatal error!'
write ( *, '(a)' ) &
'  Independent variable array T_DATA is not strictly increasing. T_DATA WRITTEN TO FORT.99'
WRITE(99,*) t_data
stop 1
end if

do interp = 1, interp_num

t = t_interp(interp)
!
!  Find the interval [ TDATA(LEFT), TDATA(RIGHT) ] that contains, or is
!  nearest to, TVAL.
!
call r8vec_bracket ( data_num, t_data, t, left, right )

p_interp(1:m,interp) = &
( ( t_data(right) - t                ) * p_data(1:m,left)   &
+ (                 t - t_data(left) ) * p_data(1:m,right) ) &
/ ( t_data(right)     - t_data(left) )

end do

return
end subroutine interp_linear

function r8vec_ascends_strictly ( n, x )

!*****************************************************************************80
!
!! R8VEC_ASCENDS_STRICTLY determines if an R8VEC is strictly ascending.
!
!  Discussion:
!
!    An R8VEC is a vector of R8 values.
!
!    Notice the effect of entry number 6 in the following results:
!
!      X = ( -8.1, 1.3, 2.2, 3.4, 7.5, 7.4, 9.8 )
!      Y = ( -8.1, 1.3, 2.2, 3.4, 7.5, 7.5, 9.8 )
!      Z = ( -8.1, 1.3, 2.2, 3.4, 7.5, 7.6, 9.8 )
!
!      R8VEC_ASCENDS_STRICTLY ( X ) = FALSE
!      R8VEC_ASCENDS_STRICTLY ( Y ) = FALSE
!      R8VEC_ASCENDS_STRICTLY ( Z ) = TRUE
!
!  Licensing:
!
!    This code is distributed under the GNU LGPL license.
!
!  Modified:
!
!    03 December 2007
!
!  Author:
!
!    John Burkardt
!
!  Parameters:
!
!    Input, integer ( kind = 4 ) N, the size of the array.
!
!    Input, real ( kind = 8 ) X(N), the array to be examined.
!
!    Output, logical R8VEC_ASCENDS_STRICTLY, is TRUE if the
!    entries of X strictly ascend.
!
implicit none

integer ( kind = 4 ) n

integer ( kind = 4 ) i
logical r8vec_ascends_strictly
real ( kind = 8 ) x(n)

do i = 1, n - 1
if ( x(i+1) <= x(i) ) then
r8vec_ascends_strictly = .false.
return
end if
end do

r8vec_ascends_strictly = .true.

return
end function r8vec_ascends_strictly


subroutine r8vec_bracket ( n, x, xval, left, right )

!*****************************************************************************80
!
!! R8VEC_BRACKET searches a sorted R8VEC for successive brackets of a value.
!
!  Discussion:
!
!    An R8VEC is an array of double precision real values.
!
!    If the values in the vector are thought of as defining intervals
!    on the real line, then this routine searches for the interval
!    nearest to or containing the given value.
!
!  Licensing:
!
!    This code is distributed under the GNU LGPL license.
!
!  Modified:
!
!    06 April 1999
!
!  Author:
!
!    John Burkardt
!
!  Parameters:
!
!    Input, integer ( kind = 4 ) N, length of input array.
!
!    Input, real ( kind = 8 ) X(N), an array sorted into ascending order.
!
!    Input, real ( kind = 8 ) XVAL, a value to be bracketed.
!
!    Output, integer ( kind = 4 ) LEFT, RIGHT, the results of the search.
!    Either:
!      XVAL < X(1), when LEFT = 1, RIGHT = 2;
!      X(N) < XVAL, when LEFT = N-1, RIGHT = N;
!    or
!      X(LEFT) <= XVAL <= X(RIGHT).
!
implicit none

integer ( kind = 4 ) n

integer ( kind = 4 ) i
integer ( kind = 4 ) left
integer ( kind = 4 ) right
real ( kind = 8 ) x(n)
real ( kind = 8 ) xval

do i = 2, n - 1

if ( xval < x(i) ) then
left = i - 1
right = i
return
end if

end do

left = n - 1
right = n

return
end subroutine r8vec_bracket

FUNCTION CHECK_DIFFERENT( vector )
! returns 0 if any two elements are the same, 1 if they are all different.
IMPLICIT NONE
REAL( KIND = 8) :: vector(:), vector2(1:size(vector))
INTEGER :: CHECK_DIFFERENT, ORDER(1: SIZE(VECTOR)), I

vector2 = vector
CALL quick_sort(vector2, order)

CHECK_DIFFERENT = 0
DO I = 1, SIZE(VECTOR2)-1
IF( VECTOR2(I) .eq. VECTOR2(I+1)) THEN
CHECK_DIFFERENT = 1
EXIT
ENDIF
ENDDO

END FUNCTION CHECK_DIFFERENT

function to_upper(strIn) result(strOut)
! Adapted from http://www.star.le.ac.uk/~cgp/fortran.html (25 May 2012)
! Original author: Clive Page

implicit none

character(len=*), intent(in) :: strIn
character(len=len(strIn)) :: strOut
integer :: i,j

do i = 1, len(strIn)
j = iachar(strIn(i:i))
if (j>= iachar("a") .and. j<=iachar("z") ) then
strOut(i:i) = achar(iachar(strIn(i:i))-32)
else
strOut(i:i) = strIn(i:i)
end if
end do

end function to_upper

END MODULE IL_RJMCMC

