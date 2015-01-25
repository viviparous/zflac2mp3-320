#!usr/bin/perl -w

=pod
2015 viviparous

Convert flac files to mp3 for transfer to mp3 player. Intended to be easy to use. 

Creates a time-stamped output directory with no subdirectories.

Copies flac files from source to destination before conversion begins. 

Uses ffmpeg or avconv. Dependencies must be installed.

Arguments are passed as KEY1=VALUE1 KEY2=VALUE2 and so on.

Step 1: flac files in dir structure D are copied to new working dir DN. Subdirectories of D will be scanned. 
The subdirectory structure of D is *not* recreated. 

Step 2: conversion is accomplished using forks (settable).

Step 3: after completion, flac files are deleted from DN. 

=cut

use strict;
use warnings;
use File::Find;
use File::Path;
use File::Copy;
use IPC::System::Simple qw(system systemx capture capturex);
#use Capture::Tiny; #to do
use Parallel::ForkManager;

#================== I N I T ====================
#===============================================



my %argHash=(searchdir=>1, threads=>1 , cvnmode=>1 , cvndirlabel=>0); #todo: optional=>0
my @requiredArgs = 	grep { $argHash{$_} eq 1 } keys %argHash;

if ( scalar(@ARGV) < scalar(@requiredArgs) ) {
	&showRequiredParms;
	doInfoMsg("Possible parameters: " . join (" , " , keys %argHash ) );
	doErrorExit("Problem with parameters. Found ". scalar(@ARGV)  ) ;
}

my @checkedArgs=();
for my $aarg (@ARGV ){
	my ($k,$v)=split('=',$aarg); doInfoMsg("Input $aarg, $k => $v"); 
	if ( exists $argHash{$k} ) { 
		push @checkedArgs , $k;
		$argHash{ $k }=$v; 
	}
} 

my $errstate=0;
my %hGivenArgs = map { $_ => $_ } @checkedArgs;
for my $rqarg (@requiredArgs) {
	if ( ! exists $hGivenArgs{$rqarg} ) {  $errstate++ ; } 
}
if( $errstate > 0) {
	&showRequiredParms;
	doErrorExit("Problem with parameters") if ( scalar(keys %argHash) != scalar(@ARGV) ) ;
}

