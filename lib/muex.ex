defmodule Muex do
  @moduledoc """
  Muex - Mutation testing library for Elixir, Erlang, and other languages.

  Muex provides a language-agnostic mutation testing framework with dependency
  injection for language adapters, making it easy to extend support to new languages.

  ## Architecture

  - `Muex.Language` - Behaviour for language adapters (parse, unparse, compile)
  - `Muex.Mutator` - Behaviour for mutation strategies
  - `Muex.Loader` - Discovers and loads source files
  - `Muex.Compiler` - Compiles mutated code and manages hot-swapping
  - `Muex.Runner` - Executes tests against mutants
  - `Muex.Reporter` - Reports mutation testing results

  ## Usage

  Run mutation testing via Mix task:

      mix muex

  With options:

      mix muex --files "lib/**/*.ex" --mutators arithmetic,comparison --fail-at 80

  ## Creating a Language Adapter

  To add support for a new language, implement the `Muex.Language` behaviour:

      defmodule Muex.Language.MyLanguage do
        @behaviour Muex.Language

        @impl true
        def parse(source), do: {:ok, parse_to_ast(source)}

        @impl true
        def unparse(ast), do: {:ok, ast_to_string(ast)}

        @impl true
        def compile(source, module_name), do: {:ok, compiled_module}

        @impl true
        def file_extensions, do: [".mylang"]

        @impl true
        def test_file_pattern, do: ~r/_test\.mylang$/
      end

  ## Creating a Mutator

  To add a new mutation strategy, implement the `Muex.Mutator` behaviour:

      defmodule Muex.Mutator.MyMutator do
        @behaviour Muex.Mutator

        @impl true
        def mutate(ast, context) do
          # Return list of mutations
          []
        end

        @impl true
        def name, do: "MyMutator"

        @impl true
        def description, do: "Custom mutation strategy"
      end
  """

  alias Muex.Reporter.Html, as: HtmlReporter
  alias Muex.Reporter.Json, as: JsonReporter

  @doc """
  Executes the full mutation testing pipeline from a `%Muex.Config{}`.

  Returns `{:ok, %{results: results, score: mutation_score}}` on success
  or `{:error, reason}` on failure. Never calls `Mix.raise` or `System.halt`;
  the caller decides how to handle the outcome.
  """
  @spec run(Muex.Config.t()) :: {:ok, map()} | {:error, String.t()}
  def run(%Muex.Config{} = config) do
    log("Loading files from #{config.files}...", config.verbose)

    {:ok, all_files} = Muex.Loader.load(config.files, config.language)

    case all_files do
      [] ->
        {:ok, %{results: [], score: 0.0}}

      _ ->
        log("Found #{length(all_files)} file(s)", config.verbose)
        do_run(config, all_files)
    end
  end

  defp do_run(config, all_files) do
    files = maybe_filter(all_files, config)

    log("Generating mutations...", config.verbose)

    all_mutations =
      files
      |> Enum.flat_map(fn file ->
        context = %{file: file.path}
        Muex.Mutator.walk(file.ast, config.mutators, context)
      end)
      |> maybe_optimize(config)
      |> maybe_cap(config)

    if all_mutations == [] do
      {:ok, %{results: [], score: 0.0}}
    else
      run_mutations(config, files, all_mutations)
    end
  end

  defp maybe_filter(files, %Muex.Config{filter: false} = config) do
    log("Skipping file filtering", config.verbose)
    files
  end

  defp maybe_filter(files, %Muex.Config{filter: true} = config) do
    log("Analyzing files for mutation testing suitability...", config.verbose)

    {included, excluded} =
      Muex.FileAnalyzer.filter_files(files, min_score: config.min_score, verbose: config.verbose)

    log(
      "Selected #{length(included)} file(s), skipped #{length(excluded)} file(s)",
      config.verbose
    )

    included
  end

  defp maybe_optimize(mutations, %Muex.Config{optimize: false}), do: mutations

  defp maybe_optimize(mutations, %Muex.Config{optimize: true, verbose: verbose} = config) do
    log("Applying mutation optimization...", verbose)
    opts = Muex.Config.optimizer_opts(config)
    optimized = Muex.MutantOptimizer.optimize(mutations, opts)

    if verbose do
      report = Muex.MutantOptimizer.optimization_report(mutations, optimized)
      log("Original mutations: #{report.original_count}", true)
      log("Optimized mutations: #{report.optimized_count}", true)
      log("Reduction: #{report.reduction} (-#{report.reduction_percentage}%)", true)
      log("Average impact score: #{report.average_impact_score}", true)
    end

    optimized
  end

  defp maybe_cap(mutations, %Muex.Config{max_mutations: max})
       when max > 0 and length(mutations) > max do
    Enum.take(mutations, max)
  end

  defp maybe_cap(mutations, _config), do: mutations

  defp run_mutations(config, files, all_mutations) do
    log("Testing #{length(all_mutations)} mutation(s)", config.verbose)
    log("Analyzing test dependencies...", config.verbose)

    dependency_map = Muex.DependencyAnalyzer.analyze(config.test_paths)
    file_to_module = Map.new(files, fn file -> {file.path, file.module_name} end)

    log("Running tests...\n", config.verbose)

    results =
      Enum.flat_map(files, fn file ->
        file_mutations = Enum.filter(all_mutations, fn m -> m.location.file == file.path end)

        if match?([_ | _], file_mutations) do
          Muex.Runner.run_all(
            file_mutations,
            file,
            config.language,
            dependency_map,
            file_to_module,
            max_workers: config.concurrency,
            timeout_ms: config.timeout_ms,
            verbose: config.verbose,
            test_paths: config.test_paths
          )
        else
          []
        end
      end)

    case output_report(results, config.format, config.verbose) do
      {:error, _} = err -> err
      _ -> build_result(results)
    end
  end

  defp build_result(results) do
    total = length(results)
    killed = Enum.count(results, &(&1.result == :killed))

    score =
      if total > 0 do
        Float.round(killed / total * 100, 2)
      else
        0.0
      end

    {:ok, %{results: results, score: score}}
  end

  defp output_report(results, "json", _verbose) do
    log(JsonReporter.to_json(results))
  end

  defp output_report(results, "html", verbose) do
    HtmlReporter.generate(results)
    log("HTML report generated: muex-report.html", verbose)
  end

  defp output_report(results, "terminal", _verbose) do
    Muex.Reporter.print_summary(results)
  end

  defp output_report(_results, other, _verbose) do
    {:error, "Unknown format: #{other}. Use terminal, json, or html"}
  end

  defp log(msg, verbose \\ true) do
    if verbose do
      if Code.ensure_loaded?(Mix) and function_exported?(Mix, :shell, 0) do
        Mix.shell().info(msg)
      else
        IO.puts(msg)
      end
    end
  end
end
