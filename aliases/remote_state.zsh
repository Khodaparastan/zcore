# ============================================
# Remote Infrastructure State Management Aliases
# ============================================
# Aliases for managing infrastructure state across clouds and tools
# Designed to complement remote.zsh for DevOps and SRE workflows

# ============================================
# Helper Functions
# ============================================

# --- Core Remote State Execution Function ---
# Usage: _srv_state_exec <user@host> <command_string...>
_srv_state_exec() {
    local target="$1"
    shift # Remove target from arguments
    local cmd_string="$*" # Remaining args form the command string

    if [ -z "$target" ] || [ -z "$cmd_string" ]; then
        echo "Usage Error: _srv_state_exec <user@host> <command_string>" >&2
        return 1
    fi

    # Check if jump host is defined (format: target=user@jumphost:user@destination)
    if [[ "$target" == *":"* ]]; then
        local jumphost="${target%%:*}"
        local destination="${target#*:}"
        echo "Using jump host: $jumphost to reach $destination" >&2
        # Use ProxyJump for SSH through a bastion/jump host
        ssh $SSH_OPTS -J "$jumphost" -T "$destination" -- "$cmd_string"
    else
        # Direct execution
        ssh $SSH_OPTS -T "$target" -- "$cmd_string"
    fi
    return $?
}

# --- Interactive Remote State Execution Function ---
# Usage: _srv_state_exec_interactive <user@host> <command_string...>
_srv_state_exec_interactive() {
    local target="$1"
    shift
    local cmd_string="$*"

    if [ -z "$target" ] || [ -z "$cmd_string" ]; then
        echo "Usage Error: _srv_state_exec_interactive <user@host> <command_string>" >&2
        return 1
    fi

    # Check if jump host is defined
    if [[ "$target" == *":"* ]]; then
        local jumphost="${target%%:*}"
        local destination="${target#*:}"
        echo "Using jump host: $jumphost to reach $destination" >&2
        ssh $SSH_OPTS -J "$jumphost" -t "$destination" -- "$cmd_string"
    else
        # Use -t for pseudo-tty allocation (interactive)
        ssh $SSH_OPTS -t "$target" -- "$cmd_string"
    fi
    return $?
}

# ============================================
# Terraform State Management (srv.tf.*)
# ============================================

# --- Terraform State List ---
# Show resources in state file
# Usage: srv.tf.state.list <user@host> [path/to/module]
alias srv.tf.state.list='_srv_remote_exec_wrapper() { path_arg=${2:+"$2"}; _srv_state_exec "$1" "cd \"$path_arg\" && terraform state list"; }; _srv_remote_exec_wrapper'

# --- Terraform State Show ---
# Show detailed state for a specific resource
# Usage: srv.tf.state.show <user@host> <resource_address> [path/to/module]
alias srv.tf.state.show='_srv_remote_exec_wrapper() { resource="$2"; path_arg=${3:+cd \"$3\" &&}; _srv_state_exec "$1" "$path_arg terraform state show \"$resource\""; }; _srv_remote_exec_wrapper'

# --- Terraform State Pull ---
# Download remote state to stdout (can redirect to file)
# Usage: srv.tf.state.pull <user@host> [path/to/module] [> state.tfstate]
alias srv.tf.state.pull='_srv_remote_exec_wrapper() { path_arg=${2:+cd \"$2\" &&}; _srv_state_exec "$1" "$path_arg terraform state pull"; }; _srv_remote_exec_wrapper'

# --- Terraform State Move ---
# Move an item in Terraform state
# Usage: srv.tf.state.mv <user@host> <source> <destination> [path/to/module]
alias srv.tf.state.mv='_srv_remote_exec_wrapper() { src="$2"; dst="$3"; path_arg=${4:+cd \"$4\" &&}; _srv_state_exec "$1" "$path_arg terraform state mv \"$src\" \"$dst\""; }; _srv_remote_exec_wrapper'

# --- Terraform State Remove ---
# Remove an item from Terraform state
# Usage: srv.tf.state.rm <user@host> <resource_address> [path/to/module]
alias srv.tf.state.rm='_srv_remote_exec_wrapper() { resource="$2"; path_arg=${3:+cd \"$3\" &&}; _srv_state_exec "$1" "$path_arg terraform state rm \"$resource\""; }; _srv_remote_exec_wrapper'

# --- Terraform Init ---
# Initialize a Terraform directory
# Usage: srv.tf.init <user@host> [path/to/module]
alias srv.tf.init='_srv_remote_exec_wrapper() { path_arg=${2:+cd \"$2\" &&}; _srv_state_exec "$1" "$path_arg terraform init"; }; _srv_remote_exec_wrapper'

