function startTime() {
  var today = new Date();
  var h = today.getHours();
  var m = today.getMinutes();
  var d = today.getDate();
  var mo = today.getMonth()+1;
  var y = today.getFullYear();
  var dofw =today.getDay();
  var days = ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'];
  h = checkTime(h);
  m = checkTime(m);
  d = checkTime(d);
  mo = checkTime(mo);
  $('.doifclock').each(function(){
    $(this).html(h + ":" + m + "&nbsp&nbsp" + days[dofw] + "&nbsp" + d + "." + mo + "." + y);
  });
  var t = setTimeout(startTime,1000);

}
function checkTime(i) {
  if (i < 10) {i = "0" + i};  // add zero in front of numbers < 10
  return i;
}

startTime();