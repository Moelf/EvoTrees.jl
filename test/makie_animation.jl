using BenchmarkTools
using DataFrames
using CSV
using Statistics
using StatsBase: sample, quantile
using EvoTrees
using EvoTrees: sigmoid, logit
using Plots
using GraphRecipes
using Random: seed!

# prepare a dataset
X = rand(1_000, 2) .* 2
Y = sin.(X[:,1] .* π) .+ X[:,2]
Y = Y .+ randn(size(Y)) .* 0.1 #logit(Y)
# Y = sigmoid(Y)
𝑖 = collect(1:size(X,1))

# make a grid
grid_size = 101
range = 2
X_grid = zeros(grid_size^2,2)
for j in 1:grid_size
    for i in 1:grid_size
        X_grid[grid_size*(j-1) + i,:] .= [(i-1) / (grid_size-1) * range,  (j-1) / (grid_size-1) * range]
    end
end
Y_grid = sin.(X_grid[:,1] .* π) .+ X_grid[:,2]

# train-eval split
𝑖_sample = sample(𝑖, size(𝑖, 1), replace = false)
train_size = 0.8
𝑖_train = 𝑖_sample[1:floor(Int, train_size * size(𝑖, 1))]
𝑖_eval = 𝑖_sample[floor(Int, train_size * size(𝑖, 1))+1:end]

X_train, X_eval = X[𝑖_train, :], X[𝑖_eval, :]
Y_train, Y_eval = Y[𝑖_train], Y[𝑖_eval]

# linear
params1 = EvoTreeRegressor(
    loss=:linear, metric=:mse,
    nrounds=100, nbins = 16,
    λ=0.5, γ=0.5, η=0.05,
    max_depth = 3, min_weight = 1.0,
    rowsample=0.8, colsample=1.0)

edges = EvoTrees.get_edges(X_train, params1.nbins)
X_bin = EvoTrees.binarize(X_train, edges)

@time model = grow_gbtree(X_train, Y_train, params1, X_eval = X_eval, Y_eval = Y_eval, print_every_n = 25)
# @btime model = grow_gbtree($X_train, $Y_train, $params1, X_eval = $X_eval, Y_eval = $Y_eval)

# @btime model = grow_gbtree($X_train, $Y_train, $params1, X_eval = $X_eval, Y_eval = $Y_eval, print_every_n = 25, metric=:mae)
@time pred_train_linear = predict(model, X_train)
# @time pred_eval_linear = predict(model, X_eval)
# mean(abs.(pred_train_linear .- Y_train))
# sqrt(mean((pred_train_linear .- Y_train) .^ 2))

x_perm_1 = sortperm(X_train[:,1])
x_perm_2 = sortperm(X_train[:,2])
p1_bin = plot(X_bin[:,1], Y_train, ms = 3, zcolor=Y_train, color=cgrad(["darkred", "#33ccff"]), msw=0, background_color = RGB(1, 1, 1), seriestype=:scatter, xaxis = ("var1"), yaxis = ("target"), legend = true, label = "")
# savefig(p1, "var1.svg")
# plot!(X_train[:,1][x_perm_1], pred_train_linear[x_perm_1], color = "red", mswidth=0, msize=3, label = "Linear", st=:scatter, leg=false)

p2 = plot(X_train[:,2], Y_train, ms = 3, zcolor=Y_train, color=cgrad(["darkred", "#33ccff"]), msw=0, background_color = "white", seriestype=:scatter, xaxis = ("var2"), yaxis = ("target"), leg = false, cbar=true)
p2_bin = plot(X_bin[:,2], Y_train, ms = 3, zcolor=Y_train, color=cgrad(["darkred", "#33ccff"]), msw=0, background_color = "white", seriestype=:scatter, xaxis = ("var2"), yaxis = ("target"), leg = false, cbar=true)
# savefig(p2, "var2.svg")
# plot!(X_train[:,2][x_perm_2], pred_train_linear[x_perm_2], color = "red", mswidth=0, msize=3, st=:scatter, label = "Predict")

p = plot(p1,p2, layout=(2,1))
savefig(p, "raw_one_ways.svg")
p = plot(p1_bin, p2_bin, layout=(2,1))
savefig(p, "bin_one_ways.svg")

# p = plot(X_train[:,1], X_train[:,2], Y_train, zcolor=Y_train, color=cgrad(["red","#3399ff"]), msize=5, markerstrokewidth=0, leg=false, cbar=true, w=1, st=:scatter)
p = plot(X_grid[:,1], X_grid[:,2], Y_grid, zcolor=Y_grid, color=:grays, msize=5, markerstrokewidth=0, leg=false, cbar=true, st=:scatter, xaxis="var1", yaxis="var2")
plot!(X_train[:,1], X_train[:,2], Y_train, zcolor=Y_train, color=cgrad(["darkred", "#33ccff"]), msize=4, markerstrokewidth=0, st=:scatter)
savefig(p, "data_3D.svg")
plot(X_train[:,1], X_train[:,2], pred_train_linear, zcolor=Y_train, m=(5, 0.9, :rainbow, Plots.stroke(0)), leg=false, cbar=true, w=1, st=:scatter)
plot(X_train[:,1], X_train[:,2], pred_train_linear, zcolor=Y_train, st=[:surface], leg=false, cbar=true, fillcolor=:rainbow, markeralpha=1.0)

