# GameDAC Controls for Omarchy

A thin Omarchy 4 shell adapter for
[`gamedacctl`](https://github.com/AndreasDellrud/gamedacctl). It shows whether
the original GameDAC controller interface is available and applies profiles
saved by the native application. Profile-specific emoji or glyph icons are
shown when configured; older profiles retain effect-specific fallback icons.

The plugin contains no HID, USB protocol, packet construction, privilege, or
firmware logic. It calls only the stable `gamedacctl status --json` and
`gamedacctl profile apply NAME --json` interfaces. Status refreshes when the
panel opens, on explicit request, or when the atomically written profile store
changes. Closing the panel leaves no polling process behind.

## Requirements

- Omarchy 4
- `gamedacctl` and `gamedacctl-gui` available on the shell process `PATH`
- The scoped GameDAC udev rule supplied by `gamedacctl`

## Development validation

```bash
omarchy plugin validate .
```

Once this directory is published as its own Git repository, install it with:

```bash
omarchy plugin add https://github.com/AndreasDellrud/omarchy-gamedacctl.git --enable
```

Left-click the headset icon to open the panel, middle-click to refresh, or
right-click to launch the full native controller. A missing or failing
controller is displayed as an error inside the panel and never invokes a shell
or privilege prompt.
