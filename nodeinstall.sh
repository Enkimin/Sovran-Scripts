#!/bin/bash
#This is a script to install Bitcoin Core and Lightning.
set -e

# Function to check if a package is installed
is_package_installed() {
    if dpkg -l "$1" 2>/dev/null | grep -q "^ii"; then
        return 0 # Package is installed
    else
        return 1 # Package is not installed
    fi
}

# Function to prompt the user with a yes/no question and return their choice
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

# Function to check if the TOR repository entry already exists
is_tor_repository_installed() {
    grep -q "deb http://deb.torproject.org/torproject.org $(lsb_release -cs) main" /etc/apt/sources.list.d/tor.list
}

# Function to install TOR
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

# Function to check if the I2P repository entry already exists
is_i2p_repository_installed() {
    grep -q "deb https://repo.i2pd.xyz $(lsb_release -cs) main" /etc/apt/sources.list.d/i2pd.list
}

# Function to install I2P
install_i2p() {
    # Check if I2P is already installed
    if is_package_installed "i2p"; then
        echo "I2P is already installed."
        if [ "$(prompt_yes_no 'Do you want to enable the I2Pd Web Console?')" == "yes" ]; then
            enable_i2pd_web_console
        fi
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

        # Enable I2Pd's web console if the user chooses to do so
        if [ "$(prompt_yes_no 'Do you want to enable I2Pd Web Console?')" == "yes" ]; then
            enable_i2pd_web_console
        fi

        echo "I2P has been successfully installed and configured."
        sleep 1
    else
        echo "I2P installation skipped."
        sleep 1
    fi
}

# Function to enable I2Pd's web console
enable_i2pd_web_console() {
    # Enable I2Pd's web console using i2prouter as the 'bitcoin' user
    echo "Enabling I2Pd Web Console..."
    su - bitcoin -c "i2prouter console start"

    echo "I2Pd Web Console enabled successfully. Moving on...."
    sleep 1
}

# Function to install required repositories for Bitcoin Core
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

# Function to download and install Bitcoin Core in the /home/bitcoin/node/ folder
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

# Function to verify cryptographic checksum of the downloaded Bitcoin Core source code
verify_checksum() {
    local node_folder="$1"
    local latest_version="$2"
    local checksum_file="${node_folder}/bitcoin-${latest_version}/SHA256SUMS.asc"
    local source_code_file="${node_folder}/bitcoin-${latest_version}/bitcoin-${latest_version}.tar.gz"

    # Download the Bitcoin Core signature file
    echo "Downloading Bitcoin Core signature file..."
    sleep 1
    wget -q "https://bitcoincore.org/bin/bitcoin-core-${latest_version}/SHA256SUMS.asc" -P "$node_folder"

    # Import Bitcoin Core developers' signing key
    echo "Importing Bitcoin Core developers' signing key..."
    sleep 1
    gpg --import bitcoin.asc

    # Verify the cryptographic checksum of the Bitcoin Core source code
    echo "Verifying the cryptographic checksum of the Bitcoin Core source code..."
    sleep 1
    sha256sum -c --ignore-missing "$checksum_file"
    if [ $? -ne 0 ]; then
        echo "ERROR: Cryptographic checksum verification failed. Aborting the installation."
        exit 1
    else
        echo "Cryptographic checksum verification successful!"
    fi
}

# Function to copy Bitcoin Core binary to /usr/local/bin and set proper ownership and permissions
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