# --- Terraform Plan ---
# Show execution plan
# Usage: srv.tf.plan <user@host> [path/to/module] [options]
alias srv.tf.plan='_srv_remote_exec_wrapper() { target=$1; path=${2:-.}; shift 2; _srv_state_exec "$target" "cd \"$path\" && terraform plan $*"; }; _srv_remote_exec_wrapper'

# --- Terraform Apply ---
# Apply execution plan
# Usage: srv.tf.apply <user@host> [path/to/module] [options]
alias srv.tf.apply='_srv_remote_exec_wrapper() { target=$1; path=${2:-.}; shift 2; _srv_state_exec "$target" "cd \"$path\" && terraform apply $*"; }; _srv_remote_exec_wrapper'

# --- Terraform Destroy ---
# Destroy infrastructure
# Usage: srv.tf.destroy <user@host> [path/to/module] [options]
alias srv.tf.destroy='_srv_remote_exec_wrapper() { target=$1; path=${2:-.}; shift 2; _srv_state_exec "$target" "cd \"$path\" && terraform destroy $*"; }; _srv_remote_exec_wrapper'

# --- Terraform Workspaces ---
# List workspaces
# Usage: srv.tf.workspace.list <user@host> [path/to/module]
alias srv.tf.workspace.list='_srv_remote_exec_wrapper() { path_arg=${2:+cd \"$2\" &&}; _srv_state_exec "$1" "$path_arg terraform workspace list"; }; _srv_remote_exec_wrapper'

# Select a workspace
# Usage: srv.tf.workspace.select <user@host> <workspace_name> [path/to/module]
alias srv.tf.workspace.select='_srv_remote_exec_wrapper() { ws="$2"; path_arg=${3:+cd \"$3\" &&}; _srv_state_exec "$1" "$path_arg terraform workspace select \"$ws\""; }; _srv_remote_exec_wrapper'

# Create a new workspace
# Usage: srv.tf.workspace.new <user@host> <workspace_name> [path/to/module]
alias srv.tf.workspace.new='_srv_remote_exec_wrapper() { ws="$2"; path_arg=${3:+cd \"$3\" &&}; _srv_state_exec "$1" "$path_arg terraform workspace new \"$ws\""; }; _srv_remote_exec_wrapper'

# ============================================
# AWS CloudFormation (srv.aws.cf.*)
# ============================================

# --- List CloudFormation Stacks ---
# Usage: srv.aws.cf.list <user@host>
alias srv.aws.cf.list='_srv_remote_exec_wrapper() { _srv_state_exec "$1" "aws cloudformation list-stacks --query \"StackSummaries[].{Name:StackName,Status:StackStatus,Updated:LastUpdatedTime}\" --output table"; }; _srv_remote_exec_wrapper'

# --- Describe Stack Resources ---
# Usage: srv.aws.cf.resources <user@host> <stack_name>
alias srv.aws.cf.resources='_srv_remote_exec_wrapper() { stack="$2"; _srv_state_exec "$1" "aws cloudformation describe-stack-resources --stack-name \"$stack\" --query \"StackResources[].{LogicalID:LogicalResourceId,PhysicalID:PhysicalResourceId,Type:ResourceType,Status:ResourceStatus}\" --output table"; }; _srv_remote_exec_wrapper'

# --- Validate Template ---
# Usage: srv.aws.cf.validate <user@host> <template_path>
alias srv.aws.cf.validate='_srv_remote_exec_wrapper() { template="$2"; _srv_state_exec "$1" "aws cloudformation validate-template --template-body file://\"$template\""; }; _srv_remote_exec_wrapper'

# --- Create/Update Stack ---
# Usage: srv.aws.cf.deploy <user@host> <stack_name> <template_path> [parameter_file]
alias srv.aws.cf.deploy='_srv_remote_exec_wrapper() { 
    stack="$2"; 
    template="$3"; 
    params=${4:+--parameter-overrides file://\"$4\"}; 
    _srv_state_exec "$1" "aws cloudformation deploy --stack-name \"$stack\" --template-file \"$template\" $params --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM"; 
}; _srv_remote_exec_wrapper'

# --- Delete Stack ---
# Usage: srv.aws.cf.delete <user@host> <stack_name>
alias srv.aws.cf.delete='_srv_remote_exec_wrapper() { stack="$2"; _srv_state_exec "$1" "aws cloudformation delete-stack --stack-name \"$stack\""; }; _srv_remote_exec_wrapper'

# ============================================
# Azure Resource Manager (srv.az.arm.*)
# ============================================

