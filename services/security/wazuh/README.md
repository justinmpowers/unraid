# Wazuh (SIEM)

Single-node [Wazuh](https://wazuh.com) 4.14: security event collection, correlation and alerting.

| Container | Role | Reachable at |
|---|---|---|
| `wazuh-manager` | Receives agent and syslog events, runs the detection rules | `1514/tcp` agents, `1515/tcp` enrollment, `514/udp` syslog (host ports) |
| `wazuh-indexer` | OpenSearch storage for alerts and inventory | `wazuh_net` only |
| `wazuh-dashboard` | Web UI | `https://wazuh.${DOMAIN}` (Traefik, **LAN only**) |

Alerts of level 10 and above are pushed to ntfy topic **`homelab-security`**.

Resource limits add up to about 4.5 CPU and 6 GB RAM. Expect around 3 GB in use when idle, mostly the indexer heap.

## Stack variables

| Variable | Notes |
|---|---|
| `TZ`, `HOST_HOSTNAME`, `DOMAIN`, `APPDATA_PATH` | Same as the other stacks |
| `WAZUH_INDEXER_PASSWORD` | Indexer `admin` user. Also used to log in to the dashboard |
| `WAZUH_DASHBOARD_PASSWORD` | Indexer `kibanaserver` service account |
| `WAZUH_API_PASSWORD` | Manager API user `wazuh-wui`. Needs 8 to 64 characters with upper case, lower case, a digit and a symbol |
| `WAZUH_SYSLOG_PORT` | Optional. Host UDP port for syslog, default `514` |
| `WAZUH_INDEXER_HEAP` | Optional. Indexer JVM heap, default `1g`. Keep the indexer's memory limit at about twice this |

Don't use `$ | ' " \` or spaces in the passwords: the images write them into config files with `sed`.

## First deploy

1. Generate the three passwords, save them in Vaultwarden, then run the setup script on the Unraid host as root:
   ```bash
   export WAZUH_INDEXER_PASSWORD='...' WAZUH_DASHBOARD_PASSWORD='...'
   export NTFY_TOKEN='tk_...'    # optional; see "ntfy alerts" below
   curl -fsSL https://raw.githubusercontent.com/justinmpowers/unraid/main/scripts/setup-wazuh.sh \
     | bash -s -- /mnt/user/appdata
   ```
   The script:
   - sets `vm.max_map_count=262144`, which the indexer needs to start, and adds it to `/boot/config/go` so it persists across reboots
   - copies `config/` into `/mnt/user/appdata/wazuh/config/`
   - generates the internal TLS certificates in `/mnt/user/appdata/wazuh/certs/`
   - writes the indexer user file with bcrypt hashes of your passwords
   - installs the ntfy integration

   Certificates and users are created only on the first run. Running the script again just re-syncs the config files.
2. In Portainer, create the stack `security-wazuh` from the compose path `services/security/wazuh/docker-compose.yml`, add the variables above, and deploy. The first start takes 2 to 3 minutes.
3. **Run the script again** now that the stack is up. This run installs the custom rules, applies the security config, and creates the retention policy. Then restart the containers it lists.
4. Add a LAN DNS record for `wazuh.${DOMAIN}` pointing at Traefik, like the other `-lan` routers. Log in as `admin` with `WAZUH_INDEXER_PASSWORD`.

**Upgrading an existing install to this version:** run the script *before* redeploying the stack. The indexer now mounts `security_config.yml` and `roles_mapping.yml`, and the script creates them. Then redeploy and run the script once more.

## Single sign-on (Authentik)

The login page offers **Log in with Authentik** next to the password form. Members of the Authentik group `wazuh-admins` get full access. Password login as `admin` keeps working.

1. **In Authentik:**
   - **Applications → Providers → Create → OAuth2/OpenID Provider:**
     - Name: `wazuh`
     - Authorization flow: the default explicit-consent or implicit-consent flow
     - Client type: **Confidential**
     - Redirect URI: `https://wazuh.${DOMAIN}/auth/openid/login` (strict)
     - Signing key: the default self-signed certificate
     - Scopes: leave the defaults (`openid`, `email`, `profile`; `profile` carries the `groups` claim)
   - **Applications → Create:** name `Wazuh`, slug **`wazuh`** (the URLs below depend on it), provider `wazuh`, launch URL `https://wazuh.${DOMAIN}`.
   - **Directory → Groups → Create** `wazuh-admins` and add yourself.
2. **On the server**, with the Client ID and Client Secret from the provider:
   ```bash
   export DOMAIN='example.com' WAZUH_OIDC_CLIENT_ID='...' WAZUH_OIDC_CLIENT_SECRET='...'
   curl -fsSL https://raw.githubusercontent.com/justinmpowers/unraid/main/scripts/setup-wazuh.sh | bash -s -- /mnt/user/appdata
   docker restart wazuh-dashboard
   ```
   The script saves these values in `wazuh/config/oidc.env` (root-only), so later runs don't need them. It also:
   - checks that the stack can reach `https://auth.${DOMAIN}/application/o/wazuh/.well-known/openid-configuration`
   - enables the OpenID domain in the indexer
   - maps the `wazuh-admins` group to `all_access` in the indexer and to the Wazuh `administrator` role in the API

**If Authentik is down when the dashboard starts, the dashboard won't start**, password login included. Docker keeps restarting it, and it comes up about 30 seconds after Authentik is back. Agents, syslog collection and ntfy alerts don't depend on it. To remove SSO entirely, run the script with `WAZUH_OIDC_DISABLE=1`, then `docker restart wazuh-dashboard`.

## Feeding it data

- **Unraid host**: Settings → Syslog Server → *Local syslog server* **Disabled**, because Wazuh owns UDP 514. Set *Remote syslog server* to the server's LAN IP, port `514` (or your `WAZUH_SYSLOG_PORT`), protocol UDP. Syslog is accepted only from private address ranges.
  - **SSH logins:** handled by Wazuh's built-in sshd rules.
  - **webGUI logins:** decoded by [config/manager/unraid_decoders.xml](config/manager/unraid_decoders.xml) and [unraid_rules.xml](config/manager/unraid_rules.xml).

  | Rule | Event | Level |
  |---|---|---|
  | 100601 | Failed webGUI login | 5 |
  | 100602 | 5 failed webGUI logins from one IP in 5 minutes | 10 (ntfy) |
  | 100603 | Successful webGUI login | 3 |

- **Router, firewall, switches and APs**: point their remote syslog at the same address.
- **UniFi (UDM Pro)**: Settings → Control Plane → Integrations → Activity Logging → *SIEM Server*, using the Unraid LAN IP and port 514. The UDM sends CEF, which [config/manager/unifi_decoders.xml](config/manager/unifi_decoders.xml) and [unifi_rules.xml](config/manager/unifi_rules.xml) decode. Every UDM event is stored (search `rule.groups: unifi`). These go to ntfy at level 10+:

  | Rule | Event |
  |---|---|
  | 100510 / 100511 | IDS/IPS or threat detection |
  | 100521 | 5 failed admin logins in 5 minutes |
  | 100530 / 100531 | UniFi severity 9–10 / 7–8 |
  | 100541 | 20 firewall blocks from one source in a minute |

  The setup script installs the UniFi and Unraid rules into the manager's `etc/` only after the stack has started once, because the image fills that directory only when it's empty. On a new install, deploy first, re-run the script, then `docker restart wazuh-manager`. To test a line, run `docker exec -it wazuh-manager /var/ossec/bin/wazuh-logtest`.
- **PCs and servers**: install a Wazuh agent. In the dashboard, go to *Agents management → Deploy new agent*, set the server address to the Unraid LAN IP, and run the command it generates. Agents add file-integrity monitoring, vulnerability detection, inventory and CIS checks.

The manager's own rootcheck, file-integrity, inventory and SCA scans are **off**: in a container they would only scan the Wazuh manager container itself. Agents run them on real hosts. Unraid's Slackware base isn't a supported agent platform, so the Unraid host is covered through syslog.

## Retention

The setup script keeps an index policy, `wazuh-retention`, that deletes `wazuh-alerts-*`, `wazuh-archives-*`, `wazuh-monitoring-*` and `wazuh-statistics-*` indices after **90 days**. Each day gets its own index. To change the period, run the script with `WAZUH_RETENTION_DAYS=<days>`. The policy is under *Indexer management → Index Management → State management policies*.

## ntfy alerts

The `custom-ntfy` integration posts every alert of level 10 or higher, e.g. an SSH brute force (rule 5712), to `http://ntfy:80/homelab-security`. Priority is *urgent* for level 13+, *high* for 12, and *default* for 10 to 11. To change the threshold or topic, edit the `<integration>` block in [config/manager/ossec.conf](config/manager/ossec.conf).

ntfy denies anonymous writes, so give the existing `alerts` user a token. It already has write access to `homelab-*`; see [../../monitoring/alertmanager/README.md](../../monitoring/alertmanager/README.md#ntfy-setup-once).
```bash
docker exec ntfy ntfy token add --label=wazuh alerts     # prints tk_...
NTFY_TOKEN='tk_...' bash setup-wazuh.sh /mnt/user/appdata   # or re-run the curl command with NTFY_TOKEN set
```
Then subscribe to `homelab-security` in the ntfy app.

## Changing config

Edit the files under `config/` and push. Then re-run the setup script on the server and restart the containers it lists. `ossec.conf` is copied into the manager on every start.

Custom rules and decoders live in `/mnt/user/appdata/wazuh/manager/etc/rules` and `.../etc/decoders`. You can also edit them from the dashboard under *Server management → Rules*.

## Changing passwords later

- **`WAZUH_API_PASSWORD`**: change it in Portainer and redeploy. The manager applies it on start. Then update the password in `/mnt/user/appdata/wazuh/dashboard/config/wazuh.yml`, or delete that file so it is rewritten, and restart the dashboard.
- **Indexer passwords**: `internal_users.yml` is only read when the security index is first created. To change a password afterwards, rehash it, update the file, push it with `securityadmin.sh`, then update the Portainer variable and redeploy:
  ```bash
  docker exec wazuh-indexer bash -c 'JAVA_HOME=/usr/share/wazuh-indexer/jdk \
    /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "NEW_PASSWORD"'
  # paste the hash into /mnt/user/appdata/wazuh/config/indexer/internal_users.yml, then:
  docker exec wazuh-indexer bash -c 'JAVA_HOME=/usr/share/wazuh-indexer/jdk \
    /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
    -f /usr/share/wazuh-indexer/config/opensearch-security/internal_users.yml -t internalusers \
    -icl -nhnv -cacert /usr/share/wazuh-indexer/config/certs/root-ca.pem \
    -cert /usr/share/wazuh-indexer/config/certs/admin.pem -key /usr/share/wazuh-indexer/config/certs/admin-key.pem'
  ```

## Backups

Everything lives under `/mnt/user/appdata/wazuh/`. The parts worth backing up with Kopia are `certs/`, `config/` and `manager/` (agent keys, custom rules). `indexer/data/` is large and can be rebuilt; alerts are also kept as files in `manager/logs/alerts/`.

## Upgrading

Renovate opens PRs for the three images. Bump all three to the same version together and read the Wazuh release notes first. Minor 4.x upgrades need no extra steps; 5.0 will need a migration.
