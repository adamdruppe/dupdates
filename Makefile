all:
	# dmd -i -Ipath/to/arsd -L-Lpath/to/postgres
	dmdi -ofdupdates main.d -version=embedded_httpd_threads -g
	# ./dupdates  --port 4545
