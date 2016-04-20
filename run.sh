#!/bin/sh

cat stat.rb > /usr/lib/cgi-bin/stat.rb

sudo service apache2 restart

firefox https://127.0.0.1/stat

sudo tail -n200 -f /var/log/apache2/error.log
