<img src="preview.png" width="720" alt="OmaProton VPN, a live world map, one click to connect, built for Omarchy">

# OmaProton VPN

**Proton VPN, built for Omarchy.** All of Proton in one bar widget for
[Omarchy Quattro](https://omarchy.org): a live world map of every city, one
click to connect, sign-in and the Kill Switch in the panel, none of it in a
terminal. Click the Proton mark and you're protected.

<img src="docs/omaproton.gif" width="360" alt="Live: the map lit on the connected city, traffic moving, and the panel switching through Catppuccin Latte, Gruvbox, Hackerman and Tokyo Night">

*Live, and in your theme.*

## Why "Oma"

Because it doesn't look like a VPN app that landed on your desktop. It looks
like Omarchy, because it *is* Omarchy, all the way down:

- **It wears your theme.** Every colour, the font, the corner radius, the
  switches, even the Proton mark and the world map are drawn from Omarchy's
  theme tokens. Switch from Tokyo Night to Catppuccin Latte and the whole
  panel, coastlines, city dots, the lit city, follows on the spot. Nothing is
  a pasted-in bitmap; nothing is hard-coded.
- **It feels like the panels next to it.** The hero, the power switch, the
  rows, the hover rings, the keyboard cursor, all the same Quattro components
  your Wi-Fi, Bluetooth, and Tailscale panels are built from. Arrow keys walk
  it, `Esc` backs out, `/` finds a country. You already know how to use it.
- **It stays out of the terminal.** Install, sign in, Kill Switch, connect,
  pick a city on a map: every step is a click in the panel. The only terminals
  you'll see are Omarchy's own floating ones, the package install's password
  prompt, and Proton's sign-in prompt, and both close themselves.
- **A map, without a map service.** Every Proton city on a world outline, the
  connected one lit and pulsing, hover for load, click to go, all from files
  already on disk. No tiles, no geocoding, no requests.
- **Fast enough to live in a bar.** Tunnel state comes from NetworkManager in
  about ten milliseconds, so the icon reacts in seconds; the Python CLI is only
  asked for the detail rows.

It drives the official `protonvpn` CLI. No API keys, no tokens, and no
credentials are stored by this plugin, your password and 2FA code go straight
into the CLI's own prompt, and Proton's client owns the session from there.

<img src="docs/panel.png" width="360" alt="The OmaProton VPN panel: world map, connection details, live traffic, quick connect">

## New to Proton?

You don't need to be a Proton customer to use this. Proton VPN has a **free
plan**: no data cap, no logs, no ads, run by Proton in Switzerland under Swiss
privacy law. It gets you a handful of countries and standard speeds, which is
plenty to be private on café Wi-Fi. Plus adds every country and city on the
map, faster servers, and the P2P, Secure Core and Tor rows.

Make a free account at [proton.me/vpn](https://proton.me/vpn), then come back
and click the Proton mark. Sign-in happens in the panel.

## What you need

- Omarchy Quattro
- A Proton account, a free one works; sign up at [proton.me](https://proton.me)

That's it. The panel installs the Proton VPN CLI for you if it isn't there.

## Install

```bash
omarchy plugin add https://github.com/grichard99/omaproton-vpn --enable
```

Then click the Proton mark in your bar. The panel walks you through the rest:

1. **Install Proton VPN CLI**: one click; Omarchy opens a terminal and handles
   the install (that terminal asks for your password, since it's a system
   package).
2. **Sign in**: type your Proton username or email in the panel and press
   Enter. A terminal opens for your password and 2FA code, then closes.
3. **Turn on the Kill Switch**: the panel offers this once. Say yes.
4. **Connect**: the switch at the top, or pick a city below.

If you'd rather place the widget yourself, drop `--enable` and run:

```bash
omarchy plugin enable io.github.grichard99.omaproton-vpn right
```

### Already have the Proton VPN desktop app?

The desktop app and the CLI can't run at the same time. The panel warns you if
the app is installed. Quit it before connecting, or remove it:

```bash
omarchy pkg drop proton-vpn-gtk-app
```

### Two-factor with a security key?

The CLI supports TOTP (authenticator-app codes) only. If your account uses a
FIDO2 key, sign in once with the desktop app instead, this widget reads the
session either way.

## Update

```bash
omarchy plugin update io.github.grichard99.omaproton-vpn
```

## Remove

```bash
omarchy plugin remove io.github.grichard99.omaproton-vpn
```

That disables the widget, removes it from your bar, and deletes the plugin
folder. It leaves your Proton VPN session, settings, and any active tunnel
alone, disconnect and sign out first if you want those gone too:

```bash
protonvpn disconnect
protonvpn signout
```

The widget also keeps a small file of your recent locations at
`~/.local/state/omarchy-protonvpn/state.json`; delete it if you like.

## How to use it

### The bar icon

The Proton mark sits in your bar in the theme's foreground colour. Solid means
protected; dimmed means not.

| Action | What it does |
| --- | --- |
| Left-click | Open the panel |
| Right-click | Toggle, connect to the fastest server, or disconnect |
| Middle-click | Force a status refresh |

The panel is keyboard-driven too: arrow keys move through every section, `Enter`
activates, `→` opens a country's city list, `←` backs out, `Esc` backs out of a
city list or closes the panel. `/` jumps to the country filter. There are no
single-letter shortcuts on purpose, a stray keystroke should never change your
connection.

### The map

<img src="docs/map.png" width="360" alt="World map with every Proton city as a dot and the connected city lit">

Under the header is a world map. Every dot is a city Proton has servers in;
the bright, pulsing one is where your traffic exits right now. Hover a dot for
the city and its current load; click it to open that country's city list.

It's drawn entirely offline. The coastlines are a single bundled outline
(Natural Earth, public domain), the dots come from the Proton client's own
server cache, and the connected city is looked up in that same cache by server
name. No map tiles, no geocoding, no requests.

The map doesn't show *your* location or draw a line to the server, the way the
Proton app does. Finding your location would take a geo-IP lookup, which this
plugin promises never to make. Lighting up the exit city is the honest version.

### The power switch

The switch at the top of the panel is the same toggle as right-click. When off,
it connects to the **fastest server for your location**: Proton's own choice,
the same thing `protonvpn connect` with no arguments does. When on, it
disconnects.

### Quick connect

Each row asks Proton for the **fastest server that has that feature**. You don't
pick a country here; Proton picks the best match for you.

| Row | What you get |
| --- | --- |
| **Fastest** | Proton's best pick for your location. Same as the power switch. |
| **Random** | Any available server, chosen at random. Useful when you want to look like you're somewhere unpredictable. |
| **P2P** | The fastest server that permits file sharing. Only P2P-flagged servers allow BitTorrent-style traffic; on other servers it's blocked. |
| **Secure Core** | The fastest Secure Core server. Your traffic enters through a hardened server in Switzerland, Iceland, or Sweden and *then* exits through the country you appear from, so a compromised exit server never sees your real IP. Slower, because it's two hops. |
| **Tor** | The fastest Tor-over-VPN server. Your traffic goes VPN first, then into the Tor network, so you can reach `.onion` sites from a normal browser. Noticeably slower. |

Rows marked **PLUS** need a paid plan. On a free plan they fail with a clear
"Requires a Proton VPN Plus plan", nothing breaks.

### Two tabs: Connections and Protection

Under Quick Connect sit two tabs, in the same pill style as Omarchy's network
panel. **Connections** holds everywhere you can go, recent places, the
country and city lists, and saved profiles when they land. **Protection**
holds everything about *how* you're protected, the Kill Switch, NetShield,
Always On, and the settings still to come (split tunneling). The tab you
pick stays until you close the panel.

### Protection

<img src="docs/protection.png" width="360" alt="The Protection tab: Kill Switch and NetShield switches, account, and sign out">

Two switches saved to Proton's own settings:

- **Kill Switch**: if the VPN drops, your internet is blocked until it's back.
  Without this, a dropped tunnel silently falls back to your plain connection
  and all you'd see is the icon dimming. The CLI ships with it **off**: which is
  why the panel offers to turn it on the first time you sign in.

  The Kill Switch and split tunneling can't both be on, because Proton ignores
  split tunneling whenever the Kill Switch is on. Each row locks the other and
  says which one to turn off, so you never have to know the rule.

  Proton won't change this setting while a tunnel is up, so if you flip it
  while connected the widget drops the tunnel, makes the change, and puts you
  back on the same server. It asks first, in a dialog, because your traffic
  isn't protected until the tunnel is back and that's your call to make, not
  something to be told about afterwards. Cancel is preselected. Disconnected
  there's nothing to interrupt, so it just changes. That takes as long as a normal connect, and the row
  says "Turning on…" the whole way through. Always On is held off in the
  middle, otherwise it would reconnect into the gap and the change would fail.
  If anything goes wrong, you end up back on the VPN with the setting
  unchanged, never stranded off it.
- **NetShield**: blocks malware, ads, and trackers at the DNS level. On a free
  plan Proton only allows malware blocking; the widget steps down to that
  automatically.

- **Split tunneling**: pick apps that skip the VPN, or flip it round so only
  the apps you pick use it. See below, it has more rules attached than the
  other two.

And one saved by the widget itself, because the CLI has no setting for it:

- **Always On**: whenever Proton isn't connected, connect it. That covers
  booting, logging in, joining a café Wi-Fi, and a tunnel that drops on its own,
  they're all just moments when you aren't protected and should be. It's
  checked on the same few-second poll that drives the bar icon, so there's
  nothing extra running. **Off by default.**

  It reconnects to the top of your **Recent** list, which is the server you
  were last actually on. If that server is full or gone, the attempt fails
  once and the next one falls back to Fastest, so it can't get stuck retrying
  a server that isn't coming back. With nothing in Recent yet it just uses
  Fastest. Never a Plus-only target, so a free account isn't sent somewhere
  it can't go. A connect that fails waits 30 seconds before trying again, so
  a dead network, or a café portal you haven't signed into yet, doesn't get
  hammered.

  Two things worth knowing. It never fires while you're signed out, and it
  will never open a sign-in terminal on its own. And while it's on, the
  **Disconnect** button won't keep you disconnected, you'll be reconnected
  within a few seconds; switch Always On off if you want to stay off.

#### Split tunneling

Turn it on and two more rows appear: **Mode**, and the **Apps** list.

- **Exclude** (the default) sends the apps you pick out through your normal
  connection, everything else stays on the VPN. Good for a bank that blocks
  VPN IPs, or a device on your own network.
- **Include** is the mirror image: only the apps you pick go through the VPN
  and everything else uses your normal connection.

The Apps list is every desktop app on the machine that the widget can point at
a real program on disk. Search it, tick what you want, untick to remove.

Four things to know, all of them Proton's behaviour rather than the widget's:

- **It needs the Kill Switch off.** Proton skips split tunneling entirely while
  the Kill Switch is on, so the row says so and stays locked until you turn the
  Kill Switch off. The switch shows off while that's true, because nothing is
  being split, and it stays off when you turn the Kill Switch back off. Your
  app lists are kept either way, so turning it back on is one click. Neither
  switch ever turns itself on. Changing the Kill Switch needs you disconnected first, so
  the order is: disconnect, Kill Switch off, set up split tunneling, connect.
  It's a real trade, a tunnel with holes in it can't also promise nothing
  leaks when it drops.
- **Restart your apps after connecting.** Proton tags an app's connections as
  they're made, so anything already running when the tunnel came up keeps using
  it until you restart it. Proton's own app tells you the same thing.
- **Apps only, no IP ranges.** Proton's settings file has a field for IP ranges
  but nothing on Linux reads it yet, so the widget doesn't offer one rather
  than write a setting that does nothing.
- **IPv4 only.** Proton tags IPv4 connections and nothing else, so an app you
  excluded still uses the VPN for anything it sends over IPv6, and in Include
  mode an app you left out still uses the VPN over IPv6. If you need an
  exclusion to be absolute, `protonvpn config set ipv6 off` stops the tunnel
  carrying IPv6 at all and apps fall back to IPv4, where it works. When you
  test this, check with `curl -4`, otherwise you may be looking at a path
  split tunneling never touches.
- **Flatpaks and Snaps aren't listed.** They all launch through one shared
  runner, so picking one would pick all of them. Same for anything that
  launches through a terminal chooser or a web-app handler.

Below the switches, **Account** shows who's signed in and the plan, with a
**Sign out** row, it asks for a second click within five seconds, because
signing out also disconnects.

If the VPN does drop unexpectedly, you also get a desktop notification,
"Proton VPN disconnected, You're no longer protected." Turn notifications off
in the widget's settings if you'd rather not.

### Connections → Recent

The last three places you connected to, pinned above the country list. Most
people use the same two or three locations forever; this makes them one click.

Every successful connection lands here, including **Fastest**, **Random**,
**P2P**, **Secure Core** and **Tor**. Those don't name a destination when you
click them, but they still put you somewhere, so the server they picked is
recorded by name and city, and clicking it again takes you straight back.
That top entry is also what Always On reconnects to.

### Connections → Countries and cities

Below that is the full country list. **Clicking a country doesn't connect**,
it drills into that country's cities, so you can see where you'll land before
you commit.

<img src="docs/city-list.png" width="360" alt="Connections tab with Japan drilled open, Osaka, clicked on the map, is ringed">

Inside a country:

- **"Fastest in &lt;country&gt;"** is always the first row. It lets Proton choose
  any server in that country, which is the same as `protonvpn connect --country`.
- **Every row below is one city**: showing the best server there right now with
  its current load and any tags, **Free** for free-plan servers, plus P2P, Tor,
  or Streaming. Cities are ordered by Proton's own speed score, best first.

The widget shows one row per city rather than one per server on purpose. Large
countries have thousands of servers and the nearest city would monopolise the
whole list, you'd scroll past hundreds of near-identical entries before seeing
a second city. When you pick a city, it connects to that city's best server; if
you want a *specific* server, use the CLI: `protonvpn connect US-NY#12`.

Secure Core servers aren't listed under their exit country. They're reached
through the Secure Core quick-connect row instead, since listing them here would
suggest a single-hop connection that isn't.

The city list comes from the Proton client's own cache, which is written the
first time you connect. Before that, every country shows only the "Fastest in"
row.

### The detail rows

When connected, the panel shows the server, its location, load, and protocol,
exactly what `protonvpn status` prints.

The **Server** line updates within seconds from NetworkManager even while a
connect is still in progress. The other rows come from the CLI and can lag a
moment behind.

### Traffic

<img src="docs/traffic.png" width="360" alt="Download and upload rates with the 60-second sparkline and session totals">

While you're connected, under the details: download and upload rates, a
60-second sparkline, and the session's totals and uptime. Download is the
filled area with a solid line; upload is the dashed line. Both are drawn in
your theme's foreground, one ink, like the rest of the panel, and told
apart by shape, not colour, so they read the same on every theme and for
colour-blind eyes. Hover the sparkline to read the values at any second.

The numbers come from the kernel's own counters for the tunnel interface
(`/sys/class/net/proton0/statistics`), read once a second **only while the
panel is open**: so it's tunnel traffic specifically, and it costs nothing
when you're not looking.

### While a connect is in progress

`protonvpn connect` blocks for anywhere from a few seconds to a minute. The
widget doesn't freeze, it shows "Connecting to …" and optimistically flips the
switch on. If the connect fails, the switch drops back and the reason is shown
under the header for a few seconds.

## Settings

Configurable from Omarchy's widget settings:

| Setting | Default | What it controls |
| --- | --- | --- |
| Desktop notifications | On | "Protected" on connect; "disconnected" if the tunnel drops unexpectedly. |
| Status refresh interval | 30 s | How often `protonvpn status` runs for the detail rows while the panel is closed. Open panel: every 5 s. |
| Link watch interval | 4 s | How often `nmcli` is polled for the bar icon. |

**Protocol.** The one Proton setting the CLI doesn't expose. It lives in
`~/.config/Proton/VPN/settings.json`:

```json
{ "protocol": "wireguard" }
```

Valid values are `wireguard`, `openvpn-udp`, and `openvpn-tcp`. Reconnect after
changing it. `wireguard` is the fastest and the CLI warns about instability on
`openvpn-tcp`.

## Security and privacy

This plugin runs unsandboxed inside the Omarchy shell process, like every
Omarchy plugin. It:

- stores no credentials, tokens, or account data
- makes no network requests of its own
- never uses `sudo`, the CLI install runs through Omarchy's own installer in a
  terminal that owns the password prompt
- never downloads or executes remote code
- runs every command as an argument list, never through a shell, with one
  exception below
- reads Proton's server cache read-only (city list, coordinates, and the map's
  connected-city lookup all come from it), reads the tunnel's byte counters
  under `/sys/class/net/` once a second while the panel is open, and writes
  one file of its own
  (`~/.local/state/omarchy-protonvpn/state.json`: recent location labels,
  whether you dismissed the Kill Switch prompt, and whether Always On is on)
- writes one file that isn't its own, and only if you turn split tunneling on:
  `~/.config/Proton/VPN/settings.json`, Proton's own settings. Rules below.

**Sign-in.** Your password and 2FA code go straight to the `protonvpn` CLI's
own prompt in a terminal; this plugin never sees them. The username you type in
the panel is the one value that has to cross a shell boundary (Omarchy's
terminal launcher takes a command string). It's checked against a strict
allow-list, letters, digits, and `. _ + @ -` only, and single-quoted before
it goes anywhere; anything else is refused with a message, not escaped. The
terminal runs non-interactively, so nothing lands in your shell history.

**Settings writes.** The Kill Switch and NetShield switches run
`protonvpn config set`. The widget will only ever pass `kill-switch` ∈
`{off, standard}` and `netshield` ∈ `{off, malware-only, malware-ads-trackers}`;
no other key or value can reach the CLI from this code.

**Writing Proton's settings file.** Split tunneling is the one feature with no
CLI command behind it, so the widget edits `~/.config/Proton/VPN/settings.json`
itself. What that means in practice:

- It only ever happens when you change something under Split tunneling.
  Nothing is written on start-up, on a poll, or when you connect.
- The file is read fresh, only `features.split_tunneling` is changed, and every
  other key is handed back exactly as found. A diff before and after a change
  shows the app list and nothing else.
- If the file is missing or unreadable, nothing is written and the row says
  "Sign in and connect once first". The widget never creates it.
- App paths only ever come from the widget's own scan of installed apps, and
  anything that isn't an absolute path is dropped rather than repaired.
- Writes are atomic (written aside, then renamed into place), so an interrupted
  write can't leave you with half a settings file.
- Nothing is written while the Kill Switch is on, since Proton would ignore it,
  and nothing is written while a `protonvpn config set` is still running, so
  the two can't land on the file at once.

**What's visible to other processes.** Omarchy exposes every plugin over a
Quickshell IPC socket under `/run/user/<uid>/`, which only your own user (and
root) can reach. Through it, any process running as you can call this widget's
`connect`, `disconnect`, `status`, and `debug` methods, the same things that
process could already do by running `protonvpn` directly. Note that while
Always On is enabled, an IPC `disconnect` is undone within a few seconds, same
as the button. `status` returns the
server name; `debug` deliberately omits your account email. The email is shown
only inside the panel.

**Network activity.** The widget polls `nmcli` (local, no network) for the bar
icon, and `protonvpn status` for the detail rows. `status` asks the Proton
client for its server list, which the client refreshes from Proton's API only
when its own cache has expired, server loads every ~15 minutes, the full list
every ~3 hours, and only while connected. The widget's polling doesn't add API
traffic beyond what the client already does on its own schedule.

**Notifications** go through `notify-send` and contain only the connection
state and server name.

**On screen.** Your Proton account email is shown only under Protection →
Account, not in the panel's default view, but if you screenshot or
screen-share that tab, it's visible.

## Notes

**How state is detected.** `protonvpn status` costs about a second of Python
start-up, which is far too slow to poll for a bar icon. The tunnel also appears
as an active NetworkManager connection named `ProtonVPN <server>` on device
`proton0`, which `nmcli` reports in around ten milliseconds. The widget polls
`nmcli` for the icon and only shells out to the CLI for the detail rows. Proton's
IPv6 leak guard (`pvpn-killswitch-ipv6`, on a dummy device) stays active
independently and is deliberately not counted as a live tunnel.

**Where the city list comes from.** The CLI has no server-list command
(`protonvpn servers` just prints a URL), but the Proton client caches the full
logical server list at `~/.cache/Proton/VPN/serverlist.json` and refreshes it on
every connect. `servers.py` reads that cache read-only and collapses it to one
row per city.

## Credits

The world outline is [Natural Earth](https://www.naturalearthdata.com/) 1:110m
land data, free, public-domain map data made by volunteers, and the reason this
widget can draw a map without calling anyone. Projected once into `World.js`.
The Proton VPN mark is drawn from the [Simple Icons](https://simpleicons.org)
path (CC0) and recoloured to the active theme, so it isn't a scaled bitmap.
Proton and Proton VPN are trademarks of Proton AG. This is an unofficial
community plugin and is not affiliated with or endorsed by Proton AG.

## License

[MIT](LICENSE)
