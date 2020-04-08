#!/usr/bin/env perl

=head1 reboot-abort.pl

This script:

- blocks reboot, shutdown and halt
- conditionally allows a reboot, shutdown or halt
- is reset on startup

=cut

use strict;
use warnings;
use Getopt::Long;
use File::Path qw(make_path);
use IO::File;

eval {
	require Data::Dumper;
	Data::Dumper->import;
};

# empty Dumper routine if Data::Dumper is not available
if ($@) { sub Dumper{} }


my $rejectReboot=0;
my $allowReboot=0;
my $rebootCmd='';
my $help=0;
my $debug=0;
my $installReboot=0;
my $eraseReboot=0;
my @allowedUsers = qw[ root ];

=head1 Configuration File

 The configartion file is ~/.reboot-abort/checks.conf

 The format is simple:

 config-type:value

 At this time there is only one config type: check
 The value is the full path to a script or program that succeeds or fails

 For instance: do not allow a reboot if the boot partition is GE 90% used

 check:/usr/local/bin/check-boot-space.sh


=cut

my ($username,$homeDir)=(getpwent())[0,7];
my $configDir='.reboot-abort';
my $configFile='checks.conf';
# fully pathed
my $fpConfigFile="${homeDir}/${configDir}/${configFile}";


###################################
# Variables
###################################
#
# keeping this simple for now with global vars
# if the script needs to get more complex - rewrite it

# vars for the run directories and files
my @runDirs= (
	'/run/systemd/system/halt.target.d',
	'/run/systemd/system/poweroff.target.d',
	'/run/systemd/system/reboot.target.d',
);

my $runFile='reboot-abort.conf';

# the contents of the runFile
my %directives = ();

$directives{allow}="[Unit]
RefuseManualStart=no
";

$directives{reject}="[Unit]
RefuseManualStart=yes
";

my $rootBin = "${homeDir}/bin";
my $chkBootScript='check-boot-space.sh';

# get the cli options
GetOptions (
	"r|reject!" => \$rejectReboot,
	"a|allow!" => \$allowReboot,
	"i|install!" => \$installReboot,
	"e|erase!" => \$eraseReboot,
	"d|debug!" => \$debug,
	"h|help!" => \$help,
	"c|cmd|command=s" => \$rebootCmd,
) or die usage(1);

if ($help) {
	usage(); 
	exit 0;
}  

# take advantage of the numeric flag values
my $flagSums = $rejectReboot + $allowReboot + $installReboot + $eraseReboot;
if ($flagSums > 1) { usage(); exit 42 }
if ($flagSums and $rebootCmd ) { usage(); exit 43 }

print qq{

  reject: $rejectReboot
   allow: $allowReboot
 install: $installReboot
   erase: $eraseReboot
     cmd: $rebootCmd

} if $debug;

if (! checkUsers($username,\@allowedUsers)) {
	die "user $username not allowed to reboot\n";
} else {
	print "user $username is allowed to reboot\n" if $debug;
}


if ($rebootCmd and ! validateCmd("$rebootCmd") ) {
	print "command: $rebootCmd\n";
	die "that is an invalid cmd\n";
}


if ($allowReboot) {
	print "configuring to allow reboot\n" if $debug;
	allow();
	exit;
} elsif ($rejectReboot) {
	reject();
	exit;
} elsif ($rebootCmd) {
	my @checks=getChecks($fpConfigFile);
	die "no checks configured\n" unless @checks;
	reboot(\@checks, $rebootCmd);
	exit;
} elsif ($installReboot) {
	install();
	exit;
} else {
	print "Unknown State\n";
	exit 44;
}


############################
# subroutines
############################


sub createDirs {
	foreach my $dir ( @runDirs ) {
		print "mkdir: $dir\n" if $debug;
		eval {
			make_path($dir);
		};
		if ( $@ ) { die "could not create $dir\n" }
	}
}

sub writeDirective {
	# must be 'allow' or 'reject'
	my $directive = shift;
	die "directive of $directive is invalid\n" unless $directive =~ /^(allow|reject)$/;
	print "inside writeDirective()\n" if $debug;
	print Dumper(\@runDirs) if $debug;
	foreach my $dir ( @runDirs ) {
		my $fh = IO::File->new;
		my $outFile="${dir}/${runFile}";
		print "outFile: $outFile\n" if $debug;
		$fh->open($outFile,'>') or die "could not open $outFile - $!\n";
		$fh->print($directives{$directive});
	}
}

