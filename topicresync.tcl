# Name			Topic Resync & Recovery
# Author		wilk wilkowy
# Description	Resynchronize (or recover) channel topic after a netsplit
# Version		1.9 (2015..2021-06-27)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: topicresync

# Partyline commands: .topicresync
# .topicresync info		- display all topics
# .topicresync now		- resynchronize all topics
# .topicresync default	- set all topics to default topic is configured
# .topicresync <#>		- resynchronize topic of given channel

# Info:
# - bots/helpers are chosen randomly for each resync
# - if use_botnet is 1 then you need to have this script loaded on all bots and enabled for the same channels

# ToDo:
# - mode default_topic to setudef? (problem with colors)

namespace eval topicresync::c {

# Resync delay, in minutes. (0 - instant)
# Be advised that minute timers are peculiar in Eggdrop - they execute each full minute (:00) so 1 minute timer almost always executes in less than 60 seconds, in worst case it might be even 1 second. 15 minutes equals to 14-15 minutes, depending on when event occured.
variable resync_delay 30

# Sometimes splits can last longer than $wait-split value (DCTL). Such splits release nick/channel protections and due to $wait-split value Eggdrop consider missing users as lost in netsplit - their wasop expires and they won't trigger REJN event.
# However such users can still in fact be on a split (without being disconnected) and return minutes (or hours) later and topic resync won't be triggered.
# For IRCnet DCTL is 1800 seconds (30 minutes).
# Eggdrop suggests wait-split to be 1500 seconds (25 minutes).
# This value is a fail-safe and allows to resync topics in future when split occured but no one returned, in minutes. (0 - off)
variable overdue_split [expr {int(${wait-split} * 6 / 60.0)}]

# Protect against net-join floods, in seconds. (0 - off)
variable antiflood_delay 2

# Resync topic everywhere?
# 1: yes, unless topic was set by an @ before timer runs out
# 0: only on channels where someone netsplitted
variable resync_everywhere 1

# Default channel topics (lowercase channel names).
variable default_topic
#set default_topic(#channel) "Hello!"

# Set to 1 if you have a linked botnet so the bot to resync the topic will be rolled by a dice.
# This requires all bots to have topicresync.tcl loaded and +topicresync channel flag, otherwise put them in ignored_bots.
variable use_botnet 1

# This bots will be removed from dice roll if use_botnet == 1.
variable ignored_bots [list]

# Put here *handles* of other bots considered as master topic bouncers for this one, while any of them is present on channel with @ then this bot will not resync topic.
variable master_bots [list]

}

# #################################################################### #

namespace eval topicresync {

	variable version "1.9"
	variable changed "2021-06-27"
	variable author "wilk"

	namespace eval v {
		variable flood_gate
		variable topic_backup
		variable resync_chan
		variable resync_timer
		variable lostsplit_timer
	}

	proc on_dcc_cmd {hand idx text} {
		if {$text eq "info"} {
			show_info $idx
		} elseif {$text eq "now"} {
			resync_topic
		} elseif {$text eq "default"} {
			reset_topic
		} elseif {[validchan $text]} {
			set chans [channels]
			resync_topic [lindex $chans [lsearch -nocase -exact $chans $text]]
		} else {
			putdcc $idx "Usage: .topicresync <info/now/#/default>"
			return
		}
		return 1
	}

	proc on_split {nick uhost hand chan} {
		# SPLT -> REJN / SIGN
		set v::resync_chan($chan) 1
		set now [unixtime]
		if {[info exists v::flood_gate] && ($now - $v::flood_gate < $c::antiflood_delay)} { return }
		set v::flood_gate $now

		set ns [namespace current]
		kill_timer ${ns}::v::resync_timer
		kill_timer ${ns}::v::lostsplit_timer
		if {$c::overdue_split > 0} {
			set v::lostsplit_timer [timer $c::overdue_split ${ns}::resync_topic]
		}
	}

	proc on_rejoin {nick uhost hand chan} {
		set v::resync_chan($chan) 1
		set now [unixtime]
		if {[info exists v::flood_gate] && ($now - $v::flood_gate < $c::antiflood_delay)} { return }
		set v::flood_gate $now

		set ns [namespace current]
		kill_timer ${ns}::v::resync_timer
		kill_timer ${ns}::v::lostsplit_timer
		if {$c::resync_delay > 0} {
			set v::resync_timer [timer $c::resync_delay ${ns}::resync_topic]
		} else {
			resync_topic
		}
	}

	proc on_topic {nick uhost hand chan topic} {
		set v::topic_backup($chan) $topic
		set v::resync_chan($chan) 0
	}