# Function to configure Bitcoin Core based on user choices and add default settings
configure_bitcoin_core() {
    local bitcoin_conf_file="/home/bitcoin/.bitcoin/bitcoin.conf"
    local use_tor="$1"
    local use_i2p="$2"

    echo "Configuring Bitcoin Core..."
    sleep 1

    # Load the bitcoin.conf template
    cat >"$bitcoin_conf_file" <<EOF
# [core]
# Maintain coinstats index used by the gettxoutsetinfo RPC.
coinstatsindex=1
# Run in the background as a daemon and accept commands.
daemon=1
# Wait for initialization to be finished before exiting. This implies -daemon.
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

    # Check if both TOR and I2P are installed
    if [ "$use_tor" == "yes" ] && [ "$use_i2p" == "yes" ]; then
        echo "You chose to install TOR and I2P."
        echo "Do you want to only use privacy networks?(This will slow down your IBD a lot)"
        echo "Or are you okay with a hybrid mode of clearnet and privacy networks?"
        if [ "$(prompt_yes_no 'Enable hybrid mode for TOR and I2P?')" == "yes" ]; then
            # Hybrid mode: Use both TOR and I2P along with clearnet
            echo "Hybrid Mode enabled. Moving on..."
            echo -e "proxy=127.0.0.1:9050" >>"$bitcoin_conf_file"
            echo -e "i2psam=127.0.0.1:7656" >>"$bitcoin_conf_file"
            echo -e "addnode=255fhcp6ajvftnyo7bwz3an3t4a4brhopm3bamyh2iu5r3gnr2rq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=27yrtht5b5bzom2w5ajb27najuqvuydtzb7bavlak25wkufec5mq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=2el6enckmfyiwbfcwsygkwksovtynzsigmyv3bzyk7j7qqahooua.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=3gocb7wc4zvbmmebktet7gujccuux4ifk3kqilnxnj5wpdpqx2hq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=3tns2oov4tnllntotazy6umzkq4fhkco3iu5rnkxtu3pbfzxda7q.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=4fcc23wt3hyjk3csfzcdyjz5pcwg5dzhdqgma6bch2qyiakcbboa.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=4osyqeknhx5qf3a73jeimexwclmt42cju6xdp7icja4ixxguu2hq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=4umsi4nlmgyp4rckosg4vegd2ysljvid47zu7pqsollkaszcbpqq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=52v6uo6crlrlhzphslyiqblirux6olgsaa45ixih7sq5np4jujaa.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=6j2ezegd3e2e2x3o3pox335f5vxfthrrigkdrbgfbdjchm5h4awa.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=6n36ljyr55szci5ygidmxqer64qr24f4qmnymnbvgehz7qinxnla.b32.i2p:0" >>"$bitcoin_conf_file"
            sleep 1
        else
            # Privacy-only mode: Use only TOR and I2P
            echo "Privacy mode enabled. Moving on..."
            echo -e "onlynet=onion,i2p" >>"$bitcoin_conf_file"
            echo -e "proxy=127.0.0.1:9050" >>"$bitcoin_conf_file"
            echo -e "i2psam=127.0.0.1:7656" >>"$bitcoin_conf_file"
            echo -e "addnode=255fhcp6ajvftnyo7bwz3an3t4a4brhopm3bamyh2iu5r3gnr2rq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=27yrtht5b5bzom2w5ajb27najuqvuydtzb7bavlak25wkufec5mq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=2el6enckmfyiwbfcwsygkwksovtynzsigmyv3bzyk7j7qqahooua.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=3gocb7wc4zvbmmebktet7gujccuux4ifk3kqilnxnj5wpdpqx2hq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=3tns2oov4tnllntotazy6umzkq4fhkco3iu5rnkxtu3pbfzxda7q.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=4fcc23wt3hyjk3csfzcdyjz5pcwg5dzhdqgma6bch2qyiakcbboa.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=4osyqeknhx5qf3a73jeimexwclmt42cju6xdp7icja4ixxguu2hq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=4umsi4nlmgyp4rckosg4vegd2ysljvid47zu7pqsollkaszcbpqq.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=52v6uo6crlrlhzphslyiqblirux6olgsaa45ixih7sq5np4jujaa.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=6j2ezegd3e2e2x3o3pox335f5vxfthrrigkdrbgfbdjchm5h4awa.b32.i2p:0" >>"$bitcoin_conf_file"
            echo -e "addnode=6n36ljyr55szci5ygidmxqer64qr24f4qmnymnbvgehz7qinxnla.b32.i2p:0" >>"$bitcoin_conf_file"
            sleep 1
        fi

    # Check if only TOR is installed
    elif [ "$use_tor" == "yes" ]; then
        # TOR-only mode
        echo "TOR-only mode enabled. Moving on..."
        sleep 1
        echo -e "onlynet=onion" >>"$bitcoin_conf_file"
        echo -e "proxy=127.0.0.1:9050" >>"$bitcoin_conf_file"

    # Check if only I2P is installed
    elif [ "$use_i2p" == "yes" ]; then
        # I2P-only mode
        echo "I2P-only mode enabled. Moving on..."
        sleep 1
        echo -e "onlynet=i2p" >>"$bitcoin_conf_file"
        echo -e "i2psam=127.0.0.1:7656" >>"$bitcoin_conf_file"
        echo -e "addnode=255fhcp6ajvftnyo7bwz3an3t4a4brhopm3bamyh2iu5r3gnr2rq.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=27yrtht5b5bzom2w5ajb27najuqvuydtzb7bavlak25wkufec5mq.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=2el6enckmfyiwbfcwsygkwksovtynzsigmyv3bzyk7j7qqahooua.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=3gocb7wc4zvbmmebktet7gujccuux4ifk3kqilnxnj5wpdpqx2hq.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=3tns2oov4tnllntotazy6umzkq4fhkco3iu5rnkxtu3pbfzxda7q.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=4fcc23wt3hyjk3csfzcdyjz5pcwg5dzhdqgma6bch2qyiakcbboa.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=4osyqeknhx5qf3a73jeimexwclmt42cju6xdp7icja4ixxguu2hq.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=4umsi4nlmgyp4rckosg4vegd2ysljvid47zu7pqsollkaszcbpqq.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=52v6uo6crlrlhzphslyiqblirux6olgsaa45ixih7sq5np4jujaa.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=6j2ezegd3e2e2x3o3pox335f5vxfthrrigkdrbgfbdjchm5h4awa.b32.i2p:0" >>"$bitcoin_conf_file"
        echo -e "addnode=6n36ljyr55szci5ygidmxqer64qr24f4qmnymnbvgehz7qinxnla.b32.i2p:0" >>"$bitcoin_conf_file"

    fi

    # Set Bitcoin Core data directory (datadir) to /home/bitcoin/.bitcoin
    echo -e "datadir=/home/bitcoin/.bitcoin" >>"$bitcoin_conf_file"

    # Set proper permissions for the .bitcoin folder and its contents
    chown -R bitcoin:bitcoin "$bitcoin_home"
    chmod 700 "$bitcoin_home"

    # Set proper permissions for the bitcoin.conf file
    chmod 600 "$bitcoin_conf_file"

    echo "Bitcoin Core configuration completed successfully!"
}

