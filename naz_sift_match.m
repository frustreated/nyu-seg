clear; clc; close all;  addpath(genpath('.\')); % ind_ = @(A,r,c) A(r,c); 

iptsetpref('ImshowBorder','tight'); %??

Consts; Params;
params.seg.featureSet = consts.BFT_RGBD;
params.debug_visible = 'off';   
params.debug_fig = true;

conf.sampleSize  = length(consts.useNdx); %%% NB! Do not change this line, change sample size only by changing the range of consts.useNdx!
conf.sampleStage = [5 4 3 2 1];
conf.imgGap = 20; % size of gap between the images
conf.juncMarker = 'oy';
conf.siftMarker = 'oy';
conf.markerSize = 3;
conf.t = {
           [0.4 0.3], ...
           [0.6 0.3], ...
           [0.6 0.4], ...
           [0.4 0.2] ...
%           [0.7 0.5] ...
         };
     

for t_ = conf.t
rt = t_{1}(1);
t  = t_{1}(2);
 

for sampleStage = conf.sampleStage

% create subdir according to Sample size and Stage chosen
matchDir = sprintf('%ssample_%d/stage_%d/', consts.matchDir, conf.sampleSize, sampleStage);
if exist(matchDir, 'dir')~=7
     mkdir(matchDir);
end

% TODO verify if classifier and corresponding hierarchical segmentation exists for given sample size
for setInd = 1:length(consts.matchImgId)
idSet = consts.matchImgId{setInd};    % set of image IDs for cuurent match group (from consts.matchImgId cell array)
imgNum = length(idSet);               % number of images in chosen set


% CONSIDERRING ONLY PAIRS OF IMAGES (BY NOW)
if imgNum < 2 || imgNum > 2; continue; end; 
fprintf('Processing image pairs: %d<->%d, stage %d, rt = %1.1f, t = %1.1f ...', ...
                            idSet(1), idSet(2), sampleStage, rt, t); 

imRgb = cell(imgNum,1); % RGB images
im = cell(imgNum, 1);   % greyscale images 
x  = cell(imgNum, 1);   % junction x-coordinates
y  = cell(imgNum, 1);   % junction y-coordinates
D  = cell(imgNum, 1);   % sift descriptors

juncsIm = cell(imgNum, 1);
edgesIm = cell(imgNum, 1);

for i = 1:imgNum 
    load(sprintf(consts.imageRgbFilename,  idSet(i)), 'imgRgb');
    load(sprintf(consts.boundaryInfoPostMerge, conf.sampleSize, params.seg.featureSet, sampleStage, idSet(i)), 'boundaryInfo');
    edgesIm{i} = boundaryInfo.edges.fragments;     % edges from watershed segmentation
    juncsIm{i} = boundaryInfo.junctions.position;  % round means top-right pixel from junction point
    imgRgb = double(imgRgb)/255; % im2double
    
    %MARKER round!
    % extracting image and its junctions coordinates
    imRgb{i} = imgRgb;
    im{i} = rgb2gray(imRgb{i});
    x{i} = round(juncsIm{i}(:,1));
    y{i} = round(juncsIm{i}(:,2));
    conf.sizeX = size(imRgb{i},1);
    conf.sizeY = size(imRgb{i},2);
end
clear imgRgb boundaryInfo;
conf.imgGapStub = 0*ones(conf.sizeX, conf.imgGap, 3); % 1 == maximum intensity (255)
pairedImRgb = [imRgb{1} conf.imgGapStub imRgb{2}];

% show images
% --------------------------------------------------
h_img = figure('Visible','off');%params.debug_visible);
imshow(pairedImRgb); axis image; axis off; title(sprintf('Images #%d #%d', idSet(1), idSet(2)));    
if params.debug; print(h_img, '-dpng', sprintf('%s\\img%06d_stg%d_a.png', matchDir, idSet(1), sampleStage) ); end;


% show detected points
% --------------------------------------------------
h_pnts = figure('Visible',params.debug_visible);
imshow(pairedImRgb); axis image; axis off; hold on; 
title(sprintf('Images #%d #%d, stage%d', idSet(1), idSet(2), sampleStage)); 
plot(juncsIm{1}(:,1),juncsIm{1}(:,2), conf.juncMarker, 'MarkerSize', conf.markerSize);
plot(juncsIm{2}(:,1)+conf.sizeY+conf.imgGap, juncsIm{2}(:,2), conf.juncMarker, 'MarkerSize', conf.markerSize);
for i = 1:imgNum
   if i==1
       shift = 0;
   else
       shift = conf.sizeY + conf.imgGap;
   end
   edges = edgesIm{i};
   for k = 1:length(edges)
        plot(edges{k}(:,1)+shift, edges{k}(:,2), 'r', 'LineWidth', 0.5);
   end
end
%if params.debug;      print(h_pnts, '-dpng', sprintf('%s/img%06d_b.png', matchDir, idSet(1)) ); end;
if params.debug;     saveas(h_pnts, sprintf('%s/img%06d_stg%d_b.png', matchDir, idSet(1), sampleStage), 'png'); end
if params.debug_fig; saveas(h_pnts, sprintf('%s/img%06d_stg%d_b.fig', matchDir, idSet(1), sampleStage), 'fig'); end



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
%rt        = 0.6;                % 1NN/2NN distance ratio threshold (between 0 and 1)
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
h_match = figure('Visible',params.debug_visible);
imshow(pairedImRgb); axis image; axis off; hold on;
title( sprintf('Tentative correspondences: img #%d #%d, stage%d (rt=%1.1f)', idSet(1), idSet(2), sampleStage, rt) );
for i = 1:imgNum
   if i==1
       shift = 0;
   else
       shift = conf.sizeY + conf.imgGap;
   end
   edges = edgesIm{i};
   for k = 1:length(edges)
        plot(edges{k}(:,1)+shift, edges{k}(:,2), 'r', 'LineWidth', 0.5);
   end
end
plot(xat,yat,conf.siftMarker, 'MarkerSize', conf.markerSize);
plot(xbt+conf.sizeY+conf.imgGap,ybt,conf.siftMarker, 'MarkerSize', conf.markerSize);
hl = line([xat; xbt+conf.sizeY+conf.imgGap],[yat; ybt],'color','g');

if params.debug;     saveas(h_match, sprintf('%s/img%06d_stg%d_rt%1.1f.png', matchDir, idSet(1), sampleStage, rt), 'png'); end
if params.debug_fig; saveas(h_match, sprintf('%s/img%06d_stg%d_rt%1.1f.fig', matchDir, idSet(1), sampleStage, rt), 'fig'); end

%if length(D)<5; continue; end;


try
%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Robustly fit homography
%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Specify the inlier threshold (in noramlized image co-ordinates)
%t              = 0.3;
[Hab, inliers] = ransacfithomography([xat; yat], [xbt; ybt], t);

% show inliers
h_homo = figure('Visible',params.debug_visible); clf; clf;
imshow(pairedImRgb); axis image; axis off; hold on;
title(sprintf('Homography (ransac inliers): img #%d #%d, stg%d (rt=%1.1f, t=%1.1f)', idSet(1), idSet(2), sampleStage, rt, t));
for i = 1:imgNum
   if i==1
       shift = 0;
   else
       shift = conf.sizeY + conf.imgGap;
   end
   edges = edgesIm{i};
   for k = 1:length(edges)
        plot(edges{k}(:,1)+shift, edges{k}(:,2), 'r', 'LineWidth', 0.5);
   end
end
hl = line([xat(inliers); xbt(inliers)+conf.sizeY+conf.imgGap],[yat(inliers); ybt(inliers)],'color','g');
plot(xat(inliers),yat(inliers),conf.siftMarker, 'MarkerSize', conf.markerSize);
plot(xbt(inliers)+conf.sizeY+conf.imgGap,ybt(inliers), conf.siftMarker, 'MarkerSize', conf.markerSize);
if params.debug;     saveas(h_homo, sprintf('%s/img%06d_stg%d_t%1.1f_rt%1.1f.png', matchDir, idSet(1), sampleStage, t, rt), 'png'); end
if params.debug_fig; saveas(h_homo, sprintf('%s/img%06d_stg%d_t%1.1f_rt%1.1f.fig', matchDir, idSet(1), sampleStage, t, rt), 'fig'); end



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
catch ME
    fprintf('Exception in homography: %s\n', ME.message);
end
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
bbox=[-400 1200 -200 700];   % image space for mosaic
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

end

end