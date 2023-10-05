#!/bin/bash
#This is a script to install Bitcoin Core
#Global Functions.
log_file="install_log.txt"
exec > >(tee -a "$log_file") 2>&1

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

# Network stuff

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
        # Confirm TOR installation 
        if [ "$(prompt_yes_no 'Do you want to install TOR?')" == "yes" ]; then
            echo "Adding the TOR repository..."
            sleep 1
            if ! echo "deb https://deb.torproject.org/torproject.org $(lsb_release -cs) main" >>/etc/apt/sources.list.d/tor.list; then
                echo "Failed to add the TOR repository." >&2
                exit 1
            fi

            echo "Importing the TOR project's GPG key..."
            sleep 1
            if ! wget -qO - https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor --output /etc/apt/trusted.gpg.d/tor.gpg; then
                echo "Failed to import the GPG key for TOR." >&2
                exit 1
            fi

            echo "Updating package lists with the new repository..."
            sleep 1
            if ! apt update; then
                echo "Failed to update package lists with the new repository." >&2
                exit 1
            fi

            echo "Installing TOR..."
            sleep 1
            if ! apt install -y tor; then
                echo "Failed to install TOR." >&2
                exit 1
            fi

            echo "Installing additional dependencies for TOR..."
            sleep 1
            if ! apt install -y torsocks tor-geoipdb; then
                echo "Failed to install additional dependencies for TOR." >&2
                exit 1
            fi

            echo "Adding the user 'bitcoin' to the 'debian-tor' group to allow TOR access..."
            sleep 1
            groupadd -f debian-tor # Create the group if it doesn't exist
            usermod -a -G debian-tor bitcoin
            echo "Setting correct permissions for the TOR configuration directory..."
            sleep 1
            if ! chown -R debian-tor:debian-tor /var/lib/tor; then
                echo "Failed to set permissions for the TOR configuration directory." >&2
                exit 1
            fi

            echo "Adding custom configurations needed for Core to the torrc file..."
            sleep 1
            if ! echo -e "ControlPort 9051\nCookieAuthentication 1\nCookieAuthFileGroupReadable 1\nLog notice stdout\nSOCKSPort 9050" >>/etc/tor/torrc; then
                echo "Failed to add custom configurations to the torrc file." >&2
                exit 1
            fi

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

    # Confirm I2P installation
    if [ "$(prompt_yes_no 'Do you want to install I2P?')" == "yes" ]; then
        echo "Adding I2P repository..."
        wget -q -O - https://repo.i2pd.xyz/.help/add_repo | sudo bash -s -
        if [ $? -ne 0 ]; then
            echo "Failed to add the I2P repository." >&2
            exit 1
        fi

        if ! is_package_installed "apt-transport-https"; then
            echo "Installing apt-transport-https..."
            if ! apt install -y apt-transport-https; then
                echo "Failed to install apt-transport-https." >&2
                exit 1
            fi
        else
            echo "apt-transport-https is already installed."
        fi

        echo "Updating package lists with the new repository..."
        if ! apt update; then
            echo "Failed to update package lists with the new repository." >&2
            exit 1
        fi

        echo "Installing I2P..."
        sleep 1
        if ! apt install -y i2p; then
            echo "Failed to install I2P." >&2
            exit 1
        fi

        echo "Starting the I2P service..."
        if ! systemctl start i2p; then
            echo "Failed to start the I2P service." >&2
            exit 1
        fi

        echo "I2P has been installed. Moving on..."
        sleep 1
    else
        echo "I2P installation skipped. Moving on..."
        sleep 1
    fi
}

# Bitocin Stuff

