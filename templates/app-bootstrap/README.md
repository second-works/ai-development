# App bootstrap template

Copy these files into a new application repository before adding application code.

```text
bin/setup
bin/setup.app
bin/doctor
.env.example
```

Run `bin/setup` after clone, then run `bin/doctor`. Both scripts are non-interactive. `bin/setup` creates `.env` from `.env.example` only when it does not already exist, so local configuration is preserved on repeated runs.

## Application-specific work

Keep OS, Docker, Node, Python and other shared runtime installation in the environment repository. Put only this application's repeatable dependency installation and generated-file setup in the executable `bin/setup.app`. It must be idempotent and must not print secret values.

Configure doctor through literal `KEY=value` lines in `.env`:

- `APP_REQUIRED_COMMANDS`: space-separated executable names that this application requires.
- `APP_REQUIRED_FILES`: space-separated repository-relative paths that this application requires.
- `APP_HEALTHCHECK_URL`: optional local `http://localhost` or `http://127.0.0.1` health endpoint. A configured endpoint is required to respond successfully; an empty value is a warning, not a failure.

The template does not install platform runtimes, read secret values, contact external endpoints, or manage persistent application data. Record application-specific secrets, data locations, ports and health behavior in that application's README and child Issue.

## New-app Done condition

A new application is ready for review only after its own `bin/setup`, `bin/doctor`, `.env.example`, README instructions and app-specific verification have been reviewed. Test setup twice and test doctor for required dependencies, missing configuration and both configured and unconfigured health checks.
