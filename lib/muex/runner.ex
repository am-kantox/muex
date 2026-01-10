defmodule Muex.Runner do
  @moduledoc """
  Runs tests against mutated code.

  Executes the test suite for each mutation and classifies the results.
  """

  @type result :: :killed | :survived | :invalid | :timeout

  @type mutation_result :: %{
          mutation: map(),
          result: result(),
          duration_ms: non_neg_integer(),
          error: term() | nil
        }

  @doc """
  Runs tests for a single mutation.

  ## Parameters

    - `mutation` - The mutation to test
    - `file_entry` - The file entry containing the original AST
    - `language_adapter` - The language adapter module
    - `opts` - Options:
      - `:timeout_ms` - Test timeout in milliseconds (default: 5000)

  ## Returns

    `mutation_result` map with test results
  """
  @spec run_mutation(map(), map(), module(), keyword()) :: mutation_result()
  def run_mutation(mutation, file_entry, language_adapter, opts \\ []) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    start_time = System.monotonic_time(:millisecond)

    result =
      case Muex.Compiler.compile(
             mutation,
             file_entry.ast,
             file_entry.module_name,
             language_adapter
           ) do
        {:ok, {_module, original_binary}} ->
          # Run tests and check result
          test_result =
            Task.async(fn -> run_tests() end)
            |> Task.await(timeout_ms)

          # Restore original module
          Muex.Compiler.restore(file_entry.module_name, original_binary)

          classify_test_result(test_result)

        {:error, reason} ->
          {:invalid, reason}
      end

    duration_ms = System.monotonic_time(:millisecond) - start_time

    {result_type, error} =
      case result do
        {:invalid, err} -> {:invalid, err}
        other -> {other, nil}
      end

    %{
      mutation: mutation,
      result: result_type,
      duration_ms: duration_ms,
      error: error
    }
  rescue
    e -> %{mutation: mutation, result: :timeout, duration_ms: 0, error: e}
  catch
    :exit, reason -> %{mutation: mutation, result: :timeout, duration_ms: 0, error: reason}
  end

  @doc """
  Runs tests for all mutations in parallel.

  ## Parameters

    - `mutations` - List of mutations to test
    - `file_entry` - The file entry containing the original AST
    - `language_adapter` - The language adapter module
    - `opts` - Options including `:concurrency` (default: System.schedulers_online())

  ## Returns

    List of `mutation_result` maps
  """
  @spec run_all([map()], map(), module(), keyword()) :: [mutation_result()]
  def run_all(mutations, file_entry, language_adapter, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, System.schedulers_online())

    mutations
    |> Task.async_stream(
      fn mutation ->
        run_mutation(mutation, file_entry, language_adapter, opts)
      end,
      max_concurrency: concurrency,
      timeout: Keyword.get(opts, :timeout_ms, 5000) + 1000
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, reason} -> %{mutation: nil, result: :timeout, duration_ms: 0, error: reason}
    end)
  end

  # Run ExUnit tests
  defp run_tests do
    # Find all test files
    test_files = Path.wildcard("test/**/*_test.exs")

    if Enum.empty?(test_files) do
      {:error, :no_tests_found}
    else
      # Run ExUnit tests by executing mix test
      # We use a separate process to isolate the test run
      case System.cmd("mix", ["test", "--color"], stderr_to_stdout: true) do
        {output, 0} ->
          # Tests passed - mutation survived
          {:ok, %{failures: 0, output: output}}

        {output, _exit_code} ->
          # Tests failed - mutation was killed
          failures = count_failures(output)
          {:ok, %{failures: failures, output: output}}
      end
    end
  rescue
    e -> {:error, e}
  end

  # Count the number of failures from test output
  defp count_failures(output) do
    case Regex.run(~r/(\d+) failures?/, output) do
      [_, count] -> String.to_integer(count)
      nil -> 1
    end
  end

  defp classify_test_result({:ok, %{failures: 0}}), do: :survived
  defp classify_test_result({:ok, %{failures: _}}), do: :killed
  defp classify_test_result({:error, _}), do: :invalid
end
