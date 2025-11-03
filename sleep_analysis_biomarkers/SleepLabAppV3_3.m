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

        % varargin{1} optionally carries a struct:
        %   groups.names   : string/cellstr OR array of structs with .names
        %   groups.pats    OR groups.patterns
        %   groups.useRegex (optional, default=false)

        hasMulti = ~isempty(varargin) && isstruct(varargin{1});
        if hasMulti
            g = varargin{1};

            % ---- pull names (scalar or array) ----
            if ~isfield(g,'names')
                error('groups struct must include a "names" field.');
            end
            if numel(g) == 1
                names = string(g.names);
            else
                names = string({g.names});   % collect from struct array
            end

            % ---- pull patterns (support both "pats" and "patterns") ----
            if isfield(g,'pats')
                if numel(g) == 1, pats = string(g.pats); else, pats = string({g.pats}); end
            elseif isfield(g,'patterns')
                if numel(g) == 1, pats = string(g.patterns); else, pats = string({g.patterns}); end
            else
                error('groups struct must include "pats" or "patterns".');
            end

            % ---- useRegex (optional) ----
            if isfield(g,'useRegex')
                Gregex = logical(g.useRegex);
            else
                Gregex = false;
            end

            % ---- trim/keep only nonempty rows; force column cellstr ----
            names = strtrim(names);
            pats  = strtrim(pats);
            keep  = (strlength(names) > 0) & (strlength(pats) > 0);
            names = names(keep);
            pats  = pats(keep);

            Gnames = cellstr(names(:));
            Gpats  = cellstr(pats(:));
            nG     = numel(Gnames);

            if nG == 0
                error('No non-empty group name/pattern pairs provided.');
            end
        else
            % ---------- legacy 2-group mode ----------
            Gnames = {char(grpA_name), char(grpB_name)};
            Gpats  = {char(grpA_pat),  char(grpB_pat)};
            Gregex = useRegex;
            nG     = 2;
        end


        logmsg('PSD: fs=%g, epoch=%gs, BP=[%g %g], window=%d, overlap=%d, peak=%d', ...
            fs, epoch_sec, baseBP(1), baseBP(2), winN, ovN, usePeak);

        epoch_len = round(fs*epoch_sec);

        % EEG prefilter
        [b_eeg, a_eeg] = butter(4, baseBP/(fs/2), 'bandpass');

        lowcut   = 0.1;
        rem_gate = [4.8 9.8];
        nrem_gate= [0.8 4.8];

        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

        % ====== Allocate per-group buckets ======
        % For legacy A/B exports we still keep A/B containers.
        A_Wake={}; A_NREM={}; A_REM={};
        B_Wake={}; B_NREM={}; B_REM={};
        % For multi, dynamic cell arrays: Groups{g}.Wake/NREM/REM -> {mouse}
        Groups = cell(1,nG);
        for gi = 1:nG
            Groups{gi} = struct('Wake',{{}}, 'NREM',{{}}, 'REM',{{}});
        end

        for k = 1:numel(d)
            name = d(k).name;
            if any(strcmp(name, excluded)), logmsg('Skip excluded: %s', name); continue; end

            % ---- group assignment (multi or legacy) ----
            if hasMulti
                grp = classifyMulti(name, Gpats, Gregex);   % 1..nG or 0
            else
                grp = classifyGroup(name, grpA_pat, grpB_pat, useRegex); % legacy helper you already have
            end
            if grp==0
                logmsg('Unassigned (skip): %s', name);
                continue;
            end

            mdir = fullfile(root, name);

            % -------- Robust EEG discovery (pattern-aware with safe fallback) --------
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
            chosenEEG = fileList.name{1};
            EEG = extractBestEEGVector(fullfile(mdir, chosenEEG));
            if isempty(EEG) || numel(EEG) < fs   % require at least 1s
                logmsg('PSD: Could not extract valid EEG from %s; skipping.', chosenEEG);
                continue;
            end
            if isfield(meta,'fellBack') && meta.fellBack
                logmsg('PSD: EEG source: %s (fallback to auto-loader).', chosenEEG);
            else
                logmsg('PSD: EEG source: %s (matched user pattern).', chosenEEG);
            end

            % labels (required)
            labPath = fullfile(mdir,'labels.mat');
            if ~exist(labPath,'file')
                logmsg('PSD: Missing labels: %s', name); continue;
            end
            L = load(labPath);
            if ~isfield(L,'labels')
                logmsg('PSD: No "labels" var in %s', labPath); continue;
            end
            labels = L.labels(:).';

            % Prefilter
            try
                EEG = filtfilt(b_eeg, a_eeg, double(EEG));
            catch
                logmsg('PSD: Filter fail: %s', name); continue;
            end

            % Epoching
            num_epochs = floor(numel(EEG)/epoch_len);
            if num_epochs < 1, logmsg('PSD: Too short: %s', name); continue; end
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
                        logmsg('PSD: Freq grid mismatch in %s; epoch skipped.', name);
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

            % Per-mouse means (linear)
            M = struct(); ok=false;
            if acc_Wake_n>0, M.Wake.F=Fmask; M.Wake.Pxx_lin=acc_Wake_sum/acc_Wake_n; ok=true; end
            if acc_NREM_n>0, M.NREM.F=Fmask; M.NREM.Pxx_lin=acc_NREM_sum/acc_NREM_n; ok=true; end
            if acc_REM_n >0, M.REM.F =Fmask; M.REM.Pxx_lin =acc_REM_sum /acc_REM_n; ok=true; end
            if ~ok, logmsg('PSD: No accepted epochs in %s; skipping mouse.', name); continue; end

            % ---- Bucket by assigned group ----
            % Legacy A/B (kept for compatibility)
            if ~hasMulti
                if grp==1
                    if isfield(M,'Wake'), A_Wake{end+1}=M.Wake; end
                    if isfield(M,'NREM'), A_NREM{end+1}=M.NREM; end
                    if isfield(M,'REM'),  A_REM{end+1}=M.REM;  end
                elseif grp==2
                    if isfield(M,'Wake'), B_Wake{end+1}=M.Wake; end
                    if isfield(M,'NREM'), B_NREM{end+1}=M.NREM; end
                    if isfield(M,'REM'),  B_REM{end+1}=M.REM;  end
                end
            end

            % Multi-group dynamic buckets
            if hasMulti
                if isfield(M,'Wake'), Groups{grp}.Wake{end+1} = M.Wake; end
                if isfield(M,'NREM'), Groups{grp}.NREM{end+1} = M.NREM; end
                if isfield(M,'REM'),  Groups{grp}.REM{end+1}  = M.REM;  end
            end
        end

        % ---------- Legacy A/B path (unchanged outputs) ----------
        [F_A_W, mean_A_W_dB, sd_A_W_dB] = groupMeanSD(A_Wake);
        [F_B_W, mean_B_W_dB, sd_B_W_dB] = groupMeanSD(B_Wake);
        [F_A_N, mean_A_N_dB, sd_A_N_dB] = groupMeanSD(A_NREM);
        [F_B_N, mean_B_N_dB, sd_B_N_dB] = groupMeanSD(B_NREM);
        [F_A_R, mean_A_R_dB, sd_A_R_dB] = groupMeanSD(A_REM);
        [F_B_R, mean_B_R_dB, sd_B_R_dB] = groupMeanSD(B_REM);

        peakTxt = ternary(usePeak,'with','no');
        xl = xlimHz;

        % Plot helper (legacy pair)
        function plot_state(Fa,ma,sa,Fb,mb,sb,stName)
            if isempty(ma) && isempty(mb), return; end
            figure; hold on;
            if showSD
                if ~isempty(ma), fill_between(Fa, ma-sa, ma+sa, [0.75 0.85 1.0], 0.25); end
                if ~isempty(mb), fill_between(Fb, mb-sb, mb+sb, [1.0 0.8 0.8], 0.25); end
            end
            if ~isempty(ma), plot(Fa, ma, '-', 'LineWidth',1.6, 'Color',[0.0 0.35 0.8]); end
            if ~isempty(mb), plot(Fb, mb, '-', 'LineWidth',1.6, 'Color',[0.85 0.2 0.1]); end
            grid on; set(gca,'XScale','log'); xlim(xl);
            xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');
            title(sprintf('Mean PSD — %s (%s peak filter)', stName, peakTxt));
            leg = {};
            if ~isempty(ma), leg{end+1}=sprintf('%s mean', Gnames{1}); end
            if ~isempty(mb), leg{end+1}=sprintf('%s mean', ternary(numel(Gnames)>=2,Gnames{2},'B')); end
            if ~isempty(leg), legend(leg,'Location','best'); end
        end

        % Pair plots (A vs B) if at least one group has data
        plot_state(F_A_W, mean_A_W_dB, sd_A_W_dB, F_B_W, mean_B_W_dB, sd_B_W_dB, 'Wake');
        plot_state(F_A_N, mean_A_N_dB, sd_A_N_dB, F_B_N, mean_B_N_dB, sd_B_N_dB, 'NREM');
        plot_state(F_A_R, mean_A_R_dB, sd_A_R_dB, F_B_R, mean_B_R_dB, sd_B_R_dB, 'REM');

        % ========= Multi-group overlay plots & tidy export =========
        if hasMulti
            % Compute mean/sd per group for each state
            States = {'Wake','NREM','REM'};
            Colors = lines(max(7,nG)); % color palette
            rowsSD = {}; % accumulate tidy rows

            for si = 1:numel(States)
                st = States{si};
                figure; hold on; set(gca,'XScale','log'); grid on; xlim(xl);
                title(sprintf('Mean PSD — %s (%s peak filter)', st, peakTxt));
                xlabel('Frequency (Hz)'); ylabel('Power/Frequency (dB/Hz)');

                for gi = 1:nG
                    C = Groups{gi}.(st);
                    [Fout, mu, sdv] = groupMeanSD(C);
                    if isempty(mu), continue; end

                    if showSD
                        fill_between(Fout, mu-sdv, mu+sdv, Colors(gi,:), 0.20);
                    end
                    plot(Fout, mu, '-', 'LineWidth',1.6, 'Color', Colors(gi,:));
                    % tidy rows
                    rowsSD{end+1} = table( ...
                        repmat(string(Gnames{gi}),numel(Fout),1), ...
                        repmat(string(st),numel(Fout),1), ...
                        Fout(:), mu(:), sdv(:), ...
                        'VariableNames', {'Group','State','Frequency_Hz','Mean_dB','SD_dB'}); %#ok<AGROW>
                end
                legend(Gnames,'Interpreter','none','Location','best'); hold off;
            end

            % write tidy multi-group CSV
            try
                if ~isempty(rowsSD)
                    Tmulti = vertcat(rowsSD{:});
                    writetable(Tmulti, fullfile(root,'group_psd_summary_multi.csv'));
                end
            catch ME
                logmsg('PSD multi-group CSV export failed: %s', ME.message);
            end
        end

        % ---------- Save legacy MAT (kept as-is for compatibility) ----------
        save(fullfile(root,'group_psd_summary.mat'), ...
            'A_Wake','A_NREM','A_REM','B_Wake','B_NREM','B_REM', ...
            'F_A_W','mean_A_W_dB','F_B_W','mean_B_W_dB', ...
            'F_A_N','mean_A_N_dB','F_B_N','mean_B_N_dB', ...
            'F_A_R','mean_A_R_dB','F_B_R','mean_B_R_dB', ...
            'sd_A_W_dB','sd_B_W_dB','sd_A_N_dB','sd_B_N_dB','sd_A_R_dB','sd_B_R_dB', ...
            'fs','epoch_sec','usePeak','grpA_name','grpB_name','grpA_pat','grpB_pat','useRegex');

        logmsg('PSD: saved group_psd_summary.mat (with SD fields).');

        % ==================== CSV EXPORTS (legacy A/B) ====================
        try
            write_group_means_csv(fullfile(root,'group_psd_wake.csv'), F_A_W, mean_A_W_dB, F_B_W, mean_B_W_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
            write_group_means_csv(fullfile(root,'group_psd_nrem.csv'), F_A_N, mean_A_N_dB, F_B_N, mean_B_N_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
            write_group_means_csv(fullfile(root,'group_psd_rem.csv'),  F_A_R, mean_A_R_dB, F_B_R, mean_B_R_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));

            Tall = [
                packStateTable("Wake", F_A_W, mean_A_W_dB, F_B_W, mean_B_W_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
                packStateTable("NREM", F_A_N, mean_A_N_dB, F_B_N, mean_B_N_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
                packStateTable("REM",  F_A_R, mean_A_R_dB, F_B_R, mean_B_R_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'))
                ];
            if ~isempty(Tall)
                writetable(Tall, fullfile(root,'group_psd_summary_long.csv'));
            end

            write_group_means_sd_csv(fullfile(root,'group_psd_wake_with_sd.csv'), F_A_W, mean_A_W_dB, sd_A_W_dB, F_B_W, mean_B_W_dB, sd_B_W_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
            write_group_means_sd_csv(fullfile(root,'group_psd_nrem_with_sd.csv'), F_A_N, mean_A_N_dB, sd_A_N_dB, F_B_N, mean_B_N_dB, sd_B_N_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
            write_group_means_sd_csv(fullfile(root,'group_psd_rem_with_sd.csv'),  F_A_R, mean_A_R_dB, sd_A_R_dB, F_B_R, mean_B_R_dB, sd_B_R_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));

            TallSD = [
                packStateTableSD("Wake", F_A_W, mean_A_W_dB, sd_A_W_dB, F_B_W, mean_B_W_dB, sd_B_W_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
                packStateTableSD("NREM", F_A_N, mean_A_N_dB, sd_A_N_dB, F_B_N, mean_B_N_dB, sd_B_N_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'));
                packStateTableSD("REM",  F_A_R, mean_A_R_dB, sd_A_R_dB, F_B_R, mean_B_R_dB, sd_B_R_dB, Gnames{1}, ternary(numel(Gnames)>=2,Gnames{2},'B'))
                ];
            if ~isempty(TallSD)
                writetable(TallSD, fullfile(root,'group_psd_summary_with_sd_long.csv'));
            end

            logmsg('PSD: CSV exports written (with and without SD).');
        catch ME
            logmsg('CSV export failed: %s', ME.message);
        end
        % ================== END CSV EXPORTS ==================

        % ---------- local helpers ----------
        function g = classifyMulti(fname, patterns, useRx)
            g = 0;
            for ii = 1:numel(patterns)
                try
                    if useRx
                        hit = ~isempty(regexpi(fname, patterns{ii}, 'once'));
                    else
                        hit = contains(fname, patterns{ii}, 'IgnoreCase', true);
                    end
                catch
                    hit = false;
                end
                if hit
                    if g~=0
                        g = 0; return; % ambiguous → unassigned
                    else
                        g = ii;
                    end
                end
            end
        end
    end

% ---- helper: compute group mean + SD in dB (mouse-level) ----
    function [Fout, mean_dB, sd_dB] = groupMeanSD(C)
        Fout = []; mean_dB = []; sd_dB = [];
        if isempty(C), return; end
        Fout = C{1}.F(:);
        Pmat_lin = nan(numel(Fout), numel(C));
        for i = 1:numel(C)
            Fi = C{i}.F(:); Pi = C{i}.Pxx_lin(:);
            if numel(Fi)==numel(Fout) && all(abs(Fi - Fout) <= 1e-12)
                Pmat_lin(:,i) = Pi;
            end
        end
        X = 10*log10(Pmat_lin + eps);
        mean_dB = mean(X,2,'omitnan');
        sd_dB   = std(X,0,2,'omitnan');
    end

% ---- helper: write per-state group mean CSV (dB) (legacy: no SD) ----
    function write_group_means_csv(csvPath, F_A, A_dB, F_B, B_dB, nameA, nameB)
        if ~isempty(F_A), F = F_A(:);
        elseif ~isempty(F_B), F = F_B(:);
        else, return; end
        T = table(F, 'VariableNames', {'Frequency_Hz'});
        if ~isempty(A_dB), T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameA))) = A_dB(:); end
        if ~isempty(B_dB), T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameB))) = B_dB(:); end
        writetable(T, csvPath);
    end

% ---- helper: write per-state group mean+SD CSV (dB) ----
    function write_group_means_sd_csv(csvPath, F_A, A_dB, A_sd, F_B, B_dB, B_sd, nameA, nameB)
        if ~isempty(F_A), F = F_A(:);
        elseif ~isempty(F_B), F = F_B(:);
        else, return; end
        T = table(F, 'VariableNames', {'Frequency_Hz'});
        if ~isempty(A_dB)
            T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameA))) = A_dB(:);
            T.(matlab.lang.makeValidName(sprintf('%s_sd_dB',  nameA))) = A_sd(:);
        end
        if ~isempty(B_dB)
            T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameB))) = B_dB(:);
            T.(matlab.lang.makeValidName(sprintf('%s_sd_dB',  nameB))) = B_sd(:);
        end
        writetable(T, csvPath);
    end

