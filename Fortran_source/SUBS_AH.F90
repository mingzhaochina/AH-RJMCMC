MODULE AGE_HYPERPARAMETER_RJMCMC
!
!  This program defines the RJMCMC method with uncertain ages.
!  The model is the set of all change points and intensity values (both at the internal change points and the end points)
!  The joint posterior distributions are output (according to the user-specific frequency) as are the marginalised age posteriors.
!  This marginalisation is performed on the fly by binning using a total of NBINS bins.

!  The outputs are returned in the structure RETURN_INFO
!
!  Phil Livermore, Dec 2016
! 
!
! For checking purposes, the subroutine runs in two modes:
! RUNNING_MODE = 1   This is the usual mode of operation
! RUNNING_MODE <> 1  This sets the likelihood to be unity, so that the prior distributions are sampled - these can be checked against the assumed distributions.

USE SORT

TYPE RETURN_INFO_STRUCTURE
REAL( KIND = 8), ALLOCATABLE, DIMENSION(:) :: AV, BEST, SUP, INF, MEDIAN, MODE, CHANGE_POINTS, CONVERGENCE
REAL( KIND = 8), ALLOCATABLE :: MARGINAL_AGES(:,:), MARGINAL_DENSITY_INTENSITY(:,:)
INTEGER :: MAX_NUMBER_CHANGE_POINTS_HISTORY
INTEGER, ALLOCATABLE :: n_changepoint_hist(:)
END TYPE RETURN_INFO_STRUCTURE



REAL( KIND = 8), PARAMETER :: PI = 3.14159265358979_8
INTEGER :: RUNNING_MODE

CONTAINS
SUBROUTINE RJMCMC(burn_in, NUM_DATA, MIDPOINT_AGE, DELTA_AGE, INTENSITY, I_SD, STRATIFIED, NSAMPLE, I_MIN, I_MAX, X_MIN, X_MAX, K_MIN, K_MAX, SIGMA_MOVE, sigma_change_value, sigma_birth, age_frac, discretise_size, SHOW, THIN, NBINS, RETURN_INFO, CALC_CREDIBLE, FREQ_WRITE_MODELS, WRITE_MODEL_FILE_NAME, FREQ_WRITE_JOINT_DISTRIB, AGE_DISTRIBUTION, credible, Outputs_directory)


IMPLICIT NONE
TYPE (RETURN_INFO_STRUCTURE) :: RETURN_INFO
CHARACTER(*) :: Outputs_directory
INTEGER :: I, K, BURN_IN, NSAMPLE, K_INIT, K_MAX, K_MIN, K_MAX_ARRAYBOUND, discretise_size, show, thin, num, J, &
           NUM_DATA, K_MAX_ARRAY_BOUND, s, birth, death, move, ind, k_prop, accept, k_best, out, &
           NBINS, BIN_INDEX, IS_DIFF, CHANGE_AGE, CHANGE_value, i_age, FREQ_WRITE_MODELS, IOS, FREQ_WRITE_JOINT_DISTRIB, SAMPLE_INDEX_JOINT_DISTRIBUTION
REAL( KIND = 8) :: D_MIN, D_MAX, I_MAX, I_MIN, sigma_move, sigma_change_value, sigma_birth, like_prop, prob, INT_J, pt_death(2), X_MIN, X_MAX, U, RAND(2), alpha
CHARACTER(300) :: WRITE_MODEL_FILE_NAME, format_descriptor, FILENAME
CHARACTER(1) :: AGE_DISTRIBUTION

INTEGER, ALLOCATABLE :: ORDER(:)
REAL( KIND = 8) :: ENDPT_BEST(2), age_frac, credible

