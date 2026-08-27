import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Proton VPN state for the bar widget.
//
// Two polls with different costs drive this:
//
//   * nmcli (~10ms) runs on a short interval and owns the bar icon. The CLI
//     names its tunnel "ProtonVPN <server>" on device proton0, so this alone
//     answers "are we up, and where" without paying for the Python CLI.
//   * `protonvpn status` (~1s of Python start-up) runs only when the panel is
//     open, on demand, and after an action, it supplies the detail rows.
//
// `protonvpn connect` blocks for 30-60s, so every action is optimistic:
// _desired pins the UI to the requested state until reality agrees.
//
// Every subprocess is an argv list. The one place a value crosses a shell
// boundary is sign-in, where the username is whitelisted and single-quoted
// before it reaches the terminal launcher.
Item {
  id: root

  property var settings: ({})
  property bool panelOpen: false

  property bool installed: false
  property bool installing: false
  // The GTK app and the CLI share one backend and can't run at the same time;
  // a user who installed the app from Proton's site hits an opaque failure.
  property bool gtkAppInstalled: false

  property bool signedIn: false
  // `protonvpn info` costs ~1s, so signedIn is false-but-unknown until the
  // first probe lands. Without this the widget briefly claims "Signed out"
  // over a tunnel that is plainly up.
  property bool accountProbed: false
  property string account: ""
  property string plan: ""

  // nmcli-derived, fast
  property bool linkActive: false
  property string linkServer: ""

  // `protonvpn status`-derived, slow
  property bool statusConnected: false
  property bool statusConnecting: false
  property string statusText: "Checking…"
  property string serverName: ""
  property string location: ""
  property var fields: []

  property var countries: []
  property bool countriesLoaded: false

  // Server drill-down for one country, read from the client's own cache.
  property var servers: []
  property string serversCountry: ""
  property string serversCountryName: ""
  property bool serversLoading: false

  // Every Proton city with coordinates, for the mini-map. From the client's
  // cache too, so it exists as soon as the user has connected once.
  property var cities: []
  property bool citiesLoaded: false
  // {code, city, lat, lon} for the server we're on, or null.
  property var currentPlace: null
  property string _locatePending: ""

  // Tunnel throughput, from the kernel's own counters for the tunnel
  // interface (/sys/class/net/<dev>/statistics). Sampled once a second, only
  // while the panel is open and a tunnel is up, zero cost otherwise.
  property string linkDevice: ""
  property var rxHistory: []
  property var txHistory: []
  property real rxRate: 0
  property real txRate: 0
  property real sessionRx: 0
  property real sessionTx: 0
  property int uptimeSec: 0
  property real _lastRx: -1
  property real _lastTx: -1
  property real _lastSampleMs: 0
  property real _linkUpMs: 0
  readonly property int trafficSamples: 60

  // `protonvpn config list`, keyed by setting name.
  property var config: ({})
  property bool configLoaded: false
  readonly property bool killSwitchOn: String(config["kill-switch"] || "") === "standard"
  readonly property bool netShieldOn: configLoaded && String(config["netshield"] || "off") !== "off"
  // The only values setConfig() will ever pass to the CLI.
  readonly property var configValues: ({
    "kill-switch": ["off", "standard"],
    "netshield": ["off", "malware-only", "malware-ads-trackers"]
  })

  // Persisted across restarts: last few places connected to, and whether the
  // kill-switch nudge was dismissed. Location labels only, nothing secret.
  property var recents: []
  property bool nudgeDismissed: false
  property bool stateLoaded: false

  // ── Always On ───────────────────────────────────────────────────────────
  // One invariant, not a set of triggers: if the switch is on and the tunnel
  // isn't up, bring it up. Signing in, joining a network and a dropped tunnel
  // are all just moments when that stops being true, so the nmcli poll that
  // already runs for the bar icon is the whole mechanism. No second watcher,
  // no second process, nothing to keep in sync.
  //
  // The CLI has no always-on mode of its own, and NetworkManager can't own it
  // either: the CLI re-creates its WireGuard profile on every connect, so an
  // NM autoconnect flag would only fight it.
  property bool autoConnect: false
  // Set when an automatic connect fails, so the next attempt falls back to
  // Fastest instead of retrying a server that is full or gone, forever.
  property bool _autoPinFailed: false
  // Don't retry a failed connect on the very next poll: `protonvpn connect`
  // against a dead network fails slowly and there is no point hammering it.
  readonly property int autoRetryMs: 30000
  property real _autoNextMs: 0
  // True while the in-flight connect was started by the reconciler rather
  // than a click, so only its failures arm the retry delay.
  property bool _autoAttempt: false

  readonly property bool autoReady: installed && signedIn && accountProbed && stateLoaded && autoConnect
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy-protonvpn"
  readonly property string statePath: stateDir + "/state.json"

  readonly property string scriptPath: Qt.resolvedUrl("servers.py").toString().replace(/^file:\/\//, "")

  property string actionStatus: ""
  property string lastError: ""
  property string pendingLabel: ""

  // -1 = follow reality; 0/1 = a requested state still catching up.
  property int _desired: -1
  // Set when we asked for the tunnel to go down, so the drop isn't reported
  // as a failure.
  property bool _expectDown: false
  // What the in-flight connect was asked for, recorded to recents on success.
  property var _target: null
  // When the last action finished, and when the in-flight link poll started.
  // A poll that began before the action ended carries pre-action data, so it
  // must not be used to decide whether the action took effect.
  property real _actionEndedMs: 0
  property real _watchStartedMs: 0
  property string _configKey: ""
  property string _configValue: ""

  readonly property bool connected: _desired === -1 ? (linkActive || statusConnected) : (_desired === 1)
  readonly property bool busy: actionProcess.running || connectProcess.running

  // Every `protonvpn` call is a fresh Python process that loads, and may
  // rewrite, Proton's shared 24MB server cache. The CLI takes no lock on it:
  // two processes refreshing at once can race and leave every server in that
  // file marked down, at which point the CLI refuses to pick a server at all
  // ("No servers found matching criteria") until the list is refetched, which
  // it will not do while its own copy looks fresh.
  //
  // So the read-only probes take turns, and stand aside while an action the
  // person asked for is running. Actions are already serialized by `busy`.
  // This also cuts a connect from ~9-15 CLI processes down to one.
  // Deliberately a plain flag, not a binding over the Process objects. A
  // binding does not re-evaluate between two statements of the same function,
  // so refresh()'s `refreshStatus(); refreshAccount();` would both read "not
  // busy" and start together: exactly the pair that raced and corrupted the
  // cache. This is set the instant a probe launches and cleared when it exits.
  property bool _probeRunning: false
  readonly property bool cliBusy: _probeRunning || busy
  // One flag per probe that stepped aside, so each is retried rather than
  // lost. Deliberately not a single shared flag: the two frequent probes
  // (status, info) always have work to do, so a shared flag lets them take
  // the slot forever and starve the country and config loads.
  property bool _wantStatus: false
  property bool _wantAccount: false
  property bool _wantCountries: false
  property bool _wantConfig: false
  readonly property bool _probesPending: _wantStatus || _wantAccount || _wantCountries || _wantConfig
  readonly property bool refreshing: statusProcess.running
  // Which config key is mid-change, "" when nothing is, and the value it's
  // heading for. A click costs two CLI runs, `config set` then the `config
  // list` re-read that confirms it, about 1.4s of CLI startup between them,
  // and the switch can't move until the second lands. Rather than throw the
  // knob early and hope, the row keeps showing the value the CLI last
  // reported and says what it's doing, the same way displayStatus says
  // "Connecting…". Cleared by the re-read, so it covers both runs.
  property string configPending: ""
  property string configPendingValue: ""

  // "" unless that row is the one mid-change.
  function configPendingLabel(key) {
    if (configPending !== key) return ""
    return configPendingValue === "off" ? "Turning off…" : "Turning on…"
  }

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property int watchIntervalSec: intSetting("watchIntervalSec", 4, 2, 60)
  readonly property bool notificationsOn: String(setting("notifications", "on")) !== "off"

  // The server line from nmcli is live even mid-`connect`; prefer it, and fall
  // back to the status parse when the link is down.
  readonly property string displayServer: linkActive && linkServer !== "" ? linkServer : serverName
  // Observed state outranks account state: a live tunnel is a fact, while
  // signedIn is unknown until the first probe returns.
  readonly property string displayStatus: {
    if (!installed) return "Not installed"
    if (busy && pendingLabel !== "") return pendingLabel
    if (connected) return "Protected"
    if (statusConnecting) return "Connecting…"
    if (!accountProbed) return "Checking…"
    if (!signedIn) return "Signed out"
    return "Not protected"
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (!installed) {
      probeInstalled()
      return
    }
    watchLink()
    // Account first: `signedIn` gates the map, the tabs and every setting, so
    // probing it before the detail rows is what stops the panel looking empty
    // for the first few seconds after a shell restart.
    refreshAccount()
    refreshStatus()
  }

  function probeInstalled() {
    if (!whichProcess.running) {
      whichProcess.command = ["which", "protonvpn"]
      whichProcess.running = true
    }
    if (!pacmanProcess.running) {
      pacmanProcess.command = ["pacman", "-Q", "proton-vpn-gtk-app"]
      pacmanProcess.running = true
    }
  }

  // Omarchy's own installer flow: a floating terminal owns the sudo prompt,
  // so the shell process never touches privileges.
  function installCli() {
    if (installed || installing) return
    installing = true
    lastError = ""
    Quickshell.execDetached(["omarchy-install-app", "Proton VPN CLI", "proton-vpn-cli"])
    installWatch.restart()
  }

  function watchLink() {
    if (watchProcess.running) return
    _watchStartedMs = Date.now()
    watchProcess.command = ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE,STATE", "connection", "show", "--active"]
    watchProcess.running = true
  }

  function refreshStatus() {
    if (!installed) return
    if (cliBusy) { _wantStatus = true; return }
    _probeRunning = true
    statusProcess.command = ["protonvpn", "status"]
    statusProcess.running = true
  }

  function refreshAccount() {
    if (!installed) return
    if (cliBusy) { _wantAccount = true; return }
    _probeRunning = true
    accountProcess.command = ["protonvpn", "info"]
    accountProcess.running = true
  }

  function loadCountries(force) {
    if (!installed || !signedIn) return
    if (countriesLoaded && force !== true) return
    if (cliBusy) { _wantCountries = true; return }
    _probeRunning = true
    countriesProcess.command = ["protonvpn", "countries", "list"]
    countriesProcess.running = true
  }

  function loadConfig() {
    // Nothing left to wait for, and no re-read coming to clear it.
    if (!installed || !signedIn) { configPending = ""; configPendingValue = ""; return }
    if (cliBusy) { _wantConfig = true; return }
    _probeRunning = true
    configProcess.command = ["protonvpn", "config", "list"]
    configProcess.running = true
  }

  // Both key and value must be in configValues; anything else is dropped.
  //
  // Refuses while a change is still settling, so a second click (or an Enter
  // from the keyboard cursor, which doesn't go through the row's `enabled`)
  // can't send a contradicting `config set` at a value the panel hasn't been
  // told about yet.
  function setConfig(key, value) {
    if (configPending !== "" || setConfigProcess.running) return
    applyConfig(key, value)
  }

  // The set itself, without the in-flight guard, so the NetShield step-down
  // below can hand off from one failed attempt straight into the next.
  function applyConfig(key, value) {
    var allowed = configValues[key]
    if (!allowed || allowed.indexOf(value) === -1) return
    if (!installed || !signedIn) return
    _configKey = key
    _configValue = value
    configPending = key
    configPendingValue = value
    lastError = ""
    setConfigProcess.command = ["protonvpn", "config", "set", key, value]
    setConfigProcess.running = true
  }

  function toggleKillSwitch() { setConfig("kill-switch", killSwitchOn ? "off" : "standard") }
  // Full protection first; the CLI refuses ads/trackers on a free plan and
  // the retry below steps down to malware-only.
  function toggleNetShield() { setConfig("netshield", netShieldOn ? "off" : "malware-ads-trackers") }

  function dismissNudge() {
    nudgeDismissed = true
    saveState()
  }

  function toggle() {
    if (!installed || busy) return
    // A live tunnel is proof of a session, so never send an already-signed-in
    // user to a sign-in prompt just because the account probe is stale or
    // briefly failed. Only offer sign-in once we've probed AND there's no link.
    if (!signedIn && !connected) {
      if (accountProbed) signIn("")
      else refreshAccount()
      return
    }
    if (connected) disconnect()
    else connectTo([], "Connecting to fastest…", null)
  }

  // target: {key, title, subtitle, args} recorded to recents on success, or
  // null for quick actions that are already one click away.
  function connectTo(args, label, target, auto) {
    if (!installed || !signedIn || busy) return
    _autoAttempt = auto === true
    _desired = 1
    _expectDown = false
    _target = target
    pendingLabel = label || "Connecting…"
    actionStatus = pendingLabel
    lastError = ""
    connectProcess.command = ["protonvpn", "connect"].concat(args || [])
    connectProcess.running = true
  }

  function connectFastest() { connectTo([], "Connecting to fastest…", null) }
  function connectRandom() { connectTo(["--random"], "Connecting to a random server…", null) }
  function connectP2P() { connectTo(["--p2p"], "Connecting to fastest P2P…", null) }
  function connectSecureCore() { connectTo(["--securecore"], "Connecting via Secure Core…", null) }
  function connectTor() { connectTo(["--tor"], "Connecting via Tor…", null) }

  function connectCountry(code, name) {
    var c = String(code || "").trim().toUpperCase()
    if (c === "") return
    var title = name || c
    connectTo(["--country", c], "Connecting to " + title + "…",
              { key: "country:" + c, title: title, subtitle: "Fastest server", args: ["--country", c] })
  }

  // `protonvpn connect <NAME>` takes precedence over every filter in the CLI's
  // own selection, so a named server connects exactly as asked. City and
  // country are only for the label people see.
  function connectServer(name, city, countryName) {
    var n = String(name || "").trim()
    if (n === "") return
    var title = city || n
    var subtitle = [countryName, n].filter(function(s) { return s }).join(" · ")
    connectTo([n], "Connecting to " + title + "…",
              { key: "server:" + n, title: title, subtitle: subtitle, args: [n] })
  }

  function connectRecent(index) {
    var r = recents[index]
    if (!r || !Array.isArray(r.args)) return
    connectTo(r.args, "Connecting to " + r.title + "…", r)
  }

  function loadServers(code, name) {
    var c = String(code || "").trim().toUpperCase()
    if (!installed || c === "" || serversProcess.running) return
    serversCountry = c
    serversCountryName = name || c
    servers = []
    serversLoading = true
    serversProcess.command = ["python3", scriptPath, c, "80"]
    serversProcess.running = true
  }

  function loadCities(force) {
    if (!installed || citiesProcess.running) return
    if (citiesLoaded && force !== true) return
    citiesProcess.command = ["python3", scriptPath, "--cities"]
    citiesProcess.running = true
  }

  // Which city the connected server is in. Runs whenever the server name
  // changes; a lookup arriving mid-run is queued, not dropped.
  function locateServer(name) {
    var n = String(name || "").trim()
    if (n === "") { currentPlace = null; _locatePending = ""; return }
    if (currentPlace && currentPlace.name === n) return
    if (locateProcess.running) { _locatePending = n; return }
    locateProcess.command = ["python3", scriptPath, "--locate", n]
    locateProcess.running = true
  }

  onDisplayServerChanged: locateServer(displayServer)

  function countryName(code) {
    var c = String(code || "").toUpperCase()
    for (var i = 0; i < countries.length; i++) if (countries[i].code === c) return countries[i].name
    return c
  }

  function clearServers() {
    servers = []
    serversCountry = ""
    serversCountryName = ""
    serversLoading = false
  }

  function disconnect() {
    if (!installed || busy) return
    _desired = 0
    _expectDown = true
    trafficReset()
    pendingLabel = "Disconnecting…"
    actionStatus = ""
    lastError = ""
    actionProcess.command = ["protonvpn", "disconnect"]
    actionProcess.running = true
  }

  // Sign-in is interactive (password, then a TOTP token), so it has to happen
  // in a real terminal, the CLI only accepts them from a tty. The username
  // can be typed in the panel; with none given the terminal asks for it.
  function signIn(username) {
    var u = String(username || "").trim()
    var cmd
    if (u === "") {
      cmd = "read -rp 'Proton username: ' u && protonvpn signin \"$u\""
    } else if (Model.validUsername(u)) {
      cmd = "protonvpn signin " + Model.shellQuote(u)
    } else {
      lastError = "Usernames can only contain letters, numbers and . _ + @ -"
      return false
    }
    lastError = ""
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", cmd])
    signInWatch.restart()
    return true
  }

  function signOut() {
    if (!installed || busy) return
    _desired = 0
    _expectDown = true
    trafficReset()
    pendingLabel = "Signing out…"
    actionProcess.command = ["protonvpn", "signout"]
    actionProcess.running = true
  }

  function trafficReset() {
    rxHistory = []; txHistory = []
    rxRate = 0; txRate = 0
    sessionRx = 0; sessionTx = 0
    uptimeSec = 0
    _lastRx = -1; _lastTx = -1; _lastSampleMs = 0
    _linkUpMs = Date.now()
  }

  // sysfs files report a size of 0, so FileView reads them as empty; `cat`
  // reads until EOF and costs about a millisecond once a second.
  function trafficSample() {
    if (trafficProcess.running || linkDevice === "") return
    var base = "/sys/class/net/" + linkDevice + "/statistics/"
    trafficProcess.command = ["cat", base + "rx_bytes", base + "tx_bytes"]
    trafficProcess.running = true
  }

  function trafficApply(text) {
    var parts = String(text || "").trim().split(/\s+/)
    var rx = parseFloat(parts[0]), tx = parseFloat(parts[1])
    if (!isFinite(rx) || !isFinite(tx)) return
    var now = Date.now()
    if (_lastRx >= 0 && _lastSampleMs > 0) {
      var dt = Math.max(0.25, (now - _lastSampleMs) / 1000)
      var drx = Math.max(0, rx - _lastRx), dtx = Math.max(0, tx - _lastTx)
      rxRate = drx / dt; txRate = dtx / dt
      sessionRx += drx; sessionTx += dtx
      var h = rxHistory.slice(); h.push(rxRate); if (h.length > trafficSamples) h.shift(); rxHistory = h
      var g = txHistory.slice(); g.push(txRate); if (g.length > trafficSamples) g.shift(); txHistory = g
    }
    _lastRx = rx; _lastTx = tx; _lastSampleMs = now
    uptimeSec = _linkUpMs > 0 ? Math.floor((now - _linkUpMs) / 1000) : 0
  }

  function notify(summary, body, urgency) {
    if (!notificationsOn) return
    Quickshell.execDetached(["notify-send", "-a", "Proton VPN", "-i", "network-vpn",
                             "-u", urgency || "normal", summary, body || ""])
  }

  function applyStatus(raw) {
    var parsed = Model.parseStatus(raw)
    statusConnected = parsed.connected
    statusConnecting = parsed.connecting
    statusText = parsed.statusText
    serverName = parsed.serverName
    location = parsed.location
    fields = parsed.fields
    reconcile()
  }

  // Drop the optimistic override as soon as the world agrees with it, and
  // also once the action that set it has finished, whatever the outcome.
  //
  // That second condition is not belt-and-braces. The override says "ignore
  // reality, this is where we're heading", and it used to be released only on
  // agreement. Always On can bring the tunnel straight back up as a
  // disconnect completes, so reality settles on the opposite of what was
  // asked, the two never agree, and the override latches for the rest of the
  // session: the panel reads "Not protected" over a live tunnel and the power
  // button starts connecting instead of disconnecting.
  //
  // Both callers run this against freshly polled state (nmcli in the link
  // watcher, `protonvpn status` in applyStatus), so releasing on !busy hands
  // the UI back to an observation, never to a stale one.
  // Drop the optimistic override as soon as the world agrees with it.
  //
  // It deliberately does NOT release while reality disagrees: during a connect
  // the link poll can still be reporting the old state, and releasing on that
  // flashes "Not protected" over a connect that is succeeding.
  function reconcile() {
    if (_desired === -1) return
    var real = linkActive || statusConnected
    if (real === (_desired === 1)) {
      _desired = -1
      pendingLabel = ""
      return
    }
    // Safety valve only, never part of a normal connect or disconnect. If the
    // world settles on the opposite of what was asked and stays there, the
    // override would otherwise hold the panel at a lie for the rest of the
    // session (a disconnect that something else immediately undoes leaves
    // "Not protected" over a live tunnel, and the power button then tries to
    // connect). Fifteen seconds is far longer than the few seconds a real
    // connect needs to settle, so this can never cause a flash.
    if (!busy && _actionEndedMs > 0 && Date.now() - _actionEndedMs > 15000) {
      _desired = -1
      pendingLabel = ""
    }
  }


  function applyState(text) {
    try {
      var s = JSON.parse(String(text || "{}"))
      recents = Array.isArray(s.recents) ? s.recents.slice(0, 3) : []
      nudgeDismissed = s.killSwitchNudgeDismissed === true
      autoConnect = s.autoConnect === true
    } catch (e) {
      recents = []
      nudgeDismissed = false
      autoConnect = false
    }
    stateLoaded = true
  }

  function saveState() {
    stateFile.setText(JSON.stringify({
      recents: recents,
      killSwitchNudgeDismissed: nudgeDismissed,
      autoConnect: autoConnect
    }))
  }

  // ── Always On ───────────────────────────────────────────────────────────

  function toggleAutoConnect() {
    autoConnect = !autoConnect
    _autoNextMs = 0
    saveState()
    autoReconcile()
  }

  // Run on every link poll, and checked against the world as it is right now.
  //
  // Back to the top of Recent, which is the server we were last actually on,
  // however we got there. If that one fails it is skipped next time round, so
  // a server that is full or gone can't stall this forever.
  function autoReconcile() {
    if (!autoReady) return
    if (connected || linkActive || busy) return
    if (_autoNextMs > 0 && Date.now() < _autoNextMs) return
    var t = recents.length > 0 && Array.isArray(recents[0].args) ? recents[0] : null
    if (t && !_autoPinFailed) connectTo(t.args, "Reconnecting to " + t.title + "…", t, true)
    else connectTo([], "Reconnecting to fastest…", null, true)
  }

  function recordRecent(target) {
    if (!target || !target.key) return
    var next = [target]
    for (var i = 0; i < recents.length && next.length < 3; i++) {
      if (recents[i] && recents[i].key !== target.key) next.push(recents[i])
    }
    recents = next
    saveState()
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", stateDir])
    refresh()
  }

  onPanelOpenChanged: if (panelOpen) {
    refresh()
    loadCountries(false)
    loadConfig()
  }

  Process {
    id: trafficProcess
    running: false
    command: []
    stdout: StdioCollector { id: trafficStdout; waitForEnd: true }
    onExited: function(exitCode) { if (exitCode === 0) root.trafficApply(String(trafficStdout.text || "")) }
  }

  Timer {
    id: trafficTimer
    interval: 1000
    repeat: true
    running: root.panelOpen && root.linkActive && root.linkDevice !== ""
    triggeredOnStart: true
    onTriggered: root.trafficSample()
  }

  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: root.applyState(text())
    onLoadFailed: root.applyState("{}")
  }

  Timer {
    id: watchTimer
    interval: root.watchIntervalSec * 1000
    repeat: true
    running: root.installed
    triggeredOnStart: true
    onTriggered: root.watchLink()
  }

  Timer {
    id: statusTimer
    // Cheap enough to keep current while the panel is open; throttled back to
    // the configured interval once it closes.
    interval: (root.panelOpen ? 5 : root.refreshIntervalSec) * 1000
    repeat: true
    // Not while a connect or disconnect is running: `protonvpn connect`
    // blocks for 30-60s, and a 5s poll across that is where most of the
    // concurrent CLI processes used to come from. delayedRefresh pulls fresh
    // state 1.2s after the action finishes, so nothing is lost by waiting.
    running: root.installed && root.signedIn && !root.busy
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: delayedRefresh
    interval: 1200
    repeat: false
    onTriggered: {
      root.watchLink()
      root.refreshStatus()
    }
  }

  // Start exactly one deferred probe, the moment a slot frees up, so the queue
  // drains at the CLI's own pace rather than waiting on a timer tick.
  // Account first: `signedIn` gates the map, the tabs and every setting.
  function drainProbes() {
    if (cliBusy) return
    if (_wantAccount) { _wantAccount = false; refreshAccount(); return }
    if (_wantConfig) { _wantConfig = false; loadConfig(); return }
    if (_wantCountries) { _wantCountries = false; loadCountries(false); return }
    if (_wantStatus) { _wantStatus = false; refreshStatus(); return }
  }

  // Safety net only: drainProbes() normally runs from each probe's exit.
  Timer {
    id: probeRetry
    interval: 600
    repeat: true
    running: root._probesPending && root.installed
    onTriggered: root.drainProbes()
  }

  Timer {
    id: accountRetry
    interval: 5000
    repeat: false
    onTriggered: root.refreshAccount()
  }

  Timer {
    id: actionStatusTimer
    interval: 6000
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  // Sign-in happens out of process in a terminal; poll for a while so the
  // panel flips to the signed-in view on its own.
  Timer {
    id: signInWatch
    interval: 3000
    repeat: true
    triggeredOnStart: false
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.refreshAccount()
      if (root.signedIn || ticks > 40) stop()
    }
  }

  // Same idea for the package install: up to five minutes for pacman.
  Timer {
    id: installWatch
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks += 1
      root.probeInstalled()
      if (root.installed || ticks > 100) {
        stop()
        root.installing = false
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      var was = root.installed
      root.installed = exitCode === 0
      if (root.installed) {
        if (!was) {
          root.installing = false
          root.lastError = ""
          root.statusText = "Checking…"
        }
        root.refresh()
        root.loadCities(false)
      } else if (!root.installing) {
        root.statusText = "Proton VPN CLI not installed"
      }
    }
  }

  Process {
    id: pacmanProcess
    running: false
    command: []
    onExited: function(exitCode) { root.gtkAppInstalled = exitCode === 0 }
  }

  Process {
    id: watchProcess
    running: false
    command: []
    stdout: StdioCollector { id: watchStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var link = Model.parseActiveVpn(String(watchStdout.text || ""))
      var was = root.linkActive
      root.linkActive = link.active
      root.linkServer = link.server
      root.linkDevice = link.device
      if (link.active && !was) root.trafficReset()
      if (!link.active && was) root.trafficReset()
      // A tunnel we didn't ask to close is the one thing a person must hear
      // about: the icon dimming is not a signal most people read.
      //
      // A connect in flight is not that. Two things take the tunnel down
      // mid-connect and neither is news: switching servers tears the old one
      // down first, and every `protonvpn connect` briefly double-activates,
      // because the CLI adds the NM profile (which NetworkManager then
      // auto-activates on its own, autoconnect defaults to yes) and then
      // explicitly activates it, so NM preempts its own activation. Without
      // this guard that lands as "You're no longer protected" in the middle
      // of a connect the person just asked for.
      if (was && !link.active) {
        if (!root._expectDown && !actionProcess.running && !connectProcess.running)
          root.notify("Proton VPN disconnected", "You're no longer protected.", "critical")
        root._expectDown = false
      }
      root.reconcile()
      root.autoReconcile()
      // The tunnel came up or went away behind our back (CLI in a terminal,
      // a drop, a reconnect), pull the detail rows back in sync.
      if (was !== link.active) root.refreshStatus()
      // A tunnel we didn't think we were signed in for means the account
      // state is wrong, not the link. Re-probe rather than trusting it.
      if (link.active && !root.signedIn) root.refreshAccount()
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      Qt.callLater(root.drainProbes)
      if (exitCode === 0) {
        root.applyStatus(String(statusStdout.text || ""))
        root.lastError = ""
      } else {
        root.lastError = Model.elide(String(statusStderr.text || "") || "protonvpn status failed")
      }
    }
  }

  Process {
    id: accountProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      Qt.callLater(root.drainProbes)
      // A one-off failure must not latch "signed out" forever, retry instead
      // of leaving a signed-in user staring at a sign-in prompt.
      if (exitCode !== 0) { accountRetry.restart(); return }
      var info = Model.parseAccount(String(accountStdout.text || ""))
      var was = root.signedIn
      root.accountProbed = true
      root.signedIn = info.signedIn
      root.account = info.account
      root.plan = info.plan
      if (info.signedIn && !was) {
        root.loadCountries(true)
        root.loadConfig()
      }
      if (!info.signedIn) {
        root.countries = []
        root.countriesLoaded = false
        root.config = {}
        root.configLoaded = false
      }
    }
  }

  Process {
    id: configProcess
    running: false
    command: []
    stdout: StdioCollector { id: configStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      root.configPending = ""
      root.configPendingValue = ""
      Qt.callLater(root.drainProbes)
      if (exitCode !== 0) return
      root.config = Model.parseConfig(String(configStdout.text || ""))
      root.configLoaded = true
    }
  }

  Process {
    id: setConfigProcess
    running: false
    command: []
    stdout: StdioCollector { id: setConfigStdout; waitForEnd: true }
    stderr: StdioCollector { id: setConfigStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var err = String(setConfigStderr.text || "") || String(setConfigStdout.text || "")
      var key = root._configKey
      var value = root._configValue
      root._configKey = ""
      root._configValue = ""
      if (exitCode !== 0) {
        if (key === "netshield" && value === "malware-ads-trackers" && Model.isPlanError(err)) {
          root.applyConfig("netshield", "malware-only")
          return
        }
        root.lastError = Model.isPlanError(err) ? "Requires a Proton VPN Plus plan" : Model.elide(err || "Setting failed")
      }
      root.loadConfig()
    }
  }

  Process {
    id: serversProcess
    running: false
    command: []
    stdout: StdioCollector { id: serversStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.serversLoading = false
      if (exitCode !== 0) { root.servers = []; return }
      try {
        root.servers = JSON.parse(String(serversStdout.text || "[]"))
      } catch (e) {
        root.servers = []
      }
    }
  }

  Process {
    id: citiesProcess
    running: false
    command: []
    stdout: StdioCollector { id: citiesStdout; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var list = JSON.parse(String(citiesStdout.text || "[]"))
        root.cities = Array.isArray(list) ? list : []
        root.citiesLoaded = root.cities.length > 0
      } catch (e) {
        root.cities = []
      }
    }
  }

  Process {
    id: locateProcess
    running: false
    command: []
    stdout: StdioCollector { id: locateStdout; waitForEnd: true }
    onExited: function(exitCode) {
      try {
        var place = exitCode === 0 ? JSON.parse(String(locateStdout.text || "{}")) : {}
        root.currentPlace = place && place.lat !== undefined && place.lat !== null ? place : null
      } catch (e) {
        root.currentPlace = null
      }
      if (root._locatePending !== "") {
        var next = root._locatePending
        root._locatePending = ""
        root.locateServer(next)
      }
    }
  }

  Process {
    id: countriesProcess
    running: false
    command: []
    stdout: StdioCollector { id: countriesStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root._probeRunning = false
      Qt.callLater(root.drainProbes)
      if (exitCode !== 0) return
      var list = Model.parseCountries(String(countriesStdout.text || ""))
      root.countries = list
      root.countriesLoaded = list.length > 0
    }
  }

  Process {
    id: connectProcess
    running: false
    command: []
    stdout: StdioCollector { id: connectStdout; waitForEnd: true }
    stderr: StdioCollector { id: connectStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._actionEndedMs = Date.now()
      var out = String(connectStdout.text || "")
      var err = String(connectStderr.text || "")
      var target = root._target
      var wasAuto = root._autoAttempt
      root._target = null
      root._autoAttempt = false
      root.pendingLabel = ""
      root._autoNextMs = wasAuto && exitCode !== 0 ? Date.now() + root.autoRetryMs : 0
      if (exitCode === 0) root._autoPinFailed = false
      else if (wasAuto) root._autoPinFailed = true
      if (exitCode !== 0) {
        root._desired = -1
        var text = err || out || "Connect failed"
        root.lastError = Model.isPlanError(text) ? "Requires a Proton VPN Plus plan" : Model.elide(text)
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        // The confirmation line, which is not always the first one: an expired
        // server list puts "Server list is outdated, updating..." ahead of it,
        // and that is not what the panel or the notification should report.
        var line = Model.elide(Model.connectedLine(out) || out.split("\n")[0] || "", 90)
        root.actionStatus = line
        actionStatusTimer.restart()
        // Fastest, Random, P2P, Secure Core and Tor arrive here with no target
        // because you didn't name a destination, but you still ended up
        // somewhere. Recover it from the CLI's own confirmation line so Recent
        // is a record of where you've been, not only of what you clicked.
        if (!target) {
          var landed = Model.parseConnected(out)
          if (landed) target = {
            key: "server:" + landed.name,
            title: landed.city !== "" ? landed.city : landed.name,
            subtitle: [landed.country, landed.name].filter(function(v) { return v !== "" }).join(" · "),
            args: [landed.name]
          }
        }
        root.recordRecent(target)
        root.notify("Protected", line, "normal")
        root.loadCities(true)
      }
      // Look at the link now rather than waiting up to watchIntervalSec, so
      // the override is released against fresh data as soon as possible.
      root.watchLink()
      delayedRefresh.restart()
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._actionEndedMs = Date.now()
      var out = String(actionStdout.text || "")
      var err = String(actionStderr.text || "")
      root.pendingLabel = ""
      if (exitCode !== 0) {
        root._desired = -1
        root._expectDown = false
        root.lastError = Model.elide(err || out || "Command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.refreshAccount()
      delayedRefresh.restart()
    }
  }
}
