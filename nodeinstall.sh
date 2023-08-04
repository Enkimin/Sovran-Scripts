#!/bin/bash
#This is a script to install Bitcoin Core and Lightning.
set -e

#Global Functions.

# Install Check.
is_package_installed() {
    if dpkg -l "$1" 2>/dev/null | grep -q "^ii"; then
        return 0 # Package is installed
    else
        return 1 # Package is not installed
    fi
}
# yes/no Prompt
prompt_yes_no() {
    local question="$1"
    local default_choice="${2:-yes}"

    while true; do
        read -p "$question (y/n) [default: $default_choice]: " user_choice
        case $user_choice in
        [Yy])
            echo "yes"
            return
            ;;
        [Nn])
            echo "no"
            return
            ;;
        "")
            # If the user just presses Enter, return the default choice
            echo "$default_choice"
            return
            ;;
        *)
            echo "Invalid choice. Please enter 'y' for yes or 'n' for no."
            ;;
        esac
    done
}
# Center text
center_text() {
    local text="$1"
    local terminal_width
    terminal_width=$(tput cols)
    local padding=$(((terminal_width - ${#text}) / 2))
    printf "%*s%s%*s\n" $padding "" "$text" $padding ""
}

# Network stuff

# Checks if the TOR repository exists
is_tor_repository_installed() {
    grep -q "deb http://deb.torproject.org/torproject.org $(lsb_release -cs) main" /etc/apt/sources.list.d/tor.list
}
# Installs TOR
install_tor() {
    # Check if TOR is already installed
    if is_package_installed "tor"; then
        echo "TOR is already installed. Moving on..."
        sleep 1
    else
        # Inform the user about TOR and its installation
        echo "Getting ready to install TOR..."
        sleep 1
        # Confirm TOR installation with the user
        if [ "$(prompt_yes_no 'Do you want to install TOR?')" == "yes" ]; then
            echo "Adding the TOR repository..."
            sleep 1
            echo "deb https://deb.torproject.org/torproject.org $(lsb_release -cs) main" >>/etc/apt/sources.list.d/tor.list

            echo "Importing the TOR project's GPG key..."
            sleep 1
            wget -qO - https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor --output /etc/apt/trusted.gpg.d/tor.gpg

            echo "Updating package lists with the new repository..."
            sleep 1
            apt update

            echo "Installing TOR..."
            sleep 1
            apt install -y tor

            echo "Installing additional dependencies for TOR..."
            sleep 1
            apt install -y torsocks
            apt install -y tor-geoipdb

            echo "Adding the user 'bitcoin' to the 'debian-tor' group to allow TOR access..."
            sleep 1
            groupadd -f debian-tor # Create the group if it doesn't exist
            usermod -a -G debian-tor bitcoin

            echo "Setting correct permissions for the TOR configuration directory..."
            sleep 1
            chown -R debian-tor:debian-tor /var/lib/tor

            echo "Adding custom configurations to the torrc file..."
            sleep 1
            echo -e "ControlPort 9051\nCookieAuthentication 1\nCookieAuthFileGroupReadable 1\nLog notice stdout\nSOCKSPort 9050" >>/etc/tor/torrc

            echo "Restarting TOR for changes to take effect..."
            sleep 1
            systemctl restart tor

            echo "TOR has been successfully installed and configured."
            sleep 1
        else
            echo "TOR installation skipped."
            sleep 1
        fi
    fi
}
# Checks if the I2P repository exists
is_i2p_repository_installed() {
    grep -q "deb https://repo.i2pd.xyz $(lsb_release -cs) main" /etc/apt/sources.list.d/i2pd.list
}
# Installs I2P
install_i2p() {
    # Check if I2P is already installed
    if is_package_installed "i2p"; then
        echo "I2P is already installed."
        return
    fi

    # Inform the user about I2P and its installation
    echo "Getting ready to install I2P....."
    sleep 1

    # Confirm I2P installation with the user
    if [ "$(prompt_yes_no 'Do you want to install I2P?')" == "yes" ]; then
        echo "Adding I2P repository..."
        wget -q -O - https://repo.i2pd.xyz/.help/add_repo | sudo bash -s -

        # Check if apt-transport-https is installed and install it if not
        if ! is_package_installed "apt-transport-https"; then
            echo "Installing apt-transport-https..."
            apt install -y apt-transport-https
        else
            echo "apt-transport-https is already installed."
        fi

        echo "Updating package lists with the new repository..."
        apt update

        echo "Installing I2P..."
        sleep 1
        apt install -y i2p

        echo "Starting the I2P service..."
        systemctl start i2p

        echo "I2P has been installed. Moving on..."
        sleep 1
    else
        echo "I2P installation skipped. Moving on..."
        sleep 1
    fi
}

#Bitocin Stuff

# Installs Core's dependencies
install_bitcoin_core_dependencies() {
    echo "Installing required repositories for Bitcoin Core..."
    sleep 1

    # Check if git is installed and install it if not
    if ! is_package_installed "git"; then
        echo "Installing git..."
        apt install -y git
    else
        echo "git is already installed."
    fi

    apt install -y build-essential libtool autotools-dev automake pkg-config bsdmainutils python3 libssl-dev libevent-dev libboost-system-dev libboost-filesystem-dev libboost-test-dev libboost-thread-dev libboost-all-dev libzmq3-dev
}
# Download's and installs Bitcoin Core
download_and_install_bitcoin_core() {
    local node_folder="/home/bitcoin/node"

    # Create the node folder if it doesn't exist
    echo "Creating the node folder..."
    sleep 1
    mkdir -p "$node_folder"

    # Fetch the latest version number from the GitHub API
    echo "Fetching the latest version of Bitcoin Core..."
    sleep 1
    latest_version=$(curl -s https://api.github.com/repos/bitcoin/bitcoin/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [[ -z "$latest_version" ]]; then
        echo "Failed to fetch the latest version of Bitcoin Core. Aborting the installation."
        exit 1
    fi

    # Clone the Bitcoin Core repository from GitHub
    echo "Cloning Bitcoin Core repository..."
    sleep 1
    if ! git clone --depth 1 --branch "$latest_version" https://github.com/bitcoin/bitcoin.git "$node_folder/bitcoin-$latest_version"; then
        echo "Failed to clone the Bitcoin Core repository. Aborting the installation."
        exit 1
    fi

    # Call verify_checksum function after cloning the Bitcoin Core repository
    verify_checksum "$node_folder" "$latest_version"

    # Navigate into the Bitcoin Core directory
    echo "Entering the Bitcoin Core directory..."
    sleep 1
    cd "$node_folder/bitcoin-$latest_version" || (echo "Failed to enter the Bitcoin Core directory. Aborting the installation." && exit 1)

    # Build and install Bitcoin Core
    echo "Building Bitcoin Core. This can take a while, so go touch some grass."
    sleep 1
    ./autogen.sh
    ./configure
    make

    # Check if 'make install' was successful
    if ! make install; then
        echo "Failed to install Bitcoin Core. Aborting the installation."
        exit 1
    fi

    echo "Bitcoin Core installation completed successfully!"
    sleep 1
}
# Verifys cryptographic checksum of Bitcoin Core source code (This gets called in the download and install function)
verify_checksum() {
    local node_folder="$1"
    local latest_version="$2"
    local checksum_file="${node_folder}/bitcoin-${latest_version}/SHA256SUMS.asc"

    # Download the Bitcoin Core signature file
    echo "Downloading Bitcoin Core signature file..."
    sleep 1
    wget -q "https://bitcoincore.org/bin/bitcoin-core-${latest_version}/SHA256SUMS.asc" -P "$node_folder"

    # Import Bitcoin Core developers' signing key (if not already imported)
    echo "Importing Bitcoin Core developers' signing key..."
    sleep 1
    gpg --recv-keys 0x01EA5486DE18A882D4C2684590C8019E36C2E964

    # Verify the signature of the SHA256SUMS.asc file
    echo "Verifying the signature of the SHA256SUMS.asc file..."
    sleep 1
    gpg --verify "${checksum_file}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Signature verification of SHA256SUMS.asc failed. Aborting the installation."
        exit 1
    else
        echo "Signature verification successful!"
    fi

    # Verify the cryptographic checksum of the Bitcoin Core source code
    echo "Verifying the cryptographic checksum of the Bitcoin Core source code..."
    sleep 1
    cd "${node_folder}/bitcoin-${latest_version}"
    sha256sum -c --ignore-missing "${checksum_file}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Cryptographic checksum verification failed. Aborting the installation."
        exit 1
    else
        echo "Cryptographic checksum verification successful!"
    fi
}
# Copys Core's binary to /usr/local/bin and set proper ownership and permissions
copy_bitcoin_core_binary() {
    local node_folder="/home/bitcoin/node"
    local latest_version="$1"

    # Copy the Bitcoin Core binary to /usr/local/bin
    echo "Copying Bitcoin Core binary to /usr/local/bin..."
    sleep 1
    cp "$node_folder/bitcoin-$latest_version/src/bitcoind" /usr/local/bin
    cp "$node_folder/bitcoin-$latest_version/src/bitcoin-cli" /usr/local/bin

    # Set proper ownership and permissions
    chown root:root /usr/local/bin/bitcoind
    chown root:root /usr/local/bin/bitcoin-cli
    chmod 755 /usr/local/bin/bitcoind
    chmod 755 /usr/local/bin/bitcoin-cli

    echo "Bitcoin Core binary has been copied to /usr/local/bin and proper permissions have been set."
    sleep 1
}
# Creates Bitcoin Core conf
create_bitcoin_conf() {
    local bitcoin_conf_file="/home/bitcoin/.bitcoin/bitcoin.conf"
    local network="$1" # clearnet, tor, i2p, or both

    # Load the common bitcoin.conf template
    cat >"$bitcoin_conf_file" <<EOF
        # [Main]

        # Maintain coinstats index used by the gettxoutsetinfo RPC.
        coinstatsindex=1

        # Run in the background as a daemon and accept commands.
        daemon=1
        daemonwait=1

        # Set database cache size in megabytes; machines sync faster with a larger cache.
        dbcache=600

        # Keep the transaction memory pool below <n> megabytes.
        maxmempool=500

        # Maintain a full transaction index, used by the getrawtransaction rpc call.
        txindex=1

        # Turn off serving SPV nodes
        nopeerbloomfilters=1
        peerbloomfilters=0
        
        # Don't accept deprecated multi-sig style
        permitbaremultisig=0
        
        # Reduce the log file size on restarts
        shrinkdebuglog=1
EOF

    case "$network" in
    clearnet)
        # No additional options needed for clearnet configuration
        ;;
    tor)
        # TOR configuration
        cat <<EOF >>"$bitcoin_conf_file"
        # [Network]
        debug=tor
        onlynet=onion
        proxy=127.0.0.1:9050
EOF
        ;;
    i2p)
        # I2P configuration
        cat <<EOF >>"$bitcoin_conf_file"
        # [Network]
        debug=i2p
        onlynet=i2p
        i2psam=127.0.0.1:7656
        addnode=255fhcp6ajvftnyo7bwz3an3t4a4brhopm3bamyh2iu5r3gnr2rq.b32.i2p:0
        addnode=27yrtht5b5bzom2w5ajb27najuqvuydtzb7bavlak25wkufec5mq.b32.i2p:0
        addnode=2el6enckmfyiwbfcwsygkwksovtynzsigmyv3bzyk7j7qqahooua.b32.i2p:0
        addnode=3gocb7wc4zvbmmebktet7gujccuux4ifk3kqilnxnj5wpdpqx2hq.b32.i2p:0
        addnode=3tns2oov4tnllntotazy6umzkq4fhkco3iu5rnkxtu3pbfzxda7q.b32.i2p:0
        addnode=4fcc23wt3hyjk3csfzcdyjz5pcwg5dzhdqgma6bch2qyiakcbboa.b32.i2p:0
        addnode=4osyqeknhx5qf3a73jeimexwclmt42cju6xdp7icja4ixxguu2hq.b32.i2p:0
        addnode=4umsi4nlmgyp4rckosg4vegd2ysljvid47zu7pqsollkaszcbpqq.b32.i2p:0
        addnode=52v6uo6crlrlhzphslyiqblirux6olgsaa45ixih7sq5np4jujaa.b32.i2p:0
        addnode=6j2ezegd3e2e2x3o3pox335f5vxfthrrigkdrbgfbdjchm5h4awa.b32.i2p:0
        addnode=6n36ljyr55szci5ygidmxqer64qr24f4qmnymnbvgehz7qinxnla.b32.i2p:0
EOF
        ;;
    both)
        # Both TOR and I2P configuration
        cat <<EOF >>"$bitcoin_conf_file"
        # [Network]
        debug=tor
        debug=i2p
        onlynet=onion,i2p
        proxy=127.0.0.1:9050
        i2psam=127.0.0.1:7656
        addnode=255fhcp6ajvftnyo7bwz3an3t4a4brhopm3bamyh2iu5r3gnr2rq.b32.i2p:0
        addnode=27yrtht5b5bzom2w5ajb27najuqvuydtzb7bavlak25wkufec5mq.b32.i2p:0
        addnode=2el6enckmfyiwbfcwsygkwksovtynzsigmyv3bzyk7j7qqahooua.b32.i2p:0
        addnode=3gocb7wc4zvbmmebktet7gujccuux4ifk3kqilnxnj5wpdpqx2hq.b32.i2p:0
        addnode=3tns2oov4tnllntotazy6umzkq4fhkco3iu5rnkxtu3pbfzxda7q.b32.i2p:0
        addnode=4fcc23wt3hyjk3csfzcdyjz5pcwg5dzhdqgma6bch2qyiakcbboa.b32.i2p:0
        addnode=4osyqeknhx5qf3a73jeimexwclmt42cju6xdp7icja4ixxguu2hq.b32.i2p:0
        addnode=4umsi4nlmgyp4rckosg4vegd2ysljvid47zu7pqsollkaszcbpqq.b32.i2p:0
        addnode=52v6uo6crlrlhzphslyiqblirux6olgsaa45ixih7sq5np4jujaa.b32.i2p:0
        addnode=6j2ezegd3e2e2x3o3pox335f5vxfthrrigkdrbgfbdjchm5h4awa.b32.i2p:0
        addnode=6n36ljyr55szci5ygidmxqer64qr24f4qmnymnbvgehz7qinxnla.b32.i2p:0
EOF
        ;;
    esac
}
# Plugs Core into systemd
create_bitcoin_core_service() {

    echo "Plugging Core into systemd"
    sleep 1
    local service_file="/etc/systemd/system/bitcoind.service"

    cat <<EOF >"$service_file"
    [Unit]
    Description=Bitcoin daemon

    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=forking
    ExecStart=/usr/local/bin/bitcoind -conf=/home/bitcoin/.bitcoin/bitcoin.conf -pid=/run/bitcoind.pid

    Restart=always
    PrivateTmp=true
    TimeoutStopSec=480s
    TimeoutStartSec=480s
    StartLimitInterval=480s
    StartLimitBurst=10

    [Install]
    WantedBy=multi-user.target
EOF

    echo "Bitcoin Core systemd service unit created."

    # Reload systemd daemon to recognize the new service
    echo "Reloading systemd daemon to recognize the new service..."
    sleep 1
    systemctl daemon-reload
}
# Starts and enables Bitcoin Core
start_and_enable_bitcoin_core() {
    systemctl start bitcoind
    systemctl enable bitcoind
    echo "Bitcoin Core has been started and enabled as a systemd service."
}

# Lightning Stuff

# Function to check if Go is installed and install the latest version if not present
install_go() {
    if command -v go &>/dev/null; then
        echo "Go is already installed. Skipping installation."
    else
        echo "Go no found. Installing Go..."
        sleep 1
        # Determine the latest version of Go available
        latest_go_version=$(curl -s https://golang.org/dl/ | grep -oP 'https://golang.org/dl/go([0-9.]+).linux-amd64.tar.gz' | head -1 | grep -oP 'go([0-9.]+)')
        if [[ -z "$latest_go_version" ]]; then
            echo "Failed to fetch the latest version of Go. Aborting the installation."
            exit 1
        fi

        # Download and extract the latest version of Go
        wget -q "https://golang.org/dl/$latest_go_version.linux-amd64.tar.gz" -P /tmp
        tar -C /usr/local -xzf "/tmp/$latest_go_version.linux-amd64.tar.gz"

        # Add Go binary directory to PATH
        echo "export PATH=\$PATH:/usr/local/go/bin" >>/etc/profile
        source /etc/profile

        echo "Go installation completed successfully!"
    fi
}
# Function to install LND
install_lnd() {
    echo "Checking the latest release of LND..."
    latest_release=$(curl -s https://api.github.com/repos/lightningnetwork/lnd/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')

    echo "Cloning LND into /home/bitcoin/node/lnd..."
    git clone https://github.com/lightningnetwork/lnd /home/bitcoin/node/lnd

    cd /home/bitcoin/node/lnd

    echo "Checking out the latest release of LND (v$latest_release)..."
    git checkout "v$latest_release"

    echo "Building and installing LND..."
    make install

    echo "LND has been installed successfully."

    # Move lncli binary to /usr/local/bin for system-wide access
    echo "Moving lncli binary to /usr/local/bin..."
    sudo mv /home/bitcoin/go/bin/lncli /usr/local/bin/

    # Edit the bitcoin.conf file using cat
    echo "Editing the bitcoin.conf file..."
    cat <<EOF >>/home/bitcoin/.bitcoin/bitcoin.conf
    # [RPC]
    debug=rpc
    server=1
    rpcbind=0.0.0.0
    rpcport=8332
    rpcauth='lnd:1628299163766bdce1b3b9d321955971$dfeb5a806808e3f5f31b46bc8289c79f27f679cfd41b9df1e154ab6588e10ad7'

    # [zeromq]
    zmqpubrawblock=tcp://127.0.0.1:28332
    zmqpubrawtx=tcp://127.0.0.1:28333
EOF

    # Restart bitcoind
    echo "Restarting bitcoind..."
    sudo systemctl restart bitcoind
    echo "bitcoind has been restarted."
}
# Function to configure LND and create its data folder
configure_lnd() {
    echo "Configuring LND..."

    # Ask the user for their node name
    echo -n "Enter a name for your node: "
    read -r node_name

    # Create the LND data folder if it doesn't exist
    lnd_data_folder="/home/bitcoin/.lnd"
    mkdir -p "$lnd_data_folder"
    chown bitcoin:bitcoin "$lnd_data_folder"
    echo "LND data folder created: $lnd_data_folder"

    # Generate LND configuration file
    lnd_config_file="/home/bitcoin/.lnd/lnd.conf"
    cat <<EOF > "$lnd_config_file"
        [Application Options]
        # Allow push payments
        accept-keysend=1
        # Public network name (User-provided node name)
        alias=$node_name
        # Allow gift routes
        allow-circular-route=1
        # Reduce the cooperative close chain fee
        coop-close-target-confs=1000
        # Log levels
        debuglevel=CNCT=debug,CRTR=debug,HSWC=debug,NTFN=debug,RPCS=debug
        # Mark unpayable, unpaid invoices as deleted
        gc-canceled-invoices-on-startup=1
        gc-canceled-invoices-on-the-fly=1
        # Avoid historical graph data sync
        ignore-historical-gossip-filters=1
        # Listen (not using Tor? Remove this)
        listen=localhost
        # Set the maximum amount of commit fees in a channel
        max-channel-fee-allocation=1.0
        # Set the max timeout blocks of a payment
        max-cltv-expiry=5000
        # Allow commitment fee to rise on anchor channels
        max-commit-fee-rate-anchors=100
        # Pending channel limit
        maxpendingchannels=10
        # Min inbound channel limit
        minchansize=5000
        # gRPC socket binding
        rpclisten=0.0.0.0:10009
        restlisten=0.0.0.0:8080
        # Avoid high startup overhead
        stagger-initial-reconnect=1
        # Delete and recreate RPC TLS certificate when details change or cert expires
        tlsautorefresh=true
        # Do not include IPs in the RPC TLS certificate
        tlsdisableautofill=true

        [Bitcoin]
        # Turn on Bitcoin mode
        bitcoin.active=1
        # Set the channel confs to wait for channels
        bitcoin.defaultchanconfs=2
        # Forward fee rate in parts per million
        bitcoin.feerate=1000
        # Set bitcoin.testnet=1 or bitcoin.mainnet=1 as appropriate
        bitcoin.mainnet=1
        # Set the lower bound for HTLCs
        bitcoin.minhtlc=1
        # Set backing node, bitcoin.node=neutrino or bitcoin.node=bitcoind
        bitcoin.node=bitcoind
        # Set CLTV forwarding delta time
        bitcoin.timelockdelta=144

        [bitcoind]
        # Configuration for using Bitcoin Core backend

        # Set the password to what the auth script said
        bitcoind.rpcpass=K@iHa$$0
        # Set the username
        bitcoind.rpcuser=lnd
        # Set the ZMQ listeners
        bitcoind.zmqpubrawblock=tcp://127.0.0.1:28332
        bitcoind.zmqpubrawtx=tcp://127.0.0.1:28333

        [bolt]
        # Enable database compaction when restarting
        db.bolt.auto-compact=true
        [protocol]
        # Enable large channels support
        protocol.wumbo-channels=1

        [routerrpc]
        # Set minimum desired savings of trying a cheaper path
        routerrpc.attemptcost=10
        routerrpc.attemptcostppm=10
        # Set the number of historical routing records
        routerrpc.maxmchistory=10000
        # Set the min confidence in a path worth trying
        routerrpc.minrtprob=0.005

        [routing]
        # Remove channels from graph that have one side that hasn't made announcements
        routing.strictgraphpruning=1
EOF

    chown bitcoin:bitcoin "$lnd_config_file"
    echo "LND configuration file created: $lnd_config_file"

    # Ask the user about Tor mode and validate input
    while true; do
        read -rp "Do you want to use Tor only mode or hybrid mode? (Type 'yes' for Tor only mode, 'no' for hybrid mode): " tor_mode
        case $tor_mode in
            [Yy]es)
                echo "Enabling Tor mode in LND..."
                ;;
            [Nn]o)
                echo "LND will be configured in hybrid mode (without Tor)."
                ;;
            *)
                echo "Invalid input. Please type 'yes' for Tor only mode or 'no' for hybrid mode."
                continue
                ;;
        esac
        break
    done

    if [[ "$tor_mode" == "yes" ]]; then
        echo -n "Enter a password for LND Tor (this will be used to generate HashedControlPassword in torrc): "
        read -r tor_password

        # Set Tor configurations in LND conf file for Tor only mode
        cat <<EOF >> "$lnd_config_file"
            [tor]
            tor.active=1
            tor.v3=1
            tor.socks=127.0.0.1:9050
            tor.streamisolation=true
            tor.password=$tor_password
            tor.privatekeypath=/root/.lnd/v3_onion_private_key
EOF

        # Update the torrc file with HashedControlPassword
        tor_hashed_password=$(tor --hash-password "$tor_password")
        echo "Updating torrc file with HashedControlPassword..."
        echo "HashedControlPassword $tor_hashed_password" | sudo tee -a /etc/tor/torrc
        sudo systemctl restart tor

        echo "LND has been configured in Tor only mode."
    else
        echo -n "Enter a password for LND Tor (this will be used to generate HashedControlPassword in torrc): "
        read -r tor_password

        # Set Tor configurations in LND conf file for hybrid mode
        cat <<EOF >> "$lnd_config_file"
            [tor]
            tor.active=1
            tor.v3=1
            tor.socks=127.0.0.1:9050
            tor.streamisolation=false
            tor.password=$tor_password
            tor.privatekeypath=/root/.lnd/v3_onion_private_key
EOF

        # Update the torrc file with HashedControlPassword
        tor_hashed_password=$(tor --hash-password "$tor_password")
        echo "Updating torrc file with HashedControlPassword..."
        echo "HashedControlPassword $tor_hashed_password" | sudo tee -a /etc/tor/torrc
        sudo systemctl restart tor
    fi

    # Create the systemd service file for LND
    lnd_service_file="/etc/systemd/system/lnd.service"
    cat <<EOF | sudo tee "$lnd_service_file"
        [Unit]
        Description=LND Lightning Network Daemon
        Wants=bitcoind.service
        After=bitcoind.service
        
        [Service]
        User=bitcoin

        LimitNOFILE=65535
        ExecStart=/home/bitcoin/go/bin/lnd --configfile=/home/bitcoin/.lnd/lnd.conf
        ExecStop=/usr/local/bin/lncli stop
        SyslogIdentifier=lnd
        Restart=always
        RestartSec=30

        [Install]
        WantedBy=multi-user.target

EOF

    # Enable and start the LND service
    sudo systemctl enable lnd.service
    sudo systemctl start lnd.service
}
# Function to prompt the user to create a wallet
prompt_create_wallet() {
    echo "Now it's time to create your wallet. Please press any key to continue and create a new wallet."

    # Wait for user input to continue
    read -n 1 -s -r -p ""
    echo ""

    echo -n "Please remember the password you enter for your wallet: "
    read -s wallet_password
    echo ""

    # Run the lncli create command
    lncli create

    # Create the wallet password file
    wallet_password_file="/home/bitcoin/.lnd/wallet_password"
    echo "$wallet_password" > "$wallet_password_file"
    chown bitcoin:bitcoin "$wallet_password_file"
    chmod 400 "$wallet_password_file"
}
# Asks about Lightning, Installs golang
ask_install_lnd() {
    if [ "$(prompt_yes_no 'Core has been insatlled and configured! Install Lightning (LND)?')" == "yes" ]; then
        echo "Proceeding with Lightning (LND) installation..."
        sleep 1
        echo "Checking for and installing golang"
        install_go  # Install Go if it's not already installed
        install_lnd # Call the function to install LND
        configure_lnd # Call the function to configure LND and create its data folder
        prompt_create_wallet # Makes a wallet and adds the auto unlock file.

        echo "LND is now installed and configured."
        if [ "$(prompt_yes_no 'Do you want to install RTL?')" == "yes" ]; then
            echo "Proceeding with RTL installation..."
            # Call the function to install RTL (you can define this function)
            install_rtl
        else
            echo "Skipping RTL installation."
        fi
    else
        echo "Skipping Lightning installation."
    fi
}

