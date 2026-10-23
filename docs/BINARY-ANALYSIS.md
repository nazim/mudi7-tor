# Binary analysis findings

Everything found with REA and Ghidra while building mudi7-tor, on
2026-10-23. Addresses are Ghidra addresses (image base `0x100000`; the file
offset of a string in the first segment is the address minus `0x100000`).
"Observed" means read from the binary or decompiler output; "inferred" means a
conclusion drawn from it.

## Target

| Item | Value |
|---|---|
| File | `/usr/bin/gl_screen` from GL.iNet firmware `e5800-4.10.0_release5-1092-0825` |
| SHA-256 | `c1aed1444ab8e516a2471b513fa93f8fe3413eec48e3b569047d655f1fba30fc` |
| Format | ELF 64-bit PIE, AArch64, dynamically linked, interpreter `/lib/ld-musl-aarch64.so.1`, **no section headers** |
| Size | 3,683,283 bytes |
| Load segments | `LOAD off=0x0 va=0x0 filesz=0x35329c flags=r-x`; `LOAD off=0x355b30 va=0x365b30 filesz=0x2d8a3 flags=rw-` |
| Libraries seen in strings | musl, LVGL (`lv_*`), libwebsockets (`lws_*`), jansson-style JSON API (`json_object_get`, `json_array_get`, `json_integer_value`, …), OpenSSL (`SSL_*`), `libubus.so.20230605` (`ubus_connect`, `ubus_invoke_fd`, `ubus_add_object`) |
| Ghidra memory blocks searched | `segment_2` `0x100000–0x45329b` (3,486,364 bytes), `segment_3` `0x465b30–0x46ffff` (42,192), `segment_3.split` `0x470000–0xbadf5f` (7,593,824), `EXTERNAL` `0xbae000–0xbaec07` uninitialized; 11,122,380 bytes in total |

## Tooling and limits

- **REA** (`rea-agents@6.7.0`) with the Ghidra 12.1.4 provider. The binary
  comes from the firmware's ext4 system image.
- `search_strings` returned nothing for `TOR_SETTING_LIST_LABEL_TEXT`: without
  section headers Ghidra defines almost no string data, so the provider's
  string inventory is empty. `search_bytes` and `xrefs` on hand-computed
  addresses worked.
- Ghidra's default analysis treats the call to `FUN_002481e0` (the task
  completion callback, `hasNoReturn=false`) as a terminal call and cuts
  function bodies after it. A headless re-analysis with the option
  "Non-Returning Functions - Discovered" set to false (`NoNoReturn.java`)
  merged the task functions back into their real bodies. Function sizes
  below come from that run where noted. The scripts are in `docs/ghidra/`.
- Decompiled text is Ghidra output, not source. Function names are Ghidra's
  `FUN_<address>`; task names come from the `syslog` format strings inside
  them.

## Strings and their addresses

Hand-located with a byte search (`\0<text>\0`), then confirmed with
`search_bytes` / `xrefs` where listed.

| String | Address | References (code address → containing function) |
|---|---|---|
| `TOR_TITLE_LABEL_TEXT` | `0x397038` | `0x1d5078` → `FUN_001d4f70` |
| `TOR_ENABLE_LABEL_TEXT` | `0x397050` | — |
| `TOR_WARNING_TEXT` | `0x397098` | — |
| `TOR_EXIT_NODE_TITLE_TEXT` | `0x3970b0` | — |
| `STATUS_TOR_LINK_LABEL_TEXT` | `0x396020` | `0x1c9364` |
| `SWITCH_BUTTON_TOR_LABEL_TEXT` | `0x39a138` | `0x204a84` → `FUN_00204950` |
| `TOR_SETTING_LIST_LABEL_TEXT` | **not in the binary** (`search_bytes` over all blocks: no match); exists only in the language file | — |
| `STATUS_VPN_CLIENT_LINK_LABEL_TEXT` | `0x395eb0` | — |
| `VPN@CLIENT_FROM_SELECT_LABEL_TEXT` ("Selected %d / Total %d") | `0x398780` | `0x1e54e4`, `0x1e5cb8`, `0x1e5ef4`, `0x1e8bc4`, `0x1e8ce0` (last two → `FUN_001e8ad0`) |
| `VPN@CLIENT_STATUS_SELECT_LABEL_TEXT` | `0x398840` | — |
| `/etc/gl_screen/image/vpn_text.png` | `0x3875c8` | `0x13cb9c` |
| `/etc/gl_screen/image/tor_text.png` | `0x3875f0` | — |
| `status_list` | `0x39ccb0` | `0x222498` → `FUN_002223e0` |
| `tunnels` | `0x39cd10` | `0x2227fc` → `FUN_002223e0` |
| `set_tunnel` | `0x39aae8` | `0x209894`, `0x20f424`, `0x21138c`, `0x2132a4`, `0x21c0c0` |
| `get_group_list` | `0x39b108` | `0x20c75c`, `0x20c780` → `FUN_0020c1a0` |
| `get_config_list` | `0x39a378` | — |
| `wg-client` | `0x39b118` | — |
| `id_list` | `0x39af70` | `0x20baec` → `FUN_0020adc0`; `0x21c214` → `FUN_0021a810` |
| `group_id` | `0x39a218` | `0x205994`, `0x206788`, `0x2074d4`, `0x21bc24`, `0x21c1f8` |
| `configs` | `0x39c8a8` | `0x21c094` |
| `via` | `0x39bbc8` | `0x212b90` → `FUN_00212a60`; `0x21c040` |
| `peer_id` | `0x39a250` | — |
| `peer_count` | `0x399ea8` | — |
| `task_get_vpn_client_status` | `0x39e7e0` | — |
| `/tmp/gl_screen/config` | `0x3882c8` | — |
| `%s/%s` | `0x388258` | `0x13d538` → `FUN_0013d4f0` |
| `/etc/gl_screen/language/text/default` | `0x39f630` | `0x23f868` → `FUN_0023f670` |

