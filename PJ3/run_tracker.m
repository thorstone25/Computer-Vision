
%  Exploiting the Circulant Structure of Tracking-by-detection with Kernels
%
%  Main script for tracking, with a gaussian kernel.
%
%  Jo�o F. Henriques, 2012
%  http://www.isr.uc.pt/~henriques/


%choose the path to the videos (you'll be able to choose one with the GUI)
base_path = './tiger2/';
video_path = './tiger2/imgs/';


%parameters according to the paper
padding = 1;					%extra area surrounding the target
output_sigma_factor = 1/16;		%spatial bandwidth (proportional to target)
sigma = 0.2;					%gaussian kernel bandwidth
lambda = 1e-2;					%regularization
interp_factor = 0.075;			%linear interpolation factor for adaptation


clearvars A b C S Sp pos posvec

%notation: variables ending with f are in the frequency domain.

%ask the user for the video
%{
video_path = choose_video(base_path);
if isempty(video_path), return, end  %user cancelled
%}
[img_files, pos, target_sz, resize_image, ground_truth, video_path] = ...
	load_video_info(video_path);


%window size, taking padding into account
sz = floor(target_sz * (1 + padding));

%desired output (gaussian shaped), bandwidth proportional to target size
output_sigma = sqrt(prod(target_sz)) * output_sigma_factor;
[rs, cs] = ndgrid((1:sz(1)) - floor(sz(1)/2), (1:sz(2)) - floor(sz(2)/2));
y = exp(-0.5 / output_sigma^2 * (rs.^2 + cs.^2));
yf = fft2(y);

%store pre-computed cosine window
cos_window = hann(sz(1)) * hann(sz(2))';


time = 0;  %to calculate FPS
positions = zeros(numel(img_files), 2);  %to calculate precision
occluded = 0;
for frame = 1:numel(img_files),
	
    %% load image
	im = imread([video_path img_files{frame}]);
	if size(im,3) > 1,
		im = rgb2gray(im);
	end
	if resize_image,
		im = imresize(im, 0.5);
	end
	
	tic()
	
	%extract and pre-process subwindow
    if(0)
        x = get_subwindow(im, next_pos, sz, cos_window);
    else
        x = get_subwindow(im, pos, sz, cos_window);
    end
    %% calculate the gaussian response
    if frame > 1,
        %calculate response of the classifier at all locations
        k = dense_gauss_kernel(sigma, x, z);
        response = real(ifft2(alphaf .* fft2(k)));   %(Eq. 9)
        psr = PSR(response);
        
        % determine if occluded
        occluded = (PSR(response) < 10);
        
        %target location is at the maximum response
        [row, col] = find(response == max(response(:)), 1);
        pos = pos - floor(sz/2) + [row, col];
    end
    if(~occluded)
        %% adjust model
        %get subwindow at current estimated target position, to train classifer
        x = get_subwindow(im, pos, sz, cos_window);
        
        %Kernel Regularized Least-Squares, calculate alphas (in Fourier domain)
        k = dense_gauss_kernel(sigma, x);
        new_alphaf = yf ./ (fft2(k) + lambda);   %(Eq. 7)
        new_z = x;
        
        if frame == 1,  %first frame, train with a single image
            alphaf = new_alphaf;
            z = x;
            response = zeros(size(k));
            next_pos = [0 0];
        else
            %subsequent frames, interpolate model only if not occluded
            alphaf = (1 - interp_factor) * alphaf + interp_factor * new_alphaf;
            z = (1 - interp_factor) * z + interp_factor * new_z;
        end
    end
    
    for pp = 1
        
        %% store the state values
        n = 25; d = 2;
        
        % create vector of states (positions), posvec, which is (1 x n x 2)
        if(pp == 1)
            if(frame <= 2*n)
                % initially just populate vector
                posvec(1,frame,:) = shiftdim(pos,-1);
            else
                % drop the first, add the last
                if(occluded)
                    posvec = [posvec(1,2:end,:) shiftdim(next_pos,-1)];
                else
                    posvec = [posvec(1,2:end,:) shiftdim(pos,-1)];
                end
            end
        else
            % frame should be > 2*n
            psvctmp = posvec(1,1,:);
            posvec = [posvec(1,2:end,:) shiftdim(next_pos,-1)];
        end
        %% predict next position if occluded
        if(frame > 2*n)
            
            % smooth the data like a sly dog
            for m = 1:d
                posvec(:,:,m) = smooth(posvec(:,:,m),7);
            end
            
            % create Hankel matrix
            H = zeros([n,n,d]);
            for ii = 1:n
                for jj = 1:n
                    m = (ii-1)+ (jj-1) +1; % vector index
                    H(ii,jj,:) = posvec(1,m,:); % Hankel my ankle
                end
            end
            
            % build A matrix
            A = H(1:(end-1),1:(end-1),:);
            b = H(1:(end-1),end,:);
            C = H(end,1:(end-1),:);
            v = zeros(size(b));
            Ap = zeros(size(A));
            
            % lower complexity
            l = 10;
            for m = 1:d
                [U, ~, V] = svd(A(:,:,m));
                S = svd(A(:,:,m));
                Sp = zeros(size(S));
                Sp(1:l) = S(1:l);
                Ap(:,:,m) = U*diag(Sp)*V';
                
                % compute dynamic linear regressor coefficients, v
                v(1:n-1,:,m) = pinv(Ap(:,:,m)) * b(:,:,m);
                
                % predict next state (location)
                next_pos(m) = C(:,:,m)*v(:,:,m);
            end
            
        end
        if(pp == 2); posvec = [psvctmp posvec(1,1:end-1,:)]; end;
    end
	%% save position and calculate FPS
	if(occluded)
        positions(frame,:) = next_pos;
    else
        positions(frame,:) = pos;
    end
	time = time + toc();
    
	%% visualization
	rect_position = [pos([2,1]) - target_sz([2,1])/2, target_sz([2,1])];
	if frame == 1,  %first frame, create GUI
		f = figure('NumberTitle','off', 'Name',['Tracker - ' video_path]);
        im_handle = imshow(im, 'Border','tight', 'InitialMag',200);
		rect_handle = rectangle('Position',rect_position, 'EdgeColor','g');
        ax = axis;
        [Ny, Nx] = size(response);
        [Xx, Yy] = meshgrid(linspace(rect_position(1),rect_position(1) + rect_position(3),Nx),...
                            linspace(rect_position(2),rect_position(2) + rect_position(4),Ny));
		hold on;
        p_handle = pcolor(Xx,Yy,128+128*response); 
        shading interp; 
        set(p_handle,'FaceAlpha','interp',...
            'AlphaData',response.^3,...
            'FaceColor','g');
        np_handle = plot(next_pos(2),next_pos(1),'r+');
        set(np_handle,'visible','off');
        axis(ax);
        placeplot(7,f(1));
        f(2) = figure; placeplot(1,f(2)); axs2 = gca;
        f(3) = figure; placeplot(3,f(3)); axs3 = gca;
        
	else
		try  %subsequent frames, update GUI
			set(im_handle, 'CData', im)
			set(rect_handle, 'Position', rect_position)
            [Xx, Yy] = meshgrid(linspace(rect_position(1),rect_position(1) + rect_position(3),Nx),...
                linspace(rect_position(2),rect_position(2) + rect_position(4),Ny));
            set(p_handle,'AlphaData',response.^3);
            set(p_handle,'Xdata',Xx,'Ydata',Yy);
            set(np_handle,'Xdata',next_pos(2),'Ydata',next_pos(1));
            np_handle.Visible = 'on';
            if(occluded)
                np_handle.Color = 'r';
            else
                np_handle.Color = 'b';
            end
            set(gcf,'name',(sprintf('PSR ~ %0.2f\tNext position at (%i, %i) ?',...
                PSR(response),round(next_pos(1)),round(next_pos(2)))));
            plot(axs2,posvec(:,:,1));
            plot(axs3,posvec(:,:,2));
            
        catch %user has closed the window
            return
		end
	end
	
	drawnow
%  	pause(0.15)  %uncomment to run slower
%     if(~mod(frame,5)); waitforbuttonpress; end
end

if resize_image, positions = positions * 2; end

disp(['Frames-per-second: ' num2str(numel(img_files) / time)])

%show the precisions plot
show_precision(positions, ground_truth, video_path)

