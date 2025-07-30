# ============================================
# Additional OpenSSL Aliases (ossl.*)
# --------------------------------------------
# Supplement to the main OpenSSL aliases
# Focus on advanced certificate operations, TLS analysis, and diagnostics
# ============================================

# --------------------------------------------
# Certificate Chain Operations
# --------------------------------------------
# Build a certificate chain from individual certificates (order is critical)
# (Usage: ossl.build.chain cert1.pem cert2.pem cert3.pem > chain.pem)
alias ossl.build.chain='cat'
# Extract certificates from a chain file (gives them numbered names)
# (Append -in chain.pem -out extracted)
alias ossl.extract.chain='_ossl_extract_chain() {
  local infile="$1"
  local outprefix="${2:-cert}"
  [ -z "$infile" ] && { echo "Usage: ossl.extract.chain chain.pem [outprefix]"; return 1; }
  awk -v outprefix="$outprefix" \
    "BEGIN { n=0 } 
     /-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/ { 
       if(/BEGIN/) { n++; out=outprefix n \".pem\"; } 
       print > out; 
     }" "$infile"
  echo "Extracted $(ls ${outprefix}*.pem | wc -l) certificates."
}; _ossl_extract_chain'
# Extract the first (leaf) certificate from a chain file
# (Append -in chain.pem -out leaf.pem)
alias ossl.extract.leaf='_ossl_extract_leaf() {
  local infile="$1"
  local outfile="${2:-leaf.pem}"
  [ -z "$infile" ] && { echo "Usage: ossl.extract.leaf chain.pem [leaf.pem]"; return 1; }
  awk "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/ { print; exit }" "$infile" > "$outfile"
  echo "Extracted leaf certificate to $outfile"
}; _ossl_extract_leaf'

# Verify certificate chain with custom CAfile
# Usage: ossl.verify.chain cert.pem cafile.pem
alias ossl.verify.chain='openssl verify -CAfile'
# Verify certificate chain against OS/browser root certs (if available)
# Usage: ossl.verify.system cert.pem
alias ossl.verify.system='_ossl_verify_system() {
  local cert="$1"
  local cafile=""
  
  # Try to find system CA file based on OS/distro
  if [ -f "/etc/ssl/certs/ca-certificates.crt" ]; then         # Debian/Ubuntu
    cafile="/etc/ssl/certs/ca-certificates.crt"
  elif [ -f "/etc/pki/tls/certs/ca-bundle.crt" ]; then         # RHEL/CentOS
    cafile="/etc/pki/tls/certs/ca-bundle.crt"
  elif [ -f "/etc/ssl/ca-bundle.pem" ]; then                   # SLES/openSUSE
    cafile="/etc/ssl/ca-bundle.pem"
  elif [ -f "/etc/pki/tls/cacert.pem" ]; then                  # Some older systems
    cafile="/etc/pki/tls/cacert.pem"
  elif [ -f "/usr/local/share/certs/ca-root-nss.crt" ]; then   # FreeBSD
    cafile="/usr/local/share/certs/ca-root-nss.crt"
  elif [ -f "/opt/local/share/curl/curl-ca-bundle.crt" ]; then # macOS with MacPorts
    cafile="/opt/local/share/curl/curl-ca-bundle.crt"
  elif [ -f "/usr/local/etc/openssl/cert.pem" ]; then         # macOS Homebrew
    cafile="/usr/local/etc/openssl/cert.pem"
  fi
  
  if [ -n "$cafile" ]; then
    echo "Using system CA file: $cafile"
    openssl verify -CAfile "$cafile" "$cert"
  else
    echo "No system CA file found. Please specify with ossl.verify.chain instead."
    return 1
  fi
}; _ossl_verify_system'

