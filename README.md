# Cage-Housed Mouse Trajectory and Behavior Analysis Tool

An automated MATLAB-based pipeline designed to process YOLO-derived bounding box coordinates for tracking and analyzing the behavioral trajectories of cage-housed mice.

---
## 📌 Project Overview
This tool provides an efficient, reproducible workflow for processing large-scale video tracking data. By parsing YOLO detection labels (`.txt` files containing bounding box coordinates and confidence scores), the pipeline filters out spatial anomalies, aligns missing frames, and calculates continuous Euclidean distance metrics. 

Ultimately, it quantifies rodent locomotor activity and automates behavioral classification into **Motion** and **Non-Motion** states within customized home-cage spatial boundaries.

---

## 🛠️ Prerequisites
To run this pipeline, you need the following environment:
* **MATLAB** (R2021a or later recommended)
* **Built-in MATLAB Functions & Toolboxes**:
  * `Data Import and Analysis` (specifically utilizes `readtable` for fast parsing of delimited text data).
  * No advanced third-party toolboxes are strictly required, as core matrix operations and Euclidean distance calculations are implemented natively.

---

## 📂 Project Directory Structure
To ensure the script executes correctly, organize your project workspace as follows:

```text
mouse-behavior-analysis/
├── data/
│   └── labels/          <-- Place your YOLO .txt label folders here
├── results/             <-- Output directory (Generated .xlsx reports will appear here)
├── src/
│   └── main_process.m   <-- Core MATLAB execution script
└── README.md

🚀 Usage Guide
Follow these steps to process your tracking datasets:

Prepare Input Data: Export your YOLO object detection results and place the entire labels/ folder into the data/ directory of this repository.

Configure Parameters: Open src/main_process.m in MATLAB and adjust the hyperparameters in the CONFIGURATION block (e.g., framePerSec, confThreshold, and boundParams) to match your experimental setup.

Execute the Pipeline: Run the src/main_process.m script.

Retrieve Results: Once completion messages appear in the command window, navigate to the results/ folder to access the comprehensive .xlsx spreadsheets containing calculated distances, timestamps, and metadata summary parameters.