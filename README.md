Git Configurations
===

This repository tracks configurations for the Git version control system.

## Installation Methods

Install this repository at `$XDG_CONFIG_HOME/git`:

### Git Worktree (Recommended)

Create a new Git worktree from the submodule copy inside your
local superproject installation to the destination path:
```sh
git worktree add $XDG_CONFIG_HOME/git -b main --track <remote_name>/main
```
where `remote_name` is the name of the "remote" repository from which
your superproject installation is cloned.

### Standalone Installation from Remote

```sh
git clone https://github.com/thekpaul/dotfiles-git.git $XDG_CONFIG_HOME/git
```
No `--recursive` flag or submodule init is required — this repository has
no submodule dependencies.

### (Sym)link from Local Superproject Installation (Not recommended)

> [!CAUTION]
> Modifications made through the link are committed from
> inside the superproject installation:
> with this repository integrated as a subtree, they land in
> the superproject's history instead of this repository, and
> with a submodule they leave the superproject's recorded pin unsynchronised.
> Prefer a worktree, which always commits to this repository directly.

- Unix-based systems where `ln` is available:
  ```sh
  ln -s <SUPERPROJECT_INSTALLATION_PATH>/git $XDG_CONFIG_HOME/git
  ```
  Using the `-s` flag creates a "symbolic" ("soft") link, which is
  most likely to be the only type of link possible to create for directories
  on Unix-based systems.
  Omitting the `-s` flag creates a "hard" link, which is
  possible for **individual files**.
- Windows systems with PowerShell, using the `New-Item` cmdlet:
  ```pwsh
  New-Item -Path $env:XDG_CONFIG_HOME\git -ItemType Junction -Value <SUPERPROJECT_INSTALLATION_PATH>\git
  ```
  `ItemType` may be changed to `HardLink` for **individual files** or
  `SymbolicLink` to create "shortcut"s ("symbolic" links).

Make sure to use the _full path_ for `<SUPERPROJECT_INSTALLATION_PATH>`.

### **(Windows only)**: Additional Global Configurations for Windows Systems

(Sym)linking `windows.config` to `$env:USERPROFILE` as `.gitconfig` provides
an additional "global" Git configuration file applicable only to Windows
systems.
```pwsh
New-Item -Path $env:USERPROFILE\.gitconfig -ItemType HardLink -Value $env:XDG_CONFIG_HOME\git\windows.config
```
If your `$env:XDG_CONFIG_HOME\git\` is already a (sym)link, you can directly
(sym)link to the file located in the original superproject installation
path:
```pwsh
New-Item -Path $env:USERPROFILE\.gitconfig -ItemType HardLink -Value <SUPERPROJECT_INSTALLATION_PATH>\git\windows.config
```
`ItemType` may be changed to `SymbolicLink` to create "shortcut"s
("symbolic" links) here as well.

## Superproject Integration

Any superproject may import this repository in either of two ways —
the author's own [dotfiles][dotfiles] is one such superproject,
not a privileged one.
Both methods track the same `main` branch, and
neither changes how the configurations behave once installed.

### As a Submodule

```sh
git submodule add https://github.com/thekpaul/dotfiles-git.git git
```
The superproject pins an exact commit of this repository;
refresh the pin to the latest `main` with:
```sh
git submodule update --remote git
```

### As a Subtree

```sh
git subtree add --prefix=git https://github.com/thekpaul/dotfiles-git.git main --squash
```
The configurations are copied into the superproject's own tree;
import later updates with:
```sh
git subtree pull --prefix=git https://github.com/thekpaul/dotfiles-git.git main --squash
```

## Structure

- `config`: the "global" Git configuration, loaded on every platform
  via `$XDG_CONFIG_HOME/git/config` — identity, sane defaults
  (`rebase`/`merge` autostash, `pull.rebase`, `push.default`), commit signing,
  the custom `simple`/`expand` pretty formats, and
  the `fix-commit`/`rst-commit` aliases.
- `windows.config`: a second, Windows-only "global" configuration file,
  layered in only when (sym)linked to `%USERPROFILE%\.gitconfig`
  (see the Windows-only installation step above) — it does not apply on
  any other platform and is never read by `config` itself.
  It points `gpg.program` at `bin/gpg.cmd` (below) and
  enables `core.longpaths`, both needed only on Windows.
- [`bin/gpg.cmd`](./bin/gpg.cmd):
  the batch wrapper `windows.config` points `gpg.program` at.
  Gpg4win's 32-bit and 64-bit installers place `gpg.exe` at different paths, so
  it tries both known native GnuPG install locations in turn and fails loudly,
  with a stderr message, if neither is found — rather than pinning
  a single path that would silently break on the other installer variant.
- [`tests/`](./tests/run-checks.sh): the isolated check suite;
  see Testing below.

## Version Expectations

Development floor is Git **2.28.0**, the oldest conda-forge build
carrying `init.defaultBranch` — `config` sets `init.defaultBranch = main`,
which is silently ignored on older Git and leaves new repositories on
the historical `master` default instead of failing.
CI (see below) exercises the declared floor and latest release.

## External Tool Assumptions

None of the following are required for `config`/`windows.config` to *load*;
each is exercised only by a specific alias or setting:

- `sh` — the `fix-commit` alias shells out to `sh -c '...'` for
  command substitution; must be a POSIX-conformant shell on `$PATH`.
  Present as the system shell on Unix-based platforms;
  Git for Windows bundles one.
- `nvim` — configured as `core.editor`; `$GIT_EDITOR`, if set,
  overrides this regardless of whether `nvim` is present.
  Absent that override, a missing `nvim` makes Git error
  rather than silently falling back to `$EDITOR` or a system default.
- `gpg` — `commit.gpgsign = true` and a `user.signingkey` are set in `config`;
  a matching secret key must be available to `gpg` (or, on Windows
  with `windows.config` layered in, to the `gpg.program` path it points at) for
  commits to succeed unless overridden per-repository.

## Testing

Run the check suite locally:
```sh
bash tests/run-checks.sh
```
This exercises both files parsing as valid Git config,
the `simple`/`expand` pretty formats rendering correctly
(including both identity lines in `expand`),
the `rst-commit` and `fix-commit` aliases end-to-end —
the latter in both a normal repository and a linked worktree,
covering the worktree-specific bug it was written to fix — and
`windows.config`'s option values, against a throwaway `HOME`/`XDG_CONFIG_HOME`
tree with this repository symlinked in as the isolated global Git config.
No real user configuration or repository state is touched.

## CI

GitHub Actions (`.github/workflows/ci.yml`) runs the check suite on
push and pull request against `main`, across a Pixi-provisioned Git 2.28.0
(floor) and latest matrix on Ubuntu, plus
container legs proving the same Pixi-provisioned latest Git under
the el8 and el7 userlands this configuration actually targets —
both legs install Git through Pixi rather than the container's own package,
since el7 ships an unusable git 1.8.3 and el8's system git likewise
predates the declared floor.

## Meta

Authored and maintained by [Paul Kim](https://thekpaul.dev).

Distributed under the [MIT License](./LICENSE).

[dotfiles]: https://github.com/thekpaul/dotfiles
