function SleepLabAppV3_3
% SleepLabApp — Multi-module GUI to run biomarkers pipelines
% Modules included: PSD Grouping, Theta–Gamma PAC (distribution +  MI), HFD, Beta-Bursts, MDF/SEF/Peak
% Assumes each mouse folder contains EEG/labels as in your previous scripts.

clc;

%% ------------------------------- UI ----------------------------------------
f = uifigure('Name','Sleep Lab App','Position',[120 80 1100 750]);

% Row heights: 1–4 controls, 5 = big Module Settings (now: common grouping + module panels),
% 6 = small spacer, 7 = Run, 8 = Log (flex)
g = uigridlayout(f,[8 4]);
g.RowHeight   = {32,34,34,34, '5x', 6, 40, '1x'};
g.ColumnWidth = {250,220,220,'1x'};


% Row 1: root + open
uilabel(g,'Text','Root folder (mouse subfolders):','HorizontalAlignment','left');
rootEdit = uieditfield(g,'text');
uibutton(g,'Text','Browse Root…','ButtonPushedFcn',@(s,e)browseRoot());
uibutton(g,'Text','Open Root','ButtonPushedFcn',@(s,e)openRoot());

% Row 2: module chooser  (using ItemsData == stable keys)
uilabel(g,'Text','Module to run:','HorizontalAlignment','left');
moduleDrop = uidropdown(g, ...
    'Items',     {'PSD Grouping','Theta-Gamma PAC','HFD','Beta-Bursts','MDF/SEF/Peak','General PAC'}, ...
    'ItemsData', {'psd','pac','hfd','beta','mdfsef','gpac'}, ...
    'Value','psd', ...
    'ValueChangedFcn', @(~,~) switchPanel());


uilabel(g,'Text','Exclude mice (comma-separated):','HorizontalAlignment','left');
excludeEdit = uieditfield(g,'text');

% Row 3: common settings
uilabel(g,'Text','Label codes [Wake REM NREM]:','HorizontalAlignment','left');
labEdit = uieditfield(g,'text','Value','2 1 3','Tooltip','Enter three integers: Wake REM NREM');
uilabel(g,'Text','fs (Hz):','HorizontalAlignment','left');
fsEdit = uieditfield(g,'numeric','Value',2000,'Limits',[1 Inf]);

% Row 4: epoch/band
uilabel(g,'Text','Epoch length (s):','HorizontalAlignment','left');
epochEdit = uieditfield(g,'numeric','Value',5,'Limits',[0.5 Inf]);
uilabel(g,'Text','Base BP for EEG prefilter [low high] (Hz):','HorizontalAlignment','left');
bpEdit = uieditfield(g,'text','Value','0.5 100');

% Row 5: module panels (stacked overlay) with Common Grouping and EEG Loader
pStack = uipanel(g,'Title','Module Settings','Scrollable','on');
pStack.Layout.Column = [1 4];
pStack.Layout.Row    = 5;

% UPDATED: 3 rows (Grouping; EEG Loader; Module Panels)
stackGrid = uigridlayout(pStack,[3 1]); % Row1: Grouping; Row2: EEG Loader; Row3: module panels
stackGrid.RowHeight   = {230, 70, '1x'};          % more room for 4 groups
stackGrid.ColumnWidth = {'1x'};

% -------- Common Grouping Panel (UPDATED: up to 4 groups) --------
pGroup = uipanel(stackGrid,'Title','Common: Grouping (applies to all modules)');
pGroup.Layout.Row = 1; pGroup.Layout.Column = 1;

% Layout: first row has the global “Use regex”, then 4 rows of (Name, Pattern) pairs
gg = uigridlayout(pGroup,[5 6]);
gg.RowHeight   = {30,30,30,30,30};
gg.ColumnWidth = {140,160,140,160,160,'1x'};

% Row 1: global regex toggle (applies to all patterns)
uilabel(gg,'Text','Use regex patterns:','HorizontalAlignment','left');
useRegexChk = uicheckbox(gg,'Value',false,'Text','Enable', ...
    'Tooltip','If On, patterns are interpreted as case-insensitive regular expressions.');
uipanel(gg,'BorderType','none'); uipanel(gg,'BorderType','none'); uipanel(gg,'BorderType','none'); uipanel(gg,'BorderType','none');

% Rows 2–5: up to four groups (Name + Pattern). Empty names/patterns are ignored downstream.
groupNameEdits = gobjects(1,4);
groupPatEdits  = gobjects(1,4);

defaults_names = {'WT','DS','',''};   % convenience defaults; user can clear or change
defaults_pats  = {'WT','DS','',''};

for ii = 1:4
    uilabel(gg,'Text',sprintf('Group %d Name:',ii),'HorizontalAlignment','left');
    groupNameEdits(ii) = uieditfield(gg,'text','Value',defaults_names{ii}, ...
        'Tooltip','Display name for this group (used in legends/exports).');

    uilabel(gg,'Text',sprintf('Group %d Pattern:',ii),'HorizontalAlignment','left');
    groupPatEdits(ii)  = uieditfield(gg,'text','Value',defaults_pats{ii}, ...
        'Tooltip','Substring or regex pattern to match this group''s mouse folders.');
    % filler for last two columns
    uipanel(gg,'BorderType','none'); uipanel(gg,'BorderType','none');
end

% Backward-compatibility aliases for existing code paths (Groups A/B)
groupANameEdit = groupNameEdits(1);
groupBNameEdit = groupNameEdits(2);
groupAPatEdit  = groupPatEdits(1);
groupBPatEdit  = groupPatEdits(2);

% -------- NEW: EEG Loader Panel (optional) --------
pLoader = uipanel(stackGrid,'Title','Common: EEG Loader (optional)');
pLoader.Layout.Row = 2; pLoader.Layout.Column = 1;

gl = uigridlayout(pLoader,[2 6]);
gl.RowHeight   = {30,30};
gl.ColumnWidth = {180, 200, 150, 120, 200, '1x'};

uilabel(gl,'Text','EEG filename pattern:','HorizontalAlignment','left');
eegPatEdit  = uieditfield(gl,'text','Value','','Tooltip', ...
    ['Optional. Examples:' newline ...
    '  Simple (not regex): eeg_clean' newline ...
    '  Regex (enable below): ^EEG\(R\)\.mat$' newline ...
    'Leave empty to use automatic loader']);

uilabel(gl,'Text','Treat as regex?','HorizontalAlignment','left');
eegRegexChk = uicheckbox(gl,'Value',false,'Text','Enable','Tooltip','Treat the pattern as regular expression (case-insensitive).');

uilabel(gl,'Text','Exclude patterns (regex, comma-separated):','HorizontalAlignment','left');
eegExclEdit = uieditfield(gl,'text','Value','^REM_EEG','Tooltip','E.g.: ^REM_EEG,EMG');

% -------- Module cards container --------
cards = uipanel(stackGrid,'BorderType','none');  % holds module specific panels
cards.Layout.Row = 3; cards.Layout.Column = 1;
cardsGrid = uigridlayout(cards,[1 1]);  % single cell where we overlay panels

% -------- PSD --------
pPSD = uipanel(cardsGrid,'Title','PSD Grouping');  pPSD.Visible='on';
pPSD.Layout.Row = 1; pPSD.Layout.Column = 1;
pgPSD = uigridlayout(pPSD,[3 8]);
pgPSD.RowHeight   = {30,30,'1x'};
pgPSD.ColumnWidth = {160,120,160,120,160,160,160,'1x'};

uilabel(pgPSD,'Text','Use peak filter (REM 4.8–9.8 / NREM 0.8–4.8)?');
usePeakDrop = uidropdown(pgPSD,'Items',{'Yes','No'},'Value','Yes','Tooltip','Gate epochs by dominant peak frequency per state.');

uilabel(pgPSD,'Text','Welch window (n):');
winEdit = uieditfield(pgPSD,'numeric','Value',2048,'Limits',[128 Inf]);

uilabel(pgPSD,'Text','Welch overlap (n):');
ovlEdit = uieditfield(pgPSD,'numeric','Value',1024,'Limits',[0 Inf]);

uilabel(pgPSD,'Text','X-lim (Hz):');
xlimEdit = uieditfield(pgPSD,'text','Value','1 100');

uilabel(pgPSD,'Text','Line noise notch (Hz):');
notchEdit = uieditfield(pgPSD,'text','Value','48 52');

psdShowSDChk = uicheckbox(pgPSD,'Text','Show SD band (mean±SD in dB)','Value',true, ...
    'Tooltip','Overlay mean±SD shaded band in dB/Hz; exports remain backward compatible.');

% fillers to align grid
uipanel(pgPSD,'BorderType','none');
uipanel(pgPSD,'BorderType','none');

% -------- PAC --------
pPAC = uipanel(cardsGrid,'Title','Theta-Gamma PAC'); pPAC.Visible='off';
pPAC.Layout.Row = 1; pPAC.Layout.Column = 1;
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
groupPACChk = uicheckbox(pgPAC,'Text','Group plots (A vs B) after compute','Value',true);

% -------- HFD --------
pHFD = uipanel(cardsGrid,'Title','HFD');            pHFD.Visible='off';
pHFD.Layout.Row = 1; pHFD.Layout.Column = 1;
pgHFD = uigridlayout(pHFD,[3 8]); pgHFD.RowHeight={30,30,'1x'}; pgHFD.ColumnWidth={160,80,160,80,160,80,220,'1x'};
uilabel(pgHFD,'Text','Fs (downsample) Hz:');   fsNewEdit = uieditfield(pgHFD,'numeric','Value',256,'Limits',[32 Inf]);
uilabel(pgHFD,'Text','FIR order (0.5–70 Hz):'); firOrderEdit = uieditfield(pgHFD,'numeric','Value',200,'Limits',[10 5000]);
uilabel(pgHFD,'Text','Win (s):');              hfdWinSec = uieditfield(pgHFD,'numeric','Value',4,'Limits',[1 Inf]);
uilabel(pgHFD,'Text','Overlap (s):');          hfdOverlapSec = uieditfield(pgHFD,'numeric','Value',2.5,'Limits',[0 Inf]);
uilabel(pgHFD,'Text','kmax:');                 kmaxEdit = uieditfield(pgHFD,'numeric','Value',30,'Limits',[5 1000]);
groupOnlyChk = uicheckbox(pgHFD,'Text','Aggregate only (skip per-mouse recompute)','Value',false);

% -------- Beta-Bursts --------
pBB = uipanel(cardsGrid,'Title','Beta-Bursts');     pBB.Visible='off';
pBB.Layout.Row = 1; pBB.Layout.Column = 1;
pgBB = uigridlayout(pBB,[3 6]); pgBB.RowHeight={30,30,'1x'}; pgBB.ColumnWidth={160,120,160,120,260,'1x'};
uilabel(pgBB,'Text','Beta band (Hz):');     bbBandEdit = uieditfield(pgBB,'text','Value','13 30');
uilabel(pgBB,'Text','Threshold percentile:'); bbThrPrct = uieditfield(pgBB,'numeric','Value',75,'Limits',[1 99]);
uilabel(pgBB,'Text','CDF X-lims [amp;dur;freq;IBI;IBIshort;IBIlong]:');
bbXlimsEdit = uieditfield(pgBB,'text','Value','[2000 1e5];[0 0.35];[15 25];[0 1];[0 0.05];[0.2 1]');

% -------- MDF/SEF/Peak (RAW EEG) --------
pMDF = uipanel(cardsGrid,'Title','MDF / SEF / Peak (from RAW EEG)');
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

% -------- General PAC (user-selectable bands) --------
pGPAC = uipanel(cardsGrid,'Title','General PAC (user-selectable bands)');
pGPAC.Visible='off';
pGPAC.Layout.Row = 1;
pGPAC.Layout.Column = 1;

pgGPAC = uigridlayout(pGPAC,[4 8]);
pgGPAC.RowHeight   = {30,30,30,'1x'};
pgGPAC.ColumnWidth = {140,140,160,80,160,80,200,'1x'};

% Row 1 (left → right)
uilabel(pgGPAC,'Text','REM source:');
gpacRemSource = uidropdown(pgGPAC,'Items',{'labels (auto)','manual REM_EEG_accusleep.mat'},'Value','labels (auto)');
uilabel(pgGPAC,'Text','Outlier |z| >');
gpacZThr = uieditfield(pgGPAC,'numeric','Value',3,'Limits',[0 Inf]);
uilabel(pgGPAC,'Text','# bins:');
gpacNbins = uieditfield(pgGPAC,'numeric','Value',72,'Limits',[12 720]);
gpacDoMI  = uicheckbox(pgGPAC,'Text','Compute MI map','Value',false);
gpacGroup = uicheckbox(pgGPAC,'Text','Group plots/exports','Value',true);

% Row 2 (state selector)
uilabel(pgGPAC,'Text','State:');
gpacState = uidropdown(pgGPAC, ...
    'Items',     {'Wake','REM','NREM'}, ...
    'ItemsData', {'wake','rem','nrem'}, ...
    'Value','rem', ...
    'Tooltip','Which sleep state to analyze (from labels).');

% Row 3 (phase bands list)
uilabel(pgGPAC,'Text','Phase bands (Hz):');
gpacPhaseList = uieditfield(pgGPAC,'text','Value','2 4; 4 6; 6 8; 8 10', ...
    'Tooltip', 'One range per row or semicolon-separated: "a b; c d; ..."');