# Ride the lightning dashboard stuff

# Install RTL dash (Ride The Lightning)
install_rtl() {
    echo "Checking for NPM (Node Package Manager)..."
    if ! command -v npm &>/dev/null; then
        echo "NPM not found. Installing NPM..."
        sleep 1
        sudo apt update
        sudo apt install -y npm
    else
        echo "NPM is already installed."
        sleep 1
    fi

    rtl_folder="/home/bitcoin/node/RTL"
    echo "Cloning RTL into $rtl_folder..."
    git clone https://github.com/Ride-The-Lightning/RTL.git "$rtl_folder"

    echo "Entering the RTL folder..."
    cd "$rtl_folder"

    echo "Running npm install..."
    npm install --omit=dev

    echo "RTL has been installed successfully."
    sleep 1
}

# Configure RTL and plug it into systemd
configure_rtl() {
    echo "Configuring RTL..."
    sleep 1

    # Get the computer's LAN IPv4 address
    lan_address=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)

    # Ask the user about enabling FIAT conversion
    echo "Do you want to enable FIAT conversion? (Type 'yes' for enabling FIAT conversion, 'no' otherwise):"
    read -r enable_fiat

    rtl_folder="/home/bitcoin/node/RTL"
    rtl_config_file="$rtl_folder/RTL-Config.json"

    cat <<EOF > "$rtl_config_file"
        {
        "multiPass": "password",
        "port": "3000",
        "defaultNodeIndex": 1,
        "dbDirectoryPath": "/home/bitcoin/node/RTL/data",
        "SSO": {
            "rtlSSO": 0
        },
        "nodes": [
            {
            "index": 1,
            "lnNode": "LND",
            "lnImplementation": "LND",
            "Authentication": {
                "macaroonPath": "/home/bitcoin/.lnd/data/chain/bitcoin/mainnet"
            },
            "Settings": {
                "userPersona": "OPERATOR",
                "themeMode": "NIGHT",
                "themeColor": "PURPLE",
                "channelBackupPath": "/home/bitcoin/bitcoin/node/RTL/backups",
                "bitcoindConfigPath": "/home/bitcoin/.bitcoin/bitcoin.conf",
                "logLevel": "INFO",
                "fiatConversion": "$enable_fiat",
                "unannouncedChannels": true,
                "lnServerUrl": "https://$lan_address:8080"
            }
            }
        ]
        }
