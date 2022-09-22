# Name			JoinMsg
# Author		wilk wilkowy
# Description	Sends message to users joining a channel
# Version		1.1 (2018..2019-04-25)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: joinmsg

namespace eval joinmsg::c {

# Users having such flags are ignored and receive no invitation message. (use "" to disable)
variable ignored_users "I|I"

# Protect against join floods, in seconds. (0 - off)
variable antiflood_delay 2

# Messages sent to joining users. Chosen randomly from list. Use *lowercase* channel names, nicks, handles and hosts!
# Available placeholders: #NICK#, #HAND#, #CHAN#
# Three types of messages are supported:
# message(chan,&handle) [list "..."]	- this is sent to joining user recognized for this handle
# message(chan,nick) [list "..."]		- this is sent to joining user with this nick
# message(chan) [list "..."]			- this is default greeting message (sent if none of above were found)
variable message
#set message(#...) [list "..."]

}

# #################################################################### #

namespace eval joinmsg {

	variable version "1.1"
	variable changed "2019-04-25"
	variable author "wilk"

	namespace eval v {
		variable flood_gate
	}

	proc on_join {nick uhost hand chan} {
		set now [unixtime]
		if {![channel get $chan joinmsg] ||
			($c::ignored_users ne "" && [matchattr $hand $c::ignored_users $chan]) ||
			([info exists v::flood_gate($chan)] && ($now - $v::flood_gate($chan) < $c::antiflood_delay))} { return }
		set v::flood_gate($chan) $now

		set lchan [string tolower $chan]
		set lnick [string tolower $nick]
		set lhand [string tolower $hand]
		if {$hand ne "" && $hand ne "*" && [info exists c::message($lchan,&$lhand)] && [llength $c::message($lchan,&$lhand)] > 0} {
			set msg [lrandom $c::message($lchan,&$lhand)]
		} elseif {[info exists c::message($lchan,$lnick)] && [llength $c::message($lchan,$lnick)] > 0} {
			set msg [lrandom $c::message($lchan,$lnick)]
		} elseif {[info exists c::message($lchan)] && [llength $c::message($lchan)] > 0} {
			set msg [lrandom $c::message($lchan)]
		} else {
			return
		}

		if {$msg ne ""} {
			putlog "JoinMsg: on-join message for $nick ($hand) on $chan"
			sendmsg $chan [string map [list "#NICK#" $nick "#HAND#" $hand "#CHAN#" $chan] $msg]
		}
	}

# -=-=-=-=-=-

	proc init {} {
		variable version; variable author
		set ns [namespace current]

		if {![info exists ::wilk::version]} {
			uplevel #0 source [file dirname [info script]]/wilk.tcl
		}
		namespace import ::wilk::*
		::wilk::register $ns

		setudef flag joinmsg

		bind join - * ${ns}::on_join

		putlog "JoinMsg v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind join - * ${ns}::on_join }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag joinmsg
	}

	init
}