sub reject {
	createDirs();
	writeDirective('reject');
}

sub allow {
	print "inside allow()\n" if $debug;
	createDirs();
	writeDirective('allow');
}

sub getChecks {
	my $configFile = shift;

	-r $configFile || die "Cannot read $configFile\n";

	my $fh = IO::File->new;

	$fh->open($configFile,'<');
	
	my @rawLines = <$fh>;
	chomp @rawLines;

	print '@rawLines ' . Dumper(\@rawLines) if $debug;

	my @lines=grep(/^check:/,@rawLines);

	print '@lines ' . Dumper(\@lines) if $debug;

	my @checks=();;
	foreach my $line (@lines) {
		my ($dummy,$check) = split(/:/,$line);
		push @checks, $check;
	}

	print '@checks: ' . Dumper(\@checks) if $debug;

	return @checks;

}

sub reboot {

	my ($checksArrayRef,$rebootCmd) = @_;

	foreach my $chkCmd (@{$checksArrayRef}) {
		print "reboot:chkCmd: $chkCmd\n" if $debug;
		my $result = system($chkCmd);
		# remember - shell returns non-zero for success
		if ( $result ) {
			warn "current check: $chkCmd\n";
			warn "Check returned negative result\n";
			die "cannot reboot\n";
		}
	}

	# allow reboot
	# then run the command
	
	allow();
	my $cmdResults=qx/$rebootCmd/;

	print "cmdResults: $cmdResults\n";

	return;

}

sub validateCmd {
	my $cmd = shift;

	# no multiple commands - ie no ';' allowed
	# must start with shutdown, reboot or halt

	my $allowed=0;
	
	if ( $cmd =~ /^(reboot|shutdown|halt})/ ) { $allowed = 1}
	
	if ( $cmd =~ /;/ ) { $allowed = 0 }

	return $allowed;

}

sub usage {

	print "stub for usage\n";

	return;

}


sub checkUsers {
	my ($username, $userArrayRef) = @_;

	if ( grep(/^$username$/,@{$userArrayRef})) {
		return 1;
	} else {
		return 0;
	};
}


# service used to setup when booted
my %service = ();

$service{dir} = '/etc/systemd/system';
$service{name} = 'set-reboot-abort.service';
$service{text} = q{

[Unit]
Description=Start /boot partition full protection - cannot reboot if disk is full

[Service]
ExecStart=/root/bin/reboot-abort.pl --reject

[Install]
WantedBy=multi-user.target

};


sub getCheckScript {
	my $checkBootFile = "${rootBin}/${chkBootScript}";
	my $fh = IO::File->new;
	$fh->open($checkBootFile,'>') or die "could not create $checkBootFile - $!\n";
	while (<DATA>) {
		print $fh $_;
	}
	chmod 0750, $checkBootFile;
}

sub createConfig {

	if (-f $fpConfigFile ) {
		warn "cowardly refusing to overwrite: $fpConfigFile\n";
		return;
	}

	make_path("${homeDir}/${configDir}");
	my $fh = IO::File->new;
	$fh->open($fpConfigFile,'>') or die "could not create $configFile - $!\n";
	print $fh "check:/bin/true\n";
	print $fh "check:/bin/false\n";
	print $fh "check:${rootBin}/${chkBootScript}\n";
	$fh->close;	
}

sub removeConfig {
}

sub install  {
	print "\ninstall: calling getCheckScript\n" if $debug;
	getCheckScript();
	print "\ninstall: calling createConfig\n" if $debug;
	createConfig();
}


sub remove {
}


__DATA__
#!/usr/bin/env bash

declare fsName='/boot'

declare maxAllowedPctSpaceUsed=15
declare maxAllowedPctInodesUsed=15

declare pctSpaceUsed
declare pctInodesUsed


pctSpaceUsed=$(df --output=pcent $fsName| tail -n -1 | sed -r -e 's/[ %]//g')
pctInodesUsed=$(df --output=ipcent $fsName| tail -n -1 | sed -r -e 's/[ %]//g')

declare retval=1;

if [[ $pctSpaceUsed -gt $maxAllowedPctSpaceUsed ]]; then
	retval=1
else
	retval=0
fi

if [[ $pctInodesUsed -gt $maxAllowedPctInodesUsed ]]; then
	retval=1
fi

exit $retval





