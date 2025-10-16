function SleepLabApp
% SleepLabApp — Multi-module GUI to run biomarkers pipelines
% Modules included: PSD Grouping, Theta–Gamma PAC (distribution +  MI), HFD, Beta-Bursts
% Assumes each mouse folder contains EEG/labels as in your previous scripts.

clc;

%% ------------------------------- UI ----------------------------------------
f = uifigure('Name','Sleep Lab App','Position',[120 80 1100 700]);

% Row heights: 1–4 controls, 5 = big Module Settings, 6 = small spacer, 7 = Run, 8 = Log (flex)
g = uigridlayout(f,[8 4]);
g.RowHeight   = {32,34,34,34, '2x', 6, 40, '1x'};
g.ColumnWidth = {250,220,220,'1x'};

% Row 1: root + open
uilabel(g,'Text','Root folder (mouse subfolders):','HorizontalAlignment','left');
rootEdit = uieditfield(g,'text');
uibutton(g,'Text','Browse Root…','ButtonPushedFcn',@(s,e)browseRoot());
uibutton(g,'Text','Open Root','ButtonPushedFcn',@(s,e)openRoot());

% Row 2: module chooser  (using ItemsData == stable keys)
uilabel(g,'Text','Module to run:','HorizontalAlignment','left');
moduleDrop = uidropdown(g, ...
    'Items',     {'PSD Grouping','Theta-Gamma PAC','HFD','Beta-Bursts','MDF/SEF/Peak'}, ...
    'ItemsData', {'psd','pac','hfd','beta','mdfsef'}, ...
    'Value','psd', ...
    'ValueChangedFcn', @(~,~) switchPanel());

uilabel(g,'Text','Exclude mice (comma-separated):','HorizontalAlignment','left');
excludeEdit = uieditfield(g,'text');

% Row 3: common settings
uilabel(g,'Text','Label codes [Wake REM NREM]:','HorizontalAlignment','left');
labEdit = uieditfield(g,'text','Value','2 1 3');
uilabel(g,'Text','fs (Hz):','HorizontalAlignment','left');
fsEdit = uieditfield(g,'numeric','Value',2000,'Limits',[1 Inf]);

% Row 4: epoch/band
uilabel(g,'Text','Epoch length (s):','HorizontalAlignment','left');
epochEdit = uieditfield(g,'numeric','Value',5,'Limits',[0.5 Inf]);
uilabel(g,'Text','Base BP for EEG prefilter [low high] (Hz):','HorizontalAlignment','left');
bpEdit = uieditfield(g,'text','Value','0.5 100');

% Row 5: module panels (stacked overlay)
pStack = uipanel(g,'Title','Module Settings','Scrollable','on');
pStack.Layout.Column = [1 4];
pStack.Layout.Row    = 5;                       % <— single tall row for settings
stackGrid = uigridlayout(pStack,[1 1]);
stackGrid.RowHeight   = {'1x'};
stackGrid.ColumnWidth = {'1x'};

% -------- PSD --------
pPSD = uipanel(stackGrid,'Title','PSD Grouping');  pPSD.Visible='on';
pPSD.Layout.Row = 1; pPSD.Layout.Column = 1;       % <— pin to same cell
pgPSD = uigridlayout(pPSD,[3 6]); pgPSD.RowHeight={30,30,'1x'}; pgPSD.ColumnWidth={160,120,160,120,160,'1x'};
uilabel(pgPSD,'Text','Use peak filter (REM 4.8–9.8 / NREM 0.8–4.8)?');
usePeakDrop = uidropdown(pgPSD,'Items',{'Yes','No'},'Value','Yes');
uilabel(pgPSD,'Text','Welch window (n):');  winEdit = uieditfield(pgPSD,'numeric','Value',2048,'Limits',[128 Inf]);
uilabel(pgPSD,'Text','Welch overlap (n):'); ovlEdit = uieditfield(pgPSD,'numeric','Value',1024,'Limits',[0 Inf]);
uilabel(pgPSD,'Text','X-lim (Hz):');        xlimEdit = uieditfield(pgPSD,'text','Value','1 100');
uilabel(pgPSD,'Text','Line noise notch (Hz):'); notchEdit = uieditfield(pgPSD,'text','Value','48 52');

% -------- PAC --------
pPAC = uipanel(stackGrid,'Title','Theta-Gamma PAC'); pPAC.Visible='off';
pPAC.Layout.Row = 1; pPAC.Layout.Column = 1;        % <— pin to same cell
pgPAC = uigridlayout(pPAC,[3 8]); pgPAC.RowHeight={30,30,'1x'}; pgPAC.ColumnWidth={120,120,140,80,140,80,200,'1x'};
uilabel(pgPAC,'Text','REM source:');
remSource = uidropdown(pgPAC,'Items',{'labels (auto)','manual REM_EEG_accusleep.mat'},'Value','labels (auto)');
uilabel(pgPAC,'Text','Z-score outlier |z| >');
zThrEdit = uieditfield(pgPAC,'numeric','Value',3,'Limits',[0 Inf]);
uilabel(pgPAC,'Text','Theta range (Hz):');
thetaEdit = uieditfield(pgPAC,'text','Value','5 9');
uilabel(pgPAC,'Text','Gamma range (Hz):');
gammaEdit = uieditfield(pgPAC,'text','Value','30 100');
uilabel(pgPAC,'Text','# bins (distribution):');
nbinsEdit = uieditfield(pgPAC,'numeric','Value',72,'Limits',[12 720]);
miChk = uicheckbox(pgPAC,'Text','Compute MI map (phase×amp grid)','Value',false);
groupPACChk = uicheckbox(pgPAC,'Text','Group plots (WT vs DS) after compute','Value',true);

% -------- HFD --------
pHFD = uipanel(stackGrid,'Title','HFD');            pHFD.Visible='off';
pHFD.Layout.Row = 1; pHFD.Layout.Column = 1;        % <— pin to same cell
pgHFD = uigridlayout(pHFD,[3 8]); pgHFD.RowHeight={30,30,'1x'}; pgHFD.ColumnWidth={160,80,160,80,160,80,220,'1x'};
uilabel(pgHFD,'Text','Fs (downsample) Hz:');   fsNewEdit = uieditfield(pgHFD,'numeric','Value',256,'Limits',[32 Inf]);
uilabel(pgHFD,'Text','FIR order (0.5–70 Hz):'); firOrderEdit = uieditfield(pgHFD,'numeric','Value',200,'Limits',[10 5000]);
uilabel(pgHFD,'Text','Win (s):');              hfdWinSec = uieditfield(pgHFD,'numeric','Value',4,'Limits',[1 Inf]);
uilabel(pgHFD,'Text','Overlap (s):');          hfdOverlapSec = uieditfield(pgHFD,'numeric','Value',2.5,'Limits',[0 Inf]);
uilabel(pgHFD,'Text','kmax:');                 kmaxEdit = uieditfield(pgHFD,'numeric','Value',30,'Limits',[5 1000]);
groupOnlyChk = uicheckbox(pgHFD,'Text','Aggregate only (skip per-mouse recompute)','Value',false);

% -------- Beta-Bursts --------
pBB = uipanel(stackGrid,'Title','Beta-Bursts');     pBB.Visible='off';
pBB.Layout.Row = 1; pBB.Layout.Column = 1;          % <— pin to same cell
pgBB = uigridlayout(pBB,[3 6]); pgBB.RowHeight={30,30,'1x'}; pgBB.ColumnWidth={160,120,160,120,260,'1x'};
uilabel(pgBB,'Text','Beta band (Hz):');     bbBandEdit = uieditfield(pgBB,'text','Value','13 30');
uilabel(pgBB,'Text','Threshold percentile:'); bbThrPrct = uieditfield(pgBB,'numeric','Value',75,'Limits',[1 99]);
uilabel(pgBB,'Text','CDF X-lims [amp;dur;freq;IBI;IBIshort;IBIlong]:');
bbXlimsEdit = uieditfield(pgBB,'text','Value','[2000 1e5];[0 0.35];[15 25];[0 1];[0 0.05];[0.2 1]');

% -------- MDF/SEF/Peak (RAW EEG) --------
pMDF = uipanel(stackGrid,'Title','MDF / SEF / Peak (from RAW EEG)');
pMDF.Visible='off';
pgMDF = uigridlayout(pMDF,[3 8]);
pgMDF.RowHeight   = {30,30,'1x'};
pgMDF.ColumnWidth = {160,140,160,140,200,140,'1x','1x'};

% Row 1
uilabel(pgMDF,'Text','Mode:');
mdfModeDrop = uidropdown(pgMDF,'Items',{'Per-mouse only','Group only','Both'}, ...
    'ItemsData',{'per','group','both'},'Value','both');

uilabel(pgMDF,'Text','SEF percentage:');
mdfSEFEdit = uieditfield(pgMDF,'numeric','Value',0.95,'Limits',[0.5 0.999]);

uilabel(pgMDF,'Text','Welch window (n):');
mdfWinEdit = uieditfield(pgMDF,'numeric','Value',2048,'Limits',[128 Inf]);

uilabel(pgMDF,'Text','Overlap (n):');
mdfOvlEdit = uieditfield(pgMDF,'numeric','Value',128,'Limits',[0 Inf]);

% Row 2
mdfAutoChk = uicheckbox(pgMDF,'Text','Group: auto-compute missing per-mouse from RAW EEG + labels', ...
    'Value',true);
mdfGateChk = uicheckbox(pgMDF,'Text','Apply peak-frequency gating (REM 4.8–9.9, NREM 0.8–4.8)', ...
    'Value',true);


% Row 7: footer (Run + status) in its own mini-grid
footer = uipanel(g,'BorderType','none');
footer.Layout.Column = [1 4];
footer.Layout.Row    = 7;

fgrid = uigridlayout(footer,[1 3]);
fgrid.RowHeight   = {40};
fgrid.ColumnWidth = {260, '1x', 120};   % [Run button | status | optional Stop]

runBtn   = uibutton(fgrid,'Text','Run Selected Module', ...
    'FontWeight','bold','ButtonPushedFcn',@(s,e)runModule());
runBtn.Layout.Column = 1;

statusLbl = uilabel(fgrid,'Text','Ready.','HorizontalAlignment','left');
statusLbl.Layout.Column = 2;

% (optional) a Stop button you can wire later
stopBtn = uibutton(fgrid,'Text','Stop','Enable','off');
stopBtn.Layout.Column = 3;

% Row 8: roomy log box
logBox = uitextarea(g,'Editable','off');
logBox.Layout.Column = [1 4];
logBox.Layout.Row    = 8;



