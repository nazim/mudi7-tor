# Changelog

## 1.0.0 - 2026-10-23

- card: Tor on/off card in the touchscreen VPN Dashboard
- card: Kill Switch badge
- card: card and list shown to the touchscreen only, not the web admin panel
- card: status row excluded from the status-bar VPN badge
- switch: Tor and VPN tunnels turn each other off on the touchscreen
- list: bridges and exit countries in one Tor group under Via → Use
- list: bridge status Connected, Idle or Off
- list: Submit saves bridges to torrc and countries to uci tor.global
- list: Tor list rejected for VPN tunnels, other groups rejected for the Tor card
- labels: home screen VPN card reads "VPN / TOR"
- lockscreen: Tor state, exit country and exit IPv4 in the signature line, RAM only
- lockscreen: no exit address request while the backlight is off
- state: torrc, uci tor and control.log re-read only when changed; /proc/net/tcp read only for the Use list
- install: checks firmware 4.10.0, GL-E5800 and SHA-256 of every GL.iNet file used
- rollback: restores stock files and the user's signature
- docs: README with status badges, advanced-user warning and reverse engineering credits
