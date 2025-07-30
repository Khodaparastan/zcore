# ============================================
# Ansible Aliases (ansible.*)
# ============================================
# Comprehensive aliases for Ansible operations, playbooks, inventory management, etc.
# Designed for system administrators and DevOps professionals

# ============================================
# Helper Functions
# ============================================

# Check if Ansible is installed
_ansible_check_installed() {
  if ! command -v ansible &> /dev/null; then
    echo "ERROR: Ansible is not installed. Please install Ansible first."
    return 1
  fi
  return 0
}

# Check if Ansible Galaxy CLI is installed
_ansible_galaxy_check_installed() {
  if ! command -v ansible-galaxy &> /dev/null; then
    echo "ERROR: ansible-galaxy is not installed. Please install Ansible first."
    return 1
  fi
  return 0
}

# Build common options for Ansible commands
_ansible_common_opts() {
  local opts=""
  
  # If ANSIBLE_INVENTORY is set, use it
  if [[ -n "$ANSIBLE_INVENTORY" ]]; then
    opts="$opts -i $ANSIBLE_INVENTORY"
  fi
  
  # If ANSIBLE_CONFIG is set and the file exists, use it
  if [[ -n "$ANSIBLE_CONFIG" && -f "$ANSIBLE_CONFIG" ]]; then
    opts="$opts -e @$ANSIBLE_CONFIG"
  fi
  
  echo "$opts"
}

# ============================================
# Playbook Execution
# ============================================

# Run Ansible playbook (basic)
# Usage: ansible.play playbook.yml [options]
alias ansible.play='_ansible_play() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts "$@"
}; _ansible_play'

# Run Ansible playbook with verbose output
# Usage: ansible.play.verbose playbook.yml [options]
alias ansible.play.verbose='_ansible_play_verbose() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts -v "$@"
}; _ansible_play_verbose'

# Run Ansible playbook with very verbose output
# Usage: ansible.play.vverbose playbook.yml [options]
alias ansible.play.vverbose='_ansible_play_vverbose() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts -vv "$@"
}; _ansible_play_vverbose'

# Run Ansible playbook with debug-level verbosity
# Usage: ansible.play.debug playbook.yml [options]
alias ansible.play.debug='_ansible_play_debug() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts -vvv "$@"
}; _ansible_play_debug'

# Run Ansible playbook in check mode (dry run)
# Usage: ansible.play.check playbook.yml [options]
alias ansible.play.check='_ansible_play_check() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts --check "$@"
}; _ansible_play_check'

# Run Ansible playbook with diff output
# Usage: ansible.play.diff playbook.yml [options]
alias ansible.play.diff='_ansible_play_diff() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts --diff "$@"
}; _ansible_play_diff'

# Run Ansible playbook with both check mode and diff
# Usage: ansible.play.checkdiff playbook.yml [options]
alias ansible.play.checkdiff='_ansible_play_checkdiff() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts --check --diff "$@"
}; _ansible_play_checkdiff'

# Run Ansible playbook with syntax check only
# Usage: ansible.play.syntax playbook.yml [options]
alias ansible.play.syntax='_ansible_play_syntax() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts --syntax-check "$@"
}; _ansible_play_syntax'

# Run Ansible playbook with specific tags
# Usage: ansible.play.tags playbook.yml tag1,tag2 [options]
alias ansible.play.tags='_ansible_play_tags() {
  _ansible_check_installed || return 1
  if [ -z "$2" ]; then
    echo "Usage: ansible.play.tags playbook.yml tag1,tag2 [options]"
    return 1
  fi
  local playbook="$1"
  local tags="$2"
  shift 2
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts --tags "$tags" "$playbook" "$@"
}; _ansible_play_tags'

# Skip specific tags in Ansible playbook
# Usage: ansible.play.skip-tags playbook.yml tag1,tag2 [options]
alias ansible.play.skip-tags='_ansible_play_skip_tags() {
  _ansible_check_installed || return 1
  if [ -z "$2" ]; then
    echo "Usage: ansible.play.skip-tags playbook.yml tag1,tag2 [options]"
    return 1
  fi
  local playbook="$1"
  local tags="$2"
  shift 2
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts --skip-tags "$tags" "$playbook" "$@"
}; _ansible_play_skip_tags'

# Run playbook with extra vars from file
# Usage: ansible.play.vars playbook.yml vars_file.yml [options]
alias ansible.play.vars='_ansible_play_vars() {
  _ansible_check_installed || return 1
  if [ -z "$2" ]; then
    echo "Usage: ansible.play.vars playbook.yml vars_file.yml [options]"
    return 1
  fi
  local playbook="$1"
  local vars_file="$2"
  shift 2
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts -e "@$vars_file" "$playbook" "$@"
}; _ansible_play_vars'

