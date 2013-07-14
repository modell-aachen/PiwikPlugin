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

package Foswiki::Plugins::PiwikPlugin::Tracker;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins ();
use Error qw(:try);
use LWP::UserAgent ();
use URI ();
use Digest::MD5();
use JSON();

use constant DRY => 0; # toggle me

################################################################################
sub new {
  my $class = shift;

  my $this = bless({
    apiUrl => $Foswiki::cfg{PiwikPlugin}{ApiUrl},
    userAgent => LWP::UserAgent->new(
      agent => "Foswiki Piwik Client",
      timeout => 2, # make it short
    ),
    gotErrors => 0,
    @_
  }, $class);

  return $this;
}

################################################################################
sub isEnabled {
  my $this = shift;

  return $this->{gotErrors}?0:1;
}

################################################################################
sub init {
  my $this = shift;

  return unless $this->isEnabled;

  $this->_readVisitorState;

  my $request = Foswiki::Func::getRequestObject;
  my ($hour, $min, $sec) = Foswiki::Time::formatTime(time(), '$hours:$minutes:$seconds') =~ /^(.*):(.*):(.*)$/;

  $this->{params} = {
    rec => 1,
    apiv => 1,
    idsite => $Foswiki::cfg{PiwikPlugin}{SiteId},
    cs => $Foswiki::cfg{Site}{CharSet},
    url => $request->url(-full=>1, -path=>1, -query=>1),
    urlref => $request->referer || '',
    ua => $request->userAgent || '',
    lang => $request->header("accept-language"),
    h => $hour,
    m => $min,
    s => $sec,
    _id => $this->{currentVisitor}{id},
    _idvc => $this->{currentVisitor}{count},
  };

  $this->{customVariables}{visit} = undef;
  $this->{customVariables}{page} = undef;

  $this->{params}{_viewts} = $this->{currentVisitor}{lastVisit} 
    if defined $this->{currentVisitor}{lastVisit};

  if ($Foswiki::cfg{PiwikPlugin}{TokenAuth}) {
    $this->{params}{token_auth} = $Foswiki::cfg{PiwikPlugin}{TokenAuth};
    $this->{params}{cip} = $this->{currentVisitor}{remoteAddr};
  };
 
  $this->_saveVisitorState;

  return $this;
}

################################################################################
sub doTrackPageView {
  my ($this, $web, $topic) = @_;

  my $session = $Foswiki::Plugins::SESSION;

  $web ||= $session->{webName};
  $topic ||= $session->{topicName};

  _writeDebug("doTrackPageView($web, $topic)");

  my $webTitle = _getTopicTitle($web, $Foswiki::cfg{HomeTopicName});
  $webTitle = $web if $webTitle eq $Foswiki::cfg{HomeTopicName};

  my $topicTitle = $topic eq $Foswiki::cfg{HomeTopicName} ? $topic : _getTopicTitle($web, $topic);

  my $pageTitle = $webTitle . '/' . $topicTitle;

  my $response = $this->sendRequest($this->getUrlTrackPageView($pageTitle));

  _writeDebug("status=".$response->status_line) if ref($response);

  if (ref($response) && $response->is_error) {
    $this->{gotErrors} = 1;
    throw Error::Simple("Error talking to Piwik server, deactivating: ".$response->status_line);
  };

  return $response;
}

################################################################################
sub doTrackSiteSearch {
  my ($this, $keyword, $category, $countResults) = @_;

  _writeDebug("doTrackSiteSearch(".($keyword||'').", ".($category||'').", ".($countResults||'').")");
        
  my $response = $this->sendRequest($this->getUrlTrackSiteSearch($keyword, $category, $countResults));

  _writeDebug("status=".$response->status_line) if ref($response);

  if (ref($response) && $response->is_error) {
    $this->{gotErrors} = 1;
    throw Error::Simple("Error talking to Piwik server, deactivating: ".$response->status_line);
  };

  return $response;
}

################################################################################
sub getUrlTrackSiteSearch {
  my ($this, $keyword, $category, $countResults) = @_;

  my %params = ();
  $params{search} = $keyword if defined $keyword;
  $params{search_cat} = $category if defined $category;
  $params{search_count} = $countResults if defined $countResults;

  return $this->getUrl(%params);
}

################################################################################
sub getUrlTrackPageView {
  my ($this, $pageTitle) = @_;

  my %params = ();
  $params{action_name} = $pageTitle if defined $pageTitle;

  _writeDebug("pageTitle=".($pageTitle||''));

  return $this->getUrl(%params);
}