# --------------------------------------------
# TLS/SSL Connection Testing & Analysis
# --------------------------------------------
# Get a server's certificate (great for getting public certs)
# (Usage: ossl.get.server.cert example.com[:port] [output.pem])
alias ossl.get.server.cert='_ossl_get_server_cert() {
  local server="$1"
  local port="${server##*:}"
  if [ "$port" = "$server" ]; then
    port="443"
    server_name="$server"
  else
    server_name="${server%:*}"
  fi
  local outfile="${2:-$server_name.pem}"
  
  echo "Retrieving certificate from $server_name:$port..."
  openssl s_client -connect "$server_name:$port" -servername "$server_name" \
    -showcerts </dev/null 2>/dev/null | \
    awk "/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/ { print }" > "$outfile"
  
  echo "Certificate saved to $outfile"
  
  # Display basic certificate information
  echo "Certificate Information:"
  openssl x509 -noout -subject -issuer -dates -in "$outfile"
}; _ossl_get_server_cert'

# Test TLS connection and report cipher, protocol version, and key details
# (Usage: ossl.test.tls example.com[:port])
alias ossl.test.tls='_ossl_test_tls() {
  local server="$1"
  local port="${server##*:}"
  if [ "$port" = "$server" ]; then
    port="443"
    server_name="$server"
  else
    server_name="${server%:*}"
  fi
  
  echo "Testing TLS connection to $server_name:$port..."
  echo | openssl s_client -connect "$server_name:$port" -servername "$server_name" 2>/dev/null | \
    grep -E "subject=|issuer=|^[ ]*Protocol[ ]*:|^[ ]*Cipher[ ]*:|Verification"
}; _ossl_test_tls'

# Test server for TLSv1.3 support
# (Usage: ossl.test.tls13 example.com[:port])
alias ossl.test.tls13='_ossl_test_tls13() {
  local server="$1"
  local port="${server##*:}"
  if [ "$port" = "$server" ]; then
    port="443" 
    server_name="$server"
  else
    server_name="${server%:*}"
  fi
  
  echo "Testing TLSv1.3 support on $server_name:$port..."
  echo | openssl s_client -connect "$server_name:$port" -servername "$server_name" -tls1_3 2>&1 | \
    grep -E "Protocol[ ]*:|New|Cipher[ ]*:|Verification|error|SSL routines"
}; _ossl_test_tls13'

# Get server cipher preference order
# (Usage: ossl.server.ciphers example.com[:port])
alias ossl.server.ciphers='_ossl_server_ciphers() {
  local server="$1"
  local port="${server##*:}"
  if [ "$port" = "$server" ]; then
    port="443"
    server_name="$server"
  else
    server_name="${server%:*}"
  fi
  
  echo "Retrieving cipher preference from $server_name:$port..."
  for v in "-tls1_2" "-tls1_3"; do
    echo -e "\n[Testing $v]"
    echo | openssl s_client -connect "$server_name:$port" -servername "$server_name" $v -cipher "ALL:COMPLEMENTOFALL" 2>/dev/null | \
      grep -E "^[ ]*Protocol[ ]*:|^[ ]*Cipher[ ]*:|No cipher|handshake failure"
  done
}; _ossl_server_ciphers'

# --------------------------------------------
# Extended Certificate Information
# --------------------------------------------
# Check certificate expiration (Days remaining)
# (Usage: ossl.check.expiry certificate.pem)
alias ossl.check.expiry='_ossl_check_expiry() {
  local cert="$1"
  local now=$(date +%s)
  local end_date=$(openssl x509 -noout -enddate -in "$cert" 2>/dev/null | cut -d= -f2)
  
  if [ -z "$end_date" ]; then
    echo "Error: Could not get expiration date from $cert"
    return 1
  fi
  
  # Convert date formats depending on OS
  if date -d "TMZ" >/dev/null 2>&1; then  # GNU date (Linux)
    local end_epoch=$(date -d "$end_date" +%s)
  else  # BSD date (macOS, FreeBSD)
    # Convert OpenSSL date (MMM DD HH:MM:SS YYYY GMT) to BSD date input
    local end_epoch=$(date -j -f "%b %d %H:%M:%S %Y %Z" "$end_date" +%s 2>/dev/null)
    if [ $? -ne 0 ]; then
      echo "Error: Could not parse date. Try GNU date utility."
      return 1
    fi
  fi
  
  local diff_secs=$((end_epoch - now))
  local diff_days=$((diff_secs / 86400))
  
  echo "$cert expires in $diff_days days ($end_date)"
  if [ $diff_days -lt 30 ]; then
    echo "WARNING: Certificate expires in less than 30 days!"
  fi
}; _ossl_check_expiry'

