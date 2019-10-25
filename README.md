be sure the fhem user have the necessary rights to execute "bluetoothctl".

check it under: 
cat /etc/group

output like: 
bluetooth:x:111:fhem,pi

add user to group bluetooth:
usermod -aG GROUPNAME USERNAME

example:
usermod -aG bluetooth fhem
usermod -aG bluetooth pi
