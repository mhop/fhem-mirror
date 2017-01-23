##############################################
# $Id$
##############################################

package main;

use strict;
use warnings;
use POSIX;

#use Encode qw(encode);

my $version='0.95';

my $apiurl='http://qrcode.tec-it.com/API/QRCode';
my $service='TEC-IT';

my $modulename='QRCode';	#Module-Name = TYPE 
my $defsyntax="define <name> $modulename";

my $defImgPath='/tmp';

my $defWidth=200;
my $defHeight=200;


sub 
#======================================================================
QRCode_Log3($$$) 
#======================================================================
#Using my own Log3 method, expecting the same
#parameters as the official method
#QRCode_Log3 <devicename>,<loglevel>,<logmessage>
#making sure, the device-name is always contained in the log message
{
	my ($name,$lvl,$text)=@_;
	Log3 $name,$lvl,"$name: $text";
	return undef;
}


sub
#======================================================================
QRCode_Initialize($)
#======================================================================
#Module instance initialization (constructor)
{
  my ($hash) = @_;

  #Telling FHEM what routines to use for module handling
  $hash->{SetFn}       = $modulename."_Set";		#setter
  $hash->{DefFn}       = $modulename."_Define";	#define
  $hash->{FW_detailFn} = $modulename."_FWDetail";
  $hash->{AttrFn}      = $modulename."_Attr";
  $hash->{NotifyFn}    = $modulename."_Notify";
  
  #Telling FHEM what attributes are available
  $hash->{AttrList}  = 
	  "qrData:textField " #Text für den QRCode im generic Modus
	. "qrSize:small,medium,large "
	. "qrColor "
	. "qrBackColor "
	. "qrTransparent:True,False "
	. "qrQuietZone "
	. "qrQuietUnit:mm,in,mil,mod,px "
	. "qrCodepage:UTF8,Cyrillic,Ansi "
	. "qrResolutionDPI "
	. "qrErrorCorrection:L,M,Q,H "
	. "qrDisplayWidth "
	. "qrDisplayHeight "
	. "qrDisplayData:0,1 "
	. "qrNoAutoUpdate:1 "
	. "qrDisplayNoImage:1 "
	. "qrDisplayNoText:1 "
	. "qrDisplayText:textField-long "
	#. "qrDeliveryMethod:Base64,Image,Download " # We only use 'Image'
  	. $readingFnAttributes; #default FHEM FnAttributes -> see commandref.
}


sub 
#======================================================================
QRCode_Set($@)
#======================================================================
#Setter - Handling set commands for device
{
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $cmd=shift @a;
  #Currently only the update command is available to refressh
  #feed date
  if ($cmd eq 'update') {
	QRCode_update(@_);
  }
  else {
  	return "Unknown argument $cmd, choose one of update:noArg";
  }

  return undef;
}

sub
#======================================================================
QRCode_Define($$)
#======================================================================
#defining the device using following syntax
#define <name> QRCode 
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);

  #Check if at least 2 arguments are specified (name and url)
  return "Wrong syntax: use $defsyntax" if(int(@a) != 2);

  my $name      = shift @a;
  my $type      = shift @a;
  
  $hash->{SERVICE}=$service;
  $hash->{APIURL}=$apiurl;
  $hash->{NOTIFYDEV}='global';
  $hash->{VERSION}=$version;
  
  #setting initial state reading for device
  readingsSingleUpdate($hash,'state','defined',1);
  
  return undef;
  
}

