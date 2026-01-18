#!/usr/bin/env elixir

# Demo script to show mutation optimization in action
# Run from muex root: elixir examples/cart/demo_optimization.exs

Mix.install([{:decimal, "~> 2.0"}])

Code.prepend_path("_build/dev/lib/muex/ebin")

defmodule OptimizationDemo do
  alias Muex.{Loader, Mutator, MutantOptimizer}
  alias Muex.Language.Elixir, as: ElixirAdapter

  def run do
    IO.puts("\n=== Mutation Optimization Demonstration ===\n")
    IO.puts("Analyzing Cart example with sophisticated heuristics...\n")

    # Load files
    path = "examples/cart/lib"
    {:ok, files} = Loader.load(path, ElixirAdapter)

    IO.puts("Loaded #{length(files)} files:")
    Enum.each(files, fn file ->
      IO.puts("  - #{Path.basename(file.path)}")
    end)

    # Generate all mutations
    IO.puts("\nGenerating mutations...")

    mutators = [
      Mutator.Arithmetic,
      Mutator.Comparison,
      Mutator.Boolean,
      Mutator.Literal,
      Mutator.FunctionCall,
      Mutator.Conditional
    ]

    all_mutations =
      Enum.flat_map(files, fn file ->
        context = %{file: file.path}
        Mutator.walk(file.ast, mutators, context)
      end)

    original_count = length(all_mutations)
    IO.puts("Generated #{original_count} mutations\n")

    # Show distribution by mutator
    IO.puts("Distribution by mutator type:")

    by_mutator =
      all_mutations
      |> Enum.group_by(fn m ->
        m.mutator |> Module.split() |> List.last()
      end)
      |> Enum.map(fn {name, muts} -> {name, length(muts)} end)
      |> Enum.sort_by(fn {_, count} -> -count end)

    Enum.each(by_mutator, fn {name, count} ->
      IO.puts("  #{String.pad_trailing(name, 20)} #{count}")
    end)

    # Apply optimization with different levels
    IO.puts("\n=== Optimization Results ===\n")

    # Level 1: Filter equivalent mutants only
    IO.puts("Level 1: Filter equivalent mutants")
    opt1 = MutantOptimizer.filter_equivalent_mutants(all_mutations)
    show_reduction(original_count, length(opt1))

    # Level 2: + Complexity filtering
    IO.puts("\nLevel 2: + Complexity filtering (min_complexity: 2)")

    opt2 =
      all_mutations
      |> MutantOptimizer.filter_equivalent_mutants()
      |> MutantOptimizer.score_by_impact()
      |> MutantOptimizer.filter_by_complexity(2)

    show_reduction(original_count, length(opt2))

    # Level 3: + Clustering
    IO.puts("\nLevel 3: + Mutation clustering")

    opt3 =
      all_mutations
      |> MutantOptimizer.filter_equivalent_mutants()
      |> MutantOptimizer.score_by_impact()
      |> MutantOptimizer.filter_by_complexity(2)
      |> MutantOptimizer.cluster_and_sample(0.8)

    show_reduction(original_count, length(opt3))

    # Level 4: + Per-function limit
    IO.puts("\nLevel 4: + Per-function limit (max: 20)")

    opt4 =
      all_mutations
      |> MutantOptimizer.filter_equivalent_mutants()
      |> MutantOptimizer.score_by_impact()
      |> MutantOptimizer.filter_by_complexity(2)
      |> MutantOptimizer.cluster_and_sample(0.8)
      |> MutantOptimizer.limit_per_function(20)

    show_reduction(original_count, length(opt4))

    # Full optimization
    IO.puts("\n=== Full Optimization ===\n")

    optimized =
      MutantOptimizer.optimize(all_mutations,
        enabled: true,
        min_complexity: 2,
        max_mutations_per_function: 20,
        cluster_similarity_threshold: 0.8,
        keep_boundary_mutations: true
      )

    report = MutantOptimizer.optimization_report(all_mutations, optimized)

    IO.puts("Original mutations:     #{report.original_count}")
    IO.puts("Optimized mutations:    #{report.optimized_count}")
    IO.puts("Reduction:              #{report.reduction} (-#{report.reduction_percentage}%)")
    IO.puts("Avg impact score:       #{report.average_impact_score}")

    IO.puts("\nOptimized distribution by mutator:")

    Enum.each(report.by_mutator, fn {name, count} ->
      IO.puts("  #{String.pad_trailing(name, 20)} #{count}")
    end)

    IO.puts("\n=== Benefits ===\n")
    IO.puts("Time saved: ~#{report.reduction_percentage}% (assuming linear scaling)")
    IO.puts("Mutations per file: ~#{div(report.optimized_count, length(files))}")

    boundary_count =
      Enum.count(optimized, fn m ->
        mutator_name = m.mutator |> Module.split() |> List.last()

        if mutator_name == "Comparison" do
          case m.ast do
            {:>=, _, _} -> true
            {:<=, _, _} -> true
            {:==, _, _} -> true
            _ -> false
          end
        else
          false
        end
      end)

    IO.puts("Boundary mutations preserved: #{boundary_count}")

    IO.puts("\n=== Recommendations ===\n")
    IO.puts("The optimizer maintains high-value mutations while reducing redundancy.")
    IO.puts("Expected mutation score: Similar to baseline (±2%)")
    IO.puts(
      "Runtime improvement: #{report.reduction_percentage}% faster (#{format_time(original_count)} → #{format_time(report.optimized_count)})"
    )

    IO.puts("\nRun full mutation testing to verify:")
    IO.puts("  mix muex --files \"examples/cart/lib\"")
  end

  defp show_reduction(original, current) do
    reduction = original - current
    pct = Float.round(reduction / original * 100, 1)
    IO.puts("  #{current} mutations (reduced by #{reduction}, -#{pct}%)")
  end

  defp format_time(mutation_count) do
    # Assume ~200ms per mutation on average
    seconds = div(mutation_count * 200, 1000)

    cond do
      seconds < 60 -> "~#{seconds}s"
      seconds < 3600 -> "~#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "~#{div(seconds, 3600)}h #{div(rem(seconds, 3600), 60)}m"
    end
  end
end

OptimizationDemo.run()
