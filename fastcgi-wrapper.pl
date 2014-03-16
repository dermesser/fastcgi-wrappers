#!/usr/bin/perl

# Original author: Denis S. Filimonov
# Patched by Lewin Bormann <lbo@spheniscida.de>
# Changes:
#   - Using explicit pipes, none of Perl's open() black magic
#   - Using STDIN as socket. This is necessary for cooperation with Apache's mod_fcgid.
#   -> Also no daemonization.

use FCGI;
use Socket;
use POSIX qw(setsid);

require 'syscall.ph';

#&daemonize;

#this keeps the program alive or something after exec'ing perl scripts
END() { } BEGIN() { }
*CORE::GLOBAL::exit = sub { die "fakeexit\nrc=".shift()."\n"; };
eval q{exit};
if ($@) {
    exit unless $@ =~ /^fakeexit/;
};

&main;

sub daemonize() {
    chdir '/'                 or die "Can't chdir to /: $!";
    defined(my $pid = fork)   or die "Can't fork: $!";
    exit if $pid;
    setsid                    or die "Can't start a new session: $!";
    umask 0;
}

sub main {
    $socket = STDIN; #FCGI::OpenSocket( "127.0.0.1:8999", 10 ); #use IP sockets
    $request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%req_params, $socket );
    if ($request) { request_loop()};
    FCGI::CloseSocket( $socket );
}

sub request_loop {
    while( $request->Accept() >= 0 ) {

        #processing any STDIN input from WebServer (for CGI-POST actions)
        $stdin_passthrough ='';
        $req_len = 0 + $req_params{'CONTENT_LENGTH'};
        if (($req_params{'REQUEST_METHOD'} eq 'POST') && ($req_len != 0) ){
            my $bytes_read = 0;
            while ($bytes_read < $req_len) {
                my $data = '';
                my $bytes = read(STDIN, $data, ($req_len - $bytes_read));
                last if ($bytes == 0 || !defined($bytes));
                $stdin_passthrough .= $data;
                $bytes_read += $bytes;
            }
        }


        #running the cgi app
        if ( (-x $req_params{SCRIPT_FILENAME}) &&  #can I execute this?
            (-s $req_params{SCRIPT_FILENAME}) &&  #Is this file empty?
            (-r $req_params{SCRIPT_FILENAME})     #can I read this file?
        ){
            pipe(CHILD_RD, PARENT_WR);
            pipe(PARENT_RD, CHILD_WR);
            pipe(PARENT_ERR_RD, CHILD_ERR_WR);

            my $pid = fork();
            unless(defined($pid)) {
                print("Content-type: text/plain\r\n\r\n");
                print "Error: CGI app returned no output - ";
                print "Executing $req_params{SCRIPT_FILENAME} failed !\n";
                next;
            }
            if ($pid > 0) {
                # Avoid waiting for eof on pipe!!!
                close(CHILD_RD);
                close(CHILD_WR);
                close(CHILD_ERR_WR);

                print PARENT_WR $stdin_passthrough;
                close(PARENT_WR);

                while(my $s = <PARENT_RD>) { print $s; }
                close(PARENT_RD);
                while(my $s = <PARENT_ERR_RD>) { print STDERR $s; }
                close(PARENT_ERR_RD);

                waitpid($pid, 0);
            } else {
                foreach $key ( keys %req_params){
                    $ENV{$key} = $req_params{$key};
                }
                # cd to the script's local directory
                if ($req_params{SCRIPT_FILENAME} =~ /^(.*)\/[^\/]+$/) {
                    chdir $1;
                }

                # Avoid waiting for eof on pipe!!!
                close(PARENT_RD);
                close(PARENT_WR);
                close(PARENT_ERR_RD);

                syscall(&SYS_dup2, fileno(CHILD_RD), 0);
                syscall(&SYS_dup2, fileno(CHILD_WR), 1);
                syscall(&SYS_dup2, fileno(CHILD_ERR_WR), 2);
                exec($req_params{SCRIPT_FILENAME});
                die("exec failed");
            }
        }
        else {
            print("Content-type: text/plain\r\n\r\n");
            print "Error: No such CGI app - $req_params{SCRIPT_FILENAME} may not ";
            print "exist or is not executable by this process.\n";
        }

    }
}
