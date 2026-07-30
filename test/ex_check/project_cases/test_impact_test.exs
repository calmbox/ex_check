defmodule ExCheck.ProjectCases.TestImpactTest do
  use ExCheck.ProjectCase, async: true

  test "bootstraps conservatively and then runs no tests for an unchanged generation", %{
    project_dir: project_dir
  } do
    first = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)

    assert first =~ "full fallback run"
    assert first =~ "fallback: missing"
    assert first =~ "manifest:"
    assert first =~ "Result: 2 passed"

    second = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)

    assert second =~ "selected run"
    assert second =~ "changed inputs: 0"
    assert second =~ "selected test files: 0"
    assert second =~ "No affected tests"
    refute second =~ "Running ExUnit"
  end

  test "selects a test through compile/export references after a source change", %{
    project_dir: project_dir
  } do
    bootstrap(project_dir)
    source = Path.join(project_dir, "lib/test_project.ex")
    File.write!(source, File.read!(source) <> "\n# changed source generation\n")

    output = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)

    assert output =~ "selected run"
    assert output =~ "changed: lib/test_project.ex"
    assert output =~ "test: test/test_project_test.exs"
    assert output =~ "Result: 2 passed"
  end

  test "does not advance state after failure and discovers a new untracked test", %{
    project_dir: project_dir
  } do
    bootstrap(project_dir)
    test_path = Path.join(project_dir, "test/new_failure_test.exs")

    File.write!(test_path, failing_test(":expected"))

    failed = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 1)
    assert failed =~ "test: test/new_failure_test.exs"
    assert failed =~ "Failed: 1 test"

    File.write!(test_path, failing_test(":actual"))

    retried = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)
    assert retried =~ "test: test/new_failure_test.exs"
    assert retried =~ "Result: 1 passed"

    unchanged = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)
    assert unchanged =~ "No affected tests"
  end

  test "falls back for configuration and corrupt state while full always runs all tests", %{
    project_dir: project_dir
  } do
    bootstrap(project_dir)
    config = Path.join(project_dir, ".check.exs")
    File.write!(config, File.read!(config) <> "\n# changed configuration\n")

    config_output = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)
    assert config_output =~ "full fallback run"
    assert config_output =~ "fallback: .check.exs"

    state_path = impact_state_path(project_dir)
    File.write!(state_path, "corrupt")

    corrupt_output = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)
    assert corrupt_output =~ "fallback: corrupt impact snapshot"
    assert corrupt_output =~ "Result: 2 passed"

    test_manifest = Path.join(Path.dirname(state_path), "compile.test_stale")
    File.write!(test_manifest, "corrupt")

    manifest_output = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)
    assert manifest_output =~ "fallback: corrupt test-reference manifest"
    assert manifest_output =~ "Result: 2 passed"

    full_output = run_check(project_dir, ~w[--debug --full --only ex_unit], 0)
    assert full_output =~ "full fallback run"
    assert full_output =~ "fallback: explicit --full"
    assert full_output =~ "Result: 2 passed"
  end

  test "explains a failing affected set without executing it", %{project_dir: project_dir} do
    bootstrap(project_dir)
    source = Path.join(project_dir, "lib/test_project.ex")

    source
    |> File.read!()
    |> String.replace("def hello do\n    :world\n  end", "def hello do\n    :universe\n  end")
    |> then(&File.write!(source, &1))

    explanation = run_check(project_dir, ~w[--explain --no-retry], 0)

    assert explanation =~ "fast explain mode check"
    assert explanation =~ "test: test/test_project_test.exs"
    refute explanation =~ "Running ExUnit"

    failed = run_check(project_dir, ~w[--only ex_unit --no-retry], 1)
    assert failed =~ "Failed: 1 doctest, 1 test"
  end

  test "uses the previous snapshot to select tests after a source rename", %{
    project_dir: project_dir
  } do
    original_source = Path.join(project_dir, "lib/renamed_source.ex")
    moved_source = Path.join(project_dir, "lib/moved_source.ex")
    test_path = Path.join(project_dir, "test/renamed_source_test.exs")

    File.write!(original_source, "defmodule RenamedSource do\n  def value, do: :ok\nend\n")

    File.write!(test_path, """
    defmodule RenamedSourceTest do
      use ExUnit.Case, async: true

      test "retains dependency selection across a source rename" do
        assert RenamedSource.value() == :ok
      end
    end
    """)

    bootstrap(project_dir)
    File.rename!(original_source, moved_source)

    output = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)

    assert output =~ "selected run"
    assert output =~ "changed: lib/moved_source.ex"
    assert output =~ "changed: lib/renamed_source.ex"
    assert output =~ "test: test/renamed_source_test.exs"
    assert output =~ "Result: 1 passed"
  end

  test "runs a directly changed test whose path contains spaces", %{project_dir: project_dir} do
    bootstrap(project_dir)
    test_path = Path.join(project_dir, "test/path with spaces_test.exs")

    File.write!(test_path, """
    defmodule PathWithSpacesTest do
      use ExUnit.Case, async: true

      test "is passed to Mix as one argument" do
        assert :ok == :ok
      end
    end
    """)

    output = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)

    assert output =~ "test: test/path with spaces_test.exs"
    assert output =~ "Result: 1 passed"
  end

  test "falls back when the selected test command exceeds safe argument limits", %{
    project_dir: project_dir
  } do
    bootstrap(project_dir)

    for index <- 1..501 do
      File.write!(Path.join(project_dir, "test/generated_#{index}_test.exs"), "# generated\n")
    end

    output = run_check(project_dir, ~w[--explain --only ex_unit --no-retry], 0)

    assert output =~ "full fallback explain"
    assert output =~ "fallback: selected test command exceeds safe argument limits"
    assert output =~ "selected test files: 502"
  end

  test "restores manifests and state when inputs change during selected tests", %{
    project_dir: project_dir
  } do
    marker = Path.join(System.tmp_dir!(), "ex_check_mid_run_#{System.unique_integer([:positive])}")
    slow_test = Path.join(project_dir, "test/slow_generation_test.exs")
    on_exit(fn -> File.rm(marker) end)

    File.write!(slow_test, """
    defmodule SlowGenerationTest do
      use ExUnit.Case, async: true

      test "holds the selected generation open" do
        File.write!(#{inspect(marker)}, "started")
        Process.sleep(500)
        assert TestProject.hello() == :world
      end
    end
    """)

    bootstrap(project_dir)
    File.rm(marker)

    state_path = impact_state_path(project_dir)
    manifest_path = Path.join(Path.dirname(state_path), "compile.test_stale")
    state_before = File.read!(state_path)
    manifest_before = File.read!(manifest_path)

    source = Path.join(project_dir, "lib/test_project.ex")
    File.write!(source, File.read!(source) <> "\n# generation one\n")

    check_task =
      Task.async(fn ->
        System.cmd("mix", ["check", "--only", "ex_unit", "--no-retry"],
          cd: project_dir,
          stderr_to_stdout: true
        )
      end)

    wait_for_file!(marker)
    File.write!(source, File.read!(source) <> "# generation two\n")

    changed_output = check_task |> Task.await(30_000) |> cmd_exit(1)

    assert changed_output =~ "inputs changed while affected tests were running"
    assert File.read!(state_path) == state_before
    assert File.read!(manifest_path) == manifest_before

    retried = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)
    assert retried =~ "test: test/slow_generation_test.exs"
  end

  test "hides impact diagnostics unless debug or explain is requested", %{project_dir: project_dir} do
    bootstrap(project_dir)
    source = Path.join(project_dir, "lib/test_project.ex")
    File.write!(source, File.read!(source) <> "\n# quiet generation\n")

    quiet = run_check(project_dir, ~w[--only ex_unit --no-retry], 0)

    refute quiet =~ "ex_check test impact"
    refute quiet =~ "generation:"
    refute quiet =~ "changed inputs:"
    refute quiet =~ "selected test files:"
    refute quiet =~ "No affected tests"

    debug = run_check(project_dir, ~w[--debug --only ex_unit --no-retry], 0)

    assert debug =~ "ex_check test impact: selected run"
    assert debug =~ "generation:"
    assert debug =~ "changed inputs: 0"
    assert debug =~ "selected test files: 0"
    assert debug =~ "No affected tests"
  end

  defp bootstrap(project_dir) do
    run_check(project_dir, ~w[--only ex_unit --no-retry], 0)
  end

  defp run_check(project_dir, args, exit_code) do
    System.cmd("mix", ["check" | args], cd: project_dir, stderr_to_stdout: true)
    |> cmd_exit(exit_code)
  end

  defp impact_state_path(project_dir) do
    Path.join(project_dir, "_build/test/lib/test_project/.mix/ex_check.test_impact")
  end

  defp failing_test(expected) do
    """
    defmodule TestProject.NewFailureTest do
      use ExUnit.Case, async: true

      test "new test is selected" do
        assert :actual == #{expected}
      end
    end
    """
  end

  defp wait_for_file!(path, remaining_ms \\ 30_000)

  defp wait_for_file!(path, remaining_ms) when remaining_ms > 0 do
    if File.exists?(path) do
      :ok
    else
      Process.sleep(10)
      wait_for_file!(path, remaining_ms - 10)
    end
  end

  defp wait_for_file!(path, 0), do: raise("timed out waiting for #{path}")
end