% Row 4 (amp bands list)
uilabel(pgGPAC,'Text','Amplitude bands (Hz):');
gpacAmpList = uieditfield(pgGPAC,'text','Value','30 50; 50 70; 70 90', ...
    'Tooltip', 'One range per row or semicolon-separated: "a b; c d; ..."');

% Fillers for remaining cells to keep layout clean
uipanel(pgGPAC,'BorderType','none'); uipanel(pgGPAC,'BorderType','none');
uipanel(pgGPAC,'BorderType','none'); uipanel(pgGPAC,'BorderType','none');

% Disable manual REM picker unless state == REM
gpacState.ValueChangedFcn = @(~,~) setManualREMEnabled();
    function setManualREMEnabled()
        isREM = strcmp(gpacState.Value,'rem');
        gpacRemSource.Enable = ternary(isREM,'on','off');
    end
setManualREMEnabled();


% Row 7: footer (Run + status)
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
        pPSD.Visible = 'off';
        pPAC.Visible = 'off';
        pHFD.Visible = 'off';
        pBB.Visible  = 'off';
        pMDF.Visible = 'off';
        pGPAC.Visible= 'off';

        switch moduleDrop.Value
            case 'psd',    pPSD.Visible   = 'on';
            case 'pac',    pPAC.Visible   = 'on';
            case 'hfd',    pHFD.Visible   = 'on';
            case 'beta',   pBB.Visible    = 'on';
            case 'mdfsef', pMDF.Visible   = 'on';
            case 'gpac',   pGPAC.Visible  = 'on';
        end
    end

    function runModule()
        try
            statusLbl.Text = 'Running...'; drawnow;
            rootDir = strtrim(rootEdit.Value);
            if ~exist(rootDir,'dir')
                uialert(f,'Please select a valid root folder.','No folder'); statusLbl.Text='Ready.'; return;
            end

            % ---------------- global/common inputs ----------------
            excl = parseList(excludeEdit.Value);
            [WakeCode, REMCode, NREMCode] = parseLabelCodes(labEdit.Value);
            fs = fsEdit.Value;
            epochSec = epochEdit.Value;
            baseBP = parseBand(bpEdit.Value);
            logmsg('Root: %s', rootDir);

            % ---------------- grouping (multi-group) ----------------
            % Collect group names & patterns from the new Grouping panel
            rawNames = string( arrayfun(@(h) strtrim(h.Value), groupNameEdits, 'UniformOutput', false) );
            rawPats  = string( arrayfun(@(h) strtrim(h.Value), groupPatEdits,   'UniformOutput', false) );
            useRegex = logical(useRegexChk.Value);

            % Remove empty entries (skip rows where pattern is empty)
            [groups.names, groups.pats] = trimGroups(rawNames, rawPats);

            keep  = rawPats ~= "";              % drop rows with empty *pattern*
            names = rawNames(keep);
            pats  = rawPats(keep);

            % Optional: normalize/trim again & drop rows where both are empty
            [names, pats] = trimGroups(names, pats);


            % default names if user wrote only patterns
            for i = 1:numel(names)
                if names(i) == ""
                    names(i) = "Group " + string(i);
                end
            end

            % At least 1 group?
            if isempty(pats)
                % Fallback to a single catch-all group
                names = "All"; pats = ".*";
            end

            % Build groups struct (new API)
            groups = struct('names',names(:).', 'patterns',pats(:).', 'useRegex',logical(useRegex));

            % Legacy A/B (compatibility with old internals)
            if numel(names) >= 1
                grpA_name = names(1); grpA_pat = pats(1);
            else
                grpA_name = "A"; grpA_pat = "";
            end
            if numel(names) >= 2
                grpB_name = names(2); grpB_pat = pats(2);
            else
                grpB_name = "B"; grpB_pat = "";
            end

            % ---------------- EEG Loader panel (optional pattern) ----------------
            userEEGpat   = strtrim(eegPatEdit.Value);   % '' => auto loader
            userEEGisReg = eegRegexChk.Value;
            tmpExcl      = strtrim(eegExclEdit.Value);
            if isempty(tmpExcl)
                ignorePats = {};
            else
                ignorePats = strtrim(split(tmpExcl,','));
                ignorePats = ignorePats(~cellfun(@isempty,ignorePats));
            end

            % ---------------- dispatch by module ----------------
            switch moduleDrop.Value
                case 'psd'
                    usePeak = strcmp(usePeakDrop.Value,'Yes');
                    w = winEdit.Value; ov = ovlEdit.Value;
                    xlimHz = parseBand(xlimEdit.Value);
                    notch  = parseBand(notchEdit.Value);
                    showSD = psdShowSDChk.Value;

                    try
                        % New signature with groups struct at the end
                        runPSD_Internal( ...
                            rootDir, fs, epochSec, baseBP, [WakeCode REMCode NREMCode], ...
                            usePeak, w, ov, xlimHz, notch, excl, ...
                            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, showSD, ...
                            userEEGpat, userEEGisReg, ignorePats, groups);
                    catch ME
                        if contains(ME.message,'Too many input arguments')
                            % Fall back to legacy 2-group signature
                            runPSD_Internal( ...
                                rootDir, fs, epochSec, baseBP, [WakeCode REMCode NREMCode], ...
                                usePeak, w, ov, xlimHz, notch, excl, ...
                                grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, showSD, ...
                                userEEGpat, userEEGisReg, ignorePats);
                        else
                            rethrow(ME);
                        end
                    end

                case 'pac'
                    useManualREM = strcmp(remSource.Value,'manual REM_EEG_accusleep.mat');
                    zthr = zThrEdit.Value;
                    th = parseBand(thetaEdit.Value);
                    ga = parseBand(gammaEdit.Value);
                    nb = nbinsEdit.Value;
                    doMI = miChk.Value;
                    doGroup = groupPACChk.Value;

                    try
                        runPAC_Internal( ...
                            rootDir, fs, epochSec, [WakeCode REMCode NREMCode], ...
                            useManualREM, zthr, th, ga, nb, excl, doMI, doGroup, ...
                            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                            userEEGpat, userEEGisReg, ignorePats, groups);
                    catch ME
                        if contains(ME.message,'Too many input arguments')
                            runPAC_Internal( ...
                                rootDir, fs, epochSec, [WakeCode REMCode NREMCode], ...
                                useManualREM, zthr, th, ga, nb, excl, doMI, doGroup, ...
                                grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                                userEEGpat, userEEGisReg, ignorePats);
                        else
                            rethrow(ME);
                        end
                    end

                case 'hfd'
                    fsNew = fsNewEdit.Value;
                    firOrd = firOrderEdit.Value;
                    winS = hfdWinSec.Value;
                    ovS  = hfdOverlapSec.Value;
                    kmax = kmaxEdit.Value;
                    groupOnly = groupOnlyChk.Value;

                    try
                        runHFD_Internal( ...
                            rootDir, fs, epochSec, baseBP, fsNew, firOrd, winS, ovS, kmax, ...
                            [WakeCode REMCode NREMCode], excl, groupOnly, ...
                            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                            userEEGpat, userEEGisReg, ignorePats, groups);
                    catch ME
                        if contains(ME.message,'Too many input arguments')
                            runHFD_Internal( ...
                                rootDir, fs, epochSec, baseBP, fsNew, firOrd, winS, ovS, kmax, ...
                                [WakeCode REMCode NREMCode], excl, groupOnly, ...
                                grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                                userEEGpat, userEEGisReg, ignorePats);
                        else
                            rethrow(ME);
                        end
                    end

                case 'beta'
                    bb = parseBand(bbBandEdit.Value);
                    thrP = bbThrPrct.Value;
                    xlims = parseXlimList(bbXlimsEdit.Value);

                    try
                        runBeta_Internal( ...
                            rootDir, fs, epochSec, [WakeCode REMCode NREMCode], ...
                            bb, thrP, excl, xlims, ...
                            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                            userEEGpat, userEEGisReg, ignorePats, groups);
                    catch ME
                        if contains(ME.message,'Too many input arguments')
                            runBeta_Internal( ...
                                rootDir, fs, epochSec, [WakeCode REMCode NREMCode], ...
                                bb, thrP, excl, xlims, ...
                                grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                                userEEGpat, userEEGisReg, ignorePats);
                        else
                            rethrow(ME);
                        end
                    end

                case 'mdfsef'
                    fs_local = fsEdit.Value; %#ok<NASGU>
                    epoch_sec = epochEdit.Value;
                    bp = str2num(bpEdit.Value); %#ok<ST2NM>
                    if numel(bp)~=2 || any(~isfinite(bp)) || bp(1)<=0 || bp(2)<=bp(1)
                        logmsg('Invalid base band-pass.'); statusLbl.Text='Ready.'; return;
                    end
                    codes = str2num(labEdit.Value); %#ok<ST2NM>
                    if numel(codes)~=3
                        logmsg('Label codes must be [Wake REM NREM].'); statusLbl.Text='Ready.'; return;
                    end
                    excluded = strtrim(split(excludeEdit.Value,',')); excluded = excluded(~cellfun(@isempty,excluded));
                    winN = mdfWinEdit.Value;
                    ovN  = mdfOvlEdit.Value;
                    sefPerc = mdfSEFEdit.Value;
                    doGate  = mdfGateChk.Value;
                    mode    = mdfModeDrop.Value;       % 'per' | 'group' | 'both'
                    autoCompute = mdfAutoChk.Value;

                    try
                        runMDFSEF_Internal( ...
                            rootDir, fs, epoch_sec, codes, bp, winN, ovN, sefPerc, doGate, mode, excluded, autoCompute, ...
                            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                            userEEGpat, userEEGisReg, ignorePats, groups);
                    catch ME
                        if contains(ME.message,'Too many input arguments')
                            runMDFSEF_Internal( ...
                                rootDir, fs, epoch_sec, codes, bp, winN, ovN, sefPerc, doGate, mode, excluded, autoCompute, ...
                                grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                                userEEGpat, userEEGisReg, ignorePats);
                        else
                            rethrow(ME);
                        end
                    end
                case 'gpac'
                    useManualREM = strcmp(gpacRemSource.Value,'manual REM_EEG_accusleep.mat');
                    zthr   = gpacZThr.Value;
                    nb     = gpacNbins.Value;
                    doMI   = gpacDoMI.Value;
                    doGroup= gpacGroup.Value;

                    % Parse band lists
                    phaseBands = parseBandList(gpacPhaseList.Value);
                    ampBands   = parseBandList(gpacAmpList.Value);
                    if isempty(phaseBands) || isempty(ampBands)
                        logmsg('General PAC: invalid band lists.'); statusLbl.Text='Ready.'; return;
                    end

                    stateSel = gpacState.Value;   % 'wake' | 'rem' | 'nrem'

                    try
                        runGenPAC_Internal( ...
                            rootDir, fs, epochSec, [WakeCode REMCode NREMCode], ...
                            useManualREM, zthr, phaseBands, ampBands, nb, excl, doMI, doGroup, stateSel, ...
                            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                            userEEGpat, userEEGisReg, ignorePats, groups);
                    catch ME
                        if contains(ME.message,'Too many input arguments')
                            runGenPAC_Internal( ...
                                rootDir, fs, epochSec, [WakeCode REMCode NREMCode], ...
                                useManualREM, zthr, phaseBands, ampBands, nb, excl, doMI, doGroup, stateSel, ...
                                grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
                                userEEGpat, userEEGisReg, ignorePats);
                        else
                            rethrow(ME);
                        end
                    end


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
            winN, ovN, xlimHz, notchHz, excluded, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, showSD, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)

        % ---------------- Compatibility shim → groups ----------------
        groups = normalize_groups_args(varargin, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex);

        logmsg('PSD: fs=%g, epoch=%gs, BP=[%g %g], window=%d, overlap=%d, usePeak=%d', ...
            fs, epoch_sec, baseBP(1), baseBP(2), winN, ovN, usePeak);

        % ---------------- Preliminaries ----------------
        epoch_len = max(1, round(fs*epoch_sec));
        [b_eeg, a_eeg] = butter(4, baseBP/(fs/2), 'bandpass');
        lowcut   = 0.1;
        rem_gate = [4.8 9.8];
        nrem_gate= [0.8 4.8];

        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
        [gNames, gPats] = trimGroups(groups.names, groups.patterns);
        nG = numel(gNames);

        % Per-group buckets: Groups{gi}.Wake/NREM/REM -> {mouse}
        Buckets = cell(1,nG);
        for gi = 1:nG
            Buckets{gi} = struct('Wake',{{}}, 'NREM',{{}}, 'REM',{{}});
        end

        % ---------------- Walk mice ----------------
        for k = 1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('PSD: skip excluded: %s', name); continue; end

            gi = classifyGroupIdx(name, gPats, groups.useRegex);
            if gi==0, logmsg('PSD: unassigned (ambiguous/none): %s', name); continue; end

            mdir = fullfile(root, name);

            % EEG discovery (pattern-aware)
            [fileList, meta] = findEEGMatFiles(mdir, struct( ...
                'userPattern',   userEEGpat, ...
                'userIsRegex',   userEEGisReg, ...
                'ignorePatterns',{ignorePats}, ...
                'wantSides',     "any", ...
                'allowNonEEG',   false));
            if isempty(fileList)
                logmsg('PSD: No EEG .mat in %s (pattern="%s").', name, userEEGpat);
                continue;
            end
            eegChosen = fileList.name{1};
            EEG = extractBestEEGVector(fullfile(mdir, eegChosen));
            if isempty(EEG) || numel(EEG) < fs
                logmsg('PSD: invalid EEG in %s; skip.', eegChosen); continue;
            end
            if isfield(meta,'fellBack') && meta.fellBack
                logmsg('PSD: EEG source: %s (auto)', eegChosen);
            else
                logmsg('PSD: EEG source: %s (user pattern)', eegChosen);
            end

            % labels
            labPath = fullfile(mdir,'labels.mat');
            if ~exist(labPath,'file'), logmsg('PSD: missing labels in %s', name); continue; end
            L = load(labPath);
            if ~isfield(L,'labels'), logmsg('PSD: labels var missing in %s', labPath); continue; end
            labels = L.labels(:).';

            % Prefilter & epoch
            try
                EEG = filtfilt(b_eeg, a_eeg, double(EEG));
            catch
                logmsg('PSD: filter fail %s', name); continue;
            end

            num_epochs = floor(numel(EEG)/epoch_len);
            if num_epochs<1, logmsg('PSD: too short %s', name); continue; end
            EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
            labels = labels(1:min(num_epochs,numel(labels)));
            EEG = EEG(:,1:numel(labels));

            % Accumulators per state (linear PSD)
            acc = struct('Wake',{{}}, 'REM',{{}}, 'NREM',{{}});
            Fmask = [];

            for e = 1:size(EEG,2)
                [Pxx,F] = pwelch(EEG(:,e), winN, ovN, [], fs);
                m = (F>=lowcut) & (F<notchHz(1) | F>notchHz(2));
                Fv = F(m); P = Pxx(m);

                if isempty(Fmask)
                    Fmask = Fv;
                else
                    if numel(Fv)~=numel(Fmask) || any(abs(Fv-Fmask)>1e-12)
                        logmsg('PSD: freq grid mismatch %s epoch=%d -> skipped', name, e);
                        continue;
                    end
                end

                st = labels(e);
                keep = true;
                if usePeak
                    [~,pk] = max(P); pkf = Fv(pk);
                    if st==codes(2)      % REM
                        keep = pkf>=rem_gate(1)  && pkf<=rem_gate(2);
                    elseif st==codes(3)  % NREM
                        keep = pkf>=nrem_gate(1) && pkf<=nrem_gate(2);
                    end
                end
                if ~keep, continue; end

                if     st==codes(1), acc.Wake{end+1} = P; %#ok<AGROW>
                elseif st==codes(2), acc.REM{end+1}  = P; %#ok<AGROW>
                elseif st==codes(3), acc.NREM{end+1} = P; %#ok<AGROW>
                end
            end

            M = struct();
            if ~isempty(acc.Wake), M.Wake = packMousePSD(Fmask, acc.Wake); end
            if ~isempty(acc.NREM), M.NREM = packMousePSD(Fmask, acc.NREM); end
            if ~isempty(acc.REM),  M.REM  = packMousePSD(Fmask, acc.REM);  end
            if isempty(fieldnames(M)), logmsg('PSD: no accepted epochs in %s', name); continue; end

            if isfield(M,'Wake'), Buckets{gi}.Wake{end+1} = M.Wake; end
            if isfield(M,'NREM'), Buckets{gi}.NREM{end+1} = M.NREM; end
            if isfield(M,'REM'),  Buckets{gi}.REM{end+1}  = M.REM;  end
        end

        % ---------------- Exports & plots (multi-group only) ----------------
        States = {'Wake','NREM','REM'};
        Colors = lines(max(7,nG));
        peakTxt = ternary(usePeak,'with','no');

        allRows = {};
        for si = 1:numel(States)
            st = States{si};
            f = figure('Visible','off'); hold on; set(gca,'XScale','log'); grid on; xlim(xlimHz);
            title(sprintf('PSD Mean — %s (%s peak filter)', st, peakTxt));
            xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');

            for gi = 1:nG
                C = Buckets{gi}.(st);
                [Fout, mu, sdv] = groupMeanSD_multi(C);
                if isempty(mu), continue; end

                if showSD
                    fill_between(Fout, mu-sdv, mu+sdv, Colors(gi,:), 0.20);
                end
                plot(Fout, mu, '-', 'LineWidth',1.8, 'Color', Colors(gi,:));

                % tidy rows
                allRows{end+1} = table( ...
                    repmat(string(gNames(gi)),numel(Fout),1), ...
                    repmat(string(st),numel(Fout),1), ...
                    Fout(:), mu(:), sdv(:), ...
                    'VariableNames', {'Group','State','Frequency_Hz','Mean_dB','SD_dB'}); %#ok<AGROW>
            end
            legend(cellstr(gNames),'Interpreter','none','Location','best'); hold off;

            outP = fullfile(root, sprintf('psd_group_mean_%s.png', lower(st)));
            safe_exportgraphics(f, outP);
            close(f);
        end

        if ~isempty(allRows)
            T = vertcat(allRows{:});
            writetable(T, fullfile(root,'group_psd_summary_multi.csv'));
        end

        % ---------------- Local helpers ----------------
        function S = packMousePSD(Fmask, Pcell)
            P = mean(cat(2, Pcell{:}), 2, 'omitnan'); % linear mean per mouse
            S = struct('F',Fmask(:), 'Pxx_lin',P(:));
        end

    end