Keys the decompiler left unnamed, with the likely text (inferred from use):
`0x39bbc0` = `from`, `0x39b928` = `to` (both used next to `via` in
`add_tunnel`), `0x3f60f8` = `name` (string field read from each peer and each
tunnel), `0x39b1a0` = `mode` (integer read from the `get_status` result).

Other strings observed (no address work):

- RPC endpoint and auth: `http://127.0.0.1:%d/rpc`, `http://127.0.0.1/rpc`,
  `127.0.0.1`, header `glinet: 1`.
- ubus: object `gl_screen`, method `set`; log strings
  `[screen][%s][error]ubus set failed`, `Failed to connect to ubus!`.
- Config paths: `/tmp/gl_screen/config`,
  `/etc/gl_screen/config/{reference,inch,screen,product}/{dpr,ndpr}/layout`,
  `/etc/gl_screen/config/{reference,screen}/ppi`, `/etc/gl_screen/countries`.
- Language: the only language name string is `default`; the screen loads one
  text file.
- Lock screen layout keys: `LOCK_SCREEN_DATA_STYLE1_SIGNATURE_LABEL_{X,Y,
  WIDTH,HEIGHT}`, `SIGNATURE_TITLE_LABEL_MAX_WIDTH`, `LOCK_SCREEN_NUMBER_
  KEYBOARD_*`, `LOCK_SCREEN_TOP_APP_CHART_*`, `LOCK_SCREEN_DATA_CARD_*`.
  Layout values (from `config/reference/dpr/layout`): signature label
  `X 12`, `Y 166`, `WIDTH 109`, `HEIGHT 100`; title max width `150`.
- Feature flags read from `system get_info`: `software_feature`,
  `hardware_feature`, `conflict_features`.

### Screen task names (syslog strings)

VPN: `task_add_vpn_client_tunnel`, `task_get_vpn_client_group`,
`task_get_vpn_client_link_status`, `task_get_vpn_client_peer_list`,
`task_get_vpn_client_status`, `task_remove_vpn_client_tunnel`,
`task_set_vpn_client_enable`, `task_set_vpn_client_priority`,
`task_set_vpn_client_supplier`, `task_set_vpn_client_tunnel_from`,
`task_set_vpn_client_tunnel_name`, `task_set_vpn_client_tunnel_to`.
Layout: `gl_load_dpr`, `gl_layout_load_dpr_layout`.

### RPC objects and methods named in the binary

`vpn-client` (`get_tunnel`, `set_tunnel`, `get_status`, `add_tunnel`,
`order_tunnel`, `get_connection_methods`), `wg-client` and `ovpn-client`
(`get_group_list`, `get_config_list`), `tor` (`get_config`, `set_config`,
`get_status`), `system` (`get_info`, `get_status`). The binary names many
more objects for other screens; they are not listed here.

## Functions

### `FUN_001d4f70` — Tor settings page

- Body `0x1d4f70–0x1d541f` (1,200 bytes). Uses `TOR_TITLE_LABEL_TEXT` at
  `0x1d5078`.
- Incoming references (`procedure_references`): three internal jumps
  (`0x1d4fbc→0x1d5248` conditional, `0x1d5214→0x1d5414` conditional,
  `0x1d5410→0x1d4fc0` unconditional) and one **DATA** reference from
  `0x48a130`.
- `0x48a128..0x48a13f` holds three function pointers: `0x1d4f70`,
  `0x1d6580`, `0x1d6440` (a page descriptor table in `.data`).
