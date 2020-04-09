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
use Pod::Usage;

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
	"h|help!" => sub { pod2usage( -verbose => 1 ) },
	"m|man!" => sub { pod2usage( -verbose => 2 ) },
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
	pdebug("user $username is allowed to reboot");
}


if ($rebootCmd and ! validateCmd("$rebootCmd") ) {
	print "command: $rebootCmd\n";
	die "that is an invalid cmd\n";
}


if ($allowReboot) {
	 pdebug("configuring to allow reboot");
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
} elsif ($eraseReboot) {
	remove();
	exit;
} else {
	print "Unknown State\n";
	exit 44;
}


############################
# subroutines
############################


sub pdebug {

	print join(' ', @_) . "\n" if $debug;
	return;
}

sub createDirs {
	foreach my $dir ( @runDirs ) {
		pdebug("mkdir: $dir");
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
	pdebug("inside writeDirective()");
	pdebug( '@runDirs: ', Dumper(\@runDirs));
	foreach my $dir ( @runDirs ) {
		my $fh = IO::File->new;
		my $outFile="${dir}/${runFile}";
		pdebug("outFile: $outFile");
		$fh->open($outFile,'>') or die "could not open $outFile - $!\n";
		$fh->print($directives{$directive});
	}
}

sub removeDirectives {
	foreach my $dir ( @runDirs ) {
		my $filename="${dir}/${runFile}";
		pdebug("filename $filename");
		unlink ($filename);
	}
}

sub reject {
	createDirs();
	writeDirective('reject');
}

sub allow {
	pdebug("inside allow()");
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

	pdebug('@rawLines ' . Dumper(\@rawLines));

	my @lines=grep(/^check:/,@rawLines);

	pdebug('@lines ' . Dumper(\@lines));

	my @checks=();;
	foreach my $line (@lines) {
		my ($dummy,$check) = split(/:/,$line);
		push @checks, $check;
	}

	pdebug('@checks: ' . Dumper(\@checks));

	return @checks;

}

sub reboot {

	my ($checksArrayRef,$rebootCmd) = @_;

	foreach my $chkCmd (@{$checksArrayRef}) {
		pdebug("reboot:chkCmd: $chkCmd");
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



sub createService {

	my $serviceFile = qq{${service{dir}}/${service{name}}};	
	if (-f $serviceFile ) {
		warn "cowardly refusing to overwrite: $serviceFile\n";
		return;
	}

	my $fh = IO::File->new;
	$fh->open($serviceFile,'>') or die "could not create $serviceFile - $!\n";
	print $fh $service{text};
	$fh->close;

	chmod 0664, $serviceFile;

	system("/usr/bin/systemctl enable $service{name}"); # or die "failed to start service $service{name} - $!\n";
	return;
}

sub removeService {

	my $serviceFile = qq{${service{dir}}/${service{name}}};	

	chmod 0664, $serviceFile;

	system("/usr/bin/systemctl disable $service{name}"); # or die "failed to disable service $service{name} - $!\n";
	unlink ($serviceFile);
	return;

}

sub getCheckScript {
	my $checkBootFile = "${rootBin}/${chkBootScript}";
	if (-f $checkBootFile ) {
		warn "cowardly refusing to overwrite: $checkBootFile\n";
		return;
	}
	my $fh = IO::File->new;
	$fh->open($checkBootFile,'>') or die "could not create $checkBootFile - $!\n";
	while (<DATA>) {
		print $fh $_;
	}
	$fh->close;
	chmod 0750, $checkBootFile;
}

sub removeCheckScript {
	my $checkBootFile = "${rootBin}/${chkBootScript}";
	unlink ($checkBootFile);
	return;
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
	unlink $fpConfigFile;
	pdebug("removeConfig: removing $fpConfigFile");
	my $fpConfigDir=qq[${homeDir}/${configDir}];
	rmdir $fpConfigDir;
	return;
}

sub install  {
	pdebug("\ninstall: calling getCheckScript");
	getCheckScript();
	pdebug("\ninstall: calling createConfig");
	createConfig();
	pdebug("\ninstall: calling createService");
	createService();
}


sub remove {
	pdebug("\nremove: calling removeCheckScript");
	removeCheckScript();
	pdebug("\nremove: calling removeConfig");
	removeConfig();
	pdebug("\nremove: calling removeService");
	removeService();
	pdebug("\nremove: calling removeDirective");
	removeDirectives();
}


=head1 NAME

F<reboot-abort.pl>

=head1 VERSION

Version 0.1

=head1 DESCRIPTION

Control Linux Reboots and Shutdowns

=head1 SYNOPSIS

    reboot-abort.pl --reject

=head1 OPTIONS

=over

=item -r | --reject

 Do not allow reboots directly via reboot, shutdonw or halt.

=item -a | --allow

 Allow reboots directly via reboot, shutdonw or halt.

=item -i | --install

 Install the reboot-abort.files and service.

=item -e | --erase

 Remove the reboot-abort.files and service.

=item -d | --debug

 Prints messages on stdout

=item -h | --help

 Print options help

=item -m | --man

 Print extended help

=item -c | --cmd | --command

 Issue a command to restart the server.

 The command will  fail to execute if:

 - the command does not start with shutdown|reboot|halt
 - more than 1 command is issued
 - one of the check scripts from ~/.reboot-abort/checks.conf returns false

=back

=head1 CHANGE HISTORY

=head2 2020-04-08: Jared Still

Script creation.

=head1 AUTHOR

Jared Still, <still@pythian.com> <jkstill@gmail.com>

=cut

# end of program

__DATA__
#!/usr/bin/env bash

declare fsName='/boot'

declare maxAllowedPctSpaceUsed=85
declare maxAllowedPctInodesUsed=85

declare pctSpaceUsed
declare pctInodesUsed


pctSpaceUsed=$(/bin/df --output=pcent $fsName| /usr/bin/tail -n -1 | /bin/sed -r -e 's/[ %]//g')
pctInodesUsed=$(/bin/df --output=ipcent $fsName| /usr/bin/tail -n -1 | /bin/sed -r -e 's/[ %]//g')

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

