%% ================= Organize Raw Data  =================
% Loads EEG L/R (or single EEG) + EMG, picks platform (NLX/LabChart),
% applies AD conversion, saves EEG_accusleep.mat / EMG_accusleep.mat.
fprintf('\n=== Organize Raw Data ===\n');

% Platform choice → ADvolts + default fs
p = menu('Acquisition platform?','Neuralynx (NLX)','LabChart');
if p==0, error('Cancelled.'); end
if p==1
    ADvolts = 0.00000030517578125;  % NLX
    fs      = 2000;
else
    ADvolts = 1;                    % LabChart (already volts)
    fs      = 1000;                 % adjust if your lab default differs
end
a = inputdlg({'Sampling rate (Hz):'},'Confirm fs',1,{num2str(fs)});
if isempty(a), error('Cancelled.'); end
fs = str2double(a{1}); if isnan(fs)||fs<=0, error('Invalid fs'); end
fprintf('ADvolts=%.17g, fs=%g Hz\n',ADvolts,fs);

% Pick EEG file(s): one (mono) OR two (L & R)
[eegFiles,eegPath] = uigetfile('*.mat','Select EEG file(s): one or two','MultiSelect','on');
if isequal(eegFiles,0), error('No EEG file selected'); end
if ischar(eegFiles), eegFiles={eegFiles}; end

% Pick EMG file
[emgFile,emgPath] = uigetfile('*.mat','Select EMG file');
if isequal(emgFile,0), error('No EMG file selected'); end

% ---- Load EEG #1 ----
S1 = load(fullfile(eegPath,eegFiles{1}));
if     isfield(S1,'merged_vector'), EEG1 = double(S1.merged_vector(:)).';
elseif isfield(S1,'EEG'),           EEG1 = double(S1.EEG(:)).';
elseif isfield(S1,'signal'),        EEG1 = double(S1.signal(:)).';
elseif isfield(S1,'data'),          EEG1 = double(S1.data(:)).';
elseif isfield(S1,'x'),             EEG1 = double(S1.x(:)).';
else
    fn1 = fieldnames(S1);
    if numel(fn1)==1
        EEG1 = double(S1.(fn1{1})(:)).';
    else
        error('Could not find EEG vector in %s', eegFiles{1});
    end
end

% ---- Load EEG #2 (optional) ----
if numel(eegFiles)==2
    S2 = load(fullfile(eegPath,eegFiles{2}));
    if     isfield(S2,'merged_vector'), EEG2 = double(S2.merged_vector(:)).';
    elseif isfield(S2,'EEG'),           EEG2 = double(S2.EEG(:)).';
    elseif isfield(S2,'signal'),        EEG2 = double(S2.signal(:)).';
    elseif isfield(S2,'data'),          EEG2 = double(S2.data(:)).';
    elseif isfield(S2,'x'),             EEG2 = double(S2.x(:)).';
    else
        fn2 = fieldnames(S2);
        if numel(fn2)==1
            EEG2 = double(S2.(fn2{1})(:)).';
        else
            error('Could not find EEG vector in %s', eegFiles{2});
        end
    end
    L = min(numel(EEG1),numel(EEG2));
    EEG = (EEG1(1:L) + EEG2(1:L))/2;
    fprintf('EEG: averaged L/R (%d samples)\n',L);
else
    EEG = EEG1;
    fprintf('EEG: single file (%d samples)\n',numel(EEG));
end

% ---- Load EMG ----
SEMG = load(fullfile(emgPath,emgFile));
if     isfield(SEMG,'merged_vector'), EMG = double(SEMG.merged_vector(:)).';
elseif isfield(SEMG,'EMG'),           EMG = double(SEMG.EMG(:)).';
elseif isfield(SEMG,'emg'),           EMG = double(SEMG.emg(:)).';
elseif isfield(SEMG,'signal'),        EMG = double(SEMG.signal(:)).';
elseif isfield(SEMG,'data'),          EMG = double(SEMG.data(:)).';
elseif isfield(SEMG,'x'),             EMG = double(SEMG.x(:)).';
else
    fnE = fieldnames(SEMG);
    if numel(fnE)==1
        EMG = double(SEMG.(fnE{1})(:)).';
    else
        error('Could not find EMG vector in %s', emgFile);
    end