%% ---------------------- INTERNAL: Theta-Gamma PAC --------------------------
    function runPAC_Internal(root, fs, epoch_sec, codes, useManual, zthr, ...
            thetaHz, gammaHz, Nbins, excluded, doMI, doGroup, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)

        % ---------------- Compatibility shim → groups ----------------
        groups = normalize_groups_args(varargin, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex);
        [gNames, gPats] = trimGroups(groups.names, groups.patterns);
        nG = numel(gNames);

        logmsg('PAC: fs=%g, epoch=%gs, theta=[%g %g], gamma=[%g %g], bins=%d, MI=%d', ...
            fs, epoch_sec, thetaHz(1), thetaHz(2), gammaHz(1), gammaHz(2), Nbins, doMI);

        resultsDir = fullfile(root, 'PAC_Results');
        if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

        epoch_len = max(1, round(fs*epoch_sec));
        G_dist  = cell(1,nG);  % per-group, per-mouse distributions
        G_MI    = cell(1,nG);  % per-group, per-mouse MI matrices

        % MI grid (fixed theta/gamma sweep for MI map, independent of thetaHz/gammaHz used for dist)
        if doMI
            fp1 = 2:13; fp2 = 4:15;            % 2-Hz theta slices (centered at fp1+1)
            fa1 = 28:1:98; fa2 = 30:1:100;     % 2-Hz gamma slices (centered at fa1+1)
            phaseCentersHz = fp1 + 1;
            ampCentersHz   = fa1 + 1;
        end

        % ---------------- Walk mice ----------------
        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
        for k = 1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('PAC: skip excluded: %s', name); continue; end

            gi = classifyGroupIdx(name, gPats, groups.useRegex);
            if gi==0, logmsg('PAC: unassigned (ambiguous/none): %s', name); continue; end

            mdir = fullfile(root,name);
            outdir = fullfile(mdir, 'new PAC');
            if ~exist(outdir,'dir'), mkdir(outdir); end

            % REM vector
            if useManual
                remPath = fullfile(mdir,'REM_EEG_accusleep.mat');
                if ~exist(remPath,'file'), logmsg('PAC: no manual REM in %s', name); continue; end
                S = load(remPath);
                if ~isfield(S,'REM_EEG'), logmsg('PAC: REM_EEG missing in %s', remPath); continue; end
                REM_vec = S.REM_EEG(:);
            else
                [fileList, ~] = findEEGMatFiles(mdir, struct( ...
                    'userPattern', userEEGpat, 'userIsRegex', userEEGisReg, ...
                    'ignorePatterns',{ignorePats}, 'wantSides',"any", 'allowNonEEG',false));
                if isempty(fileList)
                    logmsg('PAC: No EEG .mat in %s (pattern="%s").', name, userEEGpat);
                    continue;
                end
                eegChosen = fileList.name{1};
                EEG = extractBestEEGVector(fullfile(mdir, eegChosen));
                if isempty(EEG) || numel(EEG) < fs
                    logmsg('PAC: invalid EEG in %s; skip.', eegChosen);
                    continue;
                end
                labPath = fullfile(mdir,'labels.mat');
                if ~exist(labPath,'file'), logmsg('PAC: missing labels in %s', name); continue; end
                L = load(labPath);
                if ~isfield(L,'labels'), logmsg('PAC: labels var missing in %s', labPath); continue; end
                labels = L.labels(:).';

                num_epochs = floor(numel(EEG)/epoch_len);
                if num_epochs<1, logmsg('PAC: too short %s', name); continue; end
                EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
                labels = labels(1:min(num_epochs,numel(labels)));
                EEG = EEG(:,1:numel(labels));

                REM_vec = cell2mat(arrayfun(@(e) EEG(:,e), find(labels==codes(2)), 'UniformOutput', false));
            end
            if isempty(REM_vec), logmsg('PAC: no REM samples in %s', name); continue; end

            % Clean outliers
            z = zscore(double(REM_vec));
            REM_vec(abs(z)>zthr) = NaN;
            REM_vec = fillmissing(REM_vec,'linear');

            % -------- Distribution (thetaHz × gammaHz) --------
            thSig = bandpass(REM_vec, thetaHz, fs);
            gaSig = bandpass(REM_vec, gammaHz, fs);

            thPhase = angle(hilbert(thSig));
            thDeg360 = mod(rad2deg(thPhase), 360);
            thDeg720 = [thDeg360; thDeg360+360];
            gaAmp = abs(hilbert(gaSig));
            gaAmp2cy = [gaAmp; gaAmp];

            edges   = linspace(0, 720, Nbins+1);
            centers = (edges(1:end-1) + edges(2:end))/2;

            gamma_avg = zeros(Nbins,1);
            for b = 1:Nbins
                inb = (thDeg720 >= edges(b)) & (thDeg720 < edges(b+1));
                gamma_avg(b) = mean(gaAmp2cy(inb), 'omitnan');
            end

            gamma_smoothed = smooth(gamma_avg, 3);
            gamma_smoothed = gamma_smoothed / sum(gamma_smoothed + eps);

            % Per-mouse tidy CSV (distribution)
            try
                Tmouse = table(centers(:), gamma_smoothed(:), ...
                    'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
                writetable(Tmouse, fullfile(outdir, sprintf('PAC_Dist_%dbins.csv', Nbins)));
            catch ME
                logmsg('PAC per-mouse CSV failed (%s): %s', name, ME.message);
            end

            % Keep for group aggregation
            G_dist{gi}{end+1} = gamma_smoothed(:); %#ok<AGROW>

            % -------- MI (phase×amp grid) --------
            MI = [];
            if doMI
                Q = 1/Nbins; MI = zeros(numel(fa1), numel(fp1));
                for i = 1:numel(fp1)
                    ph = angle(hilbert(bandpass(REM_vec,[fp1(i) fp2(i)],fs)));
                    [bins,~] = discretize(ph, Nbins);
                    for j = 1:numel(fa1)
                        a = abs(hilbert(bandpass(REM_vec,[fa1(j) fa2(j)],fs)));
                        D = zeros(1,Nbins);
                        for ii = 1:Nbins
                            m = (bins==ii);
                            D(ii) = mean(a(m));
                        end
                        if all(D==0), continue; end
                        D = D./sum(D + eps);
                        MI(j,i) = sum(D .* log((D+eps)/Q)) / log(Nbins);
                    end
                end

                % Per-mouse MI exports
                try
                    MItab = array2table(MI, 'VariableNames', ...
                        matlab.lang.makeValidName("theta_"+string(phaseCentersHz)+"Hz"));
                    MItab = addvars(MItab, ampCentersHz(:), 'Before', 1, 'NewVariableNames','gammaAmp_Hz');
                    writetable(MItab, fullfile(outdir, sprintf('MI_%dbins.csv', Nbins)));
                catch ME
                    logmsg('PAC per-mouse MI CSV failed (%s): %s', name, ME.message);
                end

                try
                    f = figure('Visible','off');
                    contourf(phaseCentersHz, ampCentersHz, MI, 120, 'linecolor','none');
                    title(sprintf('Theta–Gamma MI — REM — %s', name), 'Interpreter','none');
                    xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)'); colorbar;
                    outP = fullfile(outdir, sprintf('MI_REM_%dbins.png', Nbins));
                    safe_exportgraphics(f, outP);
                    close(f);
                catch ME
                    logmsg('PAC per-mouse MI heatmap export failed (%s): %s', name, ME.message);
                end

                G_MI{gi}{end+1} = MI; %#ok<AGROW>
            end
        end

        % ---------------- Group aggregation & exports ----------------
        edges   = linspace(0, 720, Nbins+1);
        centers = (edges(1:end-1) + edges(2:end))/2;

        % Group distributions (overlay)
        f = figure('Visible','off'); hold on; grid on; xlim([0 720]); xticks(0:90:720);
        xlabel('\theta phase (°)'); ylabel('Normalized \gamma amplitude');
        title('Theta–Gamma PAC distribution (group means)');
        Colors = lines(max(7,nG));

        rowsDist = {};
        for gi = 1:nG
            mu = meanSafeLocal(G_dist{gi});
            if isempty(mu), continue; end
            plot(centers, mu, 'LineWidth',1.8, 'Color', Colors(gi,:));
            % tidy per-mouse rows
            giCells = G_dist{gi};
            for mi = 1:numel(giCells)
                v = giCells{mi};
                if isempty(v), continue; end
                rowsDist{end+1} = table( ...
                    repmat(string(gNames(gi)), numel(centers),1), ...
                    repmat(mi, numel(centers),1), ...
                    centers(:), v(:), ...
                    'VariableNames', {'Group','MouseIdx','ThetaPhase_deg','GammaNormAmp'}); %#ok<AGROW>
            end
        end
        legend(cellstr(gNames),'Interpreter','none','Location','best'); hold off;
        safe_exportgraphics(f, fullfile(resultsDir, 'tgpac_group_distribution_REM.png')); close(f);

        if ~isempty(rowsDist)
            writetable(vertcat(rowsDist{:}), fullfile(resultsDir,'pac_per_mouse_multi.csv'));
        end

        % Group MI heatmaps
        if doMI && doGroup
            for gi = 1:nG
                if isempty(G_MI{gi}), continue; end
                MImean = mean(cat(3, G_MI{gi}{:}), 3, 'omitnan');
                f = figure('Visible','off');
                contourf(phaseCentersHz, ampCentersHz, MImean, 120, 'linecolor','none');
                title(sprintf('Group MI — %s (REM)', gNames(gi)), 'Interpreter','none');
                xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)'); colorbar;
                safe_exportgraphics(f, fullfile(resultsDir, sprintf('tgpac_group_mi_%s.png', lower(string(gNames(gi))))));
                close(f);
            end
        end

    end



