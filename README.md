# sway_foolscreen

Fullscreen and floating for [sway](https://swaywm.org) that keep the status bar visible and put the window back exactly where it was.

`foolscreen` toggles the focused window into one of two modes:

- **`fullscreen`**: moves the window to a dedicated workspace named `fullscreen`, without a border. It fills everything except the bar.
- **`float`**: floats the window at 98% of the workspace (`-s` to change), centered.

Toggling again puts the window back into its original slot in the tiling layout.

```
foolscreen [-c RRGGBB|AARRGGBB] [-s PERCENT] fullscreen|float
```

`-c` sets the placeholder color (default `202020`). With alpha, `00000000` is fully transparent and `80ff0000` is half-transparent red.

`-s` sets the size of the floating window in percent of the workspace (default 98). Values are clamped to 20–100.

## How it works

sway has no placeholders (i3's `append_layout` doesn't exist in sway). `foolscreen` uses a real window instead:

1. It starts `foolscreen-placeholder`, a minimal Wayland client that only paints a solid color (`foolscreen-placeholder [-c COLOR] <app_id> <title>`).
2. A `for_window` rule takes the placeholder out of the layout as soon as it maps: it goes to the `fullscreen` workspace or becomes floating. The surrounding windows are never resized.
3. `swap container with mark` exchanges the window and the placeholder. The window ends up in the target mode, and the placeholder holds the slot.
4. Toggling back swaps them again and closes the placeholder.

`foolscreen-placeholder` maps in a few milliseconds; a toggle takes about 50–65 ms. A terminal like foot as the placeholder needed about 115 ms.

## Requirements

- sway, `swaymsg`, `jq`
- for building: a C compiler, `make`, `pkg-config`, `wayland-scanner`, and the wayland-client and wayland-protocols headers

On Fedora:

```sh
sudo dnf install jq gcc make pkg-config wayland-devel wayland-protocols-devel
```

On Debian/Ubuntu (`libwayland-dev` pulls in `libwayland-bin`, which has `wayland-scanner`):

```sh
sudo apt install jq gcc make pkg-config libwayland-dev wayland-protocols
```

## Build and install

```sh
make
make install            # into ~/.local/bin
make install PREFIX=/usr/local
make uninstall
```

`foolscreen` looks for `foolscreen-placeholder` in its own directory, so it doesn't depend on sway's `PATH`.

## sway config

```
bindsym $mod+f exec ~/.local/bin/foolscreen float
bindsym $mod+Shift+f exec ~/.local/bin/foolscreen fullscreen

for_window [app_id="^foolscreen-fullscreen$"] mark --add _fs_ph, move container to workspace fullscreen
for_window [app_id="^foolscreen-float-"] floating enable
```

The bar is still covered by real fullscreen windows. For that, put waybar on the overlay layer (`"layer": "overlay"`). It then draws over the top of real fullscreen windows.

## Test

```sh
make test
```

`test.sh` runs against your running sway session. It opens dummy windows on a temporary workspace `foolscreen-test` and checks, for both modes:

- the layout is restored exactly
- the neighbouring windows receive no resize (`configure`) events
- the fallbacks below work

Afterwards it returns to your workspace. If the sway config lacks the `for_window` rules, it adds them until the next reload.

It refuses to run while a window is on the `fullscreen` workspace. Don't touch the keyboard while it runs: it checks focus before every toggle and aborts if focus moved.

## Behaviour and limits

- **One window at a time** in `fullscreen` mode (marks `_fs_win`, `_fs_ph`). `float` mode works for several windows at once (marks `_fl_ph_<con_id>`).
- **Placeholder closed:** the window goes back to the end of its original workspace (`fullscreen`) or is just tiled (`float`).
- **Window closed in `fullscreen` mode:** toggling on the `fullscreen` workspace removes the placeholder and returns to the original workspace.
- **Window closed in `float` mode:** the placeholder stays. Close it yourself.
- **Border:** going back from `fullscreen` sets `border normal`. A different previous border isn't restored.
- **Origin workspace:** stored in `$XDG_RUNTIME_DIR/foolscreen-origin`; only the `fullscreen` fallback uses it.

## License

[WTFPL](http://www.wtfpl.net/), see `LICENSE`.
