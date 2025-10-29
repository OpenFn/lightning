# Lightning API Documentation

This directory contains the Lightning API documentation built with Docusaurus
and the OpenAPI plugin.

## Getting Started

### Prerequisites

- Node.js version 20.0 or above

### Installation

```bash
cd docs
npm install
```

### Generate API Documentation

Before running the site, generate the API documentation from the OpenAPI
specification:

```bash
npm run gen-api-docs
```

This will generate markdown files from the OpenAPI spec in
`static/openapi.yaml`.

### Development

Start the development server:

```bash
npm start
```

The documentation site will be available at http://localhost:3000

### Build

Build the static site for production:

```bash
npm run build
```

The static files will be generated in the `build/` directory.

### Serve Production Build

Test the production build locally:

```bash
npm run serve
```

## Project Structure

```
docs/
├── docs/               # Documentation pages
│   ├── intro.md       # Main introduction page
│   └── api/           # Generated API docs (created by gen-api-docs)
├── static/            # Static assets
│   └── openapi.yaml   # OpenAPI specification
├── src/               # Custom React components and CSS
├── docusaurus.config.ts  # Docusaurus configuration
├── sidebars.ts        # Sidebar configuration
└── package.json       # Dependencies and scripts
```

## Available Scripts

- `npm start` - Start development server
- `npm run build` - Build for production
- `npm run serve` - Serve production build
- `npm run gen-api-docs` - Generate API docs from OpenAPI spec
- `npm run clean-api-docs` - Clean generated API docs
- `npm run clear` - Clear Docusaurus cache
- `npm run typecheck` - Run TypeScript type checking

## Updating the API Documentation

1. Update the OpenAPI specification in `static/openapi.yaml`
2. Regenerate the API documentation:
   ```bash
   npm run gen-api-docs
   ```
3. Review changes and commit

## Adding New Documentation Pages

1. Create a new markdown file in the `docs/` directory
2. Add frontmatter with sidebar position and other metadata
3. The page will automatically appear in the sidebar

## Configuration

The main configuration is in `docusaurus.config.ts`. Key settings:

- **OpenAPI Plugin**: Configured to read from `static/openapi.yaml`
- **Theme**: Uses the OpenAPI docs theme for API reference pages
- **Sidebars**: Configured in `sidebars.ts` with separate sections for docs and
  API

## Contributing

When contributing documentation:

1. Follow the existing markdown formatting
2. Keep line length under 80 characters
3. Update the OpenAPI spec if API endpoints change
4. Run `npm run typecheck` before committing
5. Test the documentation locally before submitting

## Deployment

The documentation can be deployed to:

- GitHub Pages
- Netlify
- Vercel
- Any static hosting service

Build the site with `npm run build` and deploy the `build/` directory.
