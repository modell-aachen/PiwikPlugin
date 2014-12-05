# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# PiwikPlugin is Copyright (C) 2013-2014 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::PiwikPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Sandbox ();
use Error qw(:try);

our $VERSION = '2.21';
our $RELEASE = '2.21';
our $SHORTDESCRIPTION = 'Server-side page tracking using Piwik';
our $NO_PREFS_IN_TOPIC = 1;
our $tracker;
our $doneTrackPageView = 0;

sub tracker {

  unless (defined $tracker) {
    require Foswiki::Plugins::PiwikPlugin::Tracker;
    $tracker = new Foswiki::Plugins::PiwikPlugin::Tracker();
  }

  return $tracker;
}

sub initPlugin {

  tracker->init;
  startDaemon() if $Foswiki::cfg{PiwikPlugin}{AutoStartDaemon};
  addToHead() if $Foswiki::cfg{PiwikPlugin}{TrackOutlinks};

  Foswiki::Func::registerRESTHandler(
    'doTrackAction', 
    sub { return tracker->restTrackAction(@_); },
    authenticate => 0,
    validate => 0,
    http_allow => 'GET,POST',
  );

  $doneTrackPageView = 0;

  return 1;
}

sub addToHead {
  Foswiki::Func::addToZone("script", "PIWIKPLUGIN", <<EOS, "JQUERYPLUGIN");
<script src='%PUBURLPATH%/%SYSTEMWEB%/PiwikPlugin/jquery.piwik.js'></script>
EOS
}

sub completePageHandler {
  trackPageView();
}

sub modifyHeaderHandler {
  trackPageView();
}

sub trackPageView {

  return if $doneTrackPageView;
  $doneTrackPageView = 1;

  return unless tracker->isEnabled;

  try {
    # set all custom variables
    if ($Foswiki::cfg{PiwikPlugin}{CustomVariable}) {
      foreach my $var (@{$Foswiki::cfg{PiwikPlugin}{CustomVariable}}) {
        tracker->setCustomVariable(
          $var->{id},
          $var->{name},
          Foswiki::Func::expandCommonVariables($var->{value}),
          $var->{scope},
        );
      }
    }
    
    tracker->doTrackPageView;

  } catch Error::Simple with {
    # report but ignore
    print STDERR "PiwikPlugin::Tracker - ".shift."\n";
  };
}

################################################################################
sub startDaemon {

  my $request = Foswiki::Func::getRequestObject();
  my $refresh = $request->param('refresh');
  $refresh = (defined($refresh) && $refresh =~ /^(on|piwik)$/) ? 1 : 0;

  my $pidFile = $Foswiki::cfg{PiwikPlugin}{PidFile};
  my $logFile = $Foswiki::cfg{PiwikPlugin}{LogFile};

  if ($pidFile && $logFile) {

    if ($Foswiki::cfg{PiwikPlugin}{Debug}) {
      print STDERR "PiwikPlugin - pidFile=$pidFile\n";
      print STDERR "PiwikPlugin - logFile=$logFile\n";
    }

    my $pid;

    $pid = Foswiki::Sandbox::untaint(
      Foswiki::Func::readFile($pidFile),
      sub {
        my $pid = shift;
        if ($pid =~ /^\s*(\d+)\s*$/) {
          return $1;
        }
      }
    ) unless $refresh;

    if ($pid && kill 0, $pid) {

      print STDERR "PiwikPlugin - piwik_daemon already running at $pid\n"
        if $Foswiki::cfg{PiwikPlugin}{Debug};

    } else {

      my $command = $Foswiki::cfg{PiwikPlugin}{DaemonCmd};
      $command .= " -restart" if $refresh;

      my ($stdout, $exit) = Foswiki::Sandbox->sysCommand(
        $command,
        PIDFILE => $pidFile,
        LOGFILE => $logFile,
      );

      print STDERR "PiwikPlugin - started piwik_daemon.\n"
        if $Foswiki::cfg{PiwikPlugin}{Debug};

      print STDERR "PiwikPlugin - stdout: $stdout\n" if $stdout;
    }

  } else {
    print STDERR "PiwikPlugin - Can't auto-start piwik_daemin: no {PidFile} or {LogFile}\n";
  }
}


1;
