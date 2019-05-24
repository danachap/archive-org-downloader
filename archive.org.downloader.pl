#!/usr/bin/perl
	
# download mp3 files from archive.org by parsing the m3u playlist file embedded in the concert page
#
use URI;

$outputdir = ".";
@orphanfiles;  # array to hold files not automatically moved via id3 tags
$useragent="iTunes/9.1.1"; # fly under the radar with fake user agent string
$outputfolder = ""; # the subdirectory to put files into

# get show url from command line or user input
if (!($ARGV[0]))
{
	print "Enter archive.org show URL:  ";
	$url = <STDIN>;
	# die "Error:  No show URL specified on command line.\n";
}
else
{
	$url=$ARGV[0];	
}
chomp($url);
chdir $outputdir || die "Cannot change working directory to $outputdir\n$!";	# set cwd

# parse url parts from url we passed in via command line in case we need to build absolute urls from relative links later on
my $clurl = URI->new( $url );
my $domain = $clurl->host;
my $scheme = $clurl->scheme;
my $path = $clurl->path;
my $url_filename = ($clurl->path_segments)[-1];

# parse show's html source and isolate line containing link to m3u playlist file(s)
print "Looking for .m3u references in the raw HTML...\n";
$command = "curl --silent --user-agent '$useragent' $url";
@html = readpipe $command;

foreach $line (@html)
{
	# print "$line";
	if ($line =~ /\/download\/.*m3u/)
	{
		$m3uline=$line;
		print "Found .m3u line...\n";
		last;
	}
}

# next, check to ensure an m3u playlist was found in the html source
if ($m3uline eq "")
{
	print "\n\n*************************************\n";
	print "No .m3u playlist found at $url\nExiting\n\n";
	exit(1);
}
	
# if we get here, we're good to go.  now, in case there are multiple .m3u files referenced in the same
# line of HTML (such as vbr (hi-fi) and 64kbps (lo-fi), etc) let's make sure we parse out the highest
# quality one, which in the case of the archive.org site, is typically the VBR version
@m3u_versions;  # array to hold refs to all m3u files contained in the m3uline 
@bestm3u = split("\"",$m3uline);  # break html line into parsable chunks
print "Determining highest bitrate M3U file to use...\n";
foreach $line (@bestm3u)
{
	# print "m3uversion:\t$line\n";
	if ($line =~ /(http[s]{0,1}:\/\/){0,1}(.*\/download\/.*m3u)/)
	{
		print "Candidate .m3u:\t$line\n";
		push(@m3u_versions, $line);
	}
}

$bestm3uversion = "";
foreach $version (@m3u_versions) {
	# print "version:\t$version\n";
	if ($version =~ /vbr/) {
		$bestm3uversion = $version;
		last; # use this format if available
	}
	$bestm3uversion = $version;	# otherwise...
}
print "Determined optimal M3U:\t$bestm3uversion\n";

# make this an absolute URL, if required.  some archive.org urls are relative links
if (!($bestm3uversion =~ /^http/))
{
	# this is a relative url, make it absolute
	$absolute = $scheme . "://" . $domain . $bestm3uversion;
	$bestm3uversion = $absolute;
	print "Converted to absolute URL: $bestm3uversion\n";
}


# now, decide to download .m3u playlist, or actually download all of the mp3s
print "\nChoose download option\n";
print "  1 = Download .m3u playlist\n";
print "  2 = Download mp3s\n";
print "  0 = Cancel\n";
$op = <STDIN>;
chomp($op);

if ($op == 1)
{
  # download m3u only
  system("curl --silent --user-agent '$useragent' --location $bestm3uversion --output \"./${url_filename}.m3u\"");
  print "\n\n*************************************\n";
  print "Download of ${url_filename}.m3u complete.\n";
  print "Happy Listening!\n\n";
  exit(0);
}
elsif ($op != 2)
{
  print "Exiting\n\n";
  exit(0);
}


# finally, read each individual URL listed in the best m3u playlist file
# and download it.  note the use of the --location switch to deal with http 302 redirects
$command = "curl --silent --user-agent '$useragent' --location $bestm3uversion";

@songs = readpipe $command;
$num_songs = scalar @songs;	# how many songs to download?
$songcount=0;			# current song counter

foreach $song (@songs) {
	if ($song =~ /(^http:\/\/.*archive\.org\/.*\/)(.*mp3)$/) {
		$songcount++;
		$path=$1;
		$song=$2;
		$fullurl=$path.$song;
		print "Start Downloading $song (Track $songcount of $num_songs)\n";
		print "Full URL: $fullurl\n";
		system("curl --user-agent '$useragent' --progress-bar --location --output $song --url $fullurl");
		print "Finished downloading $song\n\n";
		# renameFileFromID3Tags($song, $songcount);
	}
}

# cleanup - move any orphan files into the output folder
if ($outputfolder != "") {
	foreach $file (@orphanfiles) {
		$filenew = $outputfolder . "/" . $file;
		rename($file, $filenew) || warn "Can't move file $file\n";
	}
}

# print summary
print "\n\n*************************************\n";
print "Bulk download complete.\nDownloaded $songcount tracks to ${outputdir}/${outputfolder}\n";
print "Happy Listening!\n\n";

exit(0);



############################ subroutines ############################
sub renameFileFromID3Tags {
	$filename = $_[0];
	$songcount = $_[1];

	if (length $songcount == 1) {
		$songcount = "0" . $songcount;
	}


	# for GD tracks, archive.org uses the d##t## filename convention for disk/track numbering.  keep it
	$dt = "";
	if ($filename =~ /d\d+t\d+/) {
		$dt = "-" . $& ."-";
	}

	# create new MP3-Tag object and get tag info
	$mp3 = MP3::Tag->new($filename);
	$mp3->get_tags();

	# check to see if ID3v1 tag exists
	if (exists $mp3->{ID3v1}) {
   		$artist = $mp3->{ID3v1}->artist;
		$title = $mp3->{ID3v1}->title;
		$album = $mp3->{ID3v1}->album;

		# use the first discovered album id3 tag as the folder name
		if ($outputfolder == "") {
			$outputfolder = $album;
		}

		# make a directory based on the album name
		if (! -d $outputfolder) {
			mkdir $outputfolder || die "Can't make directory $outputfolder.  $!\n";
		}

		$filename_new = "${songcount}-${artist}-${album}-${title}${dt}.mp3";
		$filename_new =~ s/\s/_/g;
		$filename_new = $outputfolder . "/" . $filename_new;
 
		# rename($song, $filename_new) || warn "Error renaming file: $!\n";
		rename($song, $filename_new) || warn "Error renaming/moving file: $!\n";
	} else {
		# keep track of files without id3 tag info
		push(@orphanfiles, $filename_new);
	}
	$mp3->close();
}
