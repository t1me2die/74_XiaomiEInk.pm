#########################################################################
# Modul to extract sensorData from the Xiaomi LYWSD02 eInk Display
# 74_XiaomiEInk.pm
# 2019-10-19 12:00:00 
# Mathias Passow -> Contact -> mathias.passow@me.com
#
# version 0.0.5
#
# changes:
# 2019-10-19 initial alpha, privat testing
# 2019-10-20 reorder code
# 2019-10-23 add function "get device battery"
# 2019-10-24 add 24h function for "get device battery"
# 2019-10-24 update for bluez 5.51 - super alpha testing
# TO-DO: have to code -> getBlueZVersion 
#

package main;

use strict;
use warnings;
use POSIX;
use HttpUtils;
use utf8;
use feature						':5.14';

package FHEM::XiaomiEInk;

my $missingModul = "";

use GPUtils qw(GP_Import GP_Export);

eval "use Blocking;1" or $missingModul .= "Blocking ";

#use Data::Dumper;          only for Debugging

## Import der FHEM Funktionen
#-- Run before package compilation
BEGIN {

    # Import from main context
    GP_Import(
        qw(readingsSingleUpdate
          readingsBulkUpdate
          readingsBulkUpdateIfChanged
          readingsBeginUpdate
          readingsEndUpdate
          defs
          modules
          Log3
          CommandAttr
          AttrVal
          ReadingsVal
          IsDisabled
          deviceEvents
          init_done
          gettimeofday
          InternalTimer
          RemoveInternalTimer
          DoTrigger
          BlockingKill
          BlockingCall
          FmtDateTime
          readingFnAttributes
          makeDeviceName)
    );
}

#-- Export to main context with different name
GP_Export(
    qw(
      Initialize
      stateRequestTimer
      )
);

my %CallBatteryAge = (
    '8h'  => 28800,
    '16h' => 57600,
    '24h' => 86400,
    '32h' => 115200,
    '40h' => 144000,
    '48h' => 172800
);

sub Initialize($) {

    my ($hash) = @_;

    $hash->{SetFn}    = "FHEM::XiaomiEInk::Set";
    $hash->{GetFn}    = "FHEM::XiaomiEInk::Get";
    $hash->{DefFn}    = "FHEM::XiaomiEInk::Define";
    $hash->{NotifyFn} = "FHEM::XiaomiEInk::Notify";
    $hash->{UndefFn}  = "FHEM::XiaomiEInk::Undef";
    $hash->{AttrFn}   = "FHEM::XiaomiEInk::Attr";
    $hash->{AttrList} =
        "interval "
      . "disable:1 "
      . "disabledForIntervals ";

    return FHEM::Meta::InitMod( __FILE__, $hash );
}

sub Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );

    return $@ unless ( FHEM::Meta::SetInternals($hash) );
    use version 0.60; our $VERSION = FHEM::Meta::Get( $hash, 'version' );

    return "too few parameters: define <name> XiaomiEInk <BTMAC>" if ( @a != 3 );
    return "Cannot define XiaomiEInk device. Perl modul ${missingModul}is missing." if ($missingModul);

    my $name = $a[0];
    my $mac  = $a[2];

    $hash->{BTMAC}                       = $mac;
    $hash->{VERSION}                     = version->parse($VERSION)->normal;
    $hash->{INTERVAL}                    = 300;
    #$hash->{helper}{CallSensDataCounter} = 0;
    #$hash->{helper}{CallBattery}         = 0;
    $hash->{NOTIFYDEV}                   = "global,$name";
    $hash->{loglevel}                    = 4;

    readingsSingleUpdate( $hash, "state", "initialized", 0 );
    CommandAttr( undef, $name . ' room XiaomiEInk' ) if ( AttrVal( $name, 'room', 'none' ) eq 'none' );

    Log3 $name, 3, "XiaomiEInk ($name) - defined with BTMAC $hash->{BTMAC}";

    $modules{XiaomiEInk}{defptr}{ $hash->{BTMAC} } = $hash;
    return undef;
}