# Installs Core's dependencies
install_bitcoin_core_dependencies() {
    echo "Installing required repositories for Bitcoin Core..."
    sleep 1
    if ! is_package_installed "git"; then
        echo "Installing git..."
        if ! apt install -y git; then
            echo "Failed to install git." >&2
            exit 1
        fi
    else
        echo "git is already installed."
    fi

    local bitcoin_core_dependencies=("build-essential" "libtool" "autotools-dev" "automake" "pkg-config" "bsdmainutils" "python3" "libssl-dev" "libevent-dev" "libboost-system-dev" "libboost-filesystem-dev" "libboost-test-dev" "libboost-thread-dev" "libboost-all-dev" "libzmq3-dev")

    # Iterate through the dependencies and install them
    for dep in "${bitcoin_core_dependencies[@]}"; do
        if ! is_package_installed "$dep"; then
            echo "Installing $dep..."
            if ! apt install -y "$dep"; then
                echo "Failed to install $dep." >&2
                exit 1
            fi
        else
            echo "$dep is already installed."
        fi
    done

    echo "Bitcoin Core dependencies have been successfully installed."
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
        echo "Failed to fetch the latest version of Bitcoin Core. Aborting the installation." >&2
        exit 1
    fi

    # Clone the Bitcoin Core repository from GitHub
    echo "Cloning Bitcoin Core repository..."
    sleep 1
    if ! git clone --depth 1 --branch "$latest_version" https://github.com/bitcoin/bitcoin.git "$node_folder/bitcoin-$latest_version"; then
        echo "Failed to clone the Bitcoin Core repository. Aborting the installation." >&2
        exit 1
    fi

    # Call verify_checksum function after cloning the Bitcoin Core repository
    verify_checksum "$node_folder" "$latest_version"

    # Navigate into the Bitcoin Core directory
    echo "Entering the Bitcoin Core directory..."
    sleep 1
    if ! cd "$node_folder/bitcoin-$latest_version"; then
        echo "Failed to enter the Bitcoin Core directory. Aborting the installation." >&2
        exit 1
    fi

    # Build and install Bitcoin Core
    echo "Building Bitcoin Core. This can take a while, so go touch some grass."
    sleep 1
    ./autogen.sh
    ./configure
    make

    # Check if 'make install' was successful
    if ! make install; then
        echo "Failed to install Bitcoin Core. Aborting the installation." >&2
        exit 1
    fi

    echo "Bitcoin Core installation completed successfully!"
    sleep 1
}

# Verifys cryptographic checksum of Bitcoin Core source code (Gets called in the install) 
verify_checksum() {
    local node_folder="$1"
    local latest_version="$2"
    local checksum_file="${node_folder}/bitcoin-${latest_version}/SHA256SUMS.asc"
    local bitcoin_core_url="https://bitcoincore.org/bin/bitcoin-core-${latest_version}/SHA256SUMS.asc"
    local gpg_key="0x01EA5486DE18A882D4C2684590C8019E36C2E964"
    echo "Downloading Bitcoin Core signature file..."
    sleep 1
    if ! wget -q "$bitcoin_core_url" -P "$node_folder"; then
        echo "ERROR: Failed to download the Bitcoin Core signature file." >&2
        exit 1
    fi

    if ! gpg --list-keys "$gpg_key" &>/dev/null; then
        echo "Importing Bitcoin Core developers' signing key..."
        sleep 1
        if ! gpg --recv-keys "$gpg_key"; then
            echo "ERROR: Failed to import the Bitcoin Core developers' signing key." >&2
            exit 1
        fi
    else
        echo "Bitcoin Core developers' signing key is already imported."
    fi

    echo "Verifying the signature of the SHA256SUMS.asc file..."
    sleep 1
    if ! gpg --verify "${checksum_file}"; then
        echo "ERROR: Signature verification of SHA256SUMS.asc failed." >&2
        exit 1
    else
        echo "Signature verification successful!"
    fi
    echo "Verifying the cryptographic checksum of the Bitcoin Core source code..."
    sleep 1
    if ! cd "${node_folder}/bitcoin-${latest_version}"; then
        echo "ERROR: Failed to navigate to the Bitcoin Core source code directory." >&2
        exit 1
    fi

    if ! sha256sum -c --ignore-missing "${checksum_file}"; then
        echo "ERROR: Cryptographic checksum verification failed." >&2
        exit 1
    else
        echo "Cryptographic checksum verification successful!"
    fi
}

# Copies Core's binary to /usr/local/bin and checks permissions
copy_bitcoin_core_binary() {
    local node_folder="/home/bitcoin/node"
    local latest_version="$1"
    local expected_location="/usr/local/bin"
    if [ -x "${expected_location}/bitcoind" ] && [ -x "${expected_location}/bitcoin-cli" ]; then
        echo "Bitcoin Core binaries are already installed in ${expected_location}. Skipping copying and permissions check."
        return
    fi
    echo "Copying Bitcoin Core binary to ${expected_location}..."
    sleep 1
    cp "$node_folder/bitcoin-$latest_version/src/bitcoind" "${expected_location}"
    cp "$node_folder/bitcoin-$latest_version/src/bitcoin-cli" "${expected_location}"
    chown root:root "${expected_location}/bitcoind"
    chown root:root "${expected_location}/bitcoin-cli"
    chmod 755 "${expected_location}/bitcoind"
    chmod 755 "${expected_location}/bitcoin-cli"
    echo "Bitcoin Core binary has been copied to ${expected_location} and proper permissions have been set."
    sleep 1
}


