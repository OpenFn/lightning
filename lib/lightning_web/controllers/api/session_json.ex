defmodule LightningWeb.API.SessionJSON do
  @moduledoc false

  def show(%{session: session, csrf_token: csrf_token}) do
    %{
      data: %{
        state: session.state,
        user_id: session.user.id,
        csrf_token: csrf_token
      }
    }
  end
end
