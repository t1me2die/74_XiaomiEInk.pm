be sure the fhem user have the necessary rights to execute "bluetoothctl".

check it under: 
\n cat /etc/group

output like: 
\n bluetooth: x :111:fhem,pi

add user to group bluetooth:
\n usermod -aG GROUPNAME USERNAME

example:
\n usermod -aG bluetooth fhem
\n usermod -aG bluetooth pi