################################################################################
sub getUrl {
  my $this = shift;

  my $apiUrl = $this->{apiUrl};
  throw Error::Simple("apiUrl not defined") unless defined $apiUrl;

  throw Error::Simple("{SiteId} not defined please look up your configuration")
    unless defined $this->{params}{idsite};

  if (defined $this->{customVariables}{visit}) {
    $this->{params}{_cvar} = JSON::encode_json($this->{customVariables}{visit});
  }

  if (defined $this->{customVariables}{page}) {
    $this->{params}{cvar} = JSON::encode_json($this->{customVariables}{page});
  }

  my $request = Foswiki::Func::getRequestObject;
  $this->{params}{gt_ms} = int($request->getTime()*1000),

  my $uri = new URI($apiUrl);
  my %queryParams = ($uri->query_form, 
    %{$this->{params}},
    @_,
  );

  if ($Foswiki::cfg{PiwikPlugin}{Debug}) {
    foreach my $key (sort keys %queryParams) {
      _writeDebug("PARAMS: $key=$queryParams{$key}");
    }
  }

  $uri->query_form(%queryParams);

  return $uri;
}

################################################################################
sub sendRequest {
  my ($this, $uri) = @_;

  #_writeDebug("sendRequest ".$uri);

  return if DRY;
  return $this->{userAgent}->get($uri);
}

################################################################################
# Sets Visit Custom Variable.
# See http://piwik.org/docs/custom-variables/
#
# @param int $id Custom variable slot ID from 1-5
# @param string $name Custom variable name
# @param string $value Custom variable value
# @param string $scope Custom variable scope. Possible values: visit, page
#
sub setCustomVariable {
  my ($this, $id, $name, $value, $scope) = @_;

  $scope = 'visit' unless defined $scope;

  _writeDebug("setCustomVariable($id, $name, $value, $scope)");

  throw Error::Simple("Parameter id to setCustomVariable should be an integer")
    unless defined $id && $id =~ /^\d+$/;

  throw Error::Simple("Invalid scope '".($scope||"")."'")
    unless defined($scope) && $scope =~ /^(visit|page)$/;

  $this->{customVariables}{$scope}{$id} = [$name, $value];
}

################################################################################
# Returns the currently assigned Custom Variable stored in a first party cookie.
#
# @param int $id Custom Variable integer index to fetch from cookie. Should be a value from 1 to 5
# @param string $scope Custom variable scope. Possible values: visit, page
#
#
sub getCustomVariable {
  my ($this, $id, $scope) = @_;

  $scope = 'visit' unless defined $scope;

  throw Error::Simple("Parameter id to getCustomVariable should be an integer")
    unless defined $id && $id =~ /^\d+$/;

  throw Error::Simple("Invalid scope '".($scope||"")."'")
    unless defined($scope) && $scope =~ /^(visit|page)$/;

  my $entry = $this->{customVariables}{$scope}{$id};

  return unless defined $entry;
  return @$entry;
}


################################################################################
sub _getVisitorFileName {
  my $wikiName = shift;

  return Foswiki::Func::getWorkArea("PiwikPlugin") . '/' . _getVisitorId($wikiName) . '.txt';
}

################################################################################
sub _readVisitorState {
  my ($this, $user) = @_;

  my $wikiName = Foswiki::Func::getWikiName($user);
  my $file = _getVisitorFileName($wikiName);

  #_writeDebug("file=$file");

  my %record = ();
  if (-f $file) {
    my $data = Foswiki::Func::readFile($file);
    foreach my $line (split(/\n/, $data)) {
      next if $line =~ /^#/;
      if ($line =~ /^(.*)=(.*)$/) {
        $record{$1} = $2;
      }
    }
  }

  my $request = Foswiki::Func::getRequestObject;

  $record{user} = $user || 'guest' unless defined $record{user};
  $record{wikiName} = $wikiName unless defined $record{wikiName};
  $record{remoteAddr} = $request->remoteAddress();
  $record{id} = _getVisitorId($wikiName);
  $record{count}++;
  $record{firstVisit} = time unless defined $record{firstVisit};

  $this->{currentVisitor} = \%record;

  return $this;
}

################################################################################
sub _getVisitorId {
  my $wikiName = shift;

  my $id;
  my $request = Foswiki::Func::getRequestObject;

  if ($wikiName eq $Foswiki::cfg{DefaultUserWikiName}) {
    $id = $request->remoteAddress;
  } else {
    $id = $wikiName;
  }

  return Digest::MD5::md5_hex($id);
}

################################################################################
sub _saveVisitorState {
  my $this = shift;

  my $file = _getVisitorFileName($this->{currentVisitor}{wikiName});

  $this->{currentVisitor}{lastVisit} = time;

  my $data = '';
  foreach my $key (sort keys %{$this->{currentVisitor}}) {
    $data .= "$key=$this->{currentVisitor}{$key}\n";
  }

  Foswiki::Func::saveFile($file, $data);
}

################################################################################
sub _writeDebug {
  print STDERR "PiwikPlugin::Tracker - $_[0]\n" if $Foswiki::cfg{PiwikPlugin}{Debug};
}

################################################################################
sub _getTopicTitle {
  my ($web, $topic) = @_;

  my $topicTitle;

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic);

  my $field = $meta->get('FIELD', 'TopicTitle');
  if ($field) {
    $topicTitle = $field->{value};
    return $topicTitle if $topicTitle;
  }

  $field = $meta->get('PREFERENCE', 'TOPICTITLE');
  if ($field) {
    $topicTitle = $field->{value};
    return $topicTitle if $topicTitle;
  }

  return $topic;
}


1;
