defmodule LightningWeb.API.ConfirmationsUnsendableTest do
  # The mailer's adapter is application config, shared by every test process,
  # so swapping it for one that fails can't run beside other tests.
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  defmodule FailingAdapter do
    @moduledoc false
    use Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: {:error, :unreachable}
  end

  setup do
    config = Application.get_env(:lightning, Lightning.Mailer)

    Application.put_env(
      :lightning,
      Lightning.Mailer,
      Keyword.put(config, :adapter, FailingAdapter)
    )

    on_exit(fn -> Application.put_env(:lightning, Lightning.Mailer, config) end)
  end

  describe "resending to the signed-in person" do
    @tag :capture_log
    test "answers service_unavailable when the email can't be sent" do
      build_conn()
      |> session_conn(insert(:user, confirmed_at: nil))
      |> post(~p"/api/confirmations")
      |> assert_problem(503, :service_unavailable, [])
    end
  end
end
