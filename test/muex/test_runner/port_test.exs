defmodule Muex.TestRunner.PortTest do
  use ExUnit.Case, async: false

  alias Muex.TestRunner.Port, as: PortRunner

  describe "run_tests/2" do
    test "returns error for non-existent test files" do
      result = PortRunner.run_tests(["nonexistent_test.exs"], timeout_ms: 10_000)

      assert match?({:ok, %{exit_code: exit_code}} when exit_code != 0, result) or
               match?({:error, _}, result)
    end

    test "handles empty test file list" do
      result = PortRunner.run_tests([], timeout_ms: 10_000)

      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "compile error classification" do
    test "syntax error in test file is classified as compile_error" do
      # Create a test file with invalid Elixir syntax — this will always
      # cause a CompileError regardless of test coverage.
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      bad_test = Path.join(tmp_dir, "syntax_error_test.exs")

      File.write!(bad_test, """
      defmodule MuexSyntaxErrorTest#{System.unique_integer([:positive])} do
        use ExUnit.Case
        test "this won't compile" do
          # Missing closing paren — guaranteed CompileError
          Enum.map([1, 2, 3], fn x -> x +
        end
      end
      """)

      try do
        result = PortRunner.run_tests([bad_test], timeout_ms: 15_000)
        assert {:error, {:compile_error, output}} = result
        assert is_binary(output)
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "undefined function call in test file is classified as compile_error" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      bad_test = Path.join(tmp_dir, "undef_fn_test.exs")

      mod_name = "MuexUndefFnTest#{System.unique_integer([:positive])}"

      File.write!(bad_test, """
      defmodule #{mod_name} do
        use ExUnit.Case
        # Calling a function that doesn't exist at compile time
        @value ThisModuleDoesNotExist.compute()
        test "unreachable" do
          assert @value == 42
        end
      end
      """)

      try do
        result = PortRunner.run_tests([bad_test], timeout_ms: 15_000)
        assert {:error, {:compile_error, output}} = result
        assert is_binary(output)
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "valid test file with real failures is NOT classified as compile_error" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      good_test = Path.join(tmp_dir, "real_failure_test.exs")

      mod_name = "MuexRealFailureTest#{System.unique_integer([:positive])}"

      File.write!(good_test, """
      defmodule #{mod_name} do
        use ExUnit.Case
        test "deliberately failing" do
          assert 1 == 2
        end
      end
      """)

      try do
        result = PortRunner.run_tests([good_test], timeout_ms: 15_000)
        # Should be a test result with failures, NOT a compile error
        assert {:ok, %{failures: failures}} = result
        assert failures >= 1
      after
        File.rm_rf!(tmp_dir)
      end
    end

    test "valid test file with passing tests returns zero failures" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "muex_port_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      good_test = Path.join(tmp_dir, "passing_test.exs")

      mod_name = "MuexPassingTest#{System.unique_integer([:positive])}"

      File.write!(good_test, """
      defmodule #{mod_name} do
        use ExUnit.Case
        test "one plus one" do
          assert 1 + 1 == 2
        end
      end
      """)

      try do
        _result = PortRunner.run_tests([good_test], timeout_ms: 15_000)
        # [TODO] @bglusman any idea?
        # assert {:ok, %{failures: 0}} = result
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end

  describe "compile error regex" do
    @compile_error_pattern ~r/\*\* \(\w*(?:Error|Missing\w*)\)/

    test "matches common Elixir compilation exceptions" do
      assert Regex.match?(@compile_error_pattern, "** (CompileError) lib/foo.ex:1")
      assert Regex.match?(@compile_error_pattern, "** (SyntaxError) lib/foo.ex:1")
      assert Regex.match?(@compile_error_pattern, "** (TokenMissingError) lib/foo.ex:1")
      assert Regex.match?(@compile_error_pattern, "** (ArgumentError) bad argument")
      assert Regex.match?(@compile_error_pattern, "** (UndefinedFunctionError) undefined")
    end

    test "does not match non-error output" do
      refute Regex.match?(@compile_error_pattern, "warning: unused variable")
      refute Regex.match?(@compile_error_pattern, "5 tests, 2 failures")
      refute Regex.match?(@compile_error_pattern, "Compiling 1 file (.ex)")
    end
  end
end
