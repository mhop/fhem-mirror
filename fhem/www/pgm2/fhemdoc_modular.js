var fd_Hash={}, fd_List=[], fd_All={}, fd_AllCnt, fd_Progress=0, fd_Lang,
    fd_Offsets=[], scrolled=0;


function
fd_status(txt)
{
  var errmsg = $("#errmsg");
  if(!$(errmsg).length) {
    $('#menuScrollArea').append('<div id="errmsg">');
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
  var p = location.pathname;
  var cmd = p.substr(0,p.indexOf('/doc'))+
                '?cmd='+fn+
                (typeof(csrfToken)!='undefined'?csrfToken:'')+
                '&XHR=1';
  var ax = $.ajax({ cache:false, url:cmd });
  ax.done(callback);
  ax.fail(function(req, stat, err) {
    console.log("FAIL ERR:"+err+" STAT:"+stat);
  });
}

function
loadOneDoc(mname, lang)
{
  function
  done(err, calc)
  {
    if(fd_Progress) {
      fd_status(fd_Progress+" / "+fd_AllCnt);
      if(++fd_Progress > fd_AllCnt) {
        fd_Progress = 0;
        setTimeout(calcOffsets,100);   // Firefox returns wrong offsets
        fd_status("");
      }
    } else {
      if(calc)
        setTimeout(calcOffsets,100);
      if(!err)
        location.href = "#"+mname;
    }
  }

  if(fd_Hash[mname] && fd_Hash[mname] == lang)
    return done(false, false);

  fd_fC("help "+mname+" "+lang, function(ret){
    //console.log(mname+" "+lang+" => "+ret.length);
    if(ret.indexOf("<html>") != 0 || ret.indexOf("<html>No help found") == 0)
      return done(true, false);
    ret = ret.replace(/<\/?html>/g,'');
    ret = ret.replace(/Keine deutsche Hilfe gefunden!<br\/>/,'');
    ret = '<div id="FD_'+mname+'">'+ret+'</div>';

    if(fd_Hash[mname])
      $("div#FD_"+mname).remove();

    if(!fd_Hash[mname])
      fd_List.push(mname);
    fd_Hash[mname] = lang;
    fd_List.sort();
    var idx=0;
    while(fd_List[idx] != mname)
      idx++;
    var toIns = "perl";
    if(idx < fd_List.length-1)
      toIns = fd_List[idx+1];
    $(ret).insertBefore("a[name="+toIns+"]");
    console.log("insert "+mname+" before "+toIns);
    return done(false, true);
  });
}

function
calcOffsets()
{
  fd_Offsets=[];
  for(var i1=0; i1<fd_List.length; i1++) {
    var cr = $("a[name="+fd_List[i1]+"]").offset();
    fd_Offsets.push(cr ? cr.top : -1);
  }
  checkScroll();
}

function
checkScroll()
{
  if(!scrolled) {
    setTimeout(checkScroll, 500);
    return;
  }
  scrolled = 0;
  var viewTop=$(window).scrollTop(), viewBottom=viewTop+$(window).height();
  var idx=0;
  while(idx<fd_Offsets.length) {
    if(fd_Offsets[idx] >= viewTop && viewBottom > fd_Offsets[idx]+30)
      break;
    idx++;
  }

  if(idx >= fd_Offsets.length) {
    $("a#otherLang").hide();

  } else {
    var mname = fd_List[idx];
    var l1 = fd_Hash[mname], l2 = (l1=="EN" ? "DE" : "EN");
    $("a#otherLang span.mod").html(mname);
    $("a#otherLang span[lang="+l1+"]").hide();
    $("a#otherLang span[lang="+l2+"]").show();
    $("a#otherLang").show();
  }
}

function
loadOtherLang()
{
  var mname = $("a#otherLang span.mod").html();
  loadOneDoc(mname, fd_Hash[mname]=="EN" ? "DE" : "EN");
}

$(document).ready(function(){
  var p = location.pathname;
  fd_Lang = p.substring(p.indexOf("commandref")+11,p.indexOf(".html"));
  if(!fd_Lang || fd_Lang == '.')
    fd_Lang = "EN";

  $("h3").each(function(){ fd_Hash[$(this).html()] = fd_Lang; });
  $("table.summary td.modname a")
    .each(function(){ fd_All[$(this).html()]=1; })
    .click(function(e){
      e.preventDefault();
      loadOneDoc($(this).html(), fd_Lang);
    });

  if(location.hash)
    loadOneDoc(location.hash.substr(1), fd_Lang);

  $("a[name=loadAll]").show().click(function(e){
    e.preventDefault();
    $("a[name=loadAll]").hide();
    location.href = "#doctop";
    fd_AllCnt = 0;
    for(var m in fd_All) fd_AllCnt++
    fd_Progress = 1;
    for(var mname in fd_All)
      loadOneDoc(mname, fd_Lang);
  });

  $("a#otherLang").click(loadOtherLang);

  window.onscroll = function(){ 
    if(!scrolled++)
      setTimeout(checkScroll, 500);
  };
});
