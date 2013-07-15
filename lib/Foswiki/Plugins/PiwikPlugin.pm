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

package Foswiki::Plugins::PiwikPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Error qw(:try);

use version; our $VERSION = version->declare("v1.99.0_001");
our $RELEASE = '15 Jul 2013';
our $SHORTDESCRIPTION = 'Server-side page tracking using Piwik';
our $NO_PREFS_IN_TOPIC = 1;
our $tracker;

sub tracker {

  unless (defined $tracker) {
    require Foswiki::Plugins::PiwikPlugin::Tracker;
    $tracker = new Foswiki::Plugins::PiwikPlugin::Tracker();
  }

  return $tracker;
}

sub initPlugin {

  tracker->init;

  return 1;
}

sub completePageHandler {

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

1;
