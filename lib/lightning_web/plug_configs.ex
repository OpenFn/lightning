defmodule LightningWeb.PlugConfigs do
  @moduledoc """
  Dinamically initialize Plugs that don't accept dynamic configs in :prod ENV.
  """

  @spec plug_parsers() :: Keyword.t()
  def plug_parsers do
    [
      parsers: [
        :urlencoded,
        :multipart,
        {
          :json,
          length: Application.fetch_env!(:lightning, :max_dataclip_size_bytes)
        }
      ],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library()
    ]
  end
end