# --- List Resource Groups ---
# Usage: srv.az.rg.list <user@host>
alias srv.az.rg.list='_srv_remote_exec_wrapper() { _srv_state_exec "$1" "az group list --output table"; }; _srv_remote_exec_wrapper'

# --- List Deployments in Resource Group ---
# Usage: srv.az.arm.list <user@host> <resource_group>
alias srv.az.arm.list='_srv_remote_exec_wrapper() { rg="$2"; _srv_state_exec "$1" "az deployment group list --resource-group \"$rg\" --output table"; }; _srv_remote_exec_wrapper'

# --- Validate Template ---
# Usage: srv.az.arm.validate <user@host> <resource_group> <template_file> [parameters_file]
alias srv.az.arm.validate='_srv_remote_exec_wrapper() { 
    rg="$2"; 
    template="$3"; 
    params=${4:+--parameters @\"$4\"}; 
    _srv_state_exec "$1" "az deployment group validate --resource-group \"$rg\" --template-file \"$template\" $params"; 
}; _srv_remote_exec_wrapper'

# --- Deploy Template ---
# Usage: srv.az.arm.deploy <user@host> <resource_group> <deployment_name> <template_file> [parameters_file]
alias srv.az.arm.deploy='_srv_remote_exec_wrapper() { 
    rg="$2"; 
    name="$3"; 
    template="$4";
    params=${5:+--parameters @\"$5\"}; 
    _srv_state_exec "$1" "az deployment group create --resource-group \"$rg\" --name \"$name\" --template-file \"$template\" $params"; 
}; _srv_remote_exec_wrapper'

# --- Show Deployment ---
# Usage: srv.az.arm.show <user@host> <resource_group> <deployment_name>
alias srv.az.arm.show='_srv_remote_exec_wrapper() { rg="$2"; name="$3"; _srv_state_exec "$1" "az deployment group show --resource-group \"$rg\" --name \"$name\" --output json"; }; _srv_remote_exec_wrapper'

# ============================================
# Kubernetes State Management (srv.k8s.*)
# ============================================

# --- Export All Resources in Namespace ---
# Usage: srv.k8s.export <user@host> <namespace> [output_dir]
alias srv.k8s.export='_srv_remote_exec_wrapper() { 
    ns="$2"; 
    outdir="${3:-k8s-export-$ns}"; 
    _srv_state_exec "$1" "
      mkdir -p \"$outdir\" && 
      for resource in \$(kubectl api-resources --namespaced=true --verbs=list -o name); do
        kubectl get -n \"$ns\" \"\$resource\" -o yaml > \"$outdir/\$resource.yaml\" 2>/dev/null || true
      done && 
      echo \"Exported resources to $outdir\""; 
}; _srv_remote_exec_wrapper'

# --- Diff Between Live and Git ---
# Usage: srv.k8s.diff <user@host> <namespace> <git_dir> [kustomize]
alias srv.k8s.diff='_srv_remote_exec_wrapper() { 
    ns="$2"; 
    gitdir="$3";
    kust=${4:+kustomize build \"$gitdir\" |};
    if [[ -z "$kust" ]]; then kust="find \"$gitdir\" -name \"*.yaml\" -exec cat {} \\; |"; fi
    _srv_state_exec "$1" "$kust kubectl diff -n \"$ns\" -f -"; 
}; _srv_remote_exec_wrapper'

# --- Apply Git State to Cluster ---
# Usage: srv.k8s.apply.git <user@host> <namespace> <git_dir> [kustomize]
alias srv.k8s.apply.git='_srv_remote_exec_wrapper() { 
    ns="$2"; 
    gitdir="$3";
    kust=${4:+kustomize build \"$gitdir\" |};
    if [[ -z "$kust" ]]; then kust="find \"$gitdir\" -name \"*.yaml\" -exec cat {} \\; |"; fi
    _srv_state_exec "$1" "$kust kubectl apply -n \"$ns\" -f -"; 
}; _srv_remote_exec_wrapper'

# ============================================
# State Migration Helpers (srv.state.*)
# ============================================

# --- Export State from Source to File ---
# Usage: srv.state.export <user@host> <type> <source_name> [output_path]
alias srv.state.export='_srv_remote_exec_wrapper() {
    type="$2";
    source="$3";
    outpath="${4:-state-export.json}";
    
    case "$type" in
      tf|terraform)
        cmd="cd \"$source\" && terraform state pull > \"$outpath\""
        ;;
      cf|cloudformation)
        cmd="aws cloudformation describe-stack-resources --stack-name \"$source\" > \"$outpath\""
        ;;
      arm|azure)
        cmd="az deployment group show --resource-group \"$source\" --name \"$source\" --output json > \"$outpath\""
        ;;
      k8s|kubernetes)
        cmd="mkdir -p \"$outpath\" && for resource in \$(kubectl api-resources --namespaced=true --verbs=list -o name); do kubectl get -n \"$source\" \"\$resource\" -o yaml > \"$outpath/\$resource.yaml\" 2>/dev/null || true; done"
        ;;
      *)
        echo "Unsupported state type: $type. Use tf, cf, arm, or k8s.";
        return 1
        ;;
    esac
    
    _srv_state_exec "$1" "$cmd";
}; _srv_remote_exec_wrapper'