create_bitcoin_conf() {
    local bitcoin_conf_file="/home/bitcoin/.bitcoin/bitcoin.conf"
    local network="\$1" 
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
                permitbaremultisig=0

                # Reduce the log file size on restarts
                shrinkdebuglog=1
EOF
    # Additional configuration based on network mode
    case "$network" in
        "tor")
            # TOR configuration
            cat <<EOF >>"$bitcoin_conf_file"
                # [Network]
                debug=tor
                proxy=127.0.0.1:9050
                onlynet=onion
EOF
            ;;
        "tor_hybrid")
            # TOR hybrid configuration
            cat <<EOF >>"$bitcoin_conf_file"
                # [Network]
                debug=tor
                proxy=127.0.0.1:9050
EOF
            ;;
        "i2p")
            # I2P configuration
            cat <<EOF >>"$bitcoin_conf_file"
                # [Network]
                debug=i2p
                i2psam=127.0.0.1:7656
                onlynet=i2p
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
EOF
            ;;
        "i2p_hybrid")
            # I2P hybrid configuration
            cat <<EOF >>"$bitcoin_conf_file"
                # [Network]
                debug=i2p
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
EOF
            ;;
        "both")
            # TOR and I2P configuration
            cat <<EOF >>"$bitcoin_conf_file"
                # [Network]
                debug=tor
                debug=i2p
                proxy=127.0.0.1:9050
                i2psam=127.0.0.1:7656
                onlynet=onion
                onlynet=i2p
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
EOF
            ;;
        "both_hybrid")
            # TOR and I2P hybrid configuration
            cat <<EOF >>"$bitcoin_conf_file"
                # [Network]
                debug=tor
                debug=i2p
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
                
EOF
            ;;
    esac
}

# Plugs Core into systemd
create_bitcoin_core_service() {
    local bitcoin_binary="/usr/local/bin/bitcoind"

    # A double check for bitcoind  
    if ! command -v "$bitcoin_binary" &>/dev/null; then
        echo "Error: $bitcoin_binary does not exist. Please install Bitcoin Core and try again."
        exit 1
    fi
    local service_file="/etc/systemd/system/bitcoind.service"
    cat <<EOF >"$service_file"
            [Unit]
            Description=Bitcoin core daemon

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
    echo "Reloading systemd daemon to recognize the new service..."
    sleep 1
    if ! systemctl daemon-reload; then
        echo "Error: Failed to reload systemd daemon. Please check your systemd configuration."
        exit 1
    fi
}

# Starts and enables Bitcoin Core
start_and_enable_bitcoin_core() {
    systemctl start bitcoind
    systemctl enable bitcoind
    echo "Bitcoin Core has been started and added to systemd. This allows Core to start at boot."
}

# Final systems check and exit.
check_services() {
    echo "Checking if all required services are running..."
    if sudo systemctl is-active --quiet bitcoind; then
        echo "Woot! Core is running. Welcome to your Core Node"
        # Additional actions you want to perform when bitcoind is running
    else
        echo "Oops, it looks like something did not work bitcoind is not running."
        echo "bitcoind"
        exit 1
    fi
}

# Main script starts here

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
center_text "Thanks for using Enki's Bitcoin Core script"
center_text "This script will walk you through installing TOR, I2P and Bitcoin Core on your box."
center_text "To continue, hit any key."
if [ -t 0 ]; then # Check if running in an interactive shell before using "read"
    center_text "To continue, hit any key."
    read -n 1 -s -r -p ""
fi
echo

# Check if the user bitcoin already exists and make it if not. 
if id "bitcoin" &>/dev/null; then
    echo "User 'bitcoin' already exists. Skipping user creation..."
else
    # Create a new user named "bitcoin" and set the password
    echo "Creating a user called bitcoin..."
    sleep 1
    if adduser --disabled-password --gecos "" bitcoin; then
        echo "User 'bitcoin' created successfully."
        echo "Please set the password for the 'bitcoin' user. You'll need this to log into the user at a later date."
        if passwd bitcoin; then
            echo "Password for 'bitcoin' user set successfully."
        else
            echo "Failed to set the password for 'bitcoin' user." >&2
            exit 1
        fi

    else
        echo "Failed to create the 'bitcoin' user." >&2
        exit 1
    fi
