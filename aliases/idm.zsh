# ============================================
# RHEL Identity Management (IdM/FreeIPA) Aliases (idm.*)
# ============================================
# Aliases for managing Red Hat Identity Management (IdM/FreeIPA) environments
# Designed for system administrators working with RHEL environments

# --- Environment Detection ---
# Check if we're on a RHEL/CentOS/Fedora-like system, as these aliases are specific to them
_idm_is_compatible_system() {
  if [[ -f /etc/redhat-release ]] || grep -q -E 'fedora|rhel|centos|rocky|alma' /etc/os-release 2>/dev/null; then
    return 0  # Compatible system
  else
    return 1  # Not a compatible system
  fi
}

# --- Client Authentication Helpers ---
# Check if we're already authenticated to IdM and authenticate if needed
_idm_ensure_auth() {
  if ! klist -s; then
    echo "Not authenticated to IdM. Please enter your credentials:"
    kinit
    if ! klist -s; then
      echo "Authentication failed. Please check your credentials and try again."
      return 1
    fi
  fi
  return 0
}

# ============================================
# User Management Aliases
# ============================================

# --- Find a user ---
# Usage: idm.user.find [search_criteria]
alias idm.user.find='_idm_user_find() {
  _idm_ensure_auth || return 1
  if [ -z "$1" ]; then
    ipa user-find
  else
    ipa user-find "$@"
  fi
}; _idm_user_find'

# --- Show user details ---
# Usage: idm.user.show <username>
alias idm.user.show='_idm_user_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.show <username>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa user-show "$1" --all
}; _idm_user_show'

# --- Add a new user ---
# Usage: idm.user.add <username> [--first=<first_name>] [--last=<last_name>] [--password]
alias idm.user.add='_idm_user_add() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.add <username> [--first=<first_name>] [--last=<last_name>] [--password]"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa user-add "$@"
}; _idm_user_add'

# --- Modify a user ---
# Usage: idm.user.mod <username> [attributes_to_modify]
alias idm.user.mod='_idm_user_mod() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.mod <username> [attributes_to_modify]"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa user-mod "$@"
}; _idm_user_mod'

# --- Delete a user ---
# Usage: idm.user.del <username>
alias idm.user.del='_idm_user_del() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.del <username>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa user-del "$@"
}; _idm_user_del'

# --- Check if a user exists ---
# Usage: idm.user.exists <username>
alias idm.user.exists='_idm_user_exists() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.exists <username>"
    return 1
  fi
  _idm_ensure_auth || return 1
  if ipa user-show "$1" &>/dev/null; then
    echo "User $1 exists."
    return 0
  else
    echo "User $1 does not exist."
    return 1
  fi
}; _idm_user_exists'

# --- Set user password ---
# Usage: idm.user.passwd <username>
alias idm.user.passwd='_idm_user_passwd() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.passwd <username>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa passwd "$1"
}; _idm_user_passwd'

# --- Enable a user ---
# Usage: idm.user.enable <username>
alias idm.user.enable='_idm_user_enable() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.enable <username>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa user-enable "$1"
}; _idm_user_enable'

# --- Disable a user ---
# Usage: idm.user.disable <username>
alias idm.user.disable='_idm_user_disable() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.disable <username>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa user-disable "$1"
}; _idm_user_disable'

# --- Reset user password ---
# Usage: idm.user.reset <username> [--password=<new_password>]
alias idm.user.reset='_idm_user_reset() {
  if [ -z "$1" ]; then
    echo "Usage: idm.user.reset <username> [--password=<new_password>]"
    return 1
  fi
  _idm_ensure_auth || return 1
  if [[ "$2" == "--password="* ]]; then
    ipa user-mod "$1" "$2" --reset-password
  else
    ipa user-mod "$1" --reset-password
  fi
}; _idm_user_reset'

# ============================================
# Group Management Aliases
# ============================================

