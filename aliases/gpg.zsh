# ============================================
# GPG Aliases
# --------------------------------------------
# Key Listing & Fingerprints
# --------------------------------------------
# List public keys (short ID format) - Existing
alias gpg.list='gpg --list-keys --keyid-format SHORT'
# List public keys (long ID format)
alias gpg.list.long='gpg --list-keys --keyid-format LONG'
# List public keys with full fingerprints
alias gpg.list.fp='gpg --fingerprint'
# List secret keys (short ID format)
alias gpg.list.sec='gpg --list-secret-keys --keyid-format SHORT'
# List secret keys with full fingerprints
alias gpg.list.sec.fp='gpg --list-secret-keys --fingerprint'

# --------------------------------------------
# Key Management (Import, Export, Edit, Revoke)
# --------------------------------------------
# Import keys from a file (append FILENAME)
alias gpg.import='gpg --import'
# Export a public key (ASCII armored) (append KEYID)
alias gpg.export='gpg --armor --export'
# Export a public key (binary) (append KEYID)
alias gpg.export.bin='gpg --export'
# Edit a key (trust, add UID, expire, etc.) (append KEYID)
alias gpg.edit='gpg --edit-key'
# Generate a revocation certificate for a key (append KEYID)
# (Outputs to revocation_cert.asc by default)
alias gpg.gen.revoke='gpg --output revocation_cert.asc --gen-revoke'
# Export *secret* keys (ASCII armored) - !! Use with extreme caution !! (append KEYID)
# alias gpg.export.secret='gpg --armor --export-secret-keys'

# --------------------------------------------
# Keyserver Interaction
# --------------------------------------------
# Receive keys from a keyserver (append KEYIDs)
alias gpg.recv='gpg --recv-keys'
# Refresh keys from a keyserver (updates local keys from server)
alias gpg.refresh='gpg --refresh-keys'
# Send keys to a keyserver (append KEYIDs)
alias gpg.send='gpg --send-keys'
# Search for keys on a keyserver (append SEARCH TERM)
alias gpg.search='gpg --search-keys'

# --------------------------------------------
# Encryption
# --------------------------------------------
# Encrypt a file for recipient(s) (ASCII armored)
# (Append -r RECIPIENT [ -r NEXT_RECIPIENT... ] FILENAME)
alias gpg.encrypt='gpg --armor --encrypt'
# Encrypt and sign a file for recipient(s) (ASCII armored, uses default key for signing)
# (Append -r RECIPIENT [ -r NEXT_RECIPIENT... ] FILENAME)
alias gpg.encrypt.sign='gpg --armor --sign --encrypt'
# Encrypt file symmetrically (password-based) (ASCII armored)
# (Shorthand for --symmetric --armor) (append FILENAME)
alias gpg.encrypt.sym='gpg -ca'

# --------------------------------------------
# Decryption
# --------------------------------------------
# Decrypt a file or message (auto-detects format)
# (Append FILENAME. Add '-o OUTFILE' to direct output)
alias gpg.decrypt='gpg --decrypt'

# --------------------------------------------
# Signing (Uses default key)
# --------------------------------------------
# Create a detached signature (ASCII armored)
# (Append FILENAME. Creates FILENAME.asc)
alias gpg.sign='gpg --armor --detach-sign'
# Create a clear-signed message (human-readable + signature)
# (Append FILENAME. Creates FILENAME.asc)
alias gpg.sign.clear='gpg --clear-sign'
# Sign file with default key (non-detached, ASCII armored)
# (Append FILENAME. Creates FILENAME.asc containing signed data)
# alias gpg.sign.inline='gpg --armor --sign' # Less common for files, often clear-sign is preferred

# --------------------------------------------
# Verification
# --------------------------------------------
# Verify a signature
# (Append SIGNATURE_FILE [ORIGINAL_FILE if detached])
alias gpg.verify='gpg --verify'

