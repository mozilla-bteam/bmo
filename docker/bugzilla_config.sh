#!/bin/bash

cd $BUGZILLA_ROOT

# Configure database
/usr/bin/mysqld_safe &
sleep 30
mysql -u root mysql -e "GRANT ALL PRIVILEGES ON *.* TO bugs@localhost IDENTIFIED BY 'bugs'; FLUSH PRIVILEGES;" || exit 1
mysql -u root mysql -e "CREATE DATABASE bugs CHARACTER SET = 'utf8';" || exit 1

perl checksetup.pl /checksetup_answers.txt
perl checksetup.pl /checksetup_answers.txt
perl ./docker/generate_bmo_data.pl

perl -i -pe 's/^User apache/User bugzilla/' /etc/httpd/conf/httpd.conf
perl -i -pe 's/^Group apache/Group bugzilla/' /etc/httpd/conf/httpd.conf

mysqladmin -u root shutdown
