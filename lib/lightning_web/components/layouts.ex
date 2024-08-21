defmodule LightningWeb.Layouts do
  @moduledoc false

  use LightningWeb, :html

  embed_templates "layouts/*"

  slot :header_tags
  slot :body_tags
  def root(assigns)
end