# --------------------------------------------
# Help / Documentation
# --------------------------------------------
# Display help information about GPG aliases
gpg.help() {
    echo "GPG Aliases - Simplified GPG Key & Encryption Management"
    echo "==========================================================="
    echo
    echo "KEY MANAGEMENT:"
    echo "  gpg.list              List all public keys (short format)"
    echo "  gpg.list.long         List all public keys (long format)"
    echo "  gpg.list.fp           List all public keys with fingerprints"
    echo "  gpg.list.sec          List all secret keys"
    echo "  gpg.list.sec.fp       List all secret keys with fingerprints"
    echo "  gpg.gen.key           Generate a new key pair (interactive)"
    echo "  gpg.gen.key.batch     Generate a key pair with defaults (non-interactive)"
    echo "  gpg.import            Import keys from a file"
    echo "  gpg.export            Export a public key (ASCII armor)"
    echo "  gpg.edit              Edit a key (trust level, expiry, etc.)"
    echo "  gpg.gen.revoke        Generate a revocation certificate"
    echo
    echo "KEYSERVER OPERATIONS:"
    echo "  gpg.recv              Receive keys from keyserver"
    echo "  gpg.refresh           Refresh/update all keys from keyserver"
    echo "  gpg.send              Send keys to keyserver"
    echo "  gpg.search            Search for keys on keyserver"
    echo
    echo "ENCRYPTION/DECRYPTION:"
    echo "  gpg.encrypt           Encrypt a file for recipient(s)"
    echo "  gpg.encrypt.sign      Encrypt and sign a file"
    echo "  gpg.encrypt.sym       Encrypt a file with a password"
    echo "  gpg.decrypt           Decrypt a file"
    echo
    echo "SIGNING/VERIFICATION:"
    echo "  gpg.sign              Create a detached signature"
    echo "  gpg.sign.clear        Create a clear-signed message"
    echo "  gpg.verify            Verify a signature"
    echo
    echo "BACKUP/MAINTENANCE:"
    echo "  gpg.backup.keys       Create a backup of your keys"
    echo "  gpg.restore.keys      Restore keys from backup"
    echo "  gpg.check.health      Check the health of your GPG setup"
    echo
    echo "EXAMPLES:"
    echo "  gpg.gen.key                       # Create a new key interactively"
    echo "  gpg.encrypt -r user@example.com file.txt   # Encrypt for recipient"
    echo "  gpg.encrypt.sym secret.txt        # Password-encrypt a file"
    echo "  gpg.decrypt secret.txt.asc        # Decrypt a file"
    echo "  gpg.sign document.pdf             # Create detached signature"
    echo "  gpg.verify document.pdf.asc document.pdf  # Verify signature"
    echo
    echo "For more details on GPG itself, see: man gpg"
}

# --------------------------------------------
# Advanced Usage
# --------------------------------------------
# Generate a new key pair (interactive wizard)
alias gpg.gen.key='gpg --full-generate-key'
# Generate a key pair with sensible defaults non-interactively
# (Creates RSA 4096 key, valid for 2 years, with user details)
# Usage: gpg.gen.key.batch "Your Name" "your.email@example.com"
alias gpg.gen.key.batch='_gpg_gen_key_batch() { 
    local name="$1"; 
    local email="$2"; 
    local expiry="${3:-2y}";
    local passphrase_fd="${4:-0}";
    local temp_batch=$(mktemp);
    cat > "$temp_batch" <<EOF
%echo Generating key for $name <$email>
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $name
Name-Email: $email
Expire-Date: $expiry
%echo Done
EOF
    cat "$temp_batch"; # Show batch file for confirmation
    if [ "$passphrase_fd" = "0" ]; then
        gpg --batch --gen-key "$temp_batch";
    else
        gpg --batch --pinentry-mode loopback --passphrase-fd "$passphrase_fd" --gen-key "$temp_batch";
    fi
    rm "$temp_batch";
}; _gpg_gen_key_batch'
# Create a minimal backup of your keys
alias gpg.backup.keys='_gpg_backup_keys() {
    local outdir="${1:-gpg-backup-$(date +%Y%m%d)}";
    mkdir -p "$outdir";
    gpg --export --armor > "$outdir/pubkeys.asc";
    gpg --export-secret-keys --armor > "$outdir/privkeys.asc";
    gpg --export-ownertrust > "$outdir/ownertrust.txt";
    echo "Backup created in $outdir. Store securely!";
}; _gpg_backup_keys'
# Restore keys from backup (use with caution)
alias gpg.restore.keys='_gpg_restore_keys() {
    local indir="${1:?Specify backup directory}";
    if [ ! -d "$indir" ]; then echo "Directory not found: $indir"; return 1; fi
    if [ -f "$indir/pubkeys.asc" ]; then gpg --import "$indir/pubkeys.asc"; fi
    if [ -f "$indir/privkeys.asc" ]; then
        echo "WARNING: About to import private keys. Make sure you trust the source."
        read -p "Continue? [y/N] " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            gpg --import "$indir/privkeys.asc"
        fi
    fi
    if [ -f "$indir/ownertrust.txt" ]; then gpg --import-ownertrust "$indir/ownertrust.txt"; fi
}; _gpg_restore_keys'
# Check the health of your gpg setup
alias gpg.check.health='gpg --check-trustdb && gpg --list-keys && gpg --list-secret-keys && echo "GPG setup appears healthy."'