#======================================================================
sub QRCode_Attr ($$$$)
#======================================================================
#Checking Attributes for validity
{
	my ( $cmd, $name, $attrName, $attrValue  ) = @_;
	
	my $error=undef;
		
	if($cmd eq 'set') {
		QRCode_Log3 $name,4,"checking new attribute value $attrName=$attrValue";
		
		if($attrName eq 'qrResolutionDPI') {
			$error='dpi value is out of range (96...600)' 
				if($attrValue < 96 || $attrValue > 600);
		}
		elsif ($attrName eq 'qrTransparent') {
			$error='transparent flag must be set to True or False'
				if($attrValue !~ /(True|False)/);
		}
		elsif ($attrName eq 'qrSize') {
			$error='size must be one of small, medium or large'
				if ($attrValue !~ /(small|medium|large)/);
		}
		elsif ($attrName =~ /(qrBackColor|qrColor)/) {
			$error='color must be a hex color RGB value (e.g. FF0000 for red)'
				if ($attrValue !~ /^(?:[0-9a-fA-F]{3}){1,2}$/);
		}
		elsif ($attrName eq 'qrQuietUnit') {
			$error='unit must be one of mm,in,mil,mod,px' 
				if ($attrValue !~/(mm|in|mil|mod|px)/);
		}
		elsif ($attrName eq 'qrErrorCorrection') {
			$error='error correction must be one of L,M,Q,H'
				if ($attrValue !~ /^[LMQH]$/);
		}
		elsif ($attrName eq 'qrCodepage') {
			$error='codepage must be one of UTF8,Cyrillic,Ansi'
				if ($attrValue !~ /(UTF8|Cyrillic|Ansi)/);
		}
		elsif ($attrName =~/(qrQuietZone|qrDisplayHeight|qrDisplayWidth)/) {
			$error='value must be a positive number'
				if ($attrValue <= 0);
		}
		elsif ($attrName =~ /(qrNoAutoUpdate|qrDisplayNoImage|qrDisplayNoText)/) {
			$error='value can be only set to 1 (otherwise delete the attribute)'
				if ($attrValue != 1);
		}
		
	}
	 
	return $error;
}


#======================================================================
sub QRCode_Notify($$)
#======================================================================
#Getting notifications to enable auto update feature when attributes
#are changed that are relevant for url and QRCode generation
{
	return undef unless ($init_done);
	
	my ($hash,$dev)=@_;
	
	my $name=$hash->{NAME};
	my $src=$dev->{NAME};
	
	my $needsUpdate=undef;
	
	if($src eq 'global') {
		foreach my $event (@{$dev->{CHANGED}})
		{
			QRCode_Log3 $name,4,"global event for $name: $event";
			
			my @evtArray = split /\s+/, $event;
			
			my $cmd=$evtArray[0];
			
			QRCode_Log3 $name,4,"event is $cmd";
			
			
			if($cmd =~ /.*ATTR/) {
				my $devName=$evtArray[1];
				my $attrName=$evtArray[2];
				QRCode_Log3 $name,4,"attribute $attrName of $devName";
				
				if($devName eq $name) {
					if($attrName =~ /^(qrData|qrSize|qrColor|qrBackColor|qrTransparent|qrQuietZone|qrQuietUnit|qrCodepage|qrResolutionDPI|qrErrorCorrection)$/) {
						QRCode_Log3 $name,4,"$name auto update relevant attribute changed";
						$needsUpdate=1;
					}
				} else {
					QRCode_Log3 $name,4,"only checking own attributes this one was for $devName -> ignoring!";
				}
			}
		}
	}
	
	
	QRCode_Log3 $name,5,"$name was notified by $src erhalten";
	
	foreach my $event (@{$dev->{CHANGED}})
	{
    	QRCode_Log3 $name,5,"$src EVENT: $event";
	}
	
	if($needsUpdate && !AttrVal($name,'qrNoAutoUpdate',undef)) {
		QRCode_Log3 $name,4,"auto updating ...";
		QRCode_update($hash);
	}
	
	return undef;
}

