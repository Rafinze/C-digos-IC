using SDDP, Gurobi

function subproblem_builder(subproblem::Model, node::Int)
    max_hidro = [50, 100, 150, 200]
    max_termo = [200, 150, 100, 50] 
    nT = 4
    nH = 4
    vol_max = [200, 200, 200, 200]
    demanda = 250
    volume_inicial = [200, 100, 50, 25]
    custo_termo = [100, 50, 120, 60]

    # State variables
    @variable(subproblem, 0 <= V[i=1:nH] <= vol_max[i], SDDP.State, initial_value = volume_inicial[i])

    # Control variables    
    @variables(subproblem, 
        begin
            0 <= H[i=1:nH] <= max_hidro[i]
            0 <= T[i=1:nT] <= max_termo[i]
        end
    )

    # Random variables
    @variable(subproblem, Chuva[i=1:nH])
    Ω = [[25.0, 50.0, 75.0, 100.0],[25.0, 50.0, 75.0, 100.0],[25.0, 50.0, 75.0, 100.0],[25.0, 50.0, 75.0, 100.0]]
    P = [1/4, 1/4, 1/4, 1/4]
    SDDP.parameterize(subproblem, Ω, P) do ω
        for i in 1:nH
            JuMP.fix(Chuva[i], ω[i])
        end
    end

    # Constraints
    @constraint(subproblem, restricao_demanda, sum(T[i] for i in 1:nT) + sum(H[j] for j in 1:nH) >= demanda)
    
    for j in 1:nH
        @constraint(subproblem, V[j].out == V[j].in - H[j] + Chuva[j])
    end

    # Objective
    @stageobjective(subproblem, sum(custo_termo[i] * T[i] for i in 1:nT))

    return subproblem
end

model = SDDP.LinearPolicyGraph(
    subproblem_builder;
    stages = 4,
    sense = :Min,
    lower_bound = 0.0,
    optimizer = Gurobi.Optimizer,
)

# Treinamento do modelo
SDDP.train(model; iteration_limit = 10)

# Simulação do modelo
simulations = SDDP.simulate(
    model,
    100,  # Number of simulations
    [:V, :H, :T],  # Variables to record
)

# Processamento dos resultados das simulações
for (sim_idx, simulation) in enumerate(simulations)
    println("Simulation $sim_idx:")
    for (stage_idx, stage) in enumerate(simulation)
        println("  Stage $stage_idx:")
        println("    Volume final dos reservatórios: ", [stage[:V][i].out for i in 1:length(stage[:V])])
        println("    Produção das hidroelétricas: ", stage[:H])
        println("    Produção das térmicas: ", stage[:T])
        println("    Custo de produção: ", stage[:stage_objective])
    end
end

# Processamento dos resultados agregados das simulações
objectives = map(simulations) do simulation 
    return sum(stage[:stage_objective] for stage in simulation)
end

μ, ci = SDDP.confidence_interval(objectives)
println("Confidence interval: ", μ, " ± ", ci)
println("Lower bound: ", SDDP.calculate_bound(model))

# Obtém o dual da restrição de demanda 
simulations = SDDP.simulate(
    model,
    1,  # Perform a single simulation
    custom_recorders = Dict{Symbol, Function}(
        :price => (sp::JuMP.Model) -> JuMP.dual(sp[:restricao_demanda]),
    ),
)

prices = map(simulations[1]) do node
    return node[:price]
end
println("Preços de dual da restrição de demanda: ", prices)

# Avaliando o valor da função em diferentes pontos no espaço de estados
Vol = SDDP.ValueFunction(model; node = 1)

# state_point = Dict(
#     :V1 => 10.0, 
#     :V2 => 10.0, 
#     :V3 => 10.0, 
#     :V4 => 10.0
# )

# Use o nome correto das variáveis de estado para criar state_point
# for i in 1:length(Vol.states)
#     state_point[Vol.states[i]] = 10.0
# end

# cost, price = SDDP.evaluate(Vol, state_point)
# println("Custo avaliado: ", cost)
# println("Preço avaliado: ", price)