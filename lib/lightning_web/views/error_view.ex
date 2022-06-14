defmodule LightningWeb.ErrorView do
  use LightningWeb, :view

  # If you want to customize a particular status code
  # for a certain format, you may uncomment below.
  def render("404.html", assigns) do
    ~H"""
    <h1>Not Found</h1>
    """
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    if String.match?(template, ~r/.json$/) do
      %{
        "error" => Phoenix.Controller.status_message_from_template(template)
      }
    else
      Phoenix.Controller.status_message_from_template(template)
    end
  end
end
