# Sovran Scripts
------------------

Install scripts for self-hosting things.

## How to use these scripts
----------------------------

These should work on most newer Debian based distros that use apt.

If your using a GUI then you can download the codes zip file > unzip and open the folder > 
Right click on the folder select "Open in terminal" > then type `ls` this will show whats in the folder > 
then `sudo ./full_script_name.sh`. You'll need to provide an admin password. 


If you are running 'headless' and dont have Git installed yet you can run : 

`wget https://github.com/Enkimin/Sovran-Scripts/archive/main.tar.gz` >
then run `tar -xzvf main.tar.gz` > and `cd main` > `ls` > `sudo ./full_script_name.sh`


You can use Git with `git clone https://github.com/Enkimin/Sovran-Scripts.git` > 
then `cd Sovran-Scripts` > `ls` > `sudo ./full_script_name.sh`



## Scripts
------------
### nodeinstall.sh
- This script walks the user through the process of installing TOR, I2P, and Bitcoin Core. 
  If the script detects that Core is already running, it will check for updates and ask the user if they want to update. 

