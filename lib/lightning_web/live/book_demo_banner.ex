defmodule LightningWeb.BookDemoBanner do
  @moduledoc false
  use LightningWeb, :live_component
  alias Lightning.Accounts
  alias Phoenix.LiveView.JS

  @impl true
  def update(%{current_user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(changeset: form_changeset(user, %{}))
     |> assign(assigns)}
  end

  defp form_changeset(user, params) do
    data = %{
      name: "#{user.first_name} #{user.last_name}",
      email: user.email,
      message: nil
    }

    types = %{name: :string, email: :string, message: :string}

    {data, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required(Map.keys(types))
  end

  defp dismiss_banner(current_user) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    Accounts.update_user_preference(
      current_user,
      "demo_banner.dismissed_at",
      timestamp
    )
  end

  @impl true
  def handle_event("dismiss_banner", _params, socket) do
    {:ok, _} = dismiss_banner(socket.assigns.current_user)

    {:noreply, socket}
  end

  def handle_event("validate", %{"demo" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> form_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("schedule-call", %{"demo" => params}, socket) do
    changeset =
      socket.assigns.current_user
      |> form_changeset(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      workflow_url = Lightning.Config.book_demo_openfn_workflow_url()
      calendly_url = Lightning.Config.book_demo_calendly_url()

      redirect_url =
        calendly_url
        |> URI.parse()
        |> URI.append_query(URI.encode_query(params))
        |> URI.to_string()

      {:ok, %{status: 200}} = Tesla.post(workflow_url, params)
      dismiss_banner(socket.assigns.current_user)
      {:noreply, redirect(socket, external: redirect_url)}
    else
      {:noreply, assign(socket, changeset: changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="relative isolate flex items-center gap-x-6 overflow-hidden bg-gray-50 px-6 py-2.5 sm:px-3.5 sm:before:flex-1">
        <div
          class="absolute left-[max(-7rem,calc(50%-52rem))] top-1/2 -z-10 -translate-y-1/2 transform-gpu blur-2xl"
          aria-hidden="true"
        >
          <div
            class="aspect-[577/310] w-[36.0625rem] bg-gradient-to-r from-[#ff80b5] to-[#9089fc] opacity-30"
            style="clip-path: polygon(74.8% 41.9%, 97.2% 73.2%, 100% 34.9%, 92.5% 0.4%, 87.5% 0%, 75% 28.6%, 58.5% 54.6%, 50.1% 56.8%, 46.9% 44%, 48.3% 17.4%, 24.7% 53.9%, 0% 27.9%, 11.9% 74.2%, 24.9% 54.1%, 68.6% 100%, 74.8% 41.9%)"
          >
          </div>
        </div>
        <div
          class="absolute left-[max(45rem,calc(50%+8rem))] top-1/2 -z-10 -translate-y-1/2 transform-gpu blur-2xl"
          aria-hidden="true"
        >
          <div
            class="aspect-[577/310] w-[36.0625rem] bg-gradient-to-r from-[#ff80b5] to-[#9089fc] opacity-30"
            style="clip-path: polygon(74.8% 41.9%, 97.2% 73.2%, 100% 34.9%, 92.5% 0.4%, 87.5% 0%, 75% 28.6%, 58.5% 54.6%, 50.1% 56.8%, 46.9% 44%, 48.3% 17.4%, 24.7% 53.9%, 0% 27.9%, 11.9% 74.2%, 24.9% 54.1%, 68.6% 100%, 74.8% 41.9%)"
          >
          </div>
        </div>
        <div class="flex flex-wrap items-center gap-x-4 gap-y-2">
          <p class="text-sm/6 text-gray-900">
            What problem are you trying to solve with OpenFn?
          </p>
          <a
            href="#"
            phx-click={show_modal("#{@id}-modal")}
            class="flex-none rounded-full bg-primary-600 px-3.5 py-1 text-sm font-semibold text-white shadow-sm hover:bg-primary-700 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary-900"
          >
            Schedule a call <span aria-hidden="true">&rarr;</span>
          </a>
        </div>
        <div class="flex flex-1 justify-end">
          <button
            id={"dismiss-#{@id}"}
            type="button"
            class="-m-3 p-3 focus-visible:outline-offset-[-4px]"
            phx-target={@myself}
            phx-click={JS.push("dismiss_banner") |> JS.hide(to: "##{@id}")}
          >
            <span class="sr-only">Dismiss</span>
            <.icon name="hero-x-mark" class="size-5 text-gray-900" />
          </button>
        </div>
      </div>
      <.modal
        id={"#{@id}-modal"}
        show={false}
        close_on_keydown={false}
        close_on_click_away={false}
        width="w-2/5"
      >
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">Schedule a 1:1 automation session</span>
            <button
              phx-click={hide_modal("#{@id}-modal")}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <.form
          :let={f}
          as={:demo}
          id="book-demo-form"
          for={@changeset}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="schedule-call"
        >
          <div class="flex flex-col gap-2">
            <.input type="text" field={f[:name]} label="Name" required={true} />
            <.input type="text" field={f[:email]} label="Email" required={true} />
            <.input
              type="textarea"
              field={f[:message]}
              label="What problem are you trying to solve with OpenFn?
          What specific task, process, or program would you like to automate?"
              placeholder="E.g. Every time a new person is registered in my clinic system, I must initiate a mobile money payment to a caregiver. This takes time & money. I'd like to use OpenFn to automate the process."
              rows="5"
              required={true}
            />
            <div class="mt-6">
              <div class="sm:flex sm:flex-row-reverse">
                <button
                  type="submit"
                  class="ml-3 inline-flex justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:w-auto"
                  disabled={!@changeset.valid?}
                >
                  Schedule a call
                </button>
                <button
                  id="cancel-credential-type-picker"
                  type="button"
                  phx-click={hide_modal("#{@id}-modal")}
                  class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
                >
                  Cancel
                </button>
              </div>
            </div>
          </div>
        </.form>
      </.modal>
    </div>
    """
  end
end