end
fprintf('EMG: %d samples\n',numel(EMG));

% ---- Apply conversion & save ----
EEG = EEG.*ADvolts; EMG = EMG.*ADvolts;
if numel(EEG)~=numel(EMG)
    warning('EEG (%d) and EMG (%d) lengths differ; downstream epoching truncates to min.',numel(EEG),numel(EMG));
end
save('EEG_accusleep.mat','EEG');
save('EMG_accusleep.mat','EMG');
fprintf('Saved: EEG_accusleep.mat, EMG_accusleep.mat\n');


%% ========================== Step 1: Pre-processing ==========================
% Demean EMG, epoch both signals to fixed-length windows, and band-pass filter.
% Uses 'fs' from the previous section and keeps your original band choices.

fprintf('\n=== Step 1: Pre-processing ===\n');

% ---- Epoch length (seconds) ----
answ = inputdlg({'Epoch length (sec):'}, 'Pre-processing', 1, {'5'});
if isempty(answ), error('Cancelled.'); end
epoch_sec = str2double(answ{1});
if isnan(epoch_sec) || epoch_sec <= 0, error('Invalid epoch length'); end
samples_per_epoch = round(fs * epoch_sec);

% ---- Align lengths & truncate to whole epochs ----
N = min(numel(EEG), numel(EMG));
N = floor(N / samples_per_epoch) * samples_per_epoch;   % whole number of epochs
if N == 0, error('Signals are too short for one full epoch.'); end
EEG = EEG(1:N);
EMG = EMG(1:N);

% ---- Demean EMG ----
EMG = EMG - mean(EMG);

% ---- Filter settings ----
fs_eeg = fs;                        % keep explicit
fs_emg = fs;
eeg_band   = [0.5 100];             % Hz
emg_band   = [20 50];               % Hz
order      = 4;

[b_eeg, a_eeg] = butter(order, [eeg_band(1)   eeg_band(2)]/(fs_eeg/2), 'bandpass');
[b_emg, a_emg] = butter(order, [emg_band(1)   emg_band(2)]/(fs_emg/2), 'bandpass');

% ---- Epoch & filter ----
num_epochs = N / samples_per_epoch;
epoch_EEG   = cell(1, num_epochs);
epoch_EMG   = cell(1, num_epochs);
filteredEEG = cell(1, num_epochs);
filteredEMG = cell(1, num_epochs);

for i = 1:num_epochs
    idx1 = (i-1)*samples_per_epoch + 1;
    idx2 =  i   *samples_per_epoch;

    epoch_EEG{i} = EEG(idx1:idx2);
    epoch_EMG{i} = EMG(idx1:idx2);

    % zero-phase filtering
    filteredEEG{i} = filtfilt(b_eeg, a_eeg, epoch_EEG{i});
    filteredEMG{i} = filtfilt(b_emg, a_emg, epoch_EMG{i});
end

fprintf('Pre-processing done: %d epochs of %g s (fs=%g Hz)\n', num_epochs, epoch_sec, fs);

%% ========================== Step 2: Scoring Creation =========================
% Computes per-epoch EMG RMS and EEG band powers (Welch), then normalizes.

fprintf('\n=== Step 2: Scoring Creation ===\n');

% ---- Bands (Hz) ----
bandNames = {'delta','theta','alpha','beta','gamma'};
bandEdges = [ 0.5  5;
              5    9;
              9    13;
              13   30;
              30   100 ];

numE = numel(filteredEEG);
numB = numel(bandNames);

% ---- EMG RMS (per epoch) ----
RMS_score = zeros(1,numE);
for i = 1:numE
    RMS_score(i) = rms(filteredEMG{i});
end
RMS_score = movmean(RMS_score, [1 1]);   % light smoothing

% ---- Welch parameters (relative to fs) ----
% Use ~2 s windows, 75% overlap (safe defaults for 5 s epochs)
win_s   = 2; 
win     = max(64, min(round(win_s*fs), numel(filteredEEG{1})));  % clamp to epoch length
ovlp    = round(0.75*win);

