sudo mkdir /usr/src/shared
sudo chmod 777 /usr/src/shared
cd /usr/src/shared
wget https://artifacts.elastic.co/downloads/beats/elastic-agent/elastic-agent-7.16.3-linux-x86_64.tar.gz
tar zxvf elastic-agent-7.16.3-linux-x86_64.tar.gz
cd elastic-agent-7.16.3-linux-x86_64
sudo ./elastic-agent install --insecure --force --v --url=http://pine.tokenocean.io:8220 --enrollment-token=Y25iV2ozOEJVVkdWNE5oQWdYS286QTRrSzU2cThTSHlBWlJVRlY2YVNUUQ==