# --- Find a group ---
# Usage: idm.group.find [search_criteria]
alias idm.group.find='_idm_group_find() {
  _idm_ensure_auth || return 1
  if [ -z "$1" ]; then
    ipa group-find
  else
    ipa group-find "$@"
  fi
}; _idm_group_find'

# --- Show group details ---
# Usage: idm.group.show <groupname>
alias idm.group.show='_idm_group_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.group.show <groupname>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa group-show "$1" --all
}; _idm_group_show'

# --- Add a new group ---
# Usage: idm.group.add <groupname> [--desc=<description>]
alias idm.group.add='_idm_group_add() {
  if [ -z "$1" ]; then
    echo "Usage: idm.group.add <groupname> [--desc=<description>]"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa group-add "$@"
}; _idm_group_add'

# --- Delete a group ---
# Usage: idm.group.del <groupname>
alias idm.group.del='_idm_group_del() {
  if [ -z "$1" ]; then
    echo "Usage: idm.group.del <groupname>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa group-del "$@"
}; _idm_group_del'

# --- Add user to group ---
# Usage: idm.group.add-member <groupname> --users=<user1,user2,...>
alias idm.group.add-member='_idm_group_add_member() {
  if [ -z "$1" ]; then
    echo "Usage: idm.group.add-member <groupname> --users=<user1,user2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa group-add-member "$@"
}; _idm_group_add_member'

# --- Remove user from group ---
# Usage: idm.group.remove-member <groupname> --users=<user1,user2,...>
alias idm.group.remove-member='_idm_group_remove_member() {
  if [ -z "$1" ]; then
    echo "Usage: idm.group.remove-member <groupname> --users=<user1,user2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa group-remove-member "$@"
}; _idm_group_remove_member'

# --- Show members of a group ---
# Usage: idm.group.members <groupname>
alias idm.group.members='_idm_group_members() {
  if [ -z "$1" ]; then
    echo "Usage: idm.group.members <groupname>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa group-show "$1" | grep -E "Member users|Direct Member users"
}; _idm_group_members'

# ============================================
# Host Management Aliases
# ============================================

# --- Find a host ---
# Usage: idm.host.find [search_criteria]
alias idm.host.find='_idm_host_find() {
  _idm_ensure_auth || return 1
  if [ -z "$1" ]; then
    ipa host-find
  else
    ipa host-find "$@"
  fi
}; _idm_host_find'

# --- Show host details ---
# Usage: idm.host.show <hostname>
alias idm.host.show='_idm_host_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.host.show <hostname>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa host-show "$1" --all
}; _idm_host_show'

# --- Add a new host ---
# Usage: idm.host.add <hostname> [--ip-address=<ip>] [--force]
alias idm.host.add='_idm_host_add() {
  if [ -z "$1" ]; then
    echo "Usage: idm.host.add <hostname> [--ip-address=<ip>] [--force]"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa host-add "$@"
}; _idm_host_add'

# --- Delete a host ---
# Usage: idm.host.del <hostname>
alias idm.host.del='_idm_host_del() {
  if [ -z "$1" ]; then
    echo "Usage: idm.host.del <hostname>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa host-del "$@"
}; _idm_host_del'

# --- Add host to hostgroup ---
# Usage: idm.hostgroup.add-member <hostgroup> --hosts=<host1,host2,...>
alias idm.hostgroup.add-member='_idm_hostgroup_add_member() {
  if [ -z "$1" ]; then
    echo "Usage: idm.hostgroup.add-member <hostgroup> --hosts=<host1,host2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa hostgroup-add-member "$@"
}; _idm_hostgroup_add_member'

# --- Find hostgroups ---
# Usage: idm.hostgroup.find [search_criteria]
alias idm.hostgroup.find='_idm_hostgroup_find() {
  _idm_ensure_auth || return 1
  if [ -z "$1" ]; then
    ipa hostgroup-find
  else
    ipa hostgroup-find "$@"
  fi
}; _idm_hostgroup_find'

