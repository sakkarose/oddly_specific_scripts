#!/usr/bin/perl -w

use IO::Handle;
use POSIX strftime;

$imageURL = "IMAGE URL";

$|=1;
$pid = $$;

while (<>) {
   chomp $_;
   if ($_ =~ m/.*$imageURL/) 
   {
      print "$imageURL\n";
   }
   elsif ($_ =~ /(.*\.(gif|png|bmp|tiff|ico|jpg|jpeg))/i) 
   {
      print "$imageURL\n";
   }
   else {
      print "$_\n";
   }
}