# Run playbook with specific limit (hosts/groups)
# Usage: ansible.play.limit playbook.yml host_or_group [options]
alias ansible.play.limit='_ansible_play_limit() {
  _ansible_check_installed || return 1
  if [ -z "$2" ]; then
    echo "Usage: ansible.play.limit playbook.yml host_or_group [options]"
    return 1
  fi
  local playbook="$1"
  local limit="$2"
  shift 2
  local opts=$(_ansible_common_opts)
  ansible-playbook $opts --limit "$limit" "$playbook" "$@"
}; _ansible_play_limit'

# ============================================
# Inventory Management
# ============================================

# List hosts in inventory
# Usage: ansible.inventory.list [pattern] [options]
alias ansible.inventory.list='_ansible_inventory_list() {
  _ansible_check_installed || return 1
  local pattern="${1:-all}"
  shift 2>/dev/null || true
  local opts=$(_ansible_common_opts)
  ansible $opts "$pattern" --list-hosts "$@"
}; _ansible_inventory_list'

# Show inventory graph
# Usage: ansible.inventory.graph [pattern] [options]
alias ansible.inventory.graph='_ansible_inventory_graph() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-inventory $opts --graph "$@"
}; _ansible_inventory_graph'

# Export inventory to YAML
# Usage: ansible.inventory.yaml [options] > inventory.yml
alias ansible.inventory.yaml='_ansible_inventory_yaml() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-inventory $opts --list --yaml "$@"
}; _ansible_inventory_yaml'

# Export inventory to JSON
# Usage: ansible.inventory.json [options] > inventory.json
alias ansible.inventory.json='_ansible_inventory_json() {
  _ansible_check_installed || return 1
  local opts=$(_ansible_common_opts)
  ansible-inventory $opts --list "$@"
}; _ansible_inventory_json'

# ============================================
# Ad-Hoc Commands
# ============================================

# Run ad-hoc Ansible command
# Usage: ansible.adhoc pattern module [args]
alias ansible.adhoc='_ansible_adhoc() {
  _ansible_check_installed || return 1
  if [ -z "$2" ]; then
    echo "Usage: ansible.adhoc pattern module [args]"
    echo "Example: ansible.adhoc all ping"
    echo "Example: ansible.adhoc webservers shell 'uptime'"
    return 1
  fi
  local pattern="$1"
  local module="$2"
  shift 2
  local opts=$(_ansible_common_opts)
  local args=""
  if [ -n "$1" ]; then
    args="-a '$@'"
  fi
  eval "ansible $opts $pattern -m $module $args"
}; _ansible_adhoc'

# Run ad-hoc shell command
# Usage: ansible.shell pattern 'command'
alias ansible.shell='_ansible_shell() {
  _ansible_check_installed || return 1
  if [ -z "$2" ]; then
    echo "Usage: ansible.shell pattern 'command'"
    echo "Example: ansible.shell all 'uptime'"
    return 1
  fi
  local pattern="$1"
  shift
  local opts=$(_ansible_common_opts)
  ansible $opts "$pattern" -m shell -a "$@"
}; _ansible_shell'

# Run ad-hoc command as root (become)
# Usage: ansible.root pattern module [args]
alias ansible.root='_ansible_root() {
  _ansible_check_installed || return 1
  if [ -z "$2" ]; then
    echo "Usage: ansible.root pattern module [args]"
    echo "Example: ansible.root all apt 'name=nginx state=latest'"
    return 1
  fi
  local pattern="$1"
  local module="$2"
  shift 2
  local opts=$(_ansible_common_opts)
  local args=""
  if [ -n "$1" ]; then
    args="-a '$@'"
  fi
  eval "ansible $opts $pattern -m $module -b $args"
}; _ansible_root'

# Check connectivity (ping)
# Usage: ansible.ping [pattern]
alias ansible.ping='_ansible_ping() {
  _ansible_check_installed || return 1
  local pattern="${1:-all}"
  shift 2>/dev/null || true
  local opts=$(_ansible_common_opts)
  ansible $opts "$pattern" -m ping "$@"
}; _ansible_ping'

# ============================================
# Ansible Galaxy
# ============================================

# Install roles from requirements file
# Usage: ansible.galaxy.install [requirements_file] [options]
alias ansible.galaxy.install='_ansible_galaxy_install() {
  _ansible_galaxy_check_installed || return 1
  local req_file="${1:-requirements.yml}"
  shift 2>/dev/null || true
  if [ ! -f "$req_file" ]; then
    echo "Error: Requirements file '$req_file' not found"
    return 1
  fi
  ansible-galaxy install -r "$req_file" "$@"
}; _ansible_galaxy_install'

