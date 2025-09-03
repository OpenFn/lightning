defmodule Lightning.Collaboration.RegistryTest do
  use Lightning.DataCase, async: false

  alias Lightning.Collaboration.Registry

  setup do
    # The Registry is started by the collaboration supervisor
    # which should be running in test
    :ok
  end

  describe "Registry" do
    test "registers and looks up processes" do
      # Register current process with a session key
      workflow_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      session_key = {:session, workflow_id, user_id}

      assert {:ok, pid} = Registry.register(session_key)
      assert pid == self()

      # Verify lookup finds the process
      assert [{^pid, nil}] = Registry.lookup(session_key)

      # Verify whereis returns the pid
      assert ^pid = Registry.whereis(session_key)
    end

    test "returns nil for non-existent keys" do
      non_existent_key = {:session, "nonexistent", "user"}

      assert [] = Registry.lookup(non_existent_key)
      assert nil == Registry.whereis(non_existent_key)
    end

    test "doesn't prevent duplicate registrations" do
      workflow_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      session_key = {:session, workflow_id, user_id}

      # First and second registration succeeds
      assert {:ok, _pid} = Registry.register(session_key)
      assert {:ok, _pid} = Registry.register(session_key)
    end

    test "supports different key patterns" do
      workflow_id = Ecto.UUID.generate()
      user_id = Ecto.UUID.generate()
      doc_name = "workflow:#{workflow_id}"

      # Register with session key
      session_key = {:session, workflow_id, user_id}
      assert {:ok, _} = Registry.register(session_key)

      # Can also register with different key type (though this would be different process)
      shared_doc_key = {:shared_doc, doc_name}

      # Since we can't register the same process twice, verify the key format works
      assert [] = Registry.lookup(shared_doc_key)
    end

    test "registry_name returns the correct registry name" do
      assert Registry.registry_name() == Lightning.Collaboration.Registry
    end
  end
end