INTEGER :: b, bb, AB, AD, PD, PB, ACV, PCV, AP, PP, PA, AA, num_age_changes, STRATIFIED(:),misfit_count
REAL( KIND = 8) :: MIDPOINT_AGE(:), DELTA_AGE(:), Intensity(:), I_sd(:), ENDPT(2), ENDPT_PROP(2), like, like_best, like_init
REAL( KIND = 8), ALLOCATABLE :: VAL_MIN(:), VAL_MAX(:),   MINI(:,:), MAXI(:,:), PT(:,:), PT_PROP(:,:), interpolated_signal(:), X(:), PT_NEW(:), PT_BEST(:,:), age(:), age_prop(:)
INTEGER, ALLOCATABLE, DIMENSION(:) :: IND_MIN, IND_MAX
INTEGER, ALLOCATABLE :: discrete_history(:,:)
LOGICAL :: CALC_CREDIBLE, AGES_FIXED

!needed to write to files in row format:
WRITE(format_descriptor,'(A,i3,A)') '(',discretise_size,'F14.4)'

! Other parameters are fixed here

k_max_array_bound = k_max + 1;

! The prior on the vertex position is defined by the end points of the model vector itself.
D_min = X_min
D_max = X_max

NUM=ceiling((nsample-burn_in)*(100.0_8-credible)/200.0_8/thin) ! number of collected samples for credible intervals

ALLOCATE( X(1: discretise_size) )
    DO I=1, discretise_size
    X(I) = X_MIN + REAL(I-1, KIND = 8)/REAL(discretise_size-1, KIND = 8) * (X_MAX - X_MIN)
    ENDDO

ALLOCATE( val_min(1: discretise_size), val_max(1: discretise_size), ind_min(1: discretise_size), ind_max(1: discretise_size),  &
MINI(1: discretise_size, 1:NUM), MAXI(1: discretise_size, 1:NUM), age(1: num_data), age_prop(1:num_data), discrete_history(1:discretise_size,1:NBINS) )

ALLOCATE( pt(1:k_max_array_bound,2), pt_prop(1:k_max_array_bound,2) , pt_best(1:k_max_array_bound,2) )

! Setup file IO for (a) writing model files and (b) writing the joint distribution data