# Show certificate SAN (Subject Alternative Names) entries
# (Usage: ossl.view.cert.sans certificate.pem)
alias ossl.view.cert.sans='openssl x509 -noout -text -in | grep -A1 "Subject Alternative Name"'

# Show certificate's Signature Algorithm
# (Usage: ossl.view.cert.sigalg certificate.pem)
alias ossl.view.cert.sigalg='openssl x509 -noout -text -in | grep "Signature Algorithm"'

# Extract public key from certificate in PEM format
# (Usage: ossl.extract.pubkey certificate.pem output.key)
alias ossl.extract.pubkey='_ossl_extract_pubkey() {
  local cert="$1"
  local outfile="${2:-${cert%.pem}.pubkey.pem}"
  
  openssl x509 -noout -pubkey -in "$cert" > "$outfile"
  echo "Public key extracted to $outfile"
}; _ossl_extract_pubkey'

# --------------------------------------------
# Function to compare certificate details
# --------------------------------------------
# Compare two certificates (expiry dates, issuer, subject, etc.)
# (Usage: ossl.compare.certs cert1.pem cert2.pem)
alias ossl.compare.certs='_ossl_compare_certs() {
  local cert1="$1"
  local cert2="$2"
  
  if [ ! -f "$cert1" ] || [ ! -f "$cert2" ]; then
    echo "Usage: ossl.compare.certs cert1.pem cert2.pem"
    return 1
  fi
  
  echo "Comparing certificates:"
  echo "======================="
  
  # Extract and compare fields
  for field in subject issuer startdate enddate serial fingerprint; do
    echo -e "\n[$field]"
    cert1_val=$(openssl x509 -noout -$field -in "$cert1" 2>/dev/null)
    cert2_val=$(openssl x509 -noout -$field -in "$cert2" 2>/dev/null)
    
    echo "Cert1: $cert1_val"
    echo "Cert2: $cert2_val"
    
    if [ "$cert1_val" = "$cert2_val" ]; then
      echo "✓ Match"
    else
      echo "✗ Differ"
    fi
  done
  
  # Compare public key modulus (to see if they share the same key)
  cert1_mod=$(openssl x509 -noout -modulus -in "$cert1" 2>/dev/null)
  cert2_mod=$(openssl x509 -noout -modulus -in "$cert2" 2>/dev/null)
  
  echo -e "\n[Public Key]"
  if [ "$cert1_mod" = "$cert2_mod" ]; then
    echo "✓ Same public key"
  else
    echo "✗ Different public keys"
  fi
}; _ossl_compare_certs'

# --------------------------------------------
# Password, Key, and CSR Operations
# --------------------------------------------
# Generate a strong random password (default: 32 chars)
# (Usage: ossl.gen.password [length])
alias ossl.gen.password='_ossl_gen_password() {
  length=${1:-32}
  openssl rand -base64 $(($length * 3 / 4)) | head -c $length
}; _ossl_gen_password'

# Change passphrase on a private key
# (Usage: ossl.change.passphrase private_key.pem)
alias ossl.change.passphrase='_ossl_change_passphrase() {
  local inkey="$1"
  local outkey="${2:-${inkey}}"
  
  if [ -z "$inkey" ]; then
    echo "Usage: ossl.change.passphrase private_key.pem [output_key.pem]"
    return 1
  fi
  
  # Backup the key if needed
  if [ "$inkey" = "$outkey" ]; then
    cp "$inkey" "${inkey}.bak"
    echo "Original key backed up to ${inkey}.bak"
  fi
  
  openssl pkey -in "$inkey" -out "$outkey"
  echo "Passphrase changed for key: $outkey"
}; _ossl_change_passphrase'