# --- Get state drift report ---
# Usage: srv.state.drift <user@host> <type> <source_path>
alias srv.state.drift='_srv_remote_exec_wrapper() {
    type="$2";
    source="$3";
    
    case "$type" in
      tf|terraform)
        cmd="cd \"$source\" && terraform plan -detailed-exitcode -input=false -lock=false -out=drift.tfplan"
        ;;
      cf|cloudformation)
        cmd="aws cloudformation detect-stack-drift --stack-name \"$source\""
        ;;
      k8s|kubernetes)
        # For k8s, return all resources that have been modified outside of git
        if [[ "$source" == *":"* ]]; then
          namespace="${source%%:*}"
          gitdir="${source#*:}"
          cmd="find \"$gitdir\" -name \"*.yaml\" -exec cat {} \\; | kubectl diff -n \"$namespace\" -f -"
        else
          echo "For k8s, use format 'namespace:gitdir'"
          return 1
        fi
        ;;
      *)
        echo "Unsupported state type: $type. Use tf, cf, or k8s.";
        return 1
        ;;
    esac
    
    _srv_state_exec "$1" "$cmd";
}; _srv_remote_exec_wrapper'

# ============================================
# Help Function
# ============================================

# Help function for state management aliases
srv.state.help() {
    echo "Remote Infrastructure State Management Aliases"
    echo "=============================================="
    echo
    echo "TERRAFORM STATE MANAGEMENT:"
    echo "  srv.tf.state.list           List resources in Terraform state"
    echo "  srv.tf.state.show           Show details of a Terraform resource"
    echo "  srv.tf.state.pull           Download Terraform state to stdout"
    echo "  srv.tf.state.mv             Move item in Terraform state"
    echo "  srv.tf.state.rm             Remove item from Terraform state"
    echo "  srv.tf.init                 Initialize Terraform directory"
    echo "  srv.tf.plan                 Plan Terraform changes"
    echo "  srv.tf.apply                Apply Terraform changes"
    echo "  srv.tf.destroy              Destroy Terraform resources"
    echo "  srv.tf.workspace.list       List Terraform workspaces"
    echo "  srv.tf.workspace.select     Select a Terraform workspace"
    echo "  srv.tf.workspace.new        Create a new Terraform workspace"
    echo
    echo "AWS CLOUDFORMATION MANAGEMENT:"
    echo "  srv.aws.cf.list             List CloudFormation stacks"
    echo "  srv.aws.cf.resources        List resources in a CloudFormation stack"
    echo "  srv.aws.cf.validate         Validate a CloudFormation template"
    echo "  srv.aws.cf.deploy           Deploy a CloudFormation stack"
    echo "  srv.aws.cf.delete           Delete a CloudFormation stack"
    echo
    echo "AZURE RESOURCE MANAGER:"
    echo "  srv.az.rg.list              List Azure Resource Groups"
    echo "  srv.az.arm.list             List ARM deployments in a Resource Group"
    echo "  srv.az.arm.validate         Validate an ARM template"
    echo "  srv.az.arm.deploy           Deploy an ARM template"
    echo "  srv.az.arm.show             Show details of an ARM deployment"
    echo
    echo "KUBERNETES STATE MANAGEMENT:"
    echo "  srv.k8s.export              Export all resources in a namespace"
    echo "  srv.k8s.diff                Diff between live cluster and git resources"
    echo "  srv.k8s.apply.git           Apply resources from git to cluster"
    echo
    echo "CROSS-TOOL STATE OPERATIONS:"
    echo "  srv.state.export            Export state (works with tf, cf, arm, k8s)"
    echo "  srv.state.drift             Generate drift report (works with tf, cf, k8s)"
    echo
    echo "EXAMPLES:"
    echo "  srv.tf.state.list user@host ~/infra      # List Terraform resources"
    echo "  srv.aws.cf.resources user@host my-stack  # List CF stack resources"
    echo "  srv.k8s.export user@host production      # Export all k8s resources"
    echo "  srv.state.drift user@host tf ~/infra     # Check Terraform drift"
}