p_bin = plot(X_bin[:,1], X_bin[:,2], Y_train, zcolor=Y_train, color=cgrad(["darkred", "#33ccff"]), msize=4, markerstrokewidth=0, st=:scatter, leg=false, cbar=true)

gr()
pyplot()
p = plot(X_grid[:,1], X_grid[:,2], Y_grid, zcolor=Y_train, st=[:surface], leg=false, cbar=true, color=:rainbow, linecolor=:rainbow, linewidth=0.0, contours=true, xaxis="var1", yaxis="var2")
Y_grid_mat = reshape(Y_grid, 101, 101)
plot(Y_grid_mat', zcolor=Y_grid_mat, st=[:surface], leg=false, cbar=true, color=:rainbow, linewidth=0.0, contours=false, xaxis="var1", yaxis="var2")
savefig(p, "pure_2D.svg")

params1 = EvoTreeRegressor(
    loss=:linear, metric=:mse,
    nrounds=100, nbins = 100,
    λ = 0.0, γ=0.0, η=0.1,
    max_depth = 2, min_weight = 1.0,
    rowsample=0.5, colsample=1.0)

anim = @animate for i=1:20
    params1.nrounds = (i-1)*5+1
    model = grow_gbtree(X_train, Y_train, params1, X_eval = X_eval, Y_eval = Y_eval, print_every_n = Inf)
    pred_train_linear = predict(model, X_train)
    x_perm = sortperm(X_train[:,1])
    plot(X_train, Y_train, ms = 1, mcolor = "gray", mscolor = "lightgray", background_color = RGB(1, 1, 1), seriestype=:scatter, xaxis = ("feature"), yaxis = ("target"), legend = true, label = "")
    plot!(X_train[:,1][x_perm], pred_train_linear[x_perm], color = "navy", linewidth = 1.5, label = "Linear")
end
gif(anim, "anim_fps1.gif", fps = 1)

# plot tree
function treemat(tree)
    mat = zeros(Int, length(tree.nodes), length(tree.nodes))
    for i in 1:length(tree.nodes)
        if tree.nodes[i].split
            mat[i,tree.nodes[i].left] = 1
            mat[tree.nodes[i].left, i] = 1
            mat[i,tree.nodes[i].right] = 1
            mat[tree.nodes[i].right, i] = 1
        end
        mat = sparse(mat)
    end
    return mat
end

tree = model.trees[2]
# tree vec
function treevec(tree)
    source, target = zeros(Int, max(1, length(tree.nodes)-1)), zeros(Int, max(1, length(tree.nodes)-1))
    count_s, count_t = 1, 1
    for i in 1:length(tree.nodes)
        if tree.nodes[i].split
            source[count_s] = i
            source[count_s+1] = i
            target[count_t] = tree.nodes[i].left
            target[count_t+1] = tree.nodes[i].right
            count_s += 2
            count_t += 2
        elseif i ==1
            source[i] = i
            target[i] = i
        end
    end
    return source, target
end

# plot tree
function nodenames(tree)
    names = []
    for i in 1:length(tree.nodes)
        if tree.nodes[i].split
            push!(names, "feat: " * string(tree.nodes[i].feat) * "\n< " * string(round(tree.nodes[i].cond, sigdigits=3)))
        else
            push!(names, "pred:\n" * string(round(tree.nodes[i].pred[1], sigdigits=3)))
        end
    end
    return names
end

tree1 = model.trees[2]
mat = treemat(tree1)
nodes = nodenames(tree1)
p = graphplot(mat, method=:tree, node_weights=ones(length(tree1)) .* 10, names = nodes, linecolor=:grey, nodeshape=:ellipse, fillcolor="#66ffcc", fontsize=8)
p = graphplot(mat, method=:tree, names = nodes, linecolor=:grey, shape=:ellipse, markercolor="red")

tree1 = model.trees[2]
source, target = treevec(tree1)
nodes = nodenames(tree1)
seed!(1)
p1 = graphplot(source, target, method=:tree, names = nodes, linecolor=:brown, nodeshape=:hexagon, fontsize=6, fillcolor="#66ffcc")

tree1 = model.trees[3]
source, target = treevec(tree1)
nodes = nodenames(tree1)
seed!(1)
p2 = graphplot(source, target, method=:tree, names = nodes, linecolor=:brown, nodeshape=:hexagon, fontsize=6, fillcolor="#66ffcc")

tree1 = model.trees[50]
source, target = treevec(tree1)
nodes = nodenames(tree1)
seed!(1)
p3 = graphplot(source, target, method=:tree, names = nodes, linecolor=:brown, nodeshape=:hexagon, fontsize=6, fillcolor="#66ffcc")

tree1 = model.trees[90]
source, target = treevec(tree1)
nodes = nodenames(tree1)
seed!(1)
p4 = graphplot(source, target, method=:tree, names = nodes, linecolor=:brown, nodeshape=:hexagon, fontsize=5, fillcolor="#66ffcc")

p = plot(p1,p2,p3,p4)
savefig(p, "tree_group.svg")
savefig(p1, "tree_1.svg")