IF( FREQ_WRITE_MODELS > 0) then
OPEN(15, FILE = TRIM(Outputs_directory)//'/'//TRIM(WRITE_MODEL_FILE_NAME), STATUS = 'REPLACE', FORM = 'FORMATTED', IOSTAT = IOS)
  IF( IOS .NE. 0) THEN
    PRINT*, 'CANNOT OPEN FILE FOR MODEL WRITING ', TRIM(Outputs_directory)//'/'//TRIM(WRITE_MODEL_FILE_NAME)
    STOP
  ENDIF
WRITE(15,*) discretise_size, floor(REAL(nsample-burn_in, KIND = 8)/thin/FREQ_WRITE_MODELS)
WRITE(15,format_descriptor) X(1:discretise_size)
ENDIF


IF( FREQ_WRITE_JOINT_DISTRIB > 0) then
CALL SYSTEM('mkdir -p '//TRIM(Outputs_directory)//'/Joint_distribution_data')

DO i=1,NUM_DATA
WRITE(FILENAME,'(A,A,I4.4,A)') TRIM(Outputs_directory),'/Joint_distribution_data/Sample_',i,'.dat'
OPEN(30+i, FILE = FILENAME, STATUS = 'REPLACE', FORM = 'FORMATTED', IOSTAT = IOS)


IF( IOS .NE. 0) THEN
PRINT*, 'CANNOT OPEN FILES FOR WRITING JOINT_DISTRIBUTION DATA'
STOP
ENDIF

ENDDO
ENDIF


k_best = -10

val_min(:) = 0.
val_max(:) = 0.
ind_min(:) = 0
ind_max(:) = 0
MINI(:,:) = 0.
MAXI(:,:) = 0.
pt(:,:) = 0.
b = 0 
misfit_count=0
bb = 0
AB=0
AD=0
PB=0
PD=0
ACV=0
PCV=0
AP=0
PP=0
PA = 0
AA = 0
RETURN_INFO%best(:) = 0.0_8
RETURN_INFO%AV(:) = 0.0_8
RETURN_INFO%change_points(:) = 0.0_8
RETURN_INFO%convergence(:) = 0.0_8
RETURN_INFO%sup(:) = 0.0_8
RETURN_INFO%inf(:) = 0.0_8
RETURN_INFO%MARGINAL_AGES(:,:) = 0.0_8
RETURN_INFO%n_changepoint_hist(:) = 0
discrete_history(:,:) = 0

IF(MINVAL( I_SD(1:NUM_DATA)) .eq. 0.0_8) THEN
PRINT*,'MIN INTENSITY ERROR IS 0, INCOMPATITBLE WITH ASSUMPTIONS BUILT INTO CODE'
STOP
ENDIF

AGES_FIXED = .FALSE.
IF(MINVAL( DELTA_AGE(1:NUM_DATA)) .eq. 0.0_8) THEN
PRINT*,'MIN AGE ERROR IS 0, ASSUMING AGES ARE FIXED'
AGES_FIXED = .TRUE.
ENDIF

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
! Initialize - Define randomly the first model of the chain
CALL RANDOM_NUMBER( RAND(1))
k_init = floor(RAND(1) * (K_max - K_min+1)) + k_min
k = k_init

!set the data ages to be the given nominal age (i.e. discount any age error). This is so datasets with stratification are valid for the initial model.
! If we randomised the ages, we'd have to check that stratification was satifisfied, and it could take a while before we find a valid model.

AGE(1:NUM_DATA) = MIDPOINT_AGE(1:NUM_DATA)

! Check to ensure that the stratification constraints (if any) are satisifed

IF( .NOT. CHECK_STRATIFICATION(AGE, STRATIFIED, NUM_DATA) ) THEN
PRINT*, 'INITIAL DATA SET IS NOT CONSISTENT WITH GIVEN STRATIFICATION CONSTRAINTS'
STOP
ENDIF

!DO i=1, NUM_DATA
!IF( AGE_DISTRIBUTION(1:1) == 'U' .OR. AGE_DISTRIBUTION(1:1) == 'u') THEN
!CALL RANDOM_NUMBER( RAND(1))
!AGE(i) = MIDPOINT_AGE(i) !+ 2.0_8 * (rand(1)-0.5_8) * DELTA_AGE(i)
!ELSE
!AGE(i) = MIDPOINT_AGE(i) !+ randn() * DELTA_AGE(i)
!ENDIF

! Check to make sure that the ages do not extend past the model ends. For then we can't compute the likelihood.
! This only happens with normally distributed ages, for which the age can be any value with prob > 0.
DO i=1, NUM_DATA
IF( AGE(i) < D_MIN) AGE(I) = D_MIN
IF( AGE(I) > D_MAX) AGE(I) = D_MAX
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

like=0;
! interpolate. First, assemble the complete linear description
ALLOCATE( interpolated_signal(1:max(NUM_DATA,discretise_size)) ) !generic output space for interpolation.
CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, NUM_DATA, age, interpolated_signal)

IF( RUNNING_MODE .eq. 1) THEN
do i=1,NUM_DATA
like=like+(Intensity(i) - interpolated_signal(i))**2/(2.0_8 * I_sd(i)**2)
enddo
else
like = 1.0_8
endif

like_best=like
like_init=like


!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
!%%%%%%%%%%%%%%%%% START RJ-MCMC SAMPLING %%%%%%%%%%%%%%%%%
!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

do s=1,nsample

! Print statistics of the chain.
    
    if (mod(s,show)==0 .AND. s>burn_in) then

        write(6,'(A,i8,A,i3,6(A,F6.1))' ) 'Samples: ',s, ' Vertices: ',k, ' Acceptance: change F ', 100.0*ACV/PCV, ' change age ', 100.0*AP/PP,  ' birth ', 100.0*AB/PB,' death ',100.0*AD/PD  ,' resample ages ', 100.0*AA/PA, ' likelihood ', like

    endif
     
    
    birth=0
    move=0
    death=0
    change_age = 0
    change_value = 0

    age_prop = age
    pt_prop=pt
    endpt_prop = endpt
    like_prop = like
    k_prop = k
    prob = 1.0
    out = 1
    !----------------------------------------------------------------------
    ! Every 3rd iteration, propose a new value
    if (mod(s,3)==0) then ! Change Value
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
        ! Every 3rd iteration iteration change the vertex positions
    elseif (mod(s,3)==1) then ! Change position
        CALL RANDOM_NUMBER( RAND(1))
        u=RAND(1) !Chose randomly between 3 different types of moves
        if (u<0.333) then ! BIRTH ++++++++++++++++++++++++++++++++++++++
            birth=1
            if (s>burn_in) PB=PB+1

            k_prop = k+1
            CALL RANDOM_NUMBER( RAND(1))
            pt_prop(k+1,1)=D_min+RAND(1)*(D_max-D_min)

! check that all the time-points are different:
DO WHILE ( CHECK_DIFFERENT(X_MIN, X_MAX, pt_prop(1:k+1,1)) .EQ. 1)
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
                pt_prop(1:ind-1,1:2)=pt(1:ind-1,1:2)
                pt_prop(ind:k-1,1:2) = pt(ind+1:k,1:2)
                
                !GET prob
!interpolate to find magnitude of current state as needed by birth

CALL Find_linear_interpolated_values(k_prop, x_min, x_max, pt_prop, endpt_prop, 1, pt_death(1:1), interpolated_signal)


prob=1.0_8/(sigma_birth*sqrt(2.0_8*pi))  *  exp(-(interpolated_signal(1)-pt_death(2))**2/(2.0_8*sigma_birth**2))
                
            endif !if (out==1)

        else ! MOVE +++++++++++++++++++++++++++++++++++++++++++++++++++++++
            if (s>burn_in) PP=PP+1
            move=1
            k_prop = k
            CALL RANDOM_NUMBER( RAND(1:2))
            ind=ceiling(RAND(1)*k)
            if(k > 0) then ! If there are no points to move, then we can't move any
            pt_prop(ind,1) = pt(ind,1)+randn()*sigma_move         !Normal distribution of move destination
            else
            pt_prop = pt
            endif  ! 
            !pt_prop(ind,1) = D_MIN + RAND(2) * (D_MAX - D_MIN)  !Uniform distribution of move destination
            !Check BOUNDS
            out=1
            if ((pt_prop(ind,1)>D_max) .OR. (pt_prop(ind,1)<D_min))  out=0

!! check that all the time-points are different:
DO WHILE ( CHECK_DIFFERENT( X_MIN, X_MAX, pt_prop(1:k,1)) .EQ. 1)
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

else !every 3rd iteration change the ages
!select an age at random between 1 and NUM_DATA

! Never accept a model with perturbed ages if we assume the ages are fixed.
IF (AGES_FIXED) OUT = 0

if (s>burn_in) PA=PA+1
num_age_changes = floor(NUM_DATA/age_frac)
do j = 1, num_age_changes
CALL RANDOM_NUMBER( RAND(1))
i_age = floor( NUM_DATA * rand(1)) + 1
!if( i_age > NUM_DATA) then; print*, rand(1), i_age; stop; endif
IF( AGE_DISTRIBUTION(1:1) =='U' .OR. AGE_DISTRIBUTION(1:1) == 'u') THEN
CALL RANDOM_NUMBER( RAND(1))
age_prop(i_age) = MIDPOINT_AGE(i_age) + 2.0_8 * (rand(1)-0.5_8) * DELTA_AGE(i_age)
ELSE
age_prop(i_age) = MIDPOINT_AGE(i_age) + randn() * DELTA_AGE(i_age)
ENDIF
! Check to make sure that the ages do not extend past the model ends. For then we can't compute the likelihood.
IF( age_prop(i_age) < D_MIN) age_prop(i_age) = D_MIN
IF( age_prop(i_age) > D_MAX) age_prop(i_age) = D_MAX
!alter age model.
enddo
change_age = 1  !the acceptance probability is the same for MOVE

IF( .NOT. CHECK_STRATIFICATION(AGE_PROP, STRATIFIED, NUM_DATA) ) out = 0


ENDIF ! decide on what proposal to make
!----------------------------------------------------------------------
    

!%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    ! COMPUTE MISFIT OF THE PROPOSED MODEL
    ! If the proposed model is not outside the bounds of the uniform prior,
    ! compute its misfit : "like_prop"
    if (out==1)  then
    like_prop=0.0_8

CALL Find_linear_interpolated_values( k_prop, x_min, x_max, pt_prop, endpt_prop, NUM_DATA, age_prop, interpolated_signal)

IF( RUNNING_MODE .eq. 1) THEN
do i=1,NUM_DATA
like_prop=like_prop+(Intensity(i) - interpolated_signal(i))**2/(2.0_8 * I_sd(i)**2)
enddo
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
                elseif( change_age .eq. 1) then
                    AA = AA + 1
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

IF( FREQ_WRITE_JOINT_DISTRIB > 0) THEN
IF( s>burn_in .AND. mod(s-burn_in,thin * FREQ_WRITE_JOINT_DISTRIB) == 0) THEN

call Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, discretise_size, age(1:NUM_DATA), interpolated_signal(1:NUM_DATA) )
Do i=1,NUM_DATA
WRITE(30+i,*) REAL(age(i), KIND = 4), REAL(interpolated_signal(i),KIND = 4)
ENDDO

