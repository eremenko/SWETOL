#!/usr/bin/perl
#
# Copyright (C) 2012 Sergey A.Eremenko (eremenko.s@gmail.com)
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#

use strict ;
use warnings ;

use Getopt::Long ;
use IO::File ;
use IPC::Open2 ;

my $verbose = 0 ;
my $config = "oonfig" ;
my $tc_binary = "/sbin/tc" ;
my $iptables_binary = "/sbin/iptables" ;
my $interface = "eth2" ;

my %superusers ;
my %superusers_src ;
my %default_users ;
my %default_users_src ;
my $default_delay = "5ms" ;
my %bad_users ;
my %bad_users_src ;
my $bad_users_delay = "15ms" ;

sub Help() {
	warn "Usage: $0 [options]
Options are:
	--help		- show this help
	--config=file
	-C file		- use config in 'file', default 'config'
	--verbose
	-v		- use verbose output
	--quiet
	-q		- be quiet, default
	--interface if
	-I if		- use interface 'if', default 'eth2'
	--tc=path	- binary of tc
	--iptables=path	- binary of iptables
\n" ;
	exit 0 ;
}

sub Execute {
	my ($prog,@args) = @_ ;
	my ($chld_out,$chld_in) ;

	if ($verbose) {
		print "Execute:",join(" ",$prog,@args),"\n" ;
	}
	my $pid = open2($chld_out,$chld_in,$prog,@args) ;
	
	waitpid ($pid,0) ;
	my $child_exit_status = $? >> 8 ;

	if ($child_exit_status) {
		warn "Error during execute: ",join(" ",$prog,@args),"\n" ;
		my $s = <$chld_out> ;
		warn "Output is: ",$s,"\n" if ($s);
		return 0 ;
	}
	if ($verbose) {
		print <$chld_out> ;
	}
	return 1 ;
}

my $rc = GetOptions(
	'config|C=s'	=> \$config,
	'verbose|v'	=> \$verbose,
	'quiet|q'	=> sub { $verbose = 0 ; },
	'tc=s'		=> \$tc_binary,
	'iptables=s'	=> \$iptables_binary,
	'interface|I=s'	=> \$interface,
	'help'		=> sub { &Help() ; },
) ;

