#!/usr/bin/env zsh
source ./z.zsh || { echo "FATAL: z.zsh not found"; exit 1; }

# ==============================================================================
# 1. FRAMEWORK BOOTSTRAP & CONFIGURATION
# ==============================================================================
# Detect OS to adjust standard tools (e.g., BSD vs GNU utilities)
z::detect::platform
if (( IS_MACOS )); then
    z::log::info "Initialized pipeline for macOS environment"
elif (( IS_LINUX )); then
    z::log::info "Initialized pipeline for Linux environment"
else
    z::log::warn "Unknown platform, proceeding with caution"
fi

# Tune framework for batch processing
# We want fewer progress updates for speed, but higher logging depth for debugging complex injected functions
z::config::set progress_update_interval 5
z::config::set log_max_depth 100
z::config::set timeout_default 5

# ==============================================================================
# 2. INJECTABLE SERVICES (Strategies)
# ==============================================================================

# STRATEGY A: FAST & RISKY
# Uses raw eval, no timeouts. Fast but dangerous if input is malformed.
service::processor::fast_unsafe() {
    local file="$1"
    # This would normally be dangerous if $file contained shell metacharacters
    # Z's caller should have sanitized it, or we risk injection here.
    builtin eval "cat '$file' > /dev/null"
    return $?
}

# STRATEGY B: ROBUST & SECURE
# Uses Z's secure execution wrapper with timeout protection and pattern scanning.
service::processor::secure_robust() {
    local file="$1"
    # z::exec::run provides:
    # 1. Automatic timeout (set to 5s above)
    # 2. pipefail enforcement
    # 3. Security scanning for dangerous patterns (fork bombs, etc) in the input
    z::exec::run "grep 'ERROR' '$file' > /dev/null 2>&1 || true"
    # Simulate complex work and potential hangs
    if [[ $file == *batch_0045* ]]; then
         z::log::debug "Simulating a hung process on corrupt file: $file"
         sleep 6 # Exceeds 5s timeout to test z::exec::run resilience
    else
         sleep 0.05
    fi
}

# ==============================================================================
# 3. PIPELINE ENGINE (The Core Logic)
# ==============================================================================
# This engine doesn't know *how* to process, only *how to orchestrate*.
# It relies on Z for safety rails (interrupts, logging, UI).
orchestrate_pipeline() {
    local data_dir="$1"
    local strategy_func="$2"

    z::log::info "Starting Pipeline Engine with strategy: [${strategy_func}]"

    # 1. Safe Path Resolution (handles symlink cycles/relative paths)
    local resolved_dir
    if ! resolved_dir=$(z::path::resolve "$data_dir"); then
        z::runtime::die "Invalid data directory: $data_dir"
    fi

    # 2. Validate Injected Dependency
    if ! z::func::exists "$strategy_func"; then
         z::runtime::die "Processing strategy not found: $strategy_func"
    fi

    local -a files=("$resolved_dir"/batch_*(N))
    local total_files=${#files}
    local -i success=0 failed=0 current=0

    z::log::info "Found $total_files batches to process in $resolved_dir"

    for file in "${files[@]}"; do
        (( current++ ))

        # 3. INTERRUPT SAFETY:
        # Allows safe Ctrl+C during massive loops without leaving half-baked state.
        z::runtime::check_interrupted || return $?

        # 4. HIGH-PERFORMANCE UI:
        # The progress bar automatically throttles itself based on z::config settings
        # so it doesn't slow down the actual processing loop.
        z::ui::progress::show "$current" "$total_files" "processing batches"

        z::log::debug "Engine handing off $file to $strategy_func"

        # 5. EXECUTION:
        # Call the injected strategy.
        if z::func::call "$strategy_func" "$file"; then
            (( success++ ))
        else
            (( failed++ ))
            # Log error but continue pipeline (resilience)
            z::log::warn "Strategy failed on batch: ${file:t}"
        fi
    done

    # Clear UI artifacts before final report
    z::ui::progress::clear
    z::log::info "Pipeline Complete. Success: $success | Failed: $failed"
}

# ==============================================================================
# 4. MAIN RUNTIME
# ==============================================================================

# Setup dummy data for the demo
WORK_DIR=$(mktemp -d /tmp/z_demo.XXXXXX)
z::log::info "Generating 200 dummy batch files in $WORK_DIR..."
for i in {0001..0200}; do
    echo "data_payload_random_${RANDOM}" > "$WORK_DIR/batch_$i.dat"
done

# Trap cleanup to happen even if we Ctrl+C (leveraging Z interrupt handling)
cleanup() {
    z::log::info "Cleaning up temporary data..."
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT
# Ensure Z handles standard interrupts first
trap 'z::runtime::handle_interrupt' INT TERM

z::log::info "=== TEST 1: Running Fast/Unsafe Strategy ==="
orchestrate_pipeline "$WORK_DIR" "service::processor::fast_unsafe"

echo ""
z::log::info "=== TEST 2: Running Robust Strategy (watch for simulated timeout at item 45) ==="
# We enable debug logs here to see the inner workings of the secure executor
z::log::enable_debug
orchestrate_pipeline "$WORK_DIR" "service::processor::secure_robust"