# --- Show hostgroup details ---
# Usage: idm.hostgroup.show <hostgroup_name>
alias idm.hostgroup.show='_idm_hostgroup_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.hostgroup.show <hostgroup_name>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa hostgroup-show "$1" --all
}; _idm_hostgroup_show'

# ============================================
# Service Management Aliases
# ============================================

# --- Find a service ---
# Usage: idm.service.find [search_criteria]
alias idm.service.find='_idm_service_find() {
  _idm_ensure_auth || return 1
  if [ -z "$1" ]; then
    ipa service-find
  else
    ipa service-find "$@"
  fi
}; _idm_service_find'

# --- Show service details ---
# Usage: idm.service.show <service_principal>
alias idm.service.show='_idm_service_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.service.show <service_principal>"
    echo "Example: idm.service.show HTTP/server.example.com"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa service-show "$1" --all
}; _idm_service_show'

# --- Add a new service ---
# Usage: idm.service.add <service_principal>
alias idm.service.add='_idm_service_add() {
  if [ -z "$1" ]; then
    echo "Usage: idm.service.add <service_principal>"
    echo "Example: idm.service.add HTTP/server.example.com"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa service-add "$@"
}; _idm_service_add'

# --- Delete a service ---
# Usage: idm.service.del <service_principal>
alias idm.service.del='_idm_service_del() {
  if [ -z "$1" ]; then
    echo "Usage: idm.service.del <service_principal>"
    echo "Example: idm.service.del HTTP/server.example.com"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa service-del "$@"
}; _idm_service_del'

# ============================================
# DNS Management Aliases
# ============================================

# --- Find DNS records ---
# Usage: idm.dns.find <zone> [search_criteria]
alias idm.dns.find='_idm_dns_find() {
  if [ -z "$1" ]; then
    echo "Usage: idm.dns.find <zone> [search_criteria]"
    echo "Example: idm.dns.find example.com"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa dnsrecord-find "$@"
}; _idm_dns_find'

# --- Show DNS record ---
# Usage: idm.dns.show <zone> <record_name>
alias idm.dns.show='_idm_dns_show() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: idm.dns.show <zone> <record_name>"
    echo "Example: idm.dns.show example.com www"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa dnsrecord-show "$1" "$2"
}; _idm_dns_show'

# --- Add DNS record ---
# Usage: idm.dns.add <zone> <record_name> [--a-rec=<ip>] [--aaaa-rec=<ipv6>] [--mx-rec=<priority> <server>]
alias idm.dns.add='_idm_dns_add() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: idm.dns.add <zone> <record_name> [--a-rec=<ip>] [--aaaa-rec=<ipv6>] [--mx-rec=<priority> <server>]"
    echo "Example: idm.dns.add example.com www --a-rec=192.168.1.10"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa dnsrecord-add "$@"
}; _idm_dns_add'

# --- Delete DNS record ---
# Usage: idm.dns.del <zone> <record_name>
alias idm.dns.del='_idm_dns_del() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: idm.dns.del <zone> <record_name>"
    echo "Example: idm.dns.del example.com www"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa dnsrecord-del "$@"
}; _idm_dns_del'

# --- Find DNS zones ---
# Usage: idm.dnszone.find [search_criteria]
alias idm.dnszone.find='_idm_dnszone_find() {
  _idm_ensure_auth || return 1
  ipa dnszone-find "$@"
}; _idm_dnszone_find'

# --- Add DNS zone ---
# Usage: idm.dnszone.add <zone_name> [--name-server=<ns>] [--admin-email=<email>]
alias idm.dnszone.add='_idm_dnszone_add() {
  if [ -z "$1" ]; then
    echo "Usage: idm.dnszone.add <zone_name> [--name-server=<ns>] [--admin-email=<email>]"
    echo "Example: idm.dnszone.add example.com"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa dnszone-add "$@"
}; _idm_dnszone_add'