%% --------------------------- INTERNAL: HFD ---------------------------------
    function runHFD_Internal(root, fs, epoch_sec, baseBP, fsNew, firOrd, winSec, ovlSec, kmax, ...
            codes, excluded, groupOnly, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)

        % ---------------- Compatibility shim → groups ----------------
        groups = normalize_groups_args(varargin, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex);
        [gNames, gPats] = trimGroups(groups.names, groups.patterns);
        nG = numel(gNames);

        logmsg('HFD: fs=%g→%g, epoch=%gs, FIR=%d (0.5–70Hz), win=%.2fs, ovl=%.2fs, kmax=%d, groupOnly=%d', ...
            fs, fsNew, epoch_sec, firOrd, winSec, ovlSec, kmax, groupOnly);

        resultsDir = fullfile(root, 'HFD_Results');
        if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

        epoch_len = max(1, round(fs*epoch_sec));
        [b_eeg, a_eeg] = butter(4, baseBP/(fs/2), 'bandpass');

        % Per-group → per-mouse → per-state buckets of HFD windows
        States = {'Wake','REM','NREM'};
        code2state = containers.Map( ...
            {codes(1), codes(2), codes(3)}, ...
            {'Wake','REM','NREM'} ...
            );

        G = cell(1,nG);
        for gi=1:nG
            G{gi} = {}; % G{gi}{mi}.Wake / .REM / .NREM -> vector of HFD windows
        end

        % ---------------- Walk mice ----------------
        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
        for k = 1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('HFD: skip excluded: %s', name); continue; end

            gi = classifyGroupIdx(name, gPats, groups.useRegex);
            if gi==0, logmsg('HFD: unassigned (ambiguous/none): %s', name); continue; end
            if groupOnly, continue; end

            mdir = fullfile(root, name);

            % --- Load EEG (pattern-aware) ---
            [fileList, ~] = findEEGMatFiles(mdir, struct( ...
                'userPattern',   userEEGpat, ...
                'userIsRegex',   userEEGisReg, ...
                'ignorePatterns',{ignorePats}, ...
                'wantSides',     "any", ...
                'allowNonEEG',   false));
            if isempty(fileList)
                logmsg('HFD: no EEG in %s', name);
                continue;
            end
            EEG = extractBestEEGVector(fullfile(mdir, fileList.name{1}));
            if isempty(EEG) || numel(EEG) < fs
                logmsg('HFD: invalid EEG in %s', name);
                continue;
            end

            % --- Load labels ---
            labPath = fullfile(mdir,'labels.mat');
            if ~exist(labPath,'file'), logmsg('HFD: missing labels in %s', name); continue; end
            L = load(labPath);
            if ~isfield(L,'labels'), logmsg('HFD: labels var missing in %s', labPath); continue; end
            labels = L.labels(:).';

            % --- Pre-filter EEG at original fs ---
            try
                EEG = filtfilt(b_eeg, a_eeg, double(EEG));
            catch
                logmsg('HFD: base filter fail %s', name);
                continue;
            end

            % --- Epoch to align with labels ---
            num_epochs = floor(numel(EEG)/epoch_len);
            if num_epochs<1, logmsg('HFD: too short %s', name); continue; end
            EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
            labels = labels(1:min(num_epochs,numel(labels)));
            EEG = EEG(:,1:numel(labels));

            % --- Prepare bandpass at fsNew ---
            dFir = designfilt('bandpassfir','FilterOrder',firOrd, ...
                'CutoffFrequency1',0.5, 'CutoffFrequency2',70, 'SampleRate',fsNew);

            % --- Window params at fsNew ---
            Nw  = max(1, round(winSec*fsNew));
            Nov = max(0, round(ovlSec*fsNew));
            hop = max(1, (Nw - Nov));

            % --- Collect per-state windows for this mouse ---
            Mouse.Wake = []; Mouse.REM = []; Mouse.NREM = [];

            for e = 1:size(EEG,2)
                st = [];
                if isKey(code2state, labels(e)), st = code2state(labels(e)); end
                if isempty(st), continue; end   % skip "Other"/Undefined epochs

                seg = EEG(:,e);                           % epoch @ fs
                seg = resample(seg, fsNew, fs);          % → fsNew
                seg = filtfilt(dFir, seg);               % 0.5–70 Hz @ fsNew

                % Sliding windows inside the epoch @ fsNew
                lastStart = max(1, numel(seg) - Nw + 1);
                starts = 1:hop:lastStart;

                vals = [];
                for wi = 1:numel(starts)
                    s = starts(wi);
                    ed = min(s + Nw - 1, numel(seg));
                    w  = seg(s:ed);
                    if numel(w) < round(0.5*Nw), continue; end
                    vals(end+1) = higuchi_fd(w, kmax); %#ok<AGROW>
                end

                if ~isempty(vals)
                    Mouse.(st) = [Mouse.(st) ; vals(:)];
                end
            end

            % Per-mouse CSV (long, with State)
            try
                rows = {};
                for s = 1:numel(States)
                    st = States{s};
                    v  = Mouse.(st);
                    if isempty(v), continue; end
                    rows{end+1} = table( ...
                        repmat(string(st), numel(v),1), ...
                        (1:numel(v)).', v(:), ...
                        'VariableNames', {'State','WindowIdx','HFD'}); %#ok<AGROW>
                end
                if ~isempty(rows)
                    Tm = vertcat(rows{:});
                    writetable(Tm, fullfile(mdir, 'HFD_per_mouse.csv'));
                end
            catch ME
                logmsg('HFD per-mouse CSV failed (%s): %s', name, ME.message);
            end

            % Stash per-mouse, per-state vectors
            G{gi}{end+1} = Mouse;
        end

        % ---------------- Group-level exports ----------------
        % 1) Long/tidy per-window table across all mice/groups/states
        rowsAll = {};
        for gi = 1:nG
            for mi = 1:numel(G{gi})
                for s = 1:numel(States)
                    st = States{s};
                    v  = G{gi}{mi}.(st);
                    if isempty(v), continue; end
                    rowsAll{end+1} = table( ...
                        repmat(string(gNames(gi)), numel(v),1), ...
                        repmat(mi, numel(v),1), ...
                        repmat(string(st), numel(v),1), ...
                        (1:numel(v)).', v(:), ...
                        'VariableNames', {'Group','MouseIdx','State','WindowIdx','HFD'}); %#ok<AGROW>
                end
            end
        end
        if ~isempty(rowsAll)
            writetable(vertcat(rowsAll{:}), fullfile(resultsDir, 'HFD_per_mouse_multi.csv'));
        end

        % 2) Mouse-level means per state (for boxplots)
        rowsMeans = {};
        for gi = 1:nG
            for mi = 1:numel(G{gi})
                for s = 1:numel(States)
                    st = States{s};
                    v  = G{gi}{mi}.(st);
                    if isempty(v), continue; end
                    rowsMeans{end+1} = table( ...
                        string(gNames(gi)), mi, string(st), mean(v,'omitnan'), ...
                        'VariableNames', {'Group','MouseIdx','State','Mean_HFD'}); %#ok<AGROW>
                end
            end
        end
        Tmeans = table();
        if ~isempty(rowsMeans)
            Tmeans = vertcat(rowsMeans{:});
            writetable(Tmeans, fullfile(resultsDir, 'HFD_per_mouse_means.csv'));
        end

        % ---------------- Boxplots ----------------
        % A) For each STATE: compare GROUPS (one figure per state)
        for s = 1:numel(States)
            st = States{s};
            if isempty(Tmeans), continue; end
            mask = strcmp(Tmeans.State, st);
            if ~any(mask), continue; end
            T = Tmeans(mask, :);

            f = figure('Visible','off');
            boxplot(T.Mean_HFD, T.Group, 'Symbol','', 'Whisker',1.5);
            title(sprintf('HFD — %s — groups', st));
            ylabel('Mean HFD per mouse');
            grid on;
            set(gca,'XTickLabelRotation',20);
            safe_exportgraphics(f, fullfile(resultsDir, sprintf('HFD_box_state_%s_by_group.png', lower(st))));
            close(f);
        end

        % B) For each GROUP: compare STATES (one figure per group)
        for gi = 1:nG
            if isempty(Tmeans), continue; end
            mask = strcmp(Tmeans.Group, string(gNames(gi)));
            if ~any(mask), continue; end
            T = Tmeans(mask, :);

            f = figure('Visible','off');
            % ensure consistent state order
            [~,ord] = ismember(T.State, States); [~,ii] = sort(ord); T = T(ii,:);
            boxplot(T.Mean_HFD, T.State, 'Symbol','', 'Whisker',1.5);
            title(sprintf('HFD — %s — states', gNames(gi)));
            ylabel('Mean HFD per mouse');
            grid on;
            set(gca,'XTickLabelRotation',0);
            safe_exportgraphics(f, fullfile(resultsDir, sprintf('HFD_box_group_%s_by_state.png', lower(string(gNames(gi))))));
            close(f);
        end

        % ---------------- Local: Higuchi FD ----------------
        function H = higuchi_fd(x, kmax)
            x = x(:).';
            Lk = zeros(1,kmax);
            for k = 1:kmax
                Lmk = zeros(1,k);
                for m = 1:k
                    sidx = m:k:numel(x);
                    if numel(sidx) < 2
                        Lmk(m) = NaN;
                        continue;
                    end
                    Lmk(m) = (sum(abs(diff(x(sidx)))) * (numel(x)-1) / (floor((numel(x)-m)/k)*k)) / k;
                end
                Lk(k) = mean(Lmk, 'omitnan');
            end
            t = (1:kmax).';
            p = polyfit(log(t), log(Lk(:)), 1);
            H = -p(1);
        end

    end



