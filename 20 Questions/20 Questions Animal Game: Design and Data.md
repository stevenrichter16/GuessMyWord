20 Questions Animal Game: Design and Data Source

This document explains how a 20 Questions animal guessing game works and describes the data source needed to implement it.  It includes:
	•	An overview of how the game functions.
	•	A complete list of 100 animals supported in the game.
	•	A set of boolean attributes used to distinguish animals.
	•	Natural‑language questions corresponding to each attribute.
	•	Guidelines on the format of the dataset.
	•	A small sample of data to illustrate encoding.
	•	A summary of the question‑asking flow and model usage.

1. Game Concept

A 20 Questions game invites the player to think of an animal from a known set, then answers a series of yes/no questions.  Based on these answers, the game narrows down the list of possible animals until it can confidently guess the correct one.  Each animal is represented by a vector of binary attributes (1 = yes, 0 = no), and the game asks questions corresponding to these attributes.  Unknown or “not sure” responses can be treated as missing values at runtime.

2. Supported Animals

The game recognises the following 100 animals.  Each one will be a row in the dataset:

1. Dog
2. Cat
3. Elephant
4. Lion
5. Tiger
6. Giraffe
7. Zebra
8. Kangaroo
9. Panda
10. Koala
11. Bear
12. Wolf
13. Fox
14. Deer
15. Rabbit
16. Squirrel
17. Hippopotamus
18. Rhinoceros
19. Cheetah
20. Leopard
21. Monkey
22. Gorilla
23. Chimpanzee
24. Orangutan
25. Baboon
26. Bat
27. Dolphin
28. Whale
29. Shark
30. Octopus
31. Squid
32. Seal
33. Walrus
34. Otter
35. Raccoon
36. Skunk
37. Moose
38. Bison
39. Camel
40. Llama
41. Alpaca
42. Donkey
43. Horse
44. Cow
45. Sheep
46. Goat
47. Pig
48. Chicken
49. Duck
50. Goose
51. Turkey
52. Eagle
53. Owl
54. Hawk
55. Falcon
56. Parrot
57. Flamingo
58. Pelican
59. Penguin
60. Swan
61. Crow
62. Pigeon
63. Sparrow
64. Hummingbird
65. Turtle
66. Tortoise
67. Frog
68. Toad
69. Snake
70. Lizard
71. Crocodile
72. Alligator
73. Salamander
74. Newt
75. Ant
76. Bee
77. Wasp
78. Butterfly
79. Moth
80. Beetle
81. Crab
82. Lobster
83. Shrimp
84. Jellyfish
85. Starfish
86. Seahorse
87. Clownfish
88. Tuna
89. Goldfish
90. Carp
91. Hyena
92. Meerkat
93. Lemur
94. Porcupine
95. Hedgehog
96. Hamster
97. Guinea pig
98. Chinchilla
99. Platypus
100. Armadillo

3. Attributes and Questions

