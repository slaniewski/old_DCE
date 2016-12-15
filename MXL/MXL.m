function Results = MXL(INPUT,Results_old,EstimOpt,OptimOpt)


% save tmp_MXL
% return

global B_backup

tic

Results.bhat = [];
Results.R = [];
Results.R_out = {};
Results.stats = [];


%% Check data and inputs


if nargin < 3 % check no. of inputs
    error('Too few input arguments for MXL(INPUT,EstimOpt,OptimOpt)')
end

disp(' ');
disp('__________________________________________________________________________________________________________________');
disp(' ');

warning off MATLAB:mir_warning_maybe_uninitialized_temporary

format shortG;
format compact;

if any(INPUT.W ~= 1)
    cprintf('Black','Estimating '); cprintf('*Black','weighted '); cprintf('Black','MXL model...\n');
else
    disp('Estimating MXL model ...')
end

if isfield(EstimOpt,'FullCov') == 0;
    EstimOpt.FullCov = 0;
end
if ~isfield(EstimOpt,'WTP_space')
    EstimOpt.WTP_space = 0;
    EstimOpt.WTP_matrix = [];
elseif EstimOpt.WTP_space == 0;
    EstimOpt.WTP_matrix = [];
end

if EstimOpt.FullCov == 0
    disp('with non-correlated random parameters ...')
    if EstimOpt.WTP_space > 0
        disp('in WTP-space ...')
    else
        disp('in preference-space ...')
    end
else
    disp('with correlated random parameters ...')
    if EstimOpt.WTP_space > 0
        disp('in WTP-space ...')
    else
        disp('in preference-space ...')
    end
end

if isfield(EstimOpt, 'NLTVariables') && ~isempty(EstimOpt.NLTVariables)
    % 	disp('with non-linear transformation(s) ... ')
    EstimOpt.NLTVariables = EstimOpt.NLTVariables(:);
    EstimOpt.NVarNLT = length(unique(EstimOpt.NLTVariables));
    if ~ismember(unique(EstimOpt.NLTVariables),1:EstimOpt.NVarA)
        error('Incorrect non-linear variable(s) specification')
    end
    if isfield(EstimOpt, 'NLTType') == 0
        cprintf(rgb('DarkOrange'), 'WARNING: Assuming Box-Cox transformation \n')
        EstimOpt.NLTType = 1;
    elseif EstimOpt.NLTType == 1
        disp('with Box-Cox transformed variable(s).')
    elseif EstimOpt.NLTType == 2
        disp('with Yeo-Johnson transformed variable(s)')
    else
        error('Incorrect transformation type')
    end
    if EstimOpt.NLTType == 1
        if any(INPUT.Xa(:, EstimOpt.NLTVariables) < 0)
            cprintf(rgb('DarkOrange'), 'WARNING: Values of Box-Cox transformed variables < 0 \n')
        elseif any(INPUT.Xa(:, EstimOpt.NLTVariables) == 0) % not sure if this is stil necessary
            cprintf(rgb('DarkOrange'), 'WARNING: Values of Box-Cox transformed variables including zeros shifted by 0.00001 \n')
            for i = 1:EstimOpt.NVarNLT
                if any(INPUT.Xa(:, EstimOpt.NLTVariables(i)) == 0)
                    INPUT.Xa(:, EstimOpt.NLTVariables(i)) = INPUT.Xa(:, EstimOpt.NLTVariables(i)) + 0.00001;
                end
            end
        end
    end
else
    EstimOpt.NVarNLT = 0;
    EstimOpt.NLTVariables = [];
    EstimOpt.NLTType = [];
end

if isfield(EstimOpt,'Dist') == 0 || isempty(EstimOpt.Dist)
    EstimOpt.Dist = zeros(1,EstimOpt.NVarA+1);
    EstimOpt.Dist(1) = 1; % scale distributed log-normally (does not matter for MXL)
    if EstimOpt.WTP_space == 0
        cprintf(rgb('DarkOrange'), 'WARNING: distributions for random parameters not specified - assuming normality \n')
    else
        cprintf(rgb('DarkOrange'), 'WARNING: distributions for random parameters not specified - assuming normality (monetary parameters assumed log-normal) \n')
        EstimOpt.Dist(end-EstimOpt.WTP_space+1:end) = 1; % cost in WTP-space models log-normally distributed
    end
else
    if length(EstimOpt.Dist) == 1
        EstimOpt.Dist = EstimOpt.Dist.*ones(1,EstimOpt.NVarA+1);
    elseif length(EstimOpt.Dist) == 1 + EstimOpt.NVarA
        EstimOpt.Dist = EstimOpt.Dist(:)';
    else
        error('Incorrect no. of random parameters'' distributions provided')
    end
end
if isfield(EstimOpt, 'Triang') == 0 || length(EstimOpt.Triang) ~= sum(EstimOpt.Dist(2:end) == 3,2) % Needed only if any parameter has triangular distribution
    EstimOpt.Triang = zeros(1, sum(EstimOpt.Dist(2:end) == 3,2));
elseif length(EstimOpt.Triang) == 1
    EstimOpt.Triang = EstimOpt.Triang*ones(1, sum(EstimOpt.Dist(2:end) == 3,2));
else
    EstimOpt.Triang = EstimOpt.Triang(:)';
end

EstimOpt.Johnson = sum(EstimOpt.Dist(2:end) >= 5);

if (sum(EstimOpt.Dist(2:end) >=3 & EstimOpt.Dist(2:end) <=5) > 0 && any(find(EstimOpt.Dist(2:end) >=3 & EstimOpt.Dist(2:end) <=5) > sum(EstimOpt.Dist(2:end) >=3 & EstimOpt.Dist(2:end) <=5))) && EstimOpt.FullCov == 1
    cprintf(rgb('DarkOrange'), 'WARNING: It is recommended to put variables with random parameters with Triangular/Weibull/Sinh-Arcsinh distribution first \n')
end

disp(['Random parameters distributions: ', num2str(EstimOpt.Dist(2:end)),' (-1 - constant, 0 - normal, 1 - lognormal, 2 - spike, 3 - Triangular, 4  - Weibull, 5 - Sinh-Arcsinh, 6 - Johnson Sb, 7 - Johnson Su)'])

if EstimOpt.WTP_space > 0 && sum(EstimOpt.Dist(end-EstimOpt.WTP_space+1:end)==1) > 0 && any(mean(INPUT.Xa(:,end-EstimOpt.WTP_space+1:end)) >= 0)
    cprintf(rgb('DarkOrange'), 'WARNING: Cost attributes with log-normally distributed parameters should enter utility function with a ''-'' sign \n')
end

if isfield(INPUT, 'Xs') == 0
    INPUT.Xs = zeros(size(INPUT.Y,1),0);
end
EstimOpt.NVarS = size(INPUT.Xs,2); % Number of covariates of scale
if isfield(INPUT, 'Xm') == 0
    INPUT.Xm = zeros(size(INPUT.Y,1),0);
end
EstimOpt.NVarM = size(INPUT.Xm,2); % Number of covariates of means of random parameters

% This does not currently work:
if isfield(INPUT, 'Xv') == 0
    INPUT.Xv = zeros(size(INPUT.Y,1),0);
end
EstimOpt.NVarV = size(INPUT.Xv,2); % Number of covariates of variances of random parameters

if EstimOpt.WTP_space > 0
    if isfield(EstimOpt, 'WTP_matrix') == 0
        WTP_att = (EstimOpt.NVarA-EstimOpt.WTP_space)/EstimOpt.WTP_space;
        if rem(WTP_att,1) ~= 0
            error('EstimOpt.WTP_matrix associating attributes with cost parameters not provided')
        else
            if EstimOpt.WTP_space > 1
                disp(['EstimOpt.WTP_matrix associating attributes with cost parameters not provided - assuming equal shares for each of the ',num2str(EstimOpt.WTP_space),' monetary attributes'])
            end
            EstimOpt.WTP_matrix = EstimOpt.NVarA - EstimOpt.WTP_space + kron(1:EstimOpt.WTP_space,ones(1,WTP_att));
            %         tic; EstimOpt.WTP_matrix = 1:EstimOpt.WTP_space;...
            %         EstimOpt.WTP_matrix = EstimOpt.WTP_matrix(floor((0:size(EstimOpt.WTP_matrix,2)*WTP_att-1)/WTP_att)+1); toc
        end
        %     elseif ~isequal(size(EstimOpt.WTP_matrix),[EstimOpt.NVarA-EstimOpt.WTP_space,EstimOpt.WTP_space])
    elseif size(EstimOpt.WTP_matrix,2) ~= EstimOpt.NVarA - EstimOpt.WTP_space
        error('Dimensions of EstimOpt.WTP_matrix not correct - for each non-monetary attribute provide no. of attribute to multiply it with')
    else
        EstimOpt.WTP_matrix = EstimOpt.WTP_matrix(:)';
    end
