defmodule Muex.Sandbox do
  @moduledoc """
  Creates isolated working directories for parallel mutation testing.

  Each sandbox mirrors the project structure using symlinks, with its own
  `_build` directory and a copy of the single mutated source file. This
  allows multiple `mix test` processes to run simultaneously without
  seeing each other's mutations.

  ## Structure

  A sandbox at `/tmp/muex_sandbox_<id>` looks like:

      sandbox/
      ├── mix.exs          → symlink to project
      ├── mix.lock         → symlink to project
      ├── config/          → symlink to project (if exists)
      ├── deps/            → symlink to project
      ├── test/            → symlink to project (or configured test dirs)
      ├── _build/          → deep copy of project _build (for this env)
      └── lib/             → directory of symlinks, except:
          └── mutated.ex   → real file with mutated source

  The `_build` directory is copied so each sandbox has its own compilation
  cache. Only the `_build/<env>/lib/<app>` subtree is copied; dep builds
  are symlinked.
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

    # Create lib/ as a directory of symlinks (not a single symlink)
    # so we can replace individual files with mutated copies
    mirror_source_tree(root, project_root, "lib")

    # Symlink test directories
    link_test_paths(root, project_root, test_paths)

    # Symlink deps/ (shared, read-only)
    safe_symlink(Path.join(project_root, "deps"), Path.join(root, "deps"))

    # Copy _build for this app only; symlink dep builds
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
    # original_path is relative to project root (e.g. "lib/muex/compiler.ex")
    sandbox_path = Path.join(sandbox.root, original_path)

    # Remove the symlink and write the mutated source as a real file
    File.rm(sandbox_path)

    case File.write(sandbox_path, mutated_source) do
      :ok ->
        # Delete beam file to force recompilation of this module only
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

    # Remove the mutated file and restore the symlink
    File.rm(sandbox_path)
    File.ln_s!(project_path, sandbox_path)

    :ok
  end

  @doc """
  Cleans up all sandbox directories.
  """
  @spec cleanup([sandbox()]) :: :ok
  def cleanup(sandboxes) do
    case sandboxes do
      [%{root: first_root} | _] ->
        # All sandboxes share a parent directory
        base_dir = Path.dirname(first_root)
        File.rm_rf!(base_dir)

      [] ->
        :ok
    end

    :ok
  end

  # -- Private helpers --

  defp symlink_top_level(root, project_root) do
    # Files that mix test needs at the project root
    top_level_files = ~w(mix.exs mix.lock .formatter.exs .credo.exs)

    for file <- top_level_files do
      source = Path.join(project_root, file)

      if File.exists?(source) do
        safe_symlink(source, Path.join(root, file))
      end
    end

    # Directories that can be shared read-only
    top_level_dirs = ~w(config priv)

    for dir <- top_level_dirs do
      source = Path.join(project_root, dir)

      if File.dir?(source) do
        safe_symlink(source, Path.join(root, dir))
      end
    end
  end

  defp mirror_source_tree(root, project_root, dir) do
    source_dir = Path.join(project_root, dir)
    target_dir = Path.join(root, dir)

    if File.dir?(source_dir) do
      # Walk the source tree and create matching directory structure
      # with symlinks for files
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

      # Ensure the dir itself exists even if empty
      File.mkdir_p!(target_dir)
    end
  end

  defp link_test_paths(root, project_root, test_paths) do
    for test_path <- test_paths do
      source = Path.join(project_root, test_path)
      target = Path.join(root, test_path)

      if File.dir?(source) do
        File.mkdir_p!(Path.dirname(target))
        safe_symlink(source, target)
      end
    end
  end

  defp setup_build_dir(root, project_root, build_env) do
    source_build = Path.join([project_root, "_build", build_env])
    target_build = Path.join([root, "_build", build_env])

    if File.dir?(source_build) do
      File.mkdir_p!(target_build)

      # The build dir contains lib/<app_name>/ for each compiled app.
      # Symlink all dep app dirs, but deep-copy the project's own app dir
      # so each sandbox has independent compilation state.
      source_lib = Path.join(source_build, "lib")
      target_lib = Path.join(target_build, "lib")

      if File.dir?(source_lib) do
        File.mkdir_p!(target_lib)

        # Determine the project app name from mix.exs
        app_name = detect_app_name(project_root)

        source_lib
        |> File.ls!()
        |> Enum.each(fn entry ->
          source_entry = Path.join(source_lib, entry)
          target_entry = Path.join(target_lib, entry)

          if entry == app_name do
            # Deep copy the project's own build artifacts
            deep_copy(source_entry, target_entry)
          else
            # Symlink dependency build artifacts
            safe_symlink(source_entry, target_entry)
          end
        end)
      end
    else
      # No build dir yet — the first mix test will create it
      File.mkdir_p!(Path.join([root, "_build", build_env, "lib"]))
    end
  end

  defp detect_app_name(project_root) do
    mix_exs = Path.join(project_root, "mix.exs")

    if File.exists?(mix_exs) do
      case File.read!(mix_exs) |> Code.string_to_quoted() do
        {:ok, ast} ->
          extract_app_from_mix_ast(ast) || "unknown"

        _ ->
          "unknown"
      end
    else
      "unknown"
    end
  end

  defp extract_app_from_mix_ast(ast) do
    {_, app} =
      Macro.prewalk(ast, nil, fn
        # Match `app: :name` in keyword list
        {:app, name}, _acc when is_atom(name) ->
          {{:app, name}, Atom.to_string(name)}

        # Match `@app :name` module attribute
        {:@, _, [{:app, _, [name]}]}, _acc when is_atom(name) ->
          {{:@, [], [{:app, [], [name]}]}, Atom.to_string(name)}

        node, acc ->
          {node, acc}
      end)

    app
  end

  defp deep_copy(source, target) do
    if File.dir?(source) do
      File.mkdir_p!(target)

      source
      |> File.ls!()
      |> Enum.each(fn entry ->
        deep_copy(Path.join(source, entry), Path.join(target, entry))
      end)
    else
      File.cp!(source, target)
    end
  end

  defp safe_symlink(source, target) do
    # Remove existing target if any (stale symlink, etc.)
    File.rm(target)
    File.ln_s!(source, target)
  end
end
