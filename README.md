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

## Meta

Authored and maintained by [Paul Kim](https://thekpaul.dev).

Distributed under the [MIT License](./LICENSE).

[dotfiles]: https://github.com/thekpaul/dotfiles
