import pandas as pd
import matplotlib.pyplot as plt
from sklearn.preprocessing import StandardScaler
from sklearn.decomposition import PCA
from sklearn.manifold import TSNE
import seaborn as sns

# === Step 1: Load mouse-level feature table ===
file_path = "mouse_level_moseq_features.csv"  # or path to a new one
df = pd.read_csv(file_path)

# === Step 2: Encode labels ===
df['label'] = df['genotype'].map({'WT': 0, 'DS': 1})
features = df.drop(columns=['mouse_id', 'genotype', 'label']).columns
X = df[features]
y = df['genotype']

# === Step 3: Standardize the features ===
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# === Step 4: PCA ===
pca = PCA(n_components=2)
X_pca = pca.fit_transform(X_scaled)

# === Step 5: t-SNE ===
tsne = TSNE(n_components=2, perplexity=5, random_state=42)
X_tsne = tsne.fit_transform(X_scaled)

# === Step 6: Plotting ===
def plot_embedding(embedding, title):
    plt.figure(figsize=(8, 6))
    sns.scatterplot(x=embedding[:, 0], y=embedding[:, 1], hue=y, palette={'WT': 'blue', 'DS': 'red'}, s=100)
    plt.title(title)
    plt.xlabel("Component 1")
    plt.ylabel("Component 2")
    plt.legend(title="Genotype")
    plt.grid(True)
    plt.tight_layout()
    plt.show()

plot_embedding(X_pca, "PCA - MoSeq Feature Space")
plot_embedding(X_tsne, "t-SNE - MoSeq Feature Space")
