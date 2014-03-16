#!/usr/bin/perl

# Original author: Denis S. Filimonov
# Patched by Lewin Bormann <lbo@spheniscida.de>
# Changes (quite much):
#   - Using STDIN as socket, for cooperation with Apache's mod_fcgid.
#   - No daemonization.
#   - No fork()s anymore, instead "inline" execution by first reading the
#     script and then executing it using eval().
#     This should result in far superior performance with perl scripts.

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

        #running the cgi app
        if ( (-x $req_params{SCRIPT_FILENAME}) &&  #can I execute this?
            (-s $req_params{SCRIPT_FILENAME}) &&  #Is this file empty?
            (-r $req_params{SCRIPT_FILENAME})     #can I read this file?
        ){
            foreach $key ( keys %req_params){
                $ENV{$key} = $req_params{$key};
            }
            my $script_content;
            open(SCRIPT,"<",$req_params{SCRIPT_FILENAME});
            {
                local $/;
                $script_content = <SCRIPT>;
            }
            close(SCRIPT);
            my $result = eval($script_content);

            unless(defined($result)) {
                print("Content-type: text/plain\n\n");
                print "Error: CGI app returned no output - ";
                print "Executing $req_params{SCRIPT_FILENAME} failed !\n";
                next;
            }
        }
        else {
            print("Content-type: text/plain\n\n");
            print "Error: No such CGI app - $req_params{SCRIPT_FILENAME} may not ";
            print "exist or is not executable by this process.\n";
        }

    }
}
