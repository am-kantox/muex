defmodule Muex.ConfigTest do
  use ExUnit.Case, async: true

  alias Muex.Config

  describe "from_args/1" do
    test "returns defaults when no args provided" do
      assert {:ok, config} = Config.from_args([])
      assert config.files == "lib"
      assert config.test_paths == ["test"]
      assert config.app == nil
      assert config.language == Muex.Language.Elixir
      assert config.filter == true
      assert config.verbose == false
      assert config.optimize == true
      assert config.optimize_level == "balanced"
      assert config.format == "terminal"
      assert config.fail_at == 100
      assert config.timeout_ms == 5000
      assert config.max_mutations == 0
      assert config.min_score == 20
      assert config.min_complexity == nil
      assert config.max_per_function == nil
      assert Muex.Mutator.Literal in config.mutators
      assert length(config.mutators) == 6
    end

    test "parses --files flag" do
      assert {:ok, config} = Config.from_args(["--files", "lib/my_app"])
      assert config.files == "lib/my_app"
    end

    test "parses --path as synonym for --files" do
      assert {:ok, config} = Config.from_args(["--path", "lib/my_app"])
      assert config.files == "lib/my_app"
    end

    test "--files takes precedence over --path" do
      assert {:ok, config} = Config.from_args(["--path", "path_val", "--files", "files_val"])
      assert config.files == "files_val"
    end

    test "returns error for invalid options" do
      assert {:error, msg} = Config.from_args(["--bogus", "foo"])
      assert msg =~ "Invalid options"
    end

    test "parses --language erlang" do
      assert {:ok, config} = Config.from_args(["--language", "erlang"])
      assert config.language == Muex.Language.Erlang
    end

    test "returns error for unknown language" do
      assert {:error, msg} = Config.from_args(["--language", "python"])
      assert msg =~ "Unknown language"
    end

    test "parses --mutators" do
      assert {:ok, config} = Config.from_args(["--mutators", "arithmetic,boolean"])
      assert config.mutators == [Muex.Mutator.Arithmetic, Muex.Mutator.Boolean]
    end

    test "returns error for unknown mutator" do
      assert {:error, msg} = Config.from_args(["--mutators", "arithmetic,bogus"])
      assert msg =~ "Unknown mutator: bogus"
    end

    test "parses --no-filter" do
      assert {:ok, config} = Config.from_args(["--no-filter"])
      assert config.filter == false
    end

    test "parses --no-optimize" do
      assert {:ok, config} = Config.from_args(["--no-optimize"])
      assert config.optimize == false
    end

    test "parses --optimize explicitly" do
      assert {:ok, config} = Config.from_args(["--optimize"])
      assert config.optimize == true
    end

    test "returns error for invalid optimize level" do
      assert {:error, msg} = Config.from_args(["--optimize-level", "ludicrous"])
      assert msg =~ "Unknown optimization level"
    end

    test "parses numeric options" do
      assert {:ok, config} =
               Config.from_args([
                 "--concurrency",
                 "8",
                 "--timeout",
                 "10000",
                 "--fail-at",
                 "80",
                 "--min-score",
                 "30",
                 "--max-mutations",
                 "500",
                 "--min-complexity",
                 "5",
                 "--max-per-function",
                 "10"
               ])

      assert config.concurrency == 8
      assert config.timeout_ms == 10_000
      assert config.fail_at == 80
      assert config.min_score == 30
      assert config.max_mutations == 500
      assert config.min_complexity == 5
      assert config.max_per_function == 10
    end

    test "parses --format" do
      assert {:ok, config} = Config.from_args(["--format", "json"])
      assert config.format == "json"
    end
  end

  describe "umbrella support via --app" do
    test "sets files to apps/<app>/lib" do
      assert {:ok, config} = Config.from_args(["--app", "my_app"])
      assert config.app == "my_app"
      assert config.files == "apps/my_app/lib"
    end

    test "sets test_paths to apps/<app>/test" do
      assert {:ok, config} = Config.from_args(["--app", "my_app"])
      assert config.test_paths == ["apps/my_app/test"]
    end

    test "explicit --files overrides --app for files" do
      assert {:ok, config} =
               Config.from_args(["--app", "my_app", "--files", "custom/lib"])

      assert config.app == "my_app"
      assert config.files == "custom/lib"
    end

    test "explicit --test-paths overrides --app for test_paths" do
      assert {:ok, config} =
               Config.from_args(["--app", "my_app", "--test-paths", "custom/test"])

      assert config.app == "my_app"
      assert config.test_paths == ["custom/test"]
    end

    test "both --files and --test-paths override --app" do
      assert {:ok, config} =
               Config.from_args([
                 "--app",
                 "my_app",
                 "--files",
                 "custom/lib",
                 "--test-paths",
                 "custom/test,shared/test"
               ])

      assert config.files == "custom/lib"
      assert config.test_paths == ["custom/test", "shared/test"]
    end
  end

  describe "test-paths parsing" do
    test "single directory" do
      assert {:ok, config} = Config.from_args(["--test-paths", "test"])
      assert config.test_paths == ["test"]
    end

    test "multiple comma-separated directories" do
      assert {:ok, config} =
               Config.from_args(["--test-paths", "test/unit,test/integration"])

      assert config.test_paths == ["test/unit", "test/integration"]
    end

    test "glob patterns preserved" do
      assert {:ok, config} =
               Config.from_args(["--test-paths", "test/**/*_test.exs"])

      assert config.test_paths == ["test/**/*_test.exs"]
    end

    test "mixed directories and globs" do
      assert {:ok, config} =
               Config.from_args([
                 "--test-paths",
                 "test/unit,integration/**/*_test.exs,test/specific_test.exs"
               ])

      assert config.test_paths == [
               "test/unit",
               "integration/**/*_test.exs",
               "test/specific_test.exs"
             ]
    end

    test "trims whitespace around entries" do
      assert {:ok, config} =
               Config.from_args(["--test-paths", " test/unit , test/integration "])

      assert config.test_paths == ["test/unit", "test/integration"]
    end

    test "filters out empty entries" do
      assert {:ok, config} =
               Config.from_args(["--test-paths", "test,,test/unit,"])

      assert config.test_paths == ["test", "test/unit"]
    end
  end

  describe "from_opts/1" do
    test "builds config from keyword list" do
      assert {:ok, config} =
               Config.from_opts(
                 files: "lib/my_app",
                 test_paths: "spec,test",
                 language: "elixir",
                 verbose: true
               )

      assert config.files == "lib/my_app"
      assert config.test_paths == ["spec", "test"]
      assert config.verbose == true
    end

    test "app sets default paths" do
      assert {:ok, config} = Config.from_opts(app: "billing")
      assert config.files == "apps/billing/lib"
      assert config.test_paths == ["apps/billing/test"]
    end
  end

  describe "optimizer_opts/1" do
    test "conservative preset" do
      assert {:ok, config} = Config.from_args(["--optimize-level", "conservative"])
      opts = Config.optimizer_opts(config)
      assert opts[:enabled] == true
      assert opts[:min_complexity] == 1
      assert opts[:max_mutations_per_function] == 50
    end

    test "balanced preset (default)" do
      assert {:ok, config} = Config.from_args([])
      opts = Config.optimizer_opts(config)
      assert opts[:min_complexity] == 2
      assert opts[:max_mutations_per_function] == 20
    end

    test "aggressive preset" do
      assert {:ok, config} = Config.from_args(["--optimize-level", "aggressive"])
      opts = Config.optimizer_opts(config)
      assert opts[:min_complexity] == 3
      assert opts[:max_mutations_per_function] == 10
    end

    test "min_complexity override" do
      assert {:ok, config} = Config.from_args(["--min-complexity", "7"])
      opts = Config.optimizer_opts(config)
      assert opts[:min_complexity] == 7
    end

    test "max_per_function override" do
      assert {:ok, config} = Config.from_args(["--max-per-function", "42"])
      opts = Config.optimizer_opts(config)
      assert opts[:max_mutations_per_function] == 42
    end
  end

  describe "resolve_test_files/1" do
    test "expands directory to test files" do
      assert {:ok, config} = Config.from_args(["--test-paths", "test"])
      files = Config.resolve_test_files(config)
      # Our project has test files in test/
      assert match?([_ | _], files)
      assert Enum.all?(files, &String.ends_with?(&1, "_test.exs"))
    end

    test "glob patterns are expanded" do
      assert {:ok, config} = Config.from_args(["--test-paths", "test/muex/*_test.exs"])
      files = Config.resolve_test_files(config)
      assert match?([_ | _], files)
      assert Enum.all?(files, &String.starts_with?(&1, "test/muex/"))
    end

    test "nonexistent path returns empty" do
      assert {:ok, config} = Config.from_args(["--test-paths", "nonexistent_dir"])
      files = Config.resolve_test_files(config)
      assert files == []
    end

    test "multiple test paths are all expanded and deduped" do
      assert {:ok, config} =
               Config.from_args(["--test-paths", "test/muex,test/muex"])

      files = Config.resolve_test_files(config)
      # Should be deduped
      assert files == Enum.uniq(files)
    end
  end
end