% ---- helper: pack one state's table for the long CSV (legacy: no SD) ----
    function T = packStateTable(stateName, F_A, A_dB, F_B, B_dB, nameA, nameB)
        if isempty(F_A) && isempty(F_B), T = table(); return; end
        if ~isempty(F_A), F = F_A(:); else, F = F_B(:); end
        T = table(repmat(string(stateName), numel(F), 1), F, ...
            'VariableNames', {'State','Frequency_Hz'});
        if ~isempty(A_dB), T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameA))) = A_dB(:); end
        if ~isempty(B_dB), T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameB))) = B_dB(:); end
    end

% ---- helper: pack one state's table (with SD) ----
    function T = packStateTableSD(stateName, F_A, A_dB, A_sd, F_B, B_dB, B_sd, nameA, nameB)
        if isempty(F_A) && isempty(F_B), T = table(); return; end
        if ~isempty(F_A), F = F_A(:); else, F = F_B(:); end
        T = table(repmat(string(stateName), numel(F), 1), F, ...
            'VariableNames', {'State','Frequency_Hz'});
        if ~isempty(A_dB)
            T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameA))) = A_dB(:);
            T.(matlab.lang.makeValidName(sprintf('%s_sd_dB',  nameA))) = A_sd(:);
        end
        if ~isempty(B_dB)
            T.(matlab.lang.makeValidName(sprintf('%s_mean_dB',nameB))) = B_dB(:);
            T.(matlab.lang.makeValidName(sprintf('%s_sd_dB',  nameB))) = B_sd(:);
        end
    end

% ---- per-mouse CSV + shaded helper (unchanged) ----
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
                'VariableNames', {'Group','State','MouseIdx','Frequency_Hz','Pxx_dB'}); %#ok<AGROW>
            rows{end+1} = Ti; %#ok<AGROW>
        end
        if ~isempty(rows)
            Tout = vertcat(rows{:});
            outName = sprintf('per_mouse_psd_%s_%s.csv', lower(groupName), lower(stateName));
            writetable(Tout, fullfile(root, outName));
        end
    end

    function fill_between(x, y1, y2, rgb, alpha)
        p = fill([x(:); flipud(x(:))], [y1(:); flipud(y2(:))], rgb, 'EdgeColor','none');
        p.FaceAlpha = alpha;
    end

    function B = parseBandList(txt)
        % Accept "a b; c d; ..." or multi-line; return Nx2 double
        if isempty(strtrim(txt)), B = []; return; end
        s = strrep(txt, ';', newline);
        lines = regexp(s, '\r?\n', 'split');
        rows = [];
        for i=1:numel(lines)
            t = strtrim(lines{i}); if isempty(t), continue; end
            v = sscanf(t, '%f %f');
            if numel(v)~=2 || any(~isfinite(v)) || v(1)>=v(2)
                B = []; return;
            end
            rows(end+1,:) = v(:).'; %#ok<AGROW>
        end
        B = rows;
    end


%% ---------------------- INTERNAL: Theta-Gamma PAC --------------------------
function runPAC_Internal(root, fs, epoch_sec, codes, useManual, zthr, ...
        thetaHz, gammaHz, Nbins, excluded, doMI, doGroup, ...
        grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
        userEEGpat, userEEGisReg, ignorePats, varargin)

    % Optional multi-group config
    groups = [];
    if ~isempty(varargin), groups = varargin{1}; end
    multiMode = isstruct(groups) && isfield(groups,'names') && isfield(groups,'patterns');

    logmsg('PAC: fs=%g, epoch=%gs, theta=[%g %g], gamma=[%g %g], bins=%d, MI=%d', ...
        fs, epoch_sec, thetaHz(1), thetaHz(2), gammaHz(1), gammaHz(2), Nbins, doMI);

    resultsDir = fullfile(root, 'Theta-Gamma PAC Results');
    if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

    d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

    % --- Accumulators ---
    if multiMode
        [gNames, gPats] = trimGroups(groups.names, groups.patterns);
        G = initMultiCells(numel(gNames));
        G_MI = initMultiCells(numel(gNames));
    else
        A = {}; B = {};
        A_MI = {}; B_MI = {};
    end

    % Normalize A/B names early for titles, legend, filenames
    if iscell(grpA_name), grpA_name_s = char(string(strjoin(string(grpA_name), '_')));
    else, grpA_name_s = char(string(grpA_name)); end
    if iscell(grpB_name), grpB_name_s = char(string(strjoin(string(grpB_name), '_')));
    else, grpB_name_s = char(string(grpB_name)); end

    if doMI
        fp1 = 2:13; fp2 = 4:15;            % theta phase bands (~2 Hz width)
        fa1 = 28:1:98; fa2 = 30:1:100;     % gamma amp bands (2 Hz width)
        phaseCentersHz = fp1 + 1;
        ampCentersHz   = fa1 + 1;
    end

    epoch_len = round(fs*epoch_sec);

    for k = 1:numel(d)
        name = d(k).name;
        if any(strcmp(name, excluded)), logmsg('Skip excluded: %s', name); continue; end

        if multiMode
            grpIdx = classifyGroupIdx(name, gPats, groups.useRegex);
            if grpIdx==0, logmsg('Unassigned (skip): %s', name); continue; end
        else
            grp = classifyGroup(name, grpA_pat, grpB_pat, useRegex);
            if grp==0, logmsg('Unassigned (skip): %s', name); continue; end
        end

        mdir = fullfile(root,name);

        % --------- Build REM vector ----------
        if useManual
            remPath = fullfile(mdir,'REM_EEG_accusleep.mat');
            if ~exist(remPath,'file'), logmsg('PAC: No manual REM in %s', name); continue; end
            S = load(remPath);
            if ~isfield(S,'REM_EEG'), logmsg('PAC: Missing REM_EEG var in %s', remPath); continue; end
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
                logmsg('PAC: Could not extract valid EEG from %s; skipping.', eegChosen);
                continue;
            end
            labPath = fullfile(mdir,'labels.mat');
            if ~exist(labPath,'file'), logmsg('PAC: Missing labels in %s', name); continue; end
            L = load(labPath);
            if ~isfield(L,'labels'), logmsg('PAC: No labels in %s', labPath); continue; end
            labels = L.labels(:).';

            num_epochs = floor(numel(EEG)/epoch_len);
            if num_epochs<1, logmsg('PAC: Too short: %s', name); continue; end
            EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
            labels = labels(1:min(num_epochs,numel(labels)));
            EEG = EEG(:,1:numel(labels));

            REM_vec = cell2mat(arrayfun(@(e) EEG(:,e), find(labels==codes(2)), 'UniformOutput', false));
        end
        if isempty(REM_vec), logmsg('PAC: No REM samples in %s', name); continue; end

        % --------------------- Clean outliers ----------------------
        z = zscore(double(REM_vec));
        REM_vec(abs(z)>zthr) = NaN;
        REM_vec = fillmissing(REM_vec,'linear');

        % ================== PAC distribution =======================
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

        outdir = fullfile(mdir, 'new PAC'); if ~exist(outdir,'dir'), mkdir(outdir); end
        results.gamma_smoothed = gamma_smoothed;
        save(fullfile(outdir, sprintf('PAC Dist Data %d.mat',Nbins)), 'results');

        try
            Tmouse = table(centers(:), gamma_smoothed(:), ...
                'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
            writetable(Tmouse, fullfile(outdir, sprintf('PAC_Dist_%dbins.csv', Nbins)));
        catch ME
            logmsg('PAC per-mouse CSV failed (%s): %s', name, ME.message);
        end

        % ========================== MI map ============================
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
            save(fullfile(outdir, sprintf('MI data (%d bins).mat',Nbins)),'MI');

            try
                MItab = array2table(MI, 'VariableNames', ...
                    matlab.lang.makeValidName("theta_"+string(phaseCentersHz)+"Hz"));
                MItab = addvars(MItab, ampCentersHz(:), 'Before', 1, 'NewVariableNames','gammaAmp_Hz');
                writetable(MItab, fullfile(outdir, sprintf('MI_%dbins.csv', Nbins)));
            catch ME
                logmsg('PAC per-mouse MI CSV failed (%s): %s', name, ME.message);
            end

            % ---- Per-mouse MI heatmap export ----
            try
                f = figure('Visible','off');
                contourf(phaseCentersHz, ampCentersHz, MI, 120, 'linecolor','none');
                title(sprintf('Theta–Gamma MI — REM — %s', name), 'Interpreter','none');
                xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)'); colorbar;
                outPngMouse = fullfile(outdir, sprintf('MI_REM_%dbins.png', Nbins)); % define BEFORE try
                try
                    exportgraphics(f, outPngMouse, 'Resolution', 200);
                catch
                    saveas(f, outPngMouse);
                end
                close(f);
            catch ME
                logmsg('TG-PAC per-mouse MI heatmap export failed (%s): %s', name, ME.message);
            end
        end

        % ======================= Bucket to groups ==============================
        if multiMode
            G{grpIdx}{end+1} = gamma_smoothed(:);
            if doMI, G_MI{grpIdx}{end+1} = MI; end
        else
            if grp==1
                A{end+1} = gamma_smoothed(:);
                if doMI, A_MI{end+1} = MI; end
            elseif grp==2
                B{end+1} = gamma_smoothed(:);
                if doMI, B_MI{end+1} = MI; end
            end
        end
    end

    % ======================== Group mean distribution =========================
    edges   = linspace(0, 720, Nbins+1);
    centers = (edges(1:end-1) + edges(2:end))/2;

    if multiMode
        GM = cellfun(@(c) meanSafeLocal(c), G, 'UniformOutput', false); % local mean helper
        figure; hold on;
        for gi = 1:numel(GM)
            if ~isempty(GM{gi}), plot(centers, GM{gi}, 'LineWidth',1.6); end
        end
        xlabel('\theta phase (°)'); ylabel('Normalized \gamma amplitude');
        xlim([0 720]); xticks(0:90:720); grid on;
        title('Theta–Gamma PAC distribution (group means)');

        % Legend safe-normalization
        if iscell(gNames)
            legItems = cellfun(@(x) char(string(x)), gNames, 'UniformOutput', false);
        else
            legItems = cellstr(char(string(gNames)));
        end
        legend(legItems, 'Interpreter','none', 'Location','best');

        % ---- Save distribution plot (multi-group) ----
        outPngDist = fullfile(resultsDir, 'tgpac_group_distribution_REM.png'); % define BEFORE try
        try
            exportgraphics(gcf, outPngDist, 'Resolution', 200);
        catch
            saveas(gcf, outPngDist);
        end
        close(gcf);

        % ---- Multi-group CSV export ----
        try
            rows = cell(0,1);
            for gi = 1:numel(G)
                giCells = G{gi};
                for mi = 1:numel(giCells)
                    v = giCells{mi};
                    if isempty(v), continue; end
                    rows{end+1} = table( ...
                        repmat(string(gNames{gi}), numel(centers),1), ...
                        repmat(mi, numel(centers),1), ...
                        centers(:), v(:), ...
                        'VariableNames', {'Group','MouseIdx','ThetaPhase_deg','GammaNormAmp'});
                end
            end
            if ~isempty(rows), writetable(vertcat(rows{:}), fullfile(resultsDir,'pac_per_mouse_multi.csv')); end
        catch ME
            logmsg('PAC multi-group CSV export failed: %s', ME.message);
        end

        % ---- Group MI heatmaps ----
        if doMI && doGroup
            for gi = 1:numel(G_MI)
                if isempty(G_MI{gi}), continue; end
                MImean = mean(cat(3, G_MI{gi}{:}),3,'omitnan');

                f = figure('Visible','off');
                contourf(phaseCentersHz, ampCentersHz, MImean, 120, 'linecolor','none');
                title(sprintf('Theta–Gamma PAC — REM — Mean MI (%s)', char(string(gNames{gi}))), 'Interpreter','none');
                xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)'); colorbar;

                outPngGI = fullfile(resultsDir, sprintf('tgpac_mi_heatmap_REM_%s.png', lower(char(string(gNames{gi}))))); % BEFORE try
                try
                    exportgraphics(f, outPngGI, 'Resolution', 200);
                catch
                    saveas(f, outPngGI);
                end
                close(f);
            end
        end

    else
        % ===== Legacy A/B =====
        % ---- Compute Am/Bm safely ----
        if exist('gpac_meanSafe','file')
            Am = gpac_meanSafe(A);
            Bm = gpac_meanSafe(B);
        else
            if ~isempty(A), Am = mean(cat(3,A{:}),3,'omitnan'); else, Am = []; end
            if ~isempty(B), Bm = mean(cat(3,B{:}),3,'omitnan'); else, Bm = []; end
        end

        figure; hold on;
        if ~isempty(Am), plot(centers, Am, 'b','LineWidth',1.6); end
        if ~isempty(Bm), plot(centers, Bm, 'r','LineWidth',1.6); end
        xlabel('\theta phase (°)'); ylabel('Normalized \gamma amplitude');
        xlim([0 720]); xticks(0:90:720); grid on;

        title(sprintf('Theta–Gamma PAC distribution (group means: %s vs %s)', grpA_name_s, grpB_name_s), 'Interpreter','none');
        legend({grpA_name_s, grpB_name_s}, 'Location','best', 'Interpreter','none');

        % ---- Save A/B distribution plot ----
        outPngDistAB = fullfile(resultsDir, 'tgpac_group_distribution_REM.png'); % BEFORE try
        try
            exportgraphics(gcf, outPngDistAB, 'Resolution', 200);
        catch
            saveas(gcf, outPngDistAB);
        end
        close(gcf);

        % ---- CSV Exports (inline writer) ----
        write_per_mouse_pac_csv_safe(A, grpA_name_s, centers, fullfile(resultsDir, sprintf('pac_per_mouse_%s.csv', lower(grpA_name_s))));
        write_per_mouse_pac_csv_safe(B, grpB_name_s, centers, fullfile(resultsDir, sprintf('pac_per_mouse_%s.csv', lower(grpB_name_s))));

        % ---- A/B MI heatmaps ----
        if doMI && doGroup
            if ~isempty(A_MI)
                MImeanA = mean(cat(3, A_MI{:}),3,'omitnan');
                f = figure('Visible','off');
                contourf(phaseCentersHz, ampCentersHz, MImeanA, 120, 'linecolor','none');
                title(sprintf('Theta–Gamma PAC — REM — Mean MI (%s)', grpA_name_s), 'Interpreter','none');
                xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)'); colorbar;

                outPngA = fullfile(resultsDir, sprintf('tgpac_mi_heatmap_REM_%s.png', lower(grpA_name_s))); % BEFORE try
                try
                    exportgraphics(f, outPngA, 'Resolution', 200);
                catch
                    saveas(f, outPngA);
                end
                close(f);
            end
            if ~isempty(B_MI)
                MImeanB = mean(cat(3, B_MI{:}),3,'omitnan');
                f = figure('Visible','off');
                contourf(phaseCentersHz, ampCentersHz, MImeanB, 120, 'linecolor','none');
                title(sprintf('Theta–Gamma PAC — REM — Mean MI (%s)', grpB_name_s), 'Interpreter','none');
                xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)'); colorbar;

                outPngB = fullfile(resultsDir, sprintf('tgpac_mi_heatmap_REM_%s.png', lower(grpB_name_s))); % BEFORE try
                try
                    exportgraphics(f, outPngB, 'Resolution', 200);
                catch
                    saveas(f, outPngB);
                end
                close(f);
            end
        end
    end

    logmsg('PAC complete. Results written to %s', resultsDir);
