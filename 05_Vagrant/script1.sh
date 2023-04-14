sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install ansible -y
sudo cat /vagrant/ansible.cfg > /etc/ansible/ansible.cfg
sudo cat /vagrant/hosts > /etc/ansible/hosts
rm -f /vagrant/key*
ssh-keygen -q -t rsa -f /vagrant/key -N ''