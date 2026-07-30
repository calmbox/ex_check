defmodule ExCheck.ContentSnapshot do
  @moduledoc false

  def capture do
    case System.cmd(
           "git",
           ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        files =
          output
          |> String.split(<<0>>, trim: true)
          |> Enum.sort()
          |> Map.new(&{&1, hash_file(&1)})

        {:ok, %{files: files, digest: digest(Enum.sort(files))}}

      {_output, _status} ->
        :unavailable
    end
  end

  def filter(%{files: files}, extensions, include_prefixes) do
    Map.filter(files, fn {path, _hash} ->
      matches_extension?(path, extensions) and matches_include_prefix?(path, include_prefixes)
    end)
  end

  def changed_paths(nil, current), do: current |> Map.keys() |> Enum.sort()

  def changed_paths(previous, current) do
    previous
    |> Map.keys()
    |> Kernel.++(Map.keys(current))
    |> Enum.uniq()
    |> Enum.filter(&(Map.get(previous, &1) != Map.get(current, &1)))
    |> Enum.sort()
  end

  def generation({:ok, snapshot}), do: {:ok, snapshot.digest}
  def generation(:unavailable), do: :unavailable

  defp matches_extension?(_path, nil), do: true

  defp matches_extension?(path, extensions) do
    Enum.any?(extensions, &String.ends_with?(path, &1))
  end

  defp matches_include_prefix?(_path, nil), do: true

  defp matches_include_prefix?(path, prefixes) do
    Enum.any?(prefixes, &String.starts_with?(path, &1))
  end

  defp digest(term) do
    term
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp hash_file(path) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} -> {:symlink, File.read_link!(path)}
      {:ok, %{type: :directory}} -> :gitlink
      {:ok, _stat} -> hash_regular_file(path)
      {:error, :enoent} -> :deleted
      {:error, reason} -> {:error, reason}
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp hash_regular_file(path) do
    case File.read(path) do
      {:ok, contents} -> :crypto.hash(:sha256, contents)
      {:error, reason} -> {:error, reason}
    end
  end
end