end

% ======================= Local helpers (no external deps) ====================

function m = meanSafeLocal(cellVecs)
% cellVecs: 1xN cells of column vectors (same length). Returns column mean.
    if isempty(cellVecs), m = []; return; end
    try
        m = mean(cat(2, cellVecs{:}), 2, 'omitnan');
    catch
        % fallback for mismatched shapes: pad to max length with NaNs
        L = cellfun(@numel, cellVecs);
        Lmax = max(L);
        M = nan(Lmax, numel(cellVecs));
        for i = 1:numel(cellVecs)
            v = cellVecs{i};
            if isempty(v), continue; end
            M(1:numel(v), i) = v(:);
        end
        m = mean(M, 2, 'omitnan');
    end
end

function write_per_mouse_pac_csv_safe(C, groupName, centers, outPath)
% C: cell array where each cell is a PAC distribution vector (Nbinsx1)
% groupName: char/string for the cohort name
% centers: 1xNbins (or Nbinsx1) degrees centers
% outPath: full filename for CSV
    try
        if isempty(C), return; end
        rows = cell(0,1);
        for mi = 1:numel(C)
            v = C{mi};
            if isempty(v), continue; end
            rows{end+1} = table( ...
                repmat(string(groupName), numel(centers), 1), ...
                repmat(mi, numel(centers), 1), ...
                centers(:), v(:), ...
                'VariableNames', {'Group','MouseIdx','ThetaPhase_deg','GammaNormAmp'});
        end
        if ~isempty(rows)
            T = vertcat(rows{:});
            writetable(T, outPath);
        end
    catch ME
        logmsg('PAC per-mouse CSV export failed for %s: %s', string(groupName), ME.message);
    end
end