EOF

    echo "RTL configuration file created: $rtl_config_file"

    # Create the data folder for RTL
    rtl_data_folder="/home/bitcoin/node/RTL/data"
    mkdir -p "$rtl_data_folder"
    chown bitcoin:bitcoin "$rtl_data_folder"
    echo "RTL data folder created: $rtl_data_folder"

    echo "RTL has been configured."

    # Create and start the systemd service for RTL
    rtl_systemd_file="/etc/systemd/system/rtl.service"
    cat <<EOF > "$rtl_systemd_file"
        [Unit]
        Description=Ride The Lightning (RTL) Bitcoin Lightning Network GUI
        After=bitcoind.service lnd.service

        [Service]
        User=bitcoin
        Group=bitcoin
        Type=simple
        ExecStart=/usr/bin/npm --prefix /home/bitcoin/node/RTL run start

        [Install]
        WantedBy=multi-user.target
EOF

    echo "Systemd service file created: $rtl_systemd_file"
    sudo systemctl enable rtl
    sudo systemctl start rtl

    echo "RTL service has been started."
    echo "You can access RTL at http://localhost:8080 or http://$lan_address:8080"
}

# Final systems check and exit. 
check_services() {
    echo "Checking if all required services are running..."
    if sudo systemctl is-active --quiet bitcoind && sudo systemctl is-active --quiet lnd && sudo systemctl is-active --quiet rtl; then
        echo "Woot! Core, LND, and RTL are all running. Welcome to your node."
        echo "You can access RTL at http://localhost:8080 or http://$lan_address:8080"
        exit 0
    else
        echo "Oops, it looks like the following service(s) are not running:"
        if ! sudo systemctl is-active --quiet bitcoind; then
            echo "bitcoind"
        fi
        if ! sudo systemctl is-active --quiet lnd; then
            echo "lnd"
        fi
        if ! sudo systemctl is-active --quiet rtl; then
            echo "rtl"
        fi
        exit 1
    fi
}

