# Deployment

## Encryption

Lightning enforces encryption at rest for Credentials, for which an encryption
key must be provided when running in production.

The key is expected to be a randomized set of bytes, 32 long; and Base64 encoded
when setting the environment variable.

There is a mix task that can generate keys in the correct shape for use as an
environment variable:

```sh
mix lightning.gen_encryption_key
0bJ9w+hn4ebQrsCaWXuA9JY49fP9kbHmywGd5K7k+/s=
```

Copy your key (NOT THIS ONE) and set it as `PRIMARY_ENCRYPTION_KEY` in your
environment.

## Environment Variables

- `PRIMARY_ENCRYPTION_KEY`  
  Base64 encoded 32 character long string. See [Encryption](#encryption).
