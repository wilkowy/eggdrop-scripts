# Topic Resync & Recovery after a netsplit
# by wilk wilkowy

setudef flag topicresync

set topres_delay 10

#set topres_default(#channel) "Hello!"

bind rejn - * topres:check
bind topc o|o * topres:backup

proc topres:check {nick addr hand chan} {
	global topres_flag topres_delay
	if {![channel get $chan topicresync] || ![botisop $chan]} { return }
	if {![info exists topres_flag($chan)] || $topres_flag($chan) == 0} {
		set topres_flag($chan) 1
		timer $topres_delay [list topres:resync $chan]
	}
	return
}

proc topres:backup {nick host hand chan topic} {
	global topres_topic
	set topres_topic($chan) $topic
}

proc topres:resync {chan} {
	global topres_flag topres_topic topres_default
	if {![botisop $chan]} { return }
	set topic [topic $chan]
	if {$topic ne ""} {
		putlog "Topic resync ($chan): $topic"
		putserv "TOPIC $chan :$topic"
		set topres_topic($chan) $topic
	} elseif {[info exists topres_topic($chan)] && $topres_topic($chan) ne ""} {
		putlog "Topic recovery ($chan): $topres_topic($chan)"
		putserv "TOPIC $chan :$topres_topic($chan)"
	} elseif {[info exists topres_default($chan)] && $topres_default($chan) ne ""} {
		putlog "Topic default ($chan): $topres_default($chan)"
		putserv "TOPIC $chan :$topres_default($chan)"
		set topres_topic($chan) $topres_default($chan)
	}
	set topres_flag($chan) 0
}

putlog "Topic Resync v1.3 by wilk"
