defmodule LightningWeb.PlugConfigs do
  @moduledoc """
  Dynamically initialize Plugs that don't accept dynamic configs in :prod ENV.
  """

  @spec plug_parsers() :: Keyword.t()
  def plug_parsers do
    [
      parsers: [
        :urlencoded,
        :multipart,
        {
          :json,
          length: Lightning.Config.max_dataclip_size_bytes()
        }
      ],
      pass: ["*/*"],
      json_decoder: Phoenix.json_library()
    ]
  end
end
