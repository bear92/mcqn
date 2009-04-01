#!/usr/bin/perl -w
#
# Alertuino Informer
# (c) 2008 MCQN Ltd
#
# Basic script to search twitter looking for new updates and then send commands to
# an Alertuino connected

use LWP::UserAgent;
use HTTP::Request::Common;
use DateTime::Format::RSS;

# Serial port to talk to the Alertuino
$alertuino_port = "COM11:";
# Terms to search for.  This is just appended to the search string, so needs to be
# in the correct format.  Just pulled out to here for easy updating
$search_string = "%23alertuino+OR+%23barcampliverpool+OR+%23bcliverpool";

# Setup...
$last_seen_update = DateTime->now;
#$last_seen_update = DateTime->new( year => 2008, month => 12, day => 4, hour => 16, minute => 29, second => 57);
$ua = LWP::UserAgent->new;
$formatter = DateTime::Format::RSS->new;

# Just check for results forever...
while (1) {
	# Retrieve the latest search results
	print "Retrieving search results...\n";
	$response = $ua->request(GET "http://search.twitter.com/search.atom?q=$search_string");
	$new_update_count = 0;

	if ($response->is_success) {
		# To introduce some randomness into how often we check for new updates
		# we'll use the number of characters in the response for the time to
		# wait
		$update_pause = length($response->content) % 180 ;

		#print $response->content;
		#@update_times = grep /<published>.*<\/published>/, $response->content;

		# Pull out the published times, we don't care about anything else
		@update_times = grep /.*published.*/, split(/\n/, $response->content);
		#print $#update_times;
		#print @update_times;
		print "Checking for new updates:\n";
		foreach $update (@update_times) {
			($update_str) = $update =~ /<published>(.*)<\/published>/;
			$dt = $formatter->parse_datetime($update_str);
			#print "$update_str\n";	
			if (DateTime->compare_ignore_floating($dt, $last_seen_update) == 1) {
				$new_update_count++;
				print "New => $update_str\n";
			}
		}

		# Update the last_seen_update to the most recent item in the list
		($update_str) = $update_times[0] =~ /<published>(.*)<\/published/;
		$last_seen_update = $formatter->parse_datetime($update_str);
		print "New last seen: $update_str\n";

		# Now tell the Alertuino
		print "Found $new_update_count new updates.  Telling Alertuino\n";

		if (open(SERPORT, ">$alertuino_port")) {
			sleep(5);
			print SERPORT "$new_update_count\n";
			close(SERPORT);
		} else {
			print STDERR "Error opening serial port: $!\n";
		}	

		# And if we've got lots of updates, we should check again sooner
		$update_pause = $update_pause / ($new_update_count > 0 ? $new_update_count : 1);
	} else {
		print STDERR $response->status_line, "\n";
		# Default to once-a-minute if the request has failed
		$update_pause = 60;
	}

	# Wait for a while, use the number of characters in the response
	#print $update_pause;
	sleep($update_pause);
}

