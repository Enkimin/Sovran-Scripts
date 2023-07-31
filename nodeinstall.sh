#!/bin/bash
#This is a script to install Bitcoin Core and Lightning. 
set -e

# Function to check if a package is installed
is_package_installed() {
    if dpkg -l "$1" 2>/dev/null | grep -q "^ii"; then
        return 0  # Package is installed
    else
        return 1  # Package is not installed
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
        echo "TOR is already installed. Skipping TOR installation..."
    else
        # Inform the user about TOR and its installation
        echo "TOR is a free and open-source software for enabling anonymous communication."
        echo "It directs internet traffic through a worldwide volunteer network consisting of thousands of relays to conceal a user's location and usage from anyone conducting network surveillance or traffic analysis."
        echo "TOR is commonly used to access the internet anonymously and bypass censorship."
        echo "Please note that using TOR might slow down your internet connection due to the nature of the anonymization process."

        # Confirm TOR installation with the user
        if [ "$(prompt_yes_no 'Do you want to install TOR?')" == "yes" ]; then
            echo "Adding the TOR repository..."
            echo "deb https://deb.torproject.org/torproject.org $(lsb_release -cs) main" >>/etc/apt/sources.list.d/tor.list

            echo "Importing the TOR project's GPG key..."
            wget -qO - https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor --output /etc/apt/trusted.gpg.d/tor.gpg

            echo "Updating package lists with the new repository..."
            apt update

            echo "Installing TOR..."
            apt install -y tor

            echo "Installing additional dependencies for TOR..."
            apt install -y torsocks
            apt install -y tor-geoipdb

            echo "Adding the user 'bitcoin' to the 'debian-tor' group to allow TOR access..."
            groupadd -f debian-tor  # Create the group if it doesn't exist
            usermod -a -G debian-tor bitcoin

            echo "Setting correct permissions for the TOR configuration directory..."
            chown -R debian-tor:debian-tor /var/lib/tor

            echo "Adding custom configurations to the torrc file..."
            echo -e "ControlPort 9051\nCookieAuthentication 1\nCookieAuthFileGroupReadable 1\nLog notice stdout\nSOCKSPort 9050" >>/etc/tor/torrc

            echo "Restarting TOR for changes to take effect..."
            systemctl restart tor

            echo "TOR has been successfully installed and configured."
        else
            echo "TOR installation skipped."
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
        if [ "$(prompt_yes_no 'Do you want to enable I2Pd Web Console?')" == "yes" ]; then
            enable_i2pd_web_console
        fi
        return
    fi

    # Inform the user about I2P and its installation
    echo "I2P (Invisible Internet Project) is a free and open-source software that provides an anonymous communication layer for applications."
    echo "It is designed to allow peers to communicate with each other securely and anonymously, protecting both the parties and the contents of the communication from being observed or intercepted."
    echo "Please note that using I2P might slow down your internet connection due to the anonymization process."

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
        apt install -y i2p

        echo "Starting the I2P service..."
        systemctl start i2p

        # Enable I2Pd's web console if the user chooses to do so
        if [ "$(prompt_yes_no 'Do you want to enable I2Pd Web Console?')" == "yes" ]; then
            enable_i2pd_web_console
        fi

        echo "I2P has been successfully installed and configured."
    else
        echo "I2P installation skipped."
    fi
}


# Function to enable I2Pd's web console
enable_i2pd_web_console() {
    # Enable I2Pd's web console using i2prouter as the 'bitcoin' user
    echo "Enabling I2Pd Web Console..."
    su - bitcoin -c "i2prouter console start"

    echo "I2Pd Web Console enabled successfully."
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

    # Verify the cryptographic checksum of the downloaded source code
    verify_checksum "$node_folder" "$latest_version" "${node_folder}/bitcoin-${latest_version}/bitcoin-${latest_version}.tar.gz.sig"

    # Navigate into the Bitcoin Core directory
    echo "Entering the Bitcoin Core directory..."
    sleep 1
    cd "$node_folder/bitcoin-$latest_version" || (echo "Failed to enter the Bitcoin Core directory. Aborting the installation." && exit 1)

    # Build and install Bitcoin Core
    echo "Building Bitcoin Core. This can take a while so go touch some grass."
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
    local signature_file="$3"
    local checksum_file="${node_folder}/bitcoin-${latest_version}/SHA256SUMS.asc"
    local source_code_file="${node_folder}/bitcoin-${latest_version}/bitcoin-${latest_version}.tar.gz"

    # Download the Bitcoin Core signature file
    echo "Downloading Bitcoin Core signature file..."
    sleep 1
    gpg --keyserver keyserver.ubuntu.com --recv-keys 0x01EA5486DE18A882D4C2684590C8019E36C2E964
    gpg --verify "$signature_file" "$source_code_file"

    # Verify the checksum of the Bitcoin Core source code
    echo "Verifying the cryptographic checksum of the Bitcoin Core source code..."
    sleep 1
    sha256sum -c --ignore-missing "$checksum_file" --status
    if [ $? -ne 0 ]; then
        echo "ERROR: Cryptographic checksum verification failed. Aborting the installation."
        exit 1
    fi
}



