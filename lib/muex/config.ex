defmodule Muex.Config do
  @moduledoc """
  Central configuration for Muex mutation testing runs.

  Parses command-line arguments into a normalized struct consumed by the
  pipeline. Supports umbrella apps (`--app`), explicit test paths
  (`--test-paths`), and all existing flags.

  ## Compile-Time Configuration

  Custom language adapters and mutators can be registered via
  `Application.compile_env/3` in `config/config.exs` (or any imported
  config file). These maps are merged into the built-in adapters/mutators
  at compile time.

    * `:languages` - A `%{String.t() => module()}` map of additional
      language adapters. Each key is the CLI name passed to `--language`
      and the value is a module implementing the `Muex.Language` behaviour.

          config :muex, languages: %{"lua" => MyApp.Language.Lua}

    * `:mutators` - A `%{String.t() => module()}` map of additional
      mutators. Each key is the CLI name usable in `--mutators` and the
      value is a module implementing the `Muex.Mutator` behaviour.

          config :muex, mutators: %{"string" => MyApp.Mutator.String}

  The built-in language adapters (`"elixir"`, `"erlang"`) and mutators
  (`"arithmetic"`, `"comparison"`, `"boolean"`, `"literal"`,
  `"function_call"`, `"conditional"`) are always available. Entries in the
  compile-time maps override built-in entries with the same key.

  ## CLI Options

    * `--files` / `--path` - Source directory, file, or glob pattern (default: `"lib"`)
    * `--test-paths` - Comma-separated list of test directories, files, or glob
      patterns (default: `"test"`). Each entry is resolved independently: a
      directory is expanded to `dir/**/*_test.exs`, a glob is used as-is, and a
      regular file is taken literally.
    * `--app` - Target a single OTP application inside an umbrella project.
      Sets `--files` to `apps/<app>/lib` and `--test-paths` to
      `apps/<app>/test` unless those flags are provided explicitly.
    * `--language` - Language adapter: `elixir` or `erlang` (default: `elixir`)
    * `--mutators` - Comma-separated list of mutator names (default: all)
    * `--concurrency` - Number of parallel workers (default: number of schedulers)
    * `--timeout` - Test timeout in milliseconds (default: 5000)
    * `--fail-at` - Minimum mutation score percentage to pass (default: 100)
    * `--format` - Output format: `terminal`, `json`, `html` (default: `terminal`)
    * `--min-score` - Minimum file complexity score for inclusion (default: 20)
    * `--max-mutations` - Cap total mutations tested; 0 = unlimited (default: 0)
    * `--no-filter` - Disable intelligent file filtering
    * `--verbose` - Show detailed progress information
    * `--optimize` / `--no-optimize` - Enable/disable mutation optimization (default: enabled)
    * `--optimize-level` - Preset: `conservative`, `balanced`, `aggressive` (default: `balanced`)
    * `--min-complexity` - Override minimum complexity for optimizer
    * `--max-per-function` - Override maximum mutations per function for optimizer
  """

  @type t :: %__MODULE__{
          files: String.t(),
          test_paths: [String.t()],
          app: String.t() | nil,
          language: module(),
          mutators: [module()],
          concurrency: pos_integer(),
          timeout_ms: pos_integer(),
          fail_at: number(),
          format: String.t(),
          min_score: non_neg_integer(),
          max_mutations: non_neg_integer(),
          filter: boolean(),
          verbose: boolean(),
          optimize: boolean(),
          optimize_level: String.t(),
          min_complexity: non_neg_integer() | nil,
          max_per_function: pos_integer() | nil
        }

  @enforce_keys [:files, :test_paths, :language, :mutators]
  defstruct [
    :files,
    :test_paths,
    :app,
    :language,
    :mutators,
    concurrency: 4,
    timeout_ms: 5000,
    fail_at: 100,
    format: "terminal",
    min_score: 20,
    max_mutations: 0,
    filter: true,
    verbose: false,
    optimize: true,
    optimize_level: "balanced",
    min_complexity: nil,
    max_per_function: nil
  ]

  @option_spec [
    files: :string,
    path: :string,
    test_paths: :string,
    app: :string,
    language: :string,
    mutators: :string,
    concurrency: :integer,
    timeout: :integer,
    fail_at: :integer,
    format: :string,
    min_score: :integer,
    max_mutations: :integer,
    no_filter: :boolean,
    verbose: :boolean,
    optimize: :boolean,
    no_optimize: :boolean,
    optimize_level: :string,
    min_complexity: :integer,
    max_per_function: :integer
  ]

  @doc """
  Parses a list of CLI argument strings into a `%Config{}`.

  Returns `{:ok, config}` or `{:error, reason}`.
  """
  @spec from_args([String.t()]) :: {:ok, t()} | {:error, String.t()}
  def from_args(args) do
    case OptionParser.parse(args, strict: @option_spec) do
      {_opts, _rest, [_ | _] = invalid} ->
        {:error, "Invalid options: #{inspect(invalid)}"}

      {opts, _rest, _} ->
        from_opts(opts)
    end
  end

  @doc """
  Builds a `%Config{}` from a keyword list (already parsed by OptionParser or
  assembled programmatically).

  Returns `{:ok, config}` or `{:error, reason}`.
  """
  @spec from_opts(keyword()) :: {:ok, t()} | {:error, String.t()}
  def from_opts(opts) do
    app = Keyword.get(opts, :app)

    with {:ok, language} <- resolve_language(Keyword.get(opts, :language, "elixir")),
         {:ok, mutators} <- resolve_mutators(Keyword.get(opts, :mutators)),
         {:ok, optimize_level} <-
           validate_optimize_level(Keyword.get(opts, :optimize_level, "balanced")) do
      config = %__MODULE__{
        files: resolve_files(opts, app),
        test_paths: resolve_test_paths(opts, app),
        app: app,
        language: language,
        mutators: mutators,
        concurrency: Keyword.get(opts, :concurrency, System.schedulers_online()),
        timeout_ms: Keyword.get(opts, :timeout, 5000),
        fail_at: Keyword.get(opts, :fail_at, 100),
        format: Keyword.get(opts, :format, "terminal"),
        min_score: Keyword.get(opts, :min_score, 20),
        max_mutations: Keyword.get(opts, :max_mutations, 0),
        filter: not Keyword.get(opts, :no_filter, false),
        verbose: Keyword.get(opts, :verbose, false),
        optimize: resolve_optimize(opts),
        optimize_level: optimize_level,
        min_complexity: Keyword.get(opts, :min_complexity),
        max_per_function: Keyword.get(opts, :max_per_function)
      }

      {:ok, config}
    end
  end

  @doc """
  Returns optimizer options derived from the config's optimization settings.
  """
  @spec optimizer_opts(t()) :: keyword()
  def optimizer_opts(%__MODULE__{} = config) do
    base =
      case config.optimize_level do
        "conservative" ->
          [
            enabled: true,
            min_complexity: 1,
            max_mutations_per_function: 50,
            cluster_similarity_threshold: 0.8,
            keep_boundary_mutations: true
          ]

        "balanced" ->
          [
            enabled: true,
            min_complexity: 2,
            max_mutations_per_function: 20,
            cluster_similarity_threshold: 0.8,
            keep_boundary_mutations: true
          ]

        "aggressive" ->
          [
            enabled: true,
            min_complexity: 3,
            max_mutations_per_function: 10,
            cluster_similarity_threshold: 0.8,
            keep_boundary_mutations: true
          ]
      end

    base =
      if config.min_complexity do
        Keyword.put(base, :min_complexity, config.min_complexity)
      else
        base
      end

    if config.max_per_function do
      Keyword.put(base, :max_mutations_per_function, config.max_per_function)
    else
      base
    end
  end

  @doc """
  Resolves `test_paths` entries into actual test file paths on disk.

  Each entry in `test_paths` is treated as follows:
    - Directory → expands to `dir/**/*_test.exs`
    - Glob pattern (contains `*` or `?`) → expanded via `Path.wildcard/1`
    - Regular file → taken literally
  """
  @spec resolve_test_files(t()) :: [Path.t()]
  def resolve_test_files(%__MODULE__{test_paths: paths}) do
    expand_test_paths(paths)
  end

  @doc """
  Expands a list of test path entries into actual file paths on disk.

  Each entry is treated as follows:
    - Directory -> expands to `dir/**/*_test.exs`
    - Glob pattern (contains `*` or `?`) -> expanded via `Path.wildcard/1`
    - Regular file -> taken literally
    - Other -> attempted as a wildcard pattern
  """
  @spec expand_test_paths([String.t()]) :: [Path.t()]
  def expand_test_paths(paths) when is_list(paths) do
    paths
    |> Enum.flat_map(&expand_test_path/1)
    |> Enum.uniq()
  end

  @doc """
  Expands a single test path entry into matching file paths.

  Handles directories, glob patterns, regular files, and fallback wildcard.
  """
  @spec expand_test_path(String.t()) :: [Path.t()]
  def expand_test_path(path) do
    cond do
      String.contains?(path, ["*", "?"]) ->
        Path.wildcard(path)

      File.dir?(path) ->
        Path.wildcard(Path.join([path, "**", "*_test.exs"]))

      File.regular?(path) ->
        [path]

      true ->
        # Might be a pattern that doesn't match anything yet, try wildcard
        Path.wildcard(path)
    end
  end

  # -- Private resolution helpers --

  defp resolve_files(opts, app) do
    explicit = Keyword.get(opts, :files) || Keyword.get(opts, :path)

    cond do
      explicit -> explicit
      app -> Path.join(["apps", app, "lib"])
      true -> "lib"
    end
  end

  defp resolve_test_paths(opts, app) do
    case Keyword.get(opts, :test_paths) do
      nil ->
        if app do
          [Path.join(["apps", app, "test"])]
        else
          ["test"]
        end

      raw ->
        raw
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end

  defp resolve_optimize(opts) do
    cond do
      Keyword.get(opts, :no_optimize, false) -> false
      Keyword.has_key?(opts, :optimize) -> Keyword.get(opts, :optimize)
      true -> true
    end
  end

  @language_map %{
                  "elixir" => Muex.Language.Elixir,
                  "erlang" => Muex.Language.Erlang
                }
                |> Map.merge(Application.compile_env(:muex, :languages, %{}))

  defp resolve_language(name) do
    with module <-
           Map.get_lazy(@language_map, name, fn ->
             Module.concat([Muex.Language, Macro.camelize(name)])
           end),
         {:module, ^module} <- Code.ensure_loaded(module),
         do: {:ok, module},
         else: (_ -> {:error, "Unknown language: #{name}"})
  end

  @mutator_map %{
                 "arithmetic" => Muex.Mutator.Arithmetic,
                 "comparison" => Muex.Mutator.Comparison,
                 "boolean" => Muex.Mutator.Boolean,
                 "literal" => Muex.Mutator.Literal,
                 "function_call" => Muex.Mutator.FunctionCall,
                 "conditional" => Muex.Mutator.Conditional
               }
               |> Map.merge(Application.compile_env(:muex, :mutators, %{}))

  @all_mutators Map.values(@mutator_map)

  defp resolve_mutators(nil), do: {:ok, @all_mutators}

  defp resolve_mutators(raw) do
    names = raw |> String.split(",") |> Enum.map(&String.trim/1)

    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, acc} ->
      case Map.fetch(@mutator_map, name) do
        {:ok, mod} -> {:cont, {:ok, acc ++ [mod]}}
        :error -> {:halt, {:error, "Unknown mutator: #{name}"}}
      end
    end)
  end

  defp validate_optimize_level(level) when level in ~w(conservative balanced aggressive) do
    {:ok, level}
  end

  defp validate_optimize_level(other) do
    {:error, "Unknown optimization level: #{other}. Use conservative, balanced, or aggressive"}
  end
end
