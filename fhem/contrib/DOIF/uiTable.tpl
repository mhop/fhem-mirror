{
package my_uiTable;

#Styles
 sub temp
 {
   my ($temp,$size,$icon)=@_;
   return((defined($icon) ? ::FW_makeImage($icon):"").$temp."&nbsp;°C","font-weight:bold;".(defined ($size) ? "font-size:".$size."pt;":"").ui_Table::temp_style($temp));
 }

 sub temp_style
 {
     my ($temp)=@_;
     if ($temp >=30) {
	   return ("color:".::DOIF_hsv ($temp,30,50,20,0,90,95));
     } elsif ($temp >= 10) {
       return ("color:".::DOIF_hsv ($temp,10,30,73,20,80,95));  
	 } elsif ($temp >= 0) {
	   return ("color:".::DOIF_hsv ($temp,0,10,211,73,60,95));
	 } elsif ($temp >= -20) {
	   return ("color:".::DOIF_hsv ($temp,-20,0,277,211,50,95));
	 }
 }
 
 sub hum
 {
    my ($hum,$size,$icon)=@_;
    return ((defined($icon) ? ::FW_makeImage($icon):"").$hum."&nbsp;%","font-weight:bold;".(defined ($size) ? "font-size:".$size."pt;":"")."color:".::DOIF_hsv ($hum,30,100,30,260,60,90));
 }

 sub style
 {
   my ($text,$color,$font_size,$font_weight)=@_;
   my $style="";
   $style.="color:$color;" if (defined ($color));
   $style.="font-size:$font_size"."pt;" if (defined ($font_size));
   $style.="font-weight:$font_weight;" if (defined ($font_weight));
   return ($text,$style);

 }
 

# Widgets
 
 sub temp_knob {
    my ($value,$color,$set)=@_;
    $color="DarkOrange" if (!defined $color); 
    $set="set" if (!defined $set);
    return ($value,"","knob,min:17,max:25,width:40,height:35,step:0.5,fgColor:$color,bgcolor:grey,anglearc:270,angleOffset:225,cursor:15,thickness:.3",$set) 
 }
 
 sub shutter {
   my ($value,$color,$type)=@_;
   $color="\@darkorange" if (!defined ($color) or $color eq "");
   if (!defined ($type) or $type == 3) {
     return ($value,"","iconRadio,$color,100,fts_shutter_10,30,fts_shutter_70,0,fts_shutter_100","set");
   } elsif ($type == 4) {
       return ($value,"","iconRadio,$color,100,fts_shutter_10,50,fts_shutter_50,30,fts_shutter_70,0,fts_shutter_100","set");
     } elsif ($type == 5) {
         return ($value,"","iconRadio,$color,100,fts_shutter_10,70,fts_shutter_30,50,fts_shutter_50,30,fts_shutter_70,0,fts_shutter_100","set");
       } elsif ($type >= 6) {
           return ($value,"","iconRadio,$color,100,fts_shutter_10,70,fts_shutter_30,50,fts_shutter_50,30,fts_shutter_70,20,fts_shutter_80,0,fts_shutter_100","set");
         } elsif ($type == 2) {
             return ($value,"","iconRadio,$color,100,fts_shutter_10,0,fts_shutter_100","set");
         }
 } 
 
 sub dimmer {
   my ($value,$color,$type)=@_;
   $color="\@darkorange" if (!defined ($color) or $color eq "");
   if (!defined ($type) or $type == 3) {
     return ($value,"","iconRadio,$color,0,light_light_dim_00,50,light_light_dim_50,100,light_light_dim_100","set");
   } elsif ($type == 4) {
       return ($value,"","iconRadio,$color,0,light_light_dim_00,50,light_light_dim_50,70,light_light_dim_70,100,light_light_dim_100","set");
     } elsif ($type == 5) {
         return ($value,"","iconRadio,$color,0,light_light_dim_00,30,light_light_dim_30,50,light_light_dim_50,70,light_light_dim_70,100,light_light_dim_100","set");
       } elsif ($type == 6) {
         return ($value,"","iconRadio,$color,0,light_light_dim_00,30,light_light_dim_30,50,light_light_dim_50,70,light_light_dim_70,80,light_light_dim_80,100,light_light_dim_100","set");
         } elsif ($type >= 7) {
           return ($value,"","iconRadio,$color,0,light_light_dim_00,20,light_light_dim_20,30,light_light_dim_30,50,light_light_dim_50,70,light_light_dim_70,80,light_light_dim_80,100,light_light_dim_100","set");
           } elsif ($type == 2) {
             return ($value,"","iconRadio,$color,0,light_light_dim_00,100,light_light_dim_100","set");
           }
 } 
 
 sub switch {
   my ($value,$icon_off,$icon_on,$state_off,$state_on)=@_;
   $state_on=(defined ($state_on) and $state_on ne "") ? $state_on : "on";
   $state_off=(defined ($state_off) and $state_off ne "") ? $state_off : "off";
   my $i_off=(defined ($icon_off) and $icon_off ne "") ? $icon_off : "off";
   $icon_on=((defined ($icon_on) and $icon_on ne "") ? $icon_on :(defined ($icon_off) and $icon_off ne "") ? "$icon_off\@DarkOrange" : "on");
   return($value,"",("iconSwitch,".$state_on.",".$i_off.",".$state_off.",".$icon_on));
 }
 
 sub icon {
   my ($value,$icon_off,$icon_on,$state_off,$state_on)=@_;
   $state_on=(defined ($state_on) and $state_on ne "") ? $state_on : "on";
   $state_off=(defined ($state_off) and $state_off ne "") ? $state_off : "off";
   my $i_off=(defined ($icon_off) and $icon_off ne "") ? $icon_off : "off";
   $icon_on=((defined ($icon_on) and $icon_on ne "") ? $icon_on :(defined ($icon_off) and $icon_off ne "") ? "$icon_off\@DarkOrange" : "on");
   return($value,"",("iconLabel,".$state_on.",".$icon_on.",".$state_off.",".$i_off));
 }
}