# Function to configure Bitcoin Core based on user choices and add default settings
configure_bitcoin_core() {
    local bitcoin_conf_file="/home/bitcoin/.bitcoin/bitcoin.conf"
    local use_tor="$1"
    local use_i2p="$2"

    echo "Configuring Bitcoin Core..."
    sleep 1 

    # Create .bitcoin folder in the user's home directory
    local bitcoin_data_dir="/home/bitcoin/.bitcoin"
    mkdir -p "$bitcoin_data_dir"

    # Set appropriate configurations in bitcoin.conf based on the user's choices for TOR and I2P
    if [[ "$use_tor" == "yes" && "$use_i2p" == "yes" ]]; then
        # Both TOR and I2P are installed
        echo "Do you want to use a 'hybrid mode' with IPv4/IPv6 for TOR? (y/n)"
        if [ "$(prompt_yes_no 'Enable hybrid mode for TOR?')" == "yes" ]; then
            echo -e "onlynet=onion,ipv4,ipv6" >>"$bitcoin_conf_file"
        else
            echo -e "onlynet=onion" >>"$bitcoin_conf_file"
        fi

        echo "Do you want to use a 'hybrid mode' with IPv4/IPv6 for I2P? (y/n)"
        if [ "$(prompt_yes_no 'Enable hybrid mode for I2P?')" == "yes" ]; then
            echo -e "onlynet=i2p,ipv4,ipv6" >>"$bitcoin_conf_file"
        else
            echo -e "onlynet=i2p" >>"$bitcoin_conf_file"
        fi
    elif [[ "$use_tor" == "yes" ]]; then
        # Only TOR is installed
        echo "Do you want to use a 'hybrid mode' with IPv4/IPv6? (y/n)"
        if [ "$(prompt_yes_no 'Enable hybrid mode?')" == "yes" ]; then
            echo -e "onlynet=onion,ipv4,ipv6" >>"$bitcoin_conf_file"
        else
            echo -e "onlynet=onion" >>"$bitcoin_conf_file"
        fi
    elif [[ "$use_i2p" == "yes" ]]; then
        # Only I2P is installed
        echo "Do you want to use a 'hybrid mode' with IPv4/IPv6 for I2P? (y/n)"
        if [ "$(prompt_yes_no 'Enable hybrid mode for I2P?')" == "yes" ]; then
            echo -e "onlynet=i2p,ipv4,ipv6" >>"$bitcoin_conf_file"
        else
            echo -e "onlynet=i2p" >>"$bitcoin_conf_file"
        fi
    else
        # Neither TOR nor I2P is installed
        echo -e "onlynet=ipv4,ipv6" >>"$bitcoin_conf_file"
    fi

    # Set Bitcoin Core data directory (datadir) to /home/bitcoin/.bitcoin
    echo -e "datadir=/home/bitcoin/.bitcoin" >>"$bitcoin_conf_file"

    # Add default settings to bitcoin.conf
    echo -e "\n# [core]" >>"$bitcoin_conf_file"
    echo -e "coinstatsindex=1" >>"$bitcoin_conf_file"
    echo -e "daemon=1" >>"$bitcoin_conf_file"
    echo -e "daemonwait=1" >>"$bitcoin_conf_file"
    echo -e "dbcache=600" >>"$bitcoin_conf_file"
    echo -e "maxmempool=800" >>"$bitcoin_conf_file"
    echo -e "txindex=1" >>"$bitcoin_conf_file"
    echo -e "nopeerbloomfilters=1" >>"$bitcoin_conf_file"
    echo -e "peerbloomfilters=0" >>"$bitcoin_conf_file"
    echo -e "permitbaremultisig=0" >>"$bitcoin_conf_file"
    echo -e "debug=1" >>"$bitcoin_conf_file"
    echo -e "shrinkdebuglog=1" >>"$bitcoin_conf_file"
    echo -e "debug=mempool" >>"$bitcoin_conf_file"
    echo -e "debug=rpc" >>"$bitcoin_conf_file"
    echo -e "debug=tor" >>"$bitcoin_conf_file"
    echo -e "debug=i2p" >>"$bitcoin_conf_file"

    # Set proper permissions for the .bitcoin folder and its contents
    chown -R bitcoin:bitcoin "$bitcoin_data_dir"
    chmod 700 "$bitcoin_data_dir"

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
User=bitcoin
Group=bitcoin
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

# Get the user's choices for TOR and I2P installation
use_tor=$(prompt_yes_no 'Do you want to use TOR?')
use_i2p=$(prompt_yes_no 'Do you want to use I2P?')

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
