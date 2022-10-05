function MMI.fit(model::EvoTypes, verbosity::Int, A, y)
  if model.device == "gpu"
    fitresult, cache = init_evotree_gpu(model, A.matrix, y)
  else
    fitresult, cache = init_evotree(model, A.matrix, y)
  end
  grow_evotree!(fitresult, cache)
  report = (features=A.names,)
  return fitresult, cache, report
end

function okay_to_continue(new, old)
  new.nrounds - old.nrounds >= 0 &&
    new.lambda == old.lambda &&
    new.gamma == old.gamma &&
    new.max_depth == old.max_depth &&
    new.min_weight == old.min_weight &&
    new.rowsample == old.rowsample &&
    new.colsample == old.colsample &&
    new.nbins == old.nbins &&
    new.alpha == old.alpha &&
    new.device == old.device
end


# Generate names to be used by feature_importances in the report
MMI.reformat(::EvoTypes, X, y) = ((matrix=MMI.matrix(X), names=[name for name ∈ schema(X).names]), y)
MMI.reformat(::EvoTypes, X) = ((matrix=MMI.matrix(X), names=[name for name ∈ schema(X).names]),)
MMI.reformat(::EvoTypes, X::AbstractMatrix, y) = ((matrix=X, names=["feat_$i" for i = 1:size(X, 2)]), y)
MMI.reformat(::EvoTypes, X::AbstractMatrix) = ((matrix=X, names=["feat_$i" for i = 1:size(X, 2)]),)
MMI.selectrows(::EvoTypes, I, A, y) = ((matrix=view(A.matrix, I, :), names=A.names), view(y, I))
MMI.selectrows(::EvoTypes, I, A) = ((matrix=view(A.matrix, I, :), names=A.names),)

# For EarlyStopping.jl support
MMI.iteration_parameter(::Type{<:EvoTypes}) = :nrounds

function MMI.update(model::EvoTypes, verbosity::Integer, fitresult, cache, A, y)
  if okay_to_continue(model, cache.params)
    grow_evotree!(fitresult, cache)
  else
    fitresult, cache = init_evotree(model, A.matrix, y)
    grow_evotree!(fitresult, cache)
  end
  report = (features=A.names,)
  return fitresult, cache, report
end

function predict(::EvoTreeRegressor, fitresult, A)
  pred = vec(predict(fitresult, A.matrix))
  return pred
end

function predict(::EvoTreeClassifier, fitresult, A)
  pred = predict(fitresult, A.matrix)
  return MMI.UnivariateFinite(fitresult.levels, pred, pool=missing)
end

function predict(::EvoTreeCount, fitresult, A)
  λs = vec(predict(fitresult, A.matrix))
  return [Distributions.Poisson(λ) for λ ∈ λs]
end

function predict(::EvoTreeGaussian, fitresult, A)
  pred = predict(fitresult, A.matrix)
  return [Distributions.Normal(pred[i, 1], pred[i, 2]) for i in axes(pred, 1)]
end


# Feature Importances
MMI.reports_feature_importances(::Type{<:EvoTypes}) = true

function MMI.feature_importances(m::EvoTypes, fitresult, report)
  fi_pairs = importance(fitresult, report.features)
  return fi_pairs
end


# Metadata
const EvoTreeRegressor_desc = "Regression models with various underlying methods: least square, quantile, logistic, gamma, tweedie."
const EvoTreeClassifier_desc = "Multi-classification with softmax and cross-entropy loss."
const EvoTreeCount_desc = "Poisson regression fitting λ with max likelihood."
const EvoTreeGaussian_desc = "Gaussian maximum likelihood of μ and σ."

MMI.metadata_pkg.((EvoTreeRegressor, EvoTreeClassifier, EvoTreeCount, EvoTreeGaussian),
  name="EvoTrees",
  uuid="f6006082-12f8-11e9-0c9c-0d5d367ab1e5",
  url="https://github.com/Evovest/EvoTrees.jl",
  julia=true,
  license="Apache",
  is_wrapper=false)

