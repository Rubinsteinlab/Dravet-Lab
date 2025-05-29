import pandas as pd
import joblib
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler

# === Load data ===
df = pd.read_csv("mouse_level_moseq_features.csv")
df['label'] = df['genotype'].map({'WT': 0, 'DS': 1})

# === Extract features and labels ===
features = df.drop(columns=['mouse_id', 'genotype', 'label']).columns
X = df[features]
y = df['label']

# === Standardize features ===
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# === Train final model ===
model = RandomForestClassifier(class_weight='balanced', random_state=42)
model.fit(X_scaled, y)

# === Save model, scaler, and feature list ===
joblib.dump(model, "final_moseq_model.pkl")
joblib.dump(scaler, "final_scaler.pkl")
joblib.dump(list(features), "final_features.pkl")

print("✅ Model, scaler, and feature list saved successfully.")
