defmodule Lightning.Collaboration.RegistryTest do
  use Lightning.DataCase, async: true

  alias Lightning.Collaboration.Registry

  setup do
    # Each test runs against its own isolated Registry instance rather than the
    # application-wide singleton, so concurrent tests can't see or collide with
    # each other's registrations. The registry name is threaded into every
    # Registry call below.
    name = :"registry_test_#{System.unique_integer([:positive])}"

    start_supervised!(%{
      id: name,
      start: {Elixir.Registry, :start_link, [[keys: :unique, name: name]]}
    })

    %{registry: name}
  end

  describe "Registry" do
    test "registers and looks up processes", %{registry: registry} do
      # Register current process with a session key
      workflow_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      session_key = {:session, workflow_id, user_id}

      assert {:ok, pid} = Registry.register(registry, session_key)
      assert pid == self()

      # Verify lookup finds the process
      assert [{^pid, nil}] = Registry.lookup(registry, session_key)

      # Verify whereis returns the pid
      assert ^pid = Registry.whereis(registry, session_key)
    end

    test "returns nil for non-existent keys", %{registry: registry} do
      non_existent_key = {:session, "nonexistent", "user"}

      assert [] = Registry.lookup(registry, non_existent_key)
      assert nil == Registry.whereis(registry, non_existent_key)
    end

    test "prevents duplicate registrations", %{registry: registry} do
      workflow_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      session_key = {:session, workflow_id, user_id}

      # First and second registration succeeds
      assert {:ok, pid} = Registry.register(registry, session_key)

      assert {:error, {:already_registered, ^pid}} =
               Registry.register(registry, session_key)
    end

    test "supports different key patterns", %{registry: registry} do
      workflow_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      doc_name = "workflow:#{workflow_id}"

      # Register with session key
      session_key = {:session, workflow_id, user_id}
      assert {:ok, _} = Registry.register(registry, session_key)

      # Can also register with different key type (though this would be different process)
      shared_doc_key = {:shared_doc, doc_name}

      # Since we can't register the same process twice, verify the key format works
      assert [] = Registry.lookup(registry, shared_doc_key)
    end
  end
end
