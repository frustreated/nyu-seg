clear; clc; close all;

addpath(genpath('.\'));
iptsetpref('ImshowBorder','tight')
ind_ = @(A,r,c) A(r,c); 

Consts; Params;
params.debug_visible = 'off';   % doesn't work because seg2framents.m loads Params.m again
outDir = strcat(consts.datasetDir, consts.matchDir);

for setInd = 1:15 %length(consts.matchImgId)
idSet = consts.matchImgId{setInd};    % set of image IDs for cuurent match group (from matchImgId cell array)
imgNum = length(idSet);               % number of images in chosen set

if imgNum < 2 || imgNum > 2; continue; end; % skipping single images & triplets
fprintf('Processing image pairs: %d, %d ...\n', idSet(1), idSet(2)); 

imRgb = cell(imgNum,1); % RGB images
im = cell(imgNum, 1);   % greyscale images 
x  = cell(imgNum, 1);   % junction x-coordinates
y  = cell(imgNum, 1);   % junction y-coordinates
D  = cell(imgNum, 1);   % sift descriptors

juncsIm = cell(imgNum, 1);
edgesIm = cell(imgNum, 1);

for i = 1:imgNum 
    load(sprintf(consts.imageRgbFilename,  idSet(i)), 'imgRgb');
    load(sprintf(consts.watershedFilename, idSet(i)), 'boundaryInfo');
    edgesIm{i} = boundaryInfo.edges.fragments;     % edges from watershed segmentation
    juncsIm{i} = boundaryInfo.junctions.position;  % round means top-right pixel from junction point
    imgRgb = double(imgRgb)/255; % im2double
    
    %MARKER round!
    % extracting image and its junctions coordinates
    imRgb{i} = imgRgb;
    im{i} = rgb2gray(imRgb{i});
    x{i} = round(juncsIm{i}(:,1));
    y{i} = round(juncsIm{i}(:,2));
end
clear imgRgb boundaryInfo;

% show images
h_img = figure('Visible',params.debug_visible); clf;
for i=1:imgNum
    subplot(1,imgNum,i);
    imagesc(imRgb{i}); axis image; axis off; title(['Image ', num2str(idSet(i))]);    
end
if params.debug; print(h_img, '-dpng', sprintf('%s\\img%06d_a.png', outDir, idSet(1)) ); end;

% show detected points
h_pnts = figure('Visible',params.debug_visible); clf;
for i = 1:imgNum
   subplot(1,imgNum,i);
   imagesc(imRgb{i}); axis image; title(['Image ', num2str(idSet(i))]); hold on;
   plot(juncsIm{i}(:,1),juncsIm{i}(:,2), '+y', 'MarkerSize',2);
   edges = edgesIm{i};
   for k = 1:length(edges)
        plot(edges{k}(:,1), edges{k}(:,2), 'r', 'LineWidth', 0.5);
   end
end
if params.debug; print(h_pnts, '-dpng', sprintf('%s\\img%06d_b.png', outDir, idSet(1)) ); end;



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Extract descriptors (heavily blurred 21xb1 patches)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

for i = 1:imgNum
   [D{i}, x{i}, y{i}] = ext_desc(im{i}, x{i}, y{i}); 
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Compute tentative matches between image 1 (a) and 2 (b) 
% by matching local features
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
rt        = 0.2; % 0.4          % 1NN/2NN distance ratio threshold (between 0 and 1)
D2        = dist2(D{1}',D{2}'); % compute pair-wise distances between descriptors
[Y,I]     = sort(D2,2);         % sort distances
rr        = Y(:,1)./Y(:,2);     % compute D. Lowes' 1nn/2nn ratio test
inD12     = find(rr<rt);        % take only points with a 1nn/2nn ratio below 0.8
I         = I(inD12);           % select matched points
xat       = x{1}(inD12);
yat       = y{1}(inD12);
xbt       = x{2}(I);
ybt       = y{2}(I);

% show all tentative matches
h_match = figure('Visible',params.debug_visible); clf;
subplot(121);
imshow(imRgb{1}); hold on;
plot(xat,yat,'+g');
hl = line([xat; xbt],[yat; ybt],'color','y');
title( sprintf('Tentative correspondences: img %d (rt=%1.1f)', idSet(1), rt) );
axis off;

subplot(122);
imshow(imRgb{2}); hold on;
plot(xbt,ybt,'og');
title( sprintf('img %d', idSet(1)) );

if params.debug; print(h_match, '-dpng', sprintf('%s\\img%06d_rt%1.1f.png', outDir, idSet(1), rt) ); end;

if length(D)<5; continue; end;

%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Robustly fit homography
%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Specify the inlier threshold (in noramlized image co-ordinates)
t              = 0.2; % 0.3
[Hab, inliers] = ransacfithomography([xat; yat], [xbt; ybt], t);

% show inliers
h_homo = figure('Visible',params.debug_visible); clf; clf;
subplot(121);
imshow(imRgb{1}); hold on;
hl = line([xat(inliers); xbt(inliers)],[yat(inliers); ybt(inliers)]);
set(hl,'color','y');
plot(xat(inliers),yat(inliers),'+g');
title(sprintf('Inliers: img %d (rt=%1.1f, t=%1.1f)', idSet(1), rt, t));

subplot(122); 
imshow(imRgb{2}); hold on;
plot(xbt(inliers),ybt(inliers),'og');
title( sprintf('img %d', idSet(1)) );
if params.debug; print(h_homo, '-dpng', sprintf('%s\\img%06d_rt%1.1f_t%1.1f.png', outDir, idSet(1), rt, t) ); end;



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Visualize homography
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% vgg_gui_H(imc,imb,Hcb);


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Warp and composite images
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % %     figure(5); clf;
% % %     bbox=[-400 1200 -200 700]   % image space for mosaic
% % %     % warp image b to mosaic image using an identity homogrpahy
% % %     % Image b is chosen as the reference frame
% % %     iwb = vgg_warp_H(imRgb{2}, eye(3), 'linear', bbox);
% % %     imshow(iwb); axis image;
% % % 
% % %     % warp image 1 to the reference mosaic frame (image 2) 
% % %     figure(6); clf;
% % %     iwa = vgg_warp_H(imRgb{1}, Hab, 'linear', bbox);  % warp image a to the mosaic image
% % %     imshow(iwa); axis image;
% % %     imagesc(double(max(iwb,iwa))); % combine images into a common mosaic (take maximum value of the two images)



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Estimate homography between images 3 and 2.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Based on the code above, write code to:
% 1. Compute tentative matches between images 2 and 3 
% 2. Robustly fit homography Hcb
% 3. Re-estimate homography from inliers

% ---- 

if imgNum < 3
    %pause;
    close all;
    continue
end;

rt        = 0.5;              % 1NN/2NN distance ratio threshold (between 0 and 1)
D2        = dist2(Dc',Db'); % compute pair-wise distances between descriptors
[Y,I]     = sort(D2,2);     % sort distances
rr        = Y(:,1)./Y(:,2); % compute D. Lowes' 1nn/2nn ratio test
inD12     = find(rr<rt);   % take only points with a 1nn/2nn ratio below 0.8
I         = I(inD12);       % select matched points
xct       = x{3}(inD12);
yct       = y{3}(inD12);
xbt       = x{2}(I);
ybt       = y{2}(I);

% show all tentative matches
figure(1); clf;
imagesc(imargb); hold on;
plot(xat,yat,'+g');
hl = line([xct; xbt],[yct; ybt],'color','y');
title('Tentative correspondences');
axis off;

%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Robustly fit homography
%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Specify the inlier threshold (in noramlized image co-ordinates)
t              = 0.3; 
[Hcb, inliers] = ransacfithomography([xct; yct], [xbt; ybt], t);

% show inliers
figure(4); clf;
imagesc(imargb); hold on;
hl = line([xct(inliers); xbt(inliers)],[yct(inliers); ybt(inliers)]);
set(hl,'color','y');
plot(xct(inliers),yct(inliers),'+g');
title('Inliers');

figure(5); clf;
bbox=[-400 1200 -200 700]   % image space for mosaic
% warp image b to mosaic image using an identity homogrpahy
% Image b is chosen as the reference frame
iwb = vgg_warp_H(imbrgb, eye(3), 'linear', bbox);
imshow(iwb); axis image;

% warp image 1 to the reference mosaic frame (image 2) 
figure(6); clf;
iwc = vgg_warp_H(imcrgb, Hcb, 'linear', bbox);  % warp image a to the mosaic image
imshow(iwc); axis image;
imagesc(double(max(iwb,iwc))); % combine images into a common mosaic (take maximum value of the two images)


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Final warping and compositing
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
figure(7); clf;
iwc = vgg_warp_H(imcrgb, Hcb, 'linear', bbox);  % warp image c to mosaic image
imshow(iwc); axis image;

figure(8); clf;
imagesc(max(iwc,double(max(iwb,iwa)))); % combine images into a common mosaic
axis image; axis off;

% pause;
close all;
end