ENDIF
ENDIF


    CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, discretise_size, x(1:discretise_size), interpolated_signal)
  
    IF( FREQ_WRITE_MODELS > 0) then
    if( s>burn_in .AND. mod(s-burn_in,thin * FREQ_WRITE_MODELS) == 0) WRITE(15,'(F10.3)') (interpolated_signal(i),i=1, discretise_size)
    ENDIF


! CALL Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, discretise_size, x(1:discretise_size), interpolated_signal)

! DO THE AVERAGE
RETURN_INFO%AV(:)=RETURN_INFO%AV(:)+interpolated_signal(1:discretise_size)


! build marginal distribution for ages:

DO i=1,NUM_DATA

IF( AGES_FIXED) THEN
    BIN_INDEX = 1
ELSE

IF( AGE_DISTRIBUTION(1:1) == 'U' .OR. AGE_DISTRIBUTION(1:1) == 'u') THEN
BIN_INDEX = FLOOR( (age(i)-(MIDPOINT_AGE(i)-DELTA_AGE(i)))/DELTA_AGE(i)/2.0_8 * NBINS ) + 1
ELSE
! For normally distributed ages, bin centred on mean with a 2*standard deviation range each side.
! Should a value fall outside this range, then simply add to either the 1st or last bin.
BIN_INDEX = FLOOR( (age(i)-(MIDPOINT_AGE(i)-2.0_8 * DELTA_AGE(i)))/DELTA_AGE(i)/4.0_8 * NBINS ) + 1
IF( BIN_INDEX < 1) BIN_INDEX = 1
IF( BIN_INDEX > NBINS ) BIN_INDEX = NBINS
ENDIF
if(BIN_INDEX < 0) then; print*, 'BIN_INDEX < 0', i, age(i), MIDPOINT_AGE(i), DELTA_AGE(i), nbins; stop; endif
RETURN_INFO%MARGINAL_AGES(BIN_INDEX,i) = RETURN_INFO%MARGINAL_AGES(BIN_INDEX,i) + 1
ENDIF

