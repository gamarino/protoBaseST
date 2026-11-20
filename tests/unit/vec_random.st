"EXPECT: ok 6"
"Vectors phase V1 (Addendum V, 2.5 step 2 and 5.1): PBPythonRandom against CPython 3.14's
 random.Random (Modules/_randommodule.c, Lib/random.py), the generator proto_db's _kmeans draws its
 initial centroids from (vector_backends.py:529-530). The expected values were printed by CPython
 3.14 (random.Random(seed).getrandbits(k) and .sample(range(n), k)).

 Checks: seed 0 is a key of one zero word (init_by_array with keyused = 1, not an empty key);
 every other seed is the 32-bit words of its absolute value, least significant first (seeds 1, 7,
 2^32 - 1, 2^32, 2^40, 2^64 + 3); getrandbits for k = 0, 1, 31, 32, 33, 64 and 100 (the multi-word
 path, words drawn least significant first, the last one shifted); _randbelow_with_getrandbits
 (k = n.bit_length(), redrawn while >= n), seen through one-element samples; sample in its pool
 branch (n <= setsize), with k = 0, and k beyond the population refused with CPython's text; sample
 in its selection-set branch (setsize = 21, plus 4 ** ceil(log(3k, 4)) for k > 5), on both sides of
 that threshold (k = 6 at 85 and 86; k = 22 at 277 and 278, setsize 21 + 4^4) and on a population
 of 2^33."
Import from: 'protobase'.
Import from: '_check'.

| c bits refused |
c := Check new.
bits := [:k :m :s | PBPythonRandom bits: k count: m seed: s].
refused := [:aBlock | [aBlock value. nil] on: PBValidationError do: [:e | e return: e messageText]].

c that: 'seed 0 is a key of one zero word'
  is: (bits value: 32 value: 3 value: 0)
  equals: #(3626764237 1654615998 3255389356).

c that: 'a seed is the 32-bit words of its absolute value, least significant first'
  is: ({1. 7. (2 raisedTo: 32) - 1. 2 raisedTo: 32. 2 raisedTo: 40. (2 raisedTo: 64) + 3}
       collect: [:s | bits value: 32 value: 3 value: s])
  equals: {#(577090037 2444712010 3639700191). #(1390851128 4071050724 647892279).
           #(2728839433 2661025012 872737089). #(485306839 1508871100 1794561286).
           #(445128065 1517081360 2880015531). #(3921169615 2134766284 3962962676)}.

c that: 'getrandbits for k = 0, 1, 31, 32, 33, 64 and 100'
  is: (#(0 1 31 32 33 64 100) collect: [:k | bits value: k value: 3 value: 42])
  equals: {#(0 0 0). #(1 0 0). #(1373158606 239081663 53710184). #(2746317213 478163327 107420369).
           #(2746317213 4402387665 1181241943).
           {2053695854357871005. 13679192365072849617. 4517457392071889495}.
           {873491343714207852616756591005. 176140902141063639299770569303. 925123444424254823561077285033}}.

c that: '_randbelow redraws getrandbits(n bit length) while the draw is >= n'
  is: ({1. 2. 3. 5. 1000. (2 raisedTo: 31) + 1. 10 raisedTo: 12}
       collect: [:n | (PBPythonRandom sampleRange: n count: 1 seed: 9) first])
  equals: #(0 1 1 3 474 1988601454 672003499630).

c that: 'sample: the pool branch, k = 0, and k beyond the population refused'
  is: {PBPythonRandom sampleRange: 21 count: 21 seed: 3. PBPythonRandom sampleRange: 85 count: 6 seed: 5.
       PBPythonRandom sampleRange: 10 count: 0 seed: 0. PBPythonRandom sampleRange: 277 count: 22 seed: 5.
       refused value: [PBPythonRandom sampleRange: 3 count: 4 seed: 0].
       refused value: [PBPythonRandom sampleRange: 3 count: -1 seed: 0]}
  equals: {#(7 18 17 4 11 15 10 9 1 13 0 20 19 3 12 5 16 8 6 14 2). #(79 32 45 67 3 59). #().
           #(130 183 271 14 238 127 26 80 57 190 240 126 194 52 274 6 110 208 143 93 199 81).
           'Sample larger than population or is negative'. 'Sample larger than population or is negative'}.

c that: 'sample: the selection-set branch, at its threshold and on a population of 2^33'
  is: {PBPythonRandom sampleRange: 86 count: 6 seed: 5. PBPythonRandom sampleRange: 22 count: 3 seed: 3.
       PBPythonRandom sampleRange: (2 raisedTo: 33) count: 5 seed: 11. PBPythonRandom sampleRange: 278 count: 22 seed: 5}
  equals: {#(79 32 45 83 67 3). #(7 18 17). #(6294919105 2522798642 6493598146 3405809747 4699224467).
           #(130 183 271 14 238 127 26 80 57 190 240 126 194 52 6 110 208 143 93 199 81 36)}.

c report displayNl.
