defmodule Lightning.Accounts.UserTOTP do
  @moduledoc """
  User Time based OTPs schema
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Repo

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          secret: String.t() | nil,
          code: String.t() | nil,
          user:
            Lightning.Accounts.User.t() | Ecto.Association.NotLoaded.t() | nil
        }

  schema "user_totps" do
    field :secret, :binary, redact: true
    field :code, :string, virtual: true
    field :last_totp_at, :utc_datetime_usec
    belongs_to :user, Lightning.Accounts.User

    timestamps()
  end

  def changeset(totp, attrs) do
    totp
    |> cast(attrs, [:code])
    |> put_change(:last_totp_at, Lightning.current_time())
    |> validate_required([:code, :secret])
    |> validate_format(:code, ~r/^\d{6}$/, message: "should be a 6 digit number")
    |> maybe_validate_code(totp)
  end

  defp maybe_validate_code(changeset, totp) do
    code = get_field(changeset, :code)

    if changeset.valid? and valid_totp?(totp, code) do
      changeset
    else
      add_error(changeset, :code, "invalid code")
    end
  end

  def validate_totp(totp, code, options \\ []) do
    valid_totp?(totp, code, options)
    |> tap(fn valid ->
      if valid, do: update_last_totp_at(totp)
    end)
  end

  defp update_last_totp_at(totp) do
    totp
    |> change(%{last_totp_at: Lightning.current_time()})
    |> Repo.update!()
  end

  defp valid_totp?(totp, code, options \\ []) do
    with true <- is_struct(totp, __MODULE__),
         true <- is_binary(code),
         true <- byte_size(code) == 6,
         time <- Keyword.get(options, :time, System.os_time(:second)),
         %{last_totp_at: since} <- Repo.get(User, totp.user_id) do
      NimbleTOTP.valid?(totp.secret, code, time: time, since: since)
    end
  end
end