# Search for a role in Ansible Galaxy
# Usage: ansible.galaxy.search role_name
alias ansible.galaxy.search='_ansible_galaxy_search() {
  _ansible_galaxy_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.galaxy.search role_name"
    return 1
  fi
  ansible-galaxy role search "$@"
}; _ansible_galaxy_search'

# Install a specific role from Ansible Galaxy
# Usage: ansible.galaxy.role.install username.role_name [version]
alias ansible.galaxy.role.install='_ansible_galaxy_role_install() {
  _ansible_galaxy_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.galaxy.role.install username.role_name [version]"
    return 1
  fi
  local role="$1"
  local version=""
  if [ -n "$2" ]; then
    version=",${2}"
  fi
  ansible-galaxy role install "${role}${version}" "$@"
}; _ansible_galaxy_role_install'

# List installed roles
# Usage: ansible.galaxy.role.list
alias ansible.galaxy.role.list='_ansible_galaxy_role_list() {
  _ansible_galaxy_check_installed || return 1
  ansible-galaxy role list "$@"
}; _ansible_galaxy_role_list'

# Install a collection from Ansible Galaxy
# Usage: ansible.galaxy.collection.install namespace.collection [version]
alias ansible.galaxy.collection.install='_ansible_galaxy_collection_install() {
  _ansible_galaxy_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.galaxy.collection.install namespace.collection [version]"
    return 1
  fi
  local collection="$1"
  local version=""
  if [ -n "$2" ]; then
    version=":${2}"
  fi
  ansible-galaxy collection install "${collection}${version}" "$@"
}; _ansible_galaxy_collection_install'

# List installed collections
# Usage: ansible.galaxy.collection.list
alias ansible.galaxy.collection.list='_ansible_galaxy_collection_list() {
  _ansible_galaxy_check_installed || return 1
  ansible-galaxy collection list "$@"
}; _ansible_galaxy_collection_list'

# ============================================
# Ansible Vault
# ============================================

# Create a new encrypted file
# Usage: ansible.vault.create file.yml
alias ansible.vault.create='_ansible_vault_create() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.vault.create file.yml"
    return 1
  fi
  ansible-vault create "$@"
}; _ansible_vault_create'

# Edit an encrypted file
# Usage: ansible.vault.edit file.yml
alias ansible.vault.edit='_ansible_vault_edit() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.vault.edit file.yml"
    return 1
  fi
  ansible-vault edit "$@"
}; _ansible_vault_edit'

# Encrypt an existing file
# Usage: ansible.vault.encrypt file.yml
alias ansible.vault.encrypt='_ansible_vault_encrypt() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.vault.encrypt file.yml"
    return 1
  fi
  ansible-vault encrypt "$@"
}; _ansible_vault_encrypt'

# Decrypt a file
# Usage: ansible.vault.decrypt file.yml
alias ansible.vault.decrypt='_ansible_vault_decrypt() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.vault.decrypt file.yml"
    return 1
  fi
  ansible-vault decrypt "$@"
}; _ansible_vault_decrypt'

# View an encrypted file
# Usage: ansible.vault.view file.yml
alias ansible.vault.view='_ansible_vault_view() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.vault.view file.yml"
    return 1
  fi
  ansible-vault view "$@"
}; _ansible_vault_view'

# Rekey (change password) an encrypted file
# Usage: ansible.vault.rekey file.yml
alias ansible.vault.rekey='_ansible_vault_rekey() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.vault.rekey file.yml"
    return 1
  fi
  ansible-vault rekey "$@"
}; _ansible_vault_rekey'

# ============================================
# Debugging & Troubleshooting
# ============================================

# Show Ansible version
# Usage: ansible.version
alias ansible.version='_ansible_version() {
  _ansible_check_installed || return 1
  ansible --version
}; _ansible_version'

# Show Ansible configurations
# Usage: ansible.config.list
alias ansible.config.list='_ansible_config_list() {
  _ansible_check_installed || return 1
  ansible-config list "$@"
}; _ansible_config_list'

# Show current Ansible configuration
# Usage: ansible.config.view
alias ansible.config.view='_ansible_config_view() {
  _ansible_check_installed || return 1
  ansible-config view "$@"
}; _ansible_config_view'

# Dump all configuration values
# Usage: ansible.config.dump
alias ansible.config.dump='_ansible_config_dump() {
  _ansible_check_installed || return 1
  ansible-config dump "$@"
}; _ansible_config_dump'

# Lint Ansible playbook
# Usage: ansible.lint playbook.yml [options]
alias ansible.lint='_ansible_lint() {
  if ! command -v ansible-lint &> /dev/null; then
    echo "ERROR: ansible-lint is not installed. Install with: pip install ansible-lint"
    return 1
  fi
  ansible-lint "$@"
}; _ansible_lint'

