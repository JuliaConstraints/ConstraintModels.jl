# ConstraintModels

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaConstraints.github.io/ConstraintModels.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaConstraints.github.io/ConstraintModels.jl/dev)
[![Build Status](https://github.com/JuliaConstraints/ConstraintModels.jl/workflows/CI/badge.svg)](https://github.com/JuliaConstraints/ConstraintModels.jl/actions)
[![codecov](https://codecov.io/gh/JuliaConstraints/ConstraintModels.jl/branch/main/graph/badge.svg?token=4u3yBCTDYG)](https://codecov.io/gh/JuliaConstraints/ConstraintModels.jl)
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)
[![ColPrac: Contributor's Guide on Collaborative Practices for Community Packages](https://img.shields.io/badge/ColPrac-Contributor's%20Guide-blueviolet)](https://github.com/SciML/ColPrac)

## Reconstructed PDPTW benchmark semantics

`ConstraintModels.Benchmarks` provides a versioned Li-Lim reader and independent
route validator. The earlier local `src/benchmarks` sources referenced by the
private Benchmarks repository were absent from its available dependency history.
This is a new minimal implementation, not a byte-identical restoration.

It checks unique service, fleet, same-route requests, precedence, capacity,
time windows and depot return. Route entries are exact integer indices; solver
values are never rounded to repair an invalid solution. Travel time and distance
use unrounded Euclidean Float64 values. The speed field is retained but ignored,
as specified by [SINTEF's format documentation](https://www.sintef.no/projectweb/top/pdptw/documentation/).
Source ids are preserved separately from internal one-based indices.

```julia
using ConstraintModels.Benchmarks
p = read_benchmark("lc101.txt", :li_lim)
result = validate_solution(p, routes) # routes omit depot 1
```

The standalone semantic checks run with
`julia --startup-file=no test/pdptw_semantics.jl` (25 assertions). The reconstructed
reader also accepts the original lc101, lr101 and lrc101 files (53 requests each).
The explicit `perf/pdptw` Project and Manifest freeze the current development
cohort for the RO qualification and bounded prototype in the private Benchmarks
repository. Packages are sibling checkouts under `~/.julia/dev`.
These finite checks do not qualify other routing formats or the lost historical
launcher environment.
