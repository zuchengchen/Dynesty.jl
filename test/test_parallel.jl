using Dynesty
using Test

@testset "Map backends" begin
    serial = SerialMapBackend()
    @test serial.queue_size == 1
    @test map_ordered(serial, x -> x^2, [3, 2, 1]) == [9, 4, 1]
    @test_throws ArgumentError SerialMapBackend(queue_size=0)
    @test Dynesty._get_map_backend(:serial, nothing, nothing) isa SerialMapBackend
    @test Dynesty._get_map_backend("none", nothing, nothing) isa SerialMapBackend

    threaded = ThreadedMapBackend(queue_size=2)
    @test map_ordered(threaded, x -> x + 1, 1:5) == [2, 3, 4, 5, 6]
    @test Dynesty._get_map_backend(:threads, nothing, 2) == threaded
    @test Dynesty._get_map_backend("threaded", nothing, 2) == threaded

    distributed = DistributedMapBackend(workers=Int[], queue_size=2)
    @test map_ordered(distributed, x -> 2x, 1:4) == [2, 4, 6, 8]
    @test Dynesty._get_map_backend(:distributed, nothing, 2) isa DistributedMapBackend
    @test Dynesty._map_backend_from_config(Dynesty._backend_config(threaded)) == threaded
    @test_throws ArgumentError Dynesty._get_map_backend(:bad, nothing, nothing)
    @test_throws ArgumentError Dynesty._get_map_backend(:threads, threaded, 2)

    seeds1 = task_seeds(1234, 5)
    seeds2 = task_seeds(1234, 5)
    @test seeds1 == seeds2
    @test length(unique(seeds1)) == 5

    rng_values1 = map_with_rng(serial, (input, rng) -> input + rand(rng), [1, 2, 3]; seed=9)
    rng_values2 = map_with_rng(serial, (input, rng) -> input + rand(rng), [1, 2, 3]; seed=9)
    @test rng_values1 == rng_values2
end

@testset "Map errors include context" begin
    err = try
        map_ordered(SerialMapBackend(), x -> x == 2 ? error("boom") : x, [1, 2, 3])
        nothing
    catch caught
        caught
    end
    @test err isa MapTaskError
    @test err.index == 2
    @test occursin("task index 2", sprint(showerror, err))
    @test occursin("boom", sprint(showerror, err))
end