# ============================================
# Certificate Management Aliases
# ============================================

# --- Find certificates ---
# Usage: idm.cert.find [search_criteria]
alias idm.cert.find='_idm_cert_find() {
  _idm_ensure_auth || return 1
  ipa cert-find "$@"
}; _idm_cert_find'

# --- Show certificate ---
# Usage: idm.cert.show <certificate_serial_number>
alias idm.cert.show='_idm_cert_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.cert.show <certificate_serial_number>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa cert-show "$1"
}; _idm_cert_show'

# --- Request a new certificate ---
# Usage: idm.cert.request <csr_file> [--principal=<principal>]
alias idm.cert.request='_idm_cert_request() {
  if [ -z "$1" ]; then
    echo "Usage: idm.cert.request <csr_file> [--principal=<principal>]"
    echo "Example: idm.cert.request /path/to/request.csr --principal=HTTP/server.example.com"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa cert-request "$@"
}; _idm_cert_request'

# ============================================
# HBAC (Host-Based Access Control) Aliases
# ============================================

# --- Find HBAC rules ---
# Usage: idm.hbac.find [search_criteria]
alias idm.hbac.find='_idm_hbac_find() {
  _idm_ensure_auth || return 1
  ipa hbacrule-find "$@"
}; _idm_hbac_find'

# --- Show HBAC rule ---
# Usage: idm.hbac.show <rule_name>
alias idm.hbac.show='_idm_hbac_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.hbac.show <rule_name>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa hbacrule-show "$1" --all
}; _idm_hbac_show'

# --- Add HBAC rule ---
# Usage: idm.hbac.add <rule_name> [--desc=<description>]
alias idm.hbac.add='_idm_hbac_add() {
  if [ -z "$1" ]; then
    echo "Usage: idm.hbac.add <rule_name> [--desc=<description>]"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa hbacrule-add "$@"
}; _idm_hbac_add'

# --- Add users to HBAC rule ---
# Usage: idm.hbac.add-user <rule_name> --users=<user1,user2,...>
alias idm.hbac.add-user='_idm_hbac_add_user() {
  if [ -z "$1" ]; then
    echo "Usage: idm.hbac.add-user <rule_name> --users=<user1,user2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa hbacrule-add-user "$@"
}; _idm_hbac_add_user'

# --- Add hosts to HBAC rule ---
# Usage: idm.hbac.add-host <rule_name> --hosts=<host1,host2,...>
alias idm.hbac.add-host='_idm_hbac_add_host() {
  if [ -z "$1" ]; then
    echo "Usage: idm.hbac.add-host <rule_name> --hosts=<host1,host2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa hbacrule-add-host "$@"
}; _idm_hbac_add_host'

# --- Add services to HBAC rule ---
# Usage: idm.hbac.add-service <rule_name> --hbacsvcs=<svc1,svc2,...>
alias idm.hbac.add-service='_idm_hbac_add_service() {
  if [ -z "$1" ]; then
    echo "Usage: idm.hbac.add-service <rule_name> --hbacsvcs=<svc1,svc2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa hbacrule-add-service "$@"
}; _idm_hbac_add_service'

# ============================================
# Sudo Rules Aliases
# ============================================

# --- Find sudo rules ---
# Usage: idm.sudo.find [search_criteria]
alias idm.sudo.find='_idm_sudo_find() {
  _idm_ensure_auth || return 1
  ipa sudorule-find "$@"
}; _idm_sudo_find'

# --- Show sudo rule ---
# Usage: idm.sudo.show <rule_name>
alias idm.sudo.show='_idm_sudo_show() {
  if [ -z "$1" ]; then
    echo "Usage: idm.sudo.show <rule_name>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa sudorule-show "$1" --all
}; _idm_sudo_show'

