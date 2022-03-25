using Statistics
using StatsBase:sample, sample!
using EvoTrees
using BenchmarkTools
using CUDA

# prepare a dataset
features = rand(Int(1.25e6), 100)
# features = rand(Int(2.5e6), 100)

# features = rand(100, 10)
X = features
Y = rand(size(X, 1))
𝑖 = collect(1:size(X, 1))

# train-eval split
𝑖_sample = sample(𝑖, size(𝑖, 1), replace=false)
train_size = 0.8
𝑖_train = 𝑖_sample[1:floor(Int, train_size * size(𝑖, 1))]
𝑖_eval = 𝑖_sample[floor(Int, train_size * size(𝑖, 1)) + 1:end]

X_train, X_eval = X[𝑖_train, :], X[𝑖_eval, :]
Y_train, Y_eval = Y[𝑖_train], Y[𝑖_eval]


###########################
# Tree CPU
###########################
params_c = EvoTreeRegressor(T=Float32,
    loss=:linear, metric=:none,
    nrounds=100,
    λ=1.0, γ=0.1, η=0.1,
    max_depth=6, min_weight=1.0,
    rowsample=0.5, colsample=0.5, nbins=64);

# params_c = EvoTreeGaussian(T=Float32,
#     loss=:gaussian, metric=:none,
#     nrounds=100,
#     λ=1.0, γ=0.1, η=0.1,
#     max_depth=6, min_weight=1.0,
#     rowsample=0.5, colsample=0.5, nbins=64);

model_c, cache_c = EvoTrees.init_evotree(params_c, X_train, Y_train);

# initialize from cache
params_c = model_c.params
X_size = size(cache_c.X_bin)

# select random rows and cols
sample!(params_c.rng, cache_c.𝑖_, cache_c.nodes[1].𝑖, replace=false, ordered=true);
sample!(params_c.rng, cache_c.𝑗_, cache_c.𝑗, replace=false, ordered=true);
# @btime sample!(params_c.rng, cache_c.𝑖_, cache_c.nodes[1].𝑖, replace=false, ordered=true);
# @btime sample!(params_c.rng, cache_c.𝑗_, cache_c.𝑗, replace=false, ordered=true);

𝑖 = cache_c.nodes[1].𝑖
𝑗 = cache_c.𝑗

# build a new tree
# 1.25e6: 1.288 ms (0 allocations: 0 bytes)
@time EvoTrees.update_grads!(params_c.loss, cache_c.δ𝑤, cache_c.pred, cache_c.Y, params_c.α)
@btime EvoTrees.update_grads!($params_c.loss, $cache_c.δ𝑤, $cache_c.pred, $cache_c.Y, $params_c.α)
# ∑ = vec(sum(cache_c.δ[𝑖,:], dims=1))
# gain = EvoTrees.get_gain(params_c.loss, ∑, params_c.λ)
# assign a root and grow tree
# train_nodes[1] = EvoTrees.TrainNode(UInt32(0), UInt32(1), ∑, gain)

# 1.25e6: 80.605 ms (10430 allocations: 6.77 MiB)
tree = EvoTrees.Tree(params_c.max_depth, model_c.K, zero(typeof(params_c.λ)))
@time EvoTrees.grow_tree!(tree, cache_c.nodes, params_c, cache_c.δ𝑤, cache_c.edges, cache_c.𝑗, cache_c.left, cache_c.left, cache_c.right, cache_c.X_bin, cache_c.K)
@btime EvoTrees.grow_tree!($EvoTrees.Tree(params_c.max_depth, model_c.K, zero(typeof(params_c.λ))), $cache_c.nodes, $params_c, $cache_c.δ𝑤, $cache_c.edges, $cache_c.𝑗, $cache_c.left, $cache_c.left, $cache_c.right, $cache_c.X_bin, $cache_c.K)

@time EvoTrees.grow_tree!(EvoTrees.Tree(params_c.max_depth, model_c.K, params_c.λ), params_c, cache_c.δ, cache_c.hist, cache_c.histL, cache_c.histR, cache_c.gains, cache_c.edges, 𝑖, 𝑗, 𝑛, cache_c.X_bin);
@btime EvoTrees.grow_tree!(EvoTrees.Tree($params_c.max_depth, $model_c.K, $params_c.λ), $params_c, $cache_c.δ, $cache_c.hist, $cache_c.histL, $cache_c.histR, $cache_c.gains, $cache_c.edges, $𝑖, $𝑗, $𝑛, $cache_c.X_bin);
@code_warntype EvoTrees.grow_tree!(EvoTrees.Tree(params_c.max_depth, model_c.K, params_c.λ), params_c, cache_c.δ, cache_c.hist, cache_c.histL, cache_c.histR, cache_c.gains, cache_c.edges, 𝑖, 𝑗, 𝑛, cache_c.X_bin);

