# ---+ Extensions
# ---++ PiwikPlugin
# This is the configuration used by the <b>PiwikPlugin</b>.

# **BOOLEAN**
# Toggle for extra plugin debug messages.
$Foswiki::cfg{PiwikPlugin}{Debug} = 0;

# **STRING**
# Endpoint of the Piwik Tracker's REST api
$Foswiki::cfg{PiwikPlugin}{ApiUrl} = "http://localhost/piwik/piwik.php";

# **NUMBER**
# The site id. Look up the trackring code for "idsite".
$Foswiki::cfg{PiwikPlugin}{SiteId} = 1;

# **PERL**
# This is a list of custom-variable definitions. (see http://piwik.org/docs/custom-variables/).
# Each definition is defined by:
# id: a unique index number for this variable,
# scope: scope of variable, can be "visit" or "page",
# name: the clear-text name of this variable, and
# value: the actual value; you may use macros to compute the value on runtime.
$Foswiki::cfg{PiwikPlugin}{CustomVariable} = [
  {
    id => 1,
    scope => "visit",
    name => "Language",
    value => "%LANGUAGE%"
  },  
];

1;
