# GOKU-net model
#
# Based on
# https://arxiv.org/abs/2003.10775

struct GOKU <: LatentDE end

@doc raw"""
    apply_feature_extractor(encoder::Encoder{GOKU}, x)

Converts a batch of the initial high-dimensional data into lower-dimensional data (i.e. extracts features)

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, _ = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> encoder = LatentDiffEq.Encoder(GOKU(), encoder_layers)

julia> x = [zeros(Float32,28*28,64) for _ in 1:50]   # Dummy data

julia> fe_out = LatentDiffEq.apply_feature_extractor(encoder, x)
```
"""
apply_feature_extractor(encoder::Encoder{GOKU}, x) = encoder.feature_extractor.(x)

@doc raw"""
    apply_pattern_extractor(encoder::Encoder{GOKU}, fe_out)

Passes features in time series through RNNs, returning a tuple containing patterns for the initial state and the parameters, respectively.

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, _ = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> encoder = LatentDiffEq.Encoder(GOKU(), encoder_layers)

julia> x = [zeros(Float32,28*28,64) for _ in 1:50]   # Dummy data

julia> fe_out = LatentDiffEq.apply_feature_extractor(encoder, x)

julia> pe_out = LatentDiffEq.apply_pattern_extractor(encoder, fe_out)
```
"""
function apply_pattern_extractor(encoder::Encoder{GOKU}, fe_out)
    pe_z₀, pe_θ_forward, pe_θ_backward = encoder.pattern_extractor

    # reverse sequence
    fe_out_rev = reverse(fe_out)

    # pass it through the recurrent layers
    pe_z₀_out = map(pe_z₀, fe_out_rev)[end]
    pe_θ_out_f = map(pe_θ_forward, fe_out)[end]
    pe_θ_out_b = map(pe_θ_backward, fe_out_rev)[end]
    pe_θ_out = vcat(pe_θ_out_f, pe_θ_out_b)

    # reset hidden states
    Flux.reset!(pe_z₀)
    Flux.reset!(pe_θ_forward)
    Flux.reset!(pe_θ_backward)

    return pe_z₀_out, pe_θ_out
end

@doc raw"""
    apply_latent_in(encoder::Encoder{GOKU}, pe_out)

Obtains representations of the mean and log-variance of the initial conditions and parameters to use for sampling.

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, _ = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> encoder = LatentDiffEq.Encoder(GOKU(), encoder_layers)

julia> x = [zeros(Float32,28*28,64) for _ in 1:50]   # Dummy data

julia> fe_out = LatentDiffEq.apply_feature_extractor(encoder, x)

julia> pe_out = LatentDiffEq.apply_pattern_extractor(encoder, fe_out)

julia> μ, logσ² = apply_latent_in(encoder, pe_out)
```
"""
function apply_latent_in(encoder::Encoder{GOKU}, pe_out)
    pe_z₀_out, pe_θ_out = pe_out
    li_μ_z₀, li_logσ²_z₀, li_μ_θ, li_logσ²_θ = encoder.latent_in

    z₀_μ = li_μ_z₀(pe_z₀_out)
    z₀_logσ² = li_logσ²_z₀(pe_z₀_out)

    θ_μ = li_μ_θ(pe_θ_out)
    θ_logσ² = li_logσ²_θ(pe_θ_out)

    return (z₀_μ, θ_μ), (z₀_logσ², θ_logσ²)
end

@doc raw"""
    apply_latent_out(decoder::Decoder{GOKU}, l̃)

Obtains the inferred initial conditions and parameters after sampling.

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, decoder_layers = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> encoder = LatentDiffEq.Encoder(GOKU(), encoder_layers)

julia> decoder = LatentDiffEq.Decoder(GOKU(), decoder_layers)

julia> x = [zeros(Float32,28*28,64) for _ in 1:50]   # Dummy data

julia> μ, logσ² = encoder(x)

julia> l̃ = LatentDiffEq.sample(μ, logσ², model)

julia> l̂ = LatentDiffEq.apply_latent_out(decoder, l̃)
```
"""
function apply_latent_out(decoder::Decoder{GOKU}, l̃)
    z̃₀, θ̃ = l̃
    lo_z₀, lo_θ = decoder.latent_out

    ẑ₀ = lo_z₀(z̃₀)
    θ̂ = lo_θ(θ̃)

    return ẑ₀, θ̂
end