# ============================================
# Documentation
# ============================================

# Show docs for a module
# Usage: ansible.doc module_name
alias ansible.doc='_ansible_doc() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.doc module_name"
    echo "Example: ansible.doc apt"
    return 1
  fi
  ansible-doc "$@"
}; _ansible_doc'

# List available modules
# Usage: ansible.doc.list [search_term]
alias ansible.doc.list='_ansible_doc_list() {
  _ansible_check_installed || return 1
  ansible-doc -l "$@" | grep "${1:-}" | less
}; _ansible_doc_list'

# Search for modules
# Usage: ansible.doc.search search_term
alias ansible.doc.search='_ansible_doc_search() {
  _ansible_check_installed || return 1
  if [ -z "$1" ]; then
    echo "Usage: ansible.doc.search search_term"
    return 1
  fi
  ansible-doc -l | grep -i "$1"
}; _ansible_doc_search'

# ============================================
# Help Function
# ============================================

# Display help for Ansible aliases
ansible.help() {
  echo "Ansible Aliases - Simplified Ansible Operations"
  echo "=============================================="
  echo
  echo "PLAYBOOK EXECUTION:"
  echo "  ansible.play                Run Ansible playbook"
  echo "  ansible.play.verbose        Run playbook with verbose output"
  echo "  ansible.play.vverbose       Run playbook with very verbose output"
  echo "  ansible.play.debug          Run playbook with debug level verbosity"
  echo "  ansible.play.check          Run playbook in check mode (dry run)"
  echo "  ansible.play.diff           Run playbook with diff output"
  echo "  ansible.play.checkdiff      Run playbook in check mode with diff"
  echo "  ansible.play.syntax         Check playbook syntax"
  echo "  ansible.play.tags           Run playbook with specific tags"
  echo "  ansible.play.skip-tags      Run playbook skipping specific tags"
  echo "  ansible.play.vars           Run playbook with extra vars from file"
  echo "  ansible.play.limit          Run playbook with specific host/group limit"
  echo
  echo "INVENTORY MANAGEMENT:"
  echo "  ansible.inventory.list      List hosts in inventory"
  echo "  ansible.inventory.graph     Show inventory graph"
  echo "  ansible.inventory.yaml      Export inventory to YAML"
  echo "  ansible.inventory.json      Export inventory to JSON"
  echo
  echo "AD-HOC COMMANDS:"
  echo "  ansible.adhoc               Run ad-hoc Ansible command"
  echo "  ansible.shell               Run ad-hoc shell command"
  echo "  ansible.root                Run ad-hoc command as root (become)"
  echo "  ansible.ping                Check connectivity (ping module)"
  echo
  echo "ANSIBLE GALAXY:"
  echo "  ansible.galaxy.install              Install roles from requirements file"
  echo "  ansible.galaxy.search               Search for a role in Ansible Galaxy"
  echo "  ansible.galaxy.role.install         Install a specific role"
  echo "  ansible.galaxy.role.list            List installed roles"
  echo "  ansible.galaxy.collection.install   Install a collection"
  echo "  ansible.galaxy.collection.list      List installed collections"
  echo
  echo "ANSIBLE VAULT:"
  echo "  ansible.vault.create        Create a new encrypted file"
  echo "  ansible.vault.edit          Edit an encrypted file"
  echo "  ansible.vault.encrypt       Encrypt an existing file"
  echo "  ansible.vault.decrypt       Decrypt a file"
  echo "  ansible.vault.view          View an encrypted file"
  echo "  ansible.vault.rekey         Change password of an encrypted file"
  echo
  echo "DEBUGGING & TROUBLESHOOTING:"
  echo "  ansible.version             Show Ansible version"
  echo "  ansible.config.list         Show Ansible configuration options"
  echo "  ansible.config.view         Show current Ansible configuration"
  echo "  ansible.config.dump         Dump all configuration values"
  echo "  ansible.lint                Lint Ansible playbook"
  echo
  echo "DOCUMENTATION:"
  echo "  ansible.doc                 Show docs for a module"
  echo "  ansible.doc.list            List available modules"
  echo "  ansible.doc.search          Search for modules"
  echo
  echo "EXAMPLES:"
  echo "  ansible.play site.yml"
  echo "  ansible.play.limit playbook.yml webservers"
  echo "  ansible.adhoc all setup"
  echo "  ansible.shell 'db_servers' 'systemctl status postgresql'"
  echo "  ansible.vault.edit group_vars/all/secrets.yml"
  echo "  ansible.galaxy.role.install geerlingguy.nginx"
}