Each animal is described by 44 boolean attributes.  These attributes correspond to natural‑language yes/no questions.  The following list shows every attribute key with the question that should be asked to the player:
	•	is_mammal: Is it a mammal?
	•	is_pet: Is it commonly kept as a household pet?
	•	is_wild: Is it mostly found in the wild (not usually living with humans)?
	•	is_large: Is it larger than an average adult human?
	•	is_carnivore: Does it mainly eat meat?
	•	is_herbivore: Does it mainly eat plants?
	•	is_canine: Is it in the dog family (a type of canine)?
	•	is_feline: Is it in the cat family (a type of feline)?
	•	has_stripes: Does it have obvious stripes on its body?
	•	has_long_neck: Does it have a noticeably long neck compared to most animals?
	•	is_marsupial: Is it a marsupial (carries its young in a pouch)?
	•	eats_mostly_bamboo: Does it mainly eat bamboo?
	•	native_to_australia: Is it native to Australia?
	•	lives_in_trees: Does it spend most of its time in trees?
	•	can_fly: Can it naturally fly?
	•	lives_in_water: Does it live mostly in water?
	•	is_bird: Is it a bird?
	•	is_reptile: Is it a reptile (like a snake, lizard, crocodile or turtle)?
	•	has_fur_or_hair: Does it have fur or hair?
	•	has_hooves: Does it have hooves instead of paws or claws?
	•	is_domesticated: Has it been domesticated by humans (kept or bred by people)? Set this to 1 only for species that are fully domesticated; leave it 0 for wild species that are merely kept as pets or in captivity.
	•	is_nocturnal: Is it mostly active at night?
	•	is_amphibian: Is it an amphibian (like a frog, toad or salamander)?
	•	is_fish: Is it a fish?
	•	lays_eggs: Does it usually lay eggs?
	•	has_tail: Does it have a tail?
	•	has_spots: Does it have noticeable spots on its body?
	•	has_horns_or_antlers: Does it have horns or antlers?
	•	has_shell: Does it have a hard shell covering part of its body?
	•	has_fins_or_flippers: Does it have fins or flippers instead of legs?
	•	is_omnivore: Does it eat both plants and animals?
	•	eats_insects: Does it eat insects as a major part of its diet?
	•	is_scavenger: Does it often eat animals that are already dead (scavenge)?
	•	is_predator: Is it a predator that hunts other animals?
	•	lives_in_forest_or_jungle: Is it mainly found in forests or jungles?
	•	lives_in_grassland_or_savanna: Is it mainly found in open grasslands or savannas?
	•	lives_in_desert: Is it adapted to live in the desert or very dry areas?
	•	lives_in_cold_climate: Is it typically found in cold or icy climates?
	•	lives_on_farm: Is it commonly found on farms as livestock or poultry?
	•	lives_in_groups: Does it usually live in groups, herds, packs or flocks?
	•	migrates_seasonally: Does it migrate long distances during certain seasons?
	•	hibernates: Does it hibernate or sleep for long periods in winter?
	•	is_venomous: Is it venomous (can inject venom through fangs, stingers, etc.)?
	•	used_for_work_or_transport: Is it commonly used by humans for work or transport (like riding or carrying loads)?

These attributes are broad enough to differentiate many animals without being so specific that they apply to only one species.  You can always expand the list to improve discrimination (for example, adding new habitat or behavior traits), but avoid duplicate attributes (such as re‑adding has_spots or is_nocturnal, which already exist) and avoid hyper‑specific traits that only one animal in the entire dataset would answer “yes” to.

4. Dataset Format

The data source is a matrix in which each row represents an animal and each column is one of the attributes listed above.
		•	File format: CSV (comma‑separated values) with a header row.  The first column Animal holds the animal name.  The remaining columns correspond to the 44 attributes.
		•	Values: 1 means yes, 0 means no.  At runtime, you may allow the user to answer “not sure”; treat this as a missing value when filtering candidates or building model inputs.
		•	Example header:
Animal,is_mammal,is_pet,is_wild,is_large,is_carnivore,is_herbivore,is_canine,is_feline,has_stripes,has_long_neck,is_marsupial,eats_mostly_bamboo,native_to_australia,lives_in_trees,can_fly,lives_in_water,is_bird,is_reptile,has_fur_or_hair,has_hooves,is_domesticated,is_nocturnal,is_amphibian,is_fish,lays_eggs,has_tail,has_spots,has_horns_or_antlers,has_shell,has_fins_or_flippers,is_omnivore,eats_insects,is_scavenger,is_predator,lives_in_forest_or_jungle,lives_in_grassland_or_savanna,lives_in_desert,lives_in_cold_climate,lives_on_farm,lives_in_groups,migrates_seasonally,hibernates,is_venomous,used_for_work_or_transport
		•	Full dataset: see animals_20q.csv alongside this file (100 rows × 44 attributes).
4.1 Sample Rows

