defmodule LightningWeb.Collections.Router do
  @moduledoc """
  Version-aware router for the Collections API.

  Uses `LightningWeb.Plugs.VersionedRouter` to dispatch to v1 or v2
  route modules based on the `x-api-version` request header.
  Mounted in the main router with `forward "/collections", ...`.
  """
  use LightningWeb.Plugs.VersionedRouter,
    version_plug: LightningWeb.Plugs.ApiVersion,
    fallback: LightningWeb.FallbackController,
    versions: %{
      v1: LightningWeb.Collections.V1Routes,
      v2: LightningWeb.Collections.V2Routes
    }
end
