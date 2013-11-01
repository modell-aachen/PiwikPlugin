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
use Digest::MD5();
use JSON();
use File::Temp ();
use File::Path qw(make_path);

################################################################################
sub new {
  my $class = shift;

  my $this = bless({
    queueDir => $Foswiki::cfg{PiwikPlugin}{QueueDir},
    excludePattern => $Foswiki::cfg{PiwikPlugin}{ExcludePattern},
    @_
  }, $class);

  unless (-d $this->{queueDir}) {
    writeDebug("creating queueDir $this->{queueDir}");
    make_path($this->{queueDir}) || die "Can't create queueDir '$this->{queueDir}'";
  }

  %{$this->{trackedActions}} = map {$_=>1} split(/\s*,\s*/, $Foswiki::cfg{PiwikPlugin}{TrackedActions} || 'edit,view,save');

  return $this;
}

################################################################################
sub init {
  my $this = shift;

  my $request = Foswiki::Func::getRequestObject;

  $this->readVisitorState;

  my ($hour, $min, $sec) = Foswiki::Time::formatTime(time(), '$hours:$minutes:$seconds') =~ /^(.*):(.*):(.*)$/;

  $this->{params} = {
    rec => 1,
    apiv => 1,
    idsite => $Foswiki::cfg{PiwikPlugin}{SiteId},
    cs => $Foswiki::cfg{Site}{CharSet},
    url => $request->url(-full=>1, -path=>1, -query=>1),
    urlref => $request->referer || '',
    ua => $request->userAgent || '',
    lang => $request->header("accept-language") || '',
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
    $this->{params}{cid} = $this->{currentVisitor}{id};
    #$this->{params}{cdt} = Foswiki::Time::formatTime(time(), '$year-$mo-$day $hours:$minutes:$seconds');# SMELL: does it need to be ... $day, $hours...?
    #$this->{params}{cdt} = time();
    #print STDERR "cdt=$this->{params}{cdt}\n";
  }

 
  $this->saveVisitorState;

  return $this;
}

################################################################################
sub isEnabled {
  my $this = shift;

  my $request = Foswiki::Func::getRequestObject;
  my $action = $request->action;
  unless (defined $this->{trackedActions}{$action}) {
    writeDebug("action '$action' isn't tracked");
    return 0;
  }

  if ($this->{excludePattern}) {
    my $session = $Foswiki::Plugins::SESSION;
    my $webTopic = $session->{webName}.'.'.$session->{topicName};
    $webTopic =~ s/\//./g;
    
    if ($webTopic =~ /$this->{excludePattern}/) {
      writeDebug("topic '$webTopic' isn't tracked");
      return 0;
    }
  }

  return 1;
}

################################################################################
sub restTrackAction {
  my ($this, $session, $subject, $verb, $response) = @_;

  my $request = Foswiki::Func::getRequestObject;

  my $action = $request->param("action");
  die "action parameter missing" unless defined $action;

  my $url = $request->param("url");
  die "url parameter missing" unless defined $url;

  return $this->doTrackAction($url, $action);
}

################################################################################
sub doTrackAction {
  my ($this, $url, $action) = @_;

  die "unknown action '$action'" unless $action =~ /^(download|link)$/;

  writeDebug("doTrackAction($url, $action)");

  return $this->queueRecord($this->createActionRecord($url, $action));
}

################################################################################
sub doTrackPageView {
  my ($this, $web, $topic) = @_;

  my $session = $Foswiki::Plugins::SESSION;

  $web ||= $session->{webName};
  $topic ||= $session->{topicName};

  writeDebug("doTrackPageView($web, $topic)");

  my $webTitle = getTopicTitle($web, $Foswiki::cfg{HomeTopicName});
  $webTitle = $web if $webTitle eq $Foswiki::cfg{HomeTopicName};
  my $topicTitle = $topic eq $Foswiki::cfg{HomeTopicName} ? $topic : getTopicTitle($web, $topic);
  my $pageTitle = $webTitle . '/' . $topicTitle;

  return $this->queueRecord($this->createPageViewRecord($pageTitle));
}

################################################################################
sub doTrackSiteSearch {
  my ($this, $keyword, $category, $countResults) = @_;

  writeDebug("doTrackSiteSearch(".($keyword||'').", ".($category||'').", ".($countResults||'').")");
        
  return $this->queueRecord($this->createSiteSearchRecord($keyword, $category, $countResults));
}

