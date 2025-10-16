🧠 Sleep and Biomarker Analysis Pipeline


Overview

This repository provides a complete MATLAB-based framework for automated sleep scoring and EEG biomarker analysis in mouse models.
The pipeline is divided into two main components:

SleepScore – processes raw EEG and EMG recordings to generate sleep-state labels (Wake, NREM, REM, Undefined).

SleepLabApp (GUI) – a graphical interface for multi-modal biomarker discovery and group analysis across mice, including spectral, fractal, and coupling metrics.

The pipeline was developed for preclinical electrophysiological research and is compatible with both Neuralynx and LabChart data.


🚀 Workflow Summary
1. Sleep Scoring

Run the SleepScore script to process raw EEG/EMG recordings and classify each 5-second epoch into sleep states.

Input:

EEG and EMG recordings (from Neuralynx or LabChart)

Sampling rate and AD conversion parameters

Output:

labels.mat - numeric vector of classified states (1 = REM, 2 = Wake, 3 = NREM)

EEG_accusleep + EMG_accusleep - variables that can be loaded into Accusleep software.
Optional: visual hypnogram and .csv summary file

After classification, you can:

Continue detailed manual inspection in AccuSleep

(Chen et al., 2022 - Validation of Deep Learning-based Sleep State Classification)

Or proceed directly to SleepLabApp for biomarker extraction.



2. Biomarker Discovery

Launch the SleepLabApp.m GUI to analyze the labeled recordings.

Modules available:

## 2. Biomarker Discovery

The **SleepLabApp** GUI allows exploration of multiple EEG-based biomarkers extracted from labeled recordings.  
Each module is accessible via a dropdown menu and produces publication-ready visualizations and CSV exports.

| Module | Description | Input | Output |
|--------|--------------|--------|---------|
| **PSD Grouping** | Computes and compares Power Spectral Density (PSD) profiles between groups (e.g., WT vs DS) for Wake, NREM, and REM. Optional peak filtering and notch removal. | EEG + labels | Group PSD plots, `.mat` and `.csv` summaries |
| **Theta–Gamma PAC** | Computes Phase-Amplitude Coupling (PAC) during REM sleep using Modulation Index and phase–amplitude distributions. | REM EEG or labeled REM epochs | PAC distribution curves, MI heatmaps, `.csv` summaries |
| **Higuchi Fractal Dimension (HFD)** | Estimates HFD per epoch to capture EEG signal complexity during different sleep states. | EEG + labels | Boxplots, per-state HFD `.csv` files, summary tables |
| **Beta-Bursts** | Detects beta-band transient bursts during wake and extracts amplitude, duration, frequency, and IBI features. | EEG(L/R) + labels | CDF plots, per-mouse and group `.csv` summaries |
| **MDF/SEF/Peak Frequency** | Computes Median Frequency (MDF), Spectral Edge Frequency (SEF), and dominant Peak frequency for each state. | Raw EEG + labels | Bar plots with SEM, per-mouse and group `.csv` outputs |

Each module automatically detects mice folders (WT/DS), processes recordings, and exports both MATLAB and CSV outputs for reproducibility and external analysis.



📂 Directory Structure

Example project organization (after sleepScore analysis):

📁 main_directory/
 ├── 🐭 C4524 WT/
 │    ├── EEG_accusleep.mat
 │    ├── EMG_accusleep.mat
 │    ├── labels.mat
 │   
 ├── 🐭 C4659 DS/
 │    ├── EEG_accusleep.mat
 │    ├── EMG_accusleep.mat
 │    ├── labels.mat
 │    └── 
 ├── SleepScore.m
 ├── SleepLabApp.m
 


🧩 System Requirements

MATLAB R2021a or later

Signal Processing Toolbox

Statistics and Machine Learning Toolbox

(Optional) Parallel Computing Toolbox for large datasets



⚙️ Usage
Step 1 – Run SleepScore
>> SleepScore

Follow the interactive prompts to select:

Acquisition platform (Neuralynx / LabChart)

Sampling rate

Channel configuration

Output directory

Outputs:
labels.mat, EEG_accusleep.mat, EMG_accusleep.mat, and summary plots.

Step 2 – Launch SleepLabApp
>> SleepLabApp

Select the main directory containing mouse subfolders.

Choose the analysis module from the dropdown.

Adjust settings (epoch length, bandpass, thresholds, etc.).

Click Run Selected Module.

Monitor progress in the real-time log box.

All results and plots will be automatically saved inside the selected root directory.


📊 Outputs

Each module exports both per-mouse and group-level data:

MATLAB .mat files for reproducibility

Long-format .csv tables for statistical analysis (R, Python, Excel)

Publication-ready plots (PSD, PAC, CDFs, bar + SEM, heatmaps)

Metadata .csv documenting all parameters used


The pipeline is designed to integrate seamlessly with AccuSleep.
Sleep labels produced by SleepScore can be directly imported into AccuSleep for manual validation or refinement.




👤 Author
Shahak Ranen
M.Sc. Neuroscience, Tel Aviv University
Department of Human Molecular Genetics & Biochemistry
Rubinstein Lab - "Dravet Syndrome" Lab, Tel Aviv University & Sheba Tel HaShomer Medical Center

Shahak Ranen <shahakranen@mail.tau.ac.il>
Moran Rubinstein <moranrub@mail.tau.ac.il>