# Main script starts here

# Root Check
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Welcome ASCII art
cat <<"EOF"
!   .::::::.     ...     :::      .::.:::::::..     :::.     :::.    :::.    :::.    :::.    ...     :::::::-.  .,::::::      ::::::::::.   :::.       .,-:::::   :::  .   
!  ;;;`    `  .;;;;;;;.  ';;,   ,;;;' ;;;;``;;;;    ;;`;;    `;;;;,  `;;;    `;;;;,  `;;; .;;;;;;;.   ;;,   `';,;;;;''''       `;;;```.;;;  ;;`;;    ,;;;'````'   ;;; .;;,.
!  '[==/[[[[,,[[     \[[, \[[  .[[/    [[[,/[[['   ,[[ '[[,    [[[[[. '[[      [[[[[. '[[,[[     \[[, `[[     [[ [[cccc         `]]nnn]]'  ,[[ '[[,  [[[          [[[[[/'  
!    '''    $$$$,     $$$  Y$c.$$"     $$$$$$c    c$$$cc$$$c   $$$ "Y$c$$      $$$ "Y$c$$$$$,     $$$  $$,    $$ $$""""          $$$""    c$$$cc$$$c $$$         _$$$$,    
!   88b    dP"888,_ _,88P   Y88P       888b "88bo, 888   888,  888    Y88      888    Y88"888,_ _,88P  888_,o8P' 888oo,__        888o      888   888,`88bo,__,o, "888"88o, 
!    "YMmMY"   "YMMMMMP"     MP        MMMM   "W"  YMM   ""`   MMM     YM      MMM     YM  "YMMMMMP"   MMMMP"`   """"YUMMM       YMMMb     YMM   ""`   "YUMMMMMP" MMM "MMP"
EOF

