defmodule LightningWeb.UserTOTPHTML do
  @moduledoc false

  use LightningWeb, :html

  embed_templates "user_totp_html/*"

  attr :authentication_type, :string, required: true

  def title(assigns) do
    ~H"""
    <h1 class="text-xl text-center font-bold leading-tight tracking-tight text-gray-900 md:text-2xl dark:text-white">
      <%= case @authentication_type do %>
        <% :backup_code -> %>
          Backup Code
        <% _other -> %>
          Authentication Code
      <% end %>
    </h1>
    """
  end

  defp invert_chosen_type(authentication_type) do
    case authentication_type do
      :backup_code ->
        :totp

      _other ->
        :backup_code
    end
  end
end
