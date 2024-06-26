##############################################
# $Id$
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

#####################################
sub
sequence_Initialize($)
{
  my ($hash) = @_;

  $hash->{DefFn} = "sequence_Define";
  $hash->{UndefFn} = "sequence_Undef";
  $hash->{NotifyFn} = "sequence_Notify";
  no warnings 'qw';
  my @attrList = qw(
    addStateEvent:1,0
    disable:0,1
    disabledForIntervals
    reportEvents:1,0
    triggerPartial:1,0 
    showtime:1,0
    strictSequence:1,0
  );
  use warnings 'qw';
  $hash->{AttrList} = join(" ", @attrList);
}


#####################################
# define sq1 sequence reg1 [timeout reg2]
sub
sequence_Define($$)
{
  my ($hash, $def) = @_;
  my @def = split("[ \t]+", $def);

  my $name = shift(@def);
  my $type = shift(@def);
  
  return "Usage: define <name> sequence <re1> <timeout1> <re2> ".
                                            "[<timeout2> <re3> ...]"
    if(int(@def) % 2 == 0 || int(@def) < 3);

  # "Syntax" checking
  my @reList;
  for(my $i = 0; $i < int(@def); $i += 2) {
    my $re = $def[$i];
    my $to = $def[$i+1];
    eval { "Hallo" =~ m/^$re$/ };
    return "Bad regexp 1: $@" if($@);
    return "Bad timeout spec $to"       # timeout or delay:timeout
      if (defined($to) && $to !~ m/^(\d+(\.\d+)?:)?\d+(\.\d+)?$/);
    push @reList,$re if($re !~ m/^:/); # Respect feature: use last dev
  }

  $hash->{RE} = $def[0];
  $hash->{IDX} = 0;
  $hash->{MAX} = int(@def);
  $hash->{STATE} = "active";
  $hash->{TS} = 0;
  InternalTimer(0, sub { notifyRegexpChanged($hash, join("|",@reList)) }, 0);
  return undef;
}

#####################################
sub
sequence_Notify($$)
{
  my ($hash, $dev) = @_;

  my $ln = $hash->{NAME};
  return "" if(IsDisabled($ln));

  my $n = $dev->{NAME};
  my $re = $hash->{RE};
  my $events = deviceEvents($dev, AttrVal($ln, "addStateEvent", 0));
  return if(!$events);
  my $max = int(@{$events});
  my $strictSequence = AttrVal($ln, "strictSequence", 0);

  for (my $i = 0; $i < $max; $i++) {
    my $s = $events->[$i];
    $s = "" if(!defined($s));
    if($n !~ m/^$re$/ && "$n:$s" !~ m/^$re$/) {
      next if(!$strictSequence || !$hash->{IDX});
      RemoveInternalTimer($ln);
      sequence_Trigger($ln, "abort-strict");
      return "";
    }

    RemoveInternalTimer($ln);
    $hash->{last_source} = $n;

    if($hash->{TS} > gettimeofday()) { # the delay stuff
      sequence_Trigger($ln, "abort");
      last;
    }

    my $idx = $hash->{IDX} + 2;
    Log3 $ln, 5, "sequence $ln matched $idx";
    my @d = split("[ \t]+", $hash->{DEF});
    $hash->{EVENTS} = "" if(!$hash->{EVENTS});
    $hash->{EVENTS} .= " $n:$s";

    if($idx > $hash->{MAX}) {   # Last element reached

      my $tt = "trigger";
      $tt .= $hash->{EVENTS} if(AttrVal($ln, "reportEvents", undef));
      delete($hash->{EVENTS});

      Log3 $ln, 5, "sequence $ln $tt";
      setReadingsVal($hash, "state", "active", TimeNow());
      $data{sequence_source} = $n;
      DoTrigger($ln, $tt);
      delete($data{sequence_source});
      $idx  = 0;
      $hash->{TS} = 0;

    } else {

      my ($delay, $nt) = split(':', $d[$idx - 1]);
      $hash->{TS} = gettimeofday() + $delay if (defined($nt) && $delay > 0);
      $nt += gettimeofday() + $delay;
      InternalTimer($nt, "sequence_Trigger", $ln, 0);

    }

    $hash->{IDX} = $idx;
    $hash->{RE} = substr($d[$idx], 0, 1) eq ':' ? $n . $d[$idx] : $d[$idx];
    last;
  }
  return "";
}