if ($verbose) { warn "Opening config $config\n" ; }
my $fh = IO::File->new($config,"r") or die "Cannot open $config: $!\n" ;
while (<$fh>) {
	s{#.*$}{} ;
	s{^\s+}{} ;
	s{\s+$}{} ;
	next if ($_ eq "") ;

	if (m{^(superusers)\s*=\s*(.*)$}) {
		foreach my $net (split(m{\s+},$2)) {
			$superusers{$net} = 1 ;
		}
	}
	elsif (m{^(superusers_src)\s*=\s*(.*)$}) {
		foreach my $net (split(m{\s+},$2)) {
			$superusers_src{$net} = 1 ;
		}
	}
	elsif (m{^(default_users)\s*=\s*(.*)$}) {
		foreach my $net (split(m{\s+},$2)) {
			$default_users{$net} = 1 ;
		}
	}
	elsif (m{^(default_users_src)\s*=\s*(.*)$}) {
		foreach my $net (split(m{\s+},$2)) {
			$default_users_src{$net} = 1 ;
		}
	}
	elsif (m{^(default_delay)\s*=\s*(.*)$}) {
		$default_delay = $2 ;
	}
	elsif (m{^(bad_users)\s*=\s*(.*)$}) {
		foreach my $net (split(m{\s+},$2)) {
			$bad_users{$net} = 1 ;
		}
	}
	elsif (m{^(bad_users_src)\s*=\s*(.*)$}) {
		foreach my $net (split(m{\s+},$2)) {
			$bad_users_src{$net} = 1 ;
		}
	}
	elsif (m{^(bad_users_delay)\s*=\s*(.*)$}) {
		$bad_users_delay = $2 ;
	}
	else {
		warn "Invalid line $_ at $config\n" ;
	}
}
close $fh ;
if ($verbose) {
	print "Config are:\n",
		"superusers=",join(" ",keys %superusers),"\n",
		"superusers_src=",join(" ",keys %superusers_src),"\n",
		"default_users=",join(" ",keys %default_users),"\n",
		"default_users_src=",join(" ",keys %default_users_src),"\n",
		"default_delay=",$default_delay,"\n",
		"bad_users_users=",join(" ",keys %bad_users),"\n",
		"bad_users_users_src=",join(" ",keys %bad_users_src),"\n",
		"bad_users_delay=",$bad_users_delay,"\n"
	;
}

my @tc_show = (
[ $tc_binary,'-s','qdisc','show','dev',$interface ],
[ $tc_binary,'-s','class','show','dev',$interface ],
[ $tc_binary,'-s','filter','show','dev',$interface ],
) ;

if ($verbose) {
	print "TC config at start are:\n" ;
	foreach my $ref (@tc_show) {
		if (!Execute(@{$ref})) {
			last ;
		}
	}
}

my @tc_delete = (
[ $tc_binary,'qdisc','del','dev',$interface,'root' ],
) ;

if ($verbose) {
	print "Deleting TC config\n" ;
}
Execute (@{$tc_delete[0]}) ;

my @tc_add = (
[ $tc_binary,'qdisc','add','dev',$interface,'root','handle','1:','prio','bands','3','priomap','0','0','0','0','0','0','0','0','0','0','0','0','0','0','0','0' ],
#[ $tc_binary,'qdisc','add','dev',$interface,'parent','1:1','handle','10:' ],
[ $tc_binary,'qdisc','add','dev',$interface,'parent','1:2','handle','20:','netem','delay',$default_delay ],
[ $tc_binary,'qdisc','add','dev',$interface,'parent','1:3','handle','30:','netem','delay',$bad_users_delay ],
[ $tc_binary,'filter','add','dev',$interface,'protocol','ip','parent','1:0','prio','1','handle','32','fw','flowid','1:2' ],
[ $tc_binary,'filter','add','dev',$interface,'protocol','ip','parent','1:0','prio','2','handle','3246','fw','flowid','1:3' ],
) ;

if ($verbose) {
	print "Making TC config\n" ;
}
foreach my $ref (@tc_add) {
	if (!Execute(@{$ref})) {
		last ;
	}
}
if ($verbose) {
	print "TC config after are:\n" ;
	foreach my $ref (@tc_show) {
		if (!Execute(@{$ref})) {
			last ;
		}
	}
}

my @iptables_list = (
[ $iptables_binary,'-t','mangle','-L', '-n', '-v'],
) ;
if ($verbose) {
	print "IPTABLES mangle before config are:\n" ;
	Execute (@{$iptables_list[0]}) ;
}

my @iptables_delete_chain = (
[ $iptables_binary,'-t','mangle','-D','POSTROUTING','-j','POSTROUTING-DELAY'],
[ $iptables_binary,'-t','mangle','-F','POSTROUTING-DELAY'],
[ $iptables_binary,'-t','mangle','-X','POSTROUTING-DELAY'],
) ;

if ($verbose) {
	print "IPTABLES deleting chain\n",
}
foreach my $ref (@iptables_delete_chain) {
	if (!Execute(@{$ref})) {
	#	last ;
	}
}

my @iptables_insert_chain = (
[ $iptables_binary,'-t','mangle','-N','POSTROUTING-DELAY'],
[ $iptables_binary,'-t','mangle','-I','POSTROUTING','1','-j','POSTROUTING-DELAY'],
) ;

foreach my $ip (keys %superusers) {
	push (@iptables_insert_chain,
		[ $iptables_binary,'-t','mangle','-A','POSTROUTING-DELAY','-d',$ip,'-j','RETURN']) ;
}
foreach my $ip (keys %superusers_src) {
	push (@iptables_insert_chain,
		[ $iptables_binary,'-t','mangle','-A','POSTROUTING-DELAY','-s',$ip,'-j','RETURN']) ;
}
foreach my $ip (keys %bad_users) {
	push (@iptables_insert_chain,
		[ $iptables_binary,'-t','mangle','-A','POSTROUTING-DELAY','-d',$ip,'-j','MARK','--set-mark','3246']) ;
}
foreach my $ip (keys %bad_users_src) {
	push (@iptables_insert_chain,
		[ $iptables_binary,'-t','mangle','-A','POSTROUTING-DELAY','-s',$ip,'-j','MARK','--set-mark','3246']) ;
}
foreach my $ip (keys %default_users) {
	push (@iptables_insert_chain,
		[ $iptables_binary,'-t','mangle','-A','POSTROUTING-DELAY','-d',$ip,'-j','MARK','--set-mark','32']) ;
}
foreach my $ip (keys %default_users_src) {
	push (@iptables_insert_chain,
		[ $iptables_binary,'-t','mangle','-A','POSTROUTING-DELAY','-s',$ip,'-j','MARK','--set-mark','32']) ;
}

if ($verbose) {
	print "IPTABLES inserting chain\n",
}
foreach my $ref (@iptables_insert_chain) {
	if (!Execute(@{$ref})) {
	#	last ;
	}
}

if ($verbose) {
	print "IPTABLES mangle after config are:\n" ;
	Execute (@{$iptables_list[0]}) ;
}

__END__