enddo


! build marginal intensity density
DO i=1,discretise_size
BIN_INDEX = FLOOR( (interpolated_signal(i)-I_MIN)/REAL(I_MAX-I_MIN, KIND = 8) * NBINS ) + 1
IF( BIN_INDEX < 0 .OR. BIN_INDEX > NBINS) THEN
PRINT*, 'FATAL ERROR, BIN_INDEX IS OUT OF RANGE'
PRINT*, ' MODEL POINT ', I, ' VALUE ',interpolated_signal(i)
PRINT*, 'INTENSITY MIN/MAX ', I_MIN, I_MAX
STOP
ENDIF
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
    
 if ( mod(s,thin)==0) THEN 
 misfit_count = misfit_count + 1
 RETURN_INFO%convergence(misfit_count)=like  ! Convergence of the misfit
 endif

    
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
IF( k_best < 0) THEN
PRINT*, 'NO MINIMUM LIKELIHOOD SOLUTION FOUND'
RETURN_INFO%best(1:discretise_size) = 0.0_8
else
CALL Find_linear_interpolated_values(k_best, x_min, x_max, pt_best, endpt_best, discretise_size, x, RETURN_INFO%best(1:discretise_size) )
ENDIF

! normalise marginal distributions
RETURN_INFO%MARGINAL_DENSITY_INTENSITY(:,:) = REAL(discrete_history(:,:), KIND = 8)/ sum( discrete_history(1,:) )


