defmodule LightningWeb.CredentialLive.Scope do
  use Ecto.Schema

  embedded_schema do
    embeds_many :options, LightningWeb.CredentialLive.Scope.Option
  end

  defmodule Option do
    use Ecto.Schema

    embedded_schema do
      field :selected, :boolean, default: false
      field :label, :string
    end
  end
end