@doc raw"""
    diffeq_layer(decoder::Decoder{GOKU}, l̂, t)

Uses decoder.diffeq's ODE solver to extrapolate the latent states (from the initial states l̂) to time t.

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, decoder_layers = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> encoder = LatentDiffEq.Encoder(GOKU(), encoder_layers)

julia> decoder = LatentDiffEq.Decoder(GOKU(), decoder_layers)

julia> x = [zeros(Float32,28*28,64) for _ in 1:50]   # Dummy data

julia> μ, logσ² = encoder(x)

julia> l̃ = LatentDiffEq.sample(μ, logσ², model)

julia> l̂ = LatentDiffEq.apply_latent_out(decoder, l̃)

julia> ẑ = LatentDiffEq.diffeq_layer(decoder, l̂, t)
```
"""
function diffeq_layer(decoder::Decoder{GOKU}, l̂, t)
    ẑ₀, θ̂ = l̂
    prob = decoder.diffeq.prob
    solver = decoder.diffeq.solver
    sensealg = decoder.diffeq.sensealg
    kwargs = decoder.diffeq.kwargs

    # Function definition for ensemble problem
    prob_func(prob,i,repeat) = remake(prob, u0=ẑ₀[:,i], p = θ̂[:,i])
    
    # Check if solve was successful, if not, return NaNs to avoid problems with dimensions matches
    output_func(sol, i) = sol.retcode == :Success ? (Array(sol), false) : (fill(NaN32,(size(ẑ₀, 1), length(t))), false)

    ## Adapt problem to given time span and create ensemble problem definition
    prob = remake(prob; tspan = (t[1],t[end]))
    ens_prob = EnsembleProblem(prob, prob_func = prob_func, output_func = output_func)

    ## Solve
    ẑ = solve(ens_prob, solver, EnsembleThreads(); sensealg = sensealg, trajectories = size(θ̂, 2), saveat = t, kwargs...)
    
    # Transform the resulting output (mainly used for Kuramoto-like systems)
    ẑ = transform_after_diffeq(ẑ, decoder.diffeq)
    ẑ = Flux.unstack(ẑ, 2)
    return ẑ
end

# Identity by default
transform_after_diffeq(x, diffeq) = x

@doc raw"""
    apply_reconstructor(decoder::Decoder{GOKU}, ẑ)

Reconstruct the initial data from the extrapolated latent states. 

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, decoder_layers = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> encoder = LatentDiffEq.Encoder(GOKU(), encoder_layers)

julia> decoder = LatentDiffEq.Decoder(GOKU(), decoder_layers)

julia> x = [zeros(Float32,28*28,64) for _ in 1:50]   # Dummy data

julia> μ, logσ² = encoder(x)

julia> l̃ = LatentDiffEq.sample(μ, logσ², model)

julia> l̂ = LatentDiffEq.apply_latent_out(decoder, l̃)

julia> ẑ = LatentDiffEq.diffeq_layer(decoder, l̂, t)

julia> x̂ = LatentDiffEq.apply_reconstructor(decoder, ẑ)
```
"""
apply_reconstructor(decoder::Decoder{GOKU}, ẑ) = decoder.reconstructor.(ẑ)

@doc raw"""
    sample(μ::T, logσ²::T, model::LatentDiffEqModel{GOKU}) where T <: Tuple{Array, Array}

Samples the parameters initial state from the normal distribution with mean μ and variance exp(logσ²).

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, decoder_layers = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> model = LatentDiffEqModel(GOKU(), encoder_layers, decoder_layers)

julia> x = [zeros(Float32,28*28,64) for _ in 1:50]   # Dummy data

julia> μ, logσ² = model.encoder(x)

julia> l̃ = LatentDiffEq.sample(μ, logσ², model)
```
"""
function sample(μ::T, logσ²::T, model::LatentDiffEqModel{GOKU}) where T <: Tuple{Array, Array}
    z₀_μ, θ_μ = μ
    z₀_logσ², θ_logσ² = logσ²

    ẑ₀ = z₀_μ + randn(Float32, size(z₀_logσ²)) .* exp.(z₀_logσ²/2f0)
    θ̂ =  θ_μ + randn(Float32, size( θ_logσ²)) .* exp.(θ_logσ²/2f0)

    return ẑ₀, θ̂
end

