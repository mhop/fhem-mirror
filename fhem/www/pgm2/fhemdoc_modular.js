"use strict";
// $Id$

var fd_loadedHash={}, fd_loadedList=[], fd_all={}, fd_allCnt, fd_progress=0, 
    fd_lang, fd_offsets=[], fd_scrolled=0, fd_modLinks={}, csrfToken="X",
    fd_mode = "FHEM";
var fd_otherSrc = { "usb":"autocreate", "createlog":"autocreate" };


function
fd_status(txt)
{
  var errmsg = $("#errmsg");
  if(!$(errmsg).length) {
    $('#menu').append('<a style="display:block; padding-top:2em" '+
                         'id="errmsg" href="#"></a>');
    errmsg = $("#errmsg");
  }
  if(txt == "")
    $(errmsg).remove();
  else
    $(errmsg).html(txt);
}

function
fd_fC(fn, callback)
{
  console.log("fd_fC:"+fn);

  if(fd_mode == "FHEM") {
    var p = location.pathname;
    var cmd = p.substr(0,p.indexOf('/doc'))+'?cmd='+fn+csrfToken+'&XHR=1';
    $.ajax({
      url:cmd, method:'POST', cache:false, success:callback,
      error:function(xhr, status, err) {
        if(xhr.status == 400 && csrfToken) {
          csrfToken = "";
          fd_csrfRefresh(function(){fd_fC(fn, callback)});
        } else {
          console.log("FAIL ERR:"+xhr.status+" STAT:"+status);
        }
      }
    });

  } else { // static
    $.ajax({
      url:fn, method:'GET',
      success:function(ret) {
        callback('<html>'+ret+'</html>');
      },
      error:function(xhr, status, err) {
        callback("");
        console.log("FAIL ERR:"+xhr.status+" STAT:"+status);
        fd_status("Cannot load "+fn);
        setTimeout(function(){ fd_status("") }, 5000);
      }
    });
  }
}