%% ------------------------ INTERNAL: Beta-Bursts ----------------------------
    function runBeta_Internal(root, fs, epoch_sec, codes, betaBand, thrPrct, excluded, xlims, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)

        % ---------------- Compatibility shim → groups ----------------
        groups = normalize_groups_args(varargin, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex);
        [gNames, gPats] = trimGroups(groups.names, groups.patterns);
        nG = numel(gNames);

        logmsg('Beta: fs=%g, epoch=%gs, band=[%g %g], thr=%g%%', fs, epoch_sec, betaBand(1), betaBand(2), thrPrct);

        resultsDir = fullfile(root, 'Beta_Results');
        if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

        epoch_len = max(1, round(fs*epoch_sec));
        [b_eeg, a_eeg] = butter(4, [max(0.5,betaBand(1)-5) min(100,betaBand(2)+10)]/(fs/2), 'bandpass');

        % Per-group buckets of per-mouse structs
        G = cell(1,nG); for gi=1:nG, G{gi} = {}; end

        % ---------------- Walk mice ----------------
        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
        for k = 1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('Beta: skip excluded: %s', name); continue; end

            gi = classifyGroupIdx(name, gPats, groups.useRegex);
            if gi==0, logmsg('Beta: unassigned (ambiguous/none): %s', name); continue; end

            mdir = fullfile(root,name);
            [fileList, ~] = findEEGMatFiles(mdir, struct( ...
                'userPattern', userEEGpat, 'userIsRegex', userEEGisReg, ...
                'ignorePatterns',{ignorePats}, 'wantSides',"any", 'allowNonEEG',false));
            if isempty(fileList), logmsg('Beta: no EEG %s', name); continue; end
            EEG = extractBestEEGVector(fullfile(mdir, fileList.name{1}));
            if isempty(EEG) || numel(EEG) < fs, logmsg('Beta: invalid EEG %s', name); continue; end

            try, EEG = filtfilt(b_eeg, a_eeg, double(EEG)); catch, logmsg('Beta: filter fail %s', name); continue; end

            % Beta burst detection via percentile threshold on bandpassed envelope
            betaSig = bandpass(EEG, betaBand, fs);
            env = abs(hilbert(betaSig));
            thr = prctile(env, thrPrct);
            isBurst = env > thr;

            % Extract features (amplitude, duration, frequency, IBI)
            bursts = bwconncomp(isBurst);
            amp = zeros(bursts.NumObjects,1);
            dur = zeros(bursts.NumObjects,1);
            t0 = []; t1 = [];
            for i=1:bursts.NumObjects
                idx = bursts.PixelIdxList{i};
                amp(i) = max(env(idx));
                dur(i) = numel(idx)/fs;
                t0(i)  = idx(1)/fs; %#ok<AGROW>
                t1(i)  = idx(end)/fs; %#ok<AGROW>
            end
            if isempty(amp)
                G{gi}{end+1} = struct('amp',[],'dur',[],'freq',[],'ibi',[],'ibi_short',[],'ibi_long',[]);
                continue;
            end
            ibi = diff(t0); % start-to-start
            freq = 1./max(dur,eps);

            ibi_short = ibi(ibi < 0.05);
            ibi_long  = ibi(ibi > 0.2);

            % per-mouse tidy CSV
            try
                Tm = table(amp(:), dur(:), freq(:), [NaN; ibi(:)], ...
                    'VariableNames', {'Amplitude','Duration_s','Frequency_Hz','IBI_s'});
                writetable(Tm, fullfile(mdir,'beta_bursts_per_mouse.csv'));
            catch ME
                logmsg('Beta per-mouse CSV failed (%s): %s', name, ME.message);
            end

            G{gi}{end+1} = struct('amp',amp(:),'dur',dur(:),'freq',freq(:),'ibi',ibi(:), ...
                'ibi_short',ibi_short(:),'ibi_long',ibi_long(:));
        end

        % ---------------- Group CDFs & exports ----------------
        % CDF plots for amplitude, duration, frequency, IBI, short IBI, long IBI
        fields = {'amp','dur','freq','ibi','ibi_short','ibi_long'};
        labels = {'Amplitude','Duration (s)','Frequency (Hz)','IBI (s)','IBI short (s)','IBI long (s)'};
        for fidx = 1:numel(fields)
            f = figure('Visible','off'); hold on; grid on; xlabel(labels{fidx}); ylabel('CDF');
            title(sprintf('Beta-bursts %s — CDF (per group)', labels{fidx}));
            Colors = lines(max(7,nG));
            for gi = 1:nG
                v = cellfun(@(S) S.(fields{fidx}), G{gi}, 'UniformOutput', false);
                v = vertcat(v{:});
                if isempty(v), continue; end
                [F,X] = ecdf(v);
                plot(X,F, 'LineWidth',1.8, 'Color', Colors(gi,:));
            end
            legend(cellstr(gNames),'Interpreter','none','Location','best'); hold off;
            safe_exportgraphics(f, fullfile(resultsDir, sprintf('beta_%s_cdf.png', fields{fidx})));
            close(f);
        end

        % Tidy dump for all features (per mouse)
        rows = {};
        for gi = 1:nG
            for mi = 1:numel(G{gi})
                S = G{gi}{mi};
                n = max([numel(S.amp), numel(S.dur), numel(S.freq), numel(S.ibi)]);
                T = table( ...
                    repmat(string(gNames(gi)),n,1), repmat(mi,n,1), ...
                    padv(S.amp,n), padv(S.dur,n), padv(S.freq,n), padv(S.ibi,n), ...
                    'VariableNames', {'Group','MouseIdx','Amplitude','Duration_s','Frequency_Hz','IBI_s'});
                rows{end+1} = T; %#ok<AGROW>
            end
        end
        if ~isempty(rows), writetable(vertcat(rows{:}), fullfile(resultsDir,'beta_per_mouse_multi.csv')); end

        % Local helper
        function v = padv(x,n)
            v = nan(n,1); v(1:min(n,numel(x))) = x(1:min(n,numel(x)));
        end

    end


%% --------------- INTERNAL: MDF/SEF/Peak from RAW EEG (multi-group) ---------------
    function runMDFSEF_Internal(root, fs, epoch_sec, codes, baseBP, winN, ovN, sefPerc, doGate, mode, excluded, autoCompute, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)

        % ---------------- Compatibility shim → groups ----------------
        groups = normalize_groups_args(varargin, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex);
        [gNames, gPats] = trimGroups(groups.names, groups.patterns);
        nG = numel(gNames);

        logmsg('MDF/SEF: fs=%g, epoch=%gs, win=%d, ovl=%d, SEF%%=%.3f, gate=%d, mode=%s, auto=%d', ...
            fs, epoch_sec, winN, ovN, sefPerc, doGate, mode, autoCompute);

        resultsDir = fullfile(root, 'MDFSEF_Results');
        if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

        epoch_len = max(1, round(fs*epoch_sec));
        [b_eeg, a_eeg] = butter(4, baseBP/(fs/2), 'bandpass');
        rem_gate = [4.8 9.9]; nrem_gate = [0.8 4.8];

        % Per-group buckets of per-mouse tables
        G = cell(1,nG); for gi=1:nG, G{gi} = {}; end

        % ---------------- Walk mice ----------------
        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
        for k = 1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('MDF/SEF: skip excluded: %s', name); continue; end

            gi = classifyGroupIdx(name, gPats, groups.useRegex);
            if gi==0, logmsg('MDF/SEF: unassigned (ambiguous/none): %s', name); continue; end

            mdir = fullfile(root, name);
            [fileList, ~] = findEEGMatFiles(mdir, struct( ...
                'userPattern', userEEGpat, 'userIsRegex', userEEGisReg, ...
                'ignorePatterns',{ignorePats}, 'wantSides',"any", 'allowNonEEG',false));

            EEG = []; labels = [];
            if ~isempty(fileList)
                EEG = extractBestEEGVector(fullfile(mdir, fileList.name{1}));
            end
            labPath = fullfile(mdir,'labels.mat');
            if exist(labPath,'file'), L = load(labPath); if isfield(L,'labels'), labels = L.labels(:).'; end, end

            if (isempty(EEG) || isempty(labels)) && ~autoCompute
                logmsg('MDF/SEF: missing EEG/labels in %s and autoCompute=0 -> skip', name);
                continue;
            end

            % Compute per-epoch PSD & features
            if isempty(EEG) || numel(EEG)<fs || isempty(labels)
                logmsg('MDF/SEF: autoCompute from scratch not possible (no data) in %s', name);
                continue;
            end

            try
                EEG = filtfilt(b_eeg, a_eeg, double(EEG));
            catch
                logmsg('MDF/SEF: base filter fail in %s', name); continue;
            end

            num_epochs = floor(numel(EEG)/epoch_len);
            if num_epochs<1, logmsg('MDF/SEF: too short %s', name); continue; end
            EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
            labels = labels(1:min(num_epochs,numel(labels)));
            EEG = EEG(:,1:numel(labels));

            rows = {};
            for e = 1:size(EEG,2)
                [Pxx,F] = pwelch(EEG(:,e), winN, ovN, [], fs);
                % optional gating on dominant peak (REM/NREM only)
                if doGate
                    [~,pk] = max(Pxx); pkf = F(pk);
                    if labels(e)==codes(2) && ~(pkf>=rem_gate(1) && pkf<=rem_gate(2)), continue; end
                    if labels(e)==codes(3) && ~(pkf>=nrem_gate(1) && pkf<=nrem_gate(2)), continue; end
                end
                % MDF/SEF (on linear spectrum)
                cum = cumsum(Pxx); tot = cum(end); if tot<=0, continue; end
                % MDF: frequency at which cum power = 50% tot
                MDF = interp1(cum, F, 0.5*tot, 'linear', 'extrap');
                % SEF: frequency at which cum power = sefPerc*tot
                SEF = interp1(cum, F, sefPerc*tot, 'linear', 'extrap');
                % Peak frequency
                [~,pk] = max(Pxx); Peak = F(pk);

                % state label
                st = 'Other';
                if labels(e)==codes(1), st='Wake'; elseif labels(e)==codes(2), st='REM'; elseif labels(e)==codes(3), st='NREM'; end

                rows{end+1} = table(e, string(st), MDF, SEF, Peak, ...
                    'VariableNames', {'EpochIdx','State','MDF_Hz','SEF_Hz','Peak_Hz'}); %#ok<AGROW>
            end

            if isempty(rows), logmsg('MDF/SEF: no epochs retained in %s', name); continue; end
            Tmouse = vertcat(rows{:});
            writetable(Tmouse, fullfile(mdir, 'MDFSEF_per_mouse.csv'));

            G{gi}{end+1} = Tmouse;
        end

        % ---------------- Group exports & plots ----------------
        % Long tidy: Group, MouseIdx, State, MDF/SEF/Peak
        rowsAll = {};
        for gi = 1:nG
            for mi = 1:numel(G{gi})
                T = G{gi}{mi};
                if isempty(T), continue; end
                rowsAll{end+1} = addvars(T, repmat(string(gNames(gi)),height(T),1), repmat(mi,height(T),1), ...
                    'Before',1, 'NewVariableNames',{'Group','MouseIdx'}); %#ok<AGROW>
            end
        end
        if ~isempty(rowsAll)
            Tout = vertcat(rowsAll{:});
            writetable(Tout, fullfile(resultsDir,'MDFSEF_per_mouse_multi.csv'));
        end

        % Group bars (means per state per group)
        States = {'Wake','REM','NREM'};
        % (Replace the inner loop in runMDFSEF_Internal just above)
        for s = 1:numel(States)
            st = States{s};
            f = figure('Visible','off');
            tiledlayout(1,3,'Padding','compact','TileSpacing','compact');
            metrics = {'MDF_Hz','SEF_Hz','Peak_Hz'};
            for m=1:3
                nexttile; hold on; grid on; title(sprintf('%s — %s', st, metrics{m}));
                mu = zeros(nG,1); se = zeros(nG,1);
                for gi=1:nG
                    vm = [];
                    for mi=1:numel(G{gi})
                        T = G{gi}{mi};
                        vm(end+1) = mean(T.(metrics{m})(strcmp(T.State,st)), 'omitnan'); %#ok<AGROW>
                    end
                    mu(gi) = mean(vm,'omitnan');
                    se(gi) = std(vm,0,'omitnan') / sqrt(max(1,numel(vm)));
                end
                bar(1:nG, mu, 'FaceColor','flat');
                er = errorbar(1:nG, mu, se, '.'); er.LineWidth=1.2; er.Color=[0 0 0];
                set(gca,'XTick',1:nG,'XTickLabel',cellstr(gNames),'XTickLabelRotation',30);
                ylabel(metrics{m});
                hold off;
            end
            safe_exportgraphics(f, fullfile(resultsDir, sprintf('MDFSEF_group_%s.png', lower(st))));
            close(f);
        end


    end


