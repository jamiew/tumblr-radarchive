// RADARCHIVE

// firebug decoy
if (!("console" in window) || !("firebug" in console)) {
  var names = ["log", "debug", "info", "warn", "error", "assert", "dir", "dirxml",
  "group", "groupEnd", "time", "timeEnd", "count", "trace", "profile", "profileEnd"];

  window.console = {};
  for (var i = 0; i < names.length; ++i)
    window.console[names[i]] = function() {};
}

// application
$(document).ready(function(){

  // hide things w/ click or ESC -- FIXME toggle just one binding
  $('body').click(function(){ $('#tags').hide(); });
  $(window).keydown(function(event){
    switch (event.keyCode) {       
      case 27:  // escape... in Firefox at least
        $('#tags').fadeOut('fast'); // with efx wordup
      break;
    }
  });

  var tagURL = '';
  // "tag this post" link -> tag menu
  $('a.tag').click(function(){
        
    // move 
    var offset = $(this).offset();
    $('#tags').css('left', offset.left ).css('top', offset.top + 3).show();
    
    // fix the target URL, we only create one instance
    var parent = $(this).parent().parent().parent();
    var newURL = '/tag/?id='+parent.attr('id').replace('post-','');
    // $(this).attr('href', newURL );
    tagURL = newURL; // TODO make nicer
    tagWall = $(this); // me too
    return false;
  });
  
  // link to actually choose a tag; submit onclick
  $('#tags a').click(function(){
    
    // submit to parent().href+tag
    var tag = '&tag='+$(this).attr('href').replace('#tag-','');
    var url = tagURL+tag;
    $.get(url, function(response){ tagWall.parent().html(response); }); // FIXME likely to break

    $('#tags').fadeOut('fast');    
    return false;
  });

});
