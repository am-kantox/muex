defmodule Muex.WorkerPool do
  @moduledoc """
  Manages a pool of workers for parallel mutation testing across all files.

  Uses a global queue of mutations with per-file locking to maximize
  cross-file parallelism while preventing concurrent modifications to the
  same source file. Each worker operates in an isolated sandbox directory
  so that parallel `mix test` invocations don't see each other's mutations.

  ## Scheduling strategy

  When a worker slot becomes available, the pool picks the next mutation
  from any file that is not currently locked. This means mutations
  targeting different files run in true parallel, while mutations
  targeting the same file are serialized.
  """

  use GenServer
  require Logger

  @default_max_workers 4

  defmodule State do
    @moduledoc false
    defstruct [
      :max_workers,
      :caller,
      :total_mutations,
      :opts,
      # Map of file_path => :queue.queue(mutation)
      pending_by_file: %{},
      # MapSet of file paths currently being mutated
      locked_files: MapSet.new(),
      # Map of worker_ref => {mutation, file_path, sandbox_idx, monitor_ref}
      active_workers: %{},
      # Reverse map: monitor_ref => worker_ref (for :DOWN lookup)
      monitor_to_worker: %{},
      # Accumulated results (reverse order)
      results: [],
      completed_mutations: 0,
      # Map of file_path => file_entry
      file_entries: %{},
      # Language adapter module
      language_adapter: nil,
      # Dependency map and file→module map
      dependency_map: %{},
      file_to_module: %{},
      # List of sandbox structs, one per worker slot
      sandboxes: [],
      # Queue of available sandbox indices
      available_sandboxes: :queue.new()
    ]
  end

  @doc """
  Starts the worker pool.

  ## Options

    - `:max_workers` - Maximum concurrent workers (default: #{@default_max_workers})
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Runs all mutations through the worker pool.

  Accepts the full set of mutations across all files. Mutations targeting
  different files run in parallel (up to `max_workers`); mutations targeting
  the same file are serialized automatically.

  ## Parameters

    - `pool` - The worker pool PID
    - `mutations` - List of all mutations to test (across all files)
    - `file_entries` - Map of file paths to file entry maps
    - `language_adapter` - The language adapter module
    - `dependency_map` - Map of modules to test files
    - `file_to_module` - Map of file paths to module names
    - `opts` - Options including `:timeout_ms`, `:test_paths`, `:verbose`

  ## Returns

    List of mutation results.
  """
  @spec run_mutations(
          pid(),
          [map()],
          %{Path.t() => map()},
          module(),
          map(),
          map(),
          keyword()
        ) :: [map()]
  def run_mutations(
        pool,
        mutations,
        file_entries,
        language_adapter,
        dependency_map,
        file_to_module,
        opts \\ []
      ) do
    GenServer.call(
      pool,
      {:run_mutations, mutations, file_entries, language_adapter, dependency_map, file_to_module,
       opts},
      :infinity
    )
  end

  # -- GenServer callbacks --

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    max_workers = Keyword.get(opts, :max_workers, @default_max_workers)

    state = %State{
      max_workers: max_workers,
      opts: opts
    }

    {:ok, state}
  end

  @impl true
  def handle_call(
        {:run_mutations, mutations, file_entries, language_adapter, dependency_map,
         file_to_module, opts},
        from,
        state
      ) do
    if Enum.empty?(mutations) do
      {:reply, [], state}
    else
      # Create sandboxes for parallel workers
      test_paths = Keyword.get(opts, :test_paths, ["test"])

      sandboxes =
        Muex.Sandbox.create_pool(state.max_workers,
          project_root: File.cwd!(),
          test_paths: test_paths
        )

      available_sandboxes =
        sandboxes
        |> Enum.with_index()
        |> Enum.reduce(:queue.new(), fn {_sb, idx}, q -> :queue.in(idx, q) end)

      # Group mutations by file path into per-file queues
      pending_by_file =
        Enum.reduce(mutations, %{}, fn mutation, acc ->
          file_path = mutation.location.file
          queue = Map.get(acc, file_path, :queue.new())
          Map.put(acc, file_path, :queue.in(mutation, queue))
        end)

      new_state = %{
        state
        | pending_by_file: pending_by_file,
          file_entries: file_entries,
          language_adapter: language_adapter,
          dependency_map: dependency_map,
          file_to_module: file_to_module,
          opts: opts,
          caller: from,
          results: [],
          total_mutations: length(mutations),
          completed_mutations: 0,
          locked_files: MapSet.new(),
          active_workers: %{},
          monitor_to_worker: %{},
          sandboxes: sandboxes,
          available_sandboxes: available_sandboxes
      }

      {:noreply, schedule_workers(new_state)}
    end
  end

  @impl true
  def handle_info({:worker_done, worker_ref, result}, state) do
    # Retrieve the worker's file path, sandbox index, and monitor ref
    {_mutation, file_path, sandbox_idx, monitor_ref} =
      Map.fetch!(state.active_workers, worker_ref)

    # Demonitor so we don't get a spurious :DOWN for normal exit
    Process.demonitor(monitor_ref, [:flush])

    new_active = Map.delete(state.active_workers, worker_ref)
    new_monitor_map = Map.delete(state.monitor_to_worker, monitor_ref)
    new_completed = state.completed_mutations + 1

    # Print progress
    if Keyword.get(state.opts, :verbose, false) do
      try do
        Muex.Reporter.print_progress(result, new_completed, state.total_mutations)
      rescue
        UndefinedFunctionError -> :ok
      end
    end

    # Unlock the file and return the sandbox to the available pool
    new_locked = MapSet.delete(state.locked_files, file_path)
    new_available = :queue.in(sandbox_idx, state.available_sandboxes)

    # Remove file from pending map if its queue is empty
    new_pending =
      case Map.get(state.pending_by_file, file_path) do
        nil ->
          Map.delete(state.pending_by_file, file_path)

        queue ->
          if :queue.is_empty(queue) do
            Map.delete(state.pending_by_file, file_path)
          else
            state.pending_by_file
          end
      end

    new_state = %{
      state
      | active_workers: new_active,
        monitor_to_worker: new_monitor_map,
        results: [result | state.results],
        completed_mutations: new_completed,
        locked_files: new_locked,
        available_sandboxes: new_available,
        pending_by_file: new_pending
    }

    # Check if all done
    if map_size(new_state.active_workers) == 0 and all_queues_empty?(new_state.pending_by_file) do
      Muex.Sandbox.cleanup(new_state.sandboxes)
      GenServer.reply(new_state.caller, Enum.reverse(new_state.results))
      {:noreply, %{new_state | caller: nil}}
    else
      {:noreply, schedule_workers(new_state)}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.fetch(state.monitor_to_worker, monitor_ref) do
      {:ok, worker_ref} ->
        {mutation, file_path, sandbox_idx, ^monitor_ref} =
          Map.fetch!(state.active_workers, worker_ref)

        # Worker crashed without sending :worker_done — synthesize a failed result
        Logger.warning("Mutation worker crashed: #{inspect(reason)}")

        result = %{
          mutation: mutation,
          result: :invalid,
          duration_ms: 0,
          error: {:worker_crashed, reason}
        }

        new_active = Map.delete(state.active_workers, worker_ref)
        new_monitor_map = Map.delete(state.monitor_to_worker, monitor_ref)
        new_completed = state.completed_mutations + 1
        new_locked = MapSet.delete(state.locked_files, file_path)
        new_available = :queue.in(sandbox_idx, state.available_sandboxes)

        new_pending =
          case Map.get(state.pending_by_file, file_path) do
            nil -> Map.delete(state.pending_by_file, file_path)
            queue ->
              if :queue.is_empty(queue),
                do: Map.delete(state.pending_by_file, file_path),
                else: state.pending_by_file
          end

        new_state = %{
          state
          | active_workers: new_active,
            monitor_to_worker: new_monitor_map,
            results: [result | state.results],
            completed_mutations: new_completed,
            locked_files: new_locked,
            available_sandboxes: new_available,
            pending_by_file: new_pending
        }

        if map_size(new_state.active_workers) == 0 and
             all_queues_empty?(new_state.pending_by_file) do
          Muex.Sandbox.cleanup(new_state.sandboxes)
          GenServer.reply(new_state.caller, Enum.reverse(new_state.results))
          {:noreply, %{new_state | caller: nil}}
        else
          {:noreply, schedule_workers(new_state)}
        end

      :error ->
        # Normal exit of a worker already handled via :worker_done — ignore
        {:noreply, state}
    end
  end

  # -- Scheduling --

  # Try to fill all available worker slots with mutations from unlocked files.
  defp schedule_workers(state) do
    available_slots = state.max_workers - map_size(state.active_workers)

    if available_slots > 0 and not :queue.is_empty(state.available_sandboxes) do
      case pick_next_mutation(state) do
        {:ok, mutation, file_path, new_pending} ->
          # Claim a sandbox
          {{:value, sandbox_idx}, new_available} = :queue.out(state.available_sandboxes)

          # Spawn worker and monitor it for crash recovery
          parent = self()
          worker_ref = make_ref()

          pid =
            spawn(fn ->
              result =
                run_mutation_worker(
                  mutation,
                  file_path,
                  Enum.at(state.sandboxes, sandbox_idx),
                  state.file_entries,
                  state.language_adapter,
                  state.dependency_map,
                  state.file_to_module,
                  state.opts
                )

              send(parent, {:worker_done, worker_ref, result})
            end)

          monitor_ref = Process.monitor(pid)

          new_state = %{
            state
            | pending_by_file: new_pending,
              locked_files: MapSet.put(state.locked_files, file_path),
              active_workers:
                Map.put(state.active_workers, worker_ref, {mutation, file_path, sandbox_idx, monitor_ref}),
              monitor_to_worker:
                Map.put(state.monitor_to_worker, monitor_ref, worker_ref),
              available_sandboxes: new_available
          }

          # Recurse to fill more slots
          schedule_workers(new_state)

        :none ->
          # No unlocked files with pending mutations — wait for a worker to finish
          state
      end
    else
      state
    end
  end

  # Find the next mutation from a file that is NOT currently locked.
  # Prioritizes files with the most pending mutations for better throughput.
  defp pick_next_mutation(state) do
    unlocked_files =
      state.pending_by_file
      |> Enum.reject(fn {file_path, queue} ->
        MapSet.member?(state.locked_files, file_path) or :queue.is_empty(queue)
      end)
      |> Enum.sort_by(fn {_path, queue} -> :queue.len(queue) end, :desc)

    case unlocked_files do
      [{file_path, queue} | _] ->
        {{:value, mutation}, new_queue} = :queue.out(queue)
        new_pending = Map.put(state.pending_by_file, file_path, new_queue)
        {:ok, mutation, file_path, new_pending}

      [] ->
        :none
    end
  end

  defp all_queues_empty?(pending_by_file) do
    Enum.all?(pending_by_file, fn {_path, queue} -> :queue.is_empty(queue) end)
  end

  # -- Worker execution --

  defp run_mutation_worker(
         mutation,
         file_path,
         sandbox,
         file_entries,
         language_adapter,
         dependency_map,
         file_to_module,
         opts
       ) do
    timeout_ms = Keyword.get(opts, :timeout_ms, 5000)
    start_time = System.monotonic_time(:millisecond)

    file_entry = Map.fetch!(file_entries, file_path)

    # Resolve test files for this mutation
    test_files =
      Muex.DependencyAnalyzer.get_tests_for_mutation(mutation, dependency_map, file_to_module)

    test_files =
      if match?([], test_files) do
        test_paths = Keyword.get(opts, :test_paths, ["test"])
        Muex.Config.expand_test_paths(test_paths)
      else
        test_files
      end

    result =
      case Muex.Compiler.compile_to_file(mutation, file_entry, language_adapter) do
        {:ok, mutated_file} ->
          {:ok, mutated_source} = File.read(mutated_file)
          File.rm!(mutated_file)

          # Apply the mutation to the sandbox (not the real project)
          :ok =
            Muex.Sandbox.apply_mutation(
              sandbox,
              file_path,
              mutated_source,
              file_entry.module_name
            )

          # Run tests from the sandbox directory
          test_result =
            Muex.TestRunner.Port.run_tests(test_files, timeout_ms: timeout_ms, cd: sandbox.root)

          # Restore the sandbox for the next mutation
          Muex.Sandbox.restore(sandbox, file_path)

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

    %{mutation: mutation, result: result_type, duration_ms: duration_ms, error: error}
  rescue
    e -> %{mutation: mutation, result: :timeout, duration_ms: 0, error: e}
  catch
    :exit, reason -> %{mutation: mutation, result: :timeout, duration_ms: 0, error: reason}
  end

  defp classify_test_result({:ok, %{failures: 0}}), do: :survived
  defp classify_test_result({:ok, %{failures: _}}), do: :killed
  defp classify_test_result({:error, :timeout}), do: :timeout
  defp classify_test_result({:error, _}), do: :invalid

  @impl true
  def terminate(_reason, state) do
    if state.sandboxes != [] do
      Muex.Sandbox.cleanup(state.sandboxes)
    end

    :ok
  end
end
