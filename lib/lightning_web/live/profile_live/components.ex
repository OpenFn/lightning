defmodule LightningWeb.ProfileLive.Components do
  use LightningWeb, :component

  attr :current_user, Lightning.Accounts.User, required: true

  def user_info(assigns) do
    ~H"""
    <div class="px-4 sm:px-0">
      <h2 class="text-base font-semibold leading-7 text-gray-900">
        {@current_user.first_name} {@current_user.last_name}
      </h2>
      <p class="mt-1 text-sm leading-6 text-gray-600">
        Change name, email, password, and request deletion.
      </p>
      <div class="border-b border-gray-900/10 mt-6 mb-6" />
      <p class="mt-1 text-sm leading-6 text-gray-600">
        Created: <Common.datetime datetime={@current_user.inserted_at} />
      </p>
      <p class="mt-1 text-sm leading-6 text-gray-600">
        Email: {@current_user.email}
      </p>
    </div>
    """
  end

  attr :page_title, :string, required: true
  attr :live_action, :atom, required: true
  attr :current_user, Lightning.Accounts.User, required: true

  attr :user_deletion_modal, :atom,
    default: LightningWeb.Components.UserDeletionModal

  attr :delete_user_url, :string, required: true

  def action_cards(assigns) do
    assigns =
      assign(assigns, gdpr_preferences: Lightning.Config.gdpr_preferences())

    ~H"""
    <div id={"user-#{@current_user.id}"} class="md:col-span-2">
      <.live_component
        :if={@live_action == :delete}
        module={@user_deletion_modal}
        id={@current_user.id}
        user={@current_user}
        logout={true}
        return_to={~p"/profile"}
      />
      <.live_component
        module={LightningWeb.ProfileLive.FormComponent}
        id={@current_user.id}
        title={@page_title}
        action={@live_action}
        user={@current_user}
        return_to={~p"/profile"}
      />
      <%= if assigns[:gdpr_preferences] do %>
        <.live_component
          module={@gdpr_preferences.component}
          id={@gdpr_preferences.id}
          current_user={@current_user}
        />
      <% end %>
      <.live_component
        module={LightningWeb.ProfileLive.MfaComponent}
        id={"#{@current_user.id}_mfa_section"}
        user={@current_user}
      />
      <.live_component
        module={LightningWeb.ProfileLive.GithubComponent}
        id={"#{@current_user.id}_github_section"}
        user={@current_user}
      />
      <.live_component
        module={LightningWeb.ProfileLive.ExperimentalFeaturesComponent}
        id="experimental-features"
        user={@current_user}
      />
      <.delete_user_card url={@delete_user_url} />
    </div>
    """
  end

  attr :url, :string, required: true

  defp delete_user_card(assigns) do
    ~H"""
    <div class="bg-white shadow-xs ring-1 ring-gray-900/5 sm:rounded-xl md:col-span-2 mb-4">
      <div class="px-4 py-6 sm:p-8">
        <span class="text-xl">Delete account</span>
        <span class="float-right">
          <.button_link theme="danger" navigate={@url}>
            Delete my account
          </.button_link>
        </span>
      </div>
    </div>
    """
  end
end
