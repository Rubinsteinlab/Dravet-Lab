
%% Extract 1st Block from Raw Data

EEG_first_block = data(datastart(1):dataend(1));
EMG_first_block = data(datastart(2):dataend(2));
save("EEG first block",'EEG_first_block')
save("EMG first block",'EMG_first_block')


%% Extract 2nd Block from Raw Data

EEG_second_block = data(datastart(1):dataend(1));
EMG_second_block = data(datastart(2):dataend(2));
save('EEG second block','EEG_second_block')
save('EMG second block','EMG_second_block')

%% Pre Processing

% First block pre-processing:
EMG_first_block = EMG_first_block - mean(EMG_first_block);
epoch_length = 5 * 1000; % 5 seconds at a sampling rate of 1000 Hz
num_epochs = floor(length(EEG_first_block) / epoch_length);
emg_band = [20  50]; % Cutoff frequencies for EMG
fs = 1000; % Sampling rate
cutoff_low = 0.5; % Low cutoff frequency (Hz) for EEG
cutoff_high = 50; % High cutoff frequency (Hz) for EEG
order = 4; % Filter order
[b_1, a_1] = butter(order, [cutoff_low/(fs/2), cutoff_high/(fs/2)], 'bandpass');
[b_2, a_2] = butter(order, [emg_band(1)/(fs/2), emg_band(2)/(fs/2)], 'bandpass');
for i = 1:num_epochs
    startIndex = (i - 1) * epoch_length + 1;
    endIndex = i * epoch_length;
    epoch_EEG_first_block{i} = EEG_first_block(startIndex:endIndex);
    epoch_EMG_first_block{i} = EMG_first_block(startIndex:endIndex);
    filteredEEG_first_block{i} = filtfilt(b_1, a_1, epoch_EEG_first_block{i});
    filteredEMG_first_block{i} = filtfilt(b_2, a_2, epoch_EMG_first_block{i});
end


% Do the same for the second block:
EMG_second_block = EMG_second_block - mean(EMG_second_block);
epoch_length = 5 * 1000;
num_epochs = floor(length(EEG_second_block) / epoch_length);
[b_1, a_1] = butter(order, [cutoff_low/(fs/2), cutoff_high/(fs/2)], 'bandpass');
[b_2, a_2] = butter(order, [emg_band(1)/(fs/2), emg_band(2)/(fs/2)], 'bandpass');
epoch_EEG_second_block = cell(1, num_epochs);
epoch_EMG_second_block = cell(1, num_epochs);
filteredEEG_second_block = cell(1, num_epochs);
filteredEMG_second_block = cell(1, num_epochs);
for i = 1:num_epochs
    startIndex = (i - 1) * epoch_length + 1;
    endIndex = i * epoch_length;
    epoch_EEG_second_block{i} = EEG_second_block(startIndex:endIndex);
    epoch_EMG_second_block{i} = EMG_second_block(startIndex:endIndex);
    filteredEEG_second_block{i} = filtfilt(b_1, a_1, epoch_EEG_second_block{i});
    filteredEMG_second_block{i} = filtfilt(b_2, a_2, epoch_EMG_second_block{i});
end


%% Step 2: Scoring Creation

% Initialize variables for both blocks
blocks = {'first', 'second'};

for block = blocks
    % Select the appropriate variables based on the block
    if strcmp(block, 'first')
        filteredEMG = filteredEMG_first_block;
        filteredEEG = filteredEEG_first_block;
    else
        filteredEMG = filteredEMG_second_block;
        filteredEEG = filteredEEG_second_block;
    end

    % Initialize RMS scores
    RMS_score = zeros(size(filteredEMG));
    for i = 1:size(filteredEMG, 2)
        RMS_score(i) = rms(filteredEMG{i});
    end
    RMS_score = movmean(RMS_score, [1 1]);

    % Define frequency bands
    delta = [0.5 5]; theta = [5 9]; alpha = [9 13]; beta = [13 30]; gamma = [30 100];
    windowSize = 512;
    overlap = 256;

    % Preallocate arrays for power spectral density (PSD) values
    deltaPxx = zeros(1, length(filteredEEG));
    thetaPxx = zeros(1, length(filteredEEG));
    alphaPxx = zeros(1, length(filteredEEG));
    betaPxx = zeros(1, length(filteredEEG));
    gammaPxx = zeros(1, length(filteredEEG));

    % Computation of PSD scores for each frequency band
    for i = 1:size(filteredEEG, 2)
        [pxx, f] = pwelch(filteredEEG{i}, hamming(windowSize), overlap, [], fs);

        % Extract and compute mean PSD for each frequency band
        deltaIndices = (f >= delta(1)) & (f <= delta(2));
        deltaPxx(i) = mean(pxx(deltaIndices));

        thetaIndices = (f >= theta(1)) & (f <= theta(2));
        thetaPxx(i) = mean(pxx(thetaIndices));

        alphaIndices = (f >= alpha(1)) & (f <= alpha(2));
        alphaPxx(i) = mean(pxx(alphaIndices));

        betaIndices = (f >= beta(1)) & (f <= beta(2));
        betaPxx(i) = mean(pxx(betaIndices));

        gammaIndices = (f >= gamma(1)) & (f <= gamma(2));
        gammaPxx(i) = mean(pxx(gammaIndices));
    end

    % Compute total power
    total_Pxx = alphaPxx + betaPxx + gammaPxx + deltaPxx + thetaPxx;

    % Normalize power values for each frequency band
    alphaPower = alphaPxx ./ total_Pxx;
    betaPower = betaPxx ./ total_Pxx;
    gammaPower = gammaPxx ./ total_Pxx;
    deltaPower = deltaPxx ./ total_Pxx;
    thetaPower = thetaPxx ./ total_Pxx;

    % Save the results in a structure for each block
    results.(block{:}).RMS_score = RMS_score;
    results.(block{:}).deltaPower = deltaPower;
    results.(block{:}).thetaPower = thetaPower;
    results.(block{:}).alphaPower = alphaPower;
    results.(block{:}).betaPower = betaPower;
    results.(block{:}).gammaPower = gammaPower;
