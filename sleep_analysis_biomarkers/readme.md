# 🧠 Sleep and Biomarker Analysis Pipeline

## 📘 Overview
This repository provides a complete MATLAB-based framework for **automated sleep scoring** and **EEG biomarker analysis** in mouse models.

The pipeline consists of two complementary components:
1. **SleepScore** – processes raw EEG and EMG recordings to generate sleep-state labels (Wake, NREM, REM, Undefined).  
2. **SleepLabApp (GUI)** – an interactive graphical interface for multi-modal biomarker discovery and group analysis across mice, including spectral, fractal, and coupling metrics.

Developed for **preclinical electrophysiology**, the pipeline supports data acquired from both **Neuralynx** and **LabChart** systems.

---

## 🚀 Workflow Summary

### 1️⃣ Sleep Scoring
Run the `SleepScore.m` script to process raw EEG/EMG recordings and classify each 5-second epoch into sleep states.

**Input**
- EEG and EMG recordings (Neuralynx or LabChart)
- Sampling rate and AD conversion parameters

**Output**
- `labels.mat` – numeric vector of classified states  
  (`1 = REM`, `2 = Wake`, `3 = NREM`, `4 = Undefined`)
- `EEG_accusleep.mat` / `EMG_accusleep.mat` – compatible with **AccuSleep** software
- Optional: hypnogram and `.csv` summary file

After classification, you can either:
- Continue manual inspection in **AccuSleep** *(Chen et al., 2022 – Validation of Deep Learning-based Sleep State Classification)*, or  
- Proceed directly to **SleepLabApp** for biomarker extraction.

---

### 2️⃣ Biomarker Discovery
Run `SleepLabApp.m` to analyze the labeled recordings.

The **SleepLabApp GUI** enables exploration of multiple EEG-based biomarkers.  
Each module is accessible via a dropdown menu and produces publication-ready plots and CSV exports.

**Modules include**
- Power Spectral Density (PSD) Grouping  
- Theta–Gamma Phase-Amplitude Coupling (PAC)  
- Higuchi Fractal Dimension (HFD)  
- Beta-Bursts  
- Median / Spectral Edge / Peak Frequency  

---

## 📂 Example Directory Structure

**Directory layout:**
- `main_directory/`
  - `C4524 WT/`
    - `EEG_accusleep.mat`
    - `EMG_accusleep.mat`
    - `labels.mat`
  - `C4659 DS/`
    - `EEG_accusleep.mat`
    - `EMG_accusleep.mat`
    - `labels.mat`
  - `SleepScore.m`
  - `SleepLabApp.m`

*(This Markdown list format ensures perfect GitHub rendering — no horizontal scrollbars or block breaks.)*

---

## 🧩 System Requirements
- MATLAB **R2021a** or later  
- **Signal Processing Toolbox**  
- **Statistics and Machine Learning Toolbox**  
- *(Optional)* **Parallel Computing Toolbox** for large datasets  

---

## ⚙️ Usage

### Step 1 – Run SleepScore

>> SleepScore

Follow the interactive prompts to select:

Acquisition platform (Neuralynx / LabChart)

Sampling rate

Channel configuration

Output directory

Outputs

labels.mat

EEG_accusleep.mat

EMG_accusleep.mat

Summary plots and .csv files

### Step 2 – Launch SleepLabApp

>> SleepLabApp

Then follow these steps:

Select the main directory containing mouse subfolders

Choose the analysis module from the dropdown

Adjust parameters (epoch length, bandpass, thresholds, etc.)

Click Run Selected Module

Monitor progress in the real-time log window

All results and plots are automatically saved inside the selected root directory.



## 📊 Outputs

Each module exports both per-mouse and group-level results:

.mat files for reproducibility

Long-format .csv tables for statistical analysis (R, Python, Excel)

Publication-ready plots (PSD, PAC, CDFs, bar ± SEM, heatmaps)

Metadata .csv documenting all analysis parameters

The pipeline integrates seamlessly with AccuSleep - sleep labels from SleepScore can be imported for manual validation or refinement.


##  🧠 Example Dataset

A small example dataset is provided under /example_data/ for quick testing.
It includes EEG, EMG, and label files from a 2-minute mouse recording (2000 Hz, 5 s epochs).




## 👤 Author

Shahak Ranen
M.Sc. Neuroscience, Tel Aviv University
Department of Human Molecular Genetics & Biochemistry
Rubinstein Lab – “Dravet Syndrome” Lab
Tel Aviv University & Sheba Tel HaShomer Medical Center

📧 Contact: shahakranen@mail.tau.ac.il

👨‍🏫 PI: Prof. Moran Rubinstein – moranrub@mail.tau.ac.il
