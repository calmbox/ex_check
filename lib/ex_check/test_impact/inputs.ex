defmodule ExCheck.TestImpact.Inputs do
  @moduledoc false

  @patterns [
    "lib/**/*.{ex,exs}",
    "test/**/*.{ex,exs}",
    "config/**/*.exs",
    "priv/repo/migrations/**/*.{ex,exs}"
  ]
  @root_files ["mix.exs", "mix.lock", ".check.exs"]

  def capture(project_root, external_paths \\ []) do
    files =
      project_root
      |> input_paths(external_paths)
      |> Map.new(fn path -> {path, hash_file(project_root, path)} end)

    identity = identity(project_root)
    digest = digest({identity, Enum.sort(files)})

    %{files: files, identity: identity, digest: digest}
  end

  def changed_paths(nil, current), do: Map.keys(current.files) |> Enum.sort()

  def changed_paths(previous, current) do
    previous.files
    |> Map.keys()
    |> Kernel.++(Map.keys(current.files))
    |> Enum.uniq()
    |> Enum.filter(&(Map.get(previous.files, &1) != Map.get(current.files, &1)))
    |> Enum.sort()
  end

  defp input_paths(project_root, external_paths) do
    discovered =
      Enum.flat_map(@patterns, fn pattern ->
        project_root
        |> Path.join(pattern)
        |> Path.wildcard(match_dot: true)
        |> Enum.map(&Path.relative_to(&1, project_root))
      end)

    root_files = Enum.filter(@root_files, &File.regular?(Path.join(project_root, &1)))
    external = Enum.filter(external_paths, &input_exists?(project_root, &1))

    (discovered ++ root_files ++ external)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp hash_file(project_root, path) do
    project_root |> absolute_path(path) |> File.read!() |> digest()
  end

  defp input_exists?(project_root, path), do: File.regular?(absolute_path(project_root, path))

  defp absolute_path(_project_root, "/" <> _ = path), do: path
  defp absolute_path(project_root, path), do: Path.join(project_root, path)

  defp identity(project_root) do
    %{
      app: Mix.Project.config()[:app],
      elixir: System.version(),
      mix: Application.spec(:mix, :vsn) |> to_string(),
      otp: System.otp_release(),
      project_root: Path.expand(project_root)
    }
  end

  defp digest(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
