#!/usr/bin/perl -w
use strict;

# synopsis: export PS1='$(gitprompt.pl)
#
# Trailing symbols:
#   $(gitprompt.pl "[%b%c%u]" c=\+ u=\~)'
# Change branchname color:
#   $(gitprompt.pl "[%c%u%b%e[0m]" c=%e[32m u=%e[31m)'
#
# Format codes:
#   %b - current branch name
#   %c - to-be-committed flag
#   %u - touched-files flag
#   %e - ascii escape
# Definitions:
#   c  - string to use for %c, defaults to 'c'
#   u  - string to use for %u, defaults to 'u'
#   nc - string to use when %c could not be determined ("no c"), defaults to c."?"
#   nu - string to use when %u could not be determined ("no u"), defaults to u."?"
 
use IO::Handle;
use IPC::Open3;
use Time::HiRes qw(time);
 
chomp(my $headref = `git symbolic-ref HEAD 2>&1`);
exit if $headref =~ /fatal: Not a git repository/;

my $format = '(%b)[%c%u]';
my %opt = (
  c => 'c',
  u => 'u',
);
if (@ARGV) {
  $format = shift;
  foreach (@ARGV) {
    die "invalid parameter $_" unless /^(\w+)\=(.*?)$/;
    $opt{$1} = $2;
  }
}
$opt{nc} = $opt{c}.'?' unless exists $opt{nc};
$opt{nu} = $opt{u}.'?' unless exists $opt{nu};
foreach my $opt (keys %opt) {
  $opt{$opt} =~ s/\%e/\e/g;
}

my $branch;
if ($headref eq 'fatal: ref HEAD is not a symbolic ref') {
  # get commit id for lookup and fallback
  chomp($branch = `git rev-parse --short HEAD 2>&1`);

  # find gitdir
  chomp(my $gitdir = `git rev-parse --git-dir`);

  # parse HEAD log
  open(HEADLOG, "$gitdir/logs/HEAD");
  my $lastrelevant = '';
  while (<HEADLOG>) {
    $lastrelevant = $_ if /^\s*\w+\s+$branch\w+\s/;
  }

  # if the log mentions switching to the commit id, use whatever it calls it
  $branch = $1 if $lastrelevant =~ /\scheckout\:\s+moving\s+from\s+\S+\s+to\s+(\S+)\s*$/;
} elsif ($headref =~ /^refs\/heads\/(.+?)\s*$/) {
  # normal branch
  $branch = $1;
} else {
  # unexpected input
  $headref =~ s/[^\x20-\x7e]//g;
  print "!$headref!";
  exit;
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
      $status_c = $opt{c};
    } elsif (/Changed but not updated/) {
      $status_u = $opt{u};
    }
  }
 
  $running = kill 0 => $statuspid;
  select undef, undef, undef, .001; #yield, actually
  $waiting = time < $start + .5;
}

if (!$waiting) {
  # if we gave up waiting, we don't know things
  $status_c = $opt{nc} unless defined $status_c;
  $status_u = $opt{nu} unless defined $status_u;
} else {
  # if it's not still alive, we know everything
  $status_c = "" unless defined $status_c;
  $status_u = "" unless defined $status_u;
}

my $str = $format;
my %formatvalue = (
  b => $branch,
  u => $status_u,
  c => $status_c,
  e => "\e",
);
$str =~ s/\%(\w)/exists $formatvalue{$1} ? $formatvalue{$1} : '%'.$1/ge;
print $str;
