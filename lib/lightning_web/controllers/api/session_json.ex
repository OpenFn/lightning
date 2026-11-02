defmodule LightningWeb.API.SessionJSON do
  @moduledoc false

  def show(%{session: session, csrf_token: csrf_token}) do
    %{
      data: %{
        state: session.state,
        user_id: session.user.id,
        stepped_up_until: session.stepped_up_until,
        csrf_token: csrf_token,
        pending_signup: nil
      }
    }
  end
end