sub Get($$@) {

    my ( $hash, $name, @aa ) = @_;
    my ( $cmd, @args ) = @aa;
    my $mac  = $hash->{BTMAC};

    Log3 $name, 5, "XiaomiEInk name -> $name, cmd -> $cmd, mac -> $mac";

    if ($cmd eq 'sensorData' or $cmd eq 'model' or $cmd eq 'clock' or $cmd eq 'firmware' or $cmd eq 'manufactury') {
        return "usage: clock" if ( @args != 0 );
        Log3 $name, 4,"Get Mac -> $mac, Name -> $name, Cmd -> $cmd";
        myUtils_LYWSD02_main($mac,$name,$cmd);
        #stateRequest1($hash);
    }
    elsif($cmd eq 'battery' and (CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ) ) )
    {   myUtils_LYWSD02_main($mac,$name,$cmd);
        CallBattery_Timestamp($hash);
    }
    elsif($cmd eq 'battery' and (!CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ) ) )
    {   return "First you have to resetBatteryTimestamp, because your last batterycall is less then " .$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ." seconds in the past";
    }
    elsif ( $cmd eq 'devicename' ) {
        return "usage: devicename" if ( @args != 0 );

    }
    else 
    {   my $list = "";
        # List for the get commands
        $list .= "sensorData:noArg model:noArg clock:noArg firmware:noArg manufactury:noArg battery:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

    return undef;
}

sub Set($$@) {

    my ( $hash, $name, @aa ) = @_;
    my ( $cmd, @args ) = @aa;


    if ( $cmd eq 'resetBatteryTimestamp' ) 
    {   return "usage: resetBatteryTimestamp" if ( @args != 0 );
        $hash->{helper}{updateTimeCallBattery} = 0;
        return;
    }
    else 
    {   my $list = "";
        $list .= "resetBatteryTimestamp:noArg";
        return "Unknown argument $cmd, choose one of $list";
    }

    return undef;
}

sub Attr(@) {

    my ( $cmd, $name, $attrName, $attrVal ) = @_;
    my $hash = $defs{$name};

    if ( $attrName eq "disable" ) {
        if ( $cmd eq "set" and $attrVal eq "1" ) {
            Log3 $name, 3, "XiaomiEInk ($name) - disabled";
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "XiaomiEInk ($name) - enabled";
        }
    }

    elsif ( $attrName eq "disabledForIntervals" ) {
        if ( $cmd eq "set" ) {
            return "check disabledForIntervals Syntax HH:MM-HH:MM or 'HH:MM-HH:MM HH:MM-HH:MM ...'" unless ( $attrVal =~ /^((\d{2}:\d{2})-(\d{2}:\d{2})\s?)+$/ );
            Log3 $name, 3, "XiaomiEInk ($name) - disabledForIntervals";
            stateRequest1($hash);
        }

        elsif ( $cmd eq "del" ) {
            Log3 $name, 3, "XiaomiEInk ($name) - enabled";
        }
    }
    elsif ( $attrName eq "interval" ) {
        
        if ( $cmd eq "set" ) {
            if ( $attrVal < 120 ) {
                Log3 $name, 3, "XiaomiEInk ($name) - interval too small, please use something >= 120 (sec), default is 300 (sec)";
                return "interval too small, please use something >= 120 (sec), default is 300 (sec)";
            }
            else {
                $hash->{INTERVAL} = $attrVal;
                Log3 $name, 3, "XiaomiEInk ($name) - set interval to $attrVal";
            }
        }

        elsif ( $cmd eq "del" ) {
            $hash->{INTERVAL} = 300;
            Log3 $name, 3, "XiaomiEInk ($name) - set interval to default";
        }
    }

    return undef;
}

