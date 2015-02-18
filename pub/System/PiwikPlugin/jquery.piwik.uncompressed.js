jQuery(function($) {
  var baseUrl = location.protocol + "//" + location.hostname + (location.port && ":" + location.port),
      pubUrl = foswiki.getPreference("PUBURL"),
      pubUrlPath = foswiki.getPreference("PUBURLPATH"),
      trackActionUrl = foswiki.getPreference("SCRIPTURL")+"/rest/PiwikPlugin/doTrackAction";

  $(document).on("click", "a", function() {
    var $this = $(this),
        href = $this.attr("href");

    if (typeof(href) !== 'undefined') {

      // is it an outgoing link?
      if (href.indexOf("http") == 0 && href.indexOf(baseUrl) != 0) {

        //console.log("external url clicked",href);

        // record it
        $.ajax({
          url: trackActionUrl, 
          async: false,
          data: {
            "action": "link",
            "url": href
          }
        }); 
      }

      // is it a link to an attachment?
      if (href.indexOf(pubUrl) == 0 || href.indexOf(pubUrlPath) == 0) {

        if (href.indexOf("/") == 0) {
          href = baseUrl+href;
        }
        //console.log("attachment clicked", href);

        // record it
        $.ajax({
          url: trackActionUrl, 
          async: false,
          data: {
            "action": "download",
            "url": href
          }
        }); 
      }
    }
  });
});