sub 
#======================================================================
QRCode_update(@) 
#======================================================================
#This subroutine is actually doing the update of QRCode-url
{
  
  my ($dhash,@a)=@_;
  
  my $name=$dhash->{NAME};
  my $errText='';

  QRCode_Log3 $name,4,'updating url ...';
  
  #Check if something wrong with the device's hash.
  if (!$name) {
  	$errText='Unable to extract device name';
  	QRCode_Log3($modulename.'_update',3,$errText);
	readingsSingleUpdate($dhash,'data',$errText,1);
	#readingsSingleUpdate($dhash,'error',1,1);
	$defs{$name}{ERROR}=1;
	return;
  }
  
  #Getting Api-URL from internals
  my $url=InternalVal($name,'APIURL',''); 
  if (!$url) {
  	#If there's no URL in internals, something is very wrong (see define)
  	$errText='APIURL is not defined';
  	QRCode_Log3($modulename.'_update',3,$errText);
	readingsSingleUpdate($dhash,'data',$errText,1);
	#readingsSingleUpdate($dhash,'error',1,1);
	$defs{$name}{ERROR}=1;
	return;
  }

  delete($defs{$name}{ERROR}) if defined ReadingsVal($name,'error',undef);

  my $data=AttrVal($name,'qrData',undef);
  if(!$data) {
  	$errText='No data to encode! Attribute qrData not defined!';
  	QRCode_Log3($modulename.'_update',3,$errText);
	readingsSingleUpdate($dhash,'data',$errText,1);
	#readingsSingleUpdate($dhash,'error',1,1);
	$defs{$name}{ERROR}=1;
	return;
  }
  
  delete($defs{$name}{ERROR}) if defined InternalVal($name,'ERROR',undef);
  
  my $encdata=urlEncode($data);
  
  $url.="?data=$encdata";
  
  my $fcolor=AttrVal($name,'qrColor',undef);
  $url.="&color=$fcolor" if($fcolor && $fcolor ne '000000');

  my $transp=AttrVal($name,'qrTransparent',undef);
  $url.="&istransparent=$transp" if($transp && $transp ne 'False');

  my $bcolor=AttrVal($name,'qrBackColor',undef);
  $url.="&backcolor=$bcolor" if($bcolor && $bcolor !~ /^(?:[fF]{3}){1,2}$/ && !$transp);

  my $qzone=AttrVal($name,'qrQuietZone',undef);
  $url.="&quietzone=$qzone" if($qzone && $qzone > 0);
  
  my $qunit=AttrVal($name,'qrQuietUnit',undef);
  $url.="&quietunit=$qunit" if($qunit && $qunit ne 'mm' );

  my $cerr=AttrVal($name,'qrErrorCorrection',undef);
  $url.="&errorcorrection=$cerr" if($cerr && $cerr ne 'L');

  my $cpage=AttrVal($name,'qrCodepage',undef);
  $url.="&codepage=$cpage" if($cpage && $cpage ne 'UTF8');

  my $dpi=AttrVal($name,'qrResolutionDPI',undef);
  $url.="&dpi=$dpi" if($dpi && $dpi != 300);

  my $size=AttrVal($name,'qrSize',undef);
  $url.="&size=$size" if($size && $ size ne 'medium');
  
  my $response = GetFileFromURLQuiet($url,5,undef,1);
  QRCode_Log3 $name,5,"--- BOF ---";
  QRCode_Log3 $name,5,$response;
  QRCode_Log3 $name,5,"--- EOF ---";
  
# Maybe I'll do a caching of the created QRCode later  
#  my $fpath=AttrVal($name,'qrFilePath',$defImgPath);
#  my $fname="$fpath/$name.png";  
#  my @fcontent=($response);  
#  my $err=FileWrite({ FileName=>$fname,ForceType=>"file",NoNL=>1 },@fcontent);
  
  #Now starting update of the readings
  readingsBeginUpdate($dhash);
  
#  readingsBulkUpdateIfChanged($dhash,'file_name',$fname);
  readingsBulkUpdateIfChanged($dhash,'data',$data);
  readingsBulkUpdateIfChanged($dhash,'qrcode_url',$url);
  readingsBulkUpdate($dhash,'state',TimeNow());
  
  #mass updating/generation of readings is complete so
  #tell FHEM to update them now!
  readingsEndUpdate($dhash,1);  

return;
}

	
#======================================================================
sub QRCode_getHtml($;$$)
#======================================================================
#Generate the details HTML code for display in device details 
#or use with an weblink or something else.
{
	my ($name,$noImage,$noText)=@_;
	
	#Checking if device exists ...
	return "<div style=\"color:red\">$name is not defined</div>" if(!$defs{$name});
	#...and is of correct TYPE
	return "<div style=\"color:red\">$name is not of TYPE $modulename</div>" if(!($defs{$name}{'TYPE'} eq $modulename));
	
	#Check for errors set by QRCode_update
	return '<div style="color:red">'.ReadingsVal($name,'data','unknown error!').'</div>'
		if(InternalVal($name,'ERROR',undef));
			
	my $imageurl=ReadingsVal($name,'qrcode_url',undef);
	return '<div style="color:red">No image url available! Use set update to create it.</div>'
		if(!$imageurl);
	
	
	my $width='width="'.AttrVal($name,'qrDisplayWidth',$defWidth).'"';
	my $height='height="'.AttrVal($name,'qrDisplayHeight',$defHeight).'"';

	my $ret  = "<table>";
	   
	   $ret .= "<tr><td rowspan=3>";
	   $ret .= "<td>";
	   $ret .= "<img $width $height src=\"".ReadingsVal($name,'qrcode_url',undef)."\"/>"
	   		if($imageurl && !$noImage);
	   $ret .= "No image url available!<br>Use set update to create it"
	   		if(!$imageurl);
	   $ret .= "</td></tr>";
	   $ret .= "<tr><td>";
	   my $stylecolor='';
	   $stylecolor=' style="color:red"' if !AttrVal($name,'qrData',undef);
	   $ret .= '<div'.$stylecolor.'>'.AttrVal($name,'qrData',ReadingsVal($name,'data','attr qrData n/a')).'</div>'
	   		if($imageurl && AttrVal($name,'qrDisplayData',undef) || !AttrVal($name,'qrData',undef));
	   $ret .= "</td>";
	   $ret .= "</tr>";
	   
	   my $dtext=AttrVal($name,'qrDisplayText',undef);
	   if ($dtext && !$noText && AttrVal($name,'qrData',undef)) {
	   		$dtext =~ s/\n/\<br\>/g;
	   		$ret .= "<tr><td>";
			$ret .= $dtext;
			$ret .= "</td></tr>";
	   }
	   $ret .= "</table>";
	   
	   return $ret;
	
}

