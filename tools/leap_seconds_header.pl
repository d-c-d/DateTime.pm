#!/usr/bin/perl -w

use strict;
use lib './lib';

my $leap = shift || './leaptab.txt';

open my $fh, "<$leap" or die "Cannot read $leap: $!";

my $x = 1;
my %months = map { $_ => $x++ } qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

my @LeapSeconds;
my @RD;
my %RDLength;

my $value = 32 - 24;
while (<$fh>)
{
    my ( $year, $mon, $day, $leap_seconds ) = split /\s+/;

    $mon =~ s/\W//;

    $leap_seconds =~ s/^([+-])//;
    my $mult = $1 eq '+' ? 1 : -1;

    my $utc_epoch = _ymd2rd( $year, $months{$mon}, $day );

    $value += $leap_seconds * $mult;

    push @LeapSeconds, $value;
    push @RD, $utc_epoch;

    $RDLength{ $utc_epoch - 1 } = $leap_seconds;
}

close $fh;

push @LeapSeconds, ++$value;

my $set_leap_seconds = <<"EOF";

#define SET_LEAP_SECONDS(utc_rd, ls)  \\
{                                     \\
  {                                   \\
    if (utc_rd < $RD[0]) {            \\
      ls = $LeapSeconds[0];           \\
EOF

for ( my $x = 1; $x < @RD; $x++ )
{
    my $else = $x == 1 ? '' : 'else ';

    my $condition =
        $x == @RD ? "utc_rd < $RD[$x]" : "utc_rd >= $RD[$x - 1] && utc_rd < $RD[$x]";

    $set_leap_seconds .= <<"EOF"
    } else if ($condition) {  \\
      ls = $LeapSeconds[$x];                      \\
EOF
}

$set_leap_seconds .= <<"EOF";
    } else {                         \\
      ls = $LeapSeconds[-1];       \\
    }                              \\
  }                                \\
}
EOF

my $set_extra_seconds = <<"EOF";

#define SET_EXTRA_SECONDS(utc_rd, es)  \\
{                                      \\
  {                                    \\
    es = 0;                            \\
    switch (utc_rd) {                  \\
EOF

my $set_day_length = <<"EOF";

#define SET_DAY_LENGTH(utc_rd, dl)     \\
{                                      \\
  {                                    \\
    dl = 86400;                        \\
    switch (utc_rd) {                  \\
EOF

foreach my $utc_rd ( sort keys %RDLength )
{
    $set_extra_seconds .= <<"EOF";
      case $utc_rd: es = $RDLength{$utc_rd}; break;            \\
EOF

    $set_day_length .= <<"EOF";
      case $utc_rd: dl = 86400 + $RDLength{$utc_rd}; break;    \\
EOF
}

$set_extra_seconds .= <<"EOF";
    }                                  \\
  }                                    \\
}
EOF

$set_day_length .= <<"EOF";
    }                                  \\
  }                                    \\
}
EOF

open $fh, '>leap_seconds.h' or die "Cannot write to leap_seconds.h: $!";

print $fh $set_leap_seconds, $set_extra_seconds, $set_day_length;

# from lib/DateTimePP.pm
sub _ymd2rd
{
    use integer;
    my ( $y, $m, $d ) = @_;
    my $adj;

    # make month in range 3..14 (treat Jan & Feb as months 13..14 of
    # prev year)
    if ( $m <= 2 )
    {
        $y -= ( $adj = ( 14 - $m ) / 12 );
        $m += 12 * $adj;
    }
    elsif ( $m > 14 )
    {
        $y += ( $adj = ( $m - 3 ) / 12 );
        $m -= 12 * $adj;
    }

    # make year positive (oh, for a use integer 'sane_div'!)
    if ( $y < 0 )
    {
        $d -= 146097 * ( $adj = ( 399 - $y ) / 400 );
        $y += 400 * $adj;
    }

    # add: day of month, days of previous 0-11 month period that began
    # w/March, days of previous 0-399 year period that began w/March
    # of a 400-multiple year), days of any 400-year periods before
    # that, and 306 days to adjust from Mar 1, year 0-relative to Jan
    # 1, year 1-relative (whew)

    $d += ( $m * 367 - 1094 ) / 12 + $y % 100 * 1461 / 4 +
          ( $y / 100 * 36524 + $y / 400 ) - 306;
}