sub
sequence_Trigger($$)
{
  my ($ln, $arg) = @_;
  my $hash = $defs{$ln};
  my @d = split("[ \t]+", $hash->{DEF});
  $hash->{RE} = $d[0];
  my $idx = $hash->{IDX}/2;
  $hash->{IDX} = 0;
  $hash->{TS} = 0;
  my $tt = "partial_$idx";
  $arg = "timeout" if(!$arg);
  Log3 $ln, 5, "sequence $ln $arg on $idx ($tt)";
  $tt .= $hash->{EVENTS} if(AttrVal($ln, "reportEvents", undef));
  delete($hash->{EVENTS});

  if(AttrVal($ln, "triggerPartial", undef)) {
    $data{sequence_source} = $hash->{last_source};
    DoTrigger($ln, $tt);
    delete($data{sequence_source});
  }
  delete($hash->{last_source});
}

sub
sequence_Undef($$)
{
  my ($hash, $name) = @_;
  RemoveInternalTimer($name);
  return undef;
}

1;

=pod
=item helper
=item summary    generate an event upon reception of a defined sequence of events
=item summary_DE generiert Event nach Empfang einer definierten Event-Sequenz
=begin html

<a id="sequence"></a>
<h3>sequence</h3>
<ul>
  <br>

  <a id="sequence-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; sequence &lt;re1&gt; &lt;timeout1&gt;
                &lt;re2&gt; [&lt;timeout2&gt; &lt;re3&gt; ...]</code>
    <br><br>

    A sequence is used to allow to trigger events for a certain combination of
    button presses on a remote. E.g. to switch on a lamp when pressing the
    Btn1:on, then Btn2:off and at last Btn1:on one after the other you could
    define the following:<br>
    <br>
    <ul>
      <code>
      define lampseq sequence Btn1:on 0.5 Btn2:off 0.5 Btn1:on<br>
      define lampon  notify lampseq:trigger set lamp on
      </code>
    </ul>
    <br>
    Subsequent patterns can be specified without device name as
    <code>:&lt;re2&gt;</code>. This will reuse the device name which triggered
    the previous sequence step:
    <br>
    <ul>
      <code>
      define lampseq sequence Btn.:on 0.5 :off<br>
      </code>
    </ul>
    <br>

    You can specify timeout as <code>&lt;delay&gt;:&lt;timeout&gt;</code>,
    where "delay" sets time during which the next event shall not be received,
    otherwise the sequence will be aborted. This can be used to capture press
    and hold of a button. Example:<br>
    <ul>
      <code>
      define lampseq sequence Btn1:on 2:3 Btn1:off<br>
      </code>
    </ul>
    sequence will be triggerred if Btn1 is pressed for 2 to 5 seconds.<br>
    Note: the global variable $data{sequence_source} is set to the name of the
    device triggering the last event.
  </ul>
  <br>

  <a id="sequence-set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a id="sequence-get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a id="sequence-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#addStateEvent">addStateEvent</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a id="sequence-attr-triggerPartial"></a>
    <li>triggerPartial</a><br>
      if set (to 1), and not all the events of a sequence are received, then a
      partial_X event is generated by the sequence. Example:<br><code><ul>
      fhem> define seq sequence d1:on 1 d1:on 1 d1:on<br>
      fhem> attr seq triggerPartial<br>
      fhem> set d1 on;; sleep 0.5;; set d1 on<br>
      </ul></code>
      generates the event seq partial_2. This can be used to assign different
      tasks for a single button, depending on the number of times it is
      pressed.
      </li><br>

    <a id="sequence-attr-reportEvents"></a>
    <li>reportEvents<br>
      if set (to 1), report the events (space separated) after the
      "trigger" or "partial_X" keyword. This way one can create more general
      sequences, and create different notifies to react:<br>
      <ul><code>
        define seq sequence remote:btn.* 1 remote:btn.*<br>
        attr seq reportEvents<br>
        define n_b1b2 notify seq:trigger.remote:btn1.remote:btn2 set lamp1 on<br>
        define n_b2b1 notify seq:trigger.remote:btn2.remote:btn1 set lamp1 off<br>
      </code></ul>
      </li><br>

    <a id="sequence-attr-strictSequence"></a>
    <li>strictSequence<br>
      if set (to 1), any "unexpected" event will reset the sequence. This may
      be helpful to avoid brute-force attacks.<br>
      Note: it will only work correctly if the sequence is triggered only
      by the configured devices (check the NOTIFYDEV internal), and the source
      is not generating "undesired" events together with the desired ones.
      </li><br>
  </ul>
  <br>

</ul>

=end html

=begin html_DE

