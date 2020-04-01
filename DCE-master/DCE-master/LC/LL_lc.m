function [f,g] = LL_lc(YY,Xa,Xc,Xs,MissingInd,EstimOpt,B)

% save tmp_LL_lc
% return

NP = EstimOpt.NP;
NAlt = EstimOpt.NAlt;
NCT = EstimOpt.NCT;
NClass = EstimOpt.NClass;
NVarA = EstimOpt.NVarA;
NVarC = EstimOpt.NVarC;
NVarS = EstimOpt.NVarS;
WTP_space = EstimOpt.WTP_space;
WTP_matrix = EstimOpt.WTP_matrix;
BActiveClass = EstimOpt.BActiveClass;
RealMin = EstimOpt.RealMin;


if sum(BActiveClass == 0,1) == 0
    Bclass = reshape(B(1:NClass*NVarA),[NVarA,NClass]);
else
    Bclass = B(1:NVarA)*ones(1,NClass);
    for i = 1:(NClass-1)
        Bclass(BActiveClass == 1,i+1) = B(NVarA+(i-1)*sum(BActiveClass,1)+1:NVarA+i*sum(BActiveClass,1));
    end
end
if WTP_space > 0
    Bclass_nonwtp = Bclass; % for gradient
    Bclass(1:end-WTP_space,:) = Bclass(1:end-WTP_space,:).*Bclass(WTP_matrix,:);
end
if NVarS > 0
    bs = reshape(B(NClass*NVarA+1:NClass*(NVarA+NVarS)),[NVarS,NClass]);
    Scale = exp(Xs*bs);
    U = reshape((Xa*Bclass).*Scale,[NAlt,NCT*NP*NClass]); % NAlt x NCT*NP*NClass
else
    U = reshape(Xa*Bclass,[NAlt,NCT*NP*NClass]); % NAlt x NCT*NP*NClass
end

U = exp(U-max(U));
U(MissingInd == 1) = 0; % do not include alternatives which were not available
U_probs =  U./sum(U,1); % NAlt x NCT*NP*NClass
P = reshape(sum(YY.*U_probs,1),[NCT,NP*NClass]); % NCT x NP*NClass
P(reshape(MissingInd(1:NAlt:end),[NCT,NP*NClass]) == 1) = 1; % do not include choice tasks which were not completed
probs = prod(P,1);
probs = reshape(probs,[NP,NClass]);

if sum(BActiveClass == 0,1) == 0
    PClass = exp(Xc*reshape([B(NClass*(NVarA+NVarS)+1:end);zeros(NVarC,1)],[NVarC,NClass]));
else
    PClass = exp(Xc*reshape([B((NClass-1)*sum(BActiveClass,1)+NVarA+NClass*NVarS+1:end);zeros(NVarC,1)],[NVarC,NClass]));
end

PClass = PClass./sum(PClass,2);

probs_x = probs.*PClass;
f = sum(probs_x,2);

