# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# PiwikPlugin is Copyright (C) 2013 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::PiwikPlugin::Daemon;

use strict;
use warnings;

use Filesys::Notify::Simple ();
use LWP::UserAgent ();
use URI ();
use File::Path qw(make_path);
use Time::HiRes ();

#use Data::Dumper ();

use constant DRY => 0; # toggle me
use constant PROFILE => 0; # toggle me

################################################################################
sub new {
  my $class = shift;

  my $this = bless({
    @_
  });

  die "apiUrl undefined" unless $this->{apiUrl};
  die "queueDir undefined" unless $this->{queueDir};

  unless (-d $this->{queueDir}) {
    $this->writeDebug("creating queueDir $this->{queueDir}");
    make_path($this->{queueDir}) || die "Can't create queueDir '$this->{queueDir}'";
  } else {
    $this->writeDebug("using queueDir $this->{queueDir}");
  }


  return $this;
}

################################################################################
sub watcher {
  my $this = shift;

  unless (defined $this->{watcher}) {
    $this->{watcher} = Filesys::Notify::Simple->new([$this->{queueDir}]);
  }

  return $this->{watcher};
}

################################################################################
sub userAgent {
  my $this = shift;

  unless (defined $this->{userAgent}) {
    $this->{userAgent} = LWP::UserAgent->new(
      agent => "Foswiki Piwik Client",
      timeout => $this->{timeout} || 2, # make it short
    );
  }

  return $this->{userAgent};
}

################################################################################
sub writeDebug {
  my $this = shift;

  return unless $this->{debug};
  print STDERR "PiwikPlugin::Daeomn - ".shift."\n";
}

################################################################################
sub writeLog {
  my $this = shift;

  return if $this->{quiet};
  print STDERR "PiwikPlugin::Daeomn - ".shift."\n";
}

################################################################################
sub run {
  my $this = shift;

  $this->writeDebug("### starting $0, PID=$$");

  # process existing files
  opendir(my $dh, $this->{queueDir}) || die "Can't open queueDir '$this->{queueDir}'";

  while (readdir($dh)) {
    next if /^\./;
    $this->processFile($this->{queueDir}.'/'.$_);
  }
  
  closedir($dh);

  # wait for new entries
  while (1) {
    $this->watcher->wait(sub {
      my $event = shift;
      $this->processFile($event->{path}) if $event;
    });
  }
}

################################################################################
sub processFile {
  my ($this, $path) = @_;

  return unless -f $path;
  #$this->writeDebug("processing file $path");

  my $response = $this->sendRequest($this->readRecord($path));

  return unless ref($response);

  if (!$response->is_error) {
    $this->writeDebug("deleting record");
    unlink $path unless DRY;
  }
}

################################################################################
sub readRecord {
  my ($this, $path) = @_;

  my $IN_FILE;
  open( $IN_FILE, '<', $path ) || die "Can't read record from '$path'";

  my %record = ();
  my $found = 0;
  while(<$IN_FILE>) {
    if (/^(.*?)=(.*)$/) {
      $found = 1;
      $record{$1} = $2;
    }
  }

  close($IN_FILE);

  return unless $found;

  return \%record;
}

################################################################################
sub sendRequest {
  my $this = shift;
  my $record = shift;

  return unless defined $record;

  my $uri = new URI($this->{apiUrl});
  my %queryParams = ($uri->query_form, 
    %{$record},
    @_,
  );

  $uri->query_form(%queryParams);

  $this->writeDebug("sendRequest: ".$uri);
  if (DRY) {
    $this->writeDebug("dry run ... ignoring!!");
    return;
  }

  my $startTime;

  if (PROFILE) {
    $startTime = [Time::HiRes::gettimeofday];
  }

  my $response = $this->userAgent->get($uri);

  if (PROFILE) {
    my $endTime = [Time::HiRes::gettimeofday];
    my $timeDiff = int(Time::HiRes::tv_interval($startTime, $endTime) * 1000);
    $this->writeLog("took ".$timeDiff."ms to talk to the backend");
  }

  if (ref($response) && $response->is_error) {
    $this->writeLog("Error talking to Piwik server: ".$response->status_line);
  }

  return $response;
}

1;