%% ---------------------- INTERNAL: General PAC (Dynamic Bands) ----------------------
function runGenPAC_Internal(root, fs, epoch_sec, codes, useManual, zthr, ...
        phaseBands, ampBands, Nbins, excluded, doMI, doGroup, stateSel, ...
        grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
        userEEGpat, userEEGisReg, ignorePats, varargin)

    % ---------------- Compatibility shim → groups (supports multi & legacy A/B) -----
    groups = normalize_groups_args(varargin, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex);
    [gNames, gPats] = trimGroups(groups.names, groups.patterns);
    nG = numel(gNames);

    logmsg('GPAC: fs=%g, epoch=%gs, NphaseInput=%d, NampInput=%d, bins=%d, MI=%d, state=%s', ...
        fs, epoch_sec, size(phaseBands,1), size(ampBands,1), Nbins, doMI, upper(string(stateSel)));

    % Match old folder naming for top-level
    resultsDir = fullfile(root, 'General PAC Results');
    if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

    epoch_len = max(1, round(fs*epoch_sec));

    % --------- Accumulators for group aggregation ----------
    G_dist  = cell(1,nG);    % each {mouse} -> cell array of per-pair tables
    G_MI    = cell(1,nG);    % each {mouse} -> MI matrix (ampCenters × phaseCenters)

    % --------- Build sliding 2 Hz grid for MI (old logic) ----------
    if doMI
        [phaseCentersHz, fp1, fp2] = buildSliding2HzGrid_fromPairs(phaseBands);
        [ampCentersHz,   fa1, fa2] = buildSliding2HzGrid_fromPairs(ampBands);
    else
        phaseCentersHz=[]; ampCentersHz=[]; fp1=[]; fp2=[]; fa1=[]; fa2=[];
    end

    % ---------------- Walk mice ----------------
    d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
    for k = 1:numel(d)
        name = d(k).name;
        if any(strcmp(name, excluded)), logmsg('GPAC: skip excluded: %s', name); continue; end

        gi = classifyGroupIdx(name, gPats, groups.useRegex);
        if gi==0, logmsg('GPAC: unassigned (ambiguous/none): %s', name); continue; end

        mdir = fullfile(root,name);
        outdir = fullfile(mdir, 'General PAC');        % per-mouse folder (as before)
        if ~exist(outdir,'dir'), mkdir(outdir); end

        % Select state vector (Wake/REM/NREM) → single continuous vector
        EEG_state = load_state_eeg_vector(mdir, fs, epoch_len, codes, stateSel, useManual, userEEGpat, userEEGisReg, ignorePats);
        if isempty(EEG_state), logmsg('GPAC: no samples for %s in %s', upper(stateSel), name); continue; end

        % Clean outliers (kept)
        z = zscore(double(EEG_state));
        EEG_state(abs(z)>zthr) = NaN;
        EEG_state = fillmissing(EEG_state,'linear');

        % ================== PAC DISTRIBUTIONS (old behavior) ==================
        % Use the user-provided bands AS-GIVEN (no auto-slicing)
        edges   = linspace(0, 720, Nbins+1);
        centers = (edges(1:end-1) + edges(2:end))/2;

        rowsMouse = {};
        for ip = 1:size(phaseBands,1)
            th = phaseBands(ip,:);
            thSig    = bandpass(EEG_state, th, fs);
            thPhase  = angle(hilbert(thSig));
            thDeg360 = mod(rad2deg(thPhase), 360);
            thDeg720 = [thDeg360; thDeg360+360];      % duplication as in newer code for smoothness

            for ia = 1:size(ampBands,1)
                ga   = ampBands(ia,:);
                gaSig  = bandpass(EEG_state, ga, fs);
                gaAmp  = abs(hilbert(gaSig));
                gaAmp2 = [gaAmp; gaAmp];

                gamma_avg = zeros(Nbins,1);
                for b = 1:Nbins
                    inb = (thDeg720 >= edges(b)) & (thDeg720 < edges(b+1));
                    gamma_avg(b) = mean(gaAmp2(inb), 'omitnan');
                end
                gamma_smoothed = smooth(gamma_avg,3);
                gamma_smoothed = gamma_smoothed / sum(gamma_smoothed + eps);

                % Per-pair row block (we keep a combined table, but with explicit ranges)
                rowsMouse{end+1} = table( ...
                    centers(:), ...
                    repmat(th(1),Nbins,1), repmat(th(2),Nbins,1), ...
                    repmat(ga(1),Nbins,1), repmat(ga(2),Nbins,1), ...
                    gamma_smoothed(:), ...
                    'VariableNames', {'ThetaPhase_deg','PhaseLow_Hz','PhaseHigh_Hz','AmpLow_Hz','AmpHigh_Hz','GammaNormAmp'}); %#ok<AGROW>

                % Optional: also write per-pair CSV like the old function
                pairLabel = sprintf('%s_phase_%g-%g_amp_%g-%g', upper(stateSel), th(1),th(2),ga(1),ga(2));
                try
                    Tmouse = table(centers(:), gamma_smoothed(:), ...
                        'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
                    writetable(Tmouse, fullfile(outdir, sprintf('GPAC_Dist_%s_%dbins.csv', pairLabel, Nbins)));
                catch ME
                    logmsg('GPAC per-mouse distribution CSV failed (%s): %s', name, ME.message);
                end
            end
        end

        % Save one combined CSV as well (convenience)
        if ~isempty(rowsMouse)
            try
                Tout = vertcat(rowsMouse{:});
                writetable(Tout, fullfile(outdir, sprintf('GPAC_Dist_%s_%dbins_ALLPAIRS.csv', upper(stateSel), Nbins)));
            catch ME
                logmsg('GPAC combined per-mouse dist CSV failed (%s): %s', name, ME.message);
            end
        end
        G_dist{gi}{end+1} = rowsMouse; %#ok<AGROW>

        % ========================== MI MAP (old behavior) ==========================
        if doMI && ~isempty(phaseCentersHz) && ~isempty(ampCentersHz)
            try
                Q  = 1/Nbins;
                MI = zeros(numel(ampCentersHz), numel(phaseCentersHz));

                % Old logic: no 0..720° duplication, no per-epoch z-norm; use discretize(ph, Nbins)
                for ic = 1:numel(phaseCentersHz)
                    ph  = angle(hilbert(bandpass(EEG_state, [fp1(ic) fp2(ic)], fs)));
                    [bins, ~] = discretize(ph, Nbins);

                    for jc = 1:numel(ampCentersHz)
                        a  = abs(hilbert(bandpass(EEG_state, [fa1(jc) fa2(jc)], fs)));
                        D  = zeros(1,Nbins);
                        for ii = 1:Nbins
                            m = (bins == ii);
                            if any(m)
                                D(ii) = mean(a(m), 'omitnan');
                            else
                                D(ii) = 0;
                            end
                        end
                        D = D ./ (sum(D) + eps);
                        MI(jc,ic) = sum(D .* log((D+eps)/Q)) / log(Nbins);
                    end
                end

                % Save MI like old code
                save(fullfile(outdir, sprintf('MI data (%d bins).mat', Nbins)), 'MI');
                try
                    MItab = array2table(MI, 'VariableNames', ...
                        matlab.lang.makeValidName("theta_"+string(phaseCentersHz)+"Hz"));
                    MItab = addvars(MItab, ampCentersHz(:), 'Before', 1, 'NewVariableNames','gammaAmp_Hz');
                    writetable(MItab, fullfile(outdir, sprintf('MI_%dbins.csv', Nbins)));
                catch ME
                    logmsg('GPAC per-mouse MI CSV failed (%s): %s', name, ME.message);
                end

                G_MI{gi}{end+1} = MI; %#ok<AGROW>
            catch ME
                logmsg('GPAC per-mouse MI compute failed (%s): %s', name, ME.message);
            end
        end
    end % mice

    % ---------------- Group plots/exports ----------------
    % Group distribution overlays (mean across mice) for each (phase,amp) pair
    if ~isempty(G_dist)
        for ip = 1:size(phaseBands,1)
            for ia = 1:size(ampBands,1)
                f = figure('Visible','off'); hold on; grid on;
                xlim([0 720]); xticks(0:90:720);
                xlabel('\theta phase (°)'); ylabel('Normalized \gamma amplitude');
                title(sprintf('General PAC — %s — phase[%g %g]Hz × amp[%g %g]Hz', ...
                    upper(stateSel), phaseBands(ip,1),phaseBands(ip,2), ampBands(ia,1),ampBands(ia,2)));
                Colors = lines(max(7,nG));
                for gi = 1:nG
                    mu = mean_dist_for_pair(G_dist{gi}, ip, ia);
                    if isempty(mu), continue; end
                    plot(mu.ThetaPhase_deg, mu.GammaNormAmp, 'LineWidth',1.8, 'Color', Colors(gi,:));
                end
                legend(cellstr(gNames),'Interpreter','none','Location','best'); hold off;
                outP = fullfile(resultsDir, sprintf('gpac_group_dist_%s_ph[%g_%g]_am[%g_%g].png', ...
                    lower(stateSel), phaseBands(ip,1),phaseBands(ip,2), ampBands(ia,1),ampBands(ia,2)));
                safe_exportgraphics(f, outP); close(f);
            end
        end
    end

    % Group MI heatmaps (match old axes/plot style)
    if doMI && doGroup
        for gi = 1:nG
            if isempty(G_MI{gi}), continue; end
            try
                MImean = mean(cat(3, G_MI{gi}{:}), 3, 'omitnan');
                f = figure('Visible','off');
                contourf(phaseCentersHz, ampCentersHz, MImean, 120, 'linecolor','none');
                title(sprintf('General PAC — %s — Mean MI (%s)', upper(stateSel), gNames{gi}), 'Interpreter','none');
                xlabel('Phase (Hz)'); ylabel('Amp (Hz)'); colorbar;
                outP = fullfile(resultsDir, sprintf('gpac_mi_heatmap_%s_%s.png', ...
                    lower(stateSel), lower(string(gNames(gi)))));
                try, exportgraphics(f, outP, 'Resolution', 200); catch, saveas(f, outP); end
                close(f);
            catch ME
                logmsg('GPAC group MI export failed for %s: %s', string(gNames(gi)), ME.message);
            end
        end
    end

    % ---------------- Local helpers ----------------
    function [centersHz, f1, f2] = buildSliding2HzGrid_fromPairs(bandPairs)
        % Old behavior: make a continuous 2 Hz sliding grid that spans the full
        % min(low) .. max(high) of the provided pairs. Window width = 2 Hz,
        % centers at integer Hz, step = 1 Hz.
        if isempty(bandPairs) || ~isnumeric(bandPairs)
            centersHz=[]; f1=[]; f2=[]; return;
        end
        lo = min(bandPairs(:,1)); hi = max(bandPairs(:,2));
        if ~isfinite(lo) || ~isfinite(hi) || hi <= lo
            centersHz=[]; f1=[]; f2=[]; return;
        end
        centersHz = (max(1, floor(lo)) : 1 : ceil(hi));   % integer centers
        f1 = max(1, centersHz - 1);                       % width = 2 Hz
        f2 = f1 + 2;
        keep = f2 > f1;
        centersHz = centersHz(keep);
        f1 = f1(keep); f2 = f2(keep);
        centersHz = centersHz(:); f1 = f1(:); f2 = f2(:);
    end

    function mu = mean_dist_for_pair(cellRows, ip, ia)
        if isempty(cellRows), mu = []; return; end
        Vecs = {};
        for m = 1:numel(cellRows)
            if isempty(cellRows{m}), continue; end
            idx = (ia-1)*size(phaseBands,1) + ip;  % same packing order used above
            if numel(cellRows{m}) < idx, continue; end
            T = cellRows{m}{idx};
            if ~isempty(T), Vecs{end+1} = T.GammaNormAmp(:); end %#ok<AGROW>
        end
        if isempty(Vecs), mu = []; return; end
        n = numel(Vecs{1});
        M = nan(n, numel(Vecs));
        for i=1:numel(Vecs)
            v = Vecs{i};
            if numel(v)==n, M(:,i) = v; end
        end
        amp = mean(M,2,'omitnan');
        mu = table(cellRows{1}{idx}.ThetaPhase_deg(:), amp(:), ...
            'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
    end

    function EEG_state = load_state_eeg_vector(mdir, fs, epoch_len, codes, stateSel, useManual, userEEGpat, userEEGisReg, ignorePats)
        % Prefer manual REM if requested
        if strcmpi(stateSel,'rem') && useManual
            p = fullfile(mdir,'REM_EEG_accusleep.mat');
            if exist(p,'file')
                S = load(p);
                if isfield(S,'REM_EEG')
                    EEG_state = detrend(double(S.REM_EEG(:)), 0);
                    return;
                end
            end
        end
        % Discover EEG
        [fileList, ~] = findEEGMatFiles(mdir, struct( ...
            'userPattern', userEEGpat, 'userIsRegex', userEEGisReg, ...
            'ignorePatterns',{ignorePats}, 'wantSides',"any", 'allowNonEEG',false));
        if isempty(fileList), EEG_state = []; return; end

        EEG = extractBestEEGVector(fullfile(mdir, fileList.name{1}));
        if isempty(EEG), EEG_state = []; return; end
        EEG = double(EEG(:));

        % Labels
        labPath = fullfile(mdir,'labels.mat');
        if ~exist(labPath,'file'), EEG_state = []; return; end
        L = load(labPath);
        if ~isfield(L,'labels'), EEG_state = []; return; end
        labels = L.labels(:).';

        % Epoch to align with labels
        num_epochs = floor(numel(EEG)/epoch_len);
        if num_epochs < 1, EEG_state = []; return; end
        EEG    = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
        labels = labels(1:min(num_epochs, numel(labels)));
        EEG    = EEG(:, 1:numel(labels));

        % Pick the state
        switch lower(stateSel)
            case 'wake', target = codes(1);
            case 'rem',  target = codes(2);
            case 'nrem', target = codes(3);
            otherwise,   target = codes(2);
        end
        idx = find(labels == target);
        if isempty(idx), EEG_state = []; return; end

        % Return a single continuous vector (chronological)
        EEG_state = reshape(EEG(:, idx), [], 1);
        EEG_state = detrend(EEG_state, 0);   % remove DC
    end
end




%% ------------------------------ utilities ----------------------------------
% NOTE:
% - pickVec and pickVecPreferMerged share one core (getFirstNumericVector).
% - padToTable / padToTableLikeOriginal share one core (padStructFieldsEqualLen).
% - Parsers are defensive (no eval, tolerant whitespace, clear errors).
% - plotCDF / plotCDF_likeScript: safer NaN handling, optional legend labels.

    function v = pickVec(S)
        % Prefer 'merged_vector' if present; else first numeric vector.
        v = [];
        if isfield(S,'merged_vector') && isnumeric(S.merged_vector) && isvector(S.merged_vector)
            v = S.merged_vector(:);
            return;
        end
        v = getFirstNumericVector(S);
    end

    function v = pickVecPreferMerged(S)
        % Alias of pickVec for backward-compat.
        v = pickVec(S);
    end

    function v = getFirstNumericVector(S)
        % Helper: return the first numeric vector found (columnized).
        v = [];
        fns = fieldnames(S);
        for ii=1:numel(fns)
            x = S.(fns{ii});
            if isnumeric(x) && isvector(x)
                v = x(:);
                return;
            end
        end
    end

    function T = padToTable(S)
        % Pad fields to equal length and return as a table (column vectors).
        S = padStructFieldsEqualLen(S);
        T = struct2table(S);
    end

    function T = padToTableLikeOriginal(S)
        % Backward-compatible wrapper (same behavior as padToTable).
        S = padStructFieldsEqualLen(S);
        T = struct2table(S);
    end

    function S = padStructFieldsEqualLen(S)
        % Ensure all numeric-vector fields are columnized and padded with NaN.
        fns = fieldnames(S);
        maxL = 0;
        for ii=1:numel(fns)
            v = S.(fns{ii});
            if isrow(v), v = v.'; end
            S.(fns{ii}) = v;
            maxL = max(maxL, numel(v));
        end
        for ii=1:numel(fns)
            v = S.(fns{ii});
            if numel(v) < maxL
                S.(fns{ii}) = [v; NaN(maxL-numel(v),1)];
            end
        end
    end

    function xs = parseList(s)
        % Split by commas; trims and drops empty parts. Accepts char/string/cellstr.
        if iscellstr(s), xs = s(~cellfun(@isempty,s)); return; end
        s = string(s);
        s = strtrim(s);
        if strlength(s)==0
            xs = {};
        else
            parts = regexp(s, '\s*,\s*', 'split');
            xs = parts(~cellfun(@isempty, parts));
        end
    end

    function [W,R,N] = parseLabelCodes(s)
        % Accepts "wake rem nrem" as space- or comma-separated (e.g., "2 1 3").
        a = regexp(strtrim(char(s)), '[,\s]+', 'split');
        a = str2double(a(~cellfun(@isempty,a)));
        if numel(a) ~= 3 || any(isnan(a))
            error('Label codes must be three numbers, e.g. "2 1 3".');
        end
        W=a(1); R=a(2); N=a(3);
    end

    function b = parseBand(s)
        % Accepts "low high" (spaces/commas). Returns sorted 1x2 row.
        a = regexp(strtrim(char(s)), '[,\s]+', 'split');
        a = str2double(a(~cellfun(@isempty,a)));
        if numel(a)~=2 || any(isnan(a))
            error('Band must be two numbers: "low high".');
        end
        b = sort(a(:)).';
    end

    function xlims = parseXlimList(s)
        % Parse 6 items separated by semicolons. Each item can be:
        %   []            -> empty
        %   [a b] or a b  -> numeric 1x2 range
        % Example:
        %   [0 1]; [0 .5]; []; []; [0 .05]; [0 .8]
        parts = regexp(char(s), '\s*;\s*', 'split');
        if numel(parts) ~= 6
            error('Expected 6 semicolon-separated xlim items.');
        end
        parseOne = @(tok) local_parse_xlim_item(tok);
        xlims.amp      = parseOne(parts{1});
        xlims.dur      = parseOne(parts{2});
        xlims.freq     = parseOne(parts{3});
        xlims.ibi      = parseOne(parts{4});
        xlims.ibiShort = parseOne(parts{5});
        xlims.ibiLong  = parseOne(parts{6});
    end

    function rng = local_parse_xlim_item(tok)
        tok = strtrim(string(tok));
        if tok=="" || tok=="[]"
            rng = [];
            return;
        end
        % remove brackets if present
        tok = regexprep(tok, '^\[|\]$', '');
        parts = regexp(tok, '[,\s]+', 'split');
        parts = parts(~cellfun(@isempty,parts));
        nums  = str2double(parts);
        if numel(nums)~=2 || any(isnan(nums))
            error('Invalid xlim item: "%s". Use [], [a b], or "a b".', tok);
        end
        rng = [min(nums), max(nums)];
    end

    function logmsg(fmt, varargin)
        % Log to GUI if available; otherwise to command window.
        try
            s = sprintf([fmt '\n'], varargin{:});
        catch
            s = [char(fmt) newline];
        end
        if exist('logBox','var') && ~isempty(logBox) && isvalid(logBox)
            try
                logBox.Value = [logBox.Value; s]; %#ok<AGROW>
                drawnow limitrate;
                return;
            catch
                % fall through to fprintf
            end
        end
        fprintf('%s', s);
    end


% -------------------------- Simple A/B CDFs --------------------------
    function plotCDF(WT,DS,ttl,xl)
        % Back-compat legend labels ('WT','DS'), robust to NaNs/empties.
        WT = WT(:); DS = DS(:);
        WT = WT(isfinite(WT));
        DS = DS(isfinite(DS));
        if isempty(WT) && isempty(DS), return; end

        figure; hold on;
        if ~isempty(WT)
            [F1,X1]=ecdf(WT);
            plot(X1,F1,'-','LineWidth',1,'Color',[.5 .5 .5]);
        end
        if ~isempty(DS)
            [F2,X2]=ecdf(DS);
            plot(X2,F2,'-','LineWidth',1,'Color',[.3 .6 1]);
        end
        hold off; grid on;
        xlabel(ttl); ylabel('Cumulative frequency');
        title(['CDF of ' ttl]);
        if ~isempty(xl), xlim(xl); end

        legendEntries = {};
        if ~isempty(WT), legendEntries{end+1}='WT'; end %#ok<AGROW>
        if ~isempty(DS), legendEntries{end+1}='DS'; end %#ok<AGROW>
        if ~isempty(legendEntries)
            legend(legendEntries,'Location','southeast'); legend boxoff;
        end
    end

% --------------------- Generic CDF (labels: A/B) ---------------------
    function plotCDF_likeScript(A,B,what,xlimv)
        % NaN-safe; labels are 'Group A'/'Group B' for generic pipelines.
        A = A(:); B = B(:);
        A = A(isfinite(A));
        B = B(isfinite(B));
        if isempty(A) && isempty(B), return; end

        [A_F, A_X] = deal([]);
        [B_F, B_X] = deal([]);
        if ~isempty(A), [A_F, A_X] = ecdf(A); end
        if ~isempty(B), [B_F, B_X] = ecdf(B); end

        figure; hold on;
        if ~isempty(A_X), plot(A_X, A_F, '-', 'LineWidth',1, 'Color',[0.5 0.5 0.5]); end
        if ~isempty(B_X), plot(B_X, B_F, '-', 'LineWidth',1, 'Color',[0.3 0.6 1.0]); end
        hold off; grid on;
        xlabel(what, 'FontSize',14);
        ylabel('Cumulative frequency','FontSize',14);
        title(['CDF of ' what], 'FontSize',14);
        if ~isempty(xlimv), xlim(xlimv); end
        set(gca,'FontSize',12,'Box','off');
        leg = {};
        if ~isempty(A_X), leg{end+1}='Group A'; end %#ok<AGROW>
        if ~isempty(B_X), leg{end+1}='Group B'; end %#ok<AGROW>
        if ~isempty(leg)
            legend(leg,'Location','southeast'); legend boxoff;
        end
    end

% ------------------- A/B group classifier (string/regex) -------------------
% Returns: 1=A, 2=B, 0=Unassigned
    function grp = classifyGroup(name, patA, patB, useRegex)
        grpA = false; grpB = false;
        name = string(name);
        if useRegex
            try
                if ~isempty(patA), grpA = ~isempty(regexpi(name, patA, 'once')); end
            catch, grpA = false; end
            try
                if ~isempty(patB), grpB = ~isempty(regexpi(name, patB, 'once')); end
            catch, grpB = false; end
        else
            if ~isempty(patA), grpA = contains(name, patA, 'IgnoreCase',true); end
            if ~isempty(patB), grpB = contains(name, patB, 'IgnoreCase',true); end
        end
        if grpA && ~grpB, grp = 1; return; end
        if grpB && ~grpA, grp = 2; return; end
        grp = 0; % matches both or none → unassigned
    end

% -------- local parser for xlim items (no eval) --------
% (kept above as local_parse_xlim_item)

% ---------------------------- end utilities ---------------------------------


% ===================== Helper Functions used outside main scope: =====================

    function doGroupMI(root, Nbins, varargin)
        % doGroupMI — plots group mean MI heatmaps.
        % Supports:
        %   1) Multi-group: doGroupMI(root, Nbins, groupsStruct)
        %        where groupsStruct has fields: names, patterns, (optional) useRegex
        %   2) Legacy 2-group:
        %        doGroupMI(root, Nbins, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex)

        if ~isfolder(root)
            logmsg('doGroupMI: invalid root: %s', string(root));
            return;
        end

        % -------- Determine calling mode --------
        multiMode = (~isempty(varargin)) && isstruct(varargin{1}) ...
            && isfield(varargin{1},'names') && isfield(varargin{1},'patterns');

        if multiMode
            groups   = varargin{1};
            % Normalize names/patterns into cellstr columns and drop empty pairs
            [gNames, gPats] = trimGroups(groups.names, groups.patterns);
            if isempty(gNames)
                logmsg('doGroupMI: no valid groups defined.');
                return;
            end
            useRegex = false;
            if isfield(groups,'useRegex'), useRegex = logical(groups.useRegex); end
        else
            % Legacy: expect at least 5 trailing args (nameA, nameB, patA, patB, useRegex)
            if numel(varargin) < 5
                logmsg('doGroupMI: legacy mode expects: grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex.');
                return;
            end
            grpA_name = char(varargin{1});
            grpB_name = char(varargin{2});
            grpA_pat  = char(varargin{3});
            grpB_pat  = char(varargin{4});
            useRegex  = logical(varargin{5});

            gNames = {grpA_name, grpB_name};
            gPats  = {grpA_pat,  grpB_pat };
        end

        % -------- Collect MI matrices per group --------
        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

        if multiMode
            G_MI = cell(1, numel(gNames));    % each cell holds a {MI, MI, ...} per group
            for gi = 1:numel(G_MI), G_MI{gi} = {}; end
        else
            MI_A = {}; MI_B = {};
        end

        for k = 1:numel(d)
            name = d(k).name;
            mdir = fullfile(root, name);

            % Determine group
            if multiMode
                gi = classifyGroupIdx(name, gPats, useRegex);
                if gi == 0, continue; end
            else
                % Legacy: map to A/B explicitly
                ga = matchOne(name, gPats{1}, useRegex);
                gb = matchOne(name, gPats{2}, useRegex);
                if ga && ~gb
                    gi = 1;
                elseif gb && ~ga
                    gi = 2;
                else
                    gi = 0;
                end
                if gi == 0, continue; end
            end

            % Load MI file if exists
            p = fullfile(mdir, 'new PAC', sprintf('MI data (%d bins).mat', Nbins));
            if ~exist(p, 'file'), continue; end
            S = load(p);
            if ~isfield(S, 'MI') || ndims(S.MI) ~= 2, continue; end

            if multiMode
                G_MI{gi}{end+1} = S.MI; %#ok<AGROW>
            else
                if gi == 1, MI_A{end+1} = S.MI; else, MI_B{end+1} = S.MI; end %#ok<AGROW>
            end
        end

        % Axes grids (match your PAC code)
        phase_freqs = 3:14;    % theta phase centers (Hz)
        amp_freqs   = 30:1:100; % gamma amp centers (Hz)

        % -------- Plotting --------
        if multiMode
            % One figure per group
            for gi = 1:numel(gNames)
                if isempty(G_MI{gi}), continue; end
                try
                    mean_MI = mean(cat(3, G_MI{gi}{:}), 3, 'omitnan');
                    figure;
                    contourf(phase_freqs, amp_freqs, mean_MI, 120, 'linecolor','none');
                    title(sprintf('Mean MI — %s', char(gNames{gi})), 'Interpreter','none');
                    xlabel('Phase Frequency (Hz)'); ylabel('Amplitude Frequency (Hz)');
                    colormap jet; colorbar;
                    caxis([0 0.001]); xlim([min(phase_freqs) max(phase_freqs)]); ylim([min(amp_freqs) max(amp_freqs)]);
                catch ME
                    logmsg('doGroupMI plot failed for %s: %s', string(gNames{gi}), ME.message);
                end
            end
        else
            % Legacy: two subplots (A | B)
            if isempty(MI_A) && isempty(MI_B)
                logmsg('doGroupMI: no MI data found.');
                return;
            end
            figure;
            if ~isempty(MI_A)
                mean_MI_A = mean(cat(3, MI_A{:}), 3, 'omitnan');
                subplot(1,2,1);
                contourf(phase_freqs, amp_freqs, mean_MI_A, 120, 'linecolor','none');
                title(sprintf('Mean MI — %s', char(gNames{1})), 'Interpreter','none');
                xlabel('Phase Frequency (Hz)'); ylabel('Amplitude Frequency (Hz)');
                colormap jet; colorbar; caxis([0 0.001]); xlim([min(phase_freqs) max(phase_freqs)]); ylim([min(amp_freqs) max(amp_freqs)]);
            end
            if ~isempty(MI_B)
                mean_MI_B = mean(cat(3, MI_B{:}), 3, 'omitnan');
                subplot(1,2,2);
                contourf(phase_freqs, amp_freqs, mean_MI_B, 120, 'linecolor','none');
                title(sprintf('Mean MI — %s', char(gNames{2})), 'Interpreter','none');
                xlabel('Phase Frequency (Hz)'); ylabel('Amplitude Frequency (Hz)');
                colormap jet; colorbar; caxis([0 0.001]); xlim([min(phase_freqs) max(phase_freqs)]); ylim([min(amp_freqs) max(amp_freqs)]);
            end
        end

        % ---------------- local helpers ----------------
        function tf = matchOne(mouseName, pat, rx)
            mouseName = string(mouseName);
            pat = string(pat);
            if strlength(pat) == 0
                tf = false;
                return;
            end
            if rx
                try
                    tf = ~isempty(regexpi(mouseName, pat, 'once'));
                catch
                    tf = false;
                end
            else
                tf = contains(mouseName, pat, 'IgnoreCase', true);
            end
        end

        function gi = classifyGroupIdx(mouseName, patList, rx)
            % Returns 1..N for first matching pattern, 0 if none/ambiguous
            hit = false(1, numel(patList));
            for ii = 1:numel(patList)
                hit(ii) = matchOne(mouseName, patList{ii}, rx);
            end
            if sum(hit) == 1
                gi = find(hit, 1, 'first');
            else
                gi = 0; % none or ambiguous
            end
        end
    end


