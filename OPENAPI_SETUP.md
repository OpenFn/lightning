# OpenAPI Automatic Generation Setup

This document explains how to use OpenApiSpex to automatically generate OpenAPI
specifications from your Lightning API code.

## Overview

OpenApiSpex is integrated to provide:

- Automatic OpenAPI spec generation from code annotations
- Request/response validation
- Interactive API documentation
- Type-safe API contracts

## Setup Complete

The following has been configured:

1. **Dependency Added**: `open_api_spex ~> 3.22` in `mix.exs`
2. **API Spec Module**: `lib/lightning_web/api_spec.ex`
3. **Schema Definitions**: `lib/lightning_web/schemas.ex`
4. **Example Controller Specs**:
   `lib/lightning_web/controllers/api/project_controller_spec.ex`
5. **Mix Alias**: `mix api.docs` to generate and update docs

## Quick Start

### 1. Install Dependencies

```bash
mix deps.get
```

### 2. Add OpenAPI Route (Optional)

To serve the OpenAPI spec at `/api/openapi`, add to
`lib/lightning_web/router.ex`:

```elixir
scope "/api" do
  pipe_through :api

  # Existing routes...

  # Add this line:
  get "/openapi", OpenApiSpex.Plug.RenderSpec, []
end
```

### 3. Generate OpenAPI Spec

```bash
# Generate the spec file
mix openapi.spec.yaml --spec LightningWeb.ApiSpec --output docs/static/openapi.yaml

# Or use the convenience alias that also regenerates docs:
mix api.docs
```

## Annotating Controllers

### Step 1: Add OpenApiSpex to a Controller

```elixir
defmodule LightningWeb.API.ProjectController do
  use LightningWeb, :controller
  use OpenApiSpex.ControllerSpecs  # Add this line

  alias LightningWeb.Schemas

  # Specify the API tag
  tags ["Projects"]

  # ... rest of controller
end
```

### Step 2: Annotate Actions

Add `operation` macro before each controller action:

```elixir
operation :index,
  summary: "List all accessible projects",
  parameters: [
    page: [in: :query, type: :integer, description: "Page number"],
    page_size: [in: :query, type: :integer, description: "Items per page"]
  ],
  responses: [
    ok: {"Projects response", "application/json", Schemas.ProjectListResponse},
    unauthorized: {"Auth required", "application/json", Schemas.ErrorResponse}
  ]

def index(conn, params) do
  # Your existing implementation
end
```

### Step 3: Define Request/Response Schemas

Add schemas to `lib/lightning_web/schemas.ex`:

```elixir
defmodule ProjectListResponse do
  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "ProjectListResponse",
    type: :object,
    properties: %{
      data: %Schema{type: :array, items: Project},
      page_number: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      total_entries: %Schema{type: :integer}
    }
  })
end
```

## Example: Fully Annotated Controller

See `lib/lightning_web/controllers/api/project_controller_spec.ex` for a
complete example.

### Inline Annotation

```elixir
defmodule LightningWeb.API.ProjectController do
  use LightningWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias LightningWeb.Schemas

  tags ["Projects"]

  operation :index,
    summary: "List all accessible projects",
    parameters: [
      page: [in: :query, type: :integer, description: "Page number", default: 1],
      page_size: [in: :query, type: :integer, description: "Items per page", default: 10]
    ],
    responses: [
      ok: {"Projects list", "application/json", Schemas.ProjectListResponse},
      unauthorized: {"Unauthorized", "application/json", Schemas.ErrorResponse}
    ]

  def index(conn, params) do
    # Implementation
  end

  operation :show,
    summary: "Get project by ID",
    parameters: [
      id: [in: :path, type: :string, format: :uuid, description: "Project ID"]
    ],
    responses: [
      ok: {"Project details", "application/json", Schemas.ProjectResponse},
      not_found: {"Not found", "application/json", Schemas.ErrorResponse}
    ]

  def show(conn, %{"id" => id}) do
    # Implementation
  end
end
```

## Request Validation

To enable request validation, add plugs to your controller:

```elixir
plug OpenApiSpex.Plug.CastAndValidate,
  json_render_error_v2: true,
  operation_id: "ProjectController.index"

def index(conn, params) do
  # params are now cast to the types defined in the operation spec
end
```

## Response Validation (Development Only)

Add response validation in development:

```elixir
if Mix.env() == :dev do
  plug OpenApiSpex.Plug.ValidateResponse
end
```

## Migration Path

### Phase 1: Co-existence (Current)

- Manual OpenAPI spec in `docs/static/openapi.yaml` (already done)
- OpenApiSpex infrastructure in place
- Both can coexist

### Phase 2: Incremental Migration

1. Start with one controller (e.g., ProjectController)
2. Add annotations
3. Generate spec and verify
4. Compare with manual spec
5. Move to next controller

### Phase 3: Full Migration

- All controllers annotated
- Remove manual spec
- Use `mix api.docs` in CI/CD

## Workflow

### Development

```bash
# 1. Modify controller annotations
vim lib/lightning_web/controllers/api/project_controller.ex

# 2. Regenerate spec and docs
mix api.docs

# 3. Review generated spec
cat docs/static/openapi.yaml

# 4. Test documentation locally
cd docs && npm start
```

### CI/CD Integration

```yaml
# .github/workflows/docs.yml
- name: Generate API docs
  run: |
    mix deps.get
    mix api.docs

- name: Deploy docs
  run: |
    cd docs
    npm install
    npm run build
```

## Benefits

1. **Single Source of Truth**: API docs live in code
2. **Type Safety**: Request/response validation
3. **Always Up-to-Date**: Docs regenerate from code
4. **Less Maintenance**: No manual spec updates
5. **Better DX**: IDE autocomplete for schemas

## Troubleshooting

### Spec Generation Fails

```bash
# Ensure deps are installed
mix deps.get

# Clear build artifacts
mix clean

# Regenerate
mix api.docs
```

### Schema Not Found

Ensure schema modules are compiled before spec generation:

```bash
mix compile
mix api.docs
```

### Route Not Recognized

Check that routes are properly defined in `router.ex` and the controller is
using the correct path.

## Resources

- [OpenApiSpex Documentation](https://hexdocs.pm/open_api_spex)
- [OpenAPI 3.0 Specification](https://swagger.io/specification/)
- [Docusaurus OpenAPI Plugin](https://github.com/PaloAltoNetworks/docusaurus-openapi-docs)

## Next Steps

1. **Try It Out**: Annotate `ProjectController` with specs
2. **Generate**: Run `mix api.docs`
3. **Review**: Check the generated `docs/static/openapi.yaml`
4. **Test**: Start docs server with `cd docs && npm start`
5. **Iterate**: Refine annotations and repeat

## Getting Help

- Check example in `project_controller_spec.ex`
- Review `schemas.ex` for schema patterns
- See OpenApiSpex docs for advanced usage
