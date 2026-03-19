defmodule LightningWeb.ErrorJSON do
  @moduledoc false

  def render(_template, %{error: error}) do
    %{"error" => error}
  end

  def render(template, _assigns) do
    %{"error" => Phoenix.Controller.status_message_from_template(template)}
  end
end
