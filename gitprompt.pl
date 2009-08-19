#!/usr/bin/perl -w
use strict;

# Synopsis:
#   export PS0='[\t]\[\e[36m\]%{(%b)\[\e[0;1m\][%c%u%f%t]%}\[\e[0m\]\u\$ '
#   export PROMPT_COMMAND='export PS1=$(gitprompt.pl statuscount=1)'
#
# Examples:
#   Trailing symbols:
#     export PS0='...%{[%b\[\e[0m\]%c%u%f%t\[\e[30;1m\]]%}\[\e[0m\]...'
#     export PROMPT_COMMAND='export PS1=$(gitprompt.pl c=\+ u=\~ f=\* statuscount=1)'
#   Change branchname color:
#     export PS0='%{[\[%f%c%u%t\]%b\[\e[0m\]]%}\[\e[0m\]\u\$ '
#     export PROMPT_COMMAND='export PS1=$(gitprompt.pl c=%e[32m u=%e[31m f=%e[35m t=%e[30\;1m)'
#
# Format codes:
#   %b - current branch name
#   %c - to-be-committed flag
#   %u - touched-files flag
#   %f - untracked-files flag
#   %t - timeout flag
#   %g - is-git-repo flag
#   %e - ascii escape
#   %[ - literal '\[' to mark the start of nonprinting characters for bash
#   %] - literal '\]' to mark the end of nonprinting characters for bash
#   %% - literal '%'
#   %{ - begin conditionally printed block, only shown if a nonliteral expands within
#   %} - end conditionally printed block
# Options:
#   c           - string to use for %c; defaults to 'c'
#   u           - string to use for %u; defaults to 'u'
#   f           - string to use for %f; defaults to 'f'
#   t           - string to use for %t; defaults to '?'
#   g           - string to use for %g; defaults to the empty string (see %{)
#   statuscount - boolean; whether to suffix %c/%u with counts ("c4u8")

use IO::Handle;
use IPC::Open3;
use Time::HiRes qw(time);

### prechecks ###
my $ps0 = $ENV{PS0};
unless ($ps0) {
  print "!define PS0!";
  exit 1;
}

### global definitions ###
my %formatliteral = (
  e => "\e",
  '%' => '%',
  '[' => "\\[",
  ']' => "\\]",
);

my %formatvalue = %{gitdata()};
my $output = "";
my @ps0 = split(/\%\{(.*?)\%\}/, $ps0);
my $conditional = 0;
foreach my $part (@ps0) {
  if ($conditional) {
    my $keep = 0;
    $part =~ s/\%(.)/exists $formatliteral{$1} ? $formatliteral{$1} : exists $formatvalue{$1} ? (($keep=1),$formatvalue{$1}) : ''/ge;
    $output .= $part if $keep;
  } else {
    $part =~ s/\%(.)/exists $formatliteral{$1} ? $formatliteral{$1} : exists $formatvalue{$1} ? $formatvalue{$1} : ''/ge;
    $output .= $part;
  }
  $conditional = !$conditional;
}
$output = "\\[\e[0;30;41m\\]! $formatvalue{error} !\\[\e[0m\\]$output" if exists $formatvalue{error};
print $output;

sub gitdata {
  ### prechecks ###
  chomp(my $headref = `git symbolic-ref HEAD 2>&1`);
  return {} if $headref =~ /fatal: Not a git repository/i;

  ### definitions ###
  my %opt = (
    c => 'c',
    u => 'u',
    f => 'f',
    t => '?',
    g => '',
    statuscount => 0,
  );

  ### read options ###
  if (@ARGV) {
    foreach (@ARGV) {
      return {error=>"invalid parameter $_"} unless /^(\w+)\=(.*?)$/;
      my ($key,$val) = ($1,$2);
      $val =~ s/\%(.)/exists $formatliteral{$1} ? $formatliteral{$1} : ''/ge;
      $opt{$key} = $val;
    }
  }

  ### collect branch data ###
  my $branch;
  if ($headref =~ /fatal: ref HEAD is not a symbolic ref/i) {
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
    return {error=>$headref};
  }
 
  ### collect status data ###
  $SIG{CHLD} = sub { wait(); };
  my ($statusout, @status);
  my $statuspid = open3(undef,$statusout,undef,"git status");
  $statusout->blocking(0);
  my ($running, $waiting, $start) = (1, 1, time);
  while ($running && $waiting) {
    while (<$statusout>) {
      push @status, $_;
    }
 
    $running = kill 0 => $statuspid;
    select undef, undef, undef, .001; #yield, actually
    $waiting = time < $start + .5;
  }

  ### parse status data ###
  my %statuscount;
  my %sectionmap = (
    'Changes to be committed' => 'c',
    'Changed but not updated' => 'u',
    'Untracked files' => 'f',
  );
  if (!$running) {
    # if it terminated, parse output
    my ($section);
    foreach (@status) {
      if (/^\# (\S.+?)\:\s*$/ && exists $sectionmap{$1}) {
        $section = $sectionmap{$1};
      } elsif ($section && /^\#\t\S/) {
			  $statuscount{$section}++;
      }
    }
  }

  ### produce output ###
  my %formatvalue = (
    b => $branch,
    t => $running ? $opt{t} : '',
    g => $opt{g},
  );
  foreach my $flag (values %sectionmap) {
    $formatvalue{$flag} = $statuscount{$flag} ? ($opt{$flag}.($opt{statuscount} ? $statuscount{$flag} : '')) : '';
  }
  return \%formatvalue;
}
