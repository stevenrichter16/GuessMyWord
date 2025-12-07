# train_to_coreml.py

import pandas as pd
from sklearn.tree import DecisionTreeClassifier
import coremltools as ct

# 1. Load the dataset
df = pd.read_csv("animals_20q.csv")

# 'Animal' is the label, everything else are features (0/1)
y = df["Animal"]
X = df.drop(columns=["Animal"])

feature_names = list(X.columns)

# 2. Train a decision tree classifier
# - criterion="entropy" often gives a nice information-gain tree
# - max_depth controls how many questions it asks (roughly)
clf = DecisionTreeClassifier(
    criterion="entropy",
    max_depth=20,       # tune this if you want <= 20 questions
    random_state=42
)
clf.fit(X, y)

# 3. Convert to Core ML
# coremltools will create:
#   - "classLabel": predicted animal (string)
#   - "classScores": dictionary of {animal: probability}
coreml_model = ct.converters.sklearn.convert(
    clf,
    input_features=feature_names
    # output_feature_names is optional for classifiers;
    # defaults to ("classLabel", "classScores")
)

# 4. Add metadata (optional but nice)
coreml_model.author = "Your Name"
coreml_model.license = "Internal use"
coreml_model.short_description = "Decision tree for a 20 Questions animal guessing game."

# Describe each input feature as a question
for name in feature_names:
    coreml_model.input_description[name] = f"Answer (0 or 1) to question: {name}"

coreml_model.output_description["classLabel"] = "Predicted animal."
if "classScores" in coreml_model.output_description:
    coreml_model.output_description["classScores"] = "Scores (probabilities) for each possible animal."
elif "classProbability" in coreml_model.output_description:
    coreml_model.output_description["classProbability"] = "Scores (probabilities) for each possible animal."

# 5. Save the model
coreml_model.save("Animal20Q.mlmodel")

print("Saved Core ML model as Animal20Q.mlmodel")