function sample(μ::T, logσ²::T, model::LatentDiffEqModel{GOKU}) where T <: Tuple{Flux.CUDA.CuArray, Flux.CUDA.CuArray}
    z₀_μ, θ_μ = μ
    z₀_logσ², θ_logσ² = logσ²

    ẑ₀ = z₀_μ + gpu(randn(Float32, size(z₀_logσ²))) .* exp.(z₀_logσ²/2f0)
    θ̂ =  θ_μ + gpu(randn(Float32, size( θ_logσ²))) .* exp.(θ_logσ²/2f0)

    return ẑ₀, θ̂
end

@doc raw"""
    default_layers(model_type::GOKU, input_dim::Int, diffeq, device;
        hidden_dim_resnet = 200, rnn_input_dim = 32,
        rnn_output_dim = 16, latent_dim = 16,
        latent_to_diffeq_dim = 200, θ_activation = softplus,
        output_activation = σ)

Generates default encoder and decoder layers that are to be fed into the LatentDiffEqModel.

# Examples
```julia-repl
julia> using LatentDiffEq, OrdinaryDiffEq, ModelingToolkit, DiffEqSensitivity, Flux

julia> include("pendulum.jl")

julia> encoder_layers, decoder_layers = default_layers(GOKU(), 28*28, Pendulum(), cpu)

julia> model = LatentDiffEqModel(GOKU(), encoder_layers, decoder_layers)
```
"""
function default_layers(model_type::GOKU, input_dim, diffeq, device;
                            hidden_dim_resnet = 200, rnn_input_dim = 32,
                            rnn_output_dim = 16, latent_dim = 16,
                            latent_to_diffeq_dim = 200, θ_activation = softplus,
                            output_activation = σ)

    z_dim = length(diffeq.prob.u0)
    θ_dim = length(diffeq.prob.p)

    ######################
    ### Encoder layers ###
    ######################
    # Resnet
    l1 = Dense(input_dim, hidden_dim_resnet, relu)
    l2 = Dense(hidden_dim_resnet, hidden_dim_resnet, relu)
    l3 = Dense(hidden_dim_resnet, hidden_dim_resnet, relu)
    l4 = Dense(hidden_dim_resnet, rnn_input_dim, relu)
    feature_extractor = Chain(l1,
                                SkipConnection(l2, +),
                                SkipConnection(l3, +),
                                l4) |> device

    # RNN
    pe_z₀ = Chain(RNN(rnn_input_dim, rnn_output_dim, relu),
                       RNN(rnn_output_dim, rnn_output_dim, relu)) |> device
    
    # Bidirectional LSTM
    pe_θ_forward = Chain(LSTM(rnn_input_dim, rnn_output_dim),
                       LSTM(rnn_output_dim, rnn_output_dim)) |> device

    pe_θ_backward = Chain(LSTM(rnn_input_dim, rnn_output_dim),
                        LSTM(rnn_output_dim, rnn_output_dim)) |> device

    pattern_extractor = (pe_z₀, pe_θ_forward, pe_θ_backward)

    # final fully connected layers before sampling
    li_μ_z₀ = Dense(rnn_output_dim, latent_dim) |> device
    li_logσ²_z₀ = Dense(rnn_output_dim, latent_dim) |> device
    
    li_μ_θ = Dense(rnn_output_dim*2, latent_dim) |> device
    li_logσ²_θ = Dense(rnn_output_dim*2, latent_dim) |> device

    latent_in = (li_μ_z₀, li_logσ²_z₀, li_μ_θ, li_logσ²_θ)

    encoder_layers = (feature_extractor, pattern_extractor, latent_in)

    ######################
    ### Decoder layers ###
    ######################

    # after sampling in the latent space but before the differential equation layer
    lo_z₀ = Chain(Dense(latent_dim, latent_to_diffeq_dim, relu),
                        Dense(latent_to_diffeq_dim, z_dim)) |> device

    lo_θ = Chain(Dense(latent_dim, latent_to_diffeq_dim, relu),
                        Dense(latent_to_diffeq_dim, θ_dim, θ_activation)) |> device

    latent_out = (lo_z₀, lo_θ)

    # going back to the input space
    # Resnet
    l1 = Dense(z_dim, hidden_dim_resnet, relu)
    l2 = Dense(hidden_dim_resnet, hidden_dim_resnet, relu)
    l3 = Dense(hidden_dim_resnet, hidden_dim_resnet, relu)
    l4 = Dense(hidden_dim_resnet, input_dim, output_activation)
    reconstructor = Chain(l1,
                            SkipConnection(l2, +),
                            SkipConnection(l3, +),
                            l4)  |> device

    decoder_layers = (latent_out, diffeq, reconstructor)

    return encoder_layers, decoder_layers
end