%% --------------------------- INTERNAL: HFD ---------------------------------
    function runHFD_Internal(root, fs, epoch_sec, baseBP, fsNew, firOrd, winSec, ovlSec, kmax, codes, excluded, groupOnly, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)
        % runHFD_Internal — robust to scalar/array group specs; auto 1–4 groups

        % ----------------------------- Group Config -----------------------------
        [gNames, gPats, gUseRegex] = normalizeGroupSpec(varargin, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex);
        nGroups = numel(gNames);
        if nGroups < 1
            gNames   = {'Group1'};
            gPats    = {'.*'};
            gUseRegex = true;
            nGroups  = 1;
        end
        gNames = fillEmptyNames(gNames); % ensure printable labels

        % ----------------------------- Logging & Setup --------------------------
        logmsg('HFD: fs=%g -> %g Hz, win=%.2fs, overlap=%.2fs, kmax=%d, aggregateOnly=%d', fs, fsNew, winSec, ovlSec, kmax, groupOnly);
        epoch_len  = round(fs*epoch_sec);
        resultsDir = fullfile(root, 'HFD Results');
        if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

        % Pre-filter FIR 0.5–70
        nyq = fs/2;
        bp = [max(0.5, baseBP(1)) min(70, baseBP(2))] / nyq;
        firCoeff = fir1(firOrd, bp, 'bandpass', hamming(firOrd+1));

        % States & label mapping (UI uses [Wake REM NREM])
        states   = {'Wake','NREM','REM'};
        codesMap = containers.Map(states, num2cell(codes([1 3 2])));

        % Iterate mice folders
        D = dir(root); D = D([D.isdir]); D = D(~ismember({D.name},{'.','..'}));

        % ======================= Per-mouse compute phase =========================
        if ~groupOnly
            for k = 1:numel(D)
                if exist('isStopRequested','file') && isStopRequested(), logmsg('HFD: stop requested.'); return; end

                name = D(k).name;
                if any(strcmp(name, excluded)), logmsg('Skip excluded: %s', name); continue; end

                % Group assignment (skip unassigned)
                gi = classifyGroupIdx_local(name, gPats, gUseRegex);
                if gi == 0, logmsg('Unassigned (skip compute): %s', name); continue; end

                mdir = fullfile(root, name);

                % -------- Robust EEG discovery (pattern-aware with safe fallback) --------
                [fileList, meta] = findEEGMatFiles(mdir, struct( ...
                    'userPattern',   userEEGpat, ...
                    'userIsRegex',   userEEGisReg, ...
                    'ignorePatterns',{ignorePats}, ...
                    'wantSides',     "any", ...
                    'allowNonEEG',   false));
                if isempty(fileList)
                    logmsg('HFD: No EEG .mat in %s (pattern="%s").', name, userEEGpat);
                    continue;
                end
                eegChosen = fileList.name{1};
                EEGraw = extractBestEEGVector(fullfile(mdir, eegChosen));
                if isempty(EEGraw) || numel(EEGraw) < fs
                    logmsg('HFD: Could not extract valid EEG from %s; skipping mouse.', eegChosen);
                    continue;
                end
                if isfield(meta,'fellBack') && meta.fellBack
                    logmsg('HFD: EEG source: %s (fallback to auto-loader).', eegChosen);
                else
                    logmsg('HFD: EEG source: %s (matched user pattern).', eegChosen);
                end

                % Labels (required)
                labPath = fullfile(mdir,'labels.mat');
                if ~exist(labPath,'file'), logmsg('HFD: Missing labels in %s', name); continue; end
                L = load(labPath); if ~isfield(L,'labels'), logmsg('HFD: No labels in %s', labPath); continue; end
                labels = L.labels(:).';

                % Pre-filter (FIR 0.5–70)
                try
                    EEGf = filtfilt(firCoeff, 1, double(EEGraw(:)));
                catch
                    logmsg('HFD: FIR filter failed (%s) — skipping mouse.', name);
                    continue;
                end

                % Epoching to align with labels
                num_epochs = floor(numel(EEGf)/epoch_len);
                if num_epochs < 1, logmsg('HFD: Too short: %s', name); continue; end
                EEGf   = reshape(EEGf(1:num_epochs*epoch_len), epoch_len, []);
                labels = labels(1:min(num_epochs,numel(labels)));
                EEGf   = EEGf(:, 1:numel(labels));

                % -------- HFD per state (windowed on downsampled epoch) --------
                FD_results = struct();
                for si = 1:numel(states)
                    st  = states{si}; code = codesMap(st);
                    idx = find(labels==code);
                    if isempty(idx), FD_results.(st).HFD = []; continue; end

                    HFD_vals = [];
                    for e = idx
                        if exist('isStopRequested','file') && isStopRequested(), logmsg('HFD: stop requested.'); return; end
                        epochSig = EEGf(:, e);

                        % anti-alias (Butter low-pass at fsNew/2), then resample
                        try
                            [b,a] = butter(4, (fsNew/2)/(fs/2), 'low');
                            ep_f  = filtfilt(b,a,epochSig);
                        catch
                            ep_f  = epochSig;
                        end
                        ep_ds = resample(ep_f, fsNew, fs);

                        wLen = round(winSec*fsNew);
                        step = max(1, wLen - round(ovlSec*fsNew));
                        if numel(ep_ds) < wLen, continue; end
                        nW = floor((numel(ep_ds) - wLen)/step) + 1;

                        for w = 1:nW
                            s = (w-1)*step + 1; eix = s + wLen - 1;
                            seg = ep_ds(s:eix);
                            N = numel(seg);
                            kmax_eff = min(kmax, floor(N/2)); if kmax_eff < 2, continue; end

                            % Higuchi length curve
                            Lm = zeros(kmax_eff,1);
                            for k2 = 1:kmax_eff
                                Lmk = 0; cnt = 0;
                                for j = 1:k2:N-k2+1
                                    if (j+k2) <= N
                                        Lmk = Lmk + abs(seg(j+k2)-seg(j));
                                        cnt = cnt + 1;
                                    end
                                end
                                if cnt>0
                                    Lm(k2) = (Lmk/cnt) * (N-1) / (k2^2);
                                else
                                    Lm(k2) = eps;
                                end
                            end
                            logL = log10(Lm + eps); logK = log10(1:kmax_eff);
                            p = polyfit(logK, logL.', 1);
                            HFD_vals(end+1,1) = abs(p(1)); %#ok<AGROW>
                        end
                    end
                    FD_results.(st).HFD = HFD_vals;
                end

                % Save per-mouse MAT
                save(fullfile(mdir,'FD_results.mat'),'FD_results');
                logmsg('HFD saved: %s', name);

                % Per-mouse CSV (long)
                try
                    rows = {};
                    for si = 1:numel(states)
                        st = states{si};
                        vals = FD_results.(st).HFD;
                        if isempty(vals), continue; end
                        rows{end+1} = table( ...
                            repmat(string(st), numel(vals),1), ...
                            repmat(string(name), numel(vals),1), ...
                            vals(:), ...
                            'VariableNames', {'State','MouseID','HFD'}); %#ok<AGROW>
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

        % Collectors
        G = initMultiStruct(states, nGroups);      % per state, per group → {mice}{vectors}
        perMouseRows = {};

        for k = 1:numel(mice)
            name = mice(k).name;
            if any(strcmp(name, excluded)), continue; end

            gi = classifyGroupIdx_local(name, gPats, gUseRegex);
            if gi == 0, continue; end

            fdPath = fullfile(root, name, 'FD_results.mat'); if ~exist(fdPath,'file'), continue; end
            S = load(fdPath); if ~isfield(S,'FD_results'), continue; end

            for st = string(states)
                vals = S.FD_results.(st).HFD;
                if isempty(vals), continue; end
                G.(st){gi}{end+1} = vals(:);

                perMouseRows{end+1} = table( ...
                    repmat(string(gNames{gi}), numel(vals),1), ...
                    repmat(st, numel(vals),1), ...
                    repmat(string(name), numel(vals),1), ...
                    (1:numel(vals)).', vals(:), ...
                    'VariableNames', {'Group','State','MouseID','SampleIdx','HFD'}); %#ok<AGROW>
            end
        end

        % -------- Build group tables + plots --------
        Tall = table(); Sums = table();

        % Long + summary tables
        for st = string(states)
            for gi = 1:nGroups
                if isempty(G.(st){gi}), continue; end
                vcat = vertcat(G.(st){gi}{:});
                if isempty(vcat), continue; end
                Tall = [Tall; table( ...
                    repmat(string(gNames{gi}), numel(vcat),1), ...
                    repmat(st, numel(vcat),1), ...
                    vcat, 'VariableNames', {'Group','State','HFD'})]; %#ok<AGROW>
                Sums = [Sums; table( ...
                    string(gNames{gi}), st, numel(vcat), mean(vcat), std(vcat), std(vcat)/sqrt(numel(vcat)), ...
                    'VariableNames', {'Group','State','N','Mean','Std','SEM'})]; %#ok<AGROW>
            end
        end

        % Plots: per state boxplot with any number of groups (safe labels)
        for st = string(states)
            labels = {}; values = [];
            for gi = 1:nGroups
                if isempty(G.(st){gi}), continue; end
                vcat = vertcat(G.(st){gi}{:});
                if isempty(vcat), continue; end
                values = [values; vcat(:)]; %#ok<AGROW>
                labels = [labels; repmat(gNames(gi), numel(vcat),1)]; %#ok<AGROW>
            end
            if ~isempty(values)
                figure('Name',sprintf('HFD: %s', st), 'Color','w');
                try
                    boxplot(values, categorical(labels), 'Colors','k','MedianStyle','line','Symbol','');
                    set(gca,'Box','off'); ylabel('Higuchi FD'); title(sprintf('HFD: %s', st));
                catch
                    plot(values,'.'); title(sprintf('HFD (fallback): %s', st)); ylabel('Higuchi FD'); grid on;
                end
            end
        end

        logmsg('HFD: grouping done.');

        % --------------------------- CSV exports ---------------------------------
        try
            if ~isempty(perMouseRows)
                writetable(vertcat(perMouseRows{:}), fullfile(resultsDir,'hfd_per_mouse_long.csv'));
            end
            if ~isempty(Tall), writetable(Tall, fullfile(resultsDir,'hfd_group_long.csv')); end
            if ~isempty(Sums), writetable(Sums, fullfile(resultsDir,'hfd_group_summary.csv')); end

            % Metadata
            fields = {'fs','epoch_sec','baseBP_low','baseBP_high','fsNew','firOrd','winSec','ovlSec','kmax','groupOnly','useRegex','userEEGpat','userEEGisReg','groups'};
            values = {fs, epoch_sec, baseBP(1), baseBP(2), fsNew, firOrd, winSec, ovlSec, kmax, logical(groupOnly), ...
                logical(gUseRegex), string(userEEGpat), logical(userEEGisReg), string(strjoin(gNames,'|'))};
            MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
            writetable(MF, fullfile(resultsDir, 'hfd_metadata.csv'));

            logmsg('HFD: CSV exports written.');
        catch ME
            logmsg('HFD CSV export failed: %s', ME.message);
        end
    end

% ============================== Local Helpers ===============================

    function [gNames, gPats, gUseRegex] = normalizeGroupSpec(vargs, grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex)
        % Accepts:
        %   vargs{1} possibly:
        %     - scalar struct with fields names, patterns, useRegex
        %     - struct ARRAY with the same fields
        %     - fields that can themselves be char/string/cellstr
        % Returns cellstr column vectors gNames, gPats and logical gUseRegex

        gUseRegex = logical(useRegex); % default from legacy
        if ~isempty(vargs) && isstruct(vargs{1})
            spec = vargs{1};
            if numel(spec) > 1
                % struct ARRAY → collect each element's names/patterns
                rawNames = arrayfun(@(s) s.names, spec, 'UniformOutput', false);
                rawPats  = arrayfun(@(s) s.patterns, spec, 'UniformOutput', false);
                gNames   = toCellstrFlat(rawNames);
                gPats    = toCellstrFlat(rawPats);
                if all(arrayfun(@(s) isfield(s,'useRegex'), spec))
                    gUseRegex = any(arrayfun(@(s) logical(s.useRegex), spec));
                end
            else
                % scalar struct
                gNames = toCellstrFlexible(spec.names);
                gPats  = toCellstrFlexible(spec.patterns);
                if isfield(spec,'useRegex'), gUseRegex = logical(spec.useRegex); end
            end
        else
            % Legacy A/B fallback
            gNames = toCellstrFlexible({grpA_name, grpB_name});
            gPats  = toCellstrFlexible({grpA_pat,  grpB_pat});
            gUseRegex = logical(useRegex);
        end

        % Trim & drop rows with BOTH empty
        [gNames, gPats] = trimGroups(gNames, gPats);
    end

    function C = toCellstrFlexible(x)
        % Convert char/string/cell-of-char/string to a *column* cellstr
        if iscell(x)
            tmp = cellfun(@(y) string(y), x, 'UniformOutput', false);
            C = cellstr(string([tmp{:}]'));
        elseif isstring(x)
            C = cellstr(x(:));
        elseif ischar(x)
            C = cellstr(string(x));
        else
            C = {}; % unknown → empty
        end
    end

    function C = toCellstrFlat(xcell)
        % xcell is a cell; each element may be char/string/cellstr
        C = {};
        for i = 1:numel(xcell)
            Ci = toCellstrFlexible(xcell{i});
            C  = [C; Ci(:)]; %#ok<AGROW>
        end
    end

    function gi = classifyGroupIdx_local(mouseName, pats, useRegex)
        % Return 0 if unassigned; otherwise 1..numel(pats)
        gi = 0;
        if isempty(pats), return; end
        for i = 1:numel(pats)
            pat = pats{i};
            if isempty(pat), continue; end
            if useRegex
                tf = ~isempty(regexp(mouseName, pat, 'once'));
            else
                tf = contains(mouseName, pat, 'IgnoreCase', true);
            end
            if tf, gi = i; return; end
        end
    end

    function names = fillEmptyNames(namesIn)
        % Ensure non-empty printable names (for legend/CSV); fill with Group# as needed
        names = namesIn;
        for i = 1:numel(names)
            s = strtrimSafe(names{i});
            if isempty(s)
                names{i} = sprintf('Group%d', i);
            else
                names{i} = s;
            end
        end
    end

    function [names, pats] = trimGroups(namesIn, patsIn)
        % Normalize to cellstr column vectors; drop rows where BOTH name & pattern are empty
        names = cellstr(string(namesIn(:)));
        pats  = cellstr(string(patsIn(:)));
        L = max(numel(names), numel(pats));
        if numel(names) < L, names(end+1:L) = {''}; end
        if numel(pats)  < L, pats(end+1:L)  = {''}; end

        mask = false(1, L);
        for i = 1:L
            names{i} = strtrimSafe(names{i});
            pats{i}  = strtrimSafe(pats{i});
            mask(i)  = ~(isempty(names{i}) && isempty(pats{i}));
        end
        names = names(mask);
        pats  = pats(mask);
    end

    function s = strtrimSafe(s)
        % Safe string/char trim that always returns a char row
        if isstring(s), s = char(s); end
        if isempty(s), s = ''; return; end
        s = strtrim(s);
    end

    function S = initMultiStruct(states, nGroups)
        % S.(state){gi} = {} cells collector
        for si = 1:numel(states)
            st = states{si};
            S.(st) = cell(1, nGroups);
            for gi = 1:nGroups, S.(st){gi} = {}; end
        end
    end


%% ------------------------ INTERNAL: Beta-Bursts ----------------------------
    function runBeta_Internal(root, fs, epoch_sec, codes, betaBand, thrPrct, excluded, xlimsAll, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)

        % Optional multi-group config (names, patterns, useRegex)
        groups    = [];
        multiMode = false;
        if ~isempty(varargin)
            groups    = varargin{1};
            multiMode = isstruct(groups) && isfield(groups,'names') && isfield(groups,'patterns');
        end

        % --- normalize group labels for plot titles (sprintf can't take cells) ---
        grpA_label = safeLabel(grpA_name);
        grpB_label = safeLabel(grpB_name);

        logmsg('Beta-Bursts: fs=%g, epoch=%gs, beta=[%g %g], thr=%gth pct', ...
            fs, epoch_sec, betaBand(1), betaBand(2), thrPrct);

        resultsDir = fullfile(root, 'Beta-Bursts Results');
        if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

        epoch_len = round(fs*epoch_sec);
        [b_beta, a_beta] = butter(4, betaBand/(fs/2), 'bandpass');
        wake_code = codes(1);

        d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

        % ---- Accumulators ----
        if multiMode
            [gNames, gPats] = trimGroups(groups.names, groups.patterns);
            G = struct('amp',{{}},'dur',{{}},'freq',{{}},'ibi',{{}},'ibiShort',{{}},'ibiLong',{{}});
            for gi = 1:numel(gNames)
                G.amp{gi} = []; G.dur{gi} = []; G.freq{gi} = []; G.ibi{gi} = []; G.ibiShort{gi} = []; G.ibiLong{gi} = [];
            end
        else
            A_amp=[]; A_dur=[]; A_freq=[]; A_ibi=[];
            B_amp=[]; B_dur=[]; B_freq=[]; B_ibi=[];
        end

        perMouseRows = {};

        for k = 1:numel(d)
            if exist('isStopRequested','file') && isStopRequested(), logmsg('Beta-Bursts: stop requested.'); return; end

            mouseName = d(k).name;
            if any(strcmp(mouseName, excluded)), logmsg('Skip excluded: %s', mouseName); continue; end

            if multiMode
                gi = classifyGroupIdx(mouseName, gPats, groups.useRegex);
                if gi==0, logmsg('Unassigned (skip): %s', mouseName); continue; end
                grpNameThis = gNames{gi};
            else
                grp = classifyGroup(mouseName, grpA_pat, grpB_pat, useRegex);
                if grp==0, logmsg('Unassigned (skip): %s', mouseName); continue; end
                grpNameThis = ternary(grp==1, grpA_label, grpB_label);
            end

            mdir   = fullfile(root, mouseName);
            labPath  = fullfile(mdir,'labels.mat');
            if ~exist(labPath,'file')
                logmsg('Missing labels in %s; skipping mouse.', mouseName);
                continue;
            end
            L = load(labPath);
            if ~isfield(L,'labels')
                logmsg('labels.mat exists but variable "labels" is missing in %s; skipping.', mouseName);
                continue;
            end
            labels = L.labels(:).';

            % ---------- Robust EEG discovery with L/R preference + safe fallback ----------
            EEG_R = []; EEG_L = []; eegSourceNote = "";

            % 1) Try explicit R/L files if present
            pathR  = fullfile(mdir,'EEG(R).mat');
            pathL  = fullfile(mdir,'EEG(L).mat');
            if exist(pathR,'file')
                SR = load(pathR); EEG_R = pickVecPreferMerged(SR);
            end
            if exist(pathL,'file')
                SL = load(pathL); EEG_L = pickVecPreferMerged(SL);
            end

            % 2) If either side missing, try pattern-aware discovery
            if isempty(EEG_R) || isempty(EEG_L)
                [fileList, meta] = findEEGMatFiles(mdir, struct( ...
                    'userPattern',   userEEGpat, ...
                    'userIsRegex',   userEEGisReg, ...
                    'ignorePatterns',{ignorePats}, ...
                    'wantSides',     "any", ...
                    'allowNonEEG',   false));
                if ~isempty(fileList)
                    sideGuess = lower(strjoin(fileList.name,'|'));
                    tryR = contains(sideGuess, {'(r)','_r',' right','-r',' r.'});
                    tryL = contains(sideGuess, {'(l)','_l',' left','-l',' l.'});

                    vecs = {};
                    for i=1:min(2,height(fileList))
                        v = extractBestEEGVector(fullfile(mdir, fileList.name{i}));
                        if ~isempty(v), vecs{end+1} = v; end %#ok<AGROW>
                    end
                    if isempty(EEG_R) && ~isempty(vecs)
                        if any(tryR), EEG_R = vecs{find(tryR,1,'first')}; else, EEG_R = vecs{1}; end
                    end
                    if isempty(EEG_L) && numel(vecs) >= 2
                        if any(tryL), EEG_L = vecs{find(tryL,1,'first')}; else, EEG_L = vecs{2}; end
                    end

                    if isfield(meta,'fellBack') && meta.fellBack
                        eegSourceNote = "(fallback to auto-loader)";
                    else
                        eegSourceNote = "(matched user pattern)";
                    end
                end
            end

            % 3) Validate extracted signals / single-channel fallback
            if isempty(EEG_R) && isempty(EEG_L)
                logmsg('No usable EEG found in %s %s', mouseName, eegSourceNote);
                continue;
            end

            if ~isempty(EEG_R) && ~isempty(EEG_L)
                len = min(numel(EEG_R), numel(EEG_L));
                EEG_R = double(EEG_R(1:len)); EEG_L = double(EEG_L(1:len));
                EEG_use_raw = mean([EEG_R(:).'; EEG_L(:).'], 1);
                logmsg('Beta-Bursts EEG source in %s: averaged L+R %s', mouseName, eegSourceNote);
            else
                one = double((~isempty(EEG_R))*EEG_R + (~isempty(EEG_L))*EEG_L);
                EEG_use_raw = one(:).';
                logmsg('Beta-Bursts EEG source in %s: single-channel (%s) %s', ...
                    mouseName, ternary(~isempty(EEG_R),'R','L'), eegSourceNote);
            end

            % --------- Align to labels & Wake mask ----------
            num_epochs = floor(numel(EEG_use_raw)/epoch_len);
            if num_epochs < 1, logmsg('Too short recording in %s; skipping.', mouseName); continue; end

            labels = labels(1:min(num_epochs, numel(labels)));
            num_epochs = numel(labels);
            N_use  = num_epochs * epoch_len;
            EEG_use = EEG_use_raw(1:N_use);

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

            % --------- Filter, envelope, bursts ----------
            try
                beta_sig   = filtfilt(b_beta, a_beta, EEG_use);
            catch
                logmsg('Filtering failed in %s; skipping.', mouseName); continue;
            end
            beta_power = abs(hilbert(beta_sig)).^2;

            thr = prctile(beta_power(wakeMask), thrPrct);
            isBurst = (beta_power > thr) & wakeMask;

            dB = diff([false, isBurst, false]);
            onsets  = find(dB ==  1);
            offsets = find(dB == -1) - 1;

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
                        dt = (s - offsets(iB-1)) / fs;
                        IBI_all(end+1,1) = dt;

                        gapMask = wakeMask(offsets(iB-1)+1 : s-1);
                        if ~isempty(gapMask) && all(gapMask)
                            IBI_withinWake(end+1,1) = dt;
                        end
                    end
                end
            end

            S = struct();
            S.burst_duration  = burst_duration;
            S.burst_amplitude = burst_amplitude;
            S.burst_frequency = burst_frequency;
            S.IBI             = IBI_withinWake;
            S.IBI_all         = IBI_all;
            T = padToTableLikeOriginal(S);

            save(fullfile(mdir,'beta-bursts features.mat'),'T');
            try, writetable(T, fullfile(mdir,'beta-bursts features.xlsx')); end
            logmsg('Saved features in %s (n=%d)', mouseName, height(T));

            outdirMouse = fullfile(mdir, 'Beta-Bursts');
            if ~exist(outdirMouse,'dir'), mkdir(outdirMouse); end
            try
                writetable(T, fullfile(outdirMouse, 'beta_bursts_features.csv'));
            catch ME
                logmsg('Per-mouse CSV failed in %s: %s', mouseName, ME.message);
            end

            % ---- Aggregate to groups ----
            if multiMode
                G.amp{gi}  = [G.amp{gi};  T.burst_amplitude];
                G.dur{gi}  = [G.dur{gi};  T.burst_duration];
                G.freq{gi} = [G.freq{gi}; T.burst_frequency];
                G.ibi{gi}  = [G.ibi{gi};  T.IBI];
            else
                if grp==1
                    A_amp = [A_amp; T.burst_amplitude];
                    A_dur = [A_dur; T.burst_duration];
                    A_freq= [A_freq; T.burst_frequency];
                    A_ibi = [A_ibi; T.IBI];
                elseif grp==2
                    B_amp = [B_amp; T.burst_amplitude];
                    B_dur = [B_dur; T.burst_duration];
                    B_freq= [B_freq; T.burst_frequency];
                    B_ibi = [B_ibi; T.IBI];
                end
            end

            % ---- Per-mouse long rows ----
            perMouseRows{end+1} = table( ...
                repmat(string(grpNameThis), numel(T.burst_amplitude),1), repmat(string(mouseName), numel(T.burst_amplitude),1), ...
                repmat("Amplitude", numel(T.burst_amplitude),1), T.burst_amplitude, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            perMouseRows{end+1} = table( ...
                repmat(string(grpNameThis), numel(T.burst_duration),1), repmat(string(mouseName), numel(T.burst_duration),1), ...
                repmat("Duration_s", numel(T.burst_duration),1), T.burst_duration, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            perMouseRows{end+1} = table( ...
                repmat(string(grpNameThis), numel(T.burst_frequency),1), repmat(string(mouseName), numel(T.burst_frequency),1), ...
                repmat("Frequency_Hz", numel(T.burst_frequency),1), T.burst_frequency, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            perMouseRows{end+1} = table( ...
                repmat(string(grpNameThis), numel(T.IBI),1), repmat(string(mouseName), numel(T.IBI),1), ...
                repmat("IBI_s", numel(T.IBI),1), T.IBI, ...
                'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            if ismember('IBI_all', T.Properties.VariableNames)
                perMouseRows{end+1} = table( ...
                    repmat(string(grpNameThis), numel(T.IBI_all),1), repmat(string(mouseName), numel(T.IBI_all),1), ...
                    repmat("IBI_all_s", numel(T.IBI_all),1), T.IBI_all, ...
                    'VariableNames', {'Group','MouseID','Metric','Value'}); %#ok<AGROW>
            end
        end

        % --------------------- Group CDF plots ----------------------
        if multiMode
            plotCDF_multi(G.amp,  gNames, sprintf('Amplitude (%s)', strjoin(gNames,' vs ')),        xlimsAll.amp);
            plotCDF_multi(G.dur,  gNames, sprintf('Duration (s) (%s)', strjoin(gNames,' vs ')),     xlimsAll.dur);
            plotCDF_multi(G.freq, gNames, sprintf('Frequency (Hz) (%s)', strjoin(gNames,' vs ')),   xlimsAll.freq);
            plotCDF_multi(G.ibi,  gNames, sprintf('IBI (s) (%s)', strjoin(gNames,' vs ')),          xlimsAll.ibi);
            % short/long IBI visual splits:
            plotCDF_multi(cellfun(@(v)v(v<0.05), G.ibi,'uni',0), gNames, sprintf('short IBI (< 50 ms) (%s)', strjoin(gNames,' vs ')), xlimsAll.ibiShort);
            plotCDF_multi(cellfun(@(v)v(v>0.2),  G.ibi,'uni',0), gNames, sprintf('long IBI (> 200 ms) (%s)',  strjoin(gNames,' vs ')), xlimsAll.ibiLong);
        else
            plotCDF_likeScript(A_amp,B_amp,  sprintf('Amplitude (%s vs %s)',      grpA_label, grpB_label), xlimsAll.amp);
            plotCDF_likeScript(A_dur,B_dur,  sprintf('Duration (s) (%s vs %s)',   grpA_label, grpB_label), xlimsAll.dur);
            plotCDF_likeScript(A_freq,B_freq,sprintf('Frequency (Hz) (%s vs %s)', grpA_label, grpB_label), xlimsAll.freq);
            plotCDF_likeScript(A_ibi,B_ibi,  sprintf('IBI (s) (%s vs %s)',        grpA_label, grpB_label), xlimsAll.ibi);
            plotCDF_likeScript(A_ibi(A_ibi<0.05), B_ibi(B_ibi<0.05),  sprintf('short IBI (< 50 ms) (%s vs %s)', grpA_label, grpB_label), xlimsAll.ibiShort);
            plotCDF_likeScript(A_ibi(A_ibi>0.2),  B_ibi(B_ibi>0.2),   sprintf('long IBI (> 200 ms) (%s vs %s)',  grpA_label, grpB_label), xlimsAll.ibiLong);
        end

        % ---------------------------- Exports -----------------------------------
        try
            if ~isempty(perMouseRows)
                writetable(vertcat(perMouseRows{:}), fullfile(resultsDir, 'beta_bursts_per_mouse_long.csv'));
            end

            if multiMode
                Gtab = table(); Sums = table();
                metrics = {'Amplitude','Duration_s','Frequency_Hz','IBI_s'};
                fields  = {'amp','dur','freq','ibi'};
                for fi = 1:numel(fields)
                    f = fields{fi}; metric = metrics{fi};
                    for gi = 1:numel(gNames)
                        vals = G.(f){gi};
                        if isempty(vals), continue; end
                        Gtab = [Gtab; table(repmat(string(gNames{gi}),numel(vals),1), repmat(string(metric),numel(vals),1), vals(:), ...
                            'VariableNames', {'Group','Metric','Value'})]; %#ok<AGROW>
                        Sums = [Sums; summarizeMetric(gNames{gi}, metric, vals)]; %#ok<AGROW>
                    end
                end
                if ~isempty(Gtab), writetable(Gtab, fullfile(resultsDir, 'beta_bursts_group_long.csv')); end
                if ~isempty(Sums), writetable(Sums, fullfile(resultsDir, 'beta_bursts_group_summary.csv')); end

                fieldsM = {'fs','epoch_sec','beta_low','beta_high','thrPrct','wake_code','groups','useRegex','userEEGpat','userEEGisReg'};
                valuesM = {fs, epoch_sec, betaBand(1), betaBand(2), thrPrct, wake_code, string(strjoin(gNames,'|')), logical(groups.useRegex), string(userEEGpat), logical(userEEGisReg)};
                MF = table(string(fieldsM(:)), string(valuesM(:)), 'VariableNames', {'Field','Value'});
                writetable(MF, fullfile(resultsDir, 'beta_bursts_metadata.csv'));
            else
                G = table();
                if ~isempty(A_amp),  G = [G; table(repmat(string(grpA_label),numel(A_amp),1),  repmat("Amplitude",numel(A_amp),1),  A_amp,  'VariableNames', {'Group','Metric','Value'})]; end
                if ~isempty(B_amp),  G = [G; table(repmat(string(grpB_label),numel(B_amp),1),  repmat("Amplitude",numel(B_amp),1),  B_amp,  'VariableNames', {'Group','Metric','Value'})]; end
                if ~isempty(A_dur),  G = [G; table(repmat(string(grpA_label),numel(A_dur),1),  repmat("Duration_s",numel(A_dur),1),  A_dur,  'VariableNames', {'Group','Metric','Value'})]; end
                if ~isempty(B_dur),  G = [G; table(repmat(string(grpB_label),numel(B_dur),1),  repmat("Duration_s",numel(B_dur),1),  B_dur,  'VariableNames', {'Group','Metric','Value'})]; end
                if ~isempty(A_freq), G = [G; table(repmat(string(grpA_label),numel(A_freq),1), repmat("Frequency_Hz",numel(A_freq),1), A_freq, 'VariableNames', {'Group','Metric','Value'})]; end
                if ~isempty(B_freq), G = [G; table(repmat(string(grpB_label),numel(B_freq),1), repmat("Frequency_Hz",numel(B_freq),1), B_freq, 'VariableNames', {'Group','Metric','Value'})]; end
                if ~isempty(A_ibi),  G = [G; table(repmat(string(grpA_label),numel(A_ibi),1),  repmat("IBI_s",numel(A_ibi),1),       A_ibi,  'VariableNames', {'Group','Metric','Value'})]; end
                if ~isempty(B_ibi),  G = [G; table(repmat(string(grpB_label),numel(B_ibi),1),  repmat("IBI_s",numel(B_ibi),1),       B_ibi,  'VariableNames', {'Group','Metric','Value'})]; end

                if ~isempty(G)
                    writetable(G, fullfile(resultsDir, 'beta_bursts_group_long.csv'));
                end

                Sums = table();
                Sums = [Sums; summarizeMetric(grpA_label,"Amplitude",A_amp);     summarizeMetric(grpB_label,"Amplitude",B_amp)];
                Sums = [Sums; summarizeMetric(grpA_label,"Duration_s",A_dur);    summarizeMetric(grpB_label,"Duration_s",B_dur)];
                Sums = [Sums; summarizeMetric(grpA_label,"Frequency_Hz",A_freq); summarizeMetric(grpB_label,"Frequency_Hz",B_freq)];
                Sums = [Sums; summarizeMetric(grpA_label,"IBI_s",A_ibi);         summarizeMetric(grpB_label,"IBI_s",B_ibi)];
                if ~isempty(Sums)
                    writetable(Sums, fullfile(resultsDir, 'beta_bursts_group_summary.csv'));
                end

                fields = {'fs','epoch_sec','beta_low','beta_high','thrPrct','wake_code','GroupA','GroupB','patA','patB','useRegex','userEEGpat','userEEGisReg'};
                values = {fs, epoch_sec, betaBand(1), betaBand(2), thrPrct, wake_code, string(grpA_label), string(grpB_label), string(grpA_pat), string(grpB_pat), logical(useRegex), string(userEEGpat), logical(userEEGisReg)};
                MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
                writetable(MF, fullfile(resultsDir, 'beta_bursts_metadata.csv'));
            end

            logmsg('Beta-Bursts: CSV exports written.');
        catch ME
            logmsg('Beta-Bursts CSV export failed: %s', ME.message);
        end

        logmsg('Beta-Bursts: done.');
    end

    function T = summarizeMetric(grp, metric, vals)
        if isempty(vals)
            T = table(); return;
        end
        n = numel(vals);
        mu = mean(vals); sd = std(vals); sem = sd/sqrt(n);
        T = table(repmat(string(grp),1,1), repmat(string(metric),1,1), n, mu, sd, sem, ...
            'VariableNames', {'Group','Metric','N','Mean','Std','SEM'});
    end

% ========================= Local helpers (multi-group) ======================

% Multi-group CDF plotter
    function plotCDF_multi(cellVals, groupNames, ttl, xlims)
        figure; hold on; grid on;
        for i = 1:numel(cellVals)
            v = cellVals{i};
            if isempty(v), continue; end
            v = v(~isnan(v) & isfinite(v));
            if isempty(v), continue; end
            v = sort(v(:));
            y = (1:numel(v))'/numel(v);
            plot(v, y, 'LineWidth', 1.6);
        end
        if ~isempty(xlims), try, xlim(xlims); end, end
        ylim([0 1]); xlabel('Value'); ylabel('CDF'); title(ttl);
        if ~isempty(groupNames)
            legend(groupNames, 'Location','best');
        end
    end

% Tiny helpers used above
    function out = ternary(cond,a,b)
        if cond, out=a; else, out=b; end
    end

    function s = safeLabel(x)
        % Accept char, string, or cell; return a char for sprintf/titles
        if iscell(x)
            if isempty(x)
                s = 'Group';
                return;
            end
            x = x{1};
        end
        if isstring(x)
            x = char(x);
        end
        if isempty(x)
            s = 'Group';
        else
            s = x;
        end
    end


%% --------------- INTERNAL: MDF/SEF/Peak from RAW EEG (multi-group) ---------------
    function runMDFSEF_Internal(root, fs, epoch_sec, codes, bp, winN, ovN, sefPerc, doGate, mode, excluded, autoCompute, ...
            grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
            userEEGpat, userEEGisReg, ignorePats, varargin)
        % Backward-compatible:
        % - Legacy A/B behavior when 'groups' (varargin{1}) is not provided.
        % - Multi-group (1–4) when groups struct is provided:
        %     groups = struct('names', {'WT','DS','HET'}, 'patterns', {' WT ',' DS ',' HET '}, 'useRegex', false)

        % ---------- Optional multi-group config ----------
        groups    = [];
        multiMode = false;
        if ~isempty(varargin)
            groups    = varargin{1};
            multiMode = isstruct(groups) && isfield(groups,'names') && isfield(groups,'patterns');
        end
        if multiMode
            [gNames, gPats] = trimGroups(groups.names, groups.patterns);
            gUseRegex = isfield(groups,'useRegex') && logical(groups.useRegex);
            % 🔒 Normalize display labels: TRIM + UPPERCASE (as requested)
            gNames = cellfun(@safeLabel, gNames, 'uni', false);
        end

        % 🔒 Normalize A/B labels up-front (TRIM + UPPERCASE, always char)
        grpA_name = safeLabel(grpA_name, 'GROUP A');
        grpB_name = safeLabel(grpB_name, 'GROUP B');

        logmsg('MDF/SEF/Peak: fs=%g, epoch=%gs, BP=[%g %g], win=%d, ov=%d, SEF=%.2f, gate=%d, mode=%s', ...
            fs, epoch_sec, bp(1), bp(2), winN, ovN, sefPerc, doGate, mode);

        resultsDir = fullfile(root, 'MDF-SEF-Peak Results');
        if ~exist(resultsDir, 'dir'), mkdir(resultsDir); end

        epoch_len = round(fs*epoch_sec);
        nfft = 2*winN;
        [b_bp, a_bp] = butter(4, bp/(fs/2), 'bandpass');

        % ======================== PER-MOUSE (runs over all mice) ========================
        if any(strcmp(mode, {'per','both'}))
            d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
            for k = 1:numel(d)
                if exist('isStopRequested','file') && isStopRequested(), logmsg('MDF/SEF/Peak: stop requested.'); return; end

                name = d(k).name;
                if any(strcmp(name, excluded)), logmsg('Excluded: %s', name); continue; end

                % --- Group detection (legacy A/B or multi) ---
                if multiMode
                    gi = classifyGroupIdx(name, gPats, gUseRegex);
                    if gi==0, logmsg('Unassigned (per-mouse skip): %s', name); continue; end
                    grp = gi;                              % keep numeric for plot title
                    grpLabel = gNames{gi};                 % already normalized
                else
                    grp = classifyGroup(name, grpA_pat, grpB_pat, useRegex);
                    if grp==0, logmsg('Unassigned (per-mouse skip): %s', name); continue; end
                    grpLabel = ternary(grp==1, grpA_name, grpB_name);
                end

                mdir = fullfile(root,name);

                % ---- Labels ----
                labPath = fullfile(mdir,'labels.mat');
                if ~exist(labPath,'file'), logmsg('Missing labels.mat in %s — skipping mouse.', name); continue; end
                L = load(labPath);
                labels = tryPickLabels(L);
                if isempty(labels), logmsg('labels missing/invalid in %s — skipping mouse.', name); continue; end

                % ---- Robust EEG discovery (prefers EEG_accusleep, else pattern/fallback) ----
                EEG = [];
                eegPath = fullfile(mdir,'EEG_accusleep.mat');
                if exist(eegPath,'file')
                    Sraw = load(eegPath);
                    if isfield(Sraw,'EEG') && isvector(Sraw.EEG), EEG = double(Sraw.EEG(:)); end
                end
                eegSourceNote = "EEG_accusleep";
                if isempty(EEG)
                    [fileList, meta] = findEEGMatFiles(mdir, struct( ...
                        'userPattern',   userEEGpat, ...
                        'userIsRegex',   userEEGisReg, ...
                        'ignorePatterns',{ignorePats}, ...
                        'wantSides',     "any", ...
                        'allowNonEEG',   false));
                    if isempty(fileList)
                        logmsg('No EEG .mat found in %s (pattern="%s").', name, userEEGpat);
                        continue;
                    end
                    EEG = extractBestEEGVector(fullfile(mdir, fileList.name{1}));
                    eegSourceNote = string(fileList.name{1});
                    if isfield(meta,'fellBack') && meta.fellBack, eegSourceNote = eegSourceNote + " (fallback)"; end
                    if isempty(EEG) || numel(EEG) < fs
                        logmsg('Could not extract valid EEG in %s; skipping.', name); continue;
                    end
                end

                % Filter & epoch
                try
                    EEGf = filtfilt(b_bp,a_bp,EEG);
                catch
                    EEGf = EEG; logmsg('Filter failed in %s — using raw.', name);
                end

                num_epochs = floor(numel(EEGf)/epoch_len);
                if num_epochs<1, logmsg('Too short recording in %s — skipping.', name); continue; end
                labels = labels(1:min(num_epochs, numel(labels)));
                num_epochs = numel(labels);
                EEGf = EEGf(1:num_epochs*epoch_len);
                EEGf = reshape(EEGf, epoch_len, []);

                % Compute per-state metrics
                Sres = compute_MDF_SEF_Peak_per_state(EEGf, labels, codes, fs, winN, ovN, nfft, sefPerc);

                % Optional peak-frequency gating
                if doGate
                    Sres = apply_peak_gating(Sres);
                end

                % Save beside EEG (keeps original filename key)
                outPath = fullfile(mdir,'SeF_MDF_data.mat');
                S = Sres; %#ok<NASGU>
                save(outPath,'S');
                logmsg('Saved per-mouse MDF/SEF/Peak: %s (EEG source: %s)', outPath, eegSourceNote);

                % Per-mouse CSV export (long)
                try
                    perMouseDir = fullfile(mdir, 'MDF-SEF-Peak');
                    if ~exist(perMouseDir,'dir'), mkdir(perMouseDir); end
                    Tpm = per_mouse_vectors_long(Sres);  % State, Metric, Value
                    if ~isempty(Tpm)
                        writetable(Tpm, fullfile(perMouseDir, sprintf('mdf_sef_peak_per_mouse_%s.csv', name)));
                    end
                catch ME
                    logmsg('Per-mouse CSV export failed (%s): %s', name, ME.message);
                end

                % Per-mouse quick figure (means per state), include mouse ID + group
                try
                    M = per_mouse_means(Sres);
                    figure; hold on;
                    statesLab = {'Wake','NREM','REM'};
                    muMDF = [M.wake.mdf,  M.nrem.mdf,  M.rem.mdf ];
                    muSEF = [M.wake.sef,  M.nrem.sef,  M.rem.sef ];
                    muPK  = [M.wake.peak, M.nrem.peak, M.rem.peak];
                    x = 1:3;
                    bar(x-0.22, muMDF, 0.2,'FaceColor',[0.3 0.6 1]);    % MDF
                    bar(x      , muSEF, 0.2,'FaceColor',[0.8 0.5 0.2]); % SEF
                    bar(x+0.22, muPK , 0.2,'FaceColor',[0.2 0.7 0.4]);  % Peak
                    set(gca,'XTick',x,'XTickLabel',statesLab);
                    ylabel('Frequency (Hz)');
                    title(sprintf('MDF/SEF/Peak — %s (%s)', name, grpLabel));
                    legend({'MDF','SEF','Peak'},'Location','best'); grid on; hold off;
                catch
                end

                % Mouse-level metadata (best-effort)
                try
                    MFmouse = table( ...
                        string(name), string(grpLabel), string(eegSourceNote), ...
                        fs, epoch_sec, bp(1), bp(2), winN, ovN, nfft, sefPerc, logical(doGate), ...
                        'VariableNames', {'MouseID','Group','EEGSource','fs','epoch_sec','bp_low','bp_high','winN','ovN','nfft','sefPerc','doGate'});
                    if ~exist(fullfile(mdir,'MDF-SEF-Peak'),'dir'), mkdir(fullfile(mdir,'MDF-SEF-Peak')); end
                    writetable(MFmouse, fullfile(mdir,'MDF-SEF-Peak','mdf_sef_peak_metadata_mouse.csv'));
                catch, end
            end
        end

        % ======================== GROUP AGGREGATION ========================
        if any(strcmp(mode, {'group','both'}))
            if ~isfolder(root), logmsg('Root folder not set or invalid.'); return; end
            d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));

            if multiMode
                % Dynamic bins per group
                Gbins = init_multi_bins(numel(gNames));
            else
                A = init_group_bin(); B = init_group_bin();
            end
            perMouseRows = {};

            for k=1:numel(d)
                if exist('isStopRequested','file') && isStopRequested(), logmsg('MDF/SEF/Peak: stop requested.'); return; end
                name = d(k).name;
                if any(strcmp(name, excluded)), logmsg('Excluded: %s', name); continue; end
                mdir = fullfile(root,name);

                % --- Group detection & label ---
                if multiMode
                    gi = classifyGroupIdx(name, gPats, gUseRegex);
                    if gi==0, continue; end
                    grpNameThis = gNames{gi}; % already normalized
                else
                    grp = classifyGroup(name, grpA_pat, grpB_pat, useRegex);
                    if grp==0, continue; end
                    grpNameThis = ternary(grp==1, grpA_name, grpB_name);
                end

                % Load per-mouse result or auto-compute
                perMousePath = fullfile(mdir,'SeF_MDF_data.mat');
                if ~exist(perMousePath,'file')
                    if ~autoCompute
                        logmsg('Missing SeF_MDF_data for %s (skip).', name);
                        continue;
                    end
                    % Auto-compute from raw (as in per-mouse branch)
                    labPath = fullfile(mdir,'labels.mat'); if ~exist(labPath,'file'), logmsg('Missing labels in %s (skip).', name); continue; end
                    L = load(labPath); labels = tryPickLabels(L);
                    if isempty(labels), logmsg('labels missing in %s', labPath); continue; end

                    EEG = [];
                    eegPath = fullfile(mdir,'EEG_accusleep.mat');
                    if exist(eegPath,'file')
                        Sraw = load(eegPath);
                        if isfield(Sraw,'EEG') && isvector(Sraw.EEG), EEG = double(Sraw.EEG(:)); end
                    end
                    if isempty(EEG)
                        [fileList, ~] = findEEGMatFiles(mdir, struct( ...
                            'userPattern',   userEEGpat, ...
                            'userIsRegex',   userEEGisReg, ...
                            'ignorePatterns',{ignorePats}, ...
                            'wantSides',     "any", ...
                            'allowNonEEG',   false));
                        if isempty(fileList), logmsg('No EEG for %s (skip).', name); continue; end
                        EEG = extractBestEEGVector(fullfile(mdir, fileList.name{1}));
                        if isempty(EEG), logmsg('EEG extraction failed for %s (skip).', name); continue; end
                    end

                    try, EEGf = filtfilt(b_bp,a_bp,EEG); catch, EEGf=EEG; end
                    num_epochs = floor(numel(EEGf)/epoch_len);
                    if num_epochs<1, logmsg('Too short: %s', name); continue; end
                    labels = labels(1:min(num_epochs,numel(labels)));
                    num_epochs = numel(labels);
                    EEGf = EEGf(1:num_epochs*epoch_len);
                    EEGf = reshape(EEGf, epoch_len, []);
                    Sres = compute_MDF_SEF_Peak_per_state(EEGf, labels, codes, fs, winN, ovN, nfft, sefPerc);
                    if doGate, Sres = apply_peak_gating(Sres); end
                    S = Sres; %#ok<NASGU>
                    save(perMousePath,'S');
                    logmsg('Auto-computed %s', perMousePath);
                else
                    R = load(perMousePath);
                    if ~isfield(R,'S'), logmsg('S missing in %s', perMousePath); continue; end
                    Sres = R.S;
                    if doGate, Sres = apply_peak_gating(Sres); end
                end

                % Per-mouse means
                mouseMeans = per_mouse_means(Sres);

                % Append to group bins
                if multiMode
                    Gbins(gi) = append_mouse(Gbins(gi), mouseMeans);
                else
                    if grp==1, A = append_mouse(A, mouseMeans); else, B = append_mouse(B, mouseMeans); end
                end

                % per-mouse long rows
                try
                    perMouseRows{end+1} = rows_from_mouseMeans(name, grpNameThis, mouseMeans); %#ok<AGROW>
                catch ME
                    logmsg('Per-mouse long row build failed for %s: %s', name, ME.message);
                end
            end

            % ---------- Plots ----------
            if multiMode
                plot_group_bars_multi(Gbins, 'mdf',  'MDF (Hz)',  gNames);
                plot_group_bars_multi(Gbins, 'sef',  'SEF (Hz)',  gNames);
                plot_group_bars_multi(Gbins, 'peak', 'Peak (Hz)', gNames);
            else
                plot_group_bars(A, B, 'MDF (Hz)',  'mdf',  grpA_name, grpB_name);
                plot_group_bars(A, B, 'SEF (Hz)',  'sef',  grpA_name, grpB_name);
                plot_group_bars(A, B, 'Peak (Hz)', 'peak', grpA_name, grpB_name);
            end

            % ---------- Save a compact summary ----------
            summaryPath = fullfile(root,'group_mdf_sef_peak_summary.mat');
            if multiMode
                save(summaryPath,'Gbins','fs','epoch_sec','bp','winN','ovN','sefPerc','doGate','codes','gNames','gPats','gUseRegex');
            else
                save(summaryPath,'A','B','fs','epoch_sec','bp','winN','ovN','sefPerc','doGate','codes','grpA_name','grpB_name','grpA_pat','grpB_pat','useRegex');
            end
            logmsg('Saved group summary: %s', summaryPath);

            % ------------------------ CSV EXPORTS (group) ------------------------
            try
                if ~isempty(perMouseRows)
                    writetable(vertcat(perMouseRows{:}), ...
                        fullfile(resultsDir, 'mdf_sef_peak_per_mouse_long.csv'));
                end

                % Group pooled (per-mouse means) — long
                Gtab = table(); Sums = table();
                if multiMode
                    for gi = 1:numel(gNames)
                        Gtab = [Gtab; group_long_from_bin(gNames{gi}, Gbins(gi))]; %#ok<AGROW>
                        Sums = [Sums; group_summary_from_bin(gNames{gi}, Gbins(gi))]; %#ok<AGROW>
                    end
                else
                    Gtab = [Gtab; group_long_from_bin(grpA_name, A)];
                    Gtab = [Gtab; group_long_from_bin(grpB_name, B)];
                    Sums = [Sums; group_summary_from_bin(grpA_name, A)];
                    Sums = [Sums; group_summary_from_bin(grpB_name, B)];
                end
                if ~isempty(Gtab)
                    writetable(Gtab, fullfile(resultsDir, 'mdf_sef_peak_group_long.csv'));
                end
                if ~isempty(Sums)
                    writetable(Sums, fullfile(resultsDir, 'mdf_sef_peak_group_summary.csv'));
                end

                % Metadata
                if multiMode
                    fields = {'fs','epoch_sec','bp_low','bp_high','winN','ovN','nfft','sefPerc','doGate','mode','codes_wake','codes_rem','codes_nrem', ...
                        'Groups','useRegex','userEEGpat','userEEGisReg'};
                    values = {fs, epoch_sec, bp(1), bp(2), winN, ovN, nfft, sefPerc, logical(doGate), string(mode), codes(1), codes(2), codes(3), ...
                        string(strjoin(gNames,'|')), logical(gUseRegex), string(userEEGpat), logical(userEEGisReg)};
                else
                    fields = {'fs','epoch_sec','bp_low','bp_high','winN','ovN','nfft','sefPerc','doGate','mode','codes_wake','codes_rem','codes_nrem', ...
                        'GroupA','GroupB','patA','patB','useRegex','userEEGpat','userEEGisReg'};
                    values = {fs, epoch_sec, bp(1), bp(2), winN, ovN, nfft, sefPerc, logical(doGate), string(mode), codes(1), codes(2), codes(3), ...
                        string(grpA_name), string(grpB_name), string(grpA_pat), string(grpB_pat), logical(useRegex), string(userEEGpat), logical(userEEGisReg)};
                end
                MF = table(string(fields(:)), string(values(:)), 'VariableNames', {'Field','Value'});
                writetable(MF, fullfile(resultsDir, 'mdf_sef_peak_metadata.csv'));

                logmsg('MDF/SEF/Peak: CSV exports written.');
            catch ME
                logmsg('MDF/SEF/Peak CSV export failed: %s', ME.message);
            end
        end

        logmsg('MDF/SEF/Peak: done.');

        % ============================ helpers (nested) ============================
        function labels = tryPickLabels(L)
            labels = [];
            if isfield(L,'labels') && isnumeric(L.labels)
                labels = L.labels(:).';
            end
            if isempty(labels)
                f = fieldnames(L);
                for ii=1:numel(f)
                    v = L.(f{ii});
                    if isnumeric(v) && isvector(v)
                        labels = v(:).';
                        break;
                    end
                end
            end
            if isempty(labels)
                if isfield(L,'text') && ~isempty(L.text)
                    c = L.text(:,1);
                    map = containers.Map({'R','W','M','N'},{1,2,2,3});
                    tmp = nan(size(c));
                    for i=1:numel(c)
                        ch = upper(string(c(i)));
                        if isKey(map, ch), tmp(i)=map(ch); end
                    end
                    labels = tmp(~isnan(tmp)).';
                end
            end
        end

        function S = compute_MDF_SEF_Peak_per_state(EEGf, labels, codes, fs, winN, ovN, nfft, sefPerc)
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
                    if ~isvector(Pxx) || ~isvector(f) || isempty(Pxx), continue; end
                    tot = sum(Pxx);
                    if tot<=0, continue; end
                    c = cumsum(Pxx);
                    mi = find(c >= tot/2, 1, 'first'); if isempty(mi), continue; end
                    si = find(c >= sefPerc*tot, 1, 'first'); if isempty(si), continue; end
                    [~,pi] = max(Pxx);
                    mdf(end+1,1) = f(mi);
                    sef(end+1,1) = f(si);
                    pk (end+1,1) = f(pi);
                end
                % Remove SEF outliers: > mean + 3*SD (per state)
                if ~isempty(sef)
                    m = mean(sef,'omitnan'); s = std(sef,'omitnan');
                    keep = sef <= (m + 3*s);
                    mdf = mdf(keep); sef = sef(keep); pk = pk(keep);
                end
                Z.mdf = mdf; Z.sef = sef; Z.peak_freq = pk;
            end
        end

        function S = apply_peak_gating(S)
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
            G = struct();
            states = {'wake','nrem','rem'};
            metrics = {'mdf','sef','peak'};
            for s=1:numel(states)
                for m=1:numel(metrics)
                    G.(states{s}).(metrics{m}) = [];
                end
            end
        end

        function Gs = init_multi_bins(n)
            Gs = repmat(init_group_bin(), 1, n);
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

        function plot_group_bars(A, B, ylab, field, nameA_in, nameB_in)
            % 🔒 Sanitize labels to CHAR (trim+upper) to avoid XTickLabel errors
            nameA = safeLabel(nameA_in, 'GROUP A');
            nameB = safeLabel(nameB_in, 'GROUP B');

            states = {'Wake','NREM','REM'};
            stKeys = {'wake','nrem','rem'};

            field = convertStringsToChars(field);

            for si = 1:numel(states)
                sk    = stKeys{si};
                Avals = A.(sk).(field);  Avals = Avals(isfinite(Avals));
                Bvals = B.(sk).(field);  Bvals = Bvals(isfinite(Bvals));

                if isempty(Avals) && isempty(Bvals), continue; end

                figure; hold on;
                muA = mean(Avals,'omitnan'); muB = mean(Bvals,'omitnan');
                seA = std(Avals,'omitnan')/sqrt(max(1,numel(Avals)));
                seB = std(Bvals,'omitnan')/sqrt(max(1,numel(Bvals)));

                bar(1, muA, 'FaceColor',[0 0.447 0.741], 'BarWidth',0.5);
                bar(2, muB, 'FaceColor',[0.85 0.325 0.098], 'BarWidth',0.5);
                errorbar([1 2], [muA muB], [seA seB], 'k', 'linestyle','none', 'LineWidth',1.5);

                if ~isempty(Avals), plot( ones(size(Avals)), Avals, 'ko', 'MarkerFaceColor','k', 'MarkerSize',6 ); end
                if ~isempty(Bvals), plot( 2*ones(size(Bvals)), Bvals, 'ko', 'MarkerFaceColor','k', 'MarkerSize',6 ); end

                xlim([0.5 2.5]);
                set(gca,'XTick',[1 2],'XTickLabel',{nameA,nameB});
                ylabel(ylab); title(sprintf('%s — %s', upper(field), states{si}));
                grid on; hold off;
            end
        end

        function plot_group_bars_multi(Gbins, field, ylab, gNamesLoc_in)
            % 🔒 Ensure group names are CHAR cellstr and normalized
            gNamesLoc = cellfun(@(s)safeLabel(s,'GROUP'), gNamesLoc_in, 'uni', false);

            states  = {'Wake','NREM','REM'}; stKeys  = {'wake','nrem','rem'};
            for si = 1:numel(states)
                sk = stKeys{si};
                valsCell = cell(1,numel(Gbins));
                mu = nan(1,numel(Gbins)); se = nan(1,numel(Gbins));
                for gi=1:numel(Gbins)
                    v = Gbins(gi).(sk).(field);
                    v = v(isfinite(v));
                    valsCell{gi} = v;
                    if ~isempty(v)
                        mu(gi) = mean(v,'omitnan');
                        se(gi) = std(v,'omitnan')/sqrt(numel(v));
                    end
                end
                if all(isnan(mu)), continue; end

                figure; hold on;
                for gi=1:numel(Gbins)
                    if isnan(mu(gi)), continue; end
                    bar(gi, mu(gi), 'BarWidth',0.6); %#ok<BAR>
                    errorbar(gi, mu(gi), se(gi), 'k','linestyle','none','LineWidth',1.5);
                    % jitter dots
                    v = valsCell{gi};
                    if ~isempty(v)
                        xj = gi + (rand(size(v))*0.3 - 0.15);
                        plot(xj, v, 'ko','MarkerFaceColor','k','MarkerSize',5);
                    end
                end
                xlim([0.5 numel(Gbins)+0.5]);
                set(gca,'XTick',1:numel(Gbins),'XTickLabel',gNamesLoc);
                ylabel(ylab); title(sprintf('%s — %s', upper(field), states{si}));
                grid on; hold off;
            end
        end

        % --------------- CSV helper builders (nested) -----------------
        function T = per_mouse_vectors_long(S)
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

        function T = rows_from_mouseMeans(mouseName, grpLabel, M)
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
                        repmat(string(grpLabel),1,1), repmat(string(mouseName),1,1), ...
                        repmat(string(sName),1,1), repmat(string(mName),1,1), v, ...
                        'VariableNames', {'Group','MouseID','State','Metric','Value'})]; %#ok<AGROW>
                end
            end
        end

        function T = group_long_from_bin(grpName, Gbin)
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
            stNames = {'Wake','NREM','REM'}; stKeys = {'wake','nrem','rem'};
            fields = {'mdf','sef','peak'};
            S = table();
            for si = 1:numel(stKeys)
                sk = stKeys{si}; sName = stNames{si};
                for fi = 1:numel(fields)
                    fk = fields{fi};
                    vals = Gbin.(sk).(fk);
                    vals = vals(isfinite(vals));
                    if isempty(vals), continue; end
                    n = numel(vals); mu = mean(vals); sd = std(vals); sem = sd/sqrt(n);
                    S = [S; table(string(grpName), string(sName), string(upper(fk)), n, mu, sd, sem, ...
                        'VariableNames', {'Group','State','Metric','N','Mean','Std','SEM'})]; %#ok<AGROW>
                end
            end
        end

        % -------- small utilities --------
        function gi = classifyGroupIdx(folderName, patterns, useRx)
            hits = false(1,numel(patterns));
            for i=1:numel(patterns)
                p = patterns{i};
                if isempty(p), hits(i)=false; continue; end
                if useRx
                    try, hits(i) = ~isempty(regexpi(folderName, p, 'once')); catch, hits(i)=false; end
                else
                    hits(i) = contains(folderName, p, 'IgnoreCase', true);
                end
            end
            if sum(hits)==1, gi = find(hits,1,'first'); else, gi = 0; end
        end

        function out = ternary(cond,a,b); if cond, out=a; else, out=b; end; end

    % 🔒 Label normalizer: TRIM + UPPERCASE, return CHAR (MATLAB graphics-safe)
        function c = safeLabel(x, defaultIfEmpty)
            if nargin<2, defaultIfEmpty = 'GROUP'; end
            % unwrap cells/strings
            if iscell(x)
                % pick the first non-empty element if exists
                x = x(~cellfun(@isempty,x));
                if isempty(x); c = char(defaultIfEmpty); return; end
                x = x{1};
            end
            if isa(x,'string')
                if numel(x)>1, x = x(1); end
                x = char(x);
            end
            if ~ischar(x)
                try
                    x = char(string(x));
                catch
                    x = '';
                end
            end
            x = strtrim(x);
            if isempty(x)
                c = char(upper(strtrim(defaultIfEmpty)));
            else
                c = char(upper(x));
            end
        end

        % -------------------- Helpers: multi-group parsing --------------------
        function [names, pats] = trimGroups(namesIn, patsIn)
            % Normalize to cellstr column vectors
            names = cellstr(string(namesIn(:)));
            pats  = cellstr(string(patsIn(:)));

            % Pad to common length
            L = max(numel(names), numel(pats));
            if numel(names) < L, names(end+1:L) = {''}; end
            if numel(pats)  < L, pats(end+1:L)  = {''}; end

            % Trim whitespace and drop rows where BOTH name & pattern are empty
            mask = true(1, L);
            for i = 1:L
                names{i} = strtrimSafe(names{i});
                pats{i}  = strtrimSafe(pats{i});
                if isempty(names{i}) && isempty(pats{i})
                    mask(i) = false;
                end
            end

            names = names(mask);
            pats  = pats(mask);
        end

        function s = strtrimSafe(s)
            % Safe string/char trim that always returns a char row
            if isstring(s), s = char(s); end
            if isempty(s), s = ''; return; end
            s = strtrim(s);
        end
    end


%% ---------------------- INTERNAL: General PAC (Dynamic Bands) ----------------------
function runGenPAC_Internal(root, fs, epoch_sec, codes, useManual, zthr, ...
        phaseBands, ampBands, Nbins, excluded, doMI, doGroup, stateSel, ...
        grpA_name, grpB_name, grpA_pat, grpB_pat, useRegex, ...
        userEEGpat, userEEGisReg, ignorePats, varargin)

    % Optional multi-group config
    groups = [];
    if ~isempty(varargin), groups = varargin{1}; end
    multiMode = isstruct(groups) && isfield(groups,'names') && isfield(groups,'patterns');

    logmsg('GPAC: fs=%g, epoch=%gs, Nphase=%d, Namp=%d, bins=%d, MI=%d, state=%s', ...
        fs, epoch_sec, size(phaseBands,1), size(ampBands,1), Nbins, doMI, upper(stateSel));

    resultsDir = fullfile(root, 'General PAC Results');
    if ~exist(resultsDir,'dir'), mkdir(resultsDir); end

    d = dir(root); d = d([d.isdir]); d = d(~ismember({d.name},{'.','..'}));
    epoch_len = round(fs*epoch_sec);

    % --- State mapping ---
    switch lower(string(stateSel))
        case "wake", targetCode = codes(1);
        case "rem",  targetCode = codes(2);
        case "nrem", targetCode = codes(3);
        otherwise, error('Unknown stateSel: %s', string(stateSel));
    end

    % --- Accumulators ---
    if multiMode
        [gNames, gPats] = trimGroups(groups.names, groups.patterns);
        G    = gpac_initMultiCells(numel(gNames));
        G_MI = gpac_initMultiCells(numel(gNames));
    else
        A = {}; B = {};
        A_MI = {}; B_MI = {};
    end

    % --- Build MI frequency windows (dynamic) ---
    if doMI
        [phaseCentersHz, fp1, fp2] = gpac_buildSliding2HzGrid(phaseBands);
        [ampCentersHz,   fa1, fa2] = gpac_buildSliding2HzGrid(ampBands);
    else
        phaseCentersHz=[]; ampCentersHz=[]; fp1=[]; fp2=[]; fa1=[]; fa2=[];
    end

    % ============================== PER MOUSE ==============================
    for k = 1:numel(d)
        name = d(k).name;
        if any(strcmp(name, excluded)), logmsg('Skip excluded: %s', name); continue; end

        % Group classification
        if multiMode
            grpIdx = classifyGroupIdx(name, gPats, groups.useRegex);
            if grpIdx==0, logmsg('Unassigned (skip): %s', name); continue; end
        else
            grp = classifyGroup(name, grpA_pat, grpB_pat, useRegex);
            if grp==0, logmsg('Unassigned (skip): %s', name); continue; end
        end

        mdir = fullfile(root,name);

        % ----------------------- Build state vector ------------------------
        if strcmpi(stateSel,'rem') && useManual
            remPath = fullfile(mdir,'REM_EEG_accusleep.mat');
            if ~exist(remPath,'file'), logmsg('GPAC: No manual REM in %s', name); continue; end
            S = load(remPath);
            if ~isfield(S,'REM_EEG'), logmsg('GPAC: Missing REM_EEG in %s', remPath); continue; end
            state_vec = S.REM_EEG(:);
        else
            [fileList, meta] = findEEGMatFiles(mdir, struct( ...
                'userPattern',   userEEGpat, ...
                'userIsRegex',   userEEGisReg, ...
                'ignorePatterns',{ignorePats}, ...
                'wantSides',     "any", ...
                'allowNonEEG',   false));
            if isempty(fileList)
                logmsg('GPAC: No EEG .mat in %s', name); continue;
            end
            eegChosen = fileList.name{1};
            EEG = extractBestEEGVector(fullfile(mdir, eegChosen));
            if isempty(EEG) || numel(EEG) < fs
                logmsg('GPAC: Invalid EEG in %s; skipping.', eegChosen); continue;
            end
            if isfield(meta,'fellBack') && meta.fellBack
                logmsg('GPAC: EEG source: %s (fallback).', eegChosen);
            else
                logmsg('GPAC: EEG source: %s (matched user pattern).', eegChosen);
            end

            labPath = fullfile(mdir,'labels.mat');
            if ~exist(labPath,'file'), logmsg('GPAC: Missing labels in %s', name); continue; end
            L = load(labPath);
            if ~isfield(L,'labels'), logmsg('GPAC: No labels in %s', labPath); continue; end
            labels = L.labels(:).';

            % Epoch to columns
            num_epochs = floor(numel(EEG)/epoch_len);
            if num_epochs<1, logmsg('GPAC: Too short: %s', name); continue; end
            EEG = reshape(EEG(1:num_epochs*epoch_len), epoch_len, []);
            labels = labels(1:min(num_epochs,numel(labels)));
            EEG = EEG(:,1:numel(labels));

            idx = find(labels==targetCode);
            if isempty(idx)
                logmsg('GPAC: No %s epochs in %s', upper(stateSel), name); continue;
            end
            state_vec = cell2mat(arrayfun(@(e) EEG(:,e), idx, 'UniformOutput', false));
        end
        if isempty(state_vec), logmsg('GPAC: Empty signal in %s', name); continue; end

        % ------------------------- Clean outliers --------------------------
        z = zscore(double(state_vec));
        state_vec(abs(z)>zthr) = NaN;
        state_vec = fillmissing(state_vec,'linear');

        % ================== PAC DISTRIBUTIONS ===============================
        edges   = linspace(0, 720, Nbins+1);
        centers = (edges(1:end-1) + edges(2:end))/2;

        for ip = 1:size(phaseBands,1)
            th = phaseBands(ip,:);
            thSig = bandpass(state_vec, th, fs);
            thPhase = angle(hilbert(thSig));
            thDeg360 = mod(rad2deg(thPhase), 360);
            thDeg720 = [thDeg360; thDeg360+360];

            for ia = 1:size(ampBands,1)
                ga = ampBands(ia,:);
                gaSig  = bandpass(state_vec, ga, fs);
                gaAmp  = abs(hilbert(gaSig));
                gaAmp2 = [gaAmp; gaAmp];

                gamma_avg = zeros(Nbins,1);
                for b = 1:Nbins
                    inb = (thDeg720 >= edges(b)) & (thDeg720 < edges(b+1));
                    gamma_avg(b) = mean(gaAmp2(inb), 'omitnan');
                end
                gamma_smoothed = smooth(gamma_avg,3);
                gamma_smoothed = gamma_smoothed / sum(gamma_smoothed + eps);

                % Save per-mouse CSV
                outdir = fullfile(mdir, 'General PAC'); if ~exist(outdir,'dir'), mkdir(outdir); end
                pairLabel = sprintf('%s_phase_%g-%g_amp_%g-%g', upper(stateSel), th(1),th(2),ga(1),ga(2));
                try
                    Tmouse = table(centers(:), gamma_smoothed(:), ...
                        'VariableNames', {'ThetaPhase_deg','GammaNormAmp'});
                    writetable(Tmouse, fullfile(outdir, sprintf('GPAC_Dist_%s_%dbins.csv', pairLabel, Nbins)));
                catch ME
                    logmsg('GPAC per-mouse distribution CSV failed (%s): %s', name, ME.message);
                end

                % Bucket into group
                if multiMode
                    G{grpIdx}{end+1} = gamma_smoothed(:);
                else
                    if grp==1, A{end+1} = gamma_smoothed(:);
                    elseif grp==2, B{end+1} = gamma_smoothed(:);
                    end
                end
            end
        end

        % ========================== MI MAP (optional) ======================
        if doMI && ~isempty(phaseCentersHz) && ~isempty(ampCentersHz)
            try
                Q = 1/Nbins; MI = zeros(numel(ampCentersHz), numel(phaseCentersHz));
                for ic = 1:numel(phaseCentersHz)
                    ph = angle(hilbert(bandpass(state_vec,[fp1(ic) fp2(ic)],fs)));
                    [bins,~] = discretize(ph, Nbins);
                    for jc = 1:numel(ampCentersHz)
                        a = abs(hilbert(bandpass(state_vec,[fa1(jc) fa2(jc)],fs)));
                        D = zeros(1,Nbins);
                        for ii = 1:Nbins
                            m = (bins==ii);
                            D(ii) = mean(a(m));
                        end
                        D = D./sum(D + eps);
                        MI(jc,ic) = sum(D .* log((D+eps)/Q)) / log(Nbins);
                    end
                end

                outdir = fullfile(mdir,'General PAC');
                save(fullfile(outdir,sprintf('MI data (%d bins).mat',Nbins)),'MI');
                try
                    MItab = array2table(MI,'VariableNames', ...
                        matlab.lang.makeValidName("theta_"+string(phaseCentersHz)+"Hz"));
                    MItab = addvars(MItab, ampCentersHz(:),'Before',1,'NewVariableNames','gammaAmp_Hz');
                    writetable(MItab, fullfile(outdir, sprintf('MI_%dbins.csv',Nbins)));
                catch ME
                    logmsg('GPAC per-mouse MI CSV failed (%s): %s', name, ME.message);
                end

                % Store
                if multiMode, G_MI{grpIdx}{end+1} = MI;
                else
                    if grp==1, A_MI{end+1} = MI; elseif grp==2, B_MI{end+1} = MI; end
                end
            catch ME
                logmsg('GPAC per-mouse MI compute failed (%s): %s', name, ME.message);
            end
        end
    end % mice loop

    % ==================== GROUP DISTRIBUTIONS =====================
    edges   = linspace(0, 720, Nbins+1);
    centers = (edges(1:end-1) + edges(2:end))/2;

    if multiMode
        GM = cellfun(@(c) gpac_meanSafe(c), G, 'UniformOutput', false);
        figure; hold on;
        for gi = 1:numel(GM)
            if ~isempty(GM{gi}), plot(centers, GM{gi}, 'LineWidth',1.6); end
        end
        xlabel('\theta phase (°)'); ylabel('Normalized \gamma amplitude');
        xlim([0 720]); xticks(0:90:720); grid on;
        title(sprintf('General PAC — %s (group means)', upper(stateSel)));
        legend(gNames, 'Interpreter','none','Location','best');

        % ---- per-mouse long CSV ----
        try
            rows = cell(0,1);
            for gi = 1:numel(G)
                giCells = G{gi};
                for mi = 1:numel(giCells)
                    v = giCells{mi}; if isempty(v), continue; end
                    rows{end+1} = table( ...
                        repmat(string(gNames{gi}), numel(centers),1), ...
                        repmat(mi, numel(centers),1), ...
                        centers(:), v(:), ...
                        'VariableNames', {'Group','MouseIdx','ThetaPhase_deg','GammaNormAmp'}); %#ok<AGROW>
                end
            end
            if ~isempty(rows)
                writetable(vertcat(rows{:}), fullfile(resultsDir,'gpac_per_mouse_multi.csv'));
            end
        catch ME
            logmsg('GPAC multi-group CSV export failed: %s', ME.message);
        end

        % ====================== MI heatmaps (multi) =======================
        if doMI && doGroup
            try
                % Stacked MI export
                rows = cell(0,1);
                for gi = 1:numel(G_MI)
                    giCells = G_MI{gi};
                    for mi = 1:numel(giCells)
                        MI = giCells{mi};
                        if isempty(MI), continue; end
                        [A,P] = ndgrid(ampCentersHz(:), phaseCentersHz(:));
                        rows{end+1} = table( ...
                            repmat(string(gNames{gi}), numel(A),1), ...
                            repmat(mi, numel(A),1), ...
                            A(:), P(:), MI(:), ...
                            'VariableNames', {'Group','MouseIdx','gammaAmp_Hz','thetaPhase_Hz','MI'}); %#ok<AGROW>
                    end
                end
                if ~isempty(rows)
                    writetable(vertcat(rows{:}), fullfile(resultsDir,'mi_per_mouse_multi.csv'));
                end

                % Mean MI heatmap per group
                for gi = 1:numel(G_MI)
                    if isempty(G_MI{gi}), continue; end
                    MImean = mean(cat(3, G_MI{gi}{:}), 3, 'omitnan');
                    figure; contourf(phaseCentersHz, ampCentersHz, MImean, 120, 'linecolor','none');
                    title(sprintf('General PAC — %s — Mean MI (%s)', upper(stateSel), gNames{gi}), 'Interpreter','none');
                    xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)');
                    colorbar;
                    outPng = fullfile(resultsDir, sprintf('gpac_mi_heatmap_%s_%s.png', upper(stateSel), gNames{gi}));
                    try, exportgraphics(gcf,outPng,'Resolution',200); catch, saveas(gcf,outPng); end
                    close(gcf);
                end
            catch ME
                logmsg('GPAC multi-group MI export/plot failed: %s', ME.message);
            end
        end

    else
        % ===== Legacy A/B (same as theta-gamma) =====
        grpA_name_s = gpac_tochar(grpA_name);
        grpB_name_s = gpac_tochar(grpB_name);

        % ===== Legacy A/B (same as theta-gamma) =====
        Am = gpac_meanSafe(A); Bm = gpac_meanSafe(B);
        figure; hold on;
        if ~isempty(Am), plot(centers, Am, 'b','LineWidth',1.6); end
        if ~isempty(Bm), plot(centers, Bm, 'r','LineWidth',1.6); end
        xlabel('\theta phase (°)'); ylabel('Normalized \gamma amplitude');
        xlim([0 720]); xticks(0:90:720); grid on;
        title(sprintf('General PAC — %s — (%s vs %s)', ...
            upper(char(string(stateSel))), gpac_tochar(grpA_name), gpac_tochar(grpB_name)), ...
            'Interpreter','none');
        legend({gpac_tochar(grpA_name), gpac_tochar(grpB_name)}, 'Location','best');

        % CSVs
        gpac_write_per_mouse_pac_csv(A, grpA_name, centers, ...
            fullfile(resultsDir, sprintf('gpac_per_mouse_%s.csv', lower(gpac_tochar(grpA_name)))));
        gpac_write_per_mouse_pac_csv(B, grpB_name, centers, ...
            fullfile(resultsDir, sprintf('gpac_per_mouse_%s.csv', lower(gpac_tochar(grpB_name)))));


        if doMI
            gpac_write_per_mouse_mi_stack(A_MI, grpA_name_s, ampCentersHz, phaseCentersHz, ...
                fullfile(resultsDir, sprintf('mi_per_mouse_%s.csv', lower(grpA_name_s))));
            gpac_write_per_mouse_mi_stack(B_MI, grpB_name_s, ampCentersHz, phaseCentersHz, ...
                fullfile(resultsDir, sprintf('mi_per_mouse_%s.csv', lower(grpB_name_s))));
        end
        % ---- Optional: Plot group-level MI heatmaps for A/B mode ----