% ------- helper: return group index (1..n), or 0 if unassigned -------
    function gix = local_match_group(name, Gpats, Gregex)
        gix = 0;
        nm = string(name);
        for gi = 1:numel(Gpats)
            pat = Gpats{gi};
            if isempty(pat), continue; end
            try
                ok = false;
                if Gregex
                    ok = ~isempty(regexpi(nm, pat, 'once'));
                else
                    ok = contains(nm, pat, 'IgnoreCase', true);
                end
                if ok
                    if gix == 0
                        gix = gi;
                    else
                        % matched more than one group → treat as unassigned
                        gix = 0;
                        return;
                    end
                end
            catch
                % invalid regex/pattern → ignore
            end
        end
    end


    function [fileList, meta] = findEEGMatFiles(mdir, opts)
        % Nested-safe version (no `arguments`). Returns:
        %   fileList.name  — cellstr of candidate filenames (no paths)
        %   meta.fellBack  — true if userPattern failed and we used fallbacks
        if nargin < 2 || isempty(opts), opts = struct; end
        % defaults
        if ~isfield(opts,'userPattern'),    opts.userPattern = '';          end
        if ~isfield(opts,'userIsRegex'),    opts.userIsRegex = false;       end
        if ~isfield(opts,'ignorePatterns'), opts.ignorePatterns = {};       end
        if ~isfield(opts,'wantSides'),      opts.wantSides = 'any';         end %#ok<NASGU>
        if ~isfield(opts,'allowNonEEG'),    opts.allowNonEEG = false;       end %#ok<NASGU>

        % normalize types
        if isstring(opts.userPattern),    opts.userPattern = char(opts.userPattern); end
        if isstring(opts.wantSides),      opts.wantSides   = char(opts.wantSides);   end
        if isstring(opts.ignorePatterns), opts.ignorePatterns = cellstr(opts.ignorePatterns); end

        meta = struct('fellBack', false);
        dd = dir(fullfile(mdir,'*.mat'));
        names = {dd.name};

        % Exclude by ignorePatterns (case-insensitive substring)
        if ~isempty(opts.ignorePatterns)
            keep = true(size(names));
            for i = 1:numel(names)
                for j = 1:numel(opts.ignorePatterns)
                    pat = lower(char(opts.ignorePatterns{j}));
                    if ~isempty(pat) && contains(lower(names{i}), pat)
                        keep(i) = false; break;
                    end
                end
            end
            names = names(keep);
        end

        % 1) Try user pattern
        if ~isempty(opts.userPattern)
            cand = {};
            for i = 1:numel(names)
                f = names{i};
                if opts.userIsRegex
                    ok = ~isempty(regexpi(f, opts.userPattern, 'once'));
                else
                    ok = contains(f, opts.userPattern, 'IgnoreCase', true);
                end
                if ok, cand{end+1} = f; end %#ok<AGROW>
            end
            if ~isempty(cand)
                fileList = struct('name',{cand});
                return
            end
        end

        % 2) Fallback heuristics
        meta.fellBack = true;

        prefOrder = { ...
            'EEG_accusleep.mat', ...
            'EEG.mat', ...
            'EEG(R).mat', ...
            'EEG(L).mat', ...
            'REM_EEG_accusleep.mat' ...
            };
        found = intersect(prefOrder, names, 'stable');
        if ~isempty(found)
            fileList = struct('name',{found});
            return
        end

        % Otherwise anything that looks like an EEG file
        cand = {};
        for i = 1:numel(names)
            if ~isempty(regexpi(names{i}, '(^|[_-])EEG([_()-]|$)', 'once'))
                cand{end+1} = names{i}; %#ok<AGROW>
            end
        end
        if isempty(cand)
            fileList = struct('name', {{}});
        else
            fileList = struct('name', {cand});
        end
    end

    function v = extractBestEEGVector(matPath)
        % Nested-safe. Load a .mat and return the best EEG vector.
        v = [];
        if ~isfile(matPath), return; end
        S = load(matPath);

        if isfield(S,'EEG') && isnumeric(S.EEG) && isvector(S.EEG)
            v = S.EEG(:); return
        end
        if isfield(S,'merged_vector') && isnumeric(S.merged_vector) && isvector(S.merged_vector)
            v = S.merged_vector(:); return
        end

        % Unwrap a single nested struct layer (common export pattern)
        fns = fieldnames(S);
        if numel(fns)==1 && isstruct(S.(fns{1}))
            S = S.(fns{1});
            fns = fieldnames(S);
        end

        % First numeric vector inside
        v = getFirstNumericVector(S);
    end

    function [names, pats, useRegex] = normalizeGroups(groups)
        useRegex = false;
        if isstruct(groups) && isfield(groups,'useRegex') && isscalar(groups.useRegex)
            useRegex = logical(groups.useRegex);
        end
        if isstruct(groups) && numel(groups) > 1
            names = string({groups.names});
            pats  = string({groups.pats});
        elseif isstruct(groups)
            names = string(groups.names);
            pats  = string(groups.pats);
        else
            error('groups must be a struct with fields "names" and "pats".');
        end
        names = names(:);
        pats  = pats(:);
    end

    function M = toDoubleMatrix_gpac(x)
        % Convert MI entries that may arrive as cells or numeric to a double matrix.
        % Return [] on failure so callers can skip safely.
        try
            if isempty(x)
                M = [];
            elseif iscell(x)
                % If it's a single cell holding a numeric, unwrap it; otherwise, try cell2mat
                if numel(x)==1 && isnumeric(x{1})
                    M = double(x{1});
                else
                    M = cell2mat(x); % will error if shapes differ → caught below
                    M = double(M);
                end
            elseif isnumeric(x)
                M = double(x);
            else
                M = [];
            end
        catch
            M = [];
        end
    end

    function v = normalizeVectorToDouble_gpac(x)
        % x may be numeric, string, cellstr, or cell of numerics/strings.
        v = [];
        try
            if isempty(x), return; end
            if iscell(x)
                % flatten mixed cells into strings then to doubles
                xs = cellfun(@(y) string(y), x, 'UniformOutput', false);
                xs = string([xs{:}]);
                v  = str2double(xs);
            elseif isstring(x)
                v = str2double(x);
            else
                v = double(x);
            end
            v = v(:);
            v = v(~isnan(v));  % drop non-numeric tokens if any
        catch
            v = [];
        end
    end

    function M = deepToDoubleMatrix_gpac(x)
        % Normalize MI entries to a double matrix or return [] to skip.
        try
            if isempty(x)
                M = [];
            elseif isnumeric(x)
                M = double(x);
            elseif isstring(x)
                % string array -> try numeric
                M = str2double(x);
                if any(isnan(M),'all'), M = []; end
            elseif iscell(x)
                % unwrap singletons first
                if numel(x)==1
                    M = deepToDoubleMatrix_gpac(x{1});
                else
                    % attempt: convert each cell to numeric, then cell2mat
                    C = cellfun(@deepToDoubleMatrix_gpac, x, 'UniformOutput', false);
                    ok = all(cellfun(@(y) isnumeric(y) && ~isempty(y), C));
                    if ~ok
                        M = [];
                    else
                        try
                            M = cell2mat(C);
                        catch
                            M = [];
                        end
                    end
                end
            else
                M = [];
            end
        catch
            M = [];
        end
    end

    function groups = normalize_groups_args(varg, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex)
        % Accepts varargin from runModule (may include groups at end), maps legacy A/B → groups struct.
        groups = [];
        if ~isempty(varg) && isstruct(varg{1}) && (isfield(varg{1},'names') || isfield(varg{1},'patterns') || isfield(varg{1},'pats'))
            g = varg{1};
            if isfield(g,'pats') && ~isfield(g,'patterns'), g.patterns = g.pats; end
            if ~isfield(g,'useRegex'), g.useRegex = false; end
            [nm, pt] = trimGroups(g.names, g.patterns);
            if isempty(nm)
                nm = "All"; pt = ".*";
            end
            groups = struct('names',nm(:).', 'patterns',pt(:).', 'useRegex',logical(g.useRegex));
        else
            % Legacy → build 1–2 groups if provided
            n = {}; p = {};
            if ~isempty(grpA_pat) && strlength(string(grpA_pat))>0, n{end+1}=string(grpA_name); p{end+1}=string(grpA_pat); end %#ok<AGROW>
            if ~isempty(grpB_pat) && strlength(string(grpB_pat))>0, n{end+1}=string(grpB_name); p{end+1}=string(grpB_pat); end %#ok<AGROW>
            if isempty(n), n = {"All"}; p = {".*"}; end
            groups = struct('names',string(n), 'patterns',string(p), 'useRegex',logical(useRegex));
        end
    end

    function [names, pats] = trimGroups(names, patterns)
        % Normalize & drop empties; return string row vectors
        names = string(names); patterns = string(patterns);
        keep = (strlength(strtrim(patterns))>0); % pattern must exist
        names = strtrim(names(keep));
        patterns = strtrim(patterns(keep));
        for i=1:numel(names)
            if names(i)=="", names(i) = "Group " + string(i); end
        end
        names = names(:).'; pats = patterns(:).';
    end

    function gi = classifyGroupIdx(fname, patterns, useRegex)
        % returns 0 if ambiguous or none
        gi = 0; hits = 0;
        patterns = cellstr(string(patterns));
        for i=1:numel(patterns)
            try
                if useRegex
                    hit = ~isempty(regexpi(fname, patterns{i}, 'once'));
                else
                    hit = contains(fname, patterns{i}, 'IgnoreCase',true);
                end
            catch
                hit = false;
            end
            if hit
                hits = hits + 1;
                if hits>1, gi = 0; return; end  % ambiguous
                gi = i;
            end
        end
    end

    function [Fout, mu_dB, sd_dB] = groupMeanSD_multi(C)
        Fout=[]; mu_dB=[]; sd_dB=[];
        if isempty(C), return; end
        Fout = C{1}.F(:);
        P = nan(numel(Fout), numel(C));
        for i=1:numel(C)
            Fi = C{i}.F(:); Pi = C{i}.Pxx_lin(:);
            if numel(Fi)==numel(Fout) && all(abs(Fi-Fout)<=1e-12)
                P(:,i)=Pi;
            end
        end
        X = 10*log10(P + eps);
        mu_dB = mean(X,2,'omitnan');
        sd_dB = std(X,0,2,'omitnan');
    end

    function y = meanSafeLocal(cellVec)
        % cellVec -> {vector} : returns mean across matched length
        if isempty(cellVec), y = []; return; end
        n = numel(cellVec{1}); M = nan(n, numel(cellVec));
        for i = 1:numel(cellVec)
            v = cellVec{i};
            if numel(v)==n, M(:,i)=v(:); end
        end
        y = mean(M,2,'omitnan');
    end

    function fill_between(x, y1, y2, rgb, alpha)
        p = fill([x(:); flipud(x(:))], [y1(:); flipud(y2(:))], rgb, 'EdgeColor','none');
        p.FaceAlpha = alpha;
    end

    function safe_exportgraphics(f, outP)
        try
            exportgraphics(f, outP, 'Resolution', 200);
        catch
            try, saveas(f, outP); catch, logmsg('Export failed: %s', outP); end
        end
    end

    function out = ternary(cond, a, b)
        % TERNARY — simple inline conditional
        % Usage:
        %   out = ternary(isREM,'on','off');
        %   out = ternary(flag, 1, 0);
        %
        % Notes:
        % - Designed for scalar logicals (typical for GUI properties).
        % - If you pass a non-scalar logical, it will broadcast `a`/`b` elementwise (basic support).

        if isscalar(cond)
            if cond, out = a; else, out = b; end
            return;
        end

        % Elementwise fallback for vectorized logicals
        if ischar(a) || isstring(a) || ischar(b) || isstring(b)
            % Strings/chars: build a string array
            out = strings(size(cond));
            out(:) = string(b);
            out(cond) = string(a);
            if ischar(a) && ischar(b)
                % If both were char, convert to char row if scalar, else leave string array
                if isscalar(cond), out = char(out); end
            end
        else
            % Numeric/other types
            out = repmat(b, size(cond));
            out(cond) = a;
        end
    end

    function b = parseBandList(s)
        % Accepts "low high" (spaces/commas). Returns sorted 1x2 row.
        a = regexp(strtrim(char(s)), '[,\s]+', 'split');
        a = str2double(a(~cellfun(@isempty,a)));
        if numel(a)~=2 || any(isnan(a)), error('Band must be two numbers: "low high".'); end
        b = sort(a(:)).';
    end

end