################################################################################
sub createSiteSearchRecord {
  my ($this, $keyword, $category, $countResults) = @_;

  my $record = $this->createTrackerRecord;
  $record->{search} = $keyword if defined $keyword;
  $record->{search_cat} = $category if defined $category;
  $record->{search_count} = $countResults if defined $countResults;

  return $record;
}

################################################################################
sub createActionRecord {
  my ($this, $url, $action) = @_;

  my $record = $this->createTrackerRecord;
  $record->{$action} = $url;
  $record->{url} = $url;

  return $record;
}

################################################################################
sub createPageViewRecord {
  my ($this, $pageTitle) = @_;

  my $record = $this->createTrackerRecord;
  $record->{action_name} = $pageTitle if defined $pageTitle;

  return $record;
}

################################################################################
sub createTrackerRecord {
  my $this = shift;

  my %record = %{$this->{params}};
  
  if (defined $this->{customVariables}{visit}) {
    $record{_cvar} = JSON::encode_json($this->{customVariables}{visit});
  }

  if (defined $this->{customVariables}{page}) {
    $record{cvar} = JSON::encode_json($this->{customVariables}{page});
  }

  my $request = Foswiki::Func::getRequestObject;
  $record{gt_ms} = int($request->getTime()*1000),

  return \%record;
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

  #writeDebug("setCustomVariable($id, $name, $value, $scope)");

  die "Parameter id to setCustomVariable should be an integer"
    unless defined $id && $id =~ /^\d+$/;

  die "Invalid scope '".($scope||"")."'"
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

  die "Parameter id to getCustomVariable should be an integer"
    unless defined $id && $id =~ /^\d+$/;

  die "Invalid scope '".($scope||"")."'"
    unless defined($scope) && $scope =~ /^(visit|page)$/;

  my $entry = $this->{customVariables}{$scope}{$id};

  return unless defined $entry;
  return @$entry;
}


################################################################################
sub getVisitorFileName {
  my $wikiName = shift;

  my $visitorsDir = Foswiki::Func::getWorkArea("PiwikPlugin") . '/visitors';
  mkdir $visitorsDir unless -d $visitorsDir;

  return $visitorsDir . '/' . getVisitorId($wikiName) . '.txt';
}

################################################################################
sub readVisitorState {
  my ($this, $wikiName) = @_;

  $wikiName ||= Foswiki::Func::getWikiName();
  my $file = getVisitorFileName($wikiName);

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

  $record{wikiName} = $wikiName unless defined $record{wikiName};
  $record{remoteAddr} = $request->remoteAddress();
  $record{id} = substr(getVisitorId($wikiName), 0, 16);
  $record{count}++;
  $record{firstVisit} = time unless defined $record{firstVisit};

  $this->{currentVisitor} = \%record;

  writeDebug("file=$file, wikiName=$record{wikiName}, id=$record{id}");


  return $this;
}

################################################################################
sub getVisitorId {
  my $wikiName = shift;

  my $id;
  my $request = Foswiki::Func::getRequestObject;

  if ($wikiName eq $Foswiki::cfg{DefaultUserWikiName}) {
    $id = $request->remoteAddress;
  } else {
    $id = $wikiName;
  }

  #writeDebug("called getVisitorId($wikiName) id=$id");

  return Digest::MD5::md5_hex($id);
}

################################################################################
sub saveVisitorState {
  my $this = shift;

  my $file = getVisitorFileName($this->{currentVisitor}{wikiName});

  $this->{currentVisitor}{lastVisit} = time;

  my $data = '';
  foreach my $key (sort keys %{$this->{currentVisitor}}) {
    $data .= "$key=$this->{currentVisitor}{$key}\n";
  }

  Foswiki::Func::saveFile($file, $data);
}

################################################################################
sub queueRecord {
  my ($this, $record) = @_;

  my $file = File::Temp->new(
    UNLINK => 0,
    DIR => $this->{queueDir},
    SUFFIX => '.txt',
  );

  #writeDebug("record at '$file'");

  while (my ($key, $val) = each %$record) {
    next unless defined $val;
    next unless defined $key;
    print $file "$key=$val\n" or die "Can't write to file '$file'";
  }

  close($file);
}

################################################################################
sub writeDebug {
  print STDERR "PiwikPlugin::Tracker - $_[0]\n" if $Foswiki::cfg{PiwikPlugin}{Debug};
}

################################################################################
sub getTopicTitle {
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

################################################################################
sub urlEncode {
  my $text = shift;

  $text =~ s/([^0-9a-zA-Z-_.:~!*'\/])/'%'.sprintf('%02x',ord($1))/ge;

  return $text;
}


1;
