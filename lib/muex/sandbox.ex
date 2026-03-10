defmodule Muex.Sandbox do
  @moduledoc """
  Creates isolated working directories for parallel mutation testing.

  Each sandbox mirrors the project structure using symlinks, with its own
  `_build` directory and a copy of the single mutated source file. This
  allows multiple `mix test` processes to run simultaneously without
  seeing each other's mutations.

  Supports both standard Mix projects and umbrella projects. For umbrellas,
  the `apps/` directory is mirrored (not `lib/`), and only the specific app
  being mutated has its `_build` artifacts deep-copied.

  ## Structure (umbrella)

      sandbox/
      ├── mix.exs          → symlink to project
      ├── mix.lock         → symlink to project
      ├── config/          → symlink to project
      ├── deps/            → symlink to project
      ├── apps/            → mirrored directory of symlinks
      │   └── my_app/lib/  → directory of symlinks, except:
      │       └── mutated.ex → real file with mutated source
      └── _build/          → symlinks + deep copy of mutated app
  """

  @type sandbox :: %{
          root: Path.t(),
          project_root: Path.t(),
          build_env: String.t()
        }

  @doc """
  Creates a pool of reusable sandbox directories.

  Returns a list of sandbox structs that can be checked out by workers.
  """
  @spec create_pool(non_neg_integer(), keyword()) :: [sandbox()]
  def create_pool(count, opts \\ []) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())
    build_env = Keyword.get(opts, :build_env, "test")
    test_paths = Keyword.get(opts, :test_paths, ["test"])

    base_dir = Path.join(System.tmp_dir!(), "muex_sandboxes_#{System.system_time(:millisecond)}")
    File.mkdir_p!(base_dir)

    for i <- 1..count do
      root = Path.join(base_dir, "worker_#{i}")
      create_sandbox(root, project_root, build_env, test_paths)
    end
  end

  @doc """
  Creates a single sandbox directory mirroring the project.
  """
  @spec create_sandbox(Path.t(), Path.t(), String.t(), [String.t()]) :: sandbox()
  def create_sandbox(root, project_root, build_env, test_paths) do
    File.mkdir_p!(root)

    # Symlink top-level files
    symlink_top_level(root, project_root)

    umbrella? = File.dir?(Path.join(project_root, "apps"))

    if umbrella? do
      # For umbrellas: create apps/ dir and symlink each app as a whole.
      # apply_mutation/4 will lazily replace the specific app's symlink
      # with a file-level mirror when a mutation targets it. This avoids
      # creating 100K+ symlinks for large umbrella projects.
      setup_umbrella_apps(root, project_root)
    else
      mirror_source_tree(root, project_root, "lib")
    end

    # Symlink test directories (for explicit --test-paths)
    link_test_paths(root, project_root, test_paths)

    # Symlink deps/ (shared, read-only)
    safe_symlink(Path.join(project_root, "deps"), Path.join(root, "deps"))

    # Setup _build: symlink everything, deep copy nothing initially.
    # apply_mutation/4 handles deep-copying the specific app's build
    # artifacts on demand.
    setup_build_dir(root, project_root, build_env)

    %{root: root, project_root: project_root, build_env: build_env}
  end

  @doc """
  Applies a mutation to a sandbox by writing the mutated source to the
  sandbox's copy of the file, and deleting the beam file so `mix test`
  triggers incremental recompilation.

  Returns `:ok` or `{:error, reason}`.
  """
  @spec apply_mutation(sandbox(), Path.t(), String.t(), atom() | nil) :: :ok | {:error, term()}
  def apply_mutation(sandbox, original_path, mutated_source, module_name) do
    sandbox_path = Path.join(sandbox.root, original_path)

    # For umbrella projects: ensure the app containing the mutated file
    # has been mirrored (symlink replaced with file-level copies) so we
    # can swap individual source files.
    ensure_app_mirrored_for_file(sandbox, original_path)

    # Ensure the mutated app's build dir is a real copy (not a symlink)
    # so this sandbox can recompile independently.
    ensure_build_copy_for_file(sandbox, original_path)

    # Remove the symlink and write the mutated source as a real file
    File.rm(sandbox_path)

    case File.write(sandbox_path, mutated_source) do
      :ok ->
        # Delete beam file to force recompilation of this module only.
        # Elixir module atoms stringify with "Elixir." prefix automatically.
        if module_name do
          beam_pattern = Path.join([sandbox.root, "_build", "**", "#{module_name}.beam"])
          Path.wildcard(beam_pattern) |> Enum.each(&File.rm/1)
        end

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Restores a sandbox after a mutation by re-creating the symlink to the
  original source file.
  """
  @spec restore(sandbox(), Path.t()) :: :ok
  def restore(sandbox, original_path) do
    sandbox_path = Path.join(sandbox.root, original_path)
    project_path = Path.join(sandbox.project_root, original_path)

    # Copy the original source back over the mutated file.
    # (The app dir is a COW copy, not symlinks, so we overwrite in place.)
    File.rm(sandbox_path)
    File.cp!(project_path, sandbox_path)

    :ok
  end

  @doc """
  Cleans up all sandbox directories.
  """
  @spec cleanup([sandbox()]) :: :ok
  def cleanup(sandboxes) do
    case sandboxes do
      [%{root: first_root} | _] ->
        base_dir = Path.dirname(first_root)
        File.rm_rf!(base_dir)

      [] ->
        :ok
    end

    :ok
  end

  # -- Private helpers --

  defp symlink_top_level(root, project_root) do
    top_level_files = ~w(mix.exs mix.lock .formatter.exs .credo.exs)

    for file <- top_level_files do
      source = Path.join(project_root, file)

      if File.exists?(source) do
        safe_symlink(source, Path.join(root, file))
      end
    end

    top_level_dirs = ~w(config priv)

    for dir <- top_level_dirs do
      source = Path.join(project_root, dir)

      if File.dir?(source) do
        safe_symlink(source, Path.join(root, dir))
      end
    end
  end

  defp setup_umbrella_apps(root, project_root) do
    apps_source = Path.join(project_root, "apps")
    apps_target = Path.join(root, "apps")
    File.mkdir_p!(apps_target)

    apps_source
    |> File.ls!()
    |> Enum.each(fn app_name ->
      source_app = Path.join(apps_source, app_name)

      if File.dir?(source_app) do
        safe_symlink(source_app, Path.join(apps_target, app_name))
      end
    end)
  end

  # Replace an app's directory symlink with a COW copy so that individual
  # source files can be overwritten with mutated copies. Using deep_copy
  # (cp -Rc on macOS) is much faster than creating thousands of symlinks.
  defp ensure_app_mirrored(sandbox, app_name) do
    app_target = Path.join([sandbox.root, "apps", app_name])
    app_source = Path.join([sandbox.project_root, "apps", app_name])

    case File.read_link(app_target) do
      {:ok, _link_target} ->
        File.rm!(app_target)
        deep_copy(app_source, app_target)

      {:error, _} ->
        # Already a real copy from a previous mutation
        :ok
    end
  end

  defp mirror_source_tree(root, project_root, dir) do
    source_dir = Path.join(project_root, dir)
    target_dir = Path.join(root, dir)

    if File.dir?(source_dir) do
      source_dir
      |> Path.join("**")
      |> Path.wildcard(match_dot: true)
      |> Enum.each(fn source_path ->
        relative = Path.relative_to(source_path, project_root)
        target_path = Path.join(root, relative)

        if File.dir?(source_path) do
          File.mkdir_p!(target_path)
        else
          File.mkdir_p!(Path.dirname(target_path))
          safe_symlink(source_path, target_path)
        end
      end)

      File.mkdir_p!(target_dir)
    end
  end

  defp link_test_paths(root, project_root, test_paths) do
    for test_path <- test_paths do
      source = Path.join(project_root, test_path)
      target = Path.join(root, test_path)

      cond do
        File.dir?(source) ->
          File.mkdir_p!(Path.dirname(target))
          # Only symlink if not already mirrored (e.g. apps/supply_chain/test
          # would already exist from mirror_source_tree on apps/)
          unless File.exists?(target) do
            safe_symlink(source, target)
          end

        File.regular?(source) ->
          # Individual test file — ensure parent dir exists
          File.mkdir_p!(Path.dirname(target))

          unless File.exists?(target) do
            safe_symlink(source, target)
          end

        true ->
          :ok
      end
    end
  end

  # Symlink the entire _build tree initially. When apply_mutation is called,
  # ensure_build_copy_for_file/2 replaces the specific app's symlink with a
  # real copy so that sandbox can recompile independently.
  defp setup_build_dir(root, project_root, build_env) do
    source_build = Path.join([project_root, "_build", build_env])
    target_build = Path.join([root, "_build", build_env])

    if File.dir?(source_build) do
      File.mkdir_p!(target_build)

      source_lib = Path.join(source_build, "lib")
      target_lib = Path.join(target_build, "lib")

      if File.dir?(source_lib) do
        File.mkdir_p!(target_lib)

        # Symlink ALL app build dirs initially. Deep copies happen lazily
        # in ensure_build_copy_for_file/2 for the mutated app only.
        source_lib
        |> File.ls!()
        |> Enum.each(fn entry ->
          source_entry = Path.join(source_lib, entry)
          target_entry = Path.join(target_lib, entry)
          safe_symlink(source_entry, target_entry)
        end)
      end
    else
      File.mkdir_p!(Path.join([root, "_build", build_env, "lib"]))
    end
  end

  defp ensure_app_mirrored_for_file(sandbox, file_path) do
    case extract_app_name_from_path(file_path) do
      nil -> :ok
      app_name -> ensure_app_mirrored(sandbox, app_name)
    end
  end

  # Given a file path like "apps/supply_chain/lib/foo.ex", extract the app
  # name ("supply_chain") and ensure its _build/test/lib/<app> directory
  # is a real deep copy (not a symlink) so we can delete its beam files.
  defp ensure_build_copy_for_file(sandbox, file_path) do
    app_name = extract_app_name_from_path(file_path)
    if app_name, do: ensure_build_copy(sandbox, app_name)
  end

  defp extract_app_name_from_path(file_path) do
    case Path.split(file_path) do
      # apps/<app_name>/lib/...
      ["apps", app_name | _] -> app_name
      # lib/... (non-umbrella)
      ["lib" | _] -> detect_app_from_build()
      _ -> nil
    end
  end

  defp detect_app_from_build do
    # For non-umbrella projects, find the app name from _build
    case Path.wildcard("_build/test/lib/*/.mix/compile.elixir") do
      [path | _] -> path |> Path.split() |> Enum.at(3)
      [] -> nil
    end
  end

  defp ensure_build_copy(sandbox, app_name) do
    target_app_build = Path.join([sandbox.root, "_build", sandbox.build_env, "lib", app_name])

    source_app_build =
      Path.join([sandbox.project_root, "_build", sandbox.build_env, "lib", app_name])

    # If it's a symlink, replace with a deep copy
    case File.read_link(target_app_build) do
      {:ok, _} ->
        # It's a symlink — replace with a real copy
        File.rm!(target_app_build)
        deep_copy(source_app_build, target_app_build)

      {:error, _} ->
        # Already a real directory (from a previous mutation on same app)
        :ok
    end
  end

  # Use system cp with clone/reflink for copy-on-write when available (macOS APFS,
  # Linux btrfs/xfs). Falls back to regular copy. This is orders of magnitude
  # faster than recursive File.cp! for large directory trees.
  defp deep_copy(source, target) do
    # macOS: -c enables clonefile (COW), -R recursive
    # Linux: --reflink=auto for COW on btrfs/xfs
    case :os.type() do
      {:unix, :darwin} ->
        {_, 0} = System.cmd("cp", ["-Rc", source, target])

      {:unix, _} ->
        case System.cmd("cp", ["-R", "--reflink=auto", source, target], stderr_to_stdout: true) do
          {_, 0} -> :ok
          _ -> File.cp_r!(source, target)
        end

      _ ->
        File.cp_r!(source, target)
    end
  end

  defp safe_symlink(source, target) do
    File.rm(target)
    File.ln_s!(source, target)
  end
end