MMI.metadata_model(EvoTreeRegressor,
  input_scitype=Union{MMI.Table(MMI.Continuous, MMI.Count, MMI.OrderedFactor),AbstractMatrix{MMI.Continuous}},
  target_scitype=AbstractVector{<:MMI.Continuous},
  weights=false,
  path="EvoTrees.EvoTreeRegressor",
  descr=EvoTreeRegressor_desc)

MMI.metadata_model(EvoTreeClassifier,
  input_scitype=Union{MMI.Table(MMI.Continuous, MMI.Count, MMI.OrderedFactor),AbstractMatrix{MMI.Continuous}},
  target_scitype=AbstractVector{<:MMI.Finite},
  weights=false,
  path="EvoTrees.EvoTreeClassifier",
  descr=EvoTreeClassifier_desc)

MMI.metadata_model(EvoTreeCount,
  input_scitype=Union{MMI.Table(MMI.Continuous, MMI.Count, MMI.OrderedFactor),AbstractMatrix{MMI.Continuous}},
  target_scitype=AbstractVector{<:MMI.Count},
  weights=false,
  path="EvoTrees.EvoTreeCount",
  descr=EvoTreeCount_desc)

MMI.metadata_model(EvoTreeGaussian,
  input_scitype=Union{MMI.Table(MMI.Continuous, MMI.Count, MMI.OrderedFactor),AbstractMatrix{MMI.Continuous}},
  target_scitype=AbstractVector{<:MMI.Continuous},
  weights=false,
  path="EvoTrees.EvoTreeGaussian",
  descr=EvoTreeGaussian_desc)

