# FastCGI wrappers

(The original file was taken from the links described in http://nginxlibrary.com/perl-fastcgi/, that is
http://nginxlibrary.com/downloads/perl-fcgi/fastcgi-wrapper. It is attributed to Denis S. Filimonov).

These scripts are intended for use with Apache's mod\_fcgid. If the daemonizing code is uncommented
and the socket changed to a TCP/IP one, they may be used with nginx as well.

Feel free to use these scripts. Please consider giving changes back to the community.

## `fastcgi-wrapper.pl`

This wrapper may execute virtually anything that uses STDIN and STDOUT. Originally written for
Perl scripts, it should only be used for anything *but* Perl scripts, e.g. ELF binaries, Python CGI
scripts etc.

This script works a bit like mod\_cgid in that it still forks the application process.

## `perl-cgi-wrapper.pl`

This script is based on the same fastcgi-wrapper script as the one above, but it's adapted
for best Perl performance. It doesn't use the usual fork-exec-interpret mechanism (like CGI does).
It rather works like the PHP binaries compiled for FastCGI use (php-cgi, for example): It accepts
FastCGI requests, reads the file described in the `$ENV{SCRIPT_FILENAME}` variable and `eval()`uates
it. This mechanism does not involve any forking (as already mentioned), making it quite cheap.

## systemd configuration

For `perl-cgi-wrapper`:

```ini
# fcgi-pl.service

[Unit]
Description=Perl CGI scripts for <user>

[Service]
Type=exec
User=<user>
StandardInput=socket
ExecStart=/usr/bin/perl /path/to/fastcgi-wrappers/perl-cgi-wrapper.pl
ExecStop=/bin/kill -TERM $MAINPID

[Install]
WantedBy=network.target
```

and a socket unit,

```ini
Description = "FCGI socket for fcgi-pl (%i)"

[Socket]
ListenStream = 127.0.0.1:8999
Accept = false

[Install]
WantedBy = sockets.target fcgi-pl.service
```

Note that for this to work, use the standard way of `STDIN` in the `main()`
function. Start the script using:

```bash
sudo systemctl start fcgi-pl.service
```

## `nginx` configuration

If you use IP sockets with the above configuration:

```nginx
location /util/ {
        fastcgi_pass   127.0.0.1:8999;
        fastcgi_index  index.pl;
        fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
        include        fastcgi_params;
}
```

You can alternatively use UNIX domain sockets.

## `mod_fcgid` configuration

A working configuration could look like the following example:

```
<IfModule mod_fcgid.c>
    FcgidConnectTimeout 20
    FcgidMaxProcesses 30
    FcgidMaxRequestsPerProcess 10000
    FcgidMaxProcessesPerClass 3
    FcgidMaxRequestLen 20000000

    <FilesMatch "\.fcgi">
    AddHandler fcgid-script .fcgi
    Options +ExecCGI
    </FilesMatch>

    <FilesMatch "\.pl">
    AddHandler fcgid-script .pl
    Options +ExecCGI
    FcgidWrapper /usr/local/bin/perl-cgi-wrapper.pl .pl
    </FilesMatch>

    # C/C++/Haskell binaries
    <FilesMatch "\.elf">
    AddHandler fcgid-script .elf
    Options +ExecCGI
    FcgidWrapper /usr/local/bin/fastcgi-wrapper.pl .elf
    </FilesMatch>

</IfModule>
```

If you don't use suexec or any other modules interfering with mod\_fcgid, this is all
the configuration you need.