%% --------------------------- callbacks & logic -----------------------------
    function browseRoot()
        p = uigetdir(pwd,'Select main directory with mouse subfolders');
        if isequal(p,0); return; end
        rootEdit.Value = p;
    end
    function openRoot()
        p = rootEdit.Value; if exist(p,'dir'), winopen(p); end
    end
    function switchPanel()
        pPSD.Visible = 'off'; pPAC.Visible='off'; pHFD.Visible='off'; pBB.Visible='off'; pMDF.Visible='off';
        switch moduleDrop.Value
            case 'psd',  pPSD.Visible='on';
            case 'pac',  pPAC.Visible='on';
            case 'hfd',  pHFD.Visible='on';
            case 'beta', pBB.Visible ='on';
            case 'mdfsef', pMDF.Visible='on';
        end
    end

    function runModule()
        try
            statusLbl.Text = 'Running...'; drawnow;
            rootDir = strtrim(rootEdit.Value);
            if ~exist(rootDir,'dir')
                uialert(f,'Please select a valid root folder.','No folder'); statusLbl.Text='Ready.'; return;
            end
            excl = parseList(excludeEdit.Value);
            [WakeCode, REMCode, NREMCode] = parseLabelCodes(labEdit.Value);
            fs = fsEdit.Value;
            epochSec = epochEdit.Value;
            baseBP = parseBand(bpEdit.Value);
            logmsg('Root: %s', rootDir);

            switch moduleDrop.Value
                case 'psd'
                    usePeak = strcmp(usePeakDrop.Value,'Yes');
                    w = winEdit.Value; ov = ovlEdit.Value;
                    xlimHz = parseBand(xlimEdit.Value);
                    notch = parseBand(notchEdit.Value);
                    runPSD_Internal(rootDir, fs, epochSec, baseBP, [WakeCode REMCode NREMCode], usePeak, w, ov, xlimHz, notch, excl);

                case 'pac'
                    useManualREM = strcmp(remSource.Value,'manual REM_EEG_accusleep.mat');
                    zthr = zThrEdit.Value;
                    th = parseBand(thetaEdit.Value);
                    ga = parseBand(gammaEdit.Value);
                    nb = nbinsEdit.Value;
                    doMI = miChk.Value;
                    doGroup = groupPACChk.Value;
                    runPAC_Internal(rootDir, fs, epochSec, [WakeCode REMCode NREMCode], useManualREM, zthr, th, ga, nb, excl, doMI, doGroup);

                case 'hfd'
                    fsNew = fsNewEdit.Value;
                    firOrd = firOrderEdit.Value;
                    winS = hfdWinSec.Value;
                    ovS  = hfdOverlapSec.Value;
                    kmax = kmaxEdit.Value;
                    groupOnly = groupOnlyChk.Value;
                    runHFD_Internal(rootDir, fs, epochSec, baseBP, fsNew, firOrd, winS, ovS, kmax, [WakeCode REMCode NREMCode], excl, groupOnly);

                case 'beta'
                    bb = parseBand(bbBandEdit.Value);
                    thrP = bbThrPrct.Value;
                    xlims = parseXlimList(bbXlimsEdit.Value);
                    runBeta_Internal(rootDir, fs, epochSec, [WakeCode REMCode NREMCode], bb, thrP, excl, xlims);
                case 'mdfsef'
                    fs = fsEdit.Value;
                    epoch_sec = epochEdit.Value;
                    bp = str2num(bpEdit.Value); %#ok<ST2NM>
                    if numel(bp)~=2 || any(~isfinite(bp)) || bp(1)<=0 || bp(2)<=bp(1)
                        logmsg('Invalid base band-pass.'); return;
                    end
                    codes = str2num(labEdit.Value); %#ok<ST2NM>
                    if numel(codes)~=3, logmsg('Label codes must be [Wake REM NREM].'); return; end
                    excluded = strtrim(split(excludeEdit.Value,','));
                    excluded = excluded(~cellfun(@isempty,excluded));
                    winN = mdfWinEdit.Value;
                    ovN  = mdfOvlEdit.Value;
                    sefPerc = mdfSEFEdit.Value;
                    doGate  = mdfGateChk.Value;
                    mode    = mdfModeDrop.Value;       % 'per' | 'group' | 'both'
                    autoCompute = mdfAutoChk.Value;
                    runMDFSEF_Internal(rootEdit.Value, fs, epoch_sec, codes, bp, winN, ovN, sefPerc, doGate, mode, excluded, autoCompute);

                otherwise
                    uialert(f,'Pick a module to run.','No module');
            end
            statusLbl.Text = 'Done.';
            logmsg('Done.');
        catch ME
            statusLbl.Text = 'Error.';
            logmsg('ERROR: %s', ME.message);
            rethrow(ME);
        end
    end

%% ------------------------ INTERNAL: PSD grouping ---------------------------
   function runPSD_Internal(root, fs, epoch_sec, baseBP, codes, usePeak, ...
            winN, ovN, xlimHz, notchHz, excluded)

    logmsg('PSD: fs=%g, epoch=%gs, BP=[%g %g], window=%d, overlap=%d, peak=%d', ...
        fs, epoch_sec, baseBP(1), baseBP(2), winN, ovN, usePeak);

    epoch_len = round(fs*epoch_sec);

    % EEG prefilter (default 0.5–100 Hz if UI left as such)
    [b_eeg, a_eeg] = butter(4, baseBP/(fs/2), 'bandpass');

    % fixed parts to mirror original
    lowcut   = 0.1;
    rem_gate = [4.8 9.8];
    nrem_gate= [0.8 4.8];

    d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

    WT_Wake={}; WT_NREM={}; WT_REM={};
    DS_Wake={}; DS_NREM={}; DS_REM={};

    for k = 1:numel(d)
        name = d(k).name;
        if any(strcmp(name, excluded)), logmsg('Skip excluded: %s', name); continue; end

        mdir = fullfile(root, name);
        eegPath = fullfile(mdir,'EEG_accusleep.mat');
        labPath = fullfile(mdir,'labels.mat');
        if ~exist(eegPath,'file') || ~exist(labPath,'file')
            logmsg('Missing EEG/labels: %s', name); continue;
        end

        S = load(eegPath);
        if ~isfield(S,'EEG'), logmsg('No EEG var in %s', eegPath); continue; end
        EEG = S.EEG(:);

        L = load(labPath);
        if ~isfield(L,'labels'), logmsg('No labels var in %s', labPath); continue; end
        labels = L.labels(:).';

        % Prefilter
        try
            EEG = filtfilt(b_eeg, a_eeg, EEG);
        catch
            logmsg('Filter fail: %s', name); continue;
        end

        % Epoching
        num_epochs = floor(numel(EEG)/epoch_len);
        if num_epochs < 1, logmsg('Too short: %s', name); continue; end
        EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
        labels = labels(1:min(num_epochs, numel(labels)));
        if numel(labels) < size(EEG,2), EEG = EEG(:,1:numel(labels)); end

        % Accumulators (linear PSD)
        acc_Wake_sum=[]; acc_Wake_n=0;
        acc_NREM_sum=[]; acc_NREM_n=0;
        acc_REM_sum =[]; acc_REM_n =0;
        Fmask=[];

        for e = 1:size(EEG,2)
            [Pxx,F] = pwelch(EEG(:,e), winN, ovN, [], fs);
            m = (F>=lowcut) & (F<notchHz(1) | F>notchHz(2));
            Fv = F(m); P = Pxx(m);

            if isempty(Fmask)
                Fmask = Fv;
            else
                if numel(Fv)~=numel(Fmask) || any(abs(Fv-Fmask)>1e-12)
                    logmsg('Freq grid mismatch in %s; epoch skipped.', name);
                    continue;
                end
            end

            st = labels(e);
            keep = true;
            if usePeak
                [~,pk] = max(P); pkf = Fv(pk);
                if st==codes(2)      % REM (UI codes = [Wake REM NREM])
                    keep = pkf>=rem_gate(1)  && pkf<=rem_gate(2);
                elseif st==codes(3)  % NREM
                    keep = pkf>=nrem_gate(1) && pkf<=nrem_gate(2);
                end
            end
            if ~keep, continue; end

            if st==codes(1)           % Wake
                if acc_Wake_n==0, acc_Wake_sum=zeros(size(P)); end
                acc_Wake_sum = acc_Wake_sum + P; acc_Wake_n=acc_Wake_n+1;
            elseif st==codes(3)       % NREM
                if acc_NREM_n==0, acc_NREM_sum=zeros(size(P)); end
                acc_NREM_sum = acc_NREM_sum + P; acc_NREM_n=acc_NREM_n+1;
            elseif st==codes(2)       % REM
                if acc_REM_n==0,  acc_REM_sum =zeros(size(P)); end
                acc_REM_sum  = acc_REM_sum  + P; acc_REM_n =acc_REM_n +1;
            end
        end

        % Per-mouse means (linear), store struct like the original
        M = struct(); ok=false;
        if acc_Wake_n>0, M.Wake.F=Fmask; M.Wake.Pxx_lin=acc_Wake_sum/acc_Wake_n; ok=true; end
        if acc_NREM_n>0, M.NREM.F=Fmask; M.NREM.Pxx_lin=acc_NREM_sum/acc_NREM_n; ok=true; end
        if acc_REM_n >0, M.REM.F =Fmask; M.REM.Pxx_lin =acc_REM_sum /acc_REM_n; ok=true; end
        if ~ok, logmsg('No accepted epochs in %s; skipping mouse.', name); continue; end

        if contains(name,'WT','IgnoreCase',true)
            if isfield(M,'Wake'), WT_Wake{end+1}=M.Wake; end
            if isfield(M,'NREM'), WT_NREM{end+1}=M.NREM; end
            if isfield(M,'REM'),  WT_REM{end+1}=M.REM;  end
        elseif contains(name,'DS','IgnoreCase',true)
            if isfield(M,'Wake'), DS_Wake{end+1}=M.Wake; end
            if isfield(M,'NREM'), DS_NREM{end+1}=M.NREM; end
            if isfield(M,'REM'),  DS_REM{end+1}=M.REM;  end
        end
    end

    % ---------- Group means (mouse → group) exactly like the original ----------
    [F_WT_W, mean_WT_Wake_dB] = groupMean(WT_Wake);
    [F_DS_W, mean_DS_Wake_dB] = groupMean(DS_Wake);
    [F_WT_N, mean_WT_NREM_dB] = groupMean(WT_NREM);
    [F_DS_N, mean_DS_NREM_dB] = groupMean(DS_NREM);
    [F_WT_R, mean_WT_REM_dB ] = groupMean(WT_REM);
    [F_DS_R, mean_DS_REM_dB ] = groupMean(DS_REM);

    peakTxt = ternary(usePeak,'with','no');
    xl = xlimHz;

    % Wake
    if ~isempty(mean_WT_Wake_dB) || ~isempty(mean_DS_Wake_dB)
        figure; hold on;
        if ~isempty(mean_WT_Wake_dB), plot(F_WT_W, mean_WT_Wake_dB, 'b-', 'LineWidth',1.5); end
        if ~isempty(mean_DS_Wake_dB), plot(F_DS_W, mean_DS_Wake_dB, 'r-', 'LineWidth',1.5); end
        grid on; set(gca,'XScale','log'); xlim(xl);
        xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');
        title(['Mean PSD - Wake (' peakTxt ' peak filter)']); legend({'WT','DS'},'Location','best');
    end
    % NREM
    if ~isempty(mean_WT_NREM_dB) || ~isempty(mean_DS_NREM_dB)
        figure; hold on;
        if ~isempty(mean_WT_NREM_dB), plot(F_WT_N, mean_WT_NREM_dB, 'b-', 'LineWidth',1.5); end
        if ~isempty(mean_DS_NREM_dB), plot(F_DS_N, mean_DS_NREM_dB, 'r-', 'LineWidth',1.5); end
        grid on; set(gca,'XScale','log'); xlim(xl);
        xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');
        title(['Mean PSD - NREM (' peakTxt ' peak filter)']); legend({'WT','DS'},'Location','best');
    end
    % REM
    if ~isempty(mean_WT_REM_dB) || ~isempty(mean_DS_REM_dB)
        figure; hold on;
        if ~isempty(mean_WT_REM_dB), plot(F_WT_R, mean_WT_REM_dB, 'b-', 'LineWidth',1.5); end
        if ~isempty(mean_DS_REM_dB), plot(F_DS_R, mean_DS_REM_dB, 'r-', 'LineWidth',1.5); end
        grid on; set(gca,'XScale','log'); xlim(xl);
        xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');
        title(['Mean PSD - REM (' peakTxt ' peak filter)']); legend({'WT','DS'},'Location','best');
    end

    % Save exactly like the original (but in the selected root)
    save(fullfile(root,'group_psd_summary.mat'), ...
        'WT_Wake','WT_NREM','WT_REM','DS_Wake','DS_NREM','DS_REM', ...
        'F_WT_W','mean_WT_Wake_dB','F_DS_W','mean_DS_Wake_dB', ...
        'F_WT_N','mean_WT_NREM_dB','F_DS_N','mean_DS_NREM_dB', ...
        'F_WT_R','mean_WT_REM_dB','F_DS_R','mean_DS_REM_dB', ...
        'fs','epoch_sec','usePeak');

    logmsg('PSD: saved group_psd_summary.mat');

    % ==================== CSV EXPORTS ====================
    try
        % 1) Per-state group mean CSVs
        write_group_means_csv(fullfile(root,'group_psd_wake.csv'), F_WT_W, mean_WT_Wake_dB, F_DS_W, mean_DS_Wake_dB);
        write_group_means_csv(fullfile(root,'group_psd_nrem.csv'), F_WT_N, mean_WT_NREM_dB, F_DS_N, mean_DS_NREM_dB);
        write_group_means_csv(fullfile(root,'group_psd_rem.csv'),  F_WT_R, mean_WT_REM_dB,  F_DS_R, mean_DS_REM_dB);

        % 2) Combined LONG file (all states)
        Tall = [
            packStateTable("Wake", F_WT_W, mean_WT_Wake_dB, F_DS_W, mean_DS_Wake_dB);
            packStateTable("NREM", F_WT_N, mean_WT_NREM_dB, F_DS_N, mean_DS_NREM_dB);
            packStateTable("REM",  F_WT_R, mean_WT_REM_dB,  F_DS_R, mean_DS_REM_dB)
        ];
        if ~isempty(Tall)
            writetable(Tall, fullfile(root,'group_psd_summary_long.csv'));
        end

        % 3) Per-mouse spectra (long; MouseIdx, Group, State)
        write_per_mouse_csv(WT_Wake, 'Wake', 'WT', root);
        write_per_mouse_csv(WT_NREM, 'NREM', 'WT', root);
        write_per_mouse_csv(WT_REM,  'REM',  'WT', root);

        write_per_mouse_csv(DS_Wake, 'Wake', 'DS', root);
        write_per_mouse_csv(DS_NREM, 'NREM', 'DS', root);
        write_per_mouse_csv(DS_REM,  'REM',  'DS', root);

        % 4) Metadata CSV (Field, Value)
        fields = { ...
            'fs','epoch_sec','baseBP_low','baseBP_high', ...
            'winN','ovN','notch_low','notch_high', ...
            'lowcut','rem_gate_low','rem_gate_high', ...
            'nrem_gate_low','nrem_gate_high','usePeak'};
        values = { ...
            fs, epoch_sec, baseBP(1), baseBP(2), ...
            winN, ovN, notchHz(1), notchHz(2), ...
            0.1, 4.8, 9.8, 0.8, 4.8, logical(usePeak)};
        MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
        writetable(MF, fullfile(root,'group_psd_metadata.csv'));

        logmsg('PSD: CSV exports written.');
    catch ME
        logmsg('CSV export failed: %s', ME.message);
    end
    % ================== END CSV EXPORTS ==================

