function [LL,g,h]= LL_lc_MATlike(YY,Xa,Xc,Xs,MissingInd,W,EstimOpt,OptimOpt,b0)

% save tmp_LL_lc_MATlike;
% return

LLfun = @(B) LL_lc(YY,Xa,Xc,Xs,MissingInd,EstimOpt,B);

if isequal(OptimOpt.GradObj,'on')
    if EstimOpt.NumGrad == 0
        [f,j] = LLfun(b0);
        j(:,EstimOpt.BActive == 0) = 0;
        j = j.*W;
         g = sum(j,1)';
        if isequal(OptimOpt.Hessian,'user-supplied') == 1
            h = j'*j;
        end
    else % => EstimOpt.NumGrad == 1 
        f = LLfun(b0);  
        j = numdiff(LLfun,f,b0,isequal(OptimOpt.FinDiffType,'central'),EstimOpt.BActive);
        j = j.*W;
        g = sum(j,1)';   
        if isequal(OptimOpt.Hessian,'user-supplied') == 1
            h = j'*j;
        end
    end
else % No gradient
    EstimOpt.NumGrad = 1;
    f = LLfun(b0);   
end
f = f.*W;
LL = sum(f);