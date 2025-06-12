import joblib
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# === Load model and features ===
model_path = 'final_moseq_model.pkl'
features_path = 'final_features.pkl'

model = joblib.load(model_path)
feature_list = joblib.load(features_path)

# === Get feature importances ===
importances = model.feature_importances_
indices = np.argsort(importances)[::-1]
sorted_features = [feature_list[i] for i in indices]

# === Select top N features ===
top_n = 50
top_features = sorted_features[:top_n]
top_importances = importances[indices[:top_n]]

# === Plot ===
plt.figure(figsize=(10, 8))
plt.barh(range(top_n), top_importances[::-1], align='center')
plt.yticks(range(top_n), top_features[::-1])
plt.xlabel('Feature Importance (relative contribution, unitless)')
plt.title('Top 50 Most Important Features (Random Forest)')
plt.tight_layout()
plt.show()