The following snippet shows the first ten animals encoded in this format.  Each row includes the animal name followed by the 44 binary attributes (line breaks added for readability):
Dog,1,1,0,0,1,0,1,0,0,0,0,0,0,0,0,0,0,0,1,0,1,0,0,0,0,1,0,0,0,0,1,0,0,1,0,0,0,0,0,1,0,0,0,1
Cat,1,1,0,0,1,0,0,1,0,0,0,0,0,0,0,0,0,0,1,0,1,1,0,0,0,1,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0
Elephant,1,0,1,1,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,1,0,0,0,1,1,0,0,1
Lion,1,0,1,1,1,0,0,1,0,0,0,0,0,0,0,0,0,0,1,0,0,1,0,0,0,1,0,0,0,0,0,0,0,1,0,1,0,0,0,1,0,0,0,0
Tiger,1,0,1,1,1,0,0,1,1,0,0,0,0,0,0,0,0,0,1,0,0,1,0,0,0,1,0,0,0,0,0,0,0,1,0,1,0,0,0,1,0,0,0,0
Giraffe,1,0,1,1,0,1,0,0,0,1,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,1,0,0,0,1,0,0,0,0
Zebra,1,0,1,1,0,1,0,0,1,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0
Kangaroo,1,0,1,1,0,1,0,0,0,0,1,0,1,0,0,0,0,0,1,0,0,1,0,0,0,1,0,0,0,0,0,0,0,0,0,1,1,0,0,1,0,0,0,0
Panda,1,0,1,1,0,1,0,0,0,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0
Koala,1,0,1,0,0,1,0,0,0,0,1,0,1,1,0,0,0,0,1,0,0,1,0,0,0,1,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0

This sample demonstrates how each animal is encoded.  For example, “Dog” is a mammal (is_mammal = 1), is commonly kept as a pet (is_pet = 1), is not wild (is_wild = 0), and so on.  An actual dataset file would include all 100 animals.

5. Question‑Asking Flow

To play the game, the program maintains the following state:
	1.	Remaining candidates: the list of animals still consistent with the answers so far.
	2.	Asked questions: the set of attributes already queried.
	3.	Answers map: a dictionary mapping each asked attribute to the player’s response (yes, no, or unknown).

5.1 Applying Answers

When the player answers a question:
	•	If the answer is yes, filter the remaining animals to keep only those with a 1 for that attribute.
	•	If the answer is no, filter to keep animals with a 0 for that attribute.
	•	If the answer is not sure, do not filter; instead, leave the candidate list unchanged and record that the attribute is unknown.

5.2 Choosing the Next Question

To efficiently narrow down the list, choose the next question that best balances the remaining candidates.  A simple heuristic is to evaluate each unused attribute and select the one that most evenly splits the remaining animals into “yes” and “no” groups.  Skip attributes where all remaining animals share the same value (no splitting power).

5.3 When to Guess

The program should guess the animal when one of the following is true:
	•	Only one candidate remains.
	•	A fixed maximum number of questions (e.g., 20) has been asked.
	•	A machine‑learning model (such as a decision tree trained on this dataset) is highly confident in its prediction.  Such a model can be trained using the attribute matrix and converted to a Core ML model for use in an iOS app.

5.4 Handling “Not sure”

The game should allow the player to answer “not sure” or skip a question.  In this case, record the response as unknown and do not remove any candidates based on that attribute.  Later questions will provide further evidence to narrow down the list.

6. Using the Data

6.1 Training a Decision Tree

To automate guessing, you can train a decision tree classifier on the full dataset.  Each animal is a class label, and the attributes are features.  A tree algorithm learns how to split on attributes to identify the correct animal.  You can convert this tree to an on‑device model (e.g. Core ML) and use it as a helper for guessing.  It is often best to combine this with the heuristic question‑selection logic described above.

6.2 Integrating with SwiftUI

For an iOS application, you can:
	1.	Store the dataset (perhaps as a JSON or plist).
	2.	Present questions to the player using the human‑friendly text.
	3.	Record answers and update the candidate list.
	4.	Use the heuristic to pick the next question.
	5.	When ready to guess, either:
	•	Take the single remaining candidate, or
	•	Use a Core ML model to get the most likely animal from the current answers.
	6.	Display the guess.
	7.	Allow the player to play again.

This design keeps the game responsive and does not require a network connection, because all inference happens locally.

⸻

By following the structure described above and including all 100 animals with their 44 attributes, you can build a robust 20 Questions animal game.  The dataset can be extended with more animals or refined attributes, and the question selection strategy can be improved (for example, by computing information gain).  Nevertheless, this specification provides a solid foundation for implementing the game and training models that will run efficiently on mobile devices.