if( $argHash{threads} =~ /\D/ || $argHash{threads} > &get_cpu_cores ) { 
	doInfoMsg("Using CPU core count instead of " . $argHash{threads} ); 
	$argHash{threads} = &get_cpu_cores; 
}
if( $argHash{cvndirlabel} =~ /\s/ ) { $argHash{cvndirlabel} =~ s/\s//g; }

&main;

exit(0); 






#================== S U B S ====================
#===============================================
sub main {

		my @filelist=findFilesInDirWithExt( $argHash{searchdir} , "flac" );
		print join(' , ', @filelist);
		doInfoMsg(scalar(@filelist)." files found");#to do: enforce unique

		my @arfspartitions = partitionArray( \@filelist , $argHash{threads} );

		for my $ar (@arfspartitions) {
			doInfoMsg("Partition size: ". scalar(@$ar));
		}


		my $newdir = &mknewhexdirName ; 
		mkdir $newdir;

		doErrorExit("$newdir doesn't exist") if (! -e $newdir);

		#doDbgExit(__LINE__);

		my $pm = Parallel::ForkManager->new($argHash{threads});

		TASKSCOPY:
		  foreach my $aref (@arfspartitions) {
			$pm->start and next TASKSCOPY; # do the fork

				for my $fn (@$aref) {
					if( -f $fn) {
						doInfoMsg("$$ Copy file $fn to dir $newdir");
						my @pathSegments = split(/\//,$fn);
						my $targetDir=$newdir;
						my $dupcount=1;
						my $undupname=$pathSegments[$#pathSegments];
						while( -e $targetDir."/". $undupname ) {
							doInfoMsg('*'x10 . "\nHandling file-name conflict: $undupname\n". '*'x10 ."\n");
							$undupname = $dupcount."_".$undupname;							
						}
						$targetDir=$targetDir."/". $undupname; 
						copy( $fn , $targetDir) or die "Copy failed: $!";
					}
				} 

			$pm->finish; # do the exit in the child process
		  }
		$pm->wait_all_children;



		my @wfflac=findFilesInDirWithExt( $newdir , "flac" );
		doInfoMsg(scalar(@wfflac)." files in $newdir");

		my @encodepartitions = partitionArray( \@wfflac , $argHash{threads} );

		doInfoMsg("Copied ". scalar(@wfflac) );

		TASKSMP3:
		  foreach my $aref (@encodepartitions) {
			$pm->start and next TASKSMP3; # do the fork

				for my $fn (@$aref) {
					if( -f $fn) {
						doInfoMsg("$$ encode $fn");
						my $cvncmd="ffmpeg -i $fn -acodec libmp3lame -ab 320k $fn.mp3";
						$cvncmd="avconv -i $fn -c:a libmp3lame -b:a 320k $fn.mp3" if ( $argHash{cvnmode} eq "avconv" );
						system($cvncmd);
					}
				} 	

			$pm->finish; # do the exit in the child process
		  }
		$pm->wait_all_children;

		doInfoMsg(__LINE__." All processing complete.");
		@wfflac=findFilesInDirWithExt( $newdir , "flac" );
		doInfoMsg(scalar(@wfflac)." FLAC files in $newdir. Delete FLACs...");

		for my $flacfn (@wfflac) { 
			print "."; 
			unlink($flacfn) or warn "Could not unlink $flacfn: $!"; 
		}
		@wfflac=findFilesInDirWithExt( $newdir , "flac" );
		doInfoMsg("Now " . scalar(@wfflac)." FLAC files in $newdir");

		print "\nDone!\n";
		
		return;

}

sub doMsg { my $m=shift; print "$m\n"; return; }
sub doInfoMsg { my $m=shift; doMsg("INFO: $m"); }
sub doWarningMsg { my $m=shift; doMsg("\n\n" . 'x'x30 . "\n\nWARNING: $m\n\n" . 'x'x30 . "\n"); sleep 30; }
sub doErrorExit { my $m=shift; doMsg("EXIT, ERROR: $m"); exit(0);}
sub doDbgExit { my $m=shift; doMsg("EXIT, DBG: $m"); exit(0);}
sub showRequiredParms {
	doInfoMsg("Required parameters: " . join(' , ', @requiredArgs) );	
}
sub mknewhexdirName {
	my $hssm = dec2hex(&seconds_since_midnight);
	my $datecmd = "+\"%Y-%m-%d_\"";
	my $newdir=capture("date", $datecmd);
	chomp($newdir); #avoid newline
	$newdir=~s/\"//g;
	$newdir=$newdir . $hssm; 
	$newdir= $newdir."_".$argHash{cvndirlabel} if ( length($argHash{cvndirlabel})>0 ); 	
	return $newdir;
}
sub findFilesInDirWithExt {
	my ($dirname , $ext )= @_;
	my @filelist=();
	find(sub { push @filelist, $File::Find::name if( -f $_ && $_ =~ /\.$ext$/ ) }, $dirname);
	return @filelist;
}
sub partitionArray{
	my ($aref , $splits) = @_;
	my @rv_arefs=();
	if( scalar(@$aref) == 0 ) { return \@rv_arefs; }
	elsif( $splits <= 1 || $splits > scalar(@$aref) ) { push @rv_arefs, $aref; return \@rv_arefs; }
		
	my $splitval = ( scalar(@$aref)-(scalar(@$aref)%$splits) ) / $splits;	
	while ( scalar(@$aref) > $splits ) {
			my @a1=splice @$aref, 0 , $splitval;
			push @a1, $aref if( scalar(@$aref) > 0 && scalar(@$aref) < $splits );
			push @rv_arefs, \@a1;			
	}
	return @rv_arefs;
}
sub dec2hex { my $d=shift; return sprintf( "%x" , $d ); }

sub seconds_since_midnight { 
	my @time = localtime(); 
	my $secs = ($time[2] * 3600) + ($time[1] * 60) + $time[0]; 
	return $secs; 
}
sub idOS { return $^O;}

sub get_cpu_cores {
	my $n = -1; 
	if (-e "/proc/cpuinfo") {
		if(&idOS eq "cygwin") {
			my $c = qx( cat /proc/cpuinfo | grep -cP "processor\\s+:" );
			chomp($c);
			$n=$c;
		}
		else {
			my $c = capture("cat /proc/cpuinfo | grep -i \"cpu cores\" ");
						
			my @lines = split("\n",$c);
			for my $L (@lines) {  
				if( $L=~ /^cpu cores\s*:\s(\d+)$/ ){ $n=$1; last;} 
			}
	
		}
	}
 return $n >= 1 ? $n : 1;
}