if doMI && doGroup
    try
        if ~isempty(A_MI)
            MImeanA = mean(cat(3, A_MI{:}), 3, 'omitnan');
            figure; contourf(phaseCentersHz, ampCentersHz, MImeanA, 120, 'linecolor','none');
            title(sprintf('General PAC — %s — Mean MI (%s)', upper(stateSel), gpac_tochar(grpA_name_s)), 'Interpreter','none');
            xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)');
            colorbar;
            outPngA = fullfile(resultsDir, sprintf('gpac_mi_heatmap_%s_%s.png', upper(stateSel), lower(gpac_tochar(grpA_name_s))));
            try, exportgraphics(gcf, outPngA, 'Resolution', 200); catch, saveas(gcf, outPngA); end
            close(gcf);
        end
        if ~isempty(B_MI)
            MImeanB = mean(cat(3, B_MI{:}), 3, 'omitnan');
            figure; contourf(phaseCentersHz, ampCentersHz, MImeanB, 120, 'linecolor','none');
            title(sprintf('General PAC — %s — Mean MI (%s)', upper(stateSel), gpac_tochar(grpB_name_s)), 'Interpreter','none');
            xlabel('Theta phase (Hz)'); ylabel('Gamma amp (Hz)');
            colorbar;
            outPngB = fullfile(resultsDir, sprintf('gpac_mi_heatmap_%s_%s.png', upper(stateSel), lower(gpac_tochar(grpB_name_s))));
            try, exportgraphics(gcf, outPngB, 'Resolution', 200); catch, saveas(gcf, outPngB); end
            close(gcf);
        end
    catch ME
        logmsg('GPAC A/B MI heatmap export failed: %s', ME.message);
    end
