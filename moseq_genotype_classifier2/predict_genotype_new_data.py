import pandas as pd
import joblib
from sklearn.preprocessing import StandardScaler

# === Step 1: Load the new raw MoSeq CSV ===
raw_path =  "D:\MoSeq Data\DS 14_04_25\combined_moseq_df.csv" # <-- replace with actual path
df = pd.read_csv(raw_path)

# === Step 2: Parse and prepare mouse_id ===
df['mouse_id'] = df['SubjectName'].str.extract(r'([A-Za-z0-9]+)')
df.rename(columns={'labels (usage sort)': 'syllable'}, inplace=True)

# === Step 3: Define relevant feature columns ===
numerical_features = [
    'dist_to_center_px', 'width_px', 'width_mm', 'velocity_theta',
    'velocity_3d_px', 'velocity_3d_mm', 'velocity_2d_px', 'velocity_2d_mm',
    'length_px', 'length_mm', 'height_ave_mm',
    'centroid_y_px', 'centroid_y_mm', 'centroid_x_px', 'centroid_x_mm',
    'area_px', 'area_mm', 'angle'
]

# === Step 4: Aggregate per mouse ===
syllable_counts = df.pivot_table(index='mouse_id', columns='syllable', aggfunc='size', fill_value=0)
syllable_counts.columns = [f'syllable_{int(c)}' for c in syllable_counts.columns]

numerical_means = df.groupby('mouse_id')[numerical_features].mean().add_suffix('_mean')
numerical_stds = df.groupby('mouse_id')[numerical_features].std().add_suffix('_std')

aggregated_df = pd.concat([syllable_counts, numerical_means, numerical_stds], axis=1).reset_index()

# === Step 5: Load model, scaler, and feature list ===
model = joblib.load("final_moseq_model.pkl")
scaler = joblib.load("final_scaler.pkl")
feature_list = joblib.load("final_features.pkl")

# === Step 6: Align features (fill missing, keep order) ===
for col in feature_list:
    if col not in aggregated_df.columns:
        aggregated_df[col] = 0  # fill missing syllables with 0
X = aggregated_df[feature_list]

# === Step 7: Standardize and predict ===
X_scaled = scaler.transform(X)
predicted_labels = model.predict(X_scaled)
predicted_probs = model.predict_proba(X_scaled)[:, 1]  # probability of DS

# === Step 8: Create output DataFrame ===
results = pd.DataFrame({
    'mouse_id': aggregated_df['mouse_id'],
    'predicted_label': predicted_labels,
    'predicted_genotype': ['WT' if x == 0 else 'DS' for x in predicted_labels],
    'probability_DS': predicted_probs
})

# === Step 9: Save predictions ===
results.to_csv("predicted_genotypes_new_data.csv", index=False)
print("✅ Predictions saved to 'predicted_genotypes_new_data.csv'")
