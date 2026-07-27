defmodule LightningWeb.Layouts do
  @moduledoc false
  use LightningWeb, :html

  embed_templates "layouts/*"

  slot :header_tags
  slot :body_tags
  def root(assigns)

  attr :side_menu_theme, :string, default: "primary-theme"
  attr :global_picker, :any, default: nil
  def live(assigns)

  attr :side_menu_theme, :string, default: "sudo-variant"
  attr :global_picker, :any, default: nil
  def settings(assigns)
end
