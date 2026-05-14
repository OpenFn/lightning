defmodule Lightning.Adaptors.InvalidatorTest do
  use ExUnit.Case, async: true

  alias Lightning.Adaptors.Invalidator
  alias Lightning.Adaptors.Supervisor, as: AdaptorsSupervisor

  setup do
    sup = :"inv_test_#{System.unique_integer([:positive])}"

    start_supervised!(
      {AdaptorsSupervisor, name: sup, strategy: Lightning.Adaptors.StrategyMock}
    )

    cache = AdaptorsSupervisor.cache_name(sup)
    source_topic = AdaptorsSupervisor.source_topic(sup)
    inv_name = AdaptorsSupervisor.invalidator_name(sup)

    start_supervised!(
      {Invalidator, name: inv_name, source_topic: source_topic, cache: cache}
    )

    {:ok, sup: sup, cache: cache, inv_name: inv_name}
  end

  describe "start_link/1" do
    test "registers under the :name opt", %{inv_name: inv_name} do
      assert is_pid(Process.whereis(inv_name))
    end
  end

  describe "handle_info/2 - {:changed, name, source}" do
    test "evicts all four matching cache keys on broadcast", %{
      sup: sup,
      cache: cache,
      inv_name: inv_name
    } do
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)
      name = "@openfn/language-http"

      Cachex.put!(cache, {:schema, name, source}, {:ok, %{"type" => "object"}})
      Cachex.put!(cache, {:versions, name, source}, {:ok, [%{version: "1.0.0"}]})

      Cachex.put!(
        cache,
        {:icon_meta, name, source},
        {:ok, %{icon_square_ext: "svg"}}
      )

      Cachex.put!(cache, {:packages, source}, {:ok, [%{name: name}]})

      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, name, source}
      )

      :sys.get_state(inv_name)

      assert {:ok, nil} = Cachex.get(cache, {:schema, name, source})
      assert {:ok, nil} = Cachex.get(cache, {:versions, name, source})
      assert {:ok, nil} = Cachex.get(cache, {:icon_meta, name, source})
      assert {:ok, nil} = Cachex.get(cache, {:packages, source})
    end

    test "does not evict name-scoped keys for a different adaptor", %{
      sup: sup,
      cache: cache,
      inv_name: inv_name
    } do
      source = AdaptorsSupervisor.source(sup)
      source_topic = AdaptorsSupervisor.source_topic(sup)

      target = "@openfn/language-http"
      bystander = "@openfn/language-dhis2"

      Cachex.put!(
        cache,
        {:schema, bystander, source},
        {:ok, %{"type" => "object"}}
      )

      Cachex.put!(cache, {:versions, bystander, source}, {:ok, []})
      Cachex.put!(cache, {:icon_meta, bystander, source}, {:ok, %{}})

      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, target, source}
      )

      :sys.get_state(inv_name)

      assert {:ok, {:ok, _}} = Cachex.get(cache, {:schema, bystander, source})
      assert {:ok, {:ok, _}} = Cachex.get(cache, {:versions, bystander, source})
      assert {:ok, {:ok, _}} = Cachex.get(cache, {:icon_meta, bystander, source})
    end

    test "{:changed, _, :local} on an npm-mode node is harmless", %{
      sup: sup,
      cache: cache,
      inv_name: inv_name
    } do
      source_topic = AdaptorsSupervisor.source_topic(sup)
      name = "@openfn/language-http"
      npm_source = AdaptorsSupervisor.source(sup)

      Cachex.put!(
        cache,
        {:schema, name, npm_source},
        {:ok, %{"type" => "object"}}
      )

      Phoenix.PubSub.broadcast!(
        Lightning.PubSub,
        source_topic,
        {:changed, name, :local}
      )

      :sys.get_state(inv_name)

      assert is_pid(Process.whereis(inv_name)), "invalidator must still be alive"
      assert {:ok, {:ok, _}} = Cachex.get(cache, {:schema, name, npm_source})
    end
  end
end
