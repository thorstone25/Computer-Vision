%% 1D Gaussian filter

clc;
clear all;
close all;

 
srcFiles = dir([pwd '\EnterExitCrossingPaths2cor\*.jpg']);
% the folder in which ur images exists

%% prep display
figure(1), placeplot(1,1); fax(1) = gca;
figure(2), placeplot(2,2); fax(2) = gca;
figure(3), placeplot(3,3); fax(3) = gca;
figure(4), placeplot(4,4); fax(4) = gca;

%% gaussian kernel
sigma = 1;

% Determine filter length
filterLength = ceil(5*(sigma)) + mod(ceil(5*(sigma))-1,2);
n = (filterLength - 1)/2;
x = -n:n;

% Create 1-D Gaussian Kernel
c = 1/(sqrt(2*pi)*sigma);
gaussKernel = c * exp(-(x.^2)/(2*sigma^2));

% Normalize to ensure kernel sums to one
gaussKernel = gaussKernel/sum(gaussKernel);

% Create 1-D Derivative of Gaussian Kernel
derivGaussKernel = gradient(gaussKernel);
derivGaussKernel = derivGaussKernel/sum(abs(derivGaussKernel));
        
thresh = 10;

numFrames = length(derivGaussKernel);
%% process    
for i = 1 : 400
    
    for f = 1:numFrames
        filename = strcat([pwd '\EnterExitCrossingPaths2cor\'],srcFiles(i+f-1).name); 
        I = rgb2gray(imread(filename));
        bg(:,:,f) = double(I); % image-time matrix: (row,column,frame)
    end
       
    fr_size = size(bg);
    width = fr_size(2);
    height = fr_size(1);
    fg = zeros(height, width);
    
    %% 2D smoothing filter
    % choose filter
    smooth_type = 1;
    switch(smooth_type)
        case 1, % no smoothing
            filt = 1;
        case 2, % 3x3 box filter
            filt = ones([3 3]);
        case 3, % 5x5 box filter
            filt = ones([5 5]);
        case 4, % 2D Gaussian
            filt = bsxfun(@times,gaussKernel,gaussKernel.');
    end
    %normalize
    filt = filt ./ sum(sum(abs(filt)));
    
    % frame by frame convolution
    bg_smooth = zeros(size(bg));
    for f = 1:numFrames
        bg_smooth(:,:,f) = conv2(bg(:,:,f),filt,'same');
    end
    
    
    
   %% Correlate with 1D gaussian in the temporal domain
   frameFactor = bsxfun(@times,double(bg_smooth),shiftdim(derivGaussKernel,-1));
   fr_diff = sum(frameFactor,3);

   %% Get noise estimate for thresholding
   % get variance per pixel
   bg_var = sum( (bsxfun(@minus,bg_smooth,mean(bg_smooth,3)).^2), 3);
   % choose median variance across the camera : assumes that less than half
   % of the pixels are occluded with 
   bg_thresh = 3 * sqrt( median( bg_var ));
   
   
   %% Threshold
   Mask = image_threshold ( fr_diff, bg_thresh );

   
   %% Display
   imshow(uint8(bg(:,:,ceil(numFrames/2))),'Parent',fax(1));
   imshow(uint8(bg_smooth(:,:,ceil(numFrames/2))),'Parent',fax(2));
   imshow(uint8(fr_diff),'Parent',fax(3));
   imshow(Mask,'Parent',fax(4))
   pause(0.05);
end