% ---- Band power per epoch ----
bandPower = zeros(numB, numE);
totalPxx  = zeros(1, numE);

for i = 1:numE
    x = filteredEEG{i};
    [pxx,f] = pwelch(x, hamming(win), ovlp, [], fs);

    for j = 1:numB
        idx = (f >= bandEdges(j,1)) & (f <= bandEdges(j,2));
        % mean power in band (handle empty idx if edges exceed Nyquist)
        bandPower(j,i) = mean(pxx(idx));
    end
    totalPxx(i) = sum(bandPower(:,i));
end

% ---- Normalize across bands (row vectors) ----
den = totalPxx + eps;
deltaPower = bandPower(1,:)./den;
thetaPower = bandPower(2,:)./den;
alphaPower = bandPower(3,:)./den;
betaPower  = bandPower(4,:)./den;
gammaPower = bandPower(5,:)./den;

fprintf('Scoring: computed RMS + band powers for %d epochs (fs=%g Hz)\n', numE, fs);


%% =============================== EMG clustering ===============================
% K=5 fixed. Robust init + standardization to avoid centroid collapse.

R = RMS_score(:);                              % Nx1
medR = median(R); stdR = std(R);
isOut = abs(R - medR) > 3*stdR;                % outliers
R_clean = R; R_clean(isOut) = medR;            % replace with median, keep indices

% Standardize for numerics (fit in Z, report on original scale)
muR = median(R_clean); sR = std(R_clean) + eps;
Z = (R_clean - muR) / sR;                      % ~unit scale

% K=5, quantile-based initial means in Z-space (stable for 1-D)
K = 5;
qz = prctile(Z, linspace(5,95,K));             % e.g., ~[5, 28.75, 52.5, 76.25, 95]%
mu0 = qz(:);                                   % Kx1
sig0 = repmat(var(Z), [1 1 K]);                % 1x1xK diagonal covs in 1-D
pi0  = ones(1,K) / K;                          % equal mix

NRUNS = 200;                                   % (1000 works too; 200 is usually enough)
opts  = statset('MaxIter',2000,'Display','off');

post_sum   = zeros(numel(Z), K);
mu_collect = zeros(NRUNS, K);
succ = 0;

for r = 1:NRUNS
    try
        % small jitter on initial means to avoid identical local optima
        mu_jit = mu0 + 0.02*randn(K,1);        % 2% jitter in Z units

        S = struct();
        S.mu = mu_jit;                         % Kx1
        S.Sigma = sig0;                        % 1x1xK (1-D diagonal)
        S.ComponentProportion = pi0;           % 1xK

        gm = fitgmdist(Z, K, ...
            'Start', S, ...
            'CovarianceType','diagonal', ...
            'SharedCovariance', false, ...
            'RegularizationValue', 1e-6, ...
            'Options', opts, ...
            'Replicates', 1);

        % Align by ascending mean on ORIGINAL scale using posterior weights
        P = posterior(gm, Z);                   % N x K
        muK = zeros(1,K);
        for k = 1:K
            w = P(:,k); muK(k) = sum(R_clean.*w) / (sum(w)+eps);
        end
        [mu_sorted, ord] = sort(muK, 'ascend'); % align
        post_sum = post_sum + P(:, ord);
        mu_collect(succ+1, :) = mu_sorted;
        succ = succ + 1;
    catch
        % skip failed run
    end
end

if succ == 0
    error('All GMM fits failed. Check RMS variance or lower RegularizationValue.');
end
if succ < NRUNS
    warning('GMM fits succeeded %d/%d runs; averaging successful runs only.', succ, NRUNS);
    mu_collect = mu_collect(1:succ, :);
end

% Average posteriors → final labels (1..5 = low→high EMG)
post_avg = post_sum / succ;
[~, idx] = max(post_avg, [], 2);

% Final centroids = mean of run-wise aligned centroids (original scale)
mu_mean = mean(mu_collect, 1);                 % 1x5 ascending
emg_centroid_low         = mu_mean(1);
emg_centroid_second_low  = mu_mean(2);
emg_centroid_third_high  = mu_mean(3);
emg_centroid_second_high = mu_mean(4);
emg_centroid_high        = mu_mean(5);