end

% ---- helper: compute group mean (linear→dB) with grid checking ----
function [Fout, mean_dB] = groupMean(C)
    Fout = []; mean_dB = [];
    if isempty(C), return; end
    Fout = C{1}.F(:);
    Pmat = nan(numel(Fout), numel(C));
    for i = 1:numel(C)
        Fi = C{i}.F(:);
        Pi = C{i}.Pxx_lin(:);
        if numel(Fi)==numel(Fout) && all(abs(Fi - Fout) <= 1e-12)
            Pmat(:,i) = Pi;
        end
    end
    mean_dB = 10*log10( mean(Pmat,2,'omitnan') + eps );
end

% ---- helper: write per-state group mean CSV (dB) ----
function write_group_means_csv(csvPath, F_WT, WT_dB, F_DS, DS_dB)
    if ~isempty(F_WT)
        F = F_WT(:);
    elseif ~isempty(F_DS)
        F = F_DS(:);
    else
        return;
    end
    T = table(F, 'VariableNames', {'Frequency_Hz'});
    if ~isempty(WT_dB), T.WT_mean_dB = WT_dB(:); end
    if ~isempty(DS_dB), T.DS_mean_dB = DS_dB(:); end
    writetable(T, csvPath);
end

% ---- helper: pack one state's table for the long CSV ----
function T = packStateTable(stateName, F_WT, WT_dB, F_DS, DS_dB)
    if isempty(F_WT) && isempty(F_DS), T = table(); return; end
    if ~isempty(F_WT), F = F_WT(:); else, F = F_DS(:); end
    T = table(repmat(string(stateName), numel(F), 1), F, ...
              'VariableNames', {'State','Frequency_Hz'});
    if ~isempty(WT_dB), T.WT_mean_dB = WT_dB(:); end
    if ~isempty(DS_dB), T.DS_mean_dB = DS_dB(:); end
end

% ---- helper: per-mouse long CSVs (Pxx_lin → dB) ----
function write_per_mouse_csv(C, stateName, groupName, root)
    if isempty(C), return; end
    rows = cell(0,1);
    for i = 1:numel(C)
        if ~isfield(C{i},'F') || ~isfield(C{i},'Pxx_lin'), continue; end
        Fi = C{i}.F(:); Pi = C{i}.Pxx_lin(:);
        if isempty(Fi) || isempty(Pi), continue; end
        Ti = table( ...
            repmat(string(groupName), numel(Fi),1), ...
            repmat(string(stateName), numel(Fi),1), ...
            repmat(i, numel(Fi),1), ...
            Fi, 10*log10(Pi + eps), ...
            'VariableNames', {'Group','State','MouseIdx','Frequency_Hz','Pxx_dB'});
        rows{end+1} = Ti; %#ok<AGROW>
    end
    if ~isempty(rows)
        Tout = vertcat(rows{:});
        outName = sprintf('per_mouse_psd_%s_%s.csv', lower(groupName), lower(stateName));
        writetable(Tout, fullfile(root, outName));
    end
end



