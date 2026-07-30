defmodule ExCheck.ProjectCases.FastFullTest do
  use ExCheck.ProjectCase, async: true

  test "defaults to fast mode and makes full mode explicit", %{project_dir: project_dir} do
    fast_output = System.cmd("mix", ~w[check --no-retry], cd: project_dir) |> cmd_exit(0)

    assert fast_output =~ "=> fast mode check"
    assert fast_output =~ "=> fast mode finished"
    refute fast_output =~ "unused_deps"

    full_output = System.cmd("mix", ~w[check --full], cd: project_dir) |> cmd_exit(0)

    assert full_output =~ "=> full mode check"
    assert full_output =~ "=> full mode finished"
    assert full_output =~ "unused_deps success"
    assert full_output =~ "running ex_unit in full mode"
    assert full_output =~ "ex_unit success"
  end

  test "full mode ignores automatic retry narrowing", %{project_dir: project_dir} do
    invalid_file_path = Path.join([project_dir, "lib", "invalid.ex"])
    File.write!(invalid_file_path, "IO.inspect( 1 )")

    System.cmd("mix", ~w[check --manifest manifest.txt], cd: project_dir) |> cmd_exit(1)

    full_output =
      System.cmd("mix", ~w[check --full --manifest manifest.txt], cd: project_dir) |> cmd_exit(1)

    refute full_output =~ "retrying automatically"
    assert full_output =~ "formatter error code 1"
    assert full_output =~ "running ex_unit in full mode"
    assert full_output =~ "ex_unit success"
    assert full_output =~ "unused_deps success"
  end

  test "rejects retry narrowing in full mode", %{project_dir: project_dir} do
    output =
      System.cmd("mix", ~w[check --full --retry], cd: project_dir, stderr_to_stdout: true)
      |> cmd_exit(1)

    assert output =~ "--full cannot be combined with --retry"
  end

  test "rejects the removed incremental flag", %{project_dir: project_dir} do
    output =
      System.cmd("mix", ~w[check --incremental], cd: project_dir, stderr_to_stdout: true)
      |> cmd_exit(1)

    assert output =~ "Unknown option"
    assert output =~ "--incremental"
  end

  test "git-changed tools receive staged, unstaged, and untracked files", %{
    project_dir: project_dir
  } do
    File.write!(Path.join(project_dir, ".check.exs"), """
    [
      retry: false,
      tools: [
        {:changed_echo, command: ["echo", "checked"], git_changed: true,
         git_changed_include: ["lib/"]}
      ]
    ]
    """)

    System.cmd("git", ["init", "--quiet"], cd: project_dir) |> cmd_exit(0)
    System.cmd("git", ["add", "."], cd: project_dir) |> cmd_exit(0)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=ExCheck",
        "-c",
        "user.email=excheck@example.test",
        "commit",
        "--quiet",
        "-m",
        "baseline"
      ],
      cd: project_dir
    )
    |> cmd_exit(0)

    source = Path.join(project_dir, "lib/test_project.ex")
    File.write!(source, File.read!(source) <> "\n# unstaged\n")
    File.write!(Path.join(project_dir, "lib/staged.ex"), "defmodule Staged do\nend\n")
    System.cmd("git", ["add", "lib/staged.ex"], cd: project_dir) |> cmd_exit(0)
    File.write!(Path.join(project_dir, "lib/untracked.ex"), "defmodule Untracked do\nend\n")

    output = run_check(project_dir, ~w[--only changed_echo --no-retry], 0)

    assert output =~ "checked lib/staged.ex lib/test_project.ex lib/untracked.ex"
  end

  test "git-changed tools can gate without appending filenames", %{project_dir: project_dir} do
    File.write!(Path.join(project_dir, ".check.exs"), """
    [
      retry: false,
      tools: [
        {:changed_echo, command: ["echo", "checked"], git_changed: true,
         git_changed_append: false, git_changed_include: ["assets/"],
         git_changed_extensions: [".js"]}
      ]
    ]
    """)

    System.cmd("git", ["init", "--quiet"], cd: project_dir) |> cmd_exit(0)
    System.cmd("git", ["add", "."], cd: project_dir) |> cmd_exit(0)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=ExCheck",
        "-c",
        "user.email=excheck@example.test",
        "commit",
        "--quiet",
        "-m",
        "baseline"
      ],
      cd: project_dir
    )
    |> cmd_exit(0)

    skipped = run_check(project_dir, ~w[--only changed_echo --no-retry], 0)
    assert skipped =~ "git-changed skipped"

    asset_path = Path.join(project_dir, "assets/example.js")
    File.mkdir_p!(Path.dirname(asset_path))
    File.write!(asset_path, "export default true\n")

    output = run_check(project_dir, ~w[--only changed_echo --no-retry], 0)
    assert output =~ "checked\n"
    refute output =~ "checked assets/example.js"

    System.cmd("git", ["add", "assets/example.js"], cd: project_dir) |> cmd_exit(0)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=ExCheck",
        "-c",
        "user.email=excheck@example.test",
        "commit",
        "--quiet",
        "-m",
        "add asset"
      ],
      cd: project_dir
    )
    |> cmd_exit(0)

    File.rm!(asset_path)
    deleted = run_check(project_dir, ~w[--only changed_echo --no-retry], 0)
    assert deleted =~ "checked\n"
  end

  test "content-changed tools run once per successful uncommitted generation", %{
    project_dir: project_dir
  } do
    File.write!(Path.join(project_dir, ".check.exs"), """
    [
      retry: false,
      tools: [
        {:content_echo, command: ["echo", "checked"], content_changed: true,
         content_changed_include: ["assets/"], content_changed_extensions: [".js"]}
      ]
    ]
    """)

    asset_path = Path.join(project_dir, "assets/example.js")
    File.mkdir_p!(Path.dirname(asset_path))
    File.write!(asset_path, "export default true\n")
    init_git!(project_dir)

    first = run_check(project_dir, ~w[--only content_echo --no-retry], 0)
    assert first =~ "checked assets/example.js"

    unchanged = run_check(project_dir, ~w[--only content_echo --no-retry], 0)
    refute unchanged =~ "checked assets/example.js"
    assert unchanged =~ "content-changed skipped"

    File.write!(asset_path, "export default false\n")

    changed = run_check(project_dir, ~w[--only content_echo --no-retry], 0)
    assert changed =~ "checked assets/example.js"

    repeated = run_check(project_dir, ~w[--only content_echo --no-retry], 0)
    refute repeated =~ "checked assets/example.js"
    assert repeated =~ "content-changed skipped"

    full = run_check(project_dir, ~w[--full --only content_echo], 0)
    assert full =~ "checked\n"
    refute full =~ "checked assets/example.js"
  end

  test "content-changed tools do not advance their snapshot after failure", %{
    project_dir: project_dir
  } do
    File.write!(Path.join(project_dir, ".check.exs"), """
    [
      retry: false,
      tools: [
        {:content_check,
         command: ["sh", "-c", "echo checked $1; grep -q '^good$' $1", "content-check"],
         content_changed: true, content_changed_include: ["assets/"],
         content_changed_extensions: [".txt"]}
      ]
    ]
    """)

    asset_path = Path.join(project_dir, "assets/example.txt")
    File.mkdir_p!(Path.dirname(asset_path))
    File.write!(asset_path, "good\n")
    init_git!(project_dir)

    run_check(project_dir, ~w[--only content_check --no-retry], 0)
    File.write!(asset_path, "bad\n")

    first_failure = run_check(project_dir, ~w[--only content_check --no-retry], 1)
    assert first_failure =~ "checked assets/example.txt"

    repeated_failure = run_check(project_dir, ~w[--only content_check --no-retry], 1)
    assert repeated_failure =~ "checked assets/example.txt"

    File.write!(asset_path, "good\n")
    run_check(project_dir, ~w[--only content_check --no-retry], 0)

    unchanged = run_check(project_dir, ~w[--only content_check --no-retry], 0)
    refute unchanged =~ "checked assets/example.txt"
    assert unchanged =~ "content-changed skipped"
  end

  test "records and reports a clean same-generation comparison only in debug mode", %{
    project_dir: project_dir
  } do
    init_git!(project_dir)

    fast = run_check(project_dir, ~w[--no-retry], 0)
    refute fast =~ "fast/full comparison"

    debug_full = run_check(project_dir, ~w[--full --debug], 0)
    assert debug_full =~ "fast/full comparison unavailable"

    run_check(project_dir, ~w[--no-retry --debug], 0)

    full = run_check(project_dir, ~w[--full], 0)
    refute full =~ "fast/full comparison"
    refute full =~ "fast miss"

    debug_full = run_check(project_dir, ~w[--full --debug], 0)

    assert debug_full =~ "same-generation fast/full comparison: no fast miss"
  end

  test "reports a same-generation full-only failure as a fast miss", %{project_dir: project_dir} do
    File.write!(Path.join(project_dir, ".check.exs"), """
    [
      retry: false,
      tools: [
        {:full_failure, ["sh", "-c", "echo full-only failure; exit 9"], full_only: true}
      ]
    ]
    """)

    init_git!(project_dir)

    run_check(project_dir, ~w[--no-retry --debug], 0)
    full = run_check(project_dir, ~w[--full --debug], 1)

    assert full =~ "fast miss"
    assert full =~ "same source generation passed fast mode but failed full mode"
  end

  defp run_check(project_dir, args, exit_code) do
    System.cmd("mix", ["check" | args], cd: project_dir, stderr_to_stdout: true)
    |> cmd_exit(exit_code)
  end

  defp init_git!(project_dir) do
    System.cmd("git", ["init", "--quiet"], cd: project_dir) |> cmd_exit(0)
    System.cmd("git", ["add", "."], cd: project_dir) |> cmd_exit(0)

    System.cmd(
      "git",
      [
        "-c",
        "user.name=ExCheck",
        "-c",
        "user.email=excheck@example.test",
        "commit",
        "--quiet",
        "-m",
        "baseline"
      ],
      cd: project_dir
    )
    |> cmd_exit(0)
  end
end
