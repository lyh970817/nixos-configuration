# Oh My Pi

`omp` is the upstream `can1357/oh-my-pi` coding agent. It is installed from
the pinned Linux x86_64 binary published in the upstream `v17.1.7` GitHub
release; the package does not run an installer or fetch anything during Home
Manager activation.

The launcher in `home/programs/pi.nix` applies the same mihomo proxy,
timezone, and locale environment as `pi` and `firstmate`. Existing `pi` and
`firstmate` commands are unchanged.

## One-time manual bootstrap

After the first rebuild, start OMP and authenticate the provider you want to
use:

```sh
omp
```

Then use `/login` inside the session and complete the provider's OAuth or
API-key flow. OMP stores local credentials in `~/.omp/agent/agent.db`; this
file is machine-local, unmanaged by Home Manager, and must not be committed.
For a headless setup, OMP also provides `omp auth-broker login <provider>`.

OMP does not reuse the credentials stored by `pi` or Codex. Provider API keys
may be supplied through the provider's documented environment variables, but
no secrets are configured in this repository.
