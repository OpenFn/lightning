defmodule LightningWeb.Plugs.WebhookAuth do
  @moduledoc """
  Plug to handle special processing for paths starting with '/i/'.
  """
  alias Lightning.WebhookAuthMethods
  alias Lightning.Workflows
  use LightningWeb, :controller

  def init(opts), do: opts

  def call(%{request_path: request_path} = conn, _opts) do
    case String.starts_with?(request_path, "/i/") do
      true ->
        [_, _, webhook] = String.split(request_path, "/")

        auth_methods =
          get_trigger_from_webhook(webhook)
          |> WebhookAuthMethods.get_auth_methods_for_trigger()

      _ ->
        :noop
    end

    conn
  end

  defp get_trigger_from_webhook(webhook) do
    trigger_id =
      Workflows.get_edge_by_webhook(webhook_id)
      |> Map.get(:source_trigger_id, nil)

    if trigger_id do
      Repo.get(Lightning.Jobs.Trigger, trigger_id)
    else
      nil
    end
  end
end