"""
  EvoTreeRegressor(;kwargs...)

A model type for constructing a EvoTreeRegressor, based on [EvoTrees.jl](https://github.com/Evovest/EvoTrees.jl), and implementing both an internal API and the MLJ model interface.
EvoTreeRegressor is used to perform the following regression types:
  - linear
  - logistic
  - Gamma
  - Tweedie
  - Quantile
  - L1

# Hyper-parameters

- `loss=:linear`:         Loss to be be minimized during training. One of:

  - `:linear`
  - `:logistic`
  - `:gamma`
  - `tweedie`
  - `:quantile`
  - `:L1`
- `nrounds=10`:           Number of rounds. It corresponds to the number of trees that will be sequentially stacked.
- `lambda::T=0.0`:        L2 regularization term on weights. Must be >= 0. Higher lambda can result in a more robust model.
- `gamma::T=0.0`:         Minimum gain improvement needed to perform a node split. Higher gamma can result in a more robust model.
- `alpha::T=0.5`:         Loss specific parameter in the [0, 1] range:
                            - `:quantile`: target quantile for the regression.
                            - `:L1`: weighting parameters to positive vs negative residuals.
                                  - Positive residual weights = `alpha`
                                  - Negative residual weights = `(1 - alpha)`
- `max_depth=5`:          Maximum depth of a tree. Must be >= 1. A tree of depth 1 is made of a single prediction leaf.
  A complete tree of depth N contains `2^(N - 1)` terminal leaves and `2^(N - 1) - 1` split nodes.
  Compute cost is proportional to `2^max_depth`. Typical optimal values are in the 3 to 9 range.
- `min_weight=0.0`:       Minimum weight needed in a node to perform a split. Matches the number of observations by default or the sum of weights as provided by the `weights` vector.
- `rowsample=1.0`:        Proportion of rows that are sampled at each iteration to build the tree. Should be in `]0, 1]`.
- `colsample=1.0`:        Proportion of columns / features that are sampled at each iteration to build the tree. Should be in `]0, 1]`.
- `nbins=32`:             Number of bins into which each feature is quantized. Buckets are defined based on quantiles, hence resulting in equal weight bins.
- `monotone_constraints=Dict{Int, Int}()`: Specify monotonic constraints using a dict where the key is the feature index and the value the applicable constraint (-1=decreasing, 0=none, 1=increasing). 
  Only `:linear`, `:logistic`, `:gamma` and `tweedie` losses are supported at the moment.
- `rng=123`:              Either an integer used as a seed to the random number generator or an actual random number generator (`::Random.AbstractRNG`).
- `metric::Symbol=:none`: Metric that is to be tracked during the training process. One of: `:none`, `:mse`, `:mae`, `:logloss`, `:gamma`, `:tweedie`.
- `device="cpu"`:         Hardware device to use for computations. Can be either `"cpu"` or `"gpu"`. Only `:linear`, `:logistic`, `:gamma` and `tweedie` losses are supported on GPU.

# Internal API

Do `params = EvoTreeRegressor()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in EvoTreeRegressor(loss=...).

## Training model

A model is built using [`fit_evotree`](@ref):

```julia
model = fit_evotree(params, X_train, Y_train, W_train=nothing; kwargs...).
```

## Inference

Predictions are obtained using [`predict`](@ref) which returns a `Matrix` of size `[nobs, 1]`:

```julia
EvoTrees.predict(model, X)
```

# MLJ Interface

From MLJ, the type can be imported using:

```julia
EvoTreeRegressor = @load EvoTreeRegressor pkg=EvoTrees
```

Do `model = EvoTreeRegressor()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in `EvoTreeRegressor(loss=...)`.

## Training model

In MLJ or MLJBase, bind an instance `model` to data with
    `mach = machine(model, X, y)` where
- `X`: any table of input features (eg, a `DataFrame`) whose columns
  each have one of the following element scitypes: `Continuous`,
  `Count`, or `<:OrderedFactor`; check column scitypes with `schema(X)`
- `y`: is the target, which can be any `AbstractVector` whose element
  scitype is `<:Continuous`; check the scitype
  with `scitype(y)`

Train the machine using `fit!(mach, rows=...)`.

## Operations

- `predict(mach, Xnew)`: return predictions of the target given
  features `Xnew` having the same scitype as `X` above. Predictions
  are deterministic.

## Fitted parameters

The fields of `fitted_params(mach)` are:
  - `:fitresult`: The `GBTree` object returned by EvoTrees.jl fitting algorithm.

## Report

The fields of `report(mach)` are:
  - `:features`: The names of the features encountered in training.

# Examples

```
# Internal API
using EvoTrees
params = EvoTreeRegressor(max_depth=5, nbins=32, nrounds=100)
nobs, nfeats = 1_000, 5
X, y = randn(nobs, nfeats), rand(nobs)
model = fit_evotree(params, X, y)
preds = EvoTrees.predict(model, X)
```

```
# MLJ Interface
using MLJ
EvoTreeRegressor = @load EvoTreeRegressor pkg=EvoTrees
model = EvoTreeRegressor(max_depth=5, nbins=32, nrounds=100)
X, y = @load_boston
mach = machine(model, X, y) |> fit!
preds = predict(mach, X)
```
"""
EvoTreeRegressor