# --- Add sudo rule ---
# Usage: idm.sudo.add <rule_name> [--desc=<description>]
alias idm.sudo.add='_idm_sudo_add() {
  if [ -z "$1" ]; then
    echo "Usage: idm.sudo.add <rule_name> [--desc=<description>]"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa sudorule-add "$@"
}; _idm_sudo_add'

# --- Add users to sudo rule ---
# Usage: idm.sudo.add-user <rule_name> --users=<user1,user2,...>
alias idm.sudo.add-user='_idm_sudo_add_user() {
  if [ -z "$1" ]; then
    echo "Usage: idm.sudo.add-user <rule_name> --users=<user1,user2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa sudorule-add-user "$@"
}; _idm_sudo_add_user'

# --- Add hosts to sudo rule ---
# Usage: idm.sudo.add-host <rule_name> --hosts=<host1,host2,...>
alias idm.sudo.add-host='_idm_sudo_add_host() {
  if [ -z "$1" ]; then
    echo "Usage: idm.sudo.add-host <rule_name> --hosts=<host1,host2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa sudorule-add-host "$@"
}; _idm_sudo_add_host'

# --- Add commands to sudo rule ---
# Usage: idm.sudo.add-command <rule_name> --commands=<cmd1,cmd2,...>
alias idm.sudo.add-command='_idm_sudo_add_command() {
  if [ -z "$1" ]; then
    echo "Usage: idm.sudo.add-command <rule_name> --commands=<cmd1,cmd2,...>"
    return 1
  fi
  _idm_ensure_auth || return 1
  ipa sudorule-add-command "$@"
}; _idm_sudo_add_command'

# ============================================
# IdM Server Management Aliases
# ============================================

# --- Check IdM server status ---
# Usage: idm.server.status
alias idm.server.status='_idm_server_status() {
  if ! _idm_is_compatible_system; then
    echo "This command is only available on RHEL/CentOS/Fedora systems."
    return 1
  fi
  echo "==== IdM/IPA Server Status ===="
  ipactl status
}; _idm_server_status'

# --- Start IdM server ---
# Usage: idm.server.start
alias idm.server.start='_idm_server_start() {
  if ! _idm_is_compatible_system; then
    echo "This command is only available on RHEL/CentOS/Fedora systems."
    return 1
  fi
  echo "Starting IdM/IPA server..."
  sudo ipactl start
}; _idm_server_start'

# --- Stop IdM server ---
# Usage: idm.server.stop
alias idm.server.stop='_idm_server_stop() {
  if ! _idm_is_compatible_system; then
    echo "This command is only available on RHEL/CentOS/Fedora systems."
    return 1
  fi
  echo "Stopping IdM/IPA server..."
  sudo ipactl stop
}; _idm_server_stop'

# --- Restart IdM server ---
# Usage: idm.server.restart
alias idm.server.restart='_idm_server_restart() {
  if ! _idm_is_compatible_system; then
    echo "This command is only available on RHEL/CentOS/Fedora systems."
    return 1
  fi
  echo "Restarting IdM/IPA server..."
  sudo ipactl restart
}; _idm_server_restart'

# ============================================
# Kerberos Ticket Management
# ============================================

# --- List Kerberos tickets ---
# Usage: idm.ticket.list
alias idm.ticket.list='klist'

# --- Get a new Kerberos ticket ---
# Usage: idm.ticket.get [principal]
alias idm.ticket.get='_idm_ticket_get() {
  if [ -z "$1" ]; then
    kinit
  else
    kinit "$1"
  fi
}; _idm_ticket_get'

# --- Destroy Kerberos tickets ---
# Usage: idm.ticket.destroy
alias idm.ticket.destroy='kdestroy'

# ============================================
# Troubleshooting Aliases
# ============================================