end

    end

    % --- Metadata ---
    try
        MF = table(["fs";"epoch_sec";"Nbins";"zthr";"useManual";"doMI";"doGroup";"state"], ...
                   string([fs; epoch_sec; Nbins; zthr; useManual; doMI; doGroup; string(stateSel)]), ...
                   'VariableNames', {'Field','Value'});
        if multiMode
            MF = [MF; table("Groups", join(string(gNames),"|"))];
        else
            MF = [MF;
                table("GroupA", string(grpA_name));
                table("GroupB", string(grpB_name));
                table("patA",  string(grpA_pat));
                table("patB",  string(grpB_pat))];
        end
        writetable(MF, fullfile(resultsDir,'gpac_metadata.csv'));
    catch
    end

    logmsg('GPAC: done.');
end

% --------------------------- local helpers (GPAC-unique) --------------------------------
function cells = gpac_initMultiCells(n)
    cells = cell(1,n); for i=1:n, cells{i} = {}; end
end

function m = gpac_meanSafe(cellvec)
    if isempty(cellvec), m = []; return; end
    try, m = mean(cat(2, cellvec{:}), 2, 'omitnan'); catch, m = []; end
end

function [centersHz, f1, f2] = gpac_buildSliding2HzGrid(bandPairs)
    if isempty(bandPairs) || ~isnumeric(bandPairs)
        centersHz=[]; f1=[]; f2=[]; return;
    end
    lo = min(bandPairs(:,1)); hi = max(bandPairs(:,2));
    if ~isfinite(lo) || ~isfinite(hi) || hi<=lo
        centersHz=[]; f1=[]; f2=[]; return;
    end
    centersHz = (max(1,floor(lo)) : 1 : ceil(hi));
    f1 = max(1, centersHz - 1); f2 = f1 + 2;
    keep = f2 > f1; centersHz = centersHz(keep);
    f1 = f1(keep); f2 = f2(keep);
    centersHz = centersHz(:); f1=f1(:); f2=f2(:);