end

if isfield(EstimOpt,'Scores') == 0 || isempty(EstimOpt.Scores)
    EstimOpt.Scores = 0;
end

if isfield(EstimOpt,'NamesA') == 0 || isempty(EstimOpt.NamesA) || length(EstimOpt.NamesA) ~= EstimOpt.NVarA
    EstimOpt.NamesA = (1:EstimOpt.NVarA)';
    EstimOpt.NamesA = cellstr(num2str(EstimOpt.NamesA));
elseif size(EstimOpt.NamesA,1) ~= EstimOpt.NVarA
    EstimOpt.NamesA = EstimOpt.NamesA';
end
if EstimOpt.NVarM > 0
    if isfield(EstimOpt,'NamesM') == 0 || isempty(EstimOpt.NamesM)|| length(EstimOpt.NamesM) ~= EstimOpt.NVarM
        EstimOpt.NamesM = (1:EstimOpt.NVarM)';
        EstimOpt.NamesM = cellstr(num2str(EstimOpt.NamesM));
    elseif size(EstimOpt.NamesM,1) ~= EstimOpt.NVarM
        EstimOpt.NamesM = EstimOpt.NamesM';
    end
end
if EstimOpt.NVarS > 0
    if isfield(EstimOpt,'NamesS') == 0 || isempty(EstimOpt.NamesS) || length(EstimOpt.NamesS) ~= EstimOpt.NVarS
        EstimOpt.NamesS = (1:EstimOpt.NVarS)';
        EstimOpt.NamesS = cellstr(num2str(EstimOpt.NamesS));
    elseif size(EstimOpt.NamesS,1) ~= EstimOpt.NVarS
        EstimOpt.NamesS = EstimOpt.NamesS';
    end
end


%% Starting values


if EstimOpt.FullCov == 0
    if exist('B_backup','var') && ~isempty(B_backup) && size(B_backup,1) == EstimOpt.NVarA*2 + EstimOpt.NVarM*EstimOpt.NVarA + EstimOpt.NVarS + EstimOpt.NVarNLT + 2*EstimOpt.Johnson
        b0 = B_backup(:);
        disp('Using the starting values from Backup')
    elseif isfield(Results_old,'MXL_d') && isfield(Results_old.MXL_d,'b0') % starting values provided
        Results_old.MXL_d.b0_old = Results_old.MXL_d.b0(:);
        Results_old.MXL_d = rmfield(Results_old.MXL_d,'b0');
        if length(Results_old.MXL_d.b0_old) ~= EstimOpt.NVarA*2 + EstimOpt.NVarM*EstimOpt.NVarA + EstimOpt.NVarS + EstimOpt.NVarNLT + 2*EstimOpt.Johnson
            cprintf(rgb('DarkOrange'), 'WARNING: Incorrect no. of starting values or model specification \n')
            Results_old.MXL_d = rmfield(Results_old.MXL_d,'b0_old');
        else
            b0 = Results_old.MXL_d.b0_old(:);
        end
    end
    if  ~exist('b0','var')
        if isfield(Results_old,'MNL') && isfield(Results_old.MNL,'bhat') && length(Results_old.MNL.bhat) == (EstimOpt.NVarA*(1+ EstimOpt.NVarM) + EstimOpt.NVarS + EstimOpt.NVarNLT) %+ 2*EstimOpt.Johnson)
            disp('Using MNL results as starting values')
            Results_old.MNL.bhat = Results_old.MNL.bhat(:);
            %             b0 = [Results_old.MNL.bhat(1:EstimOpt.NVarA);max(1,sqrt(abs(Results_old.MNL.bhat(1:EstimOpt.NVarA))));0.1*ones(EstimOpt.NVarM.*EstimOpt.NVarA,1);Results_old.MNL.bhat(EstimOpt.NVarA+1:end)];
            b0 = [Results_old.MNL.bhat(1:EstimOpt.NVarA);max(1,abs(Results_old.MNL.bhat(1:EstimOpt.NVarA)));Results_old.MNL.bhat(EstimOpt.NVarA+1:end)];
            if sum(EstimOpt.Dist(2:end)==1) > 0
                if any(b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1) < 0)
                    cprintf(rgb('DarkOrange'), 'WARNING: MNL estimates of log-normally distributed parameters negative - using arbitrary starting values (this may not solve the problem - sign of the attribute may need to be reversed \n')
                    b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1 & b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1) < 0) = 1.01;
                end
                b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1) = log(b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1));                
            end
            if sum(EstimOpt.Dist(2:end) == 3) > 0 % Triangular
                indx = find( EstimOpt.Dist(2:end) == 3);
                b0([indx; indx+EstimOpt.NVarA]) = [log(b0(indx)- EstimOpt.Triang'); log(b0(indx)- EstimOpt.Triang')];
            end
            if sum(EstimOpt.Dist(2:end) == 4) > 0 % Weibull
                indx = find( EstimOpt.Dist(2:end) == 4);
                b0([indx; indx+EstimOpt.NVarA]) = [log(b0(indx)); zeros(length(indx),1)];
            end
            if sum(EstimOpt.Dist(2:end) >=5) > 0 % Johnson
                indx = find( EstimOpt.Dist(2:end) >= 5);
                tmp = [b0(indx); log(b0(indx+EstimOpt.NVarA))];
                b0([indx; indx+EstimOpt.NVarA]) = [zeros(length(indx),1), ones(length(indx),1)];
                b0 = [b0; tmp];
            end
        else
            error('No starting values available - run MNL first')
        end
    end
