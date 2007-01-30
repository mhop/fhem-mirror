<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
 <xsl:template match="/FHZINFO">
	<HTML>

<STYLE>

BODY {
        font-size:8pt;
        font-family:Helvetica,Arial, Sans Serif;
        padding-bottom:0px;
        background-color:#d5d6d8

}

TD {
        font-size:8pt;
        font-family:Helvetica,Arial, Sans Serif;
        padding-bottom:0px;
        background-color:#d5d6d8

}
TABLE{
        border-spacing:0px
        cellpadding:0 
        cellspacing:0
}
</STYLE>


<BODY>

FS20<BR/>
<xsl:apply-templates select="FS20_DEVICES/FS20"/>


FHT<BR/>
<xsl:apply-templates select="FHT_DEVICES/FHT"/>

</BODY>
</HTML>
 </xsl:template>

 <xsl:template match="FS20">
        Name: <xsl:value-of select="@name"/><BR/>
        State: <xsl:value-of select="@state"/><BR/>
	<A>
		<xsl:attribute name="href">/cgi-bin/hfm_set.pl?action=setFS20&amp;name=<xsl:value-of select="@name"/>&amp;cmd=on&amp;thinclient=true</xsl:attribute>
		On
	</A> | 
	<A>
<xsl:attribute name="href">/cgi-bin/hfm_set.pl?action=setFS20&amp;name=<xsl:value-of select="@name"/>&amp;cmd=off&amp;thinclient=true</xsl:attribute>
Off</A> 
	<BR/><BR/> 
 </xsl:template>


 <xsl:template match="FHT">
        <B>Name: <xsl:value-of select="@name"/></B><BR/>
        <xsl:apply-templates/>
        <BR/><BR/>
 </xsl:template>

<xsl:template match="STATE">
	<xsl:if test='@name="measured-temp"'>
        <xsl:value-of select="@name"/>=<xsl:value-of select="@value"/><BR/>
    </xsl:if>    
	<xsl:if test="@name='desired-temp'">
        <xsl:value-of select="@name"/>=<xsl:value-of select="@value"/><BR/>
    </xsl:if>    
	<xsl:if test="@name='actuator'">
        <xsl:value-of select="@name"/>=<xsl:value-of select="@value"/><BR/>
    </xsl:if>    
 </xsl:template>


</xsl:stylesheet>
