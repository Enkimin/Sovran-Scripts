#!/bin/bash
#This is a script to install LND.

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
    local terminal_width=${COLUMNS:-$(tput cols 2>/dev/null) 80} # Use COLUMNS or tput (with fallback)
    local text_width=${#text}
    local padding=$(((terminal_width - text_width) / 2))
    printf "%*s%s%*s\n" $padding "" "$text" $padding ""
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
    cat <<EOF >"$lnd_config_file"
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
        cat <<EOF >>"$lnd_config_file"
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
        cat <<EOF >>"$lnd_config_file"
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
    echo "$wallet_password" >"$wallet_password_file"
    chown bitcoin:bitcoin "$wallet_password_file"
    chmod 400 "$wallet_password_file"
}
# Asks about Lightning, Installs golang
ask_install_lnd() {
    if [ "$(prompt_yes_no 'Core has been insatlled and configured! Install Lightning (LND)?')" == "yes" ]; then
        echo "Proceeding with Lightning (LND) installation..."
        sleep 1
        echo "Checking for and installing golang"
        install_go           # Install Go if it's not already installed
        install_lnd          # Call the function to install LND
        configure_lnd        # Call the function to configure LND and create its data folder
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

    cat <<EOF >"$rtl_config_file"
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
    cat <<EOF >"$rtl_systemd_file"
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


# Root Check
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Welcom Message
cat <<"EOF"
    !   .::::::.     ...     :::      .::.:::::::..     :::.     :::.    :::.    :::.    :::.    ...     :::::::-.  .,::::::      ::::::::::.   :::.       .,-:::::   :::  .   
    !  ;;;`    `  .;;;;;;;.  ';;,   ,;;;' ;;;;``;;;;    ;;`;;    `;;;;,  `;;;    `;;;;,  `;;; .;;;;;;;.   ;;,   `';,;;;;''''       `;;;```.;;;  ;;`;;    ,;;;'````'   ;;; .;;,.
    !  '[==/[[[[,,[[     \[[, \[[  .[[/    [[[,/[[['   ,[[ '[[,    [[[[[. '[[      [[[[[. '[[,[[     \[[, `[[     [[ [[cccc         `]]nnn]]'  ,[[ '[[,  [[[          [[[[[/'  
    !    '''    $$$$,     $$$  Y$c.$$"     $$$$$$c    c$$$cc$$$c   $$$ "Y$c$$      $$$ "Y$c$$$$$,     $$$  $$,    $$ $$""""          $$$""    c$$$cc$$$c $$$         _$$$$,    
    !   88b    dP"888,_ _,88P   Y88P       888b "88bo, 888   888,  888    Y88      888    Y88"888,_ _,88P  888_,o8P' 888oo,__        888o      888   888,`88bo,__,o, "888"88o, 
    !    "YMmMY"   "YMMMMMP"     MP        MMMM   "W"  YMM   ""`   MMM     YM      MMM     YM  "YMMMMMP"   MMMMP"`   """"YUMMM       YMMMb     YMM   ""`   "YUMMMMMP" MMM "MMP"
EOF
echo
center_text "Thanks for using Enki's Bitcoin Core install script."
center_text "This script will walk you through installing Bitcoin Core, TOR, and I2P on your machine."
center_text "To continue, hit any key."
if [ -t 0 ]; then # Check if running in an interactive shell before using "read"
    center_text "To continue, hit any key."
    read -n 1 -s -r -p ""
fi
echo




# Lightning instalation
ask_install_lnd #asks user about LND. If yes checks for and installs golang, and builds LND.

configure_rtl # makes the RTL config file and plugs it into systemd