	proc resync_topic {{chan ""}} {
		set ns [namespace current]
		# kill - because proc can be called from partyline as well
		kill_timer ${ns}::v::resync_timer
		unset -nocomplain v::resync_timer
		kill_timer ${ns}::v::lostsplit_timer
		unset -nocomplain v::lostsplit_timer

		if {$chan eq ""} {
			set chans [channels]
		} else {
			set chans [list $chan]
		}
		foreach chan $chans {
			if {![channel get $chan topicresync]} { continue }
			if {$c::resync_everywhere} {
				set resync 1
			} elseif {[info exists v::resync_chan($chan)]} {
				set resync $v::resync_chan($chan)
			} else {
				set resync 0
			}
			set v::resync_chan($chan) 0
			if {!$resync} { continue }

			set topic [topic $chan]
			set lchan [string tolower $chan]
			if {$topic ne ""} {
				set newtopic [set v::topic_backup($chan) $topic]
			} elseif {[info exists v::topic_backup($chan)] && $v::topic_backup($chan) ne ""} {
				set newtopic $v::topic_backup($chan)
			} elseif {[info exists c::default_topic($lchan)] && $c::default_topic($lchan) ne ""} {
				set newtopic [set v::topic_backup($chan) $c::default_topic($lchan)]
			} else {
				set newtopic ""
			}

			if {($c::use_botnet && ![myturn "topicresync$newtopic" $chan 1 1 $c::ignored_bots]) || (!$c::use_botnet && [chanhasop $chan $c::master_bots])} {
				continue
			}
			if {![botisop $chan]} {
				putlog "TopicResync: unable to resync topic - need ops ($chan)"
				continue
			}

			if {$newtopic ne ""} {
				settopic $chan $newtopic
				putlog "TopicResync: resynced topic on $chan"
			}
		}
	}

	proc reset_topic {} {
		set ns [namespace current]
		# kill - because proc can be called from partyline as well
		kill_timer ${ns}::v::resync_timer
		unset -nocomplain v::resync_timer
		kill_timer ${ns}::v::lostsplit_timer
		unset -nocomplain v::lostsplit_timer
		set chans [channels]
		foreach chan $chans {
			if {![channel get $chan topicresync]} { continue }
			if {![botisop $chan]} {
				putlog "TopicResync: unable to set default topic - need ops ($chan)"
				continue
			}
			set v::resync_chan($chan) 0
			set topic [topic $chan]
			set lchan [string tolower $chan]
			if {[info exists c::default_topic($lchan)] && $c::default_topic($lchan) ne $topic} {
				set newtopic [set v::topic_backup($chan) $c::default_topic($lchan)]
				if {$newtopic ne ""} {
					putlog "TopicResync: defaulting topic on $chan"
					settopic $chan $newtopic
				}
			}
		}
	}

	proc show_info {idx} {
		foreach chan [channels] {
			if {![channel get $chan topicresync]} {
				putdcc $idx "* Channel $chan: (resync disabled)"
			} elseif {[channel get $chan inactive]} {
				putdcc $idx "* Channel $chan: (inactive)"
			} elseif {![botonchan $chan]} {
				putdcc $idx "* Channel $chan: (not on channel)"
			} else {
				set info "* Channel $chan:"
				if {![botisop $chan]} {
					append info " (need ops)"
				}
				putdcc $idx $info
				set topic [convert_codes [topic $chan]]
				set length [format "%03d" [string length $topic]]
				putdcc $idx "| Topic (current) \[$length]: $topic"
				if {[info exists v::topic_backup($chan)]} {
					set btopic [convert_codes $v::topic_backup($chan)]
					if {$btopic ne $topic} {
						set length [format "%03d" [string length $btopic]]
						putdcc $idx "| Topic (backup)  \[$length]: $btopic"
					}
				}
				set lchan [string tolower $chan]
				if {[info exists c::default_topic($lchan)]} {
					set dtopic [convert_codes $c::default_topic($lchan)]
					#if {$dtopic ne $topic} {
						set length [format "%03d" [string length $dtopic]]
						putdcc $idx "| Topic (default) \[$length]: $dtopic"
					#}
				}
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

		setudef flag topicresync

		bind splt - * ${ns}::on_split
		bind rejn - * ${ns}::on_rejoin

		bind topc o|o * ${ns}::on_topic

		bind dcc n|- topicresync ${ns}::on_dcc_cmd

		putlog "TopicResync v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind splt - * ${ns}::on_split }
		catch { unbind rejn - * ${ns}::on_rejoin }
		catch { unbind topc o|o * ${ns}::on_topic }
		catch { unbind dcc n|- topicresync ${ns}::on_dcc_cmd }

		kill_timer ${ns}::v::resync_timer
		kill_timer ${ns}::v::lostsplit_timer

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag topicresync
	}

	init
}