%% ---------------------- INTERNAL: Theta-Gamma PAC --------------------------
function runPAC_Internal(root, fs, epoch_sec, codes, useManual, zthr, ...
        thetaHz, gammaHz, Nbins, excluded, doMI, doGroup)

    logmsg('PAC: fs=%g, epoch=%gs, theta=[%g %g], gamma=[%g %g], bins=%d, MI=%d', ...
        fs, epoch_sec, thetaHz(1), thetaHz(2), gammaHz(1), gammaHz(2), Nbins, doMI);

    % ---- results folder (for all CSVs that summarize across mice) ----
    resultsDir = fullfile(root, 'Theta-Gamma PAC Results');
    if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

    d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
    WT = {}; DS = {};              % PAC distributions (per-mouse vectors)
    WT_MI = {}; DS_MI = {};        % MI matrices (per-mouse), if doMI

    % Predefine MI grids (so we can aggregate later)
    if doMI
        fp1 = 2:13; fp2 = 4:15;          % theta phase bands (~2 Hz width)
        fa1 = 28:1:98; fa2 = 30:1:100;   % gamma amp bands (2 Hz width)
        phaseCentersHz = fp1 + 1;        % centers of [fp1 fp2]
        ampCentersHz   = fa1 + 1;        % centers of [fa1 fa2]
    end

    for k = 1:numel(d)
        name = d(k).name;
        if any(strcmp(name, excluded)), logmsg('Skip excluded: %s', name); continue; end
        mdir = fullfile(root,name);

        % --------- Build REM vector (auto via labels OR manual file) ----------
        if useManual
            remPath = fullfile(mdir,'REM_EEG_accusleep.mat');
            if ~exist(remPath,'file'), logmsg('No manual REM in %s', name); continue; end
            S = load(remPath);
            if ~isfield(S,'REM_EEG'), logmsg('Missing REM_EEG var in %s', remPath); continue; end
            REM_vec = S.REM_EEG(:);
        else
            eegPath = fullfile(mdir,'EEG_accusleep.mat');
            labPath = fullfile(mdir,'labels.mat');
            if ~exist(eegPath,'file') || ~exist(labPath,'file'), logmsg('Missing EEG/labels in %s', name); continue; end
            E = load(eegPath); if ~isfield(E,'EEG'), logmsg('No EEG var in %s', eegPath); continue; end
            L = load(labPath); if ~isfield(L,'labels'), logmsg('No labels in %s', labPath); continue; end
            EEG = E.EEG(:);
            labels = L.labels(:).';

            epoch_len = round(fs*epoch_sec);
            num_epochs = floor(numel(EEG)/epoch_len);
            if num_epochs<1, logmsg('Too short: %s', name); continue; end
            EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
            labels = labels(1:min(num_epochs,numel(labels)));
            EEG = EEG(:,1:numel(labels));

            % REM is codes(2) because UI is [Wake REM NREM]
            REM_vec = cell2mat( arrayfun(@(e) EEG(:,e), find(labels==codes(2)), 'UniformOutput', false) );
        end
        if isempty(REM_vec), logmsg('No REM samples in %s', name); continue; end

        % --------------------- Clean outliers (|z|>zthr) ----------------------
        z = zscore(double(REM_vec));
        REM_vec(abs(z)>zthr) = NaN;
        REM_vec = fillmissing(REM_vec,'linear');

        % ================== PAC distribution (match 0–720° original) ==========
        thSig = bandpass(REM_vec, thetaHz, fs);
        gaSig = bandpass(REM_vec, gammaHz, fs);

        thPhase = angle(hilbert(thSig));                  % radians
        thDeg360 = mod(rad2deg(thPhase), 360);            % [0,360)
        thDeg720 = [thDeg360; thDeg360+360];              % duplicate -> [0,720)
        gaAmp     = abs(hilbert(gaSig));
        gaAmp2cy  = [gaAmp; gaAmp];                       % duplicate amp to match 2 cycles

        edges   = linspace(0, 720, Nbins+1);
        centers = (edges(1:end-1) + edges(2:end))/2;

        gamma_avg = zeros(Nbins,1);
        for b = 1:Nbins
            inb = (thDeg720 >= edges(b)) & (thDeg720 < edges(b+1));
            gamma_avg(b) = mean(gaAmp2cy(inb), 'omitnan');
        end

        gamma_smoothed = smooth(gamma_avg, 3);
        gamma_smoothed = gamma_smoothed / sum(gamma_smoothed + eps);

        % per-mouse save folder (as you had)
        outdir = fullfile(mdir,'new PAC'); if ~exist(outdir,'dir'), mkdir(outdir); end
        results.gamma_smoothed = gamma_smoothed; %#ok<STRNU>
        save(fullfile(outdir, sprintf('PAC Dist Data %d.mat',Nbins)), 'results');

        % ---- Per-mouse PAC CSV in mouse folder --------------------------------
        try
            Tmouse = table(centers(:), gamma_smoothed(:), ...
                           'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
            writetable(Tmouse, fullfile(outdir, sprintf('PAC_Dist_%dbins.csv', Nbins)));
        catch ME
            logmsg('PAC per-mouse CSV failed (%s): %s', name, ME.message);
        end

        % ========================== Optional MI map ============================
        if doMI
            Q = 1/Nbins; MI = zeros(numel(fa1), numel(fp1));

            for i = 1:numel(fp1)
                ph = angle(hilbert(bandpass(REM_vec,[fp1(i) fp2(i)],fs)));
                [bins,~] = discretize(ph, Nbins);         % Nbins sectors over −π..π
                for j = 1:numel(fa1)
                    a = abs(hilbert(bandpass(REM_vec,[fa1(j) fa2(j)],fs)));
                    D = zeros(1,Nbins);
                    for ii = 1:Nbins
                        m = (bins==ii);
                        D(ii) = mean(a(m));
                    end
                    D = D./sum(D + eps);
                    MI(j,i) = sum(D .* log((D+eps)/Q)) / log(Nbins);
                end
            end
            save(fullfile(outdir, sprintf('MI data (%d bins).mat',Nbins)),'MI');

            % ---- Per-mouse MI CSV (mouse folder) ------------------------------
            try
                MItab = array2table(MI, 'VariableNames', ...
                    matlab.lang.makeValidName("theta_"+string(phaseCentersHz)+"Hz"));
                MItab = addvars(MItab, ampCentersHz(:), 'Before', 1, 'NewVariableNames','gammaAmp_Hz');
                writetable(MItab, fullfile(outdir, sprintf('MI_%dbins.csv', Nbins)));
            catch ME
                logmsg('PAC per-mouse MI CSV failed (%s): %s', name, ME.message);
            end

            % keep for group aggregation
            if contains(name,'WT','IgnoreCase',true)
                WT_MI{end+1} = MI;
            elseif contains(name,'DS','IgnoreCase',true)
                DS_MI{end+1} = MI;
            end
        end

        % bucket for group curves
        if contains(name,'WT','IgnoreCase',true)
            WT{end+1} = gamma_smoothed(:);
        elseif contains(name,'DS','IgnoreCase',true)
            DS{end+1} = gamma_smoothed(:);
        end
    end

    % ======================== Group mean distribution =========================
    edges   = linspace(0, 720, Nbins+1);
    centers = (edges(1:end-1) + edges(2:end))/2;
    WTm = []; DSm = [];
    if ~isempty(WT), WTm = mean(cat(2,WT{:}),2); end
    if ~isempty(DS), DSm = mean(cat(2,DS{:}),2); end

    if ~isempty(WTm) || ~isempty(DSm)
        figure; hold on;
        if ~isempty(WTm), plot(centers, WTm, 'b','LineWidth',1.5); end
        if ~isempty(DSm), plot(centers, DSm, 'r','LineWidth',1.5); end
        xlabel('\theta phase (°)'); ylabel('Normalized \gamma amplitude');
        xlim([0 720]); xticks(0:90:720); grid on;
        title('Theta–Gamma PAC distribution (group means)'); legend({'WT','DS'});
    end

    % ====================== Optional group MI heatmaps ========================
    if doMI && doGroup
        doGroupMI(root, Nbins);
    end

    % ============================= CSV EXPORTS ================================
    try
        % -- Per-mouse long stacks (WT/DS) into resultsDir --
        write_per_mouse_pac_csv(WT, 'WT', centers, fullfile(resultsDir,'pac_per_mouse_wt.csv'));
        write_per_mouse_pac_csv(DS, 'DS', centers, fullfile(resultsDir,'pac_per_mouse_ds.csv'));

        % -- Group mean PAC CSVs (resultsDir) --
        if ~isempty(WTm)
            Tw = table(centers(:), WTm(:), 'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
            writetable(Tw, fullfile(resultsDir,'pac_group_wt.csv'));
        end
        if ~isempty(DSm)
            Td = table(centers(:), DSm(:), 'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
            writetable(Td, fullfile(resultsDir,'pac_group_ds.csv'));
        end

        % -- Combined long file for both groups --
        Tall = table();
        if ~isempty(WTm)
            Tall = [Tall; table(repmat("WT",numel(centers),1), centers(:), WTm(:), ...
                                'VariableNames', {'Group','ThetaPhase_deg','GammaNormAmp'})];
        end
        if ~isempty(DSm)
            Tall = [Tall; table(repmat("DS",numel(centers),1), centers(:), DSm(:), ...
                                'VariableNames', {'Group','ThetaPhase_deg','GammaNormAmp'})];
        end
        if ~isempty(Tall)
            writetable(Tall, fullfile(resultsDir,'pac_group_distribution.csv'));
        end

        % ==================== MI EXPORTS (resultsDir) =====================
        if doMI
            % Per-mouse MI stacks (long format)
            write_per_mouse_mi_stack(WT_MI, 'WT', ampCentersHz, phaseCentersHz, ...
                                     fullfile(resultsDir,'mi_per_mouse_wt.csv'));
            write_per_mouse_mi_stack(DS_MI, 'DS', ampCentersHz, phaseCentersHz, ...
                                     fullfile(resultsDir,'mi_per_mouse_ds.csv'));

            % Group mean MI matrices
            if ~isempty(WT_MI)
                M = cat(3, WT_MI{:});
                MIw = mean(M, 3, 'omitnan');
                MItabW = array2table(MIw, 'VariableNames', ...
                    matlab.lang.makeValidName("theta_"+string(phaseCentersHz)+"Hz"));
                MItabW = addvars(MItabW, ampCentersHz(:), 'Before', 1, 'NewVariableNames','gammaAmp_Hz');
                writetable(MItabW, fullfile(resultsDir,'mi_group_wt.csv'));
            end
            if ~isempty(DS_MI)
                M = cat(3, DS_MI{:});
                MId = mean(M, 3, 'omitnan');
                MItabD = array2table(MId, 'VariableNames', ...
                    matlab.lang.makeValidName("theta_"+string(phaseCentersHz)+"Hz"));
                MItabD = addvars(MItabD, ampCentersHz(:), 'Before', 1, 'NewVariableNames','gammaAmp_Hz');
                writetable(MItabD, fullfile(resultsDir,'mi_group_ds.csv'));
            end

            % Combined long group MI (stack WT/DS means)
            Tmi = table();
            if exist('MIw','var')
                Tmi = [Tmi; expand_mi_long("WT", MIw, ampCentersHz, phaseCentersHz)];
            end
            if exist('MId','var')
                Tmi = [Tmi; expand_mi_long("DS", MId, ampCentersHz, phaseCentersHz)];
            end
            if ~isempty(Tmi)
                writetable(Tmi, fullfile(resultsDir,'mi_group_long.csv'));
            end
        end
        % =================== /MI EXPORTS ==================================

        % -- Metadata CSV (resultsDir) --
        fields = {'fs','epoch_sec','theta_low','theta_high','gamma_low','gamma_high', ...
                  'Nbins','zthr','useManual','doMI','doGroup'};
        values = {fs, epoch_sec, thetaHz(1), thetaHz(2), gammaHz(1), gammaHz(2), ...
                  Nbins, zthr, logical(useManual), logical(doMI), logical(doGroup)};
        MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
        writetable(MF, fullfile(resultsDir,'pac_metadata.csv'));

        logmsg('PAC: CSV exports written.');
    catch ME
        logmsg('PAC CSV export failed: %s', ME.message);
    end

    logmsg('PAC: done.');
end

% --------------------------- local helpers --------------------------------
function write_per_mouse_pac_csv(C, groupName, centers, outCsv)
    if isempty(C), return; end
    rows = cell(0,1);
    for i = 1:numel(C)
        gi = C{i}(:);
        if isempty(gi), continue; end
        Ti = table(repmat(string(groupName), numel(centers),1), ...
                   repmat(i, numel(centers),1), ...
                   centers(:), gi, ...
                   'VariableNames', {'Group','MouseIdx','ThetaPhase_deg','GammaNormAmp'});
        rows{end+1} = Ti; %#ok<AGROW>
    end
    if ~isempty(rows)
        writetable(vertcat(rows{:}), outCsv);
    end
end

function write_per_mouse_mi_stack(MIcells, groupName, ampHz, phaseHz, outCsv)
    if isempty(MIcells), return; end
    rows = cell(0,1);
    for i = 1:numel(MIcells)
        MI = MIcells{i};
        if isempty(MI), continue; end
        [A,P] = ndgrid(ampHz(:), phaseHz(:));
        Ti = table(repmat(string(groupName), numel(A), 1), ...
                   repmat(i, numel(A), 1), ...
                   A(:), P(:), MI(:), ...
                   'VariableNames', {'Group','MouseIdx','gammaAmp_Hz','thetaPhase_Hz','MI'});
        rows{end+1} = Ti; %#ok<AGROW>
    end
    if ~isempty(rows)
        writetable(vertcat(rows{:}), outCsv);
    end
end

function T = expand_mi_long(groupName, MImean, ampHz, phaseHz)
    [A,P] = ndgrid(ampHz(:), phaseHz(:));
    T = table(repmat(string(groupName), numel(A), 1), ...
              A(:), P(:), MImean(:), ...
              'VariableNames', {'Group','gammaAmp_Hz','thetaPhase_Hz','MI'});
end



%% --------------------------- INTERNAL: HFD ---------------------------------
function runHFD_Internal(root, fs, epoch_sec, baseBP, fsNew, firOrd, winSec, ovlSec, kmax, codes, excluded, groupOnly)
    logmsg('HFD: fs=%g -> %g Hz, win=%.2fs, overlap=%.2fs, kmax=%d, aggregateOnly=%d', fs, fsNew, winSec, ovlSec, kmax, groupOnly);
    epoch_len = round(fs*epoch_sec);

    % results folder for cross-mouse CSVs
    resultsDir = fullfile(root, 'HFD Results');
    if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

    nyq = fs/2;
    bp = [max(0.5, baseBP(1)) min(70, baseBP(2))]/nyq; % FIR 0.5–70
    firCoeff = fir1(firOrd, bp, 'bandpass', hamming(firOrd+1));

    states = {'Wake','NREM','REM'};
    codesMap = containers.Map(states, num2cell(codes([1 3 2]))); % Wake,NREM,REM

    d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

    if ~groupOnly
        for k = 1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('Skip excluded: %s', name); continue; end
            mdir = fullfile(root,name);
            eegPath = fullfile(mdir,'EEG_accusleep.mat');
            labPath = fullfile(mdir,'labels.mat');
            if ~exist(eegPath,'file') || ~exist(labPath,'file')
                logmsg('Missing EEG/labels in %s', name); continue;
            end
            S = load(eegPath); if ~isfield(S,'EEG'), logmsg('No EEG var in %s', eegPath); continue; end
            EEG = S.EEG(:);
            L = load(labPath); if ~isfield(L,'labels'), logmsg('No labels in %s', labPath); continue; end
            labels = L.labels(:).';

            EEGf = filtfilt(firCoeff,1,EEG);

            num_epochs = floor(numel(EEGf)/epoch_len);
            if num_epochs<1, logmsg('Too short: %s', name); continue; end
            EEGf = reshape(EEGf(1:num_epochs*epoch_len), epoch_len, []);
            labels = labels(1:min(num_epochs,numel(labels)));
            EEGf = EEGf(:,1:numel(labels));

            FD_results = struct();
            for si = 1:numel(states)
                st = states{si}; code = codesMap(st);
                idx = find(labels==code);
                if isempty(idx), FD_results.(st).HFD = []; continue; end

                HFD_vals = [];
                for e = idx
                    epoch = EEGf(:,e);
                    % downsample pipeline to fsNew
                    [b,a] = butter(4, (fsNew/2)/(fs/2), 'low');
                    ep_f = filtfilt(b,a,epoch);
                    ep_ds = resample(ep_f, fsNew, fs);

                    wLen = round(winSec*fsNew);
                    step = max(1, wLen - round(ovlSec*fsNew));
                    nW = floor((numel(ep_ds) - wLen)/step) + 1;
                    for w = 1:nW
                        s = (w-1)*step + 1; eix = s + wLen - 1;
                        if eix>numel(ep_ds), break; end
                        seg = ep_ds(s:eix);
                        N = numel(seg);
                        kmax_eff = min(kmax, floor(N/2)); if kmax_eff<2, continue; end
                        Lm = zeros(kmax_eff,1);
                        for k2 = 1:kmax_eff
                            Lmk = 0; cnt = 0;
                            for j = 1:k2:N-k2+1
                                if (j+k2)<=N, Lmk = Lmk + abs(seg(j+k2)-seg(j)); cnt = cnt + 1; end
                            end
                            if cnt>0, Lm(k2) = (Lmk/cnt) * (N-1) / (k2^2); else, Lm(k2)=eps; end
                        end
                        logL = log10(Lm + eps); logK = log10(1:kmax_eff);
                        p = polyfit(logK, logL.', 1);
                        HFD_vals(end+1,1) = abs(p(1)); %#ok<AGROW>
                    end
                end
                FD_results.(st).HFD = HFD_vals;
            end

            % per-mouse MAT (original behavior)
            save(fullfile(mdir,'FD_results.mat'),'FD_results');
            logmsg('HFD saved: %s', name);

            % ---- per-mouse CSV (long, by state) ----
            try
                rows = {};
                for si = 1:numel(states)
                    st = states{si};
                    vals = FD_results.(st).HFD;
                    if isempty(vals), continue; end
                    rows{end+1} = table(repmat(string(st), numel(vals),1), vals(:), ...
                        'VariableNames', {'State','HFD'}); %#ok<AGROW>
                end
                if ~isempty(rows)
                    outdirMouse = fullfile(mdir, 'HFD'); if ~exist(outdirMouse,'dir'), mkdir(outdirMouse); end
                    writetable(vertcat(rows{:}), fullfile(outdirMouse, 'HFD_values.csv'));
                end
            catch ME
                logmsg('HFD per-mouse CSV failed (%s): %s', name, ME.message);
            end
        end
    end

    % ================= Group aggregation (from saved per-mouse mats) =================
    mice = dir(root); mice = mice([mice.isdir]); mice = mice(~ismember({mice.name},{'.','..'}));

    % preserve per-mouse identity for CSVs
    HFD_cells = struct('Wake',struct('WT',{{}},'DS',{{}}), ...
                       'REM', struct('WT',{{}},'DS',{{}}), ...
                       'NREM',struct('WT',{{}},'DS',{{}}));

    perMouseRows = {}; % for resultsDir/hfd_per_mouse_long.csv

    for k = 1:numel(mice)
        name = mice(k).name;
        if any(strcmp(name, excluded)), continue; end
        fdPath = fullfile(root,name,'FD_results.mat'); if ~exist(fdPath,'file'), continue; end
        S = load(fdPath); if ~isfield(S,'FD_results'), continue; end

        isWT = contains(name,'WT','IgnoreCase',true);
        isDS = contains(name,'DS','IgnoreCase',true);
        if ~(isWT || isDS), continue; end

        % choose group without a ternary helper
        if isWT
            grp = "WT";
        else
            grp = "DS";
        end

        for st = ["Wake","REM","NREM"]
            vals = S.FD_results.(st).HFD;
            if isempty(vals), continue; end
            % collect per-mouse cells for group arrays
            if isWT
                HFD_cells.(st).WT{end+1} = vals(:);
            else
                HFD_cells.(st).DS{end+1} = vals(:);
            end
            % accumulate per-mouse long rows
            perMouseRows{end+1} = table(repmat(grp, numel(vals),1), ...         % Group
                                        repmat(st.', numel(vals),1), ...        % State
                                        repmat(string(name), numel(vals),1), ...% MouseID
                                        (1:numel(vals)).', vals(:), ...         % SampleIdx, HFD
                                        'VariableNames', {'Group','State','MouseID','SampleIdx','HFD'}); %#ok<AGROW>
        end
    end

    % -------- build group arrays (concatenate all samples across mice) --------
    HFD_group = struct();
    for st = ["Wake","REM","NREM"]
        WTvals = []; DSvals = [];
        if ~isempty(HFD_cells.(st).WT), WTvals = vertcat(HFD_cells.(st).WT{:}); end
        if ~isempty(HFD_cells.(st).DS), DSvals = vertcat(HFD_cells.(st).DS{:}); end
        HFD_group.(st).WT = WTvals;
        HFD_group.(st).DS = DSvals;
    end

    % ---------------------------- plots (unchanged) ----------------------------
    for st = ["Wake","REM","NREM"]
        WTvals = HFD_group.(st).WT; DSvals = HFD_group.(st).DS;
        if isempty(WTvals) && isempty(DSvals), continue; end
        figure;
        boxplot([WTvals; DSvals],[ones(size(WTvals)); 2*ones(size(DSvals))], 'Colors','k','MedianStyle','line','Symbol','');
        set(gca,'XTick',[1 2],'XTickLabel',{'WT','DS'}); ylabel('Higuchi FD'); title(sprintf('HFD: %s', st));
        hold on;
        if ~isempty(WTvals), WTm = mean(WTvals); WTe = std(WTvals)/sqrt(numel(WTvals)); plot([0.8 1.2],[WTm WTm],'r-','LineWidth',2); errorbar(1,WTm,WTe,'r','CapSize',10); end
        if ~isempty(DSvals), DSm = mean(DSvals); DSe = std(DSvals)/sqrt(numel(DSvals)); plot([1.8 2.2],[DSm DSm],'r-','LineWidth',2); errorbar(2,DSm,DSe,'r','CapSize',10); end
        hold off;
    end
    logmsg('HFD: grouping done.');

    % ============================== CSV EXPORTS ===============================
    try
        % ---- per-mouse long (resultsDir) ----
        if ~isempty(perMouseRows)
            writetable(vertcat(perMouseRows{:}), fullfile(resultsDir,'hfd_per_mouse_long.csv'));
        end

        % ---- group long & summary stats (resultsDir) ----
        Tall = table(); Sums = table();
        for st = ["Wake","REM","NREM"]
            % long (all samples pooled per group)
            if ~isempty(HFD_group.(st).WT)
                Tw = table(repmat("WT", numel(HFD_group.(st).WT),1), repmat(st.', numel(HFD_group.(st).WT),1), HFD_group.(st).WT, ...
                           'VariableNames', {'Group','State','HFD'});
                Tall = [Tall; Tw]; %#ok<AGROW>
            end
            if ~isempty(HFD_group.(st).DS)
                Td = table(repmat("DS", numel(HFD_group.(st).DS),1), repmat(st.', numel(HFD_group.(st).DS),1), HFD_group.(st).DS, ...
                           'VariableNames', {'Group','State','HFD'});
                Tall = [Tall; Td]; %#ok<AGROW>
            end

            % summary
            if ~isempty(HFD_group.(st).WT)
                vals = HFD_group.(st).WT;
                Sums = [Sums; table("WT", st, numel(vals), mean(vals), std(vals), std(vals)/sqrt(numel(vals)), ...
                         'VariableNames', {'Group','State','N','Mean','Std','SEM'})]; %#ok<AGROW>
            end
            if ~isempty(HFD_group.(st).DS)
                vals = HFD_group.(st).DS;
                Sums = [Sums; table("DS", st, numel(vals), mean(vals), std(vals), std(vals)/sqrt(numel(vals)), ...
                         'VariableNames', {'Group','State','N','Mean','Std','SEM'})]; %#ok<AGROW>
            end
        end

        if ~isempty(Tall)
            writetable(Tall, fullfile(resultsDir,'hfd_group_long.csv'));
        end
        if ~isempty(Sums)
            writetable(Sums, fullfile(resultsDir,'hfd_group_summary.csv'));
        end

        % ---- metadata (resultsDir) ----
        fields = {'fs','epoch_sec','baseBP_low','baseBP_high','fsNew','firOrd','winSec','ovlSec','kmax','groupOnly'};
        values = {fs, epoch_sec, baseBP(1), baseBP(2), fsNew, firOrd, winSec, ovlSec, kmax, logical(groupOnly)};
        MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
        writetable(MF, fullfile(resultsDir,'hfd_metadata.csv'));

        logmsg('HFD: CSV exports written.');
    catch ME
        logmsg('HFD CSV export failed: %s', ME.message);
    end
end

%% ------------------------ INTERNAL: Beta-Bursts ----------------------------
function runBeta_Internal(root, fs, epoch_sec, codes, betaBand, thrPrct, excluded, xlimsAll)
    logmsg('Beta-Bursts: fs=%g, epoch=%gs, beta=[%g %g], thr=%gth pct', ...
        fs, epoch_sec, betaBand(1), betaBand(2), thrPrct);

    % results folder for cross-mouse CSVs
    resultsDir = fullfile(root, 'Beta-Bursts Results');
    if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

    epoch_len = round(fs*epoch_sec);
    [b_beta, a_beta] = butter(4, betaBand/(fs/2), 'bandpass');
    wake_code = codes(1);

    d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

    WT_amp=[]; WT_dur=[]; WT_freq=[]; WT_ibi=[];
    DS_amp=[]; DS_dur=[]; DS_freq=[]; DS_ibi=[];

    % for per-mouse long CSV
    perMouseRows = {};

    for k = 1:numel(d)
        mouseName = d(k).name;
        if any(strcmp(mouseName, excluded)), logmsg('Skip excluded: %s', mouseName); continue; end

        mdir   = fullfile(root, mouseName);
        pathR  = fullfile(mdir,'EEG(R).mat');
        pathL  = fullfile(mdir,'EEG(L).mat');
        pathLb = fullfile(mdir,'labels.mat');

        if ~exist(pathR,'file') || ~exist(pathL,'file') || ~exist(pathLb,'file')
            logmsg('Missing files in %s (need EEG(R).mat, EEG(L).mat, labels.mat).', mouseName);
            continue;
        end

        % --- robust loads (prefer merged_vector, else first numeric vector) ---
        SR = load(pathR); SL = load(pathL); L = load(pathLb);
        EEG_R = pickVecPreferMerged(SR);
        EEG_L = pickVecPreferMerged(SL);
        if isempty(EEG_R) || isempty(EEG_L) || ~isfield(L,'labels')
            logmsg('Bad EEG/labels in %s; skipping.', mouseName); continue;
        end
        labels = L.labels(:).';      % row

        % --- mean EEG; align; epoch accounting (like original) ---------------
        len = min(numel(EEG_R), numel(EEG_L));
        EEG_R = EEG_R(1:len); EEG_L = EEG_L(1:len);
        EEG_mean = mean([EEG_R(:).'; EEG_L(:).'], 1);   % 1 x N

        num_epochs = floor(numel(EEG_mean)/epoch_len);
        if num_epochs < 1, logmsg('Too short recording in %s; skipping.', mouseName); continue; end

        labels = labels(1:min(num_epochs, numel(labels)));
        num_epochs = numel(labels);
        N_use  = num_epochs * epoch_len;
        EEG_use = EEG_mean(1:N_use);

        % --- sample-level Wake mask from epoch labels ------------------------
        wakeMask = false(1, N_use);
        for e = 1:num_epochs
            if labels(e) == wake_code
                s = (e-1)*epoch_len + 1;
                t = e*epoch_len;
                wakeMask(s:t) = true;
            end
        end
        if ~any(wakeMask)
            logmsg('No Wake samples (label=%d) in %s; skipping.', wake_code, mouseName);
            continue;
        end

        % --- beta filter WHOLE timeline, Hilbert power, one global threshold --
        try
            beta_sig   = filtfilt(b_beta, a_beta, EEG_use);
        catch
            logmsg('Filtering failed in %s; skipping.', mouseName); continue;
        end
        beta_power = abs(hilbert(beta_sig)).^2;

        thr = prctile(beta_power(wakeMask), thrPrct);
        isBurst = (beta_power > thr) & wakeMask;

        % onsets/offsets (inclusive), exactly as in the script
        dB = diff([false, isBurst, false]);
        onsets  = find(dB ==  1);
        offsets = find(dB == -1) - 1;

        % --- feature extraction (with frequency gate) ------------------------
        burst_duration  = [];
        burst_amplitude = [];
        burst_frequency = [];
        IBI_withinWake  = [];
        IBI_all         = [];

        beta_min = betaBand(1); beta_max = betaBand(2);
        nBursts = min(numel(onsets), numel(offsets));
        for iB = 1:nBursts
            s = onsets(iB); eix = offsets(iB);
            if eix <= s, continue; end

            seg = beta_sig(s:eix);
            bf  = meanfreq(seg, fs);

            if bf >= beta_min && bf <= beta_max
                burst_duration(end+1,1)  = (eix - s) / fs;
                burst_amplitude(end+1,1) = max(beta_power(s:eix));
                burst_frequency(end+1,1) = bf;

                if iB > 1
                    dt = (s - offsets(iB-1)) / fs;   % real-time gap
                    IBI_all(end+1,1) = dt;

                    gapMask = wakeMask(offsets(iB-1)+1 : s-1);
                    if ~isempty(gapMask) && all(gapMask)
                        IBI_withinWake(end+1,1) = dt;
                    end
                end
            end
        end

        % --- pad-to-table like original; include IBI_all ---------------------
        S = struct();
        S.burst_duration  = burst_duration;
        S.burst_amplitude = burst_amplitude;
        S.burst_frequency = burst_frequency;
        S.IBI             = IBI_withinWake;   % within-Wake (used for CDFs)
        S.IBI_all         = IBI_all;          % real-time (informational)
        T = padToTableLikeOriginal(S);

        % save per-mouse feature file
        save(fullfile(mdir,'beta-bursts features.mat'),'T');
        try, writetable(T, fullfile(mdir,'beta-bursts features.xlsx')); end
        logmsg('Saved features in %s (n=%d)', mouseName, height(T));

        % ---- per-mouse CSV (tidy) in a subfolder to avoid clutter ----------
        try
            outdirMouse = fullfile(mdir, 'Beta-Bursts'); 
            if ~exist(outdirMouse,'dir'), mkdir(outdirMouse); end
            writetable(T, fullfile(outdirMouse, 'beta_bursts_features.csv'));
        catch ME
            logmsg('Per-mouse CSV failed in %s: %s', mouseName, ME.message);
        end

        % aggregate for CDFs (within-Wake IBI, as in script)
        if contains(mouseName,'WT','IgnoreCase',true)
            groupName = "WT";
            WT_amp = [WT_amp; T.burst_amplitude];
            WT_dur = [WT_dur; T.burst_duration];
            WT_freq= [WT_freq; T.burst_frequency];
            WT_ibi = [WT_ibi; T.IBI];
        elseif contains(mouseName,'DS','IgnoreCase',true)
            groupName = "DS";
            DS_amp = [DS_amp; T.burst_amplitude];
            DS_dur = [DS_dur; T.burst_duration];
            DS_freq= [DS_freq; T.burst_frequency];
            DS_ibi = [DS_ibi; T.IBI];
        else
            groupName = ""; % unclassified
            logmsg('Folder %s not classified (name must contain WT or DS).', mouseName);
        end

        % accumulate per-mouse long rows (if classified)
        if strlength(groupName)>0
            perMouseRows{end+1} = table( ...
                repmat(groupName, numel(T.burst_amplitude),1), repmat(string(mouseName), numel(T.burst_amplitude),1), ...
                repmat("Amplitude", numel(T.burst_amplitude),1), T.burst_amplitude, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            perMouseRows{end+1} = table( ...
                repmat(groupName, numel(T.burst_duration),1), repmat(string(mouseName), numel(T.burst_duration),1), ...
                repmat("Duration_s", numel(T.burst_duration),1), T.burst_duration, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            perMouseRows{end+1} = table( ...
                repmat(groupName, numel(T.burst_frequency),1), repmat(string(mouseName), numel(T.burst_frequency),1), ...
                repmat("Frequency_Hz", numel(T.burst_frequency),1), T.burst_frequency, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            perMouseRows{end+1} = table( ...
                repmat(groupName, numel(T.IBI),1), repmat(string(mouseName), numel(T.IBI),1), ...
                repmat("IBI_s", numel(T.IBI),1), T.IBI, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            if ismember('IBI_all', T.Properties.VariableNames)
                perMouseRows{end+1} = table( ...
                    repmat(groupName, numel(T.IBI_all),1), repmat(string(mouseName), numel(T.IBI_all),1), ...
                    repmat("IBI_all_s", numel(T.IBI_all),1), T.IBI_all, ...
                    'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            end
        end
    end

    % ------------------------------ CDF plots --------------------------------
    plotCDF_likeScript(WT_amp,DS_amp,'Amplitude',      xlimsAll.amp);
    plotCDF_likeScript(WT_dur,DS_dur,'Duration (s)',   xlimsAll.dur);
    plotCDF_likeScript(WT_freq,DS_freq,'Frequency (Hz)',xlimsAll.freq);
    plotCDF_likeScript(WT_ibi,DS_ibi,'IBI (s)',        xlimsAll.ibi);
    plotCDF_likeScript(WT_ibi(WT_ibi<0.05), DS_ibi(DS_ibi<0.05), 'short IBI (< 50 ms)', xlimsAll.ibiShort);
    plotCDF_likeScript(WT_ibi(WT_ibi>0.2),  DS_ibi(DS_ibi>0.2),  'long IBI (> 200 ms)', xlimsAll.ibiLong);

    % ------------------------------ CSV EXPORTS ------------------------------
    try
        % Per-mouse long
        if ~isempty(perMouseRows)
            writetable(vertcat(perMouseRows{:}), fullfile(resultsDir, 'beta_bursts_per_mouse_long.csv'));
        end

        % Group pooled (long) for main metrics (WT vs DS)
        G = table();
        if ~isempty(WT_amp),  G = [G; table(repmat("WT",numel(WT_amp),1),  repmat("Amplitude",numel(WT_amp),1),  WT_amp,  'VariableNames', {'Group','Metric','Value'})]; end
        if ~isempty(DS_amp),  G = [G; table(repmat("DS",numel(DS_amp),1),  repmat("Amplitude",numel(DS_amp),1),  DS_amp,  'VariableNames', {'Group','Metric','Value'})]; end
        if ~isempty(WT_dur),  G = [G; table(repmat("WT",numel(WT_dur),1),  repmat("Duration_s",numel(WT_dur),1),  WT_dur,  'VariableNames', {'Group','Metric','Value'})]; end
        if ~isempty(DS_dur),  G = [G; table(repmat("DS",numel(DS_dur),1),  repmat("Duration_s",numel(DS_dur),1),  DS_dur,  'VariableNames', {'Group','Metric','Value'})]; end
        if ~isempty(WT_freq), G = [G; table(repmat("WT",numel(WT_freq),1), repmat("Frequency_Hz",numel(WT_freq),1), WT_freq, 'VariableNames', {'Group','Metric','Value'})]; end
        if ~isempty(DS_freq), G = [G; table(repmat("DS",numel(DS_freq),1), repmat("Frequency_Hz",numel(DS_freq),1), DS_freq, 'VariableNames', {'Group','Metric','Value'})]; end
        if ~isempty(WT_ibi),  G = [G; table(repmat("WT",numel(WT_ibi),1),  repmat("IBI_s",numel(WT_ibi),1),       WT_ibi,  'VariableNames', {'Group','Metric','Value'})]; end
        if ~isempty(DS_ibi),  G = [G; table(repmat("DS",numel(DS_ibi),1),  repmat("IBI_s",numel(DS_ibi),1),       DS_ibi,  'VariableNames', {'Group','Metric','Value'})]; end

        if ~isempty(G)
            writetable(G, fullfile(resultsDir, 'beta_bursts_group_long.csv'));
        end

        % Summary stats (per group & metric)
        Sums = table();
        Sums = [Sums; summarizeMetric("WT","Amplitude",WT_amp);   summarizeMetric("DS","Amplitude",DS_amp)];
        Sums = [Sums; summarizeMetric("WT","Duration_s",WT_dur);  summarizeMetric("DS","Duration_s",DS_dur)];
        Sums = [Sums; summarizeMetric("WT","Frequency_Hz",WT_freq); summarizeMetric("DS","Frequency_Hz",DS_freq)];
        Sums = [Sums; summarizeMetric("WT","IBI_s",WT_ibi);       summarizeMetric("DS","IBI_s",DS_ibi)];
        if ~isempty(Sums)
            writetable(Sums, fullfile(resultsDir, 'beta_bursts_group_summary.csv'));
        end

        % Metadata
        fields = {'fs','epoch_sec','beta_low','beta_high','thrPrct','wake_code'};
        values = {fs, epoch_sec, betaBand(1), betaBand(2), thrPrct, wake_code};
        MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
        writetable(MF, fullfile(resultsDir, 'beta_bursts_metadata.csv'));

        logmsg('Beta-Bursts: CSV exports written.');
    catch ME
        logmsg('Beta-Bursts CSV export failed: %s', ME.message);
    end

    logmsg('Beta-Bursts: done.');
end

% -------------------------- local helper -----------------------------------
function T = summarizeMetric(grp, metric, vals)
    if isempty(vals)
        T = table(); return;
    end
    n = numel(vals);
    mu = mean(vals); sd = std(vals); sem = sd/sqrt(n);
    T = table(repmat(string(grp),1,1), repmat(string(metric),1,1), n, mu, sd, sem, ...
        'VariableNames', {'Group','Metric','N','Mean','Std','SEM'});
end


%% ----------------- INTERNAL: MDF/SEF/Peak from RAW EEG ---------------------
function runMDFSEF_Internal(root, fs, epoch_sec, codes, bp, winN, ovN, sefPerc, doGate, mode, excluded, autoCompute)
    % codes is [Wake REM NREM] in that order (as in labEdit).
    logmsg('MDF/SEF/Peak: fs=%g, epoch=%gs, BP=[%g %g], win=%d, ov=%d, SEF=%.2f, gate=%d, mode=%s', ...
        fs, epoch_sec, bp(1), bp(2), winN, ovN, sefPerc, doGate, mode);

    % Group-level results folder (used only in group/both modes)
    resultsDir = fullfile(root, 'MDF-SEF-Peak Results');
    if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end

    epoch_len = round(fs*epoch_sec);
    nfft = 2*winN;
    [b_bp, a_bp] = butter(4, bp/(fs/2), 'bandpass');

    % ---------- PER-MOUSE ----------
    if any(strcmp(mode, {'per','both'}))
        [labFile, labPath] = uigetfile('*.mat','Select labels.mat');
        if isequal(labFile,0), logmsg('Per-mouse: cancelled.'); return; end
        L = load(fullfile(labPath,labFile));
        labels = tryPickLabels(L);
        if isempty(labels), logmsg('labels not found in %s', labFile); return; end
        labels = labels(:).'; % row

        [eegFile, eegPath] = uigetfile('*.mat','Select RAW EEG (.mat) with a single vector');
        if isequal(eegFile,0), logmsg('Per-mouse: cancelled.'); return; end
        S = load(fullfile(eegPath,eegFile));
        EEG = localPickVec(S);
        if isempty(EEG), logmsg('No numeric vector in %s', eegFile); return; end
        EEG = double(EEG(:));

        % Filter
        try
            EEGf = filtfilt(b_bp,a_bp,EEG);
        catch
            logmsg('Filtering failed; using unfiltered signal.');
            EEGf = EEG;
        end

        % Epoching aligned to labels
        num_epochs = floor(numel(EEGf)/epoch_len);
        if num_epochs<1, logmsg('Too short recording.'); return; end
        labels = labels(1:min(num_epochs, numel(labels)));
        num_epochs = numel(labels);
        EEGf = EEGf(1:num_epochs*epoch_len);
        EEGf = reshape(EEGf, epoch_len, []);

        % Compute per-state metrics
        Sres = compute_MDF_SEF_Peak_per_state(EEGf, labels, codes, fs, winN, ovN, nfft, sefPerc);

        % Save beside EEG file
        outPath = fullfile(eegPath,'SeF_MDF_data.mat');
        S = Sres; %#ok<NASGU>
        save(outPath,'S');
        logmsg('Saved per-mouse file: %s', outPath);

        % Quick means to console
        print_means_to_console('Per-mouse', Sres);

        % ---- Per-mouse CSV export (long) ---------------------------------
        try
            perMouseDir = fullfile(eegPath, 'MDF-SEF-Peak');
            if ~exist(perMouseDir,'dir'), mkdir(perMouseDir); end
            Tpm = per_mouse_vectors_long(Sres);  % State, Metric, Value
            if ~isempty(Tpm)
                writetable(Tpm, fullfile(perMouseDir, 'mdf_sef_peak_per_mouse.csv'));
            end
        catch ME
            logmsg('Per-mouse CSV export failed: %s', ME.message);
        end
    end

    % ---------- GROUP (WT vs DS) ----------
    if any(strcmp(mode, {'group','both'}))
        if ~isfolder(root), logmsg('Root folder not set or invalid.'); return; end

        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

        % Containers of per-mouse means (so each mouse counts once)
        WT = init_group_bin(); DS = init_group_bin();

        % Also collect per-mouse rows for CSV (long)
        perMouseRows = {};  % each is a table(Group,MouseID,State,Metric,Value)

        for k=1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('Excluded: %s', name); continue; end
            mdir = fullfile(root,name);

            % Load per-mouse result or auto-compute
            perMousePath = fullfile(mdir,'SeF_MDF_data.mat');
            if ~exist(perMousePath,'file')
                if ~autoCompute
                    logmsg('Missing SeF_MDF_data for %s (skip).', name);
                    continue;
                end
                % Try compute from RAW EEG + labels
                labPath = fullfile(mdir,'labels.mat');
                eegCand = pick_first_mat(mdir);
                if ~exist(labPath,'file') || isempty(eegCand)
                    logmsg('Missing labels or RAW EEG in %s (skip).', name);
                    continue;
                end
                L = load(labPath); labels = tryPickLabels(L);
                if isempty(labels), logmsg('labels missing in %s', labPath); continue; end
                Sraw = load(eegCand); EEG = localPickVec(Sraw);
                if isempty(EEG), logmsg('No vector EEG in %s', eegCand); continue; end

                EEG = double(EEG(:));
                try, EEGf = filtfilt(b_bp,a_bp,EEG); catch, EEGf=EEG; end
                num_epochs = floor(numel(EEGf)/epoch_len);
                if num_epochs<1, logmsg('Too short: %s', name); continue; end
                labels = labels(1:min(num_epochs,numel(labels)));
                num_epochs = numel(labels);
                EEGf = EEGf(1:num_epochs*epoch_len);
                EEGf = reshape(EEGf, epoch_len, []);

                Sres = compute_MDF_SEF_Peak_per_state(EEGf, labels, codes, fs, winN, ovN, nfft, sefPerc);
                S = Sres; %#ok<NASGU>
                save(perMousePath,'S');
                logmsg('Auto-computed %s', perMousePath);
            else
                R = load(perMousePath);
                if ~isfield(R,'S'), logmsg('S missing in %s', perMousePath); continue; end
                Sres = R.S;
            end

            % Optional peak-frequency gating for REM/NREM (group step only)
            if doGate
                Sres = apply_peak_gating(Sres);
            end

            % Convert per-mouse vectors to a single mean per metric/state
            mouseMeans = per_mouse_means(Sres);

            % classification
            isWT = contains(name,'WT','IgnoreCase',true);
            isDS = contains(name,'DS','IgnoreCase',true);

            if isWT
                WT = append_mouse(WT, mouseMeans);
            elseif isDS
                DS = append_mouse(DS, mouseMeans);
            else
                continue; % neither WT nor DS — ignore
            end

            % accumulate per-mouse long rows for CSV
            try
                grp = "WT"; if isDS, grp = "DS"; end
                perMouseRows{end+1} = rows_from_mouseMeans(name, grp, mouseMeans); %#ok<AGROW>
            catch ME
                logmsg('Per-mouse long row build failed for %s: %s', name, ME.message);
            end
        end

        % Make bar+SEM plots with per-mouse dots
        plot_group_bars(WT, DS, 'MDF (Hz)', 'mdf');
        plot_group_bars(WT, DS, 'SEF (Hz)', 'sef');
        plot_group_bars(WT, DS, 'Peak (Hz)', 'peak');

        % Save a compact summary
        summaryPath = fullfile(root,'group_mdf_sef_peak_summary.mat');
        save(summaryPath,'WT','DS','fs','epoch_sec','bp','winN','ovN','sefPerc','doGate','codes');
        logmsg('Saved group summary: %s', summaryPath);

        % ------------------------ CSV EXPORTS (group) ------------------------
        try
            % 1) Per-mouse long (one row per mouse × state × metric)
            if ~isempty(perMouseRows)
                writetable(vertcat(perMouseRows{:}), ...
                    fullfile(resultsDir, 'mdf_sef_peak_per_mouse_long.csv'));
            end

            % 2) Group pooled (per-mouse means) — long
            G = table();
            G = [G; group_long_from_bin("WT", WT)];
            G = [G; group_long_from_bin("DS", DS)];
            if ~isempty(G)
                writetable(G, fullfile(resultsDir, 'mdf_sef_peak_group_long.csv'));
            end

            % 3) Summary stats from per-mouse means
            Sums = table();
            Sums = [Sums; group_summary_from_bin("WT", WT)];
            Sums = [Sums; group_summary_from_bin("DS", DS)];
            if ~isempty(Sums)
                writetable(Sums, fullfile(resultsDir, 'mdf_sef_peak_group_summary.csv'));
            end

            % 4) Metadata
            fields = {'fs','epoch_sec','bp_low','bp_high','winN','ovN','nfft','sefPerc','doGate','mode','codes_wake','codes_rem','codes_nrem'};
            values = {fs, epoch_sec, bp(1), bp(2), winN, ovN, nfft, sefPerc, logical(doGate), string(mode), codes(1), codes(2), codes(3)};
            MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
            writetable(MF, fullfile(resultsDir, 'mdf_sef_peak_metadata.csv'));

            logmsg('MDF/SEF/Peak: CSV exports written.');
        catch ME
            logmsg('MDF/SEF/Peak CSV export failed: %s', ME.message);
        end
    end

    logmsg('MDF/SEF/Peak: done.');

    % ----------------- helpers (nested) -----------------
    function labels = tryPickLabels(L)
        labels = [];
        if isfield(L,'labels'), labels = L.labels; end
        if isempty(labels)
            % try to find a vector field named like labels
            f = fieldnames(L);
            for ii=1:numel(f)
                v = L.(f{ii});
                if isnumeric(v) && isvector(v)
                    labels = v;
                    break;
                end
            end
        end
    end

    function v = localPickVec(S)
        v = [];
        f = fieldnames(S);
        % Prefer obvious names
        pref = find(ismember(lower(f), {'eeg','raw','signal','data','eeg_raw','eegvec','vec','x'}),1);
        if ~isempty(pref)
            cand = S.(f{pref});
            if isnumeric(cand) && isvector(cand), v = cand; return; end
        end
        % otherwise first numeric vector
        for ii=1:numel(f)
            cand = S.(f{ii});
            if isnumeric(cand) && isvector(cand)
                v = cand; return;
            end
        end
    end

    function p = pick_first_mat(mdir)
        % pick the first .mat that is not SeF_MDF_data or labels
        L = dir(fullfile(mdir,'*.mat'));
        p = '';
        for ii=1:numel(L)
            nm = L(ii).name;
            if contains(nm,'labels','IgnoreCase',true), continue; end
            if contains(nm,'SeF_MDF_data','IgnoreCase',true), continue; end
            p = fullfile(mdir,nm); return;
        end
    end

    function S = compute_MDF_SEF_Peak_per_state(EEGf, labels, codes, fs, winN, ovN, nfft, sefPerc)
        % Split epochs by state, compute metrics, drop SEF outliers per state.
        % Return S.wake/nrem/rem .mdf/.sef/.peak_freq vectors.
        idxWake = find(labels==codes(1));
        idxREM  = find(labels==codes(2));
        idxNREM = find(labels==codes(3));

        S = struct('wake',struct(),'rem',struct(),'nrem',struct());
        S.wake = do_state(EEGf, idxWake);
        S.rem  = do_state(EEGf, idxREM);
        S.nrem = do_state(EEGf, idxNREM);

        function Z = do_state(X, idx)
            Z = struct('mdf',[],'sef',[],'peak_freq',[]);
            if isempty(idx), return; end
            mdf=[]; sef=[]; pk=[];
            for e = idx
                sig = X(:,e);
                [Pxx, f] = pwelch(sig, winN, ovN, nfft, fs);
                tot = sum(Pxx);
                c = cumsum(Pxx);
                mi = find(c >= tot/2, 1, 'first');
                si = find(c >= sefPerc*tot, 1, 'first');
                [~,pi] = max(Pxx);
                mdf(end+1,1) = f(mi);
                sef(end+1,1) = f(si);
                pk (end+1,1) = f(pi);
            end
            % Remove SEF outliers: > mean + 3*SD (per state)
            if ~isempty(sef)
                m = mean(sef); s = std(sef);
                keep = sef <= (m + 3*s);
                mdf = mdf(keep); sef = sef(keep); pk = pk(keep);
            end
            Z.mdf = mdf; Z.sef = sef; Z.peak_freq = pk;
        end
    end

    function S = apply_peak_gating(S)
        % Keep epochs in REM with peak in [4.8, 9.9], in NREM with peak in [0.8, 4.8].
        if ~isempty(S.rem.peak_freq)
            keep = S.rem.peak_freq >= 4.8 & S.rem.peak_freq <= 9.9;
            S.rem.peak_freq = S.rem.peak_freq(keep);
            S.rem.mdf       = S.rem.mdf(keep);
            S.rem.sef       = S.rem.sef(keep);
        end
        if ~isempty(S.nrem.peak_freq)
            keep = S.nrem.peak_freq >= 0.8 & S.nrem.peak_freq <= 4.8;
            S.nrem.peak_freq = S.nrem.peak_freq(keep);
            S.nrem.mdf       = S.nrem.mdf(keep);
            S.nrem.sef       = S.nrem.sef(keep);
        end
    end

    function G = init_group_bin()
        % store per-mouse means (vectors: one value per mouse)
        G = struct();
        states = {'wake','nrem','rem'};
        metrics = {'mdf','sef','peak'};
        for s=1:numel(states)
            for m=1:numel(metrics)
                G.(states{s}).(metrics{m}) = [];
            end
        end
    end

    function means = per_mouse_means(S)
        means = struct();
        for st = ["wake","nrem","rem"]
            v = S.(st);
            means.(st).mdf  = mean(v.mdf, 'omitnan');
            means.(st).sef  = mean(v.sef, 'omitnan');
            means.(st).peak = mean(v.peak_freq, 'omitnan');
        end
    end

    function G = append_mouse(G, M)
        for st = ["wake","nrem","rem"]
            G.(st).mdf  = [G.(st).mdf;  M.(st).mdf];
            G.(st).sef  = [G.(st).sef;  M.(st).sef];
            G.(st).peak = [G.(st).peak; M.(st).peak];
        end
    end

    function print_means_to_console(tag, S)
        mu = @(x) mean(x,'omitnan');
        logmsg('%s means — Wake: MDF %.2f, SEF %.2f, Peak %.2f', tag, mu(S.wake.mdf), mu(S.wake.sef), mu(S.wake.peak_freq));
        logmsg('%s means — NREM: MDF %.2f, SEF %.2f, Peak %.2f', tag, mu(S.nrem.mdf), mu(S.nrem.sef), mu(S.nrem.peak_freq));
        logmsg('%s means — REM : MDF %.2f, SEF %.2f, Peak %.2f', tag, mu(S.rem.mdf),  mu(S.rem.sef),  mu(S.rem.peak_freq));
    end

    function plot_group_bars(WT, DS, ylab, field)
        % field is 'mdf' | 'sef' | 'peak'
        states = {'Wake','NREM','REM'};
        stateKeys = {'wake','nrem','rem'};
        for si = 1:numel(states)
            sk = stateKeys{si};
            WTvals = WT.(sk).(field); WTvals = WTvals(isfinite(WTvals));
            DSvals = DS.(sk).(field); DSvals = DSvals(isfinite(DSvals));
            if isempty(WTvals) && isempty(DSvals), continue; end

            figure; hold on;
            muWT = mean(WTvals,'omitnan'); muDS = mean(DSvals,'omitnan');
            seWT = std(WTvals,'omitnan')/sqrt(max(1,numel(WTvals)));
            seDS = std(DSvals,'omitnan')/sqrt(max(1,numel(DSvals)));
            bar(1, muWT, 'FaceColor',[0 0.447 0.741], 'BarWidth',0.5);
            bar(2, muDS, 'FaceColor',[0.85 0.325 0.098], 'BarWidth',0.5);
            errorbar([1 2], [muWT muDS], [seWT seDS], 'k','linestyle','none','LineWidth',1.5);
            plot( ones(size(WTvals)), WTvals, 'ko','MarkerFaceColor','k','MarkerSize',6 );
            plot( 2*ones(size(DSvals)), DSvals, 'ko','MarkerFaceColor','k','MarkerSize',6 );
            xlim([0.5 2.5]); set(gca,'XTick',[1 2],'XTickLabel',{'WT','DS'});
            ylabel(ylab); title(sprintf('%s — %s', upper(field), states{si}));
            grid on; hold off;
        end
    end

    % --------------- CSV helper builders (nested) -----------------
    function T = per_mouse_vectors_long(S)
        % Convert S.(wake|nrem|rem).(mdf|sef|peak_freq) vectors into long table
        T = table(); 
        stNames = {'Wake','NREM','REM'}; stKeys = {'wake','nrem','rem'};
        metrics = {'mdf','sef','peak_freq'};
        mnames  = {'MDF_Hz','SEF_Hz','Peak_Hz'};
        for si = 1:numel(stKeys)
            sk = stKeys{si}; sName = stNames{si};
            for mi = 1:numel(metrics)
                mk = metrics{mi}; mName = mnames{mi};
                vals = S.(sk).(mk);
                if isempty(vals), continue; end
                T = [T; table(repmat(string(sName),numel(vals),1), repmat(string(mName),numel(vals),1), vals(:), ...
                    'VariableNames', {'State','Metric','Value'})]; %#ok<AGROW>
            end
        end
    end

    function T = rows_from_mouseMeans(mouseName, grp, M)
        % Build one long table of per-mouse MEANS over epochs
        stNames = {'Wake','NREM','REM'}; stKeys = {'wake','nrem','rem'};
        metrics = {'mdf','sef','peak'}; mnames = {'MDF_Hz','SEF_Hz','Peak_Hz'};
        T = table();
        for si = 1:numel(stKeys)
            sk = stKeys{si}; sName = stNames{si};
            for mi = 1:numel(metrics)
                mk = metrics{mi}; mName = mnames{mi};
                v = M.(sk).(mk);
                if ~isfinite(v), continue; end
                T = [T; table( ...
                    repmat(string(grp),1,1), repmat(string(mouseName),1,1), ...
                    repmat(string(sName),1,1), repmat(string(mName),1,1), v, ...
                    'VariableNames', {'Group','MouseID','State','Metric','Value'})]; %#ok<AGROW>
            end
        end
    end

    function T = group_long_from_bin(grpName, Gbin)
        % Build pooled long table from per-mouse means
        stNames = {'Wake','NREM','REM'}; stKeys = {'wake','nrem','rem'};
        fields = {'mdf','sef','peak'}; mnames = {'MDF_Hz','SEF_Hz','Peak_Hz'};
        T = table();
        for si = 1:numel(stKeys)
            sk = stKeys{si}; sName = stNames{si};
            for fi = 1:numel(fields)
                fk = fields{fi}; mName = mnames{fi};
                vals = Gbin.(sk).(fk);
                vals = vals(isfinite(vals));
                if isempty(vals), continue; end
                T = [T; table(repmat(string(grpName),numel(vals),1), repmat(string(sName),numel(vals),1), ...
                              repmat(string(mName),numel(vals),1), vals(:), ...
                              'VariableNames', {'Group','State','Metric','Value'})]; %#ok<AGROW>
            end
        end
    end

    function S = group_summary_from_bin(grpName, Gbin)
        % Summary stats (per-mouse means) per state × metric
        stNames = {'Wake','NREM','REM'}; stKeys = {'wake','nrem','rem'};
        fields = {'mdf','sef','peak'}; mnames = {'MDF_Hz','SEF_Hz','Peak_Hz'};
        S = table();
        for si = 1:numel(stKeys)
            sk = stKeys{si}; sName = stNames{si};
            for fi = 1:numel(fields)
                fk = fields{fi}; mName = mnames{fi};
                vals = Gbin.(sk).(fk);
                vals = vals(isfinite(vals));
                if isempty(vals), continue; end
                n = numel(vals); mu = mean(vals); sd = std(vals); sem = sd/sqrt(n);
                S = [S; table(string(grpName), string(sName), string(mName), n, mu, sd, sem, ...
                    'VariableNames', {'Group','State','Metric','N','Mean','Std','SEM'})]; %#ok<AGROW>
            end
        end
    end
end

%% ------------------------------ utilities ----------------------------------
    function v = pickVec(S)
        v = []; fns = fieldnames(S);
        if isfield(S,'merged_vector'), v = S.merged_vector(:); return; end
        for ii=1:numel(fns)
            x = S.(fns{ii});
            if isnumeric(x) && isvector(x), v = x(:); return; end
        end
    end
    function T = padToTable(S)
        fns = fieldnames(S); maxL=0;
        for ii=1:numel(fns)
            v=S.(fns{ii}); if isrow(v), v=v.'; end; S.(fns{ii})=v; maxL=max(maxL,numel(v));
        end
        for ii=1:numel(fns)
            v=S.(fns{ii}); if numel(v)<maxL, S.(fns{ii})=[v; NaN(maxL-numel(v),1)]; end
        end
        T = struct2table(S);
    end
    function xs = parseList(s)
        s = strtrim(s);
        if isempty(s), xs={}; else, xs = regexp(s,'\s*,\s*','split'); end
    end
    function [W,R,N] = parseLabelCodes(s)
        a = sscanf(s,'%f'); if numel(a)~=3, error('Label codes must be three numbers: "Wake REM NREM".'); end
        W=a(1); R=a(2); N=a(3);
    end
    function b = parseBand(s)
        a = sscanf(s,'%f'); if numel(a)~=2, error('Band must be "low high".'); end
        b = sort(a(:)).';
    end
    function xlims = parseXlimList(s)
        parts = regexp(s,';','split');
        get = @(i) eval(parts{i});
        xlims.amp      = get(1);
        xlims.dur      = get(2);
        xlims.freq     = get(3);
        xlims.ibi      = get(4);
        xlims.ibiShort = get(5);
        xlims.ibiLong  = get(6);
    end
    function logmsg(fmt, varargin)
        s = sprintf([fmt '\n'], varargin{:});
        logBox.Value = [logBox.Value; s];
        drawnow;
    end
    function out = ternary(cond,a,b); if cond, out=a; else, out=b; end; end
    function plotCDF(WT,DS,ttl,xl)
        WT = WT(~isnan(WT)); DS = DS(~isnan(DS));
        [F1,X1]=ecdf(WT); [F2,X2]=ecdf(DS);
        figure; plot(X1,F1,'-','LineWidth',1,'Color',[.5 .5 .5]); hold on;
        plot(X2,F2,'-','LineWidth',1,'Color',[.3 .6 1]); hold off;
        xlabel(ttl); ylabel('Cumulative frequency'); title(['CDF of ' ttl]); grid on;
        if ~isempty(xl), xlim(xl); end
        legend({'WT','DS'},'Location','southeast'); legend boxoff;
    end
end


% Helper Functions:

function doGroupMI(root, Nbins)
d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
MI_WT = {}; MI_DS = {};
for k=1:numel(d)
    name = d(k).name; mdir = fullfile(root,name);
    p = fullfile(mdir,'new PAC',sprintf('MI data (%d bins).mat',Nbins));
    if exist(p,'file')
        S = load(p);
        if isfield(S,'MI')
            if contains(name,'WT','IgnoreCase',true), MI_WT{end+1}=S.MI;
            elseif contains(name,'DS','IgnoreCase',true), MI_DS{end+1}=S.MI;
            end
        end
    end
end
if isempty(MI_WT) && isempty(MI_DS), return; end
phase_freqs = 3:14; amp_freqs = 30:1:100;

figure;
if ~isempty(MI_WT)
    mean_MI_WT = mean(cat(3, MI_WT{:}),3,'omitnan');
    subplot(1,2,1); contourf(phase_freqs, amp_freqs, mean_MI_WT, 500, 'linecolor','none');
    title('Mean MI for WT'); xlabel('Phase Frequency (Hz)'); ylabel('Amplitude Frequency (Hz)');
    colormap jet; colorbar; caxis([0 0.001]); xlim([4 14]); ylim([30 100]);
end
if ~isempty(MI_DS)
    mean_MI_DS = mean(cat(3, MI_DS{:}),3,'omitnan');
    subplot(1,2,2); contourf(phase_freqs, amp_freqs, mean_MI_DS, 500, 'linecolor','none');
    title('Mean MI for DS'); xlabel('Phase Frequency (Hz)'); ylabel('Amplitude Frequency (Hz)');
    colormap jet; colorbar; caxis([0 0.001]); xlim([4 14]); ylim([30 100]);
end
end

function v = pickVecPreferMerged(S)
% prefer 'merged_vector', else first numeric vector
v = [];
if isfield(S,'merged_vector') && isnumeric(S.merged_vector) && isvector(S.merged_vector)
    v = S.merged_vector(:);
    return;
end
fn = fieldnames(S);
for i=1:numel(fn)
    x = S.(fn{i});
    if isnumeric(x) && isvector(x)
        v = x(:); return;
    end
end
end

function T = padToTableLikeOriginal(S)
fns = fieldnames(S);
maxLen = 0;
for i=1:numel(fns)
    v = S.(fns{i});
    if isrow(v), v = v.'; end
    S.(fns{i}) = v;
    maxLen = max(maxLen, numel(v));
end
for i=1:numel(fns)
    v = S.(fns{i});
    if numel(v) < maxLen
        S.(fns{i}) = [v; NaN(maxLen-numel(v),1)];
    end
end
T = struct2table(S);
end

function plotCDF_likeScript(WT,DS,what,xlimv)
WT = WT(~isnan(WT)); DS = DS(~isnan(DS));
if isempty(WT) && isempty(DS), return; end
[WT_F, WT_X] = ecdf(WT);
[DS_F, DS_X] = ecdf(DS);

figure;
if ~isempty(WT_X), plot(WT_X, WT_F, '-', 'LineWidth',1, 'Color',[0.5 0.5 0.5]); hold on; end
if ~isempty(DS_X), plot(DS_X, DS_F, '-', 'LineWidth',1, 'Color',[0.3 0.6 1.0]); end
hold off;
xlabel(what, 'FontSize',14); ylabel('Cumulative frequency','FontSize',14);
title(['CDF of ' what], 'FontSize',14);
if ~isempty(xlimv), xlim(xlimv); end
set(gca,'FontSize',12,'Box','off'); legend({'WT','DS'},'Location','southeast'); legend boxoff;
end
