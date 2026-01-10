defmodule Muex.LoaderTest do
  use ExUnit.Case, async: true

  alias Muex.Language.Elixir, as: ElixirAdapter
  alias Muex.Loader

  @moduletag :tmp_dir

  describe "load/3" do
    test "loads source files from directory", %{tmp_dir: tmp_dir} do
      # Create a test file
      test_file = Path.join(tmp_dir, "calculator.ex")

      File.write!(test_file, """
      defmodule TestCalc do
        def add(a, b), do: a + b
      end
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      assert [_] = files
      assert [file] = files
      assert file.path == test_file
      assert file.module_name == TestCalc
      assert file.ast != nil
    end

    test "loads multiple source files", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "module1.ex"), """
      defmodule Module1 do
        def foo, do: :ok
      end
      """)

      File.write!(Path.join(tmp_dir, "module2.ex"), """
      defmodule Module2 do
        def bar, do: :ok
      end
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      assert [_, _] = files
      assert Enum.any?(files, &(&1.module_name == Module1))
      assert Enum.any?(files, &(&1.module_name == Module2))
    end

    test "excludes test files by default", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "module.ex"), """
      defmodule TestModule do
        def foo, do: :ok
      end
      """)

      File.write!(Path.join(tmp_dir, "module_test.exs"), """
      defmodule TestModuleTest do
        use ExUnit.Case
      end
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      assert [_] = files
      refute Enum.any?(files, &String.ends_with?(&1.path, "_test.exs"))
    end

    test "excludes files matching custom patterns", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "module.ex"), """
      defmodule Module do
        def foo, do: :ok
      end
      """)

      File.write!(Path.join(tmp_dir, "skip_me.ex"), """
      defmodule SkipMe do
        def bar, do: :ok
      end
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter, exclude: ["skip_me"])

      assert [_] = files
      refute Enum.any?(files, &String.contains?(&1.path, "skip_me"))
    end

    test "handles files in subdirectories", %{tmp_dir: tmp_dir} do
      subdir = Path.join(tmp_dir, "sub")
      File.mkdir_p!(subdir)

      File.write!(Path.join(subdir, "nested.ex"), """
      defmodule Nested do
        def baz, do: :ok
      end
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      assert [_] = files
      assert Enum.any?(files, &(&1.module_name == Nested))
    end

    test "handles files without module definition", %{tmp_dir: tmp_dir} do
      test_file = Path.join(tmp_dir, "script.ex")

      File.write!(test_file, """
      IO.puts("Hello")
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      assert [_] = files
      assert [file] = files
      assert file.module_name == nil
    end

    test "skips files with parse errors", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "good.ex"), """
      defmodule Good do
        def foo, do: :ok
      end
      """)

      File.write!(Path.join(tmp_dir, "bad.ex"), """
      defmodule Bad do
        # syntax error
        def foo, do
      end
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      # Should only load the good file
      assert [_] = files
      assert [file] = files
      assert file.module_name == Good
    end

    test "returns empty list when no files found", %{tmp_dir: tmp_dir} do
      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      assert [] = files
    end

    test "handles both .ex and .exs extensions", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "module.ex"), """
      defmodule ModuleEx do
        def foo, do: :ok
      end
      """)

      File.write!(Path.join(tmp_dir, "script.exs"), """
      defmodule ModuleExs do
        def bar, do: :ok
      end
      """)

      {:ok, files} = Loader.load(tmp_dir, ElixirAdapter)

      assert [_, _] = files
      assert Enum.any?(files, &(&1.module_name == ModuleEx))
      assert Enum.any?(files, &(&1.module_name == ModuleExs))
    end
  end
end
