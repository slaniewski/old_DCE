function f = LL_hlc(YY,Xa,Xc,Xstr,X_mea,Xmea_exp,err_sliced,EstimOpt,B)

beta = reshape(B(1:EstimOpt.NClass*EstimOpt.NVarA),[EstimOpt.NVarA,EstimOpt.NClass]);
if EstimOpt.WTP_space > 0
    beta(1:end-EstimOpt.WTP_space,:) = beta(1:end-EstimOpt.WTP_space,:).*beta(EstimOpt.WTP_matrix,:);
end
U = reshape(Xa*beta,[EstimOpt.NAlt,EstimOpt.NCT*EstimOpt.NP*EstimOpt.NClass]);
U = exp(U - max(U)); ...% NAlt*NCT*NP x NClass U(isnan(U)) = 0;... % do not include alternatives which were not available
U_sum = nansum(U,1);
P = reshape(sum(YY.*U./U_sum(ones(EstimOpt.NAlt,1),:),1),[EstimOpt.NCT,EstimOpt.NP*EstimOpt.NClass]); % NCT x NP*NClass
P(isnan(reshape(YY(1,:),[EstimOpt.NCT,EstimOpt.NP*EstimOpt.NClass]))) = 1;

probs = prod(P,1); % 1 x NP*NClass
probs = reshape(probs,[EstimOpt.NP,EstimOpt.NClass]);
probs = permute(probs(:,:,ones(EstimOpt.NRep,1)),[3 2 1]); %NRep x NClass x NP

bclass = [B(EstimOpt.NClass*EstimOpt.NVarA+1:EstimOpt.NClass*EstimOpt.NVarA+(EstimOpt.NVarC+EstimOpt.NLatent)*(EstimOpt.NClass-1));zeros(EstimOpt.NVarC+EstimOpt.NLatent,1)];
bclass = reshape(bclass,[EstimOpt.NVarC+EstimOpt.NLatent,EstimOpt.NClass]);
bstr = reshape(B(EstimOpt.NClass*EstimOpt.NVarA+(EstimOpt.NVarC+EstimOpt.NLatent)*(EstimOpt.NClass-1)+1:EstimOpt.NClass*EstimOpt.NVarA+(EstimOpt.NVarC+EstimOpt.NLatent)*(EstimOpt.NClass-1)+EstimOpt.NLatent*EstimOpt.NVarStr),[EstimOpt.NVarStr,EstimOpt.NLatent]);
bmea = B(EstimOpt.NClass*EstimOpt.NVarA+(EstimOpt.NVarC+EstimOpt.NLatent)*(EstimOpt.NClass-1)+EstimOpt.NLatent*EstimOpt.NVarStr+1:end);

LV_tmp = Xstr*bstr; % NP x NLatent
LV_tmp = reshape(permute(LV_tmp(:,:,ones(EstimOpt.NRep,1)),[2 3 1]),[EstimOpt.NLatent,EstimOpt.NRep*EstimOpt.NP]);
LV_tmp = LV_tmp + err_sliced; % NLatent x NRep*NP

LV = (LV_tmp - mean(LV_tmp,2))./std(LV_tmp,0,2); % normalilzing for 0 mean and std

