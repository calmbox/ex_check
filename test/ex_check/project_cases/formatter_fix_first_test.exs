defmodule ExCheck.ProjectCases.FormatterFixFirstTest do
  use ExCheck.ProjectCase, async: true

  @fix_eval """
  Process.sleep(1_000)
  File.write!("formatted", "formatted")
  """

  @reader_eval """
  IO.puts("reader saw: " <> to_string(File.exists?("formatted")))
  """

  @config """
  [
    tools: [
      {:formatter, fix: ["elixir", "-e", #{inspect(@fix_eval)}]},
      {:reader, command: ["elixir", "-e", #{inspect(@reader_eval)}], order: 0}
    ]
  ]
  """

  test "fixing formatter finishes before other tools start", %{project_dir: project_dir} do
    File.write!(Path.join(project_dir, ".check.exs"), @config)

    output =
      System.cmd("mix", ~w[check --fix --only formatter --only reader], cd: project_dir)
      |> cmd_exit(0)

    assert output =~ "reader saw: true"
  end
end
