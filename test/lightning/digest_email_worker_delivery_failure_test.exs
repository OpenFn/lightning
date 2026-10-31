defmodule Lightning.DigestEmailWorkerDeliveryFailureTest do
  # The mailer adapter is application-wide, so this cannot share a run with the
  # async tests that deliver mail.
  use Lightning.DataCase, async: false

  import Lightning.ApplicationHelpers, only: [put_temporary_env: 3]
  import Lightning.Factories

  alias Lightning.DigestEmailWorker

  defmodule RefusingAdapter do
    @moduledoc false
    @behaviour Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: {:error, :timeout}

    @impl true
    def validate_config(_config), do: :ok
  end

  test "reports a digest the mailer refused as failed rather than notified" do
    user = insert(:user)

    project =
      insert(:project, project_users: [%{user_id: user.id, digest: :daily}])

    insert(:simple_workflow, project: project)

    put_temporary_env(:lightning, Lightning.Mailer, adapter: RefusingAdapter)

    {:ok, result} =
      DigestEmailWorker.perform(%Oban.Job{
        args: %{"type" => "daily_project_digest"}
      })

    assert Enum.map(result.failed_users, & &1.user_id) == [user.id]

    # A send that never happened is not a notification, and it says nothing
    # about the recipient's standing or the project's activity.
    assert result.notified_users == []
    assert result.suppressed_users == []
    assert result.skipped_users == []
  end
end
