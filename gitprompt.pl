#!/usr/bin/perl -w
use strict;

use IO::Handle;
use IPC::Open3;
use Time::HiRes qw(time);

chomp(my $headref = `git symbolic-ref HEAD 2>&1`);
exit if $headref =~ m/fatal: Not a git repository/;

my $branch;
if ($headref eq 'fatal: ref HEAD is not a symbolic ref') {
  chomp($branch = `git show-ref --hash --abbrev HEAD 2>&1`);
} elsif ($headref =~ /^refs\/heads\/(.+?)\s*$/) {
  $branch = $1;
} else {
  $branch = "??";
}

my ($statusout);
$SIG{CHLD} = sub { wait(); };
my $statuspid = open3(undef,$statusout,undef,"git status");
$statusout->blocking(0);

my ($status_c, $status_u);
my ($running, $waiting, $start) = (1, 1, time);
while ($running && $waiting) {
  while (<$statusout>) {
    if (/Changes to be committed/) {
      $status_c = "c";
    } elsif (/Changed but not updated/) {
      $status_u = "u";
    }
  }

  $running = kill 0 => $statuspid;
  select undef, undef, undef, .001; #yield, actually
  $waiting = time < $start + .5;
}

if (!$waiting) {
  # if we gave up waiting, we don't know things
  $status_c = "c?" unless defined $status_c;
  $status_u = "u?" unless defined $status_u;
} else {
  # if it's not still alive, we know everything
  $status_c = "" unless defined $status_c;
  $status_u = "" unless defined $status_u;
}

print "($branch)[$status_c$status_u]";
