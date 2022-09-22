# Name			Topic Lock
# Author		wilk wilkowy
# Description	Prevents topic changes by unpriviledged users
# Version		1.0 (2021..2021-06-27)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: topiclock

# Info:
# - linked bots are allowed to change topic
# - bots/helpers are chosen randomly for each topic bounce
# - if use_botnet is 1 then you need to have this script loaded on all bots and enabled for the same channels

namespace eval topiclock::c {

# Users having such flags can change topic. (use "" to disable)
variable ignored_users "m|n"

# Set to 1 if you have a linked botnet so the bot to fix the topic will be rolled by a dice.
# This requires all bots to have topiclock.tcl loaded and +topiclock channel flag, otherwise put them in ignored_bots.
variable use_botnet 1

# This bots will be removed from dice roll if use_botnet == 1.
variable ignored_bots [list]

# Put here *handles* of other bots considered as master topic bouncers for this one, while any of them is present on channel with @ then this bot will not recover changed topic.
variable master_bots [list]

}

# #################################################################### #

namespace eval topiclock {

	variable version "1.0"
	variable changed "2021-06-27"
	variable author "wilk"

	namespace eval v {
		variable topic
	}

	proc on_topic {nick uhost hand chan topic} {
		if {![channel get $chan topiclock]} { return }

		if {![info exists v::topic($chan)] ||
			$nick eq "*" ||
			[isbotnick $nick] ||
			($c::ignored_users ne "" && [matchattr $hand $c::ignored_users $chan]) ||
			([matchattr $hand "b" $chan] && [islinked $nick])
		} then {
			set v::topic($chan) $topic
			return
		}

		if {$topic ne $v::topic($chan) &&
			(($c::use_botnet && [myturn "topiclock$nick$uhost$hand$topic" $chan 1 1 $c::ignored_bots]) ||
			(!$c::use_botnet && ![chanhasop $chan $c::master_bots]))
		} then {
			if {[botisop $chan]} {
				settopic $chan $v::topic($chan)
				putlog "TopicLock: protected topic on $chan changed by $nick ($hand)"
			} else {
				putlog "TopicLock: unable to protect topic - need ops ($chan)"
			}
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

		setudef flag topiclock

		bind topc - * ${ns}::on_topic

		putlog "TopicLock v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind topc - * ${ns}::on_topic }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag topiclock
	}

	init
}
