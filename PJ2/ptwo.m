clc;
clear all;
close all;

srcFiles = dir([pwd '\DanaOffice\*.jpg']);
numFrames = size(srcFiles);
ImGreySet= zeros(340,512,10,'uint8');
for f = 1:numFrames(1)
    filename = strcat([pwd '\DanaOffice\'],srcFiles(f).name);
    I(:,:,:,f) = imread(filename);
    ImGreySet(:,:,f) = uint8(rgb2gray(I(:,:,:,f))); % image-time matrix: (row,column,frame)
end

index = 0;
I1 = I(:,:,:,1+index);
I2 = I(:,:,:,2+index);
Igrey1 = ImGreySet(:,:,1+index);
Igrey2 = ImGreySet(:,:,2+index);

%% Apply Corner Detector for the image Set
CornerSet1 = harris(Igrey1,1,4,25000,0);
CornerSet2 = harris(Igrey2,1,4,25000,0);

% figure, clf
% image(I1); axis image;
% % image(Igrey1); colormap(gray(256)); axis image;
% hold on
% plot(CornerSet1(:,2),CornerSet1(:,1),'+')
% title('detected corners overlay over the input image')
% 
% figure, clf
% image(I2);  axis image;
% % image(Igrey2); colormap(gray(256)); axis image;
% hold on
% plot(CornerSet2(:,2),CornerSet2(:,1),'+')
% title('detected corners overlay over the input image')


[r, c]=size(Igrey1);
Thresh = 0.8;

k = int8(1);

%% NCC
for i = 1:length(CornerSet1)
    % Choosing a neighborhood for the corner point of first image
    CornerPoint1 = CornerSet1(i,:);
    if (CornerPoint1(1)<=10) || (CornerPoint1(2)<= 10) || (CornerPoint1(1)> r-10) || (CornerPoint1(2)> c-10)
        continue;
    end
    nbhd1 = I1((CornerPoint1(1)-10):(CornerPoint1(1)+10),(CornerPoint1(2)-10):(CornerPoint1(2)+10));
    
    NCCArray = zeros(1,length(CornerSet2));
    for j = 1: length(CornerSet2)
        % Choosing a neighborhood for the corner point of first image
        CornerPoint2 = CornerSet2(j,:);
        if ((CornerPoint2(1)<10) || (CornerPoint2(2)< 10) || (CornerPoint2(1)> r-10) || (CornerPoint2(2)> c-10) )
            continue;
        end
        nbhd2 = I2((CornerPoint2(1)-10):(CornerPoint2(1)+10),(CornerPoint2(2)-10):(CornerPoint2(2)+10));
        NCC = normxcorr2(nbhd1, nbhd2);
        NCCArray(1,j) = NCC(21,21);
    end
    [LargestNCC, jIndex]= max(NCCArray(:));
    if  LargestNCC > Thresh
        CorrespMap(k,1:2) = [i jIndex];
        k=k+1;
    end
end
Np = length(CorrespMap);
%% 
Cset1Index = CorrespMap(:,1);  Cset2Index = CorrespMap(:,2);

figure;
CombinedImage = cat(2,I1,I2);
imshow(CombinedImage);
hold on

xs1 = CornerSet1(:,2); 
ys1 = CornerSet1(:,1); 
xs2 = CornerSet2(:,2); 
ys2 = CornerSet2(:,1);

plot(xs1, ys1, 'gs','LineWidth',2);
plot(xs2+c+1, ys2, 'rx','LineWidth',2);


%% Plotting initial point correspondences
hold on
for i = 1: Np
    %
    x1(i) = CornerSet1(Cset1Index(i),2);
    y1(i) = CornerSet1(Cset1Index(i),1);
    
    %
    x2(i) = CornerSet2(Cset2Index(i),2)+c+1;
    y2(i) = CornerSet2(Cset2Index(i),1);

    plot([x x+c+1], ...
    [y1 y2]);
end

%% RANSAC to find Homography

h_bestimate = zeros([8 1]);

% estimator error function
h_err = @(h)(h);

for jj = 1:Np
% choose 4 random points at a time
i = randi([1 Np], [1 4]);

x = x1(i);
y = y1(i);
xp = x2(i);
yp = y2(i);

% build A matrix
for ii = 4:-1:1
A(2*ii-1:2*ii,:) = [x(ii) y(ii) 1 0 0 0 -x(ii)*xp(ii) -y(ii)*xp(ii);...
    0 0    0 x(ii) y(ii) 1 -x(ii)*yp(ii) -y(ii)*yp(ii)];
end

% build b matrix
b = reshape([xp;yp],8,[]);

% get homography estimate
h_est = A \ b;

% get error of the estimate
h_error = h_err(h_est);

% update estimate
if(h_error < h_err(h_bestimate))
    h_bestimate = h_est;
end

end

%% MSAC to check

