# iterm-config

My iTerm2 setup kept as a repository: profiles, color schemes, prompt, a summary
printed when a window opens, and a `tools` command so I do not have to remember
ports, ssh aliases and deploy commands. A new machine is set up with one script.

## Install

You need macOS, iTerm2 and Homebrew.

```sh
git clone https://github.com/TimurTurdyev/iterm-config.git ~/Dev/projects/iterm
~/Dev/projects/iterm/scripts/install.sh
```

The orchestrator runs four scripts. Each one can be run on its own and is safe to repeat:

- `install-fonts.sh`: JetBrains Mono and Monaspace (Nerd Font builds) via brew.
- `install-profiles.sh`: validates the JSON and copies profiles into DynamicProfiles. iTerm2 picks them up at once.
- `install-shell.sh`: Starship into `~/.local/bin`, a block in `~/.zshrc`, personal lists for `tools` from the templates.
- `apply-ui.sh`: Minimal theme, margins, dimming of inactive panes, default profile.
  Run it only while iTerm2 is closed, otherwise the app cache overwrites the values.
  It backs up the plist to `~/backups/iterm2` first.

## Profiles

Profiles live in `profiles/*.json`. All of them inherit `Base` and differ only in palette.
The default is `timcode.ru`: a dark scheme in the spirit of the JetBrains editor, Monaspace Neon 14
with ligatures, a blinking bar cursor instead of a block. There is also `Auto (Catppuccin)`,
which switches between Mocha and Latte with the macOS theme, and a set of everyday themes:
Tokyo Night, Dracula, Gruvbox, Nord and others.

Edit profiles in JSON, not in the settings window: a dynamic profile does not save changes made
in the UI. After an edit run `scripts/install-profiles.sh`. To change the default profile,
replace the GUID in `apply-ui.sh` and run it while iTerm2 is closed.

## Prompt

Starship, configs in `shell/`. In the `timcode.ru` profile the prompt is a single line
`user@host dir %`, green, and `%` turns red after a failed command. Other profiles get the
directory, git branch, an empty line and `❯`. `shell/iterm2.zsh` picks the config by `ITERM_PROFILE`.

## Summary on open

A new tab in `timcode.ru` starts with a short summary: load, memory, disk, battery, address and VPN,
Docker, git of the current directory, which dev services are running, which ports are listening.
Everything is local and takes about a third of a second. Repeat with `motd`.

```
timurt@MacBook-Pro  macOS 27.0  Sat 17 Oct, 12:00  up 13d 5h
load 2.1 2.1 2.2   mem 16/24 GB   disk 783G/995G (85%)   batt 91% discharging
net 192.168.3.207 en0   vpn utun4   docker 1 running   git main 3 changes
project site  vitepress, port 5180, db -, deploy make:deploy
services postgres mariadb meilisearch
ports 24 listening  443 3306 5432 7700 8001 8003 ...
```

## tools

`tools help` lists everything by group, Tab completes subcommands, projects, ssh aliases
and services. `TOOLS_DRY_RUN=1` in front of any command prints what would run and touches nothing.

The heart of it is the registry `shell/tools.projects`: one line per project, tab separated:
name, path from `~/Dev`, ssh alias, remote path, deploy kind, port, database. Deploy kinds:
`make:<target>`, `remote-make:<target>` (over ssh in the remote path), `dep:<repo>:<recipe>:<stage>`,
`ansible:<inventory>`, `cmd:<command>`, `ci`. The database is `mysql:<name>`, `pg:<name>` or `sqlite`,
the rest comes from the project's `.env`. The file is personal and not in git, the template
`tools.projects.example` sits next to it. Inside a project directory the name can be omitted.

Projects: `tools go <name>` jumps into the clone (with a trailing `.` into the wrapper above `app/`),
`tools proj list|info|scan`, `tools open` opens PhpStorm, GoLand or PyCharm depending on the stack.

Run: `tools serve` picks the command by stack (Laravel, VitePress, Go, Python) and checks the port first.
`tools env` shows `.env` without passwords. `tools svc` manages brew services and their logs.
`tools php 8.3` switches PHP in the current shell, with `--global` through `brew link`.

Databases: `tools db` opens a client from `.env`, `tools db dump` writes a dump into `~/Dev/data/db-dumps`,
`tools db restore <file>` loads it after a confirmation. The password goes through `MYSQL_PWD` or `PGPASSWORD`.

Servers: `tools ssh <alias|project>` checks the route to the address before connecting and warns
if it goes into a tunnel or to the gateway of a previous network. `tools deploy [name] [stage]`
builds the command from the registry, shows it and waits for a confirmation. `tools pull db|storage`
fetches a dump or images from the server, without `--apply` it only shows the command.

Network: `tools port <n> [kill]`, `tools dns flush`, `tools ssl <domain>`, `tools vpn`.

Tunnels. When I want to leave through my own server instead of a VPN, `tools tunnel up` opens
a SOCKS port on 127.0.0.1 over ssh (only ssh crosses the wire). `tools tunnel shell` gives a subshell
where curl, git, composer and pip use it, `tools tunnel run <cmd>` does it for one command,
`tools tunnel app chrome|firefox` starts a browser with a separate profile through it,
`tools tunnel system on|off` switches the macOS system proxy. `tools tunnel all` sends every
connection through the server with sshuttle, no per-app setup. `tools tunnel port L:host:R` and
`tools tunnel expose L [R]` are plain ssh port forwards. `tools tunnel check` compares the public IP
directly and through the tunnel, `tools tunnel down` closes things. The server alias lives in
`shell/tools.conf`, personal, template next to it.

Routes. With split tunneling a VPN sometimes pulls my own servers into the tunnel and ssh to them
hangs. The fix is a host route through the physical gateway: `tools route up`. `tools route` shows
where each address from `shell/tools.hosts` goes right now and flags routes left over from a previous
network: they look fine but do not work. `tools route down` removes them. This list is personal too,
with a template next to it.

## Checks

`scripts/check-shell.sh` runs `zsh -n` over the modules and the parsing tests for `.env` and
the registry from `shell/tests/run.zsh`. Install scripts are checked with `shellcheck -x -P scripts`.

## Adding a section to tools

`shell/tools.zsh` loads every `shell/tools.d/*.zsh`. A module declares `tools_<name>` functions
and registers help lines with `tools_help_add`. Nothing else: the dispatcher and completion find it.