echo
center_text "Thanks for using Enki's Bitcoin Core + lightning install script."
center_text "This script will walk you through installing Bitcoin Core, LND, RTL, TOR, and I2P on your machine."
center_text "To continue, hit any key."
read -n 1 -s -r -p ""
echo

# Check if the user 'bitcoin' already exists
if id "bitcoin" &>/dev/null; then
    echo "User 'bitcoin' already exists. Skipping user creation..."
else
    # Create a new user named "bitcoin" and set the password
    echo "Creating a user called bitcoin..."
    sleep 1
    adduser --disabled-password --gecos "" bitcoin
    echo "Please set the password for the 'bitcoin' user. You'll need this if you want to log into the user."
    passwd bitcoin
fi

# Ensure that /home/bitcoin directory exists and set proper permissions
bitcoin_home="/home/bitcoin"
if [ ! -d "$bitcoin_home" ]; then
    echo "Creating /home/bitcoin directory..."
    mkdir -p "$bitcoin_home"
fi

# Set the appropriate ownership and permissions for the /home/bitcoin directory
echo "Setting ownership and permissions for /home/bitcoin..."
chown -R bitcoin:bitcoin "$bitcoin_home"
chmod 700 "$bitcoin_home"

# Prompt the user if they want to install TOR
if [ "$(prompt_yes_no 'Do you want to install TOR?')" == "yes" ]; then
    install_tor