p = zeros(EstimOpt.NP,EstimOpt.NRep);
for i = 1:EstimOpt.NP
    Xc_i = Xc(i,:);
    XXc = [Xc_i(ones(EstimOpt.NRep,1),:),LV(:,(i-1)*EstimOpt.NRep+1:i*EstimOpt.NRep)'];
    Pclass = exp(XXc*bclass); % NRep x NClass
    Pclass = Pclass./sum(Pclass,2); % NRep x NClass
    p(i,:) = sum(Pclass.*probs(:,:,i),2)'; 
    
end

L_mea = ones(EstimOpt.NP,EstimOpt.NRep);
l = 0;

if EstimOpt.NVarMeaExp > 0
    Xmea_exp = reshape(Xmea_exp,[1,EstimOpt.NP,EstimOpt.NVarMeaExp]);
    Xmea_exp = reshape(Xmea_exp(ones(EstimOpt.NRep,1),:,:),[EstimOpt.NP*EstimOpt.NRep,EstimOpt.NVarMeaExp]);
end

for i = 1:size(X_mea,2)
    if EstimOpt.MeaSpecMatrix(i) == 0 % OLS
        if EstimOpt.MeaExpMatrix(i) == 0
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)'];
        else
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)',Xmea_exp];
        end
        b = bmea(l+1:l+size(X,2)+1);
        L_mea = L_mea.*normpdf(X_mea(:,i),reshape(X*b(1:end-1),[EstimOpt.NRep,EstimOpt.NP])',exp(b(end)));
        l = l + size(X,2) + 1;
    elseif EstimOpt.MeaSpecMatrix(i) == 1 % MNL 
        UniqueMea = unique(X_mea(:,i));
        k = length(UniqueMea) - 1;
        if EstimOpt.MeaExpMatrix(i) == 0
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)'];
        else
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)',Xmea_exp];
        end
        V = exp(X*reshape([zeros(size(X,2),1);bmea(l+1:l+size(X,2)*k)],[size(X,2),k+1])); % NRep*NP x unique values of attitude
        V = permute(reshape(V./sum(V,2),[EstimOpt.NRep,EstimOpt.NP,k+1]),[2 1 3]); % NP x NRep x unique
        L = zeros(EstimOpt.NP,EstimOpt.NRep);
        for j = 1:length(UniqueMea)
            L(X_mea(:,i) == UniqueMea(j),:) = V(X_mea(:,i) == UniqueMea(j),:,j);
        end
        L_mea = L_mea.*L;
        l = l + size(X,2)*k; 
        
	elseif EstimOpt.MeaSpecMatrix(i) == 2 % Ordered Probit
        UniqueMea = unique(X_mea(:,i));
        k = length(UniqueMea) - 1;
        if EstimOpt.MeaExpMatrix(i) == 0
            X = LV(EstimOpt.MeaMatrix(:,i)' == 1,:)';
        else
            X = [LV(EstimOpt.MeaMatrix(:,i)' == 1,:)',Xmea_exp];
        end
        tmp = (EstimOpt.MeaExpMatrix(i) ~= 0)*EstimOpt.NVarMeaExp;
        b = bmea(l+1:l+k+size(X,2));
        Xb = reshape(X*b(1:sum(EstimOpt.MeaMatrix(:,i),1)+tmp),[EstimOpt.NRep,EstimOpt.NP])'; % NP x NRep
        alpha = cumsum([b(sum(EstimOpt.MeaMatrix(:,i))+tmp+1);exp(b(sum(EstimOpt.MeaMatrix(:,i))+tmp+2:end))]);
        L = zeros(EstimOpt.NP,EstimOpt.NRep);
        L(X_mea(:,i) == min(UniqueMea),:) = normcdf(alpha(1)-Xb(X_mea(:,i) == min(UniqueMea),:));
        L(X_mea(:,i) == max(UniqueMea),:) = 1 - normcdf(alpha(end)-Xb(X_mea(:,i) == max(UniqueMea),:));
        for j = 2:k
            L(X_mea(:,i) == UniqueMea(j),:) = normcdf(alpha(j)-Xb(X_mea(:,i) == UniqueMea(j),:)) - normcdf(alpha(j-1)-Xb(X_mea(:,i) == UniqueMea(j),:));
        end
        L_mea = L_mea.*L;
        l = l + k + size(X,2);
    elseif EstimOpt.MeaSpecMatrix(i) == 3 % Poisson
        if EstimOpt.MeaExpMatrix(i) == 0
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)'];
        else
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)',Xmea_exp];
        end
        b = bmea(l+1:l+size(X,2));
        fit = reshape(X*b,[EstimOpt.NRep,EstimOpt.NP])';
        lam = exp(fit);
        L = exp(fit.*X_mea(:,i)-lam)./min(gamma(X_mea(:,i)+1),realmax);
        L_mea = L_mea.*L;
        l = l + size(X,2);       
    elseif EstimOpt.MeaSpecMatrix(i) == 4 % NB
        if EstimOpt.MeaExpMatrix(i) == 0
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)'];
        else
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)',Xmea_exp];
        end
        b = bmea(l+1:l+size(X,2));
        fit = reshape(X*b,[EstimOpt.NRep,EstimOpt.NP])';
        lam = exp(fit);
        theta = exp(bmea(l+size(X,2)+1));
        u = theta./(theta+lam);  
        L = min(gamma(theta+X_mea(:,i)),realmax)./(gamma(theta).*min(gamma(X_mea(:,i)+1),realmax));
        L = L.*(u.^theta).*((1 - u).^X_mea(:,i));
        L_mea = L_mea.*L;
        l = l + size(X,2) + 1;
    elseif EstimOpt.MeaSpecMatrix(i) == 5 % ZIP
        if EstimOpt.MeaExpMatrix(i) == 0
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)']; 
        else
            X = [ones(EstimOpt.NRep*EstimOpt.NP,1),LV(EstimOpt.MeaMatrix(:,i)' == 1,:)',Xmea_exp];
        end
        bzip = bmea(l+1:l+size(X,2));
        bpoiss = bmea(l+size(X,2)+1:l+2*size(X,2));
        fit = reshape(X*bpoiss,[EstimOpt.NRep,EstimOpt.NP])';
        pzip = reshape(exp(X*bzip),[EstimOpt.NRep,EstimOpt.NP])';
        pzip = pzip./(1+pzip);
        L = zeros(EstimOpt.NP,EstimOpt.NRep);
        lam = exp(fit);
        IndxZIP = X_mea(:,i) == 0;
        L(IndxZIP,:) = pzip(IndxZIP,:) + (1-pzip(IndxZIP,:)).*exp(-lam(IndxZIP,:));
        L(~IndxZIP,:) = (1-pzip(~IndxZIP,:)).*exp(fit(~IndxZIP,:).*X_mea(~IndxZIP,i) - lam(~IndxZIP,:))./min(gamma(X_mea(~IndxZIP,i)+1),realmax);
        L_mea = L_mea.*L;
        l = l + 2*size(X,2);
    end
end
f = -log(max(realmin,mean(p.*L_mea,2)));

end