fi

# Ensure that /home/bitcoin directory exists and set proper permissions
bitcoin_home="/home/bitcoin"
if [ ! -d "$bitcoin_home" ]; then
    echo "Creating /home/bitcoin directory..."
    if mkdir -p "$bitcoin_home"; then
        echo "Directory /home/bitcoin created successfully."
        echo "Setting ownership and permissions for /home/bitcoin..."
        if chown -R bitcoin:bitcoin "$bitcoin_home"; then
            echo "Ownership and permissions set successfully."
            if chmod 700 "$bitcoin_home"; then
                echo "Permissions set successfully."
            else
                echo "Failed to set permissions for $bitcoin_home." >&2
                exit 1
            fi

        else
            echo "Failed to set ownership for $bitcoin_home." >&2
            exit 1
        fi
    else
        echo "Failed to create /home/bitcoin directory." >&2
        exit 1
    fi
fi

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

# Determine if TOR and I2P are installed and set the variables accordingly
use_tor="no"
use_i2p="no"
if command -v tor &>/dev/null; then
    use_tor="yes"
fi
if command -v i2pd &>/dev/null; then
    use_i2p="yes"
fi
if [ "$use_tor" == "yes" ]; then
    echo "TOR is good to go."
fi
if [ "$use_i2p" == "yes" ]; then
    echo "I2P is good to go."
fi
# Check if neither TOR nor I2P are installed
if [ "$use_tor" == "no" ] && [ "$use_i2p" == "no" ]; then
    echo "You skippied installing both TOR and I2P. Moving on to installing Core then..."
else
    # Prompt the user to continue with Bitcoin Core installation
    read -r -p "Press any key to continue with Bitcoin Core installation..."
    echo
fi

# Installs required repositories for Bitcoin Core
install_bitcoin_core_dependencies

# Download and installs Bitcoin Core
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

# Check installed services and prompt the user accordingly
if [ "$use_tor" == "yes" ] && [ "$use_i2p" == "yes" ]; then
    read -r -p "Both TOR and I2P are installed. Hit yes to only use these networks. 
                This is more private but slows down your IBD by a fair amount. 
                Hitting no will allow clearnet connections as well plus TOR and I2P
                this makes your IBD faster but is less private. [y/n]" 
    use_both
    if [ "${use_both,,}" == "y" ]; then
        network="both"
    else
        network="both_hybrid"
    fi
    create_bitcoin_conf "$network"
elif [ "$use_tor" == "yes" ] && [ "$use_i2p" == "no" ]; then
    # Only TOR is installed
    read -r -p "Looks like only TOR is installed. Hit yes(y) for TOR only Mode. 
                Hit No(n) for a hybrid mode. It will allow clearnet and TOR connections, 
                this makes your IBD faster but is less private. [y/n]" 
    tor_mode
    if [ "${tor_mode,,}" == "tor" ]; then
        network="tor"
    else
        network="tor_hybrid"
    fi
    create_bitcoin_conf "$network"
elif [ "$use_i2p" == "yes" ] && [ "$use_tor" == "no" ]; then
    # Only I2P is installed
    read -r -p "Looks like only I2P is installed. Hit yes(y) for I2P only Mode. 
                Hit No(n) for a hybrid mode. It will allow clearnet and I2P connections, 
                this makes your IBD faster but is less private. [y/n]" 
    i2p_mode
    if [ "${i2p_mode,,}" == "i2p" ]; then
        network="i2p"
    else
        network="i2p_hybrid"
    fi
    create_bitcoin_conf "$network"
else
    echo "The conf file is made. Moving on..."
fi
# Configure Bitcoin Core based on the chosen network
create_bitcoin_conf "$network"

# Create systemd service unit for Bitcoin Core
create_bitcoin_core_service

# Reload the systemd daemon to recognize the new service
systemctl daemon-reload

# Start and enable Bitcoin Core service
start_and_enable_bitcoin_core

check_services # Final systems check and exit

# Inform the user that the script has completed successfully
center_text "Thanks for using my script and thank YOU for running a Bitcoin full node you're helping to decentralize the network even further!"

# Exit the script with a success status code
exit 0