# --- Check IdM client connectivity ---
# Usage: idm.check.connectivity
alias idm.check.connectivity='_idm_check_connectivity() {
  echo "==== IdM Connectivity Check ===="
  # Check if ipa command is available
  if ! command -v ipa >/dev/null 2>&1; then
    echo "ERROR: The 'ipa' command is not available. Is IdM/IPA installed?"
    return 1
  fi
  
  # Try to obtain Kerberos ticket
  echo "Checking Kerberos authentication..."
  if ! _idm_ensure_auth; then
    echo "ERROR: Could not authenticate to IdM."
    return 1
  fi
  
  # Check if we can find IdM servers via DNS SRV records
  echo "Checking DNS SRV records for IdM servers..."
  host -t SRV _ldap._tcp.$(dnsdomainname) || \
    echo "WARNING: Could not find IdM servers via DNS SRV records."
  
  # Try to perform a basic IdM operation
  echo "Testing IdM command functionality..."
  if ! ipa ping >/dev/null 2>&1; then
    echo "ERROR: Could not execute 'ipa ping'. Check network connectivity to IdM server."
    return 1
  fi
  
  echo "Basic connectivity to IdM server appears OK."
  return 0
}; _idm_check_connectivity'

# --- Check IdM replication status ---
# Usage: idm.check.replication
alias idm.check.replication='_idm_check_replication() {
  if ! _idm_is_compatible_system; then
    echo "This command is only available on RHEL/CentOS/Fedora systems."
    return 1
  fi
  if ! command -v ipa-replica-manage >/dev/null 2>&1; then
    echo "ERROR: This command requires 'ipa-replica-manage', which is only available on IdM servers."
    return 1
  fi
  echo "Checking IdM replication status..."
  sudo ipa-replica-manage list
  echo "Checking for replication errors..."
  sudo ipa-replica-manage connect --verbose
}; _idm_check_replication'

# --- Run IdM healthcheck ---
# Usage: idm.check.health
alias idm.check.health='_idm_check_health() {
  if ! _idm_is_compatible_system; then
    echo "This command is only available on RHEL/CentOS/Fedora systems."
    return 1
  fi
  
  if ! command -v ipa-healthcheck >/dev/null 2>&1; then
    echo "ERROR: This command requires 'ipa-healthcheck', which is usually available on IdM servers."
    echo "To install it: sudo dnf install ipa-healthcheck"
    return 1
  fi
  
  echo "Running IdM health check..."
  sudo ipa-healthcheck
}; _idm_check_health'

# --- Display IdM server information ---
# Usage: idm.server.info
alias idm.server.info='_idm_server_info() {
  if ! _idm_ensure_auth; then
    return 1
  fi
  echo "==== IdM Server Information ===="
  ipa config-show
}; _idm_server_info'

# --- Display IdM version information ---
# Usage: idm.version
alias idm.version='_idm_version() {
  if ! command -v rpm >/dev/null 2>&1; then
    echo "ERROR: The 'rpm' command is not available."
    return 1
  fi
  
  if rpm -q ipa-server &>/dev/null; then
    echo "==== IdM Server Version ===="
    rpm -q ipa-server
  elif rpm -q ipa-client &>/dev/null; then
    echo "==== IdM Client Version ===="
    rpm -q ipa-client
  else
    echo "ERROR: No IdM packages found. Is IdM installed?"
    return 1
  fi
}; _idm_version'

# ============================================
# Help Function
# ============================================

