# Name			Topic Update
# Author		wilk wilkowy
# Description	Update topic events: date->tomorrow->today
# Version		1.7 (2015..2019-12-13)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: topicupdate

# Partyline commands: .topicupdate
# .topicupdate info		- display all topics
# .topicupdate now		- update all topics

# ToDo:
# - too many hardcoded strings

namespace eval topicupdate::c {

# Topic update hour (keep leading zero; format is: MM HH).
# Was "00 02", but DST would break this event.
variable update_hour "59 01"

}

# #################################################################### #

namespace eval topicupdate {

	variable version "1.7"
	variable changed "2019-12-13"
	variable author "wilk"

	proc on_dcc_cmd {hand idx text} {
		if {$text eq "info"} {
			show_info $idx
		} elseif {$text eq "now"} {
			on_time_update 0 0 0 0 0
		} else {
			putdcc $idx "Usage: .topicupdate <info/now>"
			return
		}
		return 1
	}

	proc on_time_update {minute hour day month year} {
		set now_day [strftime "%-d"]
		set now_month [strftime "%-m"]

		foreach chan [channels] {
			if {![channel get $chan topicupdate]} { continue }

			if {![botisop $chan]} {
				putlog "TopicUpdate: unable to update - need ops ($chan)"
				continue
			}

			set topic [topic $chan]
			if {$topic eq ""} { continue }
			set oldtopic $topic

			set update 0
			if {[string match -nocase "*jutro*" $topic]} {
				set topic [string map -nocase {"JUTRO" "DZIŚ"} $topic]
				regsub -all -nocase "\0030?3((?:Nast|Next|Quiz)\[^:\]*?: DZIŚ )" $topic "\0034\\1" topic
				incr update
			}

			set matches [regexp -all -inline -nocase {(?:(?:\mwe? )?(?:poniedzia[lł]ek|po?n\.|wtorek|wto?\.|[sś]rod[aeę]|[sś]ro?\.|czwartek|czw\.|pi[aą]tek|pi[aą]t?\.|pt\.|sobot[aeę]|sob\.|niedziel[aeę]|nie\.|niedz\.) )?\(([0-3]?[0-9])[./]([01]?[0-9])\)} $topic]
			foreach {match event_day event_month} $matches {
				set event_day [scan $event_day "%d"]
				set event_month [scan $event_month "%d"]
				set prev_day [expr {$event_day - 1}]
				set prev_month $event_month
				set prev_year [strftime "%Y"]

				if {$prev_day == 0} {
					incr prev_month -1
					if {$prev_month == 0} {
						set prev_month 12
						incr prev_year -1
					}
					if {$prev_month == 2} {
						set prev_day 28
						if {($prev_year % 4 == 0 && $prev_year % 100 != 0) || $prev_year % 400 == 0} {
							incr prev_day 1
						}
					} elseif {$prev_month in [list 1 3 5 7 8 10 12]} {
						set prev_day 31
					} else {
						set prev_day 30
					}
				}

				set soon ""
				if {$now_day == $prev_day && $now_month == $prev_month} {
					set soon "JUTRO"
				} elseif {$now_day == $event_day && $now_month == $event_month} {
					set soon "DZIŚ"
				}
				if {$soon ne ""} {
					set topic [string map -nocase [list $match $soon] $topic]
					regsub -nocase "\0030?3((?:Nast|Next|Quiz)\[^:\]*?: )" $topic "\0034\\1" topic
					incr update
				}
			}

			if {$update} {
				putlog "TopicUpdate: $chan from > $oldtopic"
				putlog "TopicUpdate: $chan to   > $topic"
				settopic $chan $topic
			}
		}
	}

	proc show_info {idx} {
		foreach chan [channels] {
			if {![channel get $chan topicupdate]} {
				putdcc $idx "* Channel $chan: (update disabled)"
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
				putdcc $idx "| Topic \[$length]: $topic"
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

		setudef flag topicupdate

		bind time - "$c::update_hour *" ${ns}::on_time_update

		bind dcc n|- topicupdate ${ns}::on_dcc_cmd

		putlog "TopicUpdate v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind time - "$c::update_hour *" ${ns}::on_time_update }
		catch { unbind dcc n|- topicupdate ${ns}::on_dcc_cmd }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag topicupdate
	}

	init
}