#======================================================================
sub QRCode_FWDetail($@) {
#======================================================================
#Display the QRCode in device details in FHEMWEB
	my ($FW_wname, $name, $room, $pageHash) = @_;
	
	QRCode_Log3 $name,4,"FWDetail.name=$name";
		   
	return QRCode_getHtml($name,AttrVal($name,'qrDisplayNoImage',undef),AttrVal($name,'qrDisplayNoText',undef));
}

1;
#======================================================================
#======================================================================
#
# HTML Documentation for help and commandref
#
#======================================================================
#======================================================================
=pod
=item device
=item summary    create and display QRCode in FHEMWEB
=item summary_DE QRCode erzeugen und in FHEMWEB darstellen
=begin html

<a name="QRCode"></a>
<h3>QRCode</h3>
<ul>
  Devices of this module are used to generate an URL that will be used to generate
  and receive a QRCode from the service of TEC-IT<br/>
  The device will also display the generated QRCode in the device details. It can 
  also provide the HTML-code used for display for other purposes (e.g. weblink devices)
  <br/><br/>
  <b>ATTENTION:</b>The sevice provider does not allow more than 30 QRCode generations / minute
                   without special permission<br/><br/>
		   See terms of sevice on TEC-IT homepage: http://qrcode.tec-it.com/de#TOS
  <br/><br/>

  <a name="QRCodedefine"></a>
  <b>Define</b><br/>
  <ul>
      <code>define &lt;name&gt; QRCode</code>
      <br/><br/>
  </ul>
  <br/>

  <a name="QRCodeset"></a>
  <b>Set</b><br/>
  <ul>
    <code>set &lt;name&gt; update</code><br/>
    Refreshes the QRCode-URL for Image generation.
  </ul>
  <br/>

  <a name="QRCodeattr"></a>
  <b>Attributes</b><br/><br/>
  <ul>
 	<b>QRCode-URL relevant attributes</b>
  	<br/><br/>
	The following attributes take influence on the QRCode generation.
	<br/><br/>
	If one of those attributes is changed, per default an auto update of the QRCode-URL is performed.
	<br/><br/>
    <li><a name="qrData">qrData</a><br/>
		This attribute is used to set the data that will be encoded in the QRCode.<br/>
		If this attribute is not set an error message is generatet.
		<br/><br/>
    </li>
	<li><a name="qrSize">qrSize</a><br/>
        Defines the size of the generated QRCode image<br/> 
		Possible values are small, medium (default), large.
		<br/><br/>
    </li>
	<li><a name="qrResolutionDPI">qrResolutionDPI</a><br/>
        Defines the resolution for QRCode generaation<br/> 
		Valid values are between 96 and 600 (Default is 300dpi)
		<br/><br/>
    </li>
	<li><a name="qrColor">qrColor</a><br/>
        Defines the foreground color of the genereted QRCode image<br/> 
		This is a RGB color value in hex format (eg. FF0000 = red)
		Default is 000000 (black)
		<br/><br/>
    </li>
	<li><a name="qrBackColor">qrBackColor</a><br/>
        Defines the background color of the genereted QRCode image<br/> 
		This is a RGB color value in hex format (eg. 0000FF = blue)
		Default is FFFFFF (white).
		<br/><br/>
    </li>
	<li><a name="qrTransparent">qrTransparent</a><br/>
        Defines that the background of the generated QRCode will be transparent<br/>
		Possible values are False (non-tranparent background) or True (transparent background)<br/>
		default is non-transparent.
		<br/><br/>
    </li>
	<li><a name="qrQuietZone">qrQuietZone</a><br/>
		defines the size of a quiet zone around the QRCode in the image.<br/>
		This is a blank zone making it easier to scan the QRCode for some scanners.<br/>
		Default ist 0, if attribute is not set.
		<br/><br/>
    </li>
	<li><a name="qrQuietUnit">qrQuietUnit</a><br/>
        specifies the unit for qrQuietZone attribute<br/>
		Possible values are mm (default), in (=inch), mil (=mils), mod (=Module) or px (=Pixel).
		<br/><br/>
    </li>
	<li><a name="qrCodepage">qrCodepage</a><br/>
        Used Codepage for QRCode generation.<br/>
		Possible values are UTF8 (default), Cyrillic or Ansi
		<br/><br/>
    </li>
	<li><a name="qrErrorCorrection">qrErrorCorrection</a><br/>
        Error correction used in generated QRCode image.<br/>
		Possible values are L (default), M,Q or H
		<br/><br/>
    </li>
	
 	<b>Display relevant attributes</b>
  	<br/><br/>
	The followin Attribute change the behaviour and display parameters for the detail view<br/>
	of QRCode devices in FHEMWEB. Therfore it changes the result of QRCode_getHtml function<br/>
	(see below.)<br/><br/>
	In cas of an error, neither QRCode, nor qrDisplayText will be displayed. Instead<br/>
	an error message is displayed.
	<br/><br/>
	<li><a name="qrDisplayWidth">qrDisplayWidth</a><br/>
        display width of the QRCode image<br/>
		Default is 200
		<br/><br/>
    </li>
	<li><a name="qrDisplayHeigth">qrDisplayHeight</a><br/>
        Display height of the QRCode image<br/>
		Default is 200
		<br/><br/>
    </li>
	<li><a name="qrDisplayData">qrDisplayData</a><br/>
		If set the contents or the reading data is displayed below the QRCode image<br/>
		Usually this is the contents of attribute qrData.
		<br/><br/>
    </li>
	<li><a name="qrDisplayNoImage">qrDisplaNoImage</a><br/>
		If set, the QRCode image will not be displayed
		<br/><br/>
    </li>
	<li><a name="qrDisplayText">qrDisplaText</a><br/>
		user defined text to be displayed below QRCode image
		<br/><br/>
    </li>
	<li><a name="qrDisplayNoText">qrDisplaNoText</a><br/>
		If this attribute is set, the text specified in qrDisplayText will not be displayed<br/>
		below QRCode image. So qrDisplayText doesn't have to be deleted.
		<br/><br/>
    </li>
	<li><a name="qrNoAutoUpdate">qrNoAutoUpdate</a><br/>
		If set not auto update will be processed for QRCode relevant attributes.
		<br/><br/>
    </li>	

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br/><br/>

  <a name="QRCodereadings"></a>
  <b>Generated Readings</b>
  <br/><br/>
  <ul>
      <br/>
      <li>data<br/>
        This reading contains the data to be encoded by the QRCode<br/>
		Usually this is the contents of attribute qrData.<br/>
		In case of an error it contains the error message.
		<br/><br/>
      </li>
      <li>qrcode_url<br/>
	  	By <code>set update</code> generated URL, used to get the QRCode image<br/>
		<br/><br/>
      </li>
      <li>state<br/>
	    The state of the device<br/>
		Initially this is <code>defined</code> or the timestamp of last <code>set update</code>, or auto-update
		<br/><br/>
      </li>
  </ul>
  <br/><br/>
  
  <a name="QRCodefunctions"></a>
  <b>Usefull Funktionen</b>
  <br/><br/>
  The module comes with a useful function to provide the HTML code used for display in detail view of the<br/>
  QRCode device in FHEMWEB for other purposes, e.g. weblink.
  <br/><br/>
  <ul>
      <br/>
      <li><code>QRCode_getHtml($;$$)</code><br/><br/>
	  	Returns the HTML code for the specified QRCode device
		<br/><br/>
		Arguments:
		<br/><br/>
		<ul>
		<li>QRCodeDevice<br/>
		    Name of the QRCode device as a string.
		</li>
		<li>noImage (Optional)<br/>
		    The same as attribute qrDisplayNoImage<br/>
		</li>
		<li>noText (Optional)<br/>
		    The same as attribute qrDisplayNoText<br/>
		</li>
		</ul>
		<br/><br/>
		Example:
		<br/><br/>
		<code>QRCode_getHtml('MyQRCode',1,0)</code>
		<br/><br/>
		Generate HTML code of (QRCode-) device named MyQRCode with QRCode image but not with the<br/>
		user defined Text (qrDisplayText).
				
		
      </li>
  </ul>  