- `xrefs` on `0x48a128` and `0x48a130`: none. **Inferred:** nothing in this
  build dispatches to the Tor page through that table; the page exists but no
  menu entry reaches it. The More-menu label for it
  (`TOR_SETTING_LIST_LABEL_TEXT`) is absent from the binary, which agrees.

### `FUN_00204950` — toggle button labels

- Body `0x204950–0x204aef` (416 bytes). Maps the toggle-button function to
  its label; references `SWITCH_BUTTON_TOR_LABEL_TEXT` at `0x204a84`.
- On the Mudi 7 `hardware_feature.switch_button` is empty (device RPC), so
  this screen is not offered there.

### `FUN_002223e0` — `task_get_vpn_client_link_status` (status-bar VPN badge)

Body `0x2223e0–0x223a2f` (5,712 bytes). Observed behaviour:

1. Calls `vpn-client get_status`, takes `result.status_list` (must be an
   array).
2. For each row: reads `enabled`; a row whose `enabled` is JSON `false`
   (type tag 6) is skipped; a missing `enabled` aborts with
   `task get vpn client link status failed`.
3. On kept rows: if `type` is the string `tap-s2s`, sets a flag; reads
   `status` (must be an integer): `1` → badge state 1 and stop; `2` → badge
   state 2 and continue; other values → next row.
4. Calls `get_status` again, reads the integer at key `0x39b1a0` (`mode`,
   inferred) into `DAT_004ab3e0`. If it is `1`, calls `vpn-client
   get_tunnel` and copies up to `0x20` (32) tunnels into a static table:
   `tunnel_id` (integer) and `name` (string, `strncpy` with `0x3f` = 63
   characters, NUL-terminated at byte 63).
5. Copies the collected state into an `0x890`-byte output structure.

**Consequence used by mudi7-tor:** the Tor status row sends
`enabled = false` so the VPN badge ignores it; the card switch reads
`enabled` from `get_tunnel` instead (confirmed on the screen).

### `FUN_0021a810` — VPN peer list and tunnel submit (merged body)

Reported as `FUN_0021b090` (5,760 bytes) by the default analysis; the
re-analysis gives `FUN_0021a810` with 7,936 bytes. It contains several tasks:

**`task_get_vpn_client_peer_list`** (around `0x21b860–0x21bec0`):

- For a WireGuard group: builds `{group_id}` and calls
  `wg-client get_config_list`; reads `result.peers`. For an OpenVPN group:
  calls `FUN_00206730` and reads `result.clients`.
- Per item, in order: `name` (string, required), `location` or `end_point`
  (string; when present, stored as the second line and a flag is set),
  `peer_id` (WireGuard) or `client_id` (OpenVPN) (integer, required),
  `name` again for the row. Items with type `tap-s2s` go to a separate list.
- Both lists are sorted with a comparator (`FUN_00203d30`) through a sort
  routine at `PTR_FUN_0046ff08`. The comparator was not decompiled; on the
  device the rows appear in alphabetical order of `name` (observed).
- Any missing required field logs `get vpn client peer list failed`.

**Tunnel submit task** (around `0x21bec0–0x21c0c0`):

- Builds `{"tunnel_id": <int>, "via": {...}}` and calls
  `vpn-client set_tunnel` (`0x21c0b0`).
- `via.type` is `"openvpn"` or `"wireguard"` depending on the group kind, or
  `"novpn"` for the no-VPN choice.
- For a provider group: `via.configs = [{"group_id": <int>,
  "id_list": [...]}]` with **one** entry. The id list is filled from an
  internal integer array, skipping index 0 and non-positive values.

An unrelated task shares this merged body.

### `FUN_0020c1a0` — VPN group list (merged body)

Body `0x20c1a0–0x20e367` (8,648 bytes). Contains:

- **`task_get_vpn_client_group`** (`0x20c6d0` area): calls
  `wg-client get_group_list` and `ovpn-client get_group_list` with no
  arguments (no card id is sent), then `FUN_00205790` four times:
  `(wg, 1, pass 0)`, `(ovpn, 0, pass 0)`, `(wg, 1, pass 1)`,
  `(ovpn, 0, pass 1)`. A negative return logs `get vpn client group failed`.
- Two unrelated tasks.

### `FUN_00205790` — group filter

Arguments: `(list, rpc_result, is_wg, &count, pass)`. Observed:

- Requires `result.groups` to be an array.
- Per group reads `peer_count` (WireGuard) or `client_count` (OpenVPN); a
  missing or non-integer value returns `-1` (the whole list fails); a value
  of `0` skips the group.
- `group_type`: `t = 1`, or `t = (group_type != 1)` when the integer is
  present. A group is taken in pass 0 when `t == 0` (`group_type == 1`) and
  in pass 1 otherwise. **Inferred:** provider groups (`group_type 1`) are
  listed first, then the rest. mudi7-tor's group uses `group_type 2` and
  shows after the provider group on the test router, as observed.
