defmodule ExCheck.ProjectCases.ManifestTest do
  use ExCheck.ProjectCase, async: true

  test "formatter issue", %{project_dir: project_dir} do
    invalid_file_path =
      project_dir
      |> Path.join("lib")
      |> Path.join("invalid.ex")

    File.write!(invalid_file_path, "IO.inspect( 1 )")

    output = System.cmd("mix", ~w[check --manifest manifest.txt], cd: project_dir) |> cmd_exit(1)

    assert output =~ "compiler success"
    assert output =~ "formatter error code 1"
    assert output =~ "ex_unit success"
    assert output =~ "credo skipped due to missing package credo"
    refute output =~ "sobelow"
    refute output =~ "dialyzer"
    assert output =~ "ex_doc skipped due to missing package ex_doc"

    manifest = File.read!(Path.join(project_dir, "manifest.txt"))

    expected_manifest =
      """
      PASS compiler
      FAIL formatter
      PASS ex_unit
      SKIP credo
      SKIP doctor
      SKIP ex_doc
      SKIP gettext
      """
      |> String.split("\n")
      |> Enum.sort()

    assert manifest |> String.split("\n") |> Enum.sort() == expected_manifest

    output = System.cmd("mix", ~w[check --manifest manifest.txt], cd: project_dir) |> cmd_exit(1)

    assert output =~ "retrying automatically"
    assert output =~ "compiler success"
    assert output =~ "formatter error code 1"
    refute output =~ "ex_unit success"
    refute output =~ "credo skipped due to missing package credo"
    refute output =~ "sobelow"
    refute output =~ "dialyzer"
    refute output =~ "ex_doc skipped due to missing package ex_doc"
    refute output =~ "mix_audit"

    output =
      System.cmd("mix", ~w[check --manifest manifest.txt --retry], cd: project_dir) |> cmd_exit(1)

    refute output =~ "retrying automatically"
    assert output =~ "compiler success"
    assert output =~ "formatter error code 1"
    refute output =~ "ex_unit success"
    refute output =~ "credo skipped due to missing package credo"
    refute output =~ "sobelow"
    refute output =~ "dialyzer"
    refute output =~ "ex_doc skipped due to missing package ex_doc"
    refute output =~ "mix_audit"

    output =
      System.cmd("mix", ~w[check --manifest manifest.txt --no-retry], cd: project_dir)
      |> cmd_exit(1)

    refute output =~ "retrying automatically"
    assert output =~ "compiler success"
    assert output =~ "formatter error code 1"
    assert output =~ "ex_unit success"
    assert output =~ "credo skipped due to missing package credo"
    refute output =~ "sobelow"
    refute output =~ "dialyzer"
    assert output =~ "ex_doc skipped due to missing package ex_doc"
    refute output =~ "mix_audit"

    output =
      System.cmd("mix", ~w[check --manifest manifest.txt --retry --fix], cd: project_dir)
      |> cmd_exit(0)

    assert output =~ "compiler success"
    assert output =~ "formatter fix success"
    refute output =~ "ex_unit success"
    refute output =~ "credo skipped due to missing package credo"
    refute output =~ "sobelow"
    refute output =~ "dialyzer"
    refute output =~ "ex_doc skipped due to missing package ex_doc"
    refute output =~ "mix_audit"

    output =
      System.cmd("mix", ~w[check --manifest manifest.txt --retry], cd: project_dir) |> cmd_exit(0)

    assert output =~ "compiler success"
    refute output =~ "formatter success"
    refute output =~ "ex_unit success"
    refute output =~ "credo skipped due to missing package credo"
    refute output =~ "sobelow"
    refute output =~ "dialyzer"
    refute output =~ "ex_doc skipped due to missing package ex_doc"
    refute output =~ "mix_audit"

    failing_test_path =
      project_dir
      |> Path.join("test")
      |> Path.join("failing_test.exs")

    File.write!(failing_test_path, """
    defmodule TestProjectFailingTest do
      use ExUnit.Case

      test "sample failure" do
        assert TestProject.hello() == :universe
      end
    end
    """)

    output =
      System.cmd("mix", ~w[check --only ex_unit --only formatter], cd: project_dir) |> cmd_exit(1)

    assert output =~ "formatter success"
    assert output =~ "ex_unit error code"
    assert output =~ "Result: 2/3 passed"
    assert output =~ "Failed: 1 test"

    output = System.cmd("mix", ~w[check --retry], cd: project_dir) |> cmd_exit(1)

    refute output =~ "formatter"
    assert output =~ "ex_unit error code"
    assert output =~ "Result: 0/1 passed"
    assert output =~ "Failed: 1 test"

    File.write!(
      failing_test_path,
      File.read!(failing_test_path) |> String.replace(":universe", ":world")
    )

    output = System.cmd("mix", ~w[check --retry], cd: project_dir) |> cmd_exit(0)

    refute output =~ "formatter"
    assert output =~ "ex_unit retry success"
  end
end
