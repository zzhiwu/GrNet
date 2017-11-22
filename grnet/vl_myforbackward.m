function res = vl_myforbackward(net, x, dzdy, res, varargin)
% VL_SIMPLENN  Evaluates a simple GrNet

opts.res = [] ;
opts.conserveMemory = false ;
opts.sync = false ;
opts.disableDropout = false ;
opts.freezeDropout = false ;
opts.accumulate = false ;
opts.cudnn = true ;
opts.skipForward = false;
opts.backPropDepth = +inf ;
opts.epsilon = 5e-5;
opts.p = 10;

% opts = vl_argparse(opts, varargin);

n = numel(net.layers) ;

if (nargin <= 2) || isempty(dzdy)
  doder = false ;
else
  doder = true ;
end

if opts.cudnn
  cudnn = {'CuDNN'} ;
else
  cudnn = {'NoCuDNN'} ;
end

gpuMode = isa(x, 'gpuArray') ;

if nargin <= 3 || isempty(res)
  res = struct(...
    'x', cell(1,n+1), ...
    'dzdx', cell(1,n+1), ...
    'dzdw', cell(1,n+1), ...
    'aux', cell(1,n+1), ...
    'time', num2cell(zeros(1,n+1)), ...
    'backwardTime', num2cell(zeros(1,n+1))) ;
end
if ~opts.skipForward
  res(1).x = x ;
end


% -------------------------------------------------------------------------
%                                                              Forward pass
% -------------------------------------------------------------------------

for i=1:n
  if opts.skipForward, break; end;
  l = net.layers{i} ;
  res(i).time = tic ;
  switch l.type
    case 'frmap'
      res(i+1).x = vl_myfrmap(res(i).x, l.weight) ; 
    case 'fc'
      res(i+1).x = vl_myfc(res(i).x, l.weight) ; 
    case 'reorth'
      [res(i+1).x, res(i)] = vl_myreorth(res(i)) ;      
    case 'pooling'
      [res(i+1).x, res(i)] = v1_mypooling(res(i), l.pool) ;
    case 'eigmap'
      [res(i+1).x, res(i)] = vl_myeigmap(res(i), opts.p) ;   
    case 'projmap'
      res(i+1).x = vl_myprojmap(res(i).x) ;
    case 'softmaxloss'
      res(i+1).x = vl_mysoftmaxloss(res(i).x, l.class) ; 

    case 'custom'
      res(i+1) = l.forward(l, res(i), res(i+1)) ;
    otherwise
      error('Unknown layer type %s', l.type) ;
  end
  % optionally forget intermediate results
  forget = opts.conserveMemory ;
  forget = forget & (~doder || strcmp(l.type, 'relu')) ;
  forget = forget & ~(strcmp(l.type, 'loss') || strcmp(l.type, 'softmaxloss')) ;
  forget = forget & (~isfield(l, 'rememberOutput') || ~l.rememberOutput) ;
  if forget
    res(i).x = [] ;
  end
  if gpuMode & opts.sync
    % This should make things slower, but on MATLAB 2014a it is necessary
    % for any decent performance.
    wait(gpuDevice) ;
  end
  res(i).time = toc(res(i).time) ;
end

% -------------------------------------------------------------------------
%                                                             Backward pass
% -------------------------------------------------------------------------

if doder
  res(n+1).dzdx = dzdy ;
  for i=n:-1:max(1, n-opts.backPropDepth+1)
    l = net.layers{i} ;
    res(i).backwardTime = tic ;
    switch l.type
      case 'orthmap'
        [res(i).dzdx, res(i).dzdw] = ...
             vl_myfrmap(res(i).x, l.weight, res(i+1).dzdx) ;

      case 'fc'
        [res(i).dzdx, res(i).dzdw]  = ...
              vl_myfc(res(i).x, l.weight, res(i+1).dzdx) ; 
      case 'reorth'
        res(i).dzdx = vl_myreorth(res(i), res(i+1).dzdx) ;
      case 'pooling'
        res(i).dzdx = v1_mypooling(res(i), l.pool, res(i+1).dzdx) ;
 
      case 'eigmap'
        res(i).dzdx = vl_myeigmap(res(i), opts.p, res(i+1).dzdx) ; 
      case 'projmap'
        res(i).dzdx = vl_myprojmap(res(i).x, res(i+1).dzdx) ;
      case 'softmaxloss'
        res(i).dzdx = vl_mysoftmaxloss(res(i).x, l.class, res(i+1).dzdx) ;
      case 'custom'
        res(i) = l.backward(l, res(i), res(i+1)) ;
    end
    if opts.conserveMemory
      res(i+1).dzdx = [] ;
    end
    if gpuMode & opts.sync
      wait(gpuDevice) ;
    end
    res(i).backwardTime = toc(res(i).backwardTime) ;
  end
end

