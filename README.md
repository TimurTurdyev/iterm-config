# iterm-config

My iTerm2 setup kept as a repository: profiles, color schemes, prompt and the shell
glue for [tim](https://github.com/TimurTurdyev/tim), my terminal control panel.
A new machine is set up with one script.

## Install

You need macOS, iTerm2 and Homebrew.

```sh
git clone https://github.com/TimurTurdyev/iterm-config.git ~/Dev/projects/iterm
~/Dev/projects/iterm/scripts/install.sh
```

The orchestrator runs four scripts. Each one can be run on its own and is safe to repeat:

- `install-fonts.sh`: JetBrains Mono and Monaspace (Nerd Font builds) via brew.
- `install-profiles.sh`: validates the JSON and copies profiles into DynamicProfiles. iTerm2 picks them up at once.
- `install-shell.sh`: Starship into `~/.local/bin` and a block in `~/.zshrc`; warns if `tim` is not installed.
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

A new tab in `timcode.ru` starts with `tim motd`: project of the current directory, network and VPN,
listening ports, dev services. Everything is local and takes a few milliseconds.
`shell/iterm2.zsh` also evaluates `tim init zsh`, which gives the `tim` function (so `tim go` can
change the directory), completion and a one-line note when you enter a project folder.

## tim

Projects, ssh around the VPN, routes, tunnels, databases, local servers and the rest live in
[tim](https://github.com/TimurTurdyev/tim), a Go binary with its own config in `~/.config/tim`.
This repository only wires it into the shell. `tim --help` lists the commands by group.

## Checks

Install scripts are checked with `shellcheck -x -P scripts`, profiles with `plutil -convert xml1`.

