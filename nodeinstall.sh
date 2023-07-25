#!/bin/bash

# Function to check if a package is installed
is_package_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "installed"
}

# Function to install TOR
install_tor() {
  # Add TOR repository
  echo "deb http://deb.torproject.org/torproject.org $(lsb_release -cs) main" >> /etc/apt/sources.list.d/tor.list
  gpg --keyserver keys.gnupg.net --recv A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89
  gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -

  # Update package lists with the new repository
  echo "Updating system with the new repository..."
  apt update

  # Install TOR
  echo "Installing TOR..."
  apt install -y tor

  # Additional dependencies for TOR (you can add more if required)
  echo "Installing additional dependencies for TOR..."
  apt install -y torsocks
  apt install -y tor-geoipdb

  # Add the user "bitcoin" to the "debian-tor" group to allow TOR access
  usermod -a -G debian-tor bitcoin

  # Set correct permissions for the TOR configuration directory
  chown -R debian-tor:debian-tor /var/lib/tor

  # Add custom configurations to the torrc file
  echo -e "ControlPort 9051\nCookieAuthentication 1\nCookieAuthFileGroupReadable 1\nLog notice stdout\nSOCKSPort 9050" >> /etc/tor/torrc

  # Restart TOR for changes to take effect
  service tor restart
}

# Function to install I2P
install_i2p() {
  # Add I2P repository
  echo "Adding I2P repository..."
  wget -q -O - https://repo.i2pd.xyz/.help/add_repo | sudo bash -s -

  # Check if apt-transport-https is installed and install it if not
  if ! is_package_installed "apt-transport-https"; then
    echo "Installing apt-transport-https..."
    apt install -y apt-transport-https
  else
    echo "apt-transport-https is already installed."
  fi

  echo "Installing I2P..."
  apt install -y i2p

  # Start the I2P service
  service i2p start

  # Enable I2Pd's web console
  enable_i2pd_web_console
}

# Function to enable I2Pd's web console
enable_i2pd_web_console() {
  # Comment out existing http section entries
  sed -i 's/^http.address =/#http.address =/' /var/lib/i2p/i2p-config
  sed -i 's/^http.port =/#http.port =/' /var/lib/i2p/i2p-config
  sed -i 's/^http.auth =/#http.auth =/' /var/lib/i2p/i2p-config

  # Add new settings for http section
  echo "http.address=127.0.0.1" >> /var/lib/i2p/i2p-config
  echo "http.port=7070" >> /var/lib/i2p/i2p-config
  echo "http.auth=true" >> /var/lib/i2p/i2p-config
  echo "http.user=bitcoin" >> /var/lib/i2p/i2p-config
  echo "http.pass=bitcoin" >> /var/lib/i2p/i2p-config

  echo "I2Pd web console enabled successfully."
}

# Function to install required repositories for Bitcoin Core
install_bitcoin_core_dependencies() {
  echo "Installing required repositories for Bitcoin Core..."
  apt install -y build-essential libtool autotools-dev automake pkg-config bsdmainutils python3 libssl-dev libevent-dev libboost-system-dev libboost-filesystem-dev libboost-test-dev libboost-thread-dev libboost-all-dev libzmq3-dev
}

# Function to download and verify Bitcoin Core in the /home/bitcoin/node/ folder and build it
download_and_verify_bitcoin_core() {
  local node_folder="/home/bitcoin/node"

  # Create the node folder if it doesn't exist
  mkdir -p "$node_folder"

  # Download the latest version of Bitcoin Core and the SHA256SUMS file
  echo "Fetching the latest version of Bitcoin Core..."
  latest_version=$(curl -s https://bitcoincore.org/en/download/ | grep -oP 'bitcoin-[0-9]+\.[0-9]+\.[0-9]+.tar.gz' | tail -1)
  wget "https://bitcoincore.org/bin/$latest_version" -P "$node_folder"
  wget "https://bitcoincore.org/bin/$latest_version.asc" -P "$node_folder"

  # Verify the downloaded file using GPG signature
  echo "Verifying the downloaded Bitcoin Core..."
  gpg --keyserver keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
  gpg --verify "$node_folder/$latest_version.asc" "$node_folder/$latest_version" | grep -q "Good signature from" || (echo "Verification of Bitcoin Core failed. Aborting the installation." && exit 1)

  # Extract the downloaded tarball and navigate into the extracted folder
  echo "Extracting Bitcoin Core..."
  tar -xzf "$node_folder/$latest_version" -C "$node_folder"
  cd "$node_folder/bitcoin-*" || (echo "Failed to enter the Bitcoin Core directory. Aborting the installation." && exit 1)

  # Build and install Bitcoin Core
  echo "Building Bitcoin Core..."
  ./autogen.sh
  ./configure
  make

  # Inform the user about the time-consuming installation step
  echo "Building is complete. Now installing Bitcoin Core. This might take a while. Go outside, touch grass, and come back!"

  # Run the make install step
  make install

  echo "Bitcoin Core installation completed successfully!"
}

configure_bitcoin_core() {
  local bitcoin_conf_file="/home/bitcoin/.bitcoin/bitcoin.conf"
  local use_tor_and_i2p_mode="$1"

  echo "Configuring Bitcoin Core..."

  # Create .bitcoin folder in the user's home directory
  mkdir -p "/home/bitcoin/.bitcoin"

  # Write the appropriate configuration to the bitcoin.conf file
  cat <<EOF >"$bitcoin_conf_file"
# [core]
coinstatsindex=1
daemon=1
daemonwait=1
dbcache=600
maxmempool=800
txindex=1
nopeerbloomfilters=1
peerbloomfilters=0
permitbaremultisig=0
shrinkdebuglog=1
debug=mempool
debug=rpc
debug=tor
debug=i2p

# [NETWORK]
EOF

  if [[ "$use_tor_and_i2p_mode" == "yes" ]]; then
    cat <<EOF >>"$bitcoin_conf_file"
onlynet=onion,i2p
proxy=127.0.0.1:9050
i2psam=127.0.0.1:7656
EOF
  elif [[ "$install_tor_choice" == "yes" ]]; then
    cat <<EOF >>"$bitcoin_conf_file"

proxy=127.0.0.1:9050
EOF
  elif [[ "$install_i2p_choice" == "yes" ]]; then
    cat <<EOF >>"$bitcoin_conf_file"

i2psam=127.0.0.1:7656
EOF
  fi

  echo "Bitcoin Core has been successfully configured."
}

# Main script starts here


# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root."
  exit 1
fi

# Custom ASCII art welcome message
cat << "EOF"
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

# Wait for user to hit a key
read -n 1 -s -r -p "Press any key to continue..."

echo -e "\n"
 
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

echo "Moving on to Bitcoin Core installation..."

# Install required repositories for Bitcoin Core
install_bitcoin_core_dependencies

# Download and verify Bitcoin Core
download_and_verify_bitcoin_core

# Configure Bitcoin Core based on the user's choices for Tor and I2P
if [[ "$install_tor_choice" == "yes" || "$install_i2p_choice" == "yes" ]]; then
  echo "Do you want to enable Tor and I2P only mode? (y/n)"
  if [ "$(prompt_yes_no 'Enable Tor and I2P only mode?')" == "yes" ]; then
    configure_bitcoin_core "yes"
  else
    configure_bitcoin_core "no"
  fi
else
  configure_bitcoin_core "no"
fi

echo "Bitcoin Core has been successfully installed and configured."


