defmodule LightningWeb.ProjectLive.DeleteConnectionModal do
  @moduledoc false
  use LightningWeb, :component
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="relative z-10 hidden"
      aria-labelledby="{@id}-title"
      role="dialog"
      aria-modal="true"
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
    >
      <div
        id={"#{@id}-bg"}
        class="bg-zinc-50/90 fixed inset-0 transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-2 sm:p-6 lg:py-8 rounded-md">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="w-2/5 shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white p-4 shadow-lg ring-1 transition"
            >
              <div>
                <span class="text-black">
                  Remove GitHub Connection
                </span>
                <hr />
                <div class="hidden sm:block" aria-hidden="true">
                  <div class="py-1"></div>
                </div>
                <div class="text-black">
                  Heads up! Removing the connection from GitHub here only severs the link between OpenFn and GitHub.
                  To fully remove the OpenFn application from GitHub, please follow the instructions in
                  <.link
                    class="text-blue-600"
                    href="https://docs.github.com/en/apps/using-github-apps/reviewing-and-revoking-authorization-of-github-apps"
                  >
                    this link.
                  </.link>
                </div>
                <div class="my-4 items-center">
                  <button
                    phx-click={
                      LightningWeb.Components.Modal.hide_modal(
                        "delete_connection_modal"
                      )
                    }
                    type="button"
                    class="inline-flex justify-center py-2 px-4 border shadow-sm text-sm font-medium rounded-md text-black  focus:outline-none focus:ring-2 focus:ring-offset-2"
                  >
                    Cancel
                  </button>
                  <button
                    phx-click={
                      JS.push("delete_repo_connection")
                      |> LightningWeb.Components.Modal.hide_modal(
                        "delete_connection_modal"
                      )
                    }
                    type="button"
                    class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-danger-500 hover:bg-danger-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-danger-500"
                  >
                    Remove Connection
                  </button>
                </div>
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