end

SignalPower = struct();

blocks = {'first', 'second'};
for block = blocks
    % Extract the results for the current block
    alphaPower = results.(block{:}).alphaPower;
    betaPower = results.(block{:}).betaPower;
    gammaPower = results.(block{:}).gammaPower;
    deltaPower = results.(block{:}).deltaPower;
    thetaPower = results.(block{:}).thetaPower;
    RMS_score = results.(block{:}).RMS_score;

    % Store the results in the SignalPower structure for the current block
    SignalPower.(block{:}).Alpha = alphaPower';
    SignalPower.(block{:}).Beta = betaPower';
    SignalPower.(block{:}).Gamma = gammaPower';
    SignalPower.(block{:}).Delta = deltaPower';
    SignalPower.(block{:}).Theta = thetaPower';
    SignalPower.(block{:}).EMG = RMS_score';
end


%% EMG Clustering

% Initialize the clustering results for both blocks
blocks = {'first', 'second'};
for block = blocks
    % Extract the RMS_score for the current block
    RMS_score = results.(block{:}).RMS_score';

    % Clustering
    success = false;
    max_iterations = 100; % Maximum number of iterations to attempt

    while ~success
        try
            % Fit a Gaussian Mixture Model with k=5 components
            gmm = fitgmdist(RMS_score, 5, 'Replicates', 5); % Adjust 'Replicates' for better results

            % If the fitting succeeds without throwing an error, set success to true
            success = true;
        catch
            % If an error occurs (e.g., convergence failure), display a message and continue to the next iteration
            disp('Warning: Failed to converge. Retrying...');
        end

        % Increment the iteration counter
        max_iterations = max_iterations - 1;

        % Check if maximum iterations reached
        if max_iterations == 0
            error('Maximum number of iterations reached without convergence.');
        end
    end

    % Assign each data point to a cluster based on the highest probability
    idx = cluster(gmm, RMS_score);

    % Generate Thresholds:
    emg_centroid_high = max(gmm.mu);
    emg_centroid_second_high = max(gmm.mu(gmm.mu < max(gmm.mu)));
    emg_centroid_third_high = max(gmm.mu(gmm.mu < emg_centroid_second_high));
    emg_centroid_second_low = min(gmm.mu(gmm.mu > min(gmm.mu)));
    emg_centroid_low = min(gmm.mu);

    % Append clustering results to the SignalPower structure for the current block
    SignalPower.(block{:}).RMS_score = RMS_score;
    SignalPower.(block{:}).idx = idx;
    SignalPower.(block{:}).gmm = gmm;
    SignalPower.(block{:}).emg_centroid_high = emg_centroid_high;
    SignalPower.(block{:}).emg_centroid_second_high = emg_centroid_second_high;
    SignalPower.(block{:}).emg_centroid_third_high = emg_centroid_third_high;
    SignalPower.(block{:}).emg_centroid_second_low = emg_centroid_second_low;
    SignalPower.(block{:}).emg_centroid_low = emg_centroid_low;
    % Initialize the vector to store cluster assignments
    SignalPower.(block{:}).cluster_assignments = zeros(size(RMS_score));

    % Iterate over each data point
    for i = 1:length(RMS_score)
        % Assign the cluster index based on the mean values
        if RMS_score(i) >= emg_centroid_high
            SignalPower.(block{:}).cluster_assignments(i) = 1; % Assign to the cluster with max(gmm.mu)
        elseif RMS_score(i) >= emg_centroid_second_high
            SignalPower.(block{:}).cluster_assignments(i) = 2; % Assign to the cluster with the second highest gmm.mu
        elseif RMS_score(i) >= emg_centroid_third_high
            SignalPower.(block{:}).cluster_assignments(i) = 3; % Assign to the cluster with the third highest gmm.mu
        elseif RMS_score(i) >= emg_centroid_second_low
            SignalPower.(block{:}).cluster_assignments(i) = 4; % Assign to the cluster with the second lowest gmm.mu
        else
            SignalPower.(block{:}).cluster_assignments(i) = 5; % Assign to the cluster with the lowest gmm.mu
        end
    end
    % Plot the data points with different colors for each cluster
    figure;
    scatter(1:length(RMS_score), RMS_score, 50, idx, 'filled');
    title(['Gaussian Mixture Model Clustering Results for ', block{:}, ' Block']);
    xlabel('Data Point Index');
    ylabel('RMS Score');
    colormap('parula');
    colorbar;
    yline(emg_centroid_second_high);
    hold on;
    yline(emg_centroid_low);