"""
  EvoTreeClassifier(;kwargs...)

A model type for constructing a EvoTreeClassifier, based on [EvoTrees.jl](https://github.com/Evovest/EvoTrees.jl), and implementing both an internal API and the MLJ model interface.
EvoTreeClassifier is used to perform multi-class classification, using cross-entropy loss.

# Hyper-parameters

- `loss::Symbol=:softmax`:      Fixed to `softmax` by default.
- `nrounds=10`:                 Number of rounds. It corresponds to the number of trees that will be sequentially stacked.
- `lambda::T=0.0`:              L2 regularization term on weights. Must be >= 0. Higher lambda can result in a more robust model.
- `gamma::T=0.0`:               Minimum gain improvement needed to perform a node split. Higher gamma can result in a more robust model.
- `max_depth=5`:                Maximum depth of a tree. Must be >= 1. A tree of depth 1 is made of a single prediction leaf.
  A complete tree of depth N contains `2^(N - 1)` terminal leaves and `2^(N - 1) - 1` split nodes.
  Compute cost is proportional to `2^max_depth`. Typical optimal values are in the 3 to 9 range.
- `min_weight=0.0`:             Minimum weight needed in a node to perform a split. Matches the number of observations by default or the sum of weights as provided by the `weights` vector.
- `rowsample=1.0`:              Proportion of rows that are sampled at each iteration to build the tree. Should be in `]0, 1]`.
- `colsample=1.0`:              Proportion of columns / features that are sampled at each iteration to build the tree. Should be in `]0, 1]`.
- `nbins=32`:                   Number of bins into which each feature is quantized. Buckets are defined based on quantiles, hence resulting in equal weight bins.
- `rng=123`:                    Either an integer used as a seed to the random number generator or an actual random number generator (`::Random.AbstractRNG`).
- `metric::Symbol=:none`:       Metric that is to be tracked during the training process. One of: `:none`, `:mlogloss`.
- `device="cpu"`:               Hardware device to use for computations. Only CPU is supported at the moment.

# Internal API

Do `params = EvoTreeClassifier()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in EvoTreeClassifier(max_depth=...).

## Training model

A model is built using [`fit_evotree`](@ref):

```julia
model = fit_evotree(params, X_train, Y_train, W_train=nothing; kwargs...).
```

## Inference

Predictions are obtained using [`predict`](@ref) which returns a `Matrix` of size `[nobs, K]` where `K` is the number of classes:

```julia
EvoTrees.predict(model, X)
```

# MLJ

From MLJ, the type can be imported using:

```julia
EvoTreeClassifier = @load EvoTreeClassifier pkg=EvoTrees
```

Do `model = EvoTreeClassifier()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in `EvoTreeClassifier(loss=...)`.

## Training data

In MLJ or MLJBase, bind an instance `model` to data with

    mach = machine(model, X, y)

where

- `X`: any table of input features (eg, a `DataFrame`) whose columns
  each have one of the following element scitypes: `Continuous`,
  `Count`, or `<:OrderedFactor`; check column scitypes with `schema(X)`
- `y`: is the target, which can be any `AbstractVector` whose element
  scitype is `<:Multiclas` or `<:OrderedFactor`; check the scitype
  with `scitype(y)`
Train the machine using `fit!(mach, rows=...)`.

## Operations

- `predict(mach, Xnew)`: return predictions of the target given features `Xnew` having the same scitype as `X` above.
  Predictions are probabilistic.

- `predict_mode(mach, Xnew)`: returns the mode of each of the prediction above.

## Fitted parameters

The fields of `fitted_params(mach)` are:
  - `:fitresult`: The `GBTree` object returned by EvoTrees.jl fitting algorithm.

## Report

The fields of `report(mach)` are:
  - `:features`: The names of the features encountered in training.

# Examples

```
# Internal API
using EvoTrees
params = EvoTreeClassifier(max_depth=5, nbins=32, nrounds=100)
nobs, nfeats = 1_000, 5
X, y = randn(nobs, nfeats), rand(1:3, nobs)
model = fit_evotree(params, X, y)
preds = EvoTrees.predict(model, X)
```

```
# MLJ Interface
using MLJ
EvoTreeClassifier = @load EvoTreeClassifier pkg=EvoTrees
model = EvoTreeClassifier(max_depth=5, nbins=32, nrounds=100)
X, y = @load_iris
mach = machine(model, X, y) |> fit!
preds = predict(mach, X)
preds = predict_mode(mach, X)
```

See also
[EvoTrees.jl](https://github.com/Evovest/EvoTrees.jl).
"""
EvoTreeClassifier

