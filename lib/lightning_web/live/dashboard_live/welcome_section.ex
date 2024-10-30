defmodule LightningWeb.DashboardLive.WelcomeSection do
  use LightningWeb, :live_component

  import LightningWeb.DashboardLive.Components

  alias Lightning.Accounts

  require Logger

  @arcade_resources [
    %{
      id: 1,
      title: "Getting Started with OpenFn",
      link:
        "https://demo.arcade.software/xmGSUuZ1Ovd9WeHaTLle?embed&embed_mobile=tab&embed_desktop=inline&show_copy_link=true"
    },
    %{
      id: 2,
      title: "Creating your first workflow",
      link:
        "https://demo.arcade.software/JzPHX0mUGTkPgAUoctHy?embed&embed_mobile=tab&embed_desktop=inline&show_copy_link=true"
    },
    %{
      id: 3,
      title: "How to use the Inspector",
      link:
        "https://demo.arcade.software/L3jtNbBEdMJHtY1Z1PFk?embed&embed_mobile=tab&embed_desktop=inline&show_copy_link=true"
    },
    %{
      id: 4,
      title: "Managing project history",
      link:
        "https://demo.arcade.software/JLR25gjZdm3NlasAIrZ5?embed&embed_mobile=tab&embed_desktop=inline&show_copy_link=true"
    }
  ]

  @impl true
  def update(assigns, socket) do
    welcome_collapsed =
      Accounts.get_preference(
        assigns.current_user,
        "welcome.collapsed"
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(arcade_resources: @arcade_resources)
     |> assign(selected_arcade_resource: nil)
     |> assign(welcome_collapsed: welcome_collapsed)}
  end

  @impl true
  def handle_event(
        "select-arcade-resource",
        %{"resource" => resource_id},
        socket
      ) do
    resource =
      Enum.find(socket.assigns.arcade_resources, fn resource ->
        resource.id == String.to_integer(resource_id)
      end)

    {:noreply, assign(socket, selected_arcade_resource: resource)}
  end

  def handle_event("toggle-welcome-banner", _params, socket) do
    welcome_collapsed = !socket.assigns.welcome_collapsed

    Accounts.update_user_preference(
      socket.assigns.current_user,
      "welcome.collapsed",
      welcome_collapsed
    )
    |> case do
      {:ok, _user} ->
        {:noreply, assign(socket, welcome_collapsed: welcome_collapsed)}

      {:error, reason} ->
        Logger.error("Couldn't update user preferences: #{inspect(reason)}")
        {:noreply, socket}
    end
  end

  def handle_event("modal_closed", _params, socket) do
    {:noreply, assign(socket, selected_arcade_resource: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.welcome_banner
        id={@id}
        user={@current_user}
        resources={@arcade_resources}
        target={@myself}
        collapsed={@welcome_collapsed}
        selected_resource={@selected_arcade_resource}
      />
    </div>
    """
  end
end
