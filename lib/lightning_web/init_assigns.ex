defmodule LightningWeb.InitAssigns do
  @moduledoc """
  Ensures common `assigns` are applied to all LiveViews attaching this hook.
  """
  import Phoenix.Component
  alias Lightning.Accounts

  def on_mount(:default, _params, session, socket) do
    {:cont,
    socket |> assign_new(:current_user, fn ->
       Accounts.get_user_by_session_token(session["user_token"])
     end) |> assign_new(:require_confirmed_user, fn -> true end)}
  end
end
