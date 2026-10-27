defmodule LightningWeb.SandboxPageHelpers do
  @moduledoc """
  What the sandboxes page's test files share: the Mimic copies, `props/1`
  and `row/2`, and helpers that drive the `preview-merge` and
  `merge-sandbox` events.

      use LightningWeb.SandboxPageHelpers
  """
  import ExUnit.Assertions
  import LightningWeb.DesignSystemHelpers
  import Phoenix.LiveViewTest

  @page "#sandboxes-index-page"

  @mocked [
    Lightning.Projects,
    Lightning.Projects.Sandboxes,
    Lightning.Projects.MergeProjects,
    Lightning.Projects.Provisioner
  ]

  defmacro __using__(_opts) do
    quote do
      import LightningWeb.SandboxPageHelpers

      @page unquote(@page)

      setup_all do
        LightningWeb.SandboxPageHelpers.copy_and_stub_mocked()
      end
    end
  end

  @doc false
  def copy_and_stub_mocked do
    for mod <- @mocked do
      Mimic.copy(mod)
      Mimic.stub_with(mod, mod)
    end

    :ok
  end

  def props(view), do: page_props(view, @page)

  def row(view, project) do
    %{"root" => root, "sandboxes" => sandboxes} = props(view)
    Enum.find([root | sandboxes], &(&1["id"] == project.id))
  end

  def preview(view, sandbox, target_id \\ nil) do
    push_page_event(view, @page, "preview-merge", %{
      "id" => sandbox.id,
      "targetId" => target_id
    })

    assert_reply(view, %{} = reply)
    reply
  end

  def merge(view, sandbox, target_id, extra \\ %{}) do
    payload =
      Map.merge(
        %{
          "id" => sandbox.id,
          "targetId" => target_id,
          "workflowIds" => [],
          "deletedWorkflowIds" => [],
          "credentialIds" => [],
          "skippedCollectionNames" => []
        },
        extra
      )

    push_page_event(view, @page, "merge-sandbox", payload)
  end

  def allow_mocks(view) do
    for mod <- @mocked, do: Mimic.allow(mod, self(), view.pid)
    :ok
  end
end