DO I=1, NUM_DATA
RETURN_INFO%MARGINAL_AGES(:,i) = RETURN_INFO%MARGINAL_AGES(:,i) / SUM( RETURN_INFO%MARGINAL_AGES(:,i) )
enddo


RETURN_INFO%MAX_NUMBER_CHANGE_POINTS_HISTORY = bb

IF( FREQ_WRITE_MODELS > 0) CLOSE(15)


IF( FREQ_WRITE_JOINT_DISTRIB > 0) THEN

   DO i=1,NUM_DATA
   CLOSE(30+i)
   ENDDO

ENDIF



RETURN
END SUBROUTINE RJMCMC


SUBROUTINE Find_linear_interpolated_values( k, x_min, x_max, pt, endpt, nd, grid, interpolated_signal)
IMPLICIT none
INTEGER :: K, nd
REAL( KIND = 8) ::linear_description_time(1:k+2),linear_description_intensity(1:k+2),interpolated_signal(1:nd)
REAL( KIND = 8) :: x_max, x_min, pt(:,:), endpt(:), grid(:)
INTENT(OUT) :: interpolated_signal

linear_description_time(1) = x_min
linear_description_time(2:k+1) = pt(1:k,1)
linear_description_time(k+2) = x_max

linear_description_intensity(1) = endpt(1)
linear_description_intensity(2:k+1) = pt(1:k,2)
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

FUNCTION CHECK_DIFFERENT(x1, x2, vector )
! returns 0 if any two elements are the same, 1 if they are all different.
IMPLICIT NONE
REAL( KIND = 8) :: vector(:), vector2(1:size(vector)+2),x1,x2
INTEGER :: CHECK_DIFFERENT, ORDER(1: SIZE(VECTOR)+2), I

vector2(1:size(vector)) = vector(:)
vector2(size(vector)+1) = x1
vector2(size(vector)+2) = x2
CALL quick_sort(vector2, order)

CHECK_DIFFERENT = 0
DO I = 1, SIZE(VECTOR2)-1
IF( VECTOR2(I) .eq. VECTOR2(I+1)) THEN
CHECK_DIFFERENT = 1
EXIT
ENDIF
ENDDO

END FUNCTION CHECK_DIFFERENT

FUNCTION CHECK_STRATIFICATION(AGES, STRATIFICATION, N)
! checks the stratification - returns .TRUE. if everything if the ages are consistent with the stratification constraints, .FALSE. if not.
! Stratification is either 1 (the data is tied to neighbouring values with value 1) or 0 (untied).
IMPLICIT NONE
LOGICAL :: CHECK_STRATIFICATION
INTEGER :: N, i
INTEGER :: STRATIFICATION(1:N)
REAL( KIND = 8) :: AGES(1:N)
CHECK_STRATIFICATION = .TRUE.

IF( MAXVAL(STRATIFICATION) .EQ. 0) RETURN !early return if we don't need to check.

! check end point
IF( STRATIFICATION(1) .eq. 1 .AND. STRATIFICATION(2) .eq. 1 .AND. ages(1) > ages(2) ) THEN
CHECK_STRATIFICATION = .FALSE.
RETURN
ENDIF


DO I = 2, N-1
IF( STRATIFICATION(I) .eq. 1 .AND. STRATIFICATION(I+1) .eq. 1 .AND. (ages(i) > ages(i+1) ) ) THEN
CHECK_STRATIFICATION = .FALSE.
RETURN
ENDIF
ENDDO

RETURN
END FUNCTION CHECK_STRATIFICATION

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


END MODULE AGE_HYPERPARAMETER_RJMCMC

