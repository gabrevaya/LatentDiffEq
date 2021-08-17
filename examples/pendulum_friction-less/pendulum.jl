################################################################################
## Problem Definition -- frictionless pendulum

struct Pendulum{P,S,T,K}

    prob::P
    solver::S
    sensealg::T
    kwargs::K

    function Pendulum(; kwargs...)
        # Parameters and initial conditions only
        # used to initialize the ODE problem
        u₀ = Float32[1.0, 1.0]
        p = Float32[1.]
        tspan = (0.f0, 1.f0)

        # Define differential equations
        function f!(du, u, p, t)
                x, y = u
                G = 10.0f0
                L = p[1]
                
                du[1] = y
                du[2] =  -G/L*sin(x)
        end

        # Build ODE Problem
        _prob = ODEProblem(f!, u₀, tspan, p)

        @info "Optimizing ODE Problem"
        # Make ODE Problem more performant using ModelingToolkit
        # not necessary for this simple pendulum but can very usefull
        # for other more complex systems
        sys = modelingtoolkitize(_prob)
        ODEFunc = ODEFunction(sys, tgrad=true, jac = true, sparse = false, simplify = false)
        prob = ODEProblem(ODEFunc, u₀, tspan, p)

        solver = Tsit5()
        sensalg = BacksolveAdjoint(autojacvec=ReverseDiffVJP(true))

        P = typeof(prob)
        S = typeof(solver)
        T = typeof(sensalg)
        K = typeof(kwargs)
        new{P,S,T,K}(prob, solver, sensalg, kwargs)
    end
    
end

################################################################################
## Problem Definition -- Pendulum with friction

struct Pendulum_friction{P,S,T,K}

    prob::P
    solver::S
    sensealg::T
    kwargs::K

    function Pendulum_friction(; kwargs...)
        # Default parameters and initial conditions
        u₀ = Float32[1.0, 1.0]
        p = Float32[1.]
        tspan = (0.f0, 1.f0)

        # Define differential equations
        function f!(du, u, p, t)
                x, y = u
                G = 10.0f0
                m = 1.0f0
                b = 0.7f0          
                L = p[1]
                
                du[1] = y
                du[2] =  -G/L*sin(x) - (b/m) * y
        end

        # Build ODE Problem
        _prob = ODEProblem(f!, u₀, tspan, p)

        @info "Optimizing ODE Problem"
        sys = modelingtoolkitize(_prob)
        ODEFunc = ODEFunction(sys, tgrad=true, jac = true, sparse = false, simplify = false)
        prob = ODEProblem(ODEFunc, u₀, tspan, p)

        solver = Tsit5()
        # sensalg = BacksolveAdjoint(autojacvec=ReverseDiffVJP(true))
        sensalg = ForwardDiffSensitivity()

        P = typeof(prob)
        S = typeof(solver)
        T = typeof(sensalg)
        K = typeof(kwargs)
        new{P,S,T,K}(prob, solver, sensalg, kwargs)
    end
    
end

###############################################################################
# Problem Definition -- Stochastic Pendulum

struct SPendulum{P,S,T,K}

    prob::P
    solver::S
    sensealg::T
    kwargs::K

    function SPendulum(; kwargs...)
        # Default parameters and initial conditions
        u₀ = Float32[1.0, 1.0]
        p = Float32[1.]
        tspan = (0.f0, 1.f0)

        # Define differential equations
        function f!(du, u, p, t)
                x, y = u
                G = 10.0f0
                L = p[1]
                
                du[1] = y
                du[2] =  -G/L*sin(x)
        end

        # Build ODE Problem
        _prob = ODEProblem(f!, u₀, tspan, p)

        @info "Optimizing ODE Problem"
        sys = modelingtoolkitize(_prob)
        ODEFunc = ODEFunction(sys, tgrad=true, jac = true, sparse = false, simplify = false)
        prob = ODEProblem(ODEFunc, u₀, tspan, p)

        function σ(du,u,p,t)
            du .= 0.01f0
        end

        prob_sde = SDEProblem(prob.f.f, σ, prob.u0, prob.tspan, prob.p, jac = prob.f.jac, tgrad = prob.f.tgrad)

        solver = SOSRI()
        sensalg = ForwardDiffSensitivity()
        # sensalg = InterpolatingAdjoint()
        # sensalg = BacksolveAdjoint(autojacvec=ReverseDiffVJP(true))


        P = typeof(prob_sde)
        S = typeof(solver)
        T = typeof(sensalg)
        K = typeof(kwargs)
        new{P,S,T,K}(prob_sde, solver, sensalg, kwargs)
    end
    
end