<a id="sequence"></a>
<h3>sequence</h3>
<ul>
  <br>

  <a id="sequence-define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; sequence &lt;re1&gt; &lt;timeout1&gt;
                &lt;re2&gt; [&lt;timeout2&gt; &lt;re3&gt; ...]</code>
    <br><br>

    Ein sequence kann verwendet werden, um ein neues Event zu generieren, wenn
    eine bestimmte Folge von anderen Events in einem festgelegten Zeitraum
    eingetroffen ist. Z.Bsp. um eine Lampe dann einzuschalten, falls Btn1:on,
    dann Btn2:off und zum Schluss Btn1:on innerhalb einer Sekunde gedr&uuml;ckt
    wurde, definiert man folgendes:<br>
    <ul>
      <code>
      define lampseq sequence Btn1:on 0.5 Btn2:off 0.5 Btn1:on<br>
      define lampon  notify lampseq:trigger set lamp on
      </code>
    </ul>
    Nachfolgende Regexps k&ouml;nnen den Namen des Ger&auml;tes weglassen, in
    diesem Fall werden nur die Events des beim ersten Event eingetroffenen
    Ger&auml;tes beachtet:
    <br>
    <ul>
      <code>
      define lampseq sequence Btn.:on 0.5 :off<br>
      </code>
    </ul>
    <br>
    Timeout kann als <code>&lt;delay&gt;:&lt;timeout&gt;</code> spezifiziert
    werden, dabei setzt delay die Zeit, wo kein passendes Event empfangen
    werden darf, ansonsten wird sequence abgebrochen. Das kann verwendet
    werden, um "press and hold" auszuwerten. Folgendes
    <ul>
      <code>
      define lampseq sequence Btn1:on 2:3 :off<br>
      </code>
    </ul>
    ist nur erfolgreich, falls Btn1 zwischen 2 und 5 Sekunden lang gedr&uuml;ckt
    wurde.<br>
    Die globale Variable $data{sequence_source} wird auf dem Namen des
    Ger&auml;tes gesetzt, was den letzten Event ausgel&ouml;st hat.
  </ul>
  <br>

  <a id="sequence-set"></a>
  <b>Set</b> <ul>N/A</ul><br>

  <a id="sequence-get"></a>
  <b>Get</b> <ul>N/A</ul><br>

  <a id="sequence-attr"></a>
  <b>Attributes</b>
  <ul>
    <li><a href="#addStateEvent">addStateEvent</a></li>
    <li><a href="#disable">disable</a></li>
    <li><a href="#disabledForIntervals">disabledForIntervals</a></li>

    <a id="sequence-attr-triggerPartial"></a>
    <li>triggerPartial<br>
      Falls gesetzt (auf 1), und nicht alle erwarteten Events eingetroffen
      sind, dann wird ein partial_X Event generiert, wobei X durch Anzahl der
      eingetroffenen Events ersetzt wird. Beispiel:<br><code><ul>
      fhem> define seq sequence d1:on 1 d1:on 1 d1:on<br>
      fhem> attr seq triggerPartial<br>
      fhem> set d1 on;; sleep 0.5;; set d1 on<br>
      </ul></code>
      erzeugt das Event "seq partial_2". Dies kann verwendet werden, um z.Bsp.
      einer Taste unterschiedliche Aufgaben zuzuweisen, jenachdem wie oft sie
      gedr&uuml;ckt wurde.
      </li><br>

    <a id="sequence-attr-reportEvents"></a>
    <li>reportEvents<br>
      Falls gesetzt (auf 1), meldet trigger die empfangenen Events (Leerzeichen
      getrennt) nach dem "trigger" oder "partial_X" Schl&uuml;sselwort.
      Das kann verwendet werden, um generische sequence Instanzen zu definieren:
      <br>
      <ul><code>
        define seq sequence remote:btn.* 1 remote:btn.*<br>
        attr seq reportEvents<br>
        define n_b1b2 notify seq:trigger.remote:btn1.remote:btn2 set lamp1 on<br>
        define n_b2b1 notify seq:trigger.remote:btn2.remote:btn1 set lamp1 off<br>
      </code></ul>
      </li><br>

    <a id="sequence-attr-strictSequence"></a>
    <li>strictSequence<br>
      Falls gesetzt ist (auf 1), jedes "unerwartete" Event setzt die
      Verarbeitung zur&uuml;ck. Das kann bei sog. Brute-Force Attacken helfen.
      <br>
      Achtung: es funktioniert nur dann wie erwartet, wenn die Definition nur
      auf die konfigurierten Geraete triggert (siehe das NOTIFYDEV Internal),
      und die Quelle generiert nur die gew&uuml;nschten Events (kein
      Zeitstempel, ACK, etc).
      </li><br>
  </ul>
  <br>

</ul>

=end html_DE

=cut
