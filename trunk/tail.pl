#!/usr/bin/perl

use File::Tail;

my $ref=tie *FH,"File::Tail",(name=>"/var/log/messages",maxinterval=>1,interval=>1);

$path = "/home/user/phones";

while (<FH>) {
  if ( ($ip,$mac,$hostname) = /DHCPACK on (\S+) to (\S+) \((\S+)\)/ ) {
    unless (-e "$path/data/$hostname") {
      open(PHONE, "> $path/data/$hostname");
      print PHONE "$ip $mac $hostname\n";
      close(PHONE);
      print "Starting phone_init.pl $ip $hostname\n";
      system("perl $path/phone_init.pl $ip $hostname &");
    }
  }
}