else % EstimOpt.FullCov == 1
    if exist('B_backup','var') && ~isempty(B_backup) && size(B_backup,1) == EstimOpt.NVarA*(1+EstimOpt.NVarM) + sum(1:EstimOpt.NVarA) + EstimOpt.NVarS + EstimOpt.NVarNLT + 2*EstimOpt.Johnson
        b0 = B_backup(:);
        disp('Using the starting values from Backup')
    elseif isfield(Results_old,'MXL') && isfield(Results_old.MXL,'b0') % starting values provided
        Results_old.MXL.b0_old = Results_old.MXL.b0(:);
        Results_old.MXL = rmfield(Results_old.MXL,'b0');
        if length(Results_old.MXL.b0_old) ~= EstimOpt.NVarA*(1+EstimOpt.NVarM) + sum(1:EstimOpt.NVarA) + EstimOpt.NVarS + EstimOpt.NVarNLT + 2*EstimOpt.Johnson
            cprintf(rgb('DarkOrange'), 'WARNING: Incorrect no. of starting values or model specification \n')
            Results_old.MXL = rmfield(Results_old.MXL,'b0_old');
        else
            b0 = Results_old.MXL.b0_old;
        end
    end
    if  ~exist('b0','var')
        if isfield(Results_old,'MXL_d') && isfield(Results_old.MXL_d,'bhat') && length(Results_old.MXL_d.bhat) == ((2+EstimOpt.NVarM)*EstimOpt.NVarA + EstimOpt.NVarS + EstimOpt.NVarNLT + 2*EstimOpt.Johnson)
            disp('Using MXL_d results as starting values')
            Results_old.MXL_d.bhat = Results_old.MXL_d.bhat(:);
            if sum(EstimOpt.Dist(2:end) >= 3) > 0
                vc_tmp = Results_old.MXL_d.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2);
                vc_tmp(EstimOpt.Dist(2:end) < 3) = vc_tmp(EstimOpt.Dist(2:end) < 3).^2;
                vc_tmp = diag(vc_tmp);
            else
                vc_tmp = (diag(Results_old.MXL_d.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2))).^2;
            end
            b0 = [Results_old.MXL_d.bhat(1:EstimOpt.NVarA); vc_tmp(tril(ones(size(vc_tmp)))==1);Results_old.MXL_d.bhat(EstimOpt.NVarA*2+1:end)];
        elseif isfield(Results_old,'MNL') && isfield(Results_old.MNL,'bhat')
            disp('Using MNL results as starting values')
            Results_old.MNL.bhat = Results_old.MNL.bhat(:);
            b0 = [Results_old.MNL.bhat(1:EstimOpt.NVarA);zeros(sum(1:EstimOpt.NVarA),1); Results_old.MNL.bhat(EstimOpt.NVarA+1:end)];
            if sum(EstimOpt.Dist(2:end)==1) > 0
                if any(b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1) < 0)
                    cprintf(rgb('DarkOrange'), 'WARNING: MNL estimates of log-normally distributed parameters negative - using arbitrary starting values (this may not solve the problem - sign of the attribute may need to be reversed \n')
                    b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1 & b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1) < 0) = 1.01;
                end
                b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1) = log(b0(EstimOpt.Dist(2:EstimOpt.NVarA+1) == 1));
            end
            if sum(EstimOpt.Dist(2:end) == 3) > 0 % Triangular
                b0(EstimOpt.Dist(2:end) == 3) = log(b0(EstimOpt.Dist(2:end) == 3)- EstimOpt.Triang');
            end
            if sum(EstimOpt.Dist(2:end) == 4) > 0 % Weibull
                b0(EstimOpt.Dist(2:end) == 4) = log(b0(EstimOpt.Dist(2:end) == 4));
            end
            if sum(EstimOpt.Dist(2:end) >=5) > 0 % Johnson
                indx = find( EstimOpt.Dist(2:end) >= 5);
                tmp = b0(indx);
                b0(indx) = zeros(length(indx),1);
                b0 = [b0; tmp; zeros(length(indx),1)];
            end
        else
            error('No starting values available')
        end
    end
end


%% Optimization Options


if  isfield(EstimOpt,'BActive')
    EstimOpt.BActive = EstimOpt.BActive(:)';
else
    EstimOpt.BActive = ones(1,length(b0));
end

if sum(EstimOpt.Dist == -1) > 0
    if isfield(EstimOpt,'BActive') == 0 || isempty(EstimOpt.BActive)
        EstimOpt.BActive = ones(1,length(b0));
    end
    if EstimOpt.FullCov == 0
        EstimOpt.BActive(EstimOpt.NVarA+find(EstimOpt.Dist(2:end) == -1)) = 0;
    elseif EstimOpt.FullCov == 1
        Vt = tril(ones(EstimOpt.NVarA));
        Vt(EstimOpt.Dist(2:end)==-1,:) = 0;
        %         EstimOpt.BActive(EstimOpt.NVarA+1:EstimOpt.NVarA+sum(1:EstimOpt.NVarA)) = EstimOpt.BActive(EstimOpt.NVarA+1:EstimOpt.NVarA+sum(1:EstimOpt.NVarA)) .* (Vt(find(tril(ones(size(Vt)))))');
        EstimOpt.BActive(EstimOpt.NVarA+1:EstimOpt.NVarA+sum(1:EstimOpt.NVarA)) = EstimOpt.BActive(EstimOpt.NVarA+1:EstimOpt.NVarA+sum(1:EstimOpt.NVarA)) .* (Vt(tril(ones(size(Vt)))~=0)');
    end
end

if EstimOpt.ConstVarActive == 1
    if ~isfield(EstimOpt,'BActive') || isempty(EstimOpt.BActive) || sum(EstimOpt.BActive == 0) == 0
        error ('Are there any constraints on model parameters (EstimOpt.ConstVarActive)? Constraints not provided (EstimOpt.BActive).')
    elseif length(b0) ~= length(EstimOpt.BActive)
        error('Check no. of constraints')
    end
    disp(['Initial values: ' mat2str(b0',2)])
    disp(['Parameters with zeros are constrained to their initial values: ' mat2str(EstimOpt.BActive')])
else
    if ~isfield(EstimOpt,'BActive') || isempty(EstimOpt.BActive) || sum(EstimOpt.BActive == 0) == 0
        EstimOpt.BActive = ones(1,length(b0));
        disp(['Initial values: ' mat2str(b0',2)])
    else
        if length(b0) ~= length(EstimOpt.BActive)
            error('Check no. of constraints')
        else
            disp(['Initial values: ' mat2str(b0',2)])
            disp(['Parameters with zeros are constrained to their initial values: ' mat2str(EstimOpt.BActive')])
        end
    end
end


%% Generate pseudo-random draws


if isfield(EstimOpt,'Seed1') == 1
    rng(EstimOpt.Seed1);
end
cprintf('Simulation with ');
cprintf('*blue',[num2str(EstimOpt.NRep) ' ']);

if EstimOpt.Draws == 1
    cprintf('*blue','Pseudo-random '); cprintf('draws \n');
    err_mtx = randn(EstimOpt.NP*EstimOpt.NRep, EstimOpt.NVarA+1); %to be cut down later
elseif EstimOpt.Draws == 2 % LHS
    cprintf('*blue','Latin Hypercube Sampling '); cprintf('draws \n');
    err_mtx=lhsnorm(zeros((EstimOpt.NVarA+1)*EstimOpt.NP,1),diag(ones((EstimOpt.NVarA+1)*EstimOpt.NP,1)),EstimOpt.NRep);
    err_mtx = reshape(err_mtx, EstimOpt.NRep*EstimOpt.NP, EstimOpt.NVarA+1);
elseif EstimOpt.Draws >= 3 % Quasi random draws
    if EstimOpt.Draws == 3
        cprintf('*blue','Halton '); cprintf('draws (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = haltonset(EstimOpt.NVarA+1,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap); %
    elseif EstimOpt.Draws == 4 % apply reverse-radix scrambling
        cprintf('*blue','Halton '); cprintf('draws with reverse radix scrambling (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = haltonset(EstimOpt.NVarA+1,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap); %
        hm1 = scramble(hm1,'RR2');
    elseif EstimOpt.Draws == 5
        cprintf('*blue','Sobol '); cprintf('draws (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = sobolset(EstimOpt.NVarA+1,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap);
    elseif EstimOpt.Draws == 6
        cprintf('*blue','Sobol '); cprintf('draws with random linear scramble and random digital shift (skip = '); cprintf(num2str(EstimOpt.HaltonSkip)); cprintf('; leap = '); cprintf(num2str(EstimOpt.HaltonLeap)); cprintf(') \n')
        hm1 = sobolset(EstimOpt.NVarA+1,'Skip',EstimOpt.HaltonSkip,'Leap',EstimOpt.HaltonLeap);
        hm1 = scramble(hm1,'MatousekAffineOwen');
    end
    
    err_mtx = net(hm1,EstimOpt.NP*EstimOpt.NRep); % this takes every point:
    clear hm1;
    err_mtx = err_mtx(:,2:EstimOpt.NVarA+1);
    
    if EstimOpt.NP*EstimOpt.NRep < 3e+7
        err_mtx = icdf('Normal',err_mtx,0,1); %to be cut down later
    else % this is for very large number of draws * variables
        for i = 1:EstimOpt.NVarA
            err_mtx(:,i) = icdf('Normal',err_mtx(:,i),0,1); %to be cut down later
        end
    end
    
    err_mtx(:,EstimOpt.Dist(2:end) == -1) = 0;
    
end


%% Display Options


if ((isfield(EstimOpt, 'ConstVarActive') == 1 && EstimOpt.ConstVarActive == 1) || sum(EstimOpt.BActive == 0) > 0) && ~isequal(OptimOpt.GradObj,'on')
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient on - otherwise parameters'' constraints will be ignored - switch to constrained optimization instead (EstimOpt.ConstVarActive = 1) \n')
    OptimOpt.GradObj = 'on';
end

% if EstimOpt.NVarS > 0 && EstimOpt.NumGrad == 0 && any(isnan(INPUT.Xa(:)))
% 	EstimOpt.NumGrad = 1;
%     OptimOpt.GradObj = 'off';
% 	cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient off - covariates of scale not supported by analytical gradient \n')
% end

if any(EstimOpt.Dist(2:EstimOpt.NVarA+1) > 1) && EstimOpt.NumGrad == 0
    EstimOpt.NumGrad = 1;
    OptimOpt.GradObj = 'off';
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient off - analytical gradient available for normally or lognormally distributed parameters only \n')
end


if ((isfield(EstimOpt, 'ConstVarActive') == 1 && EstimOpt.ConstVarActive == 1) || sum(EstimOpt.BActive == 0) > 0) && ~isequal(OptimOpt.GradObj,'on')
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient on - otherwise parameters'' constraints will be ignored - switch to constrained optimization instead (EstimOpt.ConstVarActive = 1) \n')
    EstimOpt.NumGrad = 1;
    OptimOpt.GradObj = 'on';
end

% if EstimOpt.NVarNLT > 0 && EstimOpt.NLTType == 2 && EstimOpt.NumGrad == 0
% 	EstimOpt.NumGrad = 1;
% 	if EstimOpt.Display ~= 0
%         cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied gradient to numerical - Yeo-Johnston transformation not supported by analytical gradient \n')
% 	end
% end

if (isfield(EstimOpt, 'ConstVarActive') == 0 || EstimOpt.ConstVarActive == 0) && isequal(OptimOpt.Algorithm,'quasi-newton') && isequal(OptimOpt.Hessian,'user-supplied')
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied Hessian off - quasi-newton algorithm does not use it anyway \n')
    OptimOpt.Hessian = 'off';
end

if  EstimOpt.NumGrad == 1 && EstimOpt.ApproxHess == 0
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied exact Hessian off - exact Hessian only available if analythical gradient on \n')
    EstimOpt.ApproxHess = 1;
end

if  EstimOpt.NVarS > 0 && (EstimOpt.ApproxHess == 0 || EstimOpt.HessEstFix == 4)
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied exact Hessian off - exact Hessian not available for models with covariates of scale \n')
    EstimOpt.ApproxHess = 1;
    EstimOpt.HessEstFix = 0;
end

if  EstimOpt.NVarM > 0 && (EstimOpt.ApproxHess == 0 || EstimOpt.HessEstFix == 4)
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied exact Hessian off - exact Hessian not available for models with covariates of means \n')
    EstimOpt.ApproxHess = 1;
    EstimOpt.HessEstFix = 0;
end

if  EstimOpt.WTP_space > 0 && (EstimOpt.ApproxHess == 0 || EstimOpt.HessEstFix == 4)
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied exact Hessian off - exact Hessian not available for models in WTP-space \n')
    EstimOpt.ApproxHess = 1;
    EstimOpt.HessEstFix = 0;
end



if  any(isnan(INPUT.Xa(:))) == 1 && (EstimOpt.ApproxHess == 0 || EstimOpt.HessEstFix == 4)
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied exact Hessian off - exact Hessian not available with missing data \n')
    EstimOpt.ApproxHess = 1;
    EstimOpt.HessEstFix = 0;
end


if  any(EstimOpt.Dist(2:EstimOpt.NVarA+1)~= 0) && (EstimOpt.ApproxHess == 0 || EstimOpt.HessEstFix == 4)
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied exact Hessian off - exact Hessian available for models with normally distributed parameters only \n')
    EstimOpt.ApproxHess = 1;
    EstimOpt.HessEstFix = 0;
end

if EstimOpt.NVarNLT > 0 && (EstimOpt.ApproxHess == 0 || EstimOpt.HessEstFix == 4)
    cprintf(rgb('DarkOrange'), 'WARNING: Setting user-supplied exact Hessian off - exact Hessian not available for models with non-linear transformation(s) of variable(s) \n')
    EstimOpt.ApproxHess = 1;
    EstimOpt.HessEstFix = 0;
end

if any(INPUT.W ~= 1) && ((EstimOpt.ApproxHess == 0 && EstimOpt.NumGrad == 0) || EstimOpt.HessEstFix == 4)
    INPUT.W = ones(EstimOpt.NP,1);
    cprintf(rgb('DarkOrange'), 'WARNING: Setting all weights to 1, they are not supported with analytical hessian \n')
end

if EstimOpt.RobustStd == 1 && (EstimOpt.HessEstFix == 1 || EstimOpt.HessEstFix == 2)
    EstimOpt.RobustStd = 0;
    cprintf(rgb('DarkOrange'), 'WARNING: Setting off robust standard errors, they do not matter for BHHH aproximation of hessian \n')
end

if  any(EstimOpt.Dist(2:end)>= 3 & EstimOpt.Dist(2:end) <= 5) && EstimOpt.NVarM ~= 0
    error('Covariates of means do not work with triangular/weibull/sinh-arcsinh distributions')
end

fprintf('\n')
cprintf('Opmization algorithm: '); cprintf('*Black',[OptimOpt.Algorithm '\n'])

if strcmp(OptimOpt.GradObj,'on')
    if EstimOpt.NumGrad == 0
        cprintf('Gradient: '); cprintf('*Black','user-supplied, analytical \n')
    else
        cprintf('Gradient: '); cprintf('*Black',['user-supplied, numerical, ' OptimOpt.FinDiffType '\n'])
    end
else
    cprintf('Gradient: '); cprintf('*Black',['built-in, ' OptimOpt.FinDiffType '\n'])
end

if isequal(OptimOpt.Algorithm,'quasi-newton')
    cprintf('Hessian: '); cprintf('*Black','off, ')
    switch EstimOpt.HessEstFix
        case 0
            cprintf('*Black','retained from optimization \n')
        case 1
            cprintf('*Black','ex-post calculated using BHHH \n')
        case 2
            cprintf('*Black','ex-post calculated using high-precision BHHH \n')
        case 3
            cprintf('*Black','ex-post calculated numerically \n')
        case 4
            cprintf('*Black','ex-post calculated analytically \n')
    end
else
    if strcmp(OptimOpt.Hessian,'user-supplied')
        if EstimOpt.ApproxHess == 1
            cprintf('Hessian: '); cprintf('*Black','user-supplied, BHHH, ')
        else
            cprintf('Hessian: '); cprintf('*Black','user-supplied, analytical, ')
        end
    else
        cprintf('Hessian: '); cprintf('*Black',['built-in, ' OptimOpt.HessUpdate ', '])
    end
    switch EstimOpt.HessEstFix
        case 0
            cprintf('*Black','retained from optimization \n')
        case 1
            cprintf('*Black','ex-post calculated using BHHH \n')
        case 2
            cprintf('*Black','ex-post calculated using high-precision BHHH \n')
        case 3
            cprintf('*Black','ex-post calculated numerically \n')
        case 4
            cprintf('*Black','ex-post calculated analytically \n')
    end
end
fprintf('\n')


%% Rescructure data

INPUT.XXa = reshape(INPUT.Xa,EstimOpt.NAlt*EstimOpt.NCT,EstimOpt.NP, EstimOpt.NVarA);
INPUT.XXa = permute(INPUT.XXa, [1 3 2]);
INPUT.YY = reshape(INPUT.Y,EstimOpt.NAlt*EstimOpt.NCT,EstimOpt.NP);

% idx = sum(reshape(INPUT.MissingInd,[EstimOpt.NAlt,EstimOpt.NCT,EstimOpt.NP])) == EstimOpt.NAlt;
% INPUT.YYY(idx(ones(EstimOpt.NAlt,1),:,:)) = NaN; % replace YYY in missing choice-tasks with NaN
% INPUT.YY = reshape(INPUT.YYY,EstimOpt.NAlt*EstimOpt.NCT,EstimOpt.NP)==1;
%INPUT.YY = reshape(INPUT.YYY,EstimOpt.NAlt*EstimOpt.NCT,EstimOpt.NP);


INPUT.XXm = reshape(INPUT.Xm',EstimOpt.NVarM, EstimOpt.NAlt*EstimOpt.NCT,EstimOpt.NP);
INPUT.XXm = squeeze(INPUT.XXm(:,1,:));
if EstimOpt.NVarM == 1
    INPUT.XXm = INPUT.XXm';
end


err_mtx = err_mtx';
% change err_mtx from NRep*NP x NVarA to NP*NRep x NVarA (incrasing the no. of draws only adds new draws for each respondent, does not change all draws per individual)
% err_mtx = reshape(permute(reshape(err_mtx,EstimOpt.NP,EstimOpt.NRep,EstimOpt.NVarA),[2,1,3]),EstimOpt.NP*EstimOpt.NRep,EstimOpt.NVarA)';
% problem - look at the first NRep draws for NVarA=1... all are positive...
if isfield(EstimOpt, 'Drawskeep') && ~isempty(EstimOpt.Drawskeep) && EstimOpt.Drawskeep == 1
    Results.err = err_mtx;
end

VC = tril(ones(EstimOpt.NVarA));
VC(VC == 1) = (1:(EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+EstimOpt.NVarA))';
EstimOpt.DiagIndex = diag(VC);

% Creating indices for analitical gradient

EstimOpt.indx1 = [];
EstimOpt.indx2 = [];
if EstimOpt.NumGrad == 0 && EstimOpt.FullCov == 1
    for i = 1:EstimOpt.NVarA
        EstimOpt.indx1 = [EstimOpt.indx1, i:EstimOpt.NVarA];
        EstimOpt.indx2 = [EstimOpt.indx2, i*ones(1,EstimOpt.NVarA+1-i)];
    end
end

% save tmp2
% return

% if EstimOpt.ApproxHess == 0 || EstimOpt.HessEstFix == 4; %calculations needed for analitical Hessian
%     EstimOpt.XXX = permute(mmx('square',permute(INPUT.XXa,[2,4,1,3]),[]),[3,1,2,4])
%     EstimOpt.XXX = zeros(EstimOpt.NAlt*EstimOpt.NCT,EstimOpt.NVarA,EstimOpt.NVarA, EstimOpt.NP);
%     if EstimOpt.FullCov == 0
%         EstimOpt.VCx = zeros(EstimOpt.NVarA,EstimOpt.NVarA,EstimOpt.NRep,EstimOpt.NP);
%     else
%         EstimOpt.VCx = zeros(EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+EstimOpt.NVarA,EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+EstimOpt.NVarA,EstimOpt.NRep,EstimOpt.NP);
%     end
%     err_tmp = reshape(err_mtx,EstimOpt.NVarA,EstimOpt.NRep,EstimOpt.NP);
%     for i = 1:EstimOpt.NP
%         for j = 1:EstimOpt.NAlt*EstimOpt.NCT
%             EstimOpt.XXX(j,:,:,i) = (INPUT.XXa(j,:,i)')*INPUT.XXa(j,:,i);
%         end
%         for j = 1:EstimOpt.NRep
%             if EstimOpt.FullCov == 0
%                 EstimOpt.VCx(:,:,j,i) = err_tmp(:,j,i)*err_tmp(:,j,i)';
%             else
%                 EstimOpt.VCx(:,:,j,i) = err_tmp(EstimOpt.indx2,j,i)*err_tmp(EstimOpt.indx2,j,i)';
%             end
%         end
%     end

% end


%% Estimation


LLfun = @(B) LL_mxl_MATlike(INPUT.YY,INPUT.XXa,INPUT.XXm,INPUT.Xs,err_mtx,INPUT.W,EstimOpt,OptimOpt,B);

if EstimOpt.ConstVarActive == 0
    
    if EstimOpt.HessEstFix == 0
        [Results.bhat, LL, Results.exitf, Results.output, Results.g, Results.hess] = fminunc(LLfun, b0, OptimOpt);
    else
        [Results.bhat, LL, Results.exitf, Results.output, Results.g] = fminunc(LLfun, b0, OptimOpt);
    end
    
    %     [x,fval,exitflag,output,lambda,grad,hessian] = knitromatlab(fun,x0,A,b,Aeq,beq,lb,ub,nonlcon,extendedFeatures,options,KNITROOptions)
    %     [Results.bhat,LL,Results.exitf,Results.output,Results.lambda,Results.g,Results.hess] = knitromatlab(LLfun,b0,[],[],[],[],[],[],[],[],[],'knitro.opt'); %
    %     [Results.bhat,LL,Results.exitf,Results.output,Results.lambda,Results.g,Results.hess] = knitromatlab(LLfun,b0,[],[],[],[],[],[],[],[],OptimOpt,'knitro.opt'); %
    
elseif EstimOpt.ConstVarActive == 1 % equality constraints
    
    EstimOpt.CONS1 = diag(1 - EstimOpt.BActive);
    EstimOpt.CONS1(sum(EstimOpt.CONS1,1)==0,:)=[];
    EstimOpt.CONS2 = zeros(size(EstimOpt.CONS1,1),1);
    %     EstimOpt.CONS1 = sparse(EstimOpt.CONS1);
    %     EstimOpt.CONS2 = sparse(EstimOpt.CONS2);
    if EstimOpt.HessEstFix == 0
        [Results.bhat, LL, Results.exitf, Results.output, Results.lambda, Results.g, Results.hess] = fmincon(LLfun,b0,[],[],EstimOpt.CONS1,EstimOpt.CONS2,[],[],[],OptimOpt);
    else
        [Results.bhat, LL, Results.exitf, Results.output, Results.lambda, Results.g] = fmincon(LLfun,b0,[],[],EstimOpt.CONS1,EstimOpt.CONS2,[],[],[],OptimOpt);
    end
    
end


%% Output


% save tmp1
% return

Results.LL = -LL;
Results.b0_old = b0;

LLfun2 = @(B) LL_mxl(INPUT.YY,INPUT.XXa,INPUT.XXm,INPUT.Xs,err_mtx,EstimOpt,B);
if EstimOpt.HessEstFix == 0 % this will fail if there is no gradient available! 
    [Results.LLdetailed,Results.jacobian] = LLfun2(Results.bhat);
elseif EstimOpt.HessEstFix == 1
    if isequal(OptimOpt.GradObj,'on') && EstimOpt.NumGrad == 0
        [Results.LLdetailed,Results.jacobian] = LLfun2(Results.bhat);
        Results.jacobian = Results.jacobian.*INPUT.W(:,ones(1,size(Results.jacobian,2)));
    else
        Results.LLdetailed = LLfun2(Results.bhat);
        Results.jacobian = numdiff(@(B) INPUT.W.*LLfun2(B),Results.LLdetailed,Results.bhat,isequal(OptimOpt.FinDiffType, 'central'),EstimOpt.BActive);
        Results.jacobian = Results.jacobian.*INPUT.W(:,ones(1,size(Results.jacobian,2)));
    end
elseif EstimOpt.HessEstFix == 2
    Results.LLdetailed = LLfun2(Results.bhat);
    Results.jacobian = jacobianest(@(B) INPUT.W.*LLfun2(B),Results.bhat);
elseif EstimOpt.HessEstFix == 3
    Results.LLdetailed = LLfun2(Results.bhat);
    Results.hess = hessian(@(B) sum(INPUT.W.*LLfun2(B)), Results.bhat);
elseif EstimOpt.HessEstFix == 4
    [Results.LLdetailed,~,Results.hess] = LLfun2(Results.bhat);
    % no weighting?
end

Results.LLdetailed = Results.LLdetailed.*INPUT.W;

if EstimOpt.RobustStd == 1
    if EstimOpt.NumGrad == 0
        [~, Results.jacobian] = LLfun2(Results.bhat);
        Results.jacobian = Results.jacobian.*INPUT.W(:, ones(1,size(Results.jacobian,2)));
    else
        Results.jacobian = numdiff(@(B) INPUT.W.*LLfun2(B),Results.LLdetailed,Results.bhat,isequal(OptimOpt.FinDiffType, 'central'),EstimOpt.BActive);
    end
    RobustHess = Results.jacobian'*Results.jacobian;
    Results.ihess = Results.ihess*RobustHess*Results.ihess;
end

if EstimOpt.HessEstFix == 1 || EstimOpt.HessEstFix == 2
    Results.hess = Results.jacobian'*Results.jacobian;
end
EstimOpt.BLimit = (sum(Results.hess) == 0 & EstimOpt.BActive == 1);
EstimOpt.BActive(EstimOpt.BLimit == 1) = 0;
Results.hess = Results.hess(EstimOpt.BActive == 1,EstimOpt.BActive == 1);
Results.ihess = inv(Results.hess);
Results.ihess = direcXpnd(Results.ihess,EstimOpt.BActive);
Results.ihess = direcXpnd(Results.ihess',EstimOpt.BActive);

Results.std = sqrt(diag(Results.ihess));
Results.std(EstimOpt.BActive == 0) = NaN;
Results.std(EstimOpt.BLimit == 1) = 0;
Results.std(imag(Results.std) ~= 0) = NaN;

if any(INPUT.MissingInd == 1) % In case of some missing data
    idx = sum(reshape(INPUT.MissingInd,EstimOpt.NAlt,EstimOpt.NCT*EstimOpt.NP)) == EstimOpt.NAlt; ...
        idx = sum(reshape(idx, EstimOpt.NCT, EstimOpt.NP),1)'; % no. of missing NCT for every respondent
    idx = EstimOpt.NCT - idx;
    R2 = mean(exp(-Results.LLdetailed./idx),1);
else
    R2 = mean(exp(-Results.LLdetailed/EstimOpt.NCT),1);
end

if EstimOpt.Scores ~= 0
    Results.Scores =  BayesScores(INPUT.YY,INPUT.XXa,INPUT.XXm,INPUT.Xs,err_mtx,EstimOpt,Results.bhat);
end

% save out_MXL

if EstimOpt.FullCov == 0
    Results.DetailsA(1:EstimOpt.NVarA,1) = Results.bhat(1:EstimOpt.NVarA);
    Results.DetailsA(1:EstimOpt.NVarA,3:4) = [Results.std(1:EstimOpt.NVarA),pv(Results.bhat(1:EstimOpt.NVarA),Results.std(1:EstimOpt.NVarA))];
    std_out = Results.std(EstimOpt.NVarA+1:EstimOpt.NVarA*2);...
        std_out(imag(Results.std(EstimOpt.NVarA+1:EstimOpt.NVarA*2)) ~= 0) = NaN; ...
        %     Results.DetailsV = [Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2).^2,2.*std_out.*abs(Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2)),pv((Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2)).^2,2.*std_out.*abs(Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2)))];
    
    Results.DetailsV(1:EstimOpt.NVarA,1) = abs(Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2));
    Results.DetailsV(1:EstimOpt.NVarA,3:4) = [std_out,pv(abs(Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2)),std_out)];
    if sum(EstimOpt.Dist(2:end) == 3) > 0
        Results.DetailsA(EstimOpt.Dist(2:end) == 3,1) = exp(Results.bhat(EstimOpt.Dist(2:end) == 3)) + EstimOpt.Triang';
        Results.DetailsA(EstimOpt.Dist(2:end) == 3,3:4) = [exp(Results.bhat(EstimOpt.Dist(2:end) == 3)).*Results.std(EstimOpt.Dist(2:end) == 3), pv(exp(Results.bhat(EstimOpt.Dist(2:end) == 3)) + EstimOpt.Triang', exp(Results.bhat(EstimOpt.Dist(2:end) == 3)).*Results.std(EstimOpt.Dist(2:end) == 3))];
        btmp = Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2);
        stdx = zeros(sum(EstimOpt.Dist(2:end) == 3),1);
        g = [exp(Results.bhat(EstimOpt.Dist(2:end) == 3)), exp(btmp(EstimOpt.Dist(2:end) == 3))];
        indx = find(EstimOpt.Dist(2:end) == 3);
        for i = 1:sum(EstimOpt.Dist(2:end) == 3)
            stdx(i) = sqrt(g(i,:)*Results.ihess([indx(i), indx(i)+EstimOpt.NVarA], [indx(i), indx(i)+EstimOpt.NVarA])*g(i,:)');
        end
        %tutaj nie powinno byc? ==3 (byo?=o ==4)vvvv
        Results.DetailsV(EstimOpt.Dist(2:end) == 3,1) = exp(btmp(EstimOpt.Dist(2:end) == 4));
        Results.DetailsV(EstimOpt.Dist(2:end) == 3,3:4) = [stdx(EstimOpt.Dist(2:end) == 4), pv(exp(btmp(EstimOpt.Dist(2:end) == 4)), stdx(EstimOpt.Dist(2:end) == 4)) ];
    end
    if sum(EstimOpt.Dist(2:end) == 4) > 0
        Results.DetailsA(EstimOpt.Dist(2:end) == 4,1) = exp(Results.bhat(EstimOpt.Dist(2:end) == 4));
        Results.DetailsA(EstimOpt.Dist(2:end) == 4,3:4) = [exp(Results.bhat(EstimOpt.Dist(2:end) == 4)).*Results.std(EstimOpt.Dist(2:end) == 4), pv(exp(Results.bhat(EstimOpt.Dist(2:end) == 4)), exp(Results.bhat(EstimOpt.Dist(2:end) == 4)).*Results.std(EstimOpt.Dist(2:end) == 4))];
        btmp = Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*2);
        stdx = exp(btmp).*Results.std(EstimOpt.NVarA+1:EstimOpt.NVarA*2);
        Results.DetailsV(EstimOpt.Dist(2:end) == 4,1) = exp(btmp(EstimOpt.Dist(2:end) == 4)); 
        Results.DetailsV(EstimOpt.Dist(2:end) == 4,3:4) = [stdx(EstimOpt.Dist(2:end) == 4), pv(exp(btmp(EstimOpt.Dist(2:end) == 4)), stdx(EstimOpt.Dist(2:end) == 4)) ];
    end
    Results.R = [Results.DetailsA, Results.DetailsV];
    if EstimOpt.NVarM > 0
        Results.DetailsM = [];
        for i=1:EstimOpt.NVarM; 
             Results.DetailsM(1:EstimOpt.NVarA,(4*i -3)) = Results.bhat(EstimOpt.NVarA*(2+i-1)+1:EstimOpt.NVarA*(2+i));
             Results.DetailsM(1:EstimOpt.NVarA,(4*i -1):4*i) = [Results.std(EstimOpt.NVarA*(2+i-1)+1:EstimOpt.NVarA*(2+i)),pv(Results.bhat(EstimOpt.NVarA*(2+i-1)+1:EstimOpt.NVarA*(2+i)),Results.std(EstimOpt.NVarA*(2+i-1)+1:EstimOpt.NVarA*(2+i)))];
        end
        Results.R = [Results.R, Results.DetailsM];
    end
    if EstimOpt.NVarNLT > 0
        Results.DetailsNLT = [];
        for i=1:EstimOpt.NVarNLT; 
            Results.DetailsNLT(i,1) = Results.bhat(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i);
            
            Results.DetailsNLT(i,3:4) = [Results.std(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i),pv(Results.bhat(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i),Results.std(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i))];
        end
        Results.DetailsNLT0 = NaN(EstimOpt.NVarA,4);
        Results.DetailsNLT0(EstimOpt.NLTVariables,:) = Results.DetailsNLT;
        Results.R = [Results.R, Results.DetailsNLT0];
    end
    if EstimOpt.Johnson > 0
        Results.ResultsJ = NaN(EstimOpt.NVarA, 8);
        % Location parameters
        Results.DetailsJL(:,1) = Results.bhat((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson));
        Results.DetailsJL(:,3) = Results.std((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson));
        Results.DetailsJL(:,4) = pv(Results.bhat((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson)),Results.std((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson)));
       
        % Scale parameters
        Results.DetailsJS(:,1) = exp(Results.bhat((end - EstimOpt.Johnson+1):end));
        Results.DetailsJS(:,3) = exp(Results.bhat((end - EstimOpt.Johnson+1):end)).*Results.std((end - EstimOpt.Johnson+1):end);
        Results.DetailsJS(:,4) = pv(exp(Results.bhat((end - EstimOpt.Johnson+1):end)),exp(Results.bhat((end - EstimOpt.Johnson+1):end)).*Results.std((end - EstimOpt.Johnson+1):end));
        
        Results.ResultsJ(EstimOpt.Dist(2:end) > 4 & EstimOpt.Dist(2:end) <= 7,1:4) =   Results.DetailsJL;
        Results.ResultsJ(EstimOpt.Dist(2:end) > 4 & EstimOpt.Dist(2:end) <= 7,5:8) =   Results.DetailsJS;
        Results.R = [Results.R, Results.ResultsJ];
    end
    if EstimOpt.NVarS > 0
        Results.DetailsS = [];
        for i=1:EstimOpt.NVarS; 
           Results.DetailsS(i,1) = Results.bhat(EstimOpt.NVarA*(2+EstimOpt.NVarM)+i);
           Results.DetailsS(i,3:4) = [Results.std(EstimOpt.NVarA*(2+EstimOpt.NVarM)+i),pv(Results.bhat(EstimOpt.NVarA*(2+EstimOpt.NVarM)+i),Results.std(EstimOpt.NVarA*(2+EstimOpt.NVarM)+i))];
        end
        DetailsS0 = NaN(EstimOpt.NVarA,4);
        DetailsS0(1:EstimOpt.NVarS,1:4) = Results.DetailsS;

        if EstimOpt.NVarS <= EstimOpt.NVarA % will not work if NVarS > NVarA
            esults.R = [Results.R; [DetailsS0,NaN(size(DetailsS0,1),size(Results.R,2)-size(DetailsS0,2))]]; 
        end
     end
    
elseif EstimOpt.FullCov == 1
    Results.DetailsA(1:EstimOpt.NVarA,1) = Results.bhat(1:EstimOpt.NVarA);
    Results.DetailsA(1:EstimOpt.NVarA,3:4) = [Results.std(1:EstimOpt.NVarA),pv(Results.bhat(1:EstimOpt.NVarA),Results.std(1:EstimOpt.NVarA))];
    Results.DetailsV = sdtri(Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA+3)/2), Results.ihess(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA+3)/2,EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA+3)/2),EstimOpt);
    Results.DetailsV = [Results.DetailsV(:,1),zeros(EstimOpt.NVarA,1),Results.DetailsV(:,2:3)];
    if sum(EstimOpt.Dist(2:end) == 3) > 0
        Results.DetailsA(EstimOpt.Dist(2:end) == 3,1) = exp(Results.bhat(EstimOpt.Dist(2:end) == 3)) + EstimOpt.Triang';
        Results.DetailsA(EstimOpt.Dist(2:end) == 3,3:4) = [exp(Results.bhat(EstimOpt.Dist(2:end) == 3)).*Results.std(EstimOpt.Dist(2:end) == 3), pv(exp(Results.bhat(EstimOpt.Dist(2:end) == 3)) + EstimOpt.Triang', exp(Results.bhat(EstimOpt.Dist(2:end) == 3)).*Results.std(EstimOpt.Dist(2:end) == 3))];
        
        btmp = Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+2*EstimOpt.NVarA);
        btmp = btmp(EstimOpt.DiagIndex);
        stdx = zeros(sum(EstimOpt.Dist(2:end) == 3),1);
        g = [exp(Results.bhat(EstimOpt.Dist(2:end) == 3)), exp(btmp(EstimOpt.Dist(2:end) == 3))];
        indx = find(EstimOpt.Dist(2:end) == 3);
        DiagIndex = EstimOpt.DiagIndex(EstimOpt.Dist(2:end) == 3);
        for i = 1:sum(EstimOpt.Dist(2:end) == 3)
            stdx(i) = sqrt(g(i,:)*Results.ihess([indx(i), DiagIndex(i)+EstimOpt.NVarA], [indx(i), DiagIndex(i)+EstimOpt.NVarA])*g(i,:)');
        end
        Results.DetailsV(EstimOpt.Dist(2:end) == 3,1) = exp(btmp(EstimOpt.Dist(2:end) == 3))+ exp(Results.bhat(EstimOpt.Dist(2:end) == 3)) + EstimOpt.Triang'; 
        Results.DetailsV(EstimOpt.Dist(2:end) == 3,3:4) = [stdx, pv(exp(btmp(EstimOpt.Dist(2:end) == 3))+ exp(Results.bhat(EstimOpt.Dist(2:end) == 3)) + EstimOpt.Triang', stdx) ];
    end
    if sum(EstimOpt.Dist(2:end) == 4) > 0
        Results.DetailsA(EstimOpt.Dist(2:end) == 4,1) = exp(Results.bhat(EstimOpt.Dist(2:end) == 4));
        Results.DetailsA(EstimOpt.Dist(2:end) == 4,3:4) = [ exp(Results.bhat(EstimOpt.Dist(2:end) == 4)).*Results.std(EstimOpt.Dist(2:end) == 4), pv(exp(Results.bhat(EstimOpt.Dist(2:end) == 4)), exp(Results.bhat(EstimOpt.Dist(2:end) == 4)).*Results.std(EstimOpt.Dist(2:end) == 4))];
        btmp = Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+2*EstimOpt.NVarA);
        btmp = btmp(EstimOpt.DiagIndex);
        stdx = Results.std(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+2*EstimOpt.NVarA);
        stdx = stdx(EstimOpt.DiagIndex);
        stdx = exp(btmp).*stdx;
        Results.DetailsV(EstimOpt.Dist(2:end) == 4,1) = exp(btmp(EstimOpt.Dist(2:end) == 4));
        Results.DetailsV(EstimOpt.Dist(2:end) == 4,3:4) =  [stdx(EstimOpt.Dist(2:end) == 4), pv(exp(btmp(EstimOpt.Dist(2:end) == 4)), stdx(EstimOpt.Dist(2:end) == 4)) ];
    end
    if sum(EstimOpt.Dist(2:end) == 5) > 0
        btmp = Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+2*EstimOpt.NVarA);
        btmp = btmp(EstimOpt.DiagIndex);
        stdtmp = Results.std(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA-1)/2+2*EstimOpt.NVarA);
        stdtmp = stdtmp(EstimOpt.DiagIndex);
        Results.DetailsV(EstimOpt.Dist(2:end) ==5,1) = btmp(EstimOpt.Dist(2:end) == 5).^2;
        Results.DetailsV(EstimOpt.Dist(2:end) ==5,3:4) = [2*btmp(EstimOpt.Dist(2:end) == 5).*stdtmp(EstimOpt.Dist(2:end) == 5), pv(btmp(EstimOpt.Dist(2:end) == 5).^2, 2*btmp(EstimOpt.Dist(2:end) == 5).*stdtmp(EstimOpt.Dist(2:end) == 5))];
    end
    Results.R = [Results.DetailsA, Results.DetailsV];
    if EstimOpt.NVarM > 0
        Results.DetailsM = [];
        for i=1:EstimOpt.NVarM; 
            Results.DetailsM(1:EstimOpt.NVarA,(4*i -3)) = Results.bhat(EstimOpt.NVarA*(EstimOpt.NVarA/2+0.5+i)+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+i)); 
            Results.DetailsM(1:EstimOpt.NVarA,(4*i -1):4*i) = [Results.std(EstimOpt.NVarA*(EstimOpt.NVarA/2+0.5+i)+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+i)),pv(Results.bhat(EstimOpt.NVarA*(EstimOpt.NVarA/2+0.5+i)+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+i)),Results.std(EstimOpt.NVarA*(EstimOpt.NVarA/2+0.5+i)+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+i)))]; 
        end
        Results.R = [Results.R, Results.DetailsM];
    end
    
    if EstimOpt.NVarNLT > 0
        Results.DetailsNLT = [];
        for i=1:EstimOpt.NVarNLT; 
            Results.DetailsNLT(i,1) = Results.bhat(EstimOpt.NVarA+sum(1:EstimOpt.NVarA)+EstimOpt.NVarM+EstimOpt.NVarS+i);
            Results.DetailsNLT(i,3:4)  = [Results.std(EstimOpt.NVarA+sum(1:EstimOpt.NVarA)+EstimOpt.NVarM+EstimOpt.NVarS+i),pv(Results.bhat(EstimOpt.NVarA+sum(1:EstimOpt.NVarA)+EstimOpt.NVarM+EstimOpt.NVarS+i),Results.std(EstimOpt.NVarA+sum(1:EstimOpt.NVarA)+EstimOpt.NVarM+EstimOpt.NVarS+i))];
        end
        %         for i=1:EstimOpt.NVarNLT; Results.DetailsNLT = [Results.DetailsNLT; [Results.bhat(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i),Results.std(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i),pv(Results.bhat(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i),Results.std(EstimOpt.NVarA*(2+EstimOpt.NVarM)+EstimOpt.NVarS+i))]];end
        Results.DetailsNLT0 = NaN(EstimOpt.NVarA,4);
        Results.DetailsNLT0(EstimOpt.NLTVariables,:) = Results.DetailsNLT;
        Results.R = [Results.R, Results.DetailsNLT0];
    end
    if EstimOpt.Johnson > 0
        Results.ResultsJ = NaN(EstimOpt.NVarA, 8);
        % Location parameters
        Results.DetailsJL(:,1) = Results.bhat((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson));
        Results.DetailsJL(:,3) = Results.std((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson));
        Results.DetailsJL(:,4) = pv(Results.bhat((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson)),Results.std((end - 2*EstimOpt.Johnson+1):(end - EstimOpt.Johnson)));
        % Scale parameters
        Results.DetailsJS(:,1) = exp(Results.bhat((end - EstimOpt.Johnson+1):end));
        Results.DetailsJS(:,3) = exp(Results.bhat((end - EstimOpt.Johnson+1):end)).*Results.std((end - EstimOpt.Johnson+1):end);
        Results.DetailsJS(:,4) = pv(exp(Results.bhat((end - EstimOpt.Johnson+1):end)),exp(Results.bhat((end - EstimOpt.Johnson+1):end)).*Results.std((end - EstimOpt.Johnson+1):end));
        Results.ResultsJ(EstimOpt.Dist(2:end) > 4 & EstimOpt.Dist(2:end) <= 7,1:4) =   Results.DetailsJL;
        Results.ResultsJ(EstimOpt.Dist(2:end) > 4 & EstimOpt.Dist(2:end) <= 7,5:8) =   Results.DetailsJS;
        Results.R = [Results.R, Results.ResultsJ];
    end
    if EstimOpt.NVarS > 0
        Results.DetailsS = [];
        for i=1:EstimOpt.NVarS; 
            Results.DetailsS(i,1) = Results.bhat(EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+EstimOpt.NVarM)+i);
            Results.DetailsS(i,3:4) = [Results.std(EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+EstimOpt.NVarM)+i),pv(Results.bhat(EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+EstimOpt.NVarM)+i),Results.std(EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5+EstimOpt.NVarM)+i))];
        end
        DetailsS0 = NaN(EstimOpt.NVarA,4);
        DetailsS0(1:EstimOpt.NVarS,1:4) = Results.DetailsS;
        if EstimOpt.NVarS <= EstimOpt.NVarA % will not work if NVarS > NVarA
            Results.R = [Results.R, DetailsS0]; 
        end
    end
    
    Results.chol = [Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5)),Results.std(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5)),pv(Results.bhat(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5)),Results.std(EstimOpt.NVarA+1:EstimOpt.NVarA*(EstimOpt.NVarA/2+1.5)))]; %Results.R = (1:EstimOpt.NVarA*(EstimOpt.NVarA/2+0.5),size(Results.R,2)+1:size(Results.R,2)+3) =
    Results.DetailsVcov = tril(ones(EstimOpt.NVarA)); ...
        choltmp = Results.chol(:,1);
    if sum(EstimOpt.Dist(2:end) >= 3 & EstimOpt.Dist(2:end) <= 5) > 0
        choltmp(EstimOpt.DiagIndex(EstimOpt.Dist(2:end) >= 3 & EstimOpt.Dist(2:end) <= 5)) = 1;
    end
    Results.DetailsVcov(Results.DetailsVcov == 1) = choltmp; ...
        if sum(EstimOpt.Dist(2:end) >= 3 & EstimOpt.Dist(2:end) <= 5) > 0
        choltmp = sqrt(sum(Results.DetailsVcov(EstimOpt.Dist(2:end) >= 3 & EstimOpt.Dist(2:end) <= 5,:).^2,2));
        Results.DetailsVcov(EstimOpt.Dist(2:end) >= 3 & EstimOpt.Dist(2:end) <= 5,:) = Results.DetailsVcov(EstimOpt.Dist(2:end) >= 3 & EstimOpt.Dist(2:end) <= 5,:)./choltmp(:, ones(1,EstimOpt.NVarA));
        end
        Results.DetailsVcov = Results.DetailsVcov*Results.DetailsVcov';
        Results.DetailsVcor = corrcov(Results.DetailsVcov);
end

EstimOpt.params = length(b0);
% if isfield(EstimOpt,'BActive')
% 	EstimOpt.params = EstimOpt.params - sum(EstimOpt.BActive == 0);
% end
EstimOpt.params = EstimOpt.params - sum(EstimOpt.BActive == 0) + sum(EstimOpt.BLimit == 1);

Results.stats = [Results.LL; Results_old.MNL0.LL;  1-Results.LL/Results_old.MNL0.LL;R2; ((2*EstimOpt.params-2*Results.LL))/EstimOpt.NObs; ((log(EstimOpt.NObs)*EstimOpt.params-2*Results.LL))/EstimOpt.NObs ;EstimOpt.NObs; EstimOpt.NP; EstimOpt.params];
%File Output
Results.EstimOpt = EstimOpt;
Results.OptimOpt = OptimOpt;
Results.INPUT = INPUT;
Results.Dist = transpose(EstimOpt.Dist(:,2:end));
EstimOpt.JSNVariables = find(EstimOpt.Dist(2:end) > 4 & EstimOpt.Dist(2:end) <= 7);
%% Tworzebnie templatek do printu
Template1 = {'DetailsA', 'DetailsV'};
Template2 = {'DetailsA', 'DetailsV'};
Names.DetailsA = EstimOpt.NamesA;
Heads.DetailsA = {'Means'};
Heads.DetailsV = {'Standard Deviations'};
ST = {};
if EstimOpt.NVarM > 0
    Template1 = [Template1, 'DetailsM'];
    Temp = cell(1, size(Template2,2));
    Temp(1,1) = {'DetailsM'};
    Template2 = [Template2; Temp];
    Heads.DetailsM = EstimOpt.NamesM;
end

if EstimOpt.NVarNLT > 0
    Template1 = [Template1, 'DetailsNLT0'];
    Temp = cell(1, size(Template2,2));
    Temp(1,1) = {'DetailsNLT0'};
    Template2 = [Template2; Temp];
    if EstimOpt.NLTType == 1
        Heads.DetailsNLT0 = {'Box-Cox transformation parameters'};
    elseif EstimOpt.NLTType == 2
        Heads.DetailsNLT0 = {'Yeo-Johnson transformation parameters'};
    end
end

if EstimOpt.Johnson > 0
    Heads.ResultsJ = {'Johnson location parameters';'Johnson scale parameters'}; %heads need to be written vertically
    Template1 = [Template1, 'ResultsJ'];
    Temp = cell(1, size(Template2,2));
    Temp(1,1) = {'ResultsJ'};
    Template2 = [Template2; Temp];
end

if EstimOpt.NVarS > 0
   Temp = cell(1, size(Template1,2));
   Temp(1,1) = {'DetailsS'};
   Template1 = [Template1; Temp];
   Temp = cell(1, size(Template2,2));
   Temp(1,1) = {'DetailsS'};
   Template2 = [Template2; Temp];
   Names.DetailsS = EstimOpt.NamesS;
   Heads.DetailsS = {'Covariates of Scale'};
   ST = {'DetailsS'};
end

%% Tworzenie naglowka
Head = cell(1,2);
if EstimOpt.FullCov == 0
    Head(1,1) = {'MXL_d'};
else
    Head(1,1) = {'MXL'};
end

if EstimOpt.WTP_space > 0
    Head(1,2) = {'in WTP-space'};
else
    Head(1,2) = {'in preference-space'};
end
%% Tworzenie stopki
Tail = cell(17,2);
Tail(2,1) = {'Model diagnostics'};
Tail(3:17,1) = {'LL at convergence' ;'LL at constant(s) only';  strcat('McFadden''s pseudo-R',char(178));strcat('Ben-Akiva-Lerman''s pseudo-R',char(178))  ;'AIC/n' ;'BIC/n'; 'n (observations)'; 'r (respondents)';'k (parameters)';' ';'Estimation method';'Simulation with';'Optimization method';'Gradient';'Hessian'};

if isfield(Results_old,'MNL0') && isfield(Results_old.MNL0,'LL')
    Tail(3:11,2) = num2cell(Results.stats);
end

if any(INPUT.W ~= 1)
    Tail(13,2) = {'weighted'};
else
    Tail(13,2) = {'maximum likelihood'};
end

switch EstimOpt.Draws
     case 1
     Tail(14,2) = {[num2str(EstimOpt.NRep),' ','pseudo-random draws']};
     case 2
     Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Latin Hypercube Sampling draws']};
     case  3
     Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Halton draws (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};
     case 4 
     Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Halton draws with reverse radix scrambling (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};
     case 5
     Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Sobol draws (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};
     case 6
     Tail(14,2) = {[num2str(EstimOpt.NRep),' ','Sobol draws with random linear scramble and random digital shift (skip = ', num2str(EstimOpt.HaltonSkip), '; leap = ', num2str(EstimOpt.HaltonLeap),')']};    
end

Tail(15,2) = {OptimOpt.Algorithm;};

if strcmp(OptimOpt.GradObj,'on')
    if EstimOpt.NumGrad == 0
        Tail(16,2) = {'user-supplied, analytical'};
    else
        Tail(16,2) = {['user-supplied, numerical ',num2str(OptimOpt.FinDiffType)]};
    end
else
    Tail(16,2) = {['built-in, ',num2str(OptimOpt.FinDiffType)]};
    
end

outHessian = [];
if isequal(OptimOpt.Algorithm,'quasi-newton')
    outHessian='off, ';
    switch EstimOpt.HessEstFix
        case 0
            outHessian = [outHessian, 'retained from optimization'];
        case 1
            outHessian = [outHessian, 'ex-post calculated using BHHH'];
        case 2
            outHessian = [outHessian, 'ex-post calculated using high-precision BHHH'];
        case 3
            outHessian = [outHessian, 'ex-post calculated numerically'];
        case 4
            outHessian = [outHessian, 'ex-post calculated analytically'];
    end
else
    if strcmp(OptimOpt.Hessian,'user-supplied')
        if EstimOpt.ApproxHess == 1
            outHessian = 'user-supplied, BHHH, ';
        else
            outHessian = 'user-supplied, analytical, ';
        end
    else
        outHessian = ['built-in, ', num2str(OptimOpt.HessUpdate), ', '];
    end
    switch EstimOpt.HessEstFix
        case 0
            outHessian = [outHessian, 'retained from optimization'];
        case 1
            outHessian = [outHessian, 'ex-post calculated using BHHH'];
        case 2
            outHessian = [outHessian, 'ex-post calculated using high-precision BHHH'];
        case 3
            outHessian = [outHessian, 'ex-post calculated numerically'];
        case 4
            outHessian = [outHessian, 'ex-post calculated analytically'];
    end
end

Tail(17,2) = {outHessian};
%% Tworzenie ResultsOut, drukowanie na ekran i do pliku .xls
if EstimOpt.Display~=0

    Results.R_out = genOutput(EstimOpt, Results, Head, Tail, Names, Template1, Template2, Heads, ST);
    fullOrgTemplate = which('template.xls');   
    currFld = pwd;
    
if EstimOpt.FullCov == 0
    if isfield(EstimOpt,'ProjectName')
        fullSaveName = strcat(currFld,'\MXL_d_results_',EstimOpt.ProjectName,'.xls');
    else
        fullSaveName = strcat(currFld,'\MXL_d_results.xls');
    end
else
    if isfield(EstimOpt,'ProjectName')
        fullSaveName = strcat(currFld,'\MXL_results_',EstimOpt.ProjectName,'.xls');
    else
        fullSaveName = strcat(currFld,'\MXL_results.xls');
    end
end
    
    copyfile(fullOrgTemplate, 'templateTMP.xls')
    fullTMPTemplate = which('templateTMP.xls');

    excel = actxserver('Excel.Application');
    excelWorkbook = excel.Workbooks.Open(fullTMPTemplate);
    excel.Visible = 1;
    excel.DisplayAlerts = 0;
    excelSheets = excel.ActiveWorkbook.Sheets;
    excelSheet1 = excelSheets.get('Item',1);
    excelSheet1.Activate;
    column = size(Results.R_out,2);
    columnName = [];    
        while column > 0
            modulo = mod(column - 1,26);
            columnName = [char(65 + modulo) , columnName];
            column = floor(((column - modulo) / 26));
        end

    rangeE = strcat('A1:',columnName,num2str(size(Results.R_out,1)));
    excelActivesheetRange = get(excel.Activesheet,'Range',rangeE);
    excelActivesheetRange.Value = Results.R_out;
    if isfield(EstimOpt,'xlsOverwrite') && EstimOpt.xlsOverwrite == 0
        i = 1;
        while exist(fullSaveName, 'file') == 2
            if isempty(strfind(fullSaveName, '('))
                pos = strfind(fullSaveName, '.xls');
                fullSaveName = strcat(fullSaveName(1:pos-1),'(',num2str(i),').xls');
            else
                pos = strfind(fullSaveName, '(');
                fullSaveName = strcat(fullSaveName(1:pos),num2str(i),').xls');
            end
            i = i+1;
        end
    end
    excelWorkbook.ConflictResolution = 2;
    SaveAs(excelWorkbook,fullSaveName);
    excel.DisplayAlerts = 0;
    excelWorkbook.Saved = 1;
    Close(excelWorkbook)
    Quit(excel)
    delete(excel)
    delete(fullTMPTemplate)
end
end