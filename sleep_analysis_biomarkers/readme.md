# 🧠 Sleep and Biomarker Analysis Pipeline

## 📘 Overview
This repository provides a complete **MATLAB-based framework** for automated **sleep scoring** and **EEG biomarker analysis** in mouse models.  
The pipeline consists of two complementary components:

1. **SleepScore** – processes raw EEG and EMG recordings to generate sleep-state labels (*Wake, NREM, REM, Undefined*).  
2. **SleepLabApp (GUI)** – an interactive graphical interface for multi-modal biomarker discovery and group analysis across mice, including **spectral**, **fractal**, and **coupling** metrics.

Developed for **preclinical electrophysiology**, the pipeline supports data acquired from both **Neuralynx** and **LabChart** systems.

---

## 🚀 Workflow Summary

### 1️⃣ Sleep Scoring
Run the `SleepScore.m` script to process raw EEG/EMG recordings and classify each **5-second epoch** into sleep states.

**Input**
- EEG and EMG recordings (Neuralynx or LabChart)
- Sampling rate and AD conversion parameters

**Output**
- `labels.mat` – numeric vector of classified states  
  *(1 = REM, 2 = Wake, 3 = NREM, 4 = Undefined)*
- `EEG_accusleep.mat` / `EMG_accusleep.mat` – compatible with **AccuSleep** software  
- Optional: hypnogram and `.csv` summary file

After classification, you can either:
- Continue manual inspection in **AccuSleep**  
  *(Chen et al., 2022, Validation of Deep Learning-based Sleep State Classification)*  
- Or proceed directly to **SleepLabApp** for biomarker extraction.

---

### 2️⃣ Biomarker Discovery
Launch `SleepLabApp.m` to analyze the labeled recordings.

The **SleepLabApp** GUI enables exploration of multiple EEG-based biomarkers.  
Each module is accessible via a dropdown menu and produces publication-ready plots and CSV exports.

| Module | Description | Input | Output |
|--------|--------------|--------|---------|
| **PSD Grouping** | Computes and compares Power Spectral Density (PSD) profiles between groups (e.g., WT vs DS) for Wake, NREM, and REM. Optional peak filtering and notch removal. | EEG + labels | Group PSD plots, `.mat` and `.csv` summaries |
| **Theta–Gamma PAC** | Computes Phase–Amplitude Coupling (PAC) during REM using Modulation Index and phase–amplitude distributions. | REM EEG or labeled REM epochs | PAC curves, MI heatmaps, `.csv` summaries |
| **Higuchi Fractal Dimension (HFD)** | Estimates HFD per epoch to capture EEG complexity across sleep states. | EEG + labels | Boxplots, per-state HFD `.csv` files, summary tables |
| **Beta-Bursts** | Detects transient beta-band bursts during wake and extracts amplitude, duration, frequency, and IBI features. | EEG (L/R) + labels | CDF plots, per-mouse and group `.csv` summaries |
| **MDF/SEF/Peak Frequency** | Computes Median Frequency (MDF), Spectral Edge Frequency (SEF), and dominant Peak frequency per state. | Raw EEG + labels | Bar plots with SEM, per-mouse/group `.csv` outputs |

Each module automatically detects mouse folders (e.g., WT/DS), processes recordings, and exports **MATLAB** and **CSV** outputs for reproducibility and external analysis.

---

## 📂 Directory Structure
Example organization after running **SleepScore**:

## 📂 Example Directory Structure

```bash
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
 │
 ├── SleepScore.m
 ├── SleepLabApp.m


---

 ## 🧩 System Requirements
- MATLAB **R2021a** or later  
- **Signal Processing Toolbox**  
- **Statistics and Machine Learning Toolbox**  
- *(Optional)* Parallel Computing Toolbox for large datasets  

---



## ⚙️ Usage

### **Step 1 – Run SleepScore**

```matlab
>> SleepScore



