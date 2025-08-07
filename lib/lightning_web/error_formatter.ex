defmodule LightningWeb.ErrorFormatter do
  @moduledoc """
  Formats structured domain errors into user-friendly, localized messages.

  Transforms error tuples from domain operations into displayable strings using Gettext.

  ## Usage

      message = ErrorFormatter.format({:reauthorization_required, credential}, context)

  ## Extension

  Add new error types by defining additional `format/1` clauses and Gettext entries.
  See https://hexdocs.pm/gettext/Gettext.html for Gettext documentation.
  """
  use Gettext, backend: LightningWeb.Gettext
  use LightningWeb, :verified_routes

  def format({:reauthorization_required, credential}, %{project: project}) do
    dgettext("errors", "oauth_reauth_required", %{
      credentials_url: credentials_url(project),
      credential_name: credential.name
    })
  end

  defp credentials_url(project) do
    url(~p"/projects/#{project}/settings#credentials")
  end
end
