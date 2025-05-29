import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import StratifiedShuffleSplit
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import classification_report, confusion_matrix

# === Step 1: Load the mouse-level feature table ===
df = pd.read_csv("mouse_level_moseq_features.csv")

# === Step 2: Encode genotype ===
df['label'] = df['genotype'].map({'WT': 0, 'DS': 1})
features = df.drop(columns=['mouse_id', 'genotype', 'label']).columns

# === Step 3: Initialize storage ===
all_reports = []

# === Step 4: Repeat 10 random splits ===
splitter = StratifiedShuffleSplit(n_splits=10, test_size=5, random_state=42)

for i, (train_idx, test_idx) in enumerate(splitter.split(df, df['label'])):
    train_set, test_set = df.iloc[train_idx], df.iloc[test_idx]

    X_train = train_set[features]
    y_train = train_set['label']
    X_test = test_set[features]
    y_test = test_set['label']

    # === Step 5: Standardize features ===
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    # === Step 6: Train Random Forest with class weight ===
    model = RandomForestClassifier(class_weight='balanced', random_state=42)
    model.fit(X_train_scaled, y_train)
    # === Feature importance analysis ===
    importances = model.feature_importances_
    feature_names = features  # already defined earlier

    # Create a sorted list of (feature, importance)
    feature_importance = sorted(zip(feature_names, importances), key=lambda x: x[1], reverse=True)

    print("\nTop 20 Most Important Features:")
    for name, score in feature_importance[:20]:
        print(f"{name:30s}: {score:.4f}")

    # === Step 7: Predict and evaluate ===
    y_pred = model.predict(X_test_scaled)
    report = classification_report(y_test, y_pred, output_dict=True)
    all_reports.append(report)

    print(f"\n=== Run {i + 1} ===")
    print(confusion_matrix(y_test, y_pred))
    print(classification_report(y_test, y_pred, target_names=['WT', 'DS']))

# === Step 8: Compute average performance over 10 runs ===
average_f1_ds = np.mean([r['1']['f1-score'] for r in all_reports])
average_f1_wt = np.mean([r['0']['f1-score'] for r in all_reports])
print(f"\nAverage F1-score for WT: {average_f1_wt:.3f}")
print(f"Average F1-score for DS: {average_f1_ds:.3f}")
