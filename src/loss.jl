# linear
function update_grads!(::Type{Linear}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    @inbounds for i in eachindex(y)
        δ𝑤[1, i] = 2 * (p[1, i] - y[i]) * δ𝑤[3, i]
        δ𝑤[2, i] = 2 * δ𝑤[3, i]
    end
end

# logistic - on linear predictor
function update_grads!(::Type{Logistic}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    @inbounds for i in eachindex(y)
        pred = sigmoid(p[1, i])
        δ𝑤[1, i] = (pred - y[i]) * δ𝑤[3, i]
        δ𝑤[2, i] = pred * (1 - pred) * δ𝑤[3, i]
    end
end

# Poisson
function update_grads!(::Type{Poisson}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    @inbounds for i in eachindex(y)
        pred = exp(p[1, i])
        δ𝑤[1, i] = (pred - y[i]) * δ𝑤[3, i]
        δ𝑤[2, i] = pred * δ𝑤[3, i]
    end
end

# Gamma
function update_grads!(::Type{Gamma}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    @inbounds for i in eachindex(y)
        pred = exp(p[1, i])
        δ𝑤[1, i] = 2 * (1 - y[i] / pred) * δ𝑤[3, i]
        δ𝑤[2, i] = 2 * y[i] / pred * δ𝑤[3, i]
    end
end

# Tweedie
function update_grads!(::Type{Tweedie}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    rho = eltype(p)(1.5)
    @inbounds for i in eachindex(y)
        pred = exp(p[1, i])
        δ𝑤[1, i] = 2 * (pred^(2 - rho) - y[i] * pred^(1 - rho)) * δ𝑤[3, i]
        δ𝑤[2, i] =
            2 * ((2 - rho) * pred^(2 - rho) - (1 - rho) * y[i] * pred^(1 - rho)) * δ𝑤[3, i]
    end
end

# L1
function update_grads!(::Type{L1}, δ𝑤::Matrix, p::Matrix, y::Vector; alpha, kwargs...)
    @inbounds for i in eachindex(y)
        δ𝑤[1, i] =
            (alpha * max(y[i] - p[1, i], 0) - (1 - alpha) * max(p[1, i] - y[i], 0)) *
            δ𝑤[3, i]
    end
end

# Softmax
function update_grads!(::Type{Softmax}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    p .= p .- maximum(p, dims = 1)
    sums = sum(exp.(p), dims = 1)
    K = (size(δ𝑤, 1) - 1) ÷ 2
    for i in eachindex(y)
        for k = 1:K
            # δ𝑤[k, i] = (exp(p[k, i]) / sums[i] - (onehot(y[i], 1:K))) * δ𝑤[2 * K + 1, i]
            if k == y[i]
                δ𝑤[k, i] = (exp(p[k, i]) / sums[i] - 1) * δ𝑤[2*K+1, i]
            else
                δ𝑤[k, i] = (exp(p[k, i]) / sums[i]) * δ𝑤[2*K+1, i]
            end
            δ𝑤[k+K, i] = 1 / sums[i] * (1 - exp(p[k, i]) / sums[i]) * δ𝑤[2*K+1, i]
        end
    end
end

# Quantile
function update_grads!(::Type{Quantile}, δ𝑤::Matrix, p::Matrix, y::Vector; alpha, kwargs...)
    @inbounds for i in eachindex(y)
        δ𝑤[1, i] = y[i] > p[1, i] ? alpha * δ𝑤[3, i] : (alpha - 1) * δ𝑤[3, i]
        δ𝑤[2, i] = y[i] - p[1, i] # δ² serves to calculate the quantile value - hence no weighting on δ²
    end
end

# Gaussian - http://jrmeyer.github.io/machinelearning/2017/08/18/mle.html
# pred[i][1] = μ
# pred[i][2] = log(σ)
function update_grads!(::Type{GaussianDist}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    @inbounds @simd for i in eachindex(y)
        # first order
        δ𝑤[1, i] = (p[1, i] - y[i]) / exp(2 * p[2, i]) * δ𝑤[5, i]
        δ𝑤[2, i] = (1 - (p[1, i] - y[i])^2 / exp(2 * p[2, i])) * δ𝑤[5, i]
        # second order
        δ𝑤[3, i] = δ𝑤[5, i] / exp(2 * p[2, i])
        δ𝑤[4, i] = δ𝑤[5, i] * 2 / exp(2 * p[2, i]) * (p[1, i] - y[i])^2
    end
end

# LogisticProb - https://en.wikipedia.org/wiki/Logistic_distribution
# pdf = 
# pred[i][1] = μ
# pred[i][2] = log(s)
function update_grads!(::Type{LogisticDist}, δ𝑤::Matrix, p::Matrix, y::Vector; kwargs...)
    ϵ = eltype(p)(2e-7)
    @inbounds @simd for i in eachindex(y)
        # first order
        δ𝑤[1, i] = -tanh((y[i] - p[1, i]) / (2 * exp(p[2, i]))) * exp(-p[2, i]) * δ𝑤[5, i]
        δ𝑤[2, i] =
            -(
                exp(-p[2, i]) *
                (y[i] - p[1, i]) *
                tanh((y[i] - p[1, i]) / (2 * exp(p[2, i]))) - 1
            ) * δ𝑤[5, i]
        # second order
        δ𝑤[3, i] =
            sech((y[i] - p[1, i]) / (2 * exp(p[2, i])))^2 / (2 * exp(2 * p[2, i])) *
            δ𝑤[5, i]
        δ𝑤[4, i] =
            (
                exp(-2 * p[2, i]) *
                (p[1, i] - y[i]) *
                (p[1, i] - y[i] + exp(p[2, i]) * sinh(exp(-p[2, i]) * (p[1, i] - y[i])))
            ) / (1 + cosh(exp(-p[2, i]) * (p[1, i] - y[i]))) * δ𝑤[5, i]
    end
end

# utility functions
function logit(x::AbstractArray{T}) where {T<:AbstractFloat}
    return logit.(x)
end
@inline function logit(x::T) where {T<:AbstractFloat}
    @fastmath log(x / (1 - x))
end

function sigmoid(x::AbstractArray{T}) where {T<:AbstractFloat}
    return sigmoid.(x)
end
@inline function sigmoid(x::T) where {T<:AbstractFloat}
    @fastmath 1 / (1 + exp(-x))
end

function softmax(x::AbstractVector{T}) where {T<:AbstractFloat}
    x .-= maximum(x)
    x = exp.(x) ./ sum(exp.(x))
    return x
end


##############################
# get the gain metric
##############################
# GradientRegression
function get_gain(
    ::Type{L},
    ∑::Vector{T},
    λ::T,
    K,
) where {L<:GradientRegression,T<:AbstractFloat}
    ∑[1]^2 / (∑[2] + λ * ∑[3]) / 2
end

# GaussianRegression
function get_gain(::Type{L}, ∑::Vector{T}, λ::T, K) where {L<:MLE2P,T<:AbstractFloat}
    (∑[1]^2 / (∑[3] + λ * ∑[5]) + ∑[2]^2 / (∑[4] + λ * ∑[5])) / 2
end

# MultiClassRegression
function get_gain(
    ::Type{L},
    ∑::Vector{T},
    λ::T,
    K,
) where {L<:MultiClassRegression,T<:AbstractFloat}
    gain = zero(T)
    @inbounds for k = 1:K
        gain += ∑[k]^2 / (∑[k+K] + λ * ∑[2*K+1]) / 2
    end
    return gain
end

# QuantileRegression
function get_gain(
    ::Type{L},
    ∑::Vector{T},
    λ::T,
    K,
) where {L<:QuantileRegression,T<:AbstractFloat}
    abs(∑[1])
end

# L1 Regression
function get_gain(::Type{L}, ∑::Vector{T}, λ::T, K) where {L<:L1Regression,T<:AbstractFloat}
    abs(∑[1])
end


function update_childs_∑!(
    ::Type{L},
    nodes,
    n,
    bin,
    feat,
    K,
) where {L<:Union{GradientRegression,QuantileRegression,L1Regression}}
    nodes[n<<1].∑ .= nodes[n].hL[feat][(3*bin-2):(3*bin)]
    nodes[n<<1+1].∑ .= nodes[n].hR[feat][(3*bin-2):(3*bin)]
    return nothing
end

function update_childs_∑!(::Type{L}, nodes, n, bin, feat, K) where {L<:MLE2P}
    nodes[n<<1].∑ .= nodes[n].hL[feat][(5*bin-4):(5*bin)]
    nodes[n<<1+1].∑ .= nodes[n].hR[feat][(5*bin-4):(5*bin)]
    return nothing
end

function update_childs_∑!(::Type{L}, nodes, n, bin, feat, K) where {L<:MultiClassRegression}
    KK = 2 * K + 1
    nodes[n<<1].∑ .= nodes[n].hL[feat][(KK*(bin-1)+1):(KK*bin)]
    nodes[n<<1+1].∑ .= nodes[n].hR[feat][(KK*(bin-1)+1):(KK*bin)]
    return nothing
end