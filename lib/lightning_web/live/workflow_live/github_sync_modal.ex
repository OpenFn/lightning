defmodule LightningWeb.WorkflowLive.GithubSyncModal do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.VersionControl
  alias Phoenix.LiveView.JS

  @impl true
  def update(%{project_repo_connection: repo_connection} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_async(:verify_connection, fn ->
       verify_connection(repo_connection)
     end)}
  end

  defp verify_connection(repo_connection) do
    case VersionControl.verify_github_connection(repo_connection) do
      :ok -> {:ok, %{verify_connection: :ok}}
      error -> error
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id={@id <> "-form"} phx-submit="save-and-sync">
      <.modal
        id={@id}
        show={true}
        close_on_keydown={false}
        close_on_click_away={false}
        width="min-w-1/3"
      >
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              Save and sync changes to GitHub
            </span>

            <button
              phx-click="toggle_github_sync_modal"
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <div id="verify-github-connection-banner" class="mb-2">
          <.async_result assign={@verify_connection}>
            <:loading>
              <div class="rounded-md bg-blue-50 p-4">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <.icon
                      name="hero-arrow-path"
                      class="animate-spin h-5 w-5 text-blue-400"
                    />
                  </div>
                  <div class="ml-3">
                    <p class="text-sm text-blue-700">
                      Verifying connection...
                    </p>
                  </div>
                </div>
              </div>
            </:loading>
            <:failed :let={_failure}>
              <div class="bg-yellow-50 p-4">
                <div class="flex">
                  <div class="flex-shrink-0">
                    <.icon
                      name="hero-exclamation-triangle"
                      class="h-5 w-5 text-yellow-400"
                    />
                  </div>
                  <div class="ml-3">
                    <h3 class="text-sm font-medium text-yellow-800">
                      Your GitHub project is not properly connected with Lightning.
                    </h3>
                    <div class="mt-2 text-sm text-yellow-700">
                      <p>Check the project settings page for more info</p>
                    </div>
                  </div>
                </div>
              </div>
            </:failed>
            <div class="rounded-md bg-green-50 p-4">
              <div class="flex">
                <div class="flex-shrink-0">
                  <.icon name="hero-check-circle" class="h-5 w-5 text-green-400" />
                </div>
                <div class="ml-3">
                  <p class="text-sm font-medium text-green-800">
                    Your repository is properly configured.
                  </p>
                </div>
                <div class="ml-auto pl-3">
                  <div class="-mx-1.5 -my-1.5">
                    <button
                      phx-click={JS.hide(to: "#verify-github-connection-banner")}
                      type="button"
                      class="inline-flex rounded-md bg-green-50 p-1.5 text-green-500 hover:bg-green-100 focus:outline-none focus:ring-2 focus:ring-green-600 focus:ring-offset-2 focus:ring-offset-green-50"
                    >
                      <span class="sr-only">Dismiss</span>
                      <.icon name="hero-x-mark" class="h-5 w-5" />
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </.async_result>
        </div>
        <div class="flex flex-col gap-2">
          <span>
            Repository:
            <.link
              href={"https://www.github.com/" <> @project_repo_connection.repo}
              target="_blank"
              class="link"
            >
              {@project_repo_connection.repo}
            </.link>
          </span>

          <span>
            Branch:
            <span class="text-xs font-mono bg-gray-200 rounded-md p-1">
              {@project_repo_connection.branch}
            </span>
          </span>
        </div>
        <div class="mt-2 text-sm">
          Not the right repository or branch?
          <.link
            class="link"
            navigate={
              ~p"/projects/#{@project_repo_connection.project_id}/settings#vcs"
            }
          >
            Modify connection
          </.link>
        </div>
        <div class="mt-6">
          <.input
            type="textarea"
            rows="2"
            label="Commit message"
            class="w-full resize-none"
            name="github_sync[commit_message]"
            value={"#{@current_user.email} initiated a sync from Lightning"}
          />
        </div>
        <:footer class="mt-4 mx-6">
          <div class="sm:flex sm:flex-row-reverse gap-2">
            <.button
              id={"submit-btn-#{@id}"}
              type="submit"
              theme="primary"
              disabled={!@verify_connection.ok?}
            >
              Save and sync
            </.button>
            <.button
              type="button"
              phx-click="toggle_github_sync_modal"
              theme="secondary"
            >
              Cancel
            </.button>
          </div>
        </:footer>
      </.modal>
    </form>
    """
  end
end
