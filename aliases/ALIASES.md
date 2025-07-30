# ZSH Aliases Reference

This document provides a comprehensive list of all available aliases organized by category.

## Table of Contents

- [Ansible](#ansible) - Automation & orchestration
- [GPG](#gpg) - Key & encryption management
- [IdM/FreeIPA](#idmfreeipa) - RHEL Identity Management
- [Network Information](#network-information) - Network diagnostics
- [Network Configuration](#network-configuration) - Network setup & management
- [Nix](#nix) - Nix package manager, NixOS & nix-darwin
- [Nmap](#nmap) - Network scanning
- [OpenSSL](#openssl) - Certificate operations & encryption
- [OS-Specific](#os-specific) - OS-dependent commands
- [Remote](#remote) - Remote server management
- [Remote State](#remote-state) - Infrastructure state management
- [SSH](#ssh) - SSH connections & key management

## Ansible

Aliases for Ansible automation and orchestration.

### Playbook Execution

| Alias | Description |
|-------|-------------|
| `ansible.play` | Run Ansible playbook |
| `ansible.play.verbose` | Run playbook with verbose output |
| `ansible.play.vverbose` | Run playbook with very verbose output |
| `ansible.play.debug` | Run playbook with debug level verbosity |
| `ansible.play.check` | Run playbook in check mode (dry run) |
| `ansible.play.diff` | Run playbook with diff output |
| `ansible.play.checkdiff` | Run playbook in check mode with diff |
| `ansible.play.syntax` | Check playbook syntax |
| `ansible.play.tags` | Run playbook with specific tags |
| `ansible.play.skip-tags` | Run playbook skipping specific tags |
| `ansible.play.vars` | Run playbook with extra vars from file |
| `ansible.play.limit` | Run playbook with specific host/group limit |

### Inventory Management

| Alias | Description |
|-------|-------------|
| `ansible.inventory.list` | List hosts in inventory |
| `ansible.inventory.graph` | Show inventory graph |
| `ansible.inventory.yaml` | Export inventory to YAML |
| `ansible.inventory.json` | Export inventory to JSON |

### Ad-Hoc Commands

| Alias | Description |
|-------|-------------|
| `ansible.adhoc` | Run ad-hoc Ansible command |
| `ansible.shell` | Run ad-hoc shell command |
| `ansible.root` | Run ad-hoc command as root (become) |
| `ansible.ping` | Check connectivity (ping module) |

### Ansible Galaxy

| Alias | Description |
|-------|-------------|
| `ansible.galaxy.install` | Install roles from requirements file |
| `ansible.galaxy.search` | Search for a role in Ansible Galaxy |
| `ansible.galaxy.role.install` | Install a specific role |
| `ansible.galaxy.role.list` | List installed roles |
| `ansible.galaxy.collection.install` | Install a collection |
| `ansible.galaxy.collection.list` | List installed collections |

### Ansible Vault

| Alias | Description |
|-------|-------------|
| `ansible.vault.create` | Create a new encrypted file |
| `ansible.vault.edit` | Edit an encrypted file |
| `ansible.vault.encrypt` | Encrypt an existing file |
| `ansible.vault.decrypt` | Decrypt a file |
| `ansible.vault.view` | View an encrypted file |
| `ansible.vault.rekey` | Change password of an encrypted file |

### Debugging & Troubleshooting

| Alias | Description |
|-------|-------------|
| `ansible.version` | Show Ansible version |
| `ansible.config.list` | Show Ansible configuration options |
| `ansible.config.view` | Show current Ansible configuration |
| `ansible.config.dump` | Dump all configuration values |
| `ansible.lint` | Lint Ansible playbook |

### Documentation

| Alias | Description |
|-------|-------------|
| `ansible.doc` | Show docs for a module |
| `ansible.doc.list` | List available modules |
| `ansible.doc.search` | Search for modules |

## GPG

Aliases for GPG key and encryption management.

### Key Listing & Fingerprints

| Alias | Description |
|-------|-------------|
| `gpg.list` | List public keys (short ID format) |
| `gpg.list.long` | List public keys (long ID format) |
| `gpg.list.fp` | List public keys with full fingerprints |
| `gpg.list.sec` | List secret keys (short ID format) |
| `gpg.list.sec.fp` | List secret keys with full fingerprints |

### Key Management

| Alias | Description |
|-------|-------------|
| `gpg.import` | Import keys from a file |
| `gpg.export` | Export a public key (ASCII armored) |
| `gpg.export.bin` | Export a public key (binary) |
| `gpg.edit` | Edit a key (trust, add UID, expire, etc.) |
| `gpg.gen.revoke` | Generate a revocation certificate for a key |
| `gpg.gen.key` | Generate a new key pair (interactive wizard) |
| `gpg.gen.key.batch` | Generate a key pair with sensible defaults |
| `gpg.backup.keys` | Create a backup of your keys |
| `gpg.restore.keys` | Restore keys from backup |
| `gpg.check.health` | Check the health of your GPG setup |

### Keyserver Interaction

| Alias | Description |
|-------|-------------|
| `gpg.recv` | Receive keys from a keyserver |
| `gpg.refresh` | Refresh keys from a keyserver |
| `gpg.send` | Send keys to a keyserver |
| `gpg.search` | Search for keys on a keyserver |

### Encryption & Signing

| Alias | Description |
|-------|-------------|
| `gpg.encrypt` | Encrypt a file for recipient(s) |
| `gpg.encrypt.sign` | Encrypt and sign a file for recipient(s) |
| `gpg.encrypt.sym` | Encrypt file symmetrically (password-based) |
| `gpg.decrypt` | Decrypt a file or message |
| `gpg.sign` | Create a detached signature |
| `gpg.sign.clear` | Create a clear-signed message |
| `gpg.verify` | Verify a signature |

## IdM/FreeIPA

Aliases for Red Hat Identity Management (IdM/FreeIPA).

### User Management

| Alias | Description |
|-------|-------------|
| `idm.user.find` | Find a user |
| `idm.user.show` | Show user details |
| `idm.user.add` | Add a new user |
| `idm.user.mod` | Modify a user |
| `idm.user.del` | Delete a user |
| `idm.user.exists` | Check if a user exists |
| `idm.user.passwd` | Set user password |
| `idm.user.enable` | Enable a user |
| `idm.user.disable` | Disable a user |
| `idm.user.reset` | Reset user password |

### Group Management

| Alias | Description |
|-------|-------------|
| `idm.group.find` | Find a group |
| `idm.group.show` | Show group details |
| `idm.group.add` | Add a new group |
| `idm.group.del` | Delete a group |
| `idm.group.add-member` | Add user to group |
| `idm.group.remove-member` | Remove user from group |
| `idm.group.members` | Show members of a group |

### Host Management

| Alias | Description |
|-------|-------------|
| `idm.host.find` | Find a host |
| `idm.host.show` | Show host details |
| `idm.host.add` | Add a new host |
| `idm.host.del` | Delete a host |
| `idm.hostgroup.add-member` | Add host to hostgroup |
| `idm.hostgroup.find` | Find hostgroups |
| `idm.hostgroup.show` | Show hostgroup details |

### Service Management

| Alias | Description |
|-------|-------------|
| `idm.service.find` | Find a service |
| `idm.service.show` | Show service details |
| `idm.service.add` | Add a new service |
| `idm.service.del` | Delete a service |

### DNS Management

| Alias | Description |
|-------|-------------|
| `idm.dns.find` | Find DNS records |
| `idm.dns.show` | Show DNS record |
| `idm.dns.add` | Add DNS record |
| `idm.dns.del` | Delete DNS record |
| `idm.dnszone.find` | Find DNS zones |
| `idm.dnszone.add` | Add DNS zone |

### Certificate Management

| Alias | Description |
|-------|-------------|
| `idm.cert.find` | Find certificates |
| `idm.cert.show` | Show certificate |
| `idm.cert.request` | Request a new certificate |

### Access Control

| Alias | Description |
|-------|-------------|
| `idm.hbac.find` | Find HBAC rules |
| `idm.hbac.show` | Show HBAC rule |
| `idm.hbac.add` | Add HBAC rule |
| `idm.hbac.add-user` | Add users to HBAC rule |
| `idm.hbac.add-host` | Add hosts to HBAC rule |
| `idm.hbac.add-service` | Add services to HBAC rule |
| `idm.sudo.find` | Find sudo rules |
| `idm.sudo.show` | Show sudo rule |
| `idm.sudo.add` | Add sudo rule |
| `idm.sudo.add-user` | Add users to sudo rule |
| `idm.sudo.add-host` | Add hosts to sudo rule |
| `idm.sudo.add-command` | Add commands to sudo rule |

### Server Management & Authentication

| Alias | Description |
|-------|-------------|
| `idm.server.status` | Check IdM server status |
| `idm.server.start` | Start IdM server |
| `idm.server.stop` | Stop IdM server |
| `idm.server.restart` | Restart IdM server |
| `idm.server.info` | Display IdM server information |
| `idm.version` | Display IdM version information |
| `idm.ticket.list` | List Kerberos tickets |
| `idm.ticket.get` | Get a new Kerberos ticket |
| `idm.ticket.destroy` | Destroy Kerberos tickets |
| `idm.check.connectivity` | Check IdM client connectivity |
| `idm.check.replication` | Check IdM replication status |
| `idm.check.health` | Run IdM healthcheck |

## Network Information

Aliases for network information and diagnostics.

### Interface & IP Info

| Alias | Description |
|-------|-------------|
| `net.ip` | Show assigned IP addresses (IPv4 & IPv6) |
| `net.links` | Show network interfaces and link status |

### Routing Info

| Alias | Description |
|-------|-------------|
| `net.routes` | Show routing table |
| `net.gw` | Show default gateway |

### DNS Info & Management

| Alias | Description |
|-------|-------------|
| `net.dns` | Show configured DNS servers |
| `net.dns.flush` | Attempt to flush DNS cache |

### Socket / Port Info

| Alias | Description |
|-------|-------------|
| `net.ports` | Show listening TCP/UDP ports |

### Network Service Status

| Alias | Description |
|-------|-------------|
| `net.svc.nm.status` | NetworkManager status |
| `net.svc.networkd.status` | systemd-networkd status |
| `net.svc.resolved.status` | systemd-resolved status |

### Firewall Status

| Alias | Description |
|-------|-------------|
| `net.fw.ufw.status` | UFW firewall status (Ubuntu) |
| `net.fw.firewalld.status` | firewalld status (RHEL/Fedora) |
| `net.fw.pf.status` | PF firewall status (macOS) |

### Diagnostics

| Alias | Description |
|-------|-------------|
| `net.diag.ping` | Ping host (4 packets) |
| `net.diag.trace` | Traceroute to host |
| `net.diag.dig` | DNS lookup (short form) |
| `net.diag.host` | DNS lookup (standard host command) |
| `net.diag.whois` | Whois lookup |
| `net.diag.myip` | Get public IP address |

### Advanced Troubleshooting

| Alias | Description |
|-------|-------------|
| `net.diag.mtr` | Combination of ping and traceroute |
| `net.diag.iperf.client` | Network performance test (client) |
| `net.diag.iperf.server` | Network performance test (server) |
| `net.diag.http` | Detailed HTTP timing |
| `net.diag.conn` | Show all active network connections |

## Network Configuration

Aliases for network configuration and management.

### Config Guidance

| Alias | Description |
|-------|-------------|
| `net.conf.edit` | Show network config editing guidance |
| `net.conf.dns.edit` | Show DNS configuration guidance |
| `net.conf.apply` | Guidance for applying network changes |

### Config Directories

| Alias | Description |
|-------|-------------|
| `net.conf.cd.netplan` | Go to Netplan config dir (Ubuntu) |
| `net.conf.cd.nm` | Go to NetworkManager connections dir |

### Wi-Fi Management

| Alias | Description |
|-------|-------------|
| `net.wifi.scan` | Scan available Wi-Fi networks |
| `net.wifi.connect` | Connect to Wi-Fi network |
| `net.wifi.signal` | Show current Wi-Fi signal strength |
| `net.wifi.on` | Turn Wi-Fi on |
| `net.wifi.off` | Turn Wi-Fi off |
| `net.wifi.toggle` | Toggle Wi-Fi on/off |
| `net.wifi.saved` | List saved Wi-Fi networks |

### Hostname Configuration

| Alias | Description |
|-------|-------------|
| `net.hostname.set` | Set system hostname |
| `net.hostname.show` | Show current hostname |

## Nix

Aliases for Nix package manager, NixOS, and nix-darwin.

### Package Management

| Alias | Description |
|-------|-------------|
| `nix.search` | Search for packages |
| `nix.install` | Install package to user profile |
| `nix.install.attr` | Install package with attribute path |
| `nix.uninstall` | Uninstall package from user profile |
| `nix.upgrade` | Upgrade user profile packages |
| `nix.list` | List installed packages |
| `nix.show` | Show derivation for a package |
| `nix.info` | Show package information |
| `nix.run` | Run software without installing |
| `nix.build` | Build a single package |

### Development Environments

| Alias | Description |
|-------|-------------|
| `nix.shell` | Start a nix-shell with packages |
| `nix.shell.pure` | Start a pure nix-shell with packages |
| `nix.develop` | Start a shell from a flake |
| `nix.dev.pkg` | Enter a development shell for a package |
| `nix.mkshell` | Create a shell.nix file interactively |
| `nix.mkflake` | Create a flake.nix template interactively |

### NixOS System Management

| Alias | Description |
|-------|-------------|
| `nixos.rebuild` | Rebuild NixOS system |
| `nixos.rebuild.flake` | Rebuild NixOS system with flake |
| `nixos.test` | Test NixOS configuration without switching |
| `nixos.build` | Build NixOS configuration but don't activate |
| `nixos.edit` | Edit NixOS configuration file |
| `nixos.edit.hardware` | Edit hardware-configuration.nix |
| `nixos.cd` | Go to NixOS configuration directory |
| `nixos.generations` | List current NixOS system generations |
| `nixos.boot-generation` | Boot into a specific NixOS generation |
| `nixos.version` | Show current system version |

### nix-darwin System Management

| Alias | Description |
|-------|-------------|
| `darwin.rebuild` | Rebuild Darwin system |
| `darwin.rebuild.flake` | Rebuild Darwin system with flake |
| `darwin.edit` | Edit Darwin configuration file |
| `darwin.cd` | Go to Darwin configuration directory |

### Flake Management

| Alias | Description |
|-------|-------------|
| `nix.flake.update` | Update flake inputs |
| `nix.flake.lock` | Lock flake to specific input |
| `nix.flake.info` | Show flake info |
| `nix.flake.check` | Check flake outputs |
| `nix.flake.inputs` | List flake inputs |

### Nix Store & Garbage Collection

| Alias | Description |
|-------|-------------|
| `nix.gc` | Collect garbage (with confirmation) |
| `nix.gc.all` | Aggressive garbage collection |
| `nix.gc.old` | Clean up old generations |
| `nix.store.refs` | Show store path references |
| `nix.store.referrers` | Show reverse references |
| `nix.store.size` | Show store path closure size |

### Deterministic Builds

| Alias | Description |
|-------|-------------|
| `nix.drv` | Print derivation for a package |
| `nix.deps` | Show build dependencies of a package |
| `nix.diff` | Check if paths have the same content |
| `nix.bundle` | Generate a reproducible source archive |
| `nix.log` | Show build log |

### Nix Configuration & Information

| Alias | Description |
|-------|-------------|
| `nix.config` | Show Nix config |
| `nix.config.edit` | Edit global Nix config |
| `nix.enable.flakes` | Enable flake support |
| `nix.channels` | Show Nix channels |
| `nix.channels.update` | Update all channels |
| `nix.channels.add` | Add a new channel |
| `nix.channels.remove` | Remove a channel |
| `nix.doctor` | Check the health of the nix installation |
| `nix.top` | Show top packages by closure size |

## Nmap

Aliases for network scanning using Nmap.

### Host Discovery

| Alias | Description |
|-------|-------------|
| `nmap.ping` | Standard ping scan (no port scan) |
| `nmap.ping.arp` | ARP ping scan (fast, LAN only) |
| `nmap.ping.icmp` | ICMP echo ping scan |
| `nmap.ping.syn` | TCP SYN ping scan |
| `nmap.ping.ack` | TCP ACK ping scan |
| `nmap.scan.no-ping` | Skip host discovery (assume up) |

### Port Scanning

| Alias | Description |
|-------|-------------|
| `nmap.scan.tcp` | TCP SYN scan (stealthy, default ports) |
| `nmap.scan.tcp.connect` | TCP Connect scan (no sudo needed) |
| `nmap.scan.udp` | UDP scan (slow) |
| `nmap.scan.fast` | Fast scan (top 100 ports) |
| `nmap.scan.tcp.allports` | Scan all 65535 TCP ports (very slow) |
| `nmap.scan.tcp.web` | Scan common web ports (80,443,8080,8443) |

### Stealth/Advanced Scans

| Alias | Description |
|-------|-------------|
| `nmap.scan.tcp.null` | TCP NULL scan (no flags set, stealthy) |
| `nmap.scan.tcp.fin` | TCP FIN scan (FIN flag only, stealthy) |
| `nmap.scan.tcp.xmas` | TCP XMAS scan (FIN,PSH,URG flags, stealthy) |
| `nmap.scan.tcp.ack` | TCP ACK scan (firewall rule mapping) |
| `nmap.scan.tcp.window` | TCP Window scan (more accurate than ACK) |

### Service/Version Detection

| Alias | Description |
|-------|-------------|
| `nmap.scan.version` | Basic version detection scan |
| `nmap.scan.version.intense` | Intense version detection (level 9) |
| `nmap.scan.os` | OS detection scan |
| `nmap.scan.aggressive` | OS, version, scripts, traceroute scan |

### NSE Scripting

| Alias | Description |
|-------|-------------|
| `nmap.scripts.default` | Run default safe scripts |
| `nmap.scripts.discovery` | Run discovery category scripts |
| `nmap.scripts.vuln` | Run vulnerability scripts |
| `nmap.scripts.auth` | Run authentication scripts |
| `nmap.scripts.exploit` | Run exploit scripts |
| `nmap.scripts.custom` | Run specific script(s) |
| `nmap.scripts.withargs` | Run scripts with args |

### Timing & Output Options

| Alias | Description |
|-------|-------------|
| `nmap.timing.insane` | T5 (very fast, noisy) |
| `nmap.timing.aggressive` | T4 (default) |
| `nmap.timing.polite` | T2 (slower, less noisy) |
| `nmap.timing.sneaky` | T1 (very slow, IDS evasion) |
| `nmap.out.normal` | Normal output format |
| `nmap.out.xml` | XML output format |
| `nmap.out.grep` | Grepable output format |
| `nmap.out.all` | All output formats |
| `nmap.verbose` | Increase verbosity |
| `nmap.vverbose` | Very verbose output |
| `nmap.reason` | Show reason port is open/closed/filtered |
| `nmap.open` | Only show open ports |
| `nmap.debug.packets` | Show packet trace |

### Evasion Techniques

| Alias | Description |
|-------|-------------|
| `nmap.evade.frag` | Fragment packets |
| `nmap.evade.decoy` | Use decoy IPs to mask scan origin |
| `nmap.evade.srcport` | Specify source port |
| `nmap.evade.random` | Randomize target scan order |

## OpenSSL

Aliases for certificate operations and encryption using OpenSSL.

### Hashing / Message Digests

| Alias | Description |
|-------|-------------|
| `ossl.hash.md5` | Calculate MD5 hash of a file |
| `ossl.hash.sha1` | Calculate SHA1 hash of a file |
| `ossl.hash.sha256` | Calculate SHA256 hash of a file |
| `ossl.hash.sha512` | Calculate SHA512 hash of a file |

### Encoding / Decoding

| Alias | Description |
|-------|-------------|
| `ossl.b64.enc` | Base64 encode stdin or file |
| `ossl.b64.dec` | Base64 decode stdin or file |

### Random Data Generation

| Alias | Description |
|-------|-------------|
| `ossl.rand.bytes` | Generate random bytes |
| `ossl.rand.hex` | Generate random hex string |
| `ossl.rand.b64` | Generate random base64 string |

### Key Generation & Management

| Alias | Description |
|-------|-------------|
| `ossl.gen.rsa` | Generate RSA private key |
| `ossl.gen.rsa.nodes` | Generate unencrypted RSA private key |
| `ossl.gen.ec` | Generate EC private key |
| `ossl.list.eccurves` | List available EC curves |
| `ossl.get.pubkey` | Extract public key from a private key |
| `ossl.check.key` | Check private key consistency |
| `ossl.key.rmpass` | Remove passphrase from a private key |

### Certificate Signing Request (CSR)

| Alias | Description |
|-------|-------------|
| `ossl.gen.csr` | Generate CSR from an existing private key |
| `ossl.gen.keycsr` | Generate NEW private key AND CSR |
| `ossl.gen.csr.conf` | Create a non-interactive CSR with SAN from config file |

### Self-Signed Certificate Generation

| Alias | Description |
|-------|-------------|
| `ossl.gen.selfcert` | Generate NEW key and Self-Signed Cert |

### Viewing Certificates, Keys, CSRs

| Alias | Description |
|-------|-------------|
| `ossl.view.cert` | View details of a Certificate |
| `ossl.view.cert.dates` | View validity dates of a Certificate |
| `ossl.view.cert.subject` | View subject of a Certificate |
| `ossl.view.cert.issuer` | View issuer of a Certificate |
| `ossl.view.cert.serial` | View serial number of a Certificate |
| `ossl.view.cert.fp256` | View fingerprint (SHA256) of a Certificate |
| `ossl.view.cert.sans` | Show certificate SAN entries |
| `ossl.view.cert.sigalg` | Show certificate's Signature Algorithm |
| `ossl.view.csr` | View details of a CSR |
| `ossl.view.key` | View details of a private key |
| `ossl.view.p12` | View details of a PKCS#12 file |

### Verification & Matching

| Alias | Description |
|-------|-------------|
| `ossl.verify.cert` | Verify certificate chain against CA file/path |
| `ossl.verify.chain` | Verify certificate chain with custom CAfile |
| `ossl.verify.system` | Verify certificate chain against OS/browser root certs |
| `ossl.check.match` | Check if Private Key matches Certificate |
| `ossl.check.match.csr` | Check if Private Key matches CSR |
| `ossl.check.expiry` | Check certificate expiration (Days remaining) |
| `ossl.compare.certs` | Compare two certificates |

### Format Conversion

| Alias | Description |
|-------|-------------|
| `ossl.conv.pem2der` | Convert Certificate: PEM -> DER |
| `ossl.conv.der2pem` | Convert Certificate: DER -> PEM |
| `ossl.conv.pemkey2der` | Convert Private Key: PEM -> DER |
| `ossl.conv.derkey2pem` | Convert Private Key: DER -> PEM |
| `ossl.conv.p7btopem` | Convert PKCS#7 (often .p7b) -> PEM |
| `ossl.conv.pemtop7b` | Convert PEM -> PKCS#7 (.p7b) |
| `ossl.conv.p12topem` | Convert PKCS#12 (.pfx/.p12) -> PEM |
| `ossl.conv.p12topem.certs` | Convert PKCS#12 -> PEM (certs only) |
| `ossl.conv.p12topem.key` | Convert PKCS#12 -> PEM (key only) |
| `ossl.conv.pemtop12` | Convert PEM Key + Cert(s) -> PKCS#12 |

### SSL/TLS Client/Server Testing

| Alias | Description |
|-------|-------------|
| `ossl.test.client` | Connect to TLS server (interactive) |
| `ossl.test.client.showcerts` | Connect and show server certificate chain |
| `ossl.test.client.noninteractive` | Connect non-interactively |
| `ossl.test.server` | Run simple TLS test server |
| `ossl.test.tls` | Test TLS connection and report cipher, protocol, key details |
| `ossl.test.tls13` | Test server for TLSv1.3 support |
| `ossl.server.ciphers` | Get server cipher preference order |

### Certificate Chain Operations

| Alias | Description |
|-------|-------------|
| `ossl.build.chain` | Build a certificate chain from individual certificates |
| `ossl.extract.chain` | Extract certificates from a chain file |
| `ossl.extract.leaf` | Extract the first (leaf) certificate from a chain file |
| `ossl.extract.pubkey` | Extract public key from certificate in PEM format |
| `ossl.get.server.cert` | Get a server's certificate |

### Cipher Information

| Alias | Description |
|-------|-------------|
| `ossl.ciphers.list` | List available TLS ciphers |
| `ossl.ciphers.test` | Test specific cipher(s) against a server |

### Password Generation

| Alias | Description |
|-------|-------------|
| `ossl.gen.password` | Generate a strong random password |
| `ossl.change.passphrase` | Change passphrase on a private key |

## OS-Specific

OS-dependent aliases that adapt to your environment.

### macOS-Specific

| Alias | Description |
|-------|-------------|
| `flushdns` | Flush DNS cache |
| `showfiles` | Show hidden files in Finder |
| `hidefiles` | Hide hidden files in Finder |
| `cleanup` | Remove .DS_Store files |
| `sleepoff` | Prevent sleep (caffeinate) |
| `afk` | Lock screen immediately |
| `wifi.on` | Turn on Wi-Fi |
| `wifi.off` | Turn off Wi-Fi |
| `wifi.join` | Join Wi-Fi network |
| `ip.local` | Show local IP address |
| `xcopen` | Open Xcode project in current directory |
| `xcode-clean` | Clean Xcode cache |
| `preview` | Open file in Preview |
| `safari` | Open Safari |
| `firefox` | Open Firefox |
| `chrome` | Open Chrome |
| `code` | Open Visual Studio Code |

### Linux-Specific (Common)

| Alias | Description |
|-------|-------------|
| `sysinfo` | Show system information |
| `cpuinfo` | Show CPU details |
| `meminfo` | Show memory information |
| `diskinfo` | Show disk usage |
| `release` | Show Linux distribution info |
| `sc-status` | Check systemd service status |
| `sc-start` | Start systemd service |
| `sc-stop` | Stop systemd service |
| `sc-restart` | Restart systemd service |
| `sc-enable` | Enable systemd service |
| `sc-disable` | Disable systemd service |
| `sc-user` | Control user-level systemd services |
| `sc-list` | List enabled units |
| `sc-failed` | Show failed units |
| `logs` | View system logs |
| `logs-follow` | Follow logs in real-time |
| `logs-boot` | Show logs from current boot |
| `logs-err` | Show error messages |
| `fixperms` | Fix permissions recursively |
| `fixowners` | Fix ownership recursively |

### Debian/Ubuntu Specific

| Alias | Description |
|-------|-------------|
| `apt-update` | Update package lists |
| `apt-upgrade` | Update and upgrade packages |
| `apt-dist` | Perform distribution upgrade |
| `apt-install` | Install package |
| `apt-remove` | Remove package |
| `apt-purge` | Remove package and configuration |
| `apt-autoremove` | Remove unused dependencies |
| `apt-search` | Search for a package |
| `apt-show` | Show package details |
| `apt-list` | List installed packages |
| `apt-holds` | Show held packages |
| `apt-clean` | Clean package cache |

### RHEL/Fedora/CentOS Specific

| Alias | Description |
|-------|-------------|
| `dnf-update` | Check for updates |
| `dnf-upgrade` | Upgrade packages |
| `dnf-install` | Install package |
| `dnf-remove` | Remove package |
| `dnf-search` | Search for a package |
| `dnf-info` | Show package information |
| `dnf-list` | List installed packages |
| `dnf-provides` | Find package providing a file |
| `dnf-clean` | Clean package cache |
| `dnf-history` | Show transaction history |
| `check-selinux` | Check SELinux status |
| `enable-service` | Enable and start service |
| `disable-service` | Disable and stop service |

### Arch Based Specific

| Alias | Description |
|-------|-------------|
| `pac-update` | Update package database |
| `pac-upgrade` | Upgrade all packages |
| `pac-install` | Install package |
| `pac-remove` | Remove package |
| `pac-search` | Search for a package |
| `pac-info` | Show package information |
| `pac-list` | List installed packages |
| `pac-owns` | Find package owning a file |
| `pac-explicit` | List explicitly installed packages |
| `pac-orphans` | List orphaned packages |
| `pac-clean` | Clean package cache |

### WSL Specific

| Alias | Description |
|-------|-------------|
| `winuser` | Get Windows username |
| `winhome` | Get Windows home directory path |
| `explorer` | Open Windows Explorer |
| `clip` | Copy to Windows clipboard |
| `cmd` | Run Windows CMD command |
| `pwsh` | Run PowerShell command |
| `code-win` | Open VS Code (Windows version) |
| `notepad` | Open Windows Notepad |
| `ipconfig` | Run Windows ipconfig |
| `wsl-shutdown` | Shutdown WSL |
| `wsl-update` | Update WSL |
| `wsl-status` | Show WSL status |
| `wclip` | Copy path to Windows clipboard |

## Remote

Aliases for remote server management.

### Connection & Execution

| Alias | Description |
|-------|-------------|
| `srv.ssh` | Base SSH command with keepalive |
| `srv.ssh.via` | SSH using a jump/bastion host |
| `srv.run` | Run a command non-interactively |
| `srv.run.interactive` | Run a command interactively |
| `srv.run.parallel` | Run a command on multiple hosts |

### File Transfer

| Alias | Description |
|-------|-------------|
| `srv.scp.to` | Copy LOCAL -> REMOTE |
| `srv.scp.from` | Copy REMOTE -> LOCAL |
| `srv.scp.via` | Secure copy through a jump host |
| `srv.rsync.to` | Rsync LOCAL -> REMOTE |
| `srv.rsync.from` | Rsync REMOTE -> LOCAL |
| `srv.rsync.bwlimit` | Rsync with bandwidth limit |

### System Information

| Alias | Description |
|-------|-------------|
| `srv.info.os` | OS/Kernel/Release Info |
| `srv.info.host` | Hostname Info |
| `srv.info.uptime` | System Uptime and Load Average |
| `srv.info.cpu` | CPU Information |
| `srv.info.ram` | Memory Usage |
| `srv.info.disk` | Disk Filesystem Usage |
| `srv.info.pci` | PCI Devices |
| `srv.info.usb` | USB Devices |
| `srv.info.lsblk` | Block Devices (Disks/Partitions) |
| `srv.info.users` | Currently Logged-in Users |
| `srv.info.who` | More detailed user info and activity |
| `srv.info.last` | Show last logins |

### Process Management

| Alias | Description |
|-------|-------------|
| `srv.proc.list` | List processes |
| `srv.proc.top` | Interactive process viewer |
| `srv.proc.htop` | Improved interactive process viewer |
| `srv.proc.find` | Find process PID by name/pattern |
| `srv.proc.kill` | Send SIGTERM to process |
| `srv.proc.kill9` | Send SIGKILL to process |
| `srv.proc.pkill` | Kill processes by name (SIGTERM) |
| `srv.proc.pkill9` | Kill processes by name (SIGKILL) |

### Resource Monitoring

| Alias | Description |
|-------|-------------|
| `srv.mon.vmstat` | VM Statistics |
| `srv.mon.iostat` | Disk I/O Statistics |
| `srv.mon.iotop` | Interactive Disk I/O Monitor |
| `srv.mon.iftop` | Interactive Network Interface Traffic Monitor |
| `srv.mon.nethogs` | Per-Process Network Bandwidth Monitor |
| `srv.mon.du` | Summarize Disk Usage for path |
| `srv.mon.lsof` | Show open files by process |

### Log Management

| Alias | Description |
|-------|-------------|
| `srv.log.sys` | View system log |
| `srv.log.tail.sys` | Follow system log |
| `srv.log.boot` | View logs since last boot |
| `srv.log.service` | View logs for a specific service unit |
| `srv.log.tail.service` | Follow logs for a specific service unit |
| `srv.log.kern` | View kernel messages |
| `srv.log.dmesg` | View kernel ring buffer |
| `srv.log.grep` | Search all logs for a pattern |
| `srv.log.tail.file` | Tail a specific log file |

### Service Management

| Alias | Description |
|-------|-------------|
| `srv.svc.status` | Check service status |
| `srv.svc.start` | Start service |
| `srv.svc.stop` | Stop service |
| `srv.svc.restart` | Restart service |
| `srv.svc.reload` | Reload service configuration |
| `srv.svc.enable` | Enable service to start on boot |
| `srv.svc.disable` | Disable service from starting on boot |
| `srv.svc.is-active` | Check if service is currently running |
| `srv.svc.is-enabled` | Check if service is enabled on boot |
| `srv.svc.list` | List running service units |
| `srv.svc.list.all` | List all loaded service units |
| `srv.svc.list.units` | List all loaded units |

### Package Management

| Alias | Description |
|-------|-------------|
| `srv.apt.update` | Update APT package lists |
| `srv.apt.upgrade` | Upgrade APT packages |
| `srv.apt.install` | Install APT package |
| `srv.dnf.update` | Update DNF package lists |
| `srv.dnf.upgrade` | Upgrade DNF packages |
| `srv.dnf.install` | Install DNF package |

### User Management

| Alias | Description |
|-------|-------------|
| `srv.user.add` | Add a user (interactive) |
| `srv.user.add.basic` | Add a user (non-interactive) |
| `srv.user.del` | Delete a user |
| `srv.user.passwd` | Change a user's password |
| `srv.group.add` | Add a group |
| `srv.group.del` | Delete a group |
| `srv.user.addgroup` | Add user to a group |
| `srv.user.groups` | List groups a user belongs to |

### Container & Cloud Management

| Alias | Description |
|-------|-------------|
| `srv.docker` | Docker commands on remote host |
| `srv.docker.exec` | Interactive docker exec |
| `srv.docker.ps` | Docker container list |
| `srv.docker.stats` | Docker container stats |
| `srv.docker.logs` | View logs for a container |
| `srv.docker.logs.follow` | Follow container logs |
| `srv.kubectl` | Run kubectl commands |
| `srv.kubectl.pods` | Get pods across namespaces |
| `srv.kubectl.describe` | Describe a specific pod |
| `srv.kubectl.logs` | Get pod logs |
| `srv.kubectl.logs.follow` | Follow pod logs |
| `srv.kubectl.exec` | Execute command in a pod |
| `srv.aws` | Execute AWS CLI commands |
| `srv.az` | Execute Azure CLI commands |
| `srv.gcloud` | Execute Google Cloud CLI commands |
| `srv.terraform` | Execute Terraform commands |
| `srv.ansible` | Run Ansible playbook |

## Remote State

Aliases for infrastructure state management.

### Terraform State Management

| Alias | Description |
|-------|-------------|
| `srv.tf.state.list` | Show resources in state file |
| `srv.tf.state.show` | Show detailed state for a specific resource |
| `srv.tf.state.pull` | Download remote state to stdout |
| `srv.tf.state.mv` | Move an item in Terraform state |
| `srv.tf.state.rm` | Remove an item from Terraform state |
| `srv.tf.init` | Initialize a Terraform directory |
| `srv.tf.plan` | Show execution plan |
| `srv.tf.apply` | Apply execution plan |
| `srv.tf.destroy` | Destroy infrastructure |
| `srv.tf.workspace.list` | List workspaces |
| `srv.tf.workspace.select` | Select a workspace |
| `srv.tf.workspace.new` | Create a new workspace |

### AWS CloudFormation

| Alias | Description |
|-------|-------------|
| `srv.aws.cf.list` | List CloudFormation stacks |
| `srv.aws.cf.resources` | Describe stack resources |
| `srv.aws.cf.validate` | Validate template |
| `srv.aws.cf.deploy` | Create/update stack |
| `srv.aws.cf.delete` | Delete stack |

### Azure Resource Manager

| Alias | Description |
|-------|-------------|
| `srv.az.rg.list` | List resource groups |
| `srv.az.arm.list` | List deployments in resource group |
| `srv.az.arm.validate` | Validate template |
| `srv.az.arm.deploy` | Deploy template |
| `srv.az.arm.show` | Show deployment |

### Kubernetes State Management

| Alias | Description |
|-------|-------------|
| `srv.k8s.export` | Export all resources in namespace |
| `srv.k8s.diff` | Diff between live and git |
| `srv.k8s.apply.git` | Apply git state to cluster |

### Cross-Tool State Operations

| Alias | Description |
|-------|-------------|
| `srv.state.export` | Export state (works with tf, cf, arm, k8s) |
| `srv.state.drift` | Generate drift report |

## SSH

Aliases for SSH connections and key management.

### Connection Options

| Alias | Description |
|-------|-------------|
| `sshnp` | Connect disabling password authentication |
| `ssha` | Connect with SSH Agent Forwarding |
| `sshx` | Connect with X11 Forwarding |
| `sshv` | Connect with verbose output (Level 1) |
| `sshvv` | Connect with very verbose output (Level 2) |
| `sshvvv` | Connect with debug level verbose output (Level 3) |
| `ssht` | Connect forcing pseudo-terminal allocation |

### Port Forwarding

| Alias | Description |
|-------|-------------|
| `sshfl` | Setup Local Port Forwarding |
| `sshfr` | Setup Remote Port Forwarding |
| `sshdyn` | Setup Dynamic Port Forwarding / SOCKS Proxy |

### Key Management

| Alias | Description |
|-------|-------------|
| `sshkey` | Generate a new Ed25519 SSH key pair |
| `sshkeyrsa` | Generate a new RSA 4096 SSH key pair |
| `sshcopy` | Copy your public SSH key to a remote host |
| `sshfingerprint` | Show the fingerprint of a specific public key file |
| `sshfingerprintprv` | Show the fingerprint of a specific private key file |

### SSH Agent Management

| Alias | Description |
|-------|-------------|
| `sshadd` | Add an SSH key to the agent |
| `sshaddls` | List keys currently loaded in the SSH agent |
| `sshaddfls` | List keys with full public key fingerprint |
| `sshadddelkey` | Delete a specific key from the SSH agent |
| `sshadddelall` | Delete ALL keys from the SSH agent |
| `sshaddt` | Add key with a specific lifetime |

### Connection Multiplexing

| Alias | Description |
|-------|-------------|
| `sshchk` | Check the status of a ControlMaster connection |
| `sshexit` | Request exit of a ControlMaster connection |