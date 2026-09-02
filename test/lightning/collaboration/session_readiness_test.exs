defmodule Lightning.Collaboration.SessionReadinessTest do
  @moduledoc """
  `Session.save_workflow/2`'s first-load wait runs off the Session's own
  mailbox, so a concurrent call into the same process is never stalled
  behind it.
  """

  # set_mox_global: the strategy call runs in a Task owned by the production
  # Scheduler.
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Lightning.CollaborationHelpers
  import Mox

  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.Registry
  alias Lightning.Collaboration.Session

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

    instance = start_collaboration_instance()
    user = insert(:user)
    workflow = insert(:workflow, name: "Original Name")
    document_name = "workflow:#{workflow.id}"

    start_supervised!(
      {DocumentSupervisor,
       workflow: workflow,
       document_name: document_name,
       registry: instance.registry,
       pg_scope: instance.pg_scope,
       owner: self(),
       auto_exit: false,
       name: Registry.via(instance.registry, {:doc_supervisor, document_name})}
    )

    session_pid =
      start_supervised!(
        {Session,
         workflow: workflow,
         user: user,
         document_name: document_name,
         registry: instance.registry,
         pg_scope: instance.pg_scope,
         name:
           Registry.via(instance.registry, {:session, document_name, user.id, 1})}
      )

    allow_collaboration_process(session_pid)

    %{
      instance: instance,
      session: session_pid,
      user: user,
      workflow: workflow,
      document_name: document_name
    }
  end

  defp adaptor_record(overrides \\ []) do
    overrides = Map.new(overrides)

    %{
      name: "@openfn/language-http",
      source: :npm,
      latest_version: "1.0.0",
      description: nil,
      homepage: nil,
      repository: nil,
      license: nil,
      deprecated: false,
      schema_data: nil,
      schema_sha256: nil,
      versions: [
        %{
          version: "1.0.0",
          integrity: "sha512-abc",
          tarball_url: "https://example.com/x-1.0.0.tgz",
          size_bytes: 1024,
          dependencies: %{},
          peer_dependencies: %{},
          published_at: nil,
          deprecated: false
        }
      ]
    }
    |> Map.merge(overrides)
  end

  test "does not stall a concurrent call into the same session while waiting, and resolves via GenServer.reply on success",
       %{session: session, user: user} do
    expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
      Process.sleep(150)

      {:ok, [%{name: "@openfn/language-http", latest_version: "1.0.0"}]}
    end)

    expect(
      Lightning.Adaptors.StrategyMock,
      :fetch_adaptor,
      fn "@openfn/language-http" -> {:ok, adaptor_record()} end
    )

    stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
      {:ok, %{}}
    end)

    save_task = Task.async(fn -> Session.save_workflow(session, user) end)

    # The Session must still answer while the save is waiting.
    Process.sleep(30)
    assert %Yex.Doc{} = Session.get_doc(session)

    assert {:ok, saved_workflow} = Task.await(save_task, 5_000)
    assert saved_workflow.id != nil
  end

  test "replies {:error, :adaptor_catalogue_unavailable} when the wait fails, without stalling a concurrent call",
       %{session: session, user: user} do
    expect(Lightning.Adaptors.StrategyMock, :list_adaptors, fn ->
      Process.sleep(100)
      {:error, :unreachable}
    end)

    stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
      {:ok, %{}}
    end)

    save_task = Task.async(fn -> Session.save_workflow(session, user) end)

    Process.sleep(20)
    assert %Yex.Doc{} = Session.get_doc(session)

    assert {:error, :adaptor_catalogue_unavailable} =
             Task.await(save_task, 5_000)
  end

  describe "readiness wait crash safety" do
    setup context do
      Mimic.copy(Lightning.Adaptors)
      Mimic.set_mimic_global(context)
      :ok
    end

    test "a raise inside the readiness wait replies :adaptor_catalogue_unavailable",
         %{session: session, user: user} do
      Mimic.stub(Lightning.Adaptors, :ensure_loaded, fn -> raise "boom" end)

      save_task = Task.async(fn -> Session.save_workflow(session, user) end)

      assert {:error, :adaptor_catalogue_unavailable} =
               Task.await(save_task, 5_000)
    end

    test "an exit inside the readiness wait replies :adaptor_catalogue_unavailable",
         %{session: session, user: user} do
      Mimic.stub(Lightning.Adaptors, :ensure_loaded, fn -> exit(:boom) end)

      save_task = Task.async(fn -> Session.save_workflow(session, user) end)

      assert {:error, :adaptor_catalogue_unavailable} =
               Task.await(save_task, 5_000)
    end
  end
end
