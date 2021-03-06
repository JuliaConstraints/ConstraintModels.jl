
sudoku_start = [
    9  3  0  0  0  0  0  4  0
    0  0  0  0  4  2  0  9  0
    8  0  0  1  9  6  7  0  0
    0  0  0  4  7  0  0  0  0
    0  2  0  0  0  0  0  6  0
    0  0  0  0  2  3  0  0  0
    0  0  8  5  3  1  0  0  2
    0  9  0  2  8  0  0  0  0
    0  7  0  0  0  0  0  5  3
]

qap_weights = [
    0  1  2  2  3  4  4  5  3  5  6  7
    1  0  1  1  2  3  3  4  2  4  5  6
    2  1  0  2  1  2  2  3  1  3  4  5
    2  1  2  0  1  2  2  3  3  3  4  5
    3  2  1  1  0  1  1  2  2  2  3  4
    4  3  2  2  1  0  2  3  3  1  2  3
    4  3  2  2  1  2  0  1  3  1  2  3
    5  4  3  3  2  3  1  0  4  2  1  2
    3  2  1  3  2  3  3  4  0  4  5  6
    5  4  3  3  2  1  1  2  4  0  1  2
    6  5  4  4  3  2  2  1  5  1  0  1
    7  6  5  5  4  3  3  2  6  2  1  0
]

qap_distances = [
    0  3  4  6  8  5  6  6  5  1  4  6
    3  0  6  3  7  9  9  2  2  7  4  7
    4  6  0  2  6  4  4  4  2  6  3  6
    6  3  2  0  5  5  3  3  9  4  3  6
    8  7  6  5  0  4  3  4  5  7  6  7
    5  9  4  5  4  0  8  5  5  5  7  5
    6  9  4  3  3  8  0  6  8  4  6  7
    6  2  4  3  4  5  6  0  1  5  5  3
    5  2  2  9  5  5  8  1  0  4  5  2
    1  7  6  4  7  5  4  5  4  0  7  7
    4  4  3  3  6  7  6  5  5  7  0  9
    6  7  6  6  7  5  7  3  2  7  9  0
]

atoms_compounds = [
    1 0 0
    2 0 0
    2 0 1
    0 1 0
    0 2 0
    1 1 0
    0 1 1
    0 0 1
    0 0 2
    1 0 1
]

elements_weights = [2 1 1]

standard_free_energy = [
    -6.0890
    -17.164
    -34.054
    -5.9140
    -24.721
    -14.986
    -24.100
    -10.708
    -26.662
    -22.179
]

compounds_names = "x₁⋅H + x₂⋅H₂ + x₃⋅H₂O + x₄⋅N + x₅⋅N₂ + x₆⋅NH + x₇⋅NO + x₈⋅O + x₉⋅O₂ + x₁₀⋅OH"

mixture_name =  "½⋅N₂H₄ + ½⋅O₂"

equation = compounds_names * " = " * mixture_name

processing_times = [3, 2, 1]
due_times = [5, 6, 8]