// Dynamically load the codumentation of one module.
var inLoadOneDoc = false;
function
loadOneDoc(mname, lang)
{
  var origLink = mname;
  if(inLoadOneDoc)
    return;

  function
  done(err, calc)
  {
    if(fd_progress) {
      fd_status(fd_progress+" / "+fd_allCnt);
      if(++fd_progress > fd_allCnt) {
        fd_progress = 0;
        setTimeout(calcOffsets,100);   // Firefox returns wrong offsets
        fd_status("");
      }
    } else {
      if(calc)
        setTimeout(calcOffsets,100);

      inLoadOneDoc = true; // avoid the hashchange callback
      setTimeout(function(){ location.href = "#"+origLink; }, 100);

      // takes long if the complete doc is loaded
      setTimeout(function(){ inLoadOneDoc = false; }, 2000);
    }
  }

  if(fd_modLinks[mname])
    mname = fd_modLinks[mname];
  if(fd_loadedHash[mname] && fd_loadedHash[mname] == lang)
    return done(false, false);

  fd_fC(fd_mode=="FHEM" ? "help "+mname+" "+langC : 
                          "/cref"+(lang=="EN" ? "":"_"+lang)+"/"+mname+".cref",
  function(ret){
    if(ret.indexOf("<html>") != 0 || ret.indexOf("<html>No help found") == 0)
      return done(true, false);
    ret = ret.replace(/<\/?html>/g,'');
    ret = ret.replace(/Keine deutsche Hilfe gefunden!<br\/>/,'');
    ret = '<div id="FD_'+mname+'">'+ret+'</div>';
    ret = ret.replace(/target="_blank"/g, '');  // revert help URL rewrite
    ret = ret.replace(/href=".*?commandref.*?.html#/g, 'href="#');

    if(fd_loadedHash[mname])
      $("div#FD_"+mname).remove();

    if(!fd_loadedHash[mname])
      fd_loadedList.push(mname);
    fd_loadedHash[mname] = lang;
    fd_loadedList.sort();
    var idx=0;
    while(fd_loadedList[idx] != mname)
      idx++;
    var toIns = "perl";
    if(idx < fd_loadedList.length-1)
      toIns = fd_loadedList[idx+1];
    console.log("insert "+mname+" before "+toIns);
    $(ret).insertBefore("a[name="+toIns+"]");
    addAHooks("div#FD_"+mname);
    return done(false, true);
  });
}

// Add a hook for each <a> tag to load & scroll to the corresponding item
function
addAHooks(el)
{
  $(el).find("a[href]").each(function(){
    var href = $(this).attr("href");
    if(!href || href.indexOf("#") != 0)
      return;
    href = href.substr(1);
    if(fd_modLinks[href] && !fd_loadedHash[href]) {
      $(this).click(function(){
        $("a[href=#"+href+"]").unbind('click');
        loadOneDoc(href, fd_lang);
      });
    }
  });
}

// remember the offset of all loaded elements, to be able to dynamically show
// the correct "load <XXX> in other language" link
function
calcOffsets()
{
  fd_offsets=[];
  for(var i1=0; i1<fd_loadedList.length; i1++) {
    var cr = $("a[name="+fd_loadedList[i1]+"]").offset();
    fd_offsets.push(cr ? cr.top : -1);
  }
  checkScroll();
}

// Show the correct otherLang, see calcOffsets
function
checkScroll()
{
  if(!fd_scrolled) {
    setTimeout(checkScroll, 500);
    return;
  }
  fd_scrolled = 0;
  var viewTop=$(window).scrollTop(), viewBottom=viewTop+$(window).height();
  var idx=0;
  while(idx<fd_offsets.length) {
    if(fd_offsets[idx] >= viewTop && viewBottom > fd_offsets[idx]+30)
      break;
    idx++;
  }

  if(idx >= fd_offsets.length) {
    $("a#otherLang").hide();

  } else {
    var mname = fd_loadedList[idx];
    var l1 = fd_loadedHash[mname], l2 = (l1=="EN" ? "DE" : "EN");
    $("a#otherLang span.mod").html(mname);
    $("a#otherLang span[lang="+l1+"]").hide();
    $("a#otherLang span[lang="+l2+"]").show();
    $("a#otherLang").show();
  }
}

// Load the current entry in the other langueage
function
loadOtherLang()
{
  var mname = $("a#otherLang span.mod").html();
  loadOneDoc(mname, fd_loadedHash[mname]=="EN" ? "DE" : "EN");
}

// get the current csrf from FHEMWEB
function
fd_csrfRefresh(callback)
{
  if(fd_mode != "FHEM")
    return;
  console.log("fd_csrfRefresh");
  $.ajax({
    url:location.pathname.replace(/docs.*/,'')+"?XHR=1",
    success: function(data, textStatus, request){
      csrfToken = request.getResponseHeader('x-fhem-csrftoken');
      csrfToken = csrfToken ? ("&fwcsrf="+csrfToken) : "";
      if(callback)
        callback();
    }
  });
}


$(document).ready(function(){
  var p = location.pathname.split(/[_.]/);
  fd_lang = (p[1] == "modular" ? p[2] : p[1]);
  if(fd_lang == "html")
    fd_lang = "EN";

  if(location.host == "fhem.de" || location.host == "commandref.fhem.de")
    fd_mode = "static";


  $("div#modLinks").each(function(){
    var a1 = $(this).html().split(" ");
    for(var i1=0; i1<a1.length; i1++) {
      var a2 = a1[i1].split(/[:,]/);
      var mName = a2.shift();
      for(var i2=0; i2<a2.length; i2++)
        if(!fd_modLinks[a2[i2]])
          fd_modLinks[a2[i2]] = mName;
    }
  });

  $("a[name]").each(function(){ fd_loadedHash[$(this).attr("name")]=fd_lang; });
  $("table.summary td.modname a")
    .each(function(){ 
      var mod = $(this).html();
      fd_all[mod]=1;
      fd_modLinks[mod] = fd_modLinks[mod+"define"] = fd_modLinks[mod+"get"] = 
      fd_modLinks[mod+"set"] = fd_modLinks[mod+"attribute"]= mod;
    })
    .click(function(e){
      e.preventDefault();
      loadOneDoc($(this).html(), fd_lang);
    });

  for(var i1 in fd_otherSrc)
    fd_modLinks[i1] = fd_otherSrc[i1];

  if(location.hash && location.hash.length > 1)
    loadOneDoc(location.hash.substr(1), fd_lang);

  $(window).bind('hashchange', function() {
    if(location.hash.length > 1)
      loadOneDoc(location.hash.substr(1), fd_lang);
  });

  $("a[name=loadAll]").show().click(function(e){
    e.preventDefault();
    $("a[name=loadAll]").hide();
    location.href = "#doctop";
    fd_allCnt = 0;
    for(var m in fd_all) fd_allCnt++
    fd_progress = 1;
    for(var mname in fd_all)
      loadOneDoc(mname, fd_lang);
  });

  $("a#otherLang").click(loadOtherLang);
  addAHooks("body");

  window.onscroll = function(){ 
    if(!fd_scrolled++)
      setTimeout(checkScroll, 500);
  };

  fd_csrfRefresh();
});
