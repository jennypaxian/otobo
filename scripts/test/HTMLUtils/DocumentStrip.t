# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# Copyright (C) 2019-2024 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use strict;
use warnings;
use utf8;

# Set up the test driver $Self when we are running as a standalone script.
use Kernel::System::UnitTest::RegisterDriver;

our $Self;

# get HTMLUtils object
my $HTMLUtilsObject = $Kernel::OM->Get('Kernel::System::HTMLUtils');

# DocumentStrip tests
my @Tests = (
    {
        Input => '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<HTML><HEAD>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=utf-8">

<META http-equiv="Content-Type content=text/html; charset=utf-8">
<META content="MSHTML 6.00.2900.3562" name=GENERATOR></HEAD>
<BODY style="FONT-SIZE: 12px; FONT-FAMILY: Courier New,monospace,fixed">
<DIV><SPAN class=678193704-17072009><FONT size=3><SPAN class=monospace>hm there is something
wrong....</SPAN></FONT></SPAN></DIV></BODY></HTML>',
        Result => "
\n
<DIV><SPAN class=678193704-17072009><FONT size=3><SPAN class=monospace>hm there is something
wrong....</SPAN></FONT></SPAN></DIV>",
        Name => 'DocumentStrip - MSHTML'
    },
    {
        Input => '<html>

<head>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=Windows-1252">

<meta name=Generator content="Microsoft Word 10 (filtered)">

<style>
<!--
 /* Font Definitions */
 @font-face
    {font-family:"Arial Unicode MS";
    panose-1:2 11 6 4 2 2 2 2 2 4;}
@font-face
    {font-family:"\@Arial Unicode MS";
    panose-1:2 11 6 4 2 2 2 2 2 4;}
 /* Style Definitions */
 p.MsoNormal, li.MsoNormal, div.MsoNormal
    {margin:0cm;
    margin-bottom:.0001pt;
    font-size:12.0pt;
    font-family:"Times New Roman";}
a:link, span.MsoHyperlink
    {color:blue;
    text-decoration:underline;}
a:visited, span.MsoHyperlinkFollowed
    {color:purple;
    text-decoration:underline;}
span.StyleCourrierlectronique17
    {font-family:Arial;
    color:windowtext;}
@page Section1
    {size:595.3pt 841.9pt;
    margin:70.85pt 70.85pt 70.85pt 70.85pt;}
div.Section1
    {page:Section1;}
-->
</style>

</head>

<body lang=FR link=blue vlink=purple>

<div class=Section1>

<p class=MsoNormal><font size=3 face="Courier New"><span lang=EN-GB
style=\'font-size:12.0pt;font-family:"Courier New"\'>Hello, <br>
</span></font></p>

</div>

</body>

</html>
',
        Result => "
\n\n\n\n
<div class=Section1>

<p class=MsoNormal><font size=3 face=\"Courier New\"><span lang=EN-GB
style='font-size:12.0pt;font-family:\"Courier New\"'>Hello, <br>
</span></font></p>

</div>
\n\n\n
",
        Name => 'DocumentStrip - Generator - Microsoft Word 10 (filtered)',
    },
    {
        Input => '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0 Transitional//EN">
<HTML><HEAD>
<META http-equiv="Content-Type content=text/html; charset=utf-8">
<META content="MSHTML 6.00.6002.18124" name=GENERATOR></HEAD>
<BODY style="FONT-SIZE: 12px; FONT-FAMILY: =
Geneva,Helvetica,Arial,sans-serif"=20
bgColor=#ffffff>
<DIV><FONT face=Arial size=2>xxx</FONT></DIV>
<DIV><FONT face=Arial size=2>
</FONT></DIV>
<DIV><FONT face=Arial size=2></FONT>&nbsp;</DIV>
<DIV><FONT face=Arial size=2>
</FONT></DIV>
<DIV><FONT face=Arial size=2></FONT>&nbsp;</DIV>
',
        Result => "\n\n
<DIV><FONT face=Arial size=2>xxx</FONT></DIV>
<DIV><FONT face=Arial size=2>
</FONT></DIV>
<DIV><FONT face=Arial size=2></FONT>&nbsp;</DIV>
<DIV><FONT face=Arial size=2>
</FONT></DIV>
<DIV><FONT face=Arial size=2></FONT>&nbsp;</DIV>
",

        Name => 'DocumentStrip - Generator - Microsoft Word 10 (filtered)',
    },
);

for my $Test (@Tests) {

    # these 2 lines are for Windows check-out
    $Test->{Input}  =~ s{\r\n}{\n}smxg;
    $Test->{Result} =~ s{\r\n}{\n}smxg;
    my $Ascii = $HTMLUtilsObject->DocumentStrip(
        String => $Test->{Input},
    );
    $Self->Is(
        $Ascii,
        $Test->{Result},
        $Test->{Name},
    );
}

$Self->DoneTesting();