sub Notify($$) {

    my ( $hash, $dev ) = @_;
    my $name = $hash->{NAME};
    return stateRequestTimer($hash) if ( IsDisabled($name) );

    my $devname = $dev->{NAME};
    my $devtype = $dev->{TYPE};
    my $events  = deviceEvents( $dev, 1 );
    return if ( !$events );

    stateRequestTimer($hash)
      if (
        (
            (
                (
                    grep /^DEFINED.$name$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.disable$/,
                    @{$events}
                    or grep /^ATTR.$name.disable.0$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.interval$/,
                    @{$events}
                    or grep /^DELETEATTR.$name.model$/,
                    @{$events}
                    or grep /^ATTR.$name.interval.[0-9]+/,
                    @{$events}
                )
                and $devname eq 'global'
            )
        )
        and $init_done
        or (
            (
                grep /^INITIALIZED$/,
                @{$events}
                or grep /^REREADCFG$/,
                @{$events}
                or grep /^MODIFIED.$name$/,
                @{$events}
            )
            and $devname eq 'global'
        )
      );
  
    return;
}

sub Undef($$) {

    my ( $hash, $arg ) = @_;

    my $mac  = $hash->{BTMAC};
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    BlockingKill( $hash->{helper}{RUNNING_PID} )
      if ( defined( $hash->{helper}{RUNNING_PID} ) );

    delete( $modules{XiaomiEInk}{defptr}{$mac} );
    Log3 $name, 3, "Sub XiaomiEInk_Undef ($name) - delete device $name";
    return undef;
}


sub myUtils_LYWSD02_main($$$)
{   my ($mac,$name,$cmd) = @_;
    my $hash = $defs{$name};
    my $arg;
  
    Log3 $name, 4,"myUtils_LYWSD02_main, Mac -> $mac, Name -> $name, Cmd -> $cmd, HASH -> $hash";
    readingsSingleUpdate( $hash, "job", "read sensorData", 1 ) if ($cmd eq 'sensorData');
    readingsSingleUpdate( $hash, "job", "read model", 1 ) if ($cmd eq 'model');
    readingsSingleUpdate( $hash, "job", "read clock", 1 ) if ($cmd eq 'clock');
    readingsSingleUpdate( $hash, "job", "read firmware", 1 ) if ($cmd eq 'firmware');
    readingsSingleUpdate( $hash, "job", "read manufactury", 1 ) if ($cmd eq 'manufactury');
    readingsSingleUpdate( $hash, "job", "read battery", 1 ) if ($cmd eq 'battery');
  
    # Set Parameter to execute statement
    $arg = 'scan on,scan off,quit' if($cmd eq 'sensorData');
    $arg = 'a,quit' if($cmd eq 'clock' or $cmd eq 'firmware' or $cmd eq 'manufactury' or $cmd eq 'model' or $cmd eq 'battery');
  
    # NonBlocking Call to run Subroutine
    $hash->{helper}{RUNNING_PID} = BlockingCall(
        "FHEM::XiaomiEInk::BluetoothCommands",
        $name . "|" . $mac . "|" . $arg ."|" .$cmd,
        "FHEM::XiaomiEInk::BluetoothCommands_Done",
        90,
        "FHEM::XiaomiEInk::BluetoothCommands_Aborted",
        $hash
    ) unless ( exists( $hash->{helper}{RUNNING_PID} ));
    Log3 $name, 5, "Sub myUtils_LYWSD02_main ($name) - hash -> $hash, cmd -> $cmd";
}


# Script for executing a series of bluetoothctl commands
# ======================================================
#	BluetoothCommands ( <list> );
#		<list> = list of arguments to be submitted by BluetoothCommands;
#
#	Note:	in order to facilitate debugging of additional features
#			  - all display-control character seqences are eliminated,
#			  - nl is eplaced by @

