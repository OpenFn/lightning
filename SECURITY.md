# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in OpenFn Lightning, please do 
**not** open a public GitHub issue.

Instead, please report it by emailing the core team at:
**security@openfn.org**

Please include:
- A description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Any suggested fixes if you have them

We will acknowledge your report within 48 hours and aim to release a fix 
within 30 days depending on severity.

## Supported Versions

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Older versions | ❌ |

## Security Best Practices for Self-Hosted Deployments

- Always generate fresh keys using `mix lightning.gen_worker_keys` — 
  never use the example values from `.env.example`
- Set `PRIMARY_ENCRYPTION_KEY` using `mix lightning.gen_encryption_key`
- Restrict the metrics endpoint with `PROMEX_METRICS_ENDPOINT_TOKEN`
- Never expose port 4000 directly to the internet — use a reverse proxy
- Enable SSL in production via `URL_SCHEME=https`