# Create a non-interactive CSR with SAN from config file
# Requires a config file - see help for example
# (Usage: ossl.gen.csr.conf private_key.pem csr_config.cnf output.csr)
alias ossl.gen.csr.conf='_ossl_gen_csr_conf() {
  local key="$1"
  local conf="$2"
  local csr="${3:-${key%.pem}.csr}"
  
  if [ -z "$key" ] || [ -z "$conf" ]; then
    echo "Usage: ossl.gen.csr.conf private_key.pem csr_config.cnf [output.csr]"
    echo
    echo "The config file should look like:"
    echo "----------"
    cat << EOF
[ req ]
distinguished_name = req_dn
req_extensions = v3_req
prompt = no

[ req_dn ]
CN = example.com
O = Example Org
OU = IT Department
L = New York
ST = NY
C = US

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = example.com
DNS.2 = www.example.com
DNS.3 = mail.example.com
EOF
    echo "----------"
    return 1
  fi
  
  if [ ! -f "$key" ]; then
    echo "Error: Key file not found: $key"
    return 1
  fi
  
  if [ ! -f "$conf" ]; then
    echo "Error: Config file not found: $conf"
    return 1
  fi
  
  openssl req -new -key "$key" -out "$csr" -config "$conf"
  echo "CSR generated: $csr"
  echo
  echo "CSR contents:"
  openssl req -in "$csr" -noout -text | grep -E "Subject:|DNS:"
}; _ossl_gen_csr_conf'

# Help function for openssl additions
ossl.additions.help() {
    echo "Additional OpenSSL Aliases - Supplement to the main openssl.zsh"
    echo "================================================================"
    echo
    echo "CERTIFICATE CHAIN OPERATIONS:"
    echo "  ossl.build.chain           Combine certificates into chain file"
    echo "  ossl.extract.chain         Extract certs from chain file"
    echo "  ossl.extract.leaf          Extract just leaf cert from chain"
    echo "  ossl.verify.chain          Verify cert against CA file"
    echo "  ossl.verify.system         Verify against system CA store"
    echo
    echo "TLS/SSL CONNECTION TESTING:"
    echo "  ossl.get.server.cert       Get certificate from remote server"
    echo "  ossl.test.tls              Test TLS connection details"
    echo "  ossl.test.tls13            Test for TLSv1.3 support"
    echo "  ossl.server.ciphers        Get server cipher preference"
    echo
    echo "EXTENDED CERTIFICATE INFO:"
    echo "  ossl.check.expiry          Check days until certificate expires"
    echo "  ossl.view.cert.sans        Show Subject Alternative Names"
    echo "  ossl.view.cert.sigalg      Show certificate signature algorithm"
    echo "  ossl.extract.pubkey        Extract public key from certificate"
    echo "  ossl.compare.certs         Compare two certificates"
    echo
    echo "PASSWORD, KEY & CSR OPERATIONS:"
    echo "  ossl.gen.password          Generate a strong random password"
    echo "  ossl.change.passphrase     Change passphrase on a private key"
    echo "  ossl.gen.csr.conf          Create CSR from config file (with SAN)"
    echo
    echo "EXAMPLES:"
    echo "  ossl.get.server.cert example.com cert.pem   # Get a server's certificate"
    echo "  ossl.check.expiry cert.pem                  # Check days until expiry"
    echo "  ossl.test.tls13 example.com                 # Test TLSv1.3 support"
    echo "  ossl.gen.password 16                        # Generate 16-char password"
    echo "  ossl.compare.certs old.pem new.pem          # Compare two certs"
    echo "  ossl.extract.chain chain.pem                # Extract certs from chain"
    echo
    echo "For standard OpenSSL operations, see: ossl.help"
}