</ul>
=end html


















=begin html_DE

<a name="QRCode"></a>
<h3>QRCode</h3>
<ul>
  Mit hilfe dieses Moduls, kann auf einfache Weise eine URL generiert werden, mit
  der vom Dienstleister TEC-IT ein QRCode abgerufen werden kann.<br/>
  Ein Device dieses Moduls kann außerdem den QRCode auch selbst direkt in FHEMWEB 
  darstellen und auch anderen Devices (bspw. weblink) als HTML zur Verfügung stellen.
  <br/><br/>
  <b>HINWEIS:</b> Es ist ohne schriftliche Genehmigung des Dienstaanbieters nur erlaubt, 
           maximal 30 QRCode-Abrufe / Minute durchzuführen.<br/><br/>
		   Siehe dazu auch die Nutzungsbedingungen von TEC-IT: http://qrcode.tec-it.com/de#TOS
  <br/><br/>

  <a name="QRCodedefine"></a>
  <b>Define</b><br/>
  <ul>
      <code>define &lt;name&gt; QRCode</code>
      <br/><br/>
  </ul>
  <br/>

  <a name="QRCodeset"></a>
  <b>Set</b><br/>
  <ul>
    <code>set &lt;name&gt; update</code><br/>
    Führt eine aktualisierung der QRCode-Url durch.
  </ul>
  <br/>

  <a name="QRCodeattr"></a>
  <b>Attributes</b><br/><br/>
  <ul>
 	<b>QRCode-URL-relevante Attribute</b>
  	<br/><br/>
	Die folgenden Attribute sind für die Erzeugung der Abruf-URL relevant und haben somit<br/>
	direkten Einfluß auf die Erzeugung des QRCode-Images.<br/><br/>
	Für diese Attribute wird bei Änderung, standardmäßig ein automatisches Udate der QRCode-URL<br/>
	durchgeführt. Dies kann durch setzen des Attirbutes qrNoAutoUpdate (s.w.u.) deaktiviert werden.
	<br/><br/>
    <li><a name="qrData">qrData</a><br/>
        Dieses Attribut legt die Daten fest, die im QRCode kodiert werden sollen.<br/>
		Ist dieses Attribut nicht gesetzt, wird beim update eine entsprechende
		Fehlermeldung erzeugt.
		<br/><br/>
    </li>
	<li><a name="qrSize">qrSize</a><br/>
        Dieses Attribut legt die Größe fest, in der das QRCode-Image erstellt werden
		soll.<br/> Mögliche Ausprägungen sind small, medium (default), large.
		<br/><br/>
    </li>
	<li><a name="qrResolutionDPI">qrResolutionDPI</a><br/>
        Dieses Attribut legt die Auflösung fest, in der das QRCode-Image erstellt werden
		soll.<br/> Mögliche Werte liegen zwischen 96 und 600 (Default ist 300dpi)
		<br/><br/>
    </li>
	<li><a name="qrColor">qrColor</a><br/>
        Dieses Attribut legt die Vordergrundfarbe fest, in der das QRCode-Image erstellt werden
		soll.<br/> Der Wert ist ein RGB-Farbwert in Hexadezimaler schreibweise (Bspw. FF0000 für rot)
		Default ist 000000 (schwarz)
		<br/><br/>
    </li>
	<li><a name="qrBackColor">qrBackColor</a><br/>
        Dieses Attribut legt die Hintergrundfarbe fest, in der das QRCode-Image erstellt werden
		soll.<br/> Der Wert ist ein RGB-Farbwert in Hexadezimaler schreibweise (Bspw. 0000FF für blau)
		Default ist FFFFFF (weiß).
		<br/><br/>
    </li>
	<li><a name="qrTransparent">qrTransparent</a><br/>
        Dieses Attribut legt fest, ob der Hintergrund transparent sein soll.<br/>
		Mögliche Werte sind True für transparenten Hintergrund und False für nicht-transparenten
		Hintergrund (default)
		<br/><br/>
    </li>
	<li><a name="qrQuietZone">qrQuietZone</a><br/>
        Über diesen Wert kann eine Ruhe-Zone, also ein Rand um den eigentlichen QRCode festgelegt
		werden.<br/> Dies ermöglicht ggf. ein erleichtertes Erfassen des QRCodes beim Scannen.<br/>
		Mögliche Werte sind positive numerische Werte. Default ist 0, wenn das Attribut nicht gesetzt ist.
		<br/><br/>
    </li>
	<li><a name="qrQuietUnit">qrQuietUnit</a><br/>
        Über diesen Wert kann die Maßeinheit für das Festlegen einer Ruhe-Zone eingestellt werden.<br/>
		Mögliche Ausptägungen sind mm (default), in (=inch), mil (=mils), mod (=Module) oder px (=Pixel).
		<br/><br/>
    </li>
	<li><a name="qrCodepage">qrCodepage</a><br/>
        Über diesen Wert kann die Zeichentabelle für die QRCode-Erzeugung festgelegt werden.<br/>
		Mögliche Werte sind UTF8 (default), Cyrillic oder Ansi
		<br/><br/>
    </li>
	<li><a name="qrErrorCorrection">qrErrorCorrection</a><br/>
        Über diesen Wert kann Fehlerkorrektur für die QRCode-Erzeugung festgelegt werden.<br/>
		Mögliche Werte sind L (default), M,Q oder H
		<br/><br/>
    </li>
	
 	<b>darstellungsrelevante Attribute</b>
  	<br/><br/>
	Die folgenden Attribute haben nur Einfluß auf das Verhalten und die Darstellung in FHEMWEB<br/>
	in der Deatailansicht des QRCode-Devices, bzw. beim Abruf der HTML-Daten mittels 
	QRCode_getHtml (s.u.)<br/><br/>
	Im Fehlerfall wird weder der QRCode, noch qrDisplayText dargestellt, sondern eine entsprechend<br/>
	Fehlermeldung stattdessen eingeblendet.
	<br/><br/>
	<li><a name="qrDisplayWidth">qrDisplayWidth</a><br/>
        Breite des Images bei der Darstellung in FHEMWEB in der Detailübersicht<br/>
		Default ist 200
		<br/><br/>
    </li>
	<li><a name="qrDisplayHeigth">qrDisplayHeight</a><br/>
        Höhe des Images bei der Darstellung in FHEMWEB in der Detailübersicht<br/>
		Default ist 200
		<br/><br/>
    </li>
	<li><a name="qrDisplayData">qrDisplayData</a><br/>
		Wenn dieses Attribut gesetzt ist, wird unterhalb des QRCodes der Datenteil als einfacher<br/>
		Text dargestellt.
		<br/><br/>
    </li>
	<li><a name="qrDisplayNoImage">qrDisplaNoImage</a><br/>
		Wenn dieses Attribut gesetzt ist, der QRCode nicht in der Detailansicht dargestellt.
		<br/><br/>
    </li>
	<li><a name="qrDisplayText">qrDisplaText</a><br/>
		Hier kann ein beliebiger Text eingetragen werden, der unterhalb des QRCodes eingeblendet werden soll.
		<br/><br/>
    </li>
	<li><a name="qrDisplayNoText">qrDisplaNoText</a><br/>
		Ist dieses Attribut gesetzt, so wird der, im Attribut qrDisplayText eingetragene Text nicht
		eingeblendet, auch ohne das Attribut qrDisplayText zu löschen.
		<br/><br/>
    </li>
	<li><a name="qrNoAutoUpdate">qrNoAutoUpdate</a><br/>
		Ist dieses Attribut gesetzt, so wird bei Änderung eines für die QRCode-Erzeugung relevanten<br/>
		Attributs kein automatisches Update der QRCode-URL durchgeführt.
		<br/><br/>
    </li>	

    <li><a href="#readingFnAttributes">readingFnAttributes</a></li>
  </ul>
  <br/><br/>

  <a name="QRCodereadings"></a>
  <b>Erzeugte Readings</b>
  <br/><br/>
  <ul>
      <br/>
      <li>data<br/>
        Dieses Reading enthält die vom QRCode zu kodierenden Daten.<br/>
		Das ist im Normalfall der Inhalt aus dem Attribut qrData.<br/>
		Im Fehlerfall steht hier stattdessen der entsprechende Fehlertext.
		<br/><br/>
      </li>
      <li>qrcode_url<br/>
	  	Dies ist die durch <code>set update</code> erzeugte URL, die für den Abruf des QRCode-Image<br/>
		verwendet wird.
		<br/><br/>
      </li>
      <li>state<br/>
	  	Status des QRCode-Device.<br/>
		Das ist entweder <code>defined</code>, oder der Zeitpunkt des letzten <code>set update</code>, bzw. auto-update
		<br/><br/>
      </li>
  </ul>
  <br/><br/>
  
  <a name="QRCodefunctions"></a>
  <b>Enthaltene Funktionen</b>
  <br/><br/>
  Es gibt im Modul eine Funktion, die auch für andere Anwendungsfälle einsetzbar ist, wie bspw. in einem weblink
  <br/><br/>
  <ul>
      <br/>
      <li><code>QRCode_getHtml($;$$)</code><br/><br/>
	  	Die Funktion gibt den HTML-Code zurück, wie er auch für die Darstellung im QRCode-Device in der<br/>
		Detail-Ansicht verwendet wird.
		<br/><br/>
		Parameter:
		<br/><br/>
		<ul>
		<li>QRCodeDevice<br/>
		    Hier ist der Name des QRCode-Devices anzugeben, dessen HTML-Code abgerufen werden soll.
		</li>
		<li>noImage (Optional)<br/>
		    Entspricht dem Attribut qrDisplayNoImage<br/>
			Wenn dieser Parameter angezeigt wird, wird also keine Referenz auf QRCode-Image im HTML-Code<br/>
			erzeugt.
		</li>
		<li>noText (Optional)<br/>
		    Entspricht dem Attribut qrDisplayNoText<br/>
			Wenn dieser Parameter angezeigt wird, wird also Benutzerdefinierter Text unterhalb des QRCode<br/>
			im HTML-Code erzeugt.
		</li>
		</ul>
		<br/><br/>
		Beispiel:
		<br/><br/>
		<code>QRCode_getHtml('MyQRCode',1,0)</code>
		<br/><br/>
		Damit wird der HTML-Code für das (QRCode-)Device MyQRCode abgerufen, das nur das Image enthält,<br>
		aber nicht den Benutzerdefinierten text.
				
		
      </li>
  </ul>  
</ul>

=end html_DE


=cut