# Function to create systemd service unit for Bitcoin Core
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
StartLimitBurst=5

[Install]
WantedBy=multi-user.target
EOF

    echo "Bitcoin Core systemd service unit created."

    # Reload systemd daemon to recognize the new service
    echo "Reloading systemd daemon to recognize the new service..."
    sleep 1
    systemctl daemon-reload
}

# Function to start and enable Bitcoin Core service
start_and_enable_bitcoin_core() {
    systemctl start bitcoind
    systemctl enable bitcoind
    echo "Bitcoin Core has been started and enabled as a systemd service."
}

# Main script starts here

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root."
    exit 1
fi

# Custom ASCII art welcome message
cat <<"EOF"
!   .::::::.     ...     :::      .::.:::::::..     :::.     :::.    :::.    :::.    :::.    ...     :::::::-.  .,::::::      ::::::::::.   :::.       .,-:::::   :::  .
!  ;;;`    `  .;;;;;;;.  ';;,   ,;;;' ;;;;``;;;;    ;;`;;    `;;;;,  `;;;    `;;;;,  `;;; .;;;;;;;.   ;;,   `';,;;;;''''       `;;;```.;;;  ;;`;;    ,;;;'````'   ;;; .;;,.
!  '[==/[[[[,,[[     \[[, \[[  .[[/    [[[,/[[['   ,[[ '[[,    [[[[[. '[[      [[[[[. '[[,[[     \[[, `[[     [[ [[cccc         `]]nnn]]'  ,[[ '[[,  [[[          [[[[[/'  
!    '''    $$$$,     $$$  Y$c.$$"     $$$$$$c    c$$$cc$$$c   $$$ "Y$c$$      $$$ "Y$c$$$$$,     $$$  $$,    $$ $$""""          $$$""    c$$$cc$$$c $$$         _$$$$,    
!   88b    dP"888,_ _,88P   Y88P       888b "88bo, 888   888,  888    Y88      888    Y88"888,_ _,88P  888_,o8P' 888oo,__        888o      888   888,`88bo,__,o, "888"88o, 
!    "YMmMY"   "YMMMMMP"     MP        MMMM   "W"  YMM   ""`   MMM     YM      MMM     YM  "YMMMMMP"   MMMMP"`   """"YUMMM       YMMMb     YMM   ""`   "YUMMMMMP" MMM "MMP"
EOF

# Additional welcome message
echo "Thanks for using Enki's Bitcoin Core + lightning install script."
echo "This script will walk you through installing Bitcoin Core, LND, RTL, TOR, and I2P on your machine."
echo "To continue, hit any key."

# Wait for the user to hit a key
read -n 1 -s -r -p "Press any key to continue..."

echo -e "\n"

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
    echo "I2P installation skipped."
fi

# Inform the user before proceeding to Bitcoin Core installation
echo "Moving on to Bitcoin Core installation..."

# Install required repositories for Bitcoin Core
install_bitcoin_core_dependencies

# Download and install Bitcoin Core
download_and_install_bitcoin_core

# Copy Bitcoin Core binary to /usr/local/bin and set proper ownership and permissions
copy_bitcoin_core_binary "$latest_version"

# Determine if TOR and I2P are installed and set the variables accordingly
use_tor="no"
use_i2p="no"

if command -v tor &>/dev/null; then
    use_tor="yes"
fi

if command -v i2pd &>/dev/null; then
    use_i2p="yes"
fi

# Prompt the user if they want to use TOR only if it is installed
if [ "$use_tor" == "yes" ]; then
    echo "Looks like you have TOR installed."
    echo "Do you want to enable TOR only mode? This will slow down your IBD but is more private."
    if [ "$(prompt_yes_no 'Enable TOR only mode?')" == "yes" ]; then
        # TOR-only mode
        use_i2p="no"
    fi
fi

# Prompt the user if they want to use I2P only if it is installed
if [ "$use_i2p" == "yes" ]; then
    echo "Looks like you have I2P installed."
    echo "Do you want to enable I2P only mode? This will slow down your IBD but is more private."
    if [ "$(prompt_yes_no 'Enable I2P only mode?')" == "yes" ]; then
        # I2P-only mode
        use_tor="no"
    fi
fi

# Configure Bitcoin Core based on the user's choices for TOR and I2P
configure_bitcoin_core "$use_tor" "$use_i2p"

# Create systemd service unit for Bitcoin Core
create_bitcoin_core_service

# Reload the systemd daemon to recognize the new service
systemctl daemon-reload

# Start and enable Bitcoin Core service
start_and_enable_bitcoin_core

# Inform the user that the script has completed successfully
echo "Enki's Bitcoin Core + Lightning installation script has completed successfully."

# Exit the script with a success status code
exit 0