"""
  EvoTreeCount(;kwargs...)

A model type for constructing a EvoTreeCount, based on [EvoTrees.jl](https://github.com/Evovest/EvoTrees.jl), and implementing both an internal API the MLJ model interface.
EvoTreeCount is used to perform Poisson probabilistic regression on count target.

# Hyper-parameters

- `loss::Symbol=:poisson`:      Fixed to `poisson` by default.
- `nrounds=10`:                 Number of rounds. It corresponds to the number of trees that will be sequentially stacked.
- `lambda::T=0.0`:              L2 regularization term on weights. Must be >= 0. Higher lambda can result in a more robust model.
- `gamma::T=0.0`:               Minimum gain imprvement needed to perform a node split. Higher gamma can result in a more robust model.
- `max_depth=5`:                Maximum depth of a tree. Must be >= 1. A tree of depth 1 is made of a single prediction leaf.
  A complete tree of depth N contains `2^(N - 1)` terminal leaves and `2^(N - 1) - 1` split nodes.
  Compute cost is proportional to 2^max_depth. Typical optimal values are in the 3 to 9 range.
- `min_weight=0.0`:             Minimum weight needed in a node to perform a split. Matches the number of observations by default or the sum of weights as provided by the `weights` vector.
- `rowsample=1.0`:              Proportion of rows that are sampled at each iteration to build the tree. Should be `]0, 1]`.
- `colsample=1.0`:              Proportion of columns / features that are sampled at each iteration to build the tree. Should be `]0, 1]`.
- `nbins=32`:                   Number of bins into which each feature is quantized. Buckets are defined based on quantiles, hence resulting in equal weight bins.
- `monotone_constraints=Dict{Int, Int}()`: Specify monotonic constraints using a dict where the key is the feature index and the value the applicable constraint (-1=decreasing, 0=none, 1=increasing).
- `rng=123`:                    Either an integer used as a seed to the random number generator or an actual random number generator (`::Random.AbstractRNG`).
- `metric::Symbol=:none`:       Metric that is to be tracked during the training process. One of: `:none`, `:poisson`, `:mae`, `:mse`.
- `device="cpu"`:               Hardware device to use for computations. Can be either `"cpu"` or `"gpu"`.

# Internal API

Do `params = EvoTreeCount()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in EvoTreeCount(max_depth=...).

## Training model

A model is built using [`fit_evotree`](@ref):

```julia
model = fit_evotree(params, X_train, Y_train, W_train=nothing; kwargs...).
```

## Inference

Predictions are obtained using [`predict`](@ref) which returns a `Matrix` of size `[nobs, 1]`:

```julia
EvoTrees.predict(model, X)
```

# MLJ

From MLJ, the type can be imported using:

```julia
EvoTreeCount = @load EvoTreeCount pkg=EvoTrees
```

Do `model = EvoTreeCount()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in `EvoTreeCount(loss=...)`.

## Training data

In MLJ or MLJBase, bind an instance `model` to data with
    mach = machine(model, X, y)
where
- `X`: any table of input features (eg, a `DataFrame`) whose columns
  each have one of the following element scitypes: `Continuous`,
  `Count`, or `<:OrderedFactor`; check column scitypes with `schema(X)`
- `y`: is the target, which can be any `AbstractVector` whose element
  scitype is `<:Count`; check the scitype
  with `scitype(y)`
Train the machine using `fit!(mach, rows=...)`.

# Operations

- `predict(mach, Xnew)`: returns a vector of Poisson distributions given features `Xnew`
  having the same scitype as `X` above. Predictions are probabilistic.

Specific metrics can also be predicted using:

  - `predict_mean(mach, Xnew)`
  - `predict_mode(mach, Xnew)`
  - `predict_median(mach, Xnew)`

## Fitted parameters

The fields of `fitted_params(mach)` are:
  - `:fitresult`: The `GBTree` object returned by EvoTrees.jl fitting algorithm.

## Report

The fields of `report(mach)` are:
  - `:features`: The names of the features encountered in training.

# Examples

```
# Internal API
using EvoTrees
params = EvoTreeCount(max_depth=5, nbins=32, nrounds=100)
nobs, nfeats = 1_000, 5
X, y = randn(nobs, nfeats), rand(0:2, nobs)
model = fit_evotree(params, X, y)
preds = EvoTrees.predict(model, X)
```

```
using MLJ
EvoTreeCount = @load EvoTreeCount pkg=EvoTrees
model = EvoTreeCount(max_depth=5, nbins=32, nrounds=100)
nobs, nfeats = 1_000, 5
X, y = randn(nobs, nfeats), rand(0:2, nobs)
mach = machine(model, X, y) |> fit!
preds = predict(mach, X)
preds = predict_mean(mach, X)
preds = predict_mode(mach, X)
preds = predict_median(mach, X)

```

See also
[EvoTrees.jl](https://github.com/Evovest/EvoTrees.jl).
"""
EvoTreeCount