# Display help information about IdM aliases
idm.help() {
  echo "RHEL Identity Management (IdM/FreeIPA) Aliases"
  echo "=============================================="
  echo
  echo "USER MANAGEMENT:"
  echo "  idm.user.find            Find users"
  echo "  idm.user.show            Show user details"
  echo "  idm.user.add             Add a new user"
  echo "  idm.user.mod             Modify a user"
  echo "  idm.user.del             Delete a user"
  echo "  idm.user.exists          Check if a user exists"
  echo "  idm.user.passwd          Set user password"
  echo "  idm.user.enable          Enable a user"
  echo "  idm.user.disable         Disable a user"
  echo "  idm.user.reset           Reset user password"
  echo
  echo "GROUP MANAGEMENT:"
  echo "  idm.group.find           Find groups"
  echo "  idm.group.show           Show group details"
  echo "  idm.group.add            Add a new group"
  echo "  idm.group.del            Delete a group"
  echo "  idm.group.add-member     Add user to group"
  echo "  idm.group.remove-member  Remove user from group"
  echo "  idm.group.members        Show members of a group"
  echo
  echo "HOST MANAGEMENT:"
  echo "  idm.host.find            Find hosts"
  echo "  idm.host.show            Show host details"
  echo "  idm.host.add             Add a new host"
  echo "  idm.host.del             Delete a host"
  echo "  idm.hostgroup.find       Find hostgroups"
  echo "  idm.hostgroup.show       Show hostgroup details"
  echo "  idm.hostgroup.add-member Add host to hostgroup"
  echo
  echo "SERVICE MANAGEMENT:"
  echo "  idm.service.find         Find services"
  echo "  idm.service.show         Show service details"
  echo "  idm.service.add          Add a new service"
  echo "  idm.service.del          Delete a service"
  echo
  echo "DNS MANAGEMENT:"
  echo "  idm.dns.find             Find DNS records"
  echo "  idm.dns.show             Show DNS record"
  echo "  idm.dns.add              Add DNS record"
  echo "  idm.dns.del              Delete DNS record"
  echo "  idm.dnszone.find         Find DNS zones"
  echo "  idm.dnszone.add          Add DNS zone"
  echo
  echo "CERTIFICATE MANAGEMENT:"
  echo "  idm.cert.find            Find certificates"
  echo "  idm.cert.show            Show certificate"
  echo "  idm.cert.request         Request a new certificate"
  echo
  echo "ACCESS CONTROL:"
  echo "  idm.hbac.find            Find HBAC rules"
  echo "  idm.hbac.show            Show HBAC rule"
  echo "  idm.hbac.add             Add HBAC rule"
  echo "  idm.hbac.add-user        Add users to HBAC rule"
  echo "  idm.hbac.add-host        Add hosts to HBAC rule"
  echo "  idm.hbac.add-service     Add services to HBAC rule"
  echo "  idm.sudo.find            Find sudo rules"
  echo "  idm.sudo.show            Show sudo rule"
  echo "  idm.sudo.add             Add sudo rule"
  echo "  idm.sudo.add-user        Add users to sudo rule"
  echo "  idm.sudo.add-host        Add hosts to sudo rule"
  echo "  idm.sudo.add-command     Add commands to sudo rule"
  echo
  echo "SERVER MANAGEMENT:"
  echo "  idm.server.status        Check IdM server status"
  echo "  idm.server.start         Start IdM server"
  echo "  idm.server.stop          Stop IdM server"
  echo "  idm.server.restart       Restart IdM server"
  echo "  idm.server.info          Display IdM server information"
  echo "  idm.version              Display IdM version information"
  echo
  echo "KERBEROS TICKETS:"
  echo "  idm.ticket.list          List Kerberos tickets"
  echo "  idm.ticket.get           Get a new Kerberos ticket"
  echo "  idm.ticket.destroy       Destroy Kerberos tickets"
  echo
  echo "TROUBLESHOOTING:"
  echo "  idm.check.connectivity   Check IdM client connectivity"
  echo "  idm.check.replication    Check IdM replication status"
  echo "  idm.check.health         Run IdM healthcheck"
  echo
  echo "EXAMPLES:"
  echo "  idm.user.add user1 --first=John --last=Doe"
  echo "  idm.group.add-member admins --users=user1"
  echo "  idm.hbac.add-host developers-access --hosts=server1.example.com"
  echo "  idm.dns.add example.com www --a-rec=192.168.1.10"
}