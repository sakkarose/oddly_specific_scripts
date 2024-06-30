#!/usr/bin/perl -w

use strict;
use warnings;

select STDOUT; $| = 1;

while (<>)
{
   my @parts = split;
   my $url = $parts[0];
   if ($url =~ /example\.com/) 
   { 
      print "URL"; 
   }
   else
   {
      print "\n";
   }
}
