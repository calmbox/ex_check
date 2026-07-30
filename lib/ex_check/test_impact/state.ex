defmodule ExCheck.TestImpact.State do
  @moduledoc false

  @version 1
  @filename "ex_check.test_impact"

  def path, do: Path.join(Mix.Project.manifest_path(), @filename)

  def read do
    case path() |> File.read!() |> :erlang.binary_to_term([:safe]) do
      %{version: @version, inputs: inputs, path_modules: path_modules}
      when is_map(inputs) and is_map(path_modules) ->
        {:ok, %{inputs: inputs, path_modules: path_modules}}

      _ ->
        {:error, "incompatible impact snapshot"}
    end
  rescue
    File.Error -> {:error, "missing impact snapshot"}
    _ -> {:error, "corrupt impact snapshot"}
  end

  # sobelow_skip ["Traversal.FileModule"]
  def write!(inputs, path_modules) do
    content =
      :erlang.term_to_binary(
        %{version: @version, inputs: inputs, path_modules: path_modules},
        [:compressed]
      )

    atomic_write!(path(), content)
  end

  # sobelow_skip ["Traversal.FileModule"]
  def atomic_write!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".tmp.#{System.unique_integer([:positive, :monotonic])}"

    try do
      File.write!(temporary, content, [:exclusive])

      case File.rename(temporary, path) do
        :ok -> :ok
        {:error, reason} -> raise File.Error, reason: reason, action: "rename", path: path
      end
    after
      File.rm(temporary)
    end
  end
end