if nargout == 2 % function value + gradient
    U_probs = reshape(U_probs,[NAlt,NCT*NP,1,NClass]);
    probs_x = reshape(probs_x,[NP,1,NClass]);
    if NVarS > 0
        Scale = reshape(Scale,[NP*NCT*NAlt,1,NClass]);        
    end
    
    if WTP_space == 0
        if NVarS > 0
            XXa = reshape(Xa.*Scale,[NAlt,NCT*NP,NVarA,NClass]);
            Xa_tmp = reshape(Xa(YY(:,1:NCT*NP) == 1,:,:).*Scale(1:NAlt:end,:,:),[NCT,NP,NVarA*NClass]) ; % NCT*NP x NVarA
        else
            XXa = reshape(Xa,[NAlt,NCT*NP,NVarA,1]);
            Xa_tmp = reshape(Xa(YY(:,1:NCT*NP) == 1,:,ones(NClass,1)),[NCT,NP,NVarA*NClass]) ; % NCT*NP x NVarA
        end
        Xhat = reshape(sum(U_probs.*XXa,1),[NCT,NP,NVarA*NClass]); % NCT x NP x NClass*NVarA
        F = reshape(sum(Xa_tmp - Xhat,1),[NP,NVarA*NClass]); % NP x NVarA*NClass
        g1 = F.*reshape(probs_x(:,ones(NVarA,1),:),[NP,NVarA*NClass]); % gradient for choice parameters
        if NVarS > 0
            bss = reshape(Bclass,[1,1,NVarA*NClass]);
            Ftmp = Xa_tmp - Xhat;
            Ftmp = sum(reshape(Ftmp.*bss,[NCT*NP,NVarA,NClass]),2);
            gs = reshape(Ftmp.*Xs(1:NAlt:end,:,:),[NCT,NP,NVarS*NClass]);
            gs = reshape(sum(gs,1),[NP,NVarS*NClass]); % NP x NVarS*NClass
            gs = gs.*reshape(probs_x(:,ones(NVarS,1),:),[NP,NVarS*NClass]); % gradient for choice parameters
            g1 = [g1,gs];
        end
    else
        alphaX = zeros(NAlt*NCT*NP,NVarA-WTP_space,NClass);
        for i = 1:NClass %maybe this loop is unnecessary?
            alphaX(:,:,i) = Xa(:,1:(NVarA-WTP_space)).*(Bclass(WTP_matrix,i)');
        end
        if NVarS > 0
            alphaX = alphaX.*Scale;
        end
        alphaXX = reshape(alphaX,[NAlt,NCT*NP,NVarA-WTP_space,NClass]);
        Xhat1 = reshape(sum(U_probs.*alphaXX,1),[NCT,NP,(NVarA-WTP_space)*NClass]); % NCT x NP x NClass*NVarA
        alphaX = reshape(alphaX(YY(:,1:NCT*NP) == 1,:,:),[NCT,NP,(NVarA-WTP_space)*NClass]);
        F1 = reshape(sum(alphaX-Xhat1,1),[NP,(NVarA-WTP_space)*NClass]); % NP x (NVarA - WTP_space)*NClass
        g11 = F1.*reshape(probs_x(:,ones(1,NVarA - WTP_space),:),[NP,(NVarA-WTP_space)*NClass]);
        
        % cost variables
        if WTP_space == 1
            pX = Xa(:,NVarA*ones(NClass,1)) + Xa(:,1:NVarA-1)*Bclass_nonwtp(1:NVarA-1,:);% NAlt*NCT*NP x NClass
            if NVarS > 0
                pX = pX.*squeeze(Scale);
            end
            pXX = reshape(pX,[NAlt,NCT*NP,NClass]);
            Xhat2 = reshape(sum(squeeze(U_probs).*pXX,1),[NCT*NP,NClass]); % NCT*NP x NClass
            F2 = reshape(pX(YY(:,1:NCT*NP) == 1,:)-Xhat2,[NCT,NP,NClass]);
            if NVarS > 0
                bss = reshape(Bclass(NVarA,:),[1,1,NClass]);
                gs = reshape(F2.*bss,[NCT,NP,1,NClass]);
                gs = gs.*reshape(Xs(1:NAlt:end,:,ones(NClass,1)),[NCT,NP,NVarS,NClass]);
                gs = reshape(sum(gs,1),[NP,NVarS,NClass]).*probs_x;
            end
            g12 = squeeze(sum(F2,1)).*squeeze(probs_x);
        else
            pX = zeros(NAlt*NCT*NP,WTP_space,NClass);
            for i = 1:WTP_space
                pX(:,i,:) = Xa(:,(NVarA-WTP_space+i)*ones(NClass,1)) + Xa(:,WTP_matrix == NVarA-WTP_space+i)*Bclass_nonwtp(WTP_matrix == NVarA-WTP_space+i,:);
            end
            if NVarS > 0
                pX = pX.*Scale;
            end
            pXX = reshape(pX,[NAlt,NCT*NP,WTP_space,NClass]);
            Xhat2 = reshape(sum(U_probs.*pXX,1),[NCT*NP,WTP_space,NClass]); % NCT*CP x WTP_space x NClass
            F2 = reshape(pX(YY(:,1:NCT*NP) == 1,:,:)-Xhat2,[NCT,NP,WTP_space*NClass]);
            probs_x = reshape(probs_x(:,ones(WTP_space,1),:),[NP,WTP_space*NClass]);
            if NVarS > 0
                bss = reshape(Bclass(NVarA-WTP_space+1:end,:),[1,1,WTP_space*NClass]);
                gs = sum(reshape(F2.*bss,[NCT,NP,WTP_space,NClass]),3); % NCT x NP x 1 x NClass
                gs = gs.*reshape(Xs(1:NAlt:end,:,:),[NCT,NP,NVarS,NClass]);
                gs = reshape(sum(gs,1),[NP,NVarS,NClass]).*probs_x;
            end            
            g12 = squeeze(sum(F2,1)).*probs_x;
        end        
        g1 = zeros(NP,NVarA,NClass);
        g1(:,1:(NVarA-WTP_space),:) = reshape(g11,[NP,NVarA-WTP_space,NClass]);
        g1(:,(NVarA-WTP_space+1):end,:) = reshape(g12,[NP,WTP_space,NClass]);
        g1 = reshape(g1,[NP,NVarA*NClass]);
        if NVarS>0
            g1 = [g1,reshape(gs,[NP,NVarS*NClass])];
        end
    end
    
    % class membership parameters
    PClass_tmp = reshape(PClass(:,1:NClass-1),[NP,1,NClass-1]);
    PClass_tmp = reshape(PClass_tmp(:,ones(NClass-1,1),:),[NP,(NClass-1)^2]);
    PClass = reshape(PClass(:,:,ones(NClass-1,1)),[NP,NClass*(NClass-1)]);
    indx1 = 1:NClass - 1;
    indx1 = indx1 + (indx1 - 1)*NClass;
    PClass(:,indx1) = PClass(:,indx1).*(1 - PClass(:,indx1));
    indx2 = 1:NClass*(NClass - 1);
    indx2(indx1) = [];
    PClass(:,indx2) = -PClass(:,indx2).*PClass_tmp;
    PClass = reshape(PClass,[NP,NClass,NClass-1]);
    g2 = sum(PClass.*probs,2); % NP x 1 xNClass-1
    g2 = g2.*Xc;
    g2 = reshape(g2,[NP,NVarC*(NClass-1)]); % gradient for class probability parameters
    g = -[g1,g2];
    g = g./f;
end

if RealMin == 1
    f = -log(max(f,realmin));
else
    f = -log(f);
end