else
    echo "TOR installation skipped."
fi

# Prompt the user if they want to install I2P
if [ "$(prompt_yes_no 'Do you want to install I2P?')" == "yes" ]; then
    install_i2p
else
    echo "I2P installation skipped. Moving on..."
fi

# Check if the Bitcoin Core binary is already installed in /usr/local/bin
if command -v bitcoind &>/dev/null; then
    echo "Bitcoin Core is already installed. Skipping installation..."
    echo "Moving on to Config..."
    sleep 1
else
    # Install required repositories for Bitcoin Core
    install_bitcoin_core_dependencies

    # Download and install Bitcoin Core
    download_and_install_bitcoin_core

    # Copy Bitcoin Core binary to /usr/local/bin and set proper ownership and permissions
    copy_bitcoin_core_binary "$latest_version"
fi

# Determine if TOR and I2P are installed and set the variables accordingly
use_tor="no"
use_i2p="no"

if command -v tor &>/dev/null; then
    use_tor="yes"
fi

if command -v i2pd &>/dev/null; then
    use_i2p="yes"
fi

# Prompt the user if they want to use both TOR and I2P
read -r -p "Both TOR and I2P are installed. Hit yes to only use these networks. 
            This is more private but slows down your IBD a lot. 
            Hitting no will allow clearnet connections as well as TOR and I2P [y/N]" use_both

if [ "$use_both" == "y" ] || [ "$use_both" == "Y" ]; then
    network="both"
else
    # Choose the network configuration based on user choices
    if [ "$use_tor" == "yes" ] && [ "$use_i2p" == "yes" ]; then
        network="i2p" # If both TOR and I2P are installed, use I2P network by default
    elif [ "$use_tor" == "yes" ]; then
        network="tor"
    else
        network="clearnet" # Default to clearnet if neither TOR nor I2P are chosen
    fi
fi

# Configure Bitcoin Core based on the chosen network
create_bitcoin_conf "$network"

# Create systemd service unit for Bitcoin Core
create_bitcoin_core_service

# Reload the systemd daemon to recognize the new service
systemctl daemon-reload

# Start and enable Bitcoin Core service
start_and_enable_bitcoin_core

# Lightning instalation
ask_install_lnd #asks user about LND. If yes checks for and installs golang, and builds LND.

configure_rtl # makes the RTL config file and plugs it into systemd

check_services # Final systems check and exit

# Inform the user that the script has completed successfully
center_text "Thanks for using my script and thank YOU for running a Bitcoin/Lightning Full node you're helping to decentralize the network even further!"

# Exit the script with a success status code
exit 0