# push!(model_c.trees, tree)
# 1.883 ms (83 allocations: 13.77 KiB)
@btime EvoTrees.predict!(model_c.params.loss, cache_c.pred_cpu, tree, cache_c.X, model_c.K)

δ𝑤, K, edges, X_bin, nodes, out, left, right = cache_c.δ𝑤, cache_c.K, cache_c.edges, cache_c.X_bin, cache_c.nodes, cache_c.out, cache_c.left, cache_c.right;

# 1.25e6: 6.618 ms (81 allocations: 8.22 KiB)
@time EvoTrees.update_hist!(params_c.loss, nodes[1].h, δ𝑤, X_bin, 𝑖, 𝑗, K)
@btime EvoTrees.update_hist!($params_c.loss, $nodes[1].h, $δ𝑤, $X_bin, $𝑖, $𝑗, $K)
@btime EvoTrees.update_hist!($nodes[1].h, $δ𝑤, $X_bin, $nodes[1].𝑖, $𝑗)
@code_warntype EvoTrees.update_hist!(hist, δ, X_bin, 𝑖, 𝑗, 𝑛)

j = 1
# 8.399 μs (80 allocations: 13.42 KiB)
n = 1
nodes[1].∑ .= vec(sum(δ𝑤[:, 𝑖], dims=2))
EvoTrees.update_gains!(params_c.loss, nodes[n], 𝑗, params_c, K)
nodes[1].gains
# findmax(nodes[1].gains) #1.25e5: 36.500 μs (81 allocations: 8.22 KiB)
@btime EvoTrees.update_gains!($params_c.loss, $nodes[n], $𝑗, $params_c, $K)
@code_warntype EvoTrees.update_gains!(params_c.loss, nodes[n], 𝑗, params_c, K)

#1.25e5: 14.100 μs (1 allocation: 32 bytes)
best = findmax(nodes[n].gains)
@btime best = findmax(nodes[n].gains)
@btime best = findmax(view(nodes[n].gains, :, 𝑗))

tree.cond_bin[n] = best[2][1]
tree.feat[n] = best[2][2]

Int.(tree.cond_bin[n])
# tree.cond_bin[n] = 32

# 204.900 μs (1 allocation: 96 bytes)
offset = 0
@time EvoTrees.split_set!(left, right, 𝑖, X_bin, tree.feat[n], tree.cond_bin[n], offset)
@btime EvoTrees.split_set!($left, $right, $𝑖, $X_bin, $tree.feat[n], $tree.cond_bin[n], $offset)
@code_warntype EvoTrees.split_set!(left, right, 𝑖, X_bin, tree.feat[n], tree.cond_bin[n])

# 1.25e5: 227.200 μs (22 allocations: 1.44 KiB)
@time EvoTrees.split_set_threads!(out, left, right, 𝑖, X_bin, tree.feat[n], tree.cond_bin[n], offset)
@btime EvoTrees.split_set_threads!($out, $left, $right, $𝑖, $X_bin, $tree.feat[n], $tree.cond_bin[n], $offset, Int(2e15))

###################################################
# GPU
###################################################
params_g = EvoTreeRegressor(T=Float32,
    loss=:linear, metric=:none,
    nrounds=100,
    λ=1.0, γ=0.1, η=0.1,
    max_depth=6, min_weight=1.0,
    rowsample=0.5, colsample=0.5, nbins=64);

model_g, cache_g = EvoTrees.init_evotree_gpu(params_g, X_train, Y_train);

params_g = model_g.params;
X_size = size(cache_g.X_bin);

# select random rows and cols
𝑖c = cache_g.𝑖_[sample(params_g.rng, cache_g.𝑖_, ceil(Int, params_g.rowsample * X_size[1]), replace=false, ordered=true)]
𝑖 = CuVector(𝑖c)
𝑗c = cache_g.𝑗_[sample(params_g.rng, cache_g.𝑗_, ceil(Int, params_g.colsample * X_size[2]), replace=false, ordered=true)]
𝑗 = CuVector(𝑗c)
sum(𝑖)
cache_g.nodes[1].𝑖 = 𝑖
cache_g.nodes[1].𝑖 .= 𝑖
sum(𝑗)
cache_g.𝑗 .= 𝑗c
sum(cache_g.𝑗)

