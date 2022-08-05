module LatentDiffEq

using OrdinaryDiffEq
using DiffEqFlux
using SciMLSensitivity
using Flux
using Statistics
using CUDA

## Types definitions
abstract type LatentDE end

## Models definitions
include("./models/LatentDiffEqModel.jl")
include("./models/GOKU.jl")
include("./models/LatentODE.jl")
export LatentDiffEqModel, GOKU, GOKU_basic, LatentODE
export default_layers

include("./utils/utils.jl")
export vector_mse, kl, vector_kl, frange_cycle_linear
export normalize_to_unit_segment, time_loader, rand_time

end # end LatentDiffEq module
