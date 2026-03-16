defmodule ExCheck.ProjectCases.LockTest do
  use ExCheck.ProjectCase, async: true

  test "stale lease is reclaimed before running checks", %{project_dir: project_dir} do
    tmp_dir = create_tmp_directory()
    on_exit(fn -> remove_tmp_directory(tmp_dir) end)

    lock_path = Path.join(tmp_dir, "ex_check-lock-#{app_id(project_dir)}.lock.lease")

    File.mkdir_p!(lock_path)
    File.write!(Path.join(lock_path, "owner"), "stale owner")

    File.write!(
      Path.join(lock_path, "heartbeat"),
      Integer.to_string(System.system_time(:millisecond) - 15_000)
    )

    output =
      System.cmd("mix", ~w[check --only formatter], cd: project_dir, env: [{"TMPDIR", tmp_dir}])
      |> cmd_exit(0)

    assert output =~ "formatter success"
    refute output =~ "waiting for previous mix check"
    refute File.exists?(lock_path)
  end

  defp app_id(project_dir) do
    project_dir
    |> String.replace(~r/[ ~#%&*{}\\:<>?\/+|"]/, "_")
    |> String.replace(~r/^_+/, "")
  end
end
