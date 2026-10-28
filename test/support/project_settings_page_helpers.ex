defmodule LightningWeb.ProjectSettingsPageHelpers do
  @moduledoc """
  What the project settings page's test files share: opening the page,
  reading its props, sending its events and checking its replies.

      import LightningWeb.ProjectSettingsPageHelpers
  """
  import ExUnit.Assertions
  import LightningWeb.DesignSystemHelpers
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint LightningWeb.Endpoint
  @page "#project-settings-page"

  def refused, do: "You are not authorized to perform this action."

  def open(conn, project, path \\ "settings") do
    {:ok, view, _html} =
      live(conn, "/projects/#{project.id}/#{path}", on_error: :raise)

    view
  end

  def props(view), do: page_props(view, @page)

  def send_event(view, event, payload \\ %{}),
    do: push_page_event(view, @page, event, payload)

  def assert_refused(view) do
    assert_reply(view, %{error: error})
    assert error == refused()
  end

  # A reply with no error in it; `assert_reply(view, %{})` matches errors too.
  def assert_ok(view) do
    assert_reply(view, reply)
    refute Map.has_key?(reply, :error)
  end
end