% Plot
figure;
scatter((1:numel(R_clean))', R_clean, 12, idx, 'filled');
title(sprintf('EMG GMM (K=5), robust init, averaged over %d runs', succ));
xlabel('Epoch'); ylabel('RMS');
colormap('parula'); colorbar; hold on;
yline(emg_centroid_low,'--'); yline(emg_centroid_second_high,'--'); hold off;

% Highest-activity band → "active wake"
active_wake = find(R_clean >= emg_centroid_high);

% Probabilities sorted by DESCENDING centroid (for downstream logic)
[~, desc] = sort(mu_mean, 'descend');
sorted_Wake_probabilities = post_avg(:, desc);


%% ============================== Assign Clusters ==============================
% Convention: 1 = highest EMG activity, 5 = lowest (atonia)

% Using GMM labels from previous section (idx: 1..5 = low→high)
idx_low2high = idx;                  % from EMG clustering (posterior argmax)
cluster_assignments = 6 - idx_low2high;   % invert → 1=high, 5=low
cluster_assignments = cluster_assignments(:).';   % row vector


%% ================================ REM search =================================
% Feature: theta/delta ratio, modulated by EMG activity level 

theta_ratio = (thetaPower ./ (deltaPower + eps)) .* cluster_assignments;  % row
T = theta_ratio(:);                              % column for modeling

% --- Outlier cleaning: replace |x - median| > 3*STD with median ---
medT = median(T);
stdT = std(T);
isOut = abs(T - medT) > 3*stdT;
T_clean = T;
T_clean(isOut) = medT;

% --- Standardize for numerics; fit in Z, report on original scale ---
muT = median(T_clean);
sT  = std(T_clean) + eps;
Z   = (T_clean - muT) / sT;

% --- Robust GMM (K=5), quantile-based initialization + jitter, multi-run avg ---
K = 5;
qz  = prctile(Z, linspace(5,95,K));        % initial means (ascending) in Z
mu0 = qz(:);
sig0 = repmat(var(Z), [1 1 K]);            % 1x1xK (1-D diagonal)
pi0  = ones(1,K) / K;

NRUNS = 200;                                % 200–1000; 200 is usually enough
opts  = statset('MaxIter',2000,'Display','off');

post_sum   = zeros(numel(Z), K);
mu_collect = zeros(NRUNS, K);
succ = 0;

for r = 1:NRUNS
    try
        mu_jit = mu0 + 0.02*randn(K,1);    % small jitter in Z units

        S = struct();
        S.mu = mu_jit;                     % Kx1
        S.Sigma = sig0;                    % 1x1xK
        S.ComponentProportion = pi0;       % 1xK

        gm = fitgmdist(Z, K, ...
            'Start', S, ...
            'CovarianceType','diagonal', ...
            'SharedCovariance', false, ...
            'RegularizationValue', 1e-6, ...
            'Options', opts, ...
            'Replicates', 1);

        P = posterior(gm, Z);              % N x K (on Z)
        % Weighted component means on ORIGINAL scale
        muK = zeros(1,K);
        for k = 1:K
            w = P(:,k); muK(k) = sum(T_clean.*w) / (sum(w)+eps);
        end
        [mu_sorted, ord] = sort(muK, 'ascend');  % align by mean
        post_sum = post_sum + P(:, ord);
        mu_collect(succ+1, :) = mu_sorted;
        succ = succ + 1;
    catch
        % skip failed run
    end
end

if succ == 0
    error('All REM GMM fits failed. Check variance in theta/delta feature.');
elseif succ < NRUNS
    warning('REM GMM fits succeeded %d/%d runs; averaging successful runs.', succ, NRUNS);
    mu_collect = mu_collect(1:succ, :);
end

% --- Final labels & thresholds ---
post_avg = post_sum / succ;                 % averaged posteriors (aligned)
[~, idx_theta_low2high] = max(post_avg, [], 2);   % 1..5 = low→high theta ratio

mu_mean = mean(mu_collect, 1);              % 1x5 ascending (original scale)
sleeping_theta_centroid_high = mu_mean(5);  % highest mean = REM-ish threshold

% Plot
figure;
scatter((1:numel(T_clean))', T_clean, 12, idx_theta_low2high, 'filled');
title(sprintf('REM search (theta/delta * EMG level), K=5, averaged over %d runs', succ));
xlabel('Epoch'); ylabel('Theta/Delta × EMG-level');
colormap('parula'); colorbar; hold on;
yline(sleeping_theta_centroid_high,'--'); hold off;

% REM epochs = above highest centroid (your original criterion)
REM = find(T_clean > sleeping_theta_centroid_high);

% Probabilities sorted by DESCENDING centroid (for UD logic later)
[~, desc] = sort(mu_mean, 'descend');
sorted_REM_probabilities = post_avg(:, desc);


%% ================================ NREM search ================================
% Feature: delta power × EMG activity level 

delta_ratio = (deltaPower .* cluster_assignments);   % row
D = delta_ratio(:);                                  % column for modeling

% --- Outlier cleaning: replace |x - median| > 3*STD with median ---
medD = median(D);
stdD = std(D);
isOut = abs(D - medD) > 3*stdD;
D_clean = D;
D_clean(isOut) = medD;

% --- Standardize for numerics; fit in Z, report on original scale ---
muD = median(D_clean);
sD  = std(D_clean) + eps;
Z   = (D_clean - muD) / sD;

% --- Robust GMM (K=5), quantile-based init + jitter, multi-run averaging ---
K = 5;
qz  = prctile(Z, linspace(5,95,K));        % initial means (ascending) in Z
mu0 = qz(:);
sig0 = repmat(var(Z), [1 1 K]);            % 1x1xK (1-D diagonal)
pi0  = ones(1,K) / K;

NRUNS = 200;                                % 200–1000; increase if you like
opts  = statset('MaxIter',2000,'Display','off');

post_sum   = zeros(numel(Z), K);
mu_collect = zeros(NRUNS, K);
succ = 0;

for r = 1:NRUNS
    try
        mu_jit = mu0 + 0.02*randn(K,1);    % small jitter in Z units

        S = struct();
        S.mu = mu_jit;                     % Kx1
        S.Sigma = sig0;                    % 1x1xK
        S.ComponentProportion = pi0;       % 1xK

        gm = fitgmdist(Z, K, ...
            'Start', S, ...
            'CovarianceType','diagonal', ...
            'SharedCovariance', false, ...
            'RegularizationValue', 1e-6, ...
            'Options', opts, ...
            'Replicates', 1);

        P = posterior(gm, Z);              % N x K
        % Weighted means on ORIGINAL scale for alignment
        muK = zeros(1,K);
        for k = 1:K
            w = P(:,k); muK(k) = sum(D_clean.*w) / (sum(w)+eps);
        end
        [mu_sorted, ord] = sort(muK, 'ascend');  % align by mean
        post_sum = post_sum + P(:, ord);
        mu_collect(succ+1, :) = mu_sorted;
        succ = succ + 1;
    catch
        % skip failed run
    end
end

if succ == 0
    error('All NREM GMM fits failed. Check variance in delta feature.');
elseif succ < NRUNS
    warning('NREM GMM fits succeeded %d/%d runs; averaging successful runs.', succ, NRUNS);
    mu_collect = mu_collect(1:succ, :);
end

% --- Final labels & thresholds ---
post_avg = post_sum / succ;                 % averaged posteriors (aligned)
[~, idx_delta_low2high] = max(post_avg, [], 2);   % 1..5 = low→high delta

mu_mean = mean(mu_collect, 1);              % 1x5 ascending (original scale)
sleeping_delta_centroid_high = mu_mean(5);  % highest mean ~ strongest delta (NREM-ish)

% Plot
figure;
scatter((1:numel(D_clean))', D_clean, 12, idx_delta_low2high, 'filled');
title(sprintf('NREM search (delta × EMG level), K=5, averaged over %d runs', succ));
xlabel('Epoch'); ylabel('Sleeping Delta');
colormap('parula'); colorbar; hold on;
yline(sleeping_delta_centroid_high,'--'); hold off;

% NREM epochs = above highest centroid (your original criterion)
NREM = find(D_clean > sleeping_delta_centroid_high);

% Probabilities sorted by DESCENDING centroid (for UD logic later)
[~, desc] = sort(mu_mean, 'descend');
sorted_NREM_probabilities = post_avg(:, desc);

%% ================================ Classification ================================
% Labels: 1=REM, 2=Wake, 3=NREM, 4=Undefined

N = numel(RMS_score);

% Ensure row vectors
cluster_assignments = cluster_assignments(:).';
active_wake        = active_wake(:).';
REM                = REM(:).';
NREM               = NREM(:).';

% If delta_ratio from NREM section was cleaned into D_clean, expose it here:
if ~exist('delta_ratio','var') && exist('D_clean','var')
    delta_ratio = D_clean(:).';   % use cleaned delta feature for rules
end

% --- Initialize all as Undefined ---
labels = 4*ones(1, N);

% --- Seed classes from detectors ---
labels(REM)         = 1;   % REM from theta search
labels(active_wake) = 2;   % Wake from EMG high-activity band

% --- Enforce REM atonia: REM must be in EMG cluster 5 (atonia) ---
labels(labels==1 & cluster_assignments < 5) = 4;

% --- Build possible-sleep zone: ±5 epochs around confirmed REM, excluding active wake ---
rem_mask  = false(1,N); rem_mask(REM)  = true;
wake_mask = false(1,N); wake_mask(active_wake) = true;
sleep_zone = conv(double(rem_mask), ones(1,11), 'same') > 0;  % ±5
sleep_zone = sleep_zone & ~wake_mask;

% --- Confirm NREM: only where NREM detector AND in sleep_zone ---
nrem_mask = false(1,N); nrem_mask(NREM) = true;
nrem_confirmed = nrem_mask & sleep_zone;
labels(nrem_confirmed) = 3;

% --- NREM must have low EMG (clusters 4–5) ---
labels(labels==3 & cluster_assignments < 4) = 4;

% --- Bridge isolated epoch between wakes: W ? W  → center = W ---
mid = 2:N-1;
bridge_mask = labels(mid-1)==2 & labels(mid+1)==2;
labels(mid(bridge_mask)) = 2;

% --- Further Wake classification: UD + high EMG + low delta → Wake ---
labels(labels==4 & cluster_assignments < 3 & delta_ratio < sleeping_delta_centroid_high) = 2;

% --- Further NREM classification: if previous is NREM & current low EMG & high delta ---
prev_is_nrem = [false, labels(1:end-1)==3];
labels(prev_is_nrem & (cluster_assignments > 3) & (delta_ratio > 0.9*sleeping_delta_centroid_high)) = 3;

% --- Further REM persistence: keep REM only if prior 5 epochs contain REM or NREM ---
sleep_prev = (labels==1) | (labels==3);
prev5 = movsum(sleep_prev, [5 0]) - sleep_prev;   % count in previous 5 (excl. current)
kill_mask = (1:N)>=6 & labels==1 & prev5==0;
labels(kill_mask) = 4;

% --- Summary ---
REM_p = sum(labels==1);
wake_p = sum(labels==2);
NREM_p = sum(labels==3);
UD_p = sum(labels==4);
sleep_scores = 100*[wake_p, NREM_p, REM_p, UD_p] / N;
disp("Final Classification(%):(W,N,R,U)") 
disp(sleep_scores);
save("labels.mat","labels")

%% ========================= Undefined Epochs Verification (Optional) ======================
% Iteratively reclassify UD epochs using likelihoods from EMG/REM/NREM posteriors
% Labels: 1=REM, 2=Wake, 3=NREM, 4=UD

max_iterations      = 100;
tolerance           = 1e-3;
stable_runs_needed  = 3;

% thresholds (keep your originals; tweak here if needed)
thr_wake = -0.80;
thr_nrem = -0.75;
thr_rem  = -0.85;

prev_sleep_scores = zeros(1,4);
stable_runs = 0;

% Epoch timing for first-15/30-min rules (uses epoch_sec if defined)
if ~exist('epoch_sec','var') || isempty(epoch_sec), epoch_sec = 5; end
n15 = min(numel(labels), round((15*60)/epoch_sec));
n30 = min(numel(labels), round((30*60)/epoch_sec));

for iteration = 1:max_iterations
    % --- Indices by current label ---
    UD_idx   = find(labels == 4);
    W_idx    = find(labels == 2);
    REM_idx  = find(labels == 1);
    NREM_idx = find(labels == 3);

    % If no UD left, we can stop early
    if isempty(UD_idx)
        fprintf('No Undefined epochs remain (iteration %d).\n', iteration);
        break;
    end

    % --- Likelihoods for UD epochs (vectorized) ---
    % Wake feature from EMG (columns 1:3 are high-activity side, 4:5 lower)
    prob_UD_wake = mean(sorted_Wake_probabilities(UD_idx, 1:3), 2);

    if isempty(W_idx)
        prob_W_clusters = mean(mean(sorted_Wake_probabilities(:, 1:3), 2));
    else
        prob_W_clusters = mean(mean(sorted_Wake_probabilities(W_idx, 1:3), 2));
    end

    wake_likelihood = (prob_UD_wake - prob_W_clusters) ./ ...
                      (prob_UD_wake + prob_W_clusters + eps);

    % NREM likelihood = average of RMS (cols 4:5 of Wake probs) and Delta (col 1 of NREM probs)
    prob_UD_nrem_rms   = mean(sorted_Wake_probabilities(UD_idx, 4:5), 2);
    prob_UD_nrem_delta = sorted_NREM_probabilities(UD_idx, 1);

    if isempty(NREM_idx)
        prob_NREM_rms   = mean(mean(sorted_Wake_probabilities(:, 4:5), 2));
        prob_NREM_delta = mean(sorted_NREM_probabilities(:, 1));
    else
        prob_NREM_rms   = mean(mean(sorted_Wake_probabilities(NREM_idx, 4:5), 2));
        prob_NREM_delta = mean(sorted_NREM_probabilities(NREM_idx, 1));
    end

    nrem_like_rms   = (prob_UD_nrem_rms   - prob_NREM_rms)   ./ (prob_UD_nrem_rms   + prob_NREM_rms   + eps);
    nrem_like_delta = (prob_UD_nrem_delta - prob_NREM_delta) ./ (prob_UD_nrem_delta + prob_NREM_delta + eps);
    NREM_likelihood = (nrem_like_rms + nrem_like_delta) ./ 2;

    % REM likelihood = average of RMS (col 5 of Wake probs) and Theta (col 1 of REM probs)
    prob_UD_rem_rms   = sorted_Wake_probabilities(UD_idx, 5);
    prob_UD_rem_theta = sorted_REM_probabilities(UD_idx, 1);

    if isempty(REM_idx)
        prob_REM_rms   = mean(sorted_Wake_probabilities(:, 5));
        prob_REM_theta = mean(sorted_REM_probabilities(:, 1));
    else
        prob_REM_rms   = mean(sorted_Wake_probabilities(REM_idx, 5));
        prob_REM_theta = mean(sorted_REM_probabilities(REM_idx, 1));
    end

    rem_like_rms   = (prob_UD_rem_rms   - prob_REM_rms)   ./ (prob_UD_rem_rms   + prob_REM_rms   + eps);
    rem_like_theta = (prob_UD_rem_theta - prob_REM_theta) ./ (prob_UD_rem_theta + prob_REM_theta + eps);
    REM_likelihood = (rem_like_theta + rem_like_rms) ./ 2;

    % --- Decide new labels for UD epochs (match your rule set) ---
    isWake = wake_likelihood < thr_wake;
    isNREM = NREM_likelihood < thr_nrem;
    isREM  = REM_likelihood  < thr_rem;

    % 2+ conditions -> keep UD(4); exactly 1 condition -> assign that class; 0 -> keep UD
    new_ud_labels = 4*ones(size(UD_idx));
    oneWake =  isWake & ~isNREM & ~isREM;
    oneNrem = ~isWake &  isNREM & ~isREM;
    oneRem  = ~isWake & ~isNREM &  isREM;
    new_ud_labels(oneWake) = 2;
    new_ud_labels(oneNrem) = 3;
    new_ud_labels(oneRem)  = 1;

    labels(UD_idx) = new_ud_labels;

    % --- REM persistence: keep REM only if any of the previous 5 epochs are NREM (3) ---
    N = numel(labels);
    prevNREM = (labels == 3);
    prev5_nrem = movsum(prevNREM, [5 0]) - prevNREM; % count of NREM in prior 5 (exclude current)
    kill = (1:N) >= 6 & labels == 1 & prev5_nrem == 0;
    labels(kill) = 4;

    % --- Bridge isolated epoch between wakes: W ? W → center = W ---
    mid = 2:N-1;
    bridge = labels(mid-1) == 2 & labels(mid+1) == 2;
    labels(mid(bridge)) = 2;

    % --- First-15/30-min rule (based on epoch_sec) ---
    has_sleep = any(labels(1:n15) == 1 | labels(1:n15) == 3);
    if has_sleep
        labels(1:n30) = 4;
    end

    % --- Stabilization check ---
    REM_p  = sum(labels == 1);
    wake_p = sum(labels == 2);
    NREM_p = sum(labels == 3);
    UD_p   = sum(labels == 4);

    sleep_scores = 100 * [wake_p, NREM_p, REM_p, UD_p] / N;

    if all(abs(sleep_scores - prev_sleep_scores) < tolerance)
        stable_runs = stable_runs + 1;
    else
        stable_runs = 0;
    end

    if stable_runs >= stable_runs_needed
        fprintf('Results have stabilized after %d iterations.\n', iteration);
        break;
    end

    prev_sleep_scores = sleep_scores;

    if iteration == max_iterations
        warning('Reached maximum iterations (%d) without stabilization.', max_iterations);
    end
end

% --- Summary ---
REM_p = sum(labels==1);
wake_p = sum(labels==2);
NREM_p = sum(labels==3);
UD_p = sum(labels==4);
sleep_scores = 100*[wake_p, NREM_p, REM_p, UD_p] / N;
disp(sleep_scores);


%% ============================= Finalize & Export (Optional)=============================
% Save results + quick hypnogram
% Labels: 1=REM, 2=Wake, 3=NREM, 4=UD

if ~exist('epoch_sec','var') || isempty(epoch_sec), epoch_sec = 5; end
N = numel(labels);
t0 = (0:N-1) * epoch_sec;  % seconds from start

state_names = strings(1,N);
state_names(labels==1) = "REM";
state_names(labels==2) = "Wake";
state_names(labels==3) = "NREM";
state_names(labels==4) = "UD";

% Summary
REM_p  = sum(labels==1);
W_p    = sum(labels==2);
NREM_p = sum(labels==3);
UD_p   = sum(labels==4);
sleep_scores = 100*[W_p, NREM_p, REM_p, UD_p]/N;
fprintf('Final staging (%%): Wake=%.1f  NREM=%.1f  REM=%.1f  UD=%.1f\n', ...
        sleep_scores(1), sleep_scores(2), sleep_scores(3), sleep_scores(4));

% Save MAT + CSV
save('sleep_staging_results.mat', 'labels', 'state_names', 'sleep_scores', ...
     'epoch_sec', 'fs', 'cluster_assignments', 'active_wake', 'REM', 'NREM', ...
     'sorted_Wake_probabilities', 'sorted_REM_probabilities', 'sorted_NREM_probabilities');

T = table((1:N).', t0.', labels(:), state_names(:), ...
    'VariableNames', {'epoch','t_start_sec','state_code','state_name'});
writetable(T, 'sleep_staging_results.csv');

% Quick hypnogram (Wake high, REM low)
y = nan(1,N);
y(labels==2) = 3;   % Wake
y(labels==3) = 2;   % NREM
y(labels==1) = 1;   % REM
y(labels==4) = 0;   % UD

figure; stairs(t0/3600, y, 'LineWidth', 1.5);
ylim([-0.5 3.5]); yticks([0 1 2 3]); yticklabels({'UD','REM','NREM','Wake'});
xlabel('Time (hours)'); ylabel('Stage'); title('Hypnogram');
grid on;

