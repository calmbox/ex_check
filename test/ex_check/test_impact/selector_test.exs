defmodule ExCheck.TestImpact.SelectorTest do
  use ExUnit.Case, async: true

  alias ExCheck.TestImpact.Selector
  alias __MODULE__.{CompileDependent, DeletedLeaf, Example, FaqLive, Leaf, RuntimeDependent}

  test "selects compile/export dependents without recursive runtime fan-out" do
    modules = %{
      Leaf => {:module, :module, ["lib/leaf.ex"], <<>>, false, 0},
      CompileDependent => {:module, :module, ["lib/compile_dependent.ex"], <<>>, false, 0},
      RuntimeDependent => {:module, :module, ["lib/runtime_dependent.ex"], <<>>, false, 0}
    }

    sources = %{
      "lib/leaf.ex" => source([], [], [], [Leaf]),
      "lib/compile_dependent.ex" => source([Leaf], [], [], [CompileDependent]),
      "lib/runtime_dependent.ex" => source([], [], [CompileDependent], [RuntimeDependent])
    }

    tests = %{
      "test/compile_test.exs" => test_source([CompileDependent]),
      "test/runtime_test.exs" => test_source([RuntimeDependent])
    }

    selection =
      Selector.select_data(modules, sources, tests, Map.keys(tests), ["lib/leaf.ex"], %{})

    assert selection.mode == :selected
    assert selection.tests == ["test/compile_test.exs"]
  end

  test "adds exact and LiveView colocated tests" do
    tests = %{
      "test/example_test.exs" => test_source([]),
      "test/shop_web/live/faq_live_test.exs" => test_source([]),
      "test/shop_web/live/faq_details_test.exs" => test_source([]),
      "test/shop_web/live/unrelated_test.exs" => test_source([])
    }

    exact_modules = %{Example => {:module, :module, ["lib/example.ex"], <<>>, false, 0}}

    exact =
      Selector.select_data(exact_modules, %{}, tests, Map.keys(tests), ["lib/example.ex"], %{})

    live_modules = %{
      FaqLive => {:module, :module, ["lib/shop_web/live/faq_live.ex"], <<>>, false, 0}
    }

    live =
      Selector.select_data(
        live_modules,
        %{},
        tests,
        Map.keys(tests),
        ["lib/shop_web/live/faq_live.ex"],
        %{}
      )

    assert exact.tests == ["test/example_test.exs"]

    assert live.tests == [
             "test/shop_web/live/faq_details_test.exs",
             "test/shop_web/live/faq_live_test.exs"
           ]
  end

  test "uses the previous module mapping for a deleted source" do
    tests = %{"test/leaf_test.exs" => test_source([DeletedLeaf])}
    previous = %{"lib/deleted_leaf.ex" => MapSet.new([DeletedLeaf])}

    selection =
      Selector.select_data(%{}, %{}, tests, Map.keys(tests), ["lib/deleted_leaf.ex"], previous)

    assert selection.mode == :selected
    assert selection.tests == ["test/leaf_test.exs"]
  end

  test "runs new tests directly and falls back on broad or unmapped inputs" do
    tests = ["test/existing_test.exs", "test/new_test.exs"]

    direct = Selector.select_data(%{}, %{}, %{}, tests, ["test/new_test.exs"], %{})
    config = Selector.select_data(%{}, %{}, %{}, tests, ["config/test.exs"], %{})
    unknown = Selector.select_data(%{}, %{}, %{}, tests, ["lib/unknown.ex"], %{})

    assert direct.tests == ["test/new_test.exs"]
    assert config == %{mode: :full, reasons: ["config/test.exs"], tests: tests}

    assert unknown == %{
             mode: :full,
             reasons: ["unmapped_elixir_source:lib/unknown.ex"],
             tests: tests
           }
  end

  defp source(compile, export, runtime, modules) do
    {:source, 0, 0, <<>>, compile, export, runtime, [], [], [], [], modules}
  end

  defp test_source(references), do: {:source, references, [], []}
end