end

function gpac_write_per_mouse_pac_csv(C, groupName, centers, outCsv)
    if isempty(C), return; end
    rows = cell(0,1);
    for i = 1:numel(C)
        gi = C{i}(:);
        if isempty(gi), continue; end
        Ti = table( ...
            repmat(string(groupName), numel(centers),1), ...
            repmat(i,               numel(centers),1), ...
            centers(:), gi, ...
            'VariableNames', {'Group','MouseIdx','ThetaPhase_deg','GammaNormAmp'});
        rows{end+1} = Ti; %#ok<AGROW>
    end
    if ~isempty(rows)
        writetable(vertcat(rows{:}), outCsv);
    end
end

function gpac_write_per_mouse_mi_stack(MIcells, groupName, ampHz, phaseHz, outCsv)
    % MIcells is a cell array of numeric [numel(ampHz) x numel(phaseHz)] matrices
    if isempty(MIcells), return; end
    rows = cell(0,1);
    [A,P] = ndgrid(ampHz(:), phaseHz(:));  % axes grids for long export
    for i = 1:numel(MIcells)
        MI = MIcells{i};
        if isempty(MI) || ~isnumeric(MI), continue; end
        if ~isequal(size(MI), size(A))
            try, MI = reshape(MI, size(A)); catch, continue; end
        end
        Ti = table( ...
            repmat(string(groupName), numel(A), 1), ...
            repmat(i,                 numel(A), 1), ...
            A(:), P(:), MI(:), ...
            'VariableNames', {'Group','MouseIdx','gammaAmp_Hz','thetaPhase_Hz','MI'});
        rows{end+1} = Ti; %#ok<AGROW>
    end
    if ~isempty(rows)
        writetable(vertcat(rows{:}), outCsv);
    end
end

function s = gpac_tochar(x)
    % Safely convert any variable to char for sprintf or filenames
    if iscell(x)
        if isempty(x)
            s = '';
        else
            s = gpac_tochar(x{1});
        end
    elseif isstring(x)
        s = char(x);
    elseif isnumeric(x)
        s = char(string(x));
    else
        s = char(x);
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


end





