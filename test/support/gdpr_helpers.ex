defmodule Lightning.GDPRHelpers do
  import Mox
  import Phoenix.Component

  defmodule MockGDPRPreferencesComponent do
    use LightningWeb, :live_component

    def render(assigns) do
      ~H"""
      <div id={@id}>Manage your data here</div>
      """
    end
  end

  defmodule MockGDPRBannerComponent do
    use LightningWeb, :live_component

    def render(assigns) do
      ~H"""
      <div id={@id}>We value your privacy</div>
      """
    end
  end

  def setup_gdpr_component(context, type, enabled) do
    config_func = :"gdpr_#{type}"

    component_module =
      Module.concat(__MODULE__, "MockGDPR#{String.capitalize(type)}Component")

    stub(Lightning.MockConfig, config_func, fn ->
      if enabled do
        %{
          component: component_module,
          id: context[:id] || "gdpr-#{type}"
        }
      else
        false
      end
    end)

    context
  end

  def setup_enabled_gdpr_preferences(context),
    do: setup_gdpr_component(context, "preferences", true)

  def setup_disabled_gdpr_preferences(context),
    do: setup_gdpr_component(context, "preferences", false)

  def setup_enabled_gdpr_banner(context),
    do: setup_gdpr_component(context, "banner", true)

  def setup_disabled_gdpr_banner(context),
    do: setup_gdpr_component(context, "banner", false)
end
