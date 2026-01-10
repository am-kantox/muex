defmodule Muex.ReporterTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Muex.Reporter

  describe "print_summary/1" do
    test "prints basic mutation score" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Total mutants: 3"
      assert output =~ "Killed: 2"
      assert output =~ "Survived: 1"
      assert output =~ "Mutation Score: 66.67%"
    end

    test "handles all killed mutations" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :killed, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Total mutants: 2"
      assert output =~ "Killed: 2"
      assert output =~ "Survived: 0"
      assert output =~ "Mutation Score: 100.0%"
    end

    test "handles all survived mutations" do
      results = [
        %{result: :survived, mutation: test_mutation()},
        %{result: :survived, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Total mutants: 2"
      assert output =~ "Killed: 0"
      assert output =~ "Survived: 2"
      assert output =~ "Mutation Score: 0.0%"
    end

    test "reports invalid mutations" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :invalid, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Invalid: 1"
    end

    test "reports timeout mutations" do
      results = [
        %{result: :killed, mutation: test_mutation()},
        %{result: :timeout, mutation: test_mutation()}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Timeout: 1"
    end

    test "shows survived mutations details" do
      mutation = %{
        description: "Arithmetic: + to -",
        location: %{file: "lib/calc.ex", line: 5}
      }

      results = [
        %{result: :survived, mutation: mutation}
      ]

      output = capture_io(fn -> Reporter.print_summary(results) end)

      assert output =~ "Survived Mutations"
      assert output =~ "lib/calc.ex:5"
      assert output =~ "Arithmetic: + to -"
    end

    test "handles empty results" do
      output = capture_io(fn -> Reporter.print_summary([]) end)

      assert output =~ "Total mutants: 0"
      assert output =~ "Mutation Score: 0.0%"
    end
  end

  describe "print_progress/3" do
    test "prints progress for killed mutation" do
      result = %{result: :killed, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 5, 10) end)

      assert output =~ "[5/10]"
      assert output =~ "✓"
    end

    test "prints progress for survived mutation" do
      result = %{result: :survived, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 3, 10) end)

      assert output =~ "[3/10]"
      assert output =~ "✗"
    end

    test "prints progress for invalid mutation" do
      result = %{result: :invalid, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 7, 10) end)

      assert output =~ "[7/10]"
      assert output =~ "!"
    end

    test "prints progress for timeout mutation" do
      result = %{result: :timeout, mutation: test_mutation()}

      output = capture_io(fn -> Reporter.print_progress(result, 2, 10) end)

      assert output =~ "[2/10]"
      assert output =~ "⏱"
    end
  end

  defp test_mutation do
    %{
      description: "Test mutation",
      location: %{file: "test.ex", line: 1}
    }
  end
end