- Stores `group_name` (`Hideme` is shown as `Hide.me`), `group_id` and the
  WireGuard/OpenVPN flag; increments the count.

### `FUN_0020adc0` — misc. tasks (merged body)

Body `0x20adc0` (4,000 bytes). Contains `vpn-client order_tunnel` with an
`id_list` (`0x20baec`; tunnel priority), `system get_status` and
`wg-client get_group_list` next to tasks for other screens.

### `FUN_00212a60` — `task_add_vpn_client_tunnel` (merged body)

Body `0x212a60` (736 bytes). Builds
`{from: {type: "default"}, to: {type: "default"}, via: {}, name: <string>}`
and calls `vpn-client add_tunnel` (`via` key at `0x39bbc8`, `from` at
`0x39bbc0`, `to` at `0x39b928`). The same body continues with an unrelated
task.

### `FUN_001e8ad0` — "Selected N / Total M" label

Body `0x1e8ad0–0x1e8d73` (676 bytes). Reads a page-mode integer:

- Mode `2`: total = list length − 1 (`DAT_004aa608`), selected = number of
  set entries in a bit array (`FUN_00241830`) over indexes `1..total`.
- Modes `3` and `4`: selected and total come from a structure at
  `DAT_004aa4a0` (index 9, then 0 or 1 by mode).
- Formats `VPN@CLIENT_FROM_SELECT_LABEL_TEXT` with those two numbers.

### `FUN_0023f670` — layout and text loading

Body `0x23f670` (1,184 bytes); names `gl_load_dpr` and
`gl_layout_load_dpr_layout` from its log strings. Loads
`/etc/gl_screen/config/reference/ppi` and `screen/ppi`, computes the
pixel ratio (`dpr`; error `dpr value error` when 0), then the four `dpr`
layout files, the four `ndpr` layout files and finally
`/etc/gl_screen/language/text/default` (`0x23f868`). **Inferred:** the text
file is read once at start; a change needs a `gl_screen` restart (confirmed:
the home screen label changed only after `/etc/init.d/gl_screen restart`).

### `FUN_0013d4f0` — config file open

Body `0x13d4f0` (292 bytes). `snprintf(buf, 0x100, "%s/%s", dir, name)` then
calls a reader through `PTR_DAT_0046dbf0`; returns `0` on success or
`-2`. Used with `/tmp/gl_screen/config` and the `generic` file name
(the uci "cover" section). **Inferred:** settings such as `SIGNATURE` are read
from `/tmp/gl_screen/config/generic`; `ubus call gl_screen set
'{"method":"reload"}'` re-reads it (confirmed on the device).

### `FUN_00243ef0` — RPC helper

Signature as used: `(object, method, params_json, &result_json)`. Every task
above calls it. The request goes to `http://127.0.0.1[:port]/rpc` with the
`glinet: 1` header (strings). Results are jansson objects freed with
`json_delete` after a reference-count check (`FUN_0034e0a0`).

## Runtime cross-checks

Decompiled behaviour that was confirmed on the device:

| Finding | Check |
|---|---|
| Groups come from `get_group_list` without a card id; every card sees every group | Loopback `tcpdump` capture of the screen's RPC calls |
| Rows come from `get_config_list {group_id}` | Capture: `{"group_id": 10003}`, `{"group_id": 919102}` |
| The screen fetches only the last `via.configs` group of a card | Capture: with two configs on the Tor card only `919103` was requested |
| Submit sends one `configs` entry | Capture and the saved result (`uci tor.global.countries`, `torrc`) |
| Rows sorted by `name` | Screen capture: `(Bridge)` rows sort before `Afghanistan` only after the rename |
| `enabled=false` status rows do not light the VPN badge | Screen capture before and after the change |
| Text file read at start only | Label changed after `gl_screen` restart |
| `reload` re-reads `/tmp/gl_screen/config/generic` | Signature changed with no write to `/etc/config/gl_screen` |

## Other binaries (strings only, no decompilation)

- `/usr/lib/oui-httpd/rpc/screen` (Lua 5.1 bytecode): the web admin
  panel's screen settings go through
  `ubus call gl_screen set {"method":"config_update","params":{"config":{...}}}`,
  `SIGNATURE` among the keys, with validators `signature_min` and
  `signature_max`. On the device `config_update` also wrote
  `/etc/config/gl_screen`, which is why the lock screen service uses
  `reload` instead.

## Not found or not done

- No code path to the Tor settings page (see `FUN_001d4f70`).
- The sort comparator `FUN_00203d30` and the list-page mode values were not
  decompiled.
- `FUN_001c9364`'s surroundings (user of `STATUS_TOR_LINK_LABEL_TEXT`) were
  not read.
- No dynamic analysis (Frida, gdb) was run on the device.