end


%% Classification

% Initialize the classification results for both blocks
blocks = {'first', 'second'};
for block = blocks
    % Extract the RMS_score, Alpha, and Delta for the current block
    RMS_score = SignalPower.(block{:}).RMS_score;
    Alpha = SignalPower.(block{:}).Alpha;
    Delta = SignalPower.(block{:}).Delta;
    IDX = SignalPower.(block{:}).cluster_assignments;

    % Step 1: cut 15 first minutes of the recording + cut the recording from the end so it will end at the 55th minute
    RMS_score_cut = RMS_score(1:end);
    alpha_cut = Alpha(1:end);
    delta_cut = Delta(1:end);
    idx_cut = IDX(1:end);

    % Store the alpha and delta power cut for the current block
    SignalPower.(block{:}).Alpha_Power_Cut = alpha_cut;
    SignalPower.(block{:}).Delta_Power_Cut = delta_cut;
    SignalPower.(block{:}).RMS_score_cut = RMS_score_cut;
    SignalPower.(block{:}).idx_cut = idx_cut;
end

%% Create a struct with all relevant data

% Initialize the struct to hold data for both blocks
Data = struct();

blocks = {'first', 'second'};
for block = blocks
    % Extract the relevant data for the current block
    RMS_score_cut = SignalPower.(block{:}).RMS_score_cut;
    alpha_power_cut = SignalPower.(block{:}).Alpha_Power_Cut;
    delta_power_cut = SignalPower.(block{:}).Delta_Power_Cut;
    idx_cut = SignalPower.(block{:}).idx_cut;

    % Store the data in the Data struct for the current block
    Data.(block{:}).RMS_score_cut = RMS_score_cut;
    Data.(block{:}).alpha = alpha_power_cut;
    Data.(block{:}).delta = delta_power_cut;
    Data.(block{:}).idx_cut = idx_cut;
end


save('C4469 Data for histograms','Data')


%% Alpha&Delta analysis (Histograms creation)

% Create histograms for Delta and Alpha for both blocks
figure;
binEdge = 0:2:100;

% Subplot 1: Histogram of Delta for the first block (first row, first column)
subplot(3,2,1);
h1 = histogram(Data.first.delta, binEdge);
title('Delta (First Block)');
xlabel('Delta Values');
ylabel('Frequency');

% Subplot 2: Histogram of Delta for the second block (second row, first column)
subplot(3,2,3);
h2 = histogram(Data.second.delta, binEdge);
title('Delta (Second Block)');
xlabel('Delta Values');
ylabel('Frequency');

% Subplot 3: Overlayed histograms of Delta for both blocks (third row, first column)
subplot(3,2,5);
histogram(Data.first.delta, binEdge);
hold on;
histogram(Data.second.delta, binEdge);
title('Delta (First & Second Block)');
xlabel('Delta Values');
ylabel('Frequency');
legend('First Block', 'Second Block');
hold off;

% Subplot 4: Histogram of Alpha for the first block (first row, second column)
subplot(3,2,2);
histogram(Data.first.alpha, binEdge);
title('Alpha (First Block)');
xlabel('Alpha Values');
ylabel('Frequency');

% Subplot 5: Histogram of Alpha for the second block (second row, second column)
subplot(3,2,4);
histogram(Data.second.alpha, binEdge);
title('Alpha (Second Block)');
xlabel('Alpha Values');
ylabel('Frequency');

% Subplot 6: Overlayed histograms of Alpha for both blocks (third row, second column)
subplot(3,2,6);
histogram(Data.first.alpha, binEdge);
hold on;
histogram(Data.second.alpha, binEdge);
title('Alpha (First & Second Block)');
xlabel('Alpha Values');
ylabel('Frequency');
legend('First Block', 'Second Block');
hold off;

% Store histogram data in the S struct
S.delta_25 = h1.Data;
S.delta_36 = h2.Data;
S.centroids_25 = Data.first.idx_cut;
S.centroids_36 = Data.second.idx_cut;

% Determine the maximum length of the fields
fields = fieldnames(S);
maxLength = max(structfun(@numel, S));

% Pad the fields with NaN or empty values
for i = 1:numel(fields)
    fieldData = S.(fields{i});
    numElements = numel(fieldData);
    if isnumeric(fieldData)
        % Pad numeric fields with NaN
        S.(fields{i})(end+1:maxLength) = NaN;
    elseif iscell(fieldData)
        % Pad cell array fields with empty strings
        S.(fields{i})(end+1:maxLength) = {''};
    end
end


% Convert the struct to a table
T = struct2table(S);
writetable(T,'C4510.xlsx')