# build a new tree
# 1.25e6: 142.400 μs (21 allocations: 1.23 KiB)
@time CUDA.@sync EvoTrees.update_grads_gpu!(params_g.loss, cache_g.δ𝑤, cache_g.pred, cache_g.Y)
@btime CUDA.@sync EvoTrees.update_grads_gpu!($params_g.loss, $cache_g.δ𝑤, $cache_g.pred, $cache_g.Y)
# sum Gradients of each of the K parameters and bring to CPU

# 45.760 ms (23670 allocations: 1.38 MiB)
tree = EvoTrees.TreeGPU(params_g.max_depth, model_g.K, params_g.λ)
sum(cache_g.δ𝑤[:, cache_g.nodes[1].𝑖], dims=2)
CUDA.@time EvoTrees.grow_tree_gpu!(tree, cache_g.nodes, params_g, cache_g.δ𝑤, cache_g.edges, CuVector(cache_g.𝑗), cache_g.out, cache_g.left, cache_g.right, cache_g.X_bin, cache_g.K)
@btime EvoTrees.grow_tree_gpu!($tree, $cache_g.nodes, params_g, $cache_g.δ𝑤, $cache_g.edges, $𝑗, $cache_g.out, $cache_g.left, $cache_g.right, $cache_g.X_bin, $cache_g.K);
@code_warntype EvoTrees.grow_tree_gpu!(tree, params_g, cache_g.δ, cache_g.hist, cache_g.histL, cache_g.histR, cache_g.gains, cache_g.edges, 𝑖, 𝑗, 𝑛, cache_g.X_bin);

push!(model_g.trees, tree);
# 2.736 ms (93 allocations: 13.98 KiB)
@time CUDA.@sync EvoTrees.predict!(cache_g.pred_gpu, tree, cache_g.X_bin)
@btime CUDA.@sync EvoTrees.predict!($cache_g.pred_gpu, $tree, $cache_g.X_bin)

###########################
# Tree GPU
###########################
δ𝑤, K, edges, X_bin, nodes, out, left, right = cache_g.δ𝑤, cache_g.K, cache_g.edges, cache_g.X_bin, cache_g.nodes, cache_g.out, cache_g.left, cache_g.right;

# 1.25e6: 2.830 ms (76 allocations: 5.00 KiB)
@time EvoTrees.update_hist_gpu!(params_g.loss, nodes[1].h, δ𝑤, X_bin, 𝑖, 𝑗, K)
@btime EvoTrees.update_hist_gpu!($params_g.loss, $nodes[1].h, $δ𝑤, $X_bin, $𝑖, $𝑗, $K)
@btime EvoTrees.update_hist_gpu!($nodes[1].h, $δ𝑤, $X_bin, $nodes[1].𝑖, $𝑗)
@code_warntype EvoTrees.update_hist_gpu!(hist, δ, X_bin, 𝑖, 𝑗, 𝑛)


# 72.100 μs (186 allocations: 6.00 KiB)
n = 1
nodes[1].∑ .= vec(sum(δ𝑤[:, 𝑖], dims=2))
CUDA.@time EvoTrees.update_gains_gpu!(params_g.loss, nodes[n], 𝑗, params_g, K)
@btime EvoTrees.update_gains_gpu!($params_g.loss, $nodes[n], $𝑗, $params_g, $K)

tree = EvoTrees.TreeGPU(params_g.max_depth, model_g.K, params_g.λ)
best = findmax(nodes[n].gains)
if best[2][1] != params_g.nbins && best[1] > nodes[n].gain + params_g.γ
    tree.gain[n] = best[1]
    tree.cond_bin[n] = best[2][1]
    tree.feat[n] = best[2][2]
    tree.cond_float[n] = edges[tree.feat[n]][tree.cond_bin[n]]
end

tree.split[n] = tree.cond_bin[n] != 0
tree.feat[n]
Int(tree.cond_bin[n])

# 673.900 μs (600 allocations: 29.39 KiB)
offset = 0
_left, _right = EvoTrees.split_set_threads_gpu!(out, left, right, 𝑖, X_bin, tree.feat[n], tree.cond_bin[n], offset)
@time EvoTrees.split_set_threads_gpu!(out, left, right, 𝑖, X_bin, tree.feat[n], tree.cond_bin[n], offset)
@btime EvoTrees.split_set_threads_gpu!($out, $left, $right, $𝑖, $X_bin, $tree.feat[n], $tree.cond_bin[n], $offset)