sub BluetoothCommands($) 
{	
    use IPC::Open2;
    use IO::Select;
    use constant	LAUNCH_TIMEOUT	=>	30;			# timeout before submission of next command (seconds)

    my ($string) = @_;
    my ($name, $mac, $arg, $cmd) = split("\\|", $string);

    Log3 $name, 4,"BluetoothCommands, Name -> $name, Mac -> $mac, ARG -> $arg, Cmd -> $cmd";
    my $x_response = '';
    my $in_fid;
    my $out_fid;

    if ($cmd eq 'sensorData'){
        open2 ( $in_fid, $out_fid, 'bluetoothctl'.' 2>&1' );
    }
    elsif ($cmd eq 'model') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x03".' 2>&1' );
    }
    elsif ($cmd eq 'clock') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x3e".' 2>&1' );
    }
    elsif ($cmd eq 'firmware') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x14".' 2>&1' );
    }
    elsif ($cmd eq 'manufactury') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x0c".' 2>&1' );
    }
    elsif ($cmd eq 'battery') {
        open2 ( $in_fid, $out_fid, "gatttool -b $mac --char-read -a 0x52".' 2>&1' );
    }
    my $x_select = IO::Select->new ( [$in_fid] );
    my $x_controller = '';
    my $prec_command = '';
    my $next_command;
    my $i = 0;
    my $art = ' ';
    my $temperatur = 0;
    my $humidity = 0;
    my $hex;
    my $model = '';
    my $clock = '';
    my $firmware = '';
    my $manufactury = '';
    my $battery = '';
    my $temp_zaehler = 0;
    my $humi_zaehler = 0;
	my $flg = 0;
	my $save_lastBuffer = 0;
	my $flg_humi = 0;
	my $firstCatch = 0;
    my @ARGV = split(',',$arg);
    my $hash = $defs{$name};

    Log3 $name, 4, "XiaomiEInk ARGV -> @ARGV, mac -> $mac, name -> $name, cmd -> $cmd";

    foreach ( @ARGV, 'quit') {
        $next_command = $_;

        # Wait for input sollicitation, loop through action info

        while (1) {
            my $x_buffer = '';

            # Read chunks (unbuffered) and assemble lines
            my $launch_flag = 0;
            do {
                my $x_chunk;
                my @x_ready = $x_select->can_read (LAUNCH_TIMEOUT);
                if ( @x_ready == 0 ) 
                {   $launch_flag = 1;
                    last;
                }
                sysread ( $in_fid, $x_chunk , 1 );
                $x_buffer .= $x_chunk;
                $x_buffer =~ s/\r/%/g;
                $x_buffer =~ s/\n/@/g;
                if ($x_buffer =~ /@/ and $cmd eq 'clock') {
                    my $pos = index($x_buffer,'descriptor:');
                    if ($pos != -1) {
                       $hex = substr($x_buffer,$pos+21,2) .substr($x_buffer,$pos+18,2) .substr($x_buffer,$pos+15,2) .substr($x_buffer,$pos+12,2);
                       my $time = hex($hex);
                       my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime( $time );
                       $mon  += 1;
                       $year += 1900;
                       if(length($sec) < 2){ $sec="0".$sec; }
                       if(length($min) < 2){ $min="0".$min; }
                       if(length($hour) < 2){ $hour="0".$hour; }
                       if(length($mday) < 2){ $mday="0".$mday; }
                       if(length($mon) < 2){ $mon="0".$mon; }
                       $clock = $mday .'.' .$mon .'.' .$year .'-' .$hour .':' .$min .':' .$sec;
                       Log3 $name, 4, "x_Buffer -> $x_buffer, cmd -> $cmd, launch_flag -> $launch_flag, hex -> $hex, time -> $time, clock -> $clock";
                       return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                    }
                       Log3 $name, 4, "Buffer-Last? x_Buffer -> $x_buffer, cmd -> $cmd, launch_flag -> $launch_flag";
                       last;
                }
                if ($x_buffer =~ /@/ and $cmd eq 'firmware') {
                   my $pos = index($x_buffer,'descriptor:');
                   if ($pos != -1) {
                      $hex = substr($x_buffer,$pos+12);
                      $hex =~ s/\s+//g;
                      $firmware = pack('H*',$hex);
                      return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                   }
                }
                if ($x_buffer =~ /@/ and $cmd eq 'manufactury') {
                   my $pos = index($x_buffer,'descriptor:');
                   if ($pos != -1) {
                      $hex = substr($x_buffer,$pos+12);
                      $hex =~ s/\s+//g;
                      $manufactury = pack('H*',$hex);
                      return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                   }
                }
                if ($x_buffer =~ /@/ and $cmd eq 'model') {
                   my $pos = index($x_buffer,'descriptor:');
                   if ($pos != -1) {
                      $hex = substr($x_buffer,$pos+12);
                      $hex =~ s/\s+//g;
                      $model = pack('H*',$hex);
                      return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                   }
                }
                if ($x_buffer =~ /@/ and $cmd eq 'battery') {
                   my $pos = index($x_buffer,'descriptor:');
                   if ($pos != -1) {
                      $hex = substr($x_buffer,$pos+12,2);
                      $hex =~ s/\s+//g;
                      $battery = hex($hex);
                      return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                   }
                   elsif($pos == -1)
                   {   return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|error";
                   }
                }
            } until ( $x_buffer =~ /^%*[^\[].*#\s+/ );

            if ( $launch_flag )
            {   last;
            }
            $x_buffer =~ s/(\n|\e\[0m|\e\[0;\d+m|\e\[0|\e\[K)//g;
            $x_buffer =~ /^%*(.*)@\[bluetooth/;
            unless ( $x_buffer =~ /^\s*$/ ) 
            {   #print "\n<- Angekommen hier...     $1\n";
                if ($flg == 1)
				{	if (substr($x_buffer, 65, 1) eq '4')
					{	$hex = substr($x_buffer,73,2);
						$temperatur = hex($hex)/10;
						$temp_zaehler += 1;
						$flg = 0;
					}
					elsif (substr($x_buffer, 65, 1) eq '6')
					{	$hex = substr($x_buffer,73,2);
						$flg_humi = 1;
					}
					elsif ($flg_humi == 1)
					{	$hex = substr($x_buffer,28,2) .$hex;
						$humidity = hex($hex)/10;
						$humi_zaehler += 1;
						$flg = 0;
						$flg_humi = 0;
					}
				}
				
				if ($x_buffer =~ /$mac/ and $x_buffer =~ /Key/)
                {   $i = 1;
                }
                elsif ($x_buffer =~ /$mac/ and $x_buffer =~ /Value/ and $x_buffer !~ /Characteristic/ and $flg_humi == 0)
                {   $i+=1;
                    $flg = 1;
                }
                elsif ($flg_humi == 1)
                {   $flg = 1;
                }
                else
                {   $i=0;
                    $art = '';
                    $hex = '';
                    $flg = 0;
                    $flg_humi = 0;
                }
                
                if ($i == 14)
                {   my $pos = index($x_buffer,'0x');
                    if ($pos != -1)
                    {   $art = substr($x_buffer,$pos+2,2);
                    }
                }
                # Temperatur
                if ($art =~ /4/ and $i == 17)
                {   my $pos = index($x_buffer,'0x');
                    $hex = substr($x_buffer,$pos+2,2);
                    $temperatur = hex($hex)/10;
                    $temp_zaehler +=1;
                }
                elsif ($art =~ /6/ and $i == 17)
                {   my $pos = index($x_buffer,'0x');
                    $hex = substr($x_buffer,$pos+2,2);
                }
                elsif ($art =~ /6/ and $i == 18)
                {   my $pos = index($x_buffer,'0x');
                    $hex = substr($x_buffer,$pos+2,2) .$hex;
                    $humidity = hex($hex)/10;
                    if ($humi_zaehler == 0)
                    {   return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                    }
                    $humi_zaehler +=1;
                }
                if($humi_zaehler > 3 or $temp_zaehler > 3)
                {   Log3 $name, 4, "XiaomiEInk Abbruch, humi_zaehler -> $humi_zaehler --- temp_zaehler -> $temp_zaehler";
                    return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                }
                if($humi_zaehler >= 1 and $temp_zaehler >= 1)
                {   Log3 $name, 4, "XiaomiEInk Ende, alles gefunden! Name->$name|Mac->$mac|Arg->$arg|Temperatur->$temperatur|Humidity->$humidity";
                    return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
                }
            }
            if ( $x_buffer =~ /Controller\s+(\S+)/ ) 
            {   $x_response = $1;
            }

            # Assembling of output from bluetoothctl is complete
            #	- loop until all output is seen
            #	- stop looping and wait for timeout:
            #		on error message,
            #		when reception of output stops

            if ( $x_buffer =~ /(.+Invalid.+)\[/ ) {
               $next_command = 'quit';
               $x_response = $1;
            }

            if ( $prec_command eq 'quit' ) {
               last;
            }

        } # while looping through actions, waiting for sollicitation
        if ( $prec_command eq 'quit' ) {last;}
        #print "\n     $next_command  ->\n";
        print $out_fid "$next_command\n";
        $prec_command = $next_command;
    }
    close ( $in_fid );
    close ( $out_fid );
    return "$name|$mac|$arg|$temperatur|$humidity|$model|$clock|$firmware|$manufactury|$battery|ok";
}

sub BluetoothCommands_Done($) {

    my $string = shift;
    my ($name, $mac, $arg, $temperatur, $humidity, $model, $clock, $firmware, $manufactury, $battery, $error) = split( "\\|", $string );
    my $hash = $defs{$name};

    if ($error eq 'ok')
    {   readingsSingleUpdate($hash, "temperature", $temperatur, 1) if ($temperatur != 0);
        Log3 $name, 3,"BluetoothCommands_Done ($name) - temperatur";
        readingsSingleUpdate($hash, "humidity", $humidity, 1) if ($humidity != 0);
        Log3 $name, 3,"BluetoothCommands_Done ($name) - humidity";
        readingsSingleUpdate($hash, "state", 'T: ' . ReadingsVal( $name, 'temperature', 0 ) . ' H: ' . ReadingsVal( $name, 'humidity', 0 ), 1);
        Log3 $name, 3,"BluetoothCommands_Done ($name) - state";
        readingsSingleUpdate($hash, "model", $model, 1) if ($model ne '');
        readingsSingleUpdate($hash, "clock", $clock, 1) if ($clock ne '');
        readingsSingleUpdate($hash, "firmware", $firmware, 1) if ($firmware ne '');
        readingsSingleUpdate($hash, "manufactury", $manufactury, 1) if ($manufactury ne '');
        if ($battery ne '')
           {   readingsSingleUpdate($hash, "batteryPercent", $battery, 1);
           if ($battery > 15)
           {   readingsSingleUpdate($hash, "battery", "ok", 1);
           }
           elsif ($battery <= 15)
           {   readingsSingleUpdate($hash, "battery", "low", 1);
           }
           CallBattery_Timestamp($hash);
        }
        readingsSingleUpdate($hash, "job", "done", 1);
    }
    elsif($error ne 'error')
    {   readingsSingleUpdate($hash, "job", "error", 1);
    }
    delete( $hash->{helper}{RUNNING_PID} );

    Log3 $name, 5,"BluetoothCommands ($name) - BluetoothCommands: Helper is disabled. Stop processing"
}

sub BluetoothCommands_Aborted($) {

    my ($hash) = @_;
    my $name = $hash->{NAME};
    my %readings;

    delete( $hash->{helper}{RUNNING_PID} );
    readingsSingleUpdate( $hash, "state", "unreachable", 1 );
    readingsSingleUpdate( $hash, "job", "aborted", 1 );

    #$readings{'lastGattError'} = 'The BlockingCall Process terminated unexpectedly. Timedout';
    
    Log3 $name, 4, "XiaomiEInk ($name) - BluetoothCommands_Aborted: The BlockingCall Process terminated unexpectedly. Timedout";
}

sub stateRequestTimer($) {

    my ($hash) = @_;

    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);
    stateRequest1($hash);

    InternalTimer( gettimeofday() + $hash->{INTERVAL} + int( rand(60) ), "XiaomiEInk_stateRequestTimer", $hash );

    Log3 $name, 4, "XiaomiEInk ($name) - stateRequestTimer: Call Request Timer";
}

sub stateRequest1($) 
{   my ($hash) = @_;
    my $name = $hash->{NAME};
    my $mac = $hash->{BTMAC};
    my %readings;

       if ( !IsDisabled($name) ) {
            if (ReadingsVal( $name, 'model', '' ) =~ /LYWSD02/ )
            {   if (CallBattery_IsUpdateTimeAgeToOld($hash,$CallBatteryAge{ AttrVal( $name, 'BatteryFirmwareAge','24h' ) } ) )
                {   myUtils_LYWSD02_main($mac,$name,'battery');
                }
                else
                {   myUtils_LYWSD02_main($mac,$name,'sensorData');
                }
            }
            elsif ( AttrVal( $name, 'model', 'none' ) eq 'none' ) 
            {   readingsSingleUpdate( $hash, "state", "get model first", 1 );
            }
       }
}

## Routinen damit Firmware und Batterie nur alle X male statt immer aufgerufen wird
sub CallBattery_Timestamp($) 
{   my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{helper}{updateTimeCallBattery} = gettimeofday();    # in seconds since the epoch
    $hash->{helper}{updateTimestampCallBattery} = FmtDateTime( gettimeofday() );
    Log3 $name, 3, "CallBattery_Timestamp - hash -> " .$hash->{helper}{updateTimeCallBattery} ." und " .$hash->{helper}{updateTimestampCallBattery};
}

sub CallBattery_UpdateTimeAge($) 
{   my $hash = shift;
    my $name = $hash->{NAME};

    $hash->{helper}{updateTimeCallBattery} = 0 if ( not defined( $hash->{helper}{updateTimeCallBattery} ) );
    my $UpdateTimeAge = gettimeofday() - $hash->{helper}{updateTimeCallBattery};
    Log3 $name, 3, "CallBattery_UpdateTimeAge - UpdateTimeAge -> $UpdateTimeAge";
    return $UpdateTimeAge;
}


sub CallBattery_IsUpdateTimeAgeToOld($$) 
{   my ( $hash, $maxAge ) = @_;
    my $name = $hash->{NAME};

    Log3 $name, 3, "CallBattery_IsUpdateTimeAgeToOld - hash -> $hash, maxAge -> $maxAge";
    return ( CallBattery_UpdateTimeAge($hash) > $maxAge ? 1 : 0 );
}

1;

=pod
=item device
=item summary_DE    Modul um Daten vom Xiaomi BTLE Sensoren aus zu lesen

=begin html_DE

<a name="XiaomiEInk"></a>
<h3>Xiaomi BTLE Sensor</h3>
<ul>
  <u><b>XiaomiEInk - liest Daten von einem Xiaomi eInk Sensor aus</b></u>
  <br />
  Dieser Modul liest Daten von einem Sensor und legt sie in den Readings ab.<br />
  Auf dem (Linux) FHEM-Server werden gatttool, hcitool und bluetoothctl vorausgesetzt. (sudo apt install bluez)<br />
  Bitte unbedingt auf die Berechtigung achten! Der FHEM User muss in der bluetooth group vorhanden sein. <br />
  Zum kontrollieren kann man sich mit "cat /etc/group" die Berechtigungen anzeigen lassen. <br />
  Dort sollte die Berechtigung wie folgt aussehen "bluetooth:x:111:fhem,pi"
  <br /><br />
  <a name="XiaomiEInkdefine"></a>
  <b>Define</b>
  <ul><br />
    <code>define &lt;name&gt; XiaomiEInk &lt;BT-MAC&gt;</code>
    <br /><br />
    Beispiel:
    <ul><br />
      <code>define wz_Xiaomi_eInk XiaomiEInk E7:2E:00:E2:74:D6</code><br />
    </ul>
    <br />
    Der Befehl legt ein Device vom Typ XiaomiEInk mit dem Namen wz_Xiaomi_eInk und der Bluetooth MAC E7:2E:00:E2:74:D6 an.<br />
    Nach dem Anlegen muss zuerst ein "get Device model" erfolgen. Das Modul kann erst mit dem ermittelten model die Werte für Temperatur + Luftfeuchtigkeit ermitteln.
  </ul>
  <br /><br />
  <a name="XiaomiEInkreadings"></a>
  <b>Readings</b>
  <ul>
    <li>state - Temperatur + Luftfeuchtigkeit oder eine Fehlermeldung.</li>
    <li>battery - aktueller Batterie-Status in Abhängigkeit vom Wert batteryPercent.</li>
    <li>batteryPercent - aktueller Ladestand der Batterie in Prozent.</li>
    <li>clock - Uhrzeit auf dem Gereat</li>
    <li>firmware - aktuelle Firmware-Version des BTLE Sensor</li>
    <li>humidity - aktuelle Luftfeuchtigkeit</li>
    <li>temperature - aktuelle Temperatur</li>
    <li>job - aktuelle Status des Job</li>
    <li>manufactury - Hersteller</li>
    <li>model - Modellbezeichnung vom Sensor</li>
  </ul>
  <br /><br />
  <a name="XiaomiEInkset"></a>
  <b>Set</b>
  <ul>
    <li>resetBatteryTimestamp - wenn die Batterie gewechselt wurde</li>
    <br />
  </ul>
  <br /><br />
  <a name="XiaomiEInkGet"></a>
  <b>Get</b>
  <ul>
    <li>battery - liest den Batteriestand aus</li>
    <li>clock - liest die Uhrzeit aus</li>
    <li>firmware - liest die Firmware Version aus</li>
    <li>manufactury - liest den Hersteller aus</li>
    <li>model - liest das Model aus, diese Information wird fuer das Modul benoetigt</li>
    <li>sensorData - liest die Werte Temperatur / Luftfeuchtigkeit aus</li>
    <br />
  </ul>
  <br /><br />
  <a name="XiaomiEInkattribut"></a>
  <b>Attribute</b>
  <ul>
    <li>disable - deaktiviert das Device</li>
    <li>interval - Interval in Sekunden zwischen zwei Abfragen</li>
    <li>disabledForIntervals - deaktiviert das Gerät für den angegebenen Zeitinterval (13:00-18:30 or 13:00-18:30 22:00-23:00)</li>
  </ul>
</ul>

=end html_DE

=for :application/json;q=META.json 74_XiaomiEInk.pm
{
  "abstract": "Modul to retrieves data from a Xiaomi eInk Sensors",
  "x_lang": {
    "de": {
      "abstract": "Modul um Daten vom Xiaomi eInk Sensoren aus zu lesen"
    }
  },
  "keywords": [
    "fhem-mod-device",
    "fhem-core",
    "EInk",
    "BTLE",
    "Xiaomi",
    "Sensor",
    "Bluetooth LE"
  ],
  "release_status": "unstable",
  "license": "GPL_2",
  "version": "v0.0.5",
  "author": [
    "Mathias Passow <mathias.passow@me.com>"
  ],
  "x_fhem_maintainer": [
    "t1me2die"
  ],
  "x_fhem_maintainer_github": [
    "nicht vorhanden"
  ],
  "prereqs": {
    "runtime": {
      "requires": {
        "FHEM": 5.00918799,
        "perl": 5.016, 
        "Meta": 1,
        "Blocking": 1
      }
    }
  }
}
=end :application/json;q=META.json

=cut