"""
  EvoTreeGaussian(;kwargs...)

A model type for constructing a EvoTreeGaussian, based on [EvoTrees.jl](https://github.com/Evovest/EvoTrees.jl), and implementing both an internal API the MLJ model interface.
EvoTreeGaussian is used to perform Gaussain probabilistic regression, fitting μ and σ parameters to maximize likelihood.

# Hyper-parameters

- `loss::Symbol=:gaussian`:     Fixed to `gaussian` by default.
- `nrounds=10`:                 Number of rounds. It corresponds to the number of trees that will be sequentially stacked.
- `lambda::T=0.0`:              L2 regularization term on weights. Must be >= 0. Higher lambda can result in a more robust model.
- `gamma::T=0.0`:               Minimum gain imprvement needed to perform a node split. Higher gamma can result in a more robust model.
- `max_depth=5`:                Maximum depth of a tree. Must be >= 1. A tree of depth 1 is made of a single prediction leaf.
  A complete tree of depth N contains `2^(N - 1)` terminal leaves and `2^(N - 1) - 1` split nodes.
  Compute cost is proportional to 2^max_depth. Typical optimal values are in the 3 to 9 range.
- `min_weight=0.0`:             Minimum weight needed in a node to perform a split. Matches the number of observations by default or the sum of weights as provided by the `weights` vector.
- `rowsample=1.0`:              Proportion of rows that are sampled at each iteration to build the tree. Should be in `]0, 1]`.
- `colsample=1.0`:              Proportion of columns / features that are sampled at each iteration to build the tree. Should be in `]0, 1]`.
- `nbins=32`:                   Number of bins into which each feature is quantized. Buckets are defined based on quantiles, hence resulting in equal weight bins.
- `monotone_constraints=Dict{Int, Int}()`: Specify monotonic constraints using a dict where the key is the feature index and the value the applicable constraint (-1=decreasing, 0=none, 1=increasing). 
  !Experimental feature: note that for Gaussian regression, constraints may not be enforce systematically.
- `rng=123`:                    Either an integer used as a seed to the random number generator or an actual random number generator (`::Random.AbstractRNG`).
- `metric::Symbol=:none`:       Metric that is to be tracked during the training process. One of: `:none`, `:gaussian`.
- `device="cpu"`:               Hardware device to use for computations. Can be either `"cpu"` or `"gpu"`.

# Internal API

Do `params = EvoTreeGaussian()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in EvoTreeGaussian(max_depth=...).

## Training model

A model is built using [`fit_evotree`](@ref):

```julia
fit_evotree(params, X_train, Y_train, W_train=nothing; kwargs...).
```

## Inference

Predictions are obtained using [`predict`](@ref) which returns a `Matrix` of size `[nobs, 2]` where the second dimensions refer to `μ` and `σ` respectively:

```julia
EvoTrees.predict(model, X)
```

# MLJ

From MLJ, the type can be imported using:

```julia
EvoTreeGaussian = @load EvoTreeGaussian pkg=EvoTrees
```

Do `model = EvoTreeGaussian()` to construct an instance with default hyper-parameters.
Provide keyword arguments to override hyper-parameter defaults, as in `EvoTreeGaussian(loss=...)`.

## Training data

In MLJ or MLJBase, bind an instance `model` to data with

    mach = machine(model, X, y)

where

- `X`: any table of input features (eg, a `DataFrame`) whose columns
  each have one of the following element scitypes: `Continuous`,
  `Count`, or `<:OrderedFactor`; check column scitypes with `schema(X)`

- `y`: is the target, which can be any `AbstractVector` whose element
  scitype is `<:Continuous`; check the scitype
  with `scitype(y)`

Train the machine using `fit!(mach, rows=...)`.

## Operations

- `predict(mach, Xnew)`: returns a vector of Gaussian distributions given features `Xnew` having the same scitype as `X` above.
Predictions are probabilistic.

Specific metrics can also be predicted using:

  - `predict_mean(mach, Xnew)`
  - `predict_mode(mach, Xnew)`
  - `predict_median(mach, Xnew)`

## Fitted parameters

The fields of `fitted_params(mach)` are:

  - `:fitresult`: The `GBTree` object returned by EvoTrees.jl fitting algorithm.

## Report

The fields of `report(mach)` are:
  - `:features`: The names of the features encountered in training.

# Examples

```
# Internal API
using EvoTrees
params = EvoTreeGaussian(max_depth=5, nbins=32, nrounds=100)
nobs, nfeats = 1_000, 5
X, y = randn(nobs, nfeats), rand(nobs)
model = fit_evotree(params, X, y)
preds = EvoTrees.predict(model, X)
```

```
# MLJ Interface
using MLJ
EvoTreeGaussian = @load EvoTreeGaussian pkg=EvoTrees
model = EvoTreeGaussian(max_depth=5, nbins=32, nrounds=100)
X, y = @load_boston
mach = machine(model, X, y) |> fit!
preds = predict(mach, X)
preds = predict_mean(mach, X)
preds = predict_mode(mach, X)
preds = predict_median(mach, X)
```
"""
EvoTreeGaussian

# function MLJ.clean!(model::EvoTreeRegressor)
#     warning = ""
#     if model.nrounds < 1
#         warning *= "Need nrounds ≥ 1. Resetting nrounds=1. "
#         model.nrounds = 1
#     end
#     if model.lambda < 0
#         warning *= "Need lambda ≥ 0. Resetting lambda=0. "
#         model.lambda = 0.0
#     end
#     if model.gamma < 0
#         warning *= "Need gamma ≥ 0. Resetting gamma=0. "
#         model.gamma = 0.0
#     end
#     if model.η <= 0
#         warning *= "Need η > 0. Resetting η=0.001. "
#         model.η = 0.001
#     end
#     if model.max_depth < 1
#         warning *= "Need max_depth ≥ 0. Resetting max_depth=0. "
#         model.max_depth = 1
#     end
#     if model.min_weight < 0
#         warning *= "Need min_weight ≥ 0. Resetting min_weight=0. "
#         model.min_weight = 0.0
#     end
#     if model.rowsample < 0
#         warning *= "Need rowsample ≥ 0. Resetting rowsample=0. "
#         model.rowsample = 0.0
#     end
#     if model.rowsample > 1
#         warning *= "Need rowsample <= 1. Resetting rowsample=1. "
#         model.rowsample = 1.0
#     end
#     if model.colsample < 0
#         warning *= "Need colsample ≥ 0. Resetting colsample=0. "
#         model.colsample = 0.0
#     end
#     if model.colsample > 1
#         warning *= "Need colsample <= 1. Resetting colsample=1. "
#         model.colsample = 1.0
#     end
#     if model.nbins > 250
#         warning *= "Need nbins <= 250. Resetting nbins=250. "
#         model.nbins = 250
#     end